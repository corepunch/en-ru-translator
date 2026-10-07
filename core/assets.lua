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
function assets:paradigm(offset, id)
  local at = offset + id * 6
  return self:word(at), self:indirect(at+2)
end
return assets
