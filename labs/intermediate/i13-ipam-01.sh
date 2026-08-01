#!/usr/bin/env bash
# I13 gauntlet fault i13-ipam-01 (I13.7, layer 4 · network) — plants ONE
# fault: CNI IPAM exhaustion, on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash i13-ipam-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.i13-fault-backups
NETCONFDIR=/etc/i13cni/net.d
IPAMDIR=/var/lib/i13-cni-ipam
NETNAME=i13ipam
BRIDGE=i13br0

echo "============================================================"
echo " I13 gauntlet — fault i13-ipam-01"
echo " About to BREAK: layer 4, network (CNI IPAM exhaustion)"
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
for bin in cnitool; do
  command -v "$bin" >/dev/null || { echo "ABORT: $bin not found — is the intermediate toolchain installed?" >&2; exit 1; }
done
[ -x /opt/cni/bin/bridge ] || { echo "ABORT: /opt/cni/bin/bridge not found." >&2; exit 1; }

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent): a tiny bridge network with a pool of exactly one
# usable address, so a single leaked reservation exhausts it.
ip netns del i13nsA >/dev/null 2>&1 || true
ip netns del i13nsB >/dev/null 2>&1 || true
ip link del "$BRIDGE" >/dev/null 2>&1 || true
rm -rf "$IPAMDIR"
mkdir -p "$NETCONFDIR"
cat > "$NETCONFDIR/10-i13ipam.conflist" <<EOF
{
  "cniVersion": "1.0.0",
  "name": "$NETNAME",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "$BRIDGE",
      "isGateway": true,
      "ipMasq": true,
      "ipam": {
        "type": "host-local",
        "subnet": "10.213.13.0/30",
        "dataDir": "$IPAMDIR"
      }
    }
  ]
}
EOF

export CNI_PATH=/opt/cni/bin
export NETCONFPATH="$NETCONFDIR"
ip netns add i13nsA
if ! cnitool add "$NETNAME" /var/run/netns/i13nsA >/tmp/i13-ipam-check.log 2>&1; then
  echo "ABORT: the network will not even attach cleanly before the fault is planted." >&2
  cat /tmp/i13-ipam-check.log >&2; exit 1
fi

mkdir -p "$BACKUPS"
ls "$IPAMDIR/$NETNAME/" > "$BACKUPS/ipam-01.reservations.$(date +%Y%m%d-%H%M%S)"

# ---- plant: delete the namespace directly, skipping DEL. The bridge plugin
# reads the container's address out of the namespace to release it — once the
# namespace is gone, DEL (if it ran at all) would return success and reclaim
# nothing, so the reservation file is left behind forever.
ip netns del i13nsA

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. A moment ago, attaching a namespace to the '$NETNAME' network worked."
echo "  2. It does not now — for any new namespace, not just a repeat of the old one."
echo "  3. Find out what ran out, free what is stale, and verify a fresh attach works:"
echo "       sudo ip netns add i13nsverify"
echo "       sudo env CNI_PATH=/opt/cni/bin NETCONFPATH=$NETCONFDIR \\"
echo "         cnitool add $NETNAME /var/run/netns/i13nsverify"
echo "     should print an address, not an error."
echo
echo "Escape hatch (only if hopelessly stuck): the reservations that existed"
echo "right after a healthy attach are listed in $BACKUPS/ipam-01.reservations.*"
echo "Hints & solution: materials/i13.html -> lesson I13.7, staged reveals (fault 5)."
