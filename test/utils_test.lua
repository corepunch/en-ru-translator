local utils = require "core.utils"
local encoding = require "core.encoding"

local function assert_eq(a, b, msg)
  assert(a == b, (msg or "?") .. ": expected [" .. tostring(b) .. "], got [" .. tostring(a) .. "]")
end

local function cp(s) return encoding.encode(s) end

-- encode / decode round-trips
assert_eq(utils.decode(cp("привет")), "привет", "decode basic")
local s = "Привет, мир! ё"
assert_eq(utils.decode(utils.encode(s)), s, "encode->decode round-trip")
assert_eq(utils.encode("ASCII"), "ASCII", "encode ASCII passthrough")

-- decode with strip=true (cyrillic only)
local mixed = "V" .. cp("говорить")
local stripped = utils.decode(mixed, true)
assert_eq(stripped, "говорить", "decode strip=true")

-- map
local r = utils.map({10, 20, 30}, function(x) return x + 1 end)
assert_eq(r[1], 11, "map[1]")
assert_eq(r[2], 21, "map[2]")
assert_eq(r[3], 31, "map[3]")
assert_eq(#r, 3, "map length")

-- extract_form: plain verb token  Vговорить → "говорить"
local v_token = "V" .. cp("говорить")
assert_eq(utils.extract_form(v_token), "говорить", "extract_form V")

-- extract_form: X with 3-digit metadata  X003быть → "быть"
local x_token = "X003" .. cp("быть") .. "U" .. cp("должен")
assert_eq(utils.extract_form(x_token), "быть", "extract_form X003")

-- extract_form: Z with secondary N/A forms  ZоткрытьNоткрытие → "открыть"
local z_token = "Z" .. cp("открыть") .. "N" .. cp("открытие") .. "A" .. cp("открытый")
assert_eq(utils.extract_form(z_token), "открыть", "extract_form Z multi-form")

-- extract_form: N with semicolon alternative  Nобразец;выборка → "образец"
local n_token = "N" .. cp("образец") .. ";" .. cp("выборка")
assert_eq(utils.extract_form(n_token), "образец", "extract_form N semicolon")

-- extract_form: single-char tag with no text → ""
assert_eq(utils.extract_form("T"), "", "extract_form T single-char")
assert_eq(utils.extract_form(""), "", "extract_form empty")

print("utils tests passed")
