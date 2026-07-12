#!/usr/bin/env bash
# CKA mock exam 1 — environment setup (companion to mock/exam-1.html).
# Provisions namespaces, working objects and BROKEN objects for all 16 tasks
# on the LAB cluster (cp/node01/node02). Run on cp:  sudo bash setup-exam-1.sh
# Clean up afterwards:                               sudo bash setup-exam-1.sh cleanup
# Reading this file spoils nothing — faults are planted, but solutions live
# only in mock/solutions-1.html.
set -euo pipefail

EXAM_NAMESPACES=(mercury venus mars jupiter saturn uranus neptune pluto)
EXAM_DIR=/root/exam

guard() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ABORT: run with sudo (files are written under $EXAM_DIR)." >&2; exit 1
  fi
  if [ "$(hostname)" != "cp" ]; then
    echo "ABORT: this host is '$(hostname)', not the lab control plane 'cp'." >&2
    echo "Refusing to touch a machine that isn't the lab." >&2; exit 1
  fi
  local nodes
  nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
  if [ "$nodes" != "cp node01 node02" ]; then
    echo "ABORT: cluster nodes are '$nodes', expected 'cp node01 node02'." >&2
    echo "Refusing to touch a cluster that isn't the lab." >&2; exit 1
  fi
}

cleanup() {
  guard
  echo "Removing mock-exam 1 artifacts..."
  kubectl delete ns "${EXAM_NAMESPACES[@]}" --ignore-not-found
  kubectl delete pv exam-pv --ignore-not-found
  kubectl label node node02 disk- >/dev/null 2>&1 || true
  rm -rf "$EXAM_DIR"
  echo "Done. Two manual leftovers, if you created them during the exam:"
  echo "  - static pod: on node01 run  sudo rm -f /etc/kubernetes/manifests/static-web.yaml"
  echo "  - hostPath data: on the node that ran pv-writer,  sudo rm -rf /srv/exam-pv"
}

if [ "${1:-}" = "cleanup" ]; then cleanup; exit 0; fi

echo "============================================================"
echo " CKA mock exam 1 — environment setup"
echo " About to CREATE: 8 namespaces + task objects (some broken)"
echo " Intended target: the 3-VM lab cluster (cp/node01/node02)"
echo "============================================================"
guard
if kubectl get ns mercury >/dev/null 2>&1; then
  echo "ABORT: namespace 'mercury' already exists (exam in progress?)." >&2
  echo "Finish or clean up first:  sudo bash setup-exam-1.sh cleanup" >&2; exit 1
fi

read -r -p "Type 'begin' to provision the exam environment: " confirm
if [ "$confirm" != "begin" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

for ns in "${EXAM_NAMESPACES[@]}"; do kubectl create ns "$ns" >/dev/null; done
mkdir -p "$EXAM_DIR"

# ---- task objects (broken ones are intentional; do not "fix" this file) ----
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
  namespace: mercury
spec:
  replicas: 2
  selector:
    matchLabels: {app: web-frontend}
  template:
    metadata:
      labels: {app: web-frontend}
    spec:
      containers:
      - name: nginx
        image: nginx:1.29-alpine
        resources:
          requests: {cpu: "4"}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
  namespace: venus
spec:
  replicas: 2
  selector:
    matchLabels: {app: database}
  template:
    metadata:
      labels: {app: database}
    spec:
      containers:
      - name: nginx
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: db-service
  namespace: venus
spec:
  selector: {app: db}
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: mars
spec:
  replicas: 1
  selector:
    matchLabels: {app: api}
  template:
    metadata:
      labels: {app: api}
    spec:
      containers:
      - name: nginx
        image: nginx:1.29-alpine
        command: ["nginx", "-g", "daemon off;", "--with-turbo"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-portal
  namespace: jupiter
spec:
  replicas: 2
  selector:
    matchLabels: {app: web-portal}
  template:
    metadata:
      labels: {app: web-portal}
    spec:
      containers:
      - name: nginx
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
  namespace: jupiter
spec:
  replicas: 1
  selector:
    matchLabels: {app: shop}
  template:
    metadata:
      labels: {app: shop}
    spec:
      containers:
      - name: nginx
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: shop
  namespace: jupiter
spec:
  selector: {app: shop}
  ports:
  - port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: jupiter
  labels: {role: frontend}
spec:
  containers:
  - name: main
    image: busybox:1.36
    command: ["sh", "-c", "sleep 1d"]
---
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: jupiter
  labels: {role: backend}
spec:
  containers:
  - name: main
    image: busybox:1.36
    command: ["sh", "-c", "sleep 1d"]
---
apiVersion: v1
kind: Pod
metadata:
  name: db
  namespace: jupiter
  labels: {role: db}
spec:
  containers:
  - name: nginx
    image: nginx:1.29-alpine
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: logger
  namespace: saturn
spec:
  containers:
  - name: main
    image: busybox:1.36
    command:
    - sh
    - -c
    - >-
      i=0;
      while true; do
        i=$((i+1));
        echo "$(date) INFO  request served id=$i";
        if [ $((i % 4)) -eq 0 ]; then
          echo "$(date) ERROR payment gateway timeout order=$((1000+i))";
        fi;
        if [ $((i % 7)) -eq 0 ]; then
          echo "$(date) WARN  cache miss ratio high";
        fi;
        sleep 2;
      done
---
apiVersion: v1
kind: Pod
metadata:
  name: cpu-load-1
  namespace: uranus
spec:
  containers:
  - name: main
    image: busybox:1.36
    command: ["sh", "-c", "sleep 1d"]
    resources:
      limits: {cpu: 200m, memory: 32Mi}
---
apiVersion: v1
kind: Pod
metadata:
  name: cpu-load-2
  namespace: uranus
spec:
  containers:
  - name: main
    image: busybox:1.36
    command: ["sh", "-c", "while true; do :; done"]
    resources:
      limits: {cpu: 200m, memory: 32Mi}
---
apiVersion: v1
kind: Pod
metadata:
  name: cpu-load-3
  namespace: uranus
spec:
  containers:
  - name: main
    image: busybox:1.36
    command: ["sh", "-c", "sleep 1d"]
    resources:
      limits: {cpu: 200m, memory: 32Mi}
EOF

# ---- kustomize base for task 13 ----
mkdir -p "$EXAM_DIR/kustomize/base"
cat > "$EXAM_DIR/kustomize/base/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  labels:
    app: hello
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
      - name: nginx
        image: nginx:1.29-alpine
EOF
cat > "$EXAM_DIR/kustomize/base/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
EOF

echo
echo "Environment provisioned. Images pull for a minute or two — that's fine;"
echo "some workloads are MEANT to be unhealthy. Do not investigate anything yet."
echo
echo "  1. Open mock/exam-1.html"
echo "  2. Start the 120-minute timer"
echo "  3. Answer files go under $EXAM_DIR/"
echo
echo "When done, grade with mock/solutions-1.html, then clean up:"
echo "  sudo bash setup-exam-1.sh cleanup"
