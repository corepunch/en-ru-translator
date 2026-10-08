-- Minimal provider for OpenCorpora tagged forms. It deliberately has no
-- dependency on LTPRO's executable tables or the legacy 7-bit paradigm IDs.
local morphology = {}

local function has_all(tags, required)
  for _, tag in ipairs(required) do
    if not tags[tag] then return false end
  end
  return true
end

local function has_any(tags, excluded)
  for _, tag in ipairs(excluded) do
    if tags[tag] then return true end
  end
  return false
end

function morphology.new(data)
  assert(type(data) == 'table' and type(data.lexemes) == 'table'
    and type(data.paradigms) == 'table', 'invalid morphology data')
  local by_lemma = {}
  for _, lexeme in ipairs(data.lexemes) do
    local paradigm = assert(data.paradigms[lexeme.paradigm], 'missing source paradigm')
    assert(type(lexeme.lemma) == 'string' and type(lexeme.stem) == 'string'
      and type(paradigm) == 'table', 'invalid lexeme')
    by_lemma[lexeme.lemma] = by_lemma[lexeme.lemma] or {}
    local tags = {}
    for _, tag in ipairs(lexeme.tags or {}) do tags[tag] = true end
    local forms = {}
    for _, form in ipairs(paradigm) do
      local form_tags = {}
      for _, tag in ipairs(form.tags) do form_tags[tag] = true end
      forms[#forms + 1] = {
        word=form.prefix .. lexeme.stem .. form.suffix,
        tags=form_tags,
      }
    end
    by_lemma[lexeme.lemma][#by_lemma[lexeme.lemma] + 1] = {
      pos=lexeme.pos, tags=tags, forms=forms,
    }
  end

  local provider = {source=data.source, source_version=data.source_version,
    source_revision=data.source_revision}

  -- Return every source-listed form that contains all requested grammemes.
  -- Requests should include a POS grammeme (e.g. NOUN or VERB) to disambiguate.
  function provider.forms(lemma, required, excluded)
    assert(type(lemma) == 'string' and type(required) == 'table', 'invalid form request')
    excluded = excluded or {}
    local matches, seen = {}, {}
    for _, lexeme in ipairs(by_lemma[lemma] or {}) do
      for _, form in ipairs(lexeme.forms) do
        if has_all(form.tags, required) and not has_any(form.tags, excluded) and not seen[form.word] then
          seen[form.word] = true
          matches[#matches + 1] = form.word
        end
      end
    end
    table.sort(matches)
    return #matches > 0 and matches or nil
  end

  function provider.lemmas()
    local out = {}
    for lemma in pairs(by_lemma) do out[#out + 1] = lemma end
    table.sort(out)
    return out
  end

  return provider
end

return morphology
