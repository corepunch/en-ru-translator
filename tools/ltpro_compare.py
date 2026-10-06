#!/usr/bin/env python3
"""Compare Lua with provenance-checked DOSBox-X reference captures; never recapture."""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from ltpro_capture import translation


def digest(data): return hashlib.sha256(data).hexdigest()


def lua_text(value):
    # Byte escapes are valid Lua source and cannot inject instructions from fixture text.
    return '"' + ''.join('\\%03d' % byte for byte in value.encode('utf8')) + '"'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--reference', type=Path, default=Path('test/ltpro/reference.json'))
    ap.add_argument('--cases', type=Path, default=Path('test/ltpro/cases.json'))
    ap.add_argument('--data', type=Path, default=Path('LTGOLD'))
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    reference = json.loads(args.reference.read_text())
    if reference['schema'] != 1 or reference['identical_runs'] < 2: ap.error('unverified capture format')
    for name, expected in reference['assets_sha256'].items():
        if digest((args.data / name).read_bytes()) != expected: ap.error(f'capture asset differs: {name}')
    cases_bytes = args.cases.read_bytes()
    if digest(cases_bytes) != reference['input_cases_sha256']: ap.error('input corpus differs from capture')
    cases = reference['cases']
    inputs = json.loads(cases_bytes)
    if [{k: c[k] for k in ('id', 'group', 'input')} for c in cases] != inputs:
        ap.error('captured inputs differ from corpus')
    for case in cases:
        raw = bytes.fromhex(case['raw_cp866_hex'])
        if digest(raw) != case['raw_sha256'] or translation(raw) != case['translation']:
            ap.error(f'raw capture/translation inconsistency: {case["id"]}')
    with tempfile.TemporaryDirectory(prefix='ltpro-compare-') as directory:
        path = Path(directory) / 'inputs.lua'
        path.write_text('return {' + ','.join('{input=' + lua_text(c['input']) + '}' for c in cases) + '}\n')
        lines = []
        # LTPRO is launched anew per input; give Lua the same process isolation.
        for i in range(1, len(cases) + 1):
            result = subprocess.run(['lua', 'tools/ltpro_corpus.lua', str(path), str(args.data), str(i)], capture_output=True, text=True, timeout=30)
            if result.returncode: raise RuntimeError('Lua corpus runner failed: ' + result.stderr)
            lines.extend(result.stdout.splitlines())
    if len(lines) != len(cases): raise RuntimeError('missing or unexpected Lua corpus output')
    outcomes = []
    for i, (case, line) in enumerate(zip(cases, lines), 1):
        index, status, encoded = line.split('\t')
        if int(index) != i or status not in ('OK', 'ERROR'): raise RuntimeError('invalid Lua result record')
        output = bytes.fromhex(encoded).decode('utf8')
        matched = status == 'OK' and output == case['translation']
        outcomes.append({'id': case['id'], 'group': case['group'], 'input': case['input'],
                         'expected': case['translation'], 'actual': output, 'matched': matched, 'error': status == 'ERROR'})
        if not matched:
            print(f'FAIL {case["id"]} {case["input"]}\n  LTPRO: {case["translation"]}\n  Lua:   {output}')
    passed = sum(row['matched'] for row in outcomes)
    errors = sum(row['error'] for row in outcomes)
    print(f'Fresh LTPRO capture comparison: PASS={passed} FAIL={len(cases)-passed} ERRORS={errors} TOTAL={len(cases)}')
    if args.report:
        report = {'reference_sha256': digest(args.reference.read_bytes()), 'captured_at_utc': reference['captured_at_utc'],
                  'lua_process_per_case': True,
                  'passed': passed, 'failed': len(cases)-passed, 'errors': errors, 'cases': outcomes}
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit(passed != len(cases))

if __name__ == '__main__': main()
