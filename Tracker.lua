-- Guild Coffers: gold tracking and guild bank deposits.
local _, ns = ...

local GRACE = 1.0          -- seconds to keep ignoring gold after a bank/trade window closes
local DEPOSIT_DELAY = 0.5  -- seconds after the guild bank opens before depositing
local CONFIRM_WAIT = 3.0   -- seconds to wait for the money to actually leave

local lastMoney            -- copper at the last PLAYER_MONEY
local loggedIn = false
local open = {}            -- open["guildbank"|"bank"|"trade"] = true while that window is open
local graceUntil = {}
local pending              -- { amount = copper, token = table } while a deposit is in flight

---------------------------------------------------------------------------
-- Which windows are open (so withdrawals and trades are not counted as income)
---------------------------------------------------------------------------

local kindByType = {}
do
    local PI = Enum and Enum.PlayerInteractionType
    if PI then
        local map = {
            GuildBanker = "guildbank", Banker = "bank",
            AccountBanker = "bank", Trade = "trade",
        }
        for name, kind in pairs(map) do
            if PI[name] ~= nil then kindByType[PI[name]] = kind end
        end
    end
end

local function now()
    return GetTime and GetTime() or 0
end

local function isOpen(kind)
    if open[kind] then return true end
    local g = graceUntil[kind]
    return g ~= nil and now() < g
end

local function setOpen(kind, state)
    if state then
        if open[kind] then return end
        open[kind] = true
        if kind == "guildbank" then
            C_Timer.After(DEPOSIT_DELAY, function()
                if open.guildbank then ns.TryDeposit(false) end
            end)
        end
    else
        if not open[kind] then return end
        open[kind] = false
        graceUntil[kind] = now() + GRACE
    end
end

---------------------------------------------------------------------------
-- Deposits
---------------------------------------------------------------------------

local function RecordDeposit(amount)
    local c = ns.Char()
    c.donated = c.donated + amount
    c.deposits = (c.deposits or 0) + 1
    c.lastDonated = time()
    c.owed = math.max(0, c.owed - amount)
    if c.owed < 1 then c.collected = 0 end   -- fully settled: start counting afresh
    local self_made = pending ~= nil
    pending = nil
    local msg = (self_made and "deposited " or "credited your manual deposit of ")
        .. ns.CoinText(amount) .. (self_made and " to the guild bank." or ".")
    if c.owed >= 1 then msg = msg .. " Still owed: " .. ns.CoinText(c.owed) .. "." end
    ns.Print(msg)
    if ns.RefreshUI then ns.RefreshUI() end
end

function ns.TryDeposit(manual)
    if not ns.db then return end
    if not open.guildbank then
        if manual then ns.Print("open the guild bank first, then try again.") end
        return
    end
    if pending then return end
    local c = ns.Char()
    local money = GetMoney()
    if ns.isSecret(money) then return end
    local amount = math.floor(math.min(c.owed, money))
    if amount < 1 then
        if manual then
            if c.owed > 0 then
                ns.Print("less than 1 copper owed so far. It builds up as you earn more.")
            else
                ns.Print("nothing owed right now.")
            end
        end
        return
    end
    if not DepositGuildBankMoney then
        ns.Print("this client has no guild bank deposit function. Run /coffers debug and report it.")
        return
    end
    local token = {}
    pending = { amount = amount, token = token }
    DepositGuildBankMoney(amount)
    -- A blocked call can fail silently, so confirm by watching the money leave.
    C_Timer.After(CONFIRM_WAIT, function()
        if pending and pending.token == token then
            pending = nil
            ns.Print("the deposit of " .. ns.CoinText(amount) .. " did not go through. "
                .. "Forever may be blocking addon deposits. Deposit by hand and it will still be credited.")
        end
    end)
end

---------------------------------------------------------------------------
-- Gold tracking
---------------------------------------------------------------------------

local function OnMoneyChanged()
    local money = GetMoney()
    if ns.isSecret(money) then return end
    if not loggedIn or not ns.db or lastMoney == nil then
        lastMoney = money
        return
    end
    local delta = money - lastMoney
    lastMoney = money
    if delta == 0 then return end

    if delta > 0 then
        -- Gold in. Ignore withdrawals and trades; count loot, quests, vendors and mail.
        if not ns.db.enabled then return end
        if isOpen("guildbank") or isOpen("bank") or isOpen("trade") then return end
        local c = ns.Char()
        c.owed = c.owed + delta * ns.db.rate / 100
        c.collected = (c.collected or 0) + delta
        if ns.RefreshUI then ns.RefreshUI() end
    elseif open.guildbank then
        -- Gold out while the guild bank is open is a deposit (ours or the player's own).
        local amount = -delta
        if pending then amount = math.min(amount, pending.amount) end
        RecordDeposit(amount)
    end
end

ns.On("PLAYER_LOGIN", function()
    loggedIn = true
    lastMoney = GetMoney()
    if ns.isSecret(lastMoney) then lastMoney = nil end
end)
ns.On("PLAYER_MONEY", OnMoneyChanged)

---------------------------------------------------------------------------
-- Window tracking: modern interaction events, with classic-style fallbacks
---------------------------------------------------------------------------

ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, interactionType)
    local kind = kindByType[interactionType]
    if kind then setOpen(kind, true) end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, interactionType)
    local kind = kindByType[interactionType]
    if kind then setOpen(kind, false) end
end)

-- Second way to notice the guild bank: hook Blizzard's frame itself, in case this
-- client opens it without firing the events above. Harmless if the frame is absent.
local function HookGuildBankFrame()
    local f = _G.GuildBankFrame
    if not f or ns.guildBankHooked then return end
    local ok = pcall(function()
        f:HookScript("OnShow", function() setOpen("guildbank", true) end)
        f:HookScript("OnHide", function() setOpen("guildbank", false) end)
    end)
    if not ok then return end
    ns.guildBankHooked = true
    if f:IsShown() then setOpen("guildbank", true) end
end
ns.On("PLAYER_LOGIN", HookGuildBankFrame)
ns.On("ADDON_LOADED", function(_, loaded)
    if loaded == "Blizzard_GuildBankUI" then HookGuildBankFrame() end
end)

-- /coffers watch: print guild-bank-related events for a minute, so we can see exactly
-- what this client does when the bank opens.
local WATCH_SECONDS = 60
local watchUntil = 0
local WATCH_EVENTS = {
    "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANK_UPDATE_TABS",
    "GUILDBANK_UPDATE_MONEY", "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_TEXT",
    "GUILDBANK_UPDATE_WITHDRAWMONEY", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
}
local watchRegistered = false

function ns.StartWatch()
    if not watchRegistered then
        watchRegistered = true
        for _, event in ipairs(WATCH_EVENTS) do
            ns.On(event, function(ev, arg1)
                if now() < watchUntil then
                    ns.Print("watch: " .. ev .. (arg1 ~= nil and (" " .. tostring(arg1)) or ""))
                end
            end)
        end
    end
    watchUntil = now() + WATCH_SECONDS
    local f = _G.GuildBankFrame
    ns.Print("watching guild bank events for " .. WATCH_SECONDS .. "s. Open the guild bank now. "
        .. "Blizzard GuildBankFrame: " .. (f and (f:IsShown() and "present, shown" or "present, hidden") or "not found")
        .. ". Guild bank counted as open: " .. tostring(open.guildbank == true) .. ".")
end

ns.On("GUILDBANKFRAME_OPENED", function() setOpen("guildbank", true) end)
ns.On("GUILDBANKFRAME_CLOSED", function() setOpen("guildbank", false) end)
ns.On("BANKFRAME_OPENED", function() setOpen("bank", true) end)
ns.On("BANKFRAME_CLOSED", function() setOpen("bank", false) end)
ns.On("TRADE_SHOW", function() setOpen("trade", true) end)
ns.On("TRADE_CLOSED", function() setOpen("trade", false) end)
