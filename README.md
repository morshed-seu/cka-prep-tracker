# CKA Prep — 8-Week Internals Tracker & Study Materials

A dependency-free study site for the Certified Kubernetes Administrator (CKA) exam:

- **8 weeks, ~160 tiny checkpoints** you can tick off; progress saves in the browser (localStorage — per device, no backend).
- Every topic pairs the hands-on exam task with an **"Under the hood"** note explaining the internals.
- **Self-contained lessons** for each checkpoint (shipping week by week): concept + internals, a lab with exact commands and expected output, a verify step, gotchas, and deep links into the docs allowed in the exam.
- Exam-day countdown (set your date in the sidebar), per-week progress nav, light/dark theme toggle.
- Built for the post-Feb-2025 CKA curriculum (Gateway API, Helm, Kustomize, CRDs, CNI internals).

## Three tracks

The site is growing into a full journey rather than a single course. Kubernetes invented very little —
it composes decades-old operating-system, networking and distributed-systems technology — so the
earlier tracks teach those primitives hands-on first, and every beginner lesson ends by naming the
Kubernetes feature that wraps the primitive it just taught.

| Track | Start here | What it covers | Status |
|---|---|---|---|
| **Beginner** | `beginner.html` | Processes, signals, syscalls, permissions and capabilities, filesystems and overlayfs, namespaces, cgroups, TCP/IP, virtual networking and netfilter, DNS, systemd, TLS/PKI, distributed-systems fundamentals — ending in a container built by hand | in progress |
| **Intermediate** | — | Containers for real: OCI, images and layers, a minimal runtime, CNI plugins, containerd/runc internals | planned |
| **Advanced** | `index.html` | The 8-week CKA curriculum described above | ✅ complete |

No build step, no dependencies. Site map:

```
index.html            the advanced (CKA) tracker; 📖 links open each checkpoint's lesson
beginner.html         the beginner tracker — Linux and networking from the ground up
materials/wN.html     advanced lesson pages, one per week (lab + quiz); "done" syncs with the tracker
materials/bN.html     beginner lesson pages, one per module
materials/foundations.html   express refresher for readers who already know the fundamentals
labs/faults/          break-and-fix scripts that plant faults in your lab cluster (week 6)
labs/beginner/        break-and-fix scripts for the beginner track's debugging gauntlet
cheatsheets/          printable one-pagers (commands, etcd card, triage template, exam day)
mock/                 original timed mock exam + solutions (week 8), and the beginner-track assessment
assets/, tools/       shared CSS/JS and the anchor-integrity check script
docs/                 the build plans: PLAN.md (advanced), BEGINNER-TRACK.md (beginner)
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
