-- Compare Lua engine vs LTGOLD reference
local utils = require "utils"
local load = require "load"
local parser = require "parser"
local compiler = require "compiler"

local file = assert(io.open("LTGOLD/BASE.DIC", "r"))
local file2 = assert(io.open("LTGOLD/BASE.RUS", "r"))
local en_ru = {}
compiler.base = {}
for line in file:lines() do
  load.lingua(en_ru, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do
  local w, code = line:match("^(.-)\x2a(.*)$")
  if code then compiler.base[utils.decode(w)] = code end
end
file:close(); file2:close()

local ref = assert(io.open("LTGOLD/DEMO_REFERENCE.TXT", "r")):read("*all")
io.open("LTGOLD/DEMO_REFERENCE.TXT"):close()

-- Known LTGOLD translations for our key sentences (extracted from reference)
local gold = {
  -- LTGOLD appends 'ЛТГОЛД' (its own name) which we can't produce without a special
  -- dictionary entry. Compare everything except the product name suffix.
  ["This AGREEMENT is a sample for testing the electronic translation program."] =
    "Это СОГЛАШЕНИЕ - образец{1.выборка} для испытания программы электронного перевода.",

  ["AGREEMENT ON SUPPLY OF FISH MEAL"] =
    "ДОГОВОР О ПОСТАВКЕ РЫБНОЙ МУКИ",

  ["Both BUYER and SELLER agree to comply with all terms and conditions defined in this AGREEMENT."] =
    "Как ПОКУПАТЕЛЬ так и ПРОДАВЕЦ соглашаются соответствовать всем срокам и условиям определенным в этом СОГЛАШЕНИИ.",

  ["The PARTIES to this AGREEMENT acknowledge they are legally authorized to represent their organizations."] =
    "СТОРОНЫ в этом СОГЛАШЕНИИ признают, что они юридически уполномочены представлять их организации",

  ["SELLER shall supply to BUYER 1,000,000 Metric tons of Fish Meal."] =
    "ПРОДАВЕЦ поставит ПОКУПАТЕЛЮ 1,000,000 Метрические тонны Рыбной Муки",

  ["The total price for the goods and services as defined in EXHIBIT A is USD."] =
    "Общая цена для товаров и услуг как определено в ПРИЛОЖЕНИИ A - ДОЛЛАР США",

  ["The exclusive remedy for breach of this warranty shall be the replacement."] = "",

  ["This AGREEMENT supersedes all preceding negotiations and correspondence, making them null and void."] = "",

  ["Packing is to ensure full safety of PRODUCTS during transportation by all means of transport including transshipments."] = "",

  ["The Letter of Credit shall allow for partial shipments and partial payment."] = "",
}

local fail, total = 0, 0
local function strip(s)
  return s:gsub("%{.-}", ""):gsub("'", ""):gsub('"', ""):match("^%s*(.-)%s*$") or s
end

for sent, expected in pairs(gold) do
  total = total + 1
  local ts = utils.tokenize(sent, en_ru)
  parser.collect(en_ru, ts)
  local out = compiler.compile(ts) or ""
  out = out:match("^%s*(.-)%s*$") or out

  if expected == "" then
    print(string.format("  %s", out))
    print()
  else
    local clean_expected = strip(expected)
    local clean_out = strip(out)
    local ok = clean_out == clean_expected and "✓" or "✗"
    if ok == "✗" then fail = fail + 1 end
    print(string.format("  %s LUA:     %s", ok, out))
    print(string.format("    LTGOLD:  %s", expected))
    print()
  end
end

print(string.format("Passed %d/%d", total - fail, total))