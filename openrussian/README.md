# Full OpenRussian dictionary import

The checked-in source tables contain every row from the four public OpenRussian
backup exports: 26,982 nouns, 14,871 verbs, 11,941 adjectives, and 5,031 other
entries (58,825 source rows total). The C builder compiles them into standalone
indexed binary `.DIC` and `.RUS` databases. This snapshot produces 98,628 DIC
records, 53,492 native-format RUS records, and 58,772 compact morphology
records, including 4,978 shared templates.
The checked-in `BASE.DIC` applies 177 reviewed structural readings from
`function-words.txt` (pronouns, determiners, conjunctions, question words,
auxiliaries, modals, quantifiers, prepositions, and a few grammatical phrases),
replacing all records for those exact keys, 111 phrase entries from
`phrases.txt`, and 215 irregular verb forms from `irregular-verbs.txt`. It contains
98,241 DIC records after replacement.

OpenRussian is a Russian dictionary and has no English grammar: it coded `this`
as the adverb `сего`, `us` as `Америка`, `and` as `W`-text, and lacked `me`, `him`,
`was`, `does` and `could` altogether. The function-word batch takes LTGOLD's
native readings for these closed classes (`this*SэтоOэтот`, `me*M011я`,
`was*X103бытьx1быть`, `like*PДподобноV11любить`), without auxiliary stem
backreferences, plus native rules such as ``would <dDK>`like` `` (`хотел бы`). Two
additions cover native gaps: `do <TAO>[NRMS][,*]*$Vделать` reads `do` before an
object at a clause end as the verb (`Do it` → `Сделай это`), and `will do` keeps the
verb that grammar would otherwise delete after the auxiliary.

`removed-headwords.txt` also drops generated literals made of grammar words that
consume ordinary clauses, such as `this is`/`that is` → `это`, `to be` →
`исполниться`, `not to` → `беречься`, `you know` → `ведь`, and `the first` →
`первейший`. Fixed idioms (`each other`, `from now on`) and impersonal `it is …`
readings (`It is cold` → `Холодно`) stay. Native T4 rereads the first English
word of such a literal (original `It is cold.` → `Это.`). The Lua port keeps a
multiword literal's reading, as it does for authored `W` equivalents.

`.DIC` maps English glosses to Russian lexemes and literal expressions. `.RUS`
keeps the original indexed LTech format, with one-byte CP866 headwords and
native binary POS codes. The sibling `BASE.MORPH` carries OpenRussian morphology
references and shared templates. Each form is represented as a byte count to
trim from its headword and a one-byte CP866 suffix. Noun case slots and verb
tense, person, and imperative slots stay distinct; the runtime imperative flag
selects those imperative slots. The template records contain no copied source
columns, glosses, field names, or row IDs. For example, `people` maps directly
to `люди`, which keeps LTPRO's original plural-only noun code and paradigm 30.

## Source and encoding

The data is from repository commit
[`50e210c4803237779cb562bc1abcea529066031c`](https://github.com/Badestrand/russian-dictionary/commit/50e210c4803237779cb562bc1abcea529066031c),
licensed CC BY-SA 4.0. The upstream repository says these checked-in CSVs are
older backup exports; this import covers every row in those four files, not a
claim that the 2021 backup is the latest live OpenRussian database. The source
URLs and SHA-256 hashes are pinned in `upstream/manifest.json`; see
`upstream/ATTRIBUTION.md` for attribution details.

The source TSVs are UTF-8. Headwords and template suffixes remain one-byte
CP866 for the current Lua runtime. The importer removes combining stress marks
and transliterates characters CP866 cannot represent; 109 unsupported
codepoints in stored dictionary text were replaced in this snapshot. The
checked-in TSVs retain the complete UTF-8 source values.

## Download, build, and inspect

Clone the upstream data with GitHub CLI, verify its pinned CSV hashes, and
regenerate the complete TSV tables:

```sh
gh repo clone Badestrand/russian-dictionary /tmp/openrussian-source
python3 tools/export_openrussian_poc.py --full-snapshot /tmp/openrussian-source
```

Build the binary databases with `sh tools/rebuild_openrussian.sh` (add
`--verify` to check the checked-in files are reproducible). It runs:

```sh
cc -std=c11 -Wall -Wextra -Werror tools/openrussian_db.c -o /tmp/openrussian_db -liconv
/tmp/openrussian_db build openrussian/upstream \
  openrussian/BASE.DIC openrussian/BASE.RUS \
  openrussian/BASE.MORPH
python3 tools/ltech_dict.py delete openrussian/BASE.DIC \
  --keys-file openrussian/overlays/removed-headwords.txt --in-place
python3 tools/ltech_dict.py import openrussian/BASE.DIC \
  --entries openrussian/overlays/function-words.txt --replace --in-place
python3 tools/ltech_dict.py import openrussian/BASE.DIC \
  --entries openrussian/overlays/irregular-verbs.txt --replace --in-place
python3 tools/ltech_dict.py import openrussian/BASE.DIC \
  --entries openrussian/overlays/phrases.txt --replace --in-place
```

`removed-headwords.txt` lists generated OpenRussian literal phrases that would
consume input before a curated T4 subrule can see it (for example the builder's
`you are welcome*WDпожалуйста`). A curated subrule has a different key, so
`--replace` cannot remove those literals. Always rebuild from the C builder
output; this sequence reproduces the checked-in `BASE.DIC` byte for byte.

Rows from `others.tsv` have no part of speech. The builder emits each as a
one-component `W` composite with native adverb class `D` (`at all*WDсовсем`),
following LTGOLD's usual `D` coding for such words; the `W` wrapper keeps
reordering from moving these unclassified prepositions and conjunctions.
A one-word adverb is a plain `D` instead, as in LTGOLD (`always*Dвсегда`): native
rules like `X D V` do not see through a `W` composite, so `Russia will always
supply fuel` read `supply` as a noun. Every `-ly` word and the words in
[`plain-adverbs.txt`](overlays/plain-adverbs.txt) get plain `D`; other unclassified words keep `W`. It
formerly emitted `W#…#`, but native `#` marks nontranslated names and reads a
leading с/м/ж as gender, so 542 readings lost their first letter
(`according to` → `огласно`).

`info FILE` reports the binary image size and record count; `find FILE HEADWORD`
shows matching dictionary records. The builder also adds a few high-priority
English function-word and common-verb readings so source homonyms do not
override the translator's basic grammar.

Each imperfective `.RUS` verb record names its perfective partner after the
code, as LTGOLD does (`видеть*V\xc1\x88\xbc\x80увидеть`). The builder takes it from
the source `partner` column: the first perfective partner that names the verb
back, else the first perfective partner (`видеть` → `увидеть`, not `завидеть`;
`говорить` → `сказать`). `senses.lua` follows it when grammar requests perfective
aspect, so the future after `will` is `Мы увидим`, not the malformed `видеем`, and
clause-initial imperatives are perfective (`Сделай`), as in the original. An
entry that must stay imperfective names it on both sides of the native `|`
alternative (`get well soon*WVпоправляться|поправлятьсяDскорее`).

Verb records also carry LTGOLD's aspect flags: `0x04` on perfective verbs and
`0x08` on verbs with no partner, which `senses.lua` uses to force the aspect.
An imperfective-only verb then takes the analytic future (`I'll work` →
`Я буду работать`, as in the original). The future auxiliary comes from the
native быть paradigm, since OpenRussian lists `есть` in every present/future
slot. [`imperfective-only.txt`](overlays/imperfective-only.txt) lists the 152 imperfective
verbs that LTGOLD codes without a partner although the source names one
(`работать` would otherwise pair with `поработать`). The partner column mixes
`;`/`,` and stress marks; [`verb-partners.txt`](overlays/verb-partners.txt) adds pairs it
lacks (`идти пойти`).

A one-word key whose first reading is a noun and that also has a verb reading
gets LTGOLD's ambiguous record first, verb reading leading
(`work*ZV.работатьN.работа`, like the original's `work*ZV.работать…N.работа…`),
so grammar chooses: `Я работаю`, `Моя работа`. OpenRussian emits one record per
reading with nouns first, and only the first is used, so 1,580 verbs such as
`work`, `go` and `call` were unreachable. The builder's high-priority readings
use native classes: `want*V21хотеть`, `wants*vхотеть`.

The reading a generated record uses is chosen by sense, not file order. The
source tables are sorted by frequency (`source_row`), and a row that lists the
key as its first gloss gives that key's primary sense. The builder takes the
primary reading unless it is much rarer than the most frequent row listing the
key among its first glosses (10× for verbs, 2× otherwise): `call` → `звать`
(not `называть`), `supply` → `доставлять`, `visit` → `посещать` (`бывать` lists
"visit" third), but `stay` → `оставаться` (not `гостить`) and `photograph` →
`фотография` (not `фотокарточка`). A noun that is never a primary sense of the key
is dropped beside a primary verb, as in LTGOLD's `go*Vидти` (`Let's go` no longer
gives `изюминка`). `need` uses LTGOLD's impersonal `need*xнужноNнеобходимость`
(`Мне нужна помощь`).

A verb-headed key also becomes `Z` when it has a noun or adjective whose primary
sense it is; an adjective joins only when no noun has that primary sense, or noun
adjuncts turn adjectival (`the house door` → `домашняя дверь`). So
`blind*ZV.ослеплятьA.слепой` (LTGOLD `blind*ZслепитьNштораAслепой`) gives
`Любовь слепая`. The builder's curated readings (`want*V21хотеть`) stay as they
are.

`home` uses LTGOLD's packed `home*NдомAдомашнийDдомой`. As in LTGOLD, direction
comes from verb phrases, here with tagged components rather than its frozen tail:
`go home*WVидтиDдомой`, `come`, `walk`, `run`, `return`, `get`, `hurry`, `fly home`,
reached from irregular forms through the stem backreference (`He went home` →
`Он шел домой`). `am/is/are/was/were/be home` and `stay home` give `дома`
(`Она была дома`). The original prints the same for the captured cases.
Questions keep the auxiliary until T4, so native subrules on `is/are/am/was/were`
read bare `home` after a subject at a clause end as `дома`:
``is [RN?#]`home`[D,*]*$@\.`Dдома`\`` (`Is he home?` → `Он дома?`, as in the
original) and ``is [TO]N`home`[D,*]`` (`Is the dog home?` → `Собака дома?`). An
article keeps the noun (`Is he a home?` → `Он дом?`). Question cleanup drops a
present `are` before `the` + noun, so `Are the kids home?` stays unhandled, and
past questions lose their copula generally (`Was he here?` → `Он здесь?`).

`let us` (and `let's`) is native T4 rule 83, which gives `давайте` plus an
infinitive (original `Давайте идти`). The Lua port makes the next verb first
person plural perfective, the Russian hortative (`Давайте пойдем`, `Давайте
прочитаем книгу`), and keeps the infinitive for a verb with no perfective
(`Давайте работать`). The generated `let us*WDдавай` literal is removed.

Verbs are coded `V`, as in LTGOLD. Native `e` marks a verb whose base form is
also its past or participle (`come`, `read`, `put`), and the builder keeps it only
for those 13 words; coding every verb `e` made a clause-initial imperative a
participle (`Give me the book` → `Данное мне книгой`, now `Дай мне книгу`). When a
key's first verb is perfective, its imperfective partner goes first
(`come*e00приходить`, as in LTGOLD), so `He comes` is present `приходит`.
OpenRussian's unclassified `others.tsv` adverbs are imported first and hid the
verb or adjective of 152 basic words (`open` → `открыто`, `new` → `внове`).
[`content-first.txt`](overlays/content-first.txt) lists 307 words: those LTGOLD codes as verb,
adjective or `Z`, plus noun-headed adjectives it codes `A`/`d` (`ready`); for
those the builder puts the `Z` record (with noun and adjective readings) or the
adjective first. Unlisted adverb-headed words keep the adverb, since LTGOLD does
for `please`, `welcome` and `again`.

[`irregular-verbs.txt`](overlays/irregular-verbs.txt) holds 215 irregular English verb
forms from LTGOLD's native readings (`went*hидти\go`, `gave*hдавать\give`,
`left*EоставатьсяAлевый\leave`), imported after the function words. Misspelled
or regular LTGOLD keys are omitted, and `V.` readings keep only the sense that
matches the base verb (`built*Eстроить\build`, not LTGOLD's first
`разрабатывать`). Their stem backreferences reach generated stem phrases, so
`come to` (`очнуться`), `go into` and `have seen` are removed. The personal
pronouns carry LTGOLD's possessor and dative readings (`i*R011яrу меняmмне`), so
`I have a book` → `У меня есть книга`. Unlike the original, a question's future
verb is perfective (`Will you come?` → `Ты придешь?`).

The same ambiguity hides gerunds. A noun gloss in -ing (`reading` → `чтение`)
shadowed the verb's own -ing form, so `He is reading the book` printed
`Он - чтение книга`. The builder emits LTGOLD's ambiguous record
(`reading*GчитатьNчтение\read`) for every such gloss whose stem, with or without
a restored `e` or doubled consonant, is a verb. Grammar still reads the noun
where native rules do (`He stopped reading the book` → `остановил чтение`, as
in the original), and the progressive works (`Он читает книгу`). The native
suffix rules cannot reach `-ed`/`-ing` of verbs that end in a doubled consonant
(call, kill, pass) or `-ie` (lie), so the builder lists those forms as LTGOLD
does (`called*Eзвать\call`). A phrasal verb whose first source reading is
perfective (`knock out`) puts its imperfective partner first, like one-word
verbs. LTGOLD's `stop G*$Vпереставать\V` makes `stop knocking out` an infinitive
(`перестать выбивать`).

Capitalized OpenRussian lemmas (`Россия`) are stored in `.RUS` and `.MORPH`
under lowercase headwords, as LTGOLD stores them (`россия`). The runtime lowers
a capitalized `.DIC` lemma and reads gender and paradigm from the lowercase
headword; with the capital headword it found nothing, and `Russia announced`
agreed with a neuter verb.

Four more repairs close gaps the source tables leave:

- [`native-readings.txt`](overlays/native-readings.txt) takes LTGOLD's own record
  where OpenRussian has none or ranks the wrong sense first (`both*Iоба`,
  `rising*GподниматьсяAрастущий\rise`, `refinery`, `marketplace`, `export*…Aэкспортный`
  so `export bans` is adjectival, `million*I1…`). It is imported after the
  irregular verbs with `--replace`, like the function words.
- OpenRussian leaves the gender of 5,122 nouns empty, which became neuter
  (`Главное фактор`). The builder reads it off the lemma ending (`а/я/сть` feminine,
  `о/е/мя` neuter, otherwise masculine).
- OpenRussian has no valency, so every verb was coded transitive (`0x88`), and
  `Help me` printed `Помоги меня`. [`verb-government.txt`](overlays/verb-government.txt)
  carries LTGOLD's government byte for the 946 shared verbs whose case differs from
  the plain accusative (dative `0x84`, instrumental `0x90`, intransitive `0x80`);
  regenerate it with `tools/export_verb_government.py`.
- An English `-ed` or `-ing` gloss that is also a verb's inflected form
  (`opened*WDоткрыто`, `reading*Nчтение`) hides the verb. The builder emits
  LTGOLD's ambiguous record (`opened*EоткрыватьAоткрытый\open`), verb first.

The native participle tables are indexed by a paradigm number that OpenRussian
lexemes lack. `generation.lua` therefore derives the long masculine participle
from the lexeme's own forms (`определить` → `определенный`, `открыть` → `открытый`,
present passive `-емый`, active `-ющий`/`-вший`) and lets the native adjective
and short-form code agree it (`Дверь закрыта`, `Условия определены`).

Native T3 rule 78 reads `that` after a verb as a demonstrative unless the verb
has a nonzero frame digit (`know*V1знать`, `decide*V11решать`); OpenRussian verbs
have frame 0, so `They know that Russia will help` printed `знают этой России`.
[`verb-frames.txt`](overlays/verb-frames.txt) carries the 65 verbs LTGOLD codes with a
frame (`tools/export_verb_frames.py`); the builder writes the digit into their
verb, `Z`, `-ed` and `-ing` records.

Some plural nouns are their own OpenRussian glosses (`works` → `производство`).
Such a literal shadowed suffix analysis of the verb's -s form (“He works” →
`Он производство`). For a one-word -s gloss whose stem is a verb gloss, which is
not itself a verb gloss and whose noun the stem lacks, the builder puts a native
ambiguous v/n record first (`works*zработатьnпроизводство\work`, after LTGOLD's
`accesses*zуправлятьnдоступ\access`); grammar chooses `Он работает` or
`Производства`. The verb is the stem's first imperfective reading, since a
perfective present reads as future (`leaves` → `выходит`, not `выйдет`). When the
stem already has the noun (`conditions` → `условие`) the literal adds nothing and
is left alone; coding it `z` read “terms and conditions” as a verb.

`will` and `shall` use LTGOLD's auxiliary `X203быть`, and `not` its particle
`KнеDнет`; the imported `will*Nволя` and `not*WDне` printed `Мы воля` and broke
negated futures. The noun sense comes from LTGOLD's ``against <AO>`will` ``
subrule and `against ~ will` literal in `phrases.txt`. As in the original, “His
will is strong” does not get it. LTGOLD's matching `of <AO>`will`` rule is
omitted: it turned “a test of his will” into `по своей воле`.

## Prepositions and noun flags

Each preposition in `function-words.txt` is one native record: class `P` or
`p`, the governed case, and the Russian preposition, with packed alternatives
where the original uses them (`for*PРдля`, `of*PР`,
`after*pРпослеDвпоследствииJ2после того, как`). LTGOLD's entries are evidence;
deliberate differences, omitted homographs, and original captures are in
[preposition verification](../test/ltpro/prepositions/README.md).

Agreement chooses в/на and из/с/от from noun flags in `.RUS`: bit 1 (`0x02`)
marks animates and bit 6 (`0x40`) nouns that take на. The builder sets the
first from OpenRussian `animate` and the second from the curated
[`na-nouns.txt`](overlays/na-nouns.txt), read from `overlays/`. It
previously wrote `0xc0` for every noun.

## Curated phrases

Keep reviewed UTF-8 `english key*reading` rows in `phrases.txt`; keep structural
function-word readings in `function-words.txt`. Apply both batches after the C
build. Import converts to CP866, replaces exact keys, and rebuilds the `.DIC`
index. Repeating an import is safe. `.RUS` and `.MORPH` contain Russian
morphology; English-to-Russian phrases belong in `.DIC`.

```text
how XR[*]*$Dкак\`PР01у``MMWMJ0nдело`\
what <X>`up`[*]*$DDWDкакnдело\ $ \
```

Both entries use native T4 dictionary subrules, tested in original LTPRO.
The first is one grammatical family: auxiliary **X**, personal pronoun **R**,
and sentence boundary `[*]`. **P** means preposition; **B/b** mean infinitival
`to`. The head becomes `Dкак`. Backticked context actions supply `PР01у` and
change the pronoun to an `M` composite reading while preserving its node's
number/person/gender. The empty `M` component uses those fields for normal
oblique pronoun generation. `J0` closes the prepositional group before plural
`nдело`, so morphology generates nominative `дела`. The default `you` is informal
singular. The custom pre-T1 retained-slot execution path has been removed.

Original LTPRO executes this construction but produces `у его/ее/их` in the third
person. Lua's agreement/generation fixes give `у него/неё/них`. The translations
intentionally improve those forms and phrase casing while using native syntax.
Native rule order still affects `How is it?`: a later sentence-final `it` rule
overrides the composite, producing original `Как У Это?`. Lua preserves the
authored equivalent and generates `Как у него дела?`; the regression also checks
`How's it?`.

The imported default readings previously classified `are` as a noun, `is` as a
lexical verb, and `you` as fixed `W` text. Those readings could not satisfy the
`X/R` pattern. The reviewed function-word batch supplies real auxiliary and
pronoun readings, also available to ordinary grammatical rules outside greetings.
It avoids auxiliary backreferences into imported stem idioms such as the
unrelated `be in` gloss. The historical LTGOLD dictionaries remain unchanged.

`How's` expands to `how is`; smart apostrophes normalize at the encoding boundary.
`[*]` excludes `How are you feeling?` and similar longer clauses. The grammatical
rule also accepts a period, exclamation mark, or no final punctuation. The
`what` idiom uses a native T4 context rule: `<X>` allows the auxiliary to remain
or have been removed by question cleanup, lexical `up` identifies the idiom,
and `[*]` requires sentence end. The native tail action removes its context
words. `What's up there?` is excluded. Final punctuation is emitted separately;
the former Lua-only punctuation-key matcher has been removed.

`test/greetings_test.lua` checks the default dictionary, retained metadata,
additional lexical pronoun readings, contractions, case generation, casing, and
nearby inputs. These phrases intentionally improve on the original translator;
original captures remain separate. The
[dictionary-writing skill](../skills/ltgold-dictionary-writing/SKILL.md)
records manual references and the authoring workflow.

The complete source has 67 `W` composites, 24 native T4 subrules, and 20
single-word `D` equivalents. The only uninflected tail is the invariant
infinitive in `nice to meet you*WDприятно познакомиться`: a `V` component would
become imperative sentence-initially (`Приятно познакомься`).
For example, `happy birthday*WPТсNденьPРNрождение` gives instrumental `день`
and genitive `рождение`; `best wishes*WAнаилучшийnпожелание` agrees and declines
after `with`. The structural `with*PТсJс помощью` reading supplies instrumental
government. The builder also adds nominal `спасибо` as a neuter indeclinable
noun, using native no-declension metadata, so `AбольшойNспасибо` agrees normally.

The `you` subrule requires lexical `are`, `welcome`, and a final boundary. It
accepts `You're welcome.` without consuming `You are welcome to stay.` or
`You were welcome.`. Imperatives use normal morphology and the default informal
register: `Извини меня.`, `Будь здоров.`, and `Поправляйся скорее.`. The composed
past greeting spells out its subject: `Мы давно не виделись.`. OpenRussian
normalizes ё to е in generated forms, including `С днем рождения.`.

`test/common_phrases_test.lua` checks every source entry, capitalization,
contractions, punctuation, longest-phrase selection, and protected/partial-word
nonmatches. Original-program evidence, the per-entry review, known differences,
and isolated fixture construction are in
[curated-phrase verification](../test/ltpro/curated-phrases/README.md).
Some entries deliberately choose historical senses: `by the way` becomes
`между прочим` and `after all` becomes `в конце концов`.

Clause-final idioms are boundary subrules rather than literal keys, so they do
not consume a following construction. `after `all`[j,*]` matches before a comma
or sentence end but leaves “After all the guests left” alone. `not at all` has
two native subrules: standalone `Нисколько.` before `[,*]`, and `совсем не`
otherwise, so “It is not at all easy” keeps its negation. The native
``at `all`[PJj,C*]`` rule covers clause-final “at all”. `my `pleasure`[*]`
answers thanks with `Пожалуйста.` without consuming “My pleasure is great.”
The builder's literal `not at all`, `at all`, and `after all` readings are removed
before import.

The everyday batch adds farewells, wishes, and time adverbials. A single-word
key needs its input class before `W` (`goodbye*DDWPРдоNсвидание`); a bare `W`
reading printed `Рдо`. After a sentence-initial `P` preposition such as `at` or
`in`, the comma is retagged `;`, so `at `last``, `at `the``moment`` and
`in `the``end`` use `[j;,*]` (native `;` occurs in historical `[;:*]`).
`in the end` is a boundary subrule so “In the end of the street” keeps its
noun. `no `problem`[,*]` leaves “There is no problem.” alone; original LTPRO
prints `Нет.` for “No problem.” because its own `no` handling wins. The
“see you later” family is not added: native T4 rule ``[*,:;("]<D>`see` ``
rewrites a sentence-initial `see` to `Vсмотри` after any head subrule, and a
literal key would consume “I will see you later.” Original captures for the
batch are reviewed differences in casing and morphology (`До Свидание`,
`сладких сон`); Lua generates `До свидания`, `Сладких снов`.

Original LTPRO differs from Lua for these subrules in two engine respects. It
marks a matched comma so the next word is glued to it (`Нисколько,благодарности`),
and a later subrule can resurrect a node an earlier subrule deleted in the same
pass (`Нисколько Совсем.`). Lua keeps normal comma spacing and skips deleted
heads. A sentence-initial `p` preposition such as `after` makes the grammar
retag its comma as clause junction `j`, so the rule uses native `[j,*]`
(compare historical ``as `it``is`[j,*)]``); with `[,*]` the original printed
“После все, он знает.”

## Parity examples

The original LTPRO captures and exact comparison cases are checked in:

- 20 noun/verb sentences: `test/ltpro/openrussian-cases.json` and
  `test/ltpro/openrussian-reference.json`
- Four phrases: `test/ltpro/openrussian-phrase-cases.json` and
  `test/ltpro/openrussian-phrase-reference.json`
- Five additional words and sentences from the full tables:
  `test/ltpro/openrussian-full-cases.json` and
  `test/ltpro/openrussian-full-reference.json`

These 29 captures describe the generated full tables before the curated
function-word corrections. They remain historical evidence; changes to closed
classes can intentionally change their Lua results. They do not verify every
English gloss or expression. OpenRussian
word senses can differ from LTPRO's older choices; for example, OpenRussian
maps `because` to `потому что`, while this LTPRO build uses `поскольку`.
Exploratory full-vocabulary checks also exposed unresolved ambiguity and word
order cases: `City.` currently selects `городской`, and `Cold water.` is
reordered. These remain translation-quality issues despite the complete import.

```sh
python3 tools/ltpro_pipeline_probe.py \
  --cases test/ltpro/openrussian-cases.json \
  --reference test/ltpro/openrussian-reference.json \
  --data LTGOLD \
  --dictionary openrussian/BASE.DIC \
  --russian openrussian/BASE.RUS
python3 tools/ltpro_pipeline_probe.py \
  --cases test/ltpro/openrussian-phrase-cases.json \
  --reference test/ltpro/openrussian-phrase-reference.json \
  --data LTGOLD \
  --dictionary openrussian/BASE.DIC \
  --russian openrussian/BASE.RUS
python3 tools/ltpro_pipeline_probe.py \
  --cases test/ltpro/openrussian-full-cases.json \
  --reference test/ltpro/openrussian-full-reference.json \
  --data LTGOLD \
  --dictionary openrussian/BASE.DIC \
  --russian openrussian/BASE.RUS
```
