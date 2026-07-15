; ============================================================================
; Token/Dictionary Lookup & Multi-Word Phrase Matching
; LTPRO.EXE — r2 VA 0xa96b
; Called from: fcn.0000b0ff (rule engine) @ 0xcdf8, 0xd367, 0xdc95
;              fcn.0000bde8 (main entry) @ 0xbf05
; ============================================================================
;
; OVERVIEW: Matches English input words against dictionary entries by walking
; a linked list of dictionary nodes (NOT a trie). Supports multi-word phrase
; matching by chaining nodes word-by-word. Writes `\word` back-reference
; escapes into the output buffer when irregular forms match their base entry.
;
; NODE FORMAT (6 bytes):
;   +0: far ptr → child/sub-word node (for multi-word phrases)
;   +4: far ptr → tag byte + Russian text data
;
; ALGORITHM:
;
; 1. Initialize node pointer (0xa96b):
;    - Sets [bp-4] = 0x930 (dictionary root node)
;    - Sets SI = 0 (output position)
;
; 2. Tag dispatch loop (0xa985+):
;    Load tag byte from current node data, dispatch on value:
;
;    - 'M' (0x4D): Phrase-end marker — finish successfully
;      Set SI=3, null-terminate output
;
;    - 'T' (0x54): Determiner — check context table for "the"/"a"/"an"
;      Multiple entries at 0xbd1, 0xbd9, 0xbe0, 0xbe7, 0xbee
;
;    - 'X' (0x58): Auxiliary verb "do" — 5 forms:
;      do, does, did, doing, done
;
;    - default (0xab2c): General word match handler
;
; 3. Word matching (fcn.00021042):
;    Called with (node_word_data, input_buffer, position)
;    Returns match length. If match, SI advances and
;    next sub-word node is loaded from es:[bx+4]
;
; 4. Multi-word phrase building:
;    - Match first word → follow es:[bx+4] to next sub-node
;    - Match second word → follow es:[bx+4] again
;    - Continue until 'M' (phrase-end) marker
;    Each matched word advances SI by its length
;
; 5. Back-reference escape (0xaab6):
;    mov byte es:[arg_6h + si], 0x27    ; '\''
;    Writes backslash into output buffer at position SI
;
;    This creates the `\word` back-reference in packed tokens:
;    e.g. "came" → hприходить\come  (escape links to base "come")
;
;    Also clears es:[arg_ch + 0xb] to 0 (reset flag)
;
; 6. Context table iteration (X-verb path):
;    Loads context table at [0x9e4]
;    Iterates pairs indexed by di*4
;    Each pair: far pointer to Russian phrase data
;
; HOW BACK-REFERENCES ENABLE MULTI-WORD MATCHING:
;
; When LTGOLD processes "came from a distant city":
;   1. Lookup "came" → matches hприходить\come
;      - `\come` back-reference stored in token
;      - Means: "this is a form of 'come'"
;
;   2. Lookup "from" → current dict root is "came"
;      - No "from" sub-node under "came"
;      - BUT token has `\come` back-reference
;      - Follow back-reference: lookup "come" → has "from" sub-node
;      - "come from" = WVисходитьPРиз (packed verb+prep form)
;
;   3. Combined token replaces original "came" token in output
;      - Russian text = исходитьPРиз (packed V + P forms)
;      - Tag preserved from original match
;
; IMPLICATIONS FOR LUA IMPLEMENTATION:
;
;   1. After tokenizing a word, store the `\word` back-reference
;      if present in the __lex token data
;
;   2. When the next word has no direct multi-word match under the
;      current en_ru node, check for back-reference chain:
;      - Extract back-reference word from prev.__lex
;      - Look up en_ru[backref_word][next_word]
;      - If found, use that multi-word entry
;
;   3. The packed token format (W V Russian P Russian) needs expansion:
;      - W-token wrapper: carries morphological context from head noun
;      - Sub-constituents (V, P): processed by their own printers
;      - The TYPE-12 morph handler propagates noun data to W wrapper
; ============================================================================
