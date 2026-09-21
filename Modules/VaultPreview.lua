---@class AE_Addon
local addon = select(2, ...)

---@class AE_Module_VaultPreview
local Module = addon.Core:NewModule("VaultPreview", "AceConsole-3.0")
addon.Module_VaultPreview = Module

local Data = addon.Data
local LibLiqUI = addon.Libs.LiqUI
local TableForEach = LibLiqUI.Utils.TableForEach

local ICON_SIZE = 20
local LABEL_COLUMN_WIDTH = 90
local SLOT_COLUMN_WIDTH = 76
local ROW_HEIGHT = 30
local NO_DATA_TEXT = "This character hasn't logged in yet this week, so there's no Great Vault data to show.\nLog in on them to refresh it."

---Find the cached vault slot (activity) for a specific type+index, if any.
---@param character AE_Character
---@param vaultTypeID Enum.WeeklyRewardChestThresholdType
---@param index number
---@return table? activity
local function findSlot(character, vaultTypeID, index)
  for _, slot in ipairs(character.vault and character.vault.slots or {}) do
    if slot.type == vaultTypeID and slot.index == index then
      return slot
    end
  end
  return nil
end

---Build one grid cell (icon + item level, or "-" when locked/unknown) for a vault slot.
---@param character AE_Character
---@param vaultType AE_VaultType
---@param index number
---@return LiqUI_TableDataCellExtended
local function buildSlotCell(character, vaultType, index)
  local activity = findSlot(character, vaultType.id, index)

  -- Same source of truth already used for the offline-alt progress bars/tooltip
  -- (Data:UpdateVault) -- an activity only carries a usable exampleRewardLink
  -- once its threshold was met the last time this character was updated.
  if not activity or activity.progress < activity.threshold or not activity.exampleRewardLink or activity.exampleRewardLink == "" then
    return {
      data = LIGHTGRAY_FONT_COLOR:WrapTextInColorCode("-"),
    }
  end

  local itemLink = activity.exampleRewardLink
  local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemLink)
  local itemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)

  local text = icon and format("|T%d:%d|t", icon, ICON_SIZE) or ""
  if itemLevel then
    text = text .. " " .. itemLevel
  end

  return {
    data = text,
    onEnter = function(cellFrame)
      GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(itemLink)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("<Shift Click to Link to Chat>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
      GameTooltip:Show()
    end,
    onLeave = function()
      GameTooltip:Hide()
    end,
    onClick = function()
      if IsModifiedClick("CHATLINK") then
        if not ChatEdit_InsertLink(itemLink) then
          ChatFrame_OpenChat(itemLink)
        end
      end
    end,
  }
end

function Module:OnInitialize()
  self:Render()
end

---Open the Great Vault preview for a specific character. Clicking the same
---character again while it's already open just closes it (same behavior as
---the Equipment window).
---@param character AE_Character
function Module:OpenCharacter(character)
  if not self.window then return end
  if self.character and self.character == character and self.window:IsVisible() then
    self.window:Hide()
    return
  end
  self.character = character
  self:Render()
  self.window:Show()
end

function Module:Render()
  if not self.window then
    local windows = Data.db.global.liqui.windows
    local tables = Data.db.global.liqui.tables
    ---@type LiqUI_WindowInstance
    self.window = LibLiqUI:NewElement("Window", {
      name = addon.name .. "VaultPreview",
      storage = windows.VaultPreview,
      title = "Great Vault",
      onShow = function()
        Module:Render()
      end,
    })
    ---@type LiqUI_TableInstance
    self.table = LibLiqUI:NewElement("Table", {
      name = addon.name .. "VaultPreview",
      storage = tables.VaultPreview,
      header = {enabled = false},
      rowStyle = {height = ROW_HEIGHT, striped = true},
    })
    self.table:SetParent(self.window.body)
    self.table:SetPoint("TOPLEFT", self.window.body, "TOPLEFT", 0, 0)
    self.table:SetPoint("BOTTOMRIGHT", self.window.body, "BOTTOMRIGHT", 0, 0)
  end

  if not self.window:IsVisible() then
    return
  end

  local character = self.character
  if not character then
    return
  end

  self.window:SetTitle(format("Great Vault - %s (%s)", character.info.name, character.info.realm))

  if not character.vault or not character.vault.slots or #character.vault.slots == 0 then
    self.window:ShowOverlay(NO_DATA_TEXT)
    self.table:Hide()
    self.window:SetBodySize(320, 90)
    return
  end

  self.window:HideOverlay()
  self.table:Show()

  ---@type LiqUI_TableOptionsColumn[]
  local columns = {
    {id = "label", width = LABEL_COLUMN_WIDTH},
    {id = "slot1", width = SLOT_COLUMN_WIDTH},
    {id = "slot2", width = SLOT_COLUMN_WIDTH},
    {id = "slot3", width = SLOT_COLUMN_WIDTH},
  }

  ---@type LiqUI_TableData
  local rows = {}
  TableForEach(Data.vaultTypes, function(vaultType)
    ---@type LiqUI_TableDataRowExtended
    local row = {
      data = {
        {data = WHITE_FONT_COLOR:WrapTextInColorCode(vaultType.name)},
        buildSlotCell(character, vaultType, 1),
        buildSlotCell(character, vaultType, 2),
        buildSlotCell(character, vaultType, 3),
      },
    }
    table.insert(rows, row)
  end)

  self.table:SetColumns(columns)
  self.table:SetData(rows)
  local bodyWidth, bodyHeight = self.table:GetSize()
  self.window:SetBodySize(bodyWidth, bodyHeight)
end
