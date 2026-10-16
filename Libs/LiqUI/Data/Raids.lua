---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI or not LiqUI.Data then
  return
end

---@class LiqUI_Data
local Data = LiqUI.Data

local TableFilter = LiqUI.Utils.TableFilter
local TableForEach = LiqUI.Utils.TableForEach

---@type LiqUI_Raid[]
Data.raids = {
  {seasonID = 17, seasonDisplayID = 1, instanceID = 2912, journalInstanceID = 1307, order = 1, numEncounters = 6, encounters = {}, loot = {}, modifiedInstanceInfo = nil, abbr = "VS",  name = "The Voidspire"},
  {seasonID = 17, seasonDisplayID = 1, instanceID = 2913, journalInstanceID = 1308, order = 2, numEncounters = 2, encounters = {}, loot = {}, modifiedInstanceInfo = nil, abbr = "MQD", name = "March on Quel'Danas"},
  {seasonID = 17, seasonDisplayID = 1, instanceID = 2939, journalInstanceID = 1314, order = 3, numEncounters = 1, encounters = {}, loot = {}, modifiedInstanceInfo = nil, abbr = "DR",  name = "The Dreamrift"},
  {seasonID = 17, seasonDisplayID = 1, instanceID = 1592, journalInstanceID = 1305, order = 4, numEncounters = 1, encounters = {}, loot = {}, modifiedInstanceInfo = nil, abbr = "SF",  name = "Sporefall"},
  {seasonID = 18, seasonDisplayID = 2, instanceID = 2987, journalInstanceID = 1317, order = 1, numEncounters = 1, encounters = {}, loot = {}, modifiedInstanceInfo = nil, abbr = "TG",  name = "The Tidebound Grotto"},
  {seasonID = 18, seasonDisplayID = 2, instanceID = 3004, journalInstanceID = 1320, order = 2, numEncounters = 8, encounters = {}, loot = {}, modifiedInstanceInfo = nil, abbr = "VA",  name = "The Venomous Abyss"},
  {seasonID = 18, seasonDisplayID = 2, instanceID = 3095, journalInstanceID = 1324, order = 3, numEncounters = 1, encounters = {}, loot = {}, modifiedInstanceInfo = nil, abbr = "UK",  name = "The Unbinding of Kith'ix"},
}

---@type LiqUI_RaidDifficulty[]
Data.raidDifficulties = {
  {id = DifficultyUtil.ID.PrimaryRaidLFR, order = 1, abbr = "L", name = "Looking For Raid", short = "LFR", color = UNCOMMON_GREEN_COLOR},
  {id = DifficultyUtil.ID.PrimaryRaidNormal, order = 2, abbr = "N", name = "Normal", color = RARE_BLUE_COLOR},
  {id = DifficultyUtil.ID.PrimaryRaidHeroic, order = 3, abbr = "H", name = "Heroic", color = EPIC_PURPLE_COLOR},
  {id = DifficultyUtil.ID.PrimaryRaidMythic, order = 4, abbr = "M", name = "Mythic", color = LEGENDARY_ORANGE_COLOR},
}

---@return LiqUI_Raid[]
function Data:GetRaids()
  local seasonID = self:GetCurrentSeason()
  local raids = TableFilter(self.raids, function(dataRaid)
    return dataRaid.seasonID == seasonID
  end)

  table.sort(raids, function(a, b)
    return a.order < b.order
  end)

  return raids
end

---@return LiqUI_RaidDifficulty[]
function Data:GetRaidDifficulties()
  ---@type LiqUI_RaidDifficulty[]
  local difficulties = {}
  TableForEach(self.raidDifficulties, function(difficulty)
    table.insert(difficulties, difficulty)
  end)
  table.sort(difficulties, function(a, b)
    return a.order < b.order
  end)
  return difficulties
end
