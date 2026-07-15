local dictionary_store = require "dictionary_store"
local translator = require "core.translator"

-- Verify the public core API without invoking the CLI shell or capturing stdout.
local english, russian = dictionary_store.load()
local engine = translator.new(english, russian)
local output = assert(engine:translate("This AGREEMENT is a sample for testing the electronic translation program."))
assert(output == "Это СОГЛАШЕНИЕ - образец{1.выборка} для испытания программы электронного перевода.", output)
-- Regression: E-passive guard must use perfective "посидeла" (not imperfective "сидела").
-- The "mat" preposition case follows LTGOLD dictionary selection.
local cat_output = assert(engine:translate("The cat sat on the mat."))
assert(cat_output == "Кошка посидeла на ковре.", cat_output)
-- T5/T6 match the filtered head of packed W entries and move the complete
-- dictionary entry, producing the LTPRO noun/preposition ordering.
local supply_output = assert(engine:translate("AGREEMENT ON SUPPLY OF FISH MEAL"))
assert(supply_output == "ДОГОВОР О ПОСТАВКЕ РЫБНОЙ МУКИ", supply_output)
-- Reordering keeps each packed phrase component's capitalization metadata;
-- only the sentence-initial component is capitalized after W expansion.
local remedy_output = assert(engine:translate(
  "The exclusive remedy for breach of this warranty shall be the replacement."))
assert(remedy_output == "Единственная компенсация за нарушение этой гарантии будет заменой.", remedy_output)
print("translator tests passed")
