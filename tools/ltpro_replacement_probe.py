#!/usr/bin/env python3
"""Compare original LTPRO replacement instructions and all affected node fields."""
import argparse
import copy
import json
import random
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import lua_value
from ltpro_matcher_probe import fixture, original, records, representative


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--random',type=int,default=400)
    args=ap.parse_args();image=Path('LTGOLD/LTPRO.EXE').read_bytes()
    cases=[]
    rules=[('Z[VN]','NN'),('T<H%D,>Z','@$N'),('*<DK,>Z[TAO]','@$V'),
           ('[RbKk]<D>Z','.$V'),('bG','BV'),('Z[bY{]','N'),('b[TAON#]','`Pк`'),
           ('(#)','{#}'),('N<D>V','@$V'),('N<$>V[AN]','@$VN'),
           ('N<$>[VN]','@$V'),('N<$>`end`','@$V'),('N<$>!мес!','@$N'),
           ('N<$>VN','@$@N'),('N<$>VN','@$`Pк`N'),('N<D>','@$'),
           ('`if`N','.@'),('~[NV]A','.@'),('NN',';='),('NN','^&'),
           ('NN',' #'),('NN','`@текст`V'),('NN','`?текст`V'),('NN','`текст`V'),
           ('NN','`Vслово`V'),('NN','j|'),('NN','@@')]
    for pattern,action in rules:
        for tags in ['ZN','TZ','TDZ','RZ','RDZ','bG','bN','(#)','NV','NDV','NDNVN','NN']:
            f=fixture(pattern,tags,0 if pattern.startswith('*') else 1,
                {2:{'18':'END','284':'единица(мес)'}})
            f.update(action=action,last=len(tags))
            cases.append(f)
    match_cache={}
    for pattern,action in records(image):
        if not action: continue
        for width in (0,1,3):
            f=representative(pattern,width)
            last,_=original(image,f,match_cache)
            if last:
                f.update(action=action,last=last)
                cases.append(f)
    rng=random.Random(1993)
    for pattern,action in [('N<$>[VN]','@$A'),('N<$>VN','@$AN'),('N<D>V','@$N')]:
        f=fixture(pattern,'NDVN');f.update(cache='*NNVN*'+'#'*16,action=action,last=4);cases.append(f)
    for _ in range(args.random):
        f=copy.deepcopy(rng.choice(cases))
        for node in f['nodes']: node['102']=rng.choice([0,ord('Z'),ord('E')])
        f['last']=rng.randrange(f['start'],len(f['nodes'])-16)
        cases.append(f)
    expected=[];steps=0;cache={}
    for n,f in enumerate(cases):
        try: value,count=original(image,f,cache)
        except Exception:
            print('Native failure',n,f);raise
        expected.append(value);steps+=count
    with tempfile.TemporaryDirectory(prefix='ltpro-replacement-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(cases))
        output=subprocess.check_output(['lua','tools/ltpro_replacement_probe.lua',str(path)],text=True)
        actual=[json.loads(line) for line in output.splitlines()]
    assert len(actual)==len(expected)
    differences=[(i,a,b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
    for i,a,b in differences[:10]: print('DIFF',i,cases[i],'EXE',a,'Lua',b)
    print(f'LTPRO 8086 replacement vs Lua: {len(cases)-len(differences)}/{len(cases)} cases; {steps} instructions')
    raise SystemExit(bool(differences))

if __name__=='__main__': main()
