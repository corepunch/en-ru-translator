#!/usr/bin/env python3
"""Exercise native T2 control flow on generated nodes and compare Lua stage state.

DOS snapshots remain the independent complete-program check. These fixtures give
local branch evidence for every T2 selector body; they do not prove English-input
reachability. The T1 table is emptied so only T1 normalization precedes T2, and
only C-library primitives are substituted.
"""
import argparse
import collections
import random
import struct
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import Machine,lua_value
from ltpro_matcher_probe import representative

T1_TABLE,T2_TABLE,T2_COUNT=0x2738C,0x2756C,157
FIELDS=(0x0B,0x0F,0x66,0x68,0x6A,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B)
STRINGS=(0x12,0x9C,0x11C,0x243)

def rule(image,index,selector=None):
    at=T2_TABLE+index*10
    def string(pointer):
        off,seg=struct.unpack_from('<HH',image,pointer)
        if not off and not seg: return None
        address=0x3A00+seg*16+off
        return image[address:image.index(0,address)].decode('cp866')
    handler=struct.unpack_from('<H',image,at+8)[0] if selector is None else selector
    return [handler,string(at),string(at+4)]

def native(image,case,cache):
    image=bytearray(image)
    image[T1_TABLE:T1_TABLE+10]=bytes(10)
    if 'rule' in case:
        at=T2_TABLE+(case['rule']-1)*10
        image[T2_TABLE:T2_TABLE+10]=image[at:at+10]
        if 'selector' in case:struct.pack_into('<H',image,T2_TABLE+8,case['selector'])
        image[T2_TABLE+10:T2_TABLE+14]=bytes(4)
    machine=Machine(image);machine.cache=cache;machine.r.update(cs=0xE1F,ip=9)
    machine.write(machine.reg('ds')*16+0x44D,2,512)
    records=case['nodes'];addresses=[0x80000+i*0x400 for i in range(len(records))]
    machine.write(0x70000,4,(0x8000<<16))
    def pointer(address): return ((address>>4)<<16)|(address&15)
    for index,record in enumerate(records):
        address=addresses[index]
        machine.write(address,4,pointer(addresses[index+1]) if index+1<len(records) else 0)
        machine.write(address+12,1,record['12'])
        for at in FIELDS:machine.write(address+at,1,record.get(str(at),0))
        for at in STRINGS:
            value=record.get(str(at),'').encode('cp866')+b'\0'
            machine.mem[address+at:address+at+len(value)]=value
        # The native +98 pointer addresses the record's own +11C translation.
        machine.write(address+0x98,4,pointer(address+0x11C))
    def record(address):
        following=machine.read(address,4)
        return {'pointer':[address&15,address>>4],
                'next_pointer':[following&65535,following>>16],
                'raw_hex':machine.mem[address:address+0x282].hex()}
    before=[record(address) for address in addresses]
    machine.before_instruction=lambda m:(m.reg('cs'),m.reg('ip'))==(0xE1F,0x1B10)
    for value in reversed([0,0x7000,0x2E]):machine.push(value)
    machine.push(0xFFFF);machine.push(0xFFFF)
    machine.run()
    assert (machine.reg('cs'),machine.reg('ip'))==(0xE1F,0x1B10),'native T2 did not reach the T3 boundary'
    count=machine.read(machine.reg('ds')*16+0xC7B1,2)
    vector=machine.reg('ss')*16+machine.reg('bp')-0x842
    after=[]
    for i in range(count):
        ptr=machine.read(vector+i*4,4)
        if not ptr:break  # DS:C7B1 can exceed the rebuilt vector; keep the live records only
        after.append(record((ptr>>16)*16+(ptr&65535)))
    tags=machine.cstring(machine.reg('ds')*16+0xC5AE).decode('ascii')
    return {'id':case['id'],'before':before,'after':after,'cache':tags,'count':count,
            'rules':case.get('rules'),'normalize':True,'steps':machine.steps}

def randomize(rng,nodes):
    for node in nodes:
        if node['12'] in (0x2A,0x23):continue
        node['11']=rng.choice([0,1,3])
        node['15']=rng.choice([0,0,0x2F,0x77,0x6E,0x67])
        node['102']=rng.choice([0,ord('V'),ord('G'),ord('N'),ord('E')])
        node['104']=rng.choice([0,0x80,0xC1])
        node['106']=rng.choice([0,0,1,3,0x41,0xC3])
        for at in range(0x72,0x7C):node[str(at)]=rng.randrange(4)
        if node['18']=='word':node['18']=rng.choice(['word','be','been','do','Did','xyz'])
        if node['284']=='translation':node['284']=rng.choice(['translation','Aadj','Nnoun','ANboth','q'])

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--full-table',type=int,default=24,help='cases run against the complete T2 table')
    ap.add_argument('--variants',type=int,default=4)
    args=ap.parse_args()
    image=Path('LTGOLD/LTPRO.EXE').read_bytes();cases=[];rng=random.Random(1993)
    patterns=[rule(image,index)[1] for index in range(T2_COUNT)]
    # Isolate every original table record so no earlier rule masks its handler.
    for index in range(T2_COUNT):
        for width in (0,1,3):
            for variant in range(args.variants):
                base=representative(patterns[index],width)
                randomize(rng,base['nodes'])
                cases.append({'id':f'isolated-T2-{index+1}-{width}-{variant}','nodes':base['nodes'],
                    'rule':index+1,'rules':[rule(image,index)]})
    # Selectors 4, 34, 36, 37, 39, 40, 46 and 55 share the default; records using
    # them are covered above. No supplied record selects 17 or 53; synthetic
    # table selection checks their original instructions without claiming
    # English-input reachability.
    for selector in (17,53):
        for index in (13,16):
            for width in (0,1,3):
                base=representative(patterns[index],width)
                randomize(rng,base['nodes'])
                cases.append({'id':f'synthetic-T2-{index+1}-{selector}-{width}','nodes':base['nodes'],
                    'rule':index+1,'selector':selector,'rules':[rule(image,index,selector)]})
    # Full-table runs exercise rule interaction and the stale DS:C7B1 count
    # after a handler's own rebuild.
    full=rng.sample(range(T2_COUNT),min(args.full_table,T2_COUNT))
    for index in full:
        base=representative(patterns[index],1)
        randomize(rng,base['nodes'])
        cases.append({'id':f'T2-{index+1}','nodes':base['nodes']})
    accepted=[];coverage=collections.Counter();cache={};steps=0
    for case in cases:
        result=native(image,case,cache)
        steps+=result.pop('steps')
        if 'rule' in case:coverage[case['rules'][0][0]]+=1
        accepted.append(result)
    with tempfile.TemporaryDirectory(prefix='ltpro-native-second-pass-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(accepted))
        result=subprocess.run(['lua','tools/ltpro_stage_probe.lua',str(path)])
    print(f'T2 isolated selectors: {dict(sorted(coverage.items()))}; {steps} native instructions')
    raise SystemExit(result.returncode)

if __name__=='__main__':main()
