# CKA Prep Site — Self-Contained Preparation Materials Plan

## Context

The repo (`index.html` + `README.md`) is a single-page, dependency-free CKA study **tracker**: 8 weeks, ~160 checkpoints, each a short task description with occasional "Under the hood" notes, published on GitHub Pages. The gap: checkpoints tell the reader *what* to do (e.g. "Learn Raft at the explain-to-a-colleague level", "plant faults in kube-apiserver.yaml and fix each") but the actual learning content lives elsewhere — official docs, killer.sh, a study partner. The goal of this change: **a user should be able to fully prepare for the CKA using only this site** — every checkpoint backed by a lesson, a lab, and a verification, plus fault-injection scripts, recall quizzes, cheat sheets, and an original mock exam.

Decisions already made with the user:
- **Fully self-contained** depth: every checkpoint gets concept + internals + step-by-step lab with expected output + verify step. Official docs become optional reference links (they're also the docs allowed in the exam, so deep links double as exam training).
- **All four extras**: break-and-fix fault scripts, recall quizzes, printable cheat sheets/templates, original mock exam.
- Implement **gradually** (user's exam is ~2026-09-10; they start studying now, so ship materials in week order, staying ahead of their schedule).

## Site architecture

Keep the existing ethos: static HTML, zero dependencies, no build step, works on GitHub Pages and via `python3 -m http.server`. The single file can't hold ~160 full lessons, so grow into a small multi-page site:

```
index.html               — tracker (existing; each checkpoint gains a 📖 link to its lesson)
assets/site.css          — shared stylesheet, extracted from index.html's inline CSS
assets/lesson.js         — shared JS for materials pages (theme, mark-done, quiz reveal)
materials/w0.html … w8.html  — one lesson page per week, one lesson section per checkpoint
labs/faults/wN-*.sh      — fault-injection scripts (plain files, also linked from lessons)
cheatsheets/commands.html, etcd-card.html, triage-template.html, exam-day.html
mock/exam-1.html         — 16-task timed mock exam;  mock/solutions-1.html
```

Key integration points:

- **Anchored lessons**: each lesson section in `materials/wN.html` gets `id="cp-N-M"` matching the tracker's `data-id="wN-M"` scheme (`index.html:167` and onward). Each `.cp` `<li>` in the tracker gets a small `📖` anchor → `materials/wN.html#cp-N-M`.
- **Shared progress**: materials pages read/write the same `localStorage` key `cka-prep-v1` (`index.html:604`) so each lesson has a "mark checkpoint done" toggle that stays in sync with the tracker. Same origin on GitHub Pages ⇒ works for free.
- **Theme**: reuse the existing `cka-theme` localStorage + `data-theme` mechanism (`index.html:663-672`) via `assets/lesson.js` so all pages follow one toggle.
- **CSS extraction**: move index.html's `<style>` block to `assets/site.css`, referenced by all pages; add lesson-specific styles (lesson layout, command blocks with expected-output panels, quiz reveal, print styles). Index keeps identical rendering — verify visually.

## Lesson anatomy (the per-checkpoint template)

Every checkpoint's lesson follows one fixed structure so the ~160 lessons read as one system:

1. **Exam relevance** — 1–2 sentences: how this shows up as an exam task, domain weight.
2. **The concept** — self-contained internals explanation (this absorbs and expands the existing "Under the hood" notes; the tracker keeps a one-line version, the lesson holds the full story). Inline SVG diagrams where a picture beats prose (architecture, packet path, PV binding flow, cert trust domains).
3. **Lab** — numbered steps with exact commands in copyable `<pre>` blocks and **expected output** shown beneath each (abridged, with the load-bearing lines highlighted). Written against the W0 3-node kubeadm cluster.
4. **Verify** — the single command/observation that proves it worked (mirrors exam habit 8.8).
5. **Gotchas** — exam traps and failure signatures for this topic.
6. **Docs** — 1–3 deep links into kubernetes.io / helm.sh (the allowed exam docs), framed as "where to find this during the exam".

Purely logistical checkpoints (0.1, 8.9…) get a compact version: relevance + concrete steps + links, no lab.

## Per-week content inventory

Each week page = lessons for all its checkpoints + a **recall quiz** (8–12 click-to-reveal questions) at the end. Week-specific highlights:

| Week | Page focus beyond lessons |
|---|---|
| W0 | Copy-paste-able full lab build: Multipass/Vagrant commands, containerd+kubeadm install transcript, snapshot script. Complete `.bashrc`/`.vimrc` block. |
| W1 | Architecture SVG (who-talks-to-whom), request-pipeline diagram, "trace a deployment" lab with real `-v6` output, stop-the-scheduler drill transcript. |
| W2 | PKI trust-domain diagram, cert-inspection lab with real openssl output, full etcd backup/restore drill with exact etcdctl flags, upgrade walkthrough (one minor version, control plane then worker). |
| W3 | Scheduling decision-tree diagram (filter/score), QoS/eviction table, Helm & Kustomize from-zero labs (install → template → upgrade → rollback; base/overlay exercise). |
| W4 | The internals-heaviest week: veth/bridge/netns hands-on lab (build a pod network by hand with `ip` commands), kube-proxy iptables walk (annotated `iptables -t nat -L` output), CoreDNS resolution ladder, Ingress + Gateway API labs, NetworkPolicy AND/OR worked examples. |
| W5 | PV/PVC binding state machine diagram, access-modes/reclaim-policy tables, local + NFS provisioner lab, CSI call-flow diagram. |
| W6 | Each "plant faults" checkpoint pairs with scripts in `labs/faults/` (see below). Lessons become **signature catalogs**: symptom → first command → root cause tables. Includes the 30-minute six-fault gauntlet as a scripted scenario. |
| W7 | CSR onboarding full transcript, RBAC matrix worked examples, jsonpath drill set with answers, speed-drill task list (10 tasks with target times + solutions). |
| W8 | Exam mechanics, final-48h checklist; links to the mock exam. |

## Fault-injection scripts (`labs/faults/`)

Self-study replacement for "have a partner plant faults" (6.6, 6.11, 6.19):

- One script per fault class, named by week/scenario: `w6-apiserver-01.sh` … `w6-gauntlet.sh`.
- Each script: a banner stating what it's about to break and a `read -p` confirmation (these intentionally break the **lab** cluster; guard against running on the wrong machine by checking for the lab's node names/context), the fault injection, and a printed "your mission" statement. **No solution in the script output.**
- Hints and solutions live in the W6 page as three-stage reveals: symptom → hint → full fix.
- Gauntlet script plants 6 workload faults at once and prints a 30-minute timer instruction.
- Scripts are plain bash, shellcheck-clean, downloadable from GitHub raw links referenced in the lessons.

## Cheat sheets (`cheatsheets/`)

Four printable one-pagers (shared print CSS, `@media print`, fits on one A4/Letter):
- `commands.html` — imperative generators, aliases, jsonpath patterns, `kubectl explain` recipes.
- `etcd-card.html` — backup/restore exact commands with cert flags, health checks.
- `triage-template.html` — the symptom → first-3-commands table, half filled, half blank (user fills during W6; supports checkpoints 6.4/6.23).
- `exam-day.html` — PSI rules, per-question rituals (context switch, ssh discipline), time strategy.

## Original mock exam (`mock/`)

- `exam-1.html`: 16 weighted tasks (mirroring domain weights: ~5 troubleshooting, 4 architecture, 3 networking, 2–3 workloads, 2 storage), each with its own context/namespace setup snippet to run first. Built-in 120-minute JS countdown. No solutions on the page.
- `solutions-1.html`: per-task full solution, verification command, and a grading rubric (points per task, 66% pass line).
- Setup script `mock/setup-exam-1.sh` provisions all task prerequisites on the lab cluster (namespaces, broken objects for troubleshooting tasks).

## Tracker (`index.html`) changes

Deliberately small: extract CSS to `assets/site.css`; add per-checkpoint 📖 lesson links; add a "Materials" block to the sidebar (cheat sheets, fault scripts, mock exam); trim any "Under the hood" `<details>` that the lessons fully absorb to a one-liner + link (keep the tracker skimmable). README gains a site map. The claude.ai artifact stays as-is (single-file tracker); once materials exist, update it once to banner-link the GitHub Pages site as the canonical home.

## Implementation phases (gradual, in study order)

Each phase is one working session ending with a local render check + commit. Content accuracy note: verify version-sensitive facts (curriculum weights, kubeadm/k8s current stable ≈1.33/1.34, Gateway API status) via web search **during authoring**, not from memory.

1. **P0 — Scaffolding**: extract `assets/site.css`, build the lesson page template + `assets/lesson.js` (theme, mark-done sync, quiz reveal, copy buttons), wire 📖 links pattern in index.html, sidebar Materials block, README update. Verify tracker renders pixel-identical.
2. **P1 — W0 + W1 pages** (user needs these immediately): ~36 lessons incl. the architecture/request-pipeline SVGs, both quizzes.
3. **P2 — W2 page** + `etcd-card.html` cheat sheet.
4. **P3 — W3 page**.
5. **P4 — W4 page** (heaviest diagrams: veth/bridge, kube-proxy DNAT path, DNS ladder).
6. **P5 — W5 page**.
7. **P6 — W6 page + `labs/faults/` script library + `triage-template.html`**.
8. **P7 — W7 page + `commands.html` cheat sheet**.
9. **P8 — W8 page + mock exam (`mock/`) + `exam-day.html`** + final cross-link/QA pass.

## Verification (each phase)

- `python3 -m http.server` → click through: tracker → 📖 link → lesson anchor lands correctly; mark-done on lesson page reflects in tracker (same localStorage); theme toggle consistent across pages; light + dark both readable.
- **Anchor integrity script** (add `tools/check-links.sh`): grep all `data-id="wN-M"` in index.html and assert a matching `id="cp-N-M"` exists in `materials/wN.html`, and vice versa; run every phase.
- Cheat sheets: browser print preview fits one page.
- Fault scripts: `shellcheck` clean; dry-read for the wrong-cluster guard; at least one script exercised end-to-end on a lab/kind cluster if available.
- Mock exam: timer starts/stops; solutions page task numbering matches exam page.

## Addendum: beginner/intermediate enrichment (EP0–EP8)

P0–P8 above shipped a complete internals-first curriculum, but it assumes the
reader already knows Linux, networking, and distributed-systems basics — e.g.
`w1.html` opens with "control loops" and static pods with no on-ramp. Feedback:
only already-experienced people can follow the current lessons. Kubernetes
concepts sit on top of more fundamental tech (processes/namespaces, TCP/IP &
DNS, PKI/TLS, consensus, REST/YAML) a beginner may never have met. Goal: teach
those primitives and add plain-language framing, without diluting the
internals-first depth for readers who don't need it.

Decisions made:
- Beginner content lives in **toggle-able panels** (`.foundation` callouts +
  `.analogy` asides), default **on**, via a site-wide `#basics` button next to
  the theme toggle — same localStorage-driven pattern as theme
  (`assets/lesson.js`). Advanced readers hide it once, everywhere; nothing is
  removed, nothing is hidden from newcomers by default.
- Cross-cutting fundamentals get **one standalone page**,
  `materials/foundations.html` ("Week 0.5"), not folded into `w0.html` (which
  stays compact cluster-build logistics). Lessons link into its sections
  instead of re-explaining the same primitive in every week that touches it.

Design and rollout (EP0–EP8) are documented in `CLAUDE.md`'s "Beginner-friendly
conventions" section (the `.foundation`/`.analogy` pattern, jargon-`<abbr>`
convention, and the canonical analogy registry) and the phase roadmap table.
EP0 (infra + `foundations.html` + conventions) is done; EP1–EP8 enrich one
week's lessons per session, in week order, same cadence as the original build.
