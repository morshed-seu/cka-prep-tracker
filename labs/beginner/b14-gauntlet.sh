#!/usr/bin/env bash
# Beginner gauntlet runner (B14.5 / B14.7) — plants ALL EIGHT faults in one go
# for the timed run. Each individual script keeps its own guards and backups.
# Run on the sandbox VM:  sudo bash b14-gauntlet.sh
# Do not read the individual scripts before the run — they name the faults.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
FAULTS=(
  b14-permission-01.sh
  b14-cgroup-01.sh
  b14-mount-01.sh
  b14-route-01.sh
  b14-iptables-01.sh
  b14-dns-01.sh
  b14-systemd-01.sh
  b14-cert-01.sh
)

echo "============================================================"
echo " Beginner debugging gauntlet — all eight faults"
echo " Layers: permission · cgroup · mount · route · filter · DNS ·"
echo "         systemd unit · certificate"
echo " Budget: 45 minutes. Notes on. Hints only after 5 real minutes."
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
echo "This plants eight independent faults. Take a VM snapshot first if you"
echo "would rather roll back than repair (B0.9)."
read -r -p "Type 'gauntlet' to start: " confirm
if [ "$confirm" != "gauntlet" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

planted=0
for f in "${FAULTS[@]}"; do
  echo
  echo "------------------------------------------------------------"
  if bash "$HERE/$f" <<< "break" > /tmp/b14-plant.log 2>&1; then
    planted=$((planted + 1))
    printf 'planted %d/8: %-26s ok\n' "$planted" "${f%.sh}"
    grep -A20 'YOUR MISSION' /tmp/b14-plant.log | sed 's/^/    /'
  else
    printf 'SKIPPED: %-26s (its own guard refused — see below)\n' "${f%.sh}"
    tail -3 /tmp/b14-plant.log | sed 's/^/    /'
  fi
done
rm -f /tmp/b14-plant.log

echo
echo "============================================================"
echo " $planted of 8 faults planted. Start the clock."
echo
echo " Rules for the run:"
echo "   * Fix them in any order; note the time you start each one."
echo "   * Climb a ladder rather than guessing (B8.16 for anything network-shaped)."
echo "   * No hints for the first five real minutes on a fault."
echo "   * Write down, per fault: what you checked first, and what it cost you."
echo
echo " That note is the deliverable of B14.6 — not the fixes themselves."
echo " Hints & solutions: materials/b14.html → lesson B14.5, staged reveals."
echo "============================================================"
