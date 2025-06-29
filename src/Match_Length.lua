local matchStartTime = nil

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")

frame:SetScript("OnEvent", function(_, event)
    local isInstance, instanceType = IsInInstance()

    if event == "PLAYER_ENTERING_WORLD" and instanceType == "arena" then
        matchStartTime = GetTime()
    elseif event == "PLAYER_LEAVING_WORLD" and instanceType == "arena" and matchStartTime then
        local matchEndTime = GetTime()
        local matchDuration = matchEndTime - matchStartTime
        local matchDurationMinutes = math.floor(matchDuration / 60)
        print("Arena Match Length: " .. matchDurationMinutes .. " minutes")
        matchStartTime = nil
    end
end)
