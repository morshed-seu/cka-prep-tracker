# CLAUDE.md — CKA prep site

Dependency-free static site (GitHub Pages) that takes a user from zero to passing the CKA exam: an 8-week checkpoint **tracker** (`index.html`) plus **self-contained lesson pages** per week. No build step, no external requests — plain HTML/CSS/JS only.

The full approved plan is in [`docs/PLAN.md`](docs/PLAN.md). Decisions already made (don't re-ask): fully self-contained lesson depth; all four extras (fault scripts, quizzes, cheat sheets, mock exam); implement one phase per session, in week order.

## Phase roadmap (update this table at the end of each phase)

| Phase | Scope | Status |
|---|---|---|
| P0 | Scaffolding: site.css, lesson.js, 📖 links, check scripts | ✅ done (`5877d46`) |
| P1 | materials/w0.html + w1.html | ✅ done (`02c3276`) |
| P2 | materials/w2.html (kubeadm/PKI/lifecycle) + cheatsheets/etcd-card.html | ✅ done |
| P3 | materials/w3.html (workloads/scheduling/Helm/Kustomize) | ✅ done |
| P4 | materials/w4.html (networking; heaviest diagrams) | ✅ done |
| P5 | materials/w5.html (storage/CSI) | ✅ done |
| P6 | materials/w6.html + labs/faults/*.sh + cheatsheets/triage-template.html | ✅ done |
| P7 | materials/w7.html (RBAC/auth/speed) + cheatsheets/commands.html | ⬜ next |
| P8 | materials/w8.html + mock/ (exam-1, solutions, setup script) + cheatsheets/exam-day.html + final QA + artifact banner update | ⬜ |

## Phase workflow

1. Read `docs/PLAN.md` (per-week content inventory) and skim the target week's checkpoints in `index.html` (`<section id="wN">`) — every lesson expands one checkpoint, absorbing its "Under the hood" note.
2. **Verify version-sensitive facts via web search while authoring** — never from memory. Known: exam runs **Kubernetes v1.35** (checked 2026-07-10, LF CKA page); re-check each session. Page footers state the authored-against version.
3. Write `materials/wN.html` following the conventions below (copy the page skeleton from `materials/w0.html`).
4. Publish: add N to the `PUBLISHED` array in `index.html` (this injects 📖 links + sidebar entry). Cheat sheets/mock go in the `EXTRAS` array (`{t:'title', href:'...'}`). Also add the new page to the static "Site" list in each `materials/*.html` sidebar.
5. Verify: `tools/check-links.sh` && `tools/check-html.py` && `node --check assets/lesson.js`; serve with `python3 -m http.server` and spot-check pages (theme toggle, done-sync with tracker, anchors land right).
6. One commit per phase; end message with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`. Update the roadmap table above and the `cka-materials-plan` memory file in the same commit/session.

## Lesson page conventions

- One page per week: `materials/wN.html`. One `<article class="lesson" id="cp-N-M" data-id="wN-M">` per tracker checkpoint `data-id="wN-M"` — ids must match bidirectionally (`tools/check-links.sh` enforces).
- Lesson anatomy, in order (h5 headings): **Why it matters** → **The concept** (internals; absorb + expand the tracker's "Under the hood") → **Lab** (`<ol class="lab">`, commands in `<pre class="cmd">`, abridged output in `<pre class="out">` with load-bearing lines in `<b>`) → **Verify** (`<h5 class="verify">`) → **Gotchas** (`<h5 class="gotcha">`) → **Docs** (`<p class="docs-links">`, framed as "what to search in the exam docs"). Logistics-only checkpoints use a compact variant (Why + Steps + Gotchas).
- Each lesson head has the done-toggle: `<label class="donebox"><input type="checkbox"><span class="box"></span>done</label>` — `assets/lesson.js` syncs it with the tracker via localStorage key `cka-prep-v1` (key = the `data-id`).
- End of page: `<div class="quiz" id="quiz">` with 8–12 `<details class="reveal">` questions, then `<nav class="pager">` (prev/next), then `<footer>` with the version line.
- Diagrams: inline SVG using CSS vars (`var(--ink)`, `var(--line)`, `var(--accent)`, `var(--code-bg)`, `var(--muted)`) so both themes work; pipeline-style flows use `<div class="flow"><span>…</span><em>→</em>…</div>`.
- Escape `<`, `>`, `&` inside all code blocks (`&lt;` etc.) — the checker catches breakage but not silent text loss; grep for suspicious raw `<word>` patterns after authoring.
- Labs run against the week-0 lab: 3 Ubuntu 24.04 Multipass VMs named `cp`, `node01`, `node02`, kubeadm + containerd + Flannel (`10.244.0.0/16`).
- Voice: plain, direct, internals-first ("here's the machinery, here's the failure signature"); every lab ends in something checkable. All ~160 lessons should read as one system.

## Other components (specs in docs/PLAN.md)

- `labs/faults/wN-*.sh` (P6): banner + `read -p` confirm + wrong-cluster guard (check node names/context); plant fault; print mission; **no solution in output** — hints/solutions are 3-stage reveals in w6.html. Must be shellcheck-clean.
- `cheatsheets/*.html` (P2/P6/P7/P8): use `.sheet` body class; must fit one printed page (`@media print` rules exist in site.css; check browser print preview).
- `mock/` (P8): exam-1.html (16 weighted tasks, 120-min JS countdown, no solutions), solutions-1.html (per-task solution + verification + rubric, 66% pass line), setup-exam-1.sh.
- After P8: update the claude.ai tracker artifact once to banner-link the GitHub Pages site (artifact URL in the `cka-exam-prep` memory).
