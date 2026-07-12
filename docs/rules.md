# Rule Pattern and Replacement Syntax

The patterns and replacements in `rules.lua` use a compact proprietary notation originally from SARMA 2.0 / LTGOLD. Meanings below are confirmed by the Lua parser implementation (`parser.lua:125-159`) and by surgical binary-patching experiments on `LTPRO.EXE`.

See [Pipeline](pipeline.md) for how rules are applied; see [tools.md](tools.md) for patching tooling.

---

## Table Structure

**692 rules total** across 8 tables (verified from `LTPRO.EXE` binary). The Lua port in `rules.lua` contains **644 rules** across 7 passes — T6 (47 rules) is absent.

Full record dumps with per-rule annotations are in [debug/T1.txt](../debug/T1.txt) through [debug/T8.txt](../debug/T8.txt).

| Table | Rules | Rec size | Tuple Shape | Role |
|-------|-------|----------|-------------|------|
| T1 | 47 | 10 B | `{flags16, pat_off, act_off}` | Clause skeleton: Z disambiguation, J/j boundary injection, connectives |
| T2 | 157 | 10 B | `{flags16, pat_off, act_off}` | Core verb phrase: modal/aux chains, passive voice, article suppression |
| T3 | 136 | 10 B | `{flags16, pat_off, act_off}` | Embedding structures: relative clauses, that-complements, gerund/inf phrases |
| T4 | 178 | **9 B** | `{flags8, pat_off, act_off}` | Idioms/collocations, negation normalisation, final Z cleanup |
| T5 | 9 | 10 B | `{flags16, pat_off, act_off}` | NP word-order reorder (digit actions); fixed-count termination |
| T6 | 47 | 10 B | `{flags16, pat_off, act_off}` | Extended word-order reorder: longer NPs, hyphenated compounds, verbal negation |
| T7 | 35 | **8 B** | `{pat_off, act_off, flags16}` | NP/PP/VP structural guards — all (none) action |
| T8 | 83 | **8 B** | `{pat_off, act_off, flags16}` | Clause/VP structural guards — all (none) action |

**Phase breakdown:**
- **T1–T4** rewrite tags (grammatical transformation passes)
- **T5–T6** reorder tokens (Russian word-order correction, digit-index actions)
- **T7–T8** validate structure (no-action guards; annotate constituent types for the compiler)

**Record format:** T4 uses a 9-byte record with a 1-byte flags field; T7/T8 use an 8-byte record with flags stored in bytes 6–7 (after the two pointer fields). T1–T3/T5/T6 use the standard 10-byte layout with flags in bytes 8–9.

**Termination:** T1–T4, T6, T7, T8 terminate via a null-pointer sentinel record (`pat_off=0, act_off=0`). T5 uses a fixed-count mechanism: the last record (T5[8]) has `flags=0x0009` encoding the table size; there is no null sentinel after T5.

**Key insight:** Tables T7 and T8 have **no replacement field** (`act_off` is always 0). They are "recognize-and-protect" guards — a match annotates constituent boundaries used by the compiler's inflection stage, but nothing is rewritten.

---

## Rule Edit Workflow

When changing `core/rules.lua`, use this workflow to keep changes auditable and testable:

1. Add or adjust the smallest possible rule entry in the right table (T1-T4 for rewrites, T5-T6 for reorder behavior).
2. Add a short inline comment for each modified/new rule with one English trigger example.
3. Run standard tests from repo root:
  - `./test/run_all.sh`
4. If the change intentionally alters output style/wording, update expectations in `demo/compare.lua` in the same commit.
5. (Optional) If you need LTGOLD parity evidence for a new case, capture once via `LTGOLD/test_compare.sh` and store the resulting expected line.

Note on comment scope:

- `core/rules.lua` has hundreds of extracted rules; adding exhaustive comments to every legacy rule would be very noisy.
- Keep comments focused on touched rules and include a concrete trigger phrase, for example:

```lua
{ 0x00, "`make`[MR]Z", "`заставлять`MV" }, -- Example: "make him go" -> causative verb + object pronoun
```

## Broken-Sentence Repair Playbook

Use this procedure in order. It deliberately separates lexical data, grammatical rules,
and Russian morphology so a visible bad word does not lead to a fix in the wrong layer.

1. **Freeze the failure.** Run `lua init.lua "Sentence."` and copy the exact output.
   Add the intended output to `test/translator_test.lua` before considering the repair done.
2. **Trace the pipeline.** Run `lua init.lua "Sentence." --debug=2`. Read these sections:
   `Lookup` shows the packed dictionary entry, `Applying` shows matching rules, `Tokens after
   rules` shows the tag selected for every word, and `Compiler output` shows paradigm, gender,
   and case decisions.
3. **Inspect every suspicious English entry.** Run `lua demo/dict.lua find WORD`. Do not erase
   valid alternate parts of speech merely because the current sentence needs one sense.
4. **Inspect the Russian lemma.** Run both `lua rus_tool.lua find LEMMA` and the same command
   with the corrected spelling. A declinable `N`, `V`, or `A` needs a matching `.RUS` record.
   For Russian words containing `ё`, use `ё` consistently in both `.DIC` and `.RUS`; otherwise
   lookup and stem cutting operate on different byte strings.
5. **Choose the owning layer.** Wrong English meaning or lemma: edit `.DIC`. Correct lemma but
   wrong gender/paradigm: edit `.RUS`. Wrong tag after parsing: add the smallest rule in T1-T4.
   Correct tag but wrong generated ending: repair the table-driven paradigm/compiler behavior.
6. **Add a narrow rule.** Put tag rewrites in the existing table whose neighboring rules solve
   the same ambiguity. Preserve order, add one comment with the trigger and reason, and avoid
   English-word literals when a grammatical pattern describes the case. If the rule is not
   extracted from LTGOLD, label it as a custom fallback and name the missing LTGOLD table or
   flag semantics that should eventually replace it.
7. **Edit dictionary data with its tools.** For a packed multi-sense entry, first copy the full
   value printed by `find`, change only the faulty component, then use `add ... --force`. Add or
   replace the corresponding `.RUS` entry with `rus_tool.lua`. Run both `find` commands again
   to verify the stored spelling and binary metadata.
8. **Verify at three levels.** Re-run the single sentence with `--debug=2`, run the focused test
   (`lua test/translator_test.lua`), then run `./test/run_all.sh`. The trace must show the intended
   rule firing, the intended final tag, and the intended `.RUS` lemma/paradigm—not merely a lucky
   output string.

### Worked example: “The cat sat on the mat.”

This is the exact repair sequence used for this sentence. Follow the phases in order; each
phase answers a different question and identifies the file that owns the defect.

#### Phase 1 — Reproduce and define the target

Run:

```sh
lua init.lua "The cat sat on the mat."
```

Before the repair, the result was:

```text
Кошка посиденная на ковере{1.матрицаAматовый}.
```

The target was fixed explicitly as:

```text
Кошка сидела на ковре.
```

This immediately identified three observable defects: `sat` was not a finite past verb,
`ковере` was the wrong inflection, and unrelated meanings leaked into `{...}`.

#### Phase 2 — Trace lookup, rule phases, and compilation

Run:

```sh
lua init.lua "The cat sat on the mat." --debug=2
```

The important pre-fix trace was:

```text
Lookup: cat → Nкошка
Lookup: sat → Eсидеть\sit
Lookup: on  → PПнаpРот
Lookup: mat → ZVспутыватьNковер;матрицаAматовый
Tokens after rules: T Nкошка Eсидеть\sit PПна T Nковер;матрицаAматовый .
```

The phase diagnosis was:

- Dictionary lookup correctly found `sat`, but classified its irregular past form as `E`,
  which is ambiguous between simple past and participle.
- No rewrite phase resolved this particular `N E P` clause shape to a finite predicate.
- The compiler's postnominal `E ... P` fallback consequently selected a passive/adjectival
  reading and changed imperfective `сидеть` to `посидеть`, producing `посиденная`.
- The generic T2 `Z`-to-`N` rule selected the noun section of `mat`, but retained its following
  `матрица` and adjective data, which the compiler printed as alternatives.
- `.RUS` lookup found only `ковер`, masculine paradigm 1. That paradigm appends the locative
  ending without removing the alternating vowel, producing `ковере`.

#### Phase 3 — Inspect and correct lexical data

The exact inspection commands were:

```sh
lua demo/dict.lua find mat
lua rus_tool.lua find ковер
lua rus_tool.lua find ковёр
```

The `mat` entry contained legitimate verb, noun, matrix, and adjective senses, so replacing it
with a noun-only entry would have broken other sentences. Only the rug lemma was corrected:

```text
before: ZV.спутыватьN.ковер{rug};матрица{matrix}A.матовый
after:  ZV.спутыватьN.ковёр{rug};матрица{matrix}A.матовый
```

The packed entry was updated with:

```sh
lua demo/dict.lua add mat \
  'ZV.спутыватьN.ковёр{rug};матрица{matrix}A.матовый' --force
```

Because `ковёр` is declinable, a matching `BASE.RUS` record was required. Masculine paradigm
30 removes two stem letters and supplies `ра/ру/.../ре`, handling the alternating nominative
vowel: `ковёр → ковра → ковру → ковре`.

```sh
lua rus_tool.lua add ковёр N:m:30 --force
```

The verified metadata is `N`, masculine, paradigm 30, binary code `4E 00 01 1E`.

#### Phase 4 — Select the lexical sense in T2

Sense selection must occur before the generic T2 `T<H%D,>Z → @$N` rule converts `mat` from
its packed `Z...` entry into an `N...` token. After that conversion, the original English-word
identity is no longer available to a literal rule.

The following rule was therefore inserted immediately before the generic T2 rule:

```lua
{ 0x00, "PT`mat`", "..`Nковёр`" },
```

For `on + the + mat`, `P` and `T` remain unchanged (`.` and `.`), while the third token becomes
the single literal `Nковёр`. This keeps all dictionary senses available globally but prevents
`матрицаAматовый` from leaking in this context.

#### Phase 5 — Resolve the predicate in T4

T4 is the final tag-rewrite/ambiguity-cleanup phase, so the finite-past decision belongs there.
The smallest grammatical shape that describes the failure is subject (`N` or `R`), ambiguous
past form (`E`), then preposition (`P`):

```lua
{ 0x00, "[NR]EP", ".1" },
```

The first replacement `.` preserves the subject. The custom replacement `1` changes the
matched `Eсидеть\sit` token into `V1сидеть\sit`. `V1` is an internal resolved-simple-past
marker; it is deliberately separate from the legacy `V` replacement so this repair does not
silently activate unrelated extracted E-to-V rules.

The parser implements `1` in `replace()` and the compiler's `V` printer removes the marker,
sets `e.past` while conjugating, then clears it. Subject gender was already set by `Nкошка`, so
the generated past form is feminine `сидела`.

#### Phase 6 — Correct the verb paradigm data typo

The first generated result was `сидeла`, with a Latin `e`. Inspection of verb paradigm 60
found the extracted past suffix `дeл`; it was corrected to Cyrillic `дел` in
`core/paradigms.lua`. This is a paradigm-data correction, not a sentence-specific compiler
condition, because every verb using that extracted row needs Cyrillic output.

#### Phase 7 — Add and run the regression

The public translator regression in `test/translator_test.lua` is:

```lua
local cat_output = assert(engine:translate("The cat sat on the mat."))
assert(cat_output == "Кошка сидела на ковре.", cat_output)
```

Final verification commands:

```sh
lua demo/dict.lua find mat
lua rus_tool.lua find ковёр
lua init.lua "The cat sat on the mat." --debug=2
lua test/translator_test.lua
./test/run_all.sh
```

The final trace must show these exact milestones:

```text
T2 Applying: PT`mat`  ..`Nковёр`
T4 Applying: [NR]EP  .1
Tokens after rules: T Nкошка V1сидеть\sit PПна T Nковёр .
N: word=ковёр paradigm=30 gender=1 form=6
Кошка сидела на ковре.
```

---

## Pattern Syntax

### Token Types (in order of priority)

| Syntax | Name | What it matches |
|--------|------|-----------------|
| `` `word` `` | literal | Exact English word match against dictionary entry |
| `[chars]` | select | A single token whose grammatical tag starts with ANY char in the brackets |
| `<chars>` | any-match | Zero or more consecutive tokens, each matching one of the chars (lazy) |
| `*` | boundary | Position at start (`j==1`) or end (`j>#ts`) of token stream |
| `~` | negate | Prefix: inverts the immediately following pattern token |
| single char | char | A single token whose grammatical tag starts with that letter |

### Detailed Semantics

**`[chars]` character class** (`parser.lua:132-136`): Matches one token whose tag starts with ANY character in the set. Each bracket pair matches exactly one token.

**`<chars>` any-match** (`parser.lua:137-141`): Matches zero or more consecutive tokens, each matching any char in the set. Lazy (non-greedy): tries zero tokens first. `<$>` matches any token (empty content = wildcard). Tokens matched by `<>` are passed to the replacement via the `$` capture mechanism.

**`*` boundary marker** (`parser.lua:147-149`): Matches a position, not a token. `*` at pattern start → `j==1`; at pattern end → `j > #ts`. Used to anchor patterns to sentence edges.

**`~` negation prefix** (`parser.lua:150-153`): Sets a negation flag for the immediately following token. The match condition is XORed — a token passes if it does NOT satisfy the normal condition.

| Pattern | Negated meaning |
|---------|-----------------|
| `~Z` | Tag is NOT Z |
| `~[bB]` | Tag is NOT b AND NOT B |
| `~<N>` | Token does NOT match N in any-match |
| `` ~`be` `` | English word is NOT "be" |
| `~?` | Tag is NOT `?` (not an unknown word) |

**`?` unknown token** (`parser.lua:154-156`): Matches a token whose tag starts with `?` (word not in dictionary).

**Single-letter chars**: A standalone letter matches a token whose first tag character equals that letter.

### Special Characters in Patterns

| Symbol | Meaning |
|--------|---------|
| `#` | Untranslatable unit / proper noun / designation |
| `\|` | Clause boundary marker in token stream |
| `*` | Sentence boundary (start or end) |
| `?` | Unknown word (not in dictionary) |
| `-` | Hyphen in compound words |
| `'` | Apostrophe / possessive marker |
| `"` | Quote mark token |
| `:` | Colon punctuation token |
| `,` | Comma punctuation token |
| `( )` | Optional/alternative substructure |
| `{ }` | Alternative grouping |
| `^` | Word-join or boundary marker |
| `=` | Case-equality operator |
| `;` | Subordinate clause separator |
| `&` | Coordination marker |
| `+` | Rare; possible word-join modifier |
| `%` | Modifier flag for digit patterns (`<H%D,>`) |
| `!` | Inline CP866 Russian literal injection (e.g. `!мес!` = "месяц") |
| `_` | Underscore placeholder field (template fill-in) |
| `` ` `` | Literal English word match |
| `$` | Capture marker inside `<$>` — paired with replacement stream |

---

## Replacement Syntax

(`parser.lua:167-225`) — replacement characters map per matched position via `find_and_replace(ts, j, replacement_char)`.

| Char | Effect |
|------|--------|
| `' '` (space) | Suppress token output (set to `" "`) |
| `.` | Keep token unchanged (no-op) |
| `$` | Keep token unchanged; also consumed from replacement by `<>` spans |
| `@` | Apply grammatical transform using the PATTERN character at that position |
| any other char | Transform token to target tag via `find_and_replace` |

### `find_and_replace()` (`parser.lua:205-225`)

```lua
function find_and_replace(ts, j, target_tag)
  local w = ts[j]
  if w:sub(1,1) == 'Z' and target_tag ~= 'Z' and target_tag:find('[VNA]') then
    local _,_,prefix = w:find('(.-)'..target_tag)
    ts[j] = target_tag .. prefix
  else
    local _,_,prefix = w:find(target_tag..'(.*)')
    if prefix then ts[j] = target_tag .. prefix end
  end
end
```

String-level transformation: finds the first occurrence of the target tag letter in the token string and splices from there. For Z-ambiguous tokens it specifically resolves to V, N, or A. Actual morphological inflection (declension, conjugation) happens later in `compiler.lua`.

### Replacement Special Characters

| Char | Meaning |
|------|---------|
| `@` | Apply transform using pattern char |
| `$` | Back-reference to `<>` captured span |
| `` `word` `` | Insert literal Russian word (CP866) |
| `^` | Word-join operator |
| `=` | Case-setting operator |
| `j` | Insert comma |
| `;` | Clause continuation marker |
| `\|` | Insert clause-boundary separator |
| `&` | Coordination operator |
| `+` | Compound modifier |
| `{ }` | Brace-wrap output |

---

## Tag Reference

Source: `dic.txt` (SARMA 2.0 Russian documentation). Note: `#`, `|`, `*` meanings differ between dictionary context and rule-pattern context.

### Uppercase Tags

| Tag | Meaning | Notes |
|-----|---------|-------|
| `A` | Adjective, ordinal numeral | |
| `B` | Infinitive particle 'to' (perfective verb) | NOT the copula — `X` is auxiliary 'be' |
| `C` | Coordinating/disjunctive conjunction ("and", "but", "or") | |
| `D` | Adverb, parenthetical word/phrase | |
| `E` | -ed verb forms and irregular variants | Past participle / simple past |
| `F` | Active present participle — generated by analyzer | Maps to `passive()` printer (possible mismatch) |
| `G` | -ing verb forms | Gerund / present participle |
| `H` | Any digits and combinations | Numeric token |
| `I` | Cardinal numerals | |
| `J` | Conjunctions, phrase-boundary separators | Subordinating conjunction / complementizer |
| `K` | Negative particle 'not' | |
| `L` | Relative word meaning ', который' (which/who) | Resolved relative pronoun |
| `M` | Indirect pronoun | Object pronoun ("him", "her", "them") |
| `N` | Singular noun | |
| `O` | Demonstrative pronoun | ("this", "that", "these") |
| `P` | Preposition | |
| `Q` | Question word | Interrogative |
| `R` | Personal pronoun | ("I", "you", "he") |
| `S` | Demonstrative pronoun (second class) | See S vs O note below |
| `T` | Determiner (article) | Maps to `separator()` → empty output |
| `U` | Modal verb | ("must", "can", "shall") |
| `V` | Main (content) verb | Finite predicate |
| `W` | Multi-word phrase boundary marker | Inserted by T3; `is()` matches ANY class letter |
| `X` | Auxiliary verb 'be' | (is/are/was/were) |
| `Y` | Auxiliary verb 'have' (possession sense) | Perfect auxiliary |
| `Z` | Ambiguity V-N-A | Unresolved word: verb, noun, or adjective |

### Lowercase Tags — "Already Processed" Markers

Lowercase counterparts indicate the token's category has been resolved by an earlier rule pass.

| Tag | Meaning |
|-----|---------|
| `a` | Sub-class of adjective-adverbs ("more", "less") |
| `b` | Infinitive particle 'to' (imperfective verb) |
| `d` | Adverb/adjective ambiguity |
| `e` | Coincidence of infinitive / past participle / past tense forms |
| `f` | Determiner-expression (followed by a noun phrase) |
| `k` | Negative particle 'no' (vs `K` = 'not') |
| `l` | Movable relative word 'whose' — generated by analyzer |
| `m` | Compound indirect pronoun |
| `n` | Plural noun |
| `o` | Likely lowercase of `O` (demonstrative) |
| `r` | Compound personal pronoun ("myself", "yourself") |
| `s` | Lowercase of `S` (demonstrative variant) |
| `t` | Determiner — segment boundary marker, generated by analyzer |
| `u` | Modal verb combination ("had better", "ought to") |
| `v` | Verb form in -s/-es (3rd person singular present) |
| `w` | Genitive chain marker — inserted by T2/T3 for genitive/possessive modifier |
| `x` | Impersonal verb combination ("there is", etc.) |
| `y` | Auxiliary verb 'have' (existential/copular sense) |
| `z` | Ambiguity v-n (3sg-s form could be noun or verb) |

### Notes on Commonly Confused Tags

- **`B` is NOT the copula** — it is the infinitive particle 'to'. The actual auxiliary 'be' is `X`.
- **`K` = 'not'** (negation), `k` = 'no'. Both appear as negation carriers in patterns.
- **`H` = any digits**, not possessive/genitive.
- **`D` = adverb / parenthetical**, not do-support auxiliary.
- **`M` = indirect object pronoun** ("him", "her", "them"), not adverbial modifier.
- **`Z` vs `V`**: `Z` = unresolved V-N-A ambiguity; rules promote `Z` → `V`/`N`/`A` by context.
- **`S` vs `O`**: Both demonstratives; likely `S` = attributive ("this book"), `O` = standalone ("this one").
- **`B` vs `b`**: `B` = 'to' before perfective verb; `b` = 'to' before imperfective verb.
- **`W` tag**: Multi-word phrase boundary marker. The `is()` function has a special case — W-tagged tokens match ANY class letter, so `W` won't block any pattern match.
- **`w` tag** (lowercase): Genitive chain marker. Used in T5/T6 reordering patterns like `NwNw` → Russian genitive-first order.

---

## Flag Semantics (Constituent-Type Index)

The flags field in every rule record is a **constituent-type identifier** — it tells the compiler what syntactic phrase was matched, so it knows how to apply Russian morphology (case, agreement, inflection) to the matched span.

**Confirmed by binary patching:** Patching T7[0] flags `0x0002 → 0x0014` changes "доме" → "дом" (prepositional → nominative). Patching T8[13] flags `0x0025 → 0x0000` changes "говорит" → "говорить" (finite → infinitive). Full experimental results are in [work/REPORT.md](../work/REPORT.md).

**`0x003F` (all 6 low bits set)** = full clause / sentence-level wildcard. Both T1[2] `*~<UVXY>Z*` and T8[12] `L[RN]<$>p*` use `*` anchors and carry this flag.

**`0x0000`** = no constituent typing. Most T1–T4 rewrite rules carry this; they transform a tag, so the compiler only needs the resulting tag.

**Higher flags = larger/more complex constituents.** T8 exclusively holds flags above `0x001F`.

| Flag | Constituent type (from T7 patterns) |
|------|--------------------------------------|
| `0x0000` | No inflection grouping (compounds, bare pairs) |
| `0x0002` | PP — prepositional phrase |
| `0x0003` | VP with modal |
| `0x0004` | AP / participial phrase |
| `0x0005` | Participial + NP |
| `0x0006` | Full NP |
| `0x000B` | Verb + object pronoun |
| `0x000C` | Interrogative NP |
| `0x0013` | Coordinated VP |
| `0x003F` | Full clause / sentence-level |

**Special case:** T5[8] flags=`0x0009` encodes the table size (fixed-count termination), not a constituent type.

<!-- TODO: Document what ^, =, ;, & do exactly in replacements.
     Confirm whether same flag index means the same constituent type across all tables (T2/T4 vs T7/T8).
     Determine T5/T6 digit action semantics — are they 1-based position indices?
     Document T6's 47 rules and which overlap with T5/T7. -->
