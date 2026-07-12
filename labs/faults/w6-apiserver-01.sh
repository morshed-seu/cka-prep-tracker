#!/usr/bin/env bash
# CKA fault drill w6-apiserver-01 (lesson 6.6) — plants ONE fault in the
# kube-apiserver static-pod manifest of the LAB cluster.
# Run on the control-plane VM:  sudo bash w6-apiserver-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
BACKUPS=/root/.cka-fault-backups

echo "============================================================"
echo " CKA fault drill w6-apiserver-01"
echo " About to BREAK: kube-apiserver (kubectl goes dark)"
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
if ! grep -q -- '--allow-privileged=true' "$MANIFEST"; then
  echo "ABORT: manifest doesn't look like the kubeadm default (or a fault is" >&2
  echo "already planted). Restore/fix it first, then re-run." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

mkdir -p "$BACKUPS"
cp -a "$MANIFEST" "$BACKUPS/kube-apiserver.yaml.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
sed -i 's/--allow-privileged=true/--allow-privilegedd=true/' "$MANIFEST"

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. Within ~30s kubectl stops answering."
echo "  2. Diagnose from this node only: systemctl, crictl, journalctl, /var/log/pods."
echo "  3. Fix the root cause (not the symptom), then verify:"
echo "       kubectl get --raw=/readyz     →  ok"
echo
echo "Escape hatch (only if hopelessly stuck): every drill backs up the file it"
echo "touches to $BACKUPS/ — restoring the newest copy un-plants the fault."
echo "Hints & solution: materials/w6.html → lesson 6.6, staged reveals."
