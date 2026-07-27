#!/usr/bin/env bash
# Publish a finished lesson page: the four mechanical wiring steps that turn a
# written materials/<mod>.html into a reachable one.
#
#   tools/publish-module.sh i4 [--dry-run]
#
#   1. add the module number to the tracker's PUBLISHED array (injects the
#      lesson links and the sidebar entry)
#   2. add the page to the "Site" list in every already-published sibling
#   3. repoint the previous module's pager `next` from the tracker anchor to
#      the new sibling file
#   4. run all three checkers plus check-page.py, and refuse to leave the tree
#      in a state that does not validate
#
# Refuses to publish a page that still has TODO placeholders.
set -euo pipefail
cd "$(dirname "$0")/.."

die(){ echo "publish-module: $*" >&2; exit 1; }

MOD=${1:-} ; DRY=${2:-}
[[ $MOD =~ ^[wbi][0-9]+$ ]] || die "usage: publish-module.sh <module> [--dry-run]   e.g. i4"
PFX=${MOD:0:1}; NUM=${MOD:1}
PAGE="materials/$MOD.html"
[ -f "$PAGE" ] || die "no $PAGE — run tools/scaffold-module.py $MOD first"

case $PFX in
  w) TRACKER=index.html ;;
  b) TRACKER=beginner.html ;;
  i) TRACKER=intermediate.html ;;
esac

# --- refuse to publish unfinished work -------------------------------------
if grep -q 'TODO' "$PAGE"; then
  echo "publish-module: $PAGE still contains TODO placeholders:" >&2
  grep -n 'TODO' "$PAGE" | head -5 >&2
  die "finish the page first"
fi

TITLE=$(sed -n 's|.*<title>\(.*\)</title>.*|\1|p' "$PAGE" | head -1 | sed 's/ — .*//')
[ -n "$TITLE" ] || die "no <title> in $PAGE"

# Pre-flight: validate the page BEFORE touching the tracker or any sibling.
# Publishing mutates five files; discovering the page is broken afterwards
# leaves a mess that has to be unpicked by hand.
python3 tools/check-html.py "$PAGE" >/dev/null 2>&1 \
  || { python3 tools/check-html.py "$PAGE"; die "$PAGE does not parse — nothing was changed"; }
python3 tools/check-page.py "$PAGE" >/dev/null 2>&1 \
  || { python3 tools/check-page.py "$PAGE"; die "$PAGE fails QA — nothing was changed"; }

CUR=$(sed -n 's/.*var PUBLISHED=\[\([^]]*\)\].*/\1/p' "$TRACKER" | head -1)
if [[ ",$CUR," == *",$NUM,"* ]]; then
  echo "publish-module: $NUM already in PUBLISHED=[$CUR] — re-running the rest anyway"
  NEW=$CUR
else
  NEW=$(printf '%s\n%s\n' "${CUR//,/$'\n'}" "$NUM" | grep -E '^[0-9]+$' | sort -n | paste -sd,)
fi

# previous published sibling, for step 3
PREV=$(printf '%s\n' "${CUR//,/$'\n'}" | grep -E '^[0-9]+$' | awk -v n="$NUM" '$1<n' | sort -n | tail -1)

echo "module   : $MOD  ($TITLE)"
echo "tracker  : $TRACKER   PUBLISHED [$CUR] -> [$NEW]"
echo "siblings : ${CUR:-none}"
echo "prev     : ${PREV:-none}"
[ "$DRY" = --dry-run ] && { echo "(dry run — nothing written)"; exit 0; }

# --- 1. PUBLISHED ----------------------------------------------------------
sed -i "s/var PUBLISHED=\[$CUR\]/var PUBLISHED=[$NEW]/" "$TRACKER"

# --- 2. Site list in every published sibling --------------------------------
ENTRY="    <li><a href=\"$MOD.html\">$TITLE</a></li>"
for n in ${CUR//,/ }; do
  sib="materials/$PFX$n.html"
  [ -f "$sib" ] || continue
  grep -q "href=\"$MOD.html\"" "$sib" && continue
  # append after the last existing materials entry in the Site list
  last=$(grep -n "<li><a href=\"$PFX[0-9]*\.html\">" "$sib" | tail -1 | cut -d: -f1)
  [ -n "$last" ] || { echo "  !! no Site list found in $sib — add $MOD by hand"; continue; }
  sed -i "${last}a\\$ENTRY" "$sib"
  echo "  + Site entry -> $sib"
done

# --- 3. previous module's pager next ---------------------------------------
if [ -n "${PREV:-}" ] && [ -f "materials/$PFX$PREV.html" ]; then
  p="materials/$PFX$PREV.html"
  if grep -q "<a href=\"../$TRACKER#$MOD\">" "$p"; then
    sed -i "s|<a href=\"../$TRACKER#$MOD\">|<a href=\"$MOD.html\">|" "$p"
    echo "  + pager next -> $p now points at $MOD.html"
  fi
fi

# --- 4. verify --------------------------------------------------------------
echo "--- checkers"
ok=1
tools/check-links.sh   >/dev/null 2>&1 || { tools/check-links.sh | grep -i fail; ok=0; }
python3 tools/check-html.py >/dev/null 2>&1 || { python3 tools/check-html.py | grep -i fail; ok=0; }
python3 tools/check-page.py >/dev/null 2>&1 || { python3 tools/check-page.py | grep -i fail; ok=0; }
node --check assets/lesson.js >/dev/null 2>&1 || { echo "FAIL lesson.js"; ok=0; }
if [ "$ok" = 1 ]; then
  echo "ok   check-links, check-html, check-page, lesson.js — all green"
  echo "published $MOD. Remaining: tick the roadmap row in CLAUDE.md and docs/, update the memory file."
else
  die "checkers failed — the tree is NOT publishable; fix before committing"
fi
