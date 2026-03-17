PvP_Scalpel_DB = PvP_Scalpel_DB or {}
PvP_Scalpel_InteruptSpells = PvP_Scalpel_InteruptSpells or {}
PvP_Scalpel_GC = PvP_Scalpel_GC or {}

if PvPScalpel_ApplyGarbageCollectionQueue then
    PvPScalpel_ApplyGarbageCollectionQueue()
end

function PvPScalpel_WriteMatchResult()
    C_Timer.After(0.5, function()
        local function finalizeMatch()
            if PvPScalpel_DamageMeterLogKickSummary then
                PvPScalpel_DamageMeterLogKickSummary()
            end

            PvPScalpel_Log("Capturing match summary...")
            if PvPScalpel_IsRatedSoloShuffle and PvPScalpel_IsRatedSoloShuffle() then
                PvPScalpel_HandleSoloShuffleStateChange()
                PvPScalpel_FinalizeSoloShuffleMatch()
            else
                PvPScalpel_TryCaptureMatch()
            end

            if PvPScalpel_UnregisterRuntimeListeners then
                PvPScalpel_UnregisterRuntimeListeners()
            end
            PvPScalpel_Log("Match record saved.")
        end

        if PvPScalpel_RequestDamageMeterTotals then
            PvPScalpel_RequestDamageMeterTotals(finalizeMatch)
        else
            finalizeMatch()
        end
    end)
end

function PvPScalpel_HandleCooldownRefresh()
    PvPScalpel_ScanRealCooldowns()
end

function PvPScalpel_HandleZoneLifecycle()
    local formatCheck = PvPScalpel_FormatChecker()

    if formatCheck ~= "Unknown Format" and not PvPScalpel_IsTracking then
        PvPScalpel_IsTracking = true
        PvPScalpel_Log(tostring(currentMatchKey))
        PvPScalpel_Log(("PvPScalpel: Tracking ON (%s)"):format(formatCheck))
    elseif formatCheck == "Unknown Format" then
        PvPScalpel_AbortActiveCapture("left_pvp_instance")
    end
end

function PvPScalpel_HandlePvpMatchActive()
    PvPScalpel_Log("PVP MATCH ACTIVE detected.")
    PvPScalpel_WaitingForGateOpen = true

    if PvPScalpel_IsLiveMatchStarted() then
        PvPScalpel_BeginMatchCapture("PVP_MATCH_ACTIVE")
        PvPScalpel_WaitingForGateOpen = false
    else
        PvPScalpel_Log("Waiting for gates to open before starting capture...")
    end

    if PvPScalpel_IsRatedSoloShuffle and PvPScalpel_IsRatedSoloShuffle() then
        PvPScalpel_StartSoloShuffleSession()
        PvPScalpel_HandleSoloShuffleStateChange()
        PvPScalpel_Log("Solo Shuffle: session started")
    else
        PvPScalpel_ResetSoloShuffleState()
    end
end

function PvPScalpel_HandlePvpMatchComplete(winner, duration)
    PvPScalpel_WaitingForGateOpen = false
    PvPScalpel_Log(string.format("PVP MATCH COMPLETE. Winner: %s | Duration: %s", tostring(winner), tostring(duration)))

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

    PvPScalpel_WriteMatchResult()
end

function PvPScalpel_HandlePvpMatchStateChanged()
    if PvPScalpel_WaitingForGateOpen and PvPScalpel_IsLiveMatchStarted() then
        PvPScalpel_BeginMatchCapture("PVP_MATCH_STATE_CHANGED")
        PvPScalpel_WaitingForGateOpen = false
    end

    if PvPScalpel_IsRatedSoloShuffle and PvPScalpel_IsRatedSoloShuffle() then
        PvPScalpel_HandleSoloShuffleStateChange()
    end
end

function PvPScalpel_HandleTrinketCooldownEvent(event)
    return
end

if PvPScalpel_RegisterStaticListeners then
    PvPScalpel_RegisterStaticListeners()
end
