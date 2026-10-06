#!/usr/bin/env python3
"""Differentially execute original morphology functions; no DOS environment required."""
import argparse
import random
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import Machine, GoldMachine, lua_value

ENTRIES = {'noun': 0x223bc, 'adjective': 0x22530, 'verb': 0x2270b, 'participle': 0x22a87}


def original(image, fixture, cache, target):
    machine = (GoldMachine if target == 'ltgold' else Machine)(image)
    machine.cache = cache
    address = ENTRIES[fixture['routine']] + (0x6a10 if target == 'ltgold' else 0)
    header = 0x6900 if target == 'ltgold' else 0x3a00
    machine.reg('ds', 0x4a06 if target == 'ltgold' else 0x22d5)
    machine.reg('cs', (address - header) // 16)
    machine.reg('ip', (address - header) % 16)
    args = list(fixture['args'])
    word = args[1].encode('cp866') + b'\0'
    machine.mem[0xd0000:0xd0000+len(word)] = word
    args[1:2] = [0, 0xd000]
    for value in reversed(args): machine.push(value)
    machine.push(0xffff); machine.push(0xffff)
    machine.run()
    pointer = machine.reg('dx') * 16 + machine.reg('ax')
    return machine.cstring(pointer).hex() if pointer else '-', machine.steps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--random', type=int, default=400)
    ap.add_argument('--target', choices=['ltpro', 'ltgold'], default='ltpro')
    args = ap.parse_args()
    image = Path('LTGOLD/' + args.target.upper() + '.EXE').read_bytes()
    fixtures = []
    def add(routine, *values): fixtures.append({'routine': routine, 'args': list(values)})
    # Every recovered table row is exercised across the actual case/form slots.
    for gender, count in [(0, 33), (1, 66), (2, 35)]:
        for index in range(count):
            for plural in (0, 1):
                for case in range(6): add('noun', index, 'образец', gender, plural, case)
    for gender in range(3):
        for index in range(26):
            for plural in (0, 1):
                for case in range(6): add('adjective', index, 'тестовый', gender, plural, case)
    for aspect, count in [(0, 106), (1, 113)]:
        for index in range(count):
            for person in range(4): add('verb', index, 'обрабатывать', aspect, 0, person, 0, 0, 1)
            for gender in range(3): add('verb', index, 'обрабатывать', aspect, 0, 3, 0, 1, gender)
            for tag in (ord('G'), ord('E')):
                for passive in (0, 1):
                    for past in (0, 1): add('participle', index, 'обрабатывать', aspect, tag, passive, past)
    rng = random.Random(1993)
    for _ in range(args.random):
        aspect = rng.randrange(2); index = rng.randrange(106 if aspect == 0 else 113)
        word = rng.choice(['идти', 'придти', 'печь', 'сечь', 'учиться', 'смеяться', 'казаться', 'мытьсь', 'а', 'ал'])
        add('verb', index, word, aspect, rng.choice([0, 2, 4, 16, 18, 22]), rng.randrange(4), rng.randrange(2), rng.randrange(2), rng.randrange(3))
        add('adjective', rng.randrange(26), word, rng.randrange(3), rng.randrange(2), rng.randrange(6))
        add('participle', index, word, aspect, rng.choice([ord('G'), ord('E')]), rng.randrange(2), rng.randrange(2))
    cache = {}; expected = []; steps = 0
    for fixture in fixtures:
        value, count = original(image, fixture, cache, args.target)
        expected.append(value); steps += count
    with tempfile.TemporaryDirectory(prefix='ltpro-morphology-') as directory:
        path = Path(directory) / 'cases.lua'
        path.write_text('return ' + lua_value(fixtures))
        actual = subprocess.check_output(['lua', 'tools/ltpro_morphology_probe.lua', str(path)], text=True).splitlines()
    assert len(actual) == len(expected)
    differences = [(i, a, b) for i, (a, b) in enumerate(zip(expected, actual)) if a != b]
    for i, a, b in differences[:10]: print('DIFF', i, fixtures[i], 'EXE', a, 'Lua', b)
    print(f'{args.target.upper()} 8086 morphology vs Lua: {len(fixtures)-len(differences)}/{len(fixtures)} cases; {steps} instructions')
    raise SystemExit(bool(differences))


if __name__ == '__main__': main()
