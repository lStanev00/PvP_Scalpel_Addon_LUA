local PvPScalpel_UnitPopupTags = {
    "MENU_UNIT_SELF",
    "MENU_UNIT_PLAYER",
    "MENU_UNIT_ENEMY_PLAYER",
    "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID",
    "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_FRIEND",
    "MENU_UNIT_FRIEND_OFFLINE",
    "MENU_UNIT_CHAT_ROSTER",
    "MENU_UNIT_PVP_SCOREBOARD",
}

local PvPScalpel_UnitPopupMenuRegistered = false
local PvPScalpel_UnitPopupUrlDialog = nil
local PvPScalpel_UnitPopupNoticeFrame = nil
local PvPScalpel_UnitPopupDialogEscRegistered = false
local PvPScalpel_BlitzLobbyScanWindow = nil
local PvPScalpel_BlitzLobbyScanWindowEscRegistered = false
local PvPScalpel_BlitzLobbyScanWatcherActive = false
local PvPScalpel_BlitzLobbySpecCache = {}
local PvPScalpel_BlitzLobbySpecRetryAfter = {}
local PvPScalpel_BlitzLobbyInspectPendingGuid = nil
local PvPScalpel_BlitzLobbyInspectPendingUnit = nil
local PvPScalpel_BlitzLobbyInspectPendingAt = 0
local PvPScalpel_BlitzLobbyScanFailureReason = nil
local PvPScalpel_BlitzLobbyScanStateKey = "PvP Scalpel Lobby Scan"
local PvPScalpel_BlitzLobbySpinnerFrames = { "|", "/", "-", "\\" }
local PvPScalpel_BlitzLobbyInspectTimeoutSeconds = 1.5
local PvPScalpel_BlitzLobbyInspectRetrySeconds = 2.0
local PvPScalpel_BlitzLobbyRefreshHeartbeatSeconds = 0.25
local PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid = {}
local PvPScalpel_BlitzLobbyScanMockMode = false
local PvPScalpel_BlitzLobbyScanMockConfig = nil
local PvPScalpel_BlitzLobbyScanMockEntries = nil
local PvPScalpel_BlitzLobbyScanSnapshot = nil
local PvPScalpel_BlitzLobbyScanSnapshotSignature = nil
local PvPScalpel_BlitzLobbyScanLogSignature = nil
local PvPScalpel_BlitzLobbyEnemyLastSignature = nil
local PvPScalpel_BlitzLobbyEnemyLastImprovedAt = 0
local PvPScalpel_BlitzLobbyEnemySettledAt = nil
local PvPScalpel_BlitzLobbyEnemySteadyStateSeconds = 1.0
local PvPScalpel_BlitzLobbyEnemySpecIDByKey = {}
local PvPScalpel_BlitzLobbyClassTokenToClassID = nil
local PvPScalpel_SetBlitzLobbyScanFailure
local PvPScalpel_ClearBlitzLobbyScanFailure
local PvPScalpel_CyrillicToLatinMap = {
    ["А"] = "A",   ["а"] = "a",   ["Б"] = "B",   ["б"] = "b",
    ["В"] = "V",   ["в"] = "v",   ["Г"] = "G",   ["г"] = "g",
    ["Д"] = "D",   ["д"] = "d",   ["Е"] = "E",   ["е"] = "e",
    ["Ё"] = "E",   ["ё"] = "e",   ["Ж"] = "Zh",  ["ж"] = "zh",
    ["З"] = "Z",   ["з"] = "z",   ["И"] = "I",   ["и"] = "i",
    ["Й"] = "Y",   ["й"] = "y",   ["К"] = "K",   ["к"] = "k",
    ["Л"] = "L",   ["л"] = "l",   ["М"] = "M",   ["м"] = "m",
    ["Н"] = "N",   ["н"] = "n",   ["О"] = "O",   ["о"] = "o",
    ["П"] = "P",   ["п"] = "p",   ["Р"] = "R",   ["р"] = "r",
    ["С"] = "S",   ["с"] = "s",   ["Т"] = "T",   ["т"] = "t",
    ["У"] = "U",   ["у"] = "u",   ["Ф"] = "F",   ["ф"] = "f",
    ["Х"] = "H",   ["х"] = "h",   ["Ц"] = "Ts",  ["ц"] = "ts",
    ["Ч"] = "Ch",  ["ч"] = "ch",  ["Ш"] = "Sh",  ["ш"] = "sh",
    ["Щ"] = "Sht", ["щ"] = "sht", ["Ъ"] = "A",   ["ъ"] = "a",
    ["Ы"] = "Y",   ["ы"] = "y",   ["Ь"] = "",    ["ь"] = "",
    ["Э"] = "E",   ["э"] = "e",   ["Ю"] = "Yu",  ["ю"] = "yu",
    ["Я"] = "Ya",  ["я"] = "ya",
}
local blitzLobbyScanEventFrame = CreateFrame("Frame")

local function PvPScalpel_LogLobbyScan(message)
    if type(message) ~= "string" or message == "" then
        return
    end
    if PvPScalpel_Debug ~= true then
        return
    end

    if PvPScalpel_DebugWindowOpenIfAllowed then
        PvPScalpel_DebugWindowOpenIfAllowed("PvP Scalpel Debug", true)
    end

    if PvPScalpel_DebugWriteMessage then
        PvPScalpel_DebugWriteMessage("|cff00ff98[PvP Scalpel]|r [LobbyScan] " .. message)
    end
end

local function PvPScalpel_EnsurePopupWindowStateStore()
    if type(PvP_Scalpel_DebugWindowState) ~= "table" then
        PvP_Scalpel_DebugWindowState = {}
    end
    return PvP_Scalpel_DebugWindowState
end

local function PvPScalpel_GetStoredBlitzLobbyScanLayout()
    local store = PvPScalpel_EnsurePopupWindowStateStore()
    local layout = store[PvPScalpel_BlitzLobbyScanStateKey]
    if type(layout) ~= "table" then
        return nil
    end
    return layout
end

local function PvPScalpel_SaveBlitzLobbyScanLayout(frame)
    if type(frame) ~= "table" then
        return
    end

    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    local store = PvPScalpel_EnsurePopupWindowStateStore()
    store[PvPScalpel_BlitzLobbyScanStateKey] = {
        point = type(point) == "string" and point or "CENTER",
        relativePoint = type(relativePoint) == "string" and relativePoint or "CENTER",
        x = type(xOfs) == "number" and xOfs or 0,
        y = type(yOfs) == "number" and yOfs or 0,
    }
end

local function PvPScalpel_GetLobbyScanNow()
    if type(GetTime) == "function" then
        return GetTime()
    end
    return 0
end

local function PvPScalpel_IsSecretLobbyScanValue(value)
    if value == nil then
        return false
    end

    if issecretvalue then
        local okSecretValue, isSecretValue = pcall(issecretvalue, value)
        if okSecretValue and isSecretValue == true then
            return true
        end
    end

    if issecrettable then
        local okSecretTable, isSecretTable = pcall(issecrettable, value)
        if okSecretTable and isSecretTable == true then
            return true
        end
    end

    if hasanysecretvalues then
        local okAnySecrets, hasSecrets = pcall(hasanysecretvalues, value)
        if okAnySecrets and hasSecrets == true then
            return true
        end
    end

    return false
end

local function PvPScalpel_SanitizeLobbyScanValue(value)
    local sanitized = value
    if scrubsecretvalues then
        local ok, safeValue = pcall(scrubsecretvalues, value)
        if ok then
            sanitized = safeValue
        end
    end

    if PvPScalpel_IsSecretLobbyScanValue(sanitized) then
        return nil
    end

    return sanitized
end

local function PvPScalpel_NormalizeRealmLookupKey(realm)
    if type(realm) ~= "string" or realm == "" then
        return nil
    end

    local key = realm:lower():gsub("[%s%-']", "")
    if key == "" then
        return nil
    end

    return key
end

local function PvPScalpel_SplitCharacterAndRealm(fullName)
    if type(fullName) ~= "string" or fullName == "" then
        return nil, nil
    end

    local characterName, realmName = fullName:match("^([^%-]+)%-(.+)$")
    if characterName then
        return characterName, realmName
    end

    return fullName, nil
end

local function PvPScalpel_TryGetLiveUnitIdentity(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil, nil
    end

    local okExists, exists = pcall(UnitExists, unit)
    if not okExists or not exists then
        return nil, nil
    end

    local name, realm = UnitNameUnmodified(unit)
    if not name or name == "" then
        name, realm = UnitFullName(unit)
    end

    if realm == "" then
        realm = nil
    end

    return name, realm
end

local function PvPScalpel_ResolveDisplayRealm(realm)
    if type(realm) ~= "string" or realm == "" then
        return nil
    end

    local lookupKey = PvPScalpel_NormalizeRealmLookupKey(realm)
    if not lookupKey then
        return nil
    end

    local currentRealm = GetRealmName and GetRealmName()
    if type(currentRealm) == "string" and currentRealm ~= "" then
        local currentRealmKey = PvPScalpel_NormalizeRealmLookupKey(currentRealm)
        if currentRealmKey == lookupKey then
            return currentRealm
        end
    end

    if GetAutoCompleteRealms then
        local realms = GetAutoCompleteRealms()
        if type(realms) == "table" then
            for i = 1, #realms do
                local candidate = realms[i]
                if PvPScalpel_NormalizeRealmLookupKey(candidate) == lookupKey then
                    return candidate
                end
            end
        end
    end

    return realm
end

local function PvPScalpel_NormalizeAsciiRealmSlug(realm)
    if type(realm) ~= "string" or realm == "" then
        return "unknown-realm"
    end

    if type(PvPScalpel_Slugify) == "function" then
        local exactSlug = PvPScalpel_Slugify(realm)
        if type(exactSlug) == "string" and exactSlug ~= "" then
            return exactSlug
        end
    end

    local normalized = realm
    for source, replacement in pairs(PvPScalpel_CyrillicToLatinMap) do
        normalized = normalized:gsub(source, replacement)
    end

    normalized = normalized
        :gsub("([a-z])([A-Z])", "%1 %2")
        :gsub("[%s%-_]+", "-")
        :lower()
        :gsub("[^a-z0-9%-]", "-")
        :gsub("%-+", "-")
        :gsub("^%-+", "")
        :gsub("%-+$", "")

    if normalized == "" then
        return "unknown-realm"
    end

    return normalized
end

local function PvPScalpel_GetCurrentRegionCode()
    if type(GetCurrentRegionName) == "function" then
        local okName, regionName = pcall(GetCurrentRegionName)
        if okName and type(regionName) == "string" and regionName ~= "" then
            return string.lower(regionName)
        end
    end

    if type(GetCurrentRegion) == "function" then
        local okId, regionId = pcall(GetCurrentRegion)
        if okId and type(regionId) == "number" then
            if regionId == 1 then
                return "us"
            elseif regionId == 2 then
                return "kr"
            elseif regionId == 3 then
                return "eu"
            elseif regionId == 4 then
                return "tw"
            elseif regionId == 5 then
                return "cn"
            end
        end
    end

    return "unknown"
end

local function PvPScalpel_BuildCharacterNameRealm(contextData)
    if type(contextData) ~= "table" then
        return nil
    end

    local name
    local realmSource

    local contextName, contextRealm = PvPScalpel_SplitCharacterAndRealm(contextData.name)
    name = contextName
    realmSource = contextData.server or contextRealm or GetNormalizedRealmName() or GetRealmName()

    if (not name or name == "") and type(contextData.unit) == "string" and contextData.unit ~= "" then
        local liveName, liveRealm = PvPScalpel_TryGetLiveUnitIdentity(contextData.unit)
        if liveName and liveName ~= "" then
            name = liveName
            realmSource = liveRealm or realmSource
        end
    elseif not realmSource or realmSource == "" then
        local _, contextRealm = PvPScalpel_SplitCharacterAndRealm(contextData.name)
        realmSource = contextData.server or contextRealm or GetNormalizedRealmName() or GetRealmName()
    end

    if not name or name == "" then
        return nil
    end

    local displayRealm = PvPScalpel_ResolveDisplayRealm(realmSource)
    if not displayRealm or displayRealm == "" then
        return nil
    end

    return string.format("%s-%s", name, displayRealm)
end

local function PvPScalpel_GetUnitPopupNoticeFrame()
    if PvPScalpel_UnitPopupNoticeFrame then
        return PvPScalpel_UnitPopupNoticeFrame
    end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    frame:SetSize(900, 48)
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    text:SetTextColor(1, 0.82, 0)
    frame.text = text

    local anim = frame:CreateAnimationGroup()
    local fade = anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(2.0)
    fade:SetSmoothing("OUT")
    anim:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
    end)
    frame.anim = anim

    PvPScalpel_UnitPopupNoticeFrame = frame
    return frame
end

local function PvPScalpel_ShowClipboardNotice(text)
    local frame = PvPScalpel_GetUnitPopupNoticeFrame()
    frame.text:SetText(text or "")
    frame.anim:Stop()
    frame:SetAlpha(1)
    frame:Show()
    frame.anim:Play()
end

local function PvPScalpel_GetCopyDialogDisplayText(text)
    local rawText = type(text) == "string" and text or ""
    return rawText:gsub("|", "||")
end

local function PvPScalpel_ApplyCopyDialogText(editBox, text)
    if type(editBox) ~= "table" then
        return false, "missing_editbox"
    end

    local desiredText = PvPScalpel_GetCopyDialogDisplayText(text)

    editBox:SetText(desiredText)
    local currentText = type(editBox.GetText) == "function" and (editBox:GetText() or "") or ""
    if currentText == desiredText then
        return true, "SetText"
    end

    editBox:SetText("")
    if desiredText ~= "" and type(editBox.Insert) == "function" then
        editBox:Insert(desiredText)
        currentText = type(editBox.GetText) == "function" and (editBox:GetText() or "") or ""
        if currentText == desiredText then
            return true, "Insert"
        end
    end

    editBox:SetText("")
    return desiredText == "", desiredText == "" and "empty" or "failed"
end

local function PvPScalpel_GetUnitPopupUrlDialog()
    if PvPScalpel_UnitPopupUrlDialog then
        return PvPScalpel_UnitPopupUrlDialog
    end

    local frame = CreateFrame("Frame", "PvPScalpelUnitPopupUrlDialog", UIParent, "BasicFrameTemplateWithInset")
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(620, 132)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 110)
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame.TitleText:SetText("Copy name-realm")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -34)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Press Ctrl+C to copy, then Esc to close.")
    frame.subtitle = subtitle

    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    editBox:SetPoint("TOPRIGHT", subtitle, "BOTTOMRIGHT", 0, -12)
    editBox:SetHeight(32)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:GetParent():Hide()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:HighlightText()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        local parent = self:GetParent()
        if not parent or parent.restoringText == true or userInput ~= true then
            return
        end

        parent.restoringText = true
        if type(parent.ApplySourceText) == "function" then
            parent:ApplySourceText()
        else
            self:SetText(type(parent.sourceText) == "string" and parent.sourceText or "")
            self:HighlightText()
        end
        parent.restoringText = false
    end)
    frame.editBox = editBox

    frame.ApplySourceText = function(self)
        local text = type(self.sourceText) == "string" and self.sourceText or ""
        self.restoringText = true
        local ok, method = PvPScalpel_ApplyCopyDialogText(self.editBox, text)
        if not ok and type(PvPScalpel_DebugWriteMessage) == "function" then
            PvPScalpel_DebugWriteMessage(
                string.format(
                    "|cff00ff98[PvP Scalpel]|r [CopyDialog] populate failed title=%s len=%d method=%s",
                    tostring(self.TitleText and self.TitleText.GetText and self.TitleText:GetText() or "unknown"),
                    string.len(text or ""),
                    tostring(method or "unknown")
                )
            )
        end
        if type(self.editBox.SetCursorPosition) == "function" then
            self.editBox:SetCursorPosition(0)
        end
        self.editBox:HighlightText()
        self.restoringText = false
    end

    frame:SetScript("OnShow", function(self)
        self.editBox:SetFocus()
        self:ApplySourceText()
    end)
    frame:SetScript("OnHide", function(self)
        self.sourceText = nil
        self.restoringText = false
        self.pendingTitle = nil
        self.editBox:SetText("")
        self.editBox:ClearFocus()
    end)

    if not PvPScalpel_UnitPopupDialogEscRegistered then
        tinsert(UISpecialFrames, frame:GetName())
        PvPScalpel_UnitPopupDialogEscRegistered = true
    end

    PvPScalpel_UnitPopupUrlDialog = frame
    return frame
end

local function PvPScalpel_ShowUnitPopupUrlDialog(url, title)
    local frame = PvPScalpel_GetUnitPopupUrlDialog()
    frame.TitleText:SetText(type(title) == "string" and title ~= "" and title or "Copy name-realm")
    frame.sourceText = url or ""
    frame:Show()
    frame:Raise()
    frame.editBox:SetFocus()
    frame:ApplySourceText()
end

local function PvPScalpel_ShowLobbyScanCopyDialog(text)
    if type(text) ~= "string" or text == "" then
        return
    end

    PvPScalpel_ShowUnitPopupUrlDialog(text, "Copy lobby scan")
    PvPScalpel_ShowClipboardNotice("Press Ctrl+C to copy lobby scan")
end

local function PvPScalpel_ShowCopyTextDialog(text, title, notice)
    if type(text) ~= "string" or text == "" then
        return
    end

    PvPScalpel_ShowUnitPopupUrlDialog(text, title)
    if type(notice) == "string" and notice ~= "" then
        PvPScalpel_ShowClipboardNotice(notice)
    end
end

function PvPScalpel_OpenLobbyScanCopyDialog(text)
    PvPScalpel_ShowLobbyScanCopyDialog(text)
end

function PvPScalpel_OpenCopyTextDialog(text, title, notice)
    PvPScalpel_ShowCopyTextDialog(text, title, notice)
end

local function PvPScalpel_IsDebugEnabled()
    return PvPScalpel_Debug == true
end

local function PvPScalpel_IsOutOfPvpInstance()
    if type(IsInInstance) ~= "function" then
        return true
    end

    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok or inInstance ~= true then
        return true
    end

    return instanceType ~= "pvp" and instanceType ~= "arena"
end

local function PvPScalpel_IsSelfPopupContext(contextData)
    if type(contextData) ~= "table" then
        return false
    end

    if contextData.unit == "player" then
        return true
    end

    local playerName = type(UnitName) == "function" and UnitName("player") or nil
    local contextName = type(contextData.name) == "string" and contextData.name or nil
    if type(playerName) ~= "string" or playerName == "" or type(contextName) ~= "string" or contextName == "" then
        return false
    end

    local contextCharacterName = PvPScalpel_SplitCharacterAndRealm(contextName)
    return contextCharacterName == playerName
end

local function PvPScalpel_SafeLobbyScanPvpFlag(methodName)
    if not C_PvP then
        return false
    end

    local fn = C_PvP[methodName]
    if type(fn) ~= "function" then
        return false
    end

    local ok, value = pcall(fn)
    return ok and value == true
end

local function PvPScalpel_GetPregateLobbyScanFormat()
    if PvPScalpel_SafeLobbyScanPvpFlag("IsRatedSoloShuffle")
        or PvPScalpel_SafeLobbyScanPvpFlag("IsSoloShuffle")
        or PvPScalpel_SafeLobbyScanPvpFlag("IsBrawlSoloShuffle")
    then
        return "Solo Shuffle"
    end

    if PvPScalpel_SafeLobbyScanPvpFlag("IsSoloRBG")
        or PvPScalpel_SafeLobbyScanPvpFlag("IsRatedSoloRBG")
        or PvPScalpel_SafeLobbyScanPvpFlag("IsBrawlSoloRBG")
    then
        return "Battleground Blitz"
    end

    if PvPScalpel_SafeLobbyScanPvpFlag("IsRatedArena") then
        local bracket = type(PvPScalpel_GetActiveMatchBracket) == "function" and PvPScalpel_GetActiveMatchBracket() or nil
        if bracket == 1 then
            return "Rated Arena 2v2"
        end
        if bracket == 2 then
            return "Rated Arena 3v3"
        end
        return "Rated Arena"
    end

    if PvPScalpel_SafeLobbyScanPvpFlag("IsRatedBattleground") then
        return "Rated Battleground"
    end

    if type(PvPScalpel_FormatChecker) == "function" then
        return PvPScalpel_FormatChecker()
    end

    return nil
end

local function PvPScalpel_GetLobbyScanConfig()
    if PvPScalpel_WaitingForGateOpen ~= true then
        return nil
    end

    if type(PvPScalpel_IsLiveMatchStarted) == "function" and PvPScalpel_IsLiveMatchStarted() then
        return nil
    end

    local format = PvPScalpel_GetPregateLobbyScanFormat()
    if format == "Battleground Blitz" then
        return {
            format = format,
            bracketName = "[Battleground Blitz]",
            expectedLocalCount = 8,
            expectedAllyCount = 8,
            expectedEnemyCount = 8,
            expectedTotalLobbyCount = 16,
            rosterMode = "raid",
        }
    end

    if format == "Solo Shuffle" then
        return {
            format = format,
            bracketName = "[Solo Shuffle]",
            expectedLocalCount = 3,
            expectedAllyCount = 3,
            expectedEnemyCount = 0,
            expectedTotalLobbyCount = 6,
            rosterMode = "party",
        }
    end

    if format == "Rated Arena 2v2" then
        return {
            format = format,
            bracketName = "[Rated Arena 2v2]",
            expectedLocalCount = 2,
            expectedAllyCount = 2,
            expectedEnemyCount = 0,
            expectedTotalLobbyCount = 2,
            rosterMode = "party",
        }
    end

    if format == "Rated Arena 3v3" then
        return {
            format = format,
            bracketName = "[Rated Arena 3v3]",
            expectedLocalCount = 3,
            expectedAllyCount = 3,
            expectedEnemyCount = 0,
            expectedTotalLobbyCount = 3,
            rosterMode = "party",
        }
    end

    if format == "Rated Battleground" then
        return {
            format = format,
            bracketName = "[Rated Battleground]",
            expectedLocalCount = 10,
            expectedAllyCount = 10,
            expectedEnemyCount = 0,
            expectedTotalLobbyCount = 10,
            rosterMode = "raid",
        }
    end

    return nil
end

local function PvPScalpel_IsLobbyScanPregateContext()
    return PvPScalpel_GetLobbyScanConfig() ~= nil
end

local function PvPScalpel_ShouldKeepLobbyScanWatcherAlive()
    return PvPScalpel_WaitingForGateOpen == true
end

local BRACKET_UNKNOWN = 0
local BRACKET_SOLO_SHUFFLE = 1
local BRACKET_BATTLEGROUND_BLITZ = 2
local BRACKET_RATED_ARENA_2V2 = 3
local BRACKET_RATED_ARENA_3V3 = 4
local BRACKET_RATED_ARENA = 5
local BRACKET_RATED_BATTLEGROUND = 6

local function PvPScalpel_GetLobbyScanBracketCode(config)
    local format = type(config) == "table" and config.format or nil
    if format == "Solo Shuffle" then
        return BRACKET_SOLO_SHUFFLE
    end
    if format == "Battleground Blitz" then
        return BRACKET_BATTLEGROUND_BLITZ
    end
    if format == "Rated Arena 2v2" then
        return BRACKET_RATED_ARENA_2V2
    end
    if format == "Rated Arena 3v3" then
        return BRACKET_RATED_ARENA_3V3
    end
    if format == "Rated Arena" then
        return BRACKET_RATED_ARENA
    end
    if format == "Rated Battleground" then
        return BRACKET_RATED_BATTLEGROUND
    end
    return BRACKET_UNKNOWN
end

local function PvPScalpel_GetMockLobbyScanConfig()
    return {
        format = "Battleground Blitz",
        bracketName = "[Battleground Blitz]",
        expectedLocalCount = 8,
        expectedAllyCount = 8,
        expectedEnemyCount = 8,
        expectedTotalLobbyCount = 16,
        rosterMode = "raid",
    }
end

local function PvPScalpel_GetMockLobbyScanEntries()
    return {
        ally = {
            "Lychezar:chamber-of-aspects:eu(73)",
            "Bluelights:argent-dawn:eu(257)",
            "Sqüídwàrd:argent-dawn:eu(253)",
            "Ben:ghostlands:eu(70)",
            "Ganikx:silvermoon:eu(577)",
            "Vikrr:silvermoon:eu(256)",
            "Bibimbaptism:silvermoon:eu(258)",
            "Destraz:silvermoon:eu(1468)",
        },
        enemy = {
            "Arenafox:stormscale:eu(254)",
            "Mindlock:burning-legion:eu(258)",
            "Shieldrun:ravencrest:eu(73)",
            "Mistweave:kazzak:eu(270)",
            "Shadowalt:outland:eu(258)",
            "Rotblast:tarren-mill:eu(252)",
            "Moonshot:silvermoon:eu(254)",
            "Hammerx:dreanor:eu(70)",
        },
    }
end

local function PvPScalpel_GetInstanceGroupCount()
    if type(GetNumGroupMembers) ~= "function" then
        return 0
    end

    local category = LE_PARTY_CATEGORY_INSTANCE
    if type(category) == "number" then
        local ok, count = pcall(GetNumGroupMembers, category)
        if ok and type(count) == "number" and count >= 0 then
            return count
        end
    end

    local ok, count = pcall(GetNumGroupMembers)
    if ok and type(count) == "number" and count >= 0 then
        return count
    end

    return 0
end

local function PvPScalpel_GetLobbyScanExpectedLocalCount()
    local config = PvPScalpel_GetLobbyScanConfig()
    if type(config) ~= "table" then
        return 0
    end
    return type(config.expectedLocalCount) == "number" and config.expectedLocalCount or 0
end

local function PvPScalpel_ClearBlitzLobbyInspectState()
    PvPScalpel_BlitzLobbySpecCache = {}
    PvPScalpel_BlitzLobbySpecRetryAfter = {}
    PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid = {}
    PvPScalpel_BlitzLobbyEnemyLastSignature = nil
    PvPScalpel_BlitzLobbyEnemyLastImprovedAt = 0
    PvPScalpel_BlitzLobbyEnemySettledAt = nil
    PvPScalpel_ClearBlitzLobbyScanFailure()
    PvPScalpel_BlitzLobbyInspectPendingGuid = nil
    PvPScalpel_BlitzLobbyInspectPendingUnit = nil
    PvPScalpel_BlitzLobbyInspectPendingAt = 0
    if type(ClearInspectPlayer) == "function" then
        pcall(ClearInspectPlayer)
    end
end

local function PvPScalpel_ClearPendingBlitzLobbyInspect(setRetry)
    local pendingGuid = PvPScalpel_BlitzLobbyInspectPendingGuid
    if setRetry and type(pendingGuid) == "string" and pendingGuid ~= "" then
        PvPScalpel_BlitzLobbySpecRetryAfter[pendingGuid] = GetTime() + PvPScalpel_BlitzLobbyInspectRetrySeconds
        PvPScalpel_SetBlitzLobbyScanFailure("inspect timeout")
        PvPScalpel_LogLobbyScan("inspect timed out for " .. pendingGuid)
    end

    PvPScalpel_BlitzLobbyInspectPendingGuid = nil
    PvPScalpel_BlitzLobbyInspectPendingUnit = nil
    PvPScalpel_BlitzLobbyInspectPendingAt = 0
    if type(ClearInspectPlayer) == "function" then
        pcall(ClearInspectPlayer)
    end
end

local function PvPScalpel_ExpireTimedOutBlitzLobbyInspect()
    local pendingGuid = PvPScalpel_BlitzLobbyInspectPendingGuid
    if type(pendingGuid) ~= "string" or pendingGuid == "" then
        return
    end

    local pendingAt = PvPScalpel_BlitzLobbyInspectPendingAt or 0
    if pendingAt <= 0 or (GetTime() - pendingAt) < PvPScalpel_BlitzLobbyInspectTimeoutSeconds then
        return
    end

    PvPScalpel_ClearPendingBlitzLobbyInspect(true)
end

local function PvPScalpel_GetCurrentPlayerSpecID()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end

    local specIndex = GetSpecialization()
    if type(specIndex) ~= "number" or specIndex <= 0 then
        return nil
    end

    local specID = GetSpecializationInfo(specIndex)
    if type(specID) == "number" and specID > 0 then
        return specID
    end

    return nil
end

local function PvPScalpel_TryQueueBlitzLobbyInspect(unit, guid)
    if type(unit) ~= "string" or unit == "" or type(guid) ~= "string" or guid == "" then
        return nil
    end

    if type(PvPScalpel_BlitzLobbyInspectPendingGuid) == "string" and PvPScalpel_BlitzLobbyInspectPendingGuid ~= "" then
        return nil
    end

    local retryAfter = PvPScalpel_BlitzLobbySpecRetryAfter[guid]
    if type(retryAfter) == "number" and retryAfter > GetTime() then
        return nil
    end

    if PvPScalpel_BlitzLobbyInspectPendingGuid == guid then
        return nil
    end

    if type(CanInspect) ~= "function" or type(NotifyInspect) ~= "function" then
        PvPScalpel_SetBlitzLobbyScanFailure("inspect api unavailable")
        if PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid[guid] ~= "inspect_api_unavailable" then
            PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid[guid] = "inspect_api_unavailable"
            PvPScalpel_LogLobbyScan("inspect skipped for " .. guid .. " (inspect API unavailable)")
        end
        return nil
    end

    local okCanInspect, canInspect = pcall(CanInspect, unit, true)
    if not okCanInspect or not canInspect then
        PvPScalpel_SetBlitzLobbyScanFailure("cannot inspect teammate")
        if PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid[guid] ~= "cannot_inspect" then
            PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid[guid] = "cannot_inspect"
            PvPScalpel_LogLobbyScan("inspect skipped for " .. guid .. " (cannot inspect " .. unit .. ")")
        end
        return nil
    end

    local okNotify = pcall(NotifyInspect, unit)
    if not okNotify then
        PvPScalpel_SetBlitzLobbyScanFailure("notify inspect failed")
        if PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid[guid] ~= "notify_failed" then
            PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid[guid] = "notify_failed"
            PvPScalpel_LogLobbyScan("inspect skipped for " .. guid .. " (NotifyInspect failed)")
        end
        return nil
    end

    PvPScalpel_BlitzLobbyInspectPendingGuid = guid
    PvPScalpel_BlitzLobbyInspectPendingUnit = unit
    PvPScalpel_BlitzLobbyInspectPendingAt = GetTime()
    PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid[guid] = nil
    if PvPScalpel_BlitzLobbyScanFailureReason == "inspect timeout" then
        PvPScalpel_ClearBlitzLobbyScanFailure()
    end
    PvPScalpel_LogLobbyScan("inspect requested for " .. guid .. " via " .. unit)
    return nil
end

local function PvPScalpel_GetBlitzLobbyUnitSpecID(unit, guid)
    if type(guid) ~= "string" or guid == "" then
        return nil
    end

    if unit == "player" then
        return PvPScalpel_GetCurrentPlayerSpecID()
    end

    local cachedSpecID = PvPScalpel_BlitzLobbySpecCache[guid]
    if type(cachedSpecID) == "number" and cachedSpecID > 0 then
        return cachedSpecID
    end

    return PvPScalpel_TryQueueBlitzLobbyInspect(unit, guid)
end

local function PvPScalpel_AppendBlitzLobbyUnitEntry(unit, seenGuids, entries)
    if type(unit) ~= "string" or unit == "" then
        return false, false
    end

    local guid = UnitGUID and UnitGUID(unit) or nil
    if type(guid) ~= "string" or guid == "" or seenGuids[guid] then
        return false, false
    end
    seenGuids[guid] = true

    local name, realm = PvPScalpel_TryGetLiveUnitIdentity(unit)
    if type(name) ~= "string" or name == "" then
        return true, false
    end

    local displayRealm = PvPScalpel_ResolveDisplayRealm(realm or GetRealmName() or GetNormalizedRealmName())
    if type(displayRealm) ~= "string" or displayRealm == "" then
        return true, false
    end

    local specID = PvPScalpel_GetBlitzLobbyUnitSpecID(unit, guid)
    if type(specID) ~= "number" or specID <= 0 then
        return true, false
    end

    local normalizedRealmSlug = PvPScalpel_NormalizeAsciiRealmSlug(displayRealm)
    local regionCode = PvPScalpel_GetCurrentRegionCode()
    table.insert(entries, string.format("%s:%s:%s(%d)", name, normalizedRealmSlug, regionCode, specID))
    return true, true
end

local function PvPScalpel_CollectBlitzLobbyRoster()
    local config = PvPScalpel_GetLobbyScanConfig()
    local seenGuids = {}
    local entries = {}
    local joinedCount = 0
    local resolvedCount = 0
    local expectedLocalCount = type(config) == "table" and config.expectedLocalCount or 0
    local rosterMode = type(config) == "table" and config.rosterMode or "raid"

    local candidateUnits = {}
    if rosterMode == "party" then
        table.insert(candidateUnits, "player")
        for i = 1, 5 do
            table.insert(candidateUnits, "party" .. tostring(i))
        end
        for i = 1, 6 do
            table.insert(candidateUnits, "raid" .. tostring(i))
        end
    else
        local totalMembers = PvPScalpel_GetInstanceGroupCount()
        for i = 1, totalMembers do
            table.insert(candidateUnits, "raid" .. tostring(i))
        end
        table.insert(candidateUnits, "player")
    end

    for i = 1, #candidateUnits do
        local joined, resolved = PvPScalpel_AppendBlitzLobbyUnitEntry(candidateUnits[i], seenGuids, entries)
        if joined then
            joinedCount = joinedCount + 1
        end
        if resolved then
            resolvedCount = resolvedCount + 1
        end
        if expectedLocalCount > 0 and joinedCount >= expectedLocalCount and resolvedCount >= expectedLocalCount then
            break
        end
    end

    if joinedCount == 0 then
        local joined, resolved = PvPScalpel_AppendBlitzLobbyUnitEntry("player", seenGuids, entries)
        if joined then
            joinedCount = joinedCount + 1
        end
        if resolved then
            resolvedCount = resolvedCount + 1
        end
    end

    return entries, joinedCount, resolvedCount
end

local function PvPScalpel_PrepareLobbyScanScoreboardRead()
    if type(PvPScalpel_PrepareScoreboardRead) == "function" then
        PvPScalpel_PrepareScoreboardRead()
        return
    end

    if SetBattlefieldScoreFaction then
        pcall(SetBattlefieldScoreFaction, -1)
    end
    if RequestBattlefieldScoreData then
        pcall(RequestBattlefieldScoreData)
    end
end

local function PvPScalpel_GetLobbyScanClassIDByToken(classToken)
    if type(classToken) ~= "string" or classToken == "" then
        return nil
    end

    if type(PvPScalpel_BlitzLobbyClassTokenToClassID) ~= "table" then
        PvPScalpel_BlitzLobbyClassTokenToClassID = {}
        if type(GetClassInfo) == "function" then
            for classID = 1, 20 do
                local _, classTokenValue = GetClassInfo(classID)
                if type(classTokenValue) == "string" and classTokenValue ~= "" then
                    PvPScalpel_BlitzLobbyClassTokenToClassID[string.upper(classTokenValue)] = classID
                end
            end
        end
    end

    return PvPScalpel_BlitzLobbyClassTokenToClassID[string.upper(classToken)]
end

local function PvPScalpel_ResolveBlitzEnemySpecID(classToken, talentSpec)
    local sanitizedClassToken = PvPScalpel_SanitizeLobbyScanValue(classToken)
    local sanitizedTalentSpec = PvPScalpel_SanitizeLobbyScanValue(talentSpec)
    if type(sanitizedClassToken) ~= "string"
        or sanitizedClassToken == ""
        or type(sanitizedTalentSpec) ~= "string"
        or sanitizedTalentSpec == ""
    then
        return nil
    end

    local cacheKey = string.upper(sanitizedClassToken) .. ":" .. string.lower(sanitizedTalentSpec)
    local cachedSpecID = PvPScalpel_BlitzLobbyEnemySpecIDByKey[cacheKey]
    if cachedSpecID ~= nil then
        return cachedSpecID or nil
    end

    local classID = PvPScalpel_GetLobbyScanClassIDByToken(sanitizedClassToken)
    if type(classID) ~= "number"
        or classID <= 0
        or not C_SpecializationInfo
        or type(C_SpecializationInfo.GetNumSpecializationsForClassID) ~= "function"
        or type(GetSpecializationInfoForClassID) ~= "function"
    then
        PvPScalpel_BlitzLobbyEnemySpecIDByKey[cacheKey] = false
        return nil
    end

    local specCount = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    local loweredTalentSpec = string.lower(sanitizedTalentSpec)
    for specIndex = 1, specCount do
        local ok, specID, specName = pcall(GetSpecializationInfoForClassID, classID, specIndex)
        specName = PvPScalpel_SanitizeLobbyScanValue(specName)
        if ok
            and type(specID) == "number"
            and specID > 0
            and type(specName) == "string"
            and specName ~= ""
            and (specName == sanitizedTalentSpec or string.lower(specName) == loweredTalentSpec)
        then
            PvPScalpel_BlitzLobbyEnemySpecIDByKey[cacheKey] = specID
            return specID
        end
    end

    PvPScalpel_BlitzLobbyEnemySpecIDByKey[cacheKey] = false
    return nil
end

local function PvPScalpel_GetBlitzEnemyLobbyScoreInfo(index)
    if not C_PvP or type(C_PvP.GetScoreInfo) ~= "function" then
        return nil
    end

    local ok, rawScore = pcall(C_PvP.GetScoreInfo, index)
    if not ok then
        return nil
    end

    local score = PvPScalpel_SanitizeLobbyScanValue(rawScore)
    if type(score) ~= "table" then
        return nil
    end

    local playerName = PvPScalpel_SanitizeLobbyScanValue(score.name or score.playerName)
    local guid = PvPScalpel_SanitizeLobbyScanValue(score.guid)
    local classToken = PvPScalpel_SanitizeLobbyScanValue(score.classToken)
    local talentSpec = PvPScalpel_SanitizeLobbyScanValue(score.talentSpec)
    local faction = PvPScalpel_SanitizeLobbyScanValue(score.faction)
    if type(guid) ~= "string" or guid == "" or type(faction) ~= "number" then
        return nil
    end

    return {
        guid = guid,
        name = playerName,
        classToken = classToken,
        talentSpec = talentSpec,
        faction = faction,
    }
end

local function PvPScalpel_GetBlitzEnemyLobbyLocalFaction(totalPlayers)
    local playerGuid = UnitGUID and UnitGUID("player") or nil
    if type(playerGuid) ~= "string" or playerGuid == "" then
        return nil
    end

    for i = 1, totalPlayers do
        local score = PvPScalpel_GetBlitzEnemyLobbyScoreInfo(i)
        if score and score.guid == playerGuid then
            return score.faction
        end
    end

    return nil
end

local function PvPScalpel_BuildBlitzEnemyLobbyEntry(score)
    if type(score) ~= "table" then
        return nil
    end

    local fullName = PvPScalpel_SanitizeLobbyScanValue(score.name)
    local classToken = PvPScalpel_SanitizeLobbyScanValue(score.classToken)
    local talentSpec = PvPScalpel_SanitizeLobbyScanValue(score.talentSpec)
    if type(fullName) ~= "string"
        or fullName == ""
        or type(classToken) ~= "string"
        or classToken == ""
        or type(talentSpec) ~= "string"
        or talentSpec == ""
    then
        return nil
    end

    local name, realm = PvPScalpel_SplitCharacterAndRealm(fullName)
    realm = PvPScalpel_SanitizeLobbyScanValue(realm) or GetRealmName() or GetNormalizedRealmName()
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local displayRealm = PvPScalpel_ResolveDisplayRealm(realm)
    if type(displayRealm) ~= "string" or displayRealm == "" then
        return nil
    end

    local specID = PvPScalpel_ResolveBlitzEnemySpecID(classToken, talentSpec)
    if type(specID) ~= "number" or specID <= 0 then
        return nil
    end

    local normalizedRealmSlug = PvPScalpel_NormalizeAsciiRealmSlug(displayRealm)
    local regionCode = PvPScalpel_GetCurrentRegionCode()
    return string.format("%s:%s:%s(%d)", name, normalizedRealmSlug, regionCode, specID)
end

local function PvPScalpel_CollectBlitzEnemyLobbyRoster(config)
    if type(config) ~= "table" or config.format ~= "Battleground Blitz" then
        return {}, 0, 0
    end

    if not C_PvP or type(C_PvP.GetScoreInfo) ~= "function" or type(GetNumBattlefieldScores) ~= "function" then
        return {}, 0, 0
    end

    PvPScalpel_PrepareLobbyScanScoreboardRead()

    local totalPlayers = GetNumBattlefieldScores() or 0
    if totalPlayers <= 0 then
        return {}, 0, 0
    end

    local localFaction = PvPScalpel_GetBlitzEnemyLobbyLocalFaction(totalPlayers)
    if type(localFaction) ~= "number" then
        return {}, 0, 0
    end

    local expectedEnemyCount = type(config.expectedEnemyCount) == "number" and config.expectedEnemyCount or 0
    local entries = {}
    local seenGuids = {}
    local joinedCount = 0
    local resolvedCount = 0
    for i = 1, totalPlayers do
        local score = PvPScalpel_GetBlitzEnemyLobbyScoreInfo(i)
        if score
            and score.faction ~= localFaction
            and type(score.guid) == "string"
            and score.guid ~= ""
            and not seenGuids[score.guid]
        then
            seenGuids[score.guid] = true
            joinedCount = joinedCount + 1

            local entry = PvPScalpel_BuildBlitzEnemyLobbyEntry(score)
            if type(entry) == "string" and entry ~= "" then
                table.insert(entries, entry)
                resolvedCount = resolvedCount + 1
            end

            if expectedEnemyCount > 0 and joinedCount >= expectedEnemyCount and resolvedCount >= expectedEnemyCount then
                break
            end
        end
    end

    return entries, joinedCount, resolvedCount
end

local function PvPScalpel_IsFullResolvedTeam(joinedCount, resolvedCount, entryCount, expectedCount)
    return type(expectedCount) == "number"
        and expectedCount > 0
        and joinedCount >= expectedCount
        and resolvedCount >= expectedCount
        and entryCount == expectedCount
end

local function PvPScalpel_UpdateBlitzEnemySettledState(config, allyReady, enemyEntries, enemyResolvedCount)
    if not allyReady or type(config) ~= "table" or config.format ~= "Battleground Blitz" then
        PvPScalpel_BlitzLobbyEnemyLastSignature = nil
        PvPScalpel_BlitzLobbyEnemyLastImprovedAt = 0
        PvPScalpel_BlitzLobbyEnemySettledAt = nil
        return false
    end

    local signature = table.concat({
        tostring(enemyResolvedCount or 0),
        type(enemyEntries) == "table" and table.concat(enemyEntries, "|") or "",
    }, "\031")
    local now = PvPScalpel_GetLobbyScanNow()
    if signature ~= PvPScalpel_BlitzLobbyEnemyLastSignature then
        PvPScalpel_BlitzLobbyEnemyLastSignature = signature
        PvPScalpel_BlitzLobbyEnemyLastImprovedAt = now
        PvPScalpel_BlitzLobbyEnemySettledAt = nil
    end

    local expectedEnemyCount = type(config.expectedEnemyCount) == "number" and config.expectedEnemyCount or 0
    if expectedEnemyCount > 0 and enemyResolvedCount >= expectedEnemyCount then
        PvPScalpel_BlitzLobbyEnemySettledAt = PvPScalpel_BlitzLobbyEnemySettledAt or now
        return true
    end

    if type(PvPScalpel_BlitzLobbyEnemyLastImprovedAt) == "number"
        and (now - PvPScalpel_BlitzLobbyEnemyLastImprovedAt) >= PvPScalpel_BlitzLobbyEnemySteadyStateSeconds
    then
        PvPScalpel_BlitzLobbyEnemySettledAt = PvPScalpel_BlitzLobbyEnemySettledAt or now
        return true
    end

    return false
end

local function PvPScalpel_BuildBlitzLobbyBuffer(entries, configOverride, enemyEntries)
    local config = configOverride or PvPScalpel_GetLobbyScanConfig()
    local bracketCode = tostring(PvPScalpel_GetLobbyScanBracketCode(config))
    local expectedEnemyCount = type(config) == "table" and type(config.expectedEnemyCount) == "number" and config.expectedEnemyCount or 0
    if expectedEnemyCount > 0 then
        local allySegment = type(entries) == "table" and table.concat(entries, "|") or ""
        local enemySegment = type(enemyEntries) == "table" and table.concat(enemyEntries, "|") or ""
        return bracketCode .. "[" .. allySegment .. "][" .. enemySegment .. "]"
    end

    if type(entries) ~= "table" or #entries == 0 then
        return bracketCode
    end
    return bracketCode .. "|" .. table.concat(entries, "|")
end

PvPScalpel_SetBlitzLobbyScanFailure = function(reason)
    if type(reason) == "string" and reason ~= "" then
        PvPScalpel_BlitzLobbyScanFailureReason = reason
    end
end

PvPScalpel_ClearBlitzLobbyScanFailure = function()
    PvPScalpel_BlitzLobbyScanFailureReason = nil
end

local function PvPScalpel_IsTransientBlitzLobbyScanFailure(reason)
    return reason == "inspect timeout" or reason == "inspect ready without specialization"
end

local function PvPScalpel_GetDisplayedBlitzLobbyScanState(state)
    if state == "READY" then
        return "DONE"
    end
    return state
end

local function PvPScalpel_GetBlitzLobbyScanSnapshotSignature(snapshot)
    if type(snapshot) ~= "table" or snapshot.display ~= true then
        return "hidden"
    end

    return table.concat({
        tostring(snapshot.format or "unknown"),
        tostring(snapshot.scanState or "hidden"),
        tostring(snapshot.joinedCount or 0),
        tostring(snapshot.resolvedCount or 0),
        tostring(snapshot.expectedLocalCount or 0),
        tostring(snapshot.resolvedAllyCount or 0),
        tostring(snapshot.expectedAllyCount or 0),
        tostring(snapshot.resolvedEnemyCount or 0),
        tostring(snapshot.expectedEnemyCount or 0),
        tostring(snapshot.scanPhase or ""),
        tostring(snapshot.entryCount or 0),
        tostring(snapshot.failureReason or ""),
        tostring(snapshot.bufferLength or 0),
    }, "|")
end

local function PvPScalpel_SetActiveBlitzLobbyScanSnapshot(snapshot)
    local signature = PvPScalpel_GetBlitzLobbyScanSnapshotSignature(snapshot)
    if signature == PvPScalpel_BlitzLobbyScanSnapshotSignature then
        PvPScalpel_BlitzLobbyScanSnapshot = snapshot
        return
    end

    PvPScalpel_BlitzLobbyScanSnapshot = snapshot
    PvPScalpel_BlitzLobbyScanSnapshotSignature = signature
    if type(PvPScalpel_BlitzMmrHeaderRefresh) == "function" then
        PvPScalpel_BlitzMmrHeaderRefresh()
    end
end

function PvPScalpel_GetBlitzLobbyScanSnapshot()
    return PvPScalpel_BlitzLobbyScanSnapshot
end

local function PvPScalpel_ComputeBlitzLobbyScanState(config, metrics)
    if PvPScalpel_BlitzLobbyScanMockMode == true then
        return "MOCK", nil
    end

    if type(config) ~= "table" then
        return "FAILED", "no active scan config"
    end

    local expectedAllyCount = type(config.expectedAllyCount) == "number" and config.expectedAllyCount
        or (type(config.expectedLocalCount) == "number" and config.expectedLocalCount or 0)
    local allyJoinedCount = type(metrics) == "table" and metrics.allyJoinedCount or 0
    local allyResolvedCount = type(metrics) == "table" and metrics.allyResolvedCount or 0
    local allyEntryCount = type(metrics) == "table" and metrics.allyEntryCount or 0
    local ready = PvPScalpel_IsFullResolvedTeam(allyJoinedCount, allyResolvedCount, allyEntryCount, expectedAllyCount)
    if config.format == "Battleground Blitz" then
        ready = ready and type(metrics) == "table" and metrics.enemySettled == true
    end

    if ready then
        return "READY", nil
    end

    if type(PvPScalpel_BlitzLobbyScanFailureReason) == "string" and PvPScalpel_BlitzLobbyScanFailureReason ~= "" then
        if not PvPScalpel_IsTransientBlitzLobbyScanFailure(PvPScalpel_BlitzLobbyScanFailureReason) then
            return "FAILED", PvPScalpel_BlitzLobbyScanFailureReason
        end
    end

    return "LOADING", nil
end

local function PvPScalpel_LogBlitzLobbyScanState(config, state, joinedCount, resolvedCount, entryCount, bufferLength, failureReason)
    if type(config) ~= "table" then
        return
    end

    local expectedLocalCount = type(config.expectedAllyCount) == "number" and config.expectedAllyCount
        or (type(config.expectedLocalCount) == "number" and config.expectedLocalCount or 0)
    local expectedEnemyCount = type(config.expectedEnemyCount) == "number" and config.expectedEnemyCount or 0
    local expectedCount = expectedLocalCount + expectedEnemyCount
    if expectedCount <= 0 then
        expectedCount = expectedLocalCount
    end
    local signature = table.concat({
        tostring(config.format or "unknown"),
        tostring(joinedCount or 0),
        tostring(resolvedCount or 0),
        tostring(entryCount or 0),
        tostring(state or "LOADING"),
        tostring(bufferLength or 0),
        tostring(failureReason or ""),
    }, "|")

    if PvPScalpel_BlitzLobbyScanLogSignature == signature then
        return
    end

    PvPScalpel_BlitzLobbyScanLogSignature = signature
    PvPScalpel_LogLobbyScan(
        string.format(
            "state=%s format=%s joined=%d resolved=%d entries=%d expected=%d buffer=%d%s",
            tostring(state or "LOADING"),
            tostring(config.format or "unknown"),
            joinedCount or 0,
            resolvedCount or 0,
            entryCount or 0,
            expectedCount,
            bufferLength or 0,
            type(failureReason) == "string" and failureReason ~= "" and (" failure=" .. failureReason) or ""
        )
    )
end

local function PvPScalpel_StopBlitzLobbySpinner(frame)
    if type(frame) ~= "table" then
        return
    end
    frame:SetScript("OnUpdate", nil)
end

local function PvPScalpel_StartBlitzLobbySpinner(frame)
    if type(frame) ~= "table" then
        return
    end
end

local function PvPScalpel_DisableBlitzLobbyScanWatcher()
    if not PvPScalpel_BlitzLobbyScanWatcherActive then
        return
    end
    blitzLobbyScanEventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    blitzLobbyScanEventFrame:UnregisterEvent("INSPECT_READY")
    blitzLobbyScanEventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    blitzLobbyScanEventFrame:UnregisterEvent("PVP_MATCH_ACTIVE")
    blitzLobbyScanEventFrame:UnregisterEvent("PVP_MATCH_STATE_CHANGED")
    blitzLobbyScanEventFrame.refreshElapsed = 0
    blitzLobbyScanEventFrame:SetScript("OnUpdate", nil)
    PvPScalpel_BlitzLobbyScanWatcherActive = false
end

local function PvPScalpel_ClearBlitzLobbyScanWindowState(frame)
    if type(frame) ~= "table" then
        return
    end

    PvPScalpel_StopBlitzLobbySpinner(frame)
    PvPScalpel_ClearBlitzLobbyInspectState()
    frame.mockMode = nil
    frame.mockEntries = nil
    frame.mockConfig = nil
    frame.scanState = nil
    frame.lastFailureReason = nil
    frame.hasResolutionFailure = false
    if frame.progressFill then
        frame.progressFill:SetWidth(0)
    end
    if frame.progressLabel then
        frame.progressLabel:SetText("")
    end
    if frame.editBox then
        frame.editBox:SetText("[Lobby Scan]")
        frame.editBox:ClearFocus()
    end
    frame.lastLoggedScanState = nil
end

local function PvPScalpel_CloseBlitzLobbyScanWindow()
    if PvPScalpel_BlitzLobbyScanWindow then
        PvPScalpel_BlitzLobbyScanWindow:Hide()
    end
end

local PvPScalpel_RefreshBlitzLobbyScanWindow

local function PvPScalpel_ClearActiveBlitzLobbyScanState()
    local hasActiveState = PvPScalpel_BlitzLobbyScanSnapshot ~= nil
        or PvPScalpel_BlitzLobbyScanFailureReason ~= nil
        or PvPScalpel_BlitzLobbyInspectPendingGuid ~= nil
        or next(PvPScalpel_BlitzLobbySpecCache) ~= nil
        or next(PvPScalpel_BlitzLobbySpecRetryAfter) ~= nil
        or next(PvPScalpel_BlitzLobbyLastInspectSkipReasonByGuid) ~= nil
    if not hasActiveState then
        return
    end

    PvPScalpel_BlitzLobbyScanLogSignature = nil
    PvPScalpel_ClearBlitzLobbyInspectState()
    PvPScalpel_SetActiveBlitzLobbyScanSnapshot(nil)
end

local function PvPScalpel_EnableBlitzLobbyScanWatcher()
    if PvPScalpel_BlitzLobbyScanWatcherActive then
        return
    end
    blitzLobbyScanEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    blitzLobbyScanEventFrame:RegisterEvent("INSPECT_READY")
    blitzLobbyScanEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    blitzLobbyScanEventFrame:RegisterEvent("PVP_MATCH_ACTIVE")
    blitzLobbyScanEventFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    blitzLobbyScanEventFrame.refreshElapsed = 0
    blitzLobbyScanEventFrame:SetScript("OnUpdate", function(self, elapsed)
        self.refreshElapsed = (self.refreshElapsed or 0) + elapsed
        if self.refreshElapsed < PvPScalpel_BlitzLobbyRefreshHeartbeatSeconds then
            return
        end
        self.refreshElapsed = 0
        PvPScalpel_RefreshBlitzLobbyScanWindow()
    end)
    PvPScalpel_BlitzLobbyScanWatcherActive = true
end

PvPScalpel_RefreshBlitzLobbyScanWindow = function()
    local liveConfig = PvPScalpel_GetLobbyScanConfig()
    if PvPScalpel_BlitzLobbyScanMockMode == true and type(liveConfig) == "table" then
        PvPScalpel_BlitzLobbyScanMockMode = false
        PvPScalpel_BlitzLobbyScanMockConfig = nil
        PvPScalpel_BlitzLobbyScanMockEntries = nil
    end

    local config = PvPScalpel_BlitzLobbyScanMockMode == true and PvPScalpel_BlitzLobbyScanMockConfig or liveConfig

    if PvPScalpel_BlitzLobbyScanMockMode == true then
        local mockEntries = type(PvPScalpel_BlitzLobbyScanMockEntries) == "table" and PvPScalpel_BlitzLobbyScanMockEntries or {}
        local allyEntries = type(mockEntries.ally) == "table" and mockEntries.ally or {}
        local enemyEntries = type(mockEntries.enemy) == "table" and mockEntries.enemy or {}
        local expectedAllyCount = type(config.expectedAllyCount) == "number" and config.expectedAllyCount or #allyEntries
        local expectedEnemyCount = type(config.expectedEnemyCount) == "number" and config.expectedEnemyCount or #enemyEntries
        local expectedLocalCount = expectedAllyCount + expectedEnemyCount
        local resolvedCount = #allyEntries + #enemyEntries
        local mockBuffer = PvPScalpel_BuildBlitzLobbyBuffer(allyEntries, config, enemyEntries)
        local bufferLength = string.len(mockBuffer or "")
        PvPScalpel_SetActiveBlitzLobbyScanSnapshot({
            display = true,
            format = type(config.format) == "string" and config.format or "Battleground Blitz",
            bracketName = type(config.bracketName) == "string" and config.bracketName or "[Lobby Scan]",
            scanState = "MOCK",
            scanPhase = "DONE",
            expectedLocalCount = expectedLocalCount,
            expectedAllyCount = expectedAllyCount,
            expectedEnemyCount = expectedEnemyCount,
            joinedCount = resolvedCount,
            joinedAllyCount = #allyEntries,
            joinedEnemyCount = #enemyEntries,
            resolvedCount = resolvedCount,
            resolvedAllyCount = #allyEntries,
            resolvedEnemyCount = #enemyEntries,
            entryCount = resolvedCount,
            allyEntryCount = #allyEntries,
            enemyEntryCount = #enemyEntries,
            progressValue = resolvedCount,
            failureReason = nil,
            buffer = mockBuffer,
            bufferLength = bufferLength,
        })
        PvPScalpel_LogBlitzLobbyScanState(config, "MOCK", resolvedCount, resolvedCount, resolvedCount, bufferLength, nil)
        return
    end

    if type(config) ~= "table" then
        if PvPScalpel_ShouldKeepLobbyScanWatcherAlive() then
            return
        end
        PvPScalpel_DisableBlitzLobbyScanWatcher()
        PvPScalpel_ClearActiveBlitzLobbyScanState()
        return
    end

    PvPScalpel_ExpireTimedOutBlitzLobbyInspect()

    local allyEntries, allyJoinedCount, allyResolvedCount = PvPScalpel_CollectBlitzLobbyRoster()
    local expectedAllyCount = type(config.expectedAllyCount) == "number" and config.expectedAllyCount
        or (type(config.expectedLocalCount) == "number" and config.expectedLocalCount or 1)
    local expectedEnemyCount = type(config.expectedEnemyCount) == "number" and config.expectedEnemyCount or 0
    local allyReady = PvPScalpel_IsFullResolvedTeam(allyJoinedCount, allyResolvedCount, #allyEntries, expectedAllyCount)
    local enemyEntries = {}
    local enemyJoinedCount = 0
    local enemyResolvedCount = 0
    if allyReady and expectedEnemyCount > 0 then
        enemyEntries, enemyJoinedCount, enemyResolvedCount = PvPScalpel_CollectBlitzEnemyLobbyRoster(config)
    else
        PvPScalpel_UpdateBlitzEnemySettledState(config, false, nil, 0)
    end

    local enemySettled = PvPScalpel_UpdateBlitzEnemySettledState(config, allyReady, enemyEntries, enemyResolvedCount)
    local expectedLocalCount = expectedAllyCount + expectedEnemyCount
    if expectedLocalCount <= 0 then
        expectedLocalCount = expectedAllyCount
    end
    local joinedCount = allyJoinedCount + enemyJoinedCount
    local resolvedCount = allyResolvedCount + enemyResolvedCount
    local entryCount = #allyEntries + #enemyEntries
    local progressValue = math.max(0, math.min(resolvedCount, expectedLocalCount))
    local liveBuffer = PvPScalpel_BuildBlitzLobbyBuffer(allyEntries, config, enemyEntries)
    local scanPhase = allyReady and (enemySettled and "DONE" or "ENEMY") or "ALLY"
    local state, failureReason = PvPScalpel_ComputeBlitzLobbyScanState(config, {
        allyJoinedCount = allyJoinedCount,
        allyResolvedCount = allyResolvedCount,
        allyEntryCount = #allyEntries,
        enemyJoinedCount = enemyJoinedCount,
        enemyResolvedCount = enemyResolvedCount,
        enemyEntryCount = #enemyEntries,
        enemySettled = enemySettled,
    })
    if state == "READY" then
        PvPScalpel_ClearBlitzLobbyScanFailure()
        failureReason = nil
    end
    local displayedState = PvPScalpel_GetDisplayedBlitzLobbyScanState(state)
    local bufferLength = string.len(liveBuffer or "")
    PvPScalpel_SetActiveBlitzLobbyScanSnapshot({
        display = true,
        format = type(config.format) == "string" and config.format or "Battleground Blitz",
        bracketName = type(config.bracketName) == "string" and config.bracketName or "[Lobby Scan]",
        scanState = displayedState,
        scanPhase = scanPhase,
        expectedLocalCount = expectedLocalCount,
        expectedAllyCount = expectedAllyCount,
        expectedEnemyCount = expectedEnemyCount,
        joinedCount = joinedCount,
        joinedAllyCount = allyJoinedCount,
        joinedEnemyCount = enemyJoinedCount,
        resolvedCount = resolvedCount,
        resolvedAllyCount = allyResolvedCount,
        resolvedEnemyCount = enemyResolvedCount,
        entryCount = entryCount,
        allyEntryCount = #allyEntries,
        enemyEntryCount = #enemyEntries,
        progressValue = progressValue,
        failureReason = failureReason,
        buffer = liveBuffer,
        bufferLength = bufferLength,
    })
    PvPScalpel_LogBlitzLobbyScanState(config, displayedState, joinedCount, resolvedCount, entryCount, bufferLength, failureReason)
end

local function PvPScalpel_UpdateBlitzLobbyScanWatcherLifecycle()
    if PvPScalpel_BlitzLobbyScanMockMode == true
        or PvPScalpel_IsLobbyScanPregateContext()
        or PvPScalpel_ShouldKeepLobbyScanWatcherAlive()
    then
        PvPScalpel_EnableBlitzLobbyScanWatcher()
        PvPScalpel_RefreshBlitzLobbyScanWindow()
        return
    end

    PvPScalpel_DisableBlitzLobbyScanWatcher()
    PvPScalpel_ClearActiveBlitzLobbyScanState()
end

local function PvPScalpel_GetBlitzLobbyScanWindow()
    if PvPScalpel_BlitzLobbyScanWindow then
        return PvPScalpel_BlitzLobbyScanWindow
    end

    local frame = PvPScalpelBlitzLobbyScanWindow
    if type(frame) ~= "table" then
        return nil
    end

    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)

    local storedLayout = PvPScalpel_GetStoredBlitzLobbyScanLayout()
    if type(storedLayout) == "table" then
        frame:ClearAllPoints()
        frame:SetPoint(
            type(storedLayout.point) == "string" and storedLayout.point or "CENTER",
            UIParent,
            type(storedLayout.relativePoint) == "string" and storedLayout.relativePoint or "CENTER",
            type(storedLayout.x) == "number" and storedLayout.x or 0,
            type(storedLayout.y) == "number" and storedLayout.y or 150
        )
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
    frame:Hide()

    frame.headerCapsule = frame.HeaderCapsule
    frame.titleText = frame.headerCapsule and frame.headerCapsule.TitleText or nil
    frame.progressFrame = frame.ProgressFrame
    frame.progressFill = frame.ProgressFrame and frame.ProgressFrame.Fill or nil
    frame.progressLabel = frame.ProgressFrame and frame.ProgressFrame.Label or nil
    frame.editBoxShell = frame.EditBoxShell
    frame.editBox = frame.EditBox
    frame.dragRegion = frame.DragRegion

    if type(frame.SetBackdrop) == "function" then
        frame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0.03, 0.05, 0.07, 0.26)
        frame:SetBackdropBorderColor(0.24, 0.70, 0.66, 0.22)
    end
    if frame.headerCapsule and type(frame.headerCapsule.SetBackdrop) == "function" then
        frame.headerCapsule:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame.headerCapsule:SetBackdropColor(0.07, 0.14, 0.16, 0.10)
        frame.headerCapsule:SetBackdropBorderColor(0.28, 0.82, 0.78, 0.12)
    end
    if frame.progressFrame and type(frame.progressFrame.SetBackdrop) == "function" then
        frame.progressFrame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            tile = true,
            tileSize = 16,
        })
        frame.progressFrame:SetBackdropColor(0.03, 0.05, 0.07, 0.16)
        frame.progressFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end
    if frame.editBoxShell and type(frame.editBoxShell.SetBackdrop) == "function" then
        frame.editBoxShell:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            tile = true,
            tileSize = 16,
        })
        frame.editBoxShell:SetBackdropColor(0.01, 0.02, 0.03, 0.44)
        frame.editBoxShell:SetBackdropBorderColor(0, 0, 0, 0)
    end

    if frame.titleText then
        frame.titleText:SetText("Lobby Scan - LOADING")
        frame.titleText:SetFontObject("GameFontNormalLarge")
        frame.titleText:SetTextColor(1.00, 0.92, 0.52)
    end
    if frame.progressLabel then
        frame.progressLabel:SetTextColor(0.94, 0.97, 1.00)
    end

    frame.dragRegion:RegisterForDrag("LeftButton")
    frame.dragRegion:SetScript("OnDragStart", function()
        if not InCombatLockdown or not InCombatLockdown() then
            frame:StartMoving()
        end
    end)
    frame.dragRegion:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        PvPScalpel_SaveBlitzLobbyScanLayout(frame)
    end)

    frame.editBox:SetAutoFocus(false)
    frame.editBox:SetMaxLetters(0)
    frame.editBox:EnableKeyboard(false)
    frame.editBox:SetTextInsets(8, 8, 0, 0)
    frame.editBox:SetFontObject("GameFontHighlight")
    frame.editBox:SetTextColor(0.96, 0.98, 1.00)
    frame.editBox:SetJustifyH("LEFT")
    frame.editBox:SetHeight(24)
    if frame.editBox.Left then
        frame.editBox.Left:Hide()
    end
    if frame.editBox.Middle then
        frame.editBox.Middle:Hide()
    end
    if frame.editBox.Right then
        frame.editBox.Right:Hide()
    end
    frame.editBox:Show()
    frame.editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        frame:Hide()
    end)
    frame.editBox:SetScript("OnEnterPressed", function(self)
        if type(self.SetCursorPosition) == "function" then
            self:SetCursorPosition(0)
        end
    end)
    frame.editBox:SetScript("OnEditFocusGained", function(self)
        self:ClearFocus()
    end)
    frame.editBox:SetScript("OnMouseUp", function(self)
        local text = self:GetText()
        if type(text) == "string" and text ~= "" then
            PvPScalpel_ShowLobbyScanCopyDialog(text)
        end
        self:ClearFocus()
    end)

    frame:SetScript("OnShow", function(self)
        if self.mockMode == true then
            PvPScalpel_DisableBlitzLobbyScanWatcher()
        else
            PvPScalpel_EnableBlitzLobbyScanWatcher()
        end
        PvPScalpel_RefreshBlitzLobbyScanWindow()
    end)
    frame:SetScript("OnHide", function(self)
        PvPScalpel_DisableBlitzLobbyScanWatcher()
        PvPScalpel_ClearBlitzLobbyScanWindowState(self)
    end)

    if not PvPScalpel_BlitzLobbyScanWindowEscRegistered then
        tinsert(UISpecialFrames, frame:GetName())
        PvPScalpel_BlitzLobbyScanWindowEscRegistered = true
    end

    PvPScalpel_BlitzLobbyScanWindow = frame
    return frame
end

local function PvPScalpel_OpenBlitzLobbyScanWindow()
    if not PvPScalpel_IsLobbyScanPregateContext() then
        return
    end

    local config = PvPScalpel_GetLobbyScanConfig()
    PvPScalpel_ClearBlitzLobbyScanFailure()
    PvPScalpel_BlitzLobbyScanMockMode = false
    PvPScalpel_BlitzLobbyScanMockConfig = nil
    PvPScalpel_BlitzLobbyScanMockEntries = nil
    if type(config) == "table" then
        PvPScalpel_LogLobbyScan(
            string.format(
                "scan live format=%s expected=%d rosterMode=%s",
                tostring(config.format or "unknown"),
                type(config.expectedLocalCount) == "number" and config.expectedLocalCount or 0,
                tostring(config.rosterMode or "unknown")
            )
        )
    else
        PvPScalpel_LogLobbyScan("scan live with no active lobby scan config")
    end
    PvPScalpel_EnableBlitzLobbyScanWatcher()
    PvPScalpel_RefreshBlitzLobbyScanWindow()
end

local function PvPScalpel_OpenMockLobbyScanWindow()
    PvPScalpel_ClearBlitzLobbyScanFailure()
    PvPScalpel_BlitzLobbyScanMockMode = true
    PvPScalpel_BlitzLobbyScanMockConfig = PvPScalpel_GetMockLobbyScanConfig()
    PvPScalpel_BlitzLobbyScanMockEntries = PvPScalpel_GetMockLobbyScanEntries()
    PvPScalpel_LogLobbyScan("open mock format=Battleground Blitz expected=8")
    PvPScalpel_EnableBlitzLobbyScanWatcher()
    PvPScalpel_RefreshBlitzLobbyScanWindow()
end

blitzLobbyScanEventFrame:SetScript("OnEvent", function(_, event, inspecteeGUID)
    if event == "INSPECT_READY" then
        local pendingGuid = PvPScalpel_BlitzLobbyInspectPendingGuid
        local pendingUnit = PvPScalpel_BlitzLobbyInspectPendingUnit
        if type(pendingGuid) == "string" and pendingGuid ~= "" and pendingGuid == inspecteeGUID then
            local liveGuid = pendingUnit and UnitGUID and UnitGUID(pendingUnit) or nil
            if liveGuid == pendingGuid and type(GetInspectSpecialization) == "function" then
                local okSpec, specID = pcall(GetInspectSpecialization, pendingUnit)
                if okSpec and type(specID) == "number" and specID > 0 then
                    PvPScalpel_BlitzLobbySpecCache[pendingGuid] = specID
                    PvPScalpel_BlitzLobbySpecRetryAfter[pendingGuid] = nil
                    PvPScalpel_LogLobbyScan("inspect ready for " .. pendingGuid .. " specID=" .. tostring(specID))
                else
                    PvPScalpel_SetBlitzLobbyScanFailure("inspect ready without specialization")
                    PvPScalpel_LogLobbyScan("inspect ready without specialization for " .. pendingGuid)
                end
            end
            PvPScalpel_ClearPendingBlitzLobbyInspect(false)
        end
    end

    PvPScalpel_RefreshBlitzLobbyScanWindow()
end)

local function PvPScalpel_AddCopyNameRealmButton(parentDescription, nameRealm)
    if type(parentDescription) ~= "table" or type(nameRealm) ~= "string" or nameRealm == "" then
        return
    end

    parentDescription:CreateButton("Copy name-realm", function()
        PvPScalpel_ShowUnitPopupUrlDialog(nameRealm)
        PvPScalpel_ShowClipboardNotice("Press Ctrl+C to copy name-realm")
    end)
end

local function PvPScalpel_RegisterUnitPopupMenuButton()
    if PvPScalpel_UnitPopupMenuRegistered then
        return
    end

    if not Menu or type(Menu.ModifyMenu) ~= "function" then
        return
    end

    for _, menuTag in ipairs(PvPScalpel_UnitPopupTags) do
        Menu.ModifyMenu(menuTag, function(owner, rootDescription, contextData)
            local nameRealm = PvPScalpel_BuildCharacterNameRealm(contextData)
            local blitzPregate = PvPScalpel_IsLobbyScanPregateContext()
            local showMockScan = PvPScalpel_IsDebugEnabled() and PvPScalpel_IsOutOfPvpInstance() and PvPScalpel_IsSelfPopupContext(contextData)

            if not blitzPregate and not nameRealm and not showMockScan then
                return
            end

            if showMockScan then
                rootDescription:CreateButton("Show mock scan", function()
                    PvPScalpel_OpenMockLobbyScanWindow()
                end)
            end

            if blitzPregate and type(nameRealm) == "string" and nameRealm ~= "" then
                local submenu = rootDescription:CreateButton("PvP Scalpel")
                PvPScalpel_AddCopyNameRealmButton(submenu, nameRealm)
                return
            end

            PvPScalpel_AddCopyNameRealmButton(rootDescription, nameRealm)
        end)
    end

    PvPScalpel_UnitPopupMenuRegistered = true
end

local menuFrame = CreateFrame("Frame")
menuFrame:RegisterEvent("PLAYER_LOGIN")
menuFrame:RegisterEvent("ADDON_LOADED")
menuFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
menuFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
menuFrame:RegisterEvent("PVP_MATCH_ACTIVE")
menuFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
menuFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "Blizzard_Menu" then
        return
    end

    PvPScalpel_RegisterUnitPopupMenuButton()
    PvPScalpel_UpdateBlitzLobbyScanWatcherLifecycle()
end)
