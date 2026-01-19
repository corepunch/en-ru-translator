local utils = require "translator.utils"
local rules = require "translator.rules"
local parser = {}

local function echo(color, s, ...)
	local colors = {
		reset  = "\27[0m",
		red    = "\27[31m",
		green  = "\27[32m",
		yellow = "\27[33m",
		blue   = "\27[34m",
		magenta= "\27[35m",
		cyan   = "\27[36m",
		white  = "\27[37m",
	}
	local f = string.format(s, ...)
	print(colors[color]..f..colors.reset)
end

local en_ru = {}

local function eat(value, _, c) assert(not c or c == value) return c end
local function xor(a, b) return (a and not b) or (b and not a) end

local function is(word, class)
	if not word then return false end
  for i = 1, #class do
		if word:sub(1,1) == 'W' then
			if word:upper():find(class:sub(i,i)) then return true end
		else
			if word:sub(1,1):upper() == class:sub(i,i) then return true end
		end
	end
end

local function extract_pharses(s)
    local c = {}
    return s:gsub("(W[^/]*)/", function(m)
			table.insert(c,m) return "$"..#c
		end), c
end

local function iter(t)
	local d, c, i = {}, {}, 1
	t,c = extract_pharses(t)
	for pos, w in t:gmatch("()(%a+[%d%$/; \127-\255]+)") do
    table.insert(d, { w, t:sub(pos) })
	end
  -- for w in t:gmatch("(%a+[%d%$/; \127-\255]+)") do table.insert(d, w) end
  local function resolve(p)
    if not p then return end
    local a, b = p:match("(%a+)%$(%d+)")
    return b and a .. c[tonumber(b)] or p
  end
  local function chomp(prefix)
		if not d[i] then return end
		local word, _ = table.unpack(d[i])
    if word:sub(1,1) == prefix then i = i + 1 return resolve(word) end
  end
  return function()
		if not d[i] then return end
		local word, rest = table.unpack(d[i])
    local p = resolve(word)
    i = i + 1
		if not p then return
		elseif p:sub(1,1) == 'Z' then return 'Z', p .. (chomp'N' or '') .. (chomp'A' or '')
		else return p:sub(1,1), rest end
  end
end

local function find(t, s)
	for p, d in iter(t) do if s:find(p) then return d end end
end

local function find_and_replace(ts, j, s)
	local z = find(ts[j], 'Z')
	-- print('--', utils.decode(ts[j]), s, z and utils.decode(z))
	if z and string.find('VNA', s) then
		local tmp = z:gsub('^.','V')
		if find(tmp, s) then ts[j] = find(tmp, s) end
	elseif find(ts[j], s) then
		ts[j] = find(ts[j], s)
	end
end

local choose

-- предлог
local function preposition(t, p, i)
  return find(t[i], "P") or t[i][1]
end

-- существительное
local function conjunction(t, p, i)
  return find(t[i], "C") or preposition(t, p, i)
end

-- существительное
local function noun(t, p, i)
  return find(t[i], "N") or conjunction(t, p, i)
end

-- прилагательное перед существительным
local function adverb(t, p, i)
  return is(choose(t, p, i+1), "ANP") and find(t[i], "DI") or noun(t, p, i)
end

-- прилагательное перед существительным
local function adj(t, p, i)
  return is(choose(t, p, i+1), "AN") and find(t[i], "AO") or adverb(t, p, i)
end

-- глагол после местоимения
local function verb(t, p, i)
	return is(p, "XRN~") and find(t[i], "VZGXF") or adj(t, p, i)
end

-- местоимение
choose = function(t, p, i)
	if not t[i] then return nil end
  if #t[i] == 1 then return t[i][1] end
	return find(t[i], "RS") or verb(t, p, i)
end

local function pattern_tokens(m)
  local i, n = 1, false
  return function()
		n = false
		::restart::
    if i > #m then return nil end
    local c = m:sub(i, i)
    if c == '[' then
      local j, close = i + 1, m:find(']', i)
      if not close then error("Unclosed [") end
      i = close + 1
      return 'select', m:sub(j, close - 1), n  -- content between [ ]
    elseif c == '<' then
      local j, close = i + 1, m:find('>', i)
      if not close then error("Unclosed <") end
      i = close + 1
      return 'any', m:sub(j, close - 1), n  -- content between < >
    elseif c == '`' then
      local j, close = i + 1, m:find('`', i + 1)
      if not close then error("Unclosed `") end
      i = close + 1
      return 'literal', m:sub(j, close - 1), n  -- content between ` `
    elseif c == '*' then
      i = i + 1
      return 'wildcard', '*', n
    elseif c == '~' then
      i = i + 1
			n = true
			goto restart
    else
      i = i + 1
      return 'char', c, n
    end
  end
end

local function replacement_tokens(r)
	local i = 1
  return function()
    if not r or i > #r then return nil end
    local c = r:sub(i, i)
		if c == '`' then
      local close = r:find('`', i + 1)
      if not close then error("Unclosed `") end
      local content = r:sub(i + 1, close - 1)
      i = close + 1
      return 'literal', content
    else
      i = i + 1
      return 'char', c
    end
  end
end

local function replace(ts, j, m, t, s)
	if s == ' ' then ts[j] = ' '
	elseif m:find'*' and (j >= #ts or j == 1) then
	elseif t == 'literal' then ts[j] = s
	elseif s == '.' or s == '$' then
	elseif s == '@' then find_and_replace(ts, j, m)
	elseif s then find_and_replace(ts, j, s)
	-- else find_and_replace(ts, j, m) 		
	end
	return j+1
end

local function nop(ts, j, ...)
	return j+1
end

local function try_match_pattern(ts, m, j, f, replace)
	local fallback = nil
	for t, v, i in m do
		::restart::
		if not ts[j] then return false
		elseif t == 'wildcard' and xor(i,j==1 or j>#ts) then eat('@', f())
		elseif t == 'select' and xor(i, find(ts[j],v)) then j=replace(ts,j,v,f())
		elseif t == 'any' then
			local d = eat('$', f())
			fallback = function(n)
				if xor(i, find(ts[n], v)) then
					-- j = replace(ts,n,v,nil,d)
					j = nop(ts,n,v,nil,d)
					return true
				end
			end
		elseif t == 'literal' and xor(i, ts[j] == en_ru[v]) then j=replace(ts,j,v,f())
		elseif t == 'char' and xor(i, find(ts[j], v)) then j=replace(ts,j,v,f())
		elseif fallback and fallback(j) then goto restart
		else return false end
	end
	return true
end

local function match_pattern(ts, m, r)
	for i = 1, #ts do
		if try_match_pattern(ts, pattern_tokens(m), i, replacement_tokens(r), nop) then
			print("Applying "..m, r)
			try_match_pattern(ts, pattern_tokens(m), i, replacement_tokens(r), replace)
			-- return true
		end
	end
end

local function loop(ts)
	-- if match_pattern(ts, "*<TAO>[NV]`ever`", "@$@`Dкогда-либо`") then
	-- if match_pattern(ts, "*`no`,RXK*", "@y    ") then
	-- if match_pattern(ts, "V<TAO>NG", "@$NF") then
	-- if match_pattern(ts, "*<dD,>`if`~<,>`then`", "@$J$j") then
	-- 	echo('green', '*cool*') else echo('red', '*not cool*')
	-- end
	for _, rs in ipairs(rules) do
		for _, r in ipairs(rs) do
			local _, pat, act = table.unpack(r)
			match_pattern(ts, pat, act or "")
		end
	end
end

function parser.collect(dic, ts)
	en_ru = dic
	loop(ts)
	for _, n in ipairs(ts) do
		echo('blue', "%s", type(n)=='table' and utils.debug(n) or utils.decode(n))
	end
	return ts
  -- local out, prev = {}, nil
  -- for i = 1, #ts do
	-- 	local sym = choose(ts, prev, i)
	-- 	if sym and sym ~= "" then
	-- 		if sym:sub(1,1) == 'W' then
	-- 			for word in sym:gmatch("([%a ][0-9]*[\127-\255]+)") do
	-- 				table.insert(out, word)
	-- 				prev = word
	-- 			end
	-- 		else
	-- 			table.insert(out, sym)
	-- 			prev = sym
	-- 		end
	-- 		-- print(utils.decode(sym))
	-- 	else
	-- 		print('skip', utils.debug(ts[i], nil, 1))
	-- 	end
  -- end
  -- return out
end

return parser