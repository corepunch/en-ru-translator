#!/bin/sh
# test_compare.sh — Compare LTPRO.EXE output vs Lua engine output for test sentences
#
# Usage:
#   ./test_compare.sh "She can speak Russian."     # test one sentence
#   ./test_compare.sh --all                        # run full test suite
#   ./test_compare.sh --capture                    # capture reference outputs to refs/
#
# Requirements: dosbox-x, lua 5.4, run_test.sh in the same directory

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REFS_DIR="$SCRIPT_DIR/refs"

# Reference test sentences (10 sentences exercising key rule groups)
SENTENCES="
She can speak Russian.
He is in the house.
She sat on the chair.
He must not go.
The dog that I saw ran away.
He was arrested by the police.
You are standing in an open field.
The house door is open.
He cannot go.
She has been seen.
"

# ── helpers ──────────────────────────────────────────────────────────────────

run_ltpro() {
    sentence="$1"
    "$SCRIPT_DIR/run_test.sh" "$sentence" 2>/dev/null
}

run_lua() {
    sentence="$1"
    # The Lua engine prints debug lines (Applying, ANSI-colored token dumps) and
    # then the final translated line last. Grab the last non-empty line.
    cd "$PROJECT_DIR" && lua init.lua "$sentence" 2>/dev/null | \
        grep -v "^Applying" | grep -v "^Input:" | grep -v "^\[" | \
        grep -v "^$" | tail -1
}

normalize() {
    # lowercase, collapse whitespace, strip trailing punctuation for comparison
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/[[:space:]]*$//'
}

ref_file() {
    sentence="$1"
    slug=$(echo "$sentence" | tr ' ' '_' | tr -dc '[:alnum:]_' | cut -c1-40)
    echo "$REFS_DIR/${slug}.txt"
}

# ── capture mode: record LTPRO reference outputs ──────────────────────────────

if [ "$1" = "--capture" ]; then
    mkdir -p "$REFS_DIR"
    echo "Capturing reference outputs from LTPRO.EXE..."
    echo "$SENTENCES" | while IFS= read -r s; do
        [ -z "$s" ] && continue
        ref="$(ref_file "$s")"
        out="$(run_ltpro "$s")"
        if [ -n "$out" ]; then
            echo "$out" > "$ref"
            echo "  OK  [$s] → $out"
        else
            echo "  ERR [$s] — no output from LTPRO"
        fi
    done
    exit 0
fi

# ── single sentence mode ──────────────────────────────────────────────────────

run_one() {
    sentence="$1"
    ref_f="$(ref_file "$sentence")"

    lua_out="$(run_lua "$sentence")"

    if [ -f "$ref_f" ]; then
        ref_out="$(cat "$ref_f")"
    else
        ref_out="$(run_ltpro "$sentence")"
        if [ -z "$ref_out" ]; then
            printf "SKIP  [%s]\n       (LTPRO produced no output)\n" "$sentence"
            return
        fi
    fi

    if [ "$(normalize "$lua_out")" = "$(normalize "$ref_out")" ]; then
        printf "PASS  [%s]\n" "$sentence"
        printf "      %s\n" "$ref_out"
    else
        printf "FAIL  [%s]\n" "$sentence"
        printf "  LTPRO: %s\n" "$ref_out"
        printf "  Lua:   %s\n" "$lua_out"
    fi
}

# ── --all mode ────────────────────────────────────────────────────────────────

if [ "$1" = "--all" ]; then
    tmpfile=$(mktemp)
    echo "0 0 0" > "$tmpfile"
    echo "$SENTENCES" | while IFS= read -r s; do
        [ -z "$s" ] && continue
        result=$(run_one "$s")
        echo "$result"
        read pass fail skip < "$tmpfile"
        case "$result" in
            PASS*) pass=$((pass+1)) ;;
            FAIL*) fail=$((fail+1)) ;;
            SKIP*) skip=$((skip+1)) ;;
        esac
        echo "$pass $fail $skip" > "$tmpfile"
    done
    read pass fail skip < "$tmpfile"
    rm -f "$tmpfile"
    echo "---"
    echo "Results: PASS=$pass  FAIL=$fail  SKIP=$skip"
    [ "$fail" -eq 0 ] && exit 0 || exit 1
fi

# ── single sentence from argument ─────────────────────────────────────────────

if [ -n "$1" ]; then
    run_one "$1"
else
    echo "Usage: $0 \"Sentence.\"  |  $0 --all  |  $0 --capture"
    exit 1
fi
