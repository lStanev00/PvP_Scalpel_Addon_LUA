local damageMeterEventFrame = CreateFrame("Frame")
local damageMeterCombatFrame = CreateFrame("Frame")
local damageMeterRetryTicker = nil
local damageMeterUpdaterTicker = nil
local damageMeterUpdaterInterval = 0.5
local damageMeterPending = false
local damageMeterAttempts = 0
local damageMeterSessions = {}
local damageMeterInCombat = false
local damageMeterExcludedSessionIds = {}
local PvPScalpel_DamageMeterStopUpdater
local damageMeterKickStatsBySource = {}
local damageMeterStartSessionId = 0
local damageMeterGlobalHighWaterSessionId = 0
local damageMeterListenersActive = false
local damageMeterMatchObservedSessions = {}
local damageMeterLastSourceTotals = {}
local damageMeterLastSpellTotals = {}
local damageMeterLastTargetTotals = {}
local UNKNOWN_INTERRUPT_SPELL_ID = 0
local DAMAGE_METER_COLLECTION_MODE = {
    SESSION = "session",
    SNAPSHOT = "snapshot",
}
local damageMeterCollectionMode = DAMAGE_METER_COLLECTION_MODE.SESSION

local function EnsureDamageMeterSessionStore()
    local store = PvPScalpel_EnsureCurrentMatchSessionStore()
    if type(store.damageMeterSessions) ~= "table" then
        store.damageMeterSessions = {}
    end
    if type(store.damageMeterExcludedSessionIds) ~= "table" then
        store.damageMeterExcludedSessionIds = {}
    end
    if type(store.damageMeterKickStatsBySource) ~= "table" then
        store.damageMeterKickStatsBySource = {}
    end
    if type(store.damageMeterMatchObservedSessions) ~= "table" then
        store.damageMeterMatchObservedSessions = {}
    end
    if type(store.damageMeterLastSourceTotals) ~= "table" then
        store.damageMeterLastSourceTotals = {}
    end
    if type(store.damageMeterLastSpellTotals) ~= "table" then
        store.damageMeterLastSpellTotals = {}
    end
    if type(store.damageMeterLastTargetTotals) ~= "table" then
        store.damageMeterLastTargetTotals = {}
    end
    return store
end

local function BindDamageMeterRuntimeToCurrentMatchSession()
    local store = EnsureDamageMeterSessionStore()
    damageMeterPending = store.damageMeterPending == true
    damageMeterAttempts = type(store.damageMeterAttempts) == "number" and store.damageMeterAttempts or 0
    damageMeterSessions = store.damageMeterSessions
    damageMeterInCombat = store.damageMeterInCombat == true
    damageMeterExcludedSessionIds = store.damageMeterExcludedSessionIds
    damageMeterKickStatsBySource = store.damageMeterKickStatsBySource
    damageMeterStartSessionId = type(store.damageMeterRuntimeStartSessionId) == "number" and store.damageMeterRuntimeStartSessionId or 0
    damageMeterGlobalHighWaterSessionId = type(store.damageMeterGlobalHighWaterSessionId) == "number" and store.damageMeterGlobalHighWaterSessionId or 0
    damageMeterListenersActive = store.damageMeterListenersActive == true
    damageMeterMatchObservedSessions = store.damageMeterMatchObservedSessions
    damageMeterLastSourceTotals = store.damageMeterLastSourceTotals
    damageMeterLastSpellTotals = store.damageMeterLastSpellTotals
    damageMeterLastTargetTotals = store.damageMeterLastTargetTotals
    if store.damageMeterCollectionMode == DAMAGE_METER_COLLECTION_MODE.SNAPSHOT then
        damageMeterCollectionMode = DAMAGE_METER_COLLECTION_MODE.SNAPSHOT
    else
        damageMeterCollectionMode = DAMAGE_METER_COLLECTION_MODE.SESSION
    end
end

local function SyncDamageMeterRuntimeScalars()
    local store = EnsureDamageMeterSessionStore()
    store.damageMeterPending = damageMeterPending == true
    store.damageMeterAttempts = damageMeterAttempts
    store.damageMeterInCombat = damageMeterInCombat == true
    store.damageMeterRuntimeStartSessionId = damageMeterStartSessionId
    store.damageMeterGlobalHighWaterSessionId = damageMeterGlobalHighWaterSessionId
    store.damageMeterListenersActive = damageMeterListenersActive == true
    store.damageMeterCollectionMode = damageMeterCollectionMode
    store.damageMeterSessions = damageMeterSessions
    store.damageMeterExcludedSessionIds = damageMeterExcludedSessionIds
    store.damageMeterKickStatsBySource = damageMeterKickStatsBySource
    store.damageMeterMatchObservedSessions = damageMeterMatchObservedSessions
    store.damageMeterLastSourceTotals = damageMeterLastSourceTotals
    store.damageMeterLastSpellTotals = damageMeterLastSpellTotals
    store.damageMeterLastTargetTotals = damageMeterLastTargetTotals
end

BindDamageMeterRuntimeToCurrentMatchSession()

local function PvPScalpel_DamageMeterNormalizeInterruptCount(value)
    if type(value) ~= "number" or value <= 0 then
        return 0
    end
    return math.floor(value)
end

local function PvPScalpel_DamageMeterResolveCollectionMode()
    if PvPScalpel_DamageMeterUseSessionAggregation and PvPScalpel_DamageMeterUseSessionAggregation() then
        return DAMAGE_METER_COLLECTION_MODE.SESSION
    end
    return DAMAGE_METER_COLLECTION_MODE.SNAPSHOT
end

local function PvPScalpel_DamageMeterUseSessionMode()
    return damageMeterCollectionMode == DAMAGE_METER_COLLECTION_MODE.SESSION
end

local function PvPScalpel_DamageMeterShouldCollect()
    -- Only collect while the recorder is actively tracking a PvP match.
    -- This avoids doing any DamageMeter work (and avoids touching secret values)
    -- in open world / non-PvP contexts.
    return type(currentMatchKey) == "string"
        and PvPScalpel_IsLocalSpellCaptureActive
        and PvPScalpel_IsLocalSpellCaptureActive()
end

local function PvPScalpel_DamageMeterShouldLog(message)
    if type(message) ~= "string" or message == "" then
        return false
    end
    if string.find(message, "DamageMeter: unavailable", 1, true) then
        return true
    end
    if string.find(message, "DamageMeter: timed out", 1, true) then
        return true
    end
    if string.find(message, "DamageMeter: snapshot skipped secret", 1, true) then
        return true
    end
    if string.find(message, "DamageMeter: interrupt source ", 1, true) then
        return true
    end
    return false
end

local function PvPScalpel_DamageMeterLog(message)
    if PvPScalpel_Log and PvPScalpel_DamageMeterShouldLog(message) then
        PvPScalpel_Log(message)
    end
end

local function PvPScalpel_DamageMeterAvailable()
    if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable) then
        return false
    end
    local ok, isAvailable, failureReason = pcall(C_DamageMeter.IsDamageMeterAvailable)
    if not ok then
        return false
    end
    if isAvailable ~= true and failureReason then
        PvPScalpel_DamageMeterLog("DamageMeter: unavailable (" .. tostring(failureReason) .. ")")
    end
    return isAvailable == true
end

local function PvPScalpel_DamageMeterRestricted()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    if not (C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState) then
        return false
    end
    if not (Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Combat) then
        return false
    end
    local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, Enum.AddOnRestrictionType.Combat)
    return ok and state and state > 0
end

local function PvPScalpel_DamageMeterCacheSession(sessionId, sessionName)
    if not sessionId then
        return
    end
    if not PvPScalpel_DamageMeterShouldCollect() then
        return
    end
    local entry = damageMeterSessions[sessionId]
    if not entry then
        entry = {
            sessionId = sessionId,
            name = sessionName or "",
            startTime = GetTime(),
        }
        damageMeterSessions[sessionId] = entry
        PvPScalpel_DamageMeterLog("DamageMeter: cached session " .. tostring(sessionId))
    end
end

local function PvPScalpel_DamageMeterRefreshSessions()
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then
        return {}
    end
    local sessions = C_DamageMeter.GetAvailableCombatSessions() or {}
    for i = 1, #sessions do
        local session = sessions[i]
        if session and type(session.sessionID) == "number" and session.sessionID > damageMeterGlobalHighWaterSessionId then
            damageMeterGlobalHighWaterSessionId = session.sessionID
            SyncDamageMeterRuntimeScalars()
        end
        PvPScalpel_DamageMeterCacheSession(session.sessionID, session.name)
    end
    return sessions
end

local function PvPScalpel_DamageMeterGetLatestSessionId()
    local sessions = PvPScalpel_DamageMeterRefreshSessions()
    if #sessions == 0 then
        return nil
    end
    return sessions[#sessions].sessionID
end

function PvPScalpel_DamageMeterMarkStart()
    local latestSessionId = PvPScalpel_DamageMeterGetLatestSessionId() or 0
    if latestSessionId < damageMeterGlobalHighWaterSessionId then
        latestSessionId = damageMeterGlobalHighWaterSessionId
    end
    damageMeterStartSessionId = latestSessionId
    damageMeterExcludedSessionIds = {}
    damageMeterKickStatsBySource = {}
    damageMeterMatchObservedSessions = {}
    damageMeterLastSourceTotals = {}
    damageMeterLastSpellTotals = {}
    damageMeterLastTargetTotals = {}
    damageMeterCollectionMode = PvPScalpel_DamageMeterResolveCollectionMode()
    SyncDamageMeterRuntimeScalars()
    if PvPScalpel_KicksWindowReset then
        PvPScalpel_KicksWindowReset()
    end
    PvPScalpel_DamageMeterRefreshSessions()
    PvPScalpel_DamageMeterLog("DamageMeter: start session " .. tostring(damageMeterStartSessionId))
    PvPScalpel_DamageMeterLog("DamageMeter: mode=" .. tostring(damageMeterCollectionMode))
end

function PvPScalpel_DamageMeterResetMatchBuffer()
    local store = EnsureDamageMeterSessionStore()
    store.damageMeterSessions = {}
    store.damageMeterExcludedSessionIds = {}
    store.damageMeterKickStatsBySource = {}
    store.damageMeterMatchObservedSessions = {}
    store.damageMeterLastSourceTotals = {}
    store.damageMeterLastSpellTotals = {}
    store.damageMeterLastTargetTotals = {}
    damageMeterSessions = store.damageMeterSessions
    damageMeterExcludedSessionIds = store.damageMeterExcludedSessionIds
    damageMeterKickStatsBySource = store.damageMeterKickStatsBySource
    damageMeterMatchObservedSessions = store.damageMeterMatchObservedSessions
    damageMeterLastSourceTotals = store.damageMeterLastSourceTotals
    damageMeterLastSpellTotals = store.damageMeterLastSpellTotals
    damageMeterLastTargetTotals = store.damageMeterLastTargetTotals
    damageMeterCollectionMode = DAMAGE_METER_COLLECTION_MODE.SESSION
    damageMeterStartSessionId = 0
    damageMeterPending = false
    damageMeterAttempts = 0
    SyncDamageMeterRuntimeScalars()
    if PvPScalpel_KicksWindowReset then
        PvPScalpel_KicksWindowReset()
    end
    PvPScalpel_DamageMeterStopUpdater()
    if damageMeterRetryTicker then
        damageMeterRetryTicker:Cancel()
        damageMeterRetryTicker = nil
    end
end

function PvPScalpel_DamageMeterExportRecoveryState()
    return {
        startSessionId = type(damageMeterStartSessionId) == "number" and damageMeterStartSessionId or 0,
        collectionMode = damageMeterCollectionMode,
        excludedSessionIds = PvPScalpel_DeepCopyPlainTable(damageMeterExcludedSessionIds or {}),
        matchObservedSessions = PvPScalpel_DeepCopyPlainTable(damageMeterMatchObservedSessions or {}),
        kickStatsBySource = PvPScalpel_DeepCopyPlainTable(damageMeterKickStatsBySource or {}),
        lastSourceTotals = PvPScalpel_DeepCopyPlainTable(damageMeterLastSourceTotals or {}),
        lastSpellTotals = PvPScalpel_DeepCopyPlainTable(damageMeterLastSpellTotals or {}),
        lastTargetTotals = PvPScalpel_DeepCopyPlainTable(damageMeterLastTargetTotals or {}),
    }
end

function PvPScalpel_DamageMeterRestoreRecoveryState(state)
    if type(state) ~= "table" then
        return false
    end

    local store = EnsureDamageMeterSessionStore()
    store.damageMeterSessions = {}
    store.damageMeterExcludedSessionIds = PvPScalpel_DeepCopyPlainTable(state.excludedSessionIds or {})
    store.damageMeterKickStatsBySource = PvPScalpel_DeepCopyPlainTable(state.kickStatsBySource or {})
    store.damageMeterMatchObservedSessions = PvPScalpel_DeepCopyPlainTable(state.matchObservedSessions or {})
    store.damageMeterLastSourceTotals = PvPScalpel_DeepCopyPlainTable(state.lastSourceTotals or {})
    store.damageMeterLastSpellTotals = PvPScalpel_DeepCopyPlainTable(state.lastSpellTotals or {})
    store.damageMeterLastTargetTotals = PvPScalpel_DeepCopyPlainTable(state.lastTargetTotals or {})
    damageMeterSessions = store.damageMeterSessions
    damageMeterExcludedSessionIds = store.damageMeterExcludedSessionIds
    damageMeterKickStatsBySource = store.damageMeterKickStatsBySource
    damageMeterMatchObservedSessions = store.damageMeterMatchObservedSessions
    damageMeterLastSourceTotals = store.damageMeterLastSourceTotals
    damageMeterLastSpellTotals = store.damageMeterLastSpellTotals
    damageMeterLastTargetTotals = store.damageMeterLastTargetTotals
    damageMeterStartSessionId = type(state.startSessionId) == "number" and state.startSessionId or 0
    damageMeterPending = false
    damageMeterAttempts = 0

    if state.collectionMode == DAMAGE_METER_COLLECTION_MODE.SESSION or state.collectionMode == DAMAGE_METER_COLLECTION_MODE.SNAPSHOT then
        damageMeterCollectionMode = state.collectionMode
    else
        damageMeterCollectionMode = PvPScalpel_DamageMeterResolveCollectionMode()
    end
    SyncDamageMeterRuntimeScalars()

    PvPScalpel_DamageMeterStopUpdater()
    if damageMeterRetryTicker then
        damageMeterRetryTicker:Cancel()
        damageMeterRetryTicker = nil
    end

    return true
end

local function PvPScalpel_DamageMeterStartUpdater()
    if damageMeterUpdaterTicker then
        return
    end
    damageMeterUpdaterTicker = C_Timer.NewTicker(damageMeterUpdaterInterval, function()
        if not PvPScalpel_DamageMeterShouldCollect() then
            return
        end
        PvPScalpel_DamageMeterRefreshSessions()
        if not damageMeterPending and not PvPScalpel_DamageMeterRestricted() then
            PvPScalpel_DamageMeterCollectInternal()
        end
    end)
end

PvPScalpel_DamageMeterStopUpdater = function()
    if damageMeterUpdaterTicker then
        damageMeterUpdaterTicker:Cancel()
        damageMeterUpdaterTicker = nil
    end
end

local function PvPScalpel_DamageMeterSelectSessions()
    local sessions = PvPScalpel_DamageMeterRefreshSessions()
    if #sessions == 0 then
        return {}
    end

    if not PvPScalpel_DamageMeterUseSessionMode() then
        local latestSnapshotSessionId = nil
        for i = 1, #sessions do
            local sessionId = sessions[i].sessionID
            if sessionId and not damageMeterExcludedSessionIds[sessionId] and sessionId > damageMeterStartSessionId then
                if not latestSnapshotSessionId or sessionId > latestSnapshotSessionId then
                    latestSnapshotSessionId = sessionId
                end
            end
        end

        if latestSnapshotSessionId then
            return { latestSnapshotSessionId }
        end
        return {}
    end

    local selected = {}
    for i = 1, #sessions do
        local sessionId = sessions[i].sessionID
        if sessionId and not damageMeterExcludedSessionIds[sessionId] then
            if damageMeterStartSessionId > 0 and sessionId >= damageMeterStartSessionId then
                table.insert(selected, sessionId)
            elseif damageMeterMatchObservedSessions[sessionId] then
                table.insert(selected, sessionId)
            end
        end
    end

    table.sort(selected, function(a, b)
        return a < b
    end)

    return selected
end

local function PvPScalpel_DamageMeterTakeSourceDelta(sessionId, kind, sourceGuid, currentTotal)
    if type(currentTotal) ~= "number" or currentTotal < 0 then
        return 0
    end

    local sessionBucket = damageMeterLastSourceTotals[sessionId]
    if not sessionBucket then
        sessionBucket = {}
        damageMeterLastSourceTotals[sessionId] = sessionBucket
    end
    local kindBucket = sessionBucket[kind]
    if not kindBucket then
        kindBucket = {}
        sessionBucket[kind] = kindBucket
    end

    local previous = kindBucket[sourceGuid]
    kindBucket[sourceGuid] = currentTotal
    if type(previous) ~= "number" then
        if damageMeterStartSessionId > 0 and sessionId == damageMeterStartSessionId then
            return 0
        end
        return currentTotal
    end
    if currentTotal > previous then
        return currentTotal - previous
    end
    return 0
end

local function PvPScalpel_DamageMeterTakeSpellDelta(sessionId, kind, sourceGuid, spellID, currentTotal)
    if type(currentTotal) ~= "number" or currentTotal < 0 then
        return 0
    end

    local sessionBucket = damageMeterLastSpellTotals[sessionId]
    if not sessionBucket then
        sessionBucket = {}
        damageMeterLastSpellTotals[sessionId] = sessionBucket
    end
    local kindBucket = sessionBucket[kind]
    if not kindBucket then
        kindBucket = {}
        sessionBucket[kind] = kindBucket
    end
    local sourceBucket = kindBucket[sourceGuid]
    if not sourceBucket then
        sourceBucket = {}
        kindBucket[sourceGuid] = sourceBucket
    end

    local previous = sourceBucket[spellID]
    sourceBucket[spellID] = currentTotal
    if type(previous) ~= "number" then
        if damageMeterStartSessionId > 0 and sessionId == damageMeterStartSessionId then
            return 0
        end
        return currentTotal
    end
    if currentTotal > previous then
        return currentTotal - previous
    end
    return 0
end

local function PvPScalpel_DamageMeterTakeTargetDelta(sessionId, kind, sourceGuid, spellID, targetName, currentTotal)
    if type(currentTotal) ~= "number" or currentTotal < 0 then
        return 0
    end

    local sessionBucket = damageMeterLastTargetTotals[sessionId]
    if not sessionBucket then
        sessionBucket = {}
        damageMeterLastTargetTotals[sessionId] = sessionBucket
    end
    local kindBucket = sessionBucket[kind]
    if not kindBucket then
        kindBucket = {}
        sessionBucket[kind] = kindBucket
    end
    local sourceBucket = kindBucket[sourceGuid]
    if not sourceBucket then
        sourceBucket = {}
        kindBucket[sourceGuid] = sourceBucket
    end
    local spellBucket = sourceBucket[spellID]
    if not spellBucket then
        spellBucket = {}
        sourceBucket[spellID] = spellBucket
    end

    local previous = spellBucket[targetName]
    spellBucket[targetName] = currentTotal
    if type(previous) ~= "number" then
        if damageMeterStartSessionId > 0 and sessionId == damageMeterStartSessionId then
            return 0
        end
        return currentTotal
    end
    if currentTotal > previous then
        return currentTotal - previous
    end
    return 0
end

local function PvPScalpel_DamageMeterResolveSourceAmount(sessionId, kind, sourceGuid, currentTotal)
    if type(currentTotal) ~= "number" or currentTotal < 0 then
        return 0
    end
    if PvPScalpel_DamageMeterUseSessionMode() then
        return PvPScalpel_DamageMeterTakeSourceDelta(sessionId, kind, sourceGuid, currentTotal)
    end
    return currentTotal
end

local function PvPScalpel_DamageMeterResolveSpellAmount(sessionId, kind, sourceGuid, spellID, currentTotal)
    if type(currentTotal) ~= "number" or currentTotal < 0 then
        return 0
    end
    if PvPScalpel_DamageMeterUseSessionMode() then
        return PvPScalpel_DamageMeterTakeSpellDelta(sessionId, kind, sourceGuid, spellID, currentTotal)
    end
    return currentTotal
end

local function PvPScalpel_DamageMeterResolveTargetAmount(sessionId, kind, sourceGuid, spellID, targetName, currentTotal)
    if type(currentTotal) ~= "number" or currentTotal < 0 then
        return 0
    end
    if PvPScalpel_DamageMeterUseSessionMode() then
        return PvPScalpel_DamageMeterTakeTargetDelta(sessionId, kind, sourceGuid, spellID, targetName, currentTotal)
    end
    return currentTotal
end

local function PvPScalpel_DamageMeterEnsureSpellEntry(spellTotals, spellID)
    if not spellTotals then
        return nil
    end
    local entry = spellTotals[spellID]
    if not entry then
        entry = {
            damage = 0,
            healing = 0,
            overheal = 0,
            absorbed = 0,
            hits = 0,
            crits = 0,
            targets = {},
            interrupts = 0,
            dispels = 0,
        }
        spellTotals[spellID] = entry
    end
    return entry
end

local function PvPScalpel_DamageMeterEnsureSourceEntry(sinkTotalsBySource, sourceGuid)
    if not sinkTotalsBySource then
        return nil
    end
    local sourceEntry = sinkTotalsBySource[sourceGuid]
    if not sourceEntry then
        sourceEntry = {}
        sinkTotalsBySource[sourceGuid] = sourceEntry
    end
    return sourceEntry
end

local function PvPScalpel_DamageMeterSetOrAccumulate(entry, fieldName, amount)
    if not entry or type(amount) ~= "number" then
        return
    end
    if PvPScalpel_DamageMeterUseSessionMode() then
        entry[fieldName] = (entry[fieldName] or 0) + amount
    else
        local current = entry[fieldName] or 0
        if amount > current then
            entry[fieldName] = amount
        end
    end
end

local function PvPScalpel_DamageMeterRecordSpellTotals(sessionId, damageMeterType, sourceGuid, kind, sinkTotals, sinkTotalsBySource, sinkInterruptsBySource)
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromID) then
        return false, 0
    end
    if issecretvalue and (issecretvalue(sessionId) or issecretvalue(damageMeterType) or issecretvalue(sourceGuid)) then
        return false, 0
    end
    local ok, sessionSource = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionId, damageMeterType, sourceGuid)
    if not ok then
        return false, 0
    end
    if issecretvalue and issecretvalue(sessionSource) then
        return false, 0
    end
    if not sessionSource or not sessionSource.combatSpells then
        return false, 0
    end
    if issecretvalue and issecretvalue(sessionSource.combatSpells) then
        return false, 0
    end

    local recorded = 0
    local summedAmount = 0
    for i = 1, #sessionSource.combatSpells do
        local spell = sessionSource.combatSpells[i]
        if spell then
            -- Only inspect the fields we use; nested details can include unit names, etc.
            if issecretvalue and (issecretvalue(spell.spellID) or issecretvalue(spell.totalAmount)) then
                return false, recorded
            end
            if spell.spellID and type(spell.totalAmount) == "number" and spell.totalAmount > 0 then
                local spellAmount = PvPScalpel_DamageMeterResolveSpellAmount(sessionId, kind, sourceGuid, spell.spellID, spell.totalAmount)
                if spellAmount > 0 then
                    local countAmount = PvPScalpel_DamageMeterNormalizeInterruptCount(spellAmount)
                    local entry = PvPScalpel_DamageMeterEnsureSpellEntry(sinkTotals, spell.spellID)
                    local sourceEntry = nil
                    local sourceBucket = PvPScalpel_DamageMeterEnsureSourceEntry(sinkTotalsBySource, sourceGuid)
                    if sourceBucket then
                        sourceEntry = PvPScalpel_DamageMeterEnsureSpellEntry(sourceBucket, spell.spellID)
                    end

                    if spell.combatSpellDetails ~= nil then
                        local details = spell.combatSpellDetails
                        if issecretvalue and issecretvalue(details) then
                            return false, recorded, summedAmount
                        end

                        local function RecordDetail(detail)
                            if not detail then return true end
                            if issecretvalue and (issecretvalue(detail) or issecretvalue(detail.unitName) or issecretvalue(detail.amount)) then
                                return false
                            end
                            if type(detail.unitName) == "string" and detail.unitName ~= ""
                                and type(detail.amount) == "number" and detail.amount > 0 then
                                local targetAmount = PvPScalpel_DamageMeterResolveTargetAmount(
                                    sessionId,
                                    kind,
                                    sourceGuid,
                                    spell.spellID,
                                    detail.unitName,
                                    detail.amount
                                )
                                if targetAmount <= 0 then
                                    return true
                                end
                                if entry then
                                    if PvPScalpel_DamageMeterUseSessionMode() then
                                        entry.targets[detail.unitName] = (entry.targets[detail.unitName] or 0) + targetAmount
                                    else
                                        local current = entry.targets[detail.unitName] or 0
                                        if targetAmount > current then
                                            entry.targets[detail.unitName] = targetAmount
                                        end
                                    end
                                end
                                if sourceEntry then
                                    if PvPScalpel_DamageMeterUseSessionMode() then
                                        sourceEntry.targets[detail.unitName] = (sourceEntry.targets[detail.unitName] or 0) + targetAmount
                                    else
                                        local current = sourceEntry.targets[detail.unitName] or 0
                                        if targetAmount > current then
                                            sourceEntry.targets[detail.unitName] = targetAmount
                                        end
                                    end
                                end
                            end
                            return true
                        end

                        if type(details) == "table" then
                            if details.unitName ~= nil or details.amount ~= nil then
                                if not RecordDetail(details) then
                                    return false, recorded, summedAmount
                                end
                            else
                                for detailIndex = 1, #details do
                                    if not RecordDetail(details[detailIndex]) then
                                        return false, recorded, summedAmount
                                    end
                                end
                            end
                        end
                    end

                    if kind == "interrupts" or kind == "dispels" then
                        if countAmount == 0 then
                            countAmount = 1
                        end
                    end

                    recorded = recorded + 1
                    if kind == "interrupts" or kind == "dispels" then
                        summedAmount = summedAmount + countAmount
                    else
                        summedAmount = summedAmount + spellAmount
                    end
                    if kind == "damage" then
                        if entry then
                            PvPScalpel_DamageMeterSetOrAccumulate(entry, "damage", spellAmount)
                            PvPScalpel_DamageMeterSetOrAccumulate(entry, "hits", 1)
                        end
                        if sourceEntry then
                            PvPScalpel_DamageMeterSetOrAccumulate(sourceEntry, "damage", spellAmount)
                            PvPScalpel_DamageMeterSetOrAccumulate(sourceEntry, "hits", 1)
                        end
                    elseif kind == "healing" then
                        if entry then
                            PvPScalpel_DamageMeterSetOrAccumulate(entry, "healing", spellAmount)
                            PvPScalpel_DamageMeterSetOrAccumulate(entry, "hits", 1)
                        end
                        if sourceEntry then
                            PvPScalpel_DamageMeterSetOrAccumulate(sourceEntry, "healing", spellAmount)
                            PvPScalpel_DamageMeterSetOrAccumulate(sourceEntry, "hits", 1)
                        end
                    elseif kind == "absorbs" then
                        if entry then
                            PvPScalpel_DamageMeterSetOrAccumulate(entry, "absorbed", spellAmount)
                            PvPScalpel_DamageMeterSetOrAccumulate(entry, "hits", 1)
                        end
                        if sourceEntry then
                            PvPScalpel_DamageMeterSetOrAccumulate(sourceEntry, "absorbed", spellAmount)
                            PvPScalpel_DamageMeterSetOrAccumulate(sourceEntry, "hits", 1)
                        end
                    elseif kind == "interrupts" or kind == "dispels" then
                        if kind == "interrupts" then
                            if entry then
                                PvPScalpel_DamageMeterSetOrAccumulate(entry, "interrupts", countAmount)
                            end
                            if sourceEntry then
                                PvPScalpel_DamageMeterSetOrAccumulate(sourceEntry, "interrupts", countAmount)
                            end
                            if sinkInterruptsBySource then
                                local bySource = sinkInterruptsBySource[sourceGuid]
                                if not bySource then
                                    bySource = {}
                                    sinkInterruptsBySource[sourceGuid] = bySource
                                end
                                if PvPScalpel_DamageMeterUseSessionMode() then
                                    bySource[spell.spellID] = (bySource[spell.spellID] or 0) + countAmount
                                else
                                    local currentCount = bySource[spell.spellID] or 0
                                    if countAmount > currentCount then
                                        bySource[spell.spellID] = countAmount
                                    end
                                end
                            end
                        else
                            if entry then
                                PvPScalpel_DamageMeterSetOrAccumulate(entry, "dispels", countAmount)
                            end
                            if sourceEntry then
                                PvPScalpel_DamageMeterSetOrAccumulate(sourceEntry, "dispels", countAmount)
                            end
                        end
                    end
                end
            end
        end
    end

    return true, recorded, summedAmount
end

local function PvPScalpel_DamageMeterCollectType(sessionId, damageMeterType, kind, sinkTotals, sinkTotalsBySource, sinkInterruptsBySource, sinkKickStatsBySource)
    local okSession, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionId, damageMeterType)
    if not okSession then
        return false
    end
    if issecretvalue and issecretvalue(session) then
        return false
    end
    if not session or not session.combatSources then
        return true
    end
    if issecretvalue and issecretvalue(session.combatSources) then
        return false
    end

    for i = 1, #session.combatSources do
        local source = session.combatSources[i]
        if source then
            if issecretvalue and (issecretvalue(source) or issecretvalue(source.sourceGUID) or issecretvalue(source.totalAmount)) then
                if PvPScalpel_DamageMeterUseSessionMode() then
                    return false
                end
                PvPScalpel_DamageMeterLog("DamageMeter: snapshot skipped secret source in session " .. tostring(sessionId))
            else
                local sourceGUID = source.sourceGUID
                if type(sourceGUID) == "string" and sourceGUID ~= "" then
                    local okType, _, summedAmount = PvPScalpel_DamageMeterRecordSpellTotals(
                        sessionId,
                        damageMeterType,
                        sourceGUID,
                        kind,
                        sinkTotals,
                        sinkTotalsBySource,
                        sinkInterruptsBySource
                    )
                    if not okType then
                        if PvPScalpel_DamageMeterUseSessionMode() then
                            return false
                        end
                        PvPScalpel_DamageMeterLog("DamageMeter: snapshot skipped source due secret spell details in session " .. tostring(sessionId))
                    elseif kind == "interrupts" then
                        local totalCasts = PvPScalpel_DamageMeterNormalizeInterruptCount(
                            PvPScalpel_DamageMeterResolveSourceAmount(sessionId, kind, sourceGUID, source.totalAmount or 0)
                        )
                        local capturedSpellInterrupts = PvPScalpel_DamageMeterNormalizeInterruptCount(summedAmount or 0)
                        if totalCasts > capturedSpellInterrupts and sinkInterruptsBySource then
                            local missingFromSpellBreakdown = totalCasts - capturedSpellInterrupts
                            if missingFromSpellBreakdown > 0 then
                                local bySource = sinkInterruptsBySource[sourceGUID]
                                if not bySource then
                                    bySource = {}
                                    sinkInterruptsBySource[sourceGUID] = bySource
                                end
                                if PvPScalpel_DamageMeterUseSessionMode() then
                                    bySource[UNKNOWN_INTERRUPT_SPELL_ID] = (bySource[UNKNOWN_INTERRUPT_SPELL_ID] or 0) + missingFromSpellBreakdown
                                else
                                    local currentUnknown = bySource[UNKNOWN_INTERRUPT_SPELL_ID] or 0
                                    if missingFromSpellBreakdown > currentUnknown then
                                        bySource[UNKNOWN_INTERRUPT_SPELL_ID] = missingFromSpellBreakdown
                                    end
                                end
                                if PvPScalpel_Debug then
                                    PvPScalpel_DamageMeterLog(
                                        "DamageMeter: interrupt source " .. tostring(sourceGUID)
                                            .. " has " .. tostring(missingFromSpellBreakdown)
                                            .. " interrupts without spellID detail"
                                    )
                                end
                            end
                        end
                        local successfulInterrupts = totalCasts
                        local kickSource = sinkKickStatsBySource or damageMeterKickStatsBySource
                        local kickEntry = kickSource[sourceGUID]
                        if not kickEntry then
                            kickEntry = { totalCasts = 0, successfulInterrupts = 0 }
                            kickSource[sourceGUID] = kickEntry
                        end
                        if PvPScalpel_DamageMeterUseSessionMode() then
                            kickEntry.totalCasts = kickEntry.totalCasts + totalCasts
                            kickEntry.successfulInterrupts = kickEntry.successfulInterrupts + successfulInterrupts
                        else
                            if totalCasts > (kickEntry.totalCasts or 0) then
                                kickEntry.totalCasts = totalCasts
                            end
                            if successfulInterrupts > (kickEntry.successfulInterrupts or 0) then
                                kickEntry.successfulInterrupts = successfulInterrupts
                            end
                        end
                    end
                end
            end
        end
    end

    return true
end

function PvPScalpel_DamageMeterLogKickSummary()
    if not PvPScalpel_Debug then
        return
    end
    if not damageMeterKickStatsBySource then
        return
    end

    local guidToName = {}
    local scoreboardGuids = {}
    if C_PvP and C_PvP.GetScoreInfo and GetNumBattlefieldScores then
        local totalPlayers = GetNumBattlefieldScores() or 0
        for i = 1, totalPlayers do
            local score = C_PvP.GetScoreInfo(i)
            if score and type(score.guid) == "string" and score.guid ~= "" then
                scoreboardGuids[score.guid] = true
                local playerName = score.name or score.playerName
                if type(playerName) == "string" and playerName ~= "" then
                    local shortName = playerName
                    local dash = shortName:find("-", 1, true)
                    if dash then
                        shortName = shortName:sub(1, dash - 1)
                    end
                    guidToName[score.guid] = shortName
                end
            end
        end
    end

    local rows = {}
    for sourceGUID, _ in pairs(scoreboardGuids) do
        local stats = damageMeterKickStatsBySource[sourceGUID]
        local totalCasts = 0
        local succeeded = 0
        if type(stats) == "table" then
            local rawTotal = stats.totalCasts
            local rawSucceeded = stats.successfulInterrupts
            if type(rawTotal) == "number" and rawTotal > 0 then
                totalCasts = rawTotal
            end
            if type(rawSucceeded) == "number" and rawSucceeded > 0 then
                succeeded = rawSucceeded
            end
        end
        if succeeded > totalCasts then
            succeeded = totalCasts
        end
        local failed = totalCasts - succeeded
        if failed < 0 then
            failed = 0
        end
        table.insert(rows, {
            name = guidToName[sourceGUID] or sourceGUID,
            totalCasts = totalCasts,
            succeeded = succeeded,
            failed = failed,
        })
    end

    for sourceGUID, stats in pairs(damageMeterKickStatsBySource) do
        if type(sourceGUID) == "string" and type(stats) == "table" and not scoreboardGuids[sourceGUID] then
            local totalCasts = 0
            local succeeded = 0
            local rawTotal = stats.totalCasts
            local rawSucceeded = stats.successfulInterrupts
            if type(rawTotal) == "number" and rawTotal > 0 then
                totalCasts = rawTotal
            end
            if type(rawSucceeded) == "number" and rawSucceeded > 0 then
                succeeded = rawSucceeded
            end
            if succeeded > totalCasts then
                succeeded = totalCasts
            end
            local failed = totalCasts - succeeded
            if failed < 0 then
                failed = 0
            end
            local displayName = guidToName[sourceGUID] or sourceGUID
            table.insert(rows, {
                name = displayName,
                totalCasts = totalCasts,
                succeeded = succeeded,
                failed = failed,
            })
        end
    end

    table.sort(rows, function(a, b)
        if a.totalCasts ~= b.totalCasts then
            return a.totalCasts > b.totalCasts
        end
        return a.name < b.name
    end)

    PvPScalpel_DamageMeterLog("Kick summary (casted / succeeded):")
    PvPScalpel_DamageMeterLog("  Note: failed kicks are computed in the desktop application.")
    if #rows == 0 then
        PvPScalpel_DamageMeterLog("  no interrupt sources in this match")
        return
    end
    for i = 1, #rows do
        local row = rows[i]
        PvPScalpel_DamageMeterLog(string.format("  %s - %d / %d", row.name, row.totalCasts, row.succeeded))
    end
end

function PvPScalpel_DamageMeterGetInterruptTotalsForSource(sourceGUID)
    if type(sourceGUID) ~= "string" or sourceGUID == "" then
        return 0, 0
    end
    local stats = damageMeterKickStatsBySource[sourceGUID]
    if type(stats) ~= "table" then
        return 0, 0
    end

    local total = PvPScalpel_DamageMeterNormalizeInterruptCount(stats.totalCasts)
    local succeeded = PvPScalpel_DamageMeterNormalizeInterruptCount(stats.successfulInterrupts)
    if succeeded > total then
        succeeded = total
    end
    return total, succeeded
end

local function PvPScalpel_DamageMeterCollectSession(sessionId)
    local pendingTotals = nil
    local pendingTotalsBySource = {}
    local pendingInterruptsBySource = {}
    local pendingKickStatsBySource = {}

    local kickStatsSink = damageMeterKickStatsBySource
    if not PvPScalpel_DamageMeterUseSessionMode() then
        kickStatsSink = pendingKickStatsBySource
    end

    local okDamage = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.DamageDone, "damage", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource, kickStatsSink)
    if not okDamage then return false end

    local okHeal = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.HealingDone, "healing", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource, kickStatsSink)
    if not okHeal then return false end

    local okAbs = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.Absorbs, "absorbs", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource, kickStatsSink)
    if not okAbs then return false end

    local okInt = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.Interrupts, "interrupts", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource, kickStatsSink)
    if not okInt then return false end

    local okDisp = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.Dispels, "dispels", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource, kickStatsSink)
    if not okDisp then return false end

    if PvPScalpel_DamageMeterUseSessionMode() then
        if PvPScalpel_MergeSpellTotalsBySource then
            PvPScalpel_MergeSpellTotalsBySource(pendingTotalsBySource)
        end
        if PvPScalpel_MergeInterruptSpellsBySource then
            PvPScalpel_MergeInterruptSpellsBySource(pendingInterruptsBySource)
        end
    else
        local hasSpellTotals = next(pendingTotalsBySource) ~= nil
        local hasInterruptSpells = next(pendingInterruptsBySource) ~= nil
        local hasKickStats = next(pendingKickStatsBySource) ~= nil

        if hasSpellTotals then
            if PvPScalpel_ReplaceSpellTotalsBySource then
                PvPScalpel_ReplaceSpellTotalsBySource(pendingTotalsBySource)
            elseif PvPScalpel_MergeSpellTotalsBySource then
                PvPScalpel_MergeSpellTotalsBySource(pendingTotalsBySource)
            end
            PvPScalpel_DamageMeterLog("DamageMeter: snapshot spell totals captured for session " .. tostring(sessionId))
        end

        if hasInterruptSpells then
            if PvPScalpel_ReplaceInterruptSpellsBySource then
                PvPScalpel_ReplaceInterruptSpellsBySource(pendingInterruptsBySource)
            elseif PvPScalpel_MergeInterruptSpellsBySource then
                PvPScalpel_MergeInterruptSpellsBySource(pendingInterruptsBySource)
            end
            PvPScalpel_DamageMeterLog("DamageMeter: snapshot interrupt spells captured for session " .. tostring(sessionId))
        end

        if hasKickStats then
            damageMeterKickStatsBySource = pendingKickStatsBySource
            SyncDamageMeterRuntimeScalars()
            PvPScalpel_DamageMeterLog("DamageMeter: snapshot kick totals captured for session " .. tostring(sessionId))
        end
    end

    return true
end

local function PvPScalpel_DamageMeterCollectInternal()
    if not PvPScalpel_DamageMeterShouldCollect() then
        return true
    end
    if not PvPScalpel_DamageMeterAvailable() then
        PvPScalpel_DamageMeterLog("DamageMeter: unavailable")
        return true
    end

    if PvPScalpel_DamageMeterRestricted() then
        PvPScalpel_DamageMeterLog("DamageMeter: restricted")
        return false
    end

    if PvPScalpel_DamageMeterUseSessionMode() then
        local sessions = PvPScalpel_DamageMeterSelectSessions()
        if #sessions == 0 then
            PvPScalpel_DamageMeterLog("DamageMeter: no sessions")
            return true
        end

        PvPScalpel_DamageMeterLog("DamageMeter: sessions=" .. tostring(#sessions))

        for _, sessionId in ipairs(sessions) do
            if not PvPScalpel_DamageMeterCollectSession(sessionId) then
                return false
            end
        end
    else
        local sessions = PvPScalpel_DamageMeterSelectSessions()
        if #sessions == 0 then
            PvPScalpel_DamageMeterLog("DamageMeter: no snapshot session")
            return true
        end
        PvPScalpel_DamageMeterLog("DamageMeter: snapshot sessions=" .. tostring(#sessions))
        for _, sessionId in ipairs(sessions) do
            if not PvPScalpel_DamageMeterCollectSession(sessionId) then
                return false
            end
        end
    end

    if PvPScalpel_KicksWindowHandleOwnerSuccessTotalUpdate then
        PvPScalpel_KicksWindowHandleOwnerSuccessTotalUpdate()
    end

    return true
end

function PvPScalpel_RequestDamageMeterTotals(onComplete)
    if not PvPScalpel_DamageMeterShouldCollect() then
        if onComplete then
            onComplete()
        end
        return
    end
    if damageMeterPending then
        if onComplete then
            onComplete()
        end
        return
    end

    damageMeterPending = true
    damageMeterAttempts = 0
    SyncDamageMeterRuntimeScalars()

    local function finalize()
        damageMeterPending = false
        SyncDamageMeterRuntimeScalars()
        if damageMeterRetryTicker then
            damageMeterRetryTicker:Cancel()
            damageMeterRetryTicker = nil
        end
        if onComplete then
            onComplete()
        end
    end

    if PvPScalpel_DamageMeterCollectInternal() then
        finalize()
        return
    end

    damageMeterRetryTicker = C_Timer.NewTicker(0.3, function()
        damageMeterAttempts = damageMeterAttempts + 1
        SyncDamageMeterRuntimeScalars()
        PvPScalpel_DamageMeterLog("DamageMeter: retry " .. tostring(damageMeterAttempts))
        if PvPScalpel_DamageMeterCollectInternal() then
            finalize()
            return
        end
        if damageMeterAttempts >= 60 then
            PvPScalpel_DamageMeterLog("DamageMeter: timed out")
            finalize()
        end
    end)
end

local function PvPScalpel_DamageMeterOnEvent(_, event, ...)
    if not PvPScalpel_DamageMeterShouldCollect() then
        return
    end
    if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        local _, sessionId = ...
        if sessionId then
            PvPScalpel_DamageMeterCacheSession(sessionId, "")
            if sessionId > damageMeterStartSessionId then
                damageMeterMatchObservedSessions[sessionId] = true
                SyncDamageMeterRuntimeScalars()
            end
        end
    elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        local latestSessionId = PvPScalpel_DamageMeterGetLatestSessionId()
        if latestSessionId and latestSessionId > damageMeterStartSessionId then
            damageMeterMatchObservedSessions[latestSessionId] = true
            SyncDamageMeterRuntimeScalars()
        end
    elseif event == "DAMAGE_METER_RESET" then
        local store = EnsureDamageMeterSessionStore()
        store.damageMeterSessions = {}
        store.damageMeterExcludedSessionIds = {}
        store.damageMeterKickStatsBySource = {}
        store.damageMeterMatchObservedSessions = {}
        store.damageMeterLastSourceTotals = {}
        store.damageMeterLastSpellTotals = {}
        store.damageMeterLastTargetTotals = {}
        damageMeterSessions = store.damageMeterSessions
        damageMeterExcludedSessionIds = store.damageMeterExcludedSessionIds
        damageMeterKickStatsBySource = store.damageMeterKickStatsBySource
        damageMeterMatchObservedSessions = store.damageMeterMatchObservedSessions
        damageMeterLastSourceTotals = store.damageMeterLastSourceTotals
        damageMeterLastSpellTotals = store.damageMeterLastSpellTotals
        damageMeterLastTargetTotals = store.damageMeterLastTargetTotals
        damageMeterCollectionMode = DAMAGE_METER_COLLECTION_MODE.SESSION
        damageMeterStartSessionId = 0
        damageMeterGlobalHighWaterSessionId = 0
        SyncDamageMeterRuntimeScalars()
    end
end

if damageMeterEventFrame then
    damageMeterEventFrame:SetScript("OnEvent", PvPScalpel_DamageMeterOnEvent)
end

if damageMeterCombatFrame then
    damageMeterCombatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if not PvPScalpel_DamageMeterShouldCollect() then
                return
            end
            damageMeterInCombat = true
            SyncDamageMeterRuntimeScalars()
            PvPScalpel_DamageMeterStartUpdater()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if not PvPScalpel_DamageMeterShouldCollect() then
                return
            end
            damageMeterInCombat = false
            SyncDamageMeterRuntimeScalars()
            PvPScalpel_DamageMeterStopUpdater()
            if not damageMeterPending then
                PvPScalpel_RequestDamageMeterTotals()
            end
        end
    end)
end

function PvPScalpel_DamageMeterEnableListeners()
    if damageMeterListenersActive then
        return
    end

    if damageMeterEventFrame then
        damageMeterEventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
        damageMeterEventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
        damageMeterEventFrame:RegisterEvent("DAMAGE_METER_RESET")
    end

    if damageMeterCombatFrame then
        damageMeterCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        damageMeterCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end

    damageMeterListenersActive = true
    SyncDamageMeterRuntimeScalars()
end

function PvPScalpel_DamageMeterDisableListeners()
    if not damageMeterListenersActive then
        return
    end

    if damageMeterEventFrame then
        damageMeterEventFrame:UnregisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
        damageMeterEventFrame:UnregisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
        damageMeterEventFrame:UnregisterEvent("DAMAGE_METER_RESET")
    end

    if damageMeterCombatFrame then
        damageMeterCombatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        damageMeterCombatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end

    PvPScalpel_DamageMeterStopUpdater()
    damageMeterInCombat = false
    damageMeterListenersActive = false
    SyncDamageMeterRuntimeScalars()
end
