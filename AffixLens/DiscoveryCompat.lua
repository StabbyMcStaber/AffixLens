-- AffixLens discovery UI compatibility, v2.1.3 (WoW 3.3.5a).
-- Supplements the core bag scanner; never guesses affixes from item IDs.
local families={"Arcane Mind","Armor Rend","Bulwark","Cold","Feral Grace",
"Fortified by Pain","Frost Breath","Frozen Pulse","Infinite Star","Iron Will",
"Ironhide","Keen Strikes","Living Tide","Mender's Surge","Overwhelming Force",
"Pet Power","Quick Instincts","Relentless Crits","Shield Block","Spell Mastery",
"Spirit Surge","Stalwart","Temporal Flux","Thick Hide","Wellspring"}
local ranks={"VI","IV","III","II","V","I"}
local scan=CreateFrame("GameTooltip","AffixLensDiscoveryScanV213",UIParent,"GameTooltipTemplate")
scan:Hide()
local original=_G.AffixLensInspectBagItem
_G.AffixLensInspectBagItem=function(bag,slot)
    scan:SetOwner(UIParent,"ANCHOR_NONE")
    scan:ClearLines()
    scan:SetBagItem(bag,slot)
    local line=_G.AffixLensDiscoveryScanV213TextLeft1
    local name=tostring(line and line:GetText() or ""):gsub("\\+'","'")
    scan:Hide()
    for _,family in ipairs(families) do
        for _,rank in ipairs(ranks) do
            local suffix=" of "..family.." "..rank
            if #name>#suffix and name:sub(-#suffix):lower()==suffix:lower() then
                return family.." "..rank
            end
        end
    end
    return original and original(bag,slot) or nil
end
local tracked=setmetatable({},{__mode="k"})
local function marker(button,show)
    local f=tracked[button]
    if show and not f then
        f=CreateFrame("Frame",nil,button)
        f:SetWidth(23);f:SetHeight(24)
        f:SetPoint("TOPRIGHT",button,"TOPRIGHT",1,1)
        f:SetFrameStrata(button:GetFrameStrata())
        f:SetFrameLevel(button:GetFrameLevel()+8)
        f:EnableMouse(false)
        local rim=f:CreateTexture(nil,"BORDER")
        rim:SetTexture("Interface\\Buttons\\WHITE8X8")
        rim:SetVertexColor(1,0.75,0.1,1)
        rim:SetAllPoints(f)
        local dark=f:CreateTexture(nil,"ARTWORK")
        dark:SetTexture("Interface\\Buttons\\WHITE8X8")
        dark:SetVertexColor(0.08,0.04,0.03,0.94)
        dark:SetPoint("TOPLEFT",f,"TOPLEFT",1,-1)
        dark:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-1,1)
        local t=f:CreateFontString(nil,"OVERLAY")
        t:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",22,"OUTLINE")
        t:SetText("!")
        t:SetTextColor(1,0.93,0.08,1)
        t:SetShadowColor(0,0,0,1)
        t:SetShadowOffset(1,-1)
        t:SetPoint("CENTER",f,"CENTER")
        tracked[button]=f
    end
    if f then if show then f:Show() else f:Hide() end end
end
local function number(o,k)
    if o and type(o[k])=="number" then return o[k] end
end
local function attr(f,k)
    if f and f.GetAttribute then
        local ok,v=pcall(f.GetAttribute,f,k)
        if ok and type(v)=="number" then return v end
    end
end
local function location(b)
    if not (b and b.GetID) then return end
    local name=b.GetName and b:GetName() or ""
    local parent=b:GetParent()
    local info=b.info
    local bag=(b.GetBagID and b:GetBagID()) or number(b,"bagID") or
        number(b,"bag") or number(b,"bagIndex") or number(info,"bag") or
        number(info,"bagID") or attr(b,"bag") or attr(b,"bagID")
    local slot=number(b,"slot") or number(b,"slotID") or number(info,"slot")
        or number(info,"slotID") or attr(b,"slot") or attr(b,"slotID") or b:GetID()
    local namedBag,namedSlot=name:match("^ElvUI_ContainerFrameBag(%d+)Slot(%d+)$")
    if namedBag then bag=tonumber(namedBag);slot=tonumber(namedSlot) end
    if bag==nil and name:match("^ContainerFrame%d+Item%d+$")
        and parent and parent.GetID then bag=parent:GetID() end
    if bag==nil and parent then
        bag=number(parent,"bagID") or number(parent,"bag") or
            (name:find("ContainerFrame",1,true) and parent.GetID and parent:GetID())
    end
    if type(bag)~="number" or type(slot)~="number" then return end
    if bag<0 or bag>4 or slot<1 or slot>(GetContainerNumSlots(bag) or 0) then return end
    local link=GetContainerItemLink(bag,slot)
    if not link then return end
    if b.GetItemLink then
        local ok,visible=pcall(b.GetItemLink,b)
        if ok and type(visible)=="string" and visible~=link
            and visible:match("item:[^|]+")~=link:match("item:[^|]+") then return end
    end
    return bag,slot
end
local elapsed=0
local updater=CreateFrame("Frame")
updater:SetScript("OnUpdate",function(self,dt)
    elapsed=elapsed+dt
    if elapsed<1 then return end
    elapsed=0
    if not (EnumerateFrames and _G.AffixLensAffixLearned) then return end
    local seen={}
    local frame=EnumerateFrames()
    while frame do
        local typ=frame.GetObjectType and frame:GetObjectType()
        if (typ=="Button" or typ=="CheckButton") and frame:IsVisible() then
            local bag,slot=location(frame)
            if bag then
                seen[frame]=true
                local a=_G.AffixLensInspectBagItem(bag,slot)
                marker(frame,a and _G.AffixLensAffixLearned(a)==false)
            end
        end
        frame=EnumerateFrames(frame)
    end
    for b in pairs(tracked) do if not seen[b] then marker(b,false) end end
end)
SLASH_AFFIXLENSBAGTEST1="/affixbagtest"
SlashCmdList.AFFIXLENSBAGTEST=function()
    local total,count=0,0
    for bag=0,4 do
        for slot=1,(GetContainerNumSlots(bag) or 0) do
            if GetContainerItemLink(bag,slot) then
                total=total+1
                local a=_G.AffixLensInspectBagItem(bag,slot)
                if a and _G.AffixLensAffixLearned(a)==false then
                    count=count+1
                    DEFAULT_CHAT_FRAME:AddMessage("AffixLens test: bag "..bag.." slot "..slot.." unlearned "..a)
                end
            end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("AffixLens test: scanned "..total.." items; "..count.." unlearned affix item(s).")
end
SLASH_AFFIXLENSBAGFRAME1="/affixbagframe"
SlashCmdList.AFFIXLENSBAGFRAME=function()
    local f=GetMouseFocus and GetMouseFocus()
    for depth=0,3 do
        if not f then break end
        local name=f.GetName and f:GetName() or "(anonymous)"
        local typ=f.GetObjectType and f:GetObjectType() or "?"
        DEFAULT_CHAT_FRAME:AddMessage("AffixLens frame: level "..depth.." "..name.." ["..typ.."] ID="..tostring(f.GetID and f:GetID() or "nil"))
        f=f:GetParent()
    end
end
-- ElvUI can reparent/move the character pane after our original anchor
-- is created. Keep the existing saved relative offset attached to it.
local anchorTick=0
local anchor=CreateFrame("Frame")
anchor:SetScript("OnUpdate",function(self,dt)
    anchorTick=anchorTick+dt
    if anchorTick<0.5 then return end
    anchorTick=0
    local cf=_G.CharacterFrame
    local a=_G.AffixLensButtonAnchor
    if not (cf and a and cf:IsShown()) then return end
    local cfg=_G.AffixLensCharDB or {}
    local x=tonumber(cfg.buttonX) or 110
    local y=tonumber(cfg.buttonY) or -12
    local cl,ct=cf:GetLeft(),cf:GetTop()
    local al,at=a:GetLeft(),a:GetTop()
    if not (cl and ct and al and at) then return end
    local cs=cf:GetEffectiveScale() or 1
    local as=a:GetEffectiveScale() or 1
    if math.abs((cl+x)*cs-al*as)>4 or math.abs((ct+y)*cs-at*as)>4 then
        if not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")
            and MouseIsOver and MouseIsOver(a)) then
            a:ClearAllPoints()
            a:SetPoint("TOPLEFT",cf,"TOPLEFT",x,y)
        end
    end
end)
