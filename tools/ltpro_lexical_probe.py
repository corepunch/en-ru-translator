#!/usr/bin/env python3
"""Check the plan's two lexical vertical slices against native DOS state."""
import json
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import lua_value
from ltpro_capture import digest

def main():
    reference=json.loads(Path('test/ltpro/reference.json').read_text())
    if digest(Path('LTGOLD/BASE.DIC').read_bytes())!=reference['assets_sha256']['BASE.DIC']:
        raise ValueError('different native dictionary')
    stages=json.loads(Path('test/ltpro/stages.json').read_text())
    if stages['reference_sha256']!=digest(Path('test/ltpro/reference.json').read_bytes()):
        raise ValueError('different native oracle')
    cases=[]
    for case in stages['cases']:
        if case['id'] in ('case-002','case-052'):
            stage=case['snapshots'][0]
            cases.append({'id':case['id'],'input':case['input'],'cache':stage['cache'],'nodes':stage['nodes']})
    assert len(cases)==2,'missing planned lexical fixtures'
    with tempfile.TemporaryDirectory(prefix='ltpro-lexical-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(cases))
        result=subprocess.run(['lua','tools/ltpro_lexical_probe.lua',str(path)])
    raise SystemExit(result.returncode)

if __name__=='__main__':main()
