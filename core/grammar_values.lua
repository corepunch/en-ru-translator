-- Grammar values retained by the rule language and original dictionaries.
-- Number, aspect and tense stay numeric: some rules distinguish more than two values.
return {
  byte_mask = 0xFF,
  case = {nominative = 0, genitive = 2, dative = 4, accusative = 8,
    instrumental = 0x10, prepositional = 0x20},
  tense = {present = 0, past = 1, future = 2},
  aspect = {imperfective = 0, perfective = 1},
  verb_flags = {conditional = 0x02, imperative = 0x04},
}
