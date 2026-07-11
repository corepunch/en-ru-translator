-- Tests for parser.collect() — the pure rule-application core.
-- These exercise the tag-stream transformations without touching I/O or the compiler.
local utils = require "core.utils"
local parser = require "core.parser"
local dictionary_store = require "dictionary_store"

local english = dictionary_store.load()

local function assert_eq(a, b, msg)
  assert(a == b, (msg or "?") .. ": expected [" .. tostring(b) .. "], got [" .. tostring(a) .. "]")
end

local function tags(sentence)
  local ts = utils.tokenize(sentence, english)
  local result = assert(parser.collect(english, ts))
  local t = {}
  for i, tok in ipairs(result) do t[i] = tok:sub(1, 1) end
  return table.concat(t, " ")
end

local enc = require "core.encoding"

local function first_cyrillic(sentence)
  local ts = utils.tokenize(sentence, english)
  local result = assert(parser.collect(english, ts))
  for _, tok in ipairs(result) do
    local d = enc.decode_cyrillic(tok)
    if d and #d > 0 then return d end
  end
  return nil
end

-- ── Tag-sequence assertions ────────────────────────────────────────────────

-- Personal pronoun + modal + main verb
assert_eq(tags("She can speak."), "R U V .", "She can speak: R U V .")

-- Copula sentence: determiner + noun + copula + NP
assert_eq(tags("He is in the house."), "R X P T N .", "He is in the house: R X P T N .")

-- Passive voice collapses was+signed into N V
assert_eq(tags("The agreement was signed."), "T N V .", "The agreement was signed: T N V .")

-- Demonstrative + noun + copula + NP
assert_eq(tags("This agreement is a sample for testing the electronic translation program."),
  "O N X T N P G T N A N .", "demonstrative NP")

-- ── Z-ambiguity resolution ─────────────────────────────────────────────────
-- 'open' before a noun → adjective A, not verb V or Z
do
  local ts = utils.tokenize("an open field", english)
  local result = assert(parser.collect(english, ts))
  -- expect T A N (article, adjective, noun)
  local t = {}
  for i, tok in ipairs(result) do t[i] = tok:sub(1, 1) end
  assert_eq(table.concat(t, " "), "T A N", "open before noun → A")
end

-- ── Russian lexeme after parse ─────────────────────────────────────────────
-- After parsing, the pronoun token for "She" carries the Russian word "она"
do
  local ts = utils.tokenize("She can speak.", english)
  local result = assert(parser.collect(english, ts))
  local pron = result[1]
  assert_eq(pron:sub(1, 1), "R", "first token is R (pronoun)")
  local d = enc.decode_cyrillic(pron)
  assert_eq(d, "она", "pronoun decoded to она")
end

print("parser tests passed")
