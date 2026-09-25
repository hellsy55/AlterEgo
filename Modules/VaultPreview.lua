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

---Find a slot from the remembered last-known-good snapshot
---(Data:ArchiveVaultSnapshot), normalized to the same shape `buildSlotCell`
---already understands for a live slot (progress/threshold always "met",
---since the snapshot only ever remembers slots that were actually
---unlocked).
---@param character AE_Character
---@param vaultTypeID Enum.WeeklyRewardChestThresholdType
---@param index number
---@return table? activity, boolean? claimed
local function findSnapshotSlot(character, vaultTypeID, index)
  local snapshot = character.vault and character.vault.lastSnapshot
  if not snapshot then return nil end
  for id, slot in pairs(snapshot.slots or {}) do
    if slot.type == vaultTypeID and slot.index == index then
      return {
        progress = 1,
        threshold = 1,
        exampleRewardLink = slot.exampleRewardLink,
      }, snapshot.claimed and snapshot.claimed[id] == true
    end
  end
  return nil
end

---Build one grid cell (icon + item level, or "-" when locked/unknown) for a vault slot.
---@param character AE_Character
---@param vaultType AE_VaultType
---@param index number
---@param useSnapshot boolean? true = read the remembered last-known snapshot instead of the live/current data
---@return LiqUI_TableDataCellExtended
local function buildSlotCell(character, vaultType, index, useSnapshot)
  local activity, claimed
  if useSnapshot then
    activity, claimed = findSnapshotSlot(character, vaultType.id, index)
  else
    activity = findSlot(character, vaultType.id, index)
  end

  -- REAL BUG FIXED HERE: this used to also require
  -- `activity.progress >= activity.threshold`, but Blizzard's own
  -- progress/threshold can stay stale/out of sync even once a reward has
  -- genuinely been generated for a slot (the same quirk documented at
  -- length in GG's Vault.lua, "OCTAVA CORRECCION") -- a real bug report
  -- confirmed a slot the player could see and claim in the native window
  -- stayed blank here because of exactly this. `exampleRewardLink` being
  -- non-empty is the reliable signal on its own: Data:UpdateVault only
  -- ever sets it once a reward genuinely exists (either the "example" it
  -- got when progress/threshold looked met, or the REAL resolved item once
  -- `activity.rewards` exists, independent of progress/threshold).
  if not activity or not activity.exampleRewardLink or activity.exampleRewardLink == "" then
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
  if useSnapshot then
    text = LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(text)
  end

  return {
    data = text,
    onEnter = function(cellFrame)
      GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(itemLink)
      if useSnapshot then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Last known -- vault has since reset without this being claimed.", nil, nil, nil, true)
      end
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
---@param useSnapshot boolean? Show the remembered last-known snapshot instead
---of the live/current data -- used when the live grid has nothing to show
---(e.g. right after a weekly reset) but a snapshot from before that does.
function Module:OpenCharacter(character, useSnapshot)
  if not self.window then return end
  if self.character and self.character == character and self.window:IsVisible() then
    self.window:Hide()
    return
  end
  self.character = character
  self.usingSnapshot = useSnapshot and true or false
  self:Render()
  self.window:Show()
  self.window:Raise()
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
    -- Reserve a fixed strip above the table for the "Updated on" /
    -- last-known-snapshot note (below) -- fixed, not dynamic, so the table
    -- doesn't have to keep shifting up/down as that text changes.
    self.note = self.window.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.note:SetPoint("TOPLEFT", self.window.body, "TOPLEFT", 4, -2)
    self.note:SetPoint("TOPRIGHT", self.window.body, "TOPRIGHT", -4, -2)
    self.note:SetJustifyH("LEFT")
    local NOTE_HEIGHT = 16
    self.table:SetPoint("TOPLEFT", self.window.body, "TOPLEFT", 0, -NOTE_HEIGHT)
    self.table:SetPoint("BOTTOMRIGHT", self.window.body, "BOTTOMRIGHT", 0, 0)
  end

  if not self.window:IsVisible() then
    return
  end

  local character = self.character
  if not character then
    return
  end

  local useSnapshot = self.usingSnapshot
  -- Title is deliberately kept short and constant -- a real bug report
  -- confirmed that appending the snapshot date here made it long enough to
  -- overlap the titlebar's own buttons (close, etc.), which are anchored
  -- from the right edge and don't make room for a growing title. The date
  -- lives in the body instead (self.note below), where we control the
  -- layout completely.
  self.window:SetTitle(format("Great Vault - %s (%s)", character.info.name, character.info.realm))

  local updatedAt = useSnapshot
    and character.vault and character.vault.lastSnapshot and character.vault.lastSnapshot.capturedAt
    or character.vault and character.vault.lastUpdatedAt
  if updatedAt and updatedAt > 0 then
    local weekNumber = Data.GetSeasonWeekNumber and Data:GetSeasonWeekNumber()
    local text = format("Updated on: %s", date("%d/%m/%y - %H:%M", updatedAt))
    if weekNumber then
      text = text .. format(" - Week %d", weekNumber)
    end
    if useSnapshot then
      text = text .. " (Last Known -- vault has since reset)"
    end
    self.note:SetText(useSnapshot and ORANGE_FONT_COLOR:WrapTextInColorCode(text) or LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(text))
  else
    self.note:SetText("")
  end

  local hasData
  if useSnapshot then
    hasData = Data:HasVaultHistory(character)
  else
    hasData = character.vault and character.vault.slots and #character.vault.slots > 0
  end

  if not hasData then
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
        buildSlotCell(character, vaultType, 1, useSnapshot),
        buildSlotCell(character, vaultType, 2, useSnapshot),
        buildSlotCell(character, vaultType, 3, useSnapshot),
      },
    }
    table.insert(rows, row)
  end)

  self.table:SetColumns(columns)
  self.table:SetData(rows)
  -- Recompute the body size from the table every render, plus the fixed
  -- strip reserved above it for the snapshot note.
  local bodyWidth, bodyHeight = self.table:GetSize()
  self.window:SetBodySize(bodyWidth, bodyHeight + 16)
end
