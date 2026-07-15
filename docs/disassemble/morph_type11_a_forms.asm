; ============================================================================
; Morph Engine Type-11: Pre-nominal A-tagged W Forms (r2 VA 0x15e8b)
; LTPRO.EXE — overlay segment 0x1000, type dispatch at CS:0x0d49
; ============================================================================
;
; PURPOSE: Processes adjective/participle forms within pre-nominal W structures.
; When a W-sub-form has an 'A' tag and modifies a noun, this handler builds
; the correct inflected Russian adjective form with gender/number/case agreement.
;
; ELIGIBILITY CHECK (0x5E81-0x5EB8):
;   Three conditions must all match:
;   1. result token[0] == 'N' (noun head)
;   2. arg token +0x66 == 'A' (resolved tag = adjective)
;   3. arg token +0x0f == 0x77 ('w') or 0x57 ('W') (sub-form marker)
;   → On match: set result[0] = 'A', arg +0xc = 'A', arg +0x76 = 0
;
; PARTICIPLE DETECTION (0x5EE2-0x5F25):
;   When result == 'A', check arg +0x66 for verbal tags:
;   - 'E' (past participle) → build pre-nominal form
;   - 'e' (ambiguous participle) → build pre-nominal form
;   - 'V' (verb) → build pre-nominal form
;   - 'G' (gerund) → build pre-nominal form
;   If none match, fall through to text output
;
; PACKED FORM DECODING (0x602E-0x610A):
;   Three passes that decode bytes from packed stream into morphological data:
;   Pass 1: → +0x68 bits 0-5 (gender/case field 1) + bit 6 flag
;   Pass 2: → +0x6a bit 6 (agreement flag)
;   Pass 3: → +0x6a bits 0-5 (gender/case field 2)
;
;   Each byte in the packed stream is in range 0x30-0x6F (subtract 0x30 = 6 bits).
;   A grammar property table at CS:[byte - 0x4089] determines if the byte has
;   agreement data (bit 1 / test 2).
;
; FLAG HANDLING:
;   +0x72: Cleared when +0x66 == 'Z' (removes verb/noun ambiguity)
;   +0x77: Set to 1 when +0xc != 'E' (marks non-past-participle verbs)
;   +0x75: Set to 1 when token has been processed (has output)
;   +0xc: Set to 'A' to mark dictionary origin as adjective
;
; NUMERAL HANDLING:
;   'I' (cardinal numeral) in 'A' context with >= 3 text matches:
;   → Retagged as 'A' for Russian agreement (один/одна/одно)
;
; LUA EQUIVALENT:
;   When expand_phrase_tokens creates an A-tagged sub-token from a W-phrase:
;   - Check if the source had verbal tag (E/e/V/G) → force participle form
;   - Propagate gender/case flags using the packed form encoding
;   This would fix participle adjective forms in relative clauses.
; ============================================================================
