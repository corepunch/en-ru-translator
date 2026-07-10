#!/usr/bin/env python3
"""
sweep_rules.py — Binary-search for essential rules in LTPRO.EXE

For each table (working backward: T8 -> T7 -> T5 -> T4 -> T3 -> T2 -> T1),
binary-search to find the maximum suffix of records that can be cleared
(from the end of the table) without crashing the program.

Also reports when clearing a suffix changes the translation output (diff),
which reveals rules that are active on the test sentence.

DOSBox note: filenames MUST be 8.3 (COMMAND.COM limitation).

Usage:
    python3 sweep_rules.py                      # scan all tables
    python3 sweep_rules.py --table T8            # scan one table
    python3 sweep_rules.py --table T8 --rule 80  # test a single rule
    python3 sweep_rules.py --baseline            # capture baseline only
"""
import struct, sys, os, subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_EXE = os.path.join(SCRIPT_DIR, 'LTPRO.EXE')
SWEEP_EXE = os.path.join(SCRIPT_DIR, 'SW.EXE')
RUN_SCRIPT = os.path.join(SCRIPT_DIR, 'run_test.sh')
LOG_FILE = os.path.join(SCRIPT_DIR, 'sweep_results.log')
TEST_SENTENCE = 'She can speak Russian.'

# === Constants ===
BORLAND_OFFSET = 0x26754
DAT_BASE = BORLAND_OFFSET - 4
SHIFT = 242

LTGOLD_OFFSETS = {
    'T1': 3374, 'T2': 3854, 'T3': 5434, 'T4': 11981,
    'T5': 16610, 'T7': 17972, 'T8': 19158,
}
REC_SIZES = {'T1': 10, 'T2': 10, 'T3': 10, 'T4': 9, 'T5': 10, 'T7': 8, 'T8': 8}
COUNTS = {'T1': 47, 'T2': 157, 'T3': 136, 'T4': 178, 'T5': 9, 'T7': 35, 'T8': 83}
ALL_TABLES = ['T8', 'T7', 'T5', 'T4', 'T3', 'T2', 'T1']

# 0xFF is read by the DOS pattern-matching engine and causes a crash.
# Use 0x00 instead — the pattern becomes empty string, which never
# matches in the engine's pattern-matching loop.
NULL_BYTE = 0x00


def get_exe_start(table):
    return DAT_BASE + (LTGOLD_OFFSETS[table] - SHIFT)


def get_record_strings(data, table, idx):
    """Return (pat_string, act_string, flags_val, flags_sz) for one record."""
    rec = get_exe_start(table) + idx * REC_SIZES[table]

    if table == 'T4':
        po = struct.unpack_from('<H', data, rec + 1)[0]
        ao = struct.unpack_from('<H', data, rec + 5)[0]
        flags_val = data[rec]
        flags_sz = 1
    elif table in ('T7', 'T8'):
        po = struct.unpack_from('<H', data, rec)[0]
        ao = struct.unpack_from('<H', data, rec + 4)[0]
        flags_val = struct.unpack_from('<H', data, rec + 6)[0]
        flags_sz = 2
    else:
        po = struct.unpack_from('<H', data, rec)[0]
        ao = struct.unpack_from('<H', data, rec + 4)[0]
        flags_val = struct.unpack_from('<H', data, rec + 8)[0]
        flags_sz = 2

    def cstr(off):
        if off == 0:
            return ''
        pos = DAT_BASE + off
        buf = []
        while pos < len(data) and data[pos] != 0:
            buf.append(data[pos])
            pos += 1
        return bytes(buf).decode('cp866', errors='replace')

    return cstr(po), cstr(ao), flags_val, flags_sz


def get_record_offsets(data, table, idx):
    """Return (pat_offset, act_offset) for a record (for patching)."""
    rec = get_exe_start(table) + idx * REC_SIZES[table]
    if table == 'T4':
        return struct.unpack_from('<H', data, rec + 1)[0], \
               struct.unpack_from('<H', data, rec + 5)[0]
    else:
        return struct.unpack_from('<H', data, rec)[0], \
               struct.unpack_from('<H', data, rec + 4)[0]


def patch_suffix(data, table, clear_from):
    """
    Patch suffix [clear_from, N-1] of 'table' in-place.
    Sets first byte of each pattern/action string to NULL_BYTE,
    making them empty strings that never match.
    Returns count of strings patched.
    """
    n = COUNTS[table]
    if clear_from >= n:
        return 0

    patched = 0
    for i in range(clear_from, n):
        po, ao = get_record_offsets(data, table, i)
        if po:
            pa = DAT_BASE + po
            if 0 <= pa < len(data):
                data[pa] = NULL_BYTE
                patched += 1
        if ao:
            aa = DAT_BASE + ao
            if 0 <= aa < len(data):
                data[aa] = NULL_BYTE
                patched += 1
    return patched


def write_exe(data):
    with open(SWEEP_EXE, 'wb') as f:
        f.write(data)


def run_test(exe_path):
    """Run run_test.sh with given EXE. Returns (output, is_error)."""
    try:
        r = subprocess.run(
            [RUN_SCRIPT, TEST_SENTENCE, os.path.basename(exe_path)],
            capture_output=True, text=True, timeout=10,
            cwd=SCRIPT_DIR
        )
        out = r.stdout.strip()
        err = r.stderr.strip()
        if r.returncode != 0 or 'ERROR' in err:
            return err, True
        return out, False
    except subprocess.TimeoutExpired:
        return 'TIMEOUT', True
    except Exception as e:
        return str(e), True


def get_baseline(data):
    """Get baseline output from unmodified LTPRO.EXE."""
    write_exe(data)
    out, is_err = run_test(SWEEP_EXE)
    return out if not is_err else 'ERROR'


def binary_search_table(data, table, baseline):
    """
    Binary-search for the minimal clear_from index for 'table'.
    Records [clear_from, N-1] are cleared. Low clear_from = aggressive (clear more).
    Returns (safe_clear_from, test_log).
    safe_clear_from = N (clear_none) means even last record alone crashes.
    safe_clear_from = 0 means all records can be cleared safely.
    """
    n = COUNTS[table]
    log = []

    d = bytearray(data)
    patch_suffix(d, table, 0)
    write_exe(d)
    out0, err0 = run_test(SWEEP_EXE)
    if not err0:
        status = 'SAME' if out0 == baseline else 'DIFF'
        log.append((0, status, out0))
        return 0, log
    tag0 = 'TIMEOUT' if 'TIMEOUT' in out0 else 'CRASH'
    log.append((0, tag0, out0))

    d = bytearray(data)
    patch_suffix(d, table, n - 1)
    write_exe(d)
    outN, errN = run_test(SWEEP_EXE)
    if errN:
        tagN = 'TIMEOUT' if 'TIMEOUT' in outN else 'CRASH'
        log.append((n - 1, tagN, outN))
        return n, log

    statusN = 'SAME' if outN == baseline else 'DIFF'
    log.append((n - 1, statusN, outN))

    low = 0       # known err (too aggressive)
    high = n - 1  # known ok

    while low + 1 < high:
        mid = (low + high) // 2
        d = bytearray(data)
        patch_suffix(d, table, mid)
        write_exe(d)
        out, is_err = run_test(SWEEP_EXE)
        if is_err:
            tag = 'TIMEOUT' if 'TIMEOUT' in out else 'CRASH'
            log.append((mid, tag, out))
            low = mid  # too aggressive, need to keep more
        else:
            status = 'SAME' if out == baseline else 'DIFF'
            log.append((mid, status, out))
            high = mid  # safe, try clearing more

    return high, log


def log_result(msg):
    print(msg)
    with open(LOG_FILE, 'a') as f:
        f.write(msg + '\n')


def main():
    if not os.path.exists(BASE_EXE):
        print(f'Error: {BASE_EXE} not found')
        sys.exit(1)

    args = sys.argv[1:]
    target_table = None
    if '--table' in args:
        idx = args.index('--table')
        target_table = args[idx + 1]

    target_rule = None
    if '--rule' in args:
        idx = args.index('--rule')
        target_rule = int(args[idx + 1])

    only_baseline = '--baseline' in args

    with open(BASE_EXE, 'rb') as f:
        base_data = f.read()

    if only_baseline:
        b = get_baseline(base_data)
        print(f'Baseline: "{b}"')
        return

    # Single-rule test
    if target_table and target_rule is not None:
        pat, act, fv, fs = get_record_strings(base_data, target_table, target_rule)
        print(f'{target_table}[{target_rule}]:')
        print(f'  Pattern: {pat}')
        print(f'  Action:  {act}')
        print(f'  Flags:   0x{fv:0{fs*2}X}')
        d = bytearray(base_data)
        patch_suffix(d, target_table, target_rule)
        if target_rule + 1 < COUNTS[target_table]:
            patch_suffix(d, target_table, target_rule + 1)
        write_exe(d)
        out, is_err = run_test(SWEEP_EXE)
        if is_err:
            print(f'  Result:  CRASH — {out}')
        else:
            bl = get_baseline(base_data)
            st = 'SAME' if out == bl else 'DIFF'
            print(f'  Result:  {st} — "{out}"')
        return

    # Baseline
    print('Capturing baseline...', end=' ', flush=True)
    baseline = get_baseline(base_data)
    print(f'"{baseline}"')

    tables = [target_table] if target_table else ALL_TABLES

    with open(LOG_FILE, 'w') as f:
        f.write(f'Baseline: "{baseline}"\n')
        f.write(f'Test sentence: "{TEST_SENTENCE}"\n\n')

    print(f'\nLogging to {LOG_FILE}\n')

    for table in tables:
        n = COUNTS[table]
        log_result(f'=== {table} ({n} records) ===')

        safe_s, test_log = binary_search_table(base_data, table, baseline)

        # Summarise test points
        for cf, status, output in test_log:
            if status == 'CRASH':
                log_result(f'  [{cf:3d}..{n-1:3d}] ({n-cf:3d} rec) -> {status}: {output}')
            else:
                log_result(f'  [{cf:3d}..{n-1:3d}] ({n-cf:3d} rec) -> {status}')

        # Interpret result
        if safe_s >= n:
            log_result(f'  -> NOTHING can be cleared — even last record [{n-1}] crashes')
            # Show last record info
            pat, act, fv, fs = get_record_strings(base_data, table, n - 1)
            log_result(f'  -> Last record [{n-1}]: flags=0x{fv:0{fs*2}X}  pat={pat!r}  act={act!r}')
        elif safe_s == 0:
            log_result(f'  -> SAFE to clear ALL {n} records')
        else:
            safe_count = n - safe_s
            log_result(f'  -> SAFE to clear [{safe_s}..{n-1}] ({safe_count} records from end)')
            log_result(f'  -> Record [{safe_s-1}] is the boundary (clearing it crashes)')
            pat, act, fv, fs = get_record_strings(base_data, table, safe_s - 1)
            log_result(f'     Boundary {table}[{safe_s-1}]: flags=0x{fv:0{fs*2}X}  pat={pat!r}  act={act!r}')
            if safe_s - 2 >= 0:
                pat2, act2, fv2, fs2 = get_record_strings(base_data, table, safe_s - 2)
                log_result(f'     Preceding {table}[{safe_s-2}]: flags=0x{fv2:0{fs2*2}X}  pat={pat2!r}  act={act2!r}')

        # Rules that fired on the test sentence
        diffs = [(cf, out) for cf, s, out in test_log if s == 'DIFF']
        if diffs:
            log_result(f'  -> {len(diffs)} suffix(es) changed output (rules fired on test sentence):')
            for cf, out in sorted(diffs, key=lambda x: x[0]):
                log_result(f'      clear_from={cf}: "{out}"')

        log_result('')

    if os.path.exists(SWEEP_EXE):
        os.remove(SWEEP_EXE)
    print(f'\nDone. Log in {LOG_FILE}')


if __name__ == '__main__':
    main()
