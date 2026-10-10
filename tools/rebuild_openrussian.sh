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
"$work/openrussian_db" build "$dir/upstream" "$work/BASE.DIC" "$work/BASE.RUS" "$work/BASE.MORPH" >/dev/null
python3 tools/ltech_dict.py delete "$work/BASE.DIC" --keys-file "$dir/overlays/removed-headwords.txt" --in-place >/dev/null
python3 tools/ltech_dict.py import "$work/BASE.DIC" --entries "$dir/overlays/function-words.txt" --replace --in-place >/dev/null
python3 tools/ltech_dict.py import "$work/BASE.DIC" --entries "$dir/overlays/irregular-verbs.txt" --replace --in-place >/dev/null
python3 tools/ltech_dict.py import "$work/BASE.DIC" --entries "$dir/overlays/native-readings.txt" --replace --in-place >/dev/null
python3 tools/ltech_dict.py import "$work/BASE.DIC" --entries "$dir/overlays/phrases.txt" --replace --in-place >/dev/null
python3 tools/ltech_dict.py check "$work/BASE.DIC" | grep -q 'index: valid'

if [ "${1:-}" = "--verify" ]; then
  for x in DIC RUS MORPH; do cmp "$work/BASE.$x" "$dir/BASE.$x"; done
  echo "checked-in BASE.DIC/RUS/MORPH are reproducible"
else
  for x in DIC RUS MORPH; do cp "$work/BASE.$x" "$dir/BASE.$x"; done
  python3 tools/ltech_dict.py check "$dir/BASE.DIC" | grep entries
fi
