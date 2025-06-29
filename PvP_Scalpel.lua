PvP_Scalpel_DB = PvP_Scalpel_DB or {}
local myGUID = UnitGUID("player")

local function slugify(text)
    return text:lower():gsub("[ %p]", "-")
end

local curentPlayerName = UnitFullName("player");

local frame = CreateFrame("Frame")
frame:RegisterEvent("PVP_MATCH_COMPLETE")

local lastSavedMatchTime = nil

local f = CreateFrame("Frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", PvP_Scalpel_SpellTracker)


local function TryCaptureMatch()
    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then return end



    local uiMapID = C_Map.GetBestMapForUnit("player")
    local mapInfo = C_Map.GetMapInfo(uiMapID)
    local mapName = mapInfo and mapInfo.name

    
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
                isOwner = (curentPlayerName == playerName),
            }

            if entry.isOwner then
                local pvpTalents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs()
                entry.pvpTalents = pvpTalents
            end

            table.insert(match.players, entry)
        end
    end

    for _, entry in ipairs(match.players) do
        entry.interrupts = interruptData[entry.name] or {}
        entry.cc         = auraData[entry.name]   or {}
    end
    -- clear for next match—but also clear the saved tables:
    wipe(interruptData)
    wipe(auraData)

    if lastSavedMatchTime ~= now and #match.players > 0 then
        table.insert(PvP_Scalpel_DB, match)
        lastSavedMatchTime = now
        print("PvP Scalpel: Match saved (" .. #match.players .. " players)")
    end
end

frame:SetScript("OnEvent", function(_, event)
    if event == "PVP_MATCH_COMPLETE" then
        C_Timer.After(1, TryCaptureMatch)
    end
end)