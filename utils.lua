local utils = {}
local dbg = require "dbg"
local suffixes = require "suffixes"

local cp866_to_utf8 = {
  [0x80]="А", [0x81]="Б", [0x82]="В", [0x83]="Г",
  [0x84]="Д", [0x85]="Е", [0x86]="Ж", [0x87]="З",
  [0x88]="И", [0x89]="Й", [0x8A]="К", [0x8B]="Л",
  [0x8C]="М", [0x8D]="Н", [0x8E]="О", [0x8F]="П",
  [0x90]="Р", [0x91]="С", [0x92]="Т", [0x93]="У",
  [0x94]="Ф", [0x95]="Х", [0x96]="Ц", [0x97]="Ч",
  [0x98]="Ш", [0x99]="Щ", [0x9A]="Ъ", [0x9B]="Ы",
  [0x9C]="Ь", [0x9D]="Э", [0x9E]="Ю", [0x9F]="Я",

  [0xA0]="а", [0xA1]="б", [0xA2]="в", [0xA3]="г",
  [0xA4]="д", [0xA5]="е", [0xA6]="ж", [0xA7]="з",
  [0xA8]="и", [0xA9]="й", [0xAA]="к", [0xAB]="л",
  [0xAC]="м", [0xAD]="н", [0xAE]="о", [0xAF]="п",
  [0xE0]="р", [0xE1]="с", [0xE2]="т", [0xE3]="у",
  [0xE4]="ф", [0xE5]="х", [0xE6]="ц", [0xE7]="ч",
  [0xE8]="ш", [0xE9]="щ", [0xEA]="ъ", [0xEB]="ы",
  [0xEC]="ь", [0xED]="э", [0xEE]="ю", [0xEF]="я",

  [0xF0]="ё", --[0xF1]="Ё",
}

-- Reverse map: UTF-8 char → CP866 byte (built from cp866_to_utf8)
local utf8_to_cp866 = {}
for code, char in pairs(cp866_to_utf8) do utf8_to_cp866[char] = code end

-- encode: convert UTF-8 string to CP866
-- Used to normalise rule replacement literals (stored UTF-8 in rules.lua) back
-- into CP866 so the compiler decode pipeline works correctly.
function utils.encode(s)
  local t = {}
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    if b < 0x80 then
      t[#t+1] = string.char(b)
      i = i + 1
    else
      local b2 = s:byte(i+1)
      if b2 then
        local cp866b = utf8_to_cp866[s:sub(i, i+1)]
        if cp866b then
          t[#t+1] = string.char(cp866b)
          i = i + 2
        else
          t[#t+1] = string.char(b)
          i = i + 1
        end
      else
        t[#t+1] = string.char(b)
        i = i + 1
      end
    end
  end
  return table.concat(t)
end

function utils.extract(s)
  return s:match("[\127-\255]+")
end

function utils.map(t, f)
  local r = {}
  for i, v in ipairs(t) do r[i] = f(v, i) end
  return r
end

function utils.decode(s, strip)
  local t = {}
  for i = 1, #s do table.insert(t, cp866_to_utf8[s:byte(i)] or string.char(s:byte(i))) end
  return strip and utils.extract(table.concat(t)) or table.concat(t)
end

-- extract_form: return the Russian text belonging to the leading tag only
-- e.g. extract_form("X003бытьUдолжен") → "быть"
--       extract_form("X013- fесть")    → ""
function utils.extract_form(s)
  if #s <= 1 then return "" end
  local i = 2
  while i <= #s and s:byte(i) >= 48 and s:byte(i) <= 57 do i = i + 1 end
  local result = {}
  while i <= #s do
    local b = s:byte(i)
    if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then break end
    if b >= 127 then result[#result+1] = cp866_to_utf8[b] end
    i = i + 1
  end
  return table.concat(result)
end

function utils.debug(w, t, i)
  t = t or {}
  i = i or 0
  if type(w) == 'string' then table.insert(t, string.rep(" ", i)..utils.decode(w)) return end
  for k, v in pairs(w) do 
    table.insert(t, string.rep(" ",i)..k..": ") 
    utils.debug(type(v) == 'table' and v or tostring(v), t, i+1)
    -- table.insert(t, "\n")
  end
  return table.concat(t, " ")
end

-- hex_dump: print a CP866 string as hex + decoded text (for inspecting raw token/base bytes)
function utils.hex_dump(s, label)
  local hex, txt = {}, {}
  for i = 1, #s do
    hex[#hex+1] = string.format("%02X", s:byte(i))
    txt[#txt+1] = cp866_to_utf8[s:byte(i)] or string.char(s:byte(i))
  end
  if label then io.write(label .. ": ") end
  print(table.concat(hex, " ") .. "  |  " .. table.concat(txt))
end

-- decode_token: human-readable breakdown of a BASE.DIC token string
-- Prints each tag+word pair on its own line
function utils.decode_token(t, label)
  if label then print(label .. ":") end
  local i = 1
  while i <= #t do
    local b = t:byte(i)
    -- tag: ASCII letter (32-127) or known uppercase tag (0x40-0x5A, 0x61-0x7A)
    if b >= 32 and b < 128 then
      local tag = string.char(b)
      i = i + 1
      -- collect following high bytes as the Russian word
      local word = {}
      while i <= #t and t:byte(i) >= 128 do
        word[#word+1] = cp866_to_utf8[t:byte(i)] or string.format("\\x%02X", t:byte(i))
        i = i + 1
      end
      if #word > 0 then
        print(string.format("  [%s] %s", tag, table.concat(word)))
      elseif tag ~= " " then
        print(string.format("  [%s] (no text)", tag))
      end
    else
      -- high byte without preceding tag (shouldn't happen in well-formed tokens)
      print(string.format("  \\x%02X (orphan byte)", b))
      i = i + 1
    end
  end
end

-- decode_base_entry: human-readable breakdown of a BASE.RUS paradigm entry
function utils.decode_base_entry(b, label)
  if label then print(label .. ":") end
  if not b or #b == 0 then print("  (empty)") return end
  local tag = string.char(b:byte(1))
  local aspect = b:byte(2)
  local noun_flags = b:byte(3) or 0
  local paradigm = (b:byte(4) or 0) & ~0x80
  local gender = noun_flags & 3
  local plural_only = (noun_flags & 4) ~= 0
  local gender_names = {"neutral", "masculine", "feminine"}
  print(string.format("  tag=%-2s  aspect=0x%02X (perfective=%s)  gender=%s  plural_only=%s  paradigm=%d",
    tag, aspect, tostring((aspect & 2) ~= 0),
    gender_names[gender+1] or "?", tostring(plural_only), paradigm))
  if #b > 5 then
    local perf_stem = {}
    for i = 6, #b do
      perf_stem[#perf_stem+1] = cp866_to_utf8[b:byte(i)] or string.format("\\x%02X", b:byte(i))
    end
    print("  perfective_stem=" .. table.concat(perf_stem))
  end
end

function utils.tokenize(s, en_ru)
  dbg.log(1, "Input:", s)
  -- expand contracted forms into separate words for proper dictionary lookup
  s = s:gsub("cannot", "can not"):gsub("can't", "can not")
  -- strip commas from within digit sequences (e.g. 1,000,000 → 1000000)
  while s:find("(%d+),(%d+)") do s = s:gsub("(%d+),(%d+)", "%1%2") end
  local prev, tbl, words, last, i = nil, {}, {}, 0, 1
  -- caps[i] = true when token i was produced from an all-caps English source word.
  -- Used by the compiler to uppercase Russian output (e.g. AGREEMENT → СОГЛАШЕНИЕ).
  tbl.caps = {}
  local phrase_all_caps = false  -- track caps across multi-word phrase lookups

  local stem_variants = {
    G = { "", "e" },
    E = { "", "e" },
    Z = { "", "e", "y" },
  }
  local adverb_endings = {
    ["ический"] = "ически",
    ["ый"] = "о",
    ["ий"] = "и",
    ["ой"] = "о",
  }

  local function derived_translation(family, lex)
    if family ~= "D" then return lex:sub(2) end
    local adjective = utils.decode(lex:sub(2), true)
    for ending, replacement in pairs(adverb_endings) do
      if adjective:sub(-#ending) == ending then
        return utils.encode(adjective:sub(1, -#ending - 1) .. replacement)
      end
    end
  end

  local function derived_lexeme(word)
    for _, analyzer in ipairs(suffixes) do
      if word:sub(-#analyzer.suffix) == analyzer.suffix then
        local family = analyzer.tag:sub(1, 1)
        local base = word:sub(1, -#analyzer.suffix - 1)
        for _, ending in ipairs(stem_variants[family] or { "" }) do
          local entry = en_ru[base .. ending]
          local lex = entry and entry.__lex
          local source = lex and lex:sub(1, 1)
          if source == "V" or source == "Z" or source == "N" or
             (family == "D" and source == "A") then
            -- Z13 marks English -s ambiguity; an N lemma resolves to plural n.
            local tag = family == "Z" and source == "N" and "n" or family
            local translation = derived_translation(family, lex)
            if translation then return tag .. translation end
          end
        end
      end
    end
  end
  for w in s:gmatch("%w+[,%!%.;:]?") do table.insert(words, w) end
  dbg.log(2, "  Words:", table.concat(words, " | "))
  while i <= #words do
    local word, punct = words[i]:match("(%w+)([,%!%.;:]?)")
    local word_orig = word  -- original case before lowercasing
    word = word:lower()
    -- caps flag encodes original word capitalisation for the compiler:
    --   true   = all-caps (e.g. AGREEMENT) → ALL-CAPS Russian output
    --   "init" = initial-cap (e.g. Metric) → first-letter uppercase Russian output
    --   false  = lowercase → no capitalisation change
    local is_all_caps = word_orig:match("^%u+$") ~= nil  -- every letter uppercase
    local is_init_cap = (not is_all_caps) and word_orig:sub(1,1):match("%u") ~= nil
    local is_caps = is_all_caps and true or (is_init_cap and "init" or false)
    if not prev then
      -- Single all-caps letters (e.g. "A" in "EXHIBIT A") are document designators,
      -- not articles. Bypass dictionary lookup and preserve as proper-noun token.
      local is_designator = is_all_caps and #word == 1 and word:match("%a")
      local derived = (not is_designator) and derived_lexeme(word)
      if (not is_designator) and (en_ru[word] or derived) then
        dbg.log(2, "  Lookup:", word, "→", utils.decode(en_ru[word] and en_ru[word].__lex or derived))
        table.insert(tbl, en_ru[word] and en_ru[word].__lex or derived)
      else
        dbg.log(2, "  Lookup:", word, "→ (not found)")
        -- preserve original case in # token so uppercase tracking works for proper nouns
        table.insert(tbl, '#'..word_orig)
      end
      tbl.caps[#tbl] = is_caps
      phrase_all_caps = is_caps  -- reset phrase tracking to current word's caps
      prev, last = en_ru[word], i
      if punct ~= "" then
        table.insert(tbl, punct)
        tbl.caps[#tbl] = false
      end
    elseif not prev[word] then
      dbg.log(2, "  Phrase break:", word, "→ backtracking to last")
      i, prev = last, nil
    elseif prev[word].__lex then
      dbg.log(2, "  Phrase complete:", word, "→",
        utils.decode(prev[word].__lex))
      -- phrase is all-caps only when every word in the phrase was all-caps
      -- downgrade to "init" if any word was only initial-cap
      if phrase_all_caps == true and is_caps ~= true then
        phrase_all_caps = is_caps  -- downgrade: true→init or true→false
      elseif phrase_all_caps == "init" and is_caps == false then
        phrase_all_caps = false
      end
      tbl[#tbl], last = prev[word].__lex, i
      tbl.caps[#tbl] = phrase_all_caps
      if punct ~= "" then
        table.insert(tbl, punct)
        tbl.caps[#tbl] = false
      end
    else
      dbg.log(2, "  Phrase continue:", word)
      if phrase_all_caps == true and is_caps ~= true then
        phrase_all_caps = is_caps
      elseif phrase_all_caps == "init" and is_caps == false then
        phrase_all_caps = false
      end
      prev = prev[word]
    end
    i = i + 1
  end
  dbg.log(2, "  Tokens:",
    table.concat(utils.map(tbl, function(t)
      return utils.decode(t, true)
    end), " | "))
  return tbl
end


return utils
