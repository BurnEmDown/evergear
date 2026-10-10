-- A draggable minimap button so opening EverGear doesn't require remembering
-- the /evergear or /eg slash command. Built from plain frames/textures rather
-- than a minimap-button library (e.g. LibDBIcon) -- this addon doesn't pull
-- in any external libraries yet, and this client build has already shown a
-- couple of missing XML templates (see UI.lua's item-icon comment), so a
-- from-scratch implementation using only base widget types and textures that
-- are already confirmed safe elsewhere in this addon is the lower-risk path.

EverGear = EverGear or {}

-- Distance past the Minimap's edge, in pixels: the button sits outside the
-- rim, along the edge (half the Minimap's width + 17, tested in game -- 5,
-- LibDBIcon's value, still left it too far inside on this client).
local EDGE_OFFSET = 17

local button = CreateFrame("Button", "EverGearMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Icon: the addon's own icon (Icon.tga, ships at the addon's root -- also
-- used as ## IconTexture in the .toc), replacing the old EMPTY_SLOT_TEXTURES
-- placeholder now that a real one exists. Drawn edge-to-edge with its own
-- circular border baked in, so no TexCoord cropping needed here.
local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 0)
icon:SetTexture("Interface\\AddOns\\EverGear\\Icon")

-- Standard minimap-button ring border texture, same one Blizzard's own
-- tracking/calendar buttons use.
local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", 0, 0)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function UpdatePosition()
    local angle = math.rad(EverGearDB.minimapAngle or 225)
    local radius = (Minimap:GetWidth() / 2) + EDGE_OFFSET
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
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

-- The Minimap can change size (other addons, minimap scaling), so the radius
-- is re-read whenever it does.
Minimap:HookScript("OnSizeChanged", UpdatePosition)

UpdatePosition()
