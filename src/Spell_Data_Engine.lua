-- Cache build key to avoid repeated GetBuildInfo calls.
local buildKeyCache = nil
PvP_Scalpel_Spell_Data = PvP_Scalpel_Spell_Data or {}
-- PvP_Scalpel_Spell_Data = {}
PvPScalpel_BuildKey = PvPScalpel_BuildKey or nil

-- Returns a stable build key string for spell data bucketing.
function PvPScalpel_GetBuildKey()
    if buildKeyCache then return buildKeyCache end

    local snapshot = PvPScalpel_GetBuildInfoSnapshot and PvPScalpel_GetBuildInfoSnapshot() or nil
    if snapshot then
        buildKeyCache = snapshot.versionString
            or (snapshot.version and snapshot.build and (tostring(snapshot.version) .. "." .. tostring(snapshot.build)))
            or snapshot.info
    end

    buildKeyCache = buildKeyCache or "unknown"
    PvPScalpel_BuildKey = buildKeyCache
    return buildKeyCache
end

-- Initialize global build key on load.
PvPScalpel_BuildKey = PvPScalpel_GetBuildKey()

-- Ensures PvP_Scalpel_Spell_Data[buildKey][spellID] exists.
local function PvPScalpel_EnsureSpellDataTable(spellID)
    if not spellID then return end

    local buildKey = PvPScalpel_GetBuildKey()
    if not PvP_Scalpel_Spell_Data[buildKey] then
        PvP_Scalpel_Spell_Data[buildKey] = {}
    end
    if not PvP_Scalpel_Spell_Data[buildKey][spellID] then
        PvP_Scalpel_Spell_Data[buildKey][spellID] = {}
    end
end

-- Returns spell type string based on C_Spell helpers.
local function PvPScalpel_GetSpellType(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellID) then
        return "passive"
    end
    if C_Spell and C_Spell.IsSpellHarmful and C_Spell.IsSpellHarmful(spellID) then
        return "harmfull"
    end
    if C_Spell and C_Spell.IsSpellHelpful and C_Spell.IsSpellHelpful(spellID) then
        return "helpful"
    end
    return nil
end

-- Records spell metadata into PvP_Scalpel_Spell_Data for the current build.
-- Returns true if spell data is present or resolved; false if it can't be resolved.
function PvPScalpel_RecordSpellData(spellID)
    if not spellID then return false end
    if not PvP_Scalpel_Spell_Data then return false end

    local buildKey = PvPScalpel_GetBuildKey()
    if not buildKey then return false end
    PvPScalpel_EnsureSpellDataTable(spellID)
    if not PvP_Scalpel_Spell_Data[buildKey] then return false end
    local entry = PvP_Scalpel_Spell_Data[buildKey][spellID]
    if not entry then return false end

    if entry.name ~= nil or entry.description ~= nil or entry.subtext ~= nil or entry.type ~= nil then
        return true
    end

    if entry.name == nil and C_Spell and C_Spell.GetSpellName then
        entry.name = C_Spell.GetSpellName(spellID)
        if entry.name == "" then
            entry.name = nil
        end
        if entry.name == nil and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            entry.name = info and info.name or nil
            if entry.name == "" then
                entry.name = nil
            end
        end
    end

    if entry.description == nil and C_Spell and C_Spell.GetSpellDescription then
        entry.description = C_Spell.GetSpellDescription(spellID)
        if entry.description == "" then
            entry.description = nil
        end
    end

    if entry.subtext == nil and C_Spell and C_Spell.GetSpellSubtext then
        entry.subtext = C_Spell.GetSpellSubtext(spellID)
        if entry.subtext == "" then
            entry.subtext = nil
        end
    end

    if entry.type == nil then
        entry.type = PvPScalpel_GetSpellType(spellID)
    end

    PvP_Scalpel_Spell_Data[buildKey][spellID] = entry
    if entry.name ~= nil or entry.description ~= nil or entry.subtext ~= nil or entry.type ~= nil then
        return true
    end
    return nil
end
