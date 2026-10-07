-- Replays native calls recorded by ltpro_function_probe.py through Lua ports.
local memory = require 'core.ltpro.memory'
local spec = dofile(assert(arg[1]))
local show = tonumber(arg[2] or '5')

-- Adapters: native stack words -> Lua port call; return AX, DX (nil = not compared).
local adapters = {}
local function add(name, fn) adapters[name] = fn end
local ok, registry = pcall(require, 'tools.ltpro_function_adapters')
if ok then registry(add) else error(registry) end
local adapter = assert(adapters[spec['function']], 'no Lua adapter for ' .. spec['function'])

local bases = {}
local function base(id)
  if not bases[id] then
    local f = assert(io.open(spec.snapshots[id].file, 'rb'))
    bases[id] = f:read('a'); f:close()
  end
  return bases[id]
end
local rus
local passed, failed = 0, 0
for index, case in ipairs(spec.cases) do
  local info = spec.snapshots[case.snapshot]
  local m = memory.new(base(case.snapshot))
  m.ds, m.ss = info.ds, info.ss
  m.library_segment = info.ds - 0x22D5
  if not rus then local f = assert(io.open(spec.rus, 'rb')); rus = f:read('a'); f:close() end
  m.files[5] = rus
  for _, pair in ipairs(case.before) do m.overlay[pair[1]] = pair[2] end
  for handle, position in pairs(case.positions or {}) do m.positions[tonumber(handle)] = position end
  m.log = {}
  local okcall, ax, dx = pcall(adapter, m, case.args, case)
  local differences = {}
  if not okcall then
    differences[#differences + 1] = tostring(ax)
  else
    local expected = {}
    for _, pair in ipairs(case.writes) do expected[pair[1]] = pair[2] end
    local stack_lo, stack_hi = info.ss * 16, info.ss * 16 + 0x10000
    local addresses = {}
    for a in pairs(expected) do addresses[a] = true end
    for a in pairs(m.log) do if not (a >= stack_lo and a < stack_hi) then addresses[a] = true end end
    local sorted = {}
    for a in pairs(addresses) do sorted[#sorted + 1] = a end
    table.sort(sorted)
    -- Expected final value: the native write, or the entry value if the native
    -- call did not write that address.
    local entry = memory.new(base(case.snapshot))
    for _, pair in ipairs(case.before) do entry.overlay[pair[1]] = pair[2] end
    -- strtok's saved pointer (DS:CA24) may address a dead stack buffer,
    -- whose position the ports do not model.
    local ignored = {}
    for i = 0, 3 do ignored[info.ds * 16 + 0xCA24 + i] = true end
    for _, a in ipairs(sorted) do
      if ignored[a] then goto continue end
      local want = expected[a] or entry:u8(a)
      local got = m:u8(a)
      if want ~= got then
        differences[#differences + 1] = string.format('%05X lua %02X native %02X', a, got, want)
        if #differences > 8 then break end
      end
      ::continue::
    end
    if ax ~= nil and ax ~= case.ax then differences[#differences + 1] = string.format('AX lua %04X native %04X', ax, case.ax) end
    if dx ~= nil and dx ~= case.dx then differences[#differences + 1] = string.format('DX lua %04X native %04X', dx, case.dx) end
  end
  if #differences == 0 then passed = passed + 1
  else
    failed = failed + 1
    if failed <= show then
      print(string.format('FAIL %d %s args=%s: %s', index, case.snapshot, table.concat(case.args, ','), table.concat(differences, '; ')))
    end
  end
end
print(string.format('%s Lua vs native calls: PASS=%d FAIL=%d', spec['function'], passed, failed))
os.exit(failed == 0 and 0 or 1)
