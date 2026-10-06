#!/usr/bin/env python3
"""Verify T8's separate matcher using the original 12-byte constituent records."""
import argparse
import random
import struct
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import Machine, lua_value
from ltpro_matcher_probe import representative


def original(image,fixture,cache):
    machine=Machine(image);machine.cache=cache
    machine.r.update(cs=0x1c3d,ip=0x135)
    for i,c in enumerate(fixture['tags']): machine.write(0x70000+i*12,1,ord(c))
    for address,text in [(0x22d50+0xc7b6,fixture.get('cache',fixture['tags'])),(0xd0000,fixture['pattern'])]:
        value=text.encode('cp866')+b'\0';machine.mem[address:address+len(value)]=value
    for value in reversed([0,0x7000,fixture['start'],0,0xd000]): machine.push(value)
    machine.push(0xffff);machine.push(0xffff);machine.run()
    assert machine.cstring(0x22d50+0xc7b6)==fixture.get('cache',fixture['tags']).encode('ascii')
    return machine.reg('ax'),machine.steps


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--random',type=int,default=500)
    args=ap.parse_args();image=Path('LTGOLD/LTPRO.EXE').read_bytes()
    patterns=[]
    for i in range(83):
        off,seg=struct.unpack_from('<HH',image,0x2b134+i*8);at=0x3a00+seg*16+off
        patterns.append(image[at:image.index(0,at)].decode('ascii'))
    patterns+=['.','~.N','[$]','~[$]','N<D>V','N~<D>V','N<$>V','N<>V','N<DA>[VN]',
               'N<D>V<N>A','N<D>V~N','N<$>~N','N<D>','~<$>V','N-N','*N*']
    cases=[]
    for pattern in patterns:
        for width in (0,1,3):
            f=representative(pattern,width)
            cases.append({'pattern':pattern,'start':f['start'],'tags':''.join(chr(n['12']) for n in f['nodes'])})
        for tags in ['NDV','RUV','TZNP','NND','NDAV','V']:
            cases.append({'pattern':pattern,'start':1,'tags':'*'+tags+'*'+'#'*16})
    rng=random.Random(1993)
    for pattern in ['N<D>V','N<$>[VN]','[VN]','N']:
        for cached in ['*NAV*','*NDV*','*NNN*']:
            cases.append({'pattern':pattern,'start':1,'tags':'*NDV*'+'#'*16,'cache':cached+'#'*16})
    for _ in range(args.random):
        cases.append({'pattern':rng.choice(patterns),'start':1,'tags':'*'+''.join(rng.choices('NDVXYJPR*',k=rng.randrange(1,20)))+'*'+'#'*16})
    expected=[];steps=0;cache={}
    for f in cases:
        value,count=original(image,f,cache);expected.append(value);steps+=count
    with tempfile.TemporaryDirectory(prefix='ltpro-constituent-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(cases))
        actual=list(map(int,subprocess.check_output(['lua','tools/ltpro_constituent_probe.lua',str(path)],text=True).splitlines()))
    assert len(expected)==len(actual)
    differences=[(i,a,b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
    for i,a,b in differences[:10]: print('DIFF',i,cases[i],'EXE',a,'Lua',b)
    print(f'LTPRO 8086 constituent matcher vs Lua: {len(cases)-len(differences)}/{len(cases)} cases; {sum(v!=0 for v in expected)} native successes; {steps} instructions')
    raise SystemExit(bool(differences))

if __name__=='__main__': main()
