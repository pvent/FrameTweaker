local addonName, ns = ...

-------------------------------------------------------------------------------
-- 1. SAVEDVARIABLES & PERSISTENCE HOOKS (WITH BLIZZMOVE-STYLE GUARD)
-------------------------------------------------------------------------------
FrameTweakerDB = FrameTweakerDB or {}
local defaultFramePositions = {}

local frameList = {
    ["Blizzard_TalentUI"] = {
        ["PlayerTalentFrame"] = true,
    }
}

local function CacheDefaultPosition(frameName)
    local obj = _G[frameName]
    if obj and type(obj) == "table" and obj.GetPoint and not defaultFramePositions[frameName] then
        local point, relTo, relPoint, x, y = obj:GetPoint(1)
        if point then
            defaultFramePositions[frameName] = {
                point = point,
                relativeTo = relTo and relTo:GetName() or "UIParent",
                relativePoint = relPoint,
                x = x or 0,
                y = y or 0,
                scale = obj:GetScale() or 1.0
            }
        end
    end
end

local function ApplyFramePosition(frameName)
    if not FrameTweakerDB or not FrameTweakerDB[frameName] then return end
    local settings = FrameTweakerDB[frameName]
    local obj = _G[frameName]

    if obj and type(obj) == "table" and obj.SetPoint then
        if obj.__ft_moving or obj.isDragging or obj.isTweakingPosition then return end
        obj.__ft_moving = true

        CacheDefaultPosition(frameName)

        if obj.SetUserPlaced then
            obj:SetUserPlaced(true)
        end

        obj:ClearAllPoints()
        local relTo = _G[settings.relativeTo] or UIParent
        obj:SetPoint(settings.point or "CENTER", relTo, settings.relativePoint or "CENTER", settings.x or 0, settings.y or 0)
        if settings.scale then
            obj:SetScale(settings.scale)
        end

        obj.__ft_moving = false
    end
end

local function HookFramePersistence(frameName)
    local obj = _G[frameName]
    if not obj or type(obj) ~= "table" or obj.__ft_hooked then return end

    CacheDefaultPosition(frameName)

    -- Guarded SetPoint hook to defeat Blizzard's automated layout resets (UIParent_ManageFramePositions)
    if obj.SetPoint then
        hooksecurefunc(obj, "SetPoint", function(self, ...)
            if self.__ft_moving or self.isDragging or self.isTweakingPosition then return end
            if FrameTweakerDB and FrameTweakerDB[frameName] then
                self.__ft_moving = true
                self:ClearAllPoints()
                local settings = FrameTweakerDB[frameName]
                local relTo = _G[settings.relativeTo] or UIParent
                self:SetPoint(settings.point or "CENTER", relTo, settings.relativePoint or "CENTER", settings.x or 0, settings.y or 0)
                if settings.scale then
                    self:SetScale(settings.scale)
                end
                self.__ft_moving = false
            end
        end)
    end

    if obj.Show then
        hooksecurefunc(obj, "Show", function()
            if obj.__ft_moving or obj.isDragging then return end
            ApplyFramePosition(frameName)
        end)
    end

    obj.__ft_hooked = true
end

local function ApplyAllSavedPositions()
    if not FrameTweakerDB then return end
    for frameName in pairs(FrameTweakerDB) do
        local obj = _G[frameName]
        if obj then
            HookFramePersistence(frameName)
            ApplyFramePosition(frameName)
        end
    end
end

local dbFrame = CreateFrame("Frame")
dbFrame:RegisterEvent("ADDON_LOADED")
dbFrame:RegisterEvent("PLAYER_LOGIN")

dbFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if frameList[loadedAddon] then
            for frameName in pairs(frameList[loadedAddon]) do
                HookFramePersistence(frameName)
                ApplyFramePosition(frameName)
            end
        end
    elseif event == "PLAYER_LOGIN" then
        ApplyAllSavedPositions()
    end
end)

if ShowUIPanel then
    hooksecurefunc("ShowUIPanel", function(frame)
        if frame and frame.GetName then
            local name = frame:GetName()
            if name and FrameTweakerDB and FrameTweakerDB[name] then
                HookFramePersistence(name)
                ApplyFramePosition(name)
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- 2. STYLES & BACKDROP HELPERS
-------------------------------------------------------------------------------
local function SetDarkBackdrop(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.90)
    
    local border = f:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.2, 0.2, 0.2, 1)
    border:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
end

-------------------------------------------------------------------------------
-- 3. PRIORITY ESC-STACK CONTROLLER
-------------------------------------------------------------------------------
local windowStack = {}

local function RemoveFromWindowStack(frame)
    for i = #windowStack, 1, -1 do
        if windowStack[i] == frame then
            table.remove(windowStack, i)
            break
        end
    end
end

local function PushToWindowStack(frame)
    RemoveFromWindowStack(frame)
    table.insert(windowStack, frame)
end

hooksecurefunc("ToggleGameMenu", function()
    if #windowStack > 0 then
        local topFrame = windowStack[#windowStack]
        if topFrame and topFrame:IsShown() then
            topFrame:Hide()
            if GameMenuFrame and GameMenuFrame:IsShown() then
                HideUIPanel(GameMenuFrame)
            end
        end
    end
end)

local function RegisterManagedWindow(frame)
    frame:HookScript("OnShow", function(self)
        PushToWindowStack(self)
    end)
    frame:HookScript("OnHide", function(self)
        RemoveFromWindowStack(self)
    end)
end

-------------------------------------------------------------------------------
-- 4. HIGHLIGHT & DRAGGER OVERLAY
-------------------------------------------------------------------------------
local draggerFrame = CreateFrame("Frame", "FrameTweakerDragger", UIParent)
draggerFrame:SetFrameStrata("DIALOG")
draggerFrame:EnableMouse(true)
draggerFrame:SetMovable(true)
draggerFrame:RegisterForDrag("LeftButton")
draggerFrame:Hide()

local hlTex = draggerFrame:CreateTexture(nil, "BACKGROUND")
hlTex:SetAllPoints()
hlTex:SetColorTexture(1, 0, 0, 0.35)

local dragLabel = draggerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dragLabel:SetPoint("CENTER", draggerFrame, "CENTER", 0, 0)
dragLabel:SetText("[Drag Me]")

local hoverFrame = CreateFrame("Frame", "FrameTweakerHoverHighlight", UIParent)
hoverFrame:SetFrameStrata("TOOLTIP")
hoverFrame:Hide()

local hoverTex = hoverFrame:CreateTexture(nil, "BACKGROUND")
hoverTex:SetAllPoints()
hoverTex:SetColorTexture(0, 0.8, 1, 0.25)

local targetFrame = nil
local SyncUIControls
local SaveTargetFrameState
local OpenEditorForFrame
local OpenHierarchyInspector
local RenderCategoryTree
local browserFrame

local function DetachDragger()
    draggerFrame:Hide()
    draggerFrame:ClearAllPoints()
    draggerFrame:SetParent(UIParent)
    draggerFrame:SetFrameStrata("DIALOG")
    targetFrame = nil
end

local function AttachDragger(frame)
    if not frame or not frame:IsShown() then
        DetachDragger()
        return
    end

    targetFrame = frame
    frame:SetMovable(true)

    draggerFrame:Hide()
    draggerFrame:ClearAllPoints()
    draggerFrame:SetParent(frame)
    draggerFrame:SetAllPoints(frame)
    
    local frameStrata = frame:GetFrameStrata()
    if frameStrata then
        draggerFrame:SetFrameStrata(frameStrata)
    end
    draggerFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    draggerFrame:Show()
end

local function HighlightHoverFrame(frame)
    if not frame or not frame:IsShown() or frame == targetFrame then
        hoverFrame:Hide()
        return
    end
    hoverFrame:ClearAllPoints()
    hoverFrame:SetParent(frame)
    hoverFrame:SetAllPoints(frame)
    hoverFrame:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    hoverFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    hoverFrame:Show()
end

draggerFrame:SetScript("OnDragStart", function(self)
    if not targetFrame then return end
    targetFrame.isDragging = true
    targetFrame:StartMoving()
    self:SetScript("OnUpdate", function()
        if SyncUIControls then SyncUIControls(true) end
    end)
end)

draggerFrame:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    if targetFrame then
        targetFrame:StopMovingOrSizing()
        targetFrame.isDragging = nil
        if SyncUIControls then SyncUIControls(true) end
        if SaveTargetFrameState then SaveTargetFrameState() end
    end
end)

-------------------------------------------------------------------------------
-- 5. DIRECT RECT HIGHLIGHT INSPECTOR
-------------------------------------------------------------------------------
local isInspecting = false
local hoveredFrames = {}
local stackIndex = 1
local currentInspectedFrame = nil

local inspectOverlay = CreateFrame("Frame", "FrameTweakerInspectOverlay", UIParent)
inspectOverlay:SetFrameStrata("TOOLTIP")
inspectOverlay:Hide()

local inspectTex = inspectOverlay:CreateTexture(nil, "OVERLAY")
inspectTex:SetAllPoints()
inspectTex:SetColorTexture(0, 0.8, 1, 0.4)

local inspectTicker = CreateFrame("Frame", "FrameTweakerInspectTicker", UIParent)
inspectTicker:Hide()

local function IsFrameValid(f)
    if not f or type(f) ~= "table" then return false end
    if f.IsForbidden and f:IsForbidden() then return false end
    if f == UIParent or f == WorldFrame or f == inspectOverlay or f == draggerFrame or f == hoverFrame then return false end
    return true
end

local function IsMainContainer(f)
    if not IsFrameValid(f) then return false end
    local parent
    pcall(function() parent = f:GetParent() end)
    
    if not parent or parent == UIParent then
        return true
    end

    local name
    pcall(function() name = f:GetName() end)
    if name then
        if name:find("Frame$") or name:find("Window$") or name:find("Panel$") then
            return true
        end
    end

    return false
end

local function IsMouseOverFrame(f)
    if not IsFrameValid(f) then return false end
    local isVisible = false
    local isMouseOver = false
    
    pcall(function()
        isVisible = f:IsVisible()
        if isVisible and f.IsMouseOver then
            isMouseOver = f:IsMouseOver()
        end
    end)
    
    return isVisible and isMouseOver
end

local function GetFramesUnderCursor()
    local matches = {}
    local visited = {}

    local function CheckFrame(f)
        if not IsFrameValid(f) or visited[f] then return end
        visited[f] = true

        if IsMouseOverFrame(f) then
            local w, h = 0, 0
            pcall(function() w, h = f:GetSize() end)
            local area = (w > 0 and h > 0) and (w * h) or 999999
            local name = nil
            pcall(function() name = f:GetName() end)

            table.insert(matches, { frame = f, name = name or "<Unnamed>", area = area })
        end

        local parent = nil
        pcall(function() parent = f:GetParent() end)
        if parent then
            CheckFrame(parent)
        end
    end

    local foci = {}
    if GetMouseFoci then
        foci = GetMouseFoci() or {}
    elseif GetMouseFocus then
        local focus = GetMouseFocus()
        if focus then foci = { focus } end
    end

    for _, f in ipairs(foci) do
        CheckFrame(f)
    end

    if #matches == 0 then
        local currentFrame = EnumerateFrames()
        while currentFrame do
            if IsMouseOverFrame(currentFrame) then
                CheckFrame(currentFrame)
            end
            currentFrame = EnumerateFrames(currentFrame)
        end
    end

    table.sort(matches, function(a, b)
        return a.area < b.area
    end)

    return matches
end

local function StopInspecting()
    isInspecting = false
    inspectTicker:Hide()
    inspectOverlay:Hide()
    GameTooltip:Hide()
    SetCursor(nil)
    currentInspectedFrame = nil
    hoveredFrames = {}
    stackIndex = 1
end

local function StartInspecting()
    isInspecting = true
    stackIndex = 1
    SetCursor("CAST_CURSOR")
    inspectTicker:Show()
end

inspectTicker:SetScript("OnUpdate", function(self, elapsed)
    if not isInspecting then return end

    if IsKeyDown("ESCAPE") then
        StopInspecting()
        return
    end

    if IsMouseButtonDown("LeftButton") then
        local sel = currentInspectedFrame
        StopInspecting()
        if sel and IsFrameValid(sel) then
            OpenEditorForFrame(sel)
        end
        return
    elseif IsMouseButtonDown("RightButton") then
        StopInspecting()
        return
    end

    local matches = GetFramesUnderCursor()
    
    local same = (#matches == #hoveredFrames)
    if same then
        for i = 1, #matches do
            if matches[i].frame ~= hoveredFrames[i] then
                same = false; break
            end
        end
    end

    if not same then
        hoveredFrames = {}
        for i, item in ipairs(matches) do
            hoveredFrames[i] = item.frame
        end
        stackIndex = 1
    end

    if #hoveredFrames > 0 then
        if stackIndex > #hoveredFrames then stackIndex = 1 end
        local target = hoveredFrames[stackIndex]
        currentInspectedFrame = target

        inspectOverlay:ClearAllPoints()
        inspectOverlay:SetParent(UIParent)
        inspectOverlay:SetFrameStrata("TOOLTIP")
        inspectOverlay:SetAllPoints(target)
        inspectOverlay:Show()

        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()

        local fName, pName
        pcall(function() fName = target:GetName() end)
        pcall(function() pName = target:GetParent() and target:GetParent():GetName() end)

        local isContainer = IsMainContainer(target)
        local containerTag = isContainer and " |cffffd100[MAIN CONTAINER]|r" or ""

        GameTooltip:AddLine("FrameTweaker Inspector", 0, 0.8, 1)
        GameTooltip:AddLine("Target (" .. stackIndex .. "/" .. #hoveredFrames .. "): |cffffffff" .. (fName or "<Unnamed>") .. "|r" .. containerTag, 1, 0.82, 0)
        GameTooltip:AddLine("Parent: |cffaaaaaa" .. (pName or "<Unnamed/Root>") .. "|r", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cff00ff00Left-Click:|r Inspect Frame Hierarchy | |cffff0000Right-Click/ESC:|r Cancel", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    else
        currentInspectedFrame = nil
        inspectOverlay:Hide()
        GameTooltip:Hide()
    end
end)

-------------------------------------------------------------------------------
-- 6. MAIN BROWSER & DOCKED SUB-WINDOWS
-------------------------------------------------------------------------------
browserFrame = CreateFrame("Frame", "FrameTweakerBrowser", UIParent)
browserFrame:SetSize(370, 470)
browserFrame:SetPoint("CENTER", -200, 0)
browserFrame:SetMovable(true)
browserFrame:EnableMouse(true)
browserFrame:RegisterForDrag("LeftButton")
browserFrame:SetClampedToScreen(true)
browserFrame:Hide()
SetDarkBackdrop(browserFrame)

RegisterManagedWindow(browserFrame)

browserFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
browserFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

-------------------------------------------------------------------------------
-- 7. ELEMENT HIERARCHY TREE WINDOW (TOP RIGHT DOCK)
-------------------------------------------------------------------------------
local hierarchyFrame = CreateFrame("Frame", "FrameTweakerHierarchy", browserFrame)
hierarchyFrame:SetSize(310, 225)
hierarchyFrame:SetPoint("TOPLEFT", browserFrame, "TOPRIGHT", 5, 0)
hierarchyFrame:EnableMouse(true)
hierarchyFrame:Hide()
SetDarkBackdrop(hierarchyFrame)

hierarchyFrame:SetScript("OnHide", function()
    hoverFrame:Hide()
end)

local hTitle = hierarchyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
hTitle:SetPoint("TOPLEFT", hierarchyFrame, "TOPLEFT", 12, -10)
hTitle:SetText("Frame Hierarchy Inspector")

local hClose = CreateFrame("Button", nil, hierarchyFrame, "UIPanelCloseButton")
hClose:SetPoint("TOPRIGHT", hierarchyFrame, "TOPRIGHT", -2, -2)
hClose:SetScript("OnClick", function() 
    hierarchyFrame:Hide()
end)

local hScrollFrame = CreateFrame("ScrollFrame", "FT_HScrollFrame", hierarchyFrame, "UIPanelScrollFrameTemplate")
hScrollFrame:SetPoint("TOPLEFT", hierarchyFrame, "TOPLEFT", 10, -32)
hScrollFrame:SetPoint("BOTTOMRIGHT", hierarchyFrame, "BOTTOMRIGHT", -30, 8)

local hScrollContent = CreateFrame("Frame", "FT_HScrollContent", hScrollFrame)
hScrollContent:SetSize(250, 100)
hScrollFrame:SetScrollChild(hScrollContent)

local poolHierarchyButtons = {}

-------------------------------------------------------------------------------
-- 8. PROPERTIES EDITOR WINDOW (BOTTOM RIGHT DOCK)
-------------------------------------------------------------------------------
local editorFrame = CreateFrame("Frame", "FrameTweakerEditor", browserFrame)
editorFrame:SetSize(310, 240)
editorFrame:SetPoint("TOPLEFT", hierarchyFrame, "BOTTOMLEFT", 0, -5)
editorFrame:EnableMouse(true)
editorFrame:Hide()
SetDarkBackdrop(editorFrame)

editorFrame:SetScript("OnHide", function()
    DetachDragger()
end)

browserFrame:HookScript("OnHide", function()
    editorFrame:Hide()
    hierarchyFrame:Hide()
    DetachDragger()
    hoverFrame:Hide()
    StopInspecting()
end)

local editorTitle = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
editorTitle:SetPoint("TOP", editorFrame, "TOP", 0, -10)
editorTitle:SetText("Frame Properties")

local editorClose = CreateFrame("Button", nil, editorFrame, "UIPanelCloseButton")
editorClose:SetPoint("TOPRIGHT", editorFrame, "TOPRIGHT", -2, -2)
editorClose:SetScript("OnClick", function() 
    editorFrame:Hide() 
end)

local isUpdatingUI = false

local function CreatePropertyRow(name, labelText, yOfs, minVal, maxVal, step)
    local slider = CreateFrame("Slider", name .. "Slider", editorFrame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", editorFrame, "TOPLEFT", 15, yOfs)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetWidth(180)

    local text = _G[name .. "SliderText"]
    if text then text:SetText(labelText) end

    local editBox = CreateFrame("EditBox", name .. "EditBox", editorFrame, "InputBoxTemplate")
    editBox:SetSize(60, 20)
    editBox:SetPoint("LEFT", slider, "RIGHT", 15, 0)
    editBox:SetAutoFocus(false)

    return slider, editBox
end

local sliderX, inputX = CreatePropertyRow("FTE_X", "X Offset", -35, -1000, 1000, 1)
local sliderY, inputY = CreatePropertyRow("FTE_Y", "Y Offset", -85, -1000, 1000, 1)
local sliderScale, inputScale = CreatePropertyRow("FTE_Scale", "Scale (0.2 - 3.0)", -135, 0.2, 3.0, 0.05)

SaveTargetFrameState = function()
    if not targetFrame or not IsFrameValid(targetFrame) then return end
    local frameName
    pcall(function() frameName = targetFrame:GetName() end)
    if not frameName then return end

    if targetFrame.SetUserPlaced then
        targetFrame:SetUserPlaced(true)
    end

    local point, relativeTo, relativePoint, xOfs, yOfs
    pcall(function() point, relativeTo, relativePoint, xOfs, yOfs = targetFrame:GetPoint(1) end)

    FrameTweakerDB[frameName] = {
        point = point or "CENTER",
        relativeTo = "UIParent",
        relativePoint = relativePoint or point or "CENTER",
        x = xOfs and math.floor(xOfs + 0.5) or 0,
        y = yOfs and math.floor(yOfs + 0.5) or 0,
        scale = targetFrame:GetScale() or 1.0
    }

    HookFramePersistence(frameName)
    if RenderCategoryTree then RenderCategoryTree() end
end

local function ApplyTransformsFromUI()
    if not targetFrame or isUpdatingUI or not IsFrameValid(targetFrame) then return end

    local x = tonumber(inputX:GetText()) or sliderX:GetValue()
    local y = tonumber(inputY:GetText()) or sliderY:GetValue()
    local scale = tonumber(inputScale:GetText()) or sliderScale:GetValue()

    local point, relativeTo, relativePoint = "CENTER", UIParent, "CENTER"
    pcall(function()
        local p, rTo, rPoint = targetFrame:GetPoint(1)
        if p then
            point = p
            relativePoint = rPoint or p
        end
    end)

    targetFrame.isTweakingPosition = true
    if targetFrame.SetUserPlaced then
        targetFrame:SetUserPlaced(true)
    end
    targetFrame:ClearAllPoints()
    targetFrame:SetPoint(point, UIParent, relativePoint, x, y)
    targetFrame:SetScale(scale)
    targetFrame.isTweakingPosition = nil

    SaveTargetFrameState()
    SyncUIControls(false)
end

local function ResetFrameToBase(frameName)
    if not frameName then return end

    if FrameTweakerDB then
        FrameTweakerDB[frameName] = nil
    end

    local obj = _G[frameName]
    if obj and IsFrameValid(obj) then
        obj.isTweakingPosition = true
        
        local def = defaultFramePositions[frameName]
        obj:ClearAllPoints()
        if def then
            local relTo = _G[def.relativeTo] or UIParent
            obj:SetPoint(def.point, relTo, def.relativePoint, def.x, def.y)
            obj:SetScale(def.scale or 1.0)
        else
            if obj:IsUserPlaced() then
                obj:SetUserPlaced(false)
            end
            if UpdateUIPanelPositions then
                UpdateUIPanelPositions()
            else
                obj:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
            end
            obj:SetScale(1.0)
        end

        obj.isTweakingPosition = nil
    end

    if RenderCategoryTree then RenderCategoryTree() end
    if targetFrame and targetFrame:GetName() == frameName and SyncUIControls then
        SyncUIControls(true)
    end
end

local btnResetPos = CreateFrame("Button", nil, editorFrame, "UIPanelButtonTemplate")
btnResetPos:SetSize(125, 22)
btnResetPos:SetPoint("BOTTOMLEFT", editorFrame, "BOTTOMLEFT", 15, 12)
btnResetPos:SetText("Reset All Base")
btnResetPos:SetScript("OnClick", function()
    if not targetFrame or not IsFrameValid(targetFrame) then return end
    local name
    pcall(function() name = targetFrame:GetName() end)
    if name then
        ResetFrameToBase(name)
    end
end)

local btnResetScale = CreateFrame("Button", nil, editorFrame, "UIPanelButtonTemplate")
btnResetScale:SetSize(125, 22)
btnResetScale:SetPoint("BOTTOMRIGHT", editorFrame, "BOTTOMRIGHT", -15, 12)
btnResetScale:SetText("Reset Scale")
btnResetScale:SetScript("OnClick", function()
    if not targetFrame or not IsFrameValid(targetFrame) then return end
    targetFrame:SetScale(1.0)
    sliderScale:SetValue(1.0)
    ApplyTransformsFromUI()
end)

SyncUIControls = function(fromFrameState)
    if not targetFrame or not IsFrameValid(targetFrame) then return end
    isUpdatingUI = true

    local xOfs, yOfs, currentScale
    pcall(function()
        local _, _, _, x, y = targetFrame:GetPoint(1)
        xOfs = x
        yOfs = y
        currentScale = targetFrame:GetScale()
    end)

    xOfs = xOfs and math.floor(xOfs + 0.5) or 0
    yOfs = yOfs and math.floor(yOfs + 0.5) or 0
    currentScale = currentScale or 1.0

    if fromFrameState then
        sliderX:SetValue(xOfs)
        sliderY:SetValue(yOfs)
        sliderScale:SetValue(currentScale)
    end

    inputX:SetText(tostring(xOfs))
    inputY:SetText(tostring(yOfs))
    inputScale:SetText(string.format("%.2f", currentScale))

    isUpdatingUI = false
end

sliderX:SetScript("OnValueChanged", function(self, val)
    if not isUpdatingUI then inputX:SetText(tostring(math.floor(val))); ApplyTransformsFromUI() end
end)
sliderY:SetScript("OnValueChanged", function(self, val)
    if not isUpdatingUI then inputY:SetText(tostring(math.floor(val))); ApplyTransformsFromUI() end
end)
sliderScale:SetScript("OnValueChanged", function(self, val)
    if not isUpdatingUI then inputScale:SetText(string.format("%.2f", val)); ApplyTransformsFromUI() end
end)

local function SetupEditBox(editBox, slider)
    editBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            slider:SetValue(val)
            ApplyTransformsFromUI()
        end
        self:ClearFocus()
    end)
end

SetupEditBox(inputX, sliderX)
SetupEditBox(inputY, sliderY)
SetupEditBox(inputScale, sliderScale)

OpenHierarchyInspector = function(startFrame)
    if not IsFrameValid(startFrame) then return end

    for _, btn in ipairs(poolHierarchyButtons) do btn:Hide() end

    local chain = {}
    local curr = startFrame
    while curr and IsFrameValid(curr) do
        table.insert(chain, 1, curr)
        local parent = nil
        pcall(function() parent = curr:GetParent() end)
        curr = parent
    end

    local yOffset = 0
    for idx, frameObj in ipairs(chain) do
        local btn = poolHierarchyButtons[idx] or CreateFrame("Button", nil, hScrollContent, "UIPanelButtonTemplate")
        poolHierarchyButtons[idx] = btn

        local indent = (idx - 1) * 10
        btn:SetSize(240 - indent, 20)
        btn:SetPoint("TOPLEFT", hScrollContent, "TOPLEFT", indent, yOffset)

        local name
        pcall(function() name = frameObj:GetName() end)
        name = name or "<Unnamed Frame>"

        local isContainer = IsMainContainer(frameObj)
        local tag = isContainer and " [MAIN]" or ""

        if frameObj == targetFrame then
            btn:SetText("-> " .. name .. tag)
        else
            btn:SetText(name .. tag)
        end

        btn:SetScript("OnClick", function()
            OpenEditorForFrame(frameObj)
        end)

        btn:SetScript("OnEnter", function()
            HighlightHoverFrame(frameObj)
        end)
        btn:SetScript("OnLeave", function()
            hoverFrame:Hide()
        end)

        btn:Show()
        yOffset = yOffset - 22
    end

    hScrollContent:SetHeight(math.abs(yOffset) + 20)
    hierarchyFrame:Show()
end

OpenEditorForFrame = function(frame)
    if not IsFrameValid(frame) then return end
    
    local name
    pcall(function() name = frame:GetName() end)
    editorTitle:SetText(name or "<Unnamed Frame>")

    AttachDragger(frame)
    SyncUIControls(true)
    
    OpenHierarchyInspector(frame)
    editorFrame:Show()
end

-------------------------------------------------------------------------------
-- 9. EXPANDABLE CATEGORIES & BROWSER WITH SEARCH BAR & STATUS INDICATORS
-------------------------------------------------------------------------------
local UICategories = {
    ["Quests & Objectives"] = { "QuestFrame", "QuestLogFrame", "QuestLogDetailFrame", "WatchFrame" },
    ["Professions & Crafting"] = { "TradeSkillFrame", "CraftFrame" },
    ["Achievements & Collection"] = { "AchievementFrame", "PVPFrame" },
    ["Character & Inventory"] = { "CharacterFrame", "PaperDollFrame", "SpellBookFrame", "TalentFrame", "PlayerTalentFrame", "ContainerFrame1" },
    ["Action Bars"] = { "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" },
    ["Unit Frames"] = { "PlayerFrame", "TargetFrame", "FocusFrame", "PartyMemberFrame1", "PetFrame" },
    ["Minimap & World"] = { "MinimapCluster", "Minimap", "WorldMapFrame" },
    ["Chat & Dialogs"] = { "ChatFrame1", "GossipFrame", "MerchantFrame" }
}

local categoryExpanded = {}
for cat in pairs(UICategories) do categoryExpanded[cat] = false end

local bTitle = browserFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
bTitle:SetPoint("TOPLEFT", browserFrame, "TOPLEFT", 12, -10)
bTitle:SetText("UI Category Tree")

local searchBox = CreateFrame("EditBox", "FT_SearchBox", browserFrame, "InputBoxTemplate")
searchBox:SetSize(140, 20)
searchBox:SetPoint("TOPLEFT", browserFrame, "TOPLEFT", 12, -32)
searchBox:SetAutoFocus(false)
searchBox:SetScript("OnTextChanged", function(self)
    if RenderCategoryTree then RenderCategoryTree() end
end)

local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 5, 0)
searchPlaceholder:SetText("Search frame...")
searchBox:HookScript("OnTextChanged", function(self)
    searchPlaceholder:SetShown(self:GetText() == "")
end)

local inspectBtn = CreateFrame("Button", nil, browserFrame, "UIPanelButtonTemplate")
inspectBtn:SetSize(70, 22)
inspectBtn:SetPoint("TOPRIGHT", browserFrame, "TOPRIGHT", -32, -31)
inspectBtn:SetText("Inspect")
inspectBtn:SetScript("OnClick", function()
    StartInspecting()
end)

local bClose = CreateFrame("Button", nil, browserFrame, "UIPanelCloseButton")
bClose:SetPoint("TOPRIGHT", browserFrame, "TOPRIGHT", -2, -2)
bClose:SetScript("OnClick", function() 
    browserFrame:Hide()
end)

local scrollFrame = CreateFrame("ScrollFrame", "FT_ScrollFrame", browserFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", browserFrame, "TOPLEFT", 10, -60)
scrollFrame:SetPoint("BOTTOMRIGHT", browserFrame, "BOTTOMRIGHT", -30, 10)

local scrollContent = CreateFrame("Frame", "FT_ScrollContent", scrollFrame)
scrollContent:SetSize(310, 100)
scrollFrame:SetScrollChild(scrollContent)

local poolHeaderButtons = {}
local poolChildFrames = {}

RenderCategoryTree = function()
    for _, btn in ipairs(poolHeaderButtons) do btn:Hide() end
    for _, row in ipairs(poolChildFrames) do row:Hide() end

    local yOffset = 0
    local headerIdx = 0
    local childIdx = 0
    local filterText = searchBox:GetText():lower()
    local isFiltering = (filterText ~= "")

    for category, frameListCat in pairs(UICategories) do
        local hasMatchingChild = false
        if isFiltering then
            for _, frameName in ipairs(frameListCat) do
                if frameName:lower():find(filterText, 1, true) then
                    hasMatchingChild = true
                    break
                end
            end
        end

        if not isFiltering or hasMatchingChild then
            headerIdx = headerIdx + 1
            local headerBtn = poolHeaderButtons[headerIdx] or CreateFrame("Button", nil, scrollContent, "UIPanelButtonTemplate")
            poolHeaderButtons[headerIdx] = headerBtn

            headerBtn:SetSize(310, 24)
            headerBtn:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
            
            local isExp = isFiltering or categoryExpanded[category]
            headerBtn:SetText((isExp and "[-] " or "[+] ") .. category)

            headerBtn:SetScript("OnClick", function()
                if not isFiltering then
                    categoryExpanded[category] = not categoryExpanded[category]
                    RenderCategoryTree()
                end
            end)

            headerBtn:Show()
            yOffset = yOffset - 26

            if isExp then
                for _, frameName in ipairs(frameListCat) do
                    if not isFiltering or frameName:lower():find(filterText, 1, true) then
                        local obj = _G[frameName]
                        childIdx = childIdx + 1

                        local row = poolChildFrames[childIdx]
                        if not row then
                            row = CreateFrame("Frame", nil, scrollContent)
                            row:SetSize(300, 20)

                            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                            cb:SetSize(20, 20)
                            cb:SetPoint("LEFT", row, "LEFT", 0, 0)
                            cb:Disable()
                            row.cb = cb

                            local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                            btn:SetHeight(20)
                            btn:SetPoint("LEFT", cb, "RIGHT", 2, 0)
                            row.btn = btn

                            local resetBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                            resetBtn:SetSize(55, 20)
                            resetBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                            resetBtn:SetText("Reset")
                            row.resetBtn = resetBtn

                            poolChildFrames[childIdx] = row
                        end

                        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 10, yOffset)

                        local isEdited = FrameTweakerDB and FrameTweakerDB[frameName] ~= nil
                        row.cb:SetChecked(isEdited)

                        if isEdited then
                            row.resetBtn:Show()
                            row.btn:SetWidth(180)
                            row.resetBtn:SetScript("OnClick", function()
                                ResetFrameToBase(frameName)
                            end)
                        else
                            row.resetBtn:Hide()
                            row.btn:SetWidth(240)
                        end

                        if obj and IsFrameValid(obj) and obj.IsObjectType then
                            local isShown = false
                            pcall(function() isShown = obj:IsShown() end)
                            
                            local statusPrefix = isEdited and "|cff00ff00" or ""
                            row.btn:SetText(statusPrefix .. frameName .. (isShown and "" or " (Hidden)"))
                            row.btn:SetScript("OnClick", function()
                                if not isShown then pcall(function() obj:Show() end) end
                                OpenEditorForFrame(obj)
                            end)
                            row.btn:SetScript("OnEnter", function()
                                if isShown then HighlightHoverFrame(obj) end
                            end)
                            row.btn:SetScript("OnLeave", function()
                                hoverFrame:Hide()
                            end)
                        else
                            row.btn:SetText("|cff888888" .. frameName .. " (Not Loaded)|r")
                            row.btn:SetScript("OnClick", nil)
                            row.btn:SetScript("OnEnter", nil)
                            row.btn:SetScript("OnLeave", nil)
                        end

                        row:Show()
                        yOffset = yOffset - 22
                    end
                end
                yOffset = yOffset - 4
            end
        end
    end

    scrollContent:SetHeight(math.abs(yOffset) + 20)
end

-------------------------------------------------------------------------------
-- 10. SLASH COMMANDS
-------------------------------------------------------------------------------
SLASH_FRAMETWEAKER1 = "/ft"
SLASH_FRAMETWEAKER2 = "/frametweaker"
SlashCmdList["FRAMETWEAKER"] = function()
    RenderCategoryTree()
    browserFrame:Show()
end

DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[FrameTweaker]|r Type /ft to open the UI Category Tree.")