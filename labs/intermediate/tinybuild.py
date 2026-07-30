#!/usr/bin/env python3
"""tinybuild.py - build an OCI image from a Dockerfile, with no builder.

Usage:  sudo tinybuild.py DOCKERFILE [-C CONTEXT] [-o LAYOUT] [--push REF]

    sudo ./tinybuild.py Dockerfile -C . -o ./out --push 127.0.0.1:5000/demo/app:v1

Understands five instructions and no more:

    FROM <ref> | scratch     start from a pulled image, or from nothing
    RUN  <shell command>      execute it in a container, keep the diff
    COPY <src>... <dst>       copy from the build context, keep the diff
    ENV  KEY=value            amend the config
    CMD  ["a","b"] | a b      amend the config

The point of this program is that almost none of it is privileged. Writing tar
files, hashing them, emitting JSON and PUTting blobs need no kernel help at all
-- which is why unprivileged image builders can exist (I6.9). Exactly one step
needs a container, RUN, and that one is handed to runc.

Root is required only because RUN calls runc, and because a base image's layers
contain files owned by other users. --dry-run needs neither.

Three pieces are borrowed rather than reinvented:

  * FROM reuses pull.py, unchanged, to fetch and verify the base image.
  * --push is pull.py's transport in reverse: blobs first, manifest last (I5.9).
  * The diff is computed by comparing filesystem *trees*, which is what
    containerd's own "walking" differ does -- so, as I4 found the hard way, a
    replaced directory yields one .wh.<child> per former child rather than an
    opaque marker. Both encodings are legal; this one is simply honest about
    which it produces.
"""
import argparse, gzip, hashlib, io, json, os, shutil, stat, subprocess, sys, tarfile, tempfile
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib
pull = importlib.import_module("pull")

EMPTY_DIGEST = "sha256:" + hashlib.sha256(b"").hexdigest()


def die(msg):
    print(f"tinybuild: {msg}", file=sys.stderr)
    sys.exit(1)


def log(msg):
    print(msg, flush=True)


# ---------------------------------------------------------------- parsing

def parse_dockerfile(path):
    """Return a list of (INSTRUCTION, argument). Comments and blanks vanish
    here, which is precisely why they cannot affect a cache key (I6.3)."""
    steps, pending = [], ""
    for raw in open(path):
        line = raw.rstrip("\n")
        if pending:
            line, pending = pending + " " + line.strip(), ""
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.endswith("\\"):
            pending = stripped[:-1].rstrip()
            continue
        verb, _, arg = stripped.partition(" ")
        verb = verb.upper()
        if verb not in ("FROM", "RUN", "COPY", "ENV", "CMD"):
            die(f"unsupported instruction {verb!r} (this build understands "
                "FROM, RUN, COPY, ENV and CMD)")
        steps.append((verb, arg.strip()))
    if not steps or steps[0][0] != "FROM":
        die("a Dockerfile must begin with FROM")
    return steps


# ------------------------------------------------------------ tree states

def snapshot(root):
    """Map every path under root to the metadata that decides 'has it changed'.

    Content is not hashed: like containerd's walking differ, a file counts as
    changed when its size, mode, ownership or mtime moved. That is cheap and it
    is what real differs do -- and it means touching a file with identical
    content DOES produce a layer here, unlike a COPY cache key (I6.3)."""
    state = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for name in dirnames + filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root)
            try:
                st = os.lstat(full)
            except FileNotFoundError:
                continue
            key = (st.st_mode, st.st_uid, st.st_gid,
                   st.st_size if not stat.S_ISDIR(st.st_mode) else 0,
                   st.st_mtime_ns)
            if stat.S_ISLNK(st.st_mode):
                key += (os.readlink(full),)
            state[rel] = key
    return state


def diff_paths(before, after):
    """(changed, deleted) relative paths between two snapshots."""
    changed = sorted(p for p, v in after.items() if before.get(p) != v)
    deleted = sorted(p for p in before if p not in after)
    return changed, deleted


def write_layer(root, changed, deleted, dest):
    """Pack a changed-set into a gzipped tar. Returns (diff_id, digest, size).

    gzip gets mtime=0 deliberately: the header timestamp would otherwise change
    the layer digest for identical bytes on every run, which is the trap I6.9
    avoids with `gzip -n`."""
    plain = io.BytesIO()
    with tarfile.open(fileobj=plain, mode="w", format=tarfile.GNU_FORMAT) as tf:
        needed = set()
        for rel in changed:
            parts = rel.split(os.sep)
            for i in range(1, len(parts) + 1):
                needed.add(os.sep.join(parts[:i]))
        for rel in sorted(needed):
            full = os.path.join(root, rel)
            if not os.path.lexists(full):
                continue
            info = tf.gettarinfo(full, arcname=rel)
            info.uname = info.gname = ""          # numeric owner only
            if info.isreg():
                with open(full, "rb") as fh:
                    tf.addfile(info, fh)
            else:
                tf.addfile(info)
        for rel in deleted:
            head, tail = os.path.split(rel)
            if any(d == head or head.startswith(d + os.sep) for d in deleted):
                continue                          # parent already whited out
            wh = tarfile.TarInfo(os.path.join(head, ".wh." + tail))
            wh.mode, wh.mtime, wh.size = 0, 0, 0
            tf.addfile(wh)

    raw = plain.getvalue()
    diff_id = "sha256:" + hashlib.sha256(raw).hexdigest()
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", compresslevel=9, mtime=0) as gz:
        gz.write(raw)
    blob = buf.getvalue()
    digest = "sha256:" + hashlib.sha256(blob).hexdigest()
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as fh:
        fh.write(blob)
    return diff_id, digest, len(blob)


# ------------------------------------------------------------------- FROM

def apply_base(ref, rootfs, workdir):
    """Pull ref with pull.py, extract its layers in order, return its config.

    pull.py is called by swapping sys.argv rather than by refactoring it: it is
    I5's deliverable and it stays exactly as it shipped."""
    layout = os.path.join(workdir, "base")
    log(f"  FROM {ref}")
    saved, sys.argv = sys.argv, ["pull.py", ref, layout]
    try:
        pull.main()
    finally:
        sys.argv = saved
    index = json.load(open(os.path.join(layout, "index.json")))
    man = read_blob_json(layout, index["manifests"][0]["digest"])
    cfg = read_blob_json(layout, man["config"]["digest"])
    for i, layer in enumerate(man["layers"], 1):
        path = blob_path(layout, layer["digest"])
        log(f"    applying layer {i}/{len(man['layers'])}")
        extract_layer(path, rootfs)
    return cfg


def blob_path(layout, digest):
    algo, _, hexd = digest.partition(":")
    return os.path.join(layout, "blobs", algo, hexd)


def read_blob_json(layout, digest):
    return json.load(open(blob_path(layout, digest)))


def extract_layer(path, rootfs):
    """Apply one layer tar, honouring .wh. whiteouts (image-spec layer.md)."""
    with tarfile.open(path, mode="r:*") as tf:
        for member in tf:
            base = os.path.basename(member.name)
            if base.startswith(".wh."):
                target = os.path.join(rootfs, os.path.dirname(member.name),
                                      base[len(".wh."):])
                if os.path.isdir(target) and not os.path.islink(target):
                    shutil.rmtree(target, ignore_errors=True)
                elif os.path.lexists(target):
                    os.remove(target)
                continue
            dest = os.path.join(rootfs, member.name)
            if os.path.lexists(dest) and not member.isdir():
                os.remove(dest)
            tf.extract(member, rootfs, set_attrs=True, numeric_owner=True)


# -------------------------------------------------------------------- RUN

def run_step(command, rootfs, workdir, env):
    """The one step that genuinely needs a container. Everything else in this
    program is file manipulation; this is I2's bundle and I3's runc."""
    bundle = os.path.join(workdir, "bundle")
    os.makedirs(bundle, exist_ok=True)
    spec = subprocess.run(["runc", "spec", "--rootless=false"], cwd=bundle,
                          capture_output=True, text=True)
    if spec.returncode:
        die(f"runc spec failed: {spec.stderr.strip()}")
    cfg = json.load(open(os.path.join(bundle, "config.json")))
    cfg["process"]["args"] = ["/bin/sh", "-c", command]
    cfg["process"]["terminal"] = False
    cfg["process"]["cwd"] = "/"
    cfg["process"]["env"] = [f"PATH={env.get('PATH', '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin')}"] + \
                            [f"{k}={v}" for k, v in env.items() if k != "PATH"]
    cfg["root"] = {"path": os.path.abspath(rootfs), "readonly": False}
    json.dump(cfg, open(os.path.join(bundle, "config.json"), "w"), indent=2)

    cid = "tinybuild-" + hashlib.sha256(command.encode()).hexdigest()[:12]
    subprocess.run(["runc", "delete", "-f", cid], capture_output=True)
    proc = subprocess.run(["runc", "run", cid], cwd=bundle)
    subprocess.run(["runc", "delete", "-f", cid], capture_output=True)
    if proc.returncode:
        die(f"RUN exited {proc.returncode}: {command}")


# ------------------------------------------------------------------- COPY

def copy_step(arg, rootfs, context):
    words = arg.split()
    if len(words) < 2:
        die(f"COPY needs a source and a destination: {arg!r}")
    *srcs, dst = words
    for src in srcs:
        s = os.path.join(context, src)
        if not os.path.lexists(s):
            die(f"COPY source not in the build context: {src}")
        d = os.path.join(rootfs, dst.lstrip("/"))
        if dst.endswith("/") or os.path.isdir(d):
            os.makedirs(d, exist_ok=True)
            d = os.path.join(d, os.path.basename(src.rstrip("/")))
        else:
            os.makedirs(os.path.dirname(d) or "/", exist_ok=True)
        if os.path.isdir(s):
            shutil.copytree(s, d, symlinks=True, dirs_exist_ok=True)
        else:
            shutil.copy2(s, d, follow_symlinks=False)


# ------------------------------------------------------------------- push

def push(layout, ref, manifest_desc):
    """pull.py in reverse, and I5.9's order is the whole consistency model:
    every blob must exist before the manifest that names it."""
    endpoint, name, tag = pull.parse_ref(ref)
    man = read_blob_json(layout, manifest_desc["digest"])
    blobs = [man["config"]] + man["layers"]
    for desc in blobs:
        if head_blob(endpoint, name, desc["digest"]):
            log(f"    exists   {desc['digest'][:19]}")
            continue
        put_blob(endpoint, name, desc["digest"], blob_path(layout, desc["digest"]))
        log(f"    uploaded {desc['digest'][:19]}  {desc['size']} bytes")
    body = open(blob_path(layout, manifest_desc["digest"]), "rb").read()
    req = urllib.request.Request(f"{endpoint}/v2/{name}/manifests/{tag}",
                                 data=body, method="PUT")
    req.add_header("Content-Type", manifest_desc["mediaType"])
    with urllib.request.urlopen(req) as resp:
        log(f"  pushed {endpoint}/v2/{name}/manifests/{tag} -> {resp.status}")


def head_blob(endpoint, name, digest):
    req = urllib.request.Request(f"{endpoint}/v2/{name}/blobs/{digest}",
                                 method="HEAD")
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status == 200
    except urllib.error.HTTPError:
        return False


def put_blob(endpoint, name, digest, path):
    req = urllib.request.Request(f"{endpoint}/v2/{name}/blobs/uploads/",
                                 data=b"", method="POST")
    with urllib.request.urlopen(req) as resp:
        location = resp.headers["Location"]
    # The spec allows Location to be absolute or relative, and registry:2
    # returns absolute WITH a query string already attached -- so join it
    # carefully and append the digest with & rather than ? (I6.9).
    if location.startswith("/"):
        location = endpoint + location
    sep = "&" if "?" in location else "?"
    req = urllib.request.Request(f"{location}{sep}digest={digest}",
                                 data=open(path, "rb").read(), method="PUT")
    req.add_header("Content-Type", "application/octet-stream")
    with urllib.request.urlopen(req) as resp:
        if resp.status != 201:
            die(f"blob PUT returned {resp.status} for {digest}")


# -------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="build an OCI image with no builder")
    ap.add_argument("dockerfile")
    ap.add_argument("-C", "--context", default=".")
    ap.add_argument("-o", "--layout", default="./tinybuild-out")
    ap.add_argument("--push", metavar="REF")
    ap.add_argument("--dry-run", action="store_true",
                    help="parse and classify the instructions, build nothing")
    args = ap.parse_args()

    steps = parse_dockerfile(args.dockerfile)
    if args.dry_run:
        for verb, arg in steps:
            kind = "layer " if verb in ("RUN", "COPY") else "config"
            print(f"  {kind}  {verb} {arg[:70]}")
        return
    if os.geteuid() != 0:
        die("run me under sudo: RUN needs runc, and base-image layers contain "
            "files owned by other users")

    workdir = tempfile.mkdtemp(prefix="tinybuild-")
    rootfs = os.path.join(workdir, "rootfs")
    os.makedirs(rootfs)
    blobs = os.path.join(args.layout, "blobs", "sha256")
    os.makedirs(blobs, exist_ok=True)

    env, cmd, diff_ids, layers, history = {}, None, [], [], []
    base_cfg = None

    for verb, arg in steps:
        if verb == "FROM":
            if arg == "scratch":
                log("  FROM scratch")
            else:
                base_cfg = apply_base(arg, rootfs, workdir)
                for k in base_cfg.get("config", {}).get("Env", []):
                    key, _, val = k.partition("=")
                    env[key] = val
                cmd = base_cfg.get("config", {}).get("Cmd")
                diff_ids += base_cfg["rootfs"]["diff_ids"]
                history += base_cfg.get("history", [])
                base_layout = os.path.join(workdir, "base")
                index = json.load(open(os.path.join(base_layout, "index.json")))
                man = read_blob_json(base_layout, index["manifests"][0]["digest"])
                for layer in man["layers"]:
                    shutil.copy(blob_path(base_layout, layer["digest"]),
                                os.path.join(blobs, layer["digest"].split(":")[1]))
                    layers.append(layer)
            continue

        if verb in ("ENV", "CMD"):
            if verb == "ENV":
                key, _, val = arg.partition("=")
                env[key.strip()] = val.strip()
            else:
                cmd = json.loads(arg) if arg.startswith("[") else ["/bin/sh", "-c", arg]
            history.append({"created_by": f"{verb} {arg}", "empty_layer": True,
                            "comment": "tinybuild.py"})
            log(f"  {verb} {arg}   (config only, no layer)")
            continue

        before = snapshot(rootfs)
        if verb == "RUN":
            log(f"  RUN {arg}")
            run_step(arg, rootfs, workdir, env)
        else:
            log(f"  COPY {arg}")
            copy_step(arg, rootfs, args.context)
        changed, deleted = diff_paths(before, snapshot(rootfs))
        if not changed and not deleted:
            log("    no filesystem change -> still a layer slot, and it is the "
                "empty layer (I6.1)")
        tmp = os.path.join(workdir, "layer.tar.gz")
        diff_id, digest, size = write_layer(rootfs, changed, deleted, tmp)
        shutil.move(tmp, os.path.join(blobs, digest.split(":")[1]))
        diff_ids.append(diff_id)
        layers.append({"mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                       "digest": digest, "size": size})
        history.append({"created_by": f"{verb} {arg}", "comment": "tinybuild.py"})
        log(f"    +{len(changed)} changed, -{len(deleted)} deleted -> "
            f"{digest[:19]}  {size} bytes")

    config = {
        "architecture": (base_cfg or {}).get("architecture", "amd64"),
        "os": (base_cfg or {}).get("os", "linux"),
        "config": {"Env": [f"{k}={v}" for k, v in env.items()],
                   **({"Cmd": cmd} if cmd else {})},
        "rootfs": {"type": "layers", "diff_ids": diff_ids},
        "history": history,
    }
    cfg_bytes = json.dumps(config, indent=2).encode()
    cfg_digest = "sha256:" + hashlib.sha256(cfg_bytes).hexdigest()
    open(os.path.join(blobs, cfg_digest.split(":")[1]), "wb").write(cfg_bytes)

    manifest = {"schemaVersion": 2,
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "config": {"mediaType": "application/vnd.oci.image.config.v1+json",
                           "digest": cfg_digest, "size": len(cfg_bytes)},
                "layers": layers}
    man_bytes = json.dumps(manifest, indent=2).encode()
    man_digest = "sha256:" + hashlib.sha256(man_bytes).hexdigest()
    open(os.path.join(blobs, man_digest.split(":")[1]), "wb").write(man_bytes)
    man_desc = {"mediaType": manifest["mediaType"], "digest": man_digest,
                "size": len(man_bytes),
                "platform": {"architecture": config["architecture"], "os": config["os"]}}

    open(os.path.join(args.layout, "oci-layout"), "w").write(
        json.dumps({"imageLayoutVersion": "1.0.0"}))
    json.dump({"schemaVersion": 2,
               "mediaType": "application/vnd.oci.image.index.v1+json",
               "manifests": [man_desc]},
              open(os.path.join(args.layout, "index.json"), "w"), indent=2)

    log(f"\n  layers   {len(layers)}")
    log(f"  config   {cfg_digest}")
    log(f"  manifest {man_digest}")
    log(f"  layout   {args.layout}")
    if args.push:
        log(f"\n  pushing to {args.push} (blobs first, manifest last)")
        push(args.layout, args.push, man_desc)
    shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
