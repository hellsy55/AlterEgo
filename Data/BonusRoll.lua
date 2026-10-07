---@class AE_Addon
local addon = select(2, ...)

---@class AE_Data
local Data = addon.Data

-- Bonus roll data comes from the SimulationCraft addon as a line like:
--   bonus_roll_items=3418:278284:5:4:268265:264/
-- Each entry (separated by "/") is: currencyID:sourceID:contextID:keyLevel:itemID:specID
--
-- keyLevel only matters when the source is a dungeon (Mythic+ keystone level).
-- For raid sources it is ignored.

---Item creation contexts -> raid difficultyID (see Data.raidDifficulties).
---Uses Enum.ItemCreationContext when the client provides it, with fallback numbers.
---@type table<number, number>
Data.bonusRollRaidContexts = {}
do
  local enum = Enum and Enum.ItemCreationContext or {}
  Data.bonusRollRaidContexts[enum.RaidFinder or 4] = 17 -- LFR
  Data.bonusRollRaidContexts[enum.RaidNormal or 3] = 14 -- Normal
  Data.bonusRollRaidContexts[enum.RaidHeroic or 5] = 15 -- Heroic
  Data.bonusRollRaidContexts[enum.RaidMythic or 6] = 16 -- Mythic
end

---Contexts that mean "rolled in a Mythic+ keystone dungeon" (the keyLevel field is the keystone level).
---Confirmed: 5 = Raid Heroic, 6 = Raid Mythic, 16 = Keystone. 3 (Normal) and 4 (LFR) are still unconfirmed.
---@type table<number, boolean>
Data.bonusRollKeystoneContexts = {
  [16] = true,
}

---sourceID -> where the bonus roll was spent.
---
---  kind                "raid" or "dungeon"
---  journalInstanceID   matches Data.raids / Data.dungeons (that is where the instance name comes from)
---  journalEncounterID  (optional) boss, the name is read from the Encounter Journal
---  bossName            (optional) used instead of the Encounter Journal name
---  order               (optional) boss order inside the instance (lower first)
---
--- Sources that are not listed here still show up in the window under "Unknown source"
--- with their raw sourceID, so you can see which ones are missing.
---
--- Raids:    journalInstanceID 1320 = The Venomous Abyss, 1317 = The Tidebound Grotto
--- Dungeons: see Data/MythicPlus.lua (journalInstanceID column)
---@type table<number, {kind: "raid"|"dungeon", journalInstanceID: number, journalEncounterID: number?, bossName: string?, order: number?}>
Data.bonusRollSources = {
  -- The Venomous Abyss (journalInstanceID 1320)
  [278285] = {kind = "raid", journalInstanceID = 1320, bossName = "Nek'zali the Soulcoiler", order = 1},
  [278283] = {kind = "raid", journalInstanceID = 1320, bossName = "Entombed Sentinels",      order = 2},
  [278286] = {kind = "raid", journalInstanceID = 1320, bossName = "The Lost Explorers",      order = 3},
  [278287] = {kind = "raid", journalInstanceID = 1320, bossName = "Vashnik the Malignant",   order = 4},
  [278288] = {kind = "raid", journalInstanceID = 1320, bossName = "Sszorak",                 order = 5},
  [278289] = {kind = "raid", journalInstanceID = 1320, bossName = "The Twin Fangs",          order = 6},
  [278290] = {kind = "raid", journalInstanceID = 1320, bossName = "The Coiled Altar",        order = 7},
  [278284] = {kind = "raid", journalInstanceID = 1320, bossName = "Ula'tek",                 order = 8},

  -- The Tidebound Grotto (journalInstanceID 1317)
  [274708] = {kind = "raid", journalInstanceID = 1317, bossName = "Nymrissa Wavecaller", order = 1},

  -- Dungeons (journalInstanceID from Data/MythicPlus.lua)
  [279618] = {kind = "dungeon", journalInstanceID = 1322}, -- Altar of Fangs
  [279619] = {kind = "dungeon", journalInstanceID = 1309}, -- The Blinding Vale
  [279620] = {kind = "dungeon", journalInstanceID = 1311}, -- Den of Nalorakk
  [279621] = {kind = "dungeon", journalInstanceID = 1041}, -- Kings' Rest
  [279622] = {kind = "dungeon", journalInstanceID = 1202}, -- Ruby Life Pools
  [279623] = {kind = "dungeon", journalInstanceID = 1304}, -- Murder Row
  [279624] = {kind = "dungeon", journalInstanceID = 1030}, -- Temple of Sethraliss
  [279625] = {kind = "dungeon", journalInstanceID = 1313}, -- Voidscar Arena
}
