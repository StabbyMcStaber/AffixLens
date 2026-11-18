# AffixLens 3.0.1 validation notes

1. Delete the existing AffixLens addon folder, install the new folder, restart or reload; ensure **zero** old character sheet labels/buttons.
2. Verify minimap icon: hover text, click toggles, dragging changes position; `/affixlens minimap reset` restores default.
3. Open Collection: expect **268 families** and rank I–V only; search `Hemorrhage`, hover row and verify current-rank tooltip; filter through Offensive/Defensive/Resource/Utility/Mobility; learned status should say `Syncing...` only before `ExtractionService.learnedAffixes` arrives.
4. Open Equipped: all equipped equipment appears, with **Not affixable** for shirt/tabard only; an affixed ranged weapon/wand must display its affix name, category-compatible color, and effect tooltip. The footer must show **17** available slots, not 16. Hover the affix name to see exact effect and costs; hover item name for WoW tooltip.
5. Verify a player with `Venom V` sees learned **V**, *not* learned I/II/III/IV; lower-rank Venom items should not get a `!` bag marker, but a higher rank for another family should.
6. `/affixlens refresh`, `/affixdiscover off`, `/affixdiscover on`, `/affixbagtest` should work.
7. Drag and resize window, `/reload`, verify position and active tab persisted; check 1280x720 display for clipping.
8. Verify several newly added V2 affix names and a piece with an item whose tooltip title contains a natural `of` suffix.
9. If any Lua error occurs, capture the full traceback and the item/affix involved. Addon UI and parser should remain read-only; no extraction/engraving actions are sent.

10. Swap in a wand with a V2 enchant (e.g. Venom V). Equipped must detect it by enchant ID or engraved tooltip suffix, show its effect on hover, and include it in duplicate-family checks. Test ranged after /reload, not only after login.

## Live validation — 2026-11-17

Player confirmed Collection/Equipped tabs, hover effects and 17/17 equipped affixes, including Hemorrhage V on a wand.
