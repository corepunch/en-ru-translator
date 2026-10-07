# LTPRO generation and output — 2026-10-07

This continues [issue #3](https://github.com/corepunch/en-ru-translator/issues/3)
after the T5–T8 port. Generation, sentence text, the meanings appendix and
sentence-memory cleanup now run in Lua on the native memory model. The production
translator still matches **44/77 paragraphs**: the new path starts from DOS
snapshots and is not yet connected to a complete Lua lexical analyzer.

## Implemented routines

| Native entry | Lua port | Behavior |
|---|---|---|
| `1E71:02AC/0420/05FB/0977` | `forms.lua` | noun, adjective, verb and participle forms, including shared-buffer writes |
| `1E71:0CDC` | `forms.pronoun` | in-place pronoun inflection and prefix handling |
| `17AA:000A` | `generation.case` | first applicable case bit |
| `17AA:0045/02E8` | `generation.participle/pronoun` | caller state, short forms, agreement, hyphen tails |
| `17AA:0475` | `generation.word` | full 56-entry tag switch, including no-op entries |
| `17AA:1D31` | `generation.run` | record traversal and profile-gated alternatives |
| `0687:0BB7` | `output.sentence` | spacing, punctuation records, capitalization, inline alternatives |
| `0687:01C8` | `output.meanings` | numbered appendix, optional wrapping and labels |
| `0687:0A50` | `records.clear` | free sentence/alternative records and owned strings; reset root |

The native suffix tables are read from modeled DS memory. This preserves writes
that the string-only `inflect.lua` API cannot expose: a failed form still changes
the stem buffer, and successful forms can write a second NUL beyond the result's
first terminator. Latin letters mixed into Russian words stay unchanged during
Cyrillic capitalization. Original behavior is retained rather than corrected.

Earlier handover addresses `0687:7427/6A38/72C0` were wrong: those offsets
were relative to the load image. Correct file/segment pairs are `AE27` /
`0687:0BB7`, `A438` / `0687:01C8`, and `ACC0` / `0687:0A50`. The last
routine frees memory; document wrapping is elsewhere. The sentence driver starts
at `0687:05D5` (file `A845`); `066C` is its grammar call site.

## Verification

- **77/77 generation calls** match the native instructions on all compared
  memory and the defined AX return value.
- **155/155 morphology calls** match memory writes and returned pointers:
  54 verb, 54 noun, 34 adjective, 9 participle and 4 pronoun calls.
- **77/77 sentence-output calls** and **77/77 appendix calls** match the native
  instructions. Appendix wrapping is additionally checked at widths 24 and 64.
- The complete Lua chain **numeric → constituents/T7 → T8 → generation →
  output → meanings** matches **77/77 DOS boundaries on each of two independent
  captures**. Every instrumented final file has the original oracle's hash.
  There are 77 sentence transitions across 77 inputs: case 074 has two sentences,
  while case 075 is empty and never enters the sentence driver.
- Generation fuzz, seed 37: **299 pass, 0 differ, 1 native harness failure**
  across 300 mutations. Case 176, based on case-077, produces `StopIteration`
  while decoding the next native instruction. This case is unverified, not a pass.
- Generation → output → meanings → cleanup fuzz, seed 51: **200 pass,
  0 differ, 0 native skips**.
- Asset-free regression checks cover case precedence, failed-form buffer writes,
  extra terminators, finite-person-zero behavior, W readings and capitalization.
- Standard suite still stops at the previously documented cat/mat expectation
  in `test/translator_test.lua`. The new test and all preceding module tests pass;
  the remaining utilities test passes separately. `demo/compare.lua` is **25/25**.
  Fresh production comparison remains **44/77**, zero runtime errors.

Comparisons retain the established exclusions: the unmodeled stack, BIOS timer,
instrumentation bytes and `strtok`'s saved pointer into dead stack. The hook range
now ends at the instrumented SS boundary rather than an assumed 200h size, because
the two additional hooks enlarge the instrumentation. No record, output-buffer,
heap or semantic DS bytes were added to the exclusions.

## Reproduce

From repository root, with the original assets, Lua, Python/Capstone and DOSBox-X:

```sh
lua test/ltpro_generation_test.lua
python3 tools/ltpro_function_probe.py 17AA:1D31 --words 2 --stages generation
python3 tools/ltpro_function_probe.py 1E71:05FB --words 9 --stages generation
python3 tools/ltpro_function_probe.py 1E71:02AC --words 6 --stages generation
python3 tools/ltpro_function_probe.py 1E71:0420 --words 6 --stages generation
python3 tools/ltpro_function_probe.py 1E71:0977 --words 7 --stages generation
python3 tools/ltpro_function_probe.py 1E71:0CDC --words 7 --stages generation
python3 tools/ltpro_output_probe.py
python3 tools/ltpro_output_probe.py --function meanings
python3 tools/ltpro_output_probe.py --function meanings --width 24
python3 tools/ltpro_output_probe.py --function meanings --width 64
python3 tools/ltpro_output_probe.py --function cleanup
python3 tools/ltpro_memtrace.py --cache .cache/ltpro-output
python3 tools/ltpro_post_chain.py --cache .cache/ltpro-output --until meanings
python3 tools/ltpro_memtrace.py --cache .cache/ltpro-output-repeat
python3 tools/ltpro_post_chain.py --cache .cache/ltpro-output-repeat --until meanings
python3 tools/ltpro_post_fuzz.py --start T8 --stages generation --cases 300 --seed 37
python3 tools/ltpro_post_fuzz.py --start T8 --stages generation output meanings cleanup --cases 200 --seed 51
```

Use separate empty capture directories for independent recaptures; an existing
matching manifest is resumed. Function and fuzz probes default to the earlier
`.cache/ltpro-memtrace` snapshots. These caches contain original binary/dictionary
bytes and are not committed. `ltpro_post_chain.py` fails if the requested ending
boundary is missing or no transitions were compared; regenerate older captures
to obtain the output and meanings boundaries.

## Remaining gates

The input analyzer still only accepts the earlier exact-word slice. Standalone
startup state, a bridge from node-table grammar to memory records, outer sentence
segmentation/punctuation, document framing, final wrapping and CRLF are still
missing. Output buffers are not full files. Production remains on the legacy
path; no snapshot-backed fallback was installed in its public API.

The new ports also need broader branch evidence, alternate-profile tests and
held-out documents. Unterminated W annotations raise explicitly: native code
reads beyond their terminator, which is not modeled. Native stack overflows and
uninitialized frame dependencies are not covered by the memory ports. The existing
post-reorder profile restrictions and stack approximations remain documented in
the [handover](LTPRO_HANDOVER.md). A passing downstream corpus does not establish
100% end-to-end or universal LTPRO compatibility.
