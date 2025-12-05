PvP_Scalpel_DB = PvP_Scalpel_DB or {}

SLASH_PVPSCALPELRESET1 = "/pvpsreset"
SlashCmdList["PVPSCALPELRESET"] = function()
    PvP_Scalpel_DB = {}
    Log("database wiped.")
    C_UI.Reload()
end


local currentTimeline = nil
local timelineStart   = nil
local currentMatchKey = nil  -- how you link to your match record (string or number)
local isTracking = false;

local function PvPScalpel_GenerateMatchKey()
    return date("%Y%m%d_%H%M%S")
end
local function PvPScalpel_StartTimeline()

    currentTimeline = {}
    timelineStart   = GetTime()
    currentMatchKey = PvPScalpel_GenerateMatchKey()
end

local function PvPScalpel_StopTimeline(match)
    if not currentTimeline then return match end

    if not match then
        match = { matchKey = currentMatchKey }
    end

    match.timeline = currentTimeline

    currentTimeline = nil
    timelineStart   = nil
    currentMatchKey = nil

    return match
end

local function PvPScalpel_RecordEvent(eventType, unit, castGUID, spellID)
    if not currentTimeline or not timelineStart then return end
    if unit ~= "player" then return end

    local now = GetTime()

    local hp, hpMax = UnitHealth("player"), UnitHealthMax("player")
    local powerType = UnitPowerType("player")
    local power     = UnitPower("player", powerType)
    local powerMax  = UnitPowerMax("player", powerType)

    local hpPct    = (hpMax  > 0) and (hp / hpMax) or nil
    local powerPct = (powerMax > 0) and (power / powerMax) or nil

    local classification = UnitPvPClassification and UnitPvPClassification("player") or nil

    table.insert(currentTimeline, {
        t       = now - timelineStart,
        event   = eventType,
        spellID = spellID,
        castGUID= castGUID,
        hp      = hpPct,
        power   = powerPct,
        resourceType = powerType,
        pvpRole = classification,
    })
end


local spellFrame = CreateFrame("Frame")
local function OnSpellEvent(self, event, unit, castGUID, spellID, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        PvPScalpel_RecordEvent("SUCCEEDED", unit, castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_START" then
        PvPScalpel_RecordEvent("START", unit, castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_STOP" then
        PvPScalpel_RecordEvent("STOP", unit, castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        PvPScalpel_RecordEvent("FAILED", unit, castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        PvPScalpel_RecordEvent("INTERRUPTED", unit, castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        PvPScalpel_RecordEvent("CHANNEL_START", unit, castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        PvPScalpel_RecordEvent("CHANNEL_STOP", unit, castGUID, spellID)
    end
end


local function EnableSpellTracking()
    Log("Enabling Spell Tracking...")
    
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_START",        "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP",         "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",    "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",       "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",  "player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START","player")
    spellFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    
    spellFrame:SetScript("OnEvent", OnSpellEvent)
    Log("Spell Tracking ENABLED.")
end

local function DisableSpellTracking()
    Log("Disabling Spell Tracking...")
    spellFrame:UnregisterAllEvents()
    Log("Spell Tracking DISABLED.")
end


local myGUID = UnitGUID("player")
local curentPlayerName = UnitFullName("player");

local lastSavedMatchTime = nil

local function TryCaptureMatch()
    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then return end

    local mapName = GetRealZoneText();
    
    local now = date("%Y-%m-%d %H:%M:%S")
    local match = {
        matchKey = currentMatchKey,
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
        match = PvPScalpel_StopTimeline(match)
        table.insert(PvP_Scalpel_DB, match)
        lastSavedMatchTime = now
        print("PvP Scalpel: Match saved (" .. #match.players .. " players)")
    end

    isTracking = false

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
zoneFrame:RegisterEvent("PLAYER_LOGIN")
zoneFrame:SetScript("OnEvent", function(self)
    local formatCheck = PvPScalpel_FormatChecker();

    if formatCheck ~= "Unknown Format" and not isTracking then
        -- Just entered a PvP instance
        isTracking = true
        print(currentMatchKey)
        print(("PvPScalpel: Tracking ON (%s)"):format(formatCheck))

    end
end)

local pvpFrame = CreateFrame("Frame")
pvpFrame:RegisterEvent("PVP_MATCH_COMPLETE")
pvpFrame:RegisterEvent("PVP_MATCH_ACTIVE")
-- local combatFrame = CreateFrame("Frame")
-- combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
pvpFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PVP_MATCH_ACTIVE" then
        Log("PVP MATCH ACTIVE detected.")
        PvPScalpel_StartTimeline()
        EnableSpellTracking()
        Log("Timeline STARTED for new match.")

    elseif event == "PVP_MATCH_COMPLETE" then
        local winner, duration = ...
        Log(string.format("PVP MATCH COMPLETE. Winner: %s | Duration: %s", tostring(winner), tostring(duration)))

        DisableSpellTracking()

        C_Timer.After(0.5, function()
            Log("Capturing match summary...")
            TryCaptureMatch()
            Log("Match record saved.")
        end)
    end
end)