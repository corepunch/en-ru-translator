#!/usr/bin/env python3
"""Compare the Lua T3 scheduler with accepted full-DOS T2/T3 stage snapshots."""
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
    ap.add_argument('--ids',nargs='*')
    ap.add_argument('--fixtures-out',type=Path,help='also keep the generated Lua fixtures')
    args=ap.parse_args()
    stages=json.loads(args.stages.read_text())
    if stages['schema']!=1 or stages['identical_runs']<2: ap.error('unverified native stages')
    if stages['reference_sha256']!=digest(args.reference.read_bytes()): ap.error('different oracle')
    fixtures=[]
    for case in stages['cases']:
        if args.ids and case['id'] not in args.ids: continue
        snapshots=case['snapshots']
        for index,before in enumerate(snapshots):
            if before['stage']!='T2': continue
            after=snapshots[index+1] if index+1<len(snapshots) else None
            # A missing T3 boundary is a native early return, kept as evidence.
            if not after or after['stage']!='T3': continue
            fixtures.append({'id':case['id']+':'+str(index),'before':before['nodes'],
                             'after':after['nodes'],'cache':after['cache'],'stage':'T3',
                             'terminator':ord(case['input'][-1])})
    with tempfile.TemporaryDirectory(prefix='ltpro-third-pass-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(fixtures))
        if args.fixtures_out: args.fixtures_out.write_text(path.read_text())
        result=subprocess.run(['lua','tools/ltpro_stage_probe.lua',str(path)])
    raise SystemExit(result.returncode)

if __name__=='__main__': main()
