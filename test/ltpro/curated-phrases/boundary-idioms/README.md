# Boundary-idiom verification

Repeated original LTPRO captures (two byte-identical runs each) for the
subrules that replaced literal `after all`, `not at all`, and `my pleasure`:

```text
my `pleasure`[*]*$Dпожалуйста\ \
not `at``all`[,*]*$Dнисколько\  \
not `at``all`~[,*]*$DDWDсовсемKне\  .\
at `all`[PJj,C*]*$Dсовсем\ \
after `all`[,*]*$DDWPПвNконецPРnконец\ \
```

`untouched-reference.json` uses the supplied historical assets. Its native
literals drop the negation (`Нисколько легко.`) and consume
`After all the guests left`. `reference.json` uses the experimental assets
built by `build_fixture.py`: the five rows above are installed, the literal
`not at all`, `at all`, `after all`, and `my pleasure` keys are deleted, and
unused `z` headwords are omitted to keep the image size.

| Input | Experimental original | Current Lua |
| --- | --- | --- |
| Not at all. | Нисколько Совсем. | Нисколько. |
| Not at all, thanks. | Нисколько Совсем,благодарности. | Нисколько, спасибо. |
| It is not at all easy. | Это - совсем не легко. | Оно - совсем не легко. |
| She does not read at all. | Она не читает совсем. | (unrelated verb defects) … совсем. |
| After all. | В Конце концов. | В конце концов. |
| After all, he knows. | После все, он знает. | В конце концов, он знает. |
| After all the guests left. | После всех гостей оставшихся. | not matched |
| He knows after all. | Он знает в конце концов. | Он знает в конце концов. |
| My pleasure. | Пожалуйста. | Пожалуйста. |
| My pleasure is great. | Мое удовольствие большое. | not matched |

The two deliberate Lua differences are engine fixes: native lets the later
`at` subrule rewrite a node the `not` subrule deleted, and native marks a
matched comma so the next word is glued to it. Native also did not apply the
`after all` subrule before a comma. Its historical `after*p…` reading makes
the grammar retag that comma as clause junction `j`; the current source uses
`after `all`[j,*]`, which Lua applies to “After all, he knows.” These
captures preserve the earlier `[,*]` row.

```sh
fixture_dir=$(mktemp -d /tmp/boundary-idioms.XXXXXX)
python3 test/ltpro/curated-phrases/boundary-idioms/build_fixture.py "$fixture_dir"
python3 tools/ltpro_capture.py --data "$fixture_dir" \
  --cases test/ltpro/curated-phrases/boundary-idioms/cases.json \
  --output "$fixture_dir/reference.json" --repeat 2 --timeout 60
```
