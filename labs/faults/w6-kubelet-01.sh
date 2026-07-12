#!/usr/bin/env bash
# CKA fault drill w6-kubelet-01 (lesson 6.11) — breaks the kubelet on the
# LAB cluster's node01. Watch the node from cp afterwards.
# Run on the node01 VM:  sudo bash w6-kubelet-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

echo "============================================================"
echo " CKA fault drill w6-kubelet-01"
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
if [ ! -f /etc/kubernetes/kubelet.conf ]; then
  echo "ABORT: /etc/kubernetes/kubelet.conf not found — not a joined kubeadm node?" >&2; exit 1
fi
if ! systemctl is-active --quiet kubelet; then
  echo "ABORT: kubelet is not running — fix the node first, then re-run." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- plant ----
systemctl disable --now kubelet >/dev/null 2>&1

echo
echo "Fault planted."
echo
echo "YOUR MISSION (work from cp, ssh here only when the ladder says so)"
echo "  1. Within ~40s node01 goes NotReady:  kubectl get nodes -w"
echo "  2. Walk the NotReady ladder (lesson 6.10) to the root cause."
echo "  3. Fix it PROPERLY — the fix must survive a reboot of node01."
echo "  4. Verify:  kubectl get nodes  →  node01 Ready, and"
echo "     'sudo reboot' on node01 → node01 comes back Ready on its own."
echo
echo "Hints & solution: materials/w6.html → lesson 6.11, staged reveals."
