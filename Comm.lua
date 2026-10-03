---@class AE_Addon
local addon = select(2, ...)

-- Broadcasts the logged-in character's full record over the GUILD addon
-- channel so your OTHER WoW accounts (same guild, same addon, same
-- password) can pick it up and show it alongside your other characters --
-- same idea as GG's Comm.lua, simplified: AlterEgo characters are usually
-- only a handful of accounts, not a 30-person guild roster, so this sends
-- the whole record instead of GG's dirty-section partial payloads.
--
-- Trust boundary: NOTHING is sent or accepted unless Sync is enabled AND a
-- non-empty password is set, AND the password in the payload matches
-- this client's own password exactly. A normal guildmate running an
-- unmodified (or differently-configured) AlterEgo never receives your data
-- and never has their own characters show up on your end -- the guild
-- channel is just the transport, the password is the actual gate.
--
-- Chat noise: the automatic, per-change background sync (RequestSyncBroadcast
-- and everything it triggers) is silent on the SENDING side by design -- it
-- can fire many times an hour from routine gameplay (loot, currency ticks,
-- vault progress...), and printing every one of those would just be spam.
-- A password mismatch is deliberately silent too, on either side -- using
-- the right password for who you're sharing with is on each person running
-- this, not something worth a warning every time someone else's guildmate
-- happens to run Sync with a different one.

local Data = addon.Data
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")
LibStub("AceComm-3.0"):Embed(addon.Core)

-- Used only for RECEIVING (RegisterComm/OnCommReceived) -- see SendOnChannel
-- below for why outgoing sends bypass AceComm's own SendCommMessage instead
-- of using this embed for that direction too.
local CTL = ChatThrottleLib

local COMM_PREFIX = "AEv1"
-- Presence/version negotiation uses a separate prefix so a multi-part HELLO cannot
-- collide with a multi-part character record in AceComm's receive spool.
local CONTROL_PREFIX = "AEv1Sync"

-- Peer discovery/reconciliation is intentionally session-local. Nothing received from
-- another player is ever re-broadcast as a relay: each client only advertises versions
-- it knows and only sends characters that belong to its own Main WoW Account.
local PEER_HEARTBEAT_SECONDS = 60
local PEER_TIMEOUT_SECONDS = 150
local HELLO_MIN_INTERVAL_SECONDS = 8
local HELLO_RESPONSE_MIN_INTERVAL_SECONDS = 8
local MANUAL_RECONCILE_WAIT_SECONDS = 3
local ACK_TIMEOUT_SECONDS = 45
local ACK_RETRY_MAX = 2
local syncPeers = {} -- [sender] = {lastSeen, distribution, versions = { [GUID] = lastUpdate }}
local catchupPendingGUIDs = {} -- own/Main characters a peer explicitly reported missing/stale
local pendingConfirmations = {} -- [transmissionId] = {GUID, lastUpdate, manual, batchId}
local confirmationRetryCounts = {} -- [GUID|lastUpdate] = number of automatic ACK-timeout retries this session
local processedHelloIds = {} -- dedupe the same HELLO arriving over both GUILD and PARTY/RAID
local processedAckTransmissionIds = {} -- dedupe the same transmission arriving over more than one channel while still allowing a retry to be ACK'd
local helloResponseAt = {} -- [sender] = GetTime() of our last ordinary HELLO response
local lastHelloAt = 0
local syncSessionId = format("%d-%.6f", time(), GetTime())
local syncSequence = 0

local function NewSyncId(kind)
  syncSequence = syncSequence + 1
  return format("%s|%s|%d", kind, syncSessionId, syncSequence)
end
local syncHelloTimer = nil
local syncHeartbeatTicker = nil
local manualReconcileRequestId = nil
local manualReconcileResponders = nil
local manualReconcileTimer = nil

local SendSyncHello
local ScheduleSyncHello
local QueueCatchUpFromPeerVersions

-- Same control-byte protocol AceComm-3.0's own SendCommMessage uses for
-- splitting a message across multiple ~255-byte addon messages -- kept
-- identical on purpose so the stock AceComm receiving side (which this
-- addon still uses unmodified) reassembles it exactly the same way,
-- regardless of which of the two sends it.
local MSG_MULTI_FIRST = "\001"
local MSG_MULTI_NEXT = "\002"
local MSG_MULTI_LAST = "\003"
local MSG_ESCAPE = "\004"
local MAX_CHUNK_BYTES = 255

---Formats a duration in seconds as "12.3s" under a minute, or "6m 34s"
---(no decimals once minutes are involved) at or above one -- used for the
---"Sync Now" total-time summaries, which can legitimately run into
---several minutes on a congested channel.
---@param seconds number
---@return string
local function FormatDuration(seconds)
  if seconds < 60 then
    return format("%.1fs", seconds)
  end
  local minutes = math.floor(seconds / 60)
  local remainingSeconds = math.floor(seconds - minutes * 60 + 0.5)
  if remainingSeconds >= 60 then
    minutes = minutes + 1
    remainingSeconds = 0
  end
  return format("%dm %ds", minutes, remainingSeconds)
end

---Joins a short list with "and" before the last item ("GUILD" / "GUILD and
---PARTY" / "GUILD, PARTY and RAID") instead of a comma throughout -- no
---Oxford comma before the final "and". Only ever used for the channel
---list, which is at most two entries (GUILD plus whichever of RAID/PARTY
---applies, never both of those together), and for character-name lists.
---@param list string[]
---@return string
local function JoinWithAnd(list)
  if #list <= 1 then return list[1] or "" end
  if #list == 2 then return list[1] .. " and " .. list[2] end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- Don't spam the guild channel every time a single currency ticks up --
-- collect changes and send at most one full record every 20s per client.
local BROADCAST_MIN_INTERVAL_SECONDS = 20
-- Let a burst of near-simultaneous updates (Vault+Currencies+Equipment all
-- firing within the same frame) settle into a single message.
local BROADCAST_DEBOUNCE_SECONDS = 2
-- Extra safety buffer added AFTER a character's transmission is confirmed
-- fully dequeued on this end (see onDone in SendCharacterRecord) -- covers
-- the gap between "we're done sending" and "they're done receiving",
-- which our own confirmation can't see. No longer the primary defense
-- against overlapping transmissions -- the onDone confirmation is -- so
-- this can stay short.
local BROADCAST_STAGGER_SECONDS = 1.5
-- Waits for the REAL completion signal from ChatThrottleLib before
-- starting the next character (see SendCharacterRecord's onDone) rather
-- than guessing a fixed delay -- an earlier version of this code gave up
-- and moved on after a timeout, and that was actively harmful: it let the
-- next character's transmission start while the previous one was still
-- genuinely in flight, which is exactly the receive-side spool collision
-- this whole wait-for-real-completion scheme exists to prevent (see
-- batchInProgress below). A slow send that's still moving forward gets
-- waited out, not abandoned -- the only way to cut it short is disabling
-- Sync (Enable Sync checkbox), which force-clears the guard immediately
-- via ResetSyncBatchGuard.

local lastBroadcastAt = 0
local broadcastPending = false

-- True from the moment a multi-step send (the SendNext loop below) starts
-- until its last character goes out, whether that batch was triggered
-- manually ("Sync Now") or automatically. While true, any OTHER broadcast
-- -- manual or automatic -- is deferred instead of starting concurrently.
-- This isn't just about pacing: AceComm's receive-side multi-part
-- reassembly tracks only ONE in-flight message per (prefix, channel,
-- sender) at a time, keyed with no per-message id. If a second message
-- from the same sender on the same channel starts arriving before the
-- first one's last chunk does, it silently overwrites and destroys
-- whatever was being reassembled -- the first character's data just
-- vanishes, with nothing telling either side it happened. Two overlapping
-- broadcasts from this client (an automatic per-change send firing while
-- a manual multi-character batch is still going out, or vice versa) is
-- exactly that scenario.
local batchInProgress = false

-- If a manual "Sync Now" is interrupted, keep the exact GUIDs that still
-- need to go out. Additional clicks while the batch is actively sending
-- are intentionally ignored -- they do NOT create a second batch or reset
-- progress. Once the current batch has stopped (for example because combat
-- began), the next Sync Now resumes only these pending GUIDs. Successful
-- characters are removed one-by-one after ChatThrottleLib confirms every
-- chunk left this client, so already-sent characters are never repeated as
-- part of the same manual sync attempt. Nil means there is no incomplete
-- manual Sync Now to resume.
local manualPendingGUIDs = nil

-- The batchId of the Sync Now push currently going out (nil when none),
-- and which senders have ack'd ANY character in it so far -- populated
-- from the ack handler in OnCommReceived as they arrive DURING the send
-- (a big batch can take minutes, so several acks typically land well
-- before the last character even goes out). Lets the final "successfully
-- sent" summary name who it actually reached, not just that it was sent.
local activeBatchId = nil
local activeBatchConfirmedBy = {}

-- Automatic Sync never tries to push new character records while combat/encounter restrictions
-- are active. If a background batch is interrupted (or an outgoing chunk is rejected), remember
-- that work is still pending and resume it after the restriction clears. Because successful
-- characters are marked individually only after their transmission really completes, the retry
-- naturally contains only the failed/not-yet-started records instead of resending the whole batch.
local automaticResumePending = false
local automaticResumeTimer = nil

local function ResumeAutomaticSyncIfPending()
  if not automaticResumePending then return end
  if not Data.db.global.sync.enabled then
    automaticResumePending = false
    return
  end
  if batchInProgress or InCombatLockdown() then return end

  automaticResumePending = false
  addon.Core:RequestSyncBroadcast()
end

local function QueueAutomaticResume()
  if not Data.db.global.sync.enabled then return end
  automaticResumePending = true

  -- PLAYER_REGEN_ENABLED / ADDON_RESTRICTION_STATE_CHANGED are the normal resume triggers.
  -- Keep one delayed fallback as well so a send that reports failure just AFTER the relevant
  -- event fired cannot strand the pending data until some unrelated future character update.
  if not automaticResumeTimer then
    automaticResumeTimer = C_Timer.NewTimer(BROADCAST_MIN_INTERVAL_SECONDS, function()
      automaticResumeTimer = nil
      ResumeAutomaticSyncIfPending()
    end)
  end
end


---Sends one already-chunkable string over one channel, using the exact
---same wire format as AceComm-3.0's own SendCommMessage -- but queued
---under its OWN queueName (prefix .. "|" .. distribution) instead of
---always just prefix. That's the whole point: ChatThrottleLib gives each
---distinct queueName its own pipe and round-robins bandwidth BETWEEN
---pipes (one chunk from each in turn), but AceComm's SendCommMessage
---hardcodes queueName to the prefix alone -- so every channel this addon
---ever sends on (GUILD and PARTY) would share one pipe and be sent in
---strict enqueue order, every single GUILD chunk before the first PARTY
---chunk even starts. On a congested connection a slow GUILD send can
---starve PARTY completely for minutes, even though PARTY might go
---through fine on its own -- exactly what happened before this existed.
---Separate queueNames let the two channels share bandwidth instead of one
---blocking the other outright.
---@param prefix string
---@param text string
---@param distribution string
---@param prio string
---@param callbackFn function? (callbackArg, sent, total, didSend)
---@param callbackArg any
---@param target string? Required for "WHISPER"; ignored otherwise.
local function SendOnChannel(prefix, text, distribution, prio, callbackFn, callbackArg, target)
  local queueName = prefix .. "|" .. distribution
  local textlen = #text
  local maxlen = MAX_CHUNK_BYTES

  local ctlCallback = nil
  if callbackFn then
    ctlCallback = function(sent, didSend)
      return callbackFn(callbackArg, sent, textlen, didSend)
    end
  end

  local forceMultipart
  if text:match("^[\001-\009]") then
    if textlen + 1 > maxlen then
      forceMultipart = true
    else
      text = MSG_ESCAPE .. text
      textlen = textlen + 1
    end
  end

  if not forceMultipart and textlen <= maxlen then
    CTL:SendAddonMessage(prio, prefix, text, distribution, target, queueName, ctlCallback, textlen)
    return
  end

  local chunklen = maxlen - 1 -- 1 byte reserved for the part-indicator prefix
  local chunk = text:sub(1, chunklen)
  CTL:SendAddonMessage(prio, prefix, MSG_MULTI_FIRST .. chunk, distribution, target, queueName, ctlCallback, chunklen)

  local pos = 1 + chunklen
  while pos + chunklen <= textlen do
    chunk = text:sub(pos, pos + chunklen - 1)
    CTL:SendAddonMessage(prio, prefix, MSG_MULTI_NEXT .. chunk, distribution, target, queueName, ctlCallback, pos + chunklen - 1)
    pos = pos + chunklen
  end

  chunk = text:sub(pos)
  CTL:SendAddonMessage(prio, prefix, MSG_MULTI_LAST .. chunk, distribution, target, queueName, ctlCallback, textlen)
end

---@param payload table
---@return string
local function EncodeSyncPayload(payload)
  local serialized = LibSerialize:Serialize(payload)
  local compressed = LibDeflate:CompressDeflate(serialized)
  return LibDeflate:EncodeForWoWAddonChannel(compressed)
end

---@param prefix string
---@param payload table
---@param distribution string
---@param priority string
---@param target string?
local function SendPayload(prefix, payload, distribution, priority, target)
  SendOnChannel(prefix, EncodeSyncPayload(payload), distribution, priority or "NORMAL", nil, nil, target)
end

local function MarkSuccessfulSync(peer)
  local sync = Data.db.global.sync
  sync.lastSuccessfulSyncAt = time()
  sync.lastSuccessfulSyncPeer = peer or ""
end

---@param sender string
---@param distribution string?
---@param versions table<string, number>?
local function MarkPeerSeen(sender, distribution, versions)
  if not sender or sender == "" then return end
  local peer = syncPeers[sender] or { versions = {} }
  syncPeers[sender] = peer
  peer.lastSeen = GetTime()
  if distribution then peer.distribution = distribution end
  if type(versions) == "table" then
    peer.versions = versions
  elseif type(peer.versions) ~= "table" then
    peer.versions = {}
  end
end

local function GetActiveSyncPeers(filter)
  local now = GetTime()
  local active = {}
  for sender, peer in pairs(syncPeers) do
    if (not filter or filter[sender]) and peer.lastSeen and now - peer.lastSeen <= PEER_TIMEOUT_SECONDS then
      active[sender] = peer
    end
  end
  return active
end

---Session/persistent status for the tutorial checklist. Presence is session-only;
---the most recent confirmed character sync is persisted in SavedVariables.
function addon.Core:GetSyncPeerStatus()
  local active = GetActiveSyncPeers()
  local names = {}
  local newestSeen = 0
  for sender, peer in pairs(active) do
    table.insert(names, sender)
    newestSeen = math.max(newestSeen, peer.lastSeen or 0)
  end
  table.sort(names)
  local sync = Data.db.global.sync
  return {
    count = #names,
    names = names,
    newestSeen = newestSeen,
    lastSuccessfulSyncAt = sync.lastSuccessfulSyncAt or 0,
    lastSuccessfulSyncPeer = sync.lastSuccessfulSyncPeer or "",
  }
end

---Serialize+compress+send one character record. Shared by the automatic
---per-change broadcast and the manual "Sync Now".
---@param character AE_Character
---@param password string
---@param channels string[] AceComm distributions to send on ("GUILD"/"PARTY"/"RAID"), one message per entry.
---@param forced boolean? True for a manual "Sync Now" push -- tells the receiver to apply this even if it's not strictly newer than what it already has (see OnCommReceived).
---@param batchId string? Shared by every character in one broadcast. Manual batches use it for the normal Sync Now summary; automatic batches use it only so the receiver can announce completion when that batch introduced at least one brand-new character.
---@param batchTotal number? How many characters are in this batchId's push -- how the receiver knows when the whole broadcast has arrived.
---@param priority string? AceComm priority ("BULK"/"NORMAL"/"ALERT"). Defaults to "BULK".
---@param transmissionId string? Unique id used for delivery ACK bookkeeping on both automatic and manual sends.
---@param onDone function? Called once every channel's LAST chunk has been dequeued by ChatThrottleLib -- i.e. once this character's transmission is truly finished going out on every channel, not just "some time has probably passed". Receives one argument: a list of channels where at least one chunk did NOT actually go out (empty if everything succeeded) -- see the comment below on why "reached the last chunk" and "actually delivered" aren't the same thing. PerformBroadcast's SendNext waits for this before starting the next character, instead of guessing a fixed delay -- see the comment on batchInProgress for why that matters: everyone's outgoing messages share the same AceComm sender identity (whichever character you're actually logged in on), so their multi-part reassembly streams share the exact same spool slot on the receiving end, and starting the next one before the last one's LAST chunk has gone out destroys it.
local function SendCharacterRecord(character, password, channels, forced, batchId, batchTotal, priority, transmissionId, onDone)
  local payload = {
    password = password,
    character = character,
    forced = forced or nil,
    batchId = batchId,
    batchTotal = batchTotal,
    transmissionId = transmissionId,
  }

  local encoded = EncodeSyncPayload(payload)

  local remainingChannels = #channels
  local doneFired = false
  local failedChannels = {}
  local function finish()
    if doneFired then return end
    doneFired = true
    if onDone then onDone(failedChannels) end
  end
  local function channelDone()
    remainingChannels = remainingChannels - 1
    if remainingChannels <= 0 then
      finish()
    end
  end

  local function doSend(channel)
    -- callbackFn(callbackArg, sent, total, didSend) fires once per
    -- underlying ~255-byte chunk. sent >= total is the LAST chunk having
    -- cleared ChatThrottleLib's queue -- but "reached the last chunk" is
    -- NOT the same as "every chunk actually went out": ChatThrottleLib
    -- only auto-retries a chunk that comes back as its own
    -- AddonMessageThrottle code. Anything else -- a genuine
    -- GeneralError, ChannelThrottle, being out of the group, or WoW:
    -- Midnight's newer combat/encounter restriction on outgoing addon
    -- messages -- is a PERMANENT failure for that one chunk, with no
    -- retry, and this callback still eventually reaches "the last chunk"
    -- regardless. So a failed chunk anywhere along the way means this
    -- character's data almost certainly arrived incomplete/corrupted on
    -- the other end, even though the send "finished" from our side.
    -- Track that per channel instead of only checking the final chunk.
    local channelFailed = false
    SendOnChannel(COMM_PREFIX, encoded, channel, priority or "BULK", function(_, sent, total, didSend)
      if not didSend then
        channelFailed = true
      end
      if sent >= total then
        if channelFailed then
          table.insert(failedChannels, channel)
        end
        channelDone()
      end
    end, nil)
  end

  -- Each channel now has its own ChatThrottleLib pipe (see SendOnChannel),
  -- so there's no bandwidth-hogging reason left to stagger them -- fire
  -- them all at once and let ChatThrottleLib round-robin bandwidth fairly
  -- between them.
  for _, channel in ipairs(channels) do
    doSend(channel)
  end
end

---Every distribution channel worth sending on right now, filtered by the
---"Sync Channel" setting (BOTH/GUILD/PARTY -- see Data.lua's sync.channel
---default). BOTH is deliberately NOT "pick the best one" -- Sync doesn't
---know which channel the OTHER account is actually listening on (e.g.
---your main is in a guild, but the alt account you're syncing to is a
---trial that can't join guilds, and the only thing you two share right
---now is a party) -- so it sends on every channel that currently applies:
---GUILD if you're in a guild, and RAID or PARTY if you're grouped.
---Sending on more than one channel is cheap and harmless -- the receiving
---side already dedupes by lastUpdate, so a duplicate arriving on a second
---channel is just silently ignored. Setting it to GUILD or PARTY
---specifically restricts it to just that one, e.g. for testing one
---channel in isolation.
---@param verbose boolean?
---@return string[] channels empty if none apply
local function GetUsableChannels(verbose)
  local setting = Data.db.global.sync.channel or "BOTH"
  local channels = {}
  if setting ~= "PARTY" and IsInGuild() then table.insert(channels, "GUILD") end
  if setting ~= "GUILD" then
    if IsInRaid() then
      table.insert(channels, "RAID")
    elseif IsInGroup() then
      table.insert(channels, "PARTY")
    end
  end
  if #channels == 0 and verbose then
    if setting == "GUILD" then
      addon.Core:Print("Sync: not sending, Sync Channel is set to Guild but you're not in a guild.")
    elseif setting == "PARTY" then
      addon.Core:Print("Sync: not sending, Sync Channel is set to Party/Raid but you're not in a group.")
    else
      addon.Core:Print("Sync: not sending, you're not in a guild, raid, or party (Sync needs one of those to have a channel to send on).")
    end
  end
  return channels
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

---Checks Sync is actually usable right now (enabled, password set, and at
---least one channel to send it on), optionally printing why not. Shared by
---every send path below.
---@param verbose boolean?
---@return string? password nil if sync can't run right now
---@return string[]? channels nil if sync can't run right now
local function GetUsablePassword(verbose)
  if not Data.db.global.sync.enabled then
    if verbose then addon.Core:Print("Sync: not sending, Sync is disabled.") end
    return nil, nil
  end
  local password = Data.db.global.sync.password
  if not password or password == "" then
    if verbose then addon.Core:Print("Sync: not sending, no password set.") end
    return nil, nil
  end
  local channels = GetUsableChannels(verbose)
  if #channels == 0 then
    return nil, nil
  end
  return password, channels
end

---True if this character is allowed to go out over Sync right now: if a
---Main WoW Account is set, only characters filed under it qualify (so
---characters that came IN from someone else's sync never get echoed back
---out); with no Main account set, everything tracked qualifies. (In
---practice a Main account is always set now -- Data:Initialize() defaults
---one in -- but this stays defensive in case it's ever cleared.)
---@param character AE_Character
---@return boolean
local function IsEligibleToSend(character)
  local mainAccountId = Data.GetMainAccountId and Data:GetMainAccountId()
  if not mainAccountId then return true end
  local characterAccountId = character.accountId or Data:EnsureDefaultAccount()
  return characterAccountId == mainAccountId
end

---True if this specific character's own checkbox is on (in the Characters
---menu), and its WoW Account isn't disabled either. Separate from
---IsEligibleToSend, which only checks Main-account membership: this is
---what GetBroadcastCandidates uses to decide whether the CURRENT character
---fallback should still respect being unchecked.
---@param character AE_Character
---@return boolean
local function IsCharacterIndividuallyEnabled(character)
  if character.enabled == false then return false end
  local characterAccountId = character.accountId or Data:EnsureDefaultAccount()
  local account = Data.db.global.accounts[characterAccountId]
  if account and account.enabled == false then return false end
  return true
end

local function OnlySyncMaxLevelCharacters()
  return Data.db.global.sync.onlyMaxLevelCharacters ~= false
end

---Every character Sync should push out: every enabled character filed
---under the Main WoW Account (Data:GetSyncEligibleCharacters), plus the
---currently logged-in character fallback used by the existing sync path.
---When "Only Sync Max Level Characters" is enabled, both sources are
---filtered against Retail's current expansion cap so leveling characters
---never leave this account. Disabling it allows every otherwise-enabled
---character in the Main WoW Account, regardless of display filters.
---@return AE_Character[]
local function GetBroadcastCandidates()
  local candidates = {}
  local seen = {}
  local eligible = Data.GetSyncEligibleCharacters and Data:GetSyncEligibleCharacters() or Data:GetCharacters()
  for _, character in ipairs(eligible) do
    if not OnlySyncMaxLevelCharacters() or Data:IsMaxLevelCharacter(character) then
      table.insert(candidates, character)
      seen[character.GUID] = true
    end
  end

  local current = Data:GetCharacter()
  if current
    and not seen[current.GUID]
    and IsEligibleToSend(current)
    and IsCharacterIndividuallyEnabled(current)
    and (not OnlySyncMaxLevelCharacters() or Data:IsMaxLevelCharacter(current))
  then
    table.insert(candidates, current)
  end

  return candidates
end

---Re-resolve and revalidate a queued character immediately before its turn to send.
---This makes sharing changes live inside an already-running batch: disabling/moving a
---character or changing the max-level filter skips it before any new chunks start.
---@param GUID string
---@return AE_Character?
local function GetCurrentlyEligibleCharacter(GUID)
  if not GUID or GUID == "" then return nil end
  local character = Data.db.global.characters and Data.db.global.characters[GUID] or nil
  if not character then
    local current = Data:GetCharacter()
    if current and current.GUID == GUID then
      character = current
    end
  end
  if not character then return nil end
  if not IsEligibleToSend(character) or not IsCharacterIndividuallyEnabled(character) then return nil end
  if OnlySyncMaxLevelCharacters() and not Data:IsMaxLevelCharacter(character) then return nil end
  return character
end

local function BuildKnownCharacterVersions()
  local versions = {}
  for GUID, character in pairs(Data.db.global.characters or {}) do
    if type(GUID) == "string" and type(character) == "table" and type(character.lastUpdate) == "number" then
      versions[GUID] = character.lastUpdate
    end
  end
  return versions
end

local function PeerNeedsCharacter(peer, character)
  if not peer or type(peer.versions) ~= "table" then return true end
  local remoteVersion = tonumber(peer.versions[character.GUID])
  local localVersion = tonumber(character.lastUpdate) or 0
  return remoteVersion == nil or remoteVersion < localVersion
end

---@param character AE_Character
---@param peerFilter table<string, boolean>?
---@return boolean needsCharacter
---@return boolean hasPeer
local function AnyActivePeerNeedsCharacter(character, peerFilter)
  local hasPeer = false
  for _, peer in pairs(GetActiveSyncPeers(peerFilter)) do
    hasPeer = true
    if PeerNeedsCharacter(peer, character) then
      return true, true
    end
  end
  return false, hasPeer
end

local function IsCharacterAwaitingConfirmation(character)
  for _, confirmation in pairs(pendingConfirmations) do
    if confirmation.GUID == character.GUID and confirmation.lastUpdate == character.lastUpdate then
      return true
    end
  end
  return false
end

local function ConfirmationRetryKey(GUID, lastUpdate)
  return tostring(GUID) .. "|" .. tostring(lastUpdate or 0)
end

---Start the ACK deadline only after every chunk has actually left this client. Automatic
---records get a small bounded retry budget if a live peer still reports the record missing.
---@param transmissionId string
local function ArmConfirmationTimeout(transmissionId)
  local confirmation = pendingConfirmations[transmissionId]
  if not confirmation or confirmation.timeoutArmed then return end
  confirmation.timeoutArmed = true

  C_Timer.After(ACK_TIMEOUT_SECONDS, function()
    local current = pendingConfirmations[transmissionId]
    if current ~= confirmation then return end
    pendingConfirmations[transmissionId] = nil

    if confirmation.manual or not Data.db.global.sync.enabled then return end
    local character = GetCurrentlyEligibleCharacter(confirmation.GUID)
    if not character or tonumber(character.lastUpdate) ~= tonumber(confirmation.lastUpdate) then return end

    local needsCharacter, hasPeer = AnyActivePeerNeedsCharacter(character)
    if not hasPeer or not needsCharacter then return end

    local retryKey = ConfirmationRetryKey(confirmation.GUID, confirmation.lastUpdate)
    local retries = confirmationRetryCounts[retryKey] or 0
    if retries >= ACK_RETRY_MAX then return end

    confirmationRetryCounts[retryKey] = retries + 1
    catchupPendingGUIDs[confirmation.GUID] = true
    addon.Core:RequestSyncBroadcast()
  end)
end

QueueCatchUpFromPeerVersions = function(versions)
  if type(versions) ~= "table" then return end
  local queued = false
  for _, character in ipairs(GetBroadcastCandidates()) do
    local remoteVersion = tonumber(versions[character.GUID])
    local localVersion = tonumber(character.lastUpdate) or 0
    if remoteVersion == nil or remoteVersion < localVersion then
      catchupPendingGUIDs[character.GUID] = true
      queued = true
    end
  end
  if queued then
    addon.Core:RequestSyncBroadcast()
  end
end

SendSyncHello = function(target, responseTo, requestId, force)
  if not Data.db.global.sync.enabled or InCombatLockdown() then return false end
  local password = Data.db.global.sync.password
  if not password or password == "" then return false end

  local now = GetTime()
  if not target and not force and now - lastHelloAt < HELLO_MIN_INTERVAL_SECONDS then
    return false
  end

  local payload = {
    password = password,
    hello = true,
    helloId = NewSyncId("H"),
    response = target ~= nil or nil,
    responseTo = responseTo,
    requestId = requestId,
    versions = BuildKnownCharacterVersions(),
  }

  if target then
    SendPayload(CONTROL_PREFIX, payload, "WHISPER", "ALERT", target)
    return true
  end

  local channels = GetUsableChannels(false)
  if #channels == 0 then return false end
  lastHelloAt = now
  for _, channel in ipairs(channels) do
    SendPayload(CONTROL_PREFIX, payload, channel, "NORMAL")
  end
  return true
end

ScheduleSyncHello = function(delay, force)
  if syncHelloTimer then
    syncHelloTimer:Cancel()
    syncHelloTimer = nil
  end

  local scheduledDelay = delay or 0.5
  if not force then
    local remaining = HELLO_MIN_INTERVAL_SECONDS - (GetTime() - lastHelloAt)
    if remaining > scheduledDelay then
      scheduledDelay = remaining + 0.05
    end
  end

  syncHelloTimer = C_Timer.NewTimer(math.max(0, scheduledDelay), function()
    syncHelloTimer = nil
    SendSyncHello(nil, nil, nil, force)
  end)
end

---Called when Enable Sync/password/channel/eligibility changes. Coalesce bursts and obey
---the ordinary HELLO cooldown; a manual Sync Now reconciliation remains the only path that
---intentionally bypasses this debounce.
function addon.Core:AnnounceSyncPresence()
  ScheduleSyncHello(0.25, false)
end

---Close a completed character batch with the actual number of records that went out. This
---matters when sharing eligibility changes while the batch is running: receivers no longer
---wait for characters that were deliberately skipped after the batch began.
local function SendBatchDone(password, channels, batchId, sentCount, manual)
  if not batchId then return end
  local payload = {
    password = password,
    batchDone = true,
    batchId = batchId,
    batchTotal = sentCount or 0,
    manual = manual or nil,
  }
  for _, channel in ipairs(channels) do
    SendPayload(COMM_PREFIX, payload, channel, "NORMAL")
  end
end

---@param verbose boolean? Deliberate manual "Sync Now": after a short peer/version reconciliation, sends only eligible characters that at least one responding peer is missing or has an older version of. False/nil is the automatic background path: silent, and sends changed records plus records explicitly requested by peer catch-up.
---@param peerFilter table<string, boolean>? Manual reconciliation responders to target.
local function PerformBroadcast(verbose, peerFilter)
  broadcastPending = false

  -- Never sync during actual combat -- checked first, before anything
  -- else, so nothing about an in-progress batch or the throttle timer
  -- matters if this is true. Being inside a raid or Mythic+ instance is
  -- fine; being actively IN a pull is not -- InCombatLockdown() already
  -- draws exactly that line. Manual "Sync Now" refuses outright (no
  -- supersede queued either) rather than queuing up to fire the moment
  -- combat ends, since the person clicking it right this second is
  -- exactly the scenario worth avoiding: sending addon traffic mid-pull
  -- risks tainting the UI, and there's no good reason Sync can't just
  -- wait until after the pull instead. The automatic path remembers the
  -- interrupted work and resumes quietly once combat/restrictions clear.
  if InCombatLockdown() then
    if verbose then
      addon.Core:Print("Sync: not sending, you're in combat -- Sync never runs during combat, even inside a raid or Mythic+ (being in the instance is fine; being in a pull isn't). Try again once combat ends.")
    else
      QueueAutomaticResume()
    end
    return
  end

  -- Never let two broadcasts from this client overlap -- see the comment
  -- on batchInProgress above for why that's a correctness issue, not just
  -- a pacing one. Repeated Sync Now clicks while a manual batch is already
  -- moving are deliberately a no-op: the existing batch simply continues
  -- from its current character, so a double-click can never restart the
  -- list and resend characters that already finished. The automatic path
  -- still quietly retries shortly instead.
  if batchInProgress then
    if not verbose then
      C_Timer.After(BROADCAST_STAGGER_SECONDS, function()
        addon.Core:RequestSyncBroadcast()
      end)
    end
    return
  end

  local password, channels = GetUsablePassword(verbose)
  if not password then return end

  local now = time()
  if not verbose and now - lastBroadcastAt < BROADCAST_MIN_INTERVAL_SECONDS then
    C_Timer.After(BROADCAST_MIN_INTERVAL_SECONDS - (now - lastBroadcastAt) + 1, function()
      addon.Core:RequestSyncBroadcast()
    end)
    return
  end

  local candidates = GetBroadcastCandidates()
  if #candidates == 0 then
    if verbose then addon.Core:Print("Sync: no eligible characters to send (check they're enabled, and filed under your Main WoW Account).") end
    return
  end

  -- A fresh manual Sync Now is a reconciliation, not a blind resend: only
  -- characters at least one responding peer reports missing/stale are sent.
  -- If an earlier manual batch was interrupted, resume its exact pending GUIDs
  -- without re-negotiating or repeating characters that already completed.
  local toSend = {}
  if verbose then
    local resumingManualBatch = manualPendingGUIDs and next(manualPendingGUIDs) ~= nil
    if resumingManualBatch then
      local eligibleGUIDs = {}
      for _, character in ipairs(candidates) do
        eligibleGUIDs[character.GUID] = true
        if manualPendingGUIDs[character.GUID] then
          table.insert(toSend, character)
        end
      end

      for GUID in pairs(manualPendingGUIDs) do
        if not eligibleGUIDs[GUID] then
          manualPendingGUIDs[GUID] = nil
        end
      end
    else
      for _, character in ipairs(candidates) do
        local needsCharacter = AnyActivePeerNeedsCharacter(character, peerFilter)
        if needsCharacter and not IsCharacterAwaitingConfirmation(character) then
          table.insert(toSend, character)
        end
      end
    end
  else
    for _, character in ipairs(candidates) do
      if catchupPendingGUIDs[character.GUID] or HasCharacterChangedSinceLastSync(character) then
        table.insert(toSend, character)
      end
    end
  end

  lastBroadcastAt = now

  if #toSend == 0 then
    if verbose then
      local activePeers = GetActiveSyncPeers(peerFilter)
      if not next(activePeers) then
        addon.Core:Print("Sync: no compatible Sync peer responded. Keep the other account online on the same Sync Channel and try again.")
      else
        addon.Core:Print("Sync: all detected peers are already up to date. Nothing to send.")
      end
    end
    return
  end

  if verbose then
    manualPendingGUIDs = manualPendingGUIDs or {}
    for _, character in ipairs(toSend) do
      manualPendingGUIDs[character.GUID] = true
    end
  end

  -- Send one character at a time, and don't start the next one until the
  -- previous one's transmission is actually confirmed finished on every
  -- channel (SendCharacterRecord's onDone) -- not just "some fixed delay
  -- has probably been enough". Everyone's outgoing messages share the same
  -- AceComm sender identity (whichever character you're logged in on
  -- physically sends them all), so their multi-part reassembly streams on
  -- the receiving end share the exact same spool slot; starting the next
  -- character's transmission before the previous one's LAST chunk has
  -- gone out destroys whatever was mid-reassembly over there, silently.
  -- A fixed timer was only ever a guess at how long that takes -- this
  -- waits for the real signal instead.
  local sentNames = {}
  local index = 0
  local startedAt = GetTime()
  -- Unique per broadcast, not per character. Manual Sync Now uses this
  -- to print its normal receive summary. Automatic sync also carries a
  -- batch id now, but remains silent unless the receiver actually learns
  -- about at least one brand-new character; in that one case it prints a
  -- single completion line after the whole automatic batch has been
  -- processed. GetTime() has enough resolution for broadcasts here.
  local batchId = NewSyncId(verbose and "M" or "A")
  if verbose then
    activeBatchId = batchId
    activeBatchConfirmedBy = {}
  end
  batchInProgress = true
  local function SendNext()
    -- Re-check every step, not just once at the start -- unchecking
    -- "Enable Sync" mid-send should stop the rest of the batch right
    -- away instead of letting an in-flight multi-character send keep
    -- firing every few seconds regardless. Combat starting mid-send stops
    -- it the same way -- see the InCombatLockdown check at the top of
    -- PerformBroadcast for why. The character already in flight when
    -- combat started still finishes normally (it's already been handed
    -- to ChatThrottleLib); this only stops the NEXT one from starting.
    if not Data.db.global.sync.enabled then
      if verbose then
        addon.Core:Print(format("Sync: stopped -- Sync was disabled mid-send. %d of %d character(s) had already gone out: %s. Sync Now will continue with only the remaining character(s) after Sync is enabled again.", #sentNames, #toSend, #sentNames > 0 and JoinWithAnd(sentNames) or "none"))
      end
      if verbose then
        activeBatchId = nil
        activeBatchConfirmedBy = {}
      end
      batchInProgress = false
      return
    end
    if InCombatLockdown() then
      if verbose then
        addon.Core:Print(format("Sync: stopped -- you're in combat now. %d of %d character(s) had already gone out: %s. Sync Now will continue with only the remaining character(s) after combat.", #sentNames, #toSend, #sentNames > 0 and JoinWithAnd(sentNames) or "none"))
      else
        QueueAutomaticResume()
      end
      if verbose then
        activeBatchId = nil
        activeBatchConfirmedBy = {}
      end
      batchInProgress = false
      return
    end

    index = index + 1
    local queuedCharacter = toSend[index]
    if not queuedCharacter then
      -- Tell receivers the ACTUAL completed batch size. If sharing eligibility changed
      -- mid-send, this closes the batch without making them wait for skipped records.
      SendBatchDone(password, channels, batchId, #sentNames, verbose == true)

      if verbose then
        -- Who has confirmed receiving ANY character of this batch so
        -- far -- see activeBatchConfirmedBy above. Often non-empty by
        -- now: acks trickle in throughout the send, and a big batch can
        -- take minutes. Omitted entirely if nobody has ack'd yet (e.g. a
        -- very fast, small send finishing before the first ack gets
        -- back), rather than claiming a recipient we don't actually know.
        local confirmedBy = {}
        for confirmedName in pairs(activeBatchConfirmedBy) do
          table.insert(confirmedBy, confirmedName)
        end
        local toClause = #confirmedBy > 0 and format(" to %s", JoinWithAnd(confirmedBy)) or ""
        local sentList = #sentNames > 0 and JoinWithAnd(sentNames) or "none"
        addon.Core:Print(format("Sync: |cff33ff99successfully|r sent %d character(s)%s over %s in %s: %s", #sentNames, toClause, JoinWithAnd(channels), FormatDuration(GetTime() - startedAt), sentList))
        if manualPendingGUIDs and next(manualPendingGUIDs) ~= nil then
          local pendingCount = 0
          for _ in pairs(manualPendingGUIDs) do pendingCount = pendingCount + 1 end
          addon.Core:Print(format("Sync: %d character(s) still pending. Sync Now will continue with only those character(s).", pendingCount))
        else
          manualPendingGUIDs = nil
        end
        activeBatchId = nil
        activeBatchConfirmedBy = {}
      end
      batchInProgress = false
      return
    end

    -- Re-check this exact GUID at the moment its turn begins. A user can change
    -- character/account sharing or the max-level filter while a long batch is running;
    -- queued records that are no longer eligible are skipped before any chunks start.
    local character = GetCurrentlyEligibleCharacter(queuedCharacter.GUID)
    if not character then
      catchupPendingGUIDs[queuedCharacter.GUID] = nil
      if manualPendingGUIDs then
        manualPendingGUIDs[queuedCharacter.GUID] = nil
      end
      C_Timer.After(0, SendNext)
      return
    end

    local name = format("%s-%s", character.info.name or "?", character.info.realm or "?")
    if verbose then
      addon.Core:Print(format("Sync: sending %d/%d -- %s...", index, #toSend, name))
    end
    local transmissionId = NewSyncId("T")
    pendingConfirmations[transmissionId] = {
      GUID = character.GUID,
      lastUpdate = character.lastUpdate,
      manual = verbose == true,
      batchId = batchId,
    }

    SendCharacterRecord(character, password, channels, verbose, batchId, #toSend, verbose and "NORMAL" or "BULK", transmissionId, function(failedChannels)
      -- A chunk permanently failing mid-transmission (not the throttle
      -- ChatThrottleLib retries on its own) means this character's data
      -- almost certainly did not arrive intact -- WoW: Midnight's
      -- restriction on outgoing addon messages during an active
      -- raid/M+ encounter is one realistic cause, alongside plain
      -- disconnects or being kicked from the group mid-send.
      if #failedChannels > 0 then
        pendingConfirmations[transmissionId] = nil
        if verbose then
          addon.Core:Print(format("Sync: WARNING -- %s over %s did not fully send -- its data is likely incomplete on the other end. If you're in an active raid encounter or Mythic+ run, WoW itself may be restricting outgoing addon messages until it ends; try Sync Now again afterward.", name, JoinWithAnd(failedChannels)))
        else
          -- Do not mark this character as synced and do not start another background record
          -- while the transport is being rejected. PLAYER_REGEN_ENABLED or the addon-restriction
          -- event below will retry this character plus anything that never started.
          QueueAutomaticResume()
          batchInProgress = false
          return
        end
      else
        -- Only record success once every channel's chunks really left this client. Marking the
        -- character at queue time could make a combat-restricted transmission look complete and
        -- suppress the retry until that character happened to change again.
        MarkCharacterSynced(character)
        catchupPendingGUIDs[character.GUID] = nil
        if manualPendingGUIDs then
          manualPendingGUIDs[character.GUID] = nil
        end
        table.insert(sentNames, name)
        ArmConfirmationTimeout(transmissionId)
      end

      -- Confirmed done going out on every channel. Still wait a short,
      -- fixed buffer on top of that -- our confirmation only covers OUR
      -- own client handing the last chunk off; it says nothing about how
      -- long the other side takes to actually receive and finish
      -- reassembling it, so a little slack here is cheap insurance.
      C_Timer.After(BROADCAST_STAGGER_SECONDS, SendNext)
    end)
  end
  SendNext()
end

---Emergency escape hatch: force-clears the "a send is already in
---progress" guard (batchInProgress above) immediately. Called when Sync
---gets disabled, so turning it off actually frees up Sync Now again right
---away instead of leaving it locked out until the in-flight send
---eventually finishes on its own (there's no automatic timeout for
---that -- a genuinely slow send is waited out, not abandoned).
function addon.Core:ResetSyncBatchGuard()
  batchInProgress = false
  automaticResumePending = false
  activeBatchId = nil
  activeBatchConfirmedBy = {}
  manualReconcileRequestId = nil
  manualReconcileResponders = nil
  if manualReconcileTimer then
    manualReconcileTimer:Cancel()
    manualReconcileTimer = nil
  end
  if automaticResumeTimer then
    automaticResumeTimer:Cancel()
    automaticResumeTimer = nil
  end
end

---Call this after anything that changed the logged-in character's data.
---Debounced + throttled -- safe to call as often as you want. Completely
---silent -- see the file header.
function addon.Core:RequestSyncBroadcast()
  if broadcastPending then return end
  broadcastPending = true
  C_Timer.After(BROADCAST_DEBOUNCE_SECONDS, PerformBroadcast)
end

---Force a peer/version reconciliation right now. Matching peers answer with the
---versions they already know; only eligible Main-account characters they report
---missing/outdated are sent. Prints progress/results for manual testing.
function addon.Core:ForceSyncBroadcast()
  -- An interrupted manual batch already knows exactly which GUIDs remain; resume it
  -- directly instead of starting a second reconciliation/request.
  if manualPendingGUIDs and next(manualPendingGUIDs) ~= nil then
    PerformBroadcast(true)
    return
  end
  if batchInProgress or manualReconcileRequestId then return end

  if InCombatLockdown() then
    PerformBroadcast(true) -- preserve the existing explanatory chat message
    return
  end

  local password = GetUsablePassword(true)
  if not password then return end

  manualReconcileRequestId = NewSyncId("R")
  manualReconcileResponders = {}
  addon.Core:Print("Sync: checking detected peers for missing or outdated characters...")

  if not SendSyncHello(nil, nil, manualReconcileRequestId, true) then
    manualReconcileRequestId = nil
    manualReconcileResponders = nil
    addon.Core:Print("Sync: couldn't send the reconciliation request on the selected Sync Channel.")
    return
  end

  manualReconcileTimer = C_Timer.NewTimer(MANUAL_RECONCILE_WAIT_SECONDS, function()
    manualReconcileTimer = nil
    local responders = manualReconcileResponders or {}
    manualReconcileRequestId = nil
    manualReconcileResponders = nil
    PerformBroadcast(true, responders)
  end)
end

-- Which top-level Data.db.global keys are display/behavior PREFERENCES --
-- the kind of thing "Sync Addon Settings" shares -- as opposed to actual
-- game data (characters, accounts) or Sync's own configuration
-- (password, enabled, channel, and Sync's internal bookkeeping), which
-- this deliberately never touches: sending your password over the very
-- channel it's meant to gate would defeat the whole point of it, and
-- remotely flipping someone's Enable Sync or Sync Channel on their other
-- account is exactly the kind of surprise this feature should never
-- cause. Two entries (minimap, liqui) are handled separately below
-- instead of listed here, because only PART of each is a shareable
-- preference -- the rest is per-client screen position/size that would
-- look wrong copied onto a different monitor/resolution.
local SHAREABLE_SETTINGS_KEYS = {
  "sorting", "showTiers", "showScores", "showAffixColors", "showAffixHeader",
  "showNonMaxLevelCharacters", "showZeroRatedCharacters", "showItemLevel",
  "showEquippedItemLevel", "showItemLevelDecimals", "showRealms",
  "showGuildInformation", "showRating", "showCurrentKeystone", "currentCharacterMarker",
  "currentCharacterMarkerColor", "announceKeystones", "announceResets",
  "vault", "prey", "raids", "dungeons", "world", "currencies", "weeklies",
  "seasonalChores", "trackerOverrides", "useRIOScoreColor", "interface",
}

---Builds the settings blob "Sync Addon Settings" sends -- every key in
---SHAREABLE_SETTINGS_KEYS, plus just the toggle parts of minimap (not its
---screen position) and liqui (just column-visibility, not window
---position/size).
---@return table
local function BuildSettingsPayload()
  local settings = {}
  for _, key in ipairs(SHAREABLE_SETTINGS_KEYS) do
    settings[key] = Data.db.global[key]
  end
  settings.minimap = { hide = Data.db.global.minimap.hide, lock = Data.db.global.minimap.lock }
  settings.liqui = { tables = Data.db.global.liqui.tables }
  return settings
end

---Applies a received settings blob (see BuildSettingsPayload) onto this
---client's own Data.db.global, then refreshes the UI so the change is
---visible immediately.
---@param settings table
local function ApplySettingsPayload(settings)
  for _, key in ipairs(SHAREABLE_SETTINGS_KEYS) do
    if settings[key] ~= nil then
      Data.db.global[key] = settings[key]
    end
  end
  if settings.minimap then
    Data.db.global.minimap.hide = settings.minimap.hide
    Data.db.global.minimap.lock = settings.minimap.lock
    if addon.Libs.LibDBIcon then
      addon.Libs.LibDBIcon:Refresh(addon.name, Data.db.global.minimap)
    end
  end
  if settings.liqui and settings.liqui.tables then
    Data.db.global.liqui.tables = settings.liqui.tables
  end
  addon.Core:Render()
end

---Manually shares this client's addon settings (see
---SHAREABLE_SETTINGS_KEYS -- NEVER character data, NEVER Sync's own
---password/enabled/channel) with whoever else has AlterEgo, Sync
---enabled, and the same password, over whichever channel(s) Sync
---Channel currently applies. Deliberately only reachable from the "Sync
---Addon Settings" button's confirmation popup -- there is no automatic
---path to this, ever, unlike character sync's per-change background
---broadcast. Respects the same combat lockout as everything else here.
function addon.Core:ShareSettings()
  if InCombatLockdown() then
    addon.Core:Print("Sync: not sharing settings, you're in combat.")
    return
  end

  local password, channels = GetUsablePassword(true)
  if not password then return end

  local payload = {
    password = password,
    settingsShare = true,
    settings = BuildSettingsPayload(),
  }
  local serialized = LibSerialize:Serialize(payload)
  local compressed = LibDeflate:CompressDeflate(serialized)
  local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)

  for _, channel in ipairs(channels) do
    SendOnChannel(COMM_PREFIX, encoded, channel, "NORMAL")
  end

  addon.Core:Print(format("Sync: sent your addon settings over %s.", JoinWithAnd(channels)))
end

-- Received characters that arrived while you were in combat -- held here
-- instead of touching Data.db/rebuilding the main window mid-fight (that
-- Render() rebuilds a decent chunk of UI, which is exactly the kind of
-- thing that causes a hitch during a pull). Applied automatically the
-- moment combat ends (PLAYER_REGEN_ENABLED, below).
local pendingCombatApplies = {} -- [GUID] = {character, isNew, sender, distribution, payload}; auto-batch metadata is kept so completion waits until the queued record is actually applied

-- Which senders we've already warned about an unreadable message --
-- session-only. See where it's used in OnCommReceived for why.
local warnedCorrupted = {}

-- Dedupes the EXACT same update arriving on more than one channel -- e.g.
-- Sync Channel set to "Both" sends the identical payload over GUILD and
-- PARTY at once, and both copies decode and reassemble independently
-- (different channels never share a reassembly slot, so neither gets
-- corrupted by the other -- see the header comment on batchInProgress in
-- the sending code). Without this, the SAME update would get applied and
-- Render()'d twice, and -- for a forced "Sync Now" push -- ack'd back to
-- the sender twice. Keyed by GUID + the character's own lastUpdate stamp,
-- so a genuinely NEWER update for the same character (a real, separate
-- change) is never mistaken for a duplicate.
local processedUpdates = {}

---Clear session-only Sync bookkeeping tied to a character that was explicitly
---removed from AlterEgo. Persistent lastSentUpdate metadata is cleared by
---Data:DeleteCharacter itself.
---@param GUID string
function addon.Core:ForgetSyncCharacterMetadata(GUID)
  if not GUID or GUID == "" then return end

  pendingCombatApplies[GUID] = nil
  catchupPendingGUIDs[GUID] = nil
  for transmissionId, confirmation in pairs(pendingConfirmations) do
    if confirmation.GUID == GUID then
      pendingConfirmations[transmissionId] = nil
    end
  end
  for _, peer in pairs(syncPeers) do
    if peer.versions then peer.versions[GUID] = nil end
  end

  local prefix = GUID .. "|"
  for updateKey in pairs(processedUpdates) do
    if string.sub(updateKey, 1, #prefix) == prefix then
      processedUpdates[updateKey] = nil
    end
  end
end

-- How long to wait, after the most recently-arrived character of an
-- in-progress incoming batch (see TrackBatchArrival below), before giving
-- up on the rest and printing whatever showed up anyway. Generous on
-- purpose: individual characters in a big Sync Now push have taken
-- several minutes each on a congested channel in testing, so this needs
-- real slack, not just a few seconds.
local BATCH_RECEIVE_TIMEOUT_SECONDS = 120

-- Tracks in-progress "Sync Now" pushes arriving from elsewhere, so this
-- side can print its OWN "received" summary once everything from one
-- push has shown up -- mirroring the sender's "successfully sent" line.
-- Keyed by sender.."|"..batchId (see SendCharacterRecord's batchId).
-- [key] = { total, names = {}, firstAt = GetTime() }
local incomingBatches = {}

-- Automatic batches stay silent for ordinary updates. If an automatic
-- catch-up introduces one or more brand-new characters, remember those
-- names per sender until an automatic batch from that sender fully
-- completes. This survives a transport/combat interruption: the first
-- partial batch can time out, the retry can contain only existing records,
-- and the user still gets exactly one truthful "finished" notice once the
-- catch-up actually reaches a complete batch.
local incomingAutomaticBatches = {}
local pendingAutomaticNewNotices = {} -- [sender] = { names = {}, seen = {}, channels = {}, firstAt = GetTime() }

local function FinishIncomingAutomaticBatch(sender, key, batch)
  if not batch or incomingAutomaticBatches[key] ~= batch then return end
  incomingAutomaticBatches[key] = nil
  local notice = pendingAutomaticNewNotices[sender]
  if notice and #notice.names > 0 then
    local channels = {}
    for channel in pairs(notice.channels) do
      table.insert(channels, channel)
    end
    table.sort(channels)
    addon.Core:Print(format(
      "Sync: |cff33ff99automatic sync finished successfully|r -- received %d new character(s) over %s in %s from %s: %s. Existing characters will continue updating silently; you'll only be notified again when new characters are received.",
      #notice.names, JoinWithAnd(channels), FormatDuration(GetTime() - notice.firstAt), sender, JoinWithAnd(notice.names)
    ))
    pendingAutomaticNewNotices[sender] = nil
  end
end

---@param sender string
---@param distribution string
---@param payload table
---@param remote AE_Character
---@param isNew boolean
local function TrackAutomaticBatchCompletion(sender, distribution, payload, remote, isNew)
  if payload.forced or not payload.batchId or not payload.batchTotal then return end

  local characterName = format("%s-%s", remote.info and remote.info.name or "?", remote.info and remote.info.realm or "?")
  if isNew then
    local notice = pendingAutomaticNewNotices[sender]
    if not notice then
      notice = { names = {}, seen = {}, channels = {}, firstAt = GetTime() }
      pendingAutomaticNewNotices[sender] = notice
    end
    if not notice.seen[remote.GUID] then
      notice.seen[remote.GUID] = true
      table.insert(notice.names, characterName)
    end
  end

  local notice = pendingAutomaticNewNotices[sender]
  if notice then
    notice.channels[distribution] = true
  end

  local key = sender .. "|" .. tostring(payload.batchId)
  local batch = incomingAutomaticBatches[key]
  if not batch then
    batch = { total = payload.batchTotal, count = 0 }
    incomingAutomaticBatches[key] = batch
    C_Timer.After(BATCH_RECEIVE_TIMEOUT_SECONDS, function()
      -- Never claim completion for an incomplete batch. Keep any pending
      -- new-character notice so the retry can close it out later.
      if incomingAutomaticBatches[key] == batch then
        incomingAutomaticBatches[key] = nil
      end
    end)
  end

  batch.count = batch.count + 1
  if batch.count >= batch.total then
    FinishIncomingAutomaticBatch(sender, key, batch)
  end
end

---Called once per character arriving from a forced "Sync Now" push that
---carries batch info (payload.batchId/batchTotal). Automatic batches also
---carry these fields, but are handled separately above and only announce
---completion when they introduced a new character. Accumulates names
---and channels for that batch and, once every character in it has
---arrived (or this batch goes quiet for BATCH_RECEIVE_TIMEOUT_SECONDS),
---prints one summary line mirroring the sender's own "successfully sent"
---one, colored the same way.
local function FinishIncomingManualBatch(sender, key, batch)
  if not batch or incomingBatches[key] ~= batch then return end
  incomingBatches[key] = nil
  local elapsed = FormatDuration(GetTime() - batch.firstAt)
  if #batch.names >= batch.total then
    addon.Core:Print(format("Sync: |cff33ff99successfully|r received %d character(s) over %s in %s from %s: %s", #batch.names, JoinWithAnd(batch.channels), elapsed, sender, JoinWithAnd(batch.names)))
  else
    addon.Core:Print(format("Sync: received %d of %d character(s) over %s in %s from %s (gave up waiting for the rest): %s", #batch.names, batch.total, JoinWithAnd(batch.channels), elapsed, sender, JoinWithAnd(batch.names)))
  end
end

---@param sender string
---@param distribution string
---@param payload table
---@param remote AE_Character
local function TrackBatchArrival(sender, distribution, payload, remote)
  if not (payload.forced and payload.batchId and payload.batchTotal) then return end

  local key = sender .. "|" .. tostring(payload.batchId)
  local batch = incomingBatches[key]
  if not batch then
    batch = { total = payload.batchTotal, names = {}, channels = {}, firstAt = GetTime() }
    incomingBatches[key] = batch
  end
  table.insert(batch.names, format("%s-%s", remote.info and remote.info.name or "?", remote.info and remote.info.realm or "?"))
  local channelAlreadySeen = false
  for _, existingChannel in ipairs(batch.channels) do
    if existingChannel == distribution then
      channelAlreadySeen = true
      break
    end
  end
  if not channelAlreadySeen then
    table.insert(batch.channels, distribution)
  end

  if #batch.names >= batch.total then
    FinishIncomingManualBatch(sender, key, batch)
  else
    C_Timer.After(BATCH_RECEIVE_TIMEOUT_SECONDS, function()
      FinishIncomingManualBatch(sender, key, batch)
    end)
  end
end

---A sender emits this after a batch fully finishes so receivers can reconcile the
---actual sent count if sharing eligibility changed while the batch was in progress.
local function TrackBatchDone(sender, distribution, payload)
  if not payload.batchId or payload.batchTotal == nil then return end
  local key = sender .. "|" .. tostring(payload.batchId)
  local total = math.max(0, tonumber(payload.batchTotal) or 0)

  if payload.manual then
    local batch = incomingBatches[key]
    if batch then
      batch.total = total
      if #batch.names >= batch.total then
        FinishIncomingManualBatch(sender, key, batch)
      end
    end
    return
  end

  local batch = incomingAutomaticBatches[key]
  if batch then
    batch.total = total
    if batch.count >= batch.total then
      FinishIncomingAutomaticBatch(sender, key, batch)
    end
  end
end

---Actually write a received character into the saved roster and refresh
---the UI. Called either immediately (out of combat) or once combat ends
---for anything that came in while you were fighting.
---
---Only prints anything when `isNew` is true -- i.e. this GUID wasn't in
---your roster before this sync. A routine update to a character you
---already have stays silent, whether it arrived from an automatic
---background sync or a manual "Sync Now" on the sender's end -- the
---receiving side has no way to tell which of those it was, and doesn't
---need to: "new character shows up" is the one receive-side event worth a
---chat line, everything else would just be noise.
---@param remote AE_Character
---@param isNew boolean
local function ApplyReceivedCharacter(remote, isNew)
  Data.db.global.characters[remote.GUID] = remote
  addon.Core:Render()
  if isNew then
    local account = remote.accountId and Data.db.global.accounts[remote.accountId]
    local accountName = account and account.name or remote.accountId or "?"
    addon.Core:Print(format("Sync: |cff33ff99received a new character|r: %s-%s (filed under WoW Account \"|cff33ff99%s|r\").", remote.info and remote.info.name or "?", remote.info and remote.info.realm or "?", accountName))
  end
end

addon.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
  for _, pending in pairs(pendingCombatApplies) do
    ApplyReceivedCharacter(pending.character, pending.isNew)
    TrackAutomaticBatchCompletion(pending.sender, pending.distribution, pending.payload, pending.character, pending.isNew)
  end
  wipe(pendingCombatApplies)
  ResumeAutomaticSyncIfPending()
  ScheduleSyncHello(0.5, false)
end, true)

-- Midnight can reject outgoing addon traffic for an encounter-specific restriction even when
-- the normal combat check alone is not enough to describe why a chunk failed. Resume a pending
-- automatic batch as soon as Blizzard reports that restriction becoming inactive.
addon.Events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(_, _, _, state)
  if state == Enum.AddOnRestrictionState.Inactive then
    ResumeAutomaticSyncIfPending()
  end
end, true)

---Whispers delivery confirmation back to whoever sent a character record.
---Automatic ACKs are silent; manual Sync Now ACKs keep their existing chat feedback.
---@param remote AE_Character
---@param sender string
---@param password string
---@param batchId string?
---@param transmissionId string?
---@param manual boolean?
local function SendAck(remote, sender, password, batchId, transmissionId, manual)
  local payload = {
    password = password,
    ack = true,
    GUID = remote.GUID,
    lastUpdate = remote.lastUpdate,
    name = remote.info and remote.info.name,
    realm = remote.info and remote.info.realm,
    batchId = batchId,
    transmissionId = transmissionId,
    manual = manual or nil,
  }
  SendPayload(COMM_PREFIX, payload, "WHISPER", "ALERT", sender)
end

---Same idea as SendAck, but for a "Sync Addon Settings" push -- whispers
---confirmation back to whoever shared their settings, once this client
---has actually applied them, so the sender's chat shows the other side
---really got it.
---@param sender string
---@param password string
local function SendSettingsAck(sender, password)
  local payload = {
    password = password,
    settingsAck = true,
  }
  SendPayload(COMM_PREFIX, payload, "WHISPER", "ALERT", sender)
end

function addon.Core:OnCommReceived(prefix, message, distribution, sender)
  if prefix ~= COMM_PREFIX and prefix ~= CONTROL_PREFIX then return end
  if not Data.db.global.sync.enabled then return end

  -- WoW echoes your own outgoing GUILD/PARTY/RAID (and even WHISPER-to-
  -- yourself) addon messages straight back to your own client via this
  -- same event -- you're a member of every channel you send to. Without
  -- this check, every OTHER alt in your own Main WoW Account (not just
  -- the one you're logged in on, which already has its own GUID-based
  -- filter below) shows up as "an update for MyOtherAlt" from yourself,
  -- gets correctly protected and ignored, and -- for a forced push --
  -- even acks itself right back to you, doubling every confirmation.
  -- None of that is wrong exactly, just noise: your own broadcast has
  -- nothing to tell your own client that it doesn't already know.
  if sender == Ambiguate(UnitName("player"), "none") then return end

  local password = Data.db.global.sync.password
  if not password or password == "" then return end

  -- Corrupted/incomplete data (or a genuine prefix collision with some
  -- unrelated addon that happens to also use "AEv1") -- warn once per
  -- sender per session rather than every single occurrence, in case
  -- something keeps producing these back to back.
  local decoded = LibDeflate:DecodeForWoWAddonChannel(message)
  if not decoded then
    if not warnedCorrupted[sender] then
      warnedCorrupted[sender] = true
      addon.Core:Print(format("Sync: %s from %s -- ignored. (couldn't decode the addon-channel data -- likely corrupted in transit, or an unrelated addon reusing the \"%s\" prefix)", DIM_RED_FONT_COLOR:WrapTextInColorCode("got an unreadable message"), tostring(sender), COMM_PREFIX))
    end
    return
  end
  local decompressed = LibDeflate:DecompressDeflate(decoded)
  if not decompressed then
    if not warnedCorrupted[sender] then
      warnedCorrupted[sender] = true
      addon.Core:Print(format("Sync: %s from %s -- ignored. (decoded fine, but failed to decompress -- the message is likely truncated or corrupted)", DIM_RED_FONT_COLOR:WrapTextInColorCode("got an unreadable message"), tostring(sender)))
    end
    return
  end
  local success, payload = LibSerialize:Deserialize(decompressed)
  if not success or type(payload) ~= "table" then
    if not warnedCorrupted[sender] then
      warnedCorrupted[sender] = true
      addon.Core:Print(format("Sync: %s from %s -- ignored. (decompressed fine, but failed to deserialize -- likely a different/incompatible AlterEgo version, or corrupted data)", DIM_RED_FONT_COLOR:WrapTextInColorCode("got an unreadable message"), tostring(sender)))
    end
    return
  end

  -- Wrong/blank password on either end -- silently ignore the data.
  -- Using the right password for who you're sharing with is on each
  -- person running this addon, not something worth flagging every time
  -- someone else's guildmate happens to run Sync with a different one.
  if payload.password ~= password then
    return
  end

  MarkPeerSeen(sender, distribution, payload.versions)

  -- Presence/version negotiation lives on its own prefix so it can never disturb
  -- character reassembly. A HELLO never changes settings or character ownership; it
  -- only causes each client to send its own Main-account records that the peer reports
  -- missing/outdated. Responses are direct whispers and never relayed onward.
  if prefix == CONTROL_PREFIX then
    if payload.hello then
      if payload.helloId then
        local helloKey = tostring(sender) .. "|" .. tostring(payload.helloId)
        if processedHelloIds[helloKey] then return end
        processedHelloIds[helloKey] = true
        C_Timer.After(300, function() processedHelloIds[helloKey] = nil end)
      end
      if payload.responseTo and manualReconcileRequestId and payload.responseTo == manualReconcileRequestId then
        manualReconcileResponders = manualReconcileResponders or {}
        manualReconcileResponders[sender] = true
      end
      QueueCatchUpFromPeerVersions(payload.versions)
      if not payload.response then
        local now = GetTime()
        local lastResponse = helloResponseAt[sender] or 0
        -- Explicit manual reconciliation requests always get a response. Ordinary
        -- presence chatter is rate-limited per peer so roster-event bursts cannot
        -- turn into a HELLO/response storm.
        if payload.requestId or now - lastResponse >= HELLO_RESPONSE_MIN_INTERVAL_SECONDS then
          if SendSyncHello(sender, payload.requestId, nil, true) then
            helloResponseAt[sender] = now
          end
        end
      end
    end
    return
  end

  -- A delivery confirmation from a previous forced push, not character
  -- data -- print it and stop, nothing else to process. If it's for the
  -- Sync Now push currently going out, also remember who confirmed, so
  -- the final "successfully sent" summary can name them.
  if payload.ack then
    local confirmation = payload.transmissionId and pendingConfirmations[payload.transmissionId] or nil
    -- A transmission id is unique to one batch. An ACK with a mismatched batch id is
    -- still proof that an older record arrived, but it must never satisfy the current
    -- attempt or produce current-batch chat feedback.
    local matchesCurrentAttempt = confirmation ~= nil
      and (not payload.batchId or not confirmation.batchId or payload.batchId == confirmation.batchId)
    if matchesCurrentAttempt then
      pendingConfirmations[payload.transmissionId] = nil
    else
      confirmation = nil
    end

    local GUID = payload.GUID or (confirmation and confirmation.GUID)
    local confirmedUpdate = payload.lastUpdate or (confirmation and confirmation.lastUpdate)
    if GUID and confirmedUpdate then
      local sync = Data.db.global.sync
      sync.lastConfirmedUpdate = sync.lastConfirmedUpdate or {}
      local previous = tonumber(sync.lastConfirmedUpdate[GUID]) or 0
      sync.lastConfirmedUpdate[GUID] = math.max(previous, tonumber(confirmedUpdate) or 0)
      confirmationRetryCounts[ConfirmationRetryKey(GUID, confirmedUpdate)] = nil
      local peer = syncPeers[sender]
      if peer then
        peer.versions = peer.versions or {}
        peer.versions[GUID] = confirmedUpdate
      end
      MarkSuccessfulSync(sender)
    end

    -- Manual Sync Now keeps explicit chat confirmations only for the exact active
    -- transmission. Automatic delivery ACKs and delayed ACKs from older attempts stay silent.
    if confirmation and confirmation.manual then
      addon.Core:Print(format("Sync: %s |cff33ff99confirmed|r receiving %s-%s.", tostring(sender), payload.name or "?", payload.realm or "?"))
    end
    if confirmation and payload.batchId and payload.batchId == activeBatchId then
      activeBatchConfirmedBy[sender] = true
    end
    return
  end

  if payload.batchDone then
    TrackBatchDone(sender, distribution, payload)
    return
  end

  -- Same, but for a "Sync Addon Settings" push.
  if payload.settingsAck then
    addon.Core:Print(format("Sync: %s |cff33ff99confirmed|r receiving your addon settings.", tostring(sender)))
    return
  end

  -- Shared addon settings from "Sync Addon Settings" -- see
  -- ApplySettingsPayload for exactly what this does and doesn't touch
  -- (never characters, never Sync's own password/enabled/channel).
  if payload.settingsShare then
    if type(payload.settings) == "table" then
      ApplySettingsPayload(payload.settings)
      addon.Core:Print(format("Sync: |cff33ff99applied addon settings|r shared by %s.", tostring(sender)))
      SendSettingsAck(sender, password)
    end
    return
  end

  local remote = payload.character
  if type(remote) ~= "table" or type(remote.GUID) ~= "string" or remote.GUID == "" then return end
  if remote.GUID == UnitGUID("player") then return end -- shouldn't happen, but never let a record overwrite the live character

  -- Same update already handled via another channel this session (see
  -- processedUpdates above) -- stop here, before the ack and before
  -- touching the character data, so neither happens twice for the one
  -- broadcast.
  local updateKey = remote.GUID .. "|" .. tostring(remote.lastUpdate)
  if processedUpdates[updateKey] then
    -- If the original ACK was lost, a retry carries a NEW transmission id. Re-ACK
    -- that retry without reapplying the same character. Copies of the same transmission
    -- arriving over Both/Guild+Party are still handled only once.
    if payload.transmissionId and not processedAckTransmissionIds[payload.transmissionId] then
      local transmissionId = payload.transmissionId
      processedAckTransmissionIds[transmissionId] = true
      C_Timer.After(600, function() processedAckTransmissionIds[transmissionId] = nil end)
      SendAck(remote, sender, password, payload.batchId, transmissionId, payload.forced)
      if payload.forced then
        TrackBatchArrival(sender, distribution, payload, remote)
      else
        TrackAutomaticBatchCompletion(sender, distribution, payload, remote, false)
      end
    end
    return
  end
  processedUpdates[updateKey] = true
  if payload.transmissionId then
    local transmissionId = payload.transmissionId
    processedAckTransmissionIds[transmissionId] = true
    C_Timer.After(600, function() processedAckTransmissionIds[transmissionId] = nil end)
  end

  local peer = syncPeers[sender]
  if peer then
    peer.versions = peer.versions or {}
    peer.versions[remote.GUID] = remote.lastUpdate
  end

  -- ACK every readable character record, automatic or manual. The sender uses this
  -- to distinguish "left my client" from "another Sync peer actually received it".
  SendAck(remote, sender, password, payload.batchId, payload.transmissionId, payload.forced)
  MarkSuccessfulSync(sender)
  if payload.forced then
    TrackBatchArrival(sender, distribution, payload, remote)
  end

  local existing = Data.db.global.characters[remote.GUID]
  local isNew = existing == nil

  -- Only accept if it's actually newer than what we already know -- keeps a
  -- stale record (an account that hasn't played in a while, relayed back
  -- around) from ever stomping fresher data, no matter which client sent it.
  -- Silent: this is the routine "nothing to do" case, not a problem.
  -- Skipped entirely for a forced push (manual "Sync Now" on the sender's
  -- end): that's a deliberate "make sure we're both fully caught up" action,
  -- so it applies even when the record isn't strictly newer.
  if not payload.forced and existing and existing.lastUpdate and remote.lastUpdate and remote.lastUpdate <= existing.lastUpdate then
    TrackAutomaticBatchCompletion(sender, distribution, payload, remote, isNew)
    return
  end

  if existing then
    -- Protect your own Main WoW Account -- if this character is already
    -- filed there, it's YOUR authoritative copy, so incoming sync data
    -- never overwrites it. Silent: this is normal, expected protection,
    -- not something worth a chat line every time it does its job.
    local mainAccountId = Data.GetMainAccountId and Data:GetMainAccountId()
    if mainAccountId and existing.accountId == mainAccountId then
      TrackAutomaticBatchCompletion(sender, distribution, payload, remote, isNew)
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
    -- Account tied to THIS password, creating one the first time this
    -- password brings anyone in. A different password (a different
    -- friend/account) gets its own separate account instead of everything
    -- piling into one bucket. Characters we already know about keep
    -- whatever account you filed them under (see above) -- this only
    -- decides where a character lands the very first time.
    -- Defensive: if Data.lua is out of date on this client and doesn't
    -- have this function yet, fall back to the default account instead of
    -- crashing the whole receive handler (which would silently drop the
    -- character with no explanation, exactly what happened before this
    -- guard existed).
    if Data.GetOrCreateAccountForPassword then
      remote.accountId = Data:GetOrCreateAccountForPassword(password)
    else
      addon.Core:Print("Sync: Data.lua looks out of date (missing GetOrCreateAccountForPassword) -- filed under a fallback WoW Account instead. Reinstall the full addon package to fix this.")
      -- EnsureDefaultAccount() returns the lowest-order account, which is
      -- normally Main -- never file an incoming character there even in
      -- this fallback path, or it'll immediately look "stuck" the same
      -- way a Main-account collision does anywhere else.
      local mainAccountId = Data.GetMainAccountId and Data:GetMainAccountId()
      local fallbackId = Data:EnsureDefaultAccount()
      if fallbackId == mainAccountId then
        fallbackId = Data:CreateAccount()
      end
      remote.accountId = fallbackId
    end
  end

  if InCombatLockdown() then
    pendingCombatApplies[remote.GUID] = {
      character = remote,
      isNew = isNew,
      sender = sender,
      distribution = distribution,
      payload = payload,
    }
    return
  end

  ApplyReceivedCharacter(remote, isNew)
  TrackAutomaticBatchCompletion(sender, distribution, payload, remote, isNew)
end

-- Advertise presence/version state when this client becomes reachable on a relevant
-- transport. The short debounce coalesces the burst of roster/guild events that commonly
-- fire together on login. A low-rate heartbeat keeps peer presence fresh without chat noise.
addon.Events:RegisterEvent({
  "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE",
  "GUILD_ROSTER_UPDATE",
  "PLAYER_GUILD_UPDATE",
}, function()
  ScheduleSyncHello(1.5, false)
end, true)

if not syncHeartbeatTicker then
  syncHeartbeatTicker = C_Timer.NewTicker(PEER_HEARTBEAT_SECONDS, function()
    SendSyncHello(nil, nil, nil, false)
  end)
end

addon.Core:RegisterComm(COMM_PREFIX)
addon.Core:RegisterComm(CONTROL_PREFIX)
