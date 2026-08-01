#!/usr/bin/env python3
"""minidock - the whole intermediate track, in one program.

Nothing here is new. Every layer is a project you already built:

    layer 1  pull and store     I5's pull.py, behind a real content store
    layer 2  unpack and snapshot I4's chain IDs + B5's overlayfs
    layer 3  run                 I2's bundle + I3's runc and microshim.py
    layer 4  network             I9's cni-minibridge, invoked as a plugin
    layer 5  volumes and logs    I10's volman.py + I12's CRI log format
    layer 6  the platform layer  a metadata store, a CLI, a reconciler

What is new is that they are wired together, which is where the design
decisions live. The comments below say which decision belongs to which
specification, because almost none of them are ours: the split between an
image config and a runtime config is image-spec vs runtime-spec, the digest
verification is distribution-spec, the log line format is the CRI's, and the
restart loop is B13's reconciliation loop wearing a different hat.

    sudo minidock pull docker.io/library/alpine:3.21
    sudo minidock run --name web -v data:/data alpine:3.21 sh -c 'echo hi'
    sudo minidock ps -a
    sudo minidock logs web
    sudo minidock exec web ps -o pid,comm
    sudo minidock rm -f web

Root is required, and honestly so: every layer needs a capability an ordinary
user does not have - mknod for whiteouts, mount for overlayfs, clone for the
namespaces, netlink for the bridge. I11's rootless stack is the alternative,
and it needs a helper for every one of those.
"""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import selectors
import shutil
import stat
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = "/var/lib/minidock"
CONTENT = f"{ROOT}/content"            # layer 1: blobs, named by digest
IMAGES = f"{ROOT}/images.json"         # layer 1: names -> manifest digest
SNAPSHOTS = f"{ROOT}/snapshots"        # layer 2: unpacked layers, by chain ID
CONTAINERS = f"{ROOT}/containers"      # layer 3: one bundle each
VOLUMES = f"{ROOT}/volumes"            # layer 5: named volumes
DB = f"{ROOT}/state.json"              # layer 6: the metadata store
RUNC_ROOT = "/run/minidock"            # layer 3: runc's own state, not ours
NETNS_DIR = "/run/netns"               # layer 4: where `ip netns` looks
CNI_BIN = "/opt/cni/bin"

# Layer 4's network. One /24, one bridge, one plugin - the plugin is
# cni-minibridge from I9.15, and the point of this dict is that minidock
# contains no networking code at all: it writes JSON to a process's stdin.
NETCONF = {
    "cniVersion": "1.1.0",
    "name": "minidock",
    "type": "minibridge",
    "bridge": "mdbr0",
    "ipMasq": True,        # without this the pod has an address and no internet
    "ipam": {"subnet": "10.66.0.0/24"},
}
LOOPCONF = {"cniVersion": "1.1.0", "name": "minidock-lo", "type": "loopback"}
RESOLV = "nameserver 8.8.8.8\nnameserver 1.1.1.1\noptions ndots:1\n"

MAX_LINE = 16384       # I12.4: containerd's maxContainerLogLineSize, to the byte
ACCEPT = ",".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])
INDEX_TYPES = {"application/vnd.oci.image.index.v1+json",
               "application/vnd.docker.distribution.manifest.list.v2+json"}


def die(msg, code=1):
    print(f"minidock: {msg}", file=sys.stderr)
    sys.exit(code)


def need_root():
    if os.geteuid() != 0:
        die("must run as root (try sudo)")


def sh(*args, **kw):
    """Run a command, raising with its stderr attached. No shell, ever."""
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    p = subprocess.run(args, **kw)
    if p.returncode != 0:
        raise RuntimeError(f"{args[0]} failed ({p.returncode}): "
                           f"{(p.stderr or p.stdout or '').strip()}")
    return p.stdout


# =========================================================================
# layer 1 - pull and store
#
# Two stores, deliberately in two directories. Blobs are content-addressed, so
# a blob can always be re-fetched and never needs a backup; names are the one
# thing in the system that cannot be recomputed from the data, so the index is
# the only file here worth protecting. I7.11 measured the same split inside
# containerd, where the content store had 472 files and the metadata database
# was the only store with no upstream to rebuild from.
# =========================================================================

TOKEN = None


def parse_ref(ref):
    """Split a reference into endpoint, repository and tag, Docker's way."""
    if "@" in ref:
        rest, tag = ref.rsplit("@", 1)
    elif ":" in ref.rsplit("/", 1)[-1]:
        rest, tag = ref.rsplit(":", 1)
    else:
        rest, tag = ref, "latest"
    if "/" not in rest or ("." not in rest.split("/")[0]
                           and ":" not in rest.split("/")[0]
                           and rest.split("/")[0] != "localhost"):
        host, name = "docker.io", rest
    else:
        host, name = rest.split("/", 1)
    if "/" not in name:
        name = "library/" + name          # docker.io/alpine IS library/alpine
    if host == "docker.io":
        endpoint = "https://registry-1.docker.io"
    else:
        scheme = "http" if host.startswith(("localhost", "127.0.0.1")) else "https"
        endpoint = f"{scheme}://{host}"
    return endpoint, name, tag, f"{host}/{name}:{tag}"


def http(url, token=None, accept=None):
    req = urllib.request.Request(url)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if accept:
        req.add_header("Accept", accept)
    return urllib.request.urlopen(req)


def authenticate(endpoint, name):
    """The token dance. Anonymous is fine; a 401 here is the normal path."""
    try:
        http(endpoint + "/v2/").read()
        return None
    except urllib.error.HTTPError as e:
        if e.code != 401:
            die(f"{endpoint}/v2/ answered {e.code} - is this a registry?")
        challenge = e.headers.get("WWW-Authenticate", "")
    if not challenge.lower().startswith("bearer"):
        die(f"cannot handle challenge: {challenge}")
    parts = dict(p.split("=", 1) for p in challenge[7:].split(",") if "=" in p)
    q = {"scope": f"repository:{name}:pull"}
    if "service" in parts:
        q["service"] = parts["service"].strip('"')
    body = json.load(http(parts["realm"].strip('"') + "?" + urllib.parse.urlencode(q)))
    return body.get("token") or body.get("access_token")


def blob_path(digest):
    algo, hex_ = digest.split(":", 1)
    return f"{CONTENT}/blobs/{algo}/{hex_}"


def have(digest):
    return os.path.exists(blob_path(digest))


def read_blob(digest):
    with open(blob_path(digest), "rb") as f:
        return f.read()


def fetch_blob(endpoint, name, desc, what):
    """Fetch one blob, verify its digest, cache it. Never fetch it twice.

    Verify-on-write is the one error content addressing gives you for free, and
    the rename is the whole of the atomicity story: a partial download is
    called .partial until its bytes have been proved, so an interrupted pull
    can never leave a file that a later run will trust.
    """
    digest = desc["digest"]
    path = blob_path(digest)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        print(f"  cached    {what:<10} {digest[:23]}...")
        return path
    algo = digest.split(":", 1)[0]
    h, size, tmp = hashlib.new(algo), 0, path + ".partial"
    url = f"{endpoint}/v2/{name}/blobs/{digest}"
    with http(url, TOKEN) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            h.update(chunk)
            size += len(chunk)
            f.write(chunk)
    got = f"{algo}:{h.hexdigest()}"
    if got != digest:
        os.unlink(tmp)
        die(f"{what}: digest mismatch\n  claimed {digest}\n  actual  {got}")
    os.rename(tmp, path)
    print(f"  verified  {what:<10} {digest[:23]}... {size:>9} B")
    return path


def select_manifest(index, want=("linux", "amd64")):
    """Pick one manifest for this platform.

    Two traps, both from I4.9: attestation manifests sit in the same index with
    platform unknown/unknown, and `architecture` and `variant` are separate
    fields - there is no such string as "arm64v8".
    """
    for m in index.get("manifests", []):
        p = m.get("platform") or {}
        if p.get("os") == "unknown" or p.get("architecture") == "unknown":
            continue                                   # attestation, not an image
        if (p.get("os"), p.get("architecture")) == want:
            return m
    die(f"no {want[0]}/{want[1]} manifest in this index")


def load_index():
    if os.path.exists(IMAGES):
        with open(IMAGES) as f:
            return json.load(f)
    return {}


def save_index(idx):
    os.makedirs(ROOT, exist_ok=True)
    tmp = IMAGES + ".tmp"
    with open(tmp, "w") as f:
        json.dump(idx, f, indent=1, sort_keys=True)
    os.replace(tmp, IMAGES)


def cmd_pull(args):
    """minidock pull REF - the distribution spec, transcribed."""
    global TOKEN
    need_root()
    endpoint, name, tag, canonical = parse_ref(args.ref)
    idx = load_index()
    TOKEN = authenticate(endpoint, name)
    url = f"{endpoint}/v2/{name}/manifests/{tag}"
    with http(url, TOKEN, ACCEPT) as r:
        raw, media = r.read(), r.headers.get("Content-Type", "").split(";")[0]
    doc = json.loads(raw)
    if media in INDEX_TYPES or doc.get("manifests"):
        os.makedirs(f"{CONTENT}/blobs/sha256", exist_ok=True)
        chosen = select_manifest(doc)
        print(f"  index     {len(doc['manifests'])} entries -> "
              f"{chosen['platform']['os']}/{chosen['platform']['architecture']}")
        with http(f"{endpoint}/v2/{name}/manifests/{chosen['digest']}",
                  TOKEN, ACCEPT) as r:
            raw = r.read()
        doc = json.loads(raw)
    digest = "sha256:" + hashlib.sha256(raw).hexdigest()
    path = blob_path(digest)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(raw)
    fetch_blob(endpoint, name, doc["config"], "config")
    for i, layer in enumerate(doc["layers"]):
        fetch_blob(endpoint, name, layer, f"layer {i}")
    idx[canonical] = digest
    if args.ref != canonical:
        idx[args.ref] = digest              # remember what the user typed, too
    save_index(idx)
    print(f"{canonical}\n{digest}")


def resolve(ref):
    """A name -> a manifest. The one lookup that cannot be a computation."""
    idx = load_index()
    for key in (ref, f"docker.io/library/{ref}", f"docker.io/{ref}"):
        if key in idx:
            return json.loads(read_blob(idx[key])), idx[key]
        if ":" not in key.rsplit("/", 1)[-1] and f"{key}:latest" in idx:
            return json.loads(read_blob(idx[f"{key}:latest"])), idx[f"{key}:latest"]
    die(f"image not found locally: {ref}   (try: minidock pull {ref})")


def cmd_verify(args):
    """Re-hash every blob. The check the store never runs on its own.

    Verification happens on write and then never again, in every registry
    client there is - because a full re-hash costs a read of the whole store
    and corruption is rare. That is a defensible trade until the day a bit
    rots, at which point this is the command that turns an unreadable tar
    into a named blob.
    """
    bad = total = 0
    for dp, _, files in os.walk(f"{CONTENT}/blobs"):
        algo = os.path.basename(dp)
        for name in files:
            if name.endswith(".partial"):
                continue
            total += 1
            h = hashlib.new(algo)
            with open(os.path.join(dp, name), "rb") as f:
                while chunk := f.read(1 << 20):
                    h.update(chunk)
            if h.hexdigest() != name:
                bad += 1
                print(f"CORRUPT {algo}:{name}\n"
                      f"        content hashes to {algo}:{h.hexdigest()}")
    print(f"{total} blobs checked, {bad} corrupt")
    return 1 if bad else 0


def cmd_images(args):
    idx = load_index()
    print(f"{'REFERENCE':<44}{'MANIFEST':<20}{'SIZE':>10}")
    seen = {}
    for ref, digest in sorted(idx.items()):
        if not have(digest):
            print(f"{ref:<44}{digest[7:19]:<20}{'MISSING':>10}")
            continue
        m = json.loads(read_blob(digest))
        size = sum(l.get("size", 0) for l in m["layers"])
        seen[digest] = size
        print(f"{ref:<44}{digest[7:19]:<20}{size:>10}")
    if seen:
        blobs = [os.path.join(dp, f) for dp, _, fs in os.walk(CONTENT) for f in fs]
        total = sum(os.path.getsize(b) for b in blobs)
        print(f"\n{len(idx)} names -> {len(seen)} manifests; "
              f"{sum(seen.values())} B of layers declared, "
              f"{total} B in {len(blobs)} blobs on disk "
              f"(manifests and configs included; a layer shared by two images "
              f"is stored once)")


# =========================================================================
# layer 2 - unpack and snapshot
#
# A snapshotter. Each directory here holds ONE layer's diff and is keyed by
# the CHAIN ID, not the layer digest, because two images sharing a base must
# share directories up to the exact point their chains diverge and not one
# layer further (I4.12). The chain-ID recursion is containerd's, not the
# spec's: sha256("<parent> <diff_id>"), one space, both keeping their prefixes.
# =========================================================================


def chain_ids(diff_ids):
    out, cur = [], None
    for d in diff_ids:
        cur = d if cur is None else \
            "sha256:" + hashlib.sha256(f"{cur} {d}".encode()).hexdigest()
        out.append(cur)
    return out


def apply_layer(tar_path, dest):
    """Extract one layer tar into dest, translating whiteouts as we go.

    This is the function that turns an IMAGE convention into a KERNEL one. The
    image format marks a deletion with a zero-length file called `.wh.<name>`;
    overlayfs marks one with a character device numbered 0:0. They describe the
    same thing and no kernel has ever heard of the first, so somebody has to
    translate - and this is that somebody. Same for a replaced directory:
    `.wh..wh..opq` inside it becomes the xattr trusted.overlay.opaque=y.
    """
    os.makedirs(dest, exist_ok=True)
    whiteouts = opaques = 0
    try:
        return _apply_layer(tar_path, dest)
    except tarfile.TarError as e:
        # Content addressing hands you this check for free - but only if you
        # actually run it. Left unhandled, a corrupted blob surfaces here as
        # "invalid compressed data" from inside the tar reader, which names
        # neither the blob nor the image nor the word "digest". This is the
        # gauntlet's corrupted-blob fault, and the message is the whole fix.
        digest = "sha256:" + os.path.basename(tar_path)
        raise RuntimeError(
            f"cannot unpack {digest[:26]}...: {e}\n"
            f"  the bytes on disk no longer match the name they are filed "
            f"under.\n  run: minidock verify   (then delete the blob and pull "
            f"again - the content\n  store is the one store here with an "
            f"upstream to rebuild from)") from None


def _apply_layer(tar_path, dest):
    whiteouts = opaques = 0
    with tarfile.open(tar_path, "r|*") as tf:
        for m in tf:
            base = os.path.basename(m.name)
            if base == ".wh..wh..opq":
                d = os.path.join(dest, os.path.dirname(m.name))
                os.makedirs(d, exist_ok=True)
                os.setxattr(d, "trusted.overlay.opaque", b"y")
                opaques += 1
                continue
            if base.startswith(".wh."):
                target = os.path.join(dest, os.path.dirname(m.name), base[4:])
                os.makedirs(os.path.dirname(target), exist_ok=True)
                if not os.path.lexists(target):
                    os.mknod(target, stat.S_IFCHR | 0o600, os.makedev(0, 0))
                whiteouts += 1
                continue
            try:
                tf.extract(m, dest, set_attrs=True, filter="fully_trusted")
            except FileExistsError:
                pass                      # a layer may re-state a path it owns
    return whiteouts, opaques


def unpack(manifest):
    """Materialise every layer of an image. Returns the snapshot dirs, base first."""
    cfg = json.loads(read_blob(manifest["config"]["digest"]))
    diff_ids = cfg["rootfs"]["diff_ids"]
    if len(diff_ids) != len(manifest["layers"]):
        die(f"manifest has {len(manifest['layers'])} layers but the config "
            f"declares {len(diff_ids)} diff_ids - these must agree")
    dirs = []
    for cid, layer in zip(chain_ids(diff_ids), manifest["layers"]):
        snap = f"{SNAPSHOTS}/{cid.split(':', 1)[1]}"
        dirs.append(f"{snap}/fs")
        if os.path.exists(f"{snap}/.committed"):
            continue                       # the cache. This is the whole point.
        shutil.rmtree(snap, ignore_errors=True)
        os.makedirs(f"{snap}/fs", exist_ok=True)
        w, o = apply_layer(blob_path(layer["digest"]), f"{snap}/fs")
        with open(f"{snap}/.committed", "w") as f:
            json.dump({"chainID": cid, "layer": layer["digest"],
                       "whiteouts": w, "opaques": o}, f)
    return dirs, cfg


def mount_rootfs(lowers, bundle):
    """Assemble the overlay. Note the reversal: lowerdir is TOPMOST FIRST."""
    upper, work, merged = f"{bundle}/upper", f"{bundle}/work", f"{bundle}/rootfs"
    for d in (upper, work, merged):
        os.makedirs(d, exist_ok=True)
    lower = ":".join(reversed(lowers))
    sh("mount", "-t", "overlay", "overlay",
       "-o", f"lowerdir={lower},upperdir={upper},workdir={work}", merged)
    return merged


def umount_rootfs(bundle):
    for _ in range(3):
        p = subprocess.run(["umount", f"{bundle}/rootfs"],
                           capture_output=True, text=True)
        if p.returncode == 0 or "not mounted" in p.stderr:
            return True
        time.sleep(0.2)
    subprocess.run(["umount", "-l", f"{bundle}/rootfs"], capture_output=True)
    return False


