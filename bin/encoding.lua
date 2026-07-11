local encoding = require "encoding"

-- This shell is deliberately limited to transport concerns; conversion logic
-- remains reusable through require("encoding").
local mode = arg[1]
if mode ~= "encode" and mode ~= "decode" then
  io.stderr:write("usage: lua bin/encoding.lua encode|decode [text]\n")
  os.exit(2)
end

local input = arg[2] or io.read("*a")
io.write(mode == "encode" and encoding.encode(input) or encoding.decode(input))
