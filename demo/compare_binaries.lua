-- Compare independently located native blocks; LTGOLD.dat is not used as an oracle.
local binary = require "demo.ltpro_binary"
local encoding = require "core.encoding"
local pro = binary.read(arg[1] or "LTGOLD/LTPRO.EXE")
local gold = binary.read(arg[2] or "LTGOLD/LTGOLD.EXE")
local total, differences = 0, 0
for i, layout in ipairs(binary.layouts) do
  local other = {}
  for k, value in pairs(layout) do other[k] = value end
  other.offset = binary.gold_offsets[i]
  local a, b, count = pro.records(layout), gold.records(other), 0
  for j, record in ipairs(a) do
    local rhs = b[j]
    if record.flag ~= rhs.flag or record.pattern ~= rhs.pattern or
       record.action ~= rhs.action or record.endpoint_order ~= rhs.endpoint_order then
      count = count + 1
      print(string.format('%s[%d] differs: LTPRO @0x%X / LTGOLD @0x%X', layout.name, j - 1, record.address, rhs.address))
      print('  LTPRO: ' .. encoding.decode(record.pattern, false) .. ' -> ' .. encoding.decode(record.action or '', false))
      print('  LTGOLD: ' .. encoding.decode(rhs.pattern, false) .. ' -> ' .. encoding.decode(rhs.action or '', false))
    end
  end
  total, differences = total + #a, differences + count
  print(string.format('%s: %d/%d identical', layout.name, #a - count, #a))
end
local other = {name = 'LTGOLD suffix', offset = 0x511B8, count = 43, size = 10, suffix = true}
local a, b = pro.records(binary.suffix_layout), gold.records(other)
local suffix_differences = 0
for i, row in ipairs(a) do
  if row.flag ~= b[i].flag or row.suffix ~= b[i].suffix or row.tag ~= b[i].tag then
    suffix_differences = suffix_differences + 1
  end
end
print(string.format('Grammar: %d/%d identical; suffixes: %d/43 identical', total - differences, total, 43 - suffix_differences))
local morphology_total, morphology_differences = 0, 0
for _, layout in ipairs(binary.morphology_layouts) do
  local a = pro.morphology(layout)
  local b = gold.morphology({offset = layout.gold_offset, count = layout.count})
  for i, row in ipairs(a) do
    morphology_total = morphology_total + 1
    if row[1] ~= b[i][1] or row[2] ~= b[i][2] then
      morphology_differences = morphology_differences + 1
      print(string.format('Morphology differs: %s gender=%s index=%d', layout.name, tostring(layout.gender), i - 1))
    end
  end
end
print(string.format('Morphology: %d/%d identical', morphology_total - morphology_differences, morphology_total))
os.exit(differences + suffix_differences + morphology_differences == 0 and 0 or 1)
