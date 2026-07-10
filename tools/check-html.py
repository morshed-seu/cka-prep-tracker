#!/usr/bin/env python3
"""Tag-balance check for the site's HTML files. Usage: tools/check-html.py [files...]
Defaults to index.html + all materials/cheatsheets/mock pages. Exits 1 on any mismatch."""
import sys, glob
from html.parser import HTMLParser

VOID = {'meta', 'link', 'input', 'br', 'img', 'hr', 'col', 'source', 'wbr'}

class Checker(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack, self.bad = [], False
    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append((tag, self.getpos()))
    def handle_startendtag(self, tag, attrs):
        pass
    def handle_endtag(self, tag):
        if self.stack and self.stack[-1][0] == tag:
            self.stack.pop()
        else:
            print(f"  MISMATCH </{tag}> at {self.getpos()}, open: {self.stack[-1] if self.stack else None}")
            self.bad = True

files = sys.argv[1:] or ['index.html'] + sorted(
    glob.glob('materials/*.html') + glob.glob('cheatsheets/*.html') + glob.glob('mock/*.html'))
fail = False
for f in files:
    c = Checker()
    c.feed(open(f).read())
    ok = not c.stack and not c.bad
    print(f"{'ok  ' if ok else 'FAIL'} {f}" + ('' if ok else f" unclosed: {[t for t, _ in c.stack]}"))
    fail |= not ok
sys.exit(1 if fail else 0)
