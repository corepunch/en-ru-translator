#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
LUA=${LUA:-lua}
"$LUA" test/engine_test.lua
"$LUA" test/adventure_test.lua
"$LUA" test/prose_test.lua
sh test/dictionary_editor_test.sh
[ "$("$LUA" init.lua 'I fly home.')" = 'Я лечу домой.' ]
[ "$(printf '%s\n' 'I am home.' 'She was here.' | "$LUA" init.lua --document)" = 'Я дома.
Она была здесь.' ]
[ "$("$LUA" init.lua --formal 'You are working here.')" = 'Вы работаете здесь.' ]
printf '%s\n' 'CLI smoke tests passed'
