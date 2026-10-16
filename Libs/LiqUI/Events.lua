---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI then
  return
end

LiqUI.Events = LiqUI.Events or {
  handlers = {},
  runtime = {pendingByEventName = {}},
  frame = CreateFrame("Frame", "LiqUIEventsFrame"),
}

---@class LiqUI_Events
local Events = LiqUI.Events
local BUCKET_INTERVAL_SEC = 2

---@param packed LiqUI_EventPackedVarargs
---@return any ...
local function unpackEventVarargs(packed)
  if not packed or (packed.n or 0) == 0 then
    return
  end
  return unpack(packed, 1, packed.n)
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

  for handlerIndex = 1, #list do
    local entry = list[handlerIndex]
    if entry.runsImmediately then
      entry.fn(frame, event, unpackEventVarargs(packedVarargs))
    end
  end

  local hasBucketed = false
  for handlerIndex = 1, #list do
    if not list[handlerIndex].runsImmediately then
      hasBucketed = true
      break
    end
  end
  if not hasBucketed then
    return
  end

  local pendingByEventName = Events.runtime.pendingByEventName
  local bucket = pendingByEventName[event]
  if not bucket or not bucket.timer then
    ---@type LiqUI_EventBucketPending
    bucket = {packedVarargs = packedVarargs}
    pendingByEventName[event] = bucket
    bucket.timer = C_Timer.NewTimer(BUCKET_INTERVAL_SEC, function()
      local snapshot = bucket.packedVarargs
      bucket.timer = nil
      pendingByEventName[event] = nil
      local currentList = Events.handlers[event]
      if not currentList then
        return
      end
      for currentIndex = 1, #currentList do
        local entry = currentList[currentIndex]
        if not entry.runsImmediately then
          entry.fn(frame, event, unpackEventVarargs(snapshot))
        end
      end
    end)
  else
    bucket.packedVarargs = packedVarargs
  end
end)

---@param event string|string[]
---@param callback LiqUI_EventCallback
---@param runsImmediately boolean|nil
function Events:RegisterEvent(event, callback, runsImmediately)
  if type(event) == "table" then
    for eventIndex = 1, #event do
      self:RegisterEvent(event[eventIndex], callback, runsImmediately)
    end
    return
  end
  local list = self.handlers[event]
  if not list then
    list = {}
    self.handlers[event] = list
    self.frame:RegisterEvent(event)
  end
  ---@type LiqUI_EventHandlerEntry
  local entry = {fn = callback, runsImmediately = runsImmediately == true}
  list[#list + 1] = entry
end

---@param event string|string[]
---@param callback LiqUI_EventCallback|nil
function Events:UnregisterEvent(event, callback)
  if type(event) == "table" then
    for eventIndex = 1, #event do
      self:UnregisterEvent(event[eventIndex], callback)
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
    if #list == 0 then
      self.handlers[event] = nil
      local pendingByEventName = self.runtime.pendingByEventName
      local bucket = pendingByEventName[event]
      if bucket and bucket.timer then
        bucket.timer:Cancel()
      end
      pendingByEventName[event] = nil
      self.frame:UnregisterEvent(event)
    end
  else
    self.handlers[event] = nil
    local pendingByEventName = self.runtime.pendingByEventName
    local bucket = pendingByEventName[event]
    if bucket and bucket.timer then
      bucket.timer:Cancel()
    end
    pendingByEventName[event] = nil
    self.frame:UnregisterEvent(event)
  end
end
