---@class AE_Addon
local addon = select(2, ...)

---@class AE_Module_Main
local Module = addon.Core:NewModule("Main", "AceConsole-3.0", "AceTimer-3.0")
addon.Module_Main = Module

local Data = addon.Data
local Helpers = addon.Helpers
local Constants = addon.Constants
local LibLiqUI = addon.Libs.LiqUI
local SetBackgroundColor = LibLiqUI.Utils.SetBackgroundColor
local SetHighlightColor = LibLiqUI.Utils.SetHighlightColor
local TableCount = LibLiqUI.Utils.TableCount
local TableFilter = LibLiqUI.Utils.TableFilter
local TableFind = LibLiqUI.Utils.TableFind
local TableForEach = LibLiqUI.Utils.TableForEach
local TableGet = LibLiqUI.Utils.TableGet
local CreateScrollArea = LibLiqUI.Utils.CreateScrollArea

-- Keep the Currencies Show Icons option conditional when that section has no
-- icon-capable rows. Weeklies and Seasonal Chores always expose their toggle
-- because quest/status trackers can now prepend their own tracker icon too.
local function CategoryHasIconCurrencies(currencies, category)
  for _, currency in ipairs(currencies) do
    if currency.category == category
      and currency.currencyType ~= "quest"
      and currency.currencyType ~= "delveMap"
      and currency.currencyType ~= "gildedStash" then
      return true
    end
  end
  return false
end

function Module:OnInitialize()
  self:Render()
end

do
  local dialogName = "ALTEREGO_DELETE_CHARACTER"
  StaticPopupDialogs[dialogName] = {
    text = "Remove %s?\n\nThis cannot be undone.\nTo add this character again, log in on them.",
    button1 = YES,
    button2 = CANCEL,
    OnAccept = function(_, character)
      if character then
        Data:DeleteCharacter(character)
        Module:Render()
      end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

do
  local dialogName = "ALTEREGO_RENAME_ACCOUNT"
  StaticPopupDialogs[dialogName] = {
    text = "Rename \"%s\"",
    button1 = ACCEPT,
    button2 = CANCEL,
    button3 = DELETE,
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self, account)
      -- The edit box region got renamed from `editBox` to `EditBox` in newer
      -- client builds (Blizzard_StaticPopup_Game/GameDialog.lua) -- check
      -- both so this doesn't error out depending on which one is running.
      local editBox = self.EditBox or self.editBox
      if not editBox then return end
      editBox:SetText((account and account.name) or "")
      editBox:HighlightText()
      editBox:SetFocus()
    end,
    OnAccept = function(self, account)
      local editBox = self.EditBox or self.editBox
      if not editBox or not account then return end
      local newName = strtrim(editBox:GetText() or "")
      if newName ~= "" then
        Data:RenameAccount(account.id, newName)
        Module:Render()
      end
    end,
    -- button3 -- opens a confirmation popup instead of deleting outright.
    -- Characters inside the account are deleted along with it (see
    -- Data:DeleteAccount) -- not moved anywhere.
    OnAlt = function(_, account)
      if not account then return end
      local numCharacters = TableCount(Data:GetCharactersByAccount(account.id, true))
      StaticPopup_Show("ALTEREGO_CONFIRM_DELETE_ACCOUNT", account.name, numCharacters, account)
    end,
    EditBoxOnEnterPressed = function(self)
      -- Going through StaticPopup_OnClick (the same dispatcher Blizzard's
      -- own popups use) instead of self:GetParent().button1:Click() --
      -- the button fields got restructured alongside the edit box in
      -- newer builds, so this is the version-safe way to trigger Accept.
      StaticPopup_OnClick(self:GetParent(), 1)
    end,
    EditBoxOnEscapePressed = function(self)
      self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

do
  local dialogName = "ALTEREGO_CONFIRM_DELETE_ACCOUNT"
  StaticPopupDialogs[dialogName] = {
    text = "Remove \"%s\"?\n\n%d character(s) inside it will be permanently deleted.\nThis cannot be undone.",
    button1 = YES,
    button2 = CANCEL,
    OnAccept = function(_, account)
      if account then
        local ok, err = Data:DeleteAccount(account.id)
        if not ok and err then
          addon.Core:Print(err)
        end
        Module:Render()
      end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

do
  local dialogName = "ALTEREGO_CONFIRM_CHANGE_MAIN_ACCOUNT"
  StaticPopupDialogs[dialogName] = {
    text = "Change Main WoW Account?\n\n%s is currently Main.\nSet %s as the new Main WoW Account?\n\nSync will send characters from the new Main account and protect them from incoming sync data.",
    button1 = "Change Main",
    button2 = CANCEL,
    OnAccept = function(_, account)
      if account then
        Data:SetMainAccount(account.id)
        if addon.Core.AnnounceSyncPresence then addon.Core:AnnounceSyncPresence() end
        Module:Render()
      end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

-- What RequestPasswordThen should do once a non-empty password is
-- actually confirmed via the popup below -- "enable" just turns Sync on,
-- "syncNow" turns it on AND immediately force-syncs. This is also what
-- guarantees Enable Sync and Sync Now never flip Sync on by themselves:
-- they only ever request a password, and it's the popup's OnAccept
-- (below) that does the enabling, and only when given a real one.
-- Cleared as soon as it's acted on, or the popup is cancelled/dismissed
-- without a password.
local pendingSyncAction = nil

do
  local dialogName = "ALTEREGO_CONFIRM_RESET_TRACKER_ORDER"
  StaticPopupDialogs[dialogName] = {
    text = "Reset custom order?\n\nThis restores the default order and categories for Currencies, Weeklies and Seasonal Chores.",
    button1 = "Reset",
    button2 = CANCEL,
    OnAccept = function()
      Data:ResetTrackerOrder()
      Module:Render()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

do
  local dialogName = "ALTEREGO_CONFIRM_RESET_DISPLAY_FILTERS"
  StaticPopupDialogs[dialogName] = {
    text = "Reset display filters and columns?\n\nThis restores the Character display filters and columns to their defaults. Sorting, trackers, minimap settings, window position/size, accounts, and Sync settings are not changed.",
    button1 = "Reset",
    button2 = CANCEL,
    OnAccept = function()
      Data:ResetDisplayFiltersAndColumns()
      Module:Render()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

do
  local dialogName = "ALTEREGO_CONFIRM_RESET_ALL_SETTINGS_STEP_1"
  StaticPopupDialogs[dialogName] = {
    text = "Reset ALL AlterEgo settings and saved data?\n\nThis will permanently remove every saved character and account, Sync settings/password, display and tracker settings, sorting, minimap settings, and window layout. AlterEgo will return to a clean-install state.",
    button1 = "Continue",
    button2 = CANCEL,
    OnAccept = function()
      StaticPopup_Show("ALTEREGO_CONFIRM_RESET_ALL_SETTINGS_STEP_2")
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

do
  local dialogName = "ALTEREGO_CONFIRM_RESET_ALL_SETTINGS_STEP_2"
  StaticPopupDialogs[dialogName] = {
    text = "FINAL WARNING\n\nThis cannot be undone. All AlterEgo SavedVariables will be reset and the UI will reload immediately. You will need to log in on characters again for AlterEgo to capture them.\n\nReset everything now?",
    button1 = "Reset & Reload",
    button2 = CANCEL,
    OnAccept = function()
      Data:ResetAllAddonSettings()
      ReloadUI()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

do
  local dialogName = "ALTEREGO_SYNC_PASSWORD"
  StaticPopupDialogs[dialogName] = {
    text = "Shared with your other WoW accounts to sync characters, and optionally addon settings, between them. It's not tied to your Battle.net login. It's a word/phrase you set the same way on every account you want to sync with.\n\nMust match exactly on every account you want to sync with.\n\n|cffffcc55Warning:|r Avoid generic passwords such as \"123\". You can use your own nickname if you prefer.",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
      -- The edit box region got renamed from `editBox` to `EditBox` in newer
      -- client builds (Blizzard_StaticPopup_Game/GameDialog.lua) -- check
      -- both so this doesn't error out depending on which one is running.
      local editBox = self.EditBox or self.editBox
      if not editBox then return end
      editBox:SetText(Data.db.global.sync.password or "")
      editBox:HighlightText()
      editBox:SetFocus()
    end,
    OnAccept = function(self)
      local editBox = self.EditBox or self.editBox
      if not editBox then return end
      local newPassword = strtrim(editBox:GetText() or "")
      Data.db.global.sync.password = newPassword
      if newPassword == "" then
        -- Clearing the password leaves Sync enabled but permanently
        -- unable to send/receive anything (GetUsablePassword would
        -- just keep refusing it) -- so treat it the same as flipping
        -- Enable Sync off by hand: stop immediately, including freeing
        -- up any in-progress batch guard, and say so.
        if Data.db.global.sync.enabled then
          Data.db.global.sync.enabled = false
          addon.Core:ResetSyncBatchGuard()
          addon.Core:Print("Sync: password cleared -- Enable Sync turned off and Sync stopped immediately.")
        end
        pendingSyncAction = nil
        return
      end
      -- A real password just got confirmed -- act on whatever Enable
      -- Sync or Sync Now was waiting on it, if anything. Neither of them
      -- ever flips Sync on by itself (see pendingSyncAction above), so
      -- this is the only place Sync actually turns on.
      local action = pendingSyncAction
      pendingSyncAction = nil
      if action == "enable" or action == "syncNow" or action == "syncSettings" then
        Data.db.global.sync.enabled = true
      end
      if Data.db.global.sync.enabled and addon.Core.AnnounceSyncPresence then
        addon.Core:AnnounceSyncPresence()
      end
      if action == "syncNow" then
        addon.Core:ForceSyncBroadcast()
      elseif action == "syncSettings" then
        StaticPopup_Show("ALTEREGO_SYNC_SETTINGS")
      end
    end,
    OnCancel = function()
      -- Dismissed without confirming a password -- whatever Enable
      -- Sync/Sync Now was waiting on doesn't happen.
      pendingSyncAction = nil
    end,
    EditBoxOnEnterPressed = function(self)
      -- Going through StaticPopup_OnClick (the same dispatcher Blizzard's
      -- own popups use) instead of self:GetParent().button1:Click() --
      -- the button fields got restructured alongside the edit box in
      -- newer builds, so this is the version-safe way to trigger Accept.
      StaticPopup_OnClick(self:GetParent(), 1)
    end,
    EditBoxOnEscapePressed = function(self)
      self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

-- Set when the Sync Password popup should open automatically (Enable
-- Sync just got turned on, or Sync Now got clicked) but can't right this
-- second because the player is in combat -- everything else Sync-related
-- already refuses to touch the UI mid-combat (see Comm.lua's
-- InCombatLockdown checks), so this popup follows the same rule instead
-- of just popping up over whatever's happening in a pull. Consumed the
-- moment PLAYER_REGEN_ENABLED fires, below.
local pendingPasswordPopup = false

---Opens the Sync Password popup if (and only if) Sync doesn't have one
---set yet, remembering what to do once a real password is confirmed
---(see pendingSyncAction/OnAccept above). Shared by the Enable Sync
---checkbox and the Sync Now button below -- both are places where
---turning Sync on without a password would otherwise either do nothing
---or, worse, turn Sync on with no way to actually send/receive anything.
---Never pops the dialog up during combat -- the request is remembered
---instead, and honored as soon as combat actually ends.
---@param action "enable"|"syncNow"|"syncSettings"|nil What Enable Sync, Sync Now,
---or Sync Addon Settings was trying to do -- carried out once a password is confirmed.
---@return boolean hadPassword True if a password was already set (no
---popup was needed) -- the caller can go ahead and do `action` itself.
local function RequestPasswordThen(action)
  local password = Data.db.global.sync.password
  if password and password ~= "" then return true end
  pendingSyncAction = action
  addon.Core:Print("Sync: no password set -- set one to turn Sync on.")
  if InCombatLockdown() then
    pendingPasswordPopup = true
  else
    StaticPopup_Show("ALTEREGO_SYNC_PASSWORD")
  end
  return false
end

addon.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
  if not pendingPasswordPopup then return end
  pendingPasswordPopup = false
  local password = Data.db.global.sync.password
  if not password or password == "" then
    StaticPopup_Show("ALTEREGO_SYNC_PASSWORD")
  end
end, true)

do
  local dialogName = "ALTEREGO_SYNC_SETTINGS"
  StaticPopupDialogs[dialogName] = {
    text = "Sync Addon Settings?\n\nThis shares your display and behavior settings (sorting, what's shown/hidden, colors, and similar) with your other WoW accounts over the same password and channel as character sync.\n\nThis does NOT share your characters, and does NOT change the password, Enable Sync, or Sync Channel on the other end.",
    button1 = "Share Settings",
    button2 = CANCEL,
    OnAccept = function()
      addon.Core:ShareSettings()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
  }
end

-- Guided setup for Multi-Account Sync. The tutorial deliberately stays shorter than the
-- individual setting tooltips: it explains the order of operations, what each control does,
-- and highlights where the user should click in the Main window.
local SYNC_TUTORIAL_STEPS = {
  {
    title = "Open Multi-Account Sync Settings",
    text = "All Sync controls live in Settings under Multi-Account Sync. Before configuring them, make sure AlterEgo is installed and enabled on every WoW account you want to connect, and that those clients can share a guild or party/raid addon channel.",
    target = "syncSection",
    location = "Settings > Multi-Account Sync",
  },
  {
    title = "Choose Your Main WoW Account",
    text = "Open Accounts & Characters and mark the WoW Account played by this AlterEgo installation as Main. Sync sends characters filed under that Main account. Characters received from another account stay in a separate WoW Account so they are not sent back in a loop.",
    target = "accounts",
    location = "Accounts & Characters",
  },
  {
    title = "Set the Same Password Everywhere",
    text = "Use Set Password and enter the exact same word or phrase on every WoW account you want to sync. This is only an AlterEgo Sync password, never your Battle.net password. Incoming data is accepted only when the password matches.\n\n|cffffcc55Warning:|r Avoid generic passwords such as \"123\". You can use your own nickname if you prefer.",
    target = "setPassword",
    location = "Settings > Multi-Account Sync > Set Password",
  },
  {
    title = "Choose a Sync Channel",
    text = "Sync Channel decides how your accounts reach each other. \"Guild\" uses the guild addon channel. \"Party/Raid\" requires all accounts to be on the same group. \"Both\" uses every available channels. Choose a channel every account can access at the same time.",
    target = "syncChannel",
    location = "Settings > Multi-Account Sync > Sync Channel",
  },
  {
    title = "Choose Which Characters to Send",
    text = "Only Sync Max Level Characters is enabled by default. Leave it on to share only current max-level characters, or turn it off to include leveling characters. Character and WoW Account enable/disable choices are still respected.",
    target = "onlyMaxLevel",
    location = "Settings > Multi-Account Sync > Enable Sync > Only Sync Max Level Characters",
  },
  {
    title = "Enable Sync on Every Account",
    text = "Turn on Enable Sync on each WoW account. AlterEgo announces its presence, compares character versions with matching peers, and automatically sends changed or missing eligible data when a usable channel is available. Multi-Account Sync will pause for combat/encounter restrictions and resume remaining data afterward.",
    target = "enableSync",
    location = "Settings > Multi-Account Sync > Enable Sync",
  },
  {
    title = "Test It with Sync Now",
    text = "Click Sync Now on one account while the other account is online and reachable. AlterEgo asks matching peers what they already have, then sends only eligible characters that are missing or outdated and prints progress/results in chat.",
    target = "syncNow",
    location = "Settings > Multi-Account Sync > Sync Now",
  },
  {
    title = "Optional: Sync Addon Settings",
    text = "Sync Addon Settings shares AlterEgo display and behavior preferences with the other account. We recommend using it on the account where everything is already set up the way you want, so those settings can be shared with the new account. It only runs when you click it and confirm.",
    target = "syncSettings",
    location = "Settings > Multi-Account Sync > Sync Addon Settings",
  },
  {
    title = "Sync Readiness Checklist",
    text = "Use this live checklist to confirm the local setup, see whether another matching Sync peer is currently detected, and check the most recent confirmed character sync. When the required items are green, use Sync Now to force a version reconciliation.",
    target = "syncNow",
    location = "Settings > Multi-Account Sync > Sync Now",
    readinessChecklist = true,
  },
}

local syncTutorialFrame = nil
-- Session-only tutorial progress. Reopening the guide resumes the last viewed step,
-- while /reload or a new login naturally resets this local back to step 1.
local syncTutorialSessionStep = 1
local syncTutorialHighlight = nil
local syncTutorialSettingsMenu = nil

-- Dynamic parent rows in Blizzard's Menu API keep the text that existed when the
-- description was created. Keep a direct handle to their current frame so a radio
-- choice can update that visible parent label immediately instead of showing stale
-- text until the entire Settings dropdown is reopened.
local liveMenuLabelFrames = setmetatable({}, {__mode = "k"})
local function BindLiveMenuLabel(description)
  if not description or not description.AddInitializer then return end
  description:AddInitializer(function(frame, desc)
    liveMenuLabelFrames[description] = frame
    if frame and frame.fontString then
      frame.fontString:SetText(MenuUtil.GetElementText(desc))
    end
  end)
end

local function SetLiveMenuLabel(description, text)
  if not description then return end
  if MenuUtil.SetElementText then
    MenuUtil.SetElementText(description, text)
  else
    description.text = text
  end
  local frame = liveMenuLabelFrames[description]
  if frame and frame:IsShown() and frame.fontString then
    frame.fontString:SetText(text)
  end
end

local syncTutorialWindowStorage = nil
local syncTutorialMenuTargets = {}
local syncTutorialMenuTargetDescriptions = {}
local syncTutorialMenuTargetText = {
  mainAccount = function(text)
    local mainAccountId = Data.GetMainAccountId and Data:GetMainAccountId()
    local account = mainAccountId and Data.db.global.accounts[mainAccountId]
    return account ~= nil and text:find(account.name, 1, true) == 1 and text:find("[Main]", 1, true) ~= nil
  end,
  syncSection = function(text) return text == "Multi-Account Sync" end,
  enableSync = function(text) return text == "Enable Sync" end,
  onlyMaxLevel = function(text) return text == "Only Sync Max Level Characters" end,
  setPassword = function(text) return text == "Set Password" or text:match("^Change Password:") ~= nil end,
  syncChannel = function(text) return text:match("^Sync Channel:") ~= nil end,
  syncNow = function(text) return text == "Sync Now" end,
  syncSettings = function(text) return text == "Sync Addon Settings" end,
}

local function IsSyncTutorialBlocked()
  return InCombatLockdown() or (IsEncounterInProgress and IsEncounterInProgress())
end

local function IncreaseSyncTutorialFont(fontString, extraSize)
  if not fontString or not fontString.GetFont or not fontString.SetFont then return end
  local font, size, flags = fontString:GetFont()
  if font and size then
    fontString:SetFont(font, size + (extraSize or 2), flags)
  end
end

local function GetSyncTutorialWindowStorage()
  if syncTutorialWindowStorage then return syncTutorialWindowStorage end

  local windows = Data.db.global.liqui.windows
  windows.SyncTutorial = windows.SyncTutorial or {}
  syncTutorialWindowStorage = windows.SyncTutorial

  -- Scale/color/border behave like every other LiqUI window and persist normally,
  -- but position is deliberately session-local: every fresh UI session starts at the high default anchor.
  syncTutorialWindowStorage.point = nil
  return syncTutorialWindowStorage
end

local function ApplyDefaultSyncTutorialPosition(frame)
  local storage = GetSyncTutorialWindowStorage()
  if not frame or storage.point then return end

  frame:ClearAllPoints()
  -- Start high on the screen while remaining horizontally centered. This keeps the
  -- tutorial close to AlterEgo's confirmation-dialog area without covering the middle
  -- of the gameplay view.
  frame:SetPoint("TOP", UIParent, "TOP", 0, -90)

  -- Save the resolved/clamped point for reopenings during this session. The next UI
  -- session clears only this point while preserving the rest of the window preferences.
  frame:SaveSettings()
end

---Find a Main-window titlebar button from its original config name. LiqUI stores the
---button frames in the same order as the config entries, which is more reliable than
---depending on generated global frame names (some button labels contain spaces).
---@param configName string
---@return Frame?
local function GetMainTitlebarButton(configName)
  local window = Module.window
  if not window or not window.titlebarButtons or not window.options or not window.options.titlebarButtons then
    return nil
  end
  for index, config in ipairs(window.options.titlebarButtons) do
    if config.name == configName then
      return window.titlebarButtons[index]
    end
  end
  return nil
end

---Keep the live Blizzard_Menu frame for tutorial-relevant settings while that menu is open.
---Those frames are temporary/recycled, so callers must still check IsShown() before using them.
---@param key string
---@param frame Frame
---@param description table?
local function RegisterSyncTutorialMenuTarget(key, frame, description)
  syncTutorialMenuTargets[key] = frame
  syncTutorialMenuTargetDescriptions[key] = description
end

local function IsLiveSyncTutorialMenuTarget(key, frame)
  if not frame or not frame:IsShown() then return false end
  local fontString = frame.fontString or frame.Text
  local text = fontString and fontString:GetText() or ""
  local matcher = syncTutorialMenuTargetText[key]
  return matcher and matcher(text or "") or false
end

local function GetSyncTutorialTargetFrame(step)
  if not step then return nil end

  local exact = step.target and syncTutorialMenuTargets[step.target]
  if IsLiveSyncTutorialMenuTarget(step.target, exact) then
    return exact
  end

  -- The max-level option is a child submenu of Enable Sync. Until that submenu is open,
  -- highlight its parent so the user knows exactly where to hover/click next.
  if step.target == "onlyMaxLevel" then
    local enableSync = syncTutorialMenuTargets.enableSync
    if IsLiveSyncTutorialMenuTarget("enableSync", enableSync) then
      return enableSync
    end
  end

  if step.target == "accounts" or step.target == "mainAccount" then
    return GetMainTitlebarButton("Accounts & Characters")
  end

  -- Every other Sync control lives below the Settings gear. If its exact menu row is not
  -- currently visible, point to the gear first; opening it lets AddInitializer replace this
  -- fallback with the exact row automatically.
  local window = Module.window
  return window and window.titlebar and window.titlebar.SettingsButton or nil
end

---Scroll the root Settings menu enough to bring a tutorial target into view without
---selecting it. Menu rows are ordinary pooled frames, so this is purely navigation.
---@param key string
local function ScrollSyncTutorialTargetIntoView(key)
  local settingsMenu = syncTutorialSettingsMenu
  local target = syncTutorialMenuTargets[key]
  if not settingsMenu or not settingsMenu:IsShown() or not target or not target:IsShown() then return end
  local scrollBox = settingsMenu.ScrollBox
  if not scrollBox or not scrollBox:IsShown() then return end

  local viewTop, viewBottom = scrollBox:GetTop(), scrollBox:GetBottom()
  local targetTop, targetBottom = target:GetTop(), target:GetBottom()
  local scrollRange = scrollBox.GetDerivedScrollRange and scrollBox:GetDerivedScrollRange() or 0
  if not viewTop or not viewBottom or not targetTop or not targetBottom or not scrollRange or scrollRange <= 0 then
    return
  end

  local percentage = scrollBox:GetScrollPercentage() or 0
  local padding = 8
  if targetTop > viewTop - padding then
    percentage = percentage - ((targetTop - (viewTop - padding)) / scrollRange)
  elseif targetBottom < viewBottom + padding then
    percentage = percentage + (((viewBottom + padding) - targetBottom) / scrollRange)
  else
    return
  end

  percentage = math.max(0, math.min(1, percentage))
  scrollBox:SetScrollPercentage(percentage, ScrollBoxConstants.NoScrollInterpolation)
  Module.settingsMenuScrollPercentage = percentage
end

---Navigate the tutorial to the control for the current step without invoking that
---control's responder. DropdownButton:OpenMenu and description:ForceOpenSubmenu only
---open UI; they do not toggle checkboxes, choose radios, or press buttons.
---@param step table
local function NavigateSyncTutorialToStep(step)
  if not step then return end
  local window = Module.window
  if not window or not window:IsShown() then return end

  if step.target == "accounts" or step.target == "mainAccount" then
    local accountsButton = GetMainTitlebarButton("Accounts & Characters")
    if accountsButton and accountsButton.OpenMenu then
      accountsButton:OpenMenu()
    end

    -- For readiness failures caused by having no selected Main-account
    -- characters, go one step further and open the Main account's character
    -- submenu. This is navigation only; it never toggles the account or any
    -- character checkbox automatically.
    if step.target == "mainAccount" then
      C_Timer.After(0, function()
        if not syncTutorialFrame or not syncTutorialFrame:IsShown() then return end
        local description = syncTutorialMenuTargetDescriptions.mainAccount
        if description and description.CanOpenSubmenu and description:CanOpenSubmenu() then
          description:ForceOpenSubmenu()
        end
      end)
    end
    return
  end

  local settingsButton = window.titlebar and window.titlebar.SettingsButton
  if not settingsButton or not settingsButton.OpenMenu then return end
  if not settingsButton:IsMenuOpen() then
    settingsButton:OpenMenu()
  end

  -- Let Blizzard finish acquiring/repositioning the scrolling menu before moving it.
  C_Timer.After(0, function()
    if not syncTutorialFrame or not syncTutorialFrame:IsShown() then return end

    local rootTarget = step.target == "onlyMaxLevel" and "enableSync" or step.target
    ScrollSyncTutorialTargetIntoView(rootTarget)

    C_Timer.After(0, function()
      if not syncTutorialFrame or not syncTutorialFrame:IsShown() then return end

      if step.target == "onlyMaxLevel" then
        local description = syncTutorialMenuTargetDescriptions.enableSync
        if description and description.CanOpenSubmenu and description:CanOpenSubmenu() then
          description:ForceOpenSubmenu()
        end
      elseif step.target == "syncChannel" then
        local description = syncTutorialMenuTargetDescriptions.syncChannel
        if description and description.CanOpenSubmenu and description:CanOpenSubmenu() then
          description:ForceOpenSubmenu()
        end
      end

    end)
  end)
end

local function EnsureSyncTutorialHighlight()
  if syncTutorialHighlight then return syncTutorialHighlight end

  local highlight = CreateFrame("Frame", addon.name .. "SyncTutorialHighlight", UIParent, "BackdropTemplate")
  highlight:SetFrameStrata("TOOLTIP")
  highlight:SetFrameLevel(10000)
  highlight:EnableMouse(false)
  highlight:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  highlight:SetBackdropBorderColor(1, 0.82, 0, 1)
  highlight.fill = highlight:CreateTexture(nil, "BACKGROUND")
  highlight.fill:SetAllPoints()
  highlight.fill:SetColorTexture(1, 0.82, 0, 0.08)
  highlight:Hide()
  highlight:SetScript("OnUpdate", function(self)
    if not syncTutorialFrame or not syncTutorialFrame:IsShown() then
      self:Hide()
      return
    end

    local step = SYNC_TUTORIAL_STEPS[syncTutorialFrame.stepIndex or 1]
    if syncTutorialFrame.highlightTarget then
      step = { target = syncTutorialFrame.highlightTarget }
    end
    local target = GetSyncTutorialTargetFrame(step)
    if not target or not target:IsVisible() then
      self:Hide()
      return
    end

    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", target, "TOPLEFT", -4, 4)
    self:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 4, -4)
    self:SetAlpha(0.72 + 0.22 * math.sin(GetTime() * 4))
    self:Show()
  end)

  syncTutorialHighlight = highlight
  return highlight
end

local function HideSyncTutorialHighlight()
  if syncTutorialHighlight then
    syncTutorialHighlight:Hide()
  end
end

local function GetSyncTutorialEligibleCharacterStatus()
  local mainAccountId = Data.GetMainAccountId and Data:GetMainAccountId()
  local mainAccount = mainAccountId and Data.db.global.accounts[mainAccountId]
  local allMainCharacters = mainAccountId and Data:GetCharactersByAccount(mainAccountId, true) or {}
  local eligibleCharacters = Data.GetSyncEligibleCharacters and Data:GetSyncEligibleCharacters() or Data:GetCharacters(true)
  local onlyMaxLevel = Data.db.global.sync.onlyMaxLevelCharacters ~= false

  local eligibleCount = 0
  for _, character in ipairs(eligibleCharacters) do
    if not onlyMaxLevel or Data:IsMaxLevelCharacter(character) then
      eligibleCount = eligibleCount + 1
    end
  end

  local enabledMainCount = #eligibleCharacters
  local totalMainCount = #allMainCharacters
  local detail = format("%d ready to send", eligibleCount)
  local target = mainAccountId and "mainAccount" or "accounts"
  local buttonText = "Open Main Account"

  if not mainAccountId then
    detail = "0 ready; Main account not selected"
    target = "accounts"
    buttonText = "Open Accounts"
  elseif mainAccount and mainAccount.enabled == false then
    detail = "0 ready; Main account tracking is off"
    target = "mainAccount"
    buttonText = "Open Main Account"
  elseif totalMainCount == 0 then
    detail = "0 ready; no characters in Main account"
    target = "mainAccount"
    buttonText = "Open Main Account"
  elseif enabledMainCount == 0 then
    detail = "0 ready; no Main account characters selected"
    target = "mainAccount"
    buttonText = "Open Main Account"
  elseif onlyMaxLevel and eligibleCount == 0 then
    local maxLevel = Data.GetCurrentMaxLevel and Data:GetCurrentMaxLevel()
    detail = maxLevel
      and format("0 ready; %d selected, none detected at level %d", enabledMainCount, maxLevel)
      or format("0 ready; %d selected, max level unavailable", enabledMainCount)
    target = "mainAccount"
  end

  return eligibleCount, detail, target, buttonText
end

local function GetSyncTutorialChannelStatus()
  local setting = Data.db.global.sync.channel or "GUILD"
  local guildAvailable = IsInGuild()
  local groupAvailable = IsInRaid() or IsInGroup()

  if setting == "GUILD" then
    return guildAvailable, guildAvailable and "Guild available" or "Guild unavailable"
  elseif setting == "PARTY" then
    return groupAvailable, groupAvailable and (IsInRaid() and "Raid available" or "Party available") or "Party/Raid unavailable"
  end

  local available = {}
  if guildAvailable then table.insert(available, "Guild") end
  if groupAvailable then table.insert(available, IsInRaid() and "Raid" or "Party") end
  if #available > 0 then
    return true, "Both selected; available: " .. table.concat(available, " + ")
  end
  return false, "No selected channel is available"
end

local function GetSyncTutorialReadinessRows()
  local rows = {}
  local mainAccountId = Data.GetMainAccountId and Data:GetMainAccountId()
  local mainAccount = mainAccountId and Data.db.global.accounts[mainAccountId]
  table.insert(rows, {
    ready = mainAccountId ~= nil,
    label = "Main WoW Account",
    detail = mainAccount and mainAccount.name or "Not selected",
    target = "accounts",
    buttonText = "Open Accounts",
  })

  local password = Data.db.global.sync.password
  table.insert(rows, {
    ready = password ~= nil and password ~= "",
    label = "Password",
    detail = (password ~= nil and password ~= "") and "Configured" or "Not configured",
    target = "setPassword",
    buttonText = "Open Password",
  })

  table.insert(rows, {
    ready = Data.db.global.sync.enabled == true,
    label = "Enable Sync",
    detail = Data.db.global.sync.enabled and "On" or "Off",
    target = "enableSync",
    buttonText = "Open Enable Sync",
  })

  local channelReady, channelDetail = GetSyncTutorialChannelStatus()
  table.insert(rows, {
    ready = channelReady,
    label = "Sync Channel",
    detail = channelDetail,
    target = "syncChannel",
    buttonText = "Open Channel",
  })

  local eligibleCount, eligibleDetail, eligibleTarget, eligibleButtonText = GetSyncTutorialEligibleCharacterStatus()
  table.insert(rows, {
    ready = eligibleCount > 0,
    label = "Eligible Characters",
    detail = eligibleDetail,
    target = eligibleTarget,
    buttonText = eligibleButtonText,
  })

  local peerStatus = addon.Core.GetSyncPeerStatus and addon.Core:GetSyncPeerStatus() or { count = 0, names = {}, lastSuccessfulSyncAt = 0, lastSuccessfulSyncPeer = "" }
  local peerNames = peerStatus.names or {}
  table.insert(rows, {
    ready = (peerStatus.count or 0) > 0,
    label = "Sync Peer",
    detail = (peerStatus.count or 0) > 0 and format("Detected: %s", table.concat(peerNames, ", ")) or "No matching peer detected",
  })

  local lastSyncAt = tonumber(peerStatus.lastSuccessfulSyncAt) or 0
  local lastSyncPeer = peerStatus.lastSuccessfulSyncPeer or ""
  table.insert(rows, {
    ready = lastSyncAt > 0,
    informational = true,
    label = "Last Successful Sync",
    detail = lastSyncAt > 0 and format("%s%s", date("%Y-%m-%d %H:%M", lastSyncAt), lastSyncPeer ~= "" and (" with " .. lastSyncPeer) or "") or "No confirmed character sync yet",
  })

  local blocked = IsSyncTutorialBlocked()
  table.insert(rows, {
    ready = not blocked,
    label = "Combat / Encounter",
    detail = blocked and "Blocked until combat/encounter ends" or "Clear",
  })

  return rows
end

local function RefreshSyncTutorialReadinessChecklist()
  if not syncTutorialFrame or not syncTutorialFrame.readinessPanel then return end
  local step = SYNC_TUTORIAL_STEPS[syncTutorialFrame.stepIndex or 1]
  local show = step and step.readinessChecklist == true
  syncTutorialFrame.readinessPanel:SetShown(show)
  if not show then return end

  local rows = GetSyncTutorialReadinessRows()
  local allReady = true
  for index, row in ipairs(rows) do
    if not row.informational then
      allReady = allReady and row.ready
    end
    local rowFrame = syncTutorialFrame.readinessRows[index]
    if rowFrame then
      local state
      if row.informational and not row.ready then
        state = "|cff66b3ffINFO|r"
      else
        state = row.ready and "|cff55dd77READY|r" or "|cffff6666CHECK|r"
      end
      rowFrame.text:SetText(format("%s  %s: |cffffffff%s|r", state, row.label, row.detail))
      rowFrame.target = row.target
      rowFrame.text:ClearAllPoints()
      rowFrame.text:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
      rowFrame.text:SetPoint("RIGHT", rowFrame, "RIGHT", row.target and -136 or 0, 0)
      rowFrame.openButton:SetShown(row.target ~= nil)
      rowFrame.openButton:SetEnabled(row.target ~= nil)
      rowFrame.openButton:SetText(row.buttonText or "Open")
      rowFrame.openPulse:SetShown(row.target ~= nil and not row.ready and not row.informational)
    end
  end

  if syncTutorialFrame.readinessSummary then
    if allReady then
      syncTutorialFrame.readinessSummary:SetText("|cff55dd77Local setup is ready.|r  Use Sync Now to test the connection.")
    else
      syncTutorialFrame.readinessSummary:SetText("|cffffcc55Complete the items marked CHECK.|r  Use the shortcut buttons to open the related setting.")
    end
  end
  if syncTutorialFrame.readinessSyncNowButton then
    syncTutorialFrame.readinessSyncNowButton:SetShown(allReady)
    syncTutorialFrame.readinessSyncNowPulse:SetShown(allReady)
  end
  if syncTutorialFrame.readinessSummary then
    syncTutorialFrame.readinessSummary:ClearAllPoints()
    syncTutorialFrame.readinessSummary:SetPoint("TOPLEFT", syncTutorialFrame.readinessPanel, "TOPLEFT", 12, -272)
    if allReady then
      syncTutorialFrame.readinessSummary:SetPoint("RIGHT", syncTutorialFrame.readinessSyncNowButton, "LEFT", -10, 0)
    else
      syncTutorialFrame.readinessSummary:SetPoint("RIGHT", syncTutorialFrame.readinessPanel, "RIGHT", -12, 0)
    end
  end
end

local function RefreshSyncTutorial()
  if not syncTutorialFrame then return end

  local index = math.max(1, math.min(syncTutorialFrame.stepIndex or 1, #SYNC_TUTORIAL_STEPS))
  syncTutorialFrame.stepIndex = index
  syncTutorialSessionStep = index
  local step = SYNC_TUTORIAL_STEPS[index]

  syncTutorialFrame.stepCounter:SetText(format("STEP %d / %d", index, #SYNC_TUTORIAL_STEPS))
  syncTutorialFrame.stepTitle:SetText(step.title)
  syncTutorialFrame.stepText:SetText(step.text)
  syncTutorialFrame.locationText:SetText(GREEN_FONT_COLOR:WrapTextInColorCode("Look here: ") .. step.location)
  syncTutorialFrame.previousButton:SetEnabled(index > 1)
  syncTutorialFrame.nextButton:SetText(index == #SYNC_TUTORIAL_STEPS and "Done" or "Next")

  for dotIndex, dot in ipairs(syncTutorialFrame.progressDots) do
    if dotIndex == index then
      dot:SetColorTexture(1, 0.82, 0, 1)
    elseif dotIndex < index then
      dot:SetColorTexture(0.35, 0.85, 0.45, 0.8)
    else
      dot:SetColorTexture(0.45, 0.45, 0.45, 0.5)
    end
  end

  RefreshSyncTutorialReadinessChecklist()
  EnsureSyncTutorialHighlight():Show()
end

local function HideSyncTutorial()
  if syncTutorialFrame and syncTutorialFrame:IsShown() then
    syncTutorialFrame:Hide()
  end
  HideSyncTutorialHighlight()
end

function Module:ShowSyncTutorial()
  if not syncTutorialFrame then
    -- Reuse LiqUI's own Window element so the tutorial inherits AlterEgo's standard titlebar,
    -- border, background, drag behavior, close button, and overall visual language.
    local frame = LibLiqUI:NewElement("Window", {
      name = addon.name .. "SyncTutorial",
      title = "Multi-Account Sync Tutorial",
      icon = Constants.media.LogoTransparent,
      width = 620,
      height = 660,
      border = 1,
      storage = GetSyncTutorialWindowStorage(),
    })
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)

    -- Keep LiqUI's normal Settings cog. Scale/color/border persist like other windows;
    -- only the tutorial position resets at the start of each UI session.
    if frame.titlebar and frame.titlebar.title then
      IncreaseSyncTutorialFont(frame.titlebar.title, 2)
    end

    local body = frame.body

    frame.header = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.header:SetPoint("TOPLEFT", body, "TOPLEFT", 24, -20)
    frame.header:SetText("GUIDED MULTI-ACCOUNT SETUP")
    frame.header:SetTextColor(0.7, 0.7, 0.7, 1)
    IncreaseSyncTutorialFont(frame.header, 2)

    frame.stepCounter = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.stepCounter:SetPoint("TOPRIGHT", body, "TOPRIGHT", -24, -20)
    frame.stepCounter:SetTextColor(0.7, 0.7, 0.7, 1)
    IncreaseSyncTutorialFont(frame.stepCounter, 2)

    frame.progressDots = {}
    frame.progressButtons = {}
    for index = 1, #SYNC_TUTORIAL_STEPS do
      local stepIndex = index
      local stepButton = CreateFrame("Button", nil, body)
      stepButton:SetSize(46, 16)
      if index == 1 then
        stepButton:SetPoint("TOPLEFT", body, "TOPLEFT", 24, -36)
      else
        stepButton:SetPoint("LEFT", frame.progressButtons[index - 1], "RIGHT", 4, 0)
      end

      local dot = stepButton:CreateTexture(nil, "ARTWORK")
      dot:SetSize(46, 3)
      dot:SetPoint("CENTER")
      frame.progressDots[index] = dot
      frame.progressButtons[index] = stepButton

      stepButton:SetScript("OnClick", function()
        frame.highlightTarget = nil
        frame.stepIndex = stepIndex
        RefreshSyncTutorial()
      end)
      stepButton:SetScript("OnEnter", function(button)
        dot:SetAlpha(1)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(format("Step %d: %s", stepIndex, SYNC_TUTORIAL_STEPS[stepIndex].title), 1, 1, 1)
        GameTooltip:AddLine("Click to jump directly to this step.", nil, nil, nil, true)
        GameTooltip:Show()
      end)
      stepButton:SetScript("OnLeave", function()
        dot:SetAlpha(0.9)
        GameTooltip:Hide()
      end)
    end

    frame.locationPanel = CreateFrame("Button", nil, body)
    frame.locationPanel:SetPoint("TOPLEFT", body, "TOPLEFT", 24, -62)
    frame.locationPanel:SetPoint("TOPRIGHT", body, "TOPRIGHT", -24, -62)
    frame.locationPanel:SetHeight(44)
    frame.locationPanel:EnableMouse(true)
    frame.locationPanel:RegisterForClicks("LeftButtonUp")
    SetBackgroundColor(frame.locationPanel, 1, 1, 1, 0.06)
    frame.locationPanel:SetScript("OnEnter", function(panel)
      SetBackgroundColor(panel, 1, 1, 1, 0.12)
    end)
    frame.locationPanel:SetScript("OnLeave", function(panel)
      SetBackgroundColor(panel, 1, 1, 1, 0.06)
    end)

    -- Make the navigation affordance unmistakable without triggering any setting itself.
    frame.locationPulse = CreateFrame("Frame", nil, frame.locationPanel, "BackdropTemplate")
    frame.locationPulse:SetPoint("TOPLEFT", frame.locationPanel, "TOPLEFT", -2, 2)
    frame.locationPulse:SetPoint("BOTTOMRIGHT", frame.locationPanel, "BOTTOMRIGHT", 2, -2)
    frame.locationPulse:SetFrameLevel(frame.locationPanel:GetFrameLevel() + 3)
    frame.locationPulse:EnableMouse(false)
    frame.locationPulse:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame.locationPulse:SetBackdropBorderColor(1, 0.82, 0, 0.85)
    frame.locationPulse:SetScript("OnUpdate", function(pulse)
      pulse:SetAlpha(0.58 + 0.30 * math.sin(GetTime() * 4.5))
    end)
    frame.locationPanel:SetScript("OnClick", function()
      local step = SYNC_TUTORIAL_STEPS[frame.stepIndex or 1]
      -- Defer until after this click finishes so an already-open Blizzard menu can close cleanly
      -- before the requested dropdown/submenu is opened.
      C_Timer.After(0, function()
        NavigateSyncTutorialToStep(step)
      end)
    end)

    frame.locationIcon = frame.locationPanel:CreateTexture(nil, "ARTWORK")
    frame.locationIcon:SetPoint("LEFT", frame.locationPanel, "LEFT", 10, 0)
    frame.locationIcon:SetSize(18, 18)
    frame.locationIcon:SetTexture(Constants.media.LogoTransparent)

    frame.clickHereText = frame.locationPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.clickHereText:SetPoint("RIGHT", frame.locationPanel, "RIGHT", -12, 0)
    frame.clickHereText:SetText("<  CLICK HERE")
    frame.clickHereText:SetTextColor(1, 0.82, 0, 1)
    IncreaseSyncTutorialFont(frame.clickHereText, 3)

    frame.locationText = frame.locationPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.locationText:SetPoint("LEFT", frame.locationIcon, "RIGHT", 8, 0)
    frame.locationText:SetPoint("RIGHT", frame.clickHereText, "LEFT", -14, 0)
    frame.locationText:SetJustifyH("LEFT")
    IncreaseSyncTutorialFont(frame.locationText, 3)

    frame.stepTitle = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.stepTitle:SetPoint("TOPLEFT", frame.locationPanel, "BOTTOMLEFT", 0, -22)
    frame.stepTitle:SetPoint("RIGHT", body, "RIGHT", -24, 0)
    frame.stepTitle:SetJustifyH("LEFT")
    IncreaseSyncTutorialFont(frame.stepTitle, 3)

    frame.stepText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.stepText:SetPoint("TOPLEFT", frame.stepTitle, "BOTTOMLEFT", 0, -14)
    frame.stepText:SetPoint("RIGHT", body, "RIGHT", -24, 0)
    frame.stepText:SetJustifyH("LEFT")
    frame.stepText:SetJustifyV("TOP")
    frame.stepText:SetWordWrap(true)
    IncreaseSyncTutorialFont(frame.stepText, 3)

    frame.readinessPanel = CreateFrame("Frame", nil, body, "BackdropTemplate")
    frame.readinessPanel:SetPoint("TOPLEFT", frame.stepText, "BOTTOMLEFT", 0, -18)
    frame.readinessPanel:SetPoint("RIGHT", body, "RIGHT", -24, 0)
    frame.readinessPanel:SetHeight(330)
    frame.readinessPanel:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame.readinessPanel:SetBackdropColor(0, 0, 0, 0.24)
    frame.readinessPanel:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.75)

    frame.readinessHeader = frame.readinessPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.readinessHeader:SetPoint("TOPLEFT", frame.readinessPanel, "TOPLEFT", 12, -10)
    frame.readinessHeader:SetText("LIVE READINESS")
    IncreaseSyncTutorialFont(frame.readinessHeader, 2)

    frame.readinessRows = {}
    for index = 1, 8 do
      local rowFrame = CreateFrame("Frame", nil, frame.readinessPanel)
      rowFrame:SetPoint("TOPLEFT", frame.readinessPanel, "TOPLEFT", 12, -34 - ((index - 1) * 28))
      rowFrame:SetPoint("RIGHT", frame.readinessPanel, "RIGHT", -12, 0)
      rowFrame:SetHeight(26)

      rowFrame.text = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      rowFrame.text:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
      rowFrame.text:SetPoint("RIGHT", rowFrame, "RIGHT", -136, 0)
      rowFrame.text:SetJustifyH("LEFT")
      rowFrame.text:SetWordWrap(false)
      IncreaseSyncTutorialFont(rowFrame.text, 2)

      rowFrame.openButton = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
      rowFrame.openButton:SetSize(126, 24)
      rowFrame.openButton:SetPoint("RIGHT", rowFrame, "RIGHT", 0, 0)
      rowFrame.openButton:SetText("Open")
      IncreaseSyncTutorialFont(rowFrame.openButton:GetFontString(), 1)
      rowFrame.openButton:SetScript("OnClick", function()
        if not rowFrame.target then return end
        frame.highlightTarget = rowFrame.target
        C_Timer.After(0, function()
          NavigateSyncTutorialToStep({ target = rowFrame.target })
        end)
      end)

      rowFrame.openPulse = CreateFrame("Frame", nil, rowFrame.openButton, "BackdropTemplate")
      rowFrame.openPulse:SetPoint("TOPLEFT", rowFrame.openButton, "TOPLEFT", -2, 2)
      rowFrame.openPulse:SetPoint("BOTTOMRIGHT", rowFrame.openButton, "BOTTOMRIGHT", 2, -2)
      rowFrame.openPulse:SetFrameLevel(rowFrame.openButton:GetFrameLevel() + 3)
      rowFrame.openPulse:EnableMouse(false)
      rowFrame.openPulse:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
      })
      rowFrame.openPulse:SetBackdropBorderColor(1, 0.82, 0, 0.9)
      rowFrame.openPulse:SetScript("OnUpdate", function(pulse)
        pulse:SetAlpha(0.58 + 0.30 * math.sin(GetTime() * 4.5))
      end)
      rowFrame.openPulse:Hide()

      frame.readinessRows[index] = rowFrame
    end

    frame.readinessSyncNowButton = CreateFrame("Button", nil, frame.readinessPanel, "UIPanelButtonTemplate")
    frame.readinessSyncNowButton:SetSize(126, 24)
    -- Keep the shortcut on the same visual row as the readiness summary
    -- ("Local setup is ready") instead of dropping it to the panel bottom.
    frame.readinessSyncNowButton:SetPoint("TOPRIGHT", frame.readinessPanel, "TOPRIGHT", -12, -266)
    frame.readinessSyncNowButton:SetText("Open Sync Now")
    IncreaseSyncTutorialFont(frame.readinessSyncNowButton:GetFontString(), 1)
    frame.readinessSyncNowButton:SetScript("OnClick", function()
      frame.highlightTarget = "syncNow"
      C_Timer.After(0, function()
        NavigateSyncTutorialToStep({ target = "syncNow" })
      end)
    end)
    frame.readinessSyncNowButton:Hide()

    frame.readinessSyncNowPulse = CreateFrame("Frame", nil, frame.readinessSyncNowButton, "BackdropTemplate")
    frame.readinessSyncNowPulse:SetPoint("TOPLEFT", frame.readinessSyncNowButton, "TOPLEFT", -2, 2)
    frame.readinessSyncNowPulse:SetPoint("BOTTOMRIGHT", frame.readinessSyncNowButton, "BOTTOMRIGHT", 2, -2)
    frame.readinessSyncNowPulse:SetFrameLevel(frame.readinessSyncNowButton:GetFrameLevel() + 3)
    frame.readinessSyncNowPulse:EnableMouse(false)
    frame.readinessSyncNowPulse:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame.readinessSyncNowPulse:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    frame.readinessSyncNowPulse:SetScript("OnUpdate", function(pulse)
      pulse:SetAlpha(0.58 + 0.30 * math.sin(GetTime() * 4.5))
    end)
    frame.readinessSyncNowPulse:Hide()

    frame.readinessSummary = frame.readinessPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.readinessSummary:SetPoint("TOPLEFT", frame.readinessPanel, "TOPLEFT", 12, -272)
    frame.readinessSummary:SetPoint("RIGHT", frame.readinessPanel, "RIGHT", -12, 0)
    frame.readinessSummary:SetHeight(44)
    frame.readinessSummary:SetJustifyH("LEFT")
    frame.readinessSummary:SetJustifyV("TOP")
    frame.readinessSummary:SetWordWrap(true)
    IncreaseSyncTutorialFont(frame.readinessSummary, 1)

    frame.readinessPanel.refreshElapsed = 0
    frame.readinessPanel:SetScript("OnUpdate", function(panel, elapsed)
      if not panel:IsShown() then return end
      panel.refreshElapsed = (panel.refreshElapsed or 0) + elapsed
      if panel.refreshElapsed < 0.4 then return end
      panel.refreshElapsed = 0
      RefreshSyncTutorialReadinessChecklist()
    end)
    frame.readinessPanel:Hide()

    frame.hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.hint:SetPoint("BOTTOM", body, "BOTTOM", 0, 66)
    frame.hint:SetText("Click Look here to open the highlighted setting so you can set it up.")
    IncreaseSyncTutorialFont(frame.hint, 2)

    frame.previousButton = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    frame.previousButton:SetSize(120, 28)
    frame.previousButton:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 24, 22)
    frame.previousButton:SetText("Previous")
    IncreaseSyncTutorialFont(frame.previousButton:GetFontString(), 2)
    frame.previousButton:SetScript("OnClick", function()
      frame.highlightTarget = nil
      frame.stepIndex = math.max(1, (frame.stepIndex or 1) - 1)
      RefreshSyncTutorial()
    end)

    frame.nextButton = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    frame.nextButton:SetSize(120, 28)
    frame.nextButton:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -24, 22)
    IncreaseSyncTutorialFont(frame.nextButton:GetFontString(), 2)
    frame.nextButton:SetScript("OnClick", function()
      if (frame.stepIndex or 1) >= #SYNC_TUTORIAL_STEPS then
        HideSyncTutorial()
        return
      end
      frame.highlightTarget = nil
      frame.stepIndex = (frame.stepIndex or 1) + 1
      RefreshSyncTutorial()
    end)

    frame:HookScript("OnHide", HideSyncTutorialHighlight)
    syncTutorialFrame = frame
  end

  syncTutorialFrame.stepIndex = syncTutorialSessionStep
  syncTutorialFrame.highlightTarget = nil
  RefreshSyncTutorial()
  syncTutorialFrame:Show()

  -- First open in each UI session defaults high on the screen. LiqUI then stores any
  -- user drag in our session-only table, so reopening remembers it until /reload/logout.
  ApplyDefaultSyncTutorialPosition(syncTutorialFrame)
end


local CHARACTER_WIDTH = 130
local RAIDS_ROW_HEIGHT = 48

-- Raid boss icons are laid out against the *current* character-column width.
-- A single character can grow wider than CHARACTER_WIDTH when the titlebar needs
-- extra room, so using the fixed width here would leave the icon grid stuck on
-- the left side of the expanded column.
local function LayoutRaidEncounterIcons(difficultyFrame, numEncounters, columnWidth)
  if not difficultyFrame or not difficultyFrame.iconFrames or not numEncounters or numEncounters <= 0 then return end

  columnWidth = math.max(columnWidth or CHARACTER_WIDTH, 1)
  local gapWidth = 6
  local encounterX = 3
  local halfEncounters = math.ceil(numEncounters / 2)
  local gapCount = halfEncounters + 1
  local gapWidthTotal = gapCount * gapWidth
  local iconSize = math.max(1, (columnWidth - gapWidthTotal) / (halfEncounters + (numEncounters % 2 == 0 and 0.5 or 0)))
  local iconSlotHeight = RAIDS_ROW_HEIGHT * 0.5
  local iconSlotInset = 2
  local maxRenderedIconSize = math.max(1, iconSlotHeight - (iconSlotInset * 2))
  local killIcon = TableGet(Constants.raidKillIcons, "id", Data.db.global.raids.killIcon or "skull") or Constants.raidKillIcons[1]
  local killIconScale = killIcon.scale or 1
  -- Clamp the final rendered texture inside the top/bottom half-row with an
  -- explicit inset. Keeping a small gutter around every shape avoids texture
  -- filtering (especially on Skull/Diamond edges) visually bleeding into the
  -- neighboring difficulty quadrant even when the frame itself is in-bounds.
  local iconHeight = math.min(iconSize * killIconScale, maxRenderedIconSize)

  for encounterIndex = 1, numEncounters do
    local iconFrame = difficultyFrame.iconFrames[encounterIndex]
    if iconFrame then
      encounterX = encounterX + gapWidth / 2 + (iconSize / 2)
      -- Each encounter stays centered inside its own top/bottom half of the
      -- difficulty row, so every icon remains inside that difficulty quadrant.
      local encounterY = encounterIndex % 2 == 0 and (iconSlotHeight * 1.5) or (iconSlotHeight * 0.5)

      iconFrame:ClearAllPoints()
      iconFrame:SetPoint("CENTER", difficultyFrame, "TOPLEFT", encounterX, -encounterY)
      iconFrame:SetSize(iconHeight, iconHeight)
    end
  end
end

local function LayoutTimewalkingRaidIcons(timewalkingFrame, numBosses, columnWidth)
  if not timewalkingFrame or not timewalkingFrame.iconFrames or not numBosses or numBosses <= 0 then return end

  columnWidth = math.max(columnWidth or CHARACTER_WIDTH, 1)
  local killIcon = TableGet(Constants.raidKillIcons, "id", Data.db.global.raids.killIcon or "skull") or Constants.raidKillIcons[1]
  local killIconScale = killIcon.scale or 1
  local slotWidth = columnWidth / numBosses
  local iconHeight = math.min(slotWidth * 0.6, RAIDS_ROW_HEIGHT * 0.8) * killIconScale

  for bossIndex = 1, numBosses do
    local iconFrame = timewalkingFrame.iconFrames[bossIndex]
    if iconFrame then
      iconFrame:ClearAllPoints()
      iconFrame:SetPoint("CENTER", timewalkingFrame, "TOPLEFT", (bossIndex - 0.5) * slotWidth, -RAIDS_ROW_HEIGHT / 2)
      iconFrame:SetSize(iconHeight, iconHeight)
    end
  end
end

local dungeonPortalUnlockLevel = 10
local vaultMythicPlusMinLevel = 2
local vaultMaxLevelRewardMythic = 10
local vaultMaxLevelRewardWorld = 8
local vaultMaxNumRunsMythic = 8
local preyWeeklyHuntCap = 5
local vaultSlotOneIndex = 1
local vaultTooltipTexts = {
  [Enum.WeeklyRewardChestThresholdType.Raid] = {
    ["objective"] = "|4boss:bosses;",
    ["default"] = "Defeat bosses this week to unlock your first Great Vault reward.",
    ["firstSlotStart"] = "Defeat %1$d |4boss:bosses; this week to unlock your first Great Vault reward.",
    ["firstSlotMore"] = "Defeat %1$d more |4boss:bosses; this week to unlock your first Great Vault reward.",
    ["nextSlotMore"] = "Defeat %1$d more |4boss:bosses; this week to unlock another Great Vault reward.",
    ["rewardsImprove"] = "Defeat bosses on %s difficulty or higher to improve your Great Vault rewards.",
    ["rewardsMaxed"] = "Good job - You are done! There are no more rewards to improve.",
  },
  [Enum.WeeklyRewardChestThresholdType.Activities] = {
    ["objective"] = "|4dungeon:dungeons;",
    ["default"] = "Complete a Timewalking, Heroic or Mythic dungeon this week to unlock your first Great Vault reward.",
    ["firstSlotStart"] = "Complete %1$d Timewalking, Heroic or Mythic |4dungeon:dungeons; this week to unlock your first Great Vault reward.",
    ["firstSlotMore"] = "Complete %1$d more Timewalking, Heroic or Mythic |4dungeon:dungeons; this week to unlock your first Great Vault reward.",
    ["nextSlotMore"] = "Complete %1$d more Timewalking, Heroic or Mythic |4dungeon:dungeons; this week to unlock another Great Vault reward.",
    ["rewardsImprove"] = "Complete Mythic dungeons on level %d or higher to improve your Great Vault rewards.",
    ["rewardsMaxed"] = "Good job - You are done! There are no more rewards to improve. Time to work on your rating?",
  },
  [Enum.WeeklyRewardChestThresholdType.World] = {
    ["objective"] = "|4activity:activities;",
    ["default"] = "Complete delves, world activities, Prey, or Ritual Sites this week to unlock your first Great Vault reward.",
    ["firstSlotStart"] = "Complete %1$d |4activity:activities; this week (delves, world activities, Prey, or Ritual Sites) to unlock your first Great Vault reward.",
    ["firstSlotMore"] = "Complete %1$d more |4activity:activities; this week (delves, world activities, Prey, or Ritual Sites) to unlock your first Great Vault reward.",
    ["nextSlotMore"] = "Complete %1$d more |4activity:activities; this week (delves, world activities, Prey, or Ritual Sites) to unlock another Great Vault reward.",
    ["rewardsImprove"] = "Complete delves on tier %d or higher to improve your Great Vault rewards.",
    ["rewardsMaxed"] = "Good job - You are done! There are no more rewards to improve.",
  },
}

---Check if an activity is completed at a heroic level
---@param activityTierID number
---@return boolean
local function isCompletedAtHeroicLevel(activityTierID)
  local difficultyID = C_WeeklyRewards.GetDifficultyIDForActivityTier(activityTierID)
  return difficultyID == DifficultyUtil.ID.DungeonHeroic
end

---Great Vault item level for a Mythic+ keystone level
---@param keystoneLevel number
---@return integer?
local function getMythicPlusVaultItemLevel(keystoneLevel)
  if type(keystoneLevel) ~= "number" or keystoneLevel < vaultMythicPlusMinLevel then
    return nil
  end
  local seasonID = Data:GetCurrentSeason()
  local levels = Data.mythicPlusVaultItemLevels[seasonID]
  if not levels then
    return nil
  end
  local itemLevel = levels[keystoneLevel]
  if itemLevel then
    return itemLevel
  end
  if keystoneLevel > vaultMaxLevelRewardMythic then
    return levels[vaultMaxLevelRewardMythic]
  end
  return nil
end

---Whether this character has confirmed Great Vault reward history. The
---history is only created after the native vault was opened and concrete
---reward items were returned; progress/example links do not qualify.
---@param character AE_Character
---@return boolean
local function characterHasVaultPreviewData(character)
  return Data:HasVaultHistory(character)
end

---Print vault progress to tooltip
---@param infoFrame Frame
---@param character AE_Character
---@param activityType Enum.WeeklyRewardChestThresholdType
local function getVaultProgressTooltip(infoFrame, character, activityType)
  local loggedCharacter = Data:GetCharacter()
  local difficulties = Data:GetRaidDifficulties(true)
  local dungeons = Data:GetDungeons()
  local raids = Data:GetRaids()
  local activities = TableFilter(character.vault.slots or {}, function(activity) return activity.type and activity.type == activityType end)
  local numActivities = TableCount(activities)
  local activitiesInProgress = TableFilter(activities, function(slot) return slot.progress < slot.threshold end)
  local numActivitiesInProgress = TableCount(activitiesInProgress)
  table.sort(activities, function(a, b) return a.index < b.index end)
  table.sort(activitiesInProgress, function(a, b) return a.threshold < b.threshold end)
  local vaultTooltipText = vaultTooltipTexts[activityType]
  local numHeroic = 0
  local numMythic = 0
  local numMythicPlus = 0

  if character.mythicplus ~= nil and character.mythicplus.numCompletedDungeonRuns ~= nil then
    numHeroic = character.mythicplus.numCompletedDungeonRuns.heroic or 0
    numMythic = character.mythicplus.numCompletedDungeonRuns.mythic or 0
    numMythicPlus = character.mythicplus.numCompletedDungeonRuns.mythicPlus or 0
  end

  GameTooltip:SetOwner(infoFrame, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Vault Progress", 1, 1, 1)

  do -- Activity Progress
    for i = 1, 3 do
      local textLeft = format("Vault Slot %d:", i)
      local textRight = "Locked"
      local color = LIGHTGRAY_FONT_COLOR

      local activity = TableGet(activities, "index", i)
      if activity then
        textLeft = format("%d %s:", activity.threshold, string.lower(activity.type and vaultTooltipTexts[activity.type] and vaultTooltipTexts[activity.type]["objective"] or vaultTooltipText["objective"]))
        if activity.progress >= activity.threshold then
          textRight = "Unlocked"
          color = WHITE_FONT_COLOR

          -- Difficulty name
          if activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
            local raidDifficultyID = GetBaseDifficultyID(activity.level)
            local difficultyName = GetDifficultyInfo(raidDifficultyID)
            local dataDifficulty = TableGet(difficulties, "id", raidDifficultyID)
            if dataDifficulty then
              textRight = dataDifficulty.short and dataDifficulty.short or dataDifficulty.name
            elseif difficultyName then
              textRight = difficultyName
            end
          elseif activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
            if isCompletedAtHeroicLevel(activity.activityTierID) then
              textRight = WEEKLY_REWARDS_HEROIC
            else
              textRight = WEEKLY_REWARDS_MYTHIC:format(activity.level)
            end
          elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
            textRight = GREAT_VAULT_WORLD_TIER:format(activity.level)
          end

          if activity.exampleRewardLink ~= nil and activity.exampleRewardLink ~= "" then
            local itemLevel = C_Item.GetDetailedItemLevelInfo(activity.exampleRewardLink)
            if itemLevel then
              textRight = format("%s (%d+)", textRight, itemLevel)
            end
          end
        else
          textRight = format("Locked (%d/%d)", activity.progress, activity.threshold)
        end
      else
        -- Get activity threshold and objective from logged in character since current character is missing vault activity data
        local activityInfo = TableFind(loggedCharacter and loggedCharacter.vault and loggedCharacter.vault.slots or {}, function(slot) return slot.type == activityType and slot.index == i end)
        if activityInfo then
          textLeft = format("%d %s:", activityInfo.threshold, string.lower(activityInfo.type and vaultTooltipTexts[activityInfo.type] and vaultTooltipTexts[activityInfo.type]["objective"] or vaultTooltipText["objective"]))
          textRight = format("Locked (%d/%d)", 0, activityInfo.threshold)
        end
      end
      GameTooltip:AddDoubleLine(textLeft, textRight, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, color.r, color.g, color.b)
    end
  end

  do -- Raid stats
    if activityType == Enum.WeeklyRewardChestThresholdType.Raid then
      local raidInstanceID = nil
      local activityEncounterInfo = character.vault.activityEncounterInfo or {}
      TableForEach(raids, function(raid)
        if raidInstanceID ~= raid.instanceID then
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(raid.name)
        end

        TableForEach(raid.encounters or {}, function(encounter)
          local bestDifficulty = nil
          local color = DISABLED_FONT_COLOR
          local difficultyName = "-"

          local encounterInfo = TableFind(activityEncounterInfo, function(activityEncounter)
            return activityEncounter.instanceID == raid.journalInstanceID and activityEncounter.encounterID == encounter.journalEncounterID and activityEncounter.index == 1
          end)

          if encounterInfo and encounterInfo.bestDifficulty then
            bestDifficulty = TableGet(difficulties, "id", GetBaseDifficultyID(encounterInfo.bestDifficulty))
          end

          if bestDifficulty then
            color = GREEN_FONT_COLOR
            difficultyName = bestDifficulty.short and bestDifficulty.short or bestDifficulty.name
          end

          GameTooltip:AddDoubleLine(encounter.name, difficultyName, color.r, color.g, color.b, color.r, color.g, color.b)
        end)

        raidInstanceID = raid.instanceID
      end)
    end
  end

  do -- Dungeon stats
    if activityType == Enum.WeeklyRewardChestThresholdType.Activities then
      if numHeroic + numMythic + numMythicPlus > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Total Runs This Week:")
        if numHeroic > 0 then
          GameTooltip:AddDoubleLine("Heroic", tostring(numHeroic), 1, 1, 1, 1, 1, 1)
        end
        if numMythic > 0 then
          GameTooltip:AddDoubleLine("Mythic", tostring(numMythic), 1, 1, 1, 1, 1, 1)
        end
        if numMythicPlus > 0 then
          GameTooltip:AddDoubleLine("Mythic+", tostring(numMythicPlus), 1, 1, 1, 1, 1, 1)
        end
      end
    end
  end

  do -- Dungeon runs
    if activityType == Enum.WeeklyRewardChestThresholdType.Activities then
      local runsThisWeek = TableFilter(character.mythicplus.runHistory or {}, function(run) return run.thisWeek == true end)
      local numRunsThisWeek = TableCount(runsThisWeek)
      local numMaxRuns = vaultMaxNumRunsMythic
      table.sort(runsThisWeek, function(a, b) return a.level > b.level end)

      if numRunsThisWeek + numHeroic + numMythic > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Top Runs This Week:")
      end

      -- Detect max runs needed
      local lastActivity = activities[numActivities]
      if lastActivity then
        numMaxRuns = lastActivity.threshold
      end
      local missingRuns = numMaxRuns - numRunsThisWeek

      if numRunsThisWeek > 0 then
        TableForEach(runsThisWeek, function(run, i)
          if i > numMaxRuns then return end
          local rewardLevel = getMythicPlusVaultItemLevel(run.level)
          local dungeon = TableGet(dungeons, "challengeModeID", run.mapChallengeModeID)
          local dungeonName = "Mythic+"
          local color = WHITE_FONT_COLOR
          local matchesThreshold = TableFind(character.vault.slots or {}, function(activity)
            return activity.type and activity.type == activityType and activity.threshold and activity.threshold == i
          end)
          if matchesThreshold then
            color = GREEN_FONT_COLOR
          end
          if dungeon then
            dungeonName = dungeon.short and dungeon.short or dungeon.name
          end
          local rightText = string.format("+%d", run.level)
          if rewardLevel then
            rightText = string.format("+%d (%d)", run.level, rewardLevel)
          end
          GameTooltip:AddDoubleLine(dungeonName, rightText, 1, 1, 1, color.r, color.g, color.b)
        end)
      end

      if missingRuns > 0 then
        local countHeroic = numHeroic
        local countMythic = numMythic
        while countMythic > 0 and missingRuns > 0 do
          GameTooltip:AddLine(format(WEEKLY_REWARDS_MYTHIC, WeeklyRewardsUtil.MythicLevel), 1, 1, 1)
          countMythic = countMythic - 1
          missingRuns = missingRuns - 1
        end
        while countHeroic > 0 and missingRuns > 0 do
          GameTooltip:AddLine(WEEKLY_REWARDS_HEROIC, 1, 1, 1)
          countHeroic = countHeroic - 1
          missingRuns = missingRuns - 1
        end
      end
    end
  end

  do -- World activities
    if activityType == Enum.WeeklyRewardChestThresholdType.World then
      local worldActivityProgress = character.vault.worldActivityProgress or {}
      local desiredRuns = vaultMaxLevelRewardWorld
      local lastActivity = activities[numActivities]
      if lastActivity then
        desiredRuns = lastActivity.threshold
      end

      local hasProgress = false
      TableForEach(worldActivityProgress, function(tierProgress)
        if tierProgress.numPoints and tierProgress.numPoints > 0 then
          hasProgress = true
        end
      end)

      if hasProgress and desiredRuns > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(WEEKLY_REWARDS_WORLD_TOP_ACTIVITIES:format(desiredRuns))
        for _, tierProgress in ipairs(worldActivityProgress) do
          if desiredRuns <= 0 then
            break
          end
          local numRuns = math.min(tierProgress.numPoints, desiredRuns)
          if numRuns <= 0 then
            break
          end
          desiredRuns = desiredRuns - numRuns
          if tierProgress.difficulty > 1 then
            GameTooltip:AddLine(WEEKLY_REWARDS_DELVE_TIER_INFO:format(tierProgress.difficulty, numRuns), 1, 1, 1)
          else
            GameTooltip:AddLine(WEEKLY_REWARDS_DELVE_TIER_AND_WORLD_INFO:format(tierProgress.difficulty, numRuns), 1, 1, 1)
          end
        end
      end
    end
  end

  do -- Progress instructions
    local text = ""
    if vaultTooltipText then
      if numActivities == 0 then
        text = vaultTooltipText["default"]
      end
      if numActivitiesInProgress > 0 then -- Still unlocking vault slots
        local currentActivityInProgress = activitiesInProgress[1]
        if currentActivityInProgress then
          local missing = currentActivityInProgress.threshold - currentActivityInProgress.progress
          if currentActivityInProgress.index == vaultSlotOneIndex then
            if currentActivityInProgress.progress == 0 then
              text = format(vaultTooltipText["firstSlotStart"], missing)
            else
              text = format(vaultTooltipText["firstSlotMore"], missing)
            end
          else
            text = format(vaultTooltipText["nextSlotMore"], missing)
          end
        end
      elseif numActivities > 0 then -- All slots unlocked: What's next?
        if activityType == Enum.WeeklyRewardChestThresholdType.Raid then
          local activity = activities[numActivities]
          local nextDifficultyID = DifficultyUtil.GetNextPrimaryRaidDifficultyID(GetBaseDifficultyID(activity.level))
          if nextDifficultyID then
            local difficulty = TableGet(difficulties, "id", nextDifficultyID)
            if difficulty then
              text = format(vaultTooltipText["rewardsImprove"], difficulty.name)
            end
          else
            text = vaultTooltipText["rewardsMaxed"]
          end
        elseif activityType == Enum.WeeklyRewardChestThresholdType.Activities then
          local activity = activities[numActivities]
          local level = Helpers:GetLowestLevelInTopDungeonRuns(character, activity.threshold)
          if level and level < vaultMaxLevelRewardMythic then
            text = format(vaultTooltipText["rewardsImprove"], WeeklyRewardsUtil.GetNextMythicLevel(level))
          else
            text = vaultTooltipText["rewardsMaxed"]
          end
        elseif activityType == Enum.WeeklyRewardChestThresholdType.World then
          local activity = activities[numActivities]
          if activity then
            if activity.level < vaultMaxLevelRewardWorld then
              text = format(vaultTooltipText["rewardsImprove"], activity.level + 1)
            else
              text = vaultTooltipText["rewardsMaxed"]
            end
          end
        end
      end
      if text ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Next Step:")
        GameTooltip:AddLine(text, 1, 1, 1, true)
      end
    end
  end
  GameTooltip:Show()
end

---Get vault progress value for display
---@param character AE_Character
---@param activityType Enum.WeeklyRewardChestThresholdType
---@return string
local function getVaultProgressValue(character, activityType)
  local difficulties = Data:GetRaidDifficulties(true)
  local activities = TableFilter(character.vault.slots or {}, function(activity) return activity.type and activity.type == activityType end)
  local texts = {}

  for i = 1, 3 do
    local text = "-"
    local color = LIGHTGRAY_FONT_COLOR

    local activity = TableGet(activities, "index", i)
    if activity and activity.progress >= activity.threshold then
      text = "?"
      color = UNCOMMON_GREEN_COLOR

      if activityType == Enum.WeeklyRewardChestThresholdType.Raid then
        local raidDifficultyID = GetBaseDifficultyID(activity.level)
        local dataDifficulty = TableGet(difficulties, "id", raidDifficultyID)
        local difficultyName = GetDifficultyInfo(raidDifficultyID)
        if difficultyName then
          text = difficultyName
        end
        if dataDifficulty then
          text = dataDifficulty.abbr and dataDifficulty.abbr or dataDifficulty.name
          if Data.db.global.raids.colors and dataDifficulty.color then
            color = dataDifficulty.color
          end
        end

        text = tostring(text):sub(1, 1)
      elseif activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
        if isCompletedAtHeroicLevel(activity.activityTierID) then
          text = WEEKLY_REWARDS_HEROIC:sub(1, 1)
        else
          text = tostring(activity.level)
        end
      elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
        text = tostring(activity.level)
      end
    end

    table.insert(texts, color:WrapTextInColorCode(text))
  end

  return table.concat(texts, "  ")
end

---Get character info rows for the grid
---@param unfiltered boolean?
---@return AE_CharacterRows[]
function Module:GetCharacterInfo(unfiltered)
  local dungeons = Data:GetDungeons()
  local _, seasonDisplayID = Data:GetCurrentSeason()
  local equipmentModule = addon.Core:GetModule("Equipment", true)
  local bonusRollsModule = addon.Core:GetModule("BonusRolls", true)
  local vaultPreviewModule = addon.Core:GetModule("VaultPreview", true)

  ---@type AE_CharacterRows[]
  local rows = {
    {
      label = CHARACTER,
      value = function(character, characterIndex)
        local name = "-"
        local nameColor = "ffffffff"
        if character.info.name ~= nil then
          name = character.info.name
        end
        local positionSuffix = ""
        if Data.db.global.showCharacterPosition and characterIndex then
          positionSuffix = WHITE_FONT_COLOR:WrapTextInColorCode(format(" - %d", characterIndex))
        end
        if character.info.class.file ~= nil then
          local classColor = C_ClassColor.GetClassColor(character.info.class.file)
          if classColor ~= nil then
            nameColor = classColor.GenerateHexColor(classColor)
          end
        end
        local coloredName = "|c" .. nameColor .. name .. "|r" .. positionSuffix
        if character.GUID ~= UnitGUID("player") then
          return coloredName
        end
        local marker = Data.db.global.currentCharacterMarker
        local markerColor = Data.db.global.currentCharacterMarkerColor
        local currentColor = markerColor and CreateColor(markerColor.r, markerColor.g, markerColor.b) or GREEN_FONT_COLOR
        if marker == "brackets" then
          return currentColor:WrapTextInColorCode("[ ") .. coloredName .. currentColor:WrapTextInColorCode(" ]")
        end
        if marker == "parentheses" then
          return currentColor:WrapTextInColorCode("( ") .. coloredName .. currentColor:WrapTextInColorCode(" )")
        end
        if marker == "dot" then
          return coloredName .. Constants.currentCharacterNameMarker
        end
        return coloredName
      end,
      onEnter = function(infoFrame, character)
        local name = "-"
        local nameColor = WHITE_FONT_COLOR
        if character.info.name ~= nil then
          name = character.info.name
        end
        if character.info.class.file ~= nil then
          local classColor = C_ClassColor.GetClassColor(character.info.class.file)
          if classColor ~= nil then
            nameColor = CreateColor(classColor.r, classColor.g, classColor.b, 1)
          end
        end
        name = format("%s (%s)", nameColor:WrapTextInColorCode(name), character.info.realm)
        GameTooltip:SetOwner(infoFrame, "ANCHOR_RIGHT")
        GameTooltip:AddLine(name, 1, 1, 1)
        if character.info.guild ~= nil and character.info.guild.isInGuild then
          GameTooltip:AddLine(format("<%s>", character.info.guild.name), NECROLORD_GREEN_COLOR.r, NECROLORD_GREEN_COLOR.g, NECROLORD_GREEN_COLOR.b)
        end
        GameTooltip:AddLine(format("Level %d %s", character.info.level, character.info.race ~= nil and character.info.race.name or ""), 1, 1, 1)
        if character.info.factionGroup ~= nil and character.info.factionGroup.localized ~= nil then
          GameTooltip:AddLine(character.info.factionGroup.localized, 1, 1, 1)
        end
        if character.info.lastLocation ~= nil and character.info.lastLocation ~= "" then
          GameTooltip:AddLine(format("Last location: %s", character.info.lastLocation), 1, 1, 1)
        end
        if character.money ~= nil then
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(GetMoneyString(character.money, true), 1, 1, 1)
        end
        if character.lastUpdate ~= nil then
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(format("Last update:\n|cffffffff%s|r", date("%d/%m - %H:%M", character.lastUpdate)), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        end
        if (type(character.equipment) == "table" and equipmentModule) or bonusRollsModule then
          GameTooltip:AddLine(" ")
        end
        if type(character.equipment) == "table" and equipmentModule then
          GameTooltip:AddLine("<Left-click to View Equipment>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
        end
        if bonusRollsModule then
          GameTooltip:AddLine("<Right-click to View Bonus Rolls>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
        end
        GameTooltip:Show()
      end,
      onLeave = function()
        GameTooltip:Hide()
      end,
      onClick = function(infoFrame, character)
        if not equipmentModule then return end
        equipmentModule:OpenCharacter(character)
      end,
      onRightClick = function(infoFrame, character)
        if not bonusRollsModule then return end
        bonusRollsModule:OpenCharacter(character)
      end,
      enabled = true,
    },
    {
      label = "Realm",
      value = function(character)
        local realm = "-"
        local realmColor = LIGHTGRAY_FONT_COLOR
        if character.info.realm ~= nil then
          realm = character.info.realm
          realmColor = WHITE_FONT_COLOR
        end
        return realmColor:WrapTextInColorCode(realm)
      end,
      tooltip = false,
      enabled = Data.db.global.showRealms,
    },
    {
      label = "Guild",
      value = function(character)
        local guild = "-"
        local guildColor = WHITE_FONT_COLOR
        if character.info.guild == nil then
          guildColor = LIGHTGRAY_FONT_COLOR
        elseif character.info.guild.isInGuild then
          if character.info.guild.name ~= nil and character.info.guild.name ~= "" then
            guild = character.info.guild.name
            guildColor = NECROLORD_GREEN_COLOR
          else
            guildColor = LIGHTGRAY_FONT_COLOR
          end
        end
        return guildColor:WrapTextInColorCode(guild)
      end,
      onEnter = function(infoFrame, character)
        GameTooltip:SetOwner(infoFrame, "ANCHOR_RIGHT")
        if character.info.guild == nil then
          GameTooltip:AddLine("Guild", 1, 1, 1)
          GameTooltip:AddLine("Log in to update your guild information.")
        elseif character.info.guild.isInGuild and character.info.guild.name ~= nil then
          local realmName = character.info.realm
          if character.info.guild.realm ~= nil and strlenutf8(character.info.guild.realm) > 0 then
            realmName = character.info.guild.realm
          end
          GameTooltip:AddLine(character.info.guild.name, 1, 1, 1)
          GameTooltip:AddDoubleLine("Rank:", character.info.guild.rankName ~= nil and character.info.guild.rankName or "-", nil, nil, nil, 1, 1, 1)
          GameTooltip:AddDoubleLine("Realm:", realmName, nil, nil, nil, 1, 1, 1)
        else
          GameTooltip:AddLine("Guild", 1, 1, 1)
          GameTooltip:AddLine("Not in a guild.")
        end
        GameTooltip:Show()
      end,
      onLeave = function()
        GameTooltip:Hide()
      end,
      enabled = Data.db.global.showGuildInformation,
    },
    {
      label = STAT_AVERAGE_ITEM_LEVEL,
      value = function(character)
        local itemLevel = "-"
        local itemLevelColor = LIGHTGRAY_FONT_COLOR:GenerateHexColor()
        if character.info.ilvl ~= nil then
          local displayLevel = character.info.ilvl.potential or character.info.ilvl.level
          if Data.db.global.showEquippedItemLevel and character.info.ilvl.equipped ~= nil then
            displayLevel = character.info.ilvl.equipped
          end
          if displayLevel ~= nil then
            if Data.db.global.showItemLevelDecimals then
              itemLevel = format("%.2f", displayLevel)
            else
              itemLevel = tostring(floor(displayLevel))
            end
          end
          itemLevelColor = Helpers:GetItemLevelTrackColor(displayLevel):GenerateHexColor()
        end
        return WrapTextInColorCode(itemLevel, itemLevelColor)
      end,
      onEnter = function(infoFrame, character)
        local itemLevelTooltip = ""
        local itemLevelTooltip2 = STAT_AVERAGE_ITEM_LEVEL_TOOLTIP
        if character.info.ilvl ~= nil then
          local decimals = Data.db.global.showItemLevelDecimals and 2 or 0
          local equipped = character.info.ilvl.equipped
          local inBags = character.info.ilvl.potential or character.info.ilvl.level
          if equipped ~= nil then
            itemLevelTooltip = HIGHLIGHT_FONT_COLOR_CODE .. "Item Level " .. format("%." .. decimals .. "f", equipped)
            if inBags ~= nil and floor(inBags) ~= floor(equipped) then
              itemLevelTooltip = itemLevelTooltip .. format(" (%." .. decimals .. "f in bags)", inBags)
            end
            itemLevelTooltip = itemLevelTooltip .. FONT_COLOR_CODE_CLOSE
          elseif inBags ~= nil then
            itemLevelTooltip = HIGHLIGHT_FONT_COLOR_CODE .. "Item Level " .. format("%." .. decimals .. "f", inBags) .. FONT_COLOR_CODE_CLOSE
          end
          if inBags ~= nil and character.info.ilvl.pvp ~= nil and floor(inBags) ~= character.info.ilvl.pvp then
            itemLevelTooltip2 = itemLevelTooltip2 .. "\n\n" .. STAT_AVERAGE_PVP_ITEM_LEVEL:format(tostring(floor(character.info.ilvl.pvp)))
          end
        end
        GameTooltip:SetOwner(infoFrame, "ANCHOR_RIGHT")
        GameTooltip:AddLine(itemLevelTooltip, 1, 1, 1)
        GameTooltip:AddLine(itemLevelTooltip2, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
        GameTooltip:Show()
      end,
      onLeave = function()
        GameTooltip:Hide()
      end,
      enabled = Data.db.global.showItemLevel,
    },
    {
      label = "Rating",
      value = function(character)
        local rating = "-"
        local ratingColor = LIGHTGRAY_FONT_COLOR
        if character.mythicplus.rating ~= nil and C_MythicPlus.IsMythicPlusActive() then
          rating = tostring(character.mythicplus.rating)
          local color = Helpers:GetRatingColor(character.mythicplus.rating, Data.db.global.useRIOScoreColor, false)
          if color ~= nil then
            ratingColor = CreateColor(color.r, color.g, color.b, color.a)
          else
            ratingColor = WHITE_FONT_COLOR
          end
        end
        return ratingColor:WrapTextInColorCode(rating)
      end,
      onEnter = function(infoFrame, character)
        local rating = "-"
        local ratingColor = WHITE_FONT_COLOR
        local bestSeasonScore = nil
        local bestSeasonScoreColor = WHITE_FONT_COLOR
        local bestSeasonNumber = nil
        local numSeasonRuns = 0
        if character.mythicplus.runHistory ~= nil then
          numSeasonRuns = TableCount(character.mythicplus.runHistory)
        end
        if character.mythicplus.bestSeasonNumber ~= nil then
          bestSeasonNumber = character.mythicplus.bestSeasonNumber
        end
        if character.mythicplus.bestSeasonScore ~= nil then
          bestSeasonScore = character.mythicplus.bestSeasonScore
          local color = Helpers:GetRatingColor(bestSeasonScore, Data.db.global.useRIOScoreColor, bestSeasonNumber ~= nil and bestSeasonNumber < seasonDisplayID)
          if color ~= nil then
            bestSeasonScoreColor = CreateColor(color.r, color.g, color.b, color.a)
          end
        end
        if type(character.mythicplus.rating) == "number" then
          local color = Helpers:GetRatingColor(character.mythicplus.rating, Data.db.global.useRIOScoreColor, false)
          if color ~= nil then
            ratingColor = CreateColor(color.r, color.g, color.b, color.a)
          end
          rating = tostring(character.mythicplus.rating)
        end

        GameTooltip:SetOwner(infoFrame, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Mythic+ Rating", 1, 1, 1)
        if not C_MythicPlus.IsMythicPlusActive() then
          GameTooltip:AddLine("Mythic+ is not active.", DIM_RED_FONT_COLOR.r, DIM_RED_FONT_COLOR.g, DIM_RED_FONT_COLOR.b)
        else
          -- Season information
          GameTooltip:AddDoubleLine("Current Season:", ratingColor:WrapTextInColorCode(rating), nil, nil, nil, ratingColor.r, ratingColor.g, ratingColor.b)
          if bestSeasonNumber ~= nil and bestSeasonScore ~= nil then
            local bestSeasonValue = bestSeasonScoreColor:WrapTextInColorCode(tostring(bestSeasonScore))
            if bestSeasonNumber > 0 then
              local season = LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(format("(Season %s)", bestSeasonNumber))
              bestSeasonValue = format("%s %s", bestSeasonValue, season)
            end
            GameTooltip:AddDoubleLine("Best Season:", bestSeasonValue, nil, nil, nil, 1, 1, 1)
          end
          GameTooltip:AddDoubleLine("Runs this Season:", WHITE_FONT_COLOR:WrapTextInColorCode(tostring(numSeasonRuns)), nil, nil, nil, WHITE_FONT_COLOR.r, WHITE_FONT_COLOR.g, WHITE_FONT_COLOR.b)

          -- Dungeon information
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine("Highest Keys:")
          TableForEach(dungeons, function(dungeon)
            local level = "-"
            local levelColor = LIGHTGRAY_FONT_COLOR
            if character.mythicplus.dungeons ~= nil and TableCount(character.mythicplus.dungeons) > 0 then
              local characterDungeon = TableGet(character.mythicplus.dungeons, "challengeModeID", dungeon.challengeModeID)
              if characterDungeon ~= nil and type(characterDungeon.level) == "number" and characterDungeon.level > 0 then
                level = format("+%s", tostring(characterDungeon.level))
                levelColor = WHITE_FONT_COLOR
              end
            end
            GameTooltip:AddDoubleLine(dungeon.name, level, 1, 1, 1, levelColor.r, levelColor.g, levelColor.b)
          end)
          if numSeasonRuns > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("<Shift Click to Link to Chat>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
          end
        end
        GameTooltip:Show()
      end,
      onLeave = function()
        GameTooltip:Hide()
      end,
      onClick = function(infoFrame, character)
        local numSeasonRuns = 0
        if character.mythicplus.runHistory ~= nil then
          numSeasonRuns = TableCount(character.mythicplus.runHistory)
        end
        if character.mythicplus.dungeons ~= nil
          and TableCount(character.mythicplus.dungeons) > 0
          and numSeasonRuns > 0
          and IsModifiedClick("CHATLINK")
        then
          local dungeonScoreDungeonTable = {}
          for _, dungeon in pairs(character.mythicplus.dungeons) do
            table.insert(dungeonScoreDungeonTable, dungeon.challengeModeID)
            table.insert(dungeonScoreDungeonTable, dungeon.finishedSuccess and 1 or 0)
            table.insert(dungeonScoreDungeonTable, dungeon.level)
          end
          local dungeonScoreTable = {
            character.mythicplus.rating,
            character.GUID,
            character.info.name,
            character.info.class.id,
            math.ceil(character.info.ilvl.level),
            character.info.level,
            numSeasonRuns,
            character.mythicplus.bestSeasonScore,
            character.mythicplus.bestSeasonNumber,
            unpack(dungeonScoreDungeonTable),
          }
          local link = NORMAL_FONT_COLOR:WrapTextInColorCode(LinkUtil.FormatLink("dungeonScore", DUNGEON_SCORE_LINK, unpack(dungeonScoreTable)))
          if not ChatFrameUtil.InsertLink(link) then
            ChatFrameUtil.OpenChat(link)
          end
        end
      end,
      enabled = Data.db.global.showRating,
    },
    {
      label = "Current Keystone",
      value = function(character)
        local currentKeystone = LIGHTGRAY_FONT_COLOR:WrapTextInColorCode("-")
        if character.mythicplus.keystone ~= nil then
          local dungeon
          if type(character.mythicplus.keystone.challengeModeID) == "number" and character.mythicplus.keystone.challengeModeID > 0 then
            dungeon = TableGet(dungeons, "challengeModeID", character.mythicplus.keystone.challengeModeID)
          elseif type(character.mythicplus.keystone.mapId) == "number" and character.mythicplus.keystone.mapId > 0 then
            dungeon = TableGet(dungeons, "mapId", character.mythicplus.keystone.mapId)
          end
          if dungeon ~= nil then
            currentKeystone = dungeon.abbr
            if type(character.mythicplus.keystone.level) == "number" and character.mythicplus.keystone.level > 0 then
              currentKeystone = format("%s +%s", currentKeystone, tostring(character.mythicplus.keystone.level))
            end
          end
        end
        return currentKeystone
      end,
      onEnter = function(infoFrame, character)
        if character.mythicplus.keystone == nil then return end
        local itemLink = character.mythicplus.keystone.itemLink
        if type(itemLink) == "string" and itemLink ~= "" then
          GameTooltip:SetOwner(infoFrame, "ANCHOR_RIGHT")
          GameTooltip:SetHyperlink(itemLink)
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine("<Shift Click to Link to Chat>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
          GameTooltip:Show()
          return
        end
        local dungeon
        if type(character.mythicplus.keystone.challengeModeID) == "number" and character.mythicplus.keystone.challengeModeID > 0 then
          dungeon = TableGet(dungeons, "challengeModeID", character.mythicplus.keystone.challengeModeID)
        elseif type(character.mythicplus.keystone.mapId) == "number" and character.mythicplus.keystone.mapId > 0 then
          dungeon = TableGet(dungeons, "mapId", character.mythicplus.keystone.mapId)
        end
        if dungeon == nil then return end
        GameTooltip:SetOwner(infoFrame, "ANCHOR_RIGHT")
        GameTooltip:SetText(dungeon.name, 1, 1, 1)
        if type(character.mythicplus.keystone.level) == "number" and character.mythicplus.keystone.level > 0 then
          GameTooltip:AddLine(format("Mythic Keystone Level %d", character.mythicplus.keystone.level), 1, 1, 1)
        end
        GameTooltip:Show()
      end,
      onLeave = function()
        GameTooltip:Hide()
      end,
      onClick = function(infoFrame, character)
        if character.mythicplus.keystone ~= nil and type(character.mythicplus.keystone.itemLink) == "string" and character.mythicplus.keystone.itemLink ~= "" then
          if IsModifiedClick("CHATLINK") then
            if not ChatFrameUtil.InsertLink(character.mythicplus.keystone.itemLink) then
              ChatFrameUtil.OpenChat(character.mythicplus.keystone.itemLink)
            end
          end
        end
      end,
      enabled = Data.db.global.showCurrentKeystone,
    },
    {
      label = DELVES_GREAT_VAULT_LABEL,
      value = function(character)
        if character.vault.hasAvailableRewards == true then
          if characterHasVaultPreviewData(character) then
            return RARE_BLUE_COLOR:WrapTextInColorCode("Rewards Pending")
          end
          return GREEN_FONT_COLOR:WrapTextInColorCode(QUEST_REWARDS)
        end
        return ""
      end,
      onEnter = function(infoFrame, character)
        if character.vault.hasAvailableRewards == true then
          GameTooltip:SetOwner(infoFrame, "ANCHOR_RIGHT")
          GameTooltip:AddLine("It's payday!", WHITE_FONT_COLOR.r, WHITE_FONT_COLOR.g, WHITE_FONT_COLOR.b)
          GameTooltip:AddLine(GREAT_VAULT_REWARDS_WAITING, GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b, true)
          if vaultPreviewModule then
            GameTooltip:AddLine(" ")
            if characterHasVaultPreviewData(character) then
              GameTooltip:AddLine("<Click to Preview Rewards>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            else
              GameTooltip:AddLine("Open the Great Vault to check rewards", ORANGE_FONT_COLOR.r, ORANGE_FONT_COLOR.g, ORANGE_FONT_COLOR.b, true)
            end
          end
          GameTooltip:Show()
        end
      end,
      onLeave = function()
        GameTooltip:Hide()
      end,
      onClick = function(infoFrame, character)
        if not vaultPreviewModule then return end
        if character.vault.hasAvailableRewards ~= true then return end
        if not characterHasVaultPreviewData(character) then
          GameTooltip:SetOwner(infoFrame, "ANCHOR_RIGHT")
          GameTooltip:AddLine("Open the Great Vault to check rewards", ORANGE_FONT_COLOR.r, ORANGE_FONT_COLOR.g, ORANGE_FONT_COLOR.b, true)
          GameTooltip:Show()
          return
        end
        -- The pending state is specifically a confirmed reward-history view,
        -- so never fall back to live example links here.
        vaultPreviewModule:OpenCharacter(character, true)
      end,
      backgroundColor = {r = 0, g = 0, b = 0, a = 0.3},
      enabled = Data.db.global.vault.raids or Data.db.global.vault.dungeons or Data.db.global.vault.world,
    },
    {
      label = WHITE_FONT_COLOR:WrapTextInColorCode(RAIDS),
      value = function(character) return getVaultProgressValue(character, Enum.WeeklyRewardChestThresholdType.Raid) end,
      onEnter = function(infoFrame, character) getVaultProgressTooltip(infoFrame, character, Enum.WeeklyRewardChestThresholdType.Raid) end,
      onLeave = function() GameTooltip:Hide() end,
      enabled = Data.db.global.vault.raids,
    },
    {
      label = WHITE_FONT_COLOR:WrapTextInColorCode(DUNGEONS),
      value = function(character) return getVaultProgressValue(character, Enum.WeeklyRewardChestThresholdType.Activities) end,
      onEnter = function(infoFrame, character) getVaultProgressTooltip(infoFrame, character, Enum.WeeklyRewardChestThresholdType.Activities) end,
      onLeave = function() GameTooltip:Hide() end,
      enabled = Data.db.global.vault.dungeons,
    },
    {
      label = WHITE_FONT_COLOR:WrapTextInColorCode(WORLD),
      value = function(character) return getVaultProgressValue(character, Enum.WeeklyRewardChestThresholdType.World) end,
      onEnter = function(infoFrame, character) getVaultProgressTooltip(infoFrame, character, Enum.WeeklyRewardChestThresholdType.World) end,
      onLeave = function() GameTooltip:Hide() end,
      enabled = Data.db.global.vault.world,
    },
  }

  if unfiltered then
    return rows
  end

  return TableFilter(rows, function(info)
    return info.enabled
  end)
end

---Populate a currency/seasonal-chore cell text and tooltip based on its currencyType.
---@param currencyFrame table
---@param currency AE_CurrencyInfo
---@param characterCurrency AE_CharacterCurrency?
---@param settings table
---Show a full-width row highlight spanning the sidebar and every character column, at the given
---vertical offset. Used so hovering any cell in a Currencies/Weeklies/Seasonal Chores row makes it
---obvious which row that is across the whole grid.
---@param rowTop number
---@param rowHeight number
function Module:ShowRowHighlight(rowTop, rowHeight)
  if not self.window then return end

  local sidebar = self.window.body.sidebar
  if sidebar then
    local highlight = sidebar.rowHighlight
    if not highlight then
      highlight = sidebar:CreateTexture(nil, "OVERLAY")
      highlight:SetColorTexture(1, 1, 1, 0.06)
      sidebar.rowHighlight = highlight
    end
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -rowTop)
    highlight:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, -rowTop)
    highlight:SetHeight(rowHeight)
    highlight:Show()
  end

  local scrollContent = self.window.body.content and self.window.body.content.scrollArea and self.window.body.content.scrollArea.content
  if scrollContent then
    local highlight = scrollContent.rowHighlight
    if not highlight then
      highlight = scrollContent:CreateTexture(nil, "OVERLAY")
      highlight:SetColorTexture(1, 1, 1, 0.06)
      scrollContent.rowHighlight = highlight
    end
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -rowTop)
    highlight:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, -rowTop)
    highlight:SetHeight(rowHeight)
    highlight:Show()
  end
end

---Hide the full-width row highlight shown by Module:ShowRowHighlight.
function Module:HideRowHighlight()
  if not self.window then return end
  local sidebar = self.window.body.sidebar
  if sidebar and sidebar.rowHighlight then
    sidebar.rowHighlight:Hide()
  end
  local scrollContent = self.window.body.content and self.window.body.content.scrollArea and self.window.body.content.scrollArea.content
  if scrollContent and scrollContent.rowHighlight then
    scrollContent.rowHighlight:Hide()
  end
end

---Register (or refresh) a frame for the full-row highlight system. Safe to call every render:
---entries are rebuilt from scratch each time via ResetRowHighlightFrames, so this just appends.
---A single throttled OnUpdate poller (installed once, see EnsureRowHighlightPoller) checks
---IsMouseOver() on these each frame instead of relying on OnEnter/OnLeave, since those events
---don't reliably refire when Module:Render() hides/repositions/reshows frames under an already
---stationary cursor (which happens on every periodic data refresh), causing the highlight to
---silently stop working after the first hover.
---@param frame table
---@param rowTop number
---@param rowHeight number
local function RegisterRowHighlightFrame(frame, rowTop, rowHeight)
  Module.rowHighlightFrames = Module.rowHighlightFrames or {}
  table.insert(Module.rowHighlightFrames, { frame = frame, rowTop = rowTop, rowHeight = rowHeight })
end

---Clear the list of frames tracked for the row-highlight poller. Called at the start of each
---Render() so stale entries (e.g. for a currency that got hidden) don't linger.
local function ResetRowHighlightFrames()
  Module.rowHighlightFrames = {}
end

---Install the row-highlight poller once. Throttled to a few times a second; cheap since it's
---just IsMouseOver() checks against a short list.
local function EnsureRowHighlightPoller(window)
  if window.rowHighlightPollerInstalled then return end
  window.rowHighlightPollerInstalled = true

  local function IsDescendantOf(frame, ancestor)
    local current = frame
    while current do
      if current == ancestor then
        return true
      end
      current = current.GetParent and current:GetParent() or nil
    end
    return false
  end

  local elapsed = 0
  window:HookScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.05 then return end
    elapsed = 0

    local hovered = nil
    local scrollArea = window.body and window.body.content and window.body.content.scrollArea
    local scrollContent = scrollArea and scrollArea.content
    local viewport = scrollArea and scrollArea.container
    local cursorInsideCharacterViewport = viewport and viewport:IsShown() and viewport:IsMouseOver()

    for _, entry in ipairs(Module.rowHighlightFrames or {}) do
      if entry.frame:IsShown() and entry.frame:IsMouseOver() then
        -- IsMouseOver() can still report true for a child that has been scrolled
        -- beyond a WowScrollBox viewport. Only accept character-grid cells while
        -- the cursor is physically inside the visible viewport; sidebar rows are
        -- unaffected. This prevents hidden columns from producing "ghost" row
        -- highlights to the left/right of a Visible Characters-limited window.
        local inCharacterGrid = scrollContent and IsDescendantOf(entry.frame, scrollContent)
        if not inCharacterGrid or cursorInsideCharacterViewport then
          hovered = entry
          break
        end
      end
    end

    if hovered then
      Module:ShowRowHighlight(hovered.rowTop, hovered.rowHeight)
    else
      Module:HideRowHighlight()
    end
  end)
end

---Keep the Main-window titlebar controls inside the window at every width. LiqUI normally lays
---every titlebar button out in one row from right to left; for this window only, keep the primary
---window controls in the upper rows and move Weekly Affixes / Daily Delves into dedicated lower
---rows whenever everything cannot fit safely on one line. Both groups wrap independently so no
---header control can overlap another at any supported window width.
---@param window LiqUI_WindowInstance
---@param requestedBodyWidth number
---@param bodyHeight number
---@return number bodyWidth
local function LayoutMainTitlebarButtons(window, requestedBodyWidth, bodyHeight)
  local rowHeight = Constants.sizes.titlebar.height
  local customButtons = window.titlebarButtons or {}
  local fixedButtons = {}
  if window.titlebar and window.titlebar.CloseButton then
    table.insert(fixedButtons, window.titlebar.CloseButton)
  end
  if window.titlebar and window.titlebar.SettingsButton then
    table.insert(fixedButtons, window.titlebar.SettingsButton)
  end

  local function ButtonWidth(button)
    local width = button and button:GetWidth() or 0
    if not width or width <= 0 then
      return rowHeight
    end
    return width
  end

  local fixedWidth = 0
  for _, button in ipairs(fixedButtons) do
    fixedWidth = fixedWidth + ButtonWidth(button)
  end

  local customWidths = {}
  local customOverflowWidths = {}
  local widestPrimaryButton = 0
  for index, button in ipairs(customButtons) do
    -- Read the configured width rather than the frame's current width: overflow rows
    -- intentionally compact the click target a few pixels, and that must not become the
    -- new baseline on the next Render(). A 26px overflow slot still leaves comfortable
    -- padding around the largest 18px icon and lets five primary icons fit in a 130px row.
    local config = window.options and window.options.titlebarButtons and window.options.titlebarButtons[index]
    local width = (config and config.size) or rowHeight
    customWidths[index] = width
    customOverflowWidths[index] = math.min(width, math.max(24, rowHeight - 4))
    widestPrimaryButton = math.max(widestPrimaryButton, width)
  end

  -- Branding stays on the real titlebar. Use its actual on-screen extent when available so
  -- primary buttons can never collide with the AlterEgo logo/title toggle.
  local function GetBrandReserve()
    local windowLeft = window:GetLeft()
    if windowLeft and window.sidebarToggleButton and window.sidebarToggleButton:IsVisible() then
      local right = window.sidebarToggleButton:GetRight()
      if right then
        return math.max(0, right - windowLeft)
      end
    end
    return window.sidebarToggleButton and math.max(0, window.sidebarToggleButton:GetWidth() or 0) or 0
  end

  -- Secondary controls are intentionally treated as a separate group. When the header needs
  -- more than one row they are always placed below every primary-control row.
  local secondaryButtons = {}
  if window.affixes and window.affixes:IsVisible() and window.affixes.buttons then
    for _, button in ipairs(window.affixes.buttons) do
      if button and button:IsVisible() then
        table.insert(secondaryButtons, button)
      end
    end
  end
  if window.dailyDelvesButton and window.dailyDelvesButton:IsVisible() then
    table.insert(secondaryButtons, window.dailyDelvesButton)
  end

  local secondaryGap = 6
  local dailyGapWithSeparator = 24
  local function GapBeforeSecondary(hasPrevious, button)
    if not hasPrevious then return 0 end
    if button == window.dailyDelvesButton then
      return dailyGapWithSeparator
    end
    return secondaryGap
  end

  local function SecondaryRowWidth(row)
    local width = 0
    for index, button in ipairs(row) do
      width = width + GapBeforeSecondary(index > 1, button) + ButtonWidth(button)
    end
    return width
  end

  local widestSecondaryButton = 0
  for _, button in ipairs(secondaryButtons) do
    widestSecondaryButton = math.max(widestSecondaryButton, ButtonWidth(button))
  end

  local brandReserve = GetBrandReserve()
  local bodyWidth = math.max(
    requestedBodyWidth,
    brandReserve + fixedWidth,
    widestPrimaryButton,
    widestSecondaryButton
  )

  local function AssignPrimaryRows(firstRowCapacity)
    local rows = { {} }
    local rowIndex = 1
    local usedWidth = 0
    for index in ipairs(customWidths) do
      local width = rowIndex == 1 and customWidths[index] or customOverflowWidths[index]
      local capacity = rowIndex == 1 and firstRowCapacity or bodyWidth
      if rowIndex == 1 and #rows[rowIndex] == 0 and width > capacity then
        rowIndex = 2
        rows[rowIndex] = {}
        usedWidth = 0
        width = customOverflowWidths[index]
        capacity = bodyWidth
      elseif usedWidth > 0 and usedWidth + width > capacity then
        rowIndex = rowIndex + 1
        rows[rowIndex] = {}
        usedWidth = 0
        width = customOverflowWidths[index]
        capacity = bodyWidth
      end
      table.insert(rows[rowIndex], index)
      usedWidth = usedWidth + width
    end
    return rows
  end

  -- Weekly Affixes / Daily Delves share the real titlebar only when the entire header can
  -- fit safely on one row: branding on the left, the secondary group centered, and every
  -- primary/fixed control on the right. If any of those regions would collide, keep the
  -- secondary group in dedicated centered lower row(s).
  local primaryRows
  local secondaryRows = {}
  local firstRowCapacity = math.max(0, bodyWidth - brandReserve - fixedWidth)
  primaryRows = AssignPrimaryRows(firstRowCapacity)

  local primaryClusterWidth = fixedWidth
  for _, width in ipairs(customWidths) do
    primaryClusterWidth = primaryClusterWidth + width
  end

  local secondaryWidth = SecondaryRowWidth(secondaryButtons)
  local secondaryClearance = 6
  local centeredSecondaryLeft = (bodyWidth - secondaryWidth) / 2
  local centeredSecondaryRight = centeredSecondaryLeft + secondaryWidth
  local rightPrimaryLeft = bodyWidth - primaryClusterWidth
  local allPrimaryControlsFitFirstRow = #primaryRows == 1
  local secondaryFitsCenteredOnTitlebar = #secondaryButtons == 0 or (
    allPrimaryControlsFitFirstRow
    and centeredSecondaryLeft >= (brandReserve + secondaryClearance)
    and centeredSecondaryRight <= (rightPrimaryLeft - secondaryClearance)
  )
  local useDedicatedSecondaryRows = #secondaryButtons > 0 and not secondaryFitsCenteredOnTitlebar

  if useDedicatedSecondaryRows then
    local row = {}
    local usedWidth = 0
    for _, button in ipairs(secondaryButtons) do
      local gap = GapBeforeSecondary(#row > 0, button)
      local width = ButtonWidth(button)
      if #row > 0 and usedWidth + gap + width > bodyWidth then
        table.insert(secondaryRows, row)
        row = {}
        usedWidth = 0
        gap = 0
      end
      table.insert(row, button)
      usedWidth = usedWidth + gap + width
    end
    if #row > 0 then
      table.insert(secondaryRows, row)
    end
  end

  local primaryOverflowCount = math.max(0, #primaryRows - 1)
  local totalOverflowCount = primaryOverflowCount + #secondaryRows
  window.titlebarOverflowRows = window.titlebarOverflowRows or {}

  local function EnsureOverflowRow(rowIndex)
    local overflow = window.titlebarOverflowRows[rowIndex]
    if overflow then return overflow end

    overflow = CreateFrame("Frame", "$parentTitlebarOverflow" .. rowIndex, window)
    overflow:SetHeight(rowHeight)
    overflow:SetFrameLevel(window.titlebar:GetFrameLevel() + 1)
    overflow:EnableMouse(true)
    overflow:RegisterForDrag("LeftButton")
    overflow:SetScript("OnDragStart", function() window:StartMoving() end)
    overflow:SetScript("OnDragStop", function()
      window:StopMovingOrSizing()
      window:SaveSettings()
    end)
    SetBackgroundColor(overflow, 0, 0, 0, 0.5)
    window.titlebarOverflowRows[rowIndex] = overflow
    return overflow
  end

  for rowIndex = 1, totalOverflowCount do
    local overflow = EnsureOverflowRow(rowIndex)
    overflow:ClearAllPoints()
    overflow:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -(rowHeight * rowIndex))
    overflow:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -(rowHeight * rowIndex))
    overflow:Show()
  end
  for rowIndex = totalOverflowCount + 1, #window.titlebarOverflowRows do
    window.titlebarOverflowRows[rowIndex]:Hide()
  end

  -- Primary controls always occupy the top rows: Close, Settings, then custom controls.
  local anchorFrame = nil
  if window.titlebar.CloseButton then
    window.titlebar.CloseButton:SetParent(window.titlebar)
    window.titlebar.CloseButton:ClearAllPoints()
    window.titlebar.CloseButton:SetPoint("RIGHT", window.titlebar, "RIGHT", 0, 0)
    anchorFrame = window.titlebar.CloseButton
  end
  if window.titlebar.SettingsButton then
    window.titlebar.SettingsButton:SetParent(window.titlebar)
    window.titlebar.SettingsButton:ClearAllPoints()
    window.titlebar.SettingsButton:SetPoint("RIGHT", anchorFrame or window.titlebar, anchorFrame and "LEFT" or "RIGHT", 0, 0)
    anchorFrame = window.titlebar.SettingsButton
  end

  for _, buttonIndex in ipairs(primaryRows[1]) do
    local button = customButtons[buttonIndex]
    button:SetParent(window.titlebar)
    button:SetWidth(customWidths[buttonIndex])
    button:ClearAllPoints()
    button:SetPoint("RIGHT", anchorFrame or window.titlebar, anchorFrame and "LEFT" or "RIGHT", 0, 0)
    anchorFrame = button
  end

  for rowIndex = 2, #primaryRows do
    local overflow = window.titlebarOverflowRows[rowIndex - 1]
    local overflowAnchor = nil
    for _, buttonIndex in ipairs(primaryRows[rowIndex]) do
      local button = customButtons[buttonIndex]
      button:SetParent(overflow)
      button:SetWidth(customOverflowWidths[buttonIndex])
      button:ClearAllPoints()
      if overflowAnchor then
        button:SetPoint("RIGHT", overflowAnchor, "LEFT", 0, 0)
      else
        button:SetPoint("RIGHT", overflow, "RIGHT", 0, 0)
      end
      overflowAnchor = button
    end
  end

  -- Re-anchor secondary controls after the primary layout is known. The separator only appears
  -- when Daily Delves shares a row with an affix, so it can never be stranded at the start of a
  -- wrapped row.
  if window.dailyDelvesSeparator then
    window.dailyDelvesSeparator:Hide()
  end

  local function PlaceSecondaryRow(row, host, centered)
    if #row == 0 then return end
    local rowWidth = SecondaryRowWidth(row)
    local previous = nil
    for _, button in ipairs(row) do
      button:SetParent(host)
      button:ClearAllPoints()
      if not previous then
        if centered then
          button:SetPoint("LEFT", host, "CENTER", -(rowWidth / 2), 0)
        else
          button:SetPoint("LEFT", window.sidebarToggleButton or host, "RIGHT", secondaryGap, 0)
        end
      else
        local gap = GapBeforeSecondary(true, button)
        button:SetPoint("LEFT", previous, "RIGHT", gap, 0)
        if button == window.dailyDelvesButton and window.dailyDelvesSeparator then
          window.dailyDelvesSeparator:SetParent(host)
          window.dailyDelvesSeparator:ClearAllPoints()
          window.dailyDelvesSeparator:SetPoint("CENTER", previous, "RIGHT", gap / 2, 0)
          window.dailyDelvesSeparator:Show()
        end
      end
      if button.SetFrameLevel and host.GetFrameLevel then
        button:SetFrameLevel(host:GetFrameLevel() + 1)
      end
      previous = button
    end
  end

  if useDedicatedSecondaryRows then
    for index, row in ipairs(secondaryRows) do
      local host = window.titlebarOverflowRows[primaryOverflowCount + index]
      PlaceSecondaryRow(row, host, true)
    end
  else
    PlaceSecondaryRow(secondaryButtons, window.titlebar, true)
  end

  local topOffset = rowHeight * (1 + totalOverflowCount)
  local function AnchorContent(frame)
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -topOffset)
    frame:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -topOffset)
    frame:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)
  end
  AnchorContent(window.body)
  AnchorContent(window.overlay)
  window:SetSize(bodyWidth, bodyHeight + topOffset)

  return bodyWidth
end

---Update the large character-grid edge arrows so they only appear on sides that
---still contain off-screen character columns.
---@param window table
local function UpdateCharacterScrollEdgeButtons(window)
  local navigation = window and window.characterScrollNavigation
  local scrollArea = window and window.body and window.body.content and window.body.content.scrollArea
  local scrollBox = scrollArea and scrollArea.horizontalScrollBox
  local settings = Data.db.global.liqui.windows.Main
  if not navigation or settings.showCharacterScrollArrows == false or not scrollBox or not scrollBox:IsShown() then
    if navigation then
      navigation.left:Hide()
      navigation.right:Hide()
    end
    return
  end

  local arrowScale = math.max(50, math.min(200, tonumber(settings.characterScrollArrowScale) or 100)) / 100
  local iconSize = math.floor((80 * arrowScale) + 0.5)
  local hitWidth = math.max(48, iconSize)
  local hitHeight = math.max(60, iconSize + 20)
  -- Keep the texture itself inside the window. The native atlas has transparent
  -- padding, so a very small outward nudge keeps the visible arrow close to the
  -- edge without letting the artwork cross the window boundary.
  local visualEdgeOffset = math.max(2, math.floor((4 * arrowScale) + 0.5))
  for _, button in pairs({navigation.left, navigation.right}) do
    button:SetSize(hitWidth, hitHeight)
    button.Icon:SetSize(iconSize, iconSize)
    button.Icon:ClearAllPoints()
    if button.isLeftEdge then
      button.Icon:SetPoint("LEFT", window.body, "LEFT", -visualEdgeOffset, 0)
    else
      button.Icon:SetPoint("RIGHT", window.body, "RIGHT", visualEdgeOffset, 0)
    end
  end

  local range = scrollBox.GetDerivedScrollRange and scrollBox:GetDerivedScrollRange() or 0
  local scrollable = range and range > 1 and (not scrollBox.HasScrollableExtent or scrollBox:HasScrollableExtent())
  if not scrollable then
    navigation.left:Hide()
    navigation.right:Hide()
    return
  end

  local percentage = scrollBox.GetScrollPercentage and scrollBox:GetScrollPercentage() or 0
  navigation.left:SetShown(percentage > 0.001)
  navigation.right:SetShown(percentage < 0.999)
end

---Create persistent, clickable edge arrows for the horizontally-scrollable character grid.
---They are intentionally separate from Blizzard's hidden scrollbar: mouse-wheel scrolling
---remains available everywhere. Left click advances by one character column; right click
---jumps directly to the first/last character on that side.
---@param window table
local function EnsureCharacterScrollEdgeButtons(window)
  if window.characterScrollNavigation then return end
  local host = window.body and window.body.content
  local scrollArea = host and host.scrollArea
  if not host or not scrollArea then return end

  local navigation = {}
  local function CreateEdgeButton(side)
    local isLeft = side == "left"
    local button = CreateFrame("Button", nil, window)
    local anchorHost = window.body or host
    button.isLeftEdge = isLeft
    button:SetSize(88, 100)
    -- Keep a generous invisible hitbox inside the window, but anchor the artwork
    -- independently so the atlas' built-in transparent padding does not make the
    -- arrow look inset from the actual window edge.
    button:SetPoint(isLeft and "LEFT" or "RIGHT", anchorHost, isLeft and "LEFT" or "RIGHT", 0, 0)
    button:SetFrameLevel(host:GetFrameLevel() + 50)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Reuse the same Blizzard arrow atlases AlterEgo already uses for moving
    -- characters and row labels so overflow navigation matches the addon UI.
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAtlas(isLeft and "common-icon-backarrow" or "common-icon-forwardarrow", true)
    button.Icon:SetDesaturation(1)
    button.Icon:SetSize(80, 80)
    if isLeft then
      button.Icon:SetPoint("LEFT", anchorHost, "LEFT", -4, 0)
    else
      button.Icon:SetPoint("RIGHT", anchorHost, "RIGHT", 4, 0)
    end

    button:SetScript("OnEnter", function(self)
      self.Icon:SetDesaturation(0)
      GameTooltip:SetOwner(self, isLeft and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
      GameTooltip:SetText(isLeft and "More characters to the left" or "More characters to the right", 1, 1, 1)
      GameTooltip:AddLine(isLeft and "Left Click: show the previous character." or "Left Click: show the next character.", nil, nil, nil, true)
      GameTooltip:AddLine(isLeft and "Right Click: jump to the first character." or "Right Click: jump to the last character.", nil, nil, nil, true)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
      self.Icon:SetDesaturation(1)
      GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
      local scrollBox = scrollArea.horizontalScrollBox
      if not scrollBox then return end

      if mouseButton == "RightButton" then
        if isLeft then
          scrollBox:ScrollToBegin()
        else
          scrollBox:ScrollToEnd()
        end
      else
        local range = scrollBox.GetDerivedScrollRange and scrollBox:GetDerivedScrollRange() or 0
        if range and range > 0 then
          local percentage = scrollBox.GetScrollPercentage and scrollBox:GetScrollPercentage() or 0
          local currentOffset = percentage * range
          local direction = isLeft and -1 or 1
          local columnWidth = tonumber(window.characterScrollColumnWidth) or CHARACTER_WIDTH
          local targetOffset = math.max(0, math.min(range, currentOffset + (direction * columnWidth)))
          local targetPercentage = targetOffset / range
          scrollBox:SetScrollPercentage(targetPercentage, ScrollBoxConstants.NoScrollInterpolation)
        end
      end

      UpdateCharacterScrollEdgeButtons(window)
    end)
    button:Hide()
    return button
  end

  navigation.left = CreateEdgeButton("left")
  navigation.right = CreateEdgeButton("right")
  navigation.driver = CreateFrame("Frame", nil, host)
  navigation.driver.elapsed = 0
  navigation.driver:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.08 then return end
    self.elapsed = 0
    UpdateCharacterScrollEdgeButtons(window)
  end)
  window.characterScrollNavigation = navigation
end

local function PopulateCurrencyCell(currencyFrame, currency, characterCurrency, settings)
  local cellColor = CAMPAIGN_COMPLETE_COLOR
  local cellValue = "0"
  local iconFileID = currency.iconFileID
  if not iconFileID or iconFileID == 0 then
    iconFileID = [[Interface\Icons\INV_Misc_QuestionMark]]
  end
  local infoIcon = CreateSimpleTextureMarkup(iconFileID)
  local mainWindowSettings = Data.db.global.liqui.windows.Main
  local showIcons = settings.showIcons == true
    or (mainWindowSettings.sidebarCollapsed == true and mainWindowSettings.collapsingRowLabelsDisplaysAllIcons ~= false)

  if currency.currencyType == "delveMap" then
    local statusValue = "-"
    local cellText = GRAY_FONT_COLOR:WrapTextInColorCode("-")
    if characterCurrency then
      if characterCurrency.hasBuff then
        statusValue = "Active"
        cellText = CreateAtlasMarkup("QuestTurnin", 16, 16)
      elseif (characterCurrency.bagCount or 0) > 0 then
        statusValue = "In bags"
        cellText = CreateAtlasMarkup("QuestTurnin", 16, 16)
      elseif characterCurrency.questCompleted then
        statusValue = "Completed"
        cellText = CreateAtlasMarkup("common-icon-checkmark", 16, 16)
      else
        statusValue = "Available"
        cellText = CreateAtlasMarkup("Recurringavailablequesticon", 16, 16)
      end
    end

    if showIcons then
      cellText = format("%s %s", infoIcon, cellText)
    end

    currencyFrame.Text:SetText(cellText)
    currencyFrame.Text:SetJustifyH(settings.alignCenter and "CENTER" or "LEFT")
    currencyFrame:SetScript("OnEnter", function()
      GameTooltip:SetOwner(currencyFrame, "ANCHOR_RIGHT")
      GameTooltip:SetText(currency.name, 1, 1, 1)
      if not characterCurrency then
        GameTooltip:AddDoubleLine("Status:", "No Data", nil, nil, nil, 1, 1, 1)
        GameTooltip:AddLine("Log your character to update.", 1, 1, 1, true)
      else
        GameTooltip:AddDoubleLine("Status:", statusValue, nil, nil, nil, 1, 1, 1)
        GameTooltip:AddDoubleLine("In bags:", tostring(characterCurrency.bagCount or 0), nil, nil, nil, 1, 1, 1)
        GameTooltip:AddDoubleLine("Buff active:", characterCurrency.hasBuff and "Yes" or "No", nil, nil, nil, 1, 1, 1)
      end
      if currency.tooltipNote then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("%s %s", RARE_BLUE_COLOR:WrapTextInColorCode(addon.name .. ":"), currency.tooltipNote), 1, 1, 1, true)
      end
      GameTooltip:Show()
      SetHighlightColor(currencyFrame, 1, 1, 1, 0.05)
    end)
  elseif currency.currencyType == "quest" then
    local isAccountQuest = currency.resets == "account"
    local completed = characterCurrency ~= nil and characterCurrency.questCompleted == true
    if isAccountQuest and not completed then
      -- Once per account: completed on any character counts for all of them
      completed = Data:IsQuestCompletedOnAccount(currency.id)
    end

    local availableAtlas = "Recurringavailablequesticon"
    if isAccountQuest and C_Texture.GetAtlasInfo("QuestNormal") then
      availableAtlas = "QuestNormal"
    end

    local pendingTurnin = not completed and characterCurrency ~= nil and (characterCurrency.bagCount or 0) > 0

    local statusValue = "-"
    local cellText = GRAY_FONT_COLOR:WrapTextInColorCode("-")
    if completed then
      statusValue = "Completed"
      cellText = CreateAtlasMarkup("common-icon-checkmark", 16, 16)
    elseif pendingTurnin then
      statusValue = "In bags"
      cellText = CreateSimpleTextureMarkup([[Interface\RaidFrame\ReadyCheck-Waiting]], 16, 16)
    elseif characterCurrency then
      statusValue = "Available"
      cellText = CreateAtlasMarkup(availableAtlas, 16, 16)
    end

    if showIcons then
      cellText = format("%s %s", infoIcon, cellText)
    end

    currencyFrame.Text:SetText(cellText)
    currencyFrame.Text:SetJustifyH(settings.alignCenter and "CENTER" or "LEFT")
    currencyFrame:SetScript("OnEnter", function()
      GameTooltip:SetOwner(currencyFrame, "ANCHOR_RIGHT")
      GameTooltip:SetText(currency.name, 1, 1, 1)
      if not characterCurrency and not completed then
        GameTooltip:AddDoubleLine("Status:", "No Data", nil, nil, nil, 1, 1, 1)
        GameTooltip:AddLine("Log your character to update.", 1, 1, 1, true)
      else
        GameTooltip:AddDoubleLine("Status:", statusValue, nil, nil, nil, 1, 1, 1)
        if pendingTurnin then
          GameTooltip:AddDoubleLine("In bags:", tostring(characterCurrency.bagCount), nil, nil, nil, 1, 1, 1)
        end
        if currency.resets ~= "character" then
          GameTooltip:AddDoubleLine("Resets:", isAccountQuest and "Never (once per account)" or "Weekly", nil, nil, nil, 1, 1, 1)
        end
      end
      if currency.tooltipNote then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("%s %s", RARE_BLUE_COLOR:WrapTextInColorCode(addon.name .. ":"), currency.tooltipNote), 1, 1, 1, true)
      end
      GameTooltip:Show()
      SetHighlightColor(currencyFrame, 1, 1, 1, 0.05)
    end)
  elseif currency.currencyType == "gildedStash" then
    local fulfilled = characterCurrency and characterCurrency.fulfilled
    local total = characterCurrency and characterCurrency.total or 4
    local cellText = GRAY_FONT_COLOR:WrapTextInColorCode("-")
    if fulfilled ~= nil then
      cellText = format("%d/%d", fulfilled, total)
      if fulfilled >= total then
        cellText = GREEN_FONT_COLOR:WrapTextInColorCode(cellText)
      end
    end

    if showIcons then
      cellText = format("%s %s", infoIcon, cellText)
    end

    currencyFrame.Text:SetText(cellText)
    currencyFrame.Text:SetJustifyH(settings.alignCenter and "CENTER" or "LEFT")
    currencyFrame:SetScript("OnEnter", function()
      GameTooltip:SetOwner(currencyFrame, "ANCHOR_RIGHT")
      GameTooltip:SetText(currency.name, 1, 1, 1)
      if fulfilled == nil then
        GameTooltip:AddDoubleLine("Status:", "No Data", nil, nil, nil, 1, 1, 1)
        GameTooltip:AddLine("Visit Silvermoon City to update the progress.", 1, 1, 1, true)
      else
        GameTooltip:AddDoubleLine("Progress:", format("%d/%d", fulfilled, total), nil, nil, nil, 1, 1, 1)
      end
      if currency.tooltipNote then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("%s %s", RARE_BLUE_COLOR:WrapTextInColorCode(addon.name .. ":"), currency.tooltipNote), 1, 1, 1, true)
      end
      GameTooltip:Show()
      SetHighlightColor(currencyFrame, 1, 1, 1, 0.05)
    end)
  else
    local infoMaxQuantity = currency.maxQuantity or 0
    local infoMaxWeeklyQuantity = currency.maxWeeklyQuantity or 0
    local charQuantity = 0
    local charTotalEarned = 0
    local charEarnedThisWeek = 0
    local hasEarnedMax = false

    if characterCurrency then
      charQuantity = characterCurrency.quantity or 0
      charTotalEarned = characterCurrency.totalEarned or 0
      charEarnedThisWeek = characterCurrency.quantityEarnedThisWeek or 0
    end

    if infoMaxQuantity > 0 then
      hasEarnedMax = charQuantity >= infoMaxQuantity
      if currency.useTotalEarnedForMaxQty then
        hasEarnedMax = charTotalEarned >= infoMaxQuantity
      end
    end
    if infoMaxWeeklyQuantity > 0 and charEarnedThisWeek >= infoMaxWeeklyQuantity then
      hasEarnedMax = true
    end

    cellValue = tostring(charQuantity)
    if showIcons then
      cellValue = format("%s %s", infoIcon, cellValue)
    end

    if settings.showMaxEarned and hasEarnedMax then
      cellColor = DULL_RED_FONT_COLOR
    elseif charQuantity == 0 then
      cellColor = GRAY_FONT_COLOR
      if currency.currencyType == "crest" and charTotalEarned == 0 then
        cellValue = "-"
      end
    end

    currencyFrame.Text:SetText(cellColor:WrapTextInColorCode(cellValue))
    currencyFrame.Text:SetJustifyH(settings.alignCenter and "CENTER" or "LEFT")
    currencyFrame:SetScript("OnEnter", function()
      GameTooltip:SetOwner(currencyFrame, "ANCHOR_RIGHT")
      GameTooltip:SetText("Currency Progress", 1, 1, 1)
      if infoMaxWeeklyQuantity > 0 then
        GameTooltip:AddDoubleLine("Weekly Maximum:", format("%d/%d", charEarnedThisWeek, infoMaxWeeklyQuantity), nil, nil, nil, 1, 1, 1)
      end
      if currency.useTotalEarnedForMaxQty then
        if infoMaxQuantity > 0 then
          GameTooltip:AddDoubleLine("Season Maximum:", format("%d/%d", charTotalEarned, infoMaxQuantity), nil, nil, nil, 1, 1, 1)
          if currency.currencyType == "crest" then
            GameTooltip:AddDoubleLine("Remaining:", tostring(math.max(0, infoMaxQuantity - charTotalEarned)), nil, nil, nil, 1, 1, 1)
          end
        else
          if charTotalEarned > 0 then
            GameTooltip:AddDoubleLine("Season Earned:", tostring(charTotalEarned), nil, nil, nil, 1, 1, 1)
          end
          GameTooltip:AddDoubleLine("Season Maximum:", "No limit", nil, nil, nil, 1, 1, 1)
        end
      else
        if charTotalEarned > 0 then
          GameTooltip:AddDoubleLine("Total Earned:", tostring(charTotalEarned), nil, nil, nil, 1, 1, 1)
        end
        if infoMaxQuantity > 0 then
          GameTooltip:AddDoubleLine("Total Maximum:", tostring(infoMaxQuantity), nil, nil, nil, 1, 1, 1)
        end
      end
      if currency.tooltipNote then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("%s %s", RARE_BLUE_COLOR:WrapTextInColorCode(addon.name .. ":"), currency.tooltipNote), 1, 1, 1, true)
      end
      GameTooltip:Show()
      SetHighlightColor(currencyFrame, 1, 1, 1, 0.05)
    end)
  end

end

---Render the main window
-- The entire Settings menu tree below (Characters, Sorting, Sync, etc.)
-- runs its checkbox/button/radio callbacks synchronously as part of
-- Blizzard's own Menu click-and-close sequence (Menu.lua Pick ->
-- SendResponse -> ... -> CloseMenu). A real Lua error was reported from
-- exactly that chain: closing one of these menus after a click triggered a
-- ScrollBox recompute (for some other already-open piece of Blizzard UI)
-- that hit a "secret number" value, and failed specifically because
-- execution was "tainted by 'AlterEgo'" -- i.e. because OUR code was still
-- on the call stack when Blizzard's own post-click/close logic ran.
-- Deferring the actual heavy Render() work by one frame (C_Timer.After(0,
-- ...)) gets it off that stack entirely: by the time it runs, Blizzard's
-- menu has already fully closed and there's no addon taint left for it to
-- collide with. `pendingRender` collapses any burst of Render() calls
-- (several menu items, or several game events, firing in the same frame)
-- into a single deferred pass instead of one per call.
local pendingRender = false
function Module:Render()
  if pendingRender then return end
  pendingRender = true
  C_Timer.After(0, function()
    pendingRender = false
    Module:RenderNow()
  end)
end

function Module:RenderNow()
  ResetRowHighlightFrames()
  local currentAffixes = Data:GetCurrentAffixes()
  local seasonID = Data:GetCurrentSeason()
  local dungeons = Data:GetDungeons()
  local allCurrencies = Data:GetCurrencies()
  local currencies = TableFilter(allCurrencies, function(currency) return currency.category == nil end)
  local weeklies = TableFilter(allCurrencies, function(currency) return currency.category == "weekly" end)
  local seasonalChores = TableFilter(allCurrencies, function(currency) return currency.category == "seasonalChore" end)
  local trackerSections = Data:GetTrackerSections()
  local trackerMoveState = {}
  TableForEach(trackerSections, function(section, sectionIndex)
    TableForEach(section.items, function(tracker, itemIndex)
      trackerMoveState[tracker.id] = {
        canMoveUp = itemIndex > 1 or sectionIndex > 1,
        canMoveDown = itemIndex < #section.items or sectionIndex < #trackerSections,
      }
    end)
  end)
  local raidDifficulties = Data:GetRaidDifficulties()
  local characterInfo = self:GetCharacterInfo()
  local raids = Data:GetRaids()
  local characters = Data:GetCharacters()
  local numCharacters = TableCount(characters)
  local affixes = Data:GetAffixes(true)
  local mainWindowSettings = Data.db.global.liqui.windows.Main
  local windowScalePercent = self.window and self.window:GetWindowScale() or mainWindowSettings.scale or 100
  local windowScale = math.max(windowScalePercent / 100, 0.01)
  local windowWidthMax = LibLiqUI.Utils.GetMaxWindowWidth()
  if windowScale > 1 then
    -- Horizontal character scrolling is always available. Window dimensions are
    -- stored in unscaled UI units, so tighten the viewport whenever scaling would
    -- otherwise push the visible window past the screen edge.
    windowWidthMax = windowWidthMax / windowScale
  end
  local windowWidth, windowHeight = numCharacters == 0 and 500 or 0, 0
  local weeklyAffixesModule = addon.Core:GetModule("WeeklyAffixes", true)
  local dailyDelvesModule = addon.Core:GetModule("DailyDelves", true)

  if not self.window then
    local windows = Data.db.global.liqui.windows
    self.window = LibLiqUI:NewElement("Window", {
      name = addon.name .. "Main",
      storage = windows.Main,
      title = addon.name,
      icon = Constants.media.LogoTransparent,
      overlayFontObject = "GameFontHighlight_NoShadow",
      overlayTextColor = {r = 1, g = 0.82, b = 0, a = 1},
      onShow = function()
        Module:Render()
      end,
      onScaleChanged = function()
        Module:Render()
      end,
      onWindowOptionsAfterScaling = function(_, menu)
        local settings = Data.db.global.liqui.windows.Main

        menu:CreateCheckbox(
          "Show Overflow Arrows",
          function() return settings.showCharacterScrollArrows ~= false end,
          function()
            settings.showCharacterScrollArrows = not (settings.showCharacterScrollArrows ~= false)
            UpdateCharacterScrollEdgeButtons(self.window)
            return MenuResponse.Refresh
          end
        ):SetTooltip(function(tooltip)
          tooltip:AddLine("Show Overflow Arrows", 1, 1, 1, true)
          tooltip:AddLine("Show the large left/right indicators when additional characters exist outside the visible area. Horizontal scrolling remains available when this is disabled.", nil, nil, nil, true)
        end)

        local arrowScale = math.max(50, math.min(200, tonumber(settings.characterScrollArrowScale) or 100))
        local arrowScalingButton = menu:CreateButton(format("Arrow Scaling: %d%%", arrowScale))
        BindLiveMenuLabel(arrowScalingButton)
        for scalePercent = 50, 200, 10 do
          arrowScalingButton:CreateRadio(
            scalePercent .. "%",
            function(value) return (tonumber(Data.db.global.liqui.windows.Main.characterScrollArrowScale) or 100) == value end,
            function(value)
              Data.db.global.liqui.windows.Main.characterScrollArrowScale = value
              UpdateCharacterScrollEdgeButtons(self.window)
              SetLiveMenuLabel(arrowScalingButton, format("Arrow Scaling: %d%%", value))
              -- Keep Settings open; the radio state and parent label refresh immediately.
              return MenuResponse.Refresh
            end,
            scalePercent
          )
        end
        arrowScalingButton:SetTooltip(function(tooltip, elm)
          tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
          tooltip:AddLine("Adjust the size of the character overflow arrows. 100% uses the default 80x80 icon size.", nil, nil, nil, true)
        end)

        local visibleLimit = tonumber(settings.visibleCharacterLimit) or 15
        local visibleCharactersButton = menu:CreateButton(
          visibleLimit > 0 and format("Visible Characters: %d", visibleLimit) or "Visible Characters: Unlimited"
        )
        BindLiveMenuLabel(visibleCharactersButton)
        visibleCharactersButton:CreateRadio(
          "Unlimited",
          function() return (tonumber(Data.db.global.liqui.windows.Main.visibleCharacterLimit) or 15) <= 0 end,
          function()
            Data.db.global.liqui.windows.Main.visibleCharacterLimit = 0
            Module:Render()
            SetLiveMenuLabel(visibleCharactersButton, "Visible Characters: Unlimited")
            return MenuResponse.Refresh
          end
        )
        for count = 1, 20 do
          visibleCharactersButton:CreateRadio(
            tostring(count),
            function(value) return (tonumber(Data.db.global.liqui.windows.Main.visibleCharacterLimit) or 0) == value end,
            function(value)
              Data.db.global.liqui.windows.Main.visibleCharacterLimit = value
              Module:Render()
              SetLiveMenuLabel(visibleCharactersButton, format("Visible Characters: %d", value))
              return MenuResponse.Refresh
            end,
            count
          )
        end
        visibleCharactersButton:SetTooltip(function(tooltip, elm)
          tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
          tooltip:AddLine("Limit how many character columns are visible at once. Extra characters stay in the grid and remain available through horizontal scrolling and the edge arrows.", nil, nil, nil, true)
        end)
      end,
      onSettingsMenu = function(window, menu)
            -- The list has grown into a lot of sections (Character, Vault,
            -- Currencies/Weeklies/Seasonal Chores, Announcements, Interface,
            -- Multi-Account Sync...) -- without a scroll cap it just grows
            -- to fit everything and can run off the bottom of the screen.
            menu:SetScrollMode(math.min(600, GetScreenHeight() - 100))

            -- Keep the Settings menu at the same scroll position while the
            -- main AlterEgo window remains open. Blizzard menus are pooled,
            -- so keep this state on the module instead of on the menu frame
            -- itself, and restore it after the menu has finished laying out.
            menu:AddMenuAcquiredCallback(function(settingsMenu)
              -- Shared menu callbacks also fire for submenus. Keep the first live frame: it is
              -- the root Settings menu whose ScrollBox contains the Multi-Account Sync rows.
              if not syncTutorialSettingsMenu or not syncTutorialSettingsMenu:IsShown() then
                syncTutorialSettingsMenu = settingsMenu
              end
              local scrollPercentage = Module.settingsMenuScrollPercentage
              if scrollPercentage == nil then return end

              C_Timer.After(0, function()
                if not self.window or not self.window:IsShown() then return end
                if not settingsMenu:IsShown() or not settingsMenu.ScrollBox or not settingsMenu.ScrollBox:IsShown() then return end
                settingsMenu.ScrollBox:SetScrollPercentage(scrollPercentage, ScrollBoxConstants.NoScrollInterpolation)
              end)
            end)
            menu:AddMenuReleasedCallback(function(settingsMenu)
              if syncTutorialSettingsMenu == settingsMenu then
                syncTutorialSettingsMenu = nil
              end
              if self.window and self.window:IsShown() and settingsMenu.ScrollBox and settingsMenu.ScrollBox:IsShown() then
                Module.settingsMenuScrollPercentage = settingsMenu.ScrollBox:GetScrollPercentage()
              else
                Module.settingsMenuScrollPercentage = nil
              end
            end)

            menu:CreateTitle(CHARACTER)
            local currentCharacterMarkerSetting = menu:CreateButton("Current character")
            TableForEach(Constants.currentCharacterMarkers, function(marker)
              currentCharacterMarkerSetting:CreateRadio(
                marker.label,
                function(id) return Data.db.global.currentCharacterMarker == id end,
                function(id)
                  Data.db.global.currentCharacterMarker = id
                  self:Render()
                  return MenuResponse.Refresh
                end,
                marker.id
              )
            end)
            currentCharacterMarkerSetting:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Mark the character you are playing in the grid.", nil, nil, nil, true)
            end)
            do
              local markerColor = Data.db.global.currentCharacterMarkerColor or DIM_GREEN_FONT_COLOR
              local colorInfo = {
                r = markerColor.r,
                g = markerColor.g,
                b = markerColor.b,
                swatchFunc = function()
                  local r, g, b = ColorPickerFrame:GetColorRGB()
                  if r then
                    Data.db.global.currentCharacterMarkerColor = { r = r, g = g, b = b }
                    self:Render()
                  end
                end,
                cancelFunc = function(previousColor)
                  if previousColor and previousColor.r then
                    Data.db.global.currentCharacterMarkerColor = { r = previousColor.r, g = previousColor.g, b = previousColor.b }
                  else
                    Data.db.global.currentCharacterMarkerColor = nil
                  end
                  self:Render()
                end,
              }
              menu:CreateColorSwatch(
                "Current character color",
                function()
                  ColorPickerFrame:SetupColorPickerAndShow(colorInfo)
                end,
                colorInfo
              )
            end
            menu:CreateCheckbox(
              "Show Non Max Level Characters",
              function() return Data.db.global.showNonMaxLevelCharacters end,
              function()
                Data.db.global.showNonMaxLevelCharacters = not Data.db.global.showNonMaxLevelCharacters
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show captured characters below Retail's current expansion level cap.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show characters with zero rating",
              function() return Data.db.global.showZeroRatedCharacters end,
              function()
                Data.db.global.showZeroRatedCharacters = not Data.db.global.showZeroRatedCharacters
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Hide max-level characters with no Mythic+ rating. Leveling characters are controlled by Show Non Max Level Characters.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show character position",
              function() return Data.db.global.showCharacterPosition end,
              function()
                Data.db.global.showCharacterPosition = not Data.db.global.showCharacterPosition
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show each character's current position after their name (for example: Name - 1).", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show Item Level",
              function() return Data.db.global.showItemLevel end,
              function()
                Data.db.global.showItemLevel = not Data.db.global.showItemLevel
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show the Item Level column in the main window.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show Equipped Item Level",
              function() return Data.db.global.showEquippedItemLevel end,
              function()
                Data.db.global.showEquippedItemLevel = not Data.db.global.showEquippedItemLevel
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show only the item level of what's currently equipped, instead of what's possible including bags.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show Item Level Decimals",
              function() return Data.db.global.showItemLevelDecimals end,
              function()
                Data.db.global.showItemLevelDecimals = not Data.db.global.showItemLevelDecimals
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show item level with 2 decimal places.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show realm",
              function() return Data.db.global.showRealms end,
              function()
                Data.db.global.showRealms = not Data.db.global.showRealms
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("They're everywhere!", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show guild",
              function() return Data.db.global.showGuildInformation end,
              function()
                Data.db.global.showGuildInformation = not Data.db.global.showGuildInformation
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show the guild name, rank, and realm.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show Rating",
              function() return Data.db.global.showRating end,
              function()
                Data.db.global.showRating = not Data.db.global.showRating
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show the Mythic+ Rating column in the main window.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show Current Keystone",
              function() return Data.db.global.showCurrentKeystone end,
              function()
                Data.db.global.showCurrentKeystone = not Data.db.global.showCurrentKeystone
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show the Current Keystone column in the main window.", nil, nil, nil, true)
            end)
            local rioColors = menu:CreateCheckbox(
              "Use Raider.IO rating colors",
              function() return Data.db.global.useRIOScoreColor end,
              function()
                Data.db.global.useRIOScoreColor = not Data.db.global.useRIOScoreColor
                self:Render()
                return MenuResponse.Refresh
              end
            )
            rioColors:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("So many colors!", nil, nil, nil, true)
              if type(_G.RaiderIO) == "nil" then
                tooltip:AddLine(" ")
                tooltip:AddLine("Requires addon: Raider.IO", 1, 0, 0, true)
              end
            end)
            rioColors:SetEnabled(type(_G.RaiderIO) ~= "nil")
            menu:CreateTitle(DELVES_GREAT_VAULT_LABEL)
            menu:CreateCheckbox(
              "Show Raids",
              function() return Data.db.global.vault.raids end,
              function()
                Data.db.global.vault.raids = not Data.db.global.vault.raids
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Just one more!", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show Dungeons",
              function() return Data.db.global.vault.dungeons end,
              function()
                Data.db.global.vault.dungeons = not Data.db.global.vault.dungeons
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Just one more!", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show World",
              function() return Data.db.global.vault.world end,
              function()
                Data.db.global.vault.world = not Data.db.global.vault.world
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Just one more!", nil, nil, nil, true)
            end)
            menu:CreateTitle("Prey Hunts")
            menu:CreateCheckbox(
              "Enable Prey Hunts",
              function() return Data.db.global.prey.enabled end,
              function()
                Data.db.global.prey.enabled = not Data.db.global.prey.enabled
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Let's go for a hunt!", nil, nil, nil, true)
            end)
            local preyDifficultiesSetting = menu:CreateButton(
              "Difficulties"
            )
            TableForEach(Data:GetPreyDifficulties(true), function(difficulty)
              local hiddenDifficulties = Data.db.global.prey.hiddenDifficulties or {}
              preyDifficultiesSetting:CreateCheckbox(
                difficulty.name,
                function(difficultyID) return not hiddenDifficulties[difficultyID] end,
                function(difficultyID)
                  Data.db.global.prey.hiddenDifficulties[difficultyID] = not hiddenDifficulties[difficultyID]
                  self:Render()
                  return MenuResponse.Refresh
                end,
                difficulty.id
              )
            end)
            menu:CreateTitle(DUNGEONS)
            menu:CreateCheckbox(
              "Enable Dungeons",
              function() return Data.db.global.dungeons.enabled end,
              function()
                Data.db.global.dungeons.enabled = not Data.db.global.dungeons.enabled
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show Mythic+ dungeon information!", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show icons",
              function() return Data.db.global.showTiers end,
              function()
                Data.db.global.showTiers = not Data.db.global.showTiers
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show the timed icons (|A:Professions-ChatIcon-Quality-Tier1:16:16:0:-1|a |A:Professions-ChatIcon-Quality-Tier2:16:16:0:-1|a |A:Professions-ChatIcon-Quality-Tier3:16:16:0:-1|a).", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show rating",
              function() return Data.db.global.showScores end,
              function()
                Data.db.global.showScores = not Data.db.global.showScores
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show some scores!", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Use rating colors",
              function() return Data.db.global.showAffixColors end,
              function()
                Data.db.global.showAffixColors = not Data.db.global.showAffixColors
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show some colors!", nil, nil, nil, true)
            end)
            menu:CreateTitle(RAIDS)
            menu:CreateCheckbox(
              "Enable Raids",
              function() return Data.db.global.raids.enabled end,
              function()
                Data.db.global.raids.enabled = not Data.db.global.raids.enabled
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Because MythicPlus ain't enough!", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Use difficulty colors",
              function() return Data.db.global.raids.colors end,
              function()
                Data.db.global.raids.colors = not Data.db.global.raids.colors
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Argharhggh! So much greeeen!", nil, nil, nil, true)
            end)
            local raidKillIconSetting = menu:CreateButton("Kill icon")
            TableForEach(Constants.raidKillIcons, function(icon)
              raidKillIconSetting:CreateRadio(
                icon.label,
                function(id) return (Data.db.global.raids.killIcon or "skull") == id end,
                function(id)
                  Data.db.global.raids.killIcon = id
                  self:Render()
                  return MenuResponse.Refresh
                end,
                icon.id
              )
            end)
            local raidDifficultiesSetting = menu:CreateButton(
              "Difficulties"
            )
            TableForEach(Data:GetRaidDifficulties(true), function(difficulty)
              local hiddenDifficulties = Data.db.global.raids.hiddenDifficulties or {}
              raidDifficultiesSetting:CreateCheckbox(
                difficulty.name,
                function(id) return not hiddenDifficulties[id] end,
                function(id)
                  Data.db.global.raids.hiddenDifficulties[id] = not hiddenDifficulties[id]
                  self:Render()
                  return MenuResponse.Refresh
                end,
                difficulty.id
              )
            end)
            raidDifficultiesSetting:CreateCheckbox(
              "Timewalking",
              function() return Data.db.global.raids.timewalkingLockouts end,
              function()
                Data.db.global.raids.timewalkingLockouts = not Data.db.global.raids.timewalkingLockouts
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Shows Illidan/Yogg-Saron/Ragnaros lockouts while their Timewalking event is active.", nil, nil, nil, true)
            end)
            local trackerCurrencies = Data:GetCurrencies()

            menu:CreateTitle("Currencies")
            menu:CreateCheckbox(
              "Enable Currencies",
              function() return Data.db.global.currencies.enabled end,
              function()
                Data.db.global.currencies.enabled = not Data.db.global.currencies.enabled
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Time to farm!", nil, nil, nil, true)
            end)
            if CategoryHasIconCurrencies(trackerCurrencies, nil) then
              menu:CreateCheckbox(
                "Show icons",
                function() return Data.db.global.currencies.showIcons end,
                function()
                  Data.db.global.currencies.showIcons = not Data.db.global.currencies.showIcons
                  self:Render()
                  return MenuResponse.Refresh
                end
              ):SetTooltip(function(tooltip, elm)
                tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
                tooltip:AddLine("So fancy!", nil, nil, nil, true)
              end)
            end
            menu:CreateCheckbox(
              "Align text center",
              function() return Data.db.global.currencies.alignCenter end,
              function()
                Data.db.global.currencies.alignCenter = not Data.db.global.currencies.alignCenter
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Left or right? Center it is!", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Highlight max earned",
              function() return Data.db.global.currencies.showMaxEarned end,
              function()
                Data.db.global.currencies.showMaxEarned = not Data.db.global.currencies.showMaxEarned
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("They really do this, huh?", nil, nil, nil, true)
            end)
            local enabledCurrenciesOption = menu:CreateButton(
              "Currencies"
            )
            TableForEach(trackerCurrencies, function(currency)
              if currency.category ~= nil then return end
              local hiddenCurrencies = Data.db.global.currencies.hiddenCurrencies or {}
              enabledCurrenciesOption:CreateCheckbox(
                currency.name,
                function(id) return not hiddenCurrencies[id] end,
                function(id)
                  Data.db.global.currencies.hiddenCurrencies[id] = not hiddenCurrencies[id]
                  self:Render()
                  return MenuResponse.Refresh
                end,
                currency.id
              )
            end)
            menu:CreateTitle("Weeklies")
            menu:CreateCheckbox(
              "Enable Weeklies",
              function() return Data.db.global.weeklies.enabled end,
              function()
                Data.db.global.weeklies.enabled = not Data.db.global.weeklies.enabled
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Track this week's dailies... I mean weeklies.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show icons",
              function() return Data.db.global.weeklies.showIcons end,
              function()
                Data.db.global.weeklies.showIcons = not Data.db.global.weeklies.showIcons
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show each Weekly tracker's icon to the left of its current status or progress.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Align text center",
              function() return Data.db.global.weeklies.alignCenter end,
              function()
                Data.db.global.weeklies.alignCenter = not Data.db.global.weeklies.alignCenter
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Left or right? Center it is!", nil, nil, nil, true)
            end)
            local enabledWeekliesOption = menu:CreateButton(
              "Weeklies"
            )
            TableForEach(trackerCurrencies, function(currency)
              if currency.category ~= "weekly" then return end
              local hiddenCurrencies = Data.db.global.weeklies.hiddenCurrencies or {}
              enabledWeekliesOption:CreateCheckbox(
                currency.name,
                function(id) return not hiddenCurrencies[id] end,
                function(id)
                  Data.db.global.weeklies.hiddenCurrencies[id] = not hiddenCurrencies[id]
                  self:Render()
                  return MenuResponse.Refresh
                end,
                currency.id
              )
            end)
            menu:CreateTitle("Seasonal Chores")
            menu:CreateCheckbox(
              "Enable Seasonal Chores",
              function() return Data.db.global.seasonalChores.enabled end,
              function()
                Data.db.global.seasonalChores.enabled = not Data.db.global.seasonalChores.enabled
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Adulting, but for your alts.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show icons",
              function() return Data.db.global.seasonalChores.showIcons end,
              function()
                Data.db.global.seasonalChores.showIcons = not Data.db.global.seasonalChores.showIcons
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show each Seasonal Chore tracker's icon to the left of its current status or progress.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Align text center",
              function() return Data.db.global.seasonalChores.alignCenter end,
              function()
                Data.db.global.seasonalChores.alignCenter = not Data.db.global.seasonalChores.alignCenter
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Left or right? Center it is!", nil, nil, nil, true)
            end)
            local enabledSeasonalChoresOption = menu:CreateButton(
              "Chores"
            )
            TableForEach(trackerCurrencies, function(currency)
              if currency.category ~= "seasonalChore" then return end
              local hiddenCurrencies = Data.db.global.seasonalChores.hiddenCurrencies or {}
              enabledSeasonalChoresOption:CreateCheckbox(
                currency.name,
                function(id) return not hiddenCurrencies[id] end,
                function(id)
                  Data.db.global.seasonalChores.hiddenCurrencies[id] = not hiddenCurrencies[id]
                  self:Render()
                  return MenuResponse.Refresh
                end,
                currency.id
              )
            end)
            do
              local resetTrackerOrderButton = menu:CreateButton("Reset custom order", function()
                StaticPopup_Show("ALTEREGO_CONFIRM_RESET_TRACKER_ORDER")
              end)
              resetTrackerOrderButton:SetTooltip(function(tooltip, elm)
                tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
                tooltip:AddLine("Undo any reordering/recategorizing done via the hover arrows on Currencies, Weeklies and Seasonal Chores.", nil, nil, nil, true)
              end)
            end
            menu:CreateDivider()
            menu:CreateTitle(INTERFACE_OPTIONS)
            menu:CreateCheckbox(
              "Show Daily Delves",
              function() return Data.db.global.showDailyDelves ~= false end,
              function()
                Data.db.global.showDailyDelves = not (Data.db.global.showDailyDelves ~= false)
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Show the Daily Delves button in the AlterEgo main window title bar.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Collapsing row labels displays all icons",
              function() return Data.db.global.liqui.windows.Main.collapsingRowLabelsDisplaysAllIcons ~= false end,
              function()
                local settings = Data.db.global.liqui.windows.Main
                settings.collapsingRowLabelsDisplaysAllIcons = not (settings.collapsingRowLabelsDisplaysAllIcons ~= false)
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("When the Row Labels column is hidden, force tracker icons to be shown for Currencies, Weeklies and Seasonal Chores so each row remains identifiable.", nil, nil, nil, true)
              tooltip:AddLine("This temporarily overrides each section's Show icons setting only while Row Labels are collapsed.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show Weekly Affixes",
              function() return Data.db.global.showAffixHeader end,
              function()
                Data.db.global.showAffixHeader = not Data.db.global.showAffixHeader
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("The affixes will be shown at the top.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Show the minimap button",
              function() return not Data.db.global.minimap.hide end,
              function()
                Data.db.global.minimap.hide = not Data.db.global.minimap.hide
                addon.Libs.LibDBIcon:Refresh(addon.name, Data.db.global.minimap)
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("It does get crowded around the minimap sometimes.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Lock the minimap button",
              function() return Data.db.global.minimap.lock end,
              function()
                Data.db.global.minimap.lock = not Data.db.global.minimap.lock
                addon.Libs.LibDBIcon:Refresh(addon.name, Data.db.global.minimap)
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("No more moving the button around accidentally!", nil, nil, nil, true)
            end)
            do
              local resetDisplayButton = menu:CreateButton("Reset display filters & columns", function()
                StaticPopup_Show("ALTEREGO_CONFIRM_RESET_DISPLAY_FILTERS")
              end)
              resetDisplayButton:SetTooltip(function(tooltip, elm)
                tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
                tooltip:AddLine("Restore the Character display filters and columns to their default values without changing sorting, trackers, window layout, accounts, or Sync.", nil, nil, nil, true)
              end)
            end
            do
              local resetAllButton = menu:CreateButton("Reset all addon settings", function()
                StaticPopup_Show("ALTEREGO_CONFIRM_RESET_ALL_SETTINGS_STEP_1")
              end)
              resetAllButton:SetTooltip(function(tooltip, elm)
                tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
                tooltip:AddLine("Permanently erase all AlterEgo saved characters, accounts, settings, Sync configuration, and window layout, then reload the UI. Requires two confirmations.", nil, nil, nil, true)
              end)
            end
            menu:CreateDivider()
            local syncSectionTitle = menu:CreateTitle("Multi-Account Sync")
            syncSectionTitle:AddInitializer(function(frame, description)
              RegisterSyncTutorialMenuTarget("syncSection", frame, description)
            end)
            local enableSyncOption = menu:CreateCheckbox(
              "Enable Sync",
              function() return Data.db.global.sync.enabled end,
              function()
                if Data.db.global.sync.enabled then
                  Data.db.global.sync.enabled = false
                  addon.Core:ResetSyncBatchGuard()
                  addon.Core:Print("Sync: stopped. Nothing will be sent or received until you turn Enable Sync back on.")
                  -- This checkbox also owns the Only Sync Max Level Characters submenu.
                  -- Refresh the open menu explicitly so its checked state updates immediately
                  -- instead of looking off while Sync is already disabled.
                  return MenuResponse.Refresh
                end
                -- Only actually turns on once a password is confirmed --
                -- RequestPasswordThen enables it itself once that
                -- happens (see its OnAccept) when one isn't set yet, and
                -- immediately here when one already is.
                if RequestPasswordThen("enable") then
                  Data.db.global.sync.enabled = true
                  if addon.Core.AnnounceSyncPresence then addon.Core:AnnounceSyncPresence() end
                  -- Parent checkboxes with child menu entries are not reliably redrawn just
                  -- because their backing value changed. Force the redraw so Enable Sync
                  -- visibly lights up while preserving its nested max-level option.
                  return MenuResponse.Refresh
                end
                -- No password yet: close the menu so the password popup is the only active UI.
                return MenuResponse.CloseAll
              end
            )
            enableSyncOption:AddInitializer(function(button, description)
              RegisterSyncTutorialMenuTarget("enableSync", button, description)
            end)
            enableSyncOption:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Shares your Main WoW Account's characters with your other WoW accounts, as long as they're in the same guild, raid, or party, and set the same password below.", nil, nil, nil, true)
              tooltip:AddLine("Nobody else who can see messages on that channel receives anything unless they also know your password.", nil, nil, nil, true)
            end)
            local onlyMaxLevelOption = enableSyncOption:CreateCheckbox(
              "Only Sync Max Level Characters",
              function() return Data.db.global.sync.onlyMaxLevelCharacters ~= false end,
              function()
                Data.db.global.sync.onlyMaxLevelCharacters = not (Data.db.global.sync.onlyMaxLevelCharacters ~= false)
                if addon.Core.AnnounceSyncPresence then addon.Core:AnnounceSyncPresence() end
                return MenuResponse.Refresh
              end
            )
            onlyMaxLevelOption:AddInitializer(function(button, description)
              RegisterSyncTutorialMenuTarget("onlyMaxLevel", button, description)
            end)
            onlyMaxLevelOption:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Only sends characters at Retail's current maximum level.", nil, nil, nil, true)
            end)
            local setPasswordButton = menu:CreateButton(
              Data.db.global.sync.password ~= "" and ("Change Password: " .. Data.db.global.sync.password) or "Set Password",
              function()
                StaticPopup_Show("ALTEREGO_SYNC_PASSWORD")
                -- Force the whole settings menu closed here instead of
                -- relying on the default post-click behavior -- the
                -- popup should be the only thing left on screen, not
                -- layered on top of (or behind) the still-open menu.
                return MenuResponse.CloseAll
              end
            )
            setPasswordButton:AddInitializer(function(button, description)
              RegisterSyncTutorialMenuTarget("setPassword", button, description)
            end)
            setPasswordButton:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Must be identical on every account you want to sync with.", nil, nil, nil, true)
              tooltip:AddLine("Avoid generic passwords such as \"123\". You can use your own nickname if you prefer.", 1, 0.82, 0, true)
              tooltip:AddLine("Also used to name the WoW Account that characters synced in from this password land under (e.g. \"2 (yourpassword)\") -- unless one already exists with a matching name, in which case that one's reused instead.", nil, nil, nil, true)
            end)
            local syncChannelNames = { BOTH = "Both", GUILD = "Guild", PARTY = "Party/Raid" }
            local syncChannelButton = menu:CreateButton(
              format("Sync Channel: %s", syncChannelNames[Data.db.global.sync.channel] or "Guild"),
              function() end
            )
            BindLiveMenuLabel(syncChannelButton)
            syncChannelButton:AddInitializer(function(button, description)
              RegisterSyncTutorialMenuTarget("syncChannel", button, description)
            end)
            syncChannelButton:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Guild only is the safest default -- it doesn't need to know which channel the other account can actually see.", nil, nil, nil, true)
            end)
            for _, option in ipairs({
              { value = "GUILD", text = "Guild only (default)" },
              { value = "PARTY", text = "Party/Raid only" },
              { value = "BOTH", text = "Both" },
            }) do
              syncChannelButton:CreateRadio(
                option.text,
                function(value) return (Data.db.global.sync.channel or "GUILD") == value end,
                function(value)
                  Data.db.global.sync.channel = value
                  if addon.Core.AnnounceSyncPresence then addon.Core:AnnounceSyncPresence() end
                  SetLiveMenuLabel(syncChannelButton, format("Sync Channel: %s", syncChannelNames[value] or "Guild"))
                  return MenuResponse.Refresh
                end,
                option.value
              )
            end
            local syncNowButton = menu:CreateButton(
              "Sync Now",
              function()
                -- Clicking Sync Now is a clear enough intent to sync that
                -- it turns Enable Sync on by itself -- but never without a
                -- confirmed password: RequestPasswordThen only enables
                -- and force-syncs once one is actually set (see its
                -- OnAccept), immediately here when one already is.
                if RequestPasswordThen("syncNow") then
                  Data.db.global.sync.enabled = true
                  addon.Core:ForceSyncBroadcast()
                end
                return MenuResponse.CloseAll
              end
            )
            syncNowButton:AddInitializer(function(button, description)
              RegisterSyncTutorialMenuTarget("syncNow", button, description)
            end)
            syncNowButton:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Checks matching Sync peers, then sends only eligible Main WoW Account characters they report missing or outdated. Prints why if it can't reconcile.", nil, nil, nil, true)
            end)
            local syncSettingsButton = menu:CreateButton(
              "Sync Addon Settings",
              function()
                -- Sharing addon settings uses Sync's transport too, so a
                -- click here carries the same intent as Sync Now: make
                -- sure a password exists and turn Enable Sync on before
                -- offering the final Share Settings confirmation. When
                -- no password exists yet, RequestPasswordThen resumes
                -- this flow after the password popup is accepted.
                if RequestPasswordThen("syncSettings") then
                  Data.db.global.sync.enabled = true
                  StaticPopup_Show("ALTEREGO_SYNC_SETTINGS")
                end
                return MenuResponse.CloseAll
              end
            )
            syncSettingsButton:AddInitializer(function(button, description)
              RegisterSyncTutorialMenuTarget("syncSettings", button, description)
            end)
            syncSettingsButton:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Shares your display and behavior settings, not characters, with your other WoW accounts, over the same password and channel as everything else here.", nil, nil, nil, true)
              tooltip:AddLine("Only happens when you click this and confirm -- never automatically.", nil, nil, nil, true)
            end)
            local syncTutorialButton = menu:CreateButton(
              "Sync Tutorial",
              function()
                Module:ShowSyncTutorial()
                return MenuResponse.CloseAll
              end
            )
            syncTutorialButton:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Opens a step-by-step guide for configuring Multi-Account Sync from start to finish.", nil, nil, nil, true)
            end)
          end,
      onWindowOptionsAfterBorder = function(_, menu)
        local settings = Data.db.global.liqui.windows.Main
        menu:CreateCheckbox(
          "Show Logo Icon Only",
          function() return settings.logoIconOnly == true end,
          function()
            settings.logoIconOnly = not (settings.logoIconOnly == true)
            self:Render()
            return MenuResponse.Refresh
          end
        ):SetTooltip(function(tooltip)
          tooltip:AddLine("Show Logo Icon Only", 1, 1, 1, true)
          tooltip:AddLine("Show only the AlterEgo logo in the Main window header. This also shrinks the Show/Hide Row Labels hitbox so more header controls can fit on the same row.", nil, nil, nil, true)
        end)
      end,
      titlebarButtons = {
        {
          name = "Accounts & Characters",
          icon = Constants.media.IconAccount,
          tooltipTitle = "Accounts & Characters",
          tooltipDescription = "Toggle your characters.",
          onMenu = function(_, rootMenu)
            rootMenu:SetScrollMode(math.min(20 * 50, GetScreenHeight() - 20)) -- 20 pixels per row, 50 rows

            ---Build the checkbox row for one character (same row used before this feature existed).
            local function addCharacterRow(parentMenu, char)
              local nameColor = WHITE_FONT_COLOR
              if char.info.class.file ~= nil then
                local classColor = C_ClassColor.GetClassColor(char.info.class.file)
                if classColor ~= nil then
                  nameColor = CreateColor(classColor.r, classColor.g, classColor.b, 1)
                end
              end
              local characterName = format("%s (%s)", nameColor:WrapTextInColorCode(char.info.name), char.info.realm)
              local characterButton = parentMenu:CreateCheckbox(
                characterName,
                function(value) return Data.db.global.characters[value].enabled end,
                function(value)
                  Data.db.global.characters[value].enabled = not Data.db.global.characters[value].enabled
                  if addon.Core.AnnounceSyncPresence then addon.Core:AnnounceSyncPresence() end
                  self:Render()
                  return MenuResponse.Refresh
                end,
                char.GUID
              )
              local moveCharacterButton = characterButton:CreateButton("Move Character")
              TableForEach(Data:GetAccounts(), function(targetAccount)
                moveCharacterButton:CreateRadio(
                  targetAccount.name,
                  function() return (char.accountId or Data:EnsureDefaultAccount()) == targetAccount.id end,
                  function()
                    Data:MoveCharacterToAccount(char.GUID, targetAccount.id)
                    if addon.Core.AnnounceSyncPresence then addon.Core:AnnounceSyncPresence() end
                    self:Render()
                    return MenuResponse.Refresh
                  end
                )
              end)
              if char.GUID ~= UnitGUID("player") then
                local removeButton = characterButton:CreateButton("Remove character", function()
                  StaticPopup_Show("ALTEREGO_DELETE_CHARACTER", characterName, nil, char)
                end)
                removeButton:SetTooltip(function(tooltip, elm)
                  tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
                  tooltip:AddLine(format("Remove %s?", characterName), nil, nil, nil, true)
                end)
              end
            end

            local accounts = Data:GetAccounts()
            TableForEach(accounts, function(account)
              -- ---------------------------------------------------------------
              -- REAL BUG FIXED HERE, for good this time: renaming and the
              -- "Main WoW Account" toggle used to be a right-click hitbox and
              -- a clickable "M" glyph, both implemented as a custom child
              -- frame attached to this row's underlying Blizzard button.
              -- Blizzard's Menu API pools that exact frame GLOBALLY, across
              -- every dropdown in the game -- not just this addon's own
              -- menus, but every OTHER window's own generic "Settings" gear
              -- (LiqUI adds one to every window automatically), any other
              -- addon's menus, and even native secure menus (a real bug
              -- report: right-clicking a raid-frame unit's own context menu
              -- broke a protected Blizzard function because our own code had
              -- run on that same shared frame at some point). No registry of
              -- "hide this on every OTHER menu we know about" can ever fully
              -- close that off, since there's no way to enumerate every
              -- dropdown that might ever reuse the frame. The only fully
              -- robust fix is what's below: plain, native menu content (a
              -- text badge, ordinary submenu buttons, exactly like "Remove
              -- character"/"Move Character" already use safely elsewhere in
              -- this same menu) that Blizzard's OWN menu framework owns and
              -- rebuilds fresh every time -- there is nothing left behind on
              -- the shared frame for a later, unrelated menu to inherit.
              -- ---------------------------------------------------------------
              local isMainAccount = Data.GetMainAccountId and Data:GetMainAccountId() == account.id

              -- The row itself IS the "track this whole account" checkbox.
              -- The Main WoW Account badge is plain text baked into the
              -- label -- computed fresh every time this menu is built,
              -- exactly like character rows already color names by class.
              local accountRow = rootMenu:CreateCheckbox(
                isMainAccount and format("%s  |cffffd100[Main]|r", account.name) or account.name,
                function() return account.enabled end,
                function()
                  Data:SetAccountEnabled(account.id, not account.enabled)
                  if addon.Core.AnnounceSyncPresence then addon.Core:AnnounceSyncPresence() end
                  self:Render()
                  return MenuResponse.Refresh
                end
              )

              if accountRow.SetIcon then
                accountRow:SetIcon(Constants.media.IconAccount)
              end
              if isMainAccount then
                accountRow:AddInitializer(function(button, description)
                  RegisterSyncTutorialMenuTarget("mainAccount", button, description)
                end)
              end

              accountRow:CreateButton("Rename or Delete WoW Account", function()
                StaticPopup_Show("ALTEREGO_RENAME_ACCOUNT", account.name, nil, account)
              end)

              if Data.GetMainAccountId and Data.SetMainAccount then
                -- "Main" toggle -- marks which WoW Account this installation
                -- actually plays. Once set: Sync only ever SENDS characters
                -- filed under it, and never lets incoming sync data overwrite
                -- characters already filed under it (see Comm.lua). Only one
                -- account can be Main -- setting a new one clears the
                -- previous (Data:SetMainAccount already enforces this in the
                -- saved data, so there's nothing extra to keep in sync here).
                -- No MenuResponse.Refresh here on purpose -- closes the whole
                -- Accounts & Characters menu on click (same default behavior
                -- as "Rename or Delete WoW Account"/"Remove character" above),
                -- instead of staying open needing a manual close afterward.
                local mainToggleButton = accountRow:CreateButton(
                  isMainAccount and "Unset as Main WoW Account" or "Set as Main WoW Account",
                  function()
                    if isMainAccount then
                      Data:SetMainAccount(nil)
                      if addon.Core.AnnounceSyncPresence then addon.Core:AnnounceSyncPresence() end
                      self:Render()
                      return
                    end

                    local currentMainId = Data:GetMainAccountId()
                    if currentMainId and currentMainId ~= account.id then
                      local currentMain = Data.db.global.accounts[currentMainId]
                      StaticPopup_Show(
                        "ALTEREGO_CONFIRM_CHANGE_MAIN_ACCOUNT",
                        (currentMain and currentMain.name) or "The current Main WoW Account",
                        account.name,
                        account
                      )
                      return
                    end

                    Data:SetMainAccount(account.id)
                    if addon.Core.AnnounceSyncPresence then addon.Core:AnnounceSyncPresence() end
                    self:Render()
                  end
                )
                mainToggleButton:SetTooltip(function(tooltip, elm)
                  tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
                  if isMainAccount then
                    tooltip:AddLine("Sync only sends characters from here, and never lets incoming sync data overwrite them.", nil, nil, nil, true)
                  else
                    tooltip:AddLine("Marks this as the account this installation actually plays. Sync will only send characters filed here, and will protect them from being overwritten by incoming sync data.", nil, nil, nil, true)
                  end
                end)
              end

              -- Expanding the row (hover arrow, same mechanism "Remove character"
              -- already uses today) opens this account's own character list.
              local accountCharacters = Data:GetCharactersByAccount(account.id, true)
              TableForEach(accountCharacters, function(char)
                addCharacterRow(accountRow, char)
              end)
            end)

            rootMenu:CreateDivider()
            rootMenu:CreateButton("+ Add WoW Account", function()
              Data:CreateAccount()
              self:Render()
            end)
          end,
          iconSize = 18,
        },
        {
          name = "Sorting",
          icon = Constants.media.IconSorting,
          tooltipTitle = "Sorting",
          tooltipDescription = "Sort your characters.",
          onMenu = function(_, rootMenu)
            for _, option in ipairs(Constants.sortingOptions) do
              local button = rootMenu:CreateRadio(
                option.text,
                function(value) return Data.db.global.sorting == value end,
                function(value)
                  Data.db.global.sorting = value
                  self:Render()
                  return MenuResponse.Refresh
                end,
                option.value
              )
              if option.tooltipTitle or option.tooltipText then
                button:SetTooltip(function(tooltip)
                  if option.tooltipTitle then
                    tooltip:AddLine(option.tooltipTitle, 1, 1, 1, true)
                  end
                  if option.tooltipText then
                    tooltip:AddLine(option.tooltipText, nil, nil, nil, true)
                  end
                end)
              end
            end
          end,
          iconSize = 16,
        },
        {
          name = "Announce",
          icon = Constants.media.IconAnnounce,
          tooltipTitle = "Announcements",
          tooltipDescription = "Sharing is caring.",
          onMenu = function(window, menu)
            menu:CreateTitle("Announce Current Keystones")
            local sendToParty = menu:CreateButton(
              "Send to Party Chat",
              function()
                if not IsInGroup() then
                  addon.Core:Print("You are not in a party.")
                  return
                end
                addon.Core:AnnounceKeystones("PARTY")
              end
            )
            sendToParty:SetEnabled(IsInGroup())
            sendToParty:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Announce all your keystones to the party chat.", nil, nil, nil, true)
              if not IsInGroup() then
                tooltip:AddLine(" ")
                tooltip:AddLine("You are not in a party.", 1, 0, 0, true)
              end
            end)
            local sendToGuild = menu:CreateButton(
              "Send to Guild Chat",
              function()
                if not IsInGuild() then
                  addon.Core:Print("You are not in a guild.")
                  return
                end
                addon.Core:AnnounceKeystones("GUILD")
              end
            )
            sendToGuild:SetEnabled(IsInGuild())
            sendToGuild:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Announce all your keystones to the guild chat.", nil, nil, nil, true)
              if not IsInGuild() then
                tooltip:AddLine(" ")
                tooltip:AddLine("You are not in a guild.", 1, 0, 0, true)
              end
            end)
            menu:CreateTitle(OPTIONS)
            local withCharacterNames
            local withMultipleMessages = menu:CreateCheckbox(
              "Multiple chat messages",
              function() return Data.db.global.announceKeystones.multiline end,
              function()
                Data.db.global.announceKeystones.multiline = not Data.db.global.announceKeystones.multiline
                withCharacterNames:SetEnabled(Data.db.global.announceKeystones.multiline)
                return MenuResponse.Refresh
              end
            )
            withCharacterNames = menu:CreateCheckbox(
              "Include character names",
              function() return Data.db.global.announceKeystones.multilineNames end,
              function()
                Data.db.global.announceKeystones.multilineNames = not Data.db.global.announceKeystones.multilineNames
                return MenuResponse.Refresh
              end
            )
            withMultipleMessages:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Announce keystones with multiple chat messages.", nil, nil, nil, true)
              tooltip:AddLine(" ")
              tooltip:AddLine("|cffff0000Warning: |rIf you have a lot of characters it could get spammy and the messages may get blocked.", nil, nil, nil, true)
            end)
            withCharacterNames:SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Add character names before each keystone.", nil, nil, nil, true)
              if not Data.db.global.announceKeystones.multiline then
                tooltip:AddLine(" ")
                tooltip:AddLine("Multiple chat messages must be enabled.", 1, 0, 0, true)
              end
            end)
            withCharacterNames:SetEnabled(Data.db.global.announceKeystones.multiline)
            menu:CreateDivider()
            menu:CreateTitle("Automatic Announcements")
            menu:CreateCheckbox(
              "Announce instance resets",
              function() return Data.db.global.announceResets end,
              function()
                Data.db.global.announceResets = not Data.db.global.announceResets
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Let others in your group know when you've reset the instances.", nil, nil, nil, true)
            end)
            menu:CreateCheckbox(
              "Announce new keystones (Party)",
              function() return Data.db.global.announceKeystones.autoParty end,
              function()
                Data.db.global.announceKeystones.autoParty = not Data.db.global.announceKeystones.autoParty
                self:Render()
                return MenuResponse.Refresh
              end
            ):SetTooltip(function(tooltip, elm)
              tooltip:AddLine(MenuUtil.GetElementText(elm), 1, 1, 1, true)
              tooltip:AddLine("Announce to your party when you loot a new keystone.", nil, nil, nil, true)
            end)
          end,
          iconSize = 12,
        },
        {
          name = "GreatVault",
          icon = Constants.media.IconKeyhole,
          tooltipTitle = DELVES_GREAT_VAULT_LABEL,
          tooltipDescription = WEEKLY_REWARDS_ADD_ITEMS .. "\n\n" .. GREEN_FONT_COLOR:WrapTextInColorCode(format("<%s>", WEEKLY_REWARDS_CLICK_TO_PREVIEW_INSTRUCTIONS)),
          onClick = function()
            addon.Core:ToggleVault()
          end,
          iconSize = 13,
        },
        {
          name = "RaidGroupLockouts",
          icon = Constants.media.IconCharacters,
          tooltipTitle = "Raid Group Lockouts",
          tooltipDescription = "Check Normal, Heroic, and Mythic lockouts shared by your current raid group." .. "\n\n" .. GREEN_FONT_COLOR:WrapTextInColorCode("<Click to Open>"),
          onClick = function()
            addon.Core:ToggleRaidLockouts()
          end,
          iconSize = 13,
        },
      },
    })
    local sidebarWidth = Constants.sizes.sidebar.width
    self.window.body.sidebar = CreateFrame("Frame", "$parentSidebar", self.window.body)
    self.window.body.sidebar:SetPoint("TOPLEFT", self.window.body, "TOPLEFT")
    self.window.body.sidebar:SetPoint("BOTTOMLEFT", self.window.body, "BOTTOMLEFT")
    self.window.body.sidebar:SetWidth(sidebarWidth)
    SetBackgroundColor(self.window.body.sidebar, 0, 0, 0, 0.3)
    self.window.body.content = CreateFrame("Frame", "$parentContent", self.window.body)
    self.window.body.content:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPRIGHT")
    self.window.body.content:SetPoint("BOTTOMRIGHT", self.window.body, "BOTTOMRIGHT")
    self.window.body.content.scrollArea = CreateScrollArea(self.window.body.content, {
      horizontal = true,
      hideHorizontalScrollBar = true,
      name = "$parentCharacterScroll",
    })
    self.window.body.content.scrollArea:SetAllPoints()
    -- WowScrollBox clips its rendering, but explicitly clip every layer of the
    -- character viewport as well so off-screen columns never leak outside the
    -- visible Main-window character area.
    local characterScrollArea = self.window.body.content.scrollArea
    -- The horizontal bar is retained internally so ScrollBox can calculate its
    -- range, but Main is intentionally wheel/edge-arrow only. Suppress it here
    -- as well as in LiqUI so Blizzard cannot flash it back on during relayout.
    if characterScrollArea.horizontalScrollBar then
      characterScrollArea.horizontalScrollBar:SetAlpha(0)
      characterScrollArea.horizontalScrollBar:EnableMouse(false)
      if characterScrollArea.horizontalScrollBar.SetMouseMotionEnabled then
        characterScrollArea.horizontalScrollBar:SetMouseMotionEnabled(false)
      end
      characterScrollArea.horizontalScrollBar:Hide()
    end
    if characterScrollArea.container.SetClipsChildren then
      characterScrollArea.container:SetClipsChildren(true)
    end
    if characterScrollArea.horizontalScrollBox and characterScrollArea.horizontalScrollBox.SetClipsChildren then
      characterScrollArea.horizontalScrollBox:SetClipsChildren(true)
    end
    if self.window.body.content.SetClipsChildren then
      self.window.body.content:SetClipsChildren(true)
    end
    EnsureCharacterScrollEdgeButtons(self.window)

    -- The AlterEgo logo/title doubles as a compact toggle for the row-label
    -- sidebar. Keep this control in Main rather than LiqUI so it affects only
    -- this window and leaves character cells untouched.
    self.window.sidebarToggleButton = CreateFrame("Button", "$parentSidebarToggle", self.window.titlebar)
    self.window.sidebarToggleButton:RegisterForClicks("LeftButtonUp")
    self.window.sidebarToggleButton:SetFrameLevel(self.window.titlebar:GetFrameLevel() + 5)
    SetBackgroundColor(self.window.sidebarToggleButton, 1, 1, 1, 0)
    self.window.sidebarToggleButton:SetScript("OnEnter", function(button)
      SetBackgroundColor(button, 1, 1, 1, 0.08)
      local sidebarCollapsed = Data.db.global.liqui.windows.Main.sidebarCollapsed == true
      GameTooltip:SetOwner(button, "ANCHOR_TOP")
      GameTooltip:SetText(sidebarCollapsed and "Show row labels column" or "Hide row labels column", 1, 1, 1)
      GameTooltip:AddLine(
        sidebarCollapsed
          and "Show the left column that labels each row in the main character grid."
          or "Hide the left column that labels each row in the main character grid to give more horizontal space to your characters.",
        nil, nil, nil, true
      )
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Character information remains visible in every character column; only the shared row labels are hidden.", nil, nil, nil, true)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(sidebarCollapsed and "<Click to Show Row Labels>" or "<Click to Hide Row Labels>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
      GameTooltip:Show()
    end)
    self.window.sidebarToggleButton:SetScript("OnLeave", function(button)
      SetBackgroundColor(button, 1, 1, 1, 0)
      GameTooltip:Hide()
    end)
    self.window.sidebarToggleButton:SetScript("OnClick", function()
      local settings = Data.db.global.liqui.windows.Main
      settings.sidebarCollapsed = not (settings.sidebarCollapsed == true)
      GameTooltip:Hide()
      Module:Render()
    end)

    -- Closing the main window starts a fresh Settings session next time.
    -- Merely closing the Settings dropdown itself keeps the saved position.
    self.window:HookScript("OnHide", function()
      Module.settingsMenuScrollPercentage = nil
      HideSyncTutorial()
    end)

    self.window.affixes = CreateFrame("Frame", "$parentAffixes", self.window.titlebar)
    self.window.affixes.buttons = {}
    self.window.dailyDelvesSeparator = self.window.titlebar:CreateFontString("$parentDailyDelvesSeparator", "OVERLAY", "GameFontDisable")
    self.window.dailyDelvesSeparator:SetText("|")
    self.window.dailyDelvesButton = CreateFrame("Button", "$parentDailyDelves", self.window.titlebar)
    self.window.dailyDelvesButton:SetSize(20, 20)
    self.window.dailyDelvesButton:SetNormalAtlas("delves-bountiful")
    self.window.dailyDelvesButton:SetHighlightAtlas("delves-bountiful")
    self.window.dailyDelvesButton:GetHighlightTexture():SetAlpha(0.25)
    self.window.dailyDelvesButton:SetScript("OnEnter", function(button)
      GameTooltip:SetOwner(button, "ANCHOR_TOP")
      GameTooltip:SetText("Daily Delves", 1, 1, 1)
      GameTooltip:AddLine("View today's Delve stories and their difficulty tier.", nil, nil, nil, true)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("<Click to View Daily Delves>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
      GameTooltip:Show()
    end)
    self.window.dailyDelvesButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.window.dailyDelvesButton:SetScript("OnClick", function()
      if dailyDelvesModule then dailyDelvesModule:Toggle() end
    end)
  end

  if not self.window:IsVisible() then
    return
  end

  local scrollContent = self.window.body.content.scrollArea.content
  local sidebarCollapsed = mainWindowSettings.sidebarCollapsed == true

  -- Collapsing the sidebar only changes the shared row-label column. The
  -- character grid keeps rendering every cell exactly as before. Re-anchor
  -- the content directly to the body so the freed width is usable.
  self.window.body.sidebar:SetShown(not sidebarCollapsed)
  self.window.body.content:ClearAllPoints()
  if sidebarCollapsed then
    self.window.body.content:SetPoint("TOPLEFT", self.window.body, "TOPLEFT")
  else
    self.window.body.content:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPRIGHT")
  end
  self.window.body.content:SetPoint("BOTTOMRIGHT", self.window.body, "BOTTOMRIGHT")

  EnsureRowHighlightPoller(self.window)

  do -- Titlebar: Affixes
    local logoIconOnly = mainWindowSettings.logoIconOnly == true
    if logoIconOnly or numCharacters < 3 then
      self.window.titlebar.title:Hide()
    else
      self.window.titlebar.title:Show()
    end

    -- Make exactly the visible AlterEgo branding clickable. In icon-only mode
    -- keep the hitbox compact around the logo itself; the titlebar layout reads
    -- this frame's actual width, so the space released by hiding the title is
    -- immediately available to the other header controls.
    local sidebarToggleButton = self.window.sidebarToggleButton
    sidebarToggleButton:SetEnabled(numCharacters > 0)
    sidebarToggleButton:ClearAllPoints()
    if self.window.titlebar.title:IsShown() then
      sidebarToggleButton:SetPoint("TOPLEFT", self.window.titlebar, "TOPLEFT", 0, 0)
      sidebarToggleButton:SetPoint("BOTTOMLEFT", self.window.titlebar, "BOTTOMLEFT", 0, 0)
      sidebarToggleButton:SetPoint("RIGHT", self.window.titlebar.title, "RIGHT", 6, 0)
    else
      local titlebarHeight = Constants.sizes.titlebar.height
      sidebarToggleButton:SetSize(titlebarHeight, titlebarHeight)
      sidebarToggleButton:SetPoint("CENTER", self.window.titlebar.icon, "CENTER", 0, 0)
    end

    -- LayoutMainTitlebarButtons reparents the individual affix buttons onto the titlebar or
    -- an overflow row. They therefore no longer inherit visibility from window.affixes. Hide
    -- every previously rendered button up front so disabling Show Weekly Affixes (or a shorter
    -- affix list) cannot leave stale buttons visible after the next layout pass.
    TableForEach(self.window.affixes.buttons, function(affixFrame)
      affixFrame:Hide()
    end)

    if currentAffixes and TableCount(currentAffixes) > 0 and Data.db.global.showAffixHeader then
      -- The titlebar layout now wraps the right-side controls into as many rows as needed,
      -- so Weekly Affixes no longer has to disappear just because only one character column
      -- is visible. Keep it available and let LayoutMainTitlebarButtons reserve its space.
      self.window.affixes:Show()
    else
      self.window.affixes:Hide()
    end

    if self.window.affixes:IsVisible() then
      local affixAnchor = self.window.titlebar
      TableForEach(currentAffixes, function(affix, affixIndex)
        local name, desc, fileDataID = C_ChallengeMode.GetAffixInfo(affix.id)
        local affixFrame = self.window.affixes.buttons[affixIndex]
        if not affixFrame then
          affixFrame = CreateFrame("Button", "$parentAffix" .. affixIndex, self.window.affixes)
          self.window.affixes.buttons[affixIndex] = affixFrame
        end

        affixFrame:Show()
        affixFrame:ClearAllPoints()
        affixFrame:SetSize(20, 20)
        affixFrame:SetNormalTexture(fileDataID)
        affixFrame:SetScript("OnEnter", function()
          GameTooltip:SetOwner(affixFrame, "ANCHOR_TOP")
          GameTooltip:SetText(name, 1, 1, 1)
          GameTooltip:AddLine(desc, nil, nil, nil, true)
          if weeklyAffixesModule then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("<Click to View Weekly Affixes>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
          end
          GameTooltip:Show()
        end)
        affixFrame:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)
        affixFrame:SetScript("OnClick", function()
          if not weeklyAffixesModule then return end
          local affixesWindow = LibLiqUI:GetElement("Window", addon.name .. "Affixes")
          if affixesWindow then
            affixesWindow:Toggle()
            if affixesWindow:IsVisible() then
              affixesWindow:Raise()
            end
          end
        end)

        if affixIndex == 1 then
          affixFrame:ClearAllPoints()
          if numCharacters < 3 then
            affixFrame:SetPoint("LEFT", self.window.titlebar.icon, "RIGHT", 6, 0)
          else
            affixFrame:SetPoint("CENTER", affixAnchor, "CENTER", -((TableCount(currentAffixes) * 20) / 2), 0)
          end
        else
          affixFrame:SetPoint("LEFT", affixAnchor, "RIGHT", 6, 0)
        end
        affixAnchor = affixFrame
      end)

      if Data.db.global.showDailyDelves ~= false then
        self.window.dailyDelvesSeparator:ClearAllPoints()
        self.window.dailyDelvesSeparator:SetPoint("LEFT", affixAnchor, "RIGHT", 8, 0)
        self.window.dailyDelvesSeparator:Show()
        self.window.dailyDelvesButton:ClearAllPoints()
        self.window.dailyDelvesButton:SetPoint("LEFT", self.window.dailyDelvesSeparator, "RIGHT", 8, 0)
        self.window.dailyDelvesButton:Show()
      else
        self.window.dailyDelvesSeparator:Hide()
        self.window.dailyDelvesButton:Hide()
      end
    else
      self.window.dailyDelvesSeparator:Hide()
      if Data.db.global.showDailyDelves ~= false then
        self.window.dailyDelvesButton:ClearAllPoints()
        if numCharacters < 3 then
          self.window.dailyDelvesButton:SetPoint("LEFT", self.window.titlebar.icon, "RIGHT", 6, 0)
        else
          self.window.dailyDelvesButton:SetPoint("CENTER", self.window.titlebar, "CENTER", 0, 0)
        end
        self.window.dailyDelvesButton:Show()
      else
        self.window.dailyDelvesButton:Hide()
      end
    end
  end

  do -- Sidebar
    local rowCount = 0
    local totalHeight = 0
    do -- CharacterInfo Labels
      self.window.body.sidebar.infoFrames = self.window.body.sidebar.infoFrames or {}
      TableForEach(self.window.body.sidebar.infoFrames, function(f) f:Hide() end)
      TableForEach(characterInfo, function(info, infoIndex)
        local infoFrame = self.window.body.sidebar.infoFrames[infoIndex]
        if not infoFrame then
          infoFrame = CreateFrame("Frame", "$parentInfo" .. infoIndex, self.window.body.sidebar)
          infoFrame.text = infoFrame:CreateFontString(infoFrame:GetName() .. "Text", "OVERLAY")
          infoFrame.text:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", Constants.sizes.padding, -3)
          infoFrame.text:SetPoint("BOTTOMRIGHT", infoFrame, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
          infoFrame.text:SetJustifyH("LEFT")
          infoFrame.text:SetFontObject("GameFontHighlight_NoShadow")
          infoFrame.text:SetVertexColor(1.0, 0.82, 0.0, 1)
          self.window.body.sidebar.infoFrames[infoIndex] = infoFrame
        end

        infoFrame:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
        infoFrame:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
        infoFrame:SetHeight(Constants.sizes.row)
        infoFrame.text:SetText(info.label)
        infoFrame:Show()
        rowCount = rowCount + 1
        totalHeight = totalHeight + Constants.sizes.row
      end)
    end

    do -- Prey Header
      local label = self.window.body.sidebar.preyLabel
      if not label then
        label = CreateFrame("Frame", "$parentPreyLabel", self.window.body.sidebar)
        label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
        label.text:SetPoint("TOPLEFT", label, "TOPLEFT", Constants.sizes.padding, 0)
        label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 0)
        label.text:SetFontObject("GameFontHighlight_NoShadow")
        label.text:SetJustifyH("LEFT")
        label.text:SetText("Prey Hunts")
        label.text:SetVertexColor(1.0, 0.82, 0.0, 1)
        self.window.body.sidebar.preyLabel = label
      end
      if Data.db.global.prey.enabled then
        label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
        label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
        label:SetHeight(Constants.sizes.row)
        label:Show()
        rowCount = rowCount + 1
        totalHeight = totalHeight + Constants.sizes.row
      else
        label:Hide()
      end
    end

    do -- Prey Difficulties
      self.window.body.sidebar.preyDifficulties = self.window.body.sidebar.preyDifficulties or {}
      TableForEach(self.window.body.sidebar.preyDifficulties, function(f) f:Hide() end)
      TableForEach(Data:GetPreyDifficulties(), function(difficulty, difficultyIndex)
        if not Data.db.global.prey.enabled then return end
        local difficultyFrame = self.window.body.sidebar.preyDifficulties[difficultyIndex]
        if not difficultyFrame then
          difficultyFrame = CreateFrame("Frame", "$parentPreyDifficulty" .. difficultyIndex, self.window.body.sidebar)
          difficultyFrame.text = difficultyFrame:CreateFontString(difficultyFrame:GetName() .. "Text", "OVERLAY")
          difficultyFrame.text:SetPoint("TOPLEFT", difficultyFrame, "TOPLEFT", Constants.sizes.padding, -3)
          difficultyFrame.text:SetPoint("BOTTOMRIGHT", difficultyFrame, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
          difficultyFrame.text:SetFontObject("GameFontHighlight_NoShadow")
          difficultyFrame.text:SetJustifyH("LEFT")
          difficultyFrame.text:SetVertexColor(1.0, 1.0, 1.0, 1.0)
          self.window.body.sidebar.preyDifficulties[difficultyIndex] = difficultyFrame
        end

        difficultyFrame:SetScript("OnEnter", function()
          GameTooltip:SetOwner(difficultyFrame, "ANCHOR_RIGHT")
          GameTooltip:SetText(difficulty.name, 1, 1, 1)
          GameTooltip:AddLine("With each difficulty level, new affixes are added, leading to more challenging encounters.", nil, nil, nil, true)
          TableForEach(difficulty.affixes, function(affixID)
            local affix = TableGet(Data.preyAffixes, "id", affixID)
            if not affix then return end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(format("%s:", affix.name), nil, nil, nil, true)
            GameTooltip:AddLine(affix.description, 1, 1, 1, true)
          end)
          GameTooltip:Show()
        end)
        difficultyFrame:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)

        difficultyFrame:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
        difficultyFrame:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
        difficultyFrame:SetHeight(Constants.sizes.row)
        difficultyFrame.text:SetText(difficulty.name)
        difficultyFrame:Show()
        rowCount = rowCount + 1
        totalHeight = totalHeight + Constants.sizes.row
      end)
    end

    do -- MythicPlus Header
      local label = self.window.body.sidebar.mpluslabel
      if not label then
        label = CreateFrame("Frame", "$parentMythicPlusLabel", self.window.body.sidebar)
        label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
        label.text:SetPoint("TOPLEFT", label, "TOPLEFT", Constants.sizes.padding, 0)
        label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 0)
        label.text:SetFontObject("GameFontHighlight_NoShadow")
        label.text:SetJustifyH("LEFT")
        label.text:SetText(DUNGEONS)
        label.text:SetVertexColor(1.0, 0.82, 0.0, 1)
        self.window.body.sidebar.mpluslabel = label
      end

      if Data.db.global.dungeons.enabled then
        label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
        label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
        label:SetHeight(Constants.sizes.row)
        label:Show()
        rowCount = rowCount + 1
        totalHeight = totalHeight + Constants.sizes.row
      else
        label:Hide()
      end
    end

    do -- MythicPlus Labels
      self.window.body.sidebar.mpluslabels = self.window.body.sidebar.mpluslabels or {}
      TableForEach(self.window.body.sidebar.mpluslabels, function(f) f:Hide() end)
      if Data.db.global.dungeons.enabled then
        TableForEach(dungeons, function(dungeon, dungeonIndex)
          local dungeonFrame = self.window.body.sidebar.mpluslabels[dungeonIndex]
          if not dungeonFrame then
            dungeonFrame = CreateFrame("Button", "$parentDungeon" .. dungeonIndex, self.window.body.sidebar, "InsecureActionButtonTemplate")
            dungeonFrame:RegisterForClicks("AnyUp", "AnyDown")
            dungeonFrame:EnableMouse(true)
            dungeonFrame.icon = dungeonFrame:CreateTexture(dungeonFrame:GetName() .. "Icon", "ARTWORK")
            dungeonFrame.icon:SetSize(16, 16)
            dungeonFrame.icon:SetPoint("LEFT", dungeonFrame, "LEFT", Constants.sizes.padding, 0)
            dungeonFrame.text = dungeonFrame:CreateFontString(dungeonFrame:GetName() .. "Text", "OVERLAY")
            dungeonFrame.text:SetPoint("TOPLEFT", dungeonFrame, "TOPLEFT", 16 + Constants.sizes.padding * 2, -3)
            dungeonFrame.text:SetPoint("BOTTOMRIGHT", dungeonFrame, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
            dungeonFrame.text:SetJustifyH("LEFT")
            dungeonFrame.text:SetFontObject("GameFontHighlight_NoShadow")
            self.window.body.sidebar.mpluslabels[dungeonIndex] = dungeonFrame
          end

          local knownTeleportSpellID = TableFind(dungeon.teleports or {}, function(spellID)
            return C_SpellBook.IsSpellInSpellBook(spellID)
          end)

          if knownTeleportSpellID then
            if not InCombatLockdown() then
              dungeonFrame:SetAttribute("type", "spell")
              dungeonFrame:SetAttribute("spell", knownTeleportSpellID)
            end
          else
            -- TODO: Unset spell attribute? It's not like the dungeon pool changes during a session
          end

          dungeonFrame:SetScript("OnEnter", function()
            ---@diagnostic disable-next-line: param-type-mismatch
            GameTooltip:SetOwner(dungeonFrame, "ANCHOR_RIGHT")
            GameTooltip:SetText(dungeon.name, 1, 1, 1)
            if knownTeleportSpellID then
              GameTooltip:ClearLines()
              GameTooltip:SetSpellByID(knownTeleportSpellID)
              GameTooltip:AddLine(" ")
              GameTooltip:AddLine("<Click to Teleport>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
              _G[GameTooltip:GetName() .. "TextLeft1"]:SetText(dungeon.name)
            else
              GameTooltip:AddLine(format("Time this dungeon on level %d or above to unlock teleportation.", dungeonPortalUnlockLevel), nil, nil, nil, true)
            end
            GameTooltip:Show()
          end)
          dungeonFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
          end)

          dungeonFrame:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
          dungeonFrame:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
          dungeonFrame:SetHeight(Constants.sizes.row)
          dungeonFrame.icon:SetTexture(tostring(dungeon.texture))
          dungeonFrame.text:SetText(dungeon.short and dungeon.short or dungeon.name)
          dungeonFrame:Show()
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end
    end

    do -- Raid Header
      local label = self.window.body.sidebar.raidHeader
      if not label then
        label = CreateFrame("Frame", "$parentRaidHeader", self.window.body.sidebar)
        label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
        label.text:SetPoint("TOPLEFT", label, "TOPLEFT", Constants.sizes.padding, 0)
        label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 0)
        label.text:SetFontObject("GameFontHighlight_NoShadow")
        label.text:SetJustifyH("LEFT")
        label.text:SetText(RAIDS)
        label.text:SetVertexColor(1.0, 0.82, 0.0, 1)
        self.window.body.sidebar.raidHeader = label
      end

      if Data.db.global.raids.enabled then
        label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
        label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
        label:SetHeight(Constants.sizes.row)
        label:Show()
        rowCount = rowCount + 1
        totalHeight = totalHeight + Constants.sizes.row
      else
        label:Hide()
      end
    end

    do -- Raid Difficulties
      self.window.body.sidebar.raidDifficulties = self.window.body.sidebar.raidDifficulties or {}
      TableForEach(self.window.body.sidebar.raidDifficulties, function(f) f:Hide() end)
      if Data.db.global.raids.enabled then
        TableForEach(raidDifficulties, function(difficulty, difficultyIndex)
          local difficultyFrame = self.window.body.sidebar.raidDifficulties[difficultyIndex]
          if not difficultyFrame then
            difficultyFrame = CreateFrame("Frame", "$parentRaidDifficulty" .. difficultyIndex, self.window.body.sidebar)
            difficultyFrame.text = difficultyFrame:CreateFontString(difficultyFrame:GetName() .. "Text", "OVERLAY")
            difficultyFrame.text:SetPoint("TOPLEFT", difficultyFrame, "TOPLEFT", Constants.sizes.padding, -3)
            difficultyFrame.text:SetPoint("BOTTOMRIGHT", difficultyFrame, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
            difficultyFrame.text:SetJustifyH("LEFT")
            difficultyFrame.text:SetFontObject("GameFontHighlight_NoShadow")
            self.window.body.sidebar.raidDifficulties[difficultyIndex] = difficultyFrame
          end

          difficultyFrame:SetScript("OnEnter", function()
            GameTooltip:SetOwner(difficultyFrame, "ANCHOR_RIGHT")
            GameTooltip:SetText(difficulty.name, 1, 1, 1)
            GameTooltip:Show()
          end)
          difficultyFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
          end)

          difficultyFrame:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
          difficultyFrame:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
          difficultyFrame:SetHeight(RAIDS_ROW_HEIGHT)
          difficultyFrame.text:SetText(difficulty.short and difficulty.short or difficulty.name)
          difficultyFrame:Show()
          rowCount = rowCount + 1
          totalHeight = totalHeight + RAIDS_ROW_HEIGHT
        end)
      end
    end

    do -- Timewalking Lockouts Header
      local label = self.window.body.sidebar.timewalkingDifficulty
      if not label then
        label = CreateFrame("Frame", "$parentTimewalkingDifficulty", self.window.body.sidebar)
        label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
        label.text:SetPoint("TOPLEFT", label, "TOPLEFT", Constants.sizes.padding, -3)
        label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
        label.text:SetJustifyH("LEFT")
        label.text:SetFontObject("GameFontHighlight_NoShadow")
        label.text:SetText("Timewalking")
        self.window.body.sidebar.timewalkingDifficulty = label
      end

      local timewalkingEra = Data.db.global.raids.enabled and Data.db.global.raids.timewalkingLockouts and Data:GetActiveTimewalkingEra()
      if timewalkingEra then
        label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
        label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
        label:SetHeight(RAIDS_ROW_HEIGHT)
        label:Show()
        rowCount = rowCount + 1
        totalHeight = totalHeight + RAIDS_ROW_HEIGHT
      else
        label:Hide()
      end
    end

    do -- Currencies Header
      local label = self.window.body.sidebar.currencyLabel
      if not label then
        label = CreateFrame("Frame", "$parentCurrencyLabel", self.window.body.sidebar)
        label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
        label.text:SetPoint("TOPLEFT", label, "TOPLEFT", Constants.sizes.padding, 0)
        label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 0)
        label.text:SetFontObject("GameFontHighlight_NoShadow")
        label.text:SetJustifyH("LEFT")
        label.text:SetText("Currencies")
        label.text:SetVertexColor(1.0, 0.82, 0.0, 1)
        self.window.body.sidebar.currencyLabel = label
      end

      if Data.db.global.currencies.enabled then
        label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
        label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
        label:SetHeight(Constants.sizes.row)
        label:Show()
        rowCount = rowCount + 1
        totalHeight = totalHeight + Constants.sizes.row
      else
        label:Hide()
      end
    end

    do -- Currency Labels
      self.window.body.sidebar.currencyLabels = self.window.body.sidebar.currencyLabels or {}
      TableForEach(self.window.body.sidebar.currencyLabels, function(f) f:Hide() end)
      if Data.db.global.currencies.enabled then
        TableForEach(currencies, function(currency, currencyIndex)
          if Data.db.global.currencies.hiddenCurrencies and Data.db.global.currencies.hiddenCurrencies[currency.id] then
            return
          end
          local label = self.window.body.sidebar.currencyLabels[currencyIndex]
          if not label then
            label = CreateFrame("Frame", "$parentCurrency" .. currencyIndex, self.window.body.sidebar)
            label.icon = label:CreateTexture(label:GetName() .. "Icon", "ARTWORK")
            label.icon:SetSize(16, 16)
            label.icon:SetPoint("LEFT", label, "LEFT", Constants.sizes.padding, 0)
            label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
            label.text:SetPoint("TOPLEFT", label, "TOPLEFT", 16 + Constants.sizes.padding * 2, -3)
            label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
            label.text:SetJustifyH("LEFT")
            label.text:SetFontObject("GameFontHighlight_NoShadow")
            self.window.body.sidebar.currencyLabels[currencyIndex] = label
            label.SortUpButton = CreateFrame("Button", label:GetName() .. "SortUp", label)
            label.SortUpButton:SetSize(14, Constants.sizes.row / 2)
            label.SortUpButton:SetPoint("TOPRIGHT", label, "TOPRIGHT")
            label.SortUpButton.Icon = label.SortUpButton:CreateTexture(label.SortUpButton:GetName() .. "Icon", "ARTWORK")
            label.SortUpButton.Icon:SetAtlas("common-icon-forwardarrow", true)
            label.SortUpButton.Icon:SetRotation(math.rad(90))
            label.SortUpButton.Icon:SetDesaturation(1)
            label.SortUpButton.Icon:SetSize(8, 8)
            label.SortUpButton.Icon:SetPoint("CENTER", label.SortUpButton, "CENTER", 0, 0)
            label.SortUpButton:Hide()
            
            label.SortDownButton = CreateFrame("Button", label:GetName() .. "SortDown", label)
            label.SortDownButton:SetSize(14, Constants.sizes.row / 2)
            label.SortDownButton:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT")
            label.SortDownButton.Icon = label.SortDownButton:CreateTexture(label.SortDownButton:GetName() .. "Icon", "ARTWORK")
            label.SortDownButton.Icon:SetAtlas("common-icon-forwardarrow", true)
            label.SortDownButton.Icon:SetRotation(math.rad(-90))
            label.SortDownButton.Icon:SetDesaturation(1)
            label.SortDownButton.Icon:SetSize(8, 8)
            label.SortDownButton.Icon:SetPoint("CENTER", label.SortDownButton, "CENTER", 0, 0)
            label.SortDownButton:Hide()
          end

          local color = EPIC_PURPLE_COLOR -- match Heroic difficulty skulls

          local trackerMove = trackerMoveState[currency.id]

          label:SetScript("OnEnter", function()
            GameTooltip:SetOwner(label, "ANCHOR_RIGHT")
            GameTooltip:SetText(currency.name, color.r, color.g, color.b)
            if currency.description then
              GameTooltip:AddLine(currency.description, nil, nil, nil, true)
            end
            if currency.tooltipNote then
              GameTooltip:AddLine(" ")
              GameTooltip:AddLine(format("%s %s", RARE_BLUE_COLOR:WrapTextInColorCode(addon.name .. ":"), currency.tooltipNote), 1, 1, 1, true)
            end
            GameTooltip:Show()
            label.SortUpButton:Hide()
            label.SortDownButton:Hide()
            if not InCombatLockdown() then
              label.SortUpButton:SetPropagateMouseMotion(true)
              label.SortDownButton:SetPropagateMouseMotion(true)
              if trackerMove and trackerMove.canMoveUp then label.SortUpButton:Show() end
              if trackerMove and trackerMove.canMoveDown then label.SortDownButton:Show() end
            end
          end)
          label:SetScript("OnLeave", function()
            GameTooltip:Hide()
            label.SortUpButton:Hide()
            label.SortDownButton:Hide()
          end)

          label.SortUpButton:SetScript("OnEnter", function()
            label.SortUpButton.Icon:SetDesaturation(0)
            GameTooltip:SetOwner(label.SortUpButton, "ANCHOR_RIGHT")
            GameTooltip:SetText("Custom Order", 1, 1, 1, 1, true)
            GameTooltip:AddLine("Move this tracker up.")
            GameTooltip:AddLine("At the top of a section, it moves into the section above.", nil, nil, nil, true)
            GameTooltip:Show()
          end)
          label.SortUpButton:SetScript("OnLeave", function()
            label.SortUpButton.Icon:SetDesaturation(1)
            GameTooltip:Hide()
          end)
          label.SortUpButton:SetScript("OnClick", function()
            Data:SortTracker(currency, -1)
            self:Render()
          end)

          label.SortDownButton:SetScript("OnEnter", function()
            label.SortDownButton.Icon:SetDesaturation(0)
            GameTooltip:SetOwner(label.SortDownButton, "ANCHOR_RIGHT")
            GameTooltip:SetText("Custom Order", 1, 1, 1, 1, true)
            GameTooltip:AddLine("Move this tracker down.")
            GameTooltip:AddLine("At the bottom of a section, it moves into the section below.", nil, nil, nil, true)
            GameTooltip:Show()
          end)
          label.SortDownButton:SetScript("OnLeave", function()
            label.SortDownButton.Icon:SetDesaturation(1)
            GameTooltip:Hide()
          end)
          label.SortDownButton:SetScript("OnClick", function()
            Data:SortTracker(currency, 1)
            self:Render()
          end)

          label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
          label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
          label:SetHeight(Constants.sizes.row)
          label.icon:SetTexture(currency.iconFileID or [[Interface\Icons\INV_Misc_QuestionMark]])
          label.text:SetText(currency.short and currency.short or currency.name)
          label.text:SetTextColor(color.r, color.g, color.b)
          label:Show()
          RegisterRowHighlightFrame(label, totalHeight, Constants.sizes.row)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end
    end

    do -- Weeklies Header
      local label = self.window.body.sidebar.weekliesLabel
      if not label then
        label = CreateFrame("Frame", "$parentWeekliesLabel", self.window.body.sidebar)
        label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
        label.text:SetPoint("TOPLEFT", label, "TOPLEFT", Constants.sizes.padding, 0)
        label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 0)
        label.text:SetFontObject("GameFontHighlight_NoShadow")
        label.text:SetJustifyH("LEFT")
        label.text:SetText("Weeklies")
        label.text:SetVertexColor(1.0, 0.82, 0.0, 1)
        self.window.body.sidebar.weekliesLabel = label
      end

      if Data.db.global.weeklies.enabled then
        label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
        label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
        label:SetHeight(Constants.sizes.row)
        label:Show()
        rowCount = rowCount + 1
        totalHeight = totalHeight + Constants.sizes.row
      else
        label:Hide()
      end
    end

    do -- Weeklies Labels
      self.window.body.sidebar.weeklyLabels = self.window.body.sidebar.weeklyLabels or {}
      TableForEach(self.window.body.sidebar.weeklyLabels, function(f) f:Hide() end)
      if Data.db.global.weeklies.enabled then
        TableForEach(weeklies, function(currency, currencyIndex)
          if Data.db.global.weeklies.hiddenCurrencies and Data.db.global.weeklies.hiddenCurrencies[currency.id] then
            return
          end
          local label = self.window.body.sidebar.weeklyLabels[currencyIndex]
          if not label then
            label = CreateFrame("Frame", "$parentWeekly" .. currencyIndex, self.window.body.sidebar)
            label.icon = label:CreateTexture(label:GetName() .. "Icon", "ARTWORK")
            label.icon:SetSize(16, 16)
            label.icon:SetPoint("LEFT", label, "LEFT", Constants.sizes.padding, 0)
            label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
            label.text:SetPoint("TOPLEFT", label, "TOPLEFT", 16 + Constants.sizes.padding * 2, -3)
            label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
            label.text:SetJustifyH("LEFT")
            label.text:SetFontObject("GameFontHighlight_NoShadow")
            self.window.body.sidebar.weeklyLabels[currencyIndex] = label
            label.SortUpButton = CreateFrame("Button", label:GetName() .. "SortUp", label)
            label.SortUpButton:SetSize(14, Constants.sizes.row / 2)
            label.SortUpButton:SetPoint("TOPRIGHT", label, "TOPRIGHT")
            label.SortUpButton.Icon = label.SortUpButton:CreateTexture(label.SortUpButton:GetName() .. "Icon", "ARTWORK")
            label.SortUpButton.Icon:SetAtlas("common-icon-forwardarrow", true)
            label.SortUpButton.Icon:SetRotation(math.rad(90))
            label.SortUpButton.Icon:SetDesaturation(1)
            label.SortUpButton.Icon:SetSize(8, 8)
            label.SortUpButton.Icon:SetPoint("CENTER", label.SortUpButton, "CENTER", 0, 0)
            label.SortUpButton:Hide()
            
            label.SortDownButton = CreateFrame("Button", label:GetName() .. "SortDown", label)
            label.SortDownButton:SetSize(14, Constants.sizes.row / 2)
            label.SortDownButton:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT")
            label.SortDownButton.Icon = label.SortDownButton:CreateTexture(label.SortDownButton:GetName() .. "Icon", "ARTWORK")
            label.SortDownButton.Icon:SetAtlas("common-icon-forwardarrow", true)
            label.SortDownButton.Icon:SetRotation(math.rad(-90))
            label.SortDownButton.Icon:SetDesaturation(1)
            label.SortDownButton.Icon:SetSize(8, 8)
            label.SortDownButton.Icon:SetPoint("CENTER", label.SortDownButton, "CENTER", 0, 0)
            label.SortDownButton:Hide()
          end

          local color = RARE_BLUE_COLOR -- match Normal difficulty skulls

          local trackerMove = trackerMoveState[currency.id]

          label:SetScript("OnEnter", function()
            GameTooltip:SetOwner(label, "ANCHOR_RIGHT")
            GameTooltip:SetText(currency.name, color.r, color.g, color.b)
            if currency.description then
              GameTooltip:AddLine(currency.description, nil, nil, nil, true)
            end
            if currency.tooltipNote then
              GameTooltip:AddLine(" ")
              GameTooltip:AddLine(format("%s %s", RARE_BLUE_COLOR:WrapTextInColorCode(addon.name .. ":"), currency.tooltipNote), 1, 1, 1, true)
            end
            GameTooltip:Show()
            label.SortUpButton:Hide()
            label.SortDownButton:Hide()
            if not InCombatLockdown() then
              label.SortUpButton:SetPropagateMouseMotion(true)
              label.SortDownButton:SetPropagateMouseMotion(true)
              if trackerMove and trackerMove.canMoveUp then label.SortUpButton:Show() end
              if trackerMove and trackerMove.canMoveDown then label.SortDownButton:Show() end
            end
          end)
          label:SetScript("OnLeave", function()
            GameTooltip:Hide()
            label.SortUpButton:Hide()
            label.SortDownButton:Hide()
          end)

          label.SortUpButton:SetScript("OnEnter", function()
            label.SortUpButton.Icon:SetDesaturation(0)
            GameTooltip:SetOwner(label.SortUpButton, "ANCHOR_RIGHT")
            GameTooltip:SetText("Custom Order", 1, 1, 1, 1, true)
            GameTooltip:AddLine("Move this tracker up.")
            GameTooltip:AddLine("At the top of a section, it moves into the section above.", nil, nil, nil, true)
            GameTooltip:Show()
          end)
          label.SortUpButton:SetScript("OnLeave", function()
            label.SortUpButton.Icon:SetDesaturation(1)
            GameTooltip:Hide()
          end)
          label.SortUpButton:SetScript("OnClick", function()
            Data:SortTracker(currency, -1)
            self:Render()
          end)

          label.SortDownButton:SetScript("OnEnter", function()
            label.SortDownButton.Icon:SetDesaturation(0)
            GameTooltip:SetOwner(label.SortDownButton, "ANCHOR_RIGHT")
            GameTooltip:SetText("Custom Order", 1, 1, 1, 1, true)
            GameTooltip:AddLine("Move this tracker down.")
            GameTooltip:AddLine("At the bottom of a section, it moves into the section below.", nil, nil, nil, true)
            GameTooltip:Show()
          end)
          label.SortDownButton:SetScript("OnLeave", function()
            label.SortDownButton.Icon:SetDesaturation(1)
            GameTooltip:Hide()
          end)
          label.SortDownButton:SetScript("OnClick", function()
            Data:SortTracker(currency, 1)
            self:Render()
          end)

          label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
          label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
          label:SetHeight(Constants.sizes.row)
          label.icon:SetTexture(currency.iconFileID or [[Interface\Icons\INV_Misc_QuestionMark]])
          label.text:SetText(currency.short and currency.short or currency.name)
          label.text:SetTextColor(color.r, color.g, color.b)
          label:Show()
          RegisterRowHighlightFrame(label, totalHeight, Constants.sizes.row)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end
    end

    do -- Seasonal Chores Header
      local label = self.window.body.sidebar.seasonalChoresLabel
      if not label then
        label = CreateFrame("Frame", "$parentSeasonalChoresLabel", self.window.body.sidebar)
        label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
        label.text:SetPoint("TOPLEFT", label, "TOPLEFT", Constants.sizes.padding, 0)
        label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 0)
        label.text:SetFontObject("GameFontHighlight_NoShadow")
        label.text:SetJustifyH("LEFT")
        label.text:SetText("Seasonal Chores")
        label.text:SetVertexColor(1.0, 0.82, 0.0, 1)
        self.window.body.sidebar.seasonalChoresLabel = label
      end

      if Data.db.global.seasonalChores.enabled then
        label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
        label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
        label:SetHeight(Constants.sizes.row)
        label:Show()
        rowCount = rowCount + 1
        totalHeight = totalHeight + Constants.sizes.row
      else
        label:Hide()
      end
    end

    do -- Seasonal Chores Labels
      self.window.body.sidebar.seasonalChoreLabels = self.window.body.sidebar.seasonalChoreLabels or {}
      TableForEach(self.window.body.sidebar.seasonalChoreLabels, function(f) f:Hide() end)
      if Data.db.global.seasonalChores.enabled then
        TableForEach(seasonalChores, function(currency, currencyIndex)
          if Data.db.global.seasonalChores.hiddenCurrencies and Data.db.global.seasonalChores.hiddenCurrencies[currency.id] then
            return
          end
          local label = self.window.body.sidebar.seasonalChoreLabels[currencyIndex]
          if not label then
            label = CreateFrame("Frame", "$parentSeasonalChore" .. currencyIndex, self.window.body.sidebar)
            label.icon = label:CreateTexture(label:GetName() .. "Icon", "ARTWORK")
            label.icon:SetSize(16, 16)
            label.icon:SetPoint("LEFT", label, "LEFT", Constants.sizes.padding, 0)
            label.text = label:CreateFontString(label:GetName() .. "Text", "OVERLAY")
            label.text:SetPoint("TOPLEFT", label, "TOPLEFT", 16 + Constants.sizes.padding * 2, -3)
            label.text:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
            label.text:SetJustifyH("LEFT")
            label.text:SetFontObject("GameFontHighlight_NoShadow")
            self.window.body.sidebar.seasonalChoreLabels[currencyIndex] = label
            label.SortUpButton = CreateFrame("Button", label:GetName() .. "SortUp", label)
            label.SortUpButton:SetSize(14, Constants.sizes.row / 2)
            label.SortUpButton:SetPoint("TOPRIGHT", label, "TOPRIGHT")
            label.SortUpButton.Icon = label.SortUpButton:CreateTexture(label.SortUpButton:GetName() .. "Icon", "ARTWORK")
            label.SortUpButton.Icon:SetAtlas("common-icon-forwardarrow", true)
            label.SortUpButton.Icon:SetRotation(math.rad(90))
            label.SortUpButton.Icon:SetDesaturation(1)
            label.SortUpButton.Icon:SetSize(8, 8)
            label.SortUpButton.Icon:SetPoint("CENTER", label.SortUpButton, "CENTER", 0, 0)
            label.SortUpButton:Hide()
            
            label.SortDownButton = CreateFrame("Button", label:GetName() .. "SortDown", label)
            label.SortDownButton:SetSize(14, Constants.sizes.row / 2)
            label.SortDownButton:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT")
            label.SortDownButton.Icon = label.SortDownButton:CreateTexture(label.SortDownButton:GetName() .. "Icon", "ARTWORK")
            label.SortDownButton.Icon:SetAtlas("common-icon-forwardarrow", true)
            label.SortDownButton.Icon:SetRotation(math.rad(-90))
            label.SortDownButton.Icon:SetDesaturation(1)
            label.SortDownButton.Icon:SetSize(8, 8)
            label.SortDownButton.Icon:SetPoint("CENTER", label.SortDownButton, "CENTER", 0, 0)
            label.SortDownButton:Hide()
          end

          local color = LEGENDARY_ORANGE_COLOR -- match Mythic difficulty skulls

          local trackerMove = trackerMoveState[currency.id]

          label:SetScript("OnEnter", function()
            GameTooltip:SetOwner(label, "ANCHOR_RIGHT")
            GameTooltip:SetText(currency.name, color.r, color.g, color.b)
            if currency.description then
              GameTooltip:AddLine(currency.description, nil, nil, nil, true)
            end
            if currency.tooltipNote then
              GameTooltip:AddLine(" ")
              GameTooltip:AddLine(format("%s %s", RARE_BLUE_COLOR:WrapTextInColorCode(addon.name .. ":"), currency.tooltipNote), 1, 1, 1, true)
            end
            GameTooltip:Show()
            label.SortUpButton:Hide()
            label.SortDownButton:Hide()
            if not InCombatLockdown() then
              label.SortUpButton:SetPropagateMouseMotion(true)
              label.SortDownButton:SetPropagateMouseMotion(true)
              if trackerMove and trackerMove.canMoveUp then label.SortUpButton:Show() end
              if trackerMove and trackerMove.canMoveDown then label.SortDownButton:Show() end
            end
          end)
          label:SetScript("OnLeave", function()
            GameTooltip:Hide()
            label.SortUpButton:Hide()
            label.SortDownButton:Hide()
          end)

          label.SortUpButton:SetScript("OnEnter", function()
            label.SortUpButton.Icon:SetDesaturation(0)
            GameTooltip:SetOwner(label.SortUpButton, "ANCHOR_RIGHT")
            GameTooltip:SetText("Custom Order", 1, 1, 1, 1, true)
            GameTooltip:AddLine("Move this tracker up.")
            GameTooltip:AddLine("At the top of a section, it moves into the section above.", nil, nil, nil, true)
            GameTooltip:Show()
          end)
          label.SortUpButton:SetScript("OnLeave", function()
            label.SortUpButton.Icon:SetDesaturation(1)
            GameTooltip:Hide()
          end)
          label.SortUpButton:SetScript("OnClick", function()
            Data:SortTracker(currency, -1)
            self:Render()
          end)

          label.SortDownButton:SetScript("OnEnter", function()
            label.SortDownButton.Icon:SetDesaturation(0)
            GameTooltip:SetOwner(label.SortDownButton, "ANCHOR_RIGHT")
            GameTooltip:SetText("Custom Order", 1, 1, 1, 1, true)
            GameTooltip:AddLine("Move this tracker down.")
            GameTooltip:AddLine("At the bottom of a section, it moves into the section below.", nil, nil, nil, true)
            GameTooltip:Show()
          end)
          label.SortDownButton:SetScript("OnLeave", function()
            label.SortDownButton.Icon:SetDesaturation(1)
            GameTooltip:Hide()
          end)
          label.SortDownButton:SetScript("OnClick", function()
            Data:SortTracker(currency, 1)
            self:Render()
          end)

          label:SetPoint("TOPLEFT", self.window.body.sidebar, "TOPLEFT", 0, -totalHeight)
          label:SetPoint("TOPRIGHT", self.window.body.sidebar, "TOPRIGHT", 0, -totalHeight)
          label:SetHeight(Constants.sizes.row)
          label.icon:SetTexture(currency.iconFileID or [[Interface\Icons\INV_Misc_QuestionMark]])
          label.text:SetText(currency.short and currency.short or currency.name)
          label.text:SetTextColor(color.r, color.g, color.b)
          label:Show()
          RegisterRowHighlightFrame(label, totalHeight, Constants.sizes.row)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end
    end

    windowHeight = windowHeight + totalHeight
  end

  do -- Character Columns
    self.window.characterFrames = self.window.characterFrames or {}
    TableForEach(self.window.characterFrames, function(f) f:Hide() end)
    TableForEach(characters, function(character, characterIndex)
      local rowCount = 0
      local totalHeight = 0
      local characterFrame = self.window.characterFrames[characterIndex]
      if not characterFrame then
        characterFrame = CreateFrame("Frame", "$parentCharacterColumn" .. characterIndex, scrollContent)
        characterFrame.infoFrames = {}
        characterFrame.dungeonFrames = {}
        characterFrame.raidFrames = {}
        characterFrame.affixHeaderFrame = CreateFrame("Frame", "$parentAffixes", characterFrame)
        characterFrame.preyHeader = CreateFrame("Frame", "$parentPreyHeader", characterFrame)
        characterFrame.raidHeader = CreateFrame("Frame", "$parentRaidHeader", characterFrame)
        characterFrame.currencyHeaderFrame = CreateFrame("Frame", "$parentCurrencies", characterFrame)
        characterFrame.weekliesHeaderFrame = CreateFrame("Frame", "$parentWeeklies", characterFrame)
        characterFrame.seasonalChoresHeaderFrame = CreateFrame("Frame", "$parentSeasonalChores", characterFrame)
        self.window.characterFrames[characterIndex] = characterFrame
      end

      characterFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", (characterIndex - 1) * CHARACTER_WIDTH, 0)
      characterFrame:SetPoint("BOTTOMLEFT", scrollContent, "BOTTOMLEFT", (characterIndex - 1) * CHARACTER_WIDTH, 0)
      characterFrame:SetWidth(CHARACTER_WIDTH)
      SetBackgroundColor(characterFrame, 1, 1, 1, characterIndex % 2 == 0 and 0.01 or 0)
      characterFrame:Show()

      do -- Current character overlay
        local overlay = characterFrame.currentCharacterOverlay
        if not overlay then
          overlay = CreateFrame("Frame", "$parentCurrentCharacterOverlay", characterFrame)
          overlay:SetAllPoints()
          overlay:EnableMouse(false)
          overlay.background = overlay:CreateTexture(nil, "BACKGROUND")
          overlay.background:SetAllPoints()
          overlay.left = overlay:CreateTexture(nil, "ARTWORK")
          overlay.left:SetWidth(2)
          overlay.left:SetPoint("TOPLEFT")
          overlay.left:SetPoint("BOTTOMLEFT")
          overlay.right = overlay:CreateTexture(nil, "ARTWORK")
          overlay.right:SetWidth(2)
          overlay.right:SetPoint("TOPRIGHT")
          overlay.right:SetPoint("BOTTOMRIGHT")
          characterFrame.currentCharacterOverlay = overlay
        end
        local color = Data.db.global.currentCharacterMarkerColor or DIM_GREEN_FONT_COLOR
        overlay.background:SetColorTexture(color.r, color.g, color.b, 0.04)
        overlay.left:SetColorTexture(color.r, color.g, color.b, 0.15)
        overlay.right:SetColorTexture(color.r, color.g, color.b, 0.15)
        overlay:SetFrameLevel(characterFrame:GetFrameLevel() + 50)
        if character.GUID == UnitGUID("player") and Data.db.global.currentCharacterMarker == "border" then
          overlay:Show()
        else
          overlay:Hide()
        end
      end

      do -- Info
        TableForEach(characterFrame.infoFrames, function(f) f:Hide() end)
        TableForEach(characterInfo, function(info, infoIndex)
          local infoFrame = characterFrame.infoFrames[infoIndex]
          if not infoFrame then
            infoFrame = CreateFrame("Button", "$parentInfo" .. infoIndex, characterFrame)
            infoFrame.text = infoFrame:CreateFontString(infoFrame:GetName() .. "Text", "OVERLAY")
            infoFrame.text:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", Constants.sizes.padding * 1.5, -Constants.sizes.padding)
            infoFrame.text:SetPoint("BOTTOMRIGHT", infoFrame, "BOTTOMRIGHT", -Constants.sizes.padding * 1.5, Constants.sizes.padding)
            infoFrame.text:SetJustifyH("CENTER")
            infoFrame.text:SetFontObject("GameFontHighlight_NoShadow")
            characterFrame.infoFrames[infoIndex] = infoFrame
          end

          if infoIndex == 1 then
            if not infoFrame.SortLeftButton then
              infoFrame.SortLeftButton = CreateFrame("Button", infoFrame:GetName() .. "SortLeft", infoFrame)
              infoFrame.SortLeftButton:SetSize(Constants.sizes.row, Constants.sizes.row)
              infoFrame.SortLeftButton:SetPoint("LEFT", infoFrame, "LEFT")
              infoFrame.SortLeftButton.Icon = infoFrame.SortLeftButton:CreateTexture(infoFrame.SortLeftButton:GetName() .. "Icon", "ARTWORK")
              infoFrame.SortLeftButton.Icon:SetAtlas("common-icon-backarrow", true)
              infoFrame.SortLeftButton.Icon:SetDesaturation(1)
              infoFrame.SortLeftButton.Icon:SetSize(12, 12)
              infoFrame.SortLeftButton.Icon:SetPoint("CENTER", infoFrame.SortLeftButton, "CENTER", 0, 0)
              infoFrame.SortLeftButton:Hide()
            end
            infoFrame.SortLeftButton:SetScript("OnEnter", function()
              if info.onLeave then
                info.onLeave(infoFrame, character)
              end
              infoFrame.SortLeftButton.Icon:SetDesaturation(0)
              GameTooltip:SetOwner(infoFrame.SortLeftButton, "ANCHOR_RIGHT")
              GameTooltip:SetText("Custom Order", 1, 1, 1, 1, true)
              GameTooltip:AddLine("Move your character around.")
              GameTooltip:AddLine(" ")
              GameTooltip:AddLine("<Click to Move Left>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
              GameTooltip:Show()
            end)
            infoFrame.SortLeftButton:SetScript("OnLeave", function()
              infoFrame.SortLeftButton.Icon:SetDesaturation(1)
              GameTooltip:Hide()
              if info.onEnter then
                info.onEnter(infoFrame, character)
              end
            end)
            infoFrame.SortLeftButton:SetScript("OnClick", function()
              Data:SortCharacter(character, -1)
              self:Render()
            end)
            if not infoFrame.SortRightButton then
              infoFrame.SortRightButton = CreateFrame("Button", infoFrame:GetName() .. "SortRight", infoFrame)
              infoFrame.SortRightButton:SetSize(Constants.sizes.row, Constants.sizes.row)
              infoFrame.SortRightButton:SetPoint("RIGHT", infoFrame, "RIGHT")
              infoFrame.SortRightButton.Icon = infoFrame.SortRightButton:CreateTexture(infoFrame.SortRightButton:GetName() .. "Icon", "ARTWORK")
              infoFrame.SortRightButton.Icon:SetAtlas("common-icon-forwardarrow", true)
              infoFrame.SortRightButton.Icon:SetDesaturation(1)
              infoFrame.SortRightButton.Icon:SetSize(12, 12)
              infoFrame.SortRightButton.Icon:SetPoint("CENTER", infoFrame.SortRightButton, "CENTER", 0, 0)
              infoFrame.SortRightButton:Hide()
            end
            infoFrame.SortRightButton:SetScript("OnEnter", function()
              if info.onLeave then
                info.onLeave(infoFrame, character)
              end
              infoFrame.SortRightButton.Icon:SetDesaturation(0)
              GameTooltip:SetOwner(infoFrame.SortRightButton, "ANCHOR_RIGHT")
              GameTooltip:SetText("Custom Order", 1, 1, 1, 1, true)
              GameTooltip:AddLine("Move your character around.")
              GameTooltip:AddLine(" ")
              GameTooltip:AddLine("<Click to Move Right>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
              GameTooltip:Show()
            end)
            infoFrame.SortRightButton:SetScript("OnLeave", function()
              infoFrame.SortRightButton.Icon:SetDesaturation(1)
              GameTooltip:Hide()
              if info.onEnter then
                info.onEnter(infoFrame, character)
              end
            end)
            infoFrame.SortRightButton:SetScript("OnClick", function()
              Data:SortCharacter(character, 1)
              self:Render()
            end)

            if not InCombatLockdown() then
              infoFrame.SortLeftButton:SetPropagateMouseMotion(true)
              infoFrame.SortRightButton:SetPropagateMouseMotion(true)
            end
          end

          if info.value then
            infoFrame.text:SetText(info.value(character, characterIndex))
          end

          if info.backgroundColor then
            SetBackgroundColor(infoFrame, info.backgroundColor.r, info.backgroundColor.g, info.backgroundColor.b, info.backgroundColor.a)
          else
            SetBackgroundColor(infoFrame, 0, 0, 0, 0)
          end

          infoFrame:SetScript("OnEnter", function()
            if info.onEnter then
              info.onEnter(infoFrame, character)
            end

            if infoIndex == 1 then
              infoFrame.SortLeftButton:Hide()
              infoFrame.SortRightButton:Hide()
              if Data.db.global.sorting == "custom" and not InCombatLockdown() then
                infoFrame.SortLeftButton:SetPropagateMouseMotion(true)
                infoFrame.SortRightButton:SetPropagateMouseMotion(true)
                if characterIndex > 1 then infoFrame.SortLeftButton:Show() end
                if characterIndex < numCharacters then infoFrame.SortRightButton:Show() end
              end
            end

            if not info.backgroundColor then
              SetHighlightColor(infoFrame)
            end
          end)

          infoFrame:SetScript("OnLeave", function()
            if info.onLeave then
              info.onLeave(infoFrame, character)
            end

            if infoIndex == 1 then
              infoFrame.SortLeftButton:Hide()
              infoFrame.SortRightButton:Hide()
            end

            if not info.backgroundColor then
              SetHighlightColor(infoFrame, 1, 1, 1, 0)
            end
          end)

          infoFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
          infoFrame:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
              if info.onRightClick then
                info.onRightClick(infoFrame, character)
              end
            elseif info.onClick then
              info.onClick(infoFrame, character)
            end
          end)

          infoFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          infoFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          infoFrame:SetHeight(Constants.sizes.row)
          infoFrame:Show()
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end

      do -- Prey Header
        if Data.db.global.prey.enabled then
          characterFrame.preyHeader:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          characterFrame.preyHeader:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          characterFrame.preyHeader:SetHeight(Constants.sizes.row)
          characterFrame.preyHeader:Show()
          SetBackgroundColor(characterFrame.preyHeader, 0, 0, 0, 0.3)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        else
          characterFrame.preyHeader:Hide()
        end
      end

      do -- Prey Progress
        characterFrame.preyProgress = characterFrame.preyProgress or {}
        TableForEach(characterFrame.preyProgress, function(f) f:Hide() end)
        TableForEach(Data:GetPreyDifficulties(), function(difficulty, difficultyIndex)
          if not Data.db.global.prey.enabled then return end
          local difficultyFrame = characterFrame.preyProgress[difficultyIndex]
          if not difficultyFrame then
            difficultyFrame = CreateFrame("Frame", "$parentPreyProgress" .. difficultyIndex, characterFrame)
            difficultyFrame.Text = difficultyFrame:CreateFontString(difficultyFrame:GetName() .. "Text", "OVERLAY")
            difficultyFrame.Text:SetPoint("TOPLEFT", difficultyFrame, "TOPLEFT", Constants.sizes.padding * 1.5, -Constants.sizes.padding)
            difficultyFrame.Text:SetPoint("BOTTOMRIGHT", difficultyFrame, "BOTTOMRIGHT", -Constants.sizes.padding * 1.5, Constants.sizes.padding)
            difficultyFrame.Text:SetFontObject("GameFontHighlight_NoShadow")
            difficultyFrame.Text:SetJustifyH("CENTER")
            characterFrame.preyProgress[difficultyIndex] = difficultyFrame
          end

          local textValue = "-"
          local textColor = LIGHTGRAY_FONT_COLOR
          local numQuestsCompleted = 0
          local characterQuestsCompleted = character.prey and character.prey.questsCompleted or {}

          local quests = TableFilter(Data.preyQuests, function(quest)
            return quest.difficultyID == difficulty.id
          end)
          local questsCompleted = TableFilter(quests, function(quest)
            return characterQuestsCompleted[quest.questID]
          end)
          numQuestsCompleted = TableCount(questsCompleted)

          if numQuestsCompleted >= preyWeeklyHuntCap then
            textValue = format("%d / %d", numQuestsCompleted, preyWeeklyHuntCap)
            textColor = GREEN_FONT_COLOR
          elseif numQuestsCompleted > 0 then
            textValue = format("%d / %d", numQuestsCompleted, preyWeeklyHuntCap)
            textColor = WHITE_FONT_COLOR
          end

          difficultyFrame:SetScript("OnEnter", function()
            GameTooltip:SetOwner(difficultyFrame, "ANCHOR_RIGHT")
            GameTooltip:SetText("Prey Hunt Progress", 1, 1, 1)
            GameTooltip:AddDoubleLine("Difficulty:", difficulty.name, nil, nil, nil, 1, 1, 1)
            if character.prey == nil or character.prey.questsCompleted == nil then
              GameTooltip:AddLine(" ")
              GameTooltip:AddLine("No Data")
              GameTooltip:AddLine("Log your character to update.", 1, 1, 1, true)
            else
              GameTooltip:AddDoubleLine("Hunts Completed:", format("%d / %d", numQuestsCompleted, preyWeeklyHuntCap), nil, nil, nil, textColor.r, textColor.g, textColor.b)
            end
            if numQuestsCompleted > 0 then
              GameTooltip:AddLine(" ")
              GameTooltip:AddLine("Quests Done:")
              TableForEach(questsCompleted, function(quest)
                GameTooltip:AddLine(quest.name, 1, 1, 1)
              end)
            end
            GameTooltip:Show()
            SetHighlightColor(difficultyFrame, 1, 1, 1, 0.05)
          end)
          difficultyFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
            SetHighlightColor(difficultyFrame, 1, 1, 1, 0)
          end)

          difficultyFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          difficultyFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          difficultyFrame:SetHeight(Constants.sizes.row)
          difficultyFrame:Show()
          difficultyFrame.Text:SetText(textValue)
          difficultyFrame.Text:SetTextColor(textColor.r, textColor.g, textColor.b)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end

      do -- Dungeon Header
        if Data.db.global.dungeons.enabled then
          characterFrame.affixHeaderFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          characterFrame.affixHeaderFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          characterFrame.affixHeaderFrame:SetHeight(Constants.sizes.row)
          characterFrame.affixHeaderFrame:Show()
          SetBackgroundColor(characterFrame.affixHeaderFrame, 0, 0, 0, 0.3)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        else
          characterFrame.affixHeaderFrame:Hide()
        end
      end

      do -- Dungeons
        characterFrame.dungeonFrames = characterFrame.dungeonFrames or {}
        TableForEach(characterFrame.dungeonFrames, function(f) f:Hide() end)
        TableForEach(dungeons, function(dungeon, dungeonIndex)
          if not Data.db.global.dungeons.enabled then return end
          local dungeonFrame = characterFrame.dungeonFrames[dungeonIndex]
          if not dungeonFrame then
            dungeonFrame = CreateFrame("Frame", "$parentDungeons" .. dungeonIndex, characterFrame)
            dungeonFrame.Text = dungeonFrame:CreateFontString(dungeonFrame:GetName() .. "Text", "OVERLAY")
            dungeonFrame.Text:SetFontObject("GameFontHighlight_NoShadow")
            dungeonFrame.Tier = dungeonFrame:CreateFontString(dungeonFrame:GetName() .. "Tier", "OVERLAY")
            dungeonFrame.Tier:SetPoint("LEFT", dungeonFrame.Text, "RIGHT", 3, 1)
            dungeonFrame.Tier:SetJustifyH("LEFT")
            dungeonFrame.Tier:SetFontObject("GameFontHighlight_NoShadow")
            dungeonFrame.Score = dungeonFrame:CreateFontString(dungeonFrame:GetName() .. "Score", "OVERLAY")
            dungeonFrame.Score:SetPoint("RIGHT", dungeonFrame, "RIGHT", -Constants.sizes.padding * 2, 1)
            dungeonFrame.Score:SetJustifyH("RIGHT")
            dungeonFrame.Score:SetFontObject("GameFontHighlight_NoShadow")
            characterFrame.dungeonFrames[dungeonIndex] = dungeonFrame
          end

          local affixScores
          local overallScore
          local inTimeInfo
          local overTimeInfo
          local bestAffixScore
          local level = "-"
          local color = HIGHLIGHT_FONT_COLOR
          local tier = ""
          local dungeonLevel = 0

          local characterDungeon = TableGet(character.mythicplus.dungeons or {}, "challengeModeID", dungeon.challengeModeID)
          if characterDungeon then
            affixScores = characterDungeon.affixScores
            overallScore = characterDungeon.bestOverAllScore
            inTimeInfo = characterDungeon.bestTimedRun
            overTimeInfo = characterDungeon.bestNotTimedRun

            if overallScore and Data.db.global.showAffixColors then
              local rarityColor = C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor(overallScore)
              if rarityColor ~= nil then
                color = CreateColor(rarityColor.r, rarityColor.g, rarityColor.b, rarityColor.a)
              end
            end

            if affixScores then
              ---@type AE_CharacterAffixScoreInfo
              bestAffixScore = TableUtil.FindMax(affixScores, function(affixScore)
                return affixScore.score
              end)

              if bestAffixScore then
                level = tostring(bestAffixScore.level)
                dungeonLevel = bestAffixScore.level or 0

                if bestAffixScore.durationSec <= Helpers:calculateDungeonTimer(dungeon.time, bestAffixScore.level, 3, seasonID) then
                  tier = "|A:Professions-ChatIcon-Quality-Tier3:16:16:0:0|a"
                elseif bestAffixScore.durationSec <= Helpers:calculateDungeonTimer(dungeon.time, bestAffixScore.level, 2, seasonID) then
                  tier = "|A:Professions-ChatIcon-Quality-Tier2:16:16:0:0|a"
                elseif bestAffixScore.durationSec <= Helpers:calculateDungeonTimer(dungeon.time, bestAffixScore.level, 1, seasonID) then
                  tier = "|A:Professions-ChatIcon-Quality-Tier1:14:14:0:0|a"
                end

                if bestAffixScore.overTime then
                  color = LIGHTGRAY_FONT_COLOR
                end
              end
            end
          end

          if level ~= "-" and Data.db.global.showTiers then
            level = format("%s %s", level, tier)
          end

          dungeonFrame.Text:ClearAllPoints()
          dungeonFrame.Text:SetText(color:WrapTextInColorCode(level))
          dungeonFrame.Text:SetPoint("LEFT", dungeonFrame, "LEFT")
          dungeonFrame.Text:SetPoint("RIGHT", dungeonFrame, "CENTER", 0, 0)
          dungeonFrame.Text:SetJustifyH("CENTER")
          dungeonFrame.Tier:ClearAllPoints()
          dungeonFrame.Tier:SetText("")
          dungeonFrame.Score:ClearAllPoints()
          dungeonFrame.Score:SetText(color:WrapTextInColorCode(overallScore and tostring(overallScore) or "-"))
          dungeonFrame.Score:SetPoint("LEFT", dungeonFrame, "CENTER")
          dungeonFrame.Score:SetPoint("RIGHT", dungeonFrame, "RIGHT")
          dungeonFrame.Score:SetJustifyH("CENTER")

          if not Data.db.global.showScores then
            dungeonFrame.Text:ClearAllPoints()
            dungeonFrame.Text:SetPoint("CENTER", dungeonFrame, "CENTER")
            dungeonFrame.Score:SetText("")
          else
            if not Data.db.global.showTiers then
              dungeonFrame.Text:SetPoint("RIGHT", dungeonFrame, "CENTER", 0, 0)
              dungeonFrame.Text:SetJustifyH("CENTER")
            end
          end

          if level == "-" then
            dungeonFrame.Text:ClearAllPoints()
            dungeonFrame.Text:SetPoint("CENTER", dungeonFrame, "CENTER")
            dungeonFrame.Tier:SetText("")
            dungeonFrame.Score:SetText("")
          end

          dungeonFrame:SetScript("OnEnter", function()
            GameTooltip:SetOwner(dungeonFrame, "ANCHOR_RIGHT")
            GameTooltip:SetText(dungeon.name, 1, 1, 1)

            if affixScores and TableCount(affixScores) > 0 then
              if overallScore and (inTimeInfo or overTimeInfo) then
                GameTooltip_AddNormalLine(GameTooltip, DUNGEON_SCORE_TOTAL_SCORE:format(color:WrapTextInColorCode(tostring(overallScore))), GREEN_FONT_COLOR)
              end

              if bestAffixScore then
                GameTooltip_AddBlankLineToTooltip(GameTooltip)
                GameTooltip_AddNormalLine(GameTooltip, LFG_LIST_BEST_RUN)
                GameTooltip_AddColoredLine(GameTooltip, MYTHIC_PLUS_POWER_LEVEL:format(bestAffixScore.level), HIGHLIGHT_FONT_COLOR)

                local displayZeroHours = bestAffixScore.durationSec >= SECONDS_PER_HOUR
                local durationText = SecondsToClock(bestAffixScore.durationSec, displayZeroHours)

                if bestAffixScore.overTime then
                  local overtimeText = DUNGEON_SCORE_OVERTIME_TIME:format(durationText)
                  GameTooltip_AddColoredLine(GameTooltip, overtimeText, LIGHTGRAY_FONT_COLOR)
                else
                  GameTooltip_AddColoredLine(GameTooltip, tier .. " " .. durationText, HIGHLIGHT_FONT_COLOR)
                end
              end
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Dungeon Timers")
            GameTooltip:AddLine("|A:Professions-ChatIcon-Quality-Tier1:14:14:0:0|a " .. SecondsToClock(Helpers:calculateDungeonTimer(dungeon.time, dungeonLevel, 1, seasonID), false), 1, 1, 1)
            GameTooltip:AddLine("|A:Professions-ChatIcon-Quality-Tier2:16:16:0:0|a " .. SecondsToClock(Helpers:calculateDungeonTimer(dungeon.time, dungeonLevel, 2, seasonID), false), 1, 1, 1)
            GameTooltip:AddLine("|A:Professions-ChatIcon-Quality-Tier3:16:16:0:0|a " .. SecondsToClock(Helpers:calculateDungeonTimer(dungeon.time, dungeonLevel, 3, seasonID), false), 1, 1, 1)
            GameTooltip:Show()

            SetHighlightColor(dungeonFrame, 1, 1, 1, 0.05)
          end)
          dungeonFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
            SetHighlightColor(dungeonFrame, 1, 1, 1, 0)
          end)

          SetBackgroundColor(dungeonFrame, 1, 1, 1, dungeonIndex % 2 == 0 and 0.01 or 0)
          dungeonFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          dungeonFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          dungeonFrame:SetHeight(Constants.sizes.row)
          dungeonFrame:Show()
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end

      do -- Raid Header
        if Data.db.global.raids.enabled then
          characterFrame.raidHeader:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          characterFrame.raidHeader:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          characterFrame.raidHeader:SetHeight(Constants.sizes.row)
          characterFrame.raidHeader:Show()
          SetBackgroundColor(characterFrame.raidHeader, 0, 0, 0, 0.3)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        else
          characterFrame.raidHeader:Hide()
        end
      end

      do -- Raids
        characterFrame.difficultyFrames = characterFrame.difficultyFrames or {}
        TableForEach(characterFrame.difficultyFrames, function(f) f:Hide() end)
        TableForEach(raidDifficulties or {}, function(difficulty, difficultyIndex)
          if not Data.db.global.raids.enabled then return end
          local difficultyFrame = characterFrame.difficultyFrames[difficultyIndex]
          if not difficultyFrame then
            difficultyFrame = CreateFrame("Frame", "$parentRaidDifficulty" .. difficultyIndex, characterFrame)
            difficultyFrame.iconFrames = {}
            -- difficultyFrame.dividers = {}
            characterFrame.difficultyFrames[difficultyIndex] = difficultyFrame
          end

          -- Update difficulty row
          SetBackgroundColor(difficultyFrame, 1, 1, 1, difficultyIndex % 2 == 0 and 0.01 or 0)
          difficultyFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          difficultyFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          difficultyFrame:SetHeight(RAIDS_ROW_HEIGHT)
          difficultyFrame:Show()
          rowCount = rowCount + 1
          totalHeight = totalHeight + RAIDS_ROW_HEIGHT

          -- Get all raid encounters
          ---@type AE_Encounter[]
          local encounters = {}
          local numEncounters = 0
          TableForEach(raids or {}, function(raid, raidIndex)
            TableForEach(raid.encounters or {}, function(encounter, encounterIndex)
              table.insert(encounters, encounter)
              numEncounters = numEncounters + 1
            end)
          end)

          difficultyFrame:SetScript("OnEnter", function()
            GameTooltip:SetOwner(difficultyFrame, "ANCHOR_RIGHT")
            GameTooltip:SetText("Raid Progress", 1, 1, 1, 1, true)
            GameTooltip:AddLine(format("Difficulty: |cffffffff%s|r", difficulty.short and difficulty.short or difficulty.name))
            TableForEach(raids, function(raid, raidIndex)
              GameTooltip:AddLine(" ")
              GameTooltip:AddLine(raid.name)
              TableForEach(raid.encounters, function(encounter)
                local color = LIGHTGRAY_FONT_COLOR
                if character.raids.savedInstances then
                  local savedInstance = TableFind(character.raids.savedInstances, function(instance)
                    return GetBaseDifficultyID(instance.difficultyID) == difficulty.id and instance.instanceID == raid.instanceID and instance.expires > time()
                  end)
                  if savedInstance then
                    local savedEncounter = TableGet(savedInstance.encounters, "instanceEncounterID", encounter.instanceEncounterID)
                    if savedEncounter and savedEncounter.isKilled then
                      color = GREEN_FONT_COLOR
                    end
                  end
                end
                GameTooltip:AddLine(encounter.name, color.r, color.g, color.b)
              end)
            end)
            GameTooltip:Show()
            SetHighlightColor(difficultyFrame, 1, 1, 1, 0.05)
          end)

          difficultyFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
            SetHighlightColor(difficultyFrame, 1, 1, 1, 0)
          end)

          local killIcon = TableGet(Constants.raidKillIcons, "id", Data.db.global.raids.killIcon or "skull") or Constants.raidKillIcons[1]
          TableForEach(difficultyFrame.iconFrames, function(f) f:Hide() end)
          TableForEach(encounters or {}, function(encounter, encounterIndex)
            local iconFrame = difficultyFrame.iconFrames[encounterIndex]
            if not iconFrame then
              iconFrame = CreateFrame("Frame", "$parentEncounter" .. encounterIndex, difficultyFrame)
              iconFrame.Background = iconFrame:CreateTexture("Background", "BACKGROUND")
              iconFrame.Background:SetAllPoints()
              difficultyFrame.iconFrames[encounterIndex] = iconFrame
            end

            local color = CreateColor(1, 1, 1)
            local alpha = 0.08

            if character.raids.savedInstances then
              local savedInstance = TableFind(character.raids.savedInstances, function(instance)
                return GetBaseDifficultyID(instance.difficultyID) == difficulty.id and instance.instanceID == encounter.instanceID and instance.expires > time()
              end)
              if savedInstance then
                local savedEncounter = TableGet(savedInstance.encounters, "instanceEncounterID", encounter.instanceEncounterID)
                if savedEncounter and savedEncounter.isKilled then
                  color = UNCOMMON_GREEN_COLOR
                  if Data.db.global.raids.colors then
                    color = difficulty.color
                  end
                  alpha = 0.5
                end
              end
            end

            iconFrame.Background:SetTexture(killIcon.texture)
            iconFrame.Background:SetVertexColor(color.r, color.g, color.b, alpha)

            iconFrame:Show()
          end)
          LayoutRaidEncounterIcons(difficultyFrame, numEncounters, characterFrame:GetWidth())
        end)
      end

      do -- Timewalking Lockouts
        characterFrame.timewalkingFrame = characterFrame.timewalkingFrame or CreateFrame("Frame", "$parentTimewalkingDifficulty", characterFrame)
        local timewalkingFrame = characterFrame.timewalkingFrame
        timewalkingFrame.iconFrames = timewalkingFrame.iconFrames or {}

        local timewalkingEra = Data.db.global.raids.enabled and Data.db.global.raids.timewalkingLockouts and Data:GetActiveTimewalkingEra()
        if timewalkingEra then
          SetBackgroundColor(timewalkingFrame, 1, 1, 1, 0)
          timewalkingFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          timewalkingFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          timewalkingFrame:SetHeight(RAIDS_ROW_HEIGHT)
          timewalkingFrame:Show()
          rowCount = rowCount + 1
          totalHeight = totalHeight + RAIDS_ROW_HEIGHT

          local bossKills = Data:GetTimewalkingBossKills(character)
          local bosses = {
            { key = "illidan", name = "Illidan Stormrage (Black Temple)", color = UNCOMMON_GREEN_COLOR },
            { key = "yoggsaron", name = "Yogg-Saron (Ulduar)", color = RARE_BLUE_COLOR },
            { key = "ragnaros", name = "Ragnaros (Firelands)", color = LEGENDARY_ORANGE_COLOR },
          }

          local killIcon = TableGet(Constants.raidKillIcons, "id", Data.db.global.raids.killIcon or "skull") or Constants.raidKillIcons[1]

          TableForEach(timewalkingFrame.iconFrames, function(f) f:Hide() end)
          TableForEach(bosses, function(boss, bossIndex)
            local iconFrame = timewalkingFrame.iconFrames[bossIndex]
            if not iconFrame then
              iconFrame = CreateFrame("Frame", "$parentTimewalkingBoss" .. bossIndex, timewalkingFrame)
              iconFrame.Background = iconFrame:CreateTexture("Background", "BACKGROUND")
              iconFrame.Background:SetAllPoints()
              timewalkingFrame.iconFrames[bossIndex] = iconFrame
            end

            local isKilled = bossKills[boss.key]
            local color = CreateColor(1, 1, 1)
            if isKilled then
              color = UNCOMMON_GREEN_COLOR
              if Data.db.global.raids.colors then
                color = boss.color
              end
            end
            local alpha = isKilled and 0.5 or 0.08

            iconFrame.Background:SetTexture(killIcon.texture)
            iconFrame.Background:SetVertexColor(color.r, color.g, color.b, alpha)
            iconFrame:SetScript("OnEnter", function()
              GameTooltip:SetOwner(iconFrame, "ANCHOR_RIGHT")
              GameTooltip:SetText(boss.name, 1, 1, 1)
              GameTooltip:AddLine(isKilled and "Killed this week" or "Not killed this week", 1, 1, 1)
              GameTooltip:Show()
            end)
            iconFrame:SetScript("OnLeave", function()
              GameTooltip:Hide()
            end)
            iconFrame:Show()
          end)
          LayoutTimewalkingRaidIcons(timewalkingFrame, #bosses, characterFrame:GetWidth())
        else
          timewalkingFrame:Hide()
        end
      end

      do -- Currency Header
        if Data.db.global.currencies.enabled then
          characterFrame.currencyHeaderFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          characterFrame.currencyHeaderFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          characterFrame.currencyHeaderFrame:SetHeight(Constants.sizes.row)
          characterFrame.currencyHeaderFrame:Show()
          SetBackgroundColor(characterFrame.currencyHeaderFrame, 0, 0, 0, 0.3)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        else
          characterFrame.currencyHeaderFrame:Hide()
        end
      end

      do -- Currencies
        characterFrame.currencyFrames = characterFrame.currencyFrames or {}
        TableForEach(characterFrame.currencyFrames, function(f) f:Hide() end)
        TableForEach(currencies, function(currency, currencyIndex)
          if not Data.db.global.currencies.enabled then return end
          if Data.db.global.currencies.hiddenCurrencies and Data.db.global.currencies.hiddenCurrencies[currency.id] then return end

          local currencyFrame = characterFrame.currencyFrames[currencyIndex]
          if not currencyFrame then
            currencyFrame = CreateFrame("Frame", "$parentCurrencies" .. currencyIndex, characterFrame)
            currencyFrame.Text = currencyFrame:CreateFontString(currencyFrame:GetName() .. "TextLeft", "OVERLAY")
            currencyFrame.Text:SetFontObject("GameFontHighlight_NoShadow")
            currencyFrame.Text:SetPoint("TOPLEFT", currencyFrame, "TOPLEFT", Constants.sizes.padding, -3)
            currencyFrame.Text:SetPoint("BOTTOMRIGHT", currencyFrame, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
            currencyFrame.Text:SetJustifyH("LEFT")
            characterFrame.currencyFrames[currencyIndex] = currencyFrame
          end

          local characterCurrency = TableGet(character.currencies, "id", currency.id)
          PopulateCurrencyCell(currencyFrame, currency, characterCurrency, Data.db.global.currencies)
          currencyFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
            SetHighlightColor(currencyFrame, 1, 1, 1, 0)
          end)

          SetBackgroundColor(currencyFrame, 1, 1, 1, currencyIndex % 2 == 0 and 0.01 or 0)
          currencyFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          currencyFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          currencyFrame:SetHeight(Constants.sizes.row)
          currencyFrame:Show()
          RegisterRowHighlightFrame(currencyFrame, totalHeight, Constants.sizes.row)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end

      do -- Weeklies Header
        if Data.db.global.weeklies.enabled then
          characterFrame.weekliesHeaderFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          characterFrame.weekliesHeaderFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          characterFrame.weekliesHeaderFrame:SetHeight(Constants.sizes.row)
          characterFrame.weekliesHeaderFrame:Show()
          SetBackgroundColor(characterFrame.weekliesHeaderFrame, 0, 0, 0, 0.3)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        else
          characterFrame.weekliesHeaderFrame:Hide()
        end
      end

      do -- Weeklies
        characterFrame.weeklyFrames = characterFrame.weeklyFrames or {}
        TableForEach(characterFrame.weeklyFrames, function(f) f:Hide() end)
        TableForEach(weeklies, function(currency, currencyIndex)
          if not Data.db.global.weeklies.enabled then return end
          if Data.db.global.weeklies.hiddenCurrencies and Data.db.global.weeklies.hiddenCurrencies[currency.id] then return end

          local currencyFrame = characterFrame.weeklyFrames[currencyIndex]
          if not currencyFrame then
            currencyFrame = CreateFrame("Frame", "$parentWeeklies" .. currencyIndex, characterFrame)
            currencyFrame.Text = currencyFrame:CreateFontString(currencyFrame:GetName() .. "TextLeft", "OVERLAY")
            currencyFrame.Text:SetFontObject("GameFontHighlight_NoShadow")
            currencyFrame.Text:SetPoint("TOPLEFT", currencyFrame, "TOPLEFT", Constants.sizes.padding, -3)
            currencyFrame.Text:SetPoint("BOTTOMRIGHT", currencyFrame, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
            currencyFrame.Text:SetJustifyH("LEFT")
            characterFrame.weeklyFrames[currencyIndex] = currencyFrame
          end

          local characterCurrency = TableGet(character.currencies, "id", currency.id)
          PopulateCurrencyCell(currencyFrame, currency, characterCurrency, Data.db.global.weeklies)
          currencyFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
            SetHighlightColor(currencyFrame, 1, 1, 1, 0)
          end)

          SetBackgroundColor(currencyFrame, 1, 1, 1, currencyIndex % 2 == 0 and 0.01 or 0)
          currencyFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          currencyFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          currencyFrame:SetHeight(Constants.sizes.row)
          currencyFrame:Show()
          RegisterRowHighlightFrame(currencyFrame, totalHeight, Constants.sizes.row)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end

      do -- Seasonal Chores Header
        if Data.db.global.seasonalChores.enabled then
          characterFrame.seasonalChoresHeaderFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          characterFrame.seasonalChoresHeaderFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          characterFrame.seasonalChoresHeaderFrame:SetHeight(Constants.sizes.row)
          characterFrame.seasonalChoresHeaderFrame:Show()
          SetBackgroundColor(characterFrame.seasonalChoresHeaderFrame, 0, 0, 0, 0.3)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        else
          characterFrame.seasonalChoresHeaderFrame:Hide()
        end
      end

      do -- Seasonal Chores
        characterFrame.seasonalChoreFrames = characterFrame.seasonalChoreFrames or {}
        TableForEach(characterFrame.seasonalChoreFrames, function(f) f:Hide() end)
        TableForEach(seasonalChores, function(currency, currencyIndex)
          if not Data.db.global.seasonalChores.enabled then return end
          if Data.db.global.seasonalChores.hiddenCurrencies and Data.db.global.seasonalChores.hiddenCurrencies[currency.id] then return end

          local currencyFrame = characterFrame.seasonalChoreFrames[currencyIndex]
          if not currencyFrame then
            currencyFrame = CreateFrame("Frame", "$parentSeasonalChores" .. currencyIndex, characterFrame)
            currencyFrame.Text = currencyFrame:CreateFontString(currencyFrame:GetName() .. "TextLeft", "OVERLAY")
            currencyFrame.Text:SetFontObject("GameFontHighlight_NoShadow")
            currencyFrame.Text:SetPoint("TOPLEFT", currencyFrame, "TOPLEFT", Constants.sizes.padding, -3)
            currencyFrame.Text:SetPoint("BOTTOMRIGHT", currencyFrame, "BOTTOMRIGHT", -Constants.sizes.padding, 3)
            currencyFrame.Text:SetJustifyH("LEFT")
            characterFrame.seasonalChoreFrames[currencyIndex] = currencyFrame
          end

          local characterCurrency = TableGet(character.currencies, "id", currency.id)
          PopulateCurrencyCell(currencyFrame, currency, characterCurrency, Data.db.global.seasonalChores)
          currencyFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
            SetHighlightColor(currencyFrame, 1, 1, 1, 0)
          end)

          SetBackgroundColor(currencyFrame, 1, 1, 1, currencyIndex % 2 == 0 and 0.01 or 0)
          currencyFrame:SetPoint("TOPLEFT", characterFrame, "TOPLEFT", 0, -totalHeight)
          currencyFrame:SetPoint("TOPRIGHT", characterFrame, "TOPRIGHT", 0, -totalHeight)
          currencyFrame:SetHeight(Constants.sizes.row)
          currencyFrame:Show()
          RegisterRowHighlightFrame(currencyFrame, totalHeight, Constants.sizes.row)
          rowCount = rowCount + 1
          totalHeight = totalHeight + Constants.sizes.row
        end)
      end

      windowWidth = windowWidth + CHARACTER_WIDTH
    end)
  end

  local sidebarWidth = numCharacters > 0 and not sidebarCollapsed and Constants.sizes.sidebar.width or 0
  -- The horizontal ScrollArea is now the permanent overflow mechanism. Cap the
  -- viewport by both the screen-safe width and the optional number of character
  -- columns the user wants visible at once; the full character grid remains in
  -- the scroll content either way.
  local characterViewportWidthMax = math.max(1, windowWidthMax - sidebarWidth)
  local visibleCharacterLimit = tonumber(mainWindowSettings.visibleCharacterLimit) or 15
  if visibleCharacterLimit > 0 and numCharacters > 0 then
    characterViewportWidthMax = math.min(characterViewportWidthMax, visibleCharacterLimit * CHARACTER_WIDTH)
  end
  local bodyWidth = math.min(windowWidth, characterViewportWidthMax) + sidebarWidth

  if numCharacters == 1 then
    -- Keep the one-character window at a stable width whether Row Labels are shown or hidden.
    -- With labels hidden, the character column expands into their freed space; with labels shown,
    -- the same window is split back into the normal sidebar + the remaining character width.
    bodyWidth = math.max(bodyWidth, CHARACTER_WIDTH + Constants.sizes.sidebar.width)
  end

  bodyWidth = LayoutMainTitlebarButtons(self.window, bodyWidth, windowHeight)

  local characterContentWidth = windowWidth
  local expandSingleVisibleColumn = numCharacters > 0 and (numCharacters == 1 or visibleCharacterLimit == 1)
  local finalCharacterWidth = CHARACTER_WIDTH

  -- When the viewport shows a single character, let that character consume all
  -- horizontal space available to the character area. This applies both to a
  -- genuinely single-character list and to Visible Characters = 1 with several
  -- tracked characters. Showing Row Labels simply subtracts the sidebar from the
  -- same window width; hiding Row Labels gives the full window body to the column.
  if expandSingleVisibleColumn then
    finalCharacterWidth = math.max(CHARACTER_WIDTH, bodyWidth - sidebarWidth)
    for characterIndex = 1, numCharacters do
      local characterFrame = self.window.characterFrames and self.window.characterFrames[characterIndex]
      if characterFrame and characterFrame:IsShown() then
        characterFrame:ClearAllPoints()
        characterFrame:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", (characterIndex - 1) * finalCharacterWidth, 0)
        characterFrame:SetPoint("BOTTOMLEFT", scrollContent, "BOTTOMLEFT", (characterIndex - 1) * finalCharacterWidth, 0)
        characterFrame:SetWidth(finalCharacterWidth)

        -- The column can grow after its rows were initially rendered. Reflow raid
        -- and Timewalking icons against the final width so every group remains centered.
        for _, difficultyFrame in ipairs(characterFrame.difficultyFrames or {}) do
          LayoutRaidEncounterIcons(difficultyFrame, #(difficultyFrame.iconFrames or {}), finalCharacterWidth)
        end
        if characterFrame.timewalkingFrame and characterFrame.timewalkingFrame:IsShown() then
          LayoutTimewalkingRaidIcons(characterFrame.timewalkingFrame, #(characterFrame.timewalkingFrame.iconFrames or {}), finalCharacterWidth)
        end
      end
    end
    characterContentWidth = finalCharacterWidth * numCharacters
  end

  self.window.characterScrollColumnWidth = finalCharacterWidth
  self.window.body.content.scrollArea:UpdateLayout(characterContentWidth, windowHeight)
  UpdateCharacterScrollEdgeButtons(self.window)

  local zeroCharactersText = "|cffffffffHi there :-)|r\nEnable a character top right for AlterEgo to show you some goodies!"
  if numCharacters <= 0 then
    local unfilteredCharacters = Data:GetCharacters(true)
    local hasHiddenNonMaxCharacter = false
    if not Data.db.global.showNonMaxLevelCharacters then
      for _, character in ipairs(unfilteredCharacters) do
        if not Data:IsMaxLevelCharacter(character) then
          hasHiddenNonMaxCharacter = true
          break
        end
      end
    end
    if hasHiddenNonMaxCharacter then
      zeroCharactersText = zeroCharactersText .. "\n\n|cff00ee00Leveling alts?|r\nYou are currently hiding characters below the current expansion level cap. Enable |cffffffffShow Non Max Level Characters|r to display them."
    elseif not Data.db.global.showZeroRatedCharacters and TableCount(unfilteredCharacters) > 0 then
      zeroCharactersText = zeroCharactersText .. "\n\n|cff00ee00New Season?|r\nYou are currently hiding max-level characters with zero rating. If this is not your intention then enable the setting |cffffffffShow characters with zero rating|r"
    end
    self.window:ShowOverlay(zeroCharactersText)
  else
    self.window:HideOverlay()
  end

end
