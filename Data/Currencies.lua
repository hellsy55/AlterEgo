---@class AE_Addon
local addon = select(2, ...)

---@class AE_Data
local Data = addon.Data

---@type AE_Currency[]
Data.currencies = {
  {seasonID = 17, seasonDisplayID = 1, id = 3383, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Adventurer Dawncrest
  {seasonID = 17, seasonDisplayID = 1, id = 3341, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Veteran Dawncrest
  {seasonID = 17, seasonDisplayID = 1, id = 3343, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Champion Dawncrest
  {seasonID = 17, seasonDisplayID = 1, id = 3345, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Hero Dawncrest
  {seasonID = 17, seasonDisplayID = 1, id = 3347, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Myth Dawncrest
  {seasonID = 17, seasonDisplayID = 1, id = 3378, useTotalEarnedForMaxQty = true,  currencyType = "catalyst"},                                                                                                                                        -- Dawnlight Manaflux
  {seasonID = 17, seasonDisplayID = 1, id = 3212, useTotalEarnedForMaxQty = true,  currencyType = "spark",     tooltipNote = "There's a chance you'll have an extra Spark of Radiance from week one."},                                               -- Radiant Spark Dust
  {seasonID = 17, seasonDisplayID = 1, id = 3418, useTotalEarnedForMaxQty = true,  currencyType = "bonusroll", tooltipNote = "Once this currency is unlocked, you can buy extra Voidcores beyond the maximum from Vaultkeeper Elysa in Silvermoon."}, -- Nebulous Voidcore
  {seasonID = 17, seasonDisplayID = 1, id = 3310, useTotalEarnedForMaxQty = false, currencyType = "delve"},                                                                                                                                           -- Coffer Key Shards
  {seasonID = 17, seasonDisplayID = 1, id = 3028, useTotalEarnedForMaxQty = false, currencyType = "delve"},                                                                                                                                           -- Restored Coffer key
  {seasonID = 17, seasonDisplayID = 1, id = 3356, useTotalEarnedForMaxQty = false, currencyType = "delve"},                                                                                                                                           -- Untainted Mana-Crystals
  {seasonID = 18, seasonDisplayID = 2, id = 3442, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Adventurer Mistcrest
  {seasonID = 18, seasonDisplayID = 2, id = 3443, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Veteran Mistcrest
  {seasonID = 18, seasonDisplayID = 2, id = 3444, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Champion Mistcrest
  {seasonID = 18, seasonDisplayID = 2, id = 3445, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Hero Mistcrest
  {seasonID = 18, seasonDisplayID = 2, id = 3446, useTotalEarnedForMaxQty = true,  currencyType = "crest"},                                                                                                                                           -- Myth Mistcrest
  {seasonID = 18, seasonDisplayID = 2, id = 3465, useTotalEarnedForMaxQty = true,  currencyType = "catalyst"},																																	  -- Venomblight Manaflux
  {seasonID = 18, seasonDisplayID = 2, id = 3418, useTotalEarnedForMaxQty = true,  currencyType = "bonusroll"},                                                                                                                                       -- Nebulous Voidcore
  {seasonID = 18, seasonDisplayID = 2, id = 3509, useTotalEarnedForMaxQty = true,  currencyType = "spark"},                                                                                                                                           -- Tidal Spark Dust
  {seasonID = 18, seasonDisplayID = 2, id = 3310, useTotalEarnedForMaxQty = false, currencyType = "delve"},                                                                                                                                           -- Coffer Key Shards
  {seasonID = 18, seasonDisplayID = 2, id = 3028, useTotalEarnedForMaxQty = false, currencyType = "delve"},                                                                                                                                           -- Restored Coffer key
  {seasonID = 18, seasonDisplayID = 2, id = 3356, useTotalEarnedForMaxQty = false, currencyType = "delve"},                                                                                                                                           -- Untainted Mana-Crystals

  -- Weeklies (fixed display order: Dundun, Gilded Stash, Trovehunter's Bounty, Purging the Vaults, Trailing Xal'atath, Unity Against the Void)
  {id = 97064, currencyType = "quest", resets = "weekly",  name = "Dundun",  questID = 97064, iconFileID = 647701, category = "weekly", description = "Weekly delve event."},
  {id = "gildedStash", currencyType = "gildedStash", name = "Gilded Stash", spellID = 7591, iconFileID = 5872049, category = "weekly"},
  {seasonID = 17, seasonDisplayID = 1, id = 265714, useTotalEarnedForMaxQty = false, currencyType = "delveMap", name = "Trovehunter's Bounty", questID = 86371, spellID = 1254631, category = "weekly"},
  {seasonID = 18, seasonDisplayID = 2, id = 274374, useTotalEarnedForMaxQty = false, currencyType = "delveMap", name = "Trovehunter's Bounty", questID = 86371, spellID = 1293799, category = "weekly"},
  {id = 95520, currencyType = "quest", resets = "weekly",  name = "Purging the Vaults",  questID = 95520, iconFileID = 7966624, category = "weekly", description = "Weekly quest."},
  {id = 98172, currencyType = "quest", resets = "weekly",  name = "Trailing Xal'atath", questID = 98172, iconFileID = 7501330, category = "weekly", description = "Weekly quest."},
  {id = 93744, currencyType = "quest", resets = "weekly",  name = "Unity Against the Void", questID = 93744, iconFileID = 133403, category = "weekly", description = "Weekly quest."},

  -- Seasonal Chores (fixed display order: Azta'rec, Cracked Keystone)
  {id = 97913, currencyType = "quest", resets = "character", name = "Azta'rec", questID = 97913, iconFileID = 8032873, category = "seasonalChore", description = "One-time delve event. Can only be completed once per character."},
  {id = 97910, currencyType = "quest", resets = "character", name = "Cracked Keystone",  questID = 97910, iconFileID = 4352494, itemID = 279012, category = "seasonalChore", description = "One-time quest. Can only be completed once per character."},
}
