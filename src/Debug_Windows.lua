local debugWindows = {}
PvP_Scalpel_DebugWindowState = PvP_Scalpel_DebugWindowState or {}

local function NormalizeWindowName(windowName)
    if type(windowName) == "string" and windowName ~= "" then
        return windowName
    end
    return "PvP Scalpel Debug"
end

local function EnsureDebugWindowStateStore()
    if type(PvP_Scalpel_DebugWindowState) ~= "table" then
        PvP_Scalpel_DebugWindowState = {}
    end
    return PvP_Scalpel_DebugWindowState
end

local function GetStoredWindowLayout(windowName)
    local store = EnsureDebugWindowStateStore()
    local layout = store[NormalizeWindowName(windowName)]
    if type(layout) ~= "table" then
        return nil
    end
    return layout
end

local function SaveWindowLayout(window)
    if type(window) ~= "table" or type(window.frame) ~= "table" then
        return
    end

    local frame = window.frame
    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    local store = EnsureDebugWindowStateStore()
    store[window.name] = {
        point = type(point) == "string" and point or "CENTER",
        relativePoint = type(relativePoint) == "string" and relativePoint or "CENTER",
        x = type(xOfs) == "number" and xOfs or 0,
        y = type(yOfs) == "number" and yOfs or 0,
        width = frame:GetWidth(),
        height = frame:GetHeight(),
    }
end

local function BuildWindowGlobalName(windowName)
    local sanitized = tostring(windowName):gsub("[^%w]", "")
    if sanitized == "" then
        sanitized = "PvPScalpelDebug"
    end
    return "PvPScalpelDebugWindow" .. sanitized
end

local function ApplyBackdrop(frame)
    if type(frame.SetBackdrop) ~= "function" then
        return
    end

    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.02, 0.03, 0.05, 0.92)
    frame:SetBackdropBorderColor(0.16, 0.75, 0.56, 0.95)
end

local function CreateWindow(windowName)
    local normalizedName = NormalizeWindowName(windowName)
    local globalName = BuildWindowGlobalName(normalizedName)
    local storedLayout = GetStoredWindowLayout(normalizedName)
    local frame = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    local width = 560
    local height = 220
    if type(storedLayout) == "table" then
        if type(storedLayout.width) == "number" and storedLayout.width >= 320 then
            width = storedLayout.width
        end
        if type(storedLayout.height) == "number" and storedLayout.height >= 140 then
            height = storedLayout.height
        end
    end
    frame:SetSize(width, height)
    if type(frame.SetResizable) == "function" then
        frame:SetResizable(true)
    end
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(320, 140)
    elseif type(frame.SetMinResize) == "function" then
        frame:SetMinResize(320, 140)
    end
    if type(storedLayout) == "table" then
        frame:SetPoint(
            type(storedLayout.point) == "string" and storedLayout.point or "CENTER",
            UIParent,
            type(storedLayout.relativePoint) == "string" and storedLayout.relativePoint or "CENTER",
            type(storedLayout.x) == "number" and storedLayout.x or 0,
            type(storedLayout.y) == "number" and storedLayout.y or 180
        )
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    end
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    ApplyBackdrop(frame)
    frame:Hide()

    local titleBar = frame:CreateTexture(nil, "ARTWORK")
    titleBar:SetColorTexture(0.05, 0.11, 0.10, 0.95)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    titleBar:SetHeight(22)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    title:SetJustifyH("LEFT")
    title:SetText(normalizedName)

    local window = {
        frame = frame,
        title = title,
        name = normalizedName,
        suppressAutoOpen = false,
    }

    local dragRegion = CreateFrame("Button", nil, frame)
    dragRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    dragRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -4)
    dragRegion:SetHeight(22)
    dragRegion:RegisterForDrag("LeftButton")
    dragRegion:SetScript("OnDragStart", function()
        if not InCombatLockdown or not InCombatLockdown() then
            frame:StartMoving()
        end
    end)
    dragRegion:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveWindowLayout(window)
    end)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeButton:SetScript("OnClick", function()
        window.suppressAutoOpen = true
        frame:Hide()
    end)

    local scrollFrame = CreateFrame("ScrollingMessageFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    scrollFrame:SetFontObject(ChatFontNormal)
    scrollFrame:SetJustifyH("LEFT")
    scrollFrame:SetFading(false)
    scrollFrame:SetIndentedWordWrap(true)
    scrollFrame:SetMaxLines(1000)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)

    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    resizeHandle:EnableMouse(true)
    resizeHandle:RegisterForDrag("LeftButton")
    resizeHandle:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    resizeHandle:SetScript("OnDragStart", function()
        if not InCombatLockdown or not InCombatLockdown() then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeHandle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveWindowLayout(window)
    end)

    window.messageFrame = scrollFrame
    debugWindows[normalizedName] = window
    return window
end

local function GetOrCreateWindow(windowName)
    local normalizedName = NormalizeWindowName(windowName)
    return debugWindows[normalizedName] or CreateWindow(normalizedName)
end

function PvPScalpel_DebugWindowFind(windowName)
    local window = debugWindows[NormalizeWindowName(windowName)]
    if window then
        return window.messageFrame
    end
    return nil
end

function PvPScalpel_DebugWindowOpen(windowName, preserveMessages)
    local window = GetOrCreateWindow(windowName)
    window.suppressAutoOpen = false
    if preserveMessages ~= true and window.messageFrame.Clear then
        window.messageFrame:Clear()
    end
    window.title:SetText(window.name)
    window.frame:Show()
    return window.messageFrame
end

function PvPScalpel_DebugWindowOpenIfAllowed(windowName, preserveMessages)
    local normalizedName = NormalizeWindowName(windowName)
    local existingWindow = debugWindows[normalizedName]
    if existingWindow and existingWindow.suppressAutoOpen == true then
        return nil
    end
    return PvPScalpel_DebugWindowOpen(normalizedName, preserveMessages)
end

function PvPScalpel_DebugWindowClear(windowName)
    local window = debugWindows[NormalizeWindowName(windowName)]
    if window and window.messageFrame.Clear then
        window.messageFrame:Clear()
    end
    if window then
        return window.messageFrame
    end
    return nil
end

function PvPScalpel_DebugWindowClose(windowName)
    local window = debugWindows[NormalizeWindowName(windowName)]
    if window then
        window.frame:Hide()
        return true
    end
    return false
end
