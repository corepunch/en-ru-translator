#!/usr/bin/env python3
"""Exercise native T1 control flow on generated nodes and compare Lua stage state.

DOS snapshots remain the independent complete-program check. These fixtures give
additional local branch evidence; they do not prove English-input reachability.
Only C-library primitives are substituted; native boundary construction runs.
"""
import argparse
import collections
import random
import struct
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import Machine,lua_value
from ltpro_matcher_probe import representative,fixture

def native(image,case,cache):
    if 'rule' in case:
        image=bytearray(image)
        at=0x2738C+(case['rule']-1)*10
        image[0x2738C:0x27396]=image[at:at+10]
        if 'selector' in case:struct.pack_into('<H',image,0x27394,case['selector'])
        image[0x27396:0x2739A]=bytes(4)
    machine=Machine(image);machine.cache=cache;machine.r.update(cs=0xE1F,ip=9)
    machine.calloc_failure=case.get('allocation_failure',False)
    machine.write(machine.reg('ds')*16+0x44D,2,case.get('boundary_limit',512))
    records=case['nodes'];addresses=[0x80000+i*0x400 for i in range(len(records))]
    machine.write(0x70000,4,(0x8000<<16))
    def pointer(address): return ((address>>4)<<16)|(address&15)
    for index,record in enumerate(records):
        address=addresses[index]
        machine.write(address,4,pointer(addresses[index+1]) if index+1<len(records) else 0)
        machine.write(address+12,1,record['12'])
        for at in (0x0F,0x66,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B):
            machine.write(address+at,1,record.get(str(at),0))
        for at in (0x12,0x9C,0x11C):
            value=record.get(str(at),'').encode('cp866')+b'\0'
            machine.mem[address+at:address+at+len(value)]=value
    def record(address):
        following=machine.read(address,4)
        return {'pointer':[address&15,address>>4],
                'next_pointer':[following&65535,following>>16],
                'raw_hex':machine.mem[address:address+0x282].hex()}
    before=[record(address) for address in addresses]
    events=[]
    def snapshot():
        count=machine.read(machine.reg('ds')*16+0xC7B1,2)
        vector=machine.reg('ss')*16+machine.reg('bp')-0x842
        output=[]
        for i in range(count):
            ptr=machine.read(vector+i*4,4);output.append(record((ptr>>16)*16+(ptr&65535)))
        return machine.cstring(machine.reg('ds')*16+0xC5AE).decode('ascii'),output
    def observer(m):
        if (m.reg('cs'),m.reg('ip'))==(0xE1F,0x16F):
            frame=m.reg('ss')*16+m.reg('bp')
            selector=m.reg('ax')
            rule=(m.read(frame-0xA,2)-0xC3C)//10+1
            tags,output=snapshot()
            events.append({'stage':'T1-match','rule':rule,'handler':selector,
                'last':m.read(frame-6,2),'cache':tags,'nodes':output})
        return (m.reg('cs'),m.reg('ip'))==(0xE1F,0x95A)
    machine.before_instruction=observer
    for value in reversed([0,0x7000,case['terminator']]):machine.push(value)
    machine.push(0xFFFF);machine.push(0xFFFF)
    machine.run()
    early=(machine.reg('cs'),machine.reg('ip'))==(0xFFFF,0xFFFF)
    if early:
        # T1 early exits do not add/remove nodes in the implemented selectors.
        tags=machine.cstring(machine.reg('ds')*16+0xC5AE).decode('ascii')
        after=[record(address) for address in addresses]
    else:tags,after=snapshot()
    return {'id':case['id'],'before':before,'after':after,'cache':tags,
            'early_exit':int(early),'terminator':case['terminator'],'events':events,
            'allocations':machine.allocations,'rules':case.get('rules'),
            'boundary_limit':case.get('boundary_limit'),
            'allocation_failure':machine.calloc_failure},events

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--isolated-only',action='store_true')
    args=ap.parse_args()
    image=Path('LTGOLD/LTPRO.EXE').read_bytes();cases=[];rng=random.Random(1993)
    for index in range(47):
        at=0x2738C+index*10;off,seg=struct.unpack_from('<HH',image,at)
        address=0x3A00+seg*16+off
        pattern=image[address:image.index(0,address)].decode('cp866')
        for width in (0,1,3):
            base=representative(pattern,width)
            for variant in range(4):
                nodes=[dict(node) for node in base['nodes']]
                for node in nodes:
                    for field in (0x0F,0x66,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B):
                        node[str(field)]=rng.choice([0,1,3,0x77]) if field==0x0F else rng.randrange(4)
                cases.append({'id':f'T1-{index+1}-{width}-{variant}','nodes':nodes,
                    'terminator':rng.choice([0x2E,0x0A])})
    for index,tags in enumerate(['[N]','<V>','?N','JDNRV','NZNV','SZ','TZ','EG','Z','G,','TXV','XZ']):
        base=fixture('N',tags)
        cases.append({'id':f'normalization-{index}','nodes':base['nodes'],'terminator':0x2E})
    if args.isolated_only:cases=[]
    # Isolate original table records when earlier rules would mask their handlers.
    # Only table selection is narrowed; dispatcher and handler code stay original.
    for index,selector in ((10,None),(13,None),(16,None),(22,None),(37,None),(16,8)):
        at=0x2738C+index*10;off,seg=struct.unpack_from('<HH',image,at)
        address=0x3A00+seg*16+off
        pattern=image[address:image.index(0,address)].decode('cp866')
        off,seg=struct.unpack_from('<HH',image,at+4);address=0x3A00+seg*16+off
        action=image[address:image.index(0,address)].decode('cp866') if off or seg else None
        handler=struct.unpack_from('<H',image,at+8)[0]
        if selector is not None:handler=selector
        for width in (0,1,3):
            for variant in range(4):
                base=representative(pattern,width)
                for node in base['nodes']:
                    for field in (0x72,0x73,0x74):node[str(field)]=rng.randrange(4)
                cases.append({'id':f'isolated-T1-{index+1}-{handler}-{width}-{variant}',
                    'nodes':base['nodes'],'terminator':0x2E,'rule':index+1,
                    'rules':[[handler,pattern,action]],'boundary_limit':0 if variant==3 else 512,
                    'allocation_failure':variant==2})
                if selector is not None:cases[-1]['selector']=selector
    # Selector 8 has no record in the supplied table. A synthetic table selection
    # checks its original instructions but makes no English-reachability claim.
    accepted=[];coverage=collections.Counter();cache={}
    for case in cases:
        result,events=native(image,case,{} if 'rule' in case else cache)
        coverage.update(event['handler'] for event in events)
        accepted.append(result)
    with tempfile.TemporaryDirectory(prefix='ltpro-native-first-pass-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(accepted))
        result=subprocess.run(['lua','tools/ltpro_first_pass_probe.lua',str(path)])
    print(f'T1 generated-node coverage: {dict(sorted(coverage.items()))}')
    raise SystemExit(result.returncode)

if __name__=='__main__':main()
