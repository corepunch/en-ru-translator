#!/usr/bin/env python3
"""Rebuild isolated, length-preserving LTPRO assets for this frozen phrase batch."""
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
import ltech_dict as ld
from ltpro_capture import FILES


def build(destination):
    destination.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        shutil.copyfile(ROOT / 'LTGOLD' / name, destination / name)
    entries = [ld.line_parts(row.encode('cp866')) for row in
               Path(__file__).with_name('entries.txt').read_text().splitlines() if row]
    dic = ld.load_dictionary(destination / 'BASE.DIC')
    size = len(dic.body())
    dic.delete_folded({ld.fold_key(key) for key, _ in entries})
    dic.lines.extend(key + b'*' + value for key, value in entries)
    # No case in this fixture uses a z headword. Preserve the original image
    # length: this supplied DOS build fails after size-changing DIC edits.
    dic.lines = [row for row in dic.lines if not row.startswith(b'z')]
    dic.lines.sort(key=lambda row: ld.fold_key(ld.line_parts(row)[0]))
    assert len(dic.body()) <= size
    dic.trailing_newlines += size - len(dic.body())
    dic.save(destination / 'BASE.DIC')
    rus = ld.load_dictionary(destination / 'BASE.RUS')
    size = len(rus.body())
    # Neuter indeclinable nominal спасибо, following native шоссе's code.
    rus.delete_folded({word.encode('cp866') for word in ('яхта', 'яровизировать')})
    rus.add_line('спасибо'.encode('cp866'), bytes.fromhex('4e c0 80 ff'), replace=True)
    assert len(rus.body()) <= size
    rus.trailing_newlines += size - len(rus.body())
    rus.save(destination / 'BASE.RUS')


if __name__ == '__main__':
    build(Path(sys.argv[1]))
