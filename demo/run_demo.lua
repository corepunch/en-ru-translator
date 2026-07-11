-- Run key sentences from DEMO.TXT through our translator
local utils = require "core.utils"
local load = require "core.load"
local parser = require "core.parser"
local compiler = require "core.compiler"

-- load dictionaries
local file = assert(io.open("data/BASE.DIC", "r"))
local file2 = assert(io.open("data/BASE.RUS", "r"))
local en_ru, base = {}, {}
compiler.base = base
for line in file:lines() do
  load.lingua(en_ru, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do
  local word, code = line:match("^(.-)\x2a(.*)$")
  if code then base[utils.decode(word)] = code end
end
file:close(); file2:close()

local sentences = {
  "This AGREEMENT is a sample for testing the electronic translation program.",
  "AGREEMENT ON SUPPLY OF FISH MEAL",
  "Both BUYER and SELLER agree to comply with all terms and conditions defined in this AGREEMENT.",
  "The PARTIES to this AGREEMENT acknowledge they are legally authorized to represent their organizations.",
  "SELLER shall supply to BUYER 1,000,000 Metric tons of Fish Meal.",
  "The total price for the goods and services as defined in EXHIBIT A is USD.",
  "The delivery of the PRODUCTS shall be upon presentation of all documents as defined in EXHIBIT A.",
  "The Letter of Credit shall allow for partial shipments and partial payment.",
  "If the SELLER is unable to meet its obligations under this AGREEMENT, SELLER shall release all remaining portion of the Letter of Credit back to the BUYER.",
  "The exclusive remedy for breach of this warranty shall be the replacement.",
  "Packing is to ensure full safety of PRODUCTS during transportation by all means of transport including transshipments.",
  "The PARTIES shall be free from the partial or full obligations under this AGREEMENT which results from any cause or circumstance beyond the control of either party.",
  "All disputes and differences which may arise out of or in conjunction with this AGREEMENT shall be settled as far as possible by means of negotiations between the PARTIES.",
  "This AGREEMENT supersedes all preceding negotiations and correspondence, making them null and void.",
  "BUYER shall be responsible for the scheduling receipt of goods in the port of destination.",
}

print("=== Translating DEMO.TXT key sentences ===\n")

for i, sent in ipairs(sentences) do
  local ts = utils.tokenize(sent, en_ru)
  parser.collect(en_ru, ts)
  local out = compiler.compile(ts) or ""
  print(string.format("%2d. INPUT:  %s", i, sent))
  print(string.format("    OUTPUT: %s", out))
  print()
end
