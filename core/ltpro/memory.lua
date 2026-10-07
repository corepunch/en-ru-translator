-- Byte-addressed model of LTPRO's real-mode memory for the post-reorder stages.
--
-- Those stages keep far pointers into translation strings, split strings in
-- place with NUL bytes, chain allocated records and read Russian dictionary
-- text into a shared buffer. Their observable behaviour depends on exact
-- addresses and segment:offset representations, so the ports operate on this
-- model rather than on string fields. A far pointer is a (segment, offset)
-- pair; arithmetic on it changes only the 16-bit offset, as the 8086 code does.
local memory = {}
memory.__index = memory

-- `base` is an optional string holding initial memory from linear address 0
-- (a DOS snapshot); writes go to an overlay table, so the changed bytes can be
-- reported without copying the whole image.
function memory.new(base)
  return setmetatable({base = base or '', overlay = {}, files = {}, positions = {}}, memory)
end

function memory:u8(address)
  local value = self.overlay[address]
  if value then return value end
  return self.base:byte(address + 1) or 0
end

function memory:set8(address, value)
  self.overlay[address] = value & 0xFF
  if self.log then self.log[address] = true end
end

function memory:u16(address)
  return self:u8(address) | (self:u8(address + 1) << 8)
end

function memory:s16(address)
  local value = self:u16(address)
  return value >= 0x8000 and value - 0x10000 or value
end

function memory:set16(address, value)
  self:set8(address, value)
  self:set8(address + 1, value >> 8)
end

function memory:u32(address)
  return self:u16(address) | (self:u16(address + 2) << 16)
end

function memory:s32(address)
  local value = self:u32(address)
  return value >= 0x80000000 and value - 0x100000000 or value
end

function memory:set32(address, value)
  self:set16(address, value & 0xFFFF)
  self:set16(address + 2, (value >> 16) & 0xFFFF)
end

function memory.linear(segment, offset)
  return ((segment << 4) + offset) & 0xFFFFF
end

-- Far pointer stored at `address` as offset word then segment word.
function memory:far(address)
  return self:u16(address + 2), self:u16(address)
end

function memory:far_linear(address)
  return memory.linear(self:far(address))
end

function memory:set_far(address, segment, offset)
  self:set16(address, offset & 0xFFFF)
  self:set16(address + 2, segment & 0xFFFF)
end

function memory.null(segment, offset)
  return segment == 0 and offset == 0
end

-- C strings at a far pointer; offsets wrap within the segment like the
-- string helpers' SI/DI registers.
function memory:cstring(segment, offset)
  local bytes = {}
  while true do
    local c = self:u8(memory.linear(segment, offset))
    if c == 0 then break end
    bytes[#bytes + 1] = string.char(c)
    offset = (offset + 1) & 0xFFFF
  end
  return table.concat(bytes)
end

function memory:strlen(segment, offset)
  return #self:cstring(segment, offset)
end

function memory:write_string(segment, offset, text)
  for i = 1, #text do
    self:set8(memory.linear(segment, (offset + i - 1) & 0xFFFF), text:byte(i))
  end
end

-- strcpy copies forwards byte by byte including the NUL; an overlapping
-- destination after the source therefore re-reads copied bytes, as natively.
function memory:strcpy(dseg, doff, sseg, soff)
  local i = 0
  while true do
    local c = self:u8(memory.linear(sseg, (soff + i) & 0xFFFF))
    self:set8(memory.linear(dseg, (doff + i) & 0xFFFF), c)
    if c == 0 then break end
    i = i + 1
  end
  return dseg, doff
end

function memory:strcat(dseg, doff, sseg, soff)
  self:strcpy(dseg, (doff + self:strlen(dseg, doff)) & 0xFFFF, sseg, soff)
  return dseg, doff
end

-- strchr/strrchr/strstr/strpbrk return a pointer in the searched string's
-- segment, or (0, 0). strchr with NUL finds the terminator.
function memory:strchr(segment, offset, c)
  local i = 0
  while true do
    local b = self:u8(memory.linear(segment, (offset + i) & 0xFFFF))
    if b == c then return segment, (offset + i) & 0xFFFF end
    if b == 0 then return 0, 0 end
    i = i + 1
  end
end

function memory:strrchr(segment, offset, c)
  local text = self:cstring(segment, offset)
  if c == 0 then return segment, (offset + #text) & 0xFFFF end
  for i = #text, 1, -1 do
    if text:byte(i) == c then return segment, (offset + i - 1) & 0xFFFF end
  end
  return 0, 0
end

function memory:strstr(segment, offset, nseg, noff)
  local found = self:cstring(segment, offset):find(self:cstring(nseg, noff), 1, true)
  if not found then return 0, 0 end
  return segment, (offset + found - 1) & 0xFFFF
end

function memory:strpbrk(segment, offset, cseg, coff)
  local text, set = self:cstring(segment, offset), self:cstring(cseg, coff)
  for i = 1, #text do
    if set:find(text:sub(i, i), 1, true) then return segment, (offset + i - 1) & 0xFFFF end
  end
  return 0, 0
end

-- Borland stricmp folds ASCII a-z only; the result sign is what callers use.
local function fold(text) return (text:gsub('%l', string.upper)) end
function memory:stricmp(aseg, aoff, bseg, boff)
  local a, b = fold(self:cstring(aseg, aoff)), fold(self:cstring(bseg, boff))
  if a == b then return 0 end
  return a < b and -1 or 1
end

function memory:strcmp(aseg, aoff, bseg, boff)
  local a, b = self:cstring(aseg, aoff), self:cstring(bseg, boff)
  if a == b then return 0 end
  return a < b and -1 or 1
end

function memory:strncmp(aseg, aoff, bseg, boff, n)
  local a, b = self:cstring(aseg, aoff):sub(1, n), self:cstring(bseg, boff):sub(1, n)
  if a == b then return 0 end
  return a < b and -1 or 1
end

function memory:copy(dest, source, n)
  for i = 0, n - 1 do self:set8(dest + i, self:u8(source + i)) end
end

-- Changed bytes as a sorted list of {address, value}.
function memory:changes()
  local list = {}
  for address, value in pairs(self.overlay) do
    if value ~= (self.base:byte(address + 1) or 0) then list[#list + 1] = {address, value} end
  end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  return list
end

return memory
