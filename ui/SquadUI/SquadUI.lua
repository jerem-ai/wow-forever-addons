local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end

local function Say(message) print("Squad UI: " .. message) end
local function State()
    if type(SquadUIState) ~= "table" then SquadUIState = {} end
    return SquadUIState
end

local function Parent(path)
    local target = _G
    for i = 1, #path - 1 do
        assert(type(target[path[i]]) == "table", "A saved setting changed shape")
        target = target[path[i]]
    end
    return target, path[#path]
end

local function Restore(undo)
    for i = #undo.values, 1, -1 do
        local saved = undo.values[i]
        local target, key = Parent(saved.path)
        target[key] = Copy(saved.value)
    end
    for name, enabled in pairs(undo.addons) do
        if enabled then C_AddOns.EnableAddOn(name, undo.character)
        else C_AddOns.DisableAddOn(name, undo.character) end
    end
    for name, value in pairs(undo.cvars) do C_CVar.SetCVar(name, value) end
    if XPerl_RestoreAllPositions then XPerl_RestoreAllPositions() end
end

local function Change(undo, path, value)
    local target = _G
    for i = 1, #path - 1 do
        local key = path[i]
        if target[key] == nil then
            local prefix = {}
            for n = 1, i do prefix[n] = path[n] end
            undo.values[#undo.values + 1] = {path = prefix}
            target[key] = {}
        end
        assert(type(target[key]) == "table", "A saved setting changed shape")
        target = target[key]
    end
    local key = path[#path]
    undo.values[#undo.values + 1] = {path = Copy(path), value = Copy(target[key])}
    target[key] = Copy(value)
end

local function Fields(undo, path, values)
    for key, value in pairs(values) do
        local full = Copy(path); full[#full + 1] = key
        Change(undo, full, value)
    end
end

local function ApplySettings(undo)
    local character, realm = UnitName("player"), GetRealmName()
    if type(ZPerlConfigNew) == "table" and type(XPerlDB) == "table" then
        local base = {"ZPerlConfigNew", "global"}
        if ZPerlConfigSavePerCharacter then base = {"ZPerlConfigNew", realm, character} end
        for _, unit in ipairs({"player", "target", "focus", "party", "pet"}) do
            local path = Copy(base); path[#path + 1] = unit
            Fields(undo, path, {portrait = false, portrait3D = false})
        end
        local function Config(path, values)
            local full = Copy(base)
            for _, key in ipairs(path) do full[#full + 1] = key end
            Fields(undo, full, values)
        end
        Config({"player"}, {scale = 1})
        Config({"target"}, {scale = 1})
        Config({"player", "buffs"}, {size = 36})
        Config({"player", "debuffs"}, {size = 38})
        Config({"target", "debuffs"}, {size = 34})
        Config({"bar"}, {texture = {"Flat", "Interface\\Buttons\\WHITE8X8"}})
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        local left, top = math.max(16, width / 2 - 270), math.max(190, math.min(300, height * 0.34))
        for name, position in pairs({
            XPerl_Player = {left = left, top = top},
            XPerl_Target = {left = width / 2 + 70, top = top},
            XPerl_TargetTarget = {left = width / 2 + 70, top = top - 80},
            XPerl_Player_Pet = {left = left, top = top - 80},
            XPerl_Focus = {left = left, top = top + 140},
            XPerl_Party_Anchor = {left = 24, top = height * 0.8},
        }) do
            Change(undo, {"ZPerlConfigNew", "savedPositions", realm, character, name}, position)
        end
    end
    if type(XPerlXPCCDB) == "table" then
        Fields(undo, {"XPerlXPCCDB"}, {enabled = true, buffs = true, debuffs = true, player = true,
            target = true, party = true, colors = true, outline = true, tenths = true,
            size = 18, iconBorder = false, nameplates = false, optInVersion = 1})
    end
    if Questie and Questie.db and type(QuestieConfig) == "table" then
        local profile = Questie.db:GetCurrentProfile()
        Fields(undo, {"QuestieConfig", "profiles", profile}, {trackerEnabled = false,
            nameplateEnabled = false, nameplateTargetFrameEnabled = false,
            questAnnounceItems = false, questAnnounceAccepted = false, questAnnounceAbandoned = false,
            questAnnounceObjectives = false, questAnnounceCompleted = false})
    end
    if QuestTogether and QuestTogether.db and QuestTogether.GetCurrentProfileKey then
        local profile = QuestTogether:GetCurrentProfileKey()
        if profile then
            Fields(undo, {"QuestTogetherDB", "profiles", profile}, {hideMyOwnChatBubbles = true,
                announceAccepted = false, announceRemoved = false, announceProgress = false,
                emoteOnQuestCompletion = false, emoteOnNearbyPlayerQuestCompletion = false,
                emoteOnLevelUp = false, emoteOnNearbyPlayerLevelUp = false,
                nameplateQuestIconEnabled = false, nameplateQuestHealthColorEnabled = false,
                questTrackerMode = "hover", questTrackerHideSolo = true})
        end
    end
    if type(LeaPlusDB) == "table" then Fields(undo, {"LeaPlusDB"}, {AutomateQuests = "Off"}) end
    if type(AUCTIONATOR_CONFIG) == "table" then
        Fields(undo, {"AUCTIONATOR_CONFIG"}, {auction_tooltips = true, enchant_tooltips = true})
    end
    local profile = DBM_UsedProfile or "Default"
    if type(DBM_AllSavedOptions) == "table" and type(DBM_AllSavedOptions[profile]) == "table" then
        Fields(undo, {"DBM_AllSavedOptions", profile}, {WarningFontSize = 22, SpecialWarningFontSize2 = 38})
    end
    if type(DBT_AllPersistentOptions) == "table" and type(DBT_AllPersistentOptions[profile]) == "table" then
        Fields(undo, {"DBT_AllPersistentOptions", profile, "DBM"}, {FontFlag = "OUTLINE", FontShadow = true,
            FontSize = 14, Width = 220, Height = 22, HugeWidth = 240, HugeHeight = 24})
    end
    for _, name in ipairs({"nameplateShowFriends", "nameplateShowFriendlyNPCs"}) do
        local value = C_CVar.GetCVar(name)
        if value ~= nil then undo.cvars[name] = value; C_CVar.SetCVar(name, "0") end
    end
    for _, name in ipairs(SquadUIOptionalAddons) do
        if C_AddOns.DoesAddOnExist(name) then
            local enabled = C_AddOns.GetAddOnEnableState(name, character) > 0
            if enabled then undo.addons[name] = true; C_AddOns.DisableAddOn(name, character) end
        end
    end
    if XPerl_RestoreAllPositions then XPerl_RestoreAllPositions() end
end

local function ReloadNotice() StaticPopup_Show("SQUADUI_RELOAD") end

local function Apply()
    if InCombatLockdown() then Say("Leave combat before applying the preset."); return end
    local state = State()
    if state.undo then Say("Already applied. Your later edits are kept; /squadui undo restores the previous setup."); return end
    -- Capture the visible positions before changing them, including a first-login layout not yet saved by X-Perl.
    if XPerl_SavePosition then
        for _, name in ipairs({"XPerl_Player", "XPerl_Target", "XPerl_TargetTarget", "XPerl_Player_Pet", "XPerl_Focus", "XPerl_Party_Anchor"}) do
            local frame = _G[name]
            if frame and frame:GetTop() and frame:GetLeft() then XPerl_SavePosition(frame) end
        end
    end
    local undo = {values = {}, addons = {}, cvars = {}, character = UnitName("player")}
    local ok, err = pcall(ApplySettings, undo)
    if not ok then
        Restore(undo)
        Say("Changes rolled back: " .. tostring(err))
        return
    end
    state.undo, state.applied = undo, true
    Say("Preset saved for this character. Reload to finish. /squadui undo restores the previous setup.")
    ReloadNotice()
end

local function Undo()
    if InCombatLockdown() then Say("Leave combat before restoring the previous setup."); return end
    local state = State()
    if not state.undo then Say("No preset changes to undo."); return end
    Restore(state.undo)
    state.undo, state.applied = nil, false
    Say("Previous settings and optional addons restored. Reload to finish.")
    ReloadNotice()
end

StaticPopupDialogs.SQUADUI_APPLY = {
    text = "Use the squad UI? This enlarges buff timers, positions player and target frames, keeps one quest tracker, and turns off optional extras on this character. Appearance changes affect shared addon profiles too. Your saved data is kept. /squadui undo restores the previous setup.",
    button1 = "Apply preset", button2 = "Keep my UI", OnAccept = Apply,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs.SQUADUI_RELOAD = {
    text = "Squad UI settings are saved. Reload the interface to finish?",
    button1 = "Reload", button2 = "Later", OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
SLASH_SQUADUI1 = "/squadui"
SlashCmdList.SQUADUI = function(command)
    command = (command or ""):lower():match("^%s*(.-)%s*$")
    if command == "undo" then Undo()
    elseif command == "apply" then Apply()
    elseif command == "status" then Say(State().applied and "Preset applied on this character." or "Your current UI is kept. /squadui applies the optional preset.")
    else StaticPopup_Show("SQUADUI_APPLY") end
end
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    local state = State()
    if not state.noticed then
        state.noticed = true
        Say("Optional squad preset available: /squadui. Your current UI is kept until you apply it.")
    end
end)
