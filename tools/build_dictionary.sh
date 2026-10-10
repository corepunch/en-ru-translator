#!/bin/sh
# Build dictionary/BASE.DIC and dictionary/BASE.RUS: LTGOLD's dictionaries with
# our changes applied (dictionary/changes.txt, dictionary/changes-rus.txt).
#   sh tools/build_dictionary.sh           write dictionary/BASE.*
#   sh tools/build_dictionary.sh --verify  require the checked-in files to match
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

cp LTGOLD/BASE.DIC "$work/BASE.DIC"
if grep -qv '^\(#.*\)\?$' dictionary/changes.txt; then
  python3 tools/ltech_dict.py import "$work/BASE.DIC" --entries dictionary/changes.txt --replace --in-place >/dev/null
fi
python3 tools/ltech_dict.py check "$work/BASE.DIC" | grep -q 'index: valid'
cp LTGOLD/BASE.RUS "$work/BASE.RUS"
if grep -qv '^\(#.*\)\?$' dictionary/changes-rus.txt; then
  python3 tools/ltech_dict.py import "$work/BASE.RUS" --entries dictionary/changes-rus.txt --replace --in-place >/dev/null
fi
python3 tools/ltech_dict.py check "$work/BASE.RUS" | grep -q 'index: valid'

if [ "${1:-}" = "--verify" ]; then
  for x in DIC RUS; do cmp "$work/BASE.$x" "dictionary/BASE.$x"; done
  echo "dictionary/BASE.DIC and BASE.RUS are reproducible"
else
  for x in DIC RUS; do cp "$work/BASE.$x" "dictionary/BASE.$x"; done
  python3 tools/ltech_dict.py check dictionary/BASE.DIC | grep entries
fi
