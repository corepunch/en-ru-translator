-- Native lexical-node operations recovered from LTPRO 1313:000E and 1313:12DF.
-- Numeric keys are offsets into the original record; unknown fields stay unnamed.
local nodes = {}

function nodes.new(tag, fields)
  local node = fields or {}
  node[0x0C] = tag:byte()
  return node
end

function nodes.byte(node, offset)
  return node and node[offset] or 0
end

function nodes.tag(node)
  return string.char(nodes.byte(node, 0x0C))
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

function nodes.swap(previous_a, a, previous_b, b)
  -- The original updates singly-linked next pointers and special-cases adjacent nodes.
  local next_a, next_b = a.next, b.next
  previous_a.next, previous_b.next = b, a
  a.next = next_b
  b.next = a == previous_b and a or next_a
end

return nodes
