local transliteration = require "core.transliteration"
for _, case in ipairs(dofile(assert(arg[1]))) do
	local result = transliteration.convert(case.source, case.preserveCase)
	print((result:gsub(".", function(character) return string.format("%02x", character:byte()) end)))
end
