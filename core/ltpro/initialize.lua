-- Snapshot-free startup state for the native-memory LTPRO stages.
--
-- The executable contributes its initialized DS image (static strings and
-- morphology tables); mutable DOS process state is rebuilt here. The Russian
-- dictionary's index is stored as the final 32*33 signed dwords in BASE.RUS.
local memory = require 'core.ltpro.memory'
local heap = require 'core.ltpro.heap'

local initialize = {}
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

local function source_bytes(source, name)
  assert(type(source) == 'string', name .. ' must be a path or byte string')
  local file = io.open(source, 'rb')
  if file then
    local bytes = file:read('*a')
    file:close()
    return bytes
  end
  local recognized = name == 'LTPRO.EXE' and source:sub(1, 2) == 'MZ' or
    name == 'BASE.RUS' and source:sub(1, 20) == 'LTech DIC File 2.00 '
  assert(recognized, name .. ' path is unreadable and value is not recognized asset bytes')
  return source
end

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

local function put_far(m, at, seg, off)
  m:set_far(at, seg, off)
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
    put_far(m, ds + offset, 0, 0)
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
function initialize.new(exe_source, russian_source)
  local exe = source_bytes(exe_source, 'LTPRO.EXE')
  local russian = source_bytes(russian_source, 'BASE.RUS')
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

return initialize
