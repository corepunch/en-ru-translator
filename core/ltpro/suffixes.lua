-- Narrow lexical fallback recovered from LTPRO 0A4F:07F2 (file 0x0E6E2).
-- The suffix rows are the native DS:0778 table: ending, class/metadata text.
-- This module only resolves candidates for rows whose transforms are directly
-- visible in the native dispatch. Phrase and annotation handling stays with
-- the lexical analyzer.
local suffixes = {}

-- Native row order matters. For example, `ies` precedes `es` and `s`, and
-- `ed` follows `ied`. The ASCII strings and selectors were read from DS:0778.
local rows = {
  { "ies'", "N12", "unsupported" },
  { "es'", "N12", "unsupported" },
  { "s'", "N12", "unsupported" },
  { "'s", "N02", "unsupported" },
  { "ing", "G8", "ing" },
  { "ied", "E", "ied" },
  { "ed", "E", "ed" },
  { "ness", "N00", "unsupported" },
  { "ous", "A", "unsupported" },
  { "less", "A", "unsupported" },
  { "ies", "Z13", "ies" },
  { "es", "Z13", "es" },
  { "s", "Z13", "s" },
  { "fy", "V", "unsupported" },
  { "ment", "N00", "unsupported" },
  { "ion", "N00", "unsupported" },
  { "ence", "N00", "unsupported" },
  { "ance", "N00", "unsupported" },
  { "enc", "N00", "unsupported" },
  { "anc", "N00", "unsupported" },
  { "ity", "N00", "unsupported" },
  { "age", "N00", "unsupported" },
  { "ure", "N00", "unsupported" },
  { "ag", "N00", "unsupported" },
  { "nes", "N00", "unsupported" },
  { "or", "N00", "unsupported" },
  { "iest", "A", "unsupported" },
  { "ier", "A", "unsupported" },
  { "est", "A", "unsupported" },
  { "eur", "A", "unsupported" },
  { "er", "A", "unsupported" },
  { "ur", "N00", "unsupported" },
  { "ly", "D", "ly" },
  { "ical", "A", "unsupported" },
  { "ic", "A", "unsupported" },
  { "ible", "A", "unsupported" },
  { "able", "A", "unsupported" },
  { "ibl", "A", "unsupported" },
  { "abl", "A", "unsupported" },
  { "ory", "A", "unsupported" },
  { "ary", "A", "unsupported" },
  { "ou", "A", "unsupported" },
  { "les", "A", "unsupported" },
}
for _, row in ipairs(rows) do
  row.ending, row.selector, row.transform = row[1], row[2], row[3]
end

local function ascii_lower(text)
  return (text:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end

local function lookup(dictionary, key)
  local records = dictionary.by_key[ascii_lower(key)]
  if not records then return nil end
  if #records ~= 1 then return nil, "duplicate dictionary key: " .. key end
  return records[1]
end

local function decode_record(record, source, candidate, row, exact)
  local value = record.value or ""
  local tag = value:sub(1, 1)
  if not ("ekxjtudbiplyfgac"):find(tag, 1, true) then tag = tag:upper() end
  local payload = value:sub(2)
  local backref
  local slash = payload:find("\\", 1, true)
  if slash then
    backref = payload:sub(slash + 1)
    payload = payload:sub(1, slash - 1)
  end

  local morphology_tag = row and row.selector:sub(1, 1) or nil
  if row and (row.transform == "ed" or row.transform == "ied") then
    tag = "E"
  elseif row and row.transform == "ing" then
    tag = "G"
  elseif row and row.transform == "ly" then
    tag = "D"
  end

  local fields = {}
  if row and row.selector == "Z13" then
    fields[0x72], fields[0x74] = 1, 3
  elseif row and row.selector == "G8" then
    fields[0x76] = 8
  elseif row and row.selector == "E" then
    fields[0x73], fields[0x76] = 1, 8
  end

  return {
    record = record,
    source = source,
    candidate = candidate,
    exact = exact,
    tag = tag,
    payload = payload,
    backref = backref,
    morphology_tag = morphology_tag,
    native_suffix = row and row.ending or nil,
    native_selector = row and row.selector or nil,
    fields = fields,
  }
end

local function candidates(word, row)
  local ending = row.ending
  local stem = word:sub(1, #word - #ending)
  if row.transform == "ies" then return { stem .. "y" } end
  if row.transform == "s" or row.transform == "es" or row.transform == "ly" then
    if row.transform == "es" then return { stem, stem .. "e" } end
    return { stem }
  end
  if row.transform == "ied" then return { stem .. "y" } end
  if row.transform == "ed" then
    if #stem >= 2 and stem:sub(-1) == stem:sub(-2, -2) then
      return { stem:sub(1, -2) }
    end
    return { stem, stem .. "e" }
  end
  if row.transform == "ing" then
    if #stem >= 2 and stem:sub(-1) == stem:sub(-2, -2) then
      return { stem:sub(1, -2) }
    end
    -- The native G branch writes auxiliary `e` when the truncated stem is
    -- not doubled (0A4F:0E793), just as the E branch inherits it from the
    -- suffix preamble. Try the literal truncated root before that e form.
    return { stem, stem .. "e" }
  end
  return nil
end

-- Resolve one lexical token against exact records, then the bounded native
-- productive endings implemented above. Returns (result, nil), (nil, nil) for
-- no applicable native ending, or (nil, reason) for a recognized but
-- unsupported/ambiguous branch. Result.payload excludes a dictionary backref;
-- callers must apply result.backref only when their native context allows it.
function suffixes.lookup(dictionary, source)
  assert(type(source) == "string" and source ~= "", "suffix lookup needs a source word")
  local word = ascii_lower(source)
  local exact, exact_error = lookup(dictionary, word)
  if exact then return decode_record(exact, source, word, nil, true) end
  if exact_error then return nil, exact_error end

  for _, row in ipairs(rows) do
    if #word > #row.ending and word:sub(-#row.ending) == row.ending then
      if row.transform == "unsupported" then
        return nil, "native suffix row " .. row.ending .. "/" .. row.selector .. " is not ported"
      else
        for _, candidate in ipairs(candidates(word, row)) do
          local record, err = lookup(dictionary, candidate)
          if err then return nil, err end
          if record then
            return decode_record(record, source, candidate, row, false)
          end
        end
        -- 0A4F:07F2 stops at the first table row whose ending matches. Do not
        -- fall through to a shorter ending when its candidate misses.
        return nil, "native suffix candidate missed: " .. row.ending
      end
    end
  end
  return nil
end

-- Return field writes performed by the first matching DS:0778 row, before the
-- caller knows whether its derived dictionary candidate will match. The A
-- dispatch is useful when a larger hyphenated token fails and is split later:
-- native 0A4F:07F2 leaves these two side effects on the first component.
-- Other dispatches also mutate the node, but are deliberately omitted here
-- until their failed-candidate lifetime is independently captured.
function suffixes.attempt_fields(source)
  assert(type(source) == "string" and source ~= "", "suffix attempt needs a source word")
  local word = ascii_lower(source)
  for _, row in ipairs(rows) do
    if #word > #row.ending and word:sub(-#row.ending) == row.ending then
      local fields = {}
      if row.selector == "A" then
        fields[0x0F] = 0x61
        local last, before_last = word:sub(-1), word:sub(-2, -2)
        if last == "r" and (before_last == "e" or before_last == "u") then
          fields[0x73] = 1
        elseif word:sub(-2) == "st" then
          fields[0x73] = 2
        end
      end
      return { ending = row.ending, selector = row.selector, fields = fields }
    end
  end
  return nil
end

-- Expose a defensive copy for fixture tooling; callers cannot change dispatch.
function suffixes.native_rows()
  local out = {}
  for i, row in ipairs(rows) do
    out[i] = { ending = row[1], selector = row[2], transform = row[3] }
  end
  return out
end

return suffixes
