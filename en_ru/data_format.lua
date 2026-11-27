-- Native UTF-8 dictionary representation shared by the engine and editor.
local M = {}
M.pos = {n="noun", v="verb", a="adjective", r="adverb"}
M.case = {n="nominative", g="genitive", d="dative", a="accusative", i="instrumental", l="prepositional"}
M.gender = {m="masculine", f="feminine", n="neuter"}
M.number = {s="singular", p="plural"}
M.animacy = {["+"]="animate", ["-"]="inanimate"}
M.transitivity = {t="transitive", i="intransitive"}
M.aspect = {f="perfective", ["-"]="imperfective"}
M.frames = {
    [""]="unrestricted", intr="intransitive", obj="direct object (accusative)",
    dat="indirect object (dative)", gen="object (genitive)", ins="object (instrumental)",
    dobj="direct and indirect objects", toward="object with directional preposition",
    motion="motion / destination", locative="inanimate subject with a location",
    content="content clause", copula="copula", possess="possession",
    imperative="imperative sense", passive="passive sense", speech="speech",
    language="language (adverbial)", deictic="place or direction",
    infrastructure="infrastructure or utility sense",
    proper="proper name when capitalized in the source",
    participle="verb also used in bare result messages",
    statistic="label for a numeric reading",
}
local function keys(t)
    local out={}
    for k in pairs(t) do out[#out+1]=k end
    table.sort(out)
    return out
end
M.keys=keys

function M.fields(line)
    local row={}
    for item in (line.."\t"):gmatch("(.-)\t") do row[#row+1]=item end
    return row
end

function M.row(fields)
    return (table.concat(fields,"\t"):gsub("\t+$",""))
end

function M.form_name(pos, code)
    local a,b,c=code:match("^(.)(.)(.?)$")
    if pos=="n" and M.number[a] and M.case[b] and (c=="" or c=="x") then
        return M.number[a].."."..M.case[b]..(c=="x" and ".after_preposition" or "")
    elseif pos=="a" and (M.gender[a] or a=="p") and M.case[b] and (c=="" or M.animacy[c]) then
        return (M.gender[a] or "plural").."."..M.case[b]..(c~="" and "."..M.animacy[c] or "")
    elseif (pos=="a" or pos=="v") and a=="q" and c=="" and (M.gender[b] or b=="p") then
        return (pos=="a" and "short." or "short_passive.")..(M.gender[b] or "plural")
    elseif pos=="v" then
        if a=="i" and M.number[b] and c=="" then return "imperative."..M.number[b] end
        if a=="t" and (M.gender[b] or b=="p") and c=="" then return "past."..(M.gender[b] or "plural") end
        if (a=="p" or a=="f") and M.number[b] and c:match("^[123]$") then
            return (a=="p" and "present." or "future.")..M.number[b].."."..c
        end
    end
end

local form_codes={n={},v={},a={}}
for pos,map in pairs(form_codes) do
    for a in ("spmfniptq"):gmatch(".") do
        for b in ("ngdailspmf"):gmatch(".") do
            for _,c in ipairs({"","x","+","-","1","2","3"}) do
                local code=a..b..c
                local name=M.form_name(pos,code)
                if name then map[name]=code end
            end
        end
    end
end
function M.form_code(pos,name)
    return form_codes[pos] and form_codes[pos][name]
end

function M.forms(pos)
    return form_codes[pos] or {}
end

function M.flags(pos,flags)
    assert(flags:match("^[mfn][+-][ti-][f-]$"),"invalid grammatical flags: "..flags)
    if pos=="n" then
        return {gender=M.gender[flags:sub(1,1)], animacy=M.animacy[flags:sub(2,2)]}
    elseif pos=="v" then
        return {transitivity=M.transitivity[flags:sub(3,3)] or "unspecified", aspect=M.aspect[flags:sub(4,4)]}
    end
    return {}
end

function M.decode(lemma,variants,pos)
    local out={}
    if variants=="" then return out end
    for field in (variants..","):gmatch("(.-),") do
        local feature,len,suffix=field:match("^([^=]+)=(%d+):([^,]*)$")
        local length=tonumber(len)
        assert(feature and (not pos or M.form_name(pos,feature)) and not out[feature] and
            length and length<=#lemma and
            (length==#lemma or not lemma:sub(length+1,length+1):match("[\128-\191]")),
            "invalid form delta for "..lemma..": "..field)
        local word=lemma:sub(1,length)..suffix
        assert(utf8.len(word) and word~="","invalid UTF-8 form for "..lemma)
        out[feature]=word
    end
    return out
end

function M.encode(lemma,forms)
    local out={}
    for _,code in ipairs(keys(forms)) do
        local word=forms[code]
        local i=0
        while i<#lemma and i<#word and lemma:byte(i+1)==word:byte(i+1) do i=i+1 end
        while i>0 and lemma:byte(i+1) and lemma:byte(i+1)>=128 and lemma:byte(i+1)<192 do i=i-1 end
        out[#out+1]=code.."="..i..":"..word:sub(i+1)
    end
    return table.concat(out,",")
end

return M
