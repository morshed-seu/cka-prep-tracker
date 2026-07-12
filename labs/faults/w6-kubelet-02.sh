#!/usr/bin/env bash
# CKA fault drill w6-kubelet-02 (lesson 6.11) — breaks the kubelet on the
# LAB cluster's node01. Watch the node from cp afterwards.
# Run on the node01 VM:  sudo bash w6-kubelet-02.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.cka-fault-backups

echo "============================================================"
echo " CKA fault drill w6-kubelet-02"
echo " About to BREAK: the kubelet on node01 (node goes NotReady)"
echo " Intended target: the 3-VM lab cluster (cp/node01/node02)"
echo "============================================================"

# ---- wrong-cluster guard ----
if [ "$(id -u)" -ne 0 ]; then
  echo "ABORT: run with sudo." >&2; exit 1
fi
if [ "$(hostname)" != "node01" ]; then
  echo "ABORT: this host is '$(hostname)', not the lab worker 'node01'." >&2
  echo "Refusing to break a machine that isn't the lab." >&2; exit 1
fi

DROPIN=""
for d in /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
  if [ -f "$d/kubelet.service.d/10-kubeadm.conf" ]; then
    DROPIN="$d/kubelet.service.d/10-kubeadm.conf"; break
  fi
done
if [ -z "$DROPIN" ]; then
  echo "ABORT: kubelet systemd drop-in 10-kubeadm.conf not found." >&2; exit 1
fi
if ! grep -q -- '--config=/var/lib/kubelet/config.yaml' "$DROPIN"; then
  echo "ABORT: drop-in doesn't look like the kubeadm default (or a fault is" >&2
  echo "already planted). Restore/fix it first, then re-run." >&2; exit 1
fi
if ! systemctl is-active --quiet kubelet; then
  echo "ABORT: kubelet is not running — fix the node first, then re-run." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

mkdir -p "$BACKUPS"
cp -a "$DROPIN" "$BACKUPS/10-kubeadm.conf.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
sed -i 's|--config=/var/lib/kubelet/config.yaml|--config=/var/lib/kubelet/config.yml|' "$DROPIN"
systemctl daemon-reload
systemctl restart kubelet || true

echo
echo "Fault planted."
echo
echo "YOUR MISSION (work from cp, ssh here only when the ladder says so)"
echo "  1. Within ~40s node01 goes NotReady:  kubectl get nodes -w"
echo "  2. Walk the NotReady ladder (lesson 6.10) to the root cause."
echo "  3. Fix the root cause, then verify:  kubectl get nodes → node01 Ready."
echo
echo "Escape hatch (only if hopelessly stuck): every drill backs up the file it"
echo "touches to $BACKUPS/ — restoring the newest copy un-plants the fault"
echo "(remember daemon-reload)."
echo "Hints & solution: materials/w6.html → lesson 6.11, staged reveals."
