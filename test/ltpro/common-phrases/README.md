# Common-expression verification

`entries.txt` freezes the 41 fixed expressions added to the curated source.
Their `D` readings follow native BASE.DIC conventions such as
`good afternoon*Dдобрый день`, `good night*Dспокойной ночи`, and
`as soon as possible*Dкак можно скорее`. These are fixed expressions, not a
replacement for grammatical pronoun/auxiliary patterns.

This capture preserves the initial frozen-string batch. It is superseded by
the [complete grammatical rewrite](../curated-phrases/README.md), which tests
every current source entry. Keep these earlier bytes as historical evidence;
they do not verify the revised source.

`reference.json` is an original LTPRO capture, byte-identical across two runs.
It uses an **experimental** dictionary with these entries, not untouched
historical BASE.DIC. `comparison.json` compares the Lua engine against the same
experimental English dictionary and historical Russian dictionary: 43/43 exact
matches (41 expressions and two unrelated controls). The default OpenRussian
results for the revised expressions are independently checked by
`test/common_phrases_test.lua`; the two control sentences have different lexical
choices under OpenRussian and are not asserted to match the historical assets.

The DOS program returned untranslated English after size-changing dictionary
edits in this environment. The cause remains unestablished. For this controlled
experiment, retain the original file length: omit the unused `z` entries, add
trailing blank lines to compensate, and rebuild the index. This changes only the
isolated test image. It is not part of the shipped dictionary build, and no
original LTGOLD asset is modified. Reproduce the captured image from repository
root with:

```sh
ltgold_common_dir=$(mktemp -d /tmp/ltgold-common.XXXXXX)
python3 - "$ltgold_common_dir" <<'PY'
import hashlib
import json
import shutil
import sys
from pathlib import Path
sys.path.insert(0, 'tools')
import ltech_dict as ld

out = Path(sys.argv[1])
fixtures = Path('test/ltpro/common-phrases')
for name in ('LTPRO.EXE', 'BASE.RUS', 'ERPREFIX.PRE', 'LTGOLD.CNF', 'LTPRO.CMD'):
    shutil.copyfile(Path('LTGOLD') / name, out / name)
original = ld.load_dictionary(Path('LTGOLD/BASE.DIC'))
image = ld.load_dictionary(Path('LTGOLD/BASE.DIC'))
for line in (fixtures / 'entries.txt').read_text().splitlines():
    key, value = ld.line_parts(ld.encode_cp866(line))
    image.add_line(key, value, replace=True)
image.lines = [line for line in image.lines if not line.startswith(b'z')]
padding = len(original.body()) - len(image.body())
assert padding >= 0
image.trailing_newlines += padding
raw = image.save(out / 'BASE.DIC')
expected = json.loads((fixtures / 'reference.json').read_text())['assets_sha256']['BASE.DIC']
assert hashlib.sha256(raw).hexdigest() == expected
PY
python3 tools/ltpro_capture.py \
  --data "$ltgold_common_dir" \
  --cases test/ltpro/common-phrases/cases.json \
  --output "$ltgold_common_dir/reference.json" --repeat 2 --timeout 60
python3 tools/ltpro_pipeline_probe.py \
  --data "$ltgold_common_dir" \
  --dictionary "$ltgold_common_dir/BASE.DIC" --russian "$ltgold_common_dir/BASE.RUS" \
  --cases test/ltpro/common-phrases/cases.json \
  --reference "$ltgold_common_dir/reference.json" \
  --report "$ltgold_common_dir/comparison.json"
```

Deferred candidates include `no problem`, `see you later`, `see you soon`, and
`no way`: the current pipeline overwrites their literal phrase readings in later
word-specific grammar rules. They need investigation rather than an unverified
entry or a new syntax shortcut.
