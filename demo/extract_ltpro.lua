-- Deterministic extraction of LTPRO's grammar data into core/rules.lua:
--   lua demo/extract_ltpro.lua > core/rules.lua
-- LTPRO addresses live here only. core/rules.lua names every table and
-- string, and the engine reads it by those names; LTPRO.EXE stays the
-- translation oracle.
package.path = './?.lua;' .. package.path
local binary = require 'demo.ltpro_binary'
local encoding = require 'core.encoding'
local path = arg[1] or 'LTGOLD/LTPRO.EXE'
local file = assert(io.open(path, 'rb'))
local exe = file:read('a')
file:close()
local reader = binary.new(exe)

-- Data-segment helpers (DS-relative offsets).
local DS = 0x26750
local data = exe:sub(DS + 1)
local function word(at) return string.unpack('<I2', data, at + 1) end
local function cstring(at)
  local stop = assert(data:find('\0', at + 1, true), string.format('unterminated string at 0x%04X', at))
  return data:sub(at + 1, stop - 1)
end

-- CP866 bytes as readable UTF-8; bytes outside the Cyrillic table are escaped.
local function quote(bytes)
  local out = {}
  for i = 1, #bytes do
    local b = bytes:byte(i)
    local c = encoding.character(b)
    if c then out[#out + 1] = c
    elseif b == 0x22 or b == 0x5C then out[#out + 1] = '\\' .. string.char(b)
    elseif b == 0x0A then out[#out + 1] = '\\n'
    elseif b < 0x20 or b >= 0x7F then out[#out + 1] = string.format('\\%03d', b)
    else out[#out + 1] = string.char(b) end
  end
  local text = table.concat(out)
  local loaded = assert(load('return "' .. text .. '"'))()
  assert(encoding.encode(loaded) == bytes, 'string does not round-trip: ' .. text)
  return '"' .. text .. '"'
end
local function emit(...) io.write(string.format(...), '\n') end

-- Strings the engine reads by name. LTPRO keeps a separate copy of a literal
-- for each instruction that uses it; every copy must hold the same text.
local STRINGS = {
  a = { 0x48C1, 0x4923, 0xB992 },
  alt_close = { 0x0601 },
  alt_number = { 0x05F9 },
  alt_open = { 0x045C },
  alt_separator = { 0x05FF },
  aya = { 0x4881 },
  bn = { 0x4936 },
  bolee = { 0x494E },
  bolshinstvo = { 0x49C0 },
  by = { 0x48EC, 0x4900, 0xB996 },
  byt = { 0x4908, 0x4919 },
  chel = { 0xB983 },
  chetyre = { 0x4994 },
  chn = { 0x4930 },
  comma = { 0x4894 },
  comma_chto = { 0x4FCC, 0x4FDC },
  comma_chtoby = { 0x4FE2 },
  comma_kotoryy = { 0x4FB8, 0x4FC2, 0x4FD2, 0x5110 },
  delat = { 0x490D },
  desyat = { 0x49B9 },
  devyat = { 0x49B2 },
  dolzhen = { 0x48D9 },
  dva = { 0x498C },
  empty = { 0x4FEA },
  en = { 0x48E6, 0x48FA, 0x493C, 0x4942 },
  en_at = { 0x47F5 },
  en_by = { 0x5072 },
  en_four = { 0x47DA },
  en_from = { 0x4805, 0x4812 },
  en_in = { 0x47E8, 0x4F71, 0x4F9E, 0x4FA7, 0x510A },
  en_into = { 0x47F8 },
  en_most = { 0x47E3 },
  en_of = { 0x506C, 0x506F, 0x5075, 0x5078 },
  en_on = { 0x47FD, 0x4F74, 0x4FA1, 0x4FAA, 0x510D },
  en_one = { 0x507B },
  en_see = { 0x511A },
  en_some = { 0x482F },
  en_that = { 0x5125 },
  en_three = { 0x47D4 },
  en_to = { 0x47F2, 0x480F, 0x481A, 0x4F6E, 0x4F9B, 0x4FA4, 0x4FAD, 0x5107 },
  en_two = { 0x47D0 },
  en_years = { 0x47C6, 0x4825 },
  eto = { 0x481D, 0x49E0 },
  etot = { 0x4960 },
  glossary_alt = { 0x05F0 },
  glossary_alt_note = { 0x05E6 },
  glossary_head = { 0x05CE },
  glossary_note = { 0x05D9 },
  glossary_reading = { 0x05E1 },
  i = { 0xB990 },
  imeetsya = { 0x4FB0 },
  iz = { 0x480C },
  kakoy = { 0x48C8, 0x4965 },
  kaya = { 0x4873 },
  kie = { 0x486F },
  kiy = { 0x486B },
  kl = { 0xB98B },
  koe = { 0x4877 },
  l = { 0xB98E },
  let = { 0x47CC, 0x47DF, 0x482B },
  li = { 0x48F0, 0x4904, 0xB99A },
  met = { 0x4914 },
  moch = { 0x48CE },
  n = { 0xBAB1 },
  na = { 0x47ED, 0x4800, 0x48E3, 0x48F7 },
  nash = { 0x497B },
  ne = { 0x4821, 0x4F66, 0x4F6A, 0x4F77, 0x4F7B, 0x4F7F, 0x4F83, 0x4F8B, 0x4F8F, 0x4F93, 0x4F97 },
  nemnogo = { 0x4834 },
  ni = { 0x4F87 },
  nn = { 0x491E, 0x4945 },
  no = { 0x48E9, 0x48FD },
  ny = { 0x48E0, 0x48F4 },
  o = { 0x48C3, 0x4925, 0xB994 },
  oba = { 0x4983 },
  odin = { 0x4987 },
  oe = { 0x4884 },
  ok = { 0x492D },
  ot = { 0x4817 },
  pn = { 0x4933 },
  pyat = { 0x499B },
  s = { 0x480A },
  sam = { 0x497F },
  samyy = { 0x4948 },
  sem = { 0x49A6 },
  shel = { 0xB987 },
  shest = { 0x49A0 },
  shi = { 0xB99E },
  sk = { 0x49D4 },
  skolko = { 0x49CC },
  smoch = { 0x48D3 },
  smotri = { 0x511E },
  soft_n = { 0x493F },
  space = { 0x05F5, 0x05F7, 0x0603, 0x4954, 0xB97F, 0xB981 },
  sya = { 0x484A, 0x4850, 0x4853, 0x4856, 0x4859, 0x485C, 0x485F, 0x4862, 0x4865, 0x4868, 0x48BC, 0x48C5, 0x49D7, 0x49DA, 0x49DD, 0x512A, 0x512D },
  ta = { 0x495A },
  tk = { 0x492A },
  to = { 0x495D },
  tot = { 0x4956, 0x496B },
  tri = { 0x4990 },
  v = { 0x47EB, 0x47F0, 0x4803 },
  vash = { 0x4977 },
  ves = { 0x4972 },
  vk = { 0x4927 },
  vn = { 0x4939 },
  vosem = { 0x49AB },
  y = { 0x48BF, 0x4921 },
  ye = { 0x487E },
  yy = { 0x487B, 0x496F },
}
-- Pointer lists: entry i is a far pointer at base + 4*i; a count of nil means
-- the list ends at a null pointer.
local LISTS = {
  { 'contracted_is', 0x09E4, nil, "pronouns that take a contracted 's" },
  { 'reflexive', 0x630C, 2, 'reflexive suffixes' },
  { 'pronoun_cases', 0x6314, nil, 'pronoun oblique cases (gen dat acc inst prep), a row per pronoun' },
  { 'pronouns', 0x6344, nil, 'pronoun nominatives, the rows of pronoun_cases' },
  { 'endings_noun_m', 0x5130, 0x42, 'lemma endings each noun-m row serves' },
  { 'endings_noun_f', 0x53C4, 0x23, 'lemma endings each noun-f row serves' },
  { 'endings_noun_n', 0x5522, 0x21, 'lemma endings each noun-n row serves' },
  { 'endings_adjective', 0x566C, 0x1A, 'lemma endings each adjective row serves' },
  { 'endings_verb_imperfective', 0x58A8, 0x6A, 'lemma endings each verb-imperfective row serves' },
  { 'endings_verb_perfective', 0x5CCC, 0x71, 'lemma endings each verb-perfective row serves' },
  { 'endings_replacement', 0x6136, 0x2F, 'lemma endings each replacement row serves' },
}
-- Inflection tables: six-byte rows, a byte count to cut and an endings pointer.
local PARADIGMS = {
  { 'noun-m', 0x5238, 66 }, { 'noun-f', 0x5450, 35 }, { 'noun-n', 0x55A6, 33 },
  { 'adjective-m', 0x56D4, 78 }, { 'adjective-f', 0x5770, 52 }, { 'adjective-n', 0x580C, 26 },
  { 'verb-imperfective', 0x5A50, 106 }, { 'verb-perfective', 0x5E90, 113 },
  { 'replacement', 0x61F2, 47 },
}
-- 16-bit values.
local VALUES = { { 'meaning_start', 0x042B, 'number of the first inline alternative' } }

emit('-- Generated by lua demo/extract_ltpro.lua from the unpacked LTPRO image.')
emit("-- LTPRO's grammar data: rule tables, inflection tables, word lists and")
emit('-- literals, named for the engine. Handler IDs and guard scalars are native')
emit('-- data, not Lua rewrite priorities. Strings are CP866 shown as UTF-8.')
emit('local rules = {}\n')

for _, layout in ipairs(binary.layouts) do
  local key = layout.lua_index and tostring(layout.lua_index) or string.format('%q', layout.lua_key)
  emit('-- %s: %d records.', layout.name, layout.count)
  emit('rules[%s] = {', key)
  for _, record in ipairs(reader.records(layout)) do
    local fields = { string.format('0x%02X', record.flag), quote(record.pattern) }
    if record.action then fields[#fields + 1] = quote(record.action) end
    if record.endpoint_order ~= nil then fields[#fields + 1] = 'endpoint_order = ' .. record.endpoint_order end
    emit('  { %s },', table.concat(fields, ', '))
  end
  emit('}\n')
end

emit('-- English suffix analysis: ending and the class it assigns, in native order.')
emit('rules.suffixes = {')
for _, record in ipairs(reader.records(binary.suffix_layout)) do
  emit('  { %s, %s },', quote(record.suffix), quote(record.tag))
end
emit('}\n')

emit('-- Contractions: ending, class, inserted word, Russian reading, selector.')
emit('rules.contractions = {')
do
  local at = 0x0930
  while word(at) ~= 0 do
    local reading = word(at + 12) ~= 0 and quote(cstring(word(at + 12))) or 'false'
    emit('  { %s, %s, %s, %s, %d },', quote(cstring(word(at))), quote(cstring(word(at + 4))),
      quote(cstring(word(at + 8))), reading, word(at + 16))
    at = at + 18
  end
end
emit('}\n')

local names = {}
for name in pairs(STRINGS) do names[#names + 1] = name end
table.sort(names)
emit('-- Literals the grammar handlers test and write.')
emit('rules.strings = {')
for _, name in ipairs(names) do
  local value
  for _, at in ipairs(STRINGS[name]) do
    local s = cstring(at)
    assert(value == nil or value == s, name .. ': copies differ')
    value = s
  end
  emit('  %s = %s,', name, quote(value))
end
emit('}\n')

emit('rules.values = {')
for _, v in ipairs(VALUES) do emit('  %s = %d, -- %s', v[1], word(v[2]), v[3]) end
emit('}\n')

emit('-- Word lists, entries from 0.')
emit('rules.lists = {')
for _, l in ipairs(LISTS) do
  local name, base, count, note = l[1], l[2], l[3], l[4]
  if not count then count = 0; while word(base + count * 4) ~= 0 do count = count + 1 end end
  emit('  -- %s', note)
  emit('  %s = {', name)
  for i = 0, count - 1 do emit('    [%d] = %s,', i, quote(cstring(word(base + i * 4)))) end
  emit('  },')
end
emit('}\n')

emit('-- Inflection tables: row id = {cut, endings}. "=" keeps the stem, "-" has no form.')
emit('rules.paradigms = {')
for _, p in ipairs(PARADIGMS) do
  local name, base, count = p[1], p[2], p[3]
  emit('  [%q] = {', name)
  for id = 0, count - 1 do
    local at = base + id * 6
    emit('    [%d] = { %d, %s },', id, word(at), quote(cstring(word(at + 2))))
  end
  emit('  },')
end
emit('}\n')
emit('return rules')
