#!/usr/bin/env python3
"""Capture original LTPRO output for every dictionary-syntax probe.

Each probe in probes.json installs its rows into an isolated copy of the
supplied LTGOLD assets (the same rebuild as tools/ltpro_try_entries.py),
optionally rewrites single BASE.RUS code bytes in place, mounts extra
dictionaries and adds command-line switches. Every probe runs twice; both runs
must be byte-identical. The result replaces reference.json next to this file:

    python3 test/ltpro/dictionary-syntax/capture.py

test/dictionary_syntax_test.lua replays the same probes through the Lua engine.
"""
import datetime
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import ltech_dict as ld  # noqa: E402
import ltpro_capture as lc  # noqa: E402
import ltpro_try_entries as te  # noqa: E402


def edit_russian(path, edits):
    """Apply word:index:hex edits; each replaces one code byte, keeping lengths."""
    rus = ld.load_dictionary(path)
    size = len(rus.body())
    for spec in edits:
        word, index, value = spec.split(':')
        for n, row in enumerate(rus.lines):
            key, code = ld.line_parts(row)
            if key == word.encode('cp866'):
                code = bytearray(code)
                code[int(index)] = int(value, 16)
                rus.lines[n] = key + b'*' + bytes(code)
                break
        else:
            raise SystemExit(f'BASE.RUS has no {word}')
    assert len(rus.body()) == size
    rus.save(path)


def main():
    probes = json.loads((HERE / 'probes.json').read_text(encoding='utf-8'))
    work = Path(tempfile.mkdtemp(prefix='ltpro-syntax-'))
    results = []
    default_flags = list(lc.FLAGS)
    try:
        for probe in probes:
            data = work / probe['id']
            te.build(data, probe.get('entries', []), probe.get('delete', []))
            if probe.get('rus'):
                edit_russian(data / 'BASE.RUS', probe['rus'])
            names = list(lc.FILES) + probe.get('dictionaries', [])
            for name in probe.get('dictionaries', []):
                shutil.copyfile(ROOT / 'LTGOLD' / name, data / name)
            assets = {name: (data / name).read_bytes() for name in names}
            dropped_z = not any(row.startswith(b'z') for row in ld.load_dictionary(data / 'BASE.DIC').lines)
            cases = [{'id': f'{probe["id"]}-{i}', 'input': text} for i, text in enumerate(probe['inputs'])]
            lc.FLAGS = default_flags + probe.get('flags', [])
            runs = [lc.capture_batch('dosbox-x', assets, cases, 300, run) for run in (1, 2)]
            for first, second in zip(*runs):
                if first['raw_sha256'] != second['raw_sha256']:
                    raise SystemExit(f'{probe["id"]}: runs differ')
            results.append({
                'id': probe['id'],
                'command': 'LTPRO.EXE /I C0000.IN /O C0000.OUT ' + ' '.join(lc.FLAGS),
                'dropped_z_headwords': dropped_z,
                'assets': {name: hashlib.sha256(data).hexdigest() for name, data in assets.items()},
                'cases': [dict(input=case['input'], **output) for case, output in zip(cases, runs[0])],
            })
    finally:
        lc.FLAGS = default_flags
        shutil.rmtree(work)
    reference = {
        'captured': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
        'emulator': lc.__name__ + ' via dosbox-x, two byte-identical runs per probe',
        'probes_sha256': hashlib.sha256((HERE / 'probes.json').read_bytes()).hexdigest(),
        'probes': results,
    }
    (HERE / 'reference.json').write_text(json.dumps(reference, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print(f'captured {sum(len(p["cases"]) for p in results)} cases in {len(results)} probes')


if __name__ == '__main__':
    main()
