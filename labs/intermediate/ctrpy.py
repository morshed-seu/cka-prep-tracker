#!/usr/bin/env python3
"""ctrpy.py — do `ctr run`'s whole job from Python, one step at a time.

This is the I7.17 mini project. It pulls an image from the I5 local registry,
prepares a snapshot, reads the image config the way I4's oci-inspect.py did,
creates a container and a task, starts it, streams its output, waits for the
exit code, and then deletes every object it made — the same sequence `ctr run`
performs in one call, unrolled so you can see each API call.

WHY IT SHELLS OUT TO `ctr`
--------------------------
containerd's real API is gRPC over /run/containerd/containerd.sock. There is
no maintained pure-Python client for it, and hand-rolling ttrpc/gRPC against
the containerd .proto files is a project in itself — well beyond the point of
this exercise, which is to make the *sequence of operations* explicit. So each
step shells out to `ctr` and NAMES, in a comment, the Go client method it is
standing in for (from github.com/containerd/containerd/v2/client). If you ever
write the real thing in Go, this file is your call list.

Run it on `sandbox`, where containerd 2.3.3 and the I5 registry live:

    python3 ctrpy.py 127.0.0.1:5000/demo/tiny:v1
    python3 ctrpy.py                       # defaults to that image

Everything it creates is namespaced under `ctrpy` and removed on exit, so it
leaves the box exactly as it found it.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time

NAMESPACE = "ctrpy"          # our own containerd namespace, cleaned up at the end
CONTAINER = "ctrpy-demo"     # container id (also the active snapshot key)
SNAPKEY = "ctrpy-demo"       # snapshot key we prepare for the rootfs
DEFAULT_IMAGE = "127.0.0.1:5000/demo/tiny:v1"


def ctr(*args: str, ns: bool = True, check: bool = True,
        capture: bool = True) -> subprocess.CompletedProcess:
    """Run `sudo ctr [-n NAMESPACE] ARGS...`.

    Every call in this file goes through here so the namespace and sudo are in
    one place. Returns the CompletedProcess; set capture=False to let output go
    straight to the terminal (used when we stream the task).
    """
    cmd = ["sudo", "ctr"]
    if ns:
        cmd += ["-n", NAMESPACE]
    cmd += list(args)
    return subprocess.run(
        cmd, check=check,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        text=True,
    )


def step(n: int, msg: str) -> None:
    # flush so our step labels interleave correctly with the child processes'
    # own stdout (the task's output streams straight through, uncaptured).
    print(f"\n[{n}] {msg}", flush=True)


def pull(image: str) -> None:
    """Stands in for: client.Pull(ctx, ref, client.WithPullUnpack).

    Pull fetches the manifest, config and layers into the content store and —
    because of WithPullUnpack — also asks the snapshotter to unpack the layers
    into committed snapshots. Without unpack you would have the bytes but no
    mountable rootfs, which is the difference between I7.9 and I7.10.
    """
    step(1, f"pull {image} (content store + unpack into snapshots)")
    ctr("images", "pull", "--plain-http", image, capture=False)


def read_config(image: str) -> dict:
    """Stands in for: image.Config(ctx) then reading the config blob.

    This is I4's parser again: resolve the image to its config descriptor with
    `ctr image ...`, then pull that blob out of the content store and load it.
    We only need Env, Entrypoint/Cmd and WorkingDir to build the task's process.
    """
    step(2, "read the image config from the content store (reuse of I4)")
    # Walk the graph exactly as I4's oci-inspect.py did: the image's target
    # descriptor -> (index ->) manifest -> config, each fetched as a blob with
    # `ctr content get`. This is the whole of I4 and I7.7, reused.
    idx_digest = _image_target_digest(image)
    blob = json.loads(ctr("content", "get", idx_digest).stdout)
    manifest_digest = _pick_amd64_manifest(blob, idx_digest)
    manifest = json.loads(ctr("content", "get", manifest_digest).stdout)
    config_digest = manifest["config"]["digest"]
    config = json.loads(ctr("content", "get", config_digest).stdout)
    proc = config.get("config", {})
    print(f"    Entrypoint={proc.get('Entrypoint')}  Cmd={proc.get('Cmd')}")
    print(f"    Env has {len(proc.get('Env', []))} entries, WorkingDir={proc.get('WorkingDir') or '/'}")
    return config


def _image_target_digest(image: str) -> str:
    for line in ctr("images", "ls").stdout.splitlines():
        if line.startswith(image + " ") or f" {image} " in f" {line} ":
            parts = line.split()
            for p in parts:
                if p.startswith("sha256:"):
                    return p
    raise SystemExit(f"image {image} not found after pull")


def _pick_amd64_manifest(blob: dict, self_digest: str) -> str:
    # A single-arch push (our I5 tiny:v1) has no index — it *is* the manifest.
    if blob.get("mediaType", "").endswith("manifest.v1+json"):
        return self_digest
    for m in blob.get("manifests", []):
        plat = m.get("platform", {})
        if plat.get("architecture") == "amd64" and plat.get("os") == "linux":
            return m["digest"]
    raise SystemExit("no linux/amd64 manifest in index")


def create_container(image: str, config: dict) -> None:
    """Stands in for: client.NewContainer(ctx, id,
        containerd.WithNewSnapshot(key, image),
        containerd.WithNewSpec(oci.WithImageConfig(image))).

    `ctr container create` does all three at once: it prepares an ACTIVE
    snapshot keyed by the container id (I7.11), and it generates the OCI
    config.json from the image config (I7.2) — so we do not hand-write the spec
    here, we let containerd derive it exactly as it does for `ctr run`.
    """
    step(3, "create the container (prepares the active snapshot + generates config.json)")
    ctr("container", "create", "--snapshotter", "overlayfs",
        image, CONTAINER, capture=False)
    snaps = ctr("snapshot", "ls").stdout
    active = [l for l in snaps.splitlines() if l.startswith(CONTAINER)]
    print(f"    active snapshot: {active[0].split()[0] if active else '(none)'}")


def run_task(config: dict) -> int:
    """Stands in for: task, _ := container.NewTask(ctx, cio.NewCreator(...));
        task.Start(ctx); status := task.Wait(ctx); <-status.

    We create the task (which spawns the shim and calls runc create — I7.1),
    start it, let its stdio stream straight to our terminal, and read the exit
    code back. `ctr task start` blocks until the task exits when attached, so
    "stream then wait" is one call here; in Go they are three.
    """
    step(4, "create + start the task, stream its output, wait for the exit code")
    proc = subprocess.run(
        ["sudo", "ctr", "-n", NAMESPACE, "task", "start", CONTAINER],
        text=True,
    )
    return proc.returncode


def cleanup() -> None:
    """Stands in for: task.Delete(ctx); container.Delete(ctx,
        containerd.WithSnapshotCleanup).

    Order matters and is the whole point of I7.6: the task must be gone (and
    stopped) before the container, and deleting the container with snapshot
    cleanup removes the active snapshot so we do not leak disk (I7.12/I7.13).
    We ignore errors so a partial run still tidies up what exists.
    """
    step(5, "clean up every object we made (task, container, snapshot)")
    ctr("task", "kill", "-s", "SIGKILL", CONTAINER, check=False)
    time.sleep(1)
    ctr("task", "rm", CONTAINER, check=False)
    ctr("container", "rm", CONTAINER, check=False)
    # Snapshot is removed with the container; remove explicitly if it lingers.
    ctr("snapshot", "rm", SNAPKEY, check=False)
    print("    done — box left as found")


def main() -> int:
    image = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IMAGE
    print(f"ctrpy — doing `ctr run`'s job by hand, namespace={NAMESPACE!r}, image={image!r}")
    ctr("namespace", "create", NAMESPACE, check=False)
    cleanup()  # in case a previous run died mid-way
    try:
        pull(image)
        config = read_config(image)
        create_container(image, config)
        code = run_task(config)
        print(f"\n>>> task exited {code}")
        return code
    finally:
        cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
