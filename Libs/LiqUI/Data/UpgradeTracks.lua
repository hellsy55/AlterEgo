---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI or not LiqUI.Data then
  return
end

---@class LiqUI_Data
local Data = LiqUI.Data
local TableForEach = LiqUI.Utils.TableForEach
local TableGet = LiqUI.Utils.TableGet
local CRAFTED_QUALITY_STEPS = 5

---@type LiqUI_UpgradeSeason[]
Data.upgradeSeasons = {
  {
    seasonID = 17,
    seasonDisplayID = 1,
    maxUpgradeLevel = 289,
    tracks = {
      {kind = "crest", name = "Adventurer", maxLevel = 237, bonusIDs = {12769, 12770, 12771, 12772, 12773, 12774}},
      {kind = "crest", name = "Veteran", maxLevel = 250, bonusIDs = {12777, 12778, 12779, 12780, 12781, 12782}},
      {kind = "crest", name = "Champion", maxLevel = 263, bonusIDs = {12785, 12786, 12787, 12788, 12789, 12790}},
      {kind = "crest", name = "Hero", maxLevel = 276, bonusIDs = {12793, 12794, 12795, 12796, 12797, 12798}},
      {kind = "crest", name = "Myth", maxLevel = 289, bonusIDs = {12801, 12802, 12803, 12804, 12805, 12806}},
      {kind = "label", name = "Sporefused: Veteran", maxLevel = 259, bonusIDs = {13789}},
      {kind = "label", name = "Sporefused: Champion", maxLevel = 272, bonusIDs = {13788}},
      {kind = "label", name = "Sporefused: Hero", maxLevel = 285, bonusIDs = {13787}},
      {kind = "label", name = "Sporefused: Myth", maxLevel = 298, bonusIDs = {13786}},
      {kind = "label", name = "Ascendant Voidforged: Hero", maxLevel = 285, bonusIDs = {13653}},
      {kind = "label", name = "Ascendant Voidforged: Myth", maxLevel = 298, bonusIDs = {13654}},
      {kind = "label", name = "Ascendant Voidforged", maxLevel = 295, bonusIDs = {13655}},
    },
  },
  {
    seasonID = 18,
    seasonDisplayID = 2,
    maxUpgradeLevel = 334,
    tracks = {
      {kind = "crest", name = "Adventurer", maxLevel = 282, bonusIDs = {12817, 12818, 12819, 12820, 12821, 12822}},
      {kind = "crest", name = "Veteran", maxLevel = 295, bonusIDs = {12825, 12826, 12827, 12828, 12829, 12830}},
      {kind = "crest", name = "Champion", maxLevel = 308, bonusIDs = {12833, 12834, 12835, 12836, 12837, 12838}},
      {kind = "crest", name = "Hero", maxLevel = 321, bonusIDs = {12841, 12842, 12843, 12844, 12845, 12846}},
      {kind = "crest", name = "Myth", maxLevel = 334, bonusIDs = {12849, 12850, 12851, 12852, 12853, 12854}},
    },
  },
}

---@type table<number, LiqUI_CraftedItemLevelBonus>
Data.craftedItemLevelBonusIDs = {
  [12066] = {seasonID = 17, itemLevel = 246, name = "Radiance Crafted"},
  [13621] = {seasonID = 17, itemLevel = 259},
  [13622] = {seasonID = 17, itemLevel = 272},
  [13751] = {seasonID = 18, itemLevel = 292, name = "Tidal Crafted"},
  [13835] = {seasonID = 18, itemLevel = 305},
  [13836] = {seasonID = 18, itemLevel = 318},
}

---@type LiqUI_CraftedQualityLadder[]
Data.craftedQualityLadders = {
  {maxOffset = 13, bonusIDs = {9401, 9402, 9403, 9404, 9405, 9623, 9624, 9625, 9626, 9627, 12493, 12494, 12495, 12496, 12497}},
  {maxOffset = 26, bonusIDs = {9628, 9629, 9630, 9631, 9632, 12498, 12499, 12500, 12501, 12502}},
}

---@param bonusID number
---@return LiqUI_CraftedQualityLadder|nil
---@return number|nil
local function getCraftedQualityLadder(bonusID)
  local ladders = Data:GetCraftedQualityLadders()
  for ladderIndex = 1, #ladders do
    local ladder = ladders[ladderIndex]
    for bonusIndex = 1, #ladder.bonusIDs do
      if ladder.bonusIDs[bonusIndex] == bonusID then
        return ladder, ((bonusIndex - 1) % CRAFTED_QUALITY_STEPS) + 1
      end
    end
  end
  return nil
end

local function ensureUpgradeBonusIndex()
  if Data.cache.upgradeByBonusID then
    return
  end
  ---@type table<number, LiqUI_UpgradeBonusIndex>
  local index = {}
  TableForEach(Data:GetUpgradeSeasons(), function(season)
    TableForEach(season.tracks, function(track)
      for bonusIndex = 1, #track.bonusIDs do
        local bonusID = track.bonusIDs[bonusIndex]
        local existing = index[bonusID]
        if not existing or track.maxLevel > existing.track.maxLevel then
          ---@type LiqUI_UpgradeBonusIndex
          local entry = {track = track, season = season, index = bonusIndex}
          index[bonusID] = entry
        end
      end
    end)
  end)
  Data.cache.upgradeByBonusID = index
end

---@return LiqUI_UpgradeSeason[]
function Data:GetUpgradeSeasons()
  ---@type LiqUI_UpgradeSeason[]
  local seasons = {}
  TableForEach(self.upgradeSeasons, function(season)
    table.insert(seasons, season)
  end)
  return seasons
end

---@return table<number, LiqUI_CraftedItemLevelBonus>
function Data:GetCraftedItemLevelBonusIDs()
  ---@type table<number, LiqUI_CraftedItemLevelBonus>
  local bonuses = {}
  TableForEach(self.craftedItemLevelBonusIDs, function(bonus, bonusID)
    bonuses[bonusID] = bonus
  end)
  return bonuses
end

---@return LiqUI_CraftedQualityLadder[]
function Data:GetCraftedQualityLadders()
  ---@type LiqUI_CraftedQualityLadder[]
  local ladders = {}
  TableForEach(self.craftedQualityLadders, function(ladder)
    table.insert(ladders, ladder)
  end)
  return ladders
end

---@param bonusID number
---@return LiqUI_UpgradeTrack|nil
---@return LiqUI_UpgradeSeason|nil
---@return number|nil
function Data:GetUpgradeTrackForBonusID(bonusID)
  ensureUpgradeBonusIndex()
  local byBonusID = self.cache.upgradeByBonusID
  if not byBonusID then
    return nil
  end
  local entry = byBonusID[bonusID]
  if not entry then
    return nil
  end
  return entry.track, entry.season, entry.index
end

---@param bonusID number
---@return number|nil
function Data:GetUpgradeMaxLevel(bonusID)
  local track = self:GetUpgradeTrackForBonusID(bonusID)
  if not track then
    return nil
  end
  return track.maxLevel
end

---@param bonusIDs number[]
---@return number|nil
function Data:GetUpgradeMaxLevelFromBonusIDs(bonusIDs)
  if not bonusIDs then
    return nil
  end

  local craftedBases = self:GetCraftedItemLevelBonusIDs()
  local maxLevel = nil
  local craftedBaseLevel = nil
  local craftedMaxOffset = nil
  TableForEach(bonusIDs, function(bonusID)
    local trackMaxLevel = self:GetUpgradeMaxLevel(bonusID)
    if trackMaxLevel and (not maxLevel or trackMaxLevel > maxLevel) then
      maxLevel = trackMaxLevel
    end

    local craftedBase = craftedBases[bonusID]
    if craftedBase and (not craftedBaseLevel or craftedBase.itemLevel > craftedBaseLevel) then
      craftedBaseLevel = craftedBase.itemLevel
    end

    local qualityLadder = getCraftedQualityLadder(bonusID)
    if qualityLadder and (not craftedMaxOffset or qualityLadder.maxOffset > craftedMaxOffset) then
      craftedMaxOffset = qualityLadder.maxOffset
    end
  end)

  if craftedBaseLevel then
    local craftedMaxLevel = craftedBaseLevel + (craftedMaxOffset or 0)
    if not maxLevel or craftedMaxLevel > maxLevel then
      maxLevel = craftedMaxLevel
    end
  end
  return maxLevel
end

---@return number
function Data:GetCurrentMaxUpgradeLevel()
  local seasonID = self:GetCurrentSeason()
  local upgradeSeasons = self:GetUpgradeSeasons()
  local season = TableGet(upgradeSeasons, "seasonID", seasonID)
  if season then
    return season.maxUpgradeLevel
  end
  local lastSeason = upgradeSeasons[#upgradeSeasons]
  if lastSeason then
    return lastSeason.maxUpgradeLevel
  end
  return 0
end

---@param bonusID number
---@return number|nil
function Data:GetCraftedQuality(bonusID)
  local _, quality = getCraftedQualityLadder(bonusID)
  return quality
end

---@param bonusID number
---@return number|nil
function Data:GetCraftedSeason(bonusID)
  local craftedBase = self:GetCraftedItemLevelBonusIDs()[bonusID]
  if not craftedBase then
    return nil
  end
  return craftedBase.seasonID
end
