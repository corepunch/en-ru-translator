-- LTPRO's native word-record layout: byte offset -> the engine's field name.
-- Only the probes that compare captured LTPRO memory with Lua records use it;
-- the engine itself knows fields by name.
local fields = {
  [0x09] = 'capitals',
  [0x0B] = 'reading_state',
  [0x0C] = 'tag',
  [0x0D] = 'separator',
  [0x0E] = 'kind',
  [0x0F] = 'marker',
  [0x10] = 'source_position',
  [0x11] = 'source_position_high',
  [0x12] = 'source',
  [0x66] = 'previous_tag',
  [0x67] = 'lookup_code',
  [0x68] = 'lookup_flags',
  [0x69] = 'lookup_paradigm',
  [0x6A] = 'lookup_frame',
  [0x6C] = 'record_class',
  [0x6D] = 'dictionary_flags',
  [0x6E] = 'dictionary_frame',
  [0x6F] = 'dictionary_paradigm',
  [0x70] = 'dictionary_case',
  [0x72] = 'number',
  [0x73] = 'tense',
  [0x74] = 'person',
  [0x75] = 'aspect',
  [0x76] = 'case_mask',
  [0x77] = 'gender',
  [0x78] = 'verb_flags',
  [0x79] = 'governed_case',
  [0x7A] = 'passive',
  [0x7B] = 'short_form',
  [0x85] = 'paradigm',
  [0x86] = 'paradigm_high',
  [0x87] = 'source_length',
  [0x88] = 'source_length_high',
  [0x89] = 'alternative_count',
  [0x9C] = 'lookup',
  [0x11C] = 'reading',
  [0x21B] = 'suffix',
  [0x243] = 'prefix',
}

local layout = {fields = fields}
function layout.key(offset) return fields[offset] or offset end
function layout.import(raw)
  local record = {}
  for key, value in pairs(raw) do record[layout.key(key)] = value end
  return record
end
return layout
