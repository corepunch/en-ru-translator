#!/usr/bin/env python3
"""Audit the snapshot-free Lua pipeline against verified LTPRO references."""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

from ltpro_capture import translation


def digest(data):
    return hashlib.sha256(data).hexdigest()


def lua_text(value):
    """Encode text as decimal byte escapes, so fixture data is never Lua code."""
    return '"' + ''.join('\\%03d' % byte for byte in value.encode('utf-8')) + '"'


def validate(reference_path, cases_path, data_dir):
    errors = []
    reference_bytes = reference_path.read_bytes()
    reference = json.loads(reference_bytes)
    if reference.get('schema') != 1 or reference.get('identical_runs', 0) < 2:
        errors.append('unverified reference capture format')

    for name, expected in reference.get('assets_sha256', {}).items():
        path = data_dir / name
        if not path.is_file():
            errors.append(f'missing capture asset: {name}')
        elif digest(path.read_bytes()) != expected:
            errors.append(f'capture asset differs: {name}')

    cases_bytes = cases_path.read_bytes()
    if digest(cases_bytes) != reference.get('input_cases_sha256'):
        errors.append('input corpus differs from capture')
    inputs = json.loads(cases_bytes)
    cases = reference.get('cases', [])
    if [{k: case.get(k) for k in ('id', 'group', 'input')} for case in cases] != inputs:
        errors.append('captured inputs differ from corpus')

    for case in cases:
        try:
            raw = bytes.fromhex(case['raw_cp866_hex'])
        except (KeyError, ValueError) as exc:
            errors.append(f'invalid raw capture for {case.get("id", "?")}: {exc}')
            continue
        if digest(raw) != case.get('raw_sha256') or translation(raw) != case.get('translation'):
            errors.append(f'raw capture/translation inconsistency: {case.get("id", "?")}')

    return reference, cases, errors, digest(reference_bytes), digest(cases_bytes)


def lua_fixture(cases, data_dir):
    inputs = ','.join(lua_text(case['input']) for case in cases)
    return '''
package.path = './?.lua;./?/init.lua;' .. package.path
local pipeline = require 'core.ltpro.pipeline'
local encoding = require 'core.encoding'
local inputs = {''' + inputs + '''}
local options = {data_dir=''' + lua_text(str(data_dir)) + '''}
local function hex(value)
  return (value:gsub('.', function(c) return string.format('%02x', c:byte()) end))
end
for i, input in ipairs(inputs) do
  local ok, result = pcall(pipeline.translate, input, options)
  if ok then io.write(i, '\\tOK\\t', hex(encoding.encode(result)), '\\n')
  else io.write(i, '\\tERROR\\t', hex(encoding.encode(tostring(result))), '\\n') end
  collectgarbage('collect')
end
'''


def run_lua(cases, data_dir, lua_executable):
    with tempfile.TemporaryDirectory(prefix='ltpro-pipeline-probe-') as directory:
        fixture = Path(directory) / 'audit.lua'
        fixture.write_text(lua_fixture(cases, data_dir), encoding='utf-8')
        result = subprocess.run([lua_executable, str(fixture)], capture_output=True,
                                cwd=Path.cwd(), timeout=300)
    if result.returncode:
        stderr = result.stderr.decode('utf-8', errors='replace')
        raise RuntimeError(f'Lua pipeline fixture exited {result.returncode}: {stderr.strip()}')

    rows = []
    for line in result.stdout.decode('ascii').splitlines():
        parts = line.split('\t')
        if len(parts) != 3 or parts[1] not in ('OK', 'ERROR'):
            raise RuntimeError('invalid Lua result record: ' + repr(line))
        try:
            index = int(parts[0])
            value = bytes.fromhex(parts[2]).decode('cp866')
        except (ValueError, UnicodeDecodeError) as exc:
            raise RuntimeError(f'invalid Lua result payload: {line!r}: {exc}') from exc
        rows.append((index, parts[1], value))
    if len(rows) != len(cases):
        raise RuntimeError(f'expected {len(cases)} Lua records, received {len(rows)}')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, default=Path('test/ltpro/reference.json'))
    parser.add_argument('--cases', type=Path, default=Path('test/ltpro/cases.json'))
    parser.add_argument('--data', type=Path, default=Path('LTGOLD'))
    parser.add_argument('--lua', default='lua')
    parser.add_argument('--report', type=Path, help='write a JSON provenance and result report')
    args = parser.parse_args()

    try:
        reference, cases, provenance_errors, reference_hash, cases_hash = validate(
            args.reference, args.cases, args.data)
    except (OSError, json.JSONDecodeError) as exc:
        provenance_errors = [str(exc)]
        reference, cases, reference_hash, cases_hash = {}, [], None, None

    report = {
        'reference_sha256': reference_hash,
        'input_cases_sha256': cases_hash,
        'captured_at_utc': reference.get('captured_at_utc'),
        'snapshot_initialization': False,
        'assets_verified': not provenance_errors,
        'provenance_errors': provenance_errors,
        'total': len(cases),
        'passed': 0,
        'failed': 0,
        'errors': 0,
        'cases': [],
    }

    if provenance_errors:
        print('LTPRO snapshot-free pipeline audit: INVALID PROVENANCE')
    else:
        try:
            results = run_lua(cases, args.data.resolve(), args.lua)
            for expected_index, (case, (index, status, actual)) in enumerate(zip(cases, results), 1):
                if index != expected_index:
                    raise RuntimeError(f'Lua record order mismatch at {expected_index}: got {index}')
                matched = status == 'OK' and actual == case['translation']
                row = {
                    'id': case['id'], 'group': case['group'], 'input': case['input'],
                    'oracle_raw_cp866_sha256': case['raw_sha256'],
                    'actual_cp866_hex': actual.encode('cp866').hex(),
                    'actual_cp866_sha256': digest(actual.encode('cp866')),
                    'expected': case['translation'], 'actual': actual,
                    'status': status, 'matched': matched,
                }
                report['cases'].append(row)
                if matched:
                    report['passed'] += 1
                else:
                    report['failed'] += 1
                    if status == 'ERROR':
                        report['errors'] += 1
                    print(f'FAIL {case["id"]} {case["input"]}\n  LTPRO: {case["translation"]}\n  Lua:   {actual}')
        except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
            report['errors'] += 1
            report['execution_error'] = str(exc)

        print('LTPRO snapshot-free pipeline audit: '
              f'PASS={report["passed"]} FAIL={report["failed"]} '
              f'ERRORS={report["errors"]} TOTAL={report["total"]}')

    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    raise SystemExit(bool(provenance_errors or report['failed'] or report['errors']))


if __name__ == '__main__':
    main()
