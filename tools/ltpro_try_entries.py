#!/usr/bin/env python3
"""Show how original LTPRO translates sentences with candidate dictionary rows.

Installs UTF-8 ``key*code`` rows into an isolated copy of the supplied
LTGOLD/BASE.DIC, captures each sentence twice with tools/ltpro_capture.py, and
prints the original output next to the current Lua/OpenRussian output.

  python3 tools/ltpro_try_entries.py \\
      --entry 'after `all`[j,*]*$DDWPПвNконецPРnконец\\ \\' \\
      --delete 'after all' 'After all, he knows.' 'After all the guests left.'

  python3 tools/ltpro_try_entries.py --entries openrussian/overlays/phrases.txt \\

With no --entry/--entries it captures the untouched supplied assets. The
supplied DOS build fails when BASE.DIC grows, so unused ``z`` headwords are
dropped and the image is padded to its original size. --keep DIR saves the
fixture assets, cases.json, and reference.json for checking in.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import ltech_dict as ld  # noqa: E402
from ltpro_capture import FILES  # noqa: E402


def read_rows(path):
    return [row for row in Path(path).read_text(encoding='utf-8').splitlines() if row.strip()]


def build(destination, rows, deleted):
    destination.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        shutil.copyfile(ROOT / 'LTGOLD' / name, destination / name)
    if not rows and not deleted:
        return
    entries = [ld.line_parts(row.encode('cp866')) for row in rows]
    dic = ld.load_dictionary(destination / 'BASE.DIC')
    size = len(dic.body())
    dic.delete_folded({ld.fold_key(key) for key, _ in entries} |
                      {ld.fold_key(word.encode('cp866')) for word in deleted})
    dic.lines.extend(key + b'*' + value for key, value in entries)
    if len(dic.body()) > size:
        dic.lines = [row for row in dic.lines if not row.startswith(b'z')]
    dic.lines.sort(key=lambda row: ld.fold_key(ld.line_parts(row)[0]))
    if len(dic.body()) > size:
        raise SystemExit(f'candidate rows exceed the original BASE.DIC size by {len(dic.body()) - size} bytes')
    dic.trailing_newlines += size - len(dic.body())
    dic.save(destination / 'BASE.DIC')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('inputs', nargs='+', help='English sentences, exactly as to be translated')
    ap.add_argument('--entry', action='append', default=[], help='one key*code row (repeatable)')
    ap.add_argument('--entries', action='append', default=[], help='UTF-8 file of key*code rows')
    ap.add_argument('--delete', action='append', default=[], help='historical headword to remove (repeatable)')
    ap.add_argument('--delete-file', action='append', default=[], help='file of headwords to remove')
    ap.add_argument('--keep', type=Path, help='save fixture data, cases.json and reference.json here')
    args = ap.parse_args()

    rows = list(args.entry)
    for path in args.entries:
        rows += read_rows(path)
    deleted = list(args.delete)
    for path in args.delete_file:
        deleted += read_rows(path)
    work = args.keep or Path(tempfile.mkdtemp(prefix='ltpro-try-'))
    data = work / 'data'
    build(data, rows, deleted)

    cases, seen = [], set()
    for text in args.inputs:
        base = re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')[:60] or 'case'
        case_id, n = base, 2
        while case_id in seen:
            case_id, n = f'{base}-{n}', n + 1
        seen.add(case_id)
        cases.append({'id': case_id, 'group': 'try', 'input': text})
    (work / 'cases.json').write_text(json.dumps(cases, ensure_ascii=False, indent=2) + '\n')
    subprocess.run([sys.executable, str(ROOT / 'tools/ltpro_capture.py'), '--data', str(data),
                    '--cases', str(work / 'cases.json'), '--output', str(work / 'reference.json'),
                    '--repeat', '2', '--batch-size', '200', '--timeout', '300'],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    native = [c['translation'] for c in json.loads((work / 'reference.json').read_text())['cases']]
    script = ("package.path='./?.lua;'..package.path local e=require 'core.engine' "
              "for line in io.lines(arg[1]) do print((e.translate(line))) end")
    inputs_file = work / 'inputs.txt'
    inputs_file.write_text('\n'.join(args.inputs) + '\n', encoding='utf-8')
    script_file = work / 'translate.lua'
    script_file.write_text(script)
    lua = subprocess.run(['lua', str(script_file), str(inputs_file)], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout.splitlines()
    for text, original, current in zip(args.inputs, native, lua):
        mark = '==' if original == current else '!='
        print(f'{text}\n  original: {original}\n  lua:      {current}  {mark}')
    if args.keep:
        print(f'kept fixture in {work}')
    else:
        shutil.rmtree(work)


if __name__ == '__main__':
    main()
