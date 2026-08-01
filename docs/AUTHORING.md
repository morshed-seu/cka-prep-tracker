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
- **`sudo` does not extend to redirects or globs — the unprivileged shell
  evaluates those first.** `sudo tr -d x < /root/file` is *permission denied*,
  and `sudo rm /etc/cni/net.d/00-*` on a mode-0700 directory silently deletes
  nothing because the pattern never expands. Wrap the whole thing:
  `sudo sh -c 'rm -f /etc/cni/net.d/00-*'`. This cost three separate rounds in
  I-S14 and each time the symptom looked like the *lab* being wrong.
- **A daemon started with `ctr run -d` and no `--log-uri` will block on write.**
  Its stdout is the shim's `log` FIFO (I-S12), which nobody drains, so once
  ~64 KB accumulates the process stops — while still holding its listening
  socket. In I-S16 the `registry:2` container did this twice: it accepted TCP
  connections and answered nothing, and once left `:5000` held by a stray
  `sleep` with the registry itself dead. Symptoms look like a hung network.
  Always pass `--log-uri file:///var/log/<name>.log`.
- **A rootfs unpacked with `sudo tar` cannot be removed without `sudo`.**
  A scratch-directory reset written as plain `rm -rf` produces sixty lines of
  *Permission denied* before the interesting part of the script runs.
- **`vm.sh put` single-quotes its destination, so `~` does not expand.**
  `tools/vm.sh put x.sh '~/x.sh'` creates a file literally named `~/x.sh` in
  the home directory and the next `bash ~/x.sh` fails with *No such file or
  directory*. Always pass an absolute path: `/home/ubuntu/x.sh`.
- **`sandbox` runs two containerds since I-S16** — the system daemon and the
  rootless stack — so `pgrep -x containerd | head -1` silently picks whichever
  started first and every fd lookup against it comes back empty. Use
  `systemctl show containerd -p MainPID --value`. In I-S17 this produced a
  capture claiming containerd held no descriptor on its own log file.
- **Never run two `tools/vm.sh` calls concurrently.** They share
  `~/.vmrun/run.sh` and `~/.vmrun/out`, so a backgrounded capture and a
  foreground one interleave and each reads the other's output. Serialise them.
- **Anything non-trivial belongs in a file, not a snippet.** Once a lab needs
  quoting inside quoting, write it locally, `vm.sh put` it, and
  `vm.sh cap NAME 'bash ~/x.sh'`. In I-S14 an escaped `\"` inside a snippet made
  `grep` search for literal quote characters and produced a plausible-looking
  wrong answer — the worst possible failure mode for a captured lab.

## Commit discipline

- **≤500 added lines per commit touching code** (global rule; HTML counts).
  Plan **~2 lessons per commit**, not one checkpoint group: a group of four
  lessons runs ~600 lines. Docs-only commits are exempt; so are
  `labs/captures/` transcripts, which get one commit of their own at the end.
- **A new file counts entirely as added lines**, so a freshly scaffolded page
  busts the limit on its own (733 lines for a 16-checkpoint module). Never
  commit the bare scaffold. Instead grow the page from the scratchpad with
  unwritten articles **omitted** rather than stubbed — emit a group wrapper only
  when that group has a written lesson, and keep head/quiz/footer from the final
  file, so every intermediate state is valid HTML and the last one is
  byte-identical to what you reviewed. `diff` it before committing.
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

One near-exception worth knowing, met in I-S14: quoting Go source that contains
`context.TODO()` trips both the un-captured-output check *and*
`publish-module.sh`'s TODO gate. The answer is still not to loosen either one —
move the line out of `<pre class="out">` (it is source, not output) and mark the
argument as an explicit `[…]` elision rather than silently rewording a quote.

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
