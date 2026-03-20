PvP_Scalpel_CurrentMatchSession = PvP_Scalpel_CurrentMatchSession or {}

local CURRENT_MATCH_SESSION_SCHEMA_VERSION = 1

local function CreateDefaultSoloShuffleState()
    return {
        active = false,
        rounds = {},
        currentRound = nil,
        currentRoundIndex = 0,
        currentRoundStart = nil,
        currentRoundCastByGuid = nil,
        lastMatchState = nil,
        notes = {},
        saved = false,
    }
end

local function CreateDefaultRuntimeStateCache()
    return {
        isMounted = nil,
        isFlying = nil,
        isAdvancedFlyableArea = nil,
        isFlyableArea = nil,
        isGliding = nil,
        canGlide = nil,
    }
end

local function CreateDefaultMovementStateCache()
    return {
        isMoving = nil,
        lastStartedMovingAt = nil,
        lastStoppedMovingAt = nil,
    }
end

function PvPScalpel_CreateEmptyCurrentMatchSessionStore()
    return {
        schemaVersion = CURRENT_MATCH_SESSION_SCHEMA_VERSION,
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
        currentTimeline = nil,
        timelineStart = nil,
        currentMatchKey = nil,
        currentTargetSnapshot = nil,
        castTargetSnapshotByGuid = {},
        currentCastRecords = nil,
        castRecordByGuid = {},
        lastMatchWinner = nil,
        lastMatchDuration = nil,
        currentSpellTotals = nil,
        currentSpellTotalsBySource = nil,
        currentInterruptSpellsBySource = nil,
        currentCastOutcomes = nil,
        currentBgGameType = nil,
        currentCaptureIntegrity = nil,
        lastTrinketCooldowns = {},
        damageMeterStartSessionId = nil,
        isTracking = false,
        waitingForGateOpen = false,
        lastSavedMatchTime = nil,
        currentPlayerName = nil,
        soloShuffleState = CreateDefaultSoloShuffleState(),
        debugCastByGuid = {},
        resolvedCastByGuid = {},
        recentResolvedCastHistory = {},
        recentLocHistory = {},
        activeLocByKey = {},
        activeCastGuid = nil,
        targetSnapshotCache = nil,
        activeSpellCaptureSession = nil,
        heuristicRuntimeState = nil,
        runtimeStateCache = CreateDefaultRuntimeStateCache(),
        movementStateCache = CreateDefaultMovementStateCache(),
        damageMeterPending = false,
        damageMeterAttempts = 0,
        damageMeterSessions = {},
        damageMeterInCombat = false,
        damageMeterExcludedSessionIds = {},
        damageMeterKickStatsBySource = {},
        damageMeterRuntimeStartSessionId = 0,
        damageMeterGlobalHighWaterSessionId = 0,
        damageMeterListenersActive = false,
        damageMeterMatchObservedSessions = {},
        damageMeterLastSourceTotals = {},
        damageMeterLastSpellTotals = {},
        damageMeterLastTargetTotals = {},
        damageMeterCollectionMode = "session",
    }
end

function PvPScalpel_EnsureCurrentMatchSessionStore()
    if type(PvP_Scalpel_CurrentMatchSession) ~= "table" then
        PvP_Scalpel_CurrentMatchSession = PvPScalpel_CreateEmptyCurrentMatchSessionStore()
    end

    local store = PvP_Scalpel_CurrentMatchSession
    if store.schemaVersion ~= CURRENT_MATCH_SESSION_SCHEMA_VERSION then
        store = PvPScalpel_CreateEmptyCurrentMatchSessionStore()
        PvP_Scalpel_CurrentMatchSession = store
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
    if type(store.castTargetSnapshotByGuid) ~= "table" then
        store.castTargetSnapshotByGuid = {}
    end
    if type(store.castRecordByGuid) ~= "table" then
        store.castRecordByGuid = {}
    end
    if type(store.lastTrinketCooldowns) ~= "table" then
        store.lastTrinketCooldowns = {}
    end
    if type(store.soloShuffleState) ~= "table" then
        store.soloShuffleState = CreateDefaultSoloShuffleState()
    end
    if type(store.soloShuffleState.rounds) ~= "table" then
        store.soloShuffleState.rounds = {}
    end
    if type(store.soloShuffleState.notes) ~= "table" then
        store.soloShuffleState.notes = {}
    end
    if type(store.debugCastByGuid) ~= "table" then
        store.debugCastByGuid = {}
    end
    if type(store.resolvedCastByGuid) ~= "table" then
        store.resolvedCastByGuid = {}
    end
    if type(store.recentResolvedCastHistory) ~= "table" then
        store.recentResolvedCastHistory = {}
    end
    if type(store.recentLocHistory) ~= "table" then
        store.recentLocHistory = {}
    end
    if type(store.activeLocByKey) ~= "table" then
        store.activeLocByKey = {}
    end
    if type(store.runtimeStateCache) ~= "table" then
        store.runtimeStateCache = CreateDefaultRuntimeStateCache()
    end
    if type(store.movementStateCache) ~= "table" then
        store.movementStateCache = CreateDefaultMovementStateCache()
    end
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
    if type(store.damageMeterPending) ~= "boolean" then
        store.damageMeterPending = false
    end
    if type(store.damageMeterAttempts) ~= "number" then
        store.damageMeterAttempts = 0
    end
    if type(store.damageMeterInCombat) ~= "boolean" then
        store.damageMeterInCombat = false
    end
    if type(store.damageMeterRuntimeStartSessionId) ~= "number" then
        store.damageMeterRuntimeStartSessionId = 0
    end
    if type(store.damageMeterGlobalHighWaterSessionId) ~= "number" then
        store.damageMeterGlobalHighWaterSessionId = 0
    end
    if type(store.damageMeterListenersActive) ~= "boolean" then
        store.damageMeterListenersActive = false
    end
    if type(store.damageMeterCollectionMode) ~= "string" or store.damageMeterCollectionMode == "" then
        store.damageMeterCollectionMode = "session"
    end

    return store
end

function PvPScalpel_ResetCurrentMatchSessionStore(reason)
    local store = PvPScalpel_CreateEmptyCurrentMatchSessionStore()
    if type(reason) == "string" and reason ~= "" then
        table.insert(store.notes, reason)
    end
    PvP_Scalpel_CurrentMatchSession = store
    return store
end
