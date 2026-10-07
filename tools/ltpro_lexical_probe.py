#!/usr/bin/env python3
"""Compare every single-sentence lexical fixture with native DOS state."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import lua_value
from ltpro_capture import digest

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--all',action='store_true',help='Audit every single-sentence fixture (the default)')
    args=parser.parse_args()
    reference=json.loads(Path('test/ltpro/reference.json').read_text())
    if digest(Path('LTGOLD/BASE.DIC').read_bytes())!=reference['assets_sha256']['BASE.DIC']:
        raise ValueError('different native dictionary')
    stages=json.loads(Path('test/ltpro/stages.json').read_text())
    if stages['reference_sha256']!=digest(Path('test/ltpro/reference.json').read_bytes()):
        raise ValueError('different native oracle')
    cases=[]
    for case in stages['cases']:
        if len([s for s in case['snapshots'] if s['stage']=='lexical'])==1:
            stage=case['snapshots'][0]
            cases.append({'id':case['id'],'input':case['input'],'cache':stage['cache'],'nodes':stage['nodes']})
    assert cases,'missing lexical fixtures'
    with tempfile.TemporaryDirectory(prefix='ltpro-lexical-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(cases))
        result=subprocess.run(['lua','tools/ltpro_lexical_probe.lua',str(path)])
    raise SystemExit(result.returncode)

if __name__=='__main__':main()
