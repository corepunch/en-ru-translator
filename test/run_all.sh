#!/bin/sh
# Run the standard Lua-side test suite from repository root.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Lua module tests =="
for f in test/*_test.lua; do
  echo "-> $f"
  lua "$f"
done

echo
echo "== Sentence regression =="
lua demo/compare.lua

echo
echo "All standard tests completed."