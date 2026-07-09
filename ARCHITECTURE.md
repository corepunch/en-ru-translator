# ARCHITECTURE.md

> **Documentation has moved to [`docs/`](docs/INDEX.md)**

This file is a summary. Detailed documentation is split into focused files:

| Document | Description |
|----------|-------------|
| [`docs/pipeline.md`](docs/pipeline.md) | Translation pipeline: tokenize → parse → compile |
| [`docs/paradigms.md`](docs/paradigms.md) | Morphological tables: nouns, adjectives, verbs, pronouns |
| [`docs/dictionary.md`](docs/dictionary.md) | Binary format of BASE.DIC / BASE.RUS |
| [`docs/rules.md`](docs/rules.md) | Pattern matching syntax and replacement tokens |
| [`docs/tools.md`](docs/tools.md) | Python extraction tools for reverse engineering |

## Quick Overview

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Input Text  │───▶│  Tokenize   │───▶│    Parse     │───▶│   Compile   │
│  (English)   │    │  + Lookup   │    │ (apply rules)│    │ (inflect)   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                         │                  │                  │
                    BASE.DIC          rules.lua          paradigms.lua
                    BASE.RUS         (5 rule sets)      (noun/adj/verb)
```

## Key Files

| File | Role |
|------|------|
| `init.lua` | Entry point. Loads dictionaries, tokenizes input, runs parser + compiler |
| `rules.lua` | ~200 pattern-matching rules extracted from LTGOLD.EXE (669 lines, 5 rule sets) |
| `parser.lua` | Applies rules to tokenized English stream, transforms grammatical tags |
| `compiler.lua` | Generates Russian output using morphological paradigms for proper inflection |
| `paradigms.lua` | Russian noun/adjective/verb declension and conjugation tables |
| `load.lua` | Parses LTGOLD `*.DIC`/`*.RUS` dictionary format (CP866 encoded) |
| `utils.lua` | CP866↔UTF8 conversion, tokenization, string helpers |

## Conventions

- **No comments** in Lua source files — keep code compact
- **No new dependencies** — pure Lua only, no luarocks
- **Match LTGOLD style** — preserve original rule order, pattern format, and code structure
- **CP866 throughout** — legacy encoding internally, UTF-8 only for display via `utils.decode()`

## Running

```sh
lua init.lua
```

Requires Lua 5.3+ (uses bitwise operators). Test sentences are hardcoded in
`init.lua:81-97`. Edit those lines to translate different text.
