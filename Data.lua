---@class AE_Addon
local addon = select(2, ...)

---@class AE_Data
local Data = {}
addon.Data = Data

local Constants = addon.Constants
local LibAceDB = addon.Libs.AceDB
local TableCopy = addon.Libs.LiqUI.Utils.TableCopy
local TableCount = addon.Libs.LiqUI.Utils.TableCount
local TableFilter = addon.Libs.LiqUI.Utils.TableFilter
local TableFind = addon.Libs.LiqUI.Utils.TableFind
local TableForEach = addon.Libs.LiqUI.Utils.TableForEach
local TableGet = addon.Libs.LiqUI.Utils.TableGet

Data.dbVersion = 39

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
    showZeroRatedCharacters = true,
    showEquippedItemLevel = false,
    showItemLevelDecimals = false,
    showRealms = true,
    showGuildInformation = false,
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
      showIcons = true,
      showMaxEarned = true,
      alignCenter = true,
    },
    seasonalChores = {
      enabled = true,
      hiddenCurrencies = {},
      showIcons = true,
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
        Main = {},
        Affixes = {},
        Equipment = {},
        VaultPreview = {},
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
      passphrase = "",
      passphraseAccounts = {}, ---@type table<string, string> Which WoW Account each passphrase's synced characters land in
      lastSentUpdate = {}, ---@type table<string, number> Per-character GUID -> the character.lastUpdate value we last actually broadcast, so unchanged characters aren't resent
    },
  },
}

---@type AE_Character
Data.defaultCharacter = {
  GUID = "",
  lastUpdate = 0,
  currentSeason = 0,
  enabled = true,
  order = 0,
  accountId = nil, ---@type string? Which WoW Account bucket (Data.db.global.accounts) this character belongs to
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
  money = 0,
  currencies = {},
  prey = {
    questsCompleted = {},
  },
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
  },
}

---@type AE_Cache
Data.cache = {
  seasonID = nil,
  seasonDisplayID = nil,
  ---@type MythicPlusKeystoneAffix[]
  currentAffixes = {},
  classes = {},
  specs = {},
}

---Initiate AceDB
function Data:Initialize()
  self.db = LibAceDB:New(
    "AlterEgoDB",
    self.defaultDB,
    true
  )
end

---Get the current Season IDs
---@return number, number
function Data:GetCurrentSeason()
  if self.cache.seasonID and self.cache.seasonID > 0 and self.cache.seasonDisplayID and self.cache.seasonDisplayID > 0 then
    return self.cache.seasonID, self.cache.seasonDisplayID
  end

  local seasonID = C_MythicPlus.GetCurrentSeason() or -1
  local seasonDisplayID = C_MythicPlus.GetCurrentUIDisplaySeason() or -1
  if seasonID <= 0 or seasonDisplayID <= 0 then
    return -1, -1
  end

  local season = TableGet(self.seasons, "seasonID", seasonID)
  local currentExpansionLevel = GetExpansionLevel()
  if season and currentExpansionLevel and season.expansionID < currentExpansionLevel then
    local nextSeason = TableGet(self.seasons, "expansionID", currentExpansionLevel)
    if nextSeason then
      seasonID = nextSeason.seasonID
      seasonDisplayID = nextSeason.seasonDisplayID
    end
  end

  self.cache.seasonID = seasonID
  self.cache.seasonDisplayID = seasonDisplayID
  return seasonID, seasonDisplayID
end

---Get the currencies of the current season enriched with C_CurrencyInfo data
---@return AE_CurrencyInfo[]
function Data:GetCurrencies()
  local currencies = {}
  local seasonID = self:GetCurrentSeason()
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
    if currency.currencyType == "delveMap" then
      ---@type AE_CurrencyInfo
      local currencyInfo = {
        id = currency.id,
        name = currency.name or "Trovehunter's Bounty",
        description = "Weekly Trovehunter's Bounty map status from delves.",
        iconFileID = C_Item.GetItemIconByID(currency.id) or 0,
        quality = Enum.ItemQuality.Rare,
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
    local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currency.id)
    if currencyInfo then
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

  self.db.global.characters[playerGUID].GUID = playerGUID

  return self.db.global.characters[playerGUID]
end

---Remove a character from the addon. No undo; log in on that character again to reintroduce.
---@param characterOrGUID AE_Character|string
function Data:DeleteCharacter(characterOrGUID)
  local GUID = type(characterOrGUID) == "table" and characterOrGUID.GUID or characterOrGUID
  if not GUID or self.db.global.characters[GUID] == nil then return end
  self.db.global.characters[GUID] = nil
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
---@param name string? Defaults to the next free number ("1", "2", ...)
---@return string accountId
function Data:CreateAccount(name)
  -- Find the smallest free numbered slot instead of an ever-growing
  -- counter -- so deleting e.g. "10" and creating a new one reuses 10
  -- instead of jumping to 11+. Checked against the actual accounts table
  -- (not a stored counter), so this is correct even after deletions leave
  -- gaps.
  local number = 1
  while self.db.global.accounts["account_" .. number] do
    number = number + 1
  end
  local id = "account_" .. number

  local maxOrder = 0
  for _, account in pairs(self.db.global.accounts) do
    if (account.order or 0) > maxOrder then
      maxOrder = account.order
    end
  end

  self.db.global.accounts[id] = {
    name = name or tostring(number),
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

---Delete a WoW Account. Characters inside it are moved to whichever account
---is left with the lowest order. Refuses to delete the only remaining account.
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

  local fallbackId = self:EnsureDefaultAccount()
  for _, character in pairs(self.db.global.characters) do
    if character.accountId == accountId then
      character.accountId = fallbackId
    end
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

---Get (or create, first time) the WoW Account that a given sync passphrase's
---characters should land in. Calling this again with the SAME passphrase
---always returns the SAME account -- it only creates a new one the first
---time that passphrase is ever seen, so repeat syncs don't pile up
---duplicate accounts.
---@param passphrase string
---@return string accountId
function Data:GetOrCreateAccountForPassphrase(passphrase)
  if not passphrase or passphrase == "" then
    return self:EnsureDefaultAccount()
  end

  self.db.global.sync.passphraseAccounts = self.db.global.sync.passphraseAccounts or {}
  local accountId = self.db.global.sync.passphraseAccounts[passphrase]
  if accountId and self.db.global.accounts[accountId] then
    return accountId
  end

  local newAccountId = self:CreateAccount()
  self.db.global.sync.passphraseAccounts[passphrase] = newAccountId
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
  local characters = self:GetCharacters() -- same visibility rules as the main window
  local mainAccountId = self:GetMainAccountId()
  if not mainAccountId then
    return characters
  end

  local result = {}
  for _, character in ipairs(characters) do
    if character.accountId == mainAccountId then
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
  local seasonID = self:GetCurrentSeason()
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

---Get all of the raids in the current season
---@param unfiltered boolean?
---@return AE_RaidDifficulty[]
function Data:GetRaidDifficulties(unfiltered)
  local result = {}
  for _, difficulty in pairs(self.raidDifficulties) do
    table.insert(result, difficulty)
  end

  table.sort(result, function(a, b)
    return a.order < b.order
  end)

  if unfiltered then
    return result
  end

  local filtered = {}
  for _, difficulty in ipairs(result) do
    if self.db.global.raids.hiddenDifficulties and not self.db.global.raids.hiddenDifficulties[difficulty.id] then
      table.insert(filtered, difficulty)
    end
  end

  return filtered
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
  local seasonID = self:GetCurrentSeason()
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
  local seasonID = self:GetCurrentSeason()
  local keystone = TableGet(self.keystones, "seasonID", seasonID)

  if keystone ~= nil then
    return keystone.itemID
  end

  return nil
end

---Get dungeons for the current season
---@return AE_Dungeon[]
function Data:GetDungeons()
  local seasonID = self:GetCurrentSeason()
  local dungeons = TableFilter(self.dungeons, function(dataDungeon)
    return dataDungeon.seasonID == seasonID
  end)

  table.sort(dungeons, function(a, b)
    return strcmputf8i(a.name, b.name) < 0
  end)

  return dungeons
end

---Get all of the raids in the current season
---@param unfiltered boolean?
---@return AE_Raid[]
function Data:GetRaids(unfiltered)
  local seasonID = self:GetCurrentSeason()
  local raids = TableFilter(self.raids, function(dataRaid)
    return dataRaid.seasonID == seasonID
  end)

  table.sort(raids, function(a, b)
    return a.order < b.order
  end)

  return raids
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

---Get user characters
---@param unfiltered boolean?
---@return AE_Character[]
function Data:GetCharacters(unfiltered)
  local characters = {}
  for _, character in pairs(self.db.global.characters) do
    -- The max-level gate is a display FILTER (like enabled/account-enabled/
    -- zero-rated below), not an existence check -- it must respect
    -- `unfiltered` too. Applying it unconditionally here made every caller
    -- that asks for the unfiltered list (e.g. the Characters menu's account
    -- list, used to view/move/re-enable/delete characters) silently drop
    -- every character below max level, with no way to ever see or manage
    -- them again -- looking exactly like their data had vanished.
    if unfiltered or (character.info.level ~= nil and character.info.level >= 80) then -- Todo later: GetMaxLevelForPlayerExpansion()
      table.insert(characters, character)
    end
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
    if self.db.global.showZeroRatedCharacters == false and (character.mythicplus.rating and character.mythicplus.rating <= 0) then
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
    self.db.global.dbVersion = self.db.global.dbVersion + 1
    self:MigrateDB()
  end
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
      -- Last chance to remember what was in the vault THIS character never
      -- claimed -- character.vault.slots is about to be wiped below for
      -- good (that's what the whole history feature protects against).
      self:ArchiveVaultSnapshot(character)
      -- Mark previous m+ runs as not this week
      TableForEach(character.mythicplus.runHistory, function(run)
        run.thisWeek = false
      end)
      -- Reset Prey Hunts
      character.prey.questsCompleted = wipe(character.prey.questsCompleted or {})
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
    end)
  end
  self.db.global.weeklyReset = time() + C_DateAndTime.GetSecondsUntilWeeklyReset()
end

---Perform season reset tasks
function Data:TaskSeasonReset()
  local seasonID = self:GetCurrentSeason()
  if seasonID then
    TableForEach(self.db.global.characters, function(character)
      if character.currentSeason == nil or character.currentSeason < seasonID then
        wipe(character.mythicplus.runHistory or {})
        wipe(character.mythicplus.dungeons or {})
        wipe(character.currencies or {})
        character.mythicplus.rating = 0
        character.currentSeason = seasonID
        character.currentSeasonID = seasonID
      end
    end)
  end
end

---Load static game data (dungeons, raids, affix rotations)
function Data:loadGameData()
  local seasonID = self:GetCurrentSeason()

  for _, raid in pairs(self.raids) do
    -- if raid.seasonID == seasonID then
    --   EJ_ClearSearch()
    --   EJ_ResetLootFilter()
    --   EJ_SelectInstance(raid.journalInstanceID)

    --   for classID = 1, GetNumClasses() do
    --     for specIndex = 1, GetNumSpecializationsForClassID(classID) do
    --       local specID = GetSpecializationInfoForClassID(classID, specIndex)
    --       if specID then
    --         EJ_SetLootFilter(classID, specID)
    --         for i = 1, EJ_GetNumLoot() do
    --           local lootInfo = C_EncounterJournal.GetLootInfoByIndex(i)
    --           if lootInfo.name ~= nil and lootInfo.slot ~= nil and lootInfo.slot ~= "" then
    --             local item = raid.loot[lootInfo.itemID]
    --             if not item then
    --               item = lootInfo
    --               item.stats = C_Item.GetItemStats(lootInfo.link)
    --               item.classes = {}
    --               item.specs = {}
    --               raid.loot[lootInfo.itemID] = item
    --             end
    --             item.classes[classID] = true
    --             item.specs[specID] = true
    --             -- table.insert(item.classes, classID)
    --             -- table.insert(item.specs, specID)
    --             -- TODO: Make above arrays unique
    --           end
    --         end
    --       end
    --     end
    --   end
    --   EJ_ResetLootFilter()
    -- end

    if raid.seasonID == seasonID then
      local encounterIndex = 1
      EJ_SelectInstance(raid.journalInstanceID)
      local _, _, bossID = EJ_GetEncounterInfoByIndex(encounterIndex, raid.journalInstanceID)
      while bossID do
        local name, description, journalEncounterID, journalEncounterSectionID, journalLink, journalInstanceID, instanceEncounterID, instanceID = EJ_GetEncounterInfoByIndex(encounterIndex, raid.journalInstanceID)
        ---@type AE_Encounter
        local encounter = {
          index = encounterIndex,
          name = name,
          description = description,
          journalInstanceID = journalInstanceID,
          journalEncounterID = journalEncounterID,
          journalEncounterSectionID = journalEncounterSectionID,
          journalLink = journalLink,
          instanceID = instanceID,
          instanceEncounterID = instanceEncounterID,
        }
        raid.encounters[encounterIndex] = encounter
        encounterIndex = encounterIndex + 1
        _, _, bossID = EJ_GetEncounterInfoByIndex(encounterIndex, raid.journalInstanceID)
      end
      -- Encounter Journal data is not always populated yet for brand-new raids (e.g. right at season
      -- launch/PTR). Fall back to generic placeholder bosses so the raid still occupies its correct
      -- number of slots (and honors raid.order) in the grid until Blizzard populates the journal.
      if #raid.encounters == 0 and raid.numEncounters and raid.numEncounters > 0 then
        for placeholderIndex = 1, raid.numEncounters do
          raid.encounters[placeholderIndex] = {
            index = placeholderIndex,
            name = format("%s (%d)", raid.name, placeholderIndex),
            instanceID = raid.instanceID,
          }
        end
      end
      raid.modifiedInstanceInfo = C_ModifiedInstance.GetModifiedInstanceInfoFromMapID(raid.instanceID)
    end
  end

  for _, dungeon in pairs(self.dungeons) do
    -- if dungeon.seasonID == seasonID then
    --   EJ_ClearSearch()
    --   EJ_ResetLootFilter()
    --   EJ_SelectInstance(dungeon.journalInstanceID)

    --   local count = 0
    --   for classID = 1, GetNumClasses() do
    --     for specIndex = 1, GetNumSpecializationsForClassID(classID) do
    --       local specID = GetSpecializationInfoForClassID(classID, specIndex)
    --       if specID then
    --         EJ_SetLootFilter(classID, specID)
    --         for i = 1, EJ_GetNumLoot() do
    --           local lootInfo = C_EncounterJournal.GetLootInfoByIndex(i)
    --           if lootInfo.name ~= nil and lootInfo.slot ~= nil and lootInfo.slot ~= "" then
    --             local item = dungeon.loot[lootInfo.itemID]
    --             if not item then
    --               item = lootInfo
    --               item.stats = C_Item.GetItemStats(lootInfo.link)
    --               item.classes = {}
    --               item.specs = {}
    --               dungeon.loot[lootInfo.itemID] = item
    --               count = count + 1
    --             end
    --             item.classes[classID] = true
    --             item.specs[specID] = true
    --             -- table.insert(item.classes, classID)
    --             -- table.insert(item.specs, specID)
    --             -- TODO: Make above arrays unique
    --           end
    --         end
    --       end
    --     end
    --   end
    --   EJ_ResetLootFilter()
    -- end

    if dungeon.seasonID == seasonID then
      -- TODO: Get and store more dungeon data for m+
      local dungeonName, _, dungeonTimeLimit, dungeonTexture = C_ChallengeMode.GetMapUIInfo(dungeon.challengeModeID)
      dungeon.name = dungeonName
      dungeon.time = dungeonTimeLimit
      dungeon.texture = dungeon.texture ~= 0 and dungeonTexture or "Interface/Icons/achievement_bg_wineos_underxminutes"

      local encounterIndex = 1
      EJ_SelectInstance(dungeon.journalInstanceID)
      local _, _, bossID = EJ_GetEncounterInfoByIndex(encounterIndex, dungeon.journalInstanceID)
      while bossID do
        local name, description, journalEncounterID, journalEncounterSectionID, journalLink, journalInstanceID, instanceEncounterID, instanceID = EJ_GetEncounterInfoByIndex(encounterIndex, dungeon.journalInstanceID)
        ---@type AE_Encounter
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
    end
  end

  for _, affix in pairs(self.affixes) do
    local name, description, fileDataID = C_ChallengeMode.GetAffixInfo(affix.id)
    affix.name = name
    affix.description = description
    affix.fileDataID = fileDataID
  end
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
      if raid then
        TableForEach(raid.encounters, function(encounter)
          if string.lower(encounter.name) == string.lower(bossName) then
            instanceEncounterID = encounter.instanceEncounterID
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
  addon.Core:RequestSyncBroadcast()
end

function Data:UpdatePreyProgress()
  local character = self:GetCharacter()
  if not character then return end
  character.prey = character.prey or {}
  character.prey.questsCompleted = wipe(character.prey.questsCompleted or {})
  TableForEach(self.preyQuests, function(quest)
    character.prey.questsCompleted[quest.questID] = C_QuestLog.IsQuestFlaggedCompleted(quest.questID)
  end)
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
---@return number delta Always >= 0
function Data:CalculateBagItemLevelUpgrade()
  local slotEquipLocs = {
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
  local twoHandEquipLocs = { INVTYPE_2HWEAPON = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }

  local equippedMainHandLink = GetInventoryItemLink("player", INVSLOT_MAINHAND)
  local mainHandIsTwoHanded = false
  if equippedMainHandLink then
    local _, _, _, mainHandEquipLoc = C_Item.GetItemInfoInstant(equippedMainHandLink)
    mainHandIsTwoHanded = mainHandEquipLoc ~= nil and twoHandEquipLocs[mainHandEquipLoc] == true
  end

  -- Index bag items by equip location for quick lookup.
  local bagItemsByEquipLoc = {}
  for bag = 0, NUM_BAG_SLOTS do
    local numSlots = C_Container.GetContainerNumSlots(bag) or 0
    for containerSlot = 1, numSlots do
      local itemLink = C_Container.GetContainerItemLink(bag, containerSlot)
      if itemLink then
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemLink)
        if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
          bagItemsByEquipLoc[equipLoc] = bagItemsByEquipLoc[equipLoc] or {}
          table.insert(bagItemsByEquipLoc[equipLoc], itemLink)
        end
      end
    end
  end

  local deltaTotal, count = 0, 0
  for slotID, equipLocs in pairs(slotEquipLocs) do
    if not (slotID == INVSLOT_OFFHAND and mainHandIsTwoHanded) then
      local equippedLink = GetInventoryItemLink("player", slotID)
      local equippedLevel = equippedLink and C_Item.GetDetailedItemLevelInfo(equippedLink)
      if equippedLevel and equippedLevel > 0 then
        local bestLevel = equippedLevel

        for _, equipLoc in ipairs(equipLocs) do
          for _, itemLink in ipairs(bagItemsByEquipLoc[equipLoc] or {}) do
            local itemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
            if itemLevel and itemLevel > bestLevel then
              bestLevel = itemLevel
            end
          end
        end

        deltaTotal = deltaTotal + (bestLevel - equippedLevel)
        count = count + 1
      end
    end
  end

  if count == 0 then return 0 end
  return deltaTotal / count
end

---Refresh general character info from the API
function Data:UpdateCharacterInfo()
  local character = self:GetCharacter()
  if not character then return end

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
  addon.Core:Render()
  addon.Core:RequestSyncBroadcast()
end

---Refresh character money from the API
function Data:UpdateMoney()
  local character = self:GetCharacter()
  if not character then return end

  local money = GetMoney()
  if not money then return end

  character.money = money
end

---Refresh currencies from the API
function Data:UpdateCurrencies()
  local character = self:GetCharacter()
  if not character then return end
  local seasonID = self:GetCurrentSeason()

  -- Gilded Stash progress is only readable from the API while near Silvermoon City (or otherwise
  -- triggering the spell visual). Grab whatever we already had stored before wiping the table, so
  -- it can be carried forward when the live widget has nothing to report this time.
  local previousGildedStash = TableGet(character.currencies or {}, "id", "gildedStash")

  character.currencies = wipe(character.currencies or {})

  TableForEach(self.currencies or {}, function(dataCurrency)
    if dataCurrency.seasonID ~= nil and dataCurrency.seasonID ~= seasonID then
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
    if dataCurrency.currencyType == "delveMap" then
      local bagCount = C_Item.GetItemCount(dataCurrency.id, true) or 0
      local hasBuff = false
      if dataCurrency.spellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(dataCurrency.spellID)
        if aura ~= nil and not issecretvalue(aura) then
          hasBuff = true
        end
      end

      ---@type AE_CharacterCurrency
      local delveMapCurrency = {
        id = dataCurrency.id,
        currencyType = dataCurrency.currencyType,
        name = dataCurrency.name or "Trovehunter's Bounty",
        iconFileID = C_Item.GetItemIconByID(dataCurrency.id) or 0,
        quantity = bagCount,
        bagCount = bagCount,
        hasBuff = hasBuff,
        questCompleted = dataCurrency.questID ~= nil and C_QuestLog.IsQuestFlaggedCompleted(dataCurrency.questID) == true,
      }
      table.insert(character.currencies, delveMapCurrency)
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

    local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(dataCurrency.id)
    if not currencyInfo then return end
    ---@type AE_CharacterCurrency
    local currency = currencyInfo
    currency.id = dataCurrency.id
    currency.currencyType = dataCurrency.currencyType
    if dataCurrency.itemID then
      currency.quantity = C_Item.GetItemCount(dataCurrency.itemID, true)
      currency.iconFileID = C_Item.GetItemIconByID(dataCurrency.itemID) or 0
    end
    table.insert(character.currencies, currency)
  end)
end

---Refresh equipment from the API
function Data:UpdateEquipment()
  local character = self:GetCharacter()
  if not character then return end

  character.equipment = wipe(character.equipment or {})

  local upgradePattern = ITEM_UPGRADE_TOOLTIP_FORMAT_STRING
  upgradePattern = upgradePattern:gsub("%%d", "%%s")
  upgradePattern = upgradePattern:format("(.+)", "(%d+)", "(%d+)")

  TableForEach(self.inventory or {}, function(slot)
    local inventoryItemLink = GetInventoryItemLink("player", slot.id)
    if not inventoryItemLink then return end

    local itemUpgradeTrack, itemUpgradeLevel, itemUpgradeMax, itemUpgradeColor = "", 0, 0, ""
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
    itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType,
    expansionID, setID, isCraftingReagent = C_Item.GetItemInfo(inventoryItemLink)
    if itemName == nil then return end

    local upgradeInfo = C_Item.GetItemUpgradeInfo(inventoryItemLink)
    if upgradeInfo and upgradeInfo.trackString and upgradeInfo.trackString ~= "" and upgradeInfo.currentLevel > 0 and upgradeInfo.maxLevel > 0 then
      itemUpgradeTrack = upgradeInfo.trackString
      itemUpgradeLevel = upgradeInfo.currentLevel
      itemUpgradeMax = upgradeInfo.maxLevel
    end

    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot.id)
    if tooltipData and tooltipData.lines then
      TableForEach(tooltipData.lines, function(line)
        if not line.leftText then return end
        local match, _, uTrack, uLevel, uMax = line.leftText:find(upgradePattern)
        if not match then return end
        if itemUpgradeTrack == "" then
          if uTrack then
            itemUpgradeTrack = uTrack
          end
          if uLevel then
            itemUpgradeLevel = tonumber(uLevel) or itemUpgradeLevel
          end
          if uMax then
            itemUpgradeMax = tonumber(uMax) or itemUpgradeMax
          end
        end
        if line.leftColor then
          itemUpgradeColor = line.leftColor:GenerateHexColor()
        end
      end)
    end

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
      itemSlotID = slot.id,
      itemSlotName = slot.name,
    }
    table.insert(character.equipment, equipment)
  end)
end

local function isKeystoneAnnounceBlocked()
  return InCombatLockdown()
    or C_ChatInfo.InChatMessagingLockdown()
    or C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Chat)
    or C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.WeeklyRewards)
end

---@param itemLink string?
---@param dungeon AE_Dungeon?
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
  if pcall(SendChatMessage, message, "PARTY") then
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
  local dungeons = self:GetDungeons()
  local dungeon = TableGet(dungeons, "challengeModeID", keystone.challengeModeID) or TableGet(dungeons, "mapId", keystone.mapId)
  sendNewKeystoneAnnounce(keystone.itemLink, dungeon, keystone.level)
end

---Refresh keystone item from bags
function Data:UpdateKeystoneItem()
  local character = self:GetCharacter()
  if not character then return end
  local dungeons = self:GetDungeons()
  local seasonKeystoneItemID = self:GetKeystoneItemID()
  local characterKeystoneMapID = character.mythicplus.keystone.mapId
  local characterKeystoneLevel = character.mythicplus.keystone.level

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

  if not keystoneItemLink then return addon.Core:Render() end
  if not LinkUtil.IsLinkType(keystoneItemLink, "keystone") then return addon.Core:Render() end

  local _, linkOptions = LinkUtil.ExtractLink(keystoneItemLink)
  if not linkOptions then return addon.Core:Render() end

  local _, linkChallengeModeID, linkLevel = LinkUtil.SplitLinkOptions(linkOptions)
  if not linkChallengeModeID or not linkLevel then return addon.Core:Render() end
  local keystoneChallengeModeID = tonumber(linkChallengeModeID) or 0
  local keystoneLevel = tonumber(linkLevel) or 0

  local dungeon = TableGet(dungeons, "challengeModeID", keystoneChallengeModeID)
  if not dungeon then return addon.Core:Render() end
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

  addon.Core:Render()
  addon.Core:RequestSyncBroadcast()
end

---Refresh `character.vault.lastSnapshot` from whatever's CURRENTLY unlocked
---in `character.vault.slots`. Unlike `vault.slots` itself (wiped every
---weekly reset by TaskWeeklyReset), this survives the reset -- so a reward
---the player never opened the in-game Great Vault to claim can still be
---shown by the "Rewards" click on the main window after it's already reset
---for real. Called every time the real Great Vault is actually opened/
---refreshed (Data:UpdateVault), so it always reflects the MOST RECENTLY
---seen state -- exactly like re-opening the in-game window would.
---Additive on purpose: only OVERWRITES a slot when this pass actually
---found something unlocked for it; if the current week hasn't unlocked
---anything yet, whatever was captured last time is simply left alone
---instead of being blanked out.
---@param character AE_Character
function Data:ArchiveVaultSnapshot(character)
  if not character.vault or not character.vault.slots then return end
  local snapshot = character.vault.lastSnapshot
  local hasAnyUnlocked = false
  TableForEach(character.vault.slots, function(slot)
    -- Gated on exampleRewardLink existing, NOT on progress >= threshold --
    -- that pair can stay stale even once a reward genuinely exists (see
    -- VaultPreview.lua::buildSlotCell for the real bug report this came
    -- from), which was silently skipping slots here that already had a
    -- perfectly good resolved item.
    if slot.exampleRewardLink and slot.exampleRewardLink ~= "" then
      hasAnyUnlocked = true
      snapshot = snapshot or { slots = {}, claimed = {} }
      snapshot.slots[tostring(slot.id)] = {
        type = slot.type,
        index = slot.index,
        level = slot.level, -- raw Blizzard value, not an ilvl -- same caveat as the live slot
        exampleRewardLink = slot.exampleRewardLink,
      }
    end
  end)
  if hasAnyUnlocked then
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
  character.vault.lastSnapshot.claimed[tostring(activityId)] = true
end

---True if this character has a remembered Great Vault snapshot with at
---least one slot -- used so "click Rewards to preview it" can still lead
---somewhere for a character whose LIVE `vault.slots` was already wiped by
---the weekly reset, as long as the last-known snapshot remembers something.
---@param character AE_Character
---@return boolean
function Data:HasVaultHistory(character)
  return character.vault ~= nil
    and character.vault.lastSnapshot ~= nil
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
  character.vault.lastUpdatedAt = time()

  character.vault.activityEncounterInfo = wipe(character.vault.activityEncounterInfo or {})
  character.vault.slots = wipe(character.vault.slots or {})
  character.vault.worldActivityProgress = wipe(character.vault.worldActivityProgress or {})

  TableForEach(self.vaultTypes or {}, function(vaultType)
    for index = 1, 3 do
      local encounters = C_WeeklyRewards.GetActivityEncounterInfo(vaultType.id, index)
      if encounters then
        TableForEach(encounters, function(encounter)
          if not encounter then return end
          encounter.type = vaultType.id
          encounter.index = index
          table.insert(character.vault.activityEncounterInfo, encounter)
        end)
      end
    end
  end)

  local activities = C_WeeklyRewards.GetActivities()
  TableForEach(activities, function(activity)
    activity.exampleRewardLink = ""
    activity.exampleRewardUpgradeLink = ""
    if activity.progress >= activity.threshold then
      local itemLink, upgradeItemLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
      activity.exampleRewardLink = itemLink
      activity.exampleRewardUpgradeLink = upgradeItemLink
    end
    table.insert(character.vault.slots, activity)

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
        if not itemLink then return end
        activity.exampleRewardLink = itemLink
        self:ArchiveVaultSnapshot(character)
        addon.Core:Render()
      end)
      if not ok then
        geterrorhandler()(("AlterEgo: resolveBestVaultItemReward failed: %s"):format(tostring(err)))
      end
    end
  end)
  self:ArchiveVaultSnapshot(character)

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
  addon.Core:Render()
  addon.Core:RequestSyncBroadcast()
end

---Refresh Mythic+ data from the API
function Data:UpdateMythicPlus()
  local character = self:GetCharacter()
  if not character then return end

  local dungeons = self:GetDungeons()
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

  character.mythicplus.dungeons = wipe(character.mythicplus.dungeons or {})
  for _, dataDungeon in pairs(dungeons) do
    local bestTimedRun, bestNotTimedRun = C_MythicPlus.GetSeasonBestForMap(dataDungeon.challengeModeID)
    local affixScores, bestOverAllScore = C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(dataDungeon.challengeModeID)

    if affixScores then
      TableForEach(affixScores, function(affixScore)
        local affix = TableGet(affixes, "name", affixScore.name)
        affixScore.id = affix and affix.id or 0
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
      affixScores = affixScores,
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
  addon.Core:Render()
  addon.Core:RequestSyncBroadcast()
end

-- function Data:GetClasses()
--   if TableCount(Data.cache.classes) > 0 then
--     return Data.cache.classes
--   end

--   for classID = 1, GetNumClasses() do
--     local className, classFile = GetClassInfo(classID)
--     if className then
--       table.insert(Data.cache.classes, {
--         ID = classID,
--         name = className,
--         file = classFile,
--         numSpecs = GetNumSpecializationsForClassID(classID)
--       })
--     end
--   end

--   return Data.cache.classes
-- end

-- function Data:GetSpecs()
--   if TableCount(Data.cache.specs) > 0 then
--     return Data.cache.specs
--   end

--   local classes = Data:GetClasses()
--   TableForEach(classes, function(cls)
--     for specIndex = 1, GetNumSpecializationsForClassID(cls.ID) do
--       local specID, name, description, icon, role, isRecommended, isAllowed = GetSpecializationInfoForClassID(cls.ID, specIndex)
--       if specID then
--         table.insert(Data.cache.specs, {
--           ID = specID,
--           name = name,
--           description = description,
--           icon = icon,
--           role = role,
--           isRecommended = isRecommended,
--           isAllowed = isAllowed,
--           classID = cls.ID,
--           className = cls.name,
--           classFile = cls.file
--         })
--       end
--     end
--   end)

--   return Data.cache.specs
-- end
