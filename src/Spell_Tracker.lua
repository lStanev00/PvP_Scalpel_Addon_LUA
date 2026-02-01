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

function EnableSpellTracking()
    Log("Enabling Spell Tracking...")

    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")

    spellFrame:SetScript("OnEvent", OnSpellEvent)
    Log("Spell Tracking ENABLED.")
end

function DisableSpellTracking()
    Log("Disabling Spell Tracking...")
    spellFrame:UnregisterAllEvents()
    Log("Spell Tracking DISABLED.")
end

local targetFrame = CreateFrame("Frame")
targetFrame:RegisterUnitEvent("UNIT_TARGET", "player")
targetFrame:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" then return end
    if PvPScalpel_UpdateCurrentTargetSnapshot then
        PvPScalpel_UpdateCurrentTargetSnapshot()
    end
end)
