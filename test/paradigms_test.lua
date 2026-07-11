-- Tests for pure morphological paradigm tables.
-- Paradigm functions accept CP866-encoded tokens but return UTF-8 strings.
local paradigms = require "core.paradigms"
local encoding = require "core.encoding"
local dictionary_store = require "dictionary_store"

local function cp(s) return encoding.encode(s) end
local function assert_eq(a, b, msg)
  assert(a == b, (msg or "?") .. ": expected [" .. tostring(b) .. "], got [" .. tostring(a) .. "]")
end

local _, russian = dictionary_store.load()

-- ── Nouns ──────────────────────────────────────────────────────────────────
-- дом (house) masculine, paradigm 0
local bdom = russian["дом"]
local pdom = bdom:byte(4) & ~0x80
local ntk = "N" .. cp("дом")

local function noun_case(form, plural)
  return paradigms.noun(ntk, pdom, { plural = plural or false, form = form, gender = 1 })
end

assert_eq(noun_case(1),      "дом",   "дом nom sg")
assert_eq(noun_case(2),      "дома",  "дом gen sg")
assert_eq(noun_case(3),      "дому",  "дом dat sg")
assert_eq(noun_case(4),      "дом",   "дом acc sg")
assert_eq(noun_case(5),      "домом", "дом ins sg")
assert_eq(noun_case(6),      "доме",  "дом prep sg")
assert_eq(noun_case(1, true),"дома",  "дом nom pl")

-- ── Verbs ──────────────────────────────────────────────────────────────────
-- говорить (to speak) imperfective, paradigm 42
local bv = russian["говорить"]
local pv = bv:byte(4) & ~0x80
local vtk = "V" .. cp("говорить")

local function verb_form(past, plural, gender, person)
  return paradigms.verb(vtk, pv, {
    plural = plural or false,
    form = 1,
    gender = gender or 1,
    person = person or 3,
    perfective = false,
    infinitive = false,
    past = past or false,
  })
end

assert_eq(verb_form(false, false, 1, 3), "говорит",  "говорит 3sg pres")
assert_eq(verb_form(false, true,  1, 3), "говорят",  "говорят 3pl pres")
assert_eq(verb_form(true,  false, 1),    "говорил",  "говорил past masc sg")
assert_eq(verb_form(true,  false, 2),    "говорила", "говорила past fem sg")
assert_eq(verb_form(true,  true),        "говорили", "говорили past pl")

-- ── Adjectives ─────────────────────────────────────────────────────────────
-- новый (new): find_adjective returns 1-based index; adjective() takes 0-based
local pa = paradigms.find_adjective("новый") - 1
local atk = "A" .. cp("новый")

local function adj_form(form, gender, plural)
  return paradigms.adjective(atk, pa, { plural = plural or false, form = form, gender = gender or 1 })
end

assert_eq(adj_form(1, 1),      "новый",  "новый nom masc sg")
assert_eq(adj_form(1, 2),      "новая",  "новая nom fem sg")
assert_eq(adj_form(2, 1),      "нового", "нового gen masc sg")
assert_eq(adj_form(3, 1),      "новому", "новому dat masc sg")
assert_eq(adj_form(5, 1),      "новым",  "новым ins masc sg")
assert_eq(adj_form(6, 1),      "новом",  "новом prep masc sg")
assert_eq(adj_form(1, 1, true),"новые",  "новые nom pl")

print("paradigms tests passed")
