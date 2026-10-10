-- Per-token and per-rule trace for one sentence. No LTPRO capture required.
-- Used by `lua init.lua --trace`.
local nodes = require 'core.nodes'
local rules = require 'core.rules'
local encoding = require 'core.encoding'

local trace = {}

local function text(value)
  if type(value) ~= 'string' or value == '' then return '' end
  local ok, decoded = pcall(encoding.decode, value)
  return (ok and decoded or value):gsub('[%c]', ' ')
end

local function field(node, name)
  local value = nodes.number(node, name)
  return value ~= 0 and tostring(value) or nil
end

function trace.tokens(root)
  local vector, count = nodes.vector(root)
  local rows = {}
  for i = 0, count - 1 do
    local node = vector[i]
    local parts = {
      string.format('%d', i + 1),
      'source=' .. text(node.source),
      'tag=' .. nodes.tag(node),
    }
    local kind = node.kind and string.char(node.kind) or ''
    if kind ~= '' then parts[#parts + 1] = 'kind=' .. kind end
    local lookup = text(node.lookup)
    if lookup ~= '' then parts[#parts + 1] = 'lookup=' .. lookup end
    local reading = text(node.reading)
    if reading ~= '' then parts[#parts + 1] = 'reading=' .. reading end
    local generated = text(node.text)
    if generated ~= '' and generated ~= reading then parts[#parts + 1] = 'text=' .. generated end
    for _, name in ipairs({'passive', 'tense', 'aspect', 'short_form', 'person', 'gender', 'number', 'case_mask'}) do
      local value = field(node, name)
      if value then parts[#parts + 1] = name .. '=' .. value end
    end
    rows[#rows + 1] = table.concat(parts, '\t')
  end
  return rows
end

local tables = {T1 = 1, T2 = 2, T3 = 3, T4 = 4}

local function rule_text(stage, index)
  local table_index = tables[stage]
  local rule = table_index and rules[table_index] and rules[table_index][index]
  if not rule then return end
  local pattern, action = rule[2], rule[3]
  return pattern, action
end

function trace.rules(stages)
  local rows = {}
  for _, stage in ipairs({'T1', 'T2', 'T3', 'T4'}) do
    local result = stages and stages[stage]
    for _, event in ipairs(result and result.events or {}) do
      local pattern, action = event.pattern, event.action
      if not pattern then pattern, action = rule_text(stage, event.rule) end
      local span = event.last and string.format('%d-%d', (event.first or 0) + 1, event.last + 1) or tostring((event.first or 0) + 1)
      local parts = {
        stage,
        event.rule and ('#' .. event.rule) or 'sub',
        'nodes=' .. span,
      }
      if event.handler then parts[#parts + 1] = 'handler=' .. event.handler end
      if event.selector then parts[#parts + 1] = 'selector=' .. event.selector end
      if event.stale then parts[#parts + 1] = 'stale' end
      if pattern and pattern ~= '' then parts[#parts + 1] = 'pattern=' .. pattern end
      if action and action ~= '' then parts[#parts + 1] = 'action=' .. action end
      rows[#rows + 1] = table.concat(parts, '\t')
    end
  end
  return rows
end

function trace.format(translation, state)
  local lines = {'translation:\t' .. (translation or '')}
  lines[#lines + 1] = '# tokens'
  local root = state and state.root
  if root then
    for _, row in ipairs(trace.tokens(root)) do lines[#lines + 1] = row end
  end
  lines[#lines + 1] = '# rules'
  for _, row in ipairs(trace.rules(state and state.stages)) do lines[#lines + 1] = row end
  if state and state.stages and state.stages.T1 then
    lines[#lines + 1] = '# tags\t' .. (state.stages.T4 and state.stages.T4.tags or state.stages.T1.tags or '')
  end
  return table.concat(lines, '\n')
end

return trace
