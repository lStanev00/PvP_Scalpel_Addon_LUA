PvP_Scalpel_DB = PvP_Scalpel_DB or {}
PvP_Scalpel_InteruptSpells = PvP_Scalpel_InteruptSpells or {}
PvP_Scalpel_GC = PvP_Scalpel_GC or {}
PvP_Scalpel_ActiveMatchRecovery = PvP_Scalpel_ActiveMatchRecovery or {}

local ACTIVE_MATCH_RECOVERY_SCHEMA_VERSION = 1
local RELOAD_RECOVERY_DURATION_TOLERANCE_SECONDS = 5.0

local function CreateEmptyActiveMatchRecoveryStore()
    return {
        schemaVersion = ACTIVE_MATCH_RECOVERY_SCHEMA_VERSION,
        active = false,
        matchKey = "",
        format = "",
        mapName = "",
        bgGameType = nil,
        isRatedSoloShuffle = false,
        lastSeenMatchDurationSeconds = -1,
        captureStartOffsetSeconds = -1,
        reloadRecoveryCount = 0,
        spellCapture = nil,
        aggregates = {
            spellTotalsBySource = {},
            interruptSpellsBySource = {},
        },
        damageMeter = nil,
        soloShuffle = nil,
        notes = {},
    }
end

local function EnsureActiveMatchRecoveryStore()
    if type(PvP_Scalpel_ActiveMatchRecovery) ~= "table" then
        PvP_Scalpel_ActiveMatchRecovery = CreateEmptyActiveMatchRecoveryStore()
    end

    local store = PvP_Scalpel_ActiveMatchRecovery
    if store.schemaVersion ~= ACTIVE_MATCH_RECOVERY_SCHEMA_VERSION then
        store = CreateEmptyActiveMatchRecoveryStore()
        PvP_Scalpel_ActiveMatchRecovery = store
    end
    if type(store.aggregates) ~= "table" then
        store.aggregates = {
            spellTotalsBySource = {},
            interruptSpellsBySource = {},
        }
    end
    if type(store.aggregates.spellTotalsBySource) ~= "table" then
        store.aggregates.spellTotalsBySource = {}
    end
    if type(store.aggregates.interruptSpellsBySource) ~= "table" then
        store.aggregates.interruptSpellsBySource = {}
    end
    if type(store.notes) ~= "table" then
        store.notes = {}
    end
    if type(store.reloadRecoveryCount) ~= "number" then
        store.reloadRecoveryCount = 0
    end
    if type(store.lastSeenMatchDurationSeconds) ~= "number" then
        store.lastSeenMatchDurationSeconds = -1
    end
    if type(store.captureStartOffsetSeconds) ~= "number" then
        store.captureStartOffsetSeconds = -1
    end
    return store
end

local function AppendActiveRecoveryNote(store, note)
    if type(store) ~= "table" or type(note) ~= "string" or note == "" then
        return
    end
    if type(store.notes) ~= "table" then
        store.notes = {}
    end
    for i = 1, #store.notes do
        if store.notes[i] == note then
            return
        end
    end
    table.insert(store.notes, note)
end

local function GetCurrentMapName()
    if type(GetRealZoneText) ~= "function" then
        return nil
    end
    local ok, mapName = pcall(GetRealZoneText)
    if ok and type(mapName) == "string" and mapName ~= "" then
        return mapName
    end
    return nil
end

local function IsKnownPvpFormat(formatName)
    return type(formatName) == "string" and formatName ~= "" and formatName ~= "Unknown Format"
end

local function GetCurrentFormatCheck()
    if PvPScalpel_FormatChecker then
        return PvPScalpel_FormatChecker()
    end
    return "Unknown Format"
end

local function GetCurrentLiveMatchDurationSeconds()
    if PvPScalpel_GetLiveMatchDurationSeconds then
        return PvPScalpel_GetLiveMatchDurationSeconds()
    end
    return -1
end

local function IsLocalSpellCaptureRunning()
    return PvPScalpel_IsLocalSpellCaptureActive and PvPScalpel_IsLocalSpellCaptureActive()
end

local function SnapshotSoloShuffleRecoveryState()
    if type(soloShuffleState) ~= "table" then
        return nil
    end
    return {
        active = soloShuffleState.active == true,
        rounds = PvPScalpel_DeepCopyPlainTable(soloShuffleState.rounds or {}),
        currentRoundIndex = type(soloShuffleState.currentRoundIndex) == "number" and soloShuffleState.currentRoundIndex or 0,
        currentRound = PvPScalpel_DeepCopyPlainTable(soloShuffleState.currentRound),
        currentRoundStart = type(soloShuffleState.currentRoundStart) == "number" and soloShuffleState.currentRoundStart or nil,
        lastMatchState = soloShuffleState.lastMatchState,
        notes = PvPScalpel_DeepCopyPlainTable(soloShuffleState.notes or {}),
        saved = soloShuffleState.saved == true,
    }
end

local function RestoreSoloShuffleRecoveryState(snapshot)
    if type(snapshot) ~= "table" or snapshot.active ~= true then
        if PvPScalpel_ResetSoloShuffleState then
            PvPScalpel_ResetSoloShuffleState()
        end
        return
    end

    soloShuffleState.active = true
    soloShuffleState.rounds = PvPScalpel_DeepCopyPlainTable(snapshot.rounds or {})
    soloShuffleState.currentRoundIndex = type(snapshot.currentRoundIndex) == "number" and snapshot.currentRoundIndex or 0
    soloShuffleState.currentRound = PvPScalpel_DeepCopyPlainTable(snapshot.currentRound)
    soloShuffleState.currentRoundStart = type(snapshot.currentRoundStart) == "number" and snapshot.currentRoundStart or nil
    soloShuffleState.currentRoundCastByGuid = nil
    soloShuffleState.lastMatchState = snapshot.lastMatchState
    soloShuffleState.notes = PvPScalpel_DeepCopyPlainTable(snapshot.notes or {})
    soloShuffleState.saved = snapshot.saved == true
end

local function BuildRecoveryElapsedCaptureSeconds(store, liveDurationSeconds)
    if type(store) ~= "table" then
        return nil
    end

    if type(store.captureStartOffsetSeconds) == "number"
        and store.captureStartOffsetSeconds >= 0
        and type(liveDurationSeconds) == "number"
        and liveDurationSeconds >= 0 then
        return math.max(0, liveDurationSeconds - store.captureStartOffsetSeconds)
    end

    local spellCapture = store.spellCapture
    if type(spellCapture) == "table"
        and type(spellCapture.elapsedCaptureSeconds) == "number"
        and spellCapture.elapsedCaptureSeconds >= 0 then
        return spellCapture.elapsedCaptureSeconds
    end

    return nil
end

local function ValidateActiveMatchRecoveryStore(store, formatCheck, mapName, bgGameType, liveDurationSeconds)
    if type(store) ~= "table" or store.active ~= true then
        return false, "checkpoint_missing_on_mid_match_load"
    end
    if type(store.matchKey) ~= "string" or store.matchKey == "" then
        return false, "checkpoint_missing_on_mid_match_load"
    end
    if type(formatCheck) == "string" and formatCheck ~= "" and formatCheck ~= store.format then
        return false, "stale_checkpoint_discarded"
    end
    if type(mapName) == "string" and mapName ~= ""
        and type(store.mapName) == "string" and store.mapName ~= ""
        and mapName ~= store.mapName then
        return false, "stale_checkpoint_discarded"
    end
    if type(bgGameType) == "string" and bgGameType ~= ""
        and type(store.bgGameType) == "string" and store.bgGameType ~= ""
        and bgGameType ~= store.bgGameType then
        return false, "stale_checkpoint_discarded"
    end
    if type(liveDurationSeconds) == "number" and liveDurationSeconds >= 0
        and type(store.lastSeenMatchDurationSeconds) == "number" and store.lastSeenMatchDurationSeconds >= 0
        and liveDurationSeconds + RELOAD_RECOVERY_DURATION_TOLERANCE_SECONDS < store.lastSeenMatchDurationSeconds then
        return false, "stale_checkpoint_discarded"
    end
    return true, nil
end

function PvPScalpel_ClearActiveMatchRecovery(reason)
    local store = CreateEmptyActiveMatchRecoveryStore()
    if type(reason) == "string" and reason ~= "" then
        AppendActiveRecoveryNote(store, reason)
    end
    PvP_Scalpel_ActiveMatchRecovery = store
end

function PvPScalpel_UpdateActiveMatchRecoveryCheckpoint(reason)
    if not IsLocalSpellCaptureRunning() then
        return
    end
    if type(currentMatchKey) ~= "string" or currentMatchKey == "" then
        return
    end

    local store = EnsureActiveMatchRecoveryStore()
    local formatCheck = GetCurrentFormatCheck()
    local mapName = GetCurrentMapName()
    local bgGameType = currentBgGameType
    if type(bgGameType) ~= "string" or bgGameType == "" then
        bgGameType = PvPScalpel_GetCurrentBgGameType and PvPScalpel_GetCurrentBgGameType() or nil
    end
    local liveDurationSeconds = GetCurrentLiveMatchDurationSeconds()
    local elapsedCaptureSeconds = PvPScalpel_GetLocalSpellCaptureElapsedSeconds and PvPScalpel_GetLocalSpellCaptureElapsedSeconds() or nil
    local captureStartOffsetSeconds = -1
    if type(liveDurationSeconds) == "number" and liveDurationSeconds >= 0
        and type(elapsedCaptureSeconds) == "number" and elapsedCaptureSeconds >= 0 then
        captureStartOffsetSeconds = liveDurationSeconds - elapsedCaptureSeconds
    end

    local spellCapture = PvPScalpel_ExportLocalSpellCaptureRecoveryState and PvPScalpel_ExportLocalSpellCaptureRecoveryState() or nil
    if type(spellCapture) == "table" then
        spellCapture.elapsedCaptureSeconds = type(elapsedCaptureSeconds) == "number" and elapsedCaptureSeconds or -1
    end

    local integrity = PvPScalpel_EnsureCaptureIntegrity and PvPScalpel_EnsureCaptureIntegrity() or nil

    store.active = true
    store.matchKey = currentMatchKey
    store.format = IsKnownPvpFormat(formatCheck) and formatCheck or ""
    store.mapName = type(mapName) == "string" and mapName or ""
    store.bgGameType = type(bgGameType) == "string" and bgGameType ~= "" and bgGameType or nil
    store.isRatedSoloShuffle = PvPScalpel_IsRatedSoloShuffle and PvPScalpel_IsRatedSoloShuffle() or false
    store.lastSeenMatchDurationSeconds = type(liveDurationSeconds) == "number" and liveDurationSeconds or -1
    store.captureStartOffsetSeconds = captureStartOffsetSeconds
    store.reloadRecoveryCount = type(integrity) == "table" and type(integrity.reloadRecoveryCount) == "number" and integrity.reloadRecoveryCount or 0
    store.spellCapture = spellCapture
    store.aggregates = {
        spellTotalsBySource = PvPScalpel_DeepCopyPlainTable(currentSpellTotalsBySource or {}),
        interruptSpellsBySource = PvPScalpel_DeepCopyPlainTable(currentInterruptSpellsBySource or {}),
    }
    store.damageMeter = PvPScalpel_DamageMeterExportRecoveryState and PvPScalpel_DamageMeterExportRecoveryState() or nil
    store.soloShuffle = SnapshotSoloShuffleRecoveryState()
    store.notes = type(integrity) == "table" and PvPScalpel_DeepCopyPlainTable(integrity.notes or {}) or {}
    AppendActiveRecoveryNote(store, reason)
end

local function RestoreActiveMatchRecovery(formatCheck, mapName, bgGameType)
    local store = EnsureActiveMatchRecoveryStore()
    local liveDurationSeconds = GetCurrentLiveMatchDurationSeconds()
    local isValid, failureNote = ValidateActiveMatchRecoveryStore(store, formatCheck, mapName, bgGameType, liveDurationSeconds)
    if isValid ~= true then
        if store.active == true then
            PvPScalpel_ClearActiveMatchRecovery(failureNote)
        end
        return false, failureNote
    end

    local spellCapture = store.spellCapture
    local elapsedCaptureSeconds = BuildRecoveryElapsedCaptureSeconds(store, liveDurationSeconds)
    local spellSessionRestored = PvPScalpel_RestoreLocalSpellCaptureSession
        and PvPScalpel_RestoreLocalSpellCaptureSession(spellCapture, elapsedCaptureSeconds)

    if spellSessionRestored ~= true then
        PvPScalpel_ClearActiveMatchRecovery("stale_checkpoint_discarded")
        return false, "stale_checkpoint_discarded"
    end

    currentMatchKey = store.matchKey
    currentSpellTotalsBySource = PvPScalpel_DeepCopyPlainTable(store.aggregates and store.aggregates.spellTotalsBySource or {})
    currentInterruptSpellsBySource = PvPScalpel_DeepCopyPlainTable(store.aggregates and store.aggregates.interruptSpellsBySource or {})
    currentBgGameType = store.bgGameType
    PvPScalpel_IsTracking = true
    PvPScalpel_WaitingForGateOpen = false

    RestoreSoloShuffleRecoveryState(store.soloShuffle)

    local damageMeterRestored = PvPScalpel_DamageMeterRestoreRecoveryState
        and PvPScalpel_DamageMeterRestoreRecoveryState(store.damageMeter)
        or false

    if PvPScalpel_RegisterRuntimeListeners then
        PvPScalpel_RegisterRuntimeListeners()
    end

    PvPScalpel_ResetCaptureIntegrity()
    local integrity = PvPScalpel_EnsureCaptureIntegrity()
    local storedNotes = type(store.notes) == "table" and store.notes or {}
    for i = 1, #storedNotes do
        local note = storedNotes[i]
        PvPScalpel_MarkCaptureIntegrity(nil, note)
        if note == "recovered_after_reload" then
            integrity.resumedAfterReload = true
        elseif note == "started_mid_match" then
            integrity.startedMidMatch = true
        elseif note == "spell_session_restored" then
            integrity.spellSessionRestored = true
        elseif note == "damage_meter_restored" then
            integrity.damageMeterRestored = true
        elseif note == "checkpoint_missing_on_mid_match_load"
            or note == "stale_checkpoint_discarded"
            or note == "open_casts_dropped_on_reload" then
            integrity.hasEventGap = true
        end
    end
    integrity.resumedAfterReload = true
    integrity.checkpointRestored = true
    integrity.spellSessionRestored = true
    integrity.damageMeterRestored = damageMeterRestored == true
    integrity.hasEventGap = true
    integrity.reloadRecoveryCount = (type(store.reloadRecoveryCount) == "number" and store.reloadRecoveryCount or 0) + 1
    PvPScalpel_MarkCaptureIntegrity("resumedAfterReload", "recovered_after_reload")
    PvPScalpel_MarkCaptureIntegrity("checkpointRestored")
    PvPScalpel_MarkCaptureIntegrity("spellSessionRestored", "spell_session_restored")
    if damageMeterRestored == true then
        PvPScalpel_MarkCaptureIntegrity("damageMeterRestored", "damage_meter_restored")
    end
    if type(spellCapture) == "table" and type(spellCapture.unresolvedCastCount) == "number" and spellCapture.unresolvedCastCount > 0 then
        PvPScalpel_MarkCaptureIntegrity(nil, "open_casts_dropped_on_reload")
    end

    PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("recovered_after_reload")
    PvPScalpel_NotifyUser("Session recovered after UI reload. Match capture resumed with gap markers.")
    return true, nil
end

local function StartMidMatchDegradedCapture(reasonNote)
    PvPScalpel_BeginMatchCapture("PLAYER_ENTERING_WORLD_MID_MATCH")
    PvPScalpel_WaitingForGateOpen = false

    if PvPScalpel_IsRatedSoloShuffle and PvPScalpel_IsRatedSoloShuffle() then
        if type(soloShuffleState) ~= "table" or soloShuffleState.active ~= true then
            PvPScalpel_StartSoloShuffleSession()
        end
        PvPScalpel_HandleSoloShuffleStateChange()
    else
        PvPScalpel_ResetSoloShuffleState()
    end

    local integrity = PvPScalpel_EnsureCaptureIntegrity()
    integrity.startedMidMatch = true
    integrity.hasEventGap = true
    PvPScalpel_MarkCaptureIntegrity("startedMidMatch", "started_mid_match")
    if reasonNote == "stale_checkpoint_discarded" then
        PvPScalpel_MarkCaptureIntegrity(nil, "stale_checkpoint_discarded")
    else
        PvPScalpel_MarkCaptureIntegrity(nil, "checkpoint_missing_on_mid_match_load")
    end

    PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("started_mid_match")
    PvPScalpel_NotifyUser("Match already in progress after UI reload. Capture resumed mid-match and is marked degraded.")
end

local function TryHandleMidMatchRecovery(formatCheck)
    if not IsKnownPvpFormat(formatCheck) then
        return
    end
    if IsLocalSpellCaptureRunning() then
        return
    end
    if not PvPScalpel_IsLiveMatchStarted or PvPScalpel_IsLiveMatchStarted() ~= true then
        return
    end

    local mapName = GetCurrentMapName()
    local bgGameType = PvPScalpel_GetCurrentBgGameType and PvPScalpel_GetCurrentBgGameType() or nil
    local restored, failureNote = RestoreActiveMatchRecovery(formatCheck, mapName, bgGameType)
    if restored ~= true then
        StartMidMatchDegradedCapture(failureNote)
    end
end

if PvPScalpel_ApplyGarbageCollectionQueue then
    PvPScalpel_ApplyGarbageCollectionQueue()
end

function PvPScalpel_WriteMatchResult()
    C_Timer.After(0.5, function()
        local function finalizeMatch()
            if PvPScalpel_DamageMeterLogKickSummary then
                PvPScalpel_DamageMeterLogKickSummary()
            end

            PvPScalpel_Log("Capturing match summary...")
            if PvPScalpel_IsRatedSoloShuffle and PvPScalpel_IsRatedSoloShuffle() then
                PvPScalpel_HandleSoloShuffleStateChange()
                PvPScalpel_FinalizeSoloShuffleMatch()
            else
                PvPScalpel_TryCaptureMatch()
            end

            if PvPScalpel_UnregisterRuntimeListeners then
                PvPScalpel_UnregisterRuntimeListeners()
            end
            PvPScalpel_Log("Match record saved.")
        end

        if PvPScalpel_RequestDamageMeterTotals then
            PvPScalpel_RequestDamageMeterTotals(finalizeMatch)
        else
            finalizeMatch()
        end
    end)
end

function PvPScalpel_HandleCooldownRefresh()
    PvPScalpel_ScanRealCooldowns()
end

function PvPScalpel_HandleZoneLifecycle()
    local formatCheck = GetCurrentFormatCheck()
    local captureActive = IsLocalSpellCaptureRunning()

    if not IsKnownPvpFormat(formatCheck) then
        if captureActive or PvPScalpel_IsTracking then
            PvPScalpel_AbortActiveCapture("left_pvp_instance")
        else
            PvPScalpel_ClearActiveMatchRecovery("left_pvp_instance")
        end
        return
    end

    if not PvPScalpel_IsTracking then
        PvPScalpel_IsTracking = true
        PvPScalpel_Log(tostring(currentMatchKey))
        PvPScalpel_Log(("PvPScalpel: Tracking ON (%s)"):format(formatCheck))
    end

    TryHandleMidMatchRecovery(formatCheck)
end

function PvPScalpel_HandlePvpMatchActive()
    local alreadyCapturing = IsLocalSpellCaptureRunning()

    PvPScalpel_Log("PVP MATCH ACTIVE detected.")
    if not alreadyCapturing then
        PvPScalpel_WaitingForGateOpen = true

        if PvPScalpel_IsLiveMatchStarted() then
            PvPScalpel_BeginMatchCapture("PVP_MATCH_ACTIVE")
            PvPScalpel_WaitingForGateOpen = false
        else
            PvPScalpel_Log("Waiting for gates to open before starting capture...")
        end
    else
        PvPScalpel_WaitingForGateOpen = false
    end

    if PvPScalpel_IsRatedSoloShuffle and PvPScalpel_IsRatedSoloShuffle() then
        if type(soloShuffleState) ~= "table" or soloShuffleState.active ~= true then
            PvPScalpel_StartSoloShuffleSession()
            PvPScalpel_Log("Solo Shuffle: session started")
        end
        PvPScalpel_HandleSoloShuffleStateChange()
    else
        PvPScalpel_ResetSoloShuffleState()
    end
end

function PvPScalpel_HandlePvpMatchComplete(winner, duration)
    PvPScalpel_WaitingForGateOpen = false
    PvPScalpel_Log(string.format("PVP MATCH COMPLETE. Winner: %s | Duration: %s", tostring(winner), tostring(duration)))

    lastMatchWinner = nil
    if type(duration) == "number" and duration >= 0 then
        lastMatchDuration = duration
    else
        lastMatchDuration = nil
    end
    local factionIndex = GetBattlefieldArenaFaction and GetBattlefieldArenaFaction() or nil
    if factionIndex ~= nil then
        local enemyFactionIndex = (factionIndex + 1) % 2
        if winner == factionIndex then
            lastMatchWinner = "victory"
        elseif winner == enemyFactionIndex then
            lastMatchWinner = "defeat"
        else
            lastMatchWinner = "draw"
        end
    else
        lastMatchWinner = "draw"
    end

    PvPScalpel_WriteMatchResult()
end

function PvPScalpel_HandlePvpMatchStateChanged()
    if PvPScalpel_WaitingForGateOpen and PvPScalpel_IsLiveMatchStarted() then
        PvPScalpel_BeginMatchCapture("PVP_MATCH_STATE_CHANGED")
        PvPScalpel_WaitingForGateOpen = false
    end

    if PvPScalpel_IsRatedSoloShuffle and PvPScalpel_IsRatedSoloShuffle() then
        PvPScalpel_HandleSoloShuffleStateChange()
    end
end

function PvPScalpel_HandleTrinketCooldownEvent(_event)
    return
end

local recoveryLogoutFrame = CreateFrame("Frame")
recoveryLogoutFrame:RegisterEvent("PLAYER_LOGOUT")
recoveryLogoutFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" and IsLocalSpellCaptureRunning() then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("player_logout")
    end
end)

if PvPScalpel_RegisterStaticListeners then
    PvPScalpel_RegisterStaticListeners()
end
