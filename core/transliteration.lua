-- LTPRO 211E:003A and 0E82: contextual Latin-to-CP866 transliteration.
-- Keep the original spellings, including its unusual pronunciation rules.
local encoding = require "core.encoding"
local transliteration = {}
local function cp(value) return encoding.encode(value) end
local simple = { b = "б", f = "ф", h = "х", l = "л", m = "м", n = "н",
	q = "к", v = "в", z = "з" }
for key, value in pairs(simple) do simple[key] = cp(value) end
local vowels = "aeiouyAEIOUY"
local vowelSounds = cp("аеиоуыАЕИОУЫ")
local function vowel(character)
	return character ~= "" and vowels:find(character, 1, true) ~= nil
end
local function boundary(character)
	return character == "" or character:match("%s") ~= nil
end

local function character(source, lower, index)
	local c, following, third = lower:sub(index, index), lower:sub(index + 1, index + 1), lower:sub(index + 2, index + 2)
	local tail = lower:sub(index + 1)
	local previous = source:sub(index - 1, index - 1)
	if simple[c] then return simple[c], 1 end
	if c == "a" then
		if following == "u" or following == "w" then return cp("о"), 2 end
		if following == "i" then return cp(third == "r" and "еа" or "ей"), 2 end
		if following == "l" and not vowel(third) then
			if third == "k" then return cp("ок"), 2 end
			if third == "l" then return cp("ол"), 2 end
			return cp("а"), 1
		end
		if following == "y" then return cp("ей"), 2 end
		if not vowel(following) and (third == "e" or third == "y") then return cp("ей"), 1 end
		if tail:sub(1, 3) == "ble" then return cp("ейб"), 2 end
		return cp("а"), 1
	elseif c == "c" then
		if following == "h" then return cp("ч"), 2 end
		if following == "e" or following == "i" or following == "y" then return cp("с"), 1 end
		if tail:sub(1, 3) == "ion" then return cp("шн"), 4 end
		if tail:sub(1, 3) == "ial" then return cp("шл"), 4 end
		if index > 1 and tail:sub(1, 3) == "ian" then return cp("шн"), 4 end
		if tail:sub(1, 4) == "ious" then return cp("кшас"), 5 end
		return cp("к"), following == "k" and 2 or 1
	elseif c == "d" then
		if tail:sub(1, 2) == "ge" then return cp("дж"), 3 end
		return cp("д"), 1
	elseif c == "e" then
		if following == "u" or following == "w" then return cp(index == 1 and "Eю" or "ью"), 2 end
		if following == "a" or following == "e" then return cp(third == "r" and "иа" or "и"), 2 end
		if following == "i" then return cp(third == "r" and "еа" or "ей"), 2 end
		if following == "y" then return cp("ей"), 2 end
		if not vowel(following) and (third == "e" or third == "y") then return cp("и"), 1 end
		if index > 3 and not vowel(previous) and boundary(following) then return "", 1 end
		if index > 3 and following == "s" and boundary(third) then return cp("из"), 2 end
		return cp("е"), 1
	elseif c == "g" then
		if following == "e" or following == "i" or following == "y" then return cp("дж"), 2 end
		return following == "h" and "" or cp("г"), 1
	elseif c == "i" then
		if not vowel(following) and (third == "e" or third == "y") then return cp("ай"), 1 end
		if tail:sub(1, 2) == "ld" or tail:sub(1, 2) == "nd" then return cp("ай"), 1 end
		return cp("и"), 1
	elseif c == "j" then return cp("дж"), 1
	elseif c == "k" then return cp(following == "n" and "н" or "к"), following == "n" and 2 or 1
	elseif c == "o" then
		if following == "o" then return cp(third == "r" and "уа" or "у"), 2 end
		if following == "a" then return cp(third == "r" and "о" or "оу"), 2 end
		if following == "e" or lower:sub(index + 2, index + 3) == "ld" then return cp("оу"), 2 end
		if following == "u" then
			if lower:sub(index + 2, index + 4) == "ght" then return cp("о"), 1 end
			return cp(third == "r" and "аа" or "ау"), 2
		end
		if not vowel(following) and (third == "e" or third == "y") then return cp("оу"), 1 end
		return cp("о"), 1
	elseif c == "p" then return cp(following == "h" and "ф" or "п"), following == "h" and 2 or 1
	elseif c == "r" then
		if tail:sub(1, 2) == "ui" then return cp("рю"), 3 end
		return cp("р"), 1
	elseif c == "s" then
		if following == "h" then return cp("ш"), 2 end
		if tail:sub(1, 4) == "tion" then return cp("счн"), 5 end
		if tail:sub(1, 4) == "sion" then return cp("шн"), 5 end
		if tail:sub(1, 3) == "ion" then return cp(index > 1 and vowel(previous) and "жн" or "шн"), 4 end
		return cp("с"), 1
	elseif c == "t" then
		if following == "h" then
			if index == 1 and third == "e" and boundary(lower:sub(index + 3, index + 3)) then return "", 3 end
			if boundary(third) then return cp("т"), 2 end
			if index > 1 and vowel(previous) and third == "e" then return cp("зе"), 3 end
			return cp("т"), 2
		end
		if tail:sub(1, 2) == "ch" then return cp("ч"), 3 end
		if tail:sub(1, 3) == "ion" then return cp("шн"), 4 end
		return cp("т"), 1
	elseif c == "u" then
		if not vowel(following) and (third == "e" or third == "y") then return cp("ьу"), 1 end
		return cp("у"), 1
	elseif c == "w" then
		if following == "r" then return cp("р"), 2 end
		if following == "a" then return cp("уо"), 2 end
		-- The original compares against CP866 о here, rather than ASCII o.
		if following == "h" then return cp(source:byte(index + 2) == 0xAE and "х" or "у"), 2 end
		return cp("у"), 1
	elseif c == "x" then
		if tail:sub(1, 3) == "ion" then return cp("кшн"), 4 end
		if tail:sub(1, 4) == "ious" then return cp("кшас"), 5 end
		return cp("кс"), 1
	elseif c == "y" then
		if vowel(following) then
			local at = assert(vowels:find(following, 1, true))
			return cp("й") .. vowelSounds:sub(at, at), 2
		end
		return cp("и"), 1
	end
	return source:sub(index, index), 1
end

local function upper(byte)
	if byte >= 0xA0 and byte < 0xB0 then return byte - 0x20 end
	if byte >= 0xE0 and byte < 0xF0 then return byte - 0x50 end
	if byte == 0xF1 then return 0xF0 end
	return byte >= 97 and byte <= 122 and byte - 32 or byte
end

function transliteration.convert(source, preserveCase)
	local result, index = {}, 1
	local lower = source:lower()
	while index <= #source do
		local value, consumed = character(source, lower, index)
		if preserveCase and source:sub(index, index):match("%u") then
			local all = source:sub(index + 1, index + 1):match("%u") ~= nil
			local characters = {}
			for position = 1, #value do
				table.insert(characters, string.char((position == 1 or all) and upper(value:byte(position)) or value:byte(position)))
			end
			value = table.concat(characters)
		end
		table.insert(result, value)
		index = index + consumed
	end
	return table.concat(result)
end

return transliteration
