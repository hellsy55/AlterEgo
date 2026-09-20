---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI then
  return
end

---@class LiqUI_Logger
local Logger = {}
LiqUI.Logger = Logger

local CreateScrollingEditBox = LiqUI.Utils.CreateScrollingEditBox

local LINES_MAX = 200
local WINDOW_WIDTH = 1200
local WINDOW_HEIGHT = 600
local BODY_PADDING = LiqUI.Constants.layout.sizes.padding
local CLEAR_ICON_SIZE = 12

---@type table<string, LiqUI_LoggerHandle>
local handles = {}

local selectedAddonName = nil
local window = nil
local refreshPending = false

---@param textBox Frame
---@param text string
---@param scrollToEnd boolean|nil
local function applyLogText(textBox, text, scrollToEnd)
  local editBox = textBox:GetEditBox()
  if editBox.logText ~= text then
    editBox.logText = text
    textBox:SetText(text)
  end
  if scrollToEnd then
    C_Timer.After(0, function()
      local scrollBox = textBox:GetScrollBox()
      if scrollBox then
        scrollBox:ScrollToEnd()
      end
    end)
  end
end

---@param storage LiqUI_LoggerDB
local function trimLoggerLines(storage)
  while #storage.lines > LINES_MAX do
    table.remove(storage.lines, 1)
  end
end

---@param storage LiqUI_LoggerDB
local function ensureLoggerStorage(storage)
  if type(storage.lines) ~= "table" then
    storage.lines = {}
  end
  if storage.autoScroll == nil then
    storage.autoScroll = true
  end
  if storage.autoShow == nil then
    storage.autoShow = false
  end
end

---@return LiqUI_LoggerHandle[]
local function getLoggerHandles()
  ---@type LiqUI_LoggerHandle[]
  local list = {}
  for _, handle in pairs(handles) do
    table.insert(list, handle)
  end
  table.sort(list, function(a, b)
    return strcmputf8i(a.title, b.title) < 0
  end)
  return list
end

---@return LiqUI_LoggerHandle?
local function getSelectedHandle()
  local list = getLoggerHandles()
  if #list == 0 then
    return nil
  end
  if selectedAddonName then
    for index = 1, #list do
      if list[index].name == selectedAddonName then
        return list[index]
      end
    end
  end
  selectedAddonName = list[1].name
  return list[1]
end

---@param handle LiqUI_LoggerHandle
---@param level string|nil
---@param prefixOrMessage string
---@param message string?
local function appendLine(handle, level, prefixOrMessage, message)
  local storage = handle.storage
  local lineText
  if level then
    if message ~= nil then
      lineText = format("[%s] [%s] [%s] %s", date("%H:%M:%S"), level, prefixOrMessage, message)
    else
      lineText = format("[%s] [%s] %s", date("%H:%M:%S"), level, prefixOrMessage)
    end
  elseif message ~= nil then
    lineText = format("[%s] [%s] %s", date("%H:%M:%S"), prefixOrMessage, message)
  else
    lineText = format("[%s] %s", date("%H:%M:%S"), prefixOrMessage)
  end
  table.insert(storage.lines, lineText)
  trimLoggerLines(storage)
  if storage.autoShow then
    selectedAddonName = handle.name
    Logger:Show()
  end
  Logger:QueueRefresh()
end

---@param options LiqUI_NewLoggerOptions
---@return LiqUI_LoggerHandle
function LiqUI:NewLogger(options)
  if type(options) ~= "table" then
    error("LiqUI:NewLogger requires options", 2)
  end
  if type(options.name) ~= "string" or options.name == "" then
    error("LiqUI:NewLogger requires name", 2)
  end
  if type(options.storage) ~= "table" then
    error("LiqUI:NewLogger requires storage", 2)
  end

  ensureLoggerStorage(options.storage)

  local existing = handles[options.name]
  if existing then
    existing.title = options.title or existing.title or options.name
    existing.storage = options.storage
    return existing
  end

  ---@type LiqUI_LoggerHandle
  local handle = {
    name = options.name,
    title = options.title or options.name,
    storage = options.storage,
  }

  ---@param prefixOrMessage string
  ---@param message string?
  function handle:Log(prefixOrMessage, message)
    appendLine(self, nil, prefixOrMessage, message)
  end

  ---@param message string
  function handle:Warn(message)
    appendLine(self, "WARN", message)
  end

  ---@param message string
  function handle:Error(message)
    appendLine(self, "ERROR", message)
  end

  function handle:Clear()
    wipe(self.storage.lines)
    selectedAddonName = self.name
    Logger:QueueRefresh()
  end

  ---@param state boolean|nil
  function handle:Toggle(state)
    selectedAddonName = self.name
    Logger:Toggle(state)
  end

  function handle:Show()
    selectedAddonName = self.name
    Logger:Show()
  end

  function handle:Hide()
    Logger:Hide()
  end

  handles[options.name] = handle
  return handle
end

function Logger:Clear()
  local handle = getSelectedHandle()
  if not handle then
    return
  end
  wipe(handle.storage.lines)
  self:QueueRefresh()
end

function Logger:QueueRefresh()
  if refreshPending then
    return
  end
  refreshPending = true
  C_Timer.After(0, function()
    refreshPending = false
    self:Refresh()
  end)
end

function Logger:Refresh()
  if not window then
    return
  end
  if not window:IsVisible() then
    return
  end
  local textBox = window.body.textBox
  if not textBox then
    return
  end
  local handle = getSelectedHandle()
  local lines = handle and handle.storage.lines or {}
  local autoScroll = handle and handle.storage.autoScroll
  local text = table.concat(lines, "\n")
  applyLogText(textBox, text, autoScroll)
  window:SetTitle(handle and handle.title or "Log")
end

function Logger:Render()
  if not window then
    ---@type LiqUI_WindowOptions
    local windowOptions = {
      name = "LiqUILogger",
      title = "Log",
      width = WINDOW_WIDTH,
      height = WINDOW_HEIGHT,
      titlebarButtons = {
        {
          name = "AddonSelect",
          icon = LiqUI.Constants.layout.media.iconSettings,
          tooltipTitle = "Addon",
          tooltipDescription = "Choose which addon's log to show.",
          onMenu = function(_, rootMenu)
            local list = getLoggerHandles()
            for index = 1, #list do
              local handle = list[index]
              rootMenu:CreateRadio(
                handle.title,
                function()
                  return selectedAddonName == handle.name
                end,
                function()
                  selectedAddonName = handle.name
                  Logger:Refresh()
                end
              )
            end
          end,
        },
        {
          name = "ClearButton",
          icon = LiqUI.Constants.layout.media.iconClose,
          tooltipTitle = "Clear log",
          tooltipDescription = "Remove all lines from the selected addon's log.",
          onClick = function()
            Logger:Clear()
          end,
          iconSize = CLEAR_ICON_SIZE,
        },
      },
    }
    window = LiqUI:NewElement("Window", windowOptions)
    window:SetScript("OnShow", function()
      window:Render()
      Logger:Refresh()
    end)

    ---@type LiqUI_WindowBody
    local body = window.body
    local scrollHost = CreateScrollingEditBox(body, BODY_PADDING)
    local textBox = scrollHost.textBox
    textBox:SetFontObject("ChatFontSmall")

    local editBox = textBox:GetEditBox()
    editBox.logText = ""
    editBox:SetScript("OnChar", function()
    end)
    editBox:SetScript("OnKeyDown", function(_, key)
      if IsControlKeyDown() then
        return
      end
      if key == "ESCAPE" then
        textBox:ClearFocus()
      end
    end)

    window.body.textBox = textBox
    window.body.scrollBar = scrollHost.scrollBar
  end

  self:Refresh()
end

---@param state boolean|nil
function Logger:Toggle(state)
  self:Render()
  if not window then
    return
  end
  window:Toggle(state)
  if window:IsVisible() then
    self:Refresh()
  end
end

function Logger:Show()
  self:Toggle(true)
end

function Logger:Hide()
  self:Toggle(false)
end
