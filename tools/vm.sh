#!/usr/bin/env bash
# Run lab snippets on a Multipass VM without the three traps that waste a
# session's tool calls. Default VM is $CKA_VM or "sandbox".
#
#   tools/vm.sh run  'snippet'        run a snippet, print its output
#   tools/vm.sh cap  NAME 'snippet'   same, and save output to labs/captures/NAME.txt
#   tools/vm.sh put  LOCAL REMOTE     copy a file in  (multipass transfer cannot read /tmp/claude-*)
#   tools/vm.sh get  REMOTE [LOCAL]   copy a file out
#   tools/vm.sh clean                 reset runc lab state (containers, cgroups, strays)
#   tools/vm.sh shell 'cmd'           raw one-liner, no wrapping (use only for trivial reads)
#
# The traps this exists to avoid:
#  1. A container that outlives the command INHERITS the exec's stdout, so
#     `multipass exec` blocks until the container dies. Everything here runs
#     detached under setsid with output to a file on the VM, then reads it back.
#  2. `multipass transfer` is snap-confined and cannot read /tmp/claude-*.
#     `put` pipes through `multipass exec ... cat >` instead.
#  3. `strace -f runc create` never returns (create leaves runc init alive), and
#     any runaway snippet would hang the session. Everything is timeout-bounded.
set -euo pipefail
cd "$(dirname "$0")/.."

VM=${CKA_VM:-sandbox}
TIMEOUT=${CKA_VM_TIMEOUT:-90}

die(){ echo "vm.sh: $*" >&2; exit 1; }

vm_up(){
  multipass info "$VM" >/dev/null 2>&1 || die "VM '$VM' not found (multipass list)"
  [ "$(multipass info "$VM" --format csv | awk -F, 'NR==2{print $2}')" = Running ] \
    || die "VM '$VM' is not Running"
}

# Run a snippet detached on the VM, wait for it, print stdout+stderr and exit code.
# Scratch lives in ~/.vmrun, not /tmp: /tmp is sticky, so a root-owned output
# file from a sudo'ing snippet cannot be unlinked by the next run. ~/.vmrun has
# no sticky bit, so its owner can clear anything inside it.
vm_run(){
  local snippet=$1
  printf '%s\n' "$snippet" | multipass exec "$VM" -- bash -c 'mkdir -p ~/.vmrun && cat > ~/.vmrun/run.sh'
  multipass exec "$VM" -- bash -c "
    cd ~/.vmrun
    rm -f rc out
    setsid bash -c 'bash ~/.vmrun/run.sh; echo \$? > ~/.vmrun/rc' \
      > ~/.vmrun/out 2>&1 < /dev/null &
    for _ in \$(seq 1 $TIMEOUT); do [ -f rc ] && break; sleep 1; done
    cat out
    if [ -f rc ]; then
      rc=\$(cat rc)
      [ \"\$rc\" != 0 ] && echo \"vm.sh: snippet exited \$rc\" >&2
      exit 0
    else
      echo 'vm.sh: TIMED OUT after ${TIMEOUT}s — snippet still running on the VM.' >&2
      echo 'vm.sh: raise CKA_VM_TIMEOUT, or run tools/vm.sh clean.' >&2
      exit 1
    fi
  "
}

case ${1:-} in
  run)
    [ $# -ge 2 ] || die "usage: vm.sh run 'snippet'"
    vm_up; vm_run "$2"
    ;;

  cap)
    [ $# -ge 3 ] || die "usage: vm.sh cap NAME 'snippet'"
    vm_up
    mkdir -p labs/captures
    out="labs/captures/$2.txt"
    {
      echo "# captured $(date -u +%Y-%m-%dT%H:%M:%SZ) on $VM"
      echo "# --- snippet ---"
      printf '%s\n' "$3" | sed 's/^/# /'
      echo "# --- output ---"
      vm_run "$3"
    } | tee "$out"
    echo "vm.sh: saved -> $out" >&2
    ;;

  put)
    [ $# -eq 3 ] || die "usage: vm.sh put LOCAL REMOTE"
    [ -f "$2" ] || die "no such file: $2"
    vm_up
    multipass exec "$VM" -- bash -c "cat > '$3'" < "$2"
    echo "vm.sh: $2 -> $VM:$3" >&2
    ;;

  get)
    [ $# -ge 2 ] || die "usage: vm.sh get REMOTE [LOCAL]"
    vm_up
    dest=${3:-$(basename "$2")}
    multipass exec "$VM" -- bash -c "sudo cat '$2'" > "$dest"
    echo "vm.sh: $VM:$2 -> $dest" >&2
    ;;

  clean)
    vm_up
    vm_run '
      for c in $(sudo runc list -q 2>/dev/null); do sudo runc delete --force "$c"; done
      # Bracket the first letter: "sudo pkill -f microshim.py" has the pattern in
      # its OWN command line, so pkill kills the sudo wrapper. [m]icroshim.py
      # matches the target and not the literal text in this script.
      sudo pkill -9 -f "[m]icroshim\.py" 2>/dev/null || true
      sudo pkill -9 -x strace 2>/dev/null || true
      # leaked cgroups from any rm -rf repair (see I3.10)
      for d in /sys/fs/cgroup/user.slice/user-1000.slice/*/; do
        case "$d" in *session-*|*user-runtime-dir*|*"user@"*) continue;; esac
        [ -f "$d/cgroup.procs" ] && [ ! -s "$d/cgroup.procs" ] && sudo rmdir "$d" 2>/dev/null || true
      done
      echo "--- runc list:"; sudo runc list
      echo "--- strays:";    sudo pgrep -a "runc|microshim" || echo "(none)"
    '
    ;;

  shell)
    [ $# -ge 2 ] || die "usage: vm.sh shell 'cmd'"
    vm_up
    multipass exec "$VM" -- bash -c "$2" < /dev/null
    ;;

  *)
    sed -n '2,16p' "$0" | sed 's/^# \?//'
    exit 1
    ;;
esac
