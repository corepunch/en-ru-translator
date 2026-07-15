local stream = require "core.token_stream"

local function assert_eq(a, b, msg)
  assert(a == b, (msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

-- new() creates a table with all metadata fields initialized
local ts = stream.new()
assert(type(ts) == "table")
assert(type(ts.caps) == "table")
assert(type(ts.phrases) == "table")
assert(type(ts.source) == "table")
assert(type(ts.component_caps) == "table")
assert(type(ts.tag) == "table")
assert(type(ts.derived_tag) == "table")
assert(type(ts.status) == "table")
assert(type(ts.prev) == "table")
assert(type(ts.next) == "table")
assert_eq(#ts, 0)

-- append / length / indexing
stream.append(ts, "Vговорить", { caps = false, phrases = false, source = "speak", component_caps = false })
stream.append(ts, "Nдом", { caps = true, phrases = false, source = "HOUSE", component_caps = false })
assert_eq(#ts, 2)
assert_eq(ts[1], "Vговорить")
assert_eq(ts[2], "Nдом")
assert_eq(ts.caps[1], false)
assert_eq(ts.caps[2], true)
assert_eq(ts.source[1], "speak")
assert_eq(ts.source[2], "HOUSE")
-- Dictionary entries are decoded immediately into the LTPRO-style node fields.
assert_eq(ts.tag[1], "V")
assert_eq(ts.derived_tag[1], "V")
assert_eq(ts.status[1], "w")
assert_eq(ts.next[1], 2)
assert_eq(ts.prev[2], 1)

-- metadata round-trip
local m = stream.metadata(ts, 1)
assert_eq(m.caps, false)
assert_eq(m.source, "speak")
assert_eq(m.phrases, false)

-- set_metadata mutates atomically
stream.set_metadata(ts, 1, { caps = "init", phrases = true, source = "Speak", component_caps = false })
local m2 = stream.metadata(ts, 1)
assert_eq(m2.caps, "init")
assert_eq(m2.phrases, true)
assert_eq(m2.source, "Speak")

-- insert shifts later tokens and metadata
stream.insert(ts, 1, "Tthe", { caps = false, phrases = false, source = "the", component_caps = false })
assert_eq(#ts, 3)
assert_eq(ts[1], "Tthe")
assert_eq(ts[2], "Vговорить")
assert_eq(ts[3], "Nдом")
assert_eq(ts.source[1], "the")
assert_eq(ts.source[2], "Speak")
assert_eq(ts.next[1], 2)
assert_eq(ts.prev[3], 2)

-- remove returns token+metadata, shifts remaining
local tok, meta = stream.remove(ts, 1)
assert_eq(tok, "Tthe")
assert_eq(meta.source, "the")
assert_eq(#ts, 2)
assert_eq(ts[1], "Vговорить")
assert_eq(ts.prev[1], false)
assert_eq(ts.next[1], 2)

-- A grammar rewrite changes the primary +0x0c-equivalent tag but retains the
-- dictionary-derived +0x66-equivalent tag on the same node.
stream.set_token(ts, 1, "Nречь")
assert_eq(ts.tag[1], "N")
assert_eq(ts.derived_tag[1], "V")

-- snapshot captures tokens and metadata by position list
local ts2 = stream.new()
stream.append(ts2, "A", { caps = false, phrases = false, source = "a", component_caps = false })
stream.append(ts2, "B", { caps = true,  phrases = false, source = "b", component_caps = false })
stream.append(ts2, "C", { caps = false, phrases = true,  source = "c", component_caps = false })
local snap = stream.snapshot(ts2, {3, 1})
assert_eq(#snap, 2)
assert_eq(snap[1].token, "C")
assert_eq(snap[1].metadata.source, "c")
assert_eq(snap[2].token, "A")
assert_eq(snap[2].metadata.source, "a")

-- write restores from snapshot entry
stream.write(ts2, 2, snap[1])
assert_eq(ts2[2], "C")
assert_eq(ts2.source[2], "c")

print("token_stream tests passed")
