# Testing

Run from the repository root with Lua 5.3+. Asset-dependent tests require the
supplied unpacked `LTGOLD/LTPRO.EXE`, `BASE.DIC`, and `BASE.RUS`.

## Standard suite and full sentences

```sh
sh test/run_all.sh
```

`test/run_all.lua` runs every `test/*_test.lua` in one Lua process, so the
dictionaries are parsed once, and prints one line per test. A single test still
runs alone with `lua test/NAME_test.lua`.

Translation checks live in `test/translations.txt`, one per line:
`group[:entry] | input => expected` (exact), `~>` (contains) or `!>` (does
not contain). Quote an input with edge whitespace; `\t` inside quotes is a tab.
Entry tags let `common_phrases_test.lua` and `prepositions_test.lua` require a
line for every curated entry, and `greetings_test.lua` adds structural checks
to the `greeting` lines.

This is the required feature regression suite; it does not require DOSBox or
memory-operation parity. New feature expectations describe the documented Lua
behavior. Existing captured expectations remain useful regressions, not a demand
that new features reproduce every DOS quirk.

Coverage includes meanings output, suffixes and compounds, prefix derivation,
duplicate-entry callbacks, lexical class alternatives, phrase captures and W
selectors, domain preferences, protected/transliterated text, list directives,
and API/CLI integration. `phrase_inventory_test.lua` also analyzes 8,940 multiword
W entries (using `cat` for gaps) to catch unsupported branches. It checks safe
analysis, not linguistic correctness of every generated sentence.

`greetings_test.lua` exercises the single grammatical `how XR[*]` rule with
pronoun and contraction variants, capitalization, whitespace, and longer
questions that must remain unaffected. It verifies pronoun fields preserved by
native T4 context replacement,
genitive agreement, nominative plural `дела` generated from `дело`, an additional
pronoun spelling, formal/plural `you`, and
structural `R/X` tags outside greetings. The `what` idiom uses the native T4
subrule ``what <X>`up`[*]``; tests check its application with contractions,
different terminators, and longer inputs that must not match. Literal phrase
keys containing final punctuation do not match the separately stored terminator.
`common_phrases_test.lua` maps all 45 curated entries to explicit translation
cases and fails if any source entry lacks a case. Every literal key also gets
partial-word and protected-span nonmatch checks. Context tests cover declension,
contractions, capitalization, longest-match behavior, and polite-response
boundaries. The 58 repeated native captures, per-entry review, and reproduction
instructions are in `test/ltpro/curated-phrases/` (captured for the
earlier 43-entry source). Boundary-subrule cases may check only the span the
entry owns. Raw native differences remain
visible; the default expectations are not assertions of exact LTPRO parity.
`prepositions_test.lua` maps every `P`/`p` row in `function-words.txt` to a
case checking the preposition and governed noun form, plus в/на, из/с/от and
animate selection from `.RUS` noun flags; captures are in
`test/ltpro/prepositions/`. `openrussian_others_test.lua` checks that generated
`others.tsv` readings use `WD`, not the `#` class that drops a leading с/м/ж.
`encoding_test.lua` verifies standard CP866 bytes for both `Ё` and `ё`.

`W` capitalization applies to the complete phrase, including inserted words.
The reviewed differences record the intentional sentence-case corrections for
`Do your best.` and `Do your level best.`; their original captures remain intact.

The dictionary editor's bulk-import and index checks run separately:

```sh
python3 -m unittest discover -s tools -p test_ltech_dict.py
```

## Expanded executable review

```sh
python3 -m unittest discover -s test -p 'feature_review_test.py'
python3 tools/ltpro_feature_review.py --report /tmp/ltpro-feature-review.json
```

The [2026-10-08 review](test/ltpro/review-2026-10-08/README.md) contains 627
freshly captured cases (611 distinct inputs), including `-ness`, `'re`, `'ve`,
other contractions, all 180 phrase-gap keys, and expanded grammatical controls.
Each original executable output was captured twice with identical bytes. The
runner verifies provenance and requires exact outputs for both oracle matches
and individually reviewed Lua differences. A changed output or execution error
fails; a documented known limitation does not. Successful execution therefore
means no unreviewed regressions, not universally correct Russian.

The checked-in result is 574 exact matches, 47 intentional differences and 6
known-limitation cases, with zero unexpected changes or errors. Use
`--strict-oracle` to fail on any difference, including intentional Lua behavior.
See the review for separate original/Lua outputs and remaining quality issues.

## Optional historical comparisons

```sh
python3 tools/ltpro_pipeline_probe.py
python3 tools/ltpro_pipeline_probe.py --cases test/ltpro/holdout_cases.json --reference test/ltpro/holdout_reference.json
python3 tools/ltpro_pipeline_probe.py --cases test/ltpro/macro_cases.json --reference test/ltpro/macro_reference.json
```

The Python probe verifies asset/input/raw-output hashes before comparing the
single engine against the 77 original, 20 holdout and 26 lexical-macro captured inputs. It never
silently recaptures expected output. The old parser/compiler tests and custom
cat/mat expectation were retired with that implementation; native references
remain unchanged.

## Native differential probes

```sh
python3 tools/ltpro_readings_probe.py
python3 tools/ltpro_transliteration_probe.py
python3 tools/ltpro_matcher_probe.py
python3 tools/ltpro_replacement_probe.py
python3 tools/ltpro_constituent_probe.py
python3 tools/ltpro_morphology_probe.py
python3 tools/ltpro_first_pass_probe.py
python3 tools/ltpro_second_pass_probe.py
python3 tools/ltpro_third_pass_probe.py
python3 tools/ltpro_fourth_pass_probe.py
```

Matcher probes compare controlled inputs with original 8086 functions. The
morphology probe calls the same generator used by production, across every table
row plus seeded edge cases. Stage probes compare captured records, pointer
identity, tags and caches, not just text. Fixture adapters map native offsets to
the named runtime fields through `core.record_layout`; they retain offsets in
diagnostic messages so mismatches can still be located in captured evidence. Python tools may require Capstone;
see their `--help` for fixture selection and larger generated suites.

The byte-memory and allocator probes (`ltpro_function_probe`, `ltpro_post_chain`,
`ltpro_post_fuzz`, `ltpro_heap_fuzz`, and `ltpro_output_probe`) were retired with
that runtime. They compared allocation addresses and memory writes that no longer
exist. Historical reports in `reference/` describe that earlier implementation;
Git history retains the probes. The 8086 harness and snapshot capture tools remain
available for native research, and morphology still compares production Lua
string results directly with the original instructions.

The Lua suite covers shared auxiliary records, alternative independence, record
limits, constituent relinking, cached versus live tags, dictionary lookup,
inflection failure and output capitalization. Corpus and native morphology
fixtures remain unchanged.

## Extraction and capture

```sh
lua demo/audit_rules.lua
lua demo/compare_binaries.lua
lua demo/extract_dispatch.lua
```

The binary comparison reports the known T1 rule difference between the two
original executables and exits nonzero for it. This is not a Lua regression.
Extraction audits verify source data, not execution equivalence. Morphology
comes directly from EXE tables, so a separate generated-table audit is unnecessary.

New full-program references require DOSBox-X and `tools/ltpro_capture.py`.
[Corpus provenance](test/ltpro/README.md) documents the capture profile and assets.
Keep expected outputs and original assets unchanged during refactoring. Corpus
parity does not establish support for every historical grammar or lexical path.
Intentional differences introduced by the Lua feature policies should be assessed
against those policies; do not change stored captures to hide them.

`macros_test.lua` audits all 5,801 literal dictionary entries containing `=` or
`%`, including phrase readings and redirects. The reading probe checks 2,784
native decoder cases. The transliteration probe checks 39,054 contextual/casing
cases against 211E:003A/0E82, including seeded strings. Single-word W readings
keep their native literal `=` behavior; phrase W macros materialize spellings.
The macro corpus includes the unfinished `I'm doing th` that exposed the gap.
