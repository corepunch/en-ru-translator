local matching = require 'core.matching'
local nodes = require 'core.nodes'
local text = require 'core.text'
local constituents = {}
local get=nodes.number

-- Elements own linked record lists. Cached tags are intentionally separate
-- from live tags because the rule interpreter can observe both.
function constituents.insert(state,element,at)
  if at<=0 or at>=state.count then return state.count end
  for i=state.count,at+1,-1 do state.elements[i]=state.elements[i-1]; state.tags[i]=state.tags[i-1] end
  state.elements[at],state.tags[at]=element,element.tag
  state.count=state.count+1; state.tags[state.count]=0
  return state.count
end
function constituents.swap(state,i,j)
  state.elements[i],state.elements[j]=state.elements[j],state.elements[i]
  state.tags[i],state.tags[j]=state.tags[j],state.tags[i]
end
function constituents.relink(state,root)
  root.next,root.last=nil,nil
  for i=0,state.count-1 do
    local e=state.elements[i]
    if e.next then
      if root.last then root.last.next=e.next else root.next=e.next end
      root.last=e.last
    end
  end
  if root.last then root.last.next=nil end
end
function constituents.build(state,root)
  local elements,tags={},{}
  state.elements,state.tags=elements,tags
  local index,word,word_tag=0
  local function element(i) elements[i]=elements[i] or {}; return elements[i] end
  local function element_tag(i) return string.char(element(i).tag or 0) end
  local function element_class(i) return string.char(element(i).class or 0) end
  local function set_tag(i,t) tags[i],element(i).tag=t:byte(),t:byte() end
  local function set_class(i,c) element(i).class=c:byte() end
  local function clear_words(i) element(i).next,element(i).last=nil,nil end
  local function append_word(i) nodes.append(element(i),word) end
  local function start_element(i,tag,class) set_tag(i,tag); set_class(i,class); clear_words(i) end
  local function number(at) return get(word,at) end
  local function set_field(at,word_tag) word[at]=word_tag end
  local function following_tag() return nodes.tag(word.next) end
  local function source_is(at) return text.equal(word.source or '',state.assets:string(at)) end
  local function one_of(c,set) return set:find(c,1,true)~=nil end
  local function drop_boundary(i) nodes.pop(element(i)) end

  word = nodes.pop(root)
  if not word then return 0 end
  element(0).tag = word.tag
  set_class(0, '*')
  tags[0] = string.byte('*')
  clear_words(0)
  append_word(0)
  while true do
    word = nodes.pop(root)
    if not word or index > 66 then break end
    word_tag = nodes.tag(word)
    if index == 0 then
      if word_tag == 'D' or word_tag == ',' or word_tag == 'C' or word_tag == ')' then append_word(index); goto continue end
      if word_tag == 'H' and (following_tag() == '.' or following_tag() == ')') then
        append_word(index); goto continue
      end
    end
    if word_tag == 'R' or word_tag == 'r' or word_tag == 'S' then
      index = index + 1; start_element(index, word_tag, 'W'); append_word(index); goto continue
    end
    if word_tag == 'Q' and element_tag(index) ~= 'P' then
      index = index + 1; start_element(index, word_tag, 'w'); append_word(index); goto continue
    end
    if word_tag == 'G' or word_tag == 'F' then
      if element_tag(index) ~= word_tag then index = index + 1; start_element(index, word_tag, 'G') end
      append_word(index); goto continue
    end
    if word_tag == 'L' or word_tag == 'k' then
      index = index + 1; start_element(index, word_tag, 'k'); append_word(index); goto continue
    end
    if word_tag == 'P' and not source_is(0x506C) and element_class(index) == 'P' then
      index = index + 1; start_element(index, word_tag, 'W'); append_word(index); goto continue
    end
    -- Element 1's class (the array's byte at +0E) and tag (+0C).
    if word_tag == 'P' and element_class(1) ~= 'P' and element_tag(1) == 'P' and index == 1 and not source_is(0x506F) and not source_is(0x5072) then
      set_class(1, 'P'); append_word(index); goto continue
    end
    if word_tag == 'P' and index ~= 0 and element_class(index) ~= 'Y' and element_class(index) ~= 'K' and element_class(index) ~= 'D' and
       following_tag() ~= 'M' then
      if not source_is(0x5075) or element_tag(index) == 'S' then
        index = index + 1; start_element(index, word_tag, 'W')
      elseif element_class(index) == 'w' then
        set_class(index, 'W')
      elseif element_class(index) ~= 'G' and element_tag(index) ~= 'W' then
        set_class(index, 'w')
      end
      append_word(index); goto continue
    end
    if word_tag == 'w' and source_is(0x5078) then
      if element_class(index) == 'w' then set_class(index, 'W') elseif element_class(index) == 'W' then set_class(index, 'w') end
      append_word(index); goto continue
    end
    if word_tag == 'P' and element_class(index) == 'Y' and following_tag() ~= 'M' then
      index = index + 1; start_element(index, word_tag, 'W'); append_word(index); goto continue
    end
    if word_tag == 'P' and element_class(index) == 'D' then
      index = index + 1; start_element(index, word_tag, 'W'); append_word(index); goto continue
    end
    if word_tag == 'I' then
      if not one_of(element_class(index), 'WwKP') then index = index + 1; start_element(index, word_tag, 'W') end
      if element_tag(index) ~= 'P' then set_tag(index, word_tag); set_class(index, 'K') end
      append_word(index); goto continue
    end
    if word_tag == 'H' then
      if not one_of(element_class(index), 'WwKP') then index = index + 1; start_element(index, word_tag, 'W') end
      if element_tag(index) ~= 'P' and element_tag(index) ~= 'N' then
        set_tag(index, word_tag)
        set_class(index, source_is(0x507B) and 'W' or 'K')
      end
      append_word(index); goto continue
    end
    if word_tag == 'O' then
      if not one_of(element_class(index), 'WwPGK') then
        if element_tag(index) == 't' then drop_boundary(index) else index = index + 1 end
        start_element(index, word_tag, 'W')
      end
      if not one_of(element_tag(index), 'WPI') and not one_of(element_class(index), 'KGP') then
        set_tag(index, word_tag)
        if following_tag() == 'P' then
          set_class(index, 'K')
        elseif number('aspect') ~= 0 then
          set_tag(index, 'k'); set_class(index, 'K')
        end
      end
      append_word(index); goto continue
    end
    if word_tag == 'N' or word_tag == 'A' or word_tag == '#' or word_tag == '?' or word_tag == 'i' or word_tag == '$' then
      if element_tag(index) == 'k' then set_class(index, 'K') end
      if not one_of(element_class(index), 'WwPKG') then
        if element_tag(index) == 't' then drop_boundary(index) else index = index + 1 end
        start_element(index, word_tag, 'W')
      end
      if word_tag == 'A' and element_tag(index) == 'O' and element_class(index) ~= 'K' and element_tag(index) ~= 'W' then set_tag(index, word_tag) end
      if (word_tag == 'N' or word_tag == '#') and not one_of(element_class(index), 'GK') and not one_of(element_tag(index), 'PQNWRk') then
        set_tag(index, word_tag)
      end
      if word_tag == 'N' and element_tag(index) == 'Q' then set_class(index, 'W') end
      append_word(index); goto continue
    end
    if one_of(word_tag, 'UXYBbxyf') then
      index = index + 1; start_element(index, word_tag, string.char(number('marker')) == 'r' and 'y' or 'Y'); append_word(index); goto continue
    end
    if word_tag == 'V' or word_tag == 'v' then
      if element_class(index) ~= 'Y' then index = index + 1; start_element(index, word_tag, 'Y') end
      append_word(index); goto continue
    end
    if word_tag == 'E' then
      if element_tag(index) ~= 'P' and element_tag(index) ~= 'G' then
        index = index + 1
        if string.char(number('marker')) ~= 'n' and element_class(index - 1) ~= 'C' and element_tag(index - 1) ~= 'L' and element_tag(index - 1) ~= '*' then
          nodes.set_tag(word, 'V'); set_tag(index, 'V'); set_field('passive', 0)
        else
          set_tag(index, word_tag)
        end
        set_class(index, 'Y'); clear_words(index); append_word(index)
      elseif string.char(number('marker')) == 'n' then
        append_word(index)
      elseif element_tag(index - 1) == '*' or element_tag(index - 1) == 'V' then
        append_word(index)
      else
        index = index + 1; start_element(index, word_tag, 'Y'); append_word(index)
      end
      goto continue
    end
    if one_of(word_tag, ';Jj|^t()=:pul_') then
      index = index + 1; start_element(index, word_tag, 'D'); append_word(index); goto continue
    end
    if word_tag == '&' and (element_tag(index) == 'N' or element_tag(index) == 'P') then
      if element_class(index) == 'W' or (element_class(index) == 'w' and string.char(number('previous_tag')) ~= 'C') then
        if element_tag(index) == 'N' then set_tag(index, 'W') end
        set_class(index, 'W')
      end
      append_word(index); goto continue
    end
    if (word_tag == ',' or word_tag == 'C') and index ~= 0 then
      if element_class(index) ~= 'Y' then
        index = index + 1; start_element(index, word_tag, 'C')
      else
        local c = following_tag()
        if not ((c == 'V' or c == 'C') and not (word.next and word.next.aux)) then
          index = index + 1; start_element(index, word_tag, 'C')
        end
      end
      append_word(index); goto continue
    end
    if word_tag == '*' and string.char(number('separator')) == '*' then
      index = index + 1; start_element(index, word_tag, '*'); append_word(index); goto continue
    end
    if index == 0 or element_tag(index) == ')' then index = index + 1; start_element(index, word_tag, 'W') end
    append_word(index)
    ::continue::
  end
  index = index + 1
  tags[index] = 0
  return index
end

function constituents.pass(state,root,terminator,t7)
  state.count=constituents.build(state,root)
  if state.count==0 then return end
  local function E(i) return state.elements[i] or {} end
  local function tag(i) return E(i).tag or 0 end
  local function first(i) return E(i).next end
  local function retag(i,t) E(i).tag,state.tags[i]=t,t end
  local function is(r,at) return text.equal(r.source or '',state.assets:string(at)) end
  local function bit(r,n) return (get(r,'dictionary_flags') >> n) & 1 end
  local function verb(r)
    while r and get(r,'tag')~=0x56 do r=r.next end
    return r
  end
  for _,rule in ipairs(state.assets:rules(0x4FEC)) do
    local si,more=0,true
    while more and state.count-1>si do
      local hit=matching.constituents(state,si,rule.pattern)
      if hit~=0 then
        local selector=rule.selector
        if selector==1 then
          local r=first(hit)
          if r and get(r,'marker')==0 and (is(r,0x5107) or is(r,0x510A) or is(r,0x510D)) then r.case_mask=0x20 end
          more=false
        elseif selector==3 then
          t7(state,E(si+1),tag(si+1),si)
          local a,b=first(si+1),first(hit)
          while b and get(b,'tag')~=0x56 and get(b,'tag')~=0x55 do b=b.next end
          if a and b then b.gender,b.person,b.number=get(a,'gender'),3,get(a,'number') end
          more=false
        elseif selector==4 then
          local di=hit
          while tag(di)~=0x45 and di>si do di=di-1 end
          local r=first(di)
          if r and get(r,'marker')~=0x6E then r.tag,r.passive=0x56,0; retag(di,0x56) end
        elseif selector==5 then
          local r=first(hit)
          if r then retag(hit,0x56); r.tag,r.passive=0x56,0 end
        elseif selector==7 then
          local a,b=first(si),first(hit)
          if a and (get(a,'lookup_frame') >> 6) & 1 ~=0 and b then b.text='' end
        elseif selector==9 then
          local a,b=first(hit-1),first(hit)
          if a and b then
            a.person,a.number,a.gender=get(b,'person'),get(b,'number'),get(b,'gender')
            E(hit).class,E(hit-1).class=0x71,0x71
          end
          more=false
        elseif selector==10 then
          local r=nodes.word(state,0x4C,state.assets:string(0x5110))
          if r then r.reading_state=3; constituents.insert(state,{tag=0x4C,class=0x4B,next=r,last=r},hit) end
          more=false
        elseif selector==18 then
          local r=verb(first(hit))
          if r then
            if is(r,0x511A) then r.text=state.assets:string(0x511E)
            elseif get(r,'person')==0 or get(r,'previous_tag')==0x65 then r.tense=0; r.verb_flags=get(r,'verb_flags') | 4 end
          end
          E(hit).class=0x71; more=false
        elseif selector==20 then
          local skip=tag(si-1)==0x4C or terminator==0x3A
          if not skip and tag(hit)==0x50 and tag(hit+1)==0x4E then skip=true end
          local p=first(hit-1)
          if not skip then
            if not p or not p.next or get(p,'kind')==0x44 then skip=true
            else
              local nc=get(p.next,'tag')
              if nc==0x56 or nc==0x4D or nc==0x77 or get(p,'lookup_flags') & 0x3F ~= 0 then skip=true end
            end
          end
          local a,b=first(si),first(hit)
          if not skip and (not a or not b) then skip=true end
          if not skip then
            if get(a,'kind')==0x44 or get(b,'kind')==0x44 then skip=true
            elseif bit(a,1)~=0 then skip=true
            elseif get(b,'tag')==0x50 and get(b,'marker')==0x77 then skip=true
            elseif get(b,'tag')==0x4A and is(b,0x5125) then skip=true end
          end
          if not skip and get(p,'tag')==0x56 and bit(p,0)~=0 and bit(p,5)==0 and bit(p,4)==0 and
            get(p,'verb_flags')==0 and get(p,'passive')==0 then p.text=p.text..state.assets:string(0x512A) end
        elseif selector==21 then
          if tag(si-1)~=0x4C then
            local b=first(hit)
            if b and not (get(b,'tag')==0x50 and get(b,'marker')==0x77) then
              local p=E(hit-1).last
              if p and get(p,'tag')==0x56 and bit(p,0)~=0 and bit(p,5)==0 and bit(p,4)==0 and
                get(p,'verb_flags')==0 and get(p,'passive')==0 then p.text=p.text..state.assets:string(0x512D) end
            end
          end
        end
      end
      si=si+1
    end
  end
end
return constituents
