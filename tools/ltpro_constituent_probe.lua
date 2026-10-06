local matcher = require 'core.ltpro.constituent_matcher'
for _, f in ipairs(dofile(assert(arg[1]))) do print(matcher.match(f.cache or f.tags, f.start, f.pattern, f.tags)) end
