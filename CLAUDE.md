# CLAUDE.md — CKA prep site

Dependency-free static site (GitHub Pages) that takes a user from zero to passing the CKA exam. No build step, no external requests — plain HTML/CSS/JS only. It is growing into a **three-track journey**:

| Track | Tracker | Lessons | Plan | Status |
|---|---|---|---|---|
| **Beginner** — the Linux/networking/distributed-systems machinery Kubernetes is built from | `beginner.html` | `materials/b0…b14.html` | [`docs/BEGINNER-TRACK.md`](docs/BEGINNER-TRACK.md) | in progress (B-S1…B-S19) |
| **Intermediate** — composing that machinery into containers, runtimes, images, CNI | `intermediate.html` | — | — | future |
| **Advanced** — Kubernetes itself, through the CKA | `index.html` | `materials/w0…w8.html` | [`docs/PLAN.md`](docs/PLAN.md) | ✅ complete |

Decisions already made (don't re-ask): fully self-contained lesson depth; all four extras (fault scripts, quizzes, cheat sheets, mock exam); implement one phase per session, in track/week order.

## Commands

```bash
python3 -m http.server 8000        # serve locally → http://localhost:8000
tools/check-links.sh                # both tracks: tracker checkpoint <-> lesson anchor bidirectional check
                                    #   index.html    data-id="wN-M" <-> materials/wN.html  id="cp-N-M"
                                    #   beginner.html data-id="bN-M" <-> materials/bN.html  id="cp-bN-M"
tools/check-html.py                  # tag-balance check; defaults to every root tracker (index/beginner) + materials/cheatsheets/mock, or pass specific files
node --check assets/lesson.js       # syntax-check the shared JS
```

There is no build step, package manager, linter, or test framework beyond the two `tools/` scripts above — run all three (plus a visual spot-check in the browser: theme toggle, done-sync with the tracker, anchors landing right) before considering a phase finished.

## Architecture

- **Two trackers, same shape**: `index.html` (CKA weeks) and `beginner.html` (B-modules) are each the source of truth for their own checkpoints. Each carries its own inline `PUBLISHED` array (module/week numbers that have a lesson page) and `EXTRAS` array (`{t:'title', href:'...'}`), which drive the `lesson` links and sidebar entries. Publishing a lesson page = adding its number to that tracker's `PUBLISHED`.
- **Anchor scheme**, one rule for both tracks — **anchor id = `cp-` + data-id with a leading `w` stripped**: `index.html`'s `<li data-id="wN-M">` ↔ `materials/wN.html`'s `<article class="lesson" id="cp-N-M">`, and `beginner.html`'s `<li data-id="bN-M">` ↔ `materials/bN.html`'s `id="cp-bN-M"`. Bidirectional, enforced by `tools/check-links.sh`.
- **Shared client state**, all via `localStorage`, same-origin so it works free on GitHub Pages: `cka-prep-v1` (checkpoint done/undone — **one key for both tracks**, ids namespaced by the `b` prefix, so cross-track sync is free and each tracker's reset button filters to its own prefix), `cka-theme` (light/dark, `data-theme` attribute), `cka-collapsed-v1` / `cka-grp-collapsed-v1` (section + group collapse). `assets/lesson.js` wires every lesson page into these; the two trackers have their own copies of the tracker/theme logic inline.
- `assets/site.css` is the single stylesheet for every page (both trackers, lessons, cheat sheets, mock exam) — includes `@media print` rules cheat sheets depend on to fit one page. Beginner-track blocks (`.tracks .objectives .prereq .outcome .lesson.project .lesson.drill .k8s-link .langpair .modlist .godeep`) live at the end; the box headings are CSS `::before` content, so authors write `<div class="k8s-link">` and get the mandatory heading for free.
- The **three-pill track switcher** (`.tracks`) sits in every sidebar directly after `.brand-row`, with `class="on"` on the current track and Intermediate as an inert `<span>`. Root pages link `beginner.html`/`index.html`; pages in `materials/`, `cheatsheets/`, `mock/` prefix `../`. Per-page "Site" lists are *not* merged across tracks — the switcher is the only crossing point.
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
| R4 | Rewrite materials/w4.html (networking; heaviest diagrams) | ✅ done |
| R5 | Rewrite materials/w5.html (storage/CSI) | ✅ done |
| R6 | Rewrite materials/w6.html (troubleshooting) | ✅ done |
| R7 | Rewrite materials/w7.html (RBAC/auth/speed) | ✅ done |
| R8 | Rewrite materials/w8.html + final cross-link/voice-consistency QA over all 9 files | ✅ done |

P0–P8 complete; the site is a full self-contained internals-first curriculum. EP0–EP8 (the toggleable beginner-enrichment pass) is **superseded** — feedback was that bolting optional panels onto otherwise jargon-dense prose wasn't enough; the plan pivoted to rewriting every lesson's core prose in plain English with full depth kept, one unified voice, nothing to toggle (R0–R8, see "Plain-English lesson voice" below and `docs/PLAN.md`'s addendum for the pivot history). R0–R8 are done per the table above (R1 dissolved every `.foundation` callout box in w0/w1 into the main "The concept" prose — EP1's pilot only ever touched w0/w1, so w2–w8 never had any `.foundation`/`.analogy` boxes to begin with) — phases haven't always landed strictly in order when sessions ran in parallel, so check each week's own status above rather than assuming, and check `git log --oneline` for what's actually committed vs. just marked done on disk. Note: `shellcheck` was unavailable in the P8 environment — `mock/setup-exam-1.sh` passed `bash -n` and mirrors the (shellchecked) `labs/faults/` patterns, but run shellcheck on it when available.

## Beginner-track roadmap (update this table at the end of each session)

Full spec: [`docs/BEGINNER-TRACK.md`](docs/BEGINNER-TRACK.md) — 15 modules (B0–B14), **225 checkpoints**, ~74 hours, self-paced. (225, not the spec's original ~200: each module's mini project and debugging drill are their own tickable checkpoint in a trailing "Project & drill" group, because the module anatomy makes each its own lesson article and `check-links.sh` demands one tracker checkpoint per anchor. So a module's total = its spec group counts + 2; B0 has no drill, +1; B14's groups already are its capstone/gauntlet, +0. `docs/BEGINNER-TRACK.md`'s per-module tables carry the corrected totals.) **Every phase below is sized to one session, start to finish**: it ends with green checkers, a commit, and a site that renders with nothing half-written. No session depends on another session's in-memory context.

| Phase | Scope | Status |
|---|---|---|
| B-S1 | `docs/BEGINNER-TRACK.md` — curriculum spec (docs-only commit) | ✅ done |
| B-S2 | Wiring, no content: `site.css` additions; generalize `check-links.sh`/`check-html.py`; track switcher into every sidebar; `index.html` hero + prefix-scoped reset; `foundations.html` banner + go-deep links; stub `beginner.html` (`PUBLISHED=[]`) | ✅ done |
| B-S3 | `beginner.html` sections B0–B7 (119 checkpoints) | ✅ done |
| B-S4 | `beginner.html` sections B8–B14 (106 checkpoints) + hours panel | ✅ done |
| B-S5 | `materials/b0.html` — **pattern-setter** (lesson anatomy, `k8s-link`, `langpair`, project/outcome blocks); review before continuing | ✅ done |
| B-S6 | `materials/b1.html` — shell, files, filesystem tree (16 cp) | ✅ done |
| B-S7 | `materials/b2.html` — processes, threads, signals (18 cp) | ✅ done |
| B-S8 | `materials/b3.html` — kernel space, user space, system calls (14 cp) | ✅ done |
| B-S9 | `materials/b4.html` — users, groups, permissions, capabilities (15 cp) | ✅ done |
| B-S10 | `materials/b5.html` — files, VFS, storage, overlayfs (18 cp) | ✅ done |
| B-S11 | `materials/b6.html` — namespaces, chroot, pivot_root (15 cp) | ✅ done |
| B-S12…B-S18 | `materials/b7.html` … `materials/b13.html`, one module per session | ⬜ next (B-S12 = `b7.html`) |
| B-S19 | `materials/b14.html` + `labs/beginner/*.sh` + `mock/beginner-final*.html` + cross-track QA | ⬜ |

**Resume recipe for any beginner-track session:** read this table → read the target module's section in `docs/BEGINNER-TRACK.md` → `git log --oneline -8` (what actually landed, vs. just marked done) → run the three checkers for a green baseline → do the work → checkers → commit → tick the row here and update the `cka-materials-plan` memory.

Beginner specifics that differ from the CKA workflow below: anchors are `data-id="bN-M"` ↔ `id="cp-bN-M"` (one rule covers both tracks: **anchor = `cp-` + data-id with a leading `w` stripped**); labs run on a single throwaway Multipass VM named `sandbox` (Ubuntu 24.04), never on the `cp`/`node01`/`node02` cluster; every conceptual lesson ends with a mandatory **"Where this shows up in Kubernetes"** (`.k8s-link`) block deep-linking the advanced lesson anchor; **Docs** links point at `man` pages and kernel docs, not kubernetes.io.

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
| PV / PVC / StorageClass | a self-storage facility: a PV is a physical unit already built on the lot, a PVC is a reservation ticket for a unit of some size, a StorageClass is a standing order telling the facility "build a new unit to this spec whenever no existing unit matches a ticket" |

**Beginner-track extension.** The existing hotel metaphor is promoted into the beginner track's spine: **one hotel = one Linux machine; the city of buildings = the cluster.** Same rule — reuse these exact metaphors, don't invent competing ones.

| Concept | Analogy |
|---|---|
| kernel / user space | the hotel's engineering staff, who alone touch the wiring; guests must file a work order |
| system call | that work-order form — the only way a guest reaches engineering |
| process | a guest staying in the hotel; the PID is their room number |
| signal | a knock on the door with a standard meaning; SIGKILL is security removing them, no conversation |
| mount namespace | the room's own closet — same building, different contents |
| PID namespace | the room's own guest list: they can't see who else is in the hotel |
| cgroup | the room's metered power and water, with a cap the front desk sets |
| capabilities | a keyring of individually-issued permits; root is the master key |
| overlayfs layers | a stack of transparent sheets — you write on the top one, you read through the whole stack |
| DNS resolver | the hotel operator who looks a name up before dialing |
| conntrack | the switchboard's log of calls currently in progress |

## Other components (specs in docs/PLAN.md)

- `labs/faults/wN-*.sh` (P6): banner + `read -p` confirm + wrong-cluster guard (check node names/context); plant fault; print mission; **no solution in output** — hints/solutions are 3-stage reveals in w6.html. Must be shellcheck-clean.
- `cheatsheets/*.html` (P2/P6/P7/P8): use `.sheet` body class; must fit one printed page (`@media print` rules exist in site.css; check browser print preview).
- `mock/` (P8): exam-1.html (16 weighted tasks, 120-min JS countdown, no solutions), solutions-1.html (per-task solution + verification + rubric, 66% pass line), setup-exam-1.sh.
- After P8: update the claude.ai tracker artifact once to banner-link the GitHub Pages site (artifact URL in the `cka-exam-prep` memory).
