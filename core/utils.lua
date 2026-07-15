local utils = {}
local dbg = require "core.dbg"
local suffixes = require "core.suffixes"
local stream = require "core.token_stream"
local encoding = require "core.encoding"

-- encode: convert UTF-8 string to CP866
-- Used to normalise rule replacement literals (stored UTF-8 in rules.lua) back
-- into CP866 so the compiler decode pipeline works correctly.
function utils.encode(s)
  return encoding.encode(s)
end

function utils.extract(s)
  return encoding.extract(s)
end

function utils.map(t, f)
  local r = {}
  for i, v in ipairs(t) do r[i] = f(v, i) end
  return r
end

function utils.decode(s, strip)
  return strip and encoding.decode_cyrillic(s) or encoding.decode(s)
end

-- extract_form: return the Russian text belonging to the leading tag only
-- e.g. extract_form("X003бытьUдолжен") → "быть"
--       extract_form("X013- fесть")    → ""
function utils.extract_form(s)
  if #s <= 1 then return "" end
  local leading = s:byte(1)
  local i = 2
  while i <= #s and s:byte(i) >= 48 and s:byte(i) <= 57 do i = i + 1 end
  -- Some dictionary records repeat their tag after numeric metadata
  -- (V11V.соглашаться); the second tag is structural, not a new form.
  if s:byte(i) == leading then i = i + 1 end
  local result = {}
  while i <= #s do
    local b = s:byte(i)
    if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or
       b == 0x3B or b == 0x5C or b == 0x2E then break end
    if b >= 127 then
      result[#result+1] = encoding.character(b)
    elseif b == 0x20 or b == 0x2D then
      -- LTGOLD lexical forms may be multiword or hyphenated; these ASCII
      -- separators belong to the surface form rather than marking a new tag.
      result[#result+1] = string.char(b)
    end
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
    txt[#txt+1] = encoding.character(s:byte(i)) or string.char(s:byte(i))
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
        word[#word+1] = encoding.character(t:byte(i)) or string.format("\\x%02X", t:byte(i))
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
      perf_stem[#perf_stem+1] = encoding.character(b:byte(i)) or string.format("\\x%02X", b:byte(i))
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
  -- Token provenance is mutated atomically with lexical entries so phrase
  -- backtracking and later parser reorders cannot desynchronise metadata.
  local prev, tbl, words, last, i = nil, stream.new(), {}, 0, 1
  local phrase_all_caps = false  -- track caps across multi-word phrase lookups
  local phrase_component_caps = {}

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
            -- LTPRO keeps the analyzer-selected primary tag at +0x0c and the
            -- dictionary lemma's original class at +0x66.
            if translation then return tag .. translation, source end
          end
        end
      end
    end
  end
  local lexical = s:gsub("([\"'])", " %1 ")
  for raw in lexical:gmatch("%S+") do
    if raw == '"' or raw == "'" then
      table.insert(words, raw)
      goto next_raw
    elseif raw:match("^[,%!%.;:]$") then
      table.insert(words, raw)
      goto next_raw
    end
    local compound, punct = raw:match("([%w%-]+)([,%!%.;:]?)")
    if compound and compound:find('-', 1, true) and not en_ru[compound:lower()] then
      local start = 1
      while true do
        local dash = compound:find('-', start, true)
        if not dash then
          table.insert(words, compound:sub(start) .. punct)
          break
        end
        table.insert(words, compound:sub(start, dash - 1))
        table.insert(words, '-')
        start = dash + 1
      end
    elseif compound then
      table.insert(words, raw)
    end
    ::next_raw::
  end
  dbg.log(2, "  Words:", table.concat(words, " | "))
  while i <= #words do
    if words[i] == '-' or words[i] == '"' or words[i] == "'" or
       words[i]:match("^[,%!%.;:]$") then
      local structural = words[i]
      stream.append(tbl, structural, {
        caps = false, phrases = false, source = structural, component_caps = false,
      })
      prev = nil
      i = i + 1
      goto continue
    end
    local word, punct = words[i]:match("([%w%-]+)([,%!%.;:]?)")
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
      -- LTGOLD initially treats A as the article except when terminal punctuation
      -- makes it an explicit document designator (EXHIBIT A.).
      local is_designator = is_all_caps and #word == 1 and word:match("%a") and
        word ~= "i" and (word ~= "a" or punct ~= "")
      local derived, derived_tag
      if not is_designator then derived, derived_tag = derived_lexeme(word) end
      local lex = en_ru[word] and en_ru[word].__lex
      if (not is_designator) and (lex or derived) then
        dbg.log(2, "  Lookup:", word, "→", utils.decode(lex or derived))
        stream.append(tbl, lex or derived, {
          caps = is_caps, phrases = false, source = word_orig, component_caps = false,
          derived_tag = derived_tag,
        })
      else
        dbg.log(2, "  Lookup:", word, "→ (not found)")
        -- preserve original case in # token so uppercase tracking works for proper nouns
        stream.append(tbl, '#'..word_orig, {
          caps = is_caps, phrases = false, source = word_orig, component_caps = false,
        })
      end
      phrase_all_caps = is_caps  -- reset phrase tracking to current word's caps
      phrase_component_caps = { is_caps }
      prev, last = en_ru[word], i
      if punct ~= "" then
        stream.append(tbl, punct, {
          caps = false, phrases = false, source = punct, component_caps = false,
        })
      end
    elseif not prev[word] then
      -- LTGOLD back-reference multi-word matching: irregular past forms store
      -- a \word escape. Follow it to the base form's multi-word children.
      local backref = prev.__lex and prev.__lex:match('\\(%a+)')
      if backref and en_ru[backref] and en_ru[backref][word] and
         en_ru[backref][word].__lex then
        local base_lex = en_ru[backref][word].__lex
        dbg.log(2, "  Phrase via backref:", word, "→ base:", backref, "→",
          utils.decode(base_lex))
        table.insert(phrase_component_caps, is_caps)
        -- Preserve the first word's tag (e.g. h→E0 for past tense) while
        -- using the base multi-word entry's verb text.
        if base_lex:sub(1,1) == 'W' then
          -- W-token with packed sub-forms: split into verb + preposition tokens.
          -- The verb keeps the first word's tag; the preposition gets its own.
          local prev_tag = tbl[#tbl]:match('^(%a%d*)') or 'V'
          -- Find the V form within the W-token
          local vform = nil
          for j = 2, #base_lex do
            if base_lex:byte(j) == 0x56 then  -- 'V'
              vform = base_lex:sub(j + 1)
              -- Stop at next ASCII tag letter
              vform = vform:match('^([^\65-\90]*)')  -- non-ASCII chars
              break
            end
          end
          -- Find the P form within the W-token
          local pform = nil
          for j = 2, #base_lex do
            if base_lex:byte(j) == 0x50 then  -- 'P'
              pform = base_lex:sub(j)  -- keep the P tag for case info
              break
            end
          end
          if vform then
            tbl[#tbl] = prev_tag .. vform
            stream.set_metadata(tbl, #tbl, {
              caps = phrase_all_caps,
              phrases = true,
              source = tbl.source[#tbl] or word_orig,
              component_caps = { table.unpack(phrase_component_caps) },
            })
          end
          if pform then
            stream.insert(tbl, #tbl + 1, pform, {
              caps = false, phrases = true,
              source = word_orig,
              component_caps = false,
            })
          end
        else
          -- Simple entry (not W-token): use base Russian text but keep original tag.
          -- Extract raw CP866 bytes (not decoded UTF-8) for the token stream.
          local prev_tag = tbl[#tbl]:match('^(%a%d*)') or base_lex:sub(1,1)
          -- Scan past the leading tag and any digits to find the Russian text start.
          local pos = 2  -- skip first tag byte
          while pos <= #base_lex and base_lex:byte(pos) >= 48 and base_lex:byte(pos) <= 57 do
            pos = pos + 1  -- skip digits
          end
          local russian = base_lex:sub(pos)  -- raw CP866 bytes
          -- Stop at the next ASCII tag letter or backslash
          local stop = #russian + 1
          for k = 1, #russian do
            local b = russian:byte(k)
            if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 0x5C then
              stop = k; break
            end
          end
          tbl[#tbl] = prev_tag .. russian:sub(1, stop - 1)
          stream.set_metadata(tbl, #tbl, {
            caps = phrase_all_caps,
            phrases = true,
            source = tbl.source[#tbl] or word_orig,
            component_caps = { table.unpack(phrase_component_caps) },
          })
        end
        last = i
        prev = en_ru[backref][word]
        if punct ~= "" then
          stream.append(tbl, punct, {
            caps = false, phrases = false, source = punct, component_caps = false,
          })
          prev = nil
        end
      else
        dbg.log(2, "  Phrase break:", word, "→ backtracking to last")
        i, prev = last, nil
      end
    elseif prev[word].__lex then
      dbg.log(2, "  Phrase complete:", word, "→",
        utils.decode(prev[word].__lex))
      table.insert(phrase_component_caps, is_caps)
      tbl[#tbl], last = prev[word].__lex, i
      stream.set_metadata(tbl, #tbl, {
        caps = phrase_all_caps,
        phrases = true,
        source = tbl.source[#tbl] or word_orig,
        component_caps = { table.unpack(phrase_component_caps) },
      })
      -- A terminal dictionary node may also have children ("by all means" and
      -- "by all means of"); retain it so the longest lexical phrase can win.
      prev = prev[word]
      if punct ~= "" then
        stream.append(tbl, punct, {
          caps = false, phrases = false, source = punct, component_caps = false,
        })
        prev = nil
      end
    else
      dbg.log(2, "  Phrase continue:", word)
      table.insert(phrase_component_caps, is_caps)
      prev = prev[word]
    end
    i = i + 1
    ::continue::
  end
  dbg.log(2, "  Tokens:",
    table.concat(utils.map(tbl, function(t)
      return utils.decode(t, true)
    end), " | "))
  return tbl
end


return utils
