---@class AE_Addon
local addon = select(2, ...)

---@class AE_Module_Equipment
local Module = addon.Core:NewModule("Equipment", "AceConsole-3.0", "AceTimer-3.0")
addon.Module_Equipment = Module

local Data = addon.Data
local Helpers = addon.Helpers
local LibLiqUI = addon.Libs.LiqUI
local TableCount = LibLiqUI.Utils.TableCount
local TableForEach = LibLiqUI.Utils.TableForEach

local Slots = {
  [1] = {id = 1, side = "LEFT", name = "Head", canEnchant = true, canSocket = true},
  [2] = {id = 2, side = "LEFT", name = "Neck", canEnchant = false, canSocket = false},
  [3] = {id = 3, side = "LEFT", name = "Shoulder", canEnchant = true, canSocket = false},
  [4] = {id = 4, side = "LEFT", name = "Shirt", canEnchant = false, canSocket = false},
  [5] = {id = 5, side = "LEFT", name = "Chest", canEnchant = true, canSocket = false},
  [6] = {id = 6, side = "RIGHT", name = "Waist", canEnchant = false, canSocket = true},
  [7] = {id = 7, side = "RIGHT", name = "Legs", canEnchant = true, canSocket = false},
  [8] = {id = 8, side = "RIGHT", name = "Feet", canEnchant = true, canSocket = false},
  [9] = {id = 9, side = "LEFT", name = "Wrist", canEnchant = false, canSocket = true},
  [10] = {id = 10, side = "RIGHT", name = "Hands", canEnchant = false, canSocket = false},
  [11] = {id = 11, side = "RIGHT", name = "Finger0", canEnchant = true, canSocket = false},
  [12] = {id = 12, side = "RIGHT", name = "Finger1", canEnchant = true, canSocket = false},
  [13] = {id = 13, side = "RIGHT", name = "Trinket0", canEnchant = false, canSocket = false},
  [14] = {id = 14, side = "RIGHT", name = "Trinket1", canEnchant = false, canSocket = false},
  [15] = {id = 15, side = "LEFT", name = "Back", canEnchant = false, canSocket = false},
  [16] = {id = 16, side = "RIGHT", name = "MainHand", canEnchant = true, canSocket = false},
  [17] = {id = 17, side = "LEFT", name = "SecondaryHand", canEnchant = false, canSocket = false},
  --    [18] = {id = 18, side = "LEFT", name = "Ranged", canEnchant = false},
  --    [19] = {id = 19, side = "LEFT", name = "Tabard", canEnchant = false}
}

local EQUIPMENT_HEADER_HEIGHT = 30
local CRAFTED_QUALITY_MAX = 5

-- Equipment columns should follow the content that is actually displayed instead
-- of reserving large fixed widths. Text-bearing columns are recalculated for every
-- character render so long values expand the table rather than being clipped, while
-- shorter values reclaim unused space.
local equipmentColumnMeasureFont

---@param text any
---@param fontObject string
---@return number
local function measureEquipmentColumnText(text, fontObject)
  if text == nil or text == "" then
    return 0
  end

  if not equipmentColumnMeasureFont then
    equipmentColumnMeasureFont = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    equipmentColumnMeasureFont:SetWordWrap(false)
  end

  equipmentColumnMeasureFont:SetFontObject(fontObject)
  equipmentColumnMeasureFont:SetText(tostring(text))
  return math.ceil(equipmentColumnMeasureFont:GetStringWidth() or 0)
end

---@param tableFrame table
---@param rows LiqUI_TableData
local function sizeEquipmentColumnsToContent(tableFrame, rows)
  if not tableFrame or not tableFrame.options or not tableFrame.options.columns then
    return
  end

  local padding = (LibLiqUI.Constants and LibLiqUI.Constants.layout and LibLiqUI.Constants.layout.sizes.padding) or 8
  local horizontalPadding = (padding * 2) + 2
  local columns = tableFrame.options.columns

  local function fitColumn(columnIndex)
    local column = columns[columnIndex]
    if not column then return end

    local contentWidth = measureEquipmentColumnText(column.headerText or "", "GameFontNormalSmall")
    for _, row in ipairs(rows) do
      local cell = row.data and row.data[columnIndex]
      if cell and cell.data ~= nil then
        local measuredWidth
        if columnIndex == 2 and row.item then
          -- Measure the visible item name directly instead of the hyperlink payload,
          -- then reserve room for the leading item icon. This avoids both clipping
          -- and accidental over-sizing from hidden link metadata.
          local itemName = row.item.itemLink and string.match(row.item.itemLink, "%[(.-)%]")
          if not itemName then
            local itemID = row.item.itemLink and C_Item.GetItemIDForItemInfo(row.item.itemLink)
            itemName = itemID and C_Item.GetItemNameByID(itemID) or tostring(cell.data)
          end
          measuredWidth = measureEquipmentColumnText("[" .. itemName .. "]", "GameFontHighlightSmall") + 20
        else
          measuredWidth = measureEquipmentColumnText(cell.data, "GameFontHighlightSmall")
        end
        contentWidth = math.max(contentWidth, measuredWidth)
      end
    end

    column.width = math.ceil(contentWidth + horizontalPadding)
  end

  -- Fit every text-bearing column to the current character. Embellishment stays
  -- fixed so its icon remains centered in a predictable compact cell.
  fitColumn(1) -- Slot
  fitColumn(2) -- Item
  fitColumn(3) -- iLevel
  fitColumn(4) -- Upgrade Level
  fitColumn(6) -- Enchant
  fitColumn(7) -- Gems
end

---@param itemLink string?
---@return number
local function getItemLinkEnchantID(itemLink)
  if not itemLink then return 0 end
  local itemPayload = string.match(itemLink, "item:([%-?%d:]+)")
  if not itemPayload then return 0 end
  local itemPayloadSplit = {strsplit(":", itemPayload)}
  return tonumber(itemPayloadSplit[2]) or 0
end

---@param lineText string
---@return string, string
local function formatEnchantLine(lineText)
  local enchantText = lineText
  local enchantTooltip = lineText

  local enchantValue = string.match(lineText, ENCHANTED_TOOLTIP_LINE:gsub("%%s", "(.*)"))
  if enchantValue ~= nil then
    enchantTooltip = enchantValue
    enchantText = enchantValue

    local enchantName, enchantAtlas = string.match(enchantValue, "(.*)|A:(.*):20:20|a")
    if enchantName ~= nil then
      enchantText = "|A:" .. enchantAtlas .. ":20:20|a" .. enchantName
      local enchantNameSplit = {strsplit("-", enchantName)}
      if enchantNameSplit[2] ~= nil then
        enchantText = "|A:" .. enchantAtlas .. ":20:20|a" .. strtrim(enchantNameSplit[2])
      end
    end
  end

  return enchantText, enchantTooltip
end

---@param itemLink string
---@param socketIndex number
---@return string?
local function getGemCraftingQualityMarkup(itemLink, socketIndex)
  local _, gemLink = C_Item.GetItemGem(itemLink, socketIndex)
  local gemID = C_Item.GetItemGemID and C_Item.GetItemGemID(itemLink, socketIndex) or nil

  if not gemLink and gemID then
    C_Item.RequestLoadItemDataByID(gemID)
  end

  -- Crafted gem links carry their profession-quality atlas directly in the
  -- visible item name. Reading it from the link keeps this locale-independent
  -- and works for Midnight's two-tier quality icons as well as older tiers.
  if gemLink then
    local qualityMarkup = string.match(gemLink, "(|A:Professions%-ChatIcon%-Quality[^|]*|a)")
    if qualityMarkup then
      return qualityMarkup
    end

    -- Some item links may omit the quality atlas until sparse item data is
    -- hydrated. Fall back to the gem's own tooltip quality line when available.
    local gemTooltipData = C_TooltipInfo.GetHyperlink(gemLink)
    for _, gemLine in pairs((gemTooltipData and gemTooltipData.lines) or {}) do
      if gemLine.type == Enum.TooltipDataLineType.ProfessionCraftingQuality and gemLine.leftText then
        qualityMarkup = string.match(gemLine.leftText, "(|A:[^|]-Quality[^|]*|a)")
        if qualityMarkup then
          return qualityMarkup
        end
      end
    end
  end

  return nil
end

---@param itemLink string
---@return number[]
local function getItemLinkBonusIDs(itemLink)
  ---@type number[]
  local bonusIDs = {}
  local itemPayload = string.match(itemLink, "item:([%-?%d:]+)")
  if not itemPayload then
    return bonusIDs
  end
  local itemPayloadSplit = {strsplit(":", itemPayload)}
  local numBonuses = tonumber(itemPayloadSplit[13])
  if numBonuses == nil or numBonuses < 1 then
    return bonusIDs
  end
  for bonusIndex = 14, 13 + numBonuses do
    local bonusId = tonumber(itemPayloadSplit[bonusIndex])
    if bonusId ~= nil then
      table.insert(bonusIDs, bonusId)
    end
  end
  return bonusIDs
end

---@param text string
---@param complete boolean
---@param muted boolean
---@return string
local function colorUpgradeLevelText(text, complete, muted)
  if muted then
    return DISABLED_FONT_COLOR:WrapTextInColorCode(text)
  end
  if complete then
    return GREEN_FONT_COLOR:WrapTextInColorCode(text)
  end
  return text
end

-- Match BetterUpgradeTooltip's Midnight upgrade-track colors while keeping
-- the numeric rank separate: incomplete ranks stay white and the max rank is green.
local UPGRADE_TRACK_COLORS = {
  Adventurer = WHITE_FONT_COLOR,
  Veteran = UNCOMMON_GREEN_COLOR,
  Champion = RARE_BLUE_COLOR,
  Hero = ITEM_EPIC_COLOR,
  Myth = ITEM_LEGENDARY_COLOR,
}

-- Midnight Season 2 crafted gear uses five crafted-quality ranks per upgrade
-- track. Boundary item levels overlap between tracks, so crafted quality is
-- used together with item level to distinguish cases such as Hero 5/5 (318)
-- from Myth 1/5 (also 318).
local CRAFTED_UPGRADE_TRACKS = {
  {name = "Adventurer", itemLevels = {266, 269, 272, 275, 279}},
  {name = "Veteran",    itemLevels = {279, 282, 285, 288, 292}},
  {name = "Champion",   itemLevels = {292, 295, 298, 302, 305}},
  {name = "Hero",       itemLevels = {305, 308, 311, 315, 318}},
  {name = "Myth",       itemLevels = {318, 321, 324, 328, 331}},
}

---@param itemLevel number?
---@param craftedQuality number?
---@return string?
local function resolveCraftedUpgradeTrack(itemLevel, craftedQuality)
  if not itemLevel or not craftedQuality or craftedQuality < 1 or craftedQuality > CRAFTED_QUALITY_MAX then
    return nil
  end

  local roundedItemLevel = floor(itemLevel + 0.5)

  -- Prefer the exact quality + item-level pair so overlapping boundary levels
  -- are assigned to the correct track.
  for _, track in ipairs(CRAFTED_UPGRADE_TRACKS) do
    if track.itemLevels[craftedQuality] == roundedItemLevel then
      return track.name
    end
  end

  -- Keep a range fallback for crafted links whose item level is valid for the
  -- track but does not exactly match one of the expected five rank values.
  if roundedItemLevel >= 318 and roundedItemLevel <= 331 then
    return "Myth"
  elseif roundedItemLevel >= 305 and roundedItemLevel < 318 then
    return "Hero"
  elseif roundedItemLevel >= 292 and roundedItemLevel < 305 then
    return "Champion"
  elseif roundedItemLevel >= 279 and roundedItemLevel < 292 then
    return "Veteran"
  elseif roundedItemLevel >= 266 and roundedItemLevel < 279 then
    return "Adventurer"
  end

  return nil
end

---@param trackName string
---@param level number
---@param maxLevel number
---@param muted boolean
---@param crafted boolean?
---@return string
local function formatUpgradeTrackLabel(trackName, level, maxLevel, muted, crafted)
  local displayTrackName = crafted and format("%s Crafted", trackName) or trackName
  local isMythBonusRank = not crafted and trackName == "Myth" and level == 9 and maxLevel == 6
  local rankText = format("%d/%d%s", level, maxLevel, isMythBonusRank and "*" or "")

  if muted then
    return DISABLED_FONT_COLOR:WrapTextInColorCode(format("%s %s", displayTrackName, rankText))
  end

  local trackColor = UPGRADE_TRACK_COLORS[trackName]
  local coloredTrack = trackColor and trackColor:WrapTextInColorCode(displayTrackName) or displayTrackName
  local coloredRank = (level == maxLevel or isMythBonusRank) and GREEN_FONT_COLOR:WrapTextInColorCode(rankText) or rankText

  return format("%s %s", coloredTrack, coloredRank)
end

---@param seasonID number?
---@return boolean
local function isUpgradeFromPreviousSeason(seasonID)
  if not seasonID or seasonID < 1 then
    return false
  end
  local currentSeason = Data:GetCurrentSeason()
  if not currentSeason or currentSeason < 1 then
    return false
  end
  return seasonID ~= currentSeason
end

---@param item AE_Equipment
---@return string, string, boolean
local function resolveEquipmentUpgradeLevel(item)
  ---@type string[]
  local displayParts = {}
  ---@type string[]
  local sortParts = {}
  local hasUpgradeTrack = false

  local function appendLabel(text, complete, muted)
    table.insert(sortParts, text)
    table.insert(displayParts, colorUpgradeLevelText(text, complete, muted))
  end

  local bonusIDs = getItemLinkBonusIDs(item.itemLink)

  local craftedQuality = C_TradeSkillUI.GetItemCraftedQualityByItemInfo(item.itemLink)
  if not craftedQuality then
    TableForEach(bonusIDs, function(bonusId)
      local quality = Data.craftedQualityBonusIDs[bonusId]
      if quality then
        craftedQuality = quality
      end
    end)
  end

  local craftedSeason
  if craftedQuality then
    TableForEach(bonusIDs, function(bonusId)
      local seasonID = Data.craftedSeasonBonusIDs[bonusId]
      if seasonID and (not craftedSeason or seasonID > craftedSeason) then
        craftedSeason = seasonID
      end
    end)
  end

  local craftedTrack = resolveCraftedUpgradeTrack(item.itemLevel, craftedQuality)
  if craftedTrack then
    hasUpgradeTrack = true
    local muted = isUpgradeFromPreviousSeason(craftedSeason)
    table.insert(sortParts, format("%s Crafted %d/%d", craftedTrack, craftedQuality, CRAFTED_QUALITY_MAX))
    table.insert(displayParts, formatUpgradeTrackLabel(craftedTrack, craftedQuality, CRAFTED_QUALITY_MAX, muted, true))
  elseif not craftedQuality then
    local upgradeLevel = item.itemUpgradeLevel or 0
    local upgradeMax = item.itemUpgradeMax or 0
    if item.itemUpgradeTrack and item.itemUpgradeTrack ~= "" and upgradeLevel > 0 and upgradeMax > 0 then
      hasUpgradeTrack = true
      local muted = item.itemUpgradeColor ~= nil and item.itemUpgradeColor == DISABLED_FONT_COLOR:GenerateHexColor()
      table.insert(sortParts, format("%s %d/%d", item.itemUpgradeTrack, upgradeLevel, upgradeMax))
      table.insert(displayParts, formatUpgradeTrackLabel(item.itemUpgradeTrack, upgradeLevel, upgradeMax, muted))
    end

    if #displayParts == 0 then
      local fallbackTrack
      local fallbackLevel = 0
      local fallbackMax = 0
      TableForEach(bonusIDs, function(bonusId)
        TableForEach(Data.upgradeTracks, function(season)
          TableForEach(season.tracks, function(track)
            TableForEach(track.bonusIDs, function(id, trackLevel)
              if id == bonusId then
                fallbackTrack = track.name
                fallbackLevel = trackLevel
                fallbackMax = #track.bonusIDs
              end
            end)
          end)
        end)
      end)
      if fallbackTrack then
        hasUpgradeTrack = true
        table.insert(sortParts, format("%s %d/%d", fallbackTrack, fallbackLevel, fallbackMax))
        table.insert(displayParts, formatUpgradeTrackLabel(fallbackTrack, fallbackLevel, fallbackMax, true))
      end
    end
  end

  TableForEach(bonusIDs, function(bonusId)
    local label = Data.upgradeBonusLabels[bonusId]
    if label then
      appendLabel(label.name, true, isUpgradeFromPreviousSeason(label.seasonID))
    end
  end)

  -- Preserve the legacy crafted label for crafted items outside the Midnight
  -- Season 2 item-level table instead of assigning an incorrect track.
  if craftedQuality and not craftedTrack then
    appendLabel(format("Crafted %d/%d", craftedQuality, CRAFTED_QUALITY_MAX), craftedQuality == CRAFTED_QUALITY_MAX, isUpgradeFromPreviousSeason(craftedSeason))
  end

  return table.concat(displayParts, " / "), table.concat(sortParts, " / "), hasUpgradeTrack
end

---@param item AE_Equipment
---@return string
local function equipmentItemSortName(item)
  local itemID = C_Item.GetItemIDForItemInfo(item.itemLink)
  if itemID then
    local name = C_Item.GetItemNameByID(itemID)
    if name then
      return name
    end
  end
  return item.itemLink or ""
end

---@param rowA AE_EquipmentTableRow
---@param rowB AE_EquipmentTableRow
---@return boolean
local function compareEquipmentTiebreak(rowA, rowB)
  local itemA = rowA.item
  local itemB = rowB.item
  if not itemA or not itemB then
    return false
  end
  if itemA.itemSlotID ~= itemB.itemSlotID then
    return itemA.itemSlotID < itemB.itemSlotID
  end
  local itemIDA = C_Item.GetItemIDForItemInfo(itemA.itemLink) or 0
  local itemIDB = C_Item.GetItemIDForItemInfo(itemB.itemLink) or 0
  return itemIDA < itemIDB
end

---@param rowA AE_EquipmentTableRow
---@param rowB AE_EquipmentTableRow
---@param primaryA number|string
---@param primaryB number|string
---@return boolean
local function compareEquipmentPrimaryThenSlot(rowA, rowB, primaryA, primaryB)
  if primaryA ~= primaryB then
    return primaryA < primaryB
  end
  return compareEquipmentTiebreak(rowA, rowB)
end

---@param rowA AE_EquipmentTableRow
---@param rowB AE_EquipmentTableRow
---@return boolean
local function compareEquipmentSlotColumn(rowA, rowB)
  local itemA = rowA.item
  local itemB = rowB.item
  if not itemA or not itemB then
    return false
  end
  return compareEquipmentPrimaryThenSlot(rowA, rowB, itemA.itemSlotID, itemB.itemSlotID)
end

---@param rowA AE_EquipmentTableRow
---@param rowB AE_EquipmentTableRow
---@return boolean
local function compareEquipmentItemColumn(rowA, rowB)
  local itemA = rowA.item
  local itemB = rowB.item
  if not itemA or not itemB then
    return false
  end
  local nameA = equipmentItemSortName(itemA)
  local nameB = equipmentItemSortName(itemB)
  if nameA ~= nameB then
    return nameA < nameB
  end
  return compareEquipmentTiebreak(rowA, rowB)
end

---@param rowA AE_EquipmentTableRow
---@param rowB AE_EquipmentTableRow
---@return boolean
local function compareEquipmentILvlColumn(rowA, rowB)
  local itemA = rowA.item
  local itemB = rowB.item
  if not itemA or not itemB then
    return false
  end
  return compareEquipmentPrimaryThenSlot(rowA, rowB, itemA.itemLevel, itemB.itemLevel)
end

---@param rowA AE_EquipmentTableRow
---@param rowB AE_EquipmentTableRow
---@return boolean
local function compareEquipmentUpgradeColumn(rowA, rowB)
  return compareEquipmentPrimaryThenSlot(rowA, rowB, rowA.upgradeSort, rowB.upgradeSort)
end

---@param rowA AE_EquipmentTableRow
---@param rowB AE_EquipmentTableRow
---@return boolean
local function compareEquipmentEmbellishmentColumn(rowA, rowB)
  return compareEquipmentPrimaryThenSlot(rowA, rowB, rowA.embellishmentSort, rowB.embellishmentSort)
end

---@param rowA AE_EquipmentTableRow
---@param rowB AE_EquipmentTableRow
---@return boolean
local function compareEquipmentEnchantColumn(rowA, rowB)
  local itemA = rowA.item
  local itemB = rowB.item
  if not itemA or not itemB then
    return false
  end
  return compareEquipmentPrimaryThenSlot(rowA, rowB, rowA.enchantSort, rowB.enchantSort)
end

---@param rowA AE_EquipmentTableRow
---@param rowB AE_EquipmentTableRow
---@return boolean
local function compareEquipmentGemsColumn(rowA, rowB)
  local itemA = rowA.item
  local itemB = rowB.item
  if not itemA or not itemB then
    return false
  end
  return compareEquipmentPrimaryThenSlot(rowA, rowB, rowA.gemCount, rowB.gemCount)
end

function Module:OnInitialize()
  self:Render()
end

local EQUIPMENT_REFRESH_RETRY_DELAYS = {0.10, 0.35, 1.00}

function Module:RefreshEquipment()
  Data:UpdateEquipment()
  self:Render()
end

function Module:QueueEquipmentRefresh()
  -- Equipment/inventory events can fire before Blizzard has refreshed the item
  -- tooltip data that contains permanent enchant information. Refresh once
  -- immediately, then retry quickly so an already-active enchant does not sit
  -- on "Missing" until another inventory event happens several seconds later.
  self:RefreshEquipment()

  if self.equipmentRefreshTimers then
    for _, timer in ipairs(self.equipmentRefreshTimers) do
      self:CancelTimer(timer, true)
    end
  end

  self.equipmentRefreshTimers = {}
  for _, delay in ipairs(EQUIPMENT_REFRESH_RETRY_DELAYS) do
    local timer = self:ScheduleTimer(function()
      self:RefreshEquipment()
    end, delay)
    table.insert(self.equipmentRefreshTimers, timer)
  end
end

function Module:OnEnable()
  addon.Events:RegisterEvent(
    {
      "PLAYER_EQUIPMENT_CHANGED",
      "UNIT_INVENTORY_CHANGED",
    }, function(unitOrSlot)
      -- UNIT_INVENTORY_CHANGED passes a unit token, while
      -- PLAYER_EQUIPMENT_CHANGED passes the numeric equipment slot first.
      if type(unitOrSlot) == "string" and unitOrSlot ~= "player" then return end
      self:QueueEquipmentRefresh()
    end
  )

  -- Hyperlink tooltips for offline characters may become available shortly
  -- after item data finishes loading. Re-render the open equipment window as
  -- soon as that happens instead of waiting for another unrelated UI update.
  addon.Events:RegisterEvent("ITEM_DATA_LOAD_RESULT", function()
    if self.window and self.window:IsVisible() then
      self:Render()
    end
  end)
end

---Opens a new equipment window
---@param character AE_Character
function Module:OpenCharacter(character)
  if not self.window then return end
  if self.equipmentCharacter and self.equipmentCharacter == character and self.window:IsVisible() then
    self.window:Hide()
    return
  end
  self.equipmentCharacter = character
  self:Render()
  self.window:Show()
  self.window:Raise()
end

function Module:Render()
  local tableWidth = 835
  local rowHeight = 22

  if not self.window then
    local windows = Data.db.global.liqui.windows
    local tables = Data.db.global.liqui.tables
    self.window = LibLiqUI:NewElement("Window", {
      name = addon.name .. "Equipment",
      storage = windows.Equipment,
      title = "Character",
      onShow = function()
        Module:Render()
      end,
    })
    self.dataTable = LibLiqUI:NewElement("Table", {
      name = addon.name .. "Equipment",
      storage = tables.Equipment,
      header = {enabled = true, sticky = true, height = EQUIPMENT_HEADER_HEIGHT},
      columns = {
        {id = "slot", headerText = "Slot", width = 100, sorting = {enabled = true, compare = compareEquipmentSlotColumn}},
        {id = "item", headerText = "Item", width = 200, sorting = {enabled = true, compare = compareEquipmentItemColumn}},
        {id = "ilevel", headerText = "iLevel", width = 80, align = "CENTER", sorting = {enabled = true, compare = compareEquipmentILvlColumn}},
        {id = "upgrade", headerText = "Upgrade Level", width = 105, sorting = {enabled = true, compare = compareEquipmentUpgradeColumn}},
        {id = "embellishment", headerText = "Embellishment", width = 90, align = "CENTER", sorting = {enabled = true, compare = compareEquipmentEmbellishmentColumn}},
        {id = "enchant", headerText = "Enchant", width = 180, sorting = {enabled = true, compare = compareEquipmentEnchantColumn}},
        {id = "gems", headerText = "Gems", width = 80, sorting = {enabled = true, compare = compareEquipmentGemsColumn}},
      },
      rowStyle = {height = rowHeight, striped = true},
      sorting = {
        enabled = true,
        defaultOrder = "asc",
        defaultCompare = compareEquipmentSlotColumn,
      },
    })
    self.dataTable:SetParent(self.window.body)
    self.dataTable:SetPoint("TOPLEFT", self.window.body, "TOPLEFT", 0, 0)
    self.dataTable:SetPoint("BOTTOMRIGHT", self.window.body, "BOTTOMRIGHT", 0, 0)
  end

  if not self.window:IsVisible() then
    return
  end

  local character = self.equipmentCharacter
  if not character or type(character.equipment) ~= "table" then
    self.window:Hide()
    return
  end

  ---@type LiqUI_TableData
  local rows = {}

  local isCurrentCharacter = character.GUID == UnitGUID("player")
  local tooltipDataBySlot = {}
  local embellishmentInfoBySlot = {}
  local equippedEmbellishmentCount = 0

  -- Resolve embellishments for the whole equipped set first. The Missing state
  -- is character-wide: crafted slots only need a warning while fewer than two
  -- real (Unique-Equipped) embellishments are equipped. Lucky Keychain has no
  -- Embellished (2) category, so it is intentionally treated like an empty slot.
  TableForEach(character.equipment, function(item)
    local tooltipData
    if isCurrentCharacter then
      tooltipData = C_TooltipInfo.GetInventoryItem("player", item.itemSlotID)
    end
    if tooltipData == nil then
      tooltipData = C_TooltipInfo.GetHyperlink(item.itemLink)
    end

    if tooltipData == nil or tooltipData.lines == nil or next(tooltipData.lines) == nil then
      local itemID = C_Item.GetItemIDForItemInfo(item.itemLink)
      if itemID then
        C_Item.RequestLoadItemDataByID(itemID)
      end
    end

    tooltipDataBySlot[item.itemSlotID] = tooltipData
    local embellishmentInfo = Data:GetEquipmentEmbellishmentInfo(item.itemLink, tooltipData, item)
    embellishmentInfoBySlot[item.itemSlotID] = embellishmentInfo
    if embellishmentInfo.hasEmbellishment then
      equippedEmbellishmentCount = equippedEmbellishmentCount + 1
    end
  end)

  -- The character-wide missing count is independent of whether another crafted
  -- host item currently exists. A character with 0/2 or 1/2 real embellishments
  -- is still missing two or one embellishment respectively. Lucky Keychain is
  -- intentionally excluded by GetEquipmentEmbellishmentInfo and therefore does
  -- not reduce this count.
  local missingEmbellishmentCount = math.max(0, 2 - equippedEmbellishmentCount)

  -- When there are no real embellishments equipped, the title communicates the
  -- 0/2 state and the per-item Embellishment column is unnecessary. Keep the
  -- column available as soon as at least one tracked embellishment is equipped.
  if self.dataTable.db and self.dataTable.db.hiddenColumns then
    self.dataTable.db.hiddenColumns.embellishment = equippedEmbellishmentCount == 0 and true or nil
  end

  TableForEach(character.equipment, function(item)
    local itemID = C_Item.GetItemIDForItemInfo(item.itemLink)

    local upgradeLevel, upgradeSort, hasUpgradeTrack = resolveEquipmentUpgradeLevel(item)

    local enchantText, enchantTooltip, enchantColor = "", "", GREEN_FONT_COLOR
    ---@type string[]
    local socketTexts = {}
    ---@type string[]
    local socketTooltipLines = {}
    local hasEmptySocket = false

    -- Reuse the tooltip snapshot from the embellishment pre-pass so all columns
    -- are rendered from the same item state.
    local tooltipData = tooltipDataBySlot[item.itemSlotID]

    local tooltipEnchantFound = false
    local socketIndex = 0
    if tooltipData ~= nil then
      for _, line in ipairs(tooltipData.lines or {}) do
        if line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent and line.leftText then
          enchantText, enchantTooltip = formatEnchantLine(line.leftText)
          tooltipEnchantFound = true
        end

        if line.type == Enum.TooltipDataLineType.GemSocket then
          socketIndex = socketIndex + 1
          if line.gemIcon then
            local gemTexture = CreateSimpleTextureMarkup(line.gemIcon, 14, 14)
            table.insert(socketTexts, gemTexture)

            local gemTooltipLine = gemTexture .. " " .. line.leftText
            local qualityMarkup = getGemCraftingQualityMarkup(item.itemLink, socketIndex)
            if qualityMarkup then
              gemTooltipLine = gemTooltipLine .. " " .. qualityMarkup
            end
            table.insert(socketTooltipLines, gemTooltipLine)
          elseif line.socketType then
            hasEmptySocket = true
            local socketTexture = CreateSimpleTextureMarkup(string.format("Interface\\ItemSocketingFrame\\UI-EmptySocket-%s", line.socketType), 14, 14)
            table.insert(socketTooltipLines, socketTexture .. " " .. line.leftText)
          end
        end
      end
    end

    if enchantText == "" and Slots[item.itemSlotID] and Slots[item.itemSlotID].canEnchant then
      -- For offline characters, prefer the enchant line saved while that
      -- character was online. This avoids depending on hyperlink tooltip cache.
      if not isCurrentCharacter and item.enchantTooltipLine then
        enchantText, enchantTooltip = formatEnchantLine(item.enchantTooltipLine)
      else
        -- Even when the localized tooltip text is not cached yet, the item link
        -- itself contains the permanent enchant ID. A non-zero ID means the
        -- item is definitely enchanted, so never show a false red "Missing".
        local enchantID = item.enchantID
        if enchantID == nil then
          enchantID = getItemLinkEnchantID(item.itemLink)
        end

        if enchantID and enchantID > 0 then
          enchantText = "Enchanted"
          enchantTooltip = "Enchant ID: " .. tostring(enchantID)

          -- Ask Blizzard to load the underlying item data. ITEM_DATA_LOAD_RESULT
          -- above will re-render and replace this fallback with the real
          -- localized enchant name as soon as the tooltip becomes available.
          if not tooltipEnchantFound and itemID then
            C_Item.RequestLoadItemDataByID(itemID)
          end
        else
          enchantText = "Missing"
          enchantColor = DIM_RED_FONT_COLOR
        end
      end
    end

    local embellishmentInfo = embellishmentInfoBySlot[item.itemSlotID] or {isCrafted = false, hasEmbellishment = false}
    local embellishmentText = ""
    local embellishmentSort = ""
    local embellishmentMissing = false

    if embellishmentInfo.hasEmbellishment then
      local embellishmentName = embellishmentInfo.name or "Embellished"
      if embellishmentInfo.icon then
        -- Match the Gems column: the table only needs the embellishment icon.
        -- The name and effect are exposed in the hover tooltip below.
        embellishmentText = CreateSimpleTextureMarkup(embellishmentInfo.icon, 14, 14)
      else
        -- Keep the cell intentionally compact even if the icon has not loaded yet.
        embellishmentText = ""
      end
      embellishmentSort = embellishmentName
    elseif embellishmentInfo.isCrafted and equippedEmbellishmentCount < 2 then
      embellishmentText = DIM_RED_FONT_COLOR:WrapTextInColorCode("Missing")
      embellishmentSort = "Missing"
      embellishmentMissing = true
    end

    local socketSlot = Slots[item.itemSlotID]
    local gemsCellText = strjoin(" ", unpack(socketTexts))
    if socketSlot and socketSlot.canSocket then
      if hasEmptySocket then
        -- Socket has been activated (via the slot's socket-adding item) but has no gem in it yet.
        gemsCellText = DIM_RED_FONT_COLOR:WrapTextInColorCode("Missing")
      elseif TableCount(socketTexts) == 0 then
        -- No socket present yet; the slot's socket-adding item can still be used to add one.
        gemsCellText = RARE_BLUE_COLOR:WrapTextInColorCode("Available")
      end
    end

    local enchantSort = enchantTooltip ~= "" and enchantTooltip or enchantText
    local gemCount = TableCount(socketTexts)

    ---@type AE_EquipmentTableRow
    local row = {
      item = item,
      upgradeSort = upgradeSort,
      embellishmentSort = embellishmentSort,
      enchantSort = enchantSort,
      gemCount = gemCount,
      data = {
        {data = _G[item.itemSlotName]},
        {
          data = "|T" .. item.itemTexture .. ":0|t " .. item.itemLink,
          onEnter = function(cellFrame)
            GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(item.itemLink)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("<Shift Click to Link to Chat>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            GameTooltip:Show()
          end,
          onLeave = function()
            GameTooltip:Hide()
          end,
          onClick = function()
            if IsModifiedClick("CHATLINK") then
              if not ChatFrameUtil.InsertLink(item.itemLink) then
                ChatFrameUtil.OpenChat(item.itemLink)
              end
            end
          end,
        },
        {data = WrapTextInColorCode(tostring(floor(item.itemLevel)), select(4, C_Item.GetItemQualityColor(item.itemQuality)))},
        {data = upgradeLevel},
        {
          data = embellishmentText,
          onEnter = function(cellFrame)
            if embellishmentInfo.hasEmbellishment then
              -- Do not use the reagent/item tooltip here: it adds quality, item
              -- level and other metadata that are irrelevant in this column.
              -- Mirror the concise Enchant/Gems hover style instead.
              GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
              GameTooltip:AddLine(embellishmentInfo.name or "Embellishment", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
              if embellishmentInfo.tooltipLine and embellishmentInfo.tooltipLine ~= "" then
                local effectText = embellishmentInfo.tooltipLine:gsub("^Equip:%s*", "")
                GameTooltip:AddLine(effectText, 1, 1, 1, true)
              end
              GameTooltip:Show()
            elseif embellishmentMissing then
              GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
              GameTooltip:AddLine("Missing Embellishment", DIM_RED_FONT_COLOR.r, DIM_RED_FONT_COLOR.g, DIM_RED_FONT_COLOR.b)
              GameTooltip:AddLine(format("Equipped embellishments: %d/2", equippedEmbellishmentCount), 1, 1, 1)
              GameTooltip:Show()
            end
          end,
          onLeave = function()
            GameTooltip:Hide()
          end,
        },
        {
          data = enchantColor:WrapTextInColorCode(enchantText),
          onEnter = function(cellFrame)
            if enchantTooltip ~= "" then
              GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
              GameTooltip:AddLine("Enchanted:")
              GameTooltip:AddLine(enchantTooltip, 1, 1, 1)
              GameTooltip:Show()
            end
          end,
          onLeave = function()
            GameTooltip:Hide()
          end,
        },
        {
          data = gemsCellText,
          onEnter = function(cellFrame)
            if TableCount(socketTooltipLines) > 0 then
              GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
              GameTooltip:AddLine("Gems:")
              TableForEach(socketTooltipLines, function(line)
                GameTooltip:AddLine(line, 1, 1, 1)
              end)
              GameTooltip:Show()
            end
          end,
          onLeave = function()
            GameTooltip:Hide()
          end,
        },
      },
    }
    table.insert(rows, row)
  end)

  local nameColor = WHITE_FONT_COLOR
  if character.info.class.file ~= nil then
    local classColor = C_ClassColor.GetClassColor(character.info.class.file)
    if classColor ~= nil then
      nameColor = CreateColor(classColor.r, classColor.g, classColor.b, 1)
    end
  end

  local ilvlText = ""
  if character.info.ilvl ~= nil and character.info.ilvl.equipped ~= nil then
    local ilvlColor = Helpers:GetItemLevelTrackColor(character.info.ilvl.equipped):GenerateHexColor()
    local ilvlValue
    if Data.db.global.showItemLevelDecimals then
      ilvlValue = format("%.2f", character.info.ilvl.equipped)
    else
      ilvlValue = tostring(floor(character.info.ilvl.equipped))
    end
    ilvlText = " - " .. WrapTextInColorCode(ilvlValue, ilvlColor)
  end

  local positionPrefix = ""
  if Data.db.global.showCharacterPosition then
    for characterIndex, listedCharacter in ipairs(Data:GetCharacters()) do
      if listedCharacter.GUID == character.GUID then
        positionPrefix = WHITE_FONT_COLOR:WrapTextInColorCode(format("%d - ", characterIndex))
        break
      end
    end
  end

  local embellishmentStatusText = ""
  if missingEmbellishmentCount > 0 then
    local missingLabel = missingEmbellishmentCount == 1 and "Missing 1 Embellishment" or format("Missing %d Embellishments", missingEmbellishmentCount)
    embellishmentStatusText = " - " .. DIM_RED_FONT_COLOR:WrapTextInColorCode(missingLabel)
  end

  self.window:SetTitle(format("%s%s (%s)%s%s", positionPrefix, nameColor:WrapTextInColorCode(character.info.name), character.info.realm, ilvlText, embellishmentStatusText))
  sizeEquipmentColumnsToContent(self.dataTable, rows)
  self.dataTable:SetData(rows)
  local bodyWidth, bodyHeight = self.dataTable:GetSize()
  self.window:SetBodySize(bodyWidth > 0 and bodyWidth or tableWidth, bodyHeight)
end
