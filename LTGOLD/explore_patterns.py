#!/usr/bin/env python3
"""
explore_patterns.py — Surgical pattern replacement experiments on LTPRO.EXE

For each target rule in T8, replace its pattern string with simplified
variants, run the test sentence, and compare output. This reveals what
each symbol contributes to the match.

Usage:
    python3 explore_patterns.py                       # run all experiments
    python3 explore_patterns.py --rule T8[13]          # one rule only
    python3 explore_patterns.py --list                 # list planned experiments
"""
import struct, sys, os, subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_EXE = os.path.join(SCRIPT_DIR, 'LTPRO.EXE')
EXP_EXE = os.path.join(SCRIPT_DIR, 'EXP.EXE')
RUN_SCRIPT = os.path.join(SCRIPT_DIR, 'run_test.sh')
TEST_SENTENCE = 'She can speak Russian.'
LOG_FILE = os.path.join(SCRIPT_DIR, 'pattern_explore.log')

DAT_BASE = 0x26750
SHIFT = 242
T8_OFF = 19158

REC_SIZES = {'T1':10,'T2':10,'T3':10,'T4':9,'T5':10,'T7':8,'T8':8}
COUNTS = {'T1':47,'T2':157,'T3':136,'T4':178,'T5':9,'T7':35,'T8':83}

def get_pat_addr(data, table, idx):
    """Return (pat_addr, pat_bytes) for a record."""
    start = DAT_BASE + (LTGOLD_OFFSET(table) - SHIFT)
    rec = start + idx * REC_SIZES[table]
    if table == 'T4':
        po = struct.unpack_from('<H', data, rec + 1)[0]
    else:
        po = struct.unpack_from('<H', data, rec)[0]
    addr = DAT_BASE + po
    # Read until null
    end = addr
    while end < len(data) and data[end] != 0:
        end += 1
    return addr, data[addr:end]


def LTGOLD_OFFSET(table):
    return {'T1':3374,'T2':3854,'T3':5434,'T4':11981,'T5':16610,'T7':17972,'T8':19158}[table]


def replace_pattern(data, table, idx, new_pat_bytes):
    """
    Replace the pattern string of record `idx` in `table`.
    `new_pat_bytes` must be <= original pattern length.
    Pads the rest with null bytes.
    """
    addr, orig = get_pat_addr(data, table, idx)
    if len(new_pat_bytes) > len(orig):
        raise ValueError(f'New pattern ({len(new_pat_bytes)}b) longer than original ({len(orig)}b): {new_pat_bytes!r} > {orig!r}')
    for i, b in enumerate(new_pat_bytes):
        data[addr + i] = b
    for i in range(len(new_pat_bytes), len(orig) + 1):
        data[addr + i] = 0


def get_baseline(data):
    with open(EXP_EXE, 'wb') as f:
        f.write(data)
    r = subprocess.run(
        [RUN_SCRIPT, TEST_SENTENCE, 'EXP.EXE'],
        capture_output=True, text=True, timeout=10, cwd=SCRIPT_DIR
    )
    return r.stdout.strip()


def run_test(data):
    with open(EXP_EXE, 'wb') as f:
        f.write(data)
    r = subprocess.run(
        [RUN_SCRIPT, TEST_SENTENCE, 'EXP.EXE'],
        capture_output=True, text=True, timeout=10, cwd=SCRIPT_DIR
    )
    out = r.stdout.strip()
    err = r.stderr.strip()
    if r.returncode != 0 or 'ERROR' in err:
        return None, err
    return out, None


def log(msg):
    print(msg)
    with open(LOG_FILE, 'a') as f:
        f.write(msg + '\n')


# === Experimental designs for each rule ===

EXPERIMENTS = {
    'T8[13]': {  # Original: ~[bB]?[UVXY]
        'desc': 'Negation, unknown, verb-aux class',
        'variants': [
            (b'?[UVXY]',            'remove ~[bB]: match expr+unknown+verb regardless of b/B'),
            (b'~[bB][UVXY]',        'remove ?: match only ~[bB] then verb (no unknown)'),
            (b'[bB]?[UVXY]',        'remove ~: match b/B+unknown+verb (no negation)'),
            (b'~?[UVXY]',           'remove [bB]: negate-then-unknown+verb (master switch)'),
            (b'~[bB]?',             'remove [UVXY]: match ~[bB]? anywhere (no verb guard)'),
            (b'~[bB]?V',            'remove [UXY]: verb-specific only'),
            (b'~[bB]?U',            'remove [VXY]: modal-specific only'),
            (b'[VXY]',              'replace with single char class: what does this match?'),
        ],
    },
    'T8[12]': {  # Original: L[RN]<$>p*
        'desc': 'Relative pronoun, capture group, preposition, end-boundary',
        'variants': [
            (b'L[RN]p*',            'remove <$>: no token-capture, just direct match'),
            (b'L[RN]<N>p*',         'replace $ with N: capture only nouns'),
            (b'L[RN]p',             'remove <$> and *: no capture, no end-boundary'),
            (b'L[RN]*',             'remove <$>p: no preposition, just relative+pronoun at end'),
            (b'Lp*',                'remove [RN]: relative directly to preposition at end'),
            (b'L[RN]<$>',           'remove p*: no preposition, no end-boundary'),
        ],
    },
    'T8[11]': {  # Original: [UV][kNR][VXY]
        'desc': 'Modal/verb, neg-no/noun/pronoun, verb-aux class',
        'variants': [
            (b'[UV][NR][VXY]',      'remove k: N/R only, no neg-no'),
            (b'[UV]k[VXY]',         'remove [NR]: only k between modal and verb'),
            (b'[UV][kNR]',          'remove [VXY]: no verb guard at end'),
            (b'V[kNR][VXY]',        'change first class to V only'),
            (b'U[kNR][VXY]',        'change first class to U only'),
            (b'[UV]N[VXY]',         'middle class = N only'),
            (b'[UV]R[VXY]',         'middle class = R only'),
            (b'k[VXY]',             'just k+verb: what does standalone k match?'),
        ],
    },
    'T8[10]': {  # Original: [VXY]N[N#][UVXY]
        'desc': 'Verb-aux, noun, noun/unknown, modal/verb/aux',
        'variants': [
            (b'VN[N#][UVXY]',       'first class = V only'),
            (b'XN[N#][UVXY]',       'first class = X only'),
            (b'YN[N#][UVXY]',       'first class = Y only'),
            (b'[VXY]N[N#]',         'remove [UVXY] guard at end'),
            (b'[VXY]N[UVXY]',       'middle class = N only (no #)'),
            (b'[VXY]N#',            'just verb+noun+unknown'),
        ],
    },
}


def main():
    with open(BASE_EXE, 'rb') as f:
        base_data = f.read()

    # Capture baseline
    print('Capturing baseline...', end=' ', flush=True)
    baseline = get_baseline(base_data)
    print(f'"{baseline}"')

    with open(LOG_FILE, 'w') as f:
        f.write(f'Baseline: "{baseline}"\n')
        f.write(f'Test: "{TEST_SENTENCE}"\n\n')

    # Filter experiments if --rule specified
    targets = [a for a in sys.argv[1:] if a.startswith('T8[')]
    if not targets:
        targets = list(EXPERIMENTS.keys())

    if '--list' in sys.argv:
        for rule, exp in EXPERIMENTS.items():
            print(f'\n{rule}: {exp["desc"]}')
            for pat, desc in exp['variants']:
                print(f'  {pat.decode("cp866","replace"):20s}  {desc}')
        return

    for rule_key in targets:
        if rule_key not in EXPERIMENTS:
            print(f'Unknown rule: {rule_key}')
            continue

        # Parse "T8[13]" -> table="T8", idx=13
        tbl, idx_str = rule_key.replace(']', '').split('[')
        idx = int(idx_str)

        exp = EXPERIMENTS[rule_key]
        log(f'\n=== {rule_key}: {exp["desc"]} ===')
        log(f'Original: {get_pat_addr(base_data, tbl, idx)[1].decode("cp866","replace")!r}')

        for new_pat, desc in exp['variants']:
            d = bytearray(base_data)
            replace_pattern(d, tbl, idx, new_pat)
            out, err = run_test(d)
            if out is None:
                log(f'  PATCH {new_pat.decode("cp866","replace"):15s}  -> CRASH ({err})  # {desc}')
            elif out == baseline:
                log(f'  PATCH {new_pat.decode("cp866","replace"):15s}  -> SAME  # {desc}')
            else:
                log(f'  PATCH {new_pat.decode("cp866","replace"):15s}  -> DIFF: "{out}"  # {desc}')

    # Cleanup
    if os.path.exists(EXP_EXE):
        os.remove(EXP_EXE)
    print(f'\nDone. Log in {LOG_FILE}')


if __name__ == '__main__':
    main()
