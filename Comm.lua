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
-- and everything it triggers) is silent on the SENDING side by design -- it
-- can fire many times an hour from routine gameplay (loot, currency ticks,
-- vault progress...), and printing every one of those would just be spam.
-- A passphrase mismatch is deliberately silent too, on either side -- using
-- the right passphrase for who you're sharing with is on each person running
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

-- Set when a manual "Sync Now" arrives while a batch is already running.
-- Checked at the top of each SendNext step: rather than an outright
-- refusal, the NEW request takes over the moment the CURRENTLY
-- transmitting character genuinely finishes (never mid-transmission --
-- that's what actually risks corrupting it, see batchInProgress above),
-- discarding whatever was left of the old list in favor of a completely
-- fresh one.
local supersedeRequested = false

-- The batchId of the Sync Now push currently going out (nil when none),
-- and which senders have ack'd ANY character in it so far -- populated
-- from the ack handler in OnCommReceived as they arrive DURING the send
-- (a big batch can take minutes, so several acks typically land well
-- before the last character even goes out). Lets the final "successfully
-- sent" summary name who it actually reached, not just that it was sent.
local activeBatchId = nil
local activeBatchConfirmedBy = {}


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

---Serialize+compress+send one character record. Shared by the automatic
---per-change broadcast and the manual "Sync Now".
---@param character AE_Character
---@param passphrase string
---@param channels string[] AceComm distributions to send on ("GUILD"/"PARTY"/"RAID"), one message per entry.
---@param forced boolean? True for a manual "Sync Now" push -- tells the receiver to apply this even if it's not strictly newer than what it already has (see OnCommReceived).
---@param batchId string? Shared by every character in the same manual "Sync Now" click -- lets the receiver group them and print its own "received" summary once they've all arrived. Nil for the automatic path.
---@param batchTotal number? How many characters are in this batchId's push -- how the receiver knows when it has them all.
---@param priority string? AceComm priority ("BULK"/"NORMAL"/"ALERT"). Defaults to "BULK".
---@param onDone function? Called once every channel's LAST chunk has been dequeued by ChatThrottleLib -- i.e. once this character's transmission is truly finished going out on every channel, not just "some time has probably passed". Receives one argument: a list of channels where at least one chunk did NOT actually go out (empty if everything succeeded) -- see the comment below on why "reached the last chunk" and "actually delivered" aren't the same thing. PerformBroadcast's SendNext waits for this before starting the next character, instead of guessing a fixed delay -- see the comment on batchInProgress for why that matters: everyone's outgoing messages share the same AceComm sender identity (whichever character you're actually logged in on), so their multi-part reassembly streams share the exact same spool slot on the receiving end, and starting the next one before the last one's LAST chunk has gone out destroys it.
local function SendCharacterRecord(character, passphrase, channels, forced, batchId, batchTotal, priority, onDone)
  local payload = {
    passphrase = passphrase,
    character = character,
    forced = forced or nil,
    batchId = batchId,
    batchTotal = batchTotal,
  }

  local serialized = LibSerialize:Serialize(payload)
  local compressed = LibDeflate:CompressDeflate(serialized)
  local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)

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

---Checks Sync is actually usable right now (enabled, passphrase set, and at
---least one channel to send it on), optionally printing why not. Shared by
---every send path below.
---@param verbose boolean?
---@return string? passphrase nil if sync can't run right now
---@return string[]? channels nil if sync can't run right now
local function GetUsablePassphrase(verbose)
  if not Data.db.global.sync.enabled then
    if verbose then addon.Core:Print("Sync: not sending, Sync is disabled.") end
    return nil, nil
  end
  local passphrase = Data.db.global.sync.passphrase
  if not passphrase or passphrase == "" then
    if verbose then addon.Core:Print("Sync: not sending, no passphrase set.") end
    return nil, nil
  end
  local channels = GetUsableChannels(verbose)
  if #channels == 0 then
    return nil, nil
  end
  return passphrase, channels
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
  return not mainAccountId or character.accountId == mainAccountId
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
  local account = character.accountId and Data.db.global.accounts[character.accountId]
  if account and account.enabled == false then return false end
  return true
end

---Every character Sync should push out: every enabled character filed
---under the Main WoW Account (Data:GetSyncEligibleCharacters, the same
---list "Sync All Characters" used to send), PLUS the character you're
---currently logged in on even if it's a leveling alt under max level --
---GetSyncEligibleCharacters applies the Characters-menu's max-level
---display filter, which would otherwise silently stop covering the very
---character you're actively playing just because it hasn't hit max level.
---That fallback still respects the character's own checkbox, though --
---unchecking the character you're currently logged in on should still
---exclude it, same as any other character.
---@return AE_Character[]
local function GetBroadcastCandidates()
  local candidates = {}
  local seen = {}
  local eligible = Data.GetSyncEligibleCharacters and Data:GetSyncEligibleCharacters() or Data:GetCharacters()
  for _, character in ipairs(eligible) do
    table.insert(candidates, character)
    seen[character.GUID] = true
  end

  local current = Data:GetCharacter()
  if current and not seen[current.GUID] and IsEligibleToSend(current) and IsCharacterIndividuallyEnabled(current) then
    table.insert(candidates, current)
  end

  return candidates
end

---@param verbose boolean? Deliberate manual "Sync Now": prints a summary, sends every eligible character (see GetBroadcastCandidates) regardless of whether it changed, and tells the receiver to apply it even if not newer. False/nil is the automatic background path: silent, and only sends characters that actually changed since the last time they were sent.
local function PerformBroadcast(verbose)
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
  -- wait until after the pull instead. The automatic path retries
  -- quietly every few seconds until combat clears.
  if InCombatLockdown() then
    if verbose then
      addon.Core:Print("Sync: not sending, you're in combat -- Sync never runs during combat, even inside a raid or Mythic+ (being in the instance is fine; being in a pull isn't). Try again once combat ends.")
    else
      C_Timer.After(BROADCAST_STAGGER_SECONDS, function()
        addon.Core:RequestSyncBroadcast()
      end)
    end
    return
  end

  -- Never let two broadcasts from this client overlap -- see the comment
  -- on batchInProgress above for why that's a correctness issue, not just
  -- a pacing one. A manual click while one's already running doesn't get
  -- refused -- it takes over as soon as it's safe to (see
  -- supersedeRequested, checked in SendNext below). The automatic path
  -- just quietly retries shortly instead.
  if batchInProgress then
    if verbose then
      supersedeRequested = true
      addon.Core:Print("Sync: a send is already in progress -- this Sync Now will take over as soon as the character currently sending finishes.")
    else
      C_Timer.After(BROADCAST_STAGGER_SECONDS, function()
        addon.Core:RequestSyncBroadcast()
      end)
    end
    return
  end

  local passphrase, channels = GetUsablePassphrase(verbose)
  if not passphrase then return end

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

  -- Manual "Sync Now" (verbose) sends every eligible character regardless
  -- of whether it changed. The automatic per-change broadcast stays silent
  -- and only sends what actually changed, since it's routine background
  -- chatter that can fire many times an hour.
  local toSend = {}
  for _, character in ipairs(candidates) do
    if verbose or HasCharacterChangedSinceLastSync(character) then
      table.insert(toSend, character)
    end
  end

  lastBroadcastAt = now

  if #toSend == 0 then
    if verbose then addon.Core:Print("Sync: nothing to send.") end
    return
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
  -- Unique per Sync Now click, not per character -- lets the RECEIVING
  -- side (see the batch-tracking near OnCommReceived) group every
  -- character from this one push together and print its own "received"
  -- summary once they've all arrived, mirroring this side's "sent"
  -- summary. Only set for a manual push (verbose); the automatic
  -- background path stays silent on both ends, so it has no need for
  -- this. GetTime() has plenty of resolution for this to be unique
  -- across any two clicks a person could actually make.
  local batchId = verbose and format("%.6f", GetTime()) or nil
  if verbose then
    activeBatchId = batchId
    activeBatchConfirmedBy = {}
  end
  batchInProgress = true
  local function SendNext()
    -- A newer "Sync Now" arrived while we were waiting on the last
    -- character -- hand off to it now instead of continuing this old
    -- list. Safe to do here specifically: the character that was
    -- actually transmitting has just genuinely finished (that's why
    -- we're in this callback at all), so there's nothing in flight for a
    -- fresh send to collide with.
    if supersedeRequested then
      supersedeRequested = false
      batchInProgress = false
      PerformBroadcast(true)
      return
    end

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
        addon.Core:Print(format("Sync: stopped -- Sync was disabled mid-send. %d of %d character(s) had already gone out: %s", #sentNames, #toSend, #sentNames > 0 and JoinWithAnd(sentNames) or "none"))
      end
      batchInProgress = false
      return
    end
    if InCombatLockdown() then
      if verbose then
        addon.Core:Print(format("Sync: stopped -- you're in combat now. %d of %d character(s) had already gone out: %s", #sentNames, #toSend, #sentNames > 0 and JoinWithAnd(sentNames) or "none"))
      end
      batchInProgress = false
      return
    end

    index = index + 1
    local character = toSend[index]
    if not character then
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
        addon.Core:Print(format("Sync: |cff33ff99successfully|r sent %d character(s)%s over %s in %s: %s", #sentNames, toClause, JoinWithAnd(channels), FormatDuration(GetTime() - startedAt), JoinWithAnd(sentNames)))
      end
      batchInProgress = false
      return
    end
    local name = format("%s-%s", character.info.name or "?", character.info.realm or "?")
    if verbose then
      addon.Core:Print(format("Sync: sending %d/%d -- %s...", index, #toSend, name))
    end
    SendCharacterRecord(character, passphrase, channels, verbose, batchId, #toSend, verbose and "NORMAL" or "BULK", function(failedChannels)
      -- A chunk permanently failing mid-transmission (not the throttle
      -- ChatThrottleLib retries on its own) means this character's data
      -- almost certainly did not arrive intact -- WoW: Midnight's
      -- restriction on outgoing addon messages during an active
      -- raid/M+ encounter is one realistic cause, alongside plain
      -- disconnects or being kicked from the group mid-send.
      if verbose and #failedChannels > 0 then
        addon.Core:Print(format("Sync: WARNING -- %s over %s did not fully send -- its data is likely incomplete on the other end. If you're in an active raid encounter or Mythic+ run, WoW itself may be restricting outgoing addon messages until it ends; try Sync Now again afterward.", name, JoinWithAnd(failedChannels)))
      end
      -- Confirmed done going out on every channel. Still wait a short,
      -- fixed buffer on top of that -- our confirmation only covers OUR
      -- own client handing the last chunk off; it says nothing about how
      -- long the other side takes to actually receive and finish
      -- reassembling it, so a little slack here is cheap insurance.
      C_Timer.After(BROADCAST_STAGGER_SECONDS, SendNext)
    end)
    MarkCharacterSynced(character)
    table.insert(sentNames, name)
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
  supersedeRequested = false
end

---Call this after anything that changed the logged-in character's data.
---Debounced + throttled -- safe to call as often as you want. Completely
---silent -- see the file header.
function addon.Core:RequestSyncBroadcast()
  if broadcastPending then return end
  broadcastPending = true
  C_Timer.After(BROADCAST_DEBOUNCE_SECONDS, PerformBroadcast)
end

---Send right now, ignoring the throttle and the "unchanged" skip -- sends
---EVERY eligible character (see GetBroadcastCandidates), not just the one
---you're logged in on, and tells the receiver to apply each one even if
---it's not strictly newer than what they already have. Prints exactly
---what happened -- for testing, so you don't have to wait for a real data
---change or the 20s window to see whether Sync is working.
function addon.Core:ForceSyncBroadcast()
  PerformBroadcast(true)
end

-- Which top-level Data.db.global keys are display/behavior PREFERENCES --
-- the kind of thing "Sync Addon Settings" shares -- as opposed to actual
-- game data (characters, accounts) or Sync's own configuration
-- (passphrase, enabled, channel, and Sync's internal bookkeeping), which
-- this deliberately never touches: sending your passphrase over the very
-- channel it's meant to gate would defeat the whole point of it, and
-- remotely flipping someone's Enable Sync or Sync Channel on their other
-- account is exactly the kind of surprise this feature should never
-- cause. Two entries (minimap, liqui) are handled separately below
-- instead of listed here, because only PART of each is a shareable
-- preference -- the rest is per-client screen position/size that would
-- look wrong copied onto a different monitor/resolution.
local SHAREABLE_SETTINGS_KEYS = {
  "sorting", "showTiers", "showScores", "showAffixColors", "showAffixHeader",
  "showZeroRatedCharacters", "showEquippedItemLevel", "showItemLevelDecimals",
  "showRealms", "showGuildInformation", "currentCharacterMarker",
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
---passphrase/enabled/channel) with whoever else has AlterEgo, Sync
---enabled, and the same passphrase, over whichever channel(s) Sync
---Channel currently applies. Deliberately only reachable from the "Sync
---Addon Settings" button's confirmation popup -- there is no automatic
---path to this, ever, unlike character sync's per-change background
---broadcast. Respects the same combat lockout as everything else here.
function addon.Core:ShareSettings()
  if InCombatLockdown() then
    addon.Core:Print("Sync: not sharing settings, you're in combat.")
    return
  end

  local passphrase, channels = GetUsablePassphrase(true)
  if not passphrase then return end

  local payload = {
    passphrase = passphrase,
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
local pendingCombatApplies = {} -- [GUID] = {character = <AE_Character>, isNew = boolean}

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

---Called once per character arriving from a forced "Sync Now" push that
---carries batch info (payload.batchId/batchTotal -- absent on the
---automatic path, which has no summary to print here). Accumulates names
---and channels for that batch and, once every character in it has
---arrived (or this batch goes quiet for BATCH_RECEIVE_TIMEOUT_SECONDS),
---prints one summary line mirroring the sender's own "successfully sent"
---one, colored the same way.
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

  local function finishBatch()
    if incomingBatches[key] ~= batch then return end -- already finished (or superseded) elsewhere
    incomingBatches[key] = nil
    local elapsed = FormatDuration(GetTime() - batch.firstAt)
    if #batch.names >= batch.total then
      addon.Core:Print(format("Sync: |cff33ff99successfully|r received %d character(s) over %s in %s from %s: %s", #batch.names, JoinWithAnd(batch.channels), elapsed, sender, JoinWithAnd(batch.names)))
    else
      addon.Core:Print(format("Sync: received %d of %d character(s) over %s in %s from %s (gave up waiting for the rest): %s", #batch.names, batch.total, JoinWithAnd(batch.channels), elapsed, sender, JoinWithAnd(batch.names)))
    end
  end

  if #batch.names >= batch.total then
    finishBatch()
  else
    C_Timer.After(BATCH_RECEIVE_TIMEOUT_SECONDS, finishBatch)
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
  end
  wipe(pendingCombatApplies)
end, true)

---Whispers a small delivery confirmation back to whoever just sent a
---manual "Sync Now" push (payload.forced) -- letting the SENDER's chat
---show that the other side actually got the message, without waiting on
---(or blocking) anything. Sent as a WHISPER regardless of which channel
---the original data came in on, since it only needs to reach that one
---specific character, not a whole guild/group. Fires right after the
---passphrase and character shape check pass -- i.e. "I received and could
---read this", independent of whatever OnCommReceived does with the data
---next (applied, skipped as unchanged, or protected by Main): the sender
---mainly wants to know the message didn't vanish in transit, which this
---answers regardless of the outcome. Carries the original message's
---batchId back along with it so the sender can tell WHICH Sync Now push
---this confirms (see activeBatchConfirmedBy).
---@param remote AE_Character
---@param sender string
---@param passphrase string
---@param batchId string?
local function SendAck(remote, sender, passphrase, batchId)
  local payload = {
    passphrase = passphrase,
    ack = true,
    name = remote.info and remote.info.name,
    realm = remote.info and remote.info.realm,
    batchId = batchId,
  }
  local serialized = LibSerialize:Serialize(payload)
  local compressed = LibDeflate:CompressDeflate(serialized)
  local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
  SendOnChannel(COMM_PREFIX, encoded, "WHISPER", "ALERT", nil, nil, sender)
end

---Same idea as SendAck, but for a "Sync Addon Settings" push -- whispers
---confirmation back to whoever shared their settings, once this client
---has actually applied them, so the sender's chat shows the other side
---really got it.
---@param sender string
---@param passphrase string
local function SendSettingsAck(sender, passphrase)
  local payload = {
    passphrase = passphrase,
    settingsAck = true,
  }
  local serialized = LibSerialize:Serialize(payload)
  local compressed = LibDeflate:CompressDeflate(serialized)
  local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
  SendOnChannel(COMM_PREFIX, encoded, "WHISPER", "ALERT", nil, nil, sender)
end

function addon.Core:OnCommReceived(prefix, message, distribution, sender)
  if prefix ~= COMM_PREFIX then return end
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

  local passphrase = Data.db.global.sync.passphrase
  if not passphrase or passphrase == "" then return end

  -- Corrupted/incomplete data (or a genuine prefix collision with some
  -- unrelated addon that happens to also use "AEv1") -- warn once per
  -- sender per session rather than every single occurrence, in case
  -- something keeps producing these back to back.
  local decoded = LibDeflate:DecodeForWoWAddonChannel(message)
  if not decoded then
    if not warnedCorrupted[sender] then
      warnedCorrupted[sender] = true
      addon.Core:Print(format("Sync: got an unreadable message from %s -- ignored.", tostring(sender)))
    end
    return
  end
  local decompressed = LibDeflate:DecompressDeflate(decoded)
  if not decompressed then
    if not warnedCorrupted[sender] then
      warnedCorrupted[sender] = true
      addon.Core:Print(format("Sync: got an unreadable message from %s -- ignored.", tostring(sender)))
    end
    return
  end
  local success, payload = LibSerialize:Deserialize(decompressed)
  if not success or type(payload) ~= "table" then
    if not warnedCorrupted[sender] then
      warnedCorrupted[sender] = true
      addon.Core:Print(format("Sync: got an unreadable message from %s -- ignored.", tostring(sender)))
    end
    return
  end

  -- Wrong/blank passphrase on either end -- silently ignore the data.
  -- Using the right passphrase for who you're sharing with is on each
  -- person running this addon, not something worth flagging every time
  -- someone else's guildmate happens to run Sync with a different one.
  if payload.passphrase ~= passphrase then
    return
  end

  -- A delivery confirmation from a previous forced push, not character
  -- data -- print it and stop, nothing else to process. If it's for the
  -- Sync Now push currently going out, also remember who confirmed, so
  -- the final "successfully sent" summary can name them.
  if payload.ack then
    addon.Core:Print(format("Sync: %s |cff33ff99confirmed|r receiving %s-%s.", tostring(sender), payload.name or "?", payload.realm or "?"))
    if payload.batchId and payload.batchId == activeBatchId then
      activeBatchConfirmedBy[sender] = true
    end
    return
  end

  -- Same, but for a "Sync Addon Settings" push.
  if payload.settingsAck then
    addon.Core:Print(format("Sync: %s |cff33ff99confirmed|r receiving your addon settings.", tostring(sender)))
    return
  end

  -- Shared addon settings from "Sync Addon Settings" -- see
  -- ApplySettingsPayload for exactly what this does and doesn't touch
  -- (never characters, never Sync's own passphrase/enabled/channel).
  if payload.settingsShare then
    if type(payload.settings) == "table" then
      ApplySettingsPayload(payload.settings)
      addon.Core:Print(format("Sync: |cff33ff99applied addon settings|r shared by %s.", tostring(sender)))
      SendSettingsAck(sender, passphrase)
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
    return
  end
  processedUpdates[updateKey] = true

  -- Confirm delivery back to a manual "Sync Now" push -- see SendAck for
  -- why this fires here regardless of what happens to the data below.
  if payload.forced then
    SendAck(remote, sender, passphrase, payload.batchId)
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
    return
  end

  if existing then
    -- Protect your own Main WoW Account -- if this character is already
    -- filed there, it's YOUR authoritative copy, so incoming sync data
    -- never overwrites it. Silent: this is normal, expected protection,
    -- not something worth a chat line every time it does its job.
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
      addon.Core:Print("Sync: Data.lua looks out of date (missing GetOrCreateAccountForPassphrase) -- filed under a fallback WoW Account instead. Reinstall the full addon package to fix this.")
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
    pendingCombatApplies[remote.GUID] = { character = remote, isNew = isNew }
    return
  end

  ApplyReceivedCharacter(remote, isNew)
end

addon.Core:RegisterComm(COMM_PREFIX)
