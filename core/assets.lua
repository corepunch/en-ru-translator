-- Read-only decoding of the original executable's static tables. File offsets
-- are confined here; sentence state consists exclusively of Lua values.
local assets = {}
assets.__index = assets
function assets.new(exe)
  assert(exe:sub(1,2) == 'MZ', 'LTPRO.EXE is not an MZ executable')
  assert(string.unpack('<I2',exe,9)*16 == 0x3A00 and #exe == 0x26750+0xC412,
    'LTPRO.EXE does not match the expected unpacked LTPRO image')
  return setmetatable({data=exe:sub(0x26751), strings={}, rulesets={}}, assets)
end
function assets:word(offset) return string.unpack('<I2',self.data,offset+1) end
function assets:string(offset)
  local value = self.strings[offset]
  if not value then
    local stop = assert(self.data:find('\0',offset+1,true),'unterminated asset string')
    value = self.data:sub(offset+1,stop-1); self.strings[offset] = value
  end
  return value
end
function assets:indirect(offset) return self:string(self:word(offset)) end
function assets:rules(offset)
  if not self.rulesets[offset] then
    local rules = {}
    local at = offset
    while self:word(at) ~= 0 do
      local order = self:word(at+4)
      rules[#rules+1] = {pattern=self:indirect(at), order=order >= 32768 and order-65536 or order,
        selector=self:word(at+6)}
      at = at + 8
    end
    self.rulesets[offset] = rules
  end
  return self.rulesets[offset]
end
-- Inflection tables. LTPRO keeps them in its data segment; this project keeps
-- the same rows in openrussian/paradigms.txt so they can be read and extended
-- without the executable. The file, when loaded, takes precedence.
local sections = {[0x5A50]='verb-imperfective',[0x5E90]='verb-perfective',[0x5238]='noun-m',[0x5450]='noun-f',
  [0x55A6]='noun-n',[0x56D4]='adjective-m',[0x5770]='adjective-f',[0x580C]='adjective-n'}
assets.paradigm_sections = sections
function assets:load_paradigms(text, encode)
  local tables, current = {}, nil
  for line in text:gmatch('[^\n]+') do
    local name = line:match('^## (%S+)')
    if name then current = {}; tables[name] = current
    elseif current and not line:match('^#') then
      local id, cut, endings = line:match('^(%d+)\t(%d+)\t(.*)$')
      if id then current[tonumber(id)] = {tonumber(cut), encode(endings)} end
    end
  end
  self.paradigm_tables = tables
end
function assets:paradigm(offset, id)
  local section = self.paradigm_tables and self.paradigm_tables[sections[offset]]
  if section then
    local row = section[id]
    if row then return row[1], row[2] end
    return 0, ''
  end
  local at = offset + id * 6
  return self:word(at), self:indirect(at+2)
end
return assets
