-- TrainingSpawner v0.5.2: test-rig spawner for the Shooting Range (NewShootingRange).
-- No auto-spawn. F8 spawns the selected enemy at the selected distance, facing you.
-- Engine work goes through the vendored pd3lib (classes loader, spawn, ai, weapons, mission).
-- Keys:
--   F5            clear all spawned subjects
--   F7 / Shift+F7 next / previous enemy (roster of 15)
--   F8            spawn selected enemy (replaces the previous F8 subject)
--   Shift+F8      spawn the full-roster arc (legacy mode)
--   F9 / Shift+F9 next / previous distance breakpoint
--   Ctrl+F9       +1 m fine nudge (Ctrl+Shift+F9 = -1 m)
--   F10 / Shift+F10  next / previous difficulty (Normal..Overkill)
local MOD_NAME = "TrainingSpawner"

local OkPd3, pd3 = pcall(require, "pd3lib")
if not OkPd3 or pd3 == nil then
    print(string.format("[%s] pd3lib load failed: %s\n", MOD_NAME, tostring(pd3)))
    return
end
pd3.Init({ prefix = "[" .. MOD_NAME .. "]", debug = false })

local OkLogic, Logic = pcall(require, "freeze_logic")
if not OkLogic or Logic == nil then
    print(string.format("[%s] freeze_logic load failed: %s\n", MOD_NAME, tostring(Logic)))
    return
end
local OkConfig, UserConfig = pcall(require, "user_config")
local config = Logic.MergeConfig(OkConfig and UserConfig or nil)

local Safe = pd3.safe
local Classes = pd3.classes
local Spawn = pd3.spawn
local AI = pd3.ai
local Weapons = pd3.weapons
local Mission = pd3.mission
local World = pd3.world
local Chat = pd3.chat

local LOADS_PER_TICK = 2
local MAX_LOAD_ATTEMPTS = 8
local SPAWNS_PER_TICK = 3
local RANGE_REFRESH_SECONDS = 5
local DIFFICULTY_COUNT = 4

local log
local classLoader = Classes.NewLoader({
    BudgetPerTick = LOADS_PER_TICK,
    MaxAttempts = MAX_LOAD_ATTEMPTS,
    Log = function(fmt, ...) log(fmt, ...) end,
})

local pendingSpawns = {}
local spawnContext = nil
local spawned = {}
local testSubject = nil
local pendingDifficultyCheckAt = nil

local enemyIndex = 1
local difficultyIndex = nil
local distances = config.distances
local distanceSource = (config.distanceMode == "manual") and "manual" or "fallback"
local distanceIndex = 1
local currentDistance = nil
local lastRangeRefresh = -RANGE_REFRESH_SECONDS

log = function(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print(string.format("[%s] %s\n", MOD_NAME, ok and s or tostring(fmt)))
end

local function tryE(label, fn)
    local ok, res = pcall(fn)
    if not ok then
        log("%s ERROR: %s", label, tostring(res))
        return nil
    end
    return res
end

local function field(obj, name)
    if obj == nil then return nil end
    local ok, value = pcall(function() return obj[name] end)
    if ok then return value end
    return nil
end

-- ---------------------------------------------------------------------------
-- Class loading (incremental, non-fatal; pd3lib.core.classes)
-- ---------------------------------------------------------------------------

local function enqueueUnresolved()
    local paths = {}
    for _, entry in ipairs(Logic.ROSTER) do
        if classLoader:Get(entry.path) == nil then
            paths[#paths + 1] = entry.path
        end
    end
    classLoader:Enqueue(paths)
end

-- ---------------------------------------------------------------------------
-- Spawning (pd3lib.game.spawn)
-- ---------------------------------------------------------------------------

local function destroyAll()
    local n = 0
    for _, entry in ipairs(spawned) do
        if Safe.IsValid(entry.actor) then
            tryE("destroy " .. entry.name, function() return Spawn.Destroy(entry.actor) end)
            n = n + 1
        end
    end
    spawned = {}
    pendingSpawns = {}
    spawnContext = nil
    testSubject = nil
    AI.Reset()
    log("cleared %d actors", n)
end

local function beginSpawnContext()
    spawnContext = nil
    local pc = World.GetPlayerController()
    if not Safe.IsValid(pc) then return false end
    local pawn = Safe.Get(pc, "Pawn")
    if not Safe.IsValid(pawn) then return false end

    local pawnLoc = tryE("pawn location", function() return pawn:K2_GetActorLocation() end)
    local controlRot = tryE("control rotation", function() return pc:GetControlRotation() end)
    if not controlRot then controlRot = tryE("pawn rotation", function() return pawn:K2_GetActorRotation() end) end
    if not pawnLoc or not controlRot then return false end

    spawnContext = {
        x = tonumber(field(pawnLoc, "X")) or 0,
        y = tonumber(field(pawnLoc, "Y")) or 0,
        z = tonumber(field(pawnLoc, "Z")) or 0,
        yawBase = tonumber(field(controlRot, "Yaw")) or 0,
    }
    return true
end

local function spawnOne(item, cls)
    if not Safe.IsValid(cls) or not item.slot or not spawnContext then return false end

    local yaw = spawnContext.yawBase + item.slot.yawOffsetDeg
    local lx, ly = Spawn.OffsetLocation(spawnContext.x, spawnContext.y, yaw, item.slot.dist)
    local facing = Spawn.FacingYaw(yaw)
    local actor, err = Spawn.ActorFromClass(cls, { X = lx, Y = ly, Z = spawnContext.z }, facing)
    if not Safe.IsValid(actor) then
        log("spawn FAIL: %s (%s)", item.name, tostring(err))
        return false
    end

    local entry = { actor = actor, name = item.name, noFreeze = item.noFreeze or false }
    spawned[#spawned + 1] = entry
    log("spawned %s at %.2f m (%s)", item.name, item.slot.dist / 100, item.noFreeze and "unfrozen" or "frozen")
    if item.subject then testSubject = entry end
    return true
end

local function drainSpawns()
    if #pendingSpawns == 0 or not spawnContext then return end
    local survivors = {}
    local spawnedNow = 0
    for _, item in ipairs(pendingSpawns) do
        local state = classLoader:Get(item.path)
        if state == false then
            -- gave up on this class: drop the request (logged at load time)
        elseif spawnedNow >= SPAWNS_PER_TICK or state == nil then
            survivors[#survivors + 1] = item
        else
            if spawnOne(item, state) then spawnedNow = spawnedNow + 1 end
        end
    end
    pendingSpawns = survivors
end

-- ---------------------------------------------------------------------------
-- Distances (pd3lib.game.weapons live breakpoints)
-- ---------------------------------------------------------------------------

local function refreshDistances(force)
    local now = os.clock()
    if not force and now - lastRangeRefresh < RANGE_REFRESH_SECONDS then return end
    lastRangeRefresh = now

    if config.distanceMode == "manual" then
        distances = config.distances
        distanceSource = "manual"
        return
    end

    local list = Weapons.BreakpointsMeters()
    if #list > 0 then
        distances = list
        distanceSource = "auto"
        return
    end

    distances = config.distances
    distanceSource = "fallback"
end

local function ensureDistance()
    refreshDistances()
    if #distances == 0 then distanceIndex = 1; currentDistance = nil; return nil end
    if distanceIndex > #distances then distanceIndex = #distances end
    if type(currentDistance) ~= "number" then
        currentDistance = distances[distanceIndex]
    end
    return currentDistance
end

local function selectionLine()
    local entry = Logic.ROSTER[enemyIndex]
    return string.format("enemy %d/%d %s | distance %.2f m (%d/%d, %s)",
        enemyIndex, #Logic.ROSTER, entry.name,
        currentDistance or -1, distanceIndex, #distances, distanceSource)
end

-- ---------------------------------------------------------------------------
-- Public actions
-- ---------------------------------------------------------------------------

local chatWarned = false
local function notifyChat(text)
    if not config.chatNotice then return end
    local ok, err = Chat.Send(text)
    if not ok and not chatWarned then
        chatWarned = true
        log("chat notice unavailable: %s", tostring(err))
    end
end

local function notifyEnemy()
    notifyChat(string.format("[TrainingSpawner] enemy %d/%d - <Object>%s</>",
        enemyIndex, #Logic.ROSTER, Logic.ROSTER[enemyIndex].name))
end

local function notifyDistance()
    notifyChat(string.format("[TrainingSpawner] distance <Blue>%.2f m (%d/%d, %s)</>",
        currentDistance or -1, distanceIndex, #distances, distanceSource))
end

local function cycleEnemy(delta)
    enemyIndex = Logic.CycleIndex(enemyIndex, #Logic.ROSTER, delta)
    log("%s", selectionLine())
    notifyEnemy()
end

local function cycleDistance(delta)
    refreshDistances(true)
    if #distances == 0 then log("no distances available"); return end
    distanceIndex = Logic.CycleIndex(distanceIndex, #distances, delta)
    currentDistance = distances[distanceIndex]
    log("%s", selectionLine())
    notifyDistance()
end

local function nudgeDistance(delta)
    refreshDistances()
    currentDistance = Logic.NudgeDistance(currentDistance or distances[distanceIndex] or 10, delta)
    distanceSource = "nudge"
    log("%s", selectionLine())
    notifyDistance()
end

local function spawnSelected()
    local entry = Logic.ROSTER[enemyIndex]
    local d = ensureDistance()
    if type(d) ~= "number" then log("spawn: no distance available"); return end
    if not beginSpawnContext() then log("spawn: no player pawn"); return end

    if testSubject then
        if Safe.IsValid(testSubject.actor) then
            tryE("destroy subject", function() return Spawn.Destroy(testSubject.actor) end)
        end
        testSubject = nil
    end

    classLoader:RetryFailed()
    pendingSpawns[#pendingSpawns + 1] = {
        path = entry.path,
        name = entry.name,
        slot = { dist = math.floor(d * 100 + 0.5), yawOffsetDeg = 0 },
        subject = true,
        noFreeze = not config.freeze,
    }
    enqueueUnresolved()
    log("queued %s at %.2f m (%s, %s)", entry.name, d, distanceSource, config.freeze and "frozen" or "unfrozen")
end

local function spawnRosterArc()
    if not beginSpawnContext() then log("roster: no player pawn"); return end

    pendingSpawns = {}
    classLoader:RetryFailed()
    local slots = Logic.BuildLayout(#Logic.ROSTER)
    for i, entry in ipairs(Logic.ROSTER) do
        pendingSpawns[#pendingSpawns + 1] = {
            path = entry.path,
            name = entry.name,
            slot = slots[i],
            noFreeze = not config.freeze,
        }
    end
    enqueueUnresolved()
    log("queued full roster (%d, %s)", #Logic.ROSTER, config.freeze and "frozen" or "unfrozen")
end

-- ---------------------------------------------------------------------------
-- Freeze (pd3lib.game.ai)
-- ---------------------------------------------------------------------------

local function ensureFrozen(entry)
    if entry.noFreeze then
        if not entry.unfrozenLogged then
            entry.unfrozenLogged = true
            log("unfrozen %s (config.freeze=false)", entry.name)
        end
        return
    end
    if not Safe.IsValid(entry.actor) then return end
    local ok, detail = AI.FreezePawn(entry.actor, Logic.REASON)
    if ok and not entry.frozenLogged then
        entry.frozenLogged = true
        log("frozen %s (%s)", entry.name, detail)
    end
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

local function pruneDead()
    -- spawned holds entry tables, not UObjects - validate entry.actor here rather than
    -- passing the list to World.PruneValid (which checks each element as a UObject).
    local survivors = {}
    local lost = 0
    for _, entry in ipairs(spawned) do
        if Safe.IsValid(entry.actor) then
            survivors[#survivors + 1] = entry
        else
            lost = lost + 1
            log("lost %s", entry.name)
        end
    end
    if lost > 0 then spawned = survivors end
    if testSubject and not Safe.IsValid(testSubject.actor) then testSubject = nil end
end

local tickCounter = 0
local function tick()
    tickCounter = tickCounter + 1
    classLoader:Step()
    drainSpawns()
    pruneDead()
    for _, entry in ipairs(spawned) do
        ensureFrozen(entry)
    end

    if tickCounter % 60 == 0 then
        log("status live=%d frozen=%d pending=%d | %s", #spawned, AI.FrozenCount(), #pendingSpawns, selectionLine())
    end

    if pendingDifficultyCheckAt and os.clock() >= pendingDifficultyCheckAt then
        pendingDifficultyCheckAt = nil
        log("F10 after: idx=%s", tostring(Mission.DifficultyIdx()))
    end
end

local function cycleDifficulty(delta)
    if type(difficultyIndex) ~= "number" then
        difficultyIndex = Mission.DifficultyIdx() or 0
        log("difficulty: initialized from live idx=%d", difficultyIndex)
    end
    difficultyIndex = (difficultyIndex + delta) % DIFFICULTY_COUNT
    local ok, err = Mission.SetDifficultyIdx(difficultyIndex)
    log("difficulty idx=%d (%s) set=%s", difficultyIndex, tostring(Mission.DifficultyName(difficultyIndex)),
        ok and "ok" or tostring(err))
    notifyChat(string.format("[TrainingSpawner] difficulty <Hud_01>%s</>",
        tostring(Mission.DifficultyName(difficultyIndex))))
    pendingDifficultyCheckAt = os.clock() + 1.0
end

local function bind(key, mods, fn)
    if mods then
        return pcall(RegisterKeyBind, key, mods, fn)
    end
    return pcall(RegisterKeyBind, key, fn)
end

local okF5 = bind(Key.F5, nil, function() ExecuteInGameThread(destroyAll) end)
local okF7 = bind(Key.F7, nil, function() ExecuteInGameThread(function() cycleEnemy(1) end) end)
local okShiftF7 = bind(Key.F7, { ModifierKey.SHIFT }, function() ExecuteInGameThread(function() cycleEnemy(-1) end) end)
local okF8 = bind(Key.F8, nil, function() ExecuteInGameThread(spawnSelected) end)
local okShiftF8 = bind(Key.F8, { ModifierKey.SHIFT }, function() ExecuteInGameThread(spawnRosterArc) end)
local okF9 = bind(Key.F9, nil, function() ExecuteInGameThread(function() cycleDistance(1) end) end)
local okShiftF9 = bind(Key.F9, { ModifierKey.SHIFT }, function() ExecuteInGameThread(function() cycleDistance(-1) end) end)
local okCtrlF9 = bind(Key.F9, { ModifierKey.CONTROL }, function() ExecuteInGameThread(function() nudgeDistance(1) end) end)
local okCtrlShiftF9 = bind(Key.F9, { ModifierKey.CONTROL, ModifierKey.SHIFT },
    function() ExecuteInGameThread(function() nudgeDistance(-1) end) end)
local okF10 = bind(Key.F10, nil, function() ExecuteInGameThread(function() cycleDifficulty(1) end) end)
local okShiftF10 = bind(Key.F10, { ModifierKey.SHIFT }, function() ExecuteInGameThread(function() cycleDifficulty(-1) end) end)

LoopAsync(1000, function() ExecuteInGameThread(tick) end)

log("loaded v0.5.5 (pd3lib v%d) - F5 clear=%s F7/ShiftF7 enemy=%s/%s F8 spawn=%s ShiftF8 arc=%s F9 dist=%s/%s CtrlF9 nudge=%s/%s F10 diff=%s/%s | mode=%s freeze=%s chatNotice=%s (IsValid global=%s)",
    pd3.Version,
    tostring(okF5), tostring(okF7), tostring(okShiftF7), tostring(okF8), tostring(okShiftF8),
    tostring(okF9), tostring(okShiftF9), tostring(okCtrlF9), tostring(okCtrlShiftF9),
    tostring(okF10), tostring(okShiftF10),
    config.distanceMode, tostring(config.freeze), tostring(config.chatNotice),
    tostring(type(IsValid) == "function"))
