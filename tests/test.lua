-- Stubbed-API tests for Guild Coffers. Run from the repo root: python3 tests/run.py
-- These check the logic against a fake WoW API. They do not replace testing in the real client.

local real_print = print
local failures, passed = 0, 0

local function eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
    else
        failures = failures + 1
        real_print("FAIL: " .. msg .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
    end
end

local function truthy(v, msg) eq(not not v, true, msg) end

---------------------------------------------------------------------------
-- Fake client
---------------------------------------------------------------------------

local S -- per-test state

local function newState()
    return {
        now = 0, money = 0, timers = {}, printed = {}, deposits = {},
        depositWorks = true, rejectEvents = {}, secret = false, eventFrame = nil,
        sent = {}, bankLog = {},
    }
end

local function makeFrame(name)
    local f = { scripts = {}, events = {}, hooks = {} }
    setmetatable(f, { __index = function(_, k)
        return function(self) return self end   -- any other method is a no-op returning self
    end })
    function f.RegisterEvent(self, event)
        if S.rejectEvents[event] then error("unknown event " .. event) end
        self.events[event] = true
    end
    function f.SetScript(self, which, fn)
        self.scripts[which] = fn
        if which == "OnEvent" then S.eventFrame = self end
    end
    function f.HookScript(self, which, fn) self.hooks[which] = fn end
    function f.SetText(self, t) rawset(self, "_text", t) end
    function f.CreateFontString() return makeFrame() end
    function f.IsShown(self) return self._shown ~= false end
    function f.Show(self) rawset(self, "_shown", true) end
    function f.Hide(self) rawset(self, "_shown", false) end
    function f.HasFocus() return true end   -- worst case: a client that always reports focus
    function f.GetText(self) return self._text end
    if name then _G[name] = f end
    return f
end

local function installGlobals()
    _G.print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
        S.printed[#S.printed + 1] = table.concat(t, " ")
    end
    _G.CreateFrame = function(_, name, _, template)
        if S.badTemplate and template == S.badTemplate then
            error("unknown template " .. template)
        end
        return makeFrame(name)
    end
    _G.UIParent = makeFrame()
    _G.UISpecialFrames = {}
    _G.tinsert = table.insert
    _G.SlashCmdList = {}
    _G.UnitName = function() return "Test Char" end   -- Forever names can contain a space
    _G.GetRealmName = function() return "Realm" end
    _G.GetBuildInfo = function() return "1.60.1", "69913", "Oct 1 2026", 16001 end
    _G.GetTime = function() return S.now end
    _G.time = function() return 1700000000 + S.now end
    _G.date = os.date
    _G.GetMoney = function() if S.secret then return { secret = true } end return S.money end
    _G.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
    _G.Enum = { PlayerInteractionType = { Trade = 3, Banker = 8, GuildBanker = 10, AccountBanker = 68 } }
    if S.noWindowEnum then
        _G.Enum.PlayerInteractionType.Merchant = nil
    else
        _G.Enum.PlayerInteractionType.Merchant = 5
        _G.Enum.PlayerInteractionType.MailInfo = 17
    end
    _G.MerchantFrame = nil
    _G.MailFrame = nil
    _G.C_Timer = { After = function(dt, fn) S.timers[#S.timers + 1] = { at = S.now + dt, fn = fn } end }
    _G.DepositGuildBankMoney = function(amount)
        S.deposits[#S.deposits + 1] = amount
        if S.depositWorks then
            S.money = S.money - amount
            S.fire("PLAYER_MONEY")
        end
    end
    _G.GuildCoffersDB = nil
    _G.GuildCoffersWindow = nil
    _G.GetAddOnMetadata = S.addonVersion and function() return S.addonVersion end or nil
    _G.GuildCoffersHUD = nil
    _G.Settings = nil
    _G.InterfaceOptions_AddCategory = nil
    _G.InterfaceOptionsFrame_OpenToCategory = nil
    if S.settingsApi then
        _G.Settings = {
            RegisterCanvasLayoutCategory = function(p) S.registeredPanel = p; return { GetID = function() return 42 end } end,
            RegisterAddOnCategory = function(cat) S.registeredCategory = cat end,
            OpenToCategory = function(id) S.openedCategory = id end,
        }
    end
    if S.legacyApi then
        _G.InterfaceOptions_AddCategory = function(p) S.legacyAdded = p end
        _G.InterfaceOptionsFrame_OpenToCategory = function() S.legacyOpened = (S.legacyOpened or 0) + 1 end
    end
    _G.IsInGuild = function() return S.inGuild ~= false end
    _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix) S.prefix = prefix end,
        SendAddonMessage = function(prefix, msg, channel) S.sent[#S.sent + 1] = { prefix = prefix, msg = msg, channel = channel } end,
    }
    _G.QueryGuildBankLog = function(tab) S.logQuery = tab end
    _G.GetNumGuildBankMoneyTransactions = function() return #S.bankLog end
    _G.GetGuildBankMoneyTransaction = function(i) return (unpack or table.unpack)(S.bankLog[i]) end
    _G.GameTooltip = nil
    _G.GuildBankFrame = nil
    if S.guildBankFrame then
        _G.GuildBankFrame = makeFrame()
        _G.GuildBankFrame.IsShown = function() return false end
    end
end

local function advance(dt)
    S.now = S.now + dt
    local due, rest = {}, {}
    for _, t in ipairs(S.timers) do
        if t.at <= S.now then due[#due + 1] = t else rest[#rest + 1] = t end
    end
    S.timers = rest
    for _, t in ipairs(due) do t.fn() end
end

local function fresh(opts)
    S = newState()
    for k, v in pairs(opts or {}) do S[k] = v end
    S.fire = function(event, ...)
        local fr = S.eventFrame
        if fr and fr.events[event] then fr.scripts.OnEvent(fr, event, ...) end
    end
    installGlobals()
    local ns = {}
    for _, file in ipairs({ "Core.lua", "Tracker.lua", "Sync.lua", "UI.lua", "Board.lua" }) do
        assert(loadfile(file))("GuildCoffers", ns)
    end
    S.fire("ADDON_LOADED", "GuildCoffers")
    S.money = 50 * 10000
    S.fire("PLAYER_LOGIN")
    S.ns = ns
    return ns
end

local function gain(copper) S.money = S.money + copper; S.fire("PLAYER_MONEY") end
local function lose(copper) S.money = S.money - copper; S.fire("PLAYER_MONEY") end
local function printedAny(substr)
    for _, line in ipairs(S.printed) do
        if line:find(substr, 1, true) then return true end
    end
    return false
end
local GOLD = 10000

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------

do -- tracking at the default rate
    local ns = fresh()
    eq(ns.db.rate, 10, "default rate is 10")
    gain(100 * GOLD)
    eq(ns.Char().owed, 10 * GOLD, "10% of 100g owed")
    gain(5)  -- fractional copper accumulates
    truthy(ns.Char().owed > 10 * GOLD, "fractions accumulate")
end

do -- on/off and rate commands
    local ns = fresh()
    ns.HandleCommand("off")
    gain(100 * GOLD)
    eq(ns.Char().owed, 0, "nothing tracked while off")
    ns.HandleCommand("on")
    ns.HandleCommand("rate 20")
    eq(ns.db.rate, 20, "rate set to 20")
    gain(10 * GOLD)
    eq(ns.Char().owed, 2 * GOLD, "20% of 10g owed")
    ns.HandleCommand("rate 250")
    eq(ns.db.rate, 100, "rate clamped to 100")
    ns.HandleCommand("rate -5")
    eq(ns.db.rate, 0, "rate clamped to 0")
    ns.HandleCommand("rate abc")
    eq(ns.db.rate, 0, "bad rate ignored")
    truthy(printedAny("usage"), "usage shown for bad rate")
end

do -- trades are not income, including just after the window closes
    local ns = fresh()
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 3)
    gain(10 * GOLD)
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 3)
    gain(10 * GOLD)  -- money update landing just after the close
    eq(ns.Char().owed, 0, "trade gold ignored (open and grace window)")
    advance(2)
    gain(10 * GOLD)
    eq(ns.Char().owed, 1 * GOLD, "gold counts again after the grace window")
end

do -- guild bank and bank withdrawals are not income
    local ns = fresh()
    S.fire("GUILDBANKFRAME_OPENED")
    gain(5 * GOLD)
    S.fire("GUILDBANKFRAME_CLOSED")
    advance(2)
    eq(ns.Char().owed, 0, "guild bank withdrawal ignored")
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 68)  -- account bank
    gain(5 * GOLD)
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 68)
    advance(2)
    eq(ns.Char().owed, 0, "account bank withdrawal ignored")
end

do -- successful deposit, opened by both event sources
    local ns = fresh()
    gain(100 * GOLD)                                   -- owes 10g
    local before = S.money
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    S.fire("GUILDBANKFRAME_OPENED")
    advance(0.6)
    eq(#S.deposits, 1, "exactly one deposit attempt")
    eq(S.deposits[1], 10 * GOLD, "deposited the amount owed")
    eq(S.money, before - 10 * GOLD, "money left the player")
    local c = ns.Char()
    eq(c.donated, 10 * GOLD, "donated total recorded")
    eq(c.owed, 0, "owed cleared")
    eq(c.deposits, 1, "deposit count")
    truthy(c.lastDonated, "last donation time set")
    truthy(printedAny("deposited"), "player told about the deposit")
    advance(5)
    eq(printedAny("did not go through"), false, "no false failure warning")
end

do -- deposit capped by what the player holds
    local ns = fresh()
    gain(100 * GOLD)                  -- owes 10g
    lose(147 * GOLD)                  -- spent most of it (leaves 3g)
    S.fire("GUILDBANKFRAME_OPENED")
    advance(0.6)
    eq(S.deposits[1], 3 * GOLD, "deposit capped at available gold")
    eq(ns.Char().owed, 7 * GOLD, "remainder still owed")
end

do -- blocked deposit: warn, keep owing, still credit a manual deposit
    local ns = fresh({ depositWorks = false })
    gain(100 * GOLD)
    S.fire("GUILDBANKFRAME_OPENED")
    advance(0.6)
    eq(#S.deposits, 1, "deposit attempted")
    advance(3.5)
    truthy(printedAny("did not go through"), "failure warning shown")
    eq(ns.Char().donated, 0, "nothing recorded as donated")
    eq(ns.Char().owed, 10 * GOLD, "still owed")
    lose(4 * GOLD)                    -- player deposits by hand
    eq(ns.Char().donated, 4 * GOLD, "manual deposit credited")
    eq(ns.Char().owed, 6 * GOLD, "manual deposit reduces owed")
    truthy(printedAny("manual deposit"), "manual deposit message")
end

do -- nothing owed: no deposit call
    fresh()
    S.fire("GUILDBANKFRAME_OPENED")
    advance(0.6)
    eq(#S.deposits, 0, "no deposit when nothing owed")
end

do -- spending away from the guild bank does not touch the totals
    local ns = fresh()
    gain(100 * GOLD)
    lose(20 * GOLD)
    eq(ns.Char().donated, 0, "spending is not a donation")
    eq(ns.Char().owed, 10 * GOLD, "spending does not reduce owed")
end

do -- secret money values are skipped safely
    local ns = fresh()
    S.secret = true
    S.fire("PLAYER_MONEY")
    eq(ns.Char().owed, 0, "secret value ignored")
end

do -- a client that rejects events does not break loading
    local ns = fresh({ rejectEvents = { GUILDBANKFRAME_OPENED = true } })
    truthy(ns.unknownEvents and ns.unknownEvents.GUILDBANKFRAME_OPENED, "rejected event recorded")
    ns.HandleCommand("debug")
    truthy(printedAny("GUILDBANKFRAME_OPENED"), "debug report lists rejected events")
    -- the interaction-manager route still opens the bank
    gain(100 * GOLD)
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    advance(0.6)
    eq(#S.deposits, 1, "deposit works via interaction events alone")
end

do -- bank detected only through Blizzard's frame (no events fire at all)
    local ns = fresh({ guildBankFrame = true,
        rejectEvents = { GUILDBANKFRAME_OPENED = true, GUILDBANKFRAME_CLOSED = true } })
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 999)  -- unrelated window
    gain(100 * GOLD)
    local bankFrame = _G.GuildBankFrame
    truthy(bankFrame.hooks.OnShow, "guild bank frame hooked")
    bankFrame.hooks.OnShow()
    advance(0.6)
    eq(#S.deposits, 1, "deposit triggered by the frame hook")
    eq(ns.Char().donated, 10 * GOLD, "frame-hook deposit recorded")
    gain(5 * GOLD)
    eq(ns.Char().owed, 0, "bank withdrawal ignored while the frame is shown")
    bankFrame.hooks.OnHide()
    advance(2)
    gain(10 * GOLD)
    eq(ns.Char().owed, 1 * GOLD, "gold counts again after the frame hides")
end

do -- /coffers watch reports bank events for a limited time
    local ns = fresh()
    ns.HandleCommand("watch")
    truthy(printedAny("watching guild bank events"), "watch announces itself")
    S.fire("GUILDBANK_UPDATE_TABS")
    truthy(printedAny("watch: GUILDBANK_UPDATE_TABS"), "watch prints a bank event")
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    truthy(printedAny("watch: PLAYER_INTERACTION_MANAGER_FRAME_SHOW 10"), "watch prints the interaction type")
    advance(61)
    local n = #S.printed
    S.fire("GUILDBANK_UPDATE_TABS")
    eq(#S.printed, n, "watch stops after 60 seconds")
end

do -- character key keeps spaces, window builds, status and unknown commands work
    local ns = fresh()
    truthy(ns.CharKey():find("Test Char", 1, true), "character key keeps the full name")
    ns.HandleCommand("window")       -- builds and opens the standalone window
    truthy(_G.GuildCoffersWindow, "standalone window built")
    ns.HandleCommand("status")
    truthy(printedAny("Keep aside"), "status prints")
    ns.HandleCommand("nonsense")
    truthy(printedAny("commands:"), "help shown for unknown command")
end

do -- the on-screen counter shows what to keep aside
    local ns = fresh()
    truthy(ns.hud, "counter built")
    gain(100 * GOLD)
    truthy(ns.hud.line1._text:find("10g", 1, true), "counter shows 10g to keep")
    truthy(ns.hud.line2._text:find("100g collected at 10%", 1, true), "counter shows collected and rate")
    eq(ns.Char().collected, 100 * GOLD, "collected tracked")
    S.fire("GUILDBANKFRAME_OPENED"); advance(0.6)
    eq(ns.Char().collected, 0, "collected resets after a full deposit")
    truthy(ns.hud.line1._text:find("0c", 1, true), "counter shows nothing left to keep")
    eq(printedAny("interface failed"), false, "no interface errors reported")
end

do -- tiny loot: tracked, shown as "<1c" rather than "0c", and fractions build up
    local ns = fresh()
    gain(2); gain(3); gain(3)                          -- 8 copper at 10% = 0.8 copper
    truthy(ns.hud.line1._text:find("<1c", 1, true), "counter shows <1c for a fraction of a copper")
    truthy(ns.hud.line2._text:find("8c collected at 10%", 1, true), "collected shows the loot was tracked")
    S.fire("GUILDBANKFRAME_OPENED"); advance(0.6)
    eq(#S.deposits, 0, "a fraction of a copper is not deposited")
    truthy(printedAny("less than 1 copper") == false, "no message unless asked")
    ns.HandleCommand("deposit")
    truthy(printedAny("less than 1 copper owed"), "manual deposit explains the fraction")
    S.fire("GUILDBANKFRAME_CLOSED"); advance(2)        -- leave the bank, then earn more
    for _ = 1, 3 do gain(5) end                        -- another 15 copper: total owed 2.3
    S.fire("GUILDBANKFRAME_OPENED"); advance(0.6)
    eq(S.deposits[1], 2, "whole coppers are deposited once enough has built up")
end

do -- the window is filled in the first time it opens, not only on later opens
    local ns = fresh()
    gain(100 * GOLD)
    ns.HandleCommand("window")
    local p = ns.panels[#ns.panels]
    truthy(p and p.owed._text and p.owed._text:find("Keep aside now: 10g", 1, true), "status filled on first open")
    truthy(p.collected._text:find("100g", 1, true), "collected filled on first open")
end

do -- the tax rate is shown as text and changed with buttons
    local ns = fresh()
    ns.HandleCommand("window")
    local p = ns.panels[#ns.panels]
    eq(p.rateText._text, "10%", "rate shown as 10% by default")
    truthy(p.scripts.OnShow, "panel refreshes itself whenever it is shown")
    p.plus.scripts.OnClick()
    eq(ns.db.rate, 11, "+ raises the rate by 1")
    eq(p.rateText._text, "11%", "text follows the + button")
    p.plus5.scripts.OnClick()
    eq(ns.db.rate, 16, "+5 raises the rate by 5")
    p.minus5.scripts.OnClick(); p.minus.scripts.OnClick()
    eq(ns.db.rate, 10, "-5 and - lower it")
    ns.SetRate(99); p.plus5.scripts.OnClick()
    eq(ns.db.rate, 100, "rate stops at 100")
    ns.SetRate(2); p.minus5.scripts.OnClick()
    eq(ns.db.rate, 0, "rate stops at 0")
    ns.HandleCommand("rate 15")
    eq(p.rateText._text, "15%", "text follows /coffers rate")
end

do -- the panel shows which version is running
    fresh({ addonVersion = "0.1.5-test" })
    S.ns.HandleCommand("window")
    eq(S.ns.panels[#S.ns.panels].version._text, "Version 0.1.5-test", "version shown in the panel")
    fresh({ addonVersion = "@project-version@" })
    S.ns.HandleCommand("window")
    eq(S.ns.panels[#S.ns.panels].version._text, "Version dev", "unpackaged copy shows dev")
end

do -- chat summary: straight away normally, held until the vendor window closes
    local ns = fresh()
    eq(ns.db.showChat, false, "chat summary is off by default")
    gain(100 * GOLD)
    eq(printedAny("received, tax"), false, "nothing printed when off")
    ns.HandleCommand("chat")
    eq(ns.db.showChat, true, "chat command turns it on")

    gain(30)                                                   -- ordinary gain: no delay
    truthy(printedAny("+30c received, tax 3c (total to keep: 10g 3c)"), "a normal gain is reported immediately")

    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)         -- vendor window opens
    local n = #S.printed
    gain(2); advance(10); gain(2); advance(10); gain(1)        -- selling items, slowly
    eq(#S.printed, n, "nothing printed while the vendor window is open")
    eq(ns.Char().collected, 100 * GOLD + 35, "vendor gold is still counted")
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)         -- vendor window closes
    eq(#S.printed, n + 1, "one summary the moment the vendor window closes")
    truthy(printedAny("+5c received, tax <1c (total to keep: 10g 3c)"), "summary adds up the sales")
    advance(100)
    eq(#S.printed, n + 1, "no duplicate summary later")

    local k = #S.printed                                       -- a trade is not taxed or reported
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 3)
    gain(10 * GOLD)
    S.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 3)
    advance(2)
    eq(#S.printed, k, "no summary for gold that is not taxed")
end

do -- the same from the classic-style events when the interaction enum lacks them
    local ns = fresh({ noWindowEnum = true })
    ns.HandleCommand("chat")
    local n = #S.printed
    S.fire("MERCHANT_SHOW"); gain(20); gain(20)
    eq(#S.printed, n, "held while the vendor window is open (event fallback)")
    S.fire("MERCHANT_CLOSED")
    truthy(printedAny("+40c received, tax 4c"), "summary at close (event fallback)")
    n = #S.printed
    S.fire("MAIL_SHOW"); gain(5 * GOLD)
    eq(#S.printed, n, "held while the mailbox is open")
    S.fire("MAIL_CLOSED")
    truthy(printedAny("+5g received, tax 50s"), "mailbox summary at close")
end

do -- safety net if a close event never arrives
    local ns = fresh()
    ns.HandleCommand("chat")
    S.fire("MERCHANT_SHOW"); gain(10)
    local n = #S.printed
    advance(30)
    eq(#S.printed, n, "still held at 30 seconds")
    advance(35)
    truthy(printedAny("+10c received, tax 1c"), "safety net prints after a minute")
    S.fire("MERCHANT_CLOSED")
    local count = 0
    for _, line in ipairs(S.printed) do if line:find("+10c received", 1, true) then count = count + 1 end end
    eq(count, 1, "safety-net summary is not repeated at close")
end

do -- a missed close event is corrected by Blizzard's own frame
    local ns = fresh()
    ns.HandleCommand("chat")
    S.fire("MERCHANT_SHOW")
    _G.MerchantFrame = { IsShown = function() return false end }
    local n = #S.printed
    gain(20)
    eq(#S.printed, n + 1, "reported straight away when the vendor frame is really closed")
    truthy(printedAny("+20c received, tax 2c"), "text is right")
end

do -- turning chat off while a vendor summary is pending drops it
    local ns = fresh()
    ns.HandleCommand("chat")
    S.fire("MERCHANT_SHOW"); gain(30)
    ns.HandleCommand("chat")
    local n = #S.printed
    S.fire("MERCHANT_CLOSED")
    eq(#S.printed, n, "nothing printed once chat is off")
end

do -- a partial deposit keeps the collected figure
    local ns = fresh()
    gain(100 * GOLD)
    lose(147 * GOLD)                  -- leaves 3g
    S.fire("GUILDBANKFRAME_OPENED"); advance(0.6)
    eq(ns.Char().collected, 100 * GOLD, "collected kept after a partial deposit")
end

do -- counter follows on/off and the /coffers hud toggle
    local ns = fresh()
    eq(ns.db.enabled, true, "tracking is on by default")
    eq(ns.db.rate, 10, "rate is 10 by default")
    eq(ns.db.showHud, true, "counter is shown by default")
    ns.HandleCommand("off")
    truthy(ns.hud.line1._text:find("tracking off", 1, true), "counter says tracking is off")
    ns.HandleCommand("on")
    ns.HandleCommand("hud")
    eq(ns.db.showHud, false, "hud command hides the counter")
    eq(ns.hud._shown, false, "counter hidden")
    ns.HandleCommand("hud")
    eq(ns.hud._shown, true, "counter shown again")
end

do -- settings panel: modern Settings API
    local ns = fresh({ settingsApi = true })
    truthy(S.registeredPanel, "panel registered with the Settings API")
    truthy(S.registeredCategory, "category added to the AddOns settings")
    eq(ns.menuMode, "settings", "menu mode recorded")
    ns.HandleCommand("")
    eq(S.openedCategory, 42, "/coffers opens the settings category")
    eq(_G.GuildCoffersWindow, nil, "no stray window when the settings menu works")
    ns.HandleCommand("debug")
    truthy(printedAny("Menu entry: settings"), "debug reports the menu mode")
end

do -- settings panel: old interface options API
    local ns = fresh({ legacyApi = true })
    eq(S.legacyAdded and S.legacyAdded.name, "Guild Coffers", "panel added to the old options")
    ns.HandleCommand("")
    eq(S.legacyOpened, 2, "old options opened (called twice, as that client needs)")
end

do -- no settings menu found: falls back to a standalone window
    local ns = fresh()
    eq(ns.menuMode, nil, "no menu entry")
    ns.HandleCommand("")
    truthy(_G.GuildCoffersWindow, "standalone window used as the fallback")
end

do -- one failing piece is reported and does not stop the rest
    local ns = fresh({ badTemplate = "UICheckButtonTemplate" })
    truthy(printedAny("interface failed"), "the failing part is reported")
    ns.HandleCommand("")                      -- must not throw
    gain(100 * GOLD)
    truthy(ns.hud.line1._text:find("10g", 1, true), "counter still works when the panel fails")
    ns.HandleCommand("rate 15")
    eq(ns.db.rate, 15, "text commands still work")
end

do -- coin text
    local ns = fresh()
    eq(ns.CoinText(0), "0c", "zero coins")
    eq(ns.CoinText(123456), "12g 34s 56c", "mixed coins")
    eq(ns.CoinText(10 * GOLD), "10g", "round gold")
end

do -- parsing amounts
    local ns = fresh()
    eq(ns.ParseMoney("100g"), 100 * GOLD, "100g")
    eq(ns.ParseMoney("5g 50s"), 5 * GOLD + 5000, "5g 50s")
    eq(ns.ParseMoney("1G20S3C"), GOLD + 2000 + 3, "mixed case, no spaces")
    eq(ns.ParseMoney("50s"), 5000, "silver only")
    eq(ns.ParseMoney("7c"), 7, "copper only")
    eq(ns.ParseMoney("100"), 100 * GOLD, "a bare number is gold")
    eq(ns.ParseMoney("1.5g"), 15000, "decimal gold")
    eq(ns.ParseMoney("0"), 0, "zero")
    eq(ns.ParseMoney("off"), 0, "off means none")
    eq(ns.ParseMoney("abc"), nil, "words rejected")
    eq(ns.ParseMoney(""), nil, "empty rejected")
    eq(ns.ParseMoney("5 50s"), nil, "bare number mixed with units rejected")
    eq(ns.ParseMoney("-5g"), nil, "negative rejected")
end

do -- reserve: a deposit never takes you below the minimum
    local ns = fresh()                       -- starts with 50g
    ns.HandleCommand("reserve 100g")
    eq(ns.db.reserve, 100 * GOLD, "reserve set from the command")
    ns.Char().owed = 10 * GOLD
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    eq(#S.deposits, 0, "nothing deposited while below the reserve")
    truthy(printedAny("keeping your 100g reserve"), "player told why nothing was deposited")
    eq(ns.Char().owed, 10 * GOLD, "owed gold stays owed")
    S.fire("GUILDBANKFRAME_CLOSED")
end

do -- reserve: partial deposit down to the minimum, the rest stays owed
    local ns = fresh()                       -- 50g
    ns.db.enabled = false; S.money = 105 * GOLD; S.fire("PLAYER_MONEY"); ns.db.enabled = true
    ns.HandleCommand("reserve 100g")
    ns.Char().owed = 10 * GOLD
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    eq(S.deposits[1], 5 * GOLD, "only the 5g above the reserve is deposited")
    eq(S.money, 100 * GOLD, "player keeps exactly the reserve")
    eq(math.floor(ns.Char().owed), 5 * GOLD, "the remainder is still owed")
    S.fire("GUILDBANKFRAME_CLOSED")
end

do -- reserve: no effect when set to none, and a manual deposit respects it too
    local ns = fresh()
    ns.Char().owed = 10 * GOLD
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    eq(S.deposits[1], 10 * GOLD, "no reserve: full amount deposited")
    S.fire("GUILDBANKFRAME_CLOSED")
    local ns2 = fresh()
    ns2.HandleCommand("reserve 60g")
    ns2.Char().owed = 10 * GOLD
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    ns2.TryDeposit(true)
    eq(#S.deposits, 0, "manual deposit also respects the reserve")
    ns2.HandleCommand("reserve bad")
    eq(ns2.db.reserve, 60 * GOLD, "bad reserve ignored")
    ns2.HandleCommand("reserve 0")
    eq(ns2.db.reserve, 0, "reserve 0 clears it")
end

do -- reset button and command
    local ns = fresh()
    gain(100 * GOLD)
    ns.HandleCommand("window")
    local p = ns.panels[#ns.panels]
    ns.Char().donated = 3 * GOLD
    p.reset.scripts.OnClick()
    truthy(ns.Char().owed > 0, "first click only asks for confirmation")
    truthy((p.reset._text or ""):find("again", 1, true), "button asks for a second click")
    advance(6)
    eq(p.reset._text, "Reset amount owed", "confirmation times out")
    p.reset.scripts.OnClick(); p.reset.scripts.OnClick()
    eq(ns.Char().owed, 0, "second click resets what is owed")
    eq(ns.Char().collected, 0, "collected count reset too")
    eq(ns.Char().donated, 3 * GOLD, "lifetime donated is kept")
    gain(10 * GOLD)
    ns.HandleCommand("reset")
    eq(ns.Char().owed, 0, "/coffers reset works")
end

do -- reserve shown in the panel and set with the buttons' underlying call
    local ns = fresh()
    ns.HandleCommand("window")
    local p = ns.panels[#ns.panels]
    eq(p.reserveText._text, "none", "reserve shows none by default")
    ns.HandleCommand("reserve 5g 50s")
    eq(p.reserveText._text, "5g 50s", "panel follows /coffers reserve")
    ns.SetReserve(-5)
    eq(ns.db.reserve, 0, "reserve cannot go negative")
end

local function receive(sender, text, prefix, channel)
    S.fire("CHAT_MSG_ADDON", prefix or "GuildCoffers", text, channel or "GUILD", sender)
end
local function rowFor(ns, name)
    for _, r in ipairs(ns.BoardRows()) do if r.name == name then return r end end
end

do -- announcing ourselves after login
    local ns = fresh()
    eq(S.prefix, "GuildCoffers", "addon message prefix registered")
    eq(#S.sent, 0, "nothing sent straight at login")
    advance(16)
    eq(#S.sent, 2, "state and hello sent after the login delay")
    eq(S.sent[1].msg, "1|10|0|0|0", "state message carries rate and totals")
    eq(S.sent[1].channel, "GUILD", "sent to the guild channel")
    eq(S.sent[2].msg, "H|1", "hello asks who else uses the addon")
end

do -- sharing can be switched off, and nothing is sent outside a guild
    local ns = fresh()
    ns.HandleCommand("share")
    eq(ns.db.share, false, "share toggled off")
    advance(16)
    eq(#S.sent, 0, "nothing sent while sharing is off")
    local ns2 = fresh({ inGuild = false })
    advance(16)
    eq(#S.sent, 0, "nothing sent when not in a guild")
end

do -- receiving guildmates' totals
    local ns = fresh()
    receive("Bob-Realm", "1|15|500000|3|1700000000")
    local bob = rowFor(ns, "Bob")
    truthy(bob, "guildmate appears on the board")
    eq(bob.rate, 15, "their rate is stored")
    eq(bob.donated, 500000, "their total is stored")
    eq(ns.BoardRows()[1].name, "Bob", "biggest donor listed first")
    truthy(rowFor(ns, "Test Char") and rowFor(ns, "Test Char").me, "you are on the board too")
    receive("Bob-Realm", "1|20|600000|4|1700000500")
    eq(rowFor(ns, "Bob").donated, 600000, "a newer message replaces the old one")
end

do -- bad or unwanted messages are ignored
    local ns = fresh()
    receive("Eve-Realm", "1|15|500000|3|1700000000", "OtherAddon")
    receive("Eve-Realm", "1|15|500000|3|1700000000", "GuildCoffers", "WHISPER")
    receive("Eve-Realm", "garbage")
    receive("Eve-Realm", "1|abc|5|3|0")
    receive("Eve-Realm", "1|15|500000")
    receive("Test Char-Realm", "1|15|500000|3|1700000000")   -- our own echo
    eq(rowFor(ns, "Eve"), nil, "nothing stored from bad messages")
    eq(rowFor(ns, "Test Char").donated, 0, "own echo ignored")
    receive("Mal-Realm", "1|999|99999999999999|3|0")
    eq(rowFor(ns, "Mal").rate, 100, "rate clamped to 100")
    S.fire("CHAT_MSG_ADDON", "GuildCoffers", "1|15|5|3|0", "GUILD", { secret = true })
    eq(rowFor(ns, "Sec"), nil, "no crash on secret values")
end

do -- someone asks who uses the addon: we answer after a pause, and not in a flood
    local ns = fresh()
    advance(16); advance(20); S.sent = {}
    receive("New-Realm", "H|1")
    eq(#S.sent, 0, "reply is delayed")
    advance(11)
    eq(#S.sent, 1, "we answer the hello")
    eq(S.sent[1].msg:sub(1, 2), "1|", "the answer is our state")
end

do -- a deposit is shared shortly after, in one batch
    local ns = fresh()
    advance(16); S.sent = {}
    ns.Char().owed = 10 * GOLD
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    eq(S.logQuery, 9, "the money log is requested when the bank opens")
    advance(40)
    eq(#S.sent, 1, "one state message after the deposit")
    eq(S.sent[1].msg:find("^1|10|" .. (10 * GOLD) .. "|1|"), 1, "it carries the new total")
    S.fire("GUILDBANKFRAME_CLOSED")
end

do -- verification against the guild bank log
    local ns = fresh()
    receive("Bob-Realm", "1|15|500000|3|1700000000")
    receive("Dan-Realm", "1|10|900000|2|1700000000")
    S.bankLog = {
        { "deposit", "Bob", 20000, 0, 0, 1, 2 },
        { "deposit", "Bob", 10000, 0, 0, 2, 0 },
        { "withdraw", "Bob", 99999, 0, 0, 0, 1 },
        { "deposit", "Cara", 30000, 0, 0, 3, 0 },
    }
    S.fire("GUILDBANKLOG_UPDATE")
    local bob, dan, cara = rowFor(ns, "Bob"), rowFor(ns, "Dan"), rowFor(ns, "Cara")
    eq(bob.verified, true, "Bob's deposits appear in the log")
    eq(bob.bankTotal, 30000, "only deposits are totalled")
    eq(dan.verified, nil, "Dan claims donations but the log shows none: unverified")
    truthy(cara and cara.verified and not cara.usesAddon, "log-only donor listed without the addon")
    truthy(bob.bankLast > 0 and bob.bankLast < time(), "log age turned into a date")
end

do -- the leaderboard window
    local ns = fresh()
    receive("Bob-Realm", "1|15|500000|3|1700000000")
    S.bankLog = { { "deposit", "Bob", 20000, 0, 0, 1, 2 } }
    S.fire("GUILDBANKLOG_UPDATE")
    ns.HandleCommand("board")
    local b = _G.GuildCoffersBoard
    truthy(b, "board window built")
    eq(b.lines[1][2]._text, "Bob", "top row is the biggest donor")
    truthy(b.lines[1][6]._text:find("Verified", 1, true), "verified shown")
    eq(b.lines[2][2]._text, "Test Char (you)", "your own row is marked")
    eq(b.lines[3][2]._text, "", "unused rows are blank")
    ns.HandleCommand("board")
    eq(b:IsShown(), false, "board toggles closed")
end

do -- the custom-amount tooltip and the new panel controls
    local ns = fresh()
    ns.HandleCommand("window")
    local p = ns.panels[#ns.panels]
    local lines = {}
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
        AddLine = function(_, text) lines[#lines + 1] = text end }
    p.reserveHit.scripts.OnEnter(p.reserveHit)
    local joined = table.concat(lines, "\n")
    truthy(joined:find("/coffers reserve", 1, true), "tooltip tells players how to type an exact amount")
    truthy(joined:find("silver", 1, true), "tooltip explains g, s and c")
    truthy(p.boardBtn and p.share, "leaderboard button and share box exist")
    ns.db.share = false
    ns.RefreshUI()
    p.share.scripts.OnClick(p.share)
    _G.GameTooltip = nil
end

real_print(string.format("%d checks passed, %d failed", passed, failures))
if failures > 0 then error("tests failed") end
