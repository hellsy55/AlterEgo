---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI or not LiqUI.Data then
  return
end

LiqUI.EJScan = LiqUI.EJScan or {
  hosts = {},
  itemCache = {
    seasonID = 0,
    build = "",
    version = 0,
    lastUpdate = 0,
    items = {},
  },
  state = nil,
  counter = 0,
}

---@class LiqUI_EJScan
local EJScan = LiqUI.EJScan
local Data = LiqUI.Data
local Events = LiqUI.Events
local Utils = LiqUI.Utils
local _, clientBuild = GetBuildInfo()
-- Increase when the instance list or this cache changes.
local version = 5

---@param bag LiqUI_EJScanCache
---@param seasonID number
---@return boolean
local function cacheBagIsComplete(bag, seasonID)
  if bag.seasonID ~= seasonID or bag.lastUpdate <= 0 or bag.build ~= clientBuild or bag.version ~= version then
    return false
  end
  local hasUnloadedRow = false
  Utils.TableForEach(bag.items, function(row)
    if row.itemID and row.loaded == false then
      hasUnloadedRow = true
    end
  end)
  return not hasUnloadedRow
end

---@param dest LiqUI_EJScanCache
---@param source LiqUI_EJScanCache
local function copyCache(dest, source)
  dest.seasonID = source.seasonID
  dest.build = source.build
  dest.version = source.version
  dest.lastUpdate = source.lastUpdate
  dest.items = Utils.TableCopy(source.items)
end

local function syncBoundCaches()
  if EJScan.state then
    return
  end
  local seasonID = Data:GetCurrentSeason()
  if seasonID <= 0 then
    return
  end
  ---@type LiqUI_EJScanCache|nil
  local winner = nil
  if cacheBagIsComplete(EJScan.itemCache, seasonID) then
    winner = EJScan.itemCache
  end
  Utils.TableForEach(EJScan.hosts, function(host)
    if cacheBagIsComplete(host.storage, seasonID) then
      if not winner or host.storage.lastUpdate > winner.lastUpdate then
        winner = host.storage
      end
    end
  end)
  if not winner then
    return
  end
  local newestCache = winner
  if newestCache ~= EJScan.itemCache then
    copyCache(EJScan.itemCache, newestCache)
  end
  Utils.TableForEach(EJScan.hosts, function(host)
    local bag = host.storage
    if bag.seasonID ~= newestCache.seasonID or bag.lastUpdate < newestCache.lastUpdate then
      copyCache(bag, newestCache)
    end
  end)
end

---@param event LiqUI_EJScanEvent
local function eventFire(event)
  Utils.TableForEach(EJScan.hosts, function(host)
    if host.onEvent then
      host.onEvent(event)
    end
  end)
end

-- Spread work across frames; 0 queues the entire scan into one burst and tanks FPS.
local ScanScheduleDelay = 0.05
local CacheLoadTimeoutSec = 20
local JournalTabOverview = 1
local JournalTabLoot = 2
local ScanFilterSlotNone = Enum.ItemSlotFilterType.NoFilter
local ScanFilterAllClassId = 0
local ScanFilterAllSpecId = 0
local ScanMinProgressSteps = 1
---@return boolean
local function journalHide()
  if EncounterJournal and EncounterJournal:IsShown() then
    HideUIPanel(EncounterJournal)
    return true
  end
  return false
end

---@param wasShown boolean
local function journalShow(wasShown)
  if wasShown and EncounterJournal then
    ShowUIPanel(EncounterJournal)
  end
end

---@param instanceType LiqUI_EJScanInstanceType
local function journalSetDifficulty(instanceType)
  if instanceType == "raid" then
    EJ_SetDifficulty(DifficultyUtil.ID.PrimaryRaidMythic)
  else
    EJ_SetDifficulty(DifficultyUtil.ID.DungeonMythic)
  end
end

local function cacheNotifyReady()
  ---@type LiqUI_EJScanEvent
  local event = { name = "ready" }
  eventFire(event)
end

---@param state LiqUI_EJScanState
---@param instanceType LiqUI_EJScanInstanceType
---@param instances (LiqUI_Dungeon|LiqUI_Raid)[]
local function appendScanInstances(state, instanceType, instances)
  Utils.TableForEach(instances, function(instance)
    local journalInstanceID = instance.journalInstanceID
    if journalInstanceID and journalInstanceID > 0 then
      ---@type LiqUI_EJScanInstance
      local instanceEntry = { instance = instance, instanceType = instanceType }
      table.insert(state.instances, instanceEntry)
    end
  end)
end

local function journalLoadUi()
  if not EncounterJournal and EncounterJournal_LoadUI then
    EncounterJournal_LoadUI()
  end
end

local function journalSelectTier()
  local numTiers = EJ_GetNumTiers and EJ_GetNumTiers() or 0
  if numTiers > 0 then
    EJ_SelectTier(numTiers)
  end
end

local function scanFilterRefreshUi()
  ---@type fun(self: Frame)|nil
  local onFilterChanged = _G.EncounterJournal_OnFilterChanged
  if EncounterJournal and onFilterChanged then
    onFilterChanged(EncounterJournal)
  end
end

---@param refreshUI boolean|nil When false, only update C API state (skip EncounterJournal_LootUpdate).
local function scanFilterSlotClear(refreshUI)
  C_EncounterJournal.ResetSlotFilter()
  C_EncounterJournal.SetSlotFilter(ScanFilterSlotNone)
  if refreshUI ~= false then
    scanFilterRefreshUi()
  end
end

---@param encounterInfo EncounterJournalEncounterFrameInfo?
---@return number|nil
local function getEncounterInfoTab(encounterInfo)
  if not encounterInfo then
    return nil
  end
  ---@type LiqUI_EJScanEncounterInfo
  local info = encounterInfo
  return info.tab
end

--- Loot tab pins slot filter state; leave overview even when EJ is hidden (e.g. closed on loot tab).
local function journalSetTab()
  journalLoadUi()
  if not EncounterJournal then
    return
  end
  local encounterInfo = EncounterJournal.encounter and EncounterJournal.encounter.info
  if getEncounterInfoTab(encounterInfo) ~= JournalTabLoot then
    return
  end
  ---@type fun(tabType: number)|nil
  local setEncounterTab = _G.EncounterJournal_SetTab
  if setEncounterTab then
    setEncounterTab(JournalTabOverview)
  end
end

--- Saved filters + hidden loot tab can leave a non-NoFilter slot on the C API until refreshed.
local function journalPrepareFilters()
  journalSetTab()
  scanFilterSlotClear()
end

local function journalPrepare()
  journalSelectTier()
  journalPrepareFilters()
  EJ_ClearSearch()
  EJ_EndSearch()
end

---@param instanceType LiqUI_EJScanInstanceType
---@param journalInstanceID number
local function journalSelectInstanceTab(instanceType, journalInstanceID)
  journalLoadUi()
  ---@type fun(instanceID: number)|nil
  local selectInstanceTab = _G.EJ_ContentTab_SelectAppropriateInstanceTab
  if selectInstanceTab then
    selectInstanceTab(journalInstanceID)
    return
  end
  if not EncounterJournal then
    return
  end
  if instanceType == "raid" and EncounterJournal.raidsTab then
    EJ_ContentTab_Select(EncounterJournal.raidsTab:GetID())
  elseif EncounterJournal.dungeonsTab then
    EJ_ContentTab_Select(EncounterJournal.dungeonsTab:GetID())
  end
end

---@param field string
---@param value number|nil
local function setJournalID(field, value)
  if EncounterJournal then
    EncounterJournal[field] = value
  end
end

---@return number|nil
local function journalGetInstanceId()
  if not EncounterJournal then
    return nil
  end
  ---@type number?
  local instanceID = EncounterJournal.instanceID
  if instanceID and instanceID > 0 then
    return instanceID
  end
  return nil
end

--- Addons cannot call C_EncounterJournal.OnOpen (protected). ShowUIPanel lets Blizzard run OnShow/OnOpen.
---@return boolean primed True if we showed the panel and scan should hide it again when the user had EJ closed.
local function journalShowForSync()
  journalLoadUi()
  if not EncounterJournal or EncounterJournal:IsShown() then
    return false
  end
  ShowUIPanel(EncounterJournal)
  return true
end

--- API + frame IDs only; no boss list / portrait / tab UI work.
---@param journalInstanceID number
local function journalSelectInstance(journalInstanceID)
  setJournalID("instanceID", journalInstanceID)
  setJournalID("encounterID", nil)
  EJ_SelectInstance(journalInstanceID)
end

--- Full Blizzard display; only for restore or when API sync fails.
---@param journalInstanceID number
local function journalDisplayInstance(journalInstanceID)
  ---@type fun(instanceID: number, noButton: boolean|nil)|nil
  local displayInstance = _G.EncounterJournal_DisplayInstance
  if displayInstance then
    displayInstance(journalInstanceID, true)
    return
  end
  journalSelectInstance(journalInstanceID)
end

---@param journalInstanceID number
---@param instanceType LiqUI_EJScanInstanceType
local function journalSyncInstance(journalInstanceID, instanceType)
  journalLoadUi()
  journalSelectInstanceTab(instanceType, journalInstanceID)
  journalSetDifficulty(instanceType)

  journalSelectInstance(journalInstanceID)
  if journalGetInstanceId() == journalInstanceID then
    return
  end

  journalDisplayInstance(journalInstanceID)
  if journalGetInstanceId() == journalInstanceID then
    return
  end

  local primed = journalShowForSync()
  if primed and EJScan.state then
    EJScan.state.journalPrimedForScan = true
  end
  journalDisplayInstance(journalInstanceID)

  if primed and EJScan.state and not EJScan.state.journalUIWasShown and EncounterJournal and EncounterJournal:IsShown() then
    HideUIPanel(EncounterJournal)
  end
end

---@param journalEncounterID number
local function journalSelectEncounter(journalEncounterID)
  setJournalID("encounterID", journalEncounterID)
  EJ_SelectEncounter(journalEncounterID)
end

---@param journalEncounterID number
local function journalDisplayEncounter(journalEncounterID)
  ---@type fun(encounterID: number, noButton: boolean|nil)|nil
  local displayEncounter = _G.EncounterJournal_DisplayEncounter
  if displayEncounter then
    displayEncounter(journalEncounterID, true)
    return
  end
  journalSelectEncounter(journalEncounterID)
end

---@param cache LiqUI_EJScanCache
---@param lootInfo EncounterJournalItemInfo
---@param journalInstanceID number
---@param instance LiqUI_Dungeon|LiqUI_Raid
---@param instanceType LiqUI_EJScanInstanceType
---@param journalEncounterID number|nil
---@param specID number|nil
local function scanAddItem(cache, lootInfo, journalInstanceID, instance, instanceType, journalEncounterID, specID)
  if not lootInfo or not lootInfo.itemID then
    return
  end

  local item = cache.items[lootInfo.itemID]
  if not item then
    ---@type LiqUI_EJScanCacheItem
    item = {
      itemID = lootInfo.itemID,
      name = lootInfo.name or "",
      link = lootInfo.link,
      quality = Enum.ItemQuality.Common,
      slot = lootInfo.slot or "",
      icon = lootInfo.icon,
      journalInstanceID = journalInstanceID,
      instanceName = instance.name or instance.abbr or "",
      instanceType = instanceType,
      journalEncounterIDs = {},
      specs = {},
      stats = {},
    }
    cache.items[lootInfo.itemID] = item
  elseif (not item.name or item.name == "") and lootInfo.name and lootInfo.name ~= "" then
    item.name = lootInfo.name
  end

  if lootInfo.filterType then
    item.filterType = lootInfo.filterType
  end
  if lootInfo.link and not item.link then
    item.link = lootInfo.link
  end
  if lootInfo.icon and not item.icon then
    item.icon = lootInfo.icon
  end
  if lootInfo.slot and lootInfo.slot ~= "" and item.slot == "" then
    item.slot = lootInfo.slot
  end

  if journalEncounterID then
    item.journalEncounterIDs = item.journalEncounterIDs or {}
    item.journalEncounterIDs[journalEncounterID] = true
  end
  if specID then
    item.specs[specID] = true
  end
end

---@return LiqUI_EJScanJournalFilters
local function scanFilterSave()
  journalLoadUi()

  local lootClassID, lootSpecID = EJ_GetLootFilter()
  ---@type LiqUI_EJScanJournalFilters
  local filters = {
    tier = EJ_GetCurrentTier(),
    difficultyID = EJ_GetDifficulty(),
    lootClassID = lootClassID,
    lootSpecID = lootSpecID,
    slotFilter = C_EncounterJournal.GetSlotFilter(),
    instanceID = nil,
    encounterID = nil,
    searchText = "",
    hadSearch = false,
    selectedTab = nil,
    encounterTab = nil,
  }

  if EncounterJournal then
    ---@type number?
    local instanceID = EncounterJournal.instanceID
    if instanceID and instanceID > 0 then
      filters.instanceID = instanceID
    end
    ---@type number?
    local encounterID = EncounterJournal.encounterID
    if encounterID and encounterID > 0 then
      filters.encounterID = encounterID
    end
    local encounterFrame = EncounterJournal.encounter
    local encounterInfo = encounterFrame and encounterFrame.info
    if encounterInfo and encounterFrame:IsShown() then
      filters.encounterTab = getEncounterInfoTab(encounterInfo)
    end
    if EncounterJournal.selectedTab then
      filters.selectedTab = EncounterJournal.selectedTab
    end
    if EncounterJournal.searchBox then
      local searchText = EncounterJournal.searchBox:GetText()
      if searchText and searchText ~= "" then
        filters.searchText = searchText
        filters.hadSearch = true
      end
    end
  end

  return filters
end

---@param filters LiqUI_EJScanJournalFilters|nil
local function scanFilterRestore(filters)
  if not filters then
    return
  end

  journalLoadUi()

  if filters.tier and filters.tier > 0 then
    EJ_SelectTier(filters.tier)
  end
  if filters.difficultyID and filters.difficultyID > 0 then
    EJ_SetDifficulty(filters.difficultyID)
  end
  if filters.lootClassID ~= nil and filters.lootSpecID ~= nil then
    EJ_SetLootFilter(filters.lootClassID, filters.lootSpecID)
  else
    EJ_ResetLootFilter()
  end

  if filters.selectedTab then
    EJ_ContentTab_Select(filters.selectedTab)
  end

  if filters.instanceID and filters.instanceID > 0 then
    journalDisplayInstance(filters.instanceID)
    if filters.encounterID and filters.encounterID > 0 then
      journalDisplayEncounter(filters.encounterID)
    end
    if filters.encounterTab then
      ---@type fun(tabType: number)|nil
      local setEncounterTab = _G.EncounterJournal_SetTab
      if setEncounterTab then
        setEncounterTab(filters.encounterTab)
      end
    end
  else
    setJournalID("instanceID", nil)
    setJournalID("encounterID", nil)
    ---@type fun()|nil
    local listInstances = _G.EncounterJournal_ListInstances
    if listInstances then
      listInstances()
    elseif EncounterJournal then
      EncounterJournal.encounter:Hide()
      EncounterJournal.instanceSelect:Show()
    end
  end

  C_EncounterJournal.SetSlotFilter(filters.slotFilter)
  scanFilterRefreshUi()

  if not filters.instanceID or filters.instanceID <= 0 then
    if EncounterJournal then
      setJournalID("instanceID", nil)
      setJournalID("encounterID", nil)
      EncounterJournal.encounter:Hide()
      EncounterJournal.instanceSelect:Show()
    end
  end

  if filters.hadSearch and filters.searchText ~= "" then
    if EncounterJournal and EncounterJournal.searchBox then
      EncounterJournal.searchBox:SetText(filters.searchText)
    else
      EJ_SetSearch(filters.searchText)
    end
  else
    EJ_ClearSearch()
    EJ_EndSearch()
    if EncounterJournal and EncounterJournal.searchBox then
      EncounterJournal.searchBox:SetText("")
      EncounterJournal.searchBox:Close()
      if EncounterJournal.searchResults then
        EncounterJournal.searchResults:Hide()
      end
    end
  end
end

---@param state LiqUI_EJScanState
local function journalRestore(state)
  if state.journalPrimedForScan and not state.journalUIWasShown and EncounterJournal and EncounterJournal:IsShown() then
    HideUIPanel(EncounterJournal)
  end
  journalShow(state.journalUIWasShown)
  scanFilterRestore(state.journalFilters)
end

---@param cache LiqUI_EJScanCache
---@return integer loadedCount
---@return integer totalCount
local function cacheCountProgress(cache)
  local loadedCount = 0
  local totalCount = 0
  Utils.TableForEach(cache.items, function(row)
    if row.itemID then
      totalCount = totalCount + 1
      if row.loaded then
        loadedCount = loadedCount + 1
      end
    end
  end)
  return loadedCount, totalCount
end

---@param state LiqUI_EJScanState
local function cacheLoaded(state)
  if not EJScan.state or EJScan.state.scanId ~= state.scanId then
    return
  end
  local cache = state.cache
  Utils.TableForEach(cache.items, function(row)
    if row.itemID then
      row.loaded = true
    end
  end)
  cache.build = clientBuild
  cache.version = version
  cache.lastUpdate = time()
  EJScan.state = nil
  syncBoundCaches()
  cacheNotifyReady()
end

---@param itemID number
---@param state LiqUI_EJScanState
local function cacheOnItemLoad(itemID, state)
  local cache = state.cache
  local row = cache.items[itemID]
  if row then
    if (not row.name or row.name == "") then
      row.name = C_Item.GetItemInfo(itemID) or row.name
    end
    row.quality = C_Item.GetItemQualityByID(itemID) or row.quality
    if row.link and next(row.stats) == nil then
      ---@type table<string, number>?
      local rawStats = C_Item.GetItemStats(row.link)
      if rawStats then
        for statKey, value in pairs(rawStats) do
          if type(statKey) == "string" and statKey:find("^ITEM_MOD_", 1) and type(value) == "number" and value > 0 then
            row.stats[statKey] = value
          end
        end
      end
    end

    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    row.equipLoc = equipLoc
    row.classID = classID
    row.subclassID = subclassID
    row.loaded = true
  end

  if not EJScan.state or EJScan.state.scanId ~= state.scanId then
    return
  end

  local loadedCount, totalCount = cacheCountProgress(cache)
  if loadedCount < totalCount then
    ---@type LiqUI_EJScanEventCounts
    local counts = { done = loadedCount, total = totalCount }
    ---@type LiqUI_EJScanEvent
    local event = {
      name = "loading",
      progress = loadedCount / totalCount,
      counts = counts,
    }
    eventFire(event)
    return
  end
  cacheLoaded(state)
end

---@param state LiqUI_EJScanState
local function cacheLoadItems(state)
  local cache = state.cache
  cache.seasonID = Data:GetCurrentSeason()

  Utils.TableForEach(cache.items, function(row)
    if row.itemID then
      row.loaded = false
    end
  end)

  local _, totalCount = cacheCountProgress(cache)
  if totalCount == 0 then
    cacheLoaded(state)
    return
  end

  ---@type LiqUI_EJScanEventCounts
  local counts = { done = 0, total = totalCount }
  ---@type LiqUI_EJScanEvent
  local event = {
    name = "loading",
    progress = 0,
    counts = counts,
  }
  eventFire(event)

  Utils.TableForEach(cache.items, function(item)
    local itemID = item.itemID
    if itemID then
      Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        cacheOnItemLoad(itemID, state)
      end)
    end
  end)

  C_Timer.After(CacheLoadTimeoutSec, function()
    if not EJScan.state or EJScan.state.scanId ~= state.scanId then
      return
    end
    local timeoutLoadedCount, timeoutTotalCount = cacheCountProgress(cache)
    if timeoutTotalCount == 0 or timeoutLoadedCount >= timeoutTotalCount then
      return
    end
    cacheLoaded(state)
  end)
end

local ScanSchedule

local function onLootDataReceived()
  local state = EJScan.state
  if not state then
    return
  end
  state.lootEvents = state.lootEvents + 1
end

local function lootListenStop()
  Events:UnregisterEvent("EJ_LOOT_DATA_RECIEVED", onLootDataReceived)
end

local function scanFinish()
  local state = EJScan.state
  if not state then
    return
  end
  lootListenStop()
  journalRestore(state)
  cacheLoadItems(state)
end

---@param state LiqUI_EJScanState
local function scanCursorAdvance(state)
  state.encounterIndex = state.encounterIndex + 1

  while state.instanceIndex <= #state.instances do
    local entry = state.instances[state.instanceIndex]
    local encounters = entry.instance.encounters or {}
    if state.encounterIndex <= #encounters then
      return
    end
    state.instanceIndex = state.instanceIndex + 1
    state.encounterIndex = 1
  end
end

local function scanStepSchedule()
  local state = EJScan.state
  if not state then
    return
  end
  local scanId = state.scanId
  C_Timer.After(ScanScheduleDelay, function()
    ScanSchedule(scanId)
  end)
end

---@param expectedScanId number
ScanSchedule = function(expectedScanId)
  local state = EJScan.state
  if not state or state.scanId ~= expectedScanId then
    return
  end

  if state.instanceIndex > #state.instances then
    if state.pass == 1 and state.lootEvents > 0 then
      state.pass = 2
      state.lootEvents = 0
      state.instanceIndex = 1
      state.encounterIndex = 1
      state.step = 0
      state.activeJournalInstanceID = nil
      state.activeJournalEncounterID = nil
      state.activeInstanceType = nil
      state.cache.items = {}
      scanStepSchedule()
      return
    end
    ---@type LiqUI_EJScanEvent
    local event = { name = "complete", progress = 1 }
    eventFire(event)
    scanFinish()
    return
  end

  if #state.classSpecs == 0 then
    scanFinish()
    return
  end

  local entry = state.instances[state.instanceIndex]
  local encounters = entry.instance.encounters or {}
  local encounter = encounters[state.encounterIndex]

  if not encounter
    or not encounter.journalEncounterID
    or not encounter.name
    or encounter.name == "" then
    scanCursorAdvance(state)
    scanStepSchedule()
    return
  end

  do
    local journalInstanceID = entry.instance.journalInstanceID
    local instance = entry.instance
    local instanceType = entry.instanceType
    local cache = state.cache

    if state.activeJournalInstanceID ~= journalInstanceID or state.activeInstanceType ~= instanceType then
      journalSelectInstanceTab(instanceType, journalInstanceID)
      journalSyncInstance(journalInstanceID, instanceType)
      state.activeJournalInstanceID = journalInstanceID
      state.activeInstanceType = instanceType
      state.activeJournalEncounterID = nil
    end

    if state.activeJournalEncounterID ~= encounter.journalEncounterID then
      journalSelectEncounter(encounter.journalEncounterID)
      state.activeJournalEncounterID = encounter.journalEncounterID
    end

    journalSetDifficulty(instanceType)
    scanFilterSlotClear(false)
    EJ_SetLootFilter(ScanFilterAllClassId, ScanFilterAllSpecId)
    for lootIndex = 1, EJ_GetNumLoot() do
      local lootInfo = C_EncounterJournal.GetLootInfoByIndex(lootIndex)
      scanAddItem(cache, lootInfo, journalInstanceID, instance, instanceType, encounter.journalEncounterID, nil)
    end

    for _, classSpec in ipairs(state.classSpecs) do
      EJ_SetLootFilter(classSpec.classID, classSpec.specID)
      for lootIndex = 1, EJ_GetNumLoot() do
        local lootInfo = C_EncounterJournal.GetLootInfoByIndex(lootIndex)
        scanAddItem(cache, lootInfo, journalInstanceID, instance, instanceType, encounter.journalEncounterID, classSpec.specID)
      end
    end
  end

  state.step = state.step + 1
  ---@type LiqUI_EJScanEventInstance
  local instance = {
    journalInstanceID = entry.instance.journalInstanceID,
    name = entry.instance.name,
    instanceType = entry.instanceType,
  }
  ---@type LiqUI_EJScanEvent
  local event = {
    name = "encounter",
    progress = state.step / state.totalSteps,
    instance = instance,
  }
  eventFire(event)

  scanCursorAdvance(state)
  scanStepSchedule()
end

---@param reason string|nil
---@param restoreJournal boolean|nil When false, skip EJ filter restore (e.g. immediately starting a new scan).
function EJScan:ScanCancel(reason, restoreJournal)
  if not EJScan.state then
    return
  end

  lootListenStop()
  EJScan.counter = EJScan.counter + 1
  local state = EJScan.state
  EJScan.state = nil
  ---@type LiqUI_EJScanEvent
  local event = { name = "cancelled" }
  eventFire(event)

  if restoreJournal ~= false then
    journalRestore(state)
  end
end

---@param options LiqUI_EJScanOptions
function EJScan:Register(options)
  if type(options) ~= "table" then
    error("EJScan:Register requires options", 2)
  end
  if type(options.name) ~= "string" or options.name == "" then
    error("EJScan:Register requires name", 2)
  end
  if type(options.storage) ~= "table" then
    error("EJScan:Register requires storage", 2)
  end
  if options.onEvent ~= nil and type(options.onEvent) ~= "function" then
    error("EJScan:Register onEvent must be a function", 2)
  end
  ---@type LiqUI_EJScanOptions
  local host = {
    name = options.name,
    storage = options.storage,
    onEvent = options.onEvent,
  }
  self.hosts[options.name] = host
  syncBoundCaches()
end

---@return boolean
function EJScan:IsCacheReady()
  local seasonID = Data:GetCurrentSeason()
  if seasonID <= 0 then
    return false
  end
  return cacheBagIsComplete(self.itemCache, seasonID)
end

---@return boolean
function EJScan:IsScanning()
  return EJScan.state ~= nil
end

function EJScan:ClearCache()
  if EJScan.state then
    self:ScanCancel("clear", false)
  end
  local cache = self.itemCache
  cache.items = {}
  cache.seasonID = 0
  cache.build = ""
  cache.version = 0
  cache.lastUpdate = 0
  Utils.TableForEach(EJScan.hosts, function(host)
    local bag = host.storage
    bag.items = {}
    bag.seasonID = 0
    bag.build = ""
    bag.version = 0
    bag.lastUpdate = 0
  end)
  ---@type LiqUI_EJScanEvent
  local event = { name = "cleared" }
  eventFire(event)
end

function EJScan:GetCache()
  if self:IsCacheReady() then
    syncBoundCaches()
    ---@type LiqUI_EJScanEvent
    local event = { name = "current" }
    eventFire(event)
    return
  end
  if EJScan.state then
    return
  end
  if not Data:RequestGameData() then
    Data:EnsureGameData(function()
      EJScan:GetCache()
    end)
    return
  end
  syncBoundCaches()
  if self:IsCacheReady() then
    cacheNotifyReady()
    return
  end

  local cache = self.itemCache

  EJScan.counter = EJScan.counter + 1

  ---@type LiqUI_EJScanClassSpec[]
  local classSpecs = {}
  Utils.TableForEach(Data.cache.classes, function(classEntry, classID)
    Utils.TableForEach(classEntry.specs, function(spec)
      ---@type LiqUI_EJScanClassSpec
      local classSpec = {classID = classID, specID = spec.specID}
      table.insert(classSpecs, classSpec)
    end)
  end)

  ---@type LiqUI_EJScanState
  local state = {
    scanId = EJScan.counter,
    cache = cache,
    journalFilters = scanFilterSave(),
    journalUIWasShown = false,
    journalPrimedForScan = false,
    activeJournalInstanceID = nil,
    activeJournalEncounterID = nil,
    activeInstanceType = nil,
    instances = {},
    classSpecs = classSpecs,
    instanceIndex = 1,
    encounterIndex = 1,
    pass = 1,
    lootEvents = 0,
    step = 0,
    totalSteps = ScanMinProgressSteps,
  }
  EJScan.state = state

  journalPrepareFilters()
  state.journalUIWasShown = journalHide()
  journalPrepare()
  cache.items = {}
  cache.seasonID = 0
  cache.build = ""
  cache.version = 0
  cache.lastUpdate = 0
  ---@type LiqUI_EJScanEvent
  local event = { name = "start", progress = 0 }
  eventFire(event)

  appendScanInstances(state, "raid", Data:GetRaids())
  appendScanInstances(state, "dungeon", Data:GetDungeons())

  local bossCount = 0
  Utils.TableForEach(state.instances, function(instanceEntry)
    Utils.TableForEach(instanceEntry.instance.encounters or {}, function(encounter)
      if encounter.journalEncounterID and encounter.name and encounter.name ~= "" then
        bossCount = bossCount + 1
      end
    end)
  end)
  state.totalSteps = bossCount > 0 and bossCount or ScanMinProgressSteps

  Events:RegisterEvent("EJ_LOOT_DATA_RECIEVED", onLootDataReceived, true)
  scanStepSchedule()
end
