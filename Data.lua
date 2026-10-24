---@class AE_Addon
local addon = select(2, ...)

---@class AE_Data
local Data = {}
addon.Data = Data

local Constants = addon.Constants
local LibAceDB = addon.Libs.AceDB
local LiqUI = addon.Libs.LiqUI
local TableCopy = LiqUI.Utils.TableCopy
local TableCount = LiqUI.Utils.TableCount
local TableFilter = LiqUI.Utils.TableFilter
local TableFind = LiqUI.Utils.TableFind
local TableForEach = LiqUI.Utils.TableForEach
local TableGet = LiqUI.Utils.TableGet
local MergeDeep = LiqUI.Utils.MergeDeep

Data.dbVersion = 51

Data.defaultDB = {
  ---@type AE_Global
  global = {
    weeklyReset = 0,
    characters = {},
    accounts = {}, ---@type table<string, AE_Account> Groups of characters ("1", "2", ...) shown in the Characters menu
    minimap = {
      minimapPos = 195,
      hide = false,
      lock = false,
    },
    sorting = "lastUpdate",
    showTiers = true,
    showScores = true,
    showAffixColors = true,
    showAffixHeader = true,
    dailyDelves = {
      showOnlyHighTier = false,
      listAllStories = false,
      checkBountifulDone = false,
      bountifulResetAt = 0,
      bountifulRotation = {},
      variantCache = {},
    },
    showNonMaxLevelCharacters = false,
    showZeroRatedCharacters = true,
    showCharacterPosition = false,
    showItemLevel = true,
    showEquippedItemLevel = false,
    showItemLevelDecimals = false,
    showRealms = true,
    showGuildInformation = false,
    showDailyDelves = true,
    showRating = true,
    showCurrentKeystone = true,
    currentCharacterMarker = "dot",
    currentCharacterMarkerColor = nil, ---@type ColorTable? Falls back to DIM_GREEN_FONT_COLOR when unset
    cachedTimewalkingEra = nil, ---@type "bc"|"wrath"|"cata"|nil Last era read outside protected content
    announceKeystones = {
      autoParty = true,
      multiline = false,
      multilineNames = false,
    },
    announceResets = true,
    vault = {
      raids = true,
      dungeons = true,
      world = true,
    },
    prey = {
      enabled = true,
      hiddenDifficulties = {},
    },
    labyrinth = {enabled = true},
    raids = {
      enabled = true,
      colors = true,
      currentTierOnly = true,
      hiddenDifficulties = {},
      killIcon = "skull",
      modifiedInstanceOnly = true,
      timewalkingLockouts = false,
    },
    dungeons = {
      enabled = true,
      teleportOnLevelClick = false,
    },
    world = {
      enabled = true,
    },
    currencies = {
      enabled = true,
      hiddenCurrencies = {},
      showIcons = true,
      showMaxEarned = true,
      alignCenter = true,
    },
    weeklies = {
      enabled = true,
      hiddenCurrencies = {},
      showIcons = false,
      showMaxEarned = true,
      alignCenter = true,
    },
    seasonalChores = {
      enabled = true,
      hiddenCurrencies = {},
      showIcons = false,
      showMaxEarned = true,
      alignCenter = true,
    },
    trackerOverrides = {}, ---@type table<any, {order: number, category: "currency"|"weekly"|"seasonalChore"}> Custom order/category set via the Currencies/Weeklies/Seasonal Chores hover arrows
    interface = {
      -- fontSize = 12,
      windowScale = 100,
      windowColor = {r = 0.11372549019, g = 0.14117647058, b = 0.16470588235, a = 1},
    },
    liqui = {
      windows = {
        Main = {
          visibleCharacterLimit = 15,
          logoIconOnly = false,
          showCharacterScrollArrows = true,
          characterScrollArrowScale = 100,
          sidebarCollapsed = false,
          collapsingRowLabelsDisplaysAllIcons = true,
        },
        Affixes = {},
        DailyDelves = {},
        Equipment = {
          showSecondaryStats = false,
          showTierSetAsterisk = false,
          showLowItemLevelAsterisk = false,
          showMissingEmbellishmentWarning = true,
          showMissingTierSetWarning = true,
          separateSortByCharacter = false,
        },
        VaultPreview = {},
        RaidLockouts = {},
        BonusRoll = {},
      },
      tables = {
        Affixes = { hiddenColumns = {} },
        Equipment = { hiddenColumns = {} },
        VaultPreview = { hiddenColumns = {} },
      },
    },
    useRIOScoreColor = false,
    sync = {
      enabled = false,
      tutorialShown = false, ---@type boolean Remember whether the one-time Sync tutorial has already been opened
      onlyMaxLevelCharacters = true,
      password = "",
      channel = "GUILD", ---@type "BOTH"|"GUILD"|"PARTY" Which distribution(s) to send on when more than one is available. "GUILD" (default) restricts sends to the guild channel; "PARTY" restricts to party/raid; "BOTH" sends on every channel that applies (see Comm.lua's GetUsableChannels).
      passwordAccounts = {}, ---@type table<string, string> Which WoW Account each password's synced characters land in
      lastSentRevision = {}, ---@type table<string, number> Per-character GUID -> sync revision last fully broadcast, so unchanged characters are not resent
      lastConfirmedRevision = {}, ---@type table<string, number> Per-character GUID -> sync revision most recently confirmed by another Sync peer via ACK
      receivedFingerprints = {}, ---@type table<string, {revision:number, hash:string}> Authoritative content hash from each remote source
      lastSuccessfulSyncAt = 0, ---@type number Epoch timestamp of the most recent character sync confirmed by a peer (sent or received)
      lastSuccessfulSyncPeer = "", ---@type string Last peer character name involved in a confirmed character sync
    },
  },
}

---@type AE_Character
Data.defaultCharacter = {
  GUID = "",
  lastUpdate = 0,
  syncRevision = 0, ---@type number Monotonic version used only by Multi-Account Sync; independent from the user-facing lastUpdate timestamp
  currentSeason = 0,
  enabled = true,
  order = 0,
  accountId = nil, ---@type string? Which WoW Account bucket (Data.db.global.accounts) this character belongs to
  dailyDelves = {
    bountifulResetAt = 0,
    bountifulSeen = {},
    bountifulDone = {},
  },
  info = {
    name = "",
    realm = "",
    level = 0,
    race = {
      name = "",
      file = "",
      id = 0,
    },
    class = {
      name = "",
      file = "",
      id = 0,
    },
    factionGroup = {
      english = "",
      localized = "",
    },
    lastLocation = "",
    ilvl = {
      level = 0,
      equipped = 0,
      pvp = 0,
      color = "ffffffff",
    },
    guild = {
      isInGuild = false,
      name = "",
      rankName = "",
      rankIndex = 0,
      realm = "",
    },
  },
  equipment = {},
  secondaryStats = {}, -- Latest readable secondary-stat snapshot for this character
  money = 0,
  currencies = {},
  prey = {
    questsCompleted = {},
    nightmareWeeklyProgress = 0,
  },
  labyrinth = {},
  raids = {
    savedInstances = {},
  },
  mythicplus = {
    numCompletedDungeonRuns = {
      heroic = 0,
      mythic = 0,
      mythicPlus = 0,
    },
    rating = 0,
    keystone = {
      challengeModeID = 0,
      mapId = 0,
      level = 0,
      color = "",
      itemId = 0,
      itemLink = "",
    },
    bestSeasonScore = 0,
    bestSeasonNumber = 0,
    runHistory = {},
    dungeons = {},
  },
  vault = {
    hasAvailableRewards = false,
    slots = {},
    activityEncounterInfo = {},
    worldActivityProgress = {},
    lastSnapshot = nil, ---@type AE_VaultSnapshot?
    lastUpdatedAt = 0, ---@type number Data:UpdateVault last ran, regardless of what it found
    openedForReset = 0, ---@type number Weekly reset timestamp for which the real Great Vault was opened
  },
}

---@type AE_Cache
Data.cache = {
  ---@type MythicPlusKeystoneAffix[]
  currentAffixes = {},
}

---Initiate AceDB
function Data:Initialize()
  self.db = LibAceDB:New(
    "AlterEgoDB",
    self.defaultDB,
    true
  )

  -- Sync needs a Main WoW Account to know which characters are "yours" to
  -- send (see GetSyncEligibleCharacters). Rather than leave that unset
  -- until the user notices and picks one manually, default it in the
  -- moment none is marked -- the lowest-numbered account (normally "1",
  -- and the only one that exists yet on a fresh install). The user can
  -- always change this later from the Characters menu; this only fills in
  -- a sane starting point instead of Sync silently doing nothing useful
  -- (or, before this existed, treating "no Main set" as "everything is
  -- eligible", which quietly re-broadcasts characters that came IN from
  -- someone else's sync).
  if not self:GetMainAccountId() then
    self:SetMainAccount(self:EnsureDefaultAccount())
  end

  -- Horizontal character scrolling is now a permanent Main-window behavior.
  -- Drop the retired opt-out key from older SavedVariables so the removed
  -- setting cannot silently affect future layouts.
  if self.db.global.liqui and self.db.global.liqui.windows and self.db.global.liqui.windows.Main then
    self.db.global.liqui.windows.Main.horizontalScrollWhenScaled = nil
  end
end

---Get the current Season IDs
---@return number, number
function Data:GetCurrentSeason()
  return LiqUI.Data:GetCurrentSeason()
end

---Keep the fork's consumers on the shared dungeon catalog.
---@return LiqUI_Dungeon[]
function Data:GetDungeons()
  return LiqUI.Data:GetDungeons()
end

---Expose the shared raid catalog with this fork's ordering and abbreviations.
---@return LiqUI_Raid[]
function Data:GetRaidCatalog()
  local raids = {}
  local seasonTwoOrder = {[3004] = 1, [2987] = 2, [3095] = 3}
  for _, raid in ipairs(LiqUI.Data.raids) do
    local entry = raid
    if raid.seasonID == 18 and seasonTwoOrder[raid.instanceID] then
      entry = {}
      for key, value in pairs(raid) do entry[key] = value end
      entry.order = seasonTwoOrder[raid.instanceID]
      if raid.instanceID == 3095 then entry.abbr = "KX" end
    end
    raids[#raids + 1] = entry
  end
  return raids
end

---Preserve the Raid Lockouts boss order without changing the shared catalog.
---@return LiqUI_Raid[]
function Data:GetRaids()
  local seasonID = self:GetCurrentSeason()
  local raids = TableFilter(self:GetRaidCatalog(), function(raid)
    return raid.seasonID == seasonID
  end)
  table.sort(raids, function(first, second) return first.order < second.order end)
  return raids
end

---Only treat the Season 2 crest acquisition cap as lifted after the REAL
---regional weekly reset for October 20/21. The game schedules that reset;
---this intentionally avoids hardcoded server-maintenance timestamps.
---The caller must also respect the currency cap returned by Blizzard.
function Data:IsSeason2CrestCapLifted()
  local _, _, _, interface = GetBuildInfo()
  if (tonumber(interface) or 0) < 120105 then return false end
  if self:GetCurrentSeason() ~= 18 then return false end
  if not (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset) then return false end
  local remaining = C_DateAndTime.GetSecondsUntilWeeklyReset()
  if type(remaining) ~= "number" or remaining <= 0 then return false end
  local lastReset = time() + remaining - 604800
  local utc = date("!*t", lastReset)
  if not utc then return false end
  return utc.year > 2026 or (utc.year == 2026 and
    (utc.month > 10 or (utc.month == 10 and utc.day >= 20)))
end

---@param itemID number
---@return string|nil name
---@return number|nil iconFileID
---@return Enum.ItemQuality|nil quality
---@return number bagCount
---@return number quantity
local function fetchBagItem(itemID)
  local name = C_Item.GetItemNameByID(itemID)
  local iconFileID = C_Item.GetItemIconByID(itemID)
  local quality = C_Item.GetItemQualityByID(itemID)
  if name == nil or iconFileID == nil or quality == nil then
    C_Item.RequestLoadItemDataByID(itemID)
  end
  local bagCount = C_Item.GetItemCount(itemID)
  local quantity = C_Item.GetItemCount(itemID, true)
  return name, iconFileID, quality, bagCount, quantity
end

---Current season trackers enriched for labels and local tracker settings.
---@return AE_CurrencyInfo[]
function Data:GetCurrencies()
  local currencies = {}
  local seasonID = LiqUI.Data:GetCurrentSeason()
  TableForEach(self.currencies, function(currency)
    if currency.seasonID ~= nil and currency.seasonID ~= seasonID then
      return
    end
    if currency.currencyType == "quest" then
      ---@type AE_CurrencyInfo
      local questInfo = {
        id = currency.id,
        name = currency.name,
        description = currency.description or (
          currency.resets == "weekly"
          and "Weekly quest. Resets every week."
          or "One-time quest. Can only be completed once per account."
        ),
        iconFileID = currency.iconFileID,
        quality = Enum.ItemQuality.Rare,
        currencyType = currency.currencyType,
        category = currency.category,
        resets = currency.resets,
        tooltipNote = currency.tooltipNote,
        maxQuantity = 0,
        maxWeeklyQuantity = 0,
        quantity = 0,
        totalEarned = 0,
        quantityEarnedThisWeek = 0,
      }
      table.insert(currencies, questInfo)
      return
    end
    if currency.currencyType == "trackedItem" then
      local name, iconFileID, quality = fetchBagItem(currency.id)
      table.insert(currencies, {
        id = currency.id, name = name or currency.name, description = currency.description,
        currencyType = currency.currencyType, category = currency.category, quality = quality,
        iconFileID = iconFileID,
        tooltipNote = currency.tooltipNote, required = currency.required,
        maxQuantity = 0, maxWeeklyQuantity = 0, quantity = 0,
      })
      return
    end
    if currency.currencyType == "delveMap" then
      local _, iconFileID, quality = fetchBagItem(currency.id)
      ---@type AE_CurrencyInfo
      local currencyInfo = {
        id = currency.id,
        name = currency.name or "Trovehunter's Bounty",
        description = "Weekly Trovehunter's Bounty map status from delves.",
        iconFileID = iconFileID or 0,
        quality = quality or Enum.ItemQuality.Rare,
        currencyType = currency.currencyType,
        category = currency.category,
        useTotalEarnedForMaxQty = currency.useTotalEarnedForMaxQty,
        tooltipNote = currency.tooltipNote,
        maxQuantity = 0,
        maxWeeklyQuantity = 0,
        quantity = 0,
        totalEarned = 0,
        quantityEarnedThisWeek = 0,
      }
      table.insert(currencies, currencyInfo)
      return
    end
    if currency.currencyType == "gildedStash" then
      ---@type AE_CurrencyInfo
      local gildedStashInfo = {
        id = currency.id,
        name = currency.name or "Gilded Stash",
        description = "Weekly Gilded Stash progress from delves.",
        iconFileID = currency.iconFileID,
        quality = Enum.ItemQuality.Rare,
        currencyType = currency.currencyType,
        category = currency.category,
        tooltipNote = currency.tooltipNote,
        maxQuantity = 0,
        maxWeeklyQuantity = 0,
        quantity = 0,
        totalEarned = 0,
        quantityEarnedThisWeek = 0,
      }
      table.insert(currencies, gildedStashInfo)
      return
    end
    local apiInfo = C_CurrencyInfo.GetCurrencyInfo(currency.id)
    if apiInfo then
      local currencyInfo = TableCopy(apiInfo)
      currencyInfo.id = currency.id
      currencyInfo.currencyType = currency.currencyType
      currencyInfo.category = currency.category
      currencyInfo.tooltipNote = currency.tooltipNote
      table.insert(currencies, currencyInfo)
    end
  end)
  return self:ApplyTrackerOverrides(currencies)
end

---Fixed macro order the three tracker sections are always displayed in.
local TRACKER_CATEGORIES = { "currency", "weekly", "seasonalChore" }

---Sections in display order, paired with the db keys holding their enabled/hidden-item state.
local TRACKER_SECTIONS = {
  { category = "currency",      settingsKey = "currencies" },
  { category = "weekly",        settingsKey = "weeklies" },
  { category = "seasonalChore", settingsKey = "seasonalChores" },
}

---The "plain currency" section is represented as category == nil throughout the codebase
---(see Render()'s TableFilter calls), while it's easier to work with an explicit string
---internally. These two helpers convert between the two representations.
---@param category string?
---@return string
local function NormalizeTrackerCategory(category)
  return category or "currency"
end

---@param category string
---@return string?
local function DenormalizeTrackerCategory(category)
  if category == "currency" then return nil end
  return category
end

---Apply user-customized order/category overrides (set via the Currencies/Weeklies/Seasonal
---Chores hover arrows) on top of the static tracker definitions, then renormalize each
---section's order to a clean 1..n sequence. Mirrors how Data:GetCharacters() renormalizes
---character.order.
---@param currencies AE_CurrencyInfo[]
---@return AE_CurrencyInfo[]
function Data:ApplyTrackerOverrides(currencies)
  local overrides = self.db.global.trackerOverrides
  local byCategory = {}

  TableForEach(currencies, function(currency, naturalIndex)
    local override = currency.id ~= nil and overrides[currency.id]
    local category = (override and override.category) or NormalizeTrackerCategory(currency.category)
    currency.order = (override and override.order) or naturalIndex
    byCategory[category] = byCategory[category] or {}
    table.insert(byCategory[category], currency)
  end)

  local sorted = {}
  TableForEach(TRACKER_CATEGORIES, function(category)
    local group = byCategory[category] or {}
    table.sort(group, function(a, b) return a.order < b.order end)
    local order = 1
    TableForEach(group, function(currency)
      currency.category = DenormalizeTrackerCategory(category)
      currency.order = order
      if currency.id ~= nil then
        overrides[currency.id] = overrides[currency.id] or {}
        overrides[currency.id].category = category
        overrides[currency.id].order = order
      end
      order = order + 1
      table.insert(sorted, currency)
    end)
  end)

  return sorted
end

---Get the sections (currency/weekly/seasonalChore) that are currently enabled, in fixed
---display order, each with the trackers actually shown in it (order applied, hidden ones
---excluded). A section that's enabled but currently has no trackers in it (e.g. everything got
---moved out of it) still appears here as an empty entry, so the hover arrows know it's a valid
---place to move a tracker into.
---@return { category: string, items: AE_CurrencyInfo[] }[]
function Data:GetTrackerSections()
  local allTrackers = self:GetCurrencies()
  local sections = {}
  TableForEach(TRACKER_SECTIONS, function(section)
    local sectionSettings = self.db.global[section.settingsKey]
    if not sectionSettings or not sectionSettings.enabled then
      return
    end
    local hidden = sectionSettings.hiddenCurrencies or {}
    local items = {}
    TableForEach(allTrackers, function(tracker)
      if NormalizeTrackerCategory(tracker.category) == section.category and not hidden[tracker.id] then
        table.insert(items, tracker)
      end
    end)
    table.insert(sections, { category = section.category, items = items })
  end)
  return sections
end

---Get the trackers (currencies/weeklies/seasonal chores) actually shown on screen right now,
---in display order, skipping disabled sections and hidden individual trackers.
---@return AE_CurrencyInfo[]
function Data:GetVisibleTrackers()
  local visible = {}
  TableForEach(self:GetTrackerSections(), function(section)
    TableForEach(section.items, function(tracker) table.insert(visible, tracker) end)
  end)
  return visible
end

---Move a tracker up/down among the ones currently shown. Reordering within the same section
---simply swaps places with the neighbor. At the edge of a section, it crosses into the nearest
---enabled section in that direction (even if that section is currently empty), landing at the
---near edge, right next to where it came from. The neighbor/section it left never changes.
---@param tracker AE_CurrencyInfo
---@param direction number -1 to move up/earlier, 1 to move down/later
function Data:SortTracker(tracker, direction)
  if tracker.id == nil then return end

  local overrides = self.db.global.trackerOverrides
  local sections = self:GetTrackerSections()

  local sectionIndex, itemIndex
  for si, section in ipairs(sections) do
    for ii, t in ipairs(section.items) do
      if t.id == tracker.id then
        sectionIndex, itemIndex = si, ii
        break
      end
    end
    if sectionIndex then break end
  end
  if not sectionIndex then return end -- tracker isn't currently visible

  local section = sections[sectionIndex]

  if direction < 0 and itemIndex > 1 then
    -- Move up within the section: swap with the previous item
    local neighbor = section.items[itemIndex - 1]
    overrides[tracker.id] = overrides[tracker.id] or {}
    overrides[neighbor.id] = overrides[neighbor.id] or {}
    local trackerOrder, neighborOrder = tracker.order or 0, neighbor.order or 0
    overrides[tracker.id].category, overrides[tracker.id].order = section.category, neighborOrder
    overrides[neighbor.id].category, overrides[neighbor.id].order = section.category, trackerOrder
    return
  end

  if direction > 0 and itemIndex < #section.items then
    -- Move down within the section: swap with the next item
    local neighbor = section.items[itemIndex + 1]
    overrides[tracker.id] = overrides[tracker.id] or {}
    overrides[neighbor.id] = overrides[neighbor.id] or {}
    local trackerOrder, neighborOrder = tracker.order or 0, neighbor.order or 0
    overrides[tracker.id].category, overrides[tracker.id].order = section.category, neighborOrder
    overrides[neighbor.id].category, overrides[neighbor.id].order = section.category, trackerOrder
    return
  end

  -- At the edge of the section: cross into the nearest enabled section in that direction,
  -- whether or not it currently has any trackers of its own.
  local targetSection = sections[sectionIndex + direction]
  if not targetSection then return end -- already at the very top/bottom

  overrides[tracker.id] = overrides[tracker.id] or {}
  overrides[tracker.id].category = targetSection.category
  if #targetSection.items == 0 then
    overrides[tracker.id].order = 1
  elseif direction < 0 then
    -- Joining the section above: land at its bottom, next to where we came from
    overrides[tracker.id].order = (targetSection.items[#targetSection.items].order or 0) + 0.5
  else
    -- Joining the section below: land at its top, next to where we came from
    overrides[tracker.id].order = (targetSection.items[1].order or 0) - 0.5
  end
end

---Clear all custom tracker order/category overrides, restoring the default layout.
function Data:ResetTrackerOrder()
  self.db.global.trackerOverrides = {}
end

---Restore the main character-grid filters/columns to their shipped defaults.
---Deliberately leaves sorting, tracker visibility/order, minimap settings, window
---position/size/scale, account organization, and Sync settings untouched.
function Data:ResetDisplayFiltersAndColumns()
  local keys = {
    "showNonMaxLevelCharacters",
    "showZeroRatedCharacters",
    "showCharacterPosition",
    "showItemLevel",
    "showEquippedItemLevel",
    "showItemLevelDecimals",
    "showRealms",
    "showGuildInformation",
    "showRating",
    "showCurrentKeystone",
    "useRIOScoreColor",
  }

  for _, key in ipairs(keys) do
    self.db.global[key] = self.defaultDB.global[key]
  end

  -- The clickable AlterEgo title controls the shared row-label column, so it
  -- belongs to the display reset even though its persisted state lives with
  -- the Main window settings.
  self.db.global.liqui.windows.Main.sidebarCollapsed = self.defaultDB.global.liqui.windows.Main.sidebarCollapsed
end

---Reset the entire AlterEgo SavedVariables database to its shipped defaults.
---The caller should reload the UI immediately after this so every module starts
---again from the same clean-install state.
function Data:ResetAllAddonSettings()
  self.db:ResetDB(true)
end

---The weekly +50% reputation buff each classic-raid Timewalking event grants the player.
---These are stable, hardcoded spell IDs (not tied to the calendar), so checking for them directly
---is far more reliable than trying to parse calendar event text.
local TIMEWALKING_ERA_BUFFS = {
  { key = "bc", spellID = 335148 }, -- Sign of the Twisting Nether
  { key = "wrath", spellID = 335149 }, -- Sign of the Scourge
  { key = "cata", spellID = 335150 }, -- Sign of the Destroyer
}

---Detect which classic-raid Timewalking event (if any) is currently active, by checking for the
---weekly reputation buff each event grants the player. Reading auras is blocked inside protected
---content (e.g. Midnight raid instances), so the last successfully-read result is persisted and
---reused whenever a fresh read isn't allowed, instead of losing the detection while inside.
---@return "bc"|"wrath"|"cata"|nil
function Data:GetActiveTimewalkingEra()
  local ok, result = pcall(function()
    for _, buff in ipairs(TIMEWALKING_ERA_BUFFS) do
      local aura = C_UnitAuras.GetPlayerAuraBySpellID(buff.spellID)
      if aura then
        return buff.key
      end
    end
    return nil
  end)

  if ok then
    self.db.global.cachedTimewalkingEra = result
    return result
  end

  -- Aura data isn't readable here (protected content); fall back to the last known reading.
  return self.db.global.cachedTimewalkingEra
end

---Check this week's lockout status for the classic Timewalking raid finale bosses: Illidan
---Stormrage (Black Temple), Yogg-Saron (Ulduar) and Ragnaros (Firelands).
---@return table<string, boolean> killed keyed by "illidan" | "yoggsaron" | "ragnaros"
---Check this week's lockout status for the classic Timewalking raid finale bosses: Illidan
---Stormrage (Black Temple), Yogg-Saron (Ulduar) and Ragnaros (Firelands), for a specific stored
---character. Reading saved-instance data is blocked inside protected content (e.g. Midnight raid
---instances), so the last successfully-read result is persisted per character and reused whenever
---a fresh read isn't allowed (such as when that same character is the one currently inside).
---@param character AE_Character
---@return table<string, boolean> killed keyed by "illidan" | "yoggsaron" | "ragnaros"
function Data:GetTimewalkingBossKills(character)
  local defaultKills = { illidan = false, yoggsaron = false, ragnaros = false }
  if not character then return defaultKills end

  local bossesByInstance = {
    ["black temple"] = { key = "illidan", bossName = "illidan stormrage" },
    ["ulduar"] = { key = "yoggsaron", bossName = "yogg-saron" },
    ["firelands"] = { key = "ragnaros", bossName = "ragnaros" },
  }

  local ok, kills = pcall(function()
    local result = { illidan = false, yoggsaron = false, ragnaros = false }
    TableForEach(character.raids.savedInstances or {}, function(savedInstance)
      if not (savedInstance.expires > time()) then return end
      local instanceMatch = bossesByInstance[string.lower(savedInstance.name or "")]
      if not instanceMatch then return end
      TableForEach(savedInstance.encounters or {}, function(encounter)
        if string.lower(encounter.bossName or "") == instanceMatch.bossName then
          result[instanceMatch.key] = encounter.isKilled == true
        end
      end)
    end)
    return result
  end)

  if ok then
    character.raids.cachedTimewalkingKills = kills
    return kills
  end

  -- Saved-instance data isn't readable here (protected content); fall back to the last known
  -- reading for this character, or all-false if we never got one.
  return character.raids.cachedTimewalkingKills or defaultKills
end
---@param currencyID number
---@return boolean
function Data:IsQuestCompletedOnAccount(currencyID)
  for _, character in pairs(self.db.global.characters) do
    local characterCurrency = TableGet(character.currencies or {}, "id", currencyID)
    if characterCurrency and characterCurrency.questCompleted then
      return true
    end
  end
  return false
end

---Get stored character by GUID
---@param playerGUID WOWGUID?
---@return AE_Character|nil
function Data:GetCharacter(playerGUID)
  if playerGUID == nil then
    playerGUID = UnitGUID("player")
  end

  if playerGUID == nil then
    return nil
  end

  if self.db.global.characters[playerGUID] == nil then
    self.db.global.characters[playerGUID] = TableCopy(Data.defaultCharacter)
    self.db.global.characters[playerGUID].accountId = self:EnsureDefaultAccount()
  end

  local character = self.db.global.characters[playerGUID]
  character.GUID = playerGUID
  if type(character.syncRevision) ~= "number" then
    character.syncRevision = tonumber(character.lastUpdate) or 0
  end

  return character
end

---Return the monotonic version used to compare this character over Multi-Account Sync.
---Older records created before syncRevision existed fall back to lastUpdate so mixed/legacy
---SavedVariables remain comparable until that character changes locally again.
---@param character AE_Character?
---@return number
function Data:GetCharacterSyncRevision(character)
  if type(character) ~= "table" then return 0 end
  return tonumber(character.syncRevision) or tonumber(character.lastUpdate) or 0
end

---Whether this installation is authoritative for a character's Sync version.
---The actively logged-in character is always local. For offline records, a configured Main
---WoW Account is the authority boundary; installations that never configured Main preserve
---the addon's legacy behavior where all locally-tracked characters are considered sendable.
---@param character AE_Character?
---@return boolean
function Data:IsCharacterSyncAuthoritative(character)
  if type(character) ~= "table" then return false end
  if character.GUID and character.GUID == UnitGUID("player") then return true end
  local mainAccountId = self:GetMainAccountId()
  if not mainAccountId then return true end
  local characterAccountId = character.accountId or self:EnsureDefaultAccount()
  return characterAccountId == mainAccountId
end

---Advance a character's dedicated Sync revision after its syncable data changes and queue
---the normal debounced broadcast. This deliberately does NOT modify lastUpdate: that field
---continues to mean "last character-info refresh" in the UI instead of doubling as transport state.
---@param character AE_Character?
---@return boolean changedRevision
function Data:MarkCharacterSyncChanged(character)
  character = character or self:GetCharacter()
  if not character or not self:IsCharacterSyncAuthoritative(character) then return false end

  local current = math.max(self:GetCharacterSyncRevision(character), tonumber(character.lastUpdate) or 0)
  local serverNow = type(GetServerTime) == "function" and tonumber(GetServerTime()) or tonumber(time()) or 0
  character.syncRevision = math.max(current + 1, serverNow)

  if addon.Core and addon.Core.RequestSyncBroadcast then
    addon.Core:RequestSyncBroadcast()
  end
  return true
end

---Remove a character from the addon. No undo; log in on that character again to reintroduce.
---@param characterOrGUID AE_Character|string
function Data:DeleteCharacter(characterOrGUID)
  local GUID = type(characterOrGUID) == "table" and characterOrGUID.GUID or characterOrGUID
  if not GUID then return end

  self.db.global.characters[GUID] = nil

  -- Remove persistent per-character Sync bookkeeping along with the actual
  -- character record so deleting a character does not leave orphaned GUID
  -- metadata behind in SavedVariables.
  local sync = self.db.global.sync
  if sync and sync.lastSentRevision then
    sync.lastSentRevision[GUID] = nil
  end
  if sync and sync.lastConfirmedRevision then
    sync.lastConfirmedRevision[GUID] = nil
  end
  if sync and sync.receivedFingerprints then
    sync.receivedFingerprints[GUID] = nil
  end
  -- Clean legacy bookkeeping too if it still exists in an upgraded SavedVariables file.
  if sync and sync.lastSentUpdate then sync.lastSentUpdate[GUID] = nil end
  if sync and sync.lastConfirmedUpdate then sync.lastConfirmedUpdate[GUID] = nil end

  -- Comm.lua also keeps a few session-only per-GUID caches. They are not
  -- SavedVariables, but clearing them here keeps Remove Character semantically
  -- complete for the rest of the current login session too.
  if addon.Core.ForgetSyncCharacterMetadata then
    addon.Core:ForgetSyncCharacterMetadata(GUID)
  end
end

-- ===== WoW Accounts (manual grouping shown in the Characters menu) =======
--
-- These are NOT real Battle.net/WoW accounts detected automatically -- this
-- addon only ever sees the characters that logged in under the current
-- SavedVariables file. They're just user-managed folders (auto-named "1",
-- "2", ...) to organize/toggle groups of characters in the Characters menu,
-- same idea as a label. Every character always belongs to exactly one of these.

---Return every WoW Account, ordered, creating a default one if none exist yet.
---@return AE_Account[]
function Data:GetAccounts()
  self:EnsureDefaultAccount()
  local accounts = {}
  for id, account in pairs(self.db.global.accounts) do
    account.id = id
    table.insert(accounts, account)
  end
  table.sort(accounts, function(a, b) return (a.order or 0) < (b.order or 0) end)
  return accounts
end

---Make sure at least one WoW Account exists.
---@return string accountId The id of the first (lowest order) account.
function Data:EnsureDefaultAccount()
  if TableCount(self.db.global.accounts) == 0 then
    return self:CreateAccount()
  end
  local firstId, firstOrder
  for id, account in pairs(self.db.global.accounts) do
    if firstOrder == nil or (account.order or 0) < firstOrder then
      firstId, firstOrder = id, (account.order or 0)
    end
  end
  return firstId
end

---Create a new WoW Account bucket.
---@param name string? Explicit name; wins over everything else if given.
---@param password string? When name is nil, names the new account "<number> (<password>)" instead of just "<number>" -- used by GetOrCreateAccountForPassword so it's obvious at a glance which sync password's incoming characters live in this bucket.
---@return string accountId
function Data:CreateAccount(name, password)
  -- The display NAME's number is picked by checking what's actually
  -- already shown in the list -- not just which internal "account_N" id
  -- slot happens to be free. Those two used to be the same number, which
  -- meant a freed-up id slot (from a past deletion) could hand a brand
  -- new account the same NUMBER as one still sitting right there in the
  -- list, under a different id, producing two entries that looked
  -- identically named. Starting from the current account COUNT and
  -- nudging it up past anything already using that exact name (as
  -- "<number>" or "<number> (<password>)") guarantees a name that's
  -- never a duplicate of what's currently visible, regardless of what
  -- id-slot numbering history looks like underneath.
  local function nameTaken(candidateName)
    for _, account in pairs(self.db.global.accounts) do
      if account.name == candidateName then
        return true
      end
    end
    return false
  end

  local number = TableCount(self.db.global.accounts) + 1
  local function nameForNumber(n)
    return name or (password and format("%d (%s)", n, password)) or tostring(n)
  end
  if not name then
    -- Only the auto-numbered forms actually change as number increases --
    -- an explicit name is fixed regardless of number, so looping on it
    -- would either do nothing useful or spin forever if that exact name
    -- happens to already be taken. An explicit name is trusted as-is.
    while nameTaken(nameForNumber(number)) do
      number = number + 1
    end
  end

  -- The internal id, separately: smallest free "account_N" slot, so
  -- deleting e.g. account "10" and creating a new one reuses that slot
  -- instead of ids growing forever. This is bookkeeping only -- it's
  -- never shown to the person, so it drifting out of step with the
  -- display numbering above is harmless.
  local idNumber = 1
  while self.db.global.accounts["account_" .. idNumber] do
    idNumber = idNumber + 1
  end
  local id = "account_" .. idNumber

  local maxOrder = 0
  for _, account in pairs(self.db.global.accounts) do
    if (account.order or 0) > maxOrder then
      maxOrder = account.order
    end
  end

  self.db.global.accounts[id] = {
    name = nameForNumber(number),
    enabled = true,
    order = maxOrder + 1,
  }

  return id
end

---Rename a WoW Account.
---@param accountId string
---@param newName string
function Data:RenameAccount(accountId, newName)
  local account = self.db.global.accounts[accountId]
  if account and newName and newName ~= "" then
    account.name = newName
  end
end

---Enable/disable tracking for every character inside a WoW Account at once.
---Doesn't touch each character's own `enabled` flag -- disabling the account
---just hides them all until the account is re-enabled.
---@param accountId string
---@param enabled boolean
function Data:SetAccountEnabled(accountId, enabled)
  local account = self.db.global.accounts[accountId]
  if account then
    account.enabled = enabled
  end
end

---Delete a WoW Account, and every character filed inside it -- they're not
---moved anywhere, they're gone. Refuses to delete the only remaining account.
---@param accountId string
---@return boolean success
---@return string? errorMessage
function Data:DeleteAccount(accountId)
  if self.db.global.accounts[accountId] == nil then
    return false
  end
  if TableCount(self.db.global.accounts) <= 1 then
    return false, "You can't remove your only WoW Account."
  end

  self.db.global.accounts[accountId] = nil

  local charactersToDelete = {}
  for GUID, character in pairs(self.db.global.characters) do
    if character.accountId == accountId then
      table.insert(charactersToDelete, GUID)
    end
  end
  for _, GUID in ipairs(charactersToDelete) do
    self:DeleteCharacter(GUID)
  end

  local fallbackId = self:EnsureDefaultAccount()

  -- If the account we just deleted was Main, it took the Main flag down
  -- with it (the flag lived on that now-gone account entry) -- re-default
  -- to the fallback account instead of silently leaving Sync with no Main
  -- set until the next reload.
  if not self:GetMainAccountId() then
    self:SetMainAccount(fallbackId)
  end

  return true
end

---Get the characters assigned to a specific WoW Account.
---@param accountId string
---@param unfiltered boolean? Include disabled characters too
---@return AE_Character[]
function Data:GetCharactersByAccount(accountId, unfiltered)
  local characters = self:GetCharacters(true) -- unfiltered: we apply our own enabled/account filtering below
  local result = {}
  for _, character in ipairs(characters) do
    local characterAccountId = character.accountId or self:EnsureDefaultAccount()
    if characterAccountId == accountId and (unfiltered or character.enabled) then
      table.insert(result, character)
    end
  end
  return result
end

---Get (or find/create, first time) the WoW Account that a given sync
---password's INCOMING characters should land in -- resolved by NAME, not
---a hidden internal id: if any existing account's name already contains
---the password text, that account is reused as-is (no renaming) -- so
---you can pre-create and name your own bucket (e.g. "Friends
---(hunterparty2026)") and incoming characters synced with that password
---will land inside it instead of a separate new account being created
---next to it. Otherwise a brand new account is created and named
---"<number> (<password>)" so it's obvious at a glance which password's
---characters live there.
---Calling this again with the SAME password keeps returning the SAME
---account id, cached once resolved -- so repeat syncs don't create
---duplicates, and it keeps working even if you later rename the account to
---something that no longer contains the password text.
---HARD RULE, checked at every return point: this NEVER returns the Main
---WoW Account's id, no matter what a stale cache or a name match says.
---Main is reserved for YOUR OWN authoritative characters -- if incoming
---sync data ever landed there, OnCommReceived's Main-account protection
---would immediately (and silently, before that got a warning added) treat
---every future update for that character as "already my own, ignore it",
---which looks exactly like sync being broken. If the cache or a name
---match ever points at Main (leftover from an old bug, or the account
---getting flagged Main after the fact), that entry is treated as invalid
---and a fresh, separate account is used/created instead.
---@param password string
---@return string accountId
function Data:GetOrCreateAccountForPassword(password)
  if not password or password == "" then
    return self:EnsureDefaultAccount()
  end

  local mainAccountId = self:GetMainAccountId()

  self.db.global.sync.passwordAccounts = self.db.global.sync.passwordAccounts or {}
  local cachedId = self.db.global.sync.passwordAccounts[password]
  if cachedId and cachedId ~= mainAccountId and self.db.global.accounts[cachedId] then
    return cachedId
  end

  -- No usable cached mapping (first time this password is ever seen on
  -- this client, its previously-mapped account got deleted, or the cache
  -- pointed at Main and got rejected above) -- look for an existing,
  -- non-Main account whose name already mentions this password before
  -- creating a new one.
  for id, account in pairs(self.db.global.accounts) do
    if id ~= mainAccountId and account.name and string.find(account.name, password, 1, true) then
      self.db.global.sync.passwordAccounts[password] = id
      return id
    end
  end

  local newAccountId = self:CreateAccount(nil, password)
  self.db.global.sync.passwordAccounts[password] = newAccountId
  return newAccountId
end

---Mark a WoW Account as "Main" -- the one that represents the characters
---THIS installation actually plays (as opposed to accounts holding
---characters synced in from someone else). Only one account can be Main at
---a time; marking a new one unmarks the previous one. Pass nil to clear it.
---@param accountId string?
function Data:SetMainAccount(accountId)
  for id, account in pairs(self.db.global.accounts) do
    account.isMain = (accountId ~= nil and id == accountId) or nil
  end
end

---@return string? accountId The account marked Main, or nil if none is.
function Data:GetMainAccountId()
  -- Walks every account rather than returning on first match, and picks
  -- the one with the lowest `order` if, somehow, more than one ended up
  -- flagged (shouldn't happen via SetMainAccount, which always clears the
  -- others first -- this just makes the result deterministic instead of
  -- depending on Lua's unstable pairs() iteration order, which is what
  -- would make "Main" look like it randomly jumps between accounts as
  -- more get added). Any extra flags found this way are cleared so the
  -- table self-heals back to the single-Main invariant.
  local mainId, mainOrder
  for id, account in pairs(self.db.global.accounts) do
    if account.isMain and (mainId == nil or (account.order or 0) < mainOrder) then
      mainId, mainOrder = id, (account.order or 0)
    end
  end
  if mainId then
    for id, account in pairs(self.db.global.accounts) do
      if account.isMain and id ~= mainId then
        account.isMain = nil
      end
    end
  end
  return mainId
end

---Characters eligible to go out over Sync. If a Main account is set, this
---is ONLY the characters filed under it (so characters that came IN from a
---friend's sync never get re-broadcast back out). If no Main account is
---set, every currently-tracked character is eligible, same as before this
---feature existed.
---@return AE_Character[]
function Data:GetSyncEligibleCharacters()
  -- Sync eligibility must not depend on main-window display filters such as
  -- rating or whether leveling characters are currently visible. The Sync
  -- module applies its own max-level preference after this list is built.
  local characters = self:GetCharacters(true)
  local mainAccountId = self:GetMainAccountId()
  local result = {}
  local defaultAccountId = self:EnsureDefaultAccount()
  for _, character in ipairs(characters) do
    -- Characters saved before WoW Account grouping existed may not have an
    -- explicit accountId. Accounts & Characters already displays those under
    -- the default account; Sync must resolve them the same way or a character
    -- can look selected inside Main while still being reported as ineligible.
    local characterAccountId = character.accountId or defaultAccountId
    local account = self.db.global.accounts[characterAccountId]
    local accountEnabled = not account or account.enabled ~= false
    local inMainAccount = not mainAccountId or characterAccountId == mainAccountId
    if character.enabled ~= false and accountEnabled and inMainAccount then
      table.insert(result, character)
    end
  end
  return result
end

---Move a character to a different WoW Account.
---@param GUID string
---@param accountId string
function Data:MoveCharacterToAccount(GUID, accountId)
  local character = self.db.global.characters[GUID]
  if not character or self.db.global.accounts[accountId] == nil then return end
  character.accountId = accountId
end

---Get prey difficulties for the current season
---@param unfiltered boolean?
---@return AE_PreyDifficulty[]
function Data:GetPreyDifficulties(unfiltered)
  local seasonID = LiqUI.Data:GetCurrentSeason()
  local result = {}
  for _, difficulty in pairs(self.preyDifficulties) do
    if difficulty.seasonID == seasonID then
      table.insert(result, difficulty)
    end
  end

  table.sort(result, function(a, b)
    return a.id < b.id
  end)

  if unfiltered then
    return result
  end

  local filtered = {}
  for _, difficulty in ipairs(result) do
    if self.db.global.prey.hiddenDifficulties and not self.db.global.prey.hiddenDifficulties[difficulty.id] then
      table.insert(filtered, difficulty)
    end
  end

  return filtered
end

---Get prey quests
---@param unfiltered boolean?
---@return AE_PreyQuest[]
function Data:GetPreyQuests(unfiltered)
  local result = {}
  for _, quest in pairs(self.preyQuests) do
    table.insert(result, quest)
  end
  return result
end

---Get raid difficulties, optionally including ones hidden in settings
---@param unfiltered boolean?
---@return LiqUI_RaidDifficulty[]
function Data:GetRaidDifficulties(unfiltered)
  local difficulties = LiqUI.Data:GetRaidDifficulties()
  if unfiltered then
    return difficulties
  end
  local hiddenDifficulties = self.db.global.raids.hiddenDifficulties
  return TableFilter(difficulties, function(difficulty)
    return hiddenDifficulties and not hiddenDifficulties[difficulty.id]
  end)
end

---Get the current affixes of the week
---@return MythicPlusKeystoneAffix[]
function Data:GetCurrentAffixes()
  if TableCount(self.cache.currentAffixes) == 0 then
    local currentAffixes = C_MythicPlus.GetCurrentAffixes()
    if currentAffixes then
      self.cache.currentAffixes = currentAffixes
    end
  end
  return self.cache.currentAffixes
end

---Get either all affixes or just the base seasonal affixes
---@param baseOnly boolean?
---@return AE_Affix[]
function Data:GetAffixes(baseOnly)
  return TableFilter(self.affixes, function(dataAffix)
    return not baseOnly or dataAffix.base == 1
  end)
end

---Get affix rotation of the current season
---@return AE_AffixRotation|nil
function Data:GetAffixRotation()
  local seasonID = LiqUI.Data:GetCurrentSeason()
  return TableGet(self.affixRotations, "seasonID", seasonID)
end

---Get the index of the active affix week
---@param currentAffixes MythicPlusKeystoneAffix[]|nil
---@return number
function Data:GetActiveAffixRotation(currentAffixes)
  local affixRotation = self:GetAffixRotation()
  local index = 0
  if currentAffixes and affixRotation then
    TableForEach(affixRotation.affixes, function(affixWeek, affixWeekIndex)
      local thisWeek = true
      TableForEach(affixWeek, function(affixID, affixIndex)
        if not (currentAffixes[affixIndex] and currentAffixes[affixIndex].id == affixID) then
          thisWeek = false
        end
      end)
      if thisWeek then
        index = affixWeekIndex
      end
    end)
  end
  return index
end

---Get the Keystone ItemID of the current season
---@return number|nil
function Data:GetKeystoneItemID()
  local seasonID = LiqUI.Data:GetCurrentSeason()
  local keystone = TableGet(self.keystones, "seasonID", seasonID)

  if keystone ~= nil then
    return keystone.itemID
  end

  return nil
end


---Set a new character order
---@param character AE_Character
---@param direction number
function Data:SortCharacter(character, direction)
  local characters = self:GetCharacters()
  for i, _ in pairs(characters) do
    if characters[i].GUID == character.GUID then
      if direction > 0 and i < #characters and characters[i + 1] then
        self.db.global.characters[character.GUID].order = characters[i + 1].order + 0.5
        break
      end
      if direction < 0 and i > 1 and characters[i - 1] then
        self.db.global.characters[character.GUID].order = characters[i - 1].order - 0.5
      end
    end
  end
end

---Get Retail's current expansion level cap. Prefer the latest-expansion
---API so this follows the game's current expansion instead of a hard-coded
---level or the logged-in account's ownership/subscription state.
---@return number?
function Data:GetCurrentMaxLevel()
  local maxLevel = GetMaxLevelForLatestExpansion and GetMaxLevelForLatestExpansion()
  if type(maxLevel) ~= "number" or maxLevel <= 0 then
    maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
  end
  if type(maxLevel) ~= "number" or maxLevel <= 0 then
    maxLevel = GetEffectivePlayerMaxLevel and GetEffectivePlayerMaxLevel()
  end
  return type(maxLevel) == "number" and maxLevel > 0 and maxLevel or nil
end

---Whether a saved character has reached Retail's current expansion cap.
---@param character AE_Character
---@return boolean
function Data:IsMaxLevelCharacter(character)
  local level = character and character.info and character.info.level
  if type(level) ~= "number" then return false end
  local maxLevel = self:GetCurrentMaxLevel()
  return maxLevel ~= nil and level >= maxLevel
end

---Get user characters
---@param unfiltered boolean?
---@return AE_Character[]
function Data:GetCharacters(unfiltered)
  local characters = {}
  for _, character in pairs(self.db.global.characters) do
    -- Keep every captured character in the working set. Max-level visibility
    -- is a normal display filter below so unfiltered callers can still manage
    -- leveling characters even while the main window hides them.
    table.insert(characters, character)
  end

  -- Update custom order
  local order = 1
  table.sort(characters, function(a, b)
    return (a.order or 0) < (b.order or 0)
  end)
  TableForEach(characters, function(character)
    self.db.global.characters[character.GUID].order = order
    order = order + 1
  end)

  -- Sorting
  table.sort(characters, function(a, b)
    if self.db.global.sorting == "name.asc" then
      return strcmputf8i(a.info.name, b.info.name) < 0
    elseif self.db.global.sorting == "name.desc" then
      return strcmputf8i(a.info.name, b.info.name) > 0
    elseif self.db.global.sorting == "realm.asc" then
      return strcmputf8i(a.info.realm, b.info.realm) < 0
    elseif self.db.global.sorting == "realm.desc" then
      return strcmputf8i(a.info.realm, b.info.realm) > 0
    elseif self.db.global.sorting == "rating.asc" then
      return a.mythicplus.rating < b.mythicplus.rating
    elseif self.db.global.sorting == "rating.desc" then
      return a.mythicplus.rating > b.mythicplus.rating
    elseif self.db.global.sorting == "ilvl.asc" then
      return a.info.ilvl.level < b.info.ilvl.level
    elseif self.db.global.sorting == "ilvl.desc" then
      return a.info.ilvl.level > b.info.ilvl.level
    elseif self.db.global.sorting == "class.asc" then
      return strcmputf8i(a.info.class.name, b.info.class.name) < 0
    elseif self.db.global.sorting == "class.desc" then
      return strcmputf8i(a.info.class.name, b.info.class.name) > 0
    elseif self.db.global.sorting == "custom" then
      return (a.order or 0) < (b.order or 0)
    end
    return a.lastUpdate > b.lastUpdate
  end)

  -- Filters
  if unfiltered then
    return characters
  end

  local charactersFiltered = {}
  for _, character in ipairs(characters) do
    local keep = true
    if not character.enabled then
      keep = false
    end
    local account = character.accountId and self.db.global.accounts[character.accountId]
    if account and account.enabled == false then
      keep = false
    end
    if self.db.global.showNonMaxLevelCharacters == false and not self:IsMaxLevelCharacter(character) then
      keep = false
    end
    if self.db.global.showZeroRatedCharacters == false
      and self:IsMaxLevelCharacter(character)
      and (character.mythicplus.rating and character.mythicplus.rating <= 0)
    then
      keep = false
    end
    if keep then
      table.insert(charactersFiltered, character)
    end
  end

  return charactersFiltered
end

---Update everything!
function Data:UpdateDB()
  self:UpdateCharacterInfo()
  self:UpdatePreyProgress()
  self:UpdateLabyrinthProgress()
  self:UpdateEquipment()
  self:UpdateMoney()
  self:UpdateCurrencies()
  self:UpdateKeystoneItem()
  self:UpdateRaidInstances()
  self:UpdateVault()
  self:UpdateMythicPlus()
  addon.Core:RequestSyncBroadcast()
end

---Run database migrations when dbVersion changes
function Data:MigrateDB()
  ---@diagnostic disable: undefined-field, inject-field
  if type(self.db.global.dbVersion) ~= "number" then
    self.db.global.dbVersion = self.dbVersion
  end
  if self.db.global.dbVersion < self.dbVersion then
    if self.db.global.dbVersion == 1 then
      for characterIndex in pairs(self.db.global.characters) do
        self.db.global.characters[characterIndex].raids.killed = nil
        if self.db.global.characters[characterIndex].raids.savedInstances then
          for savedInstanceIndex, savedInstance in ipairs(self.db.global.characters[characterIndex].raids.savedInstances) do
            if savedInstance.instanceID == 2549 and savedInstance.encounters then
              self.db.global.characters[characterIndex].raids.savedInstances[savedInstanceIndex].encounters[4].instanceEncounterID = 2731
              self.db.global.characters[characterIndex].raids.savedInstances[savedInstanceIndex].encounters[5].instanceEncounterID = 2728
            end
          end
        end
      end
    end
    -- Add missing affix IDs
    if self.db.global.dbVersion == 10 then
      local affixes = self:GetAffixes()
      for characterIndex in pairs(self.db.global.characters) do
        local character = self.db.global.characters[characterIndex]
        if character.mythicplus.dungeons ~= nil then
          TableForEach(character.mythicplus.dungeons, function(dungeon)
            TableForEach(dungeon.affixScores, function(affixScore)
              local affix = TableGet(affixes, "name", affixScore.name)
              if affixScore.id == nil then
                affixScore.id = affix and affix.id or 0
              end
            end)
          end)
        end
      end
    end
    -- Convert season ID from display ID to season major version ID
    if self.db.global.dbVersion == 15 then
      for _, character in pairs(self.db.global.characters) do
        if character.currentSeason ~= nil and character.currentSeason == 3 then
          character.currentSeason = 11
        end
      end
    end
    -- Fix SavedInstance/EncounterJournal name mismatch for "Sennarth, t|The Cold Breath"
    if self.db.global.dbVersion == 16 then
      for _, character in pairs(self.db.global.characters) do
        if character.raids and character.raids.savedInstances then
          for _, savedInstance in pairs(character.raids.savedInstances) do
            if savedInstance.instanceID == 2522 and savedInstance.encounters then
              for _, encounter in pairs(savedInstance.encounters) do
                if encounter.index and encounter.index == 5 and encounter.instanceEncounterID == 0 then
                  encounter.instanceEncounterID = 2592
                end
              end
            end
          end
        end
      end
    end
    -- Midnight Pre-patch stat squish
    if self.db.global.dbVersion == 30 then
      local function GetPostSquishItemLevel(preSquishItemLevel)
        return C_CurveUtil.EvaluateGameCurve(92181, preSquishItemLevel)
      end
      for _, character in pairs(self.db.global.characters) do
        character.info.ilvl.level = GetPostSquishItemLevel(character.info.ilvl.level) or 0
        character.info.ilvl.pvp = GetPostSquishItemLevel(character.info.ilvl.pvp) or 0
        character.info.ilvl.level = GetPostSquishItemLevel(character.info.ilvl.level) or 0
        for _, equipment in pairs(character.equipment or {}) do
          equipment.itemLevel = GetPostSquishItemLevel(equipment.itemLevel) or 0
          equipment.itemMinLevel = GetPostSquishItemLevel(equipment.itemMinLevel) or 0
        end
      end
    end
    -- Add prey progress slice if missing
    if self.db.global.dbVersion == 33 then
      for _, character in pairs(self.db.global.characters) do
        if character.prey == nil or character.prey.questsCompleted == nil then
          character.prey = {
            questsCompleted = {},
          }
        end
      end
    end
    if self.db.global.dbVersion == 34 then
      local interface = self.db.global.interface
      ---@type LiqUI_DB
      local liqui = {
        windows = {},
        tables = {},
        loggers = {},
      }
      for _, windowName in ipairs({"Main", "Affixes", "Equipment"}) do
        ---@type LiqUI_WindowDB
        local windowSettings = {}
        if interface and interface.windowScale then
          windowSettings.scale = interface.windowScale
        end
        if interface and interface.windowColor then
          windowSettings.windowColor = TableCopy(interface.windowColor)
        end
        liqui.windows[windowName] = windowSettings
      end
      self.db.global.liqui = liqui
    end
    if self.db.global.dbVersion == 35 then
      if self.db.global.preyHunts ~= nil then
        self.db.global.prey = self.db.global.preyHunts
        self.db.global.preyHunts = nil
      end
      for _, character in pairs(self.db.global.characters) do
        if character.preyHunts ~= nil then
          character.prey = character.preyHunts
          character.preyHunts = nil
        end
      end
      self.db.global.raids.killIcon = "skull"
      self.db.global.raids.boxes = nil
    end
    if self.db.global.dbVersion == 36 then
      self.db.global.currentCharacterMarker = "dot"
    end
    -- Introduces WoW Account grouping in the Characters menu. Every existing
    -- character gets bucketed into one auto-created account ("1") so
    -- nothing changes visually until the user renames/splits things.
    if self.db.global.dbVersion == 38 then
      if TableCount(self.db.global.accounts) == 0 then
        local defaultAccountId = self:CreateAccount()
        for _, character in pairs(self.db.global.characters) do
          if character.accountId == nil then
            character.accountId = defaultAccountId
          end
        end
      end
    end
    -- Renamed Sync's "passphrase" to "password" -- purely a terminology
    -- change (it's just a shared word/phrase between your own accounts,
    -- not a security credential), so this only carries existing values
    -- across to the renamed fields.
    if self.db.global.dbVersion == 39 then
      local sync = self.db.global.sync
      if sync then
        if sync.passphrase ~= nil then
          sync.password = sync.passphrase
          sync.passphrase = nil
        end
        if sync.passphraseAccounts ~= nil then
          sync.passwordAccounts = sync.passphraseAccounts
          sync.passphraseAccounts = nil
        end
      end
    end
    -- Add the first per-character Daily Delves state.
    if self.db.global.dbVersion == 40 then
      for _, character in pairs(self.db.global.characters) do
        if type(character.dailyDelves) ~= "table" then
          character.dailyDelves = {}
        end
        if character.dailyDelves.bountifulDone == nil then
          character.dailyDelves.bountifulDone = false
        end
      end
    end
    -- Replace the old manual all-done flag with automatic per-Delve tracking.
    if self.db.global.dbVersion == 41 then
      local settings = self.db.global.dailyDelves
      settings.bountifulResetAt = 0
      settings.bountifulRotation = {}
      settings.variantCache = {}
      for _, character in pairs(self.db.global.characters) do
        if type(character.dailyDelves) ~= "table" then
          character.dailyDelves = {}
        end
        character.dailyDelves.checkBountifulDone = false
        character.dailyDelves.bountifulResetAt = 0
        character.dailyDelves.bountifulSeen = {}
        character.dailyDelves.bountifulDone = {}
      end
    end
    -- Make the Bountiful completion-check preference global while keeping
    -- seen/done tracking per character. Preserve an enabled preference if
    -- any character had it enabled before this migration.
    if self.db.global.dbVersion == 42 then
      local settings = self.db.global.dailyDelves
      local enabled = settings.checkBountifulDone == true
      for _, character in pairs(self.db.global.characters) do
        if type(character.dailyDelves) == "table" then
          if character.dailyDelves.checkBountifulDone == true then
            enabled = true
          end
          character.dailyDelves.checkBountifulDone = nil
        end
      end
      settings.checkBountifulDone = enabled
    end
    -- Track delivery-confirmed Sync state separately from merely-sent state.
    -- Existing installations start empty and learn confirmations naturally as peers communicate.
    if self.db.global.dbVersion == 43 then
      local sync = self.db.global.sync
      sync.lastConfirmedUpdate = sync.lastConfirmedUpdate or {}
      sync.lastSuccessfulSyncAt = sync.lastSuccessfulSyncAt or 0
      sync.lastSuccessfulSyncPeer = sync.lastSuccessfulSyncPeer or ""
    end
    -- Give character records a dedicated monotonic Sync revision. Seed it from the old
    -- lastUpdate-based bookkeeping, then advance OWN/Main-account characters once so the
    -- first post-upgrade reconciliation repairs any stale equal-lastUpdate snapshots created
    -- by the old scheme. Synced-in/non-Main characters keep their received version unchanged.
    if self.db.global.dbVersion == 44 then
      local sync = self.db.global.sync
      local mainAccountId = self:GetMainAccountId()
      local defaultAccountId = self:EnsureDefaultAccount()
      sync.lastSentRevision = sync.lastSentRevision or {}
      sync.lastConfirmedRevision = sync.lastConfirmedRevision or {}
      for GUID, character in pairs(self.db.global.characters or {}) do
        local baseRevision = tonumber(character.syncRevision) or tonumber(character.lastUpdate) or 0
        local characterAccountId = character.accountId or defaultAccountId
        character.syncRevision = baseRevision
        if mainAccountId and characterAccountId == mainAccountId then
          character.syncRevision = baseRevision + 1
        end
        if sync.lastSentRevision[GUID] == nil and sync.lastSentUpdate then
          sync.lastSentRevision[GUID] = tonumber(sync.lastSentUpdate[GUID])
        end
        if sync.lastConfirmedRevision[GUID] == nil and sync.lastConfirmedUpdate then
          sync.lastConfirmedRevision[GUID] = tonumber(sync.lastConfirmedUpdate[GUID])
        end
      end
    end
    -- Rename the Bonus Roll feature's technical storage from the old plural
    -- identifiers while preserving every existing character history and window setting.
    if self.db.global.dbVersion == 45 then
      local windows = self.db.global.liqui and self.db.global.liqui.windows
      if windows then
        if windows.BonusRoll == nil and windows.BonusRolls ~= nil then
          windows.BonusRoll = windows.BonusRolls
        end
        windows.BonusRolls = nil
      end
      for _, character in pairs(self.db.global.characters or {}) do
        local old = character.bonusRolls
        local current = character.bonusRoll
        if old ~= nil then
          local oldUpdated = type(old) == "table" and tonumber(old.updatedAt) or 0
          local currentUpdated = type(current) == "table" and tonumber(current.updatedAt) or 0
          if current == nil or oldUpdated > currentUpdated then
            character.bonusRoll = old
          end
          character.bonusRolls = nil
        end
      end
    end
    -- Fold the previous PTR-only Kindo'jan weekly currency into the
    -- Labyrinth itself, including offline and synced characters.
    if self.db.global.dbVersion == 46 then
      for _, character in pairs(self.db.global.characters or {}) do
        local entries = character.currencies or {}
        for index = #entries, 1, -1 do
          local entry = entries[index]
          if type(entry) == "table" and entry.id == "kindojanBounty" then
            if entry.questCompleted == true and self:IsSameWeeklyReset(entry.resetAt, self.db.global.weeklyReset) then
              character.labyrinth = character.labyrinth or {}
              character.labyrinth.killResetAt = self.db.global.weeklyReset
            end
            table.remove(entries, index)
          end
        end
      end
      if self.db.global.trackerOverrides then
        self.db.global.trackerOverrides.kindojanBounty = nil
      end
      for _, section in ipairs({"weeklies", "seasonalChores", "currencies"}) do
        local settings = self.db.global[section]
        if settings and settings.hiddenCurrencies then
          settings.hiddenCurrencies.kindojanBounty = nil
        end
      end
    end
    -- Retire the separate Ancestral Bounty marker. The weekly Nemesis
    -- kill is the sole completion state shown in the Labyrinth tracker.
    if self.db.global.dbVersion == 47 then
      for _, character in pairs(self.db.global.characters or {}) do
        if type(character.labyrinth) == "table" then
          character.labyrinth.bountyResetAt = nil
        end
      end
    end
    -- Older builds inferred chambers from a nine-stage scenario, which is
    -- not how Labyrinth chambers are represented. Drop those estimates but
    -- keep the previously recorded weekly Nemesis kill and tier information.
    if self.db.global.dbVersion == 48 then
      for _, character in pairs(self.db.global.characters or {}) do
        local progress = character.labyrinth
        if type(progress) == "table" then
          progress.active = false
          progress.chambers = nil
          progress.lastChambers = nil
          progress.lastTier = progress.tier
          progress.runStartedAt = nil
          progress.lastChamberAt = nil
          progress.weeklyChambers = 0
          progress.weeklyResetAt = self.db.global.weeklyReset
          progress.chamberTrackingVersion = 1
        end
      end
    end
    -- Labyrinth no longer duplicates Great Vault / estimated-credit data.
    -- Keep weekly chamber totals and Nemesis kills untouched.
    if self.db.global.dbVersion == 49 then
      for _, character in pairs(self.db.global.characters or {}) do
        local progress = character.labyrinth
        if type(progress) == "table" then
          progress.weeklyCredits = nil
          progress.weeklyNemesisCredit = nil
          progress.runCreditedChambers = nil
          progress.worldVaultProgress = nil
          progress.worldVaultThreshold = nil
        end
      end
    end
    -- Existing Sync users should not be treated as first-time users just
    -- because older versions did not track whether the tutorial was shown.
    -- A prior action that left all settings at their defaults is unknowable.
    if self.db.global.dbVersion == 50 then
      local sync = self.db.global.sync
      if sync and (sync.enabled == true
        or (sync.password or "") ~= ""
        or sync.onlyMaxLevelCharacters == false
        or (sync.channel or "GUILD") ~= "GUILD"
        or (tonumber(sync.lastSuccessfulSyncAt) or 0) > 0
        or (sync.lastSentRevision and next(sync.lastSentRevision))
        or (sync.lastConfirmedRevision and next(sync.lastConfirmedRevision))
        or (sync.passwordAccounts and next(sync.passwordAccounts))) then
        sync.tutorialShown = true
      end
    end
    self.db.global.dbVersion = self.db.global.dbVersion + 1
    self:MigrateDB()
  end
  ---@diagnostic enable: undefined-field, inject-field
end

---Two WoW accounts can calculate the same regional weekly reset a few seconds
---apart. Accept that clock/API jitter, but never equate different weekly cycles.
---The hour-long allowance is far below the seven-day reset interval.
function Data:IsSameWeeklyReset(first, second)
  first, second = tonumber(first), tonumber(second)
  return first ~= nil and second ~= nil and first > 0 and second > 0
    and math.abs(first - second) <= 3600
end

---The Labyrinth's regional weekly reset is shared with the existing
---Nemesis and Great Vault trackers. Do not treat a wipe as a kill.
function Data:SetKindoJanKillCompleted(character, completed)
  if not character or character.GUID ~= UnitGUID("player") then return end
  character.labyrinth = character.labyrinth or {}
  local progress = character.labyrinth
  local nextReset = self.db.global.weeklyReset
  local value = completed == true and nextReset or nil
  if progress.killResetAt == value or self:IsSameWeeklyReset(progress.killResetAt, value) then return end
  progress.killResetAt = value
  -- Nemesis completion is tracked independently from chamber totals.
  -- The native Great Vault tracker handles World Activities separately.
  self:MarkCharacterSyncChanged(character)
  addon.Core:Render()
end

---Kindo'jan is the only boss encounter in the Labyrinth. A positive
---ENCOUNTER_END (or BOSS_KILL) while inside instance 3043 is therefore
---sufficient, regardless of the client's locale or the encounter's name.
---A failed encounter must never mark the weekly Nemesis kill. Separately,
---UpdateLabyrinthProgress checks the official lifetime statistic for an
---increase observed during the same run as a fallback, not as a weekly flag.
function Data:RecordKindoJanEncounter(succeeded)
  if succeeded ~= true then return false end
  local _, _, _, interface = GetBuildInfo()
  if (tonumber(interface) or 0) < 120105 then return false end
  if not self:IsInLabyrinth() then return false end
  local character = self:GetCharacter()
  if not character then return false end
  self:SetKindoJanKillCompleted(character, true)
  return true
end

---Perform weekly reset tasks (e.g., vault, weekly-earn currency progress for offline alts)
function Data:TaskWeeklyReset()
  if type(self.db.global.weeklyReset) == "number" and self.db.global.weeklyReset <= time() then
    TableForEach(self.db.global.characters, function(character)
      -- Check if vault has available rewards
      TableForEach(character.vault.slots, function(slot)
        if slot.progress >= slot.threshold then
          character.vault.hasAvailableRewards = true
        end
      end)
      -- A new reward cycle has started. Until this character actually opens
      -- the native Great Vault again, keep the main row in the green
      -- "Rewards" state and expose no reward history from the prior cycle.
      character.vault.openedForReset = 0
      character.vault.lastSnapshot = nil
      -- Mark previous m+ runs as not this week
      TableForEach(character.mythicplus.runHistory, function(run)
        run.thisWeek = false
      end)
      -- Weekly Nemesis kill resets with the regional weekly cycle.
      if type(character.labyrinth) == "table" then
        local progress = character.labyrinth
        progress.killResetAt = nil
        progress.weeklyChambers = 0
        progress.weeklyResetAt = nil
        -- A weekly reset does not end an active physical Labyrinth run.
      end
      -- Reset Prey Hunts, including the Nightmare weekly quest fallback.
      character.prey.questsCompleted = wipe(character.prey.questsCompleted or {})
      character.prey.nightmareWeeklyProgress = 0
      character.vault.activityEncounterInfo = wipe(character.vault.activityEncounterInfo or {})
      character.vault.slots = wipe(character.vault.slots or {})
      character.vault.worldActivityProgress = wipe(character.vault.worldActivityProgress or {})
      character.mythicplus.keystone = wipe(character.mythicplus.keystone or {})
      character.mythicplus.numCompletedDungeonRuns = wipe(character.mythicplus.numCompletedDungeonRuns or {})
      -- Reset quantityEarnedThisWeek if maxWeeklyQuantity is set
      TableForEach(character.currencies or {}, function(characterCurrency)
        if characterCurrency.maxWeeklyQuantity and characterCurrency.maxWeeklyQuantity > 0 then
          characterCurrency.quantityEarnedThisWeek = 0
        end
        if characterCurrency.currencyType == "delveMap"
          or (characterCurrency.currencyType == "quest" and characterCurrency.resets == "weekly") then
          characterCurrency.questCompleted = false
        end
      end)
      self:MarkCharacterSyncChanged(character)
    end)
  end
  self.db.global.weeklyReset = time() + C_DateAndTime.GetSecondsUntilWeeklyReset()
end

---Perform season reset tasks
function Data:TaskSeasonReset()
  local seasonID = LiqUI.Data:GetCurrentSeason()
  if seasonID then
    TableForEach(self.db.global.characters, function(character)
      if character.currentSeason == nil or character.currentSeason < seasonID then
        wipe(character.mythicplus.runHistory or {})
        wipe(character.mythicplus.dungeons or {})
        wipe(character.currencies or {})
        character.mythicplus.rating = 0
        character.currentSeason = seasonID
        character.currentSeasonID = seasonID
        self:MarkCharacterSyncChanged(character)
      end
    end)
  end
end

---Read the Encounter Journal once per encounter; use one instance per frame.
---@param entry AE_Raid|AE_Dungeon
local function loadEncounters(entry)
  local journalInstanceID = entry.journalInstanceID
  if not journalInstanceID and entry.instanceID and EJ_GetInstanceByIndex then
    -- Newly added raid IDs may not have a stable journal ID in pre-launch data.
    -- Resolve it by the real map/instance ID, without guessing a journal ID.
    if EJ_GetNumTiers and EJ_SelectTier then
      EJ_SelectTier(EJ_GetNumTiers())
    end
    for raidIndex = 1, 40 do
      local candidateID, _, _, _, _, _, _, _, _, _, mapID = EJ_GetInstanceByIndex(raidIndex, true)
      if not candidateID then break end
      if mapID == entry.instanceID then
        journalInstanceID = candidateID
        entry.journalInstanceID = candidateID
        break
      end
    end
  end
  if journalInstanceID then EJ_SelectInstance(journalInstanceID) end
  local encounterIndex = 1
  while true do
    if not journalInstanceID then break end
    local name, description, journalEncounterID, journalEncounterSectionID, journalLink,
      encounterJournalInstanceID, instanceEncounterID, instanceID = EJ_GetEncounterInfoByIndex(encounterIndex, journalInstanceID)
    if not journalEncounterID then break end
    local iconImage
    if EJ_SelectEncounter and EJ_GetCreatureInfo then
      EJ_SelectEncounter(journalEncounterID)
      iconImage = select(5, EJ_GetCreatureInfo(1))
    end
    ---@type LiqUI_Encounter
    entry.encounters[encounterIndex] = {
      index = encounterIndex,
      name = name,
      description = description,
      iconImage = iconImage,
      journalInstanceID = encounterJournalInstanceID,
      journalEncounterID = journalEncounterID,
      journalEncounterSectionID = journalEncounterSectionID,
      journalLink = journalLink,
      instanceID = instanceID,
      instanceEncounterID = instanceEncounterID,
    }
    encounterIndex = encounterIndex + 1
  end
  -- Preserve this fork's missing-journal fallbacks for newly released raids.
  if entry.numEncounters and #entry.encounters == 0 and entry.numEncounters > 0 then
    for placeholderIndex = 1, entry.numEncounters do
      entry.encounters[placeholderIndex] = {
        index = placeholderIndex,
        name = entry.instanceID == 3095 and "Kith'ix" or format("%s (%d)", entry.name, placeholderIndex),
        instanceID = entry.instanceID,
      }
    end
  end
end

---Load cheap season data immediately; spread Encounter Journal scans over frames.
---@param onComplete fun()?
function Data:loadGameData(onComplete)
  local seasonID = self:GetCurrentSeason()
  local pending = {}

  for _, raid in ipairs(self:GetRaids()) do
    if raid.seasonID == seasonID then
      raid.modifiedInstanceInfo = C_ModifiedInstance.GetModifiedInstanceInfoFromMapID(raid.instanceID)
      pending[#pending + 1] = raid
    end
  end

  for _, dungeon in ipairs(self:GetDungeons()) do
    if dungeon.seasonID == seasonID then
      local dungeonName, _, dungeonTimeLimit, dungeonTexture = C_ChallengeMode.GetMapUIInfo(dungeon.challengeModeID)
      dungeon.name = dungeonName
      dungeon.time = dungeonTimeLimit
      dungeon.texture = dungeon.texture ~= 0 and dungeonTexture or "Interface/Icons/achievement_bg_wineos_underxminutes"
      pending[#pending + 1] = dungeon
    end
  end

  for _, affix in pairs(self.affixes) do
    local name, description, fileDataID = C_ChallengeMode.GetAffixInfo(affix.id)
    affix.name = name
    affix.description = description
    affix.fileDataID = fileDataID
  end

  local index = 0
  local function loadNext()
    index = index + 1
    local entry = pending[index]
    if not entry then
      if onComplete then onComplete() end
      return
    end
    loadEncounters(entry)
    C_Timer.After(0, loadNext)
  end
  loadNext()
end

---Refresh saved raid instances from the API
function Data:UpdateRaidInstances()
  local character = self:GetCharacter()
  if not character then return end
  character.raids.savedInstances = wipe(character.raids.savedInstances or {})

  local raids = self:GetRaids()
  local numSavedInstances = GetNumSavedInstances()
  if numSavedInstances == 0 then return end

  for savedInstanceIndex = 1, numSavedInstances do
    local name, lockoutId, reset, difficultyID, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress, extendDisabled, instanceID = GetSavedInstanceInfo(savedInstanceIndex)
    local raid = TableGet(raids, "instanceID", instanceID)
    ---@type AE_SavedInstance
    local savedInstance = {
      index = savedInstanceIndex,
      id = lockoutId,
      name = name,
      lockoutId = lockoutId,
      reset = reset,
      difficultyID = difficultyID,
      locked = locked,
      extended = extended,
      instanceIDMostSig = instanceIDMostSig,
      isRaid = isRaid,
      maxPlayers = maxPlayers,
      difficultyName = difficultyName,
      numEncounters = numEncounters,
      encounterProgress = encounterProgress,
      extendDisabled = extendDisabled,
      instanceID = instanceID,
      link = GetSavedInstanceChatLink(savedInstanceIndex),
      expires = 0,
      encounters = {},
    }
    if reset and reset > 0 then
      savedInstance.expires = reset + time()
    end
    for encounterIndex = 1, numEncounters do
      local bossName, fileDataID, isKilled = GetSavedInstanceEncounterInfo(savedInstanceIndex, encounterIndex)
      local instanceEncounterID = 0
      if raid and bossName then
        TableForEach(raid.encounters, function(encounter)
          if encounter.name and string.lower(encounter.name) == string.lower(bossName) then
            instanceEncounterID = encounter.instanceEncounterID or 0
          end
        end)
      end
      ---@type AE_SavedInstanceEncounter
      local savedInstanceEncounter = {
        index = encounterIndex,
        instanceEncounterID = instanceEncounterID,
        bossName = bossName,
        fileDataID = fileDataID or 0,
        isKilled = isKilled,
      }
      savedInstance.encounters[encounterIndex] = savedInstanceEncounter
    end
    character.raids.savedInstances[savedInstanceIndex] = savedInstance
  end
  addon.Core:Render()
  self:MarkCharacterSyncChanged(character)
end

-- These IDs are from the 12.1.5 client data and the DelveGuide PTR
-- observations. No dependency on DelveGuide is introduced.
local LABYRINTH_INSTANCE_ID = 3043
local LABYRINTH_TIER_ACHIEVEMENTS = {
  63863, 63864, 63865, 63846, 63847, 63848, 63849, 63850, 63851, 63852, 63853,
}

function Data:IsInLabyrinth()
  local _, _, _, _, _, _, _, mapID = GetInstanceInfo()
  return type(mapID) == "number" and mapID == LABYRINTH_INSTANCE_ID
end

local function ReadNemesisKillStatistic()
  if type(GetStatistic) ~= "function" then return end
  local ok, value = pcall(GetStatistic, 63731)
  if not ok or type(value) ~= "string" and type(value) ~= "number" then return end
  -- GetStatistic is localized presentation text; strip grouping separators.
  if type(value) == "string" then
    if value == "--" or value == "" then return end
    value = value:gsub("[^%d]", "")
  end
  return tonumber(value)
end

---The Labyrinth header is a ScenarioHeaderDelves widget (type 29).
---C_DelvesUI.GetActiveDelveTier may return 0 inside a Labyrinth.
local function ReadLabyrinthTier()
  if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID
    and C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo then
    local widgetSetID
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
      local ok, step = pcall(C_ScenarioInfo.GetScenarioStepInfo)
      if ok then widgetSetID = type(step) == "table" and step.widgetSetID end
    end
    if (not widgetSetID or widgetSetID == 0) and C_Scenario and C_Scenario.GetStepInfo then
      local ok, id = pcall(function() return select(12, C_Scenario.GetStepInfo()) end)
      if ok then widgetSetID = id end
    end
    if type(widgetSetID) == "number" and widgetSetID > 0 then
      local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, widgetSetID)
      if ok and type(widgets) == "table" then
        for _, widget in ipairs(widgets) do
          if widget.widgetType == 29 then
            local valid, info = pcall(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo, widget.widgetID)
            local text = valid and info and info.tierText
            if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
              local tier = tonumber(text:match("(%d+)"))
              if tier and tier >= 1 and tier <= 11 then return tier end
            end
          end
        end
      end
    end
  end
  if C_DelvesUI and C_DelvesUI.GetActiveDelveTier then
    local ok, tier = pcall(C_DelvesUI.GetActiveDelveTier)
    if ok and type(tier) == "number" and tier >= 1 and tier <= 11 then return tier end
  end
end

---The achievement ladder records "3 chambers at Tier N", unlocking N+1.
---Do not classify an unknown achievement API response as zero progress.
function Data:UpdateLabyrinthUnlockedTier(force)
  local character = self:GetCharacter()
  if not character then return end
  local now = time()
  if not force and self.cache.labyrinthAchievementCheckedAt
    and now - self.cache.labyrinthAchievementCheckedAt < 60 then return end
  self.cache.labyrinthAchievementCheckedAt = now
  if type(GetAchievementInfo) ~= "function" then return end
  local highestCleared, known = 0, false
  for tier, id in ipairs(LABYRINTH_TIER_ACHIEVEMENTS) do
    local ok, achievementID, _, _, completed = pcall(GetAchievementInfo, id)
    if ok and achievementID == id then
      known = true
      if completed then highestCleared = tier end
    end
  end
  if not known then return end
  local progress = character.labyrinth or {}
  local unlocked = math.min(11, highestCleared + 1)
  if progress.highestUnlockedTier ~= unlocked then
    progress.highestUnlockedTier = unlocked
    character.labyrinth = progress
    self:MarkCharacterSyncChanged(character)
    addon.Core:Render()
  end
end

---A completion event represents one chamber; the scenario step counter does
---not. Save counters per physical visit so /reload and DC can resume safely.
---A five-second debounce prevents duplicated SCENARIO_COMPLETED events.
function Data:RecordLabyrinthChamber()
  if not self:IsInLabyrinth() then return false end
  local character = self:GetCharacter()
  if not character then return false end
  self:UpdateLabyrinthProgress()
  local progress = character.labyrinth
  if not progress or not progress.active then return false end
  local now = time()
  if progress.lastChamberAt and now - progress.lastChamberAt < 5 then return false end
  if (progress.chambers or 0) >= 9 then return false end
  progress.lastChamberAt = now
  progress.chambers = (progress.chambers or 0) + 1
  progress.lastChambers = progress.chambers
  progress.lastTier = progress.tier or progress.lastTier
  if not self:IsSameWeeklyReset(progress.weeklyResetAt, self.db.global.weeklyReset) then
    progress.weeklyResetAt = self.db.global.weeklyReset
    progress.weeklyChambers = 0
  end
  progress.weeklyChambers = (progress.weeklyChambers or 0) + 1
  character.alterEgoTrackingVersion = 3
  self:MarkCharacterSyncChanged(character)
  addon.Core:Render()
  return true
end

---Update only on entry, exit, scenario/widget changes and short deferred
---updates. Never infer chambers from the number of scenario stages.
function Data:UpdateLabyrinthProgress()
  local character = self:GetCharacter()
  if not character then return end
  local progress = character.labyrinth or {}
  local now = time()
  local changed = false
  if not self:IsInLabyrinth() then
    if progress.active then
      progress.active = false
      progress.lastChambers = progress.chambers
      progress.lastTier = progress.tier
      progress.chambers = nil
      progress.runStartedAt = nil
      progress.lastSeenAt = nil
      progress.nemesisStatistic = nil
      changed = true
    end
  else
    -- A new visit follows a confirmed exit or an abandoned session older
    -- than three hours. Reloads and short disconnects continue the same run.
    local stale = progress.lastSeenAt and now - progress.lastSeenAt > 10800
    if not progress.active or stale or not progress.runStartedAt then
      progress.active = true
      progress.runStartedAt = now
      progress.chambers = 0
      progress.tier = nil
      progress.lastChamberAt = nil
      progress.nemesisStatistic = ReadNemesisKillStatistic()
      changed = true
    end
    -- Avoid sync churn: the time of a live observation is local recovery
    -- metadata and does not need to be transmitted on every event.
    progress.lastSeenAt = now
    local tier = ReadLabyrinthTier()
    if tier and progress.tier ~= tier then
      progress.tier = tier
      progress.lastTier = tier
      changed = true
    end
    -- The official lifetime kill statistic (DelveGuide: 63731) is only
    -- supporting evidence: an increase since an observation from THIS run
    -- confirms a new kill. A lifetime total alone proves no weekly status.
    -- Keep the highest sample: an API glitch returning a lower value must
    -- not create a false kill when the previous total reappears.
    local kills = ReadNemesisKillStatistic()
    local previousKills = progress.nemesisStatistic
    if kills and previousKills and kills > previousKills then
      self:SetKindoJanKillCompleted(character, true)
    end
    if kills and (not previousKills or kills > previousKills) then
      progress.nemesisStatistic = kills
    end
  end
  progress.chamberTrackingVersion = 1
  character.labyrinth = progress
  self:UpdateLabyrinthUnlockedTier(false)
  if changed then
    character.alterEgoTrackingVersion = 3
    self:MarkCharacterSyncChanged(character)
    addon.Core:Render()
  end
end

---Compare persisted snapshots without relying on freshly allocated table identity.
---Used for Prey quest flags, currencies and equipment to avoid redundant Sync revisions.
local function SavedSnapshotEqual(a, b)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return false end
  for key, value in pairs(a) do
    if not SavedSnapshotEqual(value, b[key]) then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

function Data:UpdatePreyProgress()
  local character = self:GetCharacter()
  if not character then return end
  character.prey = character.prey or {}
  local previousQuests = character.prey.questsCompleted
  local questsCompleted = {}
  TableForEach(self.preyQuests, function(quest)
    questsCompleted[quest.questID] = C_QuestLog.IsQuestFlaggedCompleted(quest.questID)
  end)
  local questsChanged = not SavedSnapshotEqual(previousQuests or {}, questsCompleted)
  character.prey.questsCompleted = questsChanged and questsCompleted or (previousQuests or questsCompleted)

  -- Some hunts accelerated by soul items advance the Nightmare weekly
  -- objective without flagging the individual Prey quest as completed.
  -- Remember the weekly objective for other characters and after turn-in.
  local weeklyQuestID = self.preyNightmareWeeklyQuestID
  local previousProgress = character.prey.nightmareWeeklyProgress or 0
  local weeklyProgress = 0
  if C_QuestLog.IsQuestFlaggedCompleted(weeklyQuestID)
    or (C_QuestLog.IsComplete and C_QuestLog.IsComplete(weeklyQuestID)) then
    weeklyProgress = 3
  elseif C_QuestLog.GetQuestObjectives then
    local objectives = C_QuestLog.GetQuestObjectives(weeklyQuestID)
    for _, objective in ipairs(objectives or {}) do
      if objective.numRequired == 3 then
        weeklyProgress = math.max(weeklyProgress, math.min(3, objective.numFulfilled or 0))
      end
    end
  end
  character.prey.nightmareWeeklyProgress = math.max(previousProgress, weeklyProgress)
  if questsChanged or character.prey.nightmareWeeklyProgress ~= previousProgress then
    self:MarkCharacterSyncChanged(character)
    addon.Core:Render()
  end
end

---Compute the character's equipped item level and its "including bags" counterpart using the same
---simple unweighted-average methodology for both, so the two numbers are always directly
---comparable (potential is guaranteed to be >= equipped). Blizzard's own GetAverageItemLevel()
---uses a different (weighted) formula for its equipped value and doesn't factor in bags at all
---despite older documentation suggesting otherwise, so mixing the two produced nonsensical results
---(bags appearing lower than equipped). Computing both ourselves avoids that mismatch.
---@return number? equippedLevel, number? potentialLevel
---Estimate the average per-slot item level upgrade currently sitting unequipped in bags, by
---comparing each equipped item against any matching item in bags and taking the difference. This
---is meant to be added on top of Blizzard's own (official, character-panel-accurate)
---avgItemLevelEquipped, rather than used as a standalone number, since our own per-slot average
---uses different weighting than Blizzard's formula and wouldn't match the character panel if
---displayed directly. Adding a non-negative delta on top keeps the displayed equipped value
---exactly what the character panel shows, while guaranteeing "in bags" is never lower than it.
-- Cached only for this session. Inventory and equipment events invalidate the result;
-- the short TTL is a fallback for API changes that do not fire either event.
local BAG_UPGRADE_SLOT_EQUIP_LOCS = {
  [INVSLOT_HEAD] = { "INVTYPE_HEAD" },
  [INVSLOT_NECK] = { "INVTYPE_NECK" },
  [INVSLOT_SHOULDER] = { "INVTYPE_SHOULDER" },
  [INVSLOT_BACK] = { "INVTYPE_CLOAK" },
  [INVSLOT_CHEST] = { "INVTYPE_CHEST", "INVTYPE_ROBE" },
  [INVSLOT_WRIST] = { "INVTYPE_WRIST" },
  [INVSLOT_HAND] = { "INVTYPE_HAND" },
  [INVSLOT_WAIST] = { "INVTYPE_WAIST" },
  [INVSLOT_LEGS] = { "INVTYPE_LEGS" },
  [INVSLOT_FEET] = { "INVTYPE_FEET" },
  [INVSLOT_FINGER1] = { "INVTYPE_FINGER" },
  [INVSLOT_FINGER2] = { "INVTYPE_FINGER" },
  [INVSLOT_TRINKET1] = { "INVTYPE_TRINKET" },
  [INVSLOT_TRINKET2] = { "INVTYPE_TRINKET" },
  [INVSLOT_MAINHAND] = { "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_RELIC" },
  [INVSLOT_OFFHAND] = { "INVTYPE_WEAPON", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" },
}
local BAG_UPGRADE_TWO_HAND_EQUIP_LOCS = { INVTYPE_2HWEAPON = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }


function Data:InvalidateBagItemLevelUpgrade()
  self.cache.bagItemLevelUpgrade = nil
end

---@return number delta Always >= 0
function Data:CalculateBagItemLevelUpgrade()
  local cached = self.cache.bagItemLevelUpgrade
  local now = GetTime()
  if cached and now - cached.updatedAt < 30 then
    return cached.delta
  end

  local equippedMainHandLink = GetInventoryItemLink("player", INVSLOT_MAINHAND)
  local mainHandIsTwoHanded = false
  if equippedMainHandLink then
    local _, _, _, mainHandEquipLoc = C_Item.GetItemInfoInstant(equippedMainHandLink)
    mainHandIsTwoHanded = mainHandEquipLoc ~= nil and BAG_UPGRADE_TWO_HAND_EQUIP_LOCS[mainHandEquipLoc] == true
  end

  -- Each bag item is queried once even when multiple slots accept its equip location.
  local bestBagLevelByEquipLoc = {}
  for bag = 0, NUM_BAG_SLOTS do
    local numSlots = C_Container.GetContainerNumSlots(bag) or 0
    for containerSlot = 1, numSlots do
      local itemLink = C_Container.GetContainerItemLink(bag, containerSlot)
      if itemLink then
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemLink)
        if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
          local itemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
          if itemLevel and itemLevel > (bestBagLevelByEquipLoc[equipLoc] or 0) then
            bestBagLevelByEquipLoc[equipLoc] = itemLevel
          end
        end
      end
    end
  end

  local deltaTotal, count = 0, 0
  for slotID, equipLocs in pairs(BAG_UPGRADE_SLOT_EQUIP_LOCS) do
    if not (slotID == INVSLOT_OFFHAND and mainHandIsTwoHanded) then
      local equippedLink = GetInventoryItemLink("player", slotID)
      local equippedLevel = equippedLink and C_Item.GetDetailedItemLevelInfo(equippedLink)
      if equippedLevel and equippedLevel > 0 then
        local bestLevel = equippedLevel
        for _, equipLoc in ipairs(equipLocs) do
          bestLevel = math.max(bestLevel, bestBagLevelByEquipLoc[equipLoc] or 0)
        end
        deltaTotal = deltaTotal + (bestLevel - equippedLevel)
        count = count + 1
      end
    end
  end

  local delta = count > 0 and deltaTotal / count or 0
  self.cache.bagItemLevelUpgrade = {updatedAt = now, delta = delta}
  return delta
end

---Refresh general character info from the API
function Data:UpdateCharacterInfo()
  local character = self:GetCharacter()
  if not character then return end

  local previousInfo = TableCopy(character.info)
  local previousLastUpdate = character.lastUpdate
  local playerName = UnitName("player")
  local playerRealm = GetRealmName()
  local playerLevel = UnitLevel("player")
  local playerRaceName, playerRaceFile, playerRaceID = UnitRace("player")
  local playerClassName, playerClassFile, playerClassID = UnitClass("player")
  local playerFactionGroupEnglish, playerFactionGroupLocalized = UnitFactionGroup("player")
  local avgItemLevel, avgItemLevelEquipped, avgItemLevelPvp = GetAverageItemLevel()
  local bagUpgradeDelta = self:CalculateBagItemLevelUpgrade()
  local itemLevelColorR, itemLevelColorG, itemLevelColorB = GetItemLevelColor()
  local guildName, guildRankName, guildRankIndex, guildRealm = GetGuildInfo("player")
  local isInGuild = IsInGuild()

  if playerName then character.info.name = playerName end
  if playerRealm then character.info.realm = playerRealm end
  if playerLevel then character.info.level = playerLevel end
  -- IMPORTANT: these fallbacks must DEEP COPY the template, never assign it
  -- directly. `self.defaultCharacter` is the single shared table used to
  -- seed EVERY character; pointing `character.info.race` (etc.) straight at
  -- `self.defaultCharacter.info.race` makes every character whose info was
  -- ever missing/corrupt share the SAME table object. The very next lines
  -- below then mutate that table in place (`character.info.race.name = ...`),
  -- which silently overwrites the same fields for every OTHER character that
  -- also got aliased onto it -- exactly the "one character's data stomps
  -- everyone else's" symptom, just triggered by this repair path instead of
  -- normal creation (which already deep copies via TableCopy in GetCharacter).
  if type(character.info.race) ~= "table" then character.info.race = TableCopy(self.defaultCharacter.info.race) end
  if playerRaceName then character.info.race.name = playerRaceName end
  if playerRaceFile then character.info.race.file = playerRaceFile end
  if playerRaceID then character.info.race.id = playerRaceID end
  if type(character.info.class) ~= "table" then character.info.class = TableCopy(self.defaultCharacter.info.class) end
  if playerClassName then character.info.class.name = playerClassName end
  if playerClassFile then character.info.class.file = playerClassFile end
  if playerClassID then character.info.class.id = playerClassID end
  if type(character.info.factionGroup) ~= "table" then character.info.factionGroup = TableCopy(self.defaultCharacter.info.factionGroup) end
  if playerFactionGroupEnglish then character.info.factionGroup.english = playerFactionGroupEnglish end
  if playerFactionGroupLocalized then character.info.factionGroup.localized = playerFactionGroupLocalized end
  if avgItemLevel then character.info.ilvl.level = avgItemLevel end
  if avgItemLevelEquipped then character.info.ilvl.equipped = avgItemLevelEquipped end
  if avgItemLevelPvp then character.info.ilvl.pvp = avgItemLevelPvp end
  if avgItemLevelEquipped then character.info.ilvl.potential = avgItemLevelEquipped + bagUpgradeDelta end
  if itemLevelColorR and itemLevelColorG and itemLevelColorB then character.info.ilvl.color = CreateColor(itemLevelColorR, itemLevelColorG, itemLevelColorB):GenerateHexColor() end
  if type(character.info.guild) ~= "table" then character.info.guild = TableCopy(self.defaultCharacter.info.guild) end
  character.info.guild.name = guildName
  character.info.guild.rankName = guildRankName
  character.info.guild.rankIndex = guildRankIndex
  character.info.guild.realm = guildRealm
  character.info.guild.isInGuild = isInGuild

  character.lastUpdate = GetServerTime()
  if not SavedSnapshotEqual(previousInfo, character.info) then
    self:MarkCharacterSyncChanged(character)
    addon.Core:Render()
  elseif previousLastUpdate ~= character.lastUpdate
    and self.db.global.sorting == "lastUpdate"
    and addon.Module_Main and addon.Module_Main.window
    and addon.Module_Main.window:IsVisible() then
    -- The visible main window sorts by this local refresh timestamp.
    addon.Module_Main:Render()
  end
end

---Store the current zone so the character tooltip can show where this
---character was last seen. Zone events keep this current; logout is a fallback.
function Data:UpdateCharacterLocation()
  local character = self:GetCharacter()
  if not character then return end

  local zoneName = GetZoneText()
  if not zoneName or zoneName == "" then
    zoneName = GetRealZoneText()
  end
  if not zoneName or zoneName == "" then return end

  if character.info.lastLocation ~= zoneName then
    character.info.lastLocation = zoneName
    self:MarkCharacterSyncChanged(character)
  end
end

---Refresh character money from the API
function Data:UpdateMoney()
  local character = self:GetCharacter()
  if not character then return end

  local money = GetMoney()
  if not money then return end

  if character.money ~= money then
    character.money = money
    self:MarkCharacterSyncChanged(character)
  end
end

---Refresh currencies from the API
function Data:UpdateCurrencies()
  local character = self:GetCharacter()
  if not character then return end
  local seasonID = LiqUI.Data:GetCurrentSeason()
  local oldCurrencies = character.currencies or {}
  local oldTrackingVersion = character.alterEgoTrackingVersion
  local oldKillResetAt = character.labyrinth and character.labyrinth.killResetAt

  -- Gilded Stash progress is only readable from the API while near Silvermoon City (or otherwise
  -- triggering the spell visual). Grab whatever we already had stored before wiping the table, so
  -- it can be carried forward when the live widget has nothing to report this time.
  local previousGildedStash = TableGet(character.currencies or {}, "id", "gildedStash")
  -- Migrate old weekly Nemesis completion to the Labyrinth without losing
  -- a kill recorded by an earlier PTR build. Obsolete currency rows disappear.
  local previousBounty = TableGet(character.currencies or {}, "id", "kindojanBounty")
  if previousBounty and previousBounty.questCompleted == true
    and self:IsSameWeeklyReset(previousBounty.resetAt, self.db.global.weeklyReset) then
    character.labyrinth = character.labyrinth or {}
    character.labyrinth.killResetAt = self.db.global.weeklyReset
  end
  character.currencies = {}
  character.alterEgoTrackingVersion = 3

  TableForEach(self.currencies or {}, function(dataCurrency)
    if dataCurrency.seasonID ~= nil and dataCurrency.seasonID ~= seasonID then
      return
    end
    if dataCurrency.currencyType == "trackedItem" then
      local name, iconFileID, quality, bagCount, quantity = fetchBagItem(dataCurrency.id)
      table.insert(character.currencies, {
        id = dataCurrency.id, currencyType = dataCurrency.currencyType,
        name = name or dataCurrency.name, quantity = quantity or 0,
        bagCount = bagCount or 0, iconFileID = iconFileID, quality = quality,
      })
      return
    end
    if dataCurrency.currencyType == "quest" then
      local questCompleted = C_QuestLog.IsQuestFlaggedCompleted(dataCurrency.questID) == true
      -- One-time quests can be flagged account-wide (warband) instead of on the character
      if not questCompleted and dataCurrency.resets == "account" and C_QuestLog.IsQuestFlaggedCompletedOnAccount then
        questCompleted = C_QuestLog.IsQuestFlaggedCompletedOnAccount(dataCurrency.questID) == true
      end

      local bagCount = 0
      if dataCurrency.itemID then
        bagCount = C_Item.GetItemCount(dataCurrency.itemID, true) or 0
      end

      ---@type AE_CharacterCurrency
      local questCurrency = {
        id = dataCurrency.id,
        currencyType = dataCurrency.currencyType,
        name = dataCurrency.name,
        iconFileID = dataCurrency.iconFileID,
        resets = dataCurrency.resets,
        questCompleted = questCompleted,
        bagCount = bagCount,
      }
      table.insert(character.currencies, questCurrency)
      return
    end

    if dataCurrency.currencyType == "gildedStash" then
      -- Mirrors how WeeklyRewards reads Gilded Stash progress: this widget is only populated
      -- client-side after visiting Silvermoon City (or otherwise triggering the spell visual).
      local fulfilled = nil
      local widget = dataCurrency.spellID and C_UIWidgetManager.GetSpellDisplayVisualizationInfo(dataCurrency.spellID)
      if widget and widget.spellInfo and widget.spellInfo.tooltip then
        local _, fulfilledText = widget.spellInfo.tooltip:match("COLOR:([^%d]*(%d)/4)")
        fulfilled = tonumber(fulfilledText)
      end

      if fulfilled == nil and previousGildedStash then
        -- Not near Silvermoon (or logged out and back in) right now: keep the last known reading
        -- instead of resetting the display to "No Data".
        fulfilled = previousGildedStash.fulfilled
      end

      ---@type AE_CharacterCurrency
      local gildedStashCurrency = {
        id = dataCurrency.id,
        currencyType = dataCurrency.currencyType,
        name = dataCurrency.name or "Gilded Stash",
        iconFileID = dataCurrency.iconFileID,
        fulfilled = fulfilled,
        total = fulfilled ~= nil and 4 or nil,
      }
      table.insert(character.currencies, gildedStashCurrency)
      return
    end

    local isBagItem = dataCurrency.currencyType == "item" or dataCurrency.currencyType == "delveMap"
    local currencyInfo = nil
    if not isBagItem then
      currencyInfo = C_CurrencyInfo.GetCurrencyInfo(dataCurrency.id)
      if not currencyInfo then return end
    end

    ---@type AE_CharacterCurrency
    local currency = {
      id = dataCurrency.id,
      currencyType = dataCurrency.currencyType,
      quantity = 0,
    }
    if currencyInfo then
      currency = MergeDeep(currency, currencyInfo)
      currency.id = dataCurrency.id
      currency.currencyType = dataCurrency.currencyType
    end

    local itemID = isBagItem and dataCurrency.id or dataCurrency.itemID
    if itemID then
      local itemName, iconFileID, quality, bagCount, quantity = fetchBagItem(itemID)
      currency.quantity = quantity
      currency.bagCount = bagCount
      if iconFileID ~= nil then
        currency.iconFileID = iconFileID
      end
      if quality ~= nil then
        currency.quality = quality
      end
      if dataCurrency.currencyType == "item" then
        currency.name = itemName or dataCurrency.name
      end
    end

    if dataCurrency.currencyType == "delveMap" then
      currency.name = dataCurrency.name or "Trovehunter's Bounty"
      currency.hasBuff = false
      if dataCurrency.spellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(dataCurrency.spellID)
        if aura ~= nil and not issecretvalue(aura) then
          currency.hasBuff = true
        end
      end
      currency.questCompleted = dataCurrency.questID ~= nil and C_QuestLog.IsQuestFlaggedCompleted(dataCurrency.questID) == true
    end

    if dataCurrency.currencyType == "spark" and dataCurrency.itemID then
      -- Keep dust quantity separate from whole Sparks in bags.
      currency.quantity = currencyInfo.quantity or 0
      currency.bagCount = C_Item.GetItemCount(dataCurrency.itemID, false, false, false) or 0
    end
    table.insert(character.currencies, currency)
  end)
  -- Avoid a new Sync revision and network broadcast on every harmless
  -- CURRENCY_DISPLAY_UPDATE or item event. Preserve the previous snapshot
  -- object when equal, including its existing metadata.
  if SavedSnapshotEqual(oldCurrencies, character.currencies) then
    character.currencies = oldCurrencies
    if oldTrackingVersion == character.alterEgoTrackingVersion
      and oldKillResetAt == (character.labyrinth and character.labyrinth.killResetAt) then
      return
    end
  end
  self:MarkCharacterSyncChanged(character)
end

local EMBELLISHED_ITEM_BONUS_ID = 8960
local CRAFTING_REAGENT_MODIFIER_FIRST = 43
local CRAFTING_REAGENT_MODIFIER_LAST = 57

-- Midnight optional-reagent embellishments are encoded directly on the
-- finished crafted item's bonus list. The shared 8960 bonus only marks the
-- item as "Embellished (2)"; the effect-specific bonus below tells us which
-- embellishment reagent was actually used.
--
-- reagentItemID points at one quality of the reagent. Quality variants share
-- the same name/icon/effect, so it is sufficient (and more stable) for the
-- Equipment table icon + reagent tooltip.
local MIDNIGHT_EMBELLISHMENTS_BY_BONUS_ID = {
  [12384] = {name = "Arcanoweave Lining", reagentItemID = 240166, spellID = 1283697},
  [12385] = {name = "Sunfire Silk Lining", reagentItemID = 240164, spellID = 1241711},
  [12685] = {name = "Devouring Banding", reagentItemID = 244674, spellID = 1244238},
  [12686] = {name = "Blessed Pango Charm", reagentItemID = 244603, spellID = 1259060},
  [12687] = {name = "Primal Spore Binding", reagentItemID = 244607, spellID = 1244276},
  [12692] = {name = "Darkmoon Sigil: Rot", reagentItemID = 245877, spellID = 1245055},
  [12693] = {name = "Darkmoon Sigil: Hunt", reagentItemID = 245875, spellID = 1245054},
  [12705] = {name = "Darkmoon Sigil: Blood", reagentItemID = 245871, spellID = 1245053},
  [12990] = {name = "B1P, Scorcher of Souls", reagentItemID = 248135, spellID = 1246309},
  [13453] = {name = "Prismatic Focusing Iris", reagentItemID = 251487, spellID = 1251906},
  [13454] = {name = "Stabilizing Gemstone Bandolier", reagentItemID = 251489, spellID = 1251905},
  [13587] = {name = "M0LL1, Atomic Anomaly", reagentItemID = 257733, spellID = 1261971},
  [13588] = {name = "B0P, Curator of Booms", reagentItemID = 257735, spellID = 1261968},
  [13640] = {name = "Darkmoon Sigil: Void", reagentItemID = 245873, spellID = 1245052},
  [13764] = {name = "Snakeskin Lining", reagentItemID = 270898, spellID = 1296550},
  [13767] = {name = "Adorned Fang", reagentItemID = 273068, spellID = 1296870},
  [13768] = {name = "Polished Ammolite", reagentItemID = 273065, spellID = 1296982},
  [13769] = {name = "Coiled Snake-Eye", reagentItemID = 273062, spellID = 1297384},
  [13771] = {name = "Hunter's Ritual Stone", reagentItemID = 273060, spellID = 1297382},
}

local MIDNIGHT_EMBELLISHMENTS_BY_SPELL_ID = {}
for _, embellishment in pairs(MIDNIGHT_EMBELLISHMENTS_BY_BONUS_ID) do
  MIDNIGHT_EMBELLISHMENTS_BY_SPELL_ID[embellishment.spellID] = embellishment
end

---@param itemLink string?
---@return number[]
local function getEquipmentItemBonusIDs(itemLink)
  local bonusIDs = {}
  if not itemLink then return bonusIDs end

  local itemPayload = string.match(itemLink, "item:([%-?%d:]+)")
  if not itemPayload then return bonusIDs end
  local itemPayloadSplit = {strsplit(":", itemPayload)}
  local numBonuses = tonumber(itemPayloadSplit[13]) or 0
  for bonusIndex = 14, 13 + numBonuses do
    local bonusID = tonumber(itemPayloadSplit[bonusIndex])
    if bonusID then
      table.insert(bonusIDs, bonusID)
    end
  end

  return bonusIDs
end

---@param itemLink string?
---@return table?
local function findMidnightEmbellishmentByBonusID(itemLink)
  for _, bonusID in ipairs(getEquipmentItemBonusIDs(itemLink)) do
    local embellishment = MIDNIGHT_EMBELLISHMENTS_BY_BONUS_ID[bonusID]
    if embellishment then
      return embellishment
    end
  end
  return nil
end

---@param result AE_EquipmentEmbellishmentInfo
---@param embellishment table
local function applyKnownEmbellishment(result, embellishment)
  result.hasEmbellishment = true
  result.name = embellishment.name
  result.itemID = embellishment.reagentItemID
  result.spellID = embellishment.spellID
  result.tooltipItemLink = "item:" .. tostring(embellishment.reagentItemID)

  local reagentName, reagentLink = C_Item.GetItemInfo(embellishment.reagentItemID)
  if reagentName then
    result.name = reagentName
  end
  if reagentLink then
    result.tooltipItemLink = reagentLink
  end

  result.icon = C_Item.GetItemIconByID(embellishment.reagentItemID)
  if not reagentName or not result.icon then
    C_Item.RequestLoadItemDataByID(embellishment.reagentItemID)
  end
end

---@param itemLink string?
---@return boolean
function Data:IsCraftedEquipmentItem(itemLink)
  if not itemLink then return false end

  if C_TradeSkillUI.GetItemCraftedQualityByItemInfo(itemLink) ~= nil then
    return true
  end

  -- Every normal crafted embellishment carries 8960, so this remains a useful
  -- fallback when crafted-quality data is not loaded yet. Lucky Keychain removes
  -- 8960; once item data is available the crafted-quality API still identifies
  -- that host item as crafted, allowing the Equipment table to show Missing.
  for _, bonusID in ipairs(getEquipmentItemBonusIDs(itemLink)) do
    if bonusID == EMBELLISHED_ITEM_BONUS_ID then
      return true
    end
  end

  return false
end

---@param lineText any
---@return boolean
local function isEmbellishedLimitLine(lineText)
  if type(lineText) ~= "string" or (issecretvalue and issecretvalue(lineText)) then return false end

  local uniqueEquippedText = _G.ITEM_UNIQUE_EQUIPPABLE or "Unique-Equipped"
  if not string.find(lineText, uniqueEquippedText, 1, true) then
    return false
  end

  -- Only the standard Embellished (2) category counts toward the character's
  -- two-item limit. Lucky Keychain removes this category; outdoor-only effects
  -- such as Outdoor Embellished (1) are also intentionally excluded.
  return string.find(lineText, "%(%s*2%s*%)") ~= nil
end

---@param itemLink string?
---@return number[]
local function getCraftingReagentItemIDs(itemLink)
  local reagentItemIDs = {}
  if not itemLink then return reagentItemIDs end

  local itemPayload = string.match(itemLink, "item:([%-?%d:]+)")
  if not itemPayload then return reagentItemIDs end
  local itemPayloadSplit = {strsplit(":", itemPayload)}
  local numBonuses = tonumber(itemPayloadSplit[13]) or 0
  local modifierCountIndex = 14 + numBonuses
  local numModifiers = tonumber(itemPayloadSplit[modifierCountIndex]) or 0
  local modifierIndex = modifierCountIndex + 1

  for _ = 1, numModifiers do
    local modifierType = tonumber(itemPayloadSplit[modifierIndex])
    local modifierValue = tonumber(itemPayloadSplit[modifierIndex + 1])
    if modifierType and modifierValue
      and modifierType >= CRAFTING_REAGENT_MODIFIER_FIRST
      and modifierType <= CRAFTING_REAGENT_MODIFIER_LAST
      and modifierValue > 0 then
      table.insert(reagentItemIDs, modifierValue)
    end
    modifierIndex = modifierIndex + 2
  end

  return reagentItemIDs
end

local embellishmentReagentCache = {}

---@param itemID number
---@return boolean? isEmbellishment nil while item data is still loading
local function isEmbellishmentReagentItem(itemID)
  if embellishmentReagentCache[itemID] == true then
    return true
  end

  local tooltipData = C_TooltipInfo.GetItemByID(itemID)
  local lines = tooltipData and tooltipData.lines
  if not lines or next(lines) == nil then
    C_Item.RequestLoadItemDataByID(itemID)
    return nil
  end

  for _, line in ipairs(lines) do
    if isEmbellishedLimitLine(line.leftText) then
      embellishmentReagentCache[itemID] = true
      return true
    end
  end

  -- Do not cache a negative result. Tooltip data can arrive in stages, and a
  -- partial reagent tooltip must not become a permanent false-negative.
  return false
end

---@param itemLink string?
---@return number? itemID
---@return boolean pendingItemData
local function findAppliedEmbellishmentReagent(itemLink)
  local pendingItemData = false
  for _, reagentItemID in ipairs(getCraftingReagentItemIDs(itemLink)) do
    local isEmbellishment = isEmbellishmentReagentItem(reagentItemID)
    if isEmbellishment == true then
      return reagentItemID, false
    elseif isEmbellishment == nil then
      pendingItemData = true
    end
  end
  return nil, pendingItemData
end

---@param line table
---@return boolean
local function isItemSpellEffectLine(line)
  local lineType = line.type
  if issecretvalue and issecretvalue(lineType) then return false end

  local lineTypes = Enum and Enum.TooltipDataLineType
  if lineTypes then
    local onUse = lineTypes.ItemSpellTriggerOnUse
    local onEquip = lineTypes.ItemSpellTriggerOnEquip
    local onProc = lineTypes.ItemSpellTriggerOnProc
    if (onUse and lineType == onUse)
      or (onEquip and lineType == onEquip)
      or (onProc and lineType == onProc) then
      return true
    end
  end

  local lineText = line.leftText
  if type(lineText) ~= "string" or (issecretvalue and issecretvalue(lineText)) then return false end
  local prefixes = {
    _G.ITEM_SPELL_TRIGGER_ONUSE,
    _G.ITEM_SPELL_TRIGGER_ONEQUIP,
    _G.ITEM_SPELL_TRIGGER_ONPROC,
  }
  for _, prefix in ipairs(prefixes) do
    if prefix and string.find(lineText, prefix, 1, true) == 1 then
      return true
    end
  end

  return false
end

---@param value any
---@return boolean
local function isUsableNumber(value)
  if type(value) ~= "number" then return false end
  return not issecretvalue or not issecretvalue(value)
end

---@param line table
---@return number?
local function getTooltipLineSpellID(line)
  if isUsableNumber(line.spellID) then
    return line.spellID
  end

  if type(line.leftText) == "string" and not (issecretvalue and issecretvalue(line.leftText)) then
    local spellID = tonumber(string.match(line.leftText, "|Hspell:(%d+)"))
    if spellID then return spellID end
  end

  return nil
end

---@class AE_EquipmentEmbellishmentInfo
---@field isCrafted boolean
---@field hasEmbellishment boolean
---@field name string?
---@field icon number|string?
---@field spellID number?
---@field tooltipLine string?
---@field itemID number?
---@field tooltipItemLink string?

---@param itemLink string?
---@param tooltipData table?
---@param storedItem table?
---@return AE_EquipmentEmbellishmentInfo
function Data:GetEquipmentEmbellishmentInfo(itemLink, tooltipData, storedItem)
  ---@type AE_EquipmentEmbellishmentInfo
  local result = {
    isCrafted = self:IsCraftedEquipmentItem(itemLink),
    hasEmbellishment = false,
  }

  -- Preserve the crafted flag captured while an alt was online. This matters in
  -- particular for Lucky Keychain recrafts, which intentionally no longer carry
  -- the shared 8960 Embellished marker.
  if storedItem and storedItem.itemLink == itemLink and storedItem.isCrafted == true then
    result.isCrafted = true
  end

  -- Primary detection path: the finished crafted item carries an effect-specific
  -- bonus ID. This works even when Blizzard has not populated the tooltip yet
  -- and, unlike the reagent-modifier heuristic, identifies the exact reagent.
  local knownEmbellishment = findMidnightEmbellishmentByBonusID(itemLink)
  if knownEmbellishment then
    result.isCrafted = true
    applyKnownEmbellishment(result, knownEmbellishment)
  end

  local lines = tooltipData and tooltipData.lines
  if not lines or next(lines) == nil then
    if not knownEmbellishment and storedItem then
      result.isCrafted = storedItem.isCrafted == true or result.isCrafted
      result.hasEmbellishment = storedItem.hasEmbellishment == true
      result.name = storedItem.embellishmentName
      result.icon = storedItem.embellishmentIcon
      result.spellID = storedItem.embellishmentSpellID
      result.tooltipLine = storedItem.embellishmentTooltipLine
      result.itemID = storedItem.embellishmentItemID
      result.tooltipItemLink = storedItem.embellishmentTooltipLink
    end
    return result
  end

  local effectLine
  local firstEffectLine
  local lastEffectLine
  local tooltipHasEmbellishedLimit = false
  for _, line in ipairs(lines) do
    if isItemSpellEffectLine(line) then
      firstEffectLine = firstEffectLine or line
      lastEffectLine = line

      -- Bonus IDs are authoritative, but matching the effect spell provides a
      -- second stable lookup path for links exported without the full bonus list.
      if not knownEmbellishment then
        local lineSpellID = getTooltipLineSpellID(line)
        local spellEmbellishment = lineSpellID and MIDNIGHT_EMBELLISHMENTS_BY_SPELL_ID[lineSpellID]
        if spellEmbellishment then
          knownEmbellishment = spellEmbellishment
          result.isCrafted = true
          applyKnownEmbellishment(result, knownEmbellishment)
        end
      end
    end
    if isEmbellishedLimitLine(line.leftText) then
      tooltipHasEmbellishedLimit = true
      result.hasEmbellishment = result.isCrafted
      -- The embellishment's effect line normally sits immediately before the
      -- Unique-Equipped category. Prefer that nearest preceding spell effect.
      effectLine = lastEffectLine or effectLine
    end
  end
  effectLine = effectLine or firstEffectLine

  if not result.hasEmbellishment then
    -- Saved data is authoritative for an offline character when Blizzard has
    -- returned only a partial hyperlink tooltip for the exact same item.
    if storedItem and storedItem.itemLink == itemLink and storedItem.hasEmbellishment == true then
      result.hasEmbellishment = true
      result.name = storedItem.embellishmentName
      result.icon = storedItem.embellishmentIcon
      result.spellID = storedItem.embellishmentSpellID
      result.tooltipLine = storedItem.embellishmentTooltipLine
      result.itemID = storedItem.embellishmentItemID
      result.tooltipItemLink = storedItem.embellishmentTooltipLink
    else
      return result
    end
  elseif not knownEmbellishment then
    -- Compatibility fallback for an embellishment not present in the Midnight
    -- bonus database. Older item-link modifier layouts can expose the reagent
    -- item directly; inherent embellishments fall back to the crafted item.
    local reagentItemID, reagentDataPending = findAppliedEmbellishmentReagent(itemLink)
    if reagentItemID then
      result.itemID = reagentItemID
      local reagentName, reagentLink = C_Item.GetItemInfo(reagentItemID)
      result.name = reagentName
      result.icon = C_Item.GetItemIconByID(reagentItemID)
      result.tooltipItemLink = reagentLink or ("item:" .. tostring(reagentItemID))
      if not reagentName or not result.icon then
        C_Item.RequestLoadItemDataByID(reagentItemID)
      end
    elseif not reagentDataPending and tooltipHasEmbellishedLimit then
      -- No optional reagent could be resolved, so this is most likely a crafted
      -- item with an inherent/built-in embellishment. In that case the item is
      -- itself the embellishment and its own icon/name are the correct display.
      local itemID = C_Item.GetItemIDForItemInfo(itemLink)
      local itemName, normalizedItemLink = C_Item.GetItemInfo(itemLink)
      result.itemID = itemID
      result.name = itemName
      result.icon = itemID and C_Item.GetItemIconByID(itemID) or nil
      result.tooltipItemLink = normalizedItemLink or itemLink
    end
  end

  if effectLine then
    if type(effectLine.leftText) == "string" and not (issecretvalue and issecretvalue(effectLine.leftText)) then
      result.tooltipLine = effectLine.leftText
    end
    result.spellID = result.spellID or getTooltipLineSpellID(effectLine)

    local effectIcon = effectLine.spellIcon or effectLine.icon
    if (type(effectIcon) == "number" or type(effectIcon) == "string")
      and not (issecretvalue and issecretvalue(effectIcon)) then
      result.icon = result.icon or effectIcon
    end

    if result.spellID and not result.name then
      local spellInfo = C_Spell.GetSpellInfo(result.spellID)
      if spellInfo then
        result.name = spellInfo.name
        result.icon = result.icon or spellInfo.iconID
      end
    end
  end

  result.name = result.name or "Embellished"
  return result
end

---Capture a secondary-stat snapshot while this character is online. Values
---can become secret in Midnight's restricted combat states; never persist,
---compare or format a secret value. Keep the last good snapshot for alts.
---@return boolean changed
function Data:UpdateSecondaryStats()
  local character = self:GetCharacter()
  if not character then return false end

  local ok, values = pcall(function()
    return {
      critRating = GetCombatRating(CR_CRIT_MELEE),
      critPercent = GetCritChance(),
      hasteRating = GetCombatRating(CR_HASTE_MELEE),
      hastePercent = GetHaste(),
      masteryRating = GetCombatRating(CR_MASTERY),
      masteryPercent = GetMasteryEffect(),
      versatilityRating = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE),
      versatilityRatingPercent = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE),
      versatilityExtraPercent = GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE),
    }
  end)
  if not ok or type(values) ~= "table" then return false end
  for _, key in ipairs({
    "critRating", "critPercent", "hasteRating", "hastePercent",
    "masteryRating", "masteryPercent", "versatilityRating",
    "versatilityRatingPercent", "versatilityExtraPercent",
  }) do
    local value = values[key]
    if (issecretvalue and issecretvalue(value)) or type(value) ~= "number" then
      return false
    end
  end

  local snapshot = {
    critRating = values.critRating,
    critPercent = math.floor(values.critPercent * 100 + 0.5) / 100,
    hasteRating = values.hasteRating,
    hastePercent = math.floor(values.hastePercent * 100 + 0.5) / 100,
    masteryRating = values.masteryRating,
    masteryPercent = math.floor(values.masteryPercent * 100 + 0.5) / 100,
    versatilityRating = values.versatilityRating,
    versatilityPercent = math.floor((values.versatilityRatingPercent + values.versatilityExtraPercent) * 100 + 0.5) / 100,
  }
  local previous = character.secondaryStats
  local changed = type(previous) ~= "table"
  for key, value in pairs(snapshot) do
    if not previous or previous[key] ~= value then
      changed = true
      break
    end
  end
  if not changed then return false end

  character.secondaryStats = snapshot
  self:MarkCharacterSyncChanged(character)
  return true
end

---Refresh equipment from the API
function Data:UpdateEquipment()
  local character = self:GetCharacter()
  if not character then return end
  -- The core update queue can request a scan independently of Equipment's
  -- inventory-event handler. Preserve the last snapshot during combat and
  -- let the module refresh it on PLAYER_REGEN_ENABLED.
  if InCombatLockdown and InCombatLockdown() then
    if addon.Module_Equipment then
      addon.Module_Equipment.equipmentRefreshAfterCombat = true
    end
    return false
  end

  local statsChanged = self:UpdateSecondaryStats()
  local previousEquipment = character.equipment
  local equipmentSnapshot = {}
  local missingItemData = false

  local upgradePattern = ITEM_UPGRADE_TOOLTIP_FORMAT_STRING
  upgradePattern = upgradePattern:gsub("%%d", "%%s")
  upgradePattern = upgradePattern:format("(.+)", "(%d+)", "(%d+)")

  TableForEach(LiqUI.Data:GetInventorySlots(), function(slot)
    local inventoryItemLink = GetInventoryItemLink("player", slot.id)
    if not inventoryItemLink then return end

    local itemUpgradeTrack, itemUpgradeLevel, itemUpgradeMax, itemUpgradeColor = "", 0, 0, ""
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
    itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType,
    expansionID, setID, isCraftingReagent = C_Item.GetItemInfo(inventoryItemLink)
    if itemName == nil then
      missingItemData = true
      return
    end

    local upgradeInfo = C_Item.GetItemUpgradeInfo(inventoryItemLink)
    if upgradeInfo and upgradeInfo.trackString and upgradeInfo.trackString ~= "" and upgradeInfo.currentLevel > 0 and upgradeInfo.maxLevel > 0 then
      itemUpgradeTrack = upgradeInfo.trackString
      itemUpgradeLevel = upgradeInfo.currentLevel
      itemUpgradeMax = upgradeInfo.maxLevel
    end

    -- The enchant ID is embedded directly in the item string (the field
    -- immediately after the item ID). Persist it with the equipment record so
    -- enchant presence can be checked for offline characters without waiting
    -- for Blizzard's tooltip cache.
    local itemPayload = string.match(itemLink or inventoryItemLink, "item:([%-?%d:]+)")
    local itemPayloadSplit = itemPayload and {strsplit(":", itemPayload)} or {}
    local enchantID = tonumber(itemPayloadSplit[2]) or 0
    local enchantTooltipLine = nil
    local ascendantVenomforged = false

    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot.id)
    if tooltipData and tooltipData.lines then
      TableForEach(tooltipData.lines, function(line)
        if line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent and line.leftText then
          -- Save the localized enchant line while this character is online.
          -- That lets the equipment window show the enchant immediately when
          -- viewing this character later from another alt.
          enchantTooltipLine = line.leftText
        end

        if not line.leftText then return end
        if type(line.leftText) == "string" and
          (not issecretvalue or not issecretvalue(line.leftText)) and
          (line.leftText:lower():find("ascendant venomforged", 1, true)
          or line.leftText:lower():find("ascendant voidforged", 1, true)) then
          ascendantVenomforged = true
        end
        local trackCapture, levelCapture, maxCapture = line.leftText:match(upgradePattern)
        if not trackCapture then return end
        if itemUpgradeTrack == "" then
          itemUpgradeTrack = trackCapture
          if levelCapture then
            itemUpgradeLevel = tonumber(levelCapture) or itemUpgradeLevel
          end
          if maxCapture then
            itemUpgradeMax = tonumber(maxCapture) or itemUpgradeMax
          end
        end
        if line.leftColor then
          itemUpgradeColor = line.leftColor:GenerateHexColor()
        end
      end)
    end

    if enchantID > 0 and not enchantTooltipLine then
      missingItemData = true
    end
    local embellishmentInfo = self:GetEquipmentEmbellishmentInfo(itemLink or inventoryItemLink, tooltipData)

    ---@type AE_Equipment
    local equipment = {
      itemName = itemName,
      itemLink = itemLink,
      itemQuality = itemQuality,
      itemLevel = itemLevel,
      itemMinLevel = itemMinLevel,
      itemType = itemType,
      itemSubType = itemSubType,
      itemStackCount = itemStackCount,
      itemEquipLoc = itemEquipLoc,
      itemTexture = itemTexture,
      sellPrice = sellPrice,
      classID = classID,
      subclassID = subclassID,
      bindType = bindType,
      expansionID = expansionID,
      setID = setID,
      isCraftingReagent = isCraftingReagent,
      itemUpgradeTrack = itemUpgradeTrack,
      itemUpgradeLevel = itemUpgradeLevel,
      itemUpgradeMax = itemUpgradeMax,
      itemUpgradeColor = itemUpgradeColor,
      ascendantVenomforged = ascendantVenomforged,
      enchantID = enchantID,
      enchantTooltipLine = enchantTooltipLine,
      isCrafted = embellishmentInfo.isCrafted,
      hasEmbellishment = embellishmentInfo.hasEmbellishment,
      embellishmentName = embellishmentInfo.name,
      embellishmentIcon = embellishmentInfo.icon,
      embellishmentSpellID = embellishmentInfo.spellID,
      embellishmentTooltipLine = embellishmentInfo.tooltipLine,
      embellishmentItemID = embellishmentInfo.itemID,
      embellishmentTooltipLink = embellishmentInfo.tooltipItemLink,
      itemSlotID = slot.id,
      itemSlotName = slot.token,
    }
    table.insert(equipmentSnapshot, equipment)
  end)
  if SavedSnapshotEqual(previousEquipment or {}, equipmentSnapshot) then
    character.equipment = previousEquipment or equipmentSnapshot
    return statsChanged, missingItemData
  end
  character.equipment = equipmentSnapshot
  self:MarkCharacterSyncChanged(character)
  return true, missingItemData
end

local function isKeystoneAnnounceBlocked()
  return InCombatLockdown()
    or C_ChatInfo.InChatMessagingLockdown()
    or C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Chat)
    or C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.WeeklyRewards)
end

---@param itemLink string?
---@param dungeon LiqUI_Dungeon?
---@param keystoneLevel number?
local function sendNewKeystoneAnnounce(itemLink, dungeon, keystoneLevel)
  if isKeystoneAnnounceBlocked() then
    Data.cache.pendingKeystoneAnnounce = true
    return
  end
  local announceText
  if itemLink and not issecretvalue(itemLink) and itemLink ~= "" then
    announceText = itemLink
  elseif dungeon and type(keystoneLevel) == "number" and keystoneLevel > 0 then
    local name = dungeon.abbr or dungeon.short or dungeon.name
    if type(name) == "string" and name ~= "" then
      announceText = name .. " +" .. tostring(keystoneLevel)
    end
  end
  if not announceText then
    Data.cache.pendingKeystoneAnnounce = true
    return
  end
  local message = Constants.prefix .. "New Keystone: " .. announceText
  if not (IsInGroup() and Data.db.global.announceKeystones.autoParty) then
    Data.cache.pendingKeystoneAnnounce = nil
    return
  end
  if pcall(C_ChatInfo.SendChatMessage, message, "PARTY") then
    Data.cache.pendingKeystoneAnnounce = nil
  else
    Data.cache.pendingKeystoneAnnounce = true
  end
end

---Send a queued new-keystone announce once chat is unrestricted
function Data:FlushPendingKeystoneAnnounce()
  if not self.cache.pendingKeystoneAnnounce then
    return
  end
  local character = self:GetCharacter()
  if not character then
    return
  end
  local keystone = character.mythicplus.keystone
  local dungeons = LiqUI.Data:GetDungeons()
  local dungeon = TableGet(dungeons, "challengeModeID", keystone.challengeModeID) or TableGet(dungeons, "mapId", keystone.mapId)
  sendNewKeystoneAnnounce(keystone.itemLink, dungeon, keystone.level)
end

---Refresh keystone item from bags
function Data:UpdateKeystoneItem()
  local character = self:GetCharacter()
  if not character then return end
  local dungeons = LiqUI.Data:GetDungeons()
  local seasonKeystoneItemID = self:GetKeystoneItemID()
  local characterKeystoneMapID = character.mythicplus.keystone.mapId
  local characterKeystoneLevel = character.mythicplus.keystone.level
  local previousKeystone = TableCopy(character.mythicplus.keystone)
  local function finish()
    if not SavedSnapshotEqual(previousKeystone, character.mythicplus.keystone) then
      self:MarkCharacterSyncChanged(character)
      addon.Core:Render()
    end
  end

  do -- Base keystone data
    local keyStoneMapID = C_MythicPlus.GetOwnedKeystoneMapID()
    local keyStoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
    local keyStoneChallengeModeID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if keyStoneMapID ~= nil then character.mythicplus.keystone.mapId = tonumber(keyStoneMapID) or 0 end
    if keyStoneLevel ~= nil then character.mythicplus.keystone.level = tonumber(keyStoneLevel) or 0 end
    if keyStoneChallengeModeID ~= nil then character.mythicplus.keystone.challengeModeID = tonumber(keyStoneChallengeModeID) or 0 end
  end

  local keystoneItemID = nil
  local keystoneItemLink = nil
  for bagID = 0, NUM_BAG_SLOTS do
    for slotID = 1, C_Container.GetContainerNumSlots(bagID) do
      local containerItemId = C_Container.GetContainerItemID(bagID, slotID)
      if containerItemId then
        local isSeasonKeystone = seasonKeystoneItemID and containerItemId == seasonKeystoneItemID
        if isSeasonKeystone or C_Item.IsItemKeystoneByID(containerItemId) then
          keystoneItemLink = C_Container.GetContainerItemLink(bagID, slotID)
          keystoneItemID = containerItemId
          break
        end
      end
    end
    if keystoneItemLink then
      break
    end
  end

  if not keystoneItemLink then return finish() end
  if not LinkUtil.IsLinkType(keystoneItemLink, "keystone") then return finish() end

  local _, linkOptions = LinkUtil.ExtractLink(keystoneItemLink)
  if not linkOptions then return finish() end

  local _, linkChallengeModeID, linkLevel = LinkUtil.SplitLinkOptions(linkOptions)
  if not linkChallengeModeID or not linkLevel then return finish() end
  local keystoneChallengeModeID = tonumber(linkChallengeModeID) or 0
  local keystoneLevel = tonumber(linkLevel) or 0

  local dungeon = TableGet(dungeons, "challengeModeID", keystoneChallengeModeID)
  if not dungeon then return finish() end
  local dungeonMapId = tonumber(dungeon.mapId) or 0

  local newKeystone = false
  if characterKeystoneMapID and characterKeystoneLevel then
    if characterKeystoneMapID ~= dungeonMapId or characterKeystoneLevel < keystoneLevel then
      newKeystone = true
    end
  elseif dungeonMapId and keystoneLevel then
    newKeystone = true
  end

  local keystoneColor = "ffffffff"
  local color = C_ChallengeMode.GetKeystoneLevelRarityColor(keystoneLevel)
  if color then
    keystoneColor = color:GenerateHexColor()
  end

  local storedItemLink = keystoneItemLink
  if issecretvalue(storedItemLink) then
    storedItemLink = ""
  end

  character.mythicplus.keystone = {
    challengeModeID = keystoneChallengeModeID,
    mapId = dungeonMapId,
    level = keystoneLevel,
    color = keystoneColor,
    itemId = keystoneItemID or seasonKeystoneItemID or 0,
    itemLink = storedItemLink,
  }

  if newKeystone then
    sendNewKeystoneAnnounce(keystoneItemLink, dungeon, keystoneLevel)
  end

  finish()
end

---Record that the player actually opened the native Great Vault for this
---weekly reward cycle. Merely receiving WEEKLY_REWARDS_UPDATE is not enough:
---Blizzard can expose progress/example links before the vault is opened.
function Data:MarkVaultOpened()
  local character = self:GetCharacter()
  if not character or not character.vault then return end
  local reset = self.db.global.weeklyReset or 0
  if character.vault.openedForReset ~= reset then
    character.vault.openedForReset = reset
    self:MarkCharacterSyncChanged(character)
  end
end

---Refresh `character.vault.lastSnapshot` using only concrete rewards that
---Blizzard returned after the native Great Vault was actually opened.
---Example reward links are intentionally excluded because they are previews,
---not the items in the character's real claimable vault.
---@param character AE_Character
function Data:ArchiveVaultSnapshot(character)
  if not character.vault or not character.vault.slots then return end

  local rewardCycle = character.vault.openedForReset
  if not rewardCycle or rewardCycle == 0 or rewardCycle ~= self.db.global.weeklyReset then
    return
  end

  local snapshot = character.vault.lastSnapshot
  if not snapshot or snapshot.confirmed ~= true or snapshot.rewardCycle ~= rewardCycle then
    snapshot = { slots = {}, claimed = {}, confirmed = true, rewardCycle = rewardCycle }
  end

  local hasAnyReward = false
  TableForEach(character.vault.slots, function(slot)
    if slot.rewardIsConcrete == true and slot.exampleRewardLink and slot.exampleRewardLink ~= "" then
      hasAnyReward = true
      snapshot.slots[tostring(slot.id)] = {
        type = slot.type,
        index = slot.index,
        level = slot.level, -- raw Blizzard value, not an ilvl -- same caveat as the live slot
        exampleRewardLink = slot.exampleRewardLink,
      }
    end
  end)
  if hasAnyReward then
    snapshot.capturedAt = time()
    character.vault.lastSnapshot = snapshot
  end
end

---Best-effort: mark a Great Vault slot as actually claimed, so the "Rewards"
---click knows it's gone. Hooked onto C_WeeklyRewards.ClaimReward below
---(AlterEgo.lua) -- if that isn't really the function the "Choose" button
---calls, the hook just never fires and nothing else breaks.
---@param activityId number
function Data:MarkVaultRewardClaimed(activityId)
  local character = self:GetCharacter()
  if not character or not character.vault.lastSnapshot then return end
  character.vault.lastSnapshot.claimed = character.vault.lastSnapshot.claimed or {}
  if character.vault.lastSnapshot.claimed[tostring(activityId)] ~= true then
    character.vault.lastSnapshot.claimed[tostring(activityId)] = true
    self:MarkCharacterSyncChanged(character)
  end
end

---True if this character has a remembered Great Vault snapshot with at
---least one slot -- used so "click Rewards to preview it" can still lead
---somewhere for a character whose LIVE `vault.slots` was already wiped by
---the weekly reset, as long as the last-known snapshot remembers something.
---@param character AE_Character
---@return boolean
function Data:HasVaultHistory(character)
  return character.vault ~= nil
    and character.vault.openedForReset ~= nil
    and character.vault.openedForReset ~= 0
    and character.vault.openedForReset == self.db.global.weeklyReset
    and character.vault.lastSnapshot ~= nil
    and character.vault.lastSnapshot.confirmed == true
    and character.vault.lastSnapshot.rewardCycle == character.vault.openedForReset
    and next(character.vault.lastSnapshot.slots or {}) ~= nil
end

---Choose which of an already-generated reward's items to show as "the
---item" for a vault slot -- mirrors Blizzard's own native Great Vault
---window (WeeklyRewardActivityItemMixin:SetDisplayedItem in
---Blizzard_WeeklyRewards.lua): among Item-type rewards (never currency,
---never a keystone), the highest quality and, on a tie, the highest ilvl --
---there's normally one equippable and one non-equippable reward, and this
---picks the equippable one. Asynchronous on purpose: C_Item.GetItemInfo can
---return nil the first time an item that isn't cached client-side yet is
---queried.
---@param rewards table[]
---@param callback fun(itemLink: string?)
local function resolveBestVaultItemReward(rewards, callback)
  local itemRewards = {}
  for _, r in ipairs(rewards or {}) do
    if r.type == Enum.CachedRewardType.Item and r.itemDBID and not C_Item.IsItemKeystoneByID(r.id) then
      table.insert(itemRewards, r)
    end
  end
  if #itemRewards == 0 then
    callback(nil)
    return
  end

  local container = ContinuableContainer:Create()
  for _, r in ipairs(itemRewards) do
    container:AddContinuable(Item:CreateFromItemID(r.id))
  end
  container:ContinueOnLoad(function()
    local best, bestQuality, bestLevel = nil, -1, -1
    for _, r in ipairs(itemRewards) do
      local _, _, quality, ilvl = C_Item.GetItemInfo(r.id)
      quality, ilvl = quality or 0, ilvl or 0
      if quality > bestQuality or (quality == bestQuality and ilvl > bestLevel) then
        best, bestQuality, bestLevel = r, quality, ilvl
      end
    end
    callback(best and C_WeeklyRewards.GetItemHyperlink(best.itemDBID) or nil)
  end)
end

---Best-effort M+/Great Vault "season week" number, purely for display.
---WoW doesn't expose a season week number through any public API, so this
---is calibrated once (see SetSeasonWeekAnchor) from a week number the
---player confirms, and every other week is computed from there by simply
---counting 7-day (604800s) increments away from that anchor's reset
---timestamp -- exactly how often self.db.global.weeklyReset advances.
---@return number? weekNumber nil if never calibrated
function Data:GetSeasonWeekNumber()
  local anchor = self.db.global.seasonWeekAnchor
  if not anchor or type(self.db.global.weeklyReset) ~= "number" then return nil end
  local weeksElapsed = Round((self.db.global.weeklyReset - anchor.weeklyReset) / 604800)
  return anchor.week + weeksElapsed
end

---(Re-)calibrate: "the week ending at the CURRENT self.db.global.weeklyReset
---is week `week`". Every other week's number (GetSeasonWeekNumber) is then
---just counted in 7-day steps from this one point -- call this again
---whenever the number drifts (a new season starting over at week 1, a
---server-side calendar hiccup, etc.) to re-anchor from that point on.
---@param week number
function Data:SetSeasonWeekAnchor(week)
  self.db.global.seasonWeekAnchor = {
    weeklyReset = self.db.global.weeklyReset,
    week = week,
  }
end

---Refresh Great Vault progress/info
function Data:UpdateVault()
  local character = self:GetCharacter()
  if not character then return end
  local vault = character.vault
  local previousEncounters = vault.activityEncounterInfo or {}
  local previousSlots = vault.slots or {}
  local previousWorldProgress = vault.worldActivityProgress or {}
  local previousAvailable = vault.hasAvailableRewards
  local previousSnapshot = vault.lastSnapshot
  vault.lastUpdatedAt = time()

  -- Do not wipe the old arrays before comparing the new API snapshot.
  vault.activityEncounterInfo = {}
  vault.slots = {}
  vault.worldActivityProgress = {}

  TableForEach(self.vaultTypes or {}, function(vaultType)
    for index = 1, 3 do
      local encounters = C_WeeklyRewards.GetActivityEncounterInfo(vaultType.id, index)
      if encounters then
        TableForEach(encounters, function(encounter)
          if not encounter then return end
          ---@type AE_WeeklyRewardActivityEncounterInfo
          local activityEncounter = TableCopy(encounter)
          activityEncounter.type = vaultType.id
          activityEncounter.index = index
          table.insert(character.vault.activityEncounterInfo, activityEncounter)
        end)
      end
    end
  end)

  local activities = C_WeeklyRewards.GetActivities()
  TableForEach(activities, function(activity)
    ---@type AE_CharacterVaultSlot
    local slot = TableCopy(activity)
    slot.exampleRewardLink = ""
    slot.exampleRewardUpgradeLink = ""
    if activity.progress >= activity.threshold then
      local itemLink, upgradeItemLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
      slot.exampleRewardLink = itemLink or ""
      slot.exampleRewardUpgradeLink = upgradeItemLink or ""
    end
    table.insert(character.vault.slots, slot)

    -- The "example" link above is only a representative sample and can
    -- come back empty even though the slot is genuinely unlocked in-game
    -- (a real bug report confirmed this: a slot the player could see and
    -- claim in the native window showed nothing in the addon).
    -- `activity.rewards` is only populated once Blizzard has ACTUALLY
    -- generated the concrete reward -- the same source the native Great
    -- Vault window itself reads from -- so once it's there, resolve and
    -- use the real reward instead, overwriting the example. pcall'd: this
    -- is new async code, and a failure here must never cost the rest of
    -- Update() (which already happened, above).
    if activity.rewards and #activity.rewards > 0 then
      local ok, err = pcall(resolveBestVaultItemReward, activity.rewards, function(itemLink)
        if not itemLink or (slot.exampleRewardLink == itemLink and slot.rewardIsConcrete) then return end
        -- A newer Vault refresh may have replaced this slot while item data
        -- was loading. Do not apply obsolete callbacks to the current state.
        local isCurrentSlot = false
        for _, currentSlot in ipairs(character.vault.slots or {}) do
          if currentSlot == slot then
            isCurrentSlot = true
            break
          end
        end
        if not isCurrentSlot then return end
        slot.exampleRewardLink = itemLink
        slot.rewardIsConcrete = true
        self:ArchiveVaultSnapshot(character)
        self:MarkCharacterSyncChanged(character)
        addon.Core:Render()
      end)
      if not ok then
        geterrorhandler()(("AlterEgo: resolveBestVaultItemReward failed: %s"):format(tostring(err)))
      end
    end
  end)

  local worldActivityProgress = C_WeeklyRewards.GetSortedProgressForActivity(Enum.WeeklyRewardChestThresholdType.World, true)
  if worldActivityProgress then
    TableForEach(worldActivityProgress, function(tierProgress)
      ---@type WeeklyRewardActivityTierProgress
      local row = {
        activityTierID = tierProgress.activityTierID,
        difficulty = tierProgress.difficulty,
        numPoints = tierProgress.numPoints,
      }
      table.insert(character.vault.worldActivityProgress, row)
    end)
  end

  character.vault.hasAvailableRewards = C_WeeklyRewards.HasAvailableRewards() == true
  if not character.vault.hasAvailableRewards then
    -- Genuinely nothing left to claim right now (either it was claimed, or
    -- there was truly nothing to begin with) -- the "Rewards" click on the
    -- main window already hides itself the moment this is false, so the
    -- remembered snapshot has no reader left; clear it instead of leaving
    -- stale data sitting around forever.
    character.vault.lastSnapshot = nil
  end
  local okEncounters, sameEncounters = pcall(SavedSnapshotEqual, previousEncounters, vault.activityEncounterInfo)
  local okSlots, sameSlots = pcall(SavedSnapshotEqual, previousSlots, vault.slots)
  local okWorld, sameWorld = pcall(SavedSnapshotEqual, previousWorldProgress, vault.worldActivityProgress)
  if not okEncounters or not sameEncounters or not okSlots or not sameSlots
    or not okWorld or not sameWorld or previousAvailable ~= vault.hasAvailableRewards
    or not SavedSnapshotEqual(previousSnapshot, vault.lastSnapshot) then
    self:MarkCharacterSyncChanged(character)
    addon.Core:Render()
  elseif addon.Module_VaultPreview and addon.Module_VaultPreview.character == character
    and addon.Module_VaultPreview.window and addon.Module_VaultPreview.window:IsVisible() then
    -- Keep the visible "Updated on" metadata current without redrawing every module.
    addon.Module_VaultPreview:Render()
  end
end

---Refresh Mythic+ data from the API
function Data:UpdateMythicPlus()
  local character = self:GetCharacter()
  if not character then return end

  local oldMythicplus = character.mythicplus
  local previous = {
    rating = oldMythicplus.rating,
    runHistory = oldMythicplus.runHistory,
    bestSeasonScore = oldMythicplus.bestSeasonScore,
    bestSeasonNumber = oldMythicplus.bestSeasonNumber,
    completed = oldMythicplus.numCompletedDungeonRuns,
    dungeons = oldMythicplus.dungeons,
    available = character.vault.hasAvailableRewards,
  }
  local dungeons = LiqUI.Data:GetDungeons()
  local ratingSummary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
  local runHistory = C_MythicPlus.GetRunHistory(true, true)
  local bestSeasonScore, bestSeasonNumber = C_MythicPlus.GetSeasonBestMythicRatingFromThisExpansion()
  local numHeroic, numMythic, numMythicPlus = C_WeeklyRewards.GetNumCompletedDungeonRuns()
  local affixes = self:GetAffixes()

  if ratingSummary ~= nil and ratingSummary.currentSeasonScore ~= nil then character.mythicplus.rating = ratingSummary.currentSeasonScore end
  if runHistory ~= nil then character.mythicplus.runHistory = runHistory end
  if bestSeasonScore ~= nil then character.mythicplus.bestSeasonScore = bestSeasonScore end
  if bestSeasonNumber ~= nil then character.mythicplus.bestSeasonNumber = bestSeasonNumber end

  character.vault.hasAvailableRewards = C_WeeklyRewards.HasAvailableRewards() == true

  character.mythicplus.numCompletedDungeonRuns = {
    heroic = numHeroic or 0,
    mythic = numMythic or 0,
    mythicPlus = numMythicPlus or 0,
  }

  character.mythicplus.dungeons = {}
  for _, dataDungeon in pairs(dungeons) do
    local bestTimedRun, bestNotTimedRun = C_MythicPlus.GetSeasonBestForMap(dataDungeon.challengeModeID)
    local affixScores, bestOverAllScore = C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(dataDungeon.challengeModeID)

    ---@type AE_CharacterAffixScoreInfo[]|nil
    local characterAffixScores = nil
    if affixScores then
      characterAffixScores = {}
      TableForEach(affixScores, function(affixScore)
        local affix = TableGet(affixes, "name", affixScore.name)
        ---@type AE_CharacterAffixScoreInfo
        local characterAffixScore = TableCopy(affixScore)
        characterAffixScore.id = affix and affix.id or 0
        table.insert(characterAffixScores, characterAffixScore)
      end)
    end

    ---@type AE_CharacterDungeon
    local dungeon = {
      challengeModeID = dataDungeon.challengeModeID,
      rating = 0,
      level = 0,
      finishedSuccess = false,
      bestTimedRun = bestTimedRun,
      bestNotTimedRun = bestNotTimedRun,
      affixScores = characterAffixScores,
      bestOverAllScore = bestOverAllScore,
    }

    if ratingSummary then
      local run = TableFind(ratingSummary.runs or {}, function(ratingRun)
        return ratingRun.challengeModeID == dataDungeon.challengeModeID
      end)
      if run then
        dungeon.rating = run.mapScore
        dungeon.level = run.bestRunLevel
        dungeon.finishedSuccess = run.finishedSuccess
      end
    end
    table.insert(character.mythicplus.dungeons, dungeon)
  end
  local updated = character.mythicplus
  local ok, same = pcall(SavedSnapshotEqual, previous, {
    rating = updated.rating,
    runHistory = updated.runHistory,
    bestSeasonScore = updated.bestSeasonScore,
    bestSeasonNumber = updated.bestSeasonNumber,
    completed = updated.numCompletedDungeonRuns,
    dungeons = updated.dungeons,
    available = character.vault.hasAvailableRewards,
  })
  if not ok or not same then
    self:MarkCharacterSyncChanged(character)
    addon.Core:Render()
  end
end
