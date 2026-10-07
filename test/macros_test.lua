local lexicon = require "core.lexicon"
local nodes = require "core.nodes"
local encoding = require "core.encoding"
local transliteration = require "core.transliteration"
local function cp(value) return encoding.encode(value) end

-- Original 0A4F:0B3C: supplied Cyrillic, source transliteration, case modes,
-- disabled transliteration, and the empty-source destination contract.
for _, marker in ipairs({ "=", "%" }) do
	for _, enabled in ipairs({ true, false }) do
		for _, source in ipairs({ "Aaron", "ABC", "th", "" }) do
			for _, supplied in ipairs({ "", "имя", "ignored" }) do
				local node = nodes.new("N", { [0x12] = source, [0x0B] = 1, [0x11C] = "kept" })
				lexicon.decode_reading(node, cp(marker .. supplied), { transliterate = enabled })
				local expected
				if marker == "=" and not enabled then expected = cp(supplied)
				elseif supplied == "имя" then expected = cp(supplied)
				elseif source == "" then expected = "kept"
				else expected = transliteration.convert(source, marker == "=") end
				assert(node[0x11C] == expected)
				assert(node[0x0F] == marker:byte())
				assert(node[0x0B] == ((enabled or marker == "%" or supplied ~= "") and 3 or 1))
			end
		end
	end
end
local phraseOwned = nodes.new("N", { [0x12] = "Aaron", [0x0F] = 0x77, [0x11C] = "prepared" })
lexicon.decode_reading(phraseOwned, "=")
assert(phraseOwned[0x11C] == "prepared" and phraseOwned[0x0F] == 0x3D)

-- Native 211E:003A/0E82 outputs, including contextual and unusual rules.
for source, expected in pairs({
	Aaron = "Аарон", Abalone = "Абалоун", Ivanova = "Иванова", th = "т",
	yce = "исе", ABC = "АБК", action = "акшн", ought = "оухт", ewe = "Eюе",
}) do
	assert(transliteration.convert(source, true) == cp(expected), source)
end
assert(transliteration.convert("ABC", false) == cp("абк"))

-- Audit the whole literal-key macro inventory, including compound W entries.
local file = assert(io.open("LTGOLD/BASE.DIC", "rb"))
local dictionary = lexicon.from_bytes(file:read("*a")); file:close()
local audited = 0
for _, record in ipairs(dictionary.records) do
	if record.key:match("^[%a .'-]+$") and record.value:find("[=%%]") and record.value:sub(1, 1) ~= "$" then
		local ok, result = pcall(lexicon.analyze, dictionary, record.key .. ".")
		assert(ok, record.key .. ": " .. tostring(result))
		audited = audited + 1
	end
end
assert(audited == 5801, "macro inventory changed; audit new entries")
local redirected = lexicon.analyze(dictionary, "Welch.")
assert(redirected.vector[1][0x12] == "welsh")
assert(redirected.vector[1][0x11C] == cp("уэльский"))
local compound = lexicon.analyze(dictionary, "Allen town.")
assert(compound.vector[1][0x11C] == cp("аллен") and compound.vector[2][0x11C] == cp("таун"))
assert(compound.vector[1][0x0F] == 0x3D and compound.vector[2][0x0F] == 0x77)
local joined = lexicon.analyze(dictionary, "Bel Air.").vector[1]
assert(joined[0x12] == "Bel Air" and joined[0x11C] == cp("бел эр"))
assert(joined[0x87] == 3 and joined[0x0F] == 0x3D)
print("macros_test: passed (5801 dictionary entries)")
