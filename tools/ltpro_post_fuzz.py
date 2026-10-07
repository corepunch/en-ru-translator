#!/usr/bin/env python3
"""Mutation fuzzing of the post-reorder stage ports against native code.

Takes cached DOS snapshots at a stage boundary, randomizes byte fields of
the word records in the list (tags, markers, grammatical fields), then runs
the native stages in the 8086 harness and the Lua ports from the same
mutated memory, and compares all memory outside the stack segment. Pointers
and strings are left intact, so the mutated states stay well formed; they
need not be reachable from English input, but they drive the rule handlers
through branches the corpus does not reach.

  python3 tools/ltpro_post_fuzz.py --start numeric --stages constituent T8 --cases 300
"""
import argparse
import random
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

from ltpro_memtrace import MEMORY, decode
from ltpro_native_probe import lua_value
from ltpro_post_chain import excluded_ranges
from ltpro_snapshot import STAGES, SnapshotMachine, asset_files, driver_arguments, records

TAGS = b'NAVEGFPDJRXYUBbIOHQSTLWwkpxyfrnlu#?*,C()|^t=:;&-iMvesqzdj'
FIELDS = {0x0B: [1, 2, 3, 4], 0x0F: [0, 0, 0, 0x77, 0x57, 0x6E, 0x71, 0x72, 0x3D, 0x68, 0x58, 0x6B, 0x67],
          0x66: list(b'NAVEGPD#?HSZIeG') + [0], 0x68: [0, 1, 2, 3, 0x41, 0xC2], 0x6A: [0, 1, 2, 3, 0x40, 0x41, 0x42],
          0x6D: list(range(0, 64)), 0x6E: [0, 0x10, 0x40, 0x50], 0x72: [0, 1, 2], 0x73: [0, 1, 2],
          0x74: [0, 1, 2, 3], 0x75: [0, 1, 2], 0x76: [0, 2, 4, 8, 0x10, 0x20], 0x77: [0, 1, 2],
          0x78: [0, 1, 4, 8, 5], 0x79: [0, 2, 4, 8], 0x7A: [0, 1], 0x7B: [0, 1]}
STAGE_INDEX = {after: index for index, (_, _, after, _) in enumerate(STAGES)}
BEFORE = {after: before for before, _, after, _ in STAGES}
OUTPUT_ROUTINES = {'output': (0x0687, 0x0BB7), 'meanings': (0x0687, 0x01C8), 'cleanup': (0x0687, 0x0A50)}


ELEMENT_TAGS = b'NAVEGFPDJRXYUBbIOHQSLWkpxyfrlu#?*,C|^t=:;&iM'
CLASSES = b'*WwGKkPYyCDq'


_readings = []


def readings():
    """Dictionary values (text after the first '*') usable as record readings."""
    if not _readings:
        for line in Path('LTGOLD/BASE.DIC').read_bytes().split(b'\n'):
            star = line.find(b'*')
            value = line[star + 1:].rstrip(b'\r') if star > 0 else b''
            if 0 < len(value) < 0x100 and b'$' not in value[:1]: _readings.append(value)
    return _readings


def mutate(snapshot, rng, rate, elements=False, texts=False):
    memory = bytearray(snapshot['memory'])
    if elements:
        # Constituent elements (tag +0 mirrored in DS:C7B6, class +2).
        ds = snapshot['ds'] * 16
        aoff, aseg = struct.unpack_from('<HH', memory, ds + 0xC7FA)
        count = struct.unpack_from('<H', memory, ds + 0xC7FE)[0]
        for i in range(1, count - 1):
            e = aseg * 16 + aoff + 12 * i
            if rng.random() < rate:
                t = rng.choice(ELEMENT_TAGS); memory[e] = t; memory[ds + 0xC7B6 + i] = t
            if rng.random() < rate:
                memory[e + 2] = rng.choice(CLASSES)
    offset, segment, _ = driver_arguments(snapshot)
    for address, raw in records(memory, segment * 16 + offset):
        if raw[0x0E] != 0x57: continue
        if texts and rng.random() < rate:
            # A real dictionary reading as the record's text; +98 at +11C.
            value = rng.choice(readings())
            memory[address + 0x11C:address + 0x11C + len(value) + 1] = value + b'\0'
            off = address - (address >> 4) * 16 + 0x11C
            struct.pack_into('<HH', memory, address + 0x98, off, address >> 4)
            memory[address + 0x0B] = rng.choice([2, 2, 3, 4])
        if rng.random() < rate:
            memory[address + 0x0C] = rng.choice(TAGS + (b' ' if elements else b''))
        for field, values in FIELDS.items():
            if rng.random() < rate / 2:
                memory[address + field] = rng.choice(values)
    return dict(snapshot, memory=bytes(memory))


def native(snapshot, stages, files, executed=None):
    """Run native stages in order from one snapshot; returns final memory."""
    current = snapshot
    alternatives = None
    for name in stages:
        machine = SnapshotMachine(current, files)
        if executed is not None:
            def observe(m, seen=executed):
                seen.add(0x3A00 + (m.reg('cs') - m.base) * 16 + m.reg('ip'))
                return False
            machine.before_instruction = observe
        offset, segment, si = driver_arguments(current)
        if name in OUTPUT_ROUTINES:
            ds = snapshot['ds'] * 16
            if name == 'output':
                out_o, out_s = struct.unpack_from('<HH', machine.mem, ds + 0xC58C)
                machine.write(out_s * 16 + out_o, 1, 0)
                machine.call(OUTPUT_ROUTINES[name], offset, segment, out_o, out_s)
                alternatives = machine.reg('ax')
            elif name == 'meanings':
                word = lambda a: struct.unpack_from('<H', machine.mem, ds + a)[0]
                if word(0xBBB6) and (word(0xBBB4) or word(0xBBBA)):
                    if alternatives is None: raise ValueError('meanings must follow output')
                    out_o, out_s = struct.unpack_from('<HH', machine.mem, ds + 0xC598)
                    machine.call(OUTPUT_ROUTINES[name], offset, segment, out_o, out_s)
                    machine.write(ds + 0x042B, 2, (word(0x042B) + alternatives) & 0xFFFF)
            else:
                machine.call(OUTPUT_ROUTINES[name], offset, segment)
        else:
            _, routine, _, with_si = STAGES[STAGE_INDEX[name]]
            machine.call(routine, *((offset, segment, si) if with_si else (offset, segment)))
        # Keep the driver's frame for the next stage: SP/BP are restored by the
        # harness call; carry the registers the hook recorded.
        current = dict(current, memory=bytes(machine.mem[:MEMORY]))
    return current['memory']


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--cache', type=Path, default=Path('.cache/ltpro-memtrace'))
    ap.add_argument('--start', default='numeric', help='snapshot to mutate: reorder, numeric or constituent')
    ap.add_argument('--stages', nargs='+', default=['constituent', 'T8'])
    ap.add_argument('--cases', type=int, default=200)
    ap.add_argument('--rate', type=float, default=0.3)
    ap.add_argument('--seed', type=int, default=1993)
    ap.add_argument('--show', type=int, default=6)
    ap.add_argument('--coverage', action='store_true', help='report native instruction coverage per function')
    ap.add_argument('--elements', action='store_true', help='also mutate constituent elements (start at constituent)')
    ap.add_argument('--only', type=int, help='replay only this case number of the seeded sequence')
    ap.add_argument('--keep', type=Path, help='with --only: save the mutated snapshot memory here')
    ap.add_argument('--texts', action='store_true', help='also replace record readings with dictionary values')
    args = ap.parse_args()
    executed = set() if args.coverage else None
    rng = random.Random(args.seed)
    files = asset_files()
    pool = []
    for path in sorted(args.cache.glob('case-*.bin.z')):
        for s in decode(zlib.decompress(path.read_bytes())):
            if s['stage'] == args.start: pool.append((path.name[:-6], s))
    passed = failed = skipped = 0
    with tempfile.TemporaryDirectory(prefix='ltpro-fuzz-') as directory:
        directory = Path(directory)
        for number in range(args.cases):
            name, base = rng.choice(pool)
            snapshot = mutate(base, rng, args.rate, args.elements, args.texts)
            if args.only is not None and number != args.only: continue
            if args.keep: args.keep.write_bytes(snapshot['memory'])
            try:
                expected = native(snapshot, args.stages, files, executed)
            except Exception as error:
                skipped += 1
                if skipped <= args.show: print(f'#{number} {name}: native skipped: {error!r}', flush=True)
                continue
            memory_file = directory / 'memory.bin'
            memory_file.write_bytes(snapshot['memory'])
            offset, segment, si = driver_arguments(snapshot)
            spec = {'memory': str(memory_file), 'ds': snapshot['ds'], 'root': [offset, segment], 'si': si,
                    'stages': args.stages, 'rus': str(Path('LTGOLD/BASE.RUS').resolve())}
            (directory / 'spec.lua').write_text('return ' + lua_value(spec))
            out = directory / 'out.bin'
            result = subprocess.run(['lua', 'tools/ltpro_post_chain.lua', str(directory / 'spec.lua'), str(out)],
                                    capture_output=True, text=True)
            if result.returncode:
                failed += 1
                if failed <= args.show: print(f'#{number} {name}: Lua error: {result.stderr.strip()[-300:]}')
                continue
            lua = out.read_bytes()
            excluded = excluded_ranges(snapshot)
            diffs = [a for a in range(MEMORY) if lua[a] != expected[a] and not any(lo <= a < hi for lo, hi in excluded)]
            if diffs:
                failed += 1
                if failed <= args.show:
                    print(f'#{number} {name}: {len(diffs)} differing bytes: ' +
                          ', '.join(f'{a:05X} lua {lua[a]:02X} native {expected[a]:02X}' for a in diffs[:5]))
            else:
                passed += 1
    print(f'fuzz {args.start} -> {"+".join(args.stages)}: PASS={passed} FAIL={failed} native-skipped={skipped}')
    if executed is not None:
        from capstone import Cs, CS_ARCH_X86, CS_MODE_16
        from ltpro_callgraph import walk, HEADER
        image = open('LTGOLD/LTPRO.EXE', 'rb').read()
        md = Cs(CS_ARCH_X86, CS_MODE_16)
        for name in args.stages:
            if name in OUTPUT_ROUTINES: segment, offset = OUTPUT_ROUTINES[name]
            else: _, (segment, offset), _, _ = STAGES[STAGE_INDEX[name]]
            queue, done = [(segment, offset)], set()
            print(f'== coverage {name}')
            while queue:
                s_, o_ = queue.pop(0)
                phys = HEADER + s_ * 16 + o_
                if phys in done: continue
                done.add(phys)
                instructions, calls, _ = walk(image, md, s_, o_)
                print(f'  {s_:04X}:{o_:04X}: {len(set(instructions) & executed)}/{len(instructions)}')
                queue.extend((cs, co) for kind, cs, co in calls if not (kind == 'far' and cs == 0))
    raise SystemExit(bool(failed))


if __name__ == '__main__': main()
