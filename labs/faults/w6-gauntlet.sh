#!/usr/bin/env bash
# CKA fault drill w6-gauntlet (lesson 6.19) — plants SIX broken workloads
# in namespace 'gauntlet' on the LAB cluster. 30 minutes, notes closed.
# Run wherever kubectl talks to the lab:  bash w6-gauntlet.sh
# Do not read this file before the drill — it names every fault.
set -euo pipefail

NS=gauntlet

echo "============================================================"
echo " CKA fault drill w6-gauntlet — the 30-minute six-pack"
echo " About to CREATE: 6 broken workloads in namespace $NS"
echo " Intended target: the 3-VM lab cluster (cp/node01/node02)"
echo "============================================================"

# ---- wrong-cluster guard ----
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
if [ "$nodes" != "cp node01 node02" ]; then
  echo "ABORT: cluster nodes are '$nodes', expected 'cp node01 node02'." >&2
  echo "Refusing to touch a cluster that isn't the lab." >&2; exit 1
fi
if kubectl get ns "$NS" >/dev/null 2>&1; then
  echo "ABORT: namespace $NS already exists (drill in progress?)." >&2
  echo "Finish or clean up first:  kubectl delete ns $NS" >&2; exit 1
fi

read -r -p "Type 'break' to plant all six faults: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- plant ----
kubectl create ns "$NS" >/dev/null
kubectl apply -n "$NS" -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web1
spec:
  replicas: 2
  selector:
    matchLabels: {app: web1}
  template:
    metadata:
      labels: {app: web1}
    spec:
      containers:
      - name: nginx
        image: nginx:1.29-alpin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web2
spec:
  replicas: 1
  selector:
    matchLabels: {app: web2}
  template:
    metadata:
      labels: {app: web2}
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          requests: {cpu: "4"}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web3
spec:
  replicas: 1
  selector:
    matchLabels: {app: web3}
  template:
    metadata:
      labels: {app: web3}
    spec:
      nodeSelector: {disktype: ssd}
      containers:
      - name: nginx
        image: nginx
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web4
spec:
  replicas: 1
  selector:
    matchLabels: {app: web4}
  template:
    metadata:
      labels: {app: web4}
    spec:
      containers:
      - name: main
        image: busybox:1.36
        command: ["/bin/shh", "-c", "sleep 1d"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web5
spec:
  replicas: 1
  selector:
    matchLabels: {app: web5}
  template:
    metadata:
      labels: {app: web5}
    spec:
      containers:
      - name: nginx
        image: nginx
---
apiVersion: v1
kind: Service
metadata:
  name: web5
spec:
  selector: {app: web05}
  ports:
  - port: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web6
spec:
  replicas: 1
  selector:
    matchLabels: {app: web6}
  template:
    metadata:
      labels: {app: web6}
    spec:
      containers:
      - name: nginx
        image: nginx
        readinessProbe:
          httpGet:
            path: /
            port: 8081
EOF

echo
echo "Six faults planted in namespace $NS. Start a 30-MINUTE timer NOW."
echo
echo "YOUR MISSION — notes closed, docs allowed (kubernetes.io only):"
echo "  web1  →  2/2 ready"
echo "  web2  →  1/1 ready"
echo "  web3  →  1/1 ready"
echo "  web4  →  1/1 ready (container Running, no restarts accumulating)"
echo "  web5  →  this returns the nginx welcome page:"
echo "           kubectl -n $NS run check --rm -it --restart=Never \\"
echo "             --image=busybox:1.36 -- wget -qO- -T2 http://web5"
echo "  web6  →  1/1 READY (not just Running)"
echo
echo "Scoreboard:  kubectl -n $NS get deploy,pods,svc"
echo "When the timer rings, grade yourself against lesson 6.19's reveals,"
echo "then clean up:  kubectl delete ns $NS"
