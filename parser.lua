local utils = require "utils"
local rules = require "rules"
local dbg = require "dbg"
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
	for pos, w in t:gmatch("()(%a+[%d%$/;,. \127-\255]+)") do
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
		else return p:sub(1,1), p end
  end
end

local function find(t, s)
	for p, d in iter(t) do if s:find(p) then return d end end
end

local function find_and_replace(ts, j, s)
	local z = find(ts[j], 'Z')
	if z and string.find('VNA', s) then
		local tmp = z:gsub('^.','V')
		if find(tmp, s) then
		  dbg.diag("tag", "Z→V:", utils.decode(ts[j], true), "→", utils.decode(find(tmp, s), true))
		  ts[j] = find(tmp, s); return
		end
	end
	local f = find(ts[j], s)
	if f then
		dbg.diag("tag", "resolve:", utils.decode(ts[j], true), "→", utils.decode(f, true))
		ts[j] = f
	-- fallback: if no exact form matches, search for the tag letter inside the token.
	-- For W tokens (multi-word phrases), skip this: sub-resolve would strip the W prefix
	-- and orphan trailing forms (e.g. WAэлектронныйNперевод → AэлектронныйNперевод, losing Nперевод).
	elseif #s == 1 and ts[j]:byte(1) ~= string.byte('W') then
		local _, e = ts[j]:find(s, 1, true)
		if e then
		  dbg.diag("tag", "sub-resolve:", utils.decode(ts[j], true), "→", utils.decode(ts[j]:sub(e), true))
		  ts[j] = ts[j]:sub(e)
		end
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
      -- Rule replacement literals are UTF-8 in rules.lua; convert to CP866 so
      -- the compiler decode pipeline (which expects CP866 tokens) works correctly.
      return 'literal', utils.encode(content)
    else
      i = i + 1
      return 'char', c
    end
  end
end

local function replace(ts, j, m, t, s)
	if s == ' ' then
		-- X2xx (shall/will = future auxiliary) → use 'q' perfective-marker instead of
		-- a silent space so the compiler knows to conjugate the next verb as perfective.
		-- LTGOLD encodes this via T7/T8 constituent-type flags; 'q' is our approximation.
		if ts[j] and ts[j]:sub(1,1) == 'X' then
			local xdigit = ts[j]:match('%d+')
			if xdigit and xdigit:sub(1,1) == '2' then
				ts[j] = 'q'
			else
				ts[j] = ' '
			end
		else
			ts[j] = ' '
		end
	elseif m:find'*' and (j >= #ts or j == 1) then
	elseif t == 'literal' then ts[j] = s
	elseif s == '.' or s == '$' then
	elseif s == '@' then find_and_replace(ts, j, m)
	elseif s == '^' then
		-- word-join: merge token j into the preceding token without a space separator
		if j > 1 and ts[j-1] ~= ' ' then
			ts[j-1] = ts[j-1] .. '^' .. ts[j]
			ts[j] = ' '
		end
	elseif s == 'j' then
		ts[j] = 'j'  -- inject end-of-clause boundary marker
	elseif s == '|' then
		ts[j] = '|'  -- inject clause-boundary separator
	elseif s == '&' then
		-- coordination marker: look for C-form, else no-op
		find_and_replace(ts, j, 'C')
	elseif s == '=' or s == ';' then
		-- case-setting / clause-continuation: no-op until semantics are confirmed
	elseif s then find_and_replace(ts, j, s)
	end
	return j+1
end

local function nop(ts, j, ...)
	return j+1
end

-- try_match_pattern: attempts match starting at position j, returns end position or false
local function try_match_pattern(ts, m, j, f, replace)
	local fallback = nil
	for t, v, i in m do
		::restart::
		if not ts[j] then
			dbg.log(3, "    match fail: end of tokens at pos", j)
			return false
		elseif t == 'wildcard' and xor(i,j==1 or j>#ts) then eat('@', f())
		elseif t == 'select' and xor(i, find(ts[j],v)) then j=replace(ts,j,v,f())
		elseif t == 'any' then
			local d = eat('$', f())
			fallback = function(n)
				if xor(i, find(ts[n], v)) then
					dbg.log(3, "    any-match consumed token", n, "tag", v)
					j = nop(ts,n,v,nil,d)
					return true
				end
			end
		elseif t == 'literal' and xor(i, ts[j] == (type(en_ru[v]) == 'table' and en_ru[v].__lex or en_ru[v])) then j=replace(ts,j,v,f())
		elseif t == 'char' and xor(i, find(ts[j], v)) then j=replace(ts,j,v,f())
		elseif fallback and fallback(j) then goto restart
		else
			dbg.log(3, "    match fail: pos", j, "type", t, "val", v, "neg", i)
			return false
		end
	end
	return j  -- return position after last matched token
end

-- reorder_tokens: apply T5/T6 digit-action reordering to a matched span
-- positions: list of token indices that were matched (in order)
-- digits: the action string (e.g. "23", "3455")
local function reorder_tokens(ts, positions, digits)
	-- snapshot the matched tokens
	local snap = {}
	for k, pos in ipairs(positions) do snap[k] = ts[pos] end
	-- snapshot caps flags alongside tokens so they travel together
	local snap_caps = {}
	if ts.caps then
		for k, pos in ipairs(positions) do snap_caps[k] = ts.caps[pos] end
	end
	dbg.log(2, "    reorder: positions=", table.concat(positions,","),
	  "digits=", digits,
	  "snap=", table.concat(utils.map(snap, function(t)
	    return utils.decode(t, true)
	  end), ","))
	-- track which snap indices have been used
	local used = {}
	-- write back in digit-specified order
	for k = 1, #digits do
		local d = tonumber(digits:sub(k, k))
		if d and d >= 1 and d <= #snap and positions[k] then
			ts[positions[k]] = snap[d]
			if ts.caps then ts.caps[positions[k]] = snap_caps[d] end
			used[d] = true
		end
	end
	-- fill remaining positions with unused snap entries in order
	local next_snap = 1
	for k = #digits + 1, #positions do
		while used[next_snap] do next_snap = next_snap + 1 end
		if next_snap <= #snap and positions[k] then
			ts[positions[k]] = snap[next_snap]
			if ts.caps then ts.caps[positions[k]] = snap_caps[next_snap] end
			used[next_snap] = true
			next_snap = next_snap + 1
		end
	end
	dbg.log(2, "    reorder result:",
	  table.concat(utils.map(positions, function(pos)
	    return utils.decode(ts[pos], true)
	  end), ","))
end

-- collect_positions: dry-run that records which ts indices were consumed
local function collect_positions(ts, m, start)
	local positions = {}
	local fallback = nil
	local j = start
	for t, v, i in m do
		::restart::
		if not ts[j] then
			dbg.log(3, "    collect fail: end of tokens at", j)
			return nil
		end
		if t == 'wildcard' then
			if not xor(i, j==1 or j>#ts) then return nil end
			-- wildcard matches boundary, doesn't consume a token
		elseif t == 'any' then
			fallback = function(n)
				if xor(i, find(ts[n], v)) then
					table.insert(positions, n)
					j = n + 1
					return true
				end
			end
		elseif t == 'select' then
			if not xor(i, find(ts[j], v)) then return nil end
			table.insert(positions, j); j = j + 1
		elseif t == 'literal' then
			if not xor(i, ts[j] == (type(en_ru[v]) == 'table' and en_ru[v].__lex or en_ru[v])) then return nil end
			table.insert(positions, j); j = j + 1
		elseif t == 'char' then
			if not xor(i, find(ts[j], v)) then
				if fallback and fallback(j) then goto restart end
				return nil
			end
			table.insert(positions, j); j = j + 1
		end
	end
	dbg.log(3, "    collected positions:", table.concat(positions, ","))
	return positions
end

local function match_pattern(ts, m, r)
	local is_digit_action = r and r:match("^%d+$")
	for i = 1, #ts do
		if try_match_pattern(ts, pattern_tokens(m), i, replacement_tokens(r), nop) then
			dbg.log(1, "  Applying:", m, r)
			if is_digit_action then
				local positions = collect_positions(ts, pattern_tokens(m), i)
				if positions and #positions > 0 then
					reorder_tokens(ts, positions, r)
				end
			else
				try_match_pattern(ts, pattern_tokens(m), i, replacement_tokens(r), replace)
			end
			dbg.log(3, "    tokens after:",
			  table.concat(utils.map(ts, function(t)
			    return type(t) == 'string' and t:sub(1,1)..':'..utils.decode(t, true) or '?'
			  end), " | "))
		end
	end
end

local function loop(ts)
	-- strip space tokens that survive from tokenization; keep caps table in sync
	for i = #ts, 1, -1 do
		if ts[i] == ' ' then
			table.remove(ts, i)
			if ts.caps then table.remove(ts.caps, i) end
		end
	end
	-- convert h tag (historical/irregular past) to E for proper rule matching
	for i = 1, #ts do
		if ts[i]:byte(1) == string.byte('h') then
			dbg.log(2, "  h→E conversion:",
			  utils.decode(ts[i], true), "→ E" .. utils.decode(ts[i]:sub(2), true))
			ts[i] = 'E' .. ts[i]:sub(2)
		end
	end
	dbg.log(3, "Initial tokens:",
	  table.concat(utils.map(ts, function(t)
	    return (t:sub(1,1))..":"..utils.decode(t, true)
	  end), " | "))
	for ri, rs in ipairs(rules) do
		dbg.log(2, "Rule set T" .. ri .. ":")
		for _, r in ipairs(rs) do
			local _, pat, act = table.unpack(r)
			match_pattern(ts, pat, act or "")
		end
		dbg.log(3, "  After T" .. ri .. ":",
		  table.concat(utils.map(ts, function(t)
		    return t:sub(1,1)..":"..utils.decode(t, true)
		  end), " | "))
	end
	-- post-process: prefer X (copula) over U (modal) when followed by A (adjective) form
	for i = 1, #ts - 1 do
		if ts[i]:sub(1,1) == 'U' and ts[i+1]:find('A', 1, true) then
			local xform = find(ts[i], 'X')
			if xform then
				dbg.log(2, "  U→X post-process:",
				  utils.decode(ts[i], true), "→", utils.decode(xform, true))
				ts[i] = xform
			end
		end
	end
	-- strip any remaining space tokens (injected by rules); keep caps in sync
	for i = #ts, 1, -1 do
		if ts[i] == ' ' then
			table.remove(ts, i)
			if ts.caps then table.remove(ts.caps, i) end
		end
	end
end

function parser.collect(dic, ts)
	en_ru = dic
	loop(ts)
	-- W tokens (multi-word phrases like WAэлектронныйNперевод) survive rules but must
	-- be expanded into their constituent forms (Aэлектронный + Nперевод) before the
	-- compiler processes them. The gmatch skips the W prefix since 'W' is not followed
	-- by CP866 bytes, so the tag reverts to the first real tag letter after W.
	for i = #ts, 1, -1 do
		if ts[i]:sub(1,1) == 'W' then
			local was_caps = ts.caps and ts.caps[i]
			local expanded = {}
			for word in ts[i]:gmatch("([%a ][0-9]*[\127-\255]+)") do
				table.insert(expanded, word)
			end
			if #expanded > 0 then
				-- Remove the W token (and its caps entry), then insert expanded tokens.
				-- Expanded tokens inherit the W token's all-caps flag so that
				-- e.g. "AGREEMENT ON" (all-caps W phrase) → each sub-token is uppercase.
				table.remove(ts, i)
				if ts.caps then table.remove(ts.caps, i) end
				for j = #expanded, 1, -1 do
					table.insert(ts, i, expanded[j])
					if ts.caps then table.insert(ts.caps, i, was_caps) end
				end
			end
		end
	end
	dbg.log(1, "Tokens after rules:")
	for _, n in ipairs(ts) do
		if dbg.level >= 1 then
			echo(dbg.level >= 3 and 'magenta' or 'blue', "%s",
				type(n)=='table' and utils.debug(n) or utils.decode(n))
		end
	end
	return ts
end

return parser