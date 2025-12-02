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

local isTracking = false
local REAL_CD_MIN_MS = 30000
local REAL_CD_MAX_MS = 360000   -- 6 minutes

PvPScalpel_RealCooldownsByID = {}
PvPScalpel_RealCooldownsByName = {}

local function IsCombatCooldown(slot, bank)
    if C_SpellBook.IsSpellBookItemPassive(slot, bank) then return false end

    local isUsable, noPower = C_SpellBook.IsSpellBookItemUsable(slot, bank)
    if not isUsable then return false end

    local isHelpful = C_SpellBook.IsSpellBookItemHelpful(slot, bank)
    local isHarmful = C_SpellBook.IsSpellBookItemHarmful(slot, bank)

    if not isHelpful and not isHarmful then return false end

    return true
end

function PvPScalpel_ScanRealCooldowns()
    wipe(PvPScalpel_RealCooldownsByID)
    wipe(PvPScalpel_RealCooldownsByName)

    local numLines = C_SpellBook.GetNumSpellBookSkillLines()

    for line = 1, numLines do
        local skillInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if skillInfo and skillInfo.skillLineID ~= 960 and skillInfo.skillLineID ~= 1003 then

            local offset = skillInfo.itemIndexOffset or 0
            local numItems = skillInfo.numSpellBookItems or 0

            for slot = offset + 1, offset + numItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
                if item and item.itemType == Enum.SpellBookItemType.Spell then

                    if IsCombatCooldown(slot, Enum.SpellBookSpellBank.Player) then
                        local spellID = item.actionID
                        local baseMS = GetSpellBaseCooldown(spellID)

                        if baseMS and baseMS >= REAL_CD_MIN_MS and baseMS <= REAL_CD_MAX_MS then
                            local name = C_Spell.GetSpellName(spellID) or ("Spell "..spellID)

                            PvPScalpel_RealCooldownsByID[spellID] = {
                                id = spellID,
                                name = name,
                                cd = baseMS / 1000,
                            }

                            PvPScalpel_RealCooldownsByName[string.lower(name)] = spellID
                        end
                    end
                end
            end
        end
    end

    print("|cffbb88ff[PvP Scalpel]|r Combat cooldowns detected:")
    for spellID, d in pairs(PvPScalpel_RealCooldownsByID) do
        print(("|cffbb88ff[PvP Scalpel]|r %s (%d) – %.1fs"):format(d.name, spellID, d.cd))
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