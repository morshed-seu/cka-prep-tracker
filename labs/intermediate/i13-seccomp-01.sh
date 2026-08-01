#!/usr/bin/env bash
# I13 gauntlet fault i13-seccomp-01 (I13.7, layer 5 · security) — plants ONE
# fault: seccomp over-restriction, on the throwaway sandbox VM.
# Run on the sandbox VM:  sudo bash i13-seccomp-01.sh
# Do not read this file before the drill — it names the fault.
set -euo pipefail

BACKUPS=/root/.i13-fault-backups
BUNDLE=/root/i13-seccomp-bundle
CID=i13-seccomp-gauntlet

# The full set runc's own three-stage init plus a bare `sh -c echo` actually
# make on this host (captured live with `strace -f -c`), minus getdents64 —
# a syscall the workload never touches directly, only runc's own init does.
ALLOW="arch_prctl bind bpf brk capget capset chdir clone clone3 close close_range copy_file_range dup3 epoll_create1 epoll_ctl epoll_pwait eventfd2 execve exit exit_group faccessat2 fchdir fchmodat fchmodat2 fchown fchownat fcntl fsconfig fsmount fsopen fstat fstatfs futex getcwd getdents64 geteuid getpid getppid getrandom getsockname gettid getuid keyctl madvise mkdirat mknodat mmap mount mprotect munmap nanosleep newfstatat openat openat2 pidfd_open pidfd_send_signal pipe2 pivot_root poll prctl pread64 prlimit64 read readlink readlinkat recvfrom renameat rseq rt_sigaction rt_sigprocmask rt_sigreturn sched_getaffinity sched_setaffinity sched_yield seccomp sendto set_robust_list set_tid_address setgid setgroups sethostname setns setsid setuid shutdown sigaltstack socket socketpair statfs statx symlinkat syscall tgkill umask umount2 uname unlinkat unshare wait4 waitid write"

echo "============================================================"
echo " I13 gauntlet — fault i13-seccomp-01"
echo " About to BREAK: layer 5, security (seccomp over-restriction)"
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
for bin in runc python3; do
  command -v "$bin" >/dev/null || { echo "ABORT: $bin not found — is the intermediate toolchain installed?" >&2; exit 1; }
done

read -r -p "Type 'break' to plant the fault: " confirm
if [ "$confirm" != "break" ]; then
  echo "Aborted — nothing changed."; exit 0
fi

# ---- setup (idempotent): a bundle that runs cleanly under the FULL list ----
runc delete -f "$CID" >/dev/null 2>&1 || true
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/rootfs/bin" "$BUNDLE/rootfs/proc"
cp /usr/bin/busybox "$BUNDLE/rootfs/bin/busybox"
ln -sf busybox "$BUNDLE/rootfs/bin/sh"
(cd "$BUNDLE" && runc spec)
python3 - "$BUNDLE/config.json" "$ALLOW" <<'PY'
import json, sys
p, allow = sys.argv[1], sys.argv[2].split()
c = json.load(open(p))
c["process"]["args"] = ["/bin/sh", "-c", "echo seccomp-ok"]
c["process"]["terminal"] = False
c["linux"]["seccomp"] = {
    "defaultAction": "SCMP_ACT_KILL_PROCESS",
    "architectures": ["SCMP_ARCH_X86_64"],
    "syscalls": [{"names": allow, "action": "SCMP_ACT_ALLOW"}],
}
json.dump(c, open(p, "w"))
PY

if ! (cd "$BUNDLE" && timeout 10 runc run "$CID" 2>/tmp/i13-seccomp-check.log | grep -q seccomp-ok); then
  echo "ABORT: the full allow-list does not even run cleanly before the fault is planted." >&2
  cat /tmp/i13-seccomp-check.log >&2; exit 1
fi
runc delete -f "$CID" >/dev/null 2>&1 || true

mkdir -p "$BACKUPS"
cp "$BUNDLE/config.json" "$BACKUPS/seccomp-01.config.json.$(date +%Y%m%d-%H%M%S)"

# ---- plant: drop one syscall runc's own init needs, that the workload never
# calls directly — the profile looks like a reasonable hand-written allow-list.
python3 - "$BUNDLE/config.json" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
names = c["linux"]["seccomp"]["syscalls"][0]["names"]
names.remove("getdents64")
json.dump(c, open(p, "w"))
PY

echo
echo "Fault planted."
echo
echo "YOUR MISSION"
echo "  1. $BUNDLE ran cleanly a moment ago under this same seccomp profile."
echo "  2. It will not run now, and runc prints nothing that names a syscall."
echo "  3. Find out what killed it and why, fix the profile, then verify:"
echo "       cd $BUNDLE && sudo runc run i13fix"
echo "     should print 'seccomp-ok', not nothing."
echo
echo "Escape hatch (only if hopelessly stuck): a backup of the working config.json"
echo "is in $BACKUPS/seccomp-01.config.json.*"
echo "Hints & solution: materials/i13.html -> lesson I13.7, staged reveals (fault 8)."
