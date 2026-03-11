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

local function PvPScalpel_IsRatedOutcomeMatch()
    return PvPScalpel_SafePvpFlag("DoesMatchOutcomeAffectRating")
end

function PvPScalpel_GetActiveMatchBracket()
    if not C_PvP then
        return nil
    end
    local fn = C_PvP.GetActiveMatchBracket
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

function PvPScalpel_IsEpicBattlegroundPlayers(players)
    if type(players) ~= "table" then
        return false
    end

    local hordeCount, allianceCount = 0, 0
    for _, player in ipairs(players) do
        local faction = type(player) == "table" and player.faction or nil
        if faction == 0 then
            hordeCount = hordeCount + 1
        elseif faction == 1 then
            allianceCount = allianceCount + 1
        end
    end

    return hordeCount >= 25 and allianceCount >= 25
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

function PvPScalpel_FormatChecker(players)
    if PvPScalpel_IsRatedOutcomeMatch() then
        if PvPScalpel_SafePvpFlag("IsRatedSoloShuffle") then
            return "Solo Shuffle"
        end

        if PvPScalpel_SafePvpFlag("IsSoloRBG") or PvPScalpel_SafePvpFlag("IsRatedSoloRBG") then
            return "Battleground Blitz"
        end

        if PvPScalpel_SafePvpFlag("IsRatedArena") then
            local bracket = PvPScalpel_GetActiveMatchBracket()
            if bracket == 1 then
                return "Rated Arena 2v2"
            end
            if bracket == 2 then
                return "Rated Arena 3v3"
            end
            return "Rated Arena"
        end

        if PvPScalpel_SafePvpFlag("IsRatedBattleground") then
            return "Rated Battleground"
        end
    end

    if PvPScalpel_SafePvpFlag("IsInBrawl") then
        return "Brawl"
    end

    if PvPScalpel_SafePvpFlag("IsArena") or PvPScalpel_SafePvpFlag("IsMatchConsideredArena") then
        return "Arena Skirmish"
    end

    if PvPScalpel_SafePvpFlag("IsBattleground") then
        if PvPScalpel_IsEpicBattlegroundPlayers(players) then
            return "Random Epic Battleground"
        end
        return "Random Battleground"
    end

    return "Unknown Format"
end
