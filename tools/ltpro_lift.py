#!/usr/bin/env python3
"""Condense a Borland C large-model LTPRO function into readable pseudo-code.

This is a reading aid, not a decompiler: every line still corresponds to
specific instructions, whose file offset is printed. It recognizes the
compiler's idioms:

- `les bx, X` followed by `es:[bx+N]` operands prints as `X->N`; a chained
  `les bx, es:[bx+N]` prints as `X->N->M`.
- Pushes followed by a far/near call and stack cleanup print as one call with
  the arguments in source order (far pointers as `seg:off` pairs merged when
  pushed as two words).
- `cmp a, b` / `test a, b` / `or a, a` followed by a conditional jump print
  as `if (a OP b) goto L`, with signed/unsigned comparisons distinguished.
- Frame slots print as `arg6`, `arg8` (above BP) and `v2`, `v0E` (below BP);
  DS globals as `[DS:xxxx]`; library calls by name.

Only instructions reachable from the entry (following branches and switch
tables, as ltpro_callgraph.walk does) are printed, in address order, with a
label line before every branch target.

Example:
  python3 tools/ltpro_lift.py 151F:2740
"""
import argparse
import re
from capstone import Cs, CS_ARCH_X86, CS_MODE_16

from ltpro_callgraph import HEADER, LIBRARY, walk

KNOWN = {(0x1313, 0x000E): 'rebuild', (0x1313, 0x0A67): 'match', (0x1313, 0x01B4): 'replace',
         (0x1313, 0x12DF): 'swap', (0x0687, 0x0812): 'new_boundary', (0x211E, 0x117F): 'is_cyrillic',
         (0x211E, 0x115A): 'is_russian_115A', (0x211E, 0x113A): 'cyr_113A', (0x2104, 0x0002): 'ends_with',
         (0x1E71, 0x02AC): 'noun_form', (0x1E71, 0x0420): 'adjective_form', (0x1E71, 0x05FB): 'verb_form',
         (0x1E71, 0x0977): 'participle_form', (0x1C3D, 0x0135): 'cmatch', (0x1449, 0x0004): 'T7',
         (0x1FCD, 0x1031): 'rus_lookup', (0x1FCD, 0x007F): 'rus_search', (0x043A, 0x074D): 'rus_index_offset',
         (0x043A, 0x0850): 'rus_index_length', (0x0687, 0x0892): 'new_record'}
SIGNED = {'jl': '<', 'jle': '<=', 'jg': '>', 'jge': '>='}
UNSIGNED = {'jb': '<u', 'jbe': '<=u', 'ja': '>u', 'jae': '>=u'}
EQUAL = {'je': '==', 'jne': '!='}


def slot(text):
    def frame(m):
        size, sign, value = m.group(1), m.group(2), int(m.group(3), 16)
        prefix = 'b ' if size and size.startswith('byte') else ''
        return prefix + (f'arg{value:X}' if sign == '+' else f'v{value:02X}')
    text = re.sub(r'(word |byte |dword )?ptr ss:\[bp ([+-]) (0x[0-9a-f]+|\d+)\]', frame, text)
    text = re.sub(r'(word |byte |dword )?ptr \[bp ([+-]) (0x[0-9a-f]+|\d+)\]', frame, text)
    text = re.sub(r'(?:word |byte )?ptr \[(0x[0-9a-f]+)\]', lambda m: f'[DS:{int(m.group(1), 16):04X}]', text)
    text = text.replace('word ptr ', 'w ').replace('byte ptr ', 'b ').replace('dword ptr ', 'd ').replace('ptr ', '')
    return text


def lift(image, segment, offset):
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    instructions, _, switches = walk(image, md, segment, offset)
    rows = [instructions[a] for a in sorted(instructions)]
    base = HEADER + segment * 16
    targets = {t for _, _, _, ts, _ in switches for t in ts}
    cases = {}
    for at, _, _, ts, keys in switches:
        for n, t in enumerate(ts):
            key = n if keys is None else (repr(chr(keys[n])) if 0x20 <= keys[n] < 0x7f else hex(keys[n]))
            cases.setdefault(t, []).append(key)
    for ins in rows:
        if (ins.mnemonic.startswith('j') or ins.mnemonic == 'loop') and ins.op_str.startswith('0x'):
            targets.add(int(ins.op_str, 16))
    out, pending, es_name, i = [], [], None, 0

    def label(ins): return f'{base + ins.address:05X}'

    def emit(ins, text):
        out.append(f'{label(ins)}  {text}')

    while i < len(rows):
        ins = rows[i]
        mn, ops = ins.mnemonic, ins.op_str
        if ins.address in targets:
            es_name = None
            if pending:
                out.append('        ; pushes ' + ', '.join(pending)); pending = []
            out.append(f'{label(ins)}:' + (f'  case {cases[ins.address]}' if ins.address in cases else ''))
        # les bx, <pointer>: remember what ES:BX designates.
        if mn == 'les' and ops.startswith('bx, '):
            source = slot(ops[4:])
            if 'es:[bx' in ops and es_name:
                n = re.search(r'\[bx \+ (0x[0-9a-f]+|\d+)\]', ops)
                es_name = f'{es_name}->{int(n.group(1), 0):X}' if n else f'{es_name}->0'
            else:
                es_name = source
            # Make ES:BX explicit where it flows into a jump or a label.
            following = rows[i + 1] if i + 1 < len(rows) else None
            if following is not None and (following.mnemonic == 'jmp' or following.address in targets):
                emit(ins, f'es:bx = {es_name}')
            i += 1
            continue
        if mn == 'les' and ops.startswith('ax, ') and i + 1 < len(rows) and rows[i + 1].mnemonic == 'mov' \
                and rows[i + 1].op_str == 'dx, es':
            if pending and pending[-1] == 'es' and i + 2 < len(rows) and rows[i + 2].op_str == 'es' and rows[i + 2].mnemonic == 'pop':
                pending.pop(); emit(ins, f'dx:ax = &*{slot(ops[4:])}  (es kept)'); i += 3; continue
            emit(ins, f'dx:ax = {slot(ops[4:])}'); i += 2; continue
        if mn == 'push':
            pending.append(slot(ops) if ops not in ('cs',) else 'cs')
            i += 1
            continue
        if mn in ('lcall', 'call'):
            if mn == 'lcall' and ',' in ops:
                s, o = (int(x, 16) for x in ops.split(', '))
                name = LIBRARY.get(o, f'lib_{o:04X}') if s == 0 else KNOWN.get((s, o), f'f_{HEADER + s * 16 + o:05X}')
            elif mn == 'call' and ops.startswith('0x'):
                if pending and pending[-1] == 'cs': pending.pop()
                t = int(ops, 16)
                name = KNOWN.get((segment, t), f'near_{base + t:05X}')
            else:
                name = slot(ops)
            # Arguments: pushed last = first. Two consecutive words of one far
            # pointer arrive as "seg-word, off-word" in reverse.
            args = list(reversed(pending)); pending = []
            merged, j = [], 0
            while j < len(args):
                a = args[j]
                b = args[j + 1] if j + 1 < len(args) else None
                m1 = re.fullmatch(r'(.*?)(w )?(arg|v)([0-9A-F]+)', a) if a else None
                m2 = re.fullmatch(r'(.*?)(w )?(arg|v)([0-9A-F]+)', b) if b else None
                if m1 and m2 and m1.group(3) == m2.group(3) and m1.group(1) == m2.group(1):
                    lo, hi = int(m1.group(4), 16), int(m2.group(4), 16)
                    if (m1.group(3) == 'arg' and hi == lo + 2) or (m1.group(3) == 'v' and hi == lo - 2):
                        merged.append(f'{m1.group(1)}{m1.group(3)}{m1.group(4)}'); j += 2; continue
                if a == 'ds' and b and b.startswith('ax'):
                    merged.append('DS:ax'); j += 2; continue
                fm1 = re.fullmatch(r'w es:\[bx \+ (0x[0-9a-f]+)\]', a)
                fm2 = re.fullmatch(r'w es:\[bx \+ (0x[0-9a-f]+)\]', b) if b else None
                if fm1 and fm2 and int(fm2.group(1), 16) == int(fm1.group(1), 16) + 2:
                    merged.append(f'{es_name}->{int(fm1.group(1), 16):X}'); j += 2; continue
                merged.append(a.replace('es:[bx', f'{es_name}[') if es_name else a); j += 1
            emit(ins, f'call {name}({", ".join(merged)})')
            es_name = None
            i += 1
            # Skip caller cleanup.
            while i < len(rows) and (rows[i].mnemonic == 'pop' and rows[i].op_str == 'cx' or
                                     rows[i].mnemonic == 'add' and rows[i].op_str.startswith('sp,')):
                i += 1
            continue
        if pending:
            out.append('        ; pushes ' + ', '.join(pending)); pending = []
        text = slot(ops)
        if es_name:
            text = re.sub(r'es:\[bx \+ (0x[0-9a-f]+|\d+)\]', lambda m: f'{es_name}->{int(m.group(1), 0):X}', text)
            text = re.sub(r'es:\[bx\]', f'{es_name}->0', text)
            text = re.sub(r'es:\[bx - (0x[0-9a-f]+|\d+)\]', lambda m: f'{es_name}->-{int(m.group(1), 0):X}', text)
        # Comparisons fused with the following conditional jump.
        if mn in ('cmp', 'test', 'or') and i + 1 < len(rows) and rows[i + 1].mnemonic in {**SIGNED, **UNSIGNED, **EQUAL} \
                and rows[i + 1].address not in targets and (mn != 'or' or ops.split(', ')[0] == ops.split(', ')[1]):
            j = rows[i + 1]
            target = f'{base + int(j.op_str, 16):05X}'
            a, b = text.split(', ')
            if mn == 'test':
                cond = f'({a} & {b}) {"== 0" if j.mnemonic == "je" else "!= 0"}' if j.mnemonic in EQUAL else f'test {text} {j.mnemonic}'
            elif mn == 'or':
                cond = f'{a} {"== 0" if j.mnemonic == "je" else "!= 0"}' if j.mnemonic in EQUAL else f'{a} {j.mnemonic}'
            else:
                op = {**SIGNED, **UNSIGNED, **EQUAL}[j.mnemonic]
                try:
                    v = int(b, 0)
                    if 0x20 <= v < 0x7f and v not in (0x20,) and ('b ' in a or a.endswith('l')): b = f"'{chr(v)}'"
                except ValueError:
                    pass
                cond = f'{a} {op} {b}'
            emit(ins, f'if {cond} goto {target}')
            i += 2
            continue
        if (mn.startswith('j') or mn == 'loop') and ops.startswith('0x'):
            text = f'{base + int(ops, 16):05X}'
        if mn in ('mov', 'add', 'sub', 'and', 'or', 'xor', 'inc', 'dec', 'shl', 'shr', 'sar', 'not', 'neg') \
                and re.match(r'^(bx|es)\b', ops):
            es_name = None
        emit(ins, f'{mn} {text}')
        if mn in ('jmp', 'retf', 'ret'): es_name = None
        i += 1
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('entry', help='segment:offset in hex')
    ap.add_argument('--image', default='LTGOLD/LTPRO.EXE')
    args = ap.parse_args()
    image = open(args.image, 'rb').read()
    segment, offset = (int(x, 16) for x in args.entry.split(':'))
    for line in lift(image, segment, offset): print(line)


if __name__ == '__main__': main()
