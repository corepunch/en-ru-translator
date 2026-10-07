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
sh test/cli_test.sh
echo "All standard tests completed."
