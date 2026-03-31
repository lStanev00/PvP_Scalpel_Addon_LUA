local PvPScalpel_ExactRealmSlugMap = {
    ["азурегос"] = "azuregos",
    ["aggra (português)"] = "aggra-português",
    ["aggra (portugiesisch)"] = "aggra-português",
    ["борейская тундра"] = "borean-tundra",
    ["chants éternels"] = "chants-éternels",
    ["confrérie du thorium"] = "confrérie-du-thorium",
    ["deephome"] = "deepholm",
    ["etrigg"] = "eitrigg",
    ["festung der stürme"] = "festung-der-stürme",
    ["вечная песня"] = "eversong",
    ["галакронд"] = "galakrond",
    ["голдринн"] = "goldrinn",
    ["гордунни"] = "gordunni",
    ["гром"] = "grom",
    ["дракономор"] = "fordragon",
    ["король лич"] = "lich-king",
    ["la croisade écarlate"] = "la-croisade-écarlate",
    ["marécage de zangar"] = "marécage-de-zangar",
    ["пиратская бухта"] = "booty-bay",
    ["подземье"] = "deepholm",
    ["pozzo dell'eternità"] = "pozzo-delleternità",
    ["разувий"] = "razuvious",
    ["ревущий фьорд"] = "howling-fjord",
    ["ревущийфьорд"] = "howling-fjord",
    ["ревущийфьод"] = "howling-fjord",
    ["свежеватель душ"] = "soulflayer",
    ["седогрив"] = "greymane",
    ["страж смерти"] = "deathguard",
    ["термоштепсель"] = "thermaplugg",
    ["ткач смерти"] = "deathweaver",
    ["well of eternity"] = "pozzo-delleternità",
    ["черный шрам"] = "blackscar",
    ["черныйшрам"] = "blackscar",
    ["ченыйшам"] = "blackscar",
    ["ясеневый лес"] = "ashenvale",
    ["свежеватель душ"] = "soulflayer",
    ["aegwynn"] = "aegwynn",
}

local function PvPScalpel_NormalizeSlugLookupKey(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local key = text
        :lower()
        :gsub("ё", "е")
        :gsub("[%s%-_]+", " ")
        :gsub("%s+", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")

    if key == "" then
        return nil
    end

    return key
end

function PvPScalpel_Slugify(text)
    if not text or text == "" then
        return ""
    end

    local exactKey = PvPScalpel_NormalizeSlugLookupKey(text)
    if exactKey then
        local exactSlug = PvPScalpel_ExactRealmSlugMap[exactKey]
        if exactSlug then
            return exactSlug
        end

        local compactKey = exactKey:gsub("%s+", "")
        if compactKey ~= "" and PvPScalpel_ExactRealmSlugMap[compactKey] then
            return PvPScalpel_ExactRealmSlugMap[compactKey]
        end
    end

    text = text
        :gsub("[-%s]", " ")
        :gsub("([a-z])([A-Z])", "%1 %2")
        :gsub("[%[%]%(%)'`’]", "")
        :gsub("%s+", " ")
        :lower()
        :gsub(" ", "-")

    return text
end
