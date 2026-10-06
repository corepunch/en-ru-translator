local utils = require "core.utils"
local paradigms = {}

-- Tables are regenerated from native six-byte records; do not normalize their spelling.
local native = require "core.ltpro.morphology"
paradigms.nouns = native.nouns
paradigms.verbs = native.verbs
paradigms.imperfective_verbs = native.imperfective
paradigms.adjectives = {}
for gender, rows in ipairs(native.adjectives) do
  paradigms.adjectives[gender] = {}
  for i, row in ipairs(rows) do paradigms.adjectives[gender][i] = row[2] end
end

local pronouns = {
  "меня мне меня мной мне",
  "тебя тебе тебя тобой тебе",
  "его ему его им нем",
  "его ему его им нем",
  "ее ей ее ею ней",
  "нас нам нас нами нас",
  "Вас Вам Вас Вами Вас",
  "их им их ими них",
  "кого кому кого кем ком",
  "чего чему что чем чем",
  "себя себе себя собой себе",
}

local past_verb = { "о", "", "а", "и", "и", "и", }
paradigms.past_verb = past_verb

paradigms.noun_gender = function(code) return code:byte(3)&3 end

local function cut(word, ending)
  return word:sub(1, #word-ending)
end

local function word_at(str, index)
  local words = {}
  for word in str:gmatch("([^\x20]+)") do table.insert(words, word) end
  return words[index]
end

function paradigms.pronoun(plural, person, gender, form)
  local row
  if plural then
    row = person == 1 and 6 or person == 2 and 7 or 8
  elseif person == 1 then
    row = 1
  elseif person == 2 then
    row = 2
  else
    row = gender == 2 and 5 or gender == 0 and 4 or 3
  end
  -- Pronoun rows contain genitive through prepositional, corresponding to cases 2-6.
  return word_at(pronouns[row], math.max(1, (form or 4) - 1))
end

function paradigms.noun(base, table_id, e)
  local ext = utils.extract(base)
  local len, str = table.unpack(paradigms.nouns[e.gender+1][table_id+1])
  if e.plural then
    -- Plural forms occupy positions 6-11 in the paradigm string.
    -- Position 6 = nominative plural, 7 = genitive plural, … 11 = prepositional plural.
    -- LTGOLD stores these directly in the same paradigm entry; we index them here.
    local pl_idx = (e.form == 1) and 6 or (e.form + 5)
    local suffix = word_at(str, pl_idx)
    if suffix == '' then return utils.decode(base, true) end
    -- '=' means "bare stem" (no suffix appended) — e.g. gen.pl "сторон" from "сторона"
    if suffix == '=' then return utils.decode(ext:sub(1, #ext-len), true) end
    return utils.decode(ext:sub(1, #ext-len), true) .. suffix
  else
    local suffix = word_at(str, e.form-1)
    if e.form == 1 or suffix == '=' then return utils.decode(base, true) end
    return utils.decode(ext:sub(1, #ext-len), true)..suffix
  end
end

function paradigms.adjective(base, table_id, e, utf8)
  local ext = utils.extract(base)
  local stem_cut, selected = table.unpack(native.adjectives[e.gender+1][table_id+1])
  -- Positions 7-12 in LTGOLD adjective paradigms are the six plural cases.
  local suffix = word_at(selected, e.plural and (e.form + 6) or e.form)
  -- The original record supplies a byte cut; the optional UTF-8 input uses two bytes per Cyrillic letter.
  return utils.decode(ext:sub(1, #ext - stem_cut * (utf8 and 2 or 1)), true)..suffix
end

-- reflexive_suffix: determine whether -сь or -ся follows a verb ending.
-- Russian rule: -сь after vowels and soft sign (ь), -ся after consonants.
local function reflexive_suffix(ending)
  if #ending == 0 then return "ся" end
  -- check last 2 bytes (one UTF-8 Cyrillic char) against vowel list
  local last2 = ending:sub(-2)
  local vowels = {["ю"]="сь",["у"]="сь",["е"]="сь",["а"]="сь",
                  ["о"]="сь",["и"]="сь",["ы"]="сь",["э"]="сь",["ь"]="сь"}
  return vowels[last2] or "ся"
end

function paradigms.verb(base, table_id, e)
  local extracted = utils.extract(base)
  local len, str = table.unpack(paradigms.verbs[table_id+1])
  -- Reflexive verbs (CP866 stem ends in с=0xE1 + я=0xEF = "-ся").
  -- LTGOLD stores these under the same paradigm as non-reflexive counterparts;
  -- conjugation needs 2 extra bytes removed and the reflexive suffix appended.
  local reflexive = #extracted >= 2 and
    extracted:byte(#extracted-1) == 0xE1 and  -- с
    extracted:byte(#extracted) == 0xEF         -- я
  local stem_cut = reflexive and (len + 2) or len
  local stem = cut(extracted, stem_cut)
  local index = (e.plural and 3 or 0) + e.person
  if e.imperative then
    local suf = word_at(str, 7)
    return utils.decode(stem, true) .. suf .. (reflexive and reflexive_suffix(suf) or "")
  elseif not e.past then
    local suf = word_at(str, index)
    return utils.decode(stem, true) .. suf .. (reflexive and reflexive_suffix(suf) or "")
  elseif e.passive then
    local part = word_at(str, 13)
    if e.plural and part:sub(-8) == "нный" then
      -- Russian short passive plural uses -ны, not the past-tense -ни pattern.
      return utils.decode(stem, true) .. part:sub(1, -9) .. "ны"
    end
    local short = utf8.len(part) > 3 and string.sub(part, 1, utf8.offset(part, -3) - 1) or ""
    local past_idx = e.plural and 4 or ((e.gender or 1) + 1)
    return utils.decode(stem, true)..short..past_verb[past_idx]
  else
    -- past tense: gender-based agreement (masc="", fem="а", neut="о", pl="и")
    local past_idx = e.plural and 4 or ((e.gender or 1) + 1)
    local past_full = word_at(str, 8) .. past_verb[past_idx]
    return utils.decode(stem, true) .. past_full .. (reflexive and reflexive_suffix(past_full) or "")
  end
end

function paradigms.passive_participle(base, table_id)
  local extracted = utils.extract(base)
  local len, str = table.unpack(paradigms.verbs[table_id+1])
  -- Position 13 is LTGOLD's full passive-participle ending.
  return utils.decode(cut(extracted, len), true) .. word_at(str, 13)
end

function paradigms.gerund(base, table_id, imperfective)
  -- LTGOLD verb paradigms store the resolved adverbial-participle ending in slot 9.
  local extracted = utils.extract(base)
  local len, str = table.unpack(paradigms.verbs[table_id+1])
  if imperfective then len, str = table.unpack(native.imperfective[table_id+1]) end
  local ending = word_at(str, 9)
  return utils.decode(cut(extracted, len), true) .. ending
end

function paradigms.find_adjective(adj)
  for i, t in ipairs(paradigms.adjectives[2]) do
    local w = word_at(t, 1)
    -- Return a 1-based match index; callers convert to 0-based table_id when
    -- passing into paradigms.adjective().
    if t and adj:sub(-#w) == w then return i end
  end
end

return paradigms
