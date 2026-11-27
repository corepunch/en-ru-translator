# Working on the translator

- Write reusable grammar and improve the lexicon's meanings and argument
  frames. Never add whole-sentence translations to the runtime.
- Keep the runtime offline, UTF-8 and in Lua. New data must have reproducible
  exports, pinned source inputs, and attribution shipped with the data.
- Use contrasts and unseen English vocabulary to check a rule. Test the CLI
  and the reusable engine entry point with `sh test/run_all.sh`.
- Commit only intended changes and use a review branch for cross-project
  runtime and data migrations.
- Use `lua tools/dictionary.lua` to inspect or edit dictionary entries. Start
  with `dict select` or `rus select` and use the named forms from `schema`.
  Keep generated shards read-only; see [the editor guide](docs/dictionary-editor.md).
