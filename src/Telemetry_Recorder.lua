function PvPScalpel_IsDuplicateMatch(matchKey, timestamp)
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

function PvPScalpel_GenerateMatchKey()
    return date("%Y%m%d_%H%M%S")
end

function PvPScalpel_StartTimeline()
    currentTimeline = {}
    timelineStart = GetTime()
    currentMatchKey = PvPScalpel_GenerateMatchKey()
    castTargetSnapshotByGuid = {}
    currentCastRecords = {}
    castRecordByGuid = {}
    currentSpellTotals = {}
    currentCastOutcomes = {}
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
    if PvPScalpel_UpdateCurrentTargetSnapshot then
        PvPScalpel_UpdateCurrentTargetSnapshot()
    end
end

function PvPScalpel_StopTimeline(match)
    if not currentTimeline then return match end

    if not match then
        match = { matchKey = currentMatchKey }
    end

    if not PvPScalpel_IsTable(currentTimeline) or not PvPScalpel_IsTable(currentCastRecords) then
        return match
    end

    match.timeline = currentTimeline
    match.castRecords = currentCastRecords
    if PvPScalpel_IsTable(currentSpellTotals) then
        match.spellTotals = currentSpellTotals
    end
    if PvPScalpel_IsTable(currentCastOutcomes) then
        match.castOutcomes = currentCastOutcomes
    end

    currentTimeline = nil
    timelineStart = nil
    currentMatchKey = nil
    currentCastRecords = nil
    castRecordByGuid = {}
    currentSpellTotals = nil
    currentCastOutcomes = nil

    return match
end

function PvPScalpel_RecordSpellTotal(spellID, targetName, damage, healing, overheal, absorbed, isCrit)
    if not spellID then return end
    if not currentSpellTotals then
        currentSpellTotals = {}
    end

    local entry = currentSpellTotals[spellID]
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
        currentSpellTotals[spellID] = entry
    end

    if PvPScalpel_IsNumber(damage) and damage > 0 then
        entry.damage = entry.damage + damage
    end
    if PvPScalpel_IsNumber(healing) and healing > 0 then
        entry.healing = entry.healing + healing
    end
    if PvPScalpel_IsNumber(overheal) and overheal > 0 then
        entry.overheal = entry.overheal + overheal
    end
    if PvPScalpel_IsNumber(absorbed) and absorbed > 0 then
        entry.absorbed = entry.absorbed + absorbed
    end

    entry.hits = entry.hits + 1
    if isCrit then
        entry.crits = entry.crits + 1
    end

    if targetName then
        local amount = 0
        if PvPScalpel_IsNumber(damage) and damage > 0 then
            amount = damage
        elseif PvPScalpel_IsNumber(healing) and healing > 0 then
            amount = healing
        end
        if amount > 0 then
            entry.targets[targetName] = (entry.targets[targetName] or 0) + amount
        end
    end
end

function PvPScalpel_RecordSpellUtilityTotal(spellID, kind, amount)
    if not spellID or not kind then return end
    if not currentSpellTotals then
        currentSpellTotals = {}
    end

    local entry = currentSpellTotals[spellID]
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
        currentSpellTotals[spellID] = entry
    end

    if kind == "interrupts" then
        if PvPScalpel_IsNumber(amount) and amount > 0 then
            entry.interrupts = entry.interrupts + amount
        else
            entry.interrupts = entry.interrupts + 1
        end
    elseif kind == "dispels" then
        if PvPScalpel_IsNumber(amount) and amount > 0 then
            entry.dispels = entry.dispels + amount
        else
            entry.dispels = entry.dispels + 1
        end
    end
end

function PvPScalpel_RecordCastOutcome(outcome)
    if not PvPScalpel_IsTable(outcome) then return end
    if not currentCastOutcomes then
        currentCastOutcomes = {}
    end
    table.insert(currentCastOutcomes, outcome)
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

function PvPScalpel_RecordItemUse(slot, start, duration, itemID, reason)
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

function PvPScalpel_CheckTrinketCooldowns(reason)
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

function PvPScalpel_RecordEvent(eventType, unit, castGUID, spellID, targetSnapshot)
    if not PvPScalpel_IsTable(currentTimeline) or not PvPScalpel_IsNumber(timelineStart) then return end
    if unit ~= "player" then return end

    local now = GetTime()
    if not PvPScalpel_IsNumber(now) then return end

    -- opt out of hp/power recording to avoid secure value taint

    local classification = UnitPvPClassification and UnitPvPClassification("player") or nil

    local eventEntry = {
        t = now - timelineStart,
        event = eventType,
        spellID = spellID,
        castGUID = castGUID,
        targetInfo = targetSnapshot,
        -- hp/power/resourceType intentionally omitted
        pvpRole = classification,
    }
    if not PvPScalpel_IsNumber(eventEntry.t) then return end
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
            t = now - soloShuffleState.currentRoundStart,
            event = eventType,
            spellID = spellID,
            castGUID = castGUID,
            targetInfo = targetSnapshot,
            -- hp/power/resourceType intentionally omitted
            pvpRole = classification,
        }
        if not PvPScalpel_IsNumber(roundEntry.t) then return end
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

function PvPScalpel_ResolveCastTargetSnapshot(eventType, castGUID)
    if not castGUID then return nil end

    if eventType == "START" or eventType == "CHANNEL_START" then
        castTargetSnapshotByGuid[castGUID] = currentTargetSnapshot
    elseif eventType == "SUCCEEDED" and castTargetSnapshotByGuid[castGUID] == nil then
        castTargetSnapshotByGuid[castGUID] = currentTargetSnapshot
    end

    return castTargetSnapshotByGuid[castGUID]
end

function PvPScalpel_ClearCastTargetSnapshot(castGUID)
    if castGUID then
        castTargetSnapshotByGuid[castGUID] = nil
    end
end
