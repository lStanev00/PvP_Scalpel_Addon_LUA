local matchStartTime = GetTime()

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        matchStartTime = GetTime()
    elseif event == "PLAYER_LEAVING_WORLD" then
        local matchEndTime = GetTime()
        local matchDuration = matchEndTime - matchStartTime
        local matchDurationMinutes = math.floor(matchDuration / 60)
        print("Match Length: " .. matchDurationMinutes .. " minutes")
    end
end)
