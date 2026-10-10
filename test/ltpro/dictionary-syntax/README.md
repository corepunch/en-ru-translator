# Dictionary syntax probes (issue 18)

Minimal pairs that settle the open questions about LTGOLD dictionary syntax.
Each probe in `probes.json` installs a few rows (or deletions, or single
`BASE.RUS` byte edits, or extra switches) into isolated copies of the supplied
LTGOLD assets. `reference.json` holds original LTPRO output for all 119 inputs,
each byte-identical in two runs. The supplied assets are never modified.

`test/dictionary_syntax_test.lua` rebuilds the same dictionaries in memory and
runs the Lua engine on LTGOLD's own BASE.DIC/BASE.RUS: **112 exact matches and
7 reviewed differences**, each with its reason in `reviewed-differences.json`.
The test fails when a reviewed difference starts to match or changes.

Findings are recorded in the
[code reference](../../../skills/dictionary-writing/references/codes.md).

| Item | Probes | Result |
| --- | --- | --- |
| 1. Sections after the selector | `third-section-*`, `stock` | Only the first character after the second backslash is read. `` \$`Dпамяти` `` changes nothing; the same edit in the tail action applies. The 7 historical rules with such sections (`bear`, `ask`, `cause`, `make`, `prevents`, `a few`, `as far as`) behave exactly as without them. |
| 2. Selector `2`; `N`/`V` | `selector-*` | `2` in selector position applies the rule only when the last matched node is plural; in a fourth section it is ignored. `N`, `V`, `$`, `?` and space have no handler. |
| 3. Punctuation classes | `stock` | Input punctuation is its own tag (`%`, `(`, `)`, `:`, `"`, `'`). `_` is a word with a leading underscore, `^` a boundary inserted before a preposition by T4 handler 2, `{}` T2's `(#)` rewrite. |
| 4. Cyrillic `С` | `cyrillic-es-class`, `latin-c-class` | A typo: it never matches the conjunction tag `C`. The two rules are also shadowed by literal `in writing`. |
| 5. Domain labels | `automatic-meanings-*` | `инф)`/`дел)` meanings are preferred under `/AM` with COMPUTER/BUSINESS second in the `/C` chain. Lua `--domain инф`/`дел` gives the same choices. |
| 6. Class prefixes and reading punctuation | `single-class-prefix`, `no-class-prefix`, `reading-punctuation` | `NNWA` = input class `N` + class of the composite reading. `,A` prints a comma. `word*:` is a phrase-head placeholder. `\|` is a fixed separator class: `faster than*\|…` keeps the copula dash and reads `light` as a noun, where `D` gives `Это быстрее чем светлый`. The `-` in `are*X013-` has no observed effect. |
| 7. Verb digits | `verb-digits-removed` | The first verb digit selects the object + `to` complement: `2` чтобы-clause, `1` что-clause; a second digit `1` keeps a bare infinitive. `U1`/`U12` give the conditional `мог бы`. |
| 8. `.RUS` bits | `rus-*` | Verb `0x08`: future with `буду`; without it a partnerless verb's present serves as future. Adjective `0x20`: short form always; `0x01`: short form as present predicate after a noun/pronoun. |
| 9. `c g i p` | `lowercase-tags-uppercased` | `c` leaves a following verb infinitive; `g` is an adverbial participle (`включая`); `i` takes singular agreement; `p` reads as the clause conjunction before a clause. |
| 10. Transliteration | `transliteration-override`, `stock` | Text after `=` replaces the transliteration (`Эйб`); `%` forces it (`Смизерс`). Historical `abe*#0m=эйб` has a Latin `m`, so it prints `Abe`. `/L-`, `/MM` and `/SM` do not change batch output, so inline `{1.…}` alternatives and the appendix are on in the supplied profile; which `LTGOLD.CNF` byte enables them is not isolated (LTPRO produces no output without that file). |

The probes also exposed four Lua defects, now fixed: leading-underscore words
were `#` instead of unknown `?`; a W phrase after a silent sentence-initial
article lost the sentence capital; `word*:` placeholders printed nothing; and
transliterated multiword names lost the capital of later words.

## Reproduce

```sh
python3 test/ltpro/dictionary-syntax/capture.py
lua test/dictionary_syntax_test.lua
```

Capture requires DOSBox-X and the supplied LTGOLD assets, including
`COMPUTER.DIC` and `BUSINESS.DIC`. It replaces `reference.json`; the
Lua test never launches DOSBox-X.
