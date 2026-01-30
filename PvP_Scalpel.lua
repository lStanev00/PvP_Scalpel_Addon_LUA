PvP_Scalpel_DB = PvP_Scalpel_DB or {}

SLASH_PVPSCALPELRESET1 = "/pvpsreset"
SlashCmdList["PVPSCALPELRESET"] = function()
    PvP_Scalpel_DB = {}
    Log("database wiped.")
    C_UI.Reload()
end


local currentTimeline = nil
local timelineStart   = nil
local currentMatchKey = nil  -- how you link to your match record (string or number)
local isTracking = false;
local currentTargetSnapshot = nil
local castTargetSnapshotByGuid = {}
local currentCastRecords = nil
local castRecordByGuid = {}
local lastMatchWinner = nil
local trinketSlots = { 13, 14 }
local lastTrinketCooldowns = {}
local soloShuffleState
local PvPScalpel_UpdateCurrentTargetSnapshot
local function PvPScalpel_IsTable(value)
    return type(value) == "table"
end

local function PvPScalpel_IsNumber(value)
    return type(value) == "number"
end

local function PvPScalpel_IsDuplicateMatch(matchKey, timestamp)
    if not matchKey or not PvPScalpel_IsTable(PvP_Scalpel_DB) then
        return true
    end
    for _, match in ipairs(PvP_Scalpel_DB) do
        if PvPScalpel_IsTable(match) and match.matchKey == matchKey then
            return true
        end
        if timestamp and PvPScalpel_IsTable(match) and match.matchDetails
            and match.matchDetails.timestamp == timestamp and match.matchKey == matchKey then
            return true
        end
    end
    return false
end

local function PvPScalpel_GenerateMatchKey()
    return date("%Y%m%d_%H%M%S")
end

local function PvPScalpel_StartTimeline()

    currentTimeline = {}
    timelineStart   = GetTime()
    currentMatchKey = PvPScalpel_GenerateMatchKey()
    castTargetSnapshotByGuid = {}
    currentCastRecords = {}
    castRecordByGuid = {}
    if GetInventoryItemCooldown then
        for _, slot in ipairs(trinketSlots) do
            local start, duration, enable = GetInventoryItemCooldown("player", slot)
            lastTrinketCooldowns[slot] = {
                start = start or 0,
                duration = duration or 0,
                enabled = enable or 0,
            }
        end
    else
        lastTrinketCooldowns = {}
    end
    PvPScalpel_UpdateCurrentTargetSnapshot()
end

local function PvPScalpel_StopTimeline(match)
    if not currentTimeline then return match end

    if not match then
        match = { matchKey = currentMatchKey }
    end

    if not PvPScalpel_IsTable(currentTimeline) or not PvPScalpel_IsTable(currentCastRecords) then
        return match
    end

    match.timeline = currentTimeline
    match.castRecords = currentCastRecords

    currentTimeline = nil
    timelineStart   = nil
    currentMatchKey = nil
    currentCastRecords = nil
    castRecordByGuid = {}

    return match
end

local function PvPScalpel_BuildTargetSnapshot()
    if not (UnitExists and UnitExists("target")) then
        return { hasTarget = false, disposition = "none" }
    end

    local isPlayer = UnitIsPlayer and UnitIsPlayer("target") or nil
    local canAttack = UnitCanAttack and UnitCanAttack("player", "target") or nil
    local isFriend = UnitIsFriend and UnitIsFriend("player", "target") or nil
    local reaction = UnitReaction and UnitReaction("player", "target") or nil

    local disposition = "unknown"
    if canAttack then
        disposition = "hostile"
    elseif isFriend then
        disposition = "friendly"
    end

    return {
        hasTarget = true,
        disposition = disposition,
        isPlayer = isPlayer,
        canAttack = canAttack,
        isFriend = isFriend,
        reaction = reaction,
    }
end

PvPScalpel_UpdateCurrentTargetSnapshot = function()
    currentTargetSnapshot = PvPScalpel_BuildTargetSnapshot()
end

local function PvPScalpel_RecordItemUse(slot, start, duration, itemID, reason)
    if not PvPScalpel_IsTable(currentTimeline) or not PvPScalpel_IsNumber(timelineStart) then return end

    local now = GetTime()
    if not PvPScalpel_IsNumber(now) then return end
    local entry = {
        t = now - timelineStart,
        event = "ITEM_USE",
        slot = slot,
        itemID = itemID,
        cdStart = start,
        cdDuration = duration,
        source = reason,
    }
    if not PvPScalpel_IsNumber(entry.t) then return end
    table.insert(currentTimeline, entry)

    if soloShuffleState and soloShuffleState.active and soloShuffleState.currentRound
        and soloShuffleState.currentRoundStart then
        local roundEntry = {
            t = now - soloShuffleState.currentRoundStart,
            event = "ITEM_USE",
            slot = slot,
            itemID = itemID,
            cdStart = start,
            cdDuration = duration,
            source = reason,
        }
        if PvPScalpel_IsTable(soloShuffleState.currentRound.timeline) and PvPScalpel_IsNumber(roundEntry.t) then
            table.insert(soloShuffleState.currentRound.timeline, roundEntry)
        else
            PvPScalpel_SoloShuffleNote("round_timeline_missing")
        end
    end
end

local function PvPScalpel_CheckTrinketCooldowns(reason)
    if not GetInventoryItemCooldown then return end

    for _, slot in ipairs(trinketSlots) do
        local start, duration, enable = GetInventoryItemCooldown("player", slot)
        if start and duration then
            local enabled = enable or 0
            local prev = lastTrinketCooldowns[slot]
            local prevActive = prev and prev.start and prev.start > 0 and prev.duration and prev.duration > 0 and prev.enabled == 1
            local active = (start > 0 and duration > 0 and enabled == 1)

            if active and not prevActive then
                local itemID = GetInventoryItemID and GetInventoryItemID("player", slot) or nil
                PvPScalpel_RecordItemUse(slot, start, duration, itemID, reason)
            end

            lastTrinketCooldowns[slot] = {
                start = start,
                duration = duration,
                enabled = enabled,
            }
        end
    end
end

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

local function PvPScalpel_RecordEvent(eventType, unit, castGUID, spellID, targetSnapshot)
    if not PvPScalpel_IsTable(currentTimeline) or not PvPScalpel_IsNumber(timelineStart) then return end
    if unit ~= "player" then return end

    local now = GetTime()
    if not PvPScalpel_IsNumber(now) then return end

    local function SafeNumber(value)
        if type(value) ~= "number" then return nil end
        local ok, coerced = pcall(function()
            return value + 0
        end)
        return ok and coerced or nil
    end

    local hpRaw, hpMaxRaw = UnitHealth("player"), UnitHealthMax("player")
    local powerType = UnitPowerType("player")
    local powerRaw  = UnitPower("player", powerType)
    local powerMaxRaw = UnitPowerMax("player", powerType)

    -- Guard against secure/secret values returned by UnitHealth/UnitPower during protected contexts.
    local hp = SafeNumber(hpRaw)
    local hpMax = SafeNumber(hpMaxRaw)
    local power = SafeNumber(powerRaw)
    local powerMax = SafeNumber(powerMaxRaw)

    local hpPct = (hp and hpMax and hpMax > 0) and (hp / hpMax) or nil
    local powerPct = (power and powerMax and powerMax > 0) and (power / powerMax) or nil

    local classification = UnitPvPClassification and UnitPvPClassification("player") or nil

    local hasSpellDataEntry = nil
    if PvPScalpel_RecordSpellData then
        local ok = PvPScalpel_RecordSpellData(spellID)
        if ok == false then
            hasSpellDataEntry = false
        end
    end

    local eventEntry = {
        t       = now - timelineStart,
        event   = eventType,
        spellID = spellID,
        castGUID= castGUID,
        targetInfo = targetSnapshot,
        hp      = hpPct,
        power   = powerPct,
        resourceType = powerType,
        pvpRole = classification,
    }
    if not PvPScalpel_IsNumber(eventEntry.t) then return end
    if hasSpellDataEntry == false then
        eventEntry.hasSpellDataEntry = false
    end
    table.insert(currentTimeline, eventEntry)

    if castGUID and PvPScalpel_IsTable(currentCastRecords) then
        local castEntry = castRecordByGuid[castGUID]
        if not castEntry then
            castEntry = {
                castGUID = castGUID,
                spellID = spellID,
                startEvent = eventType,
                startTime = now - timelineStart,
                targetInfo = targetSnapshot,
                events = {},
            }
            castRecordByGuid[castGUID] = castEntry
            table.insert(currentCastRecords, castEntry)
        end
        if not PvPScalpel_IsTable(castEntry.events) then
            castEntry.events = {}
        end
        if castEntry.spellID == nil and spellID ~= nil then
            castEntry.spellID = spellID
        end
        if castEntry.targetInfo == nil and targetSnapshot ~= nil then
            castEntry.targetInfo = targetSnapshot
        end
        local castEventTime = now - timelineStart
        if PvPScalpel_IsNumber(castEventTime) then
            local lastTime = castEntry.lastTime
            if not lastTime or castEventTime >= lastTime then
                table.insert(castEntry.events, {
                    t = castEventTime,
                    event = eventType,
                })
                castEntry.lastEvent = eventType
                castEntry.lastTime = castEventTime
            end
        end
    end

    if soloShuffleState and soloShuffleState.active and soloShuffleState.currentRound
        and soloShuffleState.currentRoundStart then
        local roundEntry = {
            t       = now - soloShuffleState.currentRoundStart,
            event   = eventType,
            spellID = spellID,
            castGUID= castGUID,
            targetInfo = targetSnapshot,
            hp      = hpPct,
            power   = powerPct,
            resourceType = powerType,
            pvpRole = classification,
        }
        if not PvPScalpel_IsNumber(roundEntry.t) then return end
        if hasSpellDataEntry == false then
            roundEntry.hasSpellDataEntry = false
        end
        if PvPScalpel_IsTable(soloShuffleState.currentRound.timeline) then
            table.insert(soloShuffleState.currentRound.timeline, roundEntry)
        else
            PvPScalpel_SoloShuffleNote("round_timeline_missing")
        end

        if castGUID and soloShuffleState.currentRoundCastByGuid then
            local roundCastEntry = soloShuffleState.currentRoundCastByGuid[castGUID]
            if not roundCastEntry then
                roundCastEntry = {
                    castGUID = castGUID,
                    spellID = spellID,
                    startEvent = eventType,
                    startTime = now - soloShuffleState.currentRoundStart,
                    targetInfo = targetSnapshot,
                    events = {},
                }
                soloShuffleState.currentRoundCastByGuid[castGUID] = roundCastEntry
                if PvPScalpel_IsTable(soloShuffleState.currentRound.castRecords) then
                    table.insert(soloShuffleState.currentRound.castRecords, roundCastEntry)
                else
                    PvPScalpel_SoloShuffleNote("round_cast_records_missing")
                end
            end
            if not PvPScalpel_IsTable(roundCastEntry.events) then
                roundCastEntry.events = {}
            end
            if roundCastEntry.spellID == nil and spellID ~= nil then
                roundCastEntry.spellID = spellID
            end
            if roundCastEntry.targetInfo == nil and targetSnapshot ~= nil then
                roundCastEntry.targetInfo = targetSnapshot
            end
            local roundEventTime = now - soloShuffleState.currentRoundStart
            if PvPScalpel_IsNumber(roundEventTime) then
                local lastTime = roundCastEntry.lastTime
                if not lastTime or roundEventTime >= lastTime then
                    table.insert(roundCastEntry.events, {
                        t = roundEventTime,
                        event = eventType,
                    })
                    roundCastEntry.lastEvent = eventType
                    roundCastEntry.lastTime = roundEventTime
                end
            end
        end
    end
end


local spellFrame = CreateFrame("Frame")
local function IsRealCastGUID(castGUID)
    if not castGUID then return true end
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

local function PvPScalpel_ResolveCastTargetSnapshot(eventType, castGUID)
    if not castGUID then return nil end

    if eventType == "START" or eventType == "CHANNEL_START" then
        castTargetSnapshotByGuid[castGUID] = currentTargetSnapshot
    elseif eventType == "SUCCEEDED" and castTargetSnapshotByGuid[castGUID] == nil then
        castTargetSnapshotByGuid[castGUID] = currentTargetSnapshot
    end

    return castTargetSnapshotByGuid[castGUID]
end

local function PvPScalpel_ClearCastTargetSnapshot(castGUID)
    if castGUID then
        castTargetSnapshotByGuid[castGUID] = nil
    end
end

local function OnSpellEvent(self, event, unit, ...)

    local isMatchStarted = C_PvP.HasMatchStarted()
    if not isMatchStarted then return end

    if event == "UNIT_SPELLCAST_SENT" then
        local _targetName, castGUID, spellID = ...
        if castGUID and not IsRealCastGUID(castGUID) then
            -- Log("PvPScalpel: Ignored Cast-2 GUID (client-side check).")
            return
        end
        PvPScalpel_RecordEvent("SENT", unit, castGUID, spellID)
        return
    end

    local castGUID, spellID = ...
    if castGUID and not IsRealCastGUID(castGUID) then
        -- Log("PvPScalpel: Ignored Cast-2 GUID (client-side check).")
        return
    end
    local eventType = nil
    local clearTarget = false

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        eventType = "SUCCEEDED"
    elseif event == "UNIT_SPELLCAST_START" then
        eventType = "START"
    elseif event == "UNIT_SPELLCAST_STOP" then
        eventType = "STOP"
        clearTarget = true
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        eventType = "FAILED"
        clearTarget = true
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        eventType = "INTERRUPTED"
        clearTarget = true
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        eventType = "CHANNEL_START"
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        eventType = "CHANNEL_STOP"
        clearTarget = true
    end

    if eventType then
        local targetSnapshot = PvPScalpel_ResolveCastTargetSnapshot(eventType, castGUID)
        PvPScalpel_RecordEvent(eventType, unit, castGUID, spellID, targetSnapshot)
        if clearTarget then
            PvPScalpel_ClearCastTargetSnapshot(castGUID)
        end
    end
end


local function EnableSpellTracking()
    Log("Enabling Spell Tracking...")
    
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_START",        "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP",         "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",    "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",       "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",  "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START","player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT",         "player")
    
    spellFrame:SetScript("OnEvent", OnSpellEvent)
    Log("Spell Tracking ENABLED.")
end

local function DisableSpellTracking()
    Log("Disabling Spell Tracking...")
    spellFrame:UnregisterAllEvents()
    Log("Spell Tracking DISABLED.")
end

local targetFrame = CreateFrame("Frame")
targetFrame:RegisterUnitEvent("UNIT_TARGET", "player")
targetFrame:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" then return end
    PvPScalpel_UpdateCurrentTargetSnapshot()
end)


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






