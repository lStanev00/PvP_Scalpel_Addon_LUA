local KICKS_WINDOW_NAME = "Kicks-PvP Scalpel"
local KICK_USE_DEDUPE_WINDOW_SECONDS = 5.0

local recentKickUseBySpellID = {}
local lastObservedOwnerSuccessfulKicks = 0
local ownerPrintedKickTotal = 0

local function GetKickWindowNow()
    if type(GetTime) == "function" then
        return GetTime()
    end
    return 0
end

local function ResolveKickSpellName(spellID, fallbackName)
    if PvPScalpel_GetSpellNameByID and type(spellID) == "number" then
        local spellName = PvPScalpel_GetSpellNameByID(spellID)
        if type(spellName) == "string" and spellName ~= "" then
            return spellName
        end
    end
    if type(fallbackName) == "string" and fallbackName ~= "" then
        return fallbackName
    end
    if type(spellID) == "number" then
        return "Spell " .. tostring(spellID)
    end
    return "Unknown Spell"
end

local function WriteKickWindowMessage(message, r, g, b)
    local renderedMessage = tostring(message)
    if type(date) == "function" then
        renderedMessage = string.format("[%s] %s", tostring(date("%H:%M:%S")), renderedMessage)
    end
    if PvPScalpel_WriteNamedDebugChatMessage then
        return PvPScalpel_WriteNamedDebugChatMessage(KICKS_WINDOW_NAME, renderedMessage, r, g, b)
    end
    return false
end

function PvPScalpel_KicksWindowReset()
    recentKickUseBySpellID = {}
    lastObservedOwnerSuccessfulKicks = 0
    ownerPrintedKickTotal = 0
end

function PvPScalpel_KicksWindowWipe()
    PvPScalpel_KicksWindowReset()
    if PvPScalpel_ClearNamedDebugChatFrame then
        PvPScalpel_ClearNamedDebugChatFrame(KICKS_WINDOW_NAME)
    end
end

function PvPScalpel_KicksWindowLogKickUsed(spellID, fallbackName)
    if type(spellID) ~= "number" then
        return false
    end

    local now = GetKickWindowNow()
    local lastLoggedAt = recentKickUseBySpellID[spellID]
    if type(lastLoggedAt) == "number" and (now - lastLoggedAt) < KICK_USE_DEDUPE_WINDOW_SECONDS then
        return false
    end

    recentKickUseBySpellID[spellID] = now
    ownerPrintedKickTotal = ownerPrintedKickTotal + 1
    local spellName = ResolveKickSpellName(spellID, fallbackName)
    return WriteKickWindowMessage("Used kick: " .. tostring(spellName), 0.95, 0.82, 0.40)
end

function PvPScalpel_KicksWindowHandleOwnerSuccessTotalUpdate()
    if not PvPScalpel_DamageMeterGetInterruptTotalsForSource then
        return false
    end

    local ownerGUID = UnitGUID and UnitGUID("player") or nil
    if type(ownerGUID) ~= "string" or ownerGUID == "" then
        return false
    end

    local _, currentSucceeded = PvPScalpel_DamageMeterGetInterruptTotalsForSource(ownerGUID)
    if type(currentSucceeded) ~= "number" then
        return false
    end

    if currentSucceeded > lastObservedOwnerSuccessfulKicks then
        lastObservedOwnerSuccessfulKicks = currentSucceeded
        return WriteKickWindowMessage("Successful kicks total: " .. tostring(currentSucceeded), 0.45, 1.00, 0.45)
    end

    if currentSucceeded < lastObservedOwnerSuccessfulKicks then
        lastObservedOwnerSuccessfulKicks = currentSucceeded
    end

    return false
end

function PvPScalpel_KicksWindowGetOwnerPrintedKickTotal()
    return ownerPrintedKickTotal
end
