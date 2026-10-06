#!/usr/bin/env python3
"""Compare the Lua T1 scheduler with accepted full-DOS stage snapshots."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import lua_value
from ltpro_capture import digest

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--stages',type=Path,default=Path('test/ltpro/stages.json'))
    ap.add_argument('--reference',type=Path,default=Path('test/ltpro/reference.json'))
    args=ap.parse_args()
    stages=json.loads(args.stages.read_text())
    if stages['schema']!=1 or stages['identical_runs']<2: ap.error('unverified native stages')
    if stages['reference_sha256']!=digest(args.reference.read_bytes()): ap.error('different oracle')
    fixtures=[]
    for case in stages['cases']:
        for index,before in enumerate(case['snapshots']):
            if before['stage']!='lexical': continue
            following=case['snapshots'][index+1:]
            events=[]
            while following and following[0]['stage']=='T1-match': events.append(following.pop(0))
            after=following[0] if following else None
            if after and after['stage']=='lexical': after=None
            if after and after['stage']!='T1': ap.error('unexpected stage sequence')
            fixtures.append({'id':case['id']+':'+str(index),'before':before['nodes'],
                             'after':after['nodes'] if after else [],
                             'events':events,
                             'cache':after['cache'] if after else '', 'early_exit':0 if after else 1,
                             'terminator':ord(case['input'][-1])})
    with tempfile.TemporaryDirectory(prefix='ltpro-first-pass-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(fixtures))
        result=subprocess.run(['lua','tools/ltpro_first_pass_probe.lua',str(path)])
    raise SystemExit(result.returncode)

if __name__=='__main__': main()
