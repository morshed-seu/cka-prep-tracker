#!/usr/bin/env bash
# Beginner gauntlet fault b14-mount-01 (B14.5) — plants ONE fault in the
# filesystem/mount layer on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash b14-mount-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.b14-fault-backups
DATA=/srv/gauntlet/data

echo "============================================================"
echo " Beginner gauntlet — fault b14-mount-01"
echo " About to BREAK: a directory full of files (they are not deleted)"
echo " Intended target: the throwaway 'sandbox' VM (never a cluster node)"
echo "============================================================"

# ---- wrong-box guards ----
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
if mountpoint -q "$DATA"; then
  echo "ABORT: $DATA is already a mount point — a fault may still be planted." >&2
  echo "Unmount it first, then re-run." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent) ----
install -d -m 755 /srv/gauntlet "$DATA"
echo 'the-answer-is-42' > "$DATA/config.txt"
echo 'v1.4.2'          > "$DATA/version.txt"
echo 'accounts,orders' > "$DATA/tables.txt"
chmod 644 "$DATA"/*.txt

mkdir -p "$BACKUPS"
ls -1 "$DATA" > "$BACKUPS/mount-01.filelist.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
mount -t tmpfs -o size=1M,mode=755 gauntlet-none "$DATA"

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. Three files that were in $DATA a moment ago are gone."
echo "  2. Nothing was deleted, nothing was moved, and no permission changed."
echo "  3. Get them back, then verify all three are readable again:"
echo "       cat $DATA/config.txt   →  the-answer-is-42"
echo "       ls $DATA | wc -l       →  3"
echo "  4. Do not recreate the files by hand — recover the originals."
echo
echo "Escape hatch (only if hopelessly stuck): the expected file list is in"
echo "$BACKUPS/mount-01.filelist.* — but restoring it is not the fix."
echo "Hints & solution: materials/b14.html → lesson B14.5, staged reveals."
