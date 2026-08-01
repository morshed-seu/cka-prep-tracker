#!/usr/bin/env bash
# I13 gauntlet fault i13-shim-01 (I13.7, layer 3 · shim) — plants ONE fault:
# an orphaned container supervisor, on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash i13-shim-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.i13-fault-backups
BUNDLE=/root/i13-shim-bundle
CID=i13-shim-gauntlet

echo "============================================================"
echo " I13 gauntlet — fault i13-shim-01"
echo " About to BREAK: layer 3, shim (an orphaned supervisor)"
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
for bin in runc python3; do
  command -v "$bin" >/dev/null || { echo "ABORT: $bin not found — is the intermediate toolchain installed?" >&2; exit 1; }
done

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent): a plain runc bundle, verified working ----
runc delete -f "$CID" >/dev/null 2>&1 || true
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/rootfs/bin" "$BUNDLE/rootfs/proc"
cp /usr/bin/busybox "$BUNDLE/rootfs/bin/busybox"
for c in sh sleep; do ln -sf busybox "$BUNDLE/rootfs/bin/$c"; done
(cd "$BUNDLE" && runc spec)
python3 - "$BUNDLE/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["process"]["args"] = ["/bin/sh", "-c", "while :; do sleep 1; done"]
c["process"]["terminal"] = False
json.dump(c, open(p, "w"))
PY

# `runc run` (no -d) IS the supervisor: it creates, starts and then waits on
# the container. Backgrounding the shell job is what lets this script kill
# that supervisor a moment later without also killing the container.
(cd "$BUNDLE" && runc run "$CID") &
SUPERVISOR_PID=$!
sleep 2
CTR_PID=$(runc state "$CID" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pid"])')
if ! kill -0 "$CTR_PID" 2>/dev/null; then
  echo "ABORT: the bundle will not even run cleanly before the fault is planted." >&2
  exit 1
fi

mkdir -p "$BACKUPS"
echo "$CID supervisor pid $SUPERVISOR_PID, container init pid $CTR_PID, both healthy" \
  > "$BACKUPS/shim-01.note.$(date +%Y%m%d-%H%M%S)"

# ---- plant: kill the supervisor. The container's init process is reparented
# to PID 1 and keeps running — nothing is left watching it, and it was never
# created through containerd, so crictl/ctr know nothing about it either.
kill -9 "$SUPERVISOR_PID" 2>/dev/null || true
sleep 1

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. Something is running on this machine that crictl and ctr both say"
echo "     nothing about."
echo "  2. Find it, work out what it is, and clean it up — the goal is a machine"
echo "     with no i13-shim-gauntlet processes and no stale runc records left."
echo "  3. Verify:"
echo "       ps -eo pid,ppid,comm | grep -c 'sh$'   -> back to its baseline count"
echo "       sudo runc list                          -> does not mention $CID"
echo
echo "Escape hatch (only if hopelessly stuck): a note naming the container ID is"
echo "in $BACKUPS/shim-01.note.*"
echo "Hints & solution: materials/i13.html -> lesson I13.7, staged reveals (fault 4)."
