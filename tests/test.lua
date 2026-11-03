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
    }
end

local function makeFrame(name)
    local f = { scripts = {}, events = {} }
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
    function f.SetText(self, t) rawset(self, "_text", t) end
    function f.CreateFontString() return makeFrame() end
    function f.IsShown() return true end
    if name then _G[name] = f end
    return f
end

local function installGlobals()
    _G.print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
        S.printed[#S.printed + 1] = table.concat(t, " ")
    end
    _G.CreateFrame = function(_, name) return makeFrame(name) end
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
    _G.C_Timer = { After = function(dt, fn) S.timers[#S.timers + 1] = { at = S.now + dt, fn = fn } end }
    _G.DepositGuildBankMoney = function(amount)
        S.deposits[#S.deposits + 1] = amount
        if S.depositWorks then
            S.money = S.money - amount
            S.fire("PLAYER_MONEY")
        end
    end
    _G.GuildCoffersDB = nil
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
    for _, file in ipairs({ "Core.lua", "Tracker.lua", "UI.lua" }) do
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

do -- character key keeps spaces, window builds, status and unknown commands work
    local ns = fresh()
    truthy(ns.CharKey():find("Test Char", 1, true), "character key keeps the full name")
    ns.HandleCommand("")       -- builds and opens the window
    truthy(_G.GuildCoffersFrame, "window built")
    ns.HandleCommand("status")
    truthy(printedAny("Owed now"), "status prints")
    ns.HandleCommand("nonsense")
    truthy(printedAny("commands:"), "help shown for unknown command")
end

do -- coin text
    local ns = fresh()
    eq(ns.CoinText(0), "0c", "zero coins")
    eq(ns.CoinText(123456), "12g 34s 56c", "mixed coins")
    eq(ns.CoinText(10 * GOLD), "10g", "round gold")
end

real_print(string.format("%d checks passed, %d failed", passed, failures))
if failures > 0 then error("tests failed") end
