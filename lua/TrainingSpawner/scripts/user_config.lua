-- User-editable TrainingSpawner configuration.
--
-- distanceMode:
--   "auto"   - read the equipped weapon's falloff breakpoints live. These are the
--              same numbers the PAYDAY 3 weapon bench shows as `range` rows
--              (damage + crit-multiplier breakpoints, converted cm -> m).
--   "manual" - use `distances` exactly as written.
--
-- distances:
--   Meters. Used in manual mode and as the fallback when the live read fails
--   (e.g. custody, melee equipped). Perks/attachments that move the breakpoints
--   are not always visible to the live read - correct them here by hand.
--
-- freeze:     true = spawned enemies have AI disabled (SetAIEnabled false).
--             The freezeToggle key (default F11) flips this at runtime; the
--             change applies to enemies spawned afterwards, not existing ones.
-- autoSpawn:  reserved; v1 never auto-spawns on level entry.
-- chatNotice: true = enemy/distance/difficulty changes are printed to the in-game chat.
-- keepSubjects: true = F8 adds another subject at the selected distance (same yaw line)
--               instead of destroying the previous one; use F5 to clear them all.
--
-- keys: action -> key spec ("Key" or "Mod+Key", e.g. "Shift+F7"; Ctrl = Control,
--       key names are the UE4SS Key enum names: F1..F24, NUM_ONE, SPACE, A..Z,
--       LEFT_MOUSE_BUTTON, ...). An action NOT listed here is disabled - remove
--       a line to unbind it. Remove the whole `keys` table to fall back to these
--       built-in defaults; set `keys = false` to disable every binding.
--       Two actions may share the same key combo; both run when it is pressed.
return {
    distanceMode = "auto",
    distances = { 2.5, 5, 10, 15, 25, 50 },
    freeze = true,
    autoSpawn = false,
    chatNotice = true,
    keepSubjects = false,
    keys = {
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
        freezeToggle = "F11",
    },
}
