-- Localize a parsed turn, not the game's state or parser input.
local engine = require "en_ru.engine"
local M = {}

function M.new(options)
    options = options or {}
    local lexicon = options.lexicon or engine.load(options)
    local function translate(text, kind)
        return (engine.translate(text, {lexicon=lexicon, formal=options.formal~=false, kind=kind}))
    end
    return {
        heading=function(text) return translate(text,"heading") end,
        prose=function(text) return translate(text) end,
        choice=function(choice)
            local result={}
            for key,value in pairs(choice) do result[key]=value end
            result.label=translate(choice.label,"label")
            return result
        end,
    }
end

return M
