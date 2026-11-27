# Editing the translation dictionary

Use the same Lua 5.3+ interpreter as the translator. The editor works offline
and does not require Python, a database server, or the upstream source archives.

```sh
lua tools/dictionary.lua dict select open --pos verb
lua tools/dictionary.lua --json dict select mail --prefix --limit 10
lua tools/dictionary.lua --json rus select читать --pos verb
lua tools/dictionary.lua schema --pos verb
lua tools/dictionary.lua --json validate
```

The bilingual dictionary stores a headword, part of speech, target lemma and an
optional argument frame. The Russian dictionary stores gender and animacy for
nouns, aspect and transitivity for verbs, and explicit inflection forms. The
reader decodes a compressed UTF-8 suffix delta; an agent does not need to write
a flag or a byte offset. For example `is` is `imperative.singular` and `ip` is
`imperative.plural`. The JSON output shows both names and internal codes,
provenance, and effective translations in lookup order. Unknown queries return
an empty array, not an error. A command error goes to stderr and exits 2.

## Edits

```sh
# Add an alternate lemma; inspect the result and then verify a sentence.
lua tools/dictionary.lua dict insert inspect --pos verb --target смотреть --frame obj
lua tools/dictionary.lua dict select inspect --pos verb
lua init.lua 'Inspect the window.'

# Override one form of an existing paradigm; all other forms are retained.
lua tools/dictionary.lua rus update читать --pos verb --form imperative.singular=читай
lua tools/dictionary.lua --json rus select читать --pos verb
lua tools/dictionary.lua rus reset читать --pos verb

# Change an entry, hide a specific sense, or clear its override.
lua tools/dictionary.lua dict update inspect --pos verb --target смотреть --frame imperative
lua tools/dictionary.lua dict delete inspect --pos verb --target смотреть
lua tools/dictionary.lua dict reset inspect --pos verb --target смотреть
```

Start with `select`, so an `insert` will not duplicate an existing translation.
`dict update --to` changes the target by hiding the old one and adding the
new one in a single write; reset both targets to undo that rename. Identically
spelled targets are the same key. If an upstream target has different frames
or modifiers, updating it requires both fields explicitly. New nouns require `--gender`; new verbs require `--aspect`. Use `rus update
--drop-form NAME` to remove a form without discarding the whole paradigm;
`rus delete` hides the paradigm. Missing inflections use the normal runtime
fallbacks, so verify the resulting translation before keeping an edit. An
inserted target without a known paradigm gets a warning; follow it with a
Russian paradigm if the word needs inflection.

The only writable data files are `editor-words.tsv` and `editor-forms.tsv`.
They take precedence over authored and imported data. Upstream exports stay
unchanged and re-exporting does not erase the edits. Backup or review these two
files with Git. Every edit replaces one file atomically and serializes other
editor writes to the same file via a directory lock (macOS/Linux). If the
process is forcibly stopped, remove its indicated `.lock` directory only once
you have verified no editor is running. A running embedded engine has already
loaded its snapshot; reload it to see changes. To edit a scratch checkout or a
copied dictionary, pass `--data DIR`.

Do not add sentences or translations of whole room descriptions. Add lexical
meanings, their argument constraints, and forms here; implement general
grammar in the engine. For a content change, run the offline suite and add a
positive example and a nearby negative control.
