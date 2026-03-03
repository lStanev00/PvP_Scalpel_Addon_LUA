local function PvPScalpel_SafePvpFlag(methodName)
    if not C_PvP then
        return false
    end
    local fn = C_PvP[methodName]
    if type(fn) ~= "function" then
        return false
    end
    local ok, value = pcall(fn)
    return ok and value == true
end

function PvPScalpel_GetMatchCaptureCategory()
    local isSoloShuffle = PvPScalpel_SafePvpFlag("IsSoloShuffle")
        or PvPScalpel_SafePvpFlag("IsRatedSoloShuffle")
        or PvPScalpel_SafePvpFlag("IsBrawlSoloShuffle")
    if isSoloShuffle then
        return "solo_shuffle"
    end

    local isBattleground = PvPScalpel_SafePvpFlag("IsBattleground")
        or PvPScalpel_SafePvpFlag("IsRatedBattleground")
        or PvPScalpel_SafePvpFlag("IsSoloRBG")
        or PvPScalpel_SafePvpFlag("IsRatedSoloRBG")
        or PvPScalpel_SafePvpFlag("IsBrawlSoloRBG")
    if isBattleground then
        return "battleground"
    end

    local isArena = PvPScalpel_SafePvpFlag("IsArena")
        or PvPScalpel_SafePvpFlag("IsRatedArena")
        or PvPScalpel_SafePvpFlag("IsMatchConsideredArena")
    if isArena then
        return "arena"
    end

    return "unknown"
end

function PvPScalpel_DamageMeterUseSessionAggregation()
    local category = PvPScalpel_GetMatchCaptureCategory()
    return category == "battleground" or category == "solo_shuffle"
end

function PvPScalpel_FormatChecker()
    local category = PvPScalpel_GetMatchCaptureCategory()
    if category == "solo_shuffle" then
        return "Solo Shuffle"
    end
    if category == "arena" then
        if PvPScalpel_SafePvpFlag("IsRatedArena") then
            return "Rated Arena"
        end
        return "Arena Skirmish"
    end
    if category == "battleground" then
        if PvPScalpel_SafePvpFlag("IsSoloRBG") then
            return "Battleground Blitz"
        end
        if PvPScalpel_SafePvpFlag("IsRatedSoloRBG") or PvPScalpel_SafePvpFlag("IsRatedBattleground") then
            return "Rated Battleground"
        end
        return "Random Battleground"
    end
    return "Unknown Format"
end
