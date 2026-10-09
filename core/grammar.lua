local nodes = require 'core.nodes'
local matching = require 'core.matching'
local rules = require 'core.rules'
local encoding = require 'core.encoding'

local grammar = {}
local number, tag, set, mark = nodes.number, nodes.tag, nodes.set_tag, nodes.set_marker
local reading = nodes.has_reading

-- LTPRO 12DC:0005, file 167C5..16AE3. Also called before T2 for questions.
function grammar.cleanup(root)
  local vector,count,state
  local removed=0
  local function rebuild()
    vector,count,state=nodes.rebuild(root)
  end
  rebuild()
  for _,rule in ipairs(rules[7]) do
    local handler,pattern,action=table.unpack(rule)
    pattern=encoding.encode(pattern);action=action and encoding.encode(action)
    local first=1
    while first<count-1 do
      local last=matching.match(vector,first,pattern,state.tags)
      if last~=0 then
        local head,tail=vector[first],vector[last]
        if handler==1 then
          for _,at in ipairs({'number','tense','person'}) do tail[at]=head[at] or 0 end
          -- Lua improvement: a question's future verb takes the perfective, as
          -- the declarative X V path does (Will you come? -> Ты придешь, not the
          -- original's present приходите).
          if (head.tense or 0)==2 then tail.aspect=1 end
          if tag(vector[first-1])=='Z' then vector[first-1].tag=0x4E end
          last=count
        elseif handler==8 then
          local following=head.next
          local before,previous=vector[first-1],vector[last-1]
          if tag(following)=='K' then before.next=following.next; following.next=tail
          else before.next=head.next; head.next=tail end
          previous.next=head
          local old_count=count
          rebuild();first=old_count
          goto advance
        elseif handler==11 then
          local auxiliary=vector[first+1]
          if (auxiliary.tense or 0)==0 and (auxiliary.person or 0)~=0 then
            auxiliary.tag=0x20
            local j=first+2
            while j<last and tag(vector[j])~='*' do
              if tag(vector[j])=='Z' then vector[j].tag=0x4E end
              j=j+1
            end
          end
          rebuild();first=count
          goto advance
        elseif handler~=0 then error('unported native cleanup selector '..handler) end
        removed=matching.replace(vector,first,last,pattern,action,state)
        first=last
      end
      ::advance::
      first=first+1
    end
    if removed~=0 then rebuild();removed=0 end
  end
  return {root=root,vector=vector,count=count,tags=state.tags,removed=removed}
end

-- LTPRO 0E1F:0009, file 11BF9..1254A: native T1 scheduling and handlers.

function grammar.first(root, options)
  options = options or {}
  local vector, count, state
  local events = {}
  local function rebuild()
    vector, count, state = nodes.rebuild(root)
  end
  rebuild()
  for i = 1, count - 2 do
    local t = tag(vector[i])
    if t == '[' or t == ']' or t == '<' or t == '>' then
      set(vector[i], '/')
      state.tags = state.tags:sub(1,i) .. '/' .. state.tags:sub(i+2)
    elseif t == '?' and (vector[i].source or ''):sub(1,1) == '_' then
      set(vector[i], '_')
      state.tags = state.tags:sub(1,i) .. '_' .. state.tags:sub(i+2)
    end
  end
  for index, rule in ipairs(options.rules or rules[1]) do
    local handler, pattern, action = table.unpack(rule)
    pattern = encoding.encode(pattern)
    action = action and encoding.encode(action)
    local last = matching.match(vector, 0, pattern, state.tags)
    if last ~= 0 then
      local head, tail, previous = vector[1], vector[last], vector[last-1]
      events[#events+1] = {rule=index, handler=handler, first=0, last=last}
      if options.on_match then options.on_match(events[#events],vector,count,state.tags) end
      local disposition = 'replace'
      if handler == 1 then
        if number(previous,'person') ~= 0 then set(previous,'N'); disposition='rebuild' end
      elseif handler == 2 then
        if number(head,'number') == number(tail,'number') then set(head,'O'); set(tail,'N')
        else set(tail,'V') end
        disposition='rebuild'
      elseif handler == 3 then
        if number(previous,'number') == 0 then disposition='skip' end
      elseif handler == 4 then
        local i=last
        while i>0 and tag(vector[i])~='Z' do i=i-1 end
        if number(vector[i],'number')==number(vector[i-1],'number') then disposition='skip' end
      elseif handler == 5 then
        local i=1
        while i<last-1 and tag(vector[i])~='Z' do i=i+1 end
        local j=i
        while j>1 and tag(vector[j])~='N' do j=j-1 end
        set(vector[i],number(vector[i],'number')==number(vector[j],'number') and 'N' or 'V')
        disposition='rebuild'
      elseif handler == 6 then
        if number(head,'marker')==0x77 then disposition='skip' end
      elseif handler == 7 then head.tense=0
      elseif handler == 8 then
        previous.aspect,previous.passive,previous.short_form,previous.marker=1,1,1,0x6E
        disposition='rebuild'
      elseif handler == 10 then
        for i=last-1,1,-1 do
          if ('ZEeG'):find(tag(vector[i]),1,true) then set(vector[i],'N') end
        end
        -- Native returns immediately with zero, before rebuilding its cache.
        return {root=root,vector=vector,count=count,tags=state.tags,events=events,result=0}
      elseif handler == 11 then
        if tag(head)=='E' then set(head,'A'); head.aspect,head.passive=1,1 end
        local i=1
        while i<last and tag(vector[i])~='*' do
          local n=vector[i]
          -- Both native DS:2D9B and DS:2DA0 point to the literal "that".
          if tag(n)=='Z' and (vector[i-1].source or ''):lower()~='that'
            and (vector[i+1].source or ''):lower()~='that' then set(n,'N') end
          if tag(n)=='G' or tag(n)=='E' then n.marker=0x6E end
          i=i+1
        end
        disposition='rebuild'
      elseif handler == 12 then
        local i=last-1
        while i>2 and tag(vector[i])~='R' do i=i-1 end
        local boundary=nodes.boundary('j','|',options.boundaries)
        if boundary then
          boundary.next=vector[i-1].next
          vector[i-1].next=boundary
        end
        -- Native continues to use the old vector until both edits finish.
        i=1
        while i<last-2 and tag(vector[i])~='B' do i=i+1 end
        set(vector[i],'J')
        if tag(vector[i+1])=='Z' then set(vector[i+1],'V') end
        disposition='rebuild'
      elseif handler == 14 then
        local i=1
        while i<last and tag(vector[i])~='*' do
          local n=vector[i]
          if tag(n)=='Z' and tag(vector[i-1])~='S' then set(n,'N') end
          if tag(n)=='G' or tag(n)=='E' then n.marker=0x6E end
          i=i+1
        end
      elseif handler == 15 then
        local i=1
        if tag(head)~='J' then
          while i<last and tag(vector[i])~='J' do i=i+1 end
        end
        if tag(vector[i])~='J' then disposition='skip'
        else
          set(vector[i],'P'); set(vector[i+1],'N'); vector[i+1].marker=0x67
          local j=i+1
          while j<last and tag(vector[j])~='R' do
            local n=vector[j]
            if tag(n)=='Z' then set(n,'N') end
            if tag(n)=='G' or tag(n)=='E' then n.marker=0x6E end
            if tag(n)==',' or tag(n)=='C' then set(n,'&') end
            j=j+1
          end
          disposition='rebuild'
        end
      elseif handler == 20 then
        if (previous.source or ''):sub(1,1)=='_' then
          set(head,'N'); set(previous,'_'); rebuild()
          return {root=root,vector=vector,count=count,tags=state.tags,events=events,result=0}
        end
        disposition='skip'
      elseif handler == 63 then
        if options.terminator==0x0A then set(previous,'N'); disposition='rebuild'
        else disposition='skip' end
      end
      if disposition=='rebuild' then rebuild()
      elseif disposition=='replace' then
        local removed=matching.replace(vector,0,last,pattern,action,state)
        if removed~=0 then rebuild() end
        -- A default rewrite ends T1; it does not continue through later rules.
        break
      end
    end
  end
  if options.terminator==0x3F then
    local result=grammar.cleanup(root)
    vector,count,state=result.vector,result.count,{tags=result.tags}
  end
  return {root=root,vector=vector,count=count,tags=state.tags,events=events,result=1}
end

-- LTPRO 0E1F:095A..1B10, file 1254A..13700: native T2 scheduling and handlers.
-- Runs over table nodes after grammar.first.
-- Field offsets are the original record offsets. `count` models DS:C7B1, which
-- several native handlers leave stale after their own vector rebuild.
-- strrchr on the +98 pointer, which addresses the record's own +11C translation.
local function initial(n) return (n.source or ''):sub(1, 1) end
local function link(tail, target) tail.aux = assert(target, 'missing native node') end
local DOLZHEN = encoding.encode('должен')
local NEUZHELI = encoding.encode('неужели ')
local NE = encoding.encode('не ')

function grammar.second(root, options)
  options = options or {}
  local vector, count, state
  local events = {}
  local function rebuild()
    local n
    vector, n, state = nodes.rebuild(root)
    return n
  end
  count = rebuild()
  if options.count then count = options.count end
  local function V(i)
    return assert(vector[i], 'native T2 read beyond lexical vector at ' .. i)
  end
  -- Native descending searches stop at di-1 when no node in di..last has the tag.
  local function seek_down(from, di, c)
    local i = from
    while i >= di and tag(vector[i]) ~= c do i = i - 1 end
    return i
  end
  local function copy_aux(target, head)
    target.number, target.tense, target.person = number(head, 'number'), 1, number(head, 'person')
    mark(target, 'X')
  end
  local removed = 0
  for index, rule in ipairs(options.rules or rules[2]) do
    local handler, pattern, action = table.unpack(rule)
    pattern = encoding.encode(pattern)
    action = action and encoding.encode(action)
    local di = 1
    while count - 1 > di do
      local last = vector[di] and matching.match(vector, di, pattern, state.tags) or 0
      if not vector[di] then
        events[#events + 1] = {rule = index, handler = handler, first = di, stale = true}
      end
      if last == 0 then
        di = di + 1
      else
        local head, tail = V(di), V(last)
        events[#events + 1] = {rule = index, handler = handler, first = di, last = last}
        if options.on_match then options.on_match(events[#events], vector, count, state.tags) end
        -- Exits: 'default' = native replacement at 13670; 'skip' = 125DE (di=last);
        -- 'finish' = 134FB (di=count); 'step' = 1369D; 'step2' = 12EC4.
        local exit = 'default'
        if handler == 1 then
          if number(V(di + 1), 'number') ~= 0 then exit = 'skip' end
        elseif handler == 2 then
          local i = seek_down(last, di, 'G')
          local n = V(i)
          if number(n, 'previous_tag') ~= 0x56 then
            if reading(n, 'A') then set(n, 'A') end
            if reading(n, 'N') then set(n, 'N'); mark(n, 'g') end
            rebuild()
          end
          exit = 'skip'
        elseif handler == 3 then
          local n = V(seek_down(last, di, 'G'))
          if reading(n, 'N') then mark(n, 'g') else exit = 'skip' end
        elseif handler == 5 then
          tail.verb_flags = number(tail, 'verb_flags') | 1; tail.tense = 0; tail.person = 3; mark(tail, 'J')
        elseif handler == 6 then
          if number(head, 'tense') < 2 then exit = 'skip' end
        elseif handler == 7 then
          if number(tail, 'number') == 0 then exit = 'skip' end
        elseif handler == 8 then
          head.verb_flags = number(head, 'verb_flags') | 1
        elseif handler == 9 then
          head.case_mask, head.number = 2, 1; mark(tail, 'w')
        elseif handler == 10 then
          head.person = 3; tail.aspect = 1
        elseif handler == 11 then
          if number(tail, 'lookup_frame') & 0x3F ~= 0 then tail.tense = 0
          else
            local n = V(seek_down(last - 1, di, 'X'))
            mark(n, 'X'); n.verb_flags = number(n, 'verb_flags') | 8
            link(tail, n)
            tail.tense, tail.aspect, tail.short_form, tail.passive = 0, 1, 1, 1
          end
        elseif handler == 12 then
          tail.tense = 0
        elseif handler == 13 then
          head.reading = DOLZHEN
        elseif handler == 14 then
          mark(tail, 'n'); exit = 'skip'
        elseif handler == 15 then
          tail.aspect = 1
        elseif handler == 16 then
          local n = V(di + 1)
          copy_aux(n, head)
          link(tail, n)
          tail.aspect, tail.short_form, tail.passive = 1, 1, 1
        elseif handler == 17 then
          set(tail, number(head, 'tense') == 2 and 'V' or 'E')
          rebuild(); exit = 'skip'
        elseif handler == 18 then
          local n = V(seek_down(last, di, 'e'))
          if number(n, 'marker') == 0x6E then set(n, 'E'); rebuild(); exit = 'skip'
          else n.tense = 0 end
        elseif handler == 19 then
          local n = V(last - 1)
          if number(n, 'tense') ~= 0 then n.aspect = 1 end
        elseif handler == 20 then
          if tag(head) == 'Y' then
            local n = V(last - 1)
            copy_aux(n, head); link(tail, n)
          else
            mark(head, 'X'); link(tail, head)
          end
          tail.aspect, tail.short_form, tail.passive = 1, 1, 1
        elseif handler == 21 then
          mark(head, 'X'); link(tail, head)
          if tag(tail) == 'E' then tail.verb_flags = number(tail, 'verb_flags') | 1 end
          tail.tense = 0; tail.verb_flags = number(tail, 'verb_flags') | 8; tail.person = 3
        elseif handler == 22 or handler == 23 then
          if handler == 22 then tail.verb_flags = number(tail, 'verb_flags') | 1 end
          tail.number, tail.tense, tail.person = number(head, 'number'), number(head, 'tense'), number(head, 'person')
        elseif handler == 24 then
          if tag(head) == 'Y' then tail.aspect, tail.tense = 1, 1
          else
            tail.tense = number(head, 'tense')
            if number(head, 'tense') == 2 then
              tail.person, tail.aspect = number(head, 'person'), 1
              mark(head, 'X'); link(tail, head)
            elseif number(head, 'tense') < 3 then
              set(tail, reading(tail, 'A') and 'A' or 'N')
              tail.case_mask = 0
              rebuild(); exit = 'skip'
            end
          end
        elseif handler == 25 then
          local c = initial(head)
          if c == 'd' or c == 'D' then
            tail.tense = number(head, 'tense')
            if tag(tail) == 'P' then tail.case_mask = 8 end
          else exit = 'skip' end
        elseif handler == 26 then
          if initial(head) == 'b' then exit = 'skip'
          else
            local following = tag(V(last + 1))
            if number(tail, 'lookup_frame') & 0x3F ~= 3 and ('C,)BJSDP'):find(following, 1, true) then
              tail.verb_flags = number(tail, 'verb_flags') | 1
              tail.tense = number(head, 'tense')
            else
              tail.lookup_frame = number(tail, 'lookup_frame') & 0xC0
              tail.aspect, tail.passive, tail.short_form = 1, 1, 1
              if number(head, 'tense') ~= 0 then mark(head, 'X'); link(tail, head) end
              tail.number = number(head, 'number')
            end
            tail.person = number(head, 'person')
          end
        elseif handler == 27 then
          set(head, 'r')
          local n = V(di + 1)
          if number(n, 'tense') ~= 0 then set(n, 'x'); n.tense = 1
          else
            set(n, 'y'); n.case_mask = 0
            if tag(tail) == 'O' and number(tail, 'aspect') ~= 0 then
              set(tail, 'y'); tail.case_mask = 2; set(V(last - 1), ' ')
            end
          end
          rebuild(); exit = 'skip'
        elseif handler == 28 then
          set(tail, 'V'); tail.tense, tail.gender, tail.person = 0, 1, 3
          tail.verb_flags = number(tail, 'verb_flags') | 1
          rebuild(); exit = 'skip'
        elseif handler == 29 then
          tail.verb_flags = number(tail, 'verb_flags') | 5; tail.tense = 0
        elseif handler == 30 then
          head.person = 3
          if tag(tail) == 'X' then tail.person = 3 end
        elseif handler == 31 then
          if number(head, 'aspect') == 0 then exit = 'skip'
          elseif tag(tail) ~= 'G' then tail.tense = 0; tail.verb_flags = number(tail, 'verb_flags') | 1 end
        elseif handler == 32 then
          tail.source = head.source; tail.reading = head.reading
        elseif handler == 33 then
          tail.tense = 0
        elseif handler == 35 then
          tail.verb_flags = number(tail, 'verb_flags') | 2
        elseif handler == 38 then
          tail.verb_flags = number(tail, 'verb_flags') | 0x10; mark(tail, 'r')
        elseif handler == 41 then
          V(last - 1).reading = ''
        elseif handler == 42 then
          if number(head, 'marker') == 0x2F or tag(V(di - 1)) == 'H' or tag(V(di + 1)) == 'H' then exit = 'step2' end
        elseif handler == 43 then
          tail.aspect = 1
        elseif handler == 44 then
          tail.aspect, tail.passive = 1, 1
        elseif handler == 45 then
          V(seek_down(last, di, 'e')).tense = 0
        elseif handler == 47 then
          local n = V(seek_down(last, di, 'E'))
          n.aspect, n.passive = 1, 1
        elseif handler == 48 then
          if initial(head) == 'b' then exit = 'skip'
          else
            local a = number(tail, 'lookup_frame') & 0x3F
            if a ~= 0 and a ~= 3 then
              set(tail, 'v'); tail.tense, tail.number, tail.person = number(head, 'tense'), 1, 3
              set(head, ' ')
              rebuild() -- native leaves DS:C7B1 unchanged here
            end
            exit = 'finish'
          end
        elseif handler == 49 then
          if number(tail, 'lookup_frame') & 0x3F == 0 then exit = 'finish'
          else
            mark(head, 'X'); link(tail, head)
            tail.tense = 0; tail.verb_flags = number(tail, 'verb_flags') | 8
            -- Both writes go through the +62 link, i.e. to head.
            tail.aux.number, tail.aux.person = 1, 3
          end
        elseif handler == 50 then
          if di == 1 then head.verb_flags = number(head, 'verb_flags') | 0x10 end
          head.person = number(V(di + 1), 'person'); tail.aspect = 1
        elseif handler == 51 then
          local before_tail, before_head = V(last - 1), vector[di - 1]
          if before_head then
            local following = head.next
            if tag(following) == 'K' then before_head.next = following.next; following.next = tail
            else before_head.next = head.next; head.next = tail end
            before_tail.next = head
          end
          last = count
          count = rebuild()
          exit = 'skip'
        elseif handler == 52 then
          if di == 1 then tail.prefix = NEUZHELI end
          nodes.swap(V(di - 1), V(di), V(di + 1), V(di + 2))
          vector[di], vector[di + 2] = vector[di + 2], vector[di]
          count = rebuild(); exit = 'finish'
        elseif handler == 53 then
          head.prefix = NE
          count = rebuild(); exit = 'finish'
        elseif handler == 54 then
          if number(head, 'tense') == 2 then
            local before_tail, before_head = V(last - 1), vector[di - 1]
            if before_head then
              before_head.next = head.next; head.next = tail; before_tail.next = head
              count = rebuild()
            end
            exit = 'skip'
          else exit = 'step' end
        elseif handler == 56 then
          if number(head, 'previous_tag') == 0x47 then exit = 'skip' end
        elseif handler == 57 then
          if number(head, 'case_mask') ~= 2 then exit = 'skip'
          elseif tag(tail) == 'G' then mark(tail, 'g') end
        elseif handler == 58 then
          if number(head, 'marker') == 0x77 then exit = 'skip'
          elseif tag(head) == 'T' then head.reading_state = 0
          elseif tag(V(di + 1)) == 'T' then V(di + 1).reading_state = 0 end
        elseif handler == 59 then
          if di <= 2 and tag(V(di - 1)) ~= 'B' then
            local i = last - 1
            while i >= di and tag(vector[i]) ~= 'S' do
              local n = V(i)
              if tag(n) == 'Z' and not ('CAO'):find(tag(V(i + 1)), 1, true) then set(n, 'N') end
              if tag(n) == 'G' or tag(n) == 'E' then mark(n, 'n') end
              i = i - 1
            end
            rebuild()
          end
          exit = 'finish'
        elseif handler == 60 then
          local i = di
          while i < last and tag(vector[i]) ~= '*' do
            local n = V(i)
            if tag(head) ~= 'E' and tag(n) == 'G' then mark(n, 'n') end
            if tag(n) == 'e' then mark(n, 'n') end
            i = i + 1
          end
          rebuild(); exit = 'finish'
        elseif handler == 61 then
          local i = di + 1
          while i < last and tag(vector[i]) ~= 'S' do
            local n = V(i)
            if tag(n) == 'Z' and tag(V(i - 1)) ~= 'C' and tag(V(i - 2)) ~= ',' then
              if number(n, 'lookup_frame') & 0x3F == 1 or not reading(n, 'N') then set(n, 'A') else set(n, 'N') end
            end
            if (tag(head) == 'X' or tag(head) == 'Y') and tag(n) == 'G' then mark(n, 'n') end
            if tag(n) == 'E' then mark(n, 'n') end
            i = i + 1
          end
          rebuild(); exit = 'skip'
        end
        if exit == 'default' then
          removed = matching.replace(vector, di, last, pattern, action, state)
          di = last + 1
        elseif exit == 'skip' then di = last + 1
        elseif exit == 'finish' then di = count + 1
        elseif exit == 'step' then di = di + 1
        elseif exit == 'step2' then di = di + 2
        end
      end
    end
    if removed ~= 0 then count = rebuild(); removed = 0 end
  end
  return {root = root, vector = vector, count = count, tags = state.tags, events = events}
end

-- LTPRO 0E1F:1B10..2D77, file 13700..14177: native T3 scheduling and handlers.
-- Runs over table nodes after grammar.second.
-- `count` models DS:C7B1, which most native handler rebuilds leave unchanged.
-- 0000:3DB0 folds ASCII a-z before comparing.
local function same_word(n, literal) return (number(n, 'source') and (n.source or '') or ''):upper() == literal:upper() end
local function perfective(n) return (number(n, 'lookup_frame') >> 6) & 1 end
local function frame(n) return number(n, 'lookup_flags') & 0x3F end
local CHTOBY = encoding.encode('чтобы')

function grammar.third(root, options)
  options = options or {}
  local vector, count, state
  local events = {}
  local function rebuild()
    local n
    vector, n, state = nodes.rebuild(root)
    return n
  end
  count = rebuild()
  if options.count then count = options.count end
  local function V(i)
    return assert(vector[i], 'native T3 read beyond lexical vector at ' .. i)
  end
  local function seek_down(from, di, c)
    local i = from
    while i >= di and tag(vector[i]) ~= c do i = i - 1 end
    return i
  end
  local removed = 0
  for index, rule in ipairs(options.rules or rules[3]) do
    local handler, pattern, action = table.unpack(rule)
    pattern = encoding.encode(pattern)
    action = action and encoding.encode(action)
    local di = 1
    while count - 1 > di do
      local last = vector[di] and matching.match(vector, di, pattern, state.tags) or 0
      if not vector[di] then
        events[#events + 1] = {rule = index, handler = handler, first = di, stale = true}
      end
      if last == 0 then
        di = di + 1
      else
        local head, tail = V(di), V(last)
        local back = 0
        events[#events + 1] = {rule = index, handler = handler, first = di, last = last}
        if options.on_match then options.on_match(events[#events], vector, count, state.tags) end
        -- Exits: 'default' = 14104 replacement; 'skip' = 1380E (di=last);
        -- 'finish' = 1405F (di=count); 'rebuild' = 13976 (rebuild, then skip).
        local exit = 'default'
        if handler == 1 then
          if number(tail, 'person') == 0 then
            if tag(V(last - 1)) ~= 'K' then tail.aspect = 1 end
            tail.verb_flags = number(tail, 'verb_flags') | 4
          end
          tail.number = 0
        elseif handler == 3 then
          if frame(head) ~= 0 and same_word(V(di + 1), 'that') then exit = 'skip'
          elseif number(V(di + 1), 'marker') == 0x77 then exit = 'skip' end
        elseif handler == 4 then
          if number(tail, 'previous_tag') ~= 0x65 then exit = 'skip'
          else tail.aspect = 1; tail.verb_flags = number(tail, 'verb_flags') | 4 end
        elseif handler == 5 then
          tail.verb_flags = number(tail, 'verb_flags') | 1; tail.tense = 0
        elseif handler == 6 then
          if tag(tail) == 'Z' then set(tail, 'V') end
          rebuild()
          if frame(head) == 0 and perfective(head) == 0 then exit = 'skip'
          elseif frame(head) ~= 0 then
            local n = V(di + 1)
            if tag(n) == 'M' then set(n, 'R'); n.case_mask = 0; rebuild() end
            exit = 'skip'
          else
            if tag(V(di + 1)) == 'R' then set(V(di + 1), 'M') end
            -- The descending B search never tests V[di] itself.
            local i = last - 1
            while i > di and tag(vector[i]) ~= 'B' do i = i - 1 end
            set(V(i), 'b')
            exit = 'rebuild'
          end
        elseif handler == 7 then
          if perfective(head) == 0 then exit = 'skip' end
        elseif handler == 8 then
          if tag(tail) == 'Z' then set(tail, 'V') end
          if perfective(head) == 0 or number(head, 'marker') == 0x6E then exit = 'rebuild' end
        elseif handler == 9 then
          if number(head, 'passive') ~= 0 or number(head, 'verb_flags') ~= 0 then exit = 'skip'
          elseif perfective(head) == 0 then
            if reading(tail, 'N') then set(tail, 'N'); mark(tail, 'g'); rebuild() end
            exit = 'skip'
          end
        elseif handler == 10 then
          if frame(head) == 0 or tag(V(last + 1)) == '*' then
            if tag(head) == 'E' and number(head, 'marker') ~= 0 and number(tail, 'marker') == 0x77 then
              set(head, 'V'); head.aspect = 1; rebuild()
            end
            exit = 'skip'
          elseif frame(head) == 2 and tag(tail) == 'S' then
            tail.reading = CHTOBY; tail.tense = 1
          end
        elseif handler == 11 then
          if number(head, 'tense') ~= 2 then exit = 'skip' else tail.tense, tail.person = 2, 3 end
        elseif handler == 12 then
          if number(head, 'tense') > 1 then
            tail.aspect = 1
            tail.tense, tail.number, tail.person = number(head, 'tense'), number(head, 'number'), number(head, 'person')
          else set(tail, 'A'); exit = 'rebuild' end
        elseif handler == 13 then
          if perfective(head) == 0 then exit = 'skip' end
        elseif handler == 14 then
          if number(tail, 'number') ~= 0 then set(tail, 'N'); rebuild(); exit = 'finish' end
        elseif handler == 16 then
          local i = di + 1
          while last - 1 > i and tag(vector[i]) ~= 'Z' do i = i + 1 end
          if number(V(i), 'number') == number(V(i - 1), 'number') then exit = 'skip' end
        elseif handler == 17 then
          local n = V(seek_down(last, di, 'E'))
          n.aspect, n.passive = 1, 1
        elseif handler == 18 then
          if same_word(tail, 'that') or reading(V(di + 1), 'P') then exit = 'skip' end
        elseif handler == 19 then
          local i = seek_down(last, di, 'G')
          if i ~= di then mark(V(i), 'g') end
        elseif handler == 20 then
          local t = tag(tail)
          if t == 'L' or t == 'J' or number(tail, 'previous_tag') == 0x57 or number(tail, 'marker') == 0x77 then exit = 'skip' end
        elseif handler == 21 then
          if tag(head) == 'L' or tag(head) == 'J' then exit = 'skip' end
        elseif handler == 24 then
          if number(head, 'case_mask') == 0 then exit = 'skip' else head.tense = 2 end
        elseif handler == 25 then
          tail.tense = 2
        elseif handler == 26 then
          if number(head, 'previous_tag') ~= number(tail, 'tag') then exit = 'skip' end
        elseif handler == 27 then
          if number(head, 'marker') ~= 0x67 then exit = 'skip' end
        elseif handler == 28 then
          head.case_mask = 4; head.reading = ''
        elseif handler == 29 then
          tail.aspect = 0
        elseif handler == 30 then
          if tag(V(di - 1)) == 'A' then exit = 'skip'
          else
            if not same_word(head, 'without') and not same_word(head, 'by') then
              set(tail, 'N'); mark(tail, 'g')
            end
            if same_word(head, 'by') then
              local i = last
              while i > di and tag(vector[i]) ~= 'P' do
                if tag(vector[i]) == 'G' then set(vector[i], 'g') end
                i = i - 1
              end
            end
            exit = 'rebuild'
          end
        elseif handler == 31 then
          if reading(V(last - 1), 'J') then exit = 'skip' end
        elseif handler == 32 then
          back = 2
        elseif handler == 34 then
          if same_word(head, 'the') then set(tail, 'N'); count = rebuild(); exit = 'skip'
          elseif number(head, 'number') == number(tail, 'number') then exit = 'skip' end
        elseif handler == 35 then
          local i = di + 1
          while i < last and tag(vector[i]) ~= 'Z' do i = i + 1 end
          if number(V(i), 'number') == number(head, 'number') then exit = 'finish' end
        elseif handler == 36 then
          tail.case_mask = 8
        elseif handler == 37 then
          if options.terminator == 0x3F then exit = 'finish' end
        elseif handler == 39 then
          if frame(head) ~= 0 then exit = 'skip' end
        elseif handler == 41 then
          if perfective(head) == 0 then set(tail, 'N'); exit = 'rebuild' end
        elseif handler == 42 then
          if perfective(head) == 0 then set(head, 'N'); exit = 'rebuild' end
        elseif handler == 43 then
          tail.tense = 0
        elseif handler == 44 then
          V(last - 1).tense = 0
        elseif handler == 46 then
          tail.aspect = 1
        elseif handler == 48 then
          if number(head, 'case_mask') == 0 then exit = 'skip' end
        elseif handler == 49 then
          if number(V(last - 1), 'marker') ~= 0 then exit = 'skip' end
        elseif handler == 50 then
          if number(V(di + 1), 'marker') ~= 0 then exit = 'skip' end
        elseif handler == 58 then
          local i = di + 1
          while i < last and tag(vector[i]) ~= '*' do
            if tag(vector[i]) == 'G' then mark(vector[i], 'n') end
            i = i + 1
          end
          rebuild(); exit = 'finish'
        elseif handler == 59 then
          local i = di + 1
          while i < last and tag(vector[i]) ~= '*' do
            local n = vector[i]
            if (tag(head) == 'X' or tag(head) == 'Y') and tag(n) == 'G' then mark(n, 'n') end
            if tag(n) == 'E' then mark(n, 'n') end
            i = i + 1
          end
          exit = 'rebuild'
        end
        if exit == 'default' then
          removed = matching.replace(vector, di, last, pattern, action, state)
          di = last - back + 1
        elseif exit == 'skip' then di = last + 1
        elseif exit == 'rebuild' then rebuild(); di = last + 1
        elseif exit == 'finish' then di = count + 1
        end
      end
    end
    if removed ~= 0 then count = rebuild(); removed = 0 end
  end
  return {root = root, vector = vector, count = count, tags = state.tags, events = events}
end

return grammar
