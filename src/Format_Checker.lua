function PvPScalpel_FormatChecker ()
    local ratedChecker = C_PvP.DoesMatchOutcomeAffectRating();

    if ratedChecker then
        local ratedArenaChecker = C_PvP.IsRatedArena();
        if ratedArenaChecker then
            return "Rated Arena"
        end

        local shuffleChecker = C_PvP.IsSoloShuffle();
        if shuffleChecker then
            return "Solo Shuffle"
        end

        local blitzChecker = C_PvP.IsSoloRBG();
        if blitzChecker then
             return "Battleground Blitz"
        end

        local RBGChecker = C_PvP.IsRatedSoloRBG();
        if RBGChecker then
            return "Rated Battleground"
        end
    end

    local arenaChecker = C_PvP.IsArena();
    if arenaChecker then
        return "Arena Skirmish"
    end

    local battlegroundChecker = C_PvP.IsBattleground();
    if battlegroundChecker then
        return "Random Battleground"
    end

    local factionalChecker = C_PvP.IsMatchFactional();
    if factionalChecker then
        print("Factional Match = true")
        return "Factional Match"
    end

    return "Unknown Format"

end