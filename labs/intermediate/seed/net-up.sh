#!/usr/bin/env bash
# net-up — N network namespaces on one bridge, each addressed, routed, and with
# masqueraded egress. That is a pod network: the IPAM, the wiring, and the
# egress path a CNI plugin sets up per pod.
#
# This is the beginner track's B9 mini project (materials/b9.html, lesson
# B9.19), shipped here so a reader who started at the Intermediate track can
# bootstrap it rather than build it. I9 rewrites this same work as a plugin that
# speaks the CNI ADD/DEL contract — reading JSON on stdin, writing JSON on
# stdout — which is the whole point: the standard added a calling convention,
# not a mechanism.
#
# Two differences from the lesson's version, both marked below:
#   * the uplink is detected from the default route instead of hardcoded ens3;
#   * a `down` mode, so it is re-runnable.
#
# Usage (on a throwaway VM, as root):
#   sudo ./net-up.sh up 3     # or just: sudo ./net-up.sh 3
#   sudo ./net-up.sh down
set -euo pipefail

SUBNET=${SUBNET:-10.20.0}
BRIDGE=${BRIDGE:-cni0}

# ---- wrong-box guard: this writes NAT rules and creates namespaces ----
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
if [ -d /etc/kubernetes ]; then
  echo "ABORT: /etc/kubernetes exists — this looks like a cluster node." >&2
  echo "This script creates a bridge and NAT rules. Use a throwaway VM." >&2
  exit 1
fi

# The lesson hardcoded UPLINK=ens3; Multipass names the interface differently on
# some hosts, so take it from the default route and fall back to the old name.
UPLINK=${UPLINK:-$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')}
UPLINK=${UPLINK:-ens3}

up() {
  local n=${1:-3} i ns host peer
  sysctl -wq net.ipv4.ip_forward=1
  ip link add "$BRIDGE" type bridge 2>/dev/null || true
  ip addr add "${SUBNET}.1/24" dev "$BRIDGE" 2>/dev/null || true
  ip link set "$BRIDGE" up
  iptables -t nat -C POSTROUTING -s "${SUBNET}.0/24" -o "$UPLINK" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s "${SUBNET}.0/24" -o "$UPLINK" -j MASQUERADE
  echo "bridge $BRIDGE = ${SUBNET}.1/24, egress via $UPLINK"
  for i in $(seq 1 "$n"); do
    ns=pod$i ; host=veth$i ; peer=eth0
    ip netns add "$ns" 2>/dev/null || true
    ip link add "$host" type veth peer name "$peer" 2>/dev/null || true
    ip link set "$peer" netns "$ns"
    ip link set "$host" up ; ip link set "$host" master "$BRIDGE"
    ip netns exec "$ns" sh -c "ip link set lo up; ip link set eth0 up;
      ip addr add ${SUBNET}.$((i+1))/24 dev eth0;
      ip route add default via ${SUBNET}.1"
    echo "  $ns = ${SUBNET}.$((i+1))"
  done
}

down() {
  local ns host
  for ns in $(ip netns list | awk '/^pod[0-9]+/{print $1}'); do
    ip netns del "$ns"
    host=veth${ns#pod}
    ip link del "$host" 2>/dev/null || true
    echo "  removed $ns"
  done
  ip link del "$BRIDGE" 2>/dev/null || true
  iptables -t nat -D POSTROUTING -s "${SUBNET}.0/24" -o "$UPLINK" -j MASQUERADE 2>/dev/null || true
  echo "bridge, namespaces and the NAT rule removed"
}

case "${1:-up}" in
  down)      down ;;
  up)        up "${2:-3}" ;;
  ''|*[!0-9]*) echo "usage: $0 [up N | down]" >&2; exit 1 ;;
  *)         up "$1" ;;          # bare count, as the lesson's version took
esac
