#!/usr/bin/env lua
-- rus_tool.lua — RUS paradigm data management tool
--
-- Search, list, and manage entries in LTGOLD .RUS dictionary files.
-- .RUS files provide morphological metadata (gender, paradigm, aspect)
-- that enables proper Russian inflection for nouns, verbs, and adjectives.
--
-- Usage:
--   lua rus_tool.lua find <word>              Exact search across all .RUS files
--   lua rus_tool.lua find <word> --partial    Substring search
--   lua rus_tool.lua find <word> --dict FILE  Search specific .RUS file
--   lua rus_tool.lua add <word> <spec>        Add entry to BASE.RUS
--   lua rus_tool.lua add <word> <spec> --dict F  Add to specific .RUS file
--   lua rus_tool.lua add <word> <spec> --force    Overwrite if exists
--   lua rus_tool.lua list [FILE] [--limit N]  List entries
--   lua rus_tool.lua paradigms                Show paradigm reference tables
--   lua rus_tool.lua help                     Show this help
--   lua rus_tool.lua help <topic>             Detailed help on topic
--
-- RUS entry format (CP866 encoded):
--   Russian_word*<binary_code>
--
-- Binary code byte layout:
--   Byte 1: Tag — 0x4E=N(noun), 0x56=V(verb), 0x41=A(adjective)
--   Byte 2: Flags (bit 1 = perfective aspect for verbs)
--   Byte 3: Gender (nouns/adjectives): 0=neutral, 1=male, 2=female
--   Byte 4: Paradigm ID (0-based) — indexes into paradigms.nouns/verbs
--   Bytes 5+: (verbs only) Imperfective stem in CP866
--
-- Add spec shorthand:
--   TAG:GENDER:PARADIGM  — e.g. N:m:0, V:i:3, A:f:5
--   TAG: N=noun, V=verb, A=adjective
--   GENDER: m=male, f=female, n=neutral (nouns/adjectives only)
--   PARADIGM: 0-127, paradigm table index

local encoding = require "core.encoding"

local DATA_DIR = "data/"

local RUS_FILES = {
  { file = "BASE.RUS",    label = "BASE.RUS (main paradigm data)" },
  { file = "DUNGEON.RUS", label = "DUNGEON.RUS (adventure game nouns)" },
}

-- normalize: re-encode any UTF-8 Cyrillic to CP866 so overlay files
-- written in UTF-8 behave identically to base CP866 files.
local function normalize_line(line)
  return (line:gsub("[\xC0-\xDF][\x80-\xBF]", function(seq)
    local b1, b2 = seq:byte(1), seq:byte(2)
    local cp = (b1 - 0xC0) * 64 + (b2 - 0x80)
    if cp >= 0x0410 and cp <= 0x042F then return string.char(cp - 0x0410 + 0x80) end
    if cp >= 0x0430 and cp <= 0x043F then return string.char(cp - 0x0430 + 0xA0) end
    if cp >= 0x0440 and cp <= 0x044F then return string.char(cp - 0x0440 + 0xE0) end
    if cp == 0x0451 then return "\xF1" end
    if cp == 0x0401 then return "\xF0" end
    return seq
  end))
end

-------------------------------------------------------------------------------
-- File I/O
-------------------------------------------------------------------------------

local function read_lines(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = line
  end
  f:close()
  return lines
end

local function write_lines(path, lines)
  local f = io.open(path, "wb")
  if not f then return false, "cannot write: " .. path end
  for _, line in ipairs(lines) do
    f:write(line)
    f:write("\n")
  end
  f:close()
  return true
end

local function parse_entry(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  if trimmed == "" or trimmed:sub(1, 1) == "#" then return nil, nil end
  local word, code = trimmed:match("^(.-)\x2a(.*)$")
  return word, code
end

local function is_rus_file(path)
  return path:match("%.RUS$") or path:match("%.rus$")
end

-------------------------------------------------------------------------------
-- Hex ↔ binary conversion
-------------------------------------------------------------------------------

local function hex_to_binary(hex)
  hex = hex:gsub("%s", ""):upper()
  if #hex % 2 ~= 0 then
    return nil, "hex string must have even number of characters"
  end
  if not hex:match("^[0-9A-F]+$") then
    return nil, "invalid hex characters (use 0-9, A-F)"
  end
  local bytes = {}
  for i = 1, #hex, 2 do
    bytes[#bytes + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
  end
  return table.concat(bytes)
end

local function binary_to_hex(code)
  local t = {}
  for i = 1, #code do
    t[#t + 1] = string.format("%02X", code:byte(i))
  end
  return table.concat(t, " ")
end

-------------------------------------------------------------------------------
-- Decode binary code into human-readable details
-------------------------------------------------------------------------------

local TAG_NAMES = { [0x4E] = "N", [0x56] = "V", [0x41] = "A" }
local GENDER_NAMES = { [0] = "neutral", [1] = "male", [2] = "female" }

local function decode_code(code)
  if not code or #code < 4 then return nil end
  local b1 = code:byte(1)
  local b2 = code:byte(2)
  local b3 = code:byte(3)
  local b4 = code:byte(4)

  local tag = TAG_NAMES[b1] or "?"
  local gender, paradigm

  if tag == "N" or tag == "A" then
    gender = b3 % 4   -- bits 0–1 of byte 3
    paradigm = b4 % 128  -- bit 7 cleared
  elseif tag == "V" then
    paradigm = b4 % 128
  end

  return {
    tag = tag,
    gender = gender,
    gender_name = gender and GENDER_NAMES[gender] or nil,
    paradigm = paradigm,
    flags = b2,
    perfective = tag == "V" and (b2 % 4 < 2) or nil,
    has_imperfective_stem = tag == "V" and #code > 5,
  }
end

-------------------------------------------------------------------------------
-- Search all RUS files for a word
-------------------------------------------------------------------------------

local function cmd_find(word, options)
  options = options or {}
  local search_word = word:lower()
  local found = false

  for _, rus in ipairs(RUS_FILES) do
    if not options.dict or options.dict:lower() == rus.file:lower() then
      local path = DATA_DIR .. rus.file
      local lines = read_lines(path)
      if lines then
        for i, line in ipairs(lines) do
          local entry_word, code = parse_entry(line)
          if entry_word then
            local decoded_word = encoding.decode(entry_word)
            local match = false
            if options.partial then
              match = decoded_word:lower():find(search_word, 1, true)
            else
              match = decoded_word:lower() == search_word
            end
            if match then
              local info = decode_code(code)
              print(string.format("  %s:%d", rus.file, i))
              print(string.format("    word:  %s", decoded_word))
              if info then
                local detail = string.format("    tag: %s", info.tag)
                if info.gender_name then
                  detail = detail .. string.format(", gender: %s", info.gender_name)
                end
                if info.paradigm then
                  detail = detail .. string.format(", paradigm: %d", info.paradigm)
                end
                if info.perfective ~= nil then
                  detail = detail .. string.format(", %s",
                    info.perfective and "perfective" or "imperfective")
                end
                if info.has_imperfective_stem then
                  detail = detail .. ", has imperfective stem"
                end
                print(detail)
              end
              print(string.format("    code:  %s", binary_to_hex(code)))
              print()
              found = true
            end
          end
        end
      end
    end
  end

  if not found then
    print(string.format("  No entries found for '%s'", word))
    if options.dict then
      print(string.format("  (searched in %s)", options.dict))
    else
      print("  (searched all .RUS files)")
    end
    print()
    print("  TIP: Use 'lua rus_tool.lua find \"<word>\" --partial' for substring search")
  end

  return found
end

-------------------------------------------------------------------------------
-- List entries from RUS files
-------------------------------------------------------------------------------

local function cmd_list(dict_name, options)
  options = options or {}
  local limit = options.limit or 100

  for _, rus in ipairs(RUS_FILES) do
    if not dict_name or dict_name:lower() == rus.file:lower() then
      local path = DATA_DIR .. rus.file
      local lines = read_lines(path)
      if lines then
        local count = 0
        print(string.format("--- %s (%d entries) ---", rus.label, #lines))
        for _, line in ipairs(lines) do
          local entry_word, code = parse_entry(line)
          if entry_word then
            local dw = encoding.decode(entry_word)
            local info = decode_code(code)
            local tag_str = info and info.tag or "?"
            local paradigm_str = info and info.paradigm and tostring(info.paradigm) or "?"
            print(string.format("  %s [%s] p%s  %s", dw, tag_str, paradigm_str,
              binary_to_hex(code)))
            count = count + 1
            if count >= limit then
              print(string.format("  ... (showing %d of %d entries, use --limit N to show more)",
                limit, #lines))
              break
            end
          end
        end
        print()
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Shorthand specification parser
--   "N:m:0"  → noun, male, paradigm 0
--   "V:i:3"  → verb, imperfective, paradigm 3
--   "A:f:5"  → adjective, female, paradigm 5
-- Also accepts space-separated: "N male 0", "V imperfective 3"
-------------------------------------------------------------------------------

local TAG_VALUES = { N = 0x4E, V = 0x56, A = 0x41 }
local GENDER_VALUES = { m = 1, male = 1, f = 2, female = 2, n = 0, neutral = 0 }

local function parse_spec(spec)
  local tag_s, gender_s, paradigm_s

  if spec:find(":") then
    tag_s, gender_s, paradigm_s = spec:match("^([NnVvAa]):([^:]+):(%d+)$")
  else
    local parts = {}
    for part in spec:gmatch("[^%s]+") do parts[#parts + 1] = part end
    if #parts == 3 then
      tag_s, gender_s, paradigm_s = parts[1], parts[2], parts[3]
    elseif #parts == 2 then
      tag_s, paradigm_s = parts[1], parts[2]
    end
  end

  if not tag_s then return nil, "invalid spec format" end

  local tag_upper = tag_s:upper()
  local tag_val = TAG_VALUES[tag_upper]
  if not tag_val then
    return nil, string.format("unknown tag '%s' (use N, V, or A)", tag_s)
  end

  local paradigm = tonumber(paradigm_s)
  if not paradigm or paradigm < 0 or paradigm > 127 then
    return nil, string.format("paradigm must be 0-127, got '%s'", paradigm_s)
  end

  local gender_val
  if tag_upper == "N" or tag_upper == "A" then
    if not gender_s or gender_s == "" then
      return nil, string.format("%s requires gender (m=male, f=female, n=neutral)", tag_upper)
    end
    gender_val = GENDER_VALUES[gender_s:lower()]
    if not gender_val then
      return nil, string.format("unknown gender '%s' (use m, f, or n)", gender_s)
    end
  elseif tag_upper == "V" then
    -- Verbs: gender_s is ignored if present (aspect is encoded in flags, not here)
    if gender_s and gender_s ~= "" and not gender_s:match("^[IiPp]") then
      -- If it looks like a gender word, warn the user
      return nil, string.format("verbs don't have gender — use V:i:3 (imperfective) or V:p:3 (perfective)")
    end
  end

  -- Build 4-byte binary code: tag, flags, gender, paradigm
  local flags = 0x00
  if tag_upper == "V" and gender_s and gender_s:lower() == "i" then
    flags = 0x02  -- bit 1 = imperfective aspect
  end
  local gender_byte = gender_val or 0
  local paradigm_byte = paradigm  -- high bit 0, safe for 0-127

  local binary = string.char(tag_val, flags, gender_byte, paradigm_byte)
  return binary
end

-------------------------------------------------------------------------------
-- Add entry to a RUS file
--   Descriptive: lua rus_tool.lua add "орк" "N:m:0"
--   Hex:         lua rus_tool.lua add "орк" "4EA08181"
-------------------------------------------------------------------------------

local function cmd_add(word, spec_or_hex, options)
  options = options or {}
  local target = options.dict or "BASE.RUS"

  if not word or word == "" then
    print("  ERROR: word cannot be empty")
    return false
  end

  if not spec_or_hex or spec_or_hex == "" then
    print("  ERROR: paradigm spec or hex code required")
    print("  Descriptive:  lua rus_tool.lua add \"орк\" \"N:m:0\"")
    print("  Hex:          lua rus_tool.lua add \"орк\" \"4E000100\"")
    print("  Use 'lua rus_tool.lua paradigms' for paradigm reference")
    return false
  end

  -- Try descriptive shorthand first (contains ":" or is "N/V/A <gender> <paradigm>")
  local binary_code
  if spec_or_hex:find(":") or spec_or_hex:match("^[NnVvAa]") then
    local err
    binary_code, err = parse_spec(spec_or_hex)
    if not binary_code then
      print("  ERROR: " .. err)
      print("  Format: TAG:GENDER:PARADIGM  (e.g. N:m:0, V:i:3, A:f:5)")
      print("  Tags:     N=noun  V=verb  A=adjective")
      print("  Genders:  m=male  f=female  n=neutral  (nouns/adjectives only)")
      print("  Paradigm: 0-127, see 'lua rus_tool.lua paradigms'")
      return false
    end
  else
    -- Fall back to hex
    local err
    binary_code, err = hex_to_binary(spec_or_hex)
    if not binary_code then
      print("  ERROR: " .. err)
      print("  Expected descriptive spec (N:m:0) or hex bytes (4E000100)")
      return false
    end
    if #binary_code < 4 then
      print("  ERROR: hex code must be at least 4 bytes")
      return false
    end
    local tag = binary_code:byte(1)
    if tag ~= 0x4E and tag ~= 0x56 and tag ~= 0x41 then
      print(string.format("  ERROR: byte 1 must be 0x4E (N), 0x56 (V), or 0x41 (A), got 0x%02X", tag))
      return false
    end
  end

  local path = DATA_DIR .. target
  local lines = read_lines(path)
  if not lines then
    print("  ERROR: cannot read " .. path)
    print("  Does the file exist?")
    return false
  end

  -- Check for duplicate
  local search_word = word:lower()
  for i, line in ipairs(lines) do
    local entry_word = parse_entry(line)
    if entry_word then
      local decoded = encoding.decode(entry_word)
      if decoded:lower() == search_word then
        print(string.format("  WARNING: '%s' already exists at line %d", decoded, i))
        if not options.force then
          print("  Use --force to overwrite")
          return false
        end
        table.remove(lines, i)
        break
      end
    end
  end

  -- Build the line: Russian_word*<binary_code>
  local encoded_word = encoding.encode(word)
  local new_line = encoded_word .. "\x2a" .. binary_code

  -- Insert in sorted order
  local insert_pos = #lines + 1
  for i, line in ipairs(lines) do
    local entry_word = parse_entry(line)
    if entry_word then
      if entry_word:lower() > word:lower() then
        insert_pos = i
        break
      end
    end
  end

  table.insert(lines, insert_pos, new_line)

  local ok, write_err = write_lines(path, lines)
  if not ok then
    print("  ERROR: " .. write_err)
    return false
  end

  local info = decode_code(binary_code)
  print(string.format("  Added '%s' to %s (line %d)", word, target, insert_pos))
  if info then
    local detail = string.format("    tag: %s", info.tag)
    if info.gender_name then detail = detail .. string.format(", gender: %s", info.gender_name) end
    if info.paradigm then detail = detail .. string.format(", paradigm: %d", info.paradigm) end
    print(detail)
  end
  print(string.format("    code: %s", binary_to_hex(binary_code)))
  return true
end

-------------------------------------------------------------------------------
-- Paradigms reference
-------------------------------------------------------------------------------

local function cmd_paradigms()
  print([[
=== RUS Paradigm Reference ===

BYTE LAYOUT: tag(1) flags(2) gender(3) paradigm(4) [imperfective_stem(5+)]

BYTE 1 — TAG:
  0x4E = N (noun)       — paradigm indexes paradigms.nouns[gender+1]
  0x56 = V (verb)       — paradigm indexes paradigms.verbs[paradigm_id+1]
  0x41 = A (adjective)  — paradigm indexes paradigms.adjectives[gender+1]

BYTE 2 — FLAGS:
  Bit 1 (value 0x02): 0=perfective, 1=imperfective (verbs only)
  Other bits vary by entry; use 0x00 as safe default for new entries.

BYTE 3 — GENDER (nouns/adjectives):
  0x00 = neutral (it/он оно)
  0x01 = male (he/он)
  0x02 = female (she/она)

BYTE 4 — PARADIGM ID (0-based, high bit ignored):
  Extract: paradigm_id = byte4 & 0x7F
  Nouns → paradigms.nouns[gender+1][paradigm_id+1]
  Verbs → paradigms.verbs[paradigm_id+1]
  Adjectives → paradigms.adjectives[gender+1][paradigm_id+1]

BYTE 5+ — IMPERFECTIVE STEM (verbs only, perfective entries):
  CP866-encoded Russian infinitive of the paired imperfective verb.
  Example: набрать has stem bytes encoding "набирать".

COMMON PATTERNS:

  Noun, male, consonant stem:  4E _ 01 <paradigm>
    paradigm 0: тролль → тролля, троллю, тролля, троллем, о тролле
    paradigm 1: такт → такта, такту, такт, тактом, о такте

  Noun, female, -а ending:     4E _ 02 <paradigm>
    paradigm 0: свеча → свечи, свече, свечу, свечой, о свече

  Noun, neutral, -о ending:    4E _ 00 <paradigm>
    paradigm 0: окно → окна, окну, окно, окном, об окне

  Verb, imperfective:          56 _2_ _ <paradigm>
    paradigm 0: писать → пишу, пишет, пишем, пишете, пишут

  Verb, perfective:            56 _0_ _ <paradigm> <imperfective_stem>
    paradigm 0: написать → напишу, напишет, напишем, напишете, напишут

LOOKING UP PARADIGM IDS:
  1. Find an existing word with the same ending pattern in BASE.RUS
  2. Read its paradigm ID from byte 4: byte4 & 0x7F
  3. Use the same paradigm ID for your new word

  Example: find "свеча" in BASE.RUS → 4E C0 82 8E
    byte4 = 0x8E → 0x8E & 0x7F = 14 → paradigm 14
    So any female -а noun with the same declension pattern uses paradigm 14.
]])
end

-------------------------------------------------------------------------------
-- HELP
-------------------------------------------------------------------------------

local HELP_TOPICS = {}

HELP_TOPICS["overview"] = [[
=== RUS Tool Overview ===

Manage paradigm data in .RUS files for the en-ru-translator.
.RUS files provide morphological metadata (gender, paradigm ID, aspect)
that enables proper Russian inflection for nouns, verbs, and adjectives.

FILE FORMAT:
  One entry per line: Russian_word*<binary_code>
  Binary code is 4+ bytes: tag, flags, gender, paradigm ID.
  CP866 encoded (UTF-8 in overlay files is auto-normalized).

RELATIONSHIP TO .DIC FILES:
  .DIC files map English words → Russian lemma + grammatical tag
  .RUS files map Russian lemma → morphological paradigm data
  Both are needed for nouns, verbs, and adjectives.

  Example for "orc":
    BASE.DIC:  orc*Nорк         (English → Russian + noun tag)
    BASE.RUS:  орк*N:m:0        (Russian → gender=male, paradigm=0)

  Without a .RUS entry, the compiler cannot decline the noun.

ADDING ENTRIES:
  Descriptive:  lua rus_tool.lua add "орк" "N:m:0"
  Hex:          lua rus_tool.lua add "орк" "4E000100"

EXAMPLES:
  lua rus_tool.lua find свеча           # find exact match
  lua rus_tool.lua find свеч --partial  # substring match
  lua rus_tool.lua list BASE.RUS        # list all entries
  lua rus_tool.lua add "орк" "N:m:0"   # add with shorthand
  lua rus_tool.lua paradigms            # paradigm reference
]]

HELP_TOPICS["find"] = [[
=== Searching RUS Entries ===

SYNOPSIS:
  lua rus_tool.lua find <word> [options]

OPTIONS:
  --dict <file>   Search only this .RUS file
  --partial       Substring search instead of exact match

EXAMPLES:

  1. Find a specific word:
     lua rus_tool.lua find свеча

  2. Substring search:
     lua rus_tool.lua find свеч --partial

  3. Search specific file:
     lua rus_tool.lua find тролль --dict DUNGEON.RUS

OUTPUT:
  Each match shows: file, line number, word, tag, gender, paradigm, hex code.
  Use the paradigm ID to find matching declension patterns.
]]

HELP_TOPICS["add"] = [[
=== Adding RUS Entries ===

SYNOPSIS:
  lua rus_tool.lua add <word> <spec> [options]

The <spec> is a paradigm specification — either descriptive shorthand or hex.

DESCRIPTIVE SHORTHAND (recommended):
  TAG:GENDER:PARADIGM

  TAG:      N = noun, V = verb, A = adjective
  GENDER:   m = male, f = female, n = neutral  (nouns/adjectives only)
  PARADIGM: 0-127, indexes the paradigm table in core/paradigms.lua

  Examples:
    N:m:0    noun,      male,      paradigm 0  (consonant stem: тролль)
    N:f:14   noun,      female,    paradigm 14 (-а ending: свеча)
    N:n:7    noun,      neutral,   paradigm 7  (-о ending: окно)
    V:i:3    verb,      imperfective, paradigm 3
    V:p:31   verb,      perfective,    paradigm 31
    A:m:5    adjective, male,      paradigm 5

  Space-separated also works:
    "N male 0"   "V imperfective 3"   "A female 5"

HEX FORMAT (advanced):
  4 hex bytes: TAG FLAGS GENDER PARADIGM
  Example: 4E 00 01 00 = noun, flags=0, male, paradigm 0

OPTIONS:
  --dict <file>   Target .RUS file (default: BASE.RUS)
  --force         Overwrite existing entry

WORKED EXAMPLES:

  1. Add a masculine noun for "orc" (орк):
     lua rus_tool.lua add "орк" "N:m:0"
     → adds: орк*<4E 00 01 00>

  2. Add a feminine noun for "candle" (свечка):
     lua rus_tool.lua add "свечка" "N:f:0"
     → adds: свечка*<4E 00 02 00>

  3. Add a neuter noun for "window" (окошко):
     lua rus_tool.lua add "окошко" "N:n:7"
     → adds: окошко*<4E 00 00 07>

  4. Add an imperfective verb:
     lua rus_tool.lua add "сражаться" "V:i:3"
     → adds: сражаться*<56 02 00 03>

  5. Add a perfective verb (hex for imperfective stem):
     lua rus_tool.lua add "набрать" "5600001F" --dict BASE.RUS
     (imperfective stem bytes must be added manually to the file)

  6. Add to overlay file:
     lua rus_tool.lua add "ларец" "N:m:0" --dict DUNGEON.RUS

FINDING THE RIGHT PARADIGM:
  1. Find an existing word with the same ending:
     lua rus_tool.lua find <word> --partial
  2. Note the paradigm ID from the output
  3. Use the same paradigm for your new word

  Example: "ларец" ends in -ец like "скарабей" (paradigm 0)
           → lua rus_tool.lua add "ларец" "N:m:0"

FINDING THE RIGHT GENDER:
  Russian nouns have fixed grammatical gender. Check a Russian dictionary
  or match the gender of existing words with the same ending:
  - Male:   consonant ending (тролль, меч, ларец)
  - Female: -а/-я ending (свеча, комната, земля)
  - Neutral: -о/-е ending (окно, поле, море)
]]

HELP_TOPICS["list"] = [[
=== Listing RUS Entries ===

SYNOPSIS:
  lua rus_tool.lua list [dict] [options]

OPTIONS:
  --limit N   Show at most N entries (default: all)

EXAMPLES:

  1. List all entries in all .RUS files:
     lua rus_tool.lua list

  2. List entries in BASE.RUS only:
     lua rus_tool.lua list BASE.RUS

  3. List first 20 entries:
     lua rus_tool.lua list --limit 20

OUTPUT FORMAT:
  word [tag] p<paradigm>  HEX HEX HEX HEX
  Example: тролль [N] p0  4E A0 81 81
]]

HELP_TOPICS["paradigms"] = HELP_TOPICS["paradigms"]  -- alias, set below

local function cmd_help(topic)
  if topic and HELP_TOPICS[topic] then
    print(HELP_TOPICS[topic])
  elseif topic then
    print(string.format("  Unknown help topic: '%s'", topic))
    print("  Available topics: overview, find, add, list, paradigms")
  else
    print([[
=== rus_tool.lua — RUS Paradigm Data Management ===

Manage .RUS paradigm files for the en-ru-translator.

COMMANDS:
  lua rus_tool.lua find <word>              Exact search across all .RUS files
  lua rus_tool.lua find <word> --partial    Substring search
  lua rus_tool.lua find <word> --dict FILE  Search specific .RUS file
  lua rus_tool.lua add <word> <spec>        Add entry to BASE.RUS
  lua rus_tool.lua add <word> <spec> --dict F  Add to specific .RUS file
  lua rus_tool.lua add <word> <spec> --force    Overwrite if exists
  lua rus_tool.lua list [DICT]              List entries in .RUS files
  lua rus_tool.lua list --limit N           Limit output
  lua rus_tool.lua paradigms                Show paradigm reference tables
  lua rus_tool.lua help                     Show this help
  lua rus_tool.lua help <topic>             Detailed help on topic

ADD SPEC (shorthand or hex):
  TAG:GENDER:PARADIGM   e.g. N:m:0, V:i:3, A:f:5
  TAG:       N=noun  V=verb  A=adjective
  GENDER:    m=male  f=female  n=neutral  (nouns/adjectives only)
  PARADIGM:  0-127, indexes paradigm tables in core/paradigms.lua

HELP TOPICS:
  overview   General overview of .RUS files and how they work
  find       How to search for entries
  add        How to add new entries with descriptive specs
  list       How to list dictionary contents
  paradigms  Paradigm ID reference tables

EXAMPLES:
  lua rus_tool.lua find тролль
  lua rus_tool.lua find свеч --partial
  lua rus_tool.lua add "орк" "N:m:0"
  lua rus_tool.lua add "свечка" "N:f:0" --dict DUNGEON.RUS
  lua rus_tool.lua list BASE.RUS --limit 10
  lua rus_tool.lua paradigms
]])
  end
end

-- set the alias after cmd_help is defined
HELP_TOPICS["paradigms"] = nil  -- will be filled by cmd_paradigms output

-------------------------------------------------------------------------------
-- CLI argument parsing
-------------------------------------------------------------------------------

local function parse_args(args)
  local result = { command = nil, word = nil, spec = nil }
  local options = {}
  local i = 1

  while i <= #args do
    local arg = args[i]
    if arg == "--dict" then
      i = i + 1
      options.dict = args[i]
    elseif arg == "--force" then
      options.force = true
    elseif arg == "--partial" then
      options.partial = true
    elseif arg == "--limit" then
      i = i + 1
      options.limit = tonumber(args[i]) or 100
    else
      if not result.command then
        result.command = arg
      elseif not result.word then
        result.word = arg
      elseif not result.spec then
        result.spec = arg
      end
    end
    i = i + 1
  end

  return result, options
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

local args = { ... }
local parsed, options = parse_args(args)

if not parsed.command then
  cmd_help()
  os.exit(0)
end

local command = parsed.command:lower()

if command == "help" then
  cmd_help(parsed.word)

elseif command == "find" then
  if not parsed.word then
    print("  Usage: lua rus_tool.lua find <word> [--partial] [--dict FILE]")
    os.exit(1)
  end
  cmd_find(parsed.word, options)

elseif command == "add" then
  if not parsed.word or not parsed.spec then
    print("  Usage: lua rus_tool.lua add <word> <spec> [--dict FILE] [--force]")
    print("  Spec: TAG:GENDER:PARADIGM (e.g. N:m:0, V:i:3, A:f:5)")
    print("  Use 'lua rus_tool.lua paradigms' for paradigm reference")
    os.exit(1)
  end
  cmd_add(parsed.word, parsed.spec, options)

elseif command == "list" then
  cmd_list(parsed.word, options)

elseif command == "paradigms" then
  cmd_paradigms()

else
  print(string.format("  Unknown command: '%s'", command))
  print("  Run 'lua rus_tool.lua help' for usage")
  os.exit(1)
end
