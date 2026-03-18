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
    currentMatchKey = PvPScalpel_GenerateMatchKey()
    currentSpellTotalsBySource = {}
    currentInterruptSpellsBySource = {}
    currentTimeline = nil
    timelineStart = nil
    castTargetSnapshotByGuid = {}
    currentCastRecords = nil
    castRecordByGuid = {}
    currentCastOutcomes = nil

    if PvPScalpel_StartLocalSpellCaptureSession then
        PvPScalpel_StartLocalSpellCaptureSession()
    end
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("capture_start")
    end
end

function PvPScalpel_StopTimeline(match)
    if type(currentMatchKey) ~= "string" and not (PvPScalpel_IsLocalSpellCaptureActive and PvPScalpel_IsLocalSpellCaptureActive()) then
        return match
    end

    if not match then
        match = { matchKey = currentMatchKey }
    end
    if PvPScalpel_IsTable(currentSpellTotalsBySource) then
        match.spellTotalsBySource = currentSpellTotalsBySource
    end
    if PvPScalpel_IsTable(currentInterruptSpellsBySource) then
        match.interruptSpellsBySource = currentInterruptSpellsBySource
    end

    if PvPScalpel_StopLocalSpellCaptureSession then
        match = PvPScalpel_StopLocalSpellCaptureSession(match)
    end
    if PvPScalpel_BuildCaptureIntegrity then
        local captureIntegrity = PvPScalpel_BuildCaptureIntegrity()
        if PvPScalpel_IsTable(captureIntegrity) then
            match.captureIntegrity = captureIntegrity
        end
    end

    currentTimeline = nil
    timelineStart = nil
    currentMatchKey = nil
    currentCastRecords = nil
    castRecordByGuid = {}
    currentSpellTotalsBySource = nil
    currentInterruptSpellsBySource = nil
    currentCastOutcomes = nil
    currentBgGameType = nil

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

function PvPScalpel_MergeSpellTotals(sourceTotals)
    if not PvPScalpel_IsTable(sourceTotals) then return end
    if not currentSpellTotals then
        currentSpellTotals = {}
    end

    for spellID, incoming in pairs(sourceTotals) do
        if spellID and PvPScalpel_IsTable(incoming) then
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

            entry.damage = entry.damage + (incoming.damage or 0)
            entry.healing = entry.healing + (incoming.healing or 0)
            entry.overheal = entry.overheal + (incoming.overheal or 0)
            entry.absorbed = entry.absorbed + (incoming.absorbed or 0)
            entry.hits = entry.hits + (incoming.hits or 0)
            entry.crits = entry.crits + (incoming.crits or 0)
            entry.interrupts = entry.interrupts + (incoming.interrupts or 0)
            entry.dispels = entry.dispels + (incoming.dispels or 0)

            if PvPScalpel_IsTable(incoming.targets) then
                for targetName, amount in pairs(incoming.targets) do
                    if type(targetName) == "string" and targetName ~= "" and PvPScalpel_IsNumber(amount) and amount > 0 then
                        entry.targets[targetName] = (entry.targets[targetName] or 0) + amount
                    end
                end
            end
        end
    end
end

function PvPScalpel_MergeSpellTotalsBySource(sourceMap)
    if not PvPScalpel_IsTable(sourceMap) then return end
    if not currentSpellTotalsBySource then
        currentSpellTotalsBySource = {}
    end

    for sourceGUID, spells in pairs(sourceMap) do
        if type(sourceGUID) == "string" and sourceGUID ~= "" and PvPScalpel_IsTable(spells) then
            local sourceEntry = currentSpellTotalsBySource[sourceGUID]
            if not sourceEntry then
                sourceEntry = {}
                currentSpellTotalsBySource[sourceGUID] = sourceEntry
            end

            for spellID, incoming in pairs(spells) do
                if spellID and PvPScalpel_IsTable(incoming) then
                    local entry = sourceEntry[spellID]
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
                        sourceEntry[spellID] = entry
                    end

                    entry.damage = entry.damage + (incoming.damage or 0)
                    entry.healing = entry.healing + (incoming.healing or 0)
                    entry.overheal = entry.overheal + (incoming.overheal or 0)
                    entry.absorbed = entry.absorbed + (incoming.absorbed or 0)
                    entry.hits = entry.hits + (incoming.hits or 0)
                    entry.crits = entry.crits + (incoming.crits or 0)
                    entry.interrupts = entry.interrupts + (incoming.interrupts or 0)
                    entry.dispels = entry.dispels + (incoming.dispels or 0)

                    if PvPScalpel_IsTable(incoming.targets) then
                        for targetName, amount in pairs(incoming.targets) do
                            if type(targetName) == "string" and targetName ~= "" and PvPScalpel_IsNumber(amount) and amount > 0 then
                                entry.targets[targetName] = (entry.targets[targetName] or 0) + amount
                            end
                        end
                    end
                end
            end
        end
    end
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("spell_totals_merge")
    end
end

function PvPScalpel_ReplaceSpellTotalsBySource(sourceMap)
    local replaced = {}
    if not PvPScalpel_IsTable(sourceMap) then
        currentSpellTotalsBySource = replaced
        return
    end

    for sourceGUID, spells in pairs(sourceMap) do
        if type(sourceGUID) == "string" and sourceGUID ~= "" and PvPScalpel_IsTable(spells) then
            local sourceEntry = {}
            for spellID, incoming in pairs(spells) do
                if spellID and PvPScalpel_IsTable(incoming) then
                    local entry = {
                        damage = incoming.damage or 0,
                        healing = incoming.healing or 0,
                        overheal = incoming.overheal or 0,
                        absorbed = incoming.absorbed or 0,
                        hits = incoming.hits or 0,
                        crits = incoming.crits or 0,
                        targets = {},
                        interrupts = incoming.interrupts or 0,
                        dispels = incoming.dispels or 0,
                    }
                    if PvPScalpel_IsTable(incoming.targets) then
                        for targetName, amount in pairs(incoming.targets) do
                            if type(targetName) == "string" and targetName ~= "" and PvPScalpel_IsNumber(amount) and amount > 0 then
                                entry.targets[targetName] = amount
                            end
                        end
                    end
                    sourceEntry[spellID] = entry
                end
            end
            if next(sourceEntry) ~= nil then
                replaced[sourceGUID] = sourceEntry
            end
        end
    end

    currentSpellTotalsBySource = replaced
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("spell_totals_replace")
    end
end

function PvPScalpel_MergeInterruptSpellsBySource(sourceMap)
    if not PvPScalpel_IsTable(sourceMap) then return end
    if not currentInterruptSpellsBySource then
        currentInterruptSpellsBySource = {}
    end

    for sourceGUID, spells in pairs(sourceMap) do
        if type(sourceGUID) == "string" and sourceGUID ~= "" and PvPScalpel_IsTable(spells) then
            local sourceEntry = currentInterruptSpellsBySource[sourceGUID]
            if not sourceEntry then
                sourceEntry = {}
                currentInterruptSpellsBySource[sourceGUID] = sourceEntry
            end

            for spellID, count in pairs(spells) do
                if spellID and PvPScalpel_IsNumber(count) and count > 0 then
                    sourceEntry[spellID] = (sourceEntry[spellID] or 0) + count
                end
            end
        end
    end
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("interrupt_spells_merge")
    end
end

function PvPScalpel_ReplaceInterruptSpellsBySource(sourceMap)
    local replaced = {}
    if not PvPScalpel_IsTable(sourceMap) then
        currentInterruptSpellsBySource = replaced
        return
    end

    for sourceGUID, spells in pairs(sourceMap) do
        if type(sourceGUID) == "string" and sourceGUID ~= "" and PvPScalpel_IsTable(spells) then
            local sourceEntry = {}
            for spellID, count in pairs(spells) do
                if spellID and PvPScalpel_IsNumber(count) and count > 0 then
                    sourceEntry[spellID] = count
                end
            end
            if next(sourceEntry) ~= nil then
                replaced[sourceGUID] = sourceEntry
            end
        end
    end

    currentInterruptSpellsBySource = replaced
    if PvPScalpel_UpdateActiveMatchRecoveryCheckpoint then
        PvPScalpel_UpdateActiveMatchRecoveryCheckpoint("interrupt_spells_replace")
    end
end

function PvPScalpel_RecordCastOutcome(outcome)
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
    return
end

function PvPScalpel_RecordItemUse(slot, start, duration, itemID, reason)
    return
end

function PvPScalpel_CheckTrinketCooldowns(reason)
    return
end

function PvPScalpel_RecordEvent(eventType, unit, castGUID, spellID, targetSnapshot)
    return
end

function PvPScalpel_ResolveCastTargetSnapshot(eventType, castGUID)
    return nil
end

function PvPScalpel_ClearCastTargetSnapshot(castGUID)
    return
end
