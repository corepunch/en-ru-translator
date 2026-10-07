-- Development pipeline over the recovered native lexical and memory stages.
-- Input is UTF-8; dictionary assets are CP866. Unsupported lexical branches
-- fail in lexical.analyze rather than falling back to the legacy compiler.
local memory = require 'core.ltpro.memory'
local heap = require 'core.ltpro.heap'
local initialize = require 'core.ltpro.initialize'
local dictionary = require 'core.ltpro.dictionary'
local lexical = require 'core.ltpro.lexical'
local first_pass = require 'core.ltpro.first_pass'
local second_pass = require 'core.ltpro.second_pass'
local third_pass = require 'core.ltpro.third_pass'
local fourth_pass = require 'core.ltpro.fourth_pass'
local reorder = require 'core.ltpro.reorder'
local bridge = require 'core.ltpro.bridge'
local senses = require 'core.ltpro.senses'
local constituents = require 'core.ltpro.constituents'
local seventh_pass = require 'core.ltpro.seventh_pass'
local eighth_pass = require 'core.ltpro.eighth_pass'
local generation = require 'core.ltpro.generation'
local output = require 'core.ltpro.output'
local encoding = require 'core.encoding'

local pipeline = {}
local linear = memory.linear

local function read_source(source, label)
  assert(type(source) == 'string', label .. ' source is required')
  -- A raw asset is arbitrary binary data and may contain NULs; `io.open`
  -- can throw for such strings instead of returning nil. Treat it as a path
  -- only when opening succeeds.
  local ok, file = pcall(io.open, source, 'rb')
  if not ok then file = nil end
  if not file then return source end
  local bytes = file:read('*a')
  file:close()
  return bytes
end

local function allocate(m, count, size, label)
  local segment, offset = heap.calloc(m, count, size)
  assert(not memory.null(segment, offset), 'native heap could not allocate ' .. label)
  return segment, offset
end

local function prepare_native_state(m, exported)
  local ds = linear(m.ds, 0)
  local root_seg, root_off = allocate(m, 1, 8, 'sentence root list')
  local first = exported.ordered[1] and exported.nodes[exported.ordered[1]]
  local last = exported.ordered[#exported.ordered] and exported.nodes[exported.ordered[#exported.ordered]]
  if first then m:set_far(linear(root_seg, root_off), first.segment, first.offset)
  else m:set_far(linear(root_seg, root_off), 0, 0) end
  if last then m:set_far(linear(root_seg, root_off) + 4, last.segment, last.offset)
  else m:set_far(linear(root_seg, root_off) + 4, root_seg, root_off) end

  local word_count = 0
  for node in pairs(exported.nodes) do
    if (node[0x0E] or 0) == 0x57 then word_count = word_count + 1 end
  end
  assert(word_count <= 512, 'native word-record limit exceeded')
  m:set16(ds + 0xC574, word_count)

  -- Native normally requests 42h elements, while the recovered builder can
  -- touch indices through 44h. Keep two guard elements in the same allocation
  -- so those native writes cannot corrupt the following heap block.
  local array_seg, array_off = allocate(m, 0x45, 12, 'constituent array')
  m:set_far(ds + 0xC7FA, array_seg, array_off)
  m:set16(ds + 0xC7FE, 0)
  for i = 0, 0x60 do m:set8(ds + 0xC7B6 + i, 0) end

  -- Sentence and appendix output are caller-owned C strings in the native
  -- driver. Allocate independent buffers and install their far pointers.
  local output_seg, output_off = allocate(m, 1, 0x2000, 'sentence output buffer')
  local appendix_seg, appendix_off = allocate(m, 1, 0x2000, 'appendix output buffer')
  m:set_far(ds + 0xC58C, output_seg, output_off)
  m:set_far(ds + 0xC598, appendix_seg, appendix_off)
  return root_seg, root_off, output_seg, output_off
end

-- Run one sentence. `options` accepts `executable`, `dictionary`, and
-- `russian` as paths or byte strings; omitted values use LTGOLD/ assets.
-- Returns CP866 output plus the intermediate stage/memory state for probes.
function pipeline.run(input, options)
  options = options or {}
  assert(type(input) == 'string', 'input sentence must be a UTF-8 string')
  local data = options.data_dir or 'LTGOLD'
  local executable = options.executable or (data .. '/LTPRO.EXE')
  local dic_source = options.dictionary or options.dic or (data .. '/BASE.DIC')
  local rus_source = options.russian or options.rus or (data .. '/BASE.RUS')

  local dic_bytes = read_source(dic_source, 'BASE.DIC')
  local rus_bytes = read_source(rus_source, 'BASE.RUS')
  local m = initialize.new(read_source(executable, 'LTPRO.EXE'), rus_bytes)
  local dict = dictionary.from_bytes(dic_bytes)
  local analyzed = lexical.analyze(dict, encoding.encode(input))

  local stages = {}
  stages.lexical_word_count = analyzed.word_count or 0
  local grammar_entered = stages.lexical_word_count > 0
  if grammar_entered then
    local t1 = first_pass.run(analyzed.root, {terminator = analyzed.terminator})
    stages.T1 = t1
    local grammar_result = t1.result
    if t1.result == 1 then
      local t2 = second_pass.run(analyzed.root, {count = t1.count})
      stages.T2 = t2
      local t3 = third_pass.run(analyzed.root, {count = t2.count, terminator = analyzed.terminator})
      stages.T3 = t3
      local t4 = fourth_pass.run(analyzed.root, {count = t3.count, terminator = analyzed.terminator})
      stages.T4 = t4
    end
    if grammar_result ~= 0 then
      local vector, count, rebuilt = reorder.apply(analyzed.root)
      stages.reorder = {vector = vector, count = count, rebuilt = rebuilt}
    end
  end

  local exported = bridge.serialize(m, analyzed.root)
  local root_seg, root_off, output_seg, output_off = prepare_native_state(m, exported)

  if grammar_entered then
    senses.numeric_pass(m, root_seg, root_off)
    stages.numeric = true
    constituents.pass(m, root_seg, root_off, analyzed.terminator, seventh_pass.run)
    stages.constituents = m:u16(linear(m.ds, 0xC7FE))
    eighth_pass.run(m, root_seg, root_off, analyzed.terminator)
    stages.T8 = true
    generation.run(m, root_seg, root_off)
    stages.generation = true
  end
  local alternatives = output.sentence(m, root_seg, root_off, output_seg, output_off)
  -- The native output routine emits a leading separator before its first word;
  -- the sentence driver drops it and appends the captured input terminator.
  local result = m:cstring(output_seg, output_off):gsub('^ ', '')
  local terminator = analyzed.terminator
  if terminator == 0x2E or terminator == 0x21 or terminator == 0x3F then
    local mark = string.char(terminator)
    if result:sub(-1) ~= mark then result = result .. mark end
  end
  local trailing_quotes = input:match("[.!?]([\"']+)%s*$") or ''
  if trailing_quotes ~= '' and result:sub(-#trailing_quotes) ~= trailing_quotes then
    result = result .. trailing_quotes
  end
  m:write_string(output_seg, output_off, result .. '\0')
  return result, {
    text = encoding.decode(result), memory = m, dictionary = dict, lexical = analyzed,
    exported = exported, root = {segment = root_seg, offset = root_off},
    output = {segment = output_seg, offset = output_off}, stages = stages,
    alternatives = alternatives,
  }
end

function pipeline.translate(input, options)
  local cp866, state = pipeline.run(input, options)
  return encoding.decode(cp866), state
end

return pipeline
