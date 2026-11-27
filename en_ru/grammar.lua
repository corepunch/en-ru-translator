-- Small, inspectable English clause analysis and Russian transfer.
local lex = require "en_ru.lexicon"
local M = {}

local articles = {a=true, an=true, the=true, some=true, no=true}
local lex_pos = {"n", "v", "a", "r"}
local pronouns = {
    i={"я","s","1","m"}, me={"я","s","1","m"},
    you={"ты","s","2","m"}, he={"он","s","3","m"}, him={"он","s","3","m"},
    she={"она","s","3","f"}, her={"она","s","3","f"}, it={"оно","s","3","n"},
    we={"мы","p","1","m"}, us={"мы","p","1","m"},
    they={"они","p","3","m"}, them={"они","p","3","m"},
}
local possessives = {my="мой", your="твой", his="его", her="её", its="его",
    our="наш", their="их", whose="чей"}
local preps = {
    ["in"]={"в","l","a"}, into={"в","a"}, at={"в","l"}, ["on"]={"на","l","a"},
    from={"из","g"}, to={"к","d"}, ["for"]={"для","g"}, ["with"]={"с","i"},
    without={"без","g"}, of={"","g"}, before={"перед","i"}, after={"после","g"},
    about={"о","l"}, near={"около","g"}, under={"под","i","a"}, between={"между","i"},
}
local joins = {["and"]="и", ["or"]="или", but="но", although="хотя", because="потому что",
    when="когда", ["while"]="пока", before="прежде чем", after="после того как", ["if"]="если"}
local clause_markers = {that=true, which=true, who=true, whom=true}
local auxiliaries = {
    am={"be","present"}, is={"be","present"}, are={"be","present"},
    was={"be","past"}, were={"be","past"}, been={"be","past"}, being={"be","ing"},
    do_={"do","present"}, does={"do","present"}, did={"do","past"},
    has={"have","present"}, had={"have","past"},
    will={"will","future"}, shall={"will","future"},
    can={"can","present"}, could={"can","past"}, must={"must","present"},
    should={"should","present"}, may={"may","present"},
}
local modals = {can="мочь", must="должен", should="следует", may="возможно"}
local contractions = {["i'm"]={"i","am"}, ["you're"]={"you","are"}, ["he's"]={"he","is"},
    ["she's"]={"she","is"}, ["it's"]={"it","is"}, ["there's"]={"there","is"}, ["we're"]={"we","are"}, ["they're"]={"they","are"},
    ["won't"]={"will","not"}, ["can't"]={"can","not"}, ["shan't"]={"shall","not"}}
local bare_place = {
    home={static="дома", toward="домой"}, here={static="здесь", toward="сюда"},
    there={static="там", toward="туда"}, inside={static="внутри", toward="внутрь"},
    outside={static="снаружи", toward="наружу"},
}
local numerals = {one=1,two=2,three=3,four=4,five=5,six=6,seven=7,eight=8,nine=9,ten=10}
local number_text = {"один","два","три","четыре","пять","шесть","семь","восемь","девять","десять"}
local fixed_pronouns = {["его"]=true,["её"]=true,["их"]=true}
local default_subject = {num="s", gender="m", person="3"}

local function analyse_words(data, words)
    local out = {}
    for _, t in ipairs(words) do
        local expansion = contractions[t.word]
        if not expansion then
            local base = t.word:match("^(.+)n't$")
            if base then expansion = {base,"not"} end
        end
        if not expansion then
            local base = t.word:match("^(.+)'ll$")
            if base then expansion = {base,"will"} end
        end
        if not expansion then
            local base = t.word:match("^(.+)'ve$")
            if base then expansion = {base,"have"} end
        end
        for _, value in ipairs(expansion or {t.word}) do
            local w = {word=value, raw=expansion and value or t.raw, pos={}}
            if value:match("^%a") then
                for _, pos in ipairs(lex_pos) do
                    local root, feature = lex.english(data, value, pos)
                    if root then w.pos[pos] = {root=root, feature=feature} end
                end
                local aux = auxiliaries[value == "do" and "do_" or value]
                if aux then
                    w.aux = aux[1]
                    w.pos.v = {root=aux[1], feature=aux[2]}
                elseif value == "be" or value == "have" then w.aux = value end
            end
            out[#out + 1] = w
        end
    end
    return out
end

local function vtoken(t) return t and t.pos.v end
local function lexical(data, t, pos)
    local id = t and t.pos[pos]
    return id and data.words[id.root] and data.words[id.root][pos] or {}
end
local function candidate(data,t,pos)
    return lexical(data,t,pos)[1]
end
local function lexical_head(t)
    return t and (pronouns[t.word] or t.pos.n or t.raw:match("^%d") or t.raw:match("^%u"))
end

-- Recognize an NP by its grammatical shape, not by matching a translated phrase.
local function np(ctx, i, last)
    local t, data = ctx.t, ctx.data
    local start, mods = i, {}
    local number, possessive, neg, count, quantity
    if i > last then return nil, i end
    if articles[t[i].word] then neg = t[i].word == "no"; i = i + 1 end
    if i <= last and possessives[t[i].word] and i < last and
            (not pronouns[t[i].word] or lexical_head(t[i+1]) or t[i+1].pos.a) then
        possessive = possessives[t[i].word]
        if t[i].word == "your" and ctx.formal then possessive = "ваш" end
        i = i + 1
    end
    if i < last and (numerals[t[i].word] or t[i].word:match("^%d+$")) and
        (lexical_head(t[i+1]) or t[i+1].pos.a) then
        count = t[i].word
        quantity = numerals[count] or tonumber(count)
        i = i + 1
    end
    while i < last and t[i].pos.a and not preps[t[i].word] and not joins[t[i].word] and
            (lexical_head(t[i+1]) or t[i+1].pos.a) and not (t[i].pos.v and t[i].pos.v.feature == "past"
            and t[i].pos.n) do
        mods[#mods + 1] = candidate(data,t[i],"a").word
        i = i + 1
    end
    local head = t[i]
    if i > last or not head or joins[head.word] or preps[head.word] or (head.aux and not head.pos.n) then
        return nil, start
    end
    local p = pronouns[head.word]
    local sense = candidate(data,head,"n")
    if not p and not sense and not lexical_head(head) and (i == start or head.pos.v or head.pos.r) then
        return nil, start
    end
    if not p and not sense and (head.raw == "" or not head.raw:match("^[%a%d]")) then return nil,start end
    local lemma = p and p[1] or sense and sense.word or head.raw
    local par = lex.paradigm(data, lemma,"n")
    local english_lemma = head.pos.n and head.pos.n.root or head.word
    number = p and p[2] or head.pos.n and head.pos.n.feature or "s"
    if head.word == "you" and ctx.formal then lemma, number = "вы", "p" end
    if english_lemma == "news" then number = "s" end
    if quantity then number = quantity == 1 and "s" or "p" end
    if (head.word=="nothing" or head.word=="something" or head.word=="nobody") and
        i<last and t[i+1].pos.a and not vtoken(t[i+1]) then
        local a = candidate(data,t[i+1],"a")
        if a then mods.post = a.word; i = i + 1 end
    elseif (head.word=="nothing" or head.word=="something") and i<last and t[i+1].pos.a and
        (i+1==last or not lexical_head(t[i+2])) then
        mods.post=candidate(data,t[i+1],"a").word; i=i+1
    end
    return {lemma=lemma, num=number, person=p and p[3] or "3", gender=p and p[4] or
        par and par.flags:sub(1,1) or "m", animate=par and par.flags:sub(2,2) or p and "+" or "-",
        neg=neg, mods=mods, possessive=possessive, count=count, quantity=quantity, word=english_lemma,
        content=sense and sense.frame == "content", token=head}, i + 1
end

local function noun(ctx, group, case, pp)
    local forms, num = {}, group.num
    local nouncase, nounnum = case,num
    if group.quantity then
        local value = group.quantity
        local last, tens = value % 10, value % 100
        if (case == "n" or case == "a") and not (case == "a" and group.animate == "+") then
            if last == 1 and tens ~= 11 then num,nounnum = "s","s"
            elseif last >= 2 and last <= 4 and (tens < 12 or tens > 14) then nouncase,nounnum = "g","s"
            else nouncase,nounnum = "g","p" end
        end
        local literal = numerals[group.count] and number_text[value] or group.count
        if numerals[group.count] then
            if value == 1 then literal = lex.adjective(ctx.data,literal,"s",group.gender,case,group.animate)
            elseif value == 2 and group.gender == "f" and (case == "n" or case == "a") then literal = "две" end
        end
        forms[#forms + 1] = literal
    end
    local function add_adj(value)
        forms[#forms + 1] = lex.adjective(ctx.data, value, num, group.gender, case, group.animate)
    end
    if group.possessive then
        if fixed_pronouns[group.possessive] then forms[#forms+1]=group.possessive else add_adj(group.possessive) end
    end
    for _, mod in ipairs(group.mods) do add_adj(mod) end
    forms[#forms + 1] = lex.noun(ctx.data, group.lemma, nounnum, nouncase, pp)
    if group.mods.post then
        forms[#forms+1]=lex.adjective(ctx.data,group.mods.post,"s","n","g","-")
    end
    return table.concat(forms," ")
end

local function verb(ctx,i,last)
    local t=ctx.t
    if i > last or not vtoken(t[i]) then return end
    local root, tense, aux = t[i].pos.v.root, t[i].pos.v.feature, t[i].aux
    local base = i
    local neg, modal, passive
    i = i + 1
    if i <= last and t[i].word == "not" then neg=true; i=i+1 end
    if i <= last and vtoken(t[i]) then
        local nextv=t[i].pos.v
        if aux == "will" or aux == "do" or modals[aux] or (aux == "be" and nextv.feature == "ing")
                or (aux == "have" and (nextv.feature=="past" or nextv.root == "read"))
                or (aux == "be" and nextv.feature == "past") then
            if modals[aux] then modal = aux end
            if aux == "have" and not modal then tense = "past" end
            passive=aux=="be" and nextv.feature=="past"
            root,base=nextv.root,i
            i=i+1
        end
    end
    return {root=root, tense=tense == "ing" and "present" or tense or "present",
        neg=neg, modal=modal, passive=passive, token=t[base]},i
end

local function sense(ctx, v, obj, gap, direction)
    local group = lexical(ctx.data,v.token,"v")
    local best,max
    for index,item in ipairs(group) do
        local frame, limit = item.frame:match("^([^%.]+)%.?(.*)$")
        local p=lex.paradigm(ctx.data,item.word,"v")
        local flags=p and p.flags or "----"
        local has_obj=obj or gap
        local score=item.authored and 5 or 0
        if frame=="passive" then score=score+(v.passive and 40 or -60)
        elseif frame=="imperative" then score=score+(v.tense=="imperative" and 20 or -30)
        elseif frame=="motion" then score=score+(direction and 12 or has_obj and -12 or 2)
        elseif frame=="intr" then score=score+(has_obj and -14 or 7)
        elseif frame=="obj" or frame=="dat" or frame=="gen" or frame=="dobj" then
            score=score+(has_obj and 8 or -5)
        elseif frame=="speech" then score=score+15
        elseif frame=="content" then score=score+4
        elseif flags:sub(3,3)=="i" then score=score+(has_obj and -12 or 4)
        elseif flags:sub(3,3)=="t" then score=score+(has_obj and 5 or -3) end
        if limit and limit~="" then score=score+(obj and obj.word==limit and 35 or -40) end
        if (v.tense=="past" or v.tense=="future") and flags:sub(4,4)=="f" then score=score+2 end
        if v.tense=="present" and flags:sub(4,4)=="f" then score=score-5 end
        score=score-index*0.001
        if not max or score>max then best,max=item,score end
    end
    local frame=best and best.frame:match("^[^%.]+")
    return best and best.word or v.token.raw, frame or ""
end

local function tail_np(ctx,i,last)
    local t=ctx.t[i]
    if not t or i>last or (bare_place[t.word] and i==last) or clause_markers[t.word] then return nil,i end
    if not lexical_head(t) and not articles[t.word] and not possessives[t.word] and not t.pos.a then return nil,i end
    return np(ctx,i,last)
end

local function single(ctx,t)
    if not t then return "" end
    if t.word=="not" then return "не" end
    if t.word=="hello" then return ctx.formal and "здравствуйте" or "привет" end
    if t.raw=='"' then
        ctx.quote=not ctx.quote
        return ctx.quote and "«" or "»"
    end
    local value=candidate(ctx.data,t,"r") or candidate(ctx.data,t,"n") or candidate(ctx.data,t,"a") or candidate(ctx.data,t,"v")
    return value and value.word or t.raw
end

local function object_case(frame)
    return frame=="dat" and "d" or frame=="gen" and "g" or "a"
end

local clause
local function relative(ctx, head, pos, last, trailing)
    local t=ctx.t
    local marker=clause_markers[t[pos] and t[pos].word]
    local subj,start=np(ctx,pos+(marker and 1 or 0),last)
    if not subj then return end
    local v,after=verb(ctx,start,last)
    if not v then return end
    -- Require a second predicate to find the end. An occupied direct-object
    -- slot or intrinsically intransitive verb is not a zero object relative.
    local obj,nextpos=tail_np(ctx,after,last)
    if obj and vtoken(t[after]) and not articles[t[after].word] then obj,nextpos=nil,after end
    local boundary=obj and nextpos or after
    if trailing then
        if vtoken(t[boundary]) then return end
        boundary=last+1
    elseif not vtoken(t[boundary]) then return end
    local _, frame=sense(ctx,v,obj,not obj,false)
    local _, default_frame=sense(ctx,v,nil,false,false)
    if obj or frame=="intr" or frame=="motion" or head.content and default_frame=="intr" then
        if not head.content then return end
        return "о том, что " .. clause(ctx,pos+(marker and 1 or 0),boundary-1,1),boundary,true
    end
    local pron=lex.adjective(ctx.data,"который",head.num,head.gender,object_case(frame),head.animate)
    return pron .. " " .. clause(ctx,pos+(marker and 1 or 0),boundary-1,1,true),boundary
end

clause = function(ctx, first, last, depth, gap)
    if first>last then return "" end
    if depth>8 then return table.concat((function()
        local result={}
        for i=first,last do result[#result+1]=ctx.t[i].raw end
        return result
    end)()," ") end
    local t,data=ctx.t,ctx.data
    local subject, i=np(ctx,first,last)
    local rel, is_content
    if subject and i and i<last and not vtoken(t[i]) then
        local part,post,content=relative(ctx,subject,i,last)
        if part then rel,i,is_content=part,post,content end
    end
    local existential, ex_end
    if t[first].word=="there" then existential, ex_end=verb(ctx,first+1,last) end
    local ex=existential and existential.root=="be"
    if ex then subject,i=nil,first+1 end
    local v,nextpos=verb(ctx,i or first,last)
    if ex then v,nextpos=existential,ex_end end
    local imperative=false
    if v and subject and i==first+1 and subject.num=="s" and subject.person=="3" and
        not v.token.pos.v.feature and not v.token.aux and vtoken(t[first]) then
        subject=nil; v,nextpos=verb(ctx,first,last); imperative=true
    end
    if not v and not subject and first<=last and vtoken(t[first]) then
        v,nextpos=verb(ctx,first,last); imperative=true
    elseif v and not subject and not ex then
        imperative=true
    elseif not v and subject and vtoken(t[first]) and first<last then
        subject=nil
        v,nextpos=verb(ctx,first,last); imperative=true
    end
    if not v then
        local words={}
        if subject then words[1]=noun(ctx,subject,"n") end
        for j=subject and i or first,last do words[#words+1]=single(ctx,t[j]) end
        return require("en_ru.tokenize").format(words)
    end
    i=nextpos
    local copula,possess = v.root=="be",v.root=="have"
    local sentential=t[i] and t[i].word=="that" and i<last and
        (ctx.t[i+1].pos.n or pronouns[ctx.t[i+1].word])
    local obj,after
    local language = candidate(data,t[i],"r")
    local speech = false
    if language and language.frame=="language" then
        for _,entry in ipairs(lexical(data,v.token,"v")) do
            if entry.frame=="speech" then speech=true; break end
        end
    end
    if not sentential and not speech then obj,after=tail_np(ctx,i,last) end
    if obj and t[i].pos.a and not t[i].pos.n and copula then obj=nil end
    if obj and t[i].word=="nothing" and not copula then v.neg=true end
    local directional=false
    for j=i,last do
        if bare_place[t[j].word] and (j==i or not preps[t[j-1].word]) or
            (t[j].word=="to" or t[j].word=="into") and lexical_head(t[j+1]) then
            directional=true; break
        end
    end
    if imperative then v.tense="imperative" end
    local lemma,frame=sense(ctx,v,obj,gap,directional)
    local features=subject or default_subject
    local out={}
    local function put(s) if s and s~="" then out[#out+1]=s end end
    if subject then
        if possess and obj then put("у " .. noun(ctx,subject,"g",true))
        else put(noun(ctx,subject,"n")) end
        if rel then if not is_content then put(",") end; put(rel); put(",") end
    end
    local neg=v.neg or obj and (obj.neg or obj.word=="nobody" or obj.word=="nothing")
    if ex or possess and obj then
        local ex_features=neg and {num="s",gender="n",person="3"} or obj or features
        local copula_word=v.tense=="past" and lex.verb(data,"быть",ex_features,"past")
            or v.tense=="future" and lex.verb(data,"быть",ex_features,"future")
            or neg and "нет" or "есть"
        if neg and v.tense~="present" then put("не") end
        put(copula_word)
    elseif copula and not v.modal then
        if v.neg then put("не") end
        if v.tense~="present" then put(lex.verb(data,"быть",features,v.tense)) end
    else
        if neg then put("не") end
        if v.modal then
            put(v.modal=="can" and lex.verb(data,modals.can,features,v.tense) or modals[v.modal])
        end
        local conjugated = lex.verb(data,lemma,imperative and {num=ctx.formal and "p" or "s",person="2",gender="m"} or features,
            v.modal and "inf" or imperative and "imperative" or v.tense)
        if v.passive and frame ~= "passive" and v.tense == "present" then
            local generated = lex.passive(data,lemma,features)
            if generated then conjugated=generated end
        end
        put(conjugated)
    end
    if copula and not obj and i<=last and t[i].pos.a and not bare_place[t[i].word] then
        put(lex.adjective(data,candidate(data,t[i],"a").word,features.num,features.gender,
            v.tense=="present" and "n" or "i",features.animate or "-"))
        i=i+1
    elseif obj then
        local indirect
        if frame=="dobj" then
            local second,following=tail_np(ctx,after,last)
            if second then indirect,obj,after=obj,second,following end
        end
        if indirect then put(noun(ctx,indirect,"d")) end
        put(noun(ctx,obj,(ex or possess) and (neg and "g" or "n") or copula and "n" or object_case(frame)))
        i=after
        if i and i<last and not vtoken(t[i]) then
            local part, post, content=relative(ctx,obj,i,last,true)
            if part then if not content then put(",") end; put(part); i=post end
        end
    end
    if sentential then put(","); put("что"); put(clause(ctx,i+1,last,depth+1)); i=last+1 end
    while i<=last do
        local w=t[i].word
        local pp=preps[w]
        local linked_subject, linked_verb
        if joins[w] then linked_subject, linked_verb=np(ctx,i+1,last) end
        if joins[w] and (not pp or linked_subject and vtoken(t[linked_verb])) then
            if w~="and" and w~="or" and out[#out]~="," then put(",") end
            put(joins[w]); put(clause(ctx,i+1,last,depth+1)); break
        elseif pp then
            local group,following=np(ctx,i+1,last)
            if w=="before" and vtoken(t[i+1]) and t[i+1].pos.v.feature=="ing" then
                put(","); put(joins.before)
                local inf=sense(ctx,{token=t[i+1],tense="future"},nil,true,false)
                put(inf)
                i=i+2
            else
            if w=="to" and vtoken(t[i+1]) and not group then
                local inf=sense(ctx,{token=t[i+1],tense="present"},nil,false,false)
                put(inf); i=i+2
            elseif group then
                if group.word=="home" and w=="at" then put(bare_place.home.static)
                else put(pp[1]); put(noun(ctx,group,pp[3] and frame=="motion" and pp[3] or pp[2],true)) end; i=following
            else put(pp[1]); i=i+1 end
            end
        elseif bare_place[w] then
            put(frame=="motion" and bare_place[w].toward or bare_place[w].static); i=i+1
        else put(single(ctx,t[i])); i=i+1 end
    end
    return require("en_ru.tokenize").format(out)
end

function M.sentence(data, words, options)
    local ctx={data=data,t=analyse_words(data,words),formal=options.formal}
    local text=clause(ctx,1,#ctx.t,0)
    return text,ctx.t
end

return M
