#!/usr/bin/env bash
# CKA fault drill w6-netpol-01 (lesson 6.22) — plants a broken NetworkPolicy
# scenario in namespace np-drill on the LAB cluster.
# Requires the Calico swap from lesson 4.24 (flannel doesn't enforce policies).
# Run wherever kubectl talks to the lab:  bash w6-netpol-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

NS=np-drill

echo "============================================================"
echo " CKA fault drill w6-netpol-01"
echo " About to CREATE: a broken app→db scenario in namespace $NS"
echo " Intended target: the 3-VM lab cluster (cp/node01/node02)"
echo "============================================================"

# ---- wrong-cluster guard ----
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
if [ "$nodes" != "cp node01 node02" ]; then
  echo "ABORT: cluster nodes are '$nodes', expected 'cp node01 node02'." >&2
  echo "Refusing to touch a cluster that isn't the lab." >&2; exit 1
fi
if ! kubectl -n kube-system get pods -l k8s-app=calico-node 2>/dev/null | grep -q Running; then
  echo "ABORT: no running calico-node pods found. This drill needs a" >&2
  echo "policy-enforcing CNI — redo the Calico swap from lesson 4.24 first" >&2
  echo "(snapshot, remove flannel, install Calico), then re-run." >&2; exit 1
fi
if kubectl get ns "$NS" >/dev/null 2>&1; then
  echo "ABORT: namespace $NS already exists (drill in progress?)." >&2
  echo "Finish or clean up first:  kubectl delete ns $NS" >&2; exit 1
fi

read -r -p "Type 'break' to plant the scenario: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- plant ----
kubectl create ns "$NS" >/dev/null
kubectl apply -n "$NS" -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: db
  labels: {app: db}
spec:
  containers:
  - name: db
    image: nginx
---
apiVersion: v1
kind: Service
metadata:
  name: db
spec:
  selector: {app: db}
  ports:
  - port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  labels: {app: frontend}
spec:
  containers:
  - name: main
    image: busybox:1.36
    command: ["sleep", "1d"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-db
spec:
  podSelector:
    matchLabels: {app: db}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels: {app: front-end}
    ports:
    - protocol: TCP
      port: 80
EOF
kubectl -n "$NS" wait --for=condition=Ready pod/db pod/frontend --timeout=120s >/dev/null

echo
echo "Scenario planted in namespace $NS."
echo
echo "YOUR MISSION"
echo "  The 'frontend' pod must be able to reach the 'db' service, but can't:"
echo "    kubectl -n $NS exec frontend -- wget -qO- -T2 http://db   →  times out"
echo "  Someone intended to allow exactly this traffic. Find what they got"
echo "  wrong and fix it MINIMALLY — the default-deny must stay in force"
echo "  (a pod without frontend's labels must still be blocked)."
echo "  Verify: the wget above returns the nginx welcome page."
echo "  Clean up when done:  kubectl delete ns $NS"
echo
echo "Hints & solution: materials/w6.html → lesson 6.22, staged reveals."
