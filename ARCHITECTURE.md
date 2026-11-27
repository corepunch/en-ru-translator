# Translation pipeline

`en_ru/engine.lua` breaks documents into sentences without flattening
paragraphs and list lines. `tokenize.lua` preserves source spelling for
unknown tokens, normalizes apostrophes, and keeps decimal tokens together.
Numeric references after abbreviations do not start a new sentence.

`lexicon.lua` loads English POS/translation candidates, exceptional English
forms, and Russian paradigms. The checked-in exports and their licenses are
separate; `vocabulary.tsv` carries independently authored lexical senses
and argument constraints. The exporter never imports translations of
multiword English keys. A candidate is a lemma and a part of speech, not a
replacement sentence.

`grammar.lua` identifies noun phrases, a finite verb group, and dependent
phrases. It chooses lexical senses based on the role and arguments; transfers
locative direction, relative clauses, negative existence, tense, and case;
then requests the Russian noun, adjective and verb forms for those features.
The object's governor determines its case, separately from the relative
pronoun's case. Function-word tables and contractions are grammatical data.

## Adding a sense or rule

- Add a target lemma, part of speech and optional frame in
  `dictionary/vocabulary.tsv`; then regenerate the export if the target needs
  new Russian inflections. Frame names: `intr`, `obj`, `dat`, `gen`,
  `dobj`, `motion`, `content`, `passive`, `imperative`. A frame can
  optionally constrain its direct object lemma (e.g. a technical verb sense).
- Add structure to the grammar rather than exceptions for full input phrases.
  Each grammatical change should have a compositional example with different
  vocabulary and a contrast where the rule must not fire.
- Keep export filters deterministic. An exported inflection is stored as the
  byte count of the common UTF-8 prefix with the lemma plus its new suffix.

## Current limits

This is a compact first independent ruleset. It is not a full English parser:
coordination, passives, subordinate clauses, numeral government, questions,
idioms and reference across sentences are only partially handled. Candidate
order is a default, not evidence that a sense is correct. Data coverage and
successful book processing do not measure accuracy. The debug token trace
exposes ambiguity rather than claiming a complete syntactic parse.

## Adventure text

`require("en_ru.adventure").new()` exposes `heading(text)`, `prose(text)`
and `choice({label=..., command=..., ...})`. Use it after a host parses the
story markup and before displaying the turn. The host retains canonical
actions, object IDs and save data; the adapter copies choice metadata and
localizes only its label. Do not pass an unparsed link string to `prose`.
The adapter is tested in isolation; no UI is switched to it by this change.

The authored `scene.tsv` entries cover reusable object names, direction and
scene verbs. A multiword headword is a single constituent, not a sentence
shortcut. For example, a window can be "boarded up" under an ordinary
passive rule; a locative existential never guesses an object's posture.
Regeneration adds `scene-forms.tsv` without changing the base data shards.
