-- LTPRO 0E1F:0009, file 11BF9..1254A: native T1 scheduling and handlers.
-- Development entry point over native nodes; never falls back to the legacy parser.
local nodes = require 'core.ltpro.nodes'
local matcher = require 'core.ltpro.matcher'
local replacement = require 'core.ltpro.replacement'
local rules = require 'core.rules'
local encoding = require 'core.encoding'
local first_pass = {}
local function byte(n, at) return n and n[at] or 0 end
local function tag(n) return string.char(byte(n, 0x0C)) end
local function set(n, c) assert(n, 'missing native node')[0x0C] = c:byte() end

function first_pass.run(root, options)
  options = options or {}
  local vector, count, state
  local events = {}
  local function rebuild()
    vector, count = nodes.vector(root)
    local tags = {}
    for i = 0, count - 1 do tags[#tags + 1] = tag(vector[i]) end
    state = {tags = table.concat(tags)}
  end
  rebuild()
  for i = 1, count - 2 do
    local t = tag(vector[i])
    if t == '[' or t == ']' or t == '<' or t == '>' then
      set(vector[i], '/')
      state.tags = state.tags:sub(1,i) .. '/' .. state.tags:sub(i+2)
    elseif t == '?' and (vector[i][0x12] or ''):sub(1,1) == '_' then
      set(vector[i], '_')
      state.tags = state.tags:sub(1,i) .. '_' .. state.tags:sub(i+2)
    end
  end
  for index, rule in ipairs(options.rules or rules[1]) do
    local handler, pattern, action = table.unpack(rule)
    pattern = encoding.encode(pattern)
    action = action and encoding.encode(action)
    local last = matcher.match(vector, 0, pattern, state.tags)
    if last ~= 0 then
      local head, tail, previous = vector[1], vector[last], vector[last-1]
      events[#events+1] = {rule=index, handler=handler, first=0, last=last}
      if options.on_match then options.on_match(events[#events],vector,count,state.tags) end
      local disposition = 'replace'
      if handler == 1 then
        if byte(previous,0x74) ~= 0 then set(previous,'N'); disposition='rebuild' end
      elseif handler == 2 then
        if byte(head,0x72) == byte(tail,0x72) then set(head,'O'); set(tail,'N')
        else set(tail,'V') end
        disposition='rebuild'
      elseif handler == 3 then
        if byte(previous,0x72) == 0 then disposition='skip' end
      elseif handler == 4 then
        local i=last
        while i>0 and tag(vector[i])~='Z' do i=i-1 end
        if byte(vector[i],0x72)==byte(vector[i-1],0x72) then disposition='skip' end
      elseif handler == 5 then
        local i=1
        while i<last-1 and tag(vector[i])~='Z' do i=i+1 end
        local j=i
        while j>1 and tag(vector[j])~='N' do j=j-1 end
        set(vector[i],byte(vector[i],0x72)==byte(vector[j],0x72) and 'N' or 'V')
        disposition='rebuild'
      elseif handler == 6 then
        if byte(head,0x0F)==0x77 then disposition='skip' end
      elseif handler == 7 then head[0x73]=0
      elseif handler == 8 then
        previous[0x75],previous[0x7A],previous[0x7B],previous[0x0F]=1,1,1,0x6E
        disposition='rebuild'
      elseif handler == 10 then
        for i=last-1,1,-1 do
          if ('ZEeG'):find(tag(vector[i]),1,true) then set(vector[i],'N') end
        end
        -- Native returns immediately with zero, before rebuilding its cache.
        return {root=root,vector=vector,count=count,tags=state.tags,events=events,result=0}
      elseif handler == 11 then
        if tag(head)=='E' then set(head,'A'); head[0x75],head[0x7A]=1,1 end
        local i=1
        while i<last and tag(vector[i])~='*' do
          local n=vector[i]
          -- Both native DS:2D9B and DS:2DA0 point to the literal "that".
          if tag(n)=='Z' and (vector[i-1][0x12] or ''):lower()~='that'
            and (vector[i+1][0x12] or ''):lower()~='that' then set(n,'N') end
          if tag(n)=='G' or tag(n)=='E' then n[0x0F]=0x6E end
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
          if tag(n)=='G' or tag(n)=='E' then n[0x0F]=0x6E end
          i=i+1
        end
      elseif handler == 15 then
        local i=1
        if tag(head)~='J' then
          while i<last and tag(vector[i])~='J' do i=i+1 end
        end
        if tag(vector[i])~='J' then disposition='skip'
        else
          set(vector[i],'P'); set(vector[i+1],'N'); vector[i+1][0x0F]=0x67
          local j=i+1
          while j<last and tag(vector[j])~='R' do
            local n=vector[j]
            if tag(n)=='Z' then set(n,'N') end
            if tag(n)=='G' or tag(n)=='E' then n[0x0F]=0x6E end
            if tag(n)==',' or tag(n)=='C' then set(n,'&') end
            j=j+1
          end
          disposition='rebuild'
        end
      elseif handler == 20 then
        if (previous[0x12] or ''):sub(1,1)=='_' then
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
        local removed=replacement.apply(vector,0,last,pattern,action,state)
        if removed~=0 then rebuild() end
        -- A default rewrite ends T1; it does not continue through later rules.
        break
      end
    end
  end
  if options.terminator==0x3F then
    local result=require('core.ltpro.cleanup').run(root)
    vector,count,state=result.vector,result.count,{tags=result.tags}
  end
  return {root=root,vector=vector,count=count,tags=state.tags,events=events,result=1}
end

return first_pass
