local assets = require 'core.assets'
local russian = require 'core.russian'
local lexicon = require 'core.lexicon'
local grammar = require 'core.grammar'
local phrasing = require 'core.phrasing'
local reorder = require 'core.reorder'
local nodes = require 'core.nodes'
local senses = require 'core.senses'
local constituents = require 'core.constituents'
local agreement = require 'core.agreement'
local syntax = require 'core.syntax'
local generation = require 'core.generation'
local output = require 'core.output'
local encoding = require 'core.encoding'
local prefixes = require 'core.prefixes'
local directives = require 'core.directives'

local engine = {}

local signatures = {
  ['LTPRO.EXE'] = 'MZ',
  ['BASE.RUS'] = 'LTech DIC File 2.00 ',
}

function engine.read_asset(source, name)
  assert(type(source) == 'string', name .. ' must be a path or byte string')
  -- Raw assets may contain embedded NULs that io.open rejects by throwing.
  local ok, file = pcall(io.open, source, 'rb')
  if ok and file then
    local bytes, message = file:read('*a')
    file:close()
    assert(bytes, name .. ' could not be read: ' .. tostring(message))
    return bytes
  end
  local signature = signatures[name]
  assert(not signature or source:sub(1, #signature) == signature,
    name .. ' path is unreadable and value is not recognized asset bytes')
  return source
end

-- Static binary assets are decoded separately from mutable sentence state.
function engine.new_state(exe_source,russian_source)
  return {assets=assets.new(engine.read_asset(exe_source,'LTPRO.EXE')),
    russian=russian.from_bytes(engine.read_asset(russian_source,'BASE.RUS')),
    elements={},tags={},count=0,word_count=0}
end

function engine.run(input, options)
  options = options or {}
  local configured = options
  options = {}
  for key, value in pairs(configured) do options[key] = value end
  assert(type(input) == 'string', 'input sentence must be a UTF-8 string')
  local sections=directives.sections(input)
  if sections then
    local chunks, states, glossary={},{},{}
    local cell_options={}
    for key,value in pairs(options) do cell_options[key]=value end
    cell_options.meanings=false
    local meaning_start=options.meaning_start or 1
    local alternatives=0
    for _,section in ipairs(sections) do
      local items=section.columns and directives.items(section.input) or {section.input}
      local lines,row={},{}
      for index,item in ipairs(items) do
        cell_options.meaning_start=meaning_start+alternatives
        local translated,state=engine.run(item,cell_options)
        alternatives=alternatives+(state.alternatives or 0)
        states[#states+1]=state
        row[#row+1]=translated
        if options.meanings then
          local meanings=output.meanings(state,state.root)
          if meanings~='' then glossary[#glossary+1]=meanings end
        end
        if not section.columns or index%section.columns==0 then
          lines[#lines+1]=table.concat(row,'\t');row={}
        end
      end
      if #row>0 then lines[#lines+1]=table.concat(row,'\t') end
      chunks[#chunks+1]=table.concat(lines,'\n')
    end
    local result=table.concat(chunks,'\n')
    local meanings=table.concat(glossary,'\n')
    if meanings~='' then result=result..'\n\n'..meanings end
    return result,{output=result,text=encoding.decode(result),sections=states,alternatives=alternatives,
      meanings=options.meanings and meanings or nil,
      meanings_text=options.meanings and encoding.decode(meanings) or nil}
  end
  local data = options.data_dir or 'LTGOLD'
  local executable = options.executable or (data .. '/LTPRO.EXE')
  local dic_source = options.dictionary or options.dic or (data .. '/BASE.DIC')
  local rus_source = options.russian or options.rus or (data .. '/BASE.RUS')

  local dic_bytes = engine.read_asset(dic_source, 'BASE.DIC')
  local state = engine.new_state(executable, rus_source)
  state.meaning_start=options.meaning_start
  if options.domain then
    assert(type(options.domain) == 'string' and options.domain ~= '', 'domain must be a nonempty string')
    state.domain=encoding.encode(options.domain)
  end
  if options.prefixes ~= false then
    if type(options.prefixes) == 'string' then
      options.prefixes = prefixes.from_bytes(engine.read_asset(options.prefixes, 'ERPREFIX.PRE'))
      assert(#options.prefixes > 0, 'ERPREFIX.PRE is unreadable or contains no active prefix rows')
    elseif options.prefixes == nil then
      local file = io.open(data .. '/ERPREFIX.PRE', 'rb')
      if file then
        options.prefixes = prefixes.from_bytes(file:read('*a'))
        file:close()
      end
    end
  end
  local dict = lexicon.from_bytes(dic_bytes)
  local analyzed = lexicon.analyze(dict, encoding.encode(input), options)

  local stages = {}
  stages.lexical_word_count = analyzed.word_count or 0
  local grammar_entered = stages.lexical_word_count > 0
  if grammar_entered then
    local t1 = grammar.first(analyzed.root, {terminator = analyzed.terminator})
    stages.T1 = t1
    local grammar_result = t1.result
    if t1.result == 1 then
      local t2 = grammar.second(analyzed.root, {count = t1.count})
      stages.T2 = t2
      local t3 = grammar.third(analyzed.root, {count = t2.count, terminator = analyzed.terminator})
      stages.T3 = t3
      local t4 = phrasing.run(analyzed.root, {count = t3.count, terminator = analyzed.terminator})
      stages.T4 = t4
    end
    if grammar_result ~= 0 then
      local vector, count, rebuilt = reorder.apply(analyzed.root)
      stages.reorder = {vector = vector, count = count, rebuilt = rebuilt}
    end
  end

  nodes.prepare(analyzed.root)
  local seen={}
  local function count(node)
    if not node or seen[node] then return end
    seen[node]=true
    if nodes.number(node,'kind')==0x57 then state.word_count=state.word_count+1 end
    count(node.next); count(node.aux)
  end
  count(analyzed.root.next)
  assert(state.word_count<=512,'word-record limit exceeded')
  if grammar_entered then
    senses.numeric_pass(state,analyzed.root)
    stages.numeric=true
    constituents.pass(state,analyzed.root,analyzed.terminator,agreement.run)
    stages.constituents=state.count
    syntax.run(state,analyzed.root,analyzed.terminator)
    stages.T8=true
    generation.run(state,analyzed.root)
    stages.generation=true
  end
  local prefixed=analyzed.root.next
  while prefixed do
    if prefixed.derivation_prefix and (prefixed.text or '') ~= '' then
      local reading=prefixed
      while reading do
        if (reading.text or '')~='' then reading.text=prefixed.derivation_prefix .. reading.text end
        reading=reading.alternative
      end
    end
    prefixed=prefixed.next
  end
  local result,alternatives=output.sentence(state,analyzed.root)
  result=result:gsub('^ ','')
  local terminator=analyzed.terminator
  if terminator==0x2E or terminator==0x21 or terminator==0x3F then
    local mark=string.char(terminator)
    if result:sub(-1)~=mark then result=result..mark end
  end
  local trailing_quotes=input:match("[.!?]([\"']+)%s*$") or ''
  if trailing_quotes~='' and result:sub(-#trailing_quotes)~=trailing_quotes then result=result..trailing_quotes end
  state.text,state.output=encoding.decode(result),result
  state.dictionary,state.lexical,state.root=dict,analyzed,analyzed.root
  state.stages,state.alternatives=stages,alternatives
  if options.meanings then
    state.meanings = output.meanings(state, analyzed.root)
    state.meanings_text = encoding.decode(state.meanings)
    if state.meanings ~= '' then result = result .. '\n\n' .. state.meanings end
    state.text,state.output=encoding.decode(result),result
  end
  return result,state
end

function engine.translate(input,options)
  local cp866,state=engine.run(input,options)
  return encoding.decode(cp866),state
end
return engine
