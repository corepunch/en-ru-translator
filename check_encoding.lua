#!/usr/bin/env lua
-- check_encoding.lua — Scan for Latin 'e' inside Russian words
--
-- The specific bug this catches: Latin 'e' (0x65) appearing between Cyrillic
-- characters, producing e.g. "сидeла" instead of "сидела".
--
-- Scans:
--   - core/paradigms.lua (verb/noun/adjective suffix strings)
--   - data/*.DIC (Russian text in dictionary entries)
--   - data/*.RUS (Russian word fields)
--
-- Usage:
--   lua check_encoding.lua              # scan all sources
--   lua check_encoding.lua paradigms    # scan paradigms only
--   lua check_encoding.lua dic          # scan DIC files only
--   lua check_encoding.lua rus          # scan RUS files only

local encoding = require "core.encoding"
local DATA_DIR = "data/"

local function is_cp866_cyrillic(b)
  return (b >= 0x80 and b <= 0x9F) or (b >= 0xA0 and b <= 0xAF) or
         (b >= 0xE0 and b <= 0xEF) or b == 0xF0
end

-- Check if a Latin byte is surrounded by Cyrillic (the encoding error pattern)
local function has_latin_in_cyrillic(s, start_pos)
  local issues = {}
  local i = start_pos or 1
  while i <= #s do
    local b = s:byte(i)
    if is_cp866_cyrillic(b) then
      -- Look ahead for Latin letters that are NOT tag prefixes
      -- A real error has Cyrillic on at least one side of the Latin letter
      local j = i + 1
      while j <= #s do
        local nb = s:byte(j)
        if nb >= 0x41 and nb <= 0x7A then
          -- Latin letter found — check if it's inside a Russian word
          -- (Cyrillic before it AND Cyrillic after it, or just Cyrillic before)
          local after_latin = j + 1
          if after_latin <= #s and is_cp866_cyrillic(s:byte(after_latin)) then
            -- Latin letter sandwiched between Cyrillic — this is the bug
            local ctx_start = math.max(1, i - 2)
            local ctx_end = math.min(#s, j + 3)
            local context = s:sub(ctx_start, ctx_end)
            issues[#issues + 1] = {pos = j, char = string.char(nb), context = context}
          end
          break  -- only check the first Latin letter after each Cyrillic run
        elseif is_cp866_cyrillic(nb) then
          break  -- hit more Cyrillic, stop
        else
          break  -- hit non-Cyrillic non-Latin, stop
        end
        j = j + 1
      end
    end
    i = i + 1
  end
  return issues
end

-------------------------------------------------------------------------------
-- Scan paradigms.lua
-------------------------------------------------------------------------------

local function scan_paradigms()
  print("=== Scanning core/paradigms.lua ===")
  local f = io.open("core/paradigms.lua", "r")
  if not f then print("  ERROR: cannot open"); return 0 end

  local issues = 0
  local line_num = 0
  for line in f:lines() do
    line_num = line_num + 1
    for pos in line:gmatch('"[^"]*"') do
      local found = has_latin_in_cyrillic(pos)
      for _, issue in ipairs(found) do
        print(string.format("  line %d: Latin '%s' in suffix: ...%s...", line_num, issue.char, issue.context))
        issues = issues + 1
      end
    end
  end
  f:close()
  print(string.format("  Found %d issue(s)\n", issues))
  return issues
end

-------------------------------------------------------------------------------
-- Scan DIC files — check Russian portions only
-------------------------------------------------------------------------------

local function scan_dic_files()
  print("=== Scanning DIC files (Russian text) ===")
  local dic_files = {"BASE.DIC", "BUSINESS.DIC", "COMPUTER.DIC"}
  local total = 0

  for _, filename in ipairs(dic_files) do
    local f = io.open(DATA_DIR .. filename, "rb")
    if f then
      local issues = 0
      local line_num = 0
      for line in f:lines() do
        line_num = line_num + 1
        local word, codes = line:match("^(.-)\x2a(.*)$")
        if codes then
          -- Extract Russian portions: skip tag letters at start, then find
          -- Cyrillic runs separated by tag letters/spaces/punctuation
          local russian_parts = {}
          local i = 1
          while i <= #codes do
            local b = codes:byte(i)
            if is_cp866_cyrillic(b) then
              -- Start of a Cyrillic run
              local run_start = i
              while i <= #codes and (is_cp866_cyrillic(codes:byte(i)) or codes:byte(i) == 0x20) do
                i = i + 1
              end
              russian_parts[#russian_parts + 1] = codes:sub(run_start, i - 1)
            else
              i = i + 1
            end
          end
          -- Check each Russian portion for Latin-in-Cyrillic
          for _, part in ipairs(russian_parts) do
            local found = has_latin_in_cyrillic(part)
            for _, issue in ipairs(found) do
              local decoded = encoding.decode(part:sub(math.max(1, issue.pos - 5), math.min(#part, issue.pos + 5)))
              print(string.format("  %s:%d: Latin '%s': %s", filename, line_num, issue.char, decoded))
              issues = issues + 1
            end
          end
        end
      end
      f:close()
      print(string.format("  %s: %d issue(s)", filename, issues))
      total = total + issues
    end
  end
  print(string.format("  Total: %d\n", total))
  return total
end

-------------------------------------------------------------------------------
-- Scan RUS files
-------------------------------------------------------------------------------

local function scan_rus_files()
  print("=== Scanning RUS files ===")
  local rus_files = {"BASE.RUS", "DUNGEON.RUS"}
  local total = 0

  for _, filename in ipairs(rus_files) do
    local f = io.open(DATA_DIR .. filename, "rb")
    if f then
      local issues = 0
      local line_num = 0
      for line in f:lines() do
        line_num = line_num + 1
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
          local word = trimmed:match("^(.-)\x2a")
          if word then
            local found = has_latin_in_cyrillic(word)
            for _, issue in ipairs(found) do
              print(string.format("  %s:%d: Latin '%s' in word: %s", filename, line_num, issue.char, encoding.decode(word)))
              issues = issues + 1
            end
          end
        end
      end
      f:close()
      print(string.format("  %s: %d issue(s)", filename, issues))
      total = total + issues
    end
  end
  print(string.format("  Total: %d\n", total))
  return total
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

local args = {...}
local scan_type = args[1] or "all"
local total = 0

if scan_type == "paradigms" or scan_type == "all" then total = total + scan_paradigms() end
if scan_type == "dic" or scan_type == "all" then total = total + scan_dic_files() end
if scan_type == "rus" or scan_type == "all" then total = total + scan_rus_files() end

print("=" .. string.rep("=", 49))
if total == 0 then
  print("No Latin-in-Cyrillic encoding issues found.")
else
  print(string.format("Total issues: %d", total))
  print("Latin letters appearing between Cyrillic characters (e.g. сидeла → сидела)")
end
