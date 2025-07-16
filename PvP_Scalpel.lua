PvP_Scalpel_DB = PvP_Scalpel_DB or {}

local interruptData = {};
local auraData      = {};


local myGUID = UnitGUID("player")

function PvPScalpel_SpellTracker (_, event)
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then return end

    local checkInstance = PvPScalpel_FormatChecker();
    if checkInstance == "Unknown Format" then return end;

    -- local pvpCheck = IsInActiveWorldPVP();
    -- if pvpCheck == false then print("target's in pvp Zone!") end;

    -- grab everything into a table
    local info = { CombatLogGetCurrentEventInfo() }
    local subEvent = info[2]
    local srcGUID  = info[4]
    local srcName  = info[5]
    local dstName  = info[9]

    ----------------------------------------------------------------
    -- 1) INTERRUPTS
    -- SPELL_INTERRUPT layout:
    --   [12]=spellID    [13]=spellName    [14]=spellSchool
    --   [15]=extraSpellID [16]=extraSpellName [17]=extraSchoold
    if subEvent == "SPELL_INTERRUPT" then
        local spellName      = info[13]
        local interruptedSpell = info[16]

        if srcName and spellName and dstName and interruptedSpell then
            interruptData[srcName] = interruptData[srcName] or {};
            interruptData[srcName][dstName] = interruptData[srcName][dstName] or {};
            local n = (interruptData[srcName][dstName][interruptedSpell] or 0) + 1;
            interruptData[srcName][dstName][interruptedSpell] = n
        end

    end

    ----------------------------------------------------------------
    -- 2) AURAS (CC / DEBUFF)
    -- SPELL_AURA_APPLIED layout:
    --   [12]=spellID    [13]=spellName    [14]=spellSchool
    --   [15]=auraType
    if subEvent == "SPELL_AURA_APPLIED" then
        local spellName = info[13]
        local auraType  = info[15]

        if spellName and srcName and dstName  then
            -- all three are non-nil/true
            if auraType == "DEBUFF" then
                auraData[srcName] = auraData[srcName] or {};
                auraData[srcName][dstName] = auraData[srcName][dstName] or {};
                auraData[srcName][dstName][spellName] = (auraData[srcName][dstName][spellName] or 0) + 1;
    
            end
        end

    end
end

local function slugify(text)
    return text:lower():gsub("[ %p]", "-")
end

local curentPlayerName = UnitFullName("player");

local frame = CreateFrame("Frame")
frame:RegisterEvent("PVP_MATCH_COMPLETE")

local lastSavedMatchTime = nil

local function TryCaptureMatch()
    local totalPlayers = GetNumBattlefieldScores()
    if totalPlayers == 0 then return end



    -- local uiMapID = C_Map.GetBestMapForUnit("player")
    -- local mapInfo = C_Map.GetMapInfo(uiMapID)
    -- local mapName = mapInfo and mapInfo.name

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

    match.interrupts = interruptData;
    match.auras = auraData;
    -- clear for next match—but also clear the saved tables:
    wipe(interruptData)
    wipe(auraData)

    interruptData = {};
    auraData = {};

    if lastSavedMatchTime ~= now and #match.players > 0 then
        table.insert(PvP_Scalpel_DB, match)
        lastSavedMatchTime = now
        print("PvP Scalpel: Match saved (" .. #match.players .. " players)")
    end
end

local isTracking = false

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

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatFrame:SetScript("OnEvent", function(_, event, ...)
    PvPScalpel_SpellTracker(_, event, ...)
end)

frame:SetScript("OnEvent", function(_, event)
    if event == "PVP_MATCH_COMPLETE" then
        C_Timer.After(1, TryCaptureMatch)
    end
end)