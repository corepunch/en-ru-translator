local assets = require "core.assets"
local lexicon = require "core.lexicon"
local encoding = require "core.encoding"

local function bytes(path)
	local file = assert(io.open(path, "rb"))
	local body = file:read("a")
	file:close()
	return body
end
local executable = assets.new(bytes("LTGOLD/LTPRO.EXE"))
local dictionary = lexicon.from_bytes(bytes("LTGOLD/BASE.DIC"))

local function sources(text)
	local state = lexicon.analyze(dictionary, encoding.encode(text))
	local result, words = {}, {}
	for index = 0, state.count - 1 do
		local node = state.vector[index]
		if node[0x0E] == 0x57 then
			table.insert(result, node[0x12])
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
	assert(vector[1][0x87] == #stem and vector[2][0x87] == #inserted)
	assert(vector[2][0x10] == 0)
	assert(vector[2][0x0F] == (kind == "X" and 0x27 or 0))
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
print("contractions_test: passed")
