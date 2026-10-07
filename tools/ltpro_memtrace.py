#!/usr/bin/env python3
"""Capture full conventional-memory snapshots at the post-reorder driver boundaries.

The sentence driver 0687:05D5 calls, in a straight line, the grammar caller
(T1-T4 and reorder), 151F:2740, 1C3D:1B3F, T8 1986:000E and 17AA:1D31 before
its output call. Each hook below sits on the argument pushes that precede one
of those calls (or, for `generation`, on the output preparation after the
last). Output and meanings hooks capture the two output buffers before cleanup.
Every hook writes
the whole first 640 KiB of memory plus the driver's BP, SP, SS and DS to
TRACE.BIN. The 8086 harness can then run the native stage from exactly the
state DOS had, including heap records, globals, open-file state and the
relocated code, and compare its result with the next snapshot.

Snapshots are large, so they are stored zlib-compressed in a cache directory
outside version control. Like ltpro_trace.py, a capture is accepted only when
the instrumented program's output equals the unmodified oracle bytes.
"""
import argparse
import json
import os
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

from ltpro_capture import CONFIG, ENVIRONMENT, FILES, FLAGS, digest
from ltpro_trace import EXE_SHA256, HOOK_SEGMENT, Code

MEMORY = 0xA0000
SITES = [
    # (stage id, name, file offset, displaced bytes): the name is the stage whose
    # result the snapshot holds. `reorder` is taken before 151F:2740.
    (1, 'reorder', 0xA8E4, bytes.fromhex('ff760cff760a')),
    (2, 'numeric', 0xA8F1, bytes.fromhex('56ff760cff760a')),
    (3, 'constituent', 0xA900, bytes.fromhex('56ff760cff760a')),
    (4, 'T8', 0xA90F, bytes.fromhex('56ff760cff760a')),
    # Also the target of the driver's skip when lexical analysis produced nothing.
    (5, 'generation', 0xA91E, bytes.fromhex('c41e8cc526c60700')),
    (6, 'output', 0xA93C, bytes.fromhex('8946fe833eb6bb00')),
    (7, 'meanings', 0xA970, bytes.fromhex('ff760cff760a')),
]
HEADER = struct.Struct('<4s6H')


def instrument(original):
    if digest(original) != EXE_SHA256: raise ValueError('unsupported executable identity')
    header = struct.unpack_from('<H', original, 8)[0] * 16
    count, table = struct.unpack_from('<H', original, 6)[0], struct.unpack_from('<H', original, 24)[0]
    shift = -(-(table + (count + len(SITES)) * 4 - header) // 16) * 16
    image = bytearray(original[:header] + bytes(shift) + original[header:])
    struct.pack_into('<H', image, 8, (header + shift) // 16)
    header += shift
    code = Code()
    entries = []
    for stage, name, site, displaced in SITES:
        if original[site:site + len(displaced)] != displaced: raise ValueError(f'changed hook site {name}')
        entries.append(len(code.data))
        # Pop the far return address first, so that the recorded SP is the
        # driver's own and the displaced argument pushes land where the caller
        # expects them; the return address is pushed back before RETF.
        code.emit('2e8f06'); code.address('return_ip')
        code.emit('2e8f06'); code.address('return_cs')
        code.emit('9c 50 53 51 52 56 57 55 1e 06')
        code.emit('b8'); code.word(stage)
        code.near('e8', 'dump')
        code.emit('07 1f 5d 5f 5e 5a 59 5b 58 9d')
        code.data.extend(displaced)
        code.emit('2eff36'); code.address('return_cs')
        code.emit('2eff36'); code.address('return_ip')
        code.emit('cb')
    code.label('dump')
    # AX=stage. Record the driver frame: BP is unchanged; the driver's SP is
    # the current SP plus the near return (2) and the saved flags/registers (20).
    code.emit('2ea3'); code.address('stage')
    code.emit('2e892e'); code.address('bp')
    code.emit('8bc4 051600 2ea3'); code.address('sp')
    code.emit('2e8c16'); code.address('ss')
    code.emit('2e8c1e'); code.address('ds')
    code.emit('0e 1f ba'); code.address('filename')
    code.emit('b8023d cd21 7309 31c9 b43c cd21')
    code.near('e9', 'opened')
    code.label('opened')
    code.emit('7303'); code.near('e9', 'error')
    code.emit('8bf8 8bd8 31c9 31d2 b80242 cd21')
    code.emit('7303'); code.near('e9', 'error')
    code.emit('ba'); code.address('header'); code.emit(f'b9{HEADER.size:02x}00')
    code.near('e8', 'write')
    # 640 KiB in 20 chunks of 8000h bytes; DS advances by 800h paragraphs.
    code.emit('31c0')
    code.label('chunk')
    code.emit('50 8ed8 31d2 b90080')
    code.near('e8', 'write')
    code.emit('58 050008 3d00a0')
    code.near('0f82', 'chunk')
    code.emit('8bdf b43e cd21 7303'); code.near('e9', 'error')
    code.emit('c3')
    code.label('write')
    code.emit('8bdf b440 cd21 7303'); code.near('e9', 'error')
    code.emit('3bc1 7403'); code.near('e9', 'error')
    code.emit('c3')
    code.label('error'); code.emit('b8434c cd21')
    code.label('filename'); code.data.extend(b'MEMORY.BIN\0')
    code.label('header'); code.data.extend(b'LTMS')
    for name in ('stage', 'bp', 'sp', 'ss', 'ds', 'reserved'):
        code.label(name); code.word(0)
    code.label('return_ip'); code.word(0)
    code.label('return_cs'); code.word(0)
    payload = code.finish()
    image.extend(b'\0' * (header + HOOK_SEGMENT * 16 - len(image)))
    image.extend(payload)
    struct.pack_into('<H', image, 14, HOOK_SEGMENT + (len(payload) + 15) // 16)
    relocated = []
    for (_, _, site, displaced), entry in zip(SITES, entries):
        site += shift
        image[site:site + len(displaced)] = b'\x9a' + struct.pack('<HH', entry, HOOK_SEGMENT) + b'\x90' * (len(displaced) - 5)
        relocated.append(site + 3 - header)
    for index, relocation in enumerate(relocated):
        struct.pack_into('<HH', image, table + (count + index) * 4, relocation % 16, relocation // 16)
    struct.pack_into('<H', image, 6, count + len(relocated))
    struct.pack_into('<HH', image, 2, len(image) % 512, (len(image) + 511) // 512)
    return bytes(image)


def decode(raw):
    """Split a MEMORY.BIN into (header dict, memory bytes) snapshots."""
    snapshots, pos = [], 0
    while pos < len(raw):
        magic, stage, bp, sp, ss, ds, _ = HEADER.unpack_from(raw, pos)
        if magic != b'LTMS' or not 1 <= stage <= len(SITES): raise ValueError(f'invalid snapshot at {pos}')
        pos += HEADER.size
        memory = raw[pos:pos + MEMORY]; pos += MEMORY
        if len(memory) != MEMORY: raise ValueError('truncated snapshot')
        snapshots.append({'stage': SITES[stage - 1][1], 'bp': bp, 'sp': sp, 'ss': ss, 'ds': ds, 'memory': memory})
    return snapshots


def load(cache, case_id):
    """Return the snapshots of one captured case from the cache directory."""
    return decode(zlib.decompress((cache / f'{case_id}.bin.z').read_bytes()))


def run(patched, assets, text, timeout):
    root = Path(tempfile.mkdtemp(prefix='ltpro-memtrace-'))
    try:
        for name, data in assets.items(): (root / name).write_bytes(data)
        (root / 'LTPRO.EXE').write_bytes(patched)
        (root / 'INPUT.TXT').write_bytes(text.encode('cp866') + b'\r\n')
        (root / 'RUN.BAT').write_bytes(('@echo off\r\nLTPRO /I INPUT.TXT /O OUTPUT.TXT ' + ' '.join(FLAGS) +
                                        '\r\necho COMPLETE>DONE.TXT\r\nexit\r\n').encode('ascii'))
        (root / 'dosbox.conf').write_text(CONFIG.format(mount=root))
        with (root / 'host.log').open('wb') as log:
            process = subprocess.run(['dosbox-x', '-conf', str(root / 'dosbox.conf'), '-silent', '-nogui'],
                cwd=root, env=dict(os.environ, **ENVIRONMENT), stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        if process.returncode or not (root / 'DONE.TXT').exists(): raise RuntimeError(f'DOSBox did not complete; kept {root}')
        output = (root / 'OUTPUT.TXT').read_bytes() if (root / 'OUTPUT.TXT').exists() else b''
        for name, data in assets.items():
            if name != 'LTPRO.EXE' and (root / name).read_bytes() != data: raise RuntimeError(f'trace mutated {name}')
        raw = (root / 'MEMORY.BIN').read_bytes() if (root / 'MEMORY.BIN').exists() else b''
    except Exception:
        print(f'Memory trace failed; diagnostics retained at {root}', flush=True); raise
    shutil.rmtree(root)
    return output, raw


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--reference', type=Path, default=Path('test/ltpro/reference.json'))
    ap.add_argument('--data', type=Path, default=Path('LTGOLD'))
    ap.add_argument('--cache', type=Path, default=Path('.cache/ltpro-memtrace'))
    ap.add_argument('--ids', nargs='*', help='case IDs (default: all)')
    ap.add_argument('--text', help='trace one ad hoc input instead (stored as adhoc.bin.z, no oracle check)')
    ap.add_argument('--timeout', type=float, default=60)
    args = ap.parse_args()
    reference = json.loads(args.reference.read_text())
    assets = {name: (args.data / name).read_bytes() for name in FILES}
    for name, data in assets.items():
        if digest(data) != reference['assets_sha256'][name]: ap.error(f'changed reference asset {name}')
    patched = instrument(assets['LTPRO.EXE'])
    args.cache.mkdir(parents=True, exist_ok=True)
    if args.text is not None:
        output, raw = run(patched, assets, args.text, args.timeout)
        (args.cache / 'adhoc.bin.z').write_bytes(zlib.compress(raw, 6))
        print(output.decode('cp866'), [s['stage'] for s in decode(raw)])
        return
    cases = [c for c in reference['cases'] if not args.ids or c['id'] in args.ids]
    manifest_path = args.cache / 'manifest.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    provenance = {'reference_sha256': digest(args.reference.read_bytes()), 'executable_sha256': EXE_SHA256,
                  'instrumented_sha256': digest(patched), 'memory_bytes': MEMORY,
                  'hooks': [{'stage': n, 'file_offset': s, 'displaced_hex': d.hex()} for _, n, s, d in SITES]}
    if manifest.get('provenance') != provenance: manifest = {'provenance': provenance, 'cases': {}}
    for case in cases:
        if case['id'] in manifest['cases']: continue
        output, raw = run(patched, assets, case['input'], args.timeout)
        if digest(output) != case['raw_sha256']: raise RuntimeError(f'instrumentation changed output: {case["id"]}')
        stages = [s['stage'] for s in decode(raw)]
        (args.cache / f'{case["id"]}.bin.z').write_bytes(zlib.compress(raw, 6))
        manifest['cases'][case['id']] = {'input': case['input'], 'output_sha256': case['raw_sha256'], 'stages': stages}
        manifest_path.write_text(json.dumps(manifest, indent=1) + '\n')
        print(f'{case["id"]}: {stages}', flush=True)


if __name__ == '__main__': main()
