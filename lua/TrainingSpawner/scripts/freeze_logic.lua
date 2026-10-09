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
    chatNotice = true,
    keepSubjects = false,
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
    if type(user.chatNotice) == "boolean" then cfg.chatNotice = user.chatNotice end
    if type(user.keepSubjects) == "boolean" then cfg.keepSubjects = user.keepSubjects end
    return cfg
end

-- ---------------------------------------------------------------------------
-- Keybind config (v0.6.0)
-- Action -> spec string ("Shift+F7"). An action missing from the user's `keys`
-- table is disabled. Pure parsing/merging only; the Key/ModifierKey enum
-- lookup happens at registration time in main.lua.
-- ---------------------------------------------------------------------------

M.KEY_ACTIONS = {
    "clear", "enemyNext", "enemyPrev",
    "spawnSelected", "spawnRosterArc",
    "distanceNext", "distancePrev", "distanceNudgeUp", "distanceNudgeDown",
    "difficultyNext", "difficultyPrev",
    "freezeToggle",
}

M.DEFAULT_KEYS = {
    clear = "F5",
    enemyNext = "F7",
    enemyPrev = "Shift+F7",
    spawnSelected = "F8",
    spawnRosterArc = "Shift+F8",
    distanceNext = "F9",
    distancePrev = "Shift+F9",
    distanceNudgeUp = "Ctrl+F9",
    distanceNudgeDown = "Ctrl+Shift+F9",
    difficultyNext = "F10",
    difficultyPrev = "Shift+F10",
    freezeToggle = "F6",
}

local MOD_ALIAS = { SHIFT = "SHIFT", CONTROL = "CONTROL", CTRL = "CONTROL", ALT = "ALT" }
local MOD_ORDER = { "SHIFT", "CONTROL", "ALT" }

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Splits on '+' while keeping empty segments ("+F5", "F5+").
local function splitPlus(spec)
    local parts = {}
    local start = 1
    while true do
        local pos = spec:find("+", start, true)
        if pos == nil then
            parts[#parts + 1] = spec:sub(start)
            return parts
        end
        parts[#parts + 1] = spec:sub(start, pos - 1)
        start = pos + 1
    end
end

--- Parses "Mod+...+Key" into `{ key = "F9", mods = { "SHIFT", "CONTROL" } }`.
--- Modifier names are case-insensitive (Ctrl = Control); mods come back in
--- canonical order. Returns nil plus a reason for malformed specs. Key enum
--- membership is deliberately not checked here - main.lua does that at
--- registration time against the UE4SS Key table.
---@param spec any
---@return table? parsed
---@return string? reason
function M.ParseKeySpec(spec)
    if type(spec) ~= "string" then return nil, "not a string" end

    local parts = splitPlus(spec)
    for i = 1, #parts do
        parts[i] = trim(parts[i])
        if parts[i] == "" then return nil, "empty segment" end
    end

    local keyPart = parts[#parts]
    if keyPart:find("[^%w_]", 1) then return nil, "invalid key name: " .. keyPart end

    local seen = {}
    for i = 1, #parts - 1 do
        local modName = MOD_ALIAS[parts[i]:upper()]
        if modName == nil then return nil, "unknown modifier: " .. parts[i] end
        if seen[modName] then return nil, "duplicate modifier: " .. parts[i] end
        seen[modName] = true
    end

    local mods = {}
    for _, name in ipairs(MOD_ORDER) do
        if seen[name] then mods[#mods + 1] = name end
    end
    return { key = keyPart:upper(), mods = mods }
end

local function addDefaults(result)
    for _, action in ipairs(M.KEY_ACTIONS) do
        local spec = M.DEFAULT_KEYS[action]
        local parsed, reason = M.ParseKeySpec(spec)
        if parsed then
            result.bindings[#result.bindings + 1] = {
                action = action,
                spec = spec,
                key = parsed.key,
                mods = parsed.mods,
            }
        else
            result.disabled[#result.disabled + 1] = action
            result.warnings[#result.warnings + 1] = string.format(
                "default key invalid for %s (%s): %s", action, tostring(reason), tostring(spec))
        end
    end
end

--- Resolves the user's `keys` table.
---   * nil   -> built-in defaults (backward compatible with configs predating `keys`)
---   * false -> every action disabled
---   * table -> only the listed actions are enabled; nil/false entries are
---              disabled, invalid specs are disabled and reported as warnings
---@param user any
---@return table # { bindings = { { action, spec, key, mods } ... }, disabled = { action ... }, warnings = { string ... }, allDisabled = true when keys = false }
function M.MergeKeys(user)
    local result = { bindings = {}, disabled = {}, warnings = {} }

    if user == nil then
        addDefaults(result)
        return result
    end
    if user == false then
        result.allDisabled = true
        for _, action in ipairs(M.KEY_ACTIONS) do result.disabled[#result.disabled + 1] = action end
        return result
    end
    if type(user) ~= "table" then
        result.warnings[#result.warnings + 1] = "keys must be a table or false; using defaults"
        addDefaults(result)
        return result
    end

    local known = {}
    for _, action in ipairs(M.KEY_ACTIONS) do known[action] = true end
    for name in pairs(user) do
        if not known[name] then
            result.warnings[#result.warnings + 1] = "unknown action in keys: " .. tostring(name)
        end
    end

    for _, action in ipairs(M.KEY_ACTIONS) do
        local spec = user[action]
        if spec == nil or spec == false then
            result.disabled[#result.disabled + 1] = action
        elseif type(spec) == "string" then
            local parsed, reason = M.ParseKeySpec(spec)
            if parsed then
                result.bindings[#result.bindings + 1] = {
                    action = action,
                    spec = spec,
                    key = parsed.key,
                    mods = parsed.mods,
                }
            else
                result.disabled[#result.disabled + 1] = action
                result.warnings[#result.warnings + 1] = string.format(
                    "keys.%s invalid (%s): %s", action, tostring(reason), spec)
            end
        else
            result.disabled[#result.disabled + 1] = action
            result.warnings[#result.warnings + 1] = string.format("keys.%s ignored (not a string)", action)
        end
    end
    return result
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
