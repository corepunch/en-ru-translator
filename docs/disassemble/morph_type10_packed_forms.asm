; ============================================================================
; Morph Engine Type-10: Packed Form Expansion (r2 VA 0x15000)
; LTPRO.EXE — overlay segment 0x1000, type dispatch at CS:0x0d49
; ============================================================================
;
; PURPOSE: Expands compressed Russian morphological data in packed byte
; sequences. Handles V+P (verb+preposition) packed forms and propagates
; morphological flags from source to destination tokens.
;
; FLAG PROPAGATION (0x4FE8-0x503C):
;   Copies from source [bp-0xc] to destination [bp-0x10]:
;     +0x7a → +0x7a   (sub-constituent flag)
;     +0x7b → +0x7b   (propagated agreement flag)
;     +0x74 → +0x74   (morphological flag)
;     +0x72 → +0x72   (gender/case agreement flag)
;     +0x77 → +0x77   (aspect/government flag)
;     +0x78 → +0x78   (additional flag byte)
;
; w-TAGGED SUB-FORM EXPANSION (0x503F-0x5062):
;   Trigger: source +0x0f == 0x77 ('w' = sub-form marker)
;   - Clear source +0x72 (agreement reset)
;   - Copy dest +0x77 → source +0x77 (aspect propagation)
;   - Jump to expansion routine at 0x14876
;
; V+P PACKED VERB FORM (0x5065-0x50C8):
;   - Search for "H/" pattern at source +0x12
;   - Check dest +0x6d bit 4 (verb+preposition ambiguity)
;   - Search packed text for "4H" marker
;   - Mark token +0xc = 'i' (inflected with preposition frame)
;   - Call text expansion (0x1313e)
;
; CONSTITUENT TYPE RESOLUTION (0x50CB-0x515D):
;   +0x76 values:
;     0x02 = post-nominal adjective (follows noun)
;     0x04 = standalone (no noun dependency)
;     0x08 = pre-nominal adjective (precedes noun)
;     0x10 = special constituent type
;     0x20 = another special (triggers +0x75=1 = processed)
;
;   Branch A: source +0x76==8 AND dest +0x6d bit1 → keep pre-nominal (8)
;   Branch B: ambiguity AND +0x72==0 AND +0x77==2 → pre-nominal (8)
;   Branch C: dest +0x85 (paradigm) == 53 → pre-nominal (8), else post-nominal (2)
;   Branch D: source +0x76 has bit4/bit5 → mark dest +0x75=1 (processed)
;
; LUA EQUIVALENT:
;   Our expand_phrase_tokens already splits W-tokens into sub-constituents.
;   What's missing: flag propagation between sub-constituents during expansion.
;   When a W-token like WAэлектронныйNперевод is expanded, the N sub-token's
;   flags (+0x72, +0x77) should be propagated to the A sub-token.
;   We already propagate ts.context[i] (+0x72). Need to add ts.flags[i] (+0x77).
; ============================================================================
