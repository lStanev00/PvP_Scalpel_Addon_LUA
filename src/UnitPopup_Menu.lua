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

local function PvPScalpel_BuildCharacterNameRealm(contextData)
    if type(contextData) ~= "table" then
        return nil
    end

    local name
    local realmSource

    local liveName, liveRealm = PvPScalpel_TryGetLiveUnitIdentity(contextData.unit)
    if liveName and liveName ~= "" then
        name = liveName
        realmSource = liveRealm or GetNormalizedRealmName() or GetRealmName()
    end

    if not name or name == "" then
        local contextName, contextRealm = PvPScalpel_SplitCharacterAndRealm(contextData.name)
        name = contextName
        realmSource = contextData.server or contextRealm or GetNormalizedRealmName() or GetRealmName()
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
    frame.editBox = editBox

    frame:SetScript("OnShow", function(self)
        self.editBox:SetFocus()
        self.editBox:HighlightText()
    end)
    frame:SetScript("OnHide", function(self)
        self.editBox:SetText("")
        self.editBox:ClearFocus()
    end)

    PvPScalpel_UnitPopupUrlDialog = frame
    return frame
end

local function PvPScalpel_ShowUnitPopupUrlDialog(url)
    local frame = PvPScalpel_GetUnitPopupUrlDialog()
    frame.editBox:SetText(url or "")
    frame:Show()
    frame:Raise()
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
            if not nameRealm then
                return
            end

            rootDescription:CreateButton("Copy name-realm", function()
                PvPScalpel_ShowUnitPopupUrlDialog(nameRealm)
                PvPScalpel_ShowClipboardNotice("Press Ctrl+C to copy name-realm")
            end)
        end)
    end

    PvPScalpel_UnitPopupMenuRegistered = true
end

local menuFrame = CreateFrame("Frame")
menuFrame:RegisterEvent("PLAYER_LOGIN")
menuFrame:RegisterEvent("ADDON_LOADED")
menuFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "Blizzard_Menu" then
        return
    end

    PvPScalpel_RegisterUnitPopupMenuButton()
end)
