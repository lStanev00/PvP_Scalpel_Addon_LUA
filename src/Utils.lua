-- Utilities shared across modules (non-game-specific helpers + safe logging).

function PvPScalpel_IsTable(value)
    return type(value) == "table"
end

function PvPScalpel_IsNumber(value)
    return type(value) == "number"
end

function PvPScalpel_GetSpellNameByID(spellID)
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

function PvPScalpel_Split(input, delimiter)
    local result = {}
    for match in (tostring(input) .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

function PvPScalpel_CamelToKebab(str)
    str = tostring(str)
    str = str:gsub("^[A-Z][a-z0-9]*", "")

    local kebab = str:gsub("([A-Z])", "-%1"):lower()
    kebab = kebab:gsub("^%-", "")
    return kebab
end

function PvPScalpel_KebabToPascal(str)
    str = tostring(str)
    return str:gsub("(^%l)", string.upper)
              :gsub("-%l", function(match)
                  return match:sub(2):upper()
              end)
end

-- Debug logging (safe: avoids printing during combat lock / restriction windows).
if PvPScalpel_Debug == nil then
    -- Production default: keep chat quiet unless the user explicitly enables debug via /pvpsdebug.
    PvPScalpel_Debug = false
end

PvPScalpel_LogQueue = PvPScalpel_LogQueue or {}

local function PvPScalpel_FlushLogQueue()
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if not PvPScalpel_LogQueue or #PvPScalpel_LogQueue == 0 then
        return
    end

    local prefix = "|cff00ff98[PvP Scalpel]|r "
    for i = 1, #PvPScalpel_LogQueue do
        local message = PvPScalpel_LogQueue[i]
        if PvPScalpel_DebugWriteMessage and PvPScalpel_DebugWriteMessage(prefix .. message) then
            -- Routed into the dedicated debug chat frame.
        elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage(prefix .. message)
        else
            print(prefix .. message)
        end
    end
    wipe(PvPScalpel_LogQueue)
end

local logFrame = CreateFrame("Frame")
logFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
logFrame:RegisterEvent("PLAYER_LOGIN")
logFrame:SetScript("OnEvent", PvPScalpel_FlushLogQueue)

function PvPScalpel_Log(msg)
    if not PvPScalpel_Debug then
        return
    end

    local message = msg
    if type(message) ~= "string" then
        message = tostring(message)
    end

    if InCombatLockdown and InCombatLockdown() then
        table.insert(PvPScalpel_LogQueue, message)
        return
    end

    local prefix = "|cff00ff98[PvP Scalpel]|r "
    if PvPScalpel_DebugWriteMessage and PvPScalpel_DebugWriteMessage(prefix .. message) then
        return
    end

    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. message)
    else
        print(prefix .. message)
    end
end
