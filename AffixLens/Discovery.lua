-- Upgrade-aware bag discovery for V2: rank II is NOT an upgrade when rank III is known.
-- Runs independently of the collection UI; never marks items from item IDs alone.
local A=AffixLens
local watcher=CreateFrame("Frame")
local elapsed=0
local needScan=true
local marked={}
local markers=setmetatable({},{__mode="k"})
local ready=false

local function scanBags()
    if not A.synced then
        needScan=true
        marked={}
        return
    end
    local new={}
    for bag=0,4 do
        for slot=1,(GetContainerNumSlots(bag) or 0) do
            if GetContainerItemLink(bag,slot) then
                local fam,rank,link=A.ItemFromBag(bag,slot)
                if fam and rank and rank>(fam.highest or 0) then
                    new[bag..":"..slot]={family=fam,rank=rank,link=link}
                end
            end
        end
    end
    if ready and A.GetSettings().alerts then
        for key,item in pairs(new) do
            local old=marked[key]
            if not old or old.family.id~=item.family.id or old.rank~=item.rank then
                A.Chat("Unlearned upgrade: "..item.family.name.." "..A.RankName(item.rank).." on "..(item.link or "an item"))
                if PlaySound then PlaySound("QUESTADDED") end
            end
        end
    end
    marked=new
    ready=true
    needScan=false
end
local function mark(button,show)
    if not button then return end
    local f=markers[button]
    if show and not f then
        f=CreateFrame("Frame",nil,button)
        f:SetWidth(22);f:SetHeight(23)
        f:SetPoint("TOPRIGHT",button,"TOPRIGHT",1,1)
        f:SetFrameLevel(button:GetFrameLevel()+7)
        f:EnableMouse(false)
        local t=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
        t:SetFont(STANDARD_TEXT_FONT,21,"OUTLINE")
        t:SetPoint("CENTER",0,0)
        t:SetText("!")
        t:SetTextColor(1,0.90,0.07)
        markers[button]=f
    end
    if f then
        if show then f:Show() else f:Hide() end
    end
end
local function bagSlotFromButton(b)
    if not b or not b.GetID then return nil end
    local name=(b.GetName and b:GetName()) or ""
    local bag,slot
    local b1,s1=name:match("^ElvUI_ContainerFrameBag(%d+)Slot(%d+)$")
    if b1 then bag=tonumber(b1);slot=tonumber(s1) end
    if name:match("^ContainerFrame%d+Item%d+$") then
        local p=b:GetParent()
        bag=(p and p.GetID) and p:GetID() or nil
        slot=b:GetID()
    end
    if not bag and b.GetBagID then bag=b:GetBagID() end
    if not bag and type(b.bagID)=="number" then bag=b.bagID end
    if not bag and type(b.bag)=="number" then bag=b.bag end
    if not slot and type(b.slotID)=="number" then slot=b.slotID end
    if not slot and type(b.slot)=="number" then slot=b.slot end
    if not bag and b.info and type(b.info.bag)=="number" then bag=b.info.bag end
    if not slot and b.info and type(b.info.slot)=="number" then slot=b.info.slot end
    -- Do not put markers on arbitrary buttons with numeric IDs (false positives).
    if not (name:find("Container",1,true) or b.GetBagID or type(b.bagID)=="number") then return nil end
    if type(bag)~="number" or type(slot)~="number" then return nil end
    if bag<0 or bag>4 or slot<1 or slot>(GetContainerNumSlots(bag) or 0) then return nil end
    return bag,slot
end
local function updateBadges()
    local active={}
    -- Handles Blizzard bags and many custom container buttons without hooking bags.
    if EnumerateFrames then
        local frame=EnumerateFrames()
        while frame do
            local typ=frame.GetObjectType and frame:GetObjectType()
            if (typ=="Button" or typ=="CheckButton") and frame:IsVisible() then
                local bag,slot=bagSlotFromButton(frame)
                if bag then
                    active[frame]=true
                    local match=marked[bag..":"..slot]
                    mark(frame,match~=nil)
                end
            end
            frame=EnumerateFrames(frame)
        end
    end
    for frame in pairs(markers) do
        if not active[frame] then mark(frame,false) end
    end
end
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("BAG_UPDATE")
watcher:RegisterEvent("LEARNED_SPELL_IN_TAB")
watcher:SetScript("OnEvent",function(self,event)
    if event=="PLAYER_LOGIN" then ready=false end
    needScan=true
end)
watcher:SetScript("OnUpdate",function(self,dt)
    elapsed=elapsed+dt
    if elapsed<1 then return end
    elapsed=0
    if needScan or not A.synced then
        if GetTime()-A.lastBuild>2 then A.BuildCatalog() end
        scanBags()
    end
    updateBadges()
end)
SLASH_AFFIXLENSDISCOVERY1="/affixdiscover"
SlashCmdList.AFFIXLENSDISCOVERY=function(msg)
    local cmd=(msg or ""):lower():match("^%s*(%S+)")
    if cmd=="on" then A.GetSettings().alerts=true
    elseif cmd=="off" then A.GetSettings().alerts=false
    else
        A.Chat("/affixdiscover on | off — bag upgrade markers remain visible.")
        return
    end
    A.Chat("Upgrade alerts "..(A.GetSettings().alerts and "enabled" or "disabled")..".")
end
SLASH_AFFIXLENSBAGTEST1="/affixbagtest"
SlashCmdList.AFFIXLENSBAGTEST=function()
    A.BuildCatalog();scanBags()
    local count=0
    for _,item in pairs(marked) do
        count=count+1
        A.Chat("Upgrade: "..item.family.name.." "..A.RankName(item.rank).." on "..(item.link or "item"))
    end
    A.Chat(count.." bag upgrades found"..(A.synced and "." or " (server ranks not synced yet)."))
end
