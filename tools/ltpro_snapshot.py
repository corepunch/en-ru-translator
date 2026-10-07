#!/usr/bin/env python3
"""Run native post-reorder LTPRO stages from full DOS memory snapshots.

`tools/ltpro_memtrace.py` stores the 640 KiB of conventional memory that DOS had
at each driver boundary. This module loads such a snapshot into the 8086
harness of ltpro_native_probe.py, keeping the relocated code, heap records and
globals exactly as DOS left them, calls one native stage with the driver's
arguments, and decodes the resulting state. Comparing that result with the
next DOS snapshot validates the harness (and its C-library substitutes) for
that stage; the Lua ports are then compared with the harness on the same and
on perturbed inputs.

Run directly to validate every cached case:
  python3 tools/ltpro_snapshot.py
"""
import argparse
import json
import struct
from pathlib import Path

from ltpro_native_probe import Machine
from ltpro_memtrace import MEMORY, load

DATA_SEGMENT = 0x22D5
RECORD = 0x282
# Driver stage calls: (name of the snapshot holding the input, routine, name of
# the snapshot holding the expected result, pushed arguments besides the root).
STAGES = [
    ('reorder', (0x151F, 0x2740), 'numeric', False),
    ('numeric', (0x1C3D, 0x1B3F), 'constituent', True),
    ('constituent', (0x1986, 0x000E), 'T8', True),
    ('T8', (0x17AA, 0x1D31), 'generation', True),
]


class SnapshotMachine(Machine):
    """The 8086 harness over a relocated DOS memory image."""

    def __init__(self, snapshot, files=None):
        header = bytearray(0x20); struct.pack_into('<H', header, 8, 2)
        super().__init__(bytes(header))
        self.mem[:MEMORY] = snapshot['memory']
        self.base = snapshot['ds'] - DATA_SEGMENT
        self.r.update(ds=snapshot['ds'], ss=snapshot['ss'], sp=snapshot['sp'], bp=snapshot['bp'])
        # The driver's general registers, saved by the hook below its SP. They
        # are observable natively: e.g. 043A:0850 reads an uninitialized local
        # that holds the SI value 043A:074D saved in the same stack slot.
        saved = snapshot['ss'] * 16 + snapshot['sp']
        for at, name in ((4, 'ax'), (6, 'bx'), (8, 'cx'), (10, 'dx'), (12, 'si'), (14, 'di'), (20, 'es')):
            self.r[name] = struct.unpack_from('<H', snapshot['memory'], saved - at)[0]
        self.heap_next = 0xA0000
        self.files = files or {}
        self.positions = {}
        self.dos_log = []

    def library(self, segment, offset):
        # Every C-library routine runs as original code: substitutes would not
        # leave the same stack contents, heap layout or stream state, and later
        # native code reads uninitialized locals.
        return False

    def extended(self, ins, op, m):
        if m == 'int' and op[0].imm == 0x21:
            # INT pushes FLAGS, CS and IP on the caller's stack, and the
            # DOSBox-X kernel entry then saves ES DS BP DI SI DX CX BX AX
            # below them. Both images stay behind as stack garbage, which is
            # observable: 043A:0850 reads an uninitialized local from the slot
            # where the INT 21h inside lseek left its CS.
            self.push(self.flag_word()); self.push(self.reg('cs')); self.push(self.reg('ip'))
            for name in ('es', 'ds', 'bp', 'di', 'si', 'dx', 'cx', 'bx', 'ax'): self.push(self.reg(name))
            self.dos(self.reg('ah'))
            carry = self.cf
            self.reg('sp', self.reg('sp') + 18)
            self.pop(); self.pop(); self.set_flag_word(self.pop())
            self.cf = carry
            return True
        return super().extended(ins, op, m)

    def dos(self, function):
        """The DOS file services reached by the post-reorder stages.

        Handles are mapped to asset files by `files`; positions start unknown
        and must be set by an absolute seek before any read.
        """
        handle = self.reg('bx')
        self.dos_log.append((function, handle, self.reg('al'), self.reg('cx'), self.reg('dx')))
        if function == 0x42:
            whence, offset = self.reg('al'), (self.reg('cx') << 16) | self.reg('dx')
            if whence == 0: self.positions[handle] = offset
            elif whence == 1: self.positions[handle] = self.positions[handle] + offset
            else: self.positions[handle] = len(self.files[handle]) + offset
            self.positions[handle] &= 0xFFFFFFFF
            self.reg('ax', self.positions[handle]); self.reg('dx', self.positions[handle] >> 16)
        elif function == 0x3F:
            data = self.files[handle][self.positions[handle]:self.positions[handle] + self.reg('cx')]
            target = self.reg('ds') * 16 + self.reg('dx')
            for i, value in enumerate(data): self.write(target + i, 1, value)
            self.positions[handle] += len(data)
            self.reg('ax', len(data))
        elif function == 0x4A:
            # Resize the program's block (the Borland heap growing). As DOSBox
            # does, absorb the following free block and write a new free MCB
            # after the resized one; other MCB bytes keep their contents.
            segment, wanted = self.reg('es'), self.reg('bx')
            mcb = (segment - 1) * 16
            size = struct.unpack_from('<H', self.mem, mcb + 3)[0]
            following = mcb + (size + 1) * 16
            kind = self.mem[mcb]
            available = size
            if struct.unpack_from('<H', self.mem, following + 1)[0] == 0:
                available += struct.unpack_from('<H', self.mem, following + 3)[0] + 1
                kind = self.mem[following]
            if wanted > available:
                self.reg('ax', 8); self.reg('bx', available); self.cf = True
                return True
            self.write(mcb + 3, 2, wanted)
            if wanted < available:
                free = mcb + (wanted + 1) * 16
                self.write(mcb, 1, 0x4D)
                self.write(free, 1, kind)
                self.write(free + 1, 2, 0)
                self.write(free + 3, 2, available - wanted - 1)
            else:
                self.write(mcb, 1, kind)
        elif function == 0x44 and self.reg('al') == 0:
            self.reg('dx', 0x0002)  # a disk file, not a device
        else:
            raise AssertionError(f'unsupported DOS function {function:02X}')
        self.cf = False
        return True

    def watch_uninitialized(self):
        """Report reads of stack locals not written since their frame began.

        Frames are tracked from CALL/LCALL (return address position, step)
        and dropped when SP rises above them. A read at or above SP belongs to
        the innermost frame whose return address lies above it; if any byte
        was last written before that frame was entered, the read sees garbage
        left by earlier code (or by DOS, hooks, interrupts).
        """
        self.frames, self.stack_writes, self.uninitialized = [], {}, []
        stack = (self.reg('ss') * 16, self.reg('ss') * 16 + 0x10000)
        plain_read, plain_write = self.read, self.write

        def write(address, size, value):
            if stack[0] <= address < stack[1]:
                for i in range(size): self.stack_writes[address + i] = self.steps
            plain_write(address, size, value)

        def read(address, size):
            sp = self.reg('ss') * 16 + self.reg('sp')
            if stack[0] <= address < stack[1] and address >= sp and self.frames:
                owner = next((f for f in reversed(self.frames) if f[0] > address), None)
                stale = [self.stack_writes.get(address + i, -1) < owner[1] for i in range(size)] if owner else []
                # Word-wise library string scans read one byte past a NUL; only
                # bytes up to and including the first NUL are significant there.
                if any(stale) and self.reg('cs') == self.base and size == 2 and not stale[0] and self.mem[address] == 0:
                    stale = []
                if any(stale):
                    ins = self.current
                    self.uninitialized.append({'cs': self.reg('cs') - self.base, 'ip': ins.address if ins else None,
                        'instruction': f'{ins.mnemonic} {ins.op_str}' if ins else '', 'bp_offset': address - (self.reg('ss') * 16 + self.reg('bp')),
                        'value': plain_read(address, size), 'step': self.steps})
            return plain_read(address, size)

        def observe(machine):
            sp = machine.reg('ss') * 16 + machine.reg('sp')
            while machine.frames and machine.frames[-1][0] < sp: machine.frames.pop()
            ins = machine.current
            if ins is not None and ins.mnemonic in ('call', 'lcall') and machine.last_step_sp != sp:
                machine.frames.append((sp, machine.steps))
            machine.last_step_sp = sp
            return False

        self.read, self.write = read, write
        self.last_step_sp = None
        self.before_instruction = observe

    def far(self, address):
        return self.read(address + 2, 2) * 16 + self.read(address, 2)

    def call(self, routine, *words):
        """Far-call `routine` (unrelocated segment, offset) with word arguments."""
        segment, offset = routine
        for value in reversed(words): self.push(value)
        self.push(0xFFFF); self.push(0xFFFF)
        self.reg('cs', segment + self.base); self.reg('ip', offset)
        self.run()
        self.reg('sp', self.reg('sp') + 2 * len(words))
        return self.reg('ax')


def driver_arguments(snapshot):
    """The driver's root pointer words at [bp+0A] and its SI register.

    The hook dumped memory while its saved registers were on the stack:
    flags at SP-2, then AX BX CX DX SI DI BP DS ES, so SI is at SP-12.
    """
    memory, ss = snapshot['memory'], snapshot['ss'] * 16
    word = lambda at: struct.unpack_from('<H', memory, at)[0]
    bp = ss + snapshot['bp']
    return word(bp + 0x0A), word(bp + 0x0C), word(ss + snapshot['sp'] - 12)


def records(memory, root):
    """Walk the linked records from the root structure's next pointer."""
    def far(at): return struct.unpack_from('<H', memory, at + 2)[0] * 16 + struct.unpack_from('<H', memory, at)[0]
    result, address, seen = [], far(root), set()
    while address:
        if address in seen or address + RECORD > len(memory): raise ValueError('invalid record list')
        seen.add(address)
        result.append((address, bytes(memory[address:address + RECORD])))
        address = far(address)
    return result


def asset_files(data=Path('LTGOLD')):
    """DOS handle -> file bytes for the frozen profile.

    LTPRO keeps BASE.RUS open on handle 5 and looks Russian entries up on disk
    through an in-memory index (observed: lseek then read on handle 5).
    """
    return {5: (data / 'BASE.RUS').read_bytes()}


def run_stage(snapshot, index, files=None):
    """Run driver stage `index` of STAGES natively from `snapshot`."""
    _, routine, _, with_si = STAGES[index]
    machine = SnapshotMachine(snapshot, files if files is not None else asset_files())
    offset, segment, si = driver_arguments(snapshot)
    words = (offset, segment, si) if with_si else (offset, segment)
    result = machine.call(routine, *words)
    return machine, result, segment * 16 + offset


def differences(native, dos, snapshot):
    """Byte ranges where harness memory differs from the DOS snapshot.

    Excluded: the BIOS tick counter, the hook stub's own code and variables
    (TRACE header words change per boundary), and the 40h bytes below the
    driver's SP that the hook's saved registers, DOS calls and dump occupy in
    DOS but not in the harness. All other memory, including dead stack frames
    deeper than that and the whole heap, must be identical.
    """
    from ltpro_trace import HOOK_SEGMENT
    base = (snapshot['ds'] - DATA_SEGMENT) * 16
    stack = snapshot['ss'] * 16 + snapshot['sp']
    excluded = [(0x46C, 0x470), (base + HOOK_SEGMENT * 16, base + HOOK_SEGMENT * 16 + 0x200), (stack - 0x40, stack)]
    a, b = bytes(native[:MEMORY]), bytes(dos)
    runs, i = [], 0
    while True:
        while i < MEMORY and a[i] == b[i]: i += 1
        if i >= MEMORY: break
        j = i
        while j < MEMORY and a[j] != b[j]: j += 1
        if not any(lo <= i < hi for lo, hi in excluded): runs.append((i, j))
        i = j
    return runs


def main():
    from ltpro_memtrace import decode
    import zlib
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--cache', type=Path, default=Path('.cache/ltpro-memtrace'))
    ap.add_argument('--ids', nargs='*')
    args = ap.parse_args()
    ids = args.ids or sorted(p.name[:-6] for p in args.cache.glob('case-*.bin.z'))
    totals, failures = {}, 0
    for case in ids:
        snapshots = decode(zlib.decompress((args.cache / f'{case}.bin.z').read_bytes()))
        for position in range(len(snapshots) - 1):
            for index, (before, _, after, _) in enumerate(STAGES):
                if snapshots[position]['stage'] != before or snapshots[position + 1]['stage'] != after: continue
                machine, _, _ = run_stage(snapshots[position], index)
                runs = differences(machine.mem, snapshots[position + 1]['memory'], snapshots[position])
                passed, total = totals.get(after, (0, 0))
                totals[after] = (passed + (not runs), total + 1)
                if runs:
                    failures += 1
                    print(f'{case} {after}: {len(runs)} differing ranges, first at {runs[0][0]:05X}', flush=True)
    for name, (passed, total) in totals.items(): print(f'{name}: harness equals DOS memory in {passed}/{total} transitions')
    raise SystemExit(bool(failures))


if __name__ == '__main__': main()
