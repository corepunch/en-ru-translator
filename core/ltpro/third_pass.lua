-- LTPRO 0E1F:1B10..2D77, file 13700..14177: native T3 scheduling and handlers.
-- Runs over native nodes after second_pass; never falls back to the legacy parser.
-- `count` models DS:C7B1, which most native handler rebuilds leave unchanged.
local nodes = require 'core.ltpro.nodes'
local matcher = require 'core.ltpro.matcher'
local replacement = require 'core.ltpro.replacement'
local rules = require 'core.rules'
local encoding = require 'core.encoding'
local third_pass = {}
local function byte(n, at) return n and n[at] or 0 end
local function tag(n) return string.char(byte(n, 0x0C)) end
local function set(n, c) assert(n, 'missing native node')[0x0C] = c:byte() end
local function mark(n, c) assert(n, 'missing native node')[0x0F] = c:byte() end
local function reading(n, c) return (assert(n, 'missing native node')[0x11C] or ''):find(c, 1, true) ~= nil end
-- 0000:3DB0 folds ASCII a-z before comparing.
local function same_word(n, literal) return (byte(n, 0x12) and (n[0x12] or '') or ''):upper() == literal:upper() end
local function perfective(n) return (byte(n, 0x6A) >> 6) & 1 end
local function frame(n) return byte(n, 0x68) & 0x3F end
local CHTOBY = encoding.encode('чтобы')

function third_pass.run(root, options)
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
      local last = vector[di] and matcher.match(vector, di, pattern, state.tags) or 0
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
          if byte(tail, 0x74) == 0 then
            if tag(V(last - 1)) ~= 'K' then tail[0x75] = 1 end
            tail[0x78] = byte(tail, 0x78) | 4
          end
          tail[0x72] = 0
        elseif handler == 3 then
          if frame(head) ~= 0 and same_word(V(di + 1), 'that') then exit = 'skip'
          elseif byte(V(di + 1), 0x0F) == 0x77 then exit = 'skip' end
        elseif handler == 4 then
          if byte(tail, 0x66) ~= 0x65 then exit = 'skip'
          else tail[0x75] = 1; tail[0x78] = byte(tail, 0x78) | 4 end
        elseif handler == 5 then
          tail[0x78] = byte(tail, 0x78) | 1; tail[0x73] = 0
        elseif handler == 6 then
          if tag(tail) == 'Z' then set(tail, 'V') end
          rebuild()
          if frame(head) == 0 and perfective(head) == 0 then exit = 'skip'
          elseif frame(head) ~= 0 then
            local n = V(di + 1)
            if tag(n) == 'M' then set(n, 'R'); n[0x76] = 0; rebuild() end
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
          if perfective(head) == 0 or byte(head, 0x0F) == 0x6E then exit = 'rebuild' end
        elseif handler == 9 then
          if byte(head, 0x7A) ~= 0 or byte(head, 0x78) ~= 0 then exit = 'skip'
          elseif perfective(head) == 0 then
            if reading(tail, 'N') then set(tail, 'N'); mark(tail, 'g'); rebuild() end
            exit = 'skip'
          end
        elseif handler == 10 then
          if frame(head) == 0 or tag(V(last + 1)) == '*' then
            if tag(head) == 'E' and byte(head, 0x0F) ~= 0 and byte(tail, 0x0F) == 0x77 then
              set(head, 'V'); head[0x75] = 1; rebuild()
            end
            exit = 'skip'
          elseif frame(head) == 2 and tag(tail) == 'S' then
            tail[0x11C] = CHTOBY; tail[0x73] = 1
          end
        elseif handler == 11 then
          if byte(head, 0x73) ~= 2 then exit = 'skip' else tail[0x73], tail[0x74] = 2, 3 end
        elseif handler == 12 then
          if byte(head, 0x73) > 1 then
            tail[0x75] = 1
            tail[0x73], tail[0x72], tail[0x74] = byte(head, 0x73), byte(head, 0x72), byte(head, 0x74)
          else set(tail, 'A'); exit = 'rebuild' end
        elseif handler == 13 then
          if perfective(head) == 0 then exit = 'skip' end
        elseif handler == 14 then
          if byte(tail, 0x72) ~= 0 then set(tail, 'N'); rebuild(); exit = 'finish' end
        elseif handler == 16 then
          local i = di + 1
          while last - 1 > i and tag(vector[i]) ~= 'Z' do i = i + 1 end
          if byte(V(i), 0x72) == byte(V(i - 1), 0x72) then exit = 'skip' end
        elseif handler == 17 then
          local n = V(seek_down(last, di, 'E'))
          n[0x75], n[0x7A] = 1, 1
        elseif handler == 18 then
          if same_word(tail, 'that') or reading(V(di + 1), 'P') then exit = 'skip' end
        elseif handler == 19 then
          local i = seek_down(last, di, 'G')
          if i ~= di then mark(V(i), 'g') end
        elseif handler == 20 then
          local t = tag(tail)
          if t == 'L' or t == 'J' or byte(tail, 0x66) == 0x57 or byte(tail, 0x0F) == 0x77 then exit = 'skip' end
        elseif handler == 21 then
          if tag(head) == 'L' or tag(head) == 'J' then exit = 'skip' end
        elseif handler == 24 then
          if byte(head, 0x76) == 0 then exit = 'skip' else head[0x73] = 2 end
        elseif handler == 25 then
          tail[0x73] = 2
        elseif handler == 26 then
          if byte(head, 0x66) ~= byte(tail, 0x0C) then exit = 'skip' end
        elseif handler == 27 then
          if byte(head, 0x0F) ~= 0x67 then exit = 'skip' end
        elseif handler == 28 then
          head[0x76] = 4; head[0x11C] = ''
        elseif handler == 29 then
          tail[0x75] = 0
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
          elseif byte(head, 0x72) == byte(tail, 0x72) then exit = 'skip' end
        elseif handler == 35 then
          local i = di + 1
          while i < last and tag(vector[i]) ~= 'Z' do i = i + 1 end
          if byte(V(i), 0x72) == byte(head, 0x72) then exit = 'finish' end
        elseif handler == 36 then
          tail[0x76] = 8
        elseif handler == 37 then
          if options.terminator == 0x3F then exit = 'finish' end
        elseif handler == 39 then
          if frame(head) ~= 0 then exit = 'skip' end
        elseif handler == 41 then
          if perfective(head) == 0 then set(tail, 'N'); exit = 'rebuild' end
        elseif handler == 42 then
          if perfective(head) == 0 then set(head, 'N'); exit = 'rebuild' end
        elseif handler == 43 then
          tail[0x73] = 0
        elseif handler == 44 then
          V(last - 1)[0x73] = 0
        elseif handler == 46 then
          tail[0x75] = 1
        elseif handler == 48 then
          if byte(head, 0x76) == 0 then exit = 'skip' end
        elseif handler == 49 then
          if byte(V(last - 1), 0x0F) ~= 0 then exit = 'skip' end
        elseif handler == 50 then
          if byte(V(di + 1), 0x0F) ~= 0 then exit = 'skip' end
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
          removed = replacement.apply(vector, di, last, pattern, action, state)
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

return third_pass
