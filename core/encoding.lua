-- Keep the legacy character set boundary in one pure module so callers can
-- convert text without loading the tokenizer, diagnostics, or dictionaries.
local encoding = {}

local cp866_to_utf8 = {
  [0x80]="А", [0x81]="Б", [0x82]="В", [0x83]="Г", [0x84]="Д", [0x85]="Е", [0x86]="Ж", [0x87]="З",
  [0x88]="И", [0x89]="Й", [0x8A]="К", [0x8B]="Л", [0x8C]="М", [0x8D]="Н", [0x8E]="О", [0x8F]="П",
  [0x90]="Р", [0x91]="С", [0x92]="Т", [0x93]="У", [0x94]="Ф", [0x95]="Х", [0x96]="Ц", [0x97]="Ч",
  [0x98]="Ш", [0x99]="Щ", [0x9A]="Ъ", [0x9B]="Ы", [0x9C]="Ь", [0x9D]="Э", [0x9E]="Ю", [0x9F]="Я",
  [0xA0]="а", [0xA1]="б", [0xA2]="в", [0xA3]="г", [0xA4]="д", [0xA5]="е", [0xA6]="ж", [0xA7]="з",
  [0xA8]="и", [0xA9]="й", [0xAA]="к", [0xAB]="л", [0xAC]="м", [0xAD]="н", [0xAE]="о", [0xAF]="п",
  [0xE0]="р", [0xE1]="с", [0xE2]="т", [0xE3]="у", [0xE4]="ф", [0xE5]="х", [0xE6]="ц", [0xE7]="ч",
  [0xE8]="ш", [0xE9]="щ", [0xEA]="ъ", [0xEB]="ы", [0xEC]="ь", [0xED]="э", [0xEE]="ю", [0xEF]="я",
  [0xF0]="ё",
}

local utf8_to_cp866 = {}
for byte, character in pairs(cp866_to_utf8) do utf8_to_cp866[character] = byte end

function encoding.encode(text)
  local result, i = {}, 1
  while i <= #text do
    local byte = text:byte(i)
    if byte < 0x80 then
      result[#result + 1], i = string.char(byte), i + 1
    else
      local converted = text:byte(i + 1) and utf8_to_cp866[text:sub(i, i + 1)]
      result[#result + 1] = converted and string.char(converted) or string.char(byte)
      i = i + (converted and 2 or 1)
    end
  end
  return table.concat(result)
end

function encoding.decode(text)
  local result = {}
  for i = 1, #text do
    local byte = text:byte(i)
    result[i] = cp866_to_utf8[byte] or string.char(byte)
  end
  return table.concat(result)
end

function encoding.extract(text)
  return text:match("[\127-\255]+")
end

function encoding.decode_cyrillic(text)
  -- The LTGOLD DIC format uses ')' to separate a packed stem from the full
  -- Russian form (e.g. Nврем)время).  When the text before ')' consists only
  -- of a tag + short Cyrillic abbreviation (no punctuation like ; . { ), use
  -- the full form after ')' instead of the abbreviated stem.
  local paren = text:find('\x29')
  if paren then
    local before_cp866 = text:sub(1, paren - 1)
    -- Strip the leading tag byte(s)
    local tag_stripped = before_cp866:gsub("^[A-Z]+", "")
    local before_utf = encoding.decode(tag_stripped)
    local cyrillic = before_utf:gsub("[^абвгдежзиклмнопрстуфхцчшщъыьэюяё]", "")
    local non_cyrillic = before_utf:gsub("[абвгдежзиклмнопрстуфхцчшщъыьэюяё]", "")
    -- Pure Cyrillic abbreviation (no punctuation) → use the full form after ')'
    if #cyrillic > 0 and #non_cyrillic == 0 and #cyrillic <= 10 then
      local after = text:sub(paren + 1)
      return encoding.extract(encoding.decode(after))
    end
  end
  return encoding.extract(encoding.decode(text))
end

function encoding.character(byte)
  return cp866_to_utf8[byte]
end

return encoding
