#!/bin/sh
# Run the standard Lua-side test suite from repository root.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# One Lua process: dictionaries are parsed once and shared by every test.
lua test/run_all.lua

echo
sh test/cli_test.sh
echo "All standard tests completed."
