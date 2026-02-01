PvP_Scalpel_DB = PvP_Scalpel_DB or {}

SLASH_PVPSCALPELRESET1 = "/pvpsreset"
SlashCmdList["PVPSCALPELRESET"] = function()
    PvP_Scalpel_DB = {}
    Log("database wiped.")
    C_UI.Reload()
end


local isTracking = false

soloShuffleState = {
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

local function PvPScalpel_IsRatedSoloShuffle()
    return C_PvP and C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle()
end

local function PvPScalpel_SoloShuffleNote(msg)
    if not soloShuffleState.notes then
        soloShuffleState.notes = {}
    end
    table.insert(soloShuffleState.notes, msg)
end

local function PvPScalpel_ResetSoloShuffleState()
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

local function PvPScalpel_StartSoloShuffleSession()
    PvPScalpel_ResetSoloShuffleState()
    soloShuffleState.active = true
end

local function PvPScalpel_StartSoloShuffleRound()
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
        timeline = {},
        castRecords = {},
    }
    soloShuffleState.currentRound = round
    soloShuffleState.currentRoundStart = now
    soloShuffleState.currentRoundCastByGuid = {}
    if not PvPScalpel_IsTable(soloShuffleState.rounds) then
        soloShuffleState.rounds = {}
        PvPScalpel_SoloShuffleNote("rounds_table_reset")
    end
    table.insert(soloShuffleState.rounds, round)
    Log(("Solo Shuffle: Round %d start"):format(soloShuffleState.currentRoundIndex))
end

local function PvPScalpel_BuildScoreSnapshot()
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
                realm = slugify(realm),
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

local function PvPScalpel_EndSoloShuffleRound()
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
    Log(("Solo Shuffle: Round %d end (%.1fs)"):format(round.roundIndex, round.duration or 0))
end

local function PvPScalpel_HandleSoloShuffleStateChange()
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
end

local myGUID = UnitGUID("player")
local curentPlayerName = UnitFullName("player");

local lastSavedMatchTime = nil

local function PvPScalpel_BuildSoloShufflePlayers()
    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then
        return {}
    end

    local players = {}
    for i = 1, totalPlayers do
        local score = C_PvP.GetScoreInfo(i)
        if score then
            local playerName, realm = strsplit("-", score.name or "")
            realm = realm or GetRealmName()

            local entry = {
                name = playerName,
                realm = slugify(realm),
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
                MSS = PvPScalpel_GetMapStatsForIndex(i),
                isOwner = (curentPlayerName == playerName),
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

local function PvPScalpel_FinalizeSoloShuffleMatch(attempt)
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
        telemetryVersion = 2,
        winner = lastMatchWinner,
        matchDetails = {
            timestamp = now,
            format = PvPScalpel_FormatChecker(),
            mapName = mapName,
            build = PvPScalpel_GetBuildInfoSnapshot(),
        },
        players = PvPScalpel_BuildSoloShufflePlayers(),
    }

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
        timeline = match.timeline,
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
            timelineComplete = match.timeline ~= nil,
            roundsComplete = roundsCaptured == 6,
            notes = integrityNotes,
        }
    }

    if lastSavedMatchTime ~= now then
        if not PvPScalpel_IsTable(match.timeline) then
            PvPScalpel_SoloShuffleNote("timeline_missing")
            return
        end
        if not PvPScalpel_IsTable(match.castRecords) then
            PvPScalpel_SoloShuffleNote("cast_records_nil")
            return
        end
        if PvPScalpel_IsDuplicateMatch(match.matchKey, match.matchDetails and match.matchDetails.timestamp) then
            PvPScalpel_SoloShuffleNote("duplicate_match")
            return
        end
        table.insert(PvP_Scalpel_DB, match)
        lastSavedMatchTime = now
        soloShuffleState.saved = true
        Log("Solo Shuffle: match saved (" .. tostring(roundsCaptured) .. " rounds)")
    else
        PvPScalpel_SoloShuffleNote("duplicate_match_timestamp")
    end
end

local function TryCaptureMatch()
    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then return end

    local mapName = GetRealZoneText();
    
    local now = date("%Y-%m-%d %H:%M:%S")
    local match = {
        matchKey = currentMatchKey,
        telemetryVersion = 2,
        winner = lastMatchWinner,
        matchDetails = {
            timestamp = now,
            format = PvPScalpel_FormatChecker(),
            mapName = mapName,
            build = PvPScalpel_GetBuildInfoSnapshot(),
        },
        players = {}
    }

    for i = 1, totalPlayers do
        local score = C_PvP.GetScoreInfo(i);
        local mapSpecificStats = PvPScalpel_GetMapStatsForIndex(i);
        if score then
            local playerName, realm = strsplit("-", score.name or "")
            realm = realm or GetRealmName()

            local entry = {
                name = playerName,
                realm = slugify(realm),
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
                MSS = mapSpecificStats,
                isOwner = (curentPlayerName == playerName),
            }
            local isOwner = (curentPlayerName == playerName)
            if isOwner then
                print("[PvP Scalpel] MMR Change:")
                print("Pre-match MMR: ", entry.prematchMMR)
                print("Post-match MMR: ", entry.postmatchMMR)
            end


            if entry.isOwner then
                local pvpTalents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
                entry.pvpTalents = pvpTalents
            end

            table.insert(match.players, entry)
        end
    end

    if lastSavedMatchTime ~= now and #match.players > 0 then
        match = PvPScalpel_StopTimeline(match)
        if not PvPScalpel_IsTable(match.timeline) then
            return
        end
        if not PvPScalpel_IsTable(match.castRecords) then
            return
        end
        if PvPScalpel_IsDuplicateMatch(match.matchKey, match.matchDetails and match.matchDetails.timestamp) then
            return
        end
        table.insert(PvP_Scalpel_DB, match)
        lastSavedMatchTime = now
        print("PvP Scalpel: Match saved (" .. #match.players .. " players)")
    end

    isTracking = false

end

local cdFrame = CreateFrame("Frame")
cdFrame:RegisterEvent("PLAYER_LOGIN")
cdFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
cdFrame:SetScript("OnEvent", function()
    PvPScalpel_ScanRealCooldowns()
end)

-- Frame to watch zoning/instance changes
local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneFrame:RegisterEvent("PLAYER_LOGIN")
zoneFrame:SetScript("OnEvent", function(self)
    local formatCheck = PvPScalpel_FormatChecker();

    if formatCheck ~= "Unknown Format" and not isTracking then
        -- Just entered a PvP instance
        isTracking = true
        print(currentMatchKey)
        print(("PvPScalpel: Tracking ON (%s)"):format(formatCheck))

    end
end)

local pvpFrame = CreateFrame("Frame")
pvpFrame:RegisterEvent("PVP_MATCH_COMPLETE")
pvpFrame:RegisterEvent("PVP_MATCH_ACTIVE")
pvpFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
-- local combatFrame = CreateFrame("Frame")
-- combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
pvpFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PVP_MATCH_ACTIVE" then
        Log("PVP MATCH ACTIVE detected.")
        PvPScalpel_StartTimeline()
        EnableSpellTracking()
        Log("Timeline STARTED for new match.")

        if PvPScalpel_IsRatedSoloShuffle() then
            PvPScalpel_StartSoloShuffleSession()
            PvPScalpel_HandleSoloShuffleStateChange()
            Log("Solo Shuffle: session started")
        else
            PvPScalpel_ResetSoloShuffleState()
        end

    elseif event == "PVP_MATCH_COMPLETE" then
        local winner, duration = ...
        Log(string.format("PVP MATCH COMPLETE. Winner: %s | Duration: %s", tostring(winner), tostring(duration)))
        lastMatchWinner = nil
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

        DisableSpellTracking()

        C_Timer.After(0.5, function()
            Log("Capturing match summary...")
            if PvPScalpel_IsRatedSoloShuffle() then
                PvPScalpel_HandleSoloShuffleStateChange()
                PvPScalpel_FinalizeSoloShuffleMatch()
            else
                TryCaptureMatch()
            end
            Log("Match record saved.")
        end)
    elseif event == "PVP_MATCH_STATE_CHANGED" then
        if PvPScalpel_IsRatedSoloShuffle() then
            PvPScalpel_HandleSoloShuffleStateChange()
        end
    end
end)

local trinketCooldownFrame = CreateFrame("Frame")
trinketCooldownFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
trinketCooldownFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
trinketCooldownFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
trinketCooldownFrame:SetScript("OnEvent", function(_, event)
    if not currentTimeline or not timelineStart then return end
    PvPScalpel_CheckTrinketCooldowns(event)
end)






