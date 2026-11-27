local format = require "en_ru.data_format"
local M = {}
local cache = {}

local function records(read, path, fn)
    local body, err = read(path)
    if not body then error(("cannot read %s: %s"):format(path, err or "missing data"), 0) end
    for line in body:gmatch("[^\r\n]+") do
        if line:sub(1, 1) ~= "#" then
            fn(format.fields(line))
        end
    end
end

local function disk(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local data = f:read("a")
    f:close()
    return data
end

local function at(map, key)
    if not map[key] then map[key] = {} end
    return map[key]
end

M.disk = disk

function M.load(root, reader, base_only)
    root = root or "dictionary"
    if not reader and not base_only and cache[root] then return cache[root] end
    local function file(name, fn)
        records(reader or disk, root .. "/" .. name, function(row)
            row.source=name
            fn(row)
        end)
    end
    local data = {words = {}, forms = {}, exceptions = {}}
    local function authored(row)
        local group = at(at(data.words, row[1]), row[2])
        group[#group + 1] = {word = row[3], frame = row[4] or "", modifier = row[5], authored = true, source = row.source}
    end
    local function form(row)
        at(data.forms, row[1])[row[2]] = {flags = row[3], variants = row[4] or "", source = row.source}
    end
    local vocabulary, assets = {}, {}
    file("vocabulary.tsv", function(row) vocabulary[#vocabulary+1]=row end)
    file("assets.tsv", function(row) assets[#assets+1]=row end)
    file("scene.tsv", authored)
    for _, row in ipairs(vocabulary) do authored(row) end
    for _, asset in ipairs(assets) do
        assert(asset[2]:match("^[a-z]+%-%d+%.tsv$"), "invalid data manifest")
        file(asset[2], function(row)
            if asset[1] == "lex" then
                local group = at(at(data.words, row[1]), row[2])
                for word in row[3]:gmatch("[^|]+") do
                    group[#group + 1] = {word = word, frame = "", source = row.source}
                end
            elseif asset[1] == "forms" then
                form(row)
            elseif asset[1] == "exceptions" then
                at(data.exceptions, row[1])[row[2]] = row[3]
            else
                error("unknown dictionary shard type: " .. asset[1])
            end
        end)
    end
    file("scene-forms.tsv", form)
    if not base_only then
        local edited={}
        file("editor-words.tsv",function(row)
            local action,en,pos,ru=table.unpack(row,1,4)
            local senses=at(at(data.words,en),pos)
            for i=#senses,1,-1 do if senses[i].word==ru then table.remove(senses,i) end end
            if action=="set" then
                local group=at(at(edited,en),pos)
                group[#group+1]={word=ru,frame=row[5] or "",modifier=row[6],
                    source=row.source, authored=true}
            else assert(action=="delete","unknown dictionary edit: "..tostring(action)) end
        end)
        for en, tags in pairs(edited) do
            for pos, senses in pairs(tags) do
                for _, entry in ipairs(data.words[en][pos]) do senses[#senses+1]=entry end
                data.words[en][pos]=senses
            end
        end
        for en,tags in pairs(data.words) do
            for pos,senses in pairs(tags) do
                if #senses==0 then tags[pos]=nil end
            end
            if not next(tags) then data.words[en]=nil end
        end
        file("editor-forms.tsv",function(row)
            local action,ru,pos=table.unpack(row,1,3)
            if action=="set" then
                at(data.forms,ru)[pos]={flags=row[4],variants=row[5] or "",source=row.source}
            elseif action=="delete" then
                if data.forms[ru] then data.forms[ru][pos]=nil end
            else error("unknown paradigm edit: "..tostring(action)) end
        end)
    end
    if not reader and not base_only then cache[root] = data end
    return data
end

local function has(data, word, pos)
    local senses=data.words[word] and data.words[word][pos]
    return senses and #senses>0 and senses or nil
end

function M.english(data, word, pos)
    local direct = has(data, word, pos)
    local exception = data.exceptions[word] and data.exceptions[word][pos]
    if exception and (not direct or pos == "v" or pos == "n") then
        for root in exception:gmatch("[^|]+") do
            if root ~= word and has(data, root, pos) then
                return root, pos == "v" and (word:match("ing$") and "ing" or "past")
                    or pos == "n" and "p" or nil
            end
        end
    end
    if direct then return word end

    local function find(stem, ending, feature)
        if stem and has(data, stem .. ending, pos) then return stem .. ending, feature end
    end
    if pos == "v" then
        local stem, suffix = word:match("^(.+)(ing)$")
        if not stem then stem, suffix = word:match("^(.+)(ed)$") end
        if stem then
            local feature = suffix == "ing" and "ing" or "past"
            local root = find(stem, "") or find(stem, "e")
            if not root and stem:sub(-1) == stem:sub(-2, -2) then root = find(stem:sub(1, -2), "") end
            if not root and stem:sub(-1) == "i" then root = find(stem:sub(1, -2), "y") end
            if root then return root, feature end
        end
    end
    if pos == "v" or pos == "n" then
        local feature = pos == "n" and "p" or "present"
        local root = find(word:match("^(.+)ies$"), "y") or
            find(word:match("^(.+)s$"), "") or find(word:match("^(.+)es$"), "")
        if root then return root, feature end
    end
end

function M.paradigm(data, lemma, pos)
    return data.forms[lemma] and data.forms[lemma][pos]
end

local function variant(paradigm, lemma, key)
    if not paradigm then return nil end
    if not paradigm.decoded then
        paradigm.decoded = format.decode(lemma,paradigm.variants)
    end
    return paradigm.decoded[key]
end

function M.noun(data, lemma, number, case, after_preposition)
    local p = M.paradigm(data, lemma, "n")
    local key = number .. case
    return (after_preposition and variant(p, lemma, key .. "x")) or variant(p, lemma, key) or lemma
end

function M.adjective(data, lemma, number, gender, case, animate)
    local p = M.paradigm(data, lemma, "a")
    local key = (number == "p" and "p" or gender) .. case
    return variant(p, lemma, key .. animate) or variant(p, lemma, key) or lemma
end

function M.verb(data, lemma, subject, tense)
    local p = M.paradigm(data, lemma, "v")
    local ending = subject.num .. subject.person
    if tense == "inf" then return lemma end
    if tense == "imperative" then
        return variant(p, lemma, "i" .. subject.num) or lemma
    elseif tense == "past" then
        return variant(p, lemma, "t" .. (subject.num == "p" and "p" or subject.gender)) or lemma
    elseif tense == "future" then
        return variant(p, lemma, "f" .. ending) or
            (variant(M.paradigm(data, "быть", "v"), "быть", "f" .. ending) or "будет") .. " " .. lemma
    end
    return variant(p, lemma, "p" .. ending) or variant(p, lemma, "f" .. ending) or lemma
end

function M.short(data, lemma, subject)
    return variant(M.paradigm(data, lemma, "a"), lemma, "q" .. (subject.num=="p" and "p" or subject.gender))
end

function M.passive(data, lemma, subject)
    return variant(M.paradigm(data, lemma, "v"), lemma, "q" .. (subject.num=="p" and "p" or subject.gender))
end

return M
