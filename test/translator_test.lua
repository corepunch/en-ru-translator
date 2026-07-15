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
print("translator tests passed")
