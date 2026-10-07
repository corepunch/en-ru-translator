#!/usr/bin/env python3
"""Random malloc/calloc/strdup/free sequences: native heap code vs core/heap.lua.

Starts from a cached DOS snapshot (its live heap included), runs the same
seeded operation sequence through the original library routines in the 8086
harness and through the Lua port, and compares all memory outside the stack
segment plus every returned pointer.
"""
import argparse
import random
import subprocess
import tempfile
import zlib
from pathlib import Path

from ltpro_memtrace import MEMORY, decode
from ltpro_native_probe import lua_value
from ltpro_snapshot import SnapshotMachine, asset_files


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--snapshot', default='.cache/ltpro-memtrace/case-001.bin.z')
    ap.add_argument('--sequences', type=int, default=40)
    ap.add_argument('--length', type=int, default=60)
    args = ap.parse_args()
    snapshot = decode(zlib.decompress(Path(args.snapshot).read_bytes()))[0]
    rng = random.Random(1993)
    failures = 0
    with tempfile.TemporaryDirectory(prefix='ltpro-heap-') as directory:
        base = Path(directory) / 'memory.bin'
        base.write_bytes(snapshot['memory'])
        for number in range(args.sequences):
            machine = SnapshotMachine(snapshot, asset_files())
            live, operations, results = [], [], []
            for _ in range(args.length):
                choice = rng.random()
                if live and choice < 0.4:
                    seg, off = live.pop(rng.randrange(len(live)))
                    operations.append(['free', off, seg])
                    machine.call((0, 0x1BAA), off, seg)
                    results.append([0, 0])
                    continue
                size = rng.choice([1, 2, 12, 20, 0x14F, 0x282, rng.randrange(1, 3000), rng.randrange(1, 70000) & 0xFFFF])
                if choice < 0.7:
                    operations.append(['malloc', size])
                    machine.call((0, 0x1CB4), size)
                else:
                    count = rng.randrange(1, 4)
                    operations.append(['calloc', count, size])
                    machine.call((0, 0x1951), count, size)
                seg, off = machine.reg('dx'), machine.reg('ax')
                results.append([off, seg])
                if seg: live.append((seg, off))
            stack = (snapshot['ss'] * 16, snapshot['ss'] * 16 + 0x10000)
            native = bytes(machine.mem[:MEMORY])
            spec = {'memory': str(base), 'ds': snapshot['ds'], 'operations': operations, 'results': results}
            spec_path = Path(directory) / 'spec.lua'
            spec_path.write_text('return ' + lua_value(spec))
            out = Path(directory) / 'lua.bin'
            subprocess.run(['lua', 'tools/ltpro_heap_fuzz.lua', str(spec_path), str(out)], check=True)
            lua = out.read_bytes()
            diffs = [a for a in range(MEMORY) if native[a] != lua[a] and not stack[0] <= a < stack[1] and not 0x46C <= a < 0x470]
            if diffs:
                failures += 1
                print(f'sequence {number}: {len(diffs)} differing bytes, first {diffs[0]:05X}', flush=True)
    print(f'heap fuzz: {args.sequences - failures}/{args.sequences} sequences identical')
    raise SystemExit(bool(failures))


if __name__ == '__main__': main()
