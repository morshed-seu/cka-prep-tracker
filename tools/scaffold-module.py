#!/usr/bin/env python3
"""Generate a lesson page's skeleton from its tracker section.

Usage: tools/scaffold-module.py i4 [--force]

Reads the module's <section> out of the right tracker, and writes
materials/i4.html containing every part of a lesson page that is mechanical:
head, sidebar, track pills, progress ring, Site list, hero, objectives and
prereq stubs, one <article> per checkpoint in the right group with the right
ids, the quiz/outcome/pager/footer tail.

Each lesson stub carries, as HTML comments, the checkpoint's own text and its
"Under the hood" note — the two things CLAUDE.md says the lesson must absorb
and expand. So a session writes prose only, and never retypes boilerplate or
risks an id typo.

The output deliberately does NOT validate: it has TODO placeholders that
tools/check-page.py fails on, so a half-written page can never be published
by accident.
"""
import sys, os, re, html

TRACKS = {
    'w': ('index.html',        'Advanced · CKA',          'index.html'),
    'b': ('beginner.html',     'Beginner · Foundations',  'beginner.html'),
    'i': ('intermediate.html', 'Intermediate · Contracts','intermediate.html'),
}
PILLS = [
    ('b', '../beginner.html',     'Beginner',     'The machine under Kubernetes'),
    ('i', '../intermediate.html', 'Intermediate', 'Containers &amp; runtimes'),
    ('w', '../index.html',        'Advanced',     'Kubernetes, through the CKA'),
]

def die(m):
    print(f"scaffold-module: {m}", file=sys.stderr); sys.exit(1)

def text_of(s):
    """Tracker markup -> readable one-liner."""
    s = re.sub(r'<[^>]+>', '', s)
    return re.sub(r'\s+', ' ', html.unescape(s)).strip()

def comment_safe(s):
    """text_of output -> safe inside an HTML comment.

    Checkpoint prose is full of placeholders like <digest> and <previous chain
    ID>. Unescaped they are fragile (and "<previous..." even matches a <pre>
    regex), and a literal "--" would terminate the comment early.
    """
    return (s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
             .replace('--', '&#45;&#45;'))

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    force = '--force' in sys.argv
    if len(args) != 1 or not re.fullmatch(r'[wbi]\d+', args[0]):
        die("usage: scaffold-module.py <module>   e.g. i4, b7, w3")
    mod = args[0]
    pfx, num = mod[0], int(mod[1:])
    tracker, brand, _ = TRACKS[pfx]
    out = f"materials/{mod}.html"
    if os.path.exists(out) and not force:
        die(f"{out} already exists (use --force to overwrite)")

    src = open(tracker).read()
    m = re.search(rf'<section class="wk" id="{mod}"(.*?)</section>', src, re.S)
    if not m:
        die(f'no <section id="{mod}"> in {tracker}')
    sec = m.group(0)

    title = re.search(r'<h2>(.*?)</h2>', sec)
    title = text_of(title.group(1)) if title else mod.upper()
    hours = re.search(r'data-hours="([^"]+)"', sec)
    hours = hours.group(1) if hours else '?'
    goal = re.search(r'<p class="wk-goal">(.*?)</p>', sec, re.S)
    goal = goal.group(1).strip() if goal else 'TODO one-paragraph hook.'
    pre = re.search(r'<div class="prereq"><p>(.*?)</p>', sec, re.S)
    pre = pre.group(1).strip() if pre else 'TODO prerequisites.'

    # groups, in document order, each with its checkpoints
    groups, cps_seen = [], 0
    for g in re.finditer(r'<div class="grp"><h3>(.*?)</h3>(.*?)(?=<div class="grp">|\Z)', sec, re.S):
        gname = text_of(g.group(1))
        cps = []
        for c in re.finditer(
                rf'<li class="cp" data-id="({mod}-\d+)">(.*?)(?=<li class="cp"|</ul>)', g.group(2), re.S):
            did = c.group(1)
            body = c.group(2)
            label = re.search(r'<span class="txt">(.*?)</span></label>', body, re.S)
            label = text_of(label.group(1)) if label else ''
            label = re.sub(rf'^{mod.upper().replace(mod[0].upper(), mod[0].upper())}\S*\s*', '', label)
            hood = re.search(r'<summary>Under the hood</summary>(.*?)</details>', body, re.S)
            hood = text_of(hood.group(1)) if hood else ''
            cps.append((did, label, hood))
            cps_seen += 1
        if cps:
            groups.append((gname, cps))
    if not cps_seen:
        die(f"parsed no checkpoints out of {tracker}#{mod} — has the tracker markup changed?")

    # published siblings, for the Site list and the pager
    pub = re.search(r'var PUBLISHED=\[([^\]]*)\]', src)
    pub = sorted(int(x) for x in re.findall(r'\d+', pub.group(1))) if pub else []
    sibs = pub + ([num] if num not in pub else [])
    site = '\n'.join(
        f'    <li><a href="{pfx}{n}.html">{pfx.upper()}{n} · TODO short title</a></li>'
        if n == num else
        f'    <li><a href="{pfx}{n}.html">{title_of(pfx, n)}</a></li>'
        for n in sorted(sibs))
    prev = max([n for n in pub if n < num], default=None)
    prev_a = (f'<a href="{pfx}{prev}.html">← {title_of(pfx, prev)}</a>'
              if prev is not None else f'<a href="../{tracker}">← Back to the tracker</a>')

    pills = '\n'.join(
        f'    <a{" class=\"on\"" if p == pfx else ""} href="{href}">{name}<em>{sub}</em></a>'
        for p, href, name, sub in PILLS)

    body = []
    for gname, cps in groups:
        gid = re.sub(r'[^a-z0-9]+', '-', gname.lower()).strip('-')[:24]
        body.append(f'\n<!-- ---------------- {gname} ---------------- -->')
        body.append(f'<div class="grp" id="g-{gid}"><h3>{html.escape(gname)}</h3>\n')
        for did, label, hood in cps:
            n = did.split('-')[1]
            aid = f'cp-{did}' if pfx != 'w' else f'cp-{did[1:]}'
            cpid = f'{mod.upper()}.{n}'
            body.append(f'''<article class="lesson" id="{aid}" data-id="{did}">
<div class="lesson-head"><span class="cp-id">{cpid}</span><h4>TODO headline</h4>
<label class="donebox"><input type="checkbox"><span class="box"></span>done</label></div>
<!-- CHECKPOINT: {comment_safe(label)}
     UNDER THE HOOD: {comment_safe(hood) or "(none)"} -->

<h5>Why it matters</h5>
<p>TODO plain-English hook.</p>

<h5>The concept</h5>
<p>TODO. Absorb and expand the "under the hood" note above.</p>

<div class="specref">
<p>TODO what the spec actually says.</p>
<blockquote>TODO verbatim quote — fetch it, never write it from memory.</blockquote>
<cite>TODO spec, version — <a href="TODO">file</a></cite>
</div>

<h5>Lab</h5>
<ol class="lab">
<li>TODO. Every command must be RUN before it is written — tools/vm.sh cap.
<pre class="cmd">TODO</pre>
<pre class="out">TODO captured output</pre></li>
</ol>

<h5 class="verify">Verify</h5>
<p>TODO what the reader can now do.</p>

<h5 class="gotcha">Gotchas</h5>
<ul>
<li><strong>TODO.</strong></li>
</ul>

<div class="k8s-link">
<p>TODO where this shows up in Kubernetes, with a deep link.</p>
</div>

<p class="docs-links"><b>Docs:</b> TODO.</p>
</article>
''')
        body.append(f'</div><!-- /g-{gid} -->\n')

    page = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="TODO one-sentence description of {title}.">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📦</text></svg>">
<title>{html.escape(title)} — {brand.split(' · ')[0]} Track</title>
<link rel="stylesheet" href="../assets/site.css">
</head>
<body class="materials">

<div class="wrap">
<aside class="side">
  <div class="brand-row">
    <div class="brand">{brand}</div>
    <button class="theme-btn" id="theme" aria-label="Toggle light/dark theme">theme</button>
  </div>
  <div class="tracks">
{pills}
  </div>
  <div class="panel ring-row">
    <div class="ring" id="ring"><div class="pct" id="pct">0%</div></div>
    <div class="ring-meta"><strong id="done-count">0 / 0</strong>{mod.upper()} done</div>
  </div>
  <nav><ul class="nav" id="nav"></ul></nav>
  <div id="matwrap"><h4>Site</h4><ul class="mats">
    <li><a href="../{tracker}">← Back to the tracker</a></li>
{site}
  </ul></div>
</aside>

<main>
<p class="crumb"><a href="../{tracker}#{mod}">← Back to the tracker</a></p>
<header class="hero">
  <h1>{html.escape(title)}</h1>
  <p>{goal}</p>
  <p>TODO second paragraph: what makes this module worth the hours.</p>
  <div class="weights">
    <span>Checkpoints<b>{cps_seen}</b></span>
    <span>Hours<b>~{hours}</b></span>
    <span>Prerequisites<b>TODO</b></span>
  </div>
</header>

<div class="objectives">
<ul>
<li>TODO one objective per checkpoint group, in order.</li>
</ul>
</div>

<div class="prereq">
<p>{pre}</p>
<p><strong>Which machine.</strong> TODO — and state the tool versions the output came from.</p>
</div>
{''.join(body)}
<div class="quiz" id="quiz">
<h3>Quiz</h3>
<ol>
<li>TODO — 8+ questions, one per hard idea.
<details class="reveal"><summary>Answer</summary><p>TODO</p></details></li>
</ol>
</div>

<div class="outcome">
<ul>
<li>TODO one line per objective, in the past tense of capability.</li>
</ul>
</div>

<div class="godeep"><a href="../{TRACKS['b'][0]}">TODO go-deep link →</a></div>

<nav class="pager">{prev_a}<a href="../{tracker}#{pfx}{num+1}">{pfx.upper()}{num+1} · TODO →</a></nav>

<footer>
TODO authored-against line: distro, kernel, tool versions, verification date,
and every version-sensitive finding the live run produced.
</footer>
</main>
</div>
<script src="../assets/lesson.js"></script>
</body>
</html>
'''
    open(out, 'w').write(page)
    print(f"wrote {out}: {len(groups)} groups, {cps_seen} checkpoints")
    print(f"  groups: {', '.join(g for g, _ in groups)}")
    print(f"  next:   fill the TODOs, then tools/publish-module.sh {mod}")

def title_of(pfx, n):
    """Short title for a sibling page, from its own <title>."""
    p = f"materials/{pfx}{n}.html"
    if os.path.exists(p):
        t = re.search(r'<title>(.*?)</title>', open(p).read())
        if t:
            return html.unescape(t.group(1)).split(' — ')[0]
    return f"{pfx.upper()}{n}"

if __name__ == '__main__':
    main()
