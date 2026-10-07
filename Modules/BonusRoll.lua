---@class AE_Addon
local addon = select(2, ...)

---@class AE_Module_BonusRoll
local Module = addon.Core:NewModule("BonusRoll", "AceConsole-3.0")
addon.Module_BonusRoll = Module

local Data = addon.Data
local LibLiqUI = addon.Libs.LiqUI
local SetBackgroundColor = LibLiqUI.Utils.SetBackgroundColor
local SetHighlightColor = LibLiqUI.Utils.SetHighlightColor

local LEFT_WIDTH = 350 -- width of the Loot side; the window grows by one column per difficulty/keystone used
local MIN_WINDOW_HEIGHT = 130
local MAX_WINDOW_HEIGHT = 520
local HEADER_HEIGHT = 24
local FOOTER_HEIGHT = 20
local ROW_HEIGHT = 22
local DIFFICULTY_COLUMN_WIDTH = 60
local MAX_COLUMNS = 5 -- LFR, Normal, Heroic, Mythic + keystone
local ICON_SIZE = 18

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

  if character then
    local saved = character.bonusRoll
    if not saved then
      saved = {raw = "", entries = {}, updatedAt = time(), exactItems = {}}
      character.bonusRoll = saved
    end
    saved.exactItems = saved.exactItems or {}
    saved.exactItems[getEntryKeyValues(currencyID, sourceID, contextID, keyLevel, itemID, specID)] = itemLink
    saved.updatedAt = time()
    if Data.MarkCharacterSyncChanged then
      Data:MarkCharacterSyncChanged(character)
    end
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

---Fetch fresh data for the logged in character and save it if it changed.
---@param character AE_Character
---@return string? err
function Module:UpdateCharacter(character)
  if not Data:IsMaxLevelCharacter(character) then return nil end
  local raw, err = fetchRaw()
  if raw == nil then
    return err
  end
  local saved = character.bonusRoll
  if saved and saved.raw == raw and type(saved.entries) == "table" then
    -- A successful check is still an update even when the roll history itself
    -- did not change. Keep the footer meaningful after the automatic login check.
    saved.updatedAt = time()
    if Data.MarkCharacterSyncChanged then
      Data:MarkCharacterSyncChanged(character)
    end
    return nil
  end
  character.bonusRoll = {
    raw = raw,
    entries = parseRaw(raw),
    updatedAt = time(),
    exactItems = saved and saved.exactItems or {},
  }
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

    local err = self:UpdateCharacter(character)
    if not err then
      if self.window and self.window:IsVisible() and self.character and self.character.GUID == guid then
        self:Render()
      end
      return
    end

    attempt = attempt + 1
    local delay = retryDelays[attempt]
    if delay then
      C_Timer.After(delay, tryRefresh)
    end
  end

  tryRefresh()
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
  for _, difficulty in ipairs(Data.raidDifficulties) do
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
      local dataInstance = findByJournalInstance(isRaid and Data.raids or Data.dungeons, source.journalInstanceID)
      section = isRaid and sections.raids or sections.dungeons
      local instanceName = dataInstance and dataInstance.name or ("Instance " .. source.journalInstanceID)
      local instanceOrder = dataInstance and dataInstance.order or 0
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
        for _, entry in ipairs(boss.entries) do
          local item = itemLookup[entry.itemID]
          if not item then
            item = {itemID = entry.itemID, entries = {}}
            itemLookup[entry.itemID] = item
            table.insert(boss.items, item)
          end
          table.insert(item.entries, entry)
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
    local perLevel, levels = {}, {}
    for _, boss in ipairs(instance.bosses) do
      for _, entry in ipairs(boss.entries) do
        if not perLevel[entry.keyLevel] then
          perLevel[entry.keyLevel] = 0
          table.insert(levels, entry.keyLevel)
        end
        perLevel[entry.keyLevel] = perLevel[entry.keyLevel] + 1
      end
    end
    table.sort(levels, function(a, b) return a > b end)
    table.insert(lines, {format("Rolls used: %d", instance.count), 1, 1, 1})
    for _, level in ipairs(levels) do
      table.insert(lines, {format("+%d: %d", level, perLevel[level]), 0.8, 0.8, 0.8})
    end
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
    for _, difficulty in ipairs(Data.raidDifficulties) do
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

    local sectionCollapsible = sectionKey == "raids"
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
      local instanceCollapsible = sectionKey == "raids" and instance.kind == "raid"
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

---@param itemID number
---@return string name, string? icon, table? color
local function getItemDisplay(itemID)
  local name = C_Item.GetItemNameByID(itemID)
  local icon = select(5, C_Item.GetItemInfoInstant(itemID))
  local quality = C_Item.GetItemQualityByID(itemID)
  local color = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
  if not name then
    -- Not cached yet: ask for it and redraw when it arrives.
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
      Module:ScheduleRender()
    end)
    name = "Item " .. itemID
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

---@param row Button
local function showInstanceTooltip(row)
  local instance = row.data.instance
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(instance.name, 1, 1, 1)
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
  self.collapsedSections = {}
  self.collapsedInstances = {}
end

---@param data table
function Module:ToggleCollapsedRow(data)
  if data.type == "header" and data.sectionKey == "raids" then
    self.collapsedSections = self.collapsedSections or {}
    self.collapsedSections.raids = not self.collapsedSections.raids
  elseif data.type == "instance" and data.instanceKey and data.instance and data.instance.kind == "raid" then
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
      Module:ResetCollapsedRows()
      Module:Refresh()
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

  -- Scrolling list
  self.scroll = CreateFrame("ScrollFrame", "$parentScroll", body)
  self.scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  self.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, FOOTER_HEIGHT)
  self.content = CreateFrame("Frame", "$parentContent", self.scroll)
  self.content:SetSize(LEFT_WIDTH, 1)
  self.scroll:SetScrollChild(self.content)
  self.scroll:EnableMouseWheel(true)
  self.scroll:SetScript("OnMouseWheel", function(scroll, delta)
    local maxScroll = math.max(0, self.content:GetHeight() - scroll:GetHeight())
    local target = scroll:GetVerticalScroll() - delta * ROW_HEIGHT * 3
    scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, target)))
  end)

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
}

---Re-check the data (current character only) and redraw.
function Module:Refresh()
  if not self.window or not self.character then return end
  local character = self.character
  self.updateError = nil
  if Data:IsMaxLevelCharacter(character) and character.GUID == UnitGUID("player") then
    self.updateError = self:UpdateCharacter(character)
  end
  self:Render()
end

function Module:ScheduleRender()
  if self.renderPending then return end
  self.renderPending = true
  C_Timer.After(0.1, function()
    self.renderPending = false
    if self.window and self.window:IsVisible() then self:Render() end
  end)
end

---Which column a roll belongs to: "key" (keystone level) or a raid difficultyID.
---@param entry table
---@param instanceKind string?
---@return "key"|number|nil
local function getEntryColumn(entry, instanceKind)
  local isKeystone = instanceKind == "dungeon" or Data.bonusRollKeystoneContexts[entry.contextID]
  if isKeystone then
    if entry.keyLevel and entry.keyLevel > 0 then return "key" end
    return nil
  end
  return getRaidDifficultyID(entry)
end

---Only the difficulties that actually had a roll get a column, plus "+#" if any keystone roll exists.
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
    table.insert(columns, {id = "key", label = "+#"})
    columnIndex.key = #columns
  end
  return columns, columnIndex
end

function Module:Render()
  if not self.window or not self.window:IsVisible() or not self.character then return end
  local character = self.character
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
  local columnsWidth = numColumns * DIFFICULTY_COLUMN_WIDTH
  local width = LEFT_WIDTH + columnsWidth

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
  local textRight = -(specOffset + ICON_SIZE + 6)
  local totalHeight = 0
  for index, data in ipairs(rows) do
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
      cell:SetPoint("CENTER", row, "RIGHT", -((numColumns - cellIndex) * DIFFICULTY_COLUMN_WIDTH + DIFFICULTY_COLUMN_WIDTH / 2), 0)
      cell:Show()
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

      local sharedSpecID = item.entries[1] and item.entries[1].specID or 0
      for entryIndex = 2, #item.entries do
        if item.entries[entryIndex].specID ~= sharedSpecID then
          sharedSpecID = 0
          break
        end
      end
      local _, specIcon = getSpecDisplay(sharedSpecID)
      if specIcon then
        row.specIcon:SetTexture(specIcon)
        row.specIcon:Show()
      end

      for _, entry in ipairs(item.entries) do
        local column = getEntryColumn(entry, data.instance.kind)
        local cell = column and row.cells[columnIndex[column]]
        -- One item occupies one row. Each populated difficulty cell owns the
        -- exact roll variant for that difficulty. If old data somehow has more
        -- than one entry in one cell, keep the first (the list is already sorted).
        if cell and not cell.entry then
          cell.entry = entry
          cell:EnableMouse(true)
          if column == "key" then
            local levelText = "+" .. entry.keyLevel
            local levelColor = C_ChallengeMode and C_ChallengeMode.GetKeystoneLevelRarityColor and C_ChallengeMode.GetKeystoneLevelRarityColor(entry.keyLevel)
            cell.text:SetText(levelColor and levelColor:WrapTextInColorCode(levelText) or levelText)
          else
            cell.text:SetText(CHECK_MARKUP)
          end
        end
      end
    end
    row:Show()
    totalHeight = totalHeight + ROW_HEIGHT
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

  -- Window size follows the content: wider with each column, taller with each row (then it scrolls).
  local contentHeight = HEADER_HEIGHT + totalHeight + FOOTER_HEIGHT
  if #rows == 0 then contentHeight = MIN_WINDOW_HEIGHT end
  local height = math.max(MIN_WINDOW_HEIGHT, math.min(MAX_WINDOW_HEIGHT, contentHeight))
  self.window:SetBodySize(width, height)
  self.content:SetSize(width, math.max(1, totalHeight))
  local visibleHeight = height - HEADER_HEIGHT - FOOTER_HEIGHT
  local maxScroll = math.max(0, totalHeight - visibleHeight)
  if self.scroll:GetVerticalScroll() > maxScroll then
    self.scroll:SetVerticalScroll(maxScroll)
  end
end

---@return table[]
function Module:GetOrderedDifficulties()
  if not self.orderedDifficulties then
    local list = {}
    for _, difficulty in ipairs(Data.raidDifficulties) do
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
  self:RegisterChatCommand("bonus", function()
    Module:OpenCurrentCharacter()
  end)
  addon.Events:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin)
    if isInitialLogin == true then
      Module:RefreshOnInitialLogin()
    end
  end, true)
  addon.Events:RegisterEvent("SPELL_CONFIRMATION_PROMPT", function(_, _, spellID)
    Module:SPELL_CONFIRMATION_PROMPT(nil, spellID)
  end, true)
  addon.Events:RegisterEvent("BONUS_ROLL_RESULT", function(_, _, typeIdentifier, itemLink, quantity, specID)
    Module:BONUS_ROLL_RESULT(nil, typeIdentifier, itemLink, quantity, specID)
  end, true)
end
