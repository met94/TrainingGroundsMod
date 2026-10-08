local Source = debug.getinfo(1, "S").source
local Dir = Source:match("^@(.*)[/\\][^/\\]*$")
if Dir == nil then error("cannot resolve freeze_logic_test.lua directory") end
local scripts = Dir .. "/../scripts"
package.path = scripts .. "/?.lua;" .. package.path
local Logic = require("freeze_logic")

local failures = 0
local function check(name, cond)
    if cond then
        print("PASS " .. name)
    else
        print("FAIL " .. name)
        failures = failures + 1
    end
end

check("reason constant", Logic.REASON == "TrainingSpawner")
check("marker constant", Logic.HANDLE_MARKER == "NewShootingRange")

check("ShouldHandle range world", Logic.ShouldHandle(
    "World /Game/DLCs/00232-JUDGEMENT/NewShootingRange/NewShootingRange.NewShootingRange") == true)
check("ShouldHandle other world", Logic.ShouldHandle("World /Game/DLCs/00110-FREE0003/Maps/ONE.ONE") == false)
check("ShouldHandle nil", Logic.ShouldHandle(nil) == false)
check("ShouldHandle number", Logic.ShouldHandle(42) == false)

check("roster count = 15", #Logic.ROSTER == 15)
local allClasses = true
for _, e in ipairs(Logic.ROSTER) do
    if type(e.path) ~= "string" or not e.path:find("_C$") then allClasses = false end
end
check("roster classes end _C", allClasses)
check("roster has Dozer", Logic.ROSTER[11].path == "/Game/Gameplay/Characters/Cop/CH_Dozer.CH_Dozer_C")
local hasMoon, hasGuard = false, false
for _, e in ipairs(Logic.ROSTER) do
    if e.name == "Moon" then hasMoon = true end
    if e.name == "Guard" then hasGuard = true end
end
check("roster has no Moon", hasMoon == false)
check("roster has no Guard", hasGuard == false)

local slots = Logic.BuildLayout(#Logic.ROSTER)
check("layout count", #slots == 15)
local inRange = true
for _, s in ipairs(slots) do
    if s.dist < 800 or s.dist > 1200 then inRange = false end
end
check("layout distances 800-1200", inRange)
check("front row 8", slots[1].dist == 800 and slots[8].dist == 800 and slots[9].dist == 1200)
check("front first = -70", math.abs(slots[1].yawOffsetDeg + 70) < 1e-9)
check("front last = +70", math.abs(slots[8].yawOffsetDeg - 70) < 1e-9)
check("back first = -70", math.abs(slots[9].yawOffsetDeg + 70) < 1e-9)
check("back last = +70", math.abs(slots[15].yawOffsetDeg - 70) < 1e-9)
check("back row 7", slots[15].dist == 1200)
check("front inner pair symmetric", math.abs(slots[4].yawOffsetDeg + 10) < 1e-9 and math.abs(slots[5].yawOffsetDeg - 10) < 1e-9)

-- v0.5.0 additions: cyclers, config, nudge
-- (NeedsFreeze / DistancesFromCm / FacingYaw / DifficultyName moved to pd3lib;
--  covered by shared/pd3lib/tests)
check("CycleIndex forward wrap", Logic.CycleIndex(3, 3, 1) == 1)
check("CycleIndex backward wrap", Logic.CycleIndex(1, 3, -1) == 3)
check("CycleIndex within", Logic.CycleIndex(1, 3, 1) == 2)
check("CycleIndex count 1", Logic.CycleIndex(1, 1, 5) == 1)
check("CycleIndex nil count", Logic.CycleIndex(1, nil, 1) == 1)
check("CycleIndex nil index", Logic.CycleIndex(nil, 4, 1) == 2)

local cfg = Logic.MergeConfig(nil)
check("MergeConfig defaults", cfg.distanceMode == "auto" and cfg.freeze == true and #cfg.distances == 6)
local cfg2 = Logic.MergeConfig({ distanceMode = "manual", distances = { 7, 11 }, freeze = false })
check("MergeConfig manual", cfg2.distanceMode == "manual" and cfg2.distances[1] == 7 and cfg2.freeze == false)
local cfg3 = Logic.MergeConfig({ distances = { -1, "x" } })
check("MergeConfig invalid distances rejected", #cfg3.distances == 6)
local cfg4 = Logic.MergeConfig({ distanceMode = "bogus" })
check("MergeConfig invalid mode rejected", cfg4.distanceMode == "auto")
check("MergeConfig chatNotice default", cfg.chatNotice == true)
check("MergeConfig chatNotice false honored", Logic.MergeConfig({ chatNotice = false }).chatNotice == false)
check("MergeConfig chatNotice invalid ignored", Logic.MergeConfig({ chatNotice = 1 }).chatNotice == true)
check("MergeConfig keepSubjects default", cfg.keepSubjects == false)
check("MergeConfig keepSubjects true honored", Logic.MergeConfig({ keepSubjects = true }).keepSubjects == true)
check("MergeConfig keepSubjects invalid ignored", Logic.MergeConfig({ keepSubjects = 1 }).keepSubjects == false)

check("NudgeDistance add", Logic.NudgeDistance(10, 1) == 11)
check("NudgeDistance sub", Logic.NudgeDistance(10, -1) == 9)
check("NudgeDistance clamp low", Logic.NudgeDistance(1, -5) == 1)
check("NudgeDistance clamp high", Logic.NudgeDistance(499.5, 5) == 500)

-- v0.6.0 additions: configurable keybindings (keys table in user_config.lua).
-- call() distinguishes "returned nil because rejected" from "missing / crashed".
local function call(fn, ...)
    if type(fn) ~= "function" then return nil, "missing function", false end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil, "pcall error: " .. tostring(a), false end
    return a, b, true
end

check("KEY_ACTIONS exists", type(Logic.KEY_ACTIONS) == "table")
check("KEY_ACTIONS has 12 actions", type(Logic.KEY_ACTIONS) == "table" and #Logic.KEY_ACTIONS == 12)
check("DEFAULT_KEYS exists", type(Logic.DEFAULT_KEYS) == "table")
check("DEFAULT_KEYS freezeToggle = F11",
    type(Logic.DEFAULT_KEYS) == "table" and Logic.DEFAULT_KEYS.freezeToggle == "F11")
local defaultsCoverAll = type(Logic.KEY_ACTIONS) == "table" and type(Logic.DEFAULT_KEYS) == "table"
if defaultsCoverAll then
    for _, action in ipairs(Logic.KEY_ACTIONS) do
        if type(Logic.DEFAULT_KEYS[action]) ~= "string" then defaultsCoverAll = false end
    end
end
check("DEFAULT_KEYS covers every action", defaultsCoverAll)

local spec1 = call(Logic.ParseKeySpec, "F5")
check("ParseKeySpec bare key", type(spec1) == "table" and spec1.key == "F5" and #spec1.mods == 0)

local spec2 = call(Logic.ParseKeySpec, "Shift+F7")
check("ParseKeySpec shift modifier", type(spec2) == "table" and spec2.key == "F7"
    and #spec2.mods == 1 and spec2.mods[1] == "SHIFT")

local spec3 = call(Logic.ParseKeySpec, "ctrl+shift+f9")
check("ParseKeySpec lowercase + canonical order", type(spec3) == "table" and spec3.key == "F9"
    and #spec3.mods == 2 and spec3.mods[1] == "SHIFT" and spec3.mods[2] == "CONTROL")

local spec4 = call(Logic.ParseKeySpec, " Shift + alt + f10 ")
check("ParseKeySpec trims whitespace", type(spec4) == "table" and spec4.key == "F10"
    and #spec4.mods == 2 and spec4.mods[1] == "SHIFT" and spec4.mods[2] == "ALT")

local badNil, badNilErr, badNilExisted = call(Logic.ParseKeySpec, nil)
check("ParseKeySpec nil rejected", badNilExisted and badNil == nil and type(badNilErr) == "string")
local badNum, badNumErr, badNumExisted = call(Logic.ParseKeySpec, 123)
check("ParseKeySpec non-string rejected", badNumExisted and badNum == nil and type(badNumErr) == "string")
local badEmpty, badEmptyErr, badEmptyExisted = call(Logic.ParseKeySpec, "")
check("ParseKeySpec empty rejected", badEmptyExisted and badEmpty == nil and type(badEmptyErr) == "string")
local badDangle, badDangleErr, badDangleExisted = call(Logic.ParseKeySpec, "Shift+")
check("ParseKeySpec dangling modifier rejected", badDangleExisted and badDangle == nil and type(badDangleErr) == "string")
local badDup, badDupErr, badDupExisted = call(Logic.ParseKeySpec, "Shift+Shift+F5")
check("ParseKeySpec duplicate modifier rejected", badDupExisted and badDup == nil and type(badDupErr) == "string")
local badMod, badModErr, badModExisted = call(Logic.ParseKeySpec, "Foo+F5")
check("ParseKeySpec unknown modifier rejected", badModExisted and badMod == nil and type(badModErr) == "string")
local badTwoKeys, badTwoKeysErr, badTwoKeysExisted = call(Logic.ParseKeySpec, "F5+F6")
check("ParseKeySpec second key rejected", badTwoKeysExisted and badTwoKeys == nil and type(badTwoKeysErr) == "string")

local m1, _, m1Existed = call(Logic.MergeKeys, nil)
check("MergeKeys nil -> defaults", m1Existed and type(m1) == "table"
    and #m1.bindings == 12 and #m1.disabled == 0 and #m1.warnings == 0)
local m1Ordered = m1Existed and type(m1) == "table"
if m1Ordered then
    for i, action in ipairs(Logic.KEY_ACTIONS) do
        if not m1.bindings[i] or m1.bindings[i].action ~= action then m1Ordered = false end
    end
end
check("MergeKeys bindings follow KEY_ACTIONS order", m1Ordered)
check("MergeKeys defaults carry parsed key/mods",
    m1Existed and type(m1) == "table" and m1.bindings[1] ~= nil
    and type(m1.bindings[1].key) == "string" and type(m1.bindings[1].mods) == "table")

local m2, _, m2Existed = call(Logic.MergeKeys, false)
check("MergeKeys false -> all disabled", m2Existed and type(m2) == "table"
    and #m2.bindings == 0 and #m2.disabled == 12)

local m3, _, m3Existed = call(Logic.MergeKeys, {})
check("MergeKeys empty table -> all disabled", m3Existed and type(m3) == "table"
    and #m3.bindings == 0 and #m3.disabled == 12 and #m3.warnings == 0)
check("MergeKeys allDisabled flag only for keys = false",
    m2Existed and type(m2) == "table" and m2.allDisabled == true
    and m3Existed and type(m3) == "table" and m3.allDisabled ~= true)

local m4, _, m4Existed = call(Logic.MergeKeys, { clear = "F5", freezeToggle = "F11" })
local m4Has = { clear = false, freezeToggle = false }
if m4Existed and type(m4) == "table" then
    for _, b in ipairs(m4.bindings) do
        if b.action == "clear" and b.spec == "F5" then m4Has.clear = true end
        if b.action == "freezeToggle" and b.spec == "F11" then m4Has.freezeToggle = true end
    end
end
check("MergeKeys only listed actions bound", m4Existed and type(m4) == "table"
    and #m4.bindings == 2 and #m4.disabled == 10 and m4Has.clear and m4Has.freezeToggle)

local m5, _, m5Existed = call(Logic.MergeKeys, { clear = "F5", enemyNext = false })
check("MergeKeys false entry disables", m5Existed and type(m5) == "table"
    and #m5.bindings == 1 and #m5.disabled == 11)

local m6, _, m6Existed = call(Logic.MergeKeys, { clear = "Shift+Shift+F5" })
check("MergeKeys invalid spec disabled + warned", m6Existed and type(m6) == "table"
    and #m6.bindings == 0 and #m6.disabled == 12 and #m6.warnings == 1)

local m7, _, m7Existed = call(Logic.MergeKeys, { clear = 42 })
check("MergeKeys non-string disabled + warned", m7Existed and type(m7) == "table"
    and #m7.bindings == 0 and #m7.disabled == 12 and #m7.warnings == 1)

local m8, _, m8Existed = call(Logic.MergeKeys, { bogusAction = "F1" })
check("MergeKeys unknown action warned", m8Existed and type(m8) == "table" and #m8.warnings == 1)

local m9, _, m9Existed = call(Logic.MergeKeys, "F5")
check("MergeKeys non-table -> defaults + warned", m9Existed and type(m9) == "table"
    and #m9.bindings == 12 and #m9.disabled == 0 and #m9.warnings == 1)

-- load robustness: an action without a valid default must be logged, not crash the mod load
table.insert(Logic.KEY_ACTIONS, "zzMissingDefault")
local guardOk, guardResult = pcall(Logic.MergeKeys, nil)
table.remove(Logic.KEY_ACTIONS)
check("MergeKeys missing default degrades gracefully", guardOk and type(guardResult) == "table"
    and #guardResult.bindings == 12 and #guardResult.disabled == 1 and #guardResult.warnings == 1)

if failures > 0 then
    print(string.format("FAILURES: %d", failures))
    os.exit(1)
end
print("ALL PASS")
