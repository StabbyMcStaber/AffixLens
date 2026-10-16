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

