---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI or not LiqUI.Data then
  return
end

---@class LiqUI_Data
local Data = LiqUI.Data

local TableForEach = LiqUI.Utils.TableForEach
local TableGet = LiqUI.Utils.TableGet
local inventorySlotSides = LiqUI.Constants.inventorySlotSides

---@type LiqUI_InventorySlot[]
Data.inventorySlots = {
  {id = INVSLOT_HEAD, token = "HEADSLOT", paperdoll = "Head", side = inventorySlotSides.LEFT, canEnchant = true, canSocket = true},
  {id = INVSLOT_NECK, token = "NECKSLOT", paperdoll = "Neck", side = inventorySlotSides.LEFT, canEnchant = false, canSocket = false},
  {id = INVSLOT_SHOULDER, token = "SHOULDERSLOT", paperdoll = "Shoulder", side = inventorySlotSides.LEFT, canEnchant = true, canSocket = false},
  {id = INVSLOT_CHEST, token = "CHESTSLOT", paperdoll = "Chest", side = inventorySlotSides.LEFT, canEnchant = true, canSocket = false},
  {id = INVSLOT_WAIST, token = "WAISTSLOT", paperdoll = "Waist", side = inventorySlotSides.RIGHT, canEnchant = false, canSocket = true},
  {id = INVSLOT_LEGS, token = "LEGSSLOT", paperdoll = "Legs", side = inventorySlotSides.RIGHT, canEnchant = true, canSocket = false},
  {id = INVSLOT_FEET, token = "FEETSLOT", paperdoll = "Feet", side = inventorySlotSides.RIGHT, canEnchant = true, canSocket = false},
  {id = INVSLOT_WRIST, token = "WRISTSLOT", paperdoll = "Wrist", side = inventorySlotSides.LEFT, canEnchant = false, canSocket = true},
  {id = INVSLOT_HAND, token = "HANDSSLOT", paperdoll = "Hands", side = inventorySlotSides.RIGHT, canEnchant = false, canSocket = false},
  {id = INVSLOT_FINGER1, token = "FINGER0SLOT", paperdoll = "Finger0", side = inventorySlotSides.RIGHT, canEnchant = true, canSocket = false},
  {id = INVSLOT_FINGER2, token = "FINGER1SLOT", paperdoll = "Finger1", side = inventorySlotSides.RIGHT, canEnchant = true, canSocket = false},
  {id = INVSLOT_TRINKET1, token = "TRINKET0SLOT", paperdoll = "Trinket0", side = inventorySlotSides.RIGHT, canEnchant = false, canSocket = false},
  {id = INVSLOT_TRINKET2, token = "TRINKET1SLOT", paperdoll = "Trinket1", side = inventorySlotSides.RIGHT, canEnchant = false, canSocket = false},
  {id = INVSLOT_BACK, token = "BACKSLOT", paperdoll = "Back", side = inventorySlotSides.LEFT, canEnchant = false, canSocket = false},
  {id = INVSLOT_MAINHAND, token = "MAINHANDSLOT", paperdoll = "MainHand", side = inventorySlotSides.RIGHT, canEnchant = true, canSocket = false},
  {id = INVSLOT_OFFHAND, token = "SECONDARYHANDSLOT", paperdoll = "SecondaryHand", side = inventorySlotSides.LEFT, canEnchant = true, canSocket = false},
}

---@return LiqUI_InventorySlot[]
function Data:GetInventorySlots()
  ---@type LiqUI_InventorySlot[]
  local slots = {}
  TableForEach(self.inventorySlots, function(slot)
    table.insert(slots, slot)
  end)
  return slots
end

---@param slotID number
---@return LiqUI_InventorySlot|nil
function Data:GetInventorySlotByID(slotID)
  return TableGet(self:GetInventorySlots(), "id", slotID)
end

---@return table<number, LiqUI_InventorySlotSideId>
function Data:GetInventorySlotSides()
  ---@type table<number, LiqUI_InventorySlotSideId>
  local sides = {}
  TableForEach(self:GetInventorySlots(), function(slot)
    sides[slot.id] = slot.side
  end)
  return sides
end
