# ModWorkshop page copy — TrainingSpawner

Paste-ready text for the ModWorkshop submission (category: Misc, tags: UE4SS, Lua,
Gameplay Changing, Training).

## Title

Training Spawner — Shooting Range test rig (frozen enemies)

## Short description

Spawn any enemy in the Shooting Range, frozen, at your weapon's real falloff distances — built for
damage, armor and shots-to-kill testing.

## Description

**Turn the Shooting Range into a controlled enemy test rig.**

TrainingSpawner spawns enemies exactly where and when you want them: choose an enemy type, choose a
distance, press one key. The spawned enemy appears in front of you, facing you, with its AI
disabled — no moving, no shooting — so shots-to-kill, armor breakpoints and penetration results are
clean.

The distance list is not a guess. By default it is read live from your equipped weapon's damage
falloff arrays — the same breakpoints the community weapon bench displays as range rows (damage
and crit-multiplier distances). If your perks or attachments shift those breakpoints, set a manual
list in the config file.

### Key bindings

| Key | Action |
| --- | --- |
| `F5` | Clear all spawned subjects |
| `F7` / `Shift+F7` | Next / previous enemy type |
| `F8` | Spawn the selected enemy at the selected distance (replaces the previous one) |
| `Shift+F8` | Spawn the full roster in an arc |
| `F9` / `Shift+F9` | Next / previous distance |
| `Ctrl+F9` / `Ctrl+Shift+F9` | Fine nudge the distance by +1 m / -1 m |
| `F10` / `Shift+F10` | Next / previous difficulty |

Every action writes a line to the UE4SS log, for example:
`enemy 4/15 Taser | distance 12.50 m (3/7, auto)`.

### Enemy roster

SWAT rifle, SMG and shotgun, their heavy variants, Shield, Sniper, Taser, Grenadier, Dozer,
Cloaker, Tower, Armed Cop and Base Cop — 15 types.

### Difficulty

Cycle between Normal, Hard, Very Hard and Overkill at any time. Difficulty scaling is applied to
enemies spawned after the change (spawn a fresh subject after switching for accurate numbers).

### Configuration

Edit `scripts\user_config.lua` in the mod folder:

```lua
return {
    distanceMode = "auto",   -- "auto" = equipped weapon breakpoints, "manual" = use the list below
    distances = { 2.5, 5, 10, 15, 25, 50 },  -- meters; manual mode and fallback
    freeze = true,           -- false = live-AI test subjects
    autoSpawn = false,       -- reserved; the mod never auto-spawns
}
```

### Install

1. Download `TrainingSpawner-0.5.3.zip`.
2. Open the zip.
3. Drag the `TrainingSpawner` folder into:

   `...\PAYDAY3\PAYDAY3\Binaries\Win64\ue4ss\Mods\`

   Xbox App for PC: `...\Payday 3\Content\PAYDAY3\Binaries\WinGDK\ue4ss\Mods\`
4. Start the game and enter the Shooting Range.

The mod enables itself (`enabled.txt`). If it does not load, open `...\Mods\mods.txt`, add
`TrainingSpawner : 1` above the keybinds, and restart the game.

### Requirements

PAYDAY 3 + [PD3 UE4SS V3.01 + Allow Pak Mods](https://modworkshop.net/mod/47771). No other mods or
libraries are needed — the pd3lib helper is bundled inside the download.

### Compatibility

- **KillStatsMod:** disable it while killing spawned enemies. Native damage/kill hooks (which
  KillStatsMod uses) crash the game on directly spawned pawns, because those pawns are not
  registered by the game's own spawn pipeline. The same caveat applies to any mod hooking
  `SBZCharacter:HandleTakePointDamage`, `Multicast_OnKill` or the damage-feed events.
- WeaponStatsViewer and other read-only mods are unaffected.
- Spawning works anywhere; the Shooting Range is simply the safest place to test.

### Notes

- The mod is client-side and local-only; it does not touch other players or game progression.
- Sources and issue tracker: <https://github.com/met94/TrainingGroundsMod>

### Changelog

- 0.5.3 — enemy cycler consolidated to `F7` (next) and `Shift+F7` (previous), matching the
  next/Shift pattern already used for distance and difficulty; `F6` is no longer bound.
- 0.5.2 — engine layer moved to the bundled pd3lib (spawning, AI freeze, live weapon breakpoints,
  class loading); behavior unchanged.
- 0.5.1 — difficulty cycling with Normal/Hard/Very Hard/Overkill keys.
- 0.5.0 — test-rig redesign: no auto-spawn, enemy cycler, live weapon-breakpoint distances,
  fine distance nudge, subject replacement, face-the-player orientation.
- 0.4.x — robustness pass (validated object reads, dead-subject pruning, status lines).
- 0.3.x — full-roster arc, freeze hardening, single-class cycler.
- 0.2.x — direct actor spawning, AI freeze, 15-class roster.
