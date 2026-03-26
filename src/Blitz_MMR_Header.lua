local BLITZ_LINGER_SECONDS = 30
local BLITZ_ACCEPT_WINDOW_RESYNC_SECONDS = 0.5
local BLITZ_QUEUE_RESOLUTION_GRACE_SECONDS = 1.75
local BLITZ_RATED_BRACKET_INDEX = 9
local BLITZ_HEADER_LAYOUT_KEY = "PvP Scalpel Blitz Header"

PvP_Scalpel_BlitzMmrCache = PvP_Scalpel_BlitzMmrCache or {}

local blitzMmrHeaderFrame = CreateFrame("Frame", "PvPScalpelBlitzMmrHeader", UIParent)
blitzMmrHeaderFrame:SetFrameStrata("HIGH")
blitzMmrHeaderFrame:SetPoint("TOP", UIParent, "TOP", 0, -38)
blitzMmrHeaderFrame:SetSize(392, 56)
blitzMmrHeaderFrame:EnableMouse(false)
blitzMmrHeaderFrame:SetClampedToScreen(true)
blitzMmrHeaderFrame:SetMovable(true)
blitzMmrHeaderFrame:Hide()

local blitzMmrHeaderBackground = blitzMmrHeaderFrame:CreateTexture(nil, "BACKGROUND")
blitzMmrHeaderBackground:SetAllPoints()
blitzMmrHeaderBackground:SetColorTexture(0.03, 0.04, 0.05, 0.74)

local blitzMmrHeaderProgressFill = blitzMmrHeaderFrame:CreateTexture(nil, "ARTWORK")
blitzMmrHeaderProgressFill:SetPoint("TOPLEFT", blitzMmrHeaderFrame, "TOPLEFT", 3, -1)
blitzMmrHeaderProgressFill:SetPoint("BOTTOMLEFT", blitzMmrHeaderFrame, "BOTTOMLEFT", 3, 1)
blitzMmrHeaderProgressFill:SetWidth(0)
blitzMmrHeaderProgressFill:SetColorTexture(0.24, 0.60, 0.34, 0.28)
blitzMmrHeaderProgressFill:Hide()

local blitzMmrHeaderGlow = blitzMmrHeaderFrame:CreateTexture(nil, "BORDER")
blitzMmrHeaderGlow:SetPoint("TOPLEFT", blitzMmrHeaderFrame, "TOPLEFT", 1, -1)
blitzMmrHeaderGlow:SetPoint("BOTTOMRIGHT", blitzMmrHeaderFrame, "BOTTOMRIGHT", -1, 1)
blitzMmrHeaderGlow:SetColorTexture(0.10, 0.13, 0.17, 0.35)

local blitzMmrHeaderTopBorder = blitzMmrHeaderFrame:CreateTexture(nil, "ARTWORK")
blitzMmrHeaderTopBorder:SetPoint("TOPLEFT", blitzMmrHeaderFrame, "TOPLEFT", 0, 0)
blitzMmrHeaderTopBorder:SetPoint("TOPRIGHT", blitzMmrHeaderFrame, "TOPRIGHT", 0, 0)
blitzMmrHeaderTopBorder:SetHeight(1)
blitzMmrHeaderTopBorder:SetColorTexture(0.76, 0.61, 0.25, 0.75)

local blitzMmrHeaderBottomBorder = blitzMmrHeaderFrame:CreateTexture(nil, "ARTWORK")
blitzMmrHeaderBottomBorder:SetPoint("BOTTOMLEFT", blitzMmrHeaderFrame, "BOTTOMLEFT", 0, 0)
blitzMmrHeaderBottomBorder:SetPoint("BOTTOMRIGHT", blitzMmrHeaderFrame, "BOTTOMRIGHT", 0, 0)
blitzMmrHeaderBottomBorder:SetHeight(1)
blitzMmrHeaderBottomBorder:SetColorTexture(0.24, 0.18, 0.08, 0.85)

local blitzMmrHeaderLeftAccent = blitzMmrHeaderFrame:CreateTexture(nil, "ARTWORK")
blitzMmrHeaderLeftAccent:SetPoint("TOPLEFT", blitzMmrHeaderFrame, "TOPLEFT", 0, 0)
blitzMmrHeaderLeftAccent:SetPoint("BOTTOMLEFT", blitzMmrHeaderFrame, "BOTTOMLEFT", 0, 0)
blitzMmrHeaderLeftAccent:SetWidth(3)
blitzMmrHeaderLeftAccent:SetColorTexture(0.84, 0.67, 0.24, 0.95)

local blitzMmrHeaderLabel = blitzMmrHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
blitzMmrHeaderLabel:SetPoint("TOPLEFT", blitzMmrHeaderFrame, "TOPLEFT", 12, -7)
blitzMmrHeaderLabel:SetJustifyH("LEFT")
blitzMmrHeaderLabel:SetTextColor(0.79, 0.80, 0.84)
blitzMmrHeaderLabel:SetText("")

local blitzMmrHeaderStatusBackground = blitzMmrHeaderFrame:CreateTexture(nil, "ARTWORK")
blitzMmrHeaderStatusBackground:SetPoint("TOPRIGHT", blitzMmrHeaderFrame, "TOPRIGHT", -10, -7)
blitzMmrHeaderStatusBackground:SetSize(52, 14)
blitzMmrHeaderStatusBackground:SetColorTexture(0.10, 0.28, 0.20, 0.90)
blitzMmrHeaderStatusBackground:Hide()

local blitzMmrHeaderStatusText = blitzMmrHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
blitzMmrHeaderStatusText:SetPoint("CENTER", blitzMmrHeaderStatusBackground, "CENTER", 0, 0)
blitzMmrHeaderStatusText:SetTextColor(0.66, 1.00, 0.78)
blitzMmrHeaderStatusText:SetText("QUEUED")
blitzMmrHeaderStatusText:Hide()

local blitzMmrHeaderTimer = blitzMmrHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
blitzMmrHeaderTimer:SetPoint("RIGHT", blitzMmrHeaderStatusBackground, "LEFT", -10, 0)
blitzMmrHeaderTimer:SetTextColor(0.90, 0.84, 0.70)
blitzMmrHeaderTimer:SetText("")
blitzMmrHeaderTimer:Hide()

local blitzMmrHeaderValue = blitzMmrHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
blitzMmrHeaderValue:SetPoint("BOTTOMLEFT", blitzMmrHeaderFrame, "BOTTOMLEFT", 12, 8)
blitzMmrHeaderValue:SetJustifyH("LEFT")
blitzMmrHeaderValue:SetTextColor(1.00, 0.96, 0.88)
blitzMmrHeaderValue:SetText("")

local blitzMmrHeaderSuffix = blitzMmrHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
blitzMmrHeaderSuffix:SetPoint("LEFT", blitzMmrHeaderValue, "RIGHT", 6, 0)
blitzMmrHeaderSuffix:SetJustifyH("LEFT")
blitzMmrHeaderSuffix:SetTextColor(0.85, 0.70, 0.32)
blitzMmrHeaderSuffix:SetText("MMR")

local blitzMmrHeaderDelta = blitzMmrHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
blitzMmrHeaderDelta:SetPoint("LEFT", blitzMmrHeaderSuffix, "RIGHT", 10, 0)
blitzMmrHeaderDelta:SetJustifyH("LEFT")
blitzMmrHeaderDelta:SetText("")

local blitzMmrHeaderHint = blitzMmrHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
blitzMmrHeaderHint:SetPoint("BOTTOMRIGHT", blitzMmrHeaderFrame, "BOTTOMRIGHT", -10, 8)
blitzMmrHeaderHint:SetJustifyH("RIGHT")
blitzMmrHeaderHint:SetTextColor(0.94, 0.80, 0.66)
blitzMmrHeaderHint:SetText("")
blitzMmrHeaderHint:Hide()

local blitzMmrHeaderEventFrame = CreateFrame("Frame")
local blitzMmrHeaderQueueIndex = nil
local blitzMmrHeaderQueueStartedAt = nil
local blitzMmrHeaderQueueEstimatedSeconds = nil
local blitzMmrHeaderUpdateElapsed = 0
local blitzMmrHeaderQueueState = "hidden"
local blitzMmrHeaderFrozenQueueSeconds = nil
local blitzMmrHeaderRequeueCount = 0
local blitzMmrHeaderPopCount = 0
local blitzMmrHeaderHasActiveQueue = false
local blitzMmrHeaderAwaitingPopResolution = false
local blitzMmrHeaderLingerHideAt = nil
local blitzMmrHeaderLingerReason = nil
local blitzMmrHeaderAcceptedPopupVisible = false
local blitzMmrHeaderLatestReadyCheckInfo = nil
local blitzMmrHeaderAcceptWindowStartRemainingSeconds = nil
local blitzMmrHeaderAcceptWindowExpiresAt = nil
local blitzMmrHeaderAcceptWindowLastSyncAt = nil
local blitzMmrHeaderPendingQueueResolution = false
local blitzMmrHeaderPendingQueueResolutionStartedAt = nil
local blitzMmrHeaderPendingQueueResolutionFromState = nil
local blitzMmrHeaderScanDisplayedProgress = nil
local blitzMmrHeaderDragging = false
local blitzMmrHeaderSuppressNextClick = false
local blitzMmrHeaderWasInLiveMatch = false
local blitzMmrHeaderPendingPostMatchSummary = nil
local blitzMmrHeaderPendingPostMatchToken = nil
local blitzMmrHeaderAwaitingPostMatchSummary = false
local blitzMmrHeaderPostMatchSummary = nil
local blitzMmrHeaderPostMatchToken = nil
local blitzMmrHeaderDismissQueue = false
local blitzMmrHeaderDismissScan = false
local blitzMmrHeaderDismissLingerToken = nil
local blitzMmrHeaderDismissPostMatchToken = nil
local blitzMmrHeaderContextMenu = nil

local function PvPScalpel_EnsureBlitzHeaderStateStore()
    if type(PvP_Scalpel_DebugWindowState) ~= "table" then
        PvP_Scalpel_DebugWindowState = {}
    end
    return PvP_Scalpel_DebugWindowState
end

local function PvPScalpel_GetStoredBlitzHeaderLayout()
    local store = PvPScalpel_EnsureBlitzHeaderStateStore()
    local layout = store[BLITZ_HEADER_LAYOUT_KEY]
    if type(layout) ~= "table" then
        return nil
    end
    return layout
end

local function PvPScalpel_SaveBlitzHeaderLayout()
    local point, _, relativePoint, xOfs, yOfs = blitzMmrHeaderFrame:GetPoint(1)
    local store = PvPScalpel_EnsureBlitzHeaderStateStore()
    store[BLITZ_HEADER_LAYOUT_KEY] = {
        point = type(point) == "string" and point or "TOP",
        relativePoint = type(relativePoint) == "string" and relativePoint or "TOP",
        x = type(xOfs) == "number" and xOfs or 0,
        y = type(yOfs) == "number" and yOfs or -38,
    }
end

local function PvPScalpel_ClearBlitzHeaderLayout()
    local store = PvPScalpel_EnsureBlitzHeaderStateStore()
    store[BLITZ_HEADER_LAYOUT_KEY] = nil
end

local function PvPScalpel_ApplyBlitzHeaderLayout()
    local storedLayout = PvPScalpel_GetStoredBlitzHeaderLayout()
    blitzMmrHeaderFrame:ClearAllPoints()
    if type(storedLayout) == "table" then
        blitzMmrHeaderFrame:SetPoint(
            type(storedLayout.point) == "string" and storedLayout.point or "TOP",
            UIParent,
            type(storedLayout.relativePoint) == "string" and storedLayout.relativePoint or "TOP",
            type(storedLayout.x) == "number" and storedLayout.x or 0,
            type(storedLayout.y) == "number" and storedLayout.y or -38
        )
        return
    end

    blitzMmrHeaderFrame:SetPoint("TOP", UIParent, "TOP", 0, -38)
end

local function PvPScalpel_IsPositiveNumber(value)
    return type(value) == "number" and value > 0
end

local function PvPScalpel_FormatMmrValue(value)
    if type(value) ~= "number" then
        return "0"
    end

    local floored = math.floor(value + 0.5)
    if type(BreakUpLargeNumbers) == "function" then
        return BreakUpLargeNumbers(floored)
    end

    return tostring(floored)
end

local function PvPScalpel_FormatQueueTimer(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        seconds = 0
    end

    local totalSeconds = math.floor(seconds)
    local minutes = math.floor(totalSeconds / 60)
    local remainingSeconds = totalSeconds % 60
    return string.format("%02d:%02d", minutes, remainingSeconds)
end

local function PvPScalpel_FormatAcceptTimer(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        seconds = 0
    end

    local totalSeconds = math.max(0, math.ceil(seconds))
    return string.format(":%02d", totalSeconds)
end

local function PvPScalpel_FormatAcceptTimerInline(seconds)
    return PvPScalpel_FormatAcceptTimer(seconds) .. " TO ACCEPT"
end

local function PvPScalpel_FormatEnterTimerInline(seconds)
    return PvPScalpel_FormatAcceptTimer(seconds) .. " TO ENTER"
end

local function PvPScalpel_SetBlitzHeaderStatus(text, red, green, blue, backgroundRed, backgroundGreen, backgroundBlue, backgroundAlpha)
    blitzMmrHeaderStatusText:SetText(text)
    blitzMmrHeaderStatusText:SetTextColor(red, green, blue)
    blitzMmrHeaderStatusBackground:SetColorTexture(backgroundRed, backgroundGreen, backgroundBlue, backgroundAlpha)

    local width = math.max(52, math.floor((blitzMmrHeaderStatusText:GetStringWidth() or 0) + 14))
    blitzMmrHeaderStatusBackground:SetWidth(width)
end

local function PvPScalpel_HideBlitzHeaderProgressFill()
    blitzMmrHeaderProgressFill:Hide()
    blitzMmrHeaderProgressFill:SetWidth(0)
end

local function PvPScalpel_SetBlitzHeaderProgressFill(progress, red, green, blue, alpha)
    if type(progress) ~= "number" then
        PvPScalpel_HideBlitzHeaderProgressFill()
        return
    end

    progress = math.max(0, math.min(1, progress))
    if progress <= 0 then
        PvPScalpel_HideBlitzHeaderProgressFill()
        return
    end

    local maxWidth = math.max(0, (blitzMmrHeaderFrame:GetWidth() or 0) - 4)
    blitzMmrHeaderProgressFill:ClearAllPoints()
    blitzMmrHeaderProgressFill:SetPoint("TOPLEFT", blitzMmrHeaderFrame, "TOPLEFT", 3, -1)
    blitzMmrHeaderProgressFill:SetPoint("BOTTOMLEFT", blitzMmrHeaderFrame, "BOTTOMLEFT", 3, 1)
    blitzMmrHeaderProgressFill:SetColorTexture(red, green, blue, alpha)
    blitzMmrHeaderProgressFill:SetWidth(maxWidth * progress)
    blitzMmrHeaderProgressFill:Show()
end

local function PvPScalpel_SetBlitzHeaderQueuedStyleFill(progress)
    PvPScalpel_SetBlitzHeaderProgressFill(progress, 0.62, 0.62, 0.66, 0.22)
end

local function PvPScalpel_SetBlitzHeaderReverseProgressFill(progress, red, green, blue, alpha)
    if type(progress) ~= "number" then
        PvPScalpel_HideBlitzHeaderProgressFill()
        return
    end

    progress = math.max(0, math.min(1, progress))
    local remaining = 1 - progress
    if remaining <= 0 then
        PvPScalpel_HideBlitzHeaderProgressFill()
        return
    end

    local maxWidth = math.max(0, (blitzMmrHeaderFrame:GetWidth() or 0) - 4)
    blitzMmrHeaderProgressFill:ClearAllPoints()
    blitzMmrHeaderProgressFill:SetPoint("TOPLEFT", blitzMmrHeaderFrame, "TOPLEFT", 3, -1)
    blitzMmrHeaderProgressFill:SetPoint("BOTTOMLEFT", blitzMmrHeaderFrame, "BOTTOMLEFT", 3, 1)
    blitzMmrHeaderProgressFill:SetColorTexture(red, green, blue, alpha)
    blitzMmrHeaderProgressFill:SetWidth(maxWidth * remaining)
    blitzMmrHeaderProgressFill:Show()
end

local function PvPScalpel_GetBlitzLobbyScanProgress(snapshot)
    local expected = type(snapshot) == "table" and type(snapshot.expectedLocalCount) == "number" and snapshot.expectedLocalCount or 0
    local resolved = type(snapshot) == "table" and type(snapshot.resolvedCount) == "number" and snapshot.resolvedCount or 0
    if expected <= 0 then
        return 0
    end
    return math.max(0, math.min(resolved, expected)) / expected
end

local function PvPScalpel_ApplyBlitzLobbyScanProgressFill(scanState, progress)
    if scanState == "FAILED" then
        PvPScalpel_SetBlitzHeaderReverseProgressFill(progress, 0.72, 0.20, 0.20, 0.30)
        return
    end

    PvPScalpel_SetBlitzHeaderReverseProgressFill(progress, 0.20, 0.62, 0.32, 0.28)
end

local function PvPScalpel_ClearBlitzHeaderVisuals()
    blitzMmrHeaderLabel:SetText("")
    blitzMmrHeaderValue:SetText("")
    blitzMmrHeaderDelta:SetText("")
    blitzMmrHeaderTimer:SetText("")
    blitzMmrHeaderTimer:Hide()
    blitzMmrHeaderStatusBackground:Hide()
    blitzMmrHeaderStatusText:Hide()
    blitzMmrHeaderHint:Hide()
    blitzMmrHeaderFrame:EnableMouse(false)
    blitzMmrHeaderScanDisplayedProgress = nil
    PvPScalpel_HideBlitzHeaderProgressFill()
    blitzMmrHeaderFrame:Hide()
end

local function PvPScalpel_ClearBlitzHeaderLingerState()
    blitzMmrHeaderLingerHideAt = nil
    blitzMmrHeaderLingerReason = nil
    blitzMmrHeaderPostMatchSummary = nil
    blitzMmrHeaderPostMatchToken = nil
end

local function PvPScalpel_ClearBlitzPendingQueueResolution()
    blitzMmrHeaderPendingQueueResolution = false
    blitzMmrHeaderPendingQueueResolutionStartedAt = nil
    blitzMmrHeaderPendingQueueResolutionFromState = nil
end

local function PvPScalpel_ClearBlitzAcceptWindowState()
    blitzMmrHeaderAcceptWindowStartRemainingSeconds = nil
    blitzMmrHeaderAcceptWindowExpiresAt = nil
    blitzMmrHeaderAcceptWindowLastSyncAt = nil
    blitzMmrHeaderLatestReadyCheckInfo = nil
    blitzMmrHeaderAcceptedPopupVisible = false
end

local function PvPScalpel_ResetBlitzHeaderRuntimeState()
    PvPScalpel_ClearBlitzHeaderLingerState()
    PvPScalpel_ClearBlitzPendingQueueResolution()
    PvPScalpel_ClearBlitzAcceptWindowState()
    blitzMmrHeaderQueueIndex = nil
    blitzMmrHeaderQueueStartedAt = nil
    blitzMmrHeaderQueueEstimatedSeconds = nil
    blitzMmrHeaderUpdateElapsed = 0
    blitzMmrHeaderQueueState = "hidden"
    blitzMmrHeaderFrozenQueueSeconds = nil
    blitzMmrHeaderRequeueCount = 0
    blitzMmrHeaderPopCount = 0
    blitzMmrHeaderHasActiveQueue = false
    blitzMmrHeaderAwaitingPopResolution = false
end

local function PvPScalpel_BeginBlitzHeaderQueueCycle(queueIndex)
    PvPScalpel_ClearBlitzHeaderLingerState()
    PvPScalpel_ClearBlitzPendingQueueResolution()
    PvPScalpel_ClearBlitzAcceptWindowState()
    blitzMmrHeaderQueueIndex = queueIndex
    blitzMmrHeaderQueueStartedAt = nil
    blitzMmrHeaderQueueEstimatedSeconds = nil
    blitzMmrHeaderUpdateElapsed = 0
    blitzMmrHeaderQueueState = "queued"
    blitzMmrHeaderFrozenQueueSeconds = nil
    blitzMmrHeaderRequeueCount = 0
    blitzMmrHeaderPopCount = 0
    blitzMmrHeaderHasActiveQueue = true
    blitzMmrHeaderAwaitingPopResolution = false
    blitzMmrHeaderDismissQueue = false
end

local function PvPScalpel_StartBlitzHeaderLinger(reason, summary, token)
    if reason ~= "canceled" and reason ~= "dodged" and reason ~= "postmatch" then
        return
    end

    blitzMmrHeaderQueueIndex = nil
    blitzMmrHeaderQueueStartedAt = nil
    blitzMmrHeaderQueueEstimatedSeconds = nil
    blitzMmrHeaderQueueState = reason
    blitzMmrHeaderHasActiveQueue = false
    blitzMmrHeaderAcceptedPopupVisible = false
    blitzMmrHeaderAwaitingPopResolution = false
    blitzMmrHeaderAcceptWindowStartRemainingSeconds = nil
    blitzMmrHeaderAcceptWindowExpiresAt = nil
    blitzMmrHeaderAcceptWindowLastSyncAt = nil
    blitzMmrHeaderLingerReason = reason
    blitzMmrHeaderLingerHideAt = GetTime() + BLITZ_LINGER_SECONDS
    if reason == "postmatch" then
        blitzMmrHeaderPostMatchSummary = type(summary) == "table" and summary or nil
        blitzMmrHeaderPostMatchToken = type(token) == "string" and token or nil
        blitzMmrHeaderPendingPostMatchSummary = nil
        blitzMmrHeaderPendingPostMatchToken = nil
        blitzMmrHeaderAwaitingPostMatchSummary = false
    else
        blitzMmrHeaderPostMatchSummary = nil
        blitzMmrHeaderPostMatchToken = nil
    end
end

local function PvPScalpel_IsBlitzHeaderLingering()
    return (blitzMmrHeaderLingerReason == "canceled"
        or blitzMmrHeaderLingerReason == "dodged"
        or blitzMmrHeaderLingerReason == "postmatch")
        and type(blitzMmrHeaderLingerHideAt) == "number"
end

local function PvPScalpel_IsBlitzHeaderPostMatchLingering()
    return blitzMmrHeaderLingerReason == "postmatch"
        and type(blitzMmrHeaderLingerHideAt) == "number"
        and type(blitzMmrHeaderPostMatchSummary) == "table"
end

local function PvPScalpel_GetBlitzHeaderLingerStatusText()
    if blitzMmrHeaderLingerReason == "postmatch" then
        return "RESULT"
    end

    if blitzMmrHeaderLingerReason == "canceled" or blitzMmrHeaderLingerReason == "dodged" then
        return string.upper(blitzMmrHeaderLingerReason)
    end

    return nil
end

local function PvPScalpel_StartBlitzPendingQueueResolution(fromState)
    if fromState ~= "accepted" and fromState ~= "confirm" and fromState ~= "queued" then
        return
    end

    blitzMmrHeaderPendingQueueResolution = true
    blitzMmrHeaderPendingQueueResolutionStartedAt = GetTime()
    blitzMmrHeaderPendingQueueResolutionFromState = fromState
    blitzMmrHeaderHasActiveQueue = false
    blitzMmrHeaderAcceptedPopupVisible = false
    blitzMmrHeaderQueueState = fromState
end

local function PvPScalpel_GetLocalPlayerIdentity()
    local playerGuid = UnitGUID("player")
    local playerName, playerRealm = UnitFullName("player")
    if type(playerRealm) ~= "string" or playerRealm == "" then
        playerRealm = GetRealmName()
    end

    return {
        guid = playerGuid,
        name = playerName or UnitName("player"),
        realm = PvPScalpel_Slugify and PvPScalpel_Slugify(playerRealm or "") or (playerRealm or ""),
    }
end

local function PvPScalpel_EnsureBlitzMmrCache()
    if type(PvP_Scalpel_BlitzMmrCache) ~= "table" then
        PvP_Scalpel_BlitzMmrCache = {}
    end

    return PvP_Scalpel_BlitzMmrCache
end

local function PvPScalpel_GetMostRecentBlitzMatch()
    if type(PvP_Scalpel_DB) ~= "table" then
        return nil
    end

    for i = #PvP_Scalpel_DB, 1, -1 do
        local match = PvP_Scalpel_DB[i]
        local details = type(match) == "table" and match.matchDetails or nil
        if type(details) == "table" and details.format == "Battleground Blitz" then
            return match
        end
    end

    return nil
end

local function PvPScalpel_FindOwnerPlayerEntry(players, identity)
    if type(players) ~= "table" then
        return nil
    end

    for i = 1, #players do
        local entry = players[i]
        if type(entry) == "table" and entry.isOwner == true then
            return entry
        end
    end

    if type(identity) == "table" and type(identity.guid) == "string" and identity.guid ~= "" then
        for i = 1, #players do
            local entry = players[i]
            if type(entry) == "table" and entry.guid == identity.guid then
                return entry
            end
        end
    end

    if type(identity) == "table" and type(identity.name) == "string" and identity.name ~= "" then
        local localRealm = type(identity.realm) == "string" and identity.realm or ""
        for i = 1, #players do
            local entry = players[i]
            if type(entry) == "table" and entry.name == identity.name then
                local entryRealm = entry.realm
                if type(entryRealm) ~= "string" then
                    entryRealm = ""
                elseif PvPScalpel_Slugify then
                    entryRealm = PvPScalpel_Slugify(entryRealm)
                end
                if entryRealm == localRealm then
                    return entry
                end
            end
        end
    end

    return nil
end

local function PvPScalpel_BuildBlitzMmrSummary(match)
    if type(match) ~= "table" then
        return nil
    end

    local details = match.matchDetails
    if type(details) ~= "table" or details.format ~= "Battleground Blitz" then
        return nil
    end

    local identity = PvPScalpel_GetLocalPlayerIdentity()
    local playerEntry = PvPScalpel_FindOwnerPlayerEntry(match.players, identity)
    if type(playerEntry) ~= "table" then
        return nil
    end

    local currentMmr = playerEntry.postmatchMMR
    if not PvPScalpel_IsPositiveNumber(currentMmr) then
        return nil
    end

    local hasValidDelta = type(playerEntry.prematchMMR) == "number"
    local delta = nil
    if hasValidDelta then
        delta = currentMmr - playerEntry.prematchMMR
    end

    return {
        matchKey = type(match.matchKey) == "string" and match.matchKey or "",
        timestamp = type(details.timestamp) == "string" and details.timestamp or "",
        currentMMR = currentMmr,
        delta = delta,
        hasValidDelta = hasValidDelta,
    }
end

local function PvPScalpel_GetBlitzSummaryToken(summary)
    if type(summary) ~= "table" then
        return nil
    end

    local matchKey = type(summary.matchKey) == "string" and summary.matchKey or ""
    if matchKey ~= "" then
        return "match:" .. matchKey
    end

    return table.concat({
        tostring(summary.timestamp or ""),
        tostring(summary.currentMMR or ""),
        tostring(summary.delta or ""),
    }, "|")
end

local function PvPScalpel_GetBlitzBracketRating()
    if type(GetPersonalRatedInfo) ~= "function" then
        return nil
    end

    local okRating, rating = pcall(GetPersonalRatedInfo, BLITZ_RATED_BRACKET_INDEX)
    if okRating and type(rating) == "number" and rating >= 0 then
        return rating
    end

    return nil
end

local function PvPScalpel_GetBlitzHeaderSummary()
    local cache = PvPScalpel_EnsureBlitzMmrCache()
    local cachedPostmatchMMR = cache.postmatchMMR
    if PvPScalpel_IsPositiveNumber(cachedPostmatchMMR) then
        local hasValidDelta = type(cache.prematchMMR) == "number"
        return {
            currentMMR = cachedPostmatchMMR,
            delta = hasValidDelta and (cachedPostmatchMMR - cache.prematchMMR) or nil,
            hasValidDelta = hasValidDelta,
            suffixText = "MMR",
        }
    end

    local bracketRating = PvPScalpel_GetBlitzBracketRating()
    if type(bracketRating) == "number" then
        return {
            currentMMR = bracketRating,
            delta = nil,
            hasValidDelta = false,
            suffixText = "RATING",
        }
    end

    return {
        currentMMR = 0,
        delta = nil,
        hasValidDelta = false,
        suffixText = "RATING",
    }
end

local function PvPScalpel_UpdateBlitzMmrCacheFromMatch(match)
    if type(match) ~= "table" then
        return false
    end

    local details = match.matchDetails
    if type(details) ~= "table" or details.format ~= "Battleground Blitz" then
        return false
    end

    local identity = PvPScalpel_GetLocalPlayerIdentity()
    local ownerEntry = PvPScalpel_FindOwnerPlayerEntry(match.players, identity)
    if type(ownerEntry) ~= "table" then
        return false
    end

    local cache = PvPScalpel_EnsureBlitzMmrCache()
    cache.prematchMMR = type(ownerEntry.prematchMMR) == "number" and ownerEntry.prematchMMR or nil
    cache.postmatchMMR = type(ownerEntry.postmatchMMR) == "number" and ownerEntry.postmatchMMR or nil
    return true
end

local function PvPScalpel_GetQueuedBlitzInfo()
    if type(GetMaxBattlefieldID) ~= "function" or type(GetBattlefieldStatus) ~= "function" then
        return false, nil, nil, nil, nil, nil
    end

    local maxBattlefieldID = GetMaxBattlefieldID() or 0
    for i = 1, maxBattlefieldID do
        local status, _, _, _, _, queueType = GetBattlefieldStatus(i)
        if queueType == "RATEDSOLORBG" and (status == "queued" or status == "confirm") then
            local queueStartedAt = nil
            local queueElapsedSeconds = nil
            local queueEstimatedSeconds = nil
            if type(GetBattlefieldTimeWaited) == "function" then
                local waitedMilliseconds = GetBattlefieldTimeWaited(i)
                if type(waitedMilliseconds) == "number" and waitedMilliseconds >= 0 then
                    queueElapsedSeconds = waitedMilliseconds / 1000
                    queueStartedAt = GetTime() - queueElapsedSeconds
                end
            end
            if type(GetBattlefieldEstimatedWaitTime) == "function" then
                local estimatedMilliseconds = GetBattlefieldEstimatedWaitTime(i)
                if type(estimatedMilliseconds) == "number" and estimatedMilliseconds > 0 then
                    queueEstimatedSeconds = estimatedMilliseconds / 1000
                end
            end
            return true, status, queueStartedAt, queueElapsedSeconds, i, queueEstimatedSeconds
        end
    end

    return false, nil, nil, nil, nil, nil
end

local function PvPScalpel_GetBlitzQueuedProgress(queueElapsedSeconds, queueEstimatedSeconds)
    if type(queueElapsedSeconds) ~= "number" or queueElapsedSeconds < 0 then
        return nil
    end
    if type(queueEstimatedSeconds) ~= "number" or queueEstimatedSeconds <= 0 then
        return nil
    end

    local progress = 1 - (queueElapsedSeconds / queueEstimatedSeconds)
    if progress < 0 then
        progress = 0
    elseif progress > 1 then
        progress = 1
    end
    return progress
end

local function PvPScalpel_GetBlitzAcceptRemainingSeconds(queueIndex)
    if type(queueIndex) ~= "number" or type(GetBattlefieldPortExpiration) ~= "function" then
        return nil
    end

    local okExpiration, remainingSeconds = pcall(GetBattlefieldPortExpiration, queueIndex)
    if okExpiration and type(remainingSeconds) == "number" and remainingSeconds >= 0 then
        return remainingSeconds
    end

    return nil
end

local function PvPScalpel_SyncBlitzAcceptWindowTiming(forceSync)
    local now = GetTime()
    local localRemainingSeconds = nil
    if type(blitzMmrHeaderAcceptWindowExpiresAt) == "number" then
        localRemainingSeconds = math.max(0, blitzMmrHeaderAcceptWindowExpiresAt - now)
    end

    local shouldSync = forceSync == true
        or type(blitzMmrHeaderAcceptWindowExpiresAt) ~= "number"
        or type(blitzMmrHeaderAcceptWindowLastSyncAt) ~= "number"
        or (now - blitzMmrHeaderAcceptWindowLastSyncAt) >= BLITZ_ACCEPT_WINDOW_RESYNC_SECONDS

    if shouldSync then
        local syncedRemainingSeconds = PvPScalpel_GetBlitzAcceptRemainingSeconds(blitzMmrHeaderQueueIndex)
        blitzMmrHeaderAcceptWindowLastSyncAt = now
        if PvPScalpel_IsPositiveNumber(syncedRemainingSeconds) then
            if not PvPScalpel_IsPositiveNumber(blitzMmrHeaderAcceptWindowStartRemainingSeconds)
                or syncedRemainingSeconds > blitzMmrHeaderAcceptWindowStartRemainingSeconds
            then
                blitzMmrHeaderAcceptWindowStartRemainingSeconds = syncedRemainingSeconds
            end

            if type(localRemainingSeconds) ~= "number"
                or math.abs(syncedRemainingSeconds - localRemainingSeconds) > 1.0
            then
                blitzMmrHeaderAcceptWindowExpiresAt = now + syncedRemainingSeconds
                localRemainingSeconds = syncedRemainingSeconds
            end
        elseif forceSync == true then
            blitzMmrHeaderAcceptWindowExpiresAt = nil
            localRemainingSeconds = nil
        end
    end

    if type(localRemainingSeconds) ~= "number" and type(blitzMmrHeaderAcceptWindowExpiresAt) == "number" then
        localRemainingSeconds = math.max(0, blitzMmrHeaderAcceptWindowExpiresAt - now)
    end

    return localRemainingSeconds
end

local function PvPScalpel_GetBlitzInviteProgress()
    local remainingSeconds = PvPScalpel_SyncBlitzAcceptWindowTiming(false)
    if not PvPScalpel_IsPositiveNumber(remainingSeconds) then
        return remainingSeconds, nil
    end

    local progress = remainingSeconds / blitzMmrHeaderAcceptWindowStartRemainingSeconds
    return remainingSeconds, math.max(0, math.min(1, progress))
end

local function PvPScalpel_IsLivePvpMatchActiveForHeader()
    if C_PvP and C_PvP.GetActiveMatchState and Enum and Enum.PvPMatchState and Enum.PvPMatchState.Engaged then
        local okState, state = pcall(C_PvP.GetActiveMatchState)
        if okState and type(state) == "number" then
            if state >= Enum.PvPMatchState.Engaged and state < Enum.PvPMatchState.Complete then
                return true
            end
            return false
        end
    end

    if C_PvP and C_PvP.HasMatchStarted then
        local okStarted, started = pcall(C_PvP.HasMatchStarted)
        if okStarted and started == true then
            return true
        end
    end

    return false
end

local function PvPScalpel_GetBlitzLobbyScanSnapshotSafe()
    if type(PvPScalpel_GetBlitzLobbyScanSnapshot) ~= "function" then
        return nil
    end
    return PvPScalpel_GetBlitzLobbyScanSnapshot()
end

local function PvPScalpel_IsBlitzLobbyScanDisplayed(snapshot)
    return type(snapshot) == "table" and snapshot.display == true
end

local function PvPScalpel_IsBlitzLobbyScanCopyReady(snapshot)
    return PvPScalpel_IsBlitzLobbyScanDisplayed(snapshot)
        and (snapshot.scanState == "DONE" or snapshot.scanState == "MOCK")
        and type(snapshot.buffer) == "string"
        and snapshot.buffer ~= ""
end

local function PvPScalpel_FormatBlitzLobbyScanProgress(snapshot)
    local expected = type(snapshot) == "table" and type(snapshot.expectedLocalCount) == "number" and snapshot.expectedLocalCount or 0
    local resolved = type(snapshot) == "table" and type(snapshot.resolvedCount) == "number" and snapshot.resolvedCount or 0
    if expected < 0 then
        expected = 0
    end
    resolved = math.max(0, math.min(resolved, expected > 0 and expected or resolved))
    return string.format("%d / %d Ready", resolved, expected)
end

local function PvPScalpel_ApplyBlitzLobbyScanHeaderDisplay(snapshot)
    if not PvPScalpel_IsBlitzLobbyScanDisplayed(snapshot) then
        return false
    end

    local scanState = type(snapshot.scanState) == "string" and snapshot.scanState or "LOADING"
    local formatLabel = type(snapshot.format) == "string" and string.upper(snapshot.format) or "BATTLEGROUND BLITZ"
    local targetProgress = PvPScalpel_GetBlitzLobbyScanProgress(snapshot)

    blitzMmrHeaderLabel:SetText(formatLabel)
    blitzMmrHeaderSuffix:SetText("")
    blitzMmrHeaderDelta:SetText("")
    blitzMmrHeaderStatusBackground:Show()
    blitzMmrHeaderStatusText:Show()
    blitzMmrHeaderTimer:Show()

    if type(blitzMmrHeaderScanDisplayedProgress) ~= "number" then
        blitzMmrHeaderScanDisplayedProgress = 0
    end

    if scanState == "DONE" or scanState == "MOCK" then
        blitzMmrHeaderValue:SetText("Lobby Scan")
        PvPScalpel_SetBlitzHeaderStatus("READY", 0.70, 1.00, 0.80, 0.10, 0.33, 0.18, 0.92)
        blitzMmrHeaderHint:SetText("Click to copy lobby scan")
        blitzMmrHeaderHint:SetTextColor(0.94, 0.80, 0.66)
        blitzMmrHeaderHint:Show()
    elseif scanState == "FAILED" then
        blitzMmrHeaderValue:SetText("Lobby Scan Failed")
        PvPScalpel_SetBlitzHeaderStatus("FAILED", 1.00, 0.82, 0.82, 0.42, 0.08, 0.08, 0.92)
        blitzMmrHeaderHint:SetText("Scan failed: " .. tostring(snapshot.failureReason or "unknown"))
        blitzMmrHeaderHint:SetTextColor(1.00, 0.78, 0.78)
        blitzMmrHeaderHint:Show()
    else
        blitzMmrHeaderValue:SetText("Scanning Lobby")
        PvPScalpel_SetBlitzHeaderStatus("LOADING", 0.86, 0.96, 1.00, 0.14, 0.23, 0.36, 0.92)
        blitzMmrHeaderHint:Hide()
    end

    if blitzMmrHeaderScanDisplayedProgress > targetProgress then
        blitzMmrHeaderScanDisplayedProgress = targetProgress
    end
    PvPScalpel_ApplyBlitzLobbyScanProgressFill(scanState, blitzMmrHeaderScanDisplayedProgress)
    blitzMmrHeaderTimer:SetText(PvPScalpel_FormatBlitzLobbyScanProgress(snapshot))
    blitzMmrHeaderFrame:EnableMouse(true)
    blitzMmrHeaderFrame:Show()
    return true
end

local function PvPScalpel_OpenBlitzRatedFinder()
    if type(TogglePVPUI) == "function" then
        pcall(TogglePVPUI)
    end
end

local function PvPScalpel_GetCurrentBlitzHeaderLingerToken()
    if blitzMmrHeaderLingerReason == "postmatch" then
        return blitzMmrHeaderPostMatchToken
    end

    if type(blitzMmrHeaderLingerReason) ~= "string" or type(blitzMmrHeaderLingerHideAt) ~= "number" then
        return nil
    end

    return string.format("%s|%.3f", blitzMmrHeaderLingerReason, blitzMmrHeaderLingerHideAt)
end

local function PvPScalpel_GetBlitzHeaderActionHint(snapshot)
    if PvPScalpel_IsBlitzLobbyScanCopyReady(snapshot) then
        return "Left-click to copy lobby scan"
    end

    if PvPScalpel_IsBlitzHeaderLingering() then
        return "Left-click to open PvP Rated Finder"
    end

    return nil
end

local function PvPScalpel_ShowBlitzHeaderTooltip()
    if not GameTooltip or not blitzMmrHeaderFrame:IsShown() then
        return
    end

    local lobbyScanSnapshot = PvPScalpel_GetBlitzLobbyScanSnapshotSafe()
    GameTooltip:SetOwner(blitzMmrHeaderFrame, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("PvP Scalpel", 1.00, 0.92, 0.52)
    local actionHint = PvPScalpel_GetBlitzHeaderActionHint(lobbyScanSnapshot)
    if type(actionHint) == "string" and actionHint ~= "" then
        GameTooltip:AddLine(actionHint, 0.94, 0.80, 0.66)
    end
    GameTooltip:AddLine("Shift+Left drag to move", 0.79, 0.80, 0.84)
    GameTooltip:AddLine("Right-click for banner options", 0.79, 0.80, 0.84)
    GameTooltip:Show()
end

local function PvPScalpel_DismissCurrentBlitzHeaderState()
    local lobbyScanSnapshot = PvPScalpel_GetBlitzLobbyScanSnapshotSafe()
    if PvPScalpel_IsBlitzLobbyScanDisplayed(lobbyScanSnapshot) then
        blitzMmrHeaderDismissScan = true
    elseif PvPScalpel_IsBlitzHeaderPostMatchLingering() then
        blitzMmrHeaderDismissPostMatchToken = blitzMmrHeaderPostMatchToken
    elseif PvPScalpel_IsBlitzHeaderLingering() then
        blitzMmrHeaderDismissLingerToken = PvPScalpel_GetCurrentBlitzHeaderLingerToken()
    else
        blitzMmrHeaderDismissQueue = true
    end

    PvPScalpel_ClearBlitzHeaderVisuals()
end

local function PvPScalpel_GetBlitzHeaderContextMenu()
    if type(blitzMmrHeaderContextMenu) == "table" then
        return blitzMmrHeaderContextMenu
    end

    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel(blitzMmrHeaderFrame:GetFrameLevel() + 20)
    menu:SetSize(150, 58)
    menu:SetClampedToScreen(true)
    menu:Hide()

    if type(menu.SetBackdrop) == "function" then
        menu:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        menu:SetBackdropColor(0.03, 0.04, 0.05, 0.94)
        menu:SetBackdropBorderColor(0.76, 0.61, 0.25, 0.70)
    end

    local closeButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    closeButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -8)
    closeButton:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -10, -8)
    closeButton:SetHeight(20)
    closeButton:SetText("Close banner")
    closeButton:SetScript("OnClick", function()
        menu:Hide()
        PvPScalpel_DismissCurrentBlitzHeaderState()
    end)

    local resetButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    resetButton:SetPoint("TOPLEFT", closeButton, "BOTTOMLEFT", 0, -6)
    resetButton:SetPoint("TOPRIGHT", closeButton, "BOTTOMRIGHT", 0, -6)
    resetButton:SetHeight(20)
    resetButton:SetText("Reset position")
    resetButton:SetScript("OnClick", function()
        menu:Hide()
        PvPScalpel_ClearBlitzHeaderLayout()
        PvPScalpel_ApplyBlitzHeaderLayout()
    end)

    blitzMmrHeaderContextMenu = menu
    return menu
end

local function PvPScalpel_CloseBlitzHeaderContextMenu()
    if type(blitzMmrHeaderContextMenu) == "table" then
        blitzMmrHeaderContextMenu:Hide()
    end
end

local function PvPScalpel_OpenBlitzHeaderContextMenu()
    local menu = PvPScalpel_GetBlitzHeaderContextMenu()
    if menu:IsShown() then
        menu:Hide()
        return
    end

    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", blitzMmrHeaderFrame, "BOTTOMRIGHT", 0, -4)
    menu:Show()
end

local function PvPScalpel_UpdateBlitzMmrHeaderDisplay(summary)
    local lobbyScanSnapshot = PvPScalpel_GetBlitzLobbyScanSnapshotSafe()
    local lingering = PvPScalpel_IsBlitzHeaderLingering()
    local accepted = blitzMmrHeaderAcceptedPopupVisible == true
        or (blitzMmrHeaderPendingQueueResolution == true and blitzMmrHeaderQueueState == "accepted")
    local popped = blitzMmrHeaderQueueState == "confirm"
    local displayActive = PvPScalpel_IsBlitzLobbyScanDisplayed(lobbyScanSnapshot)
        or lingering
        or accepted
        or popped
        or blitzMmrHeaderHasActiveQueue == true
        or blitzMmrHeaderPendingQueueResolution == true
    if not displayActive then
        PvPScalpel_ClearBlitzHeaderVisuals()
        return
    end

    if PvPScalpel_ApplyBlitzLobbyScanHeaderDisplay(lobbyScanSnapshot) then
        return
    end

    if type(summary) ~= "table" then
        PvPScalpel_ClearBlitzHeaderVisuals()
        return
    end

    blitzMmrHeaderLabel:SetText("BATTLEGROUND BLITZ")
    if PvPScalpel_IsBlitzHeaderPostMatchLingering() and type(blitzMmrHeaderPostMatchSummary) == "table" then
        summary = blitzMmrHeaderPostMatchSummary
    end

    blitzMmrHeaderValue:SetText(PvPScalpel_FormatMmrValue(summary.currentMMR))
    blitzMmrHeaderSuffix:SetText(type(summary.suffixText) == "string" and summary.suffixText or "MMR")

    if summary.hasValidDelta == true and type(summary.delta) == "number" then
        local deltaValue = math.floor(summary.delta + 0.5)
        local deltaText = "(" .. tostring(deltaValue) .. ")"
        local red = 0.74
        local green = 0.74
        local blue = 0.76
        if deltaValue > 0 then
            deltaText = "(+" .. tostring(deltaValue) .. ")"
            red = 0.43
            green = 1.00
            blue = 0.58
        elseif deltaValue < 0 then
            red = 1.00
            green = 0.45
            blue = 0.45
        end
        blitzMmrHeaderDelta:SetText(deltaText)
        blitzMmrHeaderDelta:SetTextColor(red, green, blue)
    else
        blitzMmrHeaderDelta:SetText("")
    end

    blitzMmrHeaderStatusBackground:Show()
    blitzMmrHeaderStatusText:Show()
    blitzMmrHeaderTimer:Show()

    if lingering then
        local statusText = PvPScalpel_GetBlitzHeaderLingerStatusText() or "CANCELED"
        if blitzMmrHeaderLingerReason == "postmatch" then
            PvPScalpel_SetBlitzHeaderStatus(statusText, 0.70, 1.00, 0.80, 0.10, 0.33, 0.18, 0.92)
        elseif blitzMmrHeaderLingerReason == "dodged" then
            PvPScalpel_SetBlitzHeaderStatus(statusText, 1.00, 0.84, 0.84, 0.42, 0.08, 0.08, 0.92)
        else
            PvPScalpel_SetBlitzHeaderStatus(statusText, 1.00, 0.82, 0.72, 0.44, 0.11, 0.08, 0.92)
        end
        blitzMmrHeaderTimer:SetText(PvPScalpel_FormatQueueTimer(math.max(0, blitzMmrHeaderLingerHideAt - GetTime())))
        blitzMmrHeaderHint:SetText("Click to open PvP Rated Finder")
        blitzMmrHeaderHint:SetTextColor(0.94, 0.80, 0.66)
        blitzMmrHeaderHint:Show()
        PvPScalpel_HideBlitzHeaderProgressFill()
    elseif accepted or popped then
        local remainingSeconds, progress = PvPScalpel_GetBlitzInviteProgress()
        if accepted then
            PvPScalpel_SetBlitzHeaderStatus("ACCEPTED", 0.70, 1.00, 0.80, 0.10, 0.33, 0.18, 0.92)
            if type(progress) == "number" then
                PvPScalpel_SetBlitzHeaderProgressFill(progress, 0.20, 0.62, 0.32, 0.28)
            else
                PvPScalpel_HideBlitzHeaderProgressFill()
            end
        else
            if blitzMmrHeaderPopCount >= 2 then
                PvPScalpel_SetBlitzHeaderStatus("REPOPPED (" .. tostring(blitzMmrHeaderPopCount) .. ")", 1.00, 0.89, 0.62, 0.42, 0.20, 0.08, 0.92)
            else
                PvPScalpel_SetBlitzHeaderStatus("POPPED", 1.00, 0.89, 0.62, 0.42, 0.20, 0.08, 0.92)
            end
            if type(progress) == "number" then
                PvPScalpel_SetBlitzHeaderProgressFill(progress, 0.72, 0.48, 0.16, 0.30)
            else
                PvPScalpel_HideBlitzHeaderProgressFill()
            end
        end

        if type(remainingSeconds) == "number" then
            if accepted then
                blitzMmrHeaderTimer:SetText(PvPScalpel_FormatEnterTimerInline(remainingSeconds))
            else
                blitzMmrHeaderTimer:SetText(PvPScalpel_FormatAcceptTimerInline(remainingSeconds))
            end
        else
            if accepted then
                blitzMmrHeaderTimer:SetText(PvPScalpel_FormatEnterTimerInline(0))
            else
                blitzMmrHeaderTimer:SetText(PvPScalpel_FormatAcceptTimerInline(0))
            end
        end

        blitzMmrHeaderHint:Hide()
    else
        blitzMmrHeaderHint:Hide()
        if blitzMmrHeaderRequeueCount > 0 then
            PvPScalpel_SetBlitzHeaderStatus("REQUEUED (" .. tostring(blitzMmrHeaderRequeueCount) .. ")", 0.86, 0.96, 1.00, 0.14, 0.23, 0.36, 0.92)
        else
            PvPScalpel_SetBlitzHeaderStatus("QUEUED", 0.66, 1.00, 0.78, 0.10, 0.28, 0.20, 0.90)
        end
        if type(blitzMmrHeaderQueueStartedAt) == "number" then
            blitzMmrHeaderTimer:SetText(PvPScalpel_FormatQueueTimer(GetTime() - blitzMmrHeaderQueueStartedAt))
        else
            blitzMmrHeaderTimer:SetText("00:00")
        end
        local queuedElapsedSeconds = type(blitzMmrHeaderQueueStartedAt) == "number" and math.max(0, GetTime() - blitzMmrHeaderQueueStartedAt) or nil
        local queuedProgress = PvPScalpel_GetBlitzQueuedProgress(queuedElapsedSeconds, blitzMmrHeaderQueueEstimatedSeconds)
        if type(queuedProgress) == "number" then
            PvPScalpel_SetBlitzHeaderQueuedStyleFill(queuedProgress)
        else
            PvPScalpel_HideBlitzHeaderProgressFill()
        end
    end

    blitzMmrHeaderFrame:EnableMouse(true)
    blitzMmrHeaderFrame:Show()
end

function PvPScalpel_BlitzMmrHeaderRefresh()
    local liveMatchActive = PvPScalpel_IsLivePvpMatchActiveForHeader()
    if liveMatchActive then
        blitzMmrHeaderWasInLiveMatch = true
        blitzMmrHeaderDismissScan = false
        blitzMmrHeaderDismissQueue = false
        PvPScalpel_ResetBlitzHeaderRuntimeState()
        PvPScalpel_ClearBlitzHeaderVisuals()
        return
    end

    local justExitedLiveMatch = blitzMmrHeaderWasInLiveMatch == true
    blitzMmrHeaderWasInLiveMatch = false

    -- check
    local latestBlitzSummary = PvPScalpel_GetBlitzHeaderSummary()
    local lobbyScanSnapshot = PvPScalpel_GetBlitzLobbyScanSnapshotSafe()
    if not PvPScalpel_IsBlitzLobbyScanDisplayed(lobbyScanSnapshot) then
        blitzMmrHeaderDismissScan = false
    end

    local queuedForBlitz, queueState, queueStartedAt, queueElapsedSeconds, queueIndex, queueEstimatedSeconds = PvPScalpel_GetQueuedBlitzInfo()
    local previouslyHadQueue = blitzMmrHeaderHasActiveQueue == true
    local previousQueueState = blitzMmrHeaderQueueState
    local previousQueueIndex = blitzMmrHeaderQueueIndex
    local queueWasReady = previousQueueState == "accepted" or previousQueueState == "confirm" or blitzMmrHeaderAwaitingPopResolution == true
    local pendingResolution = blitzMmrHeaderPendingQueueResolution == true
    local pendingFromState = blitzMmrHeaderPendingQueueResolutionFromState
    local pendingGraceExpired = pendingResolution
        and type(blitzMmrHeaderPendingQueueResolutionStartedAt) == "number"
        and (GetTime() - blitzMmrHeaderPendingQueueResolutionStartedAt) >= BLITZ_QUEUE_RESOLUTION_GRACE_SECONDS

    if not queuedForBlitz
        and blitzMmrHeaderAcceptedPopupVisible ~= true
        and blitzMmrHeaderQueueState ~= "confirm"
        and pendingResolution ~= true
    then
        blitzMmrHeaderDismissQueue = false
    end

    if not PvPScalpel_IsBlitzHeaderLingering() then
        blitzMmrHeaderDismissLingerToken = nil
    end
    if not PvPScalpel_IsBlitzHeaderPostMatchLingering() then
        blitzMmrHeaderDismissPostMatchToken = nil
    end

    if justExitedLiveMatch then
        if type(blitzMmrHeaderPendingPostMatchSummary) == "table"
            and type(blitzMmrHeaderPendingPostMatchToken) == "string"
            and blitzMmrHeaderPendingPostMatchToken ~= blitzMmrHeaderDismissPostMatchToken
        then
            PvPScalpel_StartBlitzHeaderLinger("postmatch", blitzMmrHeaderPendingPostMatchSummary, blitzMmrHeaderPendingPostMatchToken)
        else
            blitzMmrHeaderAwaitingPostMatchSummary = true
        end
    end

    if blitzMmrHeaderAwaitingPostMatchSummary == true
        and type(blitzMmrHeaderPendingPostMatchSummary) == "table"
        and type(blitzMmrHeaderPendingPostMatchToken) == "string"
        and blitzMmrHeaderPendingPostMatchToken ~= blitzMmrHeaderDismissPostMatchToken
    then
        PvPScalpel_StartBlitzHeaderLinger("postmatch", blitzMmrHeaderPendingPostMatchSummary, blitzMmrHeaderPendingPostMatchToken)
    end

    if PvPScalpel_IsBlitzHeaderPostMatchLingering()
        and blitzMmrHeaderDismissPostMatchToken == blitzMmrHeaderPostMatchToken
    then
        if type(blitzMmrHeaderLingerHideAt) == "number" and blitzMmrHeaderLingerHideAt <= GetTime() then
            PvPScalpel_ResetBlitzHeaderRuntimeState()
            PvPScalpel_BlitzMmrHeaderRefresh()
            return
        end
        PvPScalpel_ClearBlitzHeaderVisuals()
        return
    end

    if PvPScalpel_IsBlitzHeaderLingering()
        and blitzMmrHeaderLingerReason ~= "postmatch"
        and blitzMmrHeaderDismissLingerToken == PvPScalpel_GetCurrentBlitzHeaderLingerToken()
    then
        if type(blitzMmrHeaderLingerHideAt) == "number" and blitzMmrHeaderLingerHideAt <= GetTime() then
            PvPScalpel_ResetBlitzHeaderRuntimeState()
            PvPScalpel_BlitzMmrHeaderRefresh()
            return
        end
        PvPScalpel_ClearBlitzHeaderVisuals()
        return
    end

    if PvPScalpel_IsBlitzLobbyScanDisplayed(lobbyScanSnapshot) and blitzMmrHeaderDismissScan == true then
        PvPScalpel_ClearBlitzHeaderVisuals()
        return
    end

    if not PvPScalpel_IsBlitzHeaderLingering() and blitzMmrHeaderDismissQueue == true
        and (queuedForBlitz or pendingResolution or blitzMmrHeaderAcceptedPopupVisible == true or queueState == "confirm")
    then
        PvPScalpel_ClearBlitzHeaderVisuals()
        return
    end

    if blitzMmrHeaderAcceptedPopupVisible == true then
        blitzMmrHeaderHasActiveQueue = true
        blitzMmrHeaderQueueState = "accepted"
        PvPScalpel_ClearBlitzPendingQueueResolution()
        if type(queueIndex) == "number" then
            if not previouslyHadQueue or (type(previousQueueIndex) == "number" and previousQueueIndex ~= queueIndex) then
                PvPScalpel_BeginBlitzHeaderQueueCycle(queueIndex)
                blitzMmrHeaderPopCount = math.max(1, blitzMmrHeaderPopCount)
                blitzMmrHeaderAwaitingPopResolution = true
            else
                blitzMmrHeaderQueueIndex = queueIndex
            end
        end

        local effectiveElapsedSeconds = nil
        if type(queueElapsedSeconds) == "number" and queueElapsedSeconds >= 0 then
            effectiveElapsedSeconds = queueElapsedSeconds
        elseif type(queueStartedAt) == "number" then
            effectiveElapsedSeconds = math.max(0, GetTime() - queueStartedAt)
        elseif type(blitzMmrHeaderQueueStartedAt) == "number" then
            effectiveElapsedSeconds = math.max(0, GetTime() - blitzMmrHeaderQueueStartedAt)
        end

        if type(effectiveElapsedSeconds) == "number" then
            if type(blitzMmrHeaderFrozenQueueSeconds) ~= "number" or effectiveElapsedSeconds > blitzMmrHeaderFrozenQueueSeconds then
                blitzMmrHeaderFrozenQueueSeconds = effectiveElapsedSeconds
            end
            blitzMmrHeaderQueueStartedAt = GetTime() - effectiveElapsedSeconds
        end
        blitzMmrHeaderQueueEstimatedSeconds = queueEstimatedSeconds

        local remainingSeconds = PvPScalpel_GetBlitzAcceptRemainingSeconds(blitzMmrHeaderQueueIndex)
        if PvPScalpel_IsPositiveNumber(remainingSeconds) then
            blitzMmrHeaderAcceptWindowStartRemainingSeconds = remainingSeconds
            blitzMmrHeaderAcceptWindowExpiresAt = GetTime() + remainingSeconds
            blitzMmrHeaderAcceptWindowLastSyncAt = GetTime()
        end

        PvPScalpel_ClearBlitzHeaderLingerState()
        PvPScalpel_UpdateBlitzMmrHeaderDisplay(latestBlitzSummary)
        return
    end

    if queuedForBlitz then
        local freshQueueCycle = ((not previouslyHadQueue) and pendingResolution ~= true)
            or ((type(previousQueueIndex) == "number" and previousQueueIndex ~= queueIndex) and pendingResolution ~= true)
        if freshQueueCycle then
            PvPScalpel_BeginBlitzHeaderQueueCycle(queueIndex)
            blitzMmrHeaderQueueEstimatedSeconds = queueEstimatedSeconds
            previousQueueState = "hidden"
            queueWasReady = false
        else
            blitzMmrHeaderHasActiveQueue = true
            blitzMmrHeaderQueueIndex = queueIndex
            blitzMmrHeaderQueueEstimatedSeconds = queueEstimatedSeconds
            PvPScalpel_ClearBlitzHeaderLingerState()
        end

        if (queueWasReady or pendingFromState == "accepted" or pendingFromState == "confirm") and queueState == "queued" then
            blitzMmrHeaderRequeueCount = blitzMmrHeaderRequeueCount + 1
            blitzMmrHeaderAwaitingPopResolution = false
            blitzMmrHeaderAcceptWindowStartRemainingSeconds = nil
            blitzMmrHeaderAcceptWindowExpiresAt = nil
            blitzMmrHeaderAcceptWindowLastSyncAt = nil
            PvPScalpel_ClearBlitzPendingQueueResolution()
        elseif pendingResolution and queueState == "confirm" then
            PvPScalpel_ClearBlitzPendingQueueResolution()
        elseif previousQueueState ~= "confirm" and previousQueueState ~= "accepted"
            and queueState == "confirm" and blitzMmrHeaderAwaitingPopResolution ~= true
        then
            blitzMmrHeaderPopCount = blitzMmrHeaderPopCount + 1
            blitzMmrHeaderAwaitingPopResolution = true
            PvPScalpel_ClearBlitzPendingQueueResolution()
        end

        local effectiveElapsedSeconds = nil
        if type(queueElapsedSeconds) == "number" and queueElapsedSeconds >= 0 then
            effectiveElapsedSeconds = queueElapsedSeconds
        elseif type(queueStartedAt) == "number" then
            effectiveElapsedSeconds = math.max(0, GetTime() - queueStartedAt)
        elseif type(blitzMmrHeaderQueueStartedAt) == "number" then
            effectiveElapsedSeconds = math.max(0, GetTime() - blitzMmrHeaderQueueStartedAt)
        end

        if queueState == "confirm" then
            if type(effectiveElapsedSeconds) == "number" then
                if type(blitzMmrHeaderFrozenQueueSeconds) ~= "number" or effectiveElapsedSeconds > blitzMmrHeaderFrozenQueueSeconds then
                    blitzMmrHeaderFrozenQueueSeconds = effectiveElapsedSeconds
                end
                blitzMmrHeaderQueueStartedAt = GetTime() - effectiveElapsedSeconds
            end

            local remainingSeconds = PvPScalpel_GetBlitzAcceptRemainingSeconds(queueIndex)
            if PvPScalpel_IsPositiveNumber(remainingSeconds) then
                blitzMmrHeaderAcceptWindowStartRemainingSeconds = remainingSeconds
                blitzMmrHeaderAcceptWindowExpiresAt = GetTime() + remainingSeconds
                blitzMmrHeaderAcceptWindowLastSyncAt = GetTime()
            end
            blitzMmrHeaderQueueState = "confirm"
        else
            if blitzMmrHeaderRequeueCount > 0 and type(blitzMmrHeaderFrozenQueueSeconds) == "number" then
                if type(effectiveElapsedSeconds) ~= "number" or effectiveElapsedSeconds < blitzMmrHeaderFrozenQueueSeconds then
                    effectiveElapsedSeconds = blitzMmrHeaderFrozenQueueSeconds
                end
            end
            blitzMmrHeaderQueueStartedAt = type(effectiveElapsedSeconds) == "number" and (GetTime() - effectiveElapsedSeconds) or queueStartedAt
            blitzMmrHeaderQueueEstimatedSeconds = queueEstimatedSeconds
            blitzMmrHeaderQueueState = "queued"
        end

        PvPScalpel_UpdateBlitzMmrHeaderDisplay(latestBlitzSummary)
        return
    end

    if previouslyHadQueue and pendingResolution ~= true then
        PvPScalpel_StartBlitzPendingQueueResolution(previousQueueState)
        PvPScalpel_UpdateBlitzMmrHeaderDisplay(latestBlitzSummary)
        return
    end

    if pendingResolution then
        if not pendingGraceExpired then
            PvPScalpel_UpdateBlitzMmrHeaderDisplay(latestBlitzSummary)
            return
        end

        if pendingFromState == "queued" then
            PvPScalpel_ClearBlitzPendingQueueResolution()
            PvPScalpel_StartBlitzHeaderLinger("canceled")
            PvPScalpel_UpdateBlitzMmrHeaderDisplay(latestBlitzSummary)
            return
        end

        if pendingFromState == "confirm" then
            PvPScalpel_ClearBlitzPendingQueueResolution()
            PvPScalpel_StartBlitzHeaderLinger("dodged")
            PvPScalpel_UpdateBlitzMmrHeaderDisplay(latestBlitzSummary)
            return
        end

        PvPScalpel_ResetBlitzHeaderRuntimeState()
        PvPScalpel_ClearBlitzHeaderVisuals()
        return
    end

    if PvPScalpel_IsBlitzHeaderLingering() then
        local remainingSeconds = blitzMmrHeaderLingerHideAt - GetTime()
        if remainingSeconds <= 0 then
            PvPScalpel_ResetBlitzHeaderRuntimeState()
            PvPScalpel_ClearBlitzHeaderVisuals()
            return
        end

        PvPScalpel_UpdateBlitzMmrHeaderDisplay(latestBlitzSummary)
        return
    end

    PvPScalpel_ResetBlitzHeaderRuntimeState()
    PvPScalpel_ClearBlitzHeaderVisuals()
end

function PvPScalpel_BlitzMmrHeaderHandleMatchSaved(match)
    PvPScalpel_UpdateBlitzMmrCacheFromMatch(match)
    local summary = PvPScalpel_BuildBlitzMmrSummary(match)
    local token = PvPScalpel_GetBlitzSummaryToken(summary)
    if type(summary) == "table" and type(token) == "string" and token ~= "" then
        blitzMmrHeaderPendingPostMatchSummary = summary
        blitzMmrHeaderPendingPostMatchToken = token
        if blitzMmrHeaderAwaitingPostMatchSummary == true and not PvPScalpel_IsLivePvpMatchActiveForHeader() then
            PvPScalpel_StartBlitzHeaderLinger("postmatch", summary, token)
        end
    end
    PvPScalpel_BlitzMmrHeaderRefresh()
end

PvPScalpel_ApplyBlitzHeaderLayout()

blitzMmrHeaderEventFrame:RegisterEvent("PLAYER_LOGIN")
blitzMmrHeaderEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
blitzMmrHeaderEventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
blitzMmrHeaderEventFrame:RegisterEvent("PVP_MATCH_ACTIVE")
blitzMmrHeaderEventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
blitzMmrHeaderEventFrame:RegisterEvent("PVP_ROLE_POPUP_SHOW")
blitzMmrHeaderEventFrame:RegisterEvent("PVP_ROLE_POPUP_HIDE")
blitzMmrHeaderEventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PVP_ROLE_POPUP_SHOW" then
        local readyCheckInfo = ...
        local queuedForBlitz, _, _, _, queueIndex = PvPScalpel_GetQueuedBlitzInfo()
        if not queuedForBlitz then
            queueIndex = blitzMmrHeaderQueueIndex
        end
        if type(queueIndex) == "number"
            and (blitzMmrHeaderHasActiveQueue ~= true or blitzMmrHeaderQueueIndex ~= queueIndex)
        then
            PvPScalpel_BeginBlitzHeaderQueueCycle(queueIndex)
        end

        blitzMmrHeaderHasActiveQueue = true
        blitzMmrHeaderQueueState = "accepted"
        blitzMmrHeaderAcceptedPopupVisible = true
        blitzMmrHeaderLatestReadyCheckInfo = readyCheckInfo

        if type(queueIndex) == "number" then
            blitzMmrHeaderQueueIndex = queueIndex
        end

        if blitzMmrHeaderAwaitingPopResolution ~= true then
            blitzMmrHeaderPopCount = blitzMmrHeaderPopCount + 1
        end
        blitzMmrHeaderAwaitingPopResolution = true

        local remainingSeconds = PvPScalpel_GetBlitzAcceptRemainingSeconds(blitzMmrHeaderQueueIndex)
        if PvPScalpel_IsPositiveNumber(remainingSeconds) then
            blitzMmrHeaderAcceptWindowStartRemainingSeconds = remainingSeconds
            blitzMmrHeaderAcceptWindowExpiresAt = GetTime() + remainingSeconds
            blitzMmrHeaderAcceptWindowLastSyncAt = GetTime()
        end
    elseif event == "PVP_ROLE_POPUP_HIDE" then
        local readyCheckInfo = ...
        blitzMmrHeaderAcceptedPopupVisible = false
        blitzMmrHeaderLatestReadyCheckInfo = readyCheckInfo
    end

    PvPScalpel_BlitzMmrHeaderRefresh()
end)

blitzMmrHeaderFrame:RegisterForDrag("LeftButton")
blitzMmrHeaderFrame:SetScript("OnDragStart", function(self)
    if not IsShiftKeyDown or not IsShiftKeyDown() then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    PvPScalpel_CloseBlitzHeaderContextMenu()
    self:StartMoving()
    blitzMmrHeaderDragging = true
end)

blitzMmrHeaderFrame:SetScript("OnDragStop", function(self)
    if blitzMmrHeaderDragging ~= true then
        return
    end
    self:StopMovingOrSizing()
    blitzMmrHeaderDragging = false
    blitzMmrHeaderSuppressNextClick = true
    PvPScalpel_SaveBlitzHeaderLayout()
    PvPScalpel_ShowBlitzHeaderTooltip()
end)

blitzMmrHeaderFrame:SetScript("OnEnter", function()
    PvPScalpel_ShowBlitzHeaderTooltip()
end)

blitzMmrHeaderFrame:SetScript("OnLeave", function()
    if GameTooltip and GameTooltip:GetOwner() == blitzMmrHeaderFrame then
        GameTooltip:Hide()
    end
end)

blitzMmrHeaderFrame:SetScript("OnHide", function()
    blitzMmrHeaderDragging = false
    PvPScalpel_CloseBlitzHeaderContextMenu()
    if GameTooltip and GameTooltip:GetOwner() == blitzMmrHeaderFrame then
        GameTooltip:Hide()
    end
end)

blitzMmrHeaderFrame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        PvPScalpel_OpenBlitzHeaderContextMenu()
        return
    end

    if button ~= "LeftButton" then
        return
    end

    PvPScalpel_CloseBlitzHeaderContextMenu()

    if blitzMmrHeaderSuppressNextClick == true then
        blitzMmrHeaderSuppressNextClick = false
        return
    end

    if IsShiftKeyDown and IsShiftKeyDown() then
        return
    end

    local lobbyScanSnapshot = PvPScalpel_GetBlitzLobbyScanSnapshotSafe()
    if PvPScalpel_IsBlitzLobbyScanCopyReady(lobbyScanSnapshot) then
        if type(PvPScalpel_OpenLobbyScanCopyDialog) == "function" then
            PvPScalpel_OpenLobbyScanCopyDialog(lobbyScanSnapshot.buffer)
        end
        return
    end
    if not PvPScalpel_IsBlitzHeaderLingering() then
        return
    end

    PvPScalpel_OpenBlitzRatedFinder()
    PvPScalpel_ResetBlitzHeaderRuntimeState()
    PvPScalpel_ClearBlitzHeaderVisuals()
end)

blitzMmrHeaderFrame:SetScript("OnUpdate", function(_, elapsed)
    if not blitzMmrHeaderFrame:IsShown() then
        return
    end

    blitzMmrHeaderUpdateElapsed = blitzMmrHeaderUpdateElapsed + elapsed
    local inviteStateActive = blitzMmrHeaderAcceptedPopupVisible == true or blitzMmrHeaderQueueState == "confirm"
    local updateThreshold = inviteStateActive and 0.02 or 0.1
    if blitzMmrHeaderUpdateElapsed < updateThreshold then
        return
    end
    blitzMmrHeaderUpdateElapsed = 0

    if PvPScalpel_IsBlitzHeaderLingering() then
        local remainingSeconds = math.max(0, blitzMmrHeaderLingerHideAt - GetTime())
        blitzMmrHeaderTimer:SetText(PvPScalpel_FormatQueueTimer(remainingSeconds))
        if remainingSeconds <= 0 then
            PvPScalpel_ResetBlitzHeaderRuntimeState()
            PvPScalpel_ClearBlitzHeaderVisuals()
        end
        return
    end

    local lobbyScanSnapshot = PvPScalpel_GetBlitzLobbyScanSnapshotSafe()
    if PvPScalpel_IsBlitzLobbyScanDisplayed(lobbyScanSnapshot) then
        local targetProgress = PvPScalpel_GetBlitzLobbyScanProgress(lobbyScanSnapshot)
        local scanState = type(lobbyScanSnapshot.scanState) == "string" and lobbyScanSnapshot.scanState or "LOADING"
        if type(blitzMmrHeaderScanDisplayedProgress) ~= "number" then
            blitzMmrHeaderScanDisplayedProgress = 0
        end

        local progressDelta = targetProgress - blitzMmrHeaderScanDisplayedProgress
        if math.abs(progressDelta) > 0 then
            local step = math.max(0.01, elapsed * 2.5)
            if progressDelta > 0 then
                blitzMmrHeaderScanDisplayedProgress = math.min(targetProgress, blitzMmrHeaderScanDisplayedProgress + step)
            else
                blitzMmrHeaderScanDisplayedProgress = math.max(targetProgress, blitzMmrHeaderScanDisplayedProgress - step)
            end
            PvPScalpel_ApplyBlitzLobbyScanProgressFill(scanState, blitzMmrHeaderScanDisplayedProgress)
        end
        return
    end

    if blitzMmrHeaderPendingQueueResolution == true then
        PvPScalpel_BlitzMmrHeaderRefresh()
        return
    end

    if inviteStateActive then
        local remainingSeconds, progress = PvPScalpel_GetBlitzInviteProgress()
        if type(remainingSeconds) == "number" then
            if blitzMmrHeaderAcceptedPopupVisible == true then
                blitzMmrHeaderTimer:SetText(PvPScalpel_FormatEnterTimerInline(remainingSeconds))
            else
                blitzMmrHeaderTimer:SetText(PvPScalpel_FormatAcceptTimerInline(remainingSeconds))
            end
        else
            if blitzMmrHeaderAcceptedPopupVisible == true then
                blitzMmrHeaderTimer:SetText(PvPScalpel_FormatEnterTimerInline(0))
            else
                blitzMmrHeaderTimer:SetText(PvPScalpel_FormatAcceptTimerInline(0))
            end
        end

        if blitzMmrHeaderAcceptedPopupVisible == true then
            if type(progress) == "number" then
                PvPScalpel_SetBlitzHeaderProgressFill(progress, 0.20, 0.62, 0.32, 0.28)
            else
                PvPScalpel_HideBlitzHeaderProgressFill()
            end
        elseif type(progress) == "number" then
            PvPScalpel_SetBlitzHeaderProgressFill(progress, 0.72, 0.48, 0.16, 0.30)
        else
            PvPScalpel_HideBlitzHeaderProgressFill()
        end
        return
    end

    if type(blitzMmrHeaderQueueStartedAt) ~= "number" then
        return
    end

    local queueElapsedSeconds = math.max(0, GetTime() - blitzMmrHeaderQueueStartedAt)
    blitzMmrHeaderTimer:SetText(PvPScalpel_FormatQueueTimer(queueElapsedSeconds))

    local queuedProgress = PvPScalpel_GetBlitzQueuedProgress(queueElapsedSeconds, blitzMmrHeaderQueueEstimatedSeconds)
    if type(queuedProgress) == "number" then
        PvPScalpel_SetBlitzHeaderQueuedStyleFill(queuedProgress)
    else
        PvPScalpel_HideBlitzHeaderProgressFill()
    end
end)
