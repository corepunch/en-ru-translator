local matching = require 'core.matching'
local nodes = require 'core.nodes'
local text = require 'core.text'
local constituents = {}
local get=nodes.byte

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
  local si,rec,v=0
  local function E(i) elements[i]=elements[i] or {}; return elements[i] end
  local function e0(i) return E(i).tag or 0 end
  local function e2(i) return E(i).class or 0 end
  local function set_tag(i,t) tags[i],E(i).tag=t,t end
  local function set_class(i,c) E(i).class=c end
  local function open(i) E(i).next,E(i).last=nil,nil end
  local function append(i) nodes.append(E(i),rec) end
  local function new(i,tag,class) set_tag(i,tag); set_class(i,class); open(i) end
  local function r(at) return get(rec,at) end
  local function set_r(at,v) rec[at]=v end
  local function following(at) return get(rec.next,at) end
  local function is(at) return text.equal(rec[0x12] or '',state.assets:string(at)) end
  local function either(c,set) return set:find(string.char(c),1,true)~=nil end
  local function drop_boundary(i) nodes.pop(E(i)) end

  rec = nodes.pop(root)
  if not rec then return 0 end
  E(0).tag = r(0x0C)
  set_class(0, 0x2A)
  tags[0] = 0x2A
  open(0)
  append(0)
  while true do
    rec = nodes.pop(root)
    if not rec or si > 0x42 then break end
    v = r(0x0C)
    if si == 0 then
      if v == 0x44 or v == 0x2C or v == 0x43 or v == 0x29 then append(si); goto continue end
      if v == 0x48 and (following(0x0C) == 0x2E or following(0x0C) == 0x29) then
        append(si); goto continue
      end
    end
    if v == 0x52 or v == 0x72 or v == 0x53 then
      si = si + 1; new(si, v, 0x57); append(si); goto continue
    end
    if v == 0x51 and e0(si) ~= 0x50 then
      si = si + 1; new(si, v, 0x77); append(si); goto continue
    end
    if v == 0x47 or v == 0x46 then
      if e0(si) ~= v then si = si + 1; new(si, v, 0x47) end
      append(si); goto continue
    end
    if v == 0x4C or v == 0x6B then
      si = si + 1; new(si, v, 0x6B); append(si); goto continue
    end
    if v == 0x50 and not is(0x506C) and e2(si) == 0x50 then
      si = si + 1; new(si, v, 0x57); append(si); goto continue
    end
    -- Element 1's class (the array's byte at +0E) and tag (+0C).
    if v == 0x50 and e2(1) ~= 0x50 and e0(1) == 0x50 and si == 1 and not is(0x506F) and not is(0x5072) then
      set_class(1, 0x50); append(si); goto continue
    end
    if v == 0x50 and si ~= 0 and e2(si) ~= 0x59 and e2(si) ~= 0x4B and e2(si) ~= 0x44 and
       following(0x0C) ~= 0x4D then
      if not is(0x5075) or e0(si) == 0x53 then
        si = si + 1; new(si, v, 0x57)
      elseif e2(si) == 0x77 then
        set_class(si, 0x57)
      elseif e2(si) ~= 0x47 and e0(si) ~= 0x57 then
        set_class(si, 0x77)
      end
      append(si); goto continue
    end
    if v == 0x77 and is(0x5078) then
      if e2(si) == 0x77 then set_class(si, 0x57) elseif e2(si) == 0x57 then set_class(si, 0x77) end
      append(si); goto continue
    end
    if v == 0x50 and e2(si) == 0x59 and following(0x0C) ~= 0x4D then
      si = si + 1; new(si, v, 0x57); append(si); goto continue
    end
    if v == 0x50 and e2(si) == 0x44 then
      si = si + 1; new(si, v, 0x57); append(si); goto continue
    end
    if v == 0x49 then
      if not either(e2(si), 'WwKP') then si = si + 1; new(si, v, 0x57) end
      if e0(si) ~= 0x50 then set_tag(si, v); set_class(si, 0x4B) end
      append(si); goto continue
    end
    if v == 0x48 then
      if not either(e2(si), 'WwKP') then si = si + 1; new(si, v, 0x57) end
      if e0(si) ~= 0x50 and e0(si) ~= 0x4E then
        set_tag(si, v)
        set_class(si, is(0x507B) and 0x57 or 0x4B)
      end
      append(si); goto continue
    end
    if v == 0x4F then
      if not either(e2(si), 'WwPGK') then
        if e0(si) == 0x74 then drop_boundary(si) else si = si + 1 end
        new(si, v, 0x57)
      end
      if not either(e0(si), 'WPI') and not either(e2(si), 'KGP') then
        set_tag(si, v)
        if following(0x0C) == 0x50 then
          set_class(si, 0x4B)
        elseif r(0x75) ~= 0 then
          set_tag(si, 0x6B); set_class(si, 0x4B)
        end
      end
      append(si); goto continue
    end
    if v == 0x4E or v == 0x41 or v == 0x23 or v == 0x3F or v == 0x69 or v == 0x24 then
      if e0(si) == 0x6B then set_class(si, 0x4B) end
      if not either(e2(si), 'WwPKG') then
        if e0(si) == 0x74 then drop_boundary(si) else si = si + 1 end
        new(si, v, 0x57)
      end
      if v == 0x41 and e0(si) == 0x4F and e2(si) ~= 0x4B and e0(si) ~= 0x57 then set_tag(si, v) end
      if (v == 0x4E or v == 0x23) and not either(e2(si), 'GK') and not either(e0(si), 'PQNWRk') then
        set_tag(si, v)
      end
      if v == 0x4E and e0(si) == 0x51 then set_class(si, 0x57) end
      append(si); goto continue
    end
    if either(v, 'UXYBbxyf') then
      si = si + 1; new(si, v, r(0x0F) == 0x72 and 0x79 or 0x59); append(si); goto continue
    end
    if v == 0x56 or v == 0x76 then
      if e2(si) ~= 0x59 then si = si + 1; new(si, v, 0x59) end
      append(si); goto continue
    end
    if v == 0x45 then
      if e0(si) ~= 0x50 and e0(si) ~= 0x47 then
        si = si + 1
        if r(0x0F) ~= 0x6E and e2(si - 1) ~= 0x43 and e0(si - 1) ~= 0x4C and e0(si - 1) ~= 0x2A then
          set_r(0x0C, 0x56); set_tag(si, 0x56); set_r(0x7A, 0)
        else
          set_tag(si, v)
        end
        set_class(si, 0x59); open(si); append(si)
      elseif r(0x0F) == 0x6E then
        append(si)
      elseif e0(si - 1) == 0x2A or e0(si - 1) == 0x56 then
        append(si)
      else
        si = si + 1; new(si, v, 0x59); append(si)
      end
      goto continue
    end
    if either(v, ';Jj|^t()=:pul_') then
      si = si + 1; new(si, v, 0x44); append(si); goto continue
    end
    if v == 0x26 and (e0(si) == 0x4E or e0(si) == 0x50) then
      if e2(si) == 0x57 or (e2(si) == 0x77 and r(0x66) ~= 0x43) then
        if e0(si) == 0x4E then set_tag(si, 0x57) end
        set_class(si, 0x57)
      end
      append(si); goto continue
    end
    if (v == 0x2C or v == 0x43) and si ~= 0 then
      if e2(si) ~= 0x59 then
        si = si + 1; new(si, v, 0x43)
      else
        local c = following(0x0C)
        if not ((c == 0x56 or c == 0x43) and not (rec.next and rec.next.aux)) then
          si = si + 1; new(si, v, 0x43)
        end
      end
      append(si); goto continue
    end
    if v == 0x2A and r(0x0D) == 0x2A then
      si = si + 1; new(si, v, 0x2A); append(si); goto continue
    end
    if si == 0 or e0(si) == 0x29 then si = si + 1; new(si, v, 0x57) end
    append(si)
    ::continue::
  end
  si = si + 1
  tags[si] = 0
  return si
end

function constituents.pass(state,root,terminator,t7)
  state.count=constituents.build(state,root)
  if state.count==0 then return end
  local function E(i) return state.elements[i] or {} end
  local function tag(i) return E(i).tag or 0 end
  local function first(i) return E(i).next end
  local function retag(i,t) E(i).tag,state.tags[i]=t,t end
  local function is(r,at) return text.equal(r[0x12] or '',state.assets:string(at)) end
  local function bit(r,n) return (get(r,0x6D) >> n) & 1 end
  local function verb(r)
    while r and get(r,0x0C)~=0x56 do r=r.next end
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
          if r and get(r,0x0F)==0 and (is(r,0x5107) or is(r,0x510A) or is(r,0x510D)) then r[0x76]=0x20 end
          more=false
        elseif selector==3 then
          t7(state,E(si+1),tag(si+1),si)
          local a,b=first(si+1),first(hit)
          while b and get(b,0x0C)~=0x56 and get(b,0x0C)~=0x55 do b=b.next end
          if a and b then b[0x77],b[0x74],b[0x72]=get(a,0x77),3,get(a,0x72) end
          more=false
        elseif selector==4 then
          local di=hit
          while tag(di)~=0x45 and di>si do di=di-1 end
          local r=first(di)
          if r and get(r,0x0F)~=0x6E then r[0x0C],r[0x7A]=0x56,0; retag(di,0x56) end
        elseif selector==5 then
          local r=first(hit)
          if r then retag(hit,0x56); r[0x0C],r[0x7A]=0x56,0 end
        elseif selector==7 then
          local a,b=first(si),first(hit)
          if a and (get(a,0x6A) >> 6) & 1 ~=0 and b then b.text='' end
        elseif selector==9 then
          local a,b=first(hit-1),first(hit)
          if a and b then
            a[0x74],a[0x72],a[0x77]=get(b,0x74),get(b,0x72),get(b,0x77)
            E(hit).class,E(hit-1).class=0x71,0x71
          end
          more=false
        elseif selector==10 then
          local r=nodes.word(state,0x4C,state.assets:string(0x5110))
          if r then r[0x0B]=3; constituents.insert(state,{tag=0x4C,class=0x4B,next=r,last=r},hit) end
          more=false
        elseif selector==18 then
          local r=verb(first(hit))
          if r then
            if is(r,0x511A) then r.text=state.assets:string(0x511E)
            elseif get(r,0x74)==0 or get(r,0x66)==0x65 then r[0x73]=0; r[0x78]=get(r,0x78) | 4 end
          end
          E(hit).class=0x71; more=false
        elseif selector==20 then
          local skip=tag(si-1)==0x4C or terminator==0x3A
          if not skip and tag(hit)==0x50 and tag(hit+1)==0x4E then skip=true end
          local p=first(hit-1)
          if not skip then
            if not p or not p.next or get(p,0x0E)==0x44 then skip=true
            else
              local nc=get(p.next,0x0C)
              if nc==0x56 or nc==0x4D or nc==0x77 or get(p,0x68) & 0x3F ~= 0 then skip=true end
            end
          end
          local a,b=first(si),first(hit)
          if not skip and (not a or not b) then skip=true end
          if not skip then
            if get(a,0x0E)==0x44 or get(b,0x0E)==0x44 then skip=true
            elseif bit(a,1)~=0 then skip=true
            elseif get(b,0x0C)==0x50 and get(b,0x0F)==0x77 then skip=true
            elseif get(b,0x0C)==0x4A and is(b,0x5125) then skip=true end
          end
          if not skip and get(p,0x0C)==0x56 and bit(p,0)~=0 and bit(p,5)==0 and bit(p,4)==0 and
            get(p,0x78)==0 and get(p,0x7A)==0 then p.text=p.text..state.assets:string(0x512A) end
        elseif selector==21 then
          if tag(si-1)~=0x4C then
            local b=first(hit)
            if b and not (get(b,0x0C)==0x50 and get(b,0x0F)==0x77) then
              local p=E(hit-1).last
              if p and get(p,0x0C)==0x56 and bit(p,0)~=0 and bit(p,5)==0 and bit(p,4)==0 and
                get(p,0x78)==0 and get(p,0x7A)==0 then p.text=p.text..state.assets:string(0x512D) end
            end
          end
        end
      end
      si=si+1
    end
  end
end
return constituents
