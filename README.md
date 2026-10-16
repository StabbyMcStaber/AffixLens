# AffixLens

**Project Ebonhold addon for World of Warcraft 3.3.5a**

AffixLens shows the affix attached to each equipped item right on the character sheet, and provides two additional, switchable views.

## Features

- **Equipment labels** on the character sheet, including weapon affixes such as Vulnerability and Venom.
- **Affix View:** a movable, closable equipment table with item names, affixes, and duplicate-affix warnings.
- **Collection:** alphabetical **Armor (ranked)** and **Weapon (unranked)** sections, learned status, available ranks, and search.
- Different ranks of the same affix are allowed together. Duplicate warnings check the exact affix **and rank**; unranked weapon-only affixes are excluded.
- Affix names display without a leading `of`; escaped apostrophes are normalized. Space-constrained labels use meaningful abbreviations instead of arbitrary ellipses.
- Buttons on the character window toggle the corresponding view, opening one closes the other, and closing the character window closes both.
- Uses Ebonhold's server-provided affix catalog when available; falls back to bundled information as needed.

## Installation

1. Download **AffixLens-v2.0.0.zip** from **Releases**.
2. Extract the included `AffixLens` folder to `World of Warcraft\Interface\AddOns\`.
3. Start the WoW 3.3.5a client (or `/reload` if replacing an installed version).
4. Open your character sheet (`C`) and click **Affix View** or **Collection**.

## Commands

- `/affixcollection` — toggle collection view
- `/affixcollection scan` — refresh learned affixes
- `/affixes` — equipment-view command (see in-game help for other debug options)

## Scope / not yet integrated

This release includes **local collection tracking**, not the entirety of upstream AffixDex. Party comparison, previously seen player history, bag glow, and extended learned-state tooltip annotations are **not yet included**.

## Credit and third-party notices

Created by **Stan**, with assistance from **CarolJean**.

AffixDex by **Noturpalguy** (https://github.com/kwilliams312/AffixDex) informed catalog integration and mappings. The upstream MIT copyright and license are preserved in [`AffixLens/THIRD_PARTY_LICENSES.txt`](AffixLens/THIRD_PARTY_LICENSES.txt). No ownership of that work is claimed.
