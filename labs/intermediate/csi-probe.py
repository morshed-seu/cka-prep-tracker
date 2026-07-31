#!/usr/bin/env python3
"""csi-probe.py - drive a real CSI driver over its socket, the way Kubernetes does.

Nothing here is Kubernetes-specific. A CSI driver is a gRPC server on a unix
socket, and every storage thing Kubernetes does is one of these calls made by an
ordinary controller. This script makes them by hand, in order, and names the
component that would have made each one on a real cluster:

    Identity    - who are you, are you healthy      <- node-driver-registrar, every sidecar
    Controller  - create/delete/attach, cluster-wide <- external-provisioner, external-attacher
    Node        - stage/publish, on this machine     <- the kubelet itself

Generate the stubs first (spec v1.13.0):

    curl -sSLo ~/csi.proto \\
      https://raw.githubusercontent.com/container-storage-interface/spec/v1.13.0/csi.proto
    ~/.venv-intermediate/bin/python -m grpc_tools.protoc -I ~ \\
      --python_out=~/csi --grpc_python_out=~/csi ~/csi.proto

Usage:
    sudo ~/.venv-intermediate/bin/python csi-probe.py identity
    sudo ~/.venv-intermediate/bin/python csi-probe.py provision  NAME
    sudo ~/.venv-intermediate/bin/python csi-probe.py stage      VOLID
    sudo ~/.venv-intermediate/bin/python csi-probe.py publish    VOLID PODUID
    sudo ~/.venv-intermediate/bin/python csi-probe.py unpublish  VOLID PODUID
    sudo ~/.venv-intermediate/bin/python csi-probe.py unstage    VOLID
    sudo ~/.venv-intermediate/bin/python csi-probe.py delete     VOLID
    sudo ~/.venv-intermediate/bin/python csi-probe.py teardown   VOLID PODUID...

sudo resets HOME, so the generated stubs are not found unless you say where they
are: sudo CSI_PB_DIR=$HOME/csi ~/.venv-intermediate/bin/python csi-probe.py ...
"""
import os
import sys

sys.path.insert(0, os.environ.get("CSI_PB_DIR", os.path.expanduser("~/csi")))
import grpc                      # noqa: E402
import csi_pb2 as csi            # noqa: E402
import csi_pb2_grpc as rpc       # noqa: E402

ENDPOINT = os.environ.get("CSI_ENDPOINT", "unix:///var/lib/i10-csi/csi.sock")
DRIVER = os.environ.get("CSI_DRIVER", "hostpath.csi.k8s.io")
KUBELET = "/var/lib/kubelet"

# The two paths are not interchangeable, and the difference is the whole point of
# I10.9: staging is per node, publishing is per pod.
def staging_path(volid):
    return f"{KUBELET}/plugins/kubernetes.io/csi/{DRIVER}/{volid}/globalmount"


def target_path(volid, pod_uid):
    return f"{KUBELET}/pods/{pod_uid}/volumes/kubernetes.io~csi/pvc-{volid[:8]}/mount"


def mount_cap():
    """A 'mount' volume (the other kind is a raw block device), read-write by one node."""
    return csi.VolumeCapability(
        mount=csi.VolumeCapability.MountVolume(fs_type=""),
        access_mode=csi.VolumeCapability.AccessMode(
            mode=csi.VolumeCapability.AccessMode.SINGLE_NODE_WRITER),
    )


def chan():
    return grpc.insecure_channel(ENDPOINT)


def _name(enum, value):
    """Never crash on a capability number you do not know.

    This is not defensive programming for its own sake: hostpathplugin v1.18.0
    advertises Controller capability 11 and Node capability 4, and neither number
    exists in spec v1.13.0 - they were VOLUME_CONDITION, since replaced by the
    GET_VOLUME_HEALTH family at different numbers. A client that calls
    Type.Name() on the raw value dies with ValueError on a healthy driver.
    """
    try:
        return enum.Name(value)
    except ValueError:
        return f"<unknown:{value}>"


def caps_of(stub, which):
    """Ask the driver what it can do. The kubelet does this before every decision -
    a call the driver did not advertise is a call it never receives."""
    if which == "controller":
        r = stub.ControllerGetCapabilities(csi.ControllerGetCapabilitiesRequest())
        return {_name(csi.ControllerServiceCapability.RPC.Type, c.rpc.type)
                for c in r.capabilities}
    r = stub.NodeGetCapabilities(csi.NodeGetCapabilitiesRequest())
    return {_name(csi.NodeServiceCapability.RPC.Type, c.rpc.type) for c in r.capabilities}


def cmd_identity():
    with chan() as ch:
        s = rpc.IdentityStub(ch)
        info = s.GetPluginInfo(csi.GetPluginInfoRequest())
        print(f"GetPluginInfo         name={info.name} version={info.vendor_version}")
        pc = s.GetPluginCapabilities(csi.GetPluginCapabilitiesRequest())
        for c in pc.capabilities:
            if c.HasField("service"):
                print("GetPluginCapabilities service:",
                      csi.PluginCapability.Service.Type.Name(c.service.type))
            elif c.HasField("volume_expansion"):
                print("GetPluginCapabilities volume_expansion:",
                      csi.PluginCapability.VolumeExpansion.Type.Name(c.volume_expansion.type))
        # The spec is explicit: an absent `ready` is not "not ready". A CO that
        # reads .ready.value without checking presence declares a healthy driver
        # unhealthy, because an unset BoolValue reads as False.
        pr = s.Probe(csi.ProbeRequest())
        print("Probe                 ready=",
              pr.ready.value if pr.HasField("ready") else "unset (spec: assume ready)")

        n = rpc.NodeStub(ch)
        ni = n.NodeGetInfo(csi.NodeGetInfoRequest())
        print(f"NodeGetInfo           node_id={ni.node_id} max_volumes={ni.max_volumes_per_node}")
        print("Controller can:", sorted(caps_of(rpc.ControllerStub(ch), "controller")))
        print("Node can:      ", sorted(caps_of(n, "node")))


def cmd_provision(name):
    """What external-provisioner does when a PVC appears with no PV to satisfy it."""
    with chan() as ch:
        c = rpc.ControllerStub(ch)
        r = c.CreateVolume(csi.CreateVolumeRequest(
            name=name,
            capacity_range=csi.CapacityRange(required_bytes=64 * 1024 * 1024),
            volume_capabilities=[mount_cap()],
        ))
        v = r.volume
        print(f"CreateVolume          volume_id={v.volume_id} bytes={v.capacity_bytes}")
        print("  (this is the PV object's spec.csi.volumeHandle)")
        if "PUBLISH_UNPUBLISH_VOLUME" in caps_of(c, "controller"):
            pr = c.ControllerPublishVolume(csi.ControllerPublishVolumeRequest(
                volume_id=v.volume_id, node_id=os.environ.get("CSI_NODE", "sandbox"),
                volume_capability=mount_cap()))
            print("ControllerPublishVolume ok  publish_context=",
                  dict(pr.publish_context) or "{}")
            print("  (this is external-attacher acting on a VolumeAttachment object)")
        else:
            print("ControllerPublishVolume not advertised - no attach step on this driver")


def cmd_stage(volid):
    """What the kubelet does ONCE PER NODE, before any pod gets the volume."""
    p = staging_path(volid)
    os.makedirs(p, exist_ok=True)
    with chan() as ch:
        n = rpc.NodeStub(ch)
        if "STAGE_UNSTAGE_VOLUME" not in caps_of(n, "node"):
            print("driver does not advertise STAGE_UNSTAGE_VOLUME; kubelet would skip staging")
            return
        n.NodeStageVolume(csi.NodeStageVolumeRequest(
            volume_id=volid, staging_target_path=p, volume_capability=mount_cap()))
        print(f"NodeStageVolume       {p}")
        print("  (format-if-needed and mount, once per node - the expensive half)")


def cmd_publish(volid, pod_uid):
    """What the kubelet does ONCE PER POD - a cheap bind mount off the staged one."""
    t = target_path(volid, pod_uid)
    os.makedirs(t, exist_ok=True)
    with chan() as ch:
        rpc.NodeStub(ch).NodePublishVolume(csi.NodePublishVolumeRequest(
            volume_id=volid, staging_target_path=staging_path(volid),
            target_path=t, volume_capability=mount_cap(), readonly=False))
        print(f"NodePublishVolume     {t}")
        print("  (bind mount into this pod's directory - the cheap half, once per pod)")


def _try(label, fn):
    try:
        fn()
        print(f"{label:26s} ok")
    except grpc.RpcError as e:
        print(f"{label:26s} {e.code().name}: {e.details()}")


def cmd_unpublish(volid, pod_uid):
    with chan() as ch:
        _try("NodeUnpublishVolume", lambda: rpc.NodeStub(ch).NodeUnpublishVolume(
            csi.NodeUnpublishVolumeRequest(volume_id=volid, target_path=target_path(volid, pod_uid))))


def cmd_unstage(volid):
    with chan() as ch:
        _try("NodeUnstageVolume", lambda: rpc.NodeStub(ch).NodeUnstageVolume(
            csi.NodeUnstageVolumeRequest(volume_id=volid, staging_target_path=staging_path(volid))))


def cmd_delete(volid):
    """Note what this does NOT check: whether the volume is still mounted anywhere."""
    with chan() as ch:
        c = rpc.ControllerStub(ch)
        _try("ControllerUnpublishVolume", lambda: c.ControllerUnpublishVolume(
            csi.ControllerUnpublishVolumeRequest(
                volume_id=volid, node_id=os.environ.get("CSI_NODE", "sandbox"))))
        _try("DeleteVolume", lambda: c.DeleteVolume(csi.DeleteVolumeRequest(volume_id=volid)))


def cmd_teardown(volid, *pod_uids):
    """Exactly the reverse order. Getting it wrong leaks a mount, not a file."""
    for uid in pod_uids:
        cmd_unpublish(volid, uid)
    cmd_unstage(volid)
    cmd_delete(volid)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    verb, args = sys.argv[1], sys.argv[2:]
    try:
        {"identity": cmd_identity, "provision": cmd_provision, "stage": cmd_stage,
         "publish": cmd_publish, "unpublish": cmd_unpublish, "unstage": cmd_unstage,
         "delete": cmd_delete, "teardown": cmd_teardown}[verb](*args)
    except grpc.RpcError as e:
        # A CSI error is a gRPC status code, and the spec assigns meanings per call.
        print(f"gRPC {e.code().name}: {e.details()}")
        sys.exit(1)
