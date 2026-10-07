local memory = require 'core.memory'
local heap = require 'core.heap'
local lexicon = require 'core.lexicon'
local grammar = require 'core.grammar'
local phrasing = require 'core.phrasing'
local reorder = require 'core.reorder'
local nodes = require 'core.nodes'
local senses = require 'core.senses'
local constituents = require 'core.constituents'
local agreement = require 'core.agreement'
local syntax = require 'core.syntax'
local generation = require 'core.generation'
local output = require 'core.output'
local encoding = require 'core.encoding'

local engine = {}

local signatures = {
  ['LTPRO.EXE'] = 'MZ',
  ['BASE.RUS'] = 'LTech DIC File 2.00 ',
}

function engine.read_asset(source, name)
  assert(type(source) == 'string', name .. ' must be a path or byte string')
  -- Raw assets may contain embedded NULs that io.open rejects by throwing.
  local ok, file = pcall(io.open, source, 'rb')
  if ok and file then
    local bytes, message = file:read('*a')
    file:close()
    assert(bytes, name .. ' could not be read: ' .. tostring(message))
    return bytes
  end
  local signature = signatures[name]
  assert(not signature or source:sub(1, #signature) == signature,
    name .. ' path is unreadable and value is not recognized asset bytes')
  return source
end

-- Snapshot-free startup state for the native-memory LTPRO stages.
--
-- The executable contributes its initialized DS image (static strings and
-- morphology tables); mutable DOS process state is rebuilt here. The Russian
-- dictionary's index is stored as the final 32*33 signed dwords in BASE.RUS.

local linear = memory.linear

local MEMORY_SIZE = 0xA0000
local DS = 0x22D5
local DS_FILE_BASE = 0x26750
local DS_IMAGE_SIZE = 0xC412
local DICTIONARY_HEAD = 0xC8B4
local DESCRIPTOR_SIZE = 0x80
local READ_BUFFER_SIZE = 0x802 -- 800h read bytes plus two native sentinels
local INDEX_ROWS, INDEX_COLUMNS = 32, 33
local INDEX_SIZE = INDEX_ROWS * INDEX_COLUMNS * 4

local function u32le(bytes, offset)
  local a, b, c, d = bytes:byte(offset + 1, offset + 4)
  assert(d, 'truncated BASE.RUS header')
  return a | (b << 8) | (c << 16) | (d << 24)
end

local function u16le(bytes, offset)
  local a, b = bytes:byte(offset + 1, offset + 2)
  assert(b, 'truncated BASE.RUS header')
  return a | (b << 8)
end

-- Create a DOS-like program block so heap.lua can keep its native sbrk/brk
-- behavior, including 64-paragraph growth and MCB resizing.
local function initialize_heap(m)
  -- Keep the whole 64K DS address window disjoint from heap allocations.
  local program = 0x3400
  local initial_paragraphs = 0x1000
  local top = 0x9FFF
  local main_mcb = (program - 1) * 16
  local free_mcb = (program + initial_paragraphs) * 16
  local free_segment = program + initial_paragraphs + 1

  m:set8(main_mcb, 0x4D) -- MCB type 'M'
  m:set16(main_mcb + 1, program) -- owner
  m:set16(main_mcb + 3, initial_paragraphs)
  m:set8(free_mcb, 0x5A) -- final MCB type 'Z'
  m:set16(free_mcb + 1, 0) -- free block
  m:set16(free_mcb + 3, 0xA000 - free_segment)

  m:set16(linear(DS, 0x7B), program)
  m:set16(linear(DS, 0x87), 0) -- heap base offset
  m:set16(linear(DS, 0x89), program)
  m:set16(linear(DS, 0x8B), 0) -- break offset
  m:set16(linear(DS, 0x8D), program)
  m:set16(linear(DS, 0x8F), 0) -- heap top offset
  m:set16(linear(DS, 0x91), top)
  m:set16(linear(DS, 0xC3D8), initial_paragraphs // 64)

  -- Borland's first/last/rover pointers are words in the C library segment.
  m:set16(linear(m.library_segment, 0x1A6A), 0)
  m:set16(linear(m.library_segment, 0x1A6C), 0)
  m:set16(linear(m.library_segment, 0x1A6E), 0)
end

local function reset_sentence_state(m)
  local ds = linear(DS, 0)
  for _, offset in ipairs({0xC574, 0xC7B1, 0xC7B4, 0xC7FE, 0xC806, 0xC8E0, 0xBDB0}) do
    m:set16(ds + offset, 0)
  end
  for _, offset in ipairs({0xC7FA, 0xBCF4, 0xBCEC, 0xC8CC, 0xC8D4, 0xBDA8, 0xBDAC, 0xCA24}) do
    m:set_far(ds + offset, 0, 0)
  end

  -- The 512 limit and frozen profile defaults are process settings rather
  -- than sentence scratch. They are initialized explicitly as DOS startup
  -- normally does, while preserving the static lookup/morphology tables.
  m:set16(ds + 0x044D, 512)
  m:set16(ds + 0xBB9E, 0)
  m:set16(ds + 0xBBA0, 0)
  m:set16(ds + 0xBBA2, 0)
  m:set16(ds + 0xBBB4, 0)
  m:set16(ds + 0xBBB6, 1)
  m:set16(ds + 0xBBB8, 0)
  m:set16(ds + 0xBBBA, 1)
end

local function initialize_russian(m, bytes)
  assert(bytes:sub(1, 20) == 'LTech DIC File 2.00 ', 'unsupported BASE.RUS header')
  local text_end = u32le(bytes, 0x1E)
  local total_size = u32le(bytes, 0x22)
  assert(total_size == #bytes, 'BASE.RUS header length does not match asset')
  assert(text_end >= 0x28 and text_end + INDEX_SIZE == #bytes,
    'BASE.RUS does not contain the expected 32x33 index tail')
  assert(u16le(bytes, 0x1C) == 0x20, 'BASE.RUS is not the Russian 32-column dictionary')

  local descriptor_seg, descriptor_off = heap.calloc(m, 1, DESCRIPTOR_SIZE)
  local buffer_seg, buffer_off = heap.malloc(m, READ_BUFFER_SIZE)
  local index_seg, index_off = heap.malloc(m, INDEX_SIZE)
  assert(descriptor_seg ~= 0 and buffer_seg ~= 0 and index_seg ~= 0,
    'unable to allocate BASE.RUS runtime structures')

  m:write_string(index_seg, index_off, bytes:sub(text_end + 1))
  local d = linear(descriptor_seg, descriptor_off)
  m:set_far(linear(DS, DICTIONARY_HEAD), descriptor_seg, descriptor_off)
  m:set_far(d, 0, 0)
  m:set8(d + 0x0B, 0) -- the native descriptor does not own its read buffer
  m:set8(d + 0x5C, 0x52) -- 'R'
  m:set16(d + 0x60, INDEX_ROWS)
  m:set32(d + 0x62, 0)
  m:set32(d + 0x66, text_end)
  m:set16(d + 0x6A, 5)
  m:set32(d + 0x6C, 0)
  m:set_far(d + 0x70, buffer_seg, buffer_off)
  m:set_far(d + 0x74, 0, 0)
  m:set_far(d + 0x78, 0, 0)
  m:set_far(d + 0x7C, index_seg, index_off)

  -- The native search routines use these static strings and the DOS read
  -- chunk size. BC F8 and BD7C are also present in the EXE image; write the
  -- values explicitly to make the expected file-key pattern part of contract.
  m:write_string(DS, 0xBCF8, '\n\0')
  m:write_string(DS, 0xBD7C, '*\0')
  m:set16(linear(DS, 0xBCE8), 0x800)
  m.files[5] = bytes
  m.positions[5] = 0
end

-- `exe_source` and `russian_source` may each be a path or a byte string.
function engine.new_memory(exe_source, russian_source)
  local exe = engine.read_asset(exe_source, 'LTPRO.EXE')
  local russian = engine.read_asset(russian_source, 'BASE.RUS')
  assert(exe:sub(1, 2) == 'MZ', 'LTPRO.EXE is not an MZ executable')
  assert(u16le(exe, 8) * 16 == 0x3A00 and #exe - DS_FILE_BASE == DS_IMAGE_SIZE,
    'LTPRO.EXE does not match the expected unpacked LTPRO image')

  local ds_image = exe:sub(DS_FILE_BASE + 1)
  local ds_linear = linear(DS, 0)
  assert(ds_linear + #ds_image <= MEMORY_SIZE, 'initialized DS image exceeds conventional memory')
  local base = string.rep('\0', ds_linear) .. ds_image ..
    string.rep('\0', MEMORY_SIZE - ds_linear - #ds_image)
  local m = memory.new(base)
  m.ds, m.library_segment = DS, 0

  initialize_heap(m)
  reset_sentence_state(m)
  initialize_russian(m, russian)
  return m
end

-- Translation pipeline over the recovered lexical and memory stages.
-- Input is UTF-8; dictionary assets are CP866. Unsupported lexical branches
-- fail explicitly in lexicon.analyze.

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
function engine.run(input, options)
  options = options or {}
  assert(type(input) == 'string', 'input sentence must be a UTF-8 string')
  local data = options.data_dir or 'LTGOLD'
  local executable = options.executable or (data .. '/LTPRO.EXE')
  local dic_source = options.dictionary or options.dic or (data .. '/BASE.DIC')
  local rus_source = options.russian or options.rus or (data .. '/BASE.RUS')

  local dic_bytes = engine.read_asset(dic_source, 'BASE.DIC')
  local m = engine.new_memory(executable, rus_source)
  local dict = lexicon.from_bytes(dic_bytes)
  local analyzed = lexicon.analyze(dict, encoding.encode(input))

  local stages = {}
  stages.lexical_word_count = analyzed.word_count or 0
  local grammar_entered = stages.lexical_word_count > 0
  if grammar_entered then
    local t1 = grammar.first(analyzed.root, {terminator = analyzed.terminator})
    stages.T1 = t1
    local grammar_result = t1.result
    if t1.result == 1 then
      local t2 = grammar.second(analyzed.root, {count = t1.count})
      stages.T2 = t2
      local t3 = grammar.third(analyzed.root, {count = t2.count, terminator = analyzed.terminator})
      stages.T3 = t3
      local t4 = phrasing.run(analyzed.root, {count = t3.count, terminator = analyzed.terminator})
      stages.T4 = t4
    end
    if grammar_result ~= 0 then
      local vector, count, rebuilt = reorder.apply(analyzed.root)
      stages.reorder = {vector = vector, count = count, rebuilt = rebuilt}
    end
  end

  local exported = nodes.serialize(m, analyzed.root)
  local root_seg, root_off, output_seg, output_off = prepare_native_state(m, exported)

  if grammar_entered then
    senses.numeric_pass(m, root_seg, root_off)
    stages.numeric = true
    constituents.pass(m, root_seg, root_off, analyzed.terminator, agreement.run)
    stages.constituents = m:u16(linear(m.ds, 0xC7FE))
    syntax.run(m, root_seg, root_off, analyzed.terminator)
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

function engine.translate(input, options)
  local cp866, state = engine.run(input, options)
  return encoding.decode(cp866), state
end

return engine
