local matching = require 'core.matching'
local constituents = require 'core.constituents'
local agreement = require 'core.agreement'
local nodes = require 'core.nodes'
local text = require 'core.text'
local syntax = {}
local values = require 'core.grammar_values'

local function context(state)
  local ctx={state=state}
  function ctx.element(i) return state.elements[i] or {} end
  function ctx.element_tag(i) return string.char(ctx.element(i).tag or 0) end
  function ctx.element_class(i) return string.char(ctx.element(i).class or 0) end
  function ctx.first(i) return ctx.element(i).next end
  function ctx.last(i) return ctx.element(i).last end
  function ctx.next(r) return r and r.next end
  function ctx.aux(r) return r and r.aux end
  ctx.get=nodes.number
  function ctx.set(r,f,v) if r then r[f]=v end end
  function ctx.copy(dst,src,f) ctx.set(dst,f,ctx.get(src,f)) end
  function ctx.find(r,test)
    while r do if test(nodes.tag(r)) then return r end; r=ctx.next(r) end
    return r
  end
  function ctx.is(r,at) return text.equal(r and r.source or '',state.assets:string(at)) end
  function ctx.set_literal(r,f,at) if r then r[f]=state.assets:string(at) end end
  function ctx.reading(r,at) if r then r.text=state.assets:string(at) end end
  function ctx.dictionary_bit(r,n) return (ctx.get(r,'dictionary_flags') >> n) & 1 end
  function ctx.t7(i) return agreement.run(state,ctx.element(i),ctx.element(i).tag or 0,i) end
  return ctx
end

local function is_tag(set) return function(t) return set:find(t, 1, true) ~= nil end end
-- The last record with tag 'V' (or `set`) in the list, else the list's last.
local function last_of(ctx, i, set)
  local r, found = ctx.first(i), ctx.last(i)
  while r do
    if set:find(nodes.tag(r), 1, true) then found = r end
    r = ctx.next(r)
  end
  return found
end
-- Prepositional/negation prefix written to +243 of a record or its auxiliary.
local function prefix(ctx, r, with_aux, without_aux)
  local a = ctx.aux(r)
  if a then ctx.set_literal(a, 'prefix', with_aux) else ctx.set_literal(r, 'prefix', without_aux) end
end
-- Case after a verb whose code bit 1 of +6D is set (shared by several rules).
local function verb_case(ctx, r)
  if ctx.dictionary_bit(r, 1) ~= 0 then
    if ctx.get(r, 'number') == 0 and ctx.get(r, 'gender') == 2 then ctx.set(r, 'case_mask', 8)
    elseif ctx.get(r, 'paradigm') == 0x35 then ctx.set(r, 'case_mask', 8)
    else ctx.set(r, 'case_mask', 2) end
  else
    ctx.set(r, 'case_mask', 8)
  end
end

local handlers = {}

handlers[1] = function(ctx, frame, start, finish)
  if ctx.element_class(start) == 'q' or ctx.element_class(finish) == 'q' then return end
  frame.right = ctx.first(finish)
  if not frame.right or nodes.character(frame.right, 'marker') == 'q' or ctx.get(frame.right, 'verb_flags') & values.verb_flags.imperative ~= 0 then return end
  if ctx.element_class(start) ~= 'k' then
    frame.cursor = ctx.find(ctx.first(start), is_tag('NRS'))
    if frame.cursor and nodes.character(frame.cursor, 'marker') ~= 'q' and frame.right and ctx.get(frame.cursor, 'previous_tag') ~= 0 and
       ctx.get(frame.cursor, 'case_mask') == 0 then
      local a = ctx.aux(frame.right)
      if a then ctx.copy(a, frame.cursor, 'person'); ctx.copy(a, frame.cursor, 'number'); ctx.copy(a, frame.cursor, 'gender') end
      ctx.copy(frame.right, frame.cursor, 'gender'); ctx.copy(frame.right, frame.cursor, 'person'); ctx.copy(frame.right, frame.cursor, 'number')
    end
  end
  if (frame.cursor and nodes.tag(frame.cursor) == 'S' and ctx.get(frame.cursor, 'aspect') ~= 0) or
     ctx.element_tag(start) == 'k' or ctx.element_tag(start - 1) == 'k' then
    prefix(ctx, frame.right, 0x4F66, 0x4F6A)
  end
end

handlers[2] = function(ctx, frame, start, finish)
  if ctx.element_class(start) == 'q' then return end
  frame.left = ctx.first(start)
  frame.cursor = ctx.last(start)
  while frame.left do
    if nodes.tag(frame.left) == 'V' then frame.cursor = frame.left end
    frame.left = ctx.next(frame.left)
  end
  if not frame.cursor or ctx.get(frame.cursor, 'passive') ~= 0 then return end
  if ctx.get(frame.cursor, 'lookup_flags') & 0x3F ~= 0 and (ctx.get(frame.cursor, 'dictionary_frame') >> 6) & 1 ~= 0 and
     (ctx.element_tag(finish + 1) == 'Q' or ctx.element_tag(finish + 1) == 'J') then
    frame.left = ctx.find(ctx.first(finish), is_tag('N'))
    if frame.left then ctx.set(frame.left, 'case_mask', 4) end
    return
  end
  local index = finish
  if ctx.element_tag(finish + 1) == 'N' or ctx.element_tag(finish + 1) == 'I' then
    frame.left = ctx.find(ctx.first(finish), is_tag('N'))
    if frame.left then ctx.set(frame.left, 'case_mask', 4) end
    index = finish + 1
  end
  frame.right = ctx.find(ctx.first(index), is_tag('N'))
  if not frame.right then return end
  if ctx.get(frame.cursor, 'case_mask') ~= 8 then ctx.copy(frame.right, frame.cursor, 'case_mask'); return end
  verb_case(ctx, frame.right)
end

handlers[3] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if not frame.right or ctx.get(frame.right, 'marker') ~= 0 then return end
  local case = ctx.get(frame.right, 'case_mask')
  if case ~= 8 and case ~= values.case.prepositional then return end
  if not (ctx.is(frame.right, 0x4F6E) or ctx.is(frame.right, 0x4F71) or ctx.is(frame.right, 0x4F74)) then return end
  frame.cursor = ctx.first(start)
  frame.left = ctx.last(start)
  while frame.cursor do
    local t = nodes.tag(frame.cursor)
    if t == 'V' or t == 'E' then frame.left = frame.cursor end
    frame.cursor = ctx.next(frame.cursor)
  end
  if not frame.left then return end
  ctx.set(frame.right, 'case_mask', ctx.dictionary_bit(frame.left, 6) ~= 0 and 0x20 or 8)
end

handlers[4] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(start)
  frame.left = ctx.last(start)
  while frame.cursor do
    if nodes.tag(frame.cursor) == 'V' then frame.left = frame.cursor end
    frame.cursor = ctx.next(frame.cursor)
  end
  frame.right = ctx.first(finish)
  if not frame.right or not frame.left then return end
  ctx.copy(frame.right, frame.left, 'number'); ctx.copy(frame.right, frame.left, 'gender')
  if ctx.get(frame.left, 'passive') ~= 0 then return end
  ctx.copy(frame.right, frame.left, 'case_mask')
end

handlers[5] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if not frame.right or ctx.get(frame.right, 'person') ~= 0 then return end
  ctx.t7(start)
  frame.cursor = ctx.find(ctx.first(start), is_tag('N'))
  if frame.cursor then
    ctx.set(frame.right, 'marker', ctx.get(frame.right, 'case_mask'))
    ctx.copy(frame.right, frame.cursor, 'case_mask'); ctx.copy(frame.right, frame.cursor, 'number'); ctx.copy(frame.right, frame.cursor, 'gender')
    ctx.set(frame.right, 'person', 3)
  end
  return 'skip'
end

handlers[6] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.first(finish)
  if frame.left and frame.right then ctx.copy(frame.right, frame.left, 'gender'); ctx.copy(frame.right, frame.left, 'number') end
end

handlers[7] = function(ctx, frame, start, finish)
  frame.cursor = ctx.find(ctx.first(start), is_tag('NS'))
  if not frame.cursor then return end
  frame.right = ctx.first(finish)
  if not frame.right then return end
  ctx.copy(frame.right, frame.cursor, 'number'); ctx.copy(frame.right, frame.cursor, 'gender')
  ctx.set(frame.right, 'case_mask', nodes.tag(frame.right) == 'l' and 2 or 0)
end

handlers[8] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.cursor = frame.left
  frame.left = ctx.find(frame.left, is_tag('V'))
  frame.right = ctx.first(finish)
  if not frame.left or not frame.right then return end
  local a = ctx.aux(frame.right)
  if a then
    ctx.copy(a, frame.left, 'person'); ctx.copy(a, frame.left, 'number'); ctx.copy(a, frame.left, 'gender')
  else
    ctx.copy(frame.right, frame.left, 'number'); ctx.copy(frame.right, frame.left, 'gender')
  end
  ctx.copy(frame.right, frame.cursor, 'number'); ctx.copy(frame.right, frame.left, 'verb_flags'); ctx.copy(frame.right, frame.left, 'passive'); ctx.copy(frame.right, frame.left, 'short_form')
end

handlers[9] = function(ctx, frame, start, finish)
  frame.left = ctx.find(ctx.first(start), is_tag('V'))
  if not frame.left then return end
  frame.right = nil
  if ctx.element_class(finish) ~= 'k' then
    frame.right = ctx.find(ctx.first(finish), is_tag('N'))
    if frame.left and frame.right then ctx.copy(frame.right, frame.left, 'case_mask') end
  end
  if (frame.right and nodes.tag(frame.right) == 'S' and ctx.get(frame.right, 'aspect') ~= 0) or ctx.element_tag(finish) == 'k' then
    prefix(ctx, frame.left, 0x4F77, 0x4F7B)
  end
end

handlers[10] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(start)
  frame.left = ctx.last(start)
  while frame.cursor do
    if nodes.tag(frame.cursor) == 'V' then frame.left = frame.cursor end
    frame.cursor = ctx.next(frame.cursor)
  end
  frame.right = ctx.first(finish)
  if not frame.left or not frame.right then return end
  if ctx.get(frame.right, 'verb_flags') & values.verb_flags.imperative ~= 0 then return end
  if nodes.character(frame.left, 'previous_tag') == 'E' and nodes.character(frame.right, 'previous_tag') ~= 'E' then return end
  local a = ctx.aux(frame.right)
  if a then
    ctx.copy(a, frame.left, 'person'); ctx.copy(a, frame.left, 'number'); ctx.copy(a, frame.left, 'gender')
  else
    ctx.copy(frame.right, frame.left, 'verb_flags'); ctx.copy(frame.right, frame.left, 'passive'); ctx.copy(frame.right, frame.left, 'short_form')
  end
  ctx.copy(frame.right, frame.left, 'person'); ctx.copy(frame.right, frame.left, 'number'); ctx.copy(frame.right, frame.left, 'gender')
end

handlers[11] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(start)
  frame.right = ctx.first(finish)
  if frame.right and frame.cursor then
    ctx.copy(frame.right, frame.cursor, 'number'); ctx.copy(frame.right, frame.cursor, 'gender'); ctx.set(frame.right, 'case_mask', values.case.instrumental)
  end
end

handlers[12] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.first(finish)
  if not frame.left or not frame.right then return end
  if ctx.get(frame.left, 'aspect') ~= 0 then
    if ctx.get(frame.left, 'aspect') == 1 then prefix(ctx, frame.right, 0x4F7F, 0x4F83)
    else ctx.set_literal(frame.right, 'prefix', 0x4F87) end
  end
  if ctx.get(frame.right, 'passive') ~= 0 then ctx.set(frame.right, 'gender', 0) end
end

handlers[13] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(start)
  frame.right = ctx.first(finish)
  if frame.right and frame.cursor then
    ctx.copy(frame.right, frame.cursor, 'number'); ctx.copy(frame.right, frame.cursor, 'gender'); ctx.set(frame.right, 'short_form', 1)
  end
end

handlers[14] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(start)
  frame.left = ctx.last(start)
  while frame.cursor and frame.left do
    local t = nodes.tag(frame.cursor)
    if t == 'V' or t == 'Y' then frame.left = frame.cursor end
    frame.cursor = ctx.next(frame.cursor)
  end
  if frame.left and ctx.get(frame.left, 'passive') ~= 0 then return end
  frame.right = ctx.first(finish)
  if frame.left and frame.right then ctx.copy(frame.right, frame.left, 'case_mask') end
end

handlers[15] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  if ctx.element_class(finish) ~= 'k' then
    frame.right = ctx.find(ctx.first(finish), is_tag('N'))
    if frame.left and frame.right then
      ctx.set(frame.right, 'case_mask', (ctx.dictionary_bit(frame.right, 1) ~= 0 or ctx.element_tag(finish) == 'k') and 2 or 8)
    end
  end
  if ctx.element_tag(start - 1) == 'X' then
    frame.cursor = ctx.first(start - 1)
    if frame.cursor then ctx.set_literal(frame.cursor, 'prefix', 0x4F8B) end
  elseif frame.left then
    ctx.set_literal(frame.left, 'prefix', 0x4F8F)
  end
end

local function agree_verb(ctx, frame, start, finish)
  frame.left, frame.right = ctx.first(start), ctx.first(finish)
  local source, target = frame.left, frame.right
  if not target then return end
  local function apply(word)
    if not word then return end
    word.person = 3
    word.number = ctx.get(source, 'number')
    word.gender = ctx.get(source, 'gender')
  end
  apply(target.aux)
  apply(target)
  local flags = ctx.get(target, 'verb_flags')
  if flags & values.verb_flags.imperative ~= 0 then
    target.verb_flags = flags & (values.byte_mask ~ values.verb_flags.imperative)
  end
end
handlers[16] = agree_verb

handlers[17] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.first(finish)
  if frame.left and (ctx.get(frame.left, 'tense') ~= 0 or ctx.get(frame.left, 'person') == 0) then
    frame.right = ctx.find(frame.right, is_tag('N'))
    if frame.right then ctx.set(frame.right, 'case_mask', values.case.instrumental) end
  end
  if ctx.element_tag(start + 1) == 'k' then
    frame.right = ctx.first(finish)
    if frame.right then ctx.set_literal(frame.right, 'prefix', 0x4F93) end
  end
  if ctx.element_tag(start - 1) == 'S' and frame.left and ctx.get(frame.left, 'tense') == 0 then
    frame.left.text = ""
  end
end

handlers[18] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.find(ctx.first(finish), is_tag('A'))
  if frame.left and frame.right then
    if ctx.get(frame.left, 'person') == 0 then ctx.set(frame.right, 'case_mask', values.case.instrumental); return end
    if ctx.get(frame.left, 'tense') ~= 0 then ctx.set(frame.right, 'case_mask', values.case.instrumental) end
    if ctx.get(frame.left, 'tense') == 0 then
      frame.left.text = ""
    end
    ctx.copy(frame.right, frame.left, 'gender'); ctx.copy(frame.right, frame.left, 'number')
    if ctx.get(frame.right, 'dictionary_flags') & 1 ~= 0 and ctx.get(frame.right, 'case_mask') ~= values.case.instrumental and
       (ctx.element_tag(start - 1) == 'N' or ctx.element_tag(start - 1) == '#' or ctx.element_tag(start - 1) == 'R') then
      ctx.set(frame.right, 'short_form', 1)
    end
  end
  if ctx.element_tag(start + 1) == 'k' then
    frame.right = ctx.first(finish)
    if frame.right then ctx.set_literal(frame.right, 'prefix', 0x4F97) end
  end
end

handlers[19] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if not frame.right or ctx.get(frame.right, 'marker') ~= 0 then return end
  if not (ctx.is(frame.right, 0x4F9B) or ctx.is(frame.right, 0x4F9E) or ctx.is(frame.right, 0x4FA1)) then return end
  frame.cursor = ctx.first(start)
  frame.left = ctx.last(start)
  while frame.cursor do
    if nodes.tag(frame.cursor) == ctx.element_tag(start) then frame.left = frame.cursor end
    frame.cursor = ctx.next(frame.cursor)
  end
  if not frame.left or not frame.right then return end
  ctx.set(frame.right, 'case_mask', ctx.dictionary_bit(frame.left, 6) ~= 0 and 0x20 or 8)
end

handlers[21] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(start)
  frame.left = ctx.last(start)
  while frame.cursor do
    if nodes.tag(frame.cursor) == 'V' then frame.left = frame.cursor end
    frame.cursor = ctx.next(frame.cursor)
  end
  frame.right = ctx.first(finish)
  if frame.left and frame.right then
    ctx.copy(frame.right, frame.left, 'person'); ctx.copy(frame.right, frame.left, 'number'); ctx.copy(frame.right, frame.left, 'gender')
  end
end

handlers[42] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.first(finish)
  if not frame.left or not frame.right then return end
  if ctx.get(frame.left, 'person') == 0 then ctx.set(frame.right, 'case_mask', values.case.instrumental); return end
  if ctx.get(frame.left, 'tense') ~= 0 then ctx.set(frame.right, 'case_mask', values.case.instrumental) end
  ctx.copy(frame.right, frame.left, 'gender')
end

handlers[22] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(start)
  if ctx.element_class(start) == 'w' then frame.cursor = ctx.find(frame.cursor, is_tag('P')) end
  frame.cursor = ctx.find(frame.cursor, is_tag('N'))
  if not frame.cursor then return end
  frame.right = ctx.first(finish)
  if not frame.right then return end
  ctx.copy(frame.right, frame.cursor, 'number'); ctx.copy(frame.right, frame.cursor, 'gender')
  ctx.set(frame.right, 'case_mask', nodes.tag(frame.right) == 'l' and 2 or 0)
end

handlers[23] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.first(finish)
  if not frame.left or not frame.right then return end
  ctx.copy(frame.right, frame.left, 'person'); ctx.copy(frame.right, frame.left, 'number'); ctx.copy(frame.right, frame.left, 'gender'); ctx.copy(frame.right, frame.left, 'tense')
end

handlers[24] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.first(finish)
  if not frame.left or not frame.right then return end
  ctx.copy(frame.right, frame.left, 'person'); ctx.copy(frame.right, frame.left, 'number'); ctx.copy(frame.right, frame.left, 'gender')
end

handlers[25] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if not frame.right or ctx.get(frame.right, 'case_mask') == 2 then return end
  if ctx.get(frame.right, 'marker') ~= 0 then return end
  if ctx.is(frame.right, 0x4FA4) or ctx.is(frame.right, 0x4FA7) or ctx.is(frame.right, 0x4FAA) then ctx.set(frame.right, 'case_mask', values.case.prepositional) end
end

handlers[26] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.first(finish)
  if not frame.left or not frame.right then return end
  if ctx.is(frame.left, 0x4FAD) and ctx.get(frame.left, 'marker') == 0 then ctx.set(frame.right, 'case_mask', values.case.prepositional)
  else ctx.copy(frame.right, frame.left, 'case_mask') end
  if ctx.get(frame.right, 'marker') == 0 then
    frame.right.text = " " .. (frame.right.text or ""):sub(2)
  end
end

handlers[27] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.find(ctx.first(finish), is_tag('N'))
  if not frame.left or not frame.right then return end
  local t = nodes.tag(frame.left)
  if t == 'f' or (t == 'y' and ctx.get(frame.left, 'aspect') ~= 0) then ctx.copy(frame.right, frame.left, 'case_mask')
  else ctx.copy(frame.left, frame.right, 'gender') end
  ctx.copy(frame.left, frame.right, 'number')
end

handlers[28] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.find(ctx.first(finish), is_tag('N'))
  if frame.left and frame.right then ctx.copy(frame.right, frame.left, 'case_mask') end
end

handlers[29] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(start + 1)
  frame.left = ctx.last(start + 1)
  while frame.cursor do
    if nodes.tag(frame.cursor) == 'V' then frame.left = frame.cursor end
    frame.cursor = ctx.next(frame.cursor)
  end
  if ctx.get(frame.left, 'passive') == 0 then return end
  frame.right = ctx.find(ctx.first(finish), is_tag('N'))
  if frame.left and frame.right then ctx.copy(frame.left, frame.right, 'number'); ctx.copy(frame.left, frame.right, 'gender') end
  frame.cursor = ctx.first(start)
  if frame.cursor and ctx.get(frame.right, 'passive') ~= 0 then ctx.set(frame.cursor, 'case_mask', 4) end
end

handlers[30] = function(ctx, frame, start, finish)
  if ctx.element_class(finish) == 'q' then return end
  if ctx.element_tag(start) == 'O' then frame.left = ctx.find(ctx.first(start), is_tag('N')) else frame.left = nil end
  frame.right = ctx.first(finish)
  if not frame.right then return end
  local number = ctx.element_tag(start) == 'O' and 0 or 1
  local a = ctx.aux(frame.right)
  if a then
    ctx.set(a, 'person', 3); ctx.set(a, 'number', number)
    if frame.left then ctx.copy(frame.right, frame.left, 'gender') end
  end
  ctx.set(frame.right, 'person', 3); ctx.set(frame.right, 'number', number)
  if frame.left then ctx.copy(frame.right, frame.left, 'gender') end
  if ctx.get(frame.right, 'verb_flags') & values.verb_flags.imperative ~= 0 then ctx.set(frame.right, 'verb_flags', ctx.get(frame.right, 'verb_flags') & (values.byte_mask ~ values.verb_flags.imperative)) end
end

handlers[31] = function(ctx, frame, start, finish)
  ctx.t7(start)
  frame.right = ctx.first(finish)
  frame.left = ctx.find(ctx.first(start), is_tag('N'))
  if frame.left and frame.right then ctx.copy(frame.right, frame.left, 'case_mask'); ctx.set(frame.right, 'number', 1) end
  return 'skip'
end

handlers[32] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(start + 1)
  if frame.cursor then ctx.set(frame.cursor, 'case_mask', 8) end
end

handlers[33] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if not frame.right then return end
  ctx.set(frame.right, 'number', 1)
  ctx.set(frame.right, 'case_mask', nodes.tag(frame.right) == 'l' and 2 or 0)
end

handlers[34] = function(ctx, frame, start, finish)
  frame.cursor = ctx.find(ctx.first(start), is_tag('#'))
  if not frame.cursor then return end
  frame.right = ctx.first(finish)
  if not frame.right then return end
  local a = ctx.aux(frame.right)
  if a then ctx.copy(a, frame.cursor, 'person'); ctx.copy(a, frame.cursor, 'number'); ctx.copy(a, frame.cursor, 'gender') end
  ctx.copy(frame.right, frame.cursor, 'gender')
  if ctx.get(frame.right, 'person') ~= 0 then ctx.set(frame.cursor, 'number', 0) end
  ctx.copy(frame.right, frame.cursor, 'number')
  ctx.set(frame.right, 'person', 3)
  if ctx.get(frame.right, 'verb_flags') & values.verb_flags.imperative ~= 0 then ctx.set(frame.right, 'verb_flags', ctx.get(frame.right, 'verb_flags') & (values.byte_mask ~ values.verb_flags.imperative)) end
end

handlers[35] = function(ctx, frame, start, finish)
  ctx.element(finish).class = 0x52
end

handlers[36] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.find(ctx.first(finish), is_tag('A'))
  if not frame.left or not frame.right then return end
  ctx.copy(frame.right, frame.left, 'gender'); ctx.copy(frame.right, frame.left, 'number')
  if ctx.get(frame.right, 'dictionary_flags') & 1 ~= 0 then ctx.set(frame.right, 'short_form', 1) else ctx.set(frame.right, 'case_mask', values.case.instrumental) end
end

handlers[37] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(finish)
  if frame.cursor then ctx.set(frame.cursor, 'person', 3); ctx.set(frame.cursor, 'gender', 1) end
end

handlers[39] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if not frame.right then return end
  if nodes.tag(frame.right) == 'Y' then
    ctx.reading(frame.right, 0x4FB0)
  else
    frame.left = ctx.first(start)
    if frame.left then ctx.copy(frame.right, frame.left, 'person'); ctx.copy(frame.right, frame.left, 'number') end
  end
end

handlers[43] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.find(ctx.first(finish), is_tag('A'))
  if not frame.left or not frame.right then return end
  ctx.set(frame.right, 'case_mask', values.case.instrumental); ctx.copy(frame.right, frame.left, 'number')
end

handlers[44] = function(ctx, frame, start, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.first(finish)
  if not frame.left or not frame.right then return end
  ctx.copy(frame.right, frame.left, 'person'); ctx.copy(frame.right, frame.left, 'number'); ctx.copy(frame.right, frame.left, 'gender'); ctx.copy(frame.right, frame.left, 'case_mask')
end

handlers[45] = function(ctx, frame, start, finish)
  frame.right = ctx.find(ctx.first(finish), is_tag('N'))
  if frame.right then ctx.set(frame.right, 'case_mask', values.case.instrumental) end
end

handlers[46] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(finish)
  if frame.cursor then
    frame.cursor.text = ""
  end
end

handlers[47] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if not frame.right or ctx.get(frame.right, 'case_mask') ~= 0 then return end
  frame.left = ctx.first(start)
  if frame.left then ctx.copy(frame.right, frame.left, 'case_mask') end
end

handlers[48] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if not frame.right or ctx.get(frame.right, 'case_mask') ~= 0 then return end
  if ctx.element_class(start) == 'w' then ctx.set(frame.right, 'case_mask', 2); return end
  frame.left = ctx.find(ctx.first(start), is_tag('N'))
  if frame.left then ctx.copy(frame.right, frame.left, 'case_mask') end
end

handlers[49] = function(ctx, frame, start, finish)
  frame.cursor = ctx.find(ctx.first(start), is_tag('N'))
  if frame.cursor then ctx.set(frame.cursor, 'case_mask', 4) end
end

local function insert_element(ctx,at,tag,class,literal)
  local node=nodes.word(ctx.state,tag,ctx.state.assets:string(literal))
  if not node then return nil end
  node.reading_state=3
  constituents.insert(ctx.state,{tag=tag,class=class,next=node,last=node},at)
  return node
end

handlers[53] = function(ctx,frame,start,finish) frame.cursor=insert_element(ctx,finish-2,0x4C,0x4B,0x4FB8) end
handlers[54] = function(ctx,frame,start,finish)
  if ctx.element_class(finish)=='R' or ctx.element_tag(finish+1)=='*' then return end
  frame.cursor=insert_element(ctx,finish,0x4C,0x4B,0x4FC2)
end
handlers[55] = function(ctx,frame,start,finish)
  frame.left=ctx.first(start)
  if not frame.left then return end
  local tag,literal=0x4C,0x4FD2
  if ctx.get(frame.left,'lookup_flags') & 0x3F == 1 and (ctx.get(frame.left,'dictionary_frame') >> 6) & 1 ~=0 then tag,literal=0x4A,0x4FCC end
  frame.cursor=insert_element(ctx,finish-1,tag,0x4B,literal)
  ctx.set(frame.left,'case_mask',4)
end
handlers[56] = function(ctx,frame,start,finish)
  frame.left=ctx.find(ctx.first(start),is_tag('V'))
  if not frame.left or ctx.get(frame.left,'lookup_flags') & 0x3F == 0 then return end
  local literal=ctx.get(frame.left,'lookup_flags') & 0x3F == 1 and 0x4FDC or 0x4FE2
  if literal==0x4FE2 then frame.right=ctx.first(finish); if frame.right then ctx.set(frame.right,'tense',1) end end
  frame.cursor=insert_element(ctx,finish-1,0x4A,0x4A,literal)
end
local function swap(ctx,i,j) constituents.swap(ctx.state,i,j) end
local function retag(ctx,i,t) ctx.element(i).tag,ctx.state.tags[i]=t,t end

handlers[59] = function(ctx, frame, start, finish)
  frame.cursor = ctx.first(finish - 1)
  if frame.cursor and nodes.character(frame.cursor, 'marker') == 'r' then swap(ctx, start, start + 1) end
end

handlers[60] = function(ctx, frame, start, finish)
  swap(ctx, start, start + ctx.rule.order)
end

handlers[61] = function(ctx, frame, start, finish)
  swap(ctx, start, finish)
  swap(ctx, start + 1, finish)
  frame.left = ctx.first(start)
  frame.right = ctx.first(start + 1)
  if frame.left and frame.right then ctx.copy(frame.right, frame.left, 'case_mask') end
  retag(ctx, start, 0x70)
end

handlers[62] = function(ctx, frame, start, finish)
  if ctx.element_tag(start - 1) == 'p' then return end
  frame.left = ctx.find(ctx.first(start), is_tag('N'))
  frame.right = ctx.first(finish)
  if not frame.left or not frame.right then return end
  local frame = ctx.get(frame.right, 'lookup_frame') & 0x3F
  if frame == 1 then ctx.set(frame.left, 'case_mask', ctx.get(frame.right, 'governed_case')); return end
  if frame == 2 and ctx.element_tag(finish + 1) == 'P' then
    swap(ctx, start, finish + 1)
    swap(ctx, start + 1, finish + 1)
    retag(ctx, start, 0x70)
  end
end

handlers[63] = function(ctx, frame, start, finish)
  frame.cursor = insert_element(ctx, start, 0x2A, 0x4B, 0x4FEA)
  if frame.cursor then swap(ctx, start, finish) end
end

handlers[68] = function(ctx, frame, start, finish)
  frame.left = ctx.find(ctx.first(start), is_tag('N'))
  frame.right = ctx.first(finish)
  if frame.left and frame.right then ctx.copy(frame.right, frame.left, 'gender'); ctx.copy(frame.right, frame.left, 'number') end
end

handlers[69] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if frame.right then ctx.set(frame.right, 'person', 3); ctx.set(frame.right, 'number', 1) end
end

handlers[70] = function(ctx, frame, start, finish)
  frame.right = ctx.first(finish)
  if not frame.right or ctx.get(frame.right, 'verb_flags') ~= 0 or ctx.get(frame.right, 'passive') ~= 0 then return end
  frame.cursor = ctx.find(ctx.first(start), is_tag('N'))
  if not frame.cursor then return end
  frame.right = ctx.last(finish)
  if frame.right then ctx.copy(frame.cursor, frame.right, 'case_mask') end
end

function syntax.run(state,root,terminator)
  local ctx=context(state)
  local frame={} -- Frame values persist across selectors, as in the recovered scheduler.
  ctx.terminator=terminator
  local start=1
  while state.count-1>start do
    local skipped=false
    for _,rule in ipairs(state.assets:rules(0x49E4)) do
      local finish=matching.constituents(state,start,rule.pattern)
      if finish~=0 then
        ctx.rule=rule
        local handler=handlers[rule.selector]
        if handler and handler(ctx,frame,start,finish)=='skip' then skipped=true; break end
      end
    end
    if not skipped then ctx.t7(start) end
    start=start+1
  end
  constituents.relink(state,root)
end
return syntax
