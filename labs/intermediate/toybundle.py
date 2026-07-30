#!/usr/bin/env python3
"""toybundle.py — everything toycri.py does BELOW the gRPC layer.

I8's mini project has two halves, and this is the one that is not new. A CRI
server is a translation layer: it receives protobuf messages and turns them into
the machinery you already built earlier in the track. That machinery lives here,
so that toycri.py can be read as nothing but the translation.

  * the OCI bundle       — I2: a config.json and a rootfs, generated not typed
  * runc, driven safely  — I3: create + start, and the stdio trap that comes with
                           a container outliving the command that made it
  * the rootfs           — I4/I5: skopeo copy, then "a layer is a tar file"
  * the CRI log format   — I8.13: timestamp, stream, P/F tag, line

Nothing here imports grpc or the generated protobufs. It is deliberately
runnable and testable on its own.
"""

import os
import shutil
import subprocess
import sys
import time

# The same split containerd makes, and for the same reason: /run is a tmpfs
# mounted noexec on Ubuntu, so a rootfs unpacked there cannot be executed
# ("permission denied" on /bin/sh, which reads like a file-mode problem and is
# not one). Runtime state — the socket, runc's own state dir — goes in /run;
# anything that must be exec'd goes in /var/lib. Cf. /run/containerd vs
# /var/lib/containerd in I7.
SOCK = "/run/toycri.sock"
RUNC_ROOT = "/run/toycri/runc"
ROOT = "/var/lib/toycri"
ROOTFS = os.path.join(ROOT, "rootfs")

# The pause container's whole job, exactly as I8.4 reads it off /proc: hold the
# namespaces open and do nothing. Real pause blocks in pause(2); busybox has no
# pause command, so this is the closest one-liner.
PAUSE_ARGV = ["/bin/sh", "-c", "trap 'exit 0' TERM; while :; do sleep 3600 & wait $!; done"]


def now_ns():
    return int(time.time() * 1e9)


# --------------------------------------------------------------------------
# the OCI bundle — I2's subject, generated rather than hand-written
# --------------------------------------------------------------------------

def base_spec(argv, cwd="/", env=None, namespaces=None, terminal=False):
    """A minimal runtime-spec config.json. Six top-level keys, as I2.2 found."""
    return {
        "ociVersion": "1.3.0",
        "process": {
            "terminal": terminal,
            "user": {"uid": 0, "gid": 0},
            "args": argv,
            "env": env or ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
            "cwd": cwd,
            "capabilities": {
                s: ["CAP_CHOWN", "CAP_DAC_OVERRIDE", "CAP_NET_RAW", "CAP_SETGID", "CAP_SETUID"]
                for s in ("bounding", "effective", "permitted")
            },
            "noNewPrivileges": True,
        },
        # The bind mount under it is read-only (see write_bundle), so say so
        # here too. A real runtime gives each container its own writable upper
        # layer from the snapshotter instead (I7.11).
        "root": {"path": "rootfs", "readonly": True},
        "hostname": "toycri",
        "mounts": [
            {"destination": "/proc", "type": "proc", "source": "proc"},
            {"destination": "/dev", "type": "tmpfs", "source": "tmpfs",
             "options": ["nosuid", "strictatime", "mode=755", "size=65536k"]},
            {"destination": "/dev/pts", "type": "devpts", "source": "devpts",
             "options": ["nosuid", "noexec", "newinstance", "ptmxmode=0666", "mode=0620"]},
            {"destination": "/sys", "type": "sysfs", "source": "sysfs",
             "options": ["nosuid", "noexec", "nodev", "ro"]},
        ],
        "linux": {
            "namespaces": namespaces if namespaces is not None else [
                {"type": "pid"}, {"type": "ipc"}, {"type": "uts"},
                {"type": "mount"}, {"type": "network"},
            ],
            "maskedPaths": ["/proc/kcore", "/proc/keys", "/sys/firmware"],
            "readonlyPaths": ["/proc/sys", "/proc/sysrq-trigger"],
        },
    }


def write_bundle(path, spec, rootfs_src=ROOTFS):
    import json
    os.makedirs(path, exist_ok=True)
    rootfs = os.path.join(path, "rootfs")
    if not os.path.exists(rootfs):
        # A bind mount, not a copy: the rootfs is 8 MB and this runs per
        # container. A real runtime hands this to a snapshotter (I7.10), which
        # is also why every container here shares one writable tree instead of
        # getting its own overlay upper dir.
        #
        # Read-only, and B5.11 is why: a bind mount is the SAME files under a
        # second name, so an `rm -rf` of this bundle deletes the shared source
        # if the umount has not taken effect. Making it ro turns that accident
        # into an error. (Ask how this comment came to be written.)
        os.makedirs(rootfs)
        subprocess.run(["mount", "--bind", rootfs_src, rootfs], check=True)
        subprocess.run(["mount", "-o", "remount,bind,ro", rootfs], check=True)
    with open(os.path.join(path, "config.json"), "w") as fh:
        json.dump(spec, fh, indent=2)
    return path


def runc(*args, **kw):
    return subprocess.run(["runc", "--root", RUNC_ROOT, *args],
                          capture_output=True, text=True, **kw)


def runc_spawn(bundle, cid):
    """Create and start a container whose output nobody wants.

    Not `runc(...)`: a container that outlives the command INHERITS runc's
    stdout and stderr, so capture_output=True waits for an EOF that only
    arrives when the container dies. This is the same trap that makes
    `multipass exec` hang on a detached container, and it is why a real shim
    owns the container's stdio rather than borrowing its parent's. Redirect to
    a file instead, then read the file for runc's own diagnostics.
    """
    errfile = os.path.join(bundle, "runc.err")
    with open(errfile, "w+") as fh:
        rc = subprocess.run(["runc", "--root", RUNC_ROOT, "create",
                             "--bundle", bundle, cid],
                            stdin=subprocess.DEVNULL, stdout=fh, stderr=fh).returncode
        if rc == 0:
            rc = runc("start", cid).returncode
    with open(errfile) as fh:
        return rc, fh.read().strip()


def runc_pid(cid):
    import json
    r = runc("state", cid)
    if r.returncode != 0:
        return 0
    return json.loads(r.stdout).get("pid", 0)


# --------------------------------------------------------------------------
# the CRI log format — I8.13's four fields, written by hand because the
# workload just calls write(2) and has no idea it is being logged
# --------------------------------------------------------------------------

MAX_LINE = 16384


def pump(stream, name, log_path):
    """Read one of the container's pipes and write CRI log records."""
    if not log_path:
        return
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "ab", buffering=0) as out:
        buf = b""
        while True:
            chunk = stream.read1(4096) if hasattr(stream, "read1") else stream.read(4096)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf or len(buf) >= MAX_LINE:
                if len(buf) >= MAX_LINE and b"\n" not in buf[:MAX_LINE]:
                    piece, buf, tag = buf[:MAX_LINE], buf[MAX_LINE:], b"P"
                else:
                    piece, _, buf = buf.partition(b"\n")
                    tag = b"F"
                    if len(piece) > MAX_LINE:
                        buf = piece[MAX_LINE:] + b"\n" + buf
                        piece, tag = piece[:MAX_LINE], b"P"
                ts = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime())
                ts += ".%09d" % (time.time_ns() % 1_000_000_000)
                ts += time.strftime("%z")
                ts = ts[:-2] + ":" + ts[-2:]
                out.write(ts.encode() + b" " + name + b" " + tag + b" " + piece + b"\n")
        if buf:
            out.write(b"partial " + name + b" F " + buf + b"\n")


def _dirsize(path):
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return total


def _cleanup_bundle(path):
    """Unmount, verify, and only then delete.

    The verify step is not defensive programming for its own sake: rmtree on a
    bundle whose rootfs is still bind-mounted deletes the SHARED source tree,
    because a bind mount is the same inodes reachable by a second path (B5.11).
    Refusing to recurse while it is still a mountpoint is the whole fix.
    """
    rootfs = os.path.join(path, "rootfs")
    for _ in range(10):
        if not os.path.ismount(rootfs):
            break
        subprocess.run(["umount", rootfs], capture_output=True)
        time.sleep(0.1)
    else:
        subprocess.run(["umount", "-l", rootfs], capture_output=True)
    if os.path.ismount(rootfs):
        print("toycri: refusing to remove %s — rootfs is still mounted" % path,
              file=sys.stderr)
        return
    shutil.rmtree(path, ignore_errors=True)



# --------------------------------------------------------------------------
# the rootfs — I4's "a layer is a tar file" and I5's skopeo, in twenty lines
# --------------------------------------------------------------------------

def prepare_rootfs(ref):
    """Unpack an image into one shared rootfs, with I4/I5 machinery."""
    import glob
    import tarfile
    layout = os.path.join(ROOT, "layout")
    shutil.rmtree(layout, ignore_errors=True)
    os.makedirs(ROOT, exist_ok=True)
    os.makedirs(os.path.dirname(RUNC_ROOT), exist_ok=True)
    subprocess.run(["skopeo", "copy", ref, "oci:%s:img" % layout], check=True)
    shutil.rmtree(ROOTFS, ignore_errors=True)
    os.makedirs(ROOTFS)
    import json
    index = json.load(open(os.path.join(layout, "index.json")))
    mdig = index["manifests"][0]["digest"].split(":")[1]
    manifest = json.load(open(os.path.join(layout, "blobs", "sha256", mdig)))
    for layer in manifest["layers"]:          # I4.9: a layer is a tar file
        blob = os.path.join(layout, "blobs", "sha256", layer["digest"].split(":")[1])
        with tarfile.open(blob) as tf:
            tf.extractall(ROOTFS, filter="tar")
    print("rootfs ready at", ROOTFS, "(%d files)" % len(glob.glob(ROOTFS + "/*")))
