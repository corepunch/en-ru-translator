#!/usr/bin/env lua
-- Assign each OpenRussian lexeme the inflection paradigm (openrussian/paradigms.txt)
-- that regenerates its listed forms from the headword, as LTGOLD codes every
-- .RUS record with a paradigm number instead of storing forms.
--   lua tools/fit_paradigms.lua openrussian/upstream > fit.tsv
-- Output rows: pos<TAB>lemma<TAB>aspect<TAB>id<TAB>matched<TAB>forms. A row is
-- written when at most one listed form disagrees (the native tables carry a few
-- historical misspellings such as "жите" for "жете"). Unlisted lexemes keep
-- their source forms in BASE.MORPH.
package.path='./?.lua;'..package.path
local engine=require 'core.engine'; local generation=require 'core.generation'; local enc=require 'core.encoding'
local dir=arg[1] or 'openrussian/upstream'
local state=engine.new_state('LTGOLD/BASE.RUS')   -- no BASE.MORPH beside it: tables only
state.assets=setmetatable({},{__index=state.assets})
do local f=assert(io.open('openrussian/paradigms.txt','rb')); state.assets:load_paradigms(f:read('a'),enc.encode); f:close() end
local function norm(s) return (s:gsub('ё','е'):gsub("'",''):gsub('[;,].*','')) end
local function rows(path) local f=assert(io.open(path)); local header,col; return function()
  while true do local line=f:read('l'); if not line then f:close() return nil end
    local cells={}; for c in (line..'\t'):gmatch('([^\t]*)\t') do cells[#cells+1]=c end
    if not header then header=cells; col={}; for i,h in ipairs(header) do col[h]=i end
    elseif cells[1]~='' and cells[1]:sub(1,1)~='#' then return cells,col end end end end
local function gen(f,...) local ok,r=pcall(f,state,...); return ok and r and norm(enc.decode(r)) or nil end
local sizes={}; for name,t in pairs(state.assets.paradigm_tables) do local n=0; for _ in pairs(t) do n=n+1 end; sizes[name]=n end
local stats={}
local function fit(pos,lemma,aspect,count,probes,want,n,minimum)
  if n<minimum then return end
  local cw=enc.encode(lemma); local best,bs=nil,-1
  for id=0,count-1 do
    local s,miss=0,0
    for _,p in ipairs(probes) do local w=want[p.slot]
      if w then if p.gen(id,cw)==w then s=s+1 else miss=miss+1; if miss>1 or p.slot=='imperative_pl' then s=-1; break end end end
    end
    if s>bs then best,bs=id,s; if bs==n then break end end
  end
  local st=stats[pos] or {total=0,exact=0,near=0}; stats[pos]=st; st.total=st.total+1
  if bs==n then st.exact=st.exact+1 elseif bs>=n-1 then st.near=st.near+1 else return end
  io.write(pos,'\t',lemma,'\t',aspect,'\t',best,'\t',bs,'\t',n,'\n')
end
-- verbs
local vp={}; for i,s in ipairs({'presfut_sg1','presfut_sg2','presfut_sg3','presfut_pl1','presfut_pl2','presfut_pl3'}) do
  local person,plural=(i-1)%3+1,i>3 and 1 or 0; vp[#vp+1]={slot=s,gen=function(id,w,a) return gen(generation.verb_form,id,w,a,0,person,plural,0,1) end} end
vp[#vp+1]={slot='imperative_pl',gen=function(id,w,a) return gen(generation.verb_form,id,w,a,4,0,0,0,1) end}
vp[#vp+1]={slot='past_m',gen=function(id,w,a) return gen(generation.verb_form,id,w,a,0,0,0,1,1) end}
vp[#vp+1]={slot='past_f',gen=function(id,w,a) return gen(generation.verb_form,id,w,a,0,0,0,1,2) end}
vp[#vp+1]={slot='past_pl',gen=function(id,w,a) return gen(generation.verb_form,id,w,a,0,0,1,1,1) end}
for cells,col in rows(dir..'/verbs.tsv') do
  local aspect=cells[col.aspect]=='perfective' and 1 or 0; local want,n={},0
  for _,p in ipairs(vp) do local v=norm(cells[col[p.slot]] or ''); if v~='' then want[p.slot]=v; n=n+1 end end
  local probes={}; for _,p in ipairs(vp) do probes[#probes+1]={slot=p.slot,gen=function(id,w) return p.gen(id,w,aspect) end} end
  fit('v',norm(cells[col.bare]),aspect,sizes[aspect==1 and 'verb-perfective' or 'verb-imperfective'],probes,want,n,6)
end
-- nouns
local np={}; for _,c in ipairs({{'sg_gen',0,1},{'sg_dat',0,2},{'sg_acc',0,3},{'sg_inst',0,4},{'sg_prep',0,5},{'pl_nom',1,0},{'pl_gen',1,1},{'pl_dat',1,2},{'pl_acc',1,3},{'pl_inst',1,4},{'pl_prep',1,5}}) do
  np[#np+1]={slot=c[1],plural=c[2],case=c[3]} end
for cells,col in rows(dir..'/nouns.tsv') do
  local g=({m=1,f=2,n=0})[cells[col.gender]]
  -- Pluralia/singularia tantum and nouns with a second locative (в саду) keep
  -- their source forms: the native tables have one form per slot.
  if g and cells[col.indeclinable]~='1' and cells[col.pl_only]~='1' and cells[col.sg_only]~='1' and not (cells[col.sg_prep] or ''):find(',',1,true) then
    local want,n={},0
    for _,p in ipairs(np) do local v=norm(cells[col[p.slot]] or ''); if v~='' then want[p.slot]=v; n=n+1 end end
    local probes={}; for _,p in ipairs(np) do probes[#probes+1]={slot=p.slot,gen=function(id,w) return gen(generation.noun_form,id,w,g,p.plural,p.case) end} end
    fit('n',norm(cells[col.bare]),0,sizes[g==1 and 'noun-m' or g==2 and 'noun-f' or 'noun-n'],probes,want,n,5)
  end
end
-- adjectives
local ap={}; for _,gs in ipairs({{'m',1,0},{'f',2,0},{'n',0,0},{'pl',1,1}}) do for ci,c in ipairs({'nom','gen','dat','acc','inst','prep'}) do
  local gender,plural,case=gs[2],gs[3],ci-1; ap[#ap+1]={slot='decl_'..gs[1]..'_'..c,gen=function(id,w) return gen(generation.adjective_form,id,w,gender,plural,case,false) end} end end
for cells,col in rows(dir..'/adjectives.tsv') do
  local want,n={},0
  for _,p in ipairs(ap) do local v=norm(cells[col[p.slot]] or ''); if v~='' then want[p.slot]=v; n=n+1 end end
  fit('a',norm(cells[col.bare]),0,sizes['adjective-m'],ap,want,n,12)
end
for pos,st in pairs(stats) do io.stderr:write(string.format('%s: %d lexemes, exact %d, one form off %d, unfitted %d\n',pos,st.total,st.exact,st.near,st.total-st.exact-st.near)) end
