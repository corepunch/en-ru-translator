-- Candidate fallbacks observed in captured LTPRO lexical fixtures. The
-- dictionary file supplies the native base records; only candidate derivation
-- is under test here.
local lexicon = require 'core.lexicon'
local file = assert(io.open('LTGOLD/BASE.DIC', 'rb'))
local base = lexicon.from_bytes(file:read('*a'))
file:close()

local fixtures = {
  { id = 'case-060', source = 'books', candidate = 'book', tag = 'Z', suffix = 's', fields = {[0x72]=1,[0x74]=3} },
  { id = 'case-061', source = 'books', candidate = 'book', tag = 'Z', suffix = 's' },
  { id = 'case-070', source = 'books', candidate = 'book', tag = 'Z', suffix = 's' },
  { id = 'case-014', source = 'organizations', candidate = 'organization', tag = 'N', suffix = 's' },
  { id = 'case-013', source = 'defined', candidate = 'define', tag = 'E', suffix = 'ed', fields = {[0x73]=1,[0x76]=8} },
  { id = 'case-014', source = 'legally', candidate = 'legal', tag = 'D', suffix = 'ly' },
  { id = 'case-018', source = 'supersedes', candidate = 'supersede', tag = 'V', suffix = 'es' },
  { id = 'case-024', source = 'walked', candidate = 'walked', tag = 'E', exact = true, backref = 'walk' },
  { id = 'case-039', source = 'works', candidate = 'works', tag = 'V', exact = true, backref = 'work' },
  { id = 'case-047', source = 'working', candidate = 'working', tag = 'G', exact = true, backref = 'work' },
  { id = 'case-048', source = 'worked', candidate = 'worked', tag = 'E', exact = true, backref = 'work' },
}

for _, fixture in ipairs(fixtures) do
  local result, reason = lexicon.lookup(base, fixture.source)
  assert(result, fixture.id .. ' ' .. fixture.source .. ': ' .. tostring(reason))
  assert(result.candidate == fixture.candidate, fixture.id .. ' candidate: ' .. tostring(result.candidate))
  assert(result.tag == fixture.tag, fixture.id .. ' tag: ' .. tostring(result.tag))
  assert(result.exact == (fixture.exact or false), fixture.id .. ' exact flag')
  assert(result.native_suffix == fixture.suffix, fixture.id .. ' native suffix')
  assert(result.backref == fixture.backref, fixture.id .. ' backref: ' .. tostring(result.backref))
  for offset, value in pairs(fixture.fields or {}) do
    assert(result.fields[offset] == value, fixture.id .. ' field +' .. string.format('%02X', offset))
  end
end

local rows = lexicon.suffix_rows()
assert(rows[11].ending == 'ies' and rows[11].selector == 'Z13')
assert(rows[12].ending == 'es' and rows[12].selector == 'Z13')
assert(rows[13].ending == 's' and rows[13].selector == 'Z13')
assert(rows[33].ending == 'ly' and rows[33].selector == 'D')

local no_root = lexicon.from_bytes('word*Nслово\n')
local result, reason = lexicon.lookup(no_root, 'unknownness')
assert(result == nil and reason:find('native suffix row ness/N00', 1, true))

local duplicate = lexicon.from_bytes('book*Zкнига\nbook*Nкнижка\n')
result, reason = lexicon.lookup(duplicate, 'books')
assert(result == nil and reason == 'duplicate dictionary key: book')

-- E and G try the unmodified truncated stem before the native auxiliary-e
-- form; doubled consonants instead reduce once and preserve the repeated byte.
local ed_roots = lexicon.from_bytes('stop*Vостановить\nlike*Vнравиться\n')
result = assert(lexicon.lookup(ed_roots, 'stopped'))
assert(result.candidate == 'stop' and result.native_suffix == 'ed')
result = assert(lexicon.lookup(ed_roots, 'liked'))
assert(result.candidate == 'like' and result.native_suffix == 'ed')

local ing_roots = lexicon.from_bytes('run*Vбежать\nrunn*Vбег\nmake*Vделать\n')
result = assert(lexicon.lookup(ing_roots, 'running'))
assert(result.candidate == 'run' and result.native_suffix == 'ing')
result = assert(lexicon.lookup(ing_roots, 'making'))
assert(result.candidate == 'make' and result.native_suffix == 'ing')

-- Failed A-class suffix attempts still write node metadata before a larger
-- hyphenated source is split. buyer-seller reaches `er/A` and sets +0F/+73.
local attempt = assert(lexicon.attempt_fields('buyer-seller'))
assert(attempt.ending == 'er' and attempt.selector == 'A')
assert(attempt.fields[0x0F] == 0x61 and attempt.fields[0x73] == 1)
attempt = assert(lexicon.attempt_fields('fastest'))
assert(attempt.ending == 'est' and attempt.selector == 'A')
assert(attempt.fields[0x0F] == 0x61 and attempt.fields[0x73] == 2)

print('suffixes_test: passed')
