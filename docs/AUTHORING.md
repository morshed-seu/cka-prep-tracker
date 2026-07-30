# Authoring a module page — the session runbook

One module = one session. Read **this file only**; the long tables in
`CLAUDE.md` and `docs/*-TRACK.md` are reference, not required reading. Written
after I-S8, which did every step below by hand.

## The loop

```bash
# 0. orient (30 seconds)
git log --oneline -5
grep -n "I-S\|B-S" CLAUDE.md | tail -3          # which phase is next
tools/check-links.sh && tools/check-html.py && tools/check-page.py \
  && node --check assets/lesson.js               # green baseline

# 1. read the module's spec section, and nothing else
sed -n '/^## I4 /,/^## I5 /p' docs/INTERMEDIATE-TRACK.md

# 2. scaffold — never hand-write boilerplate
tools/scaffold-module.py i4
#    -> materials/i4.html with one stub per checkpoint, each carrying its
#       checkpoint text and "Under the hood" note as comments

# 3. lab first, prose second (see "Run before you write")
multipass start sandbox
tools/vm.sh clean
tools/vm.sh cap i4-descriptors 'skopeo copy ... && jq . index.json'

# 4. write one checkpoint group, commit, repeat
tools/check-page.py materials/i4.html --anatomy
git commit ...                                   # I-S9a, I-S9b, ...

# 5. publish
tools/publish-module.sh i4

# 6. tick the roadmap rows + memory, commit (docs-only, no line limit)
```

## Run before you write

**Every command and every line of output in a lesson must come from a real
run.** This is the rule that makes the pages worth reading, and each of I1, I2
and I3 corrected several of this repo's own assumptions because of it. Use
`tools/vm.sh cap NAME 'snippet'`, which saves to `labs/captures/NAME.txt`.

Equally: **verify version-sensitive facts by web search or by fetching the spec
text, never from memory.** Quote specs verbatim — fetch the raw file from the
tagged URL (`.../runtime-spec/v1.3.0/config.md`), do not paraphrase into a
`<blockquote>`. I-S8 caught two paraphrased "quotes" this way before they
shipped.

## The VM

Labs run on the Multipass VM **`sandbox`** (`CKA_VM` overrides). It carries the
whole intermediate toolchain. **Ask the user before provisioning a second or
third VM** — standing instruction.

`tools/vm.sh` exists because three traps waste calls otherwise:

| trap | symptom | handled by |
|---|---|---|
| a container outlives the command and inherits its stdout | `multipass exec` blocks for the full timeout | `vm.sh run` detaches under `setsid`, output to a file |
| `multipass transfer` is snap-confined | cannot read `/tmp/claude-*` | `vm.sh put` pipes through `exec ... cat >` |
| `strace -f runc create` never returns | looks like a hung runtime | `timeout`, and `CKA_VM_TIMEOUT` |

Two more, learned the hard way and worth never repeating:

- **`pkill -f <pattern>` matches its own command line.** `sudo pkill -f foo.py`
  kills the `sudo` wrapper; run inside a Bash tool call it can kill the session
  shell (exit 144). Use the bracket trick: `pkill -f '[f]oo\.py'`.
- **Scratch files go in `~`, not `/tmp`.** `/tmp` is sticky, so a root-owned
  file left by a `sudo`ing snippet cannot be unlinked by the next run.
- **No nested quoted heredoc inside a snippet.** A `python3 - <<'PY'` block
  inside the snippet is re-parsed by the outer shell and dies on the first `(`.
  Generate the file with a shell loop, or `vm.sh put` it.
- **A `jq` program containing `$vars` must be a file**, read with `jq -f`. Inline
  in double quotes, the VM-side shell expands `$s` to nothing and you get
  `Cannot index number with object`.
- **A build or install can outlive `CKA_VM_TIMEOUT` with no output at all.** The
  capture file is then written empty and `vm.sh` exits 1 — that is a timeout,
  not a silent success. Anything emulated (I6.7) or `apt`/`apk`-heavy wants
  `run_in_background` plus a generous timeout, and a recursive `grep -r /` inside
  a container will eat the whole budget on its own.

## Commit discipline

- **≤500 added lines per commit touching code** (global rule; HTML counts).
  A module page is 5–7 commits, split on checkpoint-group boundaries:
  `I-S9a`, `I-S9b`, … Docs-only commits are exempt.
- The checkers stay **red mid-module** — `check-links.sh` reports the
  not-yet-written anchors. That is expected; say so in the commit message.
  They go green at `publish-module.sh`.
- Commit messages carry **what the live run corrected**, not just what was
  written. That record is the reason later modules are accurate.

## What the checkers cover

| script | catches |
|---|---|
| `check-links.sh` | tracker checkpoint ↔ lesson anchor, both directions, all three tracks |
| `check-html.py` | tag balance |
| `check-page.py` | raw `<word>` in `<pre>` (which `check-html.py` cannot see), `&`-as-entity, broken links, dangling deep anchors, `lesson.js` wiring, un-captured output |
| `check-page.py --anatomy` | advisory: per-lesson block structure, quiz size |
| `node --check assets/lesson.js` | JS syntax |

`check-page.py` is tuned to **zero false positives** on the existing site. If it
fires, it is real — do not "fix" it by loosening the check.

## Conventions that bite

- Anchor id = `cp-` + `data-id` with a leading `w` stripped. The scaffolder gets
  this right; hand-editing does not.
- Tables are `<table class="langpair"><thead>…<tbody>`. There is **no `.tbl`**.
- Escape `<`, `>`, `&` inside every code block. A raw `<word>` is eaten silently.
- Cross-track links: **check the target's heading, not just that the anchor
  exists.** Six of I2's 18 links pointed at real anchors about the wrong
  subject. `grep -o 'id="cp-[^"]*"' materials/w6.html` then read the `<h4>`s.
- Every intermediate conceptual lesson needs **both** a `.specref` and a
  `.k8s-link`, plus an inline back-reference to the beginner lesson that built
  the primitive by hand. (I0 and I1 are exempt from `.specref`.)
- Reuse the analogy registry in `CLAUDE.md`; never invent a competing metaphor.

## Known gaps, carried forward

- `materials/b14.html` has the `capsh`-before-`unshare` bug that
  `labs/intermediate/seed/minibox.sh` had fixed in I-S5. Fixing it is a
  beginner-track session.
- `shellcheck` is unavailable in this environment; shell labs get `bash -n`.
- The advanced track has **no** `securityContext`, Pod Security Standards,
  dockershim-removal or `RuntimeClass` lesson. Say so and link what exists
  rather than inventing an anchor.
