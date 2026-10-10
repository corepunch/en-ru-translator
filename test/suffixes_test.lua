-- Candidate fallbacks observed in captured LTPRO lexical fixtures. The
-- dictionary file supplies the native base records; only candidate derivation
-- is under test here.
local lexicon = require 'core.lexicon'
local file = assert(io.open('LTGOLD/BASE.DIC', 'rb'))
local base = lexicon.from_bytes(file:read('*a'))
file:close()

local fixtures = {
  { id = 'case-060', source = 'books', candidate = 'book', tag = 'Z', suffix = 's', fields = {number=1,person=3} },
  { id = 'case-061', source = 'books', candidate = 'book', tag = 'Z', suffix = 's' },
  { id = 'case-070', source = 'books', candidate = 'book', tag = 'Z', suffix = 's' },
  { id = 'case-014', source = 'organizations', candidate = 'organization', tag = 'N', suffix = 's' },
  { id = 'case-013', source = 'defined', candidate = 'define', tag = 'E', suffix = 'ed', fields = {tense=1,case_mask=8} },
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
    assert(result.fields[offset] == value, fixture.id .. ' field ' .. offset)
  end
end

local rows = lexicon.suffix_rows()
assert(rows[11].ending == 'ies' and rows[11].selector == 'Z13')
assert(rows[12].ending == 'es' and rows[12].selector == 'Z13')
assert(rows[13].ending == 's' and rows[13].selector == 'Z13')
assert(rows[33].ending == 'ly' and rows[33].selector == 'D')

local no_root = lexicon.from_bytes('word*Nслово\n')
local result, reason = lexicon.lookup(no_root, 'unknownness')
assert(result == nil and reason == nil)

-- Derivational nouns do not invent a stem. Adjectives and possessives do.
-- The surface word is still marked as a noun when the ending is N-class.
local derived = lexicon.from_bytes('strong*Aпрочный\nsoft*Dмягко\ncat*Nкошка\ndog*Nсобака\nbusy*Aзанятый\n')
result, reason = lexicon.lookup(derived, 'strongness')
assert(result == nil and reason == nil)
local surface = assert(lexicon.surface_noun('strongness'))
assert(surface.tag == 'N' and surface.ending == 'ness' and surface.selector == 'N00')
assert(surface.fields.number == 0 and surface.fields.case_mask == 0)
assert(lexicon.surface_noun('xyzment').ending == 'ment')
assert(lexicon.surface_noun('stronger') == nil)
assert(lexicon.surface_noun('books') == nil)
assert(lexicon.surface_noun("cat's") == nil)
assert(lexicon.surface_noun('xyzzy') == nil)
local noun_matrix=0
for _,ending in ipairs({'ness','ment','ion','ence','ance','enc','anc','ity','age','ure','ag','nes','or','ur'}) do
  for _,stem in ipairs({'xyz','strong','foo','unrecognized'}) do
    for _,source in ipairs({stem..ending,(stem..ending):upper(),stem:sub(1,1):upper()..stem:sub(2)..ending}) do
      local result=lexicon.analyze(no_root,source).vector[1]
      -- Earlier plural -es (Z13) wins before truncated -nes, and LTPRO tags a
      -- word a Z row matched without a stem #.
      local shadowed=ending=='nes'
      assert(result.source==source and result.tag==string.byte(shadowed and '#' or 'N') and result.previous_tag==0,source)
      assert(result.reading_state==1 and result.person==3 and result.number==0 and result.case_mask==0,source)
      noun_matrix=noun_matrix+1
    end
  end
end
assert(noun_matrix==168)
local analyzed = lexicon.analyze(derived, 'strongness')
local marked
local node = analyzed.root.next
while node do
  if node.source == 'strongness' then marked = node end
  node = node.next
end
assert(marked and marked.tag == string.byte('N') and marked.previous_tag == 0)
assert(marked.reading_state == 1 and marked.person == 3 and marked.gender == 1)
assert(marked.number == 0 and marked.case_mask == 0)
-- A hyphenated unknown word splits, as in LTPRO (foo / - / ness).
local hyphenated = lexicon.analyze(no_root, 'foo-ness')
assert(hyphenated.count == 5 and hyphenated.vector[1].source == 'foo' and hyphenated.vector[3].source == 'ness')
result = assert(lexicon.lookup(derived, 'stronger'))
assert(result.candidate == 'strong' and result.tag == 'A' and result.native_suffix == 'er')
assert(result.fields.marker == 0x61 and result.fields.tense == 1)
result = assert(lexicon.lookup(derived, 'strongest'))
assert(result.candidate == 'strong' and result.fields.tense == 2 and result.fields.marker == 0x61)
result = assert(lexicon.lookup(derived, "cat's"))
assert(result.candidate == 'cat' and result.tag == 'N' and result.native_suffix == "'s")
assert(result.fields.number == 0 and result.fields.case_mask == 2)
result = assert(lexicon.lookup(derived, "dogs'"))
assert(result.candidate == 'dog' and result.native_suffix == "s'")
assert(result.fields.number == 1 and result.fields.case_mask == 2)
result = assert(lexicon.lookup(derived, 'busier'))
assert(result.candidate == 'busy' and result.native_suffix == 'ier' and result.fields.tense == 1)
-- LTPRO cuts ies' without restoring y (ladies' -> lad, cities' -> cit).
local possessives=lexicon.from_bytes('city*Nгород\nlad*Nпарень\nhouse*Nдом\nclass*Nкласс\n')
for source,stem in pairs({["ladies'"]='lad',["houses'"]='house',["classes'"]='class'}) do
  local found=assert(lexicon.lookup(possessives,source))
  assert(found.candidate==stem and found.fields.number==1 and found.fields.case_mask==2)
end
assert(not lexicon.lookup(possessives,"cities'"))

local duplicate = lexicon.from_bytes('book*Zкнига\nbook*Nкнижка\n')
result, reason = lexicon.lookup(duplicate, 'books')
assert(result.record == duplicate.records[1] and reason == nil)
result = assert(lexicon.lookup(duplicate, 'books', {dictionary_entry = function() return 2 end}))
assert(result.record == duplicate.records[2])

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
assert(attempt.fields.marker == 0x61 and attempt.fields.tense == 1)
attempt = assert(lexicon.attempt_fields('fastest'))
assert(attempt.ending == 'est' and attempt.selector == 'A')
assert(attempt.fields.marker == 0x61 and attempt.fields.tense == 2)

print('suffixes_test: passed')
