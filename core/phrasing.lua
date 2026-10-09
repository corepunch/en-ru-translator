local nodes = require 'core.nodes'
local matching = require 'core.matching'
local rules = require 'core.rules'
local encoding = require 'core.encoding'

local phrasing = {}
local values = require 'core.grammar_values'

-- LTPRO 108F:000F, file 142FF..1608F: the separate T4 function. It rebuilds the
-- vector, rewrites N readings from cached-tag contexts, applies per-word
-- sub-rules (node.rules, from `word pattern*$action` dictionary records), then
-- runs its 9-byte-record rule table from position 0 with a rebuild after each
-- removing match.
local number, tag, set, mark = nodes.number, nodes.tag, nodes.set_tag, nodes.set_marker
local reading = nodes.has_reading
local function same_word(n, literal) return (n.source or ''):upper() == literal:upper() end
local function same_text(n, literal) return (n.reading or ''):upper() == literal:upper() end
local function perfective(n) return (number(n, 'lookup_frame') >> 6) & 1 end
local function perfective68(n) return (number(n, 'lookup_flags') >> 6) & 1 end
local function frame(n) return number(n, 'lookup_flags') & 0x3F end
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

-- Selector IDs belong to the recovered rule data; handlers describe Lua edits.
local handlers = {}

handlers[1] = function(match)
  local head = match.head
  local exit = 'replace'
  if not reading(head, 'P') and number(head, 'marker') ~= 0x67 then match.new_boundary('t', '|', match.node(match.last - 1)) end
  exit = 'advance_past_match'
  return exit
end

handlers[2] = function(match)
  local head, tail = match.head, match.tail
  local exit = 'replace'
  if not (tag(head) == 'N' and number(head, 'marker') ~= 0x67) then
    if tag(tail) == 'P' then match.new_boundary('^', '^', match.node(match.last - 2))
    else match.new_boundary('|', '|', match.node(match.last - 1)) end
  end
  exit = 'advance_past_match'
  return exit
end

handlers[3] = function(match)
  local exit = 'replace'
  local n = match.node(match.seek_up(match.first, match.last, 'E'))
  if number(n, 'short_form') == 0 then set(n, 'F'); n.aspect, n.passive = 0, 1; match.rebuild() end
  exit = 'advance_past_match'
  return exit
end

handlers[4] = function(match)
  local head = match.head
  local exit = 'replace'
  set(head, 'J')
  local n = match.node(match.seek_up(match.first + 1, match.last, 'E'))
  n.aspect, n.passive, n.short_form = 1, 1, 1; mark(n, 'n')
  match.rebuild(); exit = 'stop_rule'
  return exit
end

handlers[5] = function(match)
  local head, tail = match.head, match.tail
  local exit = 'replace'
  if number(head, 'marker') == 0x77 then exit = 'advance_past_match'
  elseif number(tail, 'number') ~= 0 then head.reading = KOLICHESTVO; exit = 'advance_past_match' end
  return exit
end

handlers[6] = function(match)
  local exit = 'replace'
  match.node(match.last - 1).tense = 1; exit = 'replace_and_stop'
  return exit
end

handlers[7] = function(match)
  local tail = match.tail
  local exit, at = 'replace', nil
  if not tail.aux then
    if number(tail, 'previous_tag') ~= 0x47 then
      local n = match.node(match.first + 1)
      for _, f in ipairs({'aspect', 'tense', 'passive', 'short_form', 'verb_flags'}) do tail[f] = number(n, f) end
    end
    if number(tail, 'short_form') ~= 0 then tail.tense = 1 end
  end
  exit, at = 'advance_to', match.last - 2
  return exit, at
end

handlers[8] = function(match)
  local head = match.head
  local exit = 'replace'
  if number(head, 'marker') == 0x6E and not has('AM,*', tag(match.node(match.first - 1))) then set(head, 'F') end
  match.rebuild(); exit = 'advance_two'
  return exit
end

handlers[9] = function(match)
  local exit = 'replace'
  local n = match.node(match.last - 1)
  if number(n, 'marker') ~= 0x6E then
    set(n, 'V'); n.verb_flags = number(n, 'verb_flags') | 1; n.aspect, n.person, n.passive = 1, 3, 0
    match.rebuild()
  end
  exit = 'stop_rule'
  return exit
end

handlers[10] = function(match)
  local head = match.head
  local exit = 'replace'
  head.passive, head.aspect = 1, 1
  if number(head, 'marker') == 0x6E then
    if has('&,C*', tag(match.node(match.first - 1))) and has('NA#?', tag(match.node(match.first + 1))) then set(head, 'A') end
    match.rebuild()
  end
  exit = 'advance_two'
  return exit
end

local function replace_and_stop()
  return 'replace_and_stop'
end
local function inside_equivalent(match)
  local casing=match.head.phrase_case
  if casing then
    for i=match.first,match.last do
      if match.node(i).phrase_case~=casing then return false end
    end
    return true
  end
end
-- A node translated from a multiword dictionary key. Native T4 rereads its
-- first English word (it is cold*WDхолодно -> `it` rule -> Это); like an
-- authored W equivalent, it is not reinterpreted by lexical rules.
local function touches_literal(match)
  for i=match.first,match.last do
    if match.node(i).phrase_literal then return true end
  end
end
handlers[11] = replace_and_stop

local function stop_unmarked_participle(match)
  local position = match.seek_up(match.first, match.last - 1, 'E')
  if nodes.character(match.node(position), 'marker') ~= 'n' then return 'stop_rule' end
  return 'replace'
end
handlers[12] = stop_unmarked_participle

local function set_perfective(match)
  match.tail.aspect = values.aspect.perfective
  return 'stop_rule'
end
handlers[13] = set_perfective

local function set_perfective_if_flagged(match)
  if number(match.head, 'verb_flags') & values.verb_flags.conditional ~= 0 then
    match.tail.aspect = values.aspect.perfective
  end
  return 'stop_rule'
end
handlers[14] = set_perfective_if_flagged

local function inherit_tense(match)
  local source, target = match.head, match.tail
  local tense = source.tense or values.tense.present
  if tense ~= values.tense.present and number(target, 'passive') == 0 then
    target.tense = tense
    if tense == values.tense.future then target.aspect = values.aspect.perfective end
    if tag(target) == 'X' and not same_text(target, '-') then target.reading = BYT end
  end
  return 'advance_past_match'
end
handlers[15] = inherit_tense

local function require_past_tense(match)
  if number(match.head, 'tense') ~= values.tense.past then return 'stop_rule' end
  return 'replace'
end
handlers[16] = require_past_tense

local function resolve_gerund_nouns(match)
  local position = 1
  while position < match.last - 1 and tag(match.vector[position]) ~= '*' do
    local word = match.node(position)
    if tag(word) == 'G' and reading(word, 'N') then
      set(word, 'N')
      mark(word, 'g')
    end
    position = position + 1
  end
  match.rebuild()
  return 'stop_rule'
end
handlers[17] = resolve_gerund_nouns
handlers[45] = resolve_gerund_nouns

handlers[18] = function(match)
  local head = match.head
  local exit = 'replace'
  if match.first == 1 then set(head, ' ')
  else
    local c = (head.source or ''):sub(1, 1)
    if (c == 'i' or c == 'I') and number(head, 'tense') == 0 then head.reading = '-'; head.reading_state = 3 end
  end
  exit = 'advance_two'
  return exit
end

handlers[19] = function(match)
  local tail = match.tail
  local exit = 'replace'
  tail.passive, tail.aspect, tail.person, tail.tense = 0, 1, 3, 2; exit = 'replace_and_stop'
  return exit
end

handlers[20] = function(match)
  local tail = match.tail
  local exit = 'replace'
  if not same_word(tail, 'year') then exit = 'advance_past_match' end
  return exit
end

handlers[21] = function(match)
  local head = match.head
  local exit = 'replace'
  head.case_mask = 0x10; exit = 'replace_and_stop'
  return exit
end

handlers[22] = function(match)
  local head = match.head
  local exit = 'replace'
  if tag(head) == 'E' and has('C,J', tag(match.node(match.first - 1))) then exit = 'advance_past_match' else head.aspect = 0 end
  return exit
end

handlers[23] = function(match)
  local tail = match.tail
  local exit = 'replace'
  tail.reading = ''; exit = 'replace_and_stop'
  -- Native *`let``us` (rule 83) makes the next verb an infinitive after
  -- давайте (original "Давайте идти"). Lua improvement: the hortative is the
  -- first person plural of the perfective, "Давайте пойдем"; a verb without
  -- a perfective keeps the infinitive (Давайте работать, in generation).
  if (tail.source or ''):lower() == 'us' then
    local k = match.last + 1
    while match.vector[k] and ('DdK'):find(tag(match.vector[k]), 1, true) do k = k + 1 end
    local verb = match.vector[k]
    -- Grammar may already have read an ambiguous verb as its noun (Z reading
    -- V.работатьN.работа) or participle (read); the hortative needs the verb.
    if verb and (('VZeE'):find(tag(verb), 1, true)
        or tag(verb) == 'N' and (verb.reading or ''):sub(1, 2) == 'V.') then
      set(verb, 'V'); verb.previous_tag = 0x56
      verb.person, verb.number, verb.aspect, verb.tense = 1, 1, 1, 0
      verb.passive, verb.short_form, verb.marker = 0, 0, 0
      verb.hortative = true
    end
  end
  return exit
end

handlers[24] = function(match)
  local exit = 'replace'
  local k = match.last - 1
  while k > match.first and tag(match.vector[k]) ~= 'E' do k = k - 1 end
  local n = match.node(k)
  if perfective68(n) == 0 then exit = 'advance_past_match'
  else n.passive = 0; n.lookup_frame = number(n, 'lookup_frame') & 0xC0; exit = 'replace_and_stop' end
  return exit
end

handlers[25] = function(match)
  local exit = 'replace'
  local k = match.last - 1
  while k > match.first and tag(match.vector[k]) ~= 'c' do k = k - 1 end
  if tag(match.node(k)) == 'c' then exit = 'advance_past_match' end
  return exit
end

handlers[26] = function(match)
  local tail = match.tail
  local exit = 'replace'
  tail.aspect, tail.tense = 1, 1; exit = 'replace_and_stop'
  return exit
end

handlers[27] = function(match)
  local head = match.head
  local exit = 'replace'
  head.number = 1
  return exit
end

handlers[28] = function(match)
  local exit = 'replace'
  local n = match.node(match.last - 1); n.aspect, n.tense, n.short_form, n.passive = 1, 1, 1, 1
  exit = 'replace_and_stop'
  return exit
end

handlers[29] = function(match)
  local tail = match.tail
  local exit = 'replace'
  if number(tail, 'person') == 0 then
    if tag(match.node(match.last - 1)) ~= 'K' then tail.aspect = 1 end
    tail.verb_flags = number(tail, 'verb_flags') | 4
  end
  exit = 'stop_rule'
  return exit
end

handlers[30] = function(match)
  local exit = 'replace'
  local n = match.node(match.last - 1)
  if number(n, 'verb_flags') ~= 1 and number(n, 'passive') == 0 then exit = 'advance_past_match' end
  return exit
end

handlers[31] = function(match)
  local head, tail = match.head, match.tail
  local exit = 'replace'
  head.case_mask = number(tail, 'governed_case'); exit = 'replace_and_stop'
  return exit
end

handlers[32] = function(match)
  local head = match.head
  local exit = 'replace'
  local moved, before, previous = match.node(match.last - 1), match.node(match.last - 2), match.node(match.first - 1)
  before.next = moved.next
  moved.next = head
  previous.next = moved
  set(head, '+')
  match.count = match.rebuild(); exit = 'advance_past_match'
  return exit
end

handlers[33] = function(match)
  local head = match.head
  local exit = 'replace'
  if number(head, 'aspect') == 0 then exit = 'advance_past_match' end
  return exit
end

handlers[34] = function(match)
  local exit = 'replace'
  if number(match.node(match.first + 1), 'marker') ~= 0 then exit = 'advance_past_match' end
  return exit
end

handlers[35] = function(match)
  local exit = 'replace'
  local k = match.last
  while k > match.first and tag(match.vector[k]) ~= 'd' do k = k - 1 end
  local n = match.node(k)
  if reading(n, 'A') and number(n, 'aspect') == 0 then exit = 'replace_and_stop' else exit = 'advance_past_match' end
  return exit
end

handlers[36] = function(match)
  local tail = match.tail
  local exit = 'replace'
  tail.aspect = 1
  return exit
end

handlers[37] = function(match)
  local head = match.head
  local exit = 'replace'
  if number(head, 'marker') == 0x67 then exit = 'advance_past_match' end
  return exit
end

handlers[39] = function(match)
  local head = match.head
  local exit = 'replace'
  if number(head, 'aspect') == 0 then exit = 'advance_past_match' end
  return exit
end

handlers[40] = function(match)
  local exit = 'replace'
  if number(match.node(match.last - 1), 'marker') ~= 0 then exit = 'advance_past_match' end
  return exit
end

handlers[41] = function(match)
  local head, tail = match.head, match.tail
  local exit = 'replace'
  if number(head, 'marker') ~= 0 or not same_word(tail, 'year') then exit = 'advance_past_match' end
  return exit
end

handlers[42] = function(match)
  local tail = match.tail
  local exit = 'replace'
  tail.lookup_flags = (number(tail, 'lookup_flags') & 0xC0) | 1; exit = 'replace_and_stop'
  return exit
end

handlers[43] = function(match)
  local head, tail = match.head, match.tail
  local exit = 'replace'
  if frame(head) ~= 0 then
    tail.aspect = 1
    if frame(head) == 2 then tail.tense = 1 end
    set(match.node(match.last - 1), ' ')
  end
  exit = 'stop_rule'
  return exit
end

handlers[44] = function(match)
  local head = match.head
  local exit = 'replace'
  if frame(head) == 0 then exit = 'advance_past_match' end
  return exit
end

handlers[46] = function(match)
  local exit = 'replace'
  local n = match.node(match.seek_up(match.first, match.last, 'G'))
  if number(n, 'marker') ~= 0x6E then exit = 'advance_past_match'
  else set(n, 'N'); mark(n, 'g'); match.rebuild(); exit = 'advance_past_match' end
  return exit
end

handlers[47] = function(match)
  local exit = 'replace'
  local k = match.last
  while k >= match.first and tag(match.vector[k]) ~= 'G' do k = k - 1 end
  if k ~= match.first then local n = match.node(k); set(n, 'N'); mark(n, 'g') end
  match.rebuild(); exit = 'stop_rule'
  return exit
end

handlers[48] = function(match)
  local head = match.head
  local exit, at = 'replace', nil
  local k = match.first
  while k < match.last and tag(match.node(k + 1)) ~= '*' do
    local n = match.node(k)
    if tag(n) == 'E' then n.passive, n.aspect = 1, 1; mark(n, 'n') end
    if has('C,', tag(n)) and tag(head) == 'E' then set(n, '&') end
    k = k + 1
  end
  match.rebuild(); exit, at = 'advance_to', match.last - 1
  return exit, at
end

handlers[49] = function(match)
  local exit, at = 'replace', nil
  local k = match.first + 1
  while k < match.last do
    local n = match.node(k)
    if has('C,', tag(n)) then
      local following = match.node(k + 1)
      if not (tag(following) == 'E' and number(following, 'marker') ~= 0x6E) then set(n, '&') end
    end
    k = k + 1
  end
  match.rebuild(); exit, at = 'advance_to', match.last - 1
  return exit, at
end

handlers[50] = function(match)
  local exit = 'replace'
  if tag(match.node(match.last - 1)) ~= ',' then
    local k = match.first + 1
    while match.last - 1 > k do
      local n = match.node(k)
      if has('C,', tag(n)) then
        local after, before = tag(match.node(k + 1)), tag(match.node(k - 1))
        if not (after == 'P' or after == 'E' or before == 'E' or after == 'F' or before == 'F'
          or after == 'k' or after == 'Q') then set(n, '&') end
      end
      k = k + 1
    end
    match.rebuild()
  end
  exit = 'stop_rule'
  return exit
end

handlers[51] = function(match)
  local tail = match.tail
  local exit, at = 'replace', nil
  if tag(tail) == '*' then
    local k = match.first + 1
    while match.last - 1 > k and tag(match.vector[k]) ~= '*' do
      local n = match.node(k)
      if has('C,', tag(n)) and tag(match.node(k + 1)) ~= 'P' then set(n, '&') end
      k = k + 1
    end
    match.rebuild(); exit = 'stop_rule'
  else
    local width = 1
    if has('VXYU', tag(tail)) then width, match.last = 3, match.last - 1 end
    if match.last - width - match.first < 3 or (tag(match.node(match.last)) == ',' and match.first < 2) then
      exit, at = 'advance_to', match.last - 1
    else
      local k = match.first + 2
      while match.last - width > k do
        local n = match.node(k)
        if has('C,', tag(n)) then
          local after, before = tag(match.node(k + 1)), tag(match.node(k - 1))
          if not (has('PC,GQT', after) or before == 'D' or after == 'F' or before == 'F') then set(n, '&') end
        end
        k = k + 1
      end
      match.rebuild(); exit, at = 'advance_to', match.last - 1
    end
  end
  return exit, at
end

handlers[53] = function(match)
  local exit = 'replace'
  local n = match.node(match.seek_up(match.first, match.last, 'N'))
  local text = n.reading or ''
  if ascii_letter(text:sub(1, 1)) or not reading(n, 'A') or number(n, 'number') ~= 0 then exit = 'advance_past_match' end
  return exit
end

handlers[54] = function(match)
  local head, tail = match.head, match.tail
  local exit = 'replace'
  if tag(head) == 'P' and same_word(head, 'of') then exit = 'advance_past_match'
  else
    local n = match.node(match.seek_up(match.first, match.last, 'N'))
    if reading(n, 'A') and number(n, 'number') == 0 and number(tail, 'number') ~= 0 then n.number = 1
    else exit = 'advance_past_match' end
  end
  return exit
end

handlers[55] = function(match)
  local head = match.head
  local exit = 'replace'
  if number(head, 'marker') ~= 0x3D then exit = 'advance_past_match' end
  return exit
end

handlers[56] = function(match)
  local exit = 'replace'
  match.node(match.last - 1).short_form = 1; exit = 'advance_past_match'
  return exit
end

handlers[57] = function(match)
  local exit = 'replace'
  if perfective(match.node(match.first + 1)) ~= 0 then match.node(match.last - 1).reading = '' end
  exit = 'stop_rule'
  return exit
end

handlers[58] = function(match)
  local exit = 'replace'
  local n = match.node(match.seek_up(match.first + 2, match.last, ','))
  if tag(n) == ',' then set(n, ';'); match.rebuild() end
  exit = 'advance_past_match'
  return exit
end

handlers[60] = function(match)
  local head = match.head
  local exit = 'replace'
  if number(head, 'previous_tag') ~= 0x45 then
    local k = match.first + 1
    while k < match.last and tag(match.vector[k]) ~= '*' do
      local n = match.node(k)
      if tag(n) == 'E' and not has(',C+', tag(match.node(k - 1))) then mark(n, 'n') end
      k = k + 1
    end
  end
  match.rebuild(); exit = 'advance_past_match'
  return exit
end

handlers[61] = function(match)
  local head = match.head
  local exit = 'replace'
  if number(head, 'marker') == 0x77 then exit = 'advance_past_match' end
  return exit
end

handlers[62] = function(match)
  local head = match.head
  local exit = 'replace'
  head.case_mask = 4
  return exit
end

handlers[66] = function(match)
  local head, tail = match.head, match.tail
  local exit = 'replace'
  if number(head, 'marker') == 0x3D or tag(head) == 'R' then
    tail.aspect = 0
    local following = assert(head.next, 'missing native next record')
    if number(following, 'verb_flags') == 1 then
      tail.person = 0; tail.verb_flags = number(tail, 'verb_flags') | 8
      following.tense = 1; following.reading = PRIVYKSHI; set(following, 'V')
      following.short_form, following.paradigm = 1, 0
    else
      following.reading = OBYCHNO; set(following, 'D'); tail.person = 3; head.tense = 0
    end
  else exit = 'advance_past_match' end
  return exit
end

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
    if (number(n, 'marker') == 0 or (number(n, 'marker') == 0x67 and tag(V(di - 1)) ~= 'p'))
      and number(n, 'marker') ~= 0x25 and number(n, 'number') == 0 then
      local context = state.tags:sub(di + 1)
      if context:sub(1, 2) == 'NN' or context:sub(1, 3) == 'NAN' or context:sub(1, 3) == 'NdN'
        or context:sub(1, 3) == 'NHN' or context:sub(1, 3) == 'N-N' then
        local text = n.reading or ''
        if text:find('A.', 1, true) or (reading(n, 'A') and not ascii_letter(text:sub(1, 1))) then
          set(n, 'A'); set_cache(di, 'A')
          if cache(di + 1) == 'A' then step = 3 end
        elseif number(n, 'marker') ~= 0x67 then step = 4 end
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
    -- A node retagged ' ' was deleted by an earlier subrule in this pass;
    -- its own subrules must not resurrect it (not at all / at all).
    local skip = number(head, 'kind') ~= 0x57 or not head.rules or #head.rules == 0
      or number(head, 'marker') == 0x77 or number(head, 'marker') == 0x57 or tag(head) == 'g'
      or tag(head) == ' '
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
          local n = V(best - 1); n.aspect, n.passive, n.tense = 0, 0, 0
        elseif selector == '2' then
          if number(tail, 'number') == 0 then apply = false end
        elseif selector == '3' then head.aspect = 1
        elseif selector == '4' then
          if tag(V(di - 1)) == '*' then head.person = 1 end
          if tag(head) == 'G' then set(head, 'V') end
        elseif selector == '5' then
          set(head, ' '); tail.case_mask, tail.tense = 8, 1; tail.verb_flags = number(tail, 'verb_flags') | 2
        elseif selector == '6' then head.case_mask = 4
        elseif selector == '7' then mark(tail, 'n')
        elseif selector == '8' then
          tail.reading = ''
          if tag(tail) == 'P' then tail.case_mask = 4 end
        elseif selector == '9' then
          if tag(V(di - 1)) ~= 'X' then apply = false end
        elseif selector == 'a' then tail.aspect, tail.passive = 1, 1
        elseif selector == 'c' then head.verb_flags = number(head, 'verb_flags') | 2
        elseif selector == 'f' then head.reading_state = 0
        elseif selector == 'g' then mark(tail, 'g')
        elseif selector == 'h' then tail.aspect = 1
        elseif selector == 'n' then
          if tag(head) == 'N' then apply = false end
        elseif selector == 'r' then head.passive, head.tense = 0, 0
        end
        if apply then
          local c = action:sub(1, 1)
          if c == ' ' then removed = 1 end
          if c == '?' or c == '@' then action = action:sub(2)
          elseif c ~= '' and not cyrillic(c) then
            head.previous_tag = head.tag; set(head, c); set_cache(di, c)
            action = action:sub(2)
          end
          if tag(head) == 'N' and number(head, 'previous_tag') == 0x47 then mark(head, 'g')
          elseif number(head, 'marker') ~= 0x6E then mark(head, 'w') end
          -- Native also marks a matched comma boundary, which makes output
          -- glue the next word to it (original "Кроме того,он"). Keep the
          -- comma (tag , or clause junction j) unmarked so boundary rules keep spacing.
          if number(tail, 'marker') ~= 0x67 and not (number(tail, 'kind') == 0x44 and number(tail, 'source') == 0x2C) then
            mark(tail, 'w')
          end
          if action ~= '' then head.reading = action end
          -- A native subrule can put a W equivalent in the head or a context
          -- word. Share the phrase's casing through that later expansion, so
          -- English I does not capitalize an oblique pronoun mid-phrase.
          if chosen.action:find('W',1,true) then
            local _,caps=(head.source or ''):gsub('[A-Z]','')
            local casing={caps=caps,first=head}
            for at=di,best do V(at).phrase_case=casing end
          end
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
        local match = {
          first = di, last = last, count = count, vector = vector,
          head = head, tail = tail, node = V,
        }
        function match.new_boundary(...)
          new_boundary(...)
          match.vector, match.count = vector, count
        end
        function match.rebuild()
          local live_count = rebuild()
          -- The loop takes count back from match.count; a stale value lets a
          -- later rule read past the rebuilt vector (would like: *B[:*]).
          match.vector, match.count = vector, live_count
          return live_count
        end
        function match.seek_up(from, limit, wanted)
          local position = from
          while position < limit and tag(vector[position]) ~= wanted do
            position = position + 1
          end
          return position
        end
        local apply = handlers[handler]
        local exit, at = 'replace', nil
        -- English lexical idioms cannot reinterpret nodes already assigned to
        -- one W equivalent, including equivalents authored by an earlier T4
        -- subrule. Tag-based agreement rules still run normally.
        if pattern:find('`',1,true) and (inside_equivalent(match) or touches_literal(match)) then exit='advance_past_match'
        elseif apply then exit, at = apply(match) end
        last, count = match.last, match.count
        if exit == 'replace' or exit == 'replace_and_stop' then
          if action then removed = matching.replace(vector, di, last, pattern, action, state) end
          if removed ~= 0 then count = rebuild(); removed = 0 end
          di = di + 1
          if exit == 'replace_and_stop' then continue = false end
        elseif exit == 'advance_past_match' then di = last + 1
        elseif exit == 'stop_rule' then di = di + 1; continue = false
        elseif exit == 'advance_two' then di = di + 2
        elseif exit == 'advance_to' then di = at + 1
        end
      end
    end
  end
  return {root = root, vector = vector, count = count, tags = state.tags, events = events}
end

return phrasing
