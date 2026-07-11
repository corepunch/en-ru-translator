local encoding = require "core.encoding"
local load = require "core.load"

local dictionary_store = {}

-- Load both LTGOLD files behind one explicit I/O boundary; the translation
-- core receives the resulting tables and never opens dictionary files itself.
function dictionary_store.load(dictionary_path, russian_path)
  local english, russian = {}, {}
  local dictionary = assert(io.open(dictionary_path or "data/BASE.DIC", "r"))
  for line in dictionary:lines() do
    load.lingua(english, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
  end
  dictionary:close()

  local forms = assert(io.open(russian_path or "data/BASE.RUS", "r"))
  for line in forms:lines() do
    local word, code = line:match("^(.-)\x2a(.*)$")
    if code then russian[encoding.decode(word)] = code end
  end
  forms:close()
  return english, russian
end

return dictionary_store
