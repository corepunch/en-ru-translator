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

local function matches(t, class)
	if not t then return nil end
	if #t == 1 and class:find(t, 1, true) then return t end
	return find(t, class)
end

-- tag_matches: pattern-matching check using ONLY the leading tag character.
-- Case-sensitive for non-W tokens: 'X' only matches Xnnn tokens, 'x' only matches xnn tokens.
-- For W-tokens (multi-word phrases), uses case-insensitive matching as before.
local function tag_matches(t, class)
	if not t then return nil end
	if t:sub(1,1) == 'W' then
		-- W-tokens: case-insensitive match against any char in class
		local upper = t:upper()
		for i = 1, #class do
			if upper:find(class:sub(i,i), 1, true) then return t end
		end
		return nil
	end
	local ch = t:sub(1,1)
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
		  ts[j] = ts[j]:sub(pos); return
		elseif s == 'V' then
		  -- Some Z records store the verb directly after Z and tag only secondary
		  -- noun/adjective forms (ZпоставлятьNпоставка).
		  ts[j] = 'V' .. ts[j]:sub(2); return
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
		-- Preserve the structural separator for T6's N-N/NN patterns. The original
		-- action marks a join; it does not concatenate lexical token bytes here.
	elseif s == 'j' then
		ts[j] = 'j'  -- inject end-of-clause boundary marker
	elseif s == '|' then
		ts[j] = '|'  -- inject clause-boundary separator
	elseif s == '&' then
		-- coordination marker: look for C-form, else no-op
		find_and_replace(ts, j, 'C')
	elseif s == '1' and ts[j] and ts[j]:sub(1, 1):match('[Ee]') then
		-- Custom fallback action: mark an E/e form as resolved finite past without changing the behavior of LTGOLD's existing E-to-V rules.
		-- Use V! (not V1) to distinguish from dictionary-stored V1 tokens which are present-tense.
		ts[j] = 'V!' .. ts[j]:sub(2)
	elseif s == '#' then
		-- Literal `a` is initially an article; LTGOLD's boundary rule restores the
		-- original designator spelling (A) from the analyzer's source-token field.
		ts[j] = '#' .. ((ts.source and ts.source[j]) or ts[j]:sub(2))
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
		if t == 'wildcard' then
			if xor(i, j == 1 or j > #ts) then eat('@', f())
			else return false end
		elseif not ts[j] then
			dbg.log(3, "    match fail: end of tokens at pos", j)
			return false
		elseif t == 'select' and xor(i, tag_matches(ts[j],v)) then
			j=replace(ts,j,v,f())
		elseif t == 'any' then
			local d = eat('$', f())
			fallback = function(n)
				-- '$' in pattern means universal capture: match any token in span
				local match = v == '$' or xor(i, tag_matches(ts[n], v))
				if match then
					dbg.log(3, "    any-match consumed token", n, "tag", v)
					j = nop(ts,n,v,nil,d)
					return true
				end
			end
		elseif t == 'literal' and xor(i, ts[j] == (type(en_ru[v]) == 'table' and en_ru[v].__lex or en_ru[v])) then j=replace(ts,j,v,f())
		elseif t == 'char' and xor(i, tag_matches(ts[j], v)) then j=replace(ts,j,v,f())
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
		if ts[pos] == '-' then ts[pos] = ' ' end
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
				local match = v == '$' or xor(i, tag_matches(ts[n], v))
				if match then
					table.insert(positions, n)
					j = n + 1
					return true
				end
			end
		elseif t == 'select' then
			local matched = tag_matches(ts[j], v)
			if not xor(i, matched) then return nil end
			table.insert(positions, j); j = j + 1
		elseif t == 'literal' then
			if not xor(i, ts[j] == (type(en_ru[v]) == 'table' and en_ru[v].__lex or en_ru[v])) then return nil end
			table.insert(positions, j); j = j + 1
		elseif t == 'char' then
			if not xor(i, tag_matches(ts[j], v)) then
				if fallback and fallback(j) then goto restart end
				return nil
			end
			table.insert(positions, j); j = j + 1
		end
	end
	dbg.log(3, "    collected positions:", table.concat(positions, ","))
	return positions
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
			dbg.log(2, "  h→E1 conversion:",
			  utils.decode(ts[i], true), "→ E1" .. utils.decode(ts[i]:sub(2), true))
			ts[i] = 'E1' .. ts[i]:sub(2)
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
		for i = 1, #ts - 1 do
			if is(ts[i + 1], "Nn") and find(ts[i], "A") then
				find_and_replace(ts, i, "A")
			end
		end
	end,
}

local function apply_rule_sets(ts)
	for ri, rs in ipairs(rules) do
		if rule_set_preprocessors[ri] then rule_set_preprocessors[ri](ts) end
		dbg.log(2, "Rule set T" .. ri .. ":")
		for _, r in ipairs(rs) do
			local flags, pat, act = table.unpack(r)
			match_pattern(ts, pat, act or "", flags, ri)
		end
		dbg.log(3, "  After T" .. ri .. ":",
		  table.concat(utils.map(ts, function(t)
		    return t:sub(1,1)..":"..utils.decode(t, true)
		  end), " | "))
	end
end

local preposition_contexts = {
	-- A demonstrative NP selects LTGOLD's locative sense of ambiguous "to".
	["PВна:O"] = utils.encode("PПв"),
}

local function resolve_post_rule_contexts(ts)
	-- Prefer X (copula) over U (modal) when followed by an adjective form.
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
	for i = 1, #ts - 1 do
		local key = utils.decode(ts[i], false) .. ":" .. ts[i + 1]:sub(1, 1)
		if preposition_contexts[key] then ts[i] = preposition_contexts[key] end
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
			if ts.source[i] and ts.source[i]:lower() == 'it' and ts[i]:sub(1, 1) == 'R' then
				local j, future = i + 1, false
				if ts[j] and ts[j]:sub(1, 1) == 'q' then future, j = true, j + 1 end
				if ts[j] and ts[j]:sub(1, 1) == 'X' then
					-- LTGOLD resolves copular "it" as demonstrative это, not personal он.
					ts[i] = 'O' .. utils.encode('это')
					-- Intentional LTGOLD future-copula capitalization bug: "It will" emits Будет.
					if future and ts.caps then ts.caps[j] = "init" end
				end
			end
		end
	end
end

local function apply_capitalization_compatibility(ts)
	if ts.caps then
		for i = 2, #ts do
			if ts[i]:sub(1, 1) == 'W' and ts[i - 1] == 'T' and ts.caps[i - 1] then
				-- Intentional LTGOLD compatibility bug: a silent sentence-initial "The"
				-- leaks initial-capitalisation across consecutive W constituents and an
				-- immediately attached future predicate (Компенсация За; Позволит).
				local j = i
				while ts[j] and ts[j]:sub(1, 1) == 'W' do
					ts.caps[j] = "init"
					j = j + 1
				end
				while ts[j] and ts[j]:sub(1, 1) == 'q' do j = j + 1 end
				if ts[j] and ts[j]:match('^[VX]') then ts.caps[j] = "init" end
			end
		end
		for i = 2, #ts do
			if ts[i - 1] == 'T' and ts.phrases and ts.phrases[i] then
				local j = i + 1
				while ts[j] and ts[j]:sub(1, 1) == 'q' do j = j + 1 end
				if ts[j] and ts[j]:match('^[VX]') then ts.caps[j] = "init" end
			end
		end
	end
end

local function expand_phrase_tokens(ts)
	-- W tokens (multi-word phrases like WAэлектронныйNперевод) survive rules but must
	-- be expanded into their constituent forms (Aэлектронный + Nперевод) before the
	-- compiler processes them. The gmatch skips the W prefix since 'W' is not followed
	-- by CP866 bytes, so the tag reverts to the first real tag letter after W.
	for i = #ts, 1, -1 do
			if ts[i]:sub(1,1) == 'W' then
				local metadata = stream.metadata(ts, i)
				local component_caps = metadata.component_caps
			local expanded = {}
			for word in ts[i]:gmatch("([%a ][0-9]*[\127-\255]+)") do
				table.insert(expanded, word)
			end
			if #expanded > 0 then
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
			end
		end
	end
end

function parser.collect(dic, ts)
	en_ru = dic
	-- Constituent-type flags from T7/T8 guard rules. Indexed by token
	-- position; stores the flags value so the compiler can use it for
	-- case/agreement decisions (PP=0x02, NP=0x06, VP=0x03, etc.).
	ts.constituent_flags = {}
	loop(ts)
	-- These phases intentionally reproduce observable LTPRO output quirks after
	-- grammatical rules have stabilized, keeping them out of general semantics.
	apply_copular_it_compatibility(ts)
	apply_capitalization_compatibility(ts)
	expand_phrase_tokens(ts)
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
