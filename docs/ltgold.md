# How LTGOLD works

What the translator does with its dictionaries and tables, as established
against the original program (`tools/ltpro_capture.py`). Read this before
changing a dictionary, a table or the inflection code. The rule that follows
from it: LTGOLD already has a mechanism for everything it translates. A wish
to extend a format, add a table row or store something LTGOLD does not store
means the format has been misread; find the LTGOLD mechanism first.

Byte-level details are in [dictionary](dictionary.md) (`.DIC` codes, record
structure), [morphology](paradigms.md) and the
[code reference](../skills/dictionary-writing/references/codes.md) (`.RUS`
bits, verified minimal pairs).

## Data

| Data | Where | Shape |
| --- | --- | --- |
| English dictionary | `LTGOLD/BASE.DIC` (63,950 records) | one record per key: `key*code` |
| Russian dictionary | `LTGOLD/BASE.RUS` (8,771 records) | one record per Russian lemma and class: `lemma*binary code` |
| Grammar rules, inflection tables, word lists, literals | in `LTPRO.EXE`; extracted to [`core/rules.lua`](../core/rules.lua) by name | T1-T8, cleanup, T7-adjective, constituent, suffixes, contractions, paradigms, ending lists, pronouns |
| Theme dictionaries | `BUSINESS.DIC`, `COMPUTER.DIC` | same records as `BASE.DIC`, chained before it |

`core/rules.lua` holds no LTPRO addresses; they appear only in
`demo/extract_ltpro.lua` and the research tools.

## English records (`.DIC`)

- **One record per key.** All of a key's meanings are in that record: a
  segment per part of speech, alternatives after `;` within a segment
  (`table*NN.стол{piece of furniture};инф)таблица{chart}A.табличный`). Grammar
  picks the segment; its first meaning is printed and the rest appear inline as
  `{1.…}`, numbered through the text.
- **Multiword keys** are phrases. The lexicon matches the longest literal key
  before any grammar runs, so a literal (`is it*WXRэто`) takes its words away
  from later rules.
- **Subrules** are keys with a pattern, `word pattern*$action`
  (`run [TAONIH"'#?]*$Vвыполнять`): a word keeps up to ten, and T4 applies the
  one whose match ends **soonest**, so a one-word pattern beats a longer one.
- **Irregular plurals are lemmas of their own.** `children*Nдети` reads дети,
  which has its own `.RUS` record (plural-only, paradigm 23); `people*Nлюди`
  the same with paradigm 30. A plural is not built from ребенок.

## Russian records (`.RUS`)

Only ~8,800 lemmas have a record: the ones whose paradigm, gender, aspect,
government or partner LTGOLD needs to state. A word without one is still
translated: a noun inflects as masculine row 0, an adjective by its ending.

| Class | Bytes after the class letter |
| --- | --- |
| `N` | flags (`0x80` base, `0x02` animate, `0x40` takes на), gender byte (`&3` gender 0 n, 1 m, 2 f; `0x08` plural only, `0x04` singular only), paradigm `0x80|id` |
| `V` | flags (`0x08` analytic future, `0x02` native perfective, `0x04` forced perfective), government, paradigm `0x80|id`, governed case, then the perfective partner lemma |
| `A` | flags (`0x20` short form always, `0x01` short predicate), paradigm `0x80|id`; keyed by the stem without its two-letter ending (красн) |

The paradigm byte is 7 bits; id `0x7F` means none. LTGOLD fills the byte for
nearly every record; it never needs more ids than the tables have.

## Inflection

- **Tables.** Two verb tables (imperfective 106 rows, perfective 113), three
  noun tables (m 66, f 35, n 33), adjectives (26 paradigms, a row per gender;
  the three tables are views of one array) and a replacement table (47).
  A row is a cut count and space-separated endings per slot; `=` is the stem
  itself, `-` no form. Slots: verbs 1sg 2sg 3sg 1pl 2pl 3pl imperative-pl
  past-stem gerund act-pres pass-pres act-past pass-past; nouns gen dat acc
  inst prep, then the plural nom..prep; adjectives nom..prep, plural nom..prep.
- **Ending lists choose the row.** Each row has a list of the lemma endings it
  serves, in the same order as the rows (`rules.lists.endings_noun_m`,
  `endings_verb_perfective`, ...; `noun-m` row 0 serves `в г д з к л м р с т`,
  verb row 18 only `бежать`). This is how a paradigm is assigned to a new
  word: the rows whose list matches the lemma's end, longest ending first
  (`russian.paradigm_candidates`).
- **Fixed behaviour of the tables**, which the original shows and the engine
  keeps: one prepositional form (`в саде`); imperatives are plural
  (`Помогите`, `Полейте`); the comparative is analytic (`более высокий`); the
  table accusative is inanimate, and an animate noun (flag `0x02`) takes the
  genitive (`вижу брата`, `новых друзей`).
- **Pronouns** decline from their own table: nominatives я ты он оно она мы
  вы они кто что себя, each with its oblique cases (`я`: меня мне меня мной
  мне); after a preposition the third person takes н- (`о них`).
- **Errors in LTPRO's data**, verified: four endings spelled with a Latin `e`
  (жeте, дeл; the original prints `сидeла`), and imperfective row 18 (бежать)
  missing the 1pl ending жим, which shifts the later slots (the original
  prints `Они бегите`). `core/rules.lua` keeps the bytes as they are.

## Verifying

The original program is the oracle; see `AGENTS.md` for `ltpro_capture.py`.
Engine parity is measured with LTGOLD's own dictionaries against the captured
corpora under `test/ltpro/`:

```sh
python3 tools/ltpro_pipeline_probe.py --cases test/ltpro/cases.json \
  --reference test/ltpro/reference.json --data LTGOLD \
  --dictionary LTGOLD/BASE.DIC --russian LTGOLD/BASE.RUS
```

Before OpenRussian (commit `a38f955`) this gave 77/77 on the main corpus and
355/386 on `review-2026-10-08`. A dictionary change is judged by what it does
to translations; an engine change must keep these numbers.
