# LTPRO / LTGOLD rule language reference

This guide explains how to read the extracted rules, with examples for people and
agents investigating or editing them. **We have recovered all 702 records in the
known grammar tables, but have not decoded every operator and handler.** A matching
data dump is not proof that the Lua translator executes every rule like LTPRO.

The examples below distinguish four kinds of evidence:

- **Manual:** grammatical meanings documented in the supplied SARMA `LTGOLD/dic.txt`
  (CP866), especially Appendix 1.
- **Native:** behavior recovered from executable instructions. The isolated reorder
  implementation has also been checked against original instructions in both binaries.
- **Lua:** behavior implemented by the recovered Lua engine.
- **Unresolved:** a spelling or use is known, but its complete native meaning is not.

The current baseline is **LTPRO**. The native matcher/replacement ports described
below share `core.matching` and run in the production engine. LTGOLD differs in one recovered grammar record;
see [the comparison and evidence](../reference/LTPRO_COMPARISON.md). This reference
supersedes the older syntax and “flag” explanations previously in this file.

Jump to: [worked example](#start-here-what-does-zvn---nn-mean),
[native semantics](#verified-native-matching-and-replacement),
[tags](#grammatical-tag-dictionary), [actions](#replacementaction-notation),
[symbols](#punctuation-and-symbols-what-they-do-not-mean),
[reordering](#reordering-t5t6-digits-are-sequential-swaps),
[editing rules](#editing-or-cleaning-up-rules-without-losing-the-baseline).

## Start here: what does `Z[VN] -> NN` mean?

This is an **illustrative rule**, not a claim that this exact record occurs in the binary:

```text
Pattern:       Z       [VN]
Token slot:    1         2
Read as:       ambiguous word, then one word matching V or N
Action:        N         N
Read as:       change each matched node’s current tag to N
```

`Z` means an unresolved verb/noun/adjective reading. `V` means a content verb;
`N` means a singular noun. `[VN]` occupies **one** token slot and means “V or N.”
Thus the pattern covers two tokens, not three, and `NN` supplies two actions.
The arrow is explanatory notation; it is not stored in the rule string.

**Native behavior:** `Z V` or `Z N` matches, then both current tags become N.
Each changed node saves its previous tag at offset `0x66`. The replacement routine
does not search the dictionary or invent a noun translation: it changes state that
later handlers and output routines interpret. A grammatical tag and the stored
translation text are separate fields.

**Legacy Lua behavior differs:** for packed input `ZработатьNработа`, `Nплан`, its
resolver can select `Nработа`, `Nплан`. A pure V token without an N reading may remain
unchanged there. This is an implementation gap, not the native definition of `NN`.

A Lua record would also need a **table and a handler ID**:

```lua
-- Illustrative only: do not add this to the extracted baseline.
{ 0x00, "Z[VN]", "NN" }
```

The handler is part of the behavior, not decorative metadata. `0x00` is not a
universal “no special processing” guarantee across all tables.

## Three things that must not be confused

| Layer | Example | Meaning |
|---|---|---|
| Dictionary record | `work*ZработатьNработаAрабочий` | English lookup key, dictionary separator, then packed Russian readings. |
| Token stream | `T`, `Z`, `N` | Separate analyzed words, each carrying lexical text and other state. Spaces here are explanatory. |
| Grammar pattern/action | `T<H%D,>Z` → `@$N` | Match a token sequence, then apply aligned instructions and the table's handler. |

Rules operate on analyzed tokens, not English letters or Russian substrings in a
sentence. A single word can carry several readings. In the current Lua generic
matcher, a class match can find a secondary reading inside that packed token; it
is not always just a test of its first byte. The native reorder matcher, in
contrast, compares the current tag exactly.

Tags are case-sensitive: `N` and `n`, `V` and `v`, `K` and `k` have different meanings.
Lowercase does **not** uniformly mean “already processed.” Russian payloads are
CP866 internally; the generated Lua rule text is UTF-8 and replacement literals
are encoded before entering the token stream.

## Verified native matching and replacement

Recovered directly from the supplied LTPRO image and checked by executing its
instructions. These routines take zero-based native node indices, including real
boundary nodes. They return the last matched index, or zero on failure. Returning
zero is consequently ambiguous for a successful match ending at node zero; callers
use the original convention.

### Lexical matching: T1–T4, cleanup and T7

[The lexical matcher port](../core/matching.lua) implements the notation used
by the recovered tables. The executable's routine is at file offset `0x17597`.

| Pattern | Confirmed operation |
|---|---|
| `N`, punctuation, or another ordinary character | Compare with the node's **current tag byte**, offset `0x0C`. Embedded dictionary alternatives do not count. |
| `*` | Compare with an actual `*` boundary node and consume it. It is not a zero-width anchor in the native routine. |
| `[VN]` | Consume one node whose current tag is V or N. |
| `~[VN]`, `~N` | Negate the next class or ordinary-tag test. |
| Backticked `word` | Compare with node string `+0x12` ignoring **ASCII** case, or with `+0x9C` using exact bytes. This does not use packed dictionary-value equality. |
| `!text!` | Search node text `+0x11C` for `text)` with a closing parenthesis appended. `!мес!` searches for `мес)`. Negation reverses this test. |
| `<D>V` | Locate the first following V anchor in the tag cache; require every intervening tag to be D, then consume the anchor too. The span may be empty. |
| `<DA>[VN]` | Locate the first cached tag in the anchor class, then check the intervening tags against D/A. |
| ``<D>`word` `` | Locate the first node matching the lexical word test; check intervening cached tags against D. |
| `<D>!text!` | Locate the first node whose text contains `text)`; check intervening cached tags against D. |
| `<$>V` | Locate the anchor without restricting the intervening tags. The search uses the cached tag string. |
| `<>V` | An empty span class also imposes no intervening-tag restriction in this native routine. |
| `~<D>V` | Intervening tags must exclude D, and the span **must not be empty**. |
| Bare `$` | Try the remainder of the pattern at the current position recursively; if it fails, skip one node and try the remainder once more. It is not an arbitrary-length wildcard. |
| `[$]` | Accept one node without a tag test. This special path preserves pending negation rather than clearing it. |

The supplied `BASE.DIC` confirms the meaning of the `мес)` marker: for example,
`april*Nмес)апрельAапрельский` and `june*Nмес)июньAиюньский` mark month readings.
Thus the real `NI!мес!` pattern checks N, then I, then a token whose stored text
contains the month marker. It does not match the literal English word “мес”.

The search is not regex backtracking: once the first anchor is located, a failed
span restriction or later pattern test does not retry at a later anchor. For
example, `N<$>V[N]` fails on `N V D V N`: it finds the first V, then fails the N test
at D rather than retrying the second V.

A plain anchor can be a whole consecutive tag string. `N<D>VAN` searches for the
first `VAN` substring and advances across all three anchor nodes. The split points
used by the native helper are backtick, `~`, `<`, `[`, and `!`. These mechanics,
including empty-span behavior, are implemented rather than translated into a regex.

Ordinary matches read current node tags, whereas span searches use a separate
cached tag string at `DS:C5AE`. The port accepts that cache separately so intermediate
states in which it differs from the nodes can be reproduced.

### Native replacement actions

[The replacement port](../core/matching.lua) implements file offset
`0x16CE4`. Its return value indicates whether a space action requested subsequent
vector compaction. A space does not remove the node immediately.

| Action | Confirmed operation |
|---|---|
| `N`, `V`, `j`, `&`, `#`, `^`, `=`, `;`, braces, other ordinary bytes | Save the current tag to `+0x66`; write the action byte to current tag `+0x0C` and its cached position. These are not no-ops or dictionary-selection requests. |
| `@` | Keep the current node, including its previous-tag field. It does not resolve a lexical reading. |
| `.` | Keep one node while advancing the pattern; it has explicit handling for a negated/class pattern. It is not universally interchangeable with `@`. |
| Space | Write tag space and return the compaction-needed flag. There is no native synthetic `q` future marker in this routine. |
| `$` | Align to the following anchor using the tag cache or lexical/text test. A following plain-tag run has its own action loop, with the positional quirks below. |
| `` `Pк` `` | Save/replace the tag with P and write CP866 `к` to text field `+0x11C`. |
| `` `@к` `` or `` `?к` `` | Keep the tag and replace only text field `+0x11C`. The prefix is not written into the text. |
| `` `к` `` | A leading CP866 Russian letter also keeps the tag and starts the replacement text directly. The native byte classifier accepts `0x80–0xAF` and `0xE0–0xF1`. |

Replacement text is limited to 80 bytes by the original loop. Updating the text
does not replace the entire native node: grammatical state and lexical fields remain.

Two positional details matter for one-to-one behavior:

- In the plain-tag anchor loop following `$`, an `@` or a backticked payload does
  **not** advance the current node. An ordinary tag write does. The port preserves
  this; it does not rebuild output by zipping action characters with all tokens.
- An absent or short action does not imply deleting the remaining match. A rule's
  handler can still perform work independently of its replacement string.

These operations establish what the bytes do, but not every linguistic role of the
resulting internal tags. For example, confirming that `^` writes a tag byte does
not establish all downstream constituent behavior attached to that state.

### T8 uses a constituent view

[The T8 port](../core/matching.lua), file offset `0x1FF05`, reads
12-byte constituent records and a separate tag cache at `DS:C7B6`. The shared interpreter uses a constituent view here. Classes, span anchors, negation and literal boundary tags
have corresponding behavior, but `.` accepts one constituent and preserves pending
negation; bare `$` is an ordinary tag test. `[$]` is also an ordinary class there.
None of the 83 recovered T8 patterns contains a lexical-word test.

### Verification limits

The probes cover every recovered general/T8 pattern, representative spans,
positive and negative fixtures, randomized states, and differing node/cache tags.
They compare match endpoints and, for replacements, current tags, saved tags,
text fields and the tag cache. They do not execute the entire translator.

The executable also contains paths for lexical alternatives **inside** `[]` or
`<>`; none of the 702 extracted records uses them. Those paths have extra-slot or
loop-bound dependencies that are not yet modeled. The ports reject these extensions
explicitly. Malformed patterns, native buffer overflows and arbitrary uninitialized
memory are outside the tested input contract. Corpus coverage does not establish every handler branch or every lexical path.

## Grammatical tag dictionary

The following meanings are **Manual** unless another evidence label is shown.
They describe grammatical categories, not every field or action attached to them.
Some categories are analyzer-generated rather than ordinary dictionary entries.

| Tag | Meaning | Reading aid / caveat |
|---|---|---|
| `A` | Adjective or ordinal numeral. | Adjectival reading, not V. |
| `a` | Adjective/adverb subclass. | Manual examples: “more”, “less”. |
| `B` | Infinitive particle “to” with a perfective verb. | A separate particle class, not the verb itself. |
| `b` | Infinitive particle “to” with an imperfective verb. | Distinct from B. |
| `C` | Coordinating or disjunctive conjunction. | Conjunction class. |
| `D` | Adverb, parenthetical word or expression. | Not a determiner. |
| `d` | Adverb/adjective ambiguity. | Unresolved between those readings. |
| `E` | English -ed forms and irregular equivalents. | Do not assume every E is already a passive participle. |
| `e` | Coincident infinitive, participle-II and/or past forms. | Ambiguous verb forms. |
| `F` | Active present participle. | Generated by the analyzer. |
| `f` | Determiner expression followed by a noun phrase. | Not the lowercase version of participle F. |
| `G` | English -ing forms. | Gerund/participle interpretation needs context. |
| `H` | Digits and their combinations. | Numeric token class. |
| `I` | Numeral. | A: ordinal numeral; H: digits. |
| `J` | Conjunctions or phrase-separating words. | A structural grammatical class. |
| `K` | Negative particle “not”. | Different from k. |
| `k` | Negative particle “no”. | Different from K. |
| `L` | Relative word with the meaning “, который”. | Relative construction. |
| `l` | Movable relative word with the meaning “чей”. | Analyzer-generated. |
| `M` | Oblique/object pronoun. | Indirect-case pronoun category. |
| `m` | Compound oblique pronoun. | Compound category, not simply “resolved M”. |
| `N` | Singular noun. | Noun lexical reading. |
| `n` | Plural noun form. | The rules later include `n` → `N`; the native handler also matters. |
| `O` | Demonstrative pronoun. | The manual also calls S demonstrative; it does not establish the complete O/S distinction. |
| `P` | Preposition. | Russian case information can accompany lexical data. |
| `Q` | Question word. | Interrogative class. |
| `R` | Personal pronoun. | Personal-pronoun class. |
| `r` | Compound personal pronoun. | A separate compound category. |
| `S` | Demonstrative pronoun. | Do not assume a universal attributive-versus-standalone split from O. |
| `T` | Determiner/article. | It may be silent in Russian; the tag does not itself mean “delete”. |
| `t` | Determiner marking a segment boundary. | Analyzer-generated. |
| `U` | Modal verb. | Modal class, not “unique verb”. |
| `u` | Modal verb combination. | Multiword modal category. |
| `V` | Content verb. | Not necessarily already finite or conjugated. |
| `v` | Verb form in -s/-es. | Distinct from V. |
| `W` | Composite Russian lexical-phrase marker. **Manual body / Lua.** | Introduces components inside a packed dictionary reading; not a wildcard matching every class. |
| `X` | Auxiliary “be”. | Not an infinitive marker. |
| `x` | Impersonal verb combination. | Manual example: “there is”. |
| `Y` | Auxiliary “have”, possession (“иметь”). | Distinct from y. |
| `y` | Auxiliary “have”, existential/copular sense (“есть”). | Its complete runtime treatment depends on context. |
| `Z` | Verb/noun/adjective ambiguity: V–N–A. | A given word need not have all three readings. |
| `z` | Verb -s / plural-noun ambiguity: v–n. | Documented lexical code, even though absent from the current grammar patterns. |
| `#` | Untranslatable unit: proper name or designation. | It does not exclusively mean a number. |
| `?` | Unknown/unrecognized word. **Lua.** | Seen in extracted patterns; no dedicated definition in the manual's Appendix 1. |
| `\|` | Fictitious separator. | Structural token, not regex alternation. |

### Additional internal tags and unresolved distinctions

All alphabetic characters in the extracted patterns are covered above or here.
The following observations do not establish complete native meanings:

| Tag | What is established | What remains unknown |
|---|---|---|
| `c` | Occurs in T7, e.g. `O[&c]I`. | Its native state meaning; a coordination-related interpretation is only a hypothesis. |
| `g` | Produced by rules such as `*GPH,[TORS]` → `@gPHj`; Lua has a gerund printer for it. | Complete native distinction from G. |
| `i` | Produced by `HCa` → `@@i` and `aN` → `i`; occurs before nouns in guards. | Exact numeric/modifier state and its native effects. |
| `j` | Produced in clause-related rules; Lua writes a bare `j` and prints it silently. | All native boundary effects. It does not simply mean “print a comma”. |
| `p` | Appears in preposition-related rewrites, e.g. `PL` → `p`; Lua aliases its printer to P. | Exact native distinction from P. |
| `s` | Produced by ``A`one` `` → `@s`; also occurs in T4 context tests. | Complete noun-substitute behavior; Lua reuses the S printer. |
| `w` | Appears in composite/modifier contexts, especially `NwN` reorder patterns. | The fields and conditions that create this state. Do not equate it with W. |

Two additional Lua pipeline markers are useful when reading traces: `h` is
normalized to E for the analyzer's historical/irregular-past forms; `q` is a legacy
future/perfective marker injected when suppressing an `X2…` auxiliary. Neither is
an operator in the recovered grammar patterns. In particular, `q` does not prove
that the native engine represents future tense with that tag.

## Replacement/action notation

A replacement is a sequence of **instructions aligned with match atoms**, not a
regular-expression replacement string and not a newly generated tag string.
An entire `[VN]` consumes one instruction; a backticked payload is one instruction.
Boundary/span atoms use alignment instructions. Literal spaces in actions matter.

The verified native-action table above describes the shared production replacement
routine. A short action may leave trailing matched context untouched. An absent
action does not imply an inert rule: its handler can still mutate state.

### Real rewrite examples

The following strings are present in `core/rules.lua`. These explanations describe
alignment and Lua behavior, not proof that the entire native rule is implemented.

**1. Choose a noun after a determiner: `T<H%D,>Z` → `@$N` (T2, handler 0).**

```text
Pattern atom      T         <H%D,>           Z
Action            @           $             N
Role              resolve T   retain span   choose noun reading
Example tags      T           D D           Z
Result tags       T           D D           N   (if the N reading is available)
```

`%` is one of the classes in the extracted pattern, not a Lua pattern escape.
Its full native grammatical meaning is unresolved. The D-only example does not
require assuming a meaning for `%`.

**2. Choose an initial verb: `*<DK,>Z[TAO]` → `@$V` (T1, handler 1).**

The `@` aligns with the boundary, `$` with the span, and `V` with Z. The final
`[TAO]` checks one following determiner/demonstrative/adjective token. There is no
fourth action, so that context token is left alone by the Lua replacement loop.
The native handler numbered 1 must also be considered when reproducing this rule.

**3. Keep the first token: `[RbKk]<D>Z` → `.$V` (T2, handler 0).**

Match R, b, K, or k; cross a D span; select V for the following Z. `.` keeps the
first token without requesting a new reading. `[RbKk]` is one slot, not four.

**4. Resolve an infinitive construction: `bG` → `BV` (T2, handler 0).**

Two pattern tokens and two tag-selection actions: request B for the particle and
V for the -ing form. The rule does not itself spell out the final Russian ending.

**5. Supply a Russian lexical token: `b[TAON#]` → `` `Pк` `` (T4, handler `0x3E`).**

The backticks on the action side hold one replacement payload: tag P plus Russian
“к”. The second matched token is context. Backticks on the pattern side would
instead test an English dictionary word. Handler `0x3E` has additional native
meaning; the payload alone is not a complete specification of the rule.

**6. Parentheses are tokens: `(#)` → `{#}` (T2, handler 0).**

The pattern covers three positions: opening parenthesis, designation, closing
parenthesis. It is not an optional group. The action contains three characters
representing structural changes applied by the native replacement routine.

## Punctuation and symbols: what they do not mean

The same character may have different meanings in a dictionary entry, a pattern,
and an action. This inventory covers the nonalphabetic symbols in the recovered
patterns/actions, excluding characters inside English/Russian literal payloads.

| Symbol(s) | Context and meaning |
|---|---|
| `[` `]` | Delimit a one-token class in a general pattern; no nesting/ranges are implemented by Lua. |
| `<` `>` | Delimit a span class in a general pattern; not less-than/greater-than comparisons. |
| Backtick | Delimits an English lexical test on the left, or a replacement payload on the right. |
| `~` | Negates the next pattern atom, not the rest of the rule. |
| `*` | Native literal boundary-node tag; legacy zero-width boundary; dictionary key/value separator in `.DIC`. Not a repetition suffix. |
| `$` | Native span wildcard, class wildcard, or one-node optional skip depending on context; replacement alignment. See the native tables above. |
| `!` | Native text-field substring test with an appended `)`; `!мес!` searches for `мес)`. |
| `?` `#` | Token classes described above, not optional/wildcard regex operators. |
| `(` `)` | Token/structural markers, not optional or capturing groups. |
| `{` `}` | Structural classes/markers, not alternation groups or repeat counts. Dictionary annotations in braces are a separate format. |
| `\|` | Fictitious separator token, not “or”. Use `[VN]` for a one-token V-or-N match. |
| `+` | Internal class/marker; exact native meaning unresolved. Not “one or more”. |
| `^` | Native tag byte; legacy action currently does nothing. Not the start anchor. |
| `=` `;` | Native tag tests/writes with incompletely decoded downstream effects; legacy actions currently do nothing. Semicolon-separated dictionary meanings are a separate convention. |
| `_` `%` | Classes/markers appearing in native patterns; full native meanings unresolved. Not wildcard/escape syntax. |
| `&` | Native tag test/write; legacy action requests C. Complete native state remains unresolved. |
| `,` `:` `-` `/` `'` `"` | Punctuation/class matches, not regex operators. Slash also has separate uses inside packed dictionary data. Handlers may give punctuation structural effects. |
| `.` | Keep action; also an any-constituent pattern operator specifically in native T8. |
| `@` | Native keep action; legacy match-resolution/alignment action. Not a capture name. |
| Space | Significant suppression action; not harmless formatting. |
| `1` through `6` | Digits used by current native reorder actions; one-based swap positions. |

Lua escaping is a further, separate layer: a quote inside a double-quoted Lua
string must be written `\"`. The backslash is Lua source syntax, not an extra
character in the extracted grammar pattern.

## Reordering: T5/T6 digits are sequential swaps

**Native:** T5 and T6 form one contiguous 56-record scan. At each token position,
rules are considered in stored order. The first eligible match is applied, then
the scan advances past its span. The handler's predicate is part of eligibility.

Their native matcher reads **literal current tags**, not the general pattern
language: `N-N` means exactly N, hyphen, N. Do not add `[]`, `<>`, or backticked
word tests to these tables and expect the general matcher to interpret them.

For an action digit at position i, swap matched position i with the one-based
position named by that digit, using the **already changed** order. This is not a
list of source indices for building a new array.

The real T5 record is `{ 0x00, "NwNww", "3455" }`. Name the five matched tokens
A through E to make their movement visible (these names are not grammatical tags):

```text
Initial order:             A B C D E
Action digit 3: swap 1,3 → C B A D E
Action digit 4: swap 2,4 → C D A B E
Action digit 5: swap 3,5 → C D E B A
Action digit 5: swap 4,5 → C D E A B
```

Similarly, the real T6 `NN` → `2` swaps two nouns. A short digit string does not
delete the remaining positions. T6 `A-N` has an empty action string plus handler
`0x2D`; absence of swaps does not make that record inert.

The [native reorder implementation](../core/reorder.lua) includes the recovered
handler predicates and state updates. The production parser still adapts packed
Lua lexical strings and W phrases approximately. For example, native handler 2
changes the final tag to A and still performs the swaps; the legacy W adaptation
can skip those records. Do not claim full pipeline parity from the swap algorithm.

## Rule records, tables, and handler IDs

The Lua record shape is normally `{handler, pattern, action}`. The first value is
a **table-specific code selector**, not a priority, bit mask, or universal
constituent type. The same number in different tables can select different code.

| Native block | Lua key in `core/rules.lua` | Records | Action format |
|---|---|---:|---|
| T1 | `[1]` | 47 | General replacement or absent action, plus handler. |
| T2 | `[2]` | 157 | General replacement or absent action, plus handler. |
| T3 | `[3]` | 136 | General replacement or absent action, plus handler. |
| T4 | `[4]` | 178 | General replacement or absent action, plus handler. |
| T5 portion | `[5]` | 9 | Reorder digits, plus handler. |
| T6 portion | `[6]` | 47 | Reorder digits/empty string, plus handler. |
| Cleanup | `[7]` | 9 | General replacement or absent action, plus handler. |
| T7 | `[8]` | 35 | Guard scalar and handler; no replacement string. |
| T7 adjective alternate | `["adjective"]` | 1 | Guard scalar and handler; conditional table selection. |
| T8 | `[9]` | 83 | Guard scalar and handler; no replacement string. |
| **Total** | | **702** | Analyzer suffix records are separate. |

For example, this real T7 record is **not** a rewrite to an empty string:

```lua
{ 0x02, "P<$>N", endpoint_order = 0 }
```

It describes a match and dispatches a guard handler. T7's scalar controls endpoint
order for the handler; `endpoint_order = 1` exchanges the endpoints. The caller's
class chooses the main table or the adjective alternate; the alternate is not an
unconditional extra pass. T8's scalar is preserved under the same Lua field name,
but its use requires separate verification. T8 also uses a different native token
representation and matcher. A universal interpretation across T1–T8 is unsafe.

Binary layouts, useful when extending extraction:

- T1–T3, T5/T6 and cleanup: pattern far pointer (4 bytes), action far pointer
  (4 bytes), handler (2 bytes).
- T4: the same two pointers, followed by a **one-byte** handler: 9 bytes total.
- T7/T8: pattern far pointer (4 bytes), scalar (2 bytes), handler (2 bytes).
  The scalar is not an action pointer.

The [dispatch data](../demo/extract_dispatch.lua) records selector-to-code addresses.
It is not a dictionary of fully implemented handler meanings. Storing a handler
ID on a Lua token likewise does not execute the native handler.

## Editing or cleaning up rules without losing the baseline

`core/rules.lua` is generated from the supplied unpacked LTPRO image. Editing a
record there changes the baseline and will be overwritten by regeneration. For
an extraction correction, establish the binary record first and fix the reader
or generator. For a deliberate new rule, use an experimental branch and label it
as custom; the project does not currently provide a separate custom-rule loader.

For every proposed change, record:

1. The target binary/version, table, and record index (state whether zero- or one-based).
2. The full old/new record: handler, pattern, action including spaces, and guard scalar.
3. The intended token-level match, selected readings, and resulting token order.
4. A positive example and a nearby case that must remain unchanged, with the lexical
   alternatives actually available for their words.
5. Evidence for native behavior separately from desired translation improvements.

Do not sort rules, merge tables, remove apparent duplicates by pattern alone,
replace all `@` with `.`, or normalize punctuation without checking execution.
Order, handler, action length, null versus empty action, and endpoint direction
can all matter. A tag rewrite also does not specify Russian case, aspect, agreement,
or final endings by itself; those require handler state and morphology.

Useful checks from the repository root:

```sh
lua demo/audit_rules.lua
sh test/run_all.sh
python3 tools/ltpro_pipeline_probe.py
```

Do not replace references with current output to make tests pass. Extraction
success does not prove execution parity; see [testing](../TESTING.md) for native
instruction checks and captured stage/corpus comparisons.

## Evidence and remaining work

| Source | What it establishes |
|---|---|
| [Generated grammar](../core/rules.lua) and [binary reader](../demo/ltpro_binary.lua) | Exact records, table membership, actions and metadata. |
| Supplied `LTGOLD/dic.txt`, Appendix 1 and dictionary examples | Historical grammatical code meanings; local ignored source, not a complete rule-language specification. |
| [Native lexical matcher](../core/matching.lua), [replacement](../core/matching.lua), and [T8 matcher](../core/matching.lua) | Shared production interpreter for table and memory views. |
| [Native reorder](../core/reorder.lua) and [guard helpers](../core/reorder.lua) | Recovered reorder behavior, T7 table selection and endpoint direction. |
| [Executable evidence](../reference/LTPRO_EVIDENCE.asm) | Selected original instructions supporting the current audit. |
| [Matcher/replacement instructions](../reference/LTPRO_MATCHER_EVIDENCE.asm) | Original routines, string-comparison helpers, and CP866 byte classifier used for the new ports. |
| [LTPRO comparison](../reference/LTPRO_COMPARISON.md) | Binary identities, differences, verified ports and remaining parity gaps. |

The production engine composes these stages. Remaining gaps include unsupported
lexical macros, suffix paths and unused embedded-alternative matcher paths.
Corpus parity is bounded evidence, not proof of complete translation equivalence.
