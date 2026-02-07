local damageMeterEventFrame = CreateFrame("Frame")
local damageMeterCombatFrame = CreateFrame("Frame")
local damageMeterRetryTicker = nil
local damageMeterUpdaterTicker = nil
local damageMeterUpdaterInterval = 0.5
local damageMeterPending = false
local damageMeterAttempts = 0
local damageMeterSessions = {}
local damageMeterRecordedSessions = {}
local damageMeterMissingSourceAttempts = {}
local damageMeterInCombat = false

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
    PvPScalpel_DamageMeterLog("DamageMeter: start session " .. tostring(damageMeterStartSessionId))
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

local function PvPScalpel_DamageMeterStopUpdater()
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

    local startId = damageMeterStartSessionId or 0
    local selected = {}
    for i = 1, #sessions do
        local sessionId = sessions[i].sessionID
        if sessionId and sessionId >= startId then
            table.insert(selected, sessionId)
        end
    end

    if #selected == 0 then
        table.insert(selected, sessions[#sessions].sessionID)
    end

    table.sort(selected, function(a, b)
        return a < b
    end)

    return selected
end

local function PvPScalpel_DamageMeterFindPlayerSource(sessionId, playerGuid)
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromID) then
        return nil, false, false
    end
    if issecretvalue and issecretvalue(sessionId) then
        return nil, true, false
    end

    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionId, Enum.DamageMeterType.DamageDone)
    if not ok then
        return nil, false, false
    end
    if issecretvalue and issecretvalue(session) then
        return nil, true, false
    end
    if not session or not session.combatSources then
        return nil, false, false
    end
    if issecretvalue and issecretvalue(session.combatSources) then
        return nil, true, false
    end
    if #session.combatSources == 0 then
        return nil, false, false
    end

    for i = 1, #session.combatSources do
        local source = session.combatSources[i]
        if source then
            -- Don't touch source.name: it's explicitly ConditionalSecret in API docs.
            if issecretvalue and (issecretvalue(source) or issecretvalue(source.isLocalPlayer) or issecretvalue(source.sourceGUID)) then
                return nil, true, false
            end
            if source.isLocalPlayer == true then
                return source, false, true
            end
            if playerGuid and source.sourceGUID == playerGuid then
                return source, false, true
            end
        end
    end

    return nil, false, true
end

local function PvPScalpel_DamageMeterRecordSpellTotals(sessionId, damageMeterType, sourceGuid, kind)
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
    for i = 1, #sessionSource.combatSpells do
        local spell = sessionSource.combatSpells[i]
        if spell then
            -- Only inspect the fields we use; nested details can include unit names, etc.
            if issecretvalue and (issecretvalue(spell.spellID) or issecretvalue(spell.totalAmount)) then
                return false, recorded
            end
            if spell.spellID and type(spell.totalAmount) == "number" and spell.totalAmount > 0 then
                recorded = recorded + 1
                if kind == "damage" then
                    PvPScalpel_RecordSpellTotal(spell.spellID, nil, spell.totalAmount, 0, 0, 0, false)
                elseif kind == "healing" then
                    PvPScalpel_RecordSpellTotal(spell.spellID, nil, 0, spell.totalAmount, 0, 0, false)
                elseif kind == "absorbs" then
                    PvPScalpel_RecordSpellTotal(spell.spellID, nil, 0, 0, 0, spell.totalAmount, false)
                elseif kind == "interrupts" or kind == "dispels" then
                    if PvPScalpel_RecordSpellUtilityTotal then
                        PvPScalpel_RecordSpellUtilityTotal(spell.spellID, kind, spell.totalAmount)
                    end
                end
            end
        end
    end

    return true, recorded
end

local function PvPScalpel_DamageMeterCollectSession(sessionId, playerGuid)
    if damageMeterRecordedSessions[sessionId] then
        return true
    end

    local source, hasSecrets, isReady = PvPScalpel_DamageMeterFindPlayerSource(sessionId, playerGuid)
    if hasSecrets then
        PvPScalpel_DamageMeterLog("DamageMeter: secrets detected for session " .. tostring(sessionId))
        return false
    end
    if not isReady then
        return false
    end
    if not source or not source.sourceGUID then
        PvPScalpel_DamageMeterLog("DamageMeter: player source not found for session " .. tostring(sessionId))
        damageMeterMissingSourceAttempts[sessionId] = (damageMeterMissingSourceAttempts[sessionId] or 0) + 1
        -- If this session never contains a local player (unexpected), don't block the entire capture loop forever.
        if damageMeterMissingSourceAttempts[sessionId] >= 5 then
            damageMeterRecordedSessions[sessionId] = true
            return true
        end
        return false
    end

    PvPScalpel_DamageMeterLog("DamageMeter: player source " .. tostring(source.sourceGUID) .. " session " .. tostring(sessionId))

    -- Record damage first and require spells if total > 0; this prevents saving "too early" while
    -- the Damage Meter session exists but spells haven't been populated yet.
    local okDamage, damageCount = PvPScalpel_DamageMeterRecordSpellTotals(
        sessionId,
        Enum.DamageMeterType.DamageDone,
        source.sourceGUID,
        "damage"
    )
    if not okDamage then
        return false
    end
    if type(source.totalAmount) == "number" and source.totalAmount > 0 and damageCount == 0 then
        PvPScalpel_DamageMeterLog("DamageMeter: damage spells not ready (total>0), retry")
        return false
    end

    local okHeal = PvPScalpel_DamageMeterRecordSpellTotals(sessionId, Enum.DamageMeterType.HealingDone, source.sourceGUID, "healing")
    if not okHeal then return false end

    local okAbs = PvPScalpel_DamageMeterRecordSpellTotals(sessionId, Enum.DamageMeterType.Absorbs, source.sourceGUID, "absorbs")
    if not okAbs then return false end

    local okInt = PvPScalpel_DamageMeterRecordSpellTotals(sessionId, Enum.DamageMeterType.Interrupts, source.sourceGUID, "interrupts")
    if not okInt then return false end

    local okDisp = PvPScalpel_DamageMeterRecordSpellTotals(sessionId, Enum.DamageMeterType.Dispels, source.sourceGUID, "dispels")
    if not okDisp then return false end

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

    local playerGuid = UnitGUID and UnitGUID("player") or nil
    if not playerGuid then
        return false
    end

    local sessions = PvPScalpel_DamageMeterSelectSessions()
    if #sessions == 0 then
        PvPScalpel_DamageMeterLog("DamageMeter: no sessions")
        return true
    end

    PvPScalpel_DamageMeterLog("DamageMeter: sessions=" .. tostring(#sessions))

    for _, sessionId in ipairs(sessions) do
        if not PvPScalpel_DamageMeterCollectSession(sessionId, playerGuid) then
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
        damageMeterMissingSourceAttempts = {}
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
