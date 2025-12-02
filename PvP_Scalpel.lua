PvP_Scalpel_DB = PvP_Scalpel_DB or {}

local myGUID = UnitGUID("player")
local curentPlayerName = UnitFullName("player");

local frame = CreateFrame("Frame")
frame:RegisterEvent("PVP_MATCH_COMPLETE")

local lastSavedMatchTime = nil

local function TryCaptureMatch()
    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then return end

    local mapName = GetRealZoneText();
    
    local now = date("%Y-%m-%d %H:%M:%S")
    local match = {
        matchDetails = {
            timestamp = now,
            format = PvPScalpel_FormatChecker(),
            mapName = mapName
        },
        players = {}
    }

    for i = 1, totalPlayers do
        local score = C_PvP.GetScoreInfo(i);
        local mapSpecificStats = PvPScalpel_GetMapStatsForIndex(i);
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
                MSS = mapSpecificStats,
                isOwner = (curentPlayerName == playerName),
            }
            local isOwner = (curentPlayerName == playerName)
            if isOwner then
                print("[PvP Scalpel] MMR Change:")
                print("Pre-match MMR: ", entry.prematchMMR)
                print("Post-match MMR: ", entry.postmatchMMR)
            end


            if entry.isOwner then
                local pvpTalents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
                entry.pvpTalents = pvpTalents
            end

            table.insert(match.players, entry)
        end
    end

    if lastSavedMatchTime ~= now and #match.players > 0 then
        table.insert(PvP_Scalpel_DB, match)
        lastSavedMatchTime = now
        print("PvP Scalpel: Match saved (" .. #match.players .. " players)")
    end
end

local cdFrame = CreateFrame("Frame")
cdFrame:RegisterEvent("PLAYER_LOGIN")
cdFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
cdFrame:SetScript("OnEvent", function()
    PvPScalpel_ScanRealCooldowns()
end)

-- Frame to watch zoning/instance changes
local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneFrame:SetScript("OnEvent", function(self)
    local formatCheck = PvPScalpel_FormatChecker();

    if formatCheck ~= "Unknown Format" then
        -- Just entered a PvP instance
        isTracking = true
        wipe(interruptData)
        wipe(auraData)
        print(("PvPScalpel: Tracking ON (%s)"):format(formatCheck))

    end
end)

-- local combatFrame = CreateFrame("Frame")
-- combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", function(_, event)
    if event == "PVP_MATCH_COMPLETE" then
        C_Timer.After(1, TryCaptureMatch)
    end
end)