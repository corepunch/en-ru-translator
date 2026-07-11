local utils = require "core.utils"
local load = require "core.load"
local parser = require "core.parser"
local compiler = require "core.compiler"

-- share globals with parser
_G.LTGOLD_BASE = {}

local file = assert(io.open("data/BASE.DIC", "r"))
local file2 = assert(io.open("data/BASE.RUS", "r"))
local en_ru = {}
compiler.base = {}
for line in file:lines() do
  load.lingua(en_ru, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do
  local word, code = line:match("^(.-)\x2a(.*)$")
  if code then compiler.base[utils.decode(word)] = code end
end
file:close(); file2:close()

local sentences = {
  "This AGREEMENT is a sample for testing the electronic translation program.",
  "AGREEMENT ON SUPPLY OF FISH MEAL",
  "Both BUYER and SELLER agree to comply with all terms and conditions defined in this AGREEMENT.",
  "The PARTIES to this AGREEMENT acknowledge they are legally authorized to represent their organizations.",
  "SELLER shall supply to BUYER 1,000,000 Metric tons of Fish Meal.",
  "If the SELLER is unable to meet its obligations under this AGREEMENT, SELLER shall release all remaining portion of the Letter of Credit back to the BUYER.",
  "Packing is to ensure full safety of PRODUCTS during transportation by all means of transport including transshipments.",
  "All disputes and differences which may arise out of or in conjunction with this AGREEMENT shall be settled as far as possible by means of negotiations between the PARTIES.",
  "The exclusive remedy for breach of this warranty shall be the replacement.",
  "The Letter of Credit shall allow for partial shipments and partial payment.",
}

print("=== DEMO.TXT — Key Sentences ===\n")

for i, sent in ipairs(sentences) do
  local ts = utils.tokenize(sent, en_ru)
  parser.collect(en_ru, ts)
  local out = compiler.compile(ts) or "(empty)"
  print(string.format("%d. %s", i, sent))
  print(string.format("   %s", out:gsub("^%s*(.-)%s*$", "%1")))
  print()
end
