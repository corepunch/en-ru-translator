#!/usr/bin/env python3
"""
patch_rules.py — Patch rule tables in decompressed LTPRO.EXE

Usage:
    # Zero ALL tables (original behavior):
    python3 patch_rules.py [input.exe] [output.exe]

    # Zero a SINGLE table:
    python3 patch_rules.py [input.exe] [output.exe] --table T2

    # Zero a SINGLE rule within a table (0-indexed):
    python3 patch_rules.py [input.exe] [output.exe] --table T2 --rule 5

    # Dry run (no file written):
    python3 patch_rules.py [input.exe] [output.exe] --table T2 --dry-run

Defaults:
    input:  LTPRO.EXE (decompressed, 208K)
    output: LTPRO.PAT.EXE (patched)
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
    # T6 has 47 real records followed by a null sentinel. Earlier tooling counted
    # string-pool bytes as nine extra records, so whole-table patches corrupted the EXE.
    'T6': 16700,      # Table 6: 47 rules, EXE offset 0x2A79A
    'T7': 17972,      # Table 7: 35 rules, 8-byte records
    'T8': 19158,      # Table 8: 83 rules, 8-byte records
}

EXACT_RULE_COUNTS = {
    'suffix': 0,  # skip suffix table
    'T1': 47,
    'T2': 157,
    'T3': 136,
    'T4': 178,
    'T5': 9,
    'T6': 47,
    'T7': 35,
    'T8': 83,
}

TABLE_RECORD_SIZES = {
    'suffix': 10,
    'T1': 10,
    'T2': 10,
    'T3': 10,
    'T4': 9,
    'T5': 10,
    'T6': 10,
    'T7': 8,
    'T8': 8,
}

TABLE_MAX_RULES = {
    'suffix': 50,
    'T1': 47,
    'T2': 157,
    'T3': 136,
    'T4': 178,
    'T5': 9,
    'T6': 47,
    'T7': 35,
    'T8': 83,
}

ALL_TABLES = ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8']

# Unused zero-filled space between the cleanup records and T7. Experimental strings
# live only in the generated EXE, leaving the original shared string pool untouched.
EXPERIMENT_STRING_OFFSET = 0x2AC50
EXPERIMENT_STRING_CAPACITY = 32


def read_cstring(data, base, offset):
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


def get_table_exe_range(table_name):
    """Return (exe_start, exe_end, rule_count, rec_size) for a table."""
    ltgold_off = LTGOLD_TABLE_OFFSETS[table_name]
    dat_off = ltgold_off - SHIFT
    rec_size = TABLE_RECORD_SIZES[table_name]
    rule_count = EXACT_RULE_COUNTS[table_name]
    exe_start = DAT_BASE + dat_off
    exe_end = exe_start + rule_count * rec_size
    return exe_start, exe_end, rule_count, rec_size


def validate_table_layout(data, table_name):
    """Reject a bad table coordinate before a patch can modify unrelated EXE data."""
    exe_start, exe_end, rule_count, rec_size = get_table_exe_range(table_name)
    if exe_start < 0 or exe_end > len(data):
        raise ValueError(f'{table_name}: record range is outside the executable')
    # T1-T4 and T6-T8 have an all-zero record sentinel immediately after the table.
    # T5 is fixed-count and intentionally has no sentinel at this boundary.
    if table_name != 'T5' and any(data[exe_end:exe_end + rec_size]):
        raise ValueError(
            f'{table_name}: expected zero sentinel at EXE offset 0x{exe_end:X}; '
            'refusing to use an unverified table offset'
        )


def get_record_string_offsets(data, table_name, rule_index):
    """
    Return the file offsets of pattern and action C-strings for one rule record.
    Records contain far pointers [str_off:u16][seg:u16] per string field.
    Zeroing the string bytes (not the record) is the safe patch strategy.
    Returns list of (file_offset, length) for each non-empty string field.
    """
    ltgold_off = LTGOLD_TABLE_OFFSETS[table_name]
    dat_off = ltgold_off - SHIFT
    rec_size = TABLE_RECORD_SIZES[table_name]
    exe_rec = DAT_BASE + dat_off + rule_index * rec_size

    results = []

    def add_string(off):
        if off == 0:
            return
        file_off = DAT_BASE + off
        length = 0
        while file_off + length < len(data) and data[file_off + length] != 0:
            length += 1
        if length > 0:
            results.append((file_off, length))

    if table_name == 'T4':
        # 9-byte: [flags:u8][pat_off:u16][pat_seg:u16][act_off:u16][act_seg:u16] — approximate
        pat_off = struct.unpack_from('<H', data, exe_rec + 1)[0]
        act_off = struct.unpack_from('<H', data, exe_rec + 5)[0]
    elif table_name in ('T7', 'T8'):
        # 8-byte: [pat_off:u16][pat_seg:u16][act_off:u16][act_seg:u16]
        pat_off = struct.unpack_from('<H', data, exe_rec)[0]
        act_off = struct.unpack_from('<H', data, exe_rec + 4)[0]
    else:
        # 10-byte: [pat_off:u16][pat_seg:u16][act_off:u16][act_seg:u16][flags:u16]
        pat_off = struct.unpack_from('<H', data, exe_rec)[0]
        act_off = struct.unpack_from('<H', data, exe_rec + 4)[0]

    add_string(pat_off)
    add_string(act_off)
    return results


def patch_table(data, table_name, rule_index=None, dry_run=False):
    """
    Disable rules by replacing the first pattern byte with '@'.
    '@' is an action operator, not an input tag, so the pattern remains non-empty
    but cannot match. Both 0x00 and 0xFF crash some LTPRO table scanners.
    The record pointers and string lengths are left intact.
    rule_index: if None, patch all records; if int, patch only that record (0-indexed).
    Returns (exe_start, exe_end, count_patched).
    """
    validate_table_layout(data, table_name)
    exe_start, exe_end, rule_count, rec_size = get_table_exe_range(table_name)

    if rule_index is not None and (rule_index < 0 or rule_index >= rule_count):
        raise ValueError(f"Rule index {rule_index} out of range 0..{rule_count-1} for {table_name}")

    indices = [rule_index] if rule_index is not None else range(rule_count)
    count = 0
    for i in indices:
        pairs = get_record_string_offsets(data, table_name, i)
        # Only the pattern controls whether a record can fire. Action strings are
        # pooled and shared, so clearing one can silently alter many other rules.
        for file_off, length in pairs[:1]:
            # Keep the C string non-empty because T6 crashes on an empty pattern.
            if not dry_run:
                data[file_off] = ord('@')
            count += 1

    if rule_index is not None:
        rec_start = exe_start + rule_index * rec_size
        return rec_start, rec_start + rec_size, 1
    return exe_start, exe_end, rule_count


def replace_record_action(data, table_name, rule_index, action, dry_run=False):
    """Point one rule at an isolated experimental action string."""
    encoded = action.encode('cp866')
    if len(encoded) + 1 > EXPERIMENT_STRING_CAPACITY:
        raise ValueError(f'experimental action is limited to {EXPERIMENT_STRING_CAPACITY - 1} bytes')
    validate_table_layout(data, table_name)
    exe_start, exe_end, rule_count, rec_size = get_table_exe_range(table_name)
    if rule_index < 0 or rule_index >= rule_count:
        raise ValueError(f"rule index {rule_index} out of range 0..{rule_count-1}")
    record = exe_start + rule_index * rec_size
    action_field = record + (5 if table_name == 'T4' else 4)
    pointer = EXPERIMENT_STRING_OFFSET - DAT_BASE
    if not dry_run:
        data[EXPERIMENT_STRING_OFFSET:EXPERIMENT_STRING_OFFSET + EXPERIMENT_STRING_CAPACITY] = \
            encoded + b'\0' * (EXPERIMENT_STRING_CAPACITY - len(encoded))
        struct.pack_into('<H', data, action_field, pointer)
    return record, record + rec_size, 1


def dump_table(data, table_name, max_rules=None):
    """Print all records in a table as human-readable strings."""
    validate_table_layout(data, table_name)
    ltgold_off = LTGOLD_TABLE_OFFSETS[table_name]
    dat_off = ltgold_off - SHIFT
    rec_size = TABLE_RECORD_SIZES[table_name]
    rule_count = EXACT_RULE_COUNTS[table_name]
    if max_rules:
        rule_count = min(rule_count, max_rules)

    print(f"\n=== {table_name} ({rule_count} rules, {rec_size}-byte records) ===")
    for i in range(rule_count):
        exe_off = DAT_BASE + dat_off + i * rec_size

        if table_name == 'T4':
            flags = data[exe_off]
            pat_off = struct.unpack_from('<H', data, exe_off + 1)[0]
            act_off = struct.unpack_from('<H', data, exe_off + 5)[0]
        elif table_name in ('T7', 'T8'):
            pat_off = struct.unpack_from('<H', data, exe_off)[0]
            act_off = struct.unpack_from('<H', data, exe_off + 4)[0]
            flags = struct.unpack_from('<H', data, exe_off + 6)[0]
        else:
            pat_off = struct.unpack_from('<H', data, exe_off)[0]
            act_off = struct.unpack_from('<H', data, exe_off + 4)[0]
            flags = struct.unpack_from('<H', data, exe_off + 8)[0]

        # Strings are relative to the data section base in LTGOLD.dat coordinates
        # but stored as offsets into the data block; use DAT_BASE as the base
        pat_str = read_cstring(data, DAT_BASE, pat_off) if pat_off else ''
        act_str = read_cstring(data, DAT_BASE, act_off) if act_off else ''

        print(f"  {table_name}[{i:03d}]  flags=0x{flags:02X}  "
              f"pat={repr(pat_str):30s}  act={repr(act_str)}")


def main():
    args = sys.argv[1:]

    # Parse flags
    dry_run = '--dry-run' in args
    if dry_run:
        args.remove('--dry-run')

    target_table = None
    if '--table' in args:
        idx = args.index('--table')
        target_table = args[idx + 1]
        del args[idx:idx+2]
        if target_table not in LTGOLD_TABLE_OFFSETS:
            print(f"Error: unknown table '{target_table}'. Valid: {list(LTGOLD_TABLE_OFFSETS.keys())}")
            sys.exit(1)

    target_rule = None
    if '--rule' in args:
        idx = args.index('--rule')
        target_rule = int(args[idx + 1])
        del args[idx:idx+2]

    replacement_action = None
    if '--action' in args:
        idx = args.index('--action')
        replacement_action = args[idx + 1]
        del args[idx:idx+2]

    dump_only = '--dump' in args
    if dump_only:
        args.remove('--dump')

    input_file = args[0] if len(args) > 0 else 'LTPRO.EXE'
    output_file = args[1] if len(args) > 1 else 'LTPRO.PAT.EXE'

    if not os.path.exists(input_file):
        print(f'Error: {input_file} not found')
        sys.exit(1)

    with open(input_file, 'rb') as f:
        data = bytearray(f.read())

    print(f'Input:  {input_file} ({len(data)} bytes)')

    if dump_only:
        tables = [target_table] if target_table else ALL_TABLES
        for t in tables:
            dump_table(data, t)
        return

    print(f'Output: {output_file}')
    print(f'Data section base: 0x{DAT_BASE:X}')
    print()

    if target_table:
        # Patch one table (or one rule within it)
        if replacement_action is not None:
            if target_rule is None:
                print('Error: --action requires --rule')
                sys.exit(1)
            start, end, count = replace_record_action(
                data, target_table, target_rule, replacement_action, dry_run)
        else:
            start, end, count = patch_table(data, target_table, target_rule, dry_run)
        label = f"rule {target_rule}" if target_rule is not None else "all rules"
        operation = f'action={replacement_action!r}' if replacement_action is not None else 'disabled'
        print(f'{target_table} ({label}): exe 0x{start:05X}-0x{end:05X}, {operation}')
    else:
        # Patch all tables
        total_rules = 0
        total_bytes = 0
        for table_name in ALL_TABLES:
            start, end, count = patch_table(data, table_name, None, dry_run)
            size = end - start
            total_rules += count
            total_bytes += size
            print(f'{table_name:7s}: exe 0x{start:05X}-0x{end:05X}  {count:4d} rules, {size:5d} bytes')
        print(f'\nTotal: {total_rules} rules, {total_bytes} record bytes covered')

    if dry_run:
        print('\n[DRY RUN — no changes written]')
        return

    with open(output_file, 'wb') as f:
        f.write(data)
    print(f'\nPatched file written to {output_file}')

    # Verify
    if not target_table:
        with open(output_file, 'rb') as f:
            verify = f.read()
        t1_start = DAT_BASE + (LTGOLD_TABLE_OFFSETS['T1'] - SHIFT)
        v = struct.unpack_from('<H', verify, t1_start)[0]
        print(f'Verification: Table 1 first pat_off = {v} (should be 0)')


if __name__ == '__main__':
    main()
