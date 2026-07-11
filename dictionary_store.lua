local encoding = require "core.encoding"
local load = require "core.load"

local dictionary_store = {}

-- normalize: re-encode any UTF-8 Cyrillic in a DIC line to CP866 so that
-- overlay files written in UTF-8 behave identically to the base CP866 files.
local function normalize_line(line)
  return (line:gsub("[\xC0-\xDF][\x80-\xBF]", function(seq)
    local b1, b2 = seq:byte(1), seq:byte(2)
    -- UTF-8 two-byte sequence → code point
    local cp = (b1 - 0xC0) * 64 + (b2 - 0x80)
    -- Cyrillic А–Я (U+0410–U+042F) → CP866 0x80–0x9F
    if cp >= 0x0410 and cp <= 0x042F then return string.char(cp - 0x0410 + 0x80) end
    -- Cyrillic а–п (U+0430–U+043F) → CP866 0xA0–0xAF
    if cp >= 0x0430 and cp <= 0x043F then return string.char(cp - 0x0430 + 0xA0) end
    -- Cyrillic р–я (U+0440–U+044F) → CP866 0xE0–0xEF
    if cp >= 0x0440 and cp <= 0x044F then return string.char(cp - 0x0440 + 0xE0) end
    -- ё (U+0451) → CP866 0xF1; Ё (U+0401) → CP866 0xF0
    if cp == 0x0451 then return "\xF1" end
    if cp == 0x0401 then return "\xF0" end
    return seq  -- pass through anything else unchanged
  end))
end

local function load_dic_file(path, english)
  local f = assert(io.open(path, "r"))
  for line in f:lines() do
    -- Skip comment lines (# prefix) and blank lines
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      local normalized = normalize_line(trimmed)
      load.lingua(english, normalized:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
    end
  end
  f:close()
end

-- Load both LTGOLD files behind one explicit I/O boundary; the translation
-- core receives the resulting tables and never opens dictionary files itself.
-- Extra .DIC overlay files can be passed as additional arguments; they are
-- loaded after BASE.DIC so their entries override the base dictionary.
function dictionary_store.load(dictionary_path, russian_path, ...)
  local english, russian = {}, {}

  load_dic_file(dictionary_path or "data/BASE.DIC", english)

  -- Load overlay dictionaries in order; later files override earlier ones.
  for _, overlay_path in ipairs({...}) do
    load_dic_file(overlay_path, english)
  end

  local forms = assert(io.open(russian_path or "data/BASE.RUS", "r"))
  for line in forms:lines() do
    local word, code = line:match("^(.-)\x2a(.*)$")
    if code then russian[encoding.decode(word)] = code end
  end
  forms:close()
  return english, russian
end

return dictionary_store
