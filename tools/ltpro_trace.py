#!/usr/bin/env python3
"""Capture native lexical/T1/T2 boundaries and T1 events from a disposable image.

The hook saves flags and every general/segment register, writes snapshots through
DOS INT 21h, then executes the displaced instructions. Original assets are never
edited. Captures are accepted only when translation bytes match the unmodified
oracle on two runs. Requires the already installed DOSBox-X; no assembler needed.
"""
import argparse
import json
import os
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

from ltpro_capture import CONFIG, ENVIRONMENT, FILES, FLAGS, digest

EXE_SHA256 = '6a2036c2fbc629d0317bf02acbb1e6ebd82ceecb2d11f609c6460cc0c32dc4fe'
# Beyond the original image plus its minimum allocation (0x2F802). Keep the
# addition small: the DOS dictionary loader needs most of conventional memory.
HOOK_SEGMENT = 0x3100
NODE_SIZE = 0x282
SITES = [
    (1, 'lexical', 0x11C1B, bytes.fromhex('a3b1c7bf0100')),
    (2, 'T1', 0x1254A, bytes.fromhex('8c5ef4c746f21c0e')),
    (3, 'T2', 0x13700, bytes.fromhex('8c5ef0c746ee4814')),
    (4, 'T1-match', 0x11D5F, bytes.fromhex('8946d2b90f00')),
    # T3 shares the T1/T2 frame and returns at 14177 through a relative jump, so
    # its boundary is the rule-record test, which is also the loop's entry jump
    # target; the hook dumps only once the record is null, i.e. after the final
    # T3 rule and its rebuild. 14164 is unusable: 14168 is a jump target.
    (5, 'T3', 0x14168, bytes.fromhex('c45eee268b07')),
]
CONDITIONAL = {5}


class Code:
    """Only byte emission and label fixups; opcode semantics stay reviewable."""
    def __init__(self):
        self.data = bytearray()
        self.labels = {}
        self.fixups = []

    def emit(self, hex_bytes): self.data.extend(bytes.fromhex(hex_bytes))
    def word(self, value): self.data.extend(struct.pack('<H', value))
    def label(self, name): self.labels[name] = len(self.data)
    def address(self, name):
        self.fixups.append((len(self.data), name, False)); self.word(0)
    def near(self, opcode, name):
        self.emit(opcode); self.fixups.append((len(self.data), name, True)); self.word(0)
    def finish(self):
        for at, name, relative in self.fixups:
            value = self.labels[name] - (at + 2 if relative else 0)
            struct.pack_into('<H', self.data, at, value & 0xffff)
        return self.data


def instrument(original):
    if digest(original) != EXE_SHA256: raise ValueError('unsupported executable identity')
    header = struct.unpack_from('<H', original, 8)[0] * 16
    count, table = struct.unpack_from('<H', original, 6)[0], struct.unpack_from('<H', original, 24)[0]
    # The original relocation table fills its header exactly. Grow the header by
    # one paragraph for the hook relocations; load addresses are header-relative,
    # so only file offsets shift. Hook sites below stay original file offsets.
    shift = 16
    image = bytearray(original[:header] + bytes(shift) + original[header:])
    struct.pack_into('<H', image, 8, header // 16 + 1)
    header += shift
    if table + (count + len(SITES)) * 4 > header: raise ValueError('no relocation header space')
    code = Code()
    entries = []
    for stage, name, site, displaced in SITES:
        if original[site:site+len(displaced)] != displaced: raise ValueError(f'changed hook site {name}')
        entries.append(len(code.data))
        code.data.extend(displaced)
        # PUSHF; save AX BX CX DX SI DI BP DS ES. BP remains the native frame.
        code.emit('9c 50 53 51 52 56 57 55 1e 06')
        if stage in CONDITIONAL:
            # ES:BX holds the next rule record from the displaced LES; skip the
            # dump unless its pattern pointer is null (table exhausted).
            code.emit('268b07 260b4702'); code.near('0f85', f'restore{stage}')
        # Record the selected native rule before its handler executes. Other
        # boundaries zero these words instead of inheriting a previous event.
        for displacement,label in [(0xD2,'handler'),(0xF6,'rule_offset'),(0xF8,'rule_segment'),(0xFA,'last')]:
            if stage==4: code.emit(f'8b46{displacement:02x}')
            else: code.emit('31c0')
            code.emit('2ea3'); code.address(label)
        code.emit('b8'); code.word(stage)
        code.emit('8b0eb1c7 16 07 8db6bef7')  # CX=count; ES=SS; SI=BP-842h
        code.near('e8', 'dump')
        code.label(f'restore{stage}')
        code.emit('07 1f 5d 5f 5e 5a 59 5b 58 9d cb')
    code.label('dump')
    # Header: magic, stage, count, DS, SS, selector, rule pointer and endpoint.
    for opcode, label in [('2ea3','stage'), ('2e890e','count'), ('2e8c1e','ds'), ('2e8c16','ss')]:
        code.emit(opcode); code.address(label)
    code.emit('0e 1f ba'); code.address('filename')
    code.emit('b8023d cd21 7309 31c9 b43c cd21') # open existing or create
    code.near('e9', 'opened')
    code.label('opened')
    code.emit('7303'); code.near('e9', 'error')
    code.emit('8bf8 8bd8 31c9 31d2 b80242 cd21') # DI=handle; seek end
    code.emit('7303'); code.near('e9', 'error')
    code.emit('ba'); code.address('header'); code.emit('b91400')
    code.near('e8', 'write')
    # Vector, including its null terminator, from ES:SI.
    code.emit('06 1f 8bd6 2e8b0e'); code.address('count')
    code.emit('41 d1e1 d1e1'); code.near('e8', 'write')
    # Cached tags (count + terminating NUL) from original DS:C5AE.
    code.emit('2e8e1e'); code.address('ds')
    code.emit('baaec5 2e8b0e'); code.address('count')
    code.emit('41'); code.near('e8', 'write')
    code.emit('2e8b2e'); code.address('count')
    code.label('nodes')
    code.emit('85ed 7503'); code.near('e9', 'close')
    code.emit('268b14 268b4402 8ed8 b9'); code.word(NODE_SIZE)
    code.near('e8', 'write')
    code.emit('83c604 4d'); code.near('e9', 'nodes')
    code.label('close')
    code.emit('8bdf b43e cd21 7303'); code.near('e9','error')
    code.emit('c3')
    code.label('write')
    code.emit('8bdf b440 cd21 7303'); code.near('e9','error')
    code.emit('3bc1 7403'); code.near('e9','error')
    code.emit('c3')
    code.label('error'); code.emit('b8424c cd21')
    code.label('filename'); code.data.extend(b'TRACE.BIN\0')
    code.label('header'); code.data.extend(b'LTTR')
    for name in ('stage','count','ds','ss','handler','rule_offset','rule_segment','last'):
        code.label(name); code.word(0)
    payload = code.finish()
    image.extend(b'\0' * (header + HOOK_SEGMENT * 16 - len(image)))
    image.extend(payload)
    # The C startup (03A81..03AA1) shrinks its DOS allocation to SS+stack size,
    # ignoring the new MZ image length. Move the stack above the hook so startup
    # cannot release the hook's memory to dictionary/node allocations.
    struct.pack_into('<H', image, 14, HOOK_SEGMENT+(len(payload)+15)//16)
    for index, ((_, _, site, displaced), entry) in enumerate(zip(SITES, entries)):
        site += shift
        image[site:site+len(displaced)] = b'\x9a' + struct.pack('<HH', entry, HOOK_SEGMENT) + b'\x90'*(len(displaced)-5)
        # Relocation addresses are module coordinates; normalize their segment:offset.
        relocation = site + 3 - header
        struct.pack_into('<HH', image, table+(count+index)*4, relocation % 16, relocation // 16)
    struct.pack_into('<H', image, 6, count+len(SITES))
    struct.pack_into('<HH', image, 2, len(image)%512, (len(image)+511)//512)
    return bytes(image)


def decode_trace(raw):
    snapshots = []; pos = 0; identities = {}
    while pos < len(raw):
        if raw[pos:pos+4] != b'LTTR': raise ValueError(f'invalid trace magic at {pos}')
        stage,count,ds,ss,handler,rule_offset,rule_segment,last = struct.unpack_from('<8H',raw,pos+4); pos += 20
        if stage not in (1,2,3,4,5) or not 0 < count <= 512: raise ValueError('invalid trace header')
        vector = [struct.unpack_from('<HH',raw,pos+i*4) for i in range(count+1)]
        pos += (count+1)*4
        if vector[-1] != (0,0): raise ValueError('unterminated vector')
        cache = raw[pos:pos+count+1]; pos += count+1
        if not cache or cache[-1] != 0: raise ValueError('unterminated tag cache')
        # Normalize pointers by physical address, preserving aliases. Raw bytes stay
        # available: unnamed fields and uninitialized padding are not discarded.
        addresses = [segment*16+offset for offset,segment in vector[:-1]]
        for address in addresses:
            if address not in identities: identities[address] = len(identities)+1
        nodes = []
        for index,(offset,segment) in enumerate(vector[:-1]):
            record = raw[pos:pos+NODE_SIZE]; pos += NODE_SIZE
            if len(record) != NODE_SIZE: raise ValueError('truncated node')
            def text(at):
                stop = record.find(b'\0',at)
                if stop < 0: raise ValueError(f'unterminated node field {at:x}')
                return record[at:stop].decode('cp866')
            next_offset,next_segment = struct.unpack_from('<HH',record)
            next_address = next_segment*16+next_offset
            nodes.append({'id': identities[addresses[index]], 'pointer': [offset,segment],
                'next': identities.get(next_address) if next_address else None,
                'next_pointer': [next_offset,next_segment], 'tag': chr(record[0x0c]),
                'previous_tag': record[0x66], 'source': text(0x12),
                'lexical': text(0x9c), 'translation': text(0x11c),
                'raw_hex': record.hex()})
        snapshot={'stage': SITES[stage-1][1], 'native_ds':ds, 'native_ss':ss,
                  'cache': cache[:-1].decode('ascii'), 'nodes': nodes}
        if stage==4:
            if rule_segment!=ds or (rule_offset-0xC3C)%10 or not 0<=rule_offset-0xC3C<470:
                raise ValueError('invalid selected native rule')
            snapshot.update(rule=(rule_offset-0xC3C)//10+1,handler=handler,last=last)
        snapshots.append(snapshot)
    return snapshots


def semantic(snapshot):
    # Known pointers vary when the disposable image moves the native heap. Do not
    # compare uninitialized record padding as semantic state; preserve it above.
    return {'stage':snapshot['stage'], 'cache':snapshot['cache'],
        'rule':snapshot.get('rule'),'handler':snapshot.get('handler'),'last':snapshot.get('last'),'nodes':[
        {key:node[key] for key in ('id','next','tag','previous_tag','source','lexical','translation')}
        for node in snapshot['nodes']]}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--reference',type=Path,default=Path('test/ltpro/reference.json'))
    ap.add_argument('--data',type=Path,default=Path('LTGOLD'))
    ap.add_argument('--output',type=Path,default=Path('test/ltpro/stages.json'))
    ap.add_argument('--ids',nargs='*',default=['case-002','case-052'])
    ap.add_argument('--timeout',type=float,default=30)
    ap.add_argument('--resume',action='store_true',help='resume an identical capture manifest')
    args = ap.parse_args()
    reference = json.loads(args.reference.read_text())
    assets = {name:(args.data/name).read_bytes() for name in FILES}
    for name,data in assets.items():
        if digest(data) != reference['assets_sha256'][name]: ap.error(f'changed reference asset {name}')
    patched = instrument(assets['LTPRO.EXE'])
    cases = [c for c in reference['cases'] if not args.ids or c['id'] in args.ids]
    if args.ids and {c['id'] for c in cases} != set(args.ids): ap.error('unknown case ID')
    results=[]
    if args.resume and args.output.exists():
        previous=json.loads(args.output.read_text())
        if previous['reference_sha256']!=digest(args.reference.read_bytes()) or previous['instrumented_sha256']!=digest(patched):
            ap.error('resume provenance differs')
        lookup={case['id']:case for case in cases}
        for case in previous['cases']:
            expected=lookup.get(case['id'])
            if not expected or case['input']!=expected['input'] or case['output_sha256']!=expected['raw_sha256']:
                ap.error('resume cases differ')
        results.extend(previous['cases'])
    manifest={'schema':1,'reference_sha256':digest(args.reference.read_bytes()),
        'executable_sha256':EXE_SHA256,'instrumented_sha256':digest(patched),
        'identical_runs':2,'node_dump_bytes':NODE_SIZE,'complete':False,
        'requested_cases':len(cases),
        'hooks':[{'stage':name,'file_offset':site,'displaced_hex':data.hex()} for _,name,site,data in SITES],
        'cases':results}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    def save():
        temporary=args.output.with_suffix(args.output.suffix+'.tmp')
        temporary.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
        temporary.replace(args.output)
    for case in cases:
        if any(done['id']==case['id'] for done in results): continue
        repetitions=[]
        for run in range(2):
            root=Path(tempfile.mkdtemp(prefix='ltpro-trace-'))
            try:
                for name,data in assets.items(): (root/name).write_bytes(data)
                (root/'LTPRO.EXE').write_bytes(patched)
                (root/'INPUT.TXT').write_bytes(case['input'].encode('cp866')+b'\r\n')
                (root/'RUN.BAT').write_bytes(('@echo off\r\nLTPRO /I INPUT.TXT /O OUTPUT.TXT '+' '.join(FLAGS)+'\r\necho COMPLETE>DONE.TXT\r\nexit\r\n').encode('ascii'))
                (root/'dosbox.conf').write_text(CONFIG.format(mount=root))
                with (root/'host.log').open('wb') as log:
                    process=subprocess.run(['dosbox-x','-conf',str(root/'dosbox.conf'),'-silent','-nogui'],
                        cwd=root,env=dict(os.environ,**ENVIRONMENT),stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout)
                if process.returncode or not (root/'DONE.TXT').exists(): raise RuntimeError('DOSBox did not complete')
                output=(root/'OUTPUT.TXT').read_bytes()
                if digest(output)!=case['raw_sha256']: raise RuntimeError('instrumentation changed output')
                for name,data in assets.items():
                    expected=patched if name=='LTPRO.EXE' else data
                    if (root/name).read_bytes()!=expected: raise RuntimeError(f'trace mutated {name}')
                raw=(root/'TRACE.BIN').read_bytes() if (root/'TRACE.BIN').exists() else b''
                snapshots=decode_trace(raw)
                sequence = [s['stage'] for s in snapshots]
                while sequence:
                    if sequence[0]!='lexical': raise RuntimeError('unexpected stage sequence')
                    sequence=sequence[1:]
                    while sequence and sequence[0]=='T1-match': sequence=sequence[1:]
                    if sequence[:2]==['T1','T2']: sequence=sequence[2:]
                    # T3 may be absent when the shared function returns early.
                    if sequence[:1]==['T3']: sequence=sequence[1:]
                repetitions.append(snapshots)
            except Exception:
                log_path=root/'host.log'
                if log_path.exists() and log_path.stat().st_size>256*1024:
                    with log_path.open('rb') as log:
                        log.seek(-128*1024,2);tail=log.read()
                    log_path.write_bytes(b'[Earlier emulator log truncated]\n'+tail)
                print(f'Trace failed; diagnostics retained at {root}',flush=True); raise
            shutil.rmtree(root)
        if list(map(semantic,repetitions[0])) != list(map(semantic,repetitions[1])):
            raise RuntimeError(f'non-reproducible stage semantics: {case["id"]}')
        results.append({'id':case['id'],'input':case['input'],'output_sha256':case['raw_sha256'],
                        'grammar_entered':bool(repetitions[0]),'snapshots':repetitions[0]})
        save()
        print(f'{case["id"]}: {len(repetitions[0])} native boundaries; output unchanged on both runs',flush=True)
    manifest['complete']=True
    save()


if __name__=='__main__': main()
