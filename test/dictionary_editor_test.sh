#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
LUA=${LUA:-lua}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
# Include spaces and a quote to check that the lock does not interpolate input.
cp -R dictionary "$tmp/dictionary's copy"
data="$tmp/dictionary's copy"
editor() { "$LUA" tools/dictionary.lua --data "$data" "$@"; }
translate() { "$LUA" init.lua --data "$data" "$1"; }
failed() {
    if "$@" >"$tmp/stdout" 2>"$tmp/error"; then
        echo "unexpected success: $*" >&2
        exit 1
    fi
    test ! -s "$tmp/stdout"
}

editor --json validate | grep -q '"valid":true'
editor --json dict select OPEN --pos verb | grep -q '"target":"открывать"'
editor dict select ope --prefix --limit 2 | grep -q 'open'
editor --json rus select ЧИТАТЬ --pos verb | grep -q '"name":"imperative.singular","text":"читай"'
editor schema --pos verb | grep -q 'short_passive.feminine'
test "$(editor --json dict select zzzlexprobe)" = '[]'
editor dict insert zzzlexprobe --pos noun --target Книга
test "$(translate 'There is a zzzlexprobe here.')" = 'Здесь есть книга.'
failed editor dict insert zzzlexprobe --pos noun --target книга
grep -q 'already exists' "$tmp/error"
editor dict update zzzlexprobe --pos noun --target книга --to дверь
test "$(translate 'There is a zzzlexprobe here.')" = 'Здесь есть дверь.'
editor dict delete zzzlexprobe --pos noun --target дверь
test "$(editor --json dict select zzzlexprobe)" = '[]'
editor dict reset zzzlexprobe --pos noun --target дверь
editor dict reset zzzlexprobe --pos noun --target книга

editor dict delete mailbox --pos noun --target ящик
if editor dict select mailbox --pos noun | grep -q '→ ящик'; then exit 1; fi
editor dict reset mailbox --pos noun --target ящик
test "$(translate 'There is a small mailbox here.')" = 'Здесь есть небольшой почтовый ящик.'

editor rus update открывать --pos verb --form imperative.singular=открой
editor --json rus select открывать --pos verb | grep -q '"name":"imperative.singular","text":"открой"'
test "$(translate 'Open the report.')" = 'Открой отчёт.'
editor rus update открывать --pos verb --drop-form imperative.singular
if editor rus select открывать --pos verb | grep -q 'imperative.singular'; then exit 1; fi
editor rus reset открывать --pos verb
test "$(translate 'Open the report.')" = 'Открывай отчёт.'
editor rus insert пробослово --pos noun --gender neuter --animacy inanimate --form singular.genitive=пробослова
editor --json rus select пробослово | grep -q '"gender":"neuter"'
editor rus delete пробослово --pos noun
test "$(editor --json rus select пробослово)" = '[]'
editor rus reset пробослово --pos noun

cp "$data/editor-forms.tsv" "$tmp/forms.before"
failed editor rus update читать --pos verb --form imperative.dual=читай
grep -q 'unknown form' "$tmp/error"
failed editor rus update читать --pos verb --gender masculine
cmp "$data/editor-forms.tsv" "$tmp/forms.before"
mkdir "$data/editor-forms.tsv.lock"
failed editor rus delete читать --pos verb
grep -q 'cannot acquire editor lock' "$tmp/error"
rmdir "$data/editor-forms.tsv.lock"
cmp "$data/editor-forms.tsv" "$tmp/forms.before"
# Generated source is read-only even when its effective sense is suppressed.
cmp dictionary/scene-forms.tsv "$data/scene-forms.tsv"
cmp dictionary/scene.tsv "$data/scene.tsv"
cmp dictionary/vocabulary.tsv "$data/vocabulary.tsv"
editor --json validate | grep -q '"valid":true'
printf '%s\n' 'Dictionary editor CRUD, validation, atomic writes, JSON and runtime integration passed'
