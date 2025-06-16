PvP_Scalpel_DB = PvP_Scalpel_DB or {}

local function slugify(text)
    return text:lower():gsub("[ %p]", "-")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")

local lastSavedMatchTime = nil

local function TryCaptureMatch()
    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then return end

    local match = {
        matchDetails = {
            formatType = PvPScalpel_FormatChecker()
        }
    }
    local instanceType = select(2, IsInInstance()) or "unknown"
    local now = date("%Y-%m-%d %H:%M:%S")

    print("PvP Scalpel: Capturing match...")

    for i = 1, totalPlayers do
        local score = C_PvP.GetScoreInfo(i)
        if score then
            local playerName, realm = strsplit("-", score.name or "")
            realm = realm or GetRealmName()

            local entry = {
                name = playerName,
                realm = slugify(realm),
                class = score.classToken,
                spec = score.talentSpec,
                faction = score.faction,
                ratingChange = score.ratingChange,
                damage = score.damageDone,
                healing = score.healingDone,
                kills = score.killingBlows,
                deaths = score.deaths,
                matchType = instanceType,
                timestamp = now,
                stats = {}
            }

            -- Copy custom stats (if any)
            if score.stats then
                for _, stat in ipairs(score.stats) do
                    table.insert(entry.stats, {
                        name = stat.name or "?",
                        value = stat.pvpStatValue or 0
                    })
                end
            end

            table.insert(match, entry)

            -- Print standard info
            print(string.format(
                " %s-%s | %s (%s) | ΔRating: %s |  %s |  %s |  %d/%d",
                playerName, slugify(realm),
                score.talentSpec or "?", score.classToken or "?",
                score.ratingChange or "0",
                BreakUpLargeNumbers(score.damageDone or 0),
                BreakUpLargeNumbers(score.healingDone or 0),
                score.killingBlows or 0,
                score.deaths or 0
            ))

            -- Print extra stats
            if score.stats then
                for _, stat in ipairs(score.stats) do
                    print(string.format(" %s: %s", stat.name or "?", stat.pvpStatValue or 0))
                end
            end
        end
    end

    if lastSavedMatchTime ~= now and #match > 0 then
        table.insert(PvP_Scalpel_DB, match)
        lastSavedMatchTime = now
        print("PvP Scalpel: Match saved (" .. #match .. " players)")
    end
end

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEAVING_WORLD" then
        C_Timer.After(1, TryCaptureMatch)
    end
end)
