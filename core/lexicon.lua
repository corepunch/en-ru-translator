local layout = require 'core.record_layout'
local nodes = require 'core.nodes'
local transliteration = require 'core.transliteration'
local text = require 'core.text'
local prefixes = require 'core.prefixes'
local directives = require 'core.directives'
local phrase_patterns = require 'core.phrase_patterns'

local lexicon = {}

-- Lossless DIC ingestion for the native compatibility path. Record order,
-- annotations, periods, W prefixes, duplicate entries and back-references survive.
-- Search/merge policies are separate from byte ingestion.
function lexicon.from_bytes(bytes)
  local result={bytes=bytes,records={},by_key={},by_token={},unparsed={}}
  local start=1
  while start<=#bytes do
    local finish=bytes:find('\n',start,true) or (#bytes+1)
    local raw=bytes:sub(start,finish-1)
    local line=raw:gsub('\r$','')
    local star=line:find('*',1,true)
    if star then
      local record={key=line:sub(1,star-1),value=line:sub(star+1),raw=raw,offset=start-1}
      result.records[#result.records+1]=record
      result.by_key[record.key]=result.by_key[record.key] or {}
      local list=result.by_key[record.key];list[#list+1]=record
      -- The native scan tokenizes keys on space and star and folds ASCII case.
      local token=line:match('^([^ *]*)'):gsub('[A-Z]',string.lower)
      result.by_token[token]=result.by_token[token] or {}
      local tokens=result.by_token[token];tokens[#tokens+1]=record
    else result.unparsed[#result.unparsed+1]={raw=raw,offset=start-1} end
    start=finish+1
  end
  return result
end

-- Narrow lexical fallback recovered from LTPRO 0A4F:07F2 (file 0x0E6E2).
-- The suffix rows are the native DS:0778 table: ending, class/metadata text.
-- Productive rows (ing, ed, plurals, ly) search a rewritten stem. Adjective
-- and possessive class rows do too. Derivational noun rows do not invent a
-- stem: an unknown word such as "strongness" stays the surface word and is
-- recorded as a noun. Phrase and annotation handling stays with the analyzer.
-- Native row order matters. For example, `ies` precedes `es` and `s`, and
-- `ed` follows `ied`. The ASCII strings and selectors were read from DS:0778.
local rows = {
  { "ies'", "N12", "class" },
  { "es'", "N12", "class" },
  { "s'", "N12", "class" },
  { "'s", "N02", "class" },
  { "ing", "G8", "ing" },
  { "ied", "E", "ied" },
  { "ed", "E", "ed" },
  { "ness", "N00", "class" },
  { "ous", "A", "class" },
  { "less", "A", "class" },
  { "ies", "Z13", "ies" },
  { "es", "Z13", "es" },
  { "s", "Z13", "s" },
  { "fy", "V", "class" },
  { "ment", "N00", "class" },
  { "ion", "N00", "class" },
  { "ence", "N00", "class" },
  { "ance", "N00", "class" },
  { "enc", "N00", "class" },
  { "anc", "N00", "class" },
  { "ity", "N00", "class" },
  { "age", "N00", "class" },
  { "ure", "N00", "class" },
  { "ag", "N00", "class" },
  { "nes", "N00", "class" },
  { "or", "N00", "class" },
  { "iest", "A", "class" },
  { "ier", "A", "class" },
  { "est", "A", "class" },
  { "eur", "A", "class" },
  { "er", "A", "class" },
  { "ur", "N00", "class" },
  { "ly", "D", "ly" },
  { "ical", "A", "class" },
  { "ic", "A", "class" },
  { "ible", "A", "class" },
  { "able", "A", "class" },
  { "ibl", "A", "class" },
  { "abl", "A", "class" },
  { "ory", "A", "class" },
  { "ary", "A", "class" },
  { "ou", "A", "class" },
  { "les", "A", "class" },
}
for _, row in ipairs(rows) do
  row.ending, row.selector, row.transform = row[1], row[2], row[3]
end

local function ascii_lower(text)
  return (text:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

local function lookup(dictionary, key, options)
  local records = dictionary.by_key[ascii_lower(key)]
  if not records then return nil end
  local index = 1
  if options and options.dictionary_entry ~= nil then
    assert(type(options.dictionary_entry)=='function', 'dictionary_entry must be a function')
    index=options.dictionary_entry(key,records)
  end
  assert(type(index) == 'number' and records[index], 'invalid dictionary entry selection: ' .. key)
  return records[index]
end

local suffix_fields

local function resolve(dictionary,key,options)
  local seen={}
  local record=lookup(dictionary,key,options)
  while record and record.value:sub(1,1)=='=' do
    local normalized=ascii_lower(key)
    assert(not seen[normalized], 'cyclic dictionary redirect: '..key)
    seen[normalized]=true
    key=record.value:sub(2)
    record=lookup(dictionary,key,options)
  end
  return record,key
end

local function decode_record(record, source, candidate, row, exact)
  local value = record.value or ""
  local tag = value:sub(1, 1)
  if not ("ekxjtudbiplyfgac"):find(tag, 1, true) then tag = tag:upper() end
  local payload = value:sub(2)
  local backref
  local slash = payload:find("\\", 1, true)
  if slash then
    backref = payload:sub(slash + 1)
    payload = payload:sub(1, slash - 1)
  end

  local morphology_tag = row and row.selector:sub(1, 1) or nil
  if row and (row.transform == "ed" or row.transform == "ied") then
    tag = "E"
  elseif row and row.transform == "ing" then
    tag = "G"
  elseif row and row.transform == "ly" then
    tag = "D"
  end

  local fields = suffix_fields(row)
  if row and row.selector:sub(1, 1) == "A" and fields.tense and fields.tense ~= 0
      and (tag == "Z" or tag == "N") then
    tag = "A"
  end

  return {
    record = record,
    source = source,
    candidate = candidate,
    exact = exact,
    tag = tag,
    payload = payload,
    backref = backref,
    morphology_tag = morphology_tag,
    native_suffix = row and row.ending or nil,
    native_selector = row and row.selector or nil,
    fields = fields,
  }
end

local function selector_digit(selector, index)
  local byte = selector:byte(index + 1) or 0
  if byte >= 48 and byte <= 57 then return byte - 48 end
  return 0
end

-- Grammar written by the 0A4F:07F2 class switch, independent of the dictionary hit.
function suffix_fields(row)
  local fields = {}
  if not row then return fields end
  local class = row.selector:sub(1, 1)
  if class == "Z" then
    fields.number, fields.person = selector_digit(row.selector, 1), selector_digit(row.selector, 2)
  elseif class == "G" or class == "V" then
    fields.case_mask = 8
  elseif class == "E" then
    fields.tense, fields.case_mask = 1, 8
  elseif class == "A" then
    fields.marker = 0x61
    local last, before = row.ending:sub(-1), row.ending:sub(-2, -2)
    if last == "r" and (before == "e" or before == "u") then fields.tense = 1
    elseif row.ending:sub(-2) == "st" then fields.tense = 2 end
  elseif class == "N" then
    fields.number = selector_digit(row.selector, 1)
    fields.case_mask = selector_digit(row.selector, 2)
  end
  return fields
end

local function with_extra(stem, extra)
  if extra and extra ~= "" and stem:sub(-#extra) ~= extra then return { stem, stem .. extra } end
  return { stem }
end

-- Adjective endings restore ie→y, undo a doubled consonant, or keep the
-- auxiliary e that an ending such as -er records for the second try.
local function adjective_candidates(word, ending)
  local stem = word:sub(1, #word - #ending)
  local extra = ending:sub(1, 1) == "e" and "e" or nil
  if ending:sub(1, 2) == "ie" then
    stem, extra = stem .. "y", nil
  elseif #stem >= 2 and stem:sub(-1) == stem:sub(-2, -2) then
    extra, stem = stem:sub(-1), stem:sub(1, -2)
  end
  return with_extra(stem, extra)
end

local function class_candidates(word, row)
  local class = row.selector:sub(1, 1)
  local ending = row.ending
  if class == "N" and not ending:find("'", 1, true) then return {} end
  if class == "A" then return adjective_candidates(word, ending) end
  local stem = word:sub(1, #word - #ending)
  if class == "V" then return with_extra(stem, ending:sub(1, 1) == "e" and "e" or nil) end
  if ending == "ies'" then return {stem .. 'y'} end
  if ending == "es'" then return with_extra(stem, 'e') end
  return { stem }
end

local function candidates(word, row)
  local ending = row.ending
  local stem = word:sub(1, #word - #ending)
  if row.transform == "ies" then return { stem .. "y" } end
  if row.transform == "s" or row.transform == "es" or row.transform == "ly" then
    if row.transform == "es" then return { stem, stem .. "e" } end
    return { stem }
  end
  if row.transform == "ied" then return { stem .. "y" } end
  if row.transform == "ed" then
    if #stem >= 2 and stem:sub(-1) == stem:sub(-2, -2) then
      return { stem:sub(1, -2) }
    end
    return { stem, stem .. "e" }
  end
  if row.transform == "ing" then
    if #stem >= 2 and stem:sub(-1) == stem:sub(-2, -2) then
      return { stem:sub(1, -2) }
    end
    -- The native G branch writes auxiliary `e` when the truncated stem is
    -- not doubled (0A4F:0E793), just as the E branch inherits it from the
    -- suffix preamble. Try the literal truncated root before that e form.
    return { stem, stem .. "e" }
  end
  return nil
end

-- Resolve one lexical token against exact records, then the bounded native
-- productive endings implemented above. Returns (result, nil), (nil, nil) for
-- no applicable native ending, or (nil, reason) for a recognized but
-- unsupported/ambiguous branch. Result.payload excludes a dictionary backref;
-- callers must apply result.backref only when their native context allows it.
function lexicon.lookup(dictionary, source, options)
  assert(type(source) == "string" and source ~= "", "suffix lookup needs a source word")
  local word = ascii_lower(source)
  local exact, exact_key = resolve(dictionary, word, options)
  if exact then return decode_record(exact, source, exact_key, nil, true) end

  for _, row in ipairs(rows) do
    if #word > #row.ending and word:sub(-#row.ending) == row.ending then
      local choices = row.transform == "class" and class_candidates(word, row) or candidates(word, row)
      for _, candidate in ipairs(choices) do
        local record, resolved = resolve(dictionary, candidate, options)
        if record then
          return decode_record(record, source, resolved, row, false)
        end
      end
      -- 0A4F:07F2 stops at the first table row whose ending matches. Do not
      -- fall through to a shorter ending when its candidate misses. A class
      -- row with no dictionary stem leaves the surface word unchanged.
      -- Derivational nouns still publish noun grammar through surface_noun.
      if row.transform == "class" then return nil end
      return nil, "native suffix candidate missed: " .. row.ending
    end
  end
  return nil
end

-- Return field writes performed by the first matching DS:0778 row, before the
-- caller knows whether its derived dictionary candidate will match. The A
-- dispatch is useful when a larger hyphenated token fails and is split later:
-- native 0A4F:07F2 leaves these two side effects on the first component.
-- Other dispatches also mutate the node, but are deliberately omitted here
-- until their failed-candidate lifetime is independently captured.
function lexicon.attempt_fields(source)
  assert(type(source) == "string" and source ~= "", "suffix attempt needs a source word")
  local word = ascii_lower(source)
  for _, row in ipairs(rows) do
    if #word > #row.ending and word:sub(-#row.ending) == row.ending then
      local fields = {}
      if row.selector == "A" then
        fields.marker = 0x61
        local last, before_last = word:sub(-1), word:sub(-2, -2)
        if last == "r" and (before_last == "e" or before_last == "u") then
          fields.tense = 1
        elseif word:sub(-2) == "st" then
          fields.tense = 2
        end
      end
      return { ending = row.ending, selector = row.selector, fields = fields }
    end
  end
  return nil
end

-- Noun grammar for a derivational ending that keeps the surface word.
-- 0A4F:07F2 writes tag N, number, and case for an N-class row, and truncates
-- the source only when the ending contains an apostrophe. With no apostrophe
-- the caller looks the whole word up, misses, and leaves tag N in place
-- (0A4F:3A63). Possessives and every earlier row are excluded: those either
-- find a stem or follow a different miss path.
function lexicon.surface_noun(source)
  assert(type(source) == "string" and source ~= "", "surface noun needs a source word")
  local word = ascii_lower(source)
  for _, row in ipairs(rows) do
    if #word > #row.ending and word:sub(-#row.ending) == row.ending then
      local class = row.selector:sub(1, 1)
      if row.transform == "class" and class == "N" and not row.ending:find("'", 1, true) then
        return { tag = "N", ending = row.ending, selector = row.selector, fields = suffix_fields(row) }
      end
      return nil
    end
  end
  return nil
end

local function derivational_compound(dictionary,source,options)
  local left, right = ascii_lower(source):match('^([^/-]+)[/-]([^/-]+)$')
  if not left then return false end
  -- A standalone dictionary word (ion, age, or, ...) is not merely a suffix.
  -- Preserve whole unknown compounds only when neither part has a reading.
  if lookup(dictionary,left,options) or lookup(dictionary,right,options) then return false end
  for _, row in ipairs(rows) do
    if row.selector == 'N00' and (left == row.ending or right == row.ending) then return true end
  end
  return false
end

-- Expose a defensive copy for fixture tooling; callers cannot change dispatch.
function lexicon.suffix_rows()
  local out = {}
  for i, row in ipairs(rows) do
    out[i] = { ending = row[1], selector = row[2], transform = row[3] }
  end
  return out
end

-- LTPRO 0A4F:0C0F (file EAFF..F45E): decode one lexical reading's metadata.
-- The caller has consumed the tag; payload and returned offset are CP866 bytes.
local tag = nodes.tag
local function has(s,c) return s:find(c,1,true) ~= nil end
local cases = {[0x82]=8,[0x84]=4,[0x8F]=32,[0x90]=2,[0x92]=16}

local function macroText(source, value, options, previous)
	local marker, supplied = value:sub(1, 1), value:sub(2)
	if marker == "=" and options.transliterate == false then return supplied end
	if supplied ~= "" and text.is_cyrillic(supplied:byte()) then return supplied end
	-- 211E:0E82 returns without touching its destination for an empty source.
	if source == "" then return previous or "" end
	return transliteration.convert(source, marker == "=")
end

-- 0A4F:0B3C, 0CE1 and 14D6: = honors the transliteration setting; % always
-- transliterates. A supplied Cyrillic spelling takes precedence over the source.
local function writeReading(node, value, options, ordinaryReadings, macroSource)
	local marker = value:sub(1, 1)
	if marker ~= "=" and marker ~= "%" then
		node.reading = value
		if ordinaryReadings then node.reading_state = 3 end
		return
	end
	-- Native phrase macros retain the joined source for output capitalization.
	if macroSource then node.source = macroSource end
	if macroSource or node.marker ~= 0x77 then node.reading = macroText(macroSource or node.source or "", value, options, node.reading) end
	if #value > 1 or options.transliterate ~= false or marker == "%" then
		node.reading_state = 3
		if marker == "%" then node.marker = 0x25 end
	end
	if marker == "=" then node.marker = 0x3D end
end

function lexicon.decode_reading(node, payload, options, macroSource)
  options = options or {}
  local p=1
  local function digit(at)
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then node[layout.key(at)]=b-48; p=p+1; return true end
    return false
  end
  local function paradigm(at)
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then
      local value=b-48
      node[layout.key(at)]=((node[layout.key(at)] or 0)&0x80)|value|((value&1)<<6)
      p=p+1
    end
  end
  local function aspect()
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then
      node.lookup_frame=((node.lookup_frame or 0)&0xBF)|(((b-48)&1)<<6)
      p=p+1
    end
  end
  local t=tag(node)
  if t=='#' then
    if payload:sub(p,p)=='#' then p=p+1 end
    local saved=node.number or 0
    if digit('number') and saved~=0 then node.number=saved end
    if not digit('gender') then
      local gender=({[0xAC]=1,[0xA6]=2,[0xE1]=0})[payload:byte(p)]
      if gender~=nil then node.gender=gender;p=p+1 end
    end
    node.person=3
    local text=payload:sub(p)
    writeReading(node, text, options, false, macroSource)
    return p-1
  elseif has('XYx',t) then
    digit('tense');digit('number');digit('person')
    if t=='Y' then node.case_mask=8 end
  elseif t=='y' then digit('aspect');node.case_mask=2
  elseif t=='d' then digit('aspect');digit('tense')
  elseif has('MRr',t) then
    digit('number');digit('person');digit('gender')
    if t=='M' then node.case_mask=2 end
  elseif has('OS',t) then digit('number');digit('aspect');digit('gender');node.person=3
  elseif has('PQfp',t) then
    local b=payload:byte(p)
    if b and b>0x81 and b<0x93 then
      if cases[b] then node.case_mask=cases[b] end
      p=p+1
    end
  elseif t=='I' then digit('number')
  elseif t=='U' then
    digit('tense');digit('verb_flags');node.case_mask,node.person=8,3
  elseif t=='J' then digit('tense');digit('aspect')
  elseif t=='N' then digit('aspect')
  elseif t=='n' then digit('aspect');node.number=1
  elseif t=='a' then node.marker=0x61
  elseif t=='v' then paradigm('lookup_flags');aspect();node.person,node.case_mask=3,8
  elseif t=='z' then paradigm('lookup_flags');aspect();node.number,node.person,node.case_mask=1,3,8
  elseif has('eEFGVZh',t) then
    if t=='e' and node.reading_state==1 and node.person==3 then
      node.tag,node.previous_tag=0x56,0x56
    end
    paradigm('lookup_flags');aspect()
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then
      node.lookup_frame=((node.lookup_frame or 0)&0xC0)|((b-48)&0x3F);p=p+1
    end
    node.case_mask=8
    t=tag(node)
    if has('EehF',t) or node.previous_tag==0x45 then node.tense=1 end
    if t=='h' then node.tag,node.previous_tag=0x56,0x56
    else
      b=payload:byte(p)
      if t=='E' and ((node.lookup_frame or 0)&0x3F)==1 and b and b>0x81 and b<0x93 then
        if cases[b] then node.governed_case=cases[b] end
        p=p+1
      end
      if t=='F' then node.marker,node.tag=0x6E,0x45 end
    end
  end
  t=tag(node)
  if not has('ekxjtudbiplyfgac',t) then node.tag=t:upper():byte() end
  local text=payload:sub(p)
  writeReading(node, text, options, true, macroSource)
  return p-1
end

-- Longest phrase wins; a literal key wins a tie against a key with gaps.

function lexicon.match_phrase(dictionary, records, index, key)
  local best,finish,captures,best_gaps,best_literals
  for _,record in ipairs(dictionary.by_token[key] or {}) do
    if record.key:find(' ',1,true) and not record.raw:find('*$',1,true) then
      local last,gaps=phrase_patterns.match(record.key,records,index,key)
      local _,parts=record.key:gsub('%S+','')
      local literals=parts-(gaps and #gaps or 0)
      if last and (not finish or last>finish or last==finish and
          (#gaps<best_gaps or #gaps==best_gaps and literals>best_literals)) then
        best,finish,captures,best_gaps,best_literals=record,last,gaps,#gaps,literals
      end
    end
  end
  return best,finish,captures
end
function lexicon.apply_phrase(record, records, first, last, options, captures)
  options = options or {}
  local value=record.value:match('^[^\\]*')
  local node=records[first]
  local readings=phrase_patterns.readings(value)
  if #readings>1 then
    local selected=1
    if options.phrase_reading ~= nil then
      assert(type(options.phrase_reading)=='function', 'phrase_reading must be a function')
      selected=options.phrase_reading(record.key,readings)
    end
    assert(type(selected)=='number' and readings[selected], 'invalid phrase reading selection')
    node.phrase_readings=readings
    value=readings[selected]
    value=value:match('^[A-Za-z]%.(W.*)$') or value
  end
  -- Two shipped entries omit/mistype a selector. Untagged text stays literal;
  -- the Cyrillic lookalike А in black board is an adjective selector.
  value=value:gsub('^W\x80','WA')
  if value:sub(1,1)=='W' and value:sub(2,2)~='~' and not value:sub(2,2):match('[A-Za-z#]') then
    value='Ww'..value:sub(2)
  end
  if captures and #captures>0 then
    local held,literals,rendered={},{},{}
    for _,capture in ipairs(captures) do for _,n in ipairs(capture) do held[n]=true end end
    for at=first,last do if not held[records[at]] then literals[#literals+1]=records[at] end end
    local template={}
    for k,v in pairs(node) do template[k]=v end
    local used=0
    local segments=phrase_patterns.segments(value)
    for segment,part in ipairs(segments) do
      if part~='' and part~='W' then
        if segment>1 then
          if part:sub(1,1)==' ' then part='Ww'..part:sub(2)
          elseif not part:sub(1,1):match('[A-Za-z#]') then part='Ww'..part
          elseif value:sub(1,1)=='W' then part='W'..part end
        end
        local pieces
        if used==0 then pieces=literals
        else
          local fresh={}
          for k,v in pairs(template) do fresh[k]=v end
          fresh.source,fresh.source_length,fresh.rules='',0,nil
          pieces={fresh}
        end
        lexicon.apply_phrase({value=part},pieces,1,#pieces,options)
        for _,n in ipairs(pieces) do rendered[#rendered+1]=n end
        used=used+1
      end
      if segment<#segments then
        for _,n in ipairs(captures[segment] or {}) do rendered[#rendered+1]=n end
      end
    end
    -- Only explicit output gaps reinsert captured words. Idioms such as
    -- "do your best" consume a possessive already expressed by their reading.
    for _=first,last do table.remove(records,first) end
    for at=#rendered,1,-1 do table.insert(records,first,rendered[at]) end
    return first
  end
  if value:find('~',1,true) then value=table.concat(phrase_patterns.segments(value)) end
  if value:sub(1,1)~='W' then
    local t=value:sub(1,1)
    node.previous_tag=t:upper():byte()
    if not (t:match('[VZ]') and nodes.tag(node):match('[EeGFh]')) then node.tag=t:byte() end
    if nodes.tag(node)=='V' and node.source:sub(-1)~="'" then node.number=0 end
    node.marker=0x77
    local source = {}
    for index=first,last do table.insert(source, records[index].source) end
    local macroSource = table.concat(source, ' ')
    -- Native phrase distribution prepares translated text before marking the
    -- reading as phrase-owned (77), so the metadata decoder leaves it alone.
    lexicon.decode_reading(node,value:sub(2),options,macroSource)
    for _=first+1,last do table.remove(records,first+1) end
    return first+1
  end
  local pos,tag=3,value:sub(2,2)
  local oldtag,number=nodes.tag(node),node.number or 0
  local index=first
  while index<=last or tag~='' do
    assert(tag~='' and tag:match('[A-Za-z#]'), 'invalid W phrase selector: '..tag)
    local stop=pos
    while stop<=#value and not value:sub(stop,stop):match(tag=='#' and '#' or '[A-Za-z ~#/]') do
      if value:sub(stop,stop)=='{' then stop=assert(value:find('}',stop,true),'unterminated phrase annotation') end
      stop=stop+1
    end
    local text=value:sub(pos,stop-1)
    local nexttag=value:sub(stop,stop)
    if tag=='#' and nexttag=='#' then stop=stop+1;nexttag=value:sub(stop,stop) end
    if nexttag==' ' then nexttag='w' end
    if index>last then
      local fresh=nodes.new(tag,{kind=0x57,marker=0x77,source='',lookup='',
        paradigm=0xFF,paradigm_high=0xFF,source_length=#text,source_position=0})
      for _, field in ipairs({'lookup_flags','lookup_paradigm','lookup_frame','dictionary_flags',
        'dictionary_frame','dictionary_paradigm','dictionary_case','number','tense','person',
        'aspect','case_mask','gender','verb_flags','governed_case','passive','short_form'}) do fresh[field]=0 end
      table.insert(records,index,fresh)
      last=index
    end
    local n=records[index]
    n.reading_state=2
    if tag=='n' then n.number=1;tag='N'
    elseif tag=='v' then n.person=3;tag='V'
    elseif tag=='N' then
      if text:match('^%d') then n.aspect=tonumber(text:sub(1,1));text=text:sub(2) end
      if number~=0 then n.number=1 end
    elseif tag=='V' or tag=='E' then
      if oldtag=='G' or oldtag=='E' then
        tag=oldtag;n.case_mask=8
        if nodes.tag(n)=='E' then n.tense=1 end
      elseif oldtag=='F' then tag='E';n.case_mask,n.tense,n.marker=8,1,0x6E
      elseif oldtag=='h' then n.case_mask,n.tense=8,1 end
    elseif tag=='h' then n.tense=1;tag='V'
    elseif tag=='F' then tag='E';n.tense,n.case_mask,n.marker=1,8,0x6E
    elseif tag=='e' and oldtag=='G' then tag=oldtag
    elseif tag=='X' then
      for _,at in ipairs({'tense','number','person'}) do
        if text:match('^%d') then n[layout.key(at)]=tonumber(text:sub(1,1));text=text:sub(2) end
      end
    end
    if text:match('^[=%%]') then
      n.marker = text:byte()
      text = macroText(n.source or '', text, options)
    end
    n.tag,n.previous_tag,n.reading=tag:byte(),tag:upper():byte(),text
    if not tag:match('[ANVvEhFebPCwX]') then
      lexicon.decode_reading(n,text,options)
      n.reading_state=2
    end
    if (n.marker or 0)==0 then n.marker=0x77 end
    tag,pos=nexttag,stop+1
    if tag=='' then
      for _=index+1,last do table.remove(records,index+1) end
      return index+1
    end
    index=index+1
  end
  return last+1
end

-- Lexical analyzer over CP866 strings and lossless dictionary data.
-- Literal and patterned phrases share reading distribution and ordinary records.

-- 0A4F:1603 attaches up to ten `word pattern*$action` records to a word node:
-- records whose first token matches the word and whose last star is followed
-- by `$`. Phrase-key matching is separate from these grammatical subrules.
function lexicon.sub_rules(dictionary,word)
  local rules={}
  for _,record in ipairs(dictionary.by_token[word:gsub('[A-Z]',string.lower)] or {}) do
    local line=record.raw:gsub('\r$','')
    local star=line:match('^.*()%*')
    if star and line:sub(star+1,star+1)=='$' and line:sub(#word+1,#word+1)==' ' then
      if #rules>=10 then break end
      rules[#rules+1]={pattern=line:sub(#word+2,star-1),action=line:sub(star+2)}
    end
  end
  return rules
end
local function boundary(tag, marker, position)
  return nodes.new(tag,{separator=marker or 0,kind=0x44,[0x09]=0,
    source_position=position or 0,source=tag,lookup='',reading='',previous_tag=0})
end

local function word(source, position)
  local fields={}
  for _, field in ipairs({'lookup_flags','lookup_paradigm','lookup_frame','dictionary_flags',
    'dictionary_frame','dictionary_paradigm','dictionary_case','number','tense','person',
    'aspect','case_mask','gender','verb_flags','governed_case','passive','short_form'}) do fields[field]=0 end
  fields.reading_state,fields.separator,fields.kind,fields.marker=0,0,0x57,0
  fields.source,fields.lookup,fields.reading,fields.previous_tag=source,'','',0
  fields.source_position,fields.source_length,fields.paradigm,fields.paradigm_high=position,#source,0xFF,0xFF
  local numeric=source:match('^[%d,]+$') ~= nil
  local tag=numeric and 'H' or source:match("^[A-Za-z'/-]+$") and '?' or '#'
  fields.counted_word=tag=='?'
  if tag=='#' then fields.person,fields.gender=3,1 end
  -- 0687:0892 preserves the original length but bounds the source copy.
  if #source>=0x28 then tag='#';fields.source=source:sub(1,0x50) end
  return nodes.new(tag,fields)
end

-- LTPRO DS:0930..09C0, in original order: ending, inserted word, kind,
-- selector. Selector 3 restricts 's to pronouns; 4 and 2 are whole words.
local contractions = {
	{ "let's", "us", "M", 4 },
	{ "'s", "is", "X", 3 },
	{ "n't", "not", "K", 0 },
	{ "'ll", "will", "X", 0 },
	{ "'d", "would", "X", 1 },
	{ "'m", "am", "T", 0 },
	{ "'re", "are", "T", 0 },
	{ "'ve", "have", "X", 0 },
	{ "cannot", "not", "K", 2 },
}
-- DS:09E4 pronouns and DS:0BD1..0BEE exceptions in 0A4F:047B.
local contractedIs = { i = true, you = true, he = true, she = true,
	it = true, we = true, they = true, there = true, here = true,
	what = true, that = true, who = true }
local negativeStems = { ca = "can", wo = "will", sha = "shall" }

local function contraction(source)
	local lower = source:lower()
	for _, row in ipairs(contractions) do
		local ending, inserted, kind, selector = table.unpack(row)
		local stem
		if selector == 4 or selector == 2 then
			if lower == ending then stem = source:sub(1, 3) end
		elseif #source > #ending and lower:sub(-#ending) == ending then
			stem = source:sub(1, -#ending - 1)
		end
		if stem and (selector ~= 3 or contractedIs[stem:lower()]) then
			-- Native negatives retain can's n and restore will/shall before
			-- inserting not (0A4F:063C..0706).
			if ending == "n't" then
				local irregular = negativeStems[stem:lower()]
				if irregular then
					stem = stem == stem:upper() and irregular:upper()
						or stem:sub(1, 1) .. irregular:sub(2)
				end
			end
			return stem, inserted, kind
		end
	end
end

-- Input splitting from 0687:1B93: whitespace separates chunks, leading and
-- trailing punctuation becomes boundary records. Internal hyphens stay in
-- the word until dictionary analysis has had a chance to recognize them.
function lexicon.tokenize(input)
  local records={boundary('*',0x2A)}
  local quoted=input:match("([.!?])['\"]%s*$")
  if quoted then input=input:gsub("['\"]%s*$",'') end
  local terminator=input:match('([.!?])%s*$')
  if terminator then
    -- A single-letter abbreviation retains its dot in the lexical token.
    if terminator~='.' or not input:match('^%a%.$') and not input:match('%s%a%.$') then
      input=input:gsub('[.!?]%s*$','')
    end
  end
  local words=0
  for _, item in ipairs(directives.chunks(input)) do
    local position,chunk=item.position,item.text
    if item.literal then
      local n=word(chunk,position-1)
      n.tag,n.counted_word,n.literal,n.source,n.source_length=0x23,false,chunk,chunk,#chunk
      n.literal_joined=item.joined
      if item.joined then n.separator=1 end
      records[#records+1]=n
    else
    local leading=false
    while chunk~='' and chunk:sub(1,1):match('[%p]') and not chunk:sub(1,1):match('[._?]') do
      local c=chunk:sub(1,1)
      if (c=='#' or c=='/') and chunk:sub(2,2):match('%a') then break end
      if c=='`' then c="'" end
      local n=boundary(c,(leading or item.joined) and 0 or 0x20,position-1)
      n.marker=0x20
      records[#records+1]=n;leading=true
      chunk=chunk:sub(2);position=position+1
    end
    if chunk~='' then
      local tail=''
      while chunk~='' do
        local c=chunk:sub(-1)
        if c=='.' or c=='_' or (c=="'" and chunk:sub(-2,-2):match('[sS]')) or not c:match('%p') then break end
        tail=c..tail;chunk=chunk:sub(1,-2)
      end
      if chunk~='' then
        local n=word(chunk,position-1)
        if item.joined then n.separator=1 end
        records[#records+1]=n
        if n.counted_word then
          words=words+1
          if words==1 then local _,caps=chunk:gsub('[A-Z]','');records[1][0x09]=caps end
        end
      end
      for c in tail:gmatch('.') do records[#records+1]=boundary(c,0) end
    end
    end
  end
  records[#records+1]=boundary('*',0x2A)
  return records,terminator and terminator:byte() or 0x0A,words
end

local function decode(dictionary,records,index,options)
  local node=records[index]
  local source=node.source
	while true do
		local stem, inserted, kind = contraction(source)
		if not stem then break end
		source = stem
		node.source, node.source_length = source, #source
		local fresh = word(inserted, 0)
		fresh.reading_state, fresh.tag, fresh.previous_tag = 1, kind:byte(), kind:byte()
		if kind == "X" then fresh.marker = 0x27 end
		table.insert(records, index + 1, fresh)
	end
  local entry,resolved=resolve(dictionary,source,options)
  if resolved~=source then
    source=resolved
    node.source, node.source_length = source, #source
  end
  local value,backref
  if entry then
    value=entry.value
    local initial=value:sub(1,1)
    node.reading_state,node.tag,node.previous_tag=initial=='#' and 0 or 1,initial:byte(),initial:upper():byte()
    backref=value:match('\\(.*)')
    if backref then node.lookup=backref..' ' end
  end
  local derived, lookup_error
  if not value then
    derived, lookup_error=lexicon.lookup(dictionary,source,options)
    if not derived and options.prefixes then
      derived, node.derivation_prefix=prefixes.lookup(options.prefixes,source,function(stem)
        return lexicon.lookup(dictionary,stem,options)
      end)
    end
    if derived and derived.record then
      value=derived.record.value
      node.reading_state,node.tag,node.previous_tag=1,derived.tag:byte(),value:sub(1,1):upper():byte()
      for at,v in pairs(derived.fields) do node[layout.key(at)]=v end
      if derived.native_selector=='Z13' and derived.tag=='V' then node.number=0 end
      node.lookup=derived.candidate
    elseif not lookup_error then
      local compound=derivational_compound(dictionary,source,options)
      local surface=compound and {tag='N',fields={number=0,case_mask=0}}
        or not source:find('[-/]') and lexicon.surface_noun(source)
      if surface then
        -- Unknown derivational nouns keep their surface spelling. Bare
        -- endings in compounds follow the same Lua policy without splitting.
        node.reading_state,node.tag=1,surface.tag:byte()
        node.person,node.gender=3,1
        for at,v in pairs(surface.fields) do node[layout.key(at)]=v end
        node.surface_compound=compound
      end
    end
  end
  local phrase,last,captures=lexicon.match_phrase(dictionary,records,index,source:lower())
  -- Subrules are collected while scanning possible following words, even
  -- when a literal phrase later wins. At a terminal boundary no scan occurs.
  if records[index+1] and records[index+1].separator~=0x2A then
    local rules=lexicon.sub_rules(dictionary,source)
    local base=backref or (derived and derived.candidate)
    if base and not phrase then
      for _,rule in ipairs(lexicon.sub_rules(dictionary,base)) do
        if #rules<10 then rules[#rules+1]=rule end
      end
    end
    if #rules>0 then node.rules=rules end
  end
  local phrase_base=backref or (derived and derived.candidate)
  if not phrase and phrase_base then phrase,last,captures=lexicon.match_phrase(dictionary,records,index,phrase_base:lower()) end
  if phrase then
    if value then
      -- A phrase can replace an auxiliary with a lexical verb. Decode its
      -- tense/person metadata first (did = X1), retaining the original tag
      -- that phrase distribution uses for participles and other conversions.
      local context={}
      for key,item in pairs(node) do context[key]=item end
      lexicon.decode_reading(context,value:sub(2):match('^[^\\]*'),options)
      for _,field in ipairs({'tense','number','person','aspect','gender','case_mask',
          'verb_flags','governed_case','passive','short_form','lookup_flags','lookup_frame'}) do
        node[field]=context[field]
      end
    end
    return lexicon.apply_phrase(phrase,records,index,last,options,captures)
  end
  -- 10AD3 skips the phrase scan at a sentence boundary. A failed scan at
  -- 10D36 clears the temporary backreference search string otherwise.
  if not derived and records[index+1] and records[index+1].separator~=0x2A then node.lookup='' end
  if not value and not node.surface_compound then
    local left,separator,right=source:match('^([^/-]+)([/-])(.+)$')
    if left then
      local attempt=lexicon.attempt_fields(source)
      for at,v in pairs(attempt and attempt.fields or {}) do node[layout.key(at)]=v end
      node.source,node.source_length=left,#left
      local delimiter=boundary(separator,0);delimiter.marker=0x2F
      if separator=='/' then node.marker=0x2F end
      table.insert(records,index+1,delimiter)
      table.insert(records,index+2,word(right,0))
      return index
    end
  end
  if value then
    lexicon.decode_reading(node,value:sub(2):match('^[^\\]*'),options)

  elseif nodes.tag(node)=='?' or nodes.tag(node)=='#' then node.person,node.gender=3,1 end
  return index+1
end

function lexicon.analyze(dictionary,input,options)
  options = options or {}
  local records,terminator,word_count=lexicon.tokenize(input)
  local i=1
  while i<=#records do
    if records[i].kind==0x57 and not records[i].literal and (nodes.tag(records[i])=='?' or records[i].reading_state==1) then
      i=decode(dictionary,records,i,options)
    else i=i+1 end
  end
  assert(#records<=512,'native lexical vector limit exceeded')
  local root=nodes.link(records)
  local vector,count,state=nodes.rebuild(root)
  return {root=root,vector=vector,count=count,tags=state.tags,terminator=terminator,word_count=word_count}
end

return lexicon
