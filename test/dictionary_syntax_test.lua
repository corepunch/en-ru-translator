-- Replays test/ltpro/dictionary-syntax: every probe installs its experimental
-- rows in LTGOLD's own BASE.DIC/BASE.RUS exactly as capture.py did, and the
-- Lua engine must reproduce the captured original output. Reviewed
-- differences name the Lua output instead and must give a reason.
local engine = require 'core.engine'
local encoding = require 'core.encoding'

local decode_json = require 'test.json'

local function read(path)
  local file = assert(io.open(path, 'rb')); local bytes = file:read('a'); file:close(); return bytes
end
local directory = 'test/ltpro/dictionary-syntax/'
local probes = decode_json(read(directory .. 'probes.json'))
local reference = decode_json(read(directory .. 'reference.json'))
local reviewed = decode_json(read(directory .. 'reviewed-differences.json'))

-- tools/ltech_dict.py fold_byte: ASCII and CP866 Cyrillic case folding.
local function fold(key)
  return (key:gsub('.', function(c)
    local b = c:byte()
    if b >= 65 and b <= 90 then b = b + 32
    elseif b >= 0x80 and b <= 0x8F then b = b + 0x20
    elseif b >= 0x90 and b <= 0x9F then b = b + 0x50
    elseif b == 0xF0 then b = 0xF1 end
    return string.char(b)
  end))
end
local function key_of(line)
  local star = line:match('^.*()%*%$') or line:find('*', 1, true)
  return star and line:sub(1, star - 1) or line
end

local base_dic, base_rus = read('LTGOLD/BASE.DIC'), read('LTGOLD/BASE.RUS')
local finish = string.unpack('<I4', base_dic, 0x1F)
local base_lines, base_keys = {}, {}
for line in base_dic:sub(0x29, finish):gmatch('[^\n]+') do
  base_lines[#base_lines + 1] = line; base_keys[#base_keys + 1] = fold(key_of(line))
end

-- tools/ltpro_try_entries.py build(): drop rows whose folded key matches,
-- insert the new rows in folded-key order, drop z headwords when they did.
local function dictionary(probe, dropped_z)
  local remove, added = {}, {}
  for _, word in ipairs(probe.delete or {}) do remove[fold(encoding.encode(word))] = true end
  for _, row in ipairs(probe.entries or {}) do
    local line = encoding.encode(row)
    local key = fold(key_of(line))
    remove[key] = true
    added[#added + 1] = {line = line, key = key}
  end
  table.sort(added, function(a, b) return a.key < b.key end)
  local lines, next_added = {}, 1
  for index, line in ipairs(base_lines) do
    local key = base_keys[index]
    while added[next_added] and added[next_added].key < key do
      lines[#lines + 1] = added[next_added].line; next_added = next_added + 1
    end
    if not remove[key] and not (dropped_z and line:sub(1, 1) == 'z') then lines[#lines + 1] = line end
  end
  for at = next_added, #added do lines[#lines + 1] = added[at].line end
  return table.concat(lines, '\n') .. '\n'
end

local function russian(probe)
  local bytes = base_rus
  for _, spec in ipairs(probe.rus or {}) do
    local word, index, value = spec:match('^(.-):(%d+):(%x+)$')
    local start = assert(bytes:find('\n' .. encoding.encode(word) .. '*', 1, true), word) + 1 + #encoding.encode(word) + 1
    local at = start + tonumber(index)
    bytes = bytes:sub(1, at - 1) .. string.char(tonumber(value, 16)) .. bytes:sub(at + 1)
  end
  return bytes
end

assert(#probes == #reference.probes, 'reference.json is stale: rerun capture.py')
local compared, differences, used = 0, 0, {}
for index, probe in ipairs(probes) do
  local captured = reference.probes[index]
  assert(captured.id == probe.id and #captured.cases == #probe.inputs, 'reference.json is stale for ' .. probe.id)
  local options = {dictionary = dictionary(probe, captured.dropped_z_headwords), russian = russian(probe),
    domain = probe.domain}
  for case_index, case in ipairs(captured.cases) do
    assert(case.input == probe.inputs[case_index], 'reference.json is stale for ' .. probe.id)
    local actual = engine.translate(case.input, options)
    local review = (reviewed[probe.id] or {})[case.input]
    if review then
      used[probe.id .. '\0' .. case.input] = true
      assert(review.reason and review.reason ~= '', 'reviewed difference needs a reason: ' .. case.input)
      assert(review.lua ~= case.translation, probe.id .. ': now matches the original; drop the review: ' .. case.input)
      assert(actual == review.lua, probe.id .. ': ' .. case.input .. '\n  reviewed: ' .. review.lua .. '\n  lua:      ' .. actual)
      differences = differences + 1
    else
      assert(actual == case.translation, probe.id .. ': ' .. case.input .. '\n  original: ' .. case.translation .. '\n  lua:      ' .. actual)
    end
    compared = compared + 1
  end
end
for id, inputs in pairs(reviewed) do
  for input in pairs(inputs) do assert(used[id .. '\0' .. input], 'unused reviewed difference: ' .. id .. ': ' .. input) end
end
print(string.format('dictionary_syntax_test: %d original captures, %d exact, %d reviewed differences',
  compared, compared - differences, differences))
