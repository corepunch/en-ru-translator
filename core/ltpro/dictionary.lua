-- Lossless DIC ingestion for the native compatibility path. Record order,
-- annotations, periods, W prefixes, duplicate entries and back-references survive.
-- Search/merge policies are separate from byte ingestion.
local dictionary={}
function dictionary.from_bytes(bytes)
  local result={bytes=bytes,records={},by_key={},unparsed={}}
  local start=1
  while start<=#bytes do
    local finish=bytes:find('\n',start,true) or (#bytes+1)
    local raw=bytes:sub(start,finish-1)
    local line=raw:gsub('\r$','')
    local star=line:find('*',1,true)
    if star then
      local record={key=line:sub(1,star-1),value=line:sub(star+1),raw=raw,offset=start-1}
      result.records[#result.records+1]=record
      result.by_key[record.key]=result.by_key[record.key] or {}
      local list=result.by_key[record.key];list[#list+1]=record
    else result.unparsed[#result.unparsed+1]={raw=raw,offset=start-1} end
    start=finish+1
  end
  return result
end
return dictionary
