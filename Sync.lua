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

-- Forever characters have a first and a last name. Some parts of the game give the full name
-- ("Leeroy Mcbiff"), others only the first ("Leeroy"). Treat those as the same person.
local function Norm(name)
    local s = Short(name):lower()
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end
function ns.SameName(a, b)
    a, b = Norm(a), Norm(b)
    if a == "" or b == "" then return false end
    if a == b then return true end
    return b:sub(1, #a + 1) == a .. " " or a:sub(1, #b + 1) == b .. " "
end

---------------------------------------------------------------------------
-- Full names. The guild roster is the source: it lists every member's full name, and the
-- player's own entry is found by their unique character ID (GUID), not by name.
---------------------------------------------------------------------------

local roster = {}   -- full names of guild members (realm removed)
ns.roster = roster
ns.rosterInfo = {}  -- [lower-case full name] = { name, raw, rankName, rankIndex }

local function pack(...) return { n = select("#", ...), ... } end

function ns.ScanRoster()
    if not (GetNumGuildMembers and GetGuildRosterInfo) or not ns.db then return end
    local okN, n = pcall(GetNumGuildMembers)
    if not okN or not ok(n) or type(n) ~= "number" then return end
    local myGuid = UnitGUID and UnitGUID("player")
    if not ok(myGuid) then myGuid = nil end
    for i = #roster, 1, -1 do roster[i] = nil end
    local info = {}
    for i = 1, n do
        local r = pack(pcall(GetGuildRosterInfo, i))
        if r[1] and ok(r[2]) and type(r[2]) == "string" and r[2] ~= "" then
            local full = Short(r[2])
            roster[#roster + 1] = full
            info[full:lower()] = {
                name = full, raw = r[2],
                rankName = ok(r[3]) and tostring(r[3]) or "?",
                rankIndex = ok(r[4]) and tonumber(r[4]) or nil,
            }
            if myGuid then
                for j = 3, r.n do
                    if ok(r[j]) and r[j] == myGuid then
                        ns.Char().fullName = full
                        ns.myRankIndex = info[full:lower()].rankIndex
                        break
                    end
                end
            end
        end
    end
    ns.rosterInfo = info
    -- Lookups for FullName: exact names, and first names that belong to exactly one member.
    local exact, first = {}, {}
    for _, full in ipairs(roster) do
        local f = Norm(full)
        exact[f] = full
        local fn = f:match("^(%S+) ")
        if fn then
            if first[fn] == nil then first[fn] = full else first[fn] = false end
        end
    end
    ns.rosterExact, ns.rosterFirst = exact, first
    if ns.RefreshBoard then ns.RefreshBoard() end
end

-- The full name for a name that may be first-name-only: an exact roster match, or the only
-- roster member with that first name. If two members share it, the name is left as given.
function ns.FullName(name)
    name = Short(name)
    local n = Norm(name)
    local full = ns.rosterExact and ns.rosterExact[n]
    if full then return full end
    full = ns.rosterFirst and ns.rosterFirst[n]
    if full then return full end   -- false (two members share it) falls through
    return name
end

-- Every name the game gives for the player, most complete first.
function ns.MyNames()
    local names = {}
    if ns.db and ns.Char().fullName then names[1] = ns.Char().fullName end
    local function add(fn, ...)
        if not fn then return end
        local okC, n = pcall(fn, ...)
        if okC and type(n) == "string" and n ~= "" and not ns.isSecret(n) then names[#names + 1] = Short(n) end
    end
    add(UnitName, "player")
    add(GetUnitName, "player", false)
    add(UnitFullName, "player")
    table.sort(names, function(x, y) return #x > #y end)
    return names
end

function ns.IsMe(name)
    local full = ns.db and ns.Char().fullName
    if full then return Norm(ns.FullName(name)) == Norm(full) end
    -- No roster yet (or no guild): fall back to first-name matching.
    for _, n in ipairs(ns.MyNames()) do
        if ns.SameName(n, name) then return true end
    end
    return false
end

local function Board()
    ns.db.board = ns.db.board or {}
    return ns.db.board
end
---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function Send(msg)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn or not IsInGuild or not IsInGuild() then return false end
    return pcall(fn, PREFIX, msg, "GUILD")
end

ns.SendGuild = Send

-- Tell the guild our rate and totals (if the player allows it).
function ns.ShareNow()
    -- Saving to your own bank is private: nothing is announced to the guild.
    if not ns.db or ns.db.dest == "bank" then return end
    local c = ns.Char()
    lastSent = now()
    local full = (c.fullName or ""):gsub("|", "")
    Send(string.format("%d|%d|%d|%d|%d|%s", PROTOCOL, ns.db.rate or 0,
        math.floor(c.donated or 0), c.deposits or 0, c.lastDonated or 0, full))
end

-- Share soon, but never more often than MIN_GAP, so changes are batched.
function ns.ScheduleShare()
    if sharePending or not ns.db or ns.db.dest == "bank" then return end
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
    if who == "" then return end

    local kind = text:match("^(%w+)|")
    if kind == "H" then
        if ns.IsMe(who) then return end
        -- Someone just logged in and wants to know who is using the addon. Answer after a
        -- random pause so a whole guild does not reply in the same second.
        if ns.db.dest ~= "bank" and now() - lastSent > 10 then
            C_Timer.After(2 + (math.random and math.random() or 0.5) * 8, function() ns.ShareNow() end)
        end
        return
    end
    if kind == "L" or kind == "R" or kind == "Q" then
        local observer = ns.FullName(who)
        if ns.IsMe(observer) then return end
        if ns.OnLedgerMessage then ns.OnLedgerMessage(kind, text, observer) end
        return
    end
    if kind ~= tostring(PROTOCOL) then return end

    local _, rate, donated, deposits, last, claimed = text:match("^(%w+)|(%d+)|(%d+)|(%d+)|(%d+)|?([^|]*)$")
    rate = Number(rate, 0, 100)
    donated = Number(donated, 0, 1e12)
    deposits = Number(deposits, 0, 1e7)
    last = Number(last, 0, 4e9)
    if not (rate and donated and deposits and last) then return end

    -- The sender's full name: what they say it is, but only if it really is their name
    -- (it must match the name the game gives for the sender), else the roster's version.
    local name = ns.FullName(who)
    if claimed and claimed ~= "" and #claimed <= 60 and ns.SameName(claimed, who) then name = claimed end
    if ns.IsMe(name) then return end   -- our own message coming back

    local board = Board()
    board[who] = nil   -- an older entry stored under the short name
    board[name] = { rate = rate, donated = donated, deposits = deposits, last = last, seen = time() }
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
    local nowH = ns.Hour()
    local obs = {}
    for i = 1, n do
        local okT, kind, name, amount, years, months, days, hours = pcall(GetGuildBankMoneyTransaction, i)
        local t = okT and ok(kind) and ns.LEDGER_TYPES[kind]
        if t and ok(name) and ok(amount) and (tonumber(amount) or 0) >= 1 then
            local ageHours = ((tonumber(years) or 0) * 365 + (tonumber(months) or 0) * 30
                + (tonumber(days) or 0)) * 24 + (tonumber(hours) or 0)
            obs[#obs + 1] = { t = t, n = Short(name), a = math.floor(tonumber(amount)), h = nowH - ageHours }
        end
    end
    if #obs == 0 then return end
    local me = ns.Char().fullName or ns.MyNames()[1]
    ns.LedgerObserve(obs, me, true)
    ns.ShareObservations(obs)
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
    -- One row per player: guild roster members, addon users and anyone in the history.
    -- Names are matched allowing for first-name-only and full versions; the fullest is shown.
    local rows, byNorm = {}, {}
    local exact = #roster > 0   -- full names known: exact match only (and a fast lookup)
    local function row(name)
        name = ns.FullName(name)
        local found
        if exact then
            found = byNorm[Norm(name)]
        else
            for _, r in ipairs(rows) do
                if ns.SameName(r.name, name) then found = r; break end
            end
        end
        if found then
            if #name > #found.name then found.name = name end
            return found
        end
        local r = { name = name }
        rows[#rows + 1] = r
        byNorm[Norm(name)] = r
        return r
    end
    if ns.db then
        local c = ns.Char()
        local me = row(ns.MyNames()[1] or "?")
        me.rate, me.donated, me.deposits, me.last = ns.db.rate, math.floor(c.donated or 0),
            c.deposits or 0, c.lastDonated or 0
        me.usesAddon, me.me = true, true
        for name, e in pairs(Board()) do
            if not ns.IsMe(name) then
                local r = row(name)
                r.rate, r.donated, r.deposits, r.last = e.rate, e.donated, e.deposits, e.last
                r.usesAddon = true
            end
        end
        for _, t in pairs(ns.LedgerTotals()) do
            local r = row(t.name)
            r.paidIn = (r.paidIn or 0) + t.paidIn
            r.paidCount = (r.paidCount or 0) + t.paidCount
            r.lastPaid = math.max(r.lastPaid or 0, t.lastPaid)
            r.takenOut = (r.takenOut or 0) + t.takenOut
            r.repairs = (r.repairs or 0) + t.repairs
            r.verified = (r.paidCount or 0) > 0
        end
        for _, full in ipairs(roster) do
            local r = row(full)
            local info = ns.rosterInfo[full:lower()]
            r.inGuild = true
            if info then r.rankName, r.rankIndex = info.rankName, info.rankIndex end
        end
    end
    for _, r in ipairs(rows) do
        r.score = (r.paidIn or 0) * 2 + (r.donated or 0)   -- verified gold counts first
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
        if ns.db and ns.db.dest ~= "bank" and IsInGuild and IsInGuild() then
            ns.ShareNow()
            Send("H|" .. PROTOCOL)   -- ask who else is using the addon
            C_Timer.After(5, function() if ns.RequestCatchUp then ns.RequestCatchUp() end end)
        end
    end)
end)
ns.On("PLAYER_LOGIN", function()
    -- Ask the server for the guild roster (that is where full names come from).
    C_Timer.After(3, function()
        local req = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
        if req and IsInGuild and IsInGuild() then pcall(req) end
        ns.ScanRoster()
    end)
end)
ns.On("GUILD_ROSTER_UPDATE", function() ns.ScanRoster() end)
ns.On("CHAT_MSG_ADDON", OnAddonMessage)
ns.On("GUILDBANKLOG_UPDATE", ns.ReadBankLog)
