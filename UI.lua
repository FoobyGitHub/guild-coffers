-- Guild Coffers: interface.
--  * a panel in the game's AddOns settings (with fallbacks if that API differs on this client)
--  * an always-visible counter showing how much gold to keep aside
--  * a standalone window (/coffers window) as a safety net
-- Every piece is built inside pcall so one failing template cannot stop the others,
-- and the slash commands always work.
local _, ns = ...

local panels = {}   -- every built settings panel, so one refresh updates them all
ns.panels = panels
local category, legacyPanel, window, hud
local reported = {}

local function Report(where, err)
    if reported[where] then return end
    reported[where] = true
    ns.Print("part of the interface failed (" .. where .. "): " .. tostring(err)
        .. " - please report it with the output of /coffers debug.")
end

local function Safe(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Report(where, err) end
    return ok
end

local function Label(parent, template, point, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint(point, parent, point, x, y)
    if text then fs:SetText(text) end
    return fs
end

-- Hover text for a frame.
local function Tip(frame, title, text)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local RESERVE_TIP = "A deposit never takes you below this amount. Anything held back stays owed "
    .. "and is deposited later.\n\nThe buttons change it in steps. For an exact amount, type "
    .. "/coffers reserve 5g 50s 20c in chat (g = gold, s = silver, c = copper; a plain number is gold)."

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function RefreshHUD()
    if not hud or not ns.db then return end
    if not ns.db.showHud then
        hud:Hide()
        return
    end
    local c = ns.Char()
    if ns.db.enabled then
        hud.line1:SetText((ns.db.dest == "bank" and "Savings to keep: " or "Guild tax to keep: ")
            .. "|cffffd100" .. ns.OwedText(c.owed) .. "|r")
        hud.line2:SetText(ns.CoinText(c.collected or 0) .. " collected at " .. ns.db.rate .. "%")
    else
        hud.line1:SetText("Guild tax: tracking off")
        hud.line2:SetText("type /coffers to turn it on")
    end
    local w = math.max(tonumber(hud.line1:GetStringWidth()) or 0,
        tonumber(hud.line2:GetStringWidth()) or 0)
    hud:SetWidth(math.max(170, w + 16))
    hud:Show()
end

local function RefreshPanel(p)
    local c = ns.Char()
    Safe("rate text", function() p.rateText:SetText(ns.db.rate .. "%") end)
    Safe("share box", function()
        -- Saving to your own bank is private, so sharing cannot apply: grey it out.
        local own = ns.db.dest == "bank"
        p.share:SetChecked((ns.db.share and not own) and true or false)
        if own then
            p.share:Disable()
            p.share.label:SetTextColor(0.5, 0.5, 0.5)
        else
            p.share:Enable()
            p.share.label:SetTextColor(1, 1, 1)
        end
    end)
    Safe("destination", function()
        local own = ns.db.dest == "bank"
        if p.destDropdown and p.destDropdown.GenerateMenu then p.destDropdown:GenerateMenu() end
        if p.destGuild then
            p.destGuild:SetChecked(not own)
            p.destBank:SetChecked(own)
        end
    end)
    Safe("chat box", function() p.chat:SetChecked(ns.db.showChat and true or false) end)
    Safe("tracking box", function() p.enabled:SetChecked(ns.db.enabled and true or false) end)
    Safe("counter box", function() p.showHud:SetChecked(ns.db.showHud and true or false) end)
    Safe("lock box", function() p.lock:SetChecked(ns.db.hudLocked and true or false) end)
    Safe("reserve text", function() p.reserveText:SetText(ns.ReserveText(ns.db.reserve)) end)
    Safe("status text", function()
        p.owed:SetText("Keep aside now: " .. ns.OwedText(c.owed))
        p.collected:SetText("Collected since last deposit: " .. ns.CoinText(c.collected or 0))
        p.donated:SetText("Total donated: " .. ns.CoinText(c.donated)
            .. ((c.saved or 0) > 0 and ("  (saved to own bank: " .. ns.CoinText(c.saved) .. ")") or ""))
        local last = "never"
        if c.lastDonated and date then last = date("%Y-%m-%d %H:%M", c.lastDonated) end
        p.last:SetText("Last donation: " .. last)
    end)
end

local function RefreshPanels()
    if not ns.db then return end
    for _, p in ipairs(panels) do RefreshPanel(p) end
end

function ns.RefreshUI()
    Safe("counter", RefreshHUD)
    RefreshPanels()
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------

local function Check(parent, y, text, onClick, x)
    x = x or 14
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    cb.label = Label(parent, "GameFontHighlight", "TOPLEFT", x + 30, y - 7, text)
    return cb
end

local function BuildPanel(parent)
    local p = CreateFrame("Frame", nil, parent)

    Label(p, "GameFontNormalLarge", "TOPLEFT", 16, -16, "Guild Coffers")
    local sub = Label(p, "GameFontHighlightSmall", "TOPLEFT", 16, -42,
        "A share of the gold you receive is set aside and donated to the guild bank when you open it.")
    sub:SetWidth(440)
    sub:SetJustifyH("LEFT")

    p.enabled = Check(p, -72, "Track gold and tax it", function(v)
        ns.db.enabled = v
        ns.RefreshUI()
    end)
    p.showHud = Check(p, -100, "Show the tax counter on screen", function(v)
        ns.db.showHud = v
        ns.RefreshUI()
    end)
    p.lock = Check(p, -128, "Lock the counter's position", function(v)
        ns.db.hudLocked = v
    end)
    p.chat = Check(p, -156, "Show tax in chat", function(v)
        ns.db.showChat = v
    end)

    -- Where the tax goes: a dropdown with both choices, so exactly one is selected.
    -- If this client cannot build the dropdown, two linked options are used instead.
    local function SetDest(dest)
        ns.db.dest = dest
        if dest == "guild" and ns.ScheduleShare then ns.ScheduleShare() end
        ns.RefreshUI()
    end
    local GUILD_TIP = "Your tax is deposited into the guild bank when you open it, and counts as a guild "
        .. "donation on the leaderboard."
    local BANK_TIP = "Your tax is saved into your own bank (the Warband bank) when you open it, for players "
        .. "without a guild or who prefer to save it. It is private: not a guild donation, and nothing is "
        .. "shared. Also: /coffers dest guild or bank."
    Label(p, "GameFontNormalSmall", "TOPLEFT", 292, -68, "Deposit to")
    local shareY
    local builtDropdown = pcall(function()
        local dd = CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate")
        if not dd.SetupMenu then
            dd:Hide()
            error("no SetupMenu")
        end
        dd:SetPoint("TOPLEFT", 290, -84)
        dd:SetWidth(210)
        dd:SetupMenu(function(_, root)
            root:CreateRadio("The guild bank", function() return ns.db.dest ~= "bank" end,
                function() SetDest("guild") end)
            root:CreateRadio("My own bank (private)", function() return ns.db.dest == "bank" end,
                function() SetDest("bank") end)
        end)
        -- Hover help (hooked, so the dropdown keeps its own highlight behaviour).
        pcall(function()
            dd:HookScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Deposit to")
                GameTooltip:AddLine("The guild bank: " .. GUILD_TIP, 1, 1, 1, true)
                GameTooltip:AddLine("My own bank: " .. BANK_TIP, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            dd:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end)
        p.destDropdown = dd
    end)
    if builtDropdown then
        shareY = -118
    else
        p.destGuild = Check(p, -84, "Deposit to the guild bank", function() SetDest("guild") end, 290)
        Tip(p.destGuild, "Deposit to the guild bank", GUILD_TIP)
        p.destBank = Check(p, -112, "Deposit to my own bank", function() SetDest("bank") end, 290)
        Tip(p.destBank, "Deposit to my own bank", BANK_TIP)
        shareY = -140
    end

    p.share = Check(p, shareY, "Share my donations", function(v)
        ns.db.share = v
        if v and ns.ScheduleShare then ns.ScheduleShare() end
    end, 290)
    Tip(p.share, "Share my donations", "Lets guildmates see your rate and what you have donated on the leaderboard. "
        .. "Only applies when depositing to the guild bank.")

    -- The rate is shown as plain text (like the status lines below) and changed with
    -- buttons or /coffers rate <0-100>, rather than with a typed-in box.
    Label(p, "GameFontHighlight", "TOPLEFT", 20, -198, "Tax rate")
    local function RateButton(text, width, delta)
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(text)
        b:SetScript("OnClick", function() ns.SetRate((ns.db.rate or 0) + delta) end)
        return b
    end
    p.minus5 = RateButton("-5", 32, -5)
    p.minus5:SetPoint("TOPLEFT", 130, -194)
    p.minus = RateButton("-", 24, -1)
    p.minus:SetPoint("LEFT", p.minus5, "RIGHT", 4, 0)
    p.rateText = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.rateText:SetPoint("LEFT", p.minus, "RIGHT", 6, 0)
    p.rateText:SetWidth(56)
    p.rateText:SetJustifyH("CENTER")
    p.plus = RateButton("+", 24, 1)
    p.plus:SetPoint("LEFT", p.rateText, "RIGHT", 6, 0)
    p.plus5 = RateButton("+5", 32, 5)
    p.plus5:SetPoint("LEFT", p.plus, "RIGHT", 4, 0)

    -- Minimum to keep: a deposit never takes you below this. Buttons for quick changes;
    -- /coffers reserve 5g 50s sets an exact amount.
    Label(p, "GameFontHighlight", "TOPLEFT", 20, -234, "Always keep")
    local labelHit = CreateFrame("Frame", nil, p)
    labelHit:SetSize(100, 22)
    labelHit:SetPoint("TOPLEFT", 16, -230)
    Tip(labelHit, "Always keep", RESERVE_TIP)
    p.reserveHit = labelHit
    local function ReserveButton(text, delta)
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(42, 22)
        b:SetText(text)
        b:SetScript("OnClick", function() ns.SetReserve((ns.db.reserve or 0) + delta) end)
        Tip(b, "Always keep", RESERVE_TIP)
        return b
    end
    local r1 = ReserveButton("-100g", -1000000)
    r1:SetPoint("TOPLEFT", 130, -230)
    local r2 = ReserveButton("-10g", -100000)
    r2:SetPoint("LEFT", r1, "RIGHT", 2, 0)
    local r3 = ReserveButton("-1g", -10000)
    r3:SetPoint("LEFT", r2, "RIGHT", 2, 0)
    p.reserveText = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.reserveText:SetPoint("LEFT", r3, "RIGHT", 6, 0)
    p.reserveText:SetWidth(90)
    p.reserveText:SetJustifyH("CENTER")
    local valueHit = CreateFrame("Frame", nil, p)
    valueHit:SetSize(90, 22)
    valueHit:SetPoint("LEFT", r3, "RIGHT", 6, 0)
    Tip(valueHit, "Always keep", RESERVE_TIP)
    local r4 = ReserveButton("+1g", 10000)
    r4:SetPoint("LEFT", p.reserveText, "RIGHT", 6, 0)
    local r5 = ReserveButton("+10g", 100000)
    r5:SetPoint("LEFT", r4, "RIGHT", 2, 0)
    local r6 = ReserveButton("+100g", 1000000)
    r6:SetPoint("LEFT", r5, "RIGHT", 2, 0)
    local hint = Label(p, "GameFontHighlightSmall", "TOPLEFT", 130, -256,
        "Hover for help. Exact amount: /coffers reserve 5g 50s")
    hint:SetTextColor(0.7, 0.7, 0.7)

    p.owed = Label(p, "GameFontHighlight", "TOPLEFT", 20, -284)
    p.collected = Label(p, "GameFontHighlight", "TOPLEFT", 20, -306)
    p.donated = Label(p, "GameFontHighlight", "TOPLEFT", 20, -328)
    p.last = Label(p, "GameFontHighlight", "TOPLEFT", 20, -350)

    local deposit = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    deposit:SetSize(120, 24)
    deposit:SetPoint("TOPLEFT", 20, -384)
    deposit:SetText("Deposit now")
    deposit:SetScript("OnClick", function() ns.TryDeposit(true) end)

    -- Reset needs a second click within a few seconds, so it cannot be hit by accident.
    local reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    reset:SetSize(150, 24)
    reset:SetPoint("LEFT", deposit, "RIGHT", 10, 0)
    reset:SetText("Reset amount owed")
    local armed
    reset:SetScript("OnClick", function()
        if armed then
            armed = nil
            reset:SetText("Reset amount owed")
            ns.ResetOwed()
            return
        end
        local token = {}
        armed = token
        reset:SetText("Click again to confirm")
        C_Timer.After(5, function()
            if armed == token then
                armed = nil
                reset:SetText("Reset amount owed")
            end
        end)
    end)
    p.reset = reset

    local boardBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    boardBtn:SetSize(110, 24)
    boardBtn:SetPoint("LEFT", reset, "RIGHT", 10, 0)
    boardBtn:SetText("Leaderboard")
    boardBtn:SetScript("OnClick", function() if ns.ToggleBoard then ns.ToggleBoard() end end)
    Tip(boardBtn, "Leaderboard", "Who in the guild is using Guild Coffers, their rate and what they have donated. "
        .. "Players whose deposits show in the guild bank log are marked Verified.")
    p.boardBtn = boardBtn

    p.version = Label(p, "GameFontHighlightSmall", "TOPLEFT", 20, -418, "Version " .. ns.GetVersion())

    -- Refresh whenever the panel is shown, so nothing depends on when it was built.
    p:SetScript("OnShow", function() RefreshPanel(p) end)

    return p
end

local function RegisterPanel()
    local ok, p = pcall(BuildPanel, UIParent)
    if not ok then
        Report("settings panel", p)
        return
    end
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok2, cat = pcall(Settings.RegisterCanvasLayoutCategory, p, "Guild Coffers")
        if ok2 and cat then
            pcall(Settings.RegisterAddOnCategory, cat)
            category = cat
            panels[#panels + 1] = p
            ns.menuMode = "settings"
            return
        end
    end
    if InterfaceOptions_AddCategory then
        p.name = "Guild Coffers"
        if pcall(InterfaceOptions_AddCategory, p) then
            legacyPanel = p
            panels[#panels + 1] = p
            ns.menuMode = "legacy"
        end
    end
end

---------------------------------------------------------------------------
-- Standalone window (safety net: /coffers window, or when no settings menu is found)
---------------------------------------------------------------------------

local function BuildWindow()
    local w = CreateFrame("Frame", "GuildCoffersWindow", UIParent, "BasicFrameTemplateWithInset")
    w:SetSize(520, 450)
    w:SetPoint("CENTER")
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildCoffersWindow")
    local p = BuildPanel(w)
    p:SetPoint("TOPLEFT", w, "TOPLEFT", 6, -26)
    p:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -6, 6)
    panels[#panels + 1] = p
    return w
end

function ns.ShowWindow()
    if not window then
        local ok, result = pcall(BuildWindow)
        if not ok then
            Report("window", result)
            ns.Print("the window could not be built. The text commands still work: /coffers help")
            return
        end
        window = result
        window:Show()
        RefreshPanels()
        return
    end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        RefreshPanels()
    end
end

-- Open the settings entry if there is one, otherwise the standalone window.
function ns.ToggleUI()
    if category and Settings and Settings.OpenToCategory then
        local id = (category.GetID and category:GetID()) or category.ID
        if pcall(Settings.OpenToCategory, id) then return end
    elseif legacyPanel and InterfaceOptionsFrame_OpenToCategory then
        -- the old interface options frame needs this called twice to land on the right page
        pcall(InterfaceOptionsFrame_OpenToCategory, legacyPanel)
        pcall(InterfaceOptionsFrame_OpenToCategory, legacyPanel)
        return
    end
    ns.ShowWindow()
end

---------------------------------------------------------------------------
-- On-screen counter
---------------------------------------------------------------------------

local function BuildHUD()
    hud = CreateFrame("Frame", "GuildCoffersHUD", UIParent)
    ns.hud = hud
    hud:SetSize(190, 40)
    hud:SetFrameStrata("MEDIUM")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")

    local bg = hud:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    pcall(bg.SetColorTexture, bg, 0, 0, 0, 0.55)

    hud.line1 = Label(hud, "GameFontNormal", "TOPLEFT", 8, -6)
    hud.line2 = Label(hud, "GameFontHighlightSmall", "TOPLEFT", 8, -23)

    local pos = ns.db.hudPos
    hud:ClearAllPoints()
    if pos then
        hud:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        hud:SetPoint("TOP", UIParent, "TOP", 0, -90)
    end

    hud:SetScript("OnDragStart", function(self)
        if not ns.db.hudLocked then self:StartMoving() end
    end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if point then ns.db.hudPos = { point, relPoint, x, y } end
    end)
    hud:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns.ToggleUI() end
    end)
    hud:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Guild Coffers")
        GameTooltip:AddLine("Right-click: open settings", 1, 1, 1)
        GameTooltip:AddLine("Drag to move (unless locked)", 1, 1, 1)
        GameTooltip:Show()
    end)
    hud:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

ns.On("PLAYER_LOGIN", function()
    Safe("settings panel", RegisterPanel)
    Safe("counter", BuildHUD)
    ns.RefreshUI()
end)
