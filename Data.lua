-- CrateScribe: Data.lua
--
-- Static data for the 30 typed Waylaid Crates in WoW: Forever. Bundle lists
-- come from the community crate tables (wowf.io / zockify, cross-checked
-- against the in-game tooltip for Apprentice Textiles/Fabrics); material
-- item IDs are the standard Classic IDs. Each crate is filled with ONE
-- bundle from its list.
--
-- Crate item IDs are NOT hardcoded (only two are confirmed) -- they're
-- discovered at runtime by name: see DiscoverCrates in CrateScribe.lua.

local addonName, ns = ...

ns.CURRENCY_ID = 3402 -- Merchant's Favor
ns.CRATE_PREFIX = "Waylaid Crate: "

-- Item ID window that's scanned by name on login to find the typed crates.
-- The known ones (248684, 248702) sit in the middle of a block of
-- 2486xx/2487xx IDs MarketScribe has already priced.
ns.SCAN_FIRST, ns.SCAN_LAST = 248660, 248730

ns.TIER_LEVEL = { Apprentice = 10, Journeyman = 10, Expert = 20, Artisan = 35 }
ns.TIER_ORDER = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }

-- What the "A Sealed Crate" turn-in pays, keyed "<Tier>:<quality>". Once a
-- Waylaid Crate is filled it becomes a generic "Sealed <Tier> Crate", so the
-- payout depends only on the tier and the crate's rarity: gathering crates
-- (raw mats) are white (1), crafting crates (bolts/bars/parts) are green (2)
-- and pay double. Each tier adds 5 Favor (white) and 2.5s (white).
-- Apprentice-Expert are confirmed (beta turn-ins + wow-professions.com);
-- Artisan follows the same steps and is a GUESS, shown with "?" until a
-- real turn-in teaches the addon the value.
ns.DEFAULT_FAVOR = {
	["Apprentice:1"] = 5, ["Apprentice:2"] = 10,
	["Journeyman:1"] = 10, ["Journeyman:2"] = 20,
	["Expert:1"] = 15, ["Expert:2"] = 30,
	["Artisan:1"] = 20, ["Artisan:2"] = 40,
}
ns.CONFIRMED_FAVOR = {
	["Apprentice:1"] = true, ["Apprentice:2"] = true,
	["Journeyman:1"] = true, ["Journeyman:2"] = true,
	["Expert:1"] = true, ["Expert:2"] = true,
}
-- money (copper) the turn-in pays
ns.DEFAULT_MONEY = {
	["Apprentice:1"] = 250, ["Apprentice:2"] = 500,
	["Journeyman:1"] = 500, ["Journeyman:2"] = 1000,
	["Expert:1"] = 750, ["Expert:2"] = 1500,
	["Artisan:1"] = 1000, ["Artisan:2"] = 2000,
}

-- kind: "gather" (white crate) or "craft" (green crate)
-- bundles: { itemID, quantity, "Name" } -- name is only a fallback label
-- until the client has the item cached.
ns.CRATES = {
	-- Herbs
	{ name = "Apprentice Herbs", tier = "Apprentice", kind = "gather", bundles = {
		{ 2447, 20, "Peacebloom" }, { 765, 20, "Silverleaf" }, { 2449, 10, "Earthroot" },
		{ 785, 10, "Mageroyal" }, { 2450, 10, "Briarthorn" } } },
	{ name = "Journeyman Herbs", tier = "Journeyman", kind = "gather", bundles = {
		{ 3820, 10, "Stranglekelp" }, { 2453, 10, "Bruiseweed" }, { 3355, 10, "Wild Steelbloom" },
		{ 3369, 10, "Grave Moss" }, { 3356, 10, "Kingsblood" } } },
	{ name = "Earthly Expert Herbs", tier = "Expert", kind = "gather", bundles = {
		{ 3357, 20, "Liferoot" }, { 3818, 10, "Fadeleaf" }, { 3821, 10, "Goldthorn" },
		{ 3358, 10, "Khadgar's Whisker" } } },
	{ name = "Flowering Expert Herbs", tier = "Expert", kind = "gather", bundles = {
		{ 3819, 10, "Wintersbite" }, { 4625, 10, "Firebloom" }, { 8831, 20, "Purple Lotus" },
		{ 8836, 10, "Arthas' Tears" } } },
	{ name = "Earthly Artisan Herbs", tier = "Artisan", kind = "gather", bundles = {
		{ 13464, 10, "Golden Sansam" }, { 8838, 20, "Sungrass" }, { 8839, 10, "Blindweed" },
		{ 8845, 10, "Ghost Mushroom" }, { 8846, 10, "Gromsblood" } } },
	{ name = "Flowering Artisan Herbs", tier = "Artisan", kind = "gather", bundles = {
		{ 13463, 20, "Dreamfoil" }, { 13465, 20, "Mountain Silversage" }, { 13466, 20, "Plaguebloom" },
		{ 13467, 20, "Icecap" } } },

	-- Ore
	{ name = "Apprentice Ore", tier = "Apprentice", kind = "gather", bundles = {
		{ 2770, 20, "Copper Ore" }, { 2771, 20, "Tin Ore" } } },
	{ name = "Journeyman Ore", tier = "Journeyman", kind = "gather", bundles = {
		{ 2775, 10, "Silver Ore" }, { 2772, 20, "Iron Ore" } } },
	{ name = "Expert Ore", tier = "Expert", kind = "gather", bundles = {
		{ 2776, 10, "Gold Ore" }, { 3858, 20, "Mithril Ore" } } },
	{ name = "Artisan Ore", tier = "Artisan", kind = "gather", bundles = {
		{ 7911, 10, "Truesilver Ore" }, { 10620, 20, "Thorium Ore" }, { 11370, 20, "Dark Iron Ore" } } },

	-- Textiles
	{ name = "Apprentice Textiles", tier = "Apprentice", kind = "gather", bundles = {
		{ 2589, 40, "Linen Cloth" }, { 2318, 20, "Light Leather" } } },
	{ name = "Journeyman Textiles", tier = "Journeyman", kind = "gather", bundles = {
		{ 2592, 20, "Wool Cloth" }, { 4306, 40, "Silk Cloth" }, { 2319, 20, "Medium Leather" } } },
	{ name = "Expert Textiles", tier = "Expert", kind = "gather", bundles = {
		{ 4338, 40, "Mageweave Cloth" }, { 4234, 20, "Heavy Leather" } } },
	{ name = "Artisan Textiles", tier = "Artisan", kind = "gather", bundles = {
		{ 14047, 40, "Runecloth" }, { 4304, 20, "Thick Leather" }, { 8170, 20, "Rugged Leather" } } },

	-- Curiosities (enchanting mats)
	{ name = "Apprentice Curiosities", tier = "Apprentice", kind = "gather", bundles = {
		{ 10940, 20, "Strange Dust" }, { 10939, 4, "Greater Magic Essence" },
		{ 10978, 6, "Small Glimmering Shard" }, { 11084, 2, "Large Glimmering Shard" } } },
	{ name = "Journeyman Curiosities", tier = "Journeyman", kind = "gather", bundles = {
		{ 11083, 20, "Soul Dust" }, { 11082, 4, "Greater Astral Essence" },
		{ 11138, 6, "Small Glowing Shard" }, { 11139, 2, "Large Glowing Shard" } } },
	{ name = "Expert Curiosities", tier = "Expert", kind = "gather", bundles = {
		{ 11137, 20, "Vision Dust" }, { 11135, 4, "Greater Mystic Essence" },
		{ 11177, 6, "Small Radiant Shard" }, { 11178, 2, "Large Radiant Shard" } } },
	{ name = "Artisan Curiosities", tier = "Artisan", kind = "gather", bundles = {
		{ 11176, 20, "Dream Dust" }, { 11175, 4, "Greater Nether Essence" },
		{ 14343, 6, "Small Brilliant Shard" }, { 14344, 2, "Large Brilliant Shard" } } },

	-- Fabrics (tailoring / leatherworking)
	{ name = "Apprentice Fabrics", tier = "Apprentice", kind = "craft", bundles = {
		{ 4231, 2, "Cured Light Hide" }, { 2996, 20, "Bolt of Linen Cloth" } } },
	{ name = "Journeyman Fabrics", tier = "Journeyman", kind = "craft", bundles = {
		{ 2997, 6, "Bolt of Woolen Cloth" }, { 4305, 10, "Bolt of Silk Cloth" }, { 4233, 2, "Cured Medium Hide" } } },
	{ name = "Expert Fabrics", tier = "Expert", kind = "craft", bundles = {
		{ 4339, 8, "Bolt of Mageweave" }, { 4236, 2, "Cured Heavy Hide" } } },
	{ name = "Artisan Fabrics", tier = "Artisan", kind = "craft", bundles = {
		{ 14048, 8, "Bolt of Runecloth" }, { 8172, 2, "Cured Thick Hide" } } },

	-- Ingots (smelting)
	{ name = "Apprentice Ingots", tier = "Apprentice", kind = "craft", bundles = {
		{ 2840, 20, "Copper Bar" }, { 3576, 20, "Tin Bar" }, { 2841, 10, "Bronze Bar" } } },
	{ name = "Journeyman Ingots", tier = "Journeyman", kind = "craft", bundles = {
		{ 2842, 10, "Silver Bar" }, { 3575, 20, "Iron Bar" } } },
	{ name = "Expert Ingots", tier = "Expert", kind = "craft", bundles = {
		{ 3860, 20, "Mithril Bar" }, { 3859, 15, "Steel Bar" }, { 3577, 10, "Gold Bar" } } },
	{ name = "Artisan Ingots", tier = "Artisan", kind = "craft", bundles = {
		{ 11371, 2, "Dark Iron Bar" }, { 6037, 10, "Truesilver Bar" }, { 12359, 20, "Thorium Bar" } } },

	-- Parts (engineering)
	{ name = "Apprentice Parts", tier = "Apprentice", kind = "craft", bundles = {
		{ 4359, 16, "Handful of Copper Bolts" }, { 4361, 16, "Copper Tube" }, { 4363, 4, "Copper Modulator" } } },
	{ name = "Journeyman Parts", tier = "Journeyman", kind = "craft", bundles = {
		{ 4371, 8, "Bronze Tube" }, { 4375, 7, "Whirring Bronze Gizmo" }, { 4382, 4, "Bronze Framework" },
		{ 10558, 45, "Gold Power Core" } } },
	{ name = "Expert Parts", tier = "Expert", kind = "craft", bundles = {
		{ 4387, 8, "Iron Strut" }, { 10559, 5, "Mithril Tube" }, { 10560, 12, "Unstable Trigger" },
		{ 10561, 5, "Mithril Casing" } } },
	{ name = "Artisan Parts", tier = "Artisan", kind = "craft", bundles = {
		{ 15994, 5, "Thorium Widget" }, { 18631, 5, "Truesilver Transformer" }, { 16000, 2, "Thorium Tube" } } },
}

-- Confirmed from Wowhead / the beta client; the rest are found by name.
ns.KNOWN_CRATE_IDS = {
	[248684] = "Apprentice Textiles",
	[248702] = "Apprentice Fabrics",
}

ns.CRATE_BY_NAME = {}
for _, crate in ipairs(ns.CRATES) do
	ns.CRATE_BY_NAME[crate.name] = crate
end
