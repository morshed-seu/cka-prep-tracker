#!/usr/bin/env bash
# I13 gauntlet fault i13-blob-01 (I13.7, layer 1 · content store) — plants ONE
# fault: a corrupted layer blob, on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash i13-blob-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.i13-fault-backups
REG=i13reg-plain
PORT=5003
CERTSD="/etc/containerd/i13-certs.d/localhost:$PORT"
IMG="localhost:$PORT/i13/blobtest:v1"

echo "============================================================"
echo " I13 gauntlet — fault i13-blob-01"
echo " About to BREAK: layer 1, content store (corrupted blob)"
echo " Intended target: the throwaway 'sandbox' VM (never a cluster node)"
echo "============================================================"

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
for bin in nerdctl crictl ctr python3; do
  command -v "$bin" >/dev/null || { echo "ABORT: $bin not found — is the intermediate toolchain installed?" >&2; exit 1; }
done

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent): a plain registry hosting a genuinely fresh layer.
# The payload is regenerated every run so re-planting after a fix always hits
# a layer this node has never unpacked before — reusing fixed bytes would let
# a stale, already-good snapshot mask the fault on a second run.
mkdir -p /opt/i13-registry-plain/data
if ! nerdctl ps -a --format '{{.Names}}' | grep -qx "$REG"; then
  nerdctl run -d --name "$REG" --restart=always -p "$PORT:5000" \
    -v /opt/i13-registry-plain/data:/var/lib/registry \
    docker.io/library/registry:2 >/dev/null
fi
# Wait for the registry to actually answer, rather than a fixed sleep — a
# freshly (re)started container is not instantly ready to accept connections.
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/v2/" 2>/dev/null || true)
  if [ "$code" = "200" ]; then break; fi
  sleep 1
done
mkdir -p "$CERTSD"
cat > "$CERTSD/hosts.toml" <<EOF
server = "http://localhost:$PORT"
[host."http://localhost:$PORT"]
  capabilities = ["pull", "resolve"]
EOF

nerdctl rm -f i13blobsrc >/dev/null 2>&1 || true
nerdctl run --name i13blobsrc docker.io/library/alpine:3.21 \
  sh -c 'head -c 65536 /dev/urandom > /payload.bin' >/dev/null
nerdctl commit i13blobsrc "$IMG" >/dev/null
nerdctl rm -f i13blobsrc >/dev/null
nerdctl push "$IMG" >/dev/null 2>&1

crictl rmi "$IMG" >/dev/null 2>&1 || true
if ! crictl pull "$IMG" >/tmp/i13-blob-check.log 2>&1; then
  echo "ABORT: the fresh image will not even pull cleanly before the fault is planted." >&2
  cat /tmp/i13-blob-check.log >&2; exit 1
fi
SIZE=$(ctr -n k8s.io run --rm --platform linux/amd64 "$IMG" i13blobverify cat /payload.bin | wc -c)
if [ "$SIZE" != 65536 ]; then
  echo "ABORT: the freshly built image does not run cleanly (got $SIZE bytes, want 65536)." >&2
  exit 1
fi

# Work out the payload layer's compressed digest (to corrupt) and its
# containerd chain ID (to evict) the same way containerd derives it:
# chainID[0] = diff_ids[0]; chainID[i] = sha256("<chainID[i-1]> <diff_ids[i]>").
read -r LAYER_DIGEST CHAIN_ID <<PYEOF
$(python3 - "$IMG" <<'PY'
import json, hashlib, subprocess, sys
img = sys.argv[1]
listing = subprocess.check_output(
    ["ctr", "-n", "k8s.io", "images", "ls", f"name=={img}"]).decode().splitlines()
manifest_digest = listing[1].split()[2]
manifest = json.loads(subprocess.check_output(
    ["ctr", "-n", "k8s.io", "content", "get", manifest_digest]))
layer_digest = manifest["layers"][-1]["digest"]
config = json.loads(subprocess.check_output(
    ["ctr", "-n", "k8s.io", "content", "get", manifest["config"]["digest"]]))
chain = config["rootfs"]["diff_ids"][0]
for d in config["rootfs"]["diff_ids"][1:]:
    chain = "sha256:" + hashlib.sha256(f"{chain} {d}".encode()).hexdigest()
print(layer_digest, chain)
PY
)
PYEOF

BLOB="/var/lib/containerd/io.containerd.content.v1.content/blobs/sha256/${LAYER_DIGEST#sha256:}"
[ -f "$BLOB" ] || { echo "ABORT: expected blob $BLOB not found." >&2; exit 1; }

mkdir -p "$BACKUPS"
echo "$IMG layer $LAYER_DIGEST was good; chain $CHAIN_ID unpacked cleanly" \
  > "$BACKUPS/blob-01.note.$(date +%Y%m%d-%H%M%S)"

# ---- plant: corrupt the on-disk bytes in place (same filename — the content
# store trusts the filename forever) and evict the leaf snapshot, so the next
# thing that needs this layer must re-read the now-bad bytes.
dd if=/dev/zero of="$BLOB" bs=1 seek=1000 count=200 conv=notrunc >/dev/null 2>&1
ctr -n k8s.io snapshot rm "$CHAIN_ID" >/dev/null 2>&1 || true

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. crictl images still lists $IMG — as far as the node is concerned,"
echo "     the pull already succeeded."
echo "  2. A fresh container from that image will not start."
echo "  3. Find the bad blob, fix it, and verify a fresh container runs:"
echo "       sudo ctr -n k8s.io run --rm --platform linux/amd64 $IMG i13fix cat /payload.bin"
echo "     should print 65536 bytes of data, not an error."
echo
echo "Escape hatch (only if hopelessly stuck): a note naming the good digest and"
echo "chain is in $BACKUPS/blob-01.note.*"
echo "Hints & solution: materials/i13.html -> lesson I13.7, staged reveals (fault 2)."
