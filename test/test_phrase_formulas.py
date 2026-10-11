#!/usr/bin/env python3
"""The phrase build guard must reject frozen and mistagged readings."""

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from check_phrase_formulas import check


class PhraseFormulaTest(unittest.TestCase):
    def test_current_file(self):
        self.assertEqual(check(Path("dictionary/phrases.txt")), [])

    def test_shortcuts(self):
        examples = (
            ("best wishes*Dнаилучшие пожелания\n", "frozen multiword D"),
            ("best wishes*Dнаилучшиеnпожелание\n", "tagged components require a W"),
            ("best wishes*WAнаилучший пожелание\n", "untagged space in W"),
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "phrases.txt"
            for source, message in examples:
                with self.subTest(source=source):
                    path.write_text(source, encoding="utf-8")
                    self.assertTrue(any(message in error for error in check(path)))


if __name__ == "__main__":
    unittest.main()
