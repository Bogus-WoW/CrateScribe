-- CrateScribe: Writs.lua
-- Ranks Craftsman's Writs by copper per reputation:
--   (Writ AH price + the item it asks for - pouch) / reputation
-- Each Writ asks for 1 of one crafted item. Artisan Writs' Coin Pouch (1.2g) is taken off.
-- The item is priced as the cheaper of buying it or crafting it (when
-- MarketScribe knows your recipes).

local addonName, ns = ...

local ROW_H = 18
local COLS = {
	{ key = "writ", title = "Writ", width = 200, justify = "LEFT" },
	{ key = "item", title = "Needs (x1)", width = 190, justify = "LEFT" },
	{ key = "writcost", title = "Writ", width = 62, justify = "RIGHT" },
	{ key = "itemcost", title = "Item", width = 62, justify = "RIGHT" },
	{ key = "rep", title = "Rep", width = 38, justify = "RIGHT" },
	{ key = "per", title = "Cost/Rep", width = 80, justify = "RIGHT" },
}
local WIDTH = 24
for _, c in ipairs(COLS) do WIDTH = WIDTH + c.width end

local TIERS = { 0, 75, 125, 200 } -- reputation filter
local TouchWrit
local frame, rows, scrollChild, statusText, filterBtn, ticker
local filterIdx = 1

local function Grey(s) return "|cff888888" .. s .. "|r" end
local function Money(v) return v and ns.FormatMoney(v) or Grey("?") end

local function EvaluateWrit(w)
	local writID, rep, itemID, fallback = w[1], w[2], w[3], w[4]
	local r = { w = w, rep = rep, itemID = itemID, writID = writID }
	r.name = ns.ItemName(itemID, fallback)
	r.zone = w[5]
	r.writCost, r.writSeen = ns.GetPrice(writID)
	r.unit, r.source, r.seen = ns.GetUnitCost(itemID)
	r.writKnown = r.writCost ~= nil
	r.back = ns.WRIT_BACK[rep] or 0
	if r.unit then
		r.total = r.unit + (r.writCost or 0) - r.back
		r.perRep = r.total / rep
	end
	return r
end

local function EvaluateAllWrits()
	local res = {}
	for _, w in ipairs(ns.WRITS) do res[#res + 1] = EvaluateWrit(w) end
	table.sort(res, function(a, b)
		local av, bv = a.perRep, b.perRep
		if av and bv then
			if a.writKnown ~= b.writKnown then return a.writKnown end
			if av ~= bv then return av < bv end
			return a.name < b.name
		elseif av or bv then
			return av ~= nil
		end
		if a.rep ~= b.rep then return a.rep < b.rep end
		return a.name < b.name
	end)
	return res
end
ns.EvaluateAllWrits = EvaluateAllWrits

function ns.WritScanIDs()
	local ids = {}
	for _, w in ipairs(ns.WRITS) do
		ids[#ids + 1] = w[1]
		ids[#ids + 1] = w[3]
	end
	return ids
end

function ns.PrintBestWrit()
	local best, bestUnknown
	for _, r in ipairs(EvaluateAllWrits()) do
		if r.perRep then
			if r.writKnown then
				if not best or r.perRep < best.perRep then best = r end
			elseif not bestUnknown or r.perRep < bestUnknown.perRep then
				bestUnknown = r
			end
		end
	end
	if not (best or bestUnknown) then
		ns.Print("no Writs priced yet. Open the Auction House and run /crates scan.")
		return
	end
	local function Line(r, label)
		ns.Print(("%s: |cffffffff%s|r -- |cff40ff40%s per reputation|r%s"):format(label, r.name,
			ns.FormatMoney(r.perRep), r.writKnown and "" or " + the Writ (no AH price yet)"))
		print(("  %s item, %s Writ, %d rep"):format(ns.FormatMoney(r.unit), r.writCost and ns.FormatMoney(r.writCost) or "?", r.rep))
	end
	if best then Line(best, "Cheapest Writ") end
	if bestUnknown and (not best or bestUnknown.perRep < best.perRep) then
		Line(bestUnknown, best and "Maybe cheaper" or "Cheapest so far")
	end
end

local function RowTooltip(row)
	local r = row.result
	if not r then return end
	TouchWrit(r.w)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Craftsman's Writ: " .. r.name, 1, 1, 1)
	GameTooltip:AddLine(r.rep .. " reputation", 0.7, 0.7, 0.7)
	GameTooltip:AddDoubleLine("Turn in", r.zone or "|cff888888unknown|r", 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Writ on AH", Money(r.writCost), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("1x " .. r.name .. (r.source and (" (" .. r.source .. ")") or ""), Money(r.unit), 1, 1, 1, 1, 1, 1)
	if r.back > 0 then
		GameTooltip:AddDoubleLine("Coin Pouch (taken off)", "-" .. ns.FormatMoney(r.back), 1, 1, 1, 0.25, 1, 0.25)
	end
	if r.total then
		GameTooltip:AddDoubleLine("Total / rep", ns.FormatMoney(r.total) .. " / " .. ns.FormatMoney(r.perRep), 1, 0.82, 0, 1, 0.82, 0)
	end
	if not r.writKnown then
		GameTooltip:AddLine("No AH price for the Writ yet: Cost/Rep is the item only.", 1, 0.5, 0.5, true)
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
	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function Refresh()
	if not (frame and frame:IsShown()) then return end
	local want = TIERS[filterIdx]
	local n, rank = 0, 0
	for _, r in ipairs(EvaluateAllWrits()) do
		if want == 0 or r.rep == want then
			n = n + 1
			local row = rows[n] or CreateRow(n)
			rows[n] = row
			row.result = r
			local name = r.name
			if r.perRep and r.writKnown then
				rank = rank + 1
				if rank <= 3 then name = ("|cff40ff40%d.|r %s"):format(rank, name) end
			end
			row.cells.writ:SetText(name)
			row.cells.item:SetText(r.source == "craft" and (r.name .. Grey(" (craft)")) or r.name)
			row.cells.writcost:SetText(Money(r.writCost))
			row.cells.itemcost:SetText(Money(r.unit))
			row.cells.rep:SetText(r.rep)
			local per = Grey("?")
			if r.perRep and r.writKnown then
				per = "|cffffd100" .. ns.FormatMoney(r.perRep) .. "|r"
			elseif r.perRep then
				per = Grey(ns.FormatMoney(r.perRep) .. " + Writ")
			end
			row.cells.per:SetText(per)
			row:Show()
		end
	end
	for i = n + 1, #rows do rows[i]:Hide() end
	scrollChild:SetHeight(n * ROW_H)
	filterBtn:SetText(want == 0 and "Rep: all" or ("Rep: " .. want))
	statusText:SetText(Grey("Cost/Rep = (Writ AH price + the item it needs) / reputation; Artisan Writs: 1.2g Coin Pouch taken off. \"+ Writ\" = Writ has no AH price yet."))
end
ns.RefreshWrits = Refresh

local function Build()
	frame = CreateFrame("Frame", "CrateScribeWritFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WIDTH + 16, 520)
	frame:SetPoint("CENTER", 30, -20)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "CrateScribeWritFrame")
	local title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not frame.TitleText then title:SetPoint("TOP", 0, -5) end
	title:SetText("CrateScribe -- Craftsman's Writs, copper per reputation")

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

	filterBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	filterBtn:SetSize(110, 22)
	filterBtn:SetPoint("BOTTOMLEFT", 12, 30)
	filterBtn:SetScript("OnClick", function()
		filterIdx = filterIdx % #TIERS + 1
		Refresh()
	end)
	local scanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scanButton:SetSize(110, 22)
	scanButton:SetPoint("BOTTOMRIGHT", -12, 30)
	scanButton:SetText("Scan AH")
	scanButton:SetScript("OnClick", ns.Scan)

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	statusText:SetPoint("BOTTOMLEFT", 14, 12)
	statusText:SetPoint("BOTTOMRIGHT", -14, 12)
	statusText:SetJustifyH("LEFT")
	frame:SetScript("OnShow", function()
		Refresh()
		ticker = C_Timer.NewTicker(2, Refresh)
	end)
	frame:SetScript("OnHide", function()
		if ticker then ticker:Cancel() ticker = nil end
	end)
	frame:Hide()
end

function ns.ToggleWrits()
	if not frame then Build() end
	frame:SetShown(not frame:IsShown())
end

-- Hover = look it up: same rules as crate materials (and MarketScribe's own
-- tooltips): remember it as wanted if the price is missing/old, and queue an AH
-- search now if it's missing or stale (never for greys, BoP or quest items).
local function TouchItem(api, id)
	if api.NoteWanted then api.NoteWanted(id) end
	if not api.QueueItem then return end
	local price, _, source = api.GetPrice(id)
	if price then
		local vendorOnly = source == "vendor" and not (api.GetMarketPrice and api.GetMarketPrice(id))
		if api.IsPriceStale and api.IsPriceStale(id) and not vendorOnly then api.QueueItem(id) end
	elseif not (api.Auctionable and not api.Auctionable(id)) then
		api.QueueItem(id)
	end
end

function TouchWrit(w)
	local api = ns.MS()
	if not (api and api.GetPrice) then return end
	pcall(TouchItem, api, w[1])
	pcall(TouchItem, api, w[3])
end

-- tooltip line on Writ items
local WRIT_BY_ID = {}
for _, w in ipairs(ns.WRITS) do WRIT_BY_ID[w[1]] = w end

local function OnItemTooltip(tooltip)
	if not (TooltipUtil and TooltipUtil.GetDisplayedItem) then return end
	local _, _, itemID = TooltipUtil.GetDisplayedItem(tooltip)
	local w = itemID and WRIT_BY_ID[itemID]
	if not w then return end
	TouchWrit(w)
	local r = EvaluateWrit(w)
	tooltip:AddLine("|cffffb84dCrateScribe|r Turn in: " .. (r.zone or "|cff888888zone unknown|r"))
	if r.perRep then
		tooltip:AddLine(("|cffffb84dCrateScribe|r %s per rep (%s item%s), %d rep"):format(ns.FormatMoney(r.perRep),
			ns.FormatMoney(r.unit), (r.writKnown and (" + " .. ns.FormatMoney(r.writCost) .. " Writ") or ", Writ price unknown") .. (r.back > 0 and (" - " .. ns.FormatMoney(r.back) .. " pouch") or ""), r.rep))
	else
		tooltip:AddLine("|cffffb84dCrateScribe|r |cff888888no price for the item it needs yet|r")
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	end
end)
