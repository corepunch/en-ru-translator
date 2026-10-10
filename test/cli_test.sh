#!/bin/sh
# Exercise the public CLI boundary; expected text comes from the native corpus.
set -eu
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
# The original capture in test/ltpro/prepositions/reference.json.
expected='Шаг по отношению к дому.'
[ "$(lua init.lua 'A step toward the house.')" = "$expected" ]
[ "$(printf '%s' 'A step toward the house.' | lua init.lua --data=LTGOLD)" = "$expected" ]
[ "$(lua init.lua --dic=LTGOLD/BASE.DIC --rus LTGOLD/BASE.RUS -- 'A step toward the house.')" = "$expected" ]
# An unknown capitalized word stays Latin, as in LTPRO; --names transliterates it.
[ "$(lua init.lua 'Xylophornium is here.')" = 'Xylophornium - здесь.' ]
[ "$(lua init.lua --names 'Xylophornium is here.')" = 'Ксилофорниум - здесь.' ]
[ "$(lua init.lua --topic=BUSINESS 'Advising bank.')" = 'Авизующий Банк.' ]
# The phrase add-on dictionary/BASE2.DIC loads by default; --base-only and
# --original leave it out.
[ "$(lua init.lua "What's up?")" = 'Как дела?' ]
[ "$(lua init.lua --base-only "What's up?")" = 'Какое по?' ]
[ "$(lua init.lua --original "What's up?")" = 'Какое по?' ]
# The improved reading by default; --original gives the executable's own.
[ "$(lua init.lua 'The noncat is good.')" = 'Некошка хорошая.' ]
[ "$(lua init.lua --original 'The noncat is good.')" = 'НеКошка хорошая.' ]
lua init.lua --help > "$scratch/help"
# A document keeps the last sentence end's separator for an unterminated line.
printf 'The cat.\n\nAGREEMENT\n' > "$scratch/document"
[ "$(lua init.lua --document "$scratch/document")" = "$(printf 'Кошка.\n\nСОГЛАШЕНИЕ.')" ]
[ "$(lua init.lua --document < "$scratch/document")" = "$(printf 'Кошка.\n\nСОГЛАШЕНИЕ.')" ]
lua init.lua --dic LTGOLD/BASE.DIC --rus LTGOLD/BASE.RUS --meanings 'I agree.' > "$scratch/meanings"
case "$(cat "$scratch/meanings")" in *agree*) ;; *) exit 1 ;; esac
[ "$(lua init.lua '{~Keep  CASE~}.')" = 'Keep  CASE.' ]
[ "$(lua init.lua '{~\2 {~one~} {~two~}')" = "$(printf 'one\ttwo')" ]
case "$(lua init.lua --dic LTGOLD/BASE.DIC --rus LTGOLD/BASE.RUS --domain=инф admission)" in доступ*) ;; *) exit 1 ;; esac
lua init.lua --no-prefixes 'Two books.' > "$scratch/no-prefixes"
lua init.lua --prefixes LTGOLD/ERPREFIX.PRE 'Two books.' > "$scratch/prefixes"
cmp "$scratch/no-prefixes" "$scratch/prefixes"
for option in --ltpro --debug --dict; do
  if lua init.lua "$option" 'Two books.' > "$scratch/out" 2> "$scratch/error"; then
    echo "Unexpectedly accepted retired option: $option" >&2
    exit 1
  fi
  [ ! -s "$scratch/out" ]
  [ -s "$scratch/error" ]
done
if lua init.lua < /dev/null > "$scratch/out" 2> "$scratch/error"; then
  echo 'Empty CLI input unexpectedly succeeded' >&2
  exit 1
fi
[ ! -s "$scratch/out" ]
echo 'CLI tests passed'
