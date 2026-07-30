# Intermediate Track — "Building the technologies behind Kubernetes"

Authoring source of truth for the intermediate track, as [`PLAN.md`](PLAN.md) is for the advanced
(CKA) track and [`BEGINNER-TRACK.md`](BEGINNER-TRACK.md) is for the beginner track. Written in phase
**I-S1** from a raw topic outline supplied by the site owner (preserved verbatim in
[Appendix A](#appendix-a--source-outline-as-supplied)); every later session reads its module section
here before authoring.

## Why this track exists

The beginner track ends with `minibox` — ~80 lines of bash that runs a process on an overlayfs
rootfs, in five namespaces, inside a cgroup, with dropped capabilities, on a bridge with NAT and DNS,
supervised by systemd. It is, honestly, a container runtime. The advanced track begins with a
cluster that already has containerd, runc, CNI plugins and images, and teaches Kubernetes on top.

Between those two points sits everything the industry standardised in the decade after those
primitives existed:

```
minibox (bash, one host, hand-rolled)
        ↓  ← this track
image format · registry protocol · runtime spec · shim/daemon architecture · CRI · CNI · CSI shape
        ↓
kubelet, which is mostly a client of all of the above
```

**Philosophy.** The beginner track's thesis was *Kubernetes invented very little; it composes
decades-old OS technology*. This track's thesis is the sequel: **the container ecosystem added
almost no mechanism — it added contracts.** `runc` does what `minibox` already did; what it adds is
`config.json`, a schema anyone can generate. containerd's snapshotter mounts the same overlayfs B5
mounted by hand; what it adds is a content-addressed store and a gRPC API. CNI does nothing B9's
`net-up.sh` didn't; what it adds is *"exec a binary, JSON on stdin, JSON on stdout."*

So every module here follows the same arc: **you already built this → here is the spec that says how
everyone agrees to build it → here is the real implementation obeying that spec → now break it.**

**The structural device.** Two mandatory blocks per conceptual lesson:

- **"What the spec actually says"** (`<div class="specref">`) — a short quotation or faithful
  paraphrase of the normative text, with the section number and a link. This track is spec-driven in
  a way neither other track is; reading a spec is one of its teachable skills.
- **"Where this shows up in Kubernetes"** (`<div class="k8s-link">`) — inherited unchanged from the
  beginner track, deep-linking the advanced lesson anchor.

Plus one non-mandatory but constant habit: an inline **back-reference to the beginner lesson that
built the primitive by hand** (`b9.html#cp-b9-19`), so a reader always knows which of their own
scripts the standard is replacing.

## Relationship to the beginner track — what is *not* re-taught

The supplied outline's Modules 1–5, 11, 16 and 17 substantially restate beginner-track material that
was already covered hands-on. Re-teaching it would cost roughly six sessions and would contradict the
site's own premise, so it is **not** re-taught. Instead:

| Supplied outline module | Already built, hands-on, in | Treatment here |
|---|---|---|
| M1 Process isolation revisited | B2 (processes/threads/signals), B6.5 (PID ns, PID 1 semantics), B11.1 (init) | One-line callbacks; the *delta* (`clone3`, `setns` by fd, signal forwarding in a shim) lands in **I1** and **I7** |
| M2 Namespaces deep dive | B6 (all eight types, lifecycle, pinning, `nsenter`) | Callbacks; the delta (**user namespaces**, ID mapping, rootless) is **I1** and **I11** |
| M3 cgroups internals | B7 (v2 model, cpu/memory/pids/io, OOM) | Callbacks; the delta (**PSI**, `cpuset`, device controller, hugetlb, cgroup v1 as a compatibility footnote) is **I1** |
| M4 Filesystems behind containers | B5 (VFS, overlayfs lower/upper/work/merged, copy-up, whiteout, propagation) | Callbacks; the delta (whiteouts **inside a layer tar** vs on disk, `diff_id` vs digest, chain IDs, snapshotters) is **I4** and **I7** |
| M5 Building a minimal container | B14 (`minibox`) | The track *opens* from this artifact rather than rebuilding it — **I2** converts it into an OCI bundle |
| M11 Container networking | B8, B9 (veth/bridge/NAT/conntrack/netfilter/DNAT-LB) | Callbacks; the delta (**TAP/TUN**, **VXLAN/GRE overlays**, hairpin, MTU-in-overlay arithmetic) is **I1**, and the contract is **I9** |
| M16 Service discovery foundations | B10 (DNS internals, resolver, caching), W4 (CoreDNS, kube-proxy modes) | Not a module. The runtime-side slice (sandbox `resolv.conf` injection, CRI DNS config) folds into **I8** |
| M17 Distributed systems foundations | B13 (CAP, Raft, quorum, leases, idempotency, reconciliation) | Not a module. Referenced from **I7** (containerd's bbolt metadata store) and the capstone's restart logic |

Everything else in the outline — OCI image/runtime/distribution specs, image building, runtime
architecture, containerd, runc, CNI, storage, supply-chain security, observability, and the four
"build a mini X" capstones — is genuinely new and is what this track spends its time on.

## Shape of the track

**14 modules · 195 checkpoints · ~78 hours · self-paced.** No calendar: the 8-week clock belongs to
the advanced track. Ordering is dependency-driven and follows the layering of the real stack, bottom
up:

```
a box that can build → the primitives B-track skipped → the runtime contract → the image contract
   → the distribution contract → building images → the daemon that ties them together
   → the two interfaces Kubernetes actually speaks (CRI, CNI) → storage → security → seeing inside
   → assemble the whole thing
```

**Prerequisite for the track:** the beginner track complete, or equivalent fluency. This is stated in
the tracker hero and in `i0.html`. `I0` seeds the two beginner artifacts the track builds on
(`minibox.sh`, `net-up.sh`) from `labs/intermediate/seed/`, so a reader who skipped B-track is
inconvenienced but not blocked.

**How the checkpoint counts are derived** — identical rule to the beginner track: a module's total is
the sum of its **checkpoint groups**, **plus one for its mini project and one for its debugging
drill**, both living in a trailing `Project & drill` group on the tracker. Each needs to be tickable
because the page anatomy gives each its own `<article class="lesson project">` / `.drill`, and
`tools/check-links.sh` requires exactly one tracker checkpoint per lesson anchor. **I0** has no drill
(+1); **I13**'s groups already *are* its capstone and assessment (+0).

| # | Module | cps | hrs |
|---|---|---|---|
| I0 | Your build box | 8 | 2 |
| I1 | The primitives B-track left out | 14 | 5 |
| I2 | What a container is, formally — the OCI runtime spec | 16 | 6 |
| I3 | runc internals | 14 | 5 |
| I4 | Images — the OCI image spec | 16 | 6 |
| I5 | Registries — the OCI distribution spec | 15 | 6 |
| I6 | Building images | 13 | 5 |
| I7 | Runtime architecture — containerd, shims, snapshotters | 18 | 7 |
| I8 | CRI — the interface the kubelet speaks | 16 | 7 |
| I9 | CNI — the interface the network speaks | 16 | 6 |
| I10 | Container storage — volumes, snapshots, the CSI shape | 12 | 5 |
| I11 | Container security & supply chain | 15 | 6 |
| I12 | Observability of a running runtime | 10 | 4 |
| I13 | Capstone — `minidock` — & track assessment | 12 | 8 |

## Module page anatomy

Structurally identical to `materials/bN.html` (see `BEGINNER-TRACK.md` § "Module page anatomy") —
hero with `.objectives` / `.prereq` / hours chips, lesson groups, mini project, debugging drill,
recall quiz, `.outcome`, pager, footer. Copy `materials/i0.html`'s skeleton once it exists; until
then copy `materials/b0.html`'s.

### Lesson anatomy

**Why it matters → The concept → Lab → Verify → Gotchas → What the spec actually says → Where this
shows up in Kubernetes → Docs**

- **What the spec actually says** (`<div class="specref">`, new in this track) — mandatory on every
  lesson that describes standardised behaviour (all of I2, I4, I5, I8, I9; most of I3, I7, I10, I11).
  Quote or faithfully paraphrase the normative text, name the section, link it. Keep it short: the
  point is to show that the answer *is written down* and to teach reading it, not to reprint it.
  Lessons about implementation detail rather than standard (much of I1, I6, I12) legitimately omit it.
- **Where this shows up in Kubernetes** (`<div class="k8s-link">`) — mandatory on every conceptual
  lesson, exactly as in the beginner track, deep-linking `wN.html#cp-N-M`.
- **Docs** — for this track: the OCI/CNI/CRI specs, `man` pages, containerd and runc repository docs.
  kubernetes.io still belongs to the advanced track's exam-docs training.
- **Back-references** are ordinary inline prose links to `bN.html#cp-bN-M`, sibling-relative (both
  pages live in `materials/`). Every module's *first* lesson opens by naming what the reader already
  built.
- Code renders as `<pre class="cmd">` / `<pre class="out">` as everywhere else. Python programs and
  JSON documents are ordinary `cmd` blocks; the beginner track's `.langpair` is **not** used here
  (there is no second language to pair with — see below).

### Language policy

**CLI-first, Python where code is genuinely needed.** Decided in I-S1.

Real components are driven with their real tools — `ctr`, `crictl`, `nerdctl`, `runc`, `skopeo`,
`cnitool`, `buildctl`, `curl`, `jq`, `grpcurl` — because that is both the authentic interface and the
thing a reader can carry into a real incident. Where a lesson's subject genuinely *is* a program
(an image parser, a registry client, a CRI server, a CNI plugin), it is written in **Python 3**, or
in **bash + jq** where the real-world plugin would also be a shell script.

The ecosystem is written in Go, and the track says so plainly and repeatedly — it links the actual Go
source when it explains an implementation — but it does not require the reader to learn Go. The
trade-off is stated once, in `i0.html`: *your toy CRI server speaks the same protobuf wire format as
the real one, but it does not compile against the real Go interfaces.*

**PEP 668:** Ubuntu 24.04 marks the system Python externally-managed, so `pip install grpcio
grpcio-tools protobuf` must run inside a venv created in I0 (`~/.venv-intermediate`), never with
`--break-system-packages`. Every Python lab step assumes that venv is active.

### Lab environment

A **second** throwaway Multipass **Ubuntu 24.04 LTS** VM named **`buildbox`** — 4 vCPU / 8 GB /
40 GB, snapshotted in I0 exactly as `sandbox` was in B0. It is deliberately not the beginner track's
`sandbox` (undersized for image builds, and its snapshot is a beginner-track asset) and deliberately
not the CKA lab's `cp`/`node01`/`node02` (this track's labs stop and reconfigure containerd, which
would break the cluster the advanced track depends on).

Unlike the beginner track, **`buildbox` needs working internet**: pulling real images from Docker Hub
and from a locally-run `registry:2` is the subject matter of I5 and I6. Every lab that pulls names an
explicit tag *and* records the digest it resolved to, so a reader on a different day can tell
"the tag moved" from "my command is wrong".

Toolchain installed in I0, all pinned explicitly:

| Tool | Source | Why not the distro package |
|---|---|---|
| containerd 2.x | official static tarball from containerd.io | noble ships **1.7.28**, which predates the 2.0 config-version and plugin-path changes the track teaches |
| runc | official static binary | ships alongside containerd's release matrix |
| CNI plugins | containernetworking/plugins release tarball → `/opt/cni/bin` | the distro has no current package |
| `crictl`, `critest` | cri-tools release tarball | version must track the CRI API version |
| `nerdctl` | release tarball (full bundle also carries BuildKit) | not packaged |
| `skopeo`, `jq`, `tree`, `python3-venv` | apt | fine from the distro |
| BuildKit (`buildkitd`/`buildctl`) | nerdctl full bundle | I6 only |
| `cosign`, `syft`/`grype` or `trivy` | release binaries | I11 only |

**Version-sensitive facts to re-verify by web search at the start of every authoring session** —
never from memory. Values below were verified **2026-07-25**:

- **CKA targets Kubernetes v1.35** (unchanged; re-confirm each session). CRI is stable `runtime.v1`
  and backward-compatible across versions; v1.35 extended `UpdateContainerResources` and reverted
  the `KeyValue` JSON encoding change made in 1.34.
- **containerd 2.3.2** is current (2.3.0 shipped 2026-04-30; minor releases now land on a 4-month
  cadence — April / August / December, so **expect a 2.4 during this track's authoring window**).
  Ubuntu 24.04's own `containerd` is **1.7.28-0ubuntu1~24.04.2**.
- **runc v1.5.1** (2026-07-14) is current; the 1.4.z line (v1.4.3) is in security-fix-only mode.
- **OCI specs: image-spec v1.1.1, runtime-spec v1.3.0, distribution-spec v1.1.1.**
- **CNI spec v1.1.0** (shipped with libcni v1.2.0). It defines **six** operations — ADD, DEL, CHECK,
  **GC**, **STATUS**, VERSION. GC and STATUS are the 1.1 additions: GC lets a runtime hand a plugin
  the set of known-good attachments so it can free leaked IPAM reservations; STATUS lets a plugin
  report readiness so containerd/CRI-O stop inferring readiness from "a conf file exists".
- Ubuntu 24.04 defaults carried over from the beginner track and still binding here: cgroup **v2**
  only, `iptables` on the **nftables** backend, `systemd-resolved` stub at 127.0.0.53,
  `kernel.apparmor_restrict_unprivileged_userns=1` (which **I1** and **I11** must explain, not
  silently `sudo` around — it is the single biggest obstacle to the rootless labs).
- `multipass launch 24.04` **explicitly** — never `launch lts`, which now resolves to Ubuntu 26.04
  "Resolute Raccoon" and would hand the reader a different kernel from the pasted output.

---

## I0 — Your build box

**Prerequisites:** the beginner track, or equivalent. This is the front door of the track.
**8 checkpoints · ~2 hours**

**Objectives.** Stand up and snapshot `buildbox`; install and verify the whole toolchain with pinned
versions; know what each binary in it is for before meeting it properly; import the two beginner
artifacts the track builds on; understand the track's language policy and how to read a spec.

**Checkpoint groups**
- *The box* (3) — launch `multipass launch 24.04 --name buildbox -c 4 -m 8G -d 40G`, snapshot it,
  practise restoring; the venv and PEP 668; seed `minibox.sh` and `net-up.sh` from
  `labs/intermediate/seed/` and re-run each once to confirm the starting point works.
- *The toolchain* (3) — install containerd + runc + CNI plugins + crictl + nerdctl + skopeo, each
  pinned, each verified by a version command; a map of "which binary owns which layer" that the
  reader will re-draw at the end of I7; first contact — `ctr version`, `crictl info`, `runc spec`.
- *How to read a spec* (1) — MUST/SHOULD/MAY (RFC 2119), how the OCI and CNI documents are organised,
  how to find the section that answers a question, and why "the spec is silent on this" is a real and
  common answer.

**Mini project.** A `~/toolcheck.sh` that prints every installed component's version and its
config-file path in one table, and exits non-zero if anything is missing — re-run at the start of
every later module, and the fastest possible fix for "the lab output doesn't match mine".

**No debugging drill** (nothing has been built yet), hence 8 = 7 groups + project.

**Outcome.** A reproducible, snapshot-restorable box, and a reader who knows what they are about to
take apart.

---

## I1 — The primitives B-track left out

**Prerequisites:** B2, B5, B6, B7, B9.
**14 checkpoints · ~5 hours**

The bridge module. Everything here is a *delta* on what the reader already built; each lesson opens
with the beginner anchor it extends. Nothing already covered is re-taught.

**Objectives.** Explain user namespaces and ID mapping well enough to reason about rootless
containers; read PSI to distinguish "starved" from "idle"; pin a workload with `cpuset` and block a
device with the device controller; write and load a seccomp filter and read the rejection; build a
VXLAN overlay between two namespaces and compute the resulting MTU.

**Checkpoint groups**
- *Isolation, the parts we skipped* (4) — **user namespaces**: `/proc/PID/uid_map` and `gid_map`,
  the single-write rule, `newuidmap`/`newgidmap` and `/etc/subuid`, what "root inside, nobody
  outside" actually means; nesting and `setns` by file descriptor (the mechanic behind
  `kubectl exec`); `clone3` vs `unshare` vs `fork`; 24.04's
  `apparmor_restrict_unprivileged_userns` and the informed ways around it.
- *Resource control, the parts we skipped* (4) — **PSI** (`/proc/pressure/*`, `*.pressure` per
  cgroup): `some` vs `full`, and why PSI answers a question load average cannot; `cpuset.cpus` /
  `cpuset.mems` and NUMA in one paragraph; the **device controller** (v2 = an eBPF program attached
  to the cgroup, not a `devices.allow` file — the biggest v1→v2 surprise); hugetlb and cgroup v1 as
  a compatibility footnote you will still meet on old nodes.
- *Filtering syscalls for real* (2) — a seccomp BPF filter written by hand (Python `prctl` via
  `ctypes`, or `scmp_sys_resolver` + a JSON profile) and the exact failure signature (SIGSYS, "Bad
  system call", `Seccomp:` in `/proc/PID/status`); allow-list vs deny-list and why every real profile
  is an allow-list with ~300 entries.
- *Networking, the parts we skipped* (2) — **TAP/TUN**: a userspace program holding a file descriptor
  that *is* an interface; **VXLAN** between two netns on one host (`ip link add … type vxlan`), the
  50-byte header, the MTU arithmetic, and GRE in one paragraph; hairpin mode and why a pod reaching
  its own Service used to break.

**Mini project.** Run `minibox` **rootless**: a user-namespaced container owned by an unprivileged
user, with `newuidmap`, on a TAP-free `slirp`-style caveat documented honestly (what stops working,
and why rootless networking is hard).

**Debugging drill.** Two faults: a workload pinned to a single busy CPU by `cpuset` (looks like a
CPU-limit problem, isn't — PSI and `cpu.stat` disagree, and the disagreement is the clue), and a
VXLAN tunnel whose MTU was never lowered (ping and TLS handshake fine, first large response hangs —
the beginner track's B8 MTU black hole, now self-inflicted at the overlay layer).

**Outcome.** No remaining primitive-level surprises for the rest of the track.

**Feeds forward to.** What runs privileged on a node (`w1.html#cp-1-2`), overlay datapaths
(`w4.html#cp-4-7`), node-pressure eviction (`w3.html#cp-3-18`), node Conditions including
PIDPressure (`w6.html#cp-6-12`).

> **Anchor gap, verified 2026-07-25:** the advanced track contains **no** `securityContext` or Pod
> Security Standards coverage at all (that is CKS territory) — `grep -r securityContext materials/w*.html`
> returns nothing. Lessons here about `runAsUser`, capabilities and seccomp must say so explicitly and
> link what *does* exist, exactly as `materials/b12.html` already does. Do not invent an anchor.

---

## I2 — What a container is, formally — the OCI runtime spec

**Prerequisites:** I0, I1, B6, B7, B14.
**16 checkpoints · ~6 hours**

The hinge of the track. `minibox` becomes a **bundle**, and someone else's binary runs it.

**Objectives.** Write a `config.json` from scratch and explain every top-level field; describe the
filesystem bundle layout; recite the container lifecycle states and the operations that move between
them; explain what the runtime spec deliberately does **not** cover; convert `minibox`'s flags into
declarative configuration and run it with `runc`.

**Checkpoint groups**
- *The bundle* (3) — the two-file contract (`config.json` + `rootfs/`); `runc spec` and reading the
  generated default top to bottom; where the bundle comes from in a real stack (a snapshotter
  prepares `rootfs/`, the runtime writes `config.json` — nobody ships bundles).
- *config.json, field by field* (5) — `ociVersion`, `process` (args, env, cwd, terminal, user,
  capabilities' five sets, rlimits, `noNewPrivileges`, `oomScoreAdj`); `root` (path, `readonly`);
  `mounts` (and how the defaults reproduce the `/proc`, `/sys`, `/dev` work `minibox` did by hand);
  `linux.namespaces` (including sharing by **path**, which is exactly how a pod works);
  `linux.resources` (the cgroup v2 keys from B7, renamed) plus `cgroupsPath`, `seccomp`, `devices`,
  `maskedPaths`/`readonlyPaths`, `rootfsPropagation`.
- *Lifecycle* (4) — the state machine (`creating → created → running → stopped`); `create`, `start`,
  `kill`, `delete`, `state`; why **create/start is two steps** and what that split buys a runtime
  (this is the whole reason a shim can exist, and the reason `kubectl exec` and CRI can attach before
  the process runs); the `state` JSON and its `pid`; **hooks** (`createRuntime`, `createContainer`,
  `startContainer`, `poststart`, `poststop`) and which side of the namespace each runs on.
- *Boundaries* (2) — what the runtime spec does **not** standardise: images, networking, logging,
  naming, storage. Each omission is a later module. Then: the same bundle run by `runc` and by
  `crun`, byte-identical config, to prove the contract is real.

**Mini project.** **`minibox2bundle.py`** — read the flags `minibox.sh` accepts and emit a valid
`config.json`; run the result with `runc run`; diff the observable outcome (namespaces via `lsns`,
cgroup values, caps in `/proc/PID/status`) against `minibox`'s and account for every difference.

**Debugging drill.** Three hand-broken bundles: a `rootfs` path that is relative-to-the-wrong-place;
a `linux.namespaces` entry sharing a **path** that has already been garbage-collected; a `process.user`
uid that does not exist inside the rootfs. Each produces a distinct, memorable `runc` error, and the
third is the one every reader will meet again as a `CreateContainerError`.

**Outcome.** Can read any `config.json` — including the one containerd generates for a Kubernetes pod
— and predict what the container will be able to do.

**Feeds forward to.** CRI internals (`w1.html#cp-1-20`), the pause container (`w1.html#cp-1-21`),
requests/limits enforcement (`w3.html#cp-3-16`), graceful termination (`w3.html#cp-3-5`).

---

## I3 — runc internals

**Prerequisites:** I2.
**14 checkpoints · ~5 hours**

**Objectives.** Explain the two-process dance that creates a container; describe why `runc` exits and
what that implies for whoever wanted to supervise the process; use detached mode, PID files and
console sockets correctly; find where runc writes state; explain checkpoint/restore's shape without
needing it.

**Checkpoint groups**
- *Creation, step by step* (4) — `runc create` traced with `strace -f`: the re-exec into `runc init`,
  the `_LIBCONTAINER_*` environment handshake, the netlink bootstrap message, the order of operations
  (namespaces → cgroup → mounts → pivot_root → capabilities → seccomp → exec); why the ordering is
  forced rather than arbitrary (each step removes a power the next step still needs).
- *Living with a runtime that exits* (4) — foreground vs `--detach`; `--pid-file` and the race it
  closes; the **console socket** and why a terminal needs one (a pty master has to be passed over a
  unix socket — B9's unix-domain-socket lesson, applied); `runc exec` and what it re-enters;
  `runc ps`, `runc events --stats`, `runc update` for live resource changes.
- *State on disk* (2) — `/run/runc/<id>/state.json`, what a "container" is when nothing is running,
  and how a stale state directory produces "container with that ID already exists"; the root dir and
  why rootless runc uses a different one.
- *Beyond the basics* (2) — hooks in anger (a `createRuntime` hook that configures networking from
  outside, i.e. exactly what a CNI-invoking runtime does); checkpoint/restore via CRIU: what it
  requires, why it is rarely used, and the one Kubernetes feature that uses it.

**Mini project.** A ~60-line `microshim.py`: `runc create --detach --pid-file`, then hold the
container's lifetime open, forward SIGTERM/SIGINT to the container's PID 1, wait for exit, report the
exit code, and `runc delete`. It is a shim, and I7 will compare it to the real one line by line.

**Debugging drill.** Two faults: a container that "starts and immediately exits with 0" because
`args` pointed at a shell that read EOF (no `terminal`, no stdin) — the runtime-level ancestor of
`CrashLoopBackOff` on a misconfigured command; and a leftover `/run/runc` state directory after an
uncleanly killed runtime, blocking re-creation by ID.

**Outcome.** Can operate a container without any daemon at all, and can explain what a shim is *for*
before meeting one.

**Feeds forward to.** kubelet → containerd → shim → runc (`w1.html#cp-1-20`), graceful termination
(`w3.html#cp-3-5`), CrashLoopBackOff and the exit-code alphabet (`w6.html#cp-6-16`).

---

## I4 — Images — the OCI image spec

**Prerequisites:** I2, B5.
**16 checkpoints · ~6 hours**

**Objectives.** Explain an image as a content-addressed DAG rather than a file; walk an OCI layout by
hand from `index.json` to a layer tar; distinguish digest from diff_id from chain ID; explain layer
whiteouts in the tar format; assemble a runnable rootfs from an image with no container tooling.

**Checkpoint groups**
- *The model* (4) — content addressing and why a digest is an identity, not a location (B12's hashing
  lesson, cashed in); **descriptors** (mediaType + digest + size) as the only pointer type in the
  whole spec; the DAG: index → manifest → config + layers; tags as mutable labels on immutable
  content, and the entire "`:latest` moved under me" class of incident.
- *Walking a real image* (4) — `skopeo copy docker://alpine:3.21 oci:./alpine-oci:3.21`, then
  `tree` + `jq` through `oci-layout`, `index.json`, the manifest, the config; media types and how to
  tell an OCI manifest from a Docker v2 schema-2 one; **manifest lists / image indexes** and
  platform selection; annotations.
- *Layers* (4) — a layer is a **tar** (usually gzip or zstd); `digest` is over the compressed blob,
  `diff_id` over the uncompressed one, and both exist because one identifies the transfer and the
  other identifies the content; **whiteouts inside a tar** are `.wh.<name>` entries (*not* the
  character devices B5 saw on disk — the conversion is the snapshotter's job); `.wh..wh..opq` for
  opaque directories; **chain ID** and why it, not diff_id, is what a snapshotter caches on.
- *The config* (2) — the image config as "the parts of `config.json` an image can pre-declare"
  (`Env`, `Entrypoint`, `Cmd`, `WorkingDir`, `User`, `Volumes`, `Labels`) plus `rootfs.diff_ids` and
  `history`; who wins when the image config and the runtime config disagree — the answer that
  explains Kubernetes' `command`/`args` mapping.

**Mini project.** **`oci-inspect.py`** — given an OCI layout directory and a tag: resolve the index,
pick the right platform, print the manifest tree with sizes, verify **every** digest by recomputing
it, then extract the layers in order into a `rootfs/` (applying whiteouts correctly) and hand that
directory to the I2 bundle so `runc` runs a real distro image the reader unpacked themselves.

**Debugging drill.** Three faults: a layer blob whose content was altered (digest verification fails
— and the reader sees exactly what a supply-chain check is defending); an image index with no
matching platform (`no image found for platform` — the arm64/amd64 incident); and layers extracted in
the wrong order, producing a rootfs that looks fine but has a deleted file resurrected.

**Outcome.** An image is no longer magic: it is JSON, tarballs, and SHA-256.

**Feeds forward to.** Image failures and their three root causes (`w6.html#cp-6-17`), image layers on
the node (`w1.html#cp-1-23`), architecture-based node selection for multi-platform images
(`w3.html#cp-3-12`).

---

## I5 — Registries — the OCI distribution spec

**Prerequisites:** I4.
**15 checkpoints · ~6 hours**

**Objectives.** Pull an image using nothing but `curl`; explain the token-auth dance; push to a local
registry and see exactly which HTTP requests make up a push; explain why a registry is a blob store
with two namespaces; diagnose the four common pull failures from their HTTP status codes.

**Checkpoint groups**
- *The API* (4) — `/v2/` as the version handshake; the two endpoint families — **blobs** (by digest,
  immutable) and **manifests** (by tag *or* digest); `GET`/`HEAD` semantics and why `HEAD` on a
  manifest is how every "is it up to date?" check works; content negotiation via `Accept` and how
  asking wrongly gets you a schema-2 manifest when you wanted an index.
- *Pulling by hand* (4) — the `WWW-Authenticate` challenge → token endpoint → bearer token flow
  against Docker Hub; anonymous rate limits and how they present; fetch manifest → fetch config →
  fetch each layer, all with `curl`, verifying digests as you go; assemble and run it — the complete
  pull path with zero container tooling.
- *Pushing* (3) — run `registry:2` locally; the push order (**blobs first, manifest last** — so a
  manifest is never resolvable before its content exists, which is the whole consistency model);
  monolithic vs chunked uploads and the `Location`/`uuid` session; cross-repo blob mount and why
  pushing a 900 MB image the second time takes two seconds.
- *In practice* (2) — `skopeo copy`/`inspect`/`delete` as the everyday tool; mirrors, pull-through
  caches and how containerd is configured to use them (`hosts.toml`), which is the exact fix for
  "our nodes are rate-limited by Docker Hub".

**Mini project.** **`pull.py`** — a working registry client in ~120 lines: auth, resolve tag →
index → manifest, verify and cache blobs by digest in a local content store laid out like
containerd's, and materialise an OCI layout that `oci-inspect.py` from I4 can consume.

**Debugging drill.** Four failures, identified by status code and fixed: 401 with a challenge (no
token) vs 401 without (bad credentials); 404 on a blob after a successful manifest fetch (a
half-replicated mirror); 429 (rate limit) presenting to the reader as `ImagePullBackOff` with a
generic message; and a `MANIFEST_UNKNOWN` caused by requesting a tag with the wrong `Accept` header.

**Outcome.** `ImagePullBackOff` becomes a diagnosable HTTP problem rather than a Kubernetes mystery.

**Feeds forward to.** `ErrImagePull`/`ImagePullBackOff` and `imagePullSecrets` (`w6.html#cp-6-17`) —
the one advanced anchor that covers registries end to end; who does the pulling on the node
(`w1.html#cp-1-20`).

---

## I6 — Building images

**Prerequisites:** I4, I5.
**13 checkpoints · ~5 hours**

**Objectives.** Explain a Dockerfile as a sequence of layer-producing operations plus a cache key
function; predict which instruction will bust the cache; build multi-stage and multi-platform images;
build an image with **no** Dockerfile at all.

**Checkpoint groups**
- *Semantics* (4) — each instruction as either "produce a layer" or "amend the config"; the **build
  context** (what actually gets sent, and `.dockerignore` as a performance and a secrecy control);
  **cache keys** — instruction text + parent chain, with `COPY`/`ADD` hashing content, which explains
  the copy-manifest-then-install-then-copy-source ordering rule; `RUN` chaining vs layer count, and
  why deleting a file in a later layer does not shrink the image (it only adds a whiteout — I4's
  lesson arriving as a cost).
- *Doing it properly* (3) — multi-stage builds and `--target`; **BuildKit**: the DAG, parallelism,
  cache mounts, `--mount=type=secret` and why build-args leak into `history`; multi-platform builds
  and what an image index costs you.
- *Building without Docker* (2) — `nerdctl build`, `buildctl` directly, and then the honest one:
  assemble an image by hand — tar a rootfs diff, write a config, write a manifest, write an index —
  which is exactly what the mini project automates.
- *Reading images others built* (2) — `docker history` / `nerdctl image history` / config `history`
  entries as an audit trail; finding the layer that added 400 MB; spotting a secret baked into a layer
  by extracting it.

**Mini project.** **`tinybuild.py`** — read a five-instruction subset (`FROM`, `RUN`, `COPY`, `ENV`,
`CMD`), execute `RUN` steps inside the I2 bundle with `runc`, capture each step's filesystem diff as
a layer tar, write config + manifest + index, and push the result to the local registry with
`pull.py`'s code in reverse. Then run it with `nerdctl` to prove it is a real image.

**Debugging drill.** Two faults: a build whose cache never hits because an early `COPY . .` puts
volatile files above the dependency install (the single most common slow-CI cause); and an image that
runs locally and fails on another machine because a `RUN` step depended on a file only present in the
builder's context.

**Outcome.** Image builds are predictable, auditable and no longer require Docker.

**Feeds forward to.** Init containers and image layout assumptions (`w3.html#cp-3-2`), ConfigMap vs
baked-in config (`w3.html#cp-3-21`), secrets are not build-time (`w3.html#cp-3-23`).

---

## I7 — Runtime architecture — containerd, shims, snapshotters

**Prerequisites:** I2, I3, I4, I5.
**18 checkpoints · ~7 hours** — **the heaviest module; plan two sittings.**

**Objectives.** Draw the full process tree from `ctr run` to the workload and name every process;
explain what survives a containerd restart and why; explain containers vs tasks; navigate the content
store, snapshotter and metadata store on disk; use leases to stop the garbage collector deleting your
work; write a client against containerd's API.

**Checkpoint groups**
- *The process tree* (4) — `dockerd` → `containerd` → `containerd-shim-runc-v2` → workload, with
  `runc` present only momentarily (the "where did runc go?" question I3 answered in advance); the
  **shim** contract: one shim per container (or per pod sandbox), holding stdio, the exit code and
  the pty so the daemon is *restartable* — kill containerd and watch the workloads live; how the shim
  is started and how it is found again (the socket address in the bundle dir).
- *Objects* (4) — containerd **namespaces** (`default`, `k8s.io`) and why `ctr` shows nothing until
  you pass `-n k8s.io`; **containers vs tasks** — metadata vs a running process, and the fact that
  deleting a task does not delete the container; images and their relationship to content; the plugin
  model (`ctr plugins ls`), what a "plugin" is in a single binary, and the 2.x config version.
- *Storage internals* (5) — the **content store** (`/var/lib/containerd/io.containerd.content.v1.content/blobs/sha256/…`),
  which is precisely `pull.py`'s cache with a real API; the **snapshotter** — how it turns I4's
  layer tars into the overlayfs lower/upper stack B5 built by hand, `ctr snapshot ls/tree`, active vs
  committed snapshots, and where the container's writable layer physically is; the **metadata store**
  (bbolt, `meta.db`) as the source of truth for names; **leases** and garbage collection — the
  mechanism that deletes your unreferenced blob thirty seconds after you fetch it; `ctr content`/
  `ctr snapshot` walked end to end.
- *Talking to it* (3) — the socket (`/run/containerd/containerd.sock`) and the fact that write access
  to it is root on the node (B9's lesson, now with the exploit made concrete); the API surface as
  gRPC services; events (`ctr events`) as the runtime's own audit log; `nerdctl` as a
  Docker-compatible client over the same API.

**Mini project.** A Python containerd client that, in one script: pulls an image via the local
registry, prepares a snapshot, generates a `config.json` from the image config (reusing I4's parser),
creates a container and a task, starts it, streams its output, waits, and cleans up — the same work
`ctr run` does, done by the reader. Where the gRPC surface is impractical from Python, the script
shells out to `ctr` and says so explicitly, with a note naming the Go client call it replaces.

**Debugging drill.** Three faults: containerd restarted while a container runs (nothing dies — prove
it, and explain to a colleague why); a container stuck because its shim was killed (the workload is
orphaned and unreapable through the API); and a blob that vanishes because it was fetched without a
lease and the GC ran.

**Outcome.** The node's container layer is fully explicable, including everything `crictl`/`kubectl`
hide.

**Feeds forward to.** kubelet → containerd → shim → runc (`w1.html#cp-1-20`), the pause container
(`w1.html#cp-1-21`), `/var/lib/kubelet` (`w1.html#cp-1-23`), node troubleshooting
(`w6.html#cp-6-2`).

---

## I8 — CRI — the interface the kubelet speaks

**Prerequisites:** I7.
**16 checkpoints · ~7 hours**

**Objectives.** Explain why CRI exists and what it replaced; name the two services and the calls that
matter; explain a **pod sandbox** in terms of I2's namespaces-shared-by-path; drive a runtime with
`crictl` the way the kubelet does; implement enough of the CRI server to serve `crictl`.

**Checkpoint groups**
- *Why and what* (3) — the pre-CRI world (the kubelet linking every runtime in-tree) and dockershim's
  removal as the payoff; the contract: a gRPC service over a unix socket, `runtime.v1`, stable and
  backward-compatible; the two services — **RuntimeService** and **ImageService** — and why images
  are separate.
- *The sandbox model* (4) — `RunPodSandbox` creates the **pause container**: a process that does
  nothing but hold the net/ipc/uts namespaces open so app containers can join them **by path**
  (exactly I2's namespace-path field); why the sandbox is created before any app container and torn
  down last; sandbox config — DNS (the `resolv.conf` written into the sandbox), port mappings,
  linux security context, log directory; `RunPodSandbox` → CNI ADD, which is the seam I9 opens.
- *The call sequence* (4) — the real order for one pod: `PullImage` → `RunPodSandbox` →
  `CreateContainer` → `StartContainer`, then `ListContainers`/`ContainerStatus` polling; `ExecSync`
  vs `Exec` (the streaming URL redirect, and why exec traffic does not flow through the kubelet's
  gRPC); `Attach`, `PortForward`; `UpdateContainerResources` (extended in v1.35) as the mechanism
  behind in-place pod resize; `RemoveContainer`/`StopPodSandbox` and the ordering during deletion.
- *Operating it* (3) — `crictl` as a debugging tool that speaks CRI directly (`crictl ps`, `pods`,
  `inspect`, `logs`, `exec`, `imagefsinfo`) and when it sees things `kubectl` cannot; the **CRI log
  format** on disk (`<timestamp> <stream> <tag> <line>`) and who writes it; containerd's CRI plugin
  config in `/etc/containerd/config.toml` — the sandbox image, the cgroup driver (**systemd**, and
  the failure when it disagrees with the kubelet), runtime handlers and their mapping to
  `RuntimeClass`.

**Mini project.** **`toycri.py`** — a Python gRPC server implementing `Version`, `RunPodSandbox`,
`ListPodSandbox`, `CreateContainer`, `StartContainer`, `ListContainers`, `ContainerStatus` and
`RemoveContainer` by shelling out to `runc` and the I2/I4 machinery, listening on a unix socket.
Point `crictl --runtime-endpoint` at it and run `crictl pods`, `crictl ps`, `crictl runp`. The
protobufs come from the `cri-api` repository, compiled with `grpcio-tools` in the I0 venv.

**Debugging drill.** Three faults: a **cgroup-driver mismatch** (kubelet `systemd`, containerd
`cgroupfs`) — everything starts, then pods are evicted or restart mysteriously, and the evidence is
two cgroup trees; a missing/unpullable **sandbox image**, which fails every pod on the node with an
error that names no user workload; and a wrong `--runtime-endpoint` producing a connection error that
readers routinely mistake for "containerd is down".

**Outcome.** Can debug a node's runtime from below the kubelet, and can say precisely what the
kubelet asks for and what it receives.

**Feeds forward to.** CRI end to end (`w1.html#cp-1-20`), the pause container (`w1.html#cp-1-21`),
kubelet syncLoop and pod sources (`w1.html#cp-1-19`), where logs physically live (`w6.html#cp-6-2`),
the NotReady ladder (`w6.html#cp-6-10`) and the kubelet classics (`w6.html#cp-6-11`).

---

## I9 — CNI — the interface the network speaks

**Prerequisites:** I8, B9.
**16 checkpoints · ~6 hours**

**Objectives.** Recite the CNI contract in one sentence; write a working plugin in bash; explain conf
lists and chaining; explain what IPAM is separately responsible for; explain the v1.1 additions and
the problems they solve; convert B9's `net-up.sh` into a spec-compliant plugin.

**Checkpoint groups**
- *The contract* (4) — "the runtime execs a binary, with configuration on **stdin** as JSON,
  parameters in **environment variables** (`CNI_COMMAND`, `CNI_CONTAINERID`, `CNI_NETNS`, `CNI_IFNAME`,
  `CNI_PATH`, `CNI_ARGS`), and a **result on stdout** as JSON"; the six operations — ADD, DEL, CHECK,
  **GC**, **STATUS**, VERSION — and which are mandatory; **DEL must be idempotent** and must succeed
  when there is nothing to delete, which is the single most commonly violated requirement; the error
  result object and its codes.
- *Configuration* (4) — a `.conflist` in `/etc/cni/net.d`, binaries in `/opt/cni/bin`, and lexical
  ordering of conf files as a real production footgun; **chaining**: the previous plugin's result is
  passed to the next as `prevResult`, which is how `portmap`, `bandwidth`, `firewall` and `tuning`
  compose; result **versions** and the compatibility rules; `cnitool` as a runtime you can drive by
  hand.
- *The plugins that ship* (4) — `bridge` (which does what B9's script did, read side by side with it);
  `host-local` **IPAM** — the allocation file tree under `/var/lib/cni/networks/`, and why a leaked
  file means "no IP addresses left" on a node that has three pods; `static`, `loopback` (mandatory,
  and why); `macvlan` vs `ipvlan` in one paragraph each; `portmap` as DNAT (B9's lesson exactly) and
  `firewall`/`bandwidth`/`tuning`.
- *In a real stack* (2) — who calls the plugin (containerd's CRI plugin, at `RunPodSandbox`, before
  any app container) and what the kubelet never sees; how Flannel/Calico's daemons write conf files
  and manage routes, tying back to `w4.html#cp-4-6`; the v1.1 **GC** and **STATUS** verbs — GC hands
  the plugin the known-good attachment list so leaked IPAM reservations can be reclaimed, STATUS lets
  the plugin declare readiness instead of the runtime inferring it from a file's existence.

**Mini project.** **`cni-minibridge`** — B9's `net-up.sh`, rewritten as a spec-compliant plugin in
bash + jq: reads stdin JSON, honours `CNI_COMMAND`, allocates from a host-local-style store, creates
the veth into `CNI_NETNS`, wires the bridge, sets up masquerade, prints a valid v1.1.0 result, and
implements DEL idempotently plus CHECK and VERSION. Drive it with `cnitool`, then install it in
`/etc/cni/net.d` and have **containerd** call it for a real `crictl runp` sandbox.

**Debugging drill.** Three faults: a plugin that returns a **malformed result** (sandbox creation
fails with an error naming JSON, not networking); **IPAM exhaustion** from leaked reservation files
after DELs that were never called — the node accepts no new pods and the message says nothing about
files; and **two conf files** in `/etc/cni/net.d` where the reader expects the second to win.

**Outcome.** Pod networking is a contract the reader has implemented, not a black box owned by a
vendor.

**Feeds forward to.** The CNI contract (`w4.html#cp-4-5`), inspecting your CNI (`w4.html#cp-4-6`),
building a pod network by hand (`w4.html#cp-4-2`), breaking CNI on purpose (`w4.html#cp-4-8`),
datapath families (`w4.html#cp-4-7`).

---

## I10 — Container storage — volumes, snapshots, the CSI shape

**Prerequisites:** I7.
**12 checkpoints · ~5 hours**

**Objectives.** Distinguish the three storage layers a container has; explain what a volume is at the
runtime level (a bind mount and some bookkeeping); explain mount propagation choices in a runtime
context; describe CSI's architecture well enough to predict which component failed.

**Checkpoint groups**
- *A container's three storages* (3) — the image layers (read-only, shared, snapshotter-owned), the
  writable layer (snapshot-owned, dies with the container — and the disk-pressure story that follows
  from it), and mounts from outside; where each physically lives on `buildbox`, measured.
- *Volumes at runtime level* (3) — a "volume" as a `mounts` entry in `config.json` plus a directory
  someone manages; bind vs `tmpfs` vs a real block device with a filesystem; **mount propagation**
  (`rprivate` default, `rslave` and the exact reason Kubernetes' `mountPropagation: HostToContainer`
  exists) — B5's propagation lesson, now with a purpose; ownership and `fsGroup`-style recursive
  chown, and why it is slow on a million files.
- *The CSI shape* (4) — why an interface exists here at all (the same in-tree-plugin story as CRI);
  the three services — Identity, Controller, Node — and the four calls that matter
  (`CreateVolume`, `ControllerPublishVolume`, `NodeStageVolume`, `NodePublishVolume`); **stage vs
  publish** and why the distinction exists (one mount per node, many per pod); the sidecar model
  (provisioner/attacher/registrar) as "controllers that translate API objects into gRPC", which is
  literally `w5.html#cp-5-11`.

**Mini project.** **`volman.py`** — a local volume manager: create/list/remove named volumes under
`/var/lib/volman`, attach them to a container by rewriting its `config.json` mounts, enforce a size
limit with a loop-mounted ext4 image (B5's `disk.img`, reused), and survive container deletion. Then
a second container mounts the same volume and sees the data.

**Debugging drill.** Two faults: a volume mounted with the wrong propagation, so a mount made inside
the container is invisible outside (and the reverse); and a volume whose directory is owned by a uid
that does not exist in the container's user namespace — permission denied with a uid that appears
nowhere in either system's `/etc/passwd`.

**Outcome.** Kubernetes storage arrives as a naming and orchestration layer on mechanics already
understood.

**Feeds forward to.** Ephemeral volumes (`w5.html#cp-5-1`), where volumes live on the node
(`w5.html#cp-5-2`), CSI architecture (`w5.html#cp-5-11`), tracing a mount end to end
(`w5.html#cp-5-12`).

---

## I11 — Container security & supply chain

**Prerequisites:** I2, I4, I5, I1, B12.
**15 checkpoints · ~6 hours**

**Objectives.** Harden a container at the runtime level and prove each control works; run a rootless
container stack; explain image signing and verify a signature; produce and read an SBOM; explain what
a CVE scan does and does not tell you.

**Checkpoint groups**
- *Runtime hardening* (5) — the five **capability sets** in `config.json` and what dropping each
  actually prevents (B4's lesson, now declarative); `noNewPrivileges` and the setuid escape hatch;
  **seccomp profiles** as the real JSON format (`defaultAction`, `syscalls[].names/action/args`),
  including the runtime-default profile and why "unconfined" is so common; AppArmor and SELinux
  labels as `config.json` fields; **read-only rootfs** plus a `tmpfs` for `/tmp`, and the class of
  application that breaks.
- *Rootless* (3) — rootless containerd and rootless `runc`: what user namespaces buy you, what
  breaks (privileged ports, some networking, some filesystems), and what "rootless" does not protect
  against; the honest threat model — a comparison table of what each control stops, extending B12.1.
- *Supply chain* (5) — signing with **cosign**, keyless vs key-based, and verifying before running;
  attestations and provenance in one paragraph; **SBOM** generation and what it is for (answering
  "am I affected?" in minutes rather than days); CVE scanning with `trivy`/`grype`, base-image choice,
  and the arithmetic of **distroless**; the registry-side controls — digest pinning as the only
  actually-immutable reference.

**Mini project.** Harden the stack end to end: rebuild the I6 image as a distroless-style minimal
image, sign it with cosign, push it, then a `run-verified.sh` that refuses to run an image whose
signature does not verify, and runs it with dropped capabilities, a seccomp allow-list, a read-only
rootfs and a non-root user. Prove each control by attempting the thing it forbids.

**Debugging drill.** Two faults: a seccomp profile that blocks a syscall the runtime itself needs
during setup (the container fails before its first instruction, and the error names nothing useful
without `dmesg`/`SIGSYS`); and a signature verification that fails because the image was re-pushed by
tag while the signature refers to the old digest — the concrete cost of not pinning digests.

**Outcome.** Can state what a container isolates, what it does not, and which control to reach for.

**Feeds forward to.** Least privilege in RBAC (`w7.html#cp-7-6`), what runs privileged on a node
(`w1.html#cp-1-2`), secrets are base64 not encryption (`w3.html#cp-3-23`), certificates and trust
(`w2.html#cp-2-5`).

---

## I12 — Observability of a running runtime

**Prerequisites:** I7, I8.
**10 checkpoints · ~4 hours**

**Objectives.** Trace one line of application output from `write(2)` to the file `kubectl logs` reads;
explain where container metrics come from; read runtime events; know which question each of the three
signals answers.

**Checkpoint groups**
- *Logs* (3) — the path: workload stdout → shim → CRI log file → whoever tails it; the CRI log line
  format and its `stdout`/`stderr` and `P`/`F` (partial/full) fields; **rotation** and who owns it,
  which is why `kubectl logs` sometimes loses history; the design decision that a container that
  writes to a file inside itself has effectively no logs.
- *Metrics* (3) — cgroup files as the source of truth (B7's files, again), **cAdvisor** as the thing
  that reads them, and the Prometheus exposition format in ten lines; `ctr`/`crictl stats` and what
  they actually read; why container CPU is a counter and memory is a gauge, and the mistakes that
  follow from forgetting it.
- *Events and deeper* (2) — containerd events as an audit trail (`ctr events` during a pod's life);
  eBPF observability in one honest paragraph — what it makes possible and why it needs privilege;
  profiling a container from the host by PID.

**Mini project.** A ~50-line exporter: read the cgroup files for every running container, resolve
names via `crictl`/`ctr`, and serve Prometheus exposition on a port. Then scrape it with `curl` and
graph one number by hand. It is cAdvisor, minus twenty thousand lines.

**Debugging drill.** Two faults: logs that stop appearing (rotation plus a tail holding a deleted
inode — B5's stale-handle lesson at the observability layer); and a container whose memory metric
grows without its workload growing (page cache counted in `memory.current`, the single most
misdiagnosed container metric).

**Outcome.** Can answer "what is this container doing?" from the node, without Kubernetes.

**Feeds forward to.** metrics-server and the aggregated API (`w3.html#cp-3-19`), HPA's control loop
(`w3.html#cp-3-20`), the universal first moves — events, describe, logs (`w6.html#cp-6-1`), where
logs physically live (`w6.html#cp-6-2`).

---

## I13 — Capstone — `minidock` — & track assessment

**Prerequisites:** all of I0–I12.
**12 checkpoints · ~8 hours**

No new concepts. Assembly and proof. This module absorbs the supplied outline's Modules 19–22 (mini
Docker, mini containerd, mini CNI, tiny platform): they are one artifact built in layers, not four
programs.

**Checkpoint groups**
- *Capstone* (6) — build **`minidock`** one layer per checkpoint, each reusing the module's project:
  (1) pull and store — `pull.py` + a content store; (2) unpack and snapshot — `oci-inspect.py` +
  overlayfs, with a real cache so the second run is instant; (3) run — bundle + `runc` +
  `microshim.py`, with resource limits; (4) network — `cni-minibridge` invoked as a plugin, with
  DNS; (5) volumes and logs — `volman.py` plus CRI-format log files; (6) the platform layer — a
  metadata store, a CLI (`run`/`ps`/`logs`/`rm`/`exec`), multiple concurrent containers, and restart
  of failed ones under systemd.
- *Gauntlet* (3) — the timed eight-fault run against `labs/intermediate/*.sh`, then a written
  post-mortem of your own triage order, then a second run against the clock.
- *Assessment* (3) — the written self-test; the practical task set; the readiness checklist for the
  advanced track.

**Debugging gauntlet.** `labs/intermediate/i13-*.sh` — eight scripts, one planted fault per layer:
registry auth, corrupted blob/digest mismatch, malformed `config.json`, orphaned shim, CNI IPAM
exhaustion, cgroup-driver mismatch, snapshotter/GC leak, seccomp over-restriction. Same contract as
`labs/faults/` and `labs/beginner/`: banner, `read -p` confirmation, wrong-box guard (`hostname` must
be `buildbox` **and** `! -d /etc/kubernetes`), idempotent setup that verifies the subject works before
planting, no solution in the output, `bash -n` clean (shellcheck if available). Hints and solutions
are three-stage reveals on the module page.

**Track assessment.** `mock/intermediate-final.html` — 30 recall questions plus 8 practical tasks,
each mapped back to the module that taught it; `mock/intermediate-final-solutions.html` carries
solutions, verification commands and a rubric with a 66-point pass line out of 100, mirroring
`mock/beginner-final.html` and `mock/exam-1.html`. Both pages inline their own
`.task`/`.rubric`/`.timerbar` CSS, copied from `mock/exam-1.html` — `site.css` does not define those.

**Outcome / handoff.** The reader has implemented, at toy scale, every component the advanced track's
week 1 names in passing. The closing framing: *Kubernetes is the layer that decides **which** of these
should run **where**, and keeps deciding.* The module ends with an explicit "you are ready for the
advanced track when you can…" checklist, pointing at `index.html` and `materials/w0.html`.

---

## Site mechanics

### Files

| File | Role |
|---|---|
| `intermediate.html` | The intermediate tracker. Structural copy of `beginner.html`; sections `<section class="wk" id="iN" data-title="I0 · Build box">`, checkpoints `<li class="cp" data-id="iN-M">`; own `PUBLISHED` and `EXTRAS` arrays |
| `materials/i0.html … i13.html` | One page per module |
| `labs/intermediate/seed/{minibox.sh,net-up.sh}` | The two beginner artifacts, so I0 can bootstrap a reader who skipped B-track |
| `labs/intermediate/i13-*.sh`, `i13-gauntlet.sh` | Capstone fault scripts + runner |
| `mock/intermediate-final*.html` | Track assessment |
| `assets/site.css` | Gains `.specref` (one new block, same `::before`-heading pattern as `.k8s-link`); everything else is reused |
| `assets/lesson.js` | **Unchanged** — done-sync keys off `data-id`, which is already generic |

### Anchor scheme

Tracker `data-id="i4-7"` ↔ lesson `<article class="lesson" id="cp-i4-7" data-id="i4-7">`. The
existing one-rule scheme covers it unchanged: **anchor id = `cp-` + data-id with a leading `w`
stripped**.

`tools/check-links.sh` needs a three-line change in I-S2: a third `check_track intermediate.html i
"intermediate track"` call, and its two hardcoded per-lesson regexes widened —
`id="cp-b\?[0-9]*-[0-9]*"` → `id="cp-[bi]\?[0-9]*-[0-9]*"` and `data-id="[wb][0-9]*-[0-9]*"` →
`data-id="[wbi][0-9]*-[0-9]*"`. The `aid="cp-${stem#w}"` derivation and the `materials/i[0-9]*.html`
glob already generalise. **`tools/check-html.py` needs no change** — it globs `*.html` at the repo
root, so `intermediate.html` is picked up automatically.

### Shared state

The same `cka-prep-v1` localStorage key as both other tracks — intermediate ids are namespaced by
their `i` prefix, so they cannot collide, and cross-track sync stays free. `intermediate.html`'s reset
button filters to `i`-prefixed ids only, exactly as `beginner.html` filters to `b`.

### Hours panel

Same as `beginner.html`: each `<section class="wk" id="iN">` carries `data-hours="N"` from the module
table (**78** in total), and `refresh()` sums each module's budget scaled by the share of its
checkpoints still unticked. Re-budgeting a module means updating the attribute, the table above, and
the hero counter together.

### Track switcher

The third pill goes live. Every page currently carries an **inert `<span>`** for Intermediate:

```html
<span>Intermediate<em>Containers &amp; runtimes · soon</em></span>
```

I-S2 replaces it with a real link in **all 35 existing pages** that contain `class="tracks"`
(root-relative `intermediate.html` at the repo root, `../intermediate.html` from `materials/`,
`cheatsheets/`, `mock/`), dropping the `· soon`. New intermediate pages carry `class="on"` on that
pill. Per-page "Site" lists stay unmerged — intermediate pages list intermediate modules plus a
`← Intermediate tracker` link, and the switcher remains the only crossing point.

`materials/foundations.html` stays the advanced track's express refresher and gains no `i` entries.

## Analogy registry — intermediate extension

The existing registries in `CLAUDE.md` stand unchanged; these extend the same hotel/city spine (one
hotel = one Linux machine, the city = the cluster). **Do not invent a competing metaphor for
anything already listed there.**

| Concept | Analogy |
|---|---|
| OCI runtime spec / `config.json` | the written work order for one room — what to do, spelled out so any contractor can do it |
| runc | the contractor who reads the order, does the work once, and leaves the site |
| shim | the on-site foreman who stays after the contractor leaves, so head office can close for the night without evicting the guest |
| containerd | the building-services company: keeps the parts warehouse, the room-prep crew, and dispatches contractors |
| OCI image | a flat-pack kit: a parts list plus sealed boxes, every box stamped with a part number |
| digest / content addressing | the part number *is* a fingerprint of the contents — two boxes with the same number are the same box |
| registry / distribution spec | the warehouse that ships parts by part number, and the standard order form for doing so |
| snapshotter | the room-prep crew who stack the transparent sheets (B5's overlayfs) into a ready room |
| pod sandbox / pause container | the room itself — rented, numbered and wired before any guest checks in |
| CRI | the standard order form the tenant office files with *any* building-services company |
| CNI | the standard wiring contract: the electrician is handed a room number and a job, and reports back the socket they fitted |
| CSI | the same, for plumbing to a storage unit off-site |
| SBOM / signature | the parts list and the tamper seal on the kit |

## Session plan

Each phase is one session, start to finish, ending with green checkers, a commit, and a site that
renders with nothing half-written. No session depends on another session's in-memory context.

**Resume recipe:** read `CLAUDE.md`'s intermediate roadmap row → read this doc's module section →
`git log --oneline -8` (what actually landed, vs. merely marked done) → run the three checkers for a
green baseline → do the work → checkers → commit → tick the row here and in `CLAUDE.md`, and update
the `intermediate-track-plan` memory.

| Phase | Scope |
|---|---|
| **I-S1** | This document. Docs-only commit |
| **I-S2** | ✅ **done.** Wiring, no content: `.specref` in `site.css`; `tools/check-links.sh` third track; switcher pill made live in all 35 pages; stub `intermediate.html` with `PUBLISHED=[]`; `labs/intermediate/seed/` populated from the beginner artifacts. Two notes for later sessions: the stub's counters fall back to a `PLANNED={cps:195,hrs:78}` constant while no `section.wk[id^="i"]` exists — **delete it once I-S3 lands real sections**, or the fallback silently masks a selector bug; and the seed scripts are `bash -n`-clean but have **never been run live** (no `buildbox` yet), so I0 must run both end to end and paste real output |
| **I-S3** | ✅ **done.** `intermediate.html` sections **I0–I6** (96 checkpoints, 35 h), each following this document's checkpoint groups exactly, with a trailing `Project & drill` group (I0: project only). One note for I-S4: `PLANNED` was **kept rather than deleted** — with only half the sections present, counters that measure just the tickable part would report 96 cps / 35 h as the whole track, so `PLANNED` gained `mods:14` and the hours note now reads "N h published of ~78 h planned" while `mods.length < PLANNED.mods`. Delete it in I-S4, when that branch becomes dead code. Checkpoint prose deliberately says "containerd 2.x" / "runc 1.5.x": a re-search on 2026-07-26 already returned **2.3.3**, so exact pins belong in I0's install lab, in one place, next to a pasted version command |
| **I-S4** | ✅ **done.** `intermediate.html` sections **I7–I13** (99 checkpoints, 43 h) — the tracker is now complete at **195 cp / 78 h across 14 modules**, verified by count against this document's per-module tables. `PLANNED` and the partial-publication branch in `refresh()` are deleted; the hours note now reads plain "N modules to go · 78 h total", matching `beginner.html` line for line. The "Being written now" banner was rewritten to the beginner track's post-completion wording. Facts re-verified 2026-07-27 while authoring: containerd **2.3.3** (2026-07-10 — the page footer's pin was bumped from 2.3.2), CNI spec **1.1.0**, CSI spec **1.11.0**, and in-place pod resize is **GA in k8s v1.35**, not merely extended — I8.10 says GA. One wording note carried into I9.3: the CNI spec's own sentence enumerates *five* operations (ADD, DEL, CHECK, GC, VERSION) and defines STATUS alongside them, so the checkpoint quotes it that way rather than saying "six verbs" |
| **I-S5** | ✅ **done.** `materials/i0.html` — the pattern-setter (8 lessons, every one carrying the full anatomy; `.specref` on I0.6 and I0.7). `intermediate.html`'s `PUBLISHED` is now `[0]`. Every command on the page was **run live** and its output pasted verbatim. Three findings for later sessions: (1) containerd **2.3.3's `containerd config default` emits `version = 4`, not 3** — 2.0 moved 2→3, 2.3 moved 3→4, and the default output still also carries a legacy `plugins.'io.containerd.grpc.v1.cri'` section beside the split `…cri.v1.runtime` / `…cri.v1.images` plugins; I7/I8 must not repeat the "version 3" claim. (2) `crictl info`'s `.status` on a fresh box reports `NetworkReady: false` / `cni plugin not initialized` plus a `ContainerdHasNoDeprecationWarnings` condition — used as I0.6's teaching moment and I9's payoff. (3) **`labs/intermediate/seed/minibox.sh` was broken and is fixed in this commit** — see the note below |
| **I-S6** | ✅ **done.** `materials/i1.html` — the bridge module (14 lessons); `PUBLISHED` is now `[0,1]`, and `i0.html`'s pager next points at `i1.html`. Every command was **run live** on the beginner track's `sandbox` VM (2 vCPU, kernel 6.8.0) — I1 is the one module that needs no container tooling, so the page says either VM is fine and states the core count its captures came from. Five findings that correct assumptions in this document's own I1 notes: (1) **24.04 does not block userns creation.** The stock `unprivileged_userns` AppArmor profile carries `allow userns` *and* `audit deny capability`, so `unshare --user` succeeds and lands with `CapEff: 0000000000000000`; every downstream symptom (uid_map write EPERM, `setresuid` EPERM, mount EPERM) is that empty effective set, and no error message names AppArmor — `dmesg \| grep apparmor` is the only tell. (2) The **right** way past it is a named profile granting `userns,` for one binary by absolute path, verified working with the machine-wide sysctl left at `1`; the lesson ranks that above the usual "flip the sysctl". (3) The containerd/Docker default seccomp profile **moved to the `moby/profiles` repo** — every `moby/moby` link to it 404s — and lists **442** syscall names, not the "about 300" this document and most of the web repeat; its `clone` rule masks `0x7E020000`, i.e. *all* `CLONE_NEW*` bits, so a default container may create no namespace at all. (4) **Unprivileged overlayfs works** inside a userns+mountns on this kernel, so `fuse-overlayfs` is *not* required — the I1.13 note in this document is pre-5.11 folklore; the lesson says test it. (5) Cgroup delegation is not "you own the directory": writing your own pid into a cgroup you made under `user@1000.service` fails `EPERM` because migration is checked on the **common ancestor** (`user-1000.slice`, root's), so the project uses `systemd-run --user --scope` as Podman does; the delegated controller set is `cpu memory pids` — no `cpuset`, no `io`. Also worth carrying forward: the 6.8 kernel now **refuses** `ip link set vxlan0 mtu 1500` over a 1500 underlay with `EINVAL`, so the naive form of the MTU bug is unreachable and I1.12/I1.14 reproduce the form that still happens (underlay shrinks after the overlay was sized). I1.12 carries the module's only `.specref` — permitted to be absent across I1, but RFC 7348 earns one in the negative: its MTU text is a `RECOMMENDED`, and the number 50 appears nowhere in the document |
| **I-S7** | ✅ **done.** `materials/i2.html` — the OCI runtime spec (16 lessons); `PUBLISHED` is now `[0,1,2]`, and `i1.html`'s pager next points at `i2.html`. Every command was **run live** on `sandbox`, which by now carries the whole intermediate toolchain (containerd 2.3.3, runc 1.5.1, crun 1.14.1 from apt, nerdctl, the venv) and working internet — I2 needs only `runc`, `crun` and one `ctr images pull`, so it did not justify standing `buildbox` up. Six findings that correct this document's own I2 notes: (1) **`runc spec` emits six top-level keys, not eight** — `hooks` and `annotations` are legal and simply absent, which is itself worth teaching. (2) I2.6's "remove `/proc` and watch `ps` stop working" is **wrong on runc 1.5.1**: the container never starts. `libpathrs` panics with *"at least one candidate /proc/thread-self path should work"* and the operation fails `procReady not received`, because runc's own init resolves paths through `/proc/thread-self`. Shadowing `/proc` with a later `tmpfs` is refused outright by an explicit **proc-safety check**. The lesson keeps both, and the point lands harder: `/proc` is load-bearing for the *runtime*. (3) `cpu.shares` → `cpu.weight` is a **logarithmic** rescale (2→1, 512→59, 1024→100, 4096→303, 262144→10000), mapped empirically at five points rather than asserted. (4) OCI `memory.swap` is memory **plus** swap (v1 `memsw` semantics), so equal `limit`/`swap` yields `memory.swap.max = 0` — the most common mistake in the `resources` object. (5) I2.14's "run your byte-identical bundle with crun" **cannot work as written**: crun 1.14.1 reports `spec: 1.0.0` and refuses `ociVersion` ≥ 1.2.0 with *"unknown version specified"*. Its ceiling (1.1.0) is mapped in the lab, and the refusal becomes the better lesson — the contract is versioned and a runtime says what it implements. At 1.1.0 the two runtimes differ in **two namespace inode numbers** and nothing else. (6) I2.16's third drill is **not** a startup failure: a numeric `process.user.uid` absent from the rootfs starts fine and fails later with permission-denied plus `whoami: unknown uid 1000`. The real `CreateContainerError` needs a user *name* and lives one layer up — `ctr run --user appuser` gives `ctr: no users found`. Both are taught, distinguished by layer. Also carried forward: runc **warns and continues** on unknown capability names where the spec says it MUST error, silently producing an empty set — used deliberately as the project's planted bug. The mini project's diff against `minibox` came out **empty**, capability mask included, which is the track's thesis measured. A cross-link audit retargeted six of the page's 18 advanced/beginner anchors, and confirmed the advanced track has **no** dockershim-removal lesson and **no** `RuntimeClass` lesson — the page says so rather than inventing them |
| **I-S8** | ✅ **done.** `materials/i3.html` — runc internals (14 lessons); `PUBLISHED` is now `[0,1,2,3]`, and `i2.html`'s pager next points at `i3.html`. Every command was **run live** on `sandbox`; I3 needs only `runc`, so again no second VM. Findings that correct this document's own I3 notes: (1) **Three processes, not two.** `runc --debug` names them `nsexec` stage 0 / 1 / 2: stage 0 is the re-exec'd `runc init`, stage 1 unshares all six namespaces in a single call, stage 2 is the container's PID 1. The third exists because `unshare(CLONE_NEWPID)` does not move the caller into the new namespace — only its future children — so one more `clone()` is forced by the kernel. Both intermediate clones use `CLONE_PARENT`, so stage 2 stays parented to the original runc. (2) The re-exec is `execve("/proc/self/fd/6", ["runc","init"])` — **a file descriptor, not a path**. `libcontainer/exeseal` makes a sealed clone of the binary (overlayfs preferred, then `memfd_create`, then `O_TMPFILE`); verified the fd has runc's inode on a different device. This is the CVE-2019-5736 fix and worth stating, since this document's I3.1 text implies a plain re-exec. (3) The handshake is `INITPIPE`/`SYNCPIPE`/`LOGPIPE`/`LOGLEVEL`/`FIFOFD`/`INITTYPE` — **`_LIBCONTAINER_STATEDIR` and `_LIBCONTAINER_CONSOLE`, which this document's I3.2 lists, do not exist in runc 1.5.1**; they are 1.0 material. `strace` hides all of it without `-v`. `INITTYPE=setns` is what `runc exec` sets — one binary, two directions. (4) **`strace -f runc create` never returns**, because `create` deliberately leaves `runc init` alive; the labs wrap it in `timeout` and say why, since "the trace hung" reads as "the runtime hung". (5) I3.6's "make the naive version lose at least once" **understates it**: `runc state` reports `pid: 0` once a container is stopped, so against a container that exits immediately the naive lookup loses **20 out of 20**, and against `sleep 1000` it never loses — which is exactly why the bug survives testing. (6) I3.8's "which namespaces does `exec` re-enter and which does it not" **has no negative answer for runc**: all eight inodes match PID 1's, and it joins the cgroup too. The real surprise is that `exec` does *not* inherit the container's `process` block. (7) `runc update` changes the live cgroup and writes through to **neither** the bundle nor `state.json` — the Kubernetes in-place-resize (GA v1.35) caveat, and not something this document anticipated. (8) `state.json`'s `config` key is **libcontainer's internal struct**, not "the full config it was given" — `readonlyfs`, `mask_paths`, `readonly_paths`. `init_process_start` is byte-identical to field 22 of `/proc/<pid>/stat`, the anti-PID-reuse guard. (9) I3.10's improper fix is worse than described: `rm -rf` on the state dir **succeeds, allows recreation, and leaks the container's cgroup directory** with no record anywhere. (10) `criu` has **no installation candidate on noble**, so `runc checkpoint` fails with executable-not-found; the lesson turns `runc checkpoint --help` into the lab, reading each flag (`--tcp-established`, `--ext-unix-sk`, `--file-locks`, `--link-remap`, `--shell-job`) as an admission about a relationship whose other end cannot be captured. Kubernetes checkpointing verified: alpha v1.25, **beta and enabled by default since v1.30, still beta**. (11) The drill's second fault came out richer than planned — `SIGKILL`ing the shim leaves the container **running**, re-parented to PID 1 a second time, so the stale record and a live container coexist: `runc create` says "already exists" but plain `runc delete` **refuses** with "not stopped: running". That refusal is the diagnostic, and it distinguishes this fault from I3.10's. Also carried forward: `microshim.py` works only because of `prctl(PR_SET_CHILD_SUBREAPER, 1)` — without it `os.wait()` raises immediately and the shim reports a status it never received; with it the container's parent is the shim rather than systemd, and a single `SIGTERM` produces a clean forward, trap, and **exit=42**, the code plain `runc run --detach` discards |
| **I-S9** | ✅ **done.** `materials/i4.html` — the OCI image spec (16 lessons); `PUBLISHED` is now `[0,1,2,3,4]`, and `i3.html`'s pager next points at `i4.html`. Ships `labs/intermediate/oci-inspect.py` (~190 lines, stdlib only). Every command was **run live on `sandbox`** — I4 needs only `skopeo`, `jq`, `tar`, `nerdctl` and one `alpine:3.21` pull, so it again did not justify standing `buildbox` up; the user asked why the spec sized that box at 8 GB and the honest answer is that the figure was never measured — 4 GB is comfortable, disk is the real constraint, and the question is deferred to **I6**, where BuildKit and a local registry first matter. Findings that correct this document's own I4 notes: **(1)** I4.11's claim that "a wholly-replaced directory is marked with `.wh..wh..opq`" **did not reproduce**. `rm -rf /etc/apk && mkdir /etc/apk` committed through containerd emits one `.wh.<child>` per former child and no opaque marker — even though overlayfs *did* set `trusted.overlay.opaque=y` on the upper dir (verified with `getfattr` on snapshot 8, alongside the `c--------- 0, 0` char device for the deleted file). The cause is containerd's default **`walking` differ**, which compares filesystem trees and so never reads the overlay upper dir. Both encodings are legal; the lesson teaches both and states that a consumer must handle either. Binding on I7. **(2)** A real Docker Hub index carries **attestation manifests**: `alpine:3.21` has **16 entries for 8 architectures**, the other 8 marked `platform: unknown/unknown` with `vnd.docker.reference.type: attestation-manifest`. A naive platform selector picks one — so I4.15's project filters on both signals, and I5's `pull.py` must too. This document did not anticipate them. **(3)** `architecture` and `variant` are separate fields — `arm64` + `v8`, never "arm64v8"; a first-draft `jq` that concatenated them produced exactly that plausible nonsense. **(4)** I4.7's "see how little differs" is **three media-type strings plus the annotations block**, measured with `diff`: config and layer digests are byte-identical, the same blobs back both formats, so conversion changes the manifest digest while moving no bytes and silently **drops annotations** (v2s2 has nowhere to put them). **(5)** The chain-ID recursion reproduces containerd's snapshot key **exactly** (`968325f7…`) — single space, both operands keeping their `sha256:` prefixes; worth stating that chain IDs are **not in the OCI spec** but a containerd construction on its ordering guarantee. **(6)** I4.10's non-determinism claim measured rather than asserted: recompressing at `gzip -1` gives a new `digest`, an unchanged `diff_id`, and a *larger* file. **(7)** I4.14's precedence rule has one asymmetry — overriding the entrypoint **discards the image's `Cmd`**; case 3 prints an empty line and exits 0, which is exactly a pod spec with `command:` and no `args:`. The spec is silent on this, so it must be measured. **(8)** I4.16's second fault needed splitting in two: against a full index you get a clean "no image found for platform"; against a **single-platform** layout nothing selects at all, and only checking the resolved config's own `architecture` catches it — nothing in the real pull path does, which is why it surfaces later as `exec format error`. The third fault came out better than planned: reversing the layer order resurrects the deleted file and leaves **zero** stray `.wh.` files — no error, no warning, a rootfs that passes every test you would think to write. Tooling notes: `nerdctl` rejects a one-character container name; `nerdctl commit -c` accepts only `CMD` and `ENTRYPOINT`; `commit` sweeps the runtime-injected `/etc/resolv.conf` into the layer; `tools/scaffold-module.py` emits a bare `class="lesson"` for project/drill articles, which need `class="lesson project"` / `class="lesson drill"` for the anatomy checker and site.css |
| **I-S10** | `materials/i5.html` — the OCI distribution spec (15 cp) ✅ done |
| **I-S11** | ✅ **done.** `materials/i6.html` — building images (13 lessons); `PUBLISHED` is now `[0,1,2,3,4,5,6]`, and `i5.html`'s pager next points at `i6.html`. Ships `labs/intermediate/tinybuild.py` (~440 lines, stdlib only, reusing `pull.py` unchanged for `FROM`). **The `buildbox` question deferred from I-S9 is now settled: no second VM.** `sandbox` gained the **BuildKit v0.32.0** tarball (released 2026-07-29) plus `tonistiigi/binfmt --install arm64`, giving `buildkitd --containerd-worker` and a `linux/amd64,linux/arm64` worker on 2 vCPU / 3.8 GB / 16 GB free — ample, and the user chose it over provisioning `buildbox`. There is deliberately **no Docker** on the machine, so I6.8's "which has no Docker on it" holds with `sandbox` substituted for `buildbox`. Findings that correct this document's own I6 notes, all measured: **(1)** I6.1's checkpoint text puts `WORKDIR` in the config-amending bucket. **It is layer-producing** — unconditionally, even pointed at `/tmp` and `/etc` which already exist, because the step goes through the filesystem-snapshot path. Nine instructions gave **four** layers. When the diff is empty the slot holds the empty layer: 1024 zero bytes, `diff_id sha256:5f70bf18a086…` (the constant in image-spec's own `config.md` example), gzipping to the 32-byte blob `sha256:4f4fb700ef54…`; two such steps dedupe to one blob. So the reliable rule is a question about **mechanism**, not a list of instruction names. **(2)** I6.2's "Under the hood" says *"the whole context is uploaded to the builder… transferred even when no `COPY` ever references it."* **False on BuildKit** — 101 MB on disk including a 100 MB junk file transferred **38 B**. That warning describes the legacy Docker daemon, which tarred the directory up front. The claim that survives is one step along: `COPY . .` widens the graph's reference to everything, and then it really is **104.89 MB / 5.679 s** versus **114 B / 0.887 s** with a `.dockerignore` — same Dockerfile, same directory — with the `.env` recoverable from the finished image. **(3)** A Dockerfile **comment does not bust the cache** (comments never become LLB vertices), and neither does `touch` with unchanged content (content is hashed, not mtime — that *was* different on older builders); `chmod` does. I6.3's checkpoint asks the reader to record "after which change the cache stopped hitting" for a comment edit, and the answer is that nothing happens. **(4)** `--no-cache` **empties `type=cache` mounts**, permanently: four accumulated lines → one, and the next ordinary build saw two rather than five. Cache mounts otherwise persist across builds and are keyed by **target path** by default, so unrelated projects sharing a path share a cache. Neither behaviour is in this document. **(5)** The `--build-arg` leak appears **twice** in `history` — as `ARG NAME=value` *and* inlined into the `RUN` entry via the `|1` prefix — while the only added layer is the 32-byte empty blob, so a scanner that unpacks layer tars finds nothing at all. **(6)** I6.7's "five to twenty times slower" is not what one machine measured: **4.1×** on an interpreter-bound loop (0.8 s vs 3.3 s) and **1.6×** on a hashing step, both from one two-platform build. The case that matters is not a multiple — an emulated `apk add build-base` **did not complete in 520 s** where the native install takes ~20 s, so the real failure mode is a CI timeout. The lesson reports the range it measured. **(7)** `nerdctl build` and `buildctl` produce **identical manifest digests** but write to **different containerd namespaces** (`default` vs `buildkit`), so `nerdctl run` on a `buildctl`-built image concludes it is remote and tries to **pull** it — the error names a connection failure against I5.13's mirror (`?ns=docker.io` and all) and mentions neither namespaces nor the build. Same class of trap as I5.13's two non-interchangeable `config_path` settings. **(8)** `registry:2`'s blob-upload `Location` is an **absolute** URL that already carries `?_state=`, so prefixing the registry root gives `curl` exit 3 on a malformed URL and the digest must be appended with `&`; and `gzip` needs `-n`/`mtime=0` or the header timestamp changes the layer digest for identical bytes. Both are now encoded in `tinybuild.py`. **(9)** Secret mounts and cache mounts work with BuildKit 0.32's **builtin** frontend — no `# syntax=` directive needed. **(10)** A multi-stage image's `created_by` reads `COPY /hello /usr/local/bin/hello` with `--from=build` **stripped**, so the best-built images have the thinnest audit trail — a caveat I6.10 had to carry. Corroborating that: one of `python:3.13`'s seven layers reports `created_by` of `# debian.sh --arch 'amd64' out/ 'trixie' '@1783900800'`, not a Dockerfile instruction at all. Measured numbers the lessons are built on: multi-stage **261.9 MB → 8.598 MB**; whiteout cost **108,536,725 B in 3 layers vs 3,646,907 B in 2** with a 77-byte `.wh.big.bin` layer; `python:3.13` **236,258,363 of 412,660,988 bytes in one `apt-get install`**; the drill's cache fault **5.600 s → 1.060 s** on reorder. The drill's second fault needed redesigning once — the first version's Dockerfile recreated the missing file and so passed all three builds, i.e. it was self-healing rather than a fault; the shipped version is the one this document describes, and its diagnostic is the **empty-layer digest appearing where a step should have produced output**, which makes I6.1's constant a debugging tool by I6.13 |
| **I-S12 … I-S18** | `materials/i7.html` … `materials/i13.html`, one module per session |
| **I-S19** | `labs/intermediate/i13-*.sh` + `mock/intermediate-final*.html` + cross-track QA + docs |

**Seed-script correction, made in I-S5 (2026-07-27).** I-S2 shipped `labs/intermediate/seed/*.sh`
`bash -n`-clean but never executed. Running `minibox.sh` for the first time in I0.3 showed it could
never have worked: it dropped `CAP_SYS_ADMIN` with `capsh` *before* calling `unshare`, and both
`unshare(2)` and `pivot_root(2)` require it — so it died with `unshare failed: Operation not
permitted` having isolated nothing. B14's own listing (`materials/b14.html`, the lesson that builds
`minibox` layer by layer) **has the same ordering bug and is still unfixed** — fixing it there means
reworking several interlocking Python-patch lab steps, which is a beginner-track session's work, not
a drive-by. The seed copy now: builds the rootfs with `capsh` plus its three shared objects copied in
(`install_capsh()`), runs a plain `unshare` in stage 1, and drops the four capabilities in stage 2
*after* `enter_rootfs`; it also calls `hash -r` after `pivot_root`, because bash had cached
`/usr/bin/mount` and that path no longer exists inside the new root. The fix is pedagogically better
than the bug: "isolate, then disarm" and "a bash runtime must ship `capsh` into the rootfs because
`runc`, being one process, still has its own code in memory when it drops privilege" are now I0.3
content and set up I3. Verified live: namespaces, cgroup limits, veth/bridge/NAT egress, and the
four-capability drop all confirmed by pasted output. `net-up.sh` needed no change and works as
shipped (its first pod-to-pod ping can time out on ARP — use `-c2`).

**Sessions at risk of overrunning:** I-S12 (I7, 18 cp) certainly, and I-S7 (I2), I-S9 (I4), I-S13
(I8), I-S14 (I9) plausibly — all 16 cp with heavy labs. Plan two sittings for I7. The beginner
track's rule applies: before stopping, every checkpoint in the module must already have its
`<article id="cp-iN-M">` on the page — even if some hold only a *Why it matters* paragraph — so
`tools/check-links.sh` stays green, and the unfinished lesson list goes into the `CLAUDE.md` row.

**Publishing a module** (last step of its session): add its number to `intermediate.html`'s
`PUBLISHED` array, add its entry to the intermediate sidebar list on every `materials/i*.html`,
repoint the previous module page's pager `next` from the tracker anchor to the new sibling file
(the beginner track resolved this convention in B-S19 — do it as you go here, not retroactively), and
run the checkers.

**Splitting a module across commits.** Unchanged from the beginner track: a full module page runs
1000–1500 lines, past the global ≤500-added-lines-per-code-commit rule, so it takes 3–4 commits.
`check-links.sh` globs `materials/i[0-9]*.html` the moment the file exists, so it reports
not-yet-written anchors as missing on every commit but the last. Split along **checkpoint-group
boundaries** so each commit is whole lessons, say so in the intermediate commit messages, and require
green checkers only at the end of the session.

## Verification (every session)

```bash
tools/check-links.sh              # all three trackers
tools/check-html.py               # includes intermediate.html
node --check assets/lesson.js
bash -n labs/intermediate/*.sh    # shellcheck too, if available
python3 -m http.server 8000
```

Then in the browser:

1. `intermediate.html` renders: ring, group nav counts, collapse/expand, resume link, hours panel.
2. Tick a checkpoint on `intermediate.html` → reload `materials/iN.html` → shows done; and the reverse.
3. Tick checkpoints in the other two tracks → intermediate counts unaffected; each reset clears only
   its own prefix.
4. The switcher reaches all three trackers from every page, with no pill left inert.
5. Every `k8s-link` and every beginner back-reference anchor lands on the right lesson.
6. Theme toggle consistent across all three trackers and every lesson page.
7. **Every lab command run live on `buildbox`** with its real output pasted in — the slowest step per
   session and the one that keeps the track honest. This track needs it more than the beginner track
   did: containerd, runc and the OCI tooling all move fast enough that remembered output goes stale.

---

## Appendix A — source outline, as supplied

The site owner's original 22-module topic outline, preserved for traceability. The mapping to the
14 modules above is in § "Relationship to the beginner track" (for the eight overlapping modules) and
here (for the rest):

| Supplied | Lands in |
|---|---|
| M6 OCI Standards | **I2** (runtime spec), **I4** (image spec), **I5** (distribution spec) |
| M7 Container Images | **I4** (layers, digests) + **I6** (build, cache, BuildKit) + **I5** (registry protocol) |
| M8 Container Runtime Architecture | **I7** |
| M9 containerd Internals | **I7** |
| M10 runc Internals | **I3** |
| M12 CNI Internals | **I9** |
| M13 Container Storage | **I10** |
| M14 Container Security | **I11** (with capabilities/seccomp/AppArmor basics already in B4, B12, I1) |
| M15 CRI | **I8** |
| M18 Observability Foundations | **I12** |
| M19 Mini Docker · M20 Mini containerd · M21 Mini CNI · M22 Tiny platform | **I13**, as one layered artifact (`minidock`) rather than four separate programs; the CNI half is already built as I9's project |

### Verbatim outline

> **Objective.** The Intermediate Track bridges the gap between foundational Linux/OS knowledge and
> Kubernetes. Instead of teaching Kubernetes directly, this track teaches learners how the
> technologies Kubernetes depends on are implemented and work together. By the end, learners should be
> able to: explain every major component in the container ecosystem; build simplified versions of
> container technologies; understand the internal architecture of Docker, containerd, runc, CRI and
> CNI; debug container and networking issues without relying on Kubernetes abstractions; understand
> why Kubernetes is designed the way it is. The curriculum should emphasize implementation over
> theory. Every major topic should culminate in building or modifying a working implementation.

1. **Process Isolation Revisited** — process tree internals, init process, PID 1 behavior, zombie
   processes, orphan processes, signal forwarding, process reaping, process groups, sessions,
   controlling terminals, daemonization, fork/exec model, `clone()`, `unshare()`, `setns()`. *Labs:*
   build a tiny init; observe zombie accumulation; implement signal forwarding.
2. **Linux Namespaces Deep Dive** — PID, mount, network, user, IPC, UTS, time namespaces; lifecycle,
   hierarchy, persistence, switching, sharing, nesting, security. *Hands-on:* create namespaces
   manually; join existing; share between processes; inspect inode IDs. *Project:* namespace manager
   CLI.
3. **cgroups Internals** — v1, v2, resource accounting, CPU/memory/IO/PIDs controllers, cpuset,
   HugePages, device controller, OOM behavior, PSI. *Labs:* limit CPU; trigger OOM; limit processes;
   implement memory limits. *Project:* resource manager.
4. **Filesystems Behind Containers** — OverlayFS internals, AUFS history, copy-on-write, whiteout
   files, layer merging, mount propagation, bind mounts, tmpfs, devtmpfs, procfs, sysfs, root
   filesystem, `pivot_root`, `switch_root`, mount options. *Labs:* build layered filesystem manually;
   explore OverlayFS metadata; implement writable layer. *Project:* your own layered filesystem.
5. **Building a Minimal Container** — what makes a container; root filesystem; process, filesystem,
   resource and networking isolation; capabilities; seccomp, AppArmor, SELinux basics. *Labs:* build
   a container using `clone()`, namespaces, cgroups, `pivot_root()`, `mount()`. *Project:* minimal
   container runtime.
6. **OCI Standards** — image, runtime and distribution specifications; image manifests, layers,
   digests, config objects, media types, runtime bundles, image layout. *Labs:* inspect OCI images
   manually. *Project:* simple OCI image parser.
7. **Container Images** — image creation, layer caching, Dockerfile internals, build context,
   multi-stage builds, layer optimization, image history, manifest lists, multi-platform images,
   BuildKit concepts, registry protocol, content-addressable storage. *Labs:* build image manually.
   *Project:* tiny image builder.
8. **Container Runtime Architecture** — Docker architecture, dockerd, containerd, runc, shim
   processes, runtime lifecycle, runtime hooks, snapshotters, content store, metadata store. *Labs:*
   inspect runtime processes. *Project:* simplified runtime manager.
9. **containerd Internals** — daemons, plugins, gRPC APIs, snapshotters, leases, content store,
   metadata, event system, task lifecycle, containers vs tasks. *Labs:* interact with containerd
   directly. *Project:* containerd client.
10. **runc Internals** — runtime bundles, OCI configs, process creation, namespace setup, mount setup,
    cgroup setup, lifecycle, hooks, checkpoint/restore. *Labs:* run containers using runc only.
    *Project:* modify runc behavior.
11. **Container Networking** — network namespaces, veth pairs, Linux bridges, TAP/TUN, routing, NAT,
    iptables, nftables, ARP, neighbor tables, VXLAN, GRE, overlay networks, hairpin mode, MTU,
    conntrack. *Labs:* build virtual network manually. *Project:* connect multiple containers
    manually.
12. **CNI Internals** — why CNI exists, the specification, ADD/DEL/CHECK, plugin chaining, result
    formats, runtime configuration, IPAM, bridge plugin, host-local IPAM, macvlan, ipvlan, loopback,
    tuning and firewall plugins. *Labs:* install CNI manually. *Project:* simple CNI plugin.
13. **Container Storage** — volumes, bind mounts, CSI overview, local storage, block devices,
    filesystem volumes, mount propagation, persistent storage concepts, snapshotting, device plugins.
    *Project:* local volume manager.
14. **Container Security** — Linux capabilities, capability sets, seccomp filters, AppArmor, SELinux,
    user namespaces, rootless containers, image signing, supply chain, cosign, SBOM, CVE scanning,
    distroless images. *Labs:* restrict container permissions. *Project:* harden your runtime.
15. **CRI** — why CRI exists, CRI APIs, RuntimeService, ImageService, gRPC protocol, kubelet
    interaction, CRI plugins, runtime implementations. *Labs:* inspect CRI calls. *Project:* toy CRI
    server.
16. **Service Discovery Foundations** — DNS internals, service discovery, name resolution, CoreDNS
    architecture, load balancing, VIPs, kube-proxy concepts, iptables mode, IPVS mode, eBPF overview.
    *Labs:* implement DNS-based service discovery.
17. **Distributed Systems Foundations** — CAP theorem, consensus, Raft, leader election, heartbeats,
    quorum, failure detection, replication, eventual consistency, strong consistency, watches,
    idempotency, retry semantics. *Labs:* implement leader election.
18. **Observability Foundations** — logging architecture, metrics, tracing, OpenTelemetry, cAdvisor,
    Prometheus exposition, runtime metrics, container events, eBPF observability, profiling. *Labs:*
    instrument runtime.
19. **Building a Mini Docker** — image pull, image storage, layer management, namespace creation,
    cgroup setup, OverlayFS, process lifecycle, networking, logging, CLI, basic registry support.
20. **Building a Mini Containerd** — daemon, gRPC API, snapshotter, metadata store, content store,
    runtime management, event system, image manager.
21. **Building a Mini CNI** — bridge creation, veth setup, IP allocation, routing, NAT, cleanup,
    configuration parsing.
22. **Building a Tiny Container Platform** — bring everything together into a lightweight container
    platform capable of pulling OCI images, creating OverlayFS root filesystems, starting containers,
    managing namespaces, applying cgroups, connecting containers to virtual networks, providing
    service discovery, persisting metadata, managing volumes, logging container output, supporting
    multiple concurrent containers, restarting failed containers, and basic scheduling across a
    single host. *"This capstone project serves as the final milestone before learners move to the
    Advanced Kubernetes Track. At this point, Kubernetes should feel like a natural orchestration
    layer built on concepts and components they already understand and have implemented themselves."*
