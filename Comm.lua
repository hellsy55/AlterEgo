---@class AE_Addon
local addon = select(2, ...)

-- Broadcasts the logged-in character's full record over the GUILD addon
-- channel so your OTHER WoW accounts (same guild, same addon, same
-- passphrase) can pick it up and show it alongside your other characters --
-- same idea as GG's Comm.lua, simplified: AlterEgo characters are usually
-- only a handful of accounts, not a 30-person guild roster, so this sends
-- the whole record instead of GG's dirty-section partial payloads.
--
-- Trust boundary: NOTHING is sent or accepted unless Sync is enabled AND a
-- non-empty passphrase is set, AND the passphrase in the payload matches
-- this client's own passphrase exactly. A normal guildmate running an
-- unmodified (or differently-configured) AlterEgo never receives your data
-- and never has their own characters show up on your end -- the guild
-- channel is just the transport, the passphrase is the actual gate.
--
-- Chat noise: the automatic, per-change background sync (RequestSyncBroadcast
-- and everything it triggers, on both the sending AND receiving side) is
-- completely silent by design -- it can fire many times an hour from
-- routine gameplay (loot, currency ticks, vault progress...), and printing
-- every one of those would just be spam. The only things that print are
-- deliberate actions you took ("Sync Now", "Sync All Characters", "Stop
-- Sync") and genuine problems (passphrase mismatch, an out-of-date client).

local Data = addon.Data
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")
LibStub("AceComm-3.0"):Embed(addon.Core)

local COMM_PREFIX = "AEv1"

-- Don't spam the guild channel every time a single currency ticks up --
-- collect changes and send at most one full record every 20s per client.
local BROADCAST_MIN_INTERVAL_SECONDS = 20
-- Let a burst of near-simultaneous updates (Vault+Currencies+Equipment all
-- firing within the same frame) settle into a single message.
local BROADCAST_DEBOUNCE_SECONDS = 2

local lastBroadcastAt = 0
local broadcastPending = false

---Serialize+compress+send one character record. Shared by the automatic
---per-change broadcast, the manual "Sync Now" (current character), and
---"Sync All Characters" (everyone already cached locally).
---@param character AE_Character
---@param passphrase string
---@param priority string? AceComm priority ("BULK"/"NORMAL"/"ALERT"). Defaults to "BULK".
local function SendCharacterRecord(character, passphrase, priority)
  local payload = {
    passphrase = passphrase,
    character = character,
  }

  local serialized = LibSerialize:Serialize(payload)
  local compressed = LibDeflate:CompressDeflate(serialized)
  local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)

  addon.Core:SendCommMessage(COMM_PREFIX, encoded, "GUILD", nil, priority or "BULK")
end

---Has this character actually changed since the last time we told anyone
---about it (via ANY sync path)? Compares against `lastUpdate`, the same
---timestamp `Data:UpdateCharacterInfo()` already stamps on every full
---refresh -- so a character that hasn't been refreshed since its last
---broadcast is, by definition, unchanged.
---@param character AE_Character
---@return boolean
local function HasCharacterChangedSinceLastSync(character)
  local lastSent = Data.db.global.sync.lastSentUpdate[character.GUID]
  return lastSent == nil or lastSent ~= character.lastUpdate
end

---Record that we just sent this character's current state, so the next
---check of the same (unchanged) data knows to skip it.
---@param character AE_Character
local function MarkCharacterSynced(character)
  Data.db.global.sync.lastSentUpdate = Data.db.global.sync.lastSentUpdate or {}
  Data.db.global.sync.lastSentUpdate[character.GUID] = character.lastUpdate
end

---Checks Sync is actually usable right now (enabled, passphrase set, in a
---guild), optionally printing why not. Shared by every send path below.
---@param verbose boolean?
---@return string? passphrase nil if sync can't run right now
local function GetUsablePassphrase(verbose)
  if not Data.db.global.sync.enabled then
    if verbose then addon.Core:Print("Sync: not sending, Sync is disabled.") end
    return nil
  end
  local passphrase = Data.db.global.sync.passphrase
  if not passphrase or passphrase == "" then
    if verbose then addon.Core:Print("Sync: not sending, no passphrase set.") end
    return nil
  end
  if not IsInGuild() then
    if verbose then addon.Core:Print("Sync: not sending, you're not in a guild (GUILD channel needs one).") end
    return nil
  end
  return passphrase
end

---True if this character is allowed to go out over Sync right now: if a
---Main WoW Account is set, only characters filed under it qualify (so
---characters that came IN from someone else's sync never get echoed back
---out); with no Main account set, everything tracked qualifies.
---@param character AE_Character
---@return boolean
local function IsEligibleToSend(character)
  local mainAccountId = Data.GetMainAccountId and Data:GetMainAccountId()
  return not mainAccountId or character.accountId == mainAccountId
end

---@param verbose boolean? Print why nothing was sent -- used by the manual "Sync Now" button.
local function PerformBroadcast(verbose)
  broadcastPending = false

  local passphrase = GetUsablePassphrase(verbose)
  if not passphrase then return end

  local now = time()
  if not verbose and now - lastBroadcastAt < BROADCAST_MIN_INTERVAL_SECONDS then
    C_Timer.After(BROADCAST_MIN_INTERVAL_SECONDS - (now - lastBroadcastAt) + 1, function()
      addon.Core:RequestSyncBroadcast()
    end)
    return
  end

  local character = Data:GetCharacter()
  if not character then return end

  if not IsEligibleToSend(character) then
    if verbose then addon.Core:Print("Sync: not sending, this character isn't in your Main WoW Account.") end
    return
  end

  if not HasCharacterChangedSinceLastSync(character) then
    -- Automatic path stays completely silent here -- this is the normal,
    -- expected case most of the time (nothing changed since the last
    -- broadcast) and printing it would just be noise.
    if verbose then addon.Core:Print(format("Sync: %s-%s hasn't changed since the last sync -- nothing sent.", character.info.name, character.info.realm)) end
    return
  end

  -- Manual "Sync Now" (verbose) is a deliberate one-off action -- send it at
  -- the highest AceComm priority so it doesn't sit behind whatever else is
  -- using the shared BULK queue. The automatic per-change broadcast stays
  -- on BULK since it's routine background chatter, not something urgent.
  SendCharacterRecord(character, passphrase, verbose and "ALERT" or "BULK")
  MarkCharacterSynced(character)
  lastBroadcastAt = now
  if verbose then addon.Core:Print(format("Sync: sent %s-%s to the guild.", character.info.name, character.info.realm)) end
end

---Call this after anything that changed the logged-in character's data.
---Debounced + throttled -- safe to call as often as you want. Completely
---silent -- see the file header.
function addon.Core:RequestSyncBroadcast()
  if broadcastPending then return end
  broadcastPending = true
  C_Timer.After(BROADCAST_DEBOUNCE_SECONDS, PerformBroadcast)
end

---Send right now, ignoring the throttle (but NOT the "unchanged" skip), and
---print exactly what happened -- for testing, so you don't have to wait for
---a real data change or the 20s window to see whether Sync is working.
function addon.Core:ForceSyncBroadcast()
  PerformBroadcast(true)
end

-- How long to wait between characters when sending the whole cached roster
-- at once -- one AceComm message per character, spaced out so a big alt
-- army doesn't try to shove a dozen full records (equipment+vault+etc, each
-- chunked into ~255-byte pieces) through the shared queue all at once.
local SYNC_ALL_STAGGER_SECONDS = 2

---Send every character that's eligible right now (tracked + enabled, and
---filed under your Main WoW Account if one is set) -- not just the one
---you're logged in on, so you don't have to relog through every alt just to
---share it. Skips anything unchanged since the last time it was sent, and
---prints ONE summary at the end (who was actually sent vs. who was already
---up to date) instead of a line per character.
function addon.Core:ForceSyncBroadcastAll()
  local passphrase = GetUsablePassphrase(true)
  if not passphrase then return end

  local characters = Data.GetSyncEligibleCharacters and Data:GetSyncEligibleCharacters() or Data:GetCharacters()

  if #characters == 0 then
    addon.Core:Print("Sync: no eligible characters to send (check they're enabled, and in your Main WoW Account if you've set one).")
    return
  end

  local sentNames = {}
  local skippedNames = {}
  local toSend = {}
  for _, character in ipairs(characters) do
    if HasCharacterChangedSinceLastSync(character) then
      table.insert(toSend, character)
    else
      table.insert(skippedNames, format("%s-%s", character.info.name or "?", character.info.realm or "?"))
    end
  end

  local function PrintSummary()
    if #sentNames > 0 then
      addon.Core:Print(format("Sync: sent %d character(s): %s", #sentNames, table.concat(sentNames, ", ")))
    end
    if #skippedNames > 0 then
      addon.Core:Print(format("Sync: skipped %d character(s) with no changes: %s", #skippedNames, table.concat(skippedNames, ", ")))
    end
    if #sentNames == 0 and #skippedNames == 0 then
      addon.Core:Print("Sync: nothing to send.")
    end
  end

  if #toSend == 0 then
    PrintSummary()
    return
  end

  local index = 0
  local function SendNext()
    index = index + 1
    local character = toSend[index]
    if not character then
      PrintSummary()
      return
    end
    -- Deliberate bulk action, same reasoning as the manual "Sync Now" above --
    -- highest priority so it doesn't crawl behind other BULK traffic.
    SendCharacterRecord(character, passphrase, "ALERT")
    MarkCharacterSynced(character)
    table.insert(sentNames, format("%s-%s", character.info.name or "?", character.info.realm or "?"))
    C_Timer.After(SYNC_ALL_STAGGER_SECONDS, SendNext)
  end
  SendNext()
end

---Immediately turns Sync off -- a panic button for "something's wrong,
---stop sending/receiving right now" without having to dig into the
---settings checkbox.
function addon.Core:StopSync()
  Data.db.global.sync.enabled = false
  addon.Core:Print("Sync: stopped. Nothing will be sent or received until you turn Enable Sync back on.")
end

-- Received characters that arrived while you were in combat -- held here
-- instead of touching Data.db/rebuilding the main window mid-fight (that
-- Render() rebuilds a decent chunk of UI, which is exactly the kind of
-- thing that causes a hitch during a pull). Applied automatically the
-- moment combat ends (PLAYER_REGEN_ENABLED, below).
local pendingCombatApplies = {} -- [GUID] = <character>

---Actually write a received character into the saved roster and refresh
---the UI. Called either immediately (out of combat) or once combat ends
---for anything that came in while you were fighting. Silent -- see the
---file header for why routine receives don't print anything.
---@param remote AE_Character
local function ApplyReceivedCharacter(remote)
  Data.db.global.characters[remote.GUID] = remote
  addon.Core:Render()
end

addon.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
  local applied = 0
  for _, remote in pairs(pendingCombatApplies) do
    ApplyReceivedCharacter(remote)
    applied = applied + 1
  end
  wipe(pendingCombatApplies)
  if applied > 0 then
    addon.Core:Print(format("Sync: applied %d character(s) that arrived during combat.", applied))
  end
end, true)

function addon.Core:OnCommReceived(prefix, message, distribution, sender)
  if prefix ~= COMM_PREFIX then return end
  if not Data.db.global.sync.enabled then return end

  local passphrase = Data.db.global.sync.passphrase
  if not passphrase or passphrase == "" then return end

  local decoded = LibDeflate:DecodeForWoWAddonChannel(message)
  if not decoded then return end
  local decompressed = LibDeflate:DecompressDeflate(decoded)
  if not decompressed then return end
  local success, payload = LibSerialize:Deserialize(decompressed)
  if not success or type(payload) ~= "table" then return end

  -- Wrong/blank passphrase on either end -- silently ignore the DATA, but
  -- this one's worth printing: it usually means a typo in one of the two
  -- passphrases, which is easy to miss otherwise.
  if payload.passphrase ~= passphrase then
    addon.Core:Print(format("Sync: got a message from %s, but the passphrase didn't match -- ignored.", tostring(sender)))
    return
  end

  local remote = payload.character
  if type(remote) ~= "table" or type(remote.GUID) ~= "string" or remote.GUID == "" then return end
  if remote.GUID == UnitGUID("player") then return end -- shouldn't happen, but never let a record overwrite the live character

  local existing = Data.db.global.characters[remote.GUID]

  -- Only accept if it's actually newer than what we already know -- keeps a
  -- stale record (an account that hasn't played in a while, relayed back
  -- around) from ever stomping fresher data, no matter which client sent it.
  -- Silent: this is the routine "nothing to do" case, not a problem.
  if existing and existing.lastUpdate and remote.lastUpdate and remote.lastUpdate <= existing.lastUpdate then
    return
  end

  if existing then
    -- Protect your own Main WoW Account -- if this character is already
    -- filed there, it's YOUR authoritative copy, so incoming sync data
    -- never overwrites it.
    local mainAccountId = Data.GetMainAccountId and Data:GetMainAccountId()
    if mainAccountId and existing.accountId == mainAccountId then
      return
    end

    -- Preserve local-only bookkeeping across syncs -- which WoW Account
    -- bucket you filed this character under, whether you disabled it, and
    -- its manual sort order shouldn't reset just because a fresher sync
    -- came in from the other account.
    remote.accountId = existing.accountId
    remote.enabled = existing.enabled
    remote.order = existing.order
  else
    -- Brand new character we've never seen before -- file it under the WoW
    -- Account tied to THIS passphrase, creating one the first time this
    -- passphrase brings anyone in. A different passphrase (a different
    -- friend/account) gets its own separate account instead of everything
    -- piling into one bucket. Characters we already know about keep
    -- whatever account you filed them under (see above) -- this only
    -- decides where a character lands the very first time.
    -- Defensive: if Data.lua is out of date on this client and doesn't
    -- have this function yet, fall back to the default account instead of
    -- crashing the whole receive handler (which would silently drop the
    -- character with no explanation, exactly what happened before this
    -- guard existed).
    if Data.GetOrCreateAccountForPassphrase then
      remote.accountId = Data:GetOrCreateAccountForPassphrase(passphrase)
    else
      addon.Core:Print("Sync: Data.lua looks out of date (missing GetOrCreateAccountForPassphrase) -- filed under your default WoW Account instead. Reinstall the full addon package to fix this.")
      remote.accountId = Data:EnsureDefaultAccount()
    end
  end

  if InCombatLockdown() then
    pendingCombatApplies[remote.GUID] = remote
    return
  end

  ApplyReceivedCharacter(remote)
end

addon.Core:RegisterComm(COMM_PREFIX)
