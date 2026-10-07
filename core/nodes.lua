local layout = require 'core.record_layout'
local nodes = {}

-- Native lexical-node operations recovered from LTPRO 1313:000E and 1313:12DF.
-- Grammar properties are named Lua fields; links preserve ordinary table identity.
function nodes.new(tag, fields)
  local node = fields or {}
  node.tag = tag:byte()
  return node
end

-- 0687:0812 allocates a zeroed 15h-byte boundary record. This narrower
-- constructor is used with a null parent by T1; it is not a lexical-node clone.
function nodes.boundary(tag, marker, state)
  state = state or {}
  if state.limit and (state.count or 0) >= state.limit then return nil end
  local node
  if state.allocate then node=state.allocate() else node={} end
  if not node then return nil end
  node.reading_state, node.marker, node.source_position = 0, 0, 0
  node.tag,node.separator,node.kind=tag:byte(),marker:byte(),0x44
  node.source,node.lookup,node.reading=tag,'',''
  state.count=(state.count or 0)+1
  return node
end

function nodes.number(node, field)
  local value = node and node[layout.key(field)]
  return type(value) == "string" and (value:byte() or 0) or value or 0
end

function nodes.character(node, field)
  return string.char(nodes.number(node, field))
end

function nodes.tag(node)
  return string.char(nodes.number(node, 'tag'))
end

function nodes.set_tag(node, tag)
  assert(node, 'missing native node').tag = tag:byte()
end

function nodes.set_marker(node, marker)
  assert(node, 'missing native node').marker = marker:byte()
end

function nodes.has_reading(node, tag)
  return (assert(node, 'missing native node').reading or ''):find(tag, 1, true) ~= nil
end

function nodes.link(records)
  local root, previous = {}, nil
  for _, node in ipairs(records) do
    if previous then previous.next = node else root.next = node end
    previous = node
  end
  if previous then previous.next = nil end
  return root
end

function nodes.vector(root)
  local vector, count, previous, node = {}, 0, nil, root.next
  while node and count < 512 do
    if node.tag == 0x20 then
      local following = node.next
      if previous then previous.next = following else root.next = following end
      -- 0x16C4E preserves a removed X record as x; the object can have other owners.
      if node.marker == 0x58 then node.tag = 0x78 end
      node = following
    else
      vector[count] = node
      count = count + 1
      previous, node = node, node.next
    end
  end
  return vector, count
end

-- Return the live vector/count and a fresh mutable tag cache. Callers still
-- decide when to refresh: native handlers can retain stale counts or tags.
function nodes.rebuild(root)
  local vector, count = nodes.vector(root)
  local tags = {}
  for i = 0, count - 1 do tags[#tags + 1] = nodes.tag(vector[i]) end
  return vector, count, {tags = table.concat(tags)}
end

function nodes.swap(previous_a, a, previous_b, b)
  -- The original updates singly-linked next pointers and special-cases adjacent nodes.
  local next_a, next_b = a.next, b.next
  previous_a.next, previous_b.next = b, a
  a.next = next_b
  b.next = a == previous_b and a or next_a
end

-- Complete word values and owned strings replace the old serialization boundary.
function nodes.prepare(root)
  local seen = {}
  local function visit(node)
    if not node or seen[node] then return end
    seen[node] = true
    for _, fields in ipairs({
      {'source_position', 'source_position_high'},
      {'paradigm', 'paradigm_high'},
      {'source_length', 'source_length_high'},
    }) do
      local field, high = fields[1], fields[2]
      local value = node[field] or 0
      if value >= 0 and value <= 255 then value = value | ((node[high] or 0) << 8) end
      node[field] = value
    end
    for _, field in ipairs({'source', 'lookup', 'reading', 'suffix', 'prefix'}) do
      if type(node[field]) ~= 'string' then node[field] = '' end
    end
    node.text = node.reading
    visit(node.next); visit(node.aux)
  end
  visit(root.next)
end

function nodes.word(state, tag, text)
  if state.word_count >= 512 then return nil end
  state.word_count = state.word_count + 1
  local numeric = tag == 0x23 or tag == 0x3F or tag == 0x48
  return {kind=0x57, tag=numeric and #text >= 40 and 0x23 or tag,
    paradigm=0xFFFF, source_length=#text, source=numeric and text:sub(1,80) or '',
    reading=numeric and '' or text, text=numeric and '' or text}
end

function nodes.append(list, node)
  if list.last then list.last.next = node else list.next = node end
  list.last, node.next = node, nil
end

function nodes.pop(list)
  local node = list.next
  if node then list.next = node.next end
  if list.last == node then list.last = nil end
  return node
end

return nodes
