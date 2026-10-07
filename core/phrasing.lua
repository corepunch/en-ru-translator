local nodes = require 'core.nodes'
local matching = require 'core.matching'
local rules = require 'core.rules'
local encoding = require 'core.encoding'

local phrasing = {}

-- LTPRO 108F:000F, file 142FF..1608F: the separate T4 function. It rebuilds the
-- vector, rewrites N readings from cached-tag contexts, applies per-word
-- sub-rules (node.rules, from `word pattern*$action` dictionary records), then
-- runs its 9-byte-record rule table from position 0 with a rebuild after each
-- removing match.
local byte, tag, set, mark = nodes.byte, nodes.tag, nodes.set_tag, nodes.set_marker
local reading = nodes.has_reading
local function same_word(n, literal) return (n[0x12] or ''):upper() == literal:upper() end
local function same_text(n, literal) return (n[0x11C] or ''):upper() == literal:upper() end
local function perfective(n) return (byte(n, 0x6A) >> 6) & 1 end
local function perfective68(n) return (byte(n, 0x68) >> 6) & 1 end
local function frame(n) return byte(n, 0x68) & 0x3F end
local function has(s, c) return c ~= '' and s:find(c, 1, true) ~= nil end
-- 0000:3DB0 folds a-z; the ctype test at DS:BF77 bit 0C is an ASCII letter.
local function ascii_letter(c) return c ~= '' and c:match('^[A-Za-z]') ~= nil end
local function cyrillic(c)
  local b = c:byte()
  return b and ((b > 0x7F and b < 0xB0) or (b > 0xDF and b < 0xF2))
end
local KOLICHESTVO = encoding.encode('количество')
local BYT = encoding.encode('быть')
local PRIVYKSHI = encoding.encode('привыкши')
local OBYCHNO = encoding.encode('обычно')

function phrasing.run(root, options)
  options = options or {}
  local vector, count, state
  local events = {}
  local function rebuild()
    local n
    vector, n, state = nodes.rebuild(root)
    return n
  end
  count = rebuild()
  local function V(i) return assert(vector[i], 'native T4 read beyond lexical vector at ' .. i) end
  local function cache(i) return state.tags:sub(i + 1, i + 1) end
  local function set_cache(i, c) state.tags = state.tags:sub(1, i) .. c .. state.tags:sub(i + 2) end
  local function new_boundary(t, marker, after)
    local node = nodes.boundary(t, marker, options.boundaries)
    if node and after then
      node.next = after.next
      after.next = node
      count = rebuild()
    end
  end

  -- 1432A: cached-context adjective readings.
  local di = 1
  while count - 3 >= di do
    local n = V(di)
    local step = 1
    if (byte(n, 0x0F) == 0 or (byte(n, 0x0F) == 0x67 and tag(V(di - 1)) ~= 'p'))
      and byte(n, 0x0F) ~= 0x25 and byte(n, 0x72) == 0 then
      local context = state.tags:sub(di + 1)
      if context:sub(1, 2) == 'NN' or context:sub(1, 3) == 'NAN' or context:sub(1, 3) == 'NdN'
        or context:sub(1, 3) == 'NHN' or context:sub(1, 3) == 'N-N' then
        local text = n[0x11C] or ''
        if text:find('A.', 1, true) or (reading(n, 'A') and not ascii_letter(text:sub(1, 1))) then
          set(n, 'A'); set_cache(di, 'A')
          if cache(di + 1) == 'A' then step = 3 end
        elseif byte(n, 0x0F) ~= 0x67 then step = 4 end
      end
    end
    di = di + step
  end

  -- 1450E: per-word sub-rules. Only the first backslash-separated part of the
  -- action is applied here; the second part feeds the replacement routine and
  -- the character after a second backslash selects a handler.
  local removed = 0
  local sub_result = 0
  di = 1
  while count - 1 > di do
    local head = V(di)
    local skip = byte(head, 0x0E) ~= 0x57 or not head.rules or #head.rules == 0
      or byte(head, 0x0F) == 0x77 or byte(head, 0x0F) == 0x57 or tag(head) == 'g'
    if not skip then
      local best, chosen = 0x200, nil
      for index, rule in ipairs(head.rules) do
        local finish = matching.match(vector, di + 1, rule.pattern, state.tags)
        if finish ~= 0 and finish < best then best, chosen = finish, rule end
      end
      if best ~= 0x200 then
        local action, tail_action, selector = chosen.action, nil, ''
        local cut = action:find('\\', 1, true)
        if cut then
          tail_action = action:sub(cut + 1)
          action = action:sub(1, cut - 1)
          local second = tail_action:find('\\', 1, true)
          if second then
            selector = tail_action:sub(second + 1, second + 1)
            tail_action = tail_action:sub(1, second - 1)
          end
        end
        local tail = V(best)
        events[#events + 1] = {sub_rule = true, first = di, last = best, pattern = chosen.pattern, selector = selector}
        local apply = true
        if selector == '1' then
          local n = V(best - 1); n[0x75], n[0x7A], n[0x73] = 0, 0, 0
        elseif selector == '2' then
          if byte(tail, 0x72) == 0 then apply = false end
        elseif selector == '3' then head[0x75] = 1
        elseif selector == '4' then
          if tag(V(di - 1)) == '*' then head[0x74] = 1 end
          if tag(head) == 'G' then set(head, 'V') end
        elseif selector == '5' then
          set(head, ' '); tail[0x76], tail[0x73] = 8, 1; tail[0x78] = byte(tail, 0x78) | 2
        elseif selector == '6' then head[0x76] = 4
        elseif selector == '7' then mark(tail, 'n')
        elseif selector == '8' then
          tail[0x11C] = ''
          if tag(tail) == 'P' then tail[0x76] = 4 end
        elseif selector == '9' then
          if tag(V(di - 1)) ~= 'X' then apply = false end
        elseif selector == 'a' then tail[0x75], tail[0x7A] = 1, 1
        elseif selector == 'c' then head[0x78] = byte(head, 0x78) | 2
        elseif selector == 'f' then head[0x0B] = 0
        elseif selector == 'g' then mark(tail, 'g')
        elseif selector == 'h' then tail[0x75] = 1
        elseif selector == 'n' then
          if tag(head) == 'N' then apply = false end
        elseif selector == 'r' then head[0x7A], head[0x73] = 0, 0
        end
        if apply then
          local c = action:sub(1, 1)
          if c == ' ' then removed = 1 end
          if c == '?' or c == '@' then action = action:sub(2)
          elseif c ~= '' and not cyrillic(c) then
            head[0x66] = head[0x0C]; set(head, c); set_cache(di, c)
            action = action:sub(2)
          end
          if tag(head) == 'N' and byte(head, 0x66) == 0x47 then mark(head, 'g')
          elseif byte(head, 0x0F) ~= 0x6E then mark(head, 'w') end
          if byte(tail, 0x0F) ~= 0x67 then mark(tail, 'w') end
          if action ~= '' then head[0x11C] = action end
          if tail_action and tail_action ~= '' then
            sub_result = matching.replace(vector, di + 1, best, chosen.pattern, tail_action, state)
          end
          -- The native result word keeps its previous value when no replacement runs.
          if sub_result ~= 0 then removed = 1 end
        end
      end
    end
    di = di + 1
  end
  if removed ~= 0 then count = rebuild(); removed = 0 end

  -- 14951: the 9-byte-record rule table.
  for index, rule in ipairs(options.rules or rules[4]) do
    local handler, pattern, action = table.unpack(rule)
    pattern = encoding.encode(pattern)
    action = action and encoding.encode(action)
    di = 0
    local continue = true
    while continue and count - 1 > di do
      local last = matching.match(vector, di, pattern, state.tags)
      if last == 0 then
        di = di + 1
      else
        local head, tail = V(di), V(last)
        events[#events + 1] = {rule = index, handler = handler, first = di, last = last}
        if options.on_match then options.on_match(events[#events], vector, count, state.tags) end
        -- Exits: 'default' = 1600B replacement; 'skip' = 149FE; 'finish' =
        -- 15DF0 (flag cleared, no replacement); 'finish_default' = 14CCD;
        -- 'step2' = 15171; 'at' = 15C46 (di = value, then advance).
        local exit, at = 'default', nil
        local function seek_up(from, limit, c)
          local k = from
          while k < limit and tag(vector[k]) ~= c do k = k + 1 end
          return k
        end
        if handler == 1 then
          if not reading(head, 'P') and byte(head, 0x0F) ~= 0x67 then new_boundary('t', '|', V(last - 1)) end
          exit = 'skip'
        elseif handler == 2 then
          if not (tag(head) == 'N' and byte(head, 0x0F) ~= 0x67) then
            if tag(tail) == 'P' then new_boundary('^', '^', V(last - 2))
            else new_boundary('|', '|', V(last - 1)) end
          end
          exit = 'skip'
        elseif handler == 3 then
          local n = V(seek_up(di, last, 'E'))
          if byte(n, 0x7B) == 0 then set(n, 'F'); n[0x75], n[0x7A] = 0, 1; rebuild() end
          exit = 'skip'
        elseif handler == 4 then
          set(head, 'J')
          local n = V(seek_up(di + 1, last, 'E'))
          n[0x75], n[0x7A], n[0x7B] = 1, 1, 1; mark(n, 'n')
          rebuild(); exit = 'finish'
        elseif handler == 5 then
          if byte(head, 0x0F) == 0x77 then exit = 'skip'
          elseif byte(tail, 0x72) ~= 0 then head[0x11C] = KOLICHESTVO; exit = 'skip' end
        elseif handler == 6 then
          V(last - 1)[0x73] = 1; exit = 'finish_default'
        elseif handler == 7 then
          if not tail.aux then
            if byte(tail, 0x66) ~= 0x47 then
              local n = V(di + 1)
              for _, f in ipairs({0x75, 0x73, 0x7A, 0x7B, 0x78}) do tail[f] = byte(n, f) end
            end
            if byte(tail, 0x7B) ~= 0 then tail[0x73] = 1 end
          end
          exit, at = 'at', last - 2
        elseif handler == 8 then
          if byte(head, 0x0F) == 0x6E and not has('AM,*', tag(V(di - 1))) then set(head, 'F') end
          rebuild(); exit = 'step2'
        elseif handler == 9 then
          local n = V(last - 1)
          if byte(n, 0x0F) ~= 0x6E then
            set(n, 'V'); n[0x78] = byte(n, 0x78) | 1; n[0x75], n[0x74], n[0x7A] = 1, 3, 0
            rebuild()
          end
          exit = 'finish'
        elseif handler == 10 then
          head[0x7A], head[0x75] = 1, 1
          if byte(head, 0x0F) == 0x6E then
            if has('&,C*', tag(V(di - 1))) and has('NA#?', tag(V(di + 1))) then set(head, 'A') end
            rebuild()
          end
          exit = 'step2'
        elseif handler == 11 then
          exit = 'finish_default'
        elseif handler == 12 then
          local k = di
          while last - 1 > k and tag(vector[k]) ~= 'E' do k = k + 1 end
          if byte(V(k), 0x0F) ~= 0x6E then exit = 'finish' end
        elseif handler == 13 then
          tail[0x75] = 1; exit = 'finish'
        elseif handler == 14 then
          if byte(head, 0x78) & 2 ~= 0 then tail[0x75] = 1 end
          exit = 'finish'
        elseif handler == 15 then
          if byte(head, 0x73) ~= 0 and byte(tail, 0x7A) == 0 then
            tail[0x73] = byte(head, 0x73)
            if byte(head, 0x73) == 2 then tail[0x75] = 1 end
            if tag(tail) == 'X' and not same_text(tail, '-') then tail[0x11C] = BYT end
          end
          exit = 'skip'
        elseif handler == 16 then
          if byte(head, 0x73) ~= 1 then exit = 'finish' end
        elseif handler == 17 or handler == 45 then
          local k = 1
          while last - 1 > k and tag(vector[k]) ~= '*' do
            local n = V(k)
            if tag(n) == 'G' and reading(n, 'N') then set(n, 'N'); mark(n, 'g') end
            k = k + 1
          end
          rebuild(); exit = 'finish'
        elseif handler == 18 then
          if di == 1 then set(head, ' ')
          else
            local c = (head[0x12] or ''):sub(1, 1)
            if (c == 'i' or c == 'I') and byte(head, 0x73) == 0 then head[0x11C] = '-'; head[0x0B] = 3 end
          end
          exit = 'step2'
        elseif handler == 19 then
          tail[0x7A], tail[0x75], tail[0x74], tail[0x73] = 0, 1, 3, 2; exit = 'finish_default'
        elseif handler == 20 then
          if not same_word(tail, 'year') then exit = 'skip' end
        elseif handler == 21 then
          head[0x76] = 0x10; exit = 'finish_default'
        elseif handler == 22 then
          if tag(head) == 'E' and has('C,J', tag(V(di - 1))) then exit = 'skip' else head[0x75] = 0 end
        elseif handler == 23 then
          tail[0x11C] = ''; exit = 'finish_default'
        elseif handler == 24 then
          local k = last - 1
          while k > di and tag(vector[k]) ~= 'E' do k = k - 1 end
          local n = V(k)
          if perfective68(n) == 0 then exit = 'skip'
          else n[0x7A] = 0; n[0x6A] = byte(n, 0x6A) & 0xC0; exit = 'finish_default' end
        elseif handler == 25 then
          local k = last - 1
          while k > di and tag(vector[k]) ~= 'c' do k = k - 1 end
          if tag(V(k)) == 'c' then exit = 'skip' end
        elseif handler == 26 then
          tail[0x75], tail[0x73] = 1, 1; exit = 'finish_default'
        elseif handler == 27 then
          head[0x72] = 1
        elseif handler == 28 then
          local n = V(last - 1); n[0x75], n[0x73], n[0x7B], n[0x7A] = 1, 1, 1, 1
          exit = 'finish_default'
        elseif handler == 29 then
          if byte(tail, 0x74) == 0 then
            if tag(V(last - 1)) ~= 'K' then tail[0x75] = 1 end
            tail[0x78] = byte(tail, 0x78) | 4
          end
          exit = 'finish'
        elseif handler == 30 then
          local n = V(last - 1)
          if byte(n, 0x78) ~= 1 and byte(n, 0x7A) == 0 then exit = 'skip' end
        elseif handler == 31 then
          head[0x76] = byte(tail, 0x79); exit = 'finish_default'
        elseif handler == 32 then
          local moved, before, previous = V(last - 1), V(last - 2), V(di - 1)
          before.next = moved.next
          moved.next = head
          previous.next = moved
          set(head, '+')
          count = rebuild(); exit = 'skip'
        elseif handler == 33 then
          if byte(head, 0x75) == 0 then exit = 'skip' end
        elseif handler == 34 then
          if byte(V(di + 1), 0x0F) ~= 0 then exit = 'skip' end
        elseif handler == 35 then
          local k = last
          while k > di and tag(vector[k]) ~= 'd' do k = k - 1 end
          local n = V(k)
          if reading(n, 'A') and byte(n, 0x75) == 0 then exit = 'finish_default' else exit = 'skip' end
        elseif handler == 36 then
          tail[0x75] = 1
        elseif handler == 37 then
          if byte(head, 0x0F) == 0x67 then exit = 'skip' end
        elseif handler == 39 then
          if byte(head, 0x75) == 0 then exit = 'skip' end
        elseif handler == 40 then
          if byte(V(last - 1), 0x0F) ~= 0 then exit = 'skip' end
        elseif handler == 41 then
          if byte(head, 0x0F) ~= 0 or not same_word(tail, 'year') then exit = 'skip' end
        elseif handler == 42 then
          tail[0x68] = (byte(tail, 0x68) & 0xC0) | 1; exit = 'finish_default'
        elseif handler == 43 then
          if frame(head) ~= 0 then
            tail[0x75] = 1
            if frame(head) == 2 then tail[0x73] = 1 end
            set(V(last - 1), ' ')
          end
          exit = 'finish'
        elseif handler == 44 then
          if frame(head) == 0 then exit = 'skip' end
        elseif handler == 46 then
          local n = V(seek_up(di, last, 'G'))
          if byte(n, 0x0F) ~= 0x6E then exit = 'skip'
          else set(n, 'N'); mark(n, 'g'); rebuild(); exit = 'skip' end
        elseif handler == 47 then
          local k = last
          while k >= di and tag(vector[k]) ~= 'G' do k = k - 1 end
          if k ~= di then local n = V(k); set(n, 'N'); mark(n, 'g') end
          rebuild(); exit = 'finish'
        elseif handler == 48 then
          local k = di
          while k < last and tag(V(k + 1)) ~= '*' do
            local n = V(k)
            if tag(n) == 'E' then n[0x7A], n[0x75] = 1, 1; mark(n, 'n') end
            if has('C,', tag(n)) and tag(head) == 'E' then set(n, '&') end
            k = k + 1
          end
          rebuild(); exit, at = 'at', last - 1
        elseif handler == 49 then
          local k = di + 1
          while k < last do
            local n = V(k)
            if has('C,', tag(n)) then
              local following = V(k + 1)
              if not (tag(following) == 'E' and byte(following, 0x0F) ~= 0x6E) then set(n, '&') end
            end
            k = k + 1
          end
          rebuild(); exit, at = 'at', last - 1
        elseif handler == 50 then
          if tag(V(last - 1)) ~= ',' then
            local k = di + 1
            while last - 1 > k do
              local n = V(k)
              if has('C,', tag(n)) then
                local after, before = tag(V(k + 1)), tag(V(k - 1))
                if not (after == 'P' or after == 'E' or before == 'E' or after == 'F' or before == 'F'
                  or after == 'k' or after == 'Q') then set(n, '&') end
              end
              k = k + 1
            end
            rebuild()
          end
          exit = 'finish'
        elseif handler == 51 then
          if tag(tail) == '*' then
            local k = di + 1
            while last - 1 > k and tag(vector[k]) ~= '*' do
              local n = V(k)
              if has('C,', tag(n)) and tag(V(k + 1)) ~= 'P' then set(n, '&') end
              k = k + 1
            end
            rebuild(); exit = 'finish'
          else
            local width = 1
            if has('VXYU', tag(tail)) then width, last = 3, last - 1 end
            if last - width - di < 3 or (tag(V(last)) == ',' and di < 2) then
              exit, at = 'at', last - 1
            else
              local k = di + 2
              while last - width > k do
                local n = V(k)
                if has('C,', tag(n)) then
                  local after, before = tag(V(k + 1)), tag(V(k - 1))
                  if not (has('PC,GQT', after) or before == 'D' or after == 'F' or before == 'F') then set(n, '&') end
                end
                k = k + 1
              end
              rebuild(); exit, at = 'at', last - 1
            end
          end
        elseif handler == 53 then
          local n = V(seek_up(di, last, 'N'))
          local text = n[0x11C] or ''
          if ascii_letter(text:sub(1, 1)) or not reading(n, 'A') or byte(n, 0x72) ~= 0 then exit = 'skip' end
        elseif handler == 54 then
          if tag(head) == 'P' and same_word(head, 'of') then exit = 'skip'
          else
            local n = V(seek_up(di, last, 'N'))
            if reading(n, 'A') and byte(n, 0x72) == 0 and byte(tail, 0x72) ~= 0 then n[0x72] = 1
            else exit = 'skip' end
          end
        elseif handler == 55 then
          if byte(head, 0x0F) ~= 0x3D then exit = 'skip' end
        elseif handler == 56 then
          V(last - 1)[0x7B] = 1; exit = 'skip'
        elseif handler == 57 then
          if perfective(V(di + 1)) ~= 0 then V(last - 1)[0x11C] = '' end
          exit = 'finish'
        elseif handler == 58 then
          local n = V(seek_up(di + 2, last, ','))
          if tag(n) == ',' then set(n, ';'); rebuild() end
          exit = 'skip'
        elseif handler == 60 then
          if byte(head, 0x66) ~= 0x45 then
            local k = di + 1
            while k < last and tag(vector[k]) ~= '*' do
              local n = V(k)
              if tag(n) == 'E' and not has(',C+', tag(V(k - 1))) then mark(n, 'n') end
              k = k + 1
            end
          end
          rebuild(); exit = 'skip'
        elseif handler == 61 then
          if byte(head, 0x0F) == 0x77 then exit = 'skip' end
        elseif handler == 62 then
          head[0x76] = 4
        elseif handler == 66 then
          if byte(head, 0x0F) == 0x3D or tag(head) == 'R' then
            tail[0x75] = 0
            local following = assert(head.next, 'missing native next record')
            if byte(following, 0x78) == 1 then
              tail[0x74] = 0; tail[0x78] = byte(tail, 0x78) | 8
              following[0x73] = 1; following[0x11C] = PRIVYKSHI; set(following, 'V')
              following[0x7B], following[0x85] = 1, 0
            else
              following[0x11C] = OBYCHNO; set(following, 'D'); tail[0x74] = 3; head[0x73] = 0
            end
          else exit = 'skip' end
        end
        if exit == 'default' or exit == 'finish_default' then
          if action then removed = matching.replace(vector, di, last, pattern, action, state) end
          if removed ~= 0 then count = rebuild(); removed = 0 end
          di = di + 1
          if exit == 'finish_default' then continue = false end
        elseif exit == 'skip' then di = last + 1
        elseif exit == 'finish' then di = di + 1; continue = false
        elseif exit == 'step2' then di = di + 2
        elseif exit == 'at' then di = at + 1
        end
      end
    end
  end
  return {root = root, vector = vector, count = count, tags = state.tags, events = events}
end

return phrasing
