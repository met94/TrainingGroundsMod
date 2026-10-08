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
  shots-to-kill counts are exact. Set `freeze = false` in the config for live-AI tests, or press
  `F11` (rebindable) to flip the option at runtime — it applies to the next spawns.
- **Difficulty cycling.** Switch between Normal, Hard, Very Hard and Overkill; enemies spawned
  afterwards use the new difficulty's scaling.
- **In-game chat notices.** Enemy, distance and difficulty changes print a colour-coded line to
  the chat (toggle with `chatNotice` in the config).

## Key bindings

| Key | Action |
| --- | --- |
| `F5` | Clear all spawned subjects |
| `F7` / `Shift+F7` | Next / previous enemy type |
| `F8` | Spawn the selected enemy at the selected distance (replaces the previous one unless `keepSubjects`; faces you) |
| `Shift+F8` | Spawn the full roster in an arc (legacy mode) |
| `F9` / `Shift+F9` | Next / previous distance |
| `Ctrl+F9` / `Ctrl+Shift+F9` | Fine nudge current distance by +1 m / -1 m |
| `F10` / `Shift+F10` | Next / previous difficulty |
| `F11` | Toggle `freeze` for the next spawns (chat + log feedback) |

Every binding is rebindable and each one can be disabled: configure the `keys` table in
`user_config.lua` (see below). An action that is not listed there is simply not bound.

Each action prints a line to the UE4SS log, e.g.
`enemy 4/15 Taser | distance 12.50 m (3/7, auto)`. The load log lists every binding
(`keybind freezeToggle: F11 registered`) and every disabled one.

## Configuration

Edit `scripts\user_config.lua` inside the deployed mod folder:

```lua
return {
    distanceMode = "auto",   -- "auto" = equipped weapon breakpoints, "manual" = use the list below
    distances = { 2.5, 5, 10, 15, 25, 50 },  -- meters; manual mode and fallback
    freeze = true,           -- false = live-AI test subjects (F11 flips this at runtime)
    autoSpawn = false,       -- reserved; the mod never auto-spawns
    chatNotice = true,       -- print enemy/distance/difficulty changes to the in-game chat
    keepSubjects = false,    -- true = F8 adds another subject instead of replacing the previous one
    keys = {                 -- action -> key ("Key" or "Mod+Key"); remove a line to disable it
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
```

`keys` specs are `Mod+Key` combos (`Shift+F7`, `Ctrl+Shift+F9`; `Ctrl` = `Control`). Key names
are the UE4SS `Key` enum names such as `F1`..`F24`, `NUM_ONE`, `SPACE`, `A`..`Z`. An action
missing from the table is not bound at all; `keys = false` disables every binding; deleting the
whole table restores the defaults above. Invalid specs are disabled and reported in the UE4SS log.

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

- [PD3 UE4SS + Allow Pak Mods](https://modworkshop.net/mod/47771) — the UE4SS build PAYDAY 3 mods
  run on.
- [`pd3lib`](https://github.com/met94/pd3lib) — shared UE4SS helper library (bundled).

## Thanks

- Spawn-override research that informed this mod: PAINDAY – MoreSpawns (Gordon Greedman),
  Specials Only (Rockbear), Proving Grounds (Lawsfercapcake).
- The PAYDAY 3 weapon bench ([P9317](https://github.com/P9317/payday-weapon-bench), upstream
  [puppy-girl](https://github.com/puppy-girl/payday-weapon-bench)) — the range-row presentation
  the distance list mirrors.
- Development tooling: FModel, [retoc](https://github.com/trumank/retoc),
  UAssetAPI/UAssetGUI, and the [Moolah modding docs](https://moolah.dev/docs).

## Disclaimer

Unofficial mod; not affiliated with Starbreeze. PAYDAY 3 and its trademarks belong to
Starbreeze Entertainment.

## License

MIT — see [LICENSE.md](LICENSE.md).
