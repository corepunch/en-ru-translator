local list = {}

local function car(c) return c[1] end
local function cdr(c) return c[2] end

local function to_lisp(arr, i)
  i = i or 1
  if i > #arr then return nil end
  return { arr[i], to_lisp(arr, i + 1) }
end

return list