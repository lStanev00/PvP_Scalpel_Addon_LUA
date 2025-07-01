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

    return "Unknown Format"

end

function split(input, delimiter)
    local result = {}
    for match in (input .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

function camelToKebab(str)
    str = str:gsub("^[A-Z][a-z0-9]*", "")

    local kebab = str:gsub("([A-Z])", "-%1"):lower()

    kebab = kebab:gsub("^%-", "")

    return kebab
end

function kebabToPascal(str)
    return str:gsub("(^%l)", string.upper)
              :gsub("-%l", function(match)
                  return match:sub(2):upper()
              end)
end

