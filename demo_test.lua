-- Extract full sentences from DEMO.TXT and translate them
local utils = require "utils"
local load = require "load"
local parser = require "parser"
local compiler = require "compiler"

local file = assert(io.open("LTGOLD/BASE.DIC", "r"))
local file2 = assert(io.open("LTGOLD/BASE.RUS", "r"))
local en_ru, base = {}, {}
compiler.base = base
for line in file:lines() do
  load.lingua(en_ru, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do
  local word, code = line:match("^(.-)\x2a(.*)$")
  if code then base[utils.decode(word)] = code end
end
file:close(); file2:close()

-- read demo, collapse line breaks within sentences
local demo = assert(io.open("LTGOLD/DEMO.TXT", "r"))
local text = demo:read("*all"):gsub("\n", " "):gsub("  +", " "):gsub("%. ", ".\n"):gsub(": ", ":\n")
demo:close()

-- extract non-empty sentences
local sents, n = {}, 1
for line in text:gmatch("[^\n]+") do
  line = line:match("^%s*(.-)%s*$") or line
  if #line > 20 then sents[n] = line; n = n + 1 end
end

-- process first 20 sentences (legal clauses are long)
for i = 1, math.min(20, #sents) do
  local s = sents[i]
  -- truncate very long sentences for display
  local display = #s > 70 and s:sub(1, 67).."..." or s
  
  local ts = utils.tokenize(s, en_ru)
  local ok = parser.collect(en_ru, ts)
  local out = compiler.compile(ts)
  
  local out_short = out and (#out > 70 and out:sub(1, 67).."..." or out) or ""
  print(string.format("%2d. %s", i, display))
  print(string.format("    => %s", out_short))
  print()
end
