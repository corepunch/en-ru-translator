-- CP866 classification and string operations used by the linguistic stages.
local text = {}
function text.is_upper_cyrillic(c) return c >= 0x80 and c < 0xA0 or c == 0xF0 end
function text.is_lower_cyrillic(c) return c >= 0xA0 and c < 0xB0 or c >= 0xE0 and c < 0xF2 end
function text.is_cyrillic(c) return c >= 0x80 and c < 0xB0 or c >= 0xE0 and c < 0xF2 end
function text.digit(c) return c >= 48 and c <= 57 end
function text.alpha(c) return c >= 65 and c <= 90 or c >= 97 and c <= 122 end
function text.upper_ascii(c) return c >= 65 and c <= 90 end
function text.equal(a,b) return a:upper() == b:upper() end
function text.ends(word, suffix, length)
  length = length or #word
  return length >= #suffix and word:sub(length-#suffix+1,length) == suffix
end
function text.byte(word, index) return index >= 0 and word:byte(index+1) or 0 end
function text.put(word, index, c)
  assert(index >= 0, 'negative text index')
  if c == 0 then return word:sub(1,index) end
  return word:sub(1,index) .. string.char(c) .. word:sub(index+2)
end
return text
