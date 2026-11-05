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
        hud.line1:SetText("Guild tax to keep: |cffffd100" .. ns.OwedText(c.owed) .. "|r")
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
    Safe("rate box", function()
        -- Don't overwrite the box while the player is typing in it.
        if not p.rateBox.typing then p.rateBox:SetText(tostring(ns.db.rate)) end
    end)
    Safe("chat box", function() p.chat:SetChecked(ns.db.showChat and true or false) end)
    Safe("tracking box", function() p.enabled:SetChecked(ns.db.enabled and true or false) end)
    Safe("counter box", function() p.showHud:SetChecked(ns.db.showHud and true or false) end)
    Safe("lock box", function() p.lock:SetChecked(ns.db.hudLocked and true or false) end)
    Safe("status text", function()
        p.owed:SetText("Keep aside now: " .. ns.OwedText(c.owed))
        p.collected:SetText("Collected since last deposit: " .. ns.CoinText(c.collected or 0))
        p.donated:SetText("Total donated: " .. ns.CoinText(c.donated))
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

local function Check(parent, y, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 14, y)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    Label(parent, "GameFontHighlight", "TOPLEFT", 44, y - 7, text)
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
    p.chat = Check(p, -156, "Also show a chat line with each gain", function(v)
        ns.db.showChat = v
    end)

    Label(p, "GameFontHighlight", "TOPLEFT", 20, -198, "Tax rate (%)")
    p.rateBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    p.rateBox.typing = false
    p.rateBox:SetSize(40, 20)
    p.rateBox:SetPoint("TOPLEFT", 130, -194)
    p.rateBox:SetAutoFocus(false)
    p.rateBox:SetNumeric(true)
    p.rateBox:SetMaxLetters(3)
    local function ApplyRate()
        if not ns.SetRate(p.rateBox:GetText()) then
            p.rateBox:SetText(tostring(ns.db.rate))
        end
    end
    p.rateBox:SetScript("OnEnterPressed", function(self) ApplyRate() self:ClearFocus() end)
    p.rateBox:SetScript("OnEditFocusGained", function(self) self.typing = true end)
    p.rateBox:SetScript("OnEditFocusLost", function(self)
        self.typing = false
        ApplyRate()
    end)

    local minus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("LEFT", p.rateBox, "RIGHT", 8, 0)
    minus:SetText("-")
    minus:SetScript("OnClick", function() ns.SetRate((ns.db.rate or 0) - 1) end)

    local plus = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    plus:SetSize(24, 22)
    plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function() ns.SetRate((ns.db.rate or 0) + 1) end)

    p.owed = Label(p, "GameFontHighlight", "TOPLEFT", 20, -234)
    p.collected = Label(p, "GameFontHighlight", "TOPLEFT", 20, -256)
    p.donated = Label(p, "GameFontHighlight", "TOPLEFT", 20, -278)
    p.last = Label(p, "GameFontHighlight", "TOPLEFT", 20, -300)

    local deposit = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    deposit:SetSize(120, 24)
    deposit:SetPoint("TOPLEFT", 20, -334)
    deposit:SetText("Deposit now")
    deposit:SetScript("OnClick", function() ns.TryDeposit(true) end)

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
    w:SetSize(520, 390)
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
