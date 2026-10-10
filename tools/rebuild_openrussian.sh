#!/bin/sh
# Rebuild the OpenRussian dictionaries from source with the documented sequence.
#   sh tools/rebuild_openrussian.sh           write openrussian/BASE.*
#   sh tools/rebuild_openrussian.sh --verify  build into a temp dir and require
#                                             byte-identical checked-in files
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
dir=openrussian
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

cc -std=c11 -Wall -Wextra -Werror tools/openrussian_db.c -o "$work/openrussian_db" -liconv
lua tools/fit_paradigms.lua "$dir/upstream" > "$work/fit.tsv" 2>/dev/null
"$work/openrussian_db" build "$dir/upstream" "$work/BASE.DIC" "$work/BASE.RUS" "$work/BASE.MORPH" "$work/fit.tsv" >/dev/null
python3 tools/ltech_dict.py import "$work/BASE.DIC" --entries "$dir/dictionary.txt" --replace --in-place >/dev/null
python3 tools/ltech_dict.py check "$work/BASE.DIC" | grep -q 'index: valid'
for theme in "$dir"/themes/*.txt; do
  name=$(basename "$theme" .txt | tr '[:lower:]' '[:upper:]')
  "$work/openrussian_db" text "$theme" "$work/$name.DIC" >/dev/null
  python3 tools/ltech_dict.py check "$work/$name.DIC" | grep -q 'index: valid'
done

if [ "${1:-}" = "--verify" ]; then
  for x in DIC RUS MORPH; do cmp "$work/BASE.$x" "$dir/BASE.$x"; done
  for f in "$work"/*.DIC; do cmp "$f" "$dir/$(basename "$f")"; done
  echo "checked-in BASE.DIC/RUS/MORPH and theme .DIC files are reproducible"
else
  for x in DIC RUS MORPH; do cp "$work/BASE.$x" "$dir/BASE.$x"; done
  for f in "$work"/*.DIC; do cp "$f" "$dir/$(basename "$f")"; done
  python3 tools/ltech_dict.py check "$dir/BASE.DIC" | grep entries
fi
