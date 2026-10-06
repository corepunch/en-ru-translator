-- Native morphology helpers (file 0x223BC..0x22CAF). All text here is CP866.
-- Parameters use original zero-based case/paradigm indices, not the compiler API.
local source = require "core.ltpro.morphology"
local encode = require("core.utils").encode
local function encode_rows(rows)
  local encoded = {}
  for i, row in ipairs(rows) do encoded[i] = {row[1], encode(row[2])} end
  return encoded
end
local function encode_genders(groups)
  local encoded = {}
  for gender, rows in ipairs(groups) do encoded[gender] = encode_rows(rows) end
  return encoded
end
local data = {
  nouns = encode_genders(source.nouns), adjectives = encode_genders(source.adjectives),
  imperfective = encode_rows(source.imperfective), verbs = encode_rows(source.verbs),
}
local inflect = {}
local sya, soft = encode('ся'), encode('сь') -- DS:630C/6310 far pointers
local l, genders = encode('л'), { [0] = encode('о'), '', encode('а') }
local families = { [0] = data.imperfective, [1] = data.verbs }
local gender_indices = { [0] = 1, [1] = 2, [2] = 3 }

-- Lua dispatch tables for recovered branches; the executable's data stays in morphology.lua.
local verb_modes = {
  imperative = { index = 6, past = 0 },
  past = { index = 7, past = 1 },
  finite = {},
}
local participle_slots = { present = {9, 10}, past = {11, 12} }
local tag_slots = { [0x47] = 8 }
local soft_reflexive_slots = { [0] = true, [4] = true, [6] = true }
local particles = {
  { mask = 2, past_only = true, text = encode(' бы') },
  { mask = 16, text = encode(' ли') },
}
local function drop_penultimate(value) return value:sub(1, -3) .. value:sub(-1) end
local function drop_last(value) return value:sub(1, -2) end
-- DS:B983/B987/B98B, preserving the original first-applicable transformation.
local past_rewrites = {
  { suffix = encode('чел'), oblique_only = true, apply = drop_penultimate },
  { suffix = encode('шел'), oblique_only = true, apply = drop_penultimate },
  { suffix = encode('кл'), apply = drop_last },
}

local function ends(word, suffix) return word:sub(-#suffix) == suffix end
local function reflexive(word)
  return #word > 2 and (ends(word, sya) or ends(word, soft))
end
local function family(aspect) return families[aspect] or data.imperfective end
local function gender_table(name, gender)
  return data[name][gender_indices[gender] or 2]
end

local function build(word, row, index, length)
  local start, cursor = 1, 0
  -- Native strchr iteration preserves empty fields from adjacent spaces.
  while cursor < index do
    local space = row[2]:find(' ', start, true)
    if not space then return nil end
    start, cursor = space + 1, cursor + 1
  end
  local marker = row[2]:sub(start, start)
  if marker == '-' then return nil end
  local cut = length - row[1]
  local result = cut > 0 and word:sub(1, cut) or word
  if marker == '=' then return result end
  if cut == 0 then result = '' end
  local stop = row[2]:find(' ', start, true)
  local suffix = row[2]:sub(start, stop and stop - 1 or #row[2])
  result = result .. suffix
  -- The executable terminates at original/effective length + suffix length even
  -- when a nonpositive cut copied the whole word, retaining its truncation quirk.
  return stop and result:sub(1, length + #suffix) or result
end

function inflect.noun(id, word, gender, plural, case)
  -- The caller handles nominative singular; this raw helper starts at genitive.
  return build(word, assert(gender_table('nouns', gender)[id + 1]),
    math.max(0, case + (plural ~= 0 and 6 or 0) - 1), #word)
end

function inflect.adjective(id, word, gender, plural, case)
  local refl = id ~= 14 and reflexive(word)
  local value = build(word, assert(gender_table('adjectives', gender)[id + 1]),
    case + (plural ~= 0 and 6 or 0), #word - (refl and 2 or 0))
  return value and (value .. (refl and sya or ''))
end

function inflect.verb(id, word, aspect, flags, person, plural, past, gender)
  local mode = verb_modes[(flags & 4) ~= 0 and 'imperative' or (past == 1 and 'past' or 'finite')]
  if not mode.index and person == 0 then return word end
  local index = mode.index or person - 1 + (plural ~= 0 and 3 or 0)
  past = mode.past or past
  local refl = reflexive(word)
  local value = build(word, assert(family(aspect)[id + 1]), index, #word - (refl and 2 or 0))
  if not value then return nil end
  if past == 1 then
    for _, rule in ipairs(past_rewrites) do
      if (not rule.oblique_only or gender ~= 1 or plural ~= 0) and ends(value, rule.suffix) then
        value = rule.apply(value)
        break
      end
    end
    if not ends(value, l) and (gender ~= 1 or plural == 1) then value = value .. l end
    value = value .. (plural ~= 0 and encode('и') or (genders[gender] or ''))
  end
  if refl then
    local suffix = (soft_reflexive_slots[index] or
      (past == 1 and (gender ~= 1 or plural ~= 0))) and soft or sya
    value = value .. suffix
  end
  for _, particle in ipairs(particles) do
    if (flags & particle.mask) ~= 0 and (not particle.past_only or past == 1) then
      value = value .. particle.text
    end
  end
  return value
end

function inflect.participle(id, word, aspect, tag, passive, past)
  local index = tag_slots[tag] or participle_slots[past == 1 and 'past' or 'present'][passive ~= 0 and 2 or 1]
  local refl = passive == 0 and reflexive(word)
  local value = build(word, assert(family(aspect)[id + 1]), index, #word - (refl and 2 or 0))
  if value and refl then
    value = value .. (index == 8 and ((aspect ~= 0 and encode('ши') or '') .. soft) or sya)
  end
  return value
end

return inflect
