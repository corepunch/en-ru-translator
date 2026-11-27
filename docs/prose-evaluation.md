# Evaluating real prose

Use real books to discover problems, then check the same construction on
unseen language and negative controls. None of the book sentences are runtime
translations. A successful run tests the document path, not literary quality.

| Public-domain source | Pinned GITenberg revision | File | Start marker |
| --- | --- | --- | --- |
| [Alice’s Adventures in Wonderland](https://github.com/GITenberg/Alice-s-Adventures-in-Wonderland_11) | `7f18748e114b994d5d9454d5793581bc0b9cf9d7` | `11.txt` | Alice was beginning |
| [The Time Machine](https://github.com/GITenberg/The-Time-Machine_35) | `154a5c628743bd7d35d1af0fc4bcc017f0e111e1` | `35.txt` | The Time Traveller (for so |
| [The Adventures of Sherlock Holmes](https://github.com/GITenberg/The-Adventures-of-Sherlock-Holmes_1661) | `7e5dd2703fbf503c004063e96ab7c61262375e5f` | `1661.txt` | To Sherlock Holmes she |

```sh
python3 tools/translate_prose.py /path/to/11.txt \
    --start-at 'Alice was beginning' --paragraphs 18 > alice.ru.txt
```

The optional Python runner joins publisher-wrapped lines within paragraphs,
preserves blank lines and feeds the UTF-8 result to the Lua document CLI. It
downloads nothing and does not modify the input. Omit the paragraph limit for
longer extracts; use `--lua texlua` when needed. The runtime does not depend
on this tool or Python. All three pinned samples produced 18 translated
paragraphs each (3,664 English words total).

The independent Lua engine already had basic negative existential and relative
transfer. It now also checks embedded and fronted existentials, negative
pronouns, and genitive coordination. Locative “there” inside a subject is not
an existential. Typography normalization splits attached dash runs without
splitting lexical compounds, and normalizes typographic quotation marks.
Neither of these adds per-book replacements. General long-clause attachment,
reporting clauses, sense selection and stylistic polish remain incomplete.
