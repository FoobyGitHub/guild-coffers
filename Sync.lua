-- Guild Coffers: sharing donation totals with guildmates, and checking them against the
-- guild bank's own money log.
--
-- Totals other players send are self-reported, so anyone could fake theirs. The bank log is
-- kept by the game, so a deposit seen there is real. The leaderboard shows both and marks
-- which players are verified.
local _, ns = ...

local PREFIX = "GuildCoffers"
local PROTOCOL = 1
local MIN_GAP = 30          -- seconds between our own broadcasts
local LOGIN_DELAY = 15      -- wait after login before announcing ourselves
local MAX_BOARD = 300       -- most guildmates kept
local MAX_LOG_TAB = 8       -- the money log is the tab after the last item tab
local lastSent = -1000
local sharePending = false

local function now() return GetTime and GetTime() or 0 end

local function ok(v) return v ~= nil and not ns.isSecret(v) end

-- "Name-Realm" -> "Name"
local function Short(name)
    name = tostring(name or "")
    return name:match("^(.-)%-[^%-]*$") or name
end
ns.ShortName = Short

local function Board()
    ns.db.board = ns.db.board or {}
    return ns.db.board
end
local function Bank()
    ns.db.bank = ns.db.bank or {}
    return ns.db.bank
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function Send(msg)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn or not IsInGuild or not IsInGuild() then return false end
    return pcall(fn, PREFIX, msg, "GUILD")
end

-- Tell the guild our rate and totals (if the player allows it).
function ns.ShareNow()
    -- Saving to your own bank is private: nothing is announced to the guild.
    if not ns.db or not ns.db.share or ns.db.dest == "bank" then return end
    local c = ns.Char()
    lastSent = now()
    Send(string.format("%d|%d|%d|%d|%d", PROTOCOL, ns.db.rate or 0,
        math.floor(c.donated or 0), c.deposits or 0, c.lastDonated or 0))
end

-- Share soon, but never more often than MIN_GAP, so changes are batched.
function ns.ScheduleShare()
    if sharePending or not ns.db or not ns.db.share or ns.db.dest == "bank" then return end
    sharePending = true
    local wait = math.max(5, lastSent + MIN_GAP - now())
    C_Timer.After(wait, function()
        sharePending = false
        ns.ShareNow()
    end)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function Number(v, lo, hi)
    local n = tonumber(v)
    if not n or n ~= n then return nil end
    if n < lo then n = lo end
    if n > hi then n = hi end
    return math.floor(n)
end

local function Prune(board)
    local count, oldestKey, oldest = 0, nil, math.huge
    for key, e in pairs(board) do
        count = count + 1
        if (e.seen or 0) < oldest then oldest, oldestKey = e.seen or 0, key end
    end
    if count > MAX_BOARD and oldestKey then board[oldestKey] = nil end
end

local function OnAddonMessage(_, prefix, text, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" then return end
    if not ok(text) or not ok(sender) or not ns.db then return end
    text, sender = tostring(text), tostring(sender)
    local who = Short(sender)
    if who == "" or who == Short(UnitName("player")) then return end

    local kind = text:match("^(%w+)|")
    if kind == "H" then
        -- Someone just logged in and wants to know who is using the addon. Answer after a
        -- random pause so a whole guild does not reply in the same second.
        if ns.db.share and now() - lastSent > 10 then
            C_Timer.After(2 + (math.random and math.random() or 0.5) * 8, function() ns.ShareNow() end)
        end
        return
    end
    if kind ~= tostring(PROTOCOL) then return end

    local _, rate, donated, deposits, last = text:match("^(%w+)|(%d+)|(%d+)|(%d+)|(%d+)$")
    rate = Number(rate, 0, 100)
    donated = Number(donated, 0, 1e12)
    deposits = Number(deposits, 0, 1e7)
    last = Number(last, 0, 4e9)
    if not (rate and donated and deposits and last) then return end

    local board = Board()
    board[who] = { rate = rate, donated = donated, deposits = deposits, last = last, seen = time() }
    Prune(board)
    if ns.RefreshBoard then ns.RefreshBoard() end
end

---------------------------------------------------------------------------
-- The guild bank's own money log (the verified part)
---------------------------------------------------------------------------

local function LogTab() return (MAX_GUILDBANK_TABS or MAX_LOG_TAB) + 1 end

-- Ask the server for the money log. Needs the guild bank open.
function ns.QueryBankLog()
    if not QueryGuildBankLog then return end
    pcall(QueryGuildBankLog, LogTab())
end

-- Read the log the client holds and total each player's deposits.
function ns.ReadBankLog()
    if not (GetNumGuildBankMoneyTransactions and GetGuildBankMoneyTransaction) or not ns.db then return end
    local okN, n = pcall(GetNumGuildBankMoneyTransactions)
    if not okN or not ok(n) then return end
    local totals = {}
    for i = 1, n do
        local okT, kind, name, amount, years, months, days, hours = pcall(GetGuildBankMoneyTransaction, i)
        if okT and kind == "deposit" and ok(name) and ok(amount) then
            name = Short(name)
            local age = (((tonumber(years) or 0) * 365 + (tonumber(months) or 0) * 30
                + (tonumber(days) or 0)) * 24 + (tonumber(hours) or 0)) * 3600
            local t = totals[name]
            if not t then
                t = { total = 0, count = 0, last = 0 }
                totals[name] = t
            end
            t.total = t.total + (tonumber(amount) or 0)
            t.count = t.count + 1
            t.last = math.max(t.last, time() - age)
        end
    end
    local bank = Bank()
    for name, t in pairs(totals) do bank[name] = t end
    if ns.RefreshBoard then ns.RefreshBoard() end
end

-- /coffers log: report what the money log holds, so the history can be designed around facts.
function ns.LogProbe()
    if not (QueryGuildBankLog and GetNumGuildBankMoneyTransactions and GetGuildBankMoneyTransaction) then
        ns.Print("this client has no guild bank log functions. Run /coffers debug and report it.")
        return
    end
    if not (ns.IsGuildBankOpen and ns.IsGuildBankOpen()) then
        ns.Print("open the guild bank first, then run /coffers log again.")
        return
    end
    ns.Print("asking the guild bank for its money log...")
    ns.QueryBankLog()
    C_Timer.After(2.5, function()
        local okN, n = pcall(GetNumGuildBankMoneyTransactions)
        if not okN or not ok(n) then ns.Print("could not read the log.") return end
        local kinds, names, nameCount = {}, {}, 0
        local first, last
        for i = 1, n do
            local okT, kind, name, amount, y, m, d, h = pcall(GetGuildBankMoneyTransaction, i)
            if okT and ok(kind) then
                kinds[tostring(kind)] = (kinds[tostring(kind)] or 0) + 1
                if ok(name) and not names[tostring(name)] then names[tostring(name)] = true; nameCount = nameCount + 1 end
                local age = string.format("%sy %sm %sd %sh ago", tostring(y), tostring(m), tostring(d), tostring(h))
                if i == 1 then first = age end
                last = age
            end
        end
        local parts = {}
        for kind, count in pairs(kinds) do parts[#parts + 1] = kind .. " " .. count end
        table.sort(parts)
        ns.Print(string.format("money log: %d entries (%s), %d different players.", n,
            #parts > 0 and table.concat(parts, ", ") or "none", nameCount))
        if first then ns.Print("first entry listed: " .. first .. "; last entry listed: " .. last .. ".") end
    end)
end

-- Called by the tracker when the guild bank opens and after our own deposit.
function ns.OnGuildBankOpened()
    C_Timer.After(1, ns.QueryBankLog)
end
function ns.OnDepositRecorded()
    ns.ScheduleShare()
    C_Timer.After(3, ns.QueryBankLog)
end

---------------------------------------------------------------------------
-- Leaderboard data
---------------------------------------------------------------------------

-- One row per player we know about, biggest donor first.
-- verified = the guild bank log shows at least one deposit by them.
function ns.BoardRows()
    local rows, byName = {}, {}
    local function row(name)
        if not byName[name] then
            byName[name] = { name = name }
            rows[#rows + 1] = byName[name]
        end
        return byName[name]
    end
    if ns.db then
        for name, e in pairs(Board()) do
            local r = row(name)
            r.rate, r.donated, r.deposits, r.last = e.rate, e.donated, e.deposits, e.last
            r.usesAddon = true
        end
        local c = ns.Char()
        local me = row(Short(UnitName("player")))
        me.rate, me.donated, me.deposits, me.last = ns.db.rate, math.floor(c.donated or 0),
            c.deposits or 0, c.lastDonated or 0
        me.usesAddon, me.me = true, true
        for name, t in pairs(Bank()) do
            local r = row(name)
            r.bankTotal, r.bankCount, r.bankLast = t.total, t.count, t.last
            r.verified = true
        end
    end
    for _, r in ipairs(rows) do
        r.score = math.max(r.donated or 0, r.bankTotal or 0)
    end
    table.sort(rows, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    return rows
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if reg then pcall(reg, PREFIX) end
    C_Timer.After(LOGIN_DELAY, function()
        if ns.db and ns.db.share and ns.db.dest ~= "bank" then
            ns.ShareNow()
            Send("H|" .. PROTOCOL)   -- ask who else is using the addon
        end
    end)
end)
ns.On("CHAT_MSG_ADDON", OnAddonMessage)
ns.On("GUILDBANKLOG_UPDATE", ns.ReadBankLog)
