#!/usr/bin/env bash
# I13 gauntlet fault i13-snapshot-01 (I13.7, layer 2 · snapshotter) — plants
# ONE fault: a snapshotter/GC leak, on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash i13-snapshot-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.i13-fault-backups
SNAP=i13-leak-snap
LEAKFILE=/var/lib/containerd/i13-leak.tmp
MNT=/var/lib/i13-leak-mnt

echo "============================================================"
echo " I13 gauntlet — fault i13-snapshot-01"
echo " About to BREAK: layer 2, snapshotter (a disk-space leak)"
echo " Intended target: the throwaway 'sandbox' VM (never a cluster node)"
echo "============================================================"

if [ "$(id -u)" -ne 0 ]; then
  echo "ABORT: run with sudo." >&2; exit 1
fi
if [ "$(hostname)" != "sandbox" ]; then
  echo "ABORT: this host is '$(hostname)', not the throwaway 'sandbox' VM." >&2
  echo "Refusing to break a machine that isn't the sandbox." >&2; exit 1
fi
if [ -d /etc/kubernetes ]; then
  echo "ABORT: /etc/kubernetes exists — this looks like a cluster node." >&2; exit 1
fi
command -v ctr >/dev/null || { echo "ABORT: ctr not found." >&2; exit 1; }
AVAIL_KB=$(df -k --output=avail / | tail -1)
if [ "$AVAIL_KB" -lt 512000 ]; then
  echo "ABORT: less than 500 MiB free on / — too little headroom to plant this safely." >&2
  exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent): clear any previous run's leak first ----
ctr -n k8s.io snapshot rm "$SNAP" >/dev/null 2>&1 || true
pkill -f "[i]13-leak.tmp" >/dev/null 2>&1 || true
rm -f "$LEAKFILE"
BEFORE_KB=$(df -k --output=avail / | tail -1)

mkdir -p "$BACKUPS"
echo "free space before planting: ${BEFORE_KB} KiB" > "$BACKUPS/snapshot-01.note.$(date +%Y%m%d-%H%M%S)"

# ---- plant 1: an orphaned, uncommitted snapshot — real disk, no image owns it.
ctr -n k8s.io snapshot prepare "$SNAP" "" >/dev/null
mkdir -p "$MNT"
eval "$(ctr -n k8s.io snapshot mounts "$MNT" "$SNAP")"
dd if=/dev/urandom of="$MNT/junk.bin" bs=1M count=80 >/dev/null 2>&1
umount "$MNT"
rmdir "$MNT"

# ---- plant 2: a deleted-but-open file — `du` and a naive `rm` both lie about
# this space until the process holding it dies, exactly like I12.10.
bash -c "exec 9>'$LEAKFILE'; dd if=/dev/zero of=/proc/self/fd/9 bs=1M count=50 2>/dev/null; rm -f '$LEAKFILE'; sleep 3600" &
disown

sleep 1
AFTER_KB=$(df -k --output=avail / | tail -1)

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. Free space on / just dropped by roughly $(( (BEFORE_KB - AFTER_KB) / 1024 )) MiB."
echo "  2. crictl images / ctr images ls do not explain where it went."
echo "  3. Find both leaks and reclaim the space. Verify:"
echo "       df -k --output=avail /   -> back within a few MiB of ${BEFORE_KB} KiB"
echo
echo "Escape hatch (only if hopelessly stuck): the free-space baseline is in"
echo "$BACKUPS/snapshot-01.note.*"
echo "Hints & solution: materials/i13.html -> lesson I13.7, staged reveals (fault 7)."
