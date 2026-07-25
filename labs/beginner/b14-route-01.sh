#!/usr/bin/env bash
# Beginner gauntlet fault b14-route-01 (B14.5) — plants ONE fault in the
# routing layer on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash b14-route-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.b14-fault-backups
NS=gauntlet-ns
BR=gbr0
SUBNET=10.77.0.0/24
GW=10.77.0.1
NSIP=10.77.0.2

echo "============================================================"
echo " Beginner gauntlet — fault b14-route-01"
echo " About to BREAK: reachability out of a network namespace"
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

HOSTIF=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
HOSTIP=$(ip -4 -o addr show dev "${HOSTIF:-lo}" | awk '{print $4}' | cut -d/ -f1 | head -1)
if [ -z "${HOSTIP:-}" ]; then
  echo "ABORT: could not determine this VM's primary IP address." >&2; exit 1
fi

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent) ----
ip netns del "$NS" 2>/dev/null || true
ip link del "$BR" 2>/dev/null || true
ip link add "$BR" type bridge
ip addr add "$GW/24" dev "$BR"
ip link set "$BR" up
ip netns add "$NS"
ip link add gveth0 type veth peer name gveth1
ip link set gveth0 master "$BR"
ip link set gveth0 up
ip link set gveth1 netns "$NS"
ip netns exec "$NS" ip link set lo up
ip netns exec "$NS" ip addr add "$NSIP/24" dev gveth1
ip netns exec "$NS" ip link set gveth1 up
ip netns exec "$NS" ip route add default via "$GW"
sysctl -qw net.ipv4.ip_forward=1
iptables -t nat -C POSTROUTING -s "$SUBNET" ! -o "$BR" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "$SUBNET" ! -o "$BR" -j MASQUERADE

if ! ip netns exec "$NS" ping -c1 -W2 "$HOSTIP" >/dev/null 2>&1; then
  echo "ABORT: the namespace cannot reach $HOSTIP even before the fault." >&2
  echo "Clean up with: ip netns del $NS; ip link del $BR" >&2; exit 1
fi

mkdir -p "$BACKUPS"
ip netns exec "$NS" ip route show > "$BACKUPS/route-01.routes.$(date +%Y%m%d-%H%M%S)"

# ---- plant ----
ip netns exec "$NS" ip route del default
ip netns exec "$NS" ip route add default via 10.77.0.99

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. Namespace '$NS' ($NSIP) can still reach its own subnet."
echo "  2. It can no longer reach anything beyond it."
echo "  3. Reproduce it:  sudo ip netns exec $NS ping -c1 -W2 $HOSTIP"
echo "  4. Fix the root cause, then verify BOTH of these succeed:"
echo "       sudo ip netns exec $NS ping -c1 -W2 $GW"
echo "       sudo ip netns exec $NS ping -c1 -W2 $HOSTIP"
echo "  5. Do not rebuild the namespace — repair what is there."
echo
echo "Escape hatch (only if hopelessly stuck): the original routing table is in"
echo "$BACKUPS/route-01.routes.* — reading it gives the answer away."
echo "Hints & solution: materials/b14.html → lesson B14.5, staged reveals."
echo
echo "Clean-up when done:  sudo ip netns del $NS; sudo ip link del $BR"
