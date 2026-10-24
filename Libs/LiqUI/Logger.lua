---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI then
  return
end

LiqUI.Logger = LiqUI.Logger or {
  handles = {},
  selectedAddonName = nil,
  window = nil,
  refreshPending = false,
}

---@class LiqUI_Logger
local Logger = LiqUI.Logger
local CreateScrollingEditBox = LiqUI.Utils.CreateScrollingEditBox
local LINES_MAX = 200
local WINDOW_WIDTH = 1200
local WINDOW_HEIGHT = 600
local BODY_PADDING = LiqUI.Constants.layout.sizes.padding
local CLEAR_ICON_SIZE = 12

---@param textBox ScrollingEditBoxTemplate
---@param text string
---@param scrollToEnd boolean|nil
local function applyLogText(textBox, text, scrollToEnd)
  ---@type LiqUI_LogEditBox
  local editBox = textBox:GetEditBox()
  if editBox.logText ~= text then
    editBox.logText = text
    textBox:SetText(text)
  end
  if scrollToEnd then
    C_Timer.After(0, function()
      ---@type WowScrollBox
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
  for _, handle in pairs(Logger.handles) do
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
  if Logger.selectedAddonName then
    for index = 1, #list do
      if list[index].name == Logger.selectedAddonName then
        return list[index]
      end
    end
  end
  Logger.selectedAddonName = list[1].name
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
    Logger.selectedAddonName = handle.name
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

  local existing = Logger.handles[options.name]
  if existing then
    existing.title = options.title or existing.title or options.name
    existing.storage = options.storage
    return existing
  end

  local handle = {
    name = options.name,
    title = options.title or options.name,
    storage = options.storage,
  }

  ---@param loggerHandle LiqUI_LoggerHandle
  ---@param prefixOrMessage string
  ---@param message string?
  function handle.Log(loggerHandle, prefixOrMessage, message)
    appendLine(loggerHandle, nil, prefixOrMessage, message)
  end

  ---@param loggerHandle LiqUI_LoggerHandle
  ---@param message string
  function handle.Warn(loggerHandle, message)
    appendLine(loggerHandle, "WARN", message)
  end

  ---@param loggerHandle LiqUI_LoggerHandle
  ---@param message string
  function handle.Error(loggerHandle, message)
    appendLine(loggerHandle, "ERROR", message)
  end

  ---@param loggerHandle LiqUI_LoggerHandle
  function handle.Clear(loggerHandle)
    wipe(loggerHandle.storage.lines)
    Logger.selectedAddonName = loggerHandle.name
    Logger:QueueRefresh()
  end

  ---@param loggerHandle LiqUI_LoggerHandle
  ---@param state boolean|nil
  function handle.Toggle(loggerHandle, state)
    Logger.selectedAddonName = loggerHandle.name
    Logger:Toggle(state)
  end

  ---@param loggerHandle LiqUI_LoggerHandle
  function handle.Show(loggerHandle)
    Logger.selectedAddonName = loggerHandle.name
    Logger:Show()
  end

  function handle.Hide()
    Logger:Hide()
  end

  Logger.handles[options.name] = handle
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
  if Logger.refreshPending then
    return
  end
  Logger.refreshPending = true
  C_Timer.After(0, function()
    Logger.refreshPending = false
    self:Refresh()
  end)
end

function Logger:Refresh()
  local loggerWindow = Logger.window
  if not loggerWindow then
    return
  end
  if not loggerWindow:IsVisible() then
    return
  end
  local textBox = loggerWindow.body.textBox
  if not textBox then
    return
  end
  local handle = getSelectedHandle()
  local lines = handle and handle.storage.lines or {}
  local autoScroll = handle and handle.storage.autoScroll
  local text = table.concat(lines, "\n")
  applyLogText(textBox, text, autoScroll)
  loggerWindow:SetTitle(handle and handle.title or "Log")
end

---@param _ LiqUI_WindowInstance
---@param rootMenu RootMenuDescriptionProxy
local function openLoggerAddonMenu(_, rootMenu)
  local list = getLoggerHandles()
  for index = 1, #list do
    local handle = list[index]
    rootMenu:CreateRadio(
      handle.title,
      function()
        return Logger.selectedAddonName == handle.name
      end,
      function()
        Logger.selectedAddonName = handle.name
        Logger:Refresh()
      end
    )
  end
end

local function clearSelectedLog()
  Logger:Clear()
end

function Logger:Render()
  if not Logger.window then
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
          onMenu = openLoggerAddonMenu,
        },
        {
          name = "ClearButton",
          icon = LiqUI.Constants.layout.media.iconClose,
          tooltipTitle = "Clear log",
          tooltipDescription = "Remove all lines from the selected addon's log.",
          onClick = clearSelectedLog,
          iconSize = CLEAR_ICON_SIZE,
        },
      },
    }
    local loggerWindow = LiqUI:NewElement("Window", windowOptions)
    Logger.window = loggerWindow
    loggerWindow:SetScript("OnShow", function()
      loggerWindow:Render()
      Logger:Refresh()
    end)

    ---@type LiqUI_WindowBody
    local body = loggerWindow.body
    local scrollHost = CreateScrollingEditBox(body, BODY_PADDING)
    local textBox = scrollHost.textBox
    textBox:SetFontObject("ChatFontSmall")

    ---@type LiqUI_LogEditBox
    local editBox = textBox:GetEditBox()
    editBox.logText = ""
    editBox:SetScript("OnChar", function()
    end)
    ---@param _ EditBox
    ---@param key string
    local function onLogKeyDown(_, key)
      if IsControlKeyDown() then
        return
      end
      if key == "ESCAPE" then
        textBox:ClearFocus()
      end
    end
    editBox:SetScript("OnKeyDown", onLogKeyDown)

    loggerWindow.body.textBox = textBox
    loggerWindow.body.scrollBar = scrollHost.scrollBar
  end

  self:Refresh()
end

---@param state boolean|nil
function Logger:Toggle(state)
  self:Render()
  local loggerWindow = Logger.window
  if not loggerWindow then
    return
  end
  loggerWindow:Toggle(state)
  if loggerWindow:IsVisible() then
    self:Refresh()
  end
end

function Logger:Show()
  self:Toggle(true)
end

function Logger:Hide()
  self:Toggle(false)
end
