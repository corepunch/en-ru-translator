local compiler = require "core.compiler"
local parser = require "core.parser"
local utils = require "core.utils"

local translator = {}

-- Construct an in-process translator from injected data so tests can exercise
-- the complete core without depending on command-line state or file loading.
function translator.new(english_dictionary, russian_forms)
  assert(type(english_dictionary) == "table", "English dictionary is required")
  assert(type(russian_forms) == "table", "Russian forms are required")
  return {
    translate = function(_, text)
      local tokens = utils.tokenize(text, english_dictionary)
      local parsed, err = parser.collect(english_dictionary, tokens)
      if not parsed then return nil, err end
      compiler.base = russian_forms
      return compiler.compile(parsed, { quiet = true })
    end,
  }
end

return translator
