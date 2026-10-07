#!/usr/bin/env python3
"""Print the static call closure of an LTPRO routine with per-function sizes.

Functions are discovered by following direct far calls (`9A`) and near calls
(`call rel16`, usually after `push cs`) from a root. A function's extent is the
set of instructions reachable through jumps and conditional branches from its
entry; indirect `jmp cs:[bx+table]` switches are resolved by reading the word
table up to the first target outside the segment's code. Library calls into
segment 0 are listed by name but not followed. Addresses are file offsets.

Example:
  python3 tools/ltpro_callgraph.py 1986:000E
"""
import argparse
import re
import struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_16

HEADER = 0x3A00
LIBRARY = {0x0432: 'blockcopy', 0x13D2: 'ctype', 0x1951: 'calloc', 0x1BAA: 'free', 0x1CB4: 'malloc',
           0x3C95: 'strcat', 0x3CD4: 'strchr', 0x3D11: 'strcmp', 0x3D41: 'strcpy', 0x3D6A: 'strdup',
           0x3DB0: 'stricmp', 0x3DF1: 'strlen', 0x3E34: 'strncat', 0x3E97: 'strncmp', 0x3ECF: 'strncpy',
           0x3F44: 'strpbrk', 0x3F90: 'strrchr', 0x3FD9: 'strstr', 0x05D9: 'lib05D9'}


def walk(image, md, segment, offset, max_switch=128):
    """Return (instructions by file offset, calls, switch tables) of one function."""
    base = HEADER + segment * 16
    seen, calls, todo, switches, last = {}, [], [offset], [], {}
    while todo:
        ip = todo.pop()
        while True:
            at = base + ip
            if at in seen or not HEADER <= at < len(image): break
            ins = next(md.disasm(image[at:at + 16], ip, count=1), None)
            if ins is None: break
            seen[at] = ins
            mn, ops = ins.mnemonic, ins.op_str
            if mn == 'lcall' and ',' in ops:
                s, o = (int(x, 16) for x in ops.split(', '))
                calls.append(('far', s, o))
            elif mn == 'call' and ops.startswith('0x'):
                calls.append(('near', segment, int(ops, 16)))
            if mn in ('retf', 'ret', 'iret'): break
            if mn == 'jmp' and ops.startswith('0x'):
                ip = int(ops, 16); continue
            if mn == 'mov' and ops.startswith(('cx, ', 'bx, ')) and re.fullmatch(r'(0x[0-9a-f]+|\d+)', ops[4:]):
                last[ops[:2]] = int(ops[4:], 0)
            if mn == 'cmp' and ops.startswith('bx, ') and re.fullmatch(r'(0x[0-9a-f]+|\d+)', ops[4:]):
                last['bound'] = int(ops[4:], 0)
            if mn == 'jmp' and 'cs:[bx' in ops:
                disp = int(ops.split('+ ')[1].rstrip(']'), 16) if '+' in ops else 0
                targets, keys = [], None
                if last.get('bx') is not None and last.get('cx') and disp == 2 * last['cx']:
                    # Sparse switch: CX keys at CS:BX compared in a loop, then
                    # `jmp cs:[bx+2N]` reaches the matching target word.
                    table = last['bx']
                    targets = [struct.unpack_from('<H', image, base + table + disp + 2 * i)[0] for i in range(last['cx'])]
                    keys = [struct.unpack_from('<H', image, base + table + 2 * i)[0] for i in range(last['cx'])]
                elif last.get('bound') is not None:
                    # Dense switch bounded by the preceding `cmp bx, N`.
                    targets = [struct.unpack_from('<H', image, base + disp + 2 * i)[0] for i in range(last['bound'] + 1)]
                else:
                    for i in range(max_switch):
                        t = struct.unpack_from('<H', image, base + disp + 2 * i)[0]
                        # Dense switch: stop at the first entry outside this function's range.
                        if not (offset <= t < offset + 0x4000): break
                        targets.append(t)
                switches.append((at, disp, len(targets), targets, keys))
                todo.extend(targets)
                break
            if mn.startswith('j') or mn == 'loop' or mn.startswith('jcxz'):
                if ops.startswith('0x'): todo.append(int(ops, 16))
            ip += ins.size
    return seen, calls, switches


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('root', nargs='+', help='segment:offset in hex')
    ap.add_argument('--image', default='LTGOLD/LTPRO.EXE')
    args = ap.parse_args()
    image = open(args.image, 'rb').read()
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    # Normalize aliases (1449:0004 is 1313:1364) by physical address.
    order, info, queue = [], {}, []
    for root in args.root:
        s, o = (int(x, 16) for x in root.split(':'))
        queue.append((s, o))
    while queue:
        s, o = queue.pop(0)
        phys = HEADER + s * 16 + o
        if phys in info: continue
        seen, calls, switches = walk(image, md, s, o)
        size = sum(ins.size for ins in seen.values())
        info[phys] = (s, o, size, len(seen), calls, switches)
        order.append(phys)
        for kind, cs, co in calls:
            if kind == 'far' and cs == 0: continue
            queue.append((cs, co))
    total = 0
    for phys in order:
        s, o, size, count, calls, switches = info[phys]
        total += size
        names = sorted({LIBRARY.get(co, f'0:{co:04X}') for k, cs, co in calls if k == 'far' and cs == 0})
        local = sorted({f'{HEADER + cs * 16 + co:05X}' for k, cs, co in calls if not (k == 'far' and cs == 0)})
        print(f'{phys:05X} {s:04X}:{o:04X} {size:#6x} bytes {count:5d} instrs '
              f'switches={[(hex(a), n) for a, _, n, _, _ in switches]} calls={local} lib={names}')
    print(f'total {total:#x} bytes in {len(order)} functions')


if __name__ == '__main__': main()
