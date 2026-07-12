-- Test T7/T8 constituent flag propagation
local parser = require "core.parser"
local dictionary_store = require "dictionary_store"
local utils = require "core.utils"
local english, russian = dictionary_store.load()
local ts = utils.tokenize("Seller shall deliver to Buyer 1,000,000 metric tons of fish meal.", english)
local result = parser.collect(english, ts)
if result.constituent_flags then
  local count = 0
  for i, v in pairs(result.constituent_flags) do
    print(string.format("token %d [%s] = 0x%02X", i, result[i]:sub(1,1), v))
    count = count + 1
  end
  if count == 0 then print("constituent_flags: empty") end
else
  print("constituent_flags: nil")
end
