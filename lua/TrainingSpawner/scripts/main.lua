-- TrainingSpawner v0.6.0: test-rig spawner for the Shooting Range (NewShootingRange).
-- No auto-spawn. F8 spawns the selected enemy at the selected distance, facing you.
-- Engine work goes through the vendored pd3lib (classes loader, spawn, ai, weapons, mission).
-- Default keys (all rebindable / disablable via the `keys` table in user_config.lua):
--   F5            clear all spawned subjects
--   F7 / Shift+F7 next / previous enemy (roster of 15)
--   F8            spawn selected enemy (replaces the previous F8 subject)
--   Shift+F8      spawn the full-roster arc (legacy mode)
--   F9 / Shift+F9 next / previous distance breakpoint
--   Ctrl+F9       +1 m fine nudge (Ctrl+Shift+F9 = -1 m)
--   F10 / Shift+F10  next / previous difficulty (Normal..Overkill)
--   F11           toggle the freeze config option for next spawns
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
local userKeys = nil
if OkConfig and type(UserConfig) == "table" then userKeys = UserConfig.keys end
local resolvedKeys = Logic.MergeKeys(userKeys)

local Safe = pd3.safe
local Classes = pd3.classes
local Spawn = pd3.spawn
local AI = pd3.ai
local Weapons = pd3.weapons
local Mission = pd3.mission
local World = pd3.world
local Chat = pd3.chat
local Lifecycle = pd3.lifecycle

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
    if not Safe.IsValid(pc) then return false, "no player controller" end
    local pawn = Safe.Get(pc, "Pawn")
    if not Safe.IsValid(pawn) then return false, "no player pawn" end

    local pawnLoc = tryE("pawn location", function() return pawn:K2_GetActorLocation() end)
    local controlRot = tryE("control rotation", function() return pc:GetControlRotation() end)
    if not controlRot then controlRot = tryE("pawn rotation", function() return pawn:K2_GetActorRotation() end) end
    if not pawnLoc or not controlRot then return false, "no player transform" end

    spawnContext = {
        x = tonumber(field(pawnLoc, "X")) or 0,
        y = tonumber(field(pawnLoc, "Y")) or 0,
        z = tonumber(field(pawnLoc, "Z")) or 0,
        yawBase = tonumber(field(controlRot, "Yaw")) or 0,
    }
    return true
end

local function spawnOne(item, cls)
    if not Safe.IsValid(cls) then
        log("spawn drop %s: class invalid (stale after level change?)", item.name)
        return false
    end
    if not item.slot then
        log("spawn drop %s: no slot", item.name)
        return false
    end
    if not spawnContext then
        log("spawn drop %s: no spawn context", item.name)
        return false
    end

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
            log("spawn drop %s: class gave up", item.name)
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

local lastChatError = nil
local function notifyChat(text)
    if not config.chatNotice then return end
    local ok, err = Chat.Send(text)
    if ok then
        lastChatError = nil
        return
    end
    err = tostring(err)
    if err ~= lastChatError then
        lastChatError = err
        log("chat notice unavailable: %s", err)
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

local function toggleFreeze()
    config.freeze = not config.freeze
    log("freeze %s - next spawns %s", config.freeze and "ON" or "OFF",
        config.freeze and "frozen" or "use live AI")
    notifyChat(string.format("[TrainingSpawner] freeze <Object>%s</> - next spawns %s",
        config.freeze and "ON" or "OFF", config.freeze and "frozen" or "use live AI"))
end

-- ---------------------------------------------------------------------------
-- Level lifecycle: drop every per-level transient (pd3lib caches + mod state)
-- ---------------------------------------------------------------------------

-- Pure Lua only: lifecycle callbacks run in engine-hook context, where UFunction
-- calls are unsafe (see pd3lib game.heist). Engine reads re-happen on the next tick.
local function resetLevelState(reason)
    classLoader:Reset()
    pendingSpawns = {}
    spawnContext = nil
    spawned = {}
    testSubject = nil
    AI.Reset()
    World.Reset()
    Chat.Reset()
    lastChatError = nil
    lastRangeRefresh = -RANGE_REFRESH_SECONDS
    log("level reset: %s", tostring(reason))
end

Lifecycle.OnLevelInit(function(levelName) resetLevelState(levelName or "level init") end)
Lifecycle.OnLevelRestart(function() resetLevelState("restart") end)
Lifecycle.OnReturnToMenu(function() resetLevelState("menu") end)

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
    local ctxOk, ctxErr = beginSpawnContext()
    if not ctxOk then
        log("spawn: %s (controllers=%d)", tostring(ctxErr), #World.FindAll("PlayerController"))
        return
    end

    if testSubject and not config.keepSubjects then
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
    log("queued %s at %.2f m (%s, %s, %s)", entry.name, d, distanceSource,
        config.freeze and "frozen" or "unfrozen", config.keepSubjects and "keep" or "replace")
end

local function spawnRosterArc()
    local ctxOk, ctxErr = beginSpawnContext()
    if not ctxOk then
        log("roster: %s (controllers=%d)", tostring(ctxErr), #World.FindAll("PlayerController"))
        return
    end

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
        log("status live=%d frozen=%d pending=%d loads=%d | %s",
            #spawned, AI.FrozenCount(), #pendingSpawns, classLoader:Pending(), selectionLine())
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

-- Action -> game-thread function. Registration follows the resolved `keys`
-- config (freeze_logic.MergeKeys); an action missing from user_config.lua is
-- not registered at all.
local handlers = {
    clear = destroyAll,
    enemyNext = function() cycleEnemy(1) end,
    enemyPrev = function() cycleEnemy(-1) end,
    spawnSelected = spawnSelected,
    spawnRosterArc = spawnRosterArc,
    distanceNext = function() cycleDistance(1) end,
    distancePrev = function() cycleDistance(-1) end,
    distanceNudgeUp = function() nudgeDistance(1) end,
    distanceNudgeDown = function() nudgeDistance(-1) end,
    difficultyNext = function() cycleDifficulty(1) end,
    difficultyPrev = function() cycleDifficulty(-1) end,
    freezeToggle = toggleFreeze,
}

-- Maps a parsed { key = "F9", mods = { "SHIFT", ... } } to UE4SS constants;
-- unknown names disable the binding instead of crashing the mod load.
local function resolveBinding(entry)
    local keyCode = Key[entry.key]
    if keyCode == nil then return nil, nil, "unknown key: " .. entry.key end
    local mods = {}
    for _, name in ipairs(entry.mods) do
        local code = ModifierKey[name]
        if code == nil then return nil, nil, "unknown modifier: " .. name end
        mods[#mods + 1] = code
    end
    return keyCode, mods
end

local registeredCount = 0
for _, entry in ipairs(resolvedKeys.bindings) do
    local handler = handlers[entry.action]
    local keyCode, mods, reason = resolveBinding(entry)
    if handler == nil then
        log("keybind %s: no handler (internal)", entry.action)
    elseif keyCode == nil then
        log("keybind %s: disabled (%s, spec %s)", entry.action, reason, entry.spec)
    else
        local okBind, bindErr = bind(keyCode, #mods > 0 and mods or nil,
            function() ExecuteInGameThread(handler) end)
        if okBind then
            registeredCount = registeredCount + 1
            log("keybind %s: %s registered", entry.action, entry.spec)
        else
            log("keybind %s: FAILED - %s (spec %s)", entry.action, tostring(bindErr), entry.spec)
        end
    end
end
for _, action in ipairs(resolvedKeys.disabled) do
    log("keybind %s: disabled (not in keys config)", action)
end
for _, warning in ipairs(resolvedKeys.warnings) do
    log("keys config: %s", warning)
end

LoopAsync(1000, function() ExecuteInGameThread(tick) end)

log("loaded v0.6.0 (pd3lib v%d) - bindings %d/%d active | mode=%s freeze=%s keepSubjects=%s chatNotice=%s (IsValid global=%s)",
    pd3.Version, registeredCount, #Logic.KEY_ACTIONS,
    config.distanceMode, tostring(config.freeze), tostring(config.keepSubjects), tostring(config.chatNotice),
    tostring(type(IsValid) == "function"))
