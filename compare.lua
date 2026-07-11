-- Compare Lua engine vs LTGOLD reference
local utils = require "utils"
local load = require "load"
local parser = require "parser"
local compiler = require "compiler"

local verify_dosbox = false
for _, value in ipairs(arg or {}) do
  if value == "--dosbox" then verify_dosbox = true end
end

local file = assert(io.open("data/BASE.DIC", "r"))
local file2 = assert(io.open("data/BASE.RUS", "r"))
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

-- These outputs were captured sentence-by-sentence from the unmodified LTPRO.EXE.
-- Keep LTGOLD's awkward morphology and dropped words: they are compatibility targets.
local gold = {
  { "This AGREEMENT is a sample for testing the electronic translation program.",
    "Это СОГЛАШЕНИЕ - образец{1.выборка} для испытания программы электронного перевода." },
  { "AGREEMENT ON SUPPLY OF FISH MEAL",
    "ДОГОВОР О ПОСТАВКЕ РЫБНОЙ МУКИ" },
  { "Both BUYER and SELLER agree to comply with all terms and conditions defined in this AGREEMENT.",
    "Как ПОКУПАТЕЛЬ так и ПРОДАВЕЦ соглашаются соответствовать всем срокам и условиям определенным в этом СОГЛАШЕНИИ." },
  { "The PARTIES to this AGREEMENT acknowledge they are legally authorized to represent their organizations.",
    "СТОРОНЫ{1.партия;вечеринка} в этом СОГЛАШЕНИИ признают, что они юридически уполномочены представлять их организации." },
  { "SELLER shall supply to BUYER 1,000,000 Metric tons of Fish Meal.",
    "ПРОДАВЕЦ поставит ПОКУПАТЕЛЮ 1,000,000 Метрических тонн Рыбной Муки." },
  { "The total price for the goods and services as defined in EXHIBIT A is USD.",
    "Общая цена для товаров и услуг как определено в ПРИЛОЖЕНИИ{1.экспонат} - ДОЛЛАР США." },
  { "The exclusive remedy for breach of this warranty shall be the replacement.",
    "Единственная Компенсация За Нарушение этой гарантии будет заменой." },
  { "This AGREEMENT supersedes all preceding negotiations and correspondence, making them null and void.",
    "Это СОГЛАШЕНИЕ заменяет все предыдущие переговоры и корреспонденцию, заставляя их утративший законную силу." },
  { "Packing is to ensure full safety of PRODUCTS during transportation by all means of transport including transshipments.",
    "Упаковка должна гарантировать полную безопасность ПРОДУКТОВ в течение транспортировки всеми видами транспорта включая перегрузки." },
  { "The Letter of Credit shall allow for partial shipments and partial payment.",
    "Аккредитив Позволит частичным грузам{1.поставка} и частичному платежу." },
  -- Focused LTPRO probes captured directly through LTGOLD/run_test.sh.
  { "EXHIBIT A.", "ПОКАЖИТЕ A." },
  { "by all means.", "во что бы то ни стало." },
  { "by all means of transport.", "всеми видами транспорта." },
  { "He walked including me.", "Он прошел включая меня." },
  { "5 Metric tons.", "5 Метрических тонн." },
  { "2 Metric tons.", "2 Метрические тонны." },
  { "It will be a replacement.", "Это Будет заменой." },
  { "fish-meal.", "рыбная мука." },
  { "well-known product.", "известный продукт." },
  { "buyer-seller agreement.", "соглашение продавца покупателя." },
  { "A-B.", "-B." },
  { "state-of-the-art product.", "современный продукт." },
  { "He said, I agree.", "Он сказал, Я соглашаюсь{1.согласовывать}." },
  { "He said, \"I agree.\"", "Он сказал, \"Я соглашаюсь{1.согласовывать}.\"" },
  { "\"Fish meal\", seller said.", "\"Рыбная Мука\", продавец сказал." },
}

local fail, total = 0, 0
for _, case in ipairs(gold) do
  local sent, expected = table.unpack(case)
  total = total + 1
  if verify_dosbox then
    local pipe = assert(io.popen(string.format("./LTGOLD/run_test.sh %q", sent), "r"))  -- NOTE: LTGOLD/run_test.sh kept as-is, not a data file
    local captured = pipe:read("*all"):gsub("\r", "")
    local ok = pipe:close()
    local translation = captured:match("^(.-)\n%s*\n") or captured
    translation = translation:match("^%s*(.-)%s*$") or translation
    if not ok or translation ~= expected then
      fail = fail + 1
      print(string.format("  ✗ DOSBOX:  %s", translation))
      print(string.format("    STORED:  %s", expected))
      print()
    end
  end
  local ts = utils.tokenize(sent, en_ru)
  parser.collect(en_ru, ts)
  local out = compiler.compile(ts) or ""
  out = out:match("^%s*(.-)%s*$") or out

  local ok = out == expected and "✓" or "✗"
  if ok == "✗" then fail = fail + 1 end
  print(string.format("  %s LUA:     %s", ok, out))
  print(string.format("    LTGOLD:  %s", expected))
  print()
end

print(string.format("Passed %d/%d", total - fail, total))
if fail > 0 then os.exit(1) end
