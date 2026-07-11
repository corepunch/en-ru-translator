local dbg = require "core.dbg"
local dictionary_store = require "dictionary_store"
local translator = require "core.translator"

-- The entry point is an imperative shell: it owns configuration, files, CLI
-- arguments, stdout, and exit status while translation remains in modules.
local input_sentence = "You are standing in an open field west of a white house, with a boarded front door."

local function load_config(path)
  local file = io.open(path, "r")
  if not file then return end
  for line in file:lines() do
    line = line:match("^%s*(.-)%s*$") or ""
    if line ~= "" and line:sub(1, 1) ~= "#" and line:sub(1, 1) ~= ";" then
      local key, value = line:match("^(%w+)%s*=%s*(.+)$")
      if key == "diag" then
        for category in value:gmatch("[^,%s]+") do dbg.enable(category) end
      elseif key == "diag_file" then
        dbg.set_file(value)
      elseif key == "debug" then
        dbg.set_level(tonumber(value) or 1)
      end
    end
  end
  file:close()
end

local overlay_dicts = {}

for _, value in ipairs(arg or {}) do
  if value == "--debug" then
    dbg.set_level(1)
  elseif value:match("^%-%-debug=(%d+)$") then
    dbg.set_level(tonumber(value:match("^%-%-debug=(%d+)$")))
  elseif value:match("^%-%-diag=(.+)$") then
    for category in value:match("^%-%-diag=(.+)$"):gmatch("[^,%s]+") do dbg.enable(category) end
  elseif value:match("^%-%-diag%-file=(.+)$") then
    dbg.set_file(value:match("^%-%-diag%-file=(.+)$"))
  elseif value:match("^%-%-config=(.+)$") then
    load_config(value:match("^%-%-config=(.+)$"))
  elseif value:match("^%-%-dict=(.+)$") then
    table.insert(overlay_dicts, value:match("^%-%-dict=(.+)$"))
  elseif value:sub(1, 2) ~= "--" then
    input_sentence = value
  end
end

_G.TRANSLATOR_DEBUG = dbg.level > 0
dbg.log(1, "Debug level:", dbg.level)

local english, russian = dictionary_store.load(nil, nil, table.unpack(overlay_dicts))
local engine = translator.new(english, russian)
local output, err = engine:translate(input_sentence)
if not output then
  io.stderr:write(tostring(err), "\n")
  os.exit(1)
end
print(output)
