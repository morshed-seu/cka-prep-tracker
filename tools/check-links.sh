#!/usr/bin/env bash
# For every published lesson page, verify that
#   - each tracker checkpoint has a lesson anchor
#   - each lesson anchor has a matching tracker checkpoint
#   - each lesson's data-id matches its own anchor id
#
# Two tracks, one rule: anchor id = "cp-" + data-id with a leading "w" stripped.
#   advanced: index.html     data-id="w3-7"  <->  materials/w3.html  id="cp-3-7"
#   beginner: beginner.html  data-id="b3-7"  <->  materials/b3.html  id="cp-b3-7"
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
shopt -s nullglob

check_track(){                      # $1 = tracker file, $2 = page prefix (w|b), $3 = track label
  local tracker=$1 pfx=$2 label=$3
  local pages=(materials/"$pfx"[0-9]*.html)

  if [ ! -f "$tracker" ]; then
    echo "--   $label: no $tracker yet — skipped"
    return
  fi
  if [ ${#pages[@]} -eq 0 ]; then
    echo "--   $label: no lesson pages published yet — nothing to check"
    return
  fi

  local page stem aid tracker_ids anchors missing orphans id did n
  for page in "${pages[@]}"; do
    stem=$(basename "$page" .html)          # w3 | b3
    aid="cp-${stem#w}"                      # cp-3 | cp-b3
    tracker_ids=$(grep -o "data-id=\"${stem}-[0-9]*\"" "$tracker" \
      | sed "s/data-id=\"${stem}/${aid}/; s/\"//" | sort -u)
    anchors=$(grep -o "id=\"${aid}-[0-9]*\"" "$page" | sed 's/id="//; s/"//' | sort -u)

    missing=$(comm -23 <(echo "$tracker_ids") <(echo "$anchors"))
    orphans=$(comm -13 <(echo "$tracker_ids") <(echo "$anchors"))
    if [ -n "$missing" ]; then
      echo "FAIL $page: $tracker checkpoints without a lesson anchor:"; echo "$missing" | sed 's/^/  /'
      fail=1
    fi
    if [ -n "$orphans" ]; then
      echo "FAIL $page: lesson anchors with no checkpoint in $tracker:"; echo "$orphans" | sed 's/^/  /'
      fail=1
    fi

    # lesson data-id <-> its own anchor id
    while IFS= read -r line; do
      id=$(grep -o 'id="cp-b\?[0-9]*-[0-9]*"' <<<"$line" | sed 's/id="//; s/"//' || true)
      did=$(grep -o 'data-id="[wb][0-9]*-[0-9]*"' <<<"$line" | sed 's/data-id="w\?/cp-/; s/"//' || true)
      if [ -n "$id" ] && [ -n "$did" ] && [ "$id" != "$did" ]; then
        echo "FAIL $page: lesson id=$id has data-id mapping to $did"
        fail=1
      fi
    done < <(grep -o '<article class="lesson[^"]*"[^>]*>' "$page")

    n=$(grep -c . <<<"$anchors" || true)
    echo "ok   $page: $n lesson anchors checked"
  done
}

check_track index.html    w "advanced track"
check_track beginner.html b "beginner track"

exit $fail
