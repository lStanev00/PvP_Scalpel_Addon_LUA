local spellTrackingEnabled = false

function PvPScalpel_EnableSpellTracking()
    if spellTrackingEnabled then
        return
    end

    if PvPScalpel_EnableLocalSpellCaptureRuntime then
        PvPScalpel_EnableLocalSpellCaptureRuntime()
    end

    spellTrackingEnabled = true
    if PvPScalpel_Log then
        PvPScalpel_Log("Spell Tracking ENABLED.")
    end
end

function PvPScalpel_DisableSpellTracking()
    if not spellTrackingEnabled then
        return
    end

    if PvPScalpel_DisableLocalSpellCaptureRuntime then
        PvPScalpel_DisableLocalSpellCaptureRuntime()
    end

    spellTrackingEnabled = false
    if PvPScalpel_Log then
        PvPScalpel_Log("Spell Tracking DISABLED.")
    end
end
