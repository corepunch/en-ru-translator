; ============================================================================
; LTPRO W-Token Complete Lifecycle — Disassembly Findings
; ============================================================================
;
; Tokens in LTPRO are ~0x11c-byte near-pointer structs with linked-list chains.
; W-tokens have a distinct lifecycle that our Lua implementation approximates
; but doesn't fully replicate.
;
; STAGE 1: DICTIONARY LOADING
; ==========================
; Dictionary entries like "front door*NNWAпередняяNдверь" are stored as-is.
; The W tag byte is NOT created during loading — it's embedded in the packed
; grammatical-tag string. Entry goes through dict_entry_parse at 0xbde8,
; which calls strchr('*') at 0x3cd4 to split word from tag+Russian.
; No token struct allocation happens here.
;
; STAGE 2: TOKENIZATION (main_translate at 0xcd5c)
; =================================================
; Input words are looked up via the token lookup function at 0xa96b, which
; walks linked dictionary nodes. Multi-word phrases match word-by-word through
; chained node pointers. Back-references (\word) are written at 0xaab6:
;   mov byte es:[buffer + si], 0x27   ; '\'
; This stores the escape character that links inflected forms to base entries.
;
; STAGE 3: RULE ENGINE (0xb0ff calling T1-T8 tables)
; ===================================================
; W-prefixed tokens pass through the rule engine with special handling:
; - tag_matches compares W-tokens case-insensitively (W=0x57, w=0x77)
; - T7 rules (35 guards) set CONSTITUENT FLAGS on tokens (NP=0x06, PP=0x02)
; - T8 rules (83 guards) finalize constituent types for morphology
; - Rule actions @$W create W-token wrappers around sub-constituents
;
; STAGE 4: MORPH ENGINE (0x1df0f, 15 morph-table records)
; =========================================================
; Type dispatch via jump-table at CS:0x2318 (21 handlers):
;
;   Type-10 (0x15000): Packed form expansion (w-tagged tokens)
;     - Handles lowercase-w tokens (w=0x77) at +0x0f
;     - Copies +0x77 (constituent modifier flags) from wrapper to sub-constituents
;     - Sets +0x76 (constituent type) based on +0x7a (has-sub-constituents)
;     - Splits V+P packed forms into separate output words
;     - Shared tail at 0x14876: reads output buffer, processes constituent types
;
;   Type-12 (0x1b1f4): W-token sub-constituent expansion
;     - Walks linked list of sub-constituent tokens
;     - Finds V (0x56) and N (0x4e) heads within the phrase
;     - CRITICAL: copies +0x72 and +0x77 from head NOUN to W-wrapper
;       mov al, es:[N_token + 0x72]  ; case/gender/conjunction
;       mov es:[W_token + 0x72], al
;       mov al, es:[N_token + 0x77]  ; constituent-type / w-modifier
;       mov es:[W_token + 0x77], al
;     - Then copies from W-wrapper to ALL sub-constituents:
;       mov es:[V_token + 0x72], al  ; propagate to verb
;       mov es:[A_token + 0x72], al  ; propagate to adjective
;     - Sets +0x76 = 4 on sub-tokens when +0x7a is non-zero
;     - Handles O-tag (demonstrative pronoun) with special +0x72=0
;
;   Type-13 (0x1d302): Dynamic W-token creation
;     - Creates W tokens from t-tagged (segment-boundary) tokens
;     - Allocates new far-pointer struct via 0x01baa
;     - Writes 'W' (0x57) to +0x02 of the new token
;     - Chains with back-reference words at +0x94/+0x96
;     - Filters: skips if token already W/P/I/K/G
;
;   Type-17 (0x136d8): Output assembly
;     - Iterates token stream, expands [...] bracket references
;     - Copies text to output buffer at +0x11c
;     - Handles ~ (0x7e) clause boundaries
;
; STAGE 5: OUTPUT (0x1313:0x000e, segment-0 routine)
; ===================================================
; For each morph-processed token, writes the Russian text to the output buffer.
; Handles case-agreement application, multiple meanings markup, and punctuation.
;
; ============================================================================
; TOKEN STRUCTURE FIELDS (0x11c bytes each)
; ============================================================================
; Offset  Size   Purpose
; ------  ----   -------
; +0x00   word   Far pointer: segment of linked-list chain
; +0x02   word   Far pointer: offset of linked-list chain
; +0x04   word   Far pointer: .RUS morphological data (segment)
; +0x06   word   Far pointer: .RUS morphological data (offset)
; +0x0c   byte   Primary tag (N=0x4e, V=0x56, A=0x41, W=0x57, etc.)
; +0x0f   byte   Status modifier (g=genitive, /=partitive, %=pct)
; +0x66   byte   Secondary/derived-form tag (set by dict_entry_parse)
; +0x72   byte   Context marker 1 (case/gender/copula state)
;                 Copied from head noun → W-wrapper → sub-constituents
; +0x74   byte   Secondary type (compared to 'K'=0x4b in T3 dispatch)
; +0x75   byte   Set=1 when token's +0xc is 'K' (negation marker)
; +0x76   byte   Constituent-type marker
;                 0x02=PP, 0x06=NP, 0x03=VP, 0x01=numNP
;                 Set=4 by Type-12 for W-sub-constituents
; +0x77   byte   Constituent/w-modifier flags
;                 Copied from head noun → W-wrapper → sub-constituents
; +0x78   byte   Bit-flag byte (bit 2 cleared as cleanup in type-12)
; +0x7a   byte   Has-sub-constituents flag (non-zero = has sub-tokens)
; +0x94   word   Back-reference word offset (for W-token creation by type-13)
; +0x96   word   Back-reference word segment
;
; ============================================================================
; EQUIVALENT IN OUR LUA IMPLEMENTATION
; ============================================================================
;
; Our token_stream.lua already has fields named after these offsets:
;   ts.tag[i]              → +0x0c
;   ts.status[i]           → +0x0f
;   ts.derived_tag[i]      → +0x66
;   ts.context[i]          → +0x72  (currently unused by compiler)
;   ts.secondary_type[i]   → +0x74
;   ts.flags[i]            → +0x77  (currently unused by compiler)
;   ts.constituent_type[i] → +0x76  (used by T7/T8 guards only)
;
; CRITICAL GAP: The compiler does NOT read ts.context[i] or ts.flags[i] for
; case/gender agreement decisions. It uses the 'e' context object instead, which
; is set by individual printers (P, N) but not propagated through W-phrases.
;
; WHAT WE NEED TO BUILD:
; 1. When expand_phrase_tokens splits W-tokens, propagate the head noun's
;    gender/number to adjective sub-tokens via ts.context[i] and ts.flags[i]
; 2. In the compiler's A printer, check ts.context for inherited gender/number
;    when the next token is not an N (e.g., adjective at end of phrase)
; 3. In the compiler's N printer, write gender/number to ts.context of the
;    expansion's parent (so adjectives before the noun can read it)
; ============================================================================
