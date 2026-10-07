#!/usr/bin/env python3
"""Compare contextual transliteration with the original LTPRO instructions."""
import itertools
import random
import string
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import Machine, lua_value


def original(image, source, preserve_case, cache):
    machine = Machine(image)
    machine.cache = cache
    machine.r.update(cs=0x211E, ip=0x0E82)
    value = source.encode('cp866') + b'\0'
    machine.mem[0xD0000:0xD0000 + len(value)] = value
    for word in reversed([0, 0x8000, 0, 0xD000, int(preserve_case)]):
        machine.push(word)
    machine.push(0xFFFF)
    machine.push(0xFFFF)
    machine.run()
    return machine.cstring(0x80000).hex()


def main():
    image = Path('LTGOLD/LTPRO.EXE').read_bytes()
    words = [''.join(pair) for pair in itertools.product(string.ascii_lowercase, repeat=2)]
    # Each contextual switch receives vowels, consonants, end-of-word and
    # punctuation, with both initial and medial positions.
    for current in 'acdegijkoprstuwxy':
        for following in 'aeiouybcghklrstw .':
            for third in 'eryk .':
                for prefix in ['', 'b', 'abcd']:
                    words.append(prefix + current + following + third)
    words += ['Aaron', 'Ivanova', 'Vadim', 'Lada', 'the', 'th', 'ble', 'chair', 'cious',
              'action', 'special', 'ocean', 'edition', 'sion', 'revision', 'gion',
              'igh', 'ought', 'ruin', 'xion', 'xious', 'ewe', 'ew', 'while', 'youth']
    rng = random.Random(1992)
    words += [''.join(rng.choices(string.ascii_letters + "-' .012", k=rng.randrange(1,18)))
              for _ in range(300)]
    cases = [{'source': source, 'preserveCase': preserve}
             for word in words for source in [word, word.upper(), word.title()]
             for preserve in [False, True]]
    cache = {}
    expected = [original(image, case['source'], case['preserveCase'], cache) for case in cases]
    with tempfile.TemporaryDirectory(prefix='ltpro-transliteration-') as directory:
        fixture = Path(directory) / 'cases.lua'
        fixture.write_text('return ' + lua_value(cases))
        actual = subprocess.check_output(['lua', 'tools/ltpro_transliteration_probe.lua', str(fixture)], text=True).splitlines()
    assert len(expected) == len(actual)
    differences = [(index, a, b) for index, (a, b) in enumerate(zip(expected, actual)) if a != b]
    for index, a, b in differences[:20]:
        print('DIFF', cases[index], 'EXE', bytes.fromhex(a).decode('cp866'), 'Lua', bytes.fromhex(b).decode('cp866'))
    print(f'LTPRO transliteration vs Lua: {len(cases)-len(differences)}/{len(cases)}')
    raise SystemExit(bool(differences))


if __name__ == '__main__':
    main()
