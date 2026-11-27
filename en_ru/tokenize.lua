local M = {}

function M.words(text)
    text = text:gsub("’", "'"):gsub("‘", "'"):gsub("“", '"'):gsub("”", '"')
        :gsub(" ", " "):gsub(" ", " "):gsub("…", "..."):gsub("–", "—")
    local words, i = {}, 1
    while i <= #text do
        local c = text:sub(i, i)
        if c:match("%s") then
            i = i + 1
        else
            local word = text:match("^[%a][%a']*", i)
            if word then
                while true do
                    local next_part = text:match("^%-%a[%a']*", i+#word)
                    if not next_part then break end
                    word=word..next_part
                end
            end
            local dashes=text:match("^%-%-+",i)
            local raw = word or dashes or
                text:match("^%d+[.,]%d+", i) or text:match("^%d+", i) or
                text:match("^[\194-\244][\128-\191]*", i) or c
            -- A trailing quote is punctuation, not part of the word.
            if #raw > 1 and raw:sub(-1) == "'" then raw = raw:sub(1, -2) end
            words[#words + 1] = {raw = dashes and "—" or raw, word = dashes and "—" or raw:lower(), start = i}
            i = i + #raw
        end
    end
    return words
end

function M.format(parts)
    local out, prev = {}, ""
    for _, part in ipairs(parts) do
        if part ~= "" then
            if #out > 0 and not part:match("^[,.:;!?%)%]]") and part ~= "»"
                and not prev:match("^[%(%[]$") and prev ~= "«" then
                out[#out + 1] = " "
            end
            out[#out + 1] = part
            prev = part
        end
    end
    return table.concat(out)
end

local function upper_first(s)
    local leading, ch, rest = s:match("^([%s%p«»]*)([%z\1-\127\194-\244][\128-\191]*)(.*)$")
    if not ch then return s end
    local code = utf8.codepoint(ch)
    if not code then return s end
    if code >= 0x430 and code <= 0x44f then code = code - 0x20
    elseif code == 0x451 then code = 0x401
    else return leading .. ch:upper() .. rest end
    return leading .. utf8.char(code) .. rest
end
M.upper_first = upper_first

return M
