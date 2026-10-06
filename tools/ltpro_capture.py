#!/usr/bin/env python3
"""Capture repeatable full-program LTPRO references in isolated DOSBox-X mounts."""
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

FILES = ('LTPRO.EXE', 'BASE.DIC', 'BASE.RUS', 'ERPREFIX.PRE', 'LTGOLD.CNF', 'LTPRO.CMD')
FLAGS = ['/F-', '/B-', '/N']
CONFIG = '''[sdl]
output=surface
[cpu]
core=normal
cycles=fixed 30000
[midi]
mididevice=none
[sblaster]
sbtype=none
[gus]
gus=false
[speaker]
pcspeaker=false
[joystick]
joysticktype=none
[autoexec]
mount c "{mount}"
c:
RUN.BAT
'''
ENVIRONMENT = {'SDL_VIDEODRIVER': 'dummy', 'SDL_AUDIODRIVER': 'dummy'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def translation(raw):
    # Preserve raw bytes separately. The text comparison drops only CRLF framing
    # and the separately delimited meanings appendix, never case or punctuation.
    text = raw.decode('cp866').replace('\r\n', '\n').strip('\n')
    return text.split('\n\n', 1)[0]


def capture_batch(executable, assets, cases, timeout, run_number):
    root = Path(tempfile.mkdtemp(prefix='ltpro-capture-'))
    try:
        for name, data in assets.items(): (root / name).write_bytes(data)
        commands = ['@echo off']
        for index, case in enumerate(cases):
            stem = f'C{index:04d}'
            (root / (stem + '.IN')).write_bytes(case['input'].encode('cp866') + b'\r\n')
            commands.append(f'LTPRO.EXE /I {stem}.IN /O {stem}.OUT ' + ' '.join(FLAGS))
        commands.extend(['echo COMPLETE>DONE.TXT', 'exit'])
        (root / 'RUN.BAT').write_bytes(('\r\n'.join(commands) + '\r\n').encode('ascii'))
        (root / 'dosbox.conf').write_text(CONFIG.format(mount=root))
        with (root / 'host.log').open('wb') as log:
            result = subprocess.run([executable, '-conf', str(root / 'dosbox.conf'), '-silent', '-nogui'],
                cwd=root, env=dict(os.environ, **ENVIRONMENT), stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode or not (root / 'DONE.TXT').exists():
            raise RuntimeError(f'DOSBox-X did not finish: exit={result.returncode}')
        outputs = []
        for index, case in enumerate(cases):
            path = root / f'C{index:04d}.OUT'
            if not path.exists() or not path.stat().st_size:
                raise RuntimeError(f'No output for {case["id"]}: {case["input"]}')
            raw = path.read_bytes()
            outputs.append({'raw_cp866_hex': raw.hex(), 'raw_sha256': digest(raw), 'translation': translation(raw)})
        # Detect config or dictionary changes made by the executable itself.
        changed = [name for name, data in assets.items() if (root / name).read_bytes() != data]
        if changed: raise RuntimeError('LTPRO modified capture assets: ' + ', '.join(changed))
        print(f'Run {run_number}: captured {len(cases)} cases ({cases[0]["id"]}–{cases[-1]["id"]})', flush=True)
    except Exception:
        print(f'Capture failed; diagnostic files retained at {root}', flush=True)
        raise
    shutil.rmtree(root)
    return outputs


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--data', type=Path, default=Path('LTGOLD'))
    ap.add_argument('--cases', type=Path, default=Path('test/ltpro/cases.json'))
    ap.add_argument('--output', type=Path, default=Path('test/ltpro/reference.json'))
    ap.add_argument('--dosbox', default='dosbox-x')
    ap.add_argument('--repeat', type=int, default=2)
    ap.add_argument('--batch-size', type=int, default=16)
    ap.add_argument('--timeout', type=float, default=120)
    args = ap.parse_args()
    if args.repeat < 2: ap.error('--repeat must be at least 2 to check reproducibility')
    if not 1 <= args.batch_size <= 1000: ap.error('--batch-size must be 1..1000')
    executable = shutil.which(args.dosbox)
    if not executable: ap.error('DOSBox-X not found; install with brew install dosbox-x')
    cases_bytes = args.cases.read_bytes()
    cases = json.loads(cases_bytes)
    if not cases or len({c['id'] for c in cases}) != len(cases): ap.error('empty corpus or duplicate IDs')
    for case in cases:
        if not re.fullmatch(r'[a-z0-9-]+', case['id']): ap.error('invalid case ID')
        case['input'].encode('cp866')
    assets = {name: (args.data / name).read_bytes() for name in FILES}
    version = subprocess.run([executable, '-version'], capture_output=True, text=True, timeout=10)
    version_line = next(line.strip() for line in (version.stdout + version.stderr).splitlines() if 'DOSBox-X version' in line)
    all_runs = []
    for run in range(1, args.repeat + 1):
        output = []
        for start in range(0, len(cases), args.batch_size):
            output.extend(capture_batch(executable, assets, cases[start:start + args.batch_size], args.timeout, run))
        all_runs.append(output)
    for run in all_runs[1:]:
        if run != all_runs[0]:
            unstable = [cases[i]['id'] for i, (a, b) in enumerate(zip(all_runs[0], run)) if a != b]
            raise RuntimeError('Non-reproducible outputs; reference was not updated: ' + ', '.join(unstable))
    manifest = {
        'schema': 1, 'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'profile': 'supplied-unpacked-LTPRO-original-BASE',
        'dosbox_version': version_line, 'dosbox_binary_sha256': digest(Path(executable).read_bytes()),
        'assets_sha256': {name: digest(data) for name, data in assets.items()},
        'input_cases_sha256': digest(cases_bytes), 'command': ['LTPRO.EXE', '/I', '{input}', '/O', '{output}', *FLAGS],
        'dosbox_config_template': CONFIG, 'environment': ENVIRONMENT,
        'batch_size': args.batch_size, 'identical_runs': args.repeat,
        'comparison': 'Exact CP866-decoded translation paragraph; only CRLF/newline framing and the separate meanings appendix excluded. Raw output is retained.',
        'cases': [dict(case, **out) for case, out in zip(cases, all_runs[0])],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + '.tmp')
    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(args.output)
    print(f'Saved {len(cases)} fresh references, identical across {args.repeat} runs: {args.output}')

if __name__ == '__main__': main()
