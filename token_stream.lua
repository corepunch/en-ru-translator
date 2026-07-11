-- Token stream with analyzer metadata kept atomically alongside each lexical token.
local stream = {}

stream.fields = { "caps", "phrases", "source", "component_caps" }

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
  for _, field in ipairs(stream.fields) do tokens[field][index] = metadata[field] end
end

function stream.insert(tokens, index, token, metadata)
  stream.ensure(tokens)
  table.insert(tokens, index, token)
  metadata = metadata or {}
  for _, field in ipairs(stream.fields) do table.insert(tokens[field], index, metadata[field]) end
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
end

return stream
