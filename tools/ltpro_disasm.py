#!/usr/bin/env python3
"""Disassemble a file-offset range of the unpacked LTPRO.EXE, optionally condensed.

Addresses are file offsets; the MZ header is 0x3A00 bytes, so a segment:offset
pair maps to file 0x3A00 + segment*16 + offset. Jump targets are printed as
file offsets. With --frame BASE the common Borland idiom

    mov bx,SRC; mov cl,2; shl bx,cl; lea ax,[bp-BASE]; add bx,ax; les bx,ss:[bx]

is collapsed to `N=V[SRC]` and later `es:[bx+NN]` operands print as `V[SRC].NN`.
The N= tracking follows the listing order, not control flow: a line reached by
a jump may address a different record than the one printed, and `les bx, X.62`
redirects following writes through that link. See reference/LTPRO_NATIVE_MAP.md
for frame layouts to pass as --names.

Examples:
  python3 tools/ltpro_disasm.py 1254A 13700 --segment E1F --frame 842 --names t1
  python3 tools/ltpro_disasm.py 142FF 1608F --segment 108F --frame 848 --names t4
"""
import argparse
import re
import struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_16

HEADER = 0x3A00
NAMES = {
    't1': {'[bp - 6]': 'last', '[bp - 0x16]': 'i', '[bp - 2]': 'removed', '[bp - 0xa]': 'rule1',
           '[bp - 0xe]': 'rule2', '[bp - 0x12]': 'rule3', '[bp - 0x18]': 'back', '[bp - 0x14]': 'j',
           '[bp - 0x1c]': 'head', '[bp - 0x20]': 'tail', '[bp - 0x1a]': 'head.seg', '[bp - 0x1e]': 'tail.seg',
           '[bp - 0x28]': 'p28', '[bp - 0x26]': 'p28.seg', '[bp - 0x32]': 'p32', '[bp - 0x30]': 'p32.seg',
           '[bp - 0x36]': 'p36', '[bp - 0x34]': 'p36.seg', '[0xc7b1]': 'count', '[bp + 0xa]': 'terminator'},
    't4': {'[bp - 4]': 'last', '[bp - 8]': 'rule', '[bp - 6]': 'rule.seg', '[bp - 0xc]': 'k',
           '[bp - 0xe]': 'flag', '[bp - 0x12]': 'head', '[bp - 0x10]': 'head.seg', '[bp - 0x16]': 'tail',
           '[bp - 0x14]': 'tail.seg', '[bp - 0x22]': 'new', '[bp - 0x20]': 'new.seg', '[bp - 0x24]': 'sel',
           '[bp - 0x28]': 'best', '[bp - 0x26]': 'best.seg', '[bp - 0x2a]': 'best_index', '[bp - 0x2c]': 'r',
           '[bp - 0x2e]': 'tail_action', '[bp - 0x30]': 'tail_action.seg', '[bp - 0x38]': 'action',
           '[bp - 0x36]': 'action.seg', '[bp - 0x3a]': 'selector', '[bp - 0x3c]': 'sub_result',
           '[bp - 2]': 'removed', '[0xc7b1]': 'count'},
    'reorder': {'[bp - 8]': 'table.seg', '[bp - 0xa]': 'table', '[bp - 2]': 'removed', '[0xc7b1]': 'count'},
}


def disassemble(image, start, end):
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    rows = []
    for ins in md.disasm(image[start:end], start - HEADER):
        rows.append((ins.address + HEADER, bytes(ins.bytes).hex(), ins.mnemonic, ins.op_str))
    return rows


def condense(rows, base, names):
    frame = {hex(base): 0, hex(base - 4): 1, hex(base + 4): -1, hex(base + 8): -2}
    targets = set()
    for _, _, mn, ops in rows:
        if mn.startswith('j') or mn == 'loop':
            if re.match(r'^0x[0-9a-f]+$', ops): targets.add(int(ops, 16) + HEADER)

    def rename(s):
        s = s.replace('word ptr ', '').replace('byte ptr ', '').replace('ptr ', '')
        for key, value in names.items(): s = s.replace(key, value)
        return s

    def char(v):
        v = int(v, 16)
        return repr(chr(v)) if 0x20 <= v < 0x7f else hex(v)

    out, i, current = [], 0, '?'
    while i < len(rows):
        off, _, mn, ops = rows[i]
        label = f'{off:05X}' + (':' if off in targets else ' ')
        if (mn == 'mov' and ops.startswith('bx, ') and i + 5 < len(rows)
                and rows[i+1][2:] == ('mov', 'cl, 2') and rows[i+2][2:] == ('shl', 'bx, cl')
                and rows[i+3][2] == 'lea' and rows[i+4][2:] == ('add', 'bx, ax')
                and rows[i+5][2:] == ('les', 'bx, ptr ss:[bx]')):
            key = rows[i+3][3].split('- ')[1].rstrip(']')
            if key in frame:
                k = frame[key]
                current = f'V[{rename(ops[4:])}{"+%d" % k if k > 0 else ("-%d" % -k if k < 0 else "")}]'
                out.append(f'{label} N={current}'); i += 6; continue
        if mn == 'les' and ops.startswith('bx, ptr [bp'):
            current = rename(ops[8:]); out.append(f'{label} N={current}'); i += 1; continue
        if mn == 'push' and ops == 'ss' and i + 5 < len(rows) and rows[i+4][2:] == ('lcall', '0x1313, 0xe'):
            out.append(f'{label} rebuild()'); i += 6; continue
        if mn == 'lcall':
            name = {'0, 0x3f90': 'strrchr', '0, 0x3d41': 'strcpy', '0, 0x3db0': 'stricmp', '0, 0x3cd4': 'strchr',
                    '0, 0x3e97': 'strncmp', '0, 0x3fd9': 'strstr', '0, 0x3d11': 'strcmp', '0, 0x3df1': 'strlen',
                    '0, 0x1951': 'calloc', '0, 0x1baa': 'free', '0x1313, 0xa67': 'match', '0x1313, 0x1b4': 'replace',
                    '0x1313, 0x12df': 'swap', '0x1313, 0xe': 'rebuild', '0x687, 0x812': 'new_boundary',
                    '0x211e, 0x117f': 'is_cyrillic', '0x12dc, 0x5': 'cleanup'}.get(ops, ops)
            out.append(f'{label} call {name}'); i += 1; continue
        s = rename(ops)
        s = re.sub(r'es:\[bx \+ (0x[0-9a-f]+|\d+)\]', lambda m: f'{current}.{int(m.group(1), 0):02X}', s)
        s = re.sub(r'es:\[bx\]', f'{current}.00', s)
        if mn in ('cmp', 'mov') and re.search(r', 0x[0-9a-f]+$', s) and ('.0C' in s or '.0F' in s or '.66' in s):
            s = re.sub(r', (0x[0-9a-f]+)$', lambda m: ', ' + char(m.group(1)), s)
        if mn.startswith('j') and re.match(r'^0x[0-9a-f]+$', ops):
            s = f'{int(ops, 16) + HEADER:05X}'
        out.append(f'{label} {mn} {s}')
        i += 1
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('start'); ap.add_argument('end')
    ap.add_argument('--image', default='LTGOLD/LTPRO.EXE')
    ap.add_argument('--segment', help='hex segment, printed as segment:offset beside each file offset')
    ap.add_argument('--frame', help='hex BP displacement of the lexical vector (842 for 0E1F:0009, 848 for T4, 822 for reorder)')
    ap.add_argument('--names', choices=sorted(NAMES), help='frame variable names to substitute')
    args = ap.parse_args()
    image = open(args.image, 'rb').read()
    rows = disassemble(image, int(args.start, 16), int(args.end, 16))
    if args.frame:
        for line in condense(rows, int(args.frame, 16), NAMES.get(args.names, {})): print(line)
    else:
        segment = int(args.segment, 16) if args.segment else None
        for off, hexbytes, mn, ops in rows:
            so = f'{segment:04X}:{off - HEADER - segment * 16:04X} ' if segment is not None else ''
            # Capstone reports near targets in load-image coordinates.
            if (mn.startswith('j') or mn in ('loop', 'call')) and re.match(r'^0x[0-9a-f]+$', ops):
                ops = f'{int(ops, 16) + HEADER:05X}'
            print(f'{off:05X} {so}{hexbytes:<16} {mn} {ops}')


if __name__ == '__main__': main()
