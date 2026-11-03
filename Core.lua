-- Guild Coffers: guild tax and contribution tracking for WoW: Forever.
-- Early scaffold: loads, creates saved variables, and registers /coffers.
local addonName, ns = ...

local frame = CreateFrame("Frame")
ns.frame = frame

local function GetVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (getMeta and getMeta(addonName, "Version")) or "dev"
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, loaded)
    if event == "ADDON_LOADED" and loaded == addonName then
        -- SavedVariables are only available from ADDON_LOADED onwards.
        GuildCoffersDB = GuildCoffersDB or {}
        ns.db = GuildCoffersDB
        frame:UnregisterEvent("ADDON_LOADED")
    end
end)

SLASH_GUILDCOFFERS1 = "/coffers"
SlashCmdList["GUILDCOFFERS"] = function()
    print("|cffffd100Guild Coffers|r " .. GetVersion() .. " - early development build, no features yet.")
end
