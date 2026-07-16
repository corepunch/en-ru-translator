local utils = require "core.utils"
local paradigms = require "core.paradigms"
local dbg = require "core.dbg"
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
  ["доставлять"] = { object_case = case["Д"], preposition = "на", emit = false },
  ["соглашаться"] = { next_infinitive = true },
  ["соответствовать"] = { object_case = case["Д"] },
  ["признавать"] = { complementizer = "что" },
  ["уполномочивать"] = { next_infinitive = true },
  ["позволять"] = { object_case = case["Д"] },
  ["делать"] = { causative = "заставлять" },
  ["устанавливать"] = { object_case = case["В"], preposition = "на", emit = true },
  ["читать"] = { object_case = case["В"] },
  ["возвращать"] = { object_case = case["В"] },
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
  -- Packed analyzer records may prefix the first surface with several tags
  -- (EVподписывать, NNписьмо); skip that tag run before scanning its text.
  while i <= #token and ((token:byte(i) >= 65 and token:byte(i) <= 90) or
    (token:byte(i) >= 97 and token:byte(i) <= 122)) do i = i + 1 end
  while i <= #token do
    local b = token:byte(i)
    if b == 0x3B then
      local tail = token:sub(i + 1)
      local inf_prefix = utils.encode("инф)")
      if tail:sub(1, #inf_prefix) == inf_prefix then tail = tail:sub(#inf_prefix + 1) end
      local secondary_inf = tail:find(";" .. inf_prefix, 1, true)
      if secondary_inf then tail = tail:sub(1, secondary_inf - 1) end
      local stop = #tail + 1
      for j = 1, #tail do
        local c = tail:byte(j)
        if c == 0x5C or (((c >= 65 and c <= 90) or (c >= 97 and c <= 122)) and
           tail:byte(j + 1) and tail:byte(j + 1) >= 0x7F) then
          stop = (j > 1 and tail:byte(j - 1) == 0x3B) and (j - 1) or j
          break
        end
      end
      -- Alternative text ends before the next packed grammatical form or lemma
      -- back-reference; semicolon-separated alternatives remain intact.
      return utils.decode(tail:sub(1, stop - 1), false)
    end
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
      local decoded = utils.decode(a)
      local idx = paradigms.find_adjective(decoded)
      -- Reflexive participle adjectives end in CP866 -ся (0xE1 0xEF, e.g. движущийся).
      -- Strip -ся for paradigm lookup; the caller must append "ся" to the result.
      local reflexive = false
      if not idx and #a >= 4 and a:byte(#a-1) == 0xE1 and a:byte(#a) == 0xEF then
        local stripped = a:sub(1, #a-2)
        idx = paradigms.find_adjective(utils.decode(stripped))
        if idx then
          a = stripped
          reflexive = true
        end
      end
      -- find_adjective() returns a 1-based match index; convert to the
      -- 0-based paradigm table_id expected by paradigms.adjective().
      return (idx or 1) - 1, a, reflexive
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
    if e.numeral then
      -- T7 numeral-NP constituent metadata supplies a separate agreement state
      -- for modifiers; it must not leak into the following predicate.
      e.form = e.numeral.adjective_form
      e.plural = e.numeral.adjective_plural
    local n = find(s, i, 'Nn')
    -- W-phrase flag propagation: when the adjective is a sub-constituent of an
    -- expanded W-token, s.context[i] holds the head noun's raw CP866 form
    -- (mirrors LTPRO morph-engine type-12 +0x72 propagation).
    if not n and s.context and s.context[i] and s.context[i] ~= false then
      n = s.context[i]
    end
      if n then e.gender = get_gender(n) or e.gender end
      local adj_id, adj_base, adj_refl = adj(utils.extract(a))
      local result = paradigms.adjective(adj_base or a, adj_id, e)
      return adj_refl and (result .. "ся") or result
    end
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
    -- Predicative short form: after present copula X003 only (e.infinitive=true AND nominative form).
    -- X1xx/X2xx also set e.infinitive but e.form=Т (instrumental) → use full adj form instead.
    -- Subject noun precedes the copula, so search backward for it.
    if e.infinitive and e.form == case["И"] then
      e.infinitive = false
      local utf = utils.decode(utils.extract(a), true)
      local stem = #utf > 4 and utf:sub(1, #utf - 4) or utf
      local gender = e.gender
      if s then
        -- Start search from before the copula (skip X/V/U/Y auxiliaries going backward)
        local start = (i or 0) - 1
        while start >= 1 and s[start] and s[start]:sub(1,1):match('[XVUYxy]') do
          start = start - 1
        end
        for j = start, 1, -1 do
          -- Subject noun: skip N tokens that are genitive modifiers (preceded by another N)
           if s[j] and s[j]:sub(1,1):match('[Nn]') and
              (j == 1 or not s[j-1] or s[j-1]:sub(1,1) ~= 'N') then
             gender = get_gender(s[j]) or gender  -- fallback if not in RUS
             e.plural = s[j]:sub(1,1) == 'n'
            break
          end
        end
      end
      local short_endings = { [1]="", [2]="а", [3]="о", [4]="ы" }
      local idx = e.plural and 4 or ({[0]=3,[1]=1,[2]=2})[gender or 1]
      return stem .. (short_endings[idx] or "")
    end
    local n = find(s, i, 'Nn')
    if not n and s.context and s.context[i] and s.context[i] ~= false then
      n = s.context[i]
    end
    -- Predicative adjective after copula: noun is before X/V, not after.
    -- Scan backward past auxiliaries to find the subject noun for agreement.
    if not n then
      for j = (i or 0) - 1, 1, -1 do
        if s[j] and s[j]:sub(1,1):match('[Nn]') and
           (j == 1 or not s[j-1] or s[j-1]:sub(1,1) ~= 'N') then
          n = s[j]; break
        elseif s[j] and s[j]:sub(1,1):match('[XVUYxy]') then
          -- skip copula/aux verbs, continue scanning
        else break end
      end
    end
    if n then
      e.gender = get_gender(n) or e.gender  -- fallback to default if not in RUS
      local plural_only = { ["люди"]=true, ["дети"]=true, ["часы"]=true,
        ["ножницы"]=true, ["брюки"]=true, ["ворота"]=true, ["сани"]=true }
      local ntext = utils.decode(n, true)
      e.plural = n:sub(1, 1) == 'n' or plural_only[ntext]
    end
    -- Dative subject: "need" construction (X needs Y → X-dat нужен Y-nom)
    if s and s.dative_subject and s.dative_subject[i] then
      e.form = case["Д"]
    end
    local adj_id, adj_base, adj_refl = adj(utils.extract(a))
    local result = paradigms.adjective(adj_base or a, adj_id, e)
    -- Reflexive participle adjectives: append -ся to the fully declined form.
    return adj_refl and (result .. "ся") or result
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
    -- A new overt subject closes a modal's coordinated-verb scope.
    e.modal_scope = nil
    if e.verb_frame and e.verb_frame.complementizer then
      result = ", " .. e.verb_frame.complementizer .. " " .. result
      e.verb_frame = nil
    end
    return result
  end,
   N = function(t, e, s, i)
     if e.modal_scope and e.modal_scope.consumed then e.modal_scope = nil end
     if e.numeral then
       e.form = e.numeral.noun_form
       e.plural = e.numeral.noun_plural
     elseif t:sub(1,1) == 'N' then
       local plural_only = { ["люди"]=true, ["дети"]=true, ["часы"]=true,
         ["ножницы"]=true, ["брюки"]=true, ["ворота"]=true, ["сани"]=true }
       local ntext = utils.decode(t, true)
       if not plural_only[ntext] then e.plural = false end
     end
     -- Dative subject: "need" construction (X needs Y → X-dat нужен Y-nom)
     if s and s.dative_subject and s.dative_subject[i] then
       e.form = case["Д"]
     end
    -- Clear copula short-form context: a noun closes the X003+adj construction.
    e.infinitive = false
    local d = utils.decode(t, true)
    local b = compiler.base[d]
    if not b then
      dbg.diag("multi", "noun no base:", d)
      return d
    end
    e.gender = get_gender(t) or e.gender  -- fallback to default if not in RUS
    if not (e.numeral and e.numeral.noun_plural) then
      e.plural = e.plural and (b:byte(3)&0x4) == 0
    end
    -- LTGOLD encodes genitive-modifier propagation in T2/T8 rule flags (constituent-type
    -- index bits). Without the flag mechanism, we approximate: N+N → second N is genitive.
    if i and i > 1 and s and s[i-1] and s[i-1]:sub(1,1) == 'N' then
      e.form = case["Р"]
      dbg.log(2, "    N genitive modifier:", d)
    end
    local paradigm = b:byte(4)&~0x80
    -- Store the noun form in token context for downstream gender agreement
    -- (LTPRO +0x72: copula, adjective, and pronoun printers read this).
    if s and s.context and i then s.context[i] = t end
    local result = paradigms.noun(t, paradigm, e)
    dbg.log(2, string.format("    N: word=%-12s paradigm=%-3d gender=%d form=%d => %s",
      d, paradigm, e.gender, e.form, utils.decode(result)))
    -- Multiple meanings: when the token contains a semicolon-separated alternative
    -- (e.g. NNобразец;выборка), append {N.alternative} just as LTGOLD does.
    -- LTGOLD tracks a per-sentence counter in its output formatter.
    -- Suppress alternative annotation when preceded by indefinite article ("a"/"an").
    local preceded_by_indef = s and i and s[i-1] and s[i-1]:sub(1,1) == 'T' and
      s.source and (s.source[i-1] == 'a' or s.source[i-1] == 'an' or s.source[i-1] == 'A' or s.source[i-1] == 'An')
    local alt = (not preceded_by_indef) and leading_alternatives(t)
    if alt then
      e.multi_count = (e.multi_count or 0) + 1
      if alt and #alt > 0 then
        result = result .. '{' .. e.multi_count .. '.' .. alt .. '}'
      end
      dbg.diag("multi", "multi-form noun:", utils.decode(t, false))
    end
    -- Don't reset e.form to accusative here — let the preposition's case (set by P printer)
    -- propagate through the entire noun chain.
    if e.numeral then
      -- A numeral subject is semantically plural even when 2-4 require a
      -- genitive-singular noun form.
      e.numeral = nil
      e.plural, e.form = true, case["И"]
    end
    if e.verb_frame then e.verb_frame = nil end
    return result
  end,
  P = function(t, e, s, i)
    -- Absorb the preposition when a P/D token follows a verb and has a D (adverb)
    -- alternative with no following noun (e.g. "fell down" — particle, not prep).
    -- LTGOLD encodes this via the analyzer resolving "fell"→"fall" and matching
    -- "fall down" as a phrasal-verb dictionary entry.
    if s and i then
      local prev_tag = s[i-1] and s[i-1]:sub(1, 1)
      local next_tag = s[i+1] and s[i+1]:sub(1, 1)
      local has_d_alt = t:find('D', 2, true)  -- token has a D alternative packed
      if prev_tag and prev_tag:match('[VEZveEG]') and has_d_alt and
         next_tag and not next_tag:match('[Nn#]') then
        return ""
      end
    end
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
    if e.infinitive and not e.infinitive_particle and t:find('A', 1, true) then
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
              gender = get_gender(s[j]) or gender  -- fallback if not in RUS
              break
            end
          end
        end
        local short_endings = { [1]="", [2]="а", [3]="о", [4]="ы" }
        local idx = e.plural and 4 or ({[0]=3, [1]=1, [2]=2})[gender or 1]
        dbg.log(2, string.format("    Z copula+adj: stem=%-10s gender=%d idx=%d => %s",
          stem, gender, idx, stem .. (short_endings[idx] or "")))
        return stem .. (short_endings[idx] or "")
      end
    end
    if not e.perfective then
      e.perfective = (e.word == 1)
    end
    if e.word == 1 then e.imperative = true end
     -- LTGOLD emits the PERFECTIVE infinitive after a modal when available
     -- (говорить→сказать, идти→придти), otherwise the imperfective infinitive.
     -- V1 tokens are dictionary-stored present-tense surface forms and keep
     -- their original aspect under modals (e.g. can understand → может понимать).
     if e.infinitive then
       e.infinitive, e.infinitive_particle = false, false
       if e.perfective and compiler.base[d] and (compiler.base[d]:byte(2)&2) ~= 2 then
         if t:match('^V1') then
           return d  -- V1 present-tense forms keep original aspect
         end
         local paired = compiler.base[d]:sub(6)
         if #paired > 0 and paired:byte(1) >= 128 then
           e.perfective = false
           return utils.decode(paired)
         end
       end
       return d
     end
    -- Switch from imperfective to perfective paired form when the context demands it:
    -- e.perfective is set for first-word verbs in future/perfect contexts;
    -- e.past is set by V! tokens (resolved past tense). Both should trigger the switch,
    -- UNLESS e.progressive is set (V~ from X1+G: progressive past stays imperfective)
    -- or e.simple_past is set (V= from X1+K+Z: simple past from "did" stays imperfective).
    if (e.perfective or e.past) and not e.progressive and not e.simple_past and compiler.base[d] and (compiler.base[d]:byte(2)&2)~=2 then
      local paired = compiler.base[d]:sub(6)
      if #paired > 0 and paired:byte(1) >= 128 then
        t = paired
        d = utils.decode(t)
        dbg.log(2, string.format("    Z perfective switch: → %s", d))
      end
    end
    if not compiler.base[d] then return d end
    local paradigm = compiler.base[d]:byte(4)&~0x80
    -- v-tagged (3sg present) verbs: LTGOLD uses the infinitive-ending mapping
    -- (morph.txt lines 548-657) instead of the BASE.RUS paradigm ID.
    if t:byte(1) == 0x76 then
      local alt = paradigms.verb_paradigm_for_v(d)
      if alt then paradigm = alt end
    end
    return paradigms.verb(t, paradigm, e)
  end,
  U = function(t, e, s, i)
    local d = utils.decode(t, true)
    -- U1 = past/conditional modal ("could", "might", "should" past):
    -- output past tense form of modal + " бы" conditional particle.
    local is_conditional = t:byte(2) == string.byte('1')
    -- suppress modal when it was originally copula (X) followed by adjective.
    if d == "должен" and s and s[i+1] and s[i+1]:find('A', 1, true) then
      e.infinitive, e.perfective = true, true
      dbg.log(2, "    U suppressed (copula+adj context):", d)
      return ""
    end
    -- "could/should/would have done": U1 + Y + F → LTGOLD outputs just the past verb + бы,
    -- dropping the modal entirely. U1 sets the conditional flag and goes silent.
    if is_conditional and s and s[i+1] and s[i+1]:sub(1,1) == 'Y' then
      e.conditional = true
      e.infinitive, e.perfective = false, false
      dbg.log(2, "    U1 before Y: conditional=true, silent")
      return ""
    end
    local u = uniques[d]
    local source_modal = s and s.source and s.source[i] and s.source[i]:lower()
    local modal_perfective = source_modal ~= "may" and source_modal ~= "might"
    e.infinitive, e.perfective = true, modal_perfective
    e.modal_scope = { perfective = modal_perfective }
    dbg.log(2, string.format("    U: word=%-12s → infinitive=%s perfective=%s",
      d, tostring(e.infinitive), tostring(e.perfective)))
    if u then
      local _u = utils.extract(t)
      local base = utils.decode(_u:sub(1,#_u-2))
      local form = base .. u[e.plural and 4 or (e.gender+1)]
      if is_conditional then return form .. " бы" end
      return form
    else
      local b = compiler.base[d]
      if b then
        if is_conditional then
          -- Past conditional: use past tense form + " бы"
          local e_past = { plural = e.plural, gender = e.gender, form = e.form,
                           past = true, passive = false, person = e.person or 3 }
          return paradigms.verb(t, b:byte(4)&~0x80, e_past) .. " бы"
        end
        return paradigms.verb(t, b:byte(4)&~0x80, e)
      end
      return utils.decode(t, true)
    end
  end,
  T = function() return "" end,
  [" "] = function (t) return utils.decode(t, true) end,
  -- C: conjunction — decode full text after tag byte (no strip, preserves spaces)
  C = function (t, e)
    if e.modal_scope and e.modal_scope.consumed then e.modal_scope.awaiting_coord = true end
    return utils.decode(t:sub(2), false)
  end,
  D = function (t)
    -- Skip the leading tag byte(s). Some D tokens have "DD..." (double-D prefix).
    -- Then decode CP866 content stopping at ';' (alternate-meaning separator).
    -- Multi-word phrase D tokens contain spaces which must be preserved.
    local encoding = require "core.encoding"
    local i = 2
    -- Skip any additional ASCII letter prefix bytes (e.g. second 'D' in "DD...")
    while i <= #t and t:byte(i) >= 65 and t:byte(i) <= 122 do i = i + 1 end
    -- Decode CP866 content up to ';' separator or next ASCII tag letter.
    local result = {}
    while i <= #t do
      local b = t:byte(i)
      if b == 0x3B then break end  -- stop at ';' (alternate form)
      -- Stop at ASCII letter that begins a new packed tag (A, D, W, etc.)
      if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then break end
      local ch = encoding.character(b)
      if ch then result[#result+1] = ch
      elseif b == 0x20 or b == 0x2D or b == 0x2C then result[#result+1] = string.char(b)  -- space/hyphen/comma OK
      end
      i = i + 1
    end
    return table.concat(result)
  end,
  -- E/e: past participle / -ed form → produce past tense
  E = function(t, e, s, i)
    -- E-coded tokens (E001, E002, etc.) may have non-text flag bytes (0x80-0x8F)
    -- between the code and the actual Russian text. Skip them before lookup.
    local code_len = 1  -- skip the 'E' tag
    while code_len < #t and t:byte(code_len + 1) and
          t:byte(code_len + 1) >= string.byte('0') and t:byte(code_len + 1) <= string.byte('9') do
      code_len = code_len + 1
    end
    local text_start = code_len + 1
    while text_start <= #t and t:byte(text_start) >= 0x80 and t:byte(text_start) <= 0x8F do
      text_start = text_start + 1  -- skip flag bytes
    end
    local d = utils.decode(t:sub(text_start), true)
    local b = compiler.base[d]
    if not b then return d end
    -- Lowercase 'e' = ambiguous infinitive/past/participle. When preceded by a modal
    -- (U/X/Y) or infinitive particle (B/b), keep as infinitive (can read → может читать).
    local prev_tag = s and s[i - 1] and s[i - 1]:sub(1, 1)
    local is_after_modal = prev_tag and prev_tag:match('[UXYBb]') ~= nil
    local is_ambiguous = t:sub(1, 1) == 'e'
    if is_ambiguous and is_after_modal then
      e.infinitive = true
      return d
    end
    -- Uppercase E = definite past/passive participle; lowercase e = ambiguous
    -- (infinitive / past / participle). Without a temporal context signal (like
    -- an X1/Y auxiliary), default unambiguous e to non-past to match LTGOLD's
    -- present-tense treatment of bare e-tagged verbs (e.g. "He put it on...").
    e.past = not is_ambiguous
    -- Clear infinitive flag set by X1xx copula: E output is not an infinitive.
    e.infinitive = false
    local previous = s and s[i - 1] and utils.decode(s[i - 1], true)
    local participle_context = {
      ["как"] = { passive = true, gender = 0, plural = false },
    }
    local context = participle_context[previous]
    -- Detect X1xx (past copula) immediately before E → short passive participle.
    -- "The agreement was signed" = X103 + E(sign) → "было подписано".
    -- X1xx is identified by: starts with 'X', has digit code starting with '1'.
    local prev_token = s and s[i - 1]
    local is_past_copula = prev_token and prev_token:sub(1,1) == 'X' and
      (prev_token:match("^X1") ~= nil)
    if is_past_copula and not has_agent then
      e.passive = true
    end
    -- Detect instrumental agent "by" (PТ = CP866 byte 0x92). This signals
    -- LTGOLD's reflexive passive: imperfective verb past + -ся suffix.
    local has_agent = s and s[i+1] and s[i+1]:sub(1,1) == 'P' and
      #s[i+1] == 2 and s[i+1]:byte(2) == 0x92
    -- Adjectival passive: E pre-nominal before P (e.g. "the broken window needs repair").
    -- Only fire when E is preceded by article/adjective (T/A/O), NOT by subject (N/R).
    -- "N E P" = subject-verb-preposition → NOT adjectival (e.g. "the cat sat on the mat").
    -- "T E N" or "A E N" → pre-nominal participial E → adjectival passive.
    local prev_tag = s and s[i - 1] and s[i - 1]:sub(1, 1)
    local adjectival = (not has_agent) and s and s[i + 1] and
      s[i + 1]:sub(1, 1) == 'P' and prev_tag and
      prev_tag:match("[TAOj]") ~= nil
    if context then
      e.passive, e.gender, e.plural = context.passive, context.gender, context.plural
    elseif adjectival then
      e.passive = true
    elseif has_agent then
      -- Instrumental-agent passive: LTGOLD uses imperfective reflexive past (-ся form).
      e.passive = true
      dbg.log(2, "    E instrumental-agent passive detected")
    end
    if has_agent then
      -- Reflexive passive: stay imperfective (do not switch to perfective pair).
      -- Use past tense of the imperfective verb + reflexive -ся suffix.
      b = compiler.base[d]
      if not b then return d end
      local e_refl = { plural = e.plural, gender = e.gender, form = e.form,
                       past = true, passive = false, person = e.person or 3 }
      local result = paradigms.verb(t, b:byte(4)&~0x80, e_refl)
      -- Determine the correct reflexive suffix (-сь after vowels, -ся after consonants).
      local last2 = result:sub(-2)
      local vowels = { ["ю"]="сь",["у"]="сь",["е"]="сь",["а"]="сь",
                       ["о"]="сь",["и"]="сь",["ы"]="сь",["э"]="сь",["ь"]="сь" }
      local refl = vowels[last2] or "ся"
      e.passive = false
      return result .. refl
    end
    -- E0 (parser-converted from h-tag, byte3 = CP866 non-digit): suppress switch.
    -- E0x (dictionary codes E01, E02 etc., byte3 = digit): allow switch.
    -- E1x (multi-digit E11, E103: analyzer-resolved): suppress switch.
    -- E1 (single-digit, byte3 = CP866 non-digit, e.g. told→E1говорить): allow switch.
    -- Also suppress for lowercase e (ambiguous) without explicit past context.
    local is_digit = function(b) return b and b >= string.byte('0') and b <= string.byte('9') end
    local suppress = (t:byte(2) == string.byte('0') and not is_digit(t:byte(3))) or
      (t:byte(2) == string.byte('1') and is_digit(t:byte(3)))
    if not suppress and e.past and b:byte(2)&2 ~= 2 then
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
      local result = paradigms.verb(t, b:byte(4)&~0x80, e)
      e.passive = false
      return result
    end
    e.verb_frame = verb_frames[utils.extract_form(t)]
    if e.verb_frame and e.verb_frame.object_case and not e.verb_frame.preposition then
      e.form = e.verb_frame.object_case
    end
    local result = paradigms.verb(t, b:byte(4)&~0x80, e)
    -- Reflexive verbs: some E-tagged verbs require -ся when used intransitively.
    -- LTPRO type-11 checks +0x66; we use an explicit table of reflexive-only stems.
    local reflexive_intrans = { ["жечь"]=true }
    if e.past and not e.passive and reflexive_intrans[d] then
      local next_i = i and (i + 1)
      while s and s[next_i] and s[next_i]:sub(1,1):match('[TtAaDd]') do next_i = next_i + 1 end
      local next_tag = s and s[next_i] and s[next_i]:sub(1,1)
      if not next_tag or not next_tag:match('[NnRrMmOo#]') then
        local vowels = { ["ю"]="сь",["у"]="сь",["е"]="сь",["а"]="сь",
                         ["о"]="сь",["и"]="сь",["ы"]="сь",["э"]="сь",["ь"]="сь" }
        result = result .. (vowels[result:sub(-2)] or "ся")
      end
    end
    return result
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
	-- V! is the parser's resolved simple-past marker for an E/e dictionary form that has no separately packed V alternative.
	-- V~ is the progressive-past marker from X1+G: past tense but imperfective (no perfective switch).
	-- V= is the simple-past marker from X1+K+Z ("did not write"): past tense, no perfective switch.
	-- (Dictionary-stored V1 tokens are present-tense forms, not past.)
	local resolved_past = t:sub(2, 2) == '!'
	local progressive_past = t:sub(2, 2) == '~'
	local simple_past = t:sub(2, 2) == '='
	if resolved_past or progressive_past or simple_past then
		t = 'V' .. t:sub(3)
		e.past = true
		-- V~ and V= verbs must not trigger the perfective switch; they stay imperfective
		-- (was reading → читала, not прочитала; did write → писал, not написал).
		if progressive_past then e.progressive = true end
		if simple_past then e.simple_past = true end
	end
  if e.modal_scope and (not e.modal_scope.consumed or e.modal_scope.awaiting_coord) then
    -- T7 coordinated VP flags keep every verb under the same modal auxiliary.
    e.infinitive, e.perfective = true, e.modal_scope.perfective
  end
  if e.verb_frame and e.verb_frame.next_infinitive then
    e.infinitive = true
    e.verb_frame = nil
  elseif s and i then
    local plural = subject_is_plural(s, i)
    if plural ~= nil then e.plural = plural end
  end
  -- Detect instrumental agent "by" (PТ). V from a passive X+E conversion gets this context.
  -- LTGOLD emits imperfective reflexive past (-ся) for these constructions.
  local has_agent = s and i and s[i+1] and s[i+1]:sub(1,1) == 'P' and
    #s[i+1] == 2 and s[i+1]:byte(2) == 0x92
  if has_agent then
    local d = utils.extract_form(t)
    local b = compiler.base[d]
    if b then
      local e_refl = { plural = e.plural, gender = e.gender, form = e.form,
                       past = true, passive = false, person = e.person or 3 }
      local result = paradigms.verb(t, b:byte(4)&~0x80, e_refl)
      local last2 = result:sub(-2)
      local vowels = { ["ю"]="сь",["у"]="сь",["е"]="сь",["а"]="сь",
                       ["о"]="сь",["и"]="сь",["ы"]="сь",["э"]="сь",["ь"]="сь" }
      e.passive = false
      return result .. (vowels[last2] or "ся")
    end
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
	if e.modal_scope then
	  e.modal_scope.consumed = true
	  e.modal_scope.awaiting_coord = false
	end
	if resolved_past or simple_past then e.past = false end
	if simple_past then e.simple_past = false end
	if progressive_past then e.progressive = false end
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
printers.d = function(t, e) return printers.D(t, e) end
printers.f = function(t) return utils.decode(t, true) end
-- J (subordinating conjunction), L (relative pronoun), j (clause-end marker), O (demonstrative)
-- These are structural/functional words — output their Russian text directly
-- J (subordinating conjunction): decode only the J-form text, stopping at the next
-- packed tag letter (P, C, b, B, etc.) that begins a government chain.
-- e.g. JеслиPПпри → "если"; J, когдаPПпри → ", когда"
printers.J = function(t)
  local s = t:sub(2)
  -- Skip optional digit code (e.g. J01, J21)
  local i = 1
  while i <= #s and s:byte(i) >= 48 and s:byte(i) <= 57 do i = i + 1 end
  local result = {}
  while i <= #s do
    local b = s:byte(i)
    -- Stop at ASCII letter that begins a new tag (next packed form)
    -- Allow comma (0x2C), space (0x20), hyphen (0x2D) as part of Russian text
    if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then break end
    result[#result+1] = s:sub(i, i)
    i = i + 1
  end
  return utils.decode(table.concat(result), false)
end
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
  -- Relative pronoun "который" declined for gender (antecedent noun) and case (e.form).
  -- Base L token text is ", который"; lowercase l is genitive feminine "которой".
  local raw = utils.decode(t:sub(2), false)

  -- Detect antecedent noun gender by scanning backward
  local gender = nil
  if s then
    for j = (i and i-1 or 0), 1, -1 do
      local tag = s[j] and s[j]:sub(1,1)
       if tag == 'N' or tag == 'n' then
         gender = get_gender(s[j]) or gender  -- fallback if not in RUS
        break
      end
    end
  end

  -- Case for rule-created lowercase-p prepositions: infer from preposition text
  -- These prepositions always take a specific case when followed by a relative pronoun.
  local prep_case_map = {
    ["из"] = 2, ["от"] = 2, ["до"] = 2, ["без"] = 2, ["для"] = 2,
    ["у"] = 2, ["с"] = 2, ["со"] = 2, ["после"] = 2, ["кроме"] = 2,
    ["к"] = 3, ["ко"] = 3,
    ["в"] = 6, ["на"] = 6, ["о"] = 6, ["об"] = 6, ["при"] = 6,
    ["над"] = 5, ["под"] = 5, ["перед"] = 5, ["за"] = 5, ["между"] = 5,
  }

  -- Detect if immediately preceded by a preposition token (P or p)
  local preceded_by_prep = false
  local prep_form = nil
  if s and i then
    local prev_tok = s[i-1]
    local prev_tag = prev_tok and prev_tok:sub(1,1)
    if prev_tag == 'P' or prev_tag == 'p' then
      preceded_by_prep = true
      -- For lowercase p (rule-created), infer case from preposition text
      if prev_tag == 'p' then
        local prep_text = utils.decode(prev_tok:sub(2), false)
        prep_form = prep_case_map[prep_text]
      end
    end
  end

  -- Full declension table for "который": [form][gender]
  -- form: 1=nom, 2=gen, 3=dat, 4=acc, 5=ins, 6=prep
  -- gender index: 1=masc, 2=fem, 3=neut, 4=plural
  local forms = {
    [1] = {"который",  "которая",  "которое",  "которые"},   -- nominative
    [2] = {"которого", "которой",  "которого", "которых"},   -- genitive
    [3] = {"которому", "которой",  "которому", "которым"},   -- dative
    [4] = {"который",  "которую",  "которое",  "которые"},   -- accusative (inanimate; masc anim would be которого)
    [5] = {"которым",  "которой",  "которым",  "которыми"},  -- instrumental
    [6] = {"котором",  "которой",  "котором",  "которых"},   -- prepositional
  }

  -- Determine the form (case) to use: prep_form overrides e.form for rule-created p tokens
  local form_idx = prep_form or (e and e.form) or 1
  if form_idx < 1 or form_idx > 6 then form_idx = 1 end

  -- For nominative case (form=1), detect whether L is subject or object:
  -- If the next token is a subject pronoun (R) or noun (N), L is the object → accusative.
  -- If the next token is directly a verb (E/V/X/Y), L is the subject → nominative.
  -- This matters only for feminine (masc nom=acc for inanimate, neut nom=acc always).
  if form_idx == 1 and not preceded_by_prep and s and i then
    local next_tag = s[i+1] and s[i+1]:sub(1,1)
    if next_tag == 'R' or next_tag == 'N' or next_tag == 'n' then
      form_idx = 4  -- accusative (object of relative clause)
    end
  end

  -- gender index: masc=1, fem=2, neut=0→3, plural=4
  local g_idx
  if gender == 2 then g_idx = 2
  elseif gender == 0 then g_idx = 3
  else g_idx = 1  -- masculine default
  end

  local pronoun = forms[form_idx][g_idx]

  -- When preceded by a preposition: LTGOLD uses 2 spaces between prep and pronoun (no comma).
  -- The compile loop adds 1 space between tokens, making 3 total ("в   котором").
  if preceded_by_prep then
    return "  " .. pronoun
  end

  -- Otherwise keep the leading ", " that was in the original token text
  local prefix = raw:match("^([,%s]+)") or ""
  if prefix ~= "" then
    return prefix .. pronoun
  end
  return pronoun
end
printers.j = function(t) return "," end  -- clause-end marker outputs the comma it replaced
printers.O = function(t, e, s, i)
  local d = utils.decode(t, true)
  if d == "весь" then return printers.S(t, e) end
  if d == "это" then
    -- Standalone neuter demonstrative follows the этот paradigm in oblique
    -- cases (about it → об этом), but remains это in nominative/accusative.
    local forms = { "это", "этого", "этому", "это", "этим", "этом" }
    return forms[e.form or 1] or "это"
  end
  -- Hardcoded demonstrative pronoun forms. LTGOLD stores these in the Russian paradigm
  -- tables (BASE.RUS) indexed by paradigm number. A table lookup over this if-chain
  -- would match LTGOLD's approach and generalize to other demonstratives.
  if d == "этот" then
    local noun_gender, noun_plural = e.gender, false
    if s then
      for j = i and (i+1) or 1, #s do
        local tag = s[j] and s[j]:sub(1,1)
         if tag == 'N' then
           noun_gender = get_gender(s[j]) or noun_gender  -- fallback if not in RUS
           -- uppercase N = singular; lowercase n = plural
           noun_plural = false
           break
         elseif tag == 'n' then
           noun_gender = get_gender(s[j]) or noun_gender  -- fallback if not in RUS
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
-- l: genitive relative pronoun (triggered by "whose").  Force genitive case
-- regardless of e.form, since "whose" inherently means "of which/whose".
printers.l = function(t, e, s, i)
  local saved_form = e and e.form
  if e then e.form = case["Р"] end  -- genitive
  local result = printers.L(t, e, s, i)
  if e then e.form = saved_form end
  return result
end
printers.s = printers.S
-- h (history/alternate form marker) — treat as past tense like E
  printers.h = function(t, e)
    -- h-tag: historical/irregular past form. LTGOLD uses imperfective past directly.
    -- No perfective aspect switch — "came" → приходил (imperfective), not пришел.
    local d = utils.decode(t, true)
    local b = compiler.base[d]
    if not b then return d end
    e.past = true
    -- Use the imperfective verb directly (no aspect switch).
    return paradigms.verb(t, b:byte(4)&~0x80, e)
  end
-- Q (question word): decode and interpret case-government prefix.
-- LTGOLD stores a leading Russian case letter (И/Р/Д/В/Т/П) that instructs
-- the compiler which case to decline the pronoun into (e.g. Дкто → dative "кому").
printers.Q = function(t, e)
  -- utils.extract_form already strips the tag byte and decodes CP866
  local raw = utils.extract_form(t)
  -- LTGOLD case-government codes embedded in the dictionary form.
  -- A leading Russian case letter (И/Р/Д/В/Т/П) instructs the compiler
  -- which case to decline the pronoun into (e.g. Дкто → dative "кому").
  -- Use UTF-8 codepoint comparison since case letters are 2-byte Cyrillic.
  local prefix_cp = utf8.codepoint(raw, 1)
  local case_cp_map = {
    [0x0418] = case["И"], [0x0420] = case["Р"], [0x0414] = case["Д"],
    [0x0412] = case["В"], [0x0422] = case["Т"], [0x041F] = case["П"],
  }
  local case_code = case_cp_map[prefix_cp]
  if case_code and e then
    e.form = case_code
    raw = raw:sub(utf8.offset(raw, 2))  -- strip the case prefix
  end
  -- Decline interrogative/relative pronouns for the resolved case
  local pronoun_forms = {
    ["кто"]  = { "кто",  "кого",  "кому",  "кого",  "кем",  "ком"  },
    ["что"]  = { "что",  "чего",  "чему",  "что",  "чем",  "чём"  },
    ["чей"]  = { "чей",  "чьего", "чьему", "чей",  "чьим", "чьём" },
  }
  local forms = pronoun_forms[raw]
  if forms and e then
    local result = forms[e.form] or raw
    -- Reset case after the relative pronoun — it governs the relative clause,
    -- not the main clause.  Without this, dative from "кому" bleeds into
    -- subsequent tokens like object pronouns (ему instead of его).
    e.form = case["И"]
    return result
  end
  return raw
end
printers.M = function(t, e, s, i)
  local plural, person, gender = t:match("M(%d)(%d)(%d)")
  if not plural then plural, person = t:match("M(%d)(%d)") end
  if plural then
    local result = paradigms.pronoun(plural ~= '0', tonumber(person) or 3,
      tonumber(gender) or e.gender, e.form)
    -- 3rd-person pronouns preceded by a preposition take н- prefix (ним, нею, ними…).
    -- Exception: accusative feminine "её/ее" does not take н- (LTGOLD: "на ее", not "нее").
    local p = tonumber(person) or 3
    local bare_dative = s and i and s[i-1] and #s[i-1] == 2 and
      utils.decode(s[i-1]:sub(2, 2), true) == "Д"
    if p == 3 and s and i and s[i-1] and s[i-1]:sub(1,1) == 'P' and not bare_dative
       and result ~= "ее" then
      result = "н" .. result
    end
    return result
  end
  return utils.decode(t, true)
end
-- I: numeral. Output the I-form (nominative). Set e.numeral for noun case control.
-- LTGOLD numeral agreement (simplified):
-- 2-4: nom numeral + gen-pl adj + gen-sg noun
-- 5+: nom numeral + gen-pl adj + gen-pl noun
-- 1: nom numeral + nom adj + nom noun
printers.I = function(t, e, s, i)
  -- Extract I-form (nominative numeral): output "три", "пять", etc.
  local i_text = utils.extract_form(t)
  if #i_text == 0 then i_text = utils.decode(t, true) end
  local numeral = i_text:lower()
  local two_to_four = { ["два"] = true, ["две"] = true, ["три"] = true, ["четыре"] = true }
  local noun
  if s and i then noun = find(s, i + 1, 'Nn') end
  local feminine_two = (numeral == "два" or numeral == "две") and noun and get_gender(noun) == 2
  if feminine_two then
    -- LTGOLD's feminine-two constituent uses plural agreement and selects две.
    i_text = "две"
    e.numeral = { noun_form = case["И"], noun_plural = true,
      adjective_form = case["И"], adjective_plural = true }
  elseif two_to_four[numeral] then
    e.numeral = { noun_form = case["Р"], noun_plural = false,
      adjective_form = case["Р"], adjective_plural = true }
  else
    -- Numerals five and above govern genitive plural for the complete NP.
    e.numeral = { noun_form = case["Р"], noun_plural = true,
      adjective_form = case["Р"], adjective_plural = true }
  end
  e.form, e.plural = e.numeral.noun_form, e.numeral.noun_plural
  return i_text
end
printers.m = function(t) return utils.decode(t, true) end
printers.r = function(t) return utils.decode(t, true) end
-- k (negative 'no'), K (negative 'not')
printers.K = function(t) return utils.decode(t, true) end
printers.k = function(t) return utils.decode(t, true) end
-- Y: "have/has/had" (perfect auxiliary). Silent; sets perfective past context.
-- English perfect = "has/had + past participle" → Russian perfective past.
-- Exception: "must/should have <adj>" → LTGOLD outputs "иметь" literally ("должен иметь известный").
printers.Y = function(t, e, s, i)
  e.perfective = true
  -- When infinitive context from "должен" is active AND the next token is A/F (adjective/participle),
  -- output "иметь" literally instead of being silent.
  if e.infinitive and s and i then
    local next_tag = s[i+1] and s[i+1]:sub(1,1)
    if next_tag == 'A' or next_tag == 'F' then
      e.infinitive = false
      dbg.log(2, "    Y after должен + adj: output иметь")
      return utils.extract_form(t)
    end
  end
  dbg.log(2, "    Y (perfect aux): perfective=true, silent")
  return ""
end
-- x (impersonal/there-is), y (have existential), i (indefinite article form)
printers.x = function(t, e, s, i)
  -- x = impersonal verb / existential ("нужно" = it is necessary).
  -- When followed by a noun, decline as short adjective agreeing with it.
  local decoded = utils.decode(t, true)
   if decoded == "нужно" and s and i then
     local j = i + 1
     while s[j] and s[j]:sub(1,1):match('[Tq]') do j = j + 1 end
     if s[j] and s[j]:sub(1,1):match('[Nn]') then
       local gender = get_gender(s[j]) or 1
       local forms = { [1]="нужен", [2]="нужна", [0]="нужно" }
       local plural = s[j]:sub(1,1) == 'n'
       -- Set nominative for the grammatical subject following the x verb
       e.form = case["И"]
       return plural and "нужны" or (forms[gender] or "нужно")
     end
   end
  return decoded
end
printers.y = function(t, e)
  -- y1 = "нет" (existential negative "there is no") requires genitive on the
  -- governed noun (LTGOLD encodes this via constituent-flag case government).
  if t:match('^y1') then e.form = case["Р"] end
  return utils.decode(t, true)
end
printers.i = function(t) return utils.decode(t, true) end
printers.u = function(t) return utils.decode(t, true) end
-- LTGOLD's B/b tags are silent morphology controls: B selects a perfective
-- infinitive and b selects an imperfective infinitive for the following verb.
printers.B = function(t, e)
  e.infinitive, e.infinitive_particle, e.perfective = true, true, true
  return ""
end
printers.b = function(t, e)
  e.infinitive, e.infinitive_particle, e.perfective = true, true, false
  return ""
end
-- W (multi-word phrase) — output decoded. For packed W-tokens with sub-forms
-- (V + P from back-reference matches like "came from" → WVисходитьPРиз),
-- expand each sub-constituent as a separate output word.
printers.W = function(t, e, s, i)
  local vform = find_form(t, 'V')
  local pform = find_form(t, 'P')
  local nform = find_form(t, 'N')
  if vform or pform or nform then
    local parts = {}
    if vform then parts[#parts+1] = utils.decode(vform, true) end
    if pform then
      local ptext = utils.decode(pform, true)
      if #parts > 0 then parts[#parts+1] = ptext else parts[#parts+1] = ptext end
    end
    if nform then
      local ntext = utils.decode(nform, true)
      if #parts > 0 then parts[#parts+1] = ntext else parts[#parts+1] = ntext end
    end
    return table.concat(parts, " ")
  end
  return utils.decode(t, true)
end
-- # (proper noun / untranslatable): output raw string, reformat digit-only sequences
-- back to comma-formatted numbers (e.g. 1000000 → 1,000,000) since tokenize strips commas.
-- An unknown word between a modal and a verb breaks the modal chain in LTGOLD.
printers["#"] = function(t, e)
  e.modal_scope = nil
  e.infinitive = false
  e.perfective = false
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
  -- Proper names: decode CP866 and strip LTGOLD metadata prefix (digit+м= pattern).
  local decoded = utils.decode(s, false)
  decoded = decoded:gsub("^%d+м=", "")
  return decoded
end
printers.F = function(t, e, s, i)
  -- F tag: perfect/passive past-participle construction.
  -- Y (have) + F → English perfect → Russian perfective active past ("написала").
  -- U1 + Y + F → conditional past: imperfective past + " бы" (e.g. could have gone → шла бы).
  -- X103 (was) + F without agent → short passive participle ("было подписано").
  -- X103 (was) + F with instrumental agent → reflexive imperfective past ("писалось нею").
  e.infinitive = false
  e.past = true
  -- U1+Y+F conditional: output imperfective past + " бы", drop perfective switch.
  local conditional = e.conditional
  e.conditional = nil
  if conditional then
    local direct = utils.extract_form(t)
    local vtext = find_form(t, 'V')
    local base_word = (vtext and utils.decode(vtext, true)) or direct
    local b = compiler.base[base_word]
    if b then
      local vt = vtext and ('V' .. vtext) or ('V' .. utils.encode(base_word))
      local e_past = { plural = e.plural, gender = e.gender, form = e.form,
        past = true, passive = false, person = e.person or 3 }
      return paradigms.verb(vt, b:byte(4)&~0x80, e_past) .. " бы"
    end
  end
  -- Check if this is a Y (perfect) context: scan backward past negation (K/k) tokens
  -- to find the Y auxiliary (e.g. "has not seen" → Y + K + F).
  local is_perfect = false
  if s and i then
    for j = i - 1, 1, -1 do
      local prev_tag = s[j]:sub(1, 1)
      if prev_tag == 'Y' then is_perfect = true; break end
      if prev_tag ~= 'K' and prev_tag ~= 'k' then break end
    end
  end
  local has_agent = s and i and s[i+1] and s[i+1]:sub(1,1) == 'P' and
    #s[i+1] == 2 and s[i+1]:byte(2) == 0x92
  local vtext = find_form(t, 'V')
  if is_perfect and not vtext then
    -- Some F records store the imperfective verb directly after the F tag
    -- instead of packing a secondary V form (spoken → FговоритьAустный).
    local direct = utils.extract_form(t)
    local direct_base = compiler.base[direct]
    if direct_base then
      local vt = 'V' .. utils.encode(direct)
      if direct_base:byte(2)&2 ~= 2 then
        local paired = direct_base:sub(6)
        if #paired > 0 and paired:byte(1) >= 128 then
          vt = paired
          direct_base = compiler.base[utils.decode(vt)] or direct_base
        end
      end
      local e_perf = { plural = e.plural, gender = e.gender, form = e.form,
        past = true, passive = false, person = e.person or 3 }
      return paradigms.verb(vt, direct_base:byte(4)&~0x80, e_perf)
    end
  end
  if vtext then
    local d = utils.decode(vtext, true)
    local b = compiler.base[d]
    if b then
      local vt = 'V' .. vtext
      if is_perfect then
        -- English perfect: Y + F → perfective active past (написала, обнаружили, etc.)
        if b:byte(2)&2 ~= 2 then  -- if imperfective, switch to perfective pair
          local pt = b:sub(6)
          if #pt > 0 and pt:byte(1) >= 128 then
            vt = pt; b = compiler.base[utils.decode(vt)] or b
          end
        end
        local e_perf = { plural = e.plural, gender = e.gender, form = e.form,
                         past = true, passive = false, person = e.person or 3 }
        return paradigms.verb(vt, b:byte(4)&~0x80, e_perf)
      elseif has_agent then
        -- X103 + F + agent: reflexive imperfective past ("писалось нею")
        local e_refl = { plural = e.plural, gender = e.gender, form = e.form,
                         past = true, passive = false, person = e.person or 3 }
        local result = paradigms.verb(vt, b:byte(4)&~0x80, e_refl)
        local last2 = result:sub(-2)
        local vowels = { ["ю"]="сь",["у"]="сь",["е"]="сь",["а"]="сь",
                         ["о"]="сь",["и"]="сь",["ы"]="сь",["э"]="сь",["ь"]="сь" }
        return result .. (vowels[last2] or "ся")
      else
        -- X103 + F without agent: short passive participle ("было подписано")
        if b:byte(2)&2 ~= 2 then
          local pt = b:sub(6)
          if #pt > 0 and pt:byte(1) >= 128 then
            vt = pt; b = compiler.base[utils.decode(vt)] or b
          end
        end
        local e_pass = { plural = e.plural, gender = e.gender, form = e.form,
                         past = true, passive = true, person = e.person or 3 }
        return paradigms.verb(vt, b:byte(4)&~0x80, e_pass)
      end
    end
  end
  e.passive = true
  e.perfective = true
  local result = printers.Z(t, e)
  -- Append alternative meaning if token has ";инф)verb" pattern (LTGOLD multi-meaning).
  local inf_prefix = utils.encode("инф)")
  for si = 1, #t do
    if t:byte(si) == 0x3B then
      local after = t:sub(si + 1)
      if after:sub(1, #inf_prefix) == inf_prefix then
        local alt_text = utils.decode(after:sub(#inf_prefix + 1), true)
        if alt_text and #alt_text > 0 then
          e.multi_count = (e.multi_count or 0) + 1
          result = result .. '{' .. e.multi_count .. '.' .. alt_text .. '}'
        end
        break
      end
    end
  end
  return result
end
printers.X = function(t, e, s, i)
  if t:match("%d+") == "003" then
    e.infinitive = true
    e.form = case["И"]
    dbg.log(2, "    X (copula 003): infinitive=true, form=nom")
    if s and s[i+1] and s[i+1]:match("A[\128-\255]") then return "" end
    return "-"
  else
    local code = t:match("%d+") or ""
    -- X2xx = future auxiliary ("will"): output nothing, mark next verb as perfective future.
    if code:sub(1,1) == '2' then
      e.perfective = true
      dbg.log(2, "    X (future 2xx): perfective=true")
      return ""
    end
    -- X1xx = past copula ("was/were").
    -- Output: past tense of быть agreeing with subject gender/number.
    -- быть past: был(m)/была(f)/было(n)/были(pl)
    if s and i and code:sub(1,1) == '1' then
      local j = i + 1
      while s[j] and s[j]:sub(1,1) == 'T' do j = j + 1 end
      local next_tag = s[j] and s[j]:sub(1,1)
      if next_tag == 'E' or next_tag == 'F' then
        -- Check if E/F is followed by instrumental agent PТ
        local k = j + 1
        if s[k] and s[k]:sub(1,1) == 'P' and #s[k] == 2 and s[k]:byte(2) == 0x92 then
          dbg.log(2, "    X (past copula 1xx + E/F + agent): silent")
          return ""
        end
        -- No agent: X1xx outputs its past form before the short passive participle.
      end
      -- Determine subject gender from preceding noun
      local gender, plural = e.gender, e.plural
      for k = i - 1, 1, -1 do
        if s[k] and s[k]:sub(1,1):match('[Nn]') and
           (k == 1 or not s[k-1] or s[k-1]:sub(1,1) ~= 'N') then
          gender = get_gender(s[k]) or gender  -- fallback to default if not in RUS
          plural = s[k]:sub(1,1) == 'n'
          for q = k - 1, 1, -1 do
            local qtag = s[q] and s[q]:sub(1,1)
            if qtag == 'I' then plural = true break end
            if qtag and qtag:match('[NnRVEX]') then break end
          end
          break
        end
      end
      local past_forms = { [1]="был", [2]="была", [0]="было" }
      local past_out = plural and "были" or (past_forms[gender] or "было")
      e.infinitive = true
      -- Set instrumental form for adjective/noun predicates after past copula
      j = i + 1
      while j and s and s[j] and s[j]:sub(1,1) == 'T' do j = j + 1 end
      if j and s[j] and s[j]:sub(1,1):match('[NA]') then
        e.form = case["Т"]
      end
      dbg.log(2, "    X (past copula 1xx): " .. past_out)
      return past_out
    end
    local p = printers.V(t, e)
    e.infinitive = true
    local j = i and (i + 1) or nil
    while j and s and s[j] and s[j]:sub(1, 1) == 'T' do j = j + 1 end
    if j and s[j] and s[j]:sub(1, 1) == 'N' then
      -- LTGOLD uses instrumental for nominal predicates of overt future copulas.
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
    infinitive_particle = false, -- distinguishes B/b control from X copula state
    word = 1,
    multi_count = 0,  -- counter for multiple-meanings markup {N.alternative}
  }
end

 local function reset_clause_context(e)
  -- LTPRO punctuation closes transient verb/aspect government but preserves
  -- subject features until a later constituent replaces them.
  e.past, e.passive, e.imperative = false, false, false
  e.simple_past, e.perfective, e.infinitive, e.infinitive_particle = false, false, false, false
  e.modal_scope, e.numeral = nil, nil
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

function compiler.compile(s, options)
  options = options or {}
  local e = new_context()
  local c = {}
  local quote_open = false

  -- Pre-scan: mark dative subjects for "need" constructions (N/A... + x + N pattern).
  -- LTGOLD Type-13 W-token creation reorders these; we approximate by pre-marking.
  s.dative_subject = {}
  for i = 1, #s - 2 do
    if s[i]:sub(1,1):match('[NAn]') then
      local j = i + 1
      while s[j] and s[j]:sub(1,1):match('[TAa]') do j = j + 1 end
      if s[j] and s[j]:sub(1,1) == 'x' then
        local decoded = utils.decode(s[j], true)
        if decoded == "нужно" then
          -- Mark the NP tokens (at position i and any preceding A/a tokens)
          -- for dative case.
          for k = i, 1, -1 do
            if s[k]:sub(1,1):match('[NAn]') or s[k]:sub(1,1):match('[Aa]') then
              s.dative_subject[k] = true
            else break end
          end
        end
      end
    end
  end

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
      -- Strip leading comma when this is the first output element (sentence-initial
      -- clause connective).  LTGOLD stores ",Когда" for "when" so the comma attaches
      -- to the preceding clause; at sentence start there is nothing to attach to.
      if out and #c == 0 and out:sub(1, 1) == ',' then
        out = out:sub(2):match("^%s*(.*)") or ""
      end
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
      -- caps == true  → ALL-CAPS (e.g. AGREEMENT → СОГЛАШЕНИЕ)
      -- caps == "init"→ Initial-cap (e.g. Russian → Русского, Metric → Метрический)
      -- LTGOLD preserves initial-cap from source words (proper nouns, sentence-start).
      local src_caps = s.caps and s.caps[i]
      out = apply_source_caps(out, src_caps)
      -- Suppress alternative annotation when noun is preceded by indefinite article.
      local prev_src = s.source and s.source[i-1]
      local indef_article = prev_src == 'a' or prev_src == 'an' or prev_src == 'A' or prev_src == 'An'
      if not (tag == 'N' and indef_article) then
        out = append_alternatives(out, w, e)
      end
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
  -- Always capitalize the first output word. Russian sentences start with a capital
  -- regardless of which source token ended up first after any reordering.
  if #c > 0 then
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
  if not options.quiet then print("") end
  -- Only unmatched source hyphens are prefix joiners (A-B → -B); generated
  -- copular dashes retain their surrounding spaces.
  local result = table.concat(c, " "):gsub("\1%- ", "-"):gsub("\1", "")
  result = result:gsub("\2\"%s*", '"'):gsub("%s*\3\"", '"'):gsub("[\2\3]", "")
  if not options.quiet then
    print(result)
    print("")
  end
  return result
end

-- print(
  --   table.concat({
  --     noun(s.subject.noun, table.unpack(s.subject)),
  --     verb(s.verb.verb, read_transform(s.subject.noun), s.verb.secondary),
  --     noun(s.object.noun, table.unpack(s.object))}, 
  --   " "))

return compiler
