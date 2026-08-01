#!/usr/bin/env bash
# I13 gauntlet fault i13-registry-01 (I13.7, layer 1 · distribution) — plants
# ONE fault: registry authentication, on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash i13-registry-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.i13-fault-backups
REG=i13reg-auth
PORT=5002
CERTSD="/etc/containerd/i13-certs.d/localhost:$PORT"
IMG="localhost:$PORT/i13/gauntlet:v1"

echo "============================================================"
echo " I13 gauntlet — fault i13-registry-01"
echo " About to BREAK: layer 1, distribution (registry auth)"
echo " Intended target: the throwaway 'sandbox' VM (never a cluster node)"
echo "============================================================"

# ---- wrong-box guards ----
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
for bin in nerdctl crictl ctr; do
  command -v "$bin" >/dev/null || { echo "ABORT: $bin not found — is the intermediate toolchain installed?" >&2; exit 1; }
done

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent): an authenticated registry the CRI images plugin can reach ----
mkdir -p /opt/i13-registry-auth/data
if [ ! -f /opt/i13-registry-auth/htpasswd ]; then
  command -v htpasswd >/dev/null || apt-get install -y apache2-utils >/tmp/i13-apt.log 2>&1
  htpasswd -Bbn gauntlet secretpw > /opt/i13-registry-auth/htpasswd
fi
if ! nerdctl ps -a --format '{{.Names}}' | grep -qx "$REG"; then
  nerdctl run -d --name "$REG" --restart=always -p "$PORT:5000" \
    -v /opt/i13-registry-auth/htpasswd:/auth/htpasswd:ro \
    -v /opt/i13-registry-auth/data:/var/lib/registry \
    -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=gauntlet \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    docker.io/library/registry:2 >/dev/null
  sleep 2
fi

mkdir -p "$CERTSD"
GOODAUTH=$(printf 'gauntlet:secretpw' | base64 -w0)
cat > "$CERTSD/hosts.toml" <<EOF
server = "http://localhost:$PORT"

[host."http://localhost:$PORT"]
  capabilities = ["pull", "resolve"]
  [host."http://localhost:$PORT".header]
    Authorization = "Basic $GOODAUTH"
EOF

# The CRI images plugin only consults i13-certs.d/ once config_path names it —
# this is the one-time wiring step, harmless to repeat.
if ! grep -q 'i13-certs.d' /etc/containerd/config.toml 2>/dev/null; then
  cat > /etc/containerd/config.toml <<EOF
version = 4

[plugins."io.containerd.cri.v1.images".registry]
  config_path = "/etc/containerd/i13-certs.d"
EOF
  systemctl restart containerd
  sleep 2
fi

nerdctl login "localhost:$PORT" -u gauntlet -p secretpw >/dev/null 2>&1
if ! nerdctl images --format '{{.Repository}}:{{.Tag}}' | grep -qx "$IMG"; then
  nerdctl pull docker.io/library/alpine:3.21 >/dev/null 2>&1
  nerdctl tag docker.io/library/alpine:3.21 "$IMG"
fi
nerdctl push "$IMG" >/dev/null 2>&1

crictl rmi "$IMG" >/dev/null 2>&1 || true
if ! crictl pull "$IMG" >/tmp/i13-registry-check.log 2>&1; then
  echo "ABORT: the registry will not pull cleanly even before the fault is planted." >&2
  cat /tmp/i13-registry-check.log >&2; exit 1
fi

mkdir -p "$BACKUPS"
cp "$CERTSD/hosts.toml" "$BACKUPS/registry-01.hosts.toml.$(date +%Y%m%d-%H%M%S)"

# ---- plant: corrupt the credential the CRI images plugin actually reads ----
BADAUTH=$(printf 'gauntlet:wrongpass' | base64 -w0)
sed -i "s#Authorization = .*#Authorization = \"Basic $BADAUTH\"#" "$CERTSD/hosts.toml"
crictl rmi "$IMG" >/dev/null 2>&1 || true

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. $IMG pulled cleanly through crictl a moment ago. It will not now."
echo "  2. nerdctl's own login to the same registry is untouched — pulling with"
echo "     it proves nothing about what the kubelet's own path will do."
echo "  3. Find why crictl's pull fails, fix the credential the pull path"
echo "     actually reads, then verify:"
echo "       crictl pull $IMG   ->  succeeds"
echo
echo "Escape hatch (only if hopelessly stuck): a backup of the working hosts.toml"
echo "is in $BACKUPS/registry-01.hosts.toml.*"
echo "Hints & solution: materials/i13.html -> lesson I13.7, staged reveals (fault 1)."
