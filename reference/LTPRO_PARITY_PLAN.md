# Plan for LTPRO parity

Status: in progress, 2026-10-06. This is project research
documentation, not agent instructions. It supersedes the execution plan in the
historical [PLAN.md](PLAN.md), while preserving those notes as evidence to recheck.

## Measured progress — 2026-10-06

The [native stage report](LTPRO_STAGE_REPORT.md) records the current implementation:

- All 77 instrumented output files equal the original oracle bytes on both runs.
- Native lexical/T1/T2/T3 boundaries and 36 T1 rule-selection events are captured.
- The independent T1 port matches 77 sentence-stage fixtures and all 36 events.
  Another 648 generated/instruction fixtures exercise every T1 selector,
  including allocation success/limit/failure and an explicitly synthetic selector 8.
- The T2 and T3 ports match 76 captured T1→T2 and 76 T2→T3 fixtures each, and
  962 and 872 generated-node instruction fixtures cover every T2 and T3
  selector body, including bodies no supplied record selects.
- The two planned exact-word lexical/node slices match their native initialized
  word fields; the metadata decoder passes 1,377 instruction comparisons.
- A generated ledger inventories all 410 selectors and 282 distinct targets,
  with aliases, rule references and bounded CFG evidence. Complete semantic
  field/caller mapping and unobserved branch coverage remain open.
- Production paragraph matches are now **44/77**, with 33 differences and no
  runtime errors. Preserving lexical j readings and source capitalization fixed
  15 cases without corpus regressions. An additional 16-case capitalization
  matrix matches two identical native runs. This is not full-file or universal parity.

Next: port the per-word sub-rule loader (`word pattern*$action` dictionary
records) and the remaining analyzer/lookup branches, add a T4-boundary hook in
the caller's frame, then port the separate T4 function and constituent creation.
Unobserved branches, global allocation state, later generation and document/file
output remain explicit gaps. The production pipeline still uses the legacy
parser and later passes; the native T1–T3 ports are development entry points. No milestone
below is declared complete merely because its current corpus passes.

## Objective and completion contract

Build a pure-Lua implementation of the supplied unpacked `LTPRO.EXE`, retaining
its observable mistakes as well as its intended behavior. Translation improvements
belong after compatibility is established.

The initial reference is executable SHA-256
`6a2036c2fbc629d0317bf02acbb1e6ebd82ceecb2d11f609c6460cc0c32dc4fe`, the six supplied
assets and `/I INPUT /O OUTPUT /F- /B- /N` profile recorded in
[the reference corpus](../test/ltpro/README.md). This fixes configuration drift;
it does not redefine all other program modes as already supported.

There are two completion milestones:

1. **Translation-engine parity for the frozen profile:** identical CP866 output
   files, including the separate meanings appendix, capitalization, punctuation,
   spaces, wrapping, and line endings. Exercise complete documents as well as
   individual sentences, including state carried between sentences.
2. **LTPRO compatibility across supported modes:** enumerate command/configuration
   options and dictionary-loading modes from the executable, then verify each
   supported mode and its observable file/error behavior. Any omitted mode or
   unsupported input boundary remains an explicit gap in an unqualified parity claim.

Keep the public UTF-8 translation API as a wrapper around the compatible byte-level
engine. Its paragraph output is a separate API contract from an LTPRO output file.
DOS hardware, UI, and process timing are not translation-engine outputs. Failures
involving malformed input, memory limits, or unstable native behavior need an
explicit contract based on measurements; do not silently discard failing cases.

LTGOLD is a separate target: its T1 `if … then` action differs from LTPRO. Complete
LTPRO first, then add and test a version-specific profile if LTGOLD parity is needed.
One shared behavior cannot match both versions at a point where they disagree.

## Why disassembly is necessary but insufficient

Disassembly exposes the instructions. A port still has to preserve the data those
instructions read and write, their call order, integer/byte semantics, and their
interactions. Decompiler output can help follow control flow; it is not evidence
that recovered types, pointer relationships, or high-level explanations are correct.

This project has recovered tables and several operations, but the production
pipeline still implements different representations and decisions:

- `dictionary_store.lua` strips brace annotations and periods and rewrites a W
  prefix. Those transformations must be checked against native loading behavior.
- `core/parser.lua` resolves readings through packed lexical strings. Its diagnostic
  handler IDs do not execute the native handler bodies or supply native state.
- Native matching distinguishes a node's current tag, previous tag, lexical text,
  translated text, and cached tag. A single leading character cannot stand in for
  all these fields.
- `core/compiler.lua` contains contextual fallbacks and a small hand-maintained verb
  frame table. Matching morphology suffixes does not establish that the caller
  chooses the same lemma, aspect, case, or paradigm.

The initial example `If he comes then I go.` omitted `тогда` in Lua. Native
snapshots exposed the erased lexical j reading and now both outputs agree.
Correctly extracting the `if … then` record alone did not establish those effects
through the complete pipeline.

The efficient route is to port the native state transitions in dependency order,
using original execution to locate the first divergence. Collecting more natural
translations or adding sentence-specific exceptions would not close those gaps.

## Starting evidence

| Area | Established | Still missing |
|---|---|---|
| Extracted data | 702 grammar, 43 suffix, 431 morphology records match LTPRO | Execution and caller state |
| Dispatch | 410 numeric selectors; 282 distinct target addresses including defaults | Reachability, shared blocks, handler effects; these addresses are not a function count |
| Native primitives | Reorder 358, morphology 7,029, lexical matcher 4,780, replacement 2,048, T8 matcher 1,403 differential cases pass | Production integration and surrounding routines |
| Full program | 77 references reproduced byte-for-byte across two DOSBox-X runs | Lua matches only 29 translation paragraphs; raw-file parity is not yet scored |
| Rule documentation | Operational evidence for many symbols and distinct matcher families | Remaining field writers/readers, handler meanings, unused syntax paths |

These case counts are coverage evidence, not a percentage of the executable ported.
Details and limitations: [current audit](LTPRO_COMPARISON.md).

## Work sequence and gates

Each phase produces reviewable code, binary evidence, and tests. A phase may expose
an upstream error; the gate then stays open until that error is corrected.

### 1. Map the translation path and make native state observable

Start at the successful batch invocation. Trace dictionary loading, input reading,
lexical analysis, grammar passes, generation, and output. Record actual entry/exit
addresses and dependencies rather than assuming the historical phase diagram.

Create a routine/block ledger containing address, callers, shared targets, fields
read/written, called helpers, port status, and evidence. Classify all 410 dispatch
selectors, including default and aliased targets. Do not count aliases as separate
implementations or label unvisited targets dead without a reachability argument.

Add stage snapshots from real executable runs: input bytes, dictionary readings,
node records/links, cache, selected rule/handler, constituent state, and morphology
arguments/results. Try the installed DOSBox-X debugger first; if it cannot expose
the needed state, use minimal instrumentation of disposable executable copies or a
debugger-capable build. Instrumented output must still equal the unmodified oracle.
Keep this trace work bounded: first prove one stage boundary before building a
general trace system.

Normalize pointers to stable node IDs for comparisons while preserving aliasing,
order, and null links. Record initialized semantic fields; do not erase differing
fields simply because their purposes are unknown. Use isolated instruction probes
where they give better local visibility, with substitutions explicitly recorded.

**Gate:** repeatable native snapshots for one passing case and one failing case,
with the first differing phase identified. A ledger connects that path to handlers
and field definitions. Trace collection preserves the original program's output.

### 2. Port loading, lexical analysis, and native node construction

Implement a compatibility loader that preserves source bytes and native parsing
decisions. Verify record order, duplicate handling, alternate meanings, W phrases,
prefix data, Russian morphology metadata, and startup defaults. Avoid passing the
compatibility path through the current lossy normalization unless native evidence
establishes each transformation.

Port token boundaries, dictionary search order, multiword matching, suffix/prefix
analysis, spelling changes, case handling, unknown words, and numeric input.
Construct the native lexical records and tag cache. Extend `core/ltpro/nodes.lua`
with confirmed fields and operations; retain offsets for unnamed fields. Model
shared references and record lifetime wherever they affect later behavior.

**Gate:** native and Lua lexical-stage snapshots agree for the 77 cases plus
targeted fixtures for every recovered lexical branch. Exercise dictionary records
systematically where their format supports valid generated inputs; compare lookup
and analysis results, not only final translations. Unresolved paths stay listed.

### 3. Port grammar scheduling and handler bodies; integrate proven primitives

Recover pass order, scan direction, restart rules, match endpoints, compaction,
cache rebuilds, rule guards, and termination. Implement each reachable handler's
field writes and link changes in the same order as the executable. Cover cleanup,
T7 selection/endpoint changes, and the separate T8 constituent representation.

Use the existing native matcher, replacement, reorder, and constituent matcher
ports where their contracts are verified. Extend unsupported paths only when
reachable state or the requested rule-editing contract requires them. Native
branches remain branches when they are control flow; use extracted tables for
dispatch and data, without inventing lookup tables to hide missing semantics.

**Gate:** stage and handler-event traces agree, including intermediate state and
termination. Every reachable dispatch family has native-vs-Lua fixtures, with
branch-specific edge cases and a reason recorded for excluded selectors. Full
translations need not all pass yet, because generation is the next dependency.

### 4. Port generation callers and their grammatical state

Trace the writers and readers of plurality, aspect, gender, verb flags, paradigm
selection, case, constituent heads, and agreement. Recover lexical sense selection,
modal/passive/copular processing, verb frames, and ordering at generation time.
Call the verified morphology helpers with the same arguments as the executable.

Replace the current compiler's inferred decisions as each corresponding native
path becomes available. Preserve original irregularities; a linguistically better
answer is still a mismatch. Do not layer new native behavior on top of an old
fallback that can also fire.

**Gate:** native and Lua generation inputs, selected lemmas, morphology calls, and
emitted CP866 fragments agree for the baseline and targeted caller branches.
All 77 baseline translation paragraphs match, without changing the oracle.

### 5. Complete the output-file and document lifecycle

Reproduce punctuation, spacing, capitalization, alternatives numbering and appendix,
line wrapping, CRLF, sentence segmentation, paragraph handling, and end-of-file
behavior. Determine which state resets per token, clause, sentence, document, or
process. Verify consecutive translations and repeated use of the Lua API.

Extend the comparator to score full raw CP866 output. Retain paragraph comparison
as a diagnostic view. Capture multi-sentence files and limits/edge cases as well
as the current fresh-process-per-sentence inputs.

**Gate:** full output files match byte-for-byte for the frozen profile, including
document tests and stable boundary behavior. There are no silent fallbacks to
the legacy parser/compiler inside the compatibility path.

### 6. Expand coverage and close the compatibility claim

Build a coverage matrix connecting grammar records, dispatch families, lexical
branches, morphology callers, output branches, and configuration modes to evidence.
Generated node fixtures establish low-level behavior; valid English inputs establish
end-to-end reachability. A generated tag sequence alone is not proof that the
lexical analyzer can create it.

Grow the oracle with controlled combinations: ambiguity, tense/aspect, modality,
negation, agreement, relative/conditional clauses, questions, coordination,
multiword entries, numbers/dates, punctuation, casing, unknowns, and long documents.
Keep a held-out corpus not used to design fixes. Use deterministic seeds and
minimize every mismatch into a regression case. Increase combinations according
to missing branch coverage, not to an arbitrary sentence-count target.

Enumerate and test the other supported LTPRO modes after the frozen profile is
stable. Verify requested alternate dictionaries/configurations separately; immutable
reference assets remain the baseline. Track LTGOLD's version differences separately.

**Gate:** no known mismatches, all supported modes and reachable semantic paths
accounted for, full-file corpus and held-out comparisons pass, and exclusions are
explicit. Complete the rule/tag reference with native operations, contextual
linguistic explanations, examples, and evidence for each claim.

A finite corpus cannot prove equality for every possible input. Report exactly
which profile, corpus, and paths pass. A universal claim would require a much more
expensive equivalence argument over all reachable states; do not rename a passing
corpus “proof of 100% parity.”

## Integration and test policy

Build the native-compatible path coherently under `core/ltpro/` and expose it
through an explicit development entry point. Keep the current translator available
while the new path cannot complete a translation. Once the gates pass, make the
compatible engine the default; preserve optional improvements as a separately
tested policy if still wanted. Do not maintain two hidden interpretations of rules.

For each meaningful change: compare the affected native routine/stage, run its
Lua regression cases, and run the full-program corpus when the end-to-end path is
affected. Run broader checks at phase gates. Validate critical assumptions in the
custom instruction harness against actual DOSBox execution: prior string-helper
corrections show why one handwritten harness cannot be the only authority.

Separate legacy preferred-output tests from executable compatibility tests. The
old cat/mat expectation may remain a named improvement test; it cannot define
LTPRO correctness. Any changed compatibility expectation must come from a fresh,
provenance-checked executable capture, never from the Lua result.

## Effort and next deliverable

Treat this as a multi-week reverse-engineering project, not an extraction script
or a few sentence fixes. That is a planning assessment, not a measured delivery
estimate. Binary size and the 282 dispatch addresses do not reveal how many
independent paths remain, how much code is shared, or how costly tracing will be.

The initial deliverable was **phase 1 plus one lexical vertical slice**:

1. Native snapshots for `He is in the house.` and `If he comes then I go.`.
2. A minimal field/caller map and first-divergence report for those inputs.
3. A Lua loader/node path reproducing their native lexical state, with fixtures.
4. An updated routine ledger and effort range based on the measured work in that slice.

Snapshots, the first-divergence report, two lexical slices, the initial ledger
and the T2/T3 ports are delivered in the stage report. Complete semantic mapping
and branch coverage are still open. The next deliverable is the sub-rule loader
and native lookup/analyzer expansion, followed by the T4 boundary and port. These
measurements establish the method, but do not yet justify a completion date for
phases 2–5. If tracing stalls, change the tracing mechanism; do not substitute
more sentence-specific patches.

Disassembly remains the main source of truth, DOSBox supplies complete executions,
and differential tests connect the two to the Lua port. Reusing the original EXE
would avoid reimplementation work if an executable-backed translator were the goal;
it does not complete the requested independent Lua implementation.
