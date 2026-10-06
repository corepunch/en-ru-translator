-- LTPRO 0E1F:095A..1B10, file 1254A..13700: native T2 scheduling and handlers.
-- Runs over native nodes after first_pass; never falls back to the legacy parser.
-- Field offsets are the original record offsets. `count` models DS:C7B1, which
-- several native handlers leave stale after their own vector rebuild.
local nodes = require 'core.ltpro.nodes'
local matcher = require 'core.ltpro.matcher'
local replacement = require 'core.ltpro.replacement'
local rules = require 'core.rules'
local encoding = require 'core.encoding'
local second_pass = {}
local function byte(n, at) return n and n[at] or 0 end
local function tag(n) return string.char(byte(n, 0x0C)) end
local function set(n, c) assert(n, 'missing native node')[0x0C] = c:byte() end
local function mark(n, c) assert(n, 'missing native node')[0x0F] = c:byte() end
-- strrchr on the +98 pointer, which addresses the record's own +11C translation.
local function reading(n, c) return (assert(n, 'missing native node')[0x11C] or ''):find(c, 1, true) ~= nil end
local function initial(n) return (n[0x12] or ''):sub(1, 1) end
local function link(tail, target) tail.aux = assert(target, 'missing native node') end
local DOLZHEN = encoding.encode('должен')
local NEUZHELI = encoding.encode('неужели ')
local NE = encoding.encode('не ')

function second_pass.run(root, options)
  options = options or {}
  local vector, count, state
  local events = {}
  local function rebuild()
    local n
    vector, n = nodes.vector(root)
    local tags = {}
    for i = 0, n - 1 do tags[#tags + 1] = tag(vector[i]) end
    state = {tags = table.concat(tags)}
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
    target[0x72], target[0x73], target[0x74] = byte(head, 0x72), 1, byte(head, 0x74)
    mark(target, 'X')
  end
  local removed = 0
  for index, rule in ipairs(options.rules or rules[2]) do
    local handler, pattern, action = table.unpack(rule)
    pattern = encoding.encode(pattern)
    action = action and encoding.encode(action)
    local di = 1
    while count - 1 > di do
      local last = vector[di] and matcher.match(vector, di, pattern, state.tags) or 0
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
          if byte(V(di + 1), 0x72) ~= 0 then exit = 'skip' end
        elseif handler == 2 then
          local i = seek_down(last, di, 'G')
          local n = V(i)
          if byte(n, 0x66) ~= 0x56 then
            if reading(n, 'A') then set(n, 'A') end
            if reading(n, 'N') then set(n, 'N'); mark(n, 'g') end
            rebuild()
          end
          exit = 'skip'
        elseif handler == 3 then
          local n = V(seek_down(last, di, 'G'))
          if reading(n, 'N') then mark(n, 'g') else exit = 'skip' end
        elseif handler == 5 then
          tail[0x78] = byte(tail, 0x78) | 1; tail[0x73] = 0; tail[0x74] = 3; mark(tail, 'J')
        elseif handler == 6 then
          if byte(head, 0x73) < 2 then exit = 'skip' end
        elseif handler == 7 then
          if byte(tail, 0x72) == 0 then exit = 'skip' end
        elseif handler == 8 then
          head[0x78] = byte(head, 0x78) | 1
        elseif handler == 9 then
          head[0x76], head[0x72] = 2, 1; mark(tail, 'w')
        elseif handler == 10 then
          head[0x74] = 3; tail[0x75] = 1
        elseif handler == 11 then
          if byte(tail, 0x6A) & 0x3F ~= 0 then tail[0x73] = 0
          else
            local n = V(seek_down(last - 1, di, 'X'))
            mark(n, 'X'); n[0x78] = byte(n, 0x78) | 8
            link(tail, n)
            tail[0x73], tail[0x75], tail[0x7B], tail[0x7A] = 0, 1, 1, 1
          end
        elseif handler == 12 then
          tail[0x73] = 0
        elseif handler == 13 then
          head[0x11C] = DOLZHEN
        elseif handler == 14 then
          mark(tail, 'n'); exit = 'skip'
        elseif handler == 15 then
          tail[0x75] = 1
        elseif handler == 16 then
          local n = V(di + 1)
          copy_aux(n, head)
          link(tail, n)
          tail[0x75], tail[0x7B], tail[0x7A] = 1, 1, 1
        elseif handler == 17 then
          set(tail, byte(head, 0x73) == 2 and 'V' or 'E')
          rebuild(); exit = 'skip'
        elseif handler == 18 then
          local n = V(seek_down(last, di, 'e'))
          if byte(n, 0x0F) == 0x6E then set(n, 'E'); rebuild(); exit = 'skip'
          else n[0x73] = 0 end
        elseif handler == 19 then
          local n = V(last - 1)
          if byte(n, 0x73) ~= 0 then n[0x75] = 1 end
        elseif handler == 20 then
          if tag(head) == 'Y' then
            local n = V(last - 1)
            copy_aux(n, head); link(tail, n)
          else
            mark(head, 'X'); link(tail, head)
          end
          tail[0x75], tail[0x7B], tail[0x7A] = 1, 1, 1
        elseif handler == 21 then
          mark(head, 'X'); link(tail, head)
          if tag(tail) == 'E' then tail[0x78] = byte(tail, 0x78) | 1 end
          tail[0x73] = 0; tail[0x78] = byte(tail, 0x78) | 8; tail[0x74] = 3
        elseif handler == 22 or handler == 23 then
          if handler == 22 then tail[0x78] = byte(tail, 0x78) | 1 end
          tail[0x72], tail[0x73], tail[0x74] = byte(head, 0x72), byte(head, 0x73), byte(head, 0x74)
        elseif handler == 24 then
          if tag(head) == 'Y' then tail[0x75], tail[0x73] = 1, 1
          else
            tail[0x73] = byte(head, 0x73)
            if byte(head, 0x73) == 2 then
              tail[0x74], tail[0x75] = byte(head, 0x74), 1
              mark(head, 'X'); link(tail, head)
            elseif byte(head, 0x73) < 3 then
              set(tail, reading(tail, 'A') and 'A' or 'N')
              tail[0x76] = 0
              rebuild(); exit = 'skip'
            end
          end
        elseif handler == 25 then
          local c = initial(head)
          if c == 'd' or c == 'D' then
            tail[0x73] = byte(head, 0x73)
            if tag(tail) == 'P' then tail[0x76] = 8 end
          else exit = 'skip' end
        elseif handler == 26 then
          if initial(head) == 'b' then exit = 'skip'
          else
            local following = tag(V(last + 1))
            if byte(tail, 0x6A) & 0x3F ~= 3 and ('C,)BJSDP'):find(following, 1, true) then
              tail[0x78] = byte(tail, 0x78) | 1
              tail[0x73] = byte(head, 0x73)
            else
              tail[0x6A] = byte(tail, 0x6A) & 0xC0
              tail[0x75], tail[0x7A], tail[0x7B] = 1, 1, 1
              if byte(head, 0x73) ~= 0 then mark(head, 'X'); link(tail, head) end
              tail[0x72] = byte(head, 0x72)
            end
            tail[0x74] = byte(head, 0x74)
          end
        elseif handler == 27 then
          set(head, 'r')
          local n = V(di + 1)
          if byte(n, 0x73) ~= 0 then set(n, 'x'); n[0x73] = 1
          else
            set(n, 'y'); n[0x76] = 0
            if tag(tail) == 'O' and byte(tail, 0x75) ~= 0 then
              set(tail, 'y'); tail[0x76] = 2; set(V(last - 1), ' ')
            end
          end
          rebuild(); exit = 'skip'
        elseif handler == 28 then
          set(tail, 'V'); tail[0x73], tail[0x77], tail[0x74] = 0, 1, 3
          tail[0x78] = byte(tail, 0x78) | 1
          rebuild(); exit = 'skip'
        elseif handler == 29 then
          tail[0x78] = byte(tail, 0x78) | 5; tail[0x73] = 0
        elseif handler == 30 then
          head[0x74] = 3
          if tag(tail) == 'X' then tail[0x74] = 3 end
        elseif handler == 31 then
          if byte(head, 0x75) == 0 then exit = 'skip'
          elseif tag(tail) ~= 'G' then tail[0x73] = 0; tail[0x78] = byte(tail, 0x78) | 1 end
        elseif handler == 32 then
          tail[0x12] = head[0x12]; tail[0x11C] = head[0x11C]
        elseif handler == 33 then
          tail[0x73] = 0
        elseif handler == 35 then
          tail[0x78] = byte(tail, 0x78) | 2
        elseif handler == 38 then
          tail[0x78] = byte(tail, 0x78) | 0x10; mark(tail, 'r')
        elseif handler == 41 then
          V(last - 1)[0x11C] = ''
        elseif handler == 42 then
          if byte(head, 0x0F) == 0x2F or tag(V(di - 1)) == 'H' or tag(V(di + 1)) == 'H' then exit = 'step2' end
        elseif handler == 43 then
          tail[0x75] = 1
        elseif handler == 44 then
          tail[0x75], tail[0x7A] = 1, 1
        elseif handler == 45 then
          V(seek_down(last, di, 'e'))[0x73] = 0
        elseif handler == 47 then
          local n = V(seek_down(last, di, 'E'))
          n[0x75], n[0x7A] = 1, 1
        elseif handler == 48 then
          if initial(head) == 'b' then exit = 'skip'
          else
            local a = byte(tail, 0x6A) & 0x3F
            if a ~= 0 and a ~= 3 then
              set(tail, 'v'); tail[0x73], tail[0x72], tail[0x74] = byte(head, 0x73), 1, 3
              set(head, ' ')
              rebuild() -- native leaves DS:C7B1 unchanged here
            end
            exit = 'finish'
          end
        elseif handler == 49 then
          if byte(tail, 0x6A) & 0x3F == 0 then exit = 'finish'
          else
            mark(head, 'X'); link(tail, head)
            tail[0x73] = 0; tail[0x78] = byte(tail, 0x78) | 8
            -- Both writes go through the +62 link, i.e. to head.
            tail.aux[0x72], tail.aux[0x74] = 1, 3
          end
        elseif handler == 50 then
          if di == 1 then head[0x78] = byte(head, 0x78) | 0x10 end
          head[0x74] = byte(V(di + 1), 0x74); tail[0x75] = 1
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
          if di == 1 then tail[0x243] = NEUZHELI end
          nodes.swap(V(di - 1), V(di), V(di + 1), V(di + 2))
          vector[di], vector[di + 2] = vector[di + 2], vector[di]
          count = rebuild(); exit = 'finish'
        elseif handler == 53 then
          head[0x243] = NE
          count = rebuild(); exit = 'finish'
        elseif handler == 54 then
          if byte(head, 0x73) == 2 then
            local before_tail, before_head = V(last - 1), vector[di - 1]
            if before_head then
              before_head.next = head.next; head.next = tail; before_tail.next = head
              count = rebuild()
            end
            exit = 'skip'
          else exit = 'step' end
        elseif handler == 56 then
          if byte(head, 0x66) == 0x47 then exit = 'skip' end
        elseif handler == 57 then
          if byte(head, 0x76) ~= 2 then exit = 'skip'
          elseif tag(tail) == 'G' then mark(tail, 'g') end
        elseif handler == 58 then
          if byte(head, 0x0F) == 0x77 then exit = 'skip'
          elseif tag(head) == 'T' then head[0x0B] = 0
          elseif tag(V(di + 1)) == 'T' then V(di + 1)[0x0B] = 0 end
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
              if byte(n, 0x6A) & 0x3F == 1 or not reading(n, 'N') then set(n, 'A') else set(n, 'N') end
            end
            if (tag(head) == 'X' or tag(head) == 'Y') and tag(n) == 'G' then mark(n, 'n') end
            if tag(n) == 'E' then mark(n, 'n') end
            i = i + 1
          end
          rebuild(); exit = 'skip'
        end
        if exit == 'default' then
          removed = replacement.apply(vector, di, last, pattern, action, state)
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

return second_pass
