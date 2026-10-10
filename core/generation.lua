local text = require 'core.text'
local nodes = require 'core.nodes'
local russian = require 'core.russian'
local encoding = require 'core.encoding'
local generation = {}
local function signed(n) n=n & 0xFFFF; return n >= 0x8000 and n-0x10000 or n end
local function reflexive(a, word, length)
  local suffixes=a:list('reflexive')
  return length > 2 and (text.ends(word,suffixes[0],length) or text.ends(word,suffixes[1],length))
end
local function slot(value,index)
  local i=1
  for _=1,math.max(0,index) do
    local space=value:find(' ',i,true)
    if not space then return nil end
    i=space+1
  end
  local finish=value:find(' ',i,true)
  return value:sub(i,finish and finish-1 or #value), finish ~= nil
end
local function build(a,id,word,length,table_name,index)
  local trim,endings=a:paradigm(table_name,id)
  local cut=signed(length-trim)
  local ending,followed=slot(endings,index)
  if not ending or ending:sub(1,1)=='-' then return nil end
  local result=cut > 0 and word:sub(1,cut) or word
  if ending:sub(1,1)~='=' then
    if cut==0 then result='' end
    result=result..ending
    -- A followed ending is limited by the original stem-length argument.
    if followed then result=result:sub(1,length+#ending) end
  end
  return result
end
function generation.noun_form(state,id,word,gender,plural,case)
  return build(state.assets,id,word,#word,gender==0 and 'noun-n' or gender==2 and 'noun-f' or 'noun-m',
    signed(case+(plural~=0 and 6 or 0))-1)
end
function generation.adjective_form(state,id,word,gender,plural,case)
  local a=state.assets
  local refl=id~=14 and reflexive(a,word,#word)
  local result=build(a,id,word,#word-(refl and 2 or 0),gender==0 and 'adjective-n' or gender==2 and 'adjective-f' or 'adjective-m',
    signed(case+(plural~=0 and 6 or 0)))
  return result and result..(refl and a:list('reflexive')[0] or '')
end
function generation.verb_form(state,id,word,aspect,flags,person,plural,past,gender)
  local a,index=state.assets
  if flags & 4 ~= 0 then index,past=6,0
  elseif past==1 then index=7
  elseif person==0 then return word
  else index=signed(person-1+(plural~=0 and 3 or 0)) end
  local refl=reflexive(a,word,#word)
  local result=build(a,id,word,#word-(refl and 2 or 0),aspect==1 and 'verb-perfective' or 'verb-imperfective',index)
  if not result then return nil end
  local function cat(at) result=result..a:string(at) end
  if past==1 then
    local n=#result
    if (gender~=1 or plural~=0) and (text.ends(result,a:string('chel')) or text.ends(result,a:string('shel'))) then
      result=result:sub(1,n-2)..result:sub(n)
    elseif text.ends(result,a:string('kl')) then result=result:sub(1,-2) end
    if result:byte(-1)~=0xAB and (gender~=1 or plural==1) then cat('l') end
    if plural~=0 then cat('i') elseif gender==2 then cat('a') elseif gender==0 then cat('o') end
  end
  if refl then
    result=result..a:list('reflexive')[(index==0 or index==4 or index==6 or (past==1 and (gender~=1 or plural~=0))) and 1 or 0]
  end
  if past==1 and flags & 2 ~= 0 then cat('by') end
  if flags & 16 ~= 0 then cat('li') end
  return result
end
function generation.participle_form(state,id,word,aspect,tag,passive,past)
  local a=state.assets
  -- A perfective participle of an imperfective reading (defined -> определять)
  -- is built from the partner and its own paradigm (определить, 42), as the
  -- imperfective paradigm number means something else in the perfective table.
  if aspect==1 then
    local record=russian.verb_record(state,word)
    if record and not record.perfective and record.partner then
      local partner=russian.verb_record(state,record.partner)
      if partner then word,id=record.partner,partner.paradigm end
    end
  end
  local index=tag==0x47 and 8 or past==1 and (passive~=0 and 12 or 11) or (passive~=0 and 10 or 9)
  local refl=passive==0 and reflexive(a,word,#word)
  local result=build(a,id,word,#word-(refl and 2 or 0),aspect==1 and 'verb-perfective' or 'verb-imperfective',index)
  if not result then return nil end
  if refl then
    if index==8 and aspect~=0 then result=result..a:string('shi') end
    result=result..a:list('reflexive')[index==8 and 1 or 0]
  end
  return result
end
function generation.pronoun_form(state,word,person,gender,plural,case,prefix)
  local a,index,cut=state.assets,nil,#word
  -- Rows: я ты он оно она мы вы они, then кто что себя found by the word's end.
  local pronouns,cases=a:list('pronouns'),a:list('pronoun_cases')
  local first=word:byte() or 0
  if person==0 or first==0xAD or first==0xAA or first==0xE7 or person>3 then
    index=8
    while pronouns[index] do
      local ending=pronouns[index]
      if text.ends(word,ending) then cut=#ending; break end
      index=index+1
    end
    if not pronouns[index] then return nil end
  elseif person==1 then index=plural==1 and 5 or 0
  elseif person==2 then index=plural==1 and 6 or 1
  else index=plural==1 and 7 or gender==2 and 4 or 2 end
  if case==0 then return word end
  local result=word:sub(1,#word-cut)
  if case~=5 and prefix~=0 and (index==2 or index==3 or index==4 or index==7) then result=a:string('n') end
  local ending=slot(cases[index],signed(case)-1)
  return ending and result..ending
end

local NUMERAL_ENDINGS = {
  {'etot', 13}, {'kakoy', 6}, {'tot', 16}, {'yy', 0},
  {'ves', 14}, {'vash', 10}, {'nash', 10}, {'sam', 12},
  {'oba', 9}, {'odin', 17}, {'dva', 18}, {'tri', 19},
  {'chetyre', 20}, {'pyat', 21}, {'shest', 21}, {'sem', 21},
  {'vosem', 22}, {'devyat', 21}, {'desyat', 21}, {'bolshinstvo', 23},
  {'skolko', 25},
}

-- First set case bit wins; the nominative bit is implicit.
function generation.case(mask)
  for i = 1, 5 do if mask & (1 << i) ~= 0 then return i end end
  return 0
end

local function record(state,node)
  local r={}
  function r.b(f) return nodes.number(node,f) end
  function r.w(f) return signed(node[f] or 0) end
  function r.set(f,v) node[f]=v end
  r.word=r.set
  function r.text() return node.text or '' end
  function r.length() return #r.text() end
  function r.put(i,c) node.text=text.put(r.text(),i,c) end
  function r.byte(i) return text.byte(r.text(),i) end
  function r.ends(at,n) return text.ends(r.text(),state.assets:string(at),n) end
  function r.cat(at) node.text=r.text()..state.assets:string(at) end
  function r.copy(at) node.text=state.assets:string(at) end
  function r.save(value) if value==nil then return false end; node.text=value; return true end
  function r.valid() return r.w('paradigm')>=0 and r.w('paradigm')<0x7F end
  function r.adjective()
    return r.save(generation.adjective_form(state,r.w('paradigm'),r.text(),r.b('gender'),r.b('number'),generation.case(r.b('case_mask'))))
  end
  function r.verb(id,aspect)
    return r.save(generation.verb_form(state,id or r.w('paradigm'),r.text(),aspect or r.b('aspect'),r.b('verb_flags'),r.b('person'),
      r.b('number'),r.b('tense'),r.b('gender')))
  end
  return r
end

function generation.participle(state, node)
  local r = record(state, node)
  if not r.save(generation.participle_form(state, r.w('paradigm'), r.text(), r.b('aspect'), r.b('tag'), r.b('passive'), r.b('tense'))) then return end
  local n = r.length()
  if r.b('short_form') ~= 0 then
    if r.ends('sya', n) then n = n - 2; r.put(n, 0) end
    n = r.length()
    r.put(n - (r.byte(n - 3) == 0xAD and 3 or 2), 0)
    if r.b('number') ~= 0 then r.cat('y')
    elseif r.b('gender') == 2 then r.cat('a')
    elseif r.b('gender') == 0 then r.cat('o') end
  else
    local c = r.byte(n - (r.ends('sya', n) and 5 or 3))
    r.word('paradigm', (c == 0xE7 or c == 0xE8 or c == 0xE9) and 2 or 0)
    r.adjective()
  end
end

function generation.pronoun(state,node)
  local r=record(state,node)
  local stem,tail=r.text():match('^(.-)(%-.*)$')
  stem=stem or r.text()
  local result
  if text.ends(stem,state.assets:string('kakoy')) then
    r.word('paradigm',6)
    result=generation.adjective_form(state,6,stem,r.b('gender'),r.b('number'),generation.case(r.b('case_mask')))
  else result=generation.pronoun_form(state,stem,r.b('person'),r.b('gender'),r.b('number'),generation.case(r.b('case_mask')),r.b('aspect')) end
  if result then r.save(result..(tail or '')) end
end

function generation.word(state, node)
  local r = record(state, node)
  local tag = r.b('tag')
  if tag == 0x4E then -- N
    if r.valid() and (r.b('number') ~= 0 or r.b('case_mask') > 1) then
      r.save(generation.noun_form(state, r.w('paradigm'), r.text(), r.b('gender'), r.b('number'), generation.case(r.b('case_mask'))))
    end
  elseif tag == 0x55 then -- U
    local n = r.length()
    if r.ends('moch', n) then
      local aspect = 0
      if r.byte(0) ~= 0xE1 and r.b('aspect') == 1 then r.copy('smoch'); aspect = 1 end
      r.verb(0x5D, aspect)
    elseif r.ends('dolzhen', n) then
      r.put(n - 2, 0)
      r.cat(r.b('number') ~= 0 and 'ny' or r.b('gender') == 2 and 'na' or r.b('gender') == 1 and 'en' or 'no')
      if r.b('verb_flags') & 2 ~= 0 then r.cat('by') end
      if r.b('verb_flags') & 16 ~= 0 then r.cat('li') end
    end
  elseif tag == 0x58 or tag == 0x78 then -- X/x
    if tag == 0x78 and r.b('marker') == 0x6B then return 1 end
    local n = r.length()
    if r.byte(n - 1) == 0xAE then
      r.put(n - 2, 0)
      r.cat(r.b('number') ~= 0 and 'ny' or r.b('gender') == 2 and 'na' or r.b('gender') == 1 and 'en' or 'no')
      if r.b('verb_flags') & 2 ~= 0 then r.cat('by') end
      if r.b('verb_flags') & 16 ~= 0 then r.cat('li') end
    elseif r.b('verb_flags') & 8 == 0 then
      if r.ends('byt', 4) then r.word('paradigm', 0x39)
      elseif r.ends('delat') then r.set('aspect', 0); r.word('paradigm', 0)
      else return 1 end
      r.verb()
    end
  elseif tag == 0x59 then -- Y
    if r.ends('met') then r.word('paradigm', 0x28); r.verb() end
  elseif tag == 0x56 or tag == 0x76 then -- V/v
    if node.aux then
      local partner = record(state, node.aux)
      for i=0,partner.length()-1 do
        if text.alpha(partner.byte(i)) then partner.put(i,0); break end
      end
      if partner.ends('byt', 4) and partner.b('verb_flags') & 8 == 0 then
        local subject = r.b('verb_flags') & 8 ~= 0 and r.b('aspect') == 0 and partner or r
        partner.save(generation.verb_form(state, 0x39, partner.text(), partner.b('aspect'), subject.b('verb_flags'), subject.b('person'),
          subject.b('number'), partner.b('tense'), subject.b('gender')))
      end
    end
    if r.valid() then
      if r.b('passive') ~= 0 and r.b('short_form') ~= 0 then r.set('aspect', 1); generation.participle(state, node)
      else
        if r.b('verb_flags') & 8 ~= 0 then r.set('person', 0) end
        r.verb()
      end
    end
  elseif tag == 0x47 then -- G
    if r.valid() then
      r.save(generation.participle_form(state, r.w('paradigm'), r.text(), r.b('aspect'), 0x47, 0, 0))
    end
  elseif tag == 0x41 then -- A
    if (r.b('short_form') ~= 0 and r.b('previous_tag') == 0x41) or r.valid() then
      local original = r.b('previous_tag')
      if original == 0x45 or original == 0x56 or original == 0x46 or original == 0x65 or original == 0x47 then
        if original == 0x45 or original == 0x65 or original == 0x46 then
          r.set('passive', 1); if r.b('aspect') == 0 then r.set('tense', 0) end
        end
        generation.participle(state, node); return 1
      elseif r.b('short_form') ~= 0 then
        local n = r.length() - 2
        r.put(n, 0)
        if r.b('number') ~= 0 then
          if r.ends('nn', n) then r.put(n - 1, 0) end
          r.cat('y')
        elseif r.b('gender') == 2 then r.cat('a')
        elseif r.b('gender') == 0 then r.cat('o')
        else
          if r.ends('vk', n) or r.ends('tk', n) then r.put(n - 1, 0); r.cat('ok') end
          if r.ends('chn', n) or r.ends('pn', n) or r.ends('bn', n) or r.ends('vn', n) then r.put(n - 1, 0); r.cat('en') end
          if r.ends('soft_n', n) then r.put(n - 2, 0); r.cat('en') end
          if r.ends('nn', n) then r.put(n - 1, 0) end
        end
        return 1
      else r.adjective() end
    end
    if r.b('marker') == 0x61 and (r.b('tense') == 1 or r.b('tense') == 2) then
      local saved = r.text()
      if r.b('tense') == 2 then
        r.save(generation.adjective_form(state, 0, state.assets:string('samyy'), r.b('gender'), r.b('number'), generation.case(r.b('case_mask'))))
      else r.copy('bolee') end
      r.cat('space')
      node.text = r.text() .. saved
    end
  elseif tag == 0x4C or tag == 0x6C then -- L/l
    r.word('paradigm', 0); r.adjective()
  elseif tag == 0x53 then -- S
    if r.ends('tot') then
      if r.b('gender') == 2 then r.copy('ta')
      elseif r.b('gender') == 0 then r.copy('to') end
    end
  elseif tag == 0x49 or tag == 0x4F then -- I/O; native ordered suffix tests
    local id
    if r.byte(0) == 0xAB then id = 7
    else
      for _, ending in ipairs(NUMERAL_ENDINGS) do
        if r.ends(ending[1]) then id = ending[2]; break end
      end
    end
    if id then r.word('paradigm', id); r.adjective() end
  elseif tag == 0x44 then -- D
    if r.b('previous_tag') == 0x41 and r.b('marker') == 0 then
      local n = r.length()
      r.put(n - 2, r.ends('sk', (n - 2) & 0xFFFF) and 0xA8 or 0xAE)
      r.put(n - 1, 0)
    end
  elseif tag == 0x46 then -- F
    node.text = state.assets:string('comma') .. r.text()
    if r.valid() then
      r.set('tag', 0x45); r.set('tense', 0); r.set('aspect', 0)
      if r.b('previous_tag') == 0x45 or r.b('previous_tag') == 0x65 then r.set('passive', 1) end
      generation.participle(state, node)
    end
  elseif tag == 0x45 then -- E
    if r.valid() then
      local n = r.length()
      if r.ends('sya', n) then r.set('passive', 0) end
      if r.b('short_form') ~= 0 and r.b('dictionary_flags') & 8 ~= 0 then
        r.set('aspect', 0); r.set('verb_flags', 1); r.set('passive', 0); r.set('person', 3); r.set('tense', 0); r.set('tag', 0x56)
        if not r.ends('sya', n) then r.cat('sya') end
        r.verb()
      else
        if r.b('aspect') == 0 then r.set('tense', 0) end
        generation.participle(state, node)
      end
    end
  elseif tag == 0x4D or tag == 0x51 then -- M/Q
    if r.b('previous_tag') == 0x53 and r.ends('eto') then
      if r.b('number') == 0 and r.b('case_mask') & 8 == 0 then
        r.word('paradigm', 12); r.put(2, 0); r.adjective()
      end
    else generation.pronoun(state, node) end
  end
  return 1
end

function generation.run(state,root)
  local node=root.next
  while node do
    local r=record(state,node)
    if r.b('kind')==0x57 and r.b('reading_state')>1 and r.b('tag')~=0x23 and r.b('tag')~=0x48 then
      generation.word(state,node)
    end
    node=node.next
  end
  return 1
end
return generation
