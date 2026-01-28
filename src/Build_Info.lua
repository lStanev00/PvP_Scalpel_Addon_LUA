function PvPScalpel_GetBuildInfoSnapshot()
    if not GetBuildInfo then return nil end

    local buildVersion, buildNumber, buildDate, interfaceVersion, localizedVersion, buildInfo = GetBuildInfo()
    if not buildVersion then return nil end

    return {
        version = buildVersion,
        build = buildNumber,
        date = buildDate,
        interface = interfaceVersion,
        localized = localizedVersion,
        info = buildInfo,
        versionString = tostring(buildVersion) .. "." .. tostring(buildNumber),
    }
end
