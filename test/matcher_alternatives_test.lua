local matching=require 'core.matching'
local count=0
for _,tag in ipairs({'A','N','V','D'}) do
  for _,source in ipairs({'target','TARGET','miss'}) do
    for _,lookup in ipairs({'target','miss',''}) do
      for _,reading in ipairs({'noun(label)','noun(other)',''}) do
        local vector={[0]={tag=42,source='*'},[1]={tag=tag:byte(),source=source,lookup=lookup,reading=reading},[2]={tag=42,source='*'}}
        local forms={
          {'[A`target`]',tag=='A' or source:lower()=='target' or lookup=='target'},
          {'[N!label!]',tag=='N' or reading=='noun(label)'},
          {'[`target`!label!]',source:lower()=='target' or lookup=='target' or reading=='noun(label)'},
        }
        for _,form in ipairs(forms) do
          assert((matching.match(vector,1,form[1])~=0)==form[2])
          assert((matching.match(vector,1,'~'..form[1])~=0)==not form[2])
          count=count+2
        end
      end
    end
  end
end
for _,anchor in ipairs({'[A`target`]','[A!label!]','[`target``other`]','[A`absent`!label!]'}) do
  local vector={
    [0]={tag=42,source='*'},[1]={tag=78,source='head'},
    [2]={tag=68,source='skip'},[3]={tag=86,source='target',reading='noun(label)'},
    [4]={tag=78,source='tail'},[5]={tag=42,source='*'},
  }
  local pattern='N<D>'..anchor..'N'
  assert(matching.match(vector,1,pattern)==4)
  matching.replace(vector,1,4,pattern,'@$AJ')
  assert(vector[2].tag==68 and vector[3].tag==65 and vector[4].tag==74,anchor)
end
assert(count==648)
print('matcher_alternatives_test: passed ('..count..' combinations plus replacement anchors)')
