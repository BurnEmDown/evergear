local addonName, ns = ...

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
loader:RegisterEvent("PLAYER_LEVEL_UP")
loader:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == addonName then
        EverGearDB = EverGearDB or {}
        print("|cff33ff99EverGear|r loaded. Type /evergear to open.")
    elseif EverGear.Frame and EverGear.Frame:IsShown() then
        EverGear:RefreshUI()
    end
end)
