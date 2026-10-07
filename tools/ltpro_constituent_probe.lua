local matching = require 'core.matching'
for _, f in ipairs(dofile(assert(arg[1]))) do print(matching.match_constituents(f.cache or f.tags, f.start, f.pattern, f.tags)) end
