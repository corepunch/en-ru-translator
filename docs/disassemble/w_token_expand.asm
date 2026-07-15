; ============================================================================
; W-Token Expansion Handler (Morph Engine Type 12)
; LTPRO.EXE — r2 VA 0x1b1f4 (segment 0x1000)
; Disassembled via: r2 -e bin.relocs.apply=false -A -q -c 'pd 150 @ 0x1b1f4' LTPRO.EXE
; ============================================================================
;
; OVERVIEW: This handler walks the sub-constituent linked list of a W-tagged
; multi-word phrase token. It finds verb (V) and noun (N) heads and propagates
; morphological data (gender, number, case) from the noun sub-constituent to
; the W-token wrapper.
;
; THE W-TOKEN DOES NOT SPLIT INTO MULTIPLE OUTPUT TOKENS HERE. Instead, the
; wrapper token inherits the noun's morphology for proper Russian agreement.
; The actual verb/preposition sub-constituents are processed by OTHER morph
; engine type handlers (types for V, P, etc.) during their own pass.
;
; TOKEN STRUCTURE (within W-phrase linked list):
;   +0x00  word  far pointer to next token in linked list (segment)
;   +0x02  word  far pointer to next token in linked list (offset)
;   +0x04  word  far pointer to .RUS morphological data (segment)
;   +0x06  word  far pointer to .RUS morphological data (offset)
;   +0x0C  byte  grammatical tag (0x56='V', 0x4E='N', 0x4F='O')
;   +0x62  word  linked morphological source chain (segment)
;   +0x64  word  linked morphological source chain (offset)
;   +0x72  byte  morphological marker 1 (gender/case — copied N→W)
;   +0x74  byte  type marker (set=3 for O-tag chain traversal)  
;   +0x76  byte  status flag (set=4 when +0x7A is zero)
;   +0x77  byte  morphological marker 2 (copied N→W)
;   +0x78  byte  bit-flag byte (bit 2 cleared as cleanup)
;   +0x7A  byte  has-sub-constituents flag (non-zero = has sub-tokens)
;
; ALGORITHM:
; 1. Walk linked list of sub-tokens (0x1b1f9-0x1b234)
;    - Find 'V' (0x56) tag → save its far pointer
;    - Continue walking
;
; 2. If no V found or +0x7A flag is zero → exit (no expansion needed)
;
; 3. Walk linked list again, find 'N' (0x4E) tag (0x1b24f-0x1b265)
;    - This is the morphological anchor (head noun)
;
; 4. Copy morphological data noun → W-token wrapper (0x1b273-0x1b29f):
;    es:[W_tok + 0x72] = es:[N_tok + 0x72]   ; gender/case marker
;    es:[W_tok + 0x77] = es:[N_tok + 0x77]   ; form marker
;
; 5. Handle O-tag (demonstrative pronoun) sub-constituents:
;    - Set +0x72 = 0 for demonstratives (triggers different agreement)
;
; 6. Secondary pointer chain traversal for morphological source linking
;
; 7. Cleanup: clear bit 2 of +0x78 (visited flag)
;    - Jump to next-token advance (0x1c2cd)
;
; IMPLICATIONS FOR LUA IMPLEMENTATION:
; - When a W-token (e.g. "front door") is processed, the compiler must:
;   1. Find the noun head within the phrase
;   2. Copy the noun's gender/number/case to govern adjective agreement
;   3. Process sub-constituents (verb, preposition) through their own printers
; - The W-token does NOT produce multiple output words directly — each
;   sub-constituent is processed by its own printer during the compile loop
; - For packed forms like WVисходитьPРиз, the compiler should:
;   a. Extract and print the V form (verb printer)
;   b. Extract and print the P form (preposition printer)
;   as separate output tokens during the compile loop
; ============================================================================
