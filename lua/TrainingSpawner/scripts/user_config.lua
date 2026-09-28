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
-- autoSpawn:  reserved; v1 never auto-spawns on level entry.
-- chatNotice: true = enemy/distance/difficulty changes are printed to the in-game chat.
return {
    distanceMode = "auto",
    distances = { 2.5, 5, 10, 15, 25, 50 },
    freeze = true,
    autoSpawn = false,
    chatNotice = true,
}
