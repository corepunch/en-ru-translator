local utils = require "utils"
local paradigms = require "paradigms"
local dbg = require "dbg"
local compiler = {}

-- utf8_upper: uppercase Cyrillic letters in a UTF-8 string.
-- Only affects Russian а-п (D0 B0-D0 BF) → А-П (D0 90-D0 9F)
-- and р-я (D1 80-D1 8F) → Р-Я (D0 A0-D0 AF). ASCII unchanged.
local function utf8_upper(s)
  return (s:gsub("[\xD0\xD1][\x80-\xBF]", function(c)
    local b1, b2 = c:byte(1), c:byte(2)
    if b1 == 0xD0 and b2 >= 0xB0 and b2 <= 0xBF then
      return string.char(0xD0, b2 - 0x20)  -- а-п → А-П
    elseif b1 == 0xD1 and b2 >= 0x80 and b2 <= 0x8F then
      return string.char(0xD0, b2 + 0x20)  -- р-я → Р-Я
    end
    return c
  end))
end

local uniques = {
  ["должен"] = {"но","ен","на","ны"},
}

local case = {
  ["И"]   = 1,   -- именительный ед.
  ["Р"]   = 2,   -- родительный ед.
  ["Д"]   = 3,   -- дательный ед.
  ["В"]   = 4,   -- винительный ед.
  ["Т"]   = 5,   -- творительный ед.
  ["П"]   = 6,   -- предложный ед.
}

-- LTGOLD verb dictionary frames select object case and whether an English
-- preposition has a Russian surface form. Extend this table as frames are decoded.
local verb_frames = {
  ["поставлять"] = { object_case = case["Д"], preposition = "на", emit = false },
  ["соглашаться"] = { next_infinitive = true },
  ["соответствовать"] = { object_case = case["Д"] },
  ["признавать"] = { complementizer = "что" },
  ["уполномочивать"] = { next_infinitive = true },
  ["позволять"] = { object_case = case["Д"] },
  ["делать"] = { causative = "заставлять" },
}

-- local u_endings = {
--   ["011"] = "ен",    -- I do
--   ["012"] = "ен",    -- you do (sg)
--   ["03"]  = "но",    -- he/she/it does
--   ["031"] = "ен",    -- he/she/it does
--   ["032"] = "на",    -- he/she/it does
--   ["11"]  = "ны",    -- we do
--   ["12"]  = "ны",    -- you do (pl)
--   ["13"]  = "ны",    -- they do
-- }

local function get_gender(s)
  local conf = compiler.base[utils.decode(s, true)]
  return conf and conf:byte(3)&3
end

-- find_form: extract the Russian text for a specific tag letter from a multi-form token
-- e.g. find_form("SэтоOэтотL, который", "L") → "который"
-- Uses byte-scanning because tokens are CP866-encoded (single-byte Russian chars).
-- Stops at the next ASCII letter (next tag), backslash (lemma separator), or punctuation.
local function find_form(token, tag)
  local i = token:find(tag, 1, true)
  if not i then return nil end
  local result = {}
  for j = i + 1, #token do
    local b = token:byte(j)
    -- stop at next tag letter, backslash (lemma), semicolon (alternate), or period
    if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 0x5C or b == 0x3B or b == 0x2E then break end
    result[#result+1] = token:sub(j, j)
  end
  return #result > 0 and table.concat(result) or nil
end

local function leading_alternatives(token)
  local leading, i = token:byte(1), 2
  while i <= #token and token:byte(i) >= 48 and token:byte(i) <= 57 do i = i + 1 end
  if token:byte(i) == leading then i = i + 1 end
  while i <= #token do
    local b = token:byte(i)
    if b == 0x3B then return utils.decode(token:sub(i + 1), false) end
    if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then return nil end
    i = i + 1
  end
end

local function find(s, n, t)
  for i = n, #s do
    if t:find(s[i]:sub(1,1), 1, true) then return s[i] end
  end
end

local function adj(a)
    local d = utils.decode(a:sub(1, #a-2), true)
    local b = compiler.base[d]
    if b then
      return (b:byte(2)==0x80 and b:byte(3) or b:byte(4))&~0x80
    else
      return paradigms.find_adjective(utils.decode(a))
    end
end

local function set(e, f, v) e[f] = v end

local function subject_is_plural(s, stop)
  for i = 1, stop - 1 do
    if s[i]:sub(1, 1) == 'C' and utils.decode(s[i]:sub(2), false) == "так и" then
      return true
    end
  end
  for i = 1, stop - 1 do
    local tag = s[i]:sub(1, 1)
    if tag == 'n' then return true end
    if tag == 'N' then return false end
    if tag == 'R' then return s[i]:match("^R1") ~= nil end
  end
end

local printers = {
	A = function(a, e, s, i)
		if s and s.phrases and s.phrases[i] then
			local has_phrase_noun = false
			local j = i + 1
			while s[j] and s.phrases[j] do
				has_phrase_noun = has_phrase_noun or s[j]:match('^[Nn]') ~= nil
				j = j + 1
			end
			if not has_phrase_noun then
				-- LTGOLD leaves the adjective head of a nounless fixed W phrase in
				-- dictionary form (утративший законную силу), even in accusative context.
				return utils.decode(a, true)
			end
		end
		local n = find(s, i, 'Nn')
    if n then
      e.gender = get_gender(n)
      e.plural = n:sub(1, 1) == 'n'
    end
    return paradigms.adjective(a, adj(utils.extract(a)), e)
  end,
  R = function(t, e)
    -- format: R<plural><person>[<gender>]<word>
    -- e.g. R032она (3 digits), R12Вы (2 digits without gender)
    local a, b, g = t:match("R(%d)(%d)(%d)")
    if not a then a, b = t:match("R(%d)(%d)") end
    e.plural = (a or '0') ~= '0'
    e.person = tonumber(b) or 3
    if g then e.gender = tonumber(g) end  -- 1=masc, 2=fem
    local result = utils.decode(t, true)
    if e.verb_frame and e.verb_frame.complementizer then
      result = ", " .. e.verb_frame.complementizer .. " " .. result
      e.verb_frame = nil
    end
    return result
  end,
  N = function(t, e, s, i)
    -- Uppercase N = singular noun. Reset the plural flag to prevent bleed from
    -- previous n (plural) tokens. LTGOLD tracks plurality per-constituent via
    -- T7/T8 rule flag constituent-type indices; this is a simpler approximation.
    if t:sub(1,1) == 'N' then e.plural = false end
    local d = utils.decode(t, true)
    local b = compiler.base[d]
    if not b then
      dbg.diag("multi", "noun no base:", d)
      return d
    end
    e.gender = get_gender(t)
    e.plural = e.plural and (b:byte(3)&0x4) == 0
    -- LTGOLD encodes genitive-modifier propagation in T2/T8 rule flags (constituent-type
    -- index bits). Without the flag mechanism, we approximate: N+N → second N is genitive.
    if i and i > 1 and s and s[i-1] and s[i-1]:sub(1,1) == 'N' then
      e.form = case["Р"]
      dbg.log(2, "    N genitive modifier:", d)
    end
    local paradigm = b:byte(4)&~0x80
    local result = paradigms.noun(t, paradigm, e)
    dbg.log(2, string.format("    N: word=%-12s paradigm=%-3d gender=%d form=%d => %s",
      d, paradigm, e.gender, e.form, utils.decode(result)))
    -- Multiple meanings: when the token contains a semicolon-separated alternative
    -- (e.g. NNобразец;выборка), append {N.alternative} just as LTGOLD does.
    -- LTGOLD tracks a per-sentence counter in its output formatter.
    local semi = t:find(';', 1, true)
    if semi then
      e.multi_count = (e.multi_count or 0) + 1
      -- Alternatives are separated by ASCII semicolons, so stripped decoding would
      -- stop after the first one; LTGOLD preserves the complete alternative list.
      local alt = utils.decode(t:sub(semi+1), false)
      if alt and #alt > 0 then
        result = result .. '{' .. e.multi_count .. '.' .. alt .. '}'
      end
      dbg.diag("multi", "multi-form noun:", utils.decode(t, false))
    end
    -- Don't reset e.form to accusative here — let the preposition's case (set by P printer)
    -- propagate through the entire noun chain.
    if e.verb_frame then e.verb_frame = nil end
    return result
  end,
  P = function(t, e)
    local second = utils.decode(t:sub(2, 2), true)
    local third = utils.decode(t:sub(3, 3), true)
    if case[third] then
      e.form = case[third]
      local result = utils.extract_form("P" .. t:sub(4))
      dbg.log(2, string.format("    P: case=%s form=%d", third, e.form))
      if e.verb_frame and result == e.verb_frame.preposition then
        e.form = e.verb_frame.object_case
        return e.verb_frame.emit and result or ""
      end
      return result
    elseif case[second] then
      e.form = case[second]
      local result = utils.extract_form("P" .. t:sub(3))
      dbg.log(2, string.format("    P: case=%s form=%d", second, e.form))
      if e.verb_frame and result == e.verb_frame.preposition then
        e.form = e.verb_frame.object_case
        return e.verb_frame.emit and result or ""
      end
      return result
    end
    -- Resolved p/J senses without a case letter retain the current government.
    return utils.decode(t:sub(2), true)
  end,
  Z = function(t, e, s, i)
    local d = utils.extract_form(t)
    if #d == 0 then
      -- leading tag has no Russian text, but secondary forms might have
      if #utils.decode(t, true) > 0 then return "" end
      return ""
    end
    e.form = case["В"]
    dbg.log(2, string.format("    Z start: word=%-12s infinitive=%s perfective=%s",
      d, tostring(e.infinitive), tostring(e.perfective)))
    -- After copula (e.infinitive=true), use short adjective form if available.
    -- LTGOLD handles this via verb paradigm table: copula 003 sets infinitive flag,
    -- and the Z printer reads the A-form's short adjective from the paradigm table.
    -- The if-chain here approximates that lookup without the full paradigm table.
    if e.infinitive and t:find('A', 1, true) then
      e.infinitive = false
      local apost = t:find('A', 1, true)
      if apost then
        local raw = t:sub(apost+1)
        local utf = utils.decode(raw, true)
        local stem = #utf > 4 and utf:sub(1, #utf-4) or utf
        -- find head (first) N token for gender agreement, skip genitive modifiers
        local gender = e.gender
        if s then
          for j = i and (i-1) or 0, 1, -1 do
            if s[j] and s[j]:sub(1,1) == 'N' and
               (j == 1 or not s[j-1] or s[j-1]:sub(1,1) ~= 'N') then
              gender = get_gender(s[j])
              break
            end
          end
        end
        local idx = e.plural and 4 or ((gender or 1) + 1)
        dbg.log(2, string.format("    Z copula+adj: stem=%-10s gender=%d idx=%d => %s",
          stem, gender, idx, stem .. paradigms.past_verb[idx]))
        return stem .. paradigms.past_verb[idx]
      end
    end
    if not e.perfective then
      e.perfective = (e.word == 1)
    end
    if e.word == 1 then e.imperative = true end
    -- LTGOLD emits the dictionary infinitive after a modal before consulting the
    -- aspect-pair slot; that slot may legitimately be empty (гарантировать).
    if e.infinitive then e.infinitive = false return d end
    if e.perfective and compiler.base[d] and (compiler.base[d]:byte(2)&2)~=2 then
      local paired = compiler.base[d]:sub(6)
      if #paired > 0 and paired:byte(1) >= 128 then
        t = paired
        d = utils.decode(t)
        dbg.log(2, string.format("    Z perfective switch: → %s", d))
      end
    end
    if not compiler.base[d] then return d end
    return paradigms.verb(t, compiler.base[d]:byte(4)&~0x80, e)
  end,
  U = function(t, e, s, i)
    local d = utils.decode(t, true)
    -- suppress modal when it was originally copula (X) followed by adjective.
    -- LTGOLD encodes this in T8 guard-rule flags: the constituent-type index for
    -- copula+adjective suppresses the modal output. Without flags, hardcode "должен".
    if d == "должен" and s and s[i+1] and s[i+1]:find('A', 1, true) then
      e.infinitive, e.perfective = true, true
      dbg.log(2, "    U suppressed (copula+adj context):", d)
      return ""
    end
    local u = uniques[d]
    e.infinitive, e.perfective = true, true
    dbg.log(2, string.format("    U: word=%-12s → infinitive=%s perfective=%s",
      d, tostring(e.infinitive), tostring(e.perfective)))
    if u then
      local _u = utils.extract(t)
      return utils.decode(_u:sub(1,#_u-2))..u[e.plural and 4 or (e.gender+1)]
    else
      -- fall back to regular verb paradigm (e.g. мочь → может)
      local b = compiler.base[d]
      if b then return paradigms.verb(t, b:byte(4)&~0x80, e) end
      return utils.decode(t, true)
    end
  end,
  T = function() return "" end,
  [" "] = function (t) return utils.decode(t, true) end,
  -- C: conjunction — decode full text after tag byte (no strip, preserves spaces)
  C = function (t) return utils.decode(t:sub(2), false) end,
  D = function (t) return utils.decode(t:sub(2), false) end,
  -- E/e: past participle / -ed form → produce past tense
  E = function(t, e, s, i)
    local d = utils.decode(t, true)
    local b = compiler.base[d]
    if not b then return d end
    e.past = true
    local previous = s and s[i - 1] and utils.decode(s[i - 1], true)
    local participle_context = {
      ["как"] = { passive = true, gender = 0, plural = false },
    }
    local context = participle_context[previous]
    local adjectival = s and s[i - 1] and s[i + 1] and
      s[i - 1]:sub(1, 1):match("[Nn]") and s[i + 1]:sub(1, 1) == 'P'
    if context then
      -- LTGOLD's JE/T8 constituent class selects the short passive participle.
      e.passive, e.gender, e.plural = context.passive, context.gender, context.plural
    elseif adjectival then
      -- A postnominal E before a prepositional phrase agrees with its head NP.
      e.passive = true
    end
    -- detect passive voice: E followed by PТ (instrumental case-marker "by").
    -- LTGOLD's T7/T8 guard-rule flags set a passive constituent-type index on the
    -- participle token, making this stream-scan unnecessary.
    if s and s[i+1] and s[i+1]:sub(1,1) == 'P' and #s[i+1] == 2 and s[i+1]:byte(2) == 0x92 then
      e.passive = true
      dbg.log(2, "    E passive context detected")
    end
    -- '1' flag after tag (e.g. E1видеть) means "is already a resolved past form",
    -- suppress perfective conversion (also skip in passive for reflexive form)
    if (e.passive or t:byte(2) ~= string.byte('1')) and b:byte(2)&2 ~= 2 then
      local pt = b:sub(6)
      if #pt > 0 and pt:byte(1) >= 128 then
        dbg.log(2, string.format("    E perfective switch: %s → %s", d, utils.decode(pt)))
        t = pt
        d = utils.decode(t)
      end
    end
    b = compiler.base[d]
    if not b then return d end
    dbg.log(2, string.format("    E: word=%-12s perf=%s pass=%s paradigm=%d",
      d, tostring(e.perfective), tostring(e.passive), b:byte(4)&~0x80))
    if e.passive then
      if adjectival then
        local full = paradigms.passive_participle(t, b:byte(4)&~0x80)
        local table_id = (paradigms.find_adjective(full) or 1) - 1
        e.passive = false
        return paradigms.adjective(utils.encode('A' .. full), table_id, e)
      end
      -- Verb paradigm position 13 stores LTGOLD's passive participle ending.
      local result = paradigms.verb(t, b:byte(4)&~0x80, e)
      e.passive = false
      return result
    end
    return paradigms.verb(t, b:byte(4)&~0x80, e)
  end,
}

-- S: demonstrative pronoun (adjective form) — use adjective declension if possible, else decode
printers.S = function(t, e)
  local all = find_form(t, 'O')
  if all and utils.decode(all, true) == "весь" then
    local forms = { "все", "всех", "всем", "все", "всеми", "всех" }
    e.plural = true
    return forms[e.form or 1]
  end
  local ok, res = pcall(printers.A, t, e)
  if ok and res and #res > 0 then return res end
  return utils.decode(t, true)
end
printers.V = function(t, e, s, i)
  if e.verb_frame and e.verb_frame.next_infinitive then
    e.infinitive = true
    e.verb_frame = nil
  elseif s and i then
    local plural = subject_is_plural(s, i)
    if plural ~= nil then e.plural = plural end
  end
  if e.passive then
    local passive_frame = verb_frames[utils.extract_form(t)]
    local d = utils.extract_form(t)
    local b = compiler.base[d]
    if b and b:byte(2)&2 ~= 2 then
      t = b:sub(6)
      d = utils.decode(t)
      b = compiler.base[d]
    end
    if b then
      e.past = true
      local result = paradigms.verb(t, b:byte(4)&~0x80, e)
      e.passive = false
      e.past = false
      e.verb_frame = passive_frame or verb_frames[utils.extract_form(t)] or verb_frames[d]
      return result
    end
  end
  local result = printers.Z(t, e, s, i)
  e.verb_frame = verb_frames[utils.extract_form(t)]
  if e.verb_frame and e.verb_frame.object_case and not e.verb_frame.preposition then
    e.form = e.verb_frame.object_case
  end
  return result
end
printers.G = function(t, e, s, i)
  local frame = verb_frames[utils.extract_form(t)]
  if frame and frame.causative and s and i and s[i + 1] and s[i + 1]:match('^[Mm]') then
    local b = compiler.base[frame.causative]
    if b then
      e.form = case["В"]
      local base = "G" .. utils.encode(frame.causative)
      return paradigms.gerund(base, b:byte(4)&~0x80, (b:byte(2)&2) == 0)
    end
  end
  -- G→N fallback: after a preposition (e.form ~= 1), gerund forms like "testing"
  -- should output as nouns ("испытания") rather than verbals ("тестировать").
  -- Check if the token has an embedded N form; if so, use the noun printer instead.
  if e.form ~= 1 and t:find('N', 1, true) then
    local nform = find_form(t, 'N')
    if nform then
      dbg.log(2, "    G→N fallback: using noun form for case", e.form)
      return printers.N('N' .. nform, e)
    end
  end
  return printers.Z(t, e)
end
printers.e = printers.E
-- Lowercase resolved tags — decode first available form
printers.n = function(t, e) e.plural = true return printers.N(t, e) end
printers.g = function(t, e)
  local d = utils.extract_form(t)
  local b = compiler.base[d]
  if not b then return d end
  e.form = case["В"]
  return paradigms.gerund(t, b:byte(4)&~0x80, (b:byte(2)&2) == 0)
end
printers.v = function(t, e) return printers.V(t, e) end
printers.p = function(t, e) return printers.P(t, e) end
printers.f = function(t) return utils.decode(t, true) end
-- J (subordinating conjunction), L (relative pronoun), j (clause-end marker), O (demonstrative)
-- These are structural/functional words — output their Russian text directly
printers.J = function(t) return utils.decode(t, true) end
-- z: -s/-es form (verb/noun ambiguity). After prepositions prefer noun form.
-- LTGOLD resolves z via T2/T3 constituent-type rules; this is a fallback.
printers.z = function(t, e, s, i)
  if e.form ~= 1 and t:find('n', 1, true) then
    local nform = find_form(t, 'n')
    if nform then return printers.n('n' .. nform, e) end
  end
  return printers.V(t, e)
end
-- q: future/perfective aspect marker injected by the X2xx auxiliary handler.
-- Sets e.perfective so the following verb conjugates as perfective (future in Russian).
-- LTGOLD encodes this in T7/T8 guard-rule constituent-type flags.
printers.q = function(t, e)
  e.perfective = true
  dbg.log(2, "    q: perfective=true (future auxiliary)")
  return ""
end
printers.L = function(t, e, s, i)
  -- strip the leading tag byte, keep leading comma+space
  local result = utils.decode(t:sub(2), false)
  local gender = nil
  if s then
    for j = (i and i-1 or 0), 1, -1 do
      if s[j] and s[j]:sub(1,1) == 'N' and
         (j == 1 or not s[j-1] or s[j-1]:sub(1,1) ~= 'N') then
        gender = get_gender(s[j])
        break
      end
    end
  end
  if gender == 2 then
    result = result:gsub("который", "которую")
  end
  return result
end
printers.j = function(t) return "" end  -- clause-end marker is silent
printers.O = function(t, e, s, i)
  local d = utils.decode(t, true)
  if d == "весь" then return printers.S(t, e) end
  -- Hardcoded demonstrative pronoun forms. LTGOLD stores these in the Russian paradigm
  -- tables (BASE.RUS) indexed by paradigm number. A table lookup over this if-chain
  -- would match LTGOLD's approach and generalize to other demonstratives.
  if d == "этот" then
    local noun_gender, noun_plural = e.gender, false
    if s then
      for j = i and (i+1) or 1, #s do
        local tag = s[j] and s[j]:sub(1,1)
        if tag == 'N' then
          noun_gender = get_gender(s[j])
          -- uppercase N = singular; lowercase n = plural
          noun_plural = false
          break
        elseif tag == 'n' then
          noun_gender = get_gender(s[j])
          noun_plural = true
          break
        end
      end
    end
    -- Full case declension for "этот". LTGOLD uses a paradigm table; this approximates it.
    -- Indices: [form][1=masc, 2=fem, 3=neut, 4=plural]
    local forms = {
      [1] = {"этот","эта","это","эти"},       -- nominative
      [2] = {"этого","этой","этого","этих"},  -- genitive
      [3] = {"этому","этой","этому","этим"},  -- dative
      [4] = {"этот","эту","это","эти"},       -- accusative (inanimate)
      [5] = {"этим","этой","этим","этими"},   -- instrumental
      [6] = {"этом","этой","этом","этих"},    -- prepositional
    }
    local f = forms[e.form or 1] or forms[1]
    local idx = noun_plural and 4 or (noun_gender == 2 and 2 or noun_gender == 0 and 3 or 1)
    return f[idx]
  end
  local ok, res = pcall(printers.A, t, e)
  if ok and res then return res end
  return d
end
printers.l = printers.L
printers.s = printers.S
-- h (history/alternate form marker) — treat as past tense like E
  printers.h = function(t, e)
    local d = utils.decode(t, true)
    local b = compiler.base[d]
    if not b then return d end
    e.past = true
    if t:byte(2) ~= string.byte('1') and b:byte(2)&2 ~= 2 then
      local pt = b:sub(6)
      if #pt > 0 and pt:byte(1) >= 128 then
        dbg.log(2, string.format("    h perfective switch: %s → %s", d, utils.decode(pt)))
        t = pt
        d = utils.decode(t)
      end
    end
  b = compiler.base[d]
  if not b then return d end
  return paradigms.verb(t, b:byte(4)&~0x80, e)
end
-- Q (question word), M (indirect pronoun), m (compound pronoun), r (compound personal)
printers.Q = function(t) return utils.decode(t, true) end
printers.M = function(t, e)
  local plural, person, gender = t:match("M(%d)(%d)(%d)")
  if not plural then plural, person = t:match("M(%d)(%d)") end
  if plural then
    return paradigms.pronoun(plural ~= '0', tonumber(person) or 3,
      tonumber(gender) or e.gender, e.form)
  end
  return utils.decode(t, true)
end
printers.m = function(t) return utils.decode(t, true) end
printers.r = function(t) return utils.decode(t, true) end
-- k (negative 'no'), K (negative 'not')
printers.K = function(t) return utils.decode(t, true) end
printers.k = function(t) return utils.decode(t, true) end
-- x (impersonal/there-is), y (have existential), i (indefinite article form)
printers.x = function(t) return utils.decode(t, true) end
printers.y = function(t) return utils.decode(t, true) end
printers.i = function(t) return utils.decode(t, true) end
printers.u = function(t) return utils.decode(t, true) end
-- b/B (infinitive particle 'to') — suppress in output
printers.B = function(t) return "" end
printers.b = function(t) return "" end
-- W (multi-word phrase) — output decoded
printers.W = function(t) return utils.decode(t, true) end
-- # (proper noun / untranslatable): output raw string, reformat digit-only sequences
-- back to comma-formatted numbers (e.g. 1000000 → 1,000,000) since tokenize strips commas.
printers["#"] = function(t, e)
  local s = t:sub(2)
  if s:match("^%d+$") then
    -- Match LTGOLD's intentionally simplified numeral agreement: 2-4 select
    -- nominative plural, while 0/5-9 and the teens select genitive plural.
    local last_two = tonumber(s:sub(-2)) or 0
    local last = tonumber(s:sub(-1)) or 0
    e.form = ((last_two >= 11 and last_two <= 20) or last == 0 or last >= 5)
      and case["Р"] or case["И"]
    if #s > 3 then return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
    return s
  end
  return s
end
printers.F = function(t, e)
  e.past = true
  e.passive = true
  e.perfective = true
  dbg.log(2, string.format("    F: perfective=%s passive=%s",
    tostring(e.perfective), tostring(e.passive)))
  return printers.Z(t, e)
end
printers.X = function(t, e, s, i)
  if s and i then
    local j = i + 1
    while s[j] and s[j]:sub(1, 1) == 'D' do j = j + 1 end
    if s[j] and s[j]:sub(1, 1) == 'V' then
      -- Copula + derived V constituent is LTGOLD's short passive construction.
      e.passive = true
      return ""
    end
  end
  if t:match("%d+") == "003" then
    e.infinitive = true
    e.form = case["И"]
    dbg.log(2, "    X (copula 003): infinitive=true, form=nom")
    if s and s[i+1] and s[i+1]:match("A[\128-\255]") then return "" end
    return "-"
  else
    local p = printers.V(t, e)
    e.infinitive = true
    local j = i and (i + 1) or nil
    while j and s and s[j] and s[j]:sub(1, 1) == 'T' do j = j + 1 end
    if j and s[j] and s[j]:sub(1, 1) == 'N' then
      -- LTGOLD uses instrumental for nominal predicates of overt past/future
      -- copulas (будет заменой), while its suppressed present copula stays nominative.
      e.form = case["Т"]
    end
    dbg.log(2, "    X (other): infinitive=true")
    return p
  end
end

local function new_context()
  return {
    plural = false,
    gender = 1,
    person = 3,
    form = 1,
    perfective = false,
    imperative = false,
    word = 1,
    multi_count = 0,  -- counter for multiple-meanings markup {N.alternative}
  }
end

local function reset_clause_context(e)
  -- LTPRO punctuation closes transient verb/aspect government but preserves
  -- subject features until a later constituent replaces them.
  e.past, e.passive, e.imperative = false, false, false
  e.perfective, e.infinitive = false, false
  e.form = case["И"]
end

local function apply_source_caps(out, caps)
  if not out or #out == 0 or not caps then return out end
  local main, rest = out:match("^([^{]*)(.*)")
  main, rest = main or out, rest or ""
  if caps == true then return utf8_upper(main) .. rest end
  return main:gsub("^([\xD0\xD1][\x80-\xBF])", function(c)
    return utf8_upper(c)
  end, 1) .. rest
end

local function append_alternatives(out, token, e)
  if not out or #out == 0 or out:find('{', 1, true) then return out end
  local alternatives = leading_alternatives(token)
  if not alternatives or #alternatives == 0 then return out end
  e.multi_count = (e.multi_count or 0) + 1
  return out .. '{' .. e.multi_count .. '.' .. alternatives .. '}'
end

local function render_token(token, e, stream_tokens, index)
  local tag = token:sub(1, 1)
  local ok, result = pcall(printers[tag], token, e, stream_tokens, index)
  if not ok then
    dbg.diag("word", "unknown tag:", tag, "in token:", utils.decode(token, false))
  end
  return tag, ok, ok and result or utils.decode(token, true), result
end

function compiler.compile(s)
  local e = new_context()
  local c = {}
  local quote_open = false

  dbg.log(1, "Compiler output:")
  dbg.log(2, "Initial context:",
    string.format("{gender=%d person=%d form=%d perfective=%s}",
      e.gender, e.person, e.form, tostring(e.perfective)))

  -- for i, w in ipairs(s) do print(utils.decode(w)) end

  for i, w in ipairs(s) do
    if #w == 1 and w:match"[,%!%.;:]" then
      if #c > 0 then c[#c] = c[#c]..w
      else table.insert(c, w) end
      if w == ',' or w == ';' then reset_clause_context(e) end
    else
      local tag, ok, out, err = render_token(w, e, s, i)
      -- handle leading punctuation in output (e.g. relative pronoun ", которую")
      if out and out:match("^[,%!%.;:]") and #c > 0 then
        c[#c] = c[#c] .. out:sub(1,1)
        out = out:sub(2):match("^%s*(.*)") or ""
      end
      -- uppercase output when the source word was all-caps (e.g. AGREEMENT → СОГЛАШЕНИЕ).
      -- Only the main Russian word is uppercased; the {N.alt} alternatives part is left as-is.
      -- caps == true  → ALL-CAPS output  (source word was e.g. "AGREEMENT")
      -- caps == "init"→ Initial-cap only (source word was e.g. "Metric" or "Fish")
      -- LTGOLD tracks this via its input word capitalisation flags.
      out = apply_source_caps(out, s.caps and s.caps[i])
      out = append_alternatives(out, w, e)
      dbg.log(1, string.format("  [%d] tag=%-2s token=%-30s => %-25s  e={inf=%s perf=%s plur=%s form=%s}",
        i, tag, utils.decode(w):sub(1,30), utils.decode(out or ''),
        tostring(e.infinitive), tostring(e.perfective), tostring(e.plural), tostring(e.form)))
      if not ok then dbg.log(1, "    ERROR: "..tostring(err)) end
      if tag == '-' and out then out = "\1" .. out end
      if tag == '"' and out then
        out = (quote_open and "\3" or "\2") .. out
        quote_open = not quote_open
      end
      if out and #out > 0 then table.insert(c, out:find('#') and out:sub(2) or out) end
      e.word = e.word + 1
    end
  end
  -- LTGOLD follows the first source token's capitalization; lowercase source
  -- fragments remain lowercase, while a silent initial "The" still capitalizes output.
  if #c > 0 and s.caps and s.caps[1] then
    local first = c[1]
    -- find first Cyrillic/Latin char and uppercase it
    c[1] = first:gsub("^([\xD0\xD1])([\x80-\xBF])", function(b1, b2)
      -- UTF-8 Cyrillic: uppercase range is U+0410-U+042F (д0 90-д0 АФ) for А-Я
      -- lowercase а-п: D0 B0-D0 BF  р-я: D1 80-D1 8F
      local cp = (b1:byte() == 0xD0 and b2:byte() - 0x80 or b2:byte() - 0x80 + 0x40) + 0x400
      if cp >= 0x430 and cp <= 0x44F then  -- а-я: subtract 0x20
        local uc = cp - 0x20
        local ub1 = 0xD0 + (uc - 0x400 >= 0x40 and 1 or 0)
        local ub2 = (uc - 0x400) % 0x40 + 0x80
        return string.char(ub1, ub2)
      end
      return b1..b2
    end, 1)
  end
  print("")
  -- Only unmatched source hyphens are prefix joiners (A-B → -B); generated
  -- copular dashes retain their surrounding spaces.
  local result = table.concat(c, " "):gsub("\1%- ", "-"):gsub("\1", "")
  result = result:gsub("\2\"%s*", '"'):gsub("%s*\3\"", '"'):gsub("[\2\3]", "")
  print(result)
  print("")
  return result
end

-- print(
  --   table.concat({
  --     noun(s.subject.noun, table.unpack(s.subject)),
  --     verb(s.verb.verb, read_transform(s.subject.noun), s.verb.secondary),
  --     noun(s.object.noun, table.unpack(s.object))}, 
  --   " "))

return compiler
