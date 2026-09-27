-- TrainingProbe: recon + spawn smoke tests for the training-area (NewShootingRange) mod.
-- F6 dump | F7 assault kickstart | F8 direct SpawnActor (Dozer) | F9 destroy test spawns | F10 cheat-manager spawn
local MOD = "TrainingProbe"
local spawned = {}

local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print(string.format("[%s] %s\n", MOD, ok and s or tostring(fmt)))
end

local function try(fn, fallback)
    local ok, res = pcall(fn)
    if ok then return res end
    return fallback
end

local function tryE(label, fn)
    local ok, res = pcall(fn)
    if not ok then
        log("%s ERROR: %s", label, tostring(res))
        return nil
    end
    return res
end

local function classObj(path)
    local c = try(function() return StaticFindObject(path) end, nil)
    if c and try(function() return c:IsValid() end, false) then return c end
    return nil
end

local function class_of(obj)
    return try(function() return obj:GetClass():GetFName():ToString() end, "?")
end

local function firstOf(cls)
    local o = try(function() return FindFirstOf(cls) end, nil)
    if o and try(function() return o:IsValid() end, false) then return o end
    return nil
end

local function valid(o)
    return o ~= nil and try(function() return o:IsValid() end, false)
end

local function pawnCounts()
    local pawns = try(function() return FindAllOf("SBZAICharacter") end, nil) or {}
    local counts = {}
    for _, p in ipairs(pawns) do
        local c = class_of(p)
        counts[c] = (counts[c] or 0) + 1
    end
    return counts, #pawns
end

local function dump()
    log("=== dump start ===")

    local managers = try(function() return FindAllOf("PD3AssaultManager") end, nil) or {}
    log("assault managers=%d", #managers)
    for i, m in ipairs(managers) do
        log("manager[%d] %s", i, try(function() return m:GetFullName() end, "?"))
        local s = try(function() return m.Settings end, nil)
        if valid(s) then
            log("  Settings=%s", try(function() return s:GetFullName() end, "?"))
            log("  Settings.MaxTotalAISpawnCount=%s", tostring(try(function() return s.MaxTotalAISpawnCount end, "?")))
        end
        log("  IsAssaultActive=%s", tostring(try(function() return m:IsAssaultActive() end, "?")))
    end

    local counts, total = pawnCounts()
    log("SBZAICharacter count=%d", total)
    for c, n in pairs(counts) do
        log("  pawn %s x%d", c, n)
    end

    local ms = firstOf("SBZMissionState")
    if ms then
        log("missionState=%s", try(function() return ms:GetFullName() end, "?"))
        log("  GetDifficulty=%s", tostring(try(function() return ms:GetDifficulty() end, "?")))
        log("  GetDifficultyIdx=%s", tostring(try(function() return ms:GetDifficultyIdx() end, "?")))
    end

    log("test spawned actors=%d", #spawned)
    log("=== dump end ===")
end

local function kickstart()
    log("=== kickstart start ===")
    local managers = try(function() return FindAllOf("PD3AssaultManager") end, nil) or {}
    for i, m in ipairs(managers) do
        log("manager[%d] SetLevelProgression(1.0)=%s", i,
            tostring(try(function() return m:SetLevelProgression(1.0) end, "?")))
        log("manager[%d] SetAssaultActive(true)=%s", i,
            tostring(try(function() return m:SetAssaultActive(true) end, "?")))
        log("manager[%d] StartEndlessAssault(true)=%s", i,
            tostring(try(function() return m:StartEndlessAssault(true) end, "?")))
        log("manager[%d] IsAssaultActive=%s", i,
            tostring(try(function() return m:IsAssaultActive() end, "?")))
    end
    log("=== kickstart end ===")
end

local function loadClass(path)
    local c = try(function() return LoadAsset(path) end, nil)
    if valid(c) then return c end
    c = try(function() return StaticFindObject(path) end, nil)
    if valid(c) then return c end
    return nil
end

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function rot(p, y, r) return { Pitch = p, Yaw = y, Roll = r } end

local function forwardFromRotator(r)
    local yaw = math.rad(tonumber(try(function() return r.Yaw end, 0)) or 0)
    local pitch = math.rad(tonumber(try(function() return r.Pitch end, 0)) or 0)
    return vec(math.cos(yaw) * math.cos(pitch), math.sin(yaw) * math.cos(pitch), math.sin(pitch))
end

local function spawnOne(classPath, distance)
    log("=== spawnOne start: %s ===", classPath)
    local world = firstOf("World")
    local pc = firstOf("PlayerController")
    if not world or not pc then
        log("spawnOne FAIL: world=%s pc=%s", tostring(valid(world)), tostring(valid(pc)))
        return
    end
    local pawn = try(function() return pc.Pawn end, nil)
    if not valid(pawn) then
        log("spawnOne FAIL: no player pawn")
        return
    end

    local cls = loadClass(classPath)
    if not cls then
        log("spawnOne FAIL: class not loadable")
        return
    end
    log("class ok: %s", try(function() return cls:GetFullName() end, "?"))

    local pawnLoc = try(function() return pawn:K2_GetActorLocation() end, nil)
    local controlRot = try(function() return pc:GetControlRotation() end, nil)
    if not controlRot then controlRot = try(function() return pawn:K2_GetActorRotation() end, nil) end
    log("pawnLoc=%s", try(function() return string.format("%.0f %.0f %.0f", pawnLoc.X, pawnLoc.Y, pawnLoc.Z) end, "?"))
    log("rot=%s", try(function() return string.format("%.1f %.1f %.1f", controlRot.Pitch, controlRot.Yaw, controlRot.Roll) end, "?"))

    local kismet = classObj("/Script/Engine.KismetMathLibrary")
    local gs = classObj("/Script/Engine.GameplayStatics")
    log("kismet=%s gs=%s", tostring(valid(kismet)), tostring(valid(gs)))
    if not kismet or not gs then return end

    local fwd = forwardFromRotator(controlRot)
    local dist = distance or 1000
    local lx = (tonumber(pawnLoc.X) or 0) + fwd.X * dist
    local ly = (tonumber(pawnLoc.Y) or 0) + fwd.Y * dist
    local lz = (tonumber(pawnLoc.Z) or 0) + fwd.Z * dist
    local yaw = tonumber(try(function() return controlRot.Yaw end, 0)) or 0

    local locV = tryE("MakeVector(loc)", function() return kismet:MakeVector(lx, ly, lz) end)
    local rotV = tryE("MakeRotator(rot)", function() return kismet:MakeRotator(0.0, 0.0, yaw) end)
    local scaleV = tryE("MakeVector(scale)", function() return kismet:MakeVector(1.0, 1.0, 1.0) end)
    if not locV or not rotV or not scaleV then
        log("spawnOne FAIL: struct construction")
        return
    end

    local transform = tryE("MakeTransform", function() return kismet:MakeTransform(locV, rotV, scaleV) end)
    if not transform then
        log("spawnOne FAIL: MakeTransform")
        return
    end

    local actor = tryE("BeginDeferredActorSpawnFromClass", function()
        return gs:BeginDeferredActorSpawnFromClass(world, cls, transform, 0, nil, 1)
    end)
    if not valid(actor) then
        log("spawnOne FAIL: BeginDeferredActorSpawnFromClass -> %s", tostring(actor))
        return
    end
    log("deferred actor: %s", try(function() return actor:GetFullName() end, "?"))
    local okFinish = tryE("FinishSpawningActor", function()
        return gs:FinishSpawningActor(actor, transform, 1)
    end)
    log("finished: %s", tostring(okFinish))
    table.insert(spawned, actor)
    log("spawnOne END: %s", try(function() return actor:GetFullName() end, "?"))
end

local function cheatSpawn()
    log("=== cheatSpawn start ===")
    local pc = firstOf("PlayerController")
    local gi = firstOf("GameInstance")
    if not pc or not gi then
        log("cheatSpawn FAIL: pc=%s gi=%s", tostring(valid(pc)), tostring(valid(gi)))
        return
    end

    local cheat = try(function() return pc.CheatManager end, nil)
    if not valid(cheat) then
        local cheatClass = try(function() return StaticFindObject("/Script/Starbreeze.SBZCheatManager") end, nil)
        log("cheat class=%s", tostring(try(function() return cheatClass:GetFullName() end, "?")))
        cheat = try(function()
            return StaticConstructObject(cheatClass, gi, 0, 0, 0x0E000000, false, false, nil, nil, nil)
        end, nil)
        if valid(cheat) then
            tryE("pc.CheatManager = cheat", function() pc.CheatManager = cheat end)
        end
    end
    log("cheat=%s", tostring(try(function() return cheat:GetFullName() end, "?")))
    log("pc.CheatManager=%s", tostring(try(function() return pc.CheatManager:GetFullName() end, "?")))
    if not valid(cheat) then return end

    local panel = try(function() return cheat.NPCDebugPanel end, nil)
    if not valid(panel) then
        local panelClass = try(function() return StaticFindObject("/Script/Starbreeze.SBZNPCDebugPanel") end, nil)
        log("panel class=%s", tostring(try(function() return panelClass:GetFullName() end, "?")))
        panel = try(function()
            return StaticConstructObject(panelClass, gi, 0, 0, 0x0E000000, false, false, nil, nil, nil)
        end, nil)
        if valid(panel) then
            tryE("cheat.NPCDebugPanel = panel", function() cheat.NPCDebugPanel = panel end)
        end
    end
    log("panel=%s", tostring(try(function() return panel:GetFullName() end, "?")))
    log("cheat.NPCDebugPanel=%s", tostring(try(function() return cheat.NPCDebugPanel:GetFullName() end, "?")))

    log("SpawnAllAITypes(5, 900, 0, 0, 0, None)=%s", tostring(try(function()
        return cheat:SpawnAllAITypes(5, 900.0, 0.0, 0.0, 0, FName("None"))
    end, "?")))
    log("=== cheatSpawn end ===")
end

local function cleanup()
    log("=== cleanup: %d actors ===", #spawned)
    for i, a in ipairs(spawned) do
        log("destroy[%d] %s -> %s", i, try(function() return a:GetFullName() end, "?"),
            tostring(try(function() return a:K2_DestroyActor() end, "?")))
    end
    spawned = {}
end

local ok6 = pcall(RegisterKeyBind, Key.F6, function() ExecuteInGameThread(dump) end)
local ok7 = pcall(RegisterKeyBind, Key.F7, function() ExecuteInGameThread(kickstart) end)
local ok8 = pcall(RegisterKeyBind, Key.F8, function()
    ExecuteInGameThread(function() spawnOne("/Game/Gameplay/Characters/Cop/CH_Dozer.CH_Dozer_C", 1000) end)
end)
local ok9 = pcall(RegisterKeyBind, Key.F9, function() ExecuteInGameThread(cleanup) end)
local ok10 = pcall(RegisterKeyBind, Key.F10, function() ExecuteInGameThread(cheatSpawn) end)

log("loaded - F6 dump %s, F7 kickstart %s, F8 spawnDozer %s, F9 cleanup %s, F10 cheat %s",
    ok6 and "ok" or "FAIL", ok7 and "ok" or "FAIL", ok8 and "ok" or "FAIL", ok9 and "ok" or "FAIL", ok10 and "ok" or "FAIL")
