#!/usr/bin/env bash
# CKA fault drill w6-scheduler-01 (lesson 6.7) — breaks the kube-scheduler
# on the LAB cluster. kubectl keeps working; something else stops.
# Run on the control-plane VM:  sudo bash w6-scheduler-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

MANIFEST=/etc/kubernetes/manifests/kube-scheduler.yaml
BACKUPS=/root/.cka-fault-backups

echo "============================================================"
echo " CKA fault drill w6-scheduler-01"
echo " About to BREAK: kube-scheduler"
echo " Intended target: the 3-VM lab cluster (cp/node01/node02)"
echo "============================================================"

# ---- wrong-cluster guard ----
if [ "$(id -u)" -ne 0 ]; then
  echo "ABORT: run with sudo." >&2; exit 1
fi
if [ "$(hostname)" != "cp" ]; then
  echo "ABORT: this host is '$(hostname)', not the lab control plane 'cp'." >&2
  echo "Refusing to break a machine that isn't the lab." >&2; exit 1
fi
if [ ! -f "$MANIFEST" ]; then
  echo "ABORT: $MANIFEST not found — not a kubeadm control plane?" >&2; exit 1
fi
if ! grep -q -- '- --kubeconfig=/etc/kubernetes/scheduler.conf' "$MANIFEST"; then
  echo "ABORT: manifest doesn't look like the kubeadm default (or a fault is" >&2
  echo "already planted). Restore/fix it first, then re-run." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

mkdir -p "$BACKUPS"
cp -a "$MANIFEST" "$BACKUPS/kube-scheduler.yaml.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
sed -i 's|- --kubeconfig=/etc/kubernetes/scheduler.conf|- --kubeconfig=/etc/kubernetes/schedu1er.conf|' "$MANIFEST"

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. kubectl still works — the cluster only LOOKS healthy."
echo "  2. Prove something is broken:  kubectl run smoke --image=nginx"
echo "     then watch what does (or doesn't) happen to that pod."
echo "  3. Find the root cause and fix it, then verify:"
echo "       the smoke pod reaches Running, and"
echo "       kubectl -n kube-system get pods   →  scheduler Running, 1/1"
echo "  4. Clean up:  kubectl delete pod smoke"
echo
echo "Escape hatch (only if hopelessly stuck): every drill backs up the file it"
echo "touches to $BACKUPS/ — restoring the newest copy un-plants the fault."
echo "Hints & solution: materials/w6.html → lesson 6.7, staged reveals."
