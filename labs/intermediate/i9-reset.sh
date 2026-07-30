#!/usr/bin/env bash
# i9-reset — return a lab box to a clean slate between I9 experiments.
#
# CNI state lives in four places, and every one of them can outlive a plugin
# call that failed: network namespaces, host-side veths and bridges, the nat
# table (per-container CNI-<hash> chains plus the POSTROUTING jumps into them),
# and host-local's reservation tree. Missing any one of them makes the next
# experiment lie to you — which is how I9.10's "IPAM exhaustion" fault happens
# in production.
#
# Deliberately leaves alone: nerdctl0 and anything named in $KEEP_VETH.
#
# Usage:  sudo ./i9-reset.sh
set -u

KEEP_VETH=${KEEP_VETH:-}
NETS=${NETS:-i9net i9chain i9tiny i9ver i9multi ordertest minibridge}
LINKS=${LINKS:-i9br0 i9tiny0 i9chain0 i9ord5 i9ord10 mbr0 cni0}

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
if [ -d /etc/kubernetes ]; then
  echo "ABORT: /etc/kubernetes exists — this looks like a cluster node." >&2
  exit 1
fi

# 1. namespaces (this also destroys the container end of each veth pair)
for ns in $(ip netns list | awk '/^i9pod|^pod[0-9]/{print $1}'); do
  ip netns del "$ns" && echo "  netns   $ns"
done

# 2. bridges, then any orphaned host-side veth
for l in $LINKS; do
  ip link del "$l" 2>/dev/null && echo "  link    $l"
done
for v in $(ip -o link show type veth | awk -F': ' '{print $2}' | cut -d@ -f1); do
  case " $KEEP_VETH " in *" $v "*) continue ;; esac
  ip link del "$v" 2>/dev/null && echo "  veth    $v"
done

# 3. the nat table. Delete POSTROUTING/PREROUTING jumps by line number,
#    descending, because deleting by rule spec breaks on the quoted comments
#    the plugins write. Then flush and drop the per-container chains.
for chain in POSTROUTING PREROUTING OUTPUT CNI-HOSTPORT-DNAT; do
  while :; do
    n=$(iptables -t nat -L "$chain" --line-numbers -n 2>/dev/null \
        | grep -E "$(echo "$NETS" | tr ' ' '|')" | awk 'NR==1{print $1}')
    [ -n "$n" ] || break
    iptables -t nat -D "$chain" "$n" && echo "  nat     $chain rule $n"
  done
done
# Two passes: dropping a CNI-DN-* chain can orphan nothing, but dropping the
# POSTROUTING jump above may have orphaned a CNI-<hash> chain that a CNI-DN-*
# chain still referenced.
for _ in 1 2; do
  for c in $(iptables -t nat -S | awk '/^-N CNI-/{print $2}'); do
    # keep the three shared CNI-HOSTPORT-* chains; other chains jump to them
    case "$c" in CNI-HOSTPORT-*) continue ;; esac
    refs=$(iptables -t nat -S | grep -c -- "-j $c" || true)
    if [ "$refs" -eq 0 ]; then
      iptables -t nat -F "$c" && iptables -t nat -X "$c" && echo "  nat     dropped chain $c"
    fi
  done
done

# 4. host-local's reservation tree and libcni's result cache
for n in $NETS; do
  [ -d "/var/lib/cni/networks/$n" ] && rm -rf "/var/lib/cni/networks/$n" && echo "  ipam    $n"
  rm -f /var/lib/cni/results/"$n"-* 2>/dev/null
done

echo "i9-reset: done"
