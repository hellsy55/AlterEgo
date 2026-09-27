---@class AE_Addon
local addon = select(2, ...)

---@class AE_Module_RaidLockouts
local Module = addon.Core:NewModule("RaidLockouts", "AceConsole-3.0")
addon.Module_RaidLockouts = Module

local Data = addon.Data
local Constants = addon.Constants
local LibLiqUI = addon.Libs.LiqUI
local SetHighlightColor = LibLiqUI.Utils.SetHighlightColor

-- This protocol is deliberately separate from AlterEgo's account-sync protocol.
-- Raid lockouts are group information, not account data, and must work even when
-- Sync is disabled or uses a different password.
local COMM_PREFIX = "AERaidLock1"
local PROTOCOL_VERSION = 1
local SHARED_DIFFICULTIES = {14, 15, 16} -- Normal, Heroic, Mythic
local DISPLAY_DIFFICULTIES = {16, 15, 14} -- stack Mythic, Heroic, Normal
local RESPONSE_STALE_SECONDS = 120
local REQUEST_THROTTLE_SECONDS = 5

local WINDOW_WIDTH = 620
local WINDOW_HEIGHT = 470
local ROW_HEIGHT = 24
local DIFFICULTY_LINE_HEIGHT = 20
local ICON_SIZE = 17
local ICON_GAP = 5
local NAME_X = 8
local STATUS_X = 210
local BOSSES_X = 330

local STATUS_ORDER = {
  saved = 1,
  nodata = 2,
  unsaved = 3,
}

local FLEX_DIFFICULTY_BASE = {
  [233] = 16, -- Mythic - Flexible Raiding -> Mythic
}

local responses = {}
local lastRequestAt = 0
local responsePending = false
local lastStateSentAt = 0

local function baseDifficultyID(difficultyID)
  if not difficultyID then return difficultyID end
  local base = difficultyID
  if GetBaseDifficultyID then
    base = GetBaseDifficultyID(difficultyID) or difficultyID
  end
  return FLEX_DIFFICULTY_BASE[base] or base
end

local function difficultyInfo(difficultyID)
  for _, difficulty in ipairs(Data:GetRaidDifficulties(true) or {}) do
    if difficulty.id == difficultyID then
      return difficulty
    end
  end
  return nil
end

local function currentSeasonID()
  local seasonID = Data:GetCurrentSeason()
  return seasonID
end

---The fixed current-season boss catalog used both by the UI and the wire format.
---Raid order intentionally follows Data:GetRaids(): for Season 18 this places
---all eight The Venomous Abyss bosses first and Nymrissa Wavecaller last.
local function buildBossCatalog()
  local bosses = {}
  for _, raid in ipairs(Data:GetRaids() or {}) do
    local count = raid.numEncounters or #(raid.encounters or {})
    for encounterIndex = 1, count do
      local encounter = raid.encounters and raid.encounters[encounterIndex]
      table.insert(bosses, {
        raid = raid,
        index = encounterIndex,
        name = encounter and encounter.name or format("%s (%d)", raid.name or RAID, encounterIndex),
      })
    end
  end
  return bosses
end

local function buildKilledLookup(character)
  local lookup = {}
  local now = time()
  for _, instance in ipairs(character and character.raids and character.raids.savedInstances or {}) do
    local expired = instance.expires and instance.expires > 0 and instance.expires <= now
    if not expired then
      local difficultyID = baseDifficultyID(instance.difficultyID)
      for _, encounter in ipairs(instance.encounters or {}) do
        if encounter.isKilled then
          lookup[format("%s:%s:%s", tostring(instance.instanceID), tostring(difficultyID), tostring(encounter.index))] = true
        end
      end
    end
  end
  return lookup
end

local function buildDifficultySlots(character, difficultyID)
  local lookup = buildKilledLookup(character)
  local slots = {}
  local killed = 0
  for _, boss in ipairs(buildBossCatalog()) do
    local key = format("%s:%s:%s", tostring(boss.raid.instanceID), tostring(difficultyID), tostring(boss.index))
    local isKilled = lookup[key] == true
    table.insert(slots, isKilled)
    if isKilled then
      killed = killed + 1
    end
  end
  return slots, killed
end

local function buildSharedState()
  local character = Data:GetCharacter()
  if not character then return nil end

  local catalog = buildBossCatalog()
  local masks = {}
  for _, difficultyID in ipairs(SHARED_DIFFICULTIES) do
    local slots = buildDifficultySlots(character, difficultyID)
    local mask = 0
    for i, killed in ipairs(slots) do
      if killed then
        mask = mask + 2 ^ (i - 1)
      end
    end
    masks[difficultyID] = mask
  end

  return {
    seasonID = currentSeasonID(),
    total = #catalog,
    masks = masks,
  }
end

local function parseSharedState(seasonID, total, normalMask, heroicMask, mythicMask)
  local catalog = buildBossCatalog()
  if tonumber(seasonID) ~= currentSeasonID() then return nil end
  if tonumber(total) ~= #catalog then return nil end

  local masks = {
    [14] = tonumber(normalMask) or 0,
    [15] = tonumber(heroicMask) or 0,
    [16] = tonumber(mythicMask) or 0,
  }

  local parsed = {}
  for _, difficultyID in ipairs(SHARED_DIFFICULTIES) do
    local slots = {}
    local killed = 0
    local mask = masks[difficultyID]
    for i = 1, #catalog do
      local isKilled = math.floor(mask / (2 ^ (i - 1))) % 2 == 1
      slots[i] = isKilled
      if isKilled then killed = killed + 1 end
    end
    parsed[difficultyID] = {
      slots = slots,
      killed = killed,
      total = #catalog,
    }
  end
  return parsed
end

local function normalizedRealmName(realm)
  if realm and realm ~= "" then
    return realm:gsub("%s+", "")
  end
  if GetNormalizedRealmName then
    local normalized = GetNormalizedRealmName()
    if normalized and normalized ~= "" then return normalized end
  end
  return (GetRealmName() or ""):gsub("%s+", "")
end

local function unitKey(unit)
  local name, realm
  if UnitFullName then
    name, realm = UnitFullName(unit)
  end
  if not name or name == "" then
    name, realm = UnitName(unit)
  end
  if not name or name == "" then return nil end
  return name .. "-" .. normalizedRealmName(realm)
end

local function normalizeSender(sender)
  if not sender or sender == "" then return nil end
  local name, realm = sender:match("^([^%-]+)%-(.+)$")
  if not name then
    name = sender
  end
  return name .. "-" .. normalizedRealmName(realm)
end

local function groupMembers()
  if not IsInRaid() then return nil end

  local members = {}
  for i = 1, GetNumGroupMembers() do
    local unit = "raid" .. i
    local key = unitKey(unit)
    if key then
      local name, realm
      if UnitFullName then
        name, realm = UnitFullName(unit)
      end
      if not name or name == "" then
        name, realm = UnitName(unit)
      end
      local _, classFile = UnitClass(unit)
      table.insert(members, {
        key = key,
        unit = unit,
        name = name or key,
        realm = normalizedRealmName(realm),
        classFile = classFile,
        isSelf = UnitIsUnit(unit, "player"),
      })
    end
  end
  return members
end

local function memberStatus(member, difficultyID)
  if member.isSelf then
    local character = Data:GetCharacter()
    local slots, killed = buildDifficultySlots(character, difficultyID)
    return killed > 0 and "saved" or "unsaved", killed, slots, #slots
  end

  local response = responses[member.key]
  if not response or response.incompatible or not response.state then
    return "nodata", 0, {}, #buildBossCatalog()
  end
  if time() - (response.receivedAt or 0) > RESPONSE_STALE_SECONDS then
    return "nodata", 0, {}, #buildBossCatalog()
  end

  local state = response.state[difficultyID]
  if not state then
    return "nodata", 0, {}, #buildBossCatalog()
  end
  return state.killed > 0 and "saved" or "unsaved", state.killed, state.slots, state.total
end

local function buildRows(selectedDifficulties, sortColumn, sortAscending)
  local members = groupMembers()
  if not members then return nil end

  local rows = {}
  for _, member in ipairs(members) do
    local states = {}
    local totalKilled = 0
    local savedDifficulties = 0
    local unsavedDifficulties = 0
    local noDataDifficulties = 0

    for _, difficultyID in ipairs(selectedDifficulties) do
      local status, killed, slots, total = memberStatus(member, difficultyID)
      states[difficultyID] = {
        status = status,
        killed = killed,
        slots = slots,
        total = total,
      }
      totalKilled = totalKilled + killed
      if status == "saved" then
        savedDifficulties = savedDifficulties + 1
      elseif status == "unsaved" then
        unsavedDifficulties = unsavedDifficulties + 1
      else
        noDataDifficulties = noDataDifficulties + 1
      end
    end

    local overallStatus
    if savedDifficulties > 0 then
      overallStatus = "saved"
    elseif unsavedDifficulties > 0 then
      overallStatus = "unsaved"
    else
      overallStatus = "nodata"
    end

    table.insert(rows, {
      member = member,
      states = states,
      status = overallStatus,
      totalKilled = totalKilled,
      savedDifficulties = savedDifficulties,
      unsavedDifficulties = unsavedDifficulties,
      noDataDifficulties = noDataDifficulties,
    })
  end

  local function nameCompare(a, b)
    local comparison = strcmputf8i(a.member.name or "", b.member.name or "")
    if comparison == 0 then
      comparison = strcmputf8i(a.member.key or "", b.member.key or "")
    end
    return comparison
  end

  table.sort(rows, function(a, b)
    local comparison
    if sortColumn == "character" then
      comparison = nameCompare(a, b)
    elseif sortColumn == "bosses" then
      if a.totalKilled ~= b.totalKilled then
        comparison = a.totalKilled < b.totalKilled and -1 or 1
      else
        comparison = nameCompare(a, b)
      end
    else
      local aOrder = STATUS_ORDER[a.status] or 99
      local bOrder = STATUS_ORDER[b.status] or 99
      if aOrder ~= bOrder then
        comparison = aOrder < bOrder and -1 or 1
      elseif a.totalKilled ~= b.totalKilled then
        -- Within the same status, show the most progressed lockout first in
        -- the default direction, matching the old saved-first presentation.
        comparison = a.totalKilled > b.totalKilled and -1 or 1
      else
        comparison = nameCompare(a, b)
      end
    end

    if comparison == 0 then return false end
    if sortAscending then
      return comparison < 0
    end
    return comparison > 0
  end)
  return rows
end

local function currentRaidAndDifficulty()
  local inInstance, instanceType = IsInInstance()
  if not inInstance or instanceType ~= "raid" then return nil end

  local _, _, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
  if not instanceID then return nil end

  local raid
  for _, candidate in ipairs(Data:GetRaids() or {}) do
    if candidate.instanceID == instanceID then
      raid = candidate
      break
    end
  end
  if not raid then return nil end

  local difficulty = baseDifficultyID(difficultyID)
  if difficulty ~= 14 and difficulty ~= 15 and difficulty ~= 16 then
    return nil
  end
  return raid, difficulty, instanceID
end

local function playerRaidIndex()
  if not IsInRaid() then return 1 end
  for i = 1, GetNumGroupMembers() do
    if UnitIsUnit("raid" .. i, "player") then
      return i
    end
  end
  return 1
end

function Module:BroadcastState()
  if not IsInRaid() then return end
  local state = buildSharedState()
  if not state then return end

  local version = tostring(addon.version or "?"):gsub(";", "")
  local characterKey = (unitKey("player") or "?"):gsub(";", "")
  local message = table.concat({
    "S",
    PROTOCOL_VERSION,
    state.seasonID,
    state.total,
    state.masks[14] or 0,
    state.masks[15] or 0,
    state.masks[16] or 0,
    characterKey,
    version,
  }, ";")
  addon.Core:SendCommMessage(COMM_PREFIX, message, "RAID", nil, "ALERT")
  lastStateSentAt = GetTime()
end

function Module:RequestGroupState()
  if not IsInRaid() then
    self:RefreshWindow()
    return
  end

  local now = GetTime()
  if now - lastRequestAt < REQUEST_THROTTLE_SECONDS then
    self:RefreshWindow()
    return
  end
  lastRequestAt = now

  local catalog = buildBossCatalog()
  local message = table.concat({"Q", PROTOCOL_VERSION, currentSeasonID(), #catalog}, ";")
  addon.Core:SendCommMessage(COMM_PREFIX, message, "RAID", nil, "ALERT")

  -- Our own row never needs the network, but repaint immediately so a
  -- newly opened window already shows the local lockout while replies arrive.
  self:RefreshWindow()
end

function Module:OnRaidLockoutComm(prefix, message, distribution, sender)
  if prefix ~= COMM_PREFIX or distribution ~= "RAID" then return end
  if type(message) ~= "string" or message == "" then return end

  local messageType, protocol, seasonID, total, a, b, c, characterKey, version = strsplit(";", message)
  if tonumber(protocol) ~= PROTOCOL_VERSION then return end

  if messageType == "Q" then
    if tonumber(seasonID) ~= currentSeasonID() then return end
    if tonumber(total) ~= #buildBossCatalog() then return end
    if not IsInRaid() then return end

    -- Stagger a full raid's replies by roster position so 20-30 clients do
    -- not all try to speak on the same frame.
    if responsePending then return end
    responsePending = true
    local delay = math.min(1.5, 0.05 * playerRaidIndex())
    local sinceLast = GetTime() - lastStateSentAt
    if sinceLast < 1 then
      delay = math.max(delay, 1 - sinceLast)
    end
    C_Timer.After(delay, function()
      responsePending = false
      if IsInRaid() then
        Module:BroadcastState()
      end
    end)
    return
  end

  if messageType ~= "S" then return end
  local key = normalizeSender(characterKey) or normalizeSender(sender)
  if not key then return end
  if key == unitKey("player") then return end

  local parsed = parseSharedState(seasonID, total, a, b, c)
  responses[key] = {
    state = parsed,
    incompatible = parsed == nil,
    receivedAt = time(),
    addonVersion = version,
  }
  self:RefreshWindow()
end

local function setFrameBackground(frame, r, g, b, a)
  if not frame.Background then
    frame.Background = frame:CreateTexture(nil, "BACKGROUND")
    frame.Background:SetAllPoints()
    frame.Background:SetTexture(Constants.media.WhiteSquare)
  end
  frame.Background:SetVertexColor(r, g, b, a)
end

local function increaseFontSize(fontString, amount)
  local font, size, flags = fontString:GetFont()
  if font and size then
    fontString:SetFont(font, size + amount, flags)
  end
end

local function setupCheckButton(button, label)
  button:SetSize(24, 24)
  button.Text:SetText(label)
  button.Text:SetFontObject("GameFontHighlightSmall")
end

local function createHeaderButton(parent, text, key, x, width)
  local button = CreateFrame("Button", nil, parent)
  button:SetPoint("LEFT", parent, "LEFT", x, 0)
  button:SetSize(width, 24)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button.text:SetAllPoints()
  button.text:SetJustifyH("LEFT")
  button.text:SetText(WHITE_FONT_COLOR:WrapTextInColorCode(text))
  button.label = text
  button.sortKey = key
  button:SetScript("OnClick", function(clicked, mouseButton)
    if mouseButton == "RightButton" then
      Module:ResetSort()
      return
    end
    Module:SetSort(clicked.sortKey)
  end)
  button:SetScript("OnEnter", function(clicked)
    clicked.text:SetTextColor(1, 1, 1, 1)
    if not GameTooltip:IsShown() then
      GameTooltip:SetOwner(clicked, "ANCHOR_RIGHT")
      GameTooltip:SetText(clicked.label or "", 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("<Click to Sort>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
    GameTooltip:AddLine("<Right Click to Reset>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    Module:RefreshSortHeaders()
    if GameTooltip:IsShown() then
      GameTooltip:Hide()
    end
  end)
  return button
end

function Module:GetSelectedDifficulties()
  self.selectedDifficulties = self.selectedDifficulties or {}
  local selected = {}
  for _, difficultyID in ipairs(DISPLAY_DIFFICULTIES) do
    if self.selectedDifficulties[difficultyID] then
      table.insert(selected, difficultyID)
    end
  end
  if #selected == 0 then
    local _, currentDifficulty = currentRaidAndDifficulty()
    currentDifficulty = currentDifficulty or 15
    self.selectedDifficulties[currentDifficulty] = true
    table.insert(selected, currentDifficulty)
  end
  return selected
end

function Module:SetSort(column)
  if self.sortColumn == column then
    self.sortAscending = not self.sortAscending
  else
    self.sortColumn = column
    -- Character starts A-Z, Status keeps the historical saved-first ordering,
    -- and Bosses starts with the most kills at the top.
    self.sortAscending = column ~= "bosses"
  end
  self:RefreshSortHeaders()
  self:RefreshWindow()
end

function Module:ResetSort()
  self.sortColumn = "character"
  self.sortAscending = true
  self:RefreshSortHeaders()
  self:RefreshWindow()
end

function Module:RefreshSortHeaders()
  if not self.headerButtons then return end
  for key, button in pairs(self.headerButtons) do
    -- Match LiqUI's sortable Equipment table: keep the header label unchanged
    -- and indicate the active sort column with a subtle header highlight.
    button.text:SetText(WHITE_FONT_COLOR:WrapTextInColorCode(button.label))
    button.text:SetTextColor(1, 1, 1, 1)
    if key == self.sortColumn then
      SetHighlightColor(button, 1, 1, 1, 0.03)
    else
      SetHighlightColor(button, 1, 1, 1, 0)
    end
  end
end

function Module:IsEntranceCheckEnabled()
  local windows = Data.db.global.liqui.windows
  windows.RaidLockouts = windows.RaidLockouts or {}
  if windows.RaidLockouts.checkOnEntrance == nil then
    windows.RaidLockouts.checkOnEntrance = true
  end
  return windows.RaidLockouts.checkOnEntrance ~= false
end

function Module:EnsureWindow()
  if self.window then return end

  local windows = Data.db.global.liqui.windows
  windows.RaidLockouts = windows.RaidLockouts or {}
  if windows.RaidLockouts.checkOnEntrance == nil then
    windows.RaidLockouts.checkOnEntrance = true
  end

  self.window = LibLiqUI:NewElement("Window", {
    name = addon.name .. "RaidLockouts",
    storage = windows.RaidLockouts,
    title = "Raid Group Lockouts",
    width = WINDOW_WIDTH,
    height = WINDOW_HEIGHT,
    onShow = function()
      if not Module.difficultySelectionInitialized then
        local _, currentDifficulty = currentRaidAndDifficulty()
        Module.selectedDifficulties = {[currentDifficulty or 15] = true}
        Module.difficultySelectionInitialized = true
      end
      Module:RefreshDifficultyButtons()
      Module:RefreshSortHeaders()
      Module:RequestGroupState()
      Module:RefreshWindow()
    end,
  })

  local body = self.window.body
  self.selectedDifficulties = self.selectedDifficulties or {}
  self.difficultyButtons = {}
  self.sortColumn = self.sortColumn or "character"
  if self.sortAscending == nil then self.sortAscending = true end

  local previousButton
  for _, difficultyID in ipairs(SHARED_DIFFICULTIES) do
    local difficulty = difficultyInfo(difficultyID)
    local button = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
    setupCheckButton(button, difficulty and difficulty.name or tostring(difficultyID))
    if previousButton then
      button:SetPoint("LEFT", previousButton.Text, "RIGHT", 24, 0)
    else
      button:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -8)
    end
    button.difficultyID = difficultyID
    button:SetScript("OnClick", function(clicked)
      local checked = clicked:GetChecked() and true or false
      Module.selectedDifficulties[clicked.difficultyID] = checked

      local hasSelection = false
      for _, id in ipairs(SHARED_DIFFICULTIES) do
        if Module.selectedDifficulties[id] then
          hasSelection = true
          break
        end
      end
      if not hasSelection then
        Module.selectedDifficulties[clicked.difficultyID] = true
        clicked:SetChecked(true)
      end

      Module:RefreshDifficultyButtons()
      Module:RefreshWindow()
    end)
    self.difficultyButtons[difficultyID] = button
    previousButton = button
  end

  self.refreshButton = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
  self.refreshButton:SetSize(78, 24)
  self.refreshButton:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, -8)
  self.refreshButton:SetText(REFRESH)
  self.refreshButton:SetScript("OnClick", function()
    Module:RequestGroupState()
  end)

  self.entranceCheckButton = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
  setupCheckButton(self.entranceCheckButton, "Raid Lockout Window Check on Entrance")
  self.entranceCheckButton:SetChecked(windows.RaidLockouts.checkOnEntrance ~= false)
  local entranceLabelWidth = math.ceil(self.entranceCheckButton.Text:GetStringWidth())
  self.entranceCheckButton:SetPoint("RIGHT", self.refreshButton, "LEFT", -(entranceLabelWidth + 18), 0)
  self.entranceCheckButton:SetScript("OnClick", function(clicked)
    windows.RaidLockouts.checkOnEntrance = clicked:GetChecked() and true or false
  end)

  self.summary = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  increaseFontSize(self.summary, 2)
  self.summary:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -39)
  self.summary:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, -39)
  self.summary:SetJustifyH("LEFT")
  self.summary:SetTextColor(LIGHTGRAY_FONT_COLOR.r, LIGHTGRAY_FONT_COLOR.g, LIGHTGRAY_FONT_COLOR.b)

  self.header = CreateFrame("Frame", nil, body)
  self.header:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -57)
  self.header:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -57)
  self.header:SetHeight(24)
  setFrameBackground(self.header, 0, 0, 0, 0.3)
  self.headerButtons = {
    character = createHeaderButton(self.header, "Character", "character", NAME_X, 190),
    status = createHeaderButton(self.header, "Status", "status", STATUS_X, 110),
    bosses = createHeaderButton(self.header, "Bosses", "bosses", BOSSES_X, 200),
  }

  self.listArea = CreateFrame("Frame", "$parentRaidLockoutsListArea", body)
  self.listArea:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -81)
  self.listArea:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)

  -- Match Daily Delves: native LiqUI MinimalScrollBar laid over full-width rows.
  self.scrollArea = LibLiqUI.Utils.CreateScrollArea(self.listArea, {
    vertical = true,
    name = "$parentRaidLockoutsScrollArea",
    wheelPanExtent = ROW_HEIGHT,
  })
  self.scrollArea:SetAllPoints(self.listArea)
  self.scroll = self.scrollArea.verticalScrollBox
  self.scrollChild = self.scrollArea.content
  self.scrollChild:SetWidth(WINDOW_WIDTH)
  self.scrollChild:SetHeight(1)
  self.scrollBar = self.scrollArea.verticalScrollBar
  if self.scrollBar then
    self.scrollBar:SetFrameLevel(self.listArea:GetFrameLevel() + 10)
  end

  self.emptyText = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.emptyText:SetPoint("CENTER", self.listArea, "CENTER", 0, 20)
  self.emptyText:SetWidth(WINDOW_WIDTH - 80)
  self.emptyText:SetJustifyH("CENTER")
  self.emptyText:SetTextColor(LIGHTGRAY_FONT_COLOR.r, LIGHTGRAY_FONT_COLOR.g, LIGHTGRAY_FONT_COLOR.b)
  self.emptyText:Hide()

  self.rows = {}
  self:RefreshDifficultyButtons()
  self:RefreshSortHeaders()
end

function Module:RefreshDifficultyButtons()
  if not self.difficultyButtons then return end
  for difficultyID, button in pairs(self.difficultyButtons) do
    button:SetChecked(self.selectedDifficulties[difficultyID] == true)
  end
end

local function classColor(classFile)
  if classFile then
    local color = C_ClassColor.GetClassColor(classFile)
    if color then return color end
  end
  return WHITE_FONT_COLOR
end

local function statusText(state, difficultyID, showDifficulty)
  local text
  if state.status == "saved" then
    text = RED_FONT_COLOR:WrapTextInColorCode(format("SAVED %d/%d", state.killed, state.total))
  elseif state.status == "unsaved" then
    text = GREEN_FONT_COLOR:WrapTextInColorCode("Unsaved")
  else
    text = EPIC_PURPLE_COLOR:WrapTextInColorCode("NO DATA")
  end

  if not showDifficulty then return text end
  local difficulty = difficultyInfo(difficultyID)
  if not difficulty then return text end
  local color = difficulty.color or WHITE_FONT_COLOR
  return color:WrapTextInColorCode(difficulty.abbr or difficulty.name or tostring(difficultyID)) .. "  " .. text
end

local function rowBaseAlpha(index)
  return index % 2 == 0 and 0.035 or 0.015
end

local function setRowHighlight(row, highlighted)
  if not row or not row.bg then return end
  row.bg:SetColorTexture(1, 1, 1, highlighted and 0.08 or rowBaseAlpha(row.rowIndex or 1))
end

local function killedSkullColor(difficultyID)
  local color = UNCOMMON_GREEN_COLOR
  local difficulty = difficultyInfo(difficultyID)
  if Data.db.global.raids.colors and difficulty and difficulty.color then
    color = difficulty.color
  end
  return color
end

function Module:EnsureRow(index)
  local row = self.rows[index]
  if not row then
    row = CreateFrame("Button", nil, self.scrollChild)
    row:RegisterForClicks("LeftButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    increaseFontSize(row.name, 1)
    row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
    row.name:SetWidth(190)
    row.name:SetJustifyH("LEFT")

    row.statusLines = {}
    row.icons = {}

    row:SetScript("OnEnter", function(button)
      setRowHighlight(button, true)
    end)
    row:SetScript("OnLeave", function(button)
      setRowHighlight(button, false)
    end)

    for _, difficultyID in ipairs(DISPLAY_DIFFICULTIES) do
      local statusLine = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      statusLine:SetWidth(110)
      statusLine:SetJustifyH("LEFT")
      statusLine:SetJustifyV("MIDDLE")
      statusLine:Hide()
      row.statusLines[difficultyID] = statusLine

      row.icons[difficultyID] = {}
      for bossIndex = 1, #buildBossCatalog() do
        local icon = CreateFrame("Button", nil, row)
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetAllPoints()
        icon.texture:SetTexture(Constants.media.IconKillSkull)
        icon.bossIndex = bossIndex
        icon.difficultyID = difficultyID
        icon:Hide()
        icon:SetScript("OnEnter", function(button)
          setRowHighlight(row, true)
          local boss = button.boss
          if not boss then return end
          GameTooltip:SetOwner(button, "ANCHOR_TOP")
          GameTooltip:SetText(boss.name or "?", 1, 1, 1)
          if boss.raid and boss.raid.name then
            GameTooltip:AddLine(boss.raid.name, LIGHTGRAY_FONT_COLOR.r, LIGHTGRAY_FONT_COLOR.g, LIGHTGRAY_FONT_COLOR.b)
          end
          local difficulty = difficultyInfo(button.difficultyID)
          if difficulty then
            GameTooltip:AddLine(format("Difficulty: %s", difficulty.name), difficulty.color.r, difficulty.color.g, difficulty.color.b)
          end
          GameTooltip:AddLine(" ")
          if button.hasData then
            if button.killed then
              GameTooltip:AddLine("Killed this week", RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
            else
              GameTooltip:AddLine("Not killed this week", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            end
          else
            GameTooltip:AddLine("No shared lockout data", EPIC_PURPLE_COLOR.r, EPIC_PURPLE_COLOR.g, EPIC_PURPLE_COLOR.b)
          end
          GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function()
          GameTooltip:Hide()
          if not row:IsMouseOver() then
            setRowHighlight(row, false)
          end
        end)
        row.icons[difficultyID][bossIndex] = icon
      end
    end

    self.rows[index] = row
  end
  return row
end

function Module:RefreshWindow()
  if not self.window or not self.window:IsVisible() then return end

  local selectedDifficulties = self:GetSelectedDifficulties()
  local rows = buildRows(selectedDifficulties, self.sortColumn, self.sortAscending)
  if not rows then
    self.summary:SetText("")
    self.header:Hide()
    self.listArea:Hide()
    self.emptyText:SetText("Join a raid group to check the raid group lockouts shared by other AlterEgo users.")
    self.emptyText:Show()
    for _, row in ipairs(self.rows) do row:Hide() end
    return
  end

  self.header:Show()
  self.listArea:Show()
  self.emptyText:Hide()

  local saved, unsaved, nodata = 0, 0, 0
  for _, data in ipairs(rows) do
    if data.status == "saved" then saved = saved + 1
    elseif data.status == "unsaved" then unsaved = unsaved + 1
    else nodata = nodata + 1 end
  end
  self.summary:SetText(format("%s saved  ·  %s no data  ·  %s unsaved  ·  %s players",
    RED_FONT_COLOR:WrapTextInColorCode(tostring(saved)),
    EPIC_PURPLE_COLOR:WrapTextInColorCode(tostring(nodata)),
    GREEN_FONT_COLOR:WrapTextInColorCode(tostring(unsaved)),
    WHITE_FONT_COLOR:WrapTextInColorCode(tostring(#rows))))

  local bosses = buildBossCatalog()
  local showDifficultyPrefix = #selectedDifficulties > 1
  local rowHeight = math.max(ROW_HEIGHT, #selectedDifficulties * DIFFICULTY_LINE_HEIGHT)
  self.scrollArea:SetWheelPanExtent(rowHeight)
  local lineContentHeight = #selectedDifficulties * DIFFICULTY_LINE_HEIGHT
  local topPadding = math.max(0, (rowHeight - lineContentHeight) / 2)
  local y = 0

  for index, data in ipairs(rows) do
    local row = self:EnsureRow(index)
    row.rowIndex = index
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, -y)
    row:SetHeight(rowHeight)
    setRowHighlight(row, false)
    row:Show()

    local color = classColor(data.member.classFile)
    local displayName = data.member.name or data.member.key
    if data.member.realm and data.member.realm ~= "" then
      displayName = displayName .. "-" .. data.member.realm
    end
    row.name:SetText(CreateColor(color.r, color.g, color.b, 1):WrapTextInColorCode(displayName))

    for _, difficultyID in ipairs(DISPLAY_DIFFICULTIES) do
      row.statusLines[difficultyID]:Hide()
      for _, icon in ipairs(row.icons[difficultyID]) do
        icon:Hide()
      end
    end

    for lineIndex, difficultyID in ipairs(selectedDifficulties) do
      local state = data.states[difficultyID]
      local lineTop = topPadding + (lineIndex - 1) * DIFFICULTY_LINE_HEIGHT
      local statusLine = row.statusLines[difficultyID]
      statusLine:ClearAllPoints()
      statusLine:SetPoint("TOPLEFT", row, "TOPLEFT", STATUS_X, -lineTop)
      statusLine:SetHeight(DIFFICULTY_LINE_HEIGHT)
      statusLine:SetText(statusText(state, difficultyID, showDifficultyPrefix))
      statusLine:Show()

      local killColor = killedSkullColor(difficultyID)
      for bossIndex, boss in ipairs(bosses) do
        local icon = row.icons[difficultyID][bossIndex]
        local iconY = lineTop + ((DIFFICULTY_LINE_HEIGHT - ICON_SIZE) / 2)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", row, "TOPLEFT", BOSSES_X + (bossIndex - 1) * (ICON_SIZE + ICON_GAP), -iconY)
        icon.boss = boss
        icon.hasData = state.status ~= "nodata"
        icon.killed = icon.hasData and state.slots[bossIndex] == true
        if icon.killed then
          -- Match the raid rows elsewhere in AlterEgo: difficulty color when
          -- enabled, otherwise the standard green kill color, at the same alpha.
          icon.texture:SetVertexColor(killColor.r, killColor.g, killColor.b, 0.5)
        elseif icon.hasData then
          icon.texture:SetVertexColor(1, 1, 1, 0.08)
        else
          icon.texture:SetVertexColor(1, 1, 1, 0.03)
        end
        icon:Show()
      end
    end

    y = y + rowHeight
  end

  for index = #rows + 1, #self.rows do
    self.rows[index]:Hide()
  end

  local width = self.listArea:GetWidth() or WINDOW_WIDTH
  self.scrollChild:SetWidth(math.max(1, width))
  self.scrollChild:SetHeight(math.max(1, y))
  self.scrollArea:UpdateLayout(width, math.max(1, y))
  if self.scrollBar then
    self.scrollBar:ClearAllPoints()
    self.scrollBar:SetPoint("TOPRIGHT", self.listArea, "TOPRIGHT", -3, -2)
    self.scrollBar:SetPoint("BOTTOMRIGHT", self.listArea, "BOTTOMRIGHT", -3, 2)
  end
end

function Module:Toggle()
  self:EnsureWindow()
  self.window:Toggle()
  if self.window:IsVisible() then
    self.window:Raise()
  end
end

-- ===== Entering-raid lockout alert =====================================

local alertFrame
local alertLines = {}
local alertDimmer

-- Keep this self-contained: the alert borrows EllesmereUI's visual language
-- (near-black panel, thin translucent border, flat confirm button and dimmer)
-- without requiring EllesmereUI to be installed or loaded.
local function ensureAlertFrame()
  if alertFrame then return alertFrame end

  alertDimmer = CreateFrame("Frame", nil, UIParent)
  alertDimmer:SetFrameStrata("FULLSCREEN_DIALOG")
  alertDimmer:SetFrameLevel(140)
  alertDimmer:SetAllPoints(UIParent)
  alertDimmer:EnableMouse(true)
  alertDimmer.bg = alertDimmer:CreateTexture(nil, "BACKGROUND")
  alertDimmer.bg:SetAllPoints()
  alertDimmer.bg:SetColorTexture(0, 0, 0, 0.55)
  alertDimmer:Hide()

  alertFrame = CreateFrame("Frame", "AlterEgoRaidLockoutAlert", UIParent, "BackdropTemplate")
  alertFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  alertFrame:SetFrameLevel(150)
  alertFrame:SetToplevel(true)
  alertFrame:SetClampedToScreen(true)
  alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  alertFrame:SetSize(480, 220)
  alertFrame:SetMovable(true)
  alertFrame:EnableMouse(true)
  alertFrame:RegisterForDrag("LeftButton")
  alertFrame:SetScript("OnDragStart", alertFrame.StartMoving)
  alertFrame:SetScript("OnDragStop", alertFrame.StopMovingOrSizing)
  alertFrame:SetBackdrop({
    bgFile = Constants.media.WhiteSquare,
    edgeFile = Constants.media.WhiteSquare,
    edgeSize = 1,
  })
  -- EllesmereUI modal panel: #0F1116 with a subtle white outline.
  alertFrame:SetBackdropColor(15 / 255, 17 / 255, 22 / 255, 1)
  alertFrame:SetBackdropBorderColor(1, 1, 1, 0.15)
  alertFrame:SetScript("OnHide", function()
    if alertDimmer then alertDimmer:Hide() end
  end)

  alertFrame.title = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  alertFrame.title:SetPoint("TOP", alertFrame, "TOP", 0, -16)
  alertFrame.title:SetJustifyH("CENTER")

  alertFrame.subtitle = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  alertFrame.subtitle:SetPoint("TOP", alertFrame.title, "BOTTOM", 0, -5)
  alertFrame.subtitle:SetJustifyH("CENTER")
  alertFrame.subtitle:SetTextColor(1, 1, 1, 0.72)

  alertFrame.footer = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  alertFrame.footer:SetJustifyH("CENTER")
  alertFrame.footer:SetTextColor(1, 1, 1, 1)

  alertFrame.accept = CreateFrame("Button", nil, alertFrame, "BackdropTemplate")
  alertFrame.accept:SetSize(92, 26)
  alertFrame.accept:SetBackdrop({
    bgFile = Constants.media.WhiteSquare,
    edgeFile = Constants.media.WhiteSquare,
    edgeSize = 1,
  })
  alertFrame.accept:SetBackdropColor(0.05, 0.52, 0.39, 0.80)
  alertFrame.accept:SetBackdropBorderColor(1, 1, 1, 0.08)
  alertFrame.accept.text = alertFrame.accept:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  alertFrame.accept.text:SetPoint("CENTER")
  alertFrame.accept.text:SetTextColor(1, 1, 1, 1)
  alertFrame.accept.text:SetText(ACCEPT)
  alertFrame.accept:SetScript("OnEnter", function(button)
    button:SetBackdropColor(0.07, 0.62, 0.49, 1)
  end)
  alertFrame.accept:SetScript("OnLeave", function(button)
    button:SetBackdropColor(0.05, 0.52, 0.39, 0.80)
  end)
  alertFrame.accept:SetScript("OnClick", function() alertFrame:Hide() end)

  if UISpecialFrames then
    table.insert(UISpecialFrames, "AlterEgoRaidLockoutAlert")
  end
  alertFrame:Hide()
  return alertFrame
end

local function raidSlots(character, raid, difficultyID)
  local lookup = buildKilledLookup(character)
  local slots = {}
  local killed = 0
  local count = raid.numEncounters or #(raid.encounters or {})
  for encounterIndex = 1, count do
    local key = format("%s:%s:%s", tostring(raid.instanceID), tostring(difficultyID), tostring(encounterIndex))
    local isKilled = lookup[key] == true
    slots[encounterIndex] = isKilled
    if isKilled then killed = killed + 1 end
  end
  return slots, killed, count
end

function Module:ShowInstanceAlert(raid, difficultyID)
  local frame = ensureAlertFrame()
  local character = Data:GetCharacter()
  if not character then return end

  local slots, killed, total = raidSlots(character, raid, difficultyID)
  local isSaved = killed > 0
  local difficulty = difficultyInfo(difficultyID)

  frame.title:SetText(isSaved and "You are saved" or "You are unsaved")
  if isSaved then
    frame.title:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
  else
    frame.title:SetTextColor(GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
  end

  -- Use the exact raid-difficulty colors already defined by AlterEgo:
  -- Normal = rare blue, Heroic = epic purple, Mythic = legendary orange.
  local difficultyName = difficulty and difficulty.name or tostring(difficultyID)
  local difficultyColor = difficulty and difficulty.color or WHITE_FONT_COLOR
  frame.subtitle:SetText(format("%s   ·   %s", raid.name or RAID, difficultyColor:WrapTextInColorCode(difficultyName)))

  for _, line in ipairs(alertLines) do line:Hide() end

  local columns = total > 4 and 2 or 1
  local leftCount = columns == 2 and math.ceil(total / 2) or total
  local rightCount = columns == 2 and (total - leftCount) or 0
  local rowsPerColumn = math.max(leftCount, rightCount)
  local bodyTop = 72
  local rowHeight = 20
  local edgePadding = 10
  local columnGap = columns == 2 and 12 or 0
  local contentHeight = rowsPerColumn * rowHeight
  local leftColumnWidth = 0
  local rightColumnWidth = 0

  -- Measure the real rendered boss labels first. The popup width is then
  -- derived from those labels so the widest left label starts 10 px from the
  -- left border and the widest right label ends 10 px before the right border.
  for encounterIndex = 1, total do
    local line = alertLines[encounterIndex]
    if not line then
      line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      alertLines[encounterIndex] = line
    end

    local encounter = raid.encounters and raid.encounters[encounterIndex]
    local bossName = encounter and encounter.name or format("%s (%d)", raid.name or RAID, encounterIndex)
    line:SetText("- " .. bossName)
    line:SetWidth(1000)
    line:SetJustifyH("LEFT")

    if slots[encounterIndex] then
      line:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
    else
      line:SetTextColor(GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
    end

    local textWidth = math.ceil(line:GetStringWidth())
    if columns == 2 and encounterIndex > leftCount then
      rightColumnWidth = math.max(rightColumnWidth, textWidth)
    else
      leftColumnWidth = math.max(leftColumnWidth, textWidth)
    end
  end

  if columns == 1 then
    rightColumnWidth = 0
  end

  -- The boss labels define the popup width. This intentionally leaves exactly
  -- 10 px outside the widest label on each side, making the alert as narrow as
  -- the current encounter names allow.
  local frameWidth = edgePadding + leftColumnWidth + columnGap + rightColumnWidth + edgePadding
  local bossBlockX = edgePadding
  local rightX = bossBlockX + leftColumnWidth + columnGap

  for encounterIndex = 1, total do
    local line = alertLines[encounterIndex]
    line:ClearAllPoints()

    local row
    local left
    local width
    if columns == 2 and encounterIndex > leftCount then
      row = encounterIndex - leftCount - 1
      left = rightX
      width = rightColumnWidth
    else
      row = encounterIndex - 1
      left = bossBlockX
      width = leftColumnWidth
    end

    line:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -(bodyTop + row * rowHeight))
    line:SetWidth(width)
    line:SetJustifyH("LEFT")
    line:Show()
  end

  if isSaved then
    frame.footer:SetText(format("Saved on %d out of %d %s.", killed, total, total == 1 and "boss" or "bosses"))
  else
    frame.footer:SetText(format("Unsaved on all %d %s.", total, total == 1 and "boss" or "bosses"))
  end

  frame.footer:ClearAllPoints()
  frame.footer:SetPoint("TOP", frame, "TOP", 0, -(bodyTop + contentHeight + 10))
  frame.accept:ClearAllPoints()
  frame.accept:SetPoint("TOP", frame.footer, "BOTTOM", 0, -12)

  frame:SetWidth(frameWidth)
  frame:SetHeight(bodyTop + contentHeight + 10 + 18 + 12 + frame.accept:GetHeight() + 18)
  if alertDimmer then alertDimmer:Show() end
  frame:Show()
  frame:Raise()
end

function Module:CheckInstanceAlert(suppressCurrent)
  local raid, difficultyID, instanceID = currentRaidAndDifficulty()
  if not raid then
    self.lastInstanceKey = nil
    return
  end

  local key = tostring(instanceID) .. ":" .. tostring(difficultyID)
  if self.lastInstanceKey == key then return end
  self.lastInstanceKey = key
  if suppressCurrent then return end
  if not self:IsEntranceCheckEnabled() then return end

  -- Saved-instance data is client-cached. Ask for the current snapshot and
  -- wait briefly before reading it, otherwise the first frame after zoning
  -- can still contain the previous instance's information.
  RequestRaidInfo()
  C_Timer.After(3, function()
    local stillRaid, stillDifficulty, stillInstanceID = currentRaidAndDifficulty()
    if not stillRaid or stillInstanceID ~= instanceID or stillDifficulty ~= difficultyID then return end
    Data:UpdateRaidInstances()
    Module:ShowInstanceAlert(stillRaid, stillDifficulty)
  end)
end

function Module:OnInitialize()
  addon.Core:RegisterComm(COMM_PREFIX, function(prefix, message, distribution, sender)
    Module:OnRaidLockoutComm(prefix, message, distribution, sender)
  end)
  self:EnsureWindow()
end

function Module:OnEnable()
  -- PLAYER_ENTERING_WORLD fires both for genuine zone transitions and for
  -- login/UI reload. Seed the current instance on login/reload without
  -- showing the alert, so it only appears after actually entering a raid.
  addon.Events:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin, isReloadingUi)
    local suppressCurrent = isInitialLogin == true or isReloadingUi == true
    Module:CheckInstanceAlert(suppressCurrent)
    if not suppressCurrent then
      C_Timer.After(2, function() Module:CheckInstanceAlert() end)
    end
  end, true)

  addon.Events:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if Module.window and Module.window:IsVisible() then
      C_Timer.After(0.5, function()
        Module:RequestGroupState()
        Module:RefreshWindow()
      end)
    end
  end, true)

  addon.Events:RegisterEvent("UPDATE_INSTANCE_INFO", function()
    Module:RefreshWindow()
  end, true)

  addon.Events:RegisterEvent("BOSS_KILL", function()
    if not IsInRaid() then return end
    RequestRaidInfo()
    C_Timer.After(3.2, function()
      if not IsInRaid() then return end
      Data:UpdateRaidInstances()
      Module:BroadcastState()
      Module:RefreshWindow()
    end)
  end, true)
end
