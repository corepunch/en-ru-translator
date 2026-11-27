#!/usr/bin/env lua
local script=arg[0] or ""
local home=script:match("^(.*[/\\])tools[/\\][^/\\]+$") or "./"
package.path=home.."?.lua;"..package.path
local lex=require("en_ru.lexicon")
local fmt=require("en_ru.data_format")

local usage=[[
Edit the offline translator's English dictionary and Russian paradigms.
Usage: lua tools/dictionary.lua [--data DIR] [--json] COMMAND ...

  dict select EN [--prefix] [--pos noun|verb|adjective|adverb] [--limit N]
  dict insert EN --pos POS --target RU [--frame FRAME] [--modifier TEXT]
  dict update EN --pos POS --target RU [--to RU] [--frame FRAME] [--modifier TEXT]
  dict delete EN --pos POS --target RU
  dict reset  EN --pos POS --target RU

  rus select RU [--prefix] [--pos POS] [--limit N]
  rus insert RU --pos POS [--gender GENDER] [--animacy ANIMACY]
       [--aspect ASPECT] [--transitivity TRANSITIVITY] [--form NAME=WORD]...
  rus update RU --pos POS [same options] [--drop-form NAME]...
  rus delete RU --pos POS
  rus reset  RU --pos POS

  schema [--pos POS]
  validate

Writes affect only the editor overlay. 'delete' hides a sense/paradigm;
'reset' removes the edit and reveals the original. Use schema for form names.
--json works for all commands. Exact queries return empty arrays on no match.
]]

local pos_codes={}
for code,name in pairs(fmt.pos) do pos_codes[code]=code; pos_codes[name]=code end
local arity={data=true,pos=true,target=true,to=true,frame=true,modifier=true,limit=true,
    gender=true,animacy=true,aspect=true,transitivity=true,form=true,["drop-form"]=true}
local flags={json=true,prefix=true,help=true}
local repeatable={form=true,["drop-form"]=true}
local common={data=true,json=true}
local allowed={
    select={pos=true,prefix=true,limit=true},
    ["dict insert"]={pos=true,target=true,frame=true,modifier=true},
    ["dict update"]={pos=true,target=true,to=true,frame=true,modifier=true},
    ["dict delete"]={pos=true,target=true}, ["dict reset"]={pos=true,target=true},
    ["rus insert"]={pos=true,gender=true,animacy=true,aspect=true,transitivity=true,form=true},
    ["rus update"]={pos=true,gender=true,animacy=true,aspect=true,transitivity=true,form=true,["drop-form"]=true},
    ["rus delete"]={pos=true}, ["rus reset"]={pos=true},
    schema={pos=true},validate={},
}
local function args()
    local o,p={},{}
    local i=1
    while i<=#arg do
        local value=arg[i]
        if value=="-h" then o.help=true
        elseif value:sub(1,2)=="--" then
            local key,inline=value:match("^%-%-([^=]+)=(.*)$")
            key=key or value:sub(3)
            if flags[key] then
                assert(not inline and not o[key],"invalid or duplicate "..value)
                o[key]=true
            else
                assert(arity[key],"unknown option: "..value)
                if inline==nil then
                    i=i+1
                    inline=arg[i]
                    assert(inline and inline:sub(1,2)~="--","missing value: "..value)
                end
                if repeatable[key] then
                    o[key]=o[key] or {}; o[key][#o[key]+1]=inline
                else assert(o[key]==nil,"duplicate "..value); o[key]=inline end
            end
        else p[#p+1]=value end
        i=i+1
    end
    if o.help or #p==0 then return o,p end
    local command=p[1]
    local config=command=="dict" or command=="rus"
    local permitted=config and (p[2]=="select" and allowed.select or allowed[command.." "..(p[2] or "")]) or allowed[command]
    assert(permitted and #p==(config and 3 or 1),"invalid command or argument count; use --help")
    for key in pairs(o) do assert(common[key] or permitted[key],"option --"..key.." is not valid here") end
    if o.pos then o.pos=assert(pos_codes[o.pos],"unknown part of speech: "..o.pos) end
    if p[2]=="update" then
        local changed=config and command=="dict" and (o.to~=nil or o.frame~=nil or o.modifier~=nil)
            or command=="rus" and (o.form or o["drop-form"] or o.gender or o.animacy or o.aspect or o.transitivity)
        assert(changed,"update needs at least one changed field or form")
    end
    return o,p
end

local ARRAY={}
local function list(t) return setmetatable(t or {},ARRAY) end
local function quote(s)
    return '"'..s:gsub('[%z\1-\31\\"]',function(c)
        if c=='"' or c=="\\" then return "\\"..c end
        return ("\\u%04x"):format(c:byte())
    end)..'"'
end
local function json(x)
    local k=type(x)
    if k=="string" then return quote(x) end
    if k=="number" or k=="boolean" then return tostring(x) end
    local out={}
    if getmetatable(x)==ARRAY then
        for _,item in ipairs(x) do out[#out+1]=json(item) end
        return "["..table.concat(out,",").."]"
    end
    for _,key in ipairs(fmt.keys(x)) do out[#out+1]=quote(key)..":"..json(x[key]) end
    return "{"..table.concat(out,",").."}"
end

local function english(s)
    s=s:lower()
    assert(s:match("^[a-z][a-z' %-]*[a-z]$") or s:match("^[a-z]$"),"invalid English headword")
    assert(not s:find("  ",1,true) and select(2,s:gsub(" ",""))<=2,"expected one to three lexical words")
    return s
end
local function russian(s)
    assert(type(s)=="string" and #s>0 and utf8.len(s),"expected a Russian lemma or form")
    local result={}
    for _,cp in utf8.codes(s) do
        if cp>=0x410 and cp<=0x42f then cp=cp+32
        elseif cp==0x401 then cp=0x451 end
        assert(cp>=0x430 and cp<=0x44f or cp==0x451 or cp==45,
            "expected Cyrillic and optional internal hyphens: "..s)
        result[#result+1]=utf8.char(cp)
    end
    assert(s:sub(1,1)~="-" and s:sub(-1)~="-" and not s:find("--",1,true),"invalid hyphen in "..s)
    return table.concat(result)
end
local function frame(s)
    local head,object=s:match("^([^%.]+)%.(.+)$")
    assert(fmt.frames[head or s],"unknown lexical frame: "..s)
    if object then return head.."."..english(object) end
    return s
end
local function modifier(s)
    assert(utf8.len(s) and not s:find("[%c]"),"invalid modifier")
    local words={}
    for word in s:gmatch("[^ ]+") do words[#words+1]=russian(word) end
    assert(#words<=4 and not s:find("  ",1,true),"expected a short lexical modifier")
    return table.concat(words," ")
end
local function inverse(map,value,what)
    for code,label in pairs(map) do if value==label then return code end end
    error("unknown "..what..": "..value,0)
end
local function output(opts, result, lines)
    if opts.json then print(json(result))
    else for _,line in ipairs(lines) do print(line) end end
end

local kinds={dict="editor-words.tsv",rus="editor-forms.tsv"}
local function key_of(row,n)
    return table.concat(row,"\t",2,n)
end
local function overlay(path,kind)
    local body=assert(lex.disk(path))
    local rows,seen={},{}
    local n=kind=="dict" and 4 or 3
    for line in body:gmatch("[^\r\n]+") do
        if line:sub(1,1)~="#" then
            local row=fmt.fields(line)
            assert(#row>=n and (row[1]=="set" or row[1]=="delete"),path..": invalid row")
            local key=key_of(row,n)
            assert(not seen[key],path..": duplicate edit "..key)
            seen[key]=true
            if kind=="dict" then
                assert(english(row[2])==row[2] and fmt.pos[row[3]],"invalid word record")
                assert(russian(row[4])==row[4],"noncanonical Russian translation")
                assert(row[1]=="set" and #row<=6 or row[1]=="delete" and #row==4,"invalid word record fields")
                assert(frame(row[5] or "")== (row[5] or "") and modifier(row[6] or "")==(row[6] or ""),
                    "noncanonical lexical frame or modifier")
            else
                assert(russian(row[2])==row[2],"noncanonical Russian lemma")
                assert(row[3]=="n" or row[3]=="v" or row[3]=="a","invalid morphology part of speech")
                if row[1]=="set" then
                    assert(#row>=4 and #row<=5,"invalid paradigm record fields")
                    fmt.flags(row[3],row[4]); fmt.decode(row[2],row[5] or "",row[3])
                else assert(#row==3,"invalid paradigm tombstone") end
            end
            rows[#rows+1]=row
        end
    end
    return rows,body,n
end

local function shell_quote(value)
    return "'"..value:gsub("'","'\\''").."'"
end
local function write_edit(path,kind,modify)
    -- Serialize CLI writers. The replacement lives on the same filesystem.
    local lock=path..".lock"
    local acquired=os.execute("mkdir -- "..shell_quote(lock).." 2>/dev/null")
    assert(acquired==true or acquired==0,"cannot acquire editor lock: "..lock)
    local tmp=lock.."/new"
    local ok,report=pcall(function()
        local rows,old,n=overlay(path,kind)
        local function remove(key)
            for i=#rows,1,-1 do if key_of(rows[i],n)==key then table.remove(rows,i); return true end end
        end
        local result=modify(rows,remove)
        local lines={kind=="dict" and "# action\tenglish\tpos\trussian\tframe\tmodifier"
            or "# action\trussian\tpos\tflags\tvariants"}
        for _,row in ipairs(rows) do lines[#lines+1]=fmt.row(row) end
        local b=assert(io.open(tmp,"wb"))
        local wrote,err=b:write(table.concat(lines,"\n"),"\n")
        local closed,close_err=b:close()
        assert(wrote,err); assert(closed,close_err)
        assert(lex.disk(path)==old,"dictionary changed during editing")
        assert(os.rename(tmp,path))
        return result
    end)
    os.remove(tmp)
    os.execute("rmdir -- "..shell_quote(lock))
    if not ok then error(report,0) end
    return report
end

local function query(data,kind,term,opts)
    local source=kind=="dict" and data.words or data.forms
    local result,lines=list(),{}
    local limit=opts.limit and tonumber(opts.limit) or 100
    assert(limit and limit>=1 and limit%1==0,"--limit must be a positive integer")
    local names=opts.prefix and fmt.keys(source) or {term}
    for _,word in ipairs(names) do
        if word:sub(1,#term)==term and source[word] then
            for _,pos in ipairs(fmt.keys(source[word])) do
                if (not opts.pos or opts.pos==pos) and #result<limit then
                    local item=source[word][pos]
                    if kind=="dict" then
                        local senses,seen=list(),{}
                        for rank,s in ipairs(item) do
                            local key=s.word.."\t"..s.frame.."\t"..(s.modifier or "")
                            if not seen[key] then
                                seen[key]=true
                                local name=s.frame:match("^[^%.]*")
                                local info={target=s.word,rank=rank,source=s.source,frame=s.frame,
                                    rule=fmt.frames[name] or name}
                                if s.modifier and s.modifier~="" then info.modifier=s.modifier end
                                senses[#senses+1]=info
                                lines[#lines+1]=("%s [%s] → %s  %s  (%s)"):format(word,fmt.pos[pos],s.word,info.rule,s.source)
                            end
                        end
                        if #senses>0 then
                            result[#result+1]={lemma=word,pos=fmt.pos[pos],senses=senses}
                        end
                    else
                        local forms=list()
                        local variants=fmt.decode(word,item.variants,pos)
                        local grammar=fmt.flags(pos,item.flags)
                        local traits={}
                        for _,k in ipairs(fmt.keys(grammar)) do traits[#traits+1]=k.."="..grammar[k] end
                        lines[#lines+1]=("%s [%s] %s (%s)"):format(word,fmt.pos[pos],table.concat(traits,", "),item.source)
                        for _,key in ipairs(fmt.keys(variants)) do
                            local name=fmt.form_name(pos,key)
                            forms[#forms+1]={name=name,code=key,text=variants[key]}
                            lines[#lines+1]="  "..name.." = "..variants[key]
                        end
                        result[#result+1]={lemma=word,pos=fmt.pos[pos],features=grammar,
                            flags=item.flags,source=item.source,forms=forms}
                    end
                end
            end
        end
        if #result>=limit then break end
    end
    if #lines==0 then lines[1]="No matches." end
    output(opts,result,lines)
end

local function edit(root,kind,action,term,opts)
    local pos=assert(opts.pos,"--pos is required when editing")
    if kind=="rus" then assert(pos~="r","adverbs do not have a paradigm") end
    local path=root.."/"..kinds[kind]
    local message=write_edit(path,kind,function(rows,remove)
        local data=lex.load(root,lex.disk)
        if kind=="dict" then
            local target=russian(opts.target)
            local key=table.concat({term,pos,target},"\t")
            if action=="reset" then assert(remove(key),"no edit to reset"); return end
            local function single(ru)
                local found,matched
                for _,s in ipairs(data.words[term] and data.words[term][pos] or {}) do
                    if s.word==ru then
                        if found and (s.frame~=found.frame or (s.modifier or "")~=(found.modifier or "")) then matched=true end
                        found=found or s
                    end
                end
                return found,matched
            end
            local current,multiple=single(target)
            if action=="insert" then assert(not current,"translation already exists; use update")
            else assert(current,"translation not found") end
            local to=opts.to and russian(opts.to) or target
            if to~=target then assert(not single(to),"replacement translation already exists") end
            if action=="update" and multiple then
                assert(opts.frame~=nil and opts.modifier~=nil,"ambiguous senses: supply --frame and --modifier")
            end
            remove(key)
            if action=="delete" or to~=target then rows[#rows+1]={"delete",term,pos,target} end
            if action~="delete" then
                remove(table.concat({term,pos,to},"\t"))
                rows[#rows+1]={"set",term,pos,to,frame(opts.frame or current and current.frame or ""),
                    modifier(opts.modifier or current and current.modifier or "")}
                if pos~="r" and not lex.paradigm(data,to,pos) then
                    return "No Russian paradigm for "..to.."; add one with rus insert if needed."
                end
            end
        else
            local key=term.."\t"..pos
            if action=="reset" then assert(remove(key),"no edit to reset"); return end
            local p=lex.paradigm(data,term,pos)
            if action=="insert" then
                assert(not p,"paradigm already exists; use update")
                assert(pos~="n" or opts.gender,"noun insertion requires --gender")
                assert(pos~="v" or opts.aspect,"verb insertion requires --aspect")
            else assert(p,"paradigm not found") end
            remove(key)
            if action=="delete" then rows[#rows+1]={"delete",term,pos}; return end
            local values=p and fmt.decode(term,p.variants,pos) or {}
            local codes=p and {p.flags:sub(1,1),p.flags:sub(2,2),p.flags:sub(3,3),p.flags:sub(4,4)}
                or {"m","-","-","-"}
            assert(not (opts.gender or opts.animacy) or pos=="n","gender and animacy apply to nouns")
            assert(not (opts.aspect or opts.transitivity) or pos=="v","aspect and transitivity apply to verbs")
            if opts.gender then codes[1]=inverse(fmt.gender,opts.gender,"gender") end
            if opts.animacy then codes[2]=inverse(fmt.animacy,opts.animacy,"animacy") end
            if opts.transitivity then
                codes[3]=opts.transitivity=="unspecified" and "-" or inverse(fmt.transitivity,opts.transitivity,"transitivity")
            end
            if opts.aspect then codes[4]=inverse(fmt.aspect,opts.aspect,"aspect") end
            local touched={}
            for _,name in ipairs(opts["drop-form"] or {}) do
                local code=assert(fmt.form_code(pos,name),"unknown form: "..name)
                assert(values[code] and not touched[code],"form not found or repeated: "..name)
                touched[code]=true; values[code]=nil
            end
            for _,entry in ipairs(opts.form or {}) do
                local name,word=entry:match("^([^=]+)=(.+)$")
                assert(name,"--form expects NAME=WORD")
                local code=assert(fmt.form_code(pos,name),"unknown form: "..name)
                assert(not touched[code],"repeated form: "..name)
                touched[code]=true; values[code]=russian(word)
            end
            rows[#rows+1]={"set",term,pos,table.concat(codes),fmt.encode(term,values)}
        end
    end)
    local result={action=action,dictionary=kind,lemma=term,pos=fmt.pos[pos]}
    local lines={action.." "..term.." ["..fmt.pos[pos].."]"}
    if message then result.warning=message; lines[#lines+1]=message end
    output(opts,result,lines)
end

local function main()
    local o,p=args()
    if o.help or #p==0 then io.write(usage); return end
    local root=o.data or home.."dictionary"
    if p[1]=="schema" then
        local schema,lines={},{}
        for _,pos in ipairs({"n","a","v","r"}) do
            if not o.pos or o.pos==pos then
                local forms=list()
                for _,name in ipairs(fmt.keys(fmt.forms(pos))) do
                    forms[#forms+1]={name=name,code=fmt.form_code(pos,name)}
                end
                schema[fmt.pos[pos]]=forms
                lines[#lines+1]=fmt.pos[pos]
                for _,item in ipairs(forms) do lines[#lines+1]="  "..item.name.." ("..item.code..")" end
            end
        end
        schema.frames=fmt.frames
        lines[#lines+1]="Frames:"
        for _,name in ipairs(fmt.keys(fmt.frames)) do
            lines[#lines+1]="  "..(name=="" and "(empty)" or name)..": "..fmt.frames[name]
        end
        output(o,schema,lines)
    elseif p[1]=="validate" then
        local words=overlay(root.."/"..kinds.dict,"dict")
        local forms=overlay(root.."/"..kinds.rus,"rus")
        local data=lex.load(root,lex.disk)
        local count=0
        for lemma,tags in pairs(data.forms) do
            for pos,par in pairs(tags) do
                fmt.flags(pos,par.flags)
                fmt.decode(lemma,par.variants,pos)
                count=count+1
            end
        end
        output(o,{valid=true,paradigms=count,word_edits=#words,form_edits=#forms},
            {("Valid: %d paradigms, %d word edits, %d form edits."):format(count,#words,#forms)})
    else
        local kind,action,term=table.unpack(p)
        term=kind=="dict" and english(term) or russian(term)
        if action=="select" then query(lex.load(root,lex.disk),kind,term,o)
        else edit(root,kind,action,term,o) end
    end
end
local ok,err=pcall(main)
if not ok then io.stderr:write("dictionary: ",tostring(err):gsub("^.-:%d+: ",""),"\n"); os.exit(2) end
