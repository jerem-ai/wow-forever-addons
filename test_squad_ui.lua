local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}; for k, x in pairs(v) do t[k] = copy(x) end; return t
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function fixture(width, height)
    local enabled = {Details = true, Questie = true, Syndicator = true, OtherCharacter = true}
    local cv = {nameplateShowFriends = "1", nameplateShowFriendlyNPCs = "1"}
    local env = setmetatable({StaticPopupDialogs = {}, SlashCmdList = {}, print = function() end,
        UnitName = function() return "Someone Else" end, GetRealmName = function() return "A Different Realm" end,
        InCombatLockdown = function() return false end, StaticPopup_Show = function() end, ReloadUI = function() error("unrequested reload") end,
        UIParent = {GetWidth = function() return width end, GetHeight = function() return height end},
        CreateFrame = function() return {RegisterEvent = function() end, SetScript = function() end} end,
        C_CVar = {GetCVar = function(k) return cv[k] end, SetCVar = function(k, v) cv[k] = v end},
        C_AddOns = {
            DoesAddOnExist = function(n) return enabled[n] ~= nil end,
            GetAddOnEnableState = function(n, c) assert(c == "Someone Else"); return enabled[n] and 2 or 0 end,
            DisableAddOn = function(n, c) assert(c == "Someone Else"); enabled[n] = false end,
            EnableAddOn = function(n, c) assert(c == "Someone Else"); enabled[n] = true end,
        },
        ZPerlConfigNew = {global = {player = {portrait = 1}, target = {}, focus = {}, party = {}, pet = {}}},
        XPerlDB = {}, XPerlXPCCDB = {enabled = false, size = 12},
        QuestieConfig = {profiles = {["Healer's UI #2"] = {enabled = false, trackerEnabled = true, keep = 17}}},
        Questie = {db = {GetCurrentProfile = function() return "Healer's UI #2" end}},
        QuestTogetherDB = {profiles = {friend = {announceAccepted = true}}},
        QuestTogether = {db = {}, GetCurrentProfileKey = function() return "friend" end},
        AUCTIONATOR_CONFIG = {enchant_tooltips = false}, AUCTIONATOR_PRICE_DATABASE = {valuable = "keep this"},
        LeaPlusDB = {AutomateQuests = "On"}, DBM_AllSavedOptions = {Default = {WarningFontSize = 20}},
        DBT_AllPersistentOptions = {Default = {DBM = {Width = 183}}},
    }, {__index = _G})
    env._G = env
    for _, file in ipairs({"Optional.lua", "SquadUI.lua"}) do
        local chunk = assert(loadfile("ui/SquadUI/" .. file)); setfenv(chunk, env); chunk()
    end
    return env, enabled, cv
end
local roots = {"ZPerlConfigNew", "XPerlXPCCDB", "QuestieConfig", "QuestTogetherDB", "AUCTIONATOR_CONFIG", "AUCTIONATOR_PRICE_DATABASE", "LeaPlusDB", "DBM_AllSavedOptions", "DBT_AllPersistentOptions"}
for _, size in ipairs({{1280, 720}, {1920, 1080}, {3840, 2160}}) do
    local e, enabled, cv = fixture(unpack(size)); local before = {}
    for _, k in ipairs(roots) do before[k] = copy(e[k]) end
    e.SlashCmdList.SQUADUI("apply")
    assert(e.SquadUIState.applied)
    assert(e.XPerlXPCCDB.enabled and e.XPerlXPCCDB.size == 18)
    assert(e.QuestieConfig.profiles["Healer's UI #2"].enabled == false, "map visibility choice changed")
    assert(e.QuestieConfig.profiles["Healer's UI #2"].trackerEnabled == false)
    assert(not enabled.Details and enabled.Questie and enabled.Syndicator and enabled.OtherCharacter)
    local p = e.ZPerlConfigNew.savedPositions["A Different Realm"]["Someone Else"]
    assert(p.XPerl_Player.left > 0 and p.XPerl_Target.left + 220 < size[1])
    assert(p.XPerl_Player.top > 150 and p.XPerl_Player.top < size[2] / 2)
    assert(e.AUCTIONATOR_PRICE_DATABASE.valuable == "keep this")
    e.XPerlXPCCDB.size = 19
    e.SlashCmdList.SQUADUI("apply"); assert(e.XPerlXPCCDB.size == 19, "preset reapplied over a later choice")
    -- SavedVariables contains plain values; a fresh Lua load must still be able to undo.
    e.SquadUIState = copy(e.SquadUIState)
    local chunk = assert(loadfile("ui/SquadUI/SquadUI.lua")); setfenv(chunk, e); chunk()
    e.SlashCmdList.SQUADUI("undo")
    for _, k in ipairs(roots) do assert(equal(e[k], before[k]), "undo changed " .. k) end
    assert(enabled.Details and cv.nameplateShowFriends == "1" and not e.SquadUIState.applied)
end
do
    local e, enabled, cv = fixture(1920, 1080)
    e.InCombatLockdown = function() return true end
    e.SlashCmdList.SQUADUI("apply")
    assert(e.SquadUIState == nil and enabled.Details and cv.nameplateShowFriends == "1")
end
do
    local e, enabled = fixture(1920, 1080)
    e.ZPerlConfigNew.global.player = "unexpected saved data"
    local before = copy(e.ZPerlConfigNew)
    e.SlashCmdList.SQUADUI("apply")
    assert(equal(e.ZPerlConfigNew, before) and enabled.Details and not e.SquadUIState.applied, "partial failure was not rolled back")
end
do
    local e = fixture(1920, 1080)
    for _, k in ipairs(roots) do e[k] = nil end
    e.XPerlDB, e.Questie, e.QuestTogether = nil, nil, nil
    e.SlashCmdList.SQUADUI("apply"); assert(e.SquadUIState.applied)
    e.SlashCmdList.SQUADUI("undo"); assert(not e.SquadUIState.applied)
end
print("Squad UI: apply, undo, combat refusal, rollback, unusual profiles, missing addons and screen sizes passed")
