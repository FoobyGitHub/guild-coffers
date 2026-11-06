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
local FlushChat            -- defined with the chat summary below; the windows code calls it

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
            Merchant = "merchant", MailInfo = "mail",
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
        if kind == "guildbank" and ns.OnGuildBankOpened then ns.OnGuildBankOpened() end
        if kind == "guildbank" and ns.db and ns.db.dest == "bank" and ns.Char().owed >= 1 then
            ns.Print("deposits are set to your own bank, so nothing goes to the guild bank. "
                .. "Switch with /coffers dest guild.")
        end
        -- Deposit shortly after the chosen bank opens (the guild bank, or the player's own).
        local wanted = (ns.db and ns.db.dest == "bank") and "bank" or "guildbank"
        if kind == wanted then
            C_Timer.After(DEPOSIT_DELAY, function()
                if open[wanted] then ns.TryDeposit(false) end
            end)
        end
    else
        if not open[kind] then return end
        open[kind] = false
        graceUntil[kind] = now() + GRACE
        -- Finished at the vendor or mailbox: report everything from that visit at once.
        if kind == "merchant" or kind == "mail" then FlushChat() end
    end
end

---------------------------------------------------------------------------
-- Deposits
---------------------------------------------------------------------------

local function RecordDeposit(amount, dest)
    local c = ns.Char()
    local own = (dest == "bank")
    if own then
        -- Saving to your own bank is not a guild donation, so it is kept out of the shared totals.
        c.saved = (c.saved or 0) + amount
    else
        c.donated = c.donated + amount
        c.deposits = (c.deposits or 0) + 1
        c.lastDonated = time()
    end
    c.owed = math.max(0, c.owed - amount)
    if c.owed < 1 then c.collected = 0 end   -- fully settled: start counting afresh
    local self_made = pending ~= nil
    pending = nil
    local msg
    if self_made then
        msg = "deposited " .. ns.CoinText(amount) .. (own and " to your own bank." or " to the guild bank.")
    else
        msg = "credited your manual deposit of " .. ns.CoinText(amount) .. "."
    end
    if c.owed >= 1 then msg = msg .. " Still owed: " .. ns.CoinText(c.owed) .. "." end
    ns.Print(msg)
    if not own and ns.OnDepositRecorded then ns.OnDepositRecorded() end
    if ns.RefreshUI then ns.RefreshUI() end
end

-- Put gold into the player's own bank (the account-wide Warband bank on modern clients).
local function DepositOwnBank(amount)
    local bankType = Enum and Enum.BankType and Enum.BankType.Account
    if not (C_Bank and C_Bank.DepositMoney and bankType) then return false end
    return pcall(C_Bank.DepositMoney, bankType, amount)
end

function ns.IsGuildBankOpen() return open.guildbank == true end

function ns.TryDeposit(manual)
    if not ns.db then return end
    local dest = (ns.db.dest == "bank") and "bank" or "guild"
    local kind = (dest == "bank") and "bank" or "guildbank"
    if not open[kind] then
        if manual then
            ns.Print("open " .. (dest == "bank" and "your bank" or "the guild bank") .. " first, then try again.")
        end
        return
    end
    if pending then return end
    local c = ns.Char()
    local money = GetMoney()
    if ns.isSecret(money) then return end
    -- The automatic deposit waits until enough is owed, so tiny amounts do not fill the
    -- guild bank log. "Deposit now" ignores this.
    if not manual and c.owed < (ns.db.minDeposit or 0) then return end
    -- Never take the player below their chosen minimum.
    local reserve = ns.db.reserve or 0
    local amount = math.floor(math.min(c.owed, money - reserve))
    if amount < 1 then
        if reserve > 0 and c.owed >= 1 and money - reserve < 1 then
            -- Owed gold is waiting only because of the reserve: say so, even on the automatic path.
            ns.Print("keeping your " .. ns.ReserveText(reserve) .. " reserve, so nothing deposited. "
                .. "Still owed: " .. ns.CoinText(c.owed) .. ".")
        elseif manual then
            if c.owed > 0 then
                ns.Print("less than 1 copper owed so far. It builds up as you earn more.")
            else
                ns.Print("nothing owed right now.")
            end
        end
        return
    end
    if dest == "guild" and not DepositGuildBankMoney then
        ns.Print("this client has no guild bank deposit function. Run /coffers debug and report it.")
        return
    end
    local token = {}
    pending = { amount = amount, token = token, dest = dest }
    if dest == "guild" then
        DepositGuildBankMoney(amount)
    elseif not DepositOwnBank(amount) then
        pending = nil
        ns.Print("this client has no own-bank gold deposit. Run /coffers debug and report it, "
            .. "or switch back with /coffers dest guild.")
        return
    end
    -- A blocked call can fail silently, so confirm by watching the money leave.
    C_Timer.After(CONFIRM_WAIT, function()
        if pending and pending.token == token then
            pending = nil
            ns.Print("the deposit of " .. ns.CoinText(amount) .. " did not go through. "
                .. "Forever may be blocking addon deposits." .. (dest == "guild" and " Deposit by hand and it will still be credited." or ""))
        end
    end)
end

---------------------------------------------------------------------------
-- Gold tracking
---------------------------------------------------------------------------

-- Chat summary. Gold from loot, quests and the like is reported straight away. Gold
-- received while a vendor or mailbox window is open is added up and reported once,
-- when that window closes (so selling a bag of items gives one line, not one per item).
-- The long timer is only a safety net in case a close event is ever missed.
local FAILSAFE_DELAY = 60.0
local windowFrames = { merchant = "MerchantFrame", mail = "MailFrame" }
local pendingChat

function FlushChat()
    local p = pendingChat
    pendingChat = nil
    if not p or not ns.db or not ns.db.showChat then return end
    ns.Print(string.format("+%s received, tax %s (total to keep: %s)",
        ns.CoinText(p.gain), ns.OwedText(p.tax), ns.OwedText(ns.Char().owed)))
end

-- Is this window open? If we think so but Blizzard's own frame says it is closed,
-- we missed the close event: correct ourselves (which also prints the summary).
local function WindowIsOpen(kind)
    if not open[kind] then return false end
    local f = _G[windowFrames[kind]]
    if f and f.IsShown and not f:IsShown() then
        setOpen(kind, false)
        return false
    end
    return true
end

local function QueueChat(gain, tax)
    pendingChat = pendingChat or { gain = 0, tax = 0 }
    pendingChat.gain = pendingChat.gain + gain
    pendingChat.tax = pendingChat.tax + tax
    if WindowIsOpen("merchant") or WindowIsOpen("mail") then
        local token = {}
        pendingChat.token = token
        C_Timer.After(FAILSAFE_DELAY, function()
            if pendingChat and pendingChat.token == token then FlushChat() end
        end)
    else
        FlushChat()
    end
end

---------------------------------------------------------------------------
-- Which gold counts as income. Only genuine earnings are taxed:
--   * gold you loot (from a loot window, or your share of a group's loot),
--   * vendor sales (gold received while a merchant window is open),
--   * auction house sales (the "Auction successful" mail).
-- Everything else is left alone: trades, mail from players (including your own
-- characters), quest rewards, refunds and bank withdrawals.
---------------------------------------------------------------------------

local LOOT_MSG_WAIT = 1.0   -- seconds to wait for the loot chat message after gold arrives
local pendingGains = {}     -- gold that arrived with no clear source, waiting for a loot message

-- Money-bearing mail seen in the inbox, as two snapshots (the newest and the one before),
-- so a payment can be matched even if the inbox refreshes before the gold arrives.
local mailNow, mailBefore = {}, {}
local saleSubject           -- "Auction successful: (.+)" built from the game's own text

local function IsSaleMail(index, subject)
    if GetInboxInvoiceInfo then
        local okI, invoiceType = pcall(GetInboxInvoiceInfo, index)
        if okI and invoiceType == "seller" then return true end
    end
    if not saleSubject and type(AUCTION_SOLD_MAIL_SUBJECT) == "string" then
        saleSubject = "^" .. AUCTION_SOLD_MAIL_SUBJECT:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+")
    end
    return saleSubject ~= nil and type(subject) == "string" and subject:find(saleSubject) ~= nil
end

local function ScanInbox()
    if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
    local okN, n = pcall(GetInboxNumItems)
    if not okN or ns.isSecret(n) or type(n) ~= "number" then return end
    local snap = {}
    for i = 1, n do
        local okH, _, _, _, subject, money = pcall(GetInboxHeaderInfo, i)
        if okH and not ns.isSecret(money) and type(money) == "number" and money > 0 then
            snap[#snap + 1] = { money = money, sale = IsSaleMail(i, subject) }
        end
    end
    mailBefore, mailNow = mailNow, snap
end

-- Is this payment an auction house sale? Matched by amount against the inbox.
local function MailGainIsSale(amount)
    for _, list in ipairs({ mailNow, mailBefore }) do
        for i, m in ipairs(list) do
            if m.money == amount then
                table.remove(list, i)
                return m.sale
            end
        end
    end
    return false   -- not recognised: treat as ordinary mail, not taxed
end

local function Tax(delta)
    local c = ns.Char()
    local rate = ns.Rate()
    c.owed = c.owed + delta * rate / 100
    c.collected = (c.collected or 0) + delta
    if ns.db.showChat then QueueChat(delta, delta * rate / 100) end
    if ns.RefreshUI then ns.RefreshUI() end
end

local function OnLootMessage()
    -- Your loot, or your share of a group's loot. The gold may already have arrived.
    graceUntil.lootmsg = now() + LOOT_MSG_WAIT
    local waiting = pendingGains
    pendingGains = {}
    for _, p in ipairs(waiting) do Tax(p.delta) end
end

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
        if not ns.db.enabled then return end
        if isOpen("guildbank") or isOpen("bank") or isOpen("trade") then return end   -- withdrawals, trades
        if isOpen("mail") then
            if MailGainIsSale(delta) then Tax(delta) end      -- auction sales only
        elseif isOpen("merchant") or isOpen("loot") or isOpen("lootmsg") then
            Tax(delta)                                         -- vendor sales and loot
        else
            -- No clear source yet. If the loot chat message follows, it was loot.
            local p = { delta = delta }
            pendingGains[#pendingGains + 1] = p
            C_Timer.After(LOOT_MSG_WAIT, function()
                for i, q in ipairs(pendingGains) do
                    if q == p then table.remove(pendingGains, i) break end   -- not loot: not taxed
                end
            end)
        end
    elseif pending and pending.dest == "bank" and open.bank then
        -- Our own-bank deposit leaving. (Other gold spent at a bank is not counted.)
        RecordDeposit(math.min(-delta, pending.amount), "bank")
    elseif open.guildbank then
        -- Gold out while the guild bank is open is a deposit (ours or the player's own).
        local amount = -delta
        if pending then amount = math.min(amount, pending.amount) end
        RecordDeposit(amount, "guild")
    end
end

ns.On("PLAYER_LOGIN", function()
    loggedIn = true
    lastMoney = GetMoney()
    if ns.isSecret(lastMoney) then lastMoney = nil end
end)
ns.On("PLAYER_MONEY", OnMoneyChanged)
ns.On("CHAT_MSG_MONEY", OnLootMessage)
ns.On("LOOT_OPENED", function() setOpen("loot", true) end)
ns.On("LOOT_CLOSED", function() setOpen("loot", false) end)
ns.On("MAIL_INBOX_UPDATE", ScanInbox)
ns.On("MAIL_SHOW", function() mailNow, mailBefore = {}, {} ScanInbox() end)
ns.On("MERCHANT_SHOW", function() setOpen("merchant", true) end)
ns.On("MERCHANT_CLOSED", function() setOpen("merchant", false) end)
ns.On("MAIL_SHOW", function() setOpen("mail", true) end)
ns.On("MAIL_CLOSED", function() setOpen("mail", false) end)

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
