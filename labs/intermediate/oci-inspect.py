#!/usr/bin/env python3
"""oci-inspect.py - walk an OCI image layout, verify every digest, build a rootfs.

Usage:  oci-inspect.py LAYOUT_DIR TAG [--platform linux/amd64] [--extract DIR]

Nothing here is clever. It is the OCI image spec, transcribed:
an index points at manifests, a manifest points at a config and layers,
and every one of those pointers is a descriptor (mediaType + digest + size).
"""
import argparse, gzip, hashlib, json, os, shutil, sys, tarfile

def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)

def blob_path(layout, digest):
    algo, hex_ = digest.split(":", 1)
    return os.path.join(layout, "blobs", algo, hex_)

def verify(layout, desc, what):
    """Recompute the digest of a blob and compare it with what the descriptor claims."""
    path = blob_path(layout, desc["digest"])
    if not os.path.exists(path):
        die(f"{what}: blob {desc['digest']} is missing from the layout")
    h = hashlib.sha256()
    size = 0
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
            size += len(chunk)
    got = "sha256:" + h.hexdigest()
    ok_digest = got == desc["digest"]
    ok_size = size == desc.get("size", size)
    status = "OK" if (ok_digest and ok_size) else "MISMATCH"
    print(f"  [{status}] {what:<28} {desc['digest'][:26]}... {size:>9} bytes")
    if not ok_digest:
        print(f"      claimed {desc['digest']}", file=sys.stderr)
        print(f"      actual  {got}", file=sys.stderr)
        die("digest verification failed - the blob is not what the manifest says it is")
    if not ok_size:
        die(f"size mismatch: manifest says {desc['size']}, blob is {size}")
    return path

def load_json(layout, desc, what):
    return json.load(open(verify(layout, desc, what), "rb"))

def pick_manifest(index, want):
    """Select one manifest for the requested platform.

    Real-world wrinkle: a modern Docker Hub index also carries BuildKit
    attestation manifests, whose platform is literally unknown/unknown.
    They are not images. Skip them or you will 'select' one.
    """
    want_os, want_arch = want.split("/", 1)
    candidates = []
    for m in index["manifests"]:
        p = m.get("platform") or {}
        if p.get("architecture") == "unknown" or p.get("os") == "unknown":
            continue
        if m.get("annotations", {}).get("vnd.docker.reference.type") == "attestation-manifest":
            continue
        if p.get("os") == want_os and p.get("architecture") == want_arch:
            candidates.append(m)
    if not candidates:
        have = sorted({f"{(m.get('platform') or {}).get('os')}/"
                       f"{(m.get('platform') or {}).get('architecture')}"
                       for m in index["manifests"]})
        die(f"no image found for platform {want}; the index offers {', '.join(have)}")
    return candidates[0]

def chain_ids(diff_ids):
    """chainID[0] = diff_id[0]; chainID[n] = sha256("<chainID[n-1]> <diff_id[n]>")."""
    out = [diff_ids[0]]
    for d in diff_ids[1:]:
        h = hashlib.sha256(f"{out[-1]} {d}".encode()).hexdigest()
        out.append("sha256:" + h)
    return out

def apply_layer(tar_path, root):
    """Extract one layer over root, honouring whiteouts.

    A whiteout is a tar ENTRY, not a device node: '.wh.<name>' deletes a
    sibling, '.wh..wh..opq' hides every child of its own directory.
    """
    removed = []
    with tarfile.open(tar_path, "r:*") as tf:
        for member in tf:
            base = os.path.basename(member.name)
            parent = os.path.dirname(member.name)
            if base == ".wh..wh..opq":
                target_dir = os.path.join(root, parent)
                if os.path.isdir(target_dir):
                    for child in os.listdir(target_dir):
                        victim = os.path.join(target_dir, child)
                        shutil.rmtree(victim, ignore_errors=True) if os.path.isdir(victim) \
                            and not os.path.islink(victim) else os.remove(victim)
                        removed.append(os.path.join(parent, child))
                continue
            if base.startswith(".wh."):
                victim = os.path.join(root, parent, base[4:])
                if os.path.isdir(victim) and not os.path.islink(victim):
                    shutil.rmtree(victim, ignore_errors=True)
                elif os.path.lexists(victim):
                    os.remove(victim)
                removed.append(os.path.join(parent, base[4:]))
                continue
            # An ordinary entry replaces whatever is already there.
            dest = os.path.join(root, member.name)
            if os.path.lexists(dest) and not member.isdir():
                if os.path.isdir(dest) and not os.path.islink(dest):
                    shutil.rmtree(dest, ignore_errors=True)
                else:
                    os.remove(dest)
            tf.extract(member, root, filter="tar")
    return removed

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("layout")
    ap.add_argument("tag")
    ap.add_argument("--platform", default="linux/amd64")
    ap.add_argument("--extract", metavar="DIR")
    args = ap.parse_args()

    layout_file = os.path.join(args.layout, "oci-layout")
    if not os.path.exists(layout_file):
        die(f"{args.layout} is not an OCI layout (no oci-layout file)")
    print(f"layout version: {json.load(open(layout_file))['imageLayoutVersion']}")

    index = json.load(open(os.path.join(args.layout, "index.json")))
    matches = [m for m in index["manifests"]
               if m.get("annotations", {}).get("org.opencontainers.image.ref.name") == args.tag]
    if not matches:
        # A layout written by skopeo tags one manifest; a registry index does not.
        top = index
    else:
        top = {"manifests": [matches[0]]}

    print(f"\nresolving tag {args.tag!r} for platform {args.platform}")
    desc = matches[0] if matches else None
    if desc and desc["mediaType"].endswith("index.v1+json"):
        inner = load_json(args.layout, desc, "index")
        desc = pick_manifest(inner, args.platform)
    elif not desc:
        desc = pick_manifest(index, args.platform)

    print("\nverifying every digest by recomputing it:")
    manifest = load_json(args.layout, desc, "manifest")
    config = load_json(args.layout, manifest["config"], "config")

    # A layout written by `skopeo copy` (no --all) holds ONE platform, reached
    # by tag, with no index to select from. Selection cannot catch a mismatch
    # there, so check the config itself -- otherwise --platform is silently a lie.
    got = f"{config['os']}/{config['architecture']}"
    if got != args.platform:
        die(f"no image found for platform {args.platform}; "
            f"this layout's {args.tag!r} is {got}")
    layer_paths = [verify(args.layout, l, f"layer[{i}]")
                   for i, l in enumerate(manifest["layers"])]

    print(f"\nimage: {config['os']}/{config['architecture']}"
          f"  created {config.get('created', '?')}")
    print(f"  Entrypoint : {config['config'].get('Entrypoint')}")
    print(f"  Cmd        : {config['config'].get('Cmd')}")
    print(f"  Env        : {config['config'].get('Env')}")
    print(f"  WorkingDir : {config['config'].get('WorkingDir')!r}")
    print(f"  User       : {config['config'].get('User') or '(unset -> uid 0)'}")

    diff_ids = config["rootfs"]["diff_ids"]
    print(f"\n{len(diff_ids)} layer(s); diff_id -> chain ID:")
    for i, (d, c) in enumerate(zip(diff_ids, chain_ids(diff_ids))):
        print(f"  [{i}] diff_id  {d}")
        print(f"      chainID  {c}   <- what the snapshotter caches on")

    hist = config.get("history", [])
    empties = sum(1 for h in hist if h.get("empty_layer"))
    print(f"\nhistory: {len(hist)} entries, {empties} of them empty_layer "
          f"(so {len(hist) - empties} produced a layer, matching {len(diff_ids)})")

    if args.extract:
        root = args.extract
        os.makedirs(root, exist_ok=True)
        print(f"\nextracting {len(layer_paths)} layer(s) into {root}/ in order:")
        for i, p in enumerate(layer_paths):
            removed = apply_layer(p, root)
            note = f", {len(removed)} path(s) whited out" if removed else ""
            print(f"  applied layer[{i}]{note}")
            for r in removed:
                print(f"      deleted {r}")
        print(f"\nrootfs ready: {root}")

if __name__ == "__main__":
    main()
