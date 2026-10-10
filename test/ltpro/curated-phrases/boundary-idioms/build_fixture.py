#!/usr/bin/env python3
"""Isolated LTPRO assets with the five boundary-idiom subrules installed."""
from pathlib import Path
import shutil, sys
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools'))
import ltech_dict as ld
from ltpro_capture import FILES
dest = Path(sys.argv[1]); dest.mkdir(parents=True, exist_ok=True)
for name in FILES: shutil.copyfile(ROOT / 'LTGOLD' / name, dest / name)
rows = [r for r in (ROOT / 'openrussian/overlays/phrases.txt').read_text().splitlines()
        if r.startswith(('not `at', 'at `all', 'after `all', 'my `pleasure'))]
assert len(rows) == 5, rows
entries = [ld.line_parts(r.encode('cp866')) for r in rows]
removed = ['not at all', 'at all', 'after all', 'my pleasure']
dic = ld.load_dictionary(dest / 'BASE.DIC'); size = len(dic.body())
dic.delete_folded({ld.fold_key(k) for k, _ in entries} | {ld.fold_key(w.encode('cp866')) for w in removed})
dic.lines.extend(k + b'*' + v for k, v in entries)
dic.lines = [r for r in dic.lines if not r.startswith(b'z')]
dic.lines.sort(key=lambda row: ld.fold_key(ld.line_parts(row)[0]))
assert len(dic.body()) <= size, (len(dic.body()), size)
dic.trailing_newlines += size - len(dic.body()); dic.save(dest / 'BASE.DIC')
print('\n'.join(rows))
