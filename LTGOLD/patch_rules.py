#!/usr/bin/env python3
"""
patch_rules.py — Zero out rule tables in decompressed LTPRO.EXE

Usage:
    python3 patch_rules.py [input.exe] [output.exe]

If no args, defaults to:
    input:  LTPRO.EXE (decompressed)
    output: LTPRO.PAT.EXE (patched)

The patcher zeros out all 8 rule table records in the data section,
effectively disabling all grammatical transformation rules.
"""
import struct
import sys
import os

# === Configuration ===

# Data section base in decompressed LTPRO.EXE
# Borland C++ string is at EXE offset 0x26754, data section starts 4 bytes before
BORLAND_OFFSET = 0x26754
DAT_BASE = BORLAND_OFFSET - 4  # 0x26750

# Rule table offsets in LTGOLD.dat (from RESEARCH.md)
# LTPRO.EXE data section is shifted by 242 bytes from LTGOLD.dat
SHIFT = 242

LTGOLD_TABLE_OFFSETS = {
    'suffix': 2136,   # Suffix/stem rules (not part of main rule system)
    'T1': 3374,       # Table 1: 47 rules, 10-byte records
    'T2': 3854,       # Table 2: 157 rules, 10-byte records
    'T3': 5434,       # Table 3: 136 rules, 10-byte records
    'T4': 11981,      # Table 4: 178 rules, 9-byte records
    'T5': 16610,      # Table 5: 9 rules, 10-byte records
    # T6 SKIPPED: different record format, critical for program function
    # 'T6': 16874,    # Table 6: 56 rules, 10-byte records (UNKNOWN FORMAT)
    'T7': 17972,      # Table 7: 35 rules, 8-byte records
    'T8': 19158,      # Table 8: 83 rules, 8-byte records
}

# Override: use exact rule counts from RESEARCH.md instead of auto-detection
# This prevents zeroing data between tables
EXACT_RULE_COUNTS = {
    'suffix': 0,  # skip suffix table
    'T1': 47,
    'T2': 157,
    'T3': 136,
    'T4': 178,
    'T5': 9,
    'T7': 35,
    'T8': 83,
}

# Record sizes for each table
TABLE_RECORD_SIZES = {
    'suffix': 10,
    'T1': 10,
    'T2': 10,
    'T3': 10,
    'T4': 9,
    'T5': 10,
    # T6 skipped: unknown record format
    'T7': 8,
    'T8': 8,
}

# Max rules per table (from RESEARCH.md)
TABLE_MAX_RULES = {
    'suffix': 50,  # approximate
    'T1': 47,
    'T2': 157,
    'T3': 136,
    'T4': 178,
    'T5': 9,
    # T6 skipped: unknown format
    'T7': 35,
    'T8': 83,
}


def read_cstring(data, base, offset):
    """Read a C-string from data section"""
    if offset == 0:
        return None
    pos = base + offset
    if pos < 0 or pos >= len(data):
        return None
    buf = []
    while pos < len(data) and data[pos] != 0:
        buf.append(data[pos])
        pos += 1
    return bytes(buf).decode('cp866', errors='replace')


def find_table_end(data, table_name, start_dat_off):
    """Find where a table ends by looking for the end-of-table marker"""
    rec_size = TABLE_RECORD_SIZES[table_name]
    max_rules = TABLE_MAX_RULES[table_name]
    
    i = start_dat_off
    rules_found = 0
    
    while rules_found < max_rules + 10:  # allow some slack
        exe_off = DAT_BASE + i
        
        if table_name in ('T4',):
            # 9-byte record: [flags:u8] [pat_off:u16] [const:u16] [act_off:u16] [pad:u8]
            if exe_off + 9 > len(data):
                break
            flags = data[exe_off]
            pat_off = struct.unpack_from('<H', data, exe_off + 1)[0]
            act_off = struct.unpack_from('<H', data, exe_off + 5)[0]
        elif table_name in ('T7', 'T8'):
            # 8-byte record: [pat_off:u16] [const:u16] [act_off:u16] [flags:u16]
            if exe_off + 8 > len(data):
                break
            pat_off = struct.unpack_from('<H', data, exe_off)[0]
            act_off = struct.unpack_from('<H', data, exe_off + 4)[0]
            flags = struct.unpack_from('<H', data, exe_off + 6)[0]
        else:
            # 10-byte record: [pat_off:u16] [const:u16] [act_off:u16] [pad:u16] [flags:u16]
            if exe_off + 10 > len(data):
                break
            pat_off = struct.unpack_from('<H', data, exe_off)[0]
            act_off = struct.unpack_from('<H', data, exe_off + 4)[0]
            flags = struct.unpack_from('<H', data, exe_off + 8)[0]
        
        # End of table: all key fields are zero
        if pat_off == 0 and act_off == 0:
            return i
        
        rules_found += 1
        i += rec_size
    
    return i  # fallback: max rules * rec_size


def patch_table(data, table_name, dry_run=False):
    """Zero out all records in a table. Returns (start, end, count)"""
    ltgold_off = LTGOLD_TABLE_OFFSETS[table_name]
    dat_off = ltgold_off - SHIFT
    rec_size = TABLE_RECORD_SIZES[table_name]
    
    # Use exact rule count if available, otherwise auto-detect
    if table_name in EXACT_RULE_COUNTS:
        rule_count = EXACT_RULE_COUNTS[table_name]
        table_end = dat_off + rule_count * rec_size
    else:
        # Find actual table end
        table_end = find_table_end(data, table_name, dat_off)
        rule_count = (table_end - dat_off) // rec_size
    
    table_size = table_end - dat_off
    
    exe_start = DAT_BASE + dat_off
    exe_end = DAT_BASE + table_end
    
    if not dry_run:
        # Zero out all records
        for i in range(exe_start, exe_end):
            data[i] = 0
    
    return dat_off, table_end, rule_count


def main():
    input_file = sys.argv[1] if len(sys.argv) > 1 else 'LTPRO.EXE'
    output_file = sys.argv[2] if len(sys.argv) > 2 else 'LTPRO.PAT.EXE'
    dry_run = '--dry-run' in sys.argv
    
    if not os.path.exists(input_file):
        print(f'Error: {input_file} not found')
        sys.exit(1)
    
    with open(input_file, 'rb') as f:
        data = bytearray(f.read())
    
    print(f'Input:  {input_file} ({len(data)} bytes)')
    print(f'Output: {output_file}')
    print(f'Data section base: 0x{DAT_BASE:X}')
    print()
    
    total_rules = 0
    total_bytes = 0
    
    for table_name in ['suffix', 'T1', 'T2', 'T3', 'T4', 'T5', 'T7', 'T8']:
        start, end, count = patch_table(data, table_name, dry_run)
        size = end - start
        total_rules += count
        total_bytes += size
        exe_start = DAT_BASE + start
        exe_end = DAT_BASE + end
        print(f'{table_name:7s}: dat 0x{start:05X}-0x{end:05X} '
              f'exe 0x{exe_start:05X}-0x{exe_end:05X} '
              f'{count:4d} rules, {size:5d} bytes')
    
    print(f'\nTotal: {total_rules} rules, {total_bytes} bytes zeroed')
    
    if dry_run:
        print('\n[DRY RUN — no changes written]')
    else:
        with open(output_file, 'wb') as f:
            f.write(data)
        print(f'\nPatched file written to {output_file}')
    
    # Verify: read back and check first record of Table 1
    if not dry_run:
        with open(output_file, 'rb') as f:
            verify = f.read()
        t1_start = DAT_BASE + (LTGOLD_TABLE_OFFSETS['T1'] - SHIFT)
        v = struct.unpack_from('<H', verify, t1_start)[0]
        print(f'\nVerification: Table 1 first pat_off = {v} (should be 0)')


if __name__ == '__main__':
    main()
