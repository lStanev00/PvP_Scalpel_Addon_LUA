-- User slash commands for PvP Scalpel.
--
-- Command documentation:
-- /pvps-help             -> lists all available commands and their activity.
-- /pvps-reset             -> clears PvP_Scalpel_DB, PvP_Scalpel_GC, PvP_Scalpel_InteruptSpells and reloads UI.
-- /pvps-debug             -> toggles the dedicated debug chat tab on/off.
-- /pvps-debugwipe         -> clears current debug runtime state and debug chat contents.
-- /pvps-count, /pvps-len   -> prints number of recorded matches in PvP_Scalpel_DB.

local function PvPScalpel_CommandPrint(message)
    local prefix = "|cff00ff98[PvP Scalpel]|r "
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(message))
    else
        print(prefix .. tostring(message))
    end
end

local function PvPScalpel_HandleReset()
    PvP_Scalpel_DB = {}
    PvP_Scalpel_GC = {}
    PvP_Scalpel_InteruptSpells = {}
    if PvPScalpel_Log then
        PvPScalpel_Log("database wiped.")
    end
    C_UI.Reload()
end

local function PvPScalpel_HandleDebugToggle()
    local nextValue = true
    if PvPScalpel_Debug == true then
        nextValue = false
    end
    if PvPScalpel_DebugSetEnabled then
        PvPScalpel_DebugSetEnabled(nextValue)
    else
        PvPScalpel_Debug = nextValue
    end
    PvPScalpel_CommandPrint("Debug tab: " .. tostring(PvPScalpel_Debug))
end

local function PvPScalpel_HandleDebugWipe()
    if PvPScalpel_WipeDebugState then
        PvPScalpel_WipeDebugState()
    end
    PvPScalpel_CommandPrint("Debug state wiped.")
end

local function PvPScalpel_HandleCount()
    local count = 0
    if type(PvP_Scalpel_DB) == "table" then
        count = #PvP_Scalpel_DB
    end
    PvPScalpel_CommandPrint("Recorded matches: " .. tostring(count))
end

local function PvPScalpel_HandleKickDump()
    if type(PvP_Scalpel_InteruptSpells) ~= "table" or #PvP_Scalpel_InteruptSpells == 0 then
        PvPScalpel_CommandPrint("Kick table is empty.")
        return
    end

    local uniqueIDs = {}
    local ids = {}
    for i = 1, #PvP_Scalpel_InteruptSpells do
        local spellID = PvP_Scalpel_InteruptSpells[i]
        if type(spellID) == "number" and not uniqueIDs[spellID] then
            uniqueIDs[spellID] = true
            table.insert(ids, spellID)
        end
    end
    table.sort(ids)

    if #ids == 0 then
        PvPScalpel_CommandPrint("Kick table has no numeric spell IDs.")
        return
    end

    PvPScalpel_CommandPrint("Kick spells (id => name):")
    for i = 1, #ids do
        local spellID = ids[i]
        local spellName = PvPScalpel_GetSpellNameByID(spellID) or "UnknownSpell"
        PvPScalpel_CommandPrint(tostring(spellID) .. " => " .. spellName)
    end
end

local commandDocs = {
    { command = "/pvps-help", activity = "List all slash commands and what each command does." },
    { command = "/pvps-reset", activity = "Wipe addon SavedVariables and reload the UI." },
    { command = "/pvps-debug", activity = "Toggle the PvP Scalpel Debug chat tab." },
    { command = "/pvps-debugwipe", activity = "Clear current debug runtime state and debug chat contents." },
    { command = "/pvps-count", activity = "Print number of recorded matches." },
    { command = "/pvps-len", activity = "Alias of /pvpscount." },
    { command = "/pvps-kickdump", activity = "Dump known kick spell IDs and resolved spell names." },
}

local function PvPScalpel_HandleHelp()
    PvPScalpel_CommandPrint("Commands:")
    for i = 1, #commandDocs do
        local entry = commandDocs[i]
        PvPScalpel_CommandPrint(entry.command .. " -> " .. entry.activity)
    end
end

SLASH_PVPSCALPELHELP1 = "/pvps-help"
SLASH_PVPSCALPELHELP2 = "/pvpshelp"
SLASH_PVPSCALPELHELP3 = "/pvps-?"
SLASH_PVPSCALPELHELP4 = "/pvps?"
SlashCmdList["PVPSCALPELHELP"] = PvPScalpel_HandleHelp

SLASH_PVPSCALPELRESET1 = "/pvps-reset"
SlashCmdList["PVPSCALPELRESET"] = PvPScalpel_HandleReset

SLASH_PVPSCALPELDEBUG1 = "/pvps-debug"
SlashCmdList["PVPSCALPELDEBUG"] = PvPScalpel_HandleDebugToggle

SLASH_PVPSCALPELDEBUGWIPE1 = "/pvps-debugwipe"
SLASH_PVPSCALPELDEBUGWIPE2 = "/pvps-debug-wipe"
SlashCmdList["PVPSCALPELDEBUGWIPE"] = PvPScalpel_HandleDebugWipe

SLASH_PVPSCALPELCOUNT1 = "/pvps-count"
SLASH_PVPSCALPELCOUNT2 = "/pvp-slen"
SlashCmdList["PVPSCALPELCOUNT"] = PvPScalpel_HandleCount

SLASH_PVPSCALPELKICKDUMP1 = "/pvps-kickdump"
SlashCmdList["PVPSCALPELKICKDUMP"] = PvPScalpel_HandleKickDump
