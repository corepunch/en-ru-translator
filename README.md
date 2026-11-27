# English → Russian Offline Translator

A rule-based translator that runs in Lua 5.3+ without a network connection,
model download, binary dictionary reader, or additional runtime packages.
This is a draft translation tool, not a replacement for a human translation.

```sh
lua init.lua 'I fly home.'
lua init.lua --formal 'I will send you the updated report.'
lua init.lua --document letter.txt
printf '%s\n' 'I am home.' 'There was no answer.' | lua init.lua
```

The CLI reads UTF-8 and preserves line breaks and basic list markers.
`--trace` prints selected lexical candidates to stderr; `--data DIR` accepts
another export in the same TSV format. Start with the bundled data: the
translator runs from a clean checkout without Python or SQLite.

```lua
local translator = require "en_ru.engine"
local data = translator.load({data_dir = "dictionary"})
local russian, diagnostics = translator.translate("I fly home.", {
    lexicon = data,
    formal = false,
})
```

An embedded host can pass a `read_file(path) → bytes, error` callback to
`load`. A loaded lexicon may be reused across calls. Unknown words pass
through; the translator does not use a sentence-to-sentence lookup table.

- [Architecture and grammar coverage](ARCHITECTURE.md)
- [Data origins, licenses and reproducible export](dictionary/ATTRIBUTION.txt)
- [Testing](TESTING.md)

For game hosts, [Adventure text](ARCHITECTURE.md#adventure-text) describes
the optional display-only adapter. See [the Zork I evaluation](docs/adventure-evaluation.md)
for route examples, transfer checks, and remaining gaps.
