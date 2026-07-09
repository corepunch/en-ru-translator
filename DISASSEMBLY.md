# DISASSEMBLY.md — Reverse Engineering Guide for LTGOLD

Primary tool: **radare2 with r2ghidra** for decompilation and analysis.
Fallback: **dis86** only if r2 output is too messy.

## Workflow (r2ghidra-centric)

### Step 1: Open and Analyze

```sh
r2 -q -e bin.cache=true -A LTGOLD/LTGOLD.EXE
```

### Step 2: List Functions

```
afl
```

Shows all 867 functions with addresses, block counts, and sizes.

### Step 3: Decompile a Function

```
pdg @ 0x0004d608
```

Outputs C code via r2ghidra. Save to file:

```sh
r2 -q -e bin.cache=true -A -c "pdg @ 0x0004d608" -c q LTGOLD/LTGOLD.EXE \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -v "^//" > /tmp/ltgold_4d608.c
```

### Step 4: Search the Decompiled C

```sh
rg "pattern" /tmp/ltgold_4d608.c
```

### Step 5: Cross-References

```
axt @ 0x0004d608
```

Find who calls this function.

### Step 6: Go Back to r2 for Details

When you find something interesting in the C code, go back to r2 for exact addresses and context:

```
pd 50 @ 0x0004e1e3   # disassemble specific region
px 64 @ 0x523F5      # hex dump at data location
```

## Key Functions (Already Decompiled)

| Function | Address | Size | File | Role |
|----------|---------|------|------|------|
| `fcn.0004d608` | `0x4D608` | 3144 bytes | `/tmp/ltgold_4d608.c` | Rule processing (355 blocks) |
| `fcn.0004e1e3` | `0x4E1E3` | 654 bytes | `/tmp/ltgold_4e1e3.c` | Replacement handler |

## Regenerating Decompiled C

```sh
# Rule processor
r2 -q -e bin.cache=true -A -c "pdg @ 0x0004d608" -c q LTGOLD/LTGOLD.EXE \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -v "^//" > /tmp/ltgold_4d608.c

# Replacement handler
r2 -q -e bin.cache=true -A -c "pdg @ 0x0004e1e3" -c q LTGOLD/LTGOLD.EXE \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -v "^//" > /tmp/ltgold_4e1e3.c
```

## Quick Commands

| Task | Command |
|------|---------|
| List functions | `afl` |
| Decompile | `pdg @ ADDR` |
| Cross-refs | `axt @ ADDR` |
| Hex dump | `px 64 @ ADDR` |
| Disassemble | `pd 50 @ ADDR` |
| Search bytes | `/x PATTERN` |
| Search strings | `iz~STRING` |

## When to Use dis86 (Fallback)

Use dis86 **only if** r2's output is too messy to understand:

- Control flow is unclear in decompiled C
- Need cleaner SSA IR representation
- Need control flow graph visualization

See [Advanced Tools: dis86](#advanced-tools-dis86) below.

## Gotchas

### 1. 16-bit Real Mode

LTGOLD is 16-bit DOS. Segment:offset addressing (e.g., `4000:d608`).

### 2. ANSI Color Codes

r2ghidra output has ANSI codes. Strip with:
```sh
sed 's/\x1b\[[0-9;]*m//g'
```

### 3. Borland C++ Calling Convention

Functions use register-based args (AX, DX, BX, CX) + stack. Decompiled code has many `in_register_XXXX` variables.

### 4. Inline Assembly

Borland C++ uses inline `asm` blocks. r2ghidra sometimes misinterprets these.

### 5. Data in Code Section

Rule tables are stored as data within the code section. r2 may try to disassemble data as code.

## Extracted Data

| File | Content |
|------|---------|
| `LTGOLD.dat` | Data section extracted from EXE at offset `0x50960` (61376 bytes) |
| `LTGOLD/ltgold.bsl` | BSL config for dis86 (fallback tool) |

## Reference Documents

| File | Content |
|------|---------|
| `RESEARCH.md` | All findings from reverse engineering |
| `docs/` | Detailed documentation (pipeline, paradigms, rules, etc.) |

---

## Advanced Tools: dis86

**Use only if r2 output is too messy.**

dis86 is a purpose-built decompiler for 16-bit real-mode DOS binaries. Better
control flow analysis, but requires more setup.

### Building dis86

```sh
git clone https://github.com/xorvoid/dis86.git /tmp/dis86
sed -i '' 's/slice.as_ptr())/slice.as_ptr() as *const i8)/' \
  /tmp/dis86/dis86/src/emu86/mem.rs
source ~/.cargo/env && cd /tmp/dis86/dis86 && cargo build --release
```

### Extract Code for dis86

dis86 needs flat binary (not MZ EXE):

```sh
dd if=LTGOLD/LTGOLD.EXE of=LTGOLD/ltgold_code.bin bs=1 skip=26880
```

### BSL Config Format

```bsl
dis86 {
  code_segments { main { seg "4000" name "main" } }
  structures {}
  functions {
    fcn_0004d608 {
      start "4000:d608"
      end "4000:e1e3"
      mode "far"
      ret "None"
      args "4"
    }
  }
  globals {}
  text_section {}
}
```

### Running dis86

```sh
cd LTGOLD
../dis86/dis86/target/release/dis86 \
  --config ltgold.bsl \
  --binary-raw ltgold_code.bin \
  --name fcn_0004d608 \
  --emit-dis /tmp/fcn.dis \
  --emit-code /tmp/fcn.c
```

### Control Flow Graph

```sh
../dis86/dis86/target/release/dis86 \
  --config ltgold.bsl \
  --binary-raw ltgold_code.bin \
  --name fcn_0004d608 \
  --emit-graph /tmp/fcn.dot

dot -Tpng /tmp/fcn.dot > /tmp/fcn.png
open /tmp/fcn.png
```

### dis86 vs r2ghidra

| Aspect | r2ghidra | dis86 |
|--------|----------|-------|
| Setup | None | BSL config + flat binary |
| Output | C code with warnings | Cleaner C + IR + AST |
| Control flow | Basic | Graphviz visualization |
| 16-bit support | Decent | Purpose-built |
| Speed | Fast | Needs compilation |
| **Recommendation** | **Primary** | Fallback |
