# Curated phrase verification

This is the complete grammatical rewrite of `reference/openrussian/phrases.txt`:
29 W composites, three native T4 subrules, and eleven single-word D equivalents.
The review below covers every source entry. The single-word D readings retain
conventional adverbial/interjection senses; none contains a frozen multiword
Russian sentence. `entries.txt` freezes the tested syntax.

`reference.json` contains 58 original LTPRO outputs, each byte-identical in two
runs. These are **experimental assets**, not untouched historical translations:
all 43 entries are installed in an isolated historical BASE.DIC, and nominal
спасибо is added to its BASE.RUS using the native neuter indeclinable code
`4e c0 80 ff` (as in native шоссе). No supplied LTGOLD asset is modified.

The fixture preserves original image lengths: it omits unused English z
headwords and Russian яхта/яровизировать and pads with blank lines. These omissions
are restricted to the fixture; they are not part of the shipped dictionary.

The current default engine is checked separately: `common_phrases_test.lua`
asserts all 43 translations below and fails when a source entry has no case.
Every literal entry has partial-word and protected-span negative checks.
Additional tests cover declension, capitalization, contractions, longest-match
selection and sentence boundaries. `greetings_test.lua` covers retained pronoun
metadata, alternate lexical readings, and nearby nonmatches.

The native comparison has 17 exact matches and 41 differences, not a parity pass.
`reviewed-differences.json` records each difference and binds the default results
to DIC/RUS/MORPH hashes. Most are casing; others expose native/default morphology
or grammar differences. Default positive expectations use grammatical Russian,
not malformed native output. Informal imperatives are intentional; generated
OpenRussian forms normalize ё to е. The past greeting includes explicit мы.

Negative controls deliberately expose remaining unrelated limitations: default
were is missing, longer welcome constructions remain awkward, and a trailing
comparative in “For a while longer” is misplaced. These controls verify that an
idiom does not replace another construction; they do not certify the surrounding
translator. The `How is it?` rule-order defect is corrected by preserving authored W
components; the native failure and corrected Lua output remain in this capture.

The `my pleasure`, `not at all`, and `after all` rows below describe the
earlier literal entries. They are now boundary subrules (45 source entries);
see [boundary-idiom verification](boundary-idioms/README.md) for their native
captures and current Lua results.

## Reproduce

Run from the repository root:

```sh
phrase_fixture_dir=$(mktemp -d /tmp/curated-phrases.XXXXXX)
python3 test/ltpro/curated-phrases/build_fixture.py "$phrase_fixture_dir"
python3 tools/ltpro_capture.py --data "$phrase_fixture_dir" \
  --cases test/ltpro/curated-phrases/cases.json \
  --output "$phrase_fixture_dir/reference.json" --repeat 2 --timeout 60
python3 tools/ltpro_pipeline_probe.py --data "$phrase_fixture_dir" \
  --dictionary reference/openrussian/BASE.DIC --russian reference/openrussian/BASE.RUS \
  --cases test/ltpro/curated-phrases/cases.json \
  --reference "$phrase_fixture_dir/reference.json" \
  --report "$phrase_fixture_dir/comparison.json"
# The exact-parity probe returns nonzero for the reviewed differences above.
lua test/common_phrases_test.lua
lua test/greetings_test.lua
sh test/run_all.sh
```

## Entry-by-entry review

| Case | Source key | Encoding | Default expected output | Authoring decision |
| --- | --- | --- | --- | --- |
| phrase-41 | `how XR[*]` | T4 subrule | Как у тебя дела? | Typed auxiliary/pronoun slots; retained metadata. |
| phrase-42 | `what <X>`up`[*]` | T4 subrule | Как дела? | Final-boundary idiom; preserve longer contexts. |
| phrase-00 | `good morning` | W composite | Доброе утро. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-01 | `good afternoon` | W composite | Добрый день. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-02 | `good evening` | W composite | Добрый вечер. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-03 | `good night` | W composite | Спокойной ночи. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-04 | `good luck` | W composite | Удачи. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-05 | `thank you` | D single word | Спасибо. | Conventional single-word interjection спасибо. |
| phrase-06 | `thank you very much` | W composite | Большое спасибо. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-07 | `thanks a lot` | W composite | Большое спасибо. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-08 | `you `are``welcome`[*]` | T4 subrule | Пожалуйста. | Final-boundary idiom; preserve longer contexts. |
| phrase-09 | `excuse me` | W composite | Извини меня. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-10 | `long time no see` | W composite | Мы давно не виделись. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-11 | `so far so good` | W composite | Пока всё хорошо. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-12 | `just a moment` | W composite | Минутку. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-13 | `my pleasure` | W composite | С удовольствием. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-14 | `best wishes` | W composite | Наилучшие пожелания. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-15 | `happy birthday` | W composite | С днем рождения. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-16 | `merry christmas` | W composite | С Рождеством. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-17 | `happy new year` | W composite | С Новым годом. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-18 | `bless you` | W composite | Будь здоров. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-19 | `get well soon` | W composite | Поправляйся скорее. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-20 | `welcome back` | W composite | С возвращением. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-21 | `enjoy your meal` | W composite | Приятного аппетита. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-22 | `never mind` | D single word | Неважно. | Single-word impersonal response неважно. |
| phrase-23 | `not at all` | D single word | Нисколько. | Single-word degree adverb нисколько; preserves the chosen sense. |
| phrase-24 | `of course` | D single word | Конечно. | Single-word modal adverb конечно. |
| phrase-25 | `by the way` | W composite | Между прочим. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-26 | `as soon as possible` | W composite | Как можно скорее. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-27 | `on the other hand` | W composite | С другой стороны. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-28 | `after all` | W composite | В конце концов. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-29 | `at least` | W composite | По крайней мере. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-30 | `in fact` | D single word | Фактически. | Single-word adverb фактически. |
| phrase-31 | `in any case` | W composite | В любом случае. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-32 | `for example` | D single word | Например. | Single-word parenthetical adverb например. |
| phrase-33 | `as a matter of fact` | D single word | Фактически. | Single-word adverb фактически. |
| phrase-34 | `all right` | D single word | Хорошо. | Single-word response/adverb хорошо. |
| phrase-35 | `once again` | D single word | Снова. | Single-word repetition adverb снова. |
| phrase-36 | `in advance` | D single word | Заранее. | Single-word temporal adverb заранее. |
| phrase-37 | `in other words` | W composite | Другими словами. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-38 | `for a while` | W composite | На некоторое время. | Tagged lemmas, agreement and explicit case government where needed. |
| phrase-39 | `right away` | D single word | Немедленно. | Single-word temporal adverb немедленно. |
| phrase-40 | `sooner or later` | W composite | Рано или поздно. | Tagged lemmas, agreement and explicit case government where needed. |
