PvP_Scalpel_DB = PvP_Scalpel_DB or {}

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

local interruptData = {}
local auraData      = {}
local myGUID        = UnitGUID("player")

local f = CreateFrame("Frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", function(_, event)
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then return end

    -- grab everything into a table
    local info = { CombatLogGetCurrentEventInfo() }
    local subEvent = info[2]
    local srcGUID  = info[4]
    local srcName  = info[5]
    local dstName  = info[9]

    -- only track your own actions
    if srcGUID ~= myGUID then return end

    ----------------------------------------------------------------
    -- 1) INTERRUPTS
    -- SPELL_INTERRUPT layout:
    --   [12]=spellID    [13]=spellName    [14]=spellSchool
    --   [15]=extraSpellID [16]=extraSpellName [17]=extraSchool
    if subEvent == "SPELL_INTERRUPT" then
        local spellName      = info[13]
        local extraSpellName = info[16]

        print(("[KickTracker] %s used %s → interrupted %s’s %s"):format(
            srcName, spellName, dstName, extraSpellName
        ))

        interruptData[srcName] = interruptData[srcName] or {}
        local n = (interruptData[srcName][extraSpellName] or 0) + 1
        interruptData[srcName][extraSpellName] = n

        print(("[KickTracker] %s has interrupted %s %d time(s)"):format(
            srcName, extraSpellName, n
        ))
        return
    end

    ----------------------------------------------------------------
    -- 2) AURAS (CC / DEBUFF)
    -- SPELL_AURA_APPLIED layout:
    --   [12]=spellID    [13]=spellName    [14]=spellSchool
    --   [15]=auraType
    if subEvent == "SPELL_AURA_APPLIED" then
        local spellName = info[13]
        local auraType  = info[15]
        if auraType == "DEBUFF" then
            auraData[dstName] = auraData[dstName] or {}
            local m = (auraData[dstName][spellName] or 0) + 1
            auraData[dstName][spellName] = m

            print(("[AuraTracker] %s applied %s to %s (%d)"):format(
                srcName, spellName, dstName, m
            ))
        end
        return
    end
end)
