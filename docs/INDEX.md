# Documentation Index

## Architecture

| Document | Description |
|----------|-------------|
| [Pipeline](pipeline.md) | Translation pipeline: tokenize → parse → compile. Stage-by-stage walkthrough with debugging tips. |
| [Paradigms](paradigms.md) | Morphological tables: noun declension, adjective agreement, verb conjugation, pronoun forms. |
| [Dictionary](dictionary.md) | Binary format of BASE.DIC / BASE.RUS. Byte layout, grammatical tags, paradigm ID encoding. |
| [Rules](rules.md) | Rule-language reference: worked examples, tag/symbol glossary, replacement alignment, reorder actions, handlers, and explicitly unresolved native behavior. |
| [Tools](tools.md) | Python extraction tools: hex viewers, binary analyzers, string finders, rule extractors. |

## Examples

| Document | Description |
|----------|-------------|
| [Case Study: Zork](case-study-zork.md) | Step-by-step walkthrough: diagnosing translation errors, adding DUNGEON.DIC vocabulary, adding rules. |

## Active Research

[LTPRO parity plan](../reference/LTPRO_PARITY_PLAN.md) defines the target, phased
porting sequence, completion gates, and next deliverable.

[Current LTPRO comparison](../reference/LTPRO_COMPARISON.md) records the verified
binary findings and corrects several older layout and flag hypotheses.
The [fresh LTPRO corpus](../test/ltpro/README.md) contains 77 reproducible full-program
references, capture provenance, and the current Lua comparison.

Work-in-progress notes live in [`reference/`](../reference/):

| Document | Description |
|----------|-------------|
| [PLAN.md](../reference/PLAN.md) | Reverse-engineering roadmap: open questions, phased investigation, experimental results. |
| [REPORT.md](../reference/REPORT.md) | Point-in-time status on flags field mechanism and unimplemented Lua features. |
| [RESEARCH.md](../reference/RESEARCH.md) | Running log of discoveries: provenance, tooling decisions, binary layout, open questions. |
| [RULES_EXPERIMENTS.md](../reference/RULES_EXPERIMENTS.md) | Binary patching experiments: sweep results, pattern semantics verification, flag scan data. |

## Quick Reference

### Grammatical Tags

`Z` = verb/noun/adjective ambiguity; `V` = content verb; `N` = singular noun;
`A` = adjective/ordinal numeral; `X` = auxiliary “be”; `U` = modal verb.
Lowercase tags are distinct categories, not uniformly “resolved” versions.
See the [tag dictionary and internal markers](rules.md#grammatical-tag-dictionary)
for the full list and evidence limits.

### Pattern Syntax

For the general matcher, `[ZV]` matches one token in either class; `<D>` spans
zero or more D tokens; `~Z` negates the next tag match; standalone `*` tests a
boundary; backticks delimit a lexical word test. The Lua implementation has
important limits, especially for `<$>` and backtracking. T5/T6 instead match
literal tag sequences. See [pattern notation](rules.md#pattern-notation-for-the-general-matcher)
before authoring a rule.

The [verified native semantics](rules.md#verified-native-matching-and-replacement)
now distinguish the executable's real boundary nodes, span searches, lexical tests,
and direct tag writes from that legacy parser behavior. The new ports are isolated;
they do not yet replace the production parser.

### Pipeline

```
Input → tokenize / dictionary lookup → parse → compile / morphology → Russian output
```
