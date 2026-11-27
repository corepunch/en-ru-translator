# Adventure text: first Zork I pass

Input came from actual turns through [Adventure Arena's ZIL loader](https://github.com/corepunch/lua-objc/blob/7cc3f0688e1e3f1ce722fc571f3d864b5d4b6542/apps/adventure-arena/services/ZILRuntime.lua) at its [ZILScript pin](https://github.com/corepunch/zilscript/tree/9896a3f09094a840a368214704879e95fe942701/infocom/zork1).
Selected short excerpts are regression inputs [in the test fixture](../test/fixtures/zork-i.tsv),
not translation data. Fixture source attribution: Infocom, Zork I, as
distributed with the [MIT license](https://github.com/historicalsource/zork1/blob/master/LICENSE);
the license accompanies the fixture.

## Repeat the route

Start Zork I, then run `north; east; open window; enter window; west; take lamp;
turn on lamp; east; up; down; west; move rug; open trap door; down; north`.
Capture the first full description from each of the eight distinct rooms.
Pass the visible text and headings separately to the engine. Do not pass
the game's link targets into the translator. `sh test/run_all.sh` runs
the focused excerpt and transfer checks without needing ZILScript.

## What improved

- "There is a small mailbox here." → "Здесь есть небольшой почтовый ящик."
  Positive and negative existentials retain existence/absence and location.
- The forest path retains its eastward direction. Inverted locatives retain
  which object is on or above another object; noun compounds still inflect.
- The boarded windows, the slightly ajar window, and several noun headings
  preserve their gameplay meaning. The adjective for the axe is neutral.
- A separately supplied link label translates; its command and ID do not.

## What did not

This does not make all eight rooms player-ready. The kitchen's nested
auxiliaries, coordinated listings in the living room, and the troll's whole
action still need work. On a separate held-out Museum of Unsent Signals
playthrough (opening, west, examine diagram, east, north), simple positions
and directions improved, but the full prose still lost some names and
compound nouns. Do not take green excerpt tests as story-wide accuracy.
