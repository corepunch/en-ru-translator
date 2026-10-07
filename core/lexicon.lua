local nodes = require 'core.nodes'
local transliteration = require 'core.transliteration'
local text = require 'core.text'

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
-- This module only resolves candidates for rows whose transforms are directly
-- visible in the native dispatch. Phrase and annotation handling stays with
-- the lexical analyzer.
-- Native row order matters. For example, `ies` precedes `es` and `s`, and
-- `ed` follows `ied`. The ASCII strings and selectors were read from DS:0778.
local rows = {
  { "ies'", "N12", "unsupported" },
  { "es'", "N12", "unsupported" },
  { "s'", "N12", "unsupported" },
  { "'s", "N02", "unsupported" },
  { "ing", "G8", "ing" },
  { "ied", "E", "ied" },
  { "ed", "E", "ed" },
  { "ness", "N00", "unsupported" },
  { "ous", "A", "unsupported" },
  { "less", "A", "unsupported" },
  { "ies", "Z13", "ies" },
  { "es", "Z13", "es" },
  { "s", "Z13", "s" },
  { "fy", "V", "unsupported" },
  { "ment", "N00", "unsupported" },
  { "ion", "N00", "unsupported" },
  { "ence", "N00", "unsupported" },
  { "ance", "N00", "unsupported" },
  { "enc", "N00", "unsupported" },
  { "anc", "N00", "unsupported" },
  { "ity", "N00", "unsupported" },
  { "age", "N00", "unsupported" },
  { "ure", "N00", "unsupported" },
  { "ag", "N00", "unsupported" },
  { "nes", "N00", "unsupported" },
  { "or", "N00", "unsupported" },
  { "iest", "A", "unsupported" },
  { "ier", "A", "unsupported" },
  { "est", "A", "unsupported" },
  { "eur", "A", "unsupported" },
  { "er", "A", "unsupported" },
  { "ur", "N00", "unsupported" },
  { "ly", "D", "ly" },
  { "ical", "A", "unsupported" },
  { "ic", "A", "unsupported" },
  { "ible", "A", "unsupported" },
  { "able", "A", "unsupported" },
  { "ibl", "A", "unsupported" },
  { "abl", "A", "unsupported" },
  { "ory", "A", "unsupported" },
  { "ary", "A", "unsupported" },
  { "ou", "A", "unsupported" },
  { "les", "A", "unsupported" },
}
for _, row in ipairs(rows) do
  row.ending, row.selector, row.transform = row[1], row[2], row[3]
end

local function ascii_lower(text)
  return (text:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

local function lookup(dictionary, key)
  local records = dictionary.by_key[ascii_lower(key)]
  if not records then return nil end
  if #records ~= 1 then return nil, "duplicate dictionary key: " .. key end
  return records[1]
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

  local fields = {}
  if row and row.selector == "Z13" then
    fields[0x72], fields[0x74] = 1, 3
  elseif row and row.selector == "G8" then
    fields[0x76] = 8
  elseif row and row.selector == "E" then
    fields[0x73], fields[0x76] = 1, 8
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
function lexicon.lookup(dictionary, source)
  assert(type(source) == "string" and source ~= "", "suffix lookup needs a source word")
  local word = ascii_lower(source)
  local exact, exact_error = lookup(dictionary, word)
  if exact then return decode_record(exact, source, word, nil, true) end
  if exact_error then return nil, exact_error end

  for _, row in ipairs(rows) do
    if #word > #row.ending and word:sub(-#row.ending) == row.ending then
      if row.transform == "unsupported" then
        return nil, "native suffix row " .. row.ending .. "/" .. row.selector .. " is not ported"
      else
        for _, candidate in ipairs(candidates(word, row)) do
          local record, err = lookup(dictionary, candidate)
          if err then return nil, err end
          if record then
            return decode_record(record, source, candidate, row, false)
          end
        end
        -- 0A4F:07F2 stops at the first table row whose ending matches. Do not
        -- fall through to a shorter ending when its candidate misses.
        return nil, "native suffix candidate missed: " .. row.ending
      end
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
        fields[0x0F] = 0x61
        local last, before_last = word:sub(-1), word:sub(-2, -2)
        if last == "r" and (before_last == "e" or before_last == "u") then
          fields[0x73] = 1
        elseif word:sub(-2) == "st" then
          fields[0x73] = 2
        end
      end
      return { ending = row.ending, selector = row.selector, fields = fields }
    end
  end
  return nil
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
		node[0x11C] = value
		if ordinaryReadings then node[0x0B] = 3 end
		return
	end
	-- Native phrase macros retain the joined source for output capitalization.
	if macroSource then node[0x12] = macroSource end
	if macroSource or node[0x0F] ~= 0x77 then node[0x11C] = macroText(macroSource or node[0x12] or "", value, options, node[0x11C]) end
	if #value > 1 or options.transliterate ~= false or marker == "%" then
		node[0x0B] = 3
		if marker == "%" then node[0x0F] = 0x25 end
	end
	if marker == "=" then node[0x0F] = 0x3D end
end

function lexicon.decode_reading(node, payload, options, macroSource)
  options = options or {}
  local p=1
  local function digit(at)
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then node[at]=b-48; p=p+1; return true end
    return false
  end
  local function paradigm(at)
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then
      local value=b-48
      node[at]=((node[at] or 0)&0x80)|value|((value&1)<<6)
      p=p+1
    end
  end
  local function aspect()
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then
      node[0x6A]=((node[0x6A] or 0)&0xBF)|(((b-48)&1)<<6)
      p=p+1
    end
  end
  local t=tag(node)
  if t=='#' then
    if payload:sub(p,p)=='#' then p=p+1 end
    local saved=node[0x72] or 0
    if digit(0x72) and saved~=0 then node[0x72]=saved end
    if not digit(0x77) then
      local gender=({[0xAC]=1,[0xA6]=2,[0xE1]=0})[payload:byte(p)]
      if gender~=nil then node[0x77]=gender;p=p+1 end
    end
    node[0x74]=3
    local text=payload:sub(p)
    writeReading(node, text, options, false, macroSource)
    return p-1
  elseif has('XYx',t) then
    digit(0x73);digit(0x72);digit(0x74)
    if t=='Y' then node[0x76]=8 end
  elseif t=='y' then digit(0x75);node[0x76]=2
  elseif t=='d' then digit(0x75);digit(0x73)
  elseif has('MRr',t) then
    digit(0x72);digit(0x74);digit(0x77)
    if t=='M' then node[0x76]=2 end
  elseif has('OS',t) then digit(0x72);digit(0x75);digit(0x77);node[0x74]=3
  elseif has('PQfp',t) then
    local b=payload:byte(p)
    if b and b>0x81 and b<0x93 then
      if cases[b] then node[0x76]=cases[b] end
      p=p+1
    end
  elseif t=='I' then digit(0x72)
  elseif t=='U' then
    digit(0x73);digit(0x78);node[0x76],node[0x74]=8,3
  elseif t=='J' then digit(0x73);digit(0x75)
  elseif t=='N' then digit(0x75)
  elseif t=='n' then digit(0x75);node[0x72]=1
  elseif t=='a' then node[0x0F]=0x61
  elseif t=='v' then paradigm(0x68);aspect();node[0x74],node[0x76]=3,8
  elseif t=='z' then paradigm(0x68);aspect();node[0x72],node[0x74],node[0x76]=1,3,8
  elseif has('eEFGVZh',t) then
    if t=='e' and node[0x0B]==1 and node[0x74]==3 then
      node[0x0C],node[0x66]=0x56,0x56
    end
    paradigm(0x68);aspect()
    local b=payload:byte(p)
    if b and b>=48 and b<=57 then
      node[0x6A]=((node[0x6A] or 0)&0xC0)|((b-48)&0x3F);p=p+1
    end
    node[0x76]=8
    t=tag(node)
    if has('EehF',t) or node[0x66]==0x45 then node[0x73]=1 end
    if t=='h' then node[0x0C],node[0x66]=0x56,0x56
    else
      b=payload:byte(p)
      if t=='E' and ((node[0x6A] or 0)&0x3F)==1 and b and b>0x81 and b<0x93 then
        if cases[b] then node[0x79]=cases[b] end
        p=p+1
      end
      if t=='F' then node[0x0F],node[0x0C]=0x6E,0x45 end
    end
  end
  t=tag(node)
  if not has('ekxjtudbiplyfgac',t) then node[0x0C]=t:upper():byte() end
  local text=payload:sub(p)
  writeReading(node, text, options, true, macroSource)
  return p-1
end

-- Literal-key branch of 0A4F:1713 and reading distribution in 0A4F:18F8.
-- Pattern keys and record insertion markers require separate ports.

function lexicon.match_phrase(dictionary, records, index, key)
  local best,finish
  for _,record in ipairs(dictionary.by_token[key] or {}) do
    if record.key:find(' ',1,true) and record.key:match("^[A-Za-z '-]+$") then
      local words={}
      for w in record.key:gmatch('%S+') do words[#words+1]=w:lower() end
      local matched=words[1]==key
      for j=2,#words do
        local n=records[index+j-1]
        if not n or n[0x0E]~=0x57 or n[0x12]:lower()~=words[j] then matched=false;break end
      end
      if matched and record.value:sub(1,1)~='$' and (not finish or index+#words-1>finish) then
        best,finish=record,index+#words-1
      end
    end
  end
  return best,finish
end
function lexicon.apply_phrase(record, records, first, last, options)
  options = options or {}
  local value=record.value:match('^[^\\]*')
  local node=records[first]
  if value:sub(1,1)~='W' then
    local t=value:sub(1,1)
    node[0x66]=t:upper():byte()
    if not (t:match('[VZ]') and nodes.tag(node):match('[EeGFh]')) then node[0x0C]=t:byte() end
    if nodes.tag(node)=='V' and node[0x12]:sub(-1)~="'" then node[0x72]=0 end
    node[0x0F]=0x77
    local source = {}
    for index=first,last do table.insert(source, records[index][0x12]) end
    local macroSource = table.concat(source, ' ')
    -- Native phrase distribution prepares translated text before marking the
    -- reading as phrase-owned (77), so the metadata decoder leaves it alone.
    lexicon.decode_reading(node,value:sub(2),options,macroSource)
    for _=first+1,last do table.remove(records,first+1) end
    return first+1
  end
  local pos,tag=3,value:sub(2,2)
  local oldtag,number=nodes.tag(node),node[0x72] or 0
  local index=first
  while index<=last or tag~='' do
    assert(tag~='' and tag:match('[ANnVvEhFebPCwX]'), 'native W phrase selector is not ported: '..tag)
    local stop=pos
    while stop<=#value and not value:sub(stop,stop):match('[A-Za-z ~#/;]') do
      if value:sub(stop,stop)=='{' then stop=assert(value:find('}',stop,true),'unterminated phrase annotation') end
      stop=stop+1
    end
    local text=value:sub(pos,stop-1)
    local nexttag=value:sub(stop,stop)
    if nexttag==' ' then nexttag='w' end
    if index>last then
      local fresh=nodes.new(tag,{[0x0E]=0x57,[0x0F]=0x77,[0x12]='',[0x9C]='',
        [0x85]=0xFF,[0x86]=0xFF,[0x87]=#text,[0x10]=0})
      for at=0x68,0x7B do fresh[at]=0 end
      table.insert(records,index,fresh)
      last=index
    end
    local n=records[index]
    n[0x0B]=2
    if tag=='n' then n[0x72]=1;tag='N'
    elseif tag=='v' then n[0x74]=3;tag='V'
    elseif tag=='N' then
      if text:match('^%d') then n[0x75]=tonumber(text:sub(1,1));text=text:sub(2) end
      if number~=0 then n[0x72]=1 end
    elseif tag=='V' or tag=='E' then
      if oldtag=='G' or oldtag=='E' then
        tag=oldtag;n[0x76]=8
        if nodes.tag(n)=='E' then n[0x73]=1 end
      elseif oldtag=='F' then tag='E';n[0x76],n[0x73],n[0x0F]=8,1,0x6E
      elseif oldtag=='h' then n[0x76],n[0x73]=8,1 end
    elseif tag=='h' then n[0x73]=1;tag='V'
    elseif tag=='F' then tag='E';n[0x73],n[0x76],n[0x0F]=1,8,0x6E
    elseif tag=='e' and oldtag=='G' then tag=oldtag
    elseif tag=='X' then
      for _,at in ipairs({0x73,0x72,0x74}) do
        if text:match('^%d') then n[at]=tonumber(text:sub(1,1));text=text:sub(2) end
      end
    end
    if text:match('^[=%%]') then
      n[0x0F] = text:byte()
      text = macroText(n[0x12] or '', text, options)
    end
    n[0x0C],n[0x66],n[0x11C]=tag:byte(),tag:upper():byte(),text
    if (n[0x0F] or 0)==0 then n[0x0F]=0x77 end
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
-- Ports literal lookup, phrase readings, macros and a bounded tokenizer;
-- unsupported pattern and suffix branches fail explicitly.

-- 0A4F:1603 attaches up to ten `word pattern*$action` records to a word node:
-- records whose first token matches the word and whose last star is followed
-- by `$`. Literal phrase keys are handled separately; pattern-key phrase
-- matching and its interaction with these subrules remain outside this slice.
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
  return nodes.new(tag,{[0x0D]=marker or 0,[0x0E]=0x44,[0x09]=0,
    [0x10]=position or 0,[0x12]=tag,[0x9C]='',[0x11C]='',[0x66]=0})
end

local function word(source, position)
  local fields={}
  for at=0x68,0x7B do fields[at]=0 end
  fields[0x0B],fields[0x0D],fields[0x0E],fields[0x0F]=0,0,0x57,0
  fields[0x12],fields[0x9C],fields[0x11C],fields[0x66]=source,'','',0
  fields[0x10],fields[0x87],fields[0x85],fields[0x86]=position,#source,0xFF,0xFF
  local numeric=source:match('^[%d,]+$') ~= nil
  local tag=numeric and 'H' or source:match("^[A-Za-z'-]+$") and '?' or '#'
  fields.counted_word=tag=='?'
  if tag=='#' then fields[0x74],fields[0x77]=3,1 end
  -- 0687:0892 preserves the original length but bounds the source copy.
  if #source>=0x28 then tag='#';fields[0x12]=source:sub(1,0x50) end
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
  assert(not input:find('[{}]'), 'native inline input directives are not ported')
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
  for position,chunk in input:gmatch('()([^%s]+)') do
    local leading=false
    while chunk~='' and chunk:sub(1,1):match('[%p]') and not chunk:sub(1,1):match('[._?]') do
      local c=chunk:sub(1,1)
      if (c=='#' or c=='/') and chunk:sub(2,2):match('%a') then break end
      if c=='`' then c="'" end
      local n=boundary(c,leading and 0 or 0x20,position-1)
      n[0x0F]=0x20
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
        records[#records+1]=n
        if n.counted_word then
          words=words+1
          if words==1 then local _,caps=chunk:gsub('[A-Z]','');records[1][0x09]=caps end
        end
      end
      for c in tail:gmatch('.') do records[#records+1]=boundary(c,0) end
    end
  end
  records[#records+1]=boundary('*',0x2A)
  return records,terminator and terminator:byte() or 0x0A,words
end

local function decode(dictionary,records,index,options)
  local node=records[index]
  local source=node[0x12]
	while true do
		local stem, inserted, kind = contraction(source)
		if not stem then break end
		source = stem
		node[0x12], node[0x87] = source, #source
		local fresh = word(inserted, 0)
		fresh[0x0B], fresh[0x0C], fresh[0x66] = 1, kind:byte(), kind:byte()
		if kind == "X" then fresh[0x0F] = 0x27 end
		table.insert(records, index + 1, fresh)
	end
  local matches=dictionary.by_key[source:lower()]
  local aliases = {}
  while matches and #matches == 1 and matches[1].value:sub(1,1) == '=' do
    assert(not aliases[source:lower()], 'cyclic dictionary redirect: '..source)
    aliases[source:lower()] = true
    source = matches[1].value:sub(2)
    node[0x12], node[0x87] = source, #source
    matches = dictionary.by_key[source:lower()]
  end
  local value,backref
  if matches then
    assert(#matches==1,'native duplicate lookup is not ported: '..source)
    value=matches[1].value
    local initial=value:sub(1,1)
    node[0x0B],node[0x0C],node[0x66]=initial=='#' and 0 or 1,initial:byte(),initial:upper():byte()
    backref=value:match('\\(.*)')
    if backref then node[0x9C]=backref..' ' end
  end
  local derived
  if not value then
    derived=lexicon.lookup(dictionary,source)
    if derived then
      value=derived.record.value
      node[0x0B],node[0x0C],node[0x66]=1,derived.tag:byte(),value:sub(1,1):upper():byte()
      for at,v in pairs(derived.fields) do node[at]=v end
      if derived.native_selector=='Z13' and derived.tag=='V' then node[0x72]=0 end
      node[0x9C]=derived.candidate
    end
  end
  local phrase,last=lexicon.match_phrase(dictionary,records,index,source:lower())
  -- Subrules are collected while scanning possible following words, even
  -- when a literal phrase later wins. At a terminal boundary no scan occurs.
  if records[index+1] and records[index+1][0x0D]~=0x2A then
    local rules=lexicon.sub_rules(dictionary,source)
    local base=backref or (derived and derived.candidate)
    if base and not phrase then
      for _,rule in ipairs(lexicon.sub_rules(dictionary,base)) do
        if #rules<10 then rules[#rules+1]=rule end
      end
    end
    if #rules>0 then node.rules=rules end
  end
  if not phrase and backref then phrase,last=lexicon.match_phrase(dictionary,records,index,backref:lower()) end
  if phrase then return lexicon.apply_phrase(phrase,records,index,last,options) end
  -- 10AD3 skips the phrase scan at a sentence boundary. A failed scan at
  -- 10D36 clears the temporary backreference search string otherwise.
  if not derived and records[index+1] and records[index+1][0x0D]~=0x2A then node[0x9C]='' end
  if not value then
    local left,separator,right=source:match('^([^/-]+)([/-])(.+)$')
    if left then
      local attempt=lexicon.attempt_fields(source)
      for at,v in pairs(attempt and attempt.fields or {}) do node[at]=v end
      node[0x12],node[0x87]=left,#left
      local delimiter=boundary(separator,0);delimiter[0x0F]=0x2F
      if separator=='/' then node[0x0F]=0x2F end
      table.insert(records,index+1,delimiter)
      table.insert(records,index+2,word(right,0))
      return index
    end
  end
  if value then
    lexicon.decode_reading(node,value:sub(2):match('^[^\\]*'),options)

  elseif nodes.tag(node)=='?' or nodes.tag(node)=='#' then node[0x74],node[0x77]=3,1 end
  return index+1
end

function lexicon.analyze(dictionary,input,options)
  options = options or {}
  local records,terminator,word_count=lexicon.tokenize(input)
  local i=1
  while i<=#records do
    if records[i][0x0E]==0x57 and (nodes.tag(records[i])=='?' or records[i][0x0B]==1) then
      i=decode(dictionary,records,i,options)
    else i=i+1 end
  end
  assert(#records<=512,'native lexical vector limit exceeded')
  local root=nodes.link(records)
  local vector,count,state=nodes.rebuild(root)
  return {root=root,vector=vector,count=count,tags=state.tags,terminator=terminator,word_count=word_count}
end

return lexicon
