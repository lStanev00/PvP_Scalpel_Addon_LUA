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
            formatType = PvPScalpel_FormatChecker(),

        }
    }
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
                rating = score.rating,
                ratingChange = score.ratingChange,
                prematchMMR = score.prematchMMR,
                postmatchMMR = score.postmatchMMR,
                damage = score.damageDone,
                healing = score.healingDone,
                kills = score.killingBlows,
                deaths = score.deaths,
                timestamp = now,
            }
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
