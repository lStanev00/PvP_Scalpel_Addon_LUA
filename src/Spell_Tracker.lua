local myGUID = UnitGUID("player")

function PvPScalpel_SpellTracker (_, event, auraData, interruptData)
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then return end

    local checkInstance = PvPScalpel_FormatChecker();
    if checkInstance == "Unknown Format" then return end;

    -- local pvpCheck = IsInActiveWorldPVP();
    if pvpCheck == false then print("target's in pvp Zone!") end;

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
        local extraSpellName = info[16]

        if srcGUID == myGUID then

            print(("[KickTracker] %s used %s → interrupted %s’s %s"):format(
                srcName, spellName, dstName, extraSpellName
            ))

        end

        interruptData[srcName] = interruptData[srcName] or {}
        local n = (interruptData[srcName][extraSpellName] or 0) + 1
        interruptData[srcName][extraSpellName] = n

        -- print(("[KickTracker] %s has interrupted %s %d time(s)"):format(
        --     srcName, extraSpellName, n
        -- ))
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

            if srcGUID == myGUID then
                print(("[AuraTracker] %s applied %s to %s (%d)"):format(
                    srcName, spellName, dstName, m
                ))
            end
        end
        return
    end
end