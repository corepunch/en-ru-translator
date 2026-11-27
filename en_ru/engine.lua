local lex = require "en_ru.lexicon"
local tokenize = require "en_ru.tokenize"
local grammar = require "en_ru.grammar"
local M = {}

function M.load(options)
    options = options or {}
    return lex.load(options.data_dir, options.read_file)
end

local titles = {mr=true, mrs=true, ms=true, dr=true, prof=true}
local reference = {fig=true, eq=true, sec=true, vol=true, no=true}
local function after_dot(tokens,i)
    local previous, following = tokens[i-1],tokens[i+1]
    if not previous or not following then return true end
    if titles[previous.word] and following.raw:match("^%u") then return false end
    if reference[previous.word] and following.raw:match("^%d") then return false end
    return true
end

local function translate_line(input, options, data, traces)
    local prefix, text=input:match("^(%s*[%*%-%+]%s+)(.+)$")
    if not prefix then prefix,text=input:match("^(%s*%d+[.)]%s+)(.+)$") end
    if not prefix then prefix,text=input:match("^(%s*)(.*)$") end
    local tokens = tokenize.words(text)
    local sentences, current={}, {}
    local sentence_start=true
    local function flush()
        if #current == 0 then return end
        local ending, quoted={},false
        if current[#current].raw=='"' then quoted=true; current[#current]=nil end
        while #current>0 and current[#current].raw:match("^[.?!:;]$") do
            table.insert(ending,1,current[#current].raw); current[#current]=nil
        end
        local result,trace=grammar.sentence(data,current,options,table.concat(ending):find("?",1,true)~=nil)
        if sentence_start then result=tokenize.upper_first(result) end
        result=result..table.concat(ending)
        if quoted then result=result.."»" end
        sentences[#sentences+1]=result
        traces[#traces+1]=trace
        sentence_start=ending[#ending]~=";"
        current={}
    end
    local in_quote=false
    for i,t in ipairs(tokens) do
        if t.raw=='"' then in_quote=not in_quote end
        if t.raw~="." or after_dot(tokens,i) then current[#current+1]=t end
        if (t.raw=="." and after_dot(tokens,i) or t.raw=="?" or t.raw=="!") and
           (not tokens[i+1] or not tokens[i+1].raw:match('^[.?!"]$')) then flush()
        elseif t.raw==";" and not in_quote then flush()
        elseif t.raw=='"' and tokens[i-1] and tokens[i-1].raw:match("^[.?!]$") then flush() end
    end
    flush()
    return prefix..table.concat(sentences," ")
end

function M.translate(input, options)
    options = options or {}
    local data = options.lexicon or M.load(options)
    local traces, lines = {},{}
    input = input:gsub("\r\n","\n")
    for line in (input.."\n"):gmatch("(.-)\n") do
        lines[#lines+1]=translate_line(line,options,data,traces)
    end
    return table.concat(lines,"\n"), {sentences=traces}
end

return M
