-- test/zork_test.lua — Tests based on the Zork I transcript
-- The objective of this translator is text adventure games.
-- Zork I is the canonical example. These tests verify our ability to translate
-- the core game commands and environmental descriptions.

local load_mod = require "core.load"
local utils = require "core.utils"
local parser = require "core.parser"
local compiler = require "core.compiler"

local file = assert(io.open("data/BASE.DIC", "r"))
local file2 = assert(io.open("data/BASE.RUS", "r"))
local en_ru = {}
compiler.base = {}
for line in file:lines() do
  load_mod.lingua(en_ru, line:gsub("%b{}", ""):gsub("%.", ""):gsub("%*([A-Z])%1W", "*W"))
end
for line in file2:lines() do
  local w, code = line:match("^(.-)\x2a(.*)$")
  if code then compiler.base[utils.decode(w)] = code end
end
file:close(); file2:close()

-- Zork test cases from the transcript
-- Format: { group, input, expected_approximate }
-- We check for KEY WORDS rather than exact match, since perfect translation
-- of a full adventure game is beyond current capability.
local cases = {

  -- =========================================================================
  -- ROOM DESCRIPTIONS (the most important pattern in text adventures)
  -- =========================================================================

  -- Opening scene
  { "ROOM", "You are standing in an open field west of a white house.",
    "поле запад белый дом" },

  { "ROOM", "There is a small mailbox here.",
    "ящик" },

  -- Room names
  { "ROOM", "You are in the kitchen of the white house.",
    "кухня дом" },

  { "ROOM", "You are in the living room.",
    "гостиная" },

  { "ROOM", "This is a small room with passages to the east and south.",
    "комната проход" },

  { "ROOM", "You are in a dark and damp cellar with a narrow passageway leading north.",
    "подвал тёмный узкий" },

  { "ROOM", "This is a circular stone room with passages in all directions.",
    "комната круглый камень проход" },

  -- =========================================================================
  -- OBJECT DESCRIPTIONS (how items appear in rooms)
  -- =========================================================================

  { "OBJ", "There is a brass bell here.",
    "звонок" },

  { "OBJ", "A battery-powered brass lantern is on the trophy case.",
    "фонарь" },

  { "OBJ", "Above the trophy case hangs an elvish sword of great antiquity.",
    "меч" },

  { "OBJ", "On the table is an elongated brown sack, smelling of hot peppers.",
    "мешок стол" },

  { "OBJ", "The glass bottle contains: A quantity of water.",
    "бутылка вода" },

  { "OBJ", "A nasty-looking troll, brandishing a bloody axe, blocks all passages out of the room.",
    "тролль топор" },

  { "OBJ", "There is an exquisite jade figurine here.",
    "фигурка" },

  { "OBJ", "The solid-gold coffin used for the burial of Ramses II is here.",
    "гроб золотой" },

  { "OBJ", "On the altar is a large black book, open to page 569.",
    "книга алтарь" },

  -- =========================================================================
  -- PLAYER ACTIONS (what the player types)
  -- =========================================================================

  -- Movement
  { "ACT", "go south", "юг" },
  { "ACT", "go east", "восток" },
  { "ACT", "go north", "север" },
  { "ACT", "go west", "запад" },
  { "ACT", "go down", "вниз" },
  { "ACT", "go up", "вверх" },
  { "ACT", "enter house", "дом" },
  { "ACT", "go southwest", "юго-запад" },

  -- Object interaction
  { "ACT", "open mailbox", "открыть ящик" },
  { "ACT", "read leaflet", "листовка" },
  { "ACT", "take lamp", "фонарь" },
  { "ACT", "drop knife", "нож" },
  { "ACT", "open case", "открыть" },
  { "ACT", "turn on lamp", "фонарь" },
  { "ACT", "turn off lamp", "фонарь" },
  { "ACT", "move rug", "ковёр" },

  -- =========================================================================
  -- ACTION RESPONSES (what the game says after an action)
  -- =========================================================================

  { "RESP", "Taken.", "взято" },
  { "RESP", "Dropped.", "брошено" },
  { "RESP", "Done.", "готово" },
  { "RESP", "Opened.", "открыто" },

  { "RESP", "You are carrying: A brass lantern.", "несёте фонарь" },
  { "RESP", "Your load is too heavy.", "слишком тяжело" },

  -- =========================================================================
  -- COMBAT (critical for dungeon crawl games)
  -- =========================================================================

  { "COMBAT", "The troll's mighty blow drops you to your knees.",
    "удар тролль" },

  { "COMBAT", "The troll is confused and can't fight back.",
    "тролль сбит с толку" },

  { "COMBAT", "The troll is knocked out!",
    "тролль" },

  { "COMBAT", "Your sword is glowing with a faint blue glow.",
    "меч светиться" },

  -- =========================================================================
  -- ENVIRONMENTAL (weather, light, sound)
  -- =========================================================================

  { "ENV", "The brass lantern is now on.",
    "фонарь" },

  { "ENV", "The brass lantern is now off.",
    "фонарь" },

  { "ENV", "Time passes...",
    "время" },

  { "ENV", "The trap door crashes shut, and you hear someone barring it.",
    "дверь" },

  -- =========================================================================
  -- COMMON GAME PHRASES
  -- =========================================================================

  { "PHRASE", "You are in the living room. There is a doorway to the east.",
    "гостиная дверь восток" },

  { "PHRASE", "This appears to have been an artist's studio.",
    "студия художник" },

  { "PHRASE", "A large coil of rope is lying in the corner.",
    "верёвка угол" },

  { "PHRASE", "This is the attic. The only exit is a stairway leading down.",
    "чердак лестница вниз" },

  { "PHRASE", "You are at the top of Aragain Falls, an enormous waterfall.",
    "водопад" },

  { "PHRASE", "The river is running faster here.",
    "река быстро" },

  -- =========================================================================
  -- DIRECTIONAL VOCABULARY
  -- =========================================================================

  { "DIR", "You are facing the south side of a white house.",
    "юг дом" },

  { "DIR", "In one corner of the house there is a small window which is slightly ajar.",
    "окно" },

  { "DIR", "A passage leads into the forest to the east.",
    "проход лес восток" },

  { "DIR", "A dark chimney leads down and to the east is a small window which is open.",
    "камин вниз восток окно" },

  { "DIR", "Passages lead off to the east, northwest and southwest.",
    "проход восток северо-запад юго-запад" },
}

local passed, failed, total = 0, 0, 0

-- Simple Cyrillic lowercase helper
local function cyrillic_lower(s)
  local result = {}
  for i = 1, #s do
    local b = s:byte(i)
    -- ASCII lowercase A-Z (0x41-0x5A) -> a-z (0x61-0x7A)
    if b >= 0x41 and b <= 0x5A then
      result[#result+1] = b + 0x20
    else
      result[#result+1] = b
    end
  end
  return string.char(table.unpack(result))
end

for _, case in ipairs(cases) do
  local group, input, expected_words = case[1], case[2], case[3]
  total = total + 1

  local tokens = utils.tokenize(input, en_ru)
  local parsed, err = parser.collect(en_ru, tokens)

  if not parsed then
    print(string.format("FAIL [%s] %s", group, input))
    print(string.format("  parse error: %s", err))
    failed = failed + 1
  else
    local got = compiler.compile(parsed, { quiet = true })
    local got_lower = cyrillic_lower(got)

    -- Check if key words are present in the output
    local words_ok = true
    local missing_words = {}
    for word in expected_words:gmatch("%S+") do
      if not got_lower:find(word, 1, true) then
        words_ok = false
        missing_words[#missing_words + 1] = word
      end
    end

    if words_ok then
      passed = passed + 1
    else
      print(string.format("FAIL [%s] %s", group, input))
      print(string.format("  got: %s", got))
      print(string.format("  missing: %s", table.concat(missing_words, ", ")))
      failed = failed + 1
    end
  end
end

print(string.format("\nzork: %d/%d tests passed", passed, total))
