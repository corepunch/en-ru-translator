# CONTINUE.md — State & Plan for LTPRO Reverse-Engineering

## Objective

Replicate LTPRO.EXE's translation behavior in Lua to pass 300 regression tests
(ltgold100 + ltgold200). **Current: 214/300 (94/100 + 120/200)**.

## Approach

1. Disassemble LTPRO.EXE with radare2 (`/opt/homebrew/bin/r2`)
2. Annotate morph-engine type handlers in `docs/disassemble/`
3. Replicate the flag-propagation logic in `core/parser.lua`, `core/compiler.lua`

## Key Constants

```
LTPRO.EXE:         LTGOLD/LTPRO.EXE  (207714 bytes, DOS 16-bit)
VSHIFT:            0x3A00   (r2 vaddr + VSHIFT = file offset)
DAT_BASE:          0x26750  (data segment base in file)
Morph engine VA:   0x1df0f  (post-T8 morphology, 21 type handlers)
Type jump table:   CS:0x2318 in overlay 0x1000 (r2 VA 0x12318)

r2 command template:
  cd LTGOLD && r2 -e bin.relocs.apply=false -A -q -c 'pd 200 @ VA' LTPRO.EXE
```

## Test Scores

```
ltgold100: 94/100  (baseline 94, stable)
ltgold200: 120/200 (baseline 107, +13)
Total:     214/300
```

## What Was Done This Session (+13 on ltgold200)

### 1. X003 pro-verb "does" conjugation (+2)
**File:** `core/compiler.lua:1918-1927`
When X003 (copula "is/do") is at end of sentence (followed by "."), conjugate "делать"
based on subject pronoun instead of outputting "-". Detects person/number from preceding
R token. Fixes T4-ASMUCH: "He reads as much as she does" → "Он читает столько же она делает."

### 2. Reflexive double-ся fix (+1)
**File:** `core/compiler.lua:814-828, 1098-1117`
Both E printer and V printer agent detection now check if the stem is reflexive
(CP866 bytes 0xE1/0xEF at end of extracted stem) before appending reflexive suffix.
Uses same CP866 byte table as `paradigms.verb()`. Fixes "The price rose by ten percent"
→ "Цена поднималась десятью процентами." (was double "сь")

### 3. Compound subject plural (+1)
**File:** `core/compiler.lua:766-772`
When the subject noun (N tag) is found by backward scan, continue scanning backward
for a conjunction (C tag) before another noun/pronoun. If found, mark as plural.
Fixes "Both the man and the woman spoke" → "Как человек так и женщина говорили."

### 4. V infinitive after infinitive particle (+1)
**File:** `core/compiler.lua:1104-1108`
After a V token ending with 'b' (infinitive particle, e.g. Vучитьсяb), the next V
stays infinitive. Fixes "She is learning to speak Russian" → "Она учится говорить Русского."

### 5. Name transliteration from LTPRO table (+1)
**File:** `core/compiler.lua:9-72, 1871-1878`
Added `transliterate_name()` function using the LTPRO transliteration table found at
offset 0x32602 in LTPRO.EXE. Table maps CP866 Cyrillic (А-Я) to Latin transliteration
(A,B,V,G,D,E,J,Z,I,J,K,L,M,N,O,P,R,S,T,U,F,H,C,e,d,f,J,Y,J,E,c,b).
Lowercase letters (b-f) index into multi-char table (YA,IU,SH,CH,SC).
The `#` printer now calls `transliterate_name()` when the Russian form is empty.
Fixes T5-GENNAME: "The report of Anna was praised" → "Сообщение Анна было похвалено."

### 6. X1xx embedded verb conjugation (+1)
**File:** `core/compiler.lua:2079-2094`
When X1xx (past copula) has an embedded verb that is NOT "быть" (the copula itself),
conjugate the embedded verb as past tense instead of outputting the copula form.
Detects embedded verb via `utils.extract_form()` and checks against "быть".
Fixes T4-BOTH: "Both he and she were present" → "Оба он и она присутствовала."

## TODO — Remaining +7 to reach +20 target (127/200)

### Quick wins (dictionary/annotation fixes)
- **T4-NN "loudly"**: Missing annotation {1.шумный} — add dictionary entry
- **T4-HYPH "Был"**: Capitalization diff — expected "Был" (capital) but we output "был" (lowercase). Likely test data issue.
- **T4-EITHER "either"**: Maps to "Также" (also) but expected "Каждый" (each). Different meaning.
- **T4-SEE "See page twelve"**: Maps to "Уви-" (видеть) but expected "Смотри" (смотреть imperative). Different verb.
- **T2-MODAL "in Russian"**: Preposition "в" vs expected "на". Russian idiom "на русском".

### Medium complexity (grammar rules)
- **T6-ORD "prize"**: Z→V rule fires on "the 4th prize" making "prize" a verb instead of noun.
- **T6-NUM case government**: Multiple case agreement differences after numerals.
- **T2-PERF "before" tense**: Russian requires future tense after "прежде чем" (before).
- **T2-CHAIN "could have been"**: Missing "бы" conditional particle.

### Hard (parser-level)
- **T1-CLAUSE**: 7 failures — complex clause connectives.
- **T3-GER**: 5 failures — gerund constructions.
- **T4-BOTH "both reads and writes"**: "оба читают и пишут" vs "как чтение так и пишет".
- **T4-NOTAS**: "not as...as" construction broken.

## Discovered Behaviors

### Transliteration table at 0x32602 in LTPRO.EXE
Maps CP866 Cyrillic (0x80-0x9F) to Latin transliteration:
- Single chars: А=A, Б=B, В=V, Г=G, Д=D, Е=E, Ж=J, З=Z, И=I, Й=J, К=K, Л=L, М=M, Н=N, О=O, П=P, Р=R, С=S, Т=T, У=U, Ф=F, Х=H, Ц=C, Ъ=J, Ы=Y, Ь=J, Э=E
- Multi-char (via lowercase indices b-f): Ч=CH, Ш=SH, Щ=SC, Ю=IU, Я=YA

### Aspect flag convention
```
byte2 & 2 == 0 → imperfective (писать, читать, прибывать, оставаться)
byte2 & 2 == 2 → perfective   (написать, прочитать, прибыть, остаться)
```

## Running Tests

```sh
lua test/ltgold100_test.lua        # 94/100
lua test/ltgold200_test.lua        # 120/200
```
