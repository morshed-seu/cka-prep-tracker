#!/usr/bin/env bash
# For every published lesson page (materials/wN.html), verify that
#   - each tracker checkpoint data-id="wN-M" has a lesson anchor id="cp-N-M"
#   - each lesson anchor has a matching tracker checkpoint
#   - each lesson's data-id matches its own anchor id
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
shopt -s nullglob
pages=(materials/w*.html)

if [ ${#pages[@]} -eq 0 ]; then
  echo "no materials pages published yet — nothing to check"
  exit 0
fi

for page in "${pages[@]}"; do
  wk=$(basename "$page" .html); wk=${wk#w}
  tracker=$(grep -o "data-id=\"w${wk}-[0-9]*\"" index.html | sed 's/data-id="w/cp-/; s/"//' | sort -u)
  anchors=$(grep -o "id=\"cp-${wk}-[0-9]*\"" "$page" | sed 's/id="//; s/"//' | sort -u)

  missing=$(comm -23 <(echo "$tracker") <(echo "$anchors"))
  orphans=$(comm -13 <(echo "$tracker") <(echo "$anchors"))
  if [ -n "$missing" ]; then
    echo "FAIL $page: tracker checkpoints without a lesson anchor:"; echo "$missing" | sed 's/^/  /'
    fail=1
  fi
  if [ -n "$orphans" ]; then
    echo "FAIL $page: lesson anchors with no tracker checkpoint:"; echo "$orphans" | sed 's/^/  /'
    fail=1
  fi

  # lesson data-id ↔ its own anchor id
  while IFS= read -r line; do
    id=$(grep -o 'id="cp-[0-9]*-[0-9]*"' <<<"$line" | sed 's/id="//; s/"//' || true)
    did=$(grep -o 'data-id="w[0-9]*-[0-9]*"' <<<"$line" | sed 's/data-id="w/cp-/; s/"//' || true)
    if [ -n "$id" ] && [ -n "$did" ] && [ "$id" != "$did" ]; then
      echo "FAIL $page: lesson id=$id has data-id mapping to $did"
      fail=1
    fi
  done < <(grep -o '<article class="lesson"[^>]*>' "$page")

  n=$(wc -l <<<"$anchors")
  echo "ok   $page: $n lesson anchors checked"
done

exit $fail
