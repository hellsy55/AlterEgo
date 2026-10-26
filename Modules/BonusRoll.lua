---@class AE_Addon
local addon = select(2, ...)

---@class AE_Module_BonusRoll
local Module = addon.Core:NewModule("BonusRoll", "AceConsole-3.0")
addon.Module_BonusRoll = Module

local Data = addon.Data
local LibLiqUI = addon.Libs.LiqUI
local SetBackgroundColor = LibLiqUI.Utils.SetBackgroundColor
local SetHighlightColor = LibLiqUI.Utils.SetHighlightColor

local LEFT_WIDTH = 350 -- minimum width of the Loot side; content can expand it dynamically
local MIN_WINDOW_HEIGHT = 130
local HEADER_HEIGHT = 24
local FOOTER_HEIGHT = 20
local ROW_HEIGHT = 22
local DIFFICULTY_COLUMN_WIDTH = 60
local MAX_COLUMNS = 5 -- four raid difficulties + one overlapping dungeon column
local ICON_SIZE = 18
local RENDER_BATCH_SIZE = 6 -- limit frame work when showing long histories
local TEXT_RIGHT_RESERVE = 44 -- space between row text and the difficulty columns (spec/roll-count area + padding)
local WINDOW_EDGE_MARGIN = 80 -- keep dynamically sized windows inside the usable screen width when possible

local INDENT = {header = 8, instance = 16, boss = 30, item = 44}
local CHECK_MARKUP = CreateAtlasMarkup("common-icon-checkmark", 14, 14)

local ITEM_CONTEXT_FIELD = 12

local function getEntryKeyValues(currencyID, sourceID, contextID, keyLevel, itemID, specID)
  return table.concat({
    tostring(currencyID or 0),
    tostring(sourceID or 0),
    tostring(contextID or 0),
    tostring(keyLevel or 0),
    tostring(itemID or 0),
    tostring(specID or 0),
  }, ":")
end

local function getEntryKey(entry)
  return getEntryKeyValues(entry.currencyID, entry.sourceID, entry.contextID, entry.keyLevel, entry.itemID, entry.specID)
end

local function resolveLootSpecID(specID)
  if specID and specID ~= 0 then return specID end
  specID = GetLootSpecialization and GetLootSpecialization() or 0
  if specID and specID ~= 0 then return specID end
  local active = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
  if active and C_SpecializationInfo.GetSpecializationInfo then
    return C_SpecializationInfo.GetSpecializationInfo(active) or 0
  end
  return 0
end

local function getItemContextFromLink(itemLink)
  if type(itemLink) ~= "string" then return 0 end
  local itemString = itemLink:match("item:([%-?%d:]+)")
  if not itemString then return 0 end
  local parts = {strsplit(":", itemString)}
  return tonumber(parts[ITEM_CONTEXT_FIELD]) or 0
end

---------------------------------------------------------------------------
-- Fetching and parsing (SimulationCraft)
---------------------------------------------------------------------------

---Look for the SimulationCraft addon object.
---@return table?
local function getSimulationCraft()
  local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
  local simc = AceAddon and (AceAddon:GetAddon("Simulationcraft", true) or AceAddon:GetAddon("SimulationCraft", true))
  return simc or _G.Simulationcraft or _G.SimulationCraft
end

---Ask SimulationCraft for the "bonus_roll_items" value of the current character.
---This is the only place that talks to SimulationCraft. If its sharing API differs
---from GetSimcProfile, adjust it here.
---@return string? raw The text after "bonus_roll_items=" (can be an empty string)
---@return string? err "not_loaded", "no_api", "failed" or "no_line"
local function fetchRaw()
  local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    and (C_AddOns.IsAddOnLoaded("Simulationcraft") or C_AddOns.IsAddOnLoaded("SimulationCraft"))
  if not isLoaded then
    return nil, "not_loaded"
  end
  local simc = getSimulationCraft()
  if not simc or type(simc.GetSimcProfile) ~= "function" then
    return nil, "no_api"
  end
  -- GetSimcProfile(debugOutput, noBags, showMerchant, links)
  local ok, text = pcall(simc.GetSimcProfile, simc, false, true, false, false)
  if not ok or type(text) ~= "string" then
    return nil, "failed"
  end
  local raw = text:match("bonus_roll_items=([^\r\n]*)")
  if raw == nil then
    return nil, "no_line"
  end
  return strtrim(raw)
end

---Classify a Kith'ix bonus-roll source from its actual spell confirmation
---while inside the raid, never from a guessed source/item identifier.
local function learnKithixBonusSource(sourceID, fromSync)
  if type(sourceID) ~= "number" or sourceID <= 0 then return end
  local changed = Data.db and Data.db.global.kithixBonusRollSourceID ~= sourceID
  -- Use one stable local grouping key even if the Encounter Journal loads
  -- after some rolls. Mixing an unresolved and resolved EJ ID would split
  -- the same boss into two different raid headers in Bonus Roll History.
  Data.bonusRollSources[sourceID] = {
    kind = "raid", journalInstanceID = -3095,
    bossName = "Kith'ix", order = 1, kithix = true,
  }
  if Data.db then
    Data.db.global.kithixBonusRollSourceID = sourceID
    if changed and not fromSync and Data.MarkCharacterSyncChanged then
      Data:MarkCharacterSyncChanged(Data:GetCharacter())
    end
  end
end

---Use the same validated classification path for IDs learned from an
---authorized Multi-Account Sync character record.
function Module:LearnKithixBonusSource(sourceID)
  learnKithixBonusSource(sourceID, true)
end

---Infer a previously unseen Kith'ix source from an item in SimulationCraft's
---own export, but ONLY if that item appears in the Kith'ix Encounter Journal
---loot pool. This also classifies saved history from before the new install.
---Never use the won item ID itself as the source ID.
local function learnKithixSourcesFromSimC(entries)
  if not (EJ_GetNumLoot and EJ_GetLootInfoByIndex and EJ_SelectInstance) then return end
  local raid
  for _, candidate in ipairs(Data:GetRaidCatalog()) do
    if candidate.instanceID == 3095 then raid = candidate break end
  end
  if not raid or not raid.journalInstanceID then return end
  local relevant = {}
  for _, entry in ipairs(entries or {}) do
    if not Data.bonusRollSources[entry.sourceID]
      and Data.bonusRollRaidContexts[entry.contextID]
      and type(entry.itemID) == "number" then
      relevant[entry.itemID] = relevant[entry.itemID] or {}
      relevant[entry.itemID][entry.sourceID] = true
    end
  end
  if not next(relevant) then return end
  EJ_SelectInstance(raid.journalInstanceID)
  for i = 1, EJ_GetNumLoot() or 0 do
    local itemID = EJ_GetLootInfoByIndex(i)
    for sourceID in pairs(relevant[itemID] or {}) do
      learnKithixBonusSource(sourceID)
    end
  end
end

---Remember the source/context before the bonus-roll result arrives so the exact
---won item hyperlink can be associated with the same entry SimulationCraft exports.
function Module:SPELL_CONFIRMATION_PROMPT(_, spellID)
  local character = Data:GetCharacter()
  if not character or not Data:IsMaxLevelCharacter(character) then
    self.pendingBonusRoll = nil
    return
  end
  local prompts = GetSpellConfirmationPromptsInfo and GetSpellConfirmationPromptsInfo()
  if not prompts then return end
  for _, prompt in ipairs(prompts) do
    if prompt.spellID == spellID then
      local _, _, _, _, _, _, _, currentMapID = GetInstanceInfo()
      if currentMapID == 3095 then
        learnKithixBonusSource(prompt.displayItemID)
      end
      self.pendingBonusRoll = {
        currencyID = prompt.currencyID or 0,
        sourceID = prompt.displayItemID or 0,
        contextID = prompt.itemContext or 0,
        keyLevel = prompt.treasureContextLevel or 0,
      }
      return
    end
  end
end

---Capture the exact item hyperlink before its bonus IDs / tertiary information is
---lost by SimulationCraft's compact bonus_roll_items export.
function Module:BONUS_ROLL_RESULT(_, typeIdentifier, itemLink, _, specID)
  local character = Data:GetCharacter()
  if not character or not Data:IsMaxLevelCharacter(character) then
    self.pendingBonusRoll = nil
    return
  end
  if typeIdentifier ~= "item" or type(itemLink) ~= "string" then return end
  local itemID = tonumber(itemLink:match("|Hitem:(%d+):")) or tonumber(itemLink:match("item:(%d+):"))
  if not itemID then return end

  local pending = self.pendingBonusRoll or {}
  local currencyID = pending.currencyID or 0
  local sourceID = pending.sourceID or 0
  local contextID = pending.contextID or getItemContextFromLink(itemLink)
  local keyLevel = pending.keyLevel or 0
  specID = resolveLootSpecID(specID)

  -- Save the complete roll immediately. A character switch can happen before
  -- the next SimulationCraft profile fetch; saving only its item link would
  -- leave the offline character with no history entry to display.
  local seasonID = Data:GetCurrentSeason()
  local saved = character.bonusRoll
  if type(saved) ~= "table" or (saved.seasonID and seasonID and saved.seasonID ~= seasonID) then
    saved = {raw = "", entries = {}, exactItems = {}, pendingEntries = {}}
    character.bonusRoll = saved
  end
  saved.entries = saved.entries or {}
  saved.exactItems = saved.exactItems or {}
  saved.pendingEntries = saved.pendingEntries or {}
  local entry = {
    currencyID = currencyID, sourceID = sourceID, contextID = contextID,
    keyLevel = keyLevel, itemID = itemID, specID = specID,
    ts = C_DateAndTime and C_DateAndTime.GetServerTimeLocal
      and C_DateAndTime.GetServerTimeLocal() or time(),
  }
  saved.displayVersion = (saved.displayVersion or 0) + 1
  table.insert(saved.entries, entry)
  table.insert(saved.pendingEntries, entry)
  saved.exactItems[getEntryKey(entry)] = itemLink
  saved.seasonID = seasonID
  saved.updatedAt = time()
  if Data.MarkCharacterSyncChanged then
    Data:MarkCharacterSyncChanged(character)
  end

  self.pendingBonusRoll = nil
  C_Timer.After(0.15, function()
    if Module.window and Module.window:IsVisible() and Module.character and Module.character.GUID == UnitGUID("player") then
      Module:Refresh()
    end
  end)
end

---@param raw string
---@return table[]
local function parseRaw(raw)
  local entries = {}
  for chunk in raw:gmatch("[^/%s]+") do
    local currencyID, sourceID, contextID, keyLevel, itemID, specID = strsplit(":", chunk)
    currencyID, sourceID, contextID = tonumber(currencyID), tonumber(sourceID), tonumber(contextID)
    keyLevel, itemID, specID = tonumber(keyLevel), tonumber(itemID), tonumber(specID)
    if sourceID and itemID then
      table.insert(entries, {
        currencyID = currencyID or 0,
        sourceID = sourceID,
        contextID = contextID or 0,
        keyLevel = keyLevel or 0,
        itemID = itemID,
        specID = specID or 0,
      })
    end
  end
  return entries
end

---Return only the entries added by SimulationCraft since the last fetch.
---A count per full key preserves repeat rolls of the same item.
local function getNewExportEntries(previousRaw, currentEntries)
  local previousCounts = {}
  for _, entry in ipairs(parseRaw(previousRaw or "")) do
    local key = getEntryKey(entry)
    previousCounts[key] = (previousCounts[key] or 0) + 1
  end
  local added = {}
  for _, entry in ipairs(currentEntries) do
    local key = getEntryKey(entry)
    local count = previousCounts[key] or 0
    if count > 0 then
      previousCounts[key] = count - 1
    else
      table.insert(added, entry)
    end
  end
  return added
end

---Match a locally captured result to the same newly exported SimC roll.
---The prompt can be missing on one side, so source/context may differ; an
---item and a compatible loot spec are enough when both records are new.
---Read dated roll records from SimulationCraft's SavedVariables. The profile
---export omits timestamps, so import them from the same character's AceDB data.
---Use exact full roll keys to avoid attributing a date to another difficulty
---or loot spec when an item was won more than once.
local function importRollTimestamps(character)
  local simc = getSimulationCraft()
  if not simc or type(simc.GetCurrentSeasonId) ~= "function" then return false end
  local ok, simcSeason = pcall(simc.GetCurrentSeasonId, simc)
  if not ok or type(simcSeason) ~= "number" then return false end

  local info = character.info
  local rolls
  if info and type(info.name) == "string" and info.name ~= ""
    and type(info.realm) == "string" and info.realm ~= "" then
    local db = _G.SimulationCraftDB
    local charDB = type(db) == "table" and db.char
    local simcCharacter = type(charDB) == "table" and charDB[info.name .. " - " .. info.realm]
    rolls = type(simcCharacter) == "table" and simcCharacter.bonusRolls
  end
  if character.GUID == UnitGUID("player") and simc.db and simc.db.char then
    rolls = simc.db.char.bonusRolls or rolls
  end
  if type(rolls) ~= "table" then return false end

  local saved = character.bonusRoll
  if not saved or type(saved.entries) ~= "table" then return false end
  local buckets = {}
  for _, roll in ipairs(rolls) do
    if type(roll) == "table" and roll.season == simcSeason
      and type(roll.ts) == "number" and roll.ts > 0 then
      local key = getEntryKeyValues(roll.currency, roll.source, roll.context,
        roll.keyLevel, roll.itemId, roll.spec)
      buckets[key] = buckets[key] or {}
      table.insert(buckets[key], roll.ts)
    end
  end
  for _, bucket in pairs(buckets) do table.sort(bucket) end
  local offsets = {}
  local changed = false
  for _, entry in ipairs(saved.entries) do
    local key = getEntryKey(entry)
    local bucket = buckets[key]
    local nextIndex = (offsets[key] or 0) + 1
    offsets[key] = nextIndex
    local timestamp = bucket and bucket[nextIndex]
    if timestamp and entry.ts ~= timestamp then
      entry.ts = timestamp
      changed = true
    end
  end
  if changed then
    saved.displayVersion = (saved.displayVersion or 0) + 1
    if Data.MarkCharacterSyncChanged then Data:MarkCharacterSyncChanged(character) end
  end
  return changed
end

local function sameBonusRollResult(first, second)
  return first.itemID == second.itemID
    and (first.specID == second.specID or first.specID == 0 or second.specID == 0)
end

---Fetch fresh data for the logged in character and reconcile locally captured
---rolls that SimulationCraft has not exported yet (or could not export).
---@param character AE_Character
---@return string? err
function Module:UpdateCharacter(character)
  if not Data:IsMaxLevelCharacter(character) then return nil end
  local raw, err = fetchRaw()
  if raw == nil then
    importRollTimestamps(character)
    return err
  end

  local seasonID = Data:GetCurrentSeason()
  local saved = character.bonusRoll
  if type(saved) ~= "table" or (saved.seasonID and seasonID and saved.seasonID ~= seasonID) then
    saved = nil -- SimulationCraft exports only the current season.
  end

  -- A temporarily empty or truncated same-season export must not erase
  -- entries already confirmed by an earlier SimulationCraft snapshot.
  local entries = parseRaw(raw)
  if saved and saved.raw and #entries < #parseRaw(saved.raw) then
    importRollTimestamps(character)
    return "incomplete"
  end

  if saved and saved.raw == raw and type(saved.entries) == "table" then
    learnKithixSourcesFromSimC(saved.entries)
    -- A successful check is still an update even when the roll history itself
    -- did not change. Keep the footer meaningful after the automatic login check.
    saved.updatedAt = time()
    saved.seasonID = seasonID
    importRollTimestamps(character)
    -- A timestamp-only refresh is local metadata, not a new roll. Avoid
    -- incrementing syncRevision and broadcasting identical history.
    return nil
  end

  local pendingEntries = saved and saved.pendingEntries or {}
  local exactItems = saved and saved.exactItems or {}
  local newExportEntries = getNewExportEntries(saved and saved.raw, entries)

  -- Only match new SimC records against locally recorded results. Comparing
  -- with all historical records would consume a new roll on an older copy of
  -- the same item, dropping a legitimate repeat roll from the history.
  for _, exported in ipairs(newExportEntries) do
    local matchIndex
    for i, pending in ipairs(pendingEntries) do
      if getEntryKey(pending) == getEntryKey(exported) then
        matchIndex = i
        break
      end
    end
    if not matchIndex then
      for i, pending in ipairs(pendingEntries) do
        if sameBonusRollResult(pending, exported) then
          matchIndex = i
          break
        end
      end
    end
    if matchIndex then
      local pending = table.remove(pendingEntries, matchIndex)
      local link = exactItems[getEntryKey(pending)]
      if link then exactItems[getEntryKey(exported)] = link end
      exported.ts = pending.ts
    end
  end
  for _, pending in ipairs(pendingEntries) do
    table.insert(entries, pending)
  end

  character.bonusRoll = {
    raw = raw,
    entries = entries,
    pendingEntries = pendingEntries,
    seasonID = seasonID,
    updatedAt = time(),
    exactItems = exactItems,
    displayVersion = (saved and saved.displayVersion or 0) + 1,
  }
  importRollTimestamps(character)
  learnKithixSourcesFromSimC(entries)
  if Data.MarkCharacterSyncChanged then
    Data:MarkCharacterSyncChanged(character)
  end
  return nil
end

---Refresh Bonus Roll once on the character's initial login so saved data does
---not depend on opening the Bonus Roll window. The short retries cover startup
---ordering where SimulationCraft or the character info cache is not ready yet.
function Module:RefreshOnInitialLogin()
  local guid = UnitGUID("player")
  if not guid or self.loginRefreshGUID == guid then return end
  self.loginRefreshGUID = guid

  local retryDelays = {1, 3, 6}
  local attempt = 0

  local function tryRefresh()
    if UnitGUID("player") ~= guid then return end

    local character = Data:GetCharacter(guid)
    if not character then return end

    -- Character info can lag slightly behind PLAYER_ENTERING_WORLD on a fresh
    -- login. Refresh it before deciding whether this character is max level.
    if not Data:IsMaxLevelCharacter(character) and Data.UpdateCharacterInfo then
      Data:UpdateCharacterInfo()
      character = Data:GetCharacter(guid)
    end

    if not Data:IsMaxLevelCharacter(character) then return end
    if InCombatLockdown and InCombatLockdown() then
      self.loginSyncDeferredGUID = guid
      self.combatRefreshPending = true
      return
    end

    local err = self:UpdateCharacter(character)
    if not err then
      if self.window and self.window:IsVisible() and self.character and self.character.GUID == guid then
        self:ScheduleRender()
      end
      return
    end

    attempt = attempt + 1
    local delay = retryDelays[attempt]
    if delay then
      C_Timer.After(delay, tryRefresh)
    end
  end

  -- SimulationCraft creates a complete text profile to supply one history
  -- line. Defer the initial export out of the login/loading critical path;
  -- opening Bonus Roll still performs its normal live refresh immediately.
  C_Timer.After(5, tryRefresh)
end

---------------------------------------------------------------------------
-- Building the list
---------------------------------------------------------------------------

---@param entry table
---@return number? difficultyID
local function getRaidDifficultyID(entry)
  return Data.bonusRollRaidContexts[entry.contextID]
end

---@param difficultyID number
---@return table?
local function getDifficulty(difficultyID)
  for _, difficulty in ipairs(Data:GetRaidDifficulties(true)) do
    if difficulty.id == difficultyID then return difficulty end
  end
end

---@param journalInstanceID number
---@param list table[]
---@return table?
local function findByJournalInstance(list, journalInstanceID)
  for _, instance in ipairs(list) do
    if instance.journalInstanceID == journalInstanceID then return instance end
  end
end

local function getBossName(source)
  if source.bossName then return source.bossName end
  if source.journalEncounterID and EJ_GetEncounterInfo then
    local name = EJ_GetEncounterInfo(source.journalEncounterID)
    if name then return name end
  end
  return nil
end

---@param section table[]
---@param instanceKey string
---@param name string
---@param order number
local function getInstanceGroup(section, lookup, instanceKey, name, order)
  local group = lookup[instanceKey]
  if not group then
    group = {key = instanceKey, name = name, order = order, bosses = {}, bossLookup = {}, count = 0}
    lookup[instanceKey] = group
    table.insert(section, group)
  end
  return group
end

local function getBossGroup(instance, bossKey, name, order)
  local boss = instance.bossLookup[bossKey]
  if not boss then
    boss = {name = name, order = order, entries = {}}
    instance.bossLookup[bossKey] = boss
    table.insert(instance.bosses, boss)
  end
  return boss
end

---Sort rolls: raids LFR -> Normal -> Heroic -> Mythic; dungeons by key level (highest first).
local function sortEntries(a, b)
  local difficultyA = getDifficulty(getRaidDifficultyID(a) or 0)
  local difficultyB = getDifficulty(getRaidDifficultyID(b) or 0)
  local orderA = difficultyA and difficultyA.order or math.huge
  local orderB = difficultyB and difficultyB.order or math.huge
  if orderA ~= orderB then return orderA < orderB end
  if a.keyLevel ~= b.keyLevel then return a.keyLevel > b.keyLevel end
  return a.itemID < b.itemID
end

---@param entries table[]
---@return table sections
local function buildSections(entries)
  local sections = {
    raids = {list = {}, lookup = {}},
    dungeons = {list = {}, lookup = {}},
    unknown = {list = {}, lookup = {}},
  }

  for _, entry in ipairs(entries) do
    local source = Data.bonusRollSources[entry.sourceID]
    local section, instance, bossKey, bossName, bossOrder
    if source then
      local isRaid = source.kind == "raid"
      local dataInstance = findByJournalInstance(isRaid and Data:GetRaidCatalog() or LibLiqUI.Data.dungeons, source.journalInstanceID)
      section = isRaid and sections.raids or sections.dungeons
      local instanceName = dataInstance and dataInstance.name
        or (source.kithix and "The Unbinding of Kith'ix")
        or ("Instance " .. source.journalInstanceID)
      local instanceOrder = dataInstance and dataInstance.order or (source.kithix and 3 or 0)
      instance = getInstanceGroup(section.list, section.lookup, tostring(source.journalInstanceID), instanceName, instanceOrder)
      instance.kind = source.kind
      bossKey = source.journalEncounterID or source.bossName or false
      bossName = getBossName(source)
      bossOrder = source.order or 0
    else
      section = sections.unknown
      instance = getInstanceGroup(section.list, section.lookup, "unknown", "Unknown source", 0)
      if Data.bonusRollKeystoneContexts[entry.contextID] then
        instance.kind = "dungeon"
      else
        instance.kind = getRaidDifficultyID(entry) and "raid" or "dungeon"
      end
      bossKey = entry.sourceID
      bossName = "Source ID " .. entry.sourceID
      bossOrder = entry.sourceID
    end
    local boss = getBossGroup(instance, bossKey, bossName, bossOrder)
    table.insert(boss.entries, entry)
    instance.count = instance.count + 1
  end

  for _, section in pairs(sections) do
    for _, instance in ipairs(section.list) do
      for _, boss in ipairs(instance.bosses) do
        table.sort(boss.entries, sortEntries)
        boss.items = {}
        local itemLookup = {}
        local itemOrder = {}
        for _, entry in ipairs(boss.entries) do
          local group = itemLookup[entry.itemID]
          if not group then
            group = {specs = {}, order = {}}
            itemLookup[entry.itemID] = group
            table.insert(itemOrder, group)
          end
          local specID = entry.specID or 0
          local item = group.specs[specID]
          if not item then
            item = {itemID = entry.itemID, specID = specID, entries = {}}
            group.specs[specID] = item
            table.insert(group.order, item)
          end
          table.insert(item.entries, entry)
        end
        -- Keep matching items together while showing each loot spec on its
        -- own row. Rolls in other difficulties still share that spec's row.
        for _, group in ipairs(itemOrder) do
          for _, item in ipairs(group.order) do
            table.insert(boss.items, item)
          end
        end
      end
      table.sort(instance.bosses, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return (a.name or "") < (b.name or "")
      end)
    end
  end
  -- Respect the raid order defined by the current season data; dungeons stay alphabetical.
  table.sort(sections.raids.list, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
  end)
  table.sort(sections.dungeons.list, function(a, b) return a.name < b.name end)
  return sections
end

---@param instance table
---@return string[] lines
local function getInstanceTooltipLines(instance)
  local lines = {}
  if instance.kind == "dungeon" then
    -- Keystone levels are intentionally not separated in Bonus Roll History.
    -- Preserve them on the underlying entries for accurate item tooltips.
    table.insert(lines, {format("Rolls used: %d", instance.count), 1, 1, 1})
  else
    local perDifficulty = {}
    for _, boss in ipairs(instance.bosses) do
      for _, entry in ipairs(boss.entries) do
        local id = getRaidDifficultyID(entry) or 0
        perDifficulty[id] = (perDifficulty[id] or 0) + 1
      end
    end
    table.insert(lines, {format("Rolls used: %d", instance.count), 1, 1, 1})
    local difficulties = {}
    for _, difficulty in ipairs(Data:GetRaidDifficulties(true)) do
      table.insert(difficulties, difficulty)
    end
    table.sort(difficulties, function(a, b) return a.order < b.order end)
    for _, difficulty in ipairs(difficulties) do
      if perDifficulty[difficulty.id] then
        table.insert(lines, {format("%s: %d", difficulty.short or difficulty.name, perDifficulty[difficulty.id]), difficulty.color:GetRGB()})
      end
    end
  end
  return lines
end

---@param sections table
---@param collapsedSections table<string, boolean>?
---@param collapsedInstances table<string, boolean>?
---@return table[] rows
local function buildRows(sections, collapsedSections, collapsedInstances)
  local rows = {}
  collapsedSections = collapsedSections or {}
  collapsedInstances = collapsedInstances or {}

  local function addSection(sectionKey, title, section)
    if #section.list == 0 then return end

    local sectionCollapsible = sectionKey == "raids" or sectionKey == "dungeons"
    local sectionCollapsed = sectionCollapsible and collapsedSections[sectionKey] == true
    table.insert(rows, {
      type = "header",
      text = title,
      sectionKey = sectionKey,
      sectionInstances = section.list,
      collapsible = sectionCollapsible,
      collapsed = sectionCollapsed,
    })
    if sectionCollapsed then return end

    for _, instance in ipairs(section.list) do
      local instanceCollapsible = (sectionKey == "raids" and instance.kind == "raid")
        or (sectionKey == "dungeons" and instance.kind == "dungeon")
      local instanceCollapsed = instanceCollapsible and collapsedInstances[instance.key] == true
      table.insert(rows, {
        type = "instance",
        text = instance.name,
        count = instance.count,
        instance = instance,
        instanceKey = instance.key,
        collapsible = instanceCollapsible,
        collapsed = instanceCollapsed,
      })
      if not instanceCollapsed then
        for _, boss in ipairs(instance.bosses) do
          if boss.name then
            table.insert(rows, {type = "boss", text = boss.name, boss = boss, instance = instance})
          end
          for _, item in ipairs(boss.items or {}) do
            table.insert(rows, {
              type = "item",
              item = item,
              instance = instance,
              indent = boss.name and INDENT.item or INDENT.boss,
            })
          end
        end
      end
    end
  end

  addSection("raids", "Raids", sections.raids)
  addSection("dungeons", "Dungeons", sections.dungeons)
  addSection("unknown", "Unknown source", sections.unknown)
  return rows
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local getItemDisplay
local measureFont

---@param text any
---@param fontObject string
---@return number
local function measureRowText(text, fontObject)
  if text == nil or text == "" then return 0 end
  if not measureFont then
    measureFont = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight_NoShadow")
    measureFont:SetWordWrap(false)
  end
  measureFont:SetFontObject(fontObject)
  measureFont:SetText(tostring(text))
  return math.ceil(measureFont:GetStringWidth() or 0)
end

---@param rows table[]
---@return number leftWidth
local function calculateLeftWidth(rows, firstIndex, lastIndex, required)
  required = required or LEFT_WIDTH
  for index = firstIndex or 1, lastIndex or #rows do
    local data = rows[index]
    local text, indent, fontObject, leadingWidth
    leadingWidth = 0
    if data.type == "header" then
      text = (data.collapsible and "- " or "") .. (data.text or "")
      indent = INDENT.header
      fontObject = "GameFontNormal"
    elseif data.type == "instance" then
      text = (data.collapsible and "- " or "") .. (data.text or "")
      indent = INDENT.instance
      fontObject = "GameFontHighlight_NoShadow"
    elseif data.type == "boss" then
      text = data.text or ""
      indent = INDENT.boss
      fontObject = "GameFontHighlight_NoShadow"
    elseif data.type == "item" then
      local name = getItemDisplay(data.item.itemID)
      text = name or ""
      indent = data.indent or INDENT.item
      leadingWidth = ICON_SIZE + 6
      fontObject = "GameFontHighlight_NoShadow"
    end
    if text then
      local rowWidth = indent + leadingWidth + measureRowText(text, fontObject) + TEXT_RIGHT_RESERVE + 10
      required = math.max(required, rowWidth)
    end
  end
  return math.ceil(required)
end

---@param itemID number
---@return string name, string? icon, table? color
getItemDisplay = function(itemID)
  Module.itemDisplayCache = Module.itemDisplayCache or {}
  local cached = Module.itemDisplayCache[itemID]
  if cached then return cached[1], cached[2], cached[3] end
  local name = C_Item.GetItemNameByID(itemID)
  local icon = select(5, C_Item.GetItemInfoInstant(itemID))
  local quality = C_Item.GetItemQualityByID(itemID)
  local color = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
  if not name then
    Module.itemLoadPending = Module.itemLoadPending or {}
    if not Module.itemLoadPending[itemID] then
      Module.itemLoadPending[itemID] = true
      Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        Module.itemLoadPending[itemID] = nil
        Module.itemDisplayCache[itemID] = nil
        Module:ScheduleRender()
      end)
    end
    name = "Item " .. itemID
  else
    Module.itemDisplayCache[itemID] = {name, icon, color}
  end
  return name, icon, color
end

---@param specID number
---@return string? name, number? icon
local function getSpecDisplay(specID)
  if not specID or specID == 0 then return nil end
  local _, name, _, icon = GetSpecializationInfoByID(specID)
  return name, icon
end

---@param entry table
---@return string
local function getDifficultyText(entry)
  local difficultyID = getRaidDifficultyID(entry)
  if difficultyID then
    local difficulty = getDifficulty(difficultyID)
    return difficulty and difficulty.name or "Raid"
  end
  if entry.keyLevel and entry.keyLevel > 0 then
    return format("Mythic+ %d", entry.keyLevel)
  end
  return UNKNOWN
end

---@param entry table
---@return string?
local function getExactItemLink(entry)
  local saved = Module.character and Module.character.bonusRoll
  local exactItems = saved and saved.exactItems
  return exactItems and exactItems[getEntryKey(entry)] or nil
end

---Canonical Season 2 Bonus Roll rewards. These are aligned with the Great Vault
---reward table, not with SimulationCraft's treasureContextLevel. For raid entries,
---treasureContextLevel describes the prompt context and does not equal the final
---upgrade rank (passing it straight to GetItemByID can incorrectly produce 2/6).
local RAID_BONUS_ROLL_REWARDS = {
  [17] = {itemLevel = 292}, -- LFR
  [14] = {itemLevel = 305},     -- Normal
  [15] = {itemLevel = 318},     -- Heroic
  [16] = {itemLevel = 334},     -- Mythic
}

local HIGH_MYTHIC_BONUS_ROLL_SOURCES = {
  [278290] = true, -- The Coiled Altar
  [278284] = true, -- Ula'tek
}

---@param keyLevel number
---@return table? reward
local function getDungeonBonusRollReward(keyLevel)
  if not keyLevel or keyLevel <= 0 then return nil end
  if keyLevel >= 10 then return {itemLevel = 318} end
  if keyLevel >= 7 then return {itemLevel = 315} end
  if keyLevel == 6 then return {itemLevel = 311} end
  if keyLevel >= 4 then return {itemLevel = 308} end
  if keyLevel >= 2 then return {itemLevel = 305} end
  return nil
end

---@param entry table
---@return table? reward
local function getCanonicalBonusRollReward(entry)
  local difficultyID = getRaidDifficultyID(entry)
  if difficultyID then
    if difficultyID == 16 and HIGH_MYTHIC_BONUS_ROLL_SOURCES[entry.sourceID] then
      return {itemLevel = 344}
    end
    return RAID_BONUS_ROLL_REWARDS[difficultyID]
  end
  if Data.bonusRollKeystoneContexts[entry.contextID] then
    return getDungeonBonusRollReward(entry.keyLevel)
  end
  return nil
end

---Show Blizzard's native ItemKey tooltip at the canonical reward item level.
---This keeps historical SimC-only rolls on the stock WoW tooltip path instead of
---rebuilding tooltip lines in AlterEgo.
---@param entry table
---@param reward table
---@return boolean shown
local function setCanonicalHistoricalTooltip(entry, reward)
  if type(GameTooltip.SetItemKey) ~= "function" then return false end
  GameTooltip:SetItemKey(entry.itemID, reward.itemLevel, 0)
  return true
end

---@param entry table
---@return string? itemLink
local function getContextualItemLink(entry)
  if not C_TooltipInfo or type(C_TooltipInfo.GetItemByID) ~= "function" then return nil end
  local ok, tooltipData = pcall(C_TooltipInfo.GetItemByID, entry.itemID, nil, entry.contextID, entry.keyLevel)
  if not ok or type(tooltipData) ~= "table" then return nil end
  return tooltipData.hyperlink
end

---@param row Button
---@param entry table
local function showItemTooltip(row, entry)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

  -- New rolls always use the exact hyperlink captured at BONUS_ROLL_RESULT, including
  -- tertiary/socket bonus IDs. Historical SimC-only rolls use the canonical Season 2
  -- reward item level, avoiding treasureContextLevel's incorrect rank mapping.
  local exactItemLink = getExactItemLink(entry)
  if exactItemLink then
    GameTooltip:SetHyperlink(exactItemLink)
  else
    local reward = getCanonicalBonusRollReward(entry)
    local shown = reward and setCanonicalHistoricalTooltip(entry, reward)
    if not shown then
      local contextualItemLink = getContextualItemLink(entry)
      if contextualItemLink then
        GameTooltip:SetHyperlink(contextualItemLink)
      else
        GameTooltip:SetItemByID(entry.itemID)
      end
    end
  end
  GameTooltip:Show()
end

---Show acquisition history only on the item row; difficulty checkmarks
---retain their unmodified Blizzard item tooltip.
local function showAcquisitionTooltip(row)
  local data = row.data
  if not data or not data.item then return end
  local name = getItemDisplay(data.item.itemID)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(name or ("Item " .. data.item.itemID), 1, 0.82, 0)
  for _, entry in ipairs(data.item.entries) do
    local acquired = type(entry.ts) == "number" and entry.ts > 0
      and date("%d/%m/%Y %H:%M", entry.ts) or "Date unavailable"
    GameTooltip:AddDoubleLine(getDifficultyText(entry), acquired, 1, 1, 1, 0.9, 0.9, 0.9)
  end
  GameTooltip:Show()
end

---@param row Button
local function showInstanceTooltip(row)
  local instance = row.data.instance
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  -- Match the yellow instance titles in the Bonus Roll list.
  GameTooltip:AddLine(instance.name, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
  for _, line in ipairs(getInstanceTooltipLines(instance)) do
    GameTooltip:AddLine(line[1], line[2], line[3], line[4])
  end
  GameTooltip:Show()
end

local function createRow(content)
  local row = CreateFrame("Button", nil, content)
  row:SetHeight(ROW_HEIGHT)
  SetHighlightColor(row, 1, 1, 1, 0)

  row.itemIcon = row:CreateTexture(nil, "ARTWORK")
  row.itemIcon:SetSize(ICON_SIZE, ICON_SIZE)
  row.itemIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.text = row:CreateFontString(nil, "OVERLAY")
  row.text:SetFontObject("GameFontHighlight_NoShadow")
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)

  row.specIcon = row:CreateTexture(nil, "ARTWORK")
  row.specIcon:SetSize(ICON_SIZE - 2, ICON_SIZE - 2)
  row.specIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.count = row:CreateFontString(nil, "OVERLAY")
  row.count:SetFontObject("GameFontDisableSmall")

  -- Cells are positioned in Render, because the number of columns changes.
  -- Item cells are real mouse regions so each obtained difficulty can show
  -- the exact variant that was won in that column.
  row.cells = {}
  for index = 1, MAX_COLUMNS do
    local cell = CreateFrame("Button", nil, row)
    cell:SetSize(DIFFICULTY_COLUMN_WIDTH, ROW_HEIGHT)
    cell.text = cell:CreateFontString(nil, "OVERLAY")
    cell.text:SetFontObject("GameFontHighlight_NoShadow")
    cell.text:SetAllPoints(cell)
    cell.text:SetJustifyH("CENTER")
    cell.text:SetJustifyV("MIDDLE")
    cell.entry = nil
    cell:EnableMouse(false)
    cell:SetScript("OnEnter", function(self)
      if not self.entry then return end
      SetHighlightColor(row, 1, 1, 1, 0.10)
      showItemTooltip(row, self.entry)
    end)
    cell:SetScript("OnLeave", function()
      GameTooltip:Hide()
      SetHighlightColor(row, 1, 1, 1, row:IsMouseOver() and 0.10 or 0)
    end)
    row.cells[index] = cell
  end

  row:SetScript("OnEnter", function(self)
    local data = self.data
    if not data then return end
    if data.type == "item" then
      SetHighlightColor(self, 1, 1, 1, 0.10)
      showAcquisitionTooltip(self)
    elseif data.type == "instance" or data.type == "boss" then
      SetHighlightColor(self, 1, 1, 1, 0.05)
      showInstanceTooltip(self)
    end
  end)
  row:SetScript("OnLeave", function(self)
    SetHighlightColor(self, 1, 1, 1, 0)
    GameTooltip:Hide()
  end)
  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnClick", function(self, button)
    if button ~= "LeftButton" or not self.data or not self.data.collapsible then return end
    Module:ToggleCollapsedRow(self.data)
  end)
  return row
end

local function resetRow(row)
  row.itemIcon:Hide()
  row.specIcon:Hide()
  row.count:SetFontObject("GameFontDisableSmall")
  local countFont, countSize, countFlags = GameFontDisableSmall:GetFont()
  if countFont and countSize then
    row.count:SetFont(countFont, countSize + 2, countFlags)
  end
  row.count:SetText("")
  for _, cell in ipairs(row.cells) do
    cell.text:SetText("")
    cell.entry = nil
    cell:EnableMouse(false)
  end
  row.text:SetText("")
  row.text:ClearAllPoints()
  SetBackgroundColor(row, 0, 0, 0, 0)
  SetHighlightColor(row, 1, 1, 1, 0)
end

function Module:ResetCollapsedRows()
  local hadCollapsed = next(self.collapsedSections or {}) or next(self.collapsedInstances or {})
  self.collapsedSections = {}
  self.collapsedInstances = {}
  if hadCollapsed then self.renderedCharacter = nil end
end

---@param data table
function Module:ToggleCollapsedRow(data)
  if data.type == "header" and (data.sectionKey == "raids" or data.sectionKey == "dungeons") then
    self.collapsedSections = self.collapsedSections or {}
    self.collapsedSections[data.sectionKey] = not self.collapsedSections[data.sectionKey]
  elseif data.type == "instance" and data.instanceKey
    and data.instance and (data.instance.kind == "raid" or data.instance.kind == "dungeon") then
    self.collapsedInstances = self.collapsedInstances or {}
    self.collapsedInstances[data.instanceKey] = not self.collapsedInstances[data.instanceKey]
  else
    return
  end
  self:Render()
end

function Module:CreateWindow()
  if self.window then return end
  local windows = Data.db.global.liqui.windows
  windows.BonusRoll = windows.BonusRoll or {}
  self.window = LibLiqUI:NewElement("Window", {
    name = addon.name .. "BonusRoll",
    storage = windows.BonusRoll,
    title = "Bonus Roll",
    onShow = function()
      if InCombatLockdown and InCombatLockdown() then
        Module:ShowCombatSnapshot()
      else
        Module:ResetCollapsedRows()
        Module:Refresh()
      end
    end,
  })
  self.window:SetBodySize(LEFT_WIDTH, MIN_WINDOW_HEIGHT)
  local body = self.window.body

  -- Column headers
  local header = CreateFrame("Frame", "$parentHeader", body)
  header:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
  header:SetHeight(HEADER_HEIGHT)
  SetBackgroundColor(header, 0, 0, 0, 0.3)
  header.loot = header:CreateFontString(nil, "OVERLAY")
  header.loot:SetFontObject("GameFontNormal")
  header.loot:SetPoint("LEFT", header, "LEFT", INDENT.header, 0)
  header.loot:SetText("Loot")
  header.difficulty = header:CreateFontString(nil, "OVERLAY")
  header.difficulty:SetFontObject("GameFontNormal")
  header.difficulty:SetText("Difficulty")
  self.header = header

  -- Footer (status text)
  self.footer = body:CreateFontString(nil, "OVERLAY")
  self.footer:SetFontObject("GameFontDisableSmall")
  local footerFont, footerSize, footerFlags = GameFontNormalSmall:GetFont()
  if footerFont and footerSize then
    self.footer:SetFont(footerFont, footerSize + 2, footerFlags)
  end
  self.footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 8, 4)
  self.footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 4)
  self.footer:SetJustifyH("LEFT")

  -- Content list. The window grows vertically with the rows instead of using
  -- vertical scrolling, per the Bonus Roll window's intentionally unbounded list.
  self.scroll = CreateFrame("ScrollFrame", "$parentScroll", body)
  self.scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  self.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, FOOTER_HEIGHT)
  self.content = CreateFrame("Frame", "$parentContent", self.scroll)
  self.content:SetSize(LEFT_WIDTH, 1)
  self.scroll:SetScrollChild(self.content)
  self.scroll:EnableMouseWheel(false)

  self.empty = self.scroll:CreateFontString(nil, "OVERLAY")
  self.empty:SetFontObject("GameFontDisable")
  self.empty:SetPoint("CENTER", self.scroll, "CENTER", 0, 0)
  self.empty:SetJustifyH("CENTER")
  self.empty:SetJustifyV("MIDDLE")
  self.empty:SetWidth(LEFT_WIDTH - 40)

  self.rows = {}
end

---@param character AE_Character
---@return string
local function getTitle(character)
  local name = character.info and character.info.name or "?"
  local classFile = character.info and character.info.class and character.info.class.file
  local classColor = classFile and classFile ~= "" and C_ClassColor.GetClassColor(classFile)
  if classColor then
    name = classColor:WrapTextInColorCode(name)
  end
  return "Bonus Roll - " .. name
end

local ERROR_TEXT = {
  not_loaded = "SimulationCraft is not loaded. Showing saved data.",
  no_api = "Could not talk to SimulationCraft. Showing saved data.",
  failed = "SimulationCraft returned an error. Showing saved data.",
  no_line = "SimulationCraft did not report any bonus roll data. Showing saved data.",
  incomplete = "SimulationCraft returned incomplete bonus roll history. Showing saved data.",
}

---During combat, reuse the already completed view. Never show another
---character's rows when opening a character that has not been rendered yet.
function Module:ShowCombatSnapshot()
  if not self.window or not self.character then return end
  self.combatRefreshPending = true
  self.renderSerial = (self.renderSerial or 0) + 1
  if self.renderedCharacter == self.character.GUID then
    self.header:Show()
    self.content:Show()
    self.empty:Hide()
    return
  end
  self.content:Hide()
  self.header:Hide()
  self.empty:SetText("Bonus Roll will load after combat.")
  self.empty:Show()
  self.footer:SetText("")
end

---Re-check the data (current character only) and redraw when necessary.
function Module:Refresh()
  if not self.window or not self.character then return end
  if InCombatLockdown and InCombatLockdown() then
    self:ShowCombatSnapshot()
    return
  end
  local character = self.character
  self.updateError = nil
  if Data:IsMaxLevelCharacter(character) and character.GUID == UnitGUID("player") then
    self.updateError = self:UpdateCharacter(character)
  else
    importRollTimestamps(character)
  end
  local saved = character.bonusRoll
  if self.renderedCharacter ~= character.GUID
    or self.renderedEntries ~= (saved and saved.entries)
    or self.renderedVersion ~= (saved and saved.displayVersion or 0)
    or self.renderedError ~= self.updateError
    or not self.content:IsShown() then
    -- A profile fetch and full layout must not share one long Lua frame.
    -- Keep the previous character's rows hidden until the new view is ready.
    if self.renderedCharacter ~= character.GUID then
      self.content:Hide()
      self.header:Hide()
      self.empty:SetText("Loading bonus roll history...")
      self.empty:Show()
    end
    self:ScheduleRender()
  else
    if saved and saved.updatedAt then
      self.footer:SetText(format("Updated on: %s", date("%d/%m - %H:%M", saved.updatedAt)))
    end
  end
end

function Module:ScheduleRender()
  if self.renderPending then return end
  self.renderPending = true
  C_Timer.After(0.1, function()
    self.renderPending = false
    if self.window and self.window:IsVisible() then self:Render() end
  end)
end

---Which column a roll belongs to: the shared dungeon column or a raid difficultyID.
---@param entry table
---@param instanceKind string?
---@return "key"|number|nil
local function getEntryColumn(entry, instanceKind)
  local isKeystone = instanceKind == "dungeon" or Data.bonusRollKeystoneContexts[entry.contextID]
  if isKeystone then
    -- Any dungeon roll belongs to the same cell, regardless of keystone level.
    return "key"
  end
  return getRaidDifficultyID(entry)
end

---Show used raid difficulties at their native spacing, with a dungeon cell
---drawn independently at the center of the raid difficulty area.
---@param rows table[]
---@return table[] columns, table<string|number, number> columnIndex
function Module:BuildColumns(rows)
  local used = {}
  for _, data in ipairs(rows) do
    if data.type == "item" then
      for _, entry in ipairs(data.item.entries) do
        local column = getEntryColumn(entry, data.instance.kind)
        if column then used[column] = true end
      end
    end
  end
  local columns, columnIndex = {}, {}
  for _, difficulty in ipairs(self:GetOrderedDifficulties()) do
    if used[difficulty.id] then
      table.insert(columns, {id = difficulty.id, label = difficulty.color:WrapTextInColorCode(difficulty.abbr)})
      columnIndex[difficulty.id] = #columns
    end
  end
  if used.key then
    -- Do not reserve a fifth difficulty slot for the dungeon column.
    -- It shares the horizontal center without moving any raid difficulty.
    table.insert(columns, {id = "key", label = ""})
    columnIndex.key = #columns
  end
  return columns, columnIndex
end

function Module:Render()
  if not self.window or not self.window:IsVisible() or not self.character then return end
  if InCombatLockdown and InCombatLockdown() then
    self:ShowCombatSnapshot()
    return
  end
  self.renderSerial = (self.renderSerial or 0) + 1
  local renderSerial = self.renderSerial
  local character = self.character
  self.header:Show()
  self.content:Show()
  self.window:SetTitle(getTitle(character))

  if not Data:IsMaxLevelCharacter(character) then
    self.header.loot:Hide()
    self.header.difficulty:Hide()
    for _, row in ipairs(self.rows) do
      row:Hide()
      row.data = nil
    end
    local maxLevel = Data.GetCurrentMaxLevel and Data:GetCurrentMaxLevel()
    if maxLevel then
      self.empty:SetText(format("Bonus Roll is only available for max-level characters.\n\nThis character must reach level %d before Bonus Roll can be checked.", maxLevel))
    else
      self.empty:SetText("Bonus Roll is only available for max-level characters.")
    end
    self.empty:SetWidth(LEFT_WIDTH - 40)
    self.empty:Show()
    self.footer:SetText("")
    self.scroll:SetVerticalScroll(0)
    self.window:SetBodySize(LEFT_WIDTH, MIN_WINDOW_HEIGHT)
    self.content:SetSize(LEFT_WIDTH, 1)
    self.renderedCharacter = character.GUID
    self.renderedEntries = character.bonusRoll and character.bonusRoll.entries
    self.renderedVersion = character.bonusRoll and character.bonusRoll.displayVersion or 0
    self.renderedError = self.updateError
    return
  end

  local saved = character.bonusRoll
  local entries = saved and saved.entries or {}
  local sections = buildSections(entries)
  -- Keep the difficulty/spec columns stable while groups are collapsed so the
  -- window does not resize horizontally on every expand/collapse click.
  local allRows = buildRows(sections)
  local rows = buildRows(sections, self.collapsedSections, self.collapsedInstances)
  local columns, columnIndex = self:BuildColumns(allRows)
  local numColumns = #columns
  local numRaidColumns = numColumns - (columnIndex.key and 1 or 0)
  local columnsWidth = math.max(numRaidColumns, columnIndex.key and 1 or 0) * DIFFICULTY_COLUMN_WIDTH

  -- Recalculate the Loot side from the actual content so long raid, boss, dungeon,
  -- and item names expand the window instead of escaping the body or colliding with
  -- Difficulty/Rolls. Keep a minimum width, but cap growth to the usable screen width.
  -- The text FontStrings remain bounded by their LEFT/RIGHT anchors, so even at the
  -- screen cap they cannot render outside the window or over the fixed columns.
  local function applyLayout(desiredLeftWidth)
  if self.renderSerial ~= renderSerial or not self.window:IsVisible()
    or self.character ~= character then return end
  if InCombatLockdown and InCombatLockdown() then
    self:ShowCombatSnapshot()
    return
  end
  local screenWidth = UIParent and UIParent:GetWidth() or (LEFT_WIDTH + columnsWidth + WINDOW_EDGE_MARGIN)
  local maxBodyWidth = math.max(LEFT_WIDTH + columnsWidth, screenWidth - WINDOW_EDGE_MARGIN)
  local maxLeftWidth = math.max(LEFT_WIDTH, maxBodyWidth - columnsWidth)
  local leftWidth = math.min(desiredLeftWidth, maxLeftWidth)
  local width = leftWidth + columnsWidth

  -- Hide the Loot header until this character has saved Bonus Roll data.
  -- This keeps the first-time empty state visually clean.
  if saved then
    self.header.loot:Show()
  else
    self.header.loot:Hide()
  end

  -- Header: "Difficulty" only exists when there is at least one column
  self.header.difficulty:ClearAllPoints()
  if numColumns > 0 then
    self.header.difficulty:SetPoint("CENTER", self.header, "RIGHT", -(columnsWidth / 2), 0)
    self.header.difficulty:Show()
  else
    self.header.difficulty:Hide()
  end

  for _, row in ipairs(self.rows) do
    row:Hide()
    row.data = nil
  end

  local specOffset = columnsWidth + 12
  local textRight = -(columnsWidth + TEXT_RIGHT_RESERVE)
  local totalHeight = 0
  local rowIndex = 1
  local function renderNextRows()
    if self.renderSerial ~= renderSerial or not self.window:IsVisible()
      or self.character ~= character then return end
    if InCombatLockdown and InCombatLockdown() then
      self:ShowCombatSnapshot()
      return
    end
    local lastIndex = math.min(#rows, rowIndex + RENDER_BATCH_SIZE - 1)
    for index = rowIndex, lastIndex do
      local data = rows[index]
      local row = self.rows[index]
      if not row then
        row = createRow(self.content)
        self.rows[index] = row
      end
      resetRow(row)
      row.data = data
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -totalHeight)
      row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -totalHeight)

      row.specIcon:ClearAllPoints()
      row.specIcon:SetPoint("RIGHT", row, "RIGHT", -specOffset, 0)
      row.count:ClearAllPoints()
      -- The instance roll count occupies the same visual column as the item spec
      -- icons. Center it on the icon instead of aligning its right edge there.
      row.count:SetPoint("CENTER", row.specIcon, "CENTER", 0, 0)
      for cellIndex, cell in ipairs(row.cells) do
        cell:ClearAllPoints()
        local column = columns[cellIndex]
        if column then
          local centerFromRight
          if column.id == "key" then
            -- Dungeon is centered within the raid columns, without widening
            -- the N/H gap or shifting the L/N/H/M positions.
            centerFromRight = columnsWidth / 2
          else
            centerFromRight = (numRaidColumns - cellIndex + 0.5) * DIFFICULTY_COLUMN_WIDTH
          end
          cell:SetPoint("CENTER", row, "RIGHT", -centerFromRight, 0)
          cell:Show()
        else
          cell:Hide()
        end
      end

      if data.type == "header" then
        SetBackgroundColor(row, 0, 0, 0, 0.3)
        row.text:SetFontObject("GameFontNormal")
        row.text:SetPoint("LEFT", row, "LEFT", INDENT.header, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", textRight, 0)
        row.text:SetText(data.collapsible and ((data.collapsed and "+ " or "- ") .. data.text) or data.text)
        if data.sectionKey == "raids" or data.sectionKey == "dungeons" then
          row.count:SetFontObject("GameFontNormal")
          row.count:SetText("Rolls")
        end
        -- Column labels only for columns this section really uses
        local usedHere = {}
        for _, instance in ipairs(data.sectionInstances or {}) do
          for _, boss in ipairs(instance.bosses) do
            for _, entry in ipairs(boss.entries) do
              local column = getEntryColumn(entry, instance.kind)
              if column then usedHere[column] = true end
            end
          end
        end
        for _, column in ipairs(columns) do
          if usedHere[column.id] then
            row.cells[columnIndex[column.id]].text:SetText(column.label)
          end
        end
      elseif data.type == "instance" then
        row.text:SetFontObject("GameFontHighlight_NoShadow")
        row.text:SetPoint("LEFT", row, "LEFT", INDENT.instance, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", textRight, 0)
        local instanceText = data.collapsible and ((data.collapsed and "+ " or "- ") .. data.text) or data.text
        row.text:SetText(NORMAL_FONT_COLOR:WrapTextInColorCode(instanceText))
        row.count:SetText(format("%d", data.count))
      elseif data.type == "boss" then
        row.text:SetFontObject("GameFontHighlight_NoShadow")
        row.text:SetPoint("LEFT", row, "LEFT", INDENT.boss, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", textRight, 0)
        row.text:SetText(data.text)
      elseif data.type == "item" then
        local item = data.item
        local name, icon, color = getItemDisplay(item.itemID)
        row.itemIcon:ClearAllPoints()
        row.itemIcon:SetPoint("LEFT", row, "LEFT", data.indent, 0)
        row.itemIcon:SetTexture(icon)
        row.itemIcon:Show()
        row.text:SetFontObject("GameFontHighlight_NoShadow")
        row.text:SetPoint("LEFT", row.itemIcon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", textRight, 0)
        row.text:SetText(color and color:WrapTextInColorCode(name) or name)

        local _, specIcon = getSpecDisplay(item.specID)
        if specIcon then
          row.specIcon:SetTexture(specIcon)
          row.specIcon:Show()
        end

        for _, entry in ipairs(item.entries) do
          local column = getEntryColumn(entry, data.instance.kind)
          local cell = column and row.cells[columnIndex[column]]
          -- Each item/spec pair occupies its own row. Within that spec, each
          -- populated difficulty cell owns the exact roll variant. Repeated
          -- rolls in the same cell keep the first tooltip (sorted above).
          if cell and not cell.entry then
            cell.entry = entry
            cell:EnableMouse(true)
            -- A dungeon cell is a checkmark, just like a raid difficulty cell.
            -- More than one roll of this item may share this same cell.
            cell.text:SetText(CHECK_MARKUP)
          end
        end
      end
      row:Show()
      totalHeight = totalHeight + ROW_HEIGHT
    end
    rowIndex = lastIndex + 1
    if rowIndex <= #rows then
      C_Timer.After(0, renderNextRows)
      return
    end

  -- Empty / status messages
  if #rows == 0 then
    if saved then
      self.empty:SetText("No rolls used yet.")
    elseif character.GUID == UnitGUID("player") then
      self.empty:SetText("No bonus roll data yet.\n\nMake sure the SimulationCraft addon is enabled.")
    else
      self.empty:SetText("No bonus roll data saved for this character yet.\n\nLog in on this character and open this window to save it.")
    end
    self.empty:SetWidth(width - 40)
    self.empty:Show()
  else
    self.empty:Hide()
  end

  local footer
  if self.updateError then
    footer = RED_FONT_COLOR:WrapTextInColorCode(ERROR_TEXT[self.updateError] or "Could not update.")
  elseif saved and saved.updatedAt then
    -- Having saved Bonus Roll data is proof this character was successfully
    -- checked at least once; do not keep asking the user to log in again.
    footer = format("Updated on: %s", date("%d/%m - %H:%M", saved.updatedAt))
  else
    footer = ""
  end
  self.footer:SetText(footer)

  -- Width follows the measured content; height follows every visible row. No vertical
  -- scroll is used, so a long Bonus Roll history simply produces a taller window.
  local contentHeight = HEADER_HEIGHT + totalHeight + FOOTER_HEIGHT
  if #rows == 0 then contentHeight = MIN_WINDOW_HEIGHT end
  local height = math.max(MIN_WINDOW_HEIGHT, contentHeight)
  self.window:SetBodySize(width, height)
  self.content:SetSize(width, math.max(1, totalHeight))
  self.scroll:SetVerticalScroll(0)
  self.renderedCharacter = character.GUID
  self.renderedEntries = saved and saved.entries
  self.renderedVersion = saved and saved.displayVersion or 0
  self.renderedError = self.updateError
  end
  renderNextRows()
  end

  -- Font measurement can be more expensive than creating a row. Measure in
  -- small batches too, so long histories cannot exhaust a single script frame.
  local nextMeasureIndex = 1
  local requiredWidth = LEFT_WIDTH
  local function measureNextBatch()
    if self.renderSerial ~= renderSerial or not self.window:IsVisible()
      or self.character ~= character then return end
    if InCombatLockdown and InCombatLockdown() then
      self:ShowCombatSnapshot()
      return
    end
    local lastIndex = math.min(#allRows, nextMeasureIndex + 11)
    requiredWidth = calculateLeftWidth(allRows, nextMeasureIndex, lastIndex, requiredWidth)
    nextMeasureIndex = lastIndex + 1
    if nextMeasureIndex <= #allRows then
      C_Timer.After(0, measureNextBatch)
    else
      applyLayout(requiredWidth)
    end
  end
  measureNextBatch()
end

---@return table[]
function Module:GetOrderedDifficulties()
  if not self.orderedDifficulties then
    local list = {}
    for _, difficulty in ipairs(Data:GetRaidDifficulties(true)) do
      table.insert(list, difficulty)
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    self.orderedDifficulties = list
  end
  return self.orderedDifficulties
end

---Open the window for a character.
---@param character AE_Character
function Module:OpenCharacter(character)
  if not character then return end
  self:CreateWindow()
  self.character = character
  self.scroll:SetVerticalScroll(0)
  if self.window:IsVisible() then
    self:Refresh()
  else
    self.window:Show() -- onShow runs Refresh
  end
  self.window:Raise()
end

---Open the window for the character you are logged in on.
function Module:OpenCurrentCharacter()
  local character = Data:GetCharacter()
  if not character then return end
  self:OpenCharacter(character)
end

function Module:OnInitialize()
  local savedSourceID = Data.db and Data.db.global.kithixBonusRollSourceID
  if type(savedSourceID) == "number" then
    learnKithixBonusSource(savedSourceID, true)
  end
  self:RegisterChatCommand("bonus", function()
    Module:OpenCurrentCharacter()
  end)
  addon.Libs.LiqUI.Events:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin)
    if isInitialLogin == true then
      Module:RefreshOnInitialLogin()
    end
  end, true)
  addon.Libs.LiqUI.Events:RegisterEvent("SPELL_CONFIRMATION_PROMPT", function(_, _, spellID)
    Module:SPELL_CONFIRMATION_PROMPT(nil, spellID)
  end, true)
  addon.Libs.LiqUI.Events:RegisterEvent("BONUS_ROLL_RESULT", function(_, _, typeIdentifier, itemLink, quantity, specID)
    Module:BONUS_ROLL_RESULT(nil, typeIdentifier, itemLink, quantity, specID)
  end, true)
  addon.Libs.LiqUI.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    local guid = Module.loginSyncDeferredGUID
    Module.loginSyncDeferredGUID = nil
    if guid and guid == UnitGUID("player") then
      local character = Data:GetCharacter(guid)
      if character and Data:IsMaxLevelCharacter(character) then
        Module:UpdateCharacter(character)
      end
    end
    if Module.combatRefreshPending then
      Module.combatRefreshPending = nil
      if Module.window and Module.window:IsVisible() then Module:Refresh() end
    end
  end, true)
end
