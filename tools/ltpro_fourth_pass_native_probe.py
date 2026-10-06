#!/usr/bin/env python3
"""Exercise the native T4 function on generated nodes and compare Lua stage state.

DOS snapshots remain the independent complete-program check. These fixtures give
local branch evidence for T4's pre-passes, every selector body and the per-word
sub-rule handlers; they do not prove English-input reachability. 108F:000F is
entered directly with a linked record list, and only C-library primitives are
substituted. Sub-rules come from the actual `word pattern*$action` records.
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

T4_TABLE,T4_COUNT,RULE_SIZE=0x2952C,178,0x14F
FIELDS=(0x0B,0x0F,0x66,0x68,0x6A,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B)
STRINGS=(0x12,0x9C,0x11C,0x243)

def rule(image,index,selector=None):
    at=T4_TABLE+index*9
    def string(pointer):
        off,seg=struct.unpack_from('<HH',image,pointer)
        if not off and not seg: return None
        address=0x3A00+seg*16+off
        return image[address:image.index(0,address)].decode('cp866')
    handler=image[at+8] if selector is None else selector
    return [handler,string(at),string(at+4)]

def sub_rules(dictionary):
    found=[]
    for line in dictionary.split(b'\n'):
        line=line.rstrip(b'\r')
        star=line.rfind(b'*')
        if star<0 or line[star+1:star+2]!=b'$': continue
        space=line.find(b' ')
        if space<0 or space>star: continue
        found.append((line[:space].decode('cp866'),line[space+1:star].decode('cp866'),line[star+2:].decode('cp866')))
    return found

def native(image,case,cache):
    image=bytearray(image)
    if case.get('rule') is not None:
        index=case['rule']
        if index==0: image[T4_TABLE:T4_TABLE+9]=bytes(9)
        else:
            at=T4_TABLE+(index-1)*9
            image[T4_TABLE:T4_TABLE+9]=image[at:at+9]
            if 'selector' in case:image[T4_TABLE+8]=case['selector']
            image[T4_TABLE+9:T4_TABLE+13]=bytes(4)
    machine=Machine(image);machine.cache=cache;machine.r.update(cs=0x108F,ip=0xF)
    machine.write(machine.reg('ds')*16+0x44D,2,512)
    records=case['nodes'];addresses=[0x80000+i*0x400 for i in range(len(records))]
    machine.write(0x70000,4,(0x8000<<16))
    def pointer(address): return ((address>>4)<<16)|(address&15)
    rule_area=0xC0000
    for index,record in enumerate(records):
        address=addresses[index]
        machine.write(address,4,pointer(addresses[index+1]) if index+1<len(records) else 0)
        machine.write(address+12,1,record['12'])
        machine.write(address+0x0E,1,0x44 if record['12'] in (0x2A,0x23) else 0x57)
        for at in FIELDS:machine.write(address+at,1,record.get(str(at),0))
        for at in STRINGS:
            value=record.get(str(at),'').encode('cp866')+b'\0'
            machine.mem[address+at:address+at+len(value)]=value
        machine.write(address+0x98,4,pointer(address+0x11C))
        if record.get('aux') is not None:machine.write(address+0x62,4,pointer(addresses[record['aux']]))
        if record.get('rules'):
            machine.write(address+0x93,1,len(record['rules']))
            machine.write(address+0x94,4,pointer(rule_area))
            for entry in record['rules']:
                for at,text in ((0,entry['pattern']),(0x50,entry['action'])):
                    value=text.encode('cp866')+b'\0'
                    machine.mem[rule_area+at:rule_area+at+len(value)]=value
                rule_area+=RULE_SIZE
    def record(address):
        following=machine.read(address,4)
        return {'pointer':[address&15,address>>4],
                'next_pointer':[following&65535,following>>16],
                'raw_hex':machine.mem[address:address+0x282].hex()}
    before=[]
    for index,address in enumerate(addresses):
        entry=record(address)
        if records[index].get('rules'):entry['rules']=records[index]['rules']
        before.append(entry)
    state={}
    def observer(m):
        if (m.reg('cs'),m.reg('ip'))==(0x108F,0x1D99):
            count=m.read(m.reg('ds')*16+0xC7B1,2)
            vector=m.reg('ss')*16+m.reg('bp')-0x848
            after=[]
            for i in range(count):
                ptr=m.read(vector+i*4,4)
                if not ptr:break
                after.append(record((ptr>>16)*16+(ptr&65535)))
            state.update(count=count,after=after,cache=m.cstring(m.reg('ds')*16+0xC5AE).decode('ascii'))
            return True
        return False
    machine.before_instruction=observer
    for value in reversed([0,0x7000,0x2E]):machine.push(value)
    machine.push(0xFFFF);machine.push(0xFFFF)
    machine.run()
    assert state,'native T4 did not reach its epilogue'
    return {'id':case['id'],'before':before,'after':state['after'],'cache':state['cache'],
            'count':state['count'],'rules':case.get('rules'),'stage':'T4','steps':machine.steps,
            'allocations':machine.allocations}

def randomize(rng,nodes):
    for index,node in enumerate(nodes):
        if node['12'] in (0x2A,0x23):continue
        node['11']=rng.choice([0,1,3])
        node['15']=rng.choice([0,0,0,0x2F,0x77,0x6E,0x67,0x3D,0x25,0x57])
        node['102']=rng.choice([0,ord('V'),ord('G'),ord('N'),ord('E')])
        node['104']=rng.choice([0,1,2,0x41,0xC2])
        node['106']=rng.choice([0,0,1,3,0x41,0xC3])
        for at in range(0x72,0x7C):node[str(at)]=rng.randrange(4)
        if node['18']=='word':node['18']=rng.choice(['word','of','year','Year','in','xyz'])
        if node['284']=='translation':
            node['284']=rng.choice(['translation','Aadj','Nnoun','ANboth','q','-','A.x','слово','словоA','PРв'])
        if index>1 and rng.random()<0.2:node['aux']=index-1

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--variants',type=int,default=2)
    ap.add_argument('--full-table',type=int,default=8,help='sub-rule cases also run against the complete T4 table')
    args=ap.parse_args()
    image=Path('LTGOLD/LTPRO.EXE').read_bytes();cases=[];rng=random.Random(1993)
    patterns=[rule(image,index)[1] for index in range(T4_COUNT)]
    # Isolate every original 9-byte record so no earlier rule masks its handler.
    for index in range(T4_COUNT):
        for width in (0,1,3):
            for variant in range(args.variants):
                base=representative(patterns[index],width)
                randomize(rng,base['nodes'])
                cases.append({'id':f'isolated-T4-{index+1}-{width}-{variant}','nodes':base['nodes'],
                    'rule':index+1,'rules':[rule(image,index)]})
    # Records select 54 of the 99 T4 selectors; synthetic selection checks the
    # unreferenced non-default bodies without claiming English-input reachability.
    for selector in (17,20,22,25,55,61):
        for index in (10,24):
            for width in (0,1,3):
                base=representative(patterns[index],width)
                randomize(rng,base['nodes'])
                cases.append({'id':f'synthetic-T4-{index+1}-{selector}-{width}','nodes':base['nodes'],
                    'rule':index+1,'selector':selector,'rules':[rule(image,index,selector)]})
    # Every dictionary sub-rule on a word node, with an empty rule table so the
    # sub-rule pre-pass is observed alone, then a sample against the full table.
    rules=sub_rules(Path('LTGOLD/BASE.DIC').read_bytes())
    sub_cases=[]
    for number,(word,pattern,action) in enumerate(rules):
        for width in (1,3):
            try:base=representative(pattern,width)
            except ValueError:continue
            nodes=[{'12':0x2A,'18':'*','156':'','284':''},{'12':ord('N'),'18':word,'156':'','284':'translation',
                'rules':[{'pattern':pattern,'action':action}]}]+[n for n in base['nodes'][1:]]
            randomize(rng,nodes)
            sub_cases.append({'id':f'sub-rule-{number}-{width}','nodes':nodes,'rule':0,'rules':[]})
    cases.extend(sub_cases)
    for case in rng.sample(sub_cases,min(args.full_table,len(sub_cases))):
        cases.append(dict(case,id=case['id']+'-full',rule=None,rules=None))
    accepted=[];coverage=collections.Counter();cache={};steps=0
    for case in cases:
        result=native(image,case,cache)
        steps+=result.pop('steps')
        if case.get('rules'):coverage[case['rules'][0][0]]+=1
        accepted.append(result)
    with tempfile.TemporaryDirectory(prefix='ltpro-native-fourth-pass-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(accepted))
        result=subprocess.run(['lua','tools/ltpro_stage_probe.lua',str(path)])
    print(f'T4 isolated selectors: {dict(sorted(coverage.items()))}; {len(sub_cases)} sub-rule cases; {steps} native instructions')
    raise SystemExit(result.returncode)

if __name__=='__main__':main()
