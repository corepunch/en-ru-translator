-- Initial exact-dictionary lexical slice. This explicit development API accepts
-- simple ASCII word sequences with a terminal period. Other analyzer branches
-- fail visibly until their native callers are recovered; there is no legacy path.
local nodes=require 'core.ltpro.nodes'
local readings=require 'core.ltpro.readings'
local lexical={}
-- 0A4F:1603 attaches up to ten `word pattern*$action` records to a word node:
-- records whose first token matches the word and whose last star is followed
-- by `$`. Multi-word phrase matching, which precedes that test natively, is
-- not ported; a sub-rule pattern that starts with the next source word is
-- therefore not distinguished here.
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
local function boundary(first)
  return nodes.new('*',{[0x0D]=0x2A,[0x0E]=0x44,[0x09]=first and 1 or 0,
    [0x12]='*',[0x9C]='',[0x11C]='',[0x66]=0})
end
function lexical.analyze(dictionary,input)
  assert(input:match('^[A-Za-z ]+%.$'), 'native lexical slice requires words and a terminal period')
  local records={boundary(true)}
  for position,source in input:gmatch('()([A-Za-z]+)') do
    local matches=dictionary.by_key[source:lower()]
    assert(matches and #matches==1, 'native exact lookup requires one unique record: '..source)
    local value=matches[1].value
    local initial=value:sub(1,1)
    assert(initial~='W' and not value:find('[{}=%%]'), 'native complex dictionary reading is not ported: '..source)
    local payload=value:sub(2):match('^[^\\]*')
    assert(not payload:find('%.',1), 'native annotated dictionary reading is not ported: '..source)
    local fields={}
    for at=0x68,0x7B do fields[at]=0 end
    fields[0x0B],fields[0x0E],fields[0x0F]=1,0x57,0
    fields[0x12],fields[0x9C],fields[0x66]=source,'',initial:upper():byte()
    fields[0x10],fields[0x87],fields[0x85],fields[0x86]=position-1,#source,0xFF,0xFF
    local node=nodes.new(initial,fields)
    readings.decode(node,payload)
    local sub_rules=lexical.sub_rules(dictionary,source)
    if #sub_rules>0 then node.rules=sub_rules end
    records[#records+1]=node
  end
  records[#records+1]=boundary(false)
  local root=nodes.link(records)
  local vector,count=nodes.vector(root)
  local cache={}
  for i=0,count-1 do cache[#cache+1]=nodes.tag(vector[i]) end
  return {root=root,vector=vector,count=count,tags=table.concat(cache)}
end
return lexical
