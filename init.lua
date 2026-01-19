local parser = require "translator.parser"
local compiler = require "translator.compiler"
local utils = require "translator.utils"
local load = require "translator.load"
local paradigms = require "translator.paradigms"

local file = assert(io.open("translator/LTGOLD/BASE.DIC", "r"))
local file2 = assert(io.open("translator/LTGOLD/BASE.RUS", "r"))
local en_ru = {}
local base = {}

compiler.base = base

local function tohex(s)
    local t = {}
    for i = 1, #s do t[#t+1] = string.format("%02X", s:byte(i)) end
    return table.concat(t, " ")
end

local function tobin(s)
    local t = {}
    for i = 1, #s do
        local b = s:byte(i)
        local bin = ""
        for bit = 7, 0, -1 do
            local bitval = ((b >> bit) & 1)
            bin = bin .. (bitval == 1 and "X" or ".")
        end
        t[#t+1] = bin
    end
    return table.concat(t, " ")
end

for line in file:lines() do 
  local word, code = line:match("^(.-)\x2a(.*)$")
  -- if code and code:sub(1,3):match("^([A-Z])%1%.$") then
    if code and code:sub(1,3) == 'ZV.' then
  -- if code and code:find('/',1,true) then-- and code:find(' ',1,true) then
  -- if code and code:find(';',1,true) then
  -- if word=='try back' then
    -- print(utils.decode(line:gsub("%b{}", ""):gsub("%.", ""), false))
  end
  load.lingua(en_ru, line:
    gsub("%b{}", ""):
    gsub("%.", ""):
    -- gsub("%*([A-Z])%1", "*%1"))
    gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do 
  -- parse_lingua(base, line
  local word, code = line:match("^(.-)\x2a(.*)$")
  -- if code and code:byte(3) and (code:byte(3)&0x01)>0 and code:sub(1,1)=='N' then
  -- if code and utils.decode(word) == 'человек' then --and code:sub(1,1) == 'N' and code:byte(4)==0x81 then
  -- if code and code:sub(1,1)=='N' and (code:byte(4) or 0)==0x80+23 then
  -- if code and code:sub(1,1)=='N' and (code:byte(3) or 0)&0x4==04 then
  --   print(tohex(code:sub(2)), utils.decode(word), code:sub(1,1))
    -- print(tohex(code:sub(2,5)), utils.decode(code:sub(2)))
  -- end
  if code then
    base[utils.decode(word)] = code
  end
end

file:close()
file2:close()

-- local function find_actor(words)
--   for _, w in ipairs(words) do
--     if utils.decode(w):match("^R([^%s%.]+)") then return w end
--   end
--   return nil
-- end

-- print(tohex(base["если"]))
-- print(utils.decode(base["перспектива"]))

-- print(utils.debug(en_ru.during))
print(utils.decode(en_ru.fine.__lex))
-- print(utils.debug(en_ru.ever))

local s, e = parser.collect(en_ru, --"{subject} {verb} {object}", 
-- utils.tokenize("You restore my bright light", en_ru))
-- utils.tokenize("You need to turn off bright light with the aid of a switch", en_ru))
  utils.tokenize("You are standing in an open field west of a white house, with a boarded front door.", en_ru))
  -- utils.tokenize("with a boarded front door", en_ru))

  -- utils.tokenize("WELCOME TO ZORK!", en_ru))
  -- utils.tokenize("ZORK is a game of adventure, danger, and low cunning.", en_ru))
  -- utils.tokenize("and low cunning", en_ru))
  -- utils.tokenize("fine fine", en_ru))
  -- utils.tokenize("In it you will explore some of the most amazing territory ever seen by mortals.", en_ru))
  -- utils.tokenize("No computer should be without one!", en_ru))
  -- utils.tokenize("A battery-powered brass lantern is on the trophy case.", en_ru))
  -- utils.tokenize("the most amazing territory ever seen by mortals", en_ru))
  -- utils.tokenize("No, I am not", en_ru))
  -- utils.tokenize("Make thing promising", en_ru))
  -- utils.tokenize("However, if true then", en_ru))

if e then print(e) end

if s then
  compiler.compile(s)
end

-- io.write = function(...)
--     local out = {}
--     for i = 1, select("#", ...) do
--         local s = tostring(select(i, ...))
--         out[#out+1] = translate(s)
--     end
--     return old_write(table.concat(out))
-- end

os.exit()
