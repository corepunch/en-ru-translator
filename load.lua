local utils = require "translator.utils"
local load = {}

local function split(self, sep)
  return self:match("^(.-)" .. sep .. "(.*)$")
end

local function extract_phrase(prefix, input, out)
  -- local result = { phrase = true }
  -- for word in input:gmatch("([%a ][0-9]*[\127-\255]+)") do
  --   table.insert(result, word)
  -- end
  -- if prefix == '' then
    out[input:find("N") and "N" or "A"] = input
  -- else
  --   out[prefix:sub(1,1)] = input
  -- end  
end

local function extract_translation(key, input, result)
  local a, _ = input:match("^(.-)\\(.*)$")
  a = a or input
  for word in a:gmatch("([A-Z])") do 
    if word:sub(1,1) == 'Z' then word = 'V'..word:sub(2) end
    result[word:sub(1,1)] = word
  end
  for word in a:gmatch("([%a+][0-9]*[\127-\255; -]*)") do
    -- if word:sub(1,1) == 'Z' then print(key, utils.decode(a)) end
    if word:sub(1,1) == 'Z' then word = 'V'..word:sub(2) end
    result[word:sub(1,1)] = word
  end
end

function load.lingua(entries, line)
  -- local types = {
  --   N="noun", V="verb", A="adjective", D="adverb", E="past participle", 
  --   W="phrase", I="idiom", P="preposition", n="noun plural"
  -- }
  -- Skip "LTech DIC File 2.00\x1aERS\x00"

  local function add(tbl, key, value, type)
    local verb, particle = split(key, ' ')
    if particle then
      tbl[verb] = tbl[verb] or {}
      add(tbl[verb], particle, value)
    else
      tbl[key] = tbl[key] or {}
      tbl[key].__lex = value
      -- if value:find'Z' and value:find'D' then print(key, utils.decode(value)) end
      -- tbl[key].__lex = tbl[key].__lex or { __word = key, __lexeme = value }
      -- for prefix, phrase in value:gmatch("([a-zA-Z]*)(W[^/]*)") do
      --   value = value:gsub("([a-zA-Z]*)(W[^/]*)/?", "")
      --   extract_phrase(prefix, phrase, tbl[key].__lex)
      -- end
      -- extract_translation(key, value, tbl[key].__lex)
      -- if key == "wondering" then
      --   print(utils.decode(tmp))
      --   print(utils.debug(tbl[key]))
      -- end
    end
  end
  local key, value = split(line, '\x2a')
  if value then
    -- local _, count = line:gsub(" ", "")  -- replaces spaces with nothing, returns count
    -- if count > 2 then print(utils.decode(line)) end
    -- if utils.decode(value):find("уступать") then print(key, utils.decode(value)) end
    -- if value:find("turns") then print(key, utils.decode(value)) end
    -- if value:sub(1,1) == 'R' then print(key, utils.decode(value)) end
    -- if value:find('0', 1, true) then print(key, utils.decode(value)) end
    add(entries, key, value)
  end
end

return load