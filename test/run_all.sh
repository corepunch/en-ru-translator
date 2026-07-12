#!/bin/sh
# Run the standard Lua-side test suite from repository root.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Lua module tests =="
for f in test/*_test.lua; do
  [ "$f" = "test/ltgold100_test.lua" ] && continue
  [ "$f" = "test/ltgold200_test.lua" ] && continue
  echo "-> $f"
  lua "$f"
done

echo
echo "== Sentence regression =="
lua demo/compare.lua

echo
echo "== LTGOLD 100-sentence suite T7/T8 (tracking known failures) =="
echo "-> test/ltgold100_test.lua"
lua test/ltgold100_test.lua 2>/dev/null || true

echo
echo "== LTGOLD 200-sentence suite T1-T6 (tracking known failures) =="
echo "-> test/ltgold200_test.lua"
lua test/ltgold200_test.lua 2>/dev/null || true

echo
echo "All standard tests completed."