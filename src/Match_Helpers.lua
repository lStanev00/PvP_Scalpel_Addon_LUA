PvPScalpel_IsTracking = PvPScalpel_IsTracking or false
PvPScalpel_WaitingForGateOpen = PvPScalpel_WaitingForGateOpen or false
PvPScalpel_LastSavedMatchTime = PvPScalpel_LastSavedMatchTime or nil
PvPScalpel_CurrentPlayerName = PvPScalpel_CurrentPlayerName or UnitFullName("player")

soloShuffleState = soloShuffleState or {
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

function PvPScalpel_ResetCaptureIntegrity()
    currentCaptureIntegrity = nil
end

function PvPScalpel_EnsureCaptureIntegrity()
    if type(currentCaptureIntegrity) ~= "table" then
        currentCaptureIntegrity = {
            captureVersion = 1,
            resumedAfterReload = false,
            startedMidMatch = false,
            checkpointRestored = false,
            spellSessionRestored = false,
            damageMeterRestored = false,
            hasEventGap = false,
            reloadRecoveryCount = 0,
            notes = {},
        }
    end
    if type(currentCaptureIntegrity.notes) ~= "table" then
        currentCaptureIntegrity.notes = {}
    end
    if type(currentCaptureIntegrity.reloadRecoveryCount) ~= "number" then
        currentCaptureIntegrity.reloadRecoveryCount = 0
    end
    return currentCaptureIntegrity
end

function PvPScalpel_MarkCaptureIntegrity(flagName, note)
    local integrity = PvPScalpel_EnsureCaptureIntegrity()
    if type(flagName) == "string" and flagName ~= "" then
        integrity[flagName] = true
    end
    if type(note) == "string" and note ~= "" then
        local notes = integrity.notes
        for i = 1, #notes do
            if notes[i] == note then
                return integrity
            end
        end
        table.insert(notes, note)
        if type(soloShuffleState) == "table" and soloShuffleState.active == true and PvPScalpel_SoloShuffleNote then
            PvPScalpel_SoloShuffleNote(note)
        end
    end
    return integrity
end

function PvPScalpel_BuildCaptureIntegrity()
    if type(currentCaptureIntegrity) ~= "table" then
        return nil
    end
    local integrity = PvPScalpel_EnsureCaptureIntegrity()
    local hasSignal = false
    for key, value in pairs(integrity) do
        if key ~= "captureVersion" and key ~= "notes" then
            if type(value) == "boolean" and value == true then
                hasSignal = true
                break
            end
            if key == "reloadRecoveryCount" and type(value) == "number" and value > 0 then
                hasSignal = true
                break
            end
        end
    end
    if hasSignal ~= true and #integrity.notes == 0 then
        return nil
    end
    return PvPScalpel_DeepCopyPlainTable(integrity)
end

function PvPScalpel_IsRatedSoloShuffle()
    return C_PvP and C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle()
end

local function PvPScalpel_ResetMatchStartMetadata()
    currentBgGameType = nil
end

local function PvPScalpel_CaptureMatchStartMetadata()
    PvPScalpel_ResetMatchStartMetadata()

    if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" then
        return
    end
    if not C_PvP or type(C_PvP.GetBattlegroundInfo) ~= "function" then
        return
    end
    if type(GetNumBattlegroundTypes) ~= "function" then
        return
    end

    local okMap, uiMapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or type(uiMapID) ~= "number" then
        return
    end

    local okCount, battlegroundCount = pcall(GetNumBattlegroundTypes)
    if not okCount or type(battlegroundCount) ~= "number" or battlegroundCount < 1 then
        return
    end

    for index = 1, battlegroundCount do
        local okInfo, battlegroundInfo = pcall(C_PvP.GetBattlegroundInfo, index)
        if okInfo and type(battlegroundInfo) == "table" and battlegroundInfo.mapID == uiMapID then
            local gameType = battlegroundInfo.gameType
            if type(gameType) == "string" and gameType ~= "" then
                currentBgGameType = gameType
            end
            return
        end
    end
end

function PvPScalpel_GetCurrentBgGameType()
    PvPScalpel_CaptureMatchStartMetadata()
    return currentBgGameType
end

function PvPScalpel_GetLiveMatchDurationSeconds()
    if C_PvP and C_PvP.GetActiveMatchDuration then
        local ok, duration = pcall(C_PvP.GetActiveMatchDuration)
        if ok and type(duration) == "number" and duration >= 0 then
            return duration
        end
    end
    return -1
end

local function PvPScalpel_ApplyMatchStartMetadata(matchDetails)
    if type(matchDetails) ~= "table" then
        return
    end
    if type(currentBgGameType) == "string" and currentBgGameType ~= "" then
        matchDetails.bgGameType = currentBgGameType
    end
end

function PvPScalpel_SoloShuffleNote(msg)
    if not soloShuffleState.notes then
        soloShuffleState.notes = {}
    end
    table.insert(soloShuffleState.notes, msg)
end

function PvPScalpel_ResetSoloShuffleState()
    soloShuffleState.active = false
    soloShuffleState.rounds = {}
    soloShuffleState.currentRound = nil
    soloShuffleState.currentRoundIndex = 0
    soloShuffleState.currentRoundStart = nil
    soloShuffleState.currentRoundCastByGuid = nil
    soloShuffleState.lastMatchState = nil
    soloShuffleState.notes = {}
    soloShuffleState.saved = false
end

function PvPScalpel_StartSoloShuffleSession()
    PvPScalpel_ResetSoloShuffleState()
    soloShuffleState.active = true
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("solo_shuffle_session_start")
    end
end

function PvPScalpel_StartSoloShuffleRound()
    if not soloShuffleState.active then return end
    if soloShuffleState.currentRound then return end

    if soloShuffleState.currentRoundIndex >= 6 then
        PvPScalpel_SoloShuffleNote("round_start_after_expected_count")
        return
    end

    soloShuffleState.currentRoundIndex = soloShuffleState.currentRoundIndex + 1
    local now = GetTime()
    local round = {
        roundIndex = soloShuffleState.currentRoundIndex,
        stateStartTime = now,
    }
    soloShuffleState.currentRound = round
    soloShuffleState.currentRoundStart = now
    soloShuffleState.currentRoundCastByGuid = {}
    if not PvPScalpel_IsTable(soloShuffleState.rounds) then
        soloShuffleState.rounds = {}
        PvPScalpel_SoloShuffleNote("rounds_table_reset")
    end
    table.insert(soloShuffleState.rounds, round)
    PvPScalpel_Log(("Solo Shuffle: Round %d start"):format(soloShuffleState.currentRoundIndex))
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("solo_shuffle_round_start")
    end
end

function PvPScalpel_PrepareScoreboardRead()
    if SetBattlefieldScoreFaction then
        pcall(SetBattlefieldScoreFaction, -1)
    end
    if RequestBattlefieldScoreData then
        pcall(RequestBattlefieldScoreData)
    end
end

function PvPScalpel_BuildInterruptSummary(sourceGUID)
    local total = 0
    local succeeded = 0
    if PvPScalpel_DamageMeterGetInterruptTotalsForSource then
        local rawTotal, rawSucceeded = PvPScalpel_DamageMeterGetInterruptTotalsForSource(sourceGUID)
        if type(rawTotal) == "number" and rawTotal > 0 then
            total = rawTotal
        end
        if type(rawSucceeded) == "number" and rawSucceeded > 0 then
            succeeded = rawSucceeded
        end
    end
    if succeeded > total then
        succeeded = total
    end
    return { total, succeeded }
end

function PvPScalpel_BuildScoreSnapshot()
    PvPScalpel_PrepareScoreboardRead()
    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then
        return nil, "scoreboard_empty"
    end

    local statColumns = {}
    if C_PvP and C_PvP.GetMatchPVPStatColumns then
        statColumns = C_PvP.GetMatchPVPStatColumns() or {}
    end

    local players = {}
    for i = 1, totalPlayers do
        local score = C_PvP.GetScoreInfo(i)
        if score then
            local playerName, realm = strsplit("-", score.name or "")
            realm = realm or GetRealmName()
            local statValues = {}
            if score.stats then
                for _, s in ipairs(score.stats) do
                    table.insert(statValues, {
                        pvpStatID = s.pvpStatID,
                        pvpStatValue = s.pvpStatValue,
                    })
                end
            end

            table.insert(players, {
                name = playerName,
                realm = PvPScalpel_Slugify(realm),
                guid = score.guid,
                classToken = score.classToken,
                talentSpec = score.talentSpec,
                faction = score.faction,
                rating = score.rating,
                ratingChange = score.ratingChange,
                prematchMMR = score.prematchMMR,
                postmatchMMR = score.postmatchMMR,
                damageDone = score.damageDone,
                healingDone = score.healingDone,
                killingBlows = score.killingBlows,
                deaths = score.deaths,
                interrupts = PvPScalpel_BuildInterruptSummary(score.guid),
                stats = statValues,
            })
        else
            PvPScalpel_SoloShuffleNote("nil_score_entry_" .. tostring(i))
        end
    end

    return {
        statColumns = statColumns,
        players = players,
    }
end

function PvPScalpel_EndSoloShuffleRound()
    if not soloShuffleState.active then return end

    local round = soloShuffleState.currentRound
    if not round then
        PvPScalpel_SoloShuffleNote("postround_without_active_round")
        return
    end

    local now = GetTime()
    round.stateEndTime = now
    round.duration = now - (round.stateStartTime or now)

    local snapshot, snapshotNote = PvPScalpel_BuildScoreSnapshot()
    if snapshot then
        round.scoreSnapshot = snapshot
    else
        PvPScalpel_SoloShuffleNote(snapshotNote or "round_snapshot_unavailable")
    end

    round.outcome = {
        result = "unknown",
        reason = "Per-round winner not exposed via safe APIs",
    }

    soloShuffleState.currentRound = nil
    soloShuffleState.currentRoundStart = nil
    soloShuffleState.currentRoundCastByGuid = nil
    PvPScalpel_Log(("Solo Shuffle: Round %d end (%.1fs)"):format(round.roundIndex, round.duration or 0))
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("solo_shuffle_round_end")
    end
end

function PvPScalpel_HandleSoloShuffleStateChange()
    if not soloShuffleState.active then return end
    if not (C_PvP and C_PvP.GetActiveMatchState) then
        PvPScalpel_SoloShuffleNote("match_state_unavailable")
        return
    end

    local state = C_PvP.GetActiveMatchState()
    if state == soloShuffleState.lastMatchState then
        return
    end
    soloShuffleState.lastMatchState = state

    if Enum and Enum.PvPMatchState then
        if state == Enum.PvPMatchState.Engaged then
            PvPScalpel_StartSoloShuffleRound()
        elseif state == Enum.PvPMatchState.PostRound then
            PvPScalpel_EndSoloShuffleRound()
        elseif state == Enum.PvPMatchState.Complete then
            if soloShuffleState.currentRound then
                PvPScalpel_EndSoloShuffleRound()
                PvPScalpel_SoloShuffleNote("forced_round_end_on_complete")
            end
        end
    else
        PvPScalpel_SoloShuffleNote("enum_pvp_match_state_unavailable")
    end
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("solo_shuffle_state_change")
    end
end

function PvPScalpel_IsLiveMatchStarted()
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
        local ok, started = pcall(C_PvP.HasMatchStarted)
        if ok and started == true then
            return true
        end
    end
    return false
end

function PvPScalpel_BeginMatchCapture(trigger)
    if PvPScalpel_IsLocalSpellCaptureActive and PvPScalpel_IsLocalSpellCaptureActive() then
        return
    end

    PvPScalpel_ResetCaptureIntegrity()
    PvPScalpel_Log("PVP capture START (" .. tostring(trigger) .. ")")
    if PvPScalpel_RegisterRuntimeListeners then
        PvPScalpel_RegisterRuntimeListeners()
    end
    PvPScalpel_StartTimeline()
    PvPScalpel_CaptureMatchStartMetadata()
    if PvPScalpel_DamageMeterResetMatchBuffer then
        PvPScalpel_DamageMeterResetMatchBuffer()
    end
    if PvPScalpel_DamageMeterMarkStart then
        PvPScalpel_DamageMeterMarkStart()
    end
    PvPScalpel_Log("Local spell capture STARTED after gates opened.")
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("capture_begin")
    end
end

function PvPScalpel_AbortActiveCapture(reason)
    local captureActive = PvPScalpel_IsLocalSpellCaptureActive and PvPScalpel_IsLocalSpellCaptureActive()
    if not captureActive and not PvPScalpel_IsTracking then
        return
    end

    if reason and PvPScalpel_Log then
        PvPScalpel_Log("PvPScalpel: aborting active capture (" .. tostring(reason) .. ")")
    end

    if PvPScalpel_UnregisterRuntimeListeners then
        PvPScalpel_UnregisterRuntimeListeners()
    end
    if PvPScalpel_DamageMeterResetMatchBuffer then
        PvPScalpel_DamageMeterResetMatchBuffer()
    end
    if PvPScalpel_StopTimeline then
        PvPScalpel_StopTimeline(nil)
    end

    PvPScalpel_ResetMatchStartMetadata()
    PvPScalpel_ResetSoloShuffleState()
    PvPScalpel_WaitingForGateOpen = false
    PvPScalpel_IsTracking = false
    PvPScalpel_ResetCaptureIntegrity()
    if PvPScalpel_ClearActiveMatchRecovery then
        PvPScalpel_ClearActiveMatchRecovery("abort_capture")
    end
end

function PvPScalpel_FinalizeCaptureBuffer()
    if PvPScalpel_DamageMeterResetMatchBuffer then
        PvPScalpel_DamageMeterResetMatchBuffer()
    end
    PvPScalpel_ResetMatchStartMetadata()
    PvPScalpel_IsTracking = false
    PvPScalpel_ResetCaptureIntegrity()
    if PvPScalpel_ClearActiveMatchRecovery then
        PvPScalpel_ClearActiveMatchRecovery("finalize_capture")
    end
end

function PvPScalpel_BuildSoloShufflePlayers()
    PvPScalpel_PrepareScoreboardRead()
    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then
        return {}
    end

    local players = {}
    local ownerName = PvPScalpel_CurrentPlayerName or UnitFullName("player")

    for i = 1, totalPlayers do
        local score = C_PvP.GetScoreInfo(i)
        if score then
            local playerName, realm = strsplit("-", score.name or "")
            realm = realm or GetRealmName()

            local entry = {
                name = playerName,
                realm = PvPScalpel_Slugify(realm),
                guid = score.guid,
                class = score.classToken,
                spec = score.talentSpec,
                faction = score.faction,
                rating = score.rating,
                ratingChange = score.ratingChange,
                prematchMMR = score.prematchMMR,
                postmatchMMR = score.postmatchMMR,
                damage = score.damageDone,
                healing = score.healingDone,
                kills = score.killingBlows,
                deaths = score.deaths,
                interrupts = PvPScalpel_BuildInterruptSummary(score.guid),
                MSS = PvPScalpel_GetMapStatsForIndex(i),
                isOwner = (ownerName == playerName),
            }

            if entry.isOwner then
                local pvpTalents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
                entry.pvpTalents = pvpTalents
            end

            table.insert(players, entry)
        else
            PvPScalpel_SoloShuffleNote("nil_score_entry_" .. tostring(i))
        end
    end

    return players
end

function PvPScalpel_FinalizeSoloShuffleMatch(attempt)
    if soloShuffleState.saved then return end

    attempt = attempt or 1
    local totalPlayers = GetNumBattlefieldScores()
    local statColumns = {}
    if C_PvP and C_PvP.GetMatchPVPStatColumns then
        statColumns = C_PvP.GetMatchPVPStatColumns() or {}
    end

    local scoreboardReady = (totalPlayers > 0)
    if not scoreboardReady and attempt <= 10 then
        C_Timer.After(0.3, function()
            PvPScalpel_FinalizeSoloShuffleMatch(attempt + 1)
        end)
        return
    end

    if not scoreboardReady then
        PvPScalpel_SoloShuffleNote("scoreboard_unavailable_after_retries")
    end

    local mapName = GetRealZoneText()
    local now = date("%Y-%m-%d %H:%M:%S")

    local match = {
        matchKey = currentMatchKey,
        telemetryVersion = 4.0,
        winner = lastMatchWinner,
        matchDetails = {
            timestamp = now,
            mapName = mapName,
            build = PvPScalpel_GetBuildInfoSnapshot(),
        },
        players = PvPScalpel_BuildSoloShufflePlayers(),
    }
    PvPScalpel_ApplyMatchStartMetadata(match.matchDetails)
    match.matchDetails.format = PvPScalpel_FormatChecker(match.players)

    match = PvPScalpel_StopTimeline(match)

    local playerGuid = GetPlayerGuid and GetPlayerGuid() or UnitGUID("player")
    local localPlayerScore = playerGuid and C_PvP.GetScoreInfoByPlayerGuid and C_PvP.GetScoreInfoByPlayerGuid(playerGuid) or nil

    local matchSummarySnapshot = nil
    if scoreboardReady then
        local snapshot = PvPScalpel_BuildScoreSnapshot()
        if snapshot then
            matchSummarySnapshot = snapshot
            matchSummarySnapshot.statColumns = statColumns
        end
    end

    if not PvPScalpel_IsTable(soloShuffleState.rounds) then
        PvPScalpel_SoloShuffleNote("rounds_table_missing")
        soloShuffleState.rounds = {}
    end
    local roundsCaptured = #soloShuffleState.rounds
    local integrityNotes = soloShuffleState.notes or {}
    if roundsCaptured > 6 then
        PvPScalpel_SoloShuffleNote("rounds_exceeded_expected")
        roundsCaptured = 6
    end

    match.soloShuffle = {
        matchKey = currentMatchKey,
        timestamp = now,
        format = "Solo Shuffle",
        mapName = mapName,
        duration = C_PvP.GetActiveMatchDuration and C_PvP.GetActiveMatchDuration() or 0,
        roundsExpected = 6,
        roundsCaptured = roundsCaptured,
        rounds = soloShuffleState.rounds,
        matchSummary = {
            statColumns = matchSummarySnapshot and matchSummarySnapshot.statColumns or {},
            players = matchSummarySnapshot and matchSummarySnapshot.players or {},
            ratingChange = localPlayerScore and localPlayerScore.ratingChange or 0,
            prematchMMR = localPlayerScore and localPlayerScore.prematchMMR or 0,
            postmatchMMR = localPlayerScore and localPlayerScore.postmatchMMR or 0,
        },
        integrity = {
            scoreboardComplete = scoreboardReady and totalPlayers > 0,
            timelineComplete = PvPScalpel_IsTable(match.localSpellCapture) and PvPScalpel_IsTable(match.localLossOfControl),
            roundsComplete = roundsCaptured == 6,
            notes = integrityNotes,
        }
    }

    if PvPScalpel_LastSavedMatchTime ~= now then
        if not PvPScalpel_IsTable(match.localSpellCapture) then
            PvPScalpel_SoloShuffleNote("local_spell_capture_missing")
            PvPScalpel_FinalizeCaptureBuffer()
            return
        end
        if not PvPScalpel_IsTable(match.localLossOfControl) then
            PvPScalpel_SoloShuffleNote("local_loss_of_control_missing")
            PvPScalpel_FinalizeCaptureBuffer()
            return
        end
        if PvPScalpel_IsDuplicateMatch(match.matchKey, match.matchDetails and match.matchDetails.timestamp) then
            PvPScalpel_SoloShuffleNote("duplicate_match")
            PvPScalpel_FinalizeCaptureBuffer()
            return
        end
        table.insert(PvP_Scalpel_DB, match)
        if type(PvP_Scalpel_GC) == "table" and type(match.matchKey) == "string" and PvP_Scalpel_GC[match.matchKey] == nil then
            PvP_Scalpel_GC[match.matchKey] = "pending"
        end
        PvPScalpel_LastSavedMatchTime = now
        soloShuffleState.saved = true
        PvPScalpel_Log("Solo Shuffle: match saved (" .. tostring(roundsCaptured) .. " rounds)")
    else
        PvPScalpel_SoloShuffleNote("duplicate_match_timestamp")
    end

    PvPScalpel_FinalizeCaptureBuffer()
end

function PvPScalpel_TryCaptureMatch(attempt)
    attempt = attempt or 1
    PvPScalpel_PrepareScoreboardRead()

    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then
        if attempt <= 10 then
            C_Timer.After(0.3, function()
                PvPScalpel_TryCaptureMatch(attempt + 1)
            end)
        else
            PvPScalpel_FinalizeCaptureBuffer()
        end
        return
    end

    local mapName = GetRealZoneText()
    local now = date("%Y-%m-%d %H:%M:%S")
    local match = {
        matchKey = currentMatchKey,
        telemetryVersion = 4.0,
        winner = lastMatchWinner,
        matchDetails = {
            timestamp = now,
            mapName = mapName,
            build = PvPScalpel_GetBuildInfoSnapshot(),
        },
        players = {}
    }
    PvPScalpel_ApplyMatchStartMetadata(match.matchDetails)

    local ownerName = PvPScalpel_CurrentPlayerName or UnitFullName("player")

    for i = 1, totalPlayers do
        local score = C_PvP.GetScoreInfo(i)
        local mapSpecificStats = PvPScalpel_GetMapStatsForIndex(i)
        if score then
            local playerName, realm = strsplit("-", score.name or "")
            realm = realm or GetRealmName()

            local entry = {
                name = playerName,
                realm = PvPScalpel_Slugify(realm),
                guid = score.guid,
                class = score.classToken,
                spec = score.talentSpec,
                faction = score.faction,
                rating = score.rating,
                ratingChange = score.ratingChange,
                prematchMMR = score.prematchMMR,
                postmatchMMR = score.postmatchMMR,
                damage = score.damageDone,
                healing = score.healingDone,
                kills = score.killingBlows,
                deaths = score.deaths,
                interrupts = PvPScalpel_BuildInterruptSummary(score.guid),
                MSS = mapSpecificStats,
                isOwner = (ownerName == playerName),
            }
            if entry.isOwner then
                PvPScalpel_Log("[PvP Scalpel] MMR Change:")
                PvPScalpel_Log("Pre-match MMR: " .. tostring(entry.prematchMMR))
                PvPScalpel_Log("Post-match MMR: " .. tostring(entry.postmatchMMR))
                local pvpTalents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
                entry.pvpTalents = pvpTalents
            end

            table.insert(match.players, entry)
        end
    end
    match.matchDetails.format = PvPScalpel_FormatChecker(match.players)

    local isFactional = C_PvP and C_PvP.IsMatchFactional and C_PvP.IsMatchFactional() or false
    if isFactional then
        local hordeCount, allianceCount = 0, 0
        for i = 1, #match.players do
            local f = match.players[i] and match.players[i].faction or nil
            if f == 0 then
                hordeCount = hordeCount + 1
            elseif f == 1 then
                allianceCount = allianceCount + 1
            end
        end

        if (hordeCount == 0 or allianceCount == 0) and attempt <= 10 then
            C_Timer.After(0.3, function()
                PvPScalpel_TryCaptureMatch(attempt + 1)
            end)
            return
        end
    end

    if PvPScalpel_LastSavedMatchTime ~= now and #match.players > 0 then
        match = PvPScalpel_StopTimeline(match)
        if not PvPScalpel_IsTable(match.localSpellCapture) then
            PvPScalpel_FinalizeCaptureBuffer()
            return
        end
        if not PvPScalpel_IsTable(match.localLossOfControl) then
            PvPScalpel_FinalizeCaptureBuffer()
            return
        end
        if PvPScalpel_IsDuplicateMatch(match.matchKey, match.matchDetails and match.matchDetails.timestamp) then
            PvPScalpel_FinalizeCaptureBuffer()
            return
        end
        table.insert(PvP_Scalpel_DB, match)
        if type(PvP_Scalpel_GC) == "table" and type(match.matchKey) == "string" and PvP_Scalpel_GC[match.matchKey] == nil then
            PvP_Scalpel_GC[match.matchKey] = "pending"
        end
        PvPScalpel_LastSavedMatchTime = now
        PvPScalpel_Log("PvP Scalpel: Match saved (" .. #match.players .. " players)")
    end

    PvPScalpel_FinalizeCaptureBuffer()
end
