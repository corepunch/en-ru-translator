# Documentation Index

## Architecture

| Document | Description |
|----------|-------------|
| [Pipeline](pipeline.md) | Translation pipeline: tokenize → parse → compile. Stage-by-stage walkthrough with debugging tips. |
| [Paradigms](paradigms.md) | Morphological tables: noun declension, adjective agreement, verb conjugation, pronoun forms. |
| [Dictionary](dictionary.md) | Binary format of BASE.DIC / BASE.RUS. Byte layout, grammatical tags, paradigm ID encoding. |
| [Rules](rules.md) | Pattern/replacement syntax, complete tag table, table structure, flag semantics. All confirmed. |
| [Tools](tools.md) | Python extraction tools: hex viewers, binary analyzers, string finders, rule extractors. |

## Examples

| Document | Description |
|----------|-------------|
| [Case Study: Zork](case-study-zork.md) | Step-by-step walkthrough: diagnosing translation errors, adding DUNGEON.DIC vocabulary, adding rules. |

## Reverse Engineering

| Document | Description |
|----------|-------------|
| [LTGOLD Reverse Engineering](ltgold-reverse-engineering.md) | Complete knowledge base: methodology, all bugs fixed, remaining failures, r2/r2ghidra workflow, flag semantics. |

## Active Research

Work-in-progress notes live in [`work/`](../work/):

| Document | Description |
|----------|-------------|
| [PLAN.md](../work/PLAN.md) | Reverse-engineering roadmap: open questions, phased investigation, experimental results. |
| [REPORT.md](../work/REPORT.md) | Point-in-time status on flags field mechanism and unimplemented Lua features. |
| [RESEARCH.md](../work/RESEARCH.md) | Running log of discoveries: provenance, tooling decisions, binary layout, open questions. |
| [RULES_EXPERIMENTS.md](../work/RULES_EXPERIMENTS.md) | Binary patching experiments: sweep results, pattern semantics verification, flag scan data. |

## Quick Reference

### Grammatical Tags

```
Z=verb  N=noun  V/A=adjective  D=adverb  E=past participle  G=gerund
S=adjective(alt)  P=preposition  C=conjunction  X=infinitive  U=unique verb
F=passive participle  R=pronoun  Q=question word  J=subordinating conj
T=empty  #=number  ?=unknown  n=noun(plural)  w=lowercase modifier
```

### Pattern Syntax

```
[ZV]     = match one of Z or V
<VXY>    = match zero or more of V, X, or Y
~Z       = match anything except Z
*        = sentence boundary (start or end of token stream)
`word`   = match literal English word
```

### Pipeline

```
Input → tokenize (load.lua) → parse (parser.lua + rules.lua) → compile (compiler.lua + paradigms.lua) → Russian output
```
