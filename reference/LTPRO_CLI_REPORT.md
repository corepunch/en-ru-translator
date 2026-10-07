# Snapshot-free LTPRO CLI — 2026-10-07

> Historical research record. The older translator has since been retired; see
> [the current API and commands](../README.md) and [module map](../docs/pipeline.md).

The recovered Lua pipeline now translates input to output without running DOS,
executing the EXE, or loading a captured process snapshot. It matches all **77/77**
original translation outputs and **20/20** newly captured inputs. The new inputs
were captured twice with identical native output before comparison. This is 100%
of these two test sets, not proof of equality for every possible input.

The requested scope is a CLI with UTF-8 text input and output. DOS UI, process
startup emulation, document formats, exact file wrapping and CRLF are not required.
Runtime data initialization is an internal dependency and is now implemented.

## Run

```sh
lua init.lua 'The letter of credit is valid.'
printf '%s' 'She cannot work.' | lua init.lua
# Equivalent standalone entry:
lua init.lua 'Two books.'
```

The native path uses the frozen `LTGOLD/` assets. `--data DIR`, `--exe FILE`,
`--dic FILE` and `--rus FILE` override them. The EXE supplies static data tables;
no machine code is executed. The existing default translator and its overlays
remain available without `--ltpro`; that older implementation still scores 44/77.
The new API is `require('core.ltpro.pipeline').translate(text, options)`.

## Implementation

- `initialize.lua` loads static DS strings/tables, constructs heap state and builds
  the Russian dictionary descriptor directly from BASE.RUS's embedded index.
- `lexical.lua`, `phrases.lua` and `suffixes.lua` construct word and boundary nodes,
  preserve dictionary annotations, resolve exact readings and backreferences,
  collect per-word grammar rules, match literal phrases, distribute W readings,
  and handle the implemented inflection endings and compound fallback.
- `bridge.lua` allocates native-layout records after T1–T4/reorder, preserving
  words, bytes, next links and auxiliary aliases. No native snapshot supplies nodes.
- `pipeline.lua` connects these to reading selection, constituents/T7, T8,
  morphology, generation and sentence output. Inputs with no lexical words skip
  grammar as the native driver does. CLI framing restores the terminal mark/quote.
- The E-reading object case is stored at `+79`, correcting an earlier `+76` write.
  The expanded differential decoder probe now checks that field and unknown tags.

A missing backreference rule was the last original-corpus output difference:
`making` must inherit `make [MR]*$заставлять`; T4 then chooses `заставлять` rather
than `делать`. Lexical comparisons now check attached subrules as well as word
fields, text, boundaries and tag caches.

## Verification

```sh
python3 tools/ltpro_pipeline_probe.py
python3 tools/ltpro_pipeline_probe.py --cases test/ltpro/holdout_cases.json --reference test/ltpro/holdout_reference.json
python3 tools/ltpro_lexical_probe.py
python3 tools/ltpro_readings_probe.py
lua test/initialize_test.lua
lua test/bridge_test.lua
lua test/lexical_test.lua
lua test/suffixes_test.lua
lua test/pipeline_test.lua
```

| Check | Result |
|---|---|
| Original input → output corpus, snapshot-free | 77/77, zero errors |
| New native capture set, snapshot-free | 20/20, zero errors |
| Single-sentence lexical snapshots, including subrules | 75/75 |
| Native reading decoder differential cases | 2,184/2,184 |
| Initializer, bridge, lexical, suffix and pipeline tests | Pass |

Both output probes validate the input list, assets, repeated-capture provenance,
raw output hashes and expected translation extraction. They compare translation
text exactly, including inline alternatives and punctuation; the separate meanings
appendix and DOS file framing are outside this CLI comparison. The lexical probe
excludes the input with two native sentence invocations and the input that never
enters lexical analysis; both are included in the 77 output comparisons.

`test/run_all.sh` still has the existing legacy cat/mat expectation failure in
`test/translator_test.lua`; this is separate from the new native path.

## Remaining limits

This is a single-sentence entry point. General multi-sentence segmentation/state,
all contractions, the remaining suffix/prefix families, dictionary macros,
pattern-key phrases, duplicate dictionary lookup policies, and all W selectors
are not complete. Some unsupported suffixes currently remain unknown words;
unsupported macro/selector branches raise errors. Passing this corpus does not
certify arbitrary dictionaries or all native inputs. Additional profile modes
and previously documented unobserved/stack-sensitive downstream branches remain
unverified. Keep issue #3 open for these engine gaps, excluding UI/file emulation.
