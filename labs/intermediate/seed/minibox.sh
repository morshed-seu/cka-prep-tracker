#!/usr/bin/env bash
# minibox — a container runtime in bash. Layers: fs, isolation, limits, network.
#
# This is the assembled form of what beginner module B14 builds one layer at a
# time (materials/b14.html, lessons B14.1–B14.4). It ships here so a reader who
# started at the Intermediate track can bootstrap the artefact the whole track
# argues about, in a minute rather than an evening — but the modules keep
# pointing back at B14, because the argument is about what the standards added
# to *this file*, not about the file itself.
#
# Three differences from the lesson's version, all marked below:
#   * an --init mode that builds the busybox rootfs B14.1 assembles by hand;
#   * the launcher quotes its arguments instead of splitting them on spaces;
#   * the capability drop happens INSIDE, after pivot_root, not before unshare —
#     see the note above stage 2. I0.3 and I3 both come back to why.
#
# Usage (on a throwaway VM, as root):
#   sudo ./minibox.sh --init            # build /srv/minibox from /bin/busybox
#   sudo ./minibox.sh /bin/sh           # run a shell inside
#   sudo IP=10.88.0.2 MEM_MAX=128M ./minibox.sh /bin/sh -c 'echo hi'
#   sudo ./minibox.sh --clean           # unmount and remove everything
#
# Environment: NAME CPU_MAX MEM_MAX PIDS_MAX IP GW DNS BRIDGE
set -euo pipefail
ROOT=/srv/minibox
NAME=${NAME:-minibox}
BRIDGE=${BRIDGE:-mb0}

# ---- wrong-box guard: this mounts, unshares, and writes NAT rules ----
guard() {
  [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
  if [ -d /etc/kubernetes ]; then
    echo "ABORT: /etc/kubernetes exists — this looks like a cluster node." >&2
    echo "minibox reconfigures mounts, netns and iptables. Use a throwaway VM." >&2
    exit 1
  fi
}

init_rootfs() {                      # B14.1, as a function instead of by hand
  install -d -m 755 "$ROOT"/{lower-base,lower-conf,upper,work,merged}
  install -d -m 755 "$ROOT"/lower-base/{bin,dev,etc,proc,sys,tmp,root}
  command -v busybox >/dev/null || { echo "install busybox first: apt install -y busybox-static" >&2; exit 1; }
  cp "$(command -v busybox)" "$ROOT/lower-base/bin/"
  chroot "$ROOT/lower-base" /bin/busybox --install -s /bin
  install -d -m 755 "$ROOT/lower-conf/etc"
  echo "$NAME" > "$ROOT/lower-conf/etc/hostname"
  printf 'root:x:0:0:root:/root:/bin/sh\n' > "$ROOT/lower-conf/etc/passwd"
  printf 'nameserver %s\n' "${DNS:-8.8.8.8}" > "$ROOT/lower-conf/etc/resolv.conf"
  install_capsh
  echo "rootfs ready: $(find "$ROOT/lower-base/bin" -type l | wc -l) applets in $ROOT/lower-base/bin"
}

# capsh has to live INSIDE the rootfs, because the capability drop is the last
# thing that happens before the workload runs — and by then pivot_root has made
# the host's /usr unreachable. runc needs no such trick: it is one process that
# unshares, pivot_roots, drops caps and execs, so it still has its own code in
# memory at the moment it drops privilege. This is the price of writing a
# runtime as a shell script that keeps handing control to other binaries.
install_capsh() {
  local capsh; capsh=$(command -v capsh) || {
    echo "install capsh first: apt install -y libcap2-bin" >&2; exit 1; }
  install -d -m 755 "$ROOT/lower-base"/{lib64,lib/x86_64-linux-gnu}
  install -m 755 "$capsh" "$ROOT/lower-base/bin/capsh"
  # ldd names exactly the shared objects the loader will look for; copy those,
  # nothing else, so the rootfs stays a rootfs and not a copy of the host.
  ldd "$capsh" | awk '/=> \//{print $3} /ld-linux/{print $1}' | while read -r so; do
    install -m 755 "$so" "$ROOT/lower-base$so"
  done
}

mount_rootfs() {                     # B14.1 — the overlay: lower + upper + work
  mountpoint -q "$ROOT/merged" && return 0
  [ -d "$ROOT/lower-base/bin" ] || { echo "no rootfs yet — run: $0 --init" >&2; exit 1; }
  rm -rf "$ROOT/upper" "$ROOT/work"; install -d -m 755 "$ROOT/upper" "$ROOT/work"
  mount -t overlay minibox-overlay \
    -o "lowerdir=$ROOT/lower-conf:$ROOT/lower-base,upperdir=$ROOT/upper,workdir=$ROOT/work" \
    "$ROOT/merged"
}

setup_net() {                        # B14.4 — $1 = pid of the process inside the netns
  local pid=$1 br=$BRIDGE ip=${IP:-10.88.0.2} gw=${GW:-10.88.0.1}
  ip link show "$br" >/dev/null 2>&1 || {
    ip link add "$br" type bridge; ip addr add "$gw/24" dev "$br"; ip link set "$br" up; }
  ip link add "mbv$pid" type veth peer name eth0 netns "$pid"
  ip link set "mbv$pid" master "$br" up
  nsenter -t "$pid" -n ip addr add "$ip/24" dev eth0
  nsenter -t "$pid" -n ip link set eth0 up
  nsenter -t "$pid" -n ip link set lo up
  nsenter -t "$pid" -n ip route add default via "$gw"
  sysctl -qw net.ipv4.ip_forward=1
  iptables -t nat -C POSTROUTING -s 10.88.0.0/24 ! -o "$br" -j MASQUERADE 2>/dev/null ||
    iptables -t nat -A POSTROUTING -s 10.88.0.0/24 ! -o "$br" -j MASQUERADE
  printf 'nameserver %s\n' "${DNS:-8.8.8.8}" > "$ROOT/merged/etc/resolv.conf"
}

setup_cgroup() {                     # B14.3 — create the cage and join it
  local cg=/sys/fs/cgroup/$NAME
  mkdir -p "$cg"
  echo "${CPU_MAX:-50000 100000}" > "$cg/cpu.max"
  echo "${MEM_MAX:-128M}"         > "$cg/memory.max"
  echo "${PIDS_MAX:-64}"          > "$cg/pids.max"
  echo $$ > "$cg/cgroup.procs"                    # this shell, and everything it forks
}

enter_rootfs() {                     # B14.2 — runs INSIDE the new namespaces
  mount --make-rprivate /
  mount --bind "$ROOT/merged" "$ROOT/merged"      # new root must be a mount point
  install -d "$ROOT/merged/.oldroot"
  cd "$ROOT/merged"
  pivot_root . .oldroot
  cd /
  umount -l /.oldroot && rmdir /.oldroot          # the host filesystem is now unreachable
  hash -r                                         # bash cached /usr/bin/mount; that path is gone
  mount -t proc proc /proc                        # the step everyone forgets
  hostname "$NAME"
}

clean() {
  mountpoint -q "$ROOT/merged" && umount -l "$ROOT/merged"
  ip link del "$BRIDGE" 2>/dev/null || true
  rmdir "/sys/fs/cgroup/$NAME" 2>/dev/null || true
  rm -rf "$ROOT"
  echo "minibox removed (the NAT rule for 10.88.0.0/24 is left in place)"
}

# ---- stage 2: we are already inside the namespaces ----
# Order matters and is the correction B14's listing gets wrong: unshare(2) and
# pivot_root(2) both require CAP_SYS_ADMIN, so a runtime that drops it first
# fails with EPERM before it has isolated anything. Isolate, then disarm.
if [ "${_MINIBOX_STAGE:-}" = "inside" ]; then
  enter_rootfs
  exec /bin/capsh --drop=cap_sys_admin,cap_net_admin,cap_sys_module,cap_sys_time \
    --no-new-privs --shell=/bin/sh -- \
    -c "exec $(printf '%q ' "${@:-/bin/sh}")"
fi

# ---- stage 1: the launcher, on the host ----
guard
case "${1:-}" in
  --init)  init_rootfs; exit 0 ;;
  --clean) clean; exit 0 ;;
esac
mount_rootfs
setup_cgroup

# The child is backgrounded rather than exec'd, because setup_net has to run on
# the HOST against the child's pid — which is exactly how every real runtime
# does it: the runtime creates the netns, then the network plugin configures it.
_MINIBOX_STAGE=inside unshare --mount --pid --uts --ipc --net --fork "$0" "$@" &
child=$!

# Wait for unshare to actually enter its new netns before wiring it: until the
# unshare(2) call returns, /proc/$child/ns/net is still the host's.
host_netns=$(readlink "/proc/self/ns/net")
for _ in $(seq 1 50); do
  [ -e "/proc/$child/ns/net" ] || break
  [ "$(readlink "/proc/$child/ns/net")" != "$host_netns" ] && break
  sleep 0.1
done
setup_net "$child" || echo "warning: network setup failed; the container is isolated but offline" >&2

rc=0; wait "$child" || rc=$?
exit "$rc"
