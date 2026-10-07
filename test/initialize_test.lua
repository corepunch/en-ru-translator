local engine = require 'core.engine'
local russian = require 'core.russian'
local senses = require 'core.senses'
local generation = require 'core.generation'
local nodes = require 'core.nodes'
local encode = require('core.encoding').encode
local exe=engine.read_asset('LTGOLD/LTPRO.EXE','LTPRO.EXE')
local rus=engine.read_asset('LTGOLD/BASE.RUS','BASE.RUS')
local state=engine.new_state(exe,rus)
local line=assert(russian.lookup(state,encode('дом'),0))
assert(line:find(encode('дом')..'*N',1,true))
local node=nodes.word(state,0x4E,encode('дом'))
senses.store_code(node,0,assert(line:match('%*N(.*)')))
assert(node[0x6D]==0x80 and node[0x6E]==0x81 and node[0x6F]==0x80)
assert(node[0x85]==0)
assert(generation.noun_form(state,node[0x85],node.text,node[0x77],node[0x72] or 0,1)==encode('дома'))
local from_paths=engine.new_state('LTGOLD/LTPRO.EXE','LTGOLD/BASE.RUS')
assert(russian.lookup(from_paths,encode('дом'),0)==line)
assert(not pcall(engine.new_state,'missing-LTPRO.EXE',rus))
assert(not pcall(engine.new_state,exe,rus:sub(1,-2)))
-- Later dictionary queries and independent states cannot overwrite a saved line.
russian.lookup(state,encode('идти'),0)
assert(russian.lookup(from_paths,encode('дом'),0)==line)
assert(state.elements~=from_paths.elements and state.tags~=from_paths.tags)
print('initialize_test: passed')
