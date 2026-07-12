#!/usr/bin/env bash
# CKA fault drill w6-controller-manager-01 (lesson 6.7) — breaks the
# kube-controller-manager on the LAB cluster. kubectl keeps working.
# Run on the control-plane VM:  sudo bash w6-controller-manager-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

MANIFEST=/etc/kubernetes/manifests/kube-controller-manager.yaml
BACKUPS=/root/.cka-fault-backups

echo "============================================================"
echo " CKA fault drill w6-controller-manager-01"
echo " About to BREAK: kube-controller-manager"
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
if ! grep -q -- '--use-service-account-credentials=true' "$MANIFEST"; then
  echo "ABORT: manifest doesn't look like the kubeadm default (or a fault is" >&2
  echo "already planted). Restore/fix it first, then re-run." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

mkdir -p "$BACKUPS"
cp -a "$MANIFEST" "$BACKUPS/kube-controller-manager.yaml.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
sed -i 's/--use-service-account-credentials=true/--use-service-account-credentialz=true/' "$MANIFEST"

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. kubectl still works — the cluster only LOOKS healthy."
echo "  2. Prove something is broken:"
echo "       kubectl create deploy smoke --image=nginx --replicas=2"
echo "     then watch what does (or doesn't) happen."
echo "  3. Find the root cause and fix it, then verify:"
echo "       smoke gets 2/2 ready, and"
echo "       kubectl -n kube-system get pods   →  controller-manager Running, 1/1"
echo "  4. Clean up:  kubectl delete deploy smoke"
echo
echo "Escape hatch (only if hopelessly stuck): every drill backs up the file it"
echo "touches to $BACKUPS/ — restoring the newest copy un-plants the fault."
echo "Hints & solution: materials/w6.html → lesson 6.7, staged reveals."
