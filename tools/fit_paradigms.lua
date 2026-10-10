#!/usr/bin/env lua
-- Assign each OpenRussian lexeme the inflection paradigm (openrussian/paradigms.txt)
-- that regenerates its listed forms from the headword, as LTGOLD codes every
-- .RUS record with a paradigm number instead of storing forms.
--   lua tools/fit_paradigms.lua openrussian/upstream > fit.tsv
-- Output rows: pos<TAB>lemma<TAB>aspect<TAB>id<TAB>matched<TAB>forms. Every
-- lexeme gets the row that regenerates most of its listed forms, as LTGOLD's
-- own records use only LTPRO's tables: a lexeme no row fits exactly keeps the
-- nearest row's forms. The tables are not extended.
package.path='./?.lua;'..package.path
local engine=require 'core.engine'; local generation=require 'core.generation'; local enc=require 'core.encoding'
local russian=require 'core.russian'
local dir=arg[1] or 'openrussian/upstream'
local state=engine.new_state('LTGOLD/BASE.RUS')
state.assets=setmetatable({},{__index=state.assets})
do local f=assert(io.open('openrussian/paradigms.txt','rb')); state.assets:load_paradigms(f:read('a'),enc.encode); f:close() end
-- First variant only: OpenRussian separates them with , ; and // (зали'л//за'лил).
local function norm(s) return (s:gsub('ё','е'):gsub("'",''):gsub('//.*',''):gsub('[;,].*','')) end
local function rows(path) local f=assert(io.open(path)); local header,col; return function()
  while true do local line=f:read('l'); if not line then f:close() return nil end
    local cells={}; for c in (line..'\t'):gmatch('([^\t]*)\t') do cells[#cells+1]=c end
    if not header then header=cells; col={}; for i,h in ipairs(header) do col[h]=i end
    elseif cells[1]~='' and cells[1]:sub(1,1)~='#' then return cells,col end end end end
local function gen(f,...) local ok,r=pcall(f,state,...); return ok and r and norm(enc.decode(r)) or nil end
local sizes={}; for name,t in pairs(state.assets.paradigm_tables) do local n=0; for _ in pairs(t) do n=n+1 end; sizes[name]=n end
local stats={}
-- A wanted form is a string, or the listed variants of an accusative.
local function matches(form,w)
  if type(w)~='table' then return form==w end
  for _,v in ipairs(w) do if form==v then return true end end
  return false
end
local function variants(s)
  local list={}
  for v in (s:gsub("'",''):gsub('ё','е')..','):gmatch('([^,;]*)[,;]') do
    v=v:gsub('//.*',''):gsub('^%s+',''):gsub('%s+$','')
    if v~='' then list[#list+1]=v end
  end
  return #list>0 and list or nil
end
local seen={}
-- LTPRO chooses a paradigm by the lemma's ending: each table row has a list
-- of the endings it serves (core/rules.lua lists), longest match first. The
-- source forms only decide among rows: the row regenerating most of them,
-- the earliest ending candidate on a tie. Without forms the ending decides.
local function fit(pos,lemma,aspect,count,probes,want,n,class,variant)
  -- The builder keeps the first source row per (class, lemma, aspect).
  local key=pos..lemma..'/'..aspect
  if lemma=='' or seen[key] then return end
  seen[key]=true
  local cw=enc.encode(lemma)
  local candidates=russian.paradigm_candidates(state,cw,class,variant)
  local rank={}; for i,id in ipairs(candidates) do if not rank[id] then rank[id]=i end end
  local best,bs=candidates[1],-1
  if n==0 then
    local st=stats[pos] or {total=0,exact=0,near=0}; stats[pos]=st
    st.by_ending=(st.by_ending or 0)+(best and 1 or 0); st.none=(st.none or 0)+(best and 0 or 1)
    if best then io.write(pos,'\t',lemma,'\t',aspect,'\t',best,'\t0\t0\n') end
    return
  end
  for id=0,count-1 do
    local s=0
    for _,p in ipairs(probes) do local w=want[p.slot]
      if w and matches(p.gen(id,cw),w) then s=s+1 end
    end
    if s>bs or (s==bs and (rank[id] or math.huge)<(rank[best] or math.huge)) then best,bs=id,s end
  end
  local st=stats[pos] or {total=0,exact=0,near=0}; stats[pos]=st; st.total=st.total+1
  if bs==n then st.exact=st.exact+1 elseif bs>=n-1 then st.near=st.near+1 end
  if os.getenv('DEBUG_FIT') and bs<n then
    local miss={}
    for _,p in ipairs(probes) do local w=want[p.slot]
      if w and not matches(p.gen(best,cw),w) then miss[#miss+1]=p.slot..'='..tostring(type(w)=='table' and w[1] or w)..'/'..tostring(p.gen(best,cw)) end end
    io.stderr:write('MISS\t',pos,'\t',lemma,'\t',best,'\t',table.concat(miss,' '),'\n')
  end
  io.write(pos,'\t',lemma,'\t',aspect,'\t',best,'\t',bs,'\t',n,'\n')
end
-- verbs
local vp={}; for i,s in ipairs({'presfut_sg1','presfut_sg2','presfut_sg3','presfut_pl1','presfut_pl2','presfut_pl3'}) do
  local person,plural=(i-1)%3+1,i>3 and 1 or 0; vp[#vp+1]={slot=s,gen=function(id,w,a) return gen(generation.verb_form,id,w,a,0,person,plural,0,1) end} end
vp[#vp+1]={slot='imperative_pl',gen=function(id,w,a) return gen(generation.verb_form,id,w,a,4,0,0,0,1) end}
vp[#vp+1]={slot='past_m',gen=function(id,w,a) return gen(generation.verb_form,id,w,a,0,0,0,1,1) end}
vp[#vp+1]={slot='past_f',gen=function(id,w,a) return gen(generation.verb_form,id,w,a,0,0,0,1,2) end}
vp[#vp+1]={slot='past_n',gen=function(id,w,a) return gen(generation.verb_form,id,w,a,0,0,0,1,0) end}
vp[#vp+1]={slot='past_pl',gen=function(id,w,a) return gen(generation.verb_form,id,w,a,0,0,1,1,1) end}
for cells,col in rows(dir..'/verbs.tsv') do
  local aspect=cells[col.aspect]=='perfective' and 1 or 0; local want,n={},0
  for _,p in ipairs(vp) do local v=norm(cells[col[p.slot]] or ''); if v~='' then want[p.slot]=v; n=n+1 end end
  local probes={}; for _,p in ipairs(vp) do probes[#probes+1]={slot=p.slot,gen=function(id,w) return p.gen(id,w,aspect) end} end
  fit('v',norm(cells[col.bare]),aspect,sizes[aspect==1 and 'verb-perfective' or 'verb-imperfective'],probes,want,n,0x56,aspect)
end
-- nouns
local function ends(s,tail) return s:sub(-#tail)==tail end
local function inferred_gender(lemma)
  for _,t in ipairs({'о','е','ё','мя'}) do if ends(lemma,t) then return 0 end end
  for _,t in ipairs({'а','я','сть','знь','вь','бь','пь','мь','чь'}) do if ends(lemma,t) then return 2 end end
  return 1
end
local np={}; for _,c in ipairs({{'sg_gen',0,1},{'sg_dat',0,2},{'sg_acc',0,3},{'sg_inst',0,4},{'sg_prep',0,5},{'pl_nom',1,0},{'pl_gen',1,1},{'pl_dat',1,2},{'pl_acc',1,3},{'pl_inst',1,4},{'pl_prep',1,5}}) do
  np[#np+1]={slot=c[1],plural=c[2],case=c[3]} end
for cells,col in rows(dir..'/nouns.tsv') do
  local lemma=norm(cells[col.bare])
  -- The builder's gender: the source column, else read off the lemma ending.
  local g=({m=1,f=2,n=0})[cells[col.gender]] or inferred_gender(lemma)
  do
    local want,n={},0
    -- The tables hold the inanimate accusative; for an animate noun (.RUS
    -- flag 0x02) LTPRO uses the genitive instead (вижу брата, новых друзей).
    local animate=cells[col.animate]=='1'
    for _,p in ipairs(np) do
      local v=cells[col.indeclinable]=='1' and lemma or norm(cells[col[p.slot]] or '')
      if animate and (p.slot=='pl_acc' or (p.slot=='sg_acc' and g==1)) then v='' end
      if v~='' then want[p.slot]=v; n=n+1 end
    end
    local probes={}; for _,p in ipairs(np) do probes[#probes+1]={slot=p.slot,gen=function(id,w) return gen(generation.noun_form,id,w,g,p.plural,p.case) end} end
    fit('n',lemma,0,sizes[g==1 and 'noun-m' or g==2 and 'noun-f' or 'noun-n'],probes,want,n,0x4E,g)
  end
end
-- adjectives
local ap={}; for _,gs in ipairs({{'m',1,0},{'f',2,0},{'n',0,0},{'pl',1,1}}) do for ci,c in ipairs({'nom','gen','dat','acc','inst','prep'}) do
  local gender,plural,case=gs[2],gs[3],ci-1; ap[#ap+1]={slot='decl_'..gs[1]..'_'..c,gen=function(id,w) return gen(generation.adjective_form,id,w,gender,plural,case,false) end} end end
for cells,col in rows(dir..'/adjectives.tsv') do
  local want,n={},0
  for _,p in ipairs(ap) do
    -- An accusative lists the inanimate and animate forms (новый, нового).
    local v=p.slot:match('_acc$') and variants(cells[col[p.slot]] or '') or norm(cells[col[p.slot]] or '')
    if v and v~='' then want[p.slot]=v; n=n+1 end
  end
  fit('a',norm(cells[col.bare]),0,26,ap,want,n,0x41,0)
end
for pos,st in pairs(stats) do io.stderr:write(string.format('%s: %d lexemes with forms: exact %d, one form off %d, more %d; without forms: by ending %d, no ending match %d\n',
  pos,st.total,st.exact,st.near,st.total-st.exact-st.near,st.by_ending or 0,st.none or 0)) end
