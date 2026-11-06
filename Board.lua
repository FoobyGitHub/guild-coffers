-- Guild Coffers: the guild leaderboard window (/coffers board), with an officer-only
-- Promotions view.
local _, ns = ...

local ROWS = 20
local ROW_H = 18
local TOP = -112           -- first row
local board
local mode = "board"       -- "board" or "promote"
local offset = 0

local LEADER_COLS = {      -- heading, x, width, justify
    { "#", 12, 26, "LEFT" },
    { "Name", 40, 128, "LEFT" },
    { "Rate", 170, 36, "RIGHT" },
    { "Reported", 210, 72, "RIGHT" },
    { "Paid in", 286, 74, "RIGHT" },
    { "Taken out", 364, 74, "RIGHT" },
    { "Ratio", 442, 40, "RIGHT" },
    { "Last gift", 494, 84, "LEFT" },
}
local PROMO_COLS = {
    { "#", 12, 26, "LEFT" },
    { "Name", 40, 140, "LEFT" },
    { "Rank", 184, 100, "LEFT" },
    { "Paid in", 288, 80, "RIGHT" },
    { "Last gift", 380, 84, "LEFT" },
}

local function Cell(parent, template, x, y, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function DateText(ts)
    if not ts or ts <= 0 then return "never" end
    return date and date("%Y-%m-%d", ts) or tostring(ts)
end

local function Money(v, verified)
    if not v or v <= 0 then return verified and "0c" or "-" end
    return ns.ShortCoin(v)
end

-- Paid in as a share of all the gold they moved: 100% = only paid in, 50% = took out as much
-- as they paid in, 0% = only took out.
local function RatioText(r)
    local paid, taken = r.paidIn or 0, r.takenOut or 0
    if paid + taken <= 0 then return "-" end
    local pct = math.floor(paid / (paid + taken) * 100 + 0.5)
    local colour = pct >= 50 and "|cff40ff40" or "|cffff6060"
    return colour .. pct .. "%|r"
end

local function SetHeadings(cols)
    for i = 1, #LEADER_COLS do
        local h, col = board.heads[i], cols[i]
        if col then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", board, "TOPLEFT", col[2], TOP + 18)
            h:SetWidth(col[3])
            h:SetJustifyH(col[4])
            h:SetText(col[1])
        else
            h:SetText("")
        end
    end
end

local function PlaceCells(cols)
    for i = 1, ROWS do
        local line = board.lines[i]
        for c = 1, #LEADER_COLS do
            local fs, col = line[c], cols[c]
            fs:ClearAllPoints()
            if col then
                fs:SetPoint("TOPLEFT", board, "TOPLEFT", col[2], TOP - (i - 1) * ROW_H)
                fs:SetWidth(col[3])
                fs:SetJustifyH(col[4])
            end
            fs:SetText("")
        end
        line.promote:Hide()
    end
end

local function FooterText(total)
    local l = ns.db and ns.db.ledger
    local parts = {}
    if total > ROWS then
        parts[#parts + 1] = string.format("Showing %d-%d of %d (scroll for more).", offset + 1,
            math.min(offset + ROWS, total), total)
    end
    if l and l.since then
        parts[#parts + 1] = "History since " .. DateText(l.since * 3600) .. "."
    end
    if l and l.gapAt then
        parts[#parts + 1] = "|cffffaa00Some bank activity before " .. DateText(l.gapAt * 3600)
            .. " may be missing.|r"
    end
    return table.concat(parts, " ")
end

local function RefreshBoardMode()
    SetHeadings(LEADER_COLS)
    PlaceCells(LEADER_COLS)
    board.note:SetText("Paid in and Taken out are verified from the guild bank log (seen by you or reported by "
        .. "two guildmates). Ratio: paid in as a share of all they moved (100% = only paid in). Reported is each "
        .. "player's own addon total. Repairs are not counted as taken out.")
    local rows = ns.BoardRows()
    offset = math.max(0, math.min(offset, #rows - ROWS))
    for i = 1, ROWS do
        local line, r = board.lines[i], rows[i + offset]
        if r then
            local last = math.max(r.last or 0, r.lastPaid or 0)
            line[1]:SetText(i + offset)
            line[2]:SetText(r.name .. (r.me and " (you)" or ""))
            line[3]:SetText(r.rate and (r.rate .. "%") or "-")
            line[4]:SetText(r.usesAddon and ns.ShortCoin(r.donated or 0) or "-")
            line[5]:SetText(r.verified and ("|cff40ff40" .. Money(r.paidIn) .. "|r") or "-")
            line[6]:SetText(Money(r.takenOut))
            line[7]:SetText(RatioText(r))
            line[8]:SetText(DateText(last))
        end
    end
    if #rows <= 1 then
        board.footer:SetText("Only you so far. Guildmates appear once the guild roster loads or they run the addon.")
    else
        board.footer:SetText(FooterText(#rows))
    end
end

local function RefreshPromoteMode()
    SetHeadings(PROMO_COLS)
    PlaceCells(PROMO_COLS)
    board.note:SetText("")
    local days = ns.db.promoDays or 30
    board.amountText:SetText((ns.db.promoAmount or 0) > 0 and ns.ShortCoin(ns.db.promoAmount) or "any")
    board.daysText:SetText(days > 0 and (days .. " days") or "all time")
    local list = ns.PromotionCandidates()
    offset = math.max(0, math.min(offset, #list - ROWS))
    for i = 1, ROWS do
        local line, r = board.lines[i], list[i + offset]
        if r then
            line[1]:SetText(i + offset)
            line[2]:SetText(r.name)
            line[3]:SetText(r.rankName or "?")
            line[4]:SetText("|cff40ff40" .. ns.ShortCoin(r.paidIn) .. "|r")
            line[5]:SetText(DateText(r.lastPaid))
            line.promote.target = r.name
            line.promote:Show()
        end
    end
    if #list == 0 then
        board.footer:SetText("Nobody is ready for promotion with these settings. Only members below you, with "
            .. "verified deposits, are listed.")
    else
        board.footer:SetText("Promote moves a member up one rank. What each rank can do is set in the guild's "
            .. "own rank and bank settings.")
    end
end

local function Refresh()
    if not board or not ns.db or not board:IsShown() then return end
    local officer = ns.CanPromote and ns.CanPromote()
    if not officer then mode = "board" end
    board.modeBtn:SetShown(officer and true or false)
    board.modeBtn:SetText(mode == "promote" and "Leaderboard" or "Promotions")
    board.title:SetText(mode == "promote" and "Guild Coffers - ready for promotion" or "Guild Coffers - leaderboard")
    for _, f in ipairs(board.promoControls) do f:SetShown(mode == "promote") end
    if mode == "promote" then RefreshPromoteMode() else RefreshBoardMode() end
end
ns.RefreshBoard = Refresh

local function Build()
    local w = CreateFrame("Frame", "GuildCoffersBoard", UIParent, "BasicFrameTemplateWithInset")
    w:SetSize(600, -TOP + ROWS * ROW_H + 50)
    w:SetPoint("CENTER")
    -- Above the game's Options window (which is what opens it from the settings panel).
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetToplevel(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildCoffersBoard")
    board = w

    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.title:SetPoint("TOP", w, "TOP", 0, -5)

    w.note = Cell(w, "GameFontHighlightSmall", 14, -32, 470, "LEFT")

    w.modeBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    w.modeBtn:SetSize(100, 22)
    w.modeBtn:SetPoint("TOPRIGHT", w, "TOPRIGHT", -12, -30)
    w.modeBtn:SetScript("OnClick", function()
        mode = (mode == "promote") and "board" or "promote"
        offset = 0
        Refresh()
    end)

    -- Promotion settings: verified deposits of at least <amount> in the last <days>.
    w.promoControls = {}
    local function Ctl(f) w.promoControls[#w.promoControls + 1] = f; return f end
    local function Btn(text, width, onClick)
        local b = Ctl(CreateFrame("Button", nil, w, "UIPanelButtonTemplate"))
        b:SetSize(width, 20)
        b:SetText(text)
        b:SetScript("OnClick", function() onClick(); Refresh() end)
        return b
    end
    Ctl(Cell(w, "GameFontHighlight", 14, -34, 190, "LEFT")):SetText("Verified deposits of at least")
    local function SetAmount(delta)
        ns.db.promoAmount = math.max(0, (ns.db.promoAmount or 0) + delta)
    end
    local a1 = Btn("-10g", 42, function() SetAmount(-100000) end)
    a1:SetPoint("TOPLEFT", w, "TOPLEFT", 206, -30)
    local a2 = Btn("-1g", 36, function() SetAmount(-10000) end)
    a2:SetPoint("LEFT", a1, "RIGHT", 2, 0)
    w.amountText = Ctl(Cell(w, "GameFontNormal", 0, 0, 70, "CENTER"))
    w.amountText:ClearAllPoints()
    w.amountText:SetPoint("LEFT", a2, "RIGHT", 4, 0)
    local a3 = Btn("+1g", 36, function() SetAmount(10000) end)
    a3:SetPoint("LEFT", w.amountText, "RIGHT", 4, 0)
    local a4 = Btn("+10g", 42, function() SetAmount(100000) end)
    a4:SetPoint("LEFT", a3, "RIGHT", 2, 0)

    Ctl(Cell(w, "GameFontHighlight", 14, -58, 190, "LEFT")):SetText("in the last")
    local function SetDays(delta)
        ns.db.promoDays = math.max(0, math.min(365, (ns.db.promoDays or 30) + delta))
    end
    local d1 = Btn("-7", 36, function() SetDays(-7) end)
    d1:SetPoint("TOPLEFT", w, "TOPLEFT", 206, -54)
    local d2 = Btn("-1", 36, function() SetDays(-1) end)
    d2:SetPoint("LEFT", d1, "RIGHT", 2, 0)
    w.daysText = Ctl(Cell(w, "GameFontNormal", 0, 0, 70, "CENTER"))
    w.daysText:ClearAllPoints()
    w.daysText:SetPoint("LEFT", d2, "RIGHT", 4, 0)
    local d3 = Btn("+1", 36, function() SetDays(1) end)
    d3:SetPoint("LEFT", w.daysText, "RIGHT", 4, 0)
    local d4 = Btn("+7", 36, function() SetDays(7) end)
    d4:SetPoint("LEFT", d3, "RIGHT", 2, 0)
    w.promoHint = Ctl(Cell(w, "GameFontHighlightSmall", 14, -78, 560, "LEFT"))
    w.promoHint:SetText("Counts deposits you saw in the bank log yourself, or that three guildmates reported. "
        .. "\"any\" = at least one; 0 days = all time.")

    w.heads = {}
    for i = 1, #LEADER_COLS do
        w.heads[i] = Cell(w, "GameFontNormalSmall", 0, 0, 10, "LEFT")
    end
    w.lines = {}
    for i = 1, ROWS do
        local line = {}
        for c = 1, #LEADER_COLS do
            line[c] = Cell(w, "GameFontHighlightSmall", 0, 0, 10, "LEFT")
        end
        local p = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        p:SetSize(80, 18)
        p:SetPoint("TOPLEFT", w, "TOPLEFT", 480, TOP - (i - 1) * ROW_H + 3)
        p:SetText("Promote")
        p:SetScript("OnClick", function(self)
            -- After a promotion the list moves up; ignore clicks for a moment so a double-click
            -- cannot promote the next member by accident.
            local t = GetTime and GetTime() or 0
            if (w.promoteLock or 0) > t then return end
            w.promoteLock = t + 1.5
            if self.target then ns.Promote(self.target) end
        end)
        p:Hide()
        line.promote = p
        w.lines[i] = line
    end
    w.footer = Cell(w, "GameFontHighlightSmall", 14, TOP - ROWS * ROW_H - 6, 570, "LEFT")

    w:EnableMouseWheel(true)
    w:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        Refresh()
    end)
    w:SetScript("OnShow", function(self)
        if self.Raise then self:Raise() end
        local req = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
        if req and IsInGuild and IsInGuild() then pcall(req) end
        if ns.QueryBankLog and ns.IsGuildBankOpen and ns.IsGuildBankOpen() then ns.QueryBankLog() end
        Refresh()
    end)
    return w
end

function ns.ToggleBoard()
    if not ns.db then return end
    if not board then
        local ok, result = pcall(Build)
        if not ok then
            board = nil
            ns.Print("the leaderboard window could not be built: " .. tostring(result))
            return
        end
        board:Show()
        Refresh()
        return
    end
    if board:IsShown() then board:Hide() else board:Show(); Refresh() end
end

-- For tests and /coffers promote.
function ns.ShowPromotions()
    if not board or not board:IsShown() then ns.ToggleBoard() end
    if board and ns.CanPromote() then
        mode = "promote"
        offset = 0
        Refresh()
    end
end
