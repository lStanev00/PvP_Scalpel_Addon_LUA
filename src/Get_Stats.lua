function PvPScalpel_GetMapStatsForIndex(i)
    local result = {}

    local score = C_PvP.GetScoreInfo(i)
    if not score or not score.stats then
        return result
    end

    for _, s in ipairs(score.stats) do
        if s.name and s.pvpStatValue and s.pvpStatValue ~= 0 then
            table.insert(result, {
                s.name,
                s.pvpStatValue
            })
        end
    end

    return result
end

function Debug_LogPVPStats()
    print("|cff00ff00[PvPScalpel]|r Match Stats Loaded")

    if not C_PvP or not C_PvP.GetScoreInfo then
        print("|cffff5555[PvPScalpel] C_PvP API unavailable.|r")
        return
    end

    local statIDs = C_PvP.GetMatchPVPStatIDs and C_PvP.GetMatchPVPStatIDs()
    local statNames = {}

    print("|cff00ff00[PvPScalpel]|r Map Stats:")

    if statIDs and #statIDs > 0 then
        for _, id in ipairs(statIDs) do
            local info = C_PvP.GetPVPStatInfo(id)
            if info then
                table.insert(statNames, info.name)
                print("   • |cff1eff00" .. info.name .. "|r")
            end
        end
    else
        print("   |cffffaa00This mode has no map-specific stat columns.|r")
    end

    print("|cff00ff00[PvPScalpel]|r Players:")

    local total = GetNumBattlefieldScores()
    if total == 0 then
        print("|cffff5555Scoreboard unavailable.|r")
        return
    end

    for i = 1, total do
        local score = C_PvP.GetScoreInfo(i)
        if score then
            local name = score.name or "?"
            local dmg  = score.damageDone or 0
            local heal = score.healingDone or 0

            print("|cffffff00" .. name .. "|r  " ..
                  "|cff00ccffDmg:|r " .. dmg .. "  " ..
                  "|cff00ff00Heal:|r " .. heal)

            -- map stats
            if score.stats and #score.stats > 0 then
                for _, s in ipairs(score.stats) do
                    print("      |cff1eff00" .. (s.name or "?") .. "|r: " ..
                          "|cffffffff" .. (s.pvpStatValue or 0) .. "|r")
                end
            else
                print("      |cffffaa00(no map stats)|r")
            end
        end
    end

    print("|cff00ff00[PvPScalpel] End|r")
end
