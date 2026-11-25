-- CrateScribe: CrateScribe.lua
--
-- Ranks the Waylaid Crates by copper spent per Merchant's Favor, using
-- MarketScribe's cached AH/vendor prices for both the crate itself and the
-- materials that fill it.
--
--   Cost / Favor = (crate AH price + cheapest bundle - money the turn-in
--                   quest pays) / favor
-- The crate's price counts whether you buy it or already own one: a crate
-- you own could be sold instead, so turning it in costs you that price.
--
-- Also: learns real Favor payouts from the turn-in quest, finds the crate
-- item IDs by name, adds a line to crate tooltips, and can queue every
-- crate + material for a MarketScribe AH scan.

local addonName, ns = ...

local PREFIX = "|cffffb84dCrateScribe|r"
local STALE_SECONDS = 3600 -- re-scan prices older than this with the Scan button

CrateScribeDB = CrateScribeDB or {}
local db

local function Print(msg)
	print(PREFIX .. ": " .. msg)
end

--------------------------------------------------------------------------
-- Price access: prefer MarketScribe's live API; fall back to reading its
-- SavedVariables table directly with the same vendor-vs-AH rule.
--------------------------------------------------------------------------

local function MS()
	return _G.MarketScribeAPI
end

local function RealmKey()
	return (GetRealmName() or "Unknown") .. "-" .. (UnitFactionGroup("player") or "Neutral")
end

local function GetPrice(itemID)
	local api = MS()
	if api and api.GetPrice then
		return api.GetPrice(itemID)
	end
	local store = MarketScribeDB and MarketScribeDB[RealmKey()]
	if not store then
		return nil
	end
	local market = store.prices and store.prices[itemID]
	local vendor = store.vendor and store.vendor[itemID]
	if vendor and (not market or vendor <= market.price) then
		return vendor, nil, "vendor"
	elseif market then
		return market.price, market.time, market.source
	end
end

-- Cheapest of buying it vs. crafting it from a recipe you know (only works
-- when MarketScribe has your recipes loaded, i.e. after opening the
-- profession window this session). Returns cost, source, time.
local function GetUnitCost(itemID)
	local price, seen, source = GetPrice(itemID)
	local api = MS()
	if api and api.GetRecipesForOutput and api.GetRecipeCostPerItem then
		local ok, recipes = pcall(api.GetRecipesForOutput, itemID)
		if ok and recipes then
			for _, recipeID in ipairs(recipes) do
				local ok2, cost, complete = pcall(api.GetRecipeCostPerItem, recipeID)
				if ok2 and cost and complete and cost > 0 and (not price or cost < price) then
					price, seen, source = cost, nil, "craft"
				end
			end
		end
	end
	return price, source, seen
end

local function FormatMoney(copper)
	local api = MS()
	if api and api.FormatMoney then
		return api.FormatMoney(copper)
	end
	copper = math.floor(math.abs(copper or 0) + 0.5)
	if copper >= 10000 then
		return (("%.2f"):format(copper / 10000):gsub("0+$", ""):gsub("%.$", "")) .. "g"
	elseif copper >= 100 then
		return (("%.2f"):format(copper / 100):gsub("0+$", ""):gsub("%.$", "")) .. "s"
	end
	return copper .. "c"
end

local function ItemName(itemID, fallback)
	local name = C_Item.GetItemInfo(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID)
	end
	return name or fallback or ("item:" .. itemID)
end

local function MaxStack(itemID)
	local size = select(8, C_Item.GetItemInfo(itemID))
	return size
end

--------------------------------------------------------------------------
-- Crate discovery: find each typed crate's item ID by name.
--------------------------------------------------------------------------

local function LearnCrateItem(itemID)
	if not itemID then
		return
	end
	local name, _, quality = C_Item.GetItemInfo(itemID)
	if not name then
		return false
	end
	local suffix = name:match("^" .. ns.CRATE_PREFIX:gsub("%p", "%%%0") .. "(.+)$")
	local crate = suffix and ns.CRATE_BY_NAME[suffix]
	if crate then
		db.crateIDs[suffix] = itemID
		if quality then
			db.crateQuality[suffix] = quality
		end
		return true
	end
	return false
end

local pendingDiscovery = {}

local function DiscoverCrates()
	for itemID, suffix in pairs(ns.KNOWN_CRATE_IDS) do
		db.crateIDs[suffix] = db.crateIDs[suffix] or itemID
	end
	for itemID = ns.SCAN_FIRST, ns.SCAN_LAST do
		if not LearnCrateItem(itemID) and not C_Item.GetItemInfo(itemID) then
			pendingDiscovery[itemID] = true
			C_Item.RequestLoadItemDataByID(itemID)
		end
	end
end

local function CrateID(crate)
	return db.crateIDs[crate.name]
end

--------------------------------------------------------------------------
-- Favor per crate
--------------------------------------------------------------------------

local function CrateQuality(crate)
	return db.crateQuality[crate.name] or (crate.kind == "craft" and 2 or 1)
end

-- Returns favor, confirmed (bool)
local function CrateFavor(crate)
	local key = crate.tier .. ":" .. CrateQuality(crate)
	if db.favor[key] then
		return db.favor[key], true
	end
	return ns.DEFAULT_FAVOR[key] or 5, ns.CONFIRMED_FAVOR[key] or false
end

--------------------------------------------------------------------------
-- The maths
--------------------------------------------------------------------------

-- Returns a result table for one crate:
--   best       = { itemID, qty, name, cost, source } or nil
--   bundles    = every bundle with its cost (nil if unpriced)
--   complete   = every bundle had a price (so "best" really is the best)
--   crateCost  = AH price of the crate item (nil if unknown)
--   favor, favorConfirmed, fillPer, totalPer
--   perFavor   = (fill + crate price) / favor; just fill / favor while the
--                crate's price is unknown (crateKnown = false)
--   crateOld   = the crate's AH price is over 3 days old
local function Evaluate(crate)
	local r = { crate = crate, bundles = {}, complete = true }
	for _, b in ipairs(crate.bundles) do
		local itemID, qty, fallback = b[1], b[2], b[3]
		local unit, source, seen = GetUnitCost(itemID)
		local maxStack = MaxStack(itemID)
		local entry = {
			itemID = itemID, qty = qty, name = ItemName(itemID, fallback),
			unit = unit, source = source, seen = seen,
			cost = unit and unit * qty or nil,
			-- Beta bug: bundles needing more than one stack can't be filled.
			stackBug = maxStack and maxStack > 0 and qty > maxStack or false,
		}
		table.insert(r.bundles, entry)
		local usable = not (entry.stackBug and db.skipStackBug)
		if usable then
			if entry.cost then
				if not r.best or entry.cost < r.best.cost then
					r.best = entry
				end
			else
				r.complete = false
			end
		end
	end

	r.favor, r.favorConfirmed = CrateFavor(crate)
	local crateID = CrateID(crate)
	if crateID then
		r.crateCost, r.crateSeen = GetPrice(crateID)
	end
	-- money the turn-in quest pays (learned from your turn-ins, else the known
	-- amount for the tier and rarity), comes off the cost
	local key = crate.tier .. ":" .. CrateQuality(crate)
	r.money = db.tierMoney[key] or ns.DEFAULT_MONEY[key]
	if r.best then
		local back = r.money or 0
		r.fillPer = (r.best.cost - back) / r.favor
		if r.crateCost then
			r.totalPer = (r.best.cost + r.crateCost - back) / r.favor
		end
		r.crateKnown = r.crateCost ~= nil
		r.perFavor = r.totalPer or r.fillPer
	end
	r.crateOld = r.crateSeen and (time() - r.crateSeen) > 3 * 86400 or false
	return r
end

local function EvaluateAll()
	local results = {}
	for _, crate in ipairs(ns.CRATES) do
		table.insert(results, Evaluate(crate))
	end
	-- crates with a known price first (their figure is complete), then the
	-- ones whose crate price is still unknown, then the unpriced
	table.sort(results, function(a, b)
		local av, bv = a.perFavor, b.perFavor
		if av and bv then
			if a.crateKnown ~= b.crateKnown then return a.crateKnown end
			return av < bv
		elseif av or bv then
			return av ~= nil
		end
		-- neither ranked: tier, then name
		local ta, tb = ns.TIER_ORDER[a.crate.tier], ns.TIER_ORDER[b.crate.tier]
		if ta ~= tb then
			return ta < tb
		end
		return a.crate.name < b.crate.name
	end)
	return results
end
ns.EvaluateAll = EvaluateAll

--------------------------------------------------------------------------
-- Bags: how many of each crate you're holding (also learns IDs)
--------------------------------------------------------------------------

local owned = {}

local function ScanBags()
	wipe(owned)
	if not (C_Container and C_Container.GetContainerNumSlots) then
		return
	end
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local name = C_Item.GetItemInfo(info.itemID)
				if name and name:find(ns.CRATE_PREFIX, 1, true) == 1 then
					LearnCrateItem(info.itemID)
					local suffix = name:sub(#ns.CRATE_PREFIX + 1)
					owned[suffix] = (owned[suffix] or 0) + (info.stackCount or 1)
				end
			end
		end
	end
end

--------------------------------------------------------------------------
-- Learning from turn-ins: the Favor and money each crate's quest pays.
-- When a quest asks for a crate (QUEST_PROGRESS), the required item is
-- matched to a crate by name (e.g. "Sealed Crate: Apprentice Herbs") or,
-- failing that, by which Waylaid Crate left your bags. QUEST_COMPLETE then
-- records the Favor and money rewards. Everything is also logged per quest
-- in db.turnins, matched or not, so nothing is lost.
--------------------------------------------------------------------------

local pending

local function Plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- Merchant's Favor you hold right now (nil if the currency can't be read).
-- Finds the currency by name once, in case its ID isn't the one in Data.lua.
local function FavorHeld()
	if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
	local id = db.currencyID or ns.CURRENCY_ID
	local info = C_CurrencyInfo.GetCurrencyInfo(id)
	if info and Plain(info.name) and Plain(info.name):find("Favor", 1, true) then
		return Plain(info.quantity)
	end
	if C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo then
		for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
			local li = C_CurrencyInfo.GetCurrencyListInfo(i)
			if li and Plain(li.name) == "Merchant's Favor" then
				local link = C_CurrencyInfo.GetCurrencyListLink and C_CurrencyInfo.GetCurrencyListLink(i)
				local cid = link and tonumber(link:match("currency:(%d+)"))
				if cid then db.currencyID = cid end
				return Plain(li.quantity)
			end
		end
	end
end

local TIERS = { "Apprentice", "Journeyman", "Expert", "Artisan" }

local function TierIn(text)
	if not text then return nil end
	for _, t in ipairs(TIERS) do
		if text:find(t, 1, true) then return t end
	end
end

-- the crate whose name appears in an item name (longest match wins)
local function CrateInName(itemName)
	if not itemName then return nil end
	local best
	for _, crate in ipairs(ns.CRATES) do
		if itemName:find(crate.name, 1, true) and (not best or #crate.name > #best.name) then best = crate end
	end
	return best
end

-- typed crates you own right now: name -> count
local function OwnedSnapshot()
	local snap = {}
	for k, v in pairs(owned) do snap[k] = v end
	return snap
end

local function OnQuestProgress()
	pending = nil
	local n = Plain(GetNumQuestItems and GetNumQuestItems()) or 0
	for i = 1, n do
		local link = Plain(GetQuestItemLink("required", i))
		local name = Plain((GetQuestItemInfo("required", i)))
		local itemID = link and C_Item.GetItemInfoInstant(link)
		local lname = name and name:lower() or ""
		if name and (lname:find("crate", 1, true)) then
			local quality = link and select(3, C_Item.GetItemInfo(link))
			pending = { item = name, itemID = itemID, quality = quality, at = GetTime(),
				crate = CrateInName(name), tier = TierIn(name) }
			return
		end
	end
end

local function RewardFavorAmount()
	local n = Plain(GetNumRewardCurrencies and GetNumRewardCurrencies()) or 0
	for i = 1, n do
		if C_QuestOffer and C_QuestOffer.GetQuestRewardCurrencyInfo then
			local ok, info = pcall(C_QuestOffer.GetQuestRewardCurrencyInfo, "reward", i)
			if ok and info and Plain(info.currencyID) == ns.CURRENCY_ID then
				return Plain(info.totalRewardAmount) or Plain(info.baseRewardAmount)
			end
		end
		if GetQuestCurrencyID and GetQuestCurrencyInfo then
			if Plain(GetQuestCurrencyID("reward", i)) == ns.CURRENCY_ID then
				local _, _, amount = GetQuestCurrencyInfo("reward", i)
				return Plain(amount)
			end
		end
	end
end

local awaiting

local function OnQuestComplete()
	local qid = Plain(GetQuestID and GetQuestID())
	local title = Plain(GetTitleText and GetTitleText()) or ""
	local isCrateQuest = (pending and GetTime() - pending.at < 120) or title:lower():find("sealed crate", 1, true)
	if not isCrateQuest then
		pending = nil
		return
	end
	local p = pending or {}
	pending = nil
	local money = Plain(GetRewardMoney and GetRewardMoney()) or 0
	local entry = { title = title, item = p.item, itemID = p.itemID, quality = p.quality, money = money,
		favor = RewardFavorAmount(), tier = p.tier or TierIn(p.item), crate = p.crate and p.crate.name,
		t = time(), level = UnitLevel("player") }
	if qid then db.turnins[qid] = entry end
	-- The reward window doesn't always say how much Favor it pays, so also
	-- compare what you hold now with what you hold after the turn-in
	-- (QUEST_TURNED_IN).
	awaiting = { entry = entry, before = FavorHeld(), qid = qid, at = GetTime() }
end

local function OnQuestTurnedIn(qid, money)
	local a = awaiting
	if not a or (a.qid and qid and a.qid ~= qid) or GetTime() - a.at > 600 then return end
	awaiting = nil
	local entry = a.entry
	if money and money > 0 then entry.money = money end
	local tries = 0
	local function Check()
		tries = tries + 1
		local now = FavorHeld()
		if a.before and now and now > a.before then
			entry.favor = now - a.before
		elseif tries < 5 then
			C_Timer.After(1, Check)
			return
		end
		ns.LearnTurnin(entry)
	end
	C_Timer.After(0.5, Check)
end

-- Save what a turn-in paid for its tier and rarity (newest wins).
function ns.LearnTurnin(entry, quiet)
	local tier, quality = entry.tier or TierIn(entry.item), entry.quality
	if not (tier and quality and ns.TIER_LEVEL[tier]) then
		if not quiet then
			Print(("turn-in seen (%s) but couldn't tell the crate's tier and rarity. /crates turnins shows it."):format(entry.item or "?"))
		end
		return
	end
	local key = tier .. ":" .. quality
	local changed = false
	if entry.money and entry.money > 0 and db.tierMoney[key] ~= entry.money then
		db.tierMoney[key] = entry.money
		changed = true
	end
	if entry.favor and entry.favor > 0 and db.favor[key] ~= entry.favor then
		-- your very first crate pays a one-time bonus; don't learn that as the normal amount
		local default = ns.DEFAULT_FAVOR[key]
		if not (default and entry.favor >= default + 50) then
			db.favor[key] = entry.favor
			changed = true
		end
	end
	if changed and not quiet then
		Print(("learned: %s %s crates pay %s%s."):format(quality == 2 and "green" or "white", tier,
			db.favor[key] and (db.favor[key] .. " Merchant's Favor") or "? Favor",
			(db.tierMoney[key] or 0) > 0 and (" + " .. FormatMoney(db.tierMoney[key])) or ""))
	end
	if changed and ns.Refresh then ns.Refresh() end
end

--------------------------------------------------------------------------
-- AH scan via MarketScribe
--------------------------------------------------------------------------

local function ScanIDs(staleOnly)
	local ids, seen = {}, {}
	local function add(id)
		if not id or seen[id] then
			return
		end
		seen[id] = true
		if staleOnly then
			local price, t, source = GetPrice(id)
			if price and (source == "vendor" or (t and time() - t < STALE_SECONDS)) then
				return
			end
		end
		table.insert(ids, id)
	end
	for _, crate in ipairs(ns.CRATES) do
		add(CrateID(crate))
		for _, b in ipairs(crate.bundles) do
			add(b[1])
		end
	end
	if ns.WritScanIDs then
		for _, id in ipairs(ns.WritScanIDs()) do add(id) end
	end
	return ids
end

function ns.Scan()
	local api = MS()
	if not (api and api.QueueItemsForced) then
		Print("needs the updated MarketScribe (with MarketScribeAPI) to scan. Prices are still read from its saved data.")
		return
	end
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		Print("open the Auction House first.")
		return
	end
	local ids = ScanIDs(true)
	local added = api.QueueItemsForced(ids)
	if added == 0 then
		Print(("all crate and material prices are fresher than %d min."):format(STALE_SECONDS / 60))
	else
		Print(("queued %d crate/material prices in MarketScribe (~%ds)."):format(added, added))
	end
end

--------------------------------------------------------------------------
-- Tooltip line on crate items
--------------------------------------------------------------------------

-- Hovering a crate also "hovers" every material it can be filled with, using
-- MarketScribe's normal hover rules (same as its own Tooltip.lua):
--   - remember it as wanted if its AH price is missing or over an hour old,
--     so the next Auction House visit searches it;
--   - queue a search now if the price is missing or stale, which MarketScribe
--     skips if it searched that item in the last 30 minutes, and never for
--     greys, Bind-on-Pickup or quest items.
-- Searches only go out while the Auction House is open.
local function TouchMaterial(api, id)
	if api.NoteWanted then
		api.NoteWanted(id)
	end
	if not api.QueueItem then
		return
	end
	local price, _, source = api.GetPrice(id)
	if price then
		local vendorOnly = source == "vendor" and not (api.GetMarketPrice and api.GetMarketPrice(id))
		if api.IsPriceStale and api.IsPriceStale(id) and not vendorOnly then
			api.QueueItem(id)
		end
	elseif not (api.Auctionable and not api.Auctionable(id)) then
		api.QueueItem(id)
	end
end

local function TouchCrateMaterials(crate)
	local api = MS()
	if not (api and api.GetPrice) then
		return
	end
	for _, b in ipairs(crate.bundles) do
		pcall(TouchMaterial, api, b[1])
	end
end

local function OnItemTooltip(tooltip)
	if not (TooltipUtil and TooltipUtil.GetDisplayedItem) then
		return
	end
	local _, _, itemID = TooltipUtil.GetDisplayedItem(tooltip)
	if not itemID or not db then
		return
	end
	local name = C_Item.GetItemInfo(itemID)
	if not (name and name:find(ns.CRATE_PREFIX, 1, true) == 1) then
		return
	end
	LearnCrateItem(itemID)
	local crate = ns.CRATE_BY_NAME[name:sub(#ns.CRATE_PREFIX + 1)]
	if not crate then
		return
	end
	TouchCrateMaterials(crate)
	local r = Evaluate(crate)
	local favorText = r.favor .. (r.favorConfirmed and "" or "?")
	if r.best then
		tooltip:AddLine(("%s best fill: %dx %s = %s"):format(PREFIX, r.best.qty, r.best.name, FormatMoney(r.best.cost)))
		if r.crateKnown then
			tooltip:AddLine(("  %s per Favor incl. the crate (%s on the AH%s), %s Favor%s"):format(FormatMoney(r.perFavor),
				FormatMoney(r.crateCost), r.crateOld and ", old price" or "", favorText, r.complete and "" or " |cff888888~|r"))
		else
			tooltip:AddLine(("  %s per Favor + the crate (no AH price yet), %s Favor%s"):format(FormatMoney(r.perFavor),
				favorText, r.complete and "" or " |cff888888~|r"))
		end
	else
		tooltip:AddLine(PREFIX .. " |cff888888no material prices yet -- scan at the AH (/crates scan)|r")
	end
end

--------------------------------------------------------------------------
-- /crates best: the single cheapest crate per Favor you can turn in now
--------------------------------------------------------------------------

function ns.PrintBest()
	local level = UnitLevel("player") or 1
	local results = EvaluateAll()
	local best, bestUnknown, tooHigh
	for _, r in ipairs(results) do
		if r.perFavor then
			if (ns.TIER_LEVEL[r.crate.tier] or 1) > level then
				tooHigh = tooHigh or r
			elseif r.crateKnown then
				if not best or r.perFavor < best.perFavor then best = r end
			elseif not bestUnknown or r.perFavor < bestUnknown.perFavor then
				bestUnknown = r
			end
		end
	end
	if not (best or bestUnknown) then
		Print("no crates priced yet. Open the Auction House and run /crates scan.")
		return
	end
	local function Line(r, label)
		local have = ns.Owned[r.crate.name]
		Print(("%s: |cffffffff%s|r -- |cff40ff40%s per Favor|r%s"):format(label, r.crate.name,
			FormatMoney(r.perFavor), r.crateKnown and "" or " + the crate (no AH price yet)"))
		print(("  fill with %dx %s (%s)%s, %s Favor%s%s%s"):format(r.best.qty, r.best.name, FormatMoney(r.best.cost),
			r.crateKnown and (", crate " .. FormatMoney(r.crateCost) .. (r.crateOld and " (old price)" or "")) or "",
			tostring(r.favor), r.favorConfirmed and "" or " (guess)",
			(r.money or 0) > 0 and (", quest pays " .. FormatMoney(r.money)) or "",
			have and (" -- you have " .. have) or ""))
		if not r.complete then
			print("  |cff888888some bundles for this crate have no price yet, so a cheaper fill may exist|r")
		end
	end
	if best then Line(best, "Cheapest") end
	-- a crate without an AH price could still be cheaper once its price is known
	if bestUnknown and (not best or bestUnknown.perFavor < best.perFavor) then
		Line(bestUnknown, best and "Maybe cheaper" or "Cheapest so far")
	end
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

SLASH_CRATESCRIBE1 = "/crates"
SLASH_CRATESCRIBE2 = "/cs"
SlashCmdList.CRATESCRIBE = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "show" then
		if ns.Toggle then
			ns.Toggle()
		end
	elseif msg == "scan" then
		ns.Scan()
	elseif msg == "writs" or msg == "writ" then
		if ns.ToggleWrits then ns.ToggleWrits() end
	elseif msg == "writbest" then
		if ns.PrintBestWrit then ns.PrintBestWrit() end
	elseif msg == "best" or msg == "cheapest" then
		ns.PrintBest()
	elseif msg == "top" then
		local results = EvaluateAll()
		Print("cheapest Favor, crate price included:")
		for i = 1, math.min(5, #results) do
			local r = results[i]
			if r.perFavor then
				print(("  %d. %s -- %s/Favor%s (%dx %s)"):format(i, r.crate.name, FormatMoney(r.perFavor),
					r.crateKnown and "" or " + crate", r.best.qty, r.best.name))
			end
		end
	elseif msg == "turnins" then
		Print("crate turn-ins seen:")
		local n = 0
		for qid, e in pairs(db.turnins) do
			n = n + 1
			local tier = e.tier or TierIn(e.item)
			local what = tier and e.quality and (("%s %s"):format(e.quality == 2 and "green" or "white", tier)) or (e.item or "?")
			print(("  quest %d: %s -- %s Favor, %s%s"):format(qid, what,
				tostring(e.favor or "?"), FormatMoney(e.money or 0), e.level and (" at level " .. e.level) or ""))
		end
		if n == 0 then print("  none yet -- turn a crate in and it's learned automatically.") end
	elseif msg == "favor" then
		Print("Merchant's Favor per sealed crate (learned from your turn-ins *, guess ?):")
		for _, tier in ipairs({ "Apprentice", "Journeyman", "Expert", "Artisan" }) do
			local parts = {}
			for q = 1, 2 do
				local key = tier .. ":" .. q
				local v = db.favor[key] or ns.DEFAULT_FAVOR[key]
				local mark = db.favor[key] and "*" or (ns.CONFIRMED_FAVOR[key] and "" or "?")
				local m = db.tierMoney[key] or ns.DEFAULT_MONEY[key]
				table.insert(parts, (q == 1 and "white " or "green ") .. v .. mark .. (m and (" + " .. FormatMoney(m)) or ""))
			end
			print(("  %s: %s"):format(tier, table.concat(parts, ", ")))
		end
	elseif msg:match("^favor ") then
		-- /crates favor expert green 40
		local tier, color, amount = msg:match("^favor (%a+) (%a+) (%d+)$")
		tier = tier and (tier:sub(1, 1):upper() .. tier:sub(2))
		local q = color == "white" and 1 or color == "green" and 2 or nil
		if tier and ns.TIER_LEVEL[tier] and q then
			db.favor[tier .. ":" .. q] = tonumber(amount)
			Print(("set %s %s crates to %s Favor."):format(tier, color, amount))
			if ns.Refresh then ns.Refresh() end
		else
			Print("usage: /crates favor <apprentice|journeyman|expert|artisan> <white|green> <amount>")
		end
	elseif msg == "ids" then
		Print("crate item IDs found:")
		local found = 0
		for _, crate in ipairs(ns.CRATES) do
			local id = CrateID(crate)
			print(("  %s: %s"):format(crate.name, id and tostring(id) or "|cffff4040not found yet|r"))
			if id then found = found + 1 end
		end
		print(("  %d/%d -- missing ones get picked up when you see them in bags, tooltips or the AH."):format(found, #ns.CRATES))
	elseif msg:match("^dump") then
		-- /crates dump <id>: print the raw tooltip, to verify bundle lists
		local id = tonumber(msg:match("(%d+)"))
		if not (id and C_TooltipInfo and C_TooltipInfo.GetItemByID) then
			Print("usage: /crates dump <itemID>")
			return
		end
		local data = C_TooltipInfo.GetItemByID(id)
		for _, line in ipairs(data and data.lines or {}) do
			print("  " .. tostring(line.leftText) .. (line.rightText and ("  |  " .. line.rightText) or ""))
		end
	else
		Print("/crates (window), /crates best (cheapest crate per Favor), /crates scan (queue AH prices; AH must be open), /crates top, /crates writs (Craftsman's Writs window), /crates writbest, /crates favor, /crates favor <tier> <white|green> <n>, /crates ids, /crates dump <itemID>")
	end
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:SetScript("OnEvent", function(_, event, a, b, c)
	if event == "ADDON_LOADED" and a == addonName then
		CrateScribeDB = CrateScribeDB or {}
		db = CrateScribeDB
		db.crateIDs = db.crateIDs or {}
		db.crateQuality = db.crateQuality or {}
		db.favor = db.favor or {}
		db.crateMoney = nil -- old per-crate money; payouts are per tier and rarity now
		db.tierMoney = db.tierMoney or {} -- ["Expert:2"] = copper the turn-in pays
		db.turnins = db.turnins or {}       -- [questID] = what each turn-in paid
		-- re-read past turn-ins with the tier + rarity rule
		for _, e in pairs(db.turnins) do pcall(ns.LearnTurnin, e, true) end
		db.sortBy = db.sortBy or "total"
		if db.skipStackBug == nil then
			db.skipStackBug = false
		end
	elseif event == "PLAYER_LOGIN" then
		DiscoverCrates()
		ScanBags()
		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if a and pendingDiscovery[a] then
			pendingDiscovery[a] = nil
			if b then
				LearnCrateItem(a)
			end
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		ScanBags()
		if ns.Refresh then
			ns.Refresh()
		end
	elseif event == "QUEST_PROGRESS" then
		OnQuestProgress()
	elseif event == "QUEST_COMPLETE" then
		OnQuestComplete()
	elseif event == "QUEST_TURNED_IN" then
		OnQuestTurnedIn(a, c)
	end
end)

-- shared with UI.lua
ns.Evaluate = Evaluate
ns.FormatMoney = FormatMoney
ns.Owned = owned
ns.CrateID = CrateID
ns.DB = function() return db end
ns.Print = Print
ns.GetPrice = GetPrice
ns.GetUnitCost = GetUnitCost
ns.ItemName = ItemName
ns.MS = MS
