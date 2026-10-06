#!/usr/bin/env python3
"""Run one input through the instrumented LTPRO image and print its raw trace.

Use this when changing hook sites in tools/ltpro_trace.py: it runs a single
DOSBox-X session, keeps the working directory, decodes TRACE.BIN and prints
each boundary's stage, tag cache and per-record sub-rule counts. A hook that
jumps into garbage shows up as an `Interrupt Called 6` flood in host.log, which
DOSBox-X grows without bound; the directory is removed on success only.
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import ltpro_trace
from ltpro_capture import CONFIG, ENVIRONMENT, FILES, FLAGS


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('text', nargs='?', default='He is in the house.')
    ap.add_argument('--data', type=Path, default=Path('LTGOLD'))
    ap.add_argument('--keep', type=Path, help='working directory to keep (default: temporary)')
    ap.add_argument('--timeout', type=float, default=60)
    args = ap.parse_args()
    assets = {name: (args.data / name).read_bytes() for name in FILES}
    patched = ltpro_trace.instrument(assets['LTPRO.EXE'])
    root = (args.keep or Path('.ltpro-rawtrace')).resolve()
    if root.exists(): shutil.rmtree(root)
    root.mkdir()
    for name, data in assets.items(): (root / name).write_bytes(data)
    (root / 'LTPRO.EXE').write_bytes(patched)
    (root / 'INPUT.TXT').write_bytes(args.text.encode('cp866') + b'\r\n')
    (root / 'RUN.BAT').write_bytes(('@echo off\r\nLTPRO /I INPUT.TXT /O OUTPUT.TXT ' + ' '.join(FLAGS)
                                    + '\r\necho COMPLETE>DONE.TXT\r\nexit\r\n').encode('ascii'))
    (root / 'dosbox.conf').write_text(CONFIG.format(mount=root))
    try:
        with (root / 'host.log').open('wb') as log:
            subprocess.run(['dosbox-x', '-conf', str(root / 'dosbox.conf'), '-silent', '-nogui'], cwd=root,
                           env=dict(os.environ, **ENVIRONMENT), stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        subprocess.run(['pkill', '-f', 'dosbox-x'])
        faults = sum(1 for line in (root / 'host.log').open('rb') if b'Interrupt Called 6' in line)
        print(f'DOSBox did not finish; {faults} invalid-opcode faults logged; files kept in {root}')
        raise SystemExit(1)
    output = (root / 'OUTPUT.TXT').read_bytes() if (root / 'OUTPUT.TXT').exists() else b''
    print('output:', output.decode('cp866', 'replace').strip())
    raw = (root / 'TRACE.BIN').read_bytes() if (root / 'TRACE.BIN').exists() else b''
    for snapshot in ltpro_trace.decode_trace(raw):
        print(snapshot['stage'], snapshot['cache'], [(n['tag'], len(n['rules'])) for n in snapshot['nodes']])
        if snapshot['stage'] == 'lexical':
            for node in snapshot['nodes']:
                for rule in node['rules']: print('   ', node['source'], repr(rule['pattern']), repr(rule['action']))
    if not args.keep: shutil.rmtree(root)


if __name__ == '__main__': main()
