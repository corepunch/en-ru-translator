local parser = require "parser"
local compiler = require "compiler"
local utils = require "utils"
local load = require "load"

-- load dictionaries
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

-- read demo text and split into sentences
local demo = assert(io.open("LTGOLD/DEMO.TXT", "r"))
local lines = demo:read("*all")
demo:close()

-- split on . ? ! and newlines, keep delimiters
local sentences = {}
for s, sep in lines:gmatch("([^%.%?!\n]+)([%.%?!\n]*)") do
  s = s:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
  if #s > 3 then
    table.insert(sentences, s .. (sep == "\n" and "" or sep))
  end
end

print("=== Translating DEMO.TXT ===\n")
local total, correct = 0, 0
for idx, sent in ipairs(sentences) do
  local ts = utils.tokenize(sent, en_ru)
  local out, err = parser.collect(en_ru, ts)
  if err then
    print(string.format("SENT %d: ERROR %s", idx, err))
  else
    local c = compiler.compile(ts)
    -- just print a summary
    if idx <= 5 or idx % 20 == 0 then
      print(string.format("%d. [%-60s]", idx, sent:sub(1, 58)))
      print(string.format("    => %s", c or ""))
    end
  end
  if idx % 10 == 0 then io.write(".") io.flush() end
end
print("\n\nDone. Processed " .. #sentences .. " sentences.")
