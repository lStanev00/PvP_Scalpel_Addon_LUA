local interruptActionFrame = CreateFrame("Frame")
local interruptDescriptionCache = {}

local function PvPScalpel_DescriptionLooksInterrupt(description)
    if type(description) ~= "string" or description == "" then
        return false
    end

    local text = string.lower(description)
    if text == "" then
        return false
    end

    -- Exclude defensive "cannot be interrupted" style text.
    if text:find("cannot be interrupted", 1, true) or text:find("can't be interrupted", 1, true) then
        return false
    end

    if text:find("interrupts", 1, true) then
        return true
    end

    if text:find("interrupt", 1, true) and text:find("spellcasting", 1, true) then
        return true
    end

    -- Counter-style wording used by some interrupt abilities/tooltips.
    if text:find("counterspell", 1, true) or text:find("counter shot", 1, true) then
        return true
    end
    if text:find("counter", 1, true)
        and (text:find("spell", 1, true) or text:find("casting", 1, true) or text:find("cast", 1, true)) then
        return true
    end

    return false
end

local function PvPScalpel_GetSpellDescription(spellID)
    if type(spellID) ~= "number" then
        return nil
    end

    if C_Spell and C_Spell.GetSpellDescription then
        local ok, description = pcall(C_Spell.GetSpellDescription, spellID)
        if ok and type(description) == "string" and description ~= "" and (not issecretvalue or not issecretvalue(description)) then
            return description
        end
    end

    if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell and C_SpellBook.GetSpellBookItemDescription
        and Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player then
        local okFind, slotIndex, bank = pcall(C_SpellBook.FindSpellBookSlotForSpell, spellID, true, true, false, true)
        if okFind and type(slotIndex) == "number" and slotIndex > 0 and bank ~= nil then
            local okDesc, description = pcall(C_SpellBook.GetSpellBookItemDescription, slotIndex, bank)
            if okDesc and type(description) == "string" and description ~= "" and (not issecretvalue or not issecretvalue(description)) then
                return description
            end
        end
    end

    return nil
end

local function PvPScalpel_IsInterruptByDescription(spellID)
    if type(spellID) ~= "number" then
        return false
    end

    local cached = interruptDescriptionCache[spellID]
    if cached ~= nil then
        return cached == true
    end

    local description = PvPScalpel_GetSpellDescription(spellID)
    local isInterrupt = PvPScalpel_DescriptionLooksInterrupt(description)
    interruptDescriptionCache[spellID] = isInterrupt
    return isInterrupt
end

local function PvPScalpel_GetActionSlotCount()
    local buttons = NUM_ACTIONBAR_BUTTONS or 12
    local maxPages = NUM_ACTIONBAR_PAGES or 6

    if C_ActionBar then
        if C_ActionBar.GetVehicleBarIndex then
            local ok, page = pcall(C_ActionBar.GetVehicleBarIndex)
            if ok and type(page) == "number" and page > maxPages then
                maxPages = page
            end
        end
        if C_ActionBar.GetOverrideBarIndex then
            local ok, page = pcall(C_ActionBar.GetOverrideBarIndex)
            if ok and type(page) == "number" and page > maxPages then
                maxPages = page
            end
        end
        if C_ActionBar.GetTempShapeshiftBarIndex then
            local ok, page = pcall(C_ActionBar.GetTempShapeshiftBarIndex)
            if ok and type(page) == "number" and page > maxPages then
                maxPages = page
            end
        end
    end

    local total = maxPages * buttons
    if type(total) ~= "number" or total < 1 then
        return 72
    end

    -- Be generous: some bar setups use higher slot IDs than the default page span.
    if total < 216 then
        total = 216
    end

    return total
end

function PvPScalpel_ScanInterruptActions()
    if not (C_ActionBar and C_ActionBar.IsInterruptAction and GetActionInfo) then
        return
    end
    if type(PvP_Scalpel_InteruptSpells) ~= "table" then
        PvP_Scalpel_InteruptSpells = {}
    end

    local totalSlots = PvPScalpel_GetActionSlotCount()
    local knownIDs = {}
    for i = 1, #PvP_Scalpel_InteruptSpells do
        local knownID = PvP_Scalpel_InteruptSpells[i]
        if type(knownID) == "number" then
            knownIDs[knownID] = true
        end
    end

    local function TryRecordSlot(slotID)
        if type(slotID) ~= "number" or slotID < 1 then
            return
        end

        local okInfo, actionType, actionID = pcall(GetActionInfo, slotID)
        if not okInfo or type(actionType) ~= "string" then
            return
        end

        local candidateSpellID = nil
        if actionType == "spell" and type(actionID) == "number" then
            candidateSpellID = actionID
        elseif actionType == "pet" and type(actionID) == "number" and GetPetActionInfo then
            local okPet, _, _, _, _, _, petSpellID = pcall(GetPetActionInfo, actionID)
            if okPet and type(petSpellID) == "number" then
                candidateSpellID = petSpellID
            end
        end

        if type(candidateSpellID) ~= "number" then
            return
        end

        local byActionFlag = false
        local okInterrupt, isInterrupt = pcall(C_ActionBar.IsInterruptAction, slotID)
        if okInterrupt and isInterrupt and (not issecretvalue or not issecretvalue(isInterrupt)) then
            byActionFlag = true
        end

        local byDescription = PvPScalpel_IsInterruptByDescription(candidateSpellID)
        if not byActionFlag and not byDescription then
            return
        end

        if not knownIDs[candidateSpellID] then
            table.insert(PvP_Scalpel_InteruptSpells, candidateSpellID)
            knownIDs[candidateSpellID] = true
        end
    end

    -- Scan canonical slot IDs first (includes main page slots).
    for slotID = 1, totalSlots do
        TryRecordSlot(slotID)
    end

    -- Scan visible action buttons as well (includes MultiBar slots and custom bars
    -- exposed by Blizzard action bar frames that may sit outside the canonical range).
    local buttonPrefixes = nil
    if ActionButtonUtil and type(ActionButtonUtil.ActionBarButtonNames) == "table" then
        buttonPrefixes = ActionButtonUtil.ActionBarButtonNames
        local hasPetPrefix = false
        for i = 1, #buttonPrefixes do
            if buttonPrefixes[i] == "PetActionButton" then
                hasPetPrefix = true
                break
            end
        end
        if not hasPetPrefix then
            local extended = {}
            for i = 1, #buttonPrefixes do
                extended[#extended + 1] = buttonPrefixes[i]
            end
            extended[#extended + 1] = "PetActionButton"
            buttonPrefixes = extended
        end
    else
        buttonPrefixes = {
            "ActionButton",
            "MultiBarBottomLeftButton",
            "MultiBarBottomRightButton",
            "MultiBarLeftButton",
            "MultiBarRightButton",
            "MultiBar5Button",
            "MultiBar6Button",
            "MultiBar7Button",
            "PetActionButton",
        }
    end

    local buttonsPerBar = NUM_ACTIONBAR_BUTTONS or 12
    for i = 1, #buttonPrefixes do
        local prefix = buttonPrefixes[i]
        if type(prefix) == "string" and prefix ~= "" then
            for buttonIndex = 1, buttonsPerBar do
                local button = _G[prefix .. buttonIndex]
                if button and type(button.action) == "number" and button.action > 0 then
                    TryRecordSlot(button.action)
                end
            end
        end
    end

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
        and C_SpellBook.GetSpellBookItemType and Enum and Enum.SpellBookSpellBank
        and Enum.SpellBookSpellBank.Player then
        local playerBank = Enum.SpellBookSpellBank.Player
        local okLines, skillLineCount = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        if okLines and type(skillLineCount) == "number" and skillLineCount > 0 then
            for skillLineIndex = 1, skillLineCount do
                local okSkill, skillLineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, skillLineIndex)
                if okSkill and type(skillLineInfo) == "table" then
                    local offset = tonumber(skillLineInfo.itemIndexOffset) or 0
                    local count = tonumber(skillLineInfo.numSpellBookItems) or 0
                    local firstSlot = offset + 1
                    local lastSlot = offset + count
                    for slotIndex = firstSlot, lastSlot do
                        local okType, itemType, actionID, spellID = pcall(C_SpellBook.GetSpellBookItemType, slotIndex, playerBank)
                        if okType and (not issecretvalue or not issecretvalue(itemType)) then
                            local candidateID = nil
                            if type(spellID) == "number" then
                                candidateID = spellID
                            elseif type(actionID) == "number" then
                                candidateID = actionID
                            end

                            if candidateID and not knownIDs[candidateID] and PvPScalpel_IsInterruptByDescription(candidateID) then
                                table.insert(PvP_Scalpel_InteruptSpells, candidateID)
                                knownIDs[candidateID] = true
                            end
                        end
                    end
                end
            end
        end

        if C_SpellBook.HasPetSpells and Enum.SpellBookSpellBank.Pet then
            local okPet, numPetSpells = pcall(C_SpellBook.HasPetSpells)
            if okPet and type(numPetSpells) == "number" and numPetSpells > 0 then
                local petBank = Enum.SpellBookSpellBank.Pet
                for slotIndex = 1, numPetSpells do
                    local okType, _, actionID, spellID = pcall(C_SpellBook.GetSpellBookItemType, slotIndex, petBank)
                    if okType then
                        local candidateID = nil
                        if type(spellID) == "number" then
                            candidateID = spellID
                        elseif type(actionID) == "number" then
                            candidateID = actionID
                        end

                        if candidateID and not knownIDs[candidateID] and PvPScalpel_IsInterruptByDescription(candidateID) then
                            table.insert(PvP_Scalpel_InteruptSpells, candidateID)
                            knownIDs[candidateID] = true
                        end
                    end
                end
            end
        end
    end
end

if interruptActionFrame then
    interruptActionFrame:RegisterEvent("PLAYER_LOGIN")
    interruptActionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    interruptActionFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    interruptActionFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    interruptActionFrame:RegisterEvent("SPELLS_CHANGED")
    interruptActionFrame:RegisterEvent("UNIT_PET")
    interruptActionFrame:RegisterEvent("PET_BAR_UPDATE")
    interruptActionFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
            return
        end
        if event == "UNIT_PET" and unit and unit ~= "player" then
            return
        end

        if event == "PLAYER_TALENT_UPDATE"
            or event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "SPELLS_CHANGED"
            or event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_LOGIN"
            or event == "UNIT_PET"
            or event == "PET_BAR_UPDATE" then
            interruptDescriptionCache = {}
        end

        if (event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED") and C_Timer and C_Timer.After then
            C_Timer.After(0.15, function()
                if PvPScalpel_ScanInterruptActions then
                    PvPScalpel_ScanInterruptActions()
                end
            end)
            return
        end

        if PvPScalpel_ScanInterruptActions then
            PvPScalpel_ScanInterruptActions()
        end
    end)
end
