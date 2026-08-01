#!/usr/bin/env bash
# I13 gauntlet fault i13-config-01 (I13.7, layer 3 · runtime) — plants ONE
# fault: a malformed config.json, on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash i13-config-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.i13-fault-backups
BUNDLE=/root/i13-config-bundle
CID=i13-config-gauntlet

echo "============================================================"
echo " I13 gauntlet — fault i13-config-01"
echo " About to BREAK: layer 3, runtime (malformed config.json)"
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
for c in sh echo cat; do ln -sf busybox "$BUNDLE/rootfs/bin/$c"; done
(cd "$BUNDLE" && runc spec)
python3 - "$BUNDLE/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["process"]["args"] = ["/bin/sh", "-c", "echo config-ok"]
c["process"]["terminal"] = False
json.dump(c, open(p, "w"))
PY

if ! (cd "$BUNDLE" && timeout 10 runc run "$CID" 2>/tmp/i13-config-check.log | grep -q config-ok); then
  echo "ABORT: the bundle will not even run cleanly before the fault is planted." >&2
  cat /tmp/i13-config-check.log >&2; exit 1
fi
runc delete -f "$CID" >/dev/null 2>&1 || true

mkdir -p "$BACKUPS"
cp "$BUNDLE/config.json" "$BACKUPS/config-01.config.json.$(date +%Y%m%d-%H%M%S)"

# ---- plant: drop the /proc mount from the bundle's mount list ----
python3 - "$BUNDLE/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["mounts"] = [m for m in c["mounts"] if m["destination"] != "/proc"]
json.dump(c, open(p, "w"))
PY

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. $BUNDLE is a bundle that ran cleanly a moment ago. It will not run now."
echo "  2. Read runc's own error carefully — it is unusually informative here."
echo "  3. Fix config.json and verify:"
echo "       cd $BUNDLE && sudo runc run i13fix"
echo "     should print 'config-ok', not an error."
echo
echo "Escape hatch (only if hopelessly stuck): a backup of the working config.json"
echo "is in $BACKUPS/config-01.config.json.*"
echo "Hints & solution: materials/i13.html -> lesson I13.7, staged reveals (fault 3)."
