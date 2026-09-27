# TrainingSpawner

A PAYDAY 3 UE4SS mod that turns the Shooting Range into a controlled enemy test rig: spawn any
enemy type, frozen, facing you, at your weapon's real damage-falloff distances — so you can count
shots to kill, test armor and penetration, and check how perks and attachments move the breakpoints.

## Requirements

- PAYDAY 3.
- [PD3 UE4SS V3.01 + Allow Pak Mods](https://modworkshop.net/mod/47771) installed.
- Nothing else — the [`pd3lib`](https://github.com/met94/pd3lib) helper library is bundled inside
  the mod download.

## Install (players)

1. Download `TrainingSpawner-<version>.zip` (ModWorkshop) or build it with `release.ps1`.
2. Open the zip.
3. Drag the `TrainingSpawner` folder into:

   `...\PAYDAY3\PAYDAY3\Binaries\Win64\ue4ss\Mods\`

   Xbox App for PC: `...\Payday 3\Content\PAYDAY3\Binaries\WinGDK\ue4ss\Mods\`
4. Start the game and enter the Shooting Range.

The mod enables itself (`enabled.txt`). If it does not load, open `...\Mods\mods.txt`, add
`TrainingSpawner : 1` above the keybinds, and restart the game.

## What it does

- **No automatic spawning.** You choose what to spawn and when.
- **Enemy cycler** over 15 enemy types: SWAT rifle/SMG/shotgun, their heavy variants, Shield,
  Sniper, Taser, Grenadier, Dozer, Cloaker, Tower, Armed Cop and Base Cop.
- **Distance selection at your weapon's real breakpoints.** By default the distance list is read
  live from the equipped weapon's falloff arrays — the same numbers the community weapon bench
  shows as range rows (damage and crit-multiplier breakpoints, converted to meters). Switch to a
  manual list in the config when perks or attachments move the breakpoints for you.
- **Frozen by default.** Spawned enemies have their AI disabled (no movement, no shooting) so
  shots-to-kill counts are exact. Set `freeze = false` in the config for live-AI tests.
- **Difficulty cycling.** Switch between Normal, Hard, Very Hard and Overkill; enemies spawned
  afterwards use the new difficulty's scaling.

## Key bindings

| Key | Action |
| --- | --- |
| `F5` | Clear all spawned subjects |
| `F7` / `Shift+F7` | Next / previous enemy type |
| `F8` | Spawn the selected enemy at the selected distance (replaces the previous one, faces you) |
| `Shift+F8` | Spawn the full roster in an arc (legacy mode) |
| `F9` / `Shift+F9` | Next / previous distance |
| `Ctrl+F9` / `Ctrl+Shift+F9` | Fine nudge current distance by +1 m / -1 m |
| `F10` / `Shift+F10` | Next / previous difficulty |

Each action prints a line to the UE4SS log, e.g.
`enemy 4/15 Taser | distance 12.50 m (3/7, auto)`.

## Configuration

Edit `scripts\user_config.lua` inside the deployed mod folder:

```lua
return {
    distanceMode = "auto",   -- "auto" = equipped weapon breakpoints, "manual" = use the list below
    distances = { 2.5, 5, 10, 15, 25, 50 },  -- meters; manual mode and fallback
    freeze = true,           -- false = live-AI test subjects
    autoSpawn = false,       -- reserved; the mod never auto-spawns
}
```

`deploy.ps1` preserves an edited `user_config.lua` across redeploys (it is created from the
template only when missing).

## Compatibility notes

- **Do not run with KillStatsMod while killing spawned enemies.** Directly spawned pawns are not
  registered by the game's spawn pipeline, and native damage/kill hooks (KillStatsMod uses several)
  crash the game when they read such a pawn's death data. Disable KillStatsMod while using the
  range; WeaponStatsViewer is unaffected.
- Spawning works anywhere you press `F8`; the range is simply the safest place to test.
- The TrainingGrounds spawned-pawn caveat applies to any mod that hooks `HandleTakePointDamage`,
  `Multicast_OnKill` or the damage-feed events.

## Repository layout

```
TrainingGroundsMod/
  lua/TrainingSpawner/      mod sources (scripts, tests, mod.txt)
  shared/pd3lib/            pd3lib submodule (pinned; vendored into the release at build time)
  docs/                     findings, plans, ModWorkshop page copy
  deploy.ps1                build+deploy to the local UE4SS Mods folder
  release.ps1               build dist/TrainingSpawner-<version>.zip
```

Development:

```powershell
git submodule update --init          # fetch pd3lib
.\deploy.ps1                         # deploy to UE4SS Mods
.\release.ps1                        # build the ModWorkshop zip
```

Syntax gate: `npx --yes luaparse lua/TrainingSpawner/scripts/main.lua`.
Unit tests (fengari): `lua/TrainingSpawner/tests/freeze_logic_test.lua` (logic moved to pd3lib is
covered by pd3lib's own tests).

## Credits

- [`pd3lib`](https://github.com/met94/pd3lib) — shared UE4SS helper library (bundled).
- Built for the PAYDAY 3 modding community; uses the ModWorkshop / Moolah tooling ecosystem.

## License

MIT — see [LICENSE.md](LICENSE.md).
