local nodes = {}

-- Native lexical-node operations recovered from LTPRO 1313:000E and 1313:12DF.
-- Numeric keys identify recovered grammatical fields; links and text are Lua values.
function nodes.new(tag, fields)
  local node = fields or {}
  node[0x0C] = tag:byte()
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
  for at=0,0x14 do node[at]=0 end
  node[0x0C],node[0x0D],node[0x0E]=tag:byte(),marker:byte(),0x44
  node[0x12],node[0x9C],node[0x11C]=tag,'',''
  state.count=(state.count or 0)+1
  return node
end

function nodes.byte(node, offset)
  local value = node and node[offset]
  return type(value) == "string" and (value:byte() or 0) or value or 0
end

function nodes.tag(node)
  return string.char(nodes.byte(node, 0x0C))
end

function nodes.set_tag(node, tag)
  assert(node, 'missing native node')[0x0C] = tag:byte()
end

function nodes.set_marker(node, marker)
  assert(node, 'missing native node')[0x0F] = marker:byte()
end

function nodes.has_reading(node, tag)
  return (assert(node, 'missing native node')[0x11C] or ''):find(tag, 1, true) ~= nil
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
    if node[0x0C] == 0x20 then
      local following = node.next
      if previous then previous.next = following else root.next = following end
      -- 0x16C4E preserves a removed X record as x; the object can have other owners.
      if node[0x0F] == 0x58 then node[0x0C] = 0x78 end
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
    for _, f in ipairs({0x10, 0x85, 0x87}) do
      local value = node[f] or 0
      if value >= 0 and value <= 255 then value = value | ((node[f + 1] or 0) << 8) end
      node[f] = value
    end
    for _, f in ipairs({0x12, 0x9C, 0x11C, 0x21B, 0x243}) do
      if type(node[f]) ~= 'string' then
        local bytes, i = {}, f
        while type(node[i]) == 'number' and node[i] ~= 0 do
          bytes[#bytes + 1] = string.char(node[i] & 255); i = i + 1
        end
        node[f] = table.concat(bytes)
      end
    end
    node.text = node[0x11C]
    visit(node.next); visit(node.aux)
  end
  visit(root.next)
end

function nodes.word(state, tag, text)
  if state.word_count >= 512 then return nil end
  state.word_count = state.word_count + 1
  local numeric = tag == 0x23 or tag == 0x3F or tag == 0x48
  return {[0x0E]=0x57, [0x0C]=numeric and #text >= 40 and 0x23 or tag,
    [0x85]=0xFFFF, [0x87]=#text, [0x12]=numeric and text:sub(1,80) or '',
    [0x11C]=numeric and '' or text, text=numeric and '' or text}
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
