-- Fixed native-instruction observations, independent of production-parser heuristics.
local matching = require 'core.matching'
local encode = require('core.encoding').encode
local function vector(tags)
  local v = {}
  for i = 1, #tags do v[i - 1] = {tag = tags:byte(i), source = 'word', lookup = 'original', reading = 'translation'} end
  return v
end
local function equal(actual, expected, message)
  assert(actual == expected, message .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
local function match(tags, pattern, expected, start)
  equal(matching.match(vector(tags), start or 1, pattern), expected, pattern .. ' on ' .. tags)
end

match('*ZN*', '*Z[?#]*', 0, 0)
match('*Z#*', '*Z[?#]*', 3, 0)
match('*NDV*', 'N<D>V', 3)
match('*NV*', 'N<D>V', 2)
match('*NV*', 'N~<D>V', 0) -- Native negated spans cannot be empty.
match('*NAV*', 'N~<D>V', 3)
match('*NDV*', 'N~<D>V', 0)
match('*NADVV*', 'N<$>V', 4)
match('*NADVV*', 'N<>V', 4)
match('*NVDVN*', 'N<$>V[N]', 0) -- No retry at the later V after the first anchor fails.
match('*N*', '$N', 1)
match('*DN*', '$N', 2)
match('*DDN*', '$N', 0) -- Bare $ skips at most one node.
match('*NN*', '~[$]N', 0) -- [$] retains pending negation.
match('*NV*', '~[$]N', 2)
local ok = pcall(matching.match, vector('*NN*'), 1, '[N`word`]')
equal(ok, false, 'unused embedded alternatives fail explicitly')

local v = vector('*NN*')
v[1].source, v[1].lookup, v[1].reading = 'Work', 'EXACT', encode('единица(мес)')
equal(matching.match(v, 1, '`work`'), 1, 'ASCII-insensitive +12 comparison')
equal(matching.match(v, 1, '`EXACT`'), 1, 'exact +9C comparison')
equal(matching.match(v, 1, '`exact`'), 0, '+9C is case-sensitive')
equal(matching.match(v, 1, encode('!мес!')), 1, 'annotation suffix search')
equal(matching.match(v, 1, encode('!мес)!')), 0, 'bang operator appends closing parenthesis')
v[1].tag, v[1].reading = string.byte('V'), 'Nnoun'
equal(matching.match(v, 1, 'N'), 0, 'tag matching ignores packed translation alternatives')
equal(matching.replace(v, 1, 1, 'V', 'N'), 0, 'tag replacement keeps vector size')
equal(v[1].tag, string.byte('N'), 'native action retags without a noun reading')
equal(v[1].previous_tag, string.byte('V'), 'prior tag retained at +66')
equal(v[1].reading, 'Nnoun', 'retag does not resolve lexical text')
matching.replace(v, 1, 1, 'N', '@')
equal(v[1].previous_tag, string.byte('V'), '@ leaves previous tag untouched')
matching.replace(v, 1, 1, 'N', encode('`Pк`'))
equal(v[1].tag, string.byte('P'), 'literal payload optional tag')
equal(v[1].reading, encode('к'), 'literal writes text field')
matching.replace(v, 1, 1, 'P', encode('`@в`'))
equal(v[1].tag, string.byte('P'), 'literal @ keeps current tag')
equal(v[1].reading, encode('в'), 'literal @ writes only text')
equal(matching.replace(v, 1, 1, 'P', ' '), 1, 'space requests subsequent vector compaction')
equal(v[1].tag, 32, 'native deletion has no synthetic q marker')

v = vector('*NDVNN*')
matching.replace(v, 1, 5, 'N<D>VNN', '@$@AN')
equal(v[3].tag, string.byte('A'), '@ in the plain anchor run does not advance node')
equal(v[4].tag, string.byte('N'), 'following action advances after retag')
equal(v[5].previous_tag, nil, 'unvisited node is unchanged')
equal(matching.match_constituents('*VN*', 1, '.N'), 2, 'T8 dot consumes one constituent')
equal(matching.match_constituents('*VN*', 1, '$N'), 0, 'T8 dollar is not lexical optional skip')
equal(matching.match_constituents('*NV*', 1, '~.N'), 2, 'T8 dot preserves pending negation')
equal(matching.match_constituents('*NAV*', 1, 'N<$>V'), 3, 'T8 span uses constituent tags')
print('native grammar tests passed')
