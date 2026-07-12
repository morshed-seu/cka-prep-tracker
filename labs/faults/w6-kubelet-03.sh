#!/usr/bin/env bash
# CKA fault drill w6-kubelet-03 (lesson 6.11) — breaks node01 on the LAB
# cluster. Watch the node from cp afterwards.
# Run on the node01 VM:  sudo bash w6-kubelet-03.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

echo "============================================================"
echo " CKA fault drill w6-kubelet-03"
echo " About to BREAK: node01 (node goes NotReady)"
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
if [ ! -f /etc/kubernetes/kubelet.conf ]; then
  echo "ABORT: /etc/kubernetes/kubelet.conf not found — not a joined kubeadm node?" >&2; exit 1
fi
if ! systemctl is-active --quiet containerd; then
  echo "ABORT: containerd is not running — fix the node first, then re-run." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- plant ----
systemctl stop containerd

echo
echo "Fault planted."
echo
echo "YOUR MISSION (work from cp, ssh here only when the ladder says so)"
echo "  1. Within a minute or two node01 goes NotReady:  kubectl get nodes -w"
echo "  2. Walk the NotReady ladder (lesson 6.10) — note that this time the"
echo "     first rung of the ladder looks HEALTHY. Keep climbing."
echo "  3. Fix the root cause, then verify:  kubectl get nodes → node01 Ready."
echo
echo "Hints & solution: materials/w6.html → lesson 6.11, staged reveals."
