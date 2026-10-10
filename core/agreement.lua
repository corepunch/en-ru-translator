local matching = require 'core.matching'
local nodes = require 'core.nodes'
local text = require 'core.text'
local agreement = {}
-- T7 and T7-adjective in core/rules.lua.
local NOUN_TABLE, ADJECTIVE_TABLE = 8, 'adjective'
local TAGS = '#BEFGHILNOPQUVWbfk'

function agreement.run(state,list,tag,si)
  if not list.next then return 1 end
  local table_offset
  if tag < 0x100 and TAGS:find(string.char(tag),1,true) then table_offset=NOUN_TABLE
  elseif tag==0x41 then table_offset=ADJECTIVE_TABLE else return 1 end
  local vector,count,cache=nodes.rebuild(list)
  local function E(i) return state.elements[i] or {} end
  local function is(r,at) return text.equal(r.source or '',state.assets:string(at)) end
  local get=nodes.number
  local function set(r,f,v) if r then r[f]=v end end
  local function copy(dst,src,f) set(dst,f,get(src,f)) end
  local function reading(r,at) r.text=state.assets:string(at) end
  local function rebuild_vector()
    local n
    vector,n,cache=nodes.rebuild(list)
    return n
  end
  local function dictionary_bit(r,n) return (get(r,'dictionary_flags') >> n) & 1 end
  local function find_noun()
    local r=list.next
    while r do if get(r,'tag')==0x4E then return r end; r=r.next end
  end
  for _,rule in ipairs(state.assets:rules(table_offset)) do
    local di=0
    while count-1>di do
      local hit=matching.words(vector,di,rule.pattern,cache.tags)
      if hit~=0 then
        local A,B
        if rule.order~=0 then A,B=vector[hit],vector[di] else A,B=vector[di],vector[hit] end
        local N=vector[di+1]
        local selector=rule.selector
        local default = false
        if selector == 1 then
          if is(B, 'en_years') then
            local c = get(A, 'case_mask')
            if c == 4 or c == 0x10 or c == 0x20 then
            elseif c == 2 then
              reading(B, 'let'); B.paradigm = 0xFFFF
            elseif not (is(A, 'en_two') or is(A, 'en_three') or is(A, 'en_four')) then
              reading(B, 'let'); B.paradigm = 0xFFFF
            end
            copy(B, A, 'case_mask'); set(B, 'number', 0)
          elseif is(A, 'en_most') then
            set(B, 'case_mask', 2)
            if get(N, 'tag') == 0x41 or get(N, 'tag') == 0x4F then set(N, 'case_mask', 2) end
          else
            if get(N, 'tag') == 0x41 or get(N, 'tag') == 0x4F then
              set(N, 'number', 1)
              if get(A, 'case_mask') == 0 or get(A, 'case_mask') == 8 then
                if get(A, 'number') ~= 0 then set(N, 'case_mask', 2)
                elseif get(B, 'gender') ~= 2 then set(N, 'case_mask', 2) end
              else
                copy(N, A, 'case_mask')
              end
            end
            copy(A, B, 'gender')
            if get(A, 'case_mask') == 0 or get(A, 'case_mask') == 8 then
              if (get(B, 'dictionary_frame') >> 4) & 1 ~= 0 then set(B, 'number', 1) else copy(B, A, 'number') end
              set(A, 'number', 1); set(B, 'case_mask', 2)
            else
              copy(B, A, 'case_mask'); set(B, 'number', 1); set(A, 'number', 1)
            end
          end
        elseif selector == 2 then
          if get(N, 'tag') == 0x51 and get(N, 'case_mask') ~= 0 then
            set(B, 'case_mask', get(N, 'case_mask'))
          else
            local c = get(A, 'case_mask')
            if get(A, 'marker') == 0x77 or get(A, 'marker') == 0x57 then
              -- A composed equivalent supplies its own Russian preposition.
              -- English locative heuristics must not replace authored в by на.
              default = true
            elseif (c == 8 or c == 0x20) and is(A, 'en_in') and text.equal(A.text,state.assets:string('v')) then
              reading(A, dictionary_bit(B, 6) ~= 0 and 'na' or 'v')
              default = true
            elseif get(A, 'marker') ~= 0 then
              default = true
            elseif dictionary_bit(B, 1) ~= 0 then
              if c == 8 and not is(A, 'en_to') then
                set(B, 'case_mask', 2)
              else
                if is(A, 'en_from') then reading(A, 'ot')
                elseif is(A, 'en_to') then
                  A.text = ""; set(A, 'case_mask', 4)
                end
                default = true
              end
            else
              if (c == 8 or c == 0x20) and (is(A, 'en_to') or is(A, 'en_at') or is(A, 'en_into') or is(A, 'en_on')) then
                reading(A, dictionary_bit(B, 6) ~= 0 and 'na' or 'v')
              end
              if is(A, 'en_from') then reading(A, dictionary_bit(B, 6) ~= 0 and 's' or 'iz') end
              default = true
            end
          end
        elseif selector == 3 then
          copy(B, A, 'number'); copy(B, A, 'gender')
        elseif selector == 4 then
          copy(B, A, 'person'); copy(B, A, 'number'); copy(B, A, 'gender'); default = true
        elseif selector == 5 then
          set(B, 'case_mask', 0x10)
        elseif selector == 6 then
          if get(A, 'tag') == 0x4E and get(A, 'marker') == 0x3D then copy(B, A, 'case_mask') else set(B, 'case_mask', 2) end
        elseif selector == 7 then
          local C = A
          if (E(si).tag or 0) ~= 0x4E and (E(si).class or 0) ~= 0x77 and (E(si).class or 0) ~= 0x50 then C = find_noun() end
          if C then copy(B, C, 'case_mask') end
        elseif selector == 8 or selector == 9 or selector == 15 then
          default = true
        elseif selector == 10 then
          set(B, 'number', 1); copy(B, A, 'gender')
        elseif selector == 11 then
          if get(A, 'case_mask') == 0 then
            set(B, 'case_mask', 4)
          elseif get(B, 'source') == 0x69 or get(B, 'source') == 0x49 then
            reading(B, 'eto'); set(B, 'tag', 0x44)
            count = rebuild_vector()
          elseif get(A, 'case_mask') ~= 8 then
            default = true
          elseif (get(A, 'dictionary_frame') >> 6) & 1 ~= 0 then
            set(B, 'case_mask', 4)
          else
            local t = (E(si + 1).tag or 0)
            set(B, 'case_mask', ('NIHORSQW'):find(string.char(t), 1, true) and 4 or 8)
            if get(B, 'aspect') ~= 0 then A.prefix = state.assets:string('ne') end
          end
        elseif selector == 12 then
          copy(A, B, 'number'); copy(A, B, 'gender')
          if tag == 0x50 then copy(A, B, 'case_mask') else copy(B, A, 'case_mask') end
        elseif selector == 13 then
          if get(B, 'number') == 0 then
            set(A, 'tag', 0x41); set(A, 'number', 0); copy(B, A, 'case_mask'); copy(A, B, 'gender')
            count = rebuild_vector()
          else
            local done = false
            if is(B, 'en_years') then
              local last = (A.source or ''):byte(-1) or 0
              if last == 0x30 or last > 0x34 then
                reading(B, 'let'); B.paradigm = 0xFFFF; done = true
              end
            end
            if not done then
              if get(A, 'case_mask') == 0 or get(A, 'case_mask') == 8 then
                if (get(B, 'dictionary_frame') >> 4) & 1 ~= 0 then set(B, 'number', 1) else copy(B, A, 'number') end
                set(B, 'case_mask', 2)
              else
                copy(B, A, 'case_mask'); set(B, 'number', 1)
              end
              if get(N, 'tag') == 0x41 or get(N, 'tag') == 0x4F then
                set(N, 'number', 1)
                if get(A, 'case_mask') == 0 or get(A, 'case_mask') == 8 then
                  if get(A, 'number') ~= 0 then set(N, 'case_mask', 2)
                  elseif get(B, 'gender') ~= 2 then set(N, 'case_mask', 2) end
                else
                  copy(N, A, 'case_mask')
                end
              end
            end
          end
        elseif selector == 14 then
          set(A, 'number', 0); copy(A, B, 'gender')
        elseif selector == 16 then
          set(B, 'case_mask', get(A, 'marker'))
        elseif selector == 17 then
          local C = A
          if (E(si).class or 0) == 0x50 then C = find_noun() end
          if C then copy(B, C, 'case_mask'); copy(B, C, 'number'); copy(B, C, 'gender') end
        elseif selector == 18 then
          set(B, 'number', 1); default = true
        elseif selector == 19 then
          if get(B, 'previous_tag') ~= 0x47 then copy(B, A, 'tense'); copy(B, A, 'passive'); copy(B, A, 'short_form') end
          copy(B, A, 'person'); copy(B, A, 'number'); copy(B, A, 'gender'); copy(B, A, 'verb_flags')
        elseif selector == 20 then
          if get(A, 'marker') == 0x77 then
            set(A, 'number', 0); copy(A, B, 'gender'); set(B, 'case_mask', get(N, 'case_mask'))
          end
        elseif selector == 21 then
          if is(A, 'en_some') and dictionary_bit(B, 4) ~= 0 then
            reading(A, 'nemnogo'); set(A, 'tag', 0x69)
            rebuild_vector()
          end
        elseif selector == 22 then
          if get(A, 'case_mask') ~= 8 then
            default = true
          elseif dictionary_bit(B, 1) ~= 0 then
            if get(B, 'number') == 0 and get(B, 'gender') == 2 then set(B, 'case_mask', 8)
            elseif get(B, 'paradigm') == 0x35 then set(B, 'case_mask', 8)
            else set(B, 'case_mask', 2) end
          else
            set(B, 'case_mask', 8)
          end
        elseif selector == 23 then
          if get(A, 'case_mask') == 0x10 or get(A, 'case_mask') == 0x20 then set(B, 'aspect', 1) end
          default = true
        else
          default = true
        end
        if default then copy(B, A, 'case_mask') end
      end
      di = di + 1
    end
  end
  return 1
end
return agreement
