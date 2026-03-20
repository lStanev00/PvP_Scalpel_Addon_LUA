-- Shared recorder state (globals used by recorder + main).

function PvPScalpel_BindRecorderStateToCurrentMatchSession()
    local store = PvPScalpel_EnsureCurrentMatchSessionStore()
    currentTimeline = store.currentTimeline
    timelineStart = store.timelineStart
    currentMatchKey = store.currentMatchKey
    currentTargetSnapshot = store.currentTargetSnapshot
    castTargetSnapshotByGuid = store.castTargetSnapshotByGuid
    currentCastRecords = store.currentCastRecords
    castRecordByGuid = store.castRecordByGuid
    lastMatchWinner = store.lastMatchWinner
    lastMatchDuration = store.lastMatchDuration
    currentSpellTotals = store.currentSpellTotals
    currentSpellTotalsBySource = store.currentSpellTotalsBySource
    currentInterruptSpellsBySource = store.currentInterruptSpellsBySource
    currentCastOutcomes = store.currentCastOutcomes
    currentBgGameType = store.currentBgGameType
    currentCaptureIntegrity = store.currentCaptureIntegrity
    lastTrinketCooldowns = store.lastTrinketCooldowns
    damageMeterStartSessionId = store.damageMeterStartSessionId
end

function PvPScalpel_SyncRecorderStateToCurrentMatchSession()
    local store = PvPScalpel_EnsureCurrentMatchSessionStore()
    store.currentTimeline = currentTimeline
    store.timelineStart = timelineStart
    store.currentMatchKey = currentMatchKey
    store.currentTargetSnapshot = currentTargetSnapshot
    store.castTargetSnapshotByGuid = castTargetSnapshotByGuid
    store.currentCastRecords = currentCastRecords
    store.castRecordByGuid = castRecordByGuid
    store.lastMatchWinner = lastMatchWinner
    store.lastMatchDuration = lastMatchDuration
    store.currentSpellTotals = currentSpellTotals
    store.currentSpellTotalsBySource = currentSpellTotalsBySource
    store.currentInterruptSpellsBySource = currentInterruptSpellsBySource
    store.currentCastOutcomes = currentCastOutcomes
    store.currentBgGameType = currentBgGameType
    store.currentCaptureIntegrity = currentCaptureIntegrity
    store.lastTrinketCooldowns = lastTrinketCooldowns
    store.damageMeterStartSessionId = damageMeterStartSessionId
end

PvPScalpel_BindRecorderStateToCurrentMatchSession()

trinketSlots = { 13, 14 }
