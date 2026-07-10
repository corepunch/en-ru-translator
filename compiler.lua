local utils = require "utils"
local paradigms = require "paradigms"
local compiler = {}

local uniques = {
  ["должен"] = {"но","ен","на","ны"},
}

local case = {
  ["И"]   = 1,   -- именительный ед.
  ["Р"]   = 2,   -- родительный ед.
  ["Д"]   = 3,   -- дательный ед.
  ["В"]   = 4,   -- винительный ед.
  ["Т"]   = 5,   -- творительный ед.
  ["П"]   = 6,   -- предложный ед.
}

-- local u_endings = {
--   ["011"] = "ен",    -- I do
--   ["012"] = "ен",    -- you do (sg)
--   ["03"]  = "но",    -- he/she/it does
--   ["031"] = "ен",    -- he/she/it does
--   ["032"] = "на",    -- he/she/it does
--   ["11"]  = "ны",    -- we do
--   ["12"]  = "ны",    -- you do (pl)
--   ["13"]  = "ны",    -- they do
-- }

local function get_gender(s)
  local conf = compiler.base[utils.decode(s, true)]
  return conf and conf:byte(3)&3
end

-- find_form: extract the Russian text for a specific tag letter from a multi-form token
-- e.g. find_form("SэтоOэтотL, который", "L") → "который"
local function find_form(token, tag)
  -- iterate tag+word pairs: each tag is an uppercase/lowercase letter before CP866 bytes
  for t, word in token:gmatch("([A-Za-z;,])([^\127-\255]*[\127-\255][^\127-\255\127-\255A-Za-z]*)") do
    if t == tag then return word end
  end
  -- fallback: extract first high-byte sequence
  return utils.decode(token, true)
end

local function find(s, n, t)
  for i = n, #s do
    if s[i]:sub(1,1) == t then return s[i] end
  end
end

local function adj(a)
    local d = utils.decode(a:sub(1, #a-2), true)
    local b = compiler.base[d]
    if b then
      return (b:byte(2)==0x80 and b:byte(3) or b:byte(4))&~0x80
    else
      return paradigms.find_adjective(utils.decode(a))
    end
end

local function set(e, f, v) e[f] = v end

local printers = {
  A = function(a, e, s, i)
    local n = find(s, i, 'N')
    if n then e.gender = get_gender(n) end
    return paradigms.adjective(a, adj(utils.extract(a)), e)
  end,
  R = function(t, e)
    -- format: R<plural><person>[<gender>]<word>
    -- e.g. R032она (3 digits), R12Вы (2 digits without gender)
    local a, b, g = t:match("R(%d)(%d)(%d)")
    if not a then a, b = t:match("R(%d)(%d)") end
    e.plural = (a or '0') ~= '0'
    e.person = tonumber(b) or 3
    if g then e.gender = tonumber(g) end  -- 1=masc, 2=fem
    return utils.decode(t, true)
  end,
  N = function(t, e) 
    local d = utils.decode(t, true)
    local b = compiler.base[d]
    e.gender = get_gender(t)
    e.plural = e.plural and (b:byte(3)&0x4) == 0
    return paradigms.noun(t, b:byte(4)&~0x80, e), set(e, 'form', case['В'])
  end,
  P = function(t, e)
    if case[utils.decode(t:sub(3,3), true)] then
      e.form = case[utils.decode(t:sub(3,3), true)]
      return utils.decode(t:sub(4), true)  -- strip trailing ASCII flags (e.g. 'b')
    else
      e.form = case[utils.decode(t:sub(2,2), true)]
      return utils.decode(t:sub(3), true)
    end
  end,
  Z = function(t, e)
    local d = utils.decode(t, true)
    e.form = case["В"]
    -- only reset perfective if it wasn't set by a preceding modal/auxiliary
    if not e.perfective then
      e.perfective = (e.word == 1)
    end
    if e.word == 1 then e.imperative = true end
    if e.perfective and compiler.base[d] and (compiler.base[d]:byte(2)&2)~=2 then
      t = compiler.base[d]:sub(6)
      d = utils.decode(t)
    end
    if e.infinitive then e.infinitive = false return d end
    if not compiler.base[d] then return d end
    return paradigms.verb(t, compiler.base[d]:byte(4)&~0x80, e)
  end,
  U = function(t, e)
    local d = utils.decode(t, true)
    local u = uniques[d]
    e.infinitive, e.perfective = true, true
    if u then
      local _u = utils.extract(t)
      return utils.decode(_u:sub(1,#_u-2))..u[e.plural and 4 or (e.gender+1)]
    else
      -- fall back to regular verb paradigm (e.g. мочь → может)
      local b = compiler.base[d]
      if b then return paradigms.verb(t, b:byte(4)&~0x80, e) end
      return utils.decode(t, true)
    end
  end,
  T = function() return "" end,
  [" "] = function (t) return utils.decode(t, true) end,
  C = function (t) return utils.decode(t, true) end,
  D = function (t) return utils.decode(t:sub(2), false) end,
  -- E/e: past participle / -ed form → produce past tense
  E = function(t, e)
    local d = utils.decode(t, true)
    local b = compiler.base[d]
    if not b then return d end
    e.past = true
    return paradigms.verb(t, b:byte(4)&~0x80, e)
  end,
}

-- S: demonstrative pronoun (adjective form) — use adjective declension if possible, else decode
printers.S = function(t, e)
  local ok, res = pcall(printers.A, t, e)
  if ok and res and #res > 0 then return res end
  return utils.decode(t, true)
end
printers.V = printers.Z
printers.G = printers.Z
printers.e = printers.E
-- Lowercase resolved tags — decode first available form
printers.n = function(t, e) e.plural = true return printers.N(t, e) end
printers.g = function(t, e) e.past = true return printers.G(t, e) end
printers.v = function(t, e) return printers.V(t, e) end
printers.p = function(t, e) return printers.P(t, e) end
printers.f = function(t) return utils.decode(t, true) end
-- J (subordinating conjunction), L (relative pronoun), j (clause-end marker), O (demonstrative)
-- These are structural/functional words — output their Russian text directly
printers.J = function(t) return utils.decode(t, true) end
printers.L = function(t) return utils.decode(t, true) end
printers.j = function(t) return "" end  -- clause-end marker is silent
printers.O = function(t, e)
  local ok, res = pcall(printers.A, t, e)
  if ok and res then return res end
  return utils.decode(t, true)
end
printers.l = printers.L
printers.s = printers.S
-- h (history/alternate form marker) — decode and output
printers.h = function(t) return utils.decode(t, true) end
-- Q (question word), M (indirect pronoun), m (compound pronoun), r (compound personal)
printers.Q = function(t) return utils.decode(t, true) end
printers.M = function(t) return utils.decode(t, true) end
printers.m = function(t) return utils.decode(t, true) end
printers.r = function(t) return utils.decode(t, true) end
-- k (negative 'no'), K (negative 'not')
printers.K = function(t) return utils.decode(t, true) end
printers.k = function(t) return utils.decode(t, true) end
-- x (impersonal/there-is), y (have existential), i (indefinite article form)
printers.x = function(t) return utils.decode(t, true) end
printers.y = function(t) return utils.decode(t, true) end
printers.i = function(t) return utils.decode(t, true) end
printers.u = function(t) return utils.decode(t, true) end
-- b/B (infinitive particle 'to') — suppress in output
printers.B = function(t) return "" end
printers.b = function(t) return "" end
-- W (multi-word phrase) — output decoded
printers.W = function(t) return utils.decode(t, true) end
-- # (proper noun / untranslatable)
printers["#"] = function(t) return t:sub(2) end  -- output raw (ASCII proper noun)
printers.F = function(t, e)
  e.past = true
  e.passive = true
  return printers.Z(t, e)
end
printers.X = function(t, e)
  if t:match("%d+") == "003" then
    e.infinitive = true
    return "-"
  else
    local p = printers.V(t, e)
    e.infinitive = true
    return p
  end
end

function compiler.compile(s)
  local e = {
    plural = false,
    gender = 1,
    person = 3,
    form = 1,
    perfective = false,
    imperative = false,
    word = 1
  }
  local c = {}

  -- for i, w in ipairs(s) do print(utils.decode(w)) end

  for i, w in ipairs(s) do
    if #w == 1 and w:match"[,%!%.;:]" then
      if #c > 0 then c[#c] = c[#c]..w
      else table.insert(c, w) end
    else
      local tag = w:sub(1,1)
      local func = printers[tag]
      local ok, res = pcall(func, w, e, s, i)
      local out = ok and res or utils.decode(w, true)
      if _G.TRANSLATOR_DEBUG then
        print(string.format("  [%d] tag=%-2s token=%-30s => %-20s  e={inf=%s perf=%s plur=%s form=%s}",
          i, tag, utils.decode(w):sub(1,30), utils.decode(out or ''),
          tostring(e.infinitive), tostring(e.perfective), tostring(e.plural), tostring(e.form)))
        if not ok then print("    ERROR: "..tostring(res)) end
      end
      if out and #out > 0 then table.insert(c, out:find('#') and out:sub(2) or out) end
      e.word = e.word + 1
    end
  end
  -- capitalize first word
  if #c > 0 then
    local first = c[1]
    -- find first Cyrillic/Latin char and uppercase it
    c[1] = first:gsub("^([\xD0\xD1])([\x80-\xBF])", function(b1, b2)
      -- UTF-8 Cyrillic: uppercase range is U+0410-U+042F (д0 90-д0 АФ) for А-Я
      -- lowercase а-п: D0 B0-D0 BF  р-я: D1 80-D1 8F
      local cp = (b1:byte() == 0xD0 and b2:byte() - 0x80 or b2:byte() - 0x80 + 0x40) + 0x400
      if cp >= 0x430 and cp <= 0x44F then  -- а-я: subtract 0x20
        local uc = cp - 0x20
        local ub1 = 0xD0 + (uc - 0x400 >= 0x40 and 1 or 0)
        local ub2 = (uc - 0x400) % 0x40 + 0x80
        return string.char(ub1, ub2)
      end
      return b1..b2
    end, 1)
  end
  print("")
  print(table.concat(c, " "))
  print("")
end

-- print(
  --   table.concat({
  --     noun(s.subject.noun, table.unpack(s.subject)),
  --     verb(s.verb.verb, read_transform(s.subject.noun), s.verb.secondary),
  --     noun(s.object.noun, table.unpack(s.object))}, 
  --   " "))

return compiler