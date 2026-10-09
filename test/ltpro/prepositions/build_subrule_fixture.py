#!/usr/bin/env python3
"""Isolated LTPRO assets with the behind/inside boundary subrules installed."""
from pathlib import Path
import shutil, sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
import ltech_dict as ld
from ltpro_capture import FILES
dest = Path(sys.argv[1]); dest.mkdir(parents=True, exist_ok=True)
for name in FILES: shutil.copyfile(ROOT / 'LTGOLD' / name, dest / name)
rows = ['behind [,*]*$Dпозади', 'inside [,*]*$Dвнутри']
entries = [ld.line_parts(r.encode('cp866')) for r in rows]
dic = ld.load_dictionary(dest / 'BASE.DIC'); size = len(dic.body())
dic.lines.extend(k + b'*' + v for k, v in entries)
dic.lines = [r for r in dic.lines if not r.startswith(b'z')]
dic.lines.sort(key=lambda row: ld.fold_key(ld.line_parts(row)[0]))
assert len(dic.body()) <= size
dic.trailing_newlines += size - len(dic.body()); dic.save(dest / 'BASE.DIC')
