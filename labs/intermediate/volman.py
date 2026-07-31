#!/usr/bin/env python3
"""volman.py - a local volume manager, in about two hundred lines.

The point of this program is that it is boring. Every operation below is one of
the CSI calls from I10.8, done locally with no gRPC and no Kubernetes, and the
comments name the call each one stands in for. A "volume" turns out to be:

    an ext4 image file  +  a mount somewhere  +  a name in a JSON file

    create   ~ CreateVolume          (Controller) - make the storage exist
    stage    ~ NodeStageVolume       (Node)  - mount it once, on this machine
    attach   ~ NodePublishVolume     (Node)  - bind it into one container
    detach   ~ NodeUnpublishVolume   (Node)  - remove that container's bind
    unstage  ~ NodeUnstageVolume     (Node)  - unmount the machine-wide mount
    rm       ~ DeleteVolume          (Controller) - destroy the storage

The size limit is real, not advisory, because each volume is a filesystem of its
own on a loop device - which is the only way to get quota semantics for a
directory, and the reason ordinary bind mounts cannot be size-limited.

    sudo volman.py create data --size 32M
    sudo volman.py attach data ~/i10/vol --dest /data
    sudo runc run box
    sudo volman.py ls
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

ROOT = "/var/lib/volman"
IMAGES = f"{ROOT}/images"
MNT = f"{ROOT}/mnt"
STATE = f"{ROOT}/volumes.json"


def sh(*cmd, check=True):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check and r.returncode:
        sys.exit(f"volman: {' '.join(cmd)}: {r.stderr.strip() or r.stdout.strip()}")
    return r


def load():
    if not os.path.exists(STATE):
        return {}
    with open(STATE) as f:
        return json.load(f)


def save(db):
    os.makedirs(ROOT, exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(db, f, indent=2)
    os.replace(tmp, STATE)          # the whole of this program's crash-safety


def is_mounted(path):
    return os.path.ismount(path)


# --------------------------------------------------------------- Controller
def cmd_create(args):
    """~ CreateVolume. Make the storage exist. Nothing is mounted yet, and no
    container is involved - this could run on a different machine entirely."""
    db = load()
    if args.name in db:
        sys.exit(f"volman: volume {args.name!r} already exists")
    os.makedirs(IMAGES, exist_ok=True)
    img = f"{IMAGES}/{args.name}.img"
    sh("truncate", "-s", args.size, img)
    sh("mkfs.ext4", "-q", "-F", img)
    db[args.name] = {"image": img, "size": args.size, "staged": None, "published": []}
    save(db)
    print(f"created {args.name} ({args.size}) -> {img}")


def cmd_rm(args):
    """~ DeleteVolume. Refuses while anything still holds it - which is exactly
    the check the hostpath driver skips, and how you end up with a mount whose
    source says //deleted."""
    db = load()
    v = db.get(args.name) or sys.exit(f"volman: no such volume {args.name!r}")
    if v["published"]:
        sys.exit(f"volman: {args.name} is still published to {v['published']}")
    if v["staged"]:
        sys.exit(f"volman: {args.name} is still staged at {v['staged']}")
    os.remove(v["image"])
    del db[args.name]
    save(db)
    print(f"deleted {args.name}")


# --------------------------------------------------------------------- Node
def cmd_stage(args):
    """~ NodeStageVolume. Once per machine: attach the loop device and mount.
    Idempotent on purpose - the spec requires it, and the second pod on this
    node must not pay for it again."""
    db = load()
    v = db.get(args.name) or sys.exit(f"volman: no such volume {args.name!r}")
    target = f"{MNT}/{args.name}"
    if v["staged"] and is_mounted(target):
        print(f"already staged at {target} (no work done)")
        return target
    os.makedirs(target, exist_ok=True)
    sh("mount", "-o", "loop", v["image"], target)
    if args.owner:                      # the fsGroup-style chown, done once here
        uid, _, gid = args.owner.partition(":")
        sh("chown", "-R", f"{uid}:{gid or uid}", target)
    v["staged"] = target
    save(db)
    print(f"staged {args.name} at {target}")
    return target


def cmd_unstage(args):
    db = load()
    v = db.get(args.name) or sys.exit(f"volman: no such volume {args.name!r}")
    if v["published"]:
        sys.exit(f"volman: {args.name} is still published to {v['published']}")
    if v["staged"]:
        sh("umount", v["staged"])
        shutil.rmtree(v["staged"], ignore_errors=True)
        v["staged"] = None
        save(db)
    print(f"unstaged {args.name}")


def cmd_attach(args):
    """~ NodePublishVolume. Bind the staged mount into one container, by adding
    a single entry to its config.json - I10.4's mounts array, written by a
    program instead of by hand. Staging first if needed, like the kubelet."""
    db = load()
    v = db.get(args.name) or sys.exit(f"volman: no such volume {args.name!r}")
    if not (v["staged"] and is_mounted(v["staged"])):
        cmd_stage(argparse.Namespace(name=args.name, owner=args.owner))
        db = load()
        v = db[args.name]

    cfg_path = os.path.join(args.bundle, "config.json")
    with open(cfg_path) as f:
        cfg = json.load(f)
    cfg["mounts"] = [m for m in cfg["mounts"] if m["destination"] != args.dest]
    cfg["mounts"].append({
        "destination": args.dest,
        "type": "bind",
        "source": v["staged"],
        "options": ["rbind", "rw"],
    })
    with open(cfg_path, "w") as f:
        json.dump(cfg, f, indent=2)
    if args.bundle not in v["published"]:
        v["published"].append(args.bundle)
    save(db)
    print(f"attached {args.name} -> {args.dest} in {cfg_path}")


def cmd_detach(args):
    """~ NodeUnpublishVolume. Remove that one container's reference. The volume
    and its data are untouched: that is the entire value proposition."""
    db = load()
    v = db.get(args.name) or sys.exit(f"volman: no such volume {args.name!r}")
    cfg_path = os.path.join(args.bundle, "config.json")
    if os.path.exists(cfg_path):
        with open(cfg_path) as f:
            cfg = json.load(f)
        cfg["mounts"] = [m for m in cfg["mounts"] if m.get("source") != v["staged"]]
        with open(cfg_path, "w") as f:
            json.dump(cfg, f, indent=2)
    v["published"] = [b for b in v["published"] if b != args.bundle]
    save(db)
    print(f"detached {args.name} from {args.bundle}")


def cmd_ls(args):
    db = load()
    if not db:
        print("no volumes")
        return
    print(f"{'NAME':12s} {'SIZE':6s} {'USED':8s} {'STAGED':34s} PUBLISHED")
    for name, v in sorted(db.items()):
        used = "-"
        if v["staged"] and is_mounted(v["staged"]):
            st = os.statvfs(v["staged"])
            used = f"{(st.f_blocks - st.f_bfree) * st.f_frsize // 1024}K"
        print(f"{name:12s} {v['size']:6s} {used:8s} {str(v['staged'] or '-'):34s} "
              f"{len(v['published'])}")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("create"); c.add_argument("name"); c.add_argument("--size", default="32M"); c.set_defaults(fn=cmd_create)
    c = sub.add_parser("rm"); c.add_argument("name"); c.set_defaults(fn=cmd_rm)
    c = sub.add_parser("stage"); c.add_argument("name"); c.add_argument("--owner"); c.set_defaults(fn=cmd_stage)
    c = sub.add_parser("unstage"); c.add_argument("name"); c.set_defaults(fn=cmd_unstage)
    c = sub.add_parser("attach"); c.add_argument("name"); c.add_argument("bundle"); c.add_argument("--dest", default="/data"); c.add_argument("--owner"); c.set_defaults(fn=cmd_attach)
    c = sub.add_parser("detach"); c.add_argument("name"); c.add_argument("bundle"); c.set_defaults(fn=cmd_detach)
    c = sub.add_parser("ls"); c.set_defaults(fn=cmd_ls)
    args = p.parse_args()
    if os.geteuid() != 0:
        sys.exit("volman: needs root (it mounts things)")
    args.fn(args)


if __name__ == "__main__":
    main()
