-- AffixLens Collection, initial AffixDex-compatible integration (WoW 3.3.5a)
-- Inspired by AffixDex by Noturpalguy, MIT (see THIRD_PARTY_LICENSES.txt).
local ranks = {"I","II","III","IV","V","VI"}
-- Conservative fallback when Ebonhold has not supplied the complete rank catalog.
local fallbackRankCaps = {["spell mastery"]=4}
local rankCap = {}
local function clean(s)
    return (tostring(s or ""):gsub("\\+'", "'"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local function split(s)
    s=clean(s)
    local base,rank=s:match("^(.-)%s+([IVXLC]+)$")
    if base then return base,rank end
    return s,nil
end
local aliases = { ["inner light"]="Spirit Surge", ["keen strike"]="Keen Strikes", ["precision"]="Cold", ["swift footwork"]="Feral Grace", ["enduring flesh"]="Ironhide", ["block"]="Shield Block" }
local fallback = {"Arcane Mind","Armor Rend","Bulwark","Cold","Feral Grace","Fortified by Pain","Frost Breath","Frozen Pulse","Infinite Star","Iron Will","Ironhide","Keen Strikes","Living Tide","Mender's Surge","Overwhelming Force","Pet Power","Quick Instincts","Relentless Crits","Shield Block","Spell Mastery","Spirit Surge","Stalwart","Temporal Flux","Thick Hide","Wellspring"}
local weaponFallback = {"Affliction","Azzinoth","Bladestorm","Bloodlust","Clarity","Concussion","Decay","Devastation","Dissolution","Execution","Ferocity","Fire Blast","Flame Wrath","Flurry","Fortification","Frailty","Frost Arrow","Fury","Glaciation","Hemorrhage","Incineration","Judgement","Julie's Blessing","Keeper's Sting","Maiming","Permafrost","Pyromancy","Rending","Resurgence","Shackling","Shahram","Speed","Sulfuras","Thunderfury","Twin Shot","Undead","Val'anyr","Vampirism","Venom","Vulnerability","Wilds"}
local catalog, learned = {}, {}
local frame, scroller, list, searchBox, status, viewButton
local lastStamp, dirty = 0, true
local charButton
local labelsToggle
local function syncLabelsToggle()
    if labelsToggle then
        labelsToggle:SetChecked(not (AffixLensDB and AffixLensDB.inline == false))
    end
end
_G.AffixLensSyncCollectionLabelsToggle = syncLabelsToggle
local function charDB()
    AffixLensCharDB = AffixLensCharDB or {}
    AffixLensCharDB.learned = AffixLensCharDB.learned or {}
    return AffixLensCharDB
end
local function add(name,weapon,icon)
    local base=split(name)
    base=aliases[base:lower()] or base
    local key=base:lower()
    catalog[key]=catalog[key] or {name=base,weapon=weapon,icon=icon}
    if weapon then catalog[key].weapon=true end
    if icon then catalog[key].icon=icon end
    if key=="shield block" then catalog[key].name="Block" end
    return key
end
local function record(name)
    local base,rank=split(name)
    local key=add(base,false)
    learned[key]=learned[key] or {}
    local id=rank or "weapon"
    if not learned[key][id] then learned[key][id]=true; charDB().learned[key]=learned[key] end
end
local function rescan()
    -- Preserve previously learned affixes when the server hasn't synchronized yet.
    catalog={}
    rankCap={}
    for _,name in ipairs(fallback) do add(name,false) end
    for _,name in ipairs(weaponFallback) do add(name,true) end
    learned=charDB().learned
    local svc=_G.ExtractionService
    local server=svc and svc.learnedAffixes
    local source="Fallback catalog"
    if type(server)=="table" and #server>0 then
        -- Merge authoritative server entries into the fallback catalog so
        -- unlearned families absent from a learned-only response remain visible.
        for _,a in ipairs(server) do
            if type(a)=="table" and type(a.name)=="string" then
                local base, rank = split(a.name)
                local key = add(a.name,a.weaponOnly,a.icon)
                if rank then
                    for ri, roman in ipairs(ranks) do
                        if roman == rank then rankCap[key]=math.max(rankCap[key] or 0,ri) end
                    end
                end
                if a.learned then record(a.name) end
            end
        end
        -- Retain locally known families omitted by a partial server response.
        add("Shield Block",false)
        source="Ebonhold server catalog"
    else
        -- Spellbook fallback: only mark spell names matching catalog entries.
        if GetNumSpellTabs and GetSpellTabInfo and GetSpellName then
            for tab=1,GetNumSpellTabs() do
                local _,_,offset,count=GetSpellTabInfo(tab)
                for i=offset+1,offset+count do
                    local spellName=GetSpellName(i,BOOKTYPE_SPELL or "spell")
                    if spellName then
                        local base=split(spellName)
                        if catalog[base:lower()] then record(spellName) end
                    end
                end
            end
        end
    end
    lastStamp=GetTime()
    dirty=false
    return source
end
-- Old saved data may contain either naming convention. Both are the same family.
local function learnedRanks(key)
    if key~="shield block" then return learned[key] end
    local official=learned["shield block"]
    local legacy=learned.block
    if not legacy then return official end
    if not official then return legacy end
    local combined={}
    for rank,value in pairs(official) do if value then combined[rank]=true end end
    for rank,value in pairs(legacy) do if value then combined[rank]=true end end
    return combined
end
-- Resolve the item-tooltip name "Block" against the server's "Shield Block".
_G.AffixLensAffixLearned = function(name)
    if not name or name=="" then return nil end
    if dirty or GetTime()-lastStamp>10 then rescan() end
    local base,rank=split(name)
    base=base:gsub("^[Oo][Ff]%s+","")
    base=aliases[base:lower()] or base
    local key=base:lower()
    local family=catalog[key]
    if not family then return nil end
    local id=family.weapon and "weapon" or rank
    if not id then return nil end
    local known=learnedRanks(key)
    return (known and known[id]) and true or false
end
local function makeText(parent,size)
    local t=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    t:SetFont(STANDARD_TEXT_FONT,size or 12,"OUTLINE")
    t:SetJustifyH("LEFT")
    return t
end
local rows={}
local ROW_HEIGHT = 23
local MIN_WIDTH, MIN_HEIGHT = 555, 350
local MAX_WIDTH, MAX_HEIGHT = 1050, 780
local function collectionPrefs()
    local prefs=charDB()
    prefs.collection=prefs.collection or {}
    return prefs.collection
end
local function layout()
    if not frame then return end
    local w,h=frame:GetWidth(),frame:GetHeight()
    local visible=math.min(#rows,math.max(1,math.floor((h-130)/ROW_HEIGHT)))
    scroller:SetWidth(w-52)
    scroller:SetHeight(visible*ROW_HEIGHT)
    local nameWidth=math.max(155,math.min(315,math.floor((w-90)*0.38)))
    for i,row in ipairs(rows) do
        row:SetWidth(w-58)
        row.name:SetWidth(nameWidth)
        row.ranks:ClearAllPoints()
        row.ranks:SetPoint("LEFT",row,"LEFT",nameWidth+35,0)
        row.ranks:SetWidth(math.max(80,w-nameWidth-100))
        if i<=visible then row:Show() else row:Hide() end
    end
    frame.visibleRows=visible
end
local function render()
    if not frame or not frame:IsShown() then return end
    local source=rescan()
    local query=clean(searchBox:GetText() or ""):lower()
    local armor, weapons = {}, {}
    for key,a in pairs(catalog) do
        if query=="" or key:find(query,1,true) or a.name:lower():find(query,1,true) then
            if a.weapon then weapons[#weapons+1]=a else armor[#armor+1]=a end
        end
    end
    local alphabetically=function(a,b) return a.name:lower()<b.name:lower() end
    table.sort(armor,alphabetically)
    table.sort(weapons,alphabetically)
    -- Sections stay in order, while each section is independently alphabetical.
    -- Section headings live in the scroll data so they never cover affix rows.
    local sorted={}
    sorted[#sorted+1]={section="ARMOR  -  RANKED AFFIXES", size=#armor}
    for _,a in ipairs(armor) do sorted[#sorted+1]=a end
    sorted[#sorted+1]={section="WEAPON  -  LEARNED STATUS", size=#weapons}
    for _,a in ipairs(weapons) do sorted[#sorted+1]=a end
    local count=0
    for _,t in pairs(learned) do for _ in pairs(t) do count=count+1 end end
    status:SetText((#armor+#weapons).." families ("..#armor.." armor / "..#weapons.." weapon) | "..count.." learned | "..source)
    for _,row in ipairs(rows) do row:Hide() end
    local offset=FauxScrollFrame_GetOffset(scroller)
    FauxScrollFrame_Update(scroller,#sorted,frame.visibleRows or 12,ROW_HEIGHT)
    for i,row in ipairs(rows) do
        local a=i<=(frame.visibleRows or 12) and sorted[i+offset] or nil
        if a then
            row:Show()
            if a.section then
                row.icon:Hide()
                row.name:SetText("|cffffd100"..a.section.." ("..a.size..")|r")
                row.name:SetWidth(frame:GetWidth()-95)
                row.ranks:SetText("")
                row:SetScript("OnEnter",nil)
                row:SetScript("OnLeave",nil)
            else
                row.icon:Show()
                row.name:SetText(a.name)
                row.icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local key=a.name:lower()
                local parts={}
                local known=learnedRanks(key)
                if a.weapon then
                    parts[1]=known and known.weapon and "|cff40ef80LEARNED|r" or "|cff888888Not learned|r"
                else
                    local cap = rankCap[key] or fallbackRankCaps[key] or 6
                    for ri=1,cap do
                        local rank=ranks[ri]
                        parts[#parts+1]=(known and known[rank]) and ("|cff40ef80"..rank.."|r") or ("|cff777777"..rank.."|r")
                    end
                end
                row.ranks:SetText(table.concat(parts,"  "))
                row:SetScript("OnEnter",function(self)
                    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                    GameTooltip:AddLine(a.name,1,0.85,0.3)
                    GameTooltip:AddLine(a.weapon and "Weapon-only affix" or "Ranked affix",0.8,0.8,0.8)
                    GameTooltip:AddLine("Green = learned; gray = not learned",0.7,0.7,0.7)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            end
        end
    end
end
local function createUI()
    if frame then return end
    frame=CreateFrame("Frame","AffixLensCollectionWindow",UIParent)
    local prefs=collectionPrefs()
    frame:SetWidth(math.max(MIN_WIDTH,math.min(MAX_WIDTH,tonumber(prefs.width) or 555)))
    frame:SetHeight(math.max(MIN_HEIGHT,math.min(MAX_HEIGHT,tonumber(prefs.height) or 426)))
    frame:SetPoint("CENTER");frame:SetFrameStrata("DIALOG")
    frame:SetResizable(true);frame:SetMinResize(MIN_WIDTH,MIN_HEIGHT);frame:SetMaxResize(MAX_WIDTH,MAX_HEIGHT)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true);frame:EnableMouse(true)
    local dragBar=CreateFrame("Frame",nil,frame)
    dragBar:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-8)
    dragBar:SetWidth(265);dragBar:SetHeight(33)
    dragBar:EnableMouse(true);dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart",function() frame:StartMoving() end)
    dragBar:SetScript("OnDragStop",function() frame:StopMovingOrSizing() end)
    frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=28,insets={left=9,right=9,top=9,bottom=9}})
    frame:SetBackdropColor(0.05,0.04,0.08,0.94)
    local header=makeText(frame,17);header:SetPoint("TOPLEFT",24,-20);header:SetText("AffixLens - Collection")
    local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton");close:SetPoint("TOPRIGHT",-5,-6)
    local eq=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    eq:SetWidth(117);eq:SetHeight(24);eq:SetPoint("TOPRIGHT",close,"TOPLEFT",-9,-5)
    eq:SetText("Equipment")
    eq:SetFrameLevel(frame:GetFrameLevel() + 15)
    eq:SetScript("OnClick",function()
        frame:Hide()
        if SlashCmdList.AFFIXLENS then SlashCmdList.AFFIXLENS("show") end
    end)
    -- A second control for the same persisted setting used by Equipment View.
    -- No separate saved variable: both windows always represent one preference.
    labelsToggle=CreateFrame("CheckButton","AffixLensCollectionLabelsToggle",frame,"UICheckButtonTemplate")
    labelsToggle:SetWidth(22);labelsToggle:SetHeight(22)
    local toggleBackground=CreateFrame("Frame",nil,frame)
    toggleBackground:SetWidth(205);toggleBackground:SetHeight(28)
    toggleBackground:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-18,8)
    toggleBackground:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,insets={left=3,right=3,top=3,bottom=3}})
    toggleBackground:SetBackdropColor(0.02,0.02,0.03,0.96)
    toggleBackground:SetBackdropBorderColor(0.65,0.55,0.28,1)
    toggleBackground:SetFrameLevel(frame:GetFrameLevel()+12)
    labelsToggle:SetParent(toggleBackground)
    labelsToggle:ClearAllPoints()
    labelsToggle:SetPoint("RIGHT",toggleBackground,"RIGHT",-7,0)
    labelsToggle:SetFrameLevel(toggleBackground:GetFrameLevel()+2)
    local labelsCaption=makeText(toggleBackground,11)
    labelsCaption:SetPoint("RIGHT",labelsToggle,"LEFT",-5,0)
    labelsCaption:SetText("Show Equipment Labels")
    labelsToggle:SetScript("OnClick",function(self)
        if SlashCmdList.AFFIXLENS then
            SlashCmdList.AFFIXLENS(self:GetChecked() and "inline on" or "inline off")
        else
            AffixLensDB=AffixLensDB or {}
            AffixLensDB.inline=self:GetChecked() and true or false
        end
        syncLabelsToggle()
    end)
    labelsToggle:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:SetText("Show affix labels on the character equipment slots")
        GameTooltip:Show()
    end)
    labelsToggle:SetScript("OnLeave",function() GameTooltip:Hide() end)
    syncLabelsToggle()
    local searchBackground = CreateFrame("Frame",nil,frame)
    searchBackground:SetWidth(232);searchBackground:SetHeight(29)
    searchBackground:SetPoint("TOPLEFT",frame,"TOPLEFT",24,-51)
    searchBackground:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=13,insets={left=4,right=4,top=4,bottom=4}})
    searchBackground:SetBackdropColor(0.04,0.04,0.06,0.95)
    searchBackground:SetBackdropBorderColor(0.75,0.63,0.27,1)
    searchBox=CreateFrame("EditBox",nil,frame)
    searchBox:SetWidth(202);searchBox:SetHeight(22)
    searchBox:SetPoint("LEFT",searchBackground,"LEFT",14,0);searchBox:SetAutoFocus(false)
    searchBox:SetTextColor(1,1,1)
    searchBox:SetFont(STANDARD_TEXT_FONT,13,"")
    searchBox:SetMaxLetters(60)
    local hint=makeText(frame,12);hint:SetPoint("LEFT",searchBackground,"RIGHT",12,0);hint:SetText("|cffffd100Search affixes|r")
    searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
    local scroll=CreateFrame("ScrollFrame","AffixLensCollectionScroll",frame,"FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",frame,"TOPLEFT",15,-93);scroll:SetWidth(503);scroll:SetHeight(276)
    scroller=scroll
    scroll:SetScript("OnVerticalScroll",function(self,delta) FauxScrollFrame_OnVerticalScroll(self,delta,23,render) end)
    for i=1,28 do
        local row=CreateFrame("Button",nil,frame)
        row:SetHeight(22);row:SetWidth(495);row:SetPoint("TOPLEFT",frame,"TOPLEFT",29,-98-(i-1)*23)
        local icon=row:CreateTexture(nil,"ARTWORK");icon:SetWidth(19);icon:SetHeight(19);icon:SetPoint("LEFT",0,0);row.icon=icon
        local name=makeText(row,12);name:SetPoint("LEFT",icon,"RIGHT",6,0);name:SetWidth(155);row.name=name
        local v=makeText(row,12);v:SetPoint("LEFT",row,"LEFT",190,0);v:SetWidth(295);row.ranks=v
        rows[i]=row
    end
    status=makeText(frame,11);status:SetPoint("BOTTOMLEFT",24,21);status:SetWidth(265)
    searchBox:SetScript("OnTextChanged",function() FauxScrollFrame_SetOffset(scroller,0);render() end)
    local grip=CreateFrame("Button",nil,frame)
    grip:SetWidth(19);grip:SetHeight(19);grip:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-8,8)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:EnableMouse(true);grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart",function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnDragStop",function()
        frame:StopMovingOrSizing()
        local p=collectionPrefs();p.width=math.floor(frame:GetWidth()+0.5);p.height=math.floor(frame:GetHeight()+0.5)
        layout();render()
    end)
    frame:SetScript("OnSizeChanged",function() layout();render() end)
    layout()
    frame:SetScript("OnShow",function() syncLabelsToggle();layout();render() end)
    frame:Hide()
end
-- Explicit entry point for the equipment panel's Collection button.
_G.AffixLensShowCollection = function()
    if SlashCmdList.AFFIXLENSCOLLECTION then SlashCmdList.AFFIXLENSCOLLECTION("show") end
end
SLASH_AFFIXLENSCOLLECTION1="/affixcollection"
SlashCmdList.AFFIXLENSCOLLECTION=function(msg)
    local action=(msg or ""):lower():match("^%s*(%S*)")
    if action=="hide" then
        if frame then frame:Hide() end
        return
    end
    if action=="scan" then
        createUI(); render(); DEFAULT_CHAT_FRAME:AddMessage("AffixLens: collection rescanned.")
        return
    end
    -- Explicit show also switches away from equipment. A regular button
    -- press toggles the Collection view closed if already shown.
    local shouldShow = action=="show" or not (frame and frame:IsShown())
    if shouldShow then
        if SlashCmdList.AFFIXLENS then SlashCmdList.AFFIXLENS("hide") end
        createUI()
        frame:Show()
    elseif frame then
        frame:Hide()
    end
end
local event=CreateFrame("Frame");event:RegisterEvent("PLAYER_LOGIN");event:RegisterEvent("LEARNED_SPELL_IN_TAB")
event:SetScript("OnEvent",function(self,e)
    if e=="PLAYER_LOGIN" then
        charDB()
        if _G.ExtractionService and ExtractionService.RequestLearnedAffixes then pcall(ExtractionService.RequestLearnedAffixes) end
    end
    dirty=true
end)
event:SetScript("OnUpdate",function(self,delta)
    if not charButton and _G.AffixLensToggle and _G.CharacterFrame then
        charButton=CreateFrame("Button","AffixLensCollectionToggle",_G.AffixLensButtonAnchor or CharacterFrame,"UIPanelButtonTemplate")
        charButton:SetWidth(69);charButton:SetHeight(19)
        charButton:SetText("Collection")
        charButton:SetPoint("LEFT",_G.AffixLensToggle,"RIGHT",3,0)
        charButton:RegisterForDrag("LeftButton")
        charButton:SetScript("OnDragStart",function() if _G.AffixLensStartAnchorDrag then _G.AffixLensStartAnchorDrag() end end)
        charButton:SetScript("OnDragStop",function() if _G.AffixLensStopAnchorDrag then _G.AffixLensStopAnchorDrag() end end)
        charButton:SetFrameLevel(_G.AffixLensToggle:GetFrameLevel())
        charButton:SetScript("OnClick",function() SlashCmdList.AFFIXLENSCOLLECTION("") end)
        -- The title bar is shared by Character, Reputation, Skills and Currency.
        -- Mirror the Affix View button's visibility instead of inheriting only
        -- CharacterFrame visibility from the movable button anchor.
        local function syncCharacterButton()
            if _G.AffixLensToggle and _G.AffixLensToggle:IsShown() then
                charButton:Show()
            else
                charButton:Hide()
            end
        end
        _G.AffixLensToggle:HookScript("OnShow", syncCharacterButton)
        _G.AffixLensToggle:HookScript("OnHide", syncCharacterButton)
        syncCharacterButton()
    end
    if frame and frame:IsShown() and (dirty or GetTime()-lastStamp>10) then render() end
end)
