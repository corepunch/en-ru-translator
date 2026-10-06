-- Check native fields byte-for-byte after undoing the Lua source's UTF-8 display encoding.
local binary = require 'demo.ltpro_binary'
local data = require 'core.ltpro.morphology'
local encode = require('core.utils').encode
local reader = binary.read(arg[1] or 'LTGOLD/LTPRO.EXE')
local total, differences = 0, 0
for _, layout in ipairs(binary.morphology_layouts) do
  local rows = layout.gender and data[layout.name][layout.gender] or data[layout.name]
  local expected = reader.morphology(layout)
  differences = differences + math.abs(#rows - #expected)
  for i, row in ipairs(expected) do
    total = total + 1
    local actual = rows[i]
    if not actual or row[1] ~= actual[1] or row[2] ~= encode(actual[2]) then
      differences = differences + 1
      print(string.format('DIFF %s gender=%s index=%d', layout.name, tostring(layout.gender), i - 1))
    end
  end
end
print(string.format('Morphology: %d records, %d differences', total, differences))
os.exit(differences == 0 and 0 or 1)
