# DISASSEMBLY.md — Reverse Engineering Guide for LTGOLD

Practical guide for disassembling LTGOLD.EXE with radare2. Contains know-hows,
gotchas, and workflow tips from experience.

## Quick Start

```sh
# Open EXE in r2 with analysis
r2 -q -e bin.cache=true -A /Users/igor/Developer/en-ru-translator/LTGOLD/LTGOLD.EXE

# List all functions
afl

# Decompile a function to C
pdg @ 0x0004d608

# Find cross-references (who calls this function?)
axt @ 0x0004d608

# Search for byte patterns
/x 5A5B  # search for "Z[" (pattern syntax)
```

## Essential r2 Commands

### Analysis & Navigation

| Command | Description |
|---------|-------------|
| `aaa` | Full auto-analysis |
| `afl` | List all functions |
| `axt @ ADDR` | Cross-references to address |
| `axf @ ADDR` | Cross-references from address |
| `pd N @ ADDR` | Disassemble N instructions |
| `pdg @ ADDR` | Decompile to C (r2ghidra) |
| `pD N @ ADDR` | Disassemble N bytes |
| `/x PATTERN` | Search for hex pattern |
| `iz` | List strings |
| `iz~STRING` | Search strings with grep |

### Hex Search Tips

```sh
# Search for a string in binary
/x 2A5A5B3F  # "*Z[?" — start of pattern
/x 5A2A00    # "Z*\0" — verb followed by boundary

# Search for offsets (little-endian)
/x 2E0D  # offset 0x0D2E (3374)
/x 0E0F  # offset 0x0F0E (3854)
/x 3A15  # offset 0x153A (5434)
```

## Gotchas

### 1. 16-bit Real Mode Code

LTGOLD.EXE is a **16-bit DOS real mode** executable (Borland C++). This means:

- **Segment:Offset addressing** — `4000:d608` means segment 0x4000, offset 0xD608
- **Segment registers matter** — CS, DS, ES, SS are all used
- **Far calls** — `lcall` instructions jump across segments
- **Stack-based parameter passing** — many args passed via stack, not registers

**Gotcha:** r2 sometimes shows absolute addresses (like `0x0004d608`) but the actual
execution uses segment:offset pairs. The loader relocates segments at runtime.

### 2. Borland C++ Calling Convention

Borland C++ for DOS uses a mix of:
- **Register-based** — first args in AX, DX, BX, CX
- **Stack-based** — additional args on stack
- **Pascal convention** — callee cleans up stack

**Gotcha:** Decompiled code has many `in_register_XXXX` variables because r2ghidra
can't determine which registers hold parameters.

### 3. Inline Assembly

The EXE contains lots of inline assembly (Borland C++ `asm` blocks). r2ghidra
sometimes misinterprets these as regular instructions.

**Gotcha:** When you see garbage instructions or weird control flow, it's often
inline assembly that r2ghidra didn't handle well.

### 4. Data Embedded in Code

The rule tables are stored as data within the code section. r2 might try to
disassemble data as code.

**Gotcha:** Always check if an address is actually code or data. Use `db` to
define data regions if needed.

### 5. Relocation Table

The EXE has a relocation table at offset `0x1FA` (from `e_lfarlc` in MZ header).
This table lists addresses that need segment adjustment at load time.

**Gotcha:** Addresses in the binary may differ from runtime addresses due to
segment relocation.

## Python Tools for Reverse Engineering

When r2 isn't enough, create Python tools to analyze the binary.

### When to Use Python vs r2

| Task | Tool | Why |
|------|------|-----|
| Decompile function | r2 `pdg` | r2ghidra handles this well |
| Find cross-references | r2 `axt` | Built-in analysis |
| Extract strings | Python `extract.py` | Simpler, more control |
| Parse data tables | Python `extract2.py` | Custom format parsing |
| Hex dump with context | Python `dump.py` | Custom output format |
| Search for patterns | Python `findaddr.py` | Brute-force scanning |
| Find Russian text | Python `process.py` | CP866 encoding support |

### Creating New Python Tools

Follow this template when you need a new analysis tool:

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

### Useful Python Patterns

**Find all pointers to an address:**
```python
import struct
target = 0x0D2E  # offset to find references to
for i in range(len(data) - 1):
    val = struct.unpack_from('<H', data, i)[0]
    if val == target:
        print(f'Pointer at {i:08X}')
```

**Extract function body:**
```python
# Extract bytes for a specific function
func_start = 0xD608
func_size = 3144  # from r2 afl output
func_bytes = data[func_start:func_start + func_size]
with open('function.bin', 'wb') as f:
    f.write(func_bytes)
```

**Parse rule table with different record sizes:**
```python
def parse_table(data, offset, count, record_size):
    rules = []
    for i in range(count):
        pos = offset + i * record_size
        if record_size == 10:
            pat_off, unk1, act_off, unk2, flags = struct.unpack('<HHHHH', data[pos:pos+10])
        elif record_size == 9:
            flags = data[pos]
            pat_off = struct.unpack('<H', data[pos+1:pos+3])[0]
            act_off = struct.unpack('<H', data[pos+5:pos+7])[0]
        elif record_size == 8:
            pat_off, unk1, act_off, flags = struct.unpack('<HHHH', data[pos:pos+8])
        
        pattern = read_cstring(data, 0, pat_off) if pat_off else None
        action = read_cstring(data, 0, act_off) if act_off else None
        rules.append({'flags': flags, 'pattern': pattern, 'action': action})
    return rules
```

## Workflow: Analyzing a New Function

1. **Find the function** — `afl` to list, or search for known addresses
2. **Check cross-references** — `axt @ ADDR` to see who calls it
3. **Decompile** — `pdg @ ADDR` to get C code
4. **Read the C code** — look for comparisons, loops, function calls
5. **Map constants** — compare hex constants to known values (e.g., `0x54` = 'T')
6. **Trace data flow** — follow pointers and function calls
7. **Document findings** — update RESEARCH.md with new discoveries

## Extracted C Code

Decompiled functions are saved in `/tmp/` for reference:

| File | Function | Size | Notes |
|------|----------|------|-------|
| `/tmp/ltgold_4d608.c` | `fcn.0004d608` | 4188 lines | Main rule processor |
| `/tmp/ltgold_4e1e3.c` | `fcn.0004e1e3` | 233 lines | Replacement handler |

To regenerate:
```sh
r2 -q -e bin.cache=true -A -c "pdg @ 0x0004d608" -c q LTGOLD.EXE | sed 's/\x1b\[[0-9;]*m//g' | grep -v "^//"
```

## Resources

- [radare2 book](https://book.rada.re/)
- [r2ghidra](https://github.com/radareorg/r2ghidra)
- [Borland C++ DOS calling conventions](https://en.wikipedia.org/wiki/Borland_C%2B%2B)
