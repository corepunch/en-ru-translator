-- LTPRO's file layer for the /F- profile: how a text file becomes sentences,
-- and how their translations, separators and meanings appendices are written.
-- Ported from the unpacked LTPRO.EXE; addresses are segment:offset.
--
--   043A:02A0  read a line: NUL -> space, CR/LF/CRLF ends it, trailing
--              whitespace dropped, one LF kept
--   0687:34C7  per line: accumulate up to ten lines of a sentence; a blank or
--              wordless line, a list marker, or a line after a short one
--              (shorter than half of this one, with at most five records)
--              ends the accumulated text, which is translated unterminated
--   0687:1A63  classify a line: indentation, record count (0687:1B93), and
--              list markers (1F94:0007)
--   0687:24F0  find a sentence end in the accumulated line; it sets the
--              separator written after the translation, which persists
--   0687:2813  join the lines and translate (a text of 0 or 1 byte is copied)
--   0687:28E1  write the first line's prefix, the translation, the separator
--   0687:01C8  meanings appendix entries; 0687:0181 writes the appendix
--   043A:2391  at end of file: translate what remains, write the appendix
--
-- Text is CP866 throughout; the result uses CRLF as LTPRO's text-mode file.
local engine = require 'core.engine'
local encoding = require 'core.encoding'
local matching = require 'core.matching'
local output = require 'core.output'
local transliteration = require 'core.transliteration'

local document = {}

local MAX_LINES = 10     -- DS:042D
local SHORT_LINE = 5     -- DS:0431, records in a line that ends a paragraph
local APPENDIX_LIMIT = 0xEFD
local APPENDIX_HEAD = '\n\nMULTIPLE MEANINGS:\n'
local ABBREVIATIONS = {'mr', 'ms', 'mrs', 'messrs', 'dr', 'prof', 'vs', 'v', 'no', 'st'}
-- DS:BBC2: list-marker patterns over the line's records and their handlers.
local MARKERS = {
  {'`.``.``.`', 99}, {'[*-\254][?#H]', 0}, {'--[?#H]', 0}, {'//[?#H]', 0},
  {'/*[?#H]', 0}, {'[H?#])`.`[?#H]', 1}, {'[H?#])[?#H]', 1}, {'[H?#][?#H]', 10},
  {'[H?#]`.`[?#H]', 1}, {'([H?#])[?#H]', 1}, {'[H?#])`.`', 2}, {'(`ii`)', 22},
  {'(`iii`)', 22}, {'[H?#])', 2}, {'[H?#]', 12}, {'[H?#]`.`', 2}, {'H[?#H]', 11},
  {'[\186\179\201\200\218\192\195|:!*-\254]', 3},
}

-- The C library's ctype table (DS:BF77).
local function space(c) return c == 32 or c >= 9 and c <= 13 end
local function digit(c) return c >= 48 and c <= 57 end
local function upper(c) return c >= 65 and c <= 90 end
local function alpha(c) return upper(c) or c >= 97 and c <= 122 end
local function punct(c) return c >= 33 and c <= 47 or c >= 58 and c <= 64 or c >= 91 and c <= 96 or c >= 123 and c <= 126 end
local function cyrillic(c) return c >= 0x80 and c <= 0xAF or c >= 0xE0 and c <= 0xF1 end
local function byte(s, i) return i >= 0 and s:byte(i + 1) or 0 end

-- 0687:1602: the records of one word, split at hyphens, slashes and
-- parentheses unless the part before is purely alphabetic.
local function word_records(line, text)
  local function tag_of(letters, digits, cyr, other)
    if letters ~= 0 and digits ~= 0 or cyr ~= 0 or other ~= 0 then return '#' end
    if letters == 0 and digits ~= 0 then return 'H' end
    return '?'
  end
  local first = text:sub(1, 1)
  if first == '.' or first == '#' or first == '_' or first == '?' then
    if #text == 1 and not alpha(text:byte(1)) then
      local b = line.boundary(first, 0); b.tag = 0x23; return b
    end
    return line.word(first == '_' and '?' or '#', text)
  end
  local letters, digits, cyr, other = 0, 0, 0, 0
  local q, base, split, last = 1, 1, false, nil
  if first == '/' then other, q = 1, 2 end
  while q <= #text do
    local c = text:byte(q)
    if alpha(c) then letters = letters + 1
    elseif digit(c) then digits = digits + 1
    elseif cyrillic(c) then cyr = cyr + 1
    elseif c == 45 or c == 40 or c == 47 then
      if letters ~= 0 and digits == 0 and cyr == 0 and other == 0 and c ~= 40 then split = true end
      local tag = tag_of(letters, digits, cyr, other)
      if not (split and tag == '?' and c ~= 40) then
        last = line.word(tag, text:sub(base, q - 1))
        line.boundary(string.char(c), 0)
        line.words = line.words + 1
        letters, digits, cyr, other, split = 0, 0, 0, 0, false
        base = q + 1
      end
    elseif c ~= 39 and c ~= 46 and c ~= 44 then other = other + 1 end
    q = q + 1
  end
  local tag, part = tag_of(letters, digits, cyr, other), text:sub(base)
  if (part:byte(1) or 0) > 0x7A and tag == '#' and #part == 1 then
    return line.boundary(part, 0)
  end
  last = line.word(tag, part)
  if tag == '?' then line.words = line.words + 1 end
  return last
end

-- 0687:1B93 in its line mode ('='): the records LTPRO makes of one line.
local function line_records(text)
  local line = {records = {}, words = 0, literal = false}
  function line.word(tag, value)
    if (tag == '?' or tag == '#' or tag == 'H') and #value >= 0x28 then tag = '#' end
    local r = {kind = 'W', tag = tag:byte(), source = value, length = #value, position = 0}
    line.records[#line.records + 1] = r
    return r
  end
  function line.boundary(c, marker)
    local r = {kind = 'D', tag = c:byte(), source = c, marker = marker, position = 0}
    line.records[#line.records + 1] = r
    return r
  end
  for start, token in text:gmatch('()([^ \r\n\t\f\v]+)') do
    local at = start - 1
    local quote = token:sub(1, 1)
    if token:sub(1, 2) == '{~' then line.literal = true; token = token:sub(3) end
    if line.literal then token = token:sub(1, -3)
    elseif #token > 1 and token:sub(-2) == '~}' then line.literal = true; token = token:sub(1, -3) end
    if token:sub(1, 2) == '~}' then line.literal = true; token = token:sub(3) end
    local c = token:byte(1)
    if c and (punct(c) or c > 0xEF or c > 0xAF and c < 0xE0) and c ~= 46 and c ~= 95 and c ~= 63
        and not ((c == 35 or c == 47) and alpha(token:byte(2) or 0)) then
      local b = line.boundary(c == 96 and "'" or string.char(c), 0x20)
      b.position = at
      token, at = token:sub(2), at + 1
      while token ~= '' do
        c = token:byte(1)
        if not (punct(c) or c > 0xEF or c > 0xAF and c < 0xE0) or c == 95 then break end
        local r = line.boundary(string.char(c), 0)
        if r.tag == 46 then r.tag = 0x23 end
        token, at = token:sub(2), at + 1
      end
    end
    if token ~= '' then
      local si = #token
      if token:sub(-1) == "'" and quote == "'" then si = si - 1 end
      local function ch(k) return k >= 0 and token:byte(k + 1) or 0 end
      local di = si
      while true do
        local e = ch(di - 1)
        if not (e == 46 or e == 95 or e == 39 and (ch(di - 2) == 115 or ch(di - 2) == 83)) and punct(e) then
          di = di - 1
        elseif e == 46 and not alpha(ch(di - 2)) then di = di - 1
        else break end
      end
      if not (di == 0 and alpha(ch(0))) then
        local r = word_records(line, token:sub(1, math.max(di, 0)))
        r.position = at
      end
      if si < #token then si = si + 1 end
      if not (ch(si - 1) == 46 and not digit(ch(si - 2))) then
        for k = math.max(di, 0), si - 1 do
          local b = line.boundary(string.char(ch(k)), 0)
          if b.tag == 46 then b.tag = 0x23 end
        end
      end
    end
  end
  for i, r in ipairs(line.records) do r.next = line.records[i + 1] end
  return line
end

-- 1F94:0007: a list marker at the start of the line. It returns the matched
-- length (0 when none) and the offset where the line's text starts.
local function list_marker(records)
  if #records < 3 then return 0 end
  local vector = {}
  for i, r in ipairs(records) do vector[i - 1] = r end
  vector[#records] = {tag = 0, source = ''}
  local si = 0
  for _, marker in ipairs(MARKERS) do
    si = matching.match(vector, 0, marker[1])
    local selector = marker[2]
    local r = records[1]
    local function accept()
      local last = records[si + 1]
      if not last then return 0 end
      return si, last.position
    end
    if si ~= 0 then
      if selector == 1 or selector == 2 or selector == 22 then
        if r.tag == 40 then r = records[2]; if not r then return 0 end end
        if selector ~= 22 and r.tag == 63 and r.kind == 'W' and r.length > 1 then goto continue end
        if selector == 1 then return accept() end
        local last = records[si + 1]
        if not last then return 0 end
        if last.next then return si, last.next.position end
        if selector == 22 or r.kind == 'W' then return si, r.position + (r.length or 0) + 2 end
        return si, r.position + 3
      elseif selector == 10 then
        if r.kind == 'W' and r.length <= 2 and r.source:sub(-1) == '.' then return accept() end
      elseif selector == 11 then
        if r.source:find('.', 1, true) and r.next and upper(r.next.source:byte(1) or 0) then return accept() end
      elseif selector == 12 then
        if r.kind == 'W' and r.length <= 2 and r.source:sub(-1) == '.' then
          if r.next and r.next.marker ~= 0x2A then return si, r.next.position end
        end
      elseif selector == 3 then
        local last = records[si + 1]
        if not last then return 0 end
        return si, last.next and last.next.position or last.position + 2
      elseif selector == 4 then return -1
      elseif selector ~= 99 then return accept() end
    end
    ::continue::
  end
  return si
end

-- 0687:1A63: -1 for a line that is written as it is (blank, or without
-- words), otherwise the list-marker length. The line's slot receives its
-- indentation, text start and record count.
local function classify(slot, text)
  if text:byte(1) == 10 then return -1 end
  local first = text:find('[^ \t\f\v\n]')
  if not first then slot.indent, slot.start = 0, 0; return -1 end
  slot.indent, slot.start = first - 1, first - 1
  local line = line_records(text)
  slot.records = #line.records
  if line.words == 0 and not line.literal then return -1 end
  local result, start = list_marker(line.records)
  if start then slot.start = start end
  return result
end

-- 0687:0C5DE: the next word does not begin a sentence.
local function continues(text, i)
  while space(byte(text, i)) do i = i + 1 end
  local c = byte(text, i)
  return c ~= 0 and not (upper(c) or c == 40 or c == 34 or c == 39 or c == 96 or c == 91 or digit(c))
end
-- 0687:0C562: the next word may begin a sentence.
local function begins(text, i)
  while space(byte(text, i)) do i = i + 1 end
  local c = byte(text, i)
  return upper(c) or c == 40 or c == 34 or c == 39 or c == 96 or c == 91 or digit(c)
end

-- 0687:0C666: the dot at `p` ends an abbreviation.
local function abbreviation(text, start, p)
  if p == start then return false end
  local q = p - 1
  if not alpha(byte(text, q)) then return false end
  q = q - 1
  while q ~= start do
    local c = byte(text, q)
    if space(c) then
      q = q + 1
      if q + 1 == p then return true end
      break
    elseif not (alpha(c) or c == 46) then return false end
    q = q - 1
  end
  local word = text:sub(q + 1, p):lower()
  for _, value in ipairs(ABBREVIATIONS) do
    if word == value then return true end
  end
  return false
end

-- 0687:24F0: the next sentence end at or after `from`, and its separator.
local function sentence_end(text, from)
  local q = from
  while true do
    local p = text:find('[.?!:;]', q + 1)
    local spaces = text:find('      ', q + 1, true)
    if spaces and (not p or spaces < p) then return spaces - 1, '      ' end
    if not p then return nil end
    p = p - 1
    local c, c1 = byte(text, p), byte(text, p + 1)
    if c == 46 or c == 63 or c == 33 then
      if space(c1) or c1 == 0 then
        if not (c == 46 and (c1 ~= 0 and continues(text, p + 2) or abbreviation(text, from, p))) then
          return p, string.char(c) .. (c1 == 10 and '\n' or '')
        end
      elseif c1 == 41 or c1 == 34 or c1 == 39 or c1 == 46 or c1 == 93 then
        local c2 = byte(text, p + 2)
        if c2 == 0 or c2 == 10 or c2 == 41 or c2 == 93 or begins(text, p + 2) or c2 == 46 then
          local separator = text:sub(p + 1, p + 2)
          if c2 == 10 then separator = separator .. '\n'
          elseif c2 == 41 or c2 == 46 or c2 == 93 then
            separator = separator .. string.char(c2) .. (byte(text, p + 3) == 10 and '\n' or '')
          end
          return p, separator
        end
      end
    elseif c1 == 10 then return p, string.char(c) .. '\n'
    elseif c == 58 and space(c1) and begins(text, p + 2) then return p, ':'
    end
    q = p + 1
  end
end

function document.new(options)
  local slots = {}
  for i = 0, MAX_LINES do slots[i] = {text = '', length = 0, indent = 0, start = 0, records = 0} end
  return {
    options = options or {}, slots = slots, count = 0, continued = false,
    separator = '\n', appendix = '', next_meaning = 1, out = {},
    verbatim = false, transliterate = false, list = false,
  }
end

local function write(doc, value) doc.out[#doc.out + 1] = value end

-- 0687:0181
local function flush_appendix(doc)
  if doc.next_meaning == 1 or doc.appendix == '' then return end
  write(doc, APPENDIX_HEAD); write(doc, doc.appendix); write(doc, '\n\n')
  doc.appendix, doc.next_meaning = '', 1
end

-- 0687:2813 and the sentence driver 0687:05D5.
local function translate(doc, count, terminator)
  local parts = {doc.slots[0].text:sub(doc.slots[0].start + 1)}
  for i = 1, count - 1 do parts[#parts + 1] = doc.slots[i].text:sub(doc.slots[i].indent + 1) end
  local sentence = table.concat(parts)
  if #sentence <= 1 then return sentence end
  local options = {}
  for key, value in pairs(doc.options) do options[key] = value end
  options.terminator, options.meaning_start, options.meanings = terminator, doc.next_meaning, false
  -- A {~ left open protects the following sentences too, until a ~}.
  local text = encoding.decode(sentence)
  if doc.protected then text = '{~' .. text end
  local open, close = text:match('.*(){~'), text:match('.*()~}')
  doc.protected = open ~= nil and (close == nil or close < open)
  local result, state = engine.run(text, options)
  local alternatives = state.alternatives or 0
  if #doc.appendix < APPENDIX_LIMIT then
    doc.appendix = doc.appendix .. output.meanings(state, state.root)
  end
  doc.next_meaning = doc.next_meaning + alternatives
  return result
end

-- 0687:28E1 with /F-: the first line's prefix, the translation and the
-- separator of the last sentence end.
local function write_sentence(doc, translation)
  if translation:sub(1, 1) == ' ' then translation = translation:sub(2) end
  local first = doc.slots[0]
  write(doc, first.text:sub(1, first.start) .. translation .. doc.separator)
end

-- 0687:34C7
function document.line(doc, text)
  if text == '{~\n' or text == '{~=\n' then
    if text == '{~=\n' then doc.transliterate = true end
    doc.verbatim = true
    return
  elseif text == '~}\n' then
    doc.verbatim, doc.transliterate = false, false
    return
  elseif text == '{~\\n\n' then doc.list = true; return
  elseif text == '{~\\.\n' then doc.list = false; return
  end
  if doc.verbatim then
    write(doc, doc.transliterate and encoding.encode(transliteration.convert(encoding.decode(text), true)) or text)
    return
  end
  local count = doc.count
  local slot = doc.slots[count]
  local length = #text
  local kind = classify(slot, text)
  local join = false
  if kind == 0 and count < MAX_LINES and not doc.list then
    if doc.continued or count <= 0 then join = true
    else
      local previous = doc.slots[count - 1]
      if previous.length * 2 >= length and (SHORT_LINE == 0 or previous.records > SHORT_LINE) then join = true end
    end
  end
  if not join then
    if count ~= 0 then
      write_sentence(doc, translate(doc, count, 10))
      local previous = doc.slots[count - 1]
      if SHORT_LINE ~= 0 and previous.records <= SHORT_LINE then previous.records = slot.records end
      if kind ~= -1 then
        doc.slots[0].indent, doc.slots[0].start = slot.indent, slot.start
      else flush_appendix(doc) end
      doc.count, doc.continued = 0, false
    end
    if kind == -1 then write(doc, text); return end
    if doc.list then
      local first = doc.slots[0]
      if text:byte(length - 1) == 46 then
        doc.separator = '.\n'; text = text:sub(1, length - 2)
      else doc.separator = '\n' end
      first.text, first.length = text, length
      write_sentence(doc, translate(doc, 1, doc.separator:byte(1)))
      if doc.separator:byte(1) == 46 then write(doc, '\n') end
      flush_appendix(doc)
      doc.count = 0
      return
    end
  end
  if kind == -1 then return end
  count = doc.count
  doc.slots[count].text, doc.slots[count].length = text, length
  while true do
    slot = doc.slots[count]
    local p, separator = sentence_end(slot.text, slot.start)
    if not p then doc.count = count + 1; return end
    doc.separator = separator
    local rest = slot.text:sub(p + 1 + #separator)
    slot.text = slot.text:sub(1, p)
    write_sentence(doc, translate(doc, count + 1, separator:byte(1)))
    count, doc.count = 0, 0
    if rest == '' or rest == '\n' or rest == '~}\n' then
      flush_appendix(doc)
      doc.continued = false
      return
    end
    local first = doc.slots[0]
    local start = rest:find('[^ \t\f\v\n]')
    first.indent = start and start - 1 or #rest
    first.start = first.indent
    first.text = rest
    doc.continued = true
  end
end

-- 043A:2391 after the last line.
function document.finish(doc)
  if doc.count ~= 0 then
    write_sentence(doc, translate(doc, doc.count, 10))
  end
  flush_appendix(doc)
  return (table.concat(doc.out):gsub('\n', '\r\n'))
end

-- 043A:02A0: the lines of a file as LTPRO reads them.
function document.lines(input)
  local lines, i = {}, 1
  while i <= #input do
    local finish = input:find('[\r\n]', i)
    local line = input:sub(i, (finish or #input + 1) - 1):gsub('%z', ' ')
    if finish then
      i = finish + 1
      if input:byte(finish) == 13 and input:byte(i) == 10 then i = i + 1 end
    else i = #input + 1 end
    lines[#lines + 1] = line:gsub('[ \t\n\v\f\r]+$', '') .. '\n'
  end
  return lines
end

-- Translate CP866 file contents; the result is CP866 with CRLF.
function document.translate(input, options)
  local doc = document.new(options)
  for _, line in ipairs(document.lines(input)) do document.line(doc, line) end
  return document.finish(doc)
end

return document
