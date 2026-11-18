-- AffixLens 3.0.1 — Project Ebonhold V2 / WoW 3.3.5a (Lua 5.1)
-- Author: Stan
-- Neither character-sheet buttons nor character-sheet overlays are created.
AffixLens = AffixLens or {}
local A = AffixLens
A.version = "3.0.1"
A.roman = {"I", "II", "III", "IV", "V"}
A.categories = {"Offensive", "Defensive", "Resource", "Utility", "Mobility"}
A.prefix = "|cffc28cffAffixLens|r: "
A.slots = {
    {id= 1, name="Head",      categories={2,4}},
    {id= 2, name="Neck",      categories={1,3}},
    {id= 3, name="Shoulders", categories={2,4}},
    {id=15, name="Back",      categories={2,4}},
    {id= 5, name="Chest",     categories={2,4}},
    {id= 4, name="Shirt",     excluded=true},
    {id=19, name="Tabard",    excluded=true},
    {id= 9, name="Wrist",     categories={2,4}},
    {id=10, name="Hands",     categories={1,4}},
    {id= 6, name="Waist",     categories={2,4}},
    {id= 7, name="Legs",      categories={2,4}},
    {id= 8, name="Feet",      categories={2,5}},
    {id=11, name="Ring 1",    categories={1,3}},
    {id=12, name="Ring 2",    categories={1,3}},
    {id=13, name="Trinket 1",categories={1,2,3,4,5}},
    {id=14, name="Trinket 2",categories={1,2,3,4,5}},
    {id=16, name="Main Hand", categories={1}},
    {id=17, name="Off Hand",  categories={1}},
    -- Wands/ranged weapons became affixable after the V2 launch. Their
    -- category restrictions have not been independently verified: accept
    -- server-applied affixes without reporting an invented slot conflict.
    {id=18, name="Ranged",    skipCategoryCheck=true},
}
A.byId, A.byName, A.byEnchant, A.families = {}, {}, {}, {}
A.synced = false
A.catalogSource = "Snapshot fallback"
A.lastBuild = 0

function A.Chat(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(A.prefix .. tostring(msg)) end
end
function A.Clean(text)
    if not text then return "" end
    return tostring(text):gsub("\\+'", "'"):gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
end
function A.Effect(text)
    return A.Clean(text):gsub("@value@", ""):gsub("@range@", "")
end
function A.Normal(text)
    return A.Clean(text):lower():gsub("%s+", " ")
end
function A.GetSettings()
    AffixLensDB = AffixLensDB or {}
    local d = AffixLensDB
    if type(d.v3) ~= "table" then d.v3 = {} end
    local s=d.v3
    if not s.activeTab then s.activeTab = "Collection" end
    if s.minimapAngle == nil then s.minimapAngle = 2.4 end
    if s.alerts == nil then s.alerts = true end
    return s
end
function A.CategoryName(number)
    return A.categories[tonumber(number) or 0] or "Unknown"
end
function A.RankName(rank)
    return A.roman[tonumber(rank) or 0] or "?"
end
function A.IsSlotAllowed(slot, fam)
    if not slot or slot.excluded or not fam then return false end
    if slot.skipCategoryCheck then return true end
    for _, category in ipairs(slot.categories or {}) do
        if category == fam.category then return true end
    end
    return false
end
function A.BuildCatalog()
    local list, ids, names, enchants = {}, {}, {}, {}
    local nextSyntheticId=100000
    -- Full offline catalog provides preview descriptions even before server sync.
    for _, f in ipairs(AffixLensV2Fallback or {}) do
        local entry={id=f.id, name=f.name, category=f.category, mask=f.mask,
                     spec=f.spec, icon=f.icon, ranks={}, highest=0}
        for i=1,5 do
            local r=f.ranks[i]
            if r then entry.ranks[i]={spellId=r.spellId,enchantId=r.enchantId,
                applyCost=r.applyCost,extractCost=r.extractCost,text=r.text} end
        end
        ids[f.id]=entry
        names[A.Normal(f.name)]=entry
    end

    -- Prefer the LIVE Ebonhold definitions whenever present (future-proof).
    local pe=_G.ProjectEbonhold
    local db=pe and pe.AffixDatabase
    if type(db)=="table" and type(db.families)=="table" then
        for key, source in pairs(db.families) do
            if type(source)=="table" and type(source.name)=="string" then
                local entry=names[A.Normal(source.name)]
                local id=tonumber(source.familyId or source.id or key)
                if not entry then
                    if not id then nextSyntheticId=nextSyntheticId+1; id=nextSyntheticId end
                    entry={id=id, name=source.name, ranks={},highest=0}
                    ids[entry.id]=entry
                    names[A.Normal(entry.name)]=entry
                end
                entry.name=source.name
                entry.category=tonumber(source.category) or entry.category
                entry.mask=source.classMask or entry.mask
                entry.spec=source.spec or entry.spec
                entry.icon=source.icon or entry.icon
                for i=1,5 do
                    local rank=source.ranks and source.ranks[i]
                    if type(rank)=="table" then
                        entry.ranks[i]={spellId=rank.spellId, enchantId=rank.enchantId,
                            applyCost=rank.applyCost, extractCost=rank.extractCost,
                            text=rank.text}
                    end
                end
            end
        end
        A.catalogSource="Live V2 database"
    else
        A.catalogSource="V2 snapshot fallback"
    end
    -- Includes ID zero: never use #table for id-indexed Ebonhold catalogs.
    for _, entry in pairs(ids) do
        list[#list+1]=entry
        for rank=1,5 do
            local r=entry.ranks and entry.ranks[rank]
            if r and tonumber(r.enchantId) then
                enchants[tonumber(r.enchantId)]={family=entry,rank=rank}
            end
        end
    end
    table.sort(list,function(a,b) return A.Normal(a.name)<A.Normal(b.name) end)

    -- Only actual current server knowledge determines ownership.
    local svc=_G.ExtractionService
    local server=svc and svc.learnedAffixes
    local confirmed=(type(server)=="table" and #server>0)
    if confirmed then
        for _, source in ipairs(server) do
            if type(source)=="table" then
                local fam=ids[tonumber(source.familyId) or -1]
                    or names[A.Normal(source.familyName or "")]
                local rank=tonumber(source.rank)
                if fam then
                    if source.learned==true and rank and rank>=1 and rank<=5 then
                        fam.highest=math.max(fam.highest,rank)
                    end
                    if rank and rank>=1 and rank<=5 then
                        local r=fam.ranks[rank] or {}
                        -- Server records may have fresher descriptions than the database.
                        if source.text then r.text=source.text end
                        if source.icon then fam.icon=source.icon end
                        if source.enchantId then
                            r.enchantId=source.enchantId
                            enchants[tonumber(source.enchantId)]={family=fam,rank=rank}
                        end
                        if source.applyCost then r.applyCost=source.applyCost end
                        fam.ranks[rank]=r
                    end
                end
            end
        end
    end
    A.families, A.byId, A.byName, A.byEnchant=list,ids,names,enchants
    A.synced=confirmed
    A.lastBuild=GetTime()
    return #list
end

function A.FindFromText(title, base)
    title=A.Clean(title)
    base=A.Clean(base)
    if title=="" then return nil end
    -- Prefer a true suffix on the scanned item tooltip, not merely its item ID.
    local name,roman
    if base~="" and title:sub(1,#base)==base then
        name,roman=title:sub(#base+1):match("^%s+[Oo][Ff]%s+(.+)%s+([IVX]+)$")
    end
    if not name then
        name,roman=title:match("%s+[Oo][Ff]%s+(.+)%s+([IVX]+)$")
    end
    if name and roman then
        local fam=A.byName[A.Normal(name)]
        if fam then
            for i=1,5 do if A.roman[i]==roman then return fam,i end end
        end
    end
    return nil
end
local scan=CreateFrame("GameTooltip","AffixLensV3TooltipScan",UIParent,"GameTooltipTemplate")
scan:Hide()
function A.Detect(link, title, base)
    if not link then return nil end
    local enchantId=tonumber(link:match("item:%d+:(%d+)"))
    local mapped=enchantId and A.byEnchant[enchantId]
    if mapped then return mapped.family,mapped.rank end
    return A.FindFromText(title,base)
end
function A.ItemFromInventory(slot)
    local link=GetInventoryItemLink("player",slot.id)
    if not link then return {slot=slot,status="empty",name="Empty"} end
    local itemId=tonumber(link:match("item:(%d+)"))
    local base=itemId and GetItemInfo(itemId) or nil
    local result={slot=slot,status="none",name=A.Clean(base or "Loading item..."),link=link}
    if slot.excluded then result.status="excluded";return result end
    scan:SetOwner(UIParent,"ANCHOR_NONE")
    scan:ClearLines()
    scan:SetInventoryItem("player",slot.id)
    local fs=_G.AffixLensV3TooltipScanTextLeft1
    local title=fs and A.Clean(fs:GetText()) or ""
    scan:Hide()
    local fam,rank=A.Detect(link,title,base)
    if fam then
        result.family=fam;result.rank=rank;result.status="affix"
        result.affix=fam.name.." "..A.RankName(rank)
        result.valid=A.IsSlotAllowed(slot,fam)
    elseif not base and title=="" then
        result.status="loading"
    end
    return result
end
function A.ItemFromBag(bag,slot)
    local link=GetContainerItemLink(bag,slot)
    if not link then return nil end
    local itemId=tonumber(link:match("item:(%d+)"))
    local base=itemId and GetItemInfo(itemId) or nil
    scan:SetOwner(UIParent,"ANCHOR_NONE")
    scan:ClearLines()
    scan:SetBagItem(bag,slot)
    local fs=_G.AffixLensV3TooltipScanTextLeft1
    local title=fs and A.Clean(fs:GetText()) or ""
    scan:Hide()
    local fam,rank=A.Detect(link,title,base)
    return fam,rank,link
end
function A.AffixTooltip(owner,fam,rank,heading)
    if not fam then return end
    rank=math.max(1,math.min(5,tonumber(rank) or 5))
    local data=fam.ranks[rank]
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(fam.name.." "..A.RankName(rank),0.83,0.60,1)
    GameTooltip:AddLine(A.CategoryName(fam.category).."  |  "..((fam.spec and fam.spec~="") and fam.spec or "Any specialization"),0.72,0.80,0.94)
    GameTooltip:AddLine(" ")
    if data and data.text then
        GameTooltip:AddLine(A.Effect(data.text),1,0.94,0.75,true)
    else
        GameTooltip:AddLine("Effect not available in the current client catalog.",0.75,0.75,0.75,true)
    end
    GameTooltip:AddLine(" ")
    if A.synced then
        if fam.highest and fam.highest>0 then
            GameTooltip:AddLine("Highest learned: "..A.RankName(fam.highest),0.35,1,0.48)
            if rank<fam.highest then
                GameTooltip:AddLine("Lower ranks are superseded in V2.",0.75,0.75,0.75,true)
            end
        else
            GameTooltip:AddLine("Not learned",0.95,0.55,0.45)
        end
    else
        GameTooltip:AddLine("Learned ranks: awaiting live server synchronization",1,0.75,0.27,true)
    end
    if data and data.applyCost then
        GameTooltip:AddLine("Apply cost: "..(GetMoneyString and GetMoneyString(data.applyCost) or tostring(data.applyCost).." copper"),0.75,0.75,0.75)
    end
    if heading then GameTooltip:AddLine(heading,0.6,0.6,0.6,true) end
    GameTooltip:Show()
end
function A.RequestSync()
    local svc=_G.ExtractionService
    if svc and type(svc.RequestLearnedAffixes)=="function" then
        local ok=pcall(svc.RequestLearnedAffixes)
        if not ok then pcall(svc.RequestLearnedAffixes,svc) end
    end
end

local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")
events:RegisterEvent("LEARNED_SPELL_IN_TAB")
events:SetScript("OnEvent",function(self,event,arg)
    if event=="UNIT_INVENTORY_CHANGED" and arg~="player" then return end
    if event=="PLAYER_LOGIN" then
        A.GetSettings()
        A.BuildCatalog()
        A.RequestSync()
        if A.CreateUI then A.CreateUI() end
        if A.CreateMinimap then A.CreateMinimap() end
    elseif event=="PLAYER_ENTERING_WORLD" or event=="LEARNED_SPELL_IN_TAB" then
        A.RequestSync()
        A.BuildCatalog()
    end
    if A.FlagRefresh then A.FlagRefresh() end
end)
local tick=0
 events:SetScript("OnUpdate",function(self,elapsed)
    tick=tick+elapsed
    if tick<3 then return end
    tick=0
    if A.window and A.window:IsShown() then
        A.BuildCatalog()
        if A.Render then A.Render() end
    end
end)
SLASH_AFFIXLENS1="/affixlens"
SLASH_AFFIXLENS2="/affixes"
SlashCmdList.AFFIXLENS=function(msg)
    local cmd,arg=(msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd=="refresh" or cmd=="scan" then
        A.RequestSync();A.BuildCatalog()
        if A.Render then A.Render() end
        A.Chat("Refreshed: "..#A.families.." V2 families ("..(A.synced and "live learned ranks" or "waiting for learned ranks")..").")
    elseif cmd=="collection" or cmd=="equipped" then
        if A.OpenTab then A.OpenTab(cmd=="collection" and "Collection" or "Equipped") end
    elseif cmd=="minimap" and arg=="reset" then
        local cfg=A.GetSettings()
        cfg.minimapAngle=2.4
        if A.PlaceMinimap then A.PlaceMinimap() end
        A.Chat("Minimap icon position reset.")
    elseif cmd=="help" then
        A.Chat("Commands: /affixlens | collection | equipped | refresh | minimap reset")
    else
        if A.Toggle then A.Toggle() end
    end
end
SLASH_AFFIXLENSCOLLECTION1="/affixcollection"
SlashCmdList.AFFIXLENSCOLLECTION=function(msg)
    if A.OpenTab then A.OpenTab("Collection") end
end
