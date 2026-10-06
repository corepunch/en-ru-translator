local nodes = require "core.ltpro.nodes"
local reorder = require "core.ltpro.reorder"
local guards = require "core.ltpro.guards"
local stream = require "core.token_stream"
local rules = require "core.rules"

local function sentence(tags)
  local records = {nodes.new('*', {id = '^'})}
  for i = 1, #tags do
    records[#records + 1] = nodes.new(tags:sub(i, i), {id = string.char(64 + i), [0x98] = ''})
  end
  records[#records + 1] = nodes.new('*', {id = '$'})
  return nodes.link(records)
end
local function ids(root)
  local out, node, seen = {}, root.next, {}
  while node do
    assert(not seen[node], 'linked-list cycle')
    seen[node] = true
    out[#out + 1], node = node.id, node.next
  end
  return table.concat(out)
end
local function vec(tags) return nodes.vector(sentence(tags)) end

-- Native repeated digits are swaps; these cases lost/duplicated nodes in the old parser.
for _, case in ipairs({{'NwNww','3455','^CDEAB$'}, {'NwwN','444','^DABC$'},
                       {'ANNAN','4545','^DEABC$'}, {'N-N','3','^CBA$'}}) do
  local root = sentence(case[1])
  reorder.swaps(nodes.vector(root), 1, case[2])
  assert(ids(root) == case[3], ids(root))
  local tokens = stream.new()
  local positions = {}
  for i = 1, #case[1] do
    positions[i] = i
    stream.append(tokens, string.char(64 + i), {source = i, constituent_flags = i * 7})
  end
  stream.reorder(tokens, positions, case[2])
  assert('^' .. table.concat(tokens) .. '$' == case[3])
  for i, token in ipairs(tokens) do
    assert(tokens.source[i] == token:byte() - 64)
    assert(tokens.constituent_flags[i] == tokens.source[i] * 7)
  end
end

local root = sentence('NwNww')
reorder.apply(root)
assert(ids(root) == '^CDEAB$')
-- Handler 2 changes the W head to A and DOES reorder it.
root = sentence('NW')
reorder.apply(root)
assert(ids(root) == '^BA$' and nodes.tag(root.next.next) == 'A')

-- Every extracted numeric program uses forward swaps and preserves node identity.
for ti = 5, 6 do
  for _, rule in ipairs(rules[ti]) do
    local doc = sentence(rule[2])
    for i = 1, #(rule[3] or '') do
      assert(tonumber(rule[3]:sub(i, i)) >= i)
    end
    reorder.swaps(nodes.vector(doc), 1, rule[3] or '')
    assert(#ids(doc) == #rule[2] + 2)
  end
end

-- All 13 selector branches, including predicate mutations and boundary comparisons.
local v = vec('ANNAN')
assert(reorder.allowed(v,1,5,1))
v[1][0x0F],v[5][0x0F] = 0x77,0x77
assert(not reorder.allowed(v,1,5,1))
v[1][0x0F],v[5][0x0F] = 0,0
assert(reorder.allowed(v,1,5,2) and nodes.tag(v[5]) == 'A')
assert(reorder.allowed(v,1,5,3))
v[1][0x66] = 0x45
assert(not reorder.allowed(v,1,5,3)); v[1][0x66] = 0
for _, tag in ipairs({'D','H',',','&'}) do
  v[0][0x0C] = tag:byte(); assert(not reorder.allowed(v,1,5,3))
end
v[0][0x0C] = 0x2A
v[5][0x0F],v[2][0x0F] = 0x77,0x77
assert(not reorder.allowed(v,1,5,3)); v[5][0x0F],v[2][0x0F] = 0,0
assert(reorder.allowed(v,1,5,4)); v[1][0x98] = 'NP'; assert(not reorder.allowed(v,1,5,4))
v[2][0x98] = '-'; assert(not reorder.allowed(v,1,5,5) and nodes.tag(v[2]) == '-')
v[2][0x98] = 'x'; assert(reorder.allowed(v,1,5,5))
assert(not reorder.allowed(v,1,5,6)); v[5][0x72] = 1; assert(reorder.allowed(v,1,5,6))
assert(not reorder.allowed(v,1,5,7)); v[5][0x0F] = 0x72; assert(reorder.allowed(v,1,5,7))
assert(not reorder.allowed(v,1,5,8)); v[1][0x98] = '\xAC\xA5\xE1)'; assert(reorder.allowed(v,1,5,8))
assert(not reorder.allowed(v,1,5,9)); v[4][0x0F] = 0x77; assert(reorder.allowed(v,1,5,9))
assert(reorder.allowed(v,1,5,10)); v[2][0x98] = 'P'; assert(not reorder.allowed(v,1,5,10))
assert(reorder.allowed(v,1,5,11)); v[5][0x0F] = 0x77; assert(not reorder.allowed(v,1,5,11))
assert(reorder.allowed(v,5,5,12) and not reorder.allowed(v,6,6,12))
assert(not reorder.allowed(v,1,5,97)); v[5][0x0F] = 0x61; assert(reorder.allowed(v,1,5,97))

-- Position-first, first eligible rule wins across the logical T5/T6 boundary.
root = sentence('NNN')
reorder.apply(root, { {{0,'NN','2'}}, {{0,'NNN','3'}} })
assert(ids(root) == '^BAC$')
root = sentence('N-N')
local before = nodes.vector(root)
before[2][0x0F] = 0x2F
reorder.apply(root)
assert(ids(root) == '^CA$')
root = sentence('NTN')
reorder.apply(root)
assert(ids(root) == '^AC$')
root = sentence('N N')
local middle = root.next.next.next
middle[0x0F] = 0x58
nodes.vector(root)
assert(ids(root) == '^AC$' and nodes.tag(middle) == 'x')

-- Alternate guard table is selected for A only, not indiscriminately appended.
assert(guards.table_for('A') == rules.adjective)
assert(guards.table_for('N') == rules[8] and guards.table_for('Z') == nil)
local a,b = {},{}
local first,last = guards.endpoints({endpoint_order = 0},a,b)
assert(first == a and last == b)
first,last = guards.endpoints({endpoint_order = 1},a,b)
assert(first == b and last == a)
print('Native LTPRO reorder and guard selection tests passed')
