-- Token stream with analyzer metadata kept atomically alongside each lexical token.
local stream = {}

stream.fields = { "caps", "phrases", "source", "component_caps", "constituent_flags" }

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
  -- Optional native metadata is sparse; its length is the lexical vector's length.
  for _, field in ipairs(stream.fields) do
    for i = #tokens, index + 1, -1 do tokens[field][i] = tokens[field][i - 1] end
    tokens[field][index] = metadata[field]
  end
end

function stream.append(tokens, token, metadata)
  stream.insert(tokens, #tokens + 1, token, metadata)
end

function stream.remove(tokens, index)
  local metadata = stream.metadata(tokens, index)
  local token = table.remove(tokens, index)
  for _, field in ipairs(stream.fields) do
    if tokens[field] then
      for i = index, #tokens do tokens[field][i] = tokens[field][i + 1] end
      tokens[field][#tokens + 1] = nil
    end
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

-- Numeric actions exchange live slots in sequence (LTPRO 0x165A1), not snapshot indices.
function stream.reorder(tokens, positions, digits)
  for i = 1, #digits do
    local target = digits:byte(i) - 0x30
    local a, b = positions[i], positions[target]
    assert(a and b, "numeric action outside matched span")
    local pair = stream.snapshot(tokens, { a, b })
    stream.write(tokens, a, pair[2])
    stream.write(tokens, b, pair[1])
  end
end

return stream
