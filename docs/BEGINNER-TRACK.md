# Beginner Track — "The machine under Kubernetes"

Authoring source of truth for the beginner track, as [`PLAN.md`](PLAN.md) is for the advanced (CKA)
track. Written in phase **B-S1**; every later session reads its module section here before authoring.

## Why this track exists

The site's original track (`index.html` + `materials/w0–w8.html`) teaches Kubernetes to people who
already know Linux, networking and distributed systems. `materials/foundations.html` was a first
on-ramp — an 8-section primer — but a primer is not a curriculum: it tells you what a namespace *is*,
it never makes you build one. Feedback was consistent: readers without the substrate experienced
fully-detailed lessons as terse hints.

The site therefore becomes a three-track journey:

```
Beginner      the Linux / networking / distributed-systems machinery Kubernetes is built from   ← this doc
Intermediate  composing that machinery into containers, runtimes, images, CNI                   (future)
Advanced      Kubernetes itself, through the CKA                                                (exists)
```

**Philosophy.** Kubernetes invented very little. It composes decades-old operating-system,
networking and distributed-systems technology. So the beginner track never teaches a Kubernetes
concept — it teaches the *primitive*, hands-on, and then names the Kubernetes feature that wraps it.

**The structural device that enforces it.** Every conceptual beginner lesson ends with a mandatory
**"Where this shows up in Kubernetes"** block that names the specific feature and deep-links to the
exact advanced-track lesson anchor. A learner meets `cpu.max` throttling in B7 and meets it again as
`limits.cpu` in W3 — as recognition, not as new material. That block is what makes three tracks one
journey rather than three courses in a trench coat.

## Shape of the track

15 modules · 225 checkpoints · ~74 hours · self-paced. There is deliberately **no calendar**: the
8-week clock belongs to the advanced track. Ordering is strictly dependency-driven:

```
one machine → one process → what a process may do → its files → isolating it
            → its network → naming and supervising it → securing it → many machines → assemble
```

Each module is a prerequisite for the next. Extra prerequisites are noted per module.

**How the checkpoint counts are derived** (settled in B-S3, when the counts stopped being an
estimate): a module's total is the sum of its **checkpoint groups** below, **plus one checkpoint for
its mini project and one for its debugging drill**, which live in a trailing `Project & drill` group
on the tracker. They have to be tickable, because the module page anatomy gives each its own
`<article class="lesson project">` / `.drill`, and `tools/check-links.sh` requires exactly one tracker
checkpoint per lesson anchor. B0 has no drill (+1); B14's groups already *are* its capstone and
gauntlet (+0). That is why the track total is 225 rather than the ~200 first estimated in B-S1.

| # | Module | cps | hrs |
|---|---|---|---|
| B0 | Your Linux sandbox | 9 | 2 |
| B1 | Shell, files, and the filesystem tree | 16 | 4 |
| B2 | Processes, threads, signals | 18 | 6 |
| B3 | Kernel space, user space, system calls | 14 | 4 |
| B4 | Users, groups, permissions, capabilities | 15 | 4 |
| B5 | Files for real: VFS, storage, overlayfs | 18 | 6 |
| B6 | Isolation I — namespaces, chroot, pivot_root | 15 | 6 |
| B7 | Isolation II — cgroups v2 | 14 | 4 |
| B8 | Networking I — the real network | 18 | 6 |
| B9 | Networking II — virtual networking & packet filtering | 20 | 8 |
| B10 | Names — DNS and resolution | 13 | 4 |
| B11 | Service management — systemd, logs, boot | 14 | 4 |
| B12 | Security fundamentals | 16 | 5 |
| B13 | Distributed systems fundamentals | 15 | 5 |
| B14 | Capstone & track assessment | 10 | 6 |

## Module page anatomy

Every `materials/bN.html` carries, in order:

1. **Hero** — one plain-English paragraph on what the module is for, then three blocks:
   `<div class="objectives">` (learning objectives, 4–6 bullets), `<div class="prereq">`
   (which modules must be done first, and why), and estimated hours.
2. **Lesson articles**, grouped in `<div class="grp" id="g-…">` sections, one
   `<article class="lesson" id="cp-bN-M" data-id="bN-M">` per tracker checkpoint.
3. **Mini project** — its own checkpoint/article, `<article class="lesson project">`. Builds one
   working artifact the learner keeps and reuses in a later module.
4. **Debugging drill** — its own checkpoint/article, `<article class="lesson drill">`. Symptom first,
   then three-stage reveals (symptom → hint → full diagnosis), matching W6's proven pattern.
5. **Recall quiz** — `<div class="quiz" id="quiz">`, 8–12 `<details class="reveal">` questions.
6. **Outcome** — `<div class="outcome">` "You can now…" list, phrased as capabilities, not topics.
7. `<nav class="pager">` (prev/next module) and the version `<footer>`.

### Lesson anatomy

Same skeleton and the same plain-English-first voice as the advanced track's R0–R8 rewrite (see
`CLAUDE.md` § "Plain-English lesson voice"), with one addition and one substitution:

**Why it matters → The concept → Lab → Verify → Gotchas → Where this shows up in Kubernetes → Docs**

- **Where this shows up in Kubernetes** (`<div class="k8s-link">`) — mandatory on every conceptual
  lesson. Names the Kubernetes feature and links to the advanced lesson anchor
  (`materials/w3.html#cp-3-16`). Two or three sentences, no Kubernetes prerequisites assumed:
  "you have not met this yet, and when you do, it will be this."
- **Docs** — `man` pages (`man 7 namespaces`, `man 2 clone`), `Documentation/` kernel docs, RFCs.
  Not kubernetes.io: that's the advanced track's exam-docs training.
- C/Python program pairs render as two labeled `<pre class="cmd">` blocks inside
  `<div class="langpair">`. No tabs, no JS — both are always visible and both print.
- Diagrams: inline SVG on CSS vars (`var(--ink) var(--line) var(--accent) var(--code-bg) var(--muted)`),
  readable in both themes, one plain-English caption each.

### Lab environment

One throwaway **Multipass Ubuntu 24.04 LTS** VM named `sandbox` (2 vCPU / 4 GB / 20 GB), built in B0
and snapshotted so it can be wrecked and restored in under a minute. It is deliberately *not* one of
the CKA lab's `cp`/`node01`/`node02` VMs — the beginner track precedes cluster building, and every
lab here is destructive by design.

All networking labs run inside network namespaces on that single VM rather than across two machines:
it is more instructive (you build both ends), it costs no extra RAM, and it is exactly the technique
the Intermediate Track's CNI work needs.

**Version-sensitive facts to re-verify by web search at the start of every authoring session** — never
from memory:

- Ubuntu 24.04 defaults: cgroup **v2** unified hierarchy only; `iptables` is the **nftables** backend
  (`iptables-nft`); `systemd-resolved` stub resolver at `127.0.0.53`.
- `kernel.apparmor_restrict_unprivileged_userns=1` on 24.04 restricts unprivileged user namespaces.
  B6's labs must **explain** this rather than silently working around it with `sudo`.
- Whether `multipass launch 24.04` is still the current LTS image alias.
  **Checked 2026-07-23: it is not the newest.** Ubuntu **26.04 LTS ("Resolute Raccoon")** has shipped, and
  Multipass's dynamic `lts` alias now points at it. 24.04 (`noble`) is still available and is what this
  track and the CKA lab are authored against, so every lab must launch it **explicitly** —
  `multipass launch 24.04 --name sandbox …` — and must never use `multipass launch lts`, which would
  silently hand the reader a different kernel and different defaults from the pasted output.

---

## B0 — Your Linux sandbox

**Prerequisites:** none. This is the front door of the whole site for a beginner.
**9 checkpoints · ~2 hours**

**Objectives.** Build a Linux machine you own and can destroy; restore it from a snapshot in under a
minute; install the toolbelt every later module assumes; know how to look up a command without a
search engine; understand how this site's checkpoints, labs, quizzes and tracks fit together.

**Checkpoint groups**
- *How to use this track* (2) — the three tracks and why this order; how checkpoints, labs, verify
  steps and quizzes work; that progress is per-browser localStorage.
- *The sandbox VM* (3) — install Multipass; launch `sandbox` (Ubuntu 24.04, 2 vCPU/4 GB/20 GB);
  shell in, confirm `uname -a`, `lsb_release -a`, `free -h`, `nproc`.
- *Toolbelt & safety* (3) — install `build-essential strace ltrace iproute2 tcpdump nftables jq tree
  dnsutils socat`; snapshot and restore; reading `man` (sections 1/2/5/7/8), `--help`, `apropos`.

**Mini project.** `snapshot.sh` / `restore.sh` — two short wrappers around `multipass snapshot` /
`multipass restore` so restoring is one command with no flags to remember. This removes the fear that
makes beginners avoid the interesting labs.

**Debugging drill.** None (nothing to break yet).

**Outcome.** A disposable Linux machine, a toolbelt, and a restore reflex.

**Feeds forward to.** W0's three-VM kubeadm lab build (`materials/w0.html#cp-0-5`).

---

## B1 — Shell, files, and the filesystem tree

**Prerequisites:** B0.
**16 checkpoints · ~4 hours**

**Objectives.** Move around any Linux box without a file manager; read `ls -l` completely; compose
small tools with pipes; understand exit codes; know where the system keeps things and why; edit a
file in vim without panic.

**Checkpoint groups**
- *Paths and the tree* (4) — absolute vs relative, `.`/`..`/`~`; the FHS tour (`/etc /var /usr /home
  /tmp /dev /proc /sys`) framed as "config, state, programs, people, scratch, devices, kernel";
  file types in `ls -l` column one; `stat`.
- *Composing tools* (5) — stdin/stdout/stderr as three separate pipes; `>`/`>>`/`2>`/`&>`; `|`;
  globbing vs regex (the single most common beginner confusion); the working core of
  `grep sed awk cut sort uniq wc head tail find xargs`.
- *The shell itself* (4) — shell variables vs `export`ed environment variables; `env`, `PATH`
  resolution and `which`/`type`; quoting rules (`'` vs `"` vs none); exit codes, `$?`, `&&`/`||`;
  writing and running a script, shebangs, `chmod +x`.
- *Editing* (1) — vim survival: modes, `i`, `:wq`, `dd`, `/search`, `u`, visual-block indent, and
  `set ts=2 sw=2 et` for YAML later.

**Mini project.** `sysreport.sh` — collect kernel version, uptime, memory, top 5 processes by RSS,
disk usage and listening ports into one readable report, built entirely from pipes. Reused as the
"before" snapshot in later debugging drills.

**Debugging drill.** A broken `PATH` ("command not found" for a binary that exists) and a script that
silently does the wrong thing because of unquoted variable expansion with spaces.

**Outcome.** Can inspect any Linux box and build a one-off answer out of standard tools.

**Feeds forward to.** W0.9–0.10 (aliases, completion, `.vimrc`); every lab on the site.

---

## B2 — Processes, threads, signals

**Prerequisites:** B1.
**18 checkpoints · ~6 hours**

**Objectives.** Say precisely what a process *is*; read the process tree; interpret every process
state including D and Z; explain fork/exec/wait; predict what a signal does; write a program that
shuts down gracefully; explain exit code 137 before ever seeing a container.

**Checkpoint groups**
- *What a process is* (4) — address space + file descriptors + credentials + a PID; `ps` output
  columns; `pstree`; `/proc/PID/{cmdline,environ,fd,status,maps}` as the process's own X-ray.
- *Lifecycle* (5) — `fork()` then `exec()` then `wait()`, and why they're three calls and not one;
  parent/child and PPID; states R/S/D/Z/T and what each means for a stuck process; exit codes,
  including the **128 + signal** convention; orphans, re-parenting to PID 1, zombies and reaping;
  what PID 1 owes its children.
- *Threads* (2) — threads as processes sharing an address space; `/proc/PID/task`, `ps -L`; when the
  distinction matters (shared memory, per-thread state, `top -H`).
- *Signals* (5) — the signal table worth memorizing (TERM, KILL, INT, HUP, STOP, CONT, CHLD, SEGV);
  default actions; catching signals in a handler; why KILL and STOP cannot be caught; `kill`/`pkill`;
  the graceful-shutdown pattern: catch TERM → finish work → exit, and what happens if you don't.

**Mini project.** A **mini-supervisor** in C *and* Python: fork a child, forward SIGTERM to it, wait,
report whether it exited or was signalled, restart it on crash with a backoff. This is, structurally,
a baby kubelet — and B11 turns it into a real systemd unit.

**Debugging drill.** Three symptoms: a zombie army (parent not reaping), a process wedged in `D`
state (uninterruptible I/O), and a service that ignores SIGTERM and only dies to the SIGKILL that
follows the grace period.

**Outcome.** Can narrate exactly what happens between "stop this workload" and the process dying.

**Feeds forward to.** Pod termination and `terminationGracePeriodSeconds`
(`materials/w3.html#cp-3-5`), exit code 137 (`materials/w3.html#cp-3-16`), kubelet's supervision role
(`materials/w1.html#cp-1-19`).

---

## B3 — Kernel space, user space, system calls

**Prerequisites:** B2.
**14 checkpoints · ~4 hours**

**Objectives.** Draw the user/kernel boundary; explain what crossing it costs and why it exists; read
an `strace` and tell the program's story from it; triage an error from its `errno`; know `/proc` and
`/sys` as APIs rather than folders.

**Checkpoint groups**
- *The boundary* (4) — what the kernel exclusively owns (hardware, memory maps, scheduling, the
  network stack); user mode vs kernel mode; the syscall as the only doorway; libc as a thin wrapper,
  shown by `ltrace` vs `strace` on the same binary.
- *Reading syscalls* (4) — `strace` anatomy (call, arguments, return, errno); the syscalls worth
  recognizing on sight: `openat read write close execve clone wait4 mmap ioctl socket connect`;
  file descriptors as the universal handle; `strace -c` summaries; `strace -f` for children.
- *Kernel interfaces* (4) — `/proc` and `/sys` as filesystems that are really kernel APIs; `sysctl`
  and where the values persist; `dmesg` and the kernel ring buffer; `ulimit`/`rlimits`.

**Mini project.** Annotate a complete `strace` of one `curl http://example.com` — every syscall
grouped into a phase (load, resolve, socket, connect, write, read, exit) with one sentence each.
Plus the same "hello" written three ways (shell `echo`, C `write(2)`, Python `os.write`) compared
under `strace -c`.

**Debugging drill.** File-descriptor exhaustion via a deliberately low `ulimit -n`, and an `errno`
ladder: distinguishing `ENOENT` from `EACCES` from `EPERM` from `EISDIR` by symptom alone.

**Outcome.** Can find out what a program is *actually* doing when logs don't say.

**Feeds forward to.** Why nodes need `net.ipv4.ip_forward` and `fs.inotify.max_user_instances`
(`materials/w0.html#cp-0-6`), node-level triage (`materials/w6.html`).

---

## B4 — Users, groups, permissions, capabilities

**Prerequisites:** B1 (B2 helpful).
**15 checkpoints · ~4 hours**

**Objectives.** Predict whether an operation will be permitted before running it; read and write mode
bits in octal; explain why directory `x` is not file `x`; explain root as ~40 separate capabilities
rather than one flag; explain why "root inside a container" is not root on the host.

**Checkpoint groups**
- *Identity* (4) — uid/gid/euid; `/etc/passwd`, `/etc/group`, `/etc/shadow` field by field; system
  users vs login users and why services get their own; `id`, `su`, `sudo`, sudoers basics.
- *Permissions* (5) — the rwx triad on files vs on **directories** (r = list, x = traverse); octal;
  `chmod`/`chown`; `umask` and where default permissions come from; setuid/setgid/sticky and the
  `/tmp` and `passwd(1)` examples; ACLs briefly.
- *Capabilities* (4) — root decomposed: `CAP_NET_BIND_SERVICE`, `CAP_NET_ADMIN`, `CAP_SYS_ADMIN`,
  `CAP_CHOWN`, `CAP_DAC_OVERRIDE`; `getcap`/`setcap`; permitted/effective/bounding sets at working
  depth; `no_new_privs`; capabilities as *the* reason a container can be "root" and still harmless.

**Mini project.** Serve HTTP on port 80 as a non-root user three ways — setuid binary, file
capability, and a high port plus a DNAT redirect — then compare the blast radius of each.

**Debugging drill.** A permission-denied ladder on a mounted directory (traverse bit missing three
levels up), and a setuid binary that stops working after `cp` (bits and ownership not preserved).

**Outcome.** Can read any `securityContext` and predict its effect before applying it.

**Feeds forward to.** `runAsUser`/`fsGroup`/`capabilities.drop`/`allowPrivilegeEscalation`
(`materials/w3.html`), the authn-vs-authz split in RBAC (`materials/w7.html#cp-7-7`).

---

## B5 — Files for real: VFS, storage, overlayfs

**Prerequisites:** B1, B4.
**18 checkpoints · ~6 hours**

**Objectives.** Explain what mounting actually does; tell an inode from a filename; diagnose a full
disk that has no large files; build a layered filesystem by hand and find the copy-up; explain what a
container image layer physically is.

**Checkpoint groups**
- *Devices and filesystems* (4) — block devices, `lsblk`; partitions; `mkfs`; `mount`/`umount` and
  what the mount table (`findmnt`, `/proc/mounts`) really lists; `/etc/fstab`.
- *The VFS view* (4) — one interface over many filesystems; inodes vs directory entries; hard links
  vs symlinks demonstrated with `ln`; `df` vs `du`, deleted-but-open files, and inode exhaustion.
- *Special mounts* (4) — `tmpfs` and RAM-backed storage; loop devices; **bind mounts**; **mount
  propagation** (private / shared / rslave) and why a container runtime cares.
- *Overlayfs* (4) — lowerdir / upperdir / workdir / merged; mounting one by hand; **copy-up** on
  first write; whiteout files on delete; why images are layers and why containers are "the same image
  plus a thin writable layer".

**Mini project.** Build an "image" by hand: three lowerdirs stacked under one upperdir, mounted
merged; modify a file from the bottom layer and locate the copy-up; delete one and locate the
whiteout; then reset the upper and watch the original reappear.

**Debugging drill.** A disk that is 100% full with only a few MB of files (inodes), a bind mount that
refuses to propagate, and a "stale file handle" after an unmount under a running process.

**Outcome.** Understands container images physically, not by analogy.

**Feeds forward to.** Image layers (Intermediate), `emptyDir`/`hostPath` and volume mechanics
(`materials/w5.html#cp-5-1`), kubelet's `/var/lib/kubelet/pods` (`materials/w1.html#cp-1-23`).

---

## B6 — Isolation I — namespaces, chroot, pivot_root

**Prerequisites:** B2, B3, B5.
**15 checkpoints · ~6 hours**

**Objectives.** Name all eight namespace types and what each hides; create them with `unshare` and
join them with `nsenter`; explain why a new PID namespace needs `/proc` remounted; explain the
difference between `chroot` and `pivot_root` and why the former is not a security boundary; build
something that is recognizably a container.

**Checkpoint groups**
- *The idea* (3) — isolation as "your own copy of one kernel resource"; the eight types (mnt, pid,
  net, ipc, uts, user, cgroup, time) in a table with the question each answers; `/proc/PID/ns` and
  reading namespace identity by inode.
- *Hands-on per namespace* (6) — UTS (own hostname); PID (own process list, PID 1 semantics, killing
  it ends the namespace); mount (own mount table, `--mount-proc`, propagation from B5); IPC;
  **user** (uid mapping, rootless containers, and Ubuntu 24.04's
  `apparmor_restrict_unprivileged_userns` restriction — explained, not bypassed); cgroup namespace.
- *Roots and entering* (3) — `chroot`, the classic escape, and why it is convenience not security;
  `pivot_root` and what it needs; `nsenter`/`setns` — joining someone else's namespaces, which is
  what `kubectl exec` and every node-level debug session actually are.
- *Net namespace preview* (1) — created here, wired up in B9.

**Mini project.** **container v0.1** — a minimal rootfs (debootstrap or a busybox tarball) run under
`unshare --pid --mount --uts --ipc --fork`, with `pivot_root` and `/proc` mounted, giving a shell that
genuinely believes it is alone on a machine. ~25 lines, no runtime installed.

**Debugging drill.** `ps` inside the new PID namespace listing host processes (missing `/proc`
remount), and a namespace that will not go away (a leaked bind mount of `/proc/PID/ns/net` holding it).

**Outcome.** Knows what "the pod's shared namespaces" means and what the pause container is holding.

**Feeds forward to.** The pause container (`materials/w1.html#cp-1-21`), pod networking
(`materials/w4.html#cp-4-2`), the Intermediate Track's runtime work.

---

## B7 — Isolation II — cgroups v2

**Prerequisites:** B2, B6.
**14 checkpoints · ~4 hours**

**Objectives.** Explain what a cgroup controls and what it doesn't; navigate `/sys/fs/cgroup`; set a
CPU cap and *measure* the throttling; trigger an OOM kill deliberately and read the evidence;
explain why CPU pressure makes things slow and memory pressure makes things dead.

**Checkpoint groups**
- *The model* (4) — resource control vs isolation (cgroups limit, namespaces hide); v1 vs v2 and why
  24.04 is v2-only; the unified hierarchy tour; `cgroup.subtree_control`, delegation, and the
  no-internal-process rule.
- *CPU* (3) — `cpu.weight` (proportional share under contention) vs `cpu.max` (hard quota per
  period); `cpu.stat`'s `nr_throttled`/`throttled_usec`; why a throttled process looks "slow for no
  reason" on an idle box.
- *Memory, pids, io* (3) — `memory.current`, `memory.high` (throttle) vs `memory.max` (kill);
  `memory.events`; the OOM killer and the resulting **exit code 137**; `pids.max` (fork-bomb
  containment); `io.max` briefly.
- *In practice* (2) — moving a process with `cgroup.procs`; systemd slices/scopes and reading a
  service's cgroup from `systemctl status`.

**Mini project.** Cap a busy loop at 50% of one CPU and prove it with `time` + `cpu.stat`; then cap a
memory hog and watch `dmesg` record the OOM kill and the shell report 137.

**Debugging drill.** "It's slow but the CPU is idle" (throttling) and "it dies with no error message
in its own logs" (OOM killer — the evidence is in `dmesg`, not the app).

**Outcome.** Understands requests, limits, QoS classes, throttling and evictions before meeting them.

**Feeds forward to.** Requests vs limits and cgroup enforcement (`materials/w3.html#cp-3-16`), QoS
classes (`materials/w3.html#cp-3-17`), node-pressure eviction (`materials/w3.html#cp-3-18`).

---

## B8 — Networking I — the real network

**Prerequisites:** B1, B3.
**18 checkpoints · ~6 hours**

**Objectives.** Use the layers as a troubleshooting ladder rather than exam trivia; do CIDR math in
your head for common masks; read a routing table and predict which route wins; explain a TCP
connection from handshake to teardown; find out whether a problem is link, address, route, filter or
listener — in that order, every time.

**Checkpoint groups**
- *Layers and addresses* (4) — the four layers as a decision ladder; MAC addresses, ARP and the
  neighbour table; IPv4 addressing, masks, CIDR math, network/broadcast/gateway; `ip addr`, `ip link`.
- *Routing* (3) — the routing table, longest-prefix match, the default route; `ip route get` as the
  "which way would this packet go" oracle; ICMP, `ping`, `traceroute`.
- *Transport* (5) — TCP handshake, states, teardown, and what each state means when you see it;
  UDP and when it's chosen; ports and the 4-tuple that identifies a connection; listening vs
  established in `ss -ltnp` / `ss -tnp`; MTU and black-hole symptoms.
- *Observing* (4) — `tcpdump` reading (filters, `-nn`, what one line means); `curl -v` as an
  app-layer probe; the anatomy of an HTTP request/response; the five-rung triage ladder as a
  memorized routine.

**Mini project.** "Trace a packet": document one `curl` end-to-end — name resolution, route lookup,
ARP, TCP handshake, HTTP request/response, teardown — with real `tcpdump`, `ss` and `ip route get`
output pasted under each stage.

**Debugging drill.** An unreachable host solved strictly by the ladder; a wrong netmask that makes
"some" hosts unreachable; and an MTU black hole where ping works and large transfers hang.

**Outcome.** Network problems become a routine instead of guesswork.

**Feeds forward to.** All of W4, and network triage in W6 (`materials/w6.html`).

---

## B9 — Networking II — virtual networking & packet filtering

**Prerequisites:** B6, B8. *The heaviest module — plan two sittings.*
**20 checkpoints · ~8 hours**

**Objectives.** Build a working private network out of namespaces, veth pairs and a bridge; route and
NAT its traffic to the outside; read and write netfilter rules; explain DNAT-based load balancing;
explain why a unix socket is a filesystem object with permissions.

**Checkpoint groups**
- *Virtual wiring* (5) — network namespaces revisited; **veth pairs** as virtual patch cables;
  **bridges** as virtual switches; giving namespaces addresses and routes; connecting two namespaces
  and proving it with ping and tcpdump on both ends.
- *Getting out* (4) — `ip_forward` and the host as a router; NAT concepts: SNAT, MASQUERADE, DNAT;
  wiring egress from the private subnet to the internet; **conntrack** and why NAT needs state.
- *Netfilter* (5) — the hook points and packet path diagram; tables/chains/rules/targets; the
  `filter` vs `nat` distinction that explains "ping works but curl doesn't"; nftables as the real
  backend on 24.04 and `iptables-nft` as the compatibility face; rule-order debugging.
- *Load balancing and sockets* (4) — DNAT plus `-m statistic --mode random` as a round-robin
  load balancer (this *is* kube-proxy's iptables mode); host port forwarding; **unix domain sockets**
  (stream vs datagram, filesystem permissions, abstract namespace), `socat`/`nc` over UDS, and why
  access to `containerd.sock` is equivalent to root.

**Mini project.** **CNI v0.1** in two scripts: (1) create N namespaces on a bridge with IPs from a
subnet, routes, and masqueraded egress; (2) publish a host port that round-robins into two of them.
That is a pod network and a Service, hand-built, before either word is introduced.

**Debugging drill.** Ping works but curl doesn't (filter vs nat); a DNAT rule that never matches
(wrong chain / wrong order); and a conntrack entry pinning traffic to an endpoint that is already gone.

**Outcome.** Has already built the mechanism behind CNI, ClusterIP, NodePort and NetworkPolicy.

**Feeds forward to.** Building a pod network by hand (`materials/w4.html#cp-4-2`), kube-proxy's
iptables walk (`materials/w4.html#cp-4-9`), NetworkPolicy (`materials/w4.html#cp-4-17`).

---

## B10 — Names — DNS and resolution

**Prerequisites:** B8 (B9 helpful).
**13 checkpoints · ~4 hours**

**Objectives.** Explain what happens between a hostname and an IP address, in order; read
`/etc/resolv.conf` including `search` and `ndots`; read `dig` output; run a resolver and break it
deliberately; diagnose "it resolves from here but not from there".

**Checkpoint groups**
- *The client side* (4) — the resolver library and `nsswitch.conf` (why `ping` and `dig` can
  disagree); `/etc/hosts`; `/etc/resolv.conf`: `nameserver`, `search`, `options ndots`; how a short
  name becomes a series of queries.
- *The system side* (3) — recursive vs authoritative; the root → TLD → authoritative walk;
  `systemd-resolved` and the `127.0.0.53` stub on Ubuntu.
- *Records and caching* (4) — A, AAAA, CNAME, PTR, SRV, TXT, NS and what each is for; TTL and
  caching; negative caching; `dig` anatomy (question, answer, authority, flags, query time).

**Mini project.** Run `dnsmasq` with a small fake zone, point the box at it, and resolve those names
from inside a network namespace built in B9.

**Debugging drill.** Break resolution three ways — wrong nameserver, a `search` domain that silently
rewrites queries, and a stale cached record — and identify each from symptoms before looking.

**Outcome.** `ndots:5` and the cluster search-path ladder are obvious rather than magic.

**Feeds forward to.** CoreDNS and the resolution ladder (`materials/w4.html#cp-4-12`), headless
Services (`materials/w4.html#cp-4-14`).

---

## B11 — Service management — systemd, logs, boot

**Prerequisites:** B2, B7.
**14 checkpoints · ~4 hours**

**Objectives.** Write a unit file from scratch; explain the difference between ordering and
requirement; use drop-ins instead of editing vendor units; find out why a service won't start from
`systemctl status` and `journalctl` alone; explain what supervises the supervisor on a node.

**Checkpoint groups**
- *Units* (5) — what init is for; unit types (service, socket, timer, target, mount); unit file
  anatomy; `ExecStart`, `Restart`, `RestartSec`, `Type=`; `After` vs `Requires` vs `Wants`.
- *Operating* (4) — the `systemctl` verbs that matter; **drop-ins** in
  `/etc/systemd/system/x.service.d/` and `daemon-reload`; environment files; enable vs start.
- *Logs and boot* (3) — journald: `-u`, `-f`, `--since`, priorities, persistence; reading exit
  status vs signal in `systemctl status`; boot targets; systemd's cgroup slices (tie back to B7).

**Mini project.** Promote B2's mini-supervisor into a real unit: restart policy, environment file,
journald logging, `systemctl enable`; then add a `.timer` that runs B1's `sysreport.sh` hourly.

**Debugging drill.** A unit that won't start (read the failure from status: exit code vs signal), and
a `Restart=always` loop that hides a config error behind an endless restart.

**Outcome.** `systemctl status kubelet` and `journalctl -u kubelet` become fluent reading.

**Feeds forward to.** kubelet as the only systemd service and static pods
(`materials/w1.html#cp-1-2`), kubelet troubleshooting (`materials/w6.html`).

---

## B12 — Security fundamentals

**Prerequisites:** B4, B8.
**16 checkpoints · ~5 hours**

**Objectives.** Frame a system's trust boundaries; tell hashing, encoding and encryption apart; run
your own CA; issue and verify a certificate with correct SANs; set up mutual TLS and read every
failure mode's error message; explain why base64 in a config file protects nothing.

**Checkpoint groups**
- *Framing* (3) — threat modeling in one page (assets, actors, trust boundaries); least privilege and
  defense in depth as decisions, not slogans; the difference between authentication and authorization.
- *Crypto in plain terms* (4) — hashing vs encoding vs encryption (and base64 as neither);
  symmetric vs asymmetric keys; signatures; SSH keys and the agent as the everyday example.
- *PKI hands-on* (5) — build a CA (key + self-signed cert); generate a CSR; **SAN extensions** and why
  CN alone stopped working; sign; verify a chain; inspect with `openssl x509 -text`; run a TLS server
  and connect with `s_client`; add a **client certificate** for mutual TLS; expiry and renewal.
- *Handling secrets* (2) — env vars leaking through `/proc/PID/environ` and process listings; file
  permissions for key material; seccomp and AppArmor at "what it is, here's one profile" depth.

**Mini project.** Two local processes doing mutual TLS, each verifying the other against your CA.

**Debugging drill.** Break that mTLS four ways — expired cert, wrong SAN, unknown CA, mismatched
key — and map each distinct error message to its cause without guessing.

**Outcome.** kubeadm's PKI, kubeconfig identities and CSR approval are familiar shapes on arrival.

**Feeds forward to.** The PKI trust domains (`materials/w2.html#cp-2-5`), certificate inspection
(`materials/w2.html#cp-2-7`), CSR onboarding (`materials/w7.html#cp-7-1`), why Secrets are only
base64 (`materials/w3.html#cp-3-23`).

---

## B13 — Distributed systems fundamentals

**Prerequisites:** B2, B8, B11.
**15 checkpoints · ~5 hours**

**Objectives.** Say what changes the moment there are two machines instead of one; do quorum
arithmetic and explain odd member counts; explain consensus at "teach a colleague" level; recognize
the reconciliation loop as a pattern and implement one; explain why every distributed action must be
idempotent and every failure detector must guess.

**Checkpoint groups**
- *What changes* (4) — why one machine isn't enough (scale, availability, blast radius); partial
  failure — the defining difference; no shared clock; the eight fallacies; latency numbers worth
  knowing.
- *State and agreement* (5) — stateless vs stateful services; leader/follower replication; strong vs
  eventual consistency in plain terms; CAP as a practical trade-off; **quorum arithmetic** (majority
  of N, why 3 and 5, why even numbers buy nothing); **consensus/Raft**: leader election, log
  replication, commit; split brain and fencing. *(As built in B-S4: the group's count is 5, and the
  bullet lists more topics than that — split brain and fencing ride along with the Raft checkpoint
  they motivate, rather than taking a sixth slot.)*
- *Patterns* (4) — leases and leader election; idempotency and at-least-once delivery; retries with
  backoff and jitter; **the reconciliation loop** (desired vs observed vs act) and watch-vs-poll;
  heartbeats, timeouts, and why a tight timeout invents failures that didn't happen.

**Mini project.** Two artifacts: (1) a **reconciler** that keeps N worker processes alive by
comparing desired to observed state and acting on the difference — the controller pattern in ~40
lines; (2) a three-member quorum simulation where killing members shows exactly when writes must stop.

**Debugging drill.** A reconciler that fights itself because its action isn't idempotent, and a
heartbeat timeout tuned so tightly it reports healthy peers as dead.

**Outcome.** The entire Kubernetes control plane becomes an instance of patterns already practiced.

**Feeds forward to.** Raft and etcd quorum (`materials/w1.html#cp-1-9`), the controller pattern
(`materials/w1.html#cp-1-16`), leader election (`materials/w1.html#cp-1-18`), node heartbeats and
leases (`materials/w1.html#cp-1-22`).

---

## B14 — Capstone & track assessment

**Prerequisites:** all of B0–B13.
**10 checkpoints · ~6 hours**

No new concepts. Everything here is assembly and proof.

**Checkpoint groups**
- *Capstone* (4) — build `minibox` incrementally, one checkpoint per layer: rootfs on overlayfs →
  namespaces + pivot_root → cgroup limits + dropped capabilities → bridge networking with NAT, DNS,
  and a systemd unit to supervise it.
- *Gauntlet* (3) — the timed eight-fault debugging run, then a written post-mortem of your own
  triage order, then a second run against the clock.
- *Assessment* (3) — the written self-test; the practical task set; the readiness checklist for the
  Intermediate Track.

**Capstone project.** **`minibox`** — one script that runs a process in its own mnt/pid/uts/ipc/net
namespaces, on an overlayfs rootfs, inside a cgroup with CPU and memory caps, with dropped
capabilities, attached to a bridge with an IP, NAT egress and working DNS, supervised by systemd and
logging to journald. Roughly 150 lines of bash that is, honestly, a container runtime.

**Debugging gauntlet.** `labs/beginner/*.sh` — eight scripts, one planted fault per layer
(permission, cgroup, mount, route, iptables, DNS, systemd unit, certificate), 45 minutes, hints and
solutions as three-stage reveals on the module page. Same contract as `labs/faults/`: banner,
`read -p` confirmation, wrong-box guard (`hostname` must be `sandbox`), no solution in the output,
shellcheck-clean.

**Track assessment.** `mock/beginner-final.html` — 30 recall questions plus 8 practical tasks, each
mapped back to the module that taught it; `mock/beginner-final-solutions.html` carries solutions,
verification commands and a rubric with a 66% pass line, mirroring `mock/exam-1.html`.

**Outcome / handoff.** The Intermediate Track opens by rebuilding this capstone properly: "build a
mini Docker" becomes "replace bash `minibox` with the OCI runtime spec and `runc`"; "build a simple
CNI" becomes "make your B9 script speak the CNI ADD/DEL contract". The module closes with an explicit
*"you are ready for Intermediate when you can…"* checklist.

---

## Site mechanics

### Files

| File | Role |
|---|---|
| `beginner.html` | The beginner tracker. Structural copy of `index.html` minus the exam countdown; sections `<section class="wk" id="bN" data-title="B0 · Sandbox">`, checkpoints `<li class="cp" data-id="bN-M">`; own `PUBLISHED` array |
| `materials/b0.html … b14.html` | One page per module |
| `labs/beginner/*.sh` | Fault scripts (B14 gauntlet, plus drills where a script beats prose) |
| `mock/beginner-final*.html`, `mock/setup-beginner-final.sh` | Track assessment |
| `assets/site.css` | Gains `.tracks .objectives .prereq .outcome .project .drill .k8s-link .langpair`; everything else is reused |
| `assets/lesson.js` | **Unchanged** — done-sync keys off `data-id`; nav/collapse/copy logic is already generic |

### Anchor scheme

Tracker `data-id="b3-7"` ↔ lesson `<article class="lesson" id="cp-b3-7" data-id="b3-7">`.
One rule covers both tracks: **anchor id = `cp-` + data-id with a leading `w` stripped** — so
`w3-7 → cp-3-7` (unchanged) and `b3-7 → cp-b3-7`. `tools/check-links.sh` enforces it over the pairs
(`index.html`, `materials/w*.html`) and (`beginner.html`, `materials/b*.html`).

### Shared state

One `cka-prep-v1` localStorage key for both tracks — beginner ids are namespaced by their `b` prefix,
so they cannot collide and cross-track sync is free. Each tracker's reset button filters to its own
prefix so resetting one track never wipes the other.

### Hours panel

Where `index.html` has the days-until-exam panel, `beginner.html` has an hours-left panel — this
track has no calendar, so the honest unit of "how much is left" is lab time. Each
`<section class="wk" id="bN">` carries `data-hours="N"` (the module's budget from the table above,
74 in total); the tracker's `refresh()` sums each module's budget scaled by the share of its
checkpoints still unticked, and prints that plus the number of modules still open. Adding or
re-budgeting a module means updating that attribute, the module table above, and the hero counter.

### Track switcher

A three-pill `.tracks` block in every sidebar (Beginner / Intermediate · soon / Advanced · CKA). The
per-page "Site" list is **not** merged: CKA pages list CKA weeks, beginner pages list beginner
modules, and the switcher is the only crossing point.

`materials/foundations.html` stays as the express refresher for readers who already know this
material, with a "go deep → Module Bx" link in each of its eight sections.

## Session plan

Each phase below is one session, start to finish, ending with green checkers, a commit, and a site
that renders with nothing half-written. No session depends on another session's in-memory context.

**Resume recipe:** read `CLAUDE.md`'s beginner roadmap row → read this doc's module section →
`git log --oneline -8` → run the checkers for a green baseline → do the work → checkers → commit →
tick the `CLAUDE.md` row and update the `cka-materials-plan` memory.

| Phase | Scope |
|---|---|
| **B-S1** | This document. Docs-only commit |
| **B-S2** | Wiring, no content: `site.css` additions; generalize `tools/check-links.sh` and `tools/check-html.py`; track switcher into all existing sidebars; `index.html` hero + prefix-scoped reset; `foundations.html` banner and go-deep links; stub `beginner.html` with `PUBLISHED=[]` |
| **B-S3** | `beginner.html` sections **B0–B7** (119 checkpoints) — ✅ done |
| **B-S4** | `beginner.html` sections **B8–B14** (106 checkpoints), hours panel — ✅ done |
| **B-S5** | `materials/b0.html` — **the pattern-setter**: establishes lesson anatomy, `k8s-link`, `langpair`, project/outcome blocks — ✅ done |
| **B-S6** | `materials/b1.html` — shell, files, filesystem tree (16 checkpoints) — ✅ done |
| **B-S7 … B-S18** | `materials/b2.html` … `materials/b13.html`, one module per session |
| **B-S19** | `materials/b14.html` + `labs/beginner/*.sh` + `mock/beginner-final*.html` + cross-track QA |

**Publishing a module** (last step of its session): add its number to `beginner.html`'s `PUBLISHED`
array, add its entry to the beginner sidebar list on every `materials/b*.html`, run the checkers.
Also repoint the *previous* module page's pager `next` link from the tracker anchor to the new file.

**Splitting a module across commits.** A full module page runs 1000–1500 lines, well past the
global ≤500-added-lines-per-code-commit rule, so it takes 3–4 commits. `check-links.sh` globs
`materials/b[0-9]*.html` the moment the file exists, so it reports the not-yet-written anchors as
missing on every commit but the last. That is expected and the two rules cannot both hold: split
along **checkpoint-group boundaries** so each commit is whole lessons (never half-written ones),
say so in the intermediate commit messages, and require green checkers only at the end of the
session. B-S6 shipped this way (`90ff0aa` → `ead1b3c` → `f90f704` → publish).

**Pattern set by `materials/b0.html`** — copy its skeleton for every later module:

- Sidebar is the lesson-page shape (`body class="materials"`, brand *Beginner · Foundations*, the
  three-pill switcher with Beginner `on`, ring panel reading `BN done`, a static `Site` list holding
  only beginner pages + `foundations.html` + `← Beginner tracker`). No cross-track merging.
- Cross-track deep links from inside `materials/` are **sibling-relative** (`w3.html#cp-3-16`), never
  `../materials/…`. Links to the trackers keep the `../` (`../beginner.html#b0`, `../index.html`).
- Page order: crumb → `header.hero` (two plain paragraphs + `.weights` chips for cps/hours/prereqs) →
  `.objectives` → `.prereq` → lesson groups → `.quiz` → `.outcome` → `.godeep` → `.pager` → footer.
  The `::before` headings come from CSS — write the bare `<div class="objectives">`, no `<h3>`.
- `.k8s-link` goes on **conceptual** lessons only. Site-mechanics lessons (b0-2) and the mini
  project/drill articles legitimately have none; b0 carries 7 across 9 lessons.
- Footer states the release the labs were authored against plus the date it was verified.

**Commit size.** The ≤500-added-lines-per-code-commit rule binds: a tracker half and a module page
both exceed it, so a session lands as several commits along natural boundaries — one per lesson group
for module pages. The limit is per commit, not per session, so it never forces a session to stop
mid-module.

**If a module overruns its session** (B5, B6, B8, B9, B12 are the risks): before stopping, every
checkpoint in that module must already have its `<article id="cp-bN-M">` on the page — even if some
hold only a *Why it matters* paragraph — so `tools/check-links.sh` stays green, and the unfinished
lesson list goes into the `CLAUDE.md` row.

## Verification (every session)

```bash
tools/check-links.sh          # both trackers
tools/check-html.py           # includes beginner.html
node --check assets/lesson.js
shellcheck labs/beginner/*.sh # once those exist
python3 -m http.server 8000
```

Then in the browser:

1. `beginner.html` renders: ring, group nav counts, collapse/expand, resume link.
2. Tick a checkpoint on `beginner.html` → reload `materials/bN.html` → shows done; and the reverse.
3. Tick a CKA checkpoint → beginner counts unaffected; each reset clears only its own track.
4. The track switcher reaches all three entries from every page; Intermediate reads as coming-soon.
5. Every `k8s-link` anchor lands on the right advanced lesson.
6. Theme toggle consistent across trackers and lesson pages; light and dark both readable.
7. **Every lab command run live on the `sandbox` VM** with its real output pasted in — the slowest
   step per session and the one that keeps the track honest.
