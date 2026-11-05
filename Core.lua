-- Guild Coffers: guild tax and contribution tracking for WoW: Forever.
-- Core: namespace, saved variables, event dispatch, helpers and slash commands.
local addonName, ns = ...

ns.name = addonName
ns.handlers = {}
ns.frame = CreateFrame("Frame")
-- Forever inherits retail's "secret value" restrictions; guard where it exists.
ns.isSecret = issecretvalue or function() return false end

local DEFAULTS = { rate = 10, enabled = true, showHud = true, hudLocked = false, showChat = false }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns.Print(msg)
    print("|cffffd100Guild Coffers|r: " .. tostring(msg))
end

function ns.GetVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (getMeta and getMeta(addonName, "Version")) or "dev"
end

-- Plain-text money, e.g. "12g 34s 5c". No dependency on client money APIs.
function ns.CoinText(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper < 0 then copper = 0 end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Amounts owed can be a fraction of a copper; show that as "<1c" rather than "0c".
function ns.OwedText(copper)
    copper = tonumber(copper) or 0
    if copper > 0 and copper < 1 then return "<1c" end
    return ns.CoinText(copper)
end

-- Register an event. Unknown events on this client are recorded, not fatal.
function ns.On(event, fn)
    local list = ns.handlers[event]
    if not list then
        list = {}
        ns.handlers[event] = list
        local ok = pcall(ns.frame.RegisterEvent, ns.frame, event)
        if not ok then
            ns.unknownEvents = ns.unknownEvents or {}
            ns.unknownEvents[event] = true
        end
    end
    list[#list + 1] = fn
end

ns.frame:SetScript("OnEvent", function(_, event, ...)
    local list = ns.handlers[event]
    if list then
        for i = 1, #list do
            list[i](event, ...)
        end
    end
end)

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(_, loaded)
    if loaded ~= addonName then return end
    -- SavedVariables are only available from ADDON_LOADED onwards.
    GuildCoffersDB = GuildCoffersDB or {}
    local db = GuildCoffersDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.chars = db.chars or {}
    ns.db = db
end)

-- Character key: Forever names can be "first last", so keep the whole name.
function ns.CharKey()
    local name = UnitName("player") or "?"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName and GetRealmName()) or ""
    return name .. "-" .. realm
end

-- Per-character tax record. owed is in copper and may hold a fraction.
function ns.Char()
    local key = ns.CharKey()
    local c = ns.db.chars[key]
    if not c then
        c = { owed = 0, collected = 0, donated = 0, deposits = 0 }
        ns.db.chars[key] = c
    end
    return c
end

function ns.SetRate(value)
    local n = tonumber(value)
    if not n then return false end
    n = math.floor(n)
    if n < 0 then n = 0 end
    if n > 100 then n = 100 end
    ns.db.rate = n
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function PrintStatus()
    local c = ns.Char()
    ns.Print(string.format("tax %d%% (%s). Collected since last deposit: %s. Keep aside: %s. Total donated: %s.",
        ns.db.rate, ns.db.enabled and "on" or "off",
        ns.CoinText(c.collected or 0), ns.OwedText(c.owed), ns.CoinText(c.donated)))
    if c.lastDonated and date then
        ns.Print("Last donation: " .. date("%Y-%m-%d %H:%M", c.lastDonated))
    end
end

local function PrintHelp()
    ns.Print("commands:")
    print("  /coffers - open the settings (AddOns menu)")
    print("  /coffers hud - show or hide the on-screen tax counter")
    print("  /coffers chat - add or remove a chat line showing the tax on each gain")
    print("  /coffers window - open the settings in a standalone window")
    print("  /coffers rate <0-100> - set your tax percentage")
    print("  /coffers on | off - turn tracking on or off")
    print("  /coffers status - show what you owe and have donated")
    print("  /coffers deposit - deposit now (guild bank must be open)")
    print("  /coffers debug - print a compatibility report")
    print("  /coffers watch - log guild bank events for 60s (for bug reports)")
end

local function PrintDebug()
    local PI = Enum and Enum.PlayerInteractionType
    local build = (GetBuildInfo and select(4, GetBuildInfo())) or "?"
    ns.Print("Guild Coffers " .. ns.GetVersion() .. ", interface " .. tostring(build))
    local function yn(v) return v and "yes" or "NO" end
    print("  DepositGuildBankMoney: " .. yn(DepositGuildBankMoney))
    print("  C_Timer.After: " .. yn(C_Timer and C_Timer.After))
    print("  issecretvalue: " .. yn(issecretvalue))
    print("  Enum.PlayerInteractionType: " .. yn(PI))
    if PI then
        print("    GuildBanker: " .. yn(PI.GuildBanker) .. ", Banker: " .. yn(PI.Banker)
            .. ", AccountBanker: " .. yn(PI.AccountBanker) .. ", Trade: " .. yn(PI.Trade))
    end
    print("  Settings.RegisterCanvasLayoutCategory: " .. yn(Settings and Settings.RegisterCanvasLayoutCategory))
    print("  InterfaceOptions_AddCategory: " .. yn(InterfaceOptions_AddCategory))
    print("  Menu entry: " .. (ns.menuMode or "none (standalone window is used)"))
    local unknown = {}
    for event in pairs(ns.unknownEvents or {}) do unknown[#unknown + 1] = event end
    table.sort(unknown)
    print("  Events this client rejected: " .. (#unknown > 0 and table.concat(unknown, ", ") or "none"))
end

function ns.HandleCommand(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "debug" then
        PrintDebug()
        return
    end
    if not ns.db then
        ns.Print("still loading, try again in a moment.")
        return
    end
    if cmd == "" or cmd == "show" or cmd == "config" then
        if ns.ToggleUI then ns.ToggleUI() else PrintStatus() end
    elseif cmd == "rate" then
        if ns.SetRate(rest) then
            ns.Print("tax rate set to " .. ns.db.rate .. "%.")
        else
            ns.Print("usage: /coffers rate <0-100>")
        end
    elseif cmd == "on" or cmd == "off" then
        ns.db.enabled = (cmd == "on")
        ns.Print("tracking turned " .. cmd .. ".")
        if ns.RefreshUI then ns.RefreshUI() end
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "deposit" then
        ns.TryDeposit(true)
    elseif cmd == "watch" then
        ns.StartWatch()
    elseif cmd == "hud" then
        ns.db.showHud = not ns.db.showHud
        ns.Print("tax counter " .. (ns.db.showHud and "shown." or "hidden."))
        if ns.RefreshUI then ns.RefreshUI() end
    elseif cmd == "chat" then
        ns.db.showChat = not ns.db.showChat
        ns.Print("chat line " .. (ns.db.showChat and "on." or "off."))
        if ns.RefreshUI then ns.RefreshUI() end
    elseif cmd == "window" then
        if ns.ShowWindow then ns.ShowWindow() end
    else
        PrintHelp()
    end
end

SLASH_GUILDCOFFERS1 = "/coffers"
SLASH_GUILDCOFFERS2 = "/guildcoffers"
SlashCmdList["GUILDCOFFERS"] = function(input) ns.HandleCommand(input) end
