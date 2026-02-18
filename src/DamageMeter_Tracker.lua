local damageMeterEventFrame = CreateFrame("Frame")
local damageMeterCombatFrame = CreateFrame("Frame")
local damageMeterRetryTicker = nil
local damageMeterUpdaterTicker = nil
local damageMeterUpdaterInterval = 0.5
local damageMeterPending = false
local damageMeterAttempts = 0
local damageMeterSessions = {}
local damageMeterRecordedSessions = {}
local damageMeterInCombat = false
local damageMeterExcludedSessionIds = {}
local PvPScalpel_DamageMeterStopUpdater
local damageMeterKickStatsBySource = {}

local function PvPScalpel_DamageMeterNormalizeInterruptCount(value)
    if type(value) ~= "number" or value <= 0 then
        return 0
    end
    return math.floor(value)
end

local function PvPScalpel_DamageMeterShouldCollect()
    -- Only collect while the recorder is actively tracking a PvP match.
    -- This avoids doing any DamageMeter work (and avoids touching secret values)
    -- in open world / non-PvP contexts.
    return type(currentMatchKey) == "string" and type(currentTimeline) == "table" and type(timelineStart) == "number"
end

local function PvPScalpel_DamageMeterLog(message)
    if PvPScalpel_Log then
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
    damageMeterStartSessionId = PvPScalpel_DamageMeterGetLatestSessionId() or 0
    damageMeterExcludedSessionIds = {}
    damageMeterKickStatsBySource = {}
    local sessions = PvPScalpel_DamageMeterRefreshSessions()
    for i = 1, #sessions do
        local sessionId = sessions[i].sessionID
        if sessionId then
            damageMeterExcludedSessionIds[sessionId] = true
        end
    end
    PvPScalpel_DamageMeterLog("DamageMeter: start session " .. tostring(damageMeterStartSessionId))
end

function PvPScalpel_DamageMeterResetMatchBuffer()
    damageMeterSessions = {}
    damageMeterRecordedSessions = {}
    damageMeterExcludedSessionIds = {}
    damageMeterKickStatsBySource = {}
    damageMeterPending = false
    damageMeterAttempts = 0
    PvPScalpel_DamageMeterStopUpdater()
    if damageMeterRetryTicker then
        damageMeterRetryTicker:Cancel()
        damageMeterRetryTicker = nil
    end
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

    local selected = {}
    for i = 1, #sessions do
        local sessionId = sessions[i].sessionID
        if sessionId and not damageMeterExcludedSessionIds[sessionId] then
            table.insert(selected, sessionId)
        end
    end

    table.sort(selected, function(a, b)
        return a < b
    end)

    return selected
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

local function PvPScalpel_DamageMeterRecordSpellTotals(sessionId, damageMeterType, sourceGuid, kind, sinkTotals, sinkTotalsBySource, sinkInterruptsBySource, sourceTotalCount)
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
                local spellAmount = spell.totalAmount
                local countAmount = PvPScalpel_DamageMeterNormalizeInterruptCount(spellAmount)
                local entry = PvPScalpel_DamageMeterEnsureSpellEntry(sinkTotals, spell.spellID)
                local sourceEntry = nil
                local sourceBucket = PvPScalpel_DamageMeterEnsureSourceEntry(sinkTotalsBySource, sourceGuid)
                if sourceBucket then
                    sourceEntry = PvPScalpel_DamageMeterEnsureSpellEntry(sourceBucket, spell.spellID)
                end

                local detailCount = 0
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
                            if entry then
                                entry.targets[detail.unitName] = (entry.targets[detail.unitName] or 0) + detail.amount
                            end
                            if sourceEntry then
                                sourceEntry.targets[detail.unitName] = (sourceEntry.targets[detail.unitName] or 0) + detail.amount
                            end

                            if kind == "interrupts" or kind == "dispels" then
                                detailCount = detailCount + PvPScalpel_DamageMeterNormalizeInterruptCount(detail.amount)
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
                    if type(sourceTotalCount) == "number" and sourceTotalCount > 0 and countAmount > sourceTotalCount then
                        countAmount = 0
                    end
                    if countAmount == 0 and detailCount > 0 then
                        countAmount = detailCount
                    end
                    if countAmount == 0 then
                        countAmount = 1
                    end
                    if type(sourceTotalCount) == "number" and sourceTotalCount > 0 and countAmount > sourceTotalCount then
                        countAmount = sourceTotalCount
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
                        entry.damage = entry.damage + spellAmount
                        entry.hits = entry.hits + 1
                    end
                    if sourceEntry then
                        sourceEntry.damage = sourceEntry.damage + spellAmount
                        sourceEntry.hits = sourceEntry.hits + 1
                    end
                elseif kind == "healing" then
                    if entry then
                        entry.healing = entry.healing + spellAmount
                        entry.hits = entry.hits + 1
                    end
                    if sourceEntry then
                        sourceEntry.healing = sourceEntry.healing + spellAmount
                        sourceEntry.hits = sourceEntry.hits + 1
                    end
                elseif kind == "absorbs" then
                    if entry then
                        entry.absorbed = entry.absorbed + spellAmount
                        entry.hits = entry.hits + 1
                    end
                    if sourceEntry then
                        sourceEntry.absorbed = sourceEntry.absorbed + spellAmount
                        sourceEntry.hits = sourceEntry.hits + 1
                    end
                elseif kind == "interrupts" or kind == "dispels" then
                    if kind == "interrupts" then
                        if entry then
                            entry.interrupts = entry.interrupts + countAmount
                        end
                        if sourceEntry then
                            sourceEntry.interrupts = sourceEntry.interrupts + countAmount
                        end
                        if sinkInterruptsBySource then
                            local bySource = sinkInterruptsBySource[sourceGuid]
                            if not bySource then
                                bySource = {}
                                sinkInterruptsBySource[sourceGuid] = bySource
                            end
                            bySource[spell.spellID] = (bySource[spell.spellID] or 0) + countAmount
                        end
                    else
                        if entry then
                            entry.dispels = entry.dispels + countAmount
                        end
                        if sourceEntry then
                            sourceEntry.dispels = sourceEntry.dispels + countAmount
                        end
                    end
                end

            end
        end
    end

    return true, recorded, summedAmount
end

local function PvPScalpel_DamageMeterCollectType(sessionId, damageMeterType, kind, sinkTotals, sinkTotalsBySource, sinkInterruptsBySource)
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
                return false
            end

            local sourceGUID = source.sourceGUID
            if type(sourceGUID) == "string" and sourceGUID ~= "" then
                local okType, spellCount, landedAmount = PvPScalpel_DamageMeterRecordSpellTotals(
                    sessionId,
                    damageMeterType,
                    sourceGUID,
                    kind,
                    sinkTotals,
                    sinkTotalsBySource,
                    sinkInterruptsBySource,
                    PvPScalpel_DamageMeterNormalizeInterruptCount(source.totalAmount)
                )
                if not okType then
                    return false
                end
                landedAmount = landedAmount or 0
                if kind ~= "interrupts" and type(source.totalAmount) == "number" and source.totalAmount > 0 and spellCount == 0 then
                    return false
                end
                if kind == "interrupts" then
                    local issuedAmount = 0
                    if type(source.totalAmount) == "number" and source.totalAmount > 0 then
                        issuedAmount = PvPScalpel_DamageMeterNormalizeInterruptCount(source.totalAmount)
                    end
                    if landedAmount > issuedAmount then
                        landedAmount = issuedAmount
                    end
                    local kickEntry = damageMeterKickStatsBySource[sourceGUID]
                    if not kickEntry then
                        kickEntry = { issued = 0, landed = 0 }
                        damageMeterKickStatsBySource[sourceGUID] = kickEntry
                    end
                    kickEntry.issued = kickEntry.issued + issuedAmount
                    kickEntry.landed = kickEntry.landed + landedAmount
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
        local issued = 0
        local landed = 0
        if type(stats) == "table" then
            if type(stats.issued) == "number" and stats.issued > 0 then
                issued = stats.issued
            end
            if type(stats.landed) == "number" and stats.landed > 0 then
                landed = stats.landed
            end
        end
        if landed > issued then
            landed = issued
        end
        local failed = issued - landed
        if failed < 0 then
            failed = 0
        end
        table.insert(rows, {
            name = guidToName[sourceGUID] or sourceGUID,
            issued = issued,
            landed = landed,
            failed = failed,
        })
    end

    for sourceGUID, stats in pairs(damageMeterKickStatsBySource) do
        if type(sourceGUID) == "string" and type(stats) == "table" and not scoreboardGuids[sourceGUID] then
            local issued = 0
            local landed = 0
            if type(stats.issued) == "number" and stats.issued > 0 then
                issued = stats.issued
            end
            if type(stats.landed) == "number" and stats.landed > 0 then
                landed = stats.landed
            end
            if landed > issued then
                landed = issued
            end
            local failed = issued - landed
            if failed < 0 then
                failed = 0
            end
            local displayName = guidToName[sourceGUID] or sourceGUID
            table.insert(rows, {
                name = displayName,
                issued = issued,
                landed = landed,
                failed = failed,
            })
        end
    end

    table.sort(rows, function(a, b)
        if a.issued ~= b.issued then
            return a.issued > b.issued
        end
        return a.name < b.name
    end)

    PvPScalpel_DamageMeterLog("Kick summary (issued / landed / failed):")
    if #rows == 0 then
        PvPScalpel_DamageMeterLog("  no interrupt sources in this match")
        return
    end
    for i = 1, #rows do
        local row = rows[i]
        PvPScalpel_DamageMeterLog(string.format("  %s - %d / %d / %d", row.name, row.issued, row.landed, row.failed))
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

    local total = PvPScalpel_DamageMeterNormalizeInterruptCount(stats.issued)
    local landed = PvPScalpel_DamageMeterNormalizeInterruptCount(stats.landed)
    if landed > total then
        landed = total
    end
    return total, landed
end

local function PvPScalpel_DamageMeterCollectSession(sessionId)
    if damageMeterRecordedSessions[sessionId] then
        return true
    end

    local pendingTotals = nil
    local pendingTotalsBySource = {}
    local pendingInterruptsBySource = {}
    local okDamage = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.DamageDone, "damage", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource)
    if not okDamage then return false end

    local okHeal = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.HealingDone, "healing", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource)
    if not okHeal then return false end

    local okAbs = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.Absorbs, "absorbs", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource)
    if not okAbs then return false end

    local okInt = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.Interrupts, "interrupts", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource)
    if not okInt then return false end

    local okDisp = PvPScalpel_DamageMeterCollectType(sessionId, Enum.DamageMeterType.Dispels, "dispels", pendingTotals, pendingTotalsBySource, pendingInterruptsBySource)
    if not okDisp then return false end

    if PvPScalpel_MergeSpellTotalsBySource then
        PvPScalpel_MergeSpellTotalsBySource(pendingTotalsBySource)
    end
    if PvPScalpel_MergeInterruptSpellsBySource then
        PvPScalpel_MergeInterruptSpellsBySource(pendingInterruptsBySource)
    end

    damageMeterRecordedSessions[sessionId] = true
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

    local function finalize()
        damageMeterPending = false
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
        end
    elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        PvPScalpel_DamageMeterGetLatestSessionId()
    elseif event == "DAMAGE_METER_RESET" then
        damageMeterSessions = {}
        damageMeterRecordedSessions = {}
        damageMeterExcludedSessionIds = {}
        damageMeterKickStatsBySource = {}
    end
end

if damageMeterEventFrame then
    damageMeterEventFrame:SetScript("OnEvent", PvPScalpel_DamageMeterOnEvent)
    damageMeterEventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    damageMeterEventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
    damageMeterEventFrame:RegisterEvent("DAMAGE_METER_RESET")
end

if damageMeterCombatFrame then
    damageMeterCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    damageMeterCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    damageMeterCombatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if not PvPScalpel_DamageMeterShouldCollect() then
                return
            end
            damageMeterInCombat = true
            PvPScalpel_DamageMeterStartUpdater()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if not PvPScalpel_DamageMeterShouldCollect() then
                return
            end
            damageMeterInCombat = false
            PvPScalpel_DamageMeterStopUpdater()
            if not damageMeterPending then
                PvPScalpel_RequestDamageMeterTotals()
            end
        end
    end)
end
