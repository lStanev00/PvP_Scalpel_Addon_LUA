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

    for slotID = 1, totalSlots do
        local okInterrupt, isInterrupt = pcall(C_ActionBar.IsInterruptAction, slotID)
        if okInterrupt and isInterrupt and (not issecretvalue or not issecretvalue(isInterrupt)) then
            local okInfo, actionType, actionID = pcall(GetActionInfo, slotID)
            if okInfo and actionType == "spell" and type(actionID) == "number" then
                if not knownIDs[actionID] then
                    table.insert(PvP_Scalpel_InteruptSpells, actionID)
                    knownIDs[actionID] = true
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
