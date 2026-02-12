-- Desktop app -> addon garbage-collection table.
--
-- The desktop app can write into PvP_Scalpel_GC (SavedVariables) before launching WoW.
-- The addon uses this table to coordinate which matches are safe to remove from disk.
--
-- Schema:
--   PvP_Scalpel_GC[matchKey] = state
--
-- state:
--   "pending" | "synced" | "failed"
--
-- On addon load: any matchKey with state == "synced" is removed from PvP_Scalpel_DB and
-- then deleted from PvP_Scalpel_GC (so it won't repeat next launch).

function PvPScalpel_ApplyGarbageCollectionQueue()
    if type(PvP_Scalpel_DB) ~= "table" then
        PvP_Scalpel_DB = {}
    end
    if type(PvP_Scalpel_GC) ~= "table" then
        PvP_Scalpel_GC = {}
    end

    -- Backfill GC state for any matches that exist in the DB but are missing from the GC table.
    -- (Used when the desktop app hasn't written anything yet, or after manual edits.)
    local function EnsureIndexedFromDB(defaultState)
        defaultState = defaultState or "pending" -- requested wording was "queued"; we keep "pending" as the canonical state string.
        for i = 1, #PvP_Scalpel_DB do
            local match = PvP_Scalpel_DB[i]
            local matchKey = (type(match) == "table") and match.matchKey or nil
            if type(matchKey) == "string" and matchKey ~= "" and PvP_Scalpel_GC[matchKey] == nil then
                PvP_Scalpel_GC[matchKey] = defaultState
            end
        end
    end

    local hasSynced = false
    for _, state in pairs(PvP_Scalpel_GC) do
        if state == "synced" then
            hasSynced = true
            break
        end
    end

    if hasSynced then
        -- Remove synced matches from DB.
        for i = #PvP_Scalpel_DB, 1, -1 do
            local match = PvP_Scalpel_DB[i]
            local matchKey = (type(match) == "table") and match.matchKey or nil
            if type(matchKey) == "string" and PvP_Scalpel_GC[matchKey] == "synced" then
                table.remove(PvP_Scalpel_DB, i)
            end
        end

        -- Remove synced keys from GC (even if match isn't present).
        for matchKey, state in pairs(PvP_Scalpel_GC) do
            if state == "synced" then
                PvP_Scalpel_GC[matchKey] = nil
            end
        end
    end

    EnsureIndexedFromDB("pending")
end

-- Apply once per login automatically.
-- This keeps GC consistent even if the main file fails to load for any reason.
do
    local applied = false

    local function ApplyOnce()
        if applied then return end
        applied = true

        if type(PvPScalpel_ApplyGarbageCollectionQueue) ~= "function" then
            return
        end

        -- Never throw during load; GC is best-effort.
        pcall(PvPScalpel_ApplyGarbageCollectionQueue)
    end

    if type(CreateFrame) == "function" then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", ApplyOnce)
    else
        -- Extremely defensive fallback (shouldn't happen in live UI).
        ApplyOnce()
    end
end
