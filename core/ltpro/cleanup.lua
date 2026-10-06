-- LTPRO 12DC:0005, file 167C5..16AE3. Also called before T2 for questions.
local nodes=require 'core.ltpro.nodes'
local matcher=require 'core.ltpro.matcher'
local replacement=require 'core.ltpro.replacement'
local encoding=require 'core.encoding'
local rules=require 'core.rules'
local cleanup={}
local function tag(n) return string.char(n[0x0C]) end
function cleanup.run(root)
  local vector,count,state
  local removed=0
  local function rebuild()
    vector,count=nodes.vector(root)
    local tags={}
    for i=0,count-1 do tags[#tags+1]=tag(vector[i]) end
    state={tags=table.concat(tags)}
  end
  rebuild()
  for _,rule in ipairs(rules[7]) do
    local handler,pattern,action=table.unpack(rule)
    pattern=encoding.encode(pattern);action=action and encoding.encode(action)
    local first=1
    while first<count-1 do
      local last=matcher.match(vector,first,pattern,state.tags)
      if last~=0 then
        local head,tail=vector[first],vector[last]
        if handler==1 then
          for _,at in ipairs({0x72,0x73,0x74}) do tail[at]=head[at] or 0 end
          if tag(vector[first-1])=='Z' then vector[first-1][0x0C]=0x4E end
          last=count
        elseif handler==8 then
          local following=head.next
          local before,previous=vector[first-1],vector[last-1]
          if tag(following)=='K' then before.next=following.next; following.next=tail
          else before.next=head.next; head.next=tail end
          previous.next=head
          local old_count=count
          rebuild();first=old_count
          goto advance
        elseif handler==11 then
          local auxiliary=vector[first+1]
          if (auxiliary[0x73] or 0)==0 and (auxiliary[0x74] or 0)~=0 then
            auxiliary[0x0C]=0x20
            local j=first+2
            while j<last and tag(vector[j])~='*' do
              if tag(vector[j])=='Z' then vector[j][0x0C]=0x4E end
              j=j+1
            end
          end
          rebuild();first=count
          goto advance
        elseif handler~=0 then error('unported native cleanup selector '..handler) end
        removed=replacement.apply(vector,first,last,pattern,action,state)
        first=last
      end
      ::advance::
      first=first+1
    end
    if removed~=0 then rebuild();removed=0 end
  end
  return {root=root,vector=vector,count=count,tags=state.tags,removed=removed}
end
return cleanup
