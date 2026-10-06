# LTPRO / LTGOLD comparison — 2026-10-06

The production translator is **not yet one-to-one** with either executable.
Recovered grammar and morphology data now match LTPRO. Isolated Lua ports of
reordering and four morphology helpers pass instruction-level comparisons against
**both** binaries. The parser/compiler still needs native lexical state, general
matchers, handler bodies, and orchestration.

Project agent instructions were removed. Older research is reference material to
recheck. No DOSBox or new packages were installed. The optional verification tools
use already available Python/Capstone; runtime and extraction remain pure Lua.
Neither `LTGOLD/` nor the reference `open-rts` project was modified.

## Targets

| Supplied file | Bytes | SHA-256 |
|---|---:|---|
| `LTGOLD/LTPRO.EXE` | 207714 | `6a2036c2fbc629d0317bf02acbb1e6ebd82ceecb2d11f609c6460cc0c32dc4fe` |
| `LTGOLD/LTGOLD.EXE` | 391456 | `2ced94827fb8d86433feda3dce8b2ae06cc7a151d8b4aa6e3d59e14632971e45` |
| `LTPRO.ORIG.EXE` / `LTPRO.OLZ` | 88248 | `6be9c687299c4bc40e12308f99482ef60d37799bc4d7c772e11ff8d3a388ba53` |

The targets are the supplied unpacked MZ images. Equivalence to packed originals
has not been re-established; `LTPRO.PAT.EXE` is not the reference.

Addresses below are zero-based file offsets. Far pointers resolve as
`MZ_header_bytes + segment*16 + offset` before DOS relocation. LTPRO's header is
`0x3A00`, DS is `0x22D5`, and its data file base is `0x26750`. LTGOLD's header is
`0x6900`, DS is `0x4A06`, and its data base is `0x50960`. Locations were resolved
separately; a blanket offset conversion is unsafe.

## Grammar extraction

| Block | LTPRO offset | LTGOLD offset | Records | Bytes/record |
|---|---:|---:|---:|---:|
| T1 | `0x2738C` | `0x5168E` | 47 | 10 |
| T2 | `0x2756C` | `0x5186E` | 157 | 10 |
| T3 | `0x27B98` | `0x51E9A` | 136 | 10 |
| T4 | `0x2952C` | `0x5382E` | 178 | 9 |
| T5 portion | `0x2A740` | `0x54B4A` | 9 | 10 |
| T6 portion | `0x2A79A` | `0x54BA4` | 47 | 10 |
| Cleanup | `0x2AB30` | `0x54A42` | 9 | 10 |
| T7 | `0x2AC92` | `0x54F94` | 35 | 8 |
| T7 adjective alternate | `0x2ADB2` | `0x550B4` | 1 | 8 |
| T8 | `0x2B134` | `0x55436` | 83 | 8 |
| Analyzer suffixes | `0x26EC6` | `0x511B8` | 43 | 10 |

Ten-byte grammar records contain pattern/action far pointers and a u16 handler.
T4 contains the two pointers followed by a u8 handler. Its old extraction began
one byte early, corrupting 108 handler IDs. The runtime loads its true start at
`0x14954` and reads record+8 at `0x149BF`.

Eight-byte guards contain a pattern pointer, u16 scalar, and u16 handler. T7's
scalar exchanges endpoints (`0x17F29–0x17F95`); it is saved as `endpoint_order`.
T8's scalar is preserved too, but its use needs separate verification.

`core/rules.lua` is generated and matches **702/702 LTPRO records**, including the
alternate adjective table. All **43/43 suffix records** match. Five custom rules
were removed: the `mat` rewrite, `[NR]EP -> .1`, and existential permutations
`yTAAND`, `yTAND`, `yTND`. The custom `.1` replacement behavior was also removed.

`core/ltpro/dispatch.lua` records 410 selector-to-address entries. These are
table-specific handler selectors, not priorities or universal constituent types.
`core/ltpro/guards.lua` implements the T7 class switch: A selects the alternate
table, 18 other classes select the main table, and other inputs select neither.
This selection helper is not yet integrated into the legacy parser.

### The source binaries differ

**701/702 grammar records** are identical between LTPRO and LTGOLD. T1 record 26
(zero-based) has pattern ``*<dD,>`if`~<,>`then` `` in both, but different actions:

| Target | Location | Action |
|---|---:|---|
| LTPRO | `0x27490` | `@$J$j` |
| LTGOLD | `0x51792` | `@$j$P` |

Supplied LTGOLD backup variants have the same LTGOLD action. Whether this reflects
a version change or a patch is unknown. Generated runtime grammar currently targets
LTPRO. `demo/compare_binaries.lua` deliberately exits 1 for this difference.

## Morphology extraction

Each record contains a u16 stem-cut length and a far pointer to CP866 suffix text.
These arrays are followed by other pointer arrays, not zero sentinels.

| Table | LTPRO offset | LTGOLD offset | Records |
|---|---:|---:|---:|
| Neuter nouns | `0x2BCF6` | `0x55FF8` | 33 |
| Masculine nouns | `0x2B988` | `0x55C8A` | 66 |
| Feminine nouns | `0x2BBA0` | `0x55EA2` | 35 |
| Neuter adjectives | `0x2BF5C` | `0x5625E` | 26 |
| Masculine adjectives | `0x2BE24` | `0x56126` | 26 |
| Feminine adjectives | `0x2BEC0` | `0x561C2` | 26 |
| Imperfective verbs | `0x2C1A0` | `0x564A2` | 106 |
| Perfective verbs | `0x2C5E0` | `0x568E2` | 113 |

All **431/431 records** match between binaries and the generated
`core/ltpro/morphology.lua`. Nouns were already correct. Adjective suffixes were
correct but lost their cut field; 36 entries do not cut two bytes. The imperfective
list skipped placeholders, shifted indices, and eventually included unrelated
spelling patterns. It is regenerated with all placeholders and cut lengths.
Perfective record 60's manually corrected Cyrillic `е` in `дeл` is restored to the
original Latin `e`.

The production morphology module consumes these generated records, including
adjective and imperfective cuts. Its higher-level behavior remains legacy code.

## Executable logic ports

### Reorder pass

`core/ltpro/reorder.lua` ports LTPRO `0x1619D` / LTGOLD `0x1CAD8`, including vector
construction, 13 handler predicates, one 56-rule T5/T6 scan, exact tag matching,
first eligible match, span advancement, swaps, linked-node updates, and cleanup.
`nodes.lua` retains numeric field offsets for state whose full meaning is unknown.

Numeric actions are sequential swaps. `3455` on ABCDE yields CDEAB; the old parser
produced CDEEA, duplicating E and losing B. Handler 2 changes the final tag to A
and does reorder; the legacy W shortcut that skips it is not original behavior.

The production parser now uses live swaps and the combined position-first scan,
fixing repeated reordering of `buyer-seller agreement`. It **still uses legacy W
matching and incomplete predicates**; it does not call the full native node pass.
Sparse token metadata is shifted and swapped alongside tokens.

### Morphology helpers

`core/ltpro/inflect.lua` ports these functions with CP866 input and output:

| Helper | LTPRO | LTGOLD |
|---|---:|---:|
| Noun | `0x223BC` | `0x28DCC` |
| Adjective | `0x22530` | `0x28F40` |
| Finite verb | `0x2270B` | `0x2911B` |
| Participle / gerund | `0x22A87` | `0x29497` |

They preserve native indices, aspect-table selection, null returns for missing
forms, literal space splitting, `=` handling, reflexive endings, irregular past
transformations, tense/imperative/subjunctive/question flags, and the original
short-stem truncation quirk. Nominative singular bypass belongs to the noun caller.

These raw helper ports are **not yet the public compiler implementation**. Caller
flags, aspect switching, passive state, and fallback behavior must be recovered
before replacing the legacy wrappers wholesale.

### Differential verification

The probes load each actual MZ payload into a bounded 8086 interpreter and invoke
original functions on controlled fixtures. Only C string primitives and free are
substituted; grammar decisions, vector building, swaps, suffix tests, and morphology
execute original instructions. Unsupported instructions fail.

The reorder corpus covers every recovered pattern, compaction, and 300 deterministic
randomized states: **358/358 pass per binary**, executing 3,143,794 instructions each.
The morphology corpus covers every table row plus 400 randomized
fixture groups: **7,029 cases pass per binary**, executing 1,664,261 instructions each.

These are isolated function checks, not complete DOS execution, independent CPU
conformance proofs, or exhaustive translator proofs. Allocator effects, startup,
I/O, and surrounding parser state are outside the harness. No new full-program
translation captures were made.

Evidence: [grammar instructions](LTPRO_EVIDENCE.asm) and
[morphology instructions](LTPRO_MORPHOLOGY.asm).

## Translation checks

Historical comparisons use original `LTGOLD/BASE.DIC` and `.RUS`, preserving
translation spelling, capitalization, and punctuation. They exclude capture line
endings and the separate meanings appendix. Capture binary/config provenance is
incomplete; these are historical observations, not fresh full-program results.

Exact matches improved from **3/10 to 5/10**. Restoring Latin `e` fixed the `She sat
on the chair.` and `The dog that I saw ran away.` comparisons. Five gaps remain:

| Input | Historical capture | Current Lua |
|---|---|---|
| She can speak Russian. | Она может сказать Русского. | Она может говорить русского. |
| He must not go. | Он не должен придти. | Он не должен идти. |
| He was arrested by the police. | Он арестовывался полицией. | Он арестован полицией. |
| The house door is open. | Дверь{1.вход} дома открыта. | Дверь{1.вход} дома должен открывать. |
| He cannot go. | Он не может придти. | Он не может идти. |

The 25-case Lua regression passes, but mixes historical and preferred-natural
expectations. `test/translator_test.lua` still fails its custom `cat sat on the mat`
expectation after removal of unsupported rules. Its expectation was not changed to
the current incorrect output. The standard runner therefore still exits nonzero.

## Remaining work

1. Native lexical-node construction and dictionary metadata/alternative handling.
2. General matcher and replacement operators (`!`, `$`, `=`, `;`, etc.).
3. T1–T4, cleanup, T7/T8 handler bodies, scheduling, and constituent links.
4. Caller-level aspect, passive/copular state, case, and agreement.
5. Complete analyzer spelling changes, capitalization, and output formatting.

Morphology call sites identify +0x72 as plurality, +0x75 as aspect selection, +0x77
as gender, +0x78 as verb flags, and +0x85 as paradigm ID. Recovering their writers
connects verified helpers to the pipeline. Project BASE dictionaries differ from
supplied files, and the loader normalizes records; these also need parity checks.

Reproduction commands and current checks: [TESTING.md](../TESTING.md).
