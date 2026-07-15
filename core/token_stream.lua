-- Token stream with analyzer metadata kept atomically alongside each lexical token.
local stream = {}

stream.fields = {
  "caps", "phrases", "source", "component_caps",
  -- LTPRO token-node fields mirrored from +0x0c, +0x0f, +0x66, +0x72,
  -- +0x74, +0x76, and +0x77 while packed strings remain compiler-compatible.
  "tag", "status", "derived_tag", "context", "secondary_type",
  "flags", "constituent_type",
  -- Lua retains the setting table with each node so guard provenance survives moves.
  "constituent_flags", "prev", "next",
}

function stream.relink(tokens)
  -- LTPRO keeps sentence order in token-node links; rebuild their index-based
  -- equivalent whenever Lua inserts, removes, or reorders an entry.
  stream.ensure(tokens)
  for i = 1, #tokens do
    tokens.prev[i] = i > 1 and i - 1 or false
    tokens.next[i] = i < #tokens and i + 1 or false
  end
end

local function field_value(field, token, metadata)
  local value = metadata and metadata[field]
  if value ~= nil then return value end
  local tag = token and token:sub(1, 1) or false
  if field == "tag" then return tag end
  if field == "derived_tag" then
    return tag and tag:match("%a") and tag:upper() or tag
  end
  if field == "status" then
    return tag and tag:match("%a") and "w" or false
  end
  return false
end

function stream.new()
  local tokens = {}
  for _, field in ipairs(stream.fields) do tokens[field] = {} end
  return tokens
end

function stream.ensure(tokens)
  for _, field in ipairs(stream.fields) do tokens[field] = tokens[field] or {} end
  return tokens
end

function stream.metadata(tokens, index)
  local result = {}
  for _, field in ipairs(stream.fields) do result[field] = tokens[field] and tokens[field][index] end
  return result
end

function stream.set_metadata(tokens, index, metadata)
  stream.ensure(tokens)
  metadata = metadata or {}
  for _, field in ipairs(stream.fields) do
    tokens[field][index] = field_value(field, tokens[index], metadata)
  end
end

function stream.insert(tokens, index, token, metadata)
  stream.ensure(tokens)
  table.insert(tokens, index, token)
  metadata = metadata or {}
  for _, field in ipairs(stream.fields) do
    table.insert(tokens[field], index, field_value(field, token, metadata))
  end
  stream.relink(tokens)
end

function stream.append(tokens, token, metadata)
  stream.insert(tokens, #tokens + 1, token, metadata)
end

function stream.remove(tokens, index)
  local metadata = stream.metadata(tokens, index)
  local token = table.remove(tokens, index)
  for _, field in ipairs(stream.fields) do
    if tokens[field] then table.remove(tokens[field], index) end
  end
  stream.relink(tokens)
  return token, metadata
end

function stream.snapshot(tokens, positions)
  local result = {}
  for i, position in ipairs(positions) do
    result[i] = { token = tokens[position], metadata = stream.metadata(tokens, position) }
  end
  return result
end

function stream.write(tokens, position, entry)
  tokens[position] = entry.token
  stream.set_metadata(tokens, position, entry.metadata)
  stream.relink(tokens)
end

function stream.set_token(tokens, position, token, metadata)
  -- Grammar rewrites mutate +0x0c in LTPRO but retain the entry-derived fields.
  -- Mirror that behavior by updating the packed value and primary tag atomically.
  tokens[position] = token
  stream.ensure(tokens)
  tokens.tag[position] = token and token:sub(1, 1) or false
  for field, value in pairs(metadata or {}) do
    if tokens[field] then tokens[field][position] = value end
  end
end

return stream
