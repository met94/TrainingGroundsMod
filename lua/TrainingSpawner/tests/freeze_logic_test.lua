local scripts = "D:/Programowanie/payday/3/InsurancePolicySolo/TrainingGroundsMod/lua/TrainingSpawner/scripts"
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

check("NudgeDistance add", Logic.NudgeDistance(10, 1) == 11)
check("NudgeDistance sub", Logic.NudgeDistance(10, -1) == 9)
check("NudgeDistance clamp low", Logic.NudgeDistance(1, -5) == 1)
check("NudgeDistance clamp high", Logic.NudgeDistance(499.5, 5) == 500)

if failures > 0 then
    print(string.format("FAILURES: %d", failures))
    os.exit(1)
end
print("ALL PASS")
