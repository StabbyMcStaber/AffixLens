-- AffixLens inventory discovery indicators (WoW 3.3.5a).
-- Only the real bag-slot tooltip is examined; no itemID-only affix guesses.
local watcher=CreateFrame("Frame")
local elapsed=0
local ready=false
local previous={}
local marked={}
local badges={}
local function inspect()
    local counts,found={},{}
    if not _G.AffixLensInspectBagItem or not _G.AffixLensAffixLearned then return end
    for bag=0,4 do
        local slots=GetContainerNumSlots(bag) or 0
        for slot=1,slots do
            local link=GetContainerItemLink(bag,slot)
            if link then
                local affix=_G.AffixLensInspectBagItem(bag,slot)
                if affix and _G.AffixLensAffixLearned(affix)==false then
                    local token=link.."\031"..affix
                    local _,quantity=GetContainerItemInfo(bag,slot)
                    counts[token]=(counts[token] or 0)+(quantity or 1)
                    found[bag..":"..slot]={affix=affix,link=link,token=token}
                end
            end
        end
    end
    if ready and not (AffixLensDB and AffixLensDB.discoveryAlerts==false) then
        for token,count in pairs(counts) do
            if count>(previous[token] or 0) then
                local sample
                for _,entry in pairs(found) do
                    if entry.token==token then sample=entry;break end
                end
                if sample and DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffb794faAffixLens|r: |cffffd100Unlearned affix:|r "..sample.affix.." on "..sample.link)
                    if PlaySound then PlaySound("QUESTADDED") end
                end
            end
        end
    end
    previous=counts
    marked=found
    ready=true
end
local function updateBadges()
    -- The container UI can recycle frames between different bags.
    for index=1,NUM_CONTAINER_FRAMES or 13 do
        local container=_G["ContainerFrame"..index]
        if container then
            local bag=container:GetID()
            for buttonIndex=1,36 do
                local button=_G["ContainerFrame"..index.."Item"..buttonIndex]
                if button then
                    local key=bag..":"..button:GetID()
                    local badge=badges[button]
                    if marked[key] and container:IsShown() then
                        if not badge then
                            badge=button:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
                            badge:SetPoint("TOPRIGHT",button,"TOPRIGHT",1,1)
                            badge:SetText("|cffffd100!|r")
                            badges[button]=badge
                        end
                        badge:Show()
                    elseif badge then badge:Hide() end
                end
            end
        end
    end
end
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("BAG_UPDATE")
watcher:RegisterEvent("SPELLS_CHANGED")
watcher:RegisterEvent("LEARNED_SPELL_IN_TAB")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent",function(self,event)
    if event=="PLAYER_LOGIN" then
        ready=false
        previous={}
    end
    self.pending=true
end)
watcher:SetScript("OnUpdate",function(self,delta)
    elapsed=elapsed+delta
    if elapsed<0.6 then return end
    elapsed=0
    if self.pending then
        self.pending=false
        inspect()
    end
    updateBadges()
end)
SLASH_AFFIXLENSDISCOVERY1="/affixdiscover"
SlashCmdList.AFFIXLENSDISCOVERY=function(msg)
    AffixLensDB=AffixLensDB or {}
    local action=(msg or ""):lower():match("^%s*(%S+)")
    if action=="on" then AffixLensDB.discoveryAlerts=true
    elseif action=="off" then AffixLensDB.discoveryAlerts=false
    else
        DEFAULT_CHAT_FRAME:AddMessage("AffixLens: /affixdiscover on | off (bag markers remain visible)")
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("AffixLens: unlearned-affix notifications "..(AffixLensDB.discoveryAlerts and "enabled" or "disabled"))
end
