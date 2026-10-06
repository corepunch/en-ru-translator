-- Historical captures are explicitly selected; never present cached text as a fresh EXE run.
local dictionary_store = require "dictionary_store"
local translator = require "core.translator"
local cached, refs, data = false, "LTGOLD/refs", "LTGOLD"
for _, option in ipairs(arg) do
  if option == "--cached" then cached = true
  elseif option:match("^%-%-refs=") then refs = option:sub(8)
  elseif option:match("^%-%-data=") then data = option:sub(8)
  else error("unknown option: " .. option) end
end
if not cached then
  io.stderr:write("Usage: lua demo/compare_ltpro.lua --cached [--refs=LTGOLD/refs] [--data=LTGOLD]\n")
  os.exit(2)
end
local sentences = {
  "She can speak Russian.", "He is in the house.", "She sat on the chair.",
  "He must not go.", "The dog that I saw ran away.", "He was arrested by the police.",
  "You are standing in an open field.", "The house door is open.",
  "He cannot go.", "She has been seen.",
}
local english, russian = dictionary_store.load(data .. "/BASE.DIC", data .. "/BASE.RUS")
local engine = translator.new(english, russian)
local passed, failed, missing = 0, 0, 0
print("HISTORICAL LTPRO captures; no emulator run. Lua dictionaries: " .. data)
for _, sentence in ipairs(sentences) do
  local slug = sentence:gsub(" ", "_"):gsub("[^%w_]", ""):sub(1, 40)
  local file = io.open(refs .. "/" .. slug .. ".txt", "rb")
  if not file then
    missing = missing + 1
    print("MISSING " .. sentence)
  else
    local reference = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    -- Compare the translation paragraph; the old wrapper compared its meanings appendix too.
    reference = reference:match("^(.-)\n%s*\n") or reference
    reference = reference:gsub("\n+$", "")
    local output, err = engine:translate(sentence)
    if output == reference then
      passed = passed + 1
      print("PASS " .. sentence)
    else
      failed = failed + 1
      print("FAIL " .. sentence .. "\n  LTPRO: " .. reference .. "\n  Lua:   " .. (output or tostring(err)))
    end
  end
end
print(string.format("Exact translation text: PASS=%d FAIL=%d MISSING=%d", passed, failed, missing))
os.exit(failed == 0 and missing == 0 and 0 or 1)
