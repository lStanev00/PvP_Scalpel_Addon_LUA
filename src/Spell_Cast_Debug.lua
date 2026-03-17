-- NOTE [2026-03-16]:
-- The live visible-unit CC attribution heuristic is currently disabled.
-- Current state: it does not log reliably enough yet, so the code is kept
-- in place for later rework but is not enabled at runtime.

local debugInitFrame = CreateFrame("Frame")
local debugSpellFrame = CreateFrame("Frame")
local heuristicUnitFrame = CreateFrame("Frame")

local DEBUG_WINDOW_NAME = "PvP Scalpel Debug"
local LIVE_VISIBLE_UNIT_CC_ATTRIBUTION_ENABLED = false
local RESOLVED_CAST_TTL_SECONDS = 120
local LOC_CAST_CORRELATION_WINDOW_SECONDS = 1.0
local STOP_FINALIZE_GRACE_SECONDS = 0.20
local HEURISTIC_CC_CORRELATION_WINDOW_SECONDS = 1.0
local HEURISTIC_EVENT_TTL_SECONDS = 120
local MAX_ARENA_UNIT_TOKENS = 5

local debugCastByGuid = {}
local resolvedCastByGuid = {}
local recentResolvedCastHistory = {}
local recentLocHistory = {}
local activeLocByKey = {}
local activeCastGuid = nil
local RemoveCastEntry
local AppendLocToChat
local SafeGetSchoolString
local IsSpellCaptureSessionActive
local PruneResolvedHeuristicEvents
local RegisterDebugSpellEvents

local kickSpellLookup = {}
local kickSpellLookupCount = -1
local kickSpellLookupSource = nil
local heuristicLocWatcherFrames = {}
local targetSnapshotCache = nil
local spellTrackingRegistered = false
local activeSpellCaptureSession = nil
local heuristicRuntimeState = nil
local runtimeStateCache = {
    isMounted = nil,
    isFlying = nil,
    isAdvancedFlyableArea = nil,
    isFlyableArea = nil,
    isGliding = nil,
    canGlide = nil,
}
local movementStateCache = {
    isMoving = nil,
    lastStartedMovingAt = nil,
    lastStoppedMovingAt = nil,
}

local function GetMaxChatWindows()
    if Constants and Constants.ChatFrameConstants and type(Constants.ChatFrameConstants.MaxChatWindows) == "number" then
        return Constants.ChatFrameConstants.MaxChatWindows
    end
    if type(NUM_CHAT_WINDOWS) == "number" then
        return NUM_CHAT_WINDOWS
    end
    return 10
end

local function GetPlayerGuidSafe()
    if GetPlayerGuid then
        local ok, guid = pcall(GetPlayerGuid)
        if ok and type(guid) == "string" and guid ~= "" then
            return guid
        end
    end
    if UnitGUID then
        local ok, guid = pcall(UnitGUID, "player")
        if ok and type(guid) == "string" and guid ~= "" then
            return guid
        end
    end
    return nil
end

local function GetDebugNow()
    if GetTime then
        local ok, now = pcall(GetTime)
        if ok and type(now) == "number" then
            return now
        end
    end
    return 0
end

local function GetDebugEpoch()
    if time then
        local ok, now = pcall(time)
        if ok and type(now) == "number" then
            return now
        end
    end
    return nil
end

local function ScrubOptionalString(value)
    local scrubbedValue = value
    if scrubsecretvalues then
        local ok, safeValue = pcall(scrubsecretvalues, value)
        if ok then
            scrubbedValue = safeValue
        else
            scrubbedValue = nil
        end
    elseif issecretvalue and issecretvalue(value) then
        scrubbedValue = nil
    end

    if type(scrubbedValue) == "string" and scrubbedValue ~= "" then
        return scrubbedValue
    end
    return nil
end

local function ResetSessionCollections()
    activeSpellCaptureSession = {
        active = false,
        startedAt = nil,
        groupedHistory = {},
        locHistory = {},
        castKeyCounter = 0,
    }
end

local function ResetHeuristicRuntimeState()
    heuristicRuntimeState = {
        watchedUnits = {},
        nameplateUnits = {},
        pendingUserCc = {},
        resolvedHeuristicEvents = {},
        resolvedHeuristicKeys = {},
        heuristicCastKeyCounter = 0,
    }
end

local function EnsureHeuristicRuntimeState()
    if type(heuristicRuntimeState) ~= "table" then
        ResetHeuristicRuntimeState()
    end
    if type(heuristicRuntimeState.watchedUnits) ~= "table" then
        heuristicRuntimeState.watchedUnits = {}
    end
    if type(heuristicRuntimeState.nameplateUnits) ~= "table" then
        heuristicRuntimeState.nameplateUnits = {}
    end
    if type(heuristicRuntimeState.pendingUserCc) ~= "table" then
        heuristicRuntimeState.pendingUserCc = {}
    end
    if type(heuristicRuntimeState.resolvedHeuristicEvents) ~= "table" then
        heuristicRuntimeState.resolvedHeuristicEvents = {}
    end
    if type(heuristicRuntimeState.resolvedHeuristicKeys) ~= "table" then
        heuristicRuntimeState.resolvedHeuristicKeys = {}
    end
    if type(heuristicRuntimeState.heuristicCastKeyCounter) ~= "number" then
        heuristicRuntimeState.heuristicCastKeyCounter = 0
    end
    return heuristicRuntimeState
end

local function EnsureHeuristicHistory()
    PruneResolvedHeuristicEvents()
    return EnsureHeuristicRuntimeState().resolvedHeuristicEvents
end

local function EnsureSessionCollections()
    if type(activeSpellCaptureSession) ~= "table" then
        ResetSessionCollections()
    end
    if type(activeSpellCaptureSession.groupedHistory) ~= "table" then
        activeSpellCaptureSession.groupedHistory = {}
    end
    if type(activeSpellCaptureSession.locHistory) ~= "table" then
        activeSpellCaptureSession.locHistory = {}
    end
    if type(activeSpellCaptureSession.castKeyCounter) ~= "number" then
        activeSpellCaptureSession.castKeyCounter = 0
    end
    return activeSpellCaptureSession
end

local function EnsureKeptHistory()
    return EnsureSessionCollections().groupedHistory
end

local function EnsureFilteredHistory()
    return {}
end

local function EnsureLocHistory()
    return EnsureSessionCollections().locHistory
end

local function PushDebugHistory(entry)
    table.insert(EnsureKeptHistory(), entry)
end

local function PushFilteredDebugHistory(_entry)
end

local function PushLocDebugHistory(entry)
    table.insert(EnsureLocHistory(), entry)
end

local function NormalizeDebugHistory()
end

local function ShouldRunLiveHeuristicRuntime()
    return LIVE_VISIBLE_UNIT_CC_ATTRIBUTION_ENABLED == true
        and (PvPScalpel_Debug == true or IsSpellCaptureSessionActive())
end

IsSpellCaptureSessionActive = function()
    return type(activeSpellCaptureSession) == "table" and activeSpellCaptureSession.active == true
end

local function GetSpellCaptureSessionStart()
    local session = EnsureSessionCollections()
    if type(session.startedAt) == "number" then
        return session.startedAt
    end
    return nil
end

local function GetElapsedSessionCentiseconds(atTime)
    local sessionStart = GetSpellCaptureSessionStart()
    local observedAt = atTime
    if type(observedAt) ~= "number" then
        observedAt = GetDebugNow()
    end
    if type(sessionStart) ~= "number" or type(observedAt) ~= "number" then
        return -1
    end
    return math.max(0, math.floor(((observedAt - sessionStart) * 100) + 0.5))
end

local function GetCurrentRoundIndex()
    if type(soloShuffleState) == "table"
        and soloShuffleState.active == true
        and type(soloShuffleState.currentRoundIndex) == "number"
        and soloShuffleState.currentRoundIndex > 0 then
        return soloShuffleState.currentRoundIndex
    end
    return 0
end

local function BuildTargetSnapshot()
    if not (UnitExists and UnitExists("target")) then
        return {
            hasTarget = false,
            targetName = nil,
            disposition = "none",
            isPlayer = nil,
            canAttack = nil,
            isFriend = nil,
            reaction = nil,
        }
    end

    local targetName = nil
    if UnitName then
        local ok, rawTargetName = pcall(UnitName, "target")
        if ok then
            targetName = ScrubOptionalString(rawTargetName)
        end
    end

    local isPlayer = UnitIsPlayer and UnitIsPlayer("target") or nil
    local canAttack = UnitCanAttack and UnitCanAttack("player", "target") or nil
    local isFriend = UnitIsFriend and UnitIsFriend("player", "target") or nil
    local reaction = UnitReaction and UnitReaction("player", "target") or nil

    local disposition = "unknown"
    if canAttack == true then
        disposition = "hostile"
    elseif isFriend == true then
        disposition = "friendly"
    end

    return {
        hasTarget = true,
        targetName = targetName,
        disposition = disposition,
        isPlayer = isPlayer,
        canAttack = canAttack,
        isFriend = isFriend,
        reaction = reaction,
    }
end

local function RefreshTargetSnapshot()
    targetSnapshotCache = BuildTargetSnapshot()
end

local function AssignTargetSnapshot(castEntry, snapshot, targetName)
    if type(castEntry) ~= "table" then
        return
    end

    local safeTargetName = ScrubOptionalString(targetName)
    if safeTargetName then
        castEntry.targetName = safeTargetName
    end

    if type(snapshot) ~= "table" then
        return
    end

    if type(castEntry.targetName) ~= "string" or castEntry.targetName == "" then
        castEntry.targetName = snapshot.targetName
    end
    if type(castEntry.targetDisposition) ~= "string" then
        castEntry.targetDisposition = snapshot.disposition or "none"
    end
    if castEntry.targetIsPlayer == nil then
        castEntry.targetIsPlayer = snapshot.isPlayer
    end
    if castEntry.targetCanAttack == nil then
        castEntry.targetCanAttack = snapshot.canAttack
    end
    if castEntry.targetIsFriend == nil then
        castEntry.targetIsFriend = snapshot.isFriend
    end
    if castEntry.targetReaction == nil then
        castEntry.targetReaction = snapshot.reaction
    end
end

local function SafeUnitExists(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" or not UnitExists then
        return false
    end

    local ok, exists = pcall(UnitExists, unitToken)
    return ok and exists == true
end

local function SafeUnitGUID(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" or not UnitGUID then
        return nil
    end

    local ok, guid = pcall(UnitGUID, unitToken)
    if not ok then
        return nil
    end
    return ScrubOptionalString(guid)
end

local function SafeUnitName(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" or not UnitName then
        return nil
    end

    local ok, name = pcall(UnitName, unitToken)
    if not ok then
        return nil
    end
    return ScrubOptionalString(name)
end

local function SafeUnitIsUnit(leftUnit, rightUnit)
    if type(leftUnit) ~= "string" or leftUnit == "" then
        return false
    end
    if type(rightUnit) ~= "string" or rightUnit == "" or not UnitIsUnit then
        return false
    end

    local ok, matches = pcall(UnitIsUnit, leftUnit, rightUnit)
    return ok and matches == true
end

local function SafeGetLossOfControlDataByUnit(unitToken, index)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end
    if type(index) ~= "number" or index <= 0 then
        return nil
    end
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataByUnit) then
        return nil
    end

    local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlDataByUnit, unitToken, index)
    if not ok or type(data) ~= "table" then
        return nil
    end

    data.displayText = ScrubOptionalString(data.displayText) or data.displayText
    data.lockoutSchoolText = SafeGetSchoolString(data.lockoutSchool)
    return data
end

local function SafeGetLossOfControlDataCountByUnit(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return 0
    end
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCountByUnit) then
        return 0
    end

    local ok, count = pcall(C_LossOfControl.GetActiveLossOfControlDataCountByUnit, unitToken)
    if ok and type(count) == "number" and count > 0 then
        return count
    end
    return 0
end

local function SafeGetAuraDataByAuraInstanceID(unitToken, auraInstanceID)
    if type(unitToken) ~= "string" or unitToken == "" then
        return nil
    end
    if type(auraInstanceID) ~= "number" or auraInstanceID <= 0 then
        return nil
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
        return nil
    end

    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unitToken, auraInstanceID)
    if not ok or type(auraData) ~= "table" then
        return nil
    end

    auraData.name = ScrubOptionalString(auraData.name) or auraData.name
    auraData.sourceUnit = ScrubOptionalString(auraData.sourceUnit) or auraData.sourceUnit
    return auraData
end

local function GetAuraObservedSpellID(auraData)
    if type(auraData) ~= "table" then
        return nil
    end
    if type(auraData.spellId) == "number" then
        return auraData.spellId
    end
    if type(auraData.spellID) == "number" then
        return auraData.spellID
    end
    return nil
end

local function GetAuraObservedSourceUnit(auraData)
    if type(auraData) ~= "table" then
        return nil
    end
    return ScrubOptionalString(auraData.sourceUnit)
end

local function ShouldAcceptLocalOwnerSourceUnit(sourceUnit)
    if type(sourceUnit) ~= "string" or sourceUnit == "" then
        return false
    end

    return SafeUnitIsUnit("player", sourceUnit)
        or SafeUnitIsUnit("pet", sourceUnit)
        or SafeUnitIsUnit("vehicle", sourceUnit)
end

local function AddWatchedUnitToken(unitToken, kind)
    local safeUnitToken = ScrubOptionalString(unitToken) or unitToken
    if type(safeUnitToken) ~= "string" or safeUnitToken == "" then
        return
    end

    local state = EnsureHeuristicRuntimeState()
    state.watchedUnits[safeUnitToken] = kind or true
    if string.sub(safeUnitToken, 1, 9) == "nameplate" then
        state.nameplateUnits[safeUnitToken] = true
    end
end

local function RemoveWatchedUnitToken(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return
    end

    local state = EnsureHeuristicRuntimeState()
    state.watchedUnits[unitToken] = nil
    state.nameplateUnits[unitToken] = nil
end

local function RefreshStaticWatchedUnits()
    local state = EnsureHeuristicRuntimeState()
    state.watchedUnits = {}

    AddWatchedUnitToken("player", "self")
    AddWatchedUnitToken("target", "target")
    AddWatchedUnitToken("focus", "focus")

    for i = 1, MAX_ARENA_UNIT_TOKENS do
        AddWatchedUnitToken("arena" .. tostring(i), "arena")
    end

    for unitToken in pairs(state.nameplateUnits) do
        AddWatchedUnitToken(unitToken, "nameplate")
    end
end

local function IsWatchedUnitToken(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return false
    end
    return EnsureHeuristicRuntimeState().watchedUnits[unitToken] ~= nil
end

local function OnHeuristicLocWatcherEvent(self, event, unitToken, ...)
    if ShouldRunLiveHeuristicRuntime() ~= true then
        return
    end

    local watchedUnitToken = ScrubOptionalString(unitToken) or self.unitToken
    if type(watchedUnitToken) ~= "string" or watchedUnitToken == "" then
        return
    end

    if event == "LOSS_OF_CONTROL_ADDED" then
        local effectIndex = ...
        ScanWatchedUnitLossOfControl(watchedUnitToken, event, effectIndex)
        return
    end

    if event == "LOSS_OF_CONTROL_UPDATE" then
        ScanWatchedUnitLossOfControl(watchedUnitToken, event)
    end
end

local function RegisterHeuristicLocWatcher(unitToken)
    local safeUnitToken = ScrubOptionalString(unitToken) or unitToken
    if type(safeUnitToken) ~= "string" or safeUnitToken == "" then
        return
    end

    local watcherFrame = heuristicLocWatcherFrames[safeUnitToken]
    if not watcherFrame then
        watcherFrame = CreateFrame("Frame")
        watcherFrame:SetScript("OnEvent", OnHeuristicLocWatcherEvent)
        heuristicLocWatcherFrames[safeUnitToken] = watcherFrame
    end

    watcherFrame.unitToken = safeUnitToken
    watcherFrame:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", safeUnitToken)
    watcherFrame:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", safeUnitToken)
end

local function UnregisterHeuristicLocWatcher(unitToken)
    if type(unitToken) ~= "string" or unitToken == "" then
        return
    end

    local watcherFrame = heuristicLocWatcherFrames[unitToken]
    if not watcherFrame then
        return
    end

    watcherFrame:UnregisterAllEvents()
    watcherFrame:SetScript("OnEvent", nil)
    watcherFrame.unitToken = nil
    heuristicLocWatcherFrames[unitToken] = nil
end

local function RegisterStaticHeuristicLocWatchers()
    RegisterHeuristicLocWatcher("player")
    RegisterHeuristicLocWatcher("target")
    RegisterHeuristicLocWatcher("focus")

    for i = 1, MAX_ARENA_UNIT_TOKENS do
        RegisterHeuristicLocWatcher("arena" .. tostring(i))
    end
end

local function UnregisterAllHeuristicLocWatchers()
    for unitToken in pairs(heuristicLocWatcherFrames) do
        UnregisterHeuristicLocWatcher(unitToken)
    end
end

local function PrunePendingUserCc()
    local state = EnsureHeuristicRuntimeState()
    local now = GetDebugNow()
    local nextEntries = {}

    for i = 1, #state.pendingUserCc do
        local entry = state.pendingUserCc[i]
        if type(entry) == "table"
            and type(entry.expiresAt) == "number"
            and now <= entry.expiresAt then
            nextEntries[#nextEntries + 1] = entry
        end
    end

    state.pendingUserCc = nextEntries
end

local function HasPendingUserCc()
    PrunePendingUserCc()
    return #EnsureHeuristicRuntimeState().pendingUserCc > 0
end

PruneResolvedHeuristicEvents = function()
    local state = EnsureHeuristicRuntimeState()
    local now = GetDebugNow()
    local nextEntries = {}
    local nextKeys = {}

    for i = 1, #state.resolvedHeuristicEvents do
        local entry = state.resolvedHeuristicEvents[i]
        if type(entry) == "table"
            and type(entry.observedAt) == "number"
            and (now - entry.observedAt) <= HEURISTIC_EVENT_TTL_SECONDS then
            nextEntries[#nextEntries + 1] = entry
            if type(entry.dedupeKey) == "string" and entry.dedupeKey ~= "" then
                nextKeys[entry.dedupeKey] = entry.observedAt
            end
        end
    end

    state.resolvedHeuristicEvents = nextEntries
    state.resolvedHeuristicKeys = nextKeys
end

local function FindDebugChatFrame()
    if not GetChatWindowInfo then
        return nil
    end

    local maxChatWindows = GetMaxChatWindows()
    for i = 1, maxChatWindows do
        local ok, name = pcall(GetChatWindowInfo, i)
        if ok and name == DEBUG_WINDOW_NAME then
            return _G["ChatFrame" .. i]
        end
    end
    return nil
end

local function CloseDebugChatFrame()
    local chatFrame = FindDebugChatFrame()
    if chatFrame and FCF_Close then
        pcall(FCF_Close, chatFrame)
    end
end

local function PrepareDebugChatFrame(chatFrame)
    if not chatFrame then
        return nil
    end

    if chatFrame.Clear then
        chatFrame:Clear()
    end
    if chatFrame.RemoveAllMessageGroups then
        chatFrame:RemoveAllMessageGroups()
    end
    if chatFrame.RemoveAllChannels then
        chatFrame:RemoveAllChannels()
    end
    if chatFrame.ReceiveAllPrivateMessages then
        chatFrame:ReceiveAllPrivateMessages()
    end

    local chatTab = _G[chatFrame:GetName() .. "Tab"]
    if FCF_CheckShowChatFrame then
        pcall(FCF_CheckShowChatFrame, chatFrame)
        if chatTab then
            pcall(FCF_CheckShowChatFrame, chatTab)
        end
    end
    if SetChatWindowShown then
        pcall(SetChatWindowShown, chatFrame:GetID(), true)
    end
    if FCF_DockFrame and FCFDock_GetChatFrames and GENERAL_CHAT_DOCK and not chatFrame.isDocked then
        local dockedFrames = FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)
        local dockIndex = 1
        if type(dockedFrames) == "table" then
            dockIndex = #dockedFrames + 1
        end
        pcall(FCF_DockFrame, chatFrame, dockIndex, true)
    end
    if FCF_SelectDockFrame and chatFrame.isDocked then
        pcall(FCF_SelectDockFrame, chatFrame)
    elseif FCFDock_SelectWindow and GENERAL_CHAT_DOCK and chatFrame.isDocked then
        pcall(FCFDock_SelectWindow, GENERAL_CHAT_DOCK, chatFrame)
    end
    if FCF_FadeInChatFrame then
        pcall(FCF_FadeInChatFrame, chatFrame)
    end

    return chatFrame
end

local function OpenDebugChatFrame()
    local chatFrame = FindDebugChatFrame()
    if not chatFrame and FCF_OpenNewWindow then
        local ok, openedFrame = pcall(FCF_OpenNewWindow, DEBUG_WINDOW_NAME, true)
        if ok then
            chatFrame = openedFrame
        end
    end
    return PrepareDebugChatFrame(chatFrame)
end

local function FormatInterruptibleValue(value)
    if value == true then
        return "yes"
    end
    if value == false then
        return "no"
    end
    return "unknown"
end

local function FormatDebugNumber(value)
    if type(value) ~= "number" then
        return "-"
    end
    return string.format("%.1f", value)
end

local function ResolveSpellName(spellID, fallbackName)
    local spellName = PvPScalpel_GetSpellNameByID and PvPScalpel_GetSpellNameByID(spellID) or nil
    if type(spellName) == "string" and spellName ~= "" then
        return spellName
    end
    if type(fallbackName) == "string" and fallbackName ~= "" then
        return fallbackName
    end
    if type(spellID) == "number" then
        return "Spell " .. tostring(spellID)
    end
    return "Unknown Spell"
end

local function IsPlayerGuid(guid)
    return type(guid) == "string" and string.sub(guid, 1, 7) == "Player-"
end

local function RenderAttemptChatLine(entry)
    local targetText = ""
    if type(entry.targetName) == "string" and entry.targetName ~= "" then
        targetText = " on " .. entry.targetName
    end

    return string.format(
        "[%s] Attempted %s%s | spellID=%s castGUID=%s castID=%s type=%s interruptible=%s",
        tostring(entry.attemptLoggedAtText or entry.loggedAtText or date("%H:%M:%S")),
        tostring(entry.spellName or "Unknown Spell"),
        targetText,
        tostring(entry.spellID or "-"),
        tostring(entry.castGUID or "-"),
        tostring(entry.castID or "-"),
        tostring(entry.castType or "unknown"),
        FormatInterruptibleValue(entry.interruptible)
    )
end

local function NormalizeSentenceText(value)
    if type(value) ~= "string" then
        return nil
    end

    local text = string.gsub(value, "_", " ")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then
        return nil
    end

    return string.lower(text)
end

local function ContainsSentenceText(text, fragment)
    return type(text) == "string" and string.find(text, fragment, 1, true) ~= nil
end

local function GetLocFallbackDescription(entry)
    local displayText = NormalizeSentenceText(entry and entry.displayText)
    if displayText then
        return displayText
    end

    local locTypeText = NormalizeSentenceText(entry and entry.locType)
    if locTypeText then
        return locTypeText
    end

    return nil
end

local function GetLocEffectWord(entry)
    local locTypeText = NormalizeSentenceText(entry and entry.locType)
    local displayText = NormalizeSentenceText(entry and entry.displayText)

    if locTypeText == "school interrupt" then
        return "kicked"
    end
    if ContainsSentenceText(locTypeText, "stun") or ContainsSentenceText(displayText, "stun") then
        return "stunned"
    end
    if ContainsSentenceText(locTypeText, "silence") or ContainsSentenceText(displayText, "silence") then
        return "silenced"
    end
    if ContainsSentenceText(locTypeText, "disorient") or ContainsSentenceText(displayText, "disorient") then
        return "disoriented"
    end
    if ContainsSentenceText(locTypeText, "incap") or ContainsSentenceText(displayText, "incap") then
        return "incapacitated"
    end
    if ContainsSentenceText(locTypeText, "disarm") or ContainsSentenceText(displayText, "disarm") then
        return "disarmed"
    end
    if ContainsSentenceText(locTypeText, "root") or ContainsSentenceText(displayText, "root") then
        return "rooted"
    end
    if ContainsSentenceText(locTypeText, "fear") or ContainsSentenceText(displayText, "fear") then
        return "feared"
    end

    return nil
end

local function BuildLocSentence(entry)
    local effectWord = GetLocEffectWord(entry)
    if effectWord then
        return "You were " .. effectWord .. "."
    end

    local fallback = GetLocFallbackDescription(entry)
    if fallback then
        return "You were affected by " .. fallback .. "."
    end

    return "You were affected by an unknown effect."
end

local function GetCastLocReason(entry)
    if type(entry) ~= "table" then
        return nil
    end

    if entry.locType == "SCHOOL_INTERRUPT" then
        return "school-locked"
    end

    local effectWord = GetLocEffectWord(entry)
    if effectWord and effectWord ~= "kicked" then
        return effectWord
    end

    local fallback = GetLocFallbackDescription(entry)
    if fallback and fallback ~= "school interrupt" then
        return "affected by " .. fallback
    end

    return nil
end

local function AddTailPart(parts, key, value)
    if value == nil then
        return
    end

    if type(value) == "string" and value == "" then
        return
    end

    parts[#parts + 1] = key .. "=" .. tostring(value)
end

local function BuildOutcomeChatTail(entry, includeLoc)
    local tailParts = {}

    AddTailPart(tailParts, "outcome", entry and entry.outcome or "-")
    AddTailPart(tailParts, "castGUID", entry and entry.castGUID or "-")

    if entry and entry.castID ~= nil and entry.castID ~= "" then
        AddTailPart(tailParts, "castID", entry.castID)
    end
    if entry and type(entry.interruptedBy) == "string" and entry.interruptedBy ~= "" then
        AddTailPart(tailParts, "by", entry.interruptedBy)
    end
    if includeLoc == true and entry and type(entry.locType) == "string" and entry.locType ~= "" then
        AddTailPart(tailParts, "loc", entry.locType)
    end
    if entry and type(entry.lockoutSchoolText) == "string" and entry.lockoutSchoolText ~= "" then
        AddTailPart(tailParts, "school", entry.lockoutSchoolText)
    end

    return table.concat(tailParts, " ")
end

local function RenderOutcomeChatLine(entry)
    local subject = tostring(entry.spellName or "Unknown Spell")
    local summary = "Your spell " .. subject .. " finished."
    local includeLoc = false

    if entry.outcome == "success" then
        summary = "Your spell " .. subject .. " succeeded."
    elseif entry.outcome == "not_success" then
        summary = "Your spell " .. subject .. " failed."
    elseif entry.outcome == "interrupted" then
        local locReason = GetCastLocReason(entry)
        if type(locReason) == "string" and locReason ~= "" then
            summary = "Your spell " .. subject .. " failed because you were " .. locReason .. "."
            includeLoc = type(entry.locType) == "string" and entry.locType ~= ""
        else
            summary = "Your spell " .. subject .. " was interrupted."
        end
    elseif entry.outcome == "kicked" then
        summary = "Your spell " .. subject .. " was kicked."
    elseif entry.outcome == "cancelled" then
        summary = "You fake casted " .. subject .. "."
    end

    local tail = BuildOutcomeChatTail(entry, includeLoc)

    return string.format(
        "[%s] %s | %s",
        tostring(entry.outcomeLoggedAtText or entry.loggedAtText or date("%H:%M:%S")),
        summary,
        tail
    )
end

local function RenderFilteredChatLine(entry)
    return string.format(
        "[%s] [filtered] %s (%s)",
        tostring(entry.loggedAtText or date("%H:%M:%S")),
        tostring(entry.spellName or "Unknown Spell"),
        tostring(entry.spellID or "-")
    )
end

local function RenderLocChatLine(entry)
    local tailParts = {}
    AddTailPart(tailParts, "loc", entry.locType or entry.displayText or "-")
    if entry.spellID ~= nil then
        AddTailPart(tailParts, "spellID", entry.spellID)
    end
    if type(entry.lockoutSchoolText) == "string" and entry.lockoutSchoolText ~= "" then
        AddTailPart(tailParts, "school", entry.lockoutSchoolText)
    end
    if type(entry.linkedCastGUID) == "string" and entry.linkedCastGUID ~= "" then
        AddTailPart(tailParts, "castGUID", entry.linkedCastGUID)
    end
    if type(entry.linkedInterruptedBy) == "string" and entry.linkedInterruptedBy ~= "" then
        AddTailPart(tailParts, "by", entry.linkedInterruptedBy)
    end

    return string.format(
        "[%s] %s | %s",
        tostring(entry.loggedAtText or date("%H:%M:%S")),
        BuildLocSentence(entry),
        table.concat(tailParts, " ")
    )
end

local function GetAttemptColor()
    return 0.70, 0.90, 1.00
end

local function GetOutcomeColor(entry)
    if not entry then
        return 1.0, 1.0, 1.0
    end
    if entry.outcome == "success" then
        return 0.45, 1.00, 0.45
    end
    if entry.outcome == "not_success" then
        return 1.00, 0.82, 0.45
    end
    if entry.outcome == "kicked" then
        return 1.00, 0.30, 0.30
    end
    if entry.outcome == "interrupted" then
        return 1.00, 0.55, 0.55
    end
    if entry.outcome == "cancelled" then
        return 1.00, 0.68, 0.30
    end
    return 1.00, 1.00, 1.00
end

local function GetFilteredColor()
    return 0.95, 0.82, 0.40
end

local function GetLocColor(entry)
    if entry and entry.locType == "SCHOOL_INTERRUPT" then
        return 1.00, 0.20, 0.20
    end
    return 0.98, 0.60, 0.20
end

local function GetHeuristicColor(entry)
    if type(entry) == "table" and entry.subkind == "user_gives_cc" then
        return 0.60, 0.95, 1.00
    end
    return 1.00, 0.82, 0.45
end

local function ReplayHistoryRecord(chatFrame, entry)
    if not chatFrame or type(entry) ~= "table" then
        return
    end

    if entry.kind == "heuristic" then
        local r, g, b = GetHeuristicColor(entry)
        chatFrame:AddMessage(tostring(entry.message or ""), r, g, b)
        return
    end

    if entry.kind == "attempt" then
        local renderedAttempt = RenderAttemptChatLine(entry)
        local r, g, b = GetAttemptColor()
        chatFrame:AddMessage(renderedAttempt, r, g, b)
        return
    end

    if entry.kind == "outcome" then
        local renderedOutcome = RenderOutcomeChatLine(entry)
        local r, g, b = GetOutcomeColor(entry)
        chatFrame:AddMessage(renderedOutcome, r, g, b)
        return
    end

    if entry.filterReason ~= nil and entry.outcome == nil then
        local renderedFiltered = RenderFilteredChatLine(entry)
        local r, g, b = GetFilteredColor()
        chatFrame:AddMessage(renderedFiltered, r, g, b)
        return
    end

    if entry.locType ~= nil and entry.outcome == nil then
        local renderedLoc = RenderLocChatLine(entry)
        local r, g, b = GetLocColor(entry)
        chatFrame:AddMessage(renderedLoc, r, g, b)
        return
    end

    local renderedAttempt = RenderAttemptChatLine(entry)
    if renderedAttempt then
        local ar, ag, ab = GetAttemptColor()
        chatFrame:AddMessage(renderedAttempt, ar, ag, ab)
    end

    local renderedOutcome = RenderOutcomeChatLine(entry)
    if renderedOutcome then
        local orr, org, orb = GetOutcomeColor(entry)
        chatFrame:AddMessage(renderedOutcome, orr, org, orb)
    end
end

local function ReplayDebugHistory(chatFrame)
    local mergedHistory = {}
    local sequence = 0
    local history = EnsureKeptHistory()
    local filteredHistory = EnsureFilteredHistory()
    local locHistory = EnsureLocHistory()
    local heuristicHistory = EnsureHeuristicHistory()

    for i = 1, #history do
        sequence = sequence + 1
        mergedHistory[#mergedHistory + 1] = {
            entry = history[i],
            sequence = sequence,
        }
    end

    for i = 1, #filteredHistory do
        sequence = sequence + 1
        mergedHistory[#mergedHistory + 1] = {
            entry = filteredHistory[i],
            sequence = sequence,
        }
    end

    for i = 1, #locHistory do
        sequence = sequence + 1
        mergedHistory[#mergedHistory + 1] = {
            entry = locHistory[i],
            sequence = sequence,
        }
    end

    for i = 1, #heuristicHistory do
        sequence = sequence + 1
        mergedHistory[#mergedHistory + 1] = {
            entry = heuristicHistory[i],
            sequence = sequence,
        }
    end

    table.sort(mergedHistory, function(left, right)
        local leftEpoch = left.entry and left.entry.loggedAtEpoch or nil
        local rightEpoch = right.entry and right.entry.loggedAtEpoch or nil

        if type(leftEpoch) == "number" and type(rightEpoch) == "number" and leftEpoch ~= rightEpoch then
            return leftEpoch < rightEpoch
        end

        return left.sequence < right.sequence
    end)

    for i = 1, #mergedHistory do
        ReplayHistoryRecord(chatFrame, mergedHistory[i].entry)
    end
end

local function ShowDebugHistory()
    local chatFrame = OpenDebugChatFrame()
    if not chatFrame then
        return
    end
    ReplayDebugHistory(chatFrame)
end

function PvPScalpel_DebugWriteMessage(message, r, g, b)
    if PvPScalpel_Debug ~= true then
        return false
    end
    local chatFrame = FindDebugChatFrame()
    if not chatFrame or not chatFrame.AddMessage then
        return false
    end
    chatFrame:AddMessage(tostring(message), r or 1.0, g or 1.0, b or 1.0)
    return true
end

local function AppendAttemptToChat(castEntry)
    if PvPScalpel_Debug ~= true then
        return
    end
    local chatFrame = FindDebugChatFrame()
    if not chatFrame or not chatFrame.AddMessage then
        return
    end
    local rendered = RenderAttemptChatLine(castEntry)
    if not rendered then
        return
    end
    local r, g, b = GetAttemptColor()
    chatFrame:AddMessage(rendered, r, g, b)
end

local function AppendOutcomeToChat(castEntry)
    if PvPScalpel_Debug ~= true then
        return
    end
    local chatFrame = FindDebugChatFrame()
    if not chatFrame or not chatFrame.AddMessage then
        return
    end
    local rendered = RenderOutcomeChatLine(castEntry)
    if not rendered then
        return
    end
    local r, g, b = GetOutcomeColor(castEntry)
    chatFrame:AddMessage(rendered, r, g, b)
end

local function AppendFilteredToChat(filteredEntry)
    if PvPScalpel_Debug ~= true then
        return
    end
    local chatFrame = FindDebugChatFrame()
    if not chatFrame or not chatFrame.AddMessage then
        return
    end
    local rendered = RenderFilteredChatLine(filteredEntry)
    if not rendered then
        return
    end
    local r, g, b = GetFilteredColor()
    chatFrame:AddMessage(rendered, r, g, b)
end

AppendLocToChat = function(locEntry)
    if PvPScalpel_Debug ~= true then
        return
    end
    local chatFrame = FindDebugChatFrame()
    if not chatFrame or not chatFrame.AddMessage then
        return
    end
    local rendered = RenderLocChatLine(locEntry)
    if not rendered then
        return
    end
    local r, g, b = GetLocColor(locEntry)
    chatFrame:AddMessage(rendered, r, g, b)
end

local function AppendHeuristicEntryToChat(entry)
    if PvPScalpel_Debug ~= true then
        return
    end
    local chatFrame = FindDebugChatFrame()
    if not chatFrame or not chatFrame.AddMessage then
        return
    end
    local r, g, b = GetHeuristicColor(entry)
    chatFrame:AddMessage(tostring(entry.message or ""), r, g, b)
end

function PvPScalpel_DebugSetEnabled(enabled)
    PvPScalpel_Debug = enabled == true
    if PvPScalpel_Debug then
        ShowDebugHistory()
    else
        CloseDebugChatFrame()
    end
end

function RecordResolvedHeuristicEntry(subkind, dedupeKey, message)
    if not ShouldRunLiveHeuristicRuntime() then
        return
    end

    PruneResolvedHeuristicEvents()

    local state = EnsureHeuristicRuntimeState()
    if type(dedupeKey) == "string" and dedupeKey ~= "" and state.resolvedHeuristicKeys[dedupeKey] ~= nil then
        return
    end

    local entry = {
        kind = "heuristic",
        subkind = subkind,
        dedupeKey = dedupeKey,
        message = message,
        observedAt = GetDebugNow(),
        loggedAtText = date("%H:%M:%S"),
        loggedAtEpoch = GetDebugEpoch(),
    }

    state.resolvedHeuristicEvents[#state.resolvedHeuristicEvents + 1] = entry
    if type(dedupeKey) == "string" and dedupeKey ~= "" then
        state.resolvedHeuristicKeys[dedupeKey] = entry.observedAt
    end
    AppendHeuristicEntryToChat(entry)
end

function NextHeuristicCastKey()
    local state = EnsureHeuristicRuntimeState()
    state.heuristicCastKeyCounter = state.heuristicCastKeyCounter + 1
    return state.heuristicCastKeyCounter
end

function MaybeArmPendingUserCc(castEntry)
    if not ShouldRunLiveHeuristicRuntime() then
        return
    end
    if type(castEntry) ~= "table" or castEntry.outcome ~= "success" then
        return
    end
    if type(castEntry.spellID) ~= "number" then
        return
    end
    if castEntry.shouldKeep ~= true then
        return
    end

    local combatSignals = castEntry.combatSignals or nil
    if type(combatSignals) ~= "table" or combatSignals.isSpellCrowdControl ~= true then
        return
    end

    local resolvedAt = castEntry.resolveLoggedAtSeconds or GetDebugNow()
    local state = EnsureHeuristicRuntimeState()
    PrunePendingUserCc()
    state.pendingUserCc[#state.pendingUserCc + 1] = {
        castKey = type(castEntry.castKey) == "number" and castEntry.castKey or NextHeuristicCastKey(),
        castGUID = castEntry.castGUID,
        spellID = castEntry.spellID,
        spellName = castEntry.spellName,
        resolveTime = resolvedAt,
        targetName = castEntry.targetName,
        targetDisposition = castEntry.targetDisposition,
        targetIsPlayer = castEntry.targetIsPlayer,
        targetCanAttack = castEntry.targetCanAttack,
        targetIsFriend = castEntry.targetIsFriend,
        targetReaction = castEntry.targetReaction,
        expiresAt = resolvedAt + HEURISTIC_CC_CORRELATION_WINDOW_SECONDS,
    }
end

function GetObservedUnitLabel(unitToken)
    return SafeUnitName(unitToken) or unitToken or "Unknown Unit"
end

function FindBestPendingUserCc(spellID, unitToken, observedAt)
    if type(spellID) ~= "number" then
        return nil, nil
    end

    PrunePendingUserCc()

    local unitName = SafeUnitName(unitToken)
    local bestIndex = nil
    local bestCandidate = nil
    local bestExactTargetMatch = false
    local bestDelta = math.huge
    local bestCastKey = -1

    for i = 1, #EnsureHeuristicRuntimeState().pendingUserCc do
        local candidate = EnsureHeuristicRuntimeState().pendingUserCc[i]
        if type(candidate) == "table" and candidate.spellID == spellID then
            local resolveTime = candidate.resolveTime or 0
            local delta = math.abs((observedAt or GetDebugNow()) - resolveTime)
            if delta <= HEURISTIC_CC_CORRELATION_WINDOW_SECONDS then
                local exactTargetMatch = type(candidate.targetName) == "string"
                    and candidate.targetName ~= ""
                    and type(unitName) == "string"
                    and unitName ~= ""
                    and candidate.targetName == unitName
                local castKey = type(candidate.castKey) == "number" and candidate.castKey or -1
                if bestIndex == nil
                    or (exactTargetMatch and not bestExactTargetMatch)
                    or (exactTargetMatch == bestExactTargetMatch and delta < bestDelta)
                    or (exactTargetMatch == bestExactTargetMatch and delta == bestDelta and castKey > bestCastKey) then
                    bestIndex = i
                    bestCandidate = candidate
                    bestExactTargetMatch = exactTargetMatch
                    bestDelta = delta
                    bestCastKey = castKey
                end
            end
        end
    end

    return bestIndex, bestCandidate
end

function ResolveUserGivesCcFromAura(unitToken, auraData, observedVia)
    if not HasPendingUserCc() then
        return false
    end
    if type(unitToken) ~= "string" or unitToken == "" or unitToken == "player" then
        return false
    end
    if type(auraData) ~= "table" then
        return false
    end

    local sourceUnit = GetAuraObservedSourceUnit(auraData)
    if ShouldAcceptLocalOwnerSourceUnit(sourceUnit) ~= true then
        return false
    end

    local auraSpellID = GetAuraObservedSpellID(auraData)
    if type(auraSpellID) ~= "number" then
        return false
    end

    local observedAt = GetDebugNow()
    local pendingIndex, pendingCandidate = FindBestPendingUserCc(auraSpellID, unitToken, observedAt)
    if not pendingIndex or type(pendingCandidate) ~= "table" then
        return false
    end

    local unitGuid = SafeUnitGUID(unitToken)
    local dedupeKey = table.concat({
        "give",
        tostring(pendingCandidate.castKey or 0),
        tostring(unitGuid or unitToken or "-"),
        tostring(auraSpellID),
    }, "|")

    local message = string.format(
        "Your CC %s likely landed on %s. | conf=strong_visible_unit token=%s guid=%s via=%s",
        tostring(pendingCandidate.spellName or ResolveSpellName(pendingCandidate.spellID)),
        tostring(GetObservedUnitLabel(unitToken)),
        tostring(unitToken),
        tostring(unitGuid or "-"),
        tostring(observedVia or "aura")
    )

    table.remove(EnsureHeuristicRuntimeState().pendingUserCc, pendingIndex)
    RecordResolvedHeuristicEntry("user_gives_cc", dedupeKey, message)
    return true
end

local function FindMatchingPlayerLocDataForAura(auraData)
    if type(auraData) ~= "table" then
        return nil
    end

    local expectedAuraInstanceID = type(auraData.auraInstanceID) == "number" and auraData.auraInstanceID or 0
    local expectedSpellID = GetAuraObservedSpellID(auraData)
    local count = SafeGetLossOfControlDataCount()

    for index = 1, count do
        local locData = SafeGetLossOfControlData(index)
        if type(locData) == "table" then
            if expectedAuraInstanceID > 0 and locData.auraInstanceID == expectedAuraInstanceID then
                return locData
            end
            if type(expectedSpellID) == "number" and locData.spellID == expectedSpellID then
                return locData
            end
        end
    end

    return nil
end

function RecordUnattributedUserTakesCc(locData, observedVia)
    if type(locData) ~= "table" then
        return
    end

    local auraInstanceID = type(locData.auraInstanceID) == "number" and locData.auraInstanceID or 0
    local dedupeKey = table.concat({
        "take-unattributed",
        tostring(auraInstanceID),
        tostring(locData.spellID or "-"),
        tostring(locData.locType or "-"),
    }, "|")

    local message = string.format(
        "%s | conf=unattributed via=%s",
        BuildLocSentence(locData),
        tostring(observedVia or "aura")
    )

    RecordResolvedHeuristicEntry("user_takes_cc", dedupeKey, message)
end

function ResolveUserTakesCcFromAura(unitToken, locData, auraData, observedVia)
    if type(unitToken) ~= "string" or unitToken ~= "player" then
        return false
    end
    if type(locData) ~= "table" or type(auraData) ~= "table" then
        return false
    end

    local sourceUnit = GetAuraObservedSourceUnit(auraData)
    if type(sourceUnit) ~= "string" or sourceUnit == "" then
        return false
    end

    local sourceGuid = SafeUnitGUID(sourceUnit)
    if type(sourceGuid) ~= "string" or sourceGuid == "" then
        return false
    end

    local auraInstanceID = type(locData.auraInstanceID) == "number" and locData.auraInstanceID or 0
    local dedupeKey = table.concat({
        "take",
        tostring(auraInstanceID),
        tostring(locData.spellID or "-"),
        tostring(sourceGuid),
        tostring(locData.locType or "-"),
    }, "|")

    local message = string.format(
        "%s | byGuid=%s token=%s conf=strong_visible_unit via=%s",
        BuildLocSentence(locData),
        tostring(sourceGuid),
        tostring(sourceUnit),
        tostring(observedVia or "aura")
    )

    RecordResolvedHeuristicEntry("user_takes_cc", dedupeKey, message)
    return true
end

function HandleHeuristicAuraObservation(unitToken, auraData, observedVia)
    if type(auraData) ~= "table" then
        return
    end

    ResolveUserGivesCcFromAura(unitToken, auraData, observedVia)
    if unitToken == "player" then
        local locData = FindMatchingPlayerLocDataForAura(auraData)
        if locData then
            if not ResolveUserTakesCcFromAura(unitToken, locData, auraData, observedVia) then
                RecordUnattributedUserTakesCc(locData, observedVia)
            end
        end
    end
end

function HandleHeuristicLossOfControlObservation(unitToken, locData, observedVia)
    if type(unitToken) ~= "string" or unitToken == "" then
        return
    end
    if type(locData) ~= "table" then
        return
    end

    local auraInstanceID = locData.auraInstanceID
    if type(auraInstanceID) ~= "number" or auraInstanceID <= 0 then
        return
    end

    local auraData = SafeGetAuraDataByAuraInstanceID(unitToken, auraInstanceID)
    if type(auraData) ~= "table" then
        if unitToken == "player" then
            RecordUnattributedUserTakesCc(locData, observedVia)
        end
        return
    end

    ResolveUserGivesCcFromAura(unitToken, auraData, observedVia)
    if unitToken == "player" and not ResolveUserTakesCcFromAura(unitToken, locData, auraData, observedVia) then
        RecordUnattributedUserTakesCc(locData, observedVia)
    end
end

function ScanWatchedUnitLossOfControl(unitToken, sourceEvent, effectIndex)
    if type(unitToken) ~= "string" or unitToken == "" then
        return
    end
    if IsWatchedUnitToken(unitToken) ~= true or SafeUnitExists(unitToken) ~= true then
        return
    end

    if type(effectIndex) == "number" and effectIndex > 0 then
        local locData = SafeGetLossOfControlDataByUnit(unitToken, effectIndex)
        if locData then
            HandleHeuristicLossOfControlObservation(unitToken, locData, sourceEvent)
        end
        return
    end

    local count = SafeGetLossOfControlDataCountByUnit(unitToken)
    for index = 1, count do
        local locData = SafeGetLossOfControlDataByUnit(unitToken, index)
        if locData then
            HandleHeuristicLossOfControlObservation(unitToken, locData, sourceEvent)
        end
    end
end

function HandleHeuristicUnitAura(unitToken, updateInfo)
    if type(unitToken) ~= "string" or unitToken == "" then
        return
    end
    if IsWatchedUnitToken(unitToken) ~= true or SafeUnitExists(unitToken) ~= true then
        return
    end

    if type(updateInfo) == "table" and type(updateInfo.addedAuras) == "table" then
        for i = 1, #updateInfo.addedAuras do
            HandleHeuristicAuraObservation(unitToken, updateInfo.addedAuras[i], "aura")
        end
    end

    if type(updateInfo) == "table" and type(updateInfo.updatedAuraInstanceIDs) == "table" then
        for i = 1, #updateInfo.updatedAuraInstanceIDs do
            local auraInstanceID = updateInfo.updatedAuraInstanceIDs[i]
            local auraData = SafeGetAuraDataByAuraInstanceID(unitToken, auraInstanceID)
            if auraData then
                HandleHeuristicAuraObservation(unitToken, auraData, "aura")
            end
        end
    end
end

function HandleHeuristicPlayerTargetChanged()
    RefreshTargetSnapshot()
    if ShouldRunLiveHeuristicRuntime() and HasPendingUserCc() then
        ScanWatchedUnitLossOfControl("target", "target")
    end
end

function HandleHeuristicPlayerFocusChanged()
    if ShouldRunLiveHeuristicRuntime() and HasPendingUserCc() then
        ScanWatchedUnitLossOfControl("focus", "focus")
    end
end

function HandleHeuristicNameplateAdded(unitToken)
    AddWatchedUnitToken(unitToken, "nameplate")
    RegisterHeuristicLocWatcher(unitToken)
    if ShouldRunLiveHeuristicRuntime() and HasPendingUserCc() then
        ScanWatchedUnitLossOfControl(unitToken, "nameplate")
    end
end

function HandleHeuristicNameplateRemoved(unitToken)
    RemoveWatchedUnitToken(unitToken)
    UnregisterHeuristicLocWatcher(unitToken)
end

function ResetHeuristicRuntimeForWorld()
    UnregisterAllHeuristicLocWatchers()
    ResetHeuristicRuntimeState()
    RefreshStaticWatchedUnits()
    if spellTrackingRegistered then
        RegisterStaticHeuristicLocWatchers()
    end
end

local function IsRealCastGUID(castGUID)
    if not castGUID then
        return true
    end
    if string.sub(castGUID, 1, 7) == "Cast-2-" then
        return false
    end
    if string.sub(castGUID, 1, 7) == "Cast-3-" then
        return true
    end
    if string.sub(castGUID, 1, 7) == "Cast-4-" then
        return true
    end
    if string.sub(castGUID, 1, 8) == "Cast-15-" then
        return true
    end
    return true
end

local function CleanupResolvedCastCache()
    local now = GetDebugNow()
    if type(now) ~= "number" then
        return
    end
    for castGUID, timestamp in pairs(resolvedCastByGuid) do
        if type(timestamp) ~= "number" or (now - timestamp) > RESOLVED_CAST_TTL_SECONDS then
            resolvedCastByGuid[castGUID] = nil
        end
    end
end

local function IsResolvedCast(castGUID)
    return castGUID and resolvedCastByGuid[castGUID] ~= nil
end

local function MarkResolvedCast(castGUID)
    if not castGUID then
        return
    end
    resolvedCastByGuid[castGUID] = GetDebugNow()
end

local function SafeUnitCastingInfo()
    if not UnitCastingInfo then
        return nil
    end
    local ok, name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill, castID, notInterruptible, spellID =
        pcall(UnitCastingInfo, "player")
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end
    return {
        name = name,
        displayName = displayName,
        textureID = textureID,
        startTimeMs = startTimeMs,
        endTimeMs = endTimeMs,
        isTradeskill = isTradeskill,
        castID = castID,
        notInterruptible = notInterruptible,
        spellID = spellID,
    }
end

local function SafeUnitChannelInfo()
    if not UnitChannelInfo then
        return nil
    end
    local ok, name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill, notInterruptible, spellID, isEmpowered, numEmpowerStages =
        pcall(UnitChannelInfo, "player")
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end
    return {
        name = name,
        displayName = displayName,
        textureID = textureID,
        startTimeMs = startTimeMs,
        endTimeMs = endTimeMs,
        isTradeskill = isTradeskill,
        notInterruptible = notInterruptible,
        spellID = spellID,
        isEmpowered = isEmpowered,
        numEmpowerStages = numEmpowerStages,
    }
end

local function SafeIsPlayerMoving()
    if type(IsPlayerMoving) ~= "function" then
        return nil
    end

    local ok, isMoving = pcall(IsPlayerMoving)
    if ok and type(isMoving) == "boolean" then
        return isMoving
    end
    return nil
end

SafeGetSchoolString = function(lockoutSchool)
    if type(lockoutSchool) ~= "number" or not (C_Spell and C_Spell.GetSchoolString) then
        return nil
    end

    local ok, schoolText = pcall(C_Spell.GetSchoolString, lockoutSchool)
    if ok and type(schoolText) == "string" and schoolText ~= "" then
        return schoolText
    end
    return nil
end

local function SafeGetLossOfControlData(index)
    if type(index) ~= "number" or not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlData) then
        return nil
    end

    local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlData, index)
    if not ok or type(data) ~= "table" then
        return nil
    end

    data.displayText = ScrubOptionalString(data.displayText) or data.displayText
    data.lockoutSchoolText = SafeGetSchoolString(data.lockoutSchool)
    return data
end

local function SafeGetLossOfControlDataCount()
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount) then
        return 0
    end

    local ok, count = pcall(C_LossOfControl.GetActiveLossOfControlDataCount)
    if ok and type(count) == "number" and count > 0 then
        return count
    end
    return 0
end

local function RefreshKickSpellLookup()
    local source = nil
    local sourceCount = 0
    if type(PvP_Scalpel_InteruptSpells) == "table" then
        source = PvP_Scalpel_InteruptSpells
        sourceCount = #PvP_Scalpel_InteruptSpells
    end

    if source == kickSpellLookupSource and sourceCount == kickSpellLookupCount then
        return source
    end

    kickSpellLookup = {}
    kickSpellLookupSource = source
    kickSpellLookupCount = sourceCount

    if not source then
        return nil
    end

    for i = 1, sourceCount do
        local spellID = source[i]
        if type(spellID) == "number" then
            kickSpellLookup[spellID] = true
        end
    end

    return source
end

local function IsKickBypassSpellID(spellID)
    if type(spellID) ~= "number" then
        return false
    end

    local source = RefreshKickSpellLookup()
    if kickSpellLookup[spellID] == true then
        return true
    end

    if not source then
        return false
    end

    for i = 1, #source do
        local candidate = source[i]
        if candidate == spellID then
            kickSpellLookup[spellID] = true
            return true
        end
    end

    return false
end

local function SafeBooleanCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        return nil
    end
    if type(result) == "boolean" then
        return result
    end
    return nil
end

local function SafeUnitBooleanCall(fn, unit)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, unit)
    if not ok then
        return nil
    end
    if type(result) == "boolean" then
        return result
    end
    return nil
end

local function SafeGlidingInfo()
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then
        return nil, nil
    end

    local ok, isGliding, canGlide = pcall(C_PlayerInfo.GetGlidingInfo)
    if not ok then
        return nil, nil
    end

    if type(isGliding) ~= "boolean" then
        isGliding = nil
    end
    if type(canGlide) ~= "boolean" then
        canGlide = nil
    end

    return isGliding, canGlide
end

local function RefreshRuntimeStateCache()
    runtimeStateCache.isMounted = SafeBooleanCall(IsMounted)
    runtimeStateCache.isFlying = SafeUnitBooleanCall(IsFlying, "player")
    runtimeStateCache.isAdvancedFlyableArea = SafeBooleanCall(IsAdvancedFlyableArea)
    runtimeStateCache.isFlyableArea = SafeBooleanCall(IsFlyableArea)

    local isGliding, canGlide = SafeGlidingInfo()
    runtimeStateCache.isGliding = isGliding
    runtimeStateCache.canGlide = canGlide
end

local function RefreshMovementStateCache()
    movementStateCache.isMoving = SafeIsPlayerMoving()
end

local function BuildRuntimeStateSnapshot()
    RefreshRuntimeStateCache()

    return {
        isMounted = runtimeStateCache.isMounted,
        isFlying = runtimeStateCache.isFlying,
        isAdvancedFlyableArea = runtimeStateCache.isAdvancedFlyableArea,
        isFlyableArea = runtimeStateCache.isFlyableArea,
        isGliding = runtimeStateCache.isGliding,
        canGlide = runtimeStateCache.canGlide,
    }
end

local function SafeMountID(spellID)
    if type(spellID) ~= "number" or not (C_MountJournal and C_MountJournal.GetMountFromSpell) then
        return nil
    end

    local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
    if ok and type(mountID) == "number" then
        return mountID
    end
    return nil
end

local function SafeTradeSkillLink(spellID)
    if type(spellID) ~= "number" or not (C_Spell and C_Spell.GetSpellTradeSkillLink) then
        return nil
    end

    local ok, spellLink = pcall(C_Spell.GetSpellTradeSkillLink, spellID)
    if ok and type(spellLink) == "string" and spellLink ~= "" then
        return spellLink
    end
    return nil
end

local function GetSpellBookContext(spellID)
    local context = {
        isInSpellBook = false,
        slotIndex = nil,
        bank = nil,
        itemInfo = nil,
        isPassive = nil,
        isUsable = nil,
        isHelpful = nil,
        isHarmful = nil,
    }

    if type(spellID) ~= "number" or not C_SpellBook then
        return context
    end

    if C_SpellBook.FindSpellBookSlotForSpell then
        local ok, slotIndex, bank = pcall(C_SpellBook.FindSpellBookSlotForSpell, spellID, true, true, false, true)
        if ok and type(slotIndex) == "number" and slotIndex > 0 and bank ~= nil then
            context.isInSpellBook = true
            context.slotIndex = slotIndex
            context.bank = bank
        end
    end

    if not context.isInSpellBook and C_SpellBook.IsSpellInSpellBook then
        local isInSpellBook = SafeBooleanCall(C_SpellBook.IsSpellInSpellBook, spellID)
        if isInSpellBook == true then
            context.isInSpellBook = true
        end
    end

    if not context.slotIndex or context.bank == nil then
        return context
    end

    if C_SpellBook.GetSpellBookItemInfo then
        local ok, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, context.slotIndex, context.bank)
        if ok and type(itemInfo) == "table" then
            context.itemInfo = itemInfo
        end
    end

    if C_SpellBook.IsSpellBookItemPassive then
        context.isPassive = SafeBooleanCall(C_SpellBook.IsSpellBookItemPassive, context.slotIndex, context.bank)
    end

    if C_SpellBook.IsSpellBookItemHelpful then
        context.isHelpful = SafeBooleanCall(C_SpellBook.IsSpellBookItemHelpful, context.slotIndex, context.bank)
    end

    if C_SpellBook.IsSpellBookItemHarmful then
        context.isHarmful = SafeBooleanCall(C_SpellBook.IsSpellBookItemHarmful, context.slotIndex, context.bank)
    end

    if C_SpellBook.IsSpellBookItemUsable then
        local ok, isUsable = pcall(C_SpellBook.IsSpellBookItemUsable, context.slotIndex, context.bank)
        if ok and type(isUsable) == "boolean" then
            context.isUsable = isUsable
        end
    end

    return context
end

local function GetCombatSignals(spellID)
    local signals = {
        isSpellHarmful = nil,
        isSpellHelpful = nil,
        isSpellCrowdControl = nil,
        isSpellImportant = nil,
        isExternalDefensive = nil,
        isSelfBuff = nil,
    }

    if type(spellID) ~= "number" or not C_Spell then
        return signals
    end

    signals.isSpellHarmful = SafeBooleanCall(C_Spell.IsSpellHarmful, spellID)
    signals.isSpellHelpful = SafeBooleanCall(C_Spell.IsSpellHelpful, spellID)
    signals.isSpellCrowdControl = SafeBooleanCall(C_Spell.IsSpellCrowdControl, spellID)
    signals.isSpellImportant = SafeBooleanCall(C_Spell.IsSpellImportant, spellID)
    signals.isExternalDefensive = SafeBooleanCall(C_Spell.IsExternalDefensive, spellID)
    signals.isSelfBuff = SafeBooleanCall(C_Spell.IsSelfBuff, spellID)

    return signals
end

local function HasCombatPositiveSignal(spellBookContext, combatSignals)
    if spellBookContext and (spellBookContext.isHelpful == true or spellBookContext.isHarmful == true) then
        return true
    end

    if not combatSignals then
        return false
    end

    return combatSignals.isSpellHarmful == true
        or combatSignals.isSpellHelpful == true
        or combatSignals.isSpellCrowdControl == true
        or combatSignals.isSpellImportant == true
        or combatSignals.isExternalDefensive == true
        or combatSignals.isSelfBuff == true
end

local function HasHighConfidenceCombatSignal(combatSignals)
    if type(combatSignals) ~= "table" then
        return false
    end

    return combatSignals.isSpellHarmful == true
        or combatSignals.isSpellCrowdControl == true
        or combatSignals.isSpellImportant == true
        or combatSignals.isExternalDefensive == true
end

local function IsMountActionRuntimeState(runtimeState)
    if type(runtimeState) ~= "table" then
        return false
    end

    return runtimeState.isMounted == true
        or runtimeState.isGliding == true
        or runtimeState.canGlide == true
end

local function LacksStartLikeLifecycle(castEntry)
    if type(castEntry) ~= "table" then
        return true
    end

    return castEntry.sawStart ~= true
        and castEntry.sawChannelStart ~= true
        and castEntry.sawEmpowerStart ~= true
end

local function CombineDebugNotes(left, right)
    if type(left) == "string" and left ~= "" and type(right) == "string" and right ~= "" then
        if string.find(left, right, 1, true) then
            return left
        end
        return left .. " " .. right
    end
    if type(left) == "string" and left ~= "" then
        return left
    end
    if type(right) == "string" and right ~= "" then
        return right
    end
    return nil
end

local function EvaluateCombatSpellFilter(castEntry)
    local decision = {
        keep = false,
        wasKeptByKickBypass = false,
        filterReason = nil,
        note = nil,
    }

    if not castEntry or type(castEntry.spellID) ~= "number" then
        return decision
    end

    local spellID = castEntry.spellID

    if IsKickBypassSpellID(spellID) then
        decision.keep = true
        decision.wasKeptByKickBypass = true
        return decision
    end

    if SafeMountID(spellID) ~= nil then
        decision.filterReason = "mount_spell"
        decision.note = "Filtered mount summon spell."
        return decision
    end

    if SafeTradeSkillLink(spellID) ~= nil then
        decision.filterReason = "trade_skill_spell"
        decision.note = "Filtered profession or trade-skill spell."
        return decision
    end

    if C_Spell then
        if SafeBooleanCall(C_Spell.IsConsumableSpell, spellID) == true then
            decision.filterReason = "consumable_spell"
            decision.note = "Filtered consumable spell."
            return decision
        end
        if SafeBooleanCall(C_Spell.IsSpellPassive, spellID) == true then
            decision.filterReason = "passive_spell"
            decision.note = "Filtered passive spell."
            return decision
        end
        if SafeBooleanCall(C_Spell.IsAutoAttackSpell, spellID) == true then
            decision.filterReason = "auto_attack_spell"
            decision.note = "Filtered auto-attack spell."
            return decision
        end
        if SafeBooleanCall(C_Spell.IsAutoRepeatSpell, spellID) == true then
            decision.filterReason = "auto_repeat_spell"
            decision.note = "Filtered auto-repeat spell."
            return decision
        end
    end

    local spellBookContext = GetSpellBookContext(spellID)
    castEntry.spellbookContext = spellBookContext
    if spellBookContext.isPassive == true then
        decision.filterReason = "spellbook_passive"
        decision.note = "Filtered passive spellbook entry."
        return decision
    end

    local combatSignals = GetCombatSignals(spellID)
    castEntry.combatSignals = combatSignals
    local isCombatPositive = HasCombatPositiveSignal(spellBookContext, combatSignals)
    local hasHighConfidenceCombatSignal = HasHighConfidenceCombatSignal(combatSignals)

    if LacksStartLikeLifecycle(castEntry) and IsMountActionRuntimeState(castEntry.runtimeState) then
        decision.filterReason = "mount_action_runtime"
        decision.note = "Filtered terminal no-start cast during mounted or gliding state."
        return decision
    end

    if LacksStartLikeLifecycle(castEntry)
        and castEntry.sawSent ~= true
        and spellBookContext.isInSpellBook ~= true
        and hasHighConfidenceCombatSignal ~= true then
        decision.filterReason = "system_like_no_sent_no_start"
        decision.note = "Filtered no-start and no-sent cast with no spellbook backing and no high-confidence combat signals."
        return decision
    end

    if isCombatPositive then
        decision.keep = true
        return decision
    end

    if castEntry.isSucceededOnlyInstant == true and spellBookContext.isInSpellBook ~= true then
        decision.filterReason = "ambiguous_succeeded_only_instant"
        decision.note = "Filtered SUCCEEDED-only instant with no spellbook or combat-positive signals."
        return decision
    end

    decision.filterReason = "default_non_combat"
    decision.note = "Filtered spell with no strong combat-positive evidence."
    return decision
end

local function EnsureCastEntry(castGUID, spellID)
    local entry = debugCastByGuid[castGUID]
    if not entry then
        local session = EnsureSessionCollections()
        session.castKeyCounter = session.castKeyCounter + 1
        entry = {
            castKey = session.castKeyCounter,
            roundIndex = GetCurrentRoundIndex(),
            castGUID = castGUID,
            spellID = spellID,
            spellName = ResolveSpellName(spellID),
            castType = nil,
            targetName = nil,
            targetDisposition = nil,
            targetIsPlayer = nil,
            targetCanAttack = nil,
            targetIsFriend = nil,
            targetReaction = nil,
            interruptible = nil,
            castID = nil,
            attemptSourceEvent = nil,
            attemptLoggedAtText = nil,
            attemptLoggedAtSeconds = nil,
            outcomeSourceEvent = nil,
            outcomeLoggedAtText = nil,
            resolveLoggedAtSeconds = nil,
            interruptedBy = nil,
            linkedLocEntry = nil,
            outcome = nil,
            note = nil,
            filterReason = nil,
            wasKeptByKickBypass = false,
            shouldKeep = nil,
            attemptLogged = false,
            firstObservedEvent = nil,
            sawSent = false,
            sawStart = false,
            sawChannelStart = false,
            sawEmpowerStart = false,
            isSucceededOnlyInstant = false,
            locType = nil,
            locSpellID = nil,
            locDisplayText = nil,
            locDuration = nil,
            locTimeRemaining = nil,
            lockoutSchool = nil,
            lockoutSchoolText = nil,
            locAuraInstanceID = nil,
            locSourceEvent = nil,
            manualStopReason = nil,
            stoppedWhileMoving = nil,
            pendingStopAt = nil,
            pendingFailureSourceEvent = nil,
            runtimeState = BuildRuntimeStateSnapshot(),
            spellbookContext = nil,
            combatSignals = nil,
            lastSeenAt = GetDebugNow(),
        }
        debugCastByGuid[castGUID] = entry
    end
    if entry.spellID == nil and spellID ~= nil then
        entry.spellID = spellID
    end
    entry.lastSeenAt = GetDebugNow()
    entry.spellName = ResolveSpellName(entry.spellID, entry.spellName)
    return entry
end

RemoveCastEntry = function(castGUID)
    if castGUID then
        debugCastByGuid[castGUID] = nil
        if activeCastGuid == castGUID then
            activeCastGuid = nil
        end
    end
end

local function BuildGroupedHistoryEntry(castEntry)
    local loggedAtText = castEntry.outcomeLoggedAtText or castEntry.attemptLoggedAtText or date("%H:%M:%S")

    return {
        castKey = castEntry.castKey,
        roundIndex = castEntry.roundIndex or 0,
        loggedAtText = loggedAtText,
        loggedAtEpoch = castEntry.loggedAtEpoch or GetDebugEpoch(),
        attemptTimeCs = GetElapsedSessionCentiseconds(castEntry.attemptLoggedAtSeconds),
        resolveTimeCs = GetElapsedSessionCentiseconds(castEntry.resolveLoggedAtSeconds),
        attemptLoggedAtText = castEntry.attemptLoggedAtText or loggedAtText,
        outcomeLoggedAtText = castEntry.outcomeLoggedAtText or loggedAtText,
        attemptSourceEvent = castEntry.attemptSourceEvent,
        outcomeSourceEvent = castEntry.outcomeSourceEvent,
        spellID = castEntry.spellID,
        spellName = castEntry.spellName,
        castGUID = castEntry.castGUID,
        castID = castEntry.castID,
        castType = castEntry.castType,
        targetName = castEntry.targetName,
        targetDisposition = castEntry.targetDisposition,
        targetIsPlayer = castEntry.targetIsPlayer,
        targetCanAttack = castEntry.targetCanAttack,
        targetIsFriend = castEntry.targetIsFriend,
        targetReaction = castEntry.targetReaction,
        interruptible = castEntry.interruptible,
        interruptedBy = castEntry.interruptedBy,
        linkedLoc = 0,
        outcome = castEntry.outcome,
        note = castEntry.note,
        wasKeptByKickBypass = castEntry.wasKeptByKickBypass == true,
        locType = castEntry.locType,
        locSpellID = castEntry.locSpellID,
        locDisplayText = castEntry.locDisplayText,
        locDuration = castEntry.locDuration,
        locTimeRemaining = castEntry.locTimeRemaining,
        lockoutSchool = castEntry.lockoutSchool,
        lockoutSchoolText = castEntry.lockoutSchoolText,
        locAuraInstanceID = castEntry.locAuraInstanceID,
        locSourceEvent = castEntry.locSourceEvent,
        manualStopReason = castEntry.manualStopReason,
        stoppedWhileMoving = castEntry.stoppedWhileMoving,
        firstObservedEvent = castEntry.firstObservedEvent,
        sawSent = castEntry.sawSent == true,
        sawStart = castEntry.sawStart == true,
        sawChannelStart = castEntry.sawChannelStart == true,
        sawEmpowerStart = castEntry.sawEmpowerStart == true,
        isSucceededOnlyInstant = castEntry.isSucceededOnlyInstant == true,
        _linkedLocEntry = castEntry.linkedLocEntry,
    }
end

local function BuildFilteredHistoryEntry(castEntry)
    local loggedAtText = date("%H:%M:%S")
    local spellBookContext = castEntry.spellbookContext or {}
    local combatSignals = castEntry.combatSignals or {}
    local runtimeState = castEntry.runtimeState or {}

    return {
        loggedAtText = loggedAtText,
        loggedAtEpoch = GetDebugEpoch(),
        spellID = castEntry.spellID,
        spellName = castEntry.spellName,
        castGUID = castEntry.castGUID,
        castType = castEntry.castType,
        firstObservedEvent = castEntry.firstObservedEvent,
        filterReason = castEntry.filterReason,
        note = castEntry.note,
        provenance = {
            sawSent = castEntry.sawSent == true,
            sawStart = castEntry.sawStart == true,
            sawChannelStart = castEntry.sawChannelStart == true,
            sawEmpowerStart = castEntry.sawEmpowerStart == true,
            isSucceededOnlyInstant = castEntry.isSucceededOnlyInstant == true,
        },
        runtimeState = {
            isMounted = runtimeState.isMounted,
            isFlying = runtimeState.isFlying,
            isAdvancedFlyableArea = runtimeState.isAdvancedFlyableArea,
            isFlyableArea = runtimeState.isFlyableArea,
            isGliding = runtimeState.isGliding,
            canGlide = runtimeState.canGlide,
        },
        spellbookContext = {
            isInSpellBook = spellBookContext.isInSpellBook == true,
            isPassive = spellBookContext.isPassive,
            isHelpful = spellBookContext.isHelpful,
            isHarmful = spellBookContext.isHarmful,
            isUsable = spellBookContext.isUsable,
        },
        combatSignals = {
            isSpellHarmful = combatSignals.isSpellHarmful,
            isSpellHelpful = combatSignals.isSpellHelpful,
            isSpellCrowdControl = combatSignals.isSpellCrowdControl,
            isSpellImportant = combatSignals.isSpellImportant,
            isExternalDefensive = combatSignals.isExternalDefensive,
            isSelfBuff = combatSignals.isSelfBuff,
        },
    }
end

local function BuildLocHistoryEntry(locData, sourceEvent)
    return {
        locKey = 0,
        roundIndex = GetCurrentRoundIndex(),
        loggedAtText = date("%H:%M:%S"),
        loggedAtEpoch = GetDebugEpoch(),
        timeCs = GetElapsedSessionCentiseconds(),
        entryKind = "observed",
        sourceEvent = sourceEvent,
        locType = locData.locType,
        spellID = locData.spellID,
        displayText = locData.displayText,
        duration = locData.duration,
        timeRemaining = locData.timeRemaining,
        lockoutSchool = locData.lockoutSchool,
        lockoutSchoolText = locData.lockoutSchoolText,
        priority = locData.priority,
        displayType = locData.displayType,
        auraInstanceID = locData.auraInstanceID,
        issuedByGuid = "",
        linkedCastGUID = nil,
        linkedSpellID = nil,
        linkedOutcome = nil,
        linkedInterruptedBy = nil,
    }
end

local function CleanupRecentResolvedCastHistory()
    local now = GetDebugNow()
    local nextEntries = {}

    for i = 1, #recentResolvedCastHistory do
        local entry = recentResolvedCastHistory[i]
        if type(entry) == "table"
            and type(entry.resolvedAt) == "number"
            and (now - entry.resolvedAt) <= LOC_CAST_CORRELATION_WINDOW_SECONDS then
            nextEntries[#nextEntries + 1] = entry
        end
    end

    recentResolvedCastHistory = nextEntries
end

local function CleanupRecentLocHistory()
    local now = GetDebugNow()
    local nextEntries = {}

    for i = 1, #recentLocHistory do
        local entry = recentLocHistory[i]
        if type(entry) == "table"
            and type(entry.observedAt) == "number"
            and (now - entry.observedAt) <= LOC_CAST_CORRELATION_WINDOW_SECONDS then
            nextEntries[#nextEntries + 1] = entry
        end
    end

    recentLocHistory = nextEntries
end

local function RegisterRecentResolvedCast(historyEntry)
    if type(historyEntry) ~= "table" then
        return
    end

    CleanupRecentResolvedCastHistory()
    recentResolvedCastHistory[#recentResolvedCastHistory + 1] = {
        resolvedAt = GetDebugNow(),
        historyEntry = historyEntry,
    }
end

local function RegisterRecentLocEntry(locEntry)
    if type(locEntry) ~= "table" then
        return
    end

    CleanupRecentLocHistory()
    recentLocHistory[#recentLocHistory + 1] = {
        observedAt = GetDebugNow(),
        locEntry = locEntry,
    }
end

local function GetCastCorrelationOutcomePriority(outcome)
    if outcome == "kicked" then
        return 3
    end
    if outcome == "interrupted" then
        return 2
    end
    if outcome == "cancelled" then
        return 1
    end
    return 0
end

local function ShouldReplaceLocMetadata(existingLocType, newLocType)
    if type(newLocType) ~= "string" or newLocType == "" then
        return false
    end
    if type(existingLocType) ~= "string" or existingLocType == "" then
        return true
    end
    if existingLocType ~= "SCHOOL_INTERRUPT" and newLocType == "SCHOOL_INTERRUPT" then
        return true
    end
    return existingLocType == newLocType
end

local function ApplyLocFieldsToTarget(target, locEntry)
    if type(target) ~= "table" or type(locEntry) ~= "table" then
        return
    end
    if not ShouldReplaceLocMetadata(target.locType, locEntry.locType) then
        return
    end

    target.locType = locEntry.locType
    target.locSpellID = locEntry.spellID
    target.locDisplayText = locEntry.displayText
    target.locDuration = locEntry.duration
    target.locTimeRemaining = locEntry.timeRemaining
    target.lockoutSchool = locEntry.lockoutSchool
    target.lockoutSchoolText = locEntry.lockoutSchoolText
    target.locAuraInstanceID = locEntry.auraInstanceID
    target.locSourceEvent = locEntry.sourceEvent
end

local function LinkLocRecordToCast(locEntry, historyEntry, liveCastEntry)
    if type(locEntry) ~= "table" or type(historyEntry) ~= "table" then
        return false
    end

    locEntry.linkedCastGUID = historyEntry.castGUID
    locEntry.linkedSpellID = historyEntry.spellID
    locEntry.linkedOutcome = historyEntry.outcome
    locEntry.linkedInterruptedBy = historyEntry.interruptedBy
    if type(historyEntry.interruptedBy) == "string" and historyEntry.interruptedBy ~= "" then
        locEntry.issuedByGuid = historyEntry.interruptedBy
    end
    historyEntry._linkedLocEntry = locEntry

    ApplyLocFieldsToTarget(historyEntry, locEntry)
    if type(liveCastEntry) == "table" then
        ApplyLocFieldsToTarget(liveCastEntry, locEntry)
        liveCastEntry.linkedLocEntry = locEntry
    end
    return true
end

local function FindRecentResolvedCastForLoc(locEntry)
    CleanupRecentResolvedCastHistory()

    local bestHistoryEntry = nil
    local bestPriority = -1
    local bestResolvedAt = -1

    for i = 1, #recentResolvedCastHistory do
        local entry = recentResolvedCastHistory[i]
        local historyEntry = entry and entry.historyEntry or nil
        local outcome = historyEntry and historyEntry.outcome or nil
        local priority = 0
        if type(locEntry) == "table" and locEntry.locType == "SCHOOL_INTERRUPT" then
            if outcome == "kicked" then
                priority = 30
            elseif outcome == "interrupted" then
                priority = 20
            elseif outcome == "cancelled" then
                priority = 5
            end
        else
            if outcome == "interrupted" then
                priority = 20
            elseif outcome == "cancelled" then
                priority = 10
            elseif outcome == "kicked" then
                priority = 5
            end
        end
        if priority > 0 then
            local resolvedAt = entry.resolvedAt or 0
            if priority > bestPriority or (priority == bestPriority and resolvedAt > bestResolvedAt) then
                bestPriority = priority
                bestResolvedAt = resolvedAt
                bestHistoryEntry = historyEntry
            end
        end
    end

    return bestHistoryEntry
end

local function MaybeLinkLocToRecentCast(locEntry)
    if type(locEntry) ~= "table" or locEntry.linkedCastGUID then
        return
    end

    local historyEntry = FindRecentResolvedCastForLoc(locEntry)
    if historyEntry then
        LinkLocRecordToCast(locEntry, historyEntry, nil)
    end
end

local function FindRecentLocForCast(historyEntry)
    if type(historyEntry) ~= "table" then
        return nil
    end

    CleanupRecentLocHistory()

    local bestEntry = nil
    local bestScore = -1
    local bestObservedAt = -1

    for i = 1, #recentLocHistory do
        local recentEntry = recentLocHistory[i]
        local locEntry = recentEntry and recentEntry.locEntry or nil
        if type(locEntry) == "table" and not locEntry.linkedCastGUID then
            local score = 0
            if historyEntry.outcome == "kicked" then
                score = locEntry.locType == "SCHOOL_INTERRUPT" and 20 or 5
            elseif historyEntry.outcome == "interrupted" then
                score = locEntry.locType == "SCHOOL_INTERRUPT" and 15 or 10
            elseif historyEntry.outcome == "cancelled" then
                score = 1
            end

            local observedAt = recentEntry.observedAt or 0
            if score > bestScore or (score == bestScore and observedAt > bestObservedAt) then
                bestScore = score
                bestObservedAt = observedAt
                bestEntry = locEntry
            end
        end
    end

    return bestEntry
end

local function MaybeLinkRecentLocToCast(historyEntry, liveCastEntry)
    if type(historyEntry) ~= "table" then
        return
    end

    if GetCastCorrelationOutcomePriority(historyEntry.outcome) <= 0 then
        return
    end

    local locEntry = FindRecentLocForCast(historyEntry)
    if locEntry then
        LinkLocRecordToCast(locEntry, historyEntry, liveCastEntry)
    end
end

local function BuildLocCacheKey(locData)
    if type(locData) ~= "table" then
        return nil
    end

    if type(locData.auraInstanceID) == "number" and locData.auraInstanceID > 0 then
        return "aura:" .. tostring(locData.auraInstanceID)
    end

    return table.concat({
        tostring(locData.locType or "-"),
        tostring(locData.spellID or "-"),
        tostring(locData.startTime or "-"),
        tostring(locData.displayType or "-"),
    }, "|")
end

local function RecordLocEntry(locEntry)
    if type(locEntry) ~= "table" then
        return
    end

    PushLocDebugHistory(locEntry)
    RegisterRecentLocEntry(locEntry)
    AppendLocToChat(locEntry)
end

local function ObserveLocData(locData, sourceEvent)
    if type(locData) ~= "table" then
        return
    end

    local locKey = BuildLocCacheKey(locData)
    if not locKey then
        return
    end

    local existing = activeLocByKey[locKey]
    if type(existing) == "table" and type(existing.locEntry) == "table" then
        existing.lastSeenAt = GetDebugNow()
        return
    end

    local locEntry = BuildLocHistoryEntry(locData, sourceEvent)
    MaybeLinkLocToRecentCast(locEntry)
    RecordLocEntry(locEntry)
    activeLocByKey[locKey] = {
        lastSeenAt = GetDebugNow(),
        locEntry = locEntry,
    }
end

local function RefreshActiveLocState(sourceEvent)
    local seenKeys = {}
    local count = SafeGetLossOfControlDataCount()

    for index = 1, count do
        local locData = SafeGetLossOfControlData(index)
        local locKey = BuildLocCacheKey(locData)
        if locKey then
            seenKeys[locKey] = true
            ObserveLocData(locData, sourceEvent)
        end
    end

    for locKey in pairs(activeLocByKey) do
        if seenKeys[locKey] ~= true then
            activeLocByKey[locKey] = nil
        end
    end
end

local function RecordFilteredCast(castEntry)
    if PvPScalpel_Debug ~= true then
        return
    end

    local filteredEntry = BuildFilteredHistoryEntry(castEntry)
    AppendFilteredToChat(filteredEntry)
end

local function TrackCastProvenance(castEntry, sourceEvent)
    if not castEntry or type(sourceEvent) ~= "string" then
        return
    end

    if not castEntry.firstObservedEvent then
        castEntry.firstObservedEvent = sourceEvent
    end

    if sourceEvent == "UNIT_SPELLCAST_SENT" then
        castEntry.sawSent = true
    elseif sourceEvent == "UNIT_SPELLCAST_START" then
        castEntry.sawStart = true
    elseif sourceEvent == "UNIT_SPELLCAST_CHANNEL_START" then
        castEntry.sawChannelStart = true
    elseif sourceEvent == "UNIT_SPELLCAST_EMPOWER_START" then
        castEntry.sawEmpowerStart = true
    end
end

local function EnsureCastIncluded(castEntry)
    if not castEntry then
        return false
    end

    if castEntry.shouldKeep ~= nil then
        return castEntry.shouldKeep == true
    end

    if type(castEntry.spellID) ~= "number" then
        return nil
    end

    local decision = EvaluateCombatSpellFilter(castEntry)
    castEntry.shouldKeep = decision.keep == true
    castEntry.wasKeptByKickBypass = decision.wasKeptByKickBypass == true

    if castEntry.shouldKeep ~= true then
        castEntry.filterReason = decision.filterReason
        castEntry.note = CombineDebugNotes(castEntry.note, decision.note)
        RecordFilteredCast(castEntry)
        MarkResolvedCast(castEntry.castGUID)
        RemoveCastEntry(castEntry.castGUID)
        CleanupResolvedCastCache()
        return false
    end

    return true
end

local function LogCastAttempt(castEntry, sourceEvent)
    if not castEntry then
        return false
    end

    local shouldKeep = EnsureCastIncluded(castEntry)
    if shouldKeep ~= true then
        return false
    end

    if castEntry.attemptLogged then
        return true
    end

    castEntry.attemptSourceEvent = sourceEvent
    castEntry.roundIndex = castEntry.roundIndex or GetCurrentRoundIndex()
    castEntry.attemptLoggedAtText = date("%H:%M:%S")
    castEntry.attemptLoggedAtSeconds = GetDebugNow()
    castEntry.attemptLogged = true
    AppendAttemptToChat(castEntry)
    return true
end

local function ResolveOutcome(castEntry, outcome, sourceEvent)
    if not castEntry or type(outcome) ~= "string" or castEntry.outcome ~= nil then
        return
    end

    local shouldKeep = EnsureCastIncluded(castEntry)
    if shouldKeep ~= true then
        return
    end

    castEntry.outcome = outcome
    castEntry.outcomeSourceEvent = sourceEvent
    castEntry.outcomeLoggedAtText = date("%H:%M:%S")
    castEntry.resolveLoggedAtSeconds = GetDebugNow()
    castEntry.loggedAtEpoch = GetDebugEpoch()
    castEntry.pendingStopAt = nil
    castEntry.pendingFailureSourceEvent = nil

    local historyEntry = nil
    if IsSpellCaptureSessionActive() then
        historyEntry = BuildGroupedHistoryEntry(castEntry)
        PushDebugHistory(historyEntry)
        RegisterRecentResolvedCast(historyEntry)
        MaybeLinkRecentLocToCast(historyEntry, castEntry)
    end

    AppendOutcomeToChat(castEntry)

    MaybeArmPendingUserCc(castEntry)

    MarkResolvedCast(castEntry.castGUID)
    RemoveCastEntry(castEntry.castGUID)
    CleanupResolvedCastCache()
end

local function WasMovementObservedNearStop(stopAt)
    if type(stopAt) ~= "number" then
        return false
    end

    if movementStateCache.isMoving == true then
        return true
    end

    local lastStartedMovingAt = movementStateCache.lastStartedMovingAt
    return type(lastStartedMovingAt) == "number"
        and math.abs(lastStartedMovingAt - stopAt) <= STOP_FINALIZE_GRACE_SECONDS
end

local function ResolveMovementStopOutcome(castEntry)
    if type(castEntry) ~= "table" then
        return false
    end
    if castEntry.outcome ~= nil then
        return false
    end
    if castEntry.castType ~= "cast" or castEntry.sawStart ~= true then
        return false
    end
    if type(castEntry.pendingStopAt) ~= "number" then
        return false
    end
    if WasMovementObservedNearStop(castEntry.pendingStopAt) ~= true then
        return false
    end

    castEntry.manualStopReason = "movement_stop"
    castEntry.stoppedWhileMoving = true
    castEntry.note = CombineDebugNotes(castEntry.note, "Observed hard-cast stop while moving.")
    ResolveOutcome(castEntry, "cancelled", "UNIT_SPELLCAST_STOP")
    return true
end

local function FinalizePendingStop(castGUID, expectedStopAt)
    if not castGUID then
        return
    end

    local castEntry = debugCastByGuid[castGUID]
    if not castEntry or castEntry.outcome ~= nil then
        return
    end
    if type(expectedStopAt) == "number" and castEntry.pendingStopAt ~= expectedStopAt then
        return
    end
    if type(castEntry.pendingStopAt) ~= "number" then
        return
    end
    if (GetDebugNow() - castEntry.pendingStopAt) < STOP_FINALIZE_GRACE_SECONDS then
        return
    end

    if ResolveMovementStopOutcome(castEntry) then
        return
    end

    if type(castEntry.pendingFailureSourceEvent) == "string" and castEntry.pendingFailureSourceEvent ~= "" then
        ResolveOutcome(castEntry, "not_success", castEntry.pendingFailureSourceEvent)
        return
    end

    castEntry.pendingStopAt = nil
end

local function SchedulePendingStopFinalization(castGUID, pendingStopAt)
    if not castGUID then
        return
    end

    if C_Timer and C_Timer.After then
        pcall(C_Timer.After, STOP_FINALIZE_GRACE_SECONDS, function()
            FinalizePendingStop(castGUID, pendingStopAt)
        end)
    end
end

local function UpdateInterruptibleState(castGUID, interruptible)
    if not castGUID then
        return
    end
    local castEntry = debugCastByGuid[castGUID]
    if not castEntry then
        return
    end
    castEntry.interruptible = interruptible
    castEntry.lastSeenAt = GetDebugNow()
end

local function PruneStaleCastEntries()
    local now = GetDebugNow()
    for castGUID, castEntry in pairs(debugCastByGuid) do
        if type(castEntry.pendingStopAt) == "number" then
            FinalizePendingStop(castGUID, castEntry.pendingStopAt)
        end
        if not castEntry.outcome and type(castEntry.lastSeenAt) == "number" and (now - castEntry.lastSeenAt) > RESOLVED_CAST_TTL_SECONDS then
            RemoveCastEntry(castGUID)
        end
    end
end

local function ApplyCastingInfo(castEntry)
    local castInfo = SafeUnitCastingInfo()
    if not castInfo then
        return
    end
    castEntry.castType = "cast"
    castEntry.castID = castInfo.castID
    castEntry.spellID = castEntry.spellID or castInfo.spellID
    castEntry.spellName = ResolveSpellName(castEntry.spellID, castInfo.name)
    if castInfo.notInterruptible == nil then
        castEntry.interruptible = nil
    else
        castEntry.interruptible = not castInfo.notInterruptible
    end
end

local function ApplyChannelInfoData(castEntry, channelInfo, forceEmpower)
    if channelInfo then
        castEntry.spellID = castEntry.spellID or channelInfo.spellID
        castEntry.spellName = ResolveSpellName(castEntry.spellID, channelInfo.name)
        if channelInfo.notInterruptible == nil then
            castEntry.interruptible = nil
        else
            castEntry.interruptible = not channelInfo.notInterruptible
        end
        if forceEmpower or channelInfo.isEmpowered or (type(channelInfo.numEmpowerStages) == "number" and channelInfo.numEmpowerStages > 0) then
            castEntry.castType = "empower"
        else
            castEntry.castType = "channel"
        end
        return
    end
end

local function ApplyChannelInfo(castEntry, forceEmpower)
    local channelInfo = SafeUnitChannelInfo()
    if channelInfo then
        ApplyChannelInfoData(castEntry, channelInfo, forceEmpower)
        return
    end

    if forceEmpower then
        castEntry.castType = "empower"
    elseif not castEntry.castType then
        castEntry.castType = "channel"
    end
end

local function GetMatchingActiveChannelInfo(castEntry, spellID)
    local channelInfo = SafeUnitChannelInfo()
    if not channelInfo then
        return nil
    end

    local expectedSpellID = spellID or (castEntry and castEntry.spellID) or nil
    if type(expectedSpellID) == "number" and type(channelInfo.spellID) == "number" then
        if expectedSpellID == channelInfo.spellID then
            return channelInfo
        end
    end

    local expectedName = nil
    if type(castEntry) == "table" then
        expectedName = castEntry.spellName
    end
    expectedName = ResolveSpellName(expectedSpellID, expectedName)
    if type(expectedName) == "string" and expectedName ~= "" and channelInfo.name == expectedName then
        return channelInfo
    end

    return nil
end

local function EnsureCastPrepared(castGUID, spellID, castType, note, sourceEvent)
    if not castGUID or IsResolvedCast(castGUID) then
        return nil
    end

    local castEntry = EnsureCastEntry(castGUID, spellID)
    if castEntry.roundIndex == nil then
        castEntry.roundIndex = GetCurrentRoundIndex()
    end
    if castType and not castEntry.castType then
        castEntry.castType = castType
    end
    if note and not castEntry.note then
        castEntry.note = note
    end
    AssignTargetSnapshot(castEntry, targetSnapshotCache)
    if sourceEvent then
        TrackCastProvenance(castEntry, sourceEvent)
    end

    return castEntry
end

local function HandleSent(castGUID, spellID, targetName)
    if not castGUID or IsResolvedCast(castGUID) then
        return
    end

    local castEntry = EnsureCastPrepared(castGUID, spellID, nil, nil, "UNIT_SPELLCAST_SENT")
    if not castEntry then
        return
    end

    AssignTargetSnapshot(castEntry, targetSnapshotCache, targetName)
end

local function HandleStart(castGUID, spellID)
    local castEntry = EnsureCastPrepared(castGUID, spellID, "cast", nil, "UNIT_SPELLCAST_START")
    if not castEntry then
        return
    end
    ApplyCastingInfo(castEntry)
    if EnsureCastIncluded(castEntry) == false then
        return
    end
    activeCastGuid = castGUID
    LogCastAttempt(castEntry, "UNIT_SPELLCAST_START")
end

local function HandleChannelStart(castGUID, spellID, forceEmpower, sourceEvent)
    local castType = forceEmpower and "empower" or "channel"
    local castEntry = EnsureCastPrepared(castGUID, spellID, castType, nil, sourceEvent)
    if not castEntry then
        return
    end
    ApplyChannelInfo(castEntry, forceEmpower)
    if EnsureCastIncluded(castEntry) == false then
        return
    end
    activeCastGuid = castGUID
    LogCastAttempt(castEntry, sourceEvent)
end

local function HandleSuccess(castGUID, spellID)
    local castEntry = EnsureCastPrepared(castGUID, spellID, nil, nil, "UNIT_SPELLCAST_SUCCEEDED")
    if not castEntry then
        return
    end

    local activeChannelInfo = GetMatchingActiveChannelInfo(castEntry, spellID)
    if activeChannelInfo then
        ApplyChannelInfoData(castEntry, activeChannelInfo, false)
        castEntry.isSucceededOnlyInstant = false
        castEntry.note = CombineDebugNotes(castEntry.note, "Observed SUCCEEDED while matching channel or empower remained active.")
        activeCastGuid = castGUID
        if not castEntry.attemptLogged then
            LogCastAttempt(castEntry, "UNIT_SPELLCAST_SUCCEEDED")
        end
        return
    end

    if not castEntry.attemptLogged then
        castEntry.castType = castEntry.castType or "instant"
        castEntry.isSucceededOnlyInstant = castEntry.sawStart ~= true and castEntry.sawChannelStart ~= true and castEntry.sawEmpowerStart ~= true
        castEntry.note = castEntry.note or "Observed success without prior start event."
        if not LogCastAttempt(castEntry, "UNIT_SPELLCAST_SUCCEEDED") then
            return
        end
    end
    ResolveOutcome(castEntry, "success", "UNIT_SPELLCAST_SUCCEEDED")
end

local function HandleFailure(castGUID, spellID, sourceEvent)
    local castEntry = EnsureCastPrepared(castGUID, spellID, nil, nil, sourceEvent)
    if not castEntry then
        return
    end

    if type(castEntry.pendingStopAt) == "number" then
        castEntry.pendingFailureSourceEvent = sourceEvent
        if ResolveMovementStopOutcome(castEntry) then
            return
        end
        SchedulePendingStopFinalization(castGUID, castEntry.pendingStopAt)
        return
    end

    if not castEntry.attemptLogged then
        castEntry.castType = castEntry.castType or "unknown"
        castEntry.isSucceededOnlyInstant = false
        castEntry.note = castEntry.note or "Observed terminal failure without prior start event."
        if not LogCastAttempt(castEntry, sourceEvent) then
            return
        end
    end
    ResolveOutcome(castEntry, "not_success", sourceEvent)
end

local function ResolveInterruptOutcome(castEntry, interruptedBy, sourceEvent)
    local outcome = "interrupted"
    local playerGuid = GetPlayerGuidSafe()
    if type(interruptedBy) == "string" and interruptedBy ~= "" then
        castEntry.interruptedBy = interruptedBy
        if castEntry.interruptible == true and interruptedBy ~= playerGuid and IsPlayerGuid(interruptedBy) then
            outcome = "kicked"
        end
    end
    ResolveOutcome(castEntry, outcome, sourceEvent)
end

local function HandleChannelStop(castGUID, spellID, interruptedBy)
    local castEntry = EnsureCastPrepared(castGUID, spellID, nil, nil, "UNIT_SPELLCAST_CHANNEL_STOP")
    if not castEntry then
        return
    end
    castEntry.castType = castEntry.castType or "channel"
    if not castEntry.attemptLogged then
        castEntry.note = castEntry.note or "Observed terminal channel stop without prior start event."
        if not LogCastAttempt(castEntry, "UNIT_SPELLCAST_CHANNEL_STOP") then
            return
        end
    end
    if type(interruptedBy) == "string" and interruptedBy ~= "" then
        ResolveInterruptOutcome(castEntry, interruptedBy, "UNIT_SPELLCAST_CHANNEL_STOP")
    else
        ResolveOutcome(castEntry, "success", "UNIT_SPELLCAST_CHANNEL_STOP")
    end
end

local function HandleEmpowerStop(castGUID, spellID, complete, interruptedBy)
    local castEntry = EnsureCastPrepared(castGUID, spellID, nil, nil, "UNIT_SPELLCAST_EMPOWER_STOP")
    if not castEntry then
        return
    end
    castEntry.castType = "empower"
    if not castEntry.attemptLogged then
        castEntry.note = castEntry.note or "Observed terminal empower stop without prior start event."
        if not LogCastAttempt(castEntry, "UNIT_SPELLCAST_EMPOWER_STOP") then
            return
        end
    end
    if complete == true and (type(interruptedBy) ~= "string" or interruptedBy == "") then
        ResolveOutcome(castEntry, "success", "UNIT_SPELLCAST_EMPOWER_STOP")
        return
    end
    ResolveInterruptOutcome(castEntry, interruptedBy, "UNIT_SPELLCAST_EMPOWER_STOP")
end

local function HandleInterrupted(castGUID, spellID, interruptedBy, sourceEvent)
    local castEntry = EnsureCastPrepared(castGUID, spellID, nil, nil, sourceEvent)
    if not castEntry then
        return
    end
    if not castEntry.castType then
        castEntry.castType = "cast"
    end
    if not castEntry.attemptLogged then
        castEntry.note = castEntry.note or "Observed interruption without prior start event."
        if not LogCastAttempt(castEntry, sourceEvent) then
            return
        end
    end
    ResolveInterruptOutcome(castEntry, interruptedBy, sourceEvent)
end

local function HandleStop(castGUID)
    local castEntry = debugCastByGuid[castGUID]
    if activeCastGuid == castGUID then
        activeCastGuid = nil
    end
    if not castEntry or castEntry.outcome ~= nil then
        return
    end
    if castEntry.castType ~= "cast" or castEntry.sawStart ~= true then
        return
    end

    castEntry.pendingStopAt = GetDebugNow()
    castEntry.lastSeenAt = castEntry.pendingStopAt
    SchedulePendingStopFinalization(castGUID, castEntry.pendingStopAt)
end

local function HandlePlayerStartedMoving()
    movementStateCache.isMoving = true
    movementStateCache.lastStartedMovingAt = GetDebugNow()
end

local function HandlePlayerStoppedMoving()
    movementStateCache.isMoving = false
    movementStateCache.lastStoppedMovingAt = GetDebugNow()
end

local function HandleLossOfControlAdded(unit, effectIndex)
    if unit ~= "player" then
        return
    end

    local locData = SafeGetLossOfControlData(effectIndex)
    if locData then
        ObserveLocData(locData, "LOSS_OF_CONTROL_ADDED")
        return
    end

    RefreshActiveLocState("LOSS_OF_CONTROL_ADDED")
end

local function HandleLossOfControlUpdate(unit)
    if unit ~= "player" then
        return
    end

    RefreshActiveLocState("LOSS_OF_CONTROL_UPDATE")
end

local function IsPlayerSpellcastLifecycleEvent(eventName)
    return eventName == "UNIT_SPELLCAST_SENT"
        or eventName == "UNIT_SPELLCAST_START"
        or eventName == "UNIT_SPELLCAST_STOP"
        or eventName == "UNIT_SPELLCAST_SUCCEEDED"
        or eventName == "UNIT_SPELLCAST_FAILED"
        or eventName == "UNIT_SPELLCAST_FAILED_QUIET"
        or eventName == "UNIT_SPELLCAST_INTERRUPTED"
        or eventName == "UNIT_SPELLCAST_CHANNEL_START"
        or eventName == "UNIT_SPELLCAST_CHANNEL_STOP"
        or eventName == "UNIT_SPELLCAST_EMPOWER_START"
        or eventName == "UNIT_SPELLCAST_EMPOWER_STOP"
        or eventName == "UNIT_SPELLCAST_INTERRUPTIBLE"
        or eventName == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
end

local function OnHeuristicUnitEvent(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        ResetHeuristicRuntimeForWorld()
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        HandleHeuristicPlayerTargetChanged()
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        HandleHeuristicPlayerFocusChanged()
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" then
        local unitToken = ...
        HandleHeuristicNameplateAdded(unitToken)
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" then
        local unitToken = ...
        HandleHeuristicNameplateRemoved(unitToken)
        return
    end

    if ShouldRunLiveHeuristicRuntime() ~= true then
        return
    end

    if event == "UNIT_AURA" then
        local unitToken, updateInfo = ...
        if unitToken == "player" or HasPendingUserCc() then
            HandleHeuristicUnitAura(unitToken, updateInfo)
        end
        return
    end

    if event == "LOSS_OF_CONTROL_ADDED" then
        local unitToken, effectIndex = ...
        if unitToken == "player" or HasPendingUserCc() then
            ScanWatchedUnitLossOfControl(unitToken, "aura", effectIndex)
        end
        return
    end

    if event == "LOSS_OF_CONTROL_UPDATE" then
        local unitToken = ...
        if unitToken == "player" or HasPendingUserCc() then
            ScanWatchedUnitLossOfControl(unitToken, "aura")
        end
    end
end

local function ResetRuntimeCaptureState()
    debugCastByGuid = {}
    resolvedCastByGuid = {}
    recentResolvedCastHistory = {}
    recentLocHistory = {}
    activeLocByKey = {}
    activeCastGuid = nil
    targetSnapshotCache = nil
    RefreshRuntimeStateCache()
    RefreshMovementStateCache()
end

function MapTriStateBoolean(value)
    if value == true then
        return 1
    end
    if value == false then
        return 0
    end
    return 2
end

function MapCastType(castType)
    if castType == "cast" then
        return 1
    end
    if castType == "instant" then
        return 2
    end
    if castType == "channel" then
        return 3
    end
    if castType == "empower" then
        return 4
    end
    return -1
end

function MapOutcome(outcome)
    if outcome == "success" then
        return 0
    end
    if outcome == "not_success" then
        return 1
    end
    if outcome == "interrupted" then
        return 2
    end
    if outcome == "kicked" then
        return 3
    end
    if outcome == "cancelled" then
        return 4
    end
    return -1
end

function MapFirstObservedEvent(eventName)
    if eventName == "UNIT_SPELLCAST_SENT" then
        return 1
    end
    if eventName == "UNIT_SPELLCAST_START" then
        return 2
    end
    if eventName == "UNIT_SPELLCAST_CHANNEL_START" then
        return 3
    end
    if eventName == "UNIT_SPELLCAST_EMPOWER_START" then
        return 4
    end
    if eventName == "UNIT_SPELLCAST_SUCCEEDED" then
        return 5
    end
    if eventName == "UNIT_SPELLCAST_FAILED" then
        return 6
    end
    if eventName == "UNIT_SPELLCAST_FAILED_QUIET" then
        return 7
    end
    if eventName == "UNIT_SPELLCAST_INTERRUPTED" then
        return 8
    end
    return -1
end

function MapOutcomeEvent(eventName)
    if eventName == "UNIT_SPELLCAST_SUCCEEDED" then
        return 1
    end
    if eventName == "UNIT_SPELLCAST_FAILED" then
        return 2
    end
    if eventName == "UNIT_SPELLCAST_FAILED_QUIET" then
        return 3
    end
    if eventName == "UNIT_SPELLCAST_INTERRUPTED" then
        return 4
    end
    if eventName == "UNIT_SPELLCAST_CHANNEL_STOP" then
        return 5
    end
    if eventName == "UNIT_SPELLCAST_EMPOWER_STOP" then
        return 6
    end
    if eventName == "UNIT_SPELLCAST_STOP" then
        return 7
    end
    return -1
end

function MapTargetDisposition(disposition)
    if disposition == "none" then
        return 0
    end
    if disposition == "unknown" then
        return 1
    end
    if disposition == "friendly" then
        return 2
    end
    if disposition == "hostile" then
        return 3
    end
    return -1
end

function MapLocSourceEvent(eventName)
    if eventName == "LOSS_OF_CONTROL_ADDED" then
        return 1
    end
    if eventName == "LOSS_OF_CONTROL_UPDATE" then
        return 2
    end
    return 0
end

function MapLocEntryKind(entryKind)
    if entryKind == "observed" then
        return 1
    end
    return 0
end

function MapManualStopReason(reason)
    if reason == "movement_stop" then
        return 1
    end
    return 0
end

function BuildProvenanceFlags(entry)
    local flags = 0
    if entry and entry.sawSent == true then
        flags = flags + 1
    end
    if entry and entry.sawStart == true then
        flags = flags + 2
    end
    if entry and entry.sawChannelStart == true then
        flags = flags + 4
    end
    if entry and entry.sawEmpowerStart == true then
        flags = flags + 8
    end
    if entry and entry.isSucceededOnlyInstant == true then
        flags = flags + 16
    end
    return flags
end

function SecondsToCs(value)
    if type(value) ~= "number" then
        return -1
    end
    return math.max(0, math.floor((value * 100) + 0.5))
end

function GetCastSchemaRow()
    return {
        { "castKey", "u16", "-1=invalid" },
        { "roundIndex", "u8", "0=no round" },
        { "attemptTimeCs", "i32", "-1=missing" },
        { "resolveTimeCs", "i32", "-1=missing" },
        { "castType", "u8", "-1=unknown" },
        { "outcome", "u8", "-1=unknown" },
        { "interruptibleState", "u8", "2=unknown" },
        { "firstObservedEvent", "u8", "-1=unknown" },
        { "outcomeEvent", "u8", "-1=unknown" },
        { "targetName", "string", "\"\"=none" },
        { "targetDisposition", "u8", "-1=unknown" },
        { "targetIsPlayer", "u8", "2=unknown" },
        { "targetCanAttack", "u8", "2=unknown" },
        { "targetIsFriend", "u8", "2=unknown" },
        { "targetReaction", "i8", "-1=unknown" },
        { "interruptedBy", "string", "\"\"=none" },
        { "linkedLoc", "u16", "0=no link" },
        { "manualStopReason", "u8", "0=none" },
        { "provenanceFlags", "u8", "0=none" },
    }
end

function GetLocSchemaRow()
    return {
        { "locKey", "u16", "-1=invalid" },
        { "roundIndex", "u8", "0=no round" },
        { "timeCs", "i32", "-1=missing" },
        { "entryKind", "u8", "0=unknown" },
        { "sourceEvent", "u8", "0=unknown" },
        { "locType", "string", "\"\"=missing" },
        { "spellID", "i32", "-1=missing" },
        { "displayText", "string", "\"\"=missing" },
        { "durationCs", "i32", "-1=missing" },
        { "lockoutSchool", "i16", "0=none" },
        { "lockoutSchoolText", "string", "\"\"=none" },
        { "auraInstanceID", "i32", "0=none" },
        { "issuedByGuid", "string", "\"\"=none" },
    }
end

local function SerializeLocalLossOfControl()
    local history = EnsureLocHistory()
    local entries = {
        [0] = GetLocSchemaRow(),
    }
    local rowIndexByEntry = {}
    local linkedCount = 0

    for i = 1, #history do
        local entry = history[i]
        if type(entry) == "table" then
            local rowIndex = #entries + 1
            entry.locKey = rowIndex
            entries[rowIndex] = {
                rowIndex,
                type(entry.roundIndex) == "number" and entry.roundIndex or 0,
                type(entry.timeCs) == "number" and entry.timeCs or -1,
                MapLocEntryKind(entry.entryKind),
                MapLocSourceEvent(entry.sourceEvent),
                type(entry.locType) == "string" and entry.locType or "",
                type(entry.spellID) == "number" and entry.spellID or -1,
                type(entry.displayText) == "string" and entry.displayText or "",
                SecondsToCs(entry.duration),
                type(entry.lockoutSchool) == "number" and entry.lockoutSchool or 0,
                type(entry.lockoutSchoolText) == "string" and entry.lockoutSchoolText or "",
                type(entry.auraInstanceID) == "number" and entry.auraInstanceID or 0,
                type(entry.issuedByGuid) == "string" and entry.issuedByGuid or "",
            }
            rowIndexByEntry[entry] = rowIndex
            if type(entry.linkedCastGUID) == "string" and entry.linkedCastGUID ~= "" then
                linkedCount = linkedCount + 1
            end
        end
    end

    return {
        captureVersion = 1,
        timeUnit = "cs",
        totals = {
            entries = #history,
            linked = linkedCount,
            unlinked = #history - linkedCount,
        },
        entries = entries,
    }, rowIndexByEntry
end

local function SerializeLocalSpellCapture(locRowIndexByEntry)
    local groupedHistory = EnsureKeptHistory()
    local bySpellID = {}
    local totals = {
        spells = 0,
        casts = 0,
        success = 0,
        notSuccess = 0,
        interrupted = 0,
        kicked = 0,
        cancelled = 0,
    }

    for i = 1, #groupedHistory do
        local entry = groupedHistory[i]
        if type(entry) == "table" and type(entry.spellID) == "number" then
            local spellBucket = bySpellID[entry.spellID]
            if not spellBucket then
                spellBucket = {
                    spellName = entry.spellName or ResolveSpellName(entry.spellID),
                    counts = {
                        attempts = 0,
                        success = 0,
                        notSuccess = 0,
                        interrupted = 0,
                        kicked = 0,
                        cancelled = 0,
                    },
                    casts = {
                        [0] = GetCastSchemaRow(),
                    },
                }
                bySpellID[entry.spellID] = spellBucket
                totals.spells = totals.spells + 1
            end

            local linkedLoc = 0
            if type(entry._linkedLocEntry) == "table" then
                linkedLoc = locRowIndexByEntry[entry._linkedLocEntry] or 0
            end

            spellBucket.counts.attempts = spellBucket.counts.attempts + 1
            totals.casts = totals.casts + 1

            if entry.outcome == "success" then
                spellBucket.counts.success = spellBucket.counts.success + 1
                totals.success = totals.success + 1
            elseif entry.outcome == "not_success" then
                spellBucket.counts.notSuccess = spellBucket.counts.notSuccess + 1
                totals.notSuccess = totals.notSuccess + 1
            elseif entry.outcome == "interrupted" then
                spellBucket.counts.interrupted = spellBucket.counts.interrupted + 1
                totals.interrupted = totals.interrupted + 1
            elseif entry.outcome == "kicked" then
                spellBucket.counts.kicked = spellBucket.counts.kicked + 1
                totals.kicked = totals.kicked + 1
            elseif entry.outcome == "cancelled" then
                spellBucket.counts.cancelled = spellBucket.counts.cancelled + 1
                totals.cancelled = totals.cancelled + 1
            end

            table.insert(spellBucket.casts, {
                type(entry.castKey) == "number" and entry.castKey or -1,
                type(entry.roundIndex) == "number" and entry.roundIndex or 0,
                type(entry.attemptTimeCs) == "number" and entry.attemptTimeCs or -1,
                type(entry.resolveTimeCs) == "number" and entry.resolveTimeCs or -1,
                MapCastType(entry.castType),
                MapOutcome(entry.outcome),
                MapTriStateBoolean(entry.interruptible),
                MapFirstObservedEvent(entry.firstObservedEvent),
                MapOutcomeEvent(entry.outcomeSourceEvent),
                type(entry.targetName) == "string" and entry.targetName or "",
                MapTargetDisposition(entry.targetDisposition),
                MapTriStateBoolean(entry.targetIsPlayer),
                MapTriStateBoolean(entry.targetCanAttack),
                MapTriStateBoolean(entry.targetIsFriend),
                type(entry.targetReaction) == "number" and entry.targetReaction or -1,
                type(entry.interruptedBy) == "string" and entry.interruptedBy or "",
                linkedLoc,
                MapManualStopReason(entry.manualStopReason),
                BuildProvenanceFlags(entry),
            })
        end
    end

    return {
        captureVersion = 1,
        timeUnit = "cs",
        totals = totals,
        bySpellID = bySpellID,
    }
end

function PvPScalpel_IsLocalSpellCaptureActive()
    return IsSpellCaptureSessionActive()
end

function PvPScalpel_StartLocalSpellCaptureSession()
    ResetRuntimeCaptureState()
    ResetSessionCollections()
    local session = EnsureSessionCollections()
    session.active = true
    session.startedAt = GetDebugNow()
    RefreshTargetSnapshot()
    if PvPScalpel_Debug == true then
        ShowDebugHistory()
    end
end

function PvPScalpel_StopLocalSpellCaptureSession(match)
    local session = EnsureSessionCollections()

    if PvPScalpel_IsTable(match) then
        local localLossOfControl, locRowIndexByEntry = SerializeLocalLossOfControl()
        match.localLossOfControl = localLossOfControl
        match.localSpellCapture = SerializeLocalSpellCapture(locRowIndexByEntry)
    end

    session.active = false
    session.startedAt = nil
    ResetRuntimeCaptureState()
    ResetSessionCollections()

    return match
end

local function OnSpellEvent(_, event, unit, ...)
    if event == "UNIT_TARGET" then
        if unit == "player" then
            RefreshTargetSnapshot()
        end
        return
    end

    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_CAN_GLIDE_CHANGED" or event == "PLAYER_IS_GLIDING_CHANGED" then
        RefreshRuntimeStateCache()
        return
    end

    if event == "PLAYER_STARTED_MOVING" then
        HandlePlayerStartedMoving()
        return
    end

    if event == "PLAYER_STOPPED_MOVING" then
        HandlePlayerStoppedMoving()
        return
    end

    PruneStaleCastEntries()

    if event == "LOSS_OF_CONTROL_ADDED" then
        if not IsSpellCaptureSessionActive() and PvPScalpel_Debug ~= true then
            return
        end
        HandleLossOfControlAdded(unit, ...)
        return
    end

    if event == "LOSS_OF_CONTROL_UPDATE" then
        if not IsSpellCaptureSessionActive() and PvPScalpel_Debug ~= true then
            return
        end
        HandleLossOfControlUpdate(unit)
        return
    end

    if unit ~= "player" then
        return
    end

    if not IsSpellCaptureSessionActive() and PvPScalpel_Debug ~= true then
        return
    end

    if not IsSpellCaptureSessionActive() and not IsPlayerSpellcastLifecycleEvent(event) then
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        UpdateInterruptibleState(activeCastGuid, true)
        return
    end

    if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        UpdateInterruptibleState(activeCastGuid, false)
        return
    end

    if event == "UNIT_SPELLCAST_SENT" then
        local targetName, castGUID, spellID = ...
        if castGUID and not IsRealCastGUID(castGUID) then
            return
        end
        HandleSent(castGUID, spellID, targetName)
        return
    end

    local castGUID, spellID, arg3, arg4 = ...
    if castGUID and not IsRealCastGUID(castGUID) then
        return
    end
    if not castGUID then
        return
    end

    if event == "UNIT_SPELLCAST_START" then
        HandleStart(castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        HandleChannelStart(castGUID, spellID, false, "UNIT_SPELLCAST_CHANNEL_START")
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        HandleChannelStart(castGUID, spellID, true, "UNIT_SPELLCAST_EMPOWER_START")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        HandleSuccess(castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_FAILED" then
        HandleFailure(castGUID, spellID, "UNIT_SPELLCAST_FAILED")
    elseif event == "UNIT_SPELLCAST_FAILED_QUIET" then
        HandleFailure(castGUID, spellID, "UNIT_SPELLCAST_FAILED_QUIET")
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        HandleInterrupted(castGUID, spellID, arg3, "UNIT_SPELLCAST_INTERRUPTED")
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        HandleChannelStop(castGUID, spellID, arg3)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        HandleEmpowerStop(castGUID, spellID, arg3, arg4)
    elseif event == "UNIT_SPELLCAST_STOP" then
        HandleStop(castGUID)
    end
end

RegisterDebugSpellEvents = function()
    if spellTrackingRegistered then
        return
    end
    debugSpellFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    debugSpellFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    debugSpellFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
    debugSpellFrame:RegisterEvent("PLAYER_STARTED_MOVING")
    debugSpellFrame:RegisterEvent("PLAYER_STOPPED_MOVING")
    debugSpellFrame:RegisterUnitEvent("UNIT_TARGET", "player")
    debugSpellFrame:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", "player")
    debugSpellFrame:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "player")
    debugSpellFrame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "player")
    debugSpellFrame:SetScript("OnEvent", OnSpellEvent)

    if LIVE_VISIBLE_UNIT_CC_ATTRIBUTION_ENABLED == true then
        heuristicUnitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        heuristicUnitFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        heuristicUnitFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
        heuristicUnitFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        heuristicUnitFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        heuristicUnitFrame:RegisterEvent("UNIT_AURA")
        heuristicUnitFrame:SetScript("OnEvent", OnHeuristicUnitEvent)
        RegisterStaticHeuristicLocWatchers()
    end
    spellTrackingRegistered = true
end

function PvPScalpel_EnableSpellTracking()
    RegisterDebugSpellEvents()
end

function PvPScalpel_DisableSpellTracking()
    if not spellTrackingRegistered then
        return
    end
    debugSpellFrame:UnregisterAllEvents()
    debugSpellFrame:SetScript("OnEvent", nil)
    heuristicUnitFrame:UnregisterAllEvents()
    heuristicUnitFrame:SetScript("OnEvent", nil)
    UnregisterAllHeuristicLocWatchers()
    spellTrackingRegistered = false
end

function PvPScalpel_EnableLocalSpellCaptureRuntime()
    RegisterDebugSpellEvents()
end

function PvPScalpel_WipeDebugState()
    local captureActive = IsSpellCaptureSessionActive()
    local chatFrame = FindDebugChatFrame()
    if chatFrame and chatFrame.Clear then
        chatFrame:Clear()
    end

    ResetHeuristicRuntimeForWorld()
    RefreshTargetSnapshot()

    if not captureActive then
        ResetRuntimeCaptureState()
        ResetSessionCollections()
    end

    if PvPScalpel_Log then
        if captureActive then
            PvPScalpel_Log("Debug state wiped. Active match capture was preserved.")
        else
            PvPScalpel_Log("Debug state wiped.")
        end
    end
end

function PvPScalpel_DisableLocalSpellCaptureRuntime()
    if not spellTrackingRegistered then
        return
    end
    debugSpellFrame:UnregisterAllEvents()
    debugSpellFrame:SetScript("OnEvent", nil)
    heuristicUnitFrame:UnregisterAllEvents()
    heuristicUnitFrame:SetScript("OnEvent", nil)
    UnregisterAllHeuristicLocWatchers()
    spellTrackingRegistered = false
end

debugInitFrame:RegisterEvent("PLAYER_LOGIN")
debugInitFrame:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then
        return
    end

    EnsureSessionCollections()
    ResetHeuristicRuntimeForWorld()
    RefreshRuntimeStateCache()
    RefreshMovementStateCache()
    RefreshTargetSnapshot()

    if PvPScalpel_Debug ~= true then
        CloseDebugChatFrame()
    end
end)
