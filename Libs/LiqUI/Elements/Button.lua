---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI then
  return
end

local TableMergeOptions = LiqUI.Utils.TableMergeOptions
local buttonChrome = LiqUI.Constants.button
local textColors = LiqUI.Constants.text

---@param color ColorRGBAData
---@return number, number, number, number
local function colorRGBA(color)
  return color.r, color.g, color.b, color.a
end

---@param color ColorMixin
---@return ColorRGBAData
local function colorTable(color)
  local r, g, b, a = color:GetRGBA()
  return {r = r, g = g, b = b, a = a}
end

---@param button LiqUI_ButtonInstance
local function hidePanelArt(button)
  if button.Left then
    button.Left:Hide()
  end
  if button.Middle then
    button.Middle:Hide()
  end
  if button.Right then
    button.Right:Hide()
  end
  local highlightTexture = button:GetHighlightTexture()
  if highlightTexture then
    highlightTexture:Hide()
  end
end

---@param button LiqUI_ButtonInstance
local function paintButton(button)
  local options = button.options
  local backgroundColor = options.backgroundColor
  local borderColor = options.borderColor
  local textColor = options.textColor
  if not button:IsEnabled() then
    backgroundColor = options.backgroundColorDisabled
    borderColor = options.borderColorDisabled
    textColor = options.textColorDisabled
  elseif button.isPressed then
    backgroundColor = options.backgroundColorPressed
    borderColor = options.borderColorHighlight
  elseif button:IsMouseOver() then
    backgroundColor = options.backgroundColorHover
    borderColor = options.borderColorHighlight
  end
  button:SetBackdropColor(colorRGBA(backgroundColor))
  button:SetBackdropBorderColor(colorRGBA(borderColor))
  button.Text:SetTextColor(colorRGBA(textColor))
end

---@param button LiqUI_ButtonInstance
local function layoutButton(button)
  local options = button.options
  local padding = options.padding
  button.Text:ClearAllPoints()
  button.Text:SetPoint("TOPLEFT", button, "TOPLEFT", padding, 0)
  button.Text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -padding, 0)
  button.Text:SetJustifyH("CENTER")
  button.Text:SetJustifyV("MIDDLE")
  button.Text:SetWordWrap(false)
  button.Text:SetMaxLines(1)

  local width = options.width
  if not width then
    width = (button.Text:GetStringWidth() or 0) + padding * 2
  end
  if options.maxWidth then
    width = math.min(width, options.maxWidth)
  end
  button:SetSize(width, options.height)
end

---@param button LiqUI_ButtonInstance
local function wireButton(button)
  button:SetScript("OnEnter", function()
    if not button:IsEnabled() then
      return
    end
    paintButton(button)
  end)
  button:SetScript("OnLeave", function()
    button.isPressed = false
    if not button:IsEnabled() then
      return
    end
    paintButton(button)
  end)
  button:SetScript("OnMouseDown", function()
    if not button:IsEnabled() then
      return
    end
    button.isPressed = true
    paintButton(button)
  end)
  button:SetScript("OnMouseUp", function()
    button.isPressed = false
    if not button:IsEnabled() then
      return
    end
    paintButton(button)
  end)
  button:SetScript("OnEnable", function()
    paintButton(button)
  end)
  button:SetScript("OnDisable", function()
    button.isPressed = false
    paintButton(button)
  end)
  button:SetScript("OnShow", function()
    hidePanelArt(button)
    paintButton(button)
  end)
end

---@param options LiqUI_ButtonOptions
---@return LiqUI_ButtonInstance
local function createButton(options)
  if not options then
    error("LiqUI Button: options is required", 2)
  end
  local buttonName = options.name
  if not buttonName or buttonName == "" then
    error("LiqUI Button: options.name is required", 2)
  end

  ---@type LiqUI_ButtonResolvedOptions
  local defaultOptions = {
    text = "",
    height = buttonChrome.height,
    padding = buttonChrome.padding,
    enabled = true,
    backgroundColor = colorTable(buttonChrome.backgroundColor),
    backgroundColorHover = colorTable(buttonChrome.backgroundColorHover),
    backgroundColorPressed = colorTable(buttonChrome.backgroundColorPressed),
    backgroundColorDisabled = colorTable(buttonChrome.backgroundColorDisabled),
    borderColor = colorTable(buttonChrome.borderColor),
    borderColorHighlight = colorTable(buttonChrome.borderColorHighlight),
    borderColorDisabled = colorTable(buttonChrome.borderColorDisabled),
    textColor = colorTable(textColors.defaultColor),
    textColorDisabled = colorTable(textColors.placeholderColor),
  }
  ---@type LiqUI_ButtonResolvedOptions
  local mergedOptions = {}
  TableMergeOptions(mergedOptions, defaultOptions)
  TableMergeOptions(mergedOptions, options)

  local frameName = "LiqUIButton" .. buttonName:gsub("[^%w]", "")
  local parent = mergedOptions.parent or UIParent
  ---@class LiqUI_ButtonInstance
  local button = CreateFrame("Button", frameName, parent, "UIPanelButtonTemplate, BackdropTemplate")
  button.options = mergedOptions

  hidePanelArt(button)
  button.backdropInfo = LiqUI.Constants.control.backdrop
  button:ApplyBackdrop()
  button:SetPushedTextOffset(0, 0)
  button:SetNormalFontObject("GameFontHighlight")
  button:SetHighlightFontObject("GameFontHighlight")
  button:SetDisabledFontObject("GameFontHighlight")
  button:SetText(mergedOptions.text)
  layoutButton(button)
  wireButton(button)
  if mergedOptions.onClick then
    button:SetScript("OnClick", mergedOptions.onClick)
  end
  button:SetEnabled(mergedOptions.enabled ~= false)
  paintButton(button)
  return button
end

LiqUI:RegisterElement("Button", createButton)
