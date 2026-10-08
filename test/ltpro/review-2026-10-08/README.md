# Expanded feature review, 2026-10-08

This corpus contains 627 case rows and 611 distinct inputs. Every reference was
obtained with `tools/ltpro_capture.py` from a fresh original LTPRO process, with
two byte-identical runs per case and unchanged supplied assets. The historical
reference corpora were not overwritten. Raw CP866 output, hashes, command and
capture provenance are retained in each `*-reference.json` / `reference.json`.

| Corpus | Cases | Coverage |
| --- | ---: | --- |
| `cases.json` | 386 | 122 baseline, 93 noun endings, 68 contractions, 36 degrees, 20 prefixes, 18 phrases, 12 compounds, 9 possessives, 8 directives |
| `phrase-cases.json` | 189 | All 180 dictionary phrase-gap keys with `cat` in gaps, plus 9 regressions |
| `natural-cases.json` | 41 | Natural idioms, tense, possessives and contractions |
| `control-cases.json` | 11 | Expanded forms to distinguish contraction/lookup defects from inherited grammar limitations |

Noun-ending inputs include `-ness` and its hyphen/slash forms; contraction inputs
include `'re`, `'ve`, `'ll`, `'d`, `'m`, `'s`, negatives and perfect constructions.
Additional Lua matrices check 333 contraction variants, 168 noun-ending forms,
and 648 lexical-class alternative combinations. Generated phrase-gap inputs
test engine behavior; many are deliberately not natural English sentences.

## Results and interpretation

[comparison.json](comparison.json) records each input, original `ltpro` output,
current `lua` output, classification and review reason separately:

| Classification | Cases |
| --- | ---: |
| Exact original/Lua paragraph match | 574 |
| Intentional Lua feature difference | 47 |
| Known linguistic limitation | 6 |
| Unexpected output / execution error | 0 / 0 |

All 68 cases in the contractions group match exactly. The separate natural
corpus also tests stacked contractions whose grammatical limitations are listed
below. Examples copied from the authenticated comparison:

| Input | Original LTPRO | Lua | Match |
| --- | --- | --- | --- |
| The happiness is good. | Счастье хорошее. | Счастье хорошее. | Yes |
| We're ready. | Мы готовы. | Мы готовы. | Yes |
| I've worked. | Я работал. | Я работал. | Yes |
| She did her best. | Она делала все возможное. | Она делала все возможное. | Yes |
| He bears it in mind. | Он имеет это в виду. | Он имеет это в виду. | Yes |

The review fixed derived phrase lookup, idiom capture consumption and tie
selection, lost auxiliary tense/person/number, leaked preposition government,
suffix/prefix redirect resolution, plural possessive stems, class-alternative
replacement anchors, glossary numbering, transliteration capitalization, empty
span adjacency and compounds whose components have real dictionary readings.

Intentional differences follow the documented Lua policies: component compound
translation, intact unknown bare-ending compounds, prefix joining/casing,
corrected possessive stems, explicit phrase captures and directive formatting.
Each difference is pinned individually in
[reviewed-differences.json](reviewed-differences.json), including the original
raw-output hash and a reason. These expectations do not modify oracle evidence.

## Known linguistic limitations

Six case rows (including repeated sentences across groups) expose three broader
quality limitations. They remain open in `PLAN.md`; they are not accepted as
correct Russian:

- The supplied Russian data lacks morphology for `дама`. Lua correctly restores
  `ladies'` to `lady`, but leaves the Russian noun uninflected. Expanded
  `of the lady` / `of the ladies` controls reproduce that data limitation in
  the original. Original `ladies'` incorrectly restores `lad` instead.
- `At your convenience.` produces original `К Ваше Услугам.` and Lua
  `К ваше услугам.`. The phrase reading does not provide enough information for
  correct possessive agreement; the difference also includes ordinary Lua casing.
- Lua fully expands stacked contractions, but inherits defects in the resulting
  modal-perfect/conditional grammar. `They shouldn't've gone.` produces original
  `Они shouldn't пришли.` and Lua `Они не должны пришли.`; `We'd've worked.`
  produces original `We'd Работал.` and Lua `Мы будем работать.`. The expanded
  controls `They should not have gone.` and `We would have worked.` produce
  exactly those Lua outputs in both engines. Those exact control matches are
  also linguistically wrong: exact parity is not a correctness score.

## Reproduce

From the repository root, using the supplied assets and Lua 5.3+:

```sh
sh test/run_all.sh
python3 -m unittest discover -s test -p 'feature_review_test.py'
python3 tools/ltpro_feature_review.py --report /tmp/ltpro-feature-review.json
```

The review runner validates input, asset and raw capture hashes, then translates
every case. Its normal success criterion is no unreviewed output changes or
execution failures; documented limitations remain visible. `--strict-oracle`
instead fails for any difference from the executable (currently 53 rows).
Even a reviewed output changing back to the oracle requires updating its review.

New captures require DOSBox-X. To capture a corpus again, write to a temporary
output so the reviewed evidence remains intact:

```sh
python3 tools/ltpro_capture.py \
  --cases test/ltpro/review-2026-10-08/cases.json \
  --output /tmp/ltpro-feature-recapture.json \
  --repeat 2 --batch-size 16 --timeout 120
```

The same explicit capture command was used for each of the other three case
files with its corresponding reference destination. See the reference files
for exact asset/emulator provenance.
