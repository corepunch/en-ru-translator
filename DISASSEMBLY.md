# DISASSEMBLY.md — Reverse Engineering Guide for LTGOLD

Practical guide for disassembling LTGOLD.EXE with radare2, dis86, and related tools.

## Quick Reference

```sh
# r2: list all functions
r2 -q -e bin.cache=true -A -c "afl" -c q LTGOLD/LTGOLD.EXE

# r2: decompile a function
r2 -q -e bin.cache=true -A -c "pdg @ 0x0004d608" -c q LTGOLD/LTGOLD.EXE

# dis86: decompile with BSL config
cd LTGOLD && ../dis86/dis86/target/release/dis86 --config ltgold.bsl --binary-raw ltgold_code.bin --name fcn_0004d608 --emit-dis /tmp/output.dis

# Extract code segment from MZ EXE for dis86
dd if=LTGOLD/LTGOLD.EXE of=LTGOLD/ltgold_code.bin bs=1 skip=26880
```

## Extracting Code for dis86

dis86 accepts only a **flat binary region** (not MZ EXE directly). Extract the code segment:

```sh
# From MZ header: e_cparhdr=1680 paragraphs = 26880 bytes header
dd if=LTGOLD/LTGOLD.EXE of=LTGOLD/ltgold_code.bin bs=1 skip=26880
```

## BSL Config Format

BSL (Binary Specification Language) describes the binary's structure for dis86.

### Syntax

```
key value              # string property
key { ... }            # node (nested object)
key "quoted value"     # string with spaces
```

### Required Nodes

```
dis86 {
  code_segments {
    name {
      seg "XXXX"       # segment number (hex, no 0x prefix)
      name "name"      # human-readable name
    }
  }

  structures {}         # can be empty initially

  functions {
    name {
      start "XXXX:YYYY"  # segment:offset start
      end "XXXX:YYYY"    # segment:offset end
      mode "far"         # "far" or "near"
      ret "u16"          # return type: "u8", "u16", "u32", "i16", "None"
      args "4"           # number of args (or "None" for unknown)
    }
  }

  globals {}            # global variables
  text_section {}       # text section regions
}
```

### Function Properties

| Property | Required | Description |
|----------|----------|-------------|
| `start` | Yes | `seg:off` where function begins |
| `end` | Yes | `seg:off` where function ends |
| `mode` | Yes | `far` (uses `retf`) or `near` (uses `ret`) |
| `ret` | Yes | Return type: `u8`, `u16`, `u32`, `i16`, `None` |
| `args` | Yes | Argument count or `None` |
| `entry` | No | Entry point (if different from start) |
| `regargs` | No | Register arguments |
| `dont_pop_args` | No | If set, caller cleans stack |
| `indirect_call_location` | No | For indirect calls |

### Example BSL for LTGOLD

```bsl
dis86 {
  code_segments {
    main { seg "4000" name "main" }
  }

  structures {}

  functions {
    fcn_0004d608 {
      start "4000:d608"
      end "4000:e1e3"
      mode "far"
      ret "None"
      args "4"
    }
    fcn_0004e1e3 {
      start "4000:e1e3"
      end "4000:e95d"
      mode "far"
      ret "None"
      args "4"
    }
    fcn_000418fe {
      start "4000:18fe"
      end "4000:19e1"
      mode "far"
      ret "u16"
      args "4"
    }
  }

  globals {}
  text_section {}
}
```

## Workflow: Reverse Engineering with dis86

### Step 1: Identify Functions

Use r2 to find function boundaries:
```sh
r2 -q -e bin.cache=true -A -c "afl" -c q LTGOLD/LTGOLD.EXE
```

### Step 2: Create BSL Config

Write a BSL file describing each function:
- Start/end addresses (from r2 `afl`)
- Calling convention (far for DOS, near for internal)
- Return types (guess from context)
- Argument counts (from stack cleanup patterns)

### Step 3: Extract Code Segment

```sh
dd if=LTGOLD/LTGOLD.EXE of=LTGOLD/ltgold_code.bin bs=1 skip=26880
```

### Step 4: Run dis86

```sh
cd LTGOLD
../dis86/dis86/target/release/dis86 \
  --config ltgold.bsl \
  --binary-raw ltgold_code.bin \
  --name fcn_0004d608 \
  --emit-dis /tmp/fcn_0004d608.dis \
  --emit-code /tmp/fcn_0004d608.c
```

### Step 5: Generate Control Flow Graph

```sh
../dis86/dis86/target/release/dis86 \
  --config ltgold.bsl \
  --binary-raw ltgold_code.bin \
  --name fcn_0004d608 \
  --emit-graph /tmp/fcn_0004d608.dot

dot -Tpng /tmp/fcn_0004d608.dot > /tmp/fcn_0004d608.png
open /tmp/fcn_0004d608.png
```

### Step 6: Analyze and Annotate

- Name variables based on usage
- Add structs for data structures
- Mark globals
- Iterate: refine config, re-run dis86

## Gotchas

### 1. dis86 Needs Flat Binary, Not MZ

dis86 doesn't handle MZ format. Always extract the code segment first with `dd`.

### 2. Segment:Offset Format

BSL uses `XXXX:YYYY` format (no `0x` prefix):
- ✅ `4000:d608`
- ❌ `0x4000:0xd608`

### 3. Unsupported Instructions

dis86 may panic on unsupported 8086 instructions. Try smaller functions first.

### 4. Function Boundaries Must Be Exact

dis86 needs precise start/end addresses. If the function includes data after the `ret`/`retf`, the end address must be after that data.

### 5. Error Messages Are Misleading

Some error messages reference wrong property names (e.g., "Expected segoff for 'main.end'" when parsing `seg`). The actual issue is usually the format of the value.

## Documentation Sources

| File | Content |
|------|---------|
| `/tmp/dis86/README.md` | dis86 overview, commands, limitations |
| `/tmp/dis86/hydra/README.md` | Hydra runtime, function hooks, annotations |
| `/tmp/dis86/docs/mz_header.txt` | MZ EXE header dissection |
| `/tmp/dis86/docs/dos_memory_map.txt` | DOS memory map, MZ loading |
| `/tmp/dis86/docs/dos_psp.txt` | Program Segment Prefix layout |
| `/tmp/dis86/docs/dos_int21h.txt` | DOS INT 21h API reference |
| `/tmp/dis86/docs/8086_flags.txt` | 8086 flags reference |

## dis86 Output Formats

| Flag | Description |
|------|-------------|
| `--emit-dis` | Assembly disassembly |
| `--emit-ir-initial` | Initial SSA IR |
| `--emit-ir-final` | Optimized SSA IR |
| `--emit-graph` | Control flow graph (Graphviz DOT) |
| `--emit-ctrlflow` | High-level control flow structure |
| `--emit-ast` | Abstract Syntax Tree |
| `--emit-code` | C code |

## Building dis86

```sh
git clone https://github.com/xorvoid/dis86.git /tmp/dis86

# Fix compilation error
sed -i '' 's/slice.as_ptr())/slice.as_ptr() as *const i8)/' \
  /tmp/dis86/dis86/src/emu86/mem.rs

source ~/.cargo/env
cd /tmp/dis86/dis86 && cargo build --release

# Binary: /tmp/dis86/dis86/target/release/dis86
```

## Hydra Workflow (Future)

For hybrid runtime (decompile + run):
1. Create annotations (functions, globals, structs)
2. Generate Hydra appdata sources
3. Compile decompiled functions to native code
4. Run hybrid: dosbox-x emulation + native code callbacks

See `/tmp/dis86/hydra/README.md` for details.
