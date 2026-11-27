-- Localize a parsed turn, not the game's state or parser input.
local engine = require "en_ru.engine"
local M = {}
local nominal_cases = {"n", "g", "d", "a", "i", "l"}

function M.new(options)
    options = options or {}
    local lexicon = options.lexicon or engine.load(options)
    local function translate(text, kind, case)
        return (engine.translate(text, {lexicon=lexicon, formal=options.formal~=false, kind=kind, case=case}))
    end
    return {
        heading=function(text) return translate(text,"heading") end,
        prose=function(text) return translate(text) end,
        labelForms=function(text)
            local forms,seen={},{}
            for _,case in ipairs(nominal_cases) do
                local form=translate(text,"label",case)
                if not seen[form] then
                    forms[#forms+1]=form
                    seen[form]=true
                end
            end
            return forms
        end,
        choice=function(choice)
            local result={}
            for key,value in pairs(choice) do result[key]=value end
            result.label=translate(choice.label,"label")
            return result
        end,
    }
end

return M
