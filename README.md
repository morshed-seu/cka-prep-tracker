# CKA Prep — Three-Track Internals Curriculum & Study Materials

A dependency-free study site for the Certified Kubernetes Administrator (CKA) exam:

- **Three complete tracks, ~590 tiny checkpoints** you can tick off; progress saves in the browser (localStorage — per device, no backend).
- Every topic pairs the hands-on exam task with an **"Under the hood"** note explaining the internals.
- **Self-contained lessons** for each checkpoint: concept + internals, a lab with exact commands and expected output, a verify step, gotchas, and deep links into the docs allowed in the exam.
- Exam-day countdown (set your date in the sidebar), per-track progress nav, light/dark theme toggle.
- Built for the post-Feb-2025 CKA curriculum (Gateway API, Helm, Kustomize, CRDs, CNI internals).

## Three tracks

The site is a full journey rather than a single course. Kubernetes invented very little —
it composes decades-old operating-system, networking and distributed-systems technology — so the
earlier tracks teach those primitives hands-on first, and every lesson ends by naming the
Kubernetes feature that wraps the primitive it just taught.

| Track | Start here | What it covers | Status |
|---|---|---|---|
| **Beginner** | `beginner.html` | Processes, signals, syscalls, permissions and capabilities, filesystems and overlayfs, namespaces, cgroups, TCP/IP, virtual networking and netfilter, DNS, systemd, TLS/PKI, distributed-systems fundamentals — ending in a container built by hand | ✅ complete (15 modules, 225 checkpoints) |
| **Intermediate** | `intermediate.html` | Containers for real: OCI runtime/image/distribution specs, runc/containerd internals, CRI, CNI plugins, container storage/CSI, supply-chain security, observability — ending in a capstone runtime (`minidock`) | ✅ complete (14 modules, 195 checkpoints) |
| **Advanced** | `index.html` | The CKA curriculum: kubeadm clusters, workloads/scheduling, networking, storage, troubleshooting, RBAC/auth | ✅ complete (9 modules, 171 checkpoints) |

<details>
<summary><strong>Beginner track — 15 modules</strong> (<code>beginner.html</code>, <code>materials/b0…b14.html</code>)</summary>

| # | Module |
|---|---|
| B0 | Your Linux sandbox |
| B1 | Shell, files, and the filesystem tree |
| B2 | Processes, threads, signals |
| B3 | Kernel space, user space, system calls |
| B4 | Users, groups, permissions, capabilities |
| B5 | Files for real: VFS, storage, overlayfs |
| B6 | Isolation I: namespaces, chroot, pivot_root |
| B7 | Isolation II: cgroups v2 |
| B8 | Networking I: the real network |
| B9 | Networking II: virtual networking & packet filtering |
| B10 | Names: DNS and resolution |
| B11 | Service management: systemd, logs, boot |
| B12 | Security fundamentals |
| B13 | Distributed systems fundamentals |
| B14 | Capstone: build `minibox`, then the gauntlet |

</details>

<details>
<summary><strong>Intermediate track — 14 modules</strong> (<code>intermediate.html</code>, <code>materials/i0…i13.html</code>)</summary>

| # | Module |
|---|---|
| I0 | Your build box |
| I1 | The primitives the beginner track left out |
| I2 | What a container is, formally (the OCI runtime spec) |
| I3 | `runc` internals |
| I4 | Images (the OCI image spec) |
| I5 | Registries (the OCI distribution spec) |
| I6 | Building images |
| I7 | Runtime architecture: containerd, shims, snapshotters |
| I8 | CRI: the interface the kubelet speaks |
| I9 | CNI: the interface the network speaks |
| I10 | Container storage: volumes, snapshots, the CSI shape |
| I11 | Container security & supply chain |
| I12 | Observability of a running runtime |
| I13 | Capstone: build `minidock`, then the gauntlet |

</details>

<details>
<summary><strong>Advanced track — 9 weeks</strong> (<code>index.html</code>, <code>materials/w0…w8.html</code>)</summary>

| # | Week |
|---|---|
| W0 | Set up your lab & logistics |
| W1 | How the control plane actually works |
| W2 | Installation, PKI & cluster lifecycle |
| W3 | Workloads, scheduling & app config |
| W4 | Services & networking, from veth up |
| W5 | Storage: PVs, PVCs & CSI |
| W6 | Troubleshooting: the 30% week |
| W7 | RBAC, ServiceAccounts & speed drills |
| W8 | Mock exams & execution |

</details>

No build step, no dependencies. Site map:

```
index.html                the advanced (CKA) tracker; 📖 links open each checkpoint's lesson
beginner.html             the beginner tracker — Linux and networking from the ground up
intermediate.html         the intermediate tracker — containers, runtimes, images, CNI
materials/wN.html         advanced lesson pages, one per week (lab + quiz); "done" syncs with the tracker
materials/bN.html         beginner lesson pages, one per module
materials/iN.html         intermediate lesson pages, one per module
materials/foundations.html   express refresher for readers who already know the fundamentals
labs/faults/              break-and-fix scripts that plant faults in your lab cluster (week 6)
labs/beginner/            break-and-fix scripts for the beginner track's debugging gauntlet
labs/intermediate/        Python/bash tools built during the track (a toy CRI server, a CNI plugin,
                          a CSI prober, minidock) plus the capstone gauntlet fault scripts
cheatsheets/              printable one-pagers (commands, etcd card, triage template, exam day)
mock/                     timed mock exams + solutions for all three tracks
assets/, tools/           shared CSS/JS and the anchor-integrity/authoring check scripts
docs/                     the build plans: PLAN.md (advanced), BEGINNER-TRACK.md (beginner),
                          INTERMEDIATE-TRACK.md (intermediate), AUTHORING.md (session runbook)
```

## Run locally

Open `index.html` in a browser, or:

```bash
python3 -m http.server 8000
# → http://localhost:8000
```

## Publish on GitHub Pages

1. Create a repository on GitHub (e.g. `cka-prep`) and push:

   ```bash
   git remote add origin git@github.com:<your-username>/cka-prep.git
   git push -u origin main
   ```

2. On GitHub: **Settings → Pages → Build and deployment** — set *Source* to **Deploy from a branch**, choose branch **`main`** and folder **`/ (root)`**, then save.

3. After a minute the site is live at `https://<your-username>.github.io/cka-prep-tracker/`.

> Note: GitHub Pages sites on the free plan are public. Progress is stored in each browser's localStorage, so your checkmarks stay on your device and are not shared through the site.
