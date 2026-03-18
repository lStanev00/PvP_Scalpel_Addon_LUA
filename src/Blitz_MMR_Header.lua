local blitzMmrHeaderFrame = CreateFrame("Frame", "PvPScalpelBlitzMmrHeader", UIParent)
blitzMmrHeaderFrame:SetFrameStrata("HIGH")
blitzMmrHeaderFrame:SetPoint("TOP", UIParent, "TOP", 0, -18)
blitzMmrHeaderFrame:SetSize(360, 48)
blitzMmrHeaderFrame:Hide()

local blitzMmrHeaderBackground = blitzMmrHeaderFrame:CreateTexture(nil, "BACKGROUND")
blitzMmrHeaderBackground:SetAllPoints()
blitzMmrHeaderBackground:SetColorTexture(0.03, 0.04, 0.05, 0.72)

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

local blitzMmrHeaderValue = blitzMmrHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
blitzMmrHeaderValue:SetPoint("BOTTOMLEFT", blitzMmrHeaderFrame, "BOTTOMLEFT", 12, 7)
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

local blitzMmrHeaderEventFrame = CreateFrame("Frame")

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

local function PvPScalpel_GetMostRecentCompletedMatch()
    if type(PvP_Scalpel_DB) ~= "table" then
        return nil
    end

    for i = #PvP_Scalpel_DB, 1, -1 do
        local match = PvP_Scalpel_DB[i]
        if type(match) == "table" then
            return match
        end
    end

    return nil
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

local function PvPScalpel_IsQueuedForBlitz()
    if type(GetMaxBattlefieldID) ~= "function" or type(GetBattlefieldStatus) ~= "function" then
        return false
    end

    local maxBattlefieldID = GetMaxBattlefieldID() or 0
    for i = 1, maxBattlefieldID do
        local status, _, _, _, _, queueType = GetBattlefieldStatus(i)
        if queueType == "RATEDSOLORBG" and (status == "queued" or status == "confirm") then
            return true
        end
    end

    return false
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

local function PvPScalpel_UpdateBlitzMmrHeaderDisplay(summary, queuedForBlitz)
    if type(summary) ~= "table" then
        blitzMmrHeaderLabel:SetText("")
        blitzMmrHeaderValue:SetText("")
        blitzMmrHeaderDelta:SetText("")
        blitzMmrHeaderStatusBackground:Hide()
        blitzMmrHeaderStatusText:Hide()
        blitzMmrHeaderFrame:Hide()
        return
    end

    blitzMmrHeaderLabel:SetText(queuedForBlitz and "BATTLEGROUND BLITZ" or "LATEST BLITZ")
    blitzMmrHeaderValue:SetText(PvPScalpel_FormatMmrValue(summary.currentMMR))
    blitzMmrHeaderSuffix:SetText("MMR")

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

    if queuedForBlitz then
        blitzMmrHeaderStatusBackground:Show()
        blitzMmrHeaderStatusText:Show()
    else
        blitzMmrHeaderStatusBackground:Hide()
        blitzMmrHeaderStatusText:Hide()
    end

    blitzMmrHeaderFrame:Show()
end

function PvPScalpel_BlitzMmrHeaderRefresh()
    if PvPScalpel_IsLivePvpMatchActiveForHeader() then
        PvPScalpel_UpdateBlitzMmrHeaderDisplay(nil, false)
        return
    end

    local queuedForBlitz = PvPScalpel_IsQueuedForBlitz()
    if not queuedForBlitz then
        PvPScalpel_UpdateBlitzMmrHeaderDisplay(nil, false)
        return
    end

    local latestBlitzMatch = PvPScalpel_GetMostRecentBlitzMatch()
    local latestBlitzSummary = PvPScalpel_BuildBlitzMmrSummary(latestBlitzMatch)
    if type(latestBlitzSummary) ~= "table" then
        PvPScalpel_UpdateBlitzMmrHeaderDisplay(nil, false)
        return
    end

    PvPScalpel_UpdateBlitzMmrHeaderDisplay(latestBlitzSummary, true)
end

function PvPScalpel_BlitzMmrHeaderHandleMatchSaved(match)
    PvPScalpel_BlitzMmrHeaderRefresh()
end

blitzMmrHeaderEventFrame:RegisterEvent("PLAYER_LOGIN")
blitzMmrHeaderEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
blitzMmrHeaderEventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
blitzMmrHeaderEventFrame:RegisterEvent("PVP_MATCH_ACTIVE")
blitzMmrHeaderEventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
blitzMmrHeaderEventFrame:SetScript("OnEvent", function()
    PvPScalpel_BlitzMmrHeaderRefresh()
end)
