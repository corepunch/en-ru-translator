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
for `How is it?`: captured original output is `Как У Это?`. Lua now protects an
authored W equivalent from later English lexical rewrites within its span,
giving `Как у него дела?` with the neuter pronoun's grammatical fields retained.
The regression includes both this input and `How's it?`; the repeated native
capture is in `test/ltpro/curated-phrases/`.

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

The `#` decoder reads a leading Cyrillic с/м/ж as gender, so `#` text must not
start with Russian prose: the OpenRussian builder's former `W#согласно#`
printed `огласно`. Its unclassified `others.tsv` words are now `WDсогласно`.

Do not put final `.`, `!`, or `?` in a literal phrase key to restrict sentence
end. The former Lua-only matching behavior has been removed. Use a native
grammatical context rule ending in `[*]`; punctuation is emitted separately.
`How's` expands to `how is`; smart apostrophes normalize at the encoding boundary.

## Whole-file phrase review lessons

Review every requested source row, including greetings and apparently simple
adverbial expressions. For each, record the intended sense/register, encoding
choice, positive case, relevant inflection/context cases, and reviewed result.
Do not use a handful of historical matches to exempt the rest of a file from
review. Native `D` phrases are legal and occur in `LTGOLD/BASE.DIC`, but their
presence does not justify freezing words that should participate in grammar.
Conversely, do not replace a suitable single-word `D` reading merely to make
every row look complex.

### Encode the grammatical structure

These tested entries illustrate distinct choices; copy their mechanism only
when the new expression has the same grammatical requirements:

```text
happy birthday*WPТсNденьPРNрождение
good morning*WAдобрыйNутро
good night*WPРAспокойныйNночь
best wishes*WAнаилучшийnпожелание
with*PТсJс помощью
thank you*Dспасибо
```

Birthday uses instrumental `с` governing `день`, then a silent genitive governor
for `рождение`; it is not `Dс днём рождения`. The silent `PР` in good night
produces genitive agreement without emitting a preposition. Best wishes stays
nominative alone, but structural `with` governs instrumental in “With best
wishes.” Freezing “с наилучшими пожеланиями” into best wishes duplicates `с`;
encoding with as literal `W` text prevents case government. Thank you retains
the appropriate single-word interjection reading. More tags are not inherently
better: the goal is a correct grammatical representation.

Check every lemma's active Russian morphology. For “Большое спасибо”, the
interjection reading alone did not provide noun agreement; nominal `спасибо`
needed an indeclinable neuter entry in `.RUS`, using the verified native paradigm
of `шоссе`. Update the generating source as well as the built dictionary, then
verify a rebuild reproduces the data. Do not substitute a frozen surface phrase
for missing lexical morphology.

Choose person, number and register deliberately. The curated imperative entries
currently produce informal singular “Извини меня”, “Будь здоров”, and
“Поправляйся скорее”; do not silently switch to formal/plural forms or modify
expected output to conceal a mistake. Generated OpenRussian forms currently
normalize `ё` to `е`; distinguish that data convention from failed inflection.

### Preserve native actions and constrain idioms

The spaces in `\ $ \` are executable action characters, not formatting. In the
what's up rule they delete context nodes around `$` anchor alignment; the final
backslash opens an empty selector. The exact concatenation was not found in
historical BASE.DIC, but its native components and execution were verified.
Use the [symbol-by-symbol breakdown](codes.md#native-boundary-rule-for-whats-up)
and original capture before changing unfamiliar punctuation. Do not claim an
entire authored rule is copied from the original just because its parts are native.

Generalize a grammatical family only as far as its meaning permits. A literal
“you are welcome” entry consumed the start of “You are welcome to stay.” A
boundary rule with `<X>` also matched “You were welcome.” The verified idiom is:

```text
you `are``welcome`[*]*$Dпожалуйста\  \
```

Its lexical anchors are intentional: they exclude past tense and longer
constructions while contraction normalization supports “You're welcome.” Typed
`XR` remains appropriate for the how greeting family. Test both positive
variants and nearby constructions that must remain outside the idiom.

Apply the same reasoning to clause-final idioms. Literal `after all` consumed
“After all the guests left”, and literal `not at all*Dнисколько` dropped the
negation in “It is not at all easy” (native LTPRO does the same). The verified
replacements are boundary subrules:

```text
after `all`[j,*]*$DDWPПвNконецPРnконец\ \
not `at``all`[,*]*$Dнисколько\  \
not `at``all`~[,*]*$DDWDсовсемKне\  .\
at `all`[PJj,C*]*$Dсовсем\ \
my `pleasure`[*]*$Dпожалуйста\ \
```

`[,*]` is the native comma-or-end class (historical ``besides [,*]``). After
a clause-initial `p` preposition the grammar retags the comma `j`, so `after`
needs `[j,*]` (historical ``as `it``is`[j,*)]``). A
generated literal with the same first words still wins lexically and hides
the subrule, so list it in `reference/openrussian/removed-headwords.txt`;
`--replace` only replaces identical keys. “My pleasure” answers thanks, so
`Пожалуйста` replaces the former “С удовольствием” (accepting an offer).

### Diagnose the layer before changing the entry

The full-file tests exposed these reusable failure modes. They have engine fixes;
use them as diagnostic leads, not reasons to add spelling-specific exceptions.

| Symptom | Verified cause and repair |
| --- | --- |
| A phrase starting with a silent case governor loses sentence capitalization | `core/output.lua` must capitalize the first visible component. |
| Рождество does not decline or Новый produces a malformed ending | `core/senses.lua` normalizes the Russian lemma for morphology while retaining its capitalization flag; grammatical code prefixes must keep their case. |
| Authored `в` changes to `на` in “in any case” | `core/agreement.lua` preserves explicit W prepositions instead of reselecting them from English locative heuristics. |
| A later English lexical rule deletes некоторое or changes retained it to это | `core/phrasing.lua` prevents lexical backtick rules from rewriting wholly inside an authored W equivalent; tag-based grammar still runs. |
| A comma after a `[,*]` subrule glues the next word (`Кроме того,он`) | Native marks the matched comma; `core/phrasing.lua` leaves a comma tail unmarked. |
| Two subrules both fire (`Нисколько Совсем`) | Native lets a later head rewrite a node an earlier subrule deleted; `core/phrasing.lua` skips heads retagged for deletion. |
| Москва stops declining after a capitalized-lemma fix | Keep exact capitalized `.RUS` headwords; lowercase only when the capitalized form is absent (`core/senses.lua`). |
| “Bless you” fails to generate an imperative or short adjective | `core/russian.lua` uses the available source aspect for imperative forms when the requested aspect is absent; `core/syntax.lua` gives the imperative copula a short predicate adjective (regular truncation then yields здоров). |

“How is it?” previously had a test accepting broken “Как у это?”; that did not
establish correctness. Its corrected Lua result is “Как у него дела?”, while
the preserved original capture still records “Как У Это?”. Review expected
strings linguistically and inspect grammatical metadata, rather than blessing
whatever the engine currently prints.

### Evidence and completion

Use `test/common_phrases_test.lua` as the coverage model: every nonblank source
entry maps explicitly to a regression case, and an uncovered entry fails the
test. Add relevant agreement/case, contraction/capitalization, partial-word,
protected-span, longest-match, and boundary cases; use `test/greetings_test.lua`
for retained variable metadata and alternative lexical readings. Inspect every
result, including supporting function-word entries. Source-only tests do not
prove that the rebuilt default dictionary contains or executes the new reading.

The [curated capture fixture](../../../test/ltpro/curated-phrases/README.md)
records the 43 entries reviewed at that time and 58 native cases, each captured twice. It
distinguishes experimental native assets from untouched LTGOLD assets and binds
reviewed Lua differences to dictionary hashes. Its 17 exact matches and 41
reviewed differences are not an exact-parity pass. Preserve previous captures
as historical evidence rather than overwriting them to fit new expectations.
The fixture's size-preserving omissions/padding are an isolated capture
workaround, not a dictionary-authoring rule or a change to shipped assets.

For negative controls, distinguish “the idiom did not fire” from “the whole
sentence translated well”. Longer welcome constructions and “For a while longer”
still expose unrelated translation limitations. Record such limitations without
claiming that nonmatching tests prove natural Russian. Report missing or failing
entry verification explicitly; do not call a file complete while its entries
remain unreviewed.

### Closed-class batches

A `function-words.txt` row replaces every record for its key, so leave out
words whose other readings matter (*like*, *down*, *near*) or pack those
readings into the one record as LTGOLD does (`like*PДподобноV11любить`).
Check what agreement reads besides the entry: в/на and из/с/от depend on the
noun's `.RUS` flags (bit 1 animate, bit 6 на-noun), so a correct preposition
can still print “на доме” when that data is wrong. A sentence-initial `p`
preposition turns its comma into `j`, and no subrule attaches to a
sentence-final head. Both are native behaviors confirmed by captures in
`test/ltpro/prepositions/`.

## Build and verify

Keep UTF-8 source rows, then rebuild the active index through the editor:

```sh
python3 tools/ltech_dict.py delete reference/openrussian/BASE.DIC \
  --keys-file reference/openrussian/removed-headwords.txt --in-place
python3 tools/ltech_dict.py import reference/openrussian/BASE.DIC \
  --entries reference/openrussian/function-words.txt --replace --in-place
python3 tools/ltech_dict.py import reference/openrussian/BASE.DIC \
  --entries reference/openrussian/phrases.txt --replace --in-place
python3 tools/ltech_dict.py check reference/openrussian/BASE.DIC
lua test/common_phrases_test.lua
lua test/greetings_test.lua
lua test/prepositions_test.lua
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
