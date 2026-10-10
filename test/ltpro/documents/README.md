# Whole-document LTPRO references

`cases.json` holds whole files: LTGOLD's own `DEMO.TXT` (the sample agreement,
input `demo`) and short documents that isolate one rule of LTPRO's file
layer. `reference.json` is their original output, captured with
`tools/ltpro_capture.py` (`/I in /O out /F- /B- /N`, LTGOLD's BASE.DIC and
BASE.RUS), two runs byte-identical. The capture appends CRLF to each input.

`test/document_test.lua` translates every input with `core/document.lua` and
compares the complete output file byte for byte, appendices included. All 21
documents, `DEMO.TXT` among them, match the original exactly.

Recapture after changing the inputs:

```sh
python3 tools/ltpro_capture.py --cases test/ltpro/documents/cases.json \
  --output test/ltpro/documents/reference.json --repeat 2 --timeout 300
```

What the file layer does (ported in `core/document.lua`):

- Lines accumulate into a sentence (at most ten). A blank or wordless line, a
  list marker (`1.`, `(1)`, `a)`, `-` …), or a line following a short line
  (under half its length, at most five records) ends the accumulated text.
- A sentence ends at `.?!` before a space unless an abbreviation (`Mr`, `St`,
  `no`, a single letter …) or a lowercase word follows; at `:` or `;` ending
  a line; at `:` before a capital; at six spaces.
- The text is translated with that terminator, and the separator found
  (`.`, `.` + newline, `")` …) is written after it. An unterminated text gets
  the separator of the last sentence end, so `AGREEMENT` after `Is it?`
  becomes `СОГЛАШЕНИЕ?`.
- Each output line starts with its source line's indentation or list marker;
  sentences on one line keep the spaces between them.
- Alternatives are numbered across a paragraph; `MULTIPLE MEANINGS:` follows
  a sentence ending its line, or a paragraph ended by a blank line.
