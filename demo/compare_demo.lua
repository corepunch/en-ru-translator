-- Compare Lua engine output with LTGOLD reference for DEMO.TXT
local utils = require "core.utils"
local load = require "core.load"
local parser = require "core.parser"
local compiler = require "core.compiler"

local file = assert(io.open("data/BASE.DIC", "r"))
local file2 = assert(io.open("data/BASE.RUS", "r"))
local en_ru, base = {}, {}
compiler.base = base
for line in file:lines() do
  load.lingua(en_ru, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do
  local w, code = line:match("^(.-)\x2a(.*)$")
  if code then base[utils.decode(w)] = code end
end
file:close(); file2:close()

-- Read reference (skip header)
local ref = assert(io.open("test/DEMO_REFERENCE.TXT", "r")):read("*all")
io.open("test/DEMO_REFERENCE.TXT"):close()
-- skip LTGOLD header lines
local ref_start = ref:find("СОГЛАШЕНИЕ") or 1
ref = ref:sub(ref_start)

-- Individual key sentences from DEMO.TXT to compare
local tests = {
  "This AGREEMENT is a sample for testing the electronic translation program.",
  "AGREEMENT ON SUPPLY OF FISH MEAL",
  "Both BUYER and SELLER agree to comply with all terms and conditions defined in this AGREEMENT.",
  "SELLER shall supply to BUYER 1,000,000 Metric tons of Fish Meal.",
  "The total price for the goods and services as defined in EXHIBIT A is USD.",
  "If the SELLER is unable to meet its obligations under this AGREEMENT, SELLER shall release all remaining portion of the Letter of Credit back to the BUYER.",
  "The exclusive remedy for breach of this warranty shall be the replacement.",
  "This AGREEMENT supersedes all preceding negotiations and correspondence, making them null and void.",
}

-- Find LTGOLD's translation for a specific sentence by keyword matching
local function find_ref(sentence)
  -- Extract key words
  local key = sentence:match("^%a+") or ""
  if key == "This" then key = sentence:match("This (%a+)") or "AGREEMENT" end
  if key == "Both" then return "" end  -- too complex for simple matching
  if key == "If" then return "" end
  -- search reference for key word
  local pattern = key:upper()
  local start = ref:find(pattern, 1, true)
  if not then return "(not found in reference)"
  -- Extract the line
  local line_end = ref:find("\n", start)
  if not line_end then return ref:sub(start) end
  return ref:sub(start, line_end - 1)
end

print("=== Comparison: Lua vs LTGOLD ===\n")

for i, sent in ipairs(tests) do
  local ts = utils.tokenize(sent, en_ru)
  parser.collect(en_ru, ts)
  local out = compiler.compile(ts) or ""
  out = out:match("^%s*(.-)%s*$") or out
  
  local ref_text = find_ref(sent)
  local match = ref_text ~= "" and out:find(ref_text:sub(1, 10), 1, true) and "✓" or "✗"
  
  print(string.format("%d. INPUT: %s", i, sent))
  print(string.format("   %s LUA:     %s", match, out))
  if ref_text ~= "" then
    print(string.format("   LTGOLD: %s", ref_text))
  end
  print()
end
