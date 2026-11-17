-- AffixLens V2 UI: single standalone window, two tabs, no PaperDoll hooks.
local A=AffixLens
local frame, scroll, search, filterButton, status
local tabs={}
local rows={}
local filtered={}
local currentTab="Collection"
local filterCategory=0
local searchText=""
local ROW_H=25
local MAX_ROWS=29
local collectionTitles={"Affix", "Category", "Highest learned"}

local function label(parent,size,color)
    local t=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    t:SetFont(STANDARD_TEXT_FONT,size or 12,"")
    t:SetJustifyH("LEFT")
    if color then t:SetTextColor(color[1],color[2],color[3]) end
    return t
end
local function backdrop(f,bg,edge)
    f:SetBackdrop({bgFile=bg or "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile=edge or "Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,
        edgeSize=16,insets={left=5,right=5,top=5,bottom=5}})
    f:SetBackdropColor(0.045,0.045,0.075,0.98)
    f:SetBackdropBorderColor(0.53,0.35,0.72,1)
end
local function getTab() return currentTab end
local function clampWindow()
    if not frame then return end
    local cfg=A.GetSettings()
    local w=math.max(650,math.min(1080,tonumber(cfg.windowWidth) or 790))
    local h=math.max(420,math.min(850,tonumber(cfg.windowHeight) or 620))
    frame:SetWidth(w);frame:SetHeight(h)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER",UIParent,"CENTER",tonumber(cfg.windowX) or 0,tonumber(cfg.windowY) or 0)
end
local function saveLocation()
    if not frame then return end
    local x,y=frame:GetCenter()
    local cx,cy=UIParent:GetCenter()
    if x and y and cx and cy then
        local cfg=A.GetSettings()
        cfg.windowX=math.floor(x-cx+0.5)
        cfg.windowY=math.floor(y-cy+0.5)
    end
end
local function drawTab()
    for key,btn in pairs(tabs) do
        if key==currentTab then
            btn:Disable()
            btn:SetText("|cffffd36e"..key.."|r")
        else
            btn:Enable();btn:SetText(key)
        end
    end
end
local function categoriesText()
    return filterCategory==0 and "All categories" or A.CategoryName(filterCategory)
end
local function selectedFamilies()
    filtered={}
    if currentTab=="Equipped" then
        for _,slot in ipairs(A.slots) do
            filtered[#filtered+1]=A.ItemFromInventory(slot)
        end
    else
        local query=A.Normal(searchText)
        for _,fam in ipairs(A.families) do
            if (filterCategory==0 or fam.category==filterCategory) then
                local hay=A.Normal(fam.name.." "..A.CategoryName(fam.category).." "..(fam.spec or ""))
                local match=(query=="" or hay:find(query,1,true)~=nil)
                if not match and query~="" then
                    for _,rank in ipairs(fam.ranks or {}) do
                        if rank and rank.text and A.Normal(A.Effect(rank.text)):find(query,1,true) then match=true;break end
                    end
                end
                if match then filtered[#filtered+1]=fam end
            end
        end
    end
end
local function hoverEquipment(row,item)
    if not item or not item.link then return end
    GameTooltip:SetOwner(row,"ANCHOR_RIGHT")
    GameTooltip:SetInventoryItem("player",item.slot.id)
    GameTooltip:Show()
end
local function hoverAffix(row)
    local data=row.data
    if not data then return end
    if currentTab=="Collection" then
        local rank=(data.highest and data.highest>0) and data.highest or 5
        local extra=(A.synced and data.highest==0) and "Previewing Rank V" or nil
        A.AffixTooltip(row,data,rank,extra)
    elseif data.family then
        local note=not data.valid and "Warning: affix category conflicts with this slot" or nil
        A.AffixTooltip(row,data.family,data.rank,note)
    elseif data.status=="none" then
        GameTooltip:SetOwner(row,"ANCHOR_RIGHT")
        GameTooltip:SetText("No detected affix",1,0.72,0.3)
        GameTooltip:AddLine("Requires V2 enchant ID or the item's engraved tooltip suffix.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end
end
local function newRow(index)
    local r=CreateFrame("Button",nil,frame)
    r:SetHeight(ROW_H-1)
    r:SetPoint("TOPLEFT",scroll,"TOPLEFT",6,-(index-1)*ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
    r.icon=r:CreateTexture(nil,"ARTWORK")
    r.icon:SetWidth(19);r.icon:SetHeight(19)
    r.icon:SetPoint("LEFT",r,"LEFT",4,0)
    r.first=label(r,12);r.first:SetPoint("LEFT",r,"LEFT",32,0)
    r.second=label(r,11,{0.76,0.80,0.90})
    r.third=label(r,12,{0.76,0.5,1})
    r.itemHit=CreateFrame("Button",nil,r)
    r.itemHit:SetHeight(ROW_H);r.itemHit:EnableMouse(true)
    r.itemHit:SetScript("OnEnter",function(self) hoverEquipment(r,r.data) end)
    r.itemHit:SetScript("OnLeave",function() GameTooltip:Hide() end)
    r.affixHit=CreateFrame("Button",nil,r)
    r.affixHit:SetHeight(ROW_H);r.affixHit:EnableMouse(true)
    r.affixHit:SetScript("OnEnter",function(self) hoverAffix(r) end)
    r.affixHit:SetScript("OnLeave",function() GameTooltip:Hide() end)
    r:SetScript("OnEnter",function() hoverAffix(r) end)
    r:SetScript("OnLeave",function() GameTooltip:Hide() end)
    rows[#rows+1]=r
    return r
end
local function layout()
    if not frame then return end
    local w,h=frame:GetWidth(),frame:GetHeight()
    local viewW=w-62
    local viewH=h-206
    if status then status:SetWidth(w-165) end
    scroll:SetWidth(viewW)
    scroll:SetHeight(viewH)
    local visible=math.max(1,math.min(MAX_ROWS,math.floor(viewH/ROW_H)))
    frame.visibleRows=visible
    for i,r in ipairs(rows) do
        r:SetWidth(viewW-12)
        local firstWidth,secondX,thirdX
        if currentTab=="Equipped" then
            firstWidth=99
            secondX=140
            thirdX=math.max(440,viewW-245)
        else
            firstWidth=math.max(240,math.floor(viewW*0.45))
            secondX=firstWidth+37
            thirdX=math.max(secondX+125,viewW-160)
        end
        r.first:SetWidth(firstWidth)
        r.second:ClearAllPoints()
        r.second:SetPoint("LEFT",r,"LEFT",secondX,0)
        r.second:SetWidth(math.max(85,thirdX-secondX-8))
        r.third:ClearAllPoints()
        r.third:SetPoint("LEFT",r,"LEFT",thirdX,0)
        r.third:SetWidth(math.max(70,viewW-thirdX-9))
        r.itemHit:ClearAllPoints()
        r.itemHit:SetPoint("TOPLEFT",r,"TOPLEFT",secondX,0)
        r.itemHit:SetWidth(math.max(50,thirdX-secondX-8))
        r.affixHit:ClearAllPoints()
        r.affixHit:SetPoint("TOPLEFT",r,"TOPLEFT",thirdX,0)
        r.affixHit:SetWidth(math.max(70,viewW-thirdX-8))
        if i>visible then r:Hide() end
        if i==1 and frame.head2 then
            frame.head2:ClearAllPoints()
            frame.head2:SetPoint("TOPLEFT",frame,"TOPLEFT",20+secondX,-141)
            frame.head3:ClearAllPoints()
            frame.head3:SetPoint("TOPLEFT",frame,"TOPLEFT",20+thirdX,-141)
        end
    end
end
function A.Render()
    if not frame or not frame:IsShown() then return end
    drawTab()
    selectedFamilies()
    layout()
    if search then if currentTab=="Collection" then search:Show() else search:Hide() end end
    if filterButton then if currentTab=="Collection" then filterButton:Show() else filterButton:Hide() end; filterButton:SetText(categoriesText()) end
    if frame.searchCaption then if currentTab=="Collection" then frame.searchCaption:Show() else frame.searchCaption:Hide() end end
    if frame.head1 then
        frame.head1:SetText(currentTab=="Collection" and "AFFIX FAMILY" or "EQUIPMENT SLOT")
        frame.head2:SetText(currentTab=="Collection" and "CATEGORY" or "ITEM")
        frame.head3:SetText(currentTab=="Collection" and "LEARNED" or "AFFIX")
    end
    local visible=frame.visibleRows or 12
    local total=#filtered
    local offset=math.min(FauxScrollFrame_GetOffset(scroll),math.max(0,total-visible))
    FauxScrollFrame_SetOffset(scroll,offset)
    FauxScrollFrame_Update(scroll,total,visible,ROW_H)
    local learnedCount=0
    if currentTab=="Collection" and A.synced then
        for _,f in ipairs(A.families) do if f.highest>0 then learnedCount=learnedCount+1 end end
    end
    for i,r in ipairs(rows) do
        local data=(i<=visible) and filtered[i+offset] or nil
        r.data=data
        if not data then r:Hide() else
            r:Show()
            if currentTab=="Collection" then
                r.icon:Show()
                r.icon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                r.first:SetText(data.name)
                r.second:SetText(A.CategoryName(data.category))
                r.second:SetTextColor(0.70,0.75,0.85)
                if not A.synced then
                    r.third:SetText("Syncing...")
                    r.third:SetTextColor(1,0.72,0.27)
                elseif data.highest>0 then
                    r.third:SetText("Learned "..A.RankName(data.highest))
                    r.third:SetTextColor(0.30,0.95,0.55)
                else
                    r.third:SetText("Not learned")
                    r.third:SetTextColor(0.6,0.6,0.6)
                end
                r.itemHit:Hide();r.affixHit:Hide()
            else
                r.icon:Hide()
                r.first:SetText(data.slot.name)
                r.second:SetText(data.name or "-")
                r.second:SetTextColor(0.86,0.84,0.78)
                if data.status=="affix" then
                    r.third:SetText(data.affix)
                    if data.valid then r.third:SetTextColor(0.8,0.55,1)
                    else r.third:SetTextColor(1,0.45,0.35) end
                elseif data.status=="excluded" then
                    r.third:SetText("Not affixable");r.third:SetTextColor(0.51,0.51,0.56)
                elseif data.status=="loading" then
                    r.third:SetText("Loading...");r.third:SetTextColor(1,0.78,0.3)
                else
                    r.third:SetText("N/A");r.third:SetTextColor(0.56,0.57,0.60)
                end
                if data.link then r.itemHit:Show() else r.itemHit:Hide() end
                if data.family or data.status=="none" then r.affixHit:Show() else r.affixHit:Hide() end
            end
        end
    end
    if status then
        if currentTab=="Collection" then
            local own=A.synced and (learnedCount.." learned") or "learned status syncing"
            status:SetText(total.." shown / "..#A.families.." families  |  "..own.."  |  "..A.catalogSource)
        else
            local affixed,usable=0,0
            local duplicates={}
            for _,v in ipairs(filtered) do
                if not v.slot.excluded then usable=usable+1 end
                if v.family then
                    affixed=affixed+1
                    local k=v.family.id
                    duplicates[k]=(duplicates[k] or 0)+1
                end
            end
            local dup=0
            for _,n in pairs(duplicates) do if n>1 then dup=dup+1 end end
            status:SetText(affixed.."/"..usable.." affixed  |  "..dup.." repeated families (effects do not stack)")
        end
    end
end
function A.FlagRefresh()
    if frame and frame:IsShown() then A.Render() end
end
function A.OpenTab(tab)
    if not frame then A.CreateUI() end
    if tab~="Collection" and tab~="Equipped" then tab="Collection" end
    currentTab=tab
    A.GetSettings().activeTab=tab
    if not frame:IsShown() then frame:Show() end
    FauxScrollFrame_SetOffset(scroll,0)
    A.RequestSync()
    A.BuildCatalog()
    A.Render()
end
function A.Toggle()
    if not frame then A.CreateUI() end
    if frame:IsShown() then frame:Hide() else
        A.RequestSync();A.BuildCatalog();frame:Show();A.Render()
    end
end
function A.CreateUI()
    if frame then return end
    frame=CreateFrame("Frame","AffixLensV3Window",UIParent)
    A.window=frame
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true);frame:SetResizable(true)
    frame:SetMinResize(650,420);frame:SetMaxResize(1080,850)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    backdrop(frame)
    clampWindow()
    local title=label(frame,20,{1,0.81,0.24})
    title:SetPoint("TOPLEFT",frame,"TOPLEFT",22,-20)
    title:SetText("AffixLens |cffab85ffV2|r")
    local version=label(frame,10,{0.70,0.7,0.78})
    version:SetPoint("LEFT",title,"RIGHT",8,-2)
    version:SetText("v"..A.version)
    local drag=CreateFrame("Frame",nil,frame)
    drag:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-9)
    drag:SetWidth(360);drag:SetHeight(39)
    drag:EnableMouse(true);drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function() frame:StartMoving() end)
    drag:SetScript("OnDragStop",function() frame:StopMovingOrSizing();saveLocation() end)
    local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-6,-6)
    local ctab=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    ctab:SetWidth(122);ctab:SetHeight(25)
    ctab:SetPoint("TOPLEFT",frame,"TOPLEFT",20,-61)
    ctab:SetScript("OnClick",function() A.OpenTab("Collection") end)
    tabs.Collection=ctab
    local etab=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    etab:SetWidth(122);etab:SetHeight(25)
    etab:SetPoint("LEFT",ctab,"RIGHT",6,0)
    etab:SetScript("OnClick",function() A.OpenTab("Equipped") end)
    tabs.Equipped=etab
    local searchFrame=CreateFrame("Frame",nil,frame)
    searchFrame:SetPoint("TOPLEFT",frame,"TOPLEFT",23,-103)
    searchFrame:SetWidth(260);searchFrame:SetHeight(25)
    searchFrame:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=11,insets={left=3,right=3,top=3,bottom=3}})
    searchFrame:SetBackdropColor(0.06,0.06,0.09,1)
    searchFrame:SetBackdropBorderColor(0.45,0.4,0.55,1)
    search=CreateFrame("EditBox",nil,frame)
    search:SetAutoFocus(false);search:SetHeight(20);search:SetWidth(243)
    search:SetPoint("LEFT",searchFrame,"LEFT",10,0)
    search:SetFont(STANDARD_TEXT_FONT,13,"")
    search:SetTextColor(1,1,1)
    search:SetMaxLetters(90)
    search:SetScript("OnTextChanged",function(self)
        searchText=self:GetText() or ""
        if scroll then FauxScrollFrame_SetOffset(scroll,0) end
        A.Render()
    end)
    search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
    -- Bind visibility to the entire search field including its border.
    frame.searchCaption=searchFrame
    filterButton=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    filterButton:SetWidth(168);filterButton:SetHeight(25)
    filterButton:SetPoint("LEFT",searchFrame,"RIGHT",16,0)
    filterButton:SetScript("OnClick",function()
        filterCategory=(filterCategory+1)%6
        FauxScrollFrame_SetOffset(scroll,0)
        A.Render()
    end)
    filterButton:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:SetText("Filter affixes",1,0.8,0.2)
        GameTooltip:AddLine("Click to cycle: All, Offensive, Defensive, Resource, Utility, Mobility",1,1,1,true)
        GameTooltip:Show()
    end)
    filterButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
    frame.head1=label(frame,10,{0.95,0.73,0.28})
    frame.head2=label(frame,10,{0.95,0.73,0.28})
    frame.head3=label(frame,10,{0.95,0.73,0.28})
    frame.head1:SetPoint("TOPLEFT",frame,"TOPLEFT",55,-141)
    frame.head2:SetPoint("TOPLEFT",frame,"TOPLEFT",400,-141)
    frame.head3:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-72,-141)
    scroll=CreateFrame("ScrollFrame","AffixLensV3Scroll",frame,"FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",frame,"TOPLEFT",20,-165)
    scroll:SetScript("OnVerticalScroll",function(self,delta)
        FauxScrollFrame_OnVerticalScroll(self,delta,ROW_H,A.Render)
    end)
    for i=1,MAX_ROWS do newRow(i) end
    local footer=CreateFrame("Frame",nil,frame)
    footer:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",14,10)
    footer:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-15,10)
    footer:SetHeight(30)
    status=label(footer,11,{0.74,0.76,0.83})
    status:SetPoint("LEFT",footer,"LEFT",10,0)
    status:SetWidth(550)
    local refresh=CreateFrame("Button",nil,footer,"UIPanelButtonTemplate")
    refresh:SetWidth(82);refresh:SetHeight(22)
    refresh:SetPoint("RIGHT",footer,"RIGHT",-22,0)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick",function() A.RequestSync();A.BuildCatalog();A.Render() end)
    local grip=CreateFrame("Button",nil,frame)
    grip:SetWidth(17);grip:SetHeight(17)
    grip:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-7,7)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart",function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnDragStop",function()
        frame:StopMovingOrSizing()
        local cfg=A.GetSettings()
        cfg.windowWidth=math.floor(frame:GetWidth()+0.5)
        cfg.windowHeight=math.floor(frame:GetHeight()+0.5)
        saveLocation();A.Render()
    end)
    frame:SetScript("OnSizeChanged",function() if scroll then A.Render() end end)
    currentTab=A.GetSettings().activeTab or "Collection"
    frame:SetScript("OnShow",function() A.BuildCatalog();A.Render() end)
    frame:Hide()
    layout()
end

local minimap
function A.PlaceMinimap()
    if not minimap then return end
    local angle=tonumber(A.GetSettings().minimapAngle) or 2.4
    minimap:ClearAllPoints()
    minimap:SetPoint("CENTER",Minimap,"CENTER",math.cos(angle)*80,math.sin(angle)*80)
end
function A.CreateMinimap()
    if minimap or not Minimap then return end
    minimap=CreateFrame("Button","AffixLensV3MinimapButton",Minimap)
    minimap:SetFrameStrata("MEDIUM")
    minimap:SetFrameLevel(Minimap:GetFrameLevel()+7)
    minimap:SetWidth(32);minimap:SetHeight(32)
    minimap:SetMovable(true);minimap:EnableMouse(true)
    minimap:RegisterForClicks("LeftButtonUp")
    minimap:RegisterForDrag("LeftButton")
    local bg=minimap:CreateTexture(nil,"BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    bg:SetWidth(54);bg:SetHeight(54)
    bg:SetPoint("CENTER",minimap,"CENTER",0,0)
    local icon=minimap:CreateTexture(nil,"ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Enchant_DustArcane")
    icon:SetWidth(20);icon:SetHeight(20)
    icon:SetPoint("CENTER",minimap,"CENTER",0,0)
    local highlight=minimap:CreateTexture(nil,"HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetAllPoints(minimap)
    local function reposition()
        local x,y=GetCursorPosition()
        local scale=Minimap:GetEffectiveScale() or 1
        x=x/scale;y=y/scale
        local cx,cy=Minimap:GetCenter()
        if not cx or not cy then return end
        local dx,dy=x-cx,y-cy
        -- Lua 5.1 math.atan2 is not guaranteed on every WotLK client.
        local atan2=math.atan2 or function(yy,xx)
            if xx>0 then return math.atan(yy/xx) end
            if xx<0 then return math.atan(yy/xx)+(yy>=0 and math.pi or -math.pi) end
            return yy>=0 and math.pi/2 or -math.pi/2
        end
        A.GetSettings().minimapAngle=atan2(dy,dx)
        A.PlaceMinimap()
    end
    minimap:SetScript("OnDragStart",function(self)
        self.dragging=true
        self:SetScript("OnUpdate",reposition)
    end)
    minimap:SetScript("OnDragStop",function(self)
        self:SetScript("OnUpdate",nil)
        self.dragging=false
        reposition()
    end)
    minimap:SetScript("OnClick",function(self)
        if self.dragging then return end
        A.Toggle()
    end)
    minimap:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_LEFT")
        GameTooltip:AddLine("AffixLens V2",0.85,0.62,1)
        GameTooltip:AddLine("Left-click: open / close",1,1,1)
        GameTooltip:AddLine("Drag: move around minimap",0.75,0.75,0.75)
        GameTooltip:Show()
    end)
    minimap:SetScript("OnLeave",function() GameTooltip:Hide() end)
    A.PlaceMinimap()
end
