-- CrateScribe: UI.lua
-- The ranking window: one row per crate, cheapest copper-per-Favor first.

local addonName, ns = ...

local ROW_H = 18
local COLS = {
	{ key = "crate", title = "Crate", width = 180, justify = "LEFT" },
	{ key = "bundle", title = "Best bundle", width = 200, justify = "LEFT" },
	{ key = "fill", title = "Fill", width = 62, justify = "RIGHT" },
	{ key = "cratecost", title = "Crate", width = 62, justify = "RIGHT" },
	{ key = "money", title = "Pays", width = 52, justify = "RIGHT" },
	{ key = "favor", title = "Favor", width = 44, justify = "RIGHT" },
	{ key = "per", title = "Cost/Favor", width = 84, justify = "RIGHT" },
}
local WIDTH = 24
for _, c in ipairs(COLS) do
	WIDTH = WIDTH + c.width
end

local frame, rows, scrollChild, statusText, stackButton
local ticker

local function Grey(s)
	return "|cff888888" .. s .. "|r"
end

local function Money(v)
	return v and ns.FormatMoney(v) or Grey("?")
end

local function RowTooltip(row)
	local r = row.result
	if not r then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local id = ns.CrateID(r.crate)
	GameTooltip:AddLine("Waylaid Crate: " .. r.crate.name, 1, 1, 1)
	GameTooltip:AddLine(("%s, level %d, %s Favor%s"):format(r.crate.tier, ns.TIER_LEVEL[r.crate.tier],
		r.favor, r.favorConfirmed and "" or " (estimate)"), 0.7, 0.7, 0.7)
	if r.crateCost then
		GameTooltip:AddDoubleLine("Crate on AH" .. (r.crateOld and " (over 3 days old)" or ""), ns.FormatMoney(r.crateCost), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddLine("Counted in Cost/Favor: you pay it to buy one, or give it up by not selling one you own.", 0.7, 0.7, 0.7, true)
	elseif not id then
		GameTooltip:AddLine("Crate item ID not found yet -- hover one or search the AH for it.", 1, 0.5, 0.5, true)
	else
		GameTooltip:AddLine("No AH price for the crate yet.", 1, 0.5, 0.5)
	end
	if r.money and r.money > 0 then
		GameTooltip:AddDoubleLine("Turn-in pays", ns.FormatMoney(r.money), 1, 1, 1, 0.25, 1, 0.25)
		GameTooltip:AddLine("Taken off the cost in Cost/Favor (learned from your last turn-in).", 0.7, 0.7, 0.7, true)
	else
		GameTooltip:AddLine("Turn-in money not learned yet: it's learned the first time you turn this crate in.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Bundles (pick one):", 1, 0.82, 0)
	for _, b in ipairs(r.bundles) do
		local left = ("%dx %s"):format(b.qty, b.name)
		if b.stackBug then
			left = left .. " |cffff8040(>1 stack: bugged on beta)|r"
		end
		local right
		if b.cost then
			right = ("%s  (%s ea, %s)"):format(ns.FormatMoney(b.cost), ns.FormatMoney(b.unit), b.source or "?")
		else
			right = Grey("no price")
		end
		local isBest = r.best == b
		GameTooltip:AddDoubleLine(left, right, isBest and 0.25 or 1, 1, isBest and 0.25 or 1, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function CreateRow(i)
	local row = CreateFrame("Button", nil, scrollChild)
	row:SetSize(WIDTH - 24, ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
	row.bg = bg
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.8, 0.3, 0.12)

	row.cells = {}
	local x = 4
	for _, c in ipairs(COLS) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", x, 0)
		fs:SetWidth(c.width - 6)
		fs:SetJustifyH(c.justify)
		fs:SetWordWrap(false)
		row.cells[c.key] = fs
		x = x + c.width
	end
	-- bundle column: item icon, then the label shifted right of it
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.icon:SetPoint("LEFT", row, "LEFT", 4 + COLS[1].width, 0)
	row.cells.bundle:ClearAllPoints()
	row.cells.bundle:SetPoint("LEFT", row, "LEFT", 4 + COLS[1].width + 18, 0)
	row.cells.bundle:SetWidth(COLS[2].width - 24)

	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

function ns.Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local db = ns.DB()
	local results = ns.EvaluateAll()
	local level = UnitLevel("player") or 1
	local rank = 0

	for i, r in ipairs(results) do
		local row = rows[i] or CreateRow(i)
		rows[i] = row
		row.result = r

		local ownedCount = ns.Owned[r.crate.name]
		local name = r.crate.name
		if ownedCount then
			name = name .. (" |cff40c0ff(%d)|r"):format(ownedCount)
		end
		if level < ns.TIER_LEVEL[r.crate.tier] then
			name = Grey(r.crate.name .. " (" .. ns.TIER_LEVEL[r.crate.tier] .. ")")
		end
		local ranked = r.perFavor ~= nil and r.crateKnown
		if ranked then
			rank = rank + 1
			if rank <= 3 then
				name = ("|cff40ff40%d.|r %s"):format(rank, name)
			end
		end
		row.cells.crate:SetText(name)

		if r.best then
			local tex = C_Item.GetItemIconByID(r.best.itemID)
			row.icon:SetTexture(tex)
			row.icon:Show()
			local label = ("%dx %s"):format(r.best.qty, r.best.name)
			if r.best.source == "craft" then
				label = label .. Grey(" (craft)")
			end
			if r.best.stackBug then
				label = label .. " |cffff8040!|r"
			end
			row.cells.bundle:SetText(label)
		else
			row.icon:Hide()
			row.cells.bundle:SetText(Grey("no prices"))
		end

		local tilde = r.complete and "" or Grey("~")
		row.cells.fill:SetText(r.best and (Money(r.best.cost) .. tilde) or Grey("?"))
		local crateText = Money(r.crateCost)
		if r.crateCost and r.crateOld then crateText = Grey(ns.FormatMoney(r.crateCost) .. "*") end
		row.cells.cratecost:SetText(crateText)
		row.cells.money:SetText(r.money and r.money > 0 and ("|cff40ff40" .. ns.FormatMoney(r.money) .. "|r") or Grey("?"))
		row.cells.favor:SetText(r.favor .. (r.favorConfirmed and "" or Grey("?")))
		local per = Grey("?")
		if r.perFavor and r.crateKnown then
			per = "|cffffd100" .. ns.FormatMoney(r.perFavor) .. "|r" .. tilde
		elseif r.perFavor then
			per = Grey(ns.FormatMoney(r.perFavor) .. " + crate") .. tilde
		end
		row.cells.per:SetText(per)
		row:Show()
	end
	for i = #results + 1, #rows do
		rows[i]:Hide()
	end
	scrollChild:SetHeight(#results * ROW_H)

	stackButton:SetText(db.skipStackBug and "Skip >1-stack: on" or "Skip >1-stack: off")
	local msNote = _G.MarketScribeAPI and "" or "  |cffff8040(MarketScribe API not found -- reading saved prices only)|r"
	statusText:SetText(Grey("~ = some bundles unpriced   ? = estimate/not learned yet   * = crate price over 3 days old   (n) = in bags   ! = needs >1 stack") .. msNote)
end

local function Build()
	frame = CreateFrame("Frame", "CrateScribeFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WIDTH + 16, 520)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "CrateScribeFrame")

	local title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not frame.TitleText then
		title:SetPoint("TOP", 0, -5)
	end
	title:SetText("CrateScribe -- copper per Merchant's Favor")

	-- header
	local x = 14
	for _, c in ipairs(COLS) do
		local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", x, -34)
		h:SetWidth(c.width - 6)
		h:SetJustifyH(c.justify)
		h:SetText(c.title)
		x = x + c.width
	end

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -50)
	scroll:SetPoint("BOTTOMRIGHT", -30, 58)
	scrollChild = CreateFrame("Frame", nil, scroll)
	scrollChild:SetSize(WIDTH - 24, 1)
	scroll:SetScrollChild(scrollChild)
	rows = {}

	stackButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	stackButton:SetSize(140, 22)
	stackButton:SetPoint("BOTTOMLEFT", 12, 30)
	stackButton:SetScript("OnClick", function()
		local db = ns.DB()
		db.skipStackBug = not db.skipStackBug
		ns.Refresh()
	end)
	stackButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Bundles bigger than one stack", 1, 1, 1)
		GameTooltip:AddLine("On the beta, a bundle needing more than one stack (e.g. 40 Linen Cloth) can't be used to fill the crate. Turn this on to ignore those bundles until Blizzard fixes it.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	stackButton:SetScript("OnLeave", GameTooltip_Hide)

	local scanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scanButton:SetSize(110, 22)
	scanButton:SetPoint("BOTTOMRIGHT", -12, 30)
	scanButton:SetText("Scan AH")
	scanButton:SetScript("OnClick", ns.Scan)
	scanButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Scan crate prices", 1, 1, 1)
		GameTooltip:AddLine("Queues every crate and bundle material with no price, or a price older than an hour, into MarketScribe's scanner. The Auction House must be open.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	scanButton:SetScript("OnLeave", GameTooltip_Hide)

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	statusText:SetPoint("BOTTOMLEFT", 14, 12)
	statusText:SetPoint("BOTTOMRIGHT", -14, 12)
	statusText:SetJustifyH("LEFT")

	frame:SetScript("OnShow", function()
		ns.Refresh()
		-- prices stream in while MarketScribe scans; keep the table live
		ticker = C_Timer.NewTicker(2, ns.Refresh)
	end)
	frame:SetScript("OnHide", function()
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
	end)
	frame:Hide()
end

function ns.Toggle()
	if not frame then
		Build()
	end
	frame:SetShown(not frame:IsShown())
end
