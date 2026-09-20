---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI then
  return
end

local SetBackgroundColor = LiqUI.Utils.SetBackgroundColor
local TableCopy = LiqUI.Utils.TableCopy
local TableFilter = LiqUI.Utils.TableFilter
local TableFind = LiqUI.Utils.TableFind
local TableMergeOptions = LiqUI.Utils.TableMergeOptions

---@param window LiqUI_WindowInstance
local function updateWindowClampInsets(window)
  local width = window:GetWidth()
  local height = window:GetHeight()
  window:SetClampRectInsets(width / 2, -width / 2, 0, height / 2)
end

---@param window LiqUI_WindowInstance
local function applyOverlayTextWidth(window)
  if not window.overlay or not window.overlay.text then
    return
  end
  local textWidth = math.max(0, window.overlay:GetWidth() - LiqUI.Constants.layout.overlay.textInset * 2)
  window.overlay.text:SetWidth(textWidth)
  window.overlay.bar:SetWidth(math.min(280, textWidth))
end

---@param window LiqUI_WindowInstance
---@param showOptions LiqUI_WindowOverlayOptions|nil
local function applyOverlayStyle(window, showOptions)
  if not window.overlay then
    return
  end
  local fontObject = LiqUI.Constants.layout.overlay.defaultFontObject
  if showOptions and showOptions.fontObject then
    fontObject = showOptions.fontObject
  elseif window.options.overlayFontObject then
    fontObject = window.options.overlayFontObject
  end
  window.overlay.text:SetFontObject(fontObject)
  local textColor = showOptions and showOptions.textColor or window.options.overlayTextColor
  if textColor then
    window.overlay.text:SetVertexColor(textColor.r, textColor.g, textColor.b, textColor.a or 1)
  else
    window.overlay.text:SetVertexColor(1, 1, 1, 1)
  end
  local backgroundColor = showOptions and showOptions.backgroundColor or window.options.overlayBackgroundColor
    or window:GetWindowColor()
  SetBackgroundColor(window.overlay, backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a)
end

---@param settings LiqUI_WindowDB
---@param window LiqUI_WindowInstance
local function saveWindowPosition(settings, window)
  local frameLeft, frameTop = window:GetLeft(), window:GetTop()
  if frameLeft == nil or frameTop == nil then
    return
  end
  local scale = window:GetScale()
  if scale == 0 then
    scale = 1
  end
  local storedX = frameLeft * scale
  local storedY = frameTop * scale - UIParent:GetHeight()
  ---@type LiqUI_WindowPointPersisted
  settings.point = {"TOPLEFT", "TOPLEFT", storedX, storedY}
  window:ClearAllPoints()
  window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", storedX / scale, storedY / scale)
end

---@param settings LiqUI_WindowDB
---@param window LiqUI_WindowInstance
local function applyWindowPosition(settings, window)
  local scale = (settings.scale or 100) / 100
  if scale == 0 then
    scale = 1
  end

  local offsetX, offsetY
  local savedPoint = settings.point
  if type(savedPoint) == "table" and type(savedPoint[3]) == "number" and type(savedPoint[4]) == "number" then
    offsetX = savedPoint[3] / scale
    offsetY = savedPoint[4] / scale
  else
    local defaultPosition = (window.options.name == "Main" or window.options.name:match("Main$"))
      and LiqUI.Constants.layout.defaultWindowPosition.main
      or LiqUI.Constants.layout.defaultWindowPosition.secondary
    offsetX = defaultPosition.topLeftX
    offsetY = defaultPosition.topLeftY
  end

  window:SetScale(scale)
  window:ClearAllPoints()
  window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", offsetX, offsetY)
end

local function repositionTitlebarButtons(window)
  if not window.titlebar or not window.titlebar.CloseButton then
    return
  end
  local anchorFrame = window.titlebar.CloseButton
  if window.titlebar.SettingsButton then
    window.titlebar.SettingsButton:SetPoint("RIGHT", anchorFrame, "LEFT", 0, 0)
    anchorFrame = window.titlebar.SettingsButton
  end
  for _, titlebarButton in ipairs(window.titlebarButtons) do
    titlebarButton:SetPoint("RIGHT", anchorFrame, "LEFT", 0, 0)
    anchorFrame = titlebarButton
  end
end

---@param frame Frame
---@param window LiqUI_WindowInstance
---@param topOffset number
local function applyWindowContentLayout(frame, window, topOffset)
  frame:SetPoint("TOPLEFT", window, "TOPLEFT", 0, topOffset)
  frame:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, topOffset)
  frame:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 0, 0)
  frame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)
end

---Create a window frame
---@param options LiqUI_WindowOptions
---@return LiqUI_WindowInstance
local function createWindow(options)
  if not options then
    error("LiqUI Window: options is required", 2)
  end
  local windowName = options.name
  if not windowName or windowName == "" then
    error("LiqUI Window: options.name is required", 2)
  end

  local frameName = "LiqUIWindow" .. windowName:gsub("[^%w]", "")

  ---@type LiqUI_WindowInstance
  local window = CreateFrame("Frame", frameName, UIParent)

  ---@type LiqUI_WindowOptions
  local defaultOptions = {
    parent = UIParent,
    name = "",
    title = "",
    border = LiqUI.Constants.layout.sizes.border,
    titlebar = true,
    windowScale = 100,
    windowColor = LiqUI.Constants.layout.defaultWindowColor,
  }
  ---@type LiqUI_WindowOptions
  local mergedOptions = {}
  TableMergeOptions(mergedOptions, defaultOptions)
  TableMergeOptions(mergedOptions, options)

  local storage = options.storage
  if storage and not storage.windowColor then
    storage.windowColor = TableCopy(mergedOptions.windowColor)
  end

  window.options = mergedOptions
  window.db = storage
  window.titlebarButtons = {}

  window:SetFrameStrata("MEDIUM")
  window:SetFrameLevel(3000)
  window:SetToplevel(true)
  window:SetMovable(true)
  window:SetSize(window.options.width or 300, window.options.height or 300)
  window:EnableMouse(true)
  window:SetParent(window.options.parent)
  window:SetClampedToScreen(true)
  window:SetScript("OnSizeChanged", function()
    updateWindowClampInsets(window)
  end)
  updateWindowClampInsets(window)

  ---Hide the window and run the close handler
  function window:Close()
    window:Hide()
    if window.options.onClose then
      window.options.onClose(window)
    end
  end

  ---Show or hide the window
  ---@param state boolean?
  function window:Toggle(state)
    if state == nil then
      state = not window:IsVisible()
    end
    window:SetShown(state)
  end

  ---Set the title of the window
  ---@param title string
  function window:SetTitle(title)
    if not window.options.titlebar then return end
    window.titlebar.title:SetText(title)
  end

  ---Set body size and adjust window size
  ---@param width number
  ---@param height number
  function window:SetBodySize(width, height)
    local w = width
    local h = height
    if window.options.titlebar then
      h = h + LiqUI.Constants.layout.sizes.titlebar.height
    end
    window:SetSize(w, h)
    updateWindowClampInsets(window)
  end

  ---@param text string|nil
  ---@param progress number|nil 0-1; omit to hide the bar.
  ---@param showOptions LiqUI_WindowOverlayOptions|nil
  function window:ShowOverlay(text, progress, showOptions)
    if not window.overlay then
      return
    end
    window.overlayLastShowOptions = showOptions
    applyOverlayStyle(window, showOptions)
    applyOverlayTextWidth(window)
    window.overlay.text:SetText(text or "")
    if progress ~= nil then
      window.overlay.bar:Show()
      window.overlay.bar:SetValue(math.max(0, math.min(1, progress)))
      window.overlay.text:ClearAllPoints()
      window.overlay.text:SetPoint("CENTER", window.overlay, "CENTER", 0, -10)
    else
      window.overlay.bar:Hide()
      window.overlay.text:ClearAllPoints()
      window.overlay.text:SetPoint("CENTER", window.overlay, "CENTER", 0, 0)
    end
    window.overlay:Show()
    if window.body then
      window.body:Hide()
    end
  end

  function window:HideOverlay()
    if window.overlay then
      window.overlay:Hide()
    end
    if window.body then
      window.body:Show()
    end
  end

  ---@return boolean
  function window:IsOverlayShown()
    return window.overlay ~= nil and window.overlay:IsShown()
  end

  ---Add a button to the titlebar
  ---@param buttonConfig LiqUI_WindowTitlebarButton
  ---@return Frame
  function window:AddTitlebarButton(buttonConfig)
    if not window.titlebar then
      error("Cannot add titlebar button: window has no titlebar")
    end

    local buttonName = buttonConfig.name
    if buttonName == "Settings" then
      error("Use onSettingsMenu instead of a Settings titlebarButtons entry", 2)
    end
    if window.titlebarButtons[buttonName] then
      error("Button with name '" .. buttonName .. "' already exists")
    end

    local buttonSize = buttonConfig.size or LiqUI.Constants.layout.sizes.titlebar.height
    local iconSize = buttonConfig.iconSize or 12
    local isEnabled = buttonConfig.enabled ~= false

    local button
    if buttonConfig.onMenu then
      button = CreateFrame("DropdownButton", "$parent" .. buttonName, window.titlebar)
      button.menuGenerator = function(_, rootMenu)
        buttonConfig.onMenu(window, rootMenu)
      end
    else
      button = CreateFrame("Button", "$parent" .. buttonName, window.titlebar)
      button:RegisterForClicks("AnyUp")
      if buttonConfig.onClick then
        button:SetScript("OnClick", buttonConfig.onClick)
      end
    end

    -- Create the icon
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetPoint("CENTER", button, "CENTER")
    button.Icon:SetSize(iconSize, iconSize)
    button.Icon:SetTexture(buttonConfig.icon)
    button.Icon:SetVertexColor(0.7, 0.7, 0.7, 1)

    -- Set up tooltip
    if buttonConfig.tooltipTitle then
      button:SetScript("OnEnter", function()
        button.Icon:SetVertexColor(0.9, 0.9, 0.9, 1)
        SetBackgroundColor(button, 1, 1, 1, 0.05)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(buttonConfig.tooltipTitle, 1, 1, 1, 1, true)
        if buttonConfig.tooltipDescription then
          GameTooltip:AddLine(buttonConfig.tooltipDescription, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
        end
        GameTooltip:Show()
      end)

      button:SetScript("OnLeave", function()
        button.Icon:SetVertexColor(0.7, 0.7, 0.7, 1)
        SetBackgroundColor(button, 1, 1, 1, 0)
        GameTooltip:Hide()
      end)
    end

    button:SetSize(buttonSize, buttonSize)
    button:SetEnabled(isEnabled)
    button:Show()

    table.insert(window.titlebarButtons, button)

    repositionTitlebarButtons(window)

    return button
  end

  ---Remove a button from the titlebar
  ---@param buttonName string
  function window:RemoveTitlebarButton(buttonName)
    local button = TableFind(window.titlebarButtons,
                             function(titlebarButton) return titlebarButton:GetName() == buttonName end)
    if not button then
      error("Button with name '" .. buttonName .. "' does not exist")
    end

    -- Remove the button
    button:Hide()
    button:SetParent(nil)
    window.titlebarButtons = TableFilter(window.titlebarButtons,
                                         function(titlebarButton) return titlebarButton:GetName() ~= buttonName end)

    repositionTitlebarButtons(window)
  end

  ---Get a titlebar button by name
  ---@param buttonName string
  ---@return Frame?
  function window:GetTitlebarButton(buttonName)
    return TableFind(window.titlebarButtons, function(button) return button:GetName() == buttonName end)
  end

  ---@return number
  function window:GetWindowScale()
    if not window.db then
      return 100
    end
    return window.db.scale or 100
  end

  ---@param scalePercent number
  function window:SetWindowScale(scalePercent)
    if not window.db then
      return
    end
    window.db.scale = scalePercent
    window.options.windowScale = scalePercent
    applyWindowPosition(window.db, window)
  end

  ---@return ColorTable?
  function window:GetWindowColor()
    if window.db and window.db.windowColor then
      return window.db.windowColor
    end
    return window.options.windowColor
  end

  ---@param color ColorTable
  function window:SetWindowColor(color)
    if not window.db then
      return
    end
    window.db.windowColor = TableCopy(color)
    window:Render()
  end

  ---@return boolean
  function window:GetBorderShown()
    if not window.db then
      return true
    end
    return window.db.border ~= false
  end

  ---@param shown boolean
  function window:SetBorderShown(shown)
    if not window.db then
      return
    end
    window.db.border = shown
    window:Render()
  end

  function window:ApplySettings()
    local settings = window.db
    if settings then
      if settings.windowColor then
        window.options.windowColor = settings.windowColor
        SetBackgroundColor(window, settings.windowColor.r, settings.windowColor.g, settings.windowColor.b,
                           settings.windowColor.a)
        if window.overlay and window.overlay:IsShown() then
          applyOverlayStyle(window, window.overlayLastShowOptions)
        end
      end
      window.options.windowScale = settings.scale or 100
      applyWindowPosition(settings, window)
      if window.border then
        window.border:SetShown(settings.border ~= false)
      end
      return
    end

    local windowColor = window.options.windowColor
    if windowColor then
      SetBackgroundColor(window, windowColor.r, windowColor.g, windowColor.b, windowColor.a)
      if window.overlay and window.overlay:IsShown() then
        applyOverlayStyle(window, window.overlayLastShowOptions)
      end
    end
    applyWindowPosition({ scale = window.options.windowScale or 100 }, window)
    if window.border then
      window.border:Show()
    end
  end

  function window:SaveSettings()
    local settings = window.db
    if not settings then
      return
    end
    saveWindowPosition(settings, window)
    settings.scale = math.floor(window:GetScale() * 100 + 0.5)
    if window.options.windowColor then
      settings.windowColor = TableCopy(window.options.windowColor)
    end
    if window.border then
      settings.border = window.border:IsShown()
    end
  end

  function window:Render()
    window:ApplySettings()
  end

  ---@param rootMenu table
  ---@param onRefresh fun()|nil
  function window:AppendWindowOptionsMenu(rootMenu, onRefresh)
    rootMenu:CreateTitle("Window")
    local windowScale = rootMenu:CreateButton("Scaling")
    for scalePercent = 80, 200, 10 do
      windowScale:CreateRadio(
        scalePercent .. "%",
        function() return window:GetWindowScale() == scalePercent end,
        function(data)
          window:SetWindowScale(data)
          if onRefresh then
            onRefresh()
          end
        end,
        scalePercent
      )
    end

    local windowColor = window:GetWindowColor()
    local colorInfo = {
      r = windowColor.r,
      g = windowColor.g,
      b = windowColor.b,
      opacity = windowColor.a,
      swatchFunc = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = ColorPickerFrame:GetColorAlpha()
        if r then
          ---@type ColorTable
          local color = {
            r = r,
            g = g,
            b = b,
            a = a or windowColor.a,
          }
          window:SetWindowColor(color)
          if onRefresh then
            onRefresh()
          end
        end
      end,
      opacityFunc = function() end,
      cancelFunc = function(color)
        if color.r then
          ---@type ColorTable
          local restored = {
            r = color.r,
            g = color.g,
            b = color.b,
            a = color.a or windowColor.a,
          }
          window:SetWindowColor(restored)
          if onRefresh then
            onRefresh()
          end
        end
      end,
      hasOpacity = 1,
    }
    rootMenu:CreateColorSwatch(
      "Background color",
      function()
        ColorPickerFrame:SetupColorPickerAndShow(colorInfo)
      end,
      colorInfo
    )

    rootMenu:CreateCheckbox(
      "Show the border",
      function() return window:GetBorderShown() end,
      function()
        window:SetBorderShown(not window:GetBorderShown())
        if onRefresh then
          onRefresh()
        end
      end
    )
  end

  if window.options.border > 0 then
    ---@diagnostic disable-next-line: assign-type-mismatch
    window.border = CreateFrame("Frame", "$parentBorder", window, "BackdropTemplate")
    window.border:SetPoint("TOPLEFT", window, "TOPLEFT", -3, 3)
    window.border:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 3, -3)
    window.border:SetBackdrop({edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 16, insets = {left = window.options.border, right = window.options.border, top = window.options.border, bottom = window.options.border}})
    window.border:SetBackdropBorderColor(0, 0, 0, .5)
    window.border:Show()
  end

  if window.options.titlebar then
    window.titlebar = CreateFrame("Frame", "$parentTitleBar", window)
    window.titlebar:EnableMouse(true)
    window.titlebar:RegisterForDrag("LeftButton")
    window.titlebar:SetScript("OnDragStart", function() window:StartMoving() end)
    window.titlebar:SetScript("OnDragStop", function()
      window:StopMovingOrSizing()
      window:SaveSettings()
    end)
    window.titlebar:SetPoint("TOPLEFT", window, "TOPLEFT")
    window.titlebar:SetPoint("TOPRIGHT", window, "TOPRIGHT")
    window.titlebar:SetHeight(LiqUI.Constants.layout.sizes.titlebar.height)
    SetBackgroundColor(window.titlebar, 0, 0, 0, 0.5)
    window.titlebar.icon = window.titlebar:CreateTexture("$parentIcon", "ARTWORK")
    window.titlebar.icon:SetPoint("LEFT", window.titlebar, "LEFT", 6, 0)
    window.titlebar.icon:SetSize(20, 20)
    if window.options.icon then
      window.titlebar.icon:SetTexture(window.options.icon)
    else
      window.titlebar.icon:Hide()
    end
    window.titlebar.title = window.titlebar:CreateFontString("$parentText", "OVERLAY")
    local titleLeft = window.options.icon and (20 + LiqUI.Constants.layout.sizes.padding) or
      LiqUI.Constants.layout.sizes.padding
    window.titlebar.title:SetPoint("LEFT", window.titlebar, "LEFT", titleLeft, 0)
    window.titlebar.title:SetFontObject("SystemFont_Med3")
    window.titlebar.title:SetText(window.options.title or window.options.name)
    window.titlebar.CloseButton = CreateFrame("Button", "$parentCloseButton", window.titlebar)
    window.titlebar.CloseButton:SetPoint("RIGHT", window.titlebar, "RIGHT", 0, 0)
    window.titlebar.CloseButton:SetSize(LiqUI.Constants.layout.sizes.titlebar.height,
                                        LiqUI.Constants.layout.sizes.titlebar.height)
    window.titlebar.CloseButton:RegisterForClicks("AnyUp")
    window.titlebar.CloseButton:SetScript("OnClick", function()
      window:Close()
    end)
    window.titlebar.CloseButton.Icon = window.titlebar.CloseButton:CreateTexture(nil, "ARTWORK")
    window.titlebar.CloseButton.Icon:SetPoint("CENTER", window.titlebar.CloseButton, "CENTER")
    window.titlebar.CloseButton.Icon:SetSize(10, 10)
    window.titlebar.CloseButton.Icon:SetTexture(LiqUI.Constants.layout.media.iconClose)
    window.titlebar.CloseButton.Icon:SetVertexColor(0.7, 0.7, 0.7, 1)
    window.titlebar.CloseButton:SetScript("OnEnter", function()
      window.titlebar.CloseButton.Icon:SetVertexColor(1, 1, 1, 1)
      SetBackgroundColor(window.titlebar.CloseButton, 1, 0, 0, 0.2)
      GameTooltip:ClearAllPoints()
      GameTooltip:ClearLines()
      GameTooltip:SetOwner(window.titlebar.CloseButton, "ANCHOR_TOP")
      GameTooltip:SetText("Close the window", 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    window.titlebar.CloseButton:SetScript("OnLeave", function()
      window.titlebar.CloseButton.Icon:SetVertexColor(0.7, 0.7, 0.7, 1)
      SetBackgroundColor(window.titlebar.CloseButton, 1, 1, 1, 0)
      GameTooltip:Hide()
    end)

    if window.options.windowOptionsMenu ~= nil then
      error("LiqUI Window: windowOptionsMenu was removed; use onSettingsMenu or omit for window-only menu", 2)
    end

    window.titlebar.SettingsButton = CreateFrame("DropdownButton", "$parentSettingsButton", window.titlebar)
    window.titlebar.SettingsButton.menuGenerator = function(_, rootMenu)
      if window.options.onSettingsMenu then
        window.options.onSettingsMenu(window, rootMenu)
      end
      window:AppendWindowOptionsMenu(rootMenu)
    end
    window.titlebar.SettingsButton.Icon = window.titlebar.SettingsButton:CreateTexture(nil, "ARTWORK")
    window.titlebar.SettingsButton.Icon:SetPoint("CENTER", window.titlebar.SettingsButton, "CENTER")
    window.titlebar.SettingsButton.Icon:SetSize(12, 12)
    window.titlebar.SettingsButton.Icon:SetTexture(LiqUI.Constants.layout.media.iconSettings)
    window.titlebar.SettingsButton.Icon:SetVertexColor(0.7, 0.7, 0.7, 1)
    window.titlebar.SettingsButton:SetSize(LiqUI.Constants.layout.sizes.titlebar.height,
                                           LiqUI.Constants.layout.sizes.titlebar.height)
    window.titlebar.SettingsButton:SetScript("OnEnter", function()
      window.titlebar.SettingsButton.Icon:SetVertexColor(0.9, 0.9, 0.9, 1)
      SetBackgroundColor(window.titlebar.SettingsButton, 1, 1, 1, 0.05)
      GameTooltip:SetOwner(window.titlebar.SettingsButton, "ANCHOR_TOP")
      GameTooltip:SetText("Settings", 1, 1, 1, 1, true)
      GameTooltip:AddLine("Window scale, color, and border.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                          NORMAL_FONT_COLOR.b, true)
      GameTooltip:Show()
    end)
    window.titlebar.SettingsButton:SetScript("OnLeave", function()
      window.titlebar.SettingsButton.Icon:SetVertexColor(0.7, 0.7, 0.7, 1)
      SetBackgroundColor(window.titlebar.SettingsButton, 1, 1, 1, 0)
      GameTooltip:Hide()
    end)
    window.titlebar.SettingsButton:Show()
  end

  local topOffset = window.options.titlebar and -LiqUI.Constants.layout.sizes.titlebar.height or 0

  -- Body
  ---@type LiqUI_WindowBody
  local body = CreateFrame("Frame", "$parentBody", window)
  window.body = body
  applyWindowContentLayout(body, window, topOffset)
  SetBackgroundColor(body, 0, 0, 0, 0)

  do
    ---@type LiqUI_WindowOverlay
    local overlay = CreateFrame("Frame", "$parentOverlay", window)
    window.overlay = overlay
    applyWindowContentLayout(overlay, window, topOffset)
    overlay:SetFrameLevel(window.body:GetFrameLevel() + 20)
    overlay:EnableMouse(true)
    overlay:Hide()
    overlay:SetScript("OnSizeChanged", function()
      applyOverlayTextWidth(window)
    end)

    overlay.text = overlay:CreateFontString(nil, "OVERLAY", LiqUI.Constants.layout.overlay.defaultFontObject)
    overlay.text:SetPoint("CENTER")
    overlay.text:SetWordWrap(true)
    overlay.text:SetJustifyH("CENTER")
    overlay.text:SetJustifyV("MIDDLE")

    ---@type LiqUI_WindowProgressBar
    local progressBar = CreateFrame("StatusBar", "$parentBar", overlay)
    overlay.bar = progressBar
    progressBar:SetPoint("TOP", overlay.text, "BOTTOM", 0, -12)
    progressBar:SetHeight(14)
    progressBar:SetFrameLevel(overlay:GetFrameLevel() + 1)
    progressBar:SetStatusBarTexture(LiqUI.Constants.layout.media.whiteSquare)
    progressBar:SetMinMaxValues(0, 1)
    progressBar:SetValue(0)
    local barFill = LiqUI.Constants.layout.colors.primary
    progressBar:SetStatusBarColor(barFill.r, barFill.g, barFill.b, barFill.a)
    progressBar.background = progressBar:CreateTexture(nil, "BACKGROUND")
    progressBar.background:SetAllPoints()
    progressBar.background:SetTexture(LiqUI.Constants.layout.media.whiteSquare)
    progressBar.background:SetVertexColor(0, 0, 0, 0.5)
    progressBar:Hide()
  end

  if window.options.titlebarButtons then
    for _, buttonConfig in ipairs(window.options.titlebarButtons) do
      window:AddTitlebarButton(buttonConfig)
    end
  elseif window.titlebar and window.titlebar.SettingsButton then
    repositionTitlebarButtons(window)
  end

  if window.options.width and window.options.height then
    window:SetBodySize(window.options.width, window.options.height)
  end

  window:SetScript("OnShow", function()
    window:Render()
    if window.options.onShow then
      window.options.onShow(window)
    end
  end)

  window:Render()
  window:Hide()
  table.insert(UISpecialFrames, window:GetName())
  return window
end

LiqUI:RegisterElement("Window", createWindow)
