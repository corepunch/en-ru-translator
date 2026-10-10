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
# --formal: LTGOLD's own records for every key the informal section replaces.
python3 - "$work/FORMAL.DIC" <<'PY'
import sys
sys.path.insert(0, 'tools')
import ltech_dict as L
keys, section = set(), None
for line in open('dictionary/changes.txt', encoding='utf-8'):
    line = line.rstrip('\n')
    if line.startswith('## '):
        section = line[3:]
    elif section == 'informal' and line and not line.startswith('#'):
        keys.add(L.fold_key(L.line_parts(L.encode_cp866(line))[0]))
formal = L.load_dictionary('LTGOLD/BASE.DIC')
formal.delete_folded({L.fold_key(k) for k, _v in formal.entries()} - keys)
missing = keys - {L.fold_key(k) for k, _v in formal.entries()}
if missing:
    sys.exit('informal keys LTGOLD lacks: ' + ', '.join(sorted(L.decode_cp866(k) for k in missing)))
L._write_result(formal, sys.argv[1], False)
PY
python3 tools/ltech_dict.py check "$work/FORMAL.DIC" | grep -q 'index: valid'
cp LTGOLD/BASE.RUS "$work/BASE.RUS"
if grep -qv '^\(#.*\)\?$' dictionary/changes-rus.txt; then
  python3 tools/ltech_dict.py import "$work/BASE.RUS" --entries dictionary/changes-rus.txt --replace --in-place >/dev/null
fi
python3 tools/ltech_dict.py check "$work/BASE.RUS" | grep -q 'index: valid'

if [ "${1:-}" = "--verify" ]; then
  for x in BASE.DIC BASE.RUS FORMAL.DIC; do cmp "$work/$x" "dictionary/$x"; done
  echo "dictionary/BASE.DIC, BASE.RUS and FORMAL.DIC are reproducible"
else
  for x in BASE.DIC BASE.RUS FORMAL.DIC; do cp "$work/$x" "dictionary/$x"; done
  python3 tools/ltech_dict.py check dictionary/BASE.DIC | grep entries
fi
