---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI or not LiqUI.Data then
  return
end

---@class LiqUI_Data
local Data = LiqUI.Data

local TableForEach = LiqUI.Utils.TableForEach
local TableGet = LiqUI.Utils.TableGet

---@type LiqUI_Expansion[]
Data.expansions = {
  {id = Enum.ExpansionLevel.Dragonflight, abbr = "DF", name = "Dragonflight"},
  {id = Enum.ExpansionLevel.WarWithin, abbr = "TWW", name = "The War Within"},
  {id = Enum.ExpansionLevel.Midnight, abbr = "Midnight", name = "Midnight"},
}

---@return LiqUI_Expansion[]
function Data:GetExpansions()
  ---@type LiqUI_Expansion[]
  local expansions = {}
  TableForEach(self.expansions, function(expansion)
    table.insert(expansions, expansion)
  end)
  return expansions
end

---@param expansionID Enum.ExpansionLevel
---@return LiqUI_Expansion|nil
function Data:GetExpansionByID(expansionID)
  return TableGet(self:GetExpansions(), "id", expansionID)
end
