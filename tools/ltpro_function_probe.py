#!/usr/bin/env python3
"""Compare Lua ports of individual native functions with their native calls.

The post-reorder stages are run in the 8086 harness from every cached DOS
snapshot. Whenever control enters a chosen native function, the probe records
the call: its stack arguments, the memory writes made since the stage began
(so memory at entry is snapshot + delta), the writes the call makes before it
returns, and AX/DX at return. The Lua port then replays each call from the
same memory and must make the same writes (outside the stack segment, which
the ports do not model) and return the same values.

  python3 tools/ltpro_function_probe.py 151F:0B6B --words 2 --limit 300

`--words` is the number of 16-bit argument words passed to the Lua adapter
(tools/ltpro_function_probe.lua maps each function to its Lua port).
"""
import argparse
import json
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

from ltpro_memtrace import MEMORY, decode
from ltpro_native_probe import lua_value
from ltpro_snapshot import STAGES, SnapshotMachine, asset_files, driver_arguments


class Recorder(SnapshotMachine):
    """Track every write since the stage began, and calls to one function."""

    def __init__(self, snapshot, files, target, words, limit, cases, snapshot_id):
        super().__init__(snapshot, files)
        self.delta = {}
        self.target, self.words, self.limit, self.cases, self.snapshot_id = target, words, limit, cases, snapshot_id
        self.active = []  # open calls: (return sp, case, writes)
        plain_write = self.write

        def write(address, size, value):
            for i in range(size):
                byte = (value >> (8 * i)) & 0xFF
                self.delta[address + i] = byte
                for call in self.active: call[2][address + i] = byte
            plain_write(address, size, value)
        self.write = write
        self.before_instruction = self.observe

    def observe(self, machine):
        cs, ip = self.reg('cs') - self.base, self.reg('ip')
        ss, sp = self.reg('ss'), self.reg('sp')
        # The heap's free-list insertion briefly loads SS with a heap segment;
        # a call has returned only when SP rises above it on the same SS.
        while self.active and ss == self.active[-1][0][0] and sp > self.active[-1][0][1]:
            _, case, writes = self.active.pop()
            stack = (ss * 16, ss * 16 + 0x10000)
            case['writes'] = sorted([a, v] for a, v in writes.items() if not stack[0] <= a < stack[1])
            case['ax'], case['dx'] = self.reg('ax'), self.reg('dx')
        if (cs, ip) == self.target and len(self.cases) < self.limit:
            args = [self.read(ss * 16 + sp + 4 + 2 * i, 2) for i in range(self.words)]
            case = {'snapshot': self.snapshot_id, 'args': args, 'si': self.reg('si'), 'di': self.reg('di'),
                    'before': sorted([a, v] for a, v in self.delta.items()),
                    'positions': {str(h): p for h, p in self.positions.items()}}
            self.cases.append(case)
            # The call returns once SP rises above its return address.
            self.active.append(((ss, sp), case, {}))
        return False


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('function', help='segment:offset (unrelocated) of the native entry')
    ap.add_argument('--words', type=int, required=True)
    ap.add_argument('--limit', type=int, default=400)
    ap.add_argument('--cache', type=Path, default=Path('.cache/ltpro-memtrace'))
    ap.add_argument('--stages', nargs='*', help='only these stage results (numeric, constituent, T8, generation)')
    ap.add_argument('--show', type=int, default=5)
    args = ap.parse_args()
    target = tuple(int(x, 16) for x in args.function.split(':'))
    files = asset_files()
    cases, snapshots_used = [], {}
    with tempfile.TemporaryDirectory(prefix='ltpro-function-') as directory:
        directory = Path(directory)
        for path in sorted(args.cache.glob('case-*.bin.z')):
            if len(cases) >= args.limit: break
            snapshots = decode(zlib.decompress(path.read_bytes()))
            for position in range(len(snapshots) - 1):
                for index, (before, routine, after, with_si) in enumerate(STAGES):
                    if snapshots[position]['stage'] != before or snapshots[position + 1]['stage'] != after: continue
                    if args.stages and after not in args.stages: continue
                    snapshot_id = f'{path.name[:-6]}-{position}'
                    count = len(cases)
                    machine = Recorder(snapshots[position], files, target, args.words, args.limit, cases, snapshot_id)
                    offset, segment, si = driver_arguments(snapshots[position])
                    machine.call(routine, *((offset, segment, si) if with_si else (offset, segment)))
                    # The stage entry itself returns to the harness, not to an
                    # observed instruction.
                    while machine.active:
                        _, case, writes = machine.active.pop()
                        stack = (machine.reg('ss') * 16, machine.reg('ss') * 16 + 0x10000)
                        case['writes'] = sorted([a, v] for a, v in writes.items() if not stack[0] <= a < stack[1])
                        case['ax'], case['dx'] = machine.reg('ax'), machine.reg('dx')
                    if len(cases) > count:
                        file = directory / f'{snapshot_id}.bin'
                        file.write_bytes(snapshots[position]['memory'])
                        snapshots_used[snapshot_id] = {'file': str(file), 'ds': snapshots[position]['ds'],
                                                       'ss': snapshots[position]['ss']}
        unfinished = [c for c in cases if 'writes' not in c]
        if unfinished: raise SystemExit(f'{len(unfinished)} calls did not return')
        spec = {'function': args.function, 'snapshots': snapshots_used, 'cases': cases,
                'rus': str(Path('LTGOLD/BASE.RUS').resolve())}
        spec_path = directory / 'spec.lua'
        spec_path.write_text('return ' + lua_value(spec))
        result = subprocess.run(['lua', 'tools/ltpro_function_probe.lua', str(spec_path), str(args.show)])
    raise SystemExit(result.returncode)


if __name__ == '__main__': main()
