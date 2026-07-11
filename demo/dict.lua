#!/usr/bin/env lua
-- dict.lua — Dictionary management tool for en-ru-translator
--
-- Search, add, and manage entries in LTGOLD .DIC/.RUS dictionary files.
-- Standalone shell over focused dictionary and encoding operations.
--
-- Usage:
--   lua dict.lua find <word>              Search all dictionaries for a word
--   lua dict.lua find <word> <dict>       Search a specific dictionary
--   lua dict.lua add <word> <codes> <ru>  Add entry to BASE.DIC (English)
--   lua dict.lua add <word> <codes> <ru> --rus  Add entry to BASE.RUS (Russian)
--   lua dict.lua add <word> <codes> <ru> --dict <file>  Add to arbitrary dict
--   lua dict.lua list <dict>              List all entries in a dictionary
--   lua dict.lua list                     List entries in all dictionaries
--   lua dict.lua paradigms                Show available grammatical codes
--   lua dict.lua help                     Show this help
--   lua dict.lua help <topic>             Help on a specific topic
--
-- Dictionary format (CP866 encoded):
--   word*GRAMMATICAL_CODES
--
-- The * character separates the English/Russian word from its grammatical tags.
-- Multiple translations use \ as separator within the codes field.
-- Multi-word entries use spaces in the word part.

-------------------------------------------------------------------------------
-- CP866 ↔ UTF-8 conversion (standalone, no external deps)
-------------------------------------------------------------------------------

local encoding = require "core.encoding"

local function decode(s)
  local t = {}
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    if b < 0x80 then
      t[#t+1] = string.char(b)
      i = i + 1
    else
      local char = encoding.character(b)
      if char then
        t[#t+1] = char
      else
        t[#t+1] = "?"
      end
      i = i + 1
    end
  end
  return table.concat(t)
end

local function encode(s)
  return encoding.encode(s)
end

-------------------------------------------------------------------------------
-- Dictionary I/O
-------------------------------------------------------------------------------

local DATA_DIR = "data/"

local DICTIONARIES = {
  { file = "BASE.DIC",  label = "BASE.DIC  (English→Russian)", type = "en" },
  { file = "BASE.RUS",  label = "BASE.RUS  (Russian→English)", type = "ru" },
  { file = "BUSINESS.DIC", label = "BUSINESS.DIC (business terms)", type = "en" },
  { file = "COMPUTER.DIC", label = "COMPUTER.DIC (computer terms)", type = "en" },
}

-- Read all lines from a file, return as table
local function read_lines(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local lines = {}
  for line in f:lines() do
    lines[#lines+1] = line
  end
  f:close()
  return lines
end

-- Write lines to a file (binary mode to preserve CP866)
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

-- Parse a dictionary line into word + codes
-- Format: word*GRAMMATICAL_CODES
local function parse_entry(line)
  local word, codes = line:match("^(.-)\x2a(.*)$")
  return word, codes
end

-- Parse the dictionary header (first line is "LTech DIC File 2.00\x1aERS\x00")
local function has_header(lines)
  return #lines > 0 and lines[1]:match("^LTech DIC")
end

-------------------------------------------------------------------------------
-- FIND
-------------------------------------------------------------------------------

local function cmd_find(word, dict_name)
  local search_word = word:lower()
  local found = false

  for _, dict in ipairs(DICTIONARIES) do
    if not dict_name or dict.file:lower() == dict_name:lower() then
      local path = DATA_DIR .. dict.file
      local lines = read_lines(path)
      if lines then
        for i, line in ipairs(lines) do
          local entry_word, codes = parse_entry(line)
          if entry_word and entry_word:lower() == search_word then
            local display_word = decode(entry_word)
            local display_codes = codes and decode(codes) or ""
            print(string.format("  %s:%d", dict.file, i))
            print(string.format("    word:  %s", display_word))
            print(string.format("    codes: %s", display_codes))
            print(string.format("    raw:   %s", line:gsub("[\x00-\x1F]", "?")))
            print()
            found = true
          end
        end
      end
    end
  end

  if not found then
    print(string.format("  No entries found for '%s'", word))
    if dict_name then
      print(string.format("  (searched in %s)", dict_name))
    else
      print("  (searched all dictionaries)")
    end
    print()
    print("  TIP: Use 'lua dict.lua find \"<word>\" --partial' for substring search")
  end

  return found
end

-- Partial/substring search
local function cmd_find_partial(word, dict_name)
  local search_word = word:lower()
  local found = false
  local count = 0

  for _, dict in ipairs(DICTIONARIES) do
    if not dict_name or dict.file:lower() == dict_name:lower() then
      local path = DATA_DIR .. dict.file
      local lines = read_lines(path)
      if lines then
        for i, line in ipairs(lines) do
          local entry_word, codes = parse_entry(line)
          if entry_word and entry_word:lower():find(search_word, 1, true) then
            local display_word = decode(entry_word)
            local display_codes = codes and decode(codes) or ""
            print(string.format("  %s:%d  %s → %s", dict.file, i, display_word, display_codes))
            count = count + 1
            found = true
            if count >= 50 then
              print(string.format("  ... (showing first 50 matches)"))
              return true
            end
          end
        end
      end
    end
  end

  if not found then
    print(string.format("  No partial matches for '%s'", word))
  end
  return found
end

-------------------------------------------------------------------------------
-- ADD
-------------------------------------------------------------------------------

local function cmd_add(word, codes, russian, options)
  options = options or {}
  local target = options.dict or "BASE.DIC"
  local path = DATA_DIR .. target

  -- Validate word (ASCII + spaces only for dictionary keys)
  if not word or word == "" then
    print("  ERROR: word cannot be empty")
    return false
  end
  if word:find("\x2a") then
    print("  ERROR: word cannot contain '*' (dictionary separator)")
    return false
  end

  -- Validate codes
  if not codes or codes == "" then
    print("  ERROR: grammatical codes cannot be empty")
    print("  Use 'lua dict.lua paradigms' to see available codes")
    return false
  end

  -- Build the value string: <tags><translation>
  -- In LTGOLD format, the value after * is the grammatical tag(s) followed
  -- by the Russian translation directly (no separator between tag and text).
  -- Example: Nсоглашение (N tag + Russian word)
  -- Example: NN.совет{group};доска{wood} (NN. tag + Russian with alternatives)
  local value = codes
  if russian and russian ~= "" then
    value = codes .. russian
  end

  -- Read existing file
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
    if entry_word and entry_word:lower() == search_word then
      local existing_val = select(2, parse_entry(line))
      print(string.format("  WARNING: '%s' already exists at line %d", word, i))
      print(string.format("    existing: %s", existing_val and decode(existing_val) or ""))
      print(string.format("    new:      %s", decode(value)))
      if not options.force then
        print("  Use --force to overwrite, or edit manually")
        return false
      end
      -- Remove old entry
      table.remove(lines, i)
      break
    end
  end

  -- Encode the entry
  local encoded_word = encode(word)
  local encoded_value = encode(value)
  local new_line = encoded_word .. "\x2a" .. encoded_value

  -- Insert in sorted order (binary search for position)
  local insert_pos = #lines + 1
  for i, line in ipairs(lines) do
    local entry_word = parse_entry(line)
    if entry_word then
      if entry_word:lower() > search_word then
        insert_pos = i
        break
      end
    end
  end

  table.insert(lines, insert_pos, new_line)

  -- Write back
  local ok, err = write_lines(path, lines)
  if not ok then
    print("  ERROR: " .. err)
    return false
  end

  print(string.format("  Added '%s' to %s (line %d)", word, target, insert_pos))
  print(string.format("    value: %s", decode(value)))
  return true
end

-------------------------------------------------------------------------------
-- LIST
-------------------------------------------------------------------------------

local function cmd_list(dict_name, options)
  options = options or {}
  local limit = options.limit or 100

  for _, dict in ipairs(DICTIONARIES) do
    if not dict_name or dict.file:lower() == dict_name:lower() then
      local path = DATA_DIR .. dict.file
      local lines = read_lines(path)
      if lines then
        local count = 0
        local display_limit = options.limit or #lines
        print(string.format("--- %s (%d entries) ---", dict.label, #lines - (has_header(lines) and 1 or 0)))
        for i, line in ipairs(lines) do
          -- skip header line
          if i == 1 and has_header(lines) then
            -- skip
          else
            local entry_word, codes = parse_entry(line)
            if entry_word then
              local dw = decode(entry_word)
              local dc = codes and decode(codes) or ""
              print(string.format("  %s → %s", dw, dc))
              count = count + 1
              if count >= display_limit then
                print(string.format("  ... (showing %d of %d entries, use --limit N to show more)",
                  display_limit, #lines - 1))
                break
              end
            end
          end
        end
        print()
      end
    end
  end
end

-------------------------------------------------------------------------------
-- PARADIGMS — grammatical code reference
-------------------------------------------------------------------------------

local function cmd_paradigms()
  print([[
=== Grammatical Codes (LTGOLD SARMA 2.0) ===

Single-letter tags attached to words after dictionary lookup.
Lowercase = derived/already-resolved form.

CODE  MEANING
────  ─────────────────────────────────────────────────────
 Z    Ambiguity V-N-A (verb/noun/adj unresolved)
 z    Ambiguity v-n (3sg-s form: verb or noun)
 V    Main (content) verb (resolved from Z)
 v    Verb -s/-es form (3rd person singular present)
 N    Noun (singular)
 n    Noun (plural form)
 A    Adjective, ordinal numeral
 a    Adjective-adverb ("more", "less")
 S    Demonstrative pronoun (adjectival: "this book")
 O    Demonstrative pronoun (standalone: "this", "that")
 D    Adverb, parenthetical word/phrase
 d    Adverb/adjective ambiguity
 E    -ed forms and irregular past (past participle / simple past)
 e    Ambiguous: infinitive / participle-II / past tense
 G    -ing verb forms (gerund / present participle)
 F    Active present participle — analyzer-generated
 f    Determiner-expression (e.g. "a lot of")
 P    Preposition
 p    Preposition (already resolved)
 C    Conjunction (coordinating/disjunctive)
 J    Conjunction (subordinating), phrase-boundary separator
 X    Auxiliary verb 'be' (is/are/was/were)
 x    Impersonal verb combination ("there is", etc.)
 Y    Auxiliary verb 'have' (possession / perfect)
 y    Auxiliary verb 'have' (existential/copular sense)
 B    Infinitive particle 'to' (before perfective verb)
 b    Infinitive particle 'to' (before imperfective verb)
 U    Modal verb ("must", "can", "shall")
 u    Modal verb combination ("had better", "ought to")
 K    Negative particle 'not'
 k    Negative particle 'no'
 R    Personal pronoun ("I", "you", "he")
 r    Compound personal pronoun ("myself", "yourself")
 M    Indirect/object pronoun ("him", "her", "them")
 m    Compound indirect pronoun ("himself", "themselves")
 Q    Question word
 L    Relative word ', который' (which/who — resolved)
 l    Movable relative 'whose' — analyzer-generated
 T    Determiner (article); outputs empty string
 t    Determiner — segment boundary — analyzer-generated
 H    Digits and numeric combinations
 I    Cardinal numeral
 W    Multi-word phrase marker
 w    Multi-word/compound modifier flag
 #    Untranslatable unit (proper noun, designation)
 ?    Unknown / unrecognized word (not in dictionary)
│    Fictitious separator (clause boundary in token stream)

SUFFIX NUMBERS (paradigm indices):
  N001-N011  Noun paradigms (singular 1-5, plural 6-11)
  V001-V012  Verb paradigms
  A001-A005  Adjective paradigms

EXAMPLES:
  agreement*N001         → noun, paradigm 1
  supply*V001\N001       → verb OR noun (multiple meanings)
  boxed*A001             → adjective, paradigm 1
  boarded*A001           → adjective (boarded up = обшитый)
]])
end

-------------------------------------------------------------------------------
-- HELP
-------------------------------------------------------------------------------

local HELP_TOPICS = {}

HELP_TOPICS["overview"] = [[
=== Dictionary Tool Overview ===

This tool manages the LTGOLD-format dictionaries used by the en-ru-translator.
Dictionaries are CP866-encoded files with one entry per line:

  word*GRAMMATICAL_TAG TRANSLATION

The '*' separates the word from its grammatical tag + Russian translation.
The tag and translation are stored together with no separator.

MULTIPLE MEANINGS use ';' to separate alternatives:
  word*Nсоглашение;договор

All dictionaries live in the data/ directory.

EXAMPLE ENTRIES:
  agreement*Nсоглашение          (noun: соглашение)
  board*NN.совет{group};доска{wood}  (noun with alternatives)
  boarded*Aобшитый досками       (adjective)

USE CASE — Adding "boarded":
  "boarded" means "обшитый досками" (covered with boards)
  It's an adjective derived from "board"

  lua dict.lua add "boarded" "A" "обшитый досками"
  → stores: boarded*Aобшитый досками
]]

HELP_TOPICS["format"] = [[
=== Dictionary File Format ===

HEADER (first line only):
  LTech DIC File 2.00\x1aERS\x00
  This is required. The tool handles it automatically.

ENTRY FORMAT:
  <word>*<codes>\n

  - <word> is the English or Russian word (CP866 encoded)
  - * is the separator (0x2A)
  - <codes> is the grammatical tag string (CP866 encoded)
  - Entries are case-insensitive for search
  - Entries should be sorted alphabetically

MULTIPLE MEANINGS:
  word*N001\\V001
  (backslash-separated paradigm indices)

MULTI-WORD ENTRIES:
  a lot of*I1
  (spaces allowed in the word part)

CP866 ENCODING:
  Russian characters use the DOS CP866 codepage:
  А=0x80, Б=0x81, ..., а=0xA0, б=0xA1, ..., р=0xE0, ...

  The tool handles encoding/decoding automatically.
  Enter text in UTF-8; it will be converted to CP866 on save.
]]

HELP_TOPICS["add"] = [[
=== Adding Entries ===

SYNOPSIS:
  lua dict.lua add <word> <tags> [translation] [options]

The tool stores entries in LTGOLD format:
  <word>*<tags><translation>

The <tags> field is one or more grammatical codes (e.g. N, V, A001).
The <translation> field is the Russian text, appended directly after the tags.

MULTIPLE MEANINGS use ';' separator:
  word*Nсоглашение;договор

OPTIONS:
  --dict <file>   Target dictionary file (default: BASE.DIC)
  --force         Overwrite existing entry without prompting
  --rus           Add to BASE.RUS (Russian→English dictionary)

EXAMPLES:

  1. Add a noun with translation:
     lua dict.lua add "agreement" "N" "соглашение"

  2. Add a noun with paradigm index:
     lua dict.lua add "agreement" "N001" "соглашение"

  3. Add an adjective:
     lua dict.lua add "boarded" "A" "обшитый досками"

  4. Add a word with multiple meanings:
     lua dict.lua add "present" "V" "представлять" --force
     (or edit manually to add ;подарок)

  5. Add to BUSINESS.DIC:
     lua dict.lua add "invoice" "N" "счёт-фактура" --dict BUSINESS.DIC

  6. Add a multi-word entry:
     lua dict.lua add "a lot of" "I" "много"

  7. Force overwrite existing entry:
     lua dict.lua add "board" "N" "доска" --force

GRAMMATICAL CODE QUICK REFERENCE:
  N=noun, V=verb, A=adjective, D=adverb, E=past tense
  G=gerund, P=preposition, C=conjunction, I=cardinal numeral
  Add paradigm index for inflection: N001, V001, A001, etc.
  See 'lua dict.lua paradigms' for full reference.

WHAT GETS STORED:
  If you run: lua dict.lua add "boarded" "A" "обшитый досками"
  The file gets: boarded*Aобшитый досками
  (tag A + Russian text, no separator between them)
]]

HELP_TOPICS["find"] = [[
=== Searching Dictionaries ===

SYNOPSIS:
  lua dict.lua find <word> [options]

OPTIONS:
  --dict <file>   Search only this dictionary
  --partial       Substring search instead of exact match

EXAMPLES:

  1. Find all entries for "board":
     lua dict.lua find board

  2. Find "board" in BASE.DIC only:
     lua dict.lua find board --dict BASE.DIC

  3. Find all words containing "board":
     lua dict.lua find board --partial

  4. Find Russian word:
     lua dict.lua find доска
]]

HELP_TOPICS["list"] = [[
=== Listing Dictionary Entries ===

SYNOPSIS:
  lua dict.lua list [dict] [options]

OPTIONS:
  --limit N   Show at most N entries (default: all)

EXAMPLES:

  1. List all entries in all dictionaries:
     lua dict.lua list

  2. List entries in BASE.DIC only:
     lua dict.lua list BASE.DIC

  3. List first 20 entries:
     lua dict.lua list --limit 20
]]

HELP_TOPICS["tips"] = [[
=== Tips and Best Practices ===

ADDING VERBS:
  Verbs need paradigm indices for conjugation:
    lua dict.lua add "board" "V" "обшивать"
  Common verb tags: V (main verb), v (3sg present), E (past)

ADDING NOUNS:
  Nouns need paradigm indices for declension:
    lua dict.lua add "agreement" "N" "соглашение"
  Common noun tags: N (singular), n (plural)

ADDING ADJECTIVES:
  Adjectives need paradigm indices for agreement:
    lua dict.lua add "boarded" "A" "обшитый досками"
  Common adjective tags: A (adjective), a (adverb-like)

MULTIPLE MEANINGS:
  Use ';' to separate alternatives in the translation:
    lua dict.lua add "present" "V" "представлять" --force
    Then edit the file to add: ;подарок

WHAT GETS STORED:
  The tag and translation are concatenated directly:
    lua dict.lua add "boarded" "A" "обшитый досками"
    → file gets: boarded*Aобшитый досками

COMMON TAGS:
  N=noun, V=verb, A=adjective, D=adverb, E=past tense
  G=gerund, P=preposition, C=conjunction, I=cardinal numeral
  X=auxiliary be, Y=auxiliary have, U=modal verb

WORKFLOW:
  1. Search first: lua dict.lua find <word>
  2. If not found, add: lua dict.lua add <word> <tag> <translation>
  3. Run translator: lua init.lua
  4. Check output matches expected translation
]]

local function cmd_help(topic)
  if topic and HELP_TOPICS[topic] then
    print(HELP_TOPICS[topic])
  elseif topic then
    print(string.format("  Unknown help topic: '%s'", topic))
    print("  Available topics: overview, format, add, find, list, tips, paradigms")
  else
    print([[
=== dict.lua — Dictionary Management Tool ===

Manage LTGOLD-format dictionaries for the en-ru-translator.

COMMANDS:
  lua dict.lua find <word>              Exact search across all dictionaries
  lua dict.lua find <word> --partial    Substring search
  lua dict.lua find <word> --dict FILE  Search specific dictionary
  lua dict.lua add W CODES RU           Add English→Russian entry
  lua dict.lua add W CODES RU --rus     Add Russian→English entry
  lua dict.lua add W CODES RU --dict F  Add to specific dictionary
  lua dict.lua add W CODES RU --force   Overwrite if exists
  lua dict.lua list [DICT]              List dictionary entries
  lua dict.lua list --limit N           Limit output
  lua dict.lua paradigms                Show grammatical code reference
  lua dict.lua help                     Show this help
  lua dict.lua help <topic>             Detailed help on topic

HELP TOPICS:
  overview   General overview of the dictionary system
  format     File format and encoding details
  add        How to add new entries
  find       How to search for entries
  list       How to list dictionary contents
  tips       Best practices and common patterns

EXAMPLES:
  lua dict.lua find agreement
  lua dict.lua add "boarded" "A001" "обшитый досками"
  lua dict.lua add "invoice" "N001" "счёт-фактура" --dict BUSINESS.DIC
  lua dict.lua list BASE.DIC --limit 10
  lua dict.lua paradigms
]])
  end
end

-------------------------------------------------------------------------------
-- CLI argument parsing
-------------------------------------------------------------------------------

local function parse_args(args)
  local result = { command = nil, word = nil, codes = nil, russian = nil }
  local options = {}
  local i = 1

  while i <= #args do
    local arg = args[i]
    if arg == "--dict" then
      i = i + 1
      options.dict = args[i]
    elseif arg == "--rus" then
      options.rus = true
      if not options.dict then options.dict = "BASE.RUS" end
    elseif arg == "--force" then
      options.force = true
    elseif arg == "--partial" then
      options.partial = true
    elseif arg == "--limit" then
      i = i + 1
      options.limit = tonumber(args[i]) or 100
    else
      -- positional arguments
      if not result.command then
        result.command = arg
      elseif not result.word then
        result.word = arg
      elseif not result.codes then
        result.codes = arg
      elseif not result.russian then
        result.russian = arg
      end
    end
    i = i + 1
  end

  return result, options
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

local args = {...}
local parsed, options = parse_args(args)

if not parsed.command then
  cmd_help()
  os.exit(0)
end

local command = parsed.command:lower()

if command == "help" then
  cmd_help(parsed.word)  -- word slot used for topic

elseif command == "find" then
  if not parsed.word then
    print("  Usage: lua dict.lua find <word> [--partial] [--dict FILE]")
    os.exit(1)
  end
  if options.partial then
    cmd_find_partial(parsed.word, options.dict)
  else
    cmd_find(parsed.word, options.dict)
  end

elseif command == "add" then
  if not parsed.word or not parsed.codes then
    print("  Usage: lua dict.lua add <word> <codes> [russian] [--dict FILE] [--force]")
    print("  Use 'lua dict.lua paradigms' for available codes")
    os.exit(1)
  end
  cmd_add(parsed.word, parsed.codes, parsed.russian, options)

elseif command == "list" then
  cmd_list(parsed.word, options)  -- word slot used for dict filter

elseif command == "paradigms" then
  cmd_paradigms()

else
  print(string.format("  Unknown command: '%s'", command))
  print("  Run 'lua dict.lua help' for usage")
  os.exit(1)
end
