#!/usr/bin/env bash
# I13 gauntlet fault i13-cgroup-01 (I13.7, layer 6 · platform) — plants ONE
# fault: a cgroup-driver mismatch, on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash i13-cgroup-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.i13-fault-backups
POD=/tmp/i13-cgroup-pod.json
CTR=/tmp/i13-cgroup-ctr.json
LIMIT=33554432

echo "============================================================"
echo " I13 gauntlet — fault i13-cgroup-01"
echo " About to BREAK: layer 6, platform (cgroup-driver mismatch)"
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
command -v crictl >/dev/null || { echo "ABORT: crictl not found." >&2; exit 1; }
[ -d /run/systemd/system ] || { echo "ABORT: this is not a systemd host — the fault has nothing to mismatch." >&2; exit 1; }

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent): pin this systemd host's runtime to the cgroupfs
# driver — a plausible thing for someone to have copied from a non-systemd
# box — then prove a memory limit still gets created with no complaint.
if ! grep -q 'SystemdCgroup' /etc/containerd/config.toml 2>/dev/null; then
  cat >> /etc/containerd/config.toml <<'EOF'

[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc.options]
  SystemdCgroup = false
EOF
  systemctl restart containerd
  sleep 2
fi

crictl pods --name i13cgroupverify -q 2>/dev/null | xargs -r crictl rmp -f >/dev/null 2>&1 || true
crictl pull docker.io/library/alpine:3.21 >/dev/null

cat > "$POD" <<'EOF'
{"metadata":{"name":"i13cgroupverify","namespace":"default","uid":"i13cgroupverify"},"linux":{}}
EOF
cat > "$CTR" <<EOF
{"metadata":{"name":"i13cgroupctr"},"image":{"image":"docker.io/library/alpine:3.21"},
"command":["sh","-c","while :; do sleep 1; done"],
"linux":{"resources":{"memory_limit_in_bytes":$LIMIT}}}
EOF

POD_ID=$(crictl runp "$POD")
CTR_ID=$(crictl create "$POD_ID" "$CTR" "$POD")
crictl start "$CTR_ID" >/dev/null
sleep 1

CGPATH=$(crictl inspect "$CTR_ID" | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["runtimeSpec"]["linux"]["cgroupsPath"])')
ACTUAL=$(cat "/sys/fs/cgroup${CGPATH}/memory.max" 2>/dev/null || echo missing)
if [ "$ACTUAL" != "$LIMIT" ]; then
  echo "ABORT: the limit is not even enforced before the fault is planted (got '$ACTUAL')." >&2
  exit 1
fi

mkdir -p "$BACKUPS"
{
  echo "container $CTR_ID, cgroupsPath $CGPATH, memory.max $ACTUAL, enforced fine"
  echo "this host's init system: $(readlink /sbin/init 2>/dev/null || cat /proc/1/comm)"
} > "$BACKUPS/cgroup-01.note.$(date +%Y%m%d-%H%M%S)"

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. Container $CTR_ID is running right now with a memory limit set through"
echo "     crictl. Nothing about creating it errored."
echo "  2. This is a systemd host. An operator checking the usual systemd-managed"
echo "     cgroup tree for that limit finds nothing there."
echo "  3. Is the limit actually enforced? Find where it really lives, from the"
echo "     container's OWN generated config rather than a path you assumed, then"
echo "     fix the driver mismatch so this host's runtime agrees with the init"
echo "     system managing it."
echo
echo "Escape hatch (only if hopelessly stuck): a note with $CTR_ID's real cgroup"
echo "path is in $BACKUPS/cgroup-01.note.*"
echo "Hints & solution: materials/i13.html -> lesson I13.7, staged reveals (fault 6)."
