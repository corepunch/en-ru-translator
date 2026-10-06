#!/usr/bin/env python3
"""Execute LTPRO's original general matcher on controlled native-node fixtures."""
import argparse
import random
import struct
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import Machine, lua_value


def original(image, fixture, cache):
    machine = Machine(image)
    machine.cache = cache
    machine.r.update(cs=0x1313, ip=0xa67)
    def put(address, value):
        value = value.encode('cp866') + b'\0'
        machine.mem[address:address+len(value)] = value
    tags = ''
    for i, node in enumerate(fixture['nodes']):
        address = 0x80000 + i * 0x400
        machine.write(0x70000+i*4,4,((address>>4)<<16))
        machine.write(address+12,1,node['12'])
        machine.write(address+0x66,1,node.get('102',0))
        for offset in (0x12,0x9c,0x11c): put(address+offset,node.get(str(offset),''))
        tags += chr(node['12'])
    tags=fixture.get('cache',tags)
    put(0x22d50+0xc5ae,tags)
    put(0xd0000,fixture['pattern'])
    arguments=[0,0x7000,fixture['start'],0,0xd000]
    if 'action' in fixture:
        machine.reg('ip',0x1b4)
        put(0xd1000,fixture['action'])
        arguments=[0,0x7000,fixture['start'],fixture['last'],0,0xd000,0,0xd100]
    for value in reversed(arguments): machine.push(value)
    machine.push(0xffff);machine.push(0xffff)
    machine.run()
    if 'action' in fixture:
        nodes=[]
        for i in range(len(fixture['nodes'])):
            address=0x80000+i*0x400
            nodes.append([machine.read(address+12,1),machine.read(address+0x66,1),machine.cstring(address+0x11c).hex()])
        return [machine.reg('ax'),nodes,machine.cstring(0x22d50+0xc5ae).hex()],machine.steps
    assert machine.cstring(0x22d50+0xc5ae)==tags.encode('ascii'), 'matcher damaged tag cache'
    return machine.reg('ax'),machine.steps


def fixture(pattern,tags,start=1,lexical=None):
    # Extra terminal nodes keep failed lookahead inside allocated native records.
    nodes=[{'12':ord(c),'18':'word','156':'original','284':'translation'} for c in '*'+tags+'*'+'#'*16]
    for index,fields in (lexical or {}).items(): nodes[index].update(fields)
    return {'pattern':pattern,'nodes':nodes,'start':start}


def records(image):
    # T8 has a different matcher and is intentionally excluded from this probe.
    for offset,count,size in [(0x2738c,47,10),(0x2756c,157,10),(0x27b98,136,10),
                              (0x2952c,178,9),(0x2ab30,9,10),(0x2ac92,35,8),(0x2adb2,1,8)]:
        for index in range(count):
            at=offset+index*size
            def string(pointer):
                off,seg=struct.unpack_from('<HH',image,pointer)
                if not off and not seg: return None
                location=0x3a00+seg*16+off
                return image[location:image.index(0,location)].decode('cp866')
            yield string(at),string(at+4) if size!=8 else None


def representative(pattern,width):
    # Build lexical fixtures from each actual pattern, including word/annotation tests.
    nodes=[];p=0;neg=False
    def add(tag,word='word',text='translation'):
        nodes.append({'12':ord(tag),'18':word,'156':'original','284':text})
    def select(classes,negative):
        return next(c for c in 'NDV#*' if c not in classes) if negative else classes[width%len(classes)]
    if not pattern.startswith('*'): add('*')
    start=0 if pattern.startswith('*') else 1
    while p<len(pattern):
        c=pattern[p]
        if c=='~': neg=True;p+=1;continue
        if c in '[<':
            end=pattern.index(']' if c=='[' else '>',p+1)
            classes=pattern[p+1:end]
            if c=='[': add(select(classes,neg))
            else:
                for _ in range(width): add('D' if classes.startswith('$') or not classes else select(classes,neg))
            p=end
        elif c in '`!':
            end=pattern.index(c,p+1);value=pattern[p+1:end]
            add('N',value if c=='`' and not neg else 'different',value+')' if c=='!' and not neg else 'translation')
            p=end
        elif c!='$': add(select(c,True) if neg else c)
        neg=False;p+=1
    add('*')
    for _ in range(16): add('#')
    return {'pattern':pattern,'nodes':nodes,'start':start}


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--random',type=int,default=500)
    args=ap.parse_args();image=Path('LTGOLD/LTPRO.EXE').read_bytes()
    patterns=['N','~N','[VN]','~[VN]','N<D>V','N~<D>V','N<$>V','N<>V','N<DA>[VN]',
              'N<$>`end`','N<$>!мес!','[$]N','$N','$VN','*N*','N<D>V<N>A',
              'N<D>V~N','N<$>~N','`word`','~`WORD`','!мес!','~!мес!','(#)','N-N',
              'N<D>','~<$>V','~[$]N']
    fixtures=[]
    for pattern in patterns:
        for tags in ['N','V','NN','NV','NDV','NDDV','NDAV','NNV','VN','NVDNA','(#)','N-N']:
            fixtures.append(fixture(pattern,tags,0 if pattern.startswith('*') else 1,
                {2:{'18':'END','284':'единица(мес)'},1:{'284':'мес)'}}))
    # Extract every general-pattern table directly, independent of the Lua rules.
    for pattern,_ in records(image):
        for tags in ['NADV','RUV','TZNP','NwNN']:
            fixtures.append(fixture(pattern,tags,0 if pattern.startswith('*') else 1))
        for width in (0,1,3): fixtures.append(representative(pattern,width))
    rng=random.Random(1993)
    for _ in range(args.random):
        pattern=rng.choice(patterns)
        fixtures.append(fixture(pattern,''.join(rng.choices('NDVAXY*,()',k=rng.randrange(1,20))),
            0 if pattern.startswith('*') else 1))
    for pattern in ['N<D>V','N<$>[VN]','N<$>`end`','[VN]','N']:
        for cached in ['*NAV*','*NDV*','*NNN*']:
            f=fixture(pattern,'NDV');f['cache']=cached+'#'*16;fixtures.append(f)
    expected=[];steps=0;cache={}
    for n,f in enumerate(fixtures):
        try: value,count=original(image,f,cache)
        except Exception:
            print('Native failure',n,f)
            raise
        expected.append(value);steps+=count
    with tempfile.TemporaryDirectory(prefix='ltpro-matcher-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(fixtures))
        actual=list(map(int,subprocess.check_output(['lua','tools/ltpro_matcher_probe.lua',str(path)],text=True).splitlines()))
    assert len(actual)==len(expected)
    differences=[(i,a,b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
    for i,a,b in differences[:20]: print('DIFF',i,fixtures[i],'EXE',a,'Lua',b)
    print(f'LTPRO 8086 matcher vs Lua: {len(fixtures)-len(differences)}/{len(fixtures)} cases; {sum(v!=0 for v in expected)} native successes; {steps} instructions')
    raise SystemExit(bool(differences))

if __name__=='__main__': main()
