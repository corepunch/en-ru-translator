local utils = require "core.utils"
local rules = require "core.rules"
local dbg = require "core.dbg"
local stream = require "core.token_stream"
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

-- Shared flag: set when X1 (past auxiliary "did/was/had") is consumed by ' ' action,
-- checked by the V action handler to propagate past tense to the resolved verb.
local x1_past_context = false
-- X1 copula + Z adjective: keep copula visible, resolve Z→A (not V)
local x1_copula_context = false
-- Y1 past perfect (had): propagate past tense (used by Y+been+G rule)
local y1_perfect_context = false

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
	for pos, w in t:gmatch("()(%a+[%d%$/;,. %-\127-\255]+)") do
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

local function matches(t, class)
	if not t then return nil end
	if #t == 1 and class:find(t, 1, true) then return t end
	return find(t, class)
end

-- tag_matches: pattern-matching check using ONLY the leading tag character.
-- Case-sensitive for non-W tokens: 'X' only matches Xnnn tokens, 'x' only matches xnn tokens.
-- For W-tokens (multi-word phrases), uses case-insensitive matching as before.
local function tag_matches(t, class, primary_tag)
	if not t then return nil end
	local ch = primary_tag or t:sub(1, 1)
	if ch == 'W' then
		-- W-tokens: case-insensitive match against any char in class
		local upper = t:upper()
		for i = 1, #class do
			if upper:find(class:sub(i,i), 1, true) then return t end
		end
		return nil
	end
	-- Non-W: case-sensitive check on leading character only
	if class:find(ch, 1, true) then return t end
	-- '*' in a character class matches sentence-end punctuation '.', '?', '!'
	if class:find('*', 1, true) and (ch == '.' or ch == '?' or ch == '!') then return t end
	return nil
end

local function find_and_replace(ts, j, s)
	local z = find(ts[j], 'Z')
	if z and string.find('VNA', s) then
		-- Ambiguity records are packed as ZV...N...A...; select the requested
		-- embedded tagged form instead of manufacturing a duplicate VV prefix.
		local pos = ts[j]:find(s, 2, true)
		if pos then
		  dbg.diag("tag", "Z→" .. s .. ":", utils.decode(ts[j], true), "→", utils.decode(ts[j]:sub(pos), true))
		  stream.set_token(ts, j, ts[j]:sub(pos)); return
		elseif s == 'V' then
		  -- Some Z records store the verb directly after Z and tag only secondary
		  -- noun/adjective forms (ZпоставлятьNпоставка).
		  stream.set_token(ts, j, 'V' .. ts[j]:sub(2)); return
		end
	end
	local f = find(ts[j], s)
	if f then
		dbg.diag("tag", "resolve:", utils.decode(ts[j], true), "→", utils.decode(f, true))
		stream.set_token(ts, j, f)
	-- fallback: if no exact form matches, search for the tag letter inside the token.
	-- For W tokens (multi-word phrases), skip this: sub-resolve would strip the W prefix
	-- and orphan trailing forms (e.g. WAэлектронныйNперевод → AэлектронныйNперевод, losing Nперевод).
	elseif #s == 1 and ts[j]:byte(1) == string.byte('G') and s == 'V' then
		stream.set_token(ts, j, 'V' .. ts[j]:sub(2))
	elseif #s == 1 and s == 'F' and ts[j]:byte(1) ~= string.byte('W') then
		-- Rule-generated F (e.g. `having`E → F): the token has no embedded F form,
		-- so retag the leading byte. The '9' digit marks the F as rule-converted:
		-- LTGOLD governs nominative objects after converted F but genitive objects
		-- after dictionary F (Завершаемый работа vs Видимый результата).
		dbg.diag("tag", "retag F (rule-generated):", utils.decode(ts[j], true))
		stream.set_token(ts, j, 'F9' .. ts[j]:sub(2))
	elseif #s == 1 and ts[j]:byte(1) ~= string.byte('W') then
		local _, e = ts[j]:find(s, 1, true)
		if e then
			dbg.diag("tag", "sub-resolve:", utils.decode(ts[j], true), "→", utils.decode(ts[j]:sub(e), true))
			stream.set_token(ts, j, ts[j]:sub(e))
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
				stream.set_token(ts, j, 'q')
			else
				if xdigit and xdigit:sub(1,1) == '1' then
					if ts[j + 1] and ts[j + 1]:sub(1,1) == 'G' then
						-- T2's X1+G progressive action deletes the auxiliary. Preserve its
						-- past-tense feature on the resolved lexical verb with the V~ marker.
						-- V~ (not V!) tells the compiler this is a progressive past (imperfective)
						-- so the perfective switch should NOT apply (e.g. was reading → читала, not прочитала).
						stream.set_token(ts, j + 1, 'V~' .. ts[j + 1]:sub(2))
					else
						-- X1 past auxiliary (did, was, had): scan forward to decide action.
						local k = j + 1
						while ts[k] and ts[k]:sub(1,1):match('[KkDdu]') do k = k + 1 end
						if ts[k] and ts[k]:sub(1,1) == 'Z' and ts[k]:find('A', 2, true) then
							-- X copula + Z adjective: keep X visible for copula output
							x1_copula_context = true
						else
							x1_past_context = true
						end
					end
				end
				-- Only remove X when it is truly auxiliary (not copula + adjective)
				if not x1_copula_context then stream.set_token(ts, j, ' ') end
			end
		else
			x1_past_context = false  -- reset on non-X delete
			-- Y1 (had) deleted by space action: set y1_perfect_context for the downstream G→V.
			if ts[j] and ts[j]:sub(1,1) == 'Y' then
				local ydigit = ts[j]:match('%d+')
				if ydigit and ydigit:sub(1,1) == '1' then y1_perfect_context = true end
			end
			stream.set_token(ts, j, ' ')
		end
	elseif m:find'*' and (j >= #ts or j == 1) then
	elseif t == 'literal' then stream.set_token(ts, j, s)
	elseif s == '.' or s == '$' then
	elseif s == '@' then find_and_replace(ts, j, m)
	elseif s == '^' then
		-- Preserve the structural separator for T6's N-N/NN patterns. The original
		-- action marks a join; it does not concatenate lexical token bytes here.
	elseif s == 'j' then
		stream.set_token(ts, j, 'j')  -- inject end-of-clause boundary marker
	elseif s == '|' then
		stream.set_token(ts, j, '|')  -- inject clause-boundary separator
	elseif s == '&' then
		-- coordination marker: look for C-form, else no-op
		find_and_replace(ts, j, 'C')
	elseif s == '1' and ts[j] and ts[j]:sub(1, 1):match('[Ee]') then
		-- Custom fallback action: mark an E/e form as resolved finite past without changing the behavior of LTGOLD's existing E-to-V rules.
		-- Use V! (not V1) to distinguish from dictionary-stored V1 tokens which are present-tense.
		stream.set_token(ts, j, 'V!' .. ts[j]:sub(2))
	elseif s == '#' then
		-- Literal `a` is initially an article; LTGOLD's boundary rule restores the
		-- original designator spelling (A) from the analyzer's source-token field.
		stream.set_token(ts, j, '#' .. ((ts.source and ts.source[j]) or ts[j]:sub(2)))
	elseif s == '=' or s == ';' then
		-- case-setting / clause-continuation: no-op until semantics are confirmed
	elseif s then
		-- When resolving an E/e token to V, preserve past-tense info as V!
		-- so the compiler conjugates as past tense (e.g. signed→подписал not подписывает).
		local was_past = ts[j] and ts[j]:sub(1, 1):match('[Ee]')
		-- E0 tokens (h-tag converted) must stay imperfective: flag before find_and_replace.
		local is_digit_b = function(b) return b and b >= string.byte('0') and b <= string.byte('9') end
		local was_e0 = was_past and ts[j] and
			ts[j]:byte(1) == string.byte('E') and
			ts[j]:byte(2) == string.byte('0') and
			not is_digit_b(ts[j]:byte(3))
		local is_v = (s == 'V')
		-- X1 copula (was/were) + Z with A form → resolve to adjective, not verb.
		-- find() packs Z/N/A into one iter entry; use direct string search instead.
		if is_v and (x1_past_context or x1_copula_context) and ts[j] and ts[j]:sub(1,1) == 'Z' and
		   ts[j]:find('A', 2, true) then
			dbg.log(2, "  X1 copula Z→A:", utils.decode(ts[j], true), "→ A")
			find_and_replace(ts, j, 'A')
			x1_past_context = false
			x1_copula_context = false
		else
			dbg.log(3, "  $V handler: was_past=", tostring(was_past), " x1=", tostring(x1_past_context), " is_v=", tostring(is_v), " tag=", ts[j] and ts[j]:sub(1,1))
			find_and_replace(ts, j, s)
			if is_v and (was_past or x1_past_context or y1_perfect_context) and ts[j] and ts[j]:sub(1, 1) == 'V' then
				-- V! for E/e past → perfective switch; V= for X1/Y1 simple past or E0 (h-tag) → no switch
				-- E0 (h-converted) tokens must stay imperfective (h means "use imperfective past directly").
				local marker = (was_past and not x1_past_context and not y1_perfect_context and not was_e0) and '!' or '='
				stream.set_token(ts, j, 'V' .. marker .. ts[j]:sub(2))
				x1_past_context = false
				y1_perfect_context = false
			end
		end
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
		if t == 'wildcard' then
			if xor(i, j == 1 or j > #ts) then eat('@', f())
			else return false end
		elseif not ts[j] then
			dbg.log(3, "    match fail: end of tokens at pos", j)
			return false
		elseif t == 'select' and xor(i, tag_matches(ts[j], v, ts.tag and ts.tag[j])) then
			j=replace(ts,j,v,f())
		elseif t == 'any' then
			local d = eat('$', f())
			fallback = function(n)
				-- '$' in pattern means universal capture: match any token in span
				local match = v == '$' or xor(i, tag_matches(ts[n], v, ts.tag and ts.tag[n]))
				if match then
					dbg.log(3, "    any-match consumed token", n, "tag", v)
					j = nop(ts,n,v,nil,d)
					return true
				end
			end
		elseif t == 'literal' and xor(i, ts[j] == (type(en_ru[v]) == 'table' and en_ru[v].__lex or en_ru[v])) then j=replace(ts,j,v,f())
		elseif t == 'char' and xor(i, tag_matches(ts[j], v, ts.tag and ts.tag[j])) then j=replace(ts,j,v,f())
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
	-- Snapshot complete entries; LTGOLD T5/T6 moves provenance with constituents.
	local snap = stream.snapshot(ts, positions)
	dbg.log(2, "    reorder: positions=", table.concat(positions,","),
	  "digits=", digits,
	  "snap=", table.concat(utils.map(snap, function(entry)
	    return utils.decode(entry.token, true)
	  end), ","))
	-- track which snap indices have been used
	local used = {}
	-- write back in digit-specified order
	for k = 1, #digits do
		local d = tonumber(digits:sub(k, k))
		if d and d >= 1 and d <= #snap and positions[k] then
			stream.write(ts, positions[k], snap[d])
			used[d] = true
		end
	end
	-- fill remaining positions with unused snap entries in order
	local next_snap = 1
	for k = #digits + 1, #positions do
		while used[next_snap] do next_snap = next_snap + 1 end
		if next_snap <= #snap and positions[k] then
			stream.write(ts, positions[k], snap[next_snap])
			used[next_snap] = true
			next_snap = next_snap + 1
		end
	end
	dbg.log(2, "    reorder result:",
	  table.concat(utils.map(positions, function(pos)
	    return utils.decode(ts[pos], true)
	  end), ","))
	for _, pos in ipairs(positions) do
		-- Hyphens consumed by a T5/T6 constituent reorder are structural and do not
		-- surface in Russian (buyer-seller agreement → соглашение продавца покупателя).
		if ts[pos] == '-' then stream.set_token(ts, pos, ' ') end
	end
end

-- collect_positions: dry-run that records which ts indices were consumed
local function collect_positions(ts, m, start)
	local positions = {}
	local fallback = nil
	local j = start
	for t, v, i in m do
		::restart::
		if t == 'wildcard' then
			if not xor(i, j==1 or j>#ts) then return nil end
			-- wildcard matches boundary, doesn't consume a token
		elseif not ts[j] then
			dbg.log(3, "    collect fail: end of tokens at", j)
			return nil
		elseif t == 'any' then
			fallback = function(n)
				local match = v == '$' or xor(i, tag_matches(ts[n], v, ts.tag and ts.tag[n]))
				if match then
					table.insert(positions, n)
					j = n + 1
					return true
				end
			end
		elseif t == 'select' then
			local matched = tag_matches(ts[j], v, ts.tag and ts.tag[j])
			if not xor(i, matched) then return nil end
			table.insert(positions, j); j = j + 1
		elseif t == 'literal' then
			if not xor(i, ts[j] == (type(en_ru[v]) == 'table' and en_ru[v].__lex or en_ru[v])) then return nil end
			table.insert(positions, j); j = j + 1
		elseif t == 'char' then
			if not xor(i, tag_matches(ts[j], v, ts.tag and ts.tag[j])) then
				if fallback and fallback(j) then goto restart end
				return nil
			end
			table.insert(positions, j); j = j + 1
		end
	end
	dbg.log(3, "    collected positions:", table.concat(positions, ","))
	return positions
end

-- T5/T6 use the filtered reorder matcher at 0x1313:0x7fd, not the standard
-- T1-T4/T7 matcher. Its patterns are flat tag sequences, so match the resolved
-- leading tag or the single head tag projected from a packed W entry.
local function collect_reorder_positions(ts, pattern, start)
	local positions, j = {}, start
	for i = 1, #pattern do
		local expected = pattern:sub(i, i)
		if not ts[j] then return nil end
		local actual = ts.tag and ts.tag[j] or ts[j]:sub(1, 1)
		if actual == 'W' then
			-- The binary's filtered view exposes the head of a packed dictionary
			-- phrase. Lua stores the whole phrase as WA...N..., whose final embedded
			-- constituent is the head used by the reorder tables.
			for tag in ts[j]:gmatch("([%a])[%d ]*[\127-\255]+") do actual = tag end
		end
		if actual ~= expected then return nil end
		table.insert(positions, j)
		j = j + 1
	end
	return positions
end

local function apply_reorder_rule(ts, pattern, action, flags)
	if not action or not action:match("^%d+$") then return end
	for i = 1, #ts do
		local positions = collect_reorder_positions(ts, pattern, i)
		if positions then
			dbg.log(1, "  Applying filtered reorder:", pattern, action)
			local verb_phrase = false
			for _, pos in ipairs(positions) do
				verb_phrase = verb_phrase or ts[pos]:match("^WV") ~= nil
			end
			-- Flag 0x02 identifies an already-formed W constituent head in T6.
			if not verb_phrase and flags ~= 0x02 then reorder_tokens(ts, positions, action) end
		end
	end
end

local function apply_reorder_table(ts, rs, table_number)
	dbg.log(2, "Rule set T" .. table_number .. " (filtered reorder):")
	for _, rule in ipairs(rs) do
		local flags, pattern, action = table.unpack(rule)
		apply_reorder_rule(ts, pattern, action, flags)
	end
end

-- T8's 0x1c3d:0x135 matcher operates on compact morph records rather than the
-- standard token structures. Lua has no second binary structure, so project the
-- resolved leading tags into an isolated stream and map matches back to tokens.
-- This preserves the separate matcher boundary and prevents lexical W payloads
-- or analyzer metadata from affecting T8 guard recognition.
local function match_morph_pattern(ts, pattern, flags, table_number)
	local morph = {}
	local source_positions = {}
	for i, token in ipairs(ts) do
		local tag = ts.tag and ts.tag[i] or token:sub(1, 1)
		if tag ~= 'q' then
			table.insert(morph, tag)
			table.insert(source_positions, i)
		end
	end
	for i = 1, #morph do
		if try_match_pattern(morph, pattern_tokens(pattern), i, replacement_tokens(""), nop) then
			local positions = collect_positions(morph, pattern_tokens(pattern), i)
			if positions and #positions > 0 then
				local head_pos = source_positions[positions[#positions]]
				local prev = ts.constituent_flags[head_pos]
				if not prev or (prev[1] or 0) <= table_number then
					ts.constituent_flags[head_pos] = { table_number, flags }
				end
			end
		end
	end
end

local function match_pattern(ts, m, r, flags, rule_set_idx)
	local is_digit_action = r and r:match("^%d+$")
	for i = 1, #ts do
		if try_match_pattern(ts, pattern_tokens(m), i, replacement_tokens(r), nop) then
			dbg.log(1, "  Applying:", m, r)
			if is_digit_action then
				local positions = collect_positions(ts, pattern_tokens(m), i)
				local verb_phrase = false
				for _, pos in ipairs(positions or {}) do
					-- W retains the first constituent tag immediately after its marker.
					verb_phrase = verb_phrase or ts[pos]:match("^WV") ~= nil
				end
				-- T6's 0x02 records annotate W-constituent heads. LTPRO preserves
				-- their surface order even when their digit action equals a reorder rule.
				local constituent_head = flags == 0x02
				if positions and #positions > 0 and not verb_phrase and not constituent_head then
					reorder_tokens(ts, positions, r)
			end
		elseif ts[j] and ts[j]:sub(1,1) == 'Y' then
			local ydigit = ts[j]:match('%d+')
			if ydigit and ydigit:sub(1,1) == '1' then y1_perfect_context = true end
			stream.set_token(ts, j, ' ')
		else
				-- Guard rules have no rewrite action but carry constituent-type flags.
				-- Store the flags on the LAST token of the matched span so the compiler
				-- can use them for case/agreement decisions.
				if flags and flags > 0 and (r == nil or r == "" or r == ".") then
					local positions = collect_positions(ts, pattern_tokens(m), i)
					if positions and #positions > 0 then
						local head_pos = positions[#positions]
						-- Store flag along with the rule-set index that set it.
						-- This lets action rules distinguish same-table guards (blocking)
						-- from earlier-table guards (non-blocking, different processing pass).
						local prev = ts.constituent_flags[head_pos]
						if not prev or (prev[1] or 0) <= (rule_set_idx or 0) then
							ts.constituent_flags[head_pos] = { rule_set_idx or 0, flags }
						end
						dbg.log(2, string.format("    flag 0x%02X (T%d) → token %d (%s)",
							flags, rule_set_idx or 0, head_pos, utils.decode(ts[head_pos], true)))
					end
				else
					-- Action rules: skip if the head was locked by a guard from the SAME table.
					-- Guards from earlier tables (e.g. T3 guard on a token, T4 action on it)
					-- should NOT block: each table is a separate rewriting pass.
					-- T7/T8 flags always block (they finalize constituent types for morphology).
					local positions = collect_positions(ts, pattern_tokens(m), i)
					local flag_entry = positions and #positions > 0 and ts.constituent_flags[positions[#positions]]
					local blocks = false
					if flag_entry then
						local setter_table = flag_entry[1] or 0
						local flag_val = flag_entry[2] or 0
						-- Same table or T7/T8 (finalization pass): block the action
						blocks = (setter_table == (rule_set_idx or 0)) or (setter_table >= 7)
					end
					if not blocks then
						try_match_pattern(ts, pattern_tokens(m), i, replacement_tokens(r), replace)
					else
						local flag_val = flag_entry and flag_entry[2] or 0
						dbg.log(2, string.format("    Skipped (constituent_flag 0x%02X from T%d on head): %s → %s",
							flag_val, flag_entry and flag_entry[1] or 0, m, r or ""))
					end
				end
			end
			dbg.log(3, "    tokens after:",
			  table.concat(utils.map(ts, function(t)
			    return type(t) == 'string' and t:sub(1,1)..':'..utils.decode(t, true) or '?'
			  end), " | "))
		end
	end
end

local function remove_silent_tokens(ts)
	-- Rule replacements use a literal space as deletion; removing it through the
	-- stream API keeps every analyzer metadata field aligned.
	for i = #ts, 1, -1 do
		if ts[i] == ' ' then stream.remove(ts, i) end
	end
end

local function normalize_analyzer_tags(ts)
	-- LTGOLD's historical/irregular-past analyzer tag (h) enters the grammar as E.
	-- We convert to E1 (already-resolved imperfective past) so the E printer skips
	-- the perfective aspect switch. This matches LTGOLD: "came" → приходил (imperf),
	-- not пришел (perf).
	for i = 1, #ts do
		if ts[i]:byte(1) == string.byte('h') then
			-- h without digit → E0 (parser-generated imperfective past, suppress switch).
			-- h1/h2 with digit → keep as E1/E2 (multi-digit, suppress switch, same as before).
			if ts[i]:match('^h%d') then
				dbg.log(2, "  h→E1 conversion:",
				  utils.decode(ts[i], true), "→ E1" .. utils.decode(ts[i]:sub(2), true))
				stream.set_token(ts, i, 'E1' .. ts[i]:sub(2))
			else
				dbg.log(2, "  h→E0 conversion:",
				  utils.decode(ts[i], true), "→ E0" .. utils.decode(ts[i]:sub(2), true))
				stream.set_token(ts, i, 'E0' .. ts[i]:sub(2))
			end
		end
	end
end

local function resolve_attributive_forms(ts)
	-- Resolve analyzer Z/N+A records before T2/T3 discard secondary forms.
	-- Skip I-tagged (numeral) tokens: their A-form is a declined case, not an attributive adjective.
	-- Numerals need to stay as I so printers.I can output the nominative form.
	for i = 1, #ts - 1 do
		if ts[i]:sub(1,1) == 'I' then goto continue end
		local has_adjective = find(ts[i], "A") or
		  (find(ts[i], "Z") and ts[i]:find("A", 2, true))
		if find(ts[i + 1], "NnZ") and has_adjective then
			find_and_replace(ts, i, "A")
		end
		::continue::
	end
end

local rule_set_preprocessors = {
	[1] = function(ts)
		-- T1 normalizes analyzer tag bytes before matching (LTPRO 0xe224-0xe2e6).
		-- The '?' rewrite is conditional on the analyzer's secondary '_' marker;
		-- source "_" is the only equivalent metadata retained by the Lua tokenizer.
		for i = 1, #ts do
			local tag = ts[i]:sub(1, 1)
			if tag == '[' or tag == ']' or tag == '<' or tag == '>' then
				stream.set_token(ts, i, '/' .. ts[i]:sub(2))
			elseif tag == '?' and ts.source and ts.source[i] == '_' then
				stream.set_token(ts, i, '_' .. ts[i]:sub(2))
			end
		end
		-- X003 (present copula "is/are") before Z with A-form → resolve Z to A
		for i = 1, #ts - 1 do
			if ts[i]:sub(1, 1) == 'X' and ts[i]:match("003") then
				local next_tok = ts[i + 1]
				if next_tok:byte(1) == string.byte('Z') and next_tok:find(string.char(65), 2, true) then
					find_and_replace(ts, i + 1, "A")
				end
			end
		end
	end,
	[3] = function(ts)
		for i = 1, #ts - 1 do
			if ts[i]:sub(1, 1) == 'q' and ts[i + 1]:sub(1, 1) == 'Z' then
				-- X2xx selects the following ambiguous Z as a verb before T3 cleanup.
				find_and_replace(ts, i + 1, 'V')
			end
		end
	end,
	[6] = function(ts)
		-- T6 validates heads after ambiguity rules, so expose adjective heads first.
		-- Skip I-tagged (numeral) tokens: their A-form is a declined case, not an attributive adjective.
		for i = 1, #ts - 1 do
			if ts[i]:sub(1,1) == 'I' then goto continue end
			if is(ts[i + 1], "Nn") and find(ts[i], "A") then
				find_and_replace(ts, i, "A")
			end
			::continue::
		end
	end,
}

local function apply_standard_table(ts, rs, table_number)
	if rule_set_preprocessors[table_number] then rule_set_preprocessors[table_number](ts) end
	dbg.log(2, "Rule set T" .. table_number .. ":")
	for _, rule in ipairs(rs) do
		local flags, pattern, action = table.unpack(rule)
		match_pattern(ts, pattern, action or "", flags, table_number)
	end
end

local function apply_rule_sets(ts)
	-- rules[7] is a Lua compatibility cleanup block and must not renumber the
	-- actual T7/T8 passes or accidentally participate in their guard semantics.
	for table_number = 1, 4 do apply_standard_table(ts, rules[table_number], table_number) end
	if rule_set_preprocessors[6] then rule_set_preprocessors[6](ts) end
	apply_reorder_table(ts, rules[5], 5)
	apply_reorder_table(ts, rules[6], 6)
	apply_standard_table(ts, rules[7], 0)
	apply_standard_table(ts, rules[8], 7)
	dbg.log(2, "Rule set T8 (morph projection):")
	for _, rule in ipairs(rules[9]) do
		local flags, pattern = table.unpack(rule)
		match_morph_pattern(ts, pattern, flags, 8)
	end
end

local preposition_contexts = {
	-- A demonstrative NP selects LTGOLD's locative sense of ambiguous "to".
	["PВна:O"] = utils.encode("PПв"),
}

local source_preposition_government = {
	-- LTGOLD's T7 PP frames distinguish lexical senses using the source verb.
	-- These entries are the decoded subset exercised by the compatibility corpus.
	at = { default = "PПна", look = "PВна" },
	from = { default = "PРиз" },
	about = { default = "PПо", it = "PПоб" },
}

local dative_transfer_verbs = {
	give = true, gave = true, hand = true, handed = true,
	show = true, showed = true, tell = true, told = true,
}

-- Motion verbs that use "в+acc" (movement into) rather than "на+acc" for "to" preposition.
local motion_into_verbs = {
	go = true, went = true, walk = true, walked = true, run = true, ran = true,
	come = true, came = true, move = true, moved = true, travel = true, traveled = true,
	fly = true, flew = true, drive = true, drove = true, ride = true, rode = true,
}

local function previous_source_word(ts, i)
	for j = i - 1, 1, -1 do
		local word = ts.source and ts.source[j]
		if word and word:match("^%a") then return word:lower() end
	end
end

local function preceding_transfer_verb(ts, i)
	for j = i - 1, 1, -1 do
		local word = ts.source and ts.source[j]
		if word and dative_transfer_verbs[word:lower()] then return word:lower() end
		if ts[j] and ts[j]:match("^[,;%.!?]") then return nil end
	end
end

local function resolve_post_rule_contexts(ts)
	-- Prefer X (copula) over U (modal) when followed by an adjective form.
	for i = 1, #ts - 1 do
		if ts[i]:sub(1,1) == 'U' and ts[i+1]:find('A', 1, true) then
			local xform = find(ts[i], 'X')
			if xform then
				dbg.log(2, "  U→X post-process:",
				  utils.decode(ts[i], true), "→", utils.decode(xform, true))
				stream.set_token(ts, i, xform)
			end
		end
	end
	for i = 1, #ts - 1 do
		local key = utils.decode(ts[i], false) .. ":" .. ts[i + 1]:sub(1, 1)
		if preposition_contexts[key] then stream.set_token(ts, i, preposition_contexts[key]) end
	end
	for i = 1, #ts do
		local source = ts.source and ts.source[i] and ts.source[i]:lower()
		local frame = source and source_preposition_government[source]
		if frame and ts[i]:match("^[Pp]") and
		   not (source == "from" and ts[i + 1] and ts[i + 1]:match("^[I#H]")) then
			local previous = previous_source_word(ts, i)
			local next_source = ts.source[i + 1] and ts.source[i + 1]:lower()
			local sense = (source == "at" and previous and previous:match("^look")) and "look"
			  or (next_source == "it" and "it") or "default"
			stream.set_token(ts, i, utils.encode(frame[sense] or frame.default))
		elseif source == "to" and ts[i]:match("^[Pp]") then
			local previous = preceding_transfer_verb(ts, i)
			if previous then
				-- A bare PД token carries dative government while suppressing the
				-- English preposition, as in "gave it to him" → "дал это ему".
				stream.set_token(ts, i, utils.encode("PД"))
			else
				-- Motion verb + "to" → "в + acc" (movement into enclosed space).
				local prev_src = previous_source_word(ts, i)
				if prev_src and motion_into_verbs[prev_src] then
					stream.set_token(ts, i, utils.encode("PВв"))
				end
			end
		end
	end
	for i = 1, #ts do
		if ts.source and ts.source[i] and ts.source[i]:lower() == "it" and
		   ts[i]:sub(1, 1) == "R" then
			-- Object "it" after a preposition: use demonstrative "это" (prepositional: этом).
			if i > 1 and ts[i-1] and ts[i-1]:sub(1,1) == 'P' then
				stream.set_token(ts, i, "O" .. utils.encode("это"))
			else
				-- Object "it" elsewhere: select demonstrative paradigm.
				stream.set_token(ts, i, "O" .. utils.encode("это"))
			end
		end
	end
end

local function loop(ts)
	remove_silent_tokens(ts)
	normalize_analyzer_tags(ts)
	dbg.log(3, "Initial tokens:",
	  table.concat(utils.map(ts, function(t)
	    return (t:sub(1,1))..":"..utils.decode(t, true)
	  end), " | "))
	resolve_attributive_forms(ts)
	apply_rule_sets(ts)
	resolve_post_rule_contexts(ts)
	remove_silent_tokens(ts)
end

 local function apply_copular_it_compatibility(ts)
 	if ts.source then
 		for i = 1, #ts - 1 do
 			if ts.source[i] and ts.source[i]:lower() == 'it' then
 				local subord = { ["that"]=true, ["which"]=true, ["who"]=true, ["whom"]=true, ["whose"]=true }
 				local prev_source = ts.source[i-1] and ts.source[i-1]:lower()
 				if i > 1 and subord[prev_source] then
 					-- "he knew that it was done": revert to R "он"
 					stream.set_token(ts, i, 'R031' .. utils.encode('он'))
 					goto continue
 				end
 				if ts[i]:sub(1, 1) == 'R' then
 					local j, future = i + 1, false
 					if ts[j] and ts[j]:sub(1, 1) == 'q' then future, j = true, j + 1 end
 					if ts[j] and ts[j]:sub(1, 1) == 'X' then
 						stream.set_token(ts, i, 'O' .. utils.encode('это'))
 						if future and ts.caps then ts.caps[j] = "init" end
 					end
 				end
 			end
 			::continue::
 		end
 	end
 end

  local function apply_capitalization_compatibility(ts)
  	if ts.caps then
  		for i = 2, #ts do
  			if ts[i - 1] == 'T' and ts.phrases and ts.phrases[i] then
  				-- LTPRO can leak article caps to a future auxiliary that immediately
  				-- follows the T+phrase, but only when no subject noun intervenes.
  				local j = i + 1
  				while ts[j] and ts[j]:sub(1, 1) == 'q' do j = j + 1 end
  				-- Skip: don't capitalize a copula/verb that follows a subject noun.
  				if ts[i]:match('^[Nn]') then goto continue end
  				if ts[j] and ts[j]:match('^[VX]') and not ts.caps[j] then ts.caps[j] = "init" end
  			end
  			-- LTPRO propagates caps from init-cap O pronoun (e.g. "It") to following copula X.
  			if ts[i - 1]:match('^O') and ts.caps[i - 1] == "init" then
  				if ts[i] and ts[i]:match('^X') and not ts.caps[i] then ts.caps[i] = "init" end
  			end
  			::continue::
  		end
  	end
  end

local function expand_phrase_tokens(ts)
	-- W tokens (multi-word phrases like WAэлектронныйNперевод) survive rules but must
	-- be expanded into their constituent forms (Aэлектронный + Nперевод) before the
	-- compiler processes them. The gmatch skips the W prefix since 'W' is not followed
	-- by CP866 bytes, so the tag reverts to the first real tag letter after W.
	--
	-- LTPRO morph engine type-12 propagates morphological flags (token+0x72, +0x77)
	-- from the head noun to all sibling sub-constituents within the W-phrase. We
	-- replicate this by storing the N sub-token's raw form in ts.context[i] so the
	-- compiler's adjective printer can inherit gender/case agreement.
	for i = #ts, 1, -1 do
			if ts[i]:sub(1,1) == 'W' then
				local metadata = stream.metadata(ts, i)
				local component_caps = metadata.component_caps
			local expanded = {}
			for word in ts[i]:gmatch("([%a ][0-9]*[\127-\255]+)") do
				table.insert(expanded, word)
			end
			if #expanded > 0 then
				-- Find the head noun (N-tagged sub-token) for context propagation.
				local head_noun = nil
				for _, word in ipairs(expanded) do
					if word:sub(1, 1) == 'N' then head_noun = word; break end
				end
				-- Remove the W token (and its caps entry), then insert expanded tokens.
				-- Expanded tokens inherit the W token's all-caps flag so that
				-- e.g. "AGREEMENT ON" (all-caps W phrase) → each sub-token is uppercase.
				stream.remove(ts, i)
				for j = #expanded, 1, -1 do
					local expanded_caps = type(component_caps) == 'table' and component_caps[j] or metadata.caps
					stream.insert(ts, i, expanded[j], {
						caps = expanded_caps,
						phrases = true,
						source = metadata.source,
						component_caps = false,
					})
				end
				-- Propagate head-noun context and constituent flags to all sub-tokens.
				-- LTPRO Type-10 copies +0x72 (context) and +0x77 (flags) from source
				-- to all destination sub-constituents; Type-12 copies +0x76 (constituent).
				if head_noun then
					for j = 0, #expanded - 1 do
						ts.context[i + j] = head_noun
					end
					-- Also propagate the head noun's constituent type from the W-token wrapper
					local ctype = ts.constituent_type and ts.constituent_type[i]
					if ctype then
						for j = 0, #expanded - 1 do
							ts.constituent_type[i + j] = ctype
						end
					end
				end
			end
		end
	end
end

function parser.collect(dic, ts)
	en_ru = dic
	-- Constituent-type flags from T7/T8 guard rules. Indexed by token
	-- position; stores the flags value so the compiler can use it for
	-- case/agreement decisions (PP=0x02, NP=0x06, VP=0x03, etc.).
	-- Reset T7/T8 annotations without dropping the per-node metadata array that
	-- must remain index-aligned through phrase expansion and token reordering.
	ts.constituent_flags = {}
	for i = 1, #ts do ts.constituent_flags[i] = false end
	loop(ts)
	-- These phases intentionally reproduce observable LTPRO output quirks after
	-- grammatical rules have stabilized, keeping them out of general semantics.
	apply_copular_it_compatibility(ts)
	apply_capitalization_compatibility(ts)
	-- Possessive reorder: N owner ' #0 N possessed → N possessed P(gen) N owner
	-- "director's report" → tokens [N report] [P Р] [N director]
	for i = 1, #ts - 3 do
		if ts[i] and ts[i]:sub(1,1) == 'N' and
		   ts[i+1] and ts[i+1]:sub(1,1) == "'" and
		   ts[i+2] and ts[i+2]:sub(1,1) == '#' and ts[i+2]:sub(2) == '0' and
		   ts[i+3] and ts[i+3]:sub(1,1) == 'N' then
			-- Swap: move possessed noun before possessor, insert P Р
			local owner = ts[i]
			local possessed = ts[i+3]
			ts[i] = possessed
			ts[i+1] = '\x50\x90'  -- P Р (genitive preposition)
			ts[i+2] = owner
			stream.set_token(ts, i+3, ' ')  -- mark as consumed (space outputs nothing)
		end
	end
	expand_phrase_tokens(ts)
	-- Propagate T7/T8 constituent flags to token metadata for compiler use.
	-- LTPRO morph engine types 10-14 read these from token+0x76.
	for i = 1, #ts do
		local entry = ts.constituent_flags and ts.constituent_flags[i]
		if entry and entry ~= false then
			ts.constituent_type[i] = entry[2]  -- the flags byte
		end
	end
	-- Relink indices after expand_phrase_tokens may have changed positions
	for i = 1, #ts do
		if ts.context and ts.context[i] and ts.context[i] ~= false then
			-- context was propagated by expand_phrase_tokens
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
