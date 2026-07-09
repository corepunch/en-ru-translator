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
