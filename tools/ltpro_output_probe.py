#!/usr/bin/env python3
"""Replay native sentence/appendix calls from DOS generation snapshots.

These are stage comparisons, not a standalone-input or full-file parity claim.
The Lua port must reproduce every non-stack write and the sentence return value.
"""
import argparse
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

from ltpro_function_probe import Recorder
from ltpro_memtrace import decode
from ltpro_native_probe import lua_value
from ltpro_snapshot import asset_files, driver_arguments


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--function', choices=['sentence', 'meanings', 'cleanup'], default='sentence')
    ap.add_argument('--cache', type=Path, default=Path('.cache/ltpro-memtrace'))
    ap.add_argument('--show', type=int, default=5)
    ap.add_argument('--width', type=int, help='exercise wrapped appendix mode with this line width')
    args = ap.parse_args()
    target = (0x0687, {'sentence': 0x0BB7, 'meanings': 0x01C8, 'cleanup': 0x0A50}[args.function])
    cases, used = [], {}
    with tempfile.TemporaryDirectory(prefix='ltpro-output-') as temp:
        directory = Path(temp)
        for path in sorted(args.cache.glob('case-*.bin.z')):
            for index, snap in enumerate(decode(zlib.decompress(path.read_bytes()))):
                if snap['stage'] != 'generation': continue
                if args.width is not None:
                    data = bytearray(snap['memory'])
                    struct.pack_into('<H', data, snap['ds'] * 16 + 0xBB92, 1)
                    struct.pack_into('<H', data, snap['ds'] * 16 + 0xBBA6, args.width)
                    snap = dict(snap, memory=bytes(data))
                name = f'{path.name[:-6]}-{index}'
                machine = Recorder(snap, asset_files(), target, 2 if args.function == 'cleanup' else 4, 100000, cases, name)
                root_o, root_s, _ = driver_arguments(snap)
                ds = snap['ds'] * 16
                out_o, out_s = struct.unpack_from('<HH', machine.mem, ds + 0xC58C)
                machine.write(out_s * 16 + out_o, 1, 0)
                machine.call((0x0687, 0x0BB7), root_o, root_s, out_o, out_s)
                if args.function in ('meanings', 'cleanup'):
                    out_o, out_s = struct.unpack_from('<HH', machine.mem, ds + 0xC598)
                    machine.call((0x0687, 0x01C8), root_o, root_s, out_o, out_s)
                if args.function == 'cleanup': machine.call(target, root_o, root_s)
                while machine.active:
                    _, case, writes = machine.active.pop()
                    lo = snap['ss'] * 16
                    case['writes'] = sorted([a, v] for a, v in writes.items() if not lo <= a < lo + 0x10000)
                    case['ax'], case['dx'] = machine.reg('ax'), machine.reg('dx')
                file = directory / f'{name}.bin'
                file.write_bytes(snap['memory'])
                used[name] = {'file': str(file), 'ds': snap['ds'], 'ss': snap['ss']}
        if not cases: ap.error('no generation snapshots found')
        spec = {'function': f'{target[0]:04X}:{target[1]:04X}', 'snapshots': used, 'cases': cases,
                'rus': str(Path('LTGOLD/BASE.RUS').resolve())}
        file = directory / 'spec.lua'
        file.write_text('return ' + lua_value(spec))
        result = subprocess.run(['lua', 'tools/ltpro_function_probe.lua', str(file), str(args.show)])
        raise SystemExit(result.returncode)


if __name__ == '__main__': main()
