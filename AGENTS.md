# TrainingGroundsMod — agent notes

See `..\..\AGENTS.md` (workspace root) for paths, versions and rules.

- Spawner test rig: freeze/spawn any enemy at fixed distances for live armor/pen tests.
- Deploy: `.\deploy.ps1` → `Mods\TrainingSpawner`; release: `.\release.ps1`.
- Lua test: `..\..\tools\fengari\node_modules\.bin\fengari.cmd lua\TrainingSpawner\tests\freeze_logic_test.lua`.
- Deployed config: `lua\TrainingSpawner\scripts\user_config.lua` (distances, freeze, keepSubjects).
- `tools\UAssetEdit` = C#/UAssetAPI uasset↔json converter.
- `shared\pd3lib` is the pinned development revision — read-only, never sync.
