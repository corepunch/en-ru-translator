# Preposition verification

Original LTPRO captures for the preposition batch in
`openrussian/overlays/function-words.txt` (now the `## function-words` section of
`openrussian/dictionary.txt`). Every capture was byte-identical in
two runs.

- `reference.json` (63 cases) and `adverb-reference.json` (5 cases) use the
  untouched supplied LTGOLD assets. They show native behavior for the same
  native codes (`for*PРдля`, `in*PВПвb`, `after*pРпосле…`), not the
  OpenRussian dictionary.
- `subrule-reference.json` uses isolated assets from
  `build_subrule_fixture.py`, which adds `behind [,*]*$Dпозади` and
  `inside [,*]*$Dвнутри` and omits unused `z` headwords to keep the image size.

## Encoding

The entries are authored with native codes, using LTGOLD as evidence rather
than copied wholesale. Each English key has one record: preposition class
`P`/`p`, one governed case letter, and the Russian preposition, with packed
`D`/`J` alternatives where the original has them (`after*pРпослеDвпоследствииJ2после того, как`).
Deliberate differences from LTGOLD:

| Key | LTGOLD | Here | Reason |
| --- | --- | --- | --- |
| in | `PВПвb` | `PПв` | One explicit case (the last letter wins anyway); agreement still switches to accusative or на. |
| at | `PПвDат` | `PПв` | `Dат` is not a useful alternative. |
| on | `PПнаpРот` | `PПна` | The `от` alternative is not a sense of *on*. |
| onto | `PПна` | `PВна` | Direction takes the accusative (на стол); the original prints на столе. |
| toward | `PДпо отношению к` | `PДк` | Matches *towards*; the original's reading is a different sense. |
| around | `PРвокругDвсюду` | `PРвокругDвокруг` | Adverbial *around* is вокруг. |
| inside | `PПвDвнутрь` | `PПвDвнутри` | Location rather than direction. |
| within | `PP.Рв пределах{…}` | `PРв пределах` | Single reading. |

Prepositions that are also common verbs, nouns or adjectives (*like, down,
up, near, over, outside, till, plus, minus*) are not in this batch: a
`function-words.txt` row replaces every record for its key. Archaic or
phrase-only keys (*abt, afore, betwixt, ere, thru, qua, therein*) are omitted.

## Noun flags

Agreement picks в/на and из/с/от from flags in the noun's `.RUS` record:
bit 6 marks на-nouns and bit 1 animates (LTGOLD: стол `c0`, дом `80`,
мать `82`). The builder now sets bit 1 from OpenRussian `animate` and bit 6
from the curated `na` rows (then `overlays/na-nouns.txt`, now `openrussian/lexemes.tsv`). It previously wrote
`c0` for every noun, which would have given “Он - на доме” and “Подарок с брата”.

## Results

The original and Lua agree on the preposition and governed case in every
case except these, where Lua is deliberate:

| Input | Original | Lua |
| --- | --- | --- |
| A letter from the factory. | Письмо От завода. | Письмо с завода. |
| He fell onto the floor. | Он падал на поле. | Он шкура на пол. |
| A step toward the house. | Шаг по отношению к дому. | Шаг к дому. |

Other differences in these sentences are nouns, verbs and numerals outside the
batch (`city` → городской, `left` → левый, `Два книги`, missing `{n.…}`
meanings). Both programs print “Письмо через матери” (animate feminine after an
accusative preposition), “Поскольку война” for *since* before a noun, and
“Книга писателем” for *by*.

The original never applies the `D` alternative or a head-only subrule to a
sentence-final preposition: “He is inside.” is “Он - в.” in both. Before a
comma the subrules apply in both (“Он остался позади, …”).

```sh
fixture_dir=$(mktemp -d /tmp/preposition-subrules.XXXXXX)
python3 test/ltpro/prepositions/build_subrule_fixture.py "$fixture_dir"
python3 tools/ltpro_capture.py --data "$fixture_dir" \
  --cases test/ltpro/prepositions/subrule-cases.json \
  --output "$fixture_dir/reference.json" --repeat 2 --timeout 60
lua test/prepositions_test.lua
```
