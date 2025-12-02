function slugify(text)
    if not text or text == "" then return "" end

    -- Normalize text
    text = text:gsub("[-%s]", " ")     -- spaces & dashes → single separators
               :gsub("([a-z])([A-Z])", "%1 %2")  -- split "DunMorogh" → "Dun Morogh"
               :gsub("%s+", " ")        -- collapse multiple spaces
               :lower()                 -- lowercase everything

    -- Replace spaces with dashes
    text = text:gsub(" ", "-")

    return text
end