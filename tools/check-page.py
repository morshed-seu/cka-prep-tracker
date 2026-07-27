#!/usr/bin/env python3
"""Lesson-page QA that check-html.py and check-links.sh do not cover.

Usage: tools/check-page.py [--anatomy] [files...]   (defaults to materials/*.html)

Gate checks (FAIL, exit 1) — each of these was run by hand before this existed:

  1. escaping   a raw "<word>" inside <pre>. The browser eats it silently and
                check-html.py does NOT catch it (CLAUDE.md warns about this).
                A bare ">" and "<" before a space/digit are legal and ignored.
  2. amp        an "&" that a lenient parser may read as a named entity
                (&copy, &lt without the semicolon). "&&" is fine and ignored.
  3. links      every internal href resolves to a file that exists.
  4. anchors    every deep link (page.html#cp-...) exists in its target file.
  5. wiring     on pages with doneboxes: the ids assets/lesson.js needs, one
                donebox per lesson, and a pager.
  8. captures   a placeholder left inside <pre class="out">, i.e. output that
                was never actually captured from a run.

Advisory checks (WARN, never fail the build), only with --anatomy:

  6. blocks     each conceptual lesson has Why/concept/Lab/Verify/Gotchas,
                docs-links, a .k8s-link, and on i*.html a .specref.
  7. quiz       a #quiz block with at least 8 reveals.

These two are off by default because they have legitimate exceptions: compact
logistics lessons have no Lab, project/drill lessons have no Docs, and I0/I1
are explicitly permitted to omit .specref. Use --anatomy while drafting.
"""
import sys, glob, os, re

REQUIRED_IDS = ['theme', 'ring', 'pct', 'nav', 'done-count', 'matwrap']
# Deliberately NOT 'XXX': real captured output contains mktemp paths like
# /tmp/ssh-XXXX2kPq/ and redacted keys, and flagging those trains you to ignore
# this check. Matched as whole words.
PLACEHOLDERS = ['TODO', 'FIXME', 'PASTE', 'paste output', 'output here']

fail = False
def bad(f, msg):
    global fail
    print(f"FAIL {f}: {msg}")
    fail = True
def warn(f, msg):
    print(f"WARN {f}: {msg}")

def strip_inline(s):
    return re.sub(r'</?(b|i|em|strong|abbr[^>]*)>', '', s)

def check(path):
    src = open(path).read()
    base = os.path.basename(path)
    d = os.path.dirname(path) or '.'

    # 1. raw "<word>" inside <pre>. Only a '<' followed by a letter or '/' can be
    #    eaten as a tag; a bare '>' and a '<' before a space or digit are legal
    #    character data and are used deliberately all over the site ("a -> b",
    #    "if x < 3"). Flagging those produces noise nobody reads.
    # Comments are not rendered, so scan the comment-free text. And require a
    # word boundary after "pre": prose like "<previous chain ID>" otherwise
    # matches <pre[^>]*> and swallows the rest of the page.
    visible = re.sub(r'<!--.*?-->', '', src, flags=re.S)
    for m in re.finditer(r'<pre(?:\s[^>]*)?>(.*?)</pre>', visible, re.S):
        body = strip_inline(m.group(1))
        for hit in re.finditer(r'<[a-zA-Z/][a-zA-Z0-9/]*[\s>]', body):
            line = visible[:m.start()].count('\n') + 1
            bad(path, f"raw <tag> in <pre> near line {line}: {hit.group(0)!r} "
                      f"— the browser will eat this; escape to &lt;")

    # 2. an & that could be read as a named entity without its semicolon
    #    (&copy, &lt, &amp all render as characters in a lenient parser).
    #    "&&", "& ", "&1" are harmless and are used in every shell snippet.
    nocomment = re.sub(r'<!--.*?-->', '', src, flags=re.S)
    for m in re.finditer(r'&[a-zA-Z]{2,}(?![a-zA-Z0-9]*;)', nocomment):
        line = nocomment[:m.start()].count('\n') + 1
        bad(path, f"& that may parse as an entity at line ~{line}: {m.group(0)!r}")

    # 3 + 4. internal links and deep anchors
    for href in sorted(set(re.findall(r'href="([^"]+)"', src))):
        if href.startswith(('http://', 'https://', 'mailto:', 'data:', '#')):
            continue
        target, _, frag = href.partition('#')
        if not target:
            continue
        tpath = os.path.normpath(os.path.join(d, target))
        if not os.path.isfile(tpath):
            bad(path, f"broken link -> {href}")
            continue
        if frag:
            if f'id="{frag}"' not in open(tpath).read():
                bad(path, f"dangling anchor -> {href} (no id=\"{frag}\" in {tpath})")

    # 5. wiring assets/lesson.js depends on — only for tracked lesson pages.
    #    materials/foundations.html is a standalone primer with no checkpoints
    #    and legitimately has no progress ring.
    lessons = re.findall(r'<article class="lesson[^"]*" id="(cp-[^"]+)"', src)
    doneboxes = src.count('class="donebox"')
    if doneboxes:
        for i in REQUIRED_IDS:
            if f'id="{i}"' not in src:
                bad(path, f'missing id="{i}" (lesson.js needs it)')
    if lessons and doneboxes != len(lessons):
        bad(path, f"{len(lessons)} lessons but {doneboxes} doneboxes")
    if '<nav class="pager">' not in src:
        bad(path, "no <nav class=\"pager\">")
    if '<footer>' not in src:
        warn(path, "no <footer> version line")

    # 6 + 7. Per-lesson anatomy and quiz size. Advisory only, and OFF by default:
    # compact logistics lessons legitimately have no Lab, project/drill lessons
    # have no Docs, and I0/I1 are explicitly permitted to omit .specref. Run with
    # --anatomy while drafting a page, not as a gate.
    if ANATOMY:
        intermediate = bool(re.match(r'i\d+\.html$', base))
        for cls, aid in re.findall(r'<article class="lesson([^"]*)" id="(cp-[^"]+)"', src):
            body = re.search(rf'<article class="lesson[^"]*" id="{re.escape(aid)}".*?</article>',
                             src, re.S).group(0)
            if 'project' in cls or 'drill' in cls:
                continue
            for h in ['Why it matters', 'The concept', 'Lab', 'Verify', 'Gotchas']:
                if h not in body:
                    warn(path, f"{aid}: no '{h}' heading")
            if 'class="docs-links"' not in body:
                warn(path, f"{aid}: no docs-links")
            if 'class="k8s-link"' not in body:
                warn(path, f"{aid}: no .k8s-link")
            if intermediate and 'class="specref"' not in body:
                warn(path, f"{aid}: no .specref (mandatory from I2 on)")
        if lessons and 'id="quiz"' not in src:
            warn(path, "no quiz block")
        elif lessons:
            n = len(re.findall(r'<details class="reveal">', src))
            if n < 8:
                warn(path, f"only {n} reveals on the page (quiz wants 8+)")

    # 8. un-run output
    for m in re.finditer(r'<pre class="out">(.*?)</pre>', src, re.S):
        for p in PLACEHOLDERS:
            if re.search(rf'\b{re.escape(p)}\b', m.group(1)):
                line = src[:m.start()].count('\n') + 1
                bad(path, f"placeholder {p!r} in <pre class=\"out\"> at line {line} — output was never captured")

    print(f"ok   {path}: {len(lessons)} lessons, "
          f"{len(set(re.findall(chr(104)+'ref=\"([^\"]+)\"', src)))} unique hrefs checked")

args = [a for a in sys.argv[1:] if not a.startswith('--')]
ANATOMY = '--anatomy' in sys.argv
files = args or sorted(glob.glob('materials/*.html'))
for f in files:
    check(f)
sys.exit(1 if fail else 0)
