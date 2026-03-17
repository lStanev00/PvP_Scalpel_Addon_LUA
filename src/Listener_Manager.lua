local cooldownFrame = CreateFrame("Frame")
local zoneFrame = CreateFrame("Frame")
local pvpFrame = CreateFrame("Frame")
local trinketCooldownFrame = CreateFrame("Frame")

local staticListenersRegistered = false
local runtimeListenersRegistered = false
local trinketListenerRegistered = false

local function OnCooldownEvent()
    if PvPScalpel_HandleCooldownRefresh then
        PvPScalpel_HandleCooldownRefresh()
    end
end

local function OnZoneEvent()
    if PvPScalpel_HandleZoneLifecycle then
        PvPScalpel_HandleZoneLifecycle()
    end
end

local function OnPvpMatchActive()
    if PvPScalpel_HandlePvpMatchActive then
        PvPScalpel_HandlePvpMatchActive()
    end
end

local function OnPvpMatchComplete(winner, duration)
    if PvPScalpel_HandlePvpMatchComplete then
        PvPScalpel_HandlePvpMatchComplete(winner, duration)
    end
end

local function OnPvpMatchStateChanged()
    if PvPScalpel_HandlePvpMatchStateChanged then
        PvPScalpel_HandlePvpMatchStateChanged()
    end
end

local function OnPvpEvent(_, event, ...)
    if event == "PVP_MATCH_ACTIVE" then
        OnPvpMatchActive()
    elseif event == "PVP_MATCH_COMPLETE" then
        OnPvpMatchComplete(...)
    elseif event == "PVP_MATCH_STATE_CHANGED" then
        OnPvpMatchStateChanged()
    end
end

local function OnTrinketCooldownEvent(_, event)
    if PvPScalpel_HandleTrinketCooldownEvent then
        PvPScalpel_HandleTrinketCooldownEvent(event)
    end
end

cooldownFrame:SetScript("OnEvent", OnCooldownEvent)
zoneFrame:SetScript("OnEvent", OnZoneEvent)
pvpFrame:SetScript("OnEvent", OnPvpEvent)
trinketCooldownFrame:SetScript("OnEvent", OnTrinketCooldownEvent)

local function RegisterTrinketListener()
    if trinketListenerRegistered then
        return
    end
    trinketCooldownFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    trinketCooldownFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    trinketCooldownFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    trinketListenerRegistered = true
end

local function UnregisterTrinketListener()
    if not trinketListenerRegistered then
        return
    end
    trinketCooldownFrame:UnregisterEvent("BAG_UPDATE_COOLDOWN")
    trinketCooldownFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    trinketCooldownFrame:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
    trinketListenerRegistered = false
end

function PvPScalpel_RegisterStaticListeners()
    if staticListenersRegistered then
        return
    end

    cooldownFrame:RegisterEvent("PLAYER_LOGIN")
    cooldownFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    zoneFrame:RegisterEvent("PLAYER_LOGIN")

    pvpFrame:RegisterEvent("PVP_MATCH_COMPLETE")
    pvpFrame:RegisterEvent("PVP_MATCH_ACTIVE")
    pvpFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")

    staticListenersRegistered = true
end

function PvPScalpel_UnregisterStaticListeners()
    if not staticListenersRegistered then
        return
    end

    cooldownFrame:UnregisterEvent("PLAYER_LOGIN")
    cooldownFrame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    zoneFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    zoneFrame:UnregisterEvent("PLAYER_LOGIN")

    pvpFrame:UnregisterEvent("PVP_MATCH_COMPLETE")
    pvpFrame:UnregisterEvent("PVP_MATCH_ACTIVE")
    pvpFrame:UnregisterEvent("PVP_MATCH_STATE_CHANGED")

    staticListenersRegistered = false
end

function PvPScalpel_RegisterRuntimeListeners()
    if runtimeListenersRegistered then
        return
    end

    if PvPScalpel_EnableSpellTracking then
        PvPScalpel_EnableSpellTracking()
    end
    if PvPScalpel_DamageMeterEnableListeners then
        PvPScalpel_DamageMeterEnableListeners()
    end

    runtimeListenersRegistered = true
end

function PvPScalpel_UnregisterRuntimeListeners()
    if not runtimeListenersRegistered then
        return
    end

    if PvPScalpel_DisableSpellTracking then
        PvPScalpel_DisableSpellTracking()
    end
    if PvPScalpel_DamageMeterDisableListeners then
        PvPScalpel_DamageMeterDisableListeners()
    end

    runtimeListenersRegistered = false
end
