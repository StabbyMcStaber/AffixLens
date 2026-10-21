-- AffixLens v2.0.0-preview.4 - Project Ebonhold, WoW 3.3.5a (Interface 30300)
-- Author: Stan (with CarolJean)
-- Reads the actual equipped item's tooltip; it never infers an affix from an item ID alone.

local ADDON = "AffixLens"
local PREFIX = "|cffb794faAffixLens|r: "

local slots = {
    { id =  1, label = "Head",       button = "CharacterHeadSlot",          side = "left" },
    { id =  2, label = "Neck",       button = "CharacterNeckSlot",          side = "left" },
    { id =  3, label = "Shoulder",   button = "CharacterShoulderSlot",      side = "left" },
    { id = 15, label = "Back",       button = "CharacterBackSlot",          side = "left" },
    { id =  5, label = "Chest",      button = "CharacterChestSlot",         side = "left" },
    { id =  4, label = "Shirt",      button = "CharacterShirtSlot",         side = "left" },
    { id = 19, label = "Tabard",     button = "CharacterTabardSlot",        side = "left" },
    { id =  9, label = "Wrist",      button = "CharacterWristSlot",         side = "left" },
    { id = 10, label = "Hands",      button = "CharacterHandsSlot",         side = "right" },
    { id =  6, label = "Waist",      button = "CharacterWaistSlot",         side = "right" },
    { id =  7, label = "Legs",       button = "CharacterLegsSlot",          side = "right" },
    { id =  8, label = "Feet",       button = "CharacterFeetSlot",          side = "right" },
    { id = 11, label = "Ring 1",     button = "CharacterFinger0Slot",       side = "right" },
    { id = 12, label = "Ring 2",     button = "CharacterFinger1Slot",       side = "right" },
    { id = 13, label = "Trinket 1",  button = "CharacterTrinket0Slot",      side = "right" },
    { id = 14, label = "Trinket 2",  button = "CharacterTrinket1Slot",      side = "right" },
    { id = 16, label = "Main Hand",  button = "CharacterMainHandSlot",      side = "bottom" },
    { id = 17, label = "Off Hand",   button = "CharacterSecondaryHandSlot", side = "bottom" },
    { id = 18, label = "Ranged",     button = "CharacterRangedSlot",        side = "bottom" },
}

local records = {}
local scan = CreateFrame("GameTooltip", "AffixLensScanTooltip", UIParent, "GameTooltipTemplate")
scan:Hide()
local widget
local panel
local toggleButton
local buttonAnchor
local anchorsUnlocked = false
local initialized = false
local elapsed = 0
local refreshRequested = true
local db
local panelOpen = false  -- Each session and each character-window opening starts closed.

local function chat(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message) end
end

local function clean(s)
    if not s then return "" end
    -- Ebonhold sometimes escapes apostrophes in item/affix names:
    -- Warfang\'s and Warfang\\'s should both read as Warfang's.
    -- Strip only backslashes immediately preceding apostrophes; do not
    -- touch the item's original hyperlink or unrelated backslashes.
    s = tostring(s):gsub("\\+'", "'")
    return s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            :gsub("^%s+", ""):gsub("%s+$", "")
end

-- Abbreviations preserve the affix family and rank in narrow paper-doll slots.
local function inlineName(s)
    s = clean(s)
    local patterns = {
        {"Relentless Crits", "Relent Crits"},
        {"Overwhelming Force", "O-Force"},
        {"Fortified by Pain", "Fortified Pain"},
        {"Keen Strikes", "Keen Strikes"},
    }
    for _, pair in ipairs(patterns) do
        if s:sub(1, #pair[1]) == pair[1] then
            return pair[2] .. s:sub(#pair[1] + 1)
        end
    end
    return s
end

local function clip(s, n)
    s = clean(s)
    if #s <= n then return s end
    return s:sub(1, n - 3) .. "..."
end

-- PE rank-bearing affixes appear on the actual tooltip title, e.g.
-- "Sanctified Bloodmage Hood of Inner Light II".
-- Standard WoW randomized suffixes ("of the Bear") don't carry a rank.
local function rankedAffix(title, base)
    -- The client's cached GetItemInfo name sometimes *already includes*
    -- the engraved suffix. Detect explicit, catalogued ranked suffixes first.
    local rank = title:match(" ([IVXLCDM]+)$")
    if not rank then return nil end
    local knownRanked = {
        "Arcane Mind", "Armor Rend", "Bulwark", "Cold", "Feral Grace",
        "Fortified by Pain", "Frost Breath", "Frozen Pulse", "Infinite Star",
        "Iron Will", "Ironhide", "Keen Strikes", "Living Tide",
        "Mender's Surge", "Overwhelming Force", "Pet Power",
        "Quick Instincts", "Relentless Crits", "Shield Block",
        "Spell Mastery", "Spirit Surge", "Stalwart", "Temporal Flux",
        "Thick Hide", "Wellspring",
    }
    for _, family in ipairs(knownRanked) do
        local suffix = " of " .. family .. " " .. rank
        if title:sub(-#suffix):lower() == suffix:lower() then
            return family, rank
        end
    end
    if not base or base == "" or title == base then return nil end
    local name
    if title:sub(1, #base + 1) == base .. " " then
        name = title:sub(#base + 2, #title - #rank - 1)
    else
        -- Fallback only when the actual PE tooltip title contains a clear suffix.
        name = title:match(" (of .+) " .. rank .. "$")
    end
    if not name or name == "" then return nil end
    return name, rank
end

-- PE encloses the effect description in @affix@ ... @affix@ in *raw*
-- tooltip text. A private tooltip often retains markers that PE strips
-- from the visible GameTooltip. This also catches unranked proc affixes.
local function effectText()
    for i = 2, 40 do
        local fontString = _G["AffixLensScanTooltipTextLeft" .. i]
        if fontString then
            local line = fontString:GetText()
            if line then
                local effect = line:match("@affix@%s*(.-)%s*@affix@")
                if effect and effect ~= "" then return clean(effect) end
            end
        end
    end
    return nil
end

-- Weapon-only Ebonhold affixes may have no named suffix on the item.
-- Resolve @affix@ proc text against spell descriptions from the server catalog.
-- Adapted from AffixDex (Noturpalguy, MIT; see THIRD_PARTY_LICENSES.txt).
local spellTip = CreateFrame("GameTooltip", "AffixLensSpellScanTooltip", UIParent, "GameTooltipTemplate")
spellTip:Hide()
local procCache = {}
local procCatalogStamp = nil
local function normalizeProc(s)
    s = clean(s):lower()
    s = s:gsub("^chance on hit%s*:?%s*", "")
    s = s:gsub("^chance to strike[^:]-:?%s*", "")
    s = s:gsub("%$[%a]+", "")
    s = s:gsub("%d+%.?%d*", "")
    s = s:gsub("[%s%.,;:!?]+", " ")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end
local function spellDescription(id)
    if not id then return nil end
    spellTip:SetOwner(UIParent, "ANCHOR_NONE")
    spellTip:ClearLines()
    local ok = pcall(spellTip.SetHyperlink, spellTip, "spell:" .. tostring(id))
    if not ok then return nil end
    local parts = {}
    for i = 2, (spellTip:NumLines() or 0) do
        local line = _G["AffixLensSpellScanTooltipTextLeft" .. i]
        if line and line:GetText() then parts[#parts + 1] = line:GetText() end
    end
    spellTip:Hide()
    return table.concat(parts, " ")
end
local function resolveWeaponProc(effect)
    local svc = _G.ExtractionService
    local affixes = svc and svc.learnedAffixes
    if type(affixes) ~= "table" or #affixes == 0 then return nil end
    -- Server list is generally stable, but can arrive after login. Rebuild if
    -- the count changes, rather than rescanning all spell tooltips every tick.
    local stamp = tostring(affixes) .. ":" .. tostring(#affixes)
    if procCatalogStamp ~= stamp then
        procCatalogStamp = stamp
        procCache = {}
        local seen = {}
        for _, a in ipairs(affixes) do
            if a.weaponOnly and a.id and type(a.name) == "string" and not seen[a.name] then
                seen[a.name] = true
                local description = spellDescription(a.id)
                local norm = description and normalizeProc(description) or ""
                if #norm >= 12 then procCache[#procCache + 1] = {name=clean(a.name), norm=norm} end
            end
        end
    end
    local norm = normalizeProc(effect)
    if #norm < 12 then return nil end
    local best, longest = nil, 0
    for _, row in ipairs(procCache) do
        -- Require the spell effect to match the *start* of the item's proc,
        -- not an unrelated mention somewhere else in the tooltip.
        if (norm:sub(1, #row.norm) == row.norm or row.norm:sub(1, #norm) == norm)
            and math.min(#norm, #row.norm) > longest then
            best, longest = row.name, math.min(#norm, #row.norm)
        end
    end
    return best
end

-- Rankless Ebonhold weapon affixes may be present as a plain "of Name"
-- suffix in the equipped tooltip title (unlike their proc text). Prefer
-- this exact server-catalog match over fuzzy spell-description matching.
local function weaponSuffix(title)
    local svc = _G.ExtractionService
    local entries = svc and svc.learnedAffixes
    if type(entries) ~= "table" then return nil end
    local normalized = clean(title):lower()
    local best, bestLength = nil, 0
    for _, row in ipairs(entries) do
        if row.weaponOnly and type(row.name) == "string" then
            local candidate = clean(row.name)
            local suffix = " of " .. candidate:lower()
            if #candidate > bestLength and normalized:sub(-#suffix) == suffix then
                best, bestLength = candidate, #candidate
            end
        end
    end
    return best
end

local function readEquipment(entry)
    local link = GetInventoryItemLink("player", entry.id)
    if not link then
        return { status = "empty", name = "Empty", affix = "--" }
    end

    local itemID = tonumber(link:match("item:(%d+)"))
    local baseName = itemID and GetItemInfo(itemID)
    if not baseName then
        return { status = "loading", name = "Loading...", affix = "...", link = link }
    end
    -- Normalize the cached base name *and* scanned title before comparing;
    -- either one may use a different apostrophe-escaping convention.
    baseName = clean(baseName)

    -- The equipment slot matters: SetHyperlink or GetItemInfo(itemID) alone
    -- can lose the individual item's actual engraved affix.
    scan:SetOwner(UIParent, "ANCHOR_NONE")
    scan:ClearLines()
    scan:SetInventoryItem("player", entry.id)
    local titleFS = _G.AffixLensScanTooltipTextLeft1
    local title = titleFS and clean(titleFS:GetText()) or ""
    local effect = effectText()
    scan:Hide()

    if title == "" then
        return { status = "loading", name = baseName, affix = "...", link = link }
    end

    local name, rank = rankedAffix(title, baseName)
    local affix
    local duplicateKey
    if name then
        -- Remove just the leading "of" from displayed affixes, not from item
        -- names or an "of" in the middle of an affix's actual name.
        name = clean(name):gsub("^[Oo][Ff]%s+", "")
        affix = name .. " " .. rank
        -- Ebonhold permits mixing ranks of the SAME family. Only the same
        -- affix PLUS the same rank can conflict. Normalizing the display name
        -- also handles escaped apostrophes in matching affixes.
        duplicateKey = name:lower():gsub("%s+", " ") .. " " .. rank:upper()
    elseif entry.id == 16 or entry.id == 17 or entry.id == 18 then
        -- Proc effects aren't guaranteed to match the server spell tooltip
        -- verbatim. The suffix is authoritative when in the live catalog.
        affix = weaponSuffix(title) or (effect and resolveWeaponProc(effect)) or (effect and "Proc (hover for details)") or "N/A"
    elseif effect then
        affix = "Proc (hover for details)"
    else
        affix = "N/A"
    end

    return {
        status = (affix ~= "N/A" and affix ~= "--") and "affix" or "none",
        name = baseName,
        title = title,
        affix = affix,
        duplicateKey = duplicateKey,
        effect = effect,
        link = link,
    }
end

-- Source-item candidates from Ebonhold Weapon Affixes - Item Affix Mapping.csv.
-- Item IDs alone are NOT proof an engraved affix exists; require tooltip
-- evidence (@affix@ proc or an actual changed weapon suffix).
local weaponSourceFamilies = {
    ["Affliction"]="19910,3194,6831,2912,11121,13053,2205,19170,1387,1481,12250,1318,1982,3822,17752,2163,1482,2256,12974,28164,13051",
    ["Azzinoth"]="10847,32471",
    ["Bladestorm"]="7717",
    ["Bloodlust"]="27901,28438,28439,28437,17112,18203,2243,31318,29348,9423",
    ["Clarity"]="17733,17943,31322",
    ["Concussion"]="11608,28441,12796,13198,13393,29182,28442,12528",
    ["Decay"]="10803,14576,13032,8225",
    ["Devastation"]="30090",
    ["Dissolution"]="11635,6909",
    ["Execution"]="12583,11744,9511,13054,2164,1986,8190,19918,17766,9478,13285,19324,13060,11603",
    ["Ferocity"]="29962,11817",
    ["Fire Blast"]="2825,9412",
    ["Flame Wrath"]="11809",
    ["Flurry"]="31332,871,11684,17705",
    ["Fortification"]="8223,28367,18348,6622",
    ["Frailty"]="14024,934,13401",
    ["Frost Arrow"]="2824",
    ["Fury"]="29996",
    ["Glaciation"]="10761,810,10623",
    ["Hemorrhage"]="12791,6738,13057,809,7753,12463,13399,17730,10772,5616,15814,13016,8224",
    ["Incineration"]="14555,18671,11803,9419,6220,18816,12531,1728",
    ["Judgement"]="754",
    ["Julie's Blessing"]="6660",
    ["Keeper's Sting"]="10567,6469,17753",
    ["Maiming"]="10628,28573,9475,9425,17075",
    ["Permafrost"]="14487,13148,7730,13984,17704,19099,5815,5182,5756",
    ["Pyromancy"]="2299,9386,10797,12992,12243,17193,2915,12792",
    ["Rending"]="12798,13204,11607,13286,9485",
    ["Resurgence"]="12790,647,23541,19334",
    ["Shackling"]="9608,7954",
    ["Shahram"]="12592",
    ["Speed"]="18410",
    ["Sulfuras"]="17182",
    ["Thunderfury"]="19019",
    ["Twin Shot"]="34334",
    ["Undead"]="13246",
    ["Val'Anyr"]="46017",
    ["Vampirism"]="19852,31193,50415,50709,12621,10804,28774,21856,28311,17074,11920",
    ["Venom"]="6904,4446,7959,17738,13983,17002,12582,4449,1726,1265,13035,5426,6472,899,13183,15853,5752",
    ["Vulnerability"]="19169",
    ["Wilds"]="811,19100,9446,20578,9651,21679,11902,2263,15418,9486,8006,19901",
}
local weaponSourceByID = {}
for family, ids in pairs(weaponSourceFamilies) do
    for id in ids:gmatch("%d+") do weaponSourceByID[tonumber(id)] = family end
end

-- An affix from the weapon catalog must occur on an actual weapon.
-- Checking suffixes on every bag item mistakes Potion of Speed for Speed.
-- Use WoW's actual item class rather than name/substrings; ranged weapons
-- and wands are included in the Weapon class in 3.3.5a.
local function isWeaponItem(itemID)
    if not itemID then return false end
    local _, _, _, _, _, _, _, _, equipLoc, _, _, classID = GetItemInfo(itemID)
    -- GetItemInfo's 12th return is classID on 3.3.5a clients.
    if classID ~= nil then return classID == 2 end
    -- Some 3.3.5a forks expose only the localized class string.
    return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON"
        or equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_WEAPONOFFHAND"
        or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT"
        or equipLoc == "INVTYPE_THROWN"
end

-- Inspect the real bag-slot tooltip; an itemID-only lookup loses engravings.
_G.AffixLensInspectBagItem = function(bag, slot)
    local link=GetContainerItemLink(bag,slot)
    if not link then return nil end
    local itemID=tonumber(link:match("item:(%d+)"))
    local base=itemID and GetItemInfo(itemID)
    if not base then return nil end
    base=clean(base)
    scan:SetOwner(UIParent,"ANCHOR_NONE")
    scan:ClearLines()
    scan:SetBagItem(bag,slot)
    local fs=_G.AffixLensScanTooltipTextLeft1
    local title=fs and clean(fs:GetText()) or ""
    local effect=effectText()
    scan:Hide()
    if title=="" then return nil end
    local name,rank=rankedAffix(title,base)
    if name then
        return clean(name):gsub("^[Oo][Ff]%s+","").." "..rank
    end
    -- Known unranked weapon suffixes, even when no proc tooltip is present.
    if not isWeaponItem(itemID) then return nil end
    -- Require an actual changed tooltip title for an explicit suffix.
    -- Unmodified base items can still be identified by their @affix@ proc.
    local weapon=(title ~= base and weaponSuffix(title)) or (effect and resolveWeaponProc(effect))
    -- Source mapping only supplements an actual tooltip proc. It never marks
    -- an item based on a matching name or item ID alone.
    if not weapon and effect then weapon=weaponSourceByID[itemID] end
    return weapon
end

local function colors(data, duplicate)
    if duplicate then return 1.0, 0.56, 0.23 end
    if data.status == "affix" then return 0.80, 0.56, 1.0 end
    if data.status == "loading" then return 0.99, 0.82, 0.32 end
    return 0.55, 0.57, 0.62
end

local function updateWidgets()
    if not initialized then return end
    local rankCounts = {}
    local affixed, duplicateGroups = 0, 0
    local duplicates = {}

    for i, entry in ipairs(slots) do
        records[i] = readEquipment(entry)
        local data = records[i]
        if data.status == "affix" then
            affixed = affixed + 1
            if data.duplicateKey then
                rankCounts[data.duplicateKey] = (rankCounts[data.duplicateKey] or 0) + 1
            end
        end
    end
    for key, count in pairs(rankCounts) do
        if count > 1 then
            duplicates[key] = true
            duplicateGroups = duplicateGroups + 1
        end
    end

    for i, entry in ipairs(slots) do
        local data = records[i]
        local duplicate = data.duplicateKey and duplicates[data.duplicateKey] or false
        data.duplicate = duplicate
        local label = entry.inline
        if label then
            if db.inline then
                label:Show()
                local value = data.affix
                if duplicate then value = value .. " x" .. rankCounts[data.duplicateKey] end
                local maxChars = (entry.id == 16 or entry.id == 18) and 25 or (entry.id == 17 and 21 or 20)
                local display = inlineName(value)
                if entry.id == 6 or entry.id == 8 then maxChars = 19 end
                label:SetText(clip(display, maxChars))
                label:SetTextColor(colors(data, duplicate))
            else
                label:Hide()
            end
        end
        if entry.row then
            entry.row.item:SetText(clip(data.name, 29))
            local displayAffix = data.affix
            if duplicate then displayAffix = displayAffix .. "  [DUPLICATE]" end
            entry.row.affix:SetText(clip(displayAffix, 31))
            entry.row.affix:SetTextColor(colors(data, duplicate))
        end
    end
    if panel and panel.summary then
        panel.summary:SetText(affixed .. " affixed | " .. duplicateGroups .. " duplicate groups")
        if duplicateGroups > 0 then
            panel.summary:SetTextColor(1, 0.58, 0.25)
        else
            panel.summary:SetTextColor(0.65, 0.9, 0.7)
        end
    end
end

local function showTooltip(row)
    local entry = row.entry
    local data = records[entry.index]
    if not data or not data.link then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetInventoryItem("player", entry.id)
    GameTooltip:AddLine(" ")
    if data.status == "affix" then
        GameTooltip:AddLine("AffixLens: " .. data.affix, 0.8, 0.56, 1.0, true)
    elseif data.status == "none" then
        GameTooltip:AddLine("AffixLens: N/A", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("AffixLens: Reading item...", 1, 0.85, 0.3)
    end
    if data.duplicate then
        GameTooltip:AddLine("Duplicate affix AND rank equipped!", 1, 0.45, 0.1)
    end
    GameTooltip:Show()
end

local function makeInline(entry)
    local button = _G[entry.button]
    if not button then return end
    local text = button:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetHeight(17)
    if entry.label == "Waist" or entry.label == "Feet" then
        -- Keep labels INSIDE the doll beside their slot, but shorten them
        -- so the final characters do not overlap the resistance column.
        text:SetWidth(106)
        text:SetJustifyH("RIGHT")
        text:SetPoint("RIGHT", button, "LEFT", -4, -11)
    elseif entry.id == 9 then
        -- Wrist: lift away from weapon area.
        text:SetWidth(106)
        text:SetJustifyH("LEFT")
        text:SetPoint("LEFT", button, "RIGHT", 4, 7)
    elseif entry.side == "left" then
        text:SetWidth(106)
        text:SetJustifyH("LEFT")
        text:SetPoint("LEFT", button, "RIGHT", 4, 0)
    elseif entry.id == 11 then
        text:SetWidth(106)
        text:SetJustifyH("RIGHT")
        text:SetPoint("RIGHT", button, "LEFT", -4, -7)
    elseif entry.id == 14 then
        text:SetWidth(106)
        text:SetJustifyH("RIGHT")
        text:SetPoint("RIGHT", button, "LEFT", -4, 7)
    elseif entry.side == "right" then
        text:SetWidth(106)
        text:SetJustifyH("RIGHT")
        text:SetPoint("RIGHT", button, "LEFT", -4, 0)
    elseif entry.id == 16 then
        -- Main hand: to the left, under the weapon icons.
        text:SetWidth(155)
        text:SetJustifyH("RIGHT")
        text:SetPoint("RIGHT", button, "LEFT", -10, -16)
    elseif entry.id == 18 then
        -- Ranged/wand: to the right, under the weapon icons.
        text:SetWidth(165)
        text:SetJustifyH("LEFT")
        text:SetPoint("LEFT", button, "RIGHT", 10, -16)
    else
        -- Off-hand shield: immediately above the center weapon icon.
        text:SetWidth(138)
        text:SetJustifyH("CENTER")
        text:SetPoint("BOTTOM", button, "TOP", 0, 3)
    end
    entry.inline = text
end

local function createPanel()
    -- UIParent parentage lets this window be dragged independently of the
    -- character sheet. It remains hidden until "Affix View" is clicked.
    panel = CreateFrame("Frame", "AffixLensEquipmentPanel", UIParent)
    panel:SetWidth(465)
    panel:SetHeight(503)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    if db.position and type(db.position.left) == "number" and type(db.position.top) == "number" then
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.position.left, db.position.top)
    else
        panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 5, -13)
    end
    panel:SetFrameStrata("DIALOG")
    panel:Hide()
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.05, 0.07, 0.1, 0.96)
    panel:SetBackdropBorderColor(0.43, 0.30, 0.63, 1)

    -- Only the title/header is draggable, keeping row-hover item tooltips
    -- fully usable. The last dragged location is restored next time.
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -4)
    header:SetWidth(250)
    header:SetHeight(42)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() panel:StartMoving() end)
    header:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        local left, top = panel:GetLeft(), panel:GetTop()
        if left and top then
            db.position = { left = left, top = top }
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function()
        panelOpen = false
        panel:Hide()
        if SlashCmdList.AFFIXLENSCOLLECTION then SlashCmdList.AFFIXLENSCOLLECTION("hide") end
    end)

    -- Switch directly to Collection. Only one supplemental window is ever visible.
    local collectionButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    collectionButton:SetWidth(92)
    collectionButton:SetHeight(22)
    collectionButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -43, -10)
    collectionButton:SetText("Collection")
    collectionButton:SetFrameLevel(panel:GetFrameLevel() + 15)
    collectionButton:SetScript("OnClick", function()
        -- Hide the source first, then open the target explicitly.
        panelOpen = false
        panel:Hide()
        if _G.AffixLensShowCollection then
            _G.AffixLensShowCollection()
        elseif SlashCmdList.AFFIXLENSCOLLECTION then
            SlashCmdList.AFFIXLENSCOLLECTION("show")
        end
    end)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
    title:SetText("Equipped Affixes")
    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -33)
    help:SetText("Hover a row for the complete equipment tooltip")

    -- Optional character-sheet affix labels. The setting is saved across reloads.
    local labelsToggle = CreateFrame("CheckButton", "AffixLensInlineLabelsToggle", panel, "UICheckButtonTemplate")
    labelsToggle:SetWidth(23)
    labelsToggle:SetHeight(23)
    -- Dedicated footer beneath the last equipment row; don't overlap row 19.
    local toggleBackground = CreateFrame("Frame", nil, panel)
    toggleBackground:SetWidth(205); toggleBackground:SetHeight(28)
    toggleBackground:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 7)
    toggleBackground:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = {left=3,right=3,top=3,bottom=3} })
    toggleBackground:SetBackdropColor(0.02, 0.02, 0.03, 0.96)
    toggleBackground:SetBackdropBorderColor(0.65, 0.55, 0.28, 1)
    toggleBackground:SetFrameLevel(panel:GetFrameLevel() + 8)
    labelsToggle:SetParent(toggleBackground)
    labelsToggle:ClearAllPoints()
    labelsToggle:SetPoint("RIGHT", toggleBackground, "RIGHT", -7, 0)
    labelsToggle:SetFrameLevel(toggleBackground:GetFrameLevel() + 2)
    labelsToggle:SetChecked(db.inline)
    local labelsCaption = toggleBackground:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelsCaption:SetPoint("RIGHT", labelsToggle, "LEFT", -4, 0)
    labelsCaption:SetText("Show Equipment Labels")
    labelsToggle:SetScript("OnClick", function(self)
        db.inline = self:GetChecked() and true or false
        refreshRequested = true
        updateWidgets()
        if _G.AffixLensSyncCollectionLabelsToggle then _G.AffixLensSyncCollectionLabelsToggle() end
    end)
    labelsToggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show affix text next to equipped items")
        GameTooltip:AddLine("Collection and equipment overview remain available.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    labelsToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.labelsToggle = labelsToggle

    panel.summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.summary:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 15, 15)
    panel.summary:SetWidth(235)
    panel.summary:SetJustifyH("LEFT")

    for index, entry in ipairs(slots) do
        entry.index = index
        local row = CreateFrame("Button", nil, panel)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -51 - (index - 1) * 21)
        row:SetWidth(445)
        row:SetHeight(21)
        row.entry = entry
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnEnter", showTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local slotName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slotName:SetPoint("LEFT", row, "LEFT", 3, 0)
        slotName:SetWidth(75)
        slotName:SetJustifyH("LEFT")
        slotName:SetText(entry.label)

        local itemName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itemName:SetPoint("LEFT", row, "LEFT", 80, 0)
        itemName:SetWidth(183)
        itemName:SetJustifyH("LEFT")

        local affix = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        affix:SetPoint("LEFT", row, "LEFT", 265, 0)
        affix:SetWidth(178)
        affix:SetJustifyH("LEFT")

        row.item = itemName
        row.affix = affix
        entry.row = row
    end

    panel:SetScript("OnShow", function() refreshRequested = true end)
end

local function refreshPanelVisibility()
    if not initialized then return end
    local characterOpen = CharacterFrame:IsShown() and
                          (not PaperDollFrame or PaperDollFrame:IsShown())
    if panelOpen and characterOpen then panel:Show() else panel:Hide() end
    if characterOpen then toggleButton:Show() else toggleButton:Hide() end
end

-- The two controls live in a single movable frame on the title bar.
-- Offset units are relative to CharacterFrame and stored per character.
local function anchorSettings()
    AffixLensCharDB = AffixLensCharDB or {}
    return AffixLensCharDB
end
local function applyButtonAnchor()
    if not buttonAnchor or not CharacterFrame then return end
    local prefs = anchorSettings()
    local x = tonumber(prefs.buttonX) or 110
    local y = tonumber(prefs.buttonY) or -12
    buttonAnchor:ClearAllPoints()
    buttonAnchor:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", x, y)
end
local function stopAnchorDrag()
    if not buttonAnchor or not anchorsUnlocked then return end
    buttonAnchor:StopMovingOrSizing()
    local left, top = buttonAnchor:GetLeft(), buttonAnchor:GetTop()
    local charLeft, charTop = CharacterFrame:GetLeft(), CharacterFrame:GetTop()
    if left and top and charLeft and charTop then
        local prefs = anchorSettings()
        prefs.buttonX = math.floor(left - charLeft + 0.5)
        prefs.buttonY = math.floor(top - charTop + 0.5)
    end
    applyButtonAnchor()
end
_G.AffixLensStartAnchorDrag = function()
    if buttonAnchor and anchorsUnlocked then buttonAnchor:StartMoving() end
end
_G.AffixLensStopAnchorDrag = stopAnchorDrag
local function setAnchorsUnlocked(value)
    anchorsUnlocked = value and true or false
    if buttonAnchor then
        if buttonAnchor.moveHint then
            if anchorsUnlocked then buttonAnchor.moveHint:Show() else buttonAnchor.moveHint:Hide() end
        end
        if buttonAnchor.SetBackdropBorderColor then
            if anchorsUnlocked then buttonAnchor:SetBackdropBorderColor(1, 0.75, 0.1, 1)
            else buttonAnchor:SetBackdropBorderColor(0, 0, 0, 0) end
        end
    end
end

local function initialize()
    if initialized or not CharacterFrame then return false end
    -- Some clients lazily load the paper-doll portion of the Character UI.
    if not _G.CharacterHeadSlot then return false end
    db = AffixLensDB or {}
    AffixLensDB = db
    -- Do not inherit the old v1.0.1 auto-open setting. A fresh session
    -- always starts closed, regardless of the previous SavedVariables value.
    if db.inline == nil then db.inline = true end

    for _, entry in ipairs(slots) do makeInline(entry) end
    createPanel()

    buttonAnchor = CreateFrame("Frame", "AffixLensButtonAnchor", CharacterFrame)
    buttonAnchor:SetWidth(149)
    buttonAnchor:SetHeight(19)
    buttonAnchor:SetFrameLevel(CharacterFrame:GetFrameLevel() + 20)
    buttonAnchor:SetMovable(true)
    buttonAnchor:SetClampedToScreen(true)
    buttonAnchor:EnableMouse(false)
    buttonAnchor:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    buttonAnchor:SetBackdropBorderColor(0, 0, 0, 0)
    applyButtonAnchor()
    local moveHint = buttonAnchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moveHint:SetPoint("TOP", buttonAnchor, "BOTTOM", 0, -2)
    moveHint:SetText("Drag buttons to move")
    moveHint:Hide()
    buttonAnchor.moveHint = moveHint

    toggleButton = CreateFrame("Button", "AffixLensToggle", buttonAnchor, "UIPanelButtonTemplate")
    toggleButton:SetWidth(69)
    toggleButton:SetHeight(19)
    toggleButton:SetText("Affix View")
    toggleButton:SetPoint("LEFT", buttonAnchor, "LEFT", 0, 0)
    toggleButton:RegisterForDrag("LeftButton")
    toggleButton:SetScript("OnDragStart", _G.AffixLensStartAnchorDrag)
    toggleButton:SetScript("OnDragStop", _G.AffixLensStopAnchorDrag)
    toggleButton:SetScript("OnClick", function()
        panelOpen = not panelOpen
        if panelOpen and SlashCmdList.AFFIXLENSCOLLECTION then SlashCmdList.AFFIXLENSCOLLECTION("hide") end
        refreshPanelVisibility()
        refreshRequested = true
        updateWidgets()
    end)

    CharacterFrame:HookScript("OnShow", function()
        refreshPanelVisibility()
        refreshRequested = true
    end)
    CharacterFrame:HookScript("OnHide", function()
        panelOpen = false
        refreshPanelVisibility()
        if SlashCmdList.AFFIXLENSCOLLECTION then SlashCmdList.AFFIXLENSCOLLECTION("hide") end
    end)
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            refreshPanelVisibility()
            refreshRequested = true
        end)
        PaperDollFrame:HookScript("OnHide", function()
            panelOpen = false
            refreshPanelVisibility()
            if SlashCmdList.AFFIXLENSCOLLECTION then SlashCmdList.AFFIXLENSCOLLECTION("hide") end
        end)
    end
    initialized = true
    refreshPanelVisibility()
    updateWidgets()
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= ADDON and arg1 ~= "Blizzard_CharacterUI" then return end
    if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
    if not initialized then initialize() end
    refreshRequested = true
end)

events:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed < 0.4 then return end
    if not initialized then
        initialize()
        elapsed = 0
        return
    end
    -- Polling only while the Character page is visible catches a newly
    -- engraved affix even if an equipment-changed event wasn't raised.
    local characterOpen = CharacterFrame:IsShown() and
                          (not PaperDollFrame or PaperDollFrame:IsShown())
    if not characterOpen then
        if panel:IsShown() then refreshPanelVisibility() end
        elapsed = 0
        return
    end
    if refreshRequested or elapsed >= 2.4 then
        elapsed = 0
        refreshRequested = false
        refreshPanelVisibility()
        updateWidgets()
    end
end)

SLASH_AFFIXLENS1 = "/affixlens"
SLASH_AFFIXLENS2 = "/affixes"
SlashCmdList.AFFIXLENS = function(message)
    local cmd, arg = (message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if not initialized and not initialize() then
        chat("Character window isn't ready yet; try opening it first.")
        return
    end
    if cmd == "inline" then
        if arg == "on" then db.inline = true
        elseif arg == "off" then db.inline = false
        else db.inline = not db.inline end
        if panel and panel.labelsToggle then panel.labelsToggle:SetChecked(db.inline) end
        if _G.AffixLensSyncCollectionLabelsToggle then _G.AffixLensSyncCollectionLabelsToggle() end
        refreshRequested = true
        updateWidgets()
        chat("In-slot labels " .. (db.inline and "enabled" or "disabled") .. ".")
    elseif cmd == "anchors" then
        if arg == "unlock" then
            setAnchorsUnlocked(true)
            chat("Button anchors unlocked. Drag either button to reposition; /affixes anchors lock to finish.")
        elseif arg == "lock" then
            setAnchorsUnlocked(false)
            chat("Button anchors locked.")
        elseif arg == "reset" then
            local prefs = anchorSettings()
            prefs.buttonX, prefs.buttonY = nil, nil
            applyButtonAnchor()
            setAnchorsUnlocked(false)
            chat("Button position reset to the character title bar.")
        else
            chat("Usage: /affixes anchors unlock | lock | reset")
        end
        return
    elseif cmd == "refresh" then
        chat("Rescanning equipped items.")
    elseif cmd == "debug" then
        updateWidgets()
        for i, entry in ipairs(slots) do
            if arg == "" or entry.label:lower():find(arg, 1, true) then
                local data = records[i]
                chat(entry.label .. ": " .. data.affix .. " | title=" .. (data.title or "?") ..
                     " | effect=" .. (data.effect or "none"))
            end
        end
        return
    elseif cmd == "show" then
        panelOpen = true
        if SlashCmdList.AFFIXLENSCOLLECTION then SlashCmdList.AFFIXLENSCOLLECTION("hide") end
    elseif cmd == "hide" then
        panelOpen = false
    elseif cmd == "" or cmd == "toggle" then
        panelOpen = not panelOpen
        if panelOpen and SlashCmdList.AFFIXLENSCOLLECTION then SlashCmdList.AFFIXLENSCOLLECTION("hide") end
    else
        chat("Commands: /affixes [show|hide|toggle|refresh|inline on|inline off|anchors unlock|anchors lock|anchors reset|debug head]")
        return
    end
    refreshRequested = true
    refreshPanelVisibility()
    if CharacterFrame:IsShown() then updateWidgets() end
end
