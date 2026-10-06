# LTPRO native map

Consolidated findings about the unpacked `LTGOLD/LTPRO.EXE` (SHA-256
`6a2036c2…c32dc4fe`), written so that later stages can be ported without
re-deriving addresses, frames, fields or harness mechanics. Everything here
was established by disassembly plus DOSBox captures or emulator runs during
the T2–T4 and reorder ports; items marked *unverified* are inferences.

Tools: `tools/ltpro_disasm.py` (ranges, segment labels, condensed pseudo-code
with frame names), `tools/ltpro_rawtrace.py` (one input through the
instrumented image, printing every boundary), `tools/ltpro_trace.py`
(corpus capture), `tools/ltpro_native_probe.py` (8086 harness `Machine`).

## Address arithmetic

- MZ header: `0x3A00` bytes. File offset = `0x3A00 + segment*16 + offset`
  for the unrelocated segment values that appear in `lcall` operands.
- Capstone addresses printed by the tools are file offsets; jump targets in
  the condensed view are file offsets too.
- Data segment DS = `0x22D5`, so `DS:xxxx` is file `0x26750 + xxxx`.
- Code segments met so far:

| Segment | Content | File base |
|---|---|---|
| `0000` | C library (see stubs below) | `0x3A00` |
| `0687` | driver `066C`, boundary constructor `0812` | `0xA270` |
| `0A4F` | lexical analyzer: readings decoder `0C0F`, sub-rule loader `1603`, record match `1713`, entry `3B12` | `0xDEF0` |
| `0E1F` | one function `0009`: T1, question cleanup call, T2, T3 | `0x11BF0` |
| `108F` | T4 function `000F` | `0x142F0` |
| `1279` | reorder `000D` | `0x1619D` |
| `12DC` | cleanup `0005`; grammar caller `033A` | `0x167C0` |
| `1313` | rebuild `000E`, replacement `01B4`, matcher `0A67`, swap `12DF`, T7 function `1364`, T7 table select `0CDE/0CE8` | `0x16D30` |
| `151F` | post-reorder per-record pass `2740`, its helper `2029` | `0x18BF0` |
| `17AA` | `1D31`, fifth driver stage | `0x1B4A0` |
| `1986` | T8 `000E` | `0x1D260` |
| `1C3D` | constituent matcher `0135`, constituent builder `05C5`, constituent rule pass `1B3F` | `0x1FDD0` |
| `2104` | `008C` strtok-like tokenizer | `0x24A40` |
| `211E` | `117F` is_cyrillic, other ctype helpers | `0x24BE0` |
| `2269` | constituent-array helpers `0007/01B2/0442` | `0x26090` |

## Sentence pipeline (driver `0687:066C`, file `0xA8C8`)

```
0A4F:3B12 (root)                 lexical analysis
12DC:033A (root, terminator)     grammar: 0E1F:0009 T1-T3; if it returned 1 -> 108F:000F T4;
                                 if DI != 0 -> 1279:000D reorder
151F:2740 (root)                 numeric agreement flags; helper 151F:2029 for records with +0B > 1
1C3D:1B3F (root, terminator)     builds the constituent array, then a 21-selector rule pass
1986:000E (root, terminator)     T8
17AA:1D31 (root, terminator)     per word record with +0B > 1 (generation side; unexplored)
near 0687:7427 (file 0xAE27)     output (unexplored)
```

`0E1F:0009` returns 0 from T1 selector 10 (`11FDC`) and 1 after the T3
table (`14177`); both reach the epilogue at `1417D`. In the corpus only
`Stop.` returns early; `ABC-123.` never enters the grammar.

## Lexical record (`0x282` bytes; boundary records are `0x15` bytes)

| Offset | Meaning | Evidence |
|---|---|---|
| `+00` | far pointer to next record (null ends the list) | rebuild, swaps |
| `+0B` | readings/state count (1 after decode, 3 after a fallback; T4 writes 0 and 3) | readings, T4 |
| `+0C` | current tag | everywhere |
| `+0D` | marker: `*` for boundaries, `\|`, `^`, `t` for inserted boundaries | constructor |
| `+0E` | `W` (0x57) word record, `D` (0x44) boundary record | T4 pre-pass, `17AA:1D31` |
| `+0F` | secondary marker: `g n w W X J r a h / % =` | all passes |
| `+10` | source position (lexical slice) | lexical |
| `+12` | source string | matcher literals |
| `+62` | far pointer to the auxiliary record (X/Y link set by T2) | T2 11/16/20/21/26/49, T4 7 |
| `+66` | previous tag | replacement, T2/T3 |
| `+68` | paradigm byte: bits 0-5 frame/paradigm, bit 6 aspect copy, bit 7 preserved | readings, T3, T4 |
| `+6A` | bits 0-5 verb frame, bit 6 aspect (T3 `shr 6 and 1`), bits 6-7 kept by `and 0C0h` | readings, T2/T3/T4 |
| `+72..+7B` | numeric metadata written by readings: 72 number, 73 tense/auxiliary state, 74 person, 75, 76 case mask (2,4,8,0x10,0x20), 77, 78 flag bits (1,2,4,8,0x10), 79, 7A, 7B | readings, all passes |
| `+85/+86` | `0xFF` from the lexical slice; T4 66 zeroes `+85` of the next record | lexical, T4 |
| `+87` | source length (`151F:2740` indexes the last characters through it) | numeric pass |
| `+93` | count of per-word sub-rules (≤ 10) | loader, T4 |
| `+94` | far pointer to the sub-rule array (`0x14F` bytes each: pattern `+0`, action `+50h`) | loader, T4 |
| `+98` | far pointer to the record's own `+11C` translation (boundaries point elsewhere) | T2 strrchr tests, reorder |
| `+9C` | lexical base-form string (`\base` back-reference text) | matcher |
| `+11C` | translation/readings text, rewritten by handlers and sub-rules | all passes |
| `+243` | prefix string: T2 writes `неужели ` and `не ` | T2 52/53 |

Boundary records come from `0687:0812(parent, tag, marker)`; the call site
pushes the marker first, then the tag, then a null parent. They are zeroed,
with `+0C` tag, `+0D` marker, `+0E` = 0x44, `+12` = tag string.

## Globals (DS-relative)

| Address | Meaning |
|---|---|
| `C7B1` | record count; written by T1 entry, every default-rewrite rebuild, T2 51–54, T3 34, T4 entry/boundary/move handlers; *not* by most handler rebuilds |
| `C5AE` | tag cache string, rewritten by `1313:000E` and by replacement; stale after reorder swaps without removal |
| `044D` | boundary allocation limit (512) |
| `C7FA/C7FC` | far pointer to the constituent array (12-byte records); `C7FE` its count |
| `BF77` | ctype table: bit 4 upper, bit 8 lower, so `test 0Ch` means ASCII letter |
| `0C0F`, `0C12` | tokenizer delimiter strings `" *"` |
| `2D9B/2DA0/2DB9/2DC4` `that`; `2DA5` `должен`; `2DAC` `неужели `; `2DB5` `не `; `2DBE` `чтобы`; `2DC9` `without`; `2DD1/2DD4` `by`; `2DD7` `the` | T2/T3 literals |
| `3FA9` `NN`, `3FAC` `NAN`, `3FB0` `NdN`, `3FB4` `NHN`, `3FB8` `N-N`, `3FBC` `A.`, `3FBF` `количество`, `3FCA` `-`, `3FCC` `быть`, `3FD1` `-`, `3FD3/3FD8` `year`, `3FDD` `of`, `3FE0` `привыкши`, `3FE9` `обычно` | T4 literals |
| `3FF0` | reorder table start (T5 then T6) |
| `0C3C` T1, `0E1C` T2, `1448` T3, `2DDC` T4, `43E0` cleanup, `4FEC` constituent rules | rule tables (file offsets in `LTPRO_COMPARISON.md`; constituent table file `0x2B73C`, 8-byte records: pattern pointer + u16 selector ≤ 20) |
| `BCF4/BCF6` | zeroed by `151F:2740` on entry |
| `C58C/C58E` | far pointer used by the output call |

## C library stubs (segment 0) and their harness substitutes

`0432` block copy (CX bytes, callee pops two pointers), `13D2` character
helper (used by `211E`), `1951` calloc, `1BAA` free, `3C95` strcat, `3CD4`
strchr, `3D11` strcmp, `3D41` strcpy, `3DB0` stricmp (folds ASCII a–z only),
`3DF1` strlen, `3E34` strncat, `3E97` strncmp, `3ECF` strncpy, `3F44`
strpbrk, `3F90` strrchr, `3FD9` strstr. All are implemented in
`Machine.library`. `211E:117F(c)` returns 1 for CP866 Cyrillic (`0x80..0xAF`,
`0xE0..0xF1`), the same predicate as `russian()` in `replacement.lua`.

## Frames

`0E1F:0009` (`sub sp,842h`; T1, T2, T3):
`[bp+6/8]` root, `[bp+0A]` terminator; `[bp-842]` vector of far pointers,
`[bp-2]` removed, `[bp-6]` match end, `[bp-0A]` T1 rule, `[bp-0E/-0C]` T2
rule, `[bp-12/-10]` T3 rule, `[bp-16]` loop index, `[bp-18]` T3 endpoint
back-off, `[bp-1C/-1A]` head = V[di], `[bp-20/-1E]` tail = V[last],
`[bp-28/-26]`, `[bp-32/-30]`, `[bp-36/-34]` temporaries, `[bp-D2]` selector
and `[bp-F6/-F8/-FA]` rule/endpoint at the T1 dispatch.

`108F:000F` (`sub sp,848h`; T4): `[bp-848]` vector, `[bp-2]` removed,
`[bp-4]` match end, `[bp-8/-6]` rule (9-byte records), `[bp-0A]` width,
`[bp-0C]` k, `[bp-0E]` continue flag (0 ends the current rule), `[bp-12/-10]`
head, `[bp-16/-14]` tail, `[bp-22/-20]` new boundary, `[bp-24]` selector,
`[bp-28/-26]` best sub-rule endpoint (`0x200` = none), `[bp-2A]` its index,
`[bp-2C]` sub-rule loop, `[bp-2E/-30]` action after the first backslash,
`[bp-32/-34]` after the second, `[bp-38/-36]` action, `[bp-3A]` selector
character, `[bp-3C]` sub-rule replacement result (uninitialized natively).

`1279:000D` (`sub sp,822h`; reorder): `[bp-822]` vector, `[bp-8/-0A]`
table pointer, SI position, `[bp-2]` removed.

`12DC:0005` (cleanup): table at DS:43E0 in `[bp-8/-6]`, SI position.

## Switch tables (file offsets; `jmp word ptr cs:[bx+disp]`)

| Pass | Dispatch | Table | Notes |
|---|---|---|---|
| T2 | `125C3` | `CS:2659` → file `0x14849` | selectors 1–61 |
| T3 | `1377E` | `CS:2593` → file `0x14783` | 1–98; 99 → `14102` |
| T4 | `149D2` | `CS:1D9F` → file `0x1668F` | 1–98; 99 → `16007` |
| T4 sub-rules | `146A6` | chars `CS:1E65` (18 words, file `0x16755`), targets `CS:1E89` (file `0x16779`) | `0 1 2 3 4 5 6 7 8 9 a c f g h n r 0xFF` |
| cleanup | `16849` | `CS:0324` | |
| T7 | `17FAA` | `CS:0CF5` | |
| `1313:…` | `18F80` | `CS:0514` | second T7-area table, unexplored |
| `151F:2029` | `1B934` | `CS:1CC1` | unexplored |
| numeric | `1B397` | `CS:28B2` | last digit `1`–`4` |
| T8 | `1D2BE` | `CS:2AE5` | |
| constituent rules | `21984` | `CS:2318` | 21 selectors |

Handler addresses for T1–T4, reorder, cleanup, T7 and T8 are in
`core/ltpro/dispatch.lua`. T1 has no indirect jump; its dispatch is a compare
chain.

## Loop conventions

- T1: stops after its first default rewrite. T2/T3: for each rule, position 1
  while `C7B1-1 > position`; default = replacement then `position = last+1`
  (T3: `last - back + 1`); a rebuild per rule only when the replacement
  removed a record. Handlers exit through `125DE`/`1380E` (skip to last+1),
  `134FB`/`1405F` (position = count, ends the rule), `13976`/`13659`
  (rebuild without storing the count, then skip).
- T4: position starts at 0; rebuild after every removing match; handler
  exits `149FE` skip, `1600B` default, `14CCD` flag=0 then default, `15DF0`
  flag=0 without replacement, `15171` advance two, `15C46` position = value.
- Rebuild (`1313:000E`) rewrites the vector and `C5AE` and returns the
  count; callers store it into `C7B1` only where listed above, so `count`
  must be modeled separately from the vector length. A read beyond the
  rebuilt vector is possible natively after two unstored removals; no corpus
  or generated case has reached it.
- Descending searches (`while i >= di and tag ~= c do i-- end`) stop at
  `di-1`; T3 selector 6's `B` search never tests the head; T4 selector 47
  can rewrite `V[di-1]`.
- The matcher receives the cache string, which can differ from record tags
  mid-handler; replacement updates the cache per changed tag.

## Dictionary facts

- Records `key*value`; `dictionary.lua` splits at the first star, so for
  sub-rule records (`word pattern*$action`, 289 of them) the raw line must be
  reparsed at the *last* star followed by `$`.
- The record scan (`0A4F:1713`) tokenizes a candidate key on `" *"`, compares
  the first token with the word by `stricmp`, then the second token with the
  next word: equal means multi-word phrase matching, otherwise the sub-rule
  loader `0A4F:1603` is called with the text after the first token (leading
  space skipped). At most ten sub-rules per word, in file order.
- `W` entries (9,029) are multi-word phrases: `a to d converter*WAаналого-цифровойNпреобразователь`.

## Harness mechanics (`tools/ltpro_trace.py`)

- Hook stub lives at paragraph `0x3100`; the C startup resizes the memory
  block to SS plus stack, so SS is moved above the stub.
- The original relocation table fills the header exactly; the header is grown
  by whole paragraphs (load addresses are header-relative; sites keep original
  file offsets and are shifted at patch time).
- A site must be ≥ 5 bytes of whole instructions with no jump target inside
  the patched range (the start may be a target); a displaced relative jump is
  only acceptable when it is zero-length (`EB 00`). Prefer a loop's rule-record
  test (`les bx,[rule]; mov ax,es:[bx]`) with a conditional dump when the
  record is null; adjust BP for frames other than `842h` with `FRAME_ADJUST`.
- Wrapping a far call from the caller's frame (re-pushing arguments, calling,
  dumping from the dead frame) crashed with invalid-opcode floods under
  DOSBox-X even though the same stub runs in the harness; the cause was not
  found. Do not retry that approach without a debugger.
- A crash makes DOSBox-X log every fault; `host.log` reached 1.2 GB in a
  minute. `tools/ltpro_rawtrace.py` reports and keeps the directory instead.
- `0F 85/0F 84 rel16` work under the default DOSBox-X CPU; `timeout(1)` is
  absent on macOS.
- Dumps: per boundary a 20-byte header, the vector with its null terminator,
  the cache with NUL, each record's `0x282` bytes, then for word records
  their `+93` sub-rule records. `decode_trace` normalizes pointers to ids.

## 8086 harness (`tools/ltpro_native_probe.py`)

- Loads the image at segment 0 (no relocation); DS `0x22D5`, SS `0x6000`.
  Fixture records at `0x80000 + i*0x400`, root pointer at `0x70000`,
  sub-rule records at `0xC0000`, calloc heap from `0xB0000`.
- Entry/stop points used: T1 `0E1F:0009` → stop `0E1F:095A`; T2 → stop
  `0E1F:1B10`; T3 → stop `0E1F:2587`; T4 `108F:000F` → observe at
  `108F:1D99` (epilogue, BP still valid); reorder `1279:000D` to return;
  matcher `1313:0A67`, replacement `1313:01B4`.
- Tables are isolated by copying one record into slot 0 and nulling the
  next; preceding passes are disabled by nulling their first record (T1
  `0x2738C`, T2 `0x2756C`, cleanup `0x2AB30`, T3 `0x27B98`, T4 `0x2952C`).
- Supported instructions: mov push pop lea les add sub cmp xor or test and
  inc dec shl shr imul(1-op) call lcall(imm and mem) retf loop jmp/jcc.
  Anything else raises with the address; pushf/popf/int are not supported,
  so hook stubs cannot be run through their dump.
- Lua boundary records need the emulator's allocation addresses
  (`allocations`) to compare identities.

## Corpus facts

- 77 cases; 76 enter the grammar (`Stop.` returns early; `ABC-123.` bypasses
  it; `He said: "Go."` enters twice).
- Caches changed per stage: T2 39, T3 28 (of 76 fixtures), T4 12, reorder 33.
- Corpus coverage: T2 selectors 0 2 7 10 16 23 24 25 26 30 42 43 48 59 60 61;
  T4 selectors 0 4 8 10 11 14 15 18 29 37 49 50 51 53 60 and three sub-rule
  applications; everything else is covered only by generated fixtures.

## What remains unexplored

`151F:2029` (0x717 bytes, called for records with `+0B > 1`), the
constituent builder `1C3D:05C5` and its 12-byte records, the constituent
rule pass `1C3D:1B3F` (table `0x2B73C`), T8 `1986:000E` beyond its matcher,
`17AA:1D31`, the output routine, the lexical analyzer beyond exact words
(`0A4F:3B12`: multi-word phrases, suffixes `0x26EC6`, prefixes
`ERPREFIX.PRE`, unknown words, annotations `{}`, macros `=`/`%`), and whether
later stages read the stale `C5AE` after reorder.
