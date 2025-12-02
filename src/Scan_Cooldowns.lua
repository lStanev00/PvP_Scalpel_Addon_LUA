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