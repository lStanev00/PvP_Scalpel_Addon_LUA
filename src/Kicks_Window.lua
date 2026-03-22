local KICKS_WINDOW_NAME = "PvP Scalpel Debug"
local KICK_USE_DEDUPE_WINDOW_SECONDS = 5.0
local IMMEDIATE_KICK_SUCCESS_DEDUPE_WINDOW_SECONDS = 1.0
local immediateKickSuccessFrame = CreateFrame("Frame")
local immediateKickSuccessRegistered = false
local recentImmediateKickSuccessByKey = {}

local function DisableImmediateKickSuccessObserver()
    if immediateKickSuccessFrame and immediateKickSuccessRegistered then
        immediateKickSuccessFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        immediateKickSuccessRegistered = false
    end
end

local function EnsureKicksWindowRuntimeStore()
    if not PvPScalpel_EnsureCurrentMatchSessionStore then
        return nil
    end

    local store = PvPScalpel_EnsureCurrentMatchSessionStore()
    if type(store.kicksWindowRecentKickUseBySpellID) ~= "table" then
        store.kicksWindowRecentKickUseBySpellID = {}
    end
    if type(store.kicksWindowLastObservedOwnerSuccessfulKicks) ~= "number" then
        store.kicksWindowLastObservedOwnerSuccessfulKicks = 0
    end
    if type(store.kicksWindowOwnerPrintedKickTotal) ~= "number" then
        store.kicksWindowOwnerPrintedKickTotal = 0
    end
    return store
end

local function GetKickWindowNow()
    if type(GetTime) == "function" then
        return GetTime()
    end
    return 0
end

local function SanitizeKickWindowValue(value)
    local sanitized = value
    if scrubsecretvalues then
        local ok, safeValue = pcall(scrubsecretvalues, value)
        if ok then
            sanitized = safeValue
        end
    end
    if issecretvalue and sanitized ~= nil and issecretvalue(sanitized) then
        return nil
    end
    return sanitized
end

local function IsKnownKickSpellID(spellID)
    if type(spellID) ~= "number" then
        return false
    end
    if type(PvP_Scalpel_InteruptSpells) ~= "table" then
        return false
    end
    for i = 1, #PvP_Scalpel_InteruptSpells do
        if PvP_Scalpel_InteruptSpells[i] == spellID then
            return true
        end
    end
    return false
end

local function IsImmediateKickSuccessObserverAllowed()
    return PvPScalpel_Debug == true
        and PvPScalpel_IsLocalSpellCaptureActive
        and PvPScalpel_IsLocalSpellCaptureActive() == true
        and type(CombatLogGetCurrentEventInfo) == "function"
end

local function PruneImmediateKickSuccessDedupe()
    local now = GetKickWindowNow()
    for dedupeKey, observedAt in pairs(recentImmediateKickSuccessByKey) do
        if type(observedAt) ~= "number"
            or (now - observedAt) > IMMEDIATE_KICK_SUCCESS_DEDUPE_WINDOW_SECONDS then
            recentImmediateKickSuccessByKey[dedupeKey] = nil
        end
    end
end

local function BuildImmediateKickSuccessDedupeKey(sourceGUID, spellID, extraSpellID, timestamp)
    local coarseTimestamp = 0
    if type(timestamp) == "number" then
        coarseTimestamp = math.floor(timestamp * 10)
    end
    return table.concat({
        tostring(sourceGUID or ""),
        tostring(spellID or 0),
        tostring(extraSpellID or 0),
        tostring(coarseTimestamp),
    }, ":")
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
    if PvPScalpel_Debug ~= true then
        return false
    end

    local renderedMessage = tostring(message)
    if type(date) == "function" then
        renderedMessage = string.format("[%s] %s", tostring(date("%H:%M:%S")), renderedMessage)
    end
    if PvPScalpel_WriteNamedDebugChatMessage then
        return PvPScalpel_WriteNamedDebugChatMessage(KICKS_WINDOW_NAME, renderedMessage, r, g, b, "if_allowed")
    end
    return false
end

local function HandleImmediateKickSuccessEvent()
    if not IsImmediateKickSuccessObserverAllowed() then
        return
    end

    local timestamp, token, _, sourceGUID, _, _, _, _, _, _, _, spellID, spellName, _, extraSpellID, extraSpellName =
        CombatLogGetCurrentEventInfo()

    token = SanitizeKickWindowValue(token)
    if token ~= "SPELL_INTERRUPT" then
        return
    end

    sourceGUID = SanitizeKickWindowValue(sourceGUID)
    local ownerGUID = UnitGUID and UnitGUID("player") or nil
    if type(sourceGUID) ~= "string" or sourceGUID == "" or sourceGUID ~= ownerGUID then
        return
    end

    spellID = SanitizeKickWindowValue(spellID)
    if type(spellID) ~= "number" or not IsKnownKickSpellID(spellID) then
        return
    end

    extraSpellID = SanitizeKickWindowValue(extraSpellID)
    if type(extraSpellID) ~= "number" then
        extraSpellID = 0
    end

    timestamp = SanitizeKickWindowValue(timestamp)
    if type(timestamp) ~= "number" then
        timestamp = 0
    end

    local dedupeKey = BuildImmediateKickSuccessDedupeKey(sourceGUID, spellID, extraSpellID, timestamp)
    local now = GetKickWindowNow()
    PruneImmediateKickSuccessDedupe()
    local lastObservedAt = recentImmediateKickSuccessByKey[dedupeKey]
    if type(lastObservedAt) == "number"
        and (now - lastObservedAt) < IMMEDIATE_KICK_SUCCESS_DEDUPE_WINDOW_SECONDS then
        return
    end
    recentImmediateKickSuccessByKey[dedupeKey] = now

    spellName = SanitizeKickWindowValue(spellName)
    extraSpellName = SanitizeKickWindowValue(extraSpellName)
    local kickSpellName = ResolveKickSpellName(spellID, spellName)
    local message = "Successful kick: " .. tostring(kickSpellName)
    if type(extraSpellName) == "string" and extraSpellName ~= "" then
        message = message .. " interrupted " .. tostring(extraSpellName)
    elseif type(extraSpellID) == "number" and extraSpellID > 0 then
        message = message .. " interrupted spellID " .. tostring(extraSpellID)
    end

    WriteKickWindowMessage(message, 0.45, 1.00, 0.45)
end

if immediateKickSuccessFrame then
    immediateKickSuccessFrame:SetScript("OnEvent", function(_, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            HandleImmediateKickSuccessEvent()
        end
    end)
end

function PvPScalpel_KicksWindowSyncImmediateSuccessObserver()
    if not immediateKickSuccessFrame then
        return false
    end

    local shouldEnable = IsImmediateKickSuccessObserverAllowed()
    if shouldEnable then
        if not immediateKickSuccessRegistered then
            immediateKickSuccessFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            immediateKickSuccessRegistered = true
        end
        return true
    end

    DisableImmediateKickSuccessObserver()
    return false
end

function PvPScalpel_KicksWindowReset()
    local store = EnsureKicksWindowRuntimeStore()
    if not store then
        return
    end
    store.kicksWindowRecentKickUseBySpellID = {}
    store.kicksWindowLastObservedOwnerSuccessfulKicks = 0
    store.kicksWindowOwnerPrintedKickTotal = 0
    recentImmediateKickSuccessByKey = {}
end

function PvPScalpel_KicksWindowWipe()
    PvPScalpel_KicksWindowReset()
    DisableImmediateKickSuccessObserver()
    if PvPScalpel_ClearNamedDebugChatFrame then
        PvPScalpel_ClearNamedDebugChatFrame(KICKS_WINDOW_NAME)
    end
end

function PvPScalpel_KicksWindowLogKickUsed(spellID, fallbackName)
    if type(spellID) ~= "number" then
        return false
    end

    local store = EnsureKicksWindowRuntimeStore()
    if not store then
        return false
    end

    local now = GetKickWindowNow()
    local lastLoggedAt = store.kicksWindowRecentKickUseBySpellID[spellID]
    if type(lastLoggedAt) == "number" and (now - lastLoggedAt) < KICK_USE_DEDUPE_WINDOW_SECONDS then
        return false
    end

    store.kicksWindowRecentKickUseBySpellID[spellID] = now
    store.kicksWindowOwnerPrintedKickTotal = store.kicksWindowOwnerPrintedKickTotal + 1
    if PvPScalpel_KicksWindowSyncImmediateSuccessObserver then
        PvPScalpel_KicksWindowSyncImmediateSuccessObserver()
    end
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

    local store = EnsureKicksWindowRuntimeStore()
    if not store then
        return false
    end

    local _, currentSucceeded = PvPScalpel_DamageMeterGetInterruptTotalsForSource(ownerGUID)
    if type(currentSucceeded) ~= "number" then
        return false
    end

    if currentSucceeded > store.kicksWindowLastObservedOwnerSuccessfulKicks then
        store.kicksWindowLastObservedOwnerSuccessfulKicks = currentSucceeded
        return WriteKickWindowMessage("Successful kicks total: " .. tostring(currentSucceeded), 0.45, 1.00, 0.45)
    end

    if currentSucceeded < store.kicksWindowLastObservedOwnerSuccessfulKicks then
        store.kicksWindowLastObservedOwnerSuccessfulKicks = currentSucceeded
    end

    return false
end

function PvPScalpel_KicksWindowGetOwnerPrintedKickTotal()
    local store = EnsureKicksWindowRuntimeStore()
    if not store then
        return 0
    end
    return store.kicksWindowOwnerPrintedKickTotal or 0
end
