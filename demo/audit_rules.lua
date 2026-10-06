-- Audit extraction only: identical records do not prove identical execution.
local utils = require "core.utils"
local rules = require "core.rules"
local suffixes = require "core.suffixes"
local binary = require "demo.ltpro_binary"
local path = arg[1] or "LTGOLD/LTPRO.EXE"
local reader = binary.read(path)
local failures, total, matched = 0, 0, 0

local function same_text(a, b)
  return a.pattern == b.pattern and (a.action or "") == (b.action or "")
end

local function compare(layout, expected, actual)
  -- Align by pattern/action so one custom insertion cannot produce hundreds of false diffs.
  local lengths = {}
  for i = #expected + 1, 1, -1 do
    lengths[i] = {}
    for j = #actual + 1, 1, -1 do
      if i > #expected or j > #actual then lengths[i][j] = 0
      elseif same_text(expected[i], actual[j]) then lengths[i][j] = 1 + lengths[i + 1][j + 1]
      else lengths[i][j] = math.max(lengths[i + 1][j], lengths[i][j + 1]) end
    end
  end
  local i, j, exact, extra, missing, metadata = 1, 1, 0, 0, 0, 0
  while i <= #expected or j <= #actual do
    local a, b = expected[i], actual[j]
    if a and b and same_text(a, b) then
      if a.flag ~= b.flag or a.endpoint_order ~= b.endpoint_order then
        metadata = metadata + 1
        print(string.format("  %s[%d] @0x%X metadata: EXE handler=%d endpoint=%s; Lua handler=%d endpoint=%s",
          layout.name, i - 1, a.address, a.flag, tostring(a.endpoint_order), b.flag, tostring(b.endpoint_order)))
      else exact = exact + 1 end
      i, j = i + 1, j + 1
    elseif b and (not a or lengths[i][j + 1] >= lengths[i + 1][j]) then
      extra = extra + 1
      print(string.format("  EXTRA Lua[%d] %q -> %q", j, b.pattern, b.action or ""))
      j = j + 1
    else
      missing = missing + 1
      print(string.format("  MISSING %s[%d] @0x%X %q handler=%d endpoint=%s",
        layout.name, i - 1, a.address, a.pattern, a.flag, tostring(a.endpoint_order)))
      i = i + 1
    end
  end
  print(string.format("%s: EXE=%d Lua=%d exact=%d extra=%d missing=%d metadata=%d",
    layout.name, #expected, #actual, exact, extra, missing, metadata))
  failures = failures + extra + missing + metadata
  matched = matched + exact
end

for _, layout in ipairs(binary.layouts) do
  local expected, actual = reader.records(layout), {}
  total = total + #expected
  for _, record in ipairs(expected) do
    record.pattern = utils.decode(record.pattern, false)
    record.action = record.action and utils.decode(record.action, false)
  end
  for _, record in ipairs(rules[layout.lua_index or layout.lua_key] or {}) do
    actual[#actual + 1] = {
      flag = record[1], pattern = record[2], action = record[3],
      endpoint_order = record.endpoint_order,
    }
  end
  compare(layout, expected, actual)
end

local expected_suffixes = reader.records(binary.suffix_layout)
local suffix_differences = math.abs(#expected_suffixes - #suffixes)
for i = 1, math.min(#expected_suffixes, #suffixes) do
  local a, b = expected_suffixes[i], suffixes[i]
  if a.flag ~= b.flag or a.suffix ~= b.suffix or a.tag ~= b.tag then
    suffix_differences = suffix_differences + 1
    print("  suffix record differs: " .. i)
  end
end
failures = failures + suffix_differences
print(string.format("Suffixes: EXE=%d Lua=%d differences=%d", #expected_suffixes, #suffixes, suffix_differences))
print(string.format("Extraction: %d/%d exact rule records; %d difference(s). Runtime equivalence is NOT checked.",
  matched, total, failures))
os.exit(failures == 0 and 0 or 1)
