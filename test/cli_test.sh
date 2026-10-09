#!/bin/sh
# Exercise the public CLI boundary; expected text comes from the native corpus.
set -eu
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
expected_openrussian='Он - в дом.'
expected_ltech='Он - в доме.'
[ "$(lua init.lua 'He is in the house.')" = "$expected_openrussian" ]
[ "$(printf '%s' 'He is in the house.' | lua init.lua --data=LTGOLD)" = "$expected_openrussian" ]
[ "$(lua init.lua --exe LTGOLD/LTPRO.EXE --dic=LTGOLD/BASE.DIC --rus LTGOLD/BASE.RUS -- 'He is in the house.')" = "$expected_ltech" ]
lua init.lua --help > "$scratch/help"
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
