---@class AE_Addon
local addon = select(2, ...)

---@class AE_Module_DailyDelves
local Module = addon.Core:NewModule("DailyDelves", "AceConsole-3.0", "AceTimer-3.0")
addon.Module_DailyDelves = Module

local Data = addon.Data
local LibLiqUI = addon.Libs.LiqUI

local WINDOW_WIDTH = 560
local WINDOW_HEIGHT = 430
local ROW_HEIGHT = 24
local HIGH_TIER = {S = true, A = true}

local zoneIcons = {
  [2395] = "majorfactions_icons_Light512",
  [2393] = "majorfactions_icons_Light512",
  [2424] = "majorfactions_icons_Light512",
  [2413] = "majorfactions_icons_root512",
  [2405] = "majorfactions_icons_sky512",
  [2437] = "majorfactions_icons_origin512",
  [2536] = "majorfactions_icons_origin512",
  [2512] = "majorfactions_icons_zuljarra512",
}

local delves = {
  ["The Darkway"] = {mapId = 2393, waypoint = {mapId = 2393, x = 39.3, y = 32.1}, variants = {
    ["Ogre Powered"] = "S", ["Eggsplosive Growth"] = "A", ["Focusers Under Pressure"] = "C", ["Leyline Technician"] = "D",
  }},
  ["Collegiate Calamity"] = {mapId = 2393, waypoint = {mapId = 2393, x = 40.76, y = 54.06}, variants = {
    ["Invasive Glow"] = "A", ["Academy Under Siege"] = "A", ["Faculty of Fear"] = "D", ["An Elementary Antidote"] = "D",
  }},
  ["Parhelion Plaza"] = {mapId = 2424, waypoint = {mapId = 2424, x = 47.84, y = 41.64}, variants = {
    ["Holding the Line"] = "A", ["Caustic Crush"] = "D", ["March of the Arcane Brigade"] = "D", ["Bombing Run"] = "D",
  }},
  ["The Shadow Enclave"] = {mapId = 2395, waypoint = {mapId = 2395, x = 45.4, y = 86.0}, variants = {
    ["Traitor's Due"] = "B", ["Mirror Shine"] = "D", ["Shadowy Supplies"] = "D", ["Infiltrate and Ameliorate"] = "D",
  }},
  ["Twilight Crypts"] = {mapId = 2437, waypoint = {mapId = 2437, x = 25.4, y = 84.3}, variants = {
    ["Party Crasher"] = "A", ["Trapped!"] = "C", ["Loosed Loa"] = "D", ["Why Did it Have to Be Snakes?"] = "D",
  }},
  ["Atal'Aman"] = {mapId = 2536, waypoint = {mapId = 2437, x = 24.8, y = 53.0}, variants = {
    ["Toadly Unbecoming"] = "B", ["Venomous Vapors"] = "C", ["Totem Annihilation"] = "C", ["Ritual Interrupted"] = "D",
  }},
  ["The Gulf of Memory"] = {mapId = 2413, waypoint = {mapId = 2413, x = 36.7, y = 49.6}, variants = {
    ["Sporasaur Special"] = "S", ["Alnmoth Munchies"] = "D", ["Descent of the Haranir"] = "D",
  }},
  ["The Grudge Pit"] = {mapId = 2413, waypoint = {mapId = 2413, x = 70.4, y = 64.8}, variants = {
    ["Arena Champion"] = "C", ["Dastardly Rotstalk"] = "D", ["Lightbloom Invasion"] = "D", ["Fungal Pharmacon"] = "D",
  }},
  ["Sunkiller Sanctum"] = {mapId = 2405, waypoint = {mapId = 2405, x = 54.8, y = 47.1}, variants = {
    ["Core of the Problem"] = "B", ["Not What I Expected"] = "D", ["The Gravitational Effect"] = "D",
  }},
  ["Shadowguard Point"] = {mapId = 2405, waypoint = {mapId = 2405, x = 37.38, y = 47.7}, variants = {
    ["Calamitous"] = "C", ["Basalisk Blitz"] = "D", ["Captured Wildlife"] = "D", ["Stolen Mana"] = "D",
  }},
  ["The Ring of Glory"] = {mapId = 2512, waypoint = {mapId = 2512, x = 71.2, y = 56.5}, variants = {
    ["Open Night"] = "S", ["Adopt-a-thon"] = "S", ["Game Day"] = "C",
  }},
  ["Gnarldor Isle"] = {mapId = 2512, waypoint = {mapId = 2512, x = 64.45, y = 77.73}, variants = {
    ["Speaking Their Language"] = "D", ["Olds and Ends"] = "D", ["Minchi's Osseous Adventure"] = "D",
  }},
}

local difficultyConfig = {
  S = {name = "Fast",  color = "|cff22C55E", priority = 1},
  A = {name = "Good",  color = "|cff84CC16", priority = 2},
  B = {name = "Ok",    color = "|cffF97316", priority = 3},
  C = {name = "Bad",   color = "|cffEF4444", priority = 4},
  D = {name = "Awful", color = "|cff991B1B", priority = 5},
}

local function levenshteinDistance(str1, str2)
  local len1, len2 = #str1, #str2
  local matrix = {}
  for i = 0, len1 do matrix[i] = {[0] = i} end
  for j = 0, len2 do matrix[0][j] = j end
  for i = 1, len1 do
    for j = 1, len2 do
      local cost = str1:sub(i, i) == str2:sub(j, j) and 0 or 1
      matrix[i][j] = math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost)
    end
  end
  return matrix[len1][len2]
end

local function similarity(str1, str2)
  if not str1 or not str2 then return 0 end
  local maxLen = math.max(#str1, #str2)
  if maxLen == 0 then return 100 end
  local distance = levenshteinDistance(str1:lower(), str2:lower())
  return ((maxLen - distance) / maxLen) * 100
end

local function bestVariantMatch(targetVariant, variants)
  local bestMatch, bestSimilarity
  bestSimilarity = 0
  for variantName in pairs(variants) do
    local value = similarity(targetVariant, variantName)
    if value >= 80 and value > bestSimilarity then
      bestMatch, bestSimilarity = variantName, value
    end
  end
  return bestMatch
end

local function getCurrentVariants()
  local activeVariants = {}
  local processedMaps = {}
  for _, delveInfo in pairs(delves) do
    local mapId = delveInfo.mapId
    if mapId and not processedMaps[mapId] then
      processedMaps[mapId] = true
      local pois = C_AreaPoiInfo.GetDelvesForMap(mapId)
      if type(pois) == "table" then
        for _, areaPoiID in ipairs(pois) do
          local poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(mapId, areaPoiID)
          if poiInfo and poiInfo.tooltipWidgetSet then
            local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(poiInfo.tooltipWidgetSet)
            if type(widgets) == "table" then
              for _, widget in pairs(widgets) do
                if widget and widget.widgetType == 8 and widget.widgetID then
                  local widgetInfo = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo(widget.widgetID)
                  if widgetInfo and widgetInfo.text then
                    local variantName = widgetInfo.text:match("WHITE_FONT_COLOR:(.*)")
                    if variantName then
                      variantName = strtrim(variantName)
                      local description = poiInfo.description or ""
                      activeVariants[variantName] = description:find("Bountiful") and "bountiful" or true
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return activeVariants
end

local function getActiveDelves()
  local detected = getCurrentVariants()
  local activeDelves = {}
  for delveName, delveInfo in pairs(delves) do
    for detectedVariant, status in pairs(detected) do
      local matched = bestVariantMatch(detectedVariant, delveInfo.variants)
      if matched then
        local difficulty = delveInfo.variants[matched]
        table.insert(activeDelves, {
          delveName = delveName,
          mapId = delveInfo.mapId,
          variantName = matched,
          difficulty = difficulty,
          priority = difficultyConfig[difficulty].priority,
          isBountiful = status == "bountiful",
        })
        break
      end
    end
  end
  table.sort(activeDelves, function(a, b)
    if a.priority == b.priority then return a.delveName < b.delveName end
    return a.priority < b.priority
  end)
  return activeDelves
end

local function shortDelveName(name)
  return name:gsub("^The ", ""):gsub(" Sanctum$", ""):gsub(" Cavern$", ""):gsub(" Deeps$", "")
end

local function formatResetTime()
  if not C_DateAndTime or not C_DateAndTime.GetSecondsUntilDailyReset then return nil end
  local seconds = C_DateAndTime.GetSecondsUntilDailyReset()
  if type(seconds) ~= "number" or seconds < 0 then return nil end
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  return format("Daily reset in %dh %02dm", hours, minutes)
end

local function setupCheckButton(button, label)
  button:SetSize(24, 24)
  button.Text:SetText(label)
  button.Text:SetFontObject("GameFontHighlightSmall")
end

local function increaseFontSize(fontString, amount)
  local font, size, flags = fontString:GetFont()
  if font and size then
    fontString:SetFont(font, size + amount, flags)
  end
end

local function setDelveWaypoint(delveName)
  local delveInfo = delves[delveName]
  local waypoint = delveInfo and delveInfo.waypoint
  if not waypoint or not C_Map or not C_Map.SetUserWaypoint or not UiMapPoint then return end

  local point = UiMapPoint.CreateFromCoordinates(waypoint.mapId, waypoint.x / 100, waypoint.y / 100)
  if not point then return end

  C_Map.SetUserWaypoint(point)
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
  end

  if WorldMapFrame then
    if not WorldMapFrame:IsShown() then
      if OpenWorldMap then
        OpenWorldMap(waypoint.mapId)
      else
        ShowUIPanel(WorldMapFrame)
      end
    end
    if WorldMapFrame.SetMapID then
      WorldMapFrame:SetMapID(waypoint.mapId)
    end
  end
end

function Module:OnInitialize()
  self:CreateWindow()
end

function Module:CreateWindow()
  if self.window then return end
  local windows = Data.db.global.liqui.windows
  self.window = LibLiqUI:NewElement("Window", {
    name = addon.name .. "DailyDelves",
    storage = windows.DailyDelves,
    title = "Daily Delves",
    onShow = function() Module:Render() end,
  })
  self.window:SetBodySize(WINDOW_WIDTH, WINDOW_HEIGHT)

  local body = self.window.body
  self.controls = CreateFrame("Frame", "$parentControls", body)
  self.controls:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -8)
  self.controls:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -8)
  self.controls:SetHeight(32)

  self.highTier = CreateFrame("CheckButton", "$parentHighTier", self.controls, "UICheckButtonTemplate")
  setupCheckButton(self.highTier, "Show only High Tier")
  self.highTier:SetPoint("LEFT", self.controls, "LEFT", 0, 0)
  self.highTier:SetScript("OnClick", function(button)
    Data.db.global.dailyDelves.showOnlyHighTier = button:GetChecked() and true or false
    Module:Render()
  end)

  self.listAll = CreateFrame("CheckButton", "$parentListAll", self.controls, "UICheckButtonTemplate")
  setupCheckButton(self.listAll, "List all stories")
  self.listAll:SetPoint("LEFT", self.highTier.Text, "RIGHT", 26, 0)
  self.listAll:SetScript("OnClick", function(button)
    Data.db.global.dailyDelves.listAllStories = button:GetChecked() and true or false
    Module:Render()
  end)

  self.resetText = self.controls:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.resetText:SetPoint("RIGHT", self.controls, "RIGHT", 0, 0)

  self.divider = body:CreateTexture(nil, "ARTWORK")
  self.divider:SetColorTexture(1, 1, 1, 0.12)
  self.divider:SetPoint("TOPLEFT", self.controls, "BOTTOMLEFT", 0, -4)
  self.divider:SetPoint("TOPRIGHT", self.controls, "BOTTOMRIGHT", 0, -4)
  self.divider:SetHeight(1)

  self.listArea = CreateFrame("Frame", "$parentListArea", body)
  self.listArea:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -53)
  -- Leave a small visual gutter above the bottom edge of the window so the
  -- last visible Delve row never sits flush against the frame border.
  self.listArea:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 10)

  -- Use LiqUI's native MinimalScrollBar, matching the scrollbar styling used by
  -- the addon's own settings/UI components instead of UIPanelScrollFrameTemplate.
  self.scrollArea = LibLiqUI.Utils.CreateScrollArea(self.listArea, {
    vertical = true,
    name = "$parentDailyDelvesScrollArea",
    wheelPanExtent = ROW_HEIGHT,
  })
  self.scrollArea:SetAllPoints(self.listArea)
  self.scroll = self.scrollArea.verticalScrollBox
  self.content = self.scrollArea.content
  self.content:SetWidth(WINDOW_WIDTH)
  self.content:SetHeight(1)
  self.scrollBar = self.scrollArea.verticalScrollBar
  if self.scrollBar then
    self.scrollBar:SetFrameLevel(self.listArea:GetFrameLevel() + 10)
  end
  self.rows = {}
end

function Module:GetRow(index)
  local row = self.rows[index]
  if row then return row end
  row = CreateFrame("Button", "$parentRow" .. index, self.content)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("LEFT", self.content, "LEFT", 0, 0)
  row:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.025 or 0.01)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  increaseFontSize(row.text, 2)
  row.text:SetPoint("LEFT", row, "LEFT", 12, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -30, 0)
  row.text:SetJustifyH("LEFT")
  row:SetScript("OnEnter", function(button)
    button.bg:SetColorTexture(1, 1, 1, 0.08)
    if button.delveName and delves[button.delveName] and delves[button.delveName].waypoint then
      local waypoint = delves[button.delveName].waypoint
      GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
      GameTooltip:AddLine(button.delveName, 1, 1, 1)
      GameTooltip:AddLine(format("Click to mark entrance on the map (%.1f, %.1f)", waypoint.x, waypoint.y), 0.75, 0.82, 0.9, true)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(button)
    local alpha = button.rowIndex and (button.rowIndex % 2 == 0 and 0.035 or 0.015) or 0.015
    button.bg:SetColorTexture(1, 1, 1, alpha)
    GameTooltip:Hide()
  end)
  row:SetScript("OnClick", function(button, mouseButton)
    if mouseButton == "LeftButton" and button.delveName then
      setDelveWaypoint(button.delveName)
    end
  end)
  self.rows[index] = row
  return row
end

function Module:Render()
  if not self.window then self:CreateWindow() end
  if not self.window:IsVisible() then return end

  local settings = Data.db.global.dailyDelves
  self.highTier:SetChecked(settings.showOnlyHighTier)
  self.listAll:SetChecked(settings.listAllStories)
  self.resetText:SetText(formatResetTime() or "Resets daily")

  for _, row in ipairs(self.rows) do row:Hide() end

  local activeDelves = getActiveDelves()
  local activeByDelve = {}
  for _, entry in ipairs(activeDelves) do activeByDelve[entry.delveName] = entry end

  local display = {}
  if settings.listAllStories then
    local delveGroups = {}
    for delveName, delveInfo in pairs(delves) do
      local stories = {}
      local active = activeByDelve[delveName]
      for storyName, difficulty in pairs(delveInfo.variants) do
        if not settings.showOnlyHighTier or HIGH_TIER[difficulty] then
          table.insert(stories, {
            storyName = storyName,
            difficulty = difficulty,
            isToday = active and active.variantName == storyName or false,
          })
        end
      end
      -- Story order follows the same ranking logic as the Delve groups:
      -- today's story first, then best tier -> worst tier.
      table.sort(stories, function(a, b)
        if a.isToday ~= b.isToday then return a.isToday end
        local pa, pb = difficultyConfig[a.difficulty].priority, difficultyConfig[b.difficulty].priority
        if pa == pb then return a.storyName < b.storyName end
        return pa < pb
      end)
      if #stories > 0 then
        local bestPriority = 999
        local todayVisible = false
        for _, story in ipairs(stories) do
          bestPriority = math.min(bestPriority, difficultyConfig[story.difficulty].priority)
          if story.isToday then todayVisible = true end
        end
        table.insert(delveGroups, {
          delveName = delveName,
          delveInfo = delveInfo,
          stories = stories,
          todayVisible = todayVisible,
          priority = bestPriority,
          isBountiful = active and active.isBountiful or false,
        })
      end
    end

    -- Delve group ranking: visible Today story first, then best visible tier,
    -- then Bountiful, followed by name for a stable tie-breaker.
    table.sort(delveGroups, function(a, b)
      if a.todayVisible ~= b.todayVisible then return a.todayVisible end
      if a.priority ~= b.priority then return a.priority < b.priority end
      if a.isBountiful ~= b.isBountiful then return a.isBountiful end
      return a.delveName < b.delveName
    end)

    for _, group in ipairs(delveGroups) do
      local delveName = group.delveName
      local delveInfo = group.delveInfo
      table.insert(display, {kind = "header", delveName = delveName, mapId = delveInfo.mapId, active = activeByDelve[delveName]})
      for _, story in ipairs(group.stories) do
        table.insert(display, {
          kind = "story", delveName = delveName, mapId = delveInfo.mapId,
          variantName = story.storyName, difficulty = story.difficulty,
          isToday = story.isToday,
          isBountiful = activeByDelve[delveName] and activeByDelve[delveName].isBountiful,
        })
      end
    end
  else
    for _, entry in ipairs(activeDelves) do
      if not settings.showOnlyHighTier or HIGH_TIER[entry.difficulty] then
        table.insert(display, entry)
      end
    end
  end

  local y = 0
  local rowIndex = 0
  if #display == 0 then
    rowIndex = 1
    local row = self:GetRow(rowIndex)
    row.rowIndex = rowIndex
    row.delveName = nil
    row.bg:SetColorTexture(1, 1, 1, rowIndex % 2 == 0 and 0.035 or 0.015)
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
    row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, 0)
    row.text:SetText("|cff9CA3AFNo matching Delves found for the current filters.|r")
    row:Show()
    y = ROW_HEIGHT
  else
    for _, entry in ipairs(display) do
      rowIndex = rowIndex + 1
      local row = self:GetRow(rowIndex)
      row.rowIndex = rowIndex
      row.delveName = entry.delveName
      row.bg:SetColorTexture(1, 1, 1, rowIndex % 2 == 0 and 0.035 or 0.015)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
      row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -y)
      row:SetHeight(ROW_HEIGHT)
      local icon = zoneIcons[entry.mapId] or "majorfactions_icons_candle512"
      if entry.kind == "header" then
        row.text:SetText(format("|A:%s:16:16:0:0|a |cffCBD5E1%s|r", icon, shortDelveName(entry.delveName)))
      else
        local config = difficultyConfig[entry.difficulty]
        local prefix = entry.kind == "story" and "   " or ""
        local bountiful = entry.isBountiful and " |A:delves-bountiful:16:16:0:0|a" or ""
        local today = entry.isToday and " |cff7DD3FC(Today)|r" or ""
        local name = entry.kind == "story" and entry.variantName or (shortDelveName(entry.delveName) .. " |cff5C5C5C- " .. entry.variantName .. "|r")
        row.text:SetText(format("%s|A:%s:16:16:0:0|a %s%s%s |cff6B7280—|r %s%s|r", prefix, icon, name, bountiful, today, config.color, config.name))
      end
      row:Show()
      y = y + ROW_HEIGHT
    end
  end
  local width = self.listArea:GetWidth() or WINDOW_WIDTH
  self.content:SetWidth(math.max(1, width))
  self.content:SetHeight(math.max(1, y))
  self.scrollArea:UpdateLayout(width, math.max(1, y))

  if self.scrollBar then
    -- LiqUI's layout anchors the bar flush to the viewport by default. Keep it
    -- inside the Delves window and lift the bottom edge slightly so the thumb/
    -- track never spills below the frame border.
    self.scrollBar:ClearAllPoints()
    self.scrollBar:SetPoint("TOPRIGHT", self.listArea, "TOPRIGHT", -3, -2)
    self.scrollBar:SetPoint("BOTTOMRIGHT", self.listArea, "BOTTOMRIGHT", -3, 2)
  end
end

function Module:Toggle()
  if not self.window then self:CreateWindow() end
  self.window:Toggle()
  if self.window:IsVisible() then
    self.window:Raise()
    self:Render()
  end
end
