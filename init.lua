#!/usr/bin/env lua
local root = (arg[0] or ""):match("^(.*[/\\])") or "./"
package.path = root .. "?.lua;" .. package.path
local engine = require "en_ru.engine"

local usage = [[Usage: lua init.lua [--data DIR] [--formal] [--trace] [--] [TEXT]
       lua init.lua --document [FILE]
Translate English→Russian offline. Reads stdin when no text or file is given.
]]
local options, extra = {data_dir=root .. "dictionary"}, {}
local whole, trace, no_options = false,false,false
local i=1
while i<=#arg do
    local a=arg[i]
    if not no_options and (a=="--help" or a=="-h") then io.write(usage); os.exit(0)
    elseif not no_options and a=="--" then no_options=true
    elseif not no_options and a=="--document" then whole=true
    elseif not no_options and a=="--formal" then options.formal=true
    elseif not no_options and a=="--trace" then trace=true
    elseif not no_options and a=="--data" then i=i+1; options.data_dir=assert(arg[i],"missing data directory")
    elseif not no_options and a:sub(1,1)=="-" then io.stderr:write("Unknown option: ",a,"\n",usage); os.exit(2)
    else extra[#extra+1]=a end
    i=i+1
end
local ok, result, state=pcall(function()
    local text
    if #extra==0 then text=io.stdin:read("a") or ""
    elseif whole then
        assert(#extra==1,"--document accepts one file")
        local f=assert(io.open(extra[1],"rb"))
        text=f:read("a"); f:close()
    else text=table.concat(extra," ") end
    return engine.translate(text,options)
end)
if not ok then io.stderr:write(result,"\n"); os.exit(1) end
if trace then
    for id, words in ipairs(state.sentences) do
        io.stderr:write("Sentence ",id,":")
        for _,t in ipairs(words) do
            local tags={}
            for tag,v in pairs(t.pos) do tags[#tags+1]=tag..":"..v.root end
            table.sort(tags)
            io.stderr:write(" ",t.raw,"[",table.concat(tags,","),"]")
        end
        io.stderr:write("\n")
    end
end
io.write(result)
if result:sub(-1)~="\n" then io.write("\n") end
