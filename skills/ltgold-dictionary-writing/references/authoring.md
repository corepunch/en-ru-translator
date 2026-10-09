# Dictionary authoring reference

## Sources and lookup

`LTGOLD/dic.txt` is the supplied UTF-8 Russian manual. Search chapter 3
(`ПРЕДСТАВЛЕНИЕ СЛОВАРНЫХ СТАТЕЙ`) for entry structure and `КОДИРОВАНИЕ
СЛОВОСОЧЕТАНИЙ` / `W` for phrase equivalents; appendix 1 lists syntactic tags.
Search by headings rather than relying on fixed line numbers. `NEWLTGE.DOC`
describes program switches. Some other `.DOC` files are binary Word documents;
do not treat every `.DOC` as text. `README.CYR` is CP866 and describes asset roles.

Use the existing editor for indexed files, rather than grepping their binary
headers or editing them as UTF-8:

```sh
python3 tools/ltech_dict.py find LTGOLD/BASE.DIC are
python3 tools/ltech_dict.py find LTGOLD/BASE.DIC you
python3 tools/ltech_dict.py find reference/openrussian/BASE.DIC how --partial
python3 tools/ltech_dict.py find reference/openrussian/BASE.DIC 'how XR[*]'
```

Check `find --help` before adapting command options. Inspect both the active
dictionary and historical dictionaries; presence in the latter does not imply
availability in the default engine. Exact keys can have multiple readings;
the first record wins unless `dictionary_entry` selects another.

## Native conventions

Use the [complete code and value reference](codes.md) for tag meanings and
examples, tag-specific numeric fields, pattern and action syntax, and the
symbol-by-symbol greeting breakdowns. Its implementation notes take precedence
over assumptions based only on a tag's name in the manual.

Entries have the form `English key*reading`. The English side is folded for
ASCII case. Russian text and grammatical codes are stored as CP866 bytes.

Verified historical examples:

```text
am*X001\be
are*X013-fесть ли\be
is*X003бытьUдолженfимеется ли\be
i*R011яrу меняmмне
he*R031онrу негоmему
we*R11мыr11у насmнам
they*R13ониr13у нихmим
you*R12Выr12у васmВам
```

`X` digits are tense, number, person. `R/M` digits are number, person, gender.
Number 0 is singular, 1 plural; person 1/2/3; gender 0 neuter, 1 masculine,
2 feminine. Omitted digits keep existing/default fields. `R021ты` explicitly
encodes informal singular `you`; historical `R12Вы` encodes plural/formal `you`.
Choose register deliberately. Backreferences such as `\be` also enable stem
phrase lookup; inspect that stem's phrases before adding a redirect to imported
data.

After `P`, Cyrillic uppercase case codes are `Р` genitive, `Д` dative, `В`
accusative, `Т` instrumental, `П` prepositional, `И` nominative. The later
reading-selection stage accepts repeated case codes, with the last one winning;
the lexical decoder consumes the first. Do not replace Cyrillic codes with
visually similar Latin letters. `core/lexicon.lua` and `core/senses.lua` show
which metadata each stage consumes.

`W` readings can tag components for agreement and inflection:

```text
after-sale services*WAпослепродажныйNсервис
interfere*VWVсоздавать помехи
bond*ZWVподписывать обязательство/Nобязательство;облигация
```

Native `#` designates a nontranslated unit/proper name, optionally with number
and gender metadata; it is not the standard tag for Russian phrase text.
`#...#` literal spans are supported by this Lua implementation. Do not describe
that convenience as the native convention for fixed Russian greetings.
A slash separates phrase readings; semicolons separate meanings. `.` can mark an English-side classification in compound readings.
Preserve these distinctions rather than treating every character after `*`
as plain text. The native manual describes `~` as one arbitrary word; this Lua
engine supports a bounded gap of zero or more words, stopping at punctuation
and protected spans. Such a gap is too broad when a slot must be a pronoun.

Existing native per-word subrules use `head pattern*$action`, for example:

```text
as RV*$Jкогда
in `full`[*]*$Dполностью\ \
```

The pattern begins **after** the head word. `core/matching.lua` implements tags,
`[classes]`, backtick literals, and other native pattern operators. `[*]` matches
the sentence boundary. Stars within a pattern are part of the key; `*$`
separates its action. Native T4 subrules normally rewrite the head and use
backslash instructions for additional edits; they do not automatically
distribute an action across the matched span.

## Native grammatical phrase subrules

Use the existing T4 `head pattern*$head-action\tail-action\selector` mechanism.
The head rewrite changes its class/reading. Backticked context actions replace
only the selected tag and reading; the original node keeps its number, person,
gender, and other grammatical fields. A later `W` expansion can therefore use
those fields without a custom retained-slot matcher.

```text
how XR[*]*$Dкак\`PР01у``MMWMJ0nдело`\
what <X>`up`[*]*$DDWDкакnдело\ $ \
```

For `how`, `XR[*]` matches an auxiliary and personal pronoun at sentence end.
`Dкак` replaces the head. The first backticked context action replaces the
auxiliary with `PР01у`. The second changes the pronoun to `M` with a packed
`MWMJ0nдело` equivalent. Its empty first `M` component retains the original
node's grammatical fields, allowing normal pronoun generation to supply the
oblique form. `J0` separates that pronoun from the nominative plural `nдело`.
The last backslash starts an empty selector section. Read the symbol-by-symbol
[code reference](codes.md#greeting-entries) before changing these actions.

The native `how` form has been executed in the original program for all six
personal-pronoun variants. Original LTPRO produces `у его/ее/их` in the third
person; the Lua agreement/generation fixes produce `у него/неё/них`. This is a
verified engine difference, not evidence that native grammatical phrase matching
is absent. No custom pre-T1 retained-slot syntax or execution pass is needed.

The separate sentence-final `it` rule in native T4 overrides this construction
for `How is it?`: captured original output is `Как У Это?`, and current Lua output
is `Как у это?`. Treat this as an unresolved rule-order interaction; the six
personal-pronoun examples above must not be presented as covering every pronoun.

For `what`, `<X>` permits the auxiliary to remain or have been removed by native
question cleanup, lexical `up` identifies the idiom, and `[*]` requires sentence
end. The context replacement action deletes the auxiliary/anchor words. Native
BASE.DIC models include:

```text
thank `you`[*]*$Dблагодарю вас\ \
in `full`[*]*$Dполностью\ \
exclusive [*]*$VVWKнеVучитывать
```

Use structural function-word readings in `function-words.txt`; fixed `W` text
cannot act as an `R` pronoun or an `X` auxiliary. A space in a `W` reading starts
an uninflected tail, appropriate for genuinely fixed text. Use `N/n` for nouns
that must inflect, as the greeting's lemma `дело` does.

An audit of all three supplied LTGOLD dictionaries found 14,528 records containing `W` in
BASE.DIC, 2,720 in BUSINESS.DIC, and 5,224 in COMPUTER.DIC. There are no `W#`
records in the first two; the only one in COMPUTER.DIC is
`at-bus*NNW#02at-/Nшина`, a nontranslated technical component. All 29 `W`
records containing `#` use letter labels, acronyms, or technical names. Other `#`
components include `article i*WNстатья#I` and
`windows programming*WNпрограммирование в#Windows`. Contrast ordinary Russian
composition: `after-sale services*WAпослепродажныйNсервис`,
`money matters*WAденежныйnдело`, and
`be in charge of*WXбытьAответственныйPВза`.

Do not put final `.`, `!`, or `?` in a literal phrase key to restrict sentence
end. The former Lua-only matching behavior has been removed. Use a native
grammatical context rule ending in `[*]`; punctuation is emitted separately.
`How's` expands to `how is`; smart apostrophes normalize at the encoding boundary.

## Build and verify

Keep UTF-8 source rows, then rebuild the active index through the editor:

```sh
python3 tools/ltech_dict.py import reference/openrussian/BASE.DIC \
  --entries reference/openrussian/function-words.txt --replace --in-place
python3 tools/ltech_dict.py import reference/openrussian/BASE.DIC \
  --entries reference/openrussian/phrases.txt --replace --in-place
python3 tools/ltech_dict.py check reference/openrussian/BASE.DIC
lua test/greetings_test.lua
python3 -m unittest discover -s tools -p test_ltech_dict.py
sh test/run_all.sh
```

Each nonblank source row must contain a nonempty key and code, be CP866
encodable, and have a unique key within the batch. `--replace` replaces all
existing records for that exact key; preserve required alternatives in the
replacement reading. Import validates the batch before writing and is repeatable.
Full OpenRussian regeneration must apply both source batches after the C build;
see `reference/openrussian/README.md`.

Inspect tags independently of phrase output with `core.lexicon.analyze`, and
check `state.stages.T4.events` for applied native dictionary subrules. Exercise
case generation through `core.engine.translate`; observing a lexical tag alone
does not prove the final translation. Original-output checks must use the
capture workflow in repository `AGENTS.md`.
