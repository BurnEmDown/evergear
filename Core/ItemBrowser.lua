-- Debug item browser (/eg debug items): every item in EverGear's data in one
-- filterable list, so each one can be hovered in-game. With debug mode on,
-- hovering a row runs the same check as hovering the item anywhere else
-- (Debug.lua): a difference opens the capture popup, and the result is
-- remembered per item (EverGearDB.debugChecked) so the list can show which
-- items have been checked and which still need a hover.
--
-- The list only ever has as many row frames as fit in the window; scrolling
-- re-fills them from the filtered item list, so ~1,800 items cost nothing.

EverGear = EverGear or {}

local H = EverGear.UIHelpers
local THEME = H.THEME

local WIDTH, HEIGHT = 660, 600
local ROW_HEIGHT = 34
local LIST_TOP, LIST_BOTTOM, LIST_SIDE = -178, 16, 18
local BAR_WIDTH, BAR_GAP = 8, 6
local VIEW_HEIGHT = HEIGHT + LIST_TOP - LIST_BOTTOM
local VISIBLE_ROWS = math.floor(VIEW_HEIGHT / ROW_HEIGHT)

local QUALITY_NAMES = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

local STATUS_FILTERS = {
    { key = "ok",          label = "Matches game" },
    { key = "differs",     label = "Differs from game" },
    { key = "unchecked",   label = "Not checked yet" },
    { key = "unconfirmed", label = "Unconfirmed data" },
}

local SORTS = {
    { key = "level", label = "Level" },
    { key = "name",  label = "Name" },
    { key = "ilvl",  label = "Item level" },
    { key = "id",    label = "Item id" },
}

-- Current filters. nil = no filter on that field.
local filters = { sort = "level" }

local frame, scroll, rows, countText, debugCheck
local bar, thumb
local filtered = {}
local offset = 0

local function Checked()
    EverGearDB.debugChecked = EverGearDB.debugChecked or {}
    return EverGearDB.debugChecked
end

-- Required level: the item's own, or the quest's for a quest reward.
local function RequiredLevel(item)
    return item.minLevel or (item.source and item.source.minLevel)
end

local function Quality(itemId)
    local _, _, quality = H.SafeGetItemInfo(itemId)
    return quality
end

local function TypeKey(item)
    return item.armorType or item.weaponType or "none"
end

local function TypeLabel(key)
    if key == "none" then return "No armor/weapon type" end
    for _, entry in ipairs(EverGear.WEAPON_TYPE_FILTER_LIST) do
        if entry.key == key then return entry.label end
    end
    return key
end

local function SlotLabel(slot)
    if slot == "FingerSlot" then return "Ring" end
    if slot == "TrinketSlot" then return "Trinket" end
    return EverGear.FRIENDLY_SLOT_NAMES[slot] or slot or "?"
end

-- "craft:Tailoring" for crafted items, so each profession is its own source.
local function SourceKey(item)
    local source = item.source
    if not source then return "none" end
    if source.type == "craft" and source.profession then return "craft:" .. source.profession end
    return source.type or "none"
end

local function SourceLabel(key)
    local profession = key:match("^craft:(.+)$")
    if profession then return "Craft: " .. profession end
    for _, entry in ipairs(EverGear.SOURCE_TYPE_FILTERS) do
        if entry.key == key then return entry.label end
    end
    if key == "none" then return "No source" end
    return key
end

local function StatusOf(item)
    return Checked()[item.id] or "unchecked"
end

local function Matches(item)
    if filters.slot and item.slot ~= filters.slot then return false end
    if filters.type and TypeKey(item) ~= filters.type then return false end
    if filters.source and SourceKey(item) ~= filters.source then return false end
    if filters.zone and not (item.source and item.source.zone == filters.zone) then return false end
    if filters.quality ~= nil then
        local quality = Quality(item.id)
        if filters.quality == "unknown" then
            if quality then return false end
        elseif quality ~= filters.quality then
            return false
        end
    end
    if filters.status then
        if filters.status == "unconfirmed" then
            if item.confirmed then return false end
        elseif StatusOf(item) ~= filters.status then
            return false
        end
    end
    if filters.minLevel or filters.maxLevel then
        local level = RequiredLevel(item)
        if not level then return false end
        if filters.minLevel and level < filters.minLevel then return false end
        if filters.maxLevel and level > filters.maxLevel then return false end
    end
    if filters.search then
        local text = filters.search
        if tostring(item.id) ~= text then
            local haystack = strlower((item.name or "") .. "\n" .. EverGear:GetSourceSummary(item))
            if not haystack:find(text, 1, true) then return false end
        end
    end
    return true
end

local SORTERS = {
    level = function(a, b)
        local la, lb = RequiredLevel(a) or 0, RequiredLevel(b) or 0
        if la ~= lb then return la < lb end
        return a.name < b.name
    end,
    name = function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end,
    ilvl = function(a, b)
        local ia, ib = a.ilvl or 0, b.ilvl or 0
        if ia ~= ib then return ia < ib end
        return a.name < b.name
    end,
    id = function(a, b) return a.id < b.id end,
}

-- ===== Scroll bar (drawn and driven by hand, like the wanted list's) =====

local function MaxOffset()
    return math.max(0, #filtered - VISIBLE_ROWS)
end

local function ThumbTravel()
    return math.max(1, VIEW_HEIGHT - thumb:GetHeight())
end

local RefreshRows

local function SetOffset(newOffset)
    offset = math.min(MaxOffset(), math.max(0, math.floor(newOffset + 0.5)))
    local maxOffset = MaxOffset()
    local y = maxOffset > 0 and (offset / maxOffset * ThumbTravel()) or 0
    thumb:SetPoint("TOP", bar, "TOP", 0, -y)
    RefreshRows()
end

local function UpdateScrollBar()
    bar:SetShown(MaxOffset() > 0)
    local total = math.max(1, #filtered)
    thumb:SetHeight(math.max(20, VIEW_HEIGHT * math.min(1, VISIBLE_ROWS / total)))
    SetOffset(offset)
end

-- ===== Rows =====

local function RowLevelText(item)
    local level = RequiredLevel(item)
    return "Req " .. (level and tostring(level) or "?") .. ", ilvl " .. tostring(item.ilvl or "?")
end

function RefreshRows()
    if not rows then return end
    local checked = Checked()
    for i, row in ipairs(rows) do
        local item = filtered[offset + i]
        row.item = item
        if item then
            local quality = Quality(item.id)
            local r, g, b = H.GetQualityColor(quality)
            H.SetIconTexture(row.icon, H.SafeGetItemIcon(item.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:SetBackdropBorderColor(r, g, b, 1)
            row.nameText:SetText(item.name .. "  |cff888888" .. item.id .. "|r")
            row.nameText:SetTextColor(r, g, b)

            local typeKey = TypeKey(item)
            local what = SlotLabel(item.slot) .. (typeKey ~= "none" and (" " .. TypeLabel(typeKey)) or "")
            row.infoText:SetText(RowLevelText(item) .. " - " .. what .. " - " .. EverGear:GetSourceSummary(item))

            local status = checked[item.id]
            if status == "ok" then
                row.statusText:SetText("|cff33e640Matches|r")
            elseif status == "differs" then
                row.statusText:SetText("|cffff9933Differs|r")
            else
                row.statusText:SetText("")
            end
            row.unconfirmedText:SetShown(not item.confirmed)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function ApplyFilters()
    if not frame then return end
    wipe(filtered)
    local total = 0
    for _, item in pairs(EverGear.Items) do
        total = total + 1
        if Matches(item) then filtered[#filtered + 1] = item end
    end
    table.sort(filtered, SORTERS[filters.sort] or SORTERS.level)

    local checked, ok, differs = Checked(), 0, 0
    for _, item in ipairs(filtered) do
        if checked[item.id] == "ok" then ok = ok + 1
        elseif checked[item.id] == "differs" then differs = differs + 1 end
    end
    countText:SetText(string.format("Showing %d of %d items  -  |cff33e640%d match|r, |cffff9933%d differ|r, %d not checked",
        #filtered, total, ok, differs, #filtered - ok - differs))
    offset = 0
    UpdateScrollBar()
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, scroll)
    row:SetSize(WIDTH - LIST_SIDE * 2 - BAR_WIDTH - BAR_GAP, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:RegisterForClicks("LeftButtonUp")

    local icon = H.CreateItemIconFrame(nil, row, ROW_HEIGHT - 6)
    icon:SetPoint("LEFT", 0, 0)
    icon:EnableMouse(false)
    row.icon = icon

    local status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOPRIGHT", -4, -4)
    status:SetJustifyH("RIGHT")
    row.statusText = status

    local unconfirmed = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unconfirmed:SetPoint("BOTTOMRIGHT", -4, 4)
    unconfirmed:SetText("unconfirmed")
    unconfirmed:SetTextColor(0.6, 0.6, 0.6)
    row.unconfirmedText = unconfirmed

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    name:SetPoint("RIGHT", row, "RIGHT", -110, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.nameText = name

    local info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
    info:SetPoint("RIGHT", row, "RIGHT", -80, 0)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)
    info:SetTextColor(0.7, 0.7, 0.7)
    row.infoText = info

    row:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(H.BuildItemLink(self.item.id))
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Shift-click links it in chat, Ctrl-click previews it, like any item.
    row:SetScript("OnClick", function(self)
        if not self.item then return end
        local _, link = H.SafeGetItemInfo(self.item.id)
        if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    return row
end

-- ===== Filter controls =====

local function CreateDropdown(name, width, labelText, x, y, buildMenu, currentLabel)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", x + 20, y)
    label:SetText(labelText)
    label:SetTextColor(unpack(THEME.gold))

    local dropdown = CreateFrame("Frame", name, frame, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y - 12)
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_Initialize(dropdown, function(self, level, menuList)
        buildMenu(dropdown, level or 1, menuList)
    end)
    UIDropDownMenu_SetText(dropdown, currentLabel())
    dropdown.currentLabel = currentLabel
    return dropdown
end

local function AddOption(dropdown, text, field, value, menuLevel)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.checked = filters[field] == value
    info.func = function()
        filters[field] = value
        UIDropDownMenu_SetText(dropdown, dropdown.currentLabel())
        CloseDropDownMenus()
        ApplyFilters()
    end
    UIDropDownMenu_AddButton(info, menuLevel)
end

-- Distinct values of some field across all items, sorted by their label.
local function DistinctValues(keyOf, labelOf)
    local seen, list = {}, {}
    for _, item in pairs(EverGear.Items) do
        local key = keyOf(item)
        if key and not seen[key] then
            seen[key] = true
            list[#list + 1] = key
        end
    end
    table.sort(list, function(a, b) return labelOf(a) < labelOf(b) end)
    return list
end

local SLOT_ORDER = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot",
    "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "FingerSlot", "TrinketSlot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

-- Zones are split into alphabetical groups so the menu never runs off screen.
local ZONE_GROUPS = { { "A", "D" }, { "E", "L" }, { "M", "R" }, { "S", "Z" } }

local function CreateLevelBox(x, y)
    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetSize(28, 20)
    box:SetPoint("TOPLEFT", x, y)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(2)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function BuildWindow()
    frame = CreateFrame("Frame", "EverGearItemBrowser", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "EverGearItemBrowser")  -- Escape closes it

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("EverGear Item Browser")
    title:SetTextColor(unpack(THEME.gold))
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Row 1: search, level range, sort.
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 24, -42)
    searchLabel:SetText("Search (name, id, zone, boss, quest)")
    searchLabel:SetTextColor(unpack(THEME.gold))
    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(180, 20)
    search:SetPoint("TOPLEFT", 28, -56)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        local text = strtrim(self:GetText() or "")
        filters.search = text ~= "" and strlower(text) or nil
        ApplyFilters()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local levelLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelLabel:SetPoint("TOPLEFT", 228, -42)
    levelLabel:SetText("Required level")
    levelLabel:SetTextColor(unpack(THEME.gold))
    local minBox = CreateLevelBox(232, -56)
    local dash = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dash:SetPoint("LEFT", minBox, "RIGHT", 4, 0)
    dash:SetText("to")
    local maxBox = CreateLevelBox(0, 0)
    maxBox:ClearAllPoints()
    maxBox:SetPoint("LEFT", dash, "RIGHT", 8, 0)
    local function OnLevelChanged()
        filters.minLevel = tonumber(minBox:GetText())
        filters.maxLevel = tonumber(maxBox:GetText())
        ApplyFilters()
    end
    minBox:SetScript("OnTextChanged", OnLevelChanged)
    maxBox:SetScript("OnTextChanged", OnLevelChanged)

    local function LabelFor(list, field)
        return function()
            for _, entry in ipairs(list) do
                if entry.key == filters[field] then return entry.label end
            end
            return "All"
        end
    end
    CreateDropdown("EverGearItemBrowserSort", 80, "Sort by", 336, -42, function(dropdown, level)
        for _, entry in ipairs(SORTS) do AddOption(dropdown, entry.label, "sort", entry.key, level) end
    end, LabelFor(SORTS, "sort"))

    CreateDropdown("EverGearItemBrowserStatus", 110, "Check status", 456, -42, function(dropdown, level)
        AddOption(dropdown, "All", "status", nil, level)
        for _, entry in ipairs(STATUS_FILTERS) do AddOption(dropdown, entry.label, "status", entry.key, level) end
    end, LabelFor(STATUS_FILTERS, "status"))

    -- Row 2: slot, type, rarity, source, zone.
    local ROW2_Y = -84
    CreateDropdown("EverGearItemBrowserSlot", 70, "Slot", 4, ROW2_Y, function(dropdown, level)
        AddOption(dropdown, "All", "slot", nil, level)
        for _, slot in ipairs(SLOT_ORDER) do AddOption(dropdown, SlotLabel(slot), "slot", slot, level) end
    end, function() return filters.slot and SlotLabel(filters.slot) or "All" end)

    CreateDropdown("EverGearItemBrowserType", 70, "Type", 108, ROW2_Y, function(dropdown, level)
        AddOption(dropdown, "All", "type", nil, level)
        for _, key in ipairs(DistinctValues(TypeKey, TypeLabel)) do
            AddOption(dropdown, TypeLabel(key), "type", key, level)
        end
    end, function() return filters.type and TypeLabel(filters.type) or "All" end)

    CreateDropdown("EverGearItemBrowserRarity", 70, "Rarity", 212, ROW2_Y, function(dropdown, level)
        AddOption(dropdown, "All", "quality", nil, level)
        for quality = 0, 5 do
            local r, g, b = H.GetQualityColor(quality)
            local hex = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
            AddOption(dropdown, hex .. QUALITY_NAMES[quality] .. "|r", "quality", quality, level)
        end
        AddOption(dropdown, "Not loaded yet", "quality", "unknown", level)
    end, function()
        if filters.quality == nil then return "All" end
        if filters.quality == "unknown" then return "Not loaded" end
        return QUALITY_NAMES[filters.quality]
    end)

    CreateDropdown("EverGearItemBrowserSource", 90, "Source", 316, ROW2_Y, function(dropdown, level)
        AddOption(dropdown, "All", "source", nil, level)
        for _, key in ipairs(DistinctValues(SourceKey, SourceLabel)) do
            AddOption(dropdown, SourceLabel(key), "source", key, level)
        end
    end, function() return filters.source and SourceLabel(filters.source) or "All" end)

    CreateDropdown("EverGearItemBrowserZone", 100, "Zone", 440, ROW2_Y, function(dropdown, level, menuList)
        local zones = DistinctValues(function(item) return item.source and item.source.zone end,
            function(zone) return zone end)
        if level == 1 then
            AddOption(dropdown, "All", "zone", nil, level)
            for _, group in ipairs(ZONE_GROUPS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = group[1] .. " - " .. group[2]
                info.hasArrow = true
                info.notCheckable = true
                info.menuList = group
                UIDropDownMenu_AddButton(info, level)
            end
        elseif menuList then
            for _, zone in ipairs(zones) do
                local first = zone:gsub("^The ", ""):sub(1, 1):upper()
                if first >= menuList[1] and first <= menuList[2] then
                    AddOption(dropdown, zone, "zone", zone, level)
                end
            end
        end
    end, function() return filters.zone or "All" end)

    -- Row 3: debug mode, reset.
    local ROW3_Y = -138

    debugCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    debugCheck:SetSize(24, 24)
    debugCheck:SetPoint("TOPLEFT", 20, ROW3_Y + 2)
    local debugLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    debugLabel:SetPoint("LEFT", debugCheck, "RIGHT", 2, 0)
    debugLabel:SetText("Check against the game on hover (debug mode)")
    debugCheck:SetScript("OnClick", function(self)
        EverGear:HandleDebugCommand(self:GetChecked() and "on" or "off")
    end)

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(100, 22)
    reset:SetPoint("TOPRIGHT", -24, ROW3_Y)
    reset:SetText("Reset checks")
    reset:SetScript("OnClick", function()
        EverGearDB.debugChecked = {}
        ApplyFilters()
    end)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset checks")
        GameTooltip:AddLine("Forget which items matched or differed, e.g. after updating the addon's data.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", LIST_SIDE + 4, LIST_TOP + 2)
    countText:SetTextColor(unpack(THEME.parchment))

    -- The list. Rows sit directly in a clipping frame; scrolling re-fills them.
    scroll = CreateFrame("Frame", nil, frame)
    scroll:SetPoint("TOPLEFT", LIST_SIDE, LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -(LIST_SIDE + BAR_WIDTH + BAR_GAP), LIST_BOTTOM)
    rows = {}
    for i = 1, VISIBLE_ROWS do rows[i] = CreateRow(i) end

    bar = CreateFrame("Frame", nil, frame)
    bar:SetWidth(BAR_WIDTH)
    bar:SetPoint("TOPRIGHT", -LIST_SIDE, LIST_TOP)
    bar:SetPoint("BOTTOMRIGHT", -LIST_SIDE, LIST_BOTTOM)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.5)

    thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(BAR_WIDTH)
    thumb:SetHeight(40)
    thumb:SetPoint("TOP", bar, "TOP", 0, 0)
    local thumbTexture = thumb:CreateTexture(nil, "OVERLAY")
    thumbTexture:SetAllPoints()
    thumbTexture:SetColorTexture(THEME.goldDim[1], THEME.goldDim[2], THEME.goldDim[3], 0.9)
    thumb:SetHitRectInsets(-4, -4, 0, 0)
    thumb:SetScript("OnEnter", function() thumbTexture:SetVertexColor(1.25, 1.25, 1.25) end)
    thumb:SetScript("OnLeave", function() thumbTexture:SetVertexColor(1, 1, 1) end)

    local function CursorY()
        local _, y = GetCursorPosition()
        return y / bar:GetEffectiveScale()
    end
    local dragStartY, dragStartOffset
    thumb:SetScript("OnMouseDown", function() dragStartY, dragStartOffset = CursorY(), offset end)
    thumb:SetScript("OnUpdate", function()
        if not dragStartY then return end
        if not IsMouseButtonDown("LeftButton") then dragStartY = nil return end
        local movedDown = dragStartY - CursorY()
        local newOffset = dragStartOffset + movedDown / ThumbTravel() * MaxOffset()
        if math.floor(newOffset + 0.5) ~= offset then SetOffset(newOffset) end
    end)
    thumb:SetScript("OnMouseUp", function() dragStartY = nil end)
    thumb:SetScript("OnHide", function() dragStartY = nil end)

    bar:EnableMouse(true)
    bar:SetHitRectInsets(-4, -4, 0, 0)
    bar:SetScript("OnMouseDown", function()
        local top = bar:GetTop()
        if not top then return end
        local thumbTop = (top - CursorY()) - thumb:GetHeight() / 2
        SetOffset(thumbTop / ThumbTravel() * MaxOffset())
    end)

    local function OnWheel(_, delta) SetOffset(offset - delta * 3) end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", OnWheel)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", OnWheel)

    frame:SetScript("OnShow", function()
        debugCheck:SetChecked(EverGearDB.debugMode == true)
        ApplyFilters()
    end)
end

-- ===== Item cache =====
-- Rarity and the item link need the client's item cache. On open, ask the
-- server for every item a few at a time, and redraw (once things settle) as
-- the answers arrive, so the colors and the rarity filter fill in.

local REQUEST_BATCH = 40
local requestQueue, requestIndex

local requester = CreateFrame("Frame")
requester:Hide()
requester:SetScript("OnUpdate", function(self)
    local load = C_Item and C_Item.RequestLoadItemDataByID
    if not (load and requestQueue) then self:Hide() return end
    for _ = 1, REQUEST_BATCH do
        requestIndex = requestIndex + 1
        local itemId = requestQueue[requestIndex]
        if not itemId then self:Hide() return end
        if not Quality(itemId) then load(itemId) end
    end
end)

local function RequestAllItems()
    requestQueue, requestIndex = {}, 0
    for itemId in pairs(EverGear.Items) do requestQueue[#requestQueue + 1] = itemId end
    requester:Show()
end

local pendingRedraw = false
local cacheWatcher = CreateFrame("Frame")
cacheWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
cacheWatcher:SetScript("OnEvent", function()
    if not (frame and frame:IsShown()) or pendingRedraw then return end
    pendingRedraw = true
    if not (C_Timer and C_Timer.After) then pendingRedraw = false RefreshRows() return end
    C_Timer.After(0.5, function()
        pendingRedraw = false
        if not frame:IsShown() then return end
        -- Only a rarity filter changes which items are listed.
        if filters.quality ~= nil then
            local keep = offset
            ApplyFilters()
            SetOffset(keep)
        else
            RefreshRows()
        end
    end)
end)

-- ===== Public =====

function EverGear:ToggleItemBrowser()
    if not frame then BuildWindow() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        RequestAllItems()
    end
end

-- Called by Debug.lua after a hover check, and when debug mode is toggled.
function EverGear:OnItemBrowserCheck()
    if not (frame and frame:IsShown()) then return end
    debugCheck:SetChecked(EverGearDB.debugMode == true)
    -- Re-filters even without a status filter, to update the counts.
    local keep = offset
    ApplyFilters()
    SetOffset(keep)
end
