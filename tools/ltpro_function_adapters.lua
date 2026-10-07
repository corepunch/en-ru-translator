-- Lua adapters for tools/ltpro_function_probe.lua: native stack words -> port.
local runtime = require 'core.ltpro.runtime'
local senses = require 'core.ltpro.senses'
local russian = require 'core.ltpro.russian'
local heap = require 'core.ltpro.heap'
local records = require 'core.ltpro.records'
local endings = require 'core.ltpro.endings'
local constituents = require 'core.ltpro.constituents'
local seventh = require 'core.ltpro.seventh_pass'
local eighth = require 'core.ltpro.eighth_pass'
local lexmatch = require 'core.ltpro.lexmatch'
local memory = require 'core.ltpro.memory'
local function split32(v) return v & 0xFFFF, (v >> 16) & 0xFFFF end
return function(add)
  add('211E:113A', function(m, a) return runtime.is_upper_cyrillic(a[1]) and 1 or 0 end)
  add('211E:115A', function(m, a) return runtime.is_lower_cyrillic(a[1]) and 1 or 0 end)
  add('211E:117F', function(m, a) return runtime.is_cyrillic(a[1]) and 1 or 0 end)
  add('2104:0002', function(m, a) return runtime.ends_with(m, a[2], a[1], a[3], a[5], a[4]) end)
  add('151F:0B6B', function(m, a) local seg, off = senses.skip_prefix(m, a[2], a[1]); return off, seg end)
  local function key(m, a, at) local k = memory.linear(a[at + 1], a[at]); return m:u8(k), m:u8(k + 1) end
  add('043A:074D', function(m, a) return split32(russian.index_offset(m, memory.linear(a[2], a[1]), key(m, a, 3))) end)
  add('043A:0850', function(m, a)
    local k0, k1 = key(m, a, 3)
    return split32(russian.index_length(m, memory.linear(a[2], a[1]), k0, k1, m.library_segment))
  end)
  add('1FCD:057B', function(m, a) local s, o = russian.next_line(m, a[2], a[1]); return o, s end)
  add('1FCD:007F', function(m, a, case)
    local s, o = russian.search(m, a[2], a[1], a[4], a[3], a[5]); return o, s
  end)
  add('1FCD:1031', function(m, a) local s, o = russian.lookup(m, a[2], a[1], a[4], a[3], a[5]); return o, s end)
  add('0000:1CB4', function(m, a) local s, o = heap.malloc(m, a[1]); return o, s end)
  add('0000:1951', function(m, a) local s, o = heap.calloc(m, a[1], a[2]); return o, s end)
  add('0000:3D6A', function(m, a) local s, o = heap.strdup(m, a[2], a[1]); return o, s end)
  add('0000:1BAA', function(m, a) heap.free(m, a[2], a[1]) end)
  add('151F:028B', function(m, a) local s, o = senses.parse_code(m, a[2], a[1], a[4], a[3]); return o, s end)
  add('151F:000F', function(m, a) senses.store_code(m, a[1], a[3], a[2], a[5], a[4]) end)
  add('151F:09A3', function(m, a) return senses.reflexive(m, a[2], a[1]) end)
  add('151F:1F6F', function(m, a) local s, o = senses.clone(m, a[2], a[1], a[4], a[3]); return o, s end)
  add('0687:0892', function(m, a) local s, o = records.new(m, a[2], a[1], a[3], a[5], a[4]); return o, s end)
  add('2269:0007', function(m, a) records.append(m, a[2], a[1], a[4], a[3]) end)
  add('1E71:006F', function(m, a) return endings.matches(m, a[2], a[1], a[3], a[4], a[6], a[5]) & 0xFFFF end)
  add('1E71:0BA0', function(m, a) local s, o = endings.replace(m, a[2], a[1], a[4], a[3]); return o, s end)
  add('151F:056E', function(m, a) return senses.expand_phrase(m, a[4], a[3]) end)
  add('151F:0C03', function(m, a) return senses.select(m, a[2], a[1], a[4], a[3], a[5], a[6], a[7]) end)
  add('151F:2029', function(m, a) return senses.choose(m, a[2], a[1]) end)
  add('151F:2740', function(m, a) return senses.numeric_pass(m, a[2], a[1]) end)
  add('1C3D:1B3F', function(m, a) constituents.pass(m, a[2], a[1], a[3], seventh.run) end)
  add('1C3D:05C5', function(m, a) return constituents.build(m, a[2], a[1], a[4], a[3]) end)
  add('1C3D:0135', function(m, a) return constituents.match(m, a[2], a[1], a[3], a[5], a[4]) end)
  add('1449:0004', function(m, a) return seventh.run(m, a[2], a[1], a[3], a[4], a[6], a[5]) end)
  add('1986:000E', function(m, a) eighth.run(m, a[2], a[1], a[3]) end)
end
