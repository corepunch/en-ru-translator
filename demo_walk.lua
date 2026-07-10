local utils = require "utils"
local load = require "load"
local parser = require "parser"
local compiler = require "compiler"

local file = assert(io.open("LTGOLD/BASE.DIC", "r"))
local file2 = assert(io.open("LTGOLD/BASE.RUS", "r"))
local en_ru = {}
compiler.base = {}
for line in file:lines() do
  load.lingua(en_ru, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do
  local w, code = line:match("^(.-)\x2a(.*)$")
  if code then compiler.base[utils.decode(w)] = code end
end
file:close(); file2:close()

-- Read DEMO.TXT, collapse \n within sentences
local demo = assert(io.open("LTGOLD/DEMO.TXT", "r"))
local text = demo:read("*all")
demo:close()

-- Normalize whitespace and split into sentences
text = text:gsub("\n", " "):gsub("  +", " "):gsub("%. ", ".\n"):gsub(": ", ":\n")
local sents = {}
for line in text:gmatch("[^\n]+") do
  line = line:match("^%s*(.-)%s*$")
  if line and #line > 10 then sents[#sents+1] = line end
end

local total_words = 0
for _, s in ipairs(sents) do
  for _ in s:gmatch("%S+") do total_words = total_words + 1 end
end

local word_count = 0
for si, sent in ipairs(sents) do
  local ts = utils.tokenize(sent, en_ru)
  parser.collect(en_ru, ts)
  local out = compiler.compile(ts) or ""

  local n_words = 0
  for _ in sent:gmatch("%S+") do n_words = n_words + 1 end

  for w in out:gmatch("%S+") do
    word_count = word_count + 1
    print(string.format("[%d/%d] %s", word_count, total_words, w))
  end
end
