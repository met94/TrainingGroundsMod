-- Pure logic for TrainingSpawner. No engine calls; unit-tested with fengari.
-- Engine-facing helpers live in the vendored pd3lib (spawn/ai/weapons/mission).
local M = {}

M.REASON = "TrainingSpawner"
M.HANDLE_MARKER = "NewShootingRange"

M.ROSTER = {
    { name = "Rifleman",  path = "/Game/Gameplay/Characters/Cop/CH_SWAT_AR.CH_SWAT_AR_C" },
    { name = "SMG",       path = "/Game/Gameplay/Characters/Cop/CH_SWAT_SMG.CH_SWAT_SMG_C" },
    { name = "Shotgun",   path = "/Game/Gameplay/Characters/Cop/CH_SWAT_Shotgun.CH_SWAT_Shotgun_C" },
    { name = "RiflemanH", path = "/Game/Gameplay/Characters/Cop/CH_SWAT_AR_HEAVY.CH_SWAT_AR_HEAVY_C" },
    { name = "SMGH",      path = "/Game/Gameplay/Characters/Cop/CH_SWAT_SMG_HEAVY.CH_SWAT_SMG_HEAVY_C" },
    { name = "ShotgunH",  path = "/Game/Gameplay/Characters/Cop/CH_SWAT_Shotgun_HEAVY.CH_SWAT_Shotgun_HEAVY_C" },
    { name = "Shield",    path = "/Game/Gameplay/Characters/Cop/CH_SWAT_SHIELD.CH_SWAT_SHIELD_C" },
    { name = "Sniper",    path = "/Game/Gameplay/Characters/Cop/CH_Sniper.CH_Sniper_C" },
    { name = "Taser",     path = "/Game/Gameplay/Characters/Cop/CH_Taser.CH_Taser_C" },
    { name = "Grenadier", path = "/Game/Gameplay/Characters/Cop/CH_Grenadier.CH_Grenadier_C" },
    { name = "Dozer",     path = "/Game/Gameplay/Characters/Cop/CH_Dozer.CH_Dozer_C" },
    { name = "Cloaker",   path = "/Game/Gameplay/Characters/Cop/CH_Cloaker.CH_Cloaker_C" },
    { name = "Tower",     path = "/Game/DLCs/00005-DLCHEIST0001/Gameplay/Characters/Cop/CH_Tower.CH_Tower_C" },
    -- Moon (BP_Moon_Gun_C drone) removed: standalone spawn crashed the game (2026-09-27 round 6).
    { name = "ArmedCop",  path = "/Game/Gameplay/Characters/Cop/CH_ArmedCop.CH_ArmedCop_C" },
    { name = "BaseCop",   path = "/Game/Gameplay/Characters/Cop/CH_BaseCop.CH_BaseCop_C" },
    -- Guard (CH_SecurityGuard_C) removed: not loadable in the range (8 full load attempts failed,
    -- 2026-09-27 round 7); non-assault NPC.
}

M.FRONT_DIST = 800
M.BACK_DIST = 1200
M.SPREAD_DEG = 140

function M.ShouldHandle(worldName)
    if type(worldName) ~= "string" then return false end
    return worldName:find(M.HANDLE_MARKER, 1, true) ~= nil
end

-- Two-row arc in front of the player. Front row gets the extra slot.
-- Returns { { dist = cm, yawOffsetDeg = deg }, ... } ordered front left->right, then back left->right.
function M.BuildLayout(count, frontDist, backDist, spreadDeg)
    count = count or #M.ROSTER
    frontDist = frontDist or M.FRONT_DIST
    backDist = backDist or M.BACK_DIST
    spreadDeg = spreadDeg or M.SPREAD_DEG

    local front = math.ceil(count / 2)
    local back = count - front
    local slots = {}

    local function row(n, dist)
        for i = 1, n do
            local t = (n == 1) and 0.5 or (i - 1) / (n - 1)
            slots[#slots + 1] = {
                dist = dist,
                yawOffsetDeg = (t - 0.5) * spreadDeg,
                row = (dist == frontDist) and "front" or "back",
            }
        end
    end

    row(front, frontDist)
    row(back, backDist)
    return slots
end

M.DEFAULTS = {
    distanceMode = "auto",
    distances = { 2.5, 5, 10, 15, 25, 50 },
    freeze = true,
    autoSpawn = false,
}

--- Merges a user config over the defaults; invalid values are ignored.
function M.MergeConfig(user)
    local cfg = {}
    for k, v in pairs(M.DEFAULTS) do cfg[k] = v end
    if type(user) ~= "table" then return cfg end

    if user.distanceMode == "manual" or user.distanceMode == "auto" then
        cfg.distanceMode = user.distanceMode
    end
    if type(user.distances) == "table" and #user.distances > 0 then
        local out, ok = {}, true
        for _, d in ipairs(user.distances) do
            if type(d) == "number" and d > 0 then
                out[#out + 1] = d
            else
                ok = false
            end
        end
        if ok and #out > 0 then cfg.distances = out end
    end
    if type(user.freeze) == "boolean" then cfg.freeze = user.freeze end
    if type(user.autoSpawn) == "boolean" then cfg.autoSpawn = user.autoSpawn end
    return cfg
end

--- Modulo index cycler (1-based, handles negative deltas).
function M.CycleIndex(index, count, delta)
    if type(count) ~= "number" or count < 1 then return 1 end
    index = type(index) == "number" and index or 1
    return (index - 1 + delta) % count + 1
end

--- Fine distance correction with clamps (meters, 2 decimals).
function M.NudgeDistance(current, delta, min, max)
    min = min or 1
    max = max or 500
    local d = (type(current) == "number" and current or min) + delta
    if d < min then d = min end
    if d > max then d = max end
    return math.floor(d * 100 + 0.5) / 100
end

return M
