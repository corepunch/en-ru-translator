-- Development lexical analyzer over CP866 strings and lossless dictionary data.
-- Ports literal lookup, phrase readings and a bounded tokenizer; unsupported
-- dictionary macro/expansion branches fail explicitly. No legacy fallback.
local nodes=require 'core.ltpro.nodes'
local readings=require 'core.ltpro.readings'
local phrases=require 'core.ltpro.phrases'
local suffixes=require 'core.ltpro.suffixes'
local lexical={}
-- 0A4F:1603 attaches up to ten `word pattern*$action` records to a word node:
-- records whose first token matches the word and whose last star is followed
-- by `$`. Literal phrase keys are handled separately; pattern-key phrase
-- matching and its interaction with these subrules remain outside this slice.
function lexical.sub_rules(dictionary,word)
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

-- Input splitting from 0687:1B93: whitespace separates chunks, leading and
-- trailing punctuation becomes boundary records. Internal hyphens stay in
-- the word until dictionary analysis has had a chance to recognize them.
function lexical.tokenize(input)
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

local function decode(dictionary,records,index)
  local node=records[index]
  local source=node[0x12]
  -- 0A4F:047B, DS:09C0: the literal `cannot` ending has selector 2,
  -- forcing a three-byte stem and inserting a fresh `not` record.
  if source:lower()=='cannot' then
    source=source:sub(1,3)
    node[0x12],node[0x87]=source,3
    table.insert(records,index+1,word('not',0))
  end
  local matches=dictionary.by_key[source:lower()]
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
    derived=suffixes.lookup(dictionary,source)
    if derived then
      value=derived.record.value
      node[0x0B],node[0x0C],node[0x66]=1,derived.tag:byte(),value:sub(1,1):upper():byte()
      for at,v in pairs(derived.fields) do node[at]=v end
      if derived.native_selector=='Z13' and derived.tag=='V' then node[0x72]=0 end
      node[0x9C]=derived.candidate
    end
  end
  local phrase,last=phrases.match(dictionary,records,index,source:lower())
  -- Subrules are collected while scanning possible following words, even
  -- when a literal phrase later wins. At a terminal boundary no scan occurs.
  if records[index+1] and records[index+1][0x0D]~=0x2A then
    local rules=lexical.sub_rules(dictionary,source)
    local base=backref or (derived and derived.candidate)
    if base and not phrase then
      for _,rule in ipairs(lexical.sub_rules(dictionary,base)) do
        if #rules<10 then rules[#rules+1]=rule end
      end
    end
    if #rules>0 then node.rules=rules end
  end
  if not phrase and backref then phrase,last=phrases.match(dictionary,records,index,backref:lower()) end
  if phrase then return phrases.apply(phrase,records,index,last) end
  -- 10AD3 skips the phrase scan at a sentence boundary. A failed scan at
  -- 10D36 clears the temporary backreference search string otherwise.
  if not derived and records[index+1] and records[index+1][0x0D]~=0x2A then node[0x9C]='' end
  if not value then
    local left,separator,right=source:match('^([^/-]+)([/-])(.+)$')
    if left then
      local attempt=suffixes.attempt_fields(source)
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
    assert(value:sub(1,1)~='W','native W word expansion is not ported: '..source)
    readings.decode(node,value:sub(2):match('^[^\\]*'))

  elseif nodes.tag(node)=='?' or nodes.tag(node)=='#' then node[0x74],node[0x77]=3,1 end
  return index+1
end

function lexical.analyze(dictionary,input)
  local records,terminator,word_count=lexical.tokenize(input)
  local i=1
  while i<=#records do
    if records[i][0x0E]==0x57 and (nodes.tag(records[i])=='?' or records[i][0x0B]==1) then
      i=decode(dictionary,records,i)
    else i=i+1 end
  end
  assert(#records<=512,'native lexical vector limit exceeded')
  local root=nodes.link(records)
  local vector,count=nodes.vector(root)
  local cache={}
  for i=0,count-1 do cache[#cache+1]=nodes.tag(vector[i]) end
  return {root=root,vector=vector,count=count,tags=table.concat(cache),terminator=terminator,word_count=word_count}
end
return lexical
