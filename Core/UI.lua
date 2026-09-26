-- Minimal placeholder frame. Will grow into the same kind of upgrade-list panel
-- LevelGearAdvisor has, once there's real item data to show.

EverGear = EverGear or {}

local frame = CreateFrame("Frame", "EverGearFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(360, 420)
frame:SetPoint("CENTER")
frame:Hide()
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -5)
frame.title:SetText("EverGear")

local body = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
body:SetPoint("TOPLEFT", 16, -32)
body:SetPoint("BOTTOMRIGHT", -16, 16)
body:SetJustifyH("LEFT")
body:SetJustifyV("TOP")
frame.body = body

function EverGear:RefreshUI()
    local lines = {}
    for _, slotToken in ipairs(self.EQUIP_SLOTS) do
        local upgrades = self:GetUpgradesForSlot(slotToken)
        if #upgrades > 0 then
            table.insert(lines, slotToken .. ": " .. upgrades[1].name)
        end
    end
    if #lines == 0 then
        frame.body:SetText("No known upgrades yet. Item data for WoW Forever is still being added as EverGear's author levels through the game.")
    else
        frame.body:SetText(table.concat(lines, "\n"))
    end
end

frame:SetScript("OnShow", function() EverGear:RefreshUI() end)

EverGear.Frame = frame

SLASH_EVERGEAR1 = "/evergear"
SLASH_EVERGEAR2 = "/eg"
SlashCmdList["EVERGEAR"] = function()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
