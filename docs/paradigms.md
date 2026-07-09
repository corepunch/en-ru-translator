# Morphological Paradigms

Russian inflection tables extracted from LTGOLD (`paradigms.lua`). Each table maps
paradigm IDs (referenced by dictionary codes) to suffix patterns. The first number
in each entry is the **suffix length** — how many characters to trim from the stem
before applying the paradigm.

See [Dictionary Code Structure](dictionary.md) for how paradigm IDs are stored.

## Noun Paradigms (`paradigms.nouns`)

Structure: `paradigms.nouns[gender][paradigm_id] = { suffix_len, "forms" }`

- **Gender index:** 1=neutral (средний), 2=male (мужской), 3=female (женский)
- **Paradigm ID:** 0-based, referenced by `byte(4)&~0x80` from `BASE.RUS`
- **Suffix length:** Number of CP866 bytes to cut from the end of the stem
- **Forms:** Space-separated, 12 forms total:

```
Имн ед  Род ед  Дат ед  Вин ед  Тв ед  Пр ед   Имн мн  Род мн  Дат мн  Вин мн  Тв мн  Пр мн
  1        2        3        4        5        6        7        8        9       10      11      12
```

**Example:** `{02, "ка ку ко ком ке ки ек кам ки ками ках"}`
- Suffix length 2: stem "стол" (4 bytes) → cut 2 → "ст"
- Form 1 (nom.sg): "ст" + "ол" = "стол" (special: form 1 or `=` = use original stem)
- Form 2 (gen.sg): "ст" + "ол" → stem + suffix from `BASE.RUS`
- Actually: the suffixes are **full endings**, not additions. The paradigm
  replaces the last N bytes of the dictionary stem with the suffix.

**`=` handling:** If a suffix is `=`, the original stem is used unchanged (invariant form).

**Gender lookup:** `byte(3)&3` from `BASE.RUS` entry:
- 0 = male
- 1 = female
- 2 = neutral

<!-- TODO: Confirm exact mapping of byte(3)&3 values to genders.
     Verify if suffix_len is CP866 bytes or UTF-8 characters.
     Document which paradigm IDs map to which common Russian noun patterns. -->

## Adjective Paradigms (`paradigms.adjectives`)

Structure: `paradigms.adjectives[gender][paradigm_id] = "forms"`

- **Gender index:** Same as nouns (1=neutral, 2=male, 3=female)
- **Paradigm ID:** Determined by `adj()` function in compiler — looks up the
  adjective's ending in `paradigms.adjectives[2]` (male forms) to find matching
  paradigm, OR uses `byte(2)==0x80 ? byte(3) : byte(4)` from `BASE.RUS`
- **Forms:** Space-separated, 12 forms (same case/number order as nouns):

```
Имн ед  Род ед  Дат ед  Вин ед  Тв ед  Пр ед   Имн мн  Род мн  Дат мн  Вин мн  Тв мн  Пр мн
  1        2        3        4        5        6        7        8        9       10      11      12
```

**Example:** `"ый ого ому ый ым ом ые ых ый ые ыми ых"` (male, paradigm 0)
- Nom.sg: stem + "ый" → "новый"
- Gen.sg: stem + "ого" → "нового"
- Etc.

**Agreement:** Adjectives must agree with the noun they modify in gender, number,
and case. The `A` printer in `compiler.lua` finds the next noun (`find(s, i, 'N')`),
gets its gender, then declines the adjective using that gender's paradigm.

<!-- TODO: Document the exact algorithm for paradigm_id selection in adj().
     The find_adjective() function matches endings — document which endings map
     to which paradigm IDs. Understand byte(2)==0x80 flag meaning. -->

## Verb Paradigms (`paradigms.verbs`)

Structure: `paradigms.verbs[paradigm_id] = { suffix_len, "forms" }`

- **Paradigm ID:** `byte(4)&~0x80` from `BASE.RUS` entry (same byte as nouns)
- **Suffix length:** Characters to cut from stem before adding conjugation suffixes
- **Forms:** Space-separated, up to 13 forms:

```
1:  1sg pres    (я -у/-ю)
2:  2sg pres    (ты -ешь/-шь)
3:  3sg pres    (он -ет/-ит)
4:  1pl pres    (мы -ем/-им)
5:  2pl pres    (вы -ете/-ите)
6:  3pl pres    (они -ут/-ят)
7:  imperative  (ты -й/-и/-ьте)
8:  past masc   (он -л)
9:  past fem    (она -ла)
10: past neut   (оно -ло)
11: past pl     (они -ли)
12: passive participle (passive)
13: past participle (active)
```

**Example:** `{03, "ю ешь ет ем ете ют йте ял яв - - явший янный"}`
- Suffix length 3: stem "говор" (6 bytes) → cut 3 → "гов"
- 1sg: "гов" + "орю" = "говорю"
- 2sg: "гов" + "оришь" = "говоришь"
- Imperative: "гов" + "орите" = "говорите"
- Past masc: "гов" + "орял" → actually: cut stem + past form
- Passive: "гов" + "орянный" = "говорянный" (not standard — paradigm-specific)

### Conjugation Groups

The ~100 paradigms cover Russian verb conjugation patterns:

| Pattern type | Examples | Paradigm IDs |
|-------------|----------|--------------|
| -ать/-ять | говорить, читать, делать | 0, 1, 2, 3 |
| -ить | писать, видеть, любить | 4, 5, 6, 7 |
| -еть | хотеть, терпеть | 8, 9 |
| -уть/-ять | гнуть, ждать | 10, 11 |
| -ыть/-ти | мыть, нести | 12, 13 |
| -чь | жечь, печь | 14, 15 |
| -оть/-еть | плыть, несть | 16, 17 |
| Irregular | быть, ити, есть | 特殊 |

### Aspect

Determined from `BASE.DIC` entry — `byte(2)&2` flag. If imperfective
and paradigm has a perfective counterpart, the verb stem shifts to the perfective
form (stored after byte 5 in the dictionary entry).

### Past Tense

Uses `past_verb` array: `{"о", "", "а", "и", "и", "и"}` for
gender agreement: masc=nothing, fem="а", neut="о", pl="и".

### Passive Voice

When `e.passive` is set, the past participle form (index 13)
is used, then declined as an adjective via `paradigms.adjective()`.

<!-- TODO: Document exact paradigm_id mapping for each verb conjugation group.
     Verify the suffix_len semantics — is it bytes from end, or from start?
     Understand the irregular verb handling (being, есть, ити).
     Map the paradigm comments (ать ять гать...) to actual paradigm IDs. -->

## Pronoun Declension (`pronouns`)

Local array in `paradigms.lua` — not currently used in compilation but available:

```lua
local pronouns = {
  "меня мне меня мной мне",      -- 1sg
  "тебя тебе тебя тобой тебе",   -- 2sg
  "его ему его им нем",          -- 3sg masc
  "его ему его им нем",          -- 3sg neut (same as masc)
  "ее ей ее ею ней",            -- 3sg fem
  "нас нам нас нами нас",       -- 1pl
  "Вас Вам Вас Вами Вас",       -- 2pl
  "их им их ими них",           -- 3pl
  "кого кому кого кем ком",      -- who (interrogative)
  "чего чему что чем чем",       -- what (interrogative)
  "себя себе себя собой себе",   -- reflexive
}
```

Order: Род ед, Дат ед, Вин ед, Тв ед, Пр ед (5 cases for singular).
Plural forms would need separate lookup.

<!-- TODO: Integrate pronoun declension into compiler.lua R printer.
     Currently R printer only sets person/number, doesn't decline for case.
     Need to add case tracking from preceding P (preposition) token. -->
