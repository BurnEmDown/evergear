local addonName, ns = ...

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
loader:RegisterEvent("PLAYER_LEVEL_UP")
loader:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == addonName then
        EverGearDB = EverGearDB or {}
        print("|cff33ff99EverGear|r loaded. Type /evergear to open.")
    elseif event == "PLAYER_LOGIN" then
        -- Character name/realm are reliably available now; make the spec and profile
        -- dropdowns show what this character actually has saved.
        if EverGear.SyncSpecAndProfileDropdowns then EverGear:SyncSpecAndProfileDropdowns() end
        -- Characters with "Update zones to my level automatically" on get their zone filter refreshed.
        if EverGear.AutoUpdateZonesForLevel then EverGear:AutoUpdateZonesForLevel() end
    elseif event == "PLAYER_LEVEL_UP" and EverGear.AutoUpdateZonesForLevel and EverGear:IsAutoZonesOn() then
        -- loadedAddon is the new level here (the event's first argument).
        EverGear:AutoUpdateZonesForLevel(loadedAddon)
    elseif EverGear.Frame and EverGear.Frame:IsShown() then
        EverGear:RefreshUI()
    end
end)
