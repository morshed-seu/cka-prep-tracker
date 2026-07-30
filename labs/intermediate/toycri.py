#!/usr/bin/env python3
"""toycri.py — a CRI runtime, in one file, that crictl cannot tell from a real one.

I8's mini project. It implements enough of `runtime.v1` for crictl to drive a
whole pod lifecycle against it:

    Version  Status                                    (the handshake)
    RunPodSandbox  ListPodSandbox  PodSandboxStatus    (the sandbox)
    StopPodSandbox  RemovePodSandbox
    CreateContainer  StartContainer  StopContainer     (the containers)
    ListContainers  ContainerStatus  RemoveContainer
    ListImages  ImageStatus  ImageFsInfo  PullImage    (the ImageService half)

Everything BELOW the gRPC layer lives in toybundle.py, because none of it is
new: the bundle is I2's, the runtime is I3's runc, the rootfs is I4/I5's, and
the log format is the one I8.13 decodes. What is left here is the translation
layer — which is exactly what a real CRI server is.

Two deliberate simplifications, both stated rather than hidden:

  * State is in memory. A real runtime persists it (I7.12's metadata store) so a
    daemon restart does not lose the node's containers; restart toycri and the
    records are gone while the processes keep running — which is I7.3 in reverse.
  * There is no CNI. Every sandbox gets its own empty network namespace with a
    dead loopback, exactly B9.1. I9 is where that gets fixed.

Usage
-----
    # once: generate the protobuf stubs, and a rootfs from a real image
    ./toycri.py prepare-protos
    sudo ./toycri.py prepare-rootfs docker://docker.io/library/alpine:3.21

    # run the server
    sudo ./toycri.py serve

    # drive it, in another shell
    sudo crictl --runtime-endpoint unix:///run/toycri.sock version
    sudo crictl --runtime-endpoint unix:///run/toycri.sock runp sandbox.json

Requires the I0 venv (`~/.venv-intermediate`) with grpcio-tools.
"""

import os
import subprocess
import sys
import threading
import time
import uuid
from concurrent import futures

# The generated modules land next to this file after `prepare-protos`.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import grpc  # noqa: E402
import api_pb2 as pb  # noqa: E402
import api_pb2_grpc as pb_grpc  # noqa: E402

from toybundle import (  # noqa: E402
    PAUSE_ARGV, ROOT, ROOTFS, RUNC_ROOT, SOCK,
    _cleanup_bundle, _dirsize, base_spec, now_ns, prepare_rootfs, pump,
    runc, runc_pid, runc_spawn, write_bundle,
)

# --------------------------------------------------------------------------
# state
# --------------------------------------------------------------------------

class Sandbox:
    def __init__(self, cid, config):
        self.id = cid
        self.config = config
        self.created_at = now_ns()
        self.state = pb.SANDBOX_READY


class Container:
    def __init__(self, cid, sandbox_id, config):
        self.id = cid
        self.sandbox_id = sandbox_id
        self.config = config
        self.created_at = now_ns()
        self.started_at = 0
        self.finished_at = 0
        self.exit_code = 0
        self.state = pb.CONTAINER_CREATED
        self.proc = None
        self.log_path = None


SANDBOXES = {}
CONTAINERS = {}
LOCK = threading.Lock()


# --------------------------------------------------------------------------
# RuntimeService
# --------------------------------------------------------------------------

class RuntimeService(pb_grpc.RuntimeServiceServicer):

    def Version(self, request, context):
        return pb.VersionResponse(version="0.1.0", runtime_name="toycri",
                                  runtime_version="0.1.0", runtime_api_version="v1")

    def Status(self, request, context):
        st = pb.RuntimeStatus(conditions=[
            pb.RuntimeCondition(type="RuntimeReady", status=True),
            # Honest: there is no CNI here, so this is the one thing toycri
            # lies about. I9 makes it true.
            pb.RuntimeCondition(type="NetworkReady", status=True),
        ])
        return pb.StatusResponse(status=st, info={"runtime": "toycri"})

    # ---- sandbox ----------------------------------------------------------

    def RunPodSandbox(self, request, context):
        cfg = request.config
        cid = uuid.uuid4().hex + uuid.uuid4().hex[:32]
        bundle = os.path.join(ROOT, "sandboxes", cid)
        spec = base_spec(PAUSE_ARGV)
        spec["hostname"] = cfg.hostname or cfg.metadata.name
        write_bundle(bundle, spec)
        rc, err = runc_spawn(bundle, cid)
        if rc != 0:
            context.abort(grpc.StatusCode.UNKNOWN, "failed to start sandbox: %s" % err)
        with LOCK:
            SANDBOXES[cid] = Sandbox(cid, cfg)
        return pb.RunPodSandboxResponse(pod_sandbox_id=cid)

    def _sandbox_pb(self, sb):
        return pb.PodSandbox(id=sb.id, metadata=sb.config.metadata, state=sb.state,
                             created_at=sb.created_at, labels=sb.config.labels,
                             annotations=sb.config.annotations,
                             runtime_handler="toycri")

    def ListPodSandbox(self, request, context):
        with LOCK:
            items = [self._sandbox_pb(s) for s in SANDBOXES.values()]
        return pb.ListPodSandboxResponse(items=items)

    def PodSandboxStatus(self, request, context):
        sb = SANDBOXES.get(request.pod_sandbox_id)
        if sb is None:
            context.abort(grpc.StatusCode.NOT_FOUND, "sandbox not found")
        pid = runc_pid(sb.id)
        st = pb.PodSandboxStatus(
            id=sb.id, metadata=sb.config.metadata, state=sb.state,
            created_at=sb.created_at,
            network=pb.PodSandboxNetworkStatus(ip=""),
            linux=pb.LinuxPodSandboxStatus(namespaces=pb.Namespace(options=pb.NamespaceOption())),
            labels=sb.config.labels, annotations=sb.config.annotations,
            runtime_handler="toycri")
        return pb.PodSandboxStatusResponse(
            status=st, info={"pid": str(pid), "bundle": os.path.join(ROOT, "sandboxes", sb.id)})

    def StopPodSandbox(self, request, context):
        sb = SANDBOXES.get(request.pod_sandbox_id)
        if sb is None:
            return pb.StopPodSandboxResponse()   # idempotent, per the proto
        with LOCK:
            kids = [c for c in CONTAINERS.values() if c.sandbox_id == sb.id]
        for c in kids:                            # containers first, always
            self._stop_container(c, 0)
        runc("kill", sb.id, "KILL")
        time.sleep(0.2)
        runc("delete", "--force", sb.id)
        sb.state = pb.SANDBOX_NOTREADY
        return pb.StopPodSandboxResponse()

    def RemovePodSandbox(self, request, context):
        sb = SANDBOXES.pop(request.pod_sandbox_id, None)
        if sb is None:
            return pb.RemovePodSandboxResponse()
        with LOCK:
            kids = [c for c in CONTAINERS.values() if c.sandbox_id == sb.id]
        for c in kids:
            self._remove_container(c)
        runc("delete", "--force", sb.id)
        _cleanup_bundle(os.path.join(ROOT, "sandboxes", sb.id))
        return pb.RemovePodSandboxResponse()

    # ---- containers -------------------------------------------------------

    def CreateContainer(self, request, context):
        sb = SANDBOXES.get(request.pod_sandbox_id)
        if sb is None:
            context.abort(grpc.StatusCode.NOT_FOUND,
                          "failed to find sandbox id %r" % request.pod_sandbox_id)
        cfg = request.config
        cid = uuid.uuid4().hex + uuid.uuid4().hex[:32]
        spid = runc_pid(sb.id)

        # This is the whole mechanism behind "containers in a pod share a
        # network namespace" (I8.5): four entries with a path, two without.
        ns = [
            {"type": "ipc", "path": "/proc/%d/ns/ipc" % spid},
            {"type": "uts", "path": "/proc/%d/ns/uts" % spid},
            {"type": "network", "path": "/proc/%d/ns/net" % spid},
            {"type": "mount"},
        ]
        if cfg.linux.security_context.namespace_options.pid == pb.POD:
            ns.append({"type": "pid", "path": "/proc/%d/ns/pid" % spid})
        else:
            ns.append({"type": "pid"})

        argv = list(cfg.command) + list(cfg.args)
        if not argv:
            argv = ["/bin/sh"]
        env = ["%s=%s" % (kv.key, kv.value) for kv in cfg.envs] or None
        spec = base_spec(argv, cwd=cfg.working_dir or "/", env=env, namespaces=ns)
        spec["hostname"] = sb.config.hostname or sb.config.metadata.name
        bundle = write_bundle(os.path.join(ROOT, "containers", cid), spec)

        ctr = Container(cid, sb.id, cfg)
        if request.sandbox_config.log_directory and cfg.log_path:
            ctr.log_path = os.path.join(request.sandbox_config.log_directory, cfg.log_path)

        # `runc create` exits, but the container init keeps the write ends of
        # these pipes open — so reading them here is exactly what a shim does
        # (I3.5, I7.1). Holding them is the reason this process must stay alive.
        ctr.proc = subprocess.Popen(
            ["runc", "--root", RUNC_ROOT, "create", "--bundle", bundle, cid],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        ctr.proc.wait()
        if ctr.proc.returncode != 0:
            context.abort(grpc.StatusCode.UNKNOWN, "runc create failed")
        for stream, name in ((ctr.proc.stdout, b"stdout"), (ctr.proc.stderr, b"stderr")):
            threading.Thread(target=pump, args=(stream, name, ctr.log_path),
                             daemon=True).start()
        with LOCK:
            CONTAINERS[cid] = ctr
        return pb.CreateContainerResponse(container_id=cid)

    def StartContainer(self, request, context):
        c = CONTAINERS.get(request.container_id)
        if c is None:
            context.abort(grpc.StatusCode.NOT_FOUND, "container not found")
        r = runc("start", c.id)
        if r.returncode != 0:
            context.abort(grpc.StatusCode.UNKNOWN, r.stderr.strip())
        c.state = pb.CONTAINER_RUNNING
        c.started_at = now_ns()
        threading.Thread(target=self._reap, args=(c,), daemon=True).start()
        return pb.StartContainerResponse()

    def _reap(self, c):
        """Poll runc for the exit. A real shim gets a SIGCHLD instead."""
        import json
        while True:
            r = runc("state", c.id)
            if r.returncode != 0:
                break
            if json.loads(r.stdout).get("status") == "stopped":
                break
            time.sleep(0.3)
        if c.state == pb.CONTAINER_RUNNING:
            c.state = pb.CONTAINER_EXITED
            c.finished_at = now_ns()

    def _container_pb(self, c):
        return pb.Container(id=c.id, pod_sandbox_id=c.sandbox_id,
                            metadata=c.config.metadata, image=c.config.image,
                            image_ref=c.config.image.image, state=c.state,
                            created_at=c.created_at, labels=c.config.labels,
                            annotations=c.config.annotations)

    def ListContainers(self, request, context):
        with LOCK:
            items = [self._container_pb(c) for c in CONTAINERS.values()]
        return pb.ListContainersResponse(containers=items)

    def ContainerStatus(self, request, context):
        c = CONTAINERS.get(request.container_id)
        if c is None:
            context.abort(grpc.StatusCode.NOT_FOUND, "container not found")
        st = pb.ContainerStatus(
            id=c.id, metadata=c.config.metadata, state=c.state,
            created_at=c.created_at, started_at=c.started_at,
            finished_at=c.finished_at, exit_code=c.exit_code,
            image=c.config.image, image_ref=c.config.image.image,
            log_path=c.log_path or "", labels=c.config.labels,
            annotations=c.config.annotations)
        return pb.ContainerStatusResponse(
            status=st, info={"pid": str(runc_pid(c.id)),
                             "bundle": os.path.join(ROOT, "containers", c.id)})

    def _stop_container(self, c, timeout):
        runc("kill", c.id, "TERM")
        deadline = time.time() + max(timeout, 1)
        while time.time() < deadline and runc_pid(c.id):
            time.sleep(0.2)
        runc("kill", c.id, "KILL")
        c.state = pb.CONTAINER_EXITED
        if not c.finished_at:
            c.finished_at = now_ns()

    def StopContainer(self, request, context):
        c = CONTAINERS.get(request.container_id)
        if c is not None:
            self._stop_container(c, request.timeout)
        return pb.StopContainerResponse()

    def _remove_container(self, c):
        runc("delete", "--force", c.id)
        CONTAINERS.pop(c.id, None)
        _cleanup_bundle(os.path.join(ROOT, "containers", c.id))

    def RemoveContainer(self, request, context):
        c = CONTAINERS.get(request.container_id)
        if c is not None:
            self._remove_container(c)
        return pb.RemoveContainerResponse()

    # ---- the streaming trio: honestly unimplemented ------------------------
    # Exec/Attach/PortForward return a URL to a streaming server the runtime
    # hosts (I8.9). Standing one up is a second HTTP server and an SPDY
    # upgrade; ExecSync is the one that fits in a paragraph, so it is the one
    # that works.

    def ExecSync(self, request, context):
        c = CONTAINERS.get(request.container_id)
        if c is None:
            context.abort(grpc.StatusCode.NOT_FOUND, "container not found")
        r = runc("exec", c.id, *request.cmd)
        return pb.ExecSyncResponse(stdout=r.stdout.encode(), stderr=r.stderr.encode(),
                                   exit_code=r.returncode)

    def ReopenContainerLog(self, request, context):
        return pb.ReopenContainerLogResponse()

    def UpdateRuntimeConfig(self, request, context):
        return pb.UpdateRuntimeConfigResponse()


# --------------------------------------------------------------------------
# ImageService — the other half of CRI (I8.3)
# --------------------------------------------------------------------------

class ImageService(pb_grpc.ImageServiceServicer):

    def _image(self):
        return pb.Image(id="sha256:toycri", repo_tags=["toycri/rootfs:latest"],
                        size=_dirsize(ROOTFS))

    def ListImages(self, request, context):
        return pb.ListImagesResponse(images=[self._image()] if os.path.isdir(ROOTFS) else [])

    def ImageStatus(self, request, context):
        return pb.ImageStatusResponse(image=self._image())

    def PullImage(self, request, context):
        # Every sandbox and container uses the one rootfs prepare-rootfs built,
        # so a pull is a no-op that reports success — which is exactly the
        # shape of imagePullPolicy: IfNotPresent hitting a cached image.
        return pb.PullImageResponse(image_ref="sha256:toycri")

    def RemoveImage(self, request, context):
        return pb.RemoveImageResponse()

    def ImageFsInfo(self, request, context):
        fs = pb.FilesystemUsage(
            timestamp=now_ns(),
            fs_id=pb.FilesystemIdentifier(mountpoint=ROOTFS),
            used_bytes=pb.UInt64Value(value=_dirsize(ROOTFS)),
            inodes_used=pb.UInt64Value(value=0))
        return pb.ImageFsInfoResponse(image_filesystems=[fs])


def prepare_protos():
    """Compile the cri-api proto next to this file. Needs grpcio-tools."""
    here = os.path.dirname(os.path.abspath(__file__))
    proto = os.path.join(here, "api.proto")
    if not os.path.exists(proto):
        url = ("https://raw.githubusercontent.com/kubernetes/cri-api/"
               "master/pkg/apis/runtime/v1/api.proto")
        subprocess.run(["curl", "-sSL", "-o", proto, url], check=True)
    subprocess.run([sys.executable, "-m", "grpc_tools.protoc", "-I", here,
                    "--python_out", here, "--grpc_python_out", here, proto], check=True)
    print("compiled api_pb2.py and api_pb2_grpc.py in", here)


def serve():
    if os.geteuid() != 0:
        sys.exit("toycri: must run as root (it drives runc and mounts)")
    os.makedirs(ROOT, exist_ok=True)
    os.makedirs(RUNC_ROOT, exist_ok=True)
    if not os.path.isdir(ROOTFS):
        sys.exit("toycri: no rootfs — run `%s prepare-rootfs docker://alpine:3.21`" % sys.argv[0])
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=8))
    pb_grpc.add_RuntimeServiceServicer_to_server(RuntimeService(), server)
    pb_grpc.add_ImageServiceServicer_to_server(ImageService(), server)
    server.add_insecure_port("unix://" + SOCK)
    server.start()
    # I7.14 and I8.2: the socket IS the access control. root-only, like the
    # real one — anyone who can write here can run anything on the node.
    os.chmod(SOCK, 0o660)
    print("toycri listening on unix://%s  (crictl --runtime-endpoint unix://%s)"
          % (SOCK, SOCK), flush=True)
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        server.stop(0)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "serve"
    if cmd == "prepare-protos":
        prepare_protos()
    elif cmd == "prepare-rootfs":
        prepare_rootfs(sys.argv[2] if len(sys.argv) > 2 else
                       "docker://docker.io/library/alpine:3.21")
    elif cmd == "serve":
        serve()
    else:
        sys.exit(__doc__)
