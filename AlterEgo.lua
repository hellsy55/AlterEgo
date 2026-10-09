---@class AE_Addon
local addon = select(2, ...)

local Data = addon.Data
local Constants = addon.Constants
local Helpers = addon.Helpers
local LibAceAddon = addon.Libs.AceAddon
local LibDataBroker = addon.Libs.LibDataBroker
local LibDBIcon = addon.Libs.LibDBIcon
local LibLiqUI = addon.Libs.LiqUI
local TableCount = LibLiqUI.Utils.TableCount
local TableForEach = LibLiqUI.Utils.TableForEach
local TableGet = LibLiqUI.Utils.TableGet

---@class AE_Core : AceAddon
local Core = LibAceAddon:NewAddon(addon.name, "AceConsole-3.0", "AceTimer-3.0")
addon.Core = Core

---Initialize the addon
function Core:OnInitialize()
  _G["BINDING_NAME_ALTEREGO"] = "Toggle AlterEgo window"
  _G["BINDING_NAME_ALTEREGOVAULT"] = "Toggle Great Vault window"
  _G["BINDING_NAME_ALTEREGOEQUIPMENT"] = "Toggle Character Equipment window"
  _G["ALTEREGO_TOGGLE_WINDOW"] = self.ToggleWindow
  _G["ALTEREGO_TOGGLE_VAULT"] = self.ToggleVault
  _G["ALTEREGO_TOGGLE_EQUIPMENT"] = self.ToggleEquipment
  self:RegisterChatCommand(addon.name:lower(), function(input)
    -- Manual recalibration for the Great Vault's displayed season week
    -- number (see CheckGameData's one-time seed and Data.lua::
    -- SetSeasonWeekAnchor) -- for the rare case it ever needs correcting.
    local week = input and input:match("^setweek%s+(%d+)$")
    if week then
      Data:SetSeasonWeekAnchor(tonumber(week))
      self:Print(format("Great Vault season week manually set to %d.", tonumber(week)))
      self:Render()
      return
    end
    self:ToggleWindow()
  end)
  TableForEach(Constants.commands, function(command)
    self:RegisterChatCommand(command, function()
      self:ToggleWindow()
    end)
  end)
  Data:Initialize()
  Data:MigrateDB()

  local function toggleDailyDelves()
    local module = addon.Core:GetModule("DailyDelves", true)
    if module then
      module:Toggle()
    end
  end

  local libDataObject = {
    label = addon.title,
    type = "launcher",
    icon = addon.Constants.media.Logo,
    OnClick = function(...)
      local mouseButton = select(2, ...)
      local isShiftKeyDown = IsLeftShiftKeyDown() or IsRightShiftKeyDown()
      if mouseButton then
        if mouseButton == "LeftButton" and isShiftKeyDown then
          self:ToggleEquipment()
        elseif mouseButton == "RightButton" and isShiftKeyDown then
          self:ToggleVault()
        elseif mouseButton == "MiddleButton" then
          self:ToggleRaidLockouts()
        elseif mouseButton == "RightButton" then
          toggleDailyDelves()
        else
          self:ToggleWindow()
        end
      else
        self:ToggleWindow()
      end
    end,
    OnTooltipShow = function(tooltip)
      tooltip:SetText(addon.title, 1, 1, 1)
      tooltip:AddLine("|cff00ff00Left click|r to open AlterEgo.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
      tooltip:AddLine("|cff00ff00Right click|r to open Daily Delves.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
      tooltip:AddLine("|cff00ff00Middle click|r to open Raid Group Lockouts.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
      tooltip:AddLine("|cff00ff00Shift+Left click|r to open your character equipment.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
      tooltip:AddLine("|cff00ff00Shift+Right click|r to open the Great Vault.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
      local dragText = "|cff00ff00Drag|r to move this icon"
      if Data.db.global.minimap.lock then
        dragText = dragText .. " |cffff0000(locked)|r"
      end
      tooltip:AddLine(dragText .. ".", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    end,
  }

  LibDataBroker:NewDataObject(addon.name, libDataObject)
  LibDBIcon:Register(addon.name, libDataObject, Data.db.global.minimap)
  LibDBIcon:AddButtonToCompartment(addon.name)

  hooksecurefunc("ResetInstances", function()
    self:OnInstanceReset()
  end)
  -- Best-effort claim detection for Great Vault history (Data.lua::
  -- MarkVaultRewardClaimed) -- same caveat GG's addon documents for the
  -- identical hook: there's no verified confirmation this is really the
  -- function the "Choose" button calls, so this is guarded so a wrong/
  -- renamed API just silently doesn't hook anything instead of erroring.
  if type(C_WeeklyRewards) == "table" and type(C_WeeklyRewards.ClaimReward) == "function" then
    hooksecurefunc(C_WeeklyRewards, "ClaimReward", function(activityId)
      Data:MarkVaultRewardClaimed(activityId)
    end)
  end
  self:RenderNow()
end

---Toggle the main window
function Core:ToggleWindow()
  local window = LibLiqUI:GetElement("Window", addon.name .. "Main")
  if not window then return end
  window:Toggle()
  if window:IsVisible() then
    window:Raise()
  end
end

---Toggle the vault window
function Core:ToggleVault()
  if WeeklyRewardsFrame and ToggleFrame then
    ToggleFrame(WeeklyRewardsFrame)
  else
    WeeklyRewards_ShowUI()
  end
end

---Toggle the raid group lockouts window
function Core:ToggleRaidLockouts()
  local module = self:GetModule("RaidLockouts", true)
  if not module then return end
  module:Toggle()
end

---Toggle the equipment window
function Core:ToggleEquipment()
  local module = addon.Core:GetModule("Equipment", true)
  if not module then return end
  local character = Data:GetCharacter()
  if not character then return end
  module:OpenCharacter(character)
end

---Render all modules immediately (needed during initial UI setup).
function Core:RenderNow()
  for _, module in self:IterateModules() do
    if module.Render ~= nil then
      module:Render()
    end
  end
end

---Coalesce multiple render requests into one pass on the next frame.
function Core:Render()
  if self.renderQueued then return end
  self.renderQueued = true
  C_Timer.After(0, function()
    self.renderQueued = false
    self:RenderNow()
  end)
end

---Data updates may be requested by several events in the same frame.
---Keep the equipment module's enchant-aware refresh/retry implementation.
local updaters = {
  UpdateCharacterInfo = function() Data:UpdateCharacterInfo() end,
  UpdatePreyProgress = function() Data:UpdatePreyProgress() end,
  UpdateEquipment = function()
    local equipment = addon.Core:GetModule("Equipment", true)
    if equipment then
      equipment:RefreshEquipment()
    else
      Data:UpdateEquipment()
    end
  end,
  UpdateMoney = function() Data:UpdateMoney() end,
  UpdateCurrencies = function()
    Data:UpdateCurrencies()
    addon.Core:Render()
  end,
  UpdateKeystoneItem = function() Data:UpdateKeystoneItem() end,
  UpdateRaidInstances = function() Data:UpdateRaidInstances() end,
  UpdateVault = function() Data:UpdateVault() end,
  UpdateMythicPlus = function() Data:UpdateMythicPlus() end,
  RequestSyncBroadcast = function() addon.Core:RequestSyncBroadcast() end,
}

local updateQueue, updateQueued, updateQueueRunning = {}, {}, false

local function processUpdateQueue()
  local name = table.remove(updateQueue, 1)
  if name then
    updateQueued[name] = nil
    updaters[name]()
  end
  if #updateQueue > 0 then
    C_Timer.After(0, processUpdateQueue)
  else
    updateQueueRunning = false
  end
end

---Run at most one distinct queued update per frame.
---@param name string
function Core:QueueUpdate(name)
  if not updaters[name] or updateQueued[name] then return end
  updateQueued[name] = true
  updateQueue[#updateQueue + 1] = name
  if not updateQueueRunning then
    updateQueueRunning = true
    C_Timer.After(0, processUpdateQueue)
  end
end

---Match Data:UpdateDB's dependency order, including custom sync broadcast.
function Core:QueueAllUpdates()
  for _, name in ipairs({
    "UpdateCharacterInfo",
    "UpdatePreyProgress",
    "UpdateEquipment",
    "UpdateMoney",
    "UpdateCurrencies",
    "UpdateKeystoneItem",
    "UpdateRaidInstances",
    "UpdateVault",
    "UpdateMythicPlus",
    "RequestSyncBroadcast",
  }) do
    self:QueueUpdate(name)
  end
end

---Register event handlers for game data updates
function Core:OnEnable()
  addon.Events:RegisterEvent(
    {
      "PLAYER_EQUIPMENT_CHANGED",
      "UNIT_INVENTORY_CHANGED",
    }, function()
      -- Equipment scans and enchant retries belong to Equipment:OnEnable.
      self:QueueUpdate("UpdateCharacterInfo")
    end
  )
  addon.Events:RegisterEvent(
    {
      "QUEST_LOG_UPDATE",
    }, function()
      self:QueueUpdate("UpdatePreyProgress")
      self:QueueUpdate("UpdateCurrencies")
    end
  )
  addon.Events:RegisterEvent(
    {
      "GUILD_ROSTER_UPDATE",
      "PLAYER_GUILD_UPDATE",
    }, function()
      self:QueueUpdate("UpdateCharacterInfo")
    end
  )
  addon.Events:RegisterEvent(
    {
      "BOSS_KILL",
      "CHALLENGE_MODE_COMPLETED",
      "ENCOUNTER_END",
      "LFG_LOCK_INFO_RECEIVED",
      "RAID_INSTANCE_WELCOME",
    }, function()
      self:RequestGameData()
    end
  )
  addon.Events:RegisterEvent(
    {
      "CHALLENGE_MODE_MAPS_UPDATE",
      "WEEKLY_REWARDS_UPDATE",
    }, function()
      self:QueueUpdate("UpdateVault")
    end
  )
  -- Track an actual native Great Vault open separately from generic weekly
  -- reward updates. This is the trust boundary for reward history: before
  -- this interaction happens, example reward links must never become history.
  addon.Events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, _, interactionType)
    if interactionType ~= Enum.PlayerInteractionType.WeeklyRewards then return end
    Data:MarkVaultOpened()
  end, true)
  -- WEEKLY_REWARDS_UPDATE alone isn't reliable for "the player just
  -- reopened the Great Vault" -- a real bug report confirmed the addon's
  -- window stayed empty/stale on a SECOND look at the vault this session,
  -- even though the first open worked. Closing the Great Vault frame
  -- (PLAYER_INTERACTION_MANAGER_FRAME_HIDE, filtered to the WeeklyRewards
  -- interaction type) is the same "the player just looked at this" signal
  -- already used elsewhere for the keystone announce flush -- rereading
  -- twice, 1s and 3s after close, covers Blizzard's data settling with a
  -- short server-side delay instead of gambling on one fixed number.
  addon.Events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, interactionType)
    if interactionType ~= Enum.PlayerInteractionType.WeeklyRewards then return end
    for _, delay in ipairs({1, 3}) do
      C_Timer.After(delay, function()
        Data:UpdateVault()
      end)
    end
  end)
  addon.Events:RegisterEvent(
    {
      "LFG_UPDATE_RANDOM_INFO",
      "UPDATE_INSTANCE_INFO",
    }, function()
      self:QueueUpdate("UpdateRaidInstances")
    end
  )
  addon.Events:RegisterEvent(
    {
      "BAG_UPDATE_DELAYED",
      "CHALLENGE_MODE_COMPLETED",
      "CHALLENGE_MODE_MAPS_UPDATE",
      "CHALLENGE_MODE_RESET",
      "ITEM_CHANGED",
      "MYTHIC_PLUS_NEW_WEEKLY_RECORD",
    }, function()
      self:QueueUpdate("UpdateKeystoneItem")
      self:QueueUpdate("UpdateCurrencies")
      C_Timer.After(2, function()
        Data:FlushPendingKeystoneAnnounce()
      end)
    end
  )
  addon.Events:RegisterEvent(
    {
      "CHALLENGE_MODE_COMPLETED",
      "CHALLENGE_MODE_MAPS_UPDATE",
      "CHALLENGE_MODE_RESET",
      "MYTHIC_PLUS_NEW_WEEKLY_RECORD",
    }, function()
      self:QueueUpdate("UpdateMythicPlus")
    end
  )
  addon.Events:RegisterEvent(
    {
      "BONUS_ROLL_RESULT",
      "CHAT_MSG_CURRENCY",
      "CURRENCY_DISPLAY_UPDATE",
      "PLAYER_TRADE_CURRENCY",
      "POST_MATCH_CURRENCY_REWARD_UPDATE",
      "QUEST_CURRENCY_LOOT_RECEIVED",
      "SPELL_CONFIRMATION_PROMPT",
      "TRADE_CURRENCY_CHANGED",
      "TRADE_SKILL_CURRENCY_REWARD_RESULT",
    }, function()
      self:QueueUpdate("UpdateCurrencies")
    end
  )
  addon.Events:RegisterEvent(
    {
      "PLAYER_MONEY",
    }, function()
      self:QueueUpdate("UpdateMoney")
    end
  )
  addon.Events:RegisterEvent(
    {
      "PLAYER_ENTERING_WORLD",
      "ZONE_CHANGED",
      "ZONE_CHANGED_INDOORS",
      "ZONE_CHANGED_NEW_AREA",
    },
    function()
      Data:UpdateCharacterLocation()
    end,
    true
  )
  addon.Events:RegisterEvent(
    "PLAYER_LOGOUT",
    function()
      Data:UpdateCharacterLocation()
    end,
    true
  )
  addon.Events:RegisterEvent(
    "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",
    function()
      self:Render()
    end,
    true
  )
  addon.Events:RegisterEvent(
    "CHAT_MSG_SYSTEM",
    function(...)
      self:OnChatMessageSystem(...)
    end,
    true
  )
  addon.Events:RegisterEvent(
    "PLAYER_LEVEL_UP",
    function()
      Data:UpdateDB()
    end,
    true
  )
  addon.Events:RegisterEvent(
    {
      "ADDON_RESTRICTION_STATE_CHANGED",
      "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
      "PLAYER_REGEN_ENABLED",
    },
    function(_, event, _, state)
      if event == "ADDON_RESTRICTION_STATE_CHANGED" and state ~= Enum.AddOnRestrictionState.Inactive then
        return
      end
      Data:FlushPendingKeystoneAnnounce()
    end,
    true
  )
  self:CheckGameData()
end

---Request game data from the API
function Core:RequestGameData()
  C_MythicPlus.RequestCurrentAffixes()
  C_MythicPlus.RequestMapInfo()
  C_MythicPlus.RequestRewards()
  RequestRaidInfo()
end

---Check if game data is loaded
function Core:CheckGameData()
  local seasonID, seasonDisplayID = Data:GetCurrentSeason()
  if seasonID < 0 or seasonDisplayID < 0 then
    self:RequestGameData()
    self:ScheduleTimer("CheckGameData", 3)
    return
  end

  Data:loadGameData(function()
    Data:TaskWeeklyReset()
    Data:TaskSeasonReset()
    -- One-time calibration for the Great Vault's displayed season week
    -- number (Data.lua::GetSeasonWeekNumber) -- WoW has no API for this, so
    -- it's seeded once from a week number confirmed correct on the day this
    -- was added (this week's reset == week 7), then every other week just
    -- counts 7-day steps from that anchor. `/alterego setweek N` re-anchors
    -- it manually later if it ever needs correcting (a new season starting
    -- over, a mistaken seed on an install that first ran in a different
    -- week, etc.).
    if not Data.db.global.seasonWeekAnchor then
      Data:SetSeasonWeekAnchor(7)
    end
    self:QueueAllUpdates()
    self:Render()
  end)

  -- There's no dedicated "the weekly reset just happened" event in the
  -- game's API -- Data:TaskWeeklyReset only ever re-checks the boundary
  -- when THIS function runs, which otherwise only happens at login/reload.
  -- Self-reschedule this same check to fire again right when the next
  -- boundary passes (C_DateAndTime.GetSecondsUntilWeeklyReset(), the same
  -- function TaskWeeklyReset itself uses to set the next reset timestamp),
  -- so the Great Vault season week (and everything else TaskWeeklyReset
  -- handles) updates live for anyone still logged in through it, instead
  -- of needing a relog/reload to notice.
  self:ScheduleTimer("CheckGameData", C_DateAndTime.GetSecondsUntilWeeklyReset() + 5)
end

---Handle instance reset
function Core:OnInstanceReset()
  local groupChannel = Helpers:GetGroupChannel()
  if not groupChannel or not Data.db.global.announceResets or IsInInstance() or not UnitIsGroupLeader("player") then
    return
  end
  C_ChatInfo.SendChatMessage(addon.Constants.prefix .. "Resetting instances...", groupChannel)
end

---Handle chat message system
---@param _ any
---@param msg string
function Core:OnChatMessageSystem(_, msg)
  local groupChannel = Helpers:GetGroupChannel()
  if not groupChannel or not Data.db.global.announceResets or IsInInstance() or not UnitIsGroupLeader("player") then
    return
  end
  local resetPatterns = {INSTANCE_RESET_SUCCESS, INSTANCE_RESET_FAILED, INSTANCE_RESET_FAILED_OFFLINE, INSTANCE_RESET_FAILED_ZONING}
  TableForEach(resetPatterns, function(resetPattern)
    if msg:match("^" .. resetPattern:gsub("%%s", ".+") .. "$") then
      C_ChatInfo.SendChatMessage(addon.Constants.prefix .. msg, groupChannel)
    end
  end)
end

---Announce keystones to a chat channel
---@param chatType string
function Core:AnnounceKeystones(chatType)
  local characters = Data:GetCharacters()
  local dungeons = Data:GetDungeons()
  local multiline = Data.db.global.announceKeystones.multiline
  local multilineNames = Data.db.global.announceKeystones.multilineNames
  local keystones = {}
  local keystonesCompact = {}

  if TableCount(characters) < 1 then
    self:Print("You have no characters saved.")
    return
  end

  TableForEach(characters, function(character)
    local keystone = character.mythicplus.keystone
    local dungeon

    if type(keystone.level) ~= "number" or keystone.level < 1 then
      return
    end

    if type(keystone.challengeModeID) == "number" and keystone.challengeModeID > 0 then
      dungeon = TableGet(dungeons, "challengeModeID", keystone.challengeModeID)
    elseif type(keystone.mapId) == "number" and keystone.mapId > 0 then
      dungeon = TableGet(dungeons, "mapId", keystone.mapId)
    end

    if not dungeon then
      return
    end

    local text = dungeon.abbr .. " +" .. tostring(keystone.level)
    table.insert(keystones, {
      text = text,
      itemLink = keystone.itemLink,
      characterName = character.info.name,
    })
    table.insert(keystonesCompact, text)
  end)

  if TableCount(keystones) < 1 then
    self:Print("You have no keystones saved.")
    return
  end

  if multiline then
    C_ChatInfo.SendChatMessage(addon.Constants.prefix .. "My keystones:", chatType)
    TableForEach(keystones, function(keystone)
      local chatMessage = keystone.itemLink and keystone.itemLink or keystone.text
      if multilineNames == true then
        chatMessage = keystone.characterName .. ": " .. chatMessage
      end
      C_ChatInfo.SendChatMessage(chatMessage, chatType)
    end)
    return
  end

  C_ChatInfo.SendChatMessage(addon.Constants.prefix .. "My keystones: " .. table.concat(keystonesCompact, " || "), chatType)
end
