local utils = {}

local cp866_to_utf8 = {
  [0x80]="А", [0x81]="Б", [0x82]="В", [0x83]="Г",
  [0x84]="Д", [0x85]="Е", [0x86]="Ж", [0x87]="З",
  [0x88]="И", [0x89]="Й", [0x8A]="К", [0x8B]="Л",
  [0x8C]="М", [0x8D]="Н", [0x8E]="О", [0x8F]="П",
  [0x90]="Р", [0x91]="С", [0x92]="Т", [0x93]="У",
  [0x94]="Ф", [0x95]="Х", [0x96]="Ц", [0x97]="Ч",
  [0x98]="Ш", [0x99]="Щ", [0x9A]="Ъ", [0x9B]="Ы",
  [0x9C]="Ь", [0x9D]="Э", [0x9E]="Ю", [0x9F]="Я",

  [0xA0]="а", [0xA1]="б", [0xA2]="в", [0xA3]="г",
  [0xA4]="д", [0xA5]="е", [0xA6]="ж", [0xA7]="з",
  [0xA8]="и", [0xA9]="й", [0xAA]="к", [0xAB]="л",
  [0xAC]="м", [0xAD]="н", [0xAE]="о", [0xAF]="п",
  [0xE0]="р", [0xE1]="с", [0xE2]="т", [0xE3]="у",
  [0xE4]="ф", [0xE5]="х", [0xE6]="ц", [0xE7]="ч",
  [0xE8]="ш", [0xE9]="щ", [0xEA]="ъ", [0xEB]="ы",
  [0xEC]="ь", [0xED]="э", [0xEE]="ю", [0xEF]="я",

  [0xF0]="ё", --[0xF1]="Ё",
}

function utils.extract(s)
  return s:match("[\127-\255]+")
end

function utils.decode(s, strip)
  local t = {}
  for i = 1, #s do table.insert(t, cp866_to_utf8[s:byte(i)] or string.char(s:byte(i))) end
  return strip and utils.extract(table.concat(t)) or table.concat(t)
end

function utils.debug(w, t, i)
  t = t or {}
  i = i or 0
  if type(w) == 'string' then table.insert(t, string.rep(" ", i)..utils.decode(w)) return end
  for k, v in pairs(w) do 
    table.insert(t, string.rep(" ",i)..k..": ") 
    utils.debug(type(v) == 'table' and v or tostring(v), t, i+1)
    -- table.insert(t, "\n")
  end
  return table.concat(t, " ")
end

function utils.tokenize(s, en_ru)
  print("Input: "..s)
  local prev, tbl, words, last, i = nil, {}, {}, 0, 1
  for w in s:gmatch("%w+[,%!%.;:]?") do table.insert(words, w) end
  while i <= #words do
    local word, punct = words[i]:match("(%w+)([,%!%.;:]?)")
    word = word:lower()
    if not prev then
      if en_ru[word] then table.insert(tbl, en_ru[word].__lex)
      else table.insert(tbl, '#'..word) end
      prev, last = en_ru[word], i
      if punct ~= "" then table.insert(tbl, punct)
      else prev, last = en_ru[word], i end
    elseif not prev[word] or punct then
      i, prev = last, nil
    elseif prev[word].__lex then
      tbl[#tbl], last = prev[word].__lex, i
    else
      prev = prev[word]
    end
    i = i + 1
  end
  -- for k, v in pairs(tbl) do print(v) end
  return tbl
end


return utils