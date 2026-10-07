-- Lua side of ltpro_post_chain.py: run the post-reorder stage ports.
local memory = require 'core.ltpro.memory'
local senses = require 'core.ltpro.senses'
local constituents = require 'core.ltpro.constituents'
local seventh = require 'core.ltpro.seventh_pass'
local eighth = require 'core.ltpro.eighth_pass'
local generation = require 'core.ltpro.generation'
local output = require 'core.ltpro.output'
local records = require 'core.ltpro.records'
local spec = dofile(arg[1])
local f = assert(io.open(spec.memory, 'rb')); local base = f:read('a'); f:close()
local r = assert(io.open(spec.rus, 'rb')); local rus = r:read('a'); r:close()
local m = memory.new(base)
m.ds, m.library_segment = spec.ds, spec.ds - 0x22D5
m.files[5] = rus
local off, seg = spec.root[1], spec.root[2]
local alternatives
for _, stage in ipairs(spec.stages) do
  if stage == 'numeric' then senses.numeric_pass(m, seg, off)
  elseif stage == 'constituent' then constituents.pass(m, seg, off, spec.si, seventh.run)
  elseif stage == 'T8' then eighth.run(m, seg, off, spec.si)
  elseif stage == 'generation' then generation.run(m, seg, off)
  elseif stage == 'output' then
    local s, o = m:far(memory.linear(m.ds, 0xC58C))
    m:set8(memory.linear(s, o), 0)
    alternatives = output.sentence(m, seg, off, s, o)
  elseif stage == 'meanings' then
    local ds = memory.linear(m.ds, 0)
    if m:u16(ds + 0xBBB6) ~= 0 and (m:u16(ds + 0xBBB4) ~= 0 or m:u16(ds + 0xBBBA) ~= 0) then
      local s, o = m:far(ds + 0xC598)
      output.meanings(m, seg, off, s, o)
      m:set16(ds + 0x042B, m:u16(ds + 0x042B) + assert(alternatives))
    end
  elseif stage == 'cleanup' then records.clear(m, seg, off)
  else error('unknown stage: ' .. tostring(stage)) end
end
local bytes = {}
for a = 0, #base - 1 do bytes[a + 1] = string.char(m:u8(a)) end
local out = assert(io.open(arg[2], 'wb')); out:write(table.concat(bytes)); out:close()
