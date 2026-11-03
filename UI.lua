-- Guild Coffers: settings window. Built on first use so a template problem on a
-- new client cannot stop the addon loading; the slash commands always work.
local _, ns = ...

local frame

local function Label(parent, template, point, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint(point, parent, point, x, y)
    if text then fs:SetText(text) end
    return fs
end

local function Refresh()
    if not frame or not frame:IsShown() or not ns.db then return end
    local c = ns.Char()
    frame.rateBox:SetText(tostring(ns.db.rate))
    frame.enabled:SetChecked(ns.db.enabled)
    frame.owed:SetText("Owed now: " .. ns.CoinText(c.owed))
    frame.donated:SetText("Total donated: " .. ns.CoinText(c.donated))
    local last = "never"
    if c.lastDonated and date then last = date("%Y-%m-%d %H:%M", c.lastDonated) end
    frame.last:SetText("Last donation: " .. last)
end
ns.RefreshUI = Refresh

local function ApplyRateBox()
    if ns.SetRate(frame.rateBox:GetText()) then
        Refresh()
    else
        frame.rateBox:SetText(tostring(ns.db.rate))
    end
end

local function Build()
    frame = CreateFrame("Frame", "GuildCoffersFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 230)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", Refresh)
    tinsert(UISpecialFrames, "GuildCoffersFrame")

    Label(frame, "GameFontNormal", "TOP", 0, -6, "Guild Coffers")

    frame.enabled = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.enabled:SetPoint("TOPLEFT", 16, -34)
    frame.enabled:SetScript("OnClick", function(self)
        ns.db.enabled = self:GetChecked() and true or false
    end)
    Label(frame, "GameFontHighlight", "TOPLEFT", 46, -41, "Track gold and tax it")

    Label(frame, "GameFontHighlight", "TOPLEFT", 20, -76, "Tax rate (%)")

    frame.rateBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.rateBox:SetSize(40, 20)
    frame.rateBox:SetPoint("TOPLEFT", 130, -72)
    frame.rateBox:SetAutoFocus(false)
    frame.rateBox:SetNumeric(true)
    frame.rateBox:SetMaxLetters(3)
    frame.rateBox:SetScript("OnEnterPressed", function(self) ApplyRateBox() self:ClearFocus() end)
    frame.rateBox:SetScript("OnEditFocusLost", ApplyRateBox)

    local minus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("LEFT", frame.rateBox, "RIGHT", 8, 0)
    minus:SetText("-")
    minus:SetScript("OnClick", function() ns.SetRate((ns.db.rate or 0) - 1) end)

    local plus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    plus:SetSize(24, 22)
    plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function() ns.SetRate((ns.db.rate or 0) + 1) end)

    frame.owed = Label(frame, "GameFontHighlight", "TOPLEFT", 20, -112)
    frame.donated = Label(frame, "GameFontHighlight", "TOPLEFT", 20, -134)
    frame.last = Label(frame, "GameFontHighlight", "TOPLEFT", 20, -156)

    local deposit = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deposit:SetSize(120, 24)
    deposit:SetPoint("BOTTOM", 0, 14)
    deposit:SetText("Deposit now")
    deposit:SetScript("OnClick", function() ns.TryDeposit(true) end)
end

function ns.ToggleUI()
    if not frame then
        local ok, err = pcall(Build)
        if not ok then
            frame = nil
            ns.Print("could not build the window (" .. tostring(err) .. "). Use /coffers help for the text commands.")
            return
        end
        frame:Show()
        return
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
