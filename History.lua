-- Guild Coffers: donation history, built from the guild bank's money log.
--
-- The bank log only holds recent entries, so each player who opens the guild bank records
-- what it shows and shares it with guildmates. Everyone merges what they receive into one
-- history. Entries are matched (same player, type and amount, within an hour), so the same
-- deposit seen by many people is counted once, whatever order the reports arrive in.
--
-- An entry is Verified when you saw it in the bank log yourself, or when at least two
-- different guildmates report it. One person's report alone is not trusted.
local _, ns = ...

local MAX_ENTRIES = 5000
local KEEP_HOURS = 400 * 24        -- forget entries older than about 13 months
local CHUNK = 230                  -- addon messages are limited to 255 bytes
local SHARE_GAP = 60               -- seconds between our broadcasts of the log
local REPLY_MAX = 60               -- most entries sent to a guildmate catching up
local MAX_OBSERVERS = 3            -- reporters remembered per entry (enough to judge trust)
local PER_SENDER_HOUR = 100        -- most entries accepted from one guildmate per hour
local REPLY_GAP = 60               -- at most one catch-up reply from us per minute
local REQUESTER_GAP = 300          -- and at most one per requester per five minutes
local TYPES = { deposit = "d", withdraw = "w", repair = "r" }
ns.LEDGER_TYPES = TYPES

local lastShared = -1000
local lastReply = -1000
local repliedTo = {}               -- [requester] = time we last answered them
local senderBudget = {}            -- [observer] = { hour = h, n = entries accepted }
local index                        -- [key] = list of entries; built once, kept up to date
local lastPruneHour
local pendingReplies = {}          -- [since] = token, while we wait to answer a catch-up request

local function now() return GetTime and GetTime() or 0 end

-- Hours since 1970 on the server clock, so every player's times line up.
function ns.Hour()
    local t = (GetServerTime and GetServerTime()) or time()
    return math.floor(t / 3600)
end

local function Ledger()
    local l = ns.db.ledger
    if not l then
        l = { list = {} }
        ns.db.ledger = l
    end
    return l
end
ns.Ledger = Ledger

local function Key(e) return e.t .. "|" .. tostring(e.n):lower() .. "|" .. e.a end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- Verified: you saw it yourself, or at least `need` different guildmates reported it.
function ns.IsVerified(e, need)
    if e.me == true then return true end
    need = need or 2
    local n = 0
    for _ in pairs(e.by or {}) do
        n = n + 1
        if n >= need then return true end
    end
    return false
end

-- Forget very old entries, and keep the history to MAX_ENTRIES. When it is full, entries only
-- one guildmate reported go first, so nobody can push out verified history with made-up entries.
local function Prune(l)
    local oldest = ns.Hour() - KEEP_HOURS
    local kept = {}
    for _, e in ipairs(l.list) do
        if e.h >= oldest then kept[#kept + 1] = e end
    end
    if #kept > MAX_ENTRIES then
        table.sort(kept, function(a, b)
            local va, vb = ns.IsVerified(a), ns.IsVerified(b)
            if va ~= vb then return va end
            return a.h > b.h
        end)
        for i = #kept, MAX_ENTRIES + 1, -1 do kept[i] = nil end
    end
    l.list = kept
    index = nil
    lastPruneHour = ns.Hour()
end

local function Index(l)
    if index then return index end
    index = {}
    l.newest = nil
    for _, e in ipairs(l.list) do
        local k = Key(e)
        index[k] = index[k] or {}
        table.insert(index[k], e)
        if not l.newest or e.h > l.newest then l.newest = e.h end
    end
    return index
end

-- Merge a batch of entries seen in the bank log by one observer.
-- obs: list of { t = "d"|"w"|"r", n = name, a = copper, h = hour }.
function ns.LedgerObserve(obs, observer, isMe)
    if not ns.db or #obs == 0 then return 0 end
    local l = Ledger()
    local idx = Index(l)
    local newest = l.newest
    table.sort(obs, function(a, b) return a.h < b.h end)
    local matched, added, overlap = {}, 0, false
    local function addObserver(e)
        e.by = e.by or {}
        if observer and not e.by[observer] and Count(e.by) < MAX_OBSERVERS then e.by[observer] = true end
        if isMe then e.me = true end
    end
    for _, o in ipairs(obs) do
        local best, bestDist
        for _, e in ipairs(idx[Key(o)] or {}) do
            local d = math.abs(e.h - o.h)
            if d <= 1 and not matched[e] and (not bestDist or d < bestDist) then best, bestDist = e, d end
        end
        if best then
            matched[best] = true
            overlap = true
            addObserver(best)
        else
            local e = { t = o.t, n = o.n, a = o.a, h = o.h }
            addObserver(e)
            l.list[#l.list + 1] = e
            local k = Key(e)
            idx[k] = idx[k] or {}
            table.insert(idx[k], e)
            matched[e] = true
            added = added + 1
            if not l.newest or e.h > l.newest then l.newest = e.h end
        end
    end
    l.since = l.since or obs[1].h
    if obs[1].h < l.since then l.since = obs[1].h end
    -- We had history, but nothing in this log overlaps it: some activity in between was missed.
    if isMe and newest and not overlap and obs[1].h > newest then l.gapAt = obs[1].h end
    if #l.list > MAX_ENTRIES or lastPruneHour ~= ns.Hour() then Prune(l) end
    if ns.RefreshBoard then ns.RefreshBoard() end
    return added
end

-- Verified totals per player (keyed by lower-case name), optionally only from a given hour on.
function ns.LedgerTotals(fromHour, need)
    local totals = {}
    if not ns.db then return totals end
    for _, e in ipairs(Ledger().list) do
        if ns.IsVerified(e, need) and (not fromHour or e.h >= fromHour) then
            local k = tostring(e.n):lower()
            local t = totals[k]
            if not t then
                t = { name = e.n, paidIn = 0, paidCount = 0, lastPaid = 0, takenOut = 0, repairs = 0 }
                totals[k] = t
            end
            if e.t == "d" then
                t.paidIn = t.paidIn + e.a
                t.paidCount = t.paidCount + 1
                t.lastPaid = math.max(t.lastPaid, e.h * 3600)
            elseif e.t == "w" then
                t.takenOut = t.takenOut + e.a
            elseif e.t == "r" then
                t.repairs = t.repairs + e.a
            end
        end
    end
    return totals
end

---------------------------------------------------------------------------
-- Sharing with guildmates
---------------------------------------------------------------------------

local function Encode(header, list)
    local msgs, parts, size = {}, {}, #header
    for _, e in ipairs(list) do
        local item = e.t .. "," .. e.a .. "," .. e.h .. "," .. tostring(e.n):gsub("[|;,]", "")
        if size + #item + 1 > CHUNK and #parts > 0 then
            msgs[#msgs + 1] = header .. table.concat(parts, ";")
            parts, size = {}, #header
        end
        parts[#parts + 1] = item
        size = size + #item + 1
    end
    if #parts > 0 then msgs[#msgs + 1] = header .. table.concat(parts, ";") end
    return msgs
end
ns.LedgerEncode = Encode

local function Decode(body)
    local list, nowH = {}, ns.Hour()
    for item in body:gmatch("[^;]+") do
        local t, a, h, n = item:match("^([dwr]),(%d+),(%d+),(.+)$")
        a, h = tonumber(a), tonumber(h)
        if t and a and h and a >= 1 and a <= 1e11 and h <= nowH + 1 and h >= nowH - KEEP_HOURS
            and #n <= 60 and not n:find("[|%c]") and ns.IsGuildMember(n) then
            list[#list + 1] = { t = t, a = a, h = h, n = n }
        end
    end
    return list
end

local function SendAll(msgs)
    for i, msg in ipairs(msgs) do
        C_Timer.After((i - 1) * 1.0, function() ns.SendGuild(msg) end)
    end
end

local function Sharing()
    return ns.db and ns.db.dest ~= "bank" and IsInGuild and IsInGuild()
end

-- After reading the bank log: tell guildmates what it showed.
function ns.ShareObservations(obs)
    if not Sharing() or #obs == 0 or now() - lastShared < SHARE_GAP then return end
    lastShared = now()
    SendAll(Encode("L|", obs))
end

-- At login: ask guildmates for anything newer than what we have.
function ns.RequestCatchUp()
    if not Sharing() then return end
    local newest = 0
    for _, e in ipairs(Ledger().list) do
        if e.h > newest then newest = e.h end
    end
    ns.SendGuild("Q|" .. newest)
end

-- At most PER_SENDER_HOUR entries per guildmate per hour; the rest are dropped.
local function Budget(observer, list)
    local h = ns.Hour()
    local b = senderBudget[observer]
    if not b or b.hour ~= h then
        b = { hour = h, n = 0 }
        senderBudget[observer] = b
    end
    local room = PER_SENDER_HOUR - b.n
    if room <= 0 then return {} end
    for i = #list, room + 1, -1 do list[i] = nil end
    b.n = b.n + #list
    return list
end

function ns.OnLedgerMessage(kind, text, observer)
    if not ns.db then return end
    if kind == "L" then
        ns.LedgerObserve(Budget(observer, Decode(text:sub(3))), observer, false)
    elseif kind == "R" then
        local since, body = text:match("^R|(%d+)|(.*)$")
        if not since then return end
        pendingReplies[since] = nil   -- someone else answered this request first
        ns.LedgerObserve(Budget(observer, Decode(body)), observer, false)
    elseif kind == "Q" then
        local since = text:match("^Q|(%d+)$")
        if not since or not Sharing() then return end
        -- Answer sparingly: once a minute at most, and once per requester per five minutes.
        if now() - lastReply < REPLY_GAP or now() - (repliedTo[observer] or -1000) < REQUESTER_GAP then return end
        -- Only what we saw ourselves, so the reply is first-hand.
        local mine = {}
        for _, e in ipairs(Ledger().list) do
            if e.me and e.h > tonumber(since) then mine[#mine + 1] = e end
        end
        if #mine == 0 then return end
        table.sort(mine, function(a, b) return a.h > b.h end)
        for i = #mine, REPLY_MAX + 1, -1 do mine[i] = nil end
        -- Wait a random moment; if another guildmate answers first, stay quiet.
        local token = {}
        pendingReplies[since] = token
        C_Timer.After(3 + (math.random and math.random() or 0.5) * 9, function()
            if pendingReplies[since] ~= token then return end
            pendingReplies[since] = nil
            lastReply = now()
            repliedTo[observer] = now()
            SendAll(Encode("R|" .. since .. "|", mine))
        end)
    end
end

---------------------------------------------------------------------------
-- Promotion helper (officers only). Nothing is ever promoted automatically:
-- the list only suggests, and an officer clicks Promote.
---------------------------------------------------------------------------

function ns.CanPromote()
    if not (IsInGuild and IsInGuild()) then return false end
    for _, fn in ipairs({ CanGuildPromote, IsGuildLeader }) do
        if fn then
            local okC, yes = pcall(fn)
            if okC and yes then return true end
        end
    end
    return false
end

-- Members whose verified deposits in the chosen window reach the chosen amount
-- (an amount of 0 means any verified deposit), and whom you are allowed to promote.
function ns.PromotionCandidates()
    local list = {}
    if not ns.db or not ns.CanPromote() then return list end
    local days = ns.db.promoDays or 30
    local fromHour = days > 0 and (ns.Hour() - days * 24) or nil
    local threshold = ns.db.promoAmount or 0
    -- Stricter than the leaderboard: seen by you, or reported by three different guildmates.
    local totals = ns.LedgerTotals(fromHour, 3)
    for _, full in ipairs(ns.roster or {}) do
        local info = ns.rosterInfo[full:lower()]
        local t = totals[full:lower()]
        if info and t and t.paidCount > 0 and t.paidIn >= threshold and not ns.IsMe(full)
            and info.rankIndex and ns.myRankIndex and info.rankIndex > ns.myRankIndex + 1
            and not (ns.promoteSent and ns.promoteSent[full:lower()]) then
            list[#list + 1] = { name = full, rankName = info.rankName, paidIn = t.paidIn, lastPaid = t.lastPaid }
        end
    end
    table.sort(list, function(a, b) return a.paidIn > b.paidIn end)
    return list
end

-- One rank up. Called only from a click on the Promote button.
function ns.Promote(name)
    local info = ns.rosterInfo[tostring(name):lower()]
    local target = info and info.raw or name
    local fn = GuildPromote or (C_GuildInfo and C_GuildInfo.Promote)
    if not fn then
        ns.Print("this client has no promote function. Promote " .. name .. " from the guild window instead.")
        return
    end
    -- Remember it until the roster refreshes, so a second click cannot promote twice.
    ns.promoteSent = ns.promoteSent or {}
    if ns.promoteSent[tostring(name):lower()] then return end
    ns.promoteSent[tostring(name):lower()] = true
    local okP, err = pcall(fn, target)
    if okP then
        ns.Print("promotion sent for " .. name .. ". The guild roster will show the new rank shortly.")
    else
        ns.promoteSent[tostring(name):lower()] = nil
        ns.Print("could not promote " .. name .. ": " .. tostring(err))
    end
    local req = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
    if req then pcall(req) end
    if ns.RefreshBoard then ns.RefreshBoard() end
end
