local interruptActionFrame = CreateFrame("Frame")

local function PvPScalpel_GetActionSlotCount()
    local pages = NUM_ACTIONBAR_PAGES or 6
    local buttons = NUM_ACTIONBAR_BUTTONS or 12
    local total = pages * buttons
    if type(total) ~= "number" or total < 1 then
        return 72
    end
    return total
end

local function PvPScalpel_SafeGetSpellName(spellID)
    if type(spellID) ~= "number" then
        return nil
    end

    if C_Spell and C_Spell.GetSpellName then
        local ok, spellName = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(spellName) == "string" and spellName ~= "" then
            return spellName
        end
    end

    if GetSpellInfo then
        local ok, spellName = pcall(GetSpellInfo, spellID)
        if ok and type(spellName) == "string" and spellName ~= "" then
            return spellName
        end
    end

    return nil
end

function PvPScalpel_ScanInterruptActions()
    if not (C_ActionBar and C_ActionBar.IsInterruptAction and GetActionInfo) then
        return
    end

    local totalSlots = PvPScalpel_GetActionSlotCount()
    local spellsByID = {}
    local foundAny = false

    for slotID = 1, totalSlots do
        local okInterrupt, isInterrupt = pcall(C_ActionBar.IsInterruptAction, slotID)
        if okInterrupt and isInterrupt and (not issecretvalue or not issecretvalue(isInterrupt)) then
            local okInfo, actionType, actionID = pcall(GetActionInfo, slotID)
            if okInfo and actionType == "spell" and type(actionID) == "number" then
                foundAny = true
                local entry = spellsByID[actionID]
                if not entry then
                    entry = {
                        spellName = PvPScalpel_SafeGetSpellName(actionID) or ("Spell-" .. tostring(actionID)),
                        slots = {},
                    }
                    spellsByID[actionID] = entry
                end
                table.insert(entry.slots, slotID)
            end
        end
    end

    local spellIDs = {}
    for spellID in pairs(spellsByID) do
        table.insert(spellIDs, spellID)
    end
    table.sort(spellIDs)

    if foundAny and #spellIDs > 0 then
        PvPScalpel_Log("Interrupt action scan:")
        for i = 1, #spellIDs do
            local spellID = spellIDs[i]
            local entry = spellsByID[spellID]
            local slotsLabel = table.concat(entry.slots, ",")
            PvPScalpel_Log(tostring(spellID) .. " - " .. tostring(entry.spellName) .. " (slots: " .. slotsLabel .. ")")
        end
    else
        PvPScalpel_Log("Interrupt action scan: no interrupt spells found on action bars")
    end
end

if interruptActionFrame then
    interruptActionFrame:RegisterEvent("PLAYER_LOGIN")
    interruptActionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    interruptActionFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    interruptActionFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    interruptActionFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
            return
        end

        if event == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then
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
