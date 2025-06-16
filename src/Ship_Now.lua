SLASH_SHIPNOW1 = "/shipnow"
SlashCmdList["SHIPNOW"] = function()
    local lastMatch = PvP_Scalpel_DB[#PvP_Scalpel_DB]

    print("Last Saved Match:")
    for _, p in ipairs(lastMatch) do
        print(string.format(
            "%s-%s | %s (%s) | ΔRating: %s",
            p.name, p.realm, p.spec or "?", p.class or "?", p.ratingChange or "N/A"
        ))
    end
end
