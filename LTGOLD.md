# LTGOLD.md — Running the Original DOS Translator

## Running via DOSBox-X

LTGOLD is a 16-bit DOS TUI application. The batch translator **LTPRO.EXE** is the
correct tool for non-interactive use.

### Basic invocation

```sh
dosbox-x -silent \
  -c "mount c /path/to/LTGOLD" \
  -c "c:" \
  -c "LTPRO.EXE IN.TXT OUT.TXT -F-" \
  -c "exit"
```

### Important: 8.3 short filenames required

DOSBox-X mounts as FAT — long filenames don't work. Use short names:

```
test_input.txt  →  TEST_I~1.TXT
TEST_BASE.TXT   →  TEST_B~1.TXT
```

List short names with `dir` inside DOSBox-X.

### Command-line flags

| Flag | Purpose |
|------|---------|
| `/I <file>` | Input (source) file |
| `/O <file>` | Output file |
| `/D <path>` | Path to dictionaries directory |
| `/N` | Create new output file |
| `/A` | Append to existing output file |
| `/F-` | Disable output formatting |
| `/T` | Translate immediately |
| `/MM` | Display multiple meanings |
| `/SM` | Display multiple meanings (source) |
| `/X` | Tel-Lex mode (ASCII transliteration) |
| `/L-` | Transliteration off |
| `/B-` | Turn off completion bell |
| `/?` or `/H` | Display help |

Full syntax from `LTGCMD.HLP`:

```
LTPRO [/I] <file> [/O] <file> [/D] <path> [/SM] [/W(IOM)] [/F-] [/A] [/M]
      [/MM] [/R <#>] [/L(BE) <#>] [/C <cbu>] [/P(BE) <#>] [/FL] [C(BE) <#>]
      [/N] [/X] [/L-] [/B-] [/@] [/BW] [/AR-] [/AM] [/HR] [/LS <#>] [/LH <#>]
      [/ES <#>] [/EW <#>] [/FI MAC] [/FO MAC] [/?] [/H]
```

All `/` switches can be replaced with `-`. Positional args also work:

```
LTPRO.EXE INPUT.TXT OUTPUT.TXT -F-
```

### Output encoding

Output is **CP866** encoded. Decode with Python:

```python
data = open('OUTPUT.TXT', 'rb').read().decode('cp866')
```

### Python wrapper example

```python
import subprocess

def translate(input_text, input_path='IN.TXT', output_path='OUT.TXT'):
    with open(input_path, 'w') as f:
        f.write(input_text)

    subprocess.run([
        'dosbox-x', '-silent',
        '-c', 'mount c /path/to/LTGOLD',
        '-c', 'c:',
        '-c', f'LTPRO.EXE IN.TXT OUT.TXT -F-',
        '-c', 'exit'
    ], check=True)

    with open(output_path, 'rb') as f:
        return f.read().decode('cp866')
```

### LTGOLD.EXE vs LTPRO.EXE

| | LTGOLD.EXE | LTPRO.EXE |
|--|-----------|----------|
| Mode | TUI (interactive menus) | Batch (command-line) |
| Batch use | Needs interactive keypresses | Fully automatic |
| Invocation | N/A | `LTPRO.EXE in.txt out.txt -F-` |

**Use LTPRO.EXE for all automated/batch translation.**

## Command-Line Reference (LTGCMD.HLP)

### Input/Output

| Flag | Purpose |
|------|---------|
| `/I inputfile` | Name of source file |
| `/I @parmfile` | Read parameters from file |
| `/I #idenfile` | Hot identifiers file |
| `/O outputfile` | Name of output file |
| `/D pathname` | Path to dictionaries directory |
| `/C dicchain` | Dictionary chain: c=COMPUTER.DIC, b=BUSINESS.DIC, u=USER.DIC (BASE.DIC always #1) |

### Display/Write

| Flag | Purpose |
|------|---------|
| `/WI` / `/WO` / `/WM` | Write source: Input / Output / Multiple Meanings |
| `/SI` / `/SO` / `/SM` | Display source: Input / Output / Multiple Meanings |
| `/S` | Display statistics |
| `/MM` | Display multiple meanings |
| `/AM` | Enable automatic meanings (domain-specific) |

### Editing

| Flag | Purpose |
|------|---------|
| `/P` | Pre-edit each sentence |
| `/E` | Post-edit each sentence |
| `/EE` | Post-edit every sentence |

### Formatting

| Flag | Purpose |
|------|---------|
| `/F-` | Disable output formatting |
| `/FL` | Flush output buffer |
| `/R <#>` | Right margin of output |
| `/LS <#>` | Characters per line |
| `/LH <#>` | Number of lines per sentence |

### Translation

| Flag | Purpose |
|------|---------|
| `/AR` | Enable automatic Russian (morphological generation) |
| `/X` | Tel-Lex mode (ASCII transliteration) |
| `/L-` | Transliteration off |
| `/M` | Russian characters allowed in source |
| `/U` | Collect unknown words |

### Special Input Markers

| Marker | Meaning |
|--------|---------|
| `{~` | Translation OFF (skip section) |
| `~}` | Translation ON |
| `{~=` | Transliteration ON |
| `{~#` | List mode (N words per line, 1-10) |
| `{~.` | Turn off list mode |

## Config File

`LTGOLD.CNF` is binary format ("LTech CNF File 2.00") — not human-editable.

## Reverse Engineering Rule Tables

### Approach

1. Decompress LTPRO.EXE (LZEXE-packed) using `UNLZEXE.EXE` in DOSBox-X
2. Find rule table offsets in the uncompressed binary
3. Patch tables by zeroing records, re-run to test effects

### Decompression

```sh
dosbox-x -silent \
  -c "mount c /path/to/LTGOLD" \
  -c "c:" \
  -c "UNLZEXE.EXE LTPRO.EXE" \
  -c "exit"
```

Produces uncompressed LTPRO.EXE (~208K) and renames original to LTPRO.OLZ.

### Data Section Layout

Borland C++ runtime signature at EXE offset `0x26754`. Data section base: `0x26750`.

LTGOLD.dat offsets are shifted by **242 bytes** in LTPRO.EXE:
`LTPRO_dat_offset = LTGOLD_dat_offset - 242`

### Rule Table Offsets (in LTPRO.EXE)

| Table | LTGOLD offset | LTPRO dat offset | Rec size | Rules | Role |
|-------|--------------|-----------------|----------|-------|------|
| T1 | 3374 | 0x0C3C | 10 | 47 | Clause boundary, discourse |
| T2 | 3854 | 0x0E1C | 10 | 157 | Modals, passive, relative clauses |
| T3 | 5434 | 0x1448 | 10 | 136 | That-clauses, relative pronouns |
| T4 | 11981 | 0x2DDB | 9 | 178 | Idioms, collocations, tags |
| T5 | 16610 | 0x3FF0 | 10 | 9 | Late cleanup (copula, "is the") |
| T6 | 16874 | 0x40F8 | 10 | 56 | Numeric validation (UNKNOWN FORMAT) |
| T7 | 17972 | 0x4542 | 8 | 35 | Structural validation (no actions) |
| T8 | 19158 | 0x49E4 | 8 | 83 | Final validation (no actions) |

### Record Formats

**10-byte** (T1, T2, T3, T5, T6):
```
[pattern_offset:u16] [0x22D5:u16] [action_offset:u16] [pad:u16] [flags:u16]
```

**9-byte** (T4):
```
[flags:u8] [pattern_offset:u16] [0x22D5:u16] [action_offset:u16] [pad:u8]
```

**8-byte** (T7, T8):
```
[pattern_offset:u16] [0x22D5:u16] [action_offset:u16] [flags:u16]
```

`0x22D5` is a Borland C runtime constant — not rule data.

### T6 Anomaly

T6 has a different internal structure than expected. Zeroing T6 crashes the program.
T6 must be skipped during patching. Its records have the same 10-byte format but
the flags field contains `0x22D5` (the constant) instead of actual flags.

### Patching Tool

`LTGOLD/patch_rules.py` — zeros rule table records in decompressed LTPRO.EXE.

```sh
cd LTGOLD
python3 patch_rules.py LTPRO.EXE LTPRO_PAT.EXE
```

### Testing

Individual table zeroing works — T4 alone changes output from 155→172 bytes,
proving the patch affects translation behavior. Tables T1-T5, T7 can be zeroed
individually without crashing. T6 must be skipped.

### Known Limitations

- Long filenames don't work — use 8.3 short names or `dir` to find them
- T6 record format is unknown — cannot be safely patched
- Output is CP866 encoded — decode with `.decode('cp866')`
