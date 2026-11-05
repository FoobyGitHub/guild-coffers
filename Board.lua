-- Guild Coffers: the guild leaderboard window (/coffers board).
local _, ns = ...

local ROWS = 20
local board

local function Cell(parent, template, x, y, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local COLS = {   -- x, width, justify
    { 14, 28, "LEFT" },      -- rank
    { 44, 130, "LEFT" },     -- name
    { 176, 44, "RIGHT" },    -- rate
    { 228, 90, "RIGHT" },    -- donated
    { 330, 84, "LEFT" },     -- last donation
    { 420, 118, "LEFT" },    -- status
}

local function DateText(ts)
    if not ts or ts <= 0 then return "never" end
    return date and date("%Y-%m-%d", ts) or tostring(ts)
end

local function StatusText(r)
    if r.verified then
        return "|cff40ff40Verified|r " .. ns.CoinText(r.bankTotal or 0)
    end
    if (r.donated or 0) > 0 then return "|cffaaaaaaUnverified|r" end
    return "|cff888888None yet|r"
end

local function Refresh()
    if not board or not ns.db then return end
    local rows = ns.BoardRows()
    for i = 1, ROWS do
        local line, r = board.lines[i], rows[i]
        if r then
            local name = r.name .. (r.me and " (you)" or "")
            local last = math.max(r.last or 0, r.bankLast or 0)
            line[1]:SetText(i)
            line[2]:SetText(name)
            line[3]:SetText(r.rate and (r.rate .. "%") or "-")
            line[4]:SetText(r.usesAddon and ns.CoinText(r.donated or 0) or "-")
            line[5]:SetText(DateText(last))
            line[6]:SetText(StatusText(r))
        else
            for c = 1, #COLS do line[c]:SetText("") end
        end
    end
    local extra = #rows - ROWS
    board.more:SetText(extra > 0 and ("+" .. extra .. " more not shown") or
        (#rows <= 1 and "Only you so far. Guildmates appear here once they run the addon." or ""))
end
ns.RefreshBoard = Refresh

local function Build()
    local w = CreateFrame("Frame", "GuildCoffersBoard", UIParent, "BasicFrameTemplateWithInset")
    w:SetSize(560, 88 + ROWS * 18 + 44)
    w:SetPoint("CENTER")
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildCoffersBoard")

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", w, "TOP", 0, -5)
    title:SetText("Guild Coffers - leaderboard")

    local note = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -32)
    note:SetWidth(530)
    note:SetJustifyH("LEFT")
    note:SetText("Totals are reported by each player's own addon. Verified means the guild bank log "
        .. "shows a deposit by them (the amount is what the log currently holds).")

    local heads = { "#", "Name", "Rate", "Donated", "Last gift", "Bank log" }
    for c, h in ipairs(heads) do
        local fs = Cell(w, "GameFontNormalSmall", COLS[c][1], -66, COLS[c][2], COLS[c][3])
        fs:SetText(h)
    end

    w.lines = {}
    for i = 1, ROWS do
        local line = {}
        for c, col in ipairs(COLS) do
            line[c] = Cell(w, "GameFontHighlightSmall", col[1], -84 - (i - 1) * 18, col[2], col[3])
        end
        w.lines[i] = line
    end
    w.more = Cell(w, "GameFontHighlightSmall", 14, -84 - ROWS * 18 - 6, 530, "LEFT")

    w:SetScript("OnShow", function()
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
            ns.Print("the leaderboard window could not be built: " .. tostring(result))
            return
        end
        board = result
        board:Show()
        Refresh()
        return
    end
    if board:IsShown() then board:Hide() else board:Show(); Refresh() end
end
