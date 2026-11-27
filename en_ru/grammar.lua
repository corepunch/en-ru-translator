-- Small, inspectable English clause analysis and Russian transfer.
local lex = require "en_ru.lexicon"
local tokenize = require "en_ru.tokenize"
local M = {}

local articles = {a=true, an=true, the=true, some=true, no=true}
local lex_pos = {"n", "v", "a", "r"}
local fallback_pos = {"r", "n", "a", "v"}
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
    without={"без","g"}, behind={"за","i"}, above={"над","i"}, over={"над","i"}, below={"под","i"},
    through={"через","a"}, across={"через","a"}, by={"у","g"}, toward={"к","d"}, of={"","g"}, before={"перед","i"}, after={"после","g"},
    about={"о","l"}, near={"около","g"}, beside={"рядом с","i"}, under={"под","i","a"}, between={"между","i"},
    using={"с помощью","g"},
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
    upstairs={static="наверху", toward="наверх"}, downstairs={static="внизу", toward="вниз"},
    ashore={static="на берегу", toward="на берег"}, back={toward="обратно"},
    forward={toward="вперёд", static="вперёд"},
}
local compass = {north="север", south="юг", west="запад", east="восток",
    northeast="северо-восток", northwest="северо-запад", southeast="юго-восток", southwest="юго-запад"}
local vertical = {up="вверх", upward="вверх", upwards="вверх", down="вниз", downward="вниз", downwards="вниз"}
local function is_place(w) return bare_place[w] or compass[w] or vertical[w] end
local numerals = {one=1,two=2,three=3,four=4,five=5,six=6,seven=7,eight=8,nine=9,ten=10}
local number_text = {"один","два","три","четыре","пять","шесть","семь","восемь","девять","десять"}
local fixed_pronouns = {["его"]=true,["её"]=true,["их"]=true}
local default_subject = {num="s", gender="m", person="3"}
local negative_pronouns = {nobody=true, nothing=true, ["no one"]=true}

local function analyse_words(data, words)
    local out = {}
    local i = 1
    while i <= #words do
        local t = words[i]
        local combined, length
        local root, feature=lex.english(data,t.word,"v")
        for n=math.min(3,#words-i+1),2,-1 do
            local parts={}
            for k=i,i+n-1 do parts[#parts+1]=words[k].word end
            local name=table.concat(parts," ")
            local group=data.words[name]
            local verb_name=root and root.." "..table.concat(parts," ",2)
            local noun_root, noun_number=lex.english(data,words[i+n-1].word,"n")
            local compound=noun_number and table.concat(parts," ",1,n-1).." "..noun_root
            local compound_noun=compound and data.words[compound] and data.words[compound].n
            if group or compound_noun or (verb_name and data.words[verb_name]) then
                local surface={}
                for j=i,i+n-1 do surface[#surface+1]=words[j].raw end
                combined,length={word=name,raw=table.concat(surface," "),pos={}},n
                if group then
                    for _,pos in ipairs(lex_pos) do if group[pos] then combined.pos[pos]={root=name} end end
                end
                if verb_name and data.words[verb_name] and data.words[verb_name].v then
                    combined.pos.v={root=verb_name,feature=feature}
                end
                if compound_noun and not combined.pos.n then
                    combined.pos.n={root=compound,feature=noun_number}
                end
                break
            end
        end
        if combined then
            out[#out+1]=combined
            i=i+length
        else
            local expansion = contractions[t.word]
            local owner=not expansion and words[i+1] and t.word:match("^(.+)'s$")
            if owner then
                local next_word, following_word=words[i+1].word,words[i+2] and words[i+2].word
                if lex.english(data,next_word,"n") or (following_word and lex.english(data,next_word,"a")
                    and lex.english(data,following_word,"n")) then
                    expansion={owner,"'s"}
                end
            end
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
                local surface=value==owner and t.raw:sub(1,-3) or expansion and value or t.raw
                local w = {word=value, raw=surface, pos={}}
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
            i=i+1
        end
    end
    return out
end

local function vtoken(t) return t and t.pos.v end
local function follows_group(t)
    return not t or preps[t.word] or joins[t.word] or clause_markers[t.word] or is_place(t.word)
        or t.aux or t.raw:match("^%p$")
end
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

local function place_particle(t, i, last)
    local w=t[i] and t[i].word
    if not is_place(w) then return false end
    if not bare_place[w] then return true end
    local next=t[i+1]
    if i>=last or not next then return true end
    return not (articles[next.word] or possessives[next.word] or pronouns[next.word]
        or w=="back" and next.word=="of"
        or next.pos.n and not (next.pos.r or vtoken(next)) and not joins[next.word])
end

-- Recognize an NP by its grammatical shape, not by matching a translated phrase.
local function np(ctx, i, last, depth)
    local t, data = ctx.t, ctx.data
    local start, mods = i, {}
    local number, possessive, possessor, neg, count, quantity
    if i > last then return nil, i end
    if t[i].word=="all" and i<last and (articles[t[i+1].word] or lexical_head(t[i+1])) then
        mods[#mods+1]="весь"; i=i+1
    end
    if articles[t[i].word] then neg = t[i].word == "no"; i = i + 1 end
    if i <= last and possessives[t[i].word] and i < last and
            (not pronouns[t[i].word] or lexical_head(t[i+1]) or t[i+1].pos.a) then
        possessor = t[i].word
        possessive = possessives[possessor]
        if t[i].word == "your" and ctx.formal then possessive = "ваш" end
        i = i + 1
    end
    if i < last and (numerals[t[i].word] or t[i].word:match("^%d+$")) and
        (lexical_head(t[i+1]) or t[i+1].pos.a) then
        count = t[i].word
        quantity = numerals[count] or tonumber(count)
        i = i + 1
    end
    while i < last and t[i].pos.a and (not follows_group(t[i]) or compass[t[i].word]) do
        local next=t[i+1]
        if i+1==last and next.raw:match("^%d+$") and t[i].pos.n then break end
        local coordinated=next.word=="and" and i+2<last and t[i+2].pos.a
        if not coordinated and (follows_group(next) or not(lexical_head(next) or next.pos.a)) then break end
        if t[i].pos.v and t[i].pos.v.feature=="past" and t[i].pos.n and i==start then break end
        mods[#mods + 1] = candidate(data,t[i],"a").word
        i=i+1
        if coordinated then mods[#mods+1]=false; i=i+1 end
    end
    local head = t[i]
    if i > last or not head or joins[head.word] or preps[head.word] or head.aux then
        return nil, start
    end
    local p = pronouns[head.word]
    local sense
    for _, item in ipairs(lexical(data,head,"n")) do
        if not item.frame:find(".",1,true) then sense=item; break end
    end
    if not p and not sense and not lexical_head(head) and (i == start or head.pos.v or head.pos.r) then
        return nil, start
    end
    if not p and not sense and (head.raw == "" or not head.raw:match("^[%a%d]")) then return nil,start end
    local lemma = p and p[1] or compass[head.word] or sense and sense.word or head.raw
    local authored_modifier=sense and sense.modifier
    local complement
    if authored_modifier and authored_modifier ~= "" then
        if authored_modifier:find(" ",1,true) then complement=authored_modifier
        elseif lex.paradigm(data,authored_modifier,"n") and not lex.paradigm(data,authored_modifier,"a") then
            complement=lex.noun(data,authored_modifier,"s","g")
        else mods[#mods+1]=authored_modifier end
    end
    local par = lex.paradigm(data, lemma,"n")
    local english_lemma = head.pos.n and head.pos.n.root or head.word
    number = p and p[2] or head.pos.n and head.pos.n.feature or "s"
    if head.word == "you" and ctx.formal then lemma, number = "вы", "p" end
    if english_lemma == "news" then number = "s" end
    if english_lemma == "people" and lemma == "люди" then number = "p" end
    if quantity then number = quantity == 1 and "s" or "p" end
    if (head.word=="nothing" or head.word=="something" or head.word=="nobody") and
        i<last and t[i+1].pos.a and not vtoken(t[i+1]) then
        local a = candidate(data,t[i+1],"a")
        if a then mods.post = a.word; i = i + 1 end
    elseif (head.word=="nothing" or head.word=="something") and i<last and t[i+1].pos.a and
        (i+1==last or not lexical_head(t[i+2])) then
        mods.post=candidate(data,t[i+1],"a").word; i=i+1
    end
    local child, finish
    if (depth or 0)<3 and i+2<=last and t[i+1].word=="of" then
        child,finish=np(ctx,i+2,last,(depth or 0)+1)
    end
    local group={lemma=lemma, complement=complement, child=child, num=number, person=p and p[3] or "3", gender=p and p[4] or
        par and par.flags:sub(1,1) or "m", animate=par and par.flags:sub(2,2) or p and "+" or "-",
        neg=neg, mods=mods, possessive=possessive, possessor=possessor, count=count, quantity=quantity, word=english_lemma,
        frame=sense and sense.frame, content=sense and sense.frame == "content", token=head}
    if not child and (depth or 0)<3 and i+2<=last and t[i+1].word=="'s" then
        local owned, after=np(ctx,i+2,last,(depth or 0)+1)
        if owned and not owned.child then
            owned.child=group
            return owned,after
        end
    end
    return group,finish or i+1
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
    for _, mod in ipairs(group.mods) do
        if mod then add_adj(mod) else forms[#forms+1]="и" end
    end
    local nominal=lex.noun(ctx.data,group.lemma,nounnum,nouncase,pp)
    if group.frame=="proper" and group.token.raw:match("^%u") then nominal=tokenize.upper_first(nominal) end
    forms[#forms + 1] = nominal
    if group.complement then forms[#forms+1]=group.complement end
    if group.child then forms[#forms+1]=noun(ctx,group.child,"g") end
    if group.mods.post then
        forms[#forms+1]=lex.adjective(ctx.data,group.mods.post,"s","n","g","-")
    end
    return table.concat(forms," ")
end

local function select_nominal_sense(data, group, frame)
    for _, reading in ipairs(lexical(data,group.token,"n")) do
        if reading.frame==frame then
            local paradigm=lex.paradigm(data,reading.word,"n")
            if paradigm then
                group.lemma,group.gender,group.animate=reading.word,paradigm.flags:sub(1,1),paradigm.flags:sub(2,2)
            end
            return
        end
    end
end

local function located_np(ctx, first, last, case)
    local group, after=np(ctx,first,last)
    if not group then return nil,first end
    return noun(ctx,group,case,true),after
end

local function place(ctx, first,last,directed,only_preposition,stationary)
    local t=ctx.t
    if first>last or not t[first] then return nil,first end
    local w=t[first].word
    if compass[w] and first<last and t[first+1].word=="of" then
        local anchor,after=located_np(ctx,first+2,last,"g")
        if anchor then return "к "..lex.noun(ctx.data,compass[w],"s","d").." от "..anchor,after end
    end
    if w=="to" and first<last then
        local k=t[first+1].word=="the" and first+2 or first+1
        if k<=last and compass[t[k].word] then
            local direction=compass[t[k].word]
            return stationary and "к "..lex.noun(ctx.data,direction,"s","d") or "на "..direction,k+1
        end
    end
    if not only_preposition then
        if bare_place[w] and place_particle(t,first,last) then
            local phrase
            if directed then phrase=bare_place[w].toward else phrase=bare_place[w].static end
            if phrase then return phrase,first+1 end
        end
        if vertical[w] then return vertical[w],first+1 end
        if compass[w] then return "на "..compass[w],first+1 end
    end
    local pp=preps[w] or (w=="inside" and {"в","l","a"}) or (w=="outside" and {"за пределами","g"})
    if not pp or w=="before" or w=="after" or w=="of" then return nil,first end
    local phrase,after=located_np(ctx,first+1,last,directed and (pp[3] or pp[2]) or pp[2])
    if phrase then return pp[1] .. " " .. phrase,after end
    return nil,first
end

local function verb(ctx,i,last)
    local t=ctx.t
    if i > last or not vtoken(t[i]) then return end
    local root, tense, aux = t[i].pos.v.root, t[i].pos.v.feature, t[i].aux
    local base = i
    local neg, modal, passive, modifier
    i = i + 1
    if i <= last and t[i].word == "not" then neg=true; i=i+1 end
    local following=t[i+1] and t[i+1].pos.v
    if aux=="be" and i<last and t[i].pos.r and not t[i].pos.n and not articles[t[i].word] and following and
        (following.feature=="ing" or following.feature=="past") then
        modifier=t[i]; i=i+1
    end
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
    if root=="be" and i<=last and vtoken(t[i]) and t[i].pos.v.feature=="past" then
        root,base,passive=t[i].pos.v.root,i,true
        i=i+1
    end
    return {root=root, tense=tense == "ing" and "present" or tense or "present",
        neg=neg, modal=modal, passive=passive, modifier=modifier, token=t[base]},i
end

local function existential_at(ctx,i,last)
    if i<=last and ctx.t[i] and ctx.t[i].word=="there" then
        local v,after=verb(ctx,i+1,last)
        if v and v.root=="be" then return v,after end
    end
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
        elseif frame=="participle" then score=score+(v.passive and 30 or has_obj and 8 or -5)
        elseif frame=="imperative" then score=score+(v.tense=="imperative" and 20 or -30)
        elseif frame=="motion" then score=score+(direction and 12 or has_obj and -12 or 2)
        elseif frame=="intr" then score=score+(has_obj and -14 or 7)
        elseif frame=="obj" or frame=="dat" or frame=="gen" or frame=="ins" or frame=="toward" or frame=="dobj" then
            score=score+(has_obj and 8 or -5)
        elseif frame=="locative" then score=score+(v.location and 20 or -30)
        elseif frame=="speech" then score=score+15
        elseif frame=="content" then score=score+4
        elseif flags:sub(3,3)=="i" then score=score+(has_obj and -12 or 4)
        elseif flags:sub(3,3)=="t" then score=score+(has_obj and 5 or -3) end
        if limit and limit~="" then score=score+(obj and obj.word==limit and 35 or -40) end
        if (v.tense=="past" or v.tense=="future") and flags:sub(4,4)=="f" then score=score+2 end
        if v.passive and flags:sub(4,4)=="f" then score=score+5
        elseif v.tense=="present" and flags:sub(4,4)=="f" then score=score-5 end
        score=score-index*0.001
        if not max or score>max then best,max=item,score end
    end
    local frame=best and best.frame:match("^[^%.]+")
    return best and best.word or v.token.raw, frame or ""
end

local function tail_np(ctx,i,last)
    local t=ctx.t[i]
    if not t or i>last or place_particle(ctx.t,i,last) or t.aux or clause_markers[t.word] then return nil,i end
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
    for _, pos in ipairs(fallback_pos) do
        for _, value in ipairs(lexical(ctx.data,t,pos)) do
            if pos~="n" or not value.frame:find(".",1,true) then
                return value.frame=="proper" and t.raw:match("^%u") and tokenize.upper_first(value.word) or value.word
            end
        end
    end
    return t.raw
end

local function object_case(frame)
    return frame=="dat" and "d" or frame=="gen" and "g" or frame=="ins" and "i" or "a"
end

local clause
local function subject_relative(ctx, head, i, last, depth)
    local t=ctx.t
    local marker=t[i] and t[i].word
    local explicit=marker=="which" or marker=="who" or marker=="that"
    local start=explicit and i+1 or i
    local reading=vtoken(t[start])
    if not reading or not explicit and (reading.feature~="ing" or preps[marker]) then return nil,i end
    local v=verb(ctx,start,last)
    if not v then return nil,i end
    local stop=start+1
    while stop<=last and not joins[t[stop].word] and t[stop].raw~="," do stop=stop+1 end
    local pron=lex.adjective(ctx.data,"который",head.num,head.gender,"n",head.animate)
    return clause(ctx,start,stop-1,depth+1,nil,head,pron),stop
end

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

clause = function(ctx, first, last, depth, gap, inherited, inherited_label)
    if first>last then return "" end
    if depth>8 then return table.concat((function()
        local result={}
        for i=first,last do result[#result+1]=ctx.t[i].raw end
        return result
    end)()," ") end
    local t,data=ctx.t,ctx.data
    if not inherited and t[first].word=="if" then
        for j=first+1,last-1 do
            if t[j].raw=="," then
                return "если "..clause(ctx,first+1,j-1,depth+1)..", "..clause(ctx,j+1,last,depth+1)
            end
        end
    end
    local opening, after_opening
    if not inherited then
        opening,after_opening=place(ctx,first,last,false,true)
        if not opening and (t[first].word=="after" or t[first].word=="before" or t[first].word=="that") then
            local front,after=np(ctx,first+1,last)
            local body=after and t[after] and t[after].raw=="," and after+1 or after
            if front and existential_at(ctx,body,last) then
                local preposition=preps[t[first].word]
                if preposition then
                    opening=preposition[1].." "..noun(ctx,front,preposition[2],true)
                    after_opening=after
                else
                    local nominal=candidate(data,front.token,"n")
                    if nominal and nominal.frame=="time" then
                        opening=lex.adjective(data,"тот",front.num,front.gender,"i",front.animate).." "..noun(ctx,front,"i")
                        after_opening=after
                    end
                end
            end
        end
    end
    if opening and t[after_opening] and t[after_opening].raw=="," then after_opening=after_opening+1 end
    local lead=opening and after_opening or first
    local subject, i=np(ctx,lead,last)
    if inherited then subject,i=inherited,first end
    local rel, is_content
    if subject and i and i<last and not vtoken(t[i]) then
        local part,post,content=relative(ctx,subject,i,last)
        if part then rel,i,is_content=part,post,content end
    end
    local existential, ex_end
    if not inherited then existential,ex_end=existential_at(ctx,lead,last) end
    local ex=existential~=nil
    if ex then subject,i=nil,lead+1 end
    local v,nextpos=verb(ctx,i or lead,last)
    local inverted
    if opening and (not v or not subject or t[lead] and t[lead].aux) then
        local candidate_verb, start=verb(ctx,lead,last)
        local group,finish
        if candidate_verb then group,finish=tail_np(ctx,start,last) end
        if group then subject,v,nextpos,inverted=group,candidate_verb,finish,true end
    end
    if not ex and not inherited and ctx.question
        and t[lead] and t[lead].aux=="be" then
        local question_verb, start=verb(ctx,lead,last)
        if question_verb and question_verb.root=="be" then
            local group,finish=np(ctx,start,last)
            local extra
            if group and finish<last and t[finish].word=="and" then extra,finish=np(ctx,finish+1,last) end
            if group and place(ctx,finish,last,false) then
                if extra then
                    inherited_label=noun(ctx,group,"n").." и "..noun(ctx,extra,"n")
                    group.num, group.person="p","3"
                end
                subject,v,nextpos=group,question_verb,finish
            end
        end
    end
    if ex then v,nextpos=existential,ex_end end
    -- Status messages such as "Device registered" omit the passive auxiliary.
    if v and not inherited and subject and subject.animate=="-" and subject.token.pos.n
        and not articles[t[lead].word] and not v.passive and v.token.word:match("ed$")
        and nextpos==last+1 then
        for _, entry in ipairs(lexical(data,v.token,"v")) do
            if entry.frame=="participle" then v.passive,v.tense=true,"present"; break end
        end
    end
    local imperative=false
    local command_start=not pronouns[t[first].word] and vtoken(t[first])
    if v and subject and not inherited and not opening and i==first+1 and subject.num=="s" and subject.person=="3" and
        not v.token.pos.v.feature and not v.token.aux and command_start then
        subject=nil; v,nextpos=verb(ctx,first,last); imperative=true
    end
    if not v and not subject and command_start then
        v,nextpos=verb(ctx,first,last); imperative=true
    elseif v and not subject and not ex and not opening then
        imperative=true
    elseif not v and subject and command_start and first<last then
        subject=nil
        v,nextpos=verb(ctx,first,last); imperative=true
    end
    if not v then
        local words={}
        if opening then words[#words+1]=opening end
        if subject then words[#words+1]=noun(ctx,subject,"n") end
        for j=subject and i or (opening and lead or first),last do words[#words+1]=single(ctx,t[j]) end
        return tokenize.format(words)
    end
    i=nextpos
    local copula,possess = v.root=="be",v.root=="have"
    local sentential=t[i] and t[i].word=="that" and i<last and
        (ctx.t[i+1].pos.n or pronouns[ctx.t[i+1].word] or existential_at(ctx,i+1,last))
    local content_start=sentential and i+1
    if not content_start and existential_at(ctx,i,last) then
        for _,entry in ipairs(lexical(data,v.token,"v")) do
            if entry.frame=="content" then content_start=i; break end
        end
    end
    local obj,after
    local language = candidate(data,t[i],"r")
    local speech = false
    if language and language.frame=="language" then
        for _,entry in ipairs(lexical(data,v.token,"v")) do
            if entry.frame=="speech" then speech=true; break end
        end
    end
    local location=place(ctx,i,last,false)
    local predicate_adverb=copula and not ex and i<last and t[i].pos.r and not articles[t[i].word]
        and (place(ctx,i+1,last,false) or t[i+1].pos.a)
    if not content_start and not speech and not location and not predicate_adverb then obj,after=tail_np(ctx,i,last) end
    -- Select a utility meaning only when the subject and verb license it.
    -- A city can lose electricity while a minister loses political power.
    if obj and subject and subject.frame=="infrastructure" then
        select_nominal_sense(data,obj,subject.frame.."."..v.root)
    end
    if obj and t[i].pos.a and i==last and copula then obj=nil end
    if obj and t[i].word=="nothing" and not copula then v.neg=true end
    local directional=false
    v.location=(opening~=nil or place(ctx,i,last,false)~=nil) and subject and subject.animate=="-"
        and not pronouns[subject.token.word]
    for j=i,last do
        if place_particle(t,j,last) and (j==i or not preps[t[j-1].word]) or
            (t[j].word=="to" or t[j].word=="into") and lexical_head(t[j+1]) then
            directional=true; break
        end
    end
    if imperative then v.tense="imperative" end
    local lemma,frame=sense(ctx,v,obj,gap,directional)
    local features=subject or default_subject
    local out={}
    local function put(s) if s and s~="" then out[#out+1]=s end end
    if opening then put(opening) end
    if ex and obj and after then
        local location, finish=place(ctx,after,last,false)
        if location and (finish==last+1 or t[finish].raw=="," or joins[t[finish].word]) then
            put(location); after=finish
        end
    end
    if subject and not inverted then
        if inherited_label then put(inherited_label)
        elseif possess and obj then put("у " .. noun(ctx,subject,"g",true))
        else put(noun(ctx,subject,"n")) end
        if rel then if not is_content then put(",") end; put(rel); put(",") end
    end
    local neg=v.neg or obj and (obj.neg or negative_pronouns[obj.word])
    if v.modifier then put(single(ctx,v.modifier)) end
    if ex or possess and obj then
        local ex_features=neg and {num="s",gender="n",person="3"} or obj or features
        local copula_word=v.tense=="past" and lex.verb(data,"быть",ex_features,"past")
            or v.tense=="future" and lex.verb(data,"быть",ex_features,"future")
            or neg and "нет" or "есть"
        if neg and v.tense~="present" then put("не") end
        put(copula_word)
    elseif copula and not v.modal then
        if v.neg then put("не") end
        if v.tense~="present" then put(lex.verb(data,"быть",features,v.tense))
        elseif obj and subject and not pronouns[subject.token.word] and subject.word~="this"
            and not obj.token.pos.a then put("—") end
    else
        if neg then put("не") end
        if v.modal and not v.passive then
            put(v.modal=="can" and lex.verb(data,modals.can,features,v.tense) or modals[v.modal])
        end
        local conjugated = lex.verb(data,lemma,imperative and {num=ctx.formal and "p" or "s",person="2",gender="m"} or features,
            v.modal and "inf" or imperative and "imperative" or v.tense)
        if v.passive and frame ~= "passive" then
            local generated = lex.passive(data,lemma,features)
            if generated then
                conjugated=generated
                if v.modal then put(v.modal=="can" and "может быть" or modals[v.modal].." быть")
                elseif v.tense~="present" then put(lex.verb(data,"быть",features,v.tense)) end
            elseif v.modal then
                put(v.modal=="can" and lex.verb(data,modals.can,features,v.tense) or modals[v.modal])
            end
        end
        put(conjugated)
    end
    if inverted then
        put(noun(ctx,subject,"n"))
        if i<=last then
            local part,post=subject_relative(ctx,subject,i,last,depth)
            if part then put(","); put(part); i=post end
        end
    end
    if copula and not obj and i<=last then
        local modifier
        if i<last and t[i].pos.r and t[i+1].pos.a and not is_place(t[i].word) then
            modifier=candidate(data,t[i],"r").word; i=i+1
        end
        if t[i].pos.a and not is_place(t[i].word) and (i==last or follows_group(t[i+1])) then
            local pred=candidate(data,t[i],"a").word
            put(modifier)
            put(v.tense=="present" and lex.short(data,pred,features) or
                lex.adjective(data,pred,features.num,features.gender,v.tense=="present" and "n" or "i",features.animate or "-"))
            i=i+1
        elseif modifier then i=i-1 end
    elseif obj then
        local indirect
        if frame=="dobj" then
            local second,following=tail_np(ctx,after,last)
            if second then indirect,obj,after=obj,second,following end
        end
        if indirect then put(noun(ctx,indirect,"d")) end
        if frame=="toward" then put("на") end
        if imperative and obj.possessor=="your" then obj.possessive="свой" end
        put(noun(ctx,obj,(ex or possess) and (neg and "g" or "n") or copula and "n" or object_case(frame)))
        i=after
        if i and i<=last then
            local part, post=subject_relative(ctx,obj,i,last,depth)
            local content
            if not part and i<last and not preps[t[i].word] and not vtoken(t[i]) then
                part,post,content=relative(ctx,obj,i,last,true)
            end
            if part then if not content then put(",") end; put(part); i=post end
        end
    end
    if ex and obj and neg then
        while i<last and (t[i].word=="and" or t[i].word=="or") do
            local item,after=tail_np(ctx,i+1,last)
            if not item or after<=last and vtoken(t[after]) then break end
            put(joins[t[i].word]); put(noun(ctx,item,"g")); i=after
        end
    end
    if content_start then put(","); put("что"); put(clause(ctx,content_start,last,depth+1)); i=last+1 end
    while i<=last do
        local w=t[i].word
        local pp=preps[w]
        local linked_subject, linked_verb
        if joins[w] then linked_subject, linked_verb=np(ctx,i+1,last) end
        if w=="right" and place(ctx,i+1,last,frame=="motion") then
            put("прямо"); i=i+1
        elseif joins[w] and (not pp or linked_subject and vtoken(t[linked_verb])) then
            if w~="and" and w~="or" and out[#out]~="," then put(",") end
            put(joins[w])
            if subject and (w=="and" or w=="or") and vtoken(t[i+1])
                and not (linked_subject and vtoken(t[linked_verb])) then
                put(clause(ctx,i+1,last,depth+1,nil,subject,""))
            else
                put(clause(ctx,i+1,last,depth+1))
            end
            break
        elseif pp or is_place(w) then
            local location, location_end=place(ctx,i,last,frame=="motion",false,copula)
            local group,following=np(ctx,i+1,last)
            if location and not (w=="at" and group and group.word=="home") then
                put(location)
                i=location_end
            elseif is_place(w) then
                put(single(ctx,t[i]))
                i=i+1
            elseif w=="before" and vtoken(t[i+1]) and t[i+1].pos.v.feature=="ing" then
                put(",")
                put(joins.before)
                put(sense(ctx,{token=t[i+1],tense="future"},nil,true,false))
                i=i+2
            elseif w=="to" and vtoken(t[i+1]) and not group then
                put(sense(ctx,{token=t[i+1],tense="present"},nil,false,false))
                i=i+2
            elseif group then
                if group.word=="home" and w=="at" then put(bare_place.home.static)
                else
                    put(pp[1])
                    put(noun(ctx,group,pp[3] and frame=="motion" and pp[3] or pp[2],true))
                end
                i=following
            else
                put(w=="over" and single(ctx,t[i]) or pp[1])
                i=i+1
            end
        else put(single(ctx,t[i])); i=i+1 end
    end
    return tokenize.format(out)
end

local function numeric_label(ctx)
    local t,last=ctx.t,#ctx.t
    if last<3 or not t[last].raw:match("^%d+$") then return end
    local colon=last-1
    if last>=5 and t[colon].raw=="/" and t[colon-1].raw:match("^%d+$") then colon=colon-2 end
    if t[colon].raw~=":" then return end
    local group,finish=np(ctx,1,colon-1)
    if not group then return end
    if finish~=colon then
        local head,after=np(ctx,finish,colon-1)
        if not head or after~=colon or head.child then return end
        head.child,group=group,head
    end
    select_nominal_sense(ctx.data,group,"statistic.value")
    local value={}
    for i=colon+1,last do value[#value+1]=t[i].raw end
    return noun(ctx,group,"n")..": "..table.concat(value)
end

function M.sentence(data, words, options, question)
    local ctx={data=data,t=analyse_words(data,words),formal=options.formal,question=question}
    local text=numeric_label(ctx)
    if options.kind=="heading" or options.kind=="label" then
        local location,after=place(ctx,1,#ctx.t,false,true)
        if location and after==#ctx.t+1 then text=location
        else
            local group,nextpos=np(ctx,1,#ctx.t)
            if group then
                local case=options.kind=="label" and options.case or "n"
                local nominal=noun(ctx,group,case)
                if nextpos==#ctx.t+1 then text=nominal
                elseif nextpos==#ctx.t and ctx.t[nextpos].raw:match("^%d+$") then
                    text=nominal.." "..ctx.t[nextpos].raw
                else
                    local qualifier,finish=place(ctx,nextpos,#ctx.t,false,true)
                    if qualifier and finish==#ctx.t+1 then text=nominal.." "..qualifier
                    elseif nextpos==#ctx.t then
                        local head,finish=np(ctx,nextpos,#ctx.t)
                        if head and finish==#ctx.t+1 then text=noun(ctx,head,case).." "..noun(ctx,group,"g") end
                    end
                end
            end
        end
    end
    text=text or clause(ctx,1,#ctx.t,0)
    return text,ctx.t
end

return M
