#!/usr/bin/env python3
"""Instruction coverage of the native post-reorder stages over cached snapshots.

Runs every cached DOS snapshot transition through the 8086 harness and records
the executed instruction addresses (file offsets). Prints, per function of
each stage's static call closure, how many of its instructions ran. Use it to
see which branches the corpus reaches and which need generated fixtures.
"""
import argparse
import json
import zlib
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_16

from ltpro_callgraph import HEADER, walk
from ltpro_memtrace import decode
from ltpro_snapshot import STAGES, SnapshotMachine, asset_files, driver_arguments


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--cache', type=Path, default=Path('.cache/ltpro-memtrace'))
    ap.add_argument('--output', type=Path, default=Path('.cache/coverage.json'))
    args = ap.parse_args()
    files = asset_files()
    executed = {name: set() for _, _, name, _ in STAGES}
    for path in sorted(args.cache.glob('case-*.bin.z')):
        snapshots = decode(zlib.decompress(path.read_bytes()))
        for position in range(len(snapshots) - 1):
            for index, (before, routine, after, with_si) in enumerate(STAGES):
                if snapshots[position]['stage'] != before or snapshots[position + 1]['stage'] != after: continue
                machine = SnapshotMachine(snapshots[position], files)
                seen = executed[after]
                def observe(m, seen=seen):
                    seen.add(HEADER + (m.reg('cs') - m.base) * 16 + m.reg('ip'))
                    return False
                machine.before_instruction = observe
                offset, segment, si = driver_arguments(snapshots[position])
                machine.call(routine, *((offset, segment, si) if with_si else (offset, segment)))
    image = open('LTGOLD/LTPRO.EXE', 'rb').read()
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    report = {}
    for _, (segment, offset), name, _ in STAGES:
        queue, done, rows = [(segment, offset)], set(), []
        while queue:
            s, o = queue.pop(0)
            phys = HEADER + s * 16 + o
            if phys in done: continue
            done.add(phys)
            instructions, calls, _ = walk(image, md, s, o)
            ran = len(set(instructions) & executed[name])
            rows.append({'function': f'{s:04X}:{o:04X}', 'file': f'{phys:05X}', 'instructions': len(instructions), 'executed': ran})
            queue.extend((cs, co) for kind, cs, co in calls if not (kind == 'far' and cs == 0))
        report[name] = rows
        print(f'== {name}')
        for row in rows: print(f"  {row['function']} ({row['file']}): {row['executed']}/{row['instructions']}")
    report['executed'] = {name: sorted(f'{a:05X}' for a in seen) for name, seen in executed.items()}
    args.output.write_text(json.dumps(report))


if __name__ == '__main__': main()
