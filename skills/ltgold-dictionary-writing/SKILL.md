---
name: ltgold-dictionary-writing
description: "Write and review LTGOLD/SARMA English–Russian dictionary entries for en-ru-translator, including grammatical phrase patterns, W readings, and function-word tags. Use when enriching or correcting its .DIC dictionary."
---

# LTGOLD dictionary writing

Work from the en-ru-translator repository root. The normal checkout is
`/Users/igor/Developer/en-ru-translator`; use the current checkout when working
elsewhere. Read its `AGENTS.md`, [authoring reference](references/authoring.md),
and [code and value reference](references/codes.md) before choosing tags or
phrase syntax. The code reference covers every documented dictionary class,
additional Lua/internal tags, numeric fields, pattern operators, subrule controls,
and worked breakdowns of the greeting entries. Consult it rather than guessing
what a letter or digit means; distinguish dictionary codes from runtime tags.

The default English dictionary is `reference/openrussian/BASE.DIC`. Keep reviewed
UTF-8 entries in `reference/openrussian/phrases.txt` and structural word readings
in `reference/openrussian/function-words.txt`; import them with
`tools/ltech_dict.py`. Historical `LTGOLD/BASE.DIC` is a separate reference,
not an automatically merged source. English phrase rules belong in `.DIC`;
`.RUS` and `.MORPH` supply Russian morphology.

Honor the requested scope. For a whole-file or batch review, inventory every
entry and complete an entry-by-entry review; fixing the user's example does not
complete the rest. Historical presence and native syntactic validity are
evidence, not proof of a suitable grammatical encoding or correct translation.

Take no shortcuts. Use verified dictionary syntax, grammatical tags, reusable
patterns, and normal agreement and morphology. Do not hardcode surface forms,
enumerate grammatical variants, or use `#` literals or uninflected tails to hide
missing matcher, agreement, morphology, or casing support. Fix and verify the
underlying defect instead. Fixed text must reflect a genuinely fixed expression
and follow the documented format; it is not a workaround for one failing example.
Do not declare success from the target sentence alone.

For multiword Russian equivalents, use tagged lemma components with agreement
and case government, including conventional greetings such as “happy birthday”.
Do not label an entire sentence `D` merely because it is a familiar expression,
or mechanically wrap frozen text in `W`. A single-word `D` equivalent or truly
fixed text can be appropriate; record the grammatical reason. Preserve intended
meaning and register, and explain deliberate changes. See the authoring
reference's [whole-file review lessons](references/authoring.md#whole-file-phrase-review-lessons)
for verified examples and diagnostic pitfalls.

Recover the native LTGOLD mechanism before changing the translator. Search
`BASE.DIC` for comparable entries, trace the relevant pipeline stage, and test
candidate syntax in the original executable. Do not introduce Lua-specific
syntax or matching behavior to compensate for an incomplete understanding of
LTGOLD. An apparent missing feature is an investigation task, not permission to
invent an extension. Native short-expression rules already use `[*]` boundaries.

For a phrase family, identify the invariant meaning and the variable grammatical
classes. Prefer one native typed pattern that preserves the original nodes'
grammatical fields when that expresses the family. For example, auxiliaries `am/are/is` are **X**, personal
pronouns are **R**, **P** means preposition, and **B/b** mean infinitival `to`.
Do not guess tags from initials or enumerate pronoun variants of one grammatical
construction. Use literal entries for genuinely fixed expressions.

Search existing entries and the LTGOLD manual before adding a rule. Inspect the
active lexical tags as well as the dictionary text: a fixed `W#ты#` reading
cannot serve as an `R` pronoun. Fix missing structural readings or engine support
when necessary; preserve lexical metadata through captures and let normal
agreement/generation decline the word. Document verified native behavior and
remaining port defects separately; do not assume absent native support.

Test every entry you add or change, including structural function-word readings;
do not sample a batch or infer coverage from another entry's passing result.
Keep an explicit entry-to-case mapping and persistent regression cases. Verify
the rebuilt default dictionary through the actual engine, and verify authored
syntax in the original executable with the capture workflow below. Capture
experimental dictionaries separately from untouched historical assets. Inspect
each result; executing successfully or reproducing a frozen expected string
does not establish correct grammar. For each inflecting or variable entry, test
agreement/case or person/number variants and a nearby context that must not be
consumed. Record the reason for retaining any genuinely fixed expression.
An entry with failing or missing verification is unfinished; report it explicitly
instead of declaring the whole file complete.

Rebuild from the C builder output (never by importing into an existing
`BASE.DIC`) and confirm the documented sequence reproduces the checked-in files.
Put each translation check on one line in `test/translations.txt`, tagged with
its source entry, and run `sh test/run_all.sh`. Before accepting a builder
change or a new class of entries, compare old and new translations of the whole
captured corpus and review every changed line. Cover grammatical variants,
contractions, capitalization, and nearby contexts the rule must not consume.
For variable words, also exercise an additional lexical reading to establish
that matching depends on tags rather than an English spelling list. Run the
standard regression suite after engine changes.

When checking original behavior or translation parity, follow the repository's
capture instructions: the original executable is the oracle. Use explicit
temporary cases/output paths, preserve captured text, and report original and
Lua outputs separately. A better Lua translation can intentionally differ;
never alter a capture to make it agree.
Report entry coverage, grammatical regression results, and exact native parity
separately. A reviewed native difference is not an exact match; a negative
matching test does not certify the surrounding translation. Never turn a known
grammatical defect into an accepted expectation just to make tests pass.
