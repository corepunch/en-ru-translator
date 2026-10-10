local lexicon = require "core.lexicon"
local encoding = require "core.encoding"

local function bytes(path)
	local file = assert(io.open(path, "rb"))
	local body = file:read("a")
	file:close()
	return body
end
-- The original executable is the oracle: read its data segment directly.
local segment = bytes("LTGOLD/LTPRO.EXE"):sub(0x26751)
local executable = {}
function executable:word(at) return string.unpack("<I2", segment, at + 1) end
function executable:indirect(at)
	local p = self:word(at)
	return segment:sub(p + 1, segment:find("\0", p + 1, true) - 1)
end
local dictionary = lexicon.from_bytes(bytes("LTGOLD/BASE.DIC"))

local function sources(text)
	local state = lexicon.analyze(dictionary, encoding.encode(text))
	local result, words = {}, {}
	for index = 0, state.count - 1 do
		local node = state.vector[index]
		if node.kind == 0x57 then
			table.insert(result, node.source)
			table.insert(words, node)
		end
	end
	return table.concat(result, " "), words
end

-- Read every row from LTPRO itself: a missing copied row fails this test.
local at, count = 0x930, 0
while executable:word(at) ~= 0 do
	local ending = executable:indirect(at)
	local kind = executable:indirect(at + 4)
	local inserted = executable:indirect(at + 8)
	local selector = executable:word(at + 16)
	local input = selector == 4 and "let's" or selector == 2 and "cannot" or "he" .. ending
	local stem = selector == 4 and "let" or selector == 2 and "can" or "he"
	local actual, vector = sources(input)
	assert(actual == stem .. " " .. inserted, input .. " => " .. actual)
	assert(vector[1].source_length == #stem and vector[2].source_length == #inserted)
	assert(vector[2].source_position == 0)
	assert(vector[2].marker == (kind == "X" and 0x27 or 0))
	at, count = at + 18, count + 1
end
assert(count == 9)

for input, expected in pairs({
	["can't"] = "can not", ["won't"] = "will not", ["shan't"] = "shall not",
	["CAN'T"] = "CAN not", ["Won't"] = "Will not",
	["I'm"] = "I am", ["I'd've"] = "I would have",
	["it's"] = "it is", ["there's"] = "there is", ["here's"] = "here is",
	["what's"] = "what is", ["that's"] = "that is", ["who's"] = "who is",
	["John's book"] = "John's book", ["cat's"] = "cat's", ["O'Neil"] = "O'Neil",
	["scannot"] = "scannot", ["outlet's"] = "outlet's",
}) do
	local actual = sources(input)
	assert(actual == sources(expected), input .. " => " .. actual)
end
for _, apostrophe in ipairs({ "'", "’", "‘" }) do
	assert(sources("I" .. apostrophe .. "m") == sources("I am"))
	assert(sources("you" .. apostrophe .. "re") == sources("you are"))
	assert(sources("we" .. apostrophe .. "ve") == sources("we have"))
	assert(sources("he" .. apostrophe .. "s") == sources("he is"))
end
-- Exercise valid pronoun/auxiliary combinations, casing and apostrophe forms.
-- These lexical invariants complement the full-sentence executable captures.
local combinations = {
  {pronouns={'I'}, ending='m', auxiliary='am'},
  {pronouns={'you','we','they'}, ending='re', auxiliary='are'},
  {pronouns={'I','you','we','they'}, ending='ve', auxiliary='have'},
  {pronouns={'he','she','it','there','here','what','that','who'}, ending='s', auxiliary='is'},
  {pronouns={'I','you','he','she','it','we','they'}, ending='ll', auxiliary='will'},
  {pronouns={'I','you','he','she','it','we','they'}, ending='d', auxiliary='would'},
  {pronouns={'I','you','he','she','it','we','they'}, ending="d've", auxiliary='would have'},
}
local matrix_count=0
for _, row in ipairs(combinations) do
  for _, pronoun in ipairs(row.pronouns) do
    for _, apostrophe in ipairs({"'",'’','‘'}) do
      for _, casing in ipairs({'lower','title','upper'}) do
        local stem=pronoun:lower()
        if casing=='title' then stem=stem:sub(1,1):upper()..stem:sub(2)
        elseif casing=='upper' then stem=stem:upper() end
        local ending=row.ending:gsub("'",apostrophe)
        if casing=='upper' then ending=ending:upper() end
        local input=stem..apostrophe..ending..' testing this.'
        local expected=sources(stem..' '..row.auxiliary..' testing this.')
        local actual=sources(input)
        assert(actual==expected,input..' => '..actual..' / '..expected)
        matrix_count=matrix_count+1
      end
    end
  end
end
assert(matrix_count==333)
print("contractions_test: passed")
