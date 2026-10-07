local readings=require 'core.ltpro.readings'
local cases=dofile(assert(arg[1]))
local fields={0x0B,0x0C,0x0F,0x66,0x68,0x6A,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79}
for _,case in ipairs(cases) do
  local node={}
  for _,at in ipairs(fields) do node[at]=case.initial[at] or 0 end
  node[0x0C]=case.tag:byte()
  local consumed=readings.decode(node,case.payload)
  local values={tostring(consumed)}
  for _,at in ipairs(fields) do values[#values+1]=tostring(node[at]) end
  values[#values+1]=(node[0x11C]:gsub('.',function(c)return string.format('%02x',c:byte())end))
  print(table.concat(values,','))
end
