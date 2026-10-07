#!/bin/sh
# Exercise the public CLI boundary; expected text comes from the native corpus.
set -eu
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
expected='Он - в доме.'
[ "$(lua init.lua 'He is in the house.')" = "$expected" ]
[ "$(printf '%s' 'He is in the house.' | lua init.lua --data=LTGOLD)" = "$expected" ]
[ "$(lua init.lua --exe LTGOLD/LTPRO.EXE --dic=LTGOLD/BASE.DIC --rus LTGOLD/BASE.RUS -- 'He is in the house.')" = "$expected" ]
lua init.lua --help > "$scratch/help"
lua init.lua --meanings 'I agree.' > "$scratch/meanings"
rg -q 'agree' "$scratch/meanings"
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
