#!/usr/bin/env python3
"""Round-trip and edit checks for tools/ltech_dict.py."""

import io
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ltech_dict as ld


ROOT = Path(__file__).resolve().parents[1]
LTGOLD = ROOT / 'LTGOLD'
SOKRAT = Path('/Users/igor/Downloads/SOKRAT')


def template_header():
    header = bytearray(b'LTech DIC File 2.00 \x1aERS\x00\x02\x02\x00')
    header += b'\x1a\x00'  # 26-letter alphabet
    header += b'\x00' * (0x28 - len(header))
    return bytes(header)


class RoundTripTests(unittest.TestCase):
    def test_shipped_ltech_files_round_trip(self):
        names = ['BASE.DIC', 'BASE.RUS', 'BUSINESS.DIC', 'COMPUTER.DIC']
        missing = [name for name in names if not (LTGOLD / name).is_file()]
        if missing:
            self.skipTest('missing ' + ', '.join(missing))
        for name in names:
            path = LTGOLD / name
            original = path.read_bytes()
            dictionary = ld.load_dictionary(path)
            self.assertTrue(dictionary.index_valid(), name)
            self.assertIsNone(dictionary.framing_note, name)
            self.assertEqual(dictionary.to_bytes(), original, name)

    def test_sokrat_szdd_index_matches(self):
        samples = [
            SOKRAT / 'D2' / 'BASE.DI_',
            SOKRAT / 'D1' / 'BASE.RU_',
            SOKRAT / 'D2' / 'BASR.DI_',
        ]
        if not all(path.is_file() for path in samples):
            self.skipTest('Сократ SZDD samples are not on this machine')
        for path in samples:
            dictionary = ld.load_dictionary(path)
            self.assertEqual(dictionary.kind, 'lts', path.name)
            self.assertTrue(dictionary.index_valid(), path.name)
            self.assertGreater(sum(1 for _key, _value in dictionary.entries()), 0)

    def test_shifted_body_is_reported_and_rebuilt(self):
        path = LTGOLD / 'BUSINESS.DIC'
        if not path.is_file():
            self.skipTest('BUSINESS.DIC is not present')
        original = bytearray(path.read_bytes())
        insert = 'inserted term*Nвставка\n'.encode('cp866')
        # Put the new line after the leading newline, and leave the old index
        # where it slides to: header + longer body + original index bytes.
        body_end = struct.unpack_from('<I', original, 0x1E)[0]
        damaged = original[:0x29] + insert + original[0x29:]
        self.assertNotEqual(struct.unpack_from('<I', damaged, 0x22)[0], len(damaged))
        dictionary = ld.load_dictionary_bytes(damaged, path)
        self.assertIsNotNone(dictionary.framing_note)
        self.assertFalse(dictionary.index_valid())
        keys = [ld.decode_cp866(key) for key, _value in dictionary.entries()]
        self.assertIn('inserted term', keys)
        rebuilt = dictionary.to_bytes()
        again = ld.load_dictionary_bytes(rebuilt, path)
        self.assertTrue(again.index_valid())
        self.assertIsNone(again.framing_note)
        self.assertEqual(again.to_bytes(), rebuilt)
        self.assertLess(body_end, len(damaged))


class EditTests(unittest.TestCase):
    def setUp(self):
        self.dictionary = ld._load_structured(self._image(), Path('memory.dic'))

    def _image(self):
        dictionary = ld.Dictionary(
            template_header(),
            [
                'a*T'.encode('cp866'),
                'cat*Nкот'.encode('cp866'),
                'dog*Nсобака'.encode('cp866'),
                'gg*N'.encode('cp866'),
            ],
            1, 2, 'ltech', 26, ld.LATIN, 'ltech', False, 0x1E, 0x22, b'',
        )
        data = dictionary.to_bytes()
        return data

    def test_find_add_delete_and_index(self):
        self.assertEqual(len(self.dictionary.find('Cat')), 1)
        self.assertEqual(self.dictionary.find('dog')[0][1].decode('cp866'), 'Nсобака')
        self.dictionary.add_line('ant'.encode('cp866'), 'Nмуравей'.encode('cp866'))
        keys = [key.decode('ascii') for key, _value in self.dictionary.entries()]
        self.assertEqual(keys, ['a', 'ant', 'cat', 'dog', 'gg'])
        with self.assertRaises(ld.DictError):
            self.dictionary.add_line(b'cat', 'Nкот'.encode('cp866'))
        self.dictionary.add_line(b'cat', 'Nкошка'.encode('cp866'), replace=True)
        self.assertEqual(self.dictionary.find('cat')[0][1].decode('cp866'), 'Nкошка')
        removed = self.dictionary.delete_folded({ld.fold_key(b'dog')})
        self.assertEqual(removed, 1)
        saved = self.dictionary.to_bytes()
        loaded = ld.load_dictionary_bytes(saved, Path('edited.dic'))
        self.assertTrue(loaded.index_valid())
        self.assertEqual([key for key, _value in loaded.entries()], [b'a', b'ant', b'cat', b'gg'])
        # The single-letter slot and the doubled-letter slot both name "gg"'s newline
        # only when no real "gg" word exists. Here "gg" is a real headword.
        index = loaded.index_bytes()
        slots = list(struct.unpack('<' + 'I' * (26 * 27), index))
        cat = next(offset for offset, key in self._offsets(loaded) if key == b'cat')
        self.assertEqual(slots[2 * 27 + 0], cat)  # row c, column a

    def _offsets(self, dictionary):
        body = dictionary.body()
        header = len(dictionary.header)
        index = 0
        while index < len(body):
            if body[index] == 10:
                end = body.find(b'\n', index + 1)
                if end < 0:
                    end = len(body)
                line = body[index + 1:end]
                if line:
                    key, _value = ld.line_parts(line)
                    yield header + index, key
                index = end
            else:
                index += 1

    def test_subtract_command(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'BASE.DIC'
            source.write_bytes(self.dictionary.to_bytes())
            drop = root / 'drop.txt'
            drop.write_text('cat\ndog\n', encoding='utf-8')
            output = root / 'out.dic'
            with redirect_stdout(io.StringIO()):
                status = ld.main(['subtract', str(source), '--drop', str(drop), '-o', str(output)])
            self.assertEqual(status, 0)
            loaded = ld.load_dictionary(output)
            self.assertEqual([key for key, _value in loaded.entries()], [b'a', b'gg'])
            self.assertTrue(loaded.index_valid())
            untouched = source.read_bytes()
            self.assertEqual(untouched, self.dictionary.to_bytes())


if __name__ == '__main__':
    unittest.main()
