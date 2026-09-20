assert(LibStub, "LiqUI requires LibStub")

local MAJOR, MINOR = "LiqUI-1.0", 4
---@class LiqUI
local LiqUI = LibStub:NewLibrary(MAJOR, MINOR)
if not LiqUI then
  return
end

LiqUI.minor = MINOR

_G.LiqUI = LiqUI

LiqUI.elements = {}
LiqUI.created = {}
LiqUI.registeredAddons = {}

---@param elementType string
---@param createFn fun(options: table): any
function LiqUI:RegisterElement(elementType, createFn)
  if type(elementType) ~= "string" or elementType == "" then
    error("LiqUI:RegisterElement requires elementType", 2)
  end
  if type(createFn) ~= "function" then
    error("LiqUI:RegisterElement requires createFn", 2)
  end
  self.elements[elementType] = createFn
end

---@param elementType string
---@param options table
---@return any
function LiqUI:NewElement(elementType, options)
  if type(elementType) ~= "string" or elementType == "" then
    error("LiqUI:NewElement requires elementType", 2)
  end
  local createFn = self.elements[elementType]
  if not createFn then
    error("LiqUI:NewElement unknown elementType: " .. elementType, 2)
  end
  if type(options) ~= "table" then
    error("LiqUI:NewElement requires options", 2)
  end
  local name = options.name
  if type(name) ~= "string" or name == "" then
    error("LiqUI:NewElement requires options.name", 2)
  end

  local byType = self.created[elementType]
  if not byType then
    byType = {}
    self.created[elementType] = byType
  end
  local existing = byType[name]
  if existing then
    return existing
  end

  local instance = createFn(options)
  byType[name] = instance
  return instance
end

---@param elementType string
---@param name string
---@return any
function LiqUI:GetElement(elementType, name)
  local byType = self.created[elementType]
  if not byType then
    return nil
  end
  return byType[name]
end

---@param options LiqUI_RegisterAddonOptions
function LiqUI:RegisterAddon(options)
  if type(options) ~= "table" then
    error("LiqUI:RegisterAddon requires options", 2)
  end
  if type(options.name) ~= "string" or options.name == "" then
    error("LiqUI:RegisterAddon requires name", 2)
  end
  ---@type LiqUI_RegisteredAddon
  local entry = {
    name = options.name,
    title = options.title or options.name,
  }
  self.registeredAddons[options.name] = entry
end

---@param name string
---@return LiqUI_RegisteredAddon?
function LiqUI:GetRegisteredAddon(name)
  return self.registeredAddons[name]
end

---@return LiqUI_RegisteredAddon[]
function LiqUI:GetRegisteredAddons()
  ---@type LiqUI_RegisteredAddon[]
  local list = {}
  for _, entry in pairs(self.registeredAddons) do
    table.insert(list, entry)
  end
  table.sort(list, function(a, b)
    return strcmputf8i(a.title, b.title) < 0
  end)
  return list
end
