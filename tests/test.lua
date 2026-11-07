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
        -- Any other METHOD (CamelCase) is a no-op returning self; plain fields stay nil, as in the client.
        if type(k) == "string" and k:match("^%u") then
            return function(self) return self end
        end
    end })
    function f.RegisterEvent(self, event)
        if S.rejectEvents[event] then error("unknown event " .. event) end
        self.events[event] = true
    end
    function f.SetScript(self, which, fn)
        self.scripts[which] = fn
        if which == "OnEvent" then S.eventFrame = self end
    end
    function f.SetChecked(self, v) rawset(self, "_checked", v and true or false) end
    function f.GetChecked(self) return self._checked end
    function f.Disable(self) rawset(self, "_disabled", true) end
    function f.Enable(self) rawset(self, "_disabled", false) end
    function f.SetupMenu(self, gen) rawset(self, "_gen", gen) end
    function f.SetShown(self, v) rawset(self, "_shown", v and true or false) end
    function f.SetFrameStrata(self, strata) rawset(self, "_strata", strata) end
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
    _G.UnitName = function() return S.unitName or "Test Char" end   -- Forever names can contain a space
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
    _G.Enum.BankType = { Character = 0, Guild = 1, Account = 2 }
    _G.C_Bank = S.noOwnBank and { CanUseBank = function() return true end } or {
        CanUseBank = function() return not S.noAccountBank end,
        DepositMoney = function(bankType, amount)
        S.ownDeposits = S.ownDeposits or {}
        S.ownDeposits[#S.ownDeposits + 1] = { bankType = bankType, amount = amount }
        if S.ownDepositWorks ~= false then S.money = S.money - amount; S.fire("PLAYER_MONEY") end
    end }
    _G.hooksecurefunc = function(name, fn)
        local orig = _G[name]
        _G[name] = function(...) orig(...); fn(...) end
    end
    _G.AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
    _G.GetInboxNumItems = function() return S.inbox and #S.inbox or 0 end
    _G.GetInboxHeaderInfo = function(i)
        local m = S.inbox[i]
        return nil, nil, m[1], m[2], m[3], 0, 30, false, true, false, true, true, false
    end
    _G.GetInboxInvoiceInfo = S.noInvoice and nil or function(i)
        local m = S.inbox[i]
        return m[4]
    end
    _G.GetGuildInfoText = function() return S.guildInfo or "" end
    _G.UnitGUID = function() return S.myGuid or "Player-1-0001" end
    _G.GetNumGuildMembers = function() return S.roster and #S.roster or 0 end
    _G.GetGuildRosterInfo = function(i)
        local m = S.roster[i]
        return m[1], m[3] or "Member", m[4] or 1, 10, "Paladin", "Elwynn", "", "", true, 0, "PALADIN", 0, 0, false, false, 4, m[2]
    end
    _G.C_GuildInfo = { GuildRoster = function() S.rosterRequested = true end }
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
    for _, file in ipairs({ "Core.lua", "Tracker.lua", "Sync.lua", "History.lua", "UI.lua", "Board.lua" }) do
        assert(loadfile(file))("GuildCoffers", ns)
    end
    S.fire("ADDON_LOADED", "GuildCoffers")
    if not S.keepMin then ns.db.minDeposit = 0 end   -- most tests deposit small amounts
    S.money = 50 * 10000
    S.fire("PLAYER_LOGIN")
    S.ns = ns
    return ns
end

-- gain(): gold looted from a loot window (taxable). plain(): gold with no source (e.g. a quest).
local function gain(copper)
    S.fire("LOOT_OPENED"); S.money = S.money + copper; S.fire("PLAYER_MONEY"); S.fire("LOOT_CLOSED")
end
local function plain(copper) S.money = S.money + copper; S.fire("PLAYER_MONEY") end
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
    S.inbox = { { "Auction House", "Auction successful: Copper Ore", 5 * GOLD, "seller" } }
    S.fire("MAIL_SHOW"); plain(5 * GOLD)
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
    truthy(printedAny("keeping your 100g spending money"), "player told why nothing was deposited")
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
    eq(S.sent[1].msg, "1|10|0|0|0|", "state message carries rate and totals (full name unknown: blank)")
    eq(S.sent[1].channel, "GUILD", "sent to the guild channel")
    eq(S.sent[2].msg, "H|1", "hello asks who else uses the addon")
end

do -- no separate share setting; nothing sent outside a guild
    local ns = fresh()
    advance(16)
    eq(ns.db.share, nil, "there is no separate share setting")
    eq(printedAny("leaderboard"), false, "no notice printed at login")
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
    advance(16); advance(610); S.sent = {}   -- hellos are answered only if we have not shared for 10 minutes
    receive("New-Realm", "H|1")
    eq(#S.sent, 0, "reply is delayed")
    advance(11)
    eq(#S.sent, 1, "we answer the hello")
    eq(S.sent[1].msg:sub(1, 2), "1|", "the answer is our state")
end

do -- a deposit is shared shortly after, in one batch
    local ns = fresh()
    advance(16); advance(6); S.sent = {}   -- past the login announcements and catch-up request
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
    eq(bob.paidIn, 30000, "deposits are paid in")
    eq(bob.takenOut, 99999, "withdrawals are taken out")
    eq(dan.verified, nil, "Dan claims donations but the log shows none: unverified")
    truthy(cara and cara.verified and not cara.usesAddon, "log-only donor listed without the addon")
    truthy(bob.lastPaid > 0 and bob.lastPaid < time(), "log age turned into a date")
end

do -- the leaderboard window
    local ns = fresh()
    receive("Bob-Realm", "1|15|500000|3|1700000000")
    S.bankLog = { { "deposit", "Bob", 20000, 0, 0, 1, 2 } }
    S.fire("GUILDBANKLOG_UPDATE")
    ns.HandleCommand("board")
    local b = _G.GuildCoffersBoard
    truthy(b, "board window built")
    eq(b._strata, "FULLSCREEN_DIALOG", "board sits above the Options window")
    eq(b.lines[1][2]._text, "Bob", "top row is the biggest donor")
    truthy(b.lines[1][5]._text:find("2g", 1, true), "verified paid in shown")
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
    truthy(joined:find("/coffers spending", 1, true), "tooltip tells players how to type an exact amount")
    truthy(joined:find("silver", 1, true), "tooltip explains g, s and c")
    truthy(p.boardBtn, "leaderboard button exists")
    eq(p.share, nil, "no separate share box: sharing follows the guild-bank choice")
    _G.GameTooltip = nil
end

do -- /coffers log
    local ns = fresh()
    ns.HandleCommand("log")
    truthy(printedAny("open the guild bank first"), "log probe needs the bank open")
    S.bankLog = { { "deposit", "Bob", 20000, 0, 0, 1, 2 }, { "withdraw", "Bob", 5000, 0, 0, 3, 0 }, { "repair", "Cara", 900, 0, 0, 4, 1 } }
    S.fire("GUILDBANKFRAME_OPENED")
    ns.HandleCommand("log"); advance(3)
    truthy(printedAny("3 entries"), "log probe reports the entry count")
    truthy(printedAny("deposit 1"), "log probe reports entry types")
    truthy(printedAny("2 different players"), "log probe counts players")
    S.fire("GUILDBANKFRAME_CLOSED")
end

local function menuItems(dd)
    local items = {}
    local root = { CreateRadio = function(_, text, isSel, setSel)
        items[#items + 1] = { text = text, isSel = isSel, setSel = setSel }
        return {}
    end }
    dd._gen(dd, root)
    return items
end

do -- defaults: guild bank and 10%, and /coffers defaults puts them back
    local ns = fresh()
    eq(ns.db.dest, "guild", "guild bank is the default destination")
    eq(ns.db.rate, 10, "10% is the default rate")
    eq(ns.db.enabled, true, "tracking on by default")
    ns.HandleCommand("dest bank")
    ns.HandleCommand("rate 25")
    ns.HandleCommand("reserve 50g")
    ns.Char().donated = 7 * GOLD
    ns.HandleCommand("defaults")
    eq(ns.db.dest, "guild", "defaults: back to the guild bank")
    eq(ns.db.rate, 10, "defaults: back to 10%")
    eq(ns.db.reserve, 0, "defaults: no reserve")
    eq(ns.Char().donated, 7 * GOLD, "defaults keep your tax records")
end

do -- one person, not two: the bank log has the full name, the game gave only the first name
    local ns = fresh({ unitName = "Leeroy" })
    ns.Char().donated = 202
    S.bankLog = { { "deposit", "Leeroy Mcbiff", 202, 0, 0, 0, 0 } }
    S.fire("GUILDBANKLOG_UPDATE")
    local rows = ns.BoardRows()
    eq(#rows, 1, "one row for one player")
    eq(rows[1].name, "Leeroy Mcbiff", "the fuller name is shown")
    eq(rows[1].me, true, "it is marked as you")
    eq(rows[1].verified, true, "and verified by the bank log")
    receive("Leeroy Mcbiff-Realm", "1|10|202|1|1700000000")
    eq(#ns.BoardRows(), 1, "your own echo does not add a second row")
end

do -- names that only share a first name stay separate when both are full names
    local ns = fresh({ unitName = "Leeroy Mcbiff" })
    S.bankLog = { { "deposit", "Leeroy Jenkins", 500, 0, 0, 0, 0 } }
    S.fire("GUILDBANKLOG_UPDATE")
    eq(#ns.BoardRows(), 2, "two different players")
    eq(ns.SameName("Leeroy", "Leeroy Mcbiff-Realm"), true, "first name matches full name")
    eq(ns.SameName("Leeroy Jenkins", "Leeroy Mcbiff"), false, "different surnames do not match")
    eq(ns.SameName("Lee", "Leeroy"), false, "partial words do not match")
end

do -- full names come from the guild roster, found by GUID, so it works for every player
    local ns = fresh({ unitName = "Leeroy", roster = {
        { "Leeroy Mcbiff-Realm", "Player-1-0001" },     -- you
        { "Leeroy Jenkins-Realm", "Player-1-0002" },    -- someone else with your first name
        { "Bob Smith-Realm", "Player-1-0003" },
    } })
    advance(4)
    eq(S.rosterRequested, true, "roster requested after login")
    eq(ns.Char().fullName, "Leeroy Mcbiff", "your full name found by GUID, not by name")
    ns.Char().donated = 202
    S.bankLog = {
        { "deposit", "Leeroy Mcbiff", 202, 0, 0, 0, 0 },
        { "deposit", "Leeroy Jenkins", 500, 0, 0, 0, 0 },
    }
    S.fire("GUILDBANKLOG_UPDATE")
    local me, other = rowFor(ns, "Leeroy Mcbiff"), rowFor(ns, "Leeroy Jenkins")
    truthy(me and me.me and me.verified, "you: one row, full name, verified")
    truthy(other and not other.me, "a guildmate with the same first name stays separate")
    eq(#ns.BoardRows(), 3, "two Leeroys stay two rows (plus Bob from the roster)")
    advance(16)
    truthy(S.sent[1].msg:find("|Leeroy Mcbiff$"), "your full name is sent with your totals")

    receive("Bob-Realm", "1|10|300|1|1700000000|")
    truthy(rowFor(ns, "Bob Smith"), "a first-name-only sender is named from the roster")
    receive("Bob-Realm", "1|10|300|1|1700000000|Leeroy Mcbiff")
    eq(rowFor(ns, "Leeroy Mcbiff").donated, 202, "nobody can claim someone else's full name")
    receive("Leeroy Mcbiff-Realm", "1|10|202|1|1700000000|Leeroy Mcbiff")
    eq(#ns.BoardRows(), 3, "your own message coming back adds no row")
end

do -- with no roster (no guild), first-name matching is the fallback
    local ns = fresh({ unitName = "Leeroy" })
    receive("Cara-Realm", "1|10|300|1|1700000000|Cara Jones")
    truthy(rowFor(ns, "Cara"), "without a roster, a claimed full name is not trusted")
    S.bankLog = { { "deposit", "Cara Jones", 300, 0, 0, 0, 0 } }
    S.fire("GUILDBANKLOG_UPDATE")
    eq(#ns.BoardRows(), 2, "her bank-log entry joins her row (you + Cara)")
    eq(rowFor(ns, "Cara Jones").verified, true, "and verifies it")
end

do -- debug shows the name lookups
    local ns = fresh()
    ns.HandleCommand("debug")
    truthy(printedAny("Names: UnitName = Test Char"), "debug lists the player's name lookups")
end

---------------------------------------------------------------------------
-- Donation history, roster view and promotions
---------------------------------------------------------------------------

local function ledgerMsgs(prefix)
    local out = {}
    for _, m in ipairs(S.sent) do if m.msg:sub(1, #prefix) == prefix then out[#out + 1] = m.msg end end
    return out
end

do -- the same bank log read twice is not counted twice; new entries are added
    local ns = fresh()
    S.bankLog = { { "deposit", "Bob Smith", 20000, 0, 0, 0, 5 }, { "withdraw", "Bob Smith", 5000, 0, 0, 0, 3 } }
    S.fire("GUILDBANKLOG_UPDATE")
    S.fire("GUILDBANKLOG_UPDATE")
    eq(#ns.Ledger().list, 2, "re-reading the same log adds nothing")
    advance(1800)   -- half an hour later the ages read one hour on, give or take
    S.bankLog = { { "deposit", "Bob Smith", 20000, 0, 0, 0, 6 }, { "withdraw", "Bob Smith", 5000, 0, 0, 0, 4 },
        { "deposit", "Bob Smith", 20000, 0, 0, 0, 0 } }
    S.fire("GUILDBANKLOG_UPDATE")
    eq(#ns.Ledger().list, 3, "an hour's drift still matches; the new deposit is added")
    local t = ns.LedgerTotals()["bob smith"]
    eq(t.paidIn, 40000, "two deposits paid in")
    eq(t.takenOut, 5000, "one withdrawal taken out")
    eq(ns.Ledger().gapAt, nil, "no gap: the logs overlap")
end

do -- what one guildmate reports is not verified; two guildmates, or seeing it yourself, is
    local ns = fresh()
    local h = ns.Hour() - 2
    local msg = "L|d,50000," .. h .. ",Cara Jones"
    receive("Eve-Realm", msg)
    eq(ns.LedgerTotals()["cara jones"], nil, "one report alone is not verified")
    receive("Eve-Realm", msg)
    eq(ns.LedgerTotals()["cara jones"], nil, "the same person reporting twice is still one")
    receive("Dan-Realm", msg)
    eq(ns.LedgerTotals()["cara jones"].paidIn, 50000, "a second guildmate verifies it")
    eq(#ns.Ledger().list, 1, "and it is one entry, not three")
    receive("Eve-Realm", "L|d,90000," .. (h + 1) .. ",Fay Lee")
    S.bankLog = { { "deposit", "Fay Lee", 90000, 0, 0, 0, 1 } }
    S.fire("GUILDBANKLOG_UPDATE")
    eq(ns.LedgerTotals()["fay lee"].paidIn, 90000, "seeing it in the log yourself verifies it")
end

do -- bad history messages are ignored
    local ns = fresh()
    local h = ns.Hour()
    receive("Eve-Realm", "L|x,5," .. h .. ",Bob")
    receive("Eve-Realm", "L|d,abc," .. h .. ",Bob")
    receive("Eve-Realm", "L|d,5," .. (h + 50) .. ",Bob")        -- in the future
    receive("Eve-Realm", "L|d,0," .. h .. ",Bob")               -- nothing
    receive("Eve-Realm", "L|d,5," .. h .. "," .. string.rep("x", 80))
    eq(#ns.Ledger().list, 0, "nothing stored from bad entries")
end

do -- reading the log shares it with the guild, in messages that fit the size limit
    local ns = fresh()
    S.bankLog = {}
    for i = 1, 25 do S.bankLog[i] = { "deposit", "Member Number" .. i, 1000 + i, 0, 0, 0, i } end
    S.fire("GUILDBANKLOG_UPDATE")
    advance(30)
    local msgs = ledgerMsgs("L|")
    truthy(#msgs >= 2, "split into several messages")
    local longest = 0
    for _, m in ipairs(msgs) do longest = math.max(longest, #m) end
    truthy(longest <= 255, "every message fits the 255-byte limit")
    local ns2 = fresh()
    for _, m in ipairs(msgs) do receive("Eve-Realm", m) end
    for _, m in ipairs(msgs) do receive("Dan-Realm", m) end
    local total = 0
    for _ in pairs(ns2.LedgerTotals()) do total = total + 1 end
    eq(total, 25, "a guildmate rebuilds all 25 entries from the messages")
end

do -- catching up: ask at login; one guildmate answers with first-hand entries, others stay quiet
    local ns = fresh()
    advance(16); advance(6)
    eq(#ledgerMsgs("Q|"), 1, "catch-up requested after login")
    S.bankLog = { { "deposit", "Bob Smith", 20000, 0, 0, 0, 5 } }
    S.fire("GUILDBANKLOG_UPDATE")
    advance(70); S.sent = {}
    receive("New-Realm", "Q|0")
    advance(13); advance(1)
    eq(#ledgerMsgs("R|0|"), 1, "we answer a catch-up request")
    S.sent = {}
    receive("Other-Realm", "Q|0")
    receive("Dan-Realm", "R|0|d,1,1,X")       -- someone else answered first
    advance(13); advance(1)
    eq(#ledgerMsgs("R|0|"), 0, "we stay quiet when someone else already answered")
end

do -- a gap is flagged when a new log does not overlap the history
    local ns = fresh()
    S.bankLog = { { "deposit", "Bob Smith", 20000, 0, 0, 0, 0 } }
    S.fire("GUILDBANKLOG_UPDATE")
    advance(3600 * 48)
    S.bankLog = { { "deposit", "Cara Jones", 7000, 0, 0, 0, 1 } }
    S.fire("GUILDBANKLOG_UPDATE")
    truthy(ns.Ledger().gapAt, "possible gap recorded")
end

local ROSTER = {
    { "Leeroy Mcbiff-Realm", "Player-1-0001", "Guild Master", 0 },
    { "Bob Smith-Realm", "Player-1-0003", "Member", 3 },
    { "Cara Jones-Realm", "Player-1-0004", "Officer", 1 },
    { "Dan Brown-Realm", "Player-1-0005", "Initiate", 4 },
}

do -- roster view: every guild member is listed, donors or not
    local ns = fresh({ unitName = "Leeroy", roster = ROSTER })
    advance(4)
    S.bankLog = { { "deposit", "Bob Smith", 20000, 0, 0, 0, 1 } }
    S.fire("GUILDBANKLOG_UPDATE")
    local rows = ns.BoardRows()
    eq(#rows, 4, "all four members listed")
    eq(rows[1].name, "Bob Smith", "the verified donor is first")
    local dan = rowFor(ns, "Dan Brown")
    truthy(dan and dan.inGuild and not dan.verified, "a non-donor is listed with nothing paid in")
    ns.HandleCommand("board")
    local b = _G.GuildCoffersBoard
    eq(b.lines[1][2]._text, "Bob Smith", "board shows the donor")
    truthy(b.lines[1][5]._text:find("2g", 1, true), "paid in shown")
    eq(b.lines[4][5]._text, "-", "non-donor shows nothing paid in")
    ns.HandleCommand("board")
end

do -- ratio of paid in to taken out
    local ns = fresh({ roster = ROSTER })
    advance(4)
    S.bankLog = { { "deposit", "Bob Smith", 20000, 0, 0, 0, 3 }, { "withdraw", "Bob Smith", 40000, 0, 0, 0, 1 } }
    S.fire("GUILDBANKLOG_UPDATE")
    ns.HandleCommand("board")
    local b = _G.GuildCoffersBoard
    local line
    for i = 1, 20 do if b.lines[i][2]._text == "Bob Smith" then line = b.lines[i] end end
    truthy(line and line[7]._text:find("33%", 1, true), "ratio shown as a percentage (paid 2g, took 4g: 33%)")
    ns.HandleCommand("board")
end

do -- scrolling a long roster
    local big = {}
    for i = 1, 45 do big[i] = { "Member " .. i .. "-Realm", "Player-1-" .. (100 + i), "Member", 3 } end
    local ns = fresh({ roster = big })
    advance(4)
    ns.HandleCommand("board")
    local b = _G.GuildCoffersBoard
    truthy(b.footer._text:find("of 46", 1, true), "footer says how many there are")
    b.scripts.OnMouseWheel(b, -1)
    eq(b.lines[1][1]._text, 4, "scrolling moves the list")
    ns.HandleCommand("board")
end

do -- promotions: officers only, threshold and window set in the UI, one click to promote
    local promoted
    local ns = fresh({ unitName = "Leeroy", roster = ROSTER })
    _G.CanGuildPromote = function() return true end
    _G.GuildPromote = function(name) promoted = name end
    advance(4)
    eq(ns.CanPromote(), true, "the guild master can promote")
    S.bankLog = {
        { "deposit", "Bob Smith", 20000, 0, 0, 0, 2 },      -- 2g, recent
        { "deposit", "Dan Brown", 500, 0, 0, 0, 3 },        -- 5s, recent
        { "deposit", "Cara Jones", 90000, 0, 0, 0, 1 },     -- officer: already just below you
    }
    S.fire("GUILDBANKLOG_UPDATE")
    local list = ns.PromotionCandidates()
    eq(#list, 2, "amount 'any': both members with a verified deposit (not the officer)")
    eq(list[1].name, "Bob Smith", "biggest first")
    ns.ShowPromotions()
    local b = _G.GuildCoffersBoard
    eq(b.amountText._text, "any", "amount shows 'any' at 0")
    eq(b.daysText._text, "30 days", "window shows 30 days by default")
    eq(b.lines[1][2]._text, "Bob Smith", "candidate listed")
    eq(b.lines[1].promote._shown, true, "Promote button shown")
    b.lines[1].promote.scripts.OnClick(b.lines[1].promote)
    eq(promoted, "Bob Smith-Realm", "clicking Promote promotes that member (full name for the game)")
    promoted = nil
    b.lines[1].promote.scripts.OnClick(b.lines[1].promote)
    eq(promoted, nil, "a second click does not promote twice")
    eq(b.lines[1][2]._text, "Dan Brown", "Bob leaves the list until the roster refreshes")
    advance(2)
    S.fire("GUILD_ROSTER_UPDATE"); advance(3)
    ns.db.promoAmount = 10000
    ns.RefreshBoard()
    eq(#ns.PromotionCandidates(), 1, "at 1g only Bob qualifies")
    eq(b.amountText._text, "1g", "amount shown")
    ns.db.promoDays = 0
    ns.RefreshBoard()
    eq(b.daysText._text, "all time", "0 days shows all time")
    _G.CanGuildPromote = nil
    _G.GuildPromote = nil
    ns.HandleCommand("board")
end

do -- promotions are hidden from members who cannot promote
    local ns = fresh({ unitName = "Bob", myGuid = "Player-1-0003", roster = ROSTER })
    advance(4)
    eq(ns.CanPromote(), false, "a member cannot promote")
    eq(#ns.PromotionCandidates(), 0, "no list for members")
    ns.HandleCommand("promote")
    truthy(printedAny("for guild members who are allowed to promote"), "the command explains why")
    ns.HandleCommand("board")
    eq(_G.GuildCoffersBoard.modeBtn._shown, false, "no Promotions button for members")
    ns.HandleCommand("board")
end

---------------------------------------------------------------------------
-- What counts as income, minimum deposit, guild rate
---------------------------------------------------------------------------

do -- only loot, vendor sales and auction sales are taxed
    local ns = fresh()
    gain(10 * GOLD)
    eq(ns.Char().owed, GOLD, "looted gold is taxed")
    advance(2)
    plain(10 * GOLD); advance(2)
    eq(ns.Char().owed, GOLD, "gold with no source (e.g. a refund) is not taxed")
    plain(4 * GOLD); S.fire("CHAT_MSG_MONEY", "Your share of the loot is 4 Gold.")
    eq(ns.Char().owed, GOLD + 4000, "your share of group loot is taxed (message after the gold)")
    S.fire("CHAT_MSG_MONEY", "You loot 2 Gold"); plain(2 * GOLD)
    eq(ns.Char().owed, GOLD + 6000, "and when the message comes first")
    advance(2)
    S.fire("MERCHANT_SHOW"); plain(GOLD); S.fire("MERCHANT_CLOSED")
    eq(ns.Char().owed, GOLD + 7000, "vendor sales are taxed")
    advance(2)
    S.fire("TRADE_SHOW"); plain(20 * GOLD); S.fire("TRADE_CLOSED")
    eq(ns.Char().owed, GOLD + 7000, "trades are not taxed")
end

do -- quest rewards are taxed
    local ns = fresh()
    S.fire("QUEST_COMPLETE"); plain(10 * GOLD); S.fire("QUEST_FINISHED")
    eq(ns.Char().owed, GOLD, "reward received while the quest reward window is open")
    advance(2)
    plain(5 * GOLD); S.fire("QUEST_TURNED_IN", 123, 0, 5 * GOLD)
    eq(ns.Char().owed, GOLD + 5000, "reward that arrives just before the turn-in event")
    advance(2)
    S.fire("QUEST_TURNED_IN", 124, 0, 2 * GOLD); plain(2 * GOLD)
    eq(ns.Char().owed, GOLD + 7000, "reward that arrives just after it")
end

do -- mail: auction sales are taxed, mail from players (including your own alts) is not
    local ns = fresh()
    S.inbox = {
        { "Myalt", "gold for you", 30 * GOLD, nil },
        { "Auction House", "Auction successful: Linen Cloth", 3 * GOLD, "seller" },
        { "Auction House", "Outbid on Copper Ore", 2 * GOLD, "buyer" },
    }
    S.fire("MAIL_SHOW")
    plain(30 * GOLD)
    eq(ns.Char().owed, 0, "gold mailed from your own character is not taxed")
    plain(2 * GOLD)
    eq(ns.Char().owed, 0, "an outbid refund is not taxed")
    plain(3 * GOLD)
    eq(ns.Char().owed, 3000, "an auction sale is taxed")
    S.fire("MAIL_CLOSED")
end

do -- auction sale recognised by its subject when the invoice is not available
    local ns = fresh({ noInvoice = true })
    S.inbox = { { "Auction House", "Auction successful: Linen Cloth", 3 * GOLD } }
    S.fire("MAIL_SHOW")
    S.inbox = {}                 -- the inbox refreshes before the gold arrives
    S.fire("MAIL_INBOX_UPDATE")
    plain(3 * GOLD)
    eq(ns.Char().owed, 3000, "still matched from the earlier inbox snapshot")
    S.fire("MAIL_CLOSED")
end

do -- minimum deposit: automatic deposits wait until enough is owed; Deposit now ignores it
    local ns = fresh({ keepMin = true })
    eq(ns.db.minDeposit, GOLD, "default minimum is 1g")
    ns.Char().owed = 5000                        -- 50s
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    eq(#S.deposits, 0, "50s owed: no automatic deposit")
    ns.TryDeposit(true)
    eq(S.deposits[1], 5000, "Deposit now still deposits it")
    S.fire("GUILDBANKFRAME_CLOSED")
    ns.Char().owed = 2 * GOLD
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    eq(S.deposits[2], 2 * GOLD, "2g owed: deposited automatically")
    S.fire("GUILDBANKFRAME_CLOSED")
    ns.HandleCommand("min 50s")
    eq(ns.db.minDeposit, 5000, "/coffers min sets it")
    ns.HandleCommand("min 0")
    eq(ns.db.minDeposit, 0, "0 deposits every time")
    ns.HandleCommand("window")
    local p = ns.panels[#ns.panels]
    eq(p.minText._text, "none", "panel shows the minimum")
end

do -- guild rate from the guild info text
    local ns = fresh({ guildInfo = "Welcome! Guild tax: [coffers:15] please." })
    S.fire("GUILD_ROSTER_UPDATE"); advance(3)
    eq(ns.Rate(), 15, "members follow the guild's rate")
    truthy(printedAny("guild's tax rate is 15%"), "told the guild rate")
    gain(10 * GOLD)
    eq(ns.Char().owed, 15000, "taxed at the guild rate")
    ns.HandleCommand("window")
    local p = ns.panels[#ns.panels]
    eq(p.rateText._text, "15%", "panel shows the guild rate")
    eq(p.rateNote._text, "guild rate", "and says it is the guild's")
    p.plus.scripts.OnClick(p.plus)
    eq(ns.Rate(), 16, "changing it makes it your own rate")
    eq(ns.db.rateMode, "own", "own rate remembered")
    eq(p.useGuild._shown, true, "Use guild rate button appears")
    S.guildInfo = "[coffers:20]"
    S.fire("GUILD_ROSTER_UPDATE"); advance(3)
    eq(ns.Rate(), 16, "your own rate is kept when officers change theirs")
    p.useGuild.scripts.OnClick(p.useGuild)
    eq(ns.Rate(), 20, "Use guild rate follows the guild again")
    S.guildInfo = "no tag here"
    S.fire("GUILD_ROSTER_UPDATE"); advance(3)
    eq(ns.Rate(), 16, "no guild rate: your own last rate applies")
    ns.HandleCommand("rate guild")
    eq(ns.db.rateMode, "guild", "/coffers rate guild")
end

---------------------------------------------------------------------------
-- Review fixes
---------------------------------------------------------------------------

do -- a deposit is credited even if the bank closes before the gold leaves
    local ns = fresh()
    ns.Char().owed = 5 * GOLD
    S.depositWorks = false                  -- the gold will leave late
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    S.fire("GUILDBANKFRAME_CLOSED"); advance(2)
    S.money = S.money - 5 * GOLD; S.fire("PLAYER_MONEY")
    eq(math.floor(ns.Char().owed), 0, "credited although the window had closed")
    eq(ns.Char().donated, 5 * GOLD, "counted as donated")
end

do -- tracking off stops automatic deposits
    local ns = fresh()
    ns.HandleCommand("off")
    ns.Char().owed = 5 * GOLD
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    eq(#S.deposits, 0, "no automatic deposit with tracking off")
    S.fire("GUILDBANKFRAME_CLOSED")
end

do -- an auction sale matches only once; a later player mail of the same amount is not taxed
    local ns = fresh()
    S.inbox = { { "Auction House", "Auction successful: Linen Cloth", 3 * GOLD, "seller" } }
    S.fire("MAIL_SHOW")
    S.fire("MAIL_INBOX_UPDATE"); S.fire("MAIL_INBOX_UPDATE")    -- rescans do not add it twice
    plain(3 * GOLD)
    eq(ns.Char().owed, 3000, "the sale is taxed")
    S.inbox = { { "Friend", "here you go", 3 * GOLD } }
    S.fire("MAIL_INBOX_UPDATE")
    plain(3 * GOLD)
    eq(ns.Char().owed, 3000, "a player's mail of the same amount is not")
    S.fire("MAIL_CLOSED")
end

do -- history flooding: per-sender limit, escape codes, non-members, observer cap
    local ns = fresh({ roster = { { "Bob Smith-Realm", "Player-1-0003", "Member", 3 },
        { "Eve Liar-Realm", "Player-1-0009", "Member", 3 }, { "Dan Brown-Realm", "Player-1-0005", "Member", 3 },
        { "Fay Lee-Realm", "Player-1-0006", "Member", 3 }, { "Gus Hill-Realm", "Player-1-0007", "Member", 3 } } })
    advance(4)
    local h = ns.Hour()
    for i = 1, 30 do
        local items = {}
        for j = 1, 6 do items[#items + 1] = "d," .. (i * 10 + j) .. "," .. h .. ",Bob Smith" end
        receive("Eve Liar-Realm", "L|" .. table.concat(items, ";"))
    end
    eq(#ns.Ledger().list, 100, "one guildmate can add at most 100 entries an hour")
    local before = #ns.Ledger().list
    receive("Dan Brown-Realm", "L|d,5," .. h .. ",|cff40ff40Fake")
    receive("Dan Brown-Realm", "L|d,5," .. h .. ",Not In Guild")
    eq(#ns.Ledger().list, before, "names with escape codes or outside the guild are refused")
    local msg = "L|d,777," .. h .. ",Bob Smith"
    for _, who in ipairs({ "Dan Brown-Realm", "Fay Lee-Realm", "Gus Hill-Realm", "Bob Smith-Realm" }) do
        receive(who, msg)
    end
    local e
    for _, x in ipairs(ns.Ledger().list) do if x.a == 777 then e = x end end
    local n = 0
    for _ in pairs(e.by) do n = n + 1 end
    eq(n, 3, "an entry remembers at most three reporters")
end

do -- the leaderboard is ranked by verified gold, not by what players claim
    local ns = fresh()
    receive("Mal-Realm", "1|10|999999999999|1|1700000000|")
    S.bankLog = { { "deposit", "Bob Smith", 20000, 0, 0, 0, 1 } }
    S.fire("GUILDBANKLOG_UPDATE")
    eq(ns.BoardRows()[1].name, "Bob Smith", "verified donor ranks above a huge claimed total")
end

do -- promotions need the officer to have seen it, or three reporters
    local ns = fresh({ unitName = "Leeroy", roster = ROSTER })
    _G.CanGuildPromote = function() return true end
    advance(4)
    local h = ns.Hour() - 1
    receive("Cara Jones-Realm", "L|d,50000," .. h .. ",Dan Brown")
    receive("Bob Smith-Realm", "L|d,50000," .. h .. ",Dan Brown")
    eq(ns.LedgerTotals()["dan brown"].paidIn, 50000, "two reporters: verified on the leaderboard")
    eq(#ns.PromotionCandidates(), 0, "but not enough for the promotions list")
    S.bankLog = { { "deposit", "Dan Brown", 50000, 0, 0, 0, 1 } }
    S.fire("GUILDBANKLOG_UPDATE")
    eq(#ns.PromotionCandidates(), 1, "once the officer sees it in the log, it counts")
    _G.CanGuildPromote = nil
end

do -- a shared first name cannot be used to take over someone else's name
    local ns = fresh({ unitName = "Bob", myGuid = "Player-1-0003", roster = {
        { "Leeroy Mcbiff-Realm", "Player-1-0001", "Member", 3 },
        { "Leeroy Jenkins-Realm", "Player-1-0002", "Member", 3 },
        { "Bob Smith-Realm", "Player-1-0003", "Member", 3 },
    } })
    advance(4)
    receive("Leeroy-Realm", "1|10|500|1|1700000000|Leeroy Jenkins")
    local jenkins = rowFor(ns, "Leeroy Jenkins")
    eq(jenkins and jenkins.donated, nil, "an ambiguous first-name sender cannot claim a full name")
end

do -- compact money text
    local ns = fresh()
    eq(ns.ShortCoin(1234567890), "123456g", "big amounts in gold only")
    eq(ns.ShortCoin(55000), "5g 50s", "gold and silver")
    eq(ns.ShortCoin(55), "55c", "small amounts in full")
end

do -- no account bank in the game: the own-bank option is hidden and cannot be chosen
    local ns = fresh({ noAccountBank = true })
    ns.HandleCommand("window")
    local p = ns.panels[#ns.panels]
    eq(p.destDropdown, nil, "no destination dropdown")
    eq(p.destGuild, nil, "and no fallback boxes")
    ns.HandleCommand("dest bank")
    eq(ns.db.dest, "guild", "own bank cannot be chosen")
    truthy(printedAny("no account (Warband) bank"), "the player is told why")
    ns.db.dest = "bank"                       -- chosen on an older version
    ns.Char().owed = 5 * GOLD
    S.fire("GUILDBANKFRAME_OPENED"); advance(1)
    eq(S.deposits[1], 5 * GOLD, "falls back to the guild bank")
    S.fire("GUILDBANKFRAME_CLOSED")
end

do -- spending money command and wording
    local ns = fresh()
    ns.HandleCommand("spending 50g")
    eq(ns.db.reserve, 50 * GOLD, "/coffers spending sets it")
    truthy(printedAny("spending money set to 50g"), "confirmed in chat")
end

real_print(string.format("%d checks passed, %d failed", passed, failures))
if failures > 0 then error("tests failed") end
