# CLAUDE.md — CKA prep site

Dependency-free static site (GitHub Pages) that takes a user from zero to passing the CKA exam: an 8-week checkpoint **tracker** (`index.html`) plus **self-contained lesson pages** per week. No build step, no external requests — plain HTML/CSS/JS only.

The full approved plan is in [`docs/PLAN.md`](docs/PLAN.md). Decisions already made (don't re-ask): fully self-contained lesson depth; all four extras (fault scripts, quizzes, cheat sheets, mock exam); implement one phase per session, in week order.

## Commands

```bash
python3 -m http.server 8000        # serve locally → http://localhost:8000
tools/check-links.sh                # tracker checkpoint <-> lesson anchor bidirectional check (data-id="wN-M" <-> id="cp-N-M")
tools/check-html.py                  # tag-balance check; defaults to index.html + materials/cheatsheets/mock pages, or pass specific files
node --check assets/lesson.js       # syntax-check the shared JS
```

There is no build step, package manager, linter, or test framework beyond the two `tools/` scripts above — run all three (plus a visual spot-check in the browser: theme toggle, done-sync with the tracker, anchors landing right) before considering a phase finished.

## Architecture

- `index.html` is the source of truth for checkpoints: `PUBLISHED` (array of week numbers with a lesson page) and `EXTRAS` (cheat sheets/mock, `{t:'title', href:'...'}`) arrays there drive which 📖 links and sidebar entries render. Adding a week's lesson page requires adding its number to `PUBLISHED`.
- **Anchor scheme**: every tracker checkpoint `<li data-id="wN-M">` in `index.html` must have exactly one matching `<article class="lesson" id="cp-N-M">` in `materials/wN.html`, and vice versa — enforced by `tools/check-links.sh`.
- **Shared client state**, all via `localStorage`, same-origin so it works free on GitHub Pages: `cka-prep-v1` (checkpoint done/undone, read/written by both `index.html` and every lesson page's done-toggle), `cka-theme` (light/dark, `data-theme` attribute), `cka-beginner-v1` (`.foundation`/`.analogy` visibility, `body.basics-off` class). `assets/lesson.js` is what wires lesson pages into all three; `index.html` has its own copies of the tracker/theme logic inline.
- `assets/site.css` is the single stylesheet for every page (tracker, lessons, cheat sheets, mock exam) — includes `@media print` rules cheat sheets depend on to fit one page.
- Lesson pages are otherwise independent static files with no shared templating — conventions below are enforced by convention + the check scripts, not by a build step.

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
| P7 | materials/w7.html (RBAC/auth/speed) + cheatsheets/commands.html | ✅ done |
| P8 | materials/w8.html + mock/ (exam-1, solutions, setup script) + cheatsheets/exam-day.html + final QA + artifact banner update | ✅ done |
| EP0 | ~~Beginner-mode infra: toggleable `.foundation`/`.analogy` panels~~ | ⛔ superseded by R0 |
| EP1 | ~~Enrich W0 + W1 with toggleable `.foundation` callouts (pilot)~~ | ⛔ superseded by R1 |
| R0 | Retire `#basics` toggle infra (lesson.js/site.css/every page header); rewrite `materials/foundations.html`; new conventions below | ✅ done |
| R1 | Rewrite materials/w0.html + w1.html: plain-English-first voice, full depth kept | ✅ done |
| R2 | Rewrite materials/w2.html (kubeadm/PKI/lifecycle) | ✅ done |
| R3 | Rewrite materials/w3.html (workloads/scheduling/Helm/Kustomize) | ✅ done |
| R4 | Rewrite materials/w4.html (networking; heaviest diagrams) | ⬜ next |
| R5 | Rewrite materials/w5.html (storage/CSI) | ⬜ |
| R6 | Rewrite materials/w6.html (troubleshooting) | ⬜ |
| R7 | Rewrite materials/w7.html (RBAC/auth/speed) | ⬜ |
| R8 | Rewrite materials/w8.html + final cross-link/voice-consistency QA over all 9 files | ⬜ |

P0–P8 complete; the site is a full self-contained internals-first curriculum. EP0–EP8 (the toggleable beginner-enrichment pass) is **superseded** — feedback was that bolting optional panels onto otherwise jargon-dense prose wasn't enough; the plan pivoted to rewriting every lesson's core prose in plain English with full depth kept, one unified voice, nothing to toggle (R0–R8, see "Plain-English lesson voice" below and `docs/PLAN.md`'s addendum for the pivot history). R0–R3 are done (R1 also dissolved every `.foundation` callout box in w0/w1 into the main "The concept" prose — those boxes are retired per-week as each gets rewritten, not site-wide; w2/w3 never had any (EP1's pilot only touched w0/w1), and w4–w8 still have them until their own R-phase); R4–R8 rewrite one week's lesson file per session, in order. Note: `shellcheck` was unavailable in the P8 environment — `mock/setup-exam-1.sh` passed `bash -n` and mirrors the (shellchecked) `labs/faults/` patterns, but run shellcheck on it when available.

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
- Voice: plain-English-first, full depth always included — "here's the machinery, here's the failure signature," but walked up to gradually rather than dropped in cold. See "Plain-English lesson voice" below for the per-lesson rewrite recipe (R0–R8). Every lab ends in something checkable. All ~160 lessons should read as one system.

## Plain-English lesson voice (R0–R8)

Supersedes the old EP0–EP8 toggle-based enrichment pass (history + pivot rationale in `docs/PLAN.md`'s EP0–EP8 addendum). Feedback: bolting optional `.foundation` panels onto otherwise jargon-dense prose wasn't enough — readers experienced fully-detailed lessons as if they were terse hints, because the surrounding sentences assumed background they didn't have. Goal now: rewrite the core prose itself so plain language leads and full depth follows, in one voice, for every reader — nothing hidden, nothing to toggle.

Apply this recipe to every `<article class="lesson">` when rewriting a week (R1–R8):

- **Why it matters** — open with one plain-English sentence naming the thing and why a newcomer would care, before the existing exam-relevance framing. Every lesson gets this, not just primitive-heavy ones.
- **The concept** — plain language first, precision second: define each dense term inline in plain words on first use in the lesson (CRI, gRPC, veth, DNAT, quorum, SAN, admission, reconcile loop…) rather than leaving clarity to an `<abbr>` tooltip alone. Reach for **one** analogy from the registry below where it actually clarifies — don't stack metaphors for the same idea. Then deliver the same internals detail the lesson always had, unabridged: depth is never cut for accessibility, only unpacked more gradually. Expand any paragraph or bullet list that currently compresses several ideas into one dense clause into the connected reasoning a beginner needs to follow. Diagrams stay; give each one a one-sentence plain caption if it lacks one.
- **Lab** — keep every command and expected output verbatim (no accuracy regressions); add a short plain sentence before each step saying what it does and why, not just what to type, where that's currently missing.
- **Verify / Gotchas / Docs** — same structure, rewritten so the *why* behind each gotcha is spelled out rather than compressed into a subordinate clause.
- Keep `<abbr title="short plain definition">term</abbr>` on first jargon use per lesson — cheap, still a useful hover reference even though it's no longer the primary clarity mechanism.
- `materials/foundations.html` remains the standalone primer for cross-cutting fundamentals (processes/containers, APIs/declarative, YAML, TCP/IP+DNS, PKI/TLS, consensus/quorum, Linux networking primitives, systemd/static pods) — link into its sections for an optional deeper dive rather than re-deriving a primitive from scratch inside a week's lesson.

**Canonical analogy registry** — reuse these exact metaphors everywhere so they don't collide across weeks; add to this table (don't invent a competing metaphor for something already listed):

| Concept | Analogy |
|---|---|
| apiserver | the front desk / reception |
| etcd | the filing cabinet / ledger |
| controllers / reconcile loop | thermostats, or housekeeping re-checking a posted note |
| scheduler | the seating host at a restaurant |
| pod | a shipping container |
| Service | directory assistance / a phone book entry |
| Ingress | the building receptionist routing calls to the right room |
| CNI / cluster network | the road network between buildings |
| RBAC | a keycard system |
| certificate / CA | a notarized ID card / the notary everyone already trusts |
| network namespace + veth + bridge | a hotel room, its phone wire, and the switchboard connecting rooms |
| systemd + static pods | the building superintendent who keeps the boiler running directly, before the tenant office can open |
| quorum / consensus | a small committee that only needs a strict majority to act |

## Other components (specs in docs/PLAN.md)

- `labs/faults/wN-*.sh` (P6): banner + `read -p` confirm + wrong-cluster guard (check node names/context); plant fault; print mission; **no solution in output** — hints/solutions are 3-stage reveals in w6.html. Must be shellcheck-clean.
- `cheatsheets/*.html` (P2/P6/P7/P8): use `.sheet` body class; must fit one printed page (`@media print` rules exist in site.css; check browser print preview).
- `mock/` (P8): exam-1.html (16 weighted tasks, 120-min JS countdown, no solutions), solutions-1.html (per-task solution + verification + rubric, 66% pass line), setup-exam-1.sh.
- After P8: update the claude.ai tracker artifact once to banner-link the GitHub Pages site (artifact URL in the `cka-exam-prep` memory).
