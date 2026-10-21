# AffixLens v2.1.2 (2026-10-21)

## Fixed
- Prevent unlearned weapon-affix notifications on consumables and other non-weapon items, including **Potion of Speed**.
- Gate weapon-affix discovery on actual weapon classification and tooltip evidence instead of incidental name matches.
- Add 194 candidate weapon source mappings across 41 affix families from the Ebonhold weapon-affix spreadsheet, including **Speed** on Sprinter's Sword (18410).

## Testing
- Requires in-game validation on WoW 3.3.5a. Test Potion of Speed (no alert), a mapped affixed weapon (correct alert if unlearned), and a normal copy of that weapon (no alert).
- Source mapping is a discovery fallback when an @affix@ tooltip effect exists; item ID alone must not trigger an alert.

## Install
- Extract the `AffixLens` directory into `Interface\\AddOns\\` and enter `/reload`.

---

# AffixLens v2.1.1 (2026-10-20)

## Fixed
- Restored the original **Shield Block** name in Collection and its original learned-rank lookup, resolving the incorrect Block display introduced in v2.1.0.
- Retained the item-tooltip alias from **Block** to **Shield Block**, without renaming the Collection family.

## Unchanged from v2.1.0
- Resizable Collection window with saved size.
- Inventory alerts and yellow bag-slot markers for detectable unlearned affixes.

## Install
Extract the `AffixLens` folder into `Interface\\AddOns\\`, overwrite the existing files, and type `/reload`.

---

# AffixLens v2.1.0 (2026-10-20)

## New
- Resizable Collection window with a bottom-right grip, responsive scrolling and per-character saved dimensions.
- Inventory discovery notifications for newly acquired items bearing recognizable, unlearned affixes.
- Yellow exclamation markers on bag slots containing unlearned affixes.
- Toggle discovery chat and sound alerts with `/affixdiscover on` or `/affixdiscover off` (bag markers remain enabled).

## Fixed
- Recognize **Block** on item tooltips as the same learned-affix family as **Shield Block** in Ebonhold's records.
- Show one Block family in Collection and carry forward saved learned ranks under either naming convention.
- Keep server entries and fallback families visible when a partial catalog response arrives.

## Install
Extract the `AffixLens` folder from the release ZIP to `Interface\\AddOns\\`, replacing your existing addon files, then run `/reload`.

## Testing note
Changes were inspected in source and Block mapping was user-tested in-game. Inventory detection and resize behavior should also be confirmed in a live Project Ebonhold client.

---

# AffixLens v2.0.2

## New

- Added a saved Show Equipment Labels control to both the Equipped Affixes and Collection windows.
- Turn character-sheet affix text on or off without losing the detailed equipment view or collection tracker.
- Both controls stay synchronized, and `/affixes inline on` and `/affixes inline off` remain supported.

## Fixed

- Repaired the Collection navigation button inside Equipped Affixes.
- Restricted AffixLens character-header buttons to the Character tab; they no longer remain visible on Reputation, Skills, or Currency.
- Improved the footer layout so Show Equipment Labels stays visible and clickable.

## Installation

1. Download the attached `AffixLens-v2.0.2.zip` file.
2. Extract `AffixLens` into `ebonhold\Interface\AddOns\`.
3. Restart the client, or type `/reload` when updating an already installed addon.

## Notes

Compatible with Project Ebonhold WoW 3.3.5a. Existing affix collection data and button positions are retained.

Thanks to Noturpalguy for the original AffixDex work. MIT attribution remains in `AffixLens/THIRD_PARTY_LICENSES.txt`.

---

# AffixLens v2.0.1

## What's new
- Move the Affix View and Collection buttons together as one draggable anchor group.
- New default placement in the character window's upper title bar, away from level and class text.
- Both buttons now use consistent sizing and styling.
- Anchor positions are saved per character.
- Unlock, lock, or reset the button position with chat commands.

## Anchor commands
- `/affixes anchors unlock` - drag the buttons to a preferred position.
- `/affixes anchors lock` - lock the group in place.
- `/affixes anchors reset` - restore the default position.

## Installation
1. Download `AffixLens-v2.0.1.zip`.
2. Extract the `AffixLens` folder to `ebonhold\Interface\AddOns\`.
3. Restart the client or type `/reload` when updating an existing installation.

This update builds on v2.0.0. The affix display, collection tracker, and existing saved data remain supported.

---

# Changelog

## v2.0.0 (2026-10-16)

- Integrated a searchable, server-aware learned-affix collection.
- Split collection into alphabetical ranked armor / unranked weapon groups.
- Added equipment popup, mutual-exclusive Collection/Equipment views, movable windows, and character-sheet button controls.
- Added rank-sensitive duplicate detection, escape normalization, weapon suffix detection, and abbreviated character-sheet labels.
- Improved equipment-slot positioning and UI layout through community testing.

This is the first public release of the combined AffixLens addon.


