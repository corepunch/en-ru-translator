# Python Extraction Tools

These tools in `LTGOLD/` were used to reverse-engineer the LTGOLD.EXE binary and
extract the translation rules, dictionaries, and grammatical data.

## Core Extraction

| Tool | Purpose |
|------|---------|
| `extract.py` | Split EXE by null bytes, decode CP866 blocks, print Cyrillic strings |
| `extract2.py` | Parse rule tables from binary (10-byte records with flags + offsets) |

### `extract.py`

Quick and dirty string extraction. Splits the entire EXE on null bytes and tries
to decode each block as CP866. Prints any block containing Cyrillic characters.
Good for finding embedded data.

```sh
python3 extract.py
```

### `extract2.py`

Structured rule table extraction. Reads 10-byte records from known offsets in
`LTGOLD.dat`:

```
[flags:u16] [pattern_offset:u16] [unknown:u16] [action_offset:u16] [padding:u16]
```

Pattern and action are C-strings at their respective offsets (relative to start of
data section). Hardcoded `START` and `rec_size` values per table — adjust offsets
when targeting different rule sets.

```sh
python3 extract2.py  # outputs Lua table syntax
```

**Available table offsets** (edit `START` constant):

| START | rec_size | Notes |
|-------|----------|-------|
| 2136 | 10 | |
| 3374 | 10 | |
| 3854 | 10 | |
| 5434 | 10 | Active default |
| 11981 | 9 | |
| 16610 | 10 | |
| 16874 | 10 | |
| 17972 | 8 | |
| 19158 | 8 | |

## Hex Viewers

| Tool | Purpose |
|------|---------|
| `dump.py` | CLI hex/text dumper with CP866 decoding |
| `dump2.py` | Interactive curses hex viewer |

### `dump.py`

Non-interactive hex dump. Shows offset + hex + decoded text.
Useful for quick inspection of binary regions.

```sh
python3 dump.py LTGOLD.EXE --width 32 --group 4 --enc cp866
python3 dump.py LTGOLD.EXE --no-text          # hex only
python3 dump.py LTGOLD.EXE --no-hex           # text only
```

### `dump2.py`

Full curses-based hex editor/viewer. Supports:
- Keyboard navigation (arrows, PgUp/PgDn)
- Hex/text toggle (`h`, `t`)
- Pointer following (`x`) — highlights 16-bit pointers and shows dereferenced values
- Search (`/`) — hex value search with highlighting
- Mouse support (click to position, scroll wheel)
- Column width adjustment (`1`-`9`)

```sh
python3 dump2.py LTGOLD.EXE
python3 dump2.py LTGOLD.EXE --start 0x50000 --end 0x60000
python3 dump2.py LTGOLD.EXE --find16 0x2A2A  # highlight word 0x2A2A
```

**Controls:**

| Key | Action |
|-----|--------|
| `q` / Esc | Quit |
| `h` | Toggle hex view |
| `t` | Toggle text view |
| `o` | Toggle offset display |
| `x` | Toggle pointer following |
| `/` | Search (hex values) |
| `1`-`9` | Set column width |
| PgUp/PgDn | Page scroll |

## Analysis Tools

| Tool | Purpose |
|------|---------|
| `dump3.py` | MZ EXE header parser + data region detector |
| `find2.py` | Find dictionary separator bytes (`*`) near pattern delimiters |
| `find3.py` | Find long Latin strings in text files |
| `findaddr.py` | Brute-force pattern scanner for known offset sequences |

### `dump3.py`

Parses the DOS MZ EXE header, prints header fields, relocation table info, and
scans the load image for data-like regions (high density of printable characters
+ null bytes). Useful for locating embedded string tables.

```sh
python3 dump3.py LTGOLD.EXE
```

### `find2.py`

Searches for `0x2A` bytes (dictionary `*` separator) within 200 bytes of `0x7E`
or `0x60` bytes (pattern delimiters). Helps locate where rules and dictionary
entries are stored in the binary.

```sh
python3 find2.py
```

### `find3.py`

Finds consecutive Latin characters (default: 10+) in a text file. Helps locate
English words embedded in otherwise binary or mixed-format files.

```sh
python3 find3.py LTGOLD.EXE 10
python3 find3.py some_output.txt 5
```

### `findaddr.py`

Scans binary for three 16-bit words at known offset deltas (default: `+72`, `+15`).
When you know some data table entries and their offsets from each other, this finds
all matching locations. Used to locate paradigm tables and rule arrays.

Edit the `fst` and `snd` constants at the top of the file to set offset deltas.

```sh
python3 findaddr.py
```

## Data Manipulation

| Tool | Purpose |
|------|---------|
| `process.py` | Search for CP866-encoded Russian words across all files |
| `clear.py` | Zero out a byte range in a file (binary patching) |

### `process.py`

Walks a directory tree, searches every file for a given CP866-encoded Russian
string, prints surrounding context. Great for finding where a specific word
appears in the binary.

Edit the `target` variable at the top of the file to search for different words.

```sh
python3 process.py
```

### `clear.py`

Zeros out bytes in a file. Used for patching the binary when extracting or
modifying data sections.

```sh
python3 clear.py LTGOLD.EXE 0x50000 0x1000  # zero 4KB at offset 0x50000
```

## Russian Documentation Files

These files in `LTGOLD/` contain original documentation (CP866 encoded).
Read with: `python3 -c "print(open('file', 'rb').read().decode('cp866'))"`.

| File | Content |
|------|---------|
| `README.CYR` | Original README in Russian — system requirements, installation, features |
| `COMENT.DOC` | Modem/Connection board documentation (not translation-related) |
| `dic.txt` | **SARMA DIC format documentation** — dictionary structure, menu system, coding system. Key reference for understanding `*.DIC` and `*.RUS` formats |
| `NEWLTGE.DOC` | Update notes — transliteration codes `{~=...~}`, punctuation handling, dictionary peeking (`-@` switch) |
| `LTDOC.DOC` | Word macros for integration |
| `LTGOLDE.HLP` | English help text |
| `LTGOLDR.HLP` | Russian help text |

### Key Findings from Documentation

**From `NEWLTGE.DOC`:**
- Sentence boundary = period (`.`). Programs auto-detect abbreviations.
- If no period found, sentence breaks at 512th word.
- Transliteration markers: `{~=` (on), `~}` (off)
- `-@` switch: peek at dictionary selections during translation
- `-AR` switch: automatic Russian case generation (broken in this version)

**From `dic.txt`:**
- Dictionary format: `word*codes` per line
- `*` separator between word and grammatical codes
- Multi-word entries use spaces
- Dictionary expansion system documented

## Disassembly Findings (r2)

Disassembled `LTGOLD.EXE` with radare2 to understand rule processing:

### Rule Table Locations

Rules are stored in `LTGOLD.dat` — the data section extracted from `LTGOLD.EXE`
at offset `0x50960` (330080 bytes). The EXE was decompressed with `UNLZEXE.EXE`
before extraction. Key rule table offsets (discovered via `extract2.py` and hex analysis):

```
0x0D2E (3374)  - Table 1: 47 entries, 10-byte records
0x0F0E (3854)  - Table 2: 157 entries, 10-byte records
0x153A (5434)  - Table 3: 136 entries, 10-byte records
0x2ED5 (11981) - Table 4: 178 entries, 9-byte records
0x40E2 (16610) - Table 5: 9 entries, 10-byte records
0x41EA (16874) - Table 6: 56 entries, 10-byte records
0x4634 (17972) - Table 7: 35 entries, 8-byte records (no actions)
0x4AC6 (19158) - Table 8: 83 entries, 8-byte records (no actions)
```

### Code Analysis

The main rule processing function appears to be around `0x4D608` (called from
`0x418FE`). Key observations:

1. **Pattern matching** compares token types against pattern characters (Z, N, V, etc.)
2. **`*` (wildcard)** checks `j==1` (start) or `j>#ts` (end) — confirmed sentence boundary
3. **`~` (negation)** inverts the match result via XOR
4. **`[` (select)** matches one of listed characters
5. **`<` (any)** matches zero or more of listed characters
6. **`@` in action** triggers `find_and_replace()` on the current token
7. **`$` in action** references captured groups from `<...>` or `(...)`

The function at `0x4E1E3` handles replacement token processing — it compares
action bytes against `$` (0x24), `T` (0x54), `K` (0x4B) and dispatches accordingly.

<!-- TODO: Trace the full call chain from entry point to rule application.
     Identify how multiple tables are iterated.
     Map priority flags to processing order. -->

## Creating New Python Tools

When r2 isn't enough for a task, create a Python tool. Place them in `LTGOLD/`.

### When to Create a New Tool

- r2's `axt` doesn't find cross-references (common in 16-bit code)
- Need to parse a custom data format
- Need to search for patterns across the entire binary
- Need to visualize or count occurrences
- Need to extract data for further analysis

### Tool Template

```python
#!/usr/bin/env python3
"""
Purpose: [What this tool does]
Usage: python3 tool_name.py [args]
"""
import struct
import sys

FILENAME = "/Users/igor/Developer/en-ru-translator/LTGOLD/LTGOLD.EXE"

def read_cstring(data, base, offset):
    """Read null-terminated string from data at base+offset."""
    if offset == 0:
        return None
    pos = base + offset
    buf = []
    while pos < len(data) and data[pos] != 0:
        buf.append(data[pos])
        pos += 1
    return bytes(buf).decode('cp866', errors='replace')

def main():
    with open(FILENAME, 'rb') as f:
        data = f.read()
    
    # Your analysis logic here
    # ...

if __name__ == "__main__":
    main()
```

### Common Tasks

**Find all pointers to an address:**
```python
target = 0x0D2E  # offset to find references to
for i in range(len(data) - 1):
    val = struct.unpack_from('<H', data, i)[0]
    if val == target:
        print(f'Pointer at {i:08X}')
```

**Extract function bytes:**
```python
func_start = 0xD608
func_size = 3144  # from r2 afl output
func_bytes = data[func_start:func_start + func_size]
with open('function.bin', 'wb') as f:
    f.write(func_bytes)
```

**Count occurrences of a byte pattern:**
```python
pattern = bytes([0x2A, 0x00])  # "*\0"
count = data.count(pattern)
print(f'Found {count} occurrences of pattern')
```

**Extract all strings near an offset:**
```python
offset = 0x523F5  # near rule patterns
for i in range(offset - 100, offset + 100):
    if data[i] == 0x00:  # null terminator
        # try to read string before this
        j = i - 1
        while j > 0 and data[j] != 0x00:
            j -= 1
        s = data[j+1:i]
        if len(s) > 2:
            try:
                print(f'{j+1:08X}: {s.decode("cp866")}')
            except:
                pass
```

### r2 vs Python

| Task | r2 | Python |
|------|-----|--------|
| Decompile function | ✅ `pdg` | ❌ |
| Find cross-references | ✅ `axt` | ⚠️ Basic scanning only |
| Parse custom formats | ⚠️ `pf` templates | ✅ Full control |
| Search binary patterns | ✅ `/x` | ✅ With encoding support |
| Hex dump with context | ✅ `px` | ✅ Custom formatting |
| Batch analysis | ❌ | ✅ |
| CP866/Cyrillic support | ❌ | ✅ |

### r2 Features That Replace Python

- **`/x PATTERN`** — search for hex bytes (equivalent to `findaddr.py` for simple cases)
- **`axt @ ADDR`** — find cross-references (replaces manual pointer scanning)
- **`pdg @ ADDR`** — decompile to C (replaces manual disassembly)
- **`pf`** — print formatted data structures (replaces custom parsers)

But r2 has limitations with 16-bit code — Python tools give more control.
