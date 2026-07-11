local dictionary_store = require "dictionary_store"
local translator = require "translator"

-- Verify the public core API without invoking the CLI shell or capturing stdout.
local english, russian = dictionary_store.load()
local engine = translator.new(english, russian)
local output = assert(engine:translate("This AGREEMENT is a sample for testing the electronic translation program."))
assert(output == "Это СОГЛАШЕНИЕ - образец{1.выборка} для испытания программы электронного перевода.", output)
print("translator tests passed")
