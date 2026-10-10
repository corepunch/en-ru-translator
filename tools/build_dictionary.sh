#!/bin/sh
# Build dictionary/BASE.DIC and dictionary/BASE.RUS: LTGOLD's dictionaries with
# our changes applied (dictionary/changes.txt, dictionary/changes-rus.txt), and
# the add-on dictionary/BASE2.DIC and BASE2.RUS: only the records of
# dictionary/phrases.txt and phrases-rus.txt. The engine loads BASE.*, then
# BASE2.*, BASE3.* ... (each overriding the earlier), as Quake 2 loads paks.
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
if not keys:
    sys.exit(0)
formal = L.load_dictionary('LTGOLD/BASE.DIC')
formal.delete_folded({L.fold_key(k) for k, _v in formal.entries()} - keys)
missing = keys - {L.fold_key(k) for k, _v in formal.entries()}
if missing:
    sys.exit('informal keys LTGOLD lacks: ' + ', '.join(sorted(L.decode_cp866(k) for k in missing)))
L._write_result(formal, sys.argv[1], False)
PY
[ ! -f "$work/FORMAL.DIC" ] || python3 tools/ltech_dict.py check "$work/FORMAL.DIC" | grep -q 'index: valid'
cp LTGOLD/BASE.RUS "$work/BASE.RUS"
if grep -qv '^\(#.*\)\?$' dictionary/changes-rus.txt; then
  python3 tools/ltech_dict.py import "$work/BASE.RUS" --entries dictionary/changes-rus.txt --replace --in-place >/dev/null
fi
python3 tools/ltech_dict.py check "$work/BASE.RUS" | grep -q 'index: valid'

# An add-on: LTGOLD's file with the add-on imported, keeping only the add-on's
# own keys, so it is a standalone file that can be taken out.
overlay() { # base entries output
  if ! grep -qv '^\(#.*\)\?$' "$2"; then return; fi
  cp "$1" "$3"
  python3 tools/ltech_dict.py import "$3" --entries "$2" --replace --in-place >/dev/null
  python3 - "$2" "$3" <<'PY'
import sys
sys.path.insert(0, 'tools')
import ltech_dict as L
keys = set()
for line in open(sys.argv[1], encoding='utf-8'):
    line = line.rstrip('\n')
    if line and not line.startswith('#'):
        keys.add(L.fold_key(L.line_parts(L.encode_cp866(line))[0]))
d = L.load_dictionary(sys.argv[2])
d.delete_folded({L.fold_key(k) for k, _v in d.entries()} - keys)
L._write_result(d, sys.argv[2], True)
PY
  python3 tools/ltech_dict.py check "$3" | grep -q 'index: valid'
}
overlay LTGOLD/BASE.DIC dictionary/phrases.txt "$work/BASE2.DIC"
overlay LTGOLD/BASE.RUS dictionary/phrases-rus.txt "$work/BASE2.RUS"

if [ "${1:-}" = "--verify" ]; then
  for x in BASE.DIC BASE.RUS; do cmp "$work/$x" "dictionary/$x"; done
  for x in FORMAL.DIC BASE2.DIC BASE2.RUS; do
    if [ -f "$work/$x" ]; then cmp "$work/$x" "dictionary/$x"; else [ ! -f "dictionary/$x" ]; fi
  done
  echo "dictionary/BASE.*, FORMAL.DIC and BASE2.* are reproducible"
else
  for x in BASE.DIC BASE.RUS; do cp "$work/$x" "dictionary/$x"; done
  for x in FORMAL.DIC BASE2.DIC BASE2.RUS; do
    if [ -f "$work/$x" ]; then cp "$work/$x" "dictionary/$x"; else rm -f "dictionary/$x"; fi
  done
  python3 tools/ltech_dict.py check dictionary/BASE.DIC | grep entries
fi
