local matching = require 'core.matching'
local nodes = require 'core.nodes'
local text = require 'core.text'
local agreement = {}
local NOUN_TABLE, ADJECTIVE_TABLE = 0x4542, 0x4662
local TAGS = '#BEFGHILNOPQUVWbfk'

function agreement.run(state,list,tag,si)
  if not list.next then return 1 end
  local table_offset
  if tag < 0x100 and TAGS:find(string.char(tag),1,true) then table_offset=NOUN_TABLE
  elseif tag==0x41 then table_offset=ADJECTIVE_TABLE else return 1 end
  local vector,count,cache=nodes.rebuild(list)
  local function E(i) return state.elements[i] or {} end
  local function is(r,at) return text.equal(r[0x12] or '',state.assets:string(at)) end
  local get=nodes.byte
  local function set(r,f,v) if r then r[f]=v end end
  local function copy(dst,src,f) set(dst,f,get(src,f)) end
  local function reading(r,at) r.text=state.assets:string(at) end
  local function rebuild_vector()
    local n
    vector,n,cache=nodes.rebuild(list)
    return n
  end
  local function b6D(r,n) return (get(r,0x6D) >> n) & 1 end
  local function find_noun()
    local r=list.next
    while r do if get(r,0x0C)==0x4E then return r end; r=r.next end
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
          if is(B, 0x47C6) then
            local c = get(A, 0x76)
            if c == 4 or c == 0x10 or c == 0x20 then
            elseif c == 2 then
              reading(B, 0x47CC); B[0x85] = 0xFFFF
            elseif not (is(A, 0x47D0) or is(A, 0x47D4) or is(A, 0x47DA)) then
              reading(B, 0x47DF); B[0x85] = 0xFFFF
            end
            copy(B, A, 0x76); set(B, 0x72, 0)
          elseif is(A, 0x47E3) then
            set(B, 0x76, 2)
            if get(N, 0x0C) == 0x41 or get(N, 0x0C) == 0x4F then set(N, 0x76, 2) end
          else
            if get(N, 0x0C) == 0x41 or get(N, 0x0C) == 0x4F then
              set(N, 0x72, 1)
              if get(A, 0x76) == 0 or get(A, 0x76) == 8 then
                if get(A, 0x72) ~= 0 then set(N, 0x76, 2)
                elseif get(B, 0x77) ~= 2 then set(N, 0x76, 2) end
              else
                copy(N, A, 0x76)
              end
            end
            copy(A, B, 0x77)
            if get(A, 0x76) == 0 or get(A, 0x76) == 8 then
              if (get(B, 0x6E) >> 4) & 1 ~= 0 then set(B, 0x72, 1) else copy(B, A, 0x72) end
              set(A, 0x72, 1); set(B, 0x76, 2)
            else
              copy(B, A, 0x76); set(B, 0x72, 1); set(A, 0x72, 1)
            end
          end
        elseif selector == 2 then
          if get(N, 0x0C) == 0x51 and get(N, 0x76) ~= 0 then
            set(B, 0x76, get(N, 0x76))
          else
            local c = get(A, 0x76)
            if (c == 8 or c == 0x20) and is(A, 0x47E8) and text.equal(A.text,state.assets:string(0x47EB)) then
              reading(A, b6D(B, 6) ~= 0 and 0x47ED or 0x47F0)
              default = true
            elseif get(A, 0x0F) ~= 0 then
              default = true
            elseif b6D(B, 1) ~= 0 then
              if c == 8 and not is(A, 0x480F) then
                set(B, 0x76, 2)
              else
                if is(A, 0x4812) then reading(A, 0x4817)
                elseif is(A, 0x481A) then
                  A.text = ""; set(A, 0x76, 4)
                end
                default = true
              end
            else
              if (c == 8 or c == 0x20) and (is(A, 0x47F2) or is(A, 0x47F5) or is(A, 0x47F8) or is(A, 0x47FD)) then
                reading(A, b6D(B, 6) ~= 0 and 0x4800 or 0x4803)
              end
              if is(A, 0x4805) then reading(A, b6D(B, 6) ~= 0 and 0x480A or 0x480C) end
              default = true
            end
          end
        elseif selector == 3 then
          copy(B, A, 0x72); copy(B, A, 0x77)
        elseif selector == 4 then
          copy(B, A, 0x74); copy(B, A, 0x72); copy(B, A, 0x77); default = true
        elseif selector == 5 then
          set(B, 0x76, 0x10)
        elseif selector == 6 then
          if get(A, 0x0C) == 0x4E and get(A, 0x0F) == 0x3D then copy(B, A, 0x76) else set(B, 0x76, 2) end
        elseif selector == 7 then
          local C = A
          if (E(si).tag or 0) ~= 0x4E and (E(si).class or 0) ~= 0x77 and (E(si).class or 0) ~= 0x50 then C = find_noun() end
          if C then copy(B, C, 0x76) end
        elseif selector == 8 or selector == 9 or selector == 15 then
          default = true
        elseif selector == 10 then
          set(B, 0x72, 1); copy(B, A, 0x77)
        elseif selector == 11 then
          if get(A, 0x76) == 0 then
            set(B, 0x76, 4)
          elseif get(B, 0x12) == 0x69 or get(B, 0x12) == 0x49 then
            reading(B, 0x481D); set(B, 0x0C, 0x44)
            count = rebuild_vector()
          elseif get(A, 0x76) ~= 8 then
            default = true
          elseif (get(A, 0x6E) >> 6) & 1 ~= 0 then
            set(B, 0x76, 4)
          else
            local t = (E(si + 1).tag or 0)
            set(B, 0x76, ('NIHORSQW'):find(string.char(t), 1, true) and 4 or 8)
            if get(B, 0x75) ~= 0 then A[0x243] = state.assets:string(0x4821) end
          end
        elseif selector == 12 then
          copy(A, B, 0x72); copy(A, B, 0x77)
          if tag == 0x50 then copy(A, B, 0x76) else copy(B, A, 0x76) end
        elseif selector == 13 then
          if get(B, 0x72) == 0 then
            set(A, 0x0C, 0x41); set(A, 0x72, 0); copy(B, A, 0x76); copy(A, B, 0x77)
            count = rebuild_vector()
          else
            local done = false
            if is(B, 0x4825) then
              local last = (A[0x12] or ''):byte(-1) or 0
              if last == 0x30 or last > 0x34 then
                reading(B, 0x482B); B[0x85] = 0xFFFF; done = true
              end
            end
            if not done then
              if get(A, 0x76) == 0 or get(A, 0x76) == 8 then
                if (get(B, 0x6E) >> 4) & 1 ~= 0 then set(B, 0x72, 1) else copy(B, A, 0x72) end
                set(B, 0x76, 2)
              else
                copy(B, A, 0x76); set(B, 0x72, 1)
              end
              if get(N, 0x0C) == 0x41 or get(N, 0x0C) == 0x4F then
                set(N, 0x72, 1)
                if get(A, 0x76) == 0 or get(A, 0x76) == 8 then
                  if get(A, 0x72) ~= 0 then set(N, 0x76, 2)
                  elseif get(B, 0x77) ~= 2 then set(N, 0x76, 2) end
                else
                  copy(N, A, 0x76)
                end
              end
            end
          end
        elseif selector == 14 then
          set(A, 0x72, 0); copy(A, B, 0x77)
        elseif selector == 16 then
          set(B, 0x76, get(A, 0x0F))
        elseif selector == 17 then
          local C = A
          if (E(si).class or 0) == 0x50 then C = find_noun() end
          if C then copy(B, C, 0x76); copy(B, C, 0x72); copy(B, C, 0x77) end
        elseif selector == 18 then
          set(B, 0x72, 1); default = true
        elseif selector == 19 then
          if get(B, 0x66) ~= 0x47 then copy(B, A, 0x73); copy(B, A, 0x7A); copy(B, A, 0x7B) end
          copy(B, A, 0x74); copy(B, A, 0x72); copy(B, A, 0x77); copy(B, A, 0x78)
        elseif selector == 20 then
          if get(A, 0x0F) == 0x77 then
            set(A, 0x72, 0); copy(A, B, 0x77); set(B, 0x76, get(N, 0x76))
          end
        elseif selector == 21 then
          if is(A, 0x482F) and b6D(B, 4) ~= 0 then
            reading(A, 0x4834); set(A, 0x0C, 0x69)
            rebuild_vector()
          end
        elseif selector == 22 then
          if get(A, 0x76) ~= 8 then
            default = true
          elseif b6D(B, 1) ~= 0 then
            if get(B, 0x72) == 0 and get(B, 0x77) == 2 then set(B, 0x76, 8)
            elseif get(B, 0x85) == 0x35 then set(B, 0x76, 8)
            else set(B, 0x76, 2) end
          else
            set(B, 0x76, 8)
          end
        elseif selector == 23 then
          if get(A, 0x76) == 0x10 or get(A, 0x76) == 0x20 then set(B, 0x75, 1) end
          default = true
        else
          default = true
        end
        if default then copy(B, A, 0x76) end
      end
      di = di + 1
    end
  end
  return 1
end
return agreement
