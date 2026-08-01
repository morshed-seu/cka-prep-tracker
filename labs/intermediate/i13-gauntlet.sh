#!/usr/bin/env bash
# I13 gauntlet runner (I13.7 / I13.9) — plants ALL EIGHT faults in one go for
# the timed run. Each individual script keeps its own guards and setup.
# Run on the sandbox VM:  sudo bash i13-gauntlet.sh
# Do not read the individual scripts before the run — they name the faults.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
FAULTS=(
  i13-registry-01.sh
  i13-blob-01.sh
  i13-config-01.sh
  i13-shim-01.sh
  i13-ipam-01.sh
  i13-cgroup-01.sh
  i13-snapshot-01.sh
  i13-seccomp-01.sh
)

echo "============================================================"
echo " I13 debugging gauntlet — all eight faults"
echo " Layers: distribution x2 (registry auth, corrupted blob) ·"
echo "         runtime (config.json) · shim (orphaned supervisor) ·"
echo "         network (IPAM exhaustion) · platform (cgroup driver) ·"
echo "         snapshotter (disk leak) · security (seccomp)"
echo " Budget: 60 minutes. Notes on. Hints only after 5 real minutes."
echo " Intended target: the throwaway 'sandbox' VM (never a cluster node)"
echo "============================================================"

# ---- wrong-box guards (each fault script re-checks these itself) ----
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
for f in "${FAULTS[@]}"; do
  if [ ! -f "$HERE/$f" ]; then
    echo "ABORT: $HERE/$f not found." >&2; exit 1
  fi
done

echo
echo "This plants eight independent faults across the whole node — registries,"
echo "containerd state, CNI reservations, cgroups and a runc bundle. Nothing"
echo "here is destructive to the VM itself, but it is not quick to eyeball-undo."
read -r -p "Type 'gauntlet' to start: " confirm
if [ "$confirm" != "gauntlet" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

planted=0
for f in "${FAULTS[@]}"; do
  echo
  echo "------------------------------------------------------------"
  if bash "$HERE/$f" <<< "break" > /tmp/i13-plant.log 2>&1; then
    planted=$((planted + 1))
    printf 'planted %d/8: %-20s ok\n' "$planted" "${f%.sh}"
    grep -A6 'YOUR MISSION' /tmp/i13-plant.log | sed 's/^/    /'
  else
    printf 'SKIPPED: %-20s (its own guard refused — see below)\n' "${f%.sh}"
    tail -3 /tmp/i13-plant.log | sed 's/^/    /'
  fi
done
rm -f /tmp/i13-plant.log

echo
echo "============================================================"
echo " $planted of 8 faults planted. Start the clock."
echo
echo " Rules for the run:"
echo "   * Fix them in any order; note the time you start each one."
echo "   * crictl and your own tools can be broken by the same underlying"
echo "     cause and say completely different things about it — check both."
echo "   * No hints for the first five real minutes on a fault."
echo "   * Write down, per fault: what you checked first, and what it cost you."
echo
echo " That note is the deliverable of I13.8 — not the fixes themselves."
echo " Hints & solutions: materials/i13.html -> lesson I13.7, staged reveals."
echo "============================================================"
