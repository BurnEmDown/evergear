-- A draggable minimap button so opening EverGear doesn't require remembering
-- the /evergear or /eg slash command. Built from plain frames/textures rather
-- than a minimap-button library (e.g. LibDBIcon) -- this addon doesn't pull
-- in any external libraries yet, and this client build has already shown a
-- couple of missing XML templates (see UI.lua's item-icon comment), so a
-- from-scratch implementation using only base widget types and textures that
-- are already confirmed safe elsewhere in this addon is the lower-risk path.

EverGear = EverGear or {}

local RADIUS = 80  -- distance from Minimap's center, in pixels

local button = CreateFrame("Button", "EverGearMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Icon: reuses a texture already proven to load fine in this client (it's
-- one of the EMPTY_SLOT_TEXTURES in Constants.lua), rather than guessing at
-- an icon path that might not exist here.
local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 0)
icon:SetTexture(EverGear.EMPTY_SLOT_TEXTURES and EverGear.EMPTY_SLOT_TEXTURES.ChestSlot or "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Chest")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- Standard minimap-button ring border texture, same one Blizzard's own
-- tracking/calendar buttons use.
local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", 0, 0)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function UpdatePosition()
    local angle = math.rad(EverGearDB.minimapAngle or 225)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

button:SetScript("OnClick", function()
    EverGear:ToggleUI()
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("EverGear")
    GameTooltip:AddLine("Click to open/close.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag to move this button.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        EverGearDB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
        UpdatePosition()
    end)
end)
button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

UpdatePosition()
