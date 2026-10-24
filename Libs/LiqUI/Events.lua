---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI then
  return
end

LiqUI.Events = LiqUI.Events or {
  handlers = {},
  runtime = {pendingByCallback = {}},
  frame = CreateFrame("Frame", "LiqUIEventsFrame"),
}

---@class LiqUI_Events
local Events = LiqUI.Events

local TableForEach = LiqUI.Utils.TableForEach

Events.runtime.pendingByCallback = Events.runtime.pendingByCallback or {}

local BUCKET_INTERVAL_SEC = 2

---@param entry LiqUI_EventHandlerEntry
---@param packedVarargs LiqUI_EventPackedVarargs
---@return boolean
local function entryMatchesUnit(entry, packedVarargs)
  if not entry.unit then
    return true
  end
  return packedVarargs[1] == entry.unit
end

---@param event string
---@param callback LiqUI_EventCallback
---@param unit string|nil
---@return boolean
local function isRegistered(event, callback, unit)
  local list = Events.handlers[event]
  if not list then
    return false
  end
  for handlerIndex = 1, #list do
    local entry = list[handlerIndex]
    if entry.fn == callback and entry.unit == unit then
      return true
    end
  end
  return false
end

---@param callback LiqUI_EventCallback
---@return boolean
local function isCallbackRegisteredAnywhere(callback)
  local found = false
  TableForEach(Events.handlers, function(list)
    if found then
      return
    end
    for handlerIndex = 1, #list do
      if list[handlerIndex].fn == callback then
        found = true
        return
      end
    end
  end)
  return found
end

---@param callback LiqUI_EventCallback
local function cancelPending(callback)
  local pendingByCallback = Events.runtime.pendingByCallback
  ---@type LiqUI_EventBucketPending?
  local bucket = pendingByCallback[callback]
  if bucket and bucket.timer then
    bucket.timer:Cancel()
  end
  pendingByCallback[callback] = nil
end

---@param frame Frame
---@param callback LiqUI_EventCallback
---@param bucket LiqUI_EventBucketPending
local function scheduleBucket(frame, callback, bucket)
  local pendingByCallback = Events.runtime.pendingByCallback
  bucket.timer = C_Timer.NewTimer(BUCKET_INTERVAL_SEC, function()
    pendingByCallback[callback] = nil
    local currentList = Events.handlers[bucket.event]
    if not currentList then
      return
    end
    for currentIndex = 1, #currentList do
      if currentList[currentIndex].fn == callback then
        callback(frame, bucket.event, unpack(bucket.packedVarargs, 1, bucket.packedVarargs.n))
        return
      end
    end
  end)
end

Events.frame:SetScript("OnEvent", function(frame, event, ...)
  local list = Events.handlers[event]
  if not list then
    return
  end

  local packedCount = select("#", ...)
  ---@type LiqUI_EventPackedVarargs
  local packedVarargs = {n = packedCount}
  for packedIndex = 1, packedCount do
    packedVarargs[packedIndex] = select(packedIndex, ...)
  end

  local pendingByCallback = Events.runtime.pendingByCallback
  for handlerIndex = 1, #list do
    local entry = list[handlerIndex]
    if entryMatchesUnit(entry, packedVarargs) then
      if entry.runsImmediately then
        entry.fn(frame, event, unpack(packedVarargs, 1, packedVarargs.n))
      else
        local fn = entry.fn
        ---@type LiqUI_EventBucketPending?
        local bucket = pendingByCallback[fn]
        if not bucket then
          ---@type LiqUI_EventBucketPending
          local newBucket = {event = event, packedVarargs = packedVarargs}
          pendingByCallback[fn] = newBucket
          scheduleBucket(frame, fn, newBucket)
        else
          bucket.event = event
          bucket.packedVarargs = packedVarargs
        end
      end
    end
  end
end)

---@param event string|string[]
---@param callback LiqUI_EventCallback
---@param runsImmediately boolean|nil
---@param unit string|nil
function Events:RegisterEvent(event, callback, runsImmediately, unit)
  if type(event) == "table" then
    for _, eventName in ipairs(event) do
      self:RegisterEvent(eventName, callback, runsImmediately, unit)
    end
    return
  end
  local list = self.handlers[event]
  if not list then
    list = {}
    self.handlers[event] = list
    self.frame:RegisterEvent(event)
  end
  if isRegistered(event, callback, unit) then
    return
  end
  ---@type LiqUI_EventHandlerEntry
  local entry = {
    fn = callback,
    runsImmediately = runsImmediately == true,
    unit = unit,
  }
  list[#list + 1] = entry
end

---@param event string|string[]
---@param callback LiqUI_EventCallback|nil
function Events:UnregisterEvent(event, callback)
  if type(event) == "table" then
    for _, eventName in ipairs(event) do
      self:UnregisterEvent(eventName, callback)
    end
    return
  end
  local list = self.handlers[event]
  if not list then
    return
  end
  if callback then
    for handlerIndex = #list, 1, -1 do
      if list[handlerIndex].fn == callback then
        table.remove(list, handlerIndex)
      end
    end
    if not isCallbackRegisteredAnywhere(callback) then
      cancelPending(callback)
    end
    if #list == 0 then
      self.handlers[event] = nil
      self.frame:UnregisterEvent(event)
    end
    return
  end

  ---@type LiqUI_EventCallback[]
  local removedCallbacks = {}
  for handlerIndex = 1, #list do
    removedCallbacks[#removedCallbacks + 1] = list[handlerIndex].fn
  end
  self.handlers[event] = nil
  self.frame:UnregisterEvent(event)
  for removedIndex = 1, #removedCallbacks do
    local fn = removedCallbacks[removedIndex]
    if not isCallbackRegisteredAnywhere(fn) then
      cancelPending(fn)
    end
  end
end
