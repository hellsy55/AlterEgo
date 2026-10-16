---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI then
  return
end

LiqUI.Data = LiqUI.Data or {
  gameDataLoaded = false,
  cache = {
    seasonID = nil,
    seasonDisplayID = nil,
    classes = {},
    upgradeByBonusID = nil,
  },
  dungeons = {},
  raids = {},
  raidDifficulties = {},
  seasons = {},
  expansions = {},
  inventorySlots = {},
  upgradeSeasons = {},
  craftedItemLevelBonusIDs = {},
  craftedQualityLadders = {},
}

---@class LiqUI_Data
local Data = LiqUI.Data
local TableForEach = LiqUI.Utils.TableForEach

---@param journalEncounterID number
---@return LiqUI_Encounter|nil
function Data:GetJournalEncounterByID(journalEncounterID)
  ---@type LiqUI_Encounter|nil
  local encounter = nil
  local raids = self:GetRaids()
  local dungeons = self:GetDungeons()

  TableForEach(raids, function(raid)
    TableForEach(raid.encounters or {}, function(raidEncounter)
      if raidEncounter.journalEncounterID == journalEncounterID then
        encounter = raidEncounter
        return
      end
    end)
    if encounter then
      return
    end
  end)

  TableForEach(dungeons, function(dungeon)
    TableForEach(dungeon.encounters or {}, function(dungeonEncounter)
      if dungeonEncounter.journalEncounterID == journalEncounterID then
        encounter = dungeonEncounter
        return
      end
    end)
    if encounter then
      return
    end
  end)

  return encounter
end

---@param journalInstanceID number
---@return LiqUI_Raid|LiqUI_Dungeon|nil
function Data:GetJournalInstanceByID(journalInstanceID)
  local raids = self:GetRaids()
  local dungeons = self:GetDungeons()
  ---@type LiqUI_Raid|LiqUI_Dungeon|nil
  local instance = nil
  TableForEach(raids, function(raid)
    if raid.journalInstanceID == journalInstanceID then
      instance = raid
      return
    end
  end)
  TableForEach(dungeons, function(dungeon)
    if dungeon.journalInstanceID == journalInstanceID then
      instance = dungeon
      return
    end
  end)
  return instance
end

function Data:loadGameData()
  TableForEach(self:GetRaids(), function(raid)
    local encounterIndex = 1
    EJ_SelectInstance(raid.journalInstanceID)
    local _, _, bossID = EJ_GetEncounterInfoByIndex(encounterIndex, raid.journalInstanceID)
    while bossID do
      local name, description, journalEncounterID, journalEncounterSectionID, journalLink, journalInstanceID, instanceEncounterID, instanceID = EJ_GetEncounterInfoByIndex(encounterIndex, raid.journalInstanceID)
      local iconImage
      if journalEncounterID then
        EJ_SelectEncounter(journalEncounterID)
        iconImage = select(5, EJ_GetCreatureInfo(1))
      end
      ---@type LiqUI_Encounter
      local encounter = {
        index = encounterIndex,
        name = name,
        description = description,
        journalInstanceID = journalInstanceID,
        journalEncounterID = journalEncounterID,
        iconImage = iconImage,
        journalEncounterSectionID = journalEncounterSectionID,
        journalLink = journalLink,
        instanceID = instanceID,
        instanceEncounterID = instanceEncounterID,
      }
      raid.encounters[encounterIndex] = encounter
      encounterIndex = encounterIndex + 1
      _, _, bossID = EJ_GetEncounterInfoByIndex(encounterIndex, raid.journalInstanceID)
    end
    raid.modifiedInstanceInfo = C_ModifiedInstance.GetModifiedInstanceInfoFromMapID(raid.instanceID)
  end)

  TableForEach(self:GetDungeons(), function(dungeon)
    local dungeonName, _, dungeonTimeLimit, dungeonTexture = C_ChallengeMode.GetMapUIInfo(dungeon.challengeModeID)
    dungeon.name = dungeonName
    dungeon.time = dungeonTimeLimit
    dungeon.texture = dungeon.texture ~= 0 and dungeonTexture or "Interface/Icons/achievement_bg_wineos_underxminutes"

    local encounterIndex = 1
    EJ_SelectInstance(dungeon.journalInstanceID)
    dungeon.description = select(2, EJ_GetInstanceInfo())
    local _, _, bossID = EJ_GetEncounterInfoByIndex(encounterIndex, dungeon.journalInstanceID)
    while bossID do
      local name, description, journalEncounterID, journalEncounterSectionID, journalLink, journalInstanceID, instanceEncounterID, instanceID = EJ_GetEncounterInfoByIndex(encounterIndex, dungeon.journalInstanceID)
      ---@type LiqUI_Encounter
      local encounter = {
        index = encounterIndex,
        name = name,
        description = description,
        journalEncounterID = journalEncounterID,
        journalEncounterSectionID = journalEncounterSectionID,
        journalLink = journalLink,
        journalInstanceID = journalInstanceID,
        instanceEncounterID = instanceEncounterID,
        instanceID = instanceID,
      }
      dungeon.encounters[encounterIndex] = encounter
      encounterIndex = encounterIndex + 1
      _, _, bossID = EJ_GetEncounterInfoByIndex(encounterIndex, dungeon.journalInstanceID)
    end
  end)

  for classID = 1, GetNumClasses() do
    local className, classFile = GetClassInfo(classID)
    if className and classFile then
      ---@type LiqUI_Specialization[]
      local specs = {}
      for specIndex = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do
        local specID, name, _, icon = GetSpecializationInfoForClassID(classID, specIndex)
        if specID then
          ---@type LiqUI_Specialization
          local spec = {specID = specID, name = name, icon = icon}
          table.insert(specs, spec)
        end
      end
      ---@type LiqUI_Class
      local classEntry = {id = classID, name = className, file = classFile, specs = specs}
      self.cache.classes[classID] = classEntry
    end
  end
end

---@param classID number
---@return LiqUI_Specialization[]
function Data:GetClassSpecs(classID)
  local classEntry = self.cache.classes[classID]
  return classEntry and classEntry.specs or {}
end

---@return boolean
function Data:RequestGameData()
  local seasonID = C_MythicPlus.GetCurrentSeason()
  if seasonID == nil or seasonID <= 0 then
    return false
  end
  if not self.gameDataLoaded then
    self:loadGameData()
    self.gameDataLoaded = true
  end
  return true
end

---@param onReady fun()
function Data:EnsureGameData(onReady)
  if self:RequestGameData() then
    onReady()
    return
  end
  C_Timer.After(1, function()
    Data:EnsureGameData(onReady)
  end)
end
