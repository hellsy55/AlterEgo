---@class LiqUI
local LiqUI = LibStub and LibStub("LiqUI-1.0", true)
if not LiqUI then
  return
end

local BindScrollBoxMouseWheel = LiqUI.Utils.BindScrollBoxMouseWheel
local CreateScrollArea = LiqUI.Utils.CreateScrollArea
local SetBackgroundColor = LiqUI.Utils.SetBackgroundColor
local SetHighlightColor = LiqUI.Utils.SetHighlightColor
local TableForEach = LiqUI.Utils.TableForEach
local TableMergeOptions = LiqUI.Utils.TableMergeOptions

local HEADER_BACKGROUND_ALPHA = 0.3

---@param value table
---@return boolean
local function isExtendedTable(value)
  if type(value) ~= "table" then
    return false
  end
  for key in pairs(value) do
    if type(key) == "string" then
      return true
    end
  end
  return false
end

---@param cellValue LiqUI_TableDataCellValue|nil
---@return LiqUI_TableDataCellExtended
local function normalizeCell(cellValue)
  if cellValue == nil then
    return { data = nil }
  end
  if type(cellValue) ~= "table" then
    return { data = cellValue }
  end
  if not isExtendedTable(cellValue) then
    return { data = cellValue }
  end
  ---@type LiqUI_TableDataCellExtended
  local normalized = { data = cellValue.data }
  for key, value in pairs(cellValue) do
    if type(key) == "string" and key ~= "data" then
      normalized[key] = value
    end
  end
  return normalized
end

---@param row LiqUI_TableDataRow
---@return LiqUI_TableDataRowExtended
local function normalizeRow(row)
  local cells
  ---@type LiqUI_TableDataRowExtended
  local normalized = { data = {} }

  if isExtendedTable(row) then
    cells = row.data or {}
    for key, value in pairs(row) do
      if type(key) == "string" and key ~= "data" then
        normalized[key] = value
      end
    end
  else
    cells = row
  end

  for columnIndex, cellValue in ipairs(cells) do
    normalized.data[columnIndex] = normalizeCell(cellValue)
  end
  return normalized
end

---@param data LiqUI_TableData
---@return LiqUI_TableDataRowExtended[]
local function normalizeData(data)
  ---@type LiqUI_TableDataRowExtended[]
  local normalized = {}
  for rowIndex = 1, #data do
    normalized[rowIndex] = normalizeRow(data[rowIndex])
  end
  return normalized
end

---@param columns LiqUI_TableOptionsColumn[]
---@param sorting LiqUI_TableOptionsSorting|nil
local function validateSortingColumns(columns, sorting)
  if not sorting or not sorting.enabled then
    return
  end
  for columnIndex, column in ipairs(columns) do
    if not column.sorting then
      error(format('LiqUI Table: column #%d ("%s") must define sorting', columnIndex, tostring(column.id)), 2)
    end
  end
end

---Create a new table frame
---@param options LiqUI_TableOptions
---@return LiqUI_TableInstance
local function createTable(options)
  if not options then
    error("LiqUI Table: options is required", 2)
  end
  if not options.name or options.name == "" then
    error("LiqUI Table: options.name is required", 2)
  end

  local instanceName = options.name
  ---@type LiqUI_TableInstance
  local frame = CreateFrame("Frame", "LiqUITable" .. instanceName:gsub("[^%w]", "")) ---@diagnostic disable-line:assign-type-mismatch

  ---@type LiqUI_TableOptions
  local defaultOptions = {
    name = "",
    header = {
      enabled = true,
      sticky = false,
      height = LiqUI.Constants.layout.sizes.header,
      fontObject = "GameFontNormalSmall",
    },
    rowStyle = {
      height = LiqUI.Constants.layout.sizes.row,
      highlight = true,
      striped = true,
    },
    cellStyle = {
      padding = LiqUI.Constants.layout.sizes.padding,
      highlight = false,
      fontObject = "GameFontHighlightSmall",
    },
    sorting = {
      enabled = false,
      defaultOrder = "desc",
      defaultCompare = function()
        return false
      end,
    },
  }
  ---@type LiqUI_TableOptions
  local mergedOptions = {}
  TableMergeOptions(mergedOptions, defaultOptions)
  TableMergeOptions(mergedOptions, options)

  local sorting = mergedOptions.sorting
  if sorting and sorting.enabled then
    if type(sorting.defaultCompare) ~= "function" then
      error("LiqUI Table: sorting.enabled requires sorting.defaultCompare", 2)
    end
    if sorting.defaultOrder ~= "asc" and sorting.defaultOrder ~= "desc" then
      error("LiqUI Table: sorting.enabled requires sorting.defaultOrder to be \"asc\" or \"desc\"", 2)
    end
  end
  if mergedOptions.columns then
    validateSortingColumns(mergedOptions.columns, mergedOptions.sorting)
  end

  ---@type LiqUI_TableDB
  local tableDb = options.storage
  if not tableDb then
    ---@type LiqUI_TableDB
    tableDb = { hiddenColumns = {} }
  elseif not tableDb.hiddenColumns then
    tableDb.hiddenColumns = {}
  end

  if sorting then
    if tableDb.sortState then
      sorting.savedState = tableDb.sortState
    end
    if not sorting.onStateChanged then
      sorting.onStateChanged = function(state)
        tableDb.sortState = state
      end
    end
  end

  frame.options = mergedOptions
  frame.db = tableDb
  frame.data = {}
  frame.rowFrames = {}
  frame.sortState = { columnId = nil, direction = nil }
  frame.layoutSize = { shownWidth = 0, shownHeight = 0 }

  ---@return LiqUI_TableOptionsColumn[]
  function frame:GetActiveColumns()
    ---@type LiqUI_TableOptionsColumn[]
    local result = {}
    local columns = frame.options.columns or {}
    local hiddenColumns = frame.db and frame.db.hiddenColumns
    TableForEach(columns, function(column, columnIndex)
      if column.id and hiddenColumns and hiddenColumns[column.id] then
        return
      end
      column.dataIndex = columnIndex
      table.insert(result, column)
    end)
    return result
  end

  ---@param columnId string|nil
  ---@return number|nil
  function frame:getColumnById(columnId)
    if not columnId then
      return nil
    end
    local columns = frame:GetActiveColumns()
    for columnIndex, column in ipairs(columns) do
      if column.id == columnId then
        return columnIndex
      end
    end
    return nil
  end

  function frame:setSortStateToDefault()
    local state = frame.sortState
    state.columnId = nil
    state.direction = nil
  end

  function frame:validateSortState()
    local sortingOptions = frame.options.sorting
    if not sortingOptions or not sortingOptions.enabled then
      return
    end
    local state = frame.sortState
    if not state then
      return
    end
    if state.columnId and not frame:getColumnById(state.columnId) then
      frame:setSortStateToDefault()
      if sortingOptions.onStateChanged then
        sortingOptions.onStateChanged(state)
      end
      return
    end
    if state.columnId then
      if state.direction ~= "asc" and state.direction ~= "desc" then
        state.direction = (sortingOptions.defaultOrder == "asc") and "asc" or "desc"
      end
    else
      state.direction = nil
    end
  end

  function frame:onSortStateChanged()
    local sortingOptions = frame.options.sorting
    if sortingOptions and sortingOptions.onStateChanged then
      sortingOptions.onStateChanged(frame.sortState)
    end
  end

  function frame:scrollToTop()
    C_Timer.After(0, function()
      frame:ScrollToTop()
    end)
  end

  function frame:applySort()
    local sortingOptions = frame.options.sorting
    if not sortingOptions or not sortingOptions.enabled then
      return
    end

    local data = frame.data
    if not data or #data == 0 then
      return
    end

    local state = frame.sortState
    local sortColumnIndex = frame:getColumnById(state.columnId)
    if state.columnId and state.direction and not sortColumnIndex then
      return
    end

    local indices = {}
    for rowIndex = 1, #data do
      indices[rowIndex] = rowIndex
    end

    local columnSort = state.columnId and state.direction and sortColumnIndex
    if not columnSort then
      table.sort(indices, function(rowIndexA, rowIndexB)
        return sortingOptions.defaultCompare(data[rowIndexA], data[rowIndexB], rowIndexA, rowIndexB)
      end)
    else
      local ascending = state.direction == "asc"
      local columns = frame:GetActiveColumns()
      local columnConfig = columns[sortColumnIndex]
      if not columnConfig or not columnConfig.sorting then
        error(format("LiqUI Table: column \"%s\" must define sorting", tostring(columnConfig and columnConfig.id)), 2)
      end
      local columnSorting = columnConfig.sorting
      if not columnSorting or not columnSorting.enabled then
        error(format("LiqUI Table: column \"%s\" is not sortable", tostring(columnConfig.id)), 2)
      end
      local compare = columnSorting.compare
      if type(compare) ~= "function" then
        error(format("LiqUI Table: column \"%s\" must define sorting.compare", tostring(columnConfig.id)), 2)
      end
      table.sort(indices, function(rowIndexA, rowIndexB)
        if ascending then
          return compare(data[rowIndexA], data[rowIndexB], rowIndexA, rowIndexB)
        end
        return compare(data[rowIndexB], data[rowIndexA], rowIndexB, rowIndexA)
      end)
    end

    ---@type LiqUI_TableData
    local sortedData = {}
    for position = 1, #indices do
      sortedData[position] = data[indices[position]]
    end
    frame.data = sortedData
  end

  ---@param shouldSort boolean
  function frame:runTable(shouldSort)
    if shouldSort then
      frame:validateSortState()
      frame:applySort()
    end
    frame:Render()
  end

  function frame:Render()
    if frame.isRendering then
      frame.renderQueued = true
      return
    end
    frame.isRendering = true
    frame.renderQueued = false

    local sortState = frame.sortState
    local headerConfig = frame.options.header
    local rowStyle = frame.options.rowStyle
    local cellStyle = frame.options.cellStyle
    local sortingConfig = frame.options.sorting
    local sortingEnabled = sortingConfig and sortingConfig.enabled
    local activeColumns = frame:GetActiveColumns()

    local headerEnabled = headerConfig and headerConfig.enabled
    local headerSticky = headerConfig and headerConfig.sticky
    local defaultRowHeight = (rowStyle and rowStyle.height) or LiqUI.Constants.layout.sizes.row
    local defaultColumnWidth = LiqUI.Constants.layout.sizes.column
    local headerHeight = (headerConfig and headerConfig.height) or LiqUI.Constants.layout.sizes.header
    local defaultPadding = (cellStyle and cellStyle.padding) or LiqUI.Constants.layout.sizes.padding
    local defaultHeaderFont = (headerConfig and headerConfig.fontObject) or "GameFontNormalSmall"
    local defaultCellFont = cellStyle and cellStyle.fontObject or "GameFontHighlightSmall"

    local layoutWidth = 0
    TableForEach(activeColumns, function(column)
      layoutWidth = layoutWidth + (column.width or defaultColumnWidth)
    end)

    local scrollHeight = 0
    if headerEnabled and not headerSticky then
      scrollHeight = headerHeight
    end
    local rowOffsetY = scrollHeight
    local columnOffsetX = 0

    local scrollArea = frame.scrollArea
    local headerRowFrame = frame.headerRowFrame

    scrollArea:SetParent(frame)
    scrollArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    scrollArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    if headerEnabled then
      if not headerRowFrame then
        headerRowFrame = CreateFrame("Frame", "$parentHeaderRow", frame)
        headerRowFrame.cells = {}
        BindScrollBoxMouseWheel(headerRowFrame, scrollArea:GetWheelScrollBox())
        frame.headerRowFrame = headerRowFrame
      end

      if headerSticky then
        headerRowFrame:SetParent(frame)
        headerRowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        headerRowFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        headerRowFrame:SetFrameLevel(scrollArea.verticalScrollBar:GetFrameLevel() + 2)
        scrollArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -headerHeight)
        scrollArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
      else
        headerRowFrame:SetParent(scrollArea.content)
        headerRowFrame:SetPoint("TOPLEFT", scrollArea.content, "TOPLEFT", 0, 0)
        headerRowFrame:SetPoint("TOPRIGHT", scrollArea.content, "TOPRIGHT", 0, 0)
        headerRowFrame:SetFrameLevel(scrollArea.content:GetFrameLevel() + 1)
      end

      SetBackgroundColor(headerRowFrame, 0, 0, 0, HEADER_BACKGROUND_ALPHA)
      headerRowFrame:SetHeight(headerHeight)
      headerRowFrame:Show()

      columnOffsetX = 0
      TableForEach(headerRowFrame.cells, function(headerCellFrame) headerCellFrame:Hide() end)
      TableForEach(activeColumns, function(column, columnIndex)
        local columnWidth = column.width or defaultColumnWidth
        local columnAlign = column.align or "LEFT"
        local columnSortable = sortingEnabled and column.sorting and column.sorting.enabled
        local sortHighlight = columnSortable and sortState.columnId == column.id and sortState.direction ~= nil

        local headerCellFrame = headerRowFrame.cells[columnIndex]
        if not headerCellFrame then
          headerCellFrame = CreateFrame("Button", "$parentCell" .. columnIndex, headerRowFrame)
          headerCellFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
          headerCellFrame.label = headerCellFrame:CreateFontString("$parentLabel", "OVERLAY")
          headerCellFrame.label:SetWordWrap(false)
          headerCellFrame.tableFrame = frame
          BindScrollBoxMouseWheel(headerCellFrame, scrollArea:GetWheelScrollBox())
          headerRowFrame.cells[columnIndex] = headerCellFrame
        end

        SetBackgroundColor(headerCellFrame, 0, 0, 0, 0)
        headerCellFrame:SetPoint("TOPLEFT", headerRowFrame, "TOPLEFT", columnOffsetX, 0)
        headerCellFrame:SetPoint("BOTTOMLEFT", headerRowFrame, "BOTTOMLEFT", columnOffsetX, 0)
        headerCellFrame:SetWidth(columnWidth)
        headerCellFrame:Show()
        headerCellFrame.label:SetFontObject(defaultHeaderFont)
        headerCellFrame.label:SetJustifyH(columnAlign)
        headerCellFrame.label:SetPoint("TOPLEFT", headerCellFrame, "TOPLEFT", defaultPadding, -defaultPadding)
        headerCellFrame.label:SetPoint("BOTTOMRIGHT", headerCellFrame, "BOTTOMRIGHT", -defaultPadding, defaultPadding)
        headerCellFrame.label:SetText(column.headerText or "")
        columnOffsetX = columnOffsetX + columnWidth

        if columnSortable then
          if sortHighlight then
            SetHighlightColor(headerCellFrame, 1, 1, 1, 0.03)
          else
            SetHighlightColor(headerCellFrame, 1, 1, 1, 0)
          end
        end

        headerCellFrame:SetScript("OnEnter", function()
          if column.onEnter then
            column.onEnter(headerCellFrame, columnIndex, column.id, column)
          end
          if columnSortable then
            if not GameTooltip:IsShown() then
              GameTooltip:SetOwner(headerCellFrame, "ANCHOR_RIGHT")
              GameTooltip:SetText(column.headerText or "", 1, 1, 1)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("<Click to Sort>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            GameTooltip:AddLine("<Right Click to Reset>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
            GameTooltip:Show()
          end
        end)

        headerCellFrame:SetScript("OnLeave", function()
          if column.onLeave then
            column.onLeave(headerCellFrame, columnIndex, column.id, column)
          end
          if columnSortable and GameTooltip:IsShown() then
            GameTooltip:Hide()
          end
        end)

        headerCellFrame:SetScript("OnClick", function(_, button)
          if columnSortable and column.id then
            if button == "RightButton" then
              frame:setSortStateToDefault()
              frame:runTable(true)
              frame:scrollToTop()
              frame:onSortStateChanged()
              return
            end

            if sortState.columnId == column.id then
              sortState.direction = (sortState.direction == "asc") and "desc" or "asc"
            else
              sortState.columnId = column.id
              sortState.direction = (sortingConfig and sortingConfig.defaultOrder == "asc") and "asc" or "desc"
            end
            frame:runTable(true)
            frame:scrollToTop()
            frame:onSortStateChanged()
          end
        end)
      end)
    elseif headerRowFrame then
      headerRowFrame:Hide()
    end

    TableForEach(frame.rowFrames, function(rowFrame) rowFrame:Hide() end)
    TableForEach(frame.data, function(rowData, rowIndex)
      local rowHeight = rowData.height or defaultRowHeight
      local rowFrame = frame.rowFrames[rowIndex]

      if not rowFrame then
        ---@type LiqUI_TableRowFrame
        rowFrame = CreateFrame("Frame", "$parentRow" .. rowIndex, scrollArea.content)
        rowFrame.cells = {}
        BindScrollBoxMouseWheel(rowFrame, scrollArea:GetWheelScrollBox())
        frame.rowFrames[rowIndex] = rowFrame
      end

      if rowData.backgroundColor then
        SetBackgroundColor(rowFrame, rowData.backgroundColor)
      elseif rowStyle and rowStyle.striped and rowIndex % 2 == 1 then
        SetBackgroundColor(rowFrame, 1, 1, 1, 0.02)
      else
        SetBackgroundColor(rowFrame, 0, 0, 0, 0)
      end

      rowFrame:SetParent(scrollArea.content)
      rowFrame:SetPoint("TOPLEFT", scrollArea.content, "TOPLEFT", 0, -rowOffsetY)
      rowFrame:SetPoint("TOPRIGHT", scrollArea.content, "TOPRIGHT", 0, -rowOffsetY)
      rowFrame:SetFrameLevel(scrollArea.content:GetFrameLevel() + 1)
      rowFrame:SetHeight(rowHeight)
      rowFrame:Show()
      rowOffsetY = rowOffsetY + rowHeight
      scrollHeight = scrollHeight + rowHeight

      columnOffsetX = 0
      TableForEach(rowFrame.cells, function(bodyCellFrame) bodyCellFrame:Hide() end)
      TableForEach(activeColumns, function(column, columnIndex)
        local columnWidth = column.width or defaultColumnWidth
        local columnAlign = column.align or "LEFT"
        local cellData = rowData.data[column.dataIndex]
        local displayText = tostring(cellData and cellData.data or "")

        if column.render then
          local formatted = column.render(cellData, rowData, rowIndex)
          if formatted ~= nil then
            displayText = tostring(formatted)
          end
        end

        local bodyCellFrame = rowFrame.cells[columnIndex]
        if not bodyCellFrame then
          ---@type LiqUI_TableCellFrame
          bodyCellFrame = CreateFrame("Button", "$parentCell" .. columnIndex, rowFrame)
          bodyCellFrame.label = bodyCellFrame:CreateFontString("$parentLabel", "OVERLAY")
          bodyCellFrame.label:SetWordWrap(false)
          bodyCellFrame.tableFrame = frame
          BindScrollBoxMouseWheel(bodyCellFrame, scrollArea:GetWheelScrollBox())
          rowFrame.cells[columnIndex] = bodyCellFrame
        end

        bodyCellFrame:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", columnOffsetX, 0)
        bodyCellFrame:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", columnOffsetX, 0)
        bodyCellFrame:SetWidth(columnWidth)
        bodyCellFrame.label:SetFontObject(defaultCellFont)
        bodyCellFrame.label:SetText(displayText)
        bodyCellFrame.label:SetJustifyH(columnAlign)
        bodyCellFrame.label:SetPoint("TOPLEFT", bodyCellFrame, "TOPLEFT", defaultPadding, -defaultPadding)
        bodyCellFrame.label:SetPoint("BOTTOMRIGHT", bodyCellFrame, "BOTTOMRIGHT", -defaultPadding, defaultPadding)

        if cellData and cellData.backgroundColor then
          SetBackgroundColor(bodyCellFrame, cellData.backgroundColor)
        else
          SetBackgroundColor(bodyCellFrame, 0, 0, 0, 0)
        end

        bodyCellFrame:SetScript("OnEnter", function()
          if rowStyle and rowStyle.highlight then
            SetHighlightColor(rowFrame, 1, 1, 1, 0.05)
          end
          if cellStyle and cellStyle.highlight then
            SetHighlightColor(bodyCellFrame, 1, 1, 1, 0.05)
          end
          if rowData.onEnter then
            rowData.onEnter(bodyCellFrame, rowFrame, rowIndex, columnIndex, column.id, rowData, cellData)
          end
          if cellData and cellData.onEnter then
            cellData.onEnter(bodyCellFrame, rowFrame, rowIndex, columnIndex, column.id, rowData, cellData)
          end
        end)
        bodyCellFrame:SetScript("OnLeave", function()
          if rowStyle and rowStyle.highlight then
            SetHighlightColor(rowFrame, 1, 1, 1, 0)
          end
          if cellStyle and cellStyle.highlight then
            SetHighlightColor(bodyCellFrame, 1, 1, 1, 0)
          end
          if rowData.onLeave then
            rowData.onLeave(bodyCellFrame, rowFrame, rowIndex, columnIndex, column.id, rowData, cellData)
          end
          if cellData and cellData.onLeave then
            cellData.onLeave(bodyCellFrame, rowFrame, rowIndex, columnIndex, column.id, rowData, cellData)
          end
        end)
        bodyCellFrame:SetScript("OnClick", function(_, button)
          if rowData.onClick then
            rowData.onClick(bodyCellFrame, rowFrame, rowIndex, columnIndex, column.id, rowData, cellData, button)
          end
          if cellData and cellData.onClick then
            cellData.onClick(bodyCellFrame, rowFrame, rowIndex, columnIndex, column.id, rowData, cellData, button)
          end
        end)

        bodyCellFrame:Show()
        columnOffsetX = columnOffsetX + columnWidth
      end)
    end)

    local shownHeight = scrollHeight
    if headerEnabled and headerSticky then
      shownHeight = shownHeight + headerHeight
    end

    frame.layoutSize.shownWidth = layoutWidth
    frame.layoutSize.shownHeight = shownHeight

    scrollArea:UpdateLayout(layoutWidth, scrollHeight)

    frame.isRendering = false
    if frame.renderQueued then
      frame:Render()
    end
  end

  function frame:ScrollToTop()
    local scrollArea = frame.scrollArea
    if not scrollArea then
      return
    end
    scrollArea:ScrollToTop()
  end

  ---@param data LiqUI_TableData
  function frame:SetData(data)
    local columns = frame.options.columns
    if not columns or #columns == 0 then
      error("LiqUI Table: columns is required", 2)
    end
    if type(data) ~= "table" then
      error("LiqUI Table: data must be a table", 2)
    end
    for rowIndex = 1, #data do
      if type(data[rowIndex]) ~= "table" then
        error(format("LiqUI Table: row #%d must be a table", rowIndex), 2)
      end
    end
    validateSortingColumns(columns, frame.options.sorting)
    frame.data = normalizeData(data)
    frame:runTable(true)
  end

  ---@param columns LiqUI_TableOptionsColumn[]
  function frame:SetColumns(columns)
    if not columns or #columns == 0 then
      error("LiqUI Table: columns is required", 2)
    end
    validateSortingColumns(columns, frame.options.sorting)
    frame.options.columns = columns
    frame:runTable(true)
  end

  ---@param columnId string
  ---@param hidden boolean
  function frame:SetColumnHidden(columnId, hidden)
    if not frame.db then
      return
    end
    if hidden then
      frame.db.hiddenColumns[columnId] = true
    else
      frame.db.hiddenColumns[columnId] = nil
    end
    frame:runTable(true)
  end

  ---@return LiqUI_TableSortState
  function frame:GetSortState()
    local state = frame.sortState
    return { columnId = state.columnId, direction = state.direction }
  end

  ---@param columnId string|nil
  ---@param direction "asc"|"desc"|nil
  function frame:SetSortState(columnId, direction)
    local state = frame.sortState
    state.columnId = columnId
    state.direction = direction
    frame:runTable(true)
    frame:onSortStateChanged()
  end

  ---@param height number
  function frame:SetRowHeight(height)
    local rowStyle = frame.options.rowStyle
    if rowStyle then
      rowStyle.height = height
    end
    if frame.scrollArea then
      frame.scrollArea:SetWheelPanExtent(height)
    end
    frame:runTable(false)
  end

  ---@return number width
  ---@return number height
  function frame:GetSize()
    local layoutSize = frame.layoutSize
    return layoutSize.shownWidth, layoutSize.shownHeight
  end

  local saved = sorting and sorting.savedState
  if sorting and sorting.enabled and saved and type(saved.columnId) == "string" and saved.columnId ~= "" then
    frame.sortState.columnId = saved.columnId
    if saved.direction == "asc" or saved.direction == "desc" then
      frame.sortState.direction = saved.direction
    else
      frame.sortState.direction = (sorting.defaultOrder == "asc") and "asc" or "desc"
    end
  else
    frame:setSortStateToDefault()
  end

  frame.scrollArea = CreateScrollArea(frame, {
    name = "$parentScrollArea",
    vertical = true,
    horizontal = false,
    wheelPanExtent = (frame.options.rowStyle and frame.options.rowStyle.height) or LiqUI.Constants.layout.sizes.row,
  })

  frame.scrollArea:HookScript("OnSizeChanged", function()
    frame:Render()
  end)

  frame:runTable(false)
  return frame
end

LiqUI:RegisterElement("Table", createTable)
