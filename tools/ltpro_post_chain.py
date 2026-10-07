#!/usr/bin/env python3
"""Run the ported post-reorder stages back to back and compare with DOS.

From each cached DOS snapshot taken after reordering, the Lua ports of the
numeric pass (151F:2740), the constituent stage (1C3D:1B3F) and T8
(1986:000E) run in sequence on the memory model, with no native code in
between. The resulting memory is compared with the DOS snapshot taken after
T8, outside the stack segment (not modeled), the BIOS tick counter, the
trace hook's own bytes and strtok's saved pointer (it may point into dead
stack). A passing case means the Lua stages reproduce every heap record,
alternative, constituent element and global that DOS had.

  python3 tools/ltpro_post_chain.py [--ids case-001 ...] [--until T8]
"""
import argparse
import subprocess
import tempfile
import zlib
from pathlib import Path

from ltpro_memtrace import MEMORY, decode
from ltpro_native_probe import lua_value
from ltpro_snapshot import DATA_SEGMENT, driver_arguments
from ltpro_trace import HOOK_SEGMENT

ORDER = ['numeric', 'constituent', 'T8']


def excluded_ranges(snapshot):
    base = (snapshot['ds'] - DATA_SEGMENT) * 16
    ds = snapshot['ds'] * 16
    ss = snapshot['ss'] * 16
    return [(0x46C, 0x470), (base + HOOK_SEGMENT * 16, base + HOOK_SEGMENT * 16 + 0x200),
            (ss, ss + 0x10000), (ds + 0xCA24, ds + 0xCA28)]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--cache', type=Path, default=Path('.cache/ltpro-memtrace'))
    ap.add_argument('--ids', nargs='*')
    ap.add_argument('--until', choices=ORDER, default='T8')
    ap.add_argument('--show', type=int, default=8)
    args = ap.parse_args()
    stages = ORDER[:ORDER.index(args.until) + 1]
    paths = [args.cache / f'{i}.bin.z' for i in args.ids] if args.ids else sorted(args.cache.glob('case-*.bin.z'))
    passed = failed = 0
    with tempfile.TemporaryDirectory(prefix='ltpro-chain-') as directory:
        directory = Path(directory)
        for path in paths:
            snapshots = decode(zlib.decompress(path.read_bytes()))
            for position, start in enumerate(snapshots):
                if start['stage'] != 'reorder': continue
                end = next((s for s in snapshots[position + 1:] if s['stage'] == args.until), None)
                if end is None: continue
                memory_file = directory / 'memory.bin'
                memory_file.write_bytes(start['memory'])
                offset, segment, si = driver_arguments(start)
                spec = {'memory': str(memory_file), 'ds': start['ds'], 'root': [offset, segment], 'si': si,
                        'stages': stages, 'rus': str(Path('LTGOLD/BASE.RUS').resolve())}
                spec_path = directory / 'spec.lua'
                spec_path.write_text('return ' + lua_value(spec))
                out = directory / 'out.bin'
                result = subprocess.run(['lua', 'tools/ltpro_post_chain.lua', str(spec_path), str(out)],
                                        capture_output=True, text=True)
                name = f'{path.name[:-6]}@{position}'
                if result.returncode:
                    failed += 1
                    if failed <= args.show: print(f'{name}: Lua error: {result.stderr.strip()[-400:]}')
                    continue
                lua = out.read_bytes()
                excluded = excluded_ranges(start)
                dos = end['memory']
                diffs = [a for a in range(MEMORY) if lua[a] != dos[a] and not any(lo <= a < hi for lo, hi in excluded)]
                if diffs:
                    failed += 1
                    if failed <= args.show:
                        print(f'{name}: {len(diffs)} differing bytes, first ' +
                              ', '.join(f'{a:05X} lua {lua[a]:02X} dos {dos[a]:02X}' for a in diffs[:4]))
                else:
                    passed += 1
    print(f'Lua {"+".join(stages)} chain vs DOS: PASS={passed} FAIL={failed}')
    raise SystemExit(bool(failed))


if __name__ == '__main__': main()
