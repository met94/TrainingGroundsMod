# Training Grounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** All enemy types spawn fully frozen in the PAYDAY 3 `NewShootingRange` training area, on all
four difficulty tiers, via a pak that replaces the range's assault settings plus a standalone UE4SS
Lua freezer mod.

**Architecture:** Replace the existing cooked `DA_AssaultManagerSettings` asset (the one the range's
`SBZWorldSettings` references) with an edited copy containing all enemy squads at all progression
tiers and raised limits. A separate UE4SS Lua mod watches the range map and calls the proven
`SBZAIController:SetAIEnabled(false, FName)` on every enemy pawn that appears.

**Tech Stack:** retoc 0.1.5 (IoStore unpack/repack), UAssetGUI/UAssetAPI (cooked property edits),
UE4SS 3.0.1 (Lua runtime), PowerShell build scripts.

**Spec:** `TrainingGroundsMod/docs/2026-09-26-training-grounds-design.md`

## Global Constraints

- Do not edit existing UE4SS mods in `Mods/`/`Mods2/` (WeaponStatsViewer, CrewLab, KillStatsMod, …). New work is new folders only.
- Game data edits must come from the **live install** (`PAYDAY3\Content\Paks`), not the stale `Exports/` or `Output/` trees.
- AES key lives in `C:\Users\AB\AppData\Roaming\FModel\AppSettings.json` (read it; never hardcode/copy it into shipped files).
- Keep an untouched backup of every extracted/edited game asset under `TrainingGroundsMod/work/backup/`.
- Uninstall must always be trivial: delete `TrainingSpawns_P.*` from `~mods` and the `TrainingFreeze` folder.
- UE4SS Lua rules (CrewLab findings): never call a hooked function, never hot-reload (full game restart per deploy), `PushOrder(Order, Mode)` arg order, `ToFName` for FName args.
- No commits in this repo (workspace is not a git repo); no game-file commits.
- Evidence only for game facts: exports, live containers, UE4SS logs, in-game observation.
- Phase 0 findings override plan details; record deviations in the runbook.

## Review Focus

- **Unsigned container without bypass**: game may fatal at boot (`Pak master signature table check failed`) — Task 2 must observe boot success, not assume it.
- **Container triple shape**: retoc `to-zen` output may lack the `.pak` stub the game scan expects — Task 2 verifies which of `.utoc/.ucas/.pak` is actually needed.
- **Range spawns no AI**: `bEnableNavigationSystem=false` on the map may block spawn points — Task 4 decides whether Lua kickstart/`ForceSpawnSquad` is needed.
- **Frozen-but-despawned / respawn**: assault waves may recycle pawns faster than the freeze watcher sees them — Task 7 must handle re-apply on new pawn/controller.
- **Default-asset side effects**: replacing the shared default settings changes HoldOut fallback/legacy-range behavior — Task 8 documents this and the uninstall.

---

### Task 1: Project scaffold and toolchain baseline

**Files:**
- Create: `TrainingGroundsMod/docs/` (design done), `work/`, `assets/`, `dist/`, `lua/`
- Create: `TrainingGroundsMod/scripts/Build-Pak.ps1` (build helper, filled in Task 6)

**Interfaces:**
- Produces: workspace folder layout and reusable retoc invocation pattern for later tasks.

- [ ] **Step 1: Create folders**

```powershell
$root='D:\Programowanie\payday\3\InsurancePolicySolo\TrainingGroundsMod'
New-Item -ItemType Directory -Force "$root\work\live_extract","$root\work\backup","$root\work\reference_mods","$root\assets","$root\dist","$root\lua","$root\scripts" | Out-Null
```

- [ ] **Step 2: Verify retoc + AES key read**

```powershell
$key=(Get-Content 'C:\Users\AB\AppData\Roaming\FModel\AppSettings.json' -Raw | ConvertFrom-Json).PerDirectory.'D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Content\Paks'.AesKeys.mainKey
& 'C:\Users\AB\.cargo\bin\retoc.exe' -a $key info 'D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Content\Paks\pakchunk4-PAK_ONE-Windows.utoc'
```

Expected: container info prints (mount point `../../../PAYDAY3/Content/`), no `missing encryption key`.
Note: the AES key contains `0x…` and must be passed without quotes issues; store it only in a
git-ignored local file if cached (`$root\work\.aeskey` is acceptable locally, never shipped).

---

### Task 2: Phase 0a — mount proof and bypass identification

**Files:**
- Create: `PAYDAY3\Content\Paks\~mods\` (game install)
- Create: `TrainingGroundsMod\work\live_extract\**` (extracted legacy asset)
- Create: `TrainingGroundsMod\dist\TrainingSpawns_P.*` (no-op container for the test)

**Interfaces:**
- Produces: known-good `~mods` install procedure + evidence of which signature bypass is active;
  `TrainingSpawns_P` container name reused by all later tasks.

- [ ] **Step 1: Extract the live default settings asset (no-op copy)**

```powershell
$key=(Get-Content 'C:\Users\AB\AppData\Roaming\FModel\AppSettings.json' -Raw | ConvertFrom-Json).PerDirectory.'D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Content\Paks'.AesKeys.mainKey
$paks='D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Content\Paks'
$root='D:\Programowanie\payday\3\InsurancePolicySolo\TrainingGroundsMod'
& 'C:\Users\AB\.cargo\bin\retoc.exe' -a $key to-legacy --version UE5_5 -f DA_AssaultManagerSettings "$paks\pakchunk0-PAK_Minimal-Windows.utoc" "$root\work\live_extract"
Get-ChildItem "$root\work\live_extract" -Recurse -Filter 'DA_AssaultManagerSettings*' | Select-Object FullName, Length
```

Expected: `…\Gameplay\AI\Assault\DA_AssaultManagerSettings.uasset` + `.uexp` (also the Pharaoh
variant if the filter is substring-based). Copy the extracted pair to `work\backup\` untouched.

- [ ] **Step 2: Repack as a `_P` IoStore container**

```powershell
& 'C:\Users\AB\.cargo\bin\retoc.exe' to-zen --version UE5_5 "$root\work\live_extract" "$root\dist\TrainingSpawns_P.utoc"
Get-ChildItem "$root\dist"
```

Expected: `TrainingSpawns_P.utoc` + `TrainingSpawns_P.ucas`. If retoc emits a `.pak`, record its
size; if not, copy the path of an existing 365-byte game stub
(`PAYDAY3\Content\Paks\pakchunk4-PAK_ONE-Windows.pak`) as a candidate stub and test both variants.

- [ ] **Step 3: Install into `~mods` and check for existing bypass**

```powershell
New-Item -ItemType Directory -Force "$paks\~mods" | Out-Null
Copy-Item "$root\dist\TrainingSpawns_P.*" "$paks\~mods\" -Force
Get-ChildItem 'D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Binaries\Win64' -Filter '*AllowMods*'
```

Expected: container copied. Note whether a bypass artifact exists (none was found on 2026-09-26).

- [ ] **Step 4: Boot test (user launches game to main menu)**

Ask the user to launch PAYDAY 3 and reach the main menu, then check:

```powershell
$game='D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3'
Select-String -LiteralPath "$game\Binaries\Win64\ue4ss\UE4SS.log" -Pattern 'Mounted|~mods|signature|SigBypass' | Select-Object -Last 20
Get-ChildItem "$game\Saved\Logs" -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 3 Name, LastWriteTime
Get-ChildItem "$game\Binaries\Win64" -Filter 'PD3AllowMods.log' -ErrorAction SilentlyContinue
```

Expected: no `Pak master signature table check failed` fatal, game reaches menu. Record which
evidence line proves mount (or its absence). If the game fatals or silently ignores the container:
install `PD3AllowMods.asi` v19 (`PD3-MoolahProject\Tools\Install-PD3AllowMods.ps1`) or `SigBypassMod`
(Nexus 265) and retest — record which one worked.

- [ ] **Step 5: Record outcome**

Append to `TrainingGroundsMod/docs/phase0-findings.md`: bypass used, container file set required,
boot result, log evidence.

---

### Task 3: Phase 0b — unpack reference mods for edit patterns

**Files:**
- Create: `TrainingGroundsMod\work\reference_mods\**`
- Create: `TrainingGroundsMod\docs\phase0-findings.md` (append)

**Interfaces:**
- Produces: list of asset paths + property patterns used by existing spawn mods (feeds Task 6).

- [ ] **Step 1: Download the reference mods**

Primary source pages: ModWorkshop mod 55079 (PAINDAY - More Spawns), mod 50160 (Specials Only),
Nexus "No Enemy". Use browser download links from the pages (`files.modworkshop.net`); store under
`work\reference_mods\`. If a page requires login, record it and continue with the others.

- [ ] **Step 2: Inspect containers**

```powershell
$key=(Get-Content 'C:\Users\AB\AppData\Roaming\FModel\AppSettings.json' -Raw | ConvertFrom-Json).PerDirectory.'D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Content\Paks'.AesKeys.mainKey
$ref='D:\Programowanie\payday\3\InsurancePolicySolo\TrainingGroundsMod\work\reference_mods'
Get-ChildItem $ref -Recurse -Include '*.pak','*.utoc' | ForEach-Object { & 'C:\Users\AB\.cargo\bin\retoc.exe' -a $key list --path $_.FullName }
```

Expected: asset paths each mod overrides (look for `DA_AssaultManagerSettings`, `DA_SWAT*Squad*`,
`DA_Special*`, `DA_Pawn*`). Record exact paths + which properties appear to be edited.

- [ ] **Step 3: Append findings**

Add a table (mod → overridden assets → observed values) to `docs/phase0-findings.md`. If a mod uses
a pattern worth copying (e.g. weight 0 vs removed entry), note it for Task 6.

---

### Task 4: Phase 0c — range recon probe

**Files:**
- Create: `TrainingGroundsMod\lua\TrainingProbe\scripts\main.lua`
- Deploy: `PAYDAY3\Binaries\Win64\ue4ss\Mods\TrainingProbe\` (+ `enabled.txt`)
- Create: `TrainingGroundsMod\docs\phase0-findings.md` (append)

**Interfaces:**
- Produces: yes/no answers for (a) `PD3AssaultManager` present on the range and active, (b) whether
  enemy pawns spawn there unaided, (c) any runtime difficulty setter, (d) nav/spawn viability.
  Feeds Task 6/7 design choices.

- [ ] **Step 1: Write the probe**

`main.lua`: log level/heist name at `OnLevelInit`; `F6` keybind dumps (via `ExecuteInGameThread`):
`FindFirstOf("PD3AssaultManager")` (+ `Settings`, `IsAssaultActive`), enemy pawn count by class,
`bEnableNavigationSystem` if readable, and any `SetDifficulty`-like functions found on
`GameState`/`GameInstance`. All output prefixed `[TrainingProbe]`. No hooks on functions the probe
calls; observation only.

- [ ] **Step 2: Syntax gate + deploy**

```powershell
npx --yes luaparse 'D:\Programowanie\payday\3\InsurancePolicySolo\TrainingGroundsMod\lua\TrainingProbe\scripts\main.lua'
$dst='D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Binaries\Win64\ue4ss\Mods\TrainingProbe'
New-Item -ItemType Directory -Force "$dst\scripts" | Out-Null
Copy-Item 'D:\Programowanie\payday\3\InsurancePolicySolo\TrainingGroundsMod\lua\TrainingProbe\scripts\main.lua' "$dst\scripts\" -Force
New-Item -ItemType File -Force "$dst\enabled.txt" | Out-Null
```

- [ ] **Step 3: Live run (user enters the shooting range)**

Restart game, enter Shooting Range, press `F6`, then read:

```powershell
Select-String -LiteralPath 'D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Binaries\Win64\ue4ss\UE4SS.log' -Pattern '\[TrainingProbe\]' | Select-Object -Last 40 | ForEach-Object { $_.Line }
```

- [ ] **Step 4: Record answers + decision**

Append to `docs/phase0-findings.md`; state whether Task 7 needs an assault kickstart path.

---

### Task 5: Phase 1 — minimal override proof

**Files:**
- Modify: `TrainingGroundsMod\assets\DA_AssaultManagerSettings.uasset/.uexp`
- Rebuild: `TrainingGroundsMod\dist\TrainingSpawns_P.*`

**Interfaces:**
- Produces: proven end-to-end edit→pack→mount→observe loop; asset editor choice recorded
  (UAssetGUI vs UAssetAPI script).

- [ ] **Step 1: Edit one harmless value**

Using UAssetGUI (download from GitHub releases) open the extracted `.uasset`; change exactly one
`ProgressionArray` squad `Weight` (e.g. Normal tier 0.0 first squad `0.8 → 0.81`) in the
`properties` view; save.

- [ ] **Step 2: Repack and install**

Re-run Task 2 Step 2–3 commands (to-zen + copy to `~mods`).

- [ ] **Step 3: Verify in game**

Launch, enter the range; the change is not directly visible — verification uses the Task 4 probe or
an updated log line in the probe (`Weight` read from the live `PD3AssaultManager.Settings` asset if
reachable). If unreadable, fall back to observing spawn composition differences on the next wave
after setting a distinguishing value (e.g. one squad count).

- [ ] **Step 4: Uninstall test**

Delete `TrainingSpawns_P.*` from `~mods`, boot, confirm vanilla behavior (no fatal, no residual).

- [ ] **Step 5: Record in findings**

Note editor tool + exact steps; this becomes the Task 6 procedure.

---

### Task 6: Phase 2 — full spawn configuration pak

**Files:**
- Modify: `TrainingGroundsMod\assets\DA_AssaultManagerSettings.uasset/.uexp`
- Create: `TrainingGroundsMod\scripts\Build-Pak.ps1`
- Build: `TrainingGroundsMod\dist\TrainingSpawns_P.{pak,utoc,ucas}`

**Interfaces:**
- Consumes: Task 5 edit loop + Task 3 reference patterns + Task 4 spawn answers.
- Produces: shippable spawn pak.

- [ ] **Step 1: Enumerate target squads per type**

From the live asset (or its FModel export as a field map), list every `SquadArray` entry per
difficulty/tier; map each to its enemy type. Target set (replace mode): all `DA_SWATSquad_*`,
`DA_Special_{Taser,Grenadier,Dozer,Cloaker,Tower}`, `DA_SWATSquad_Shield`, `DA_PoliceSquad_Sniper`,
DLC Moon squads, cop/security squads. Non-target squads → weight `0`.

- [ ] **Step 2: Apply edits: all types at all tiers for all 4 difficulties**

For `DifficultySettingsArray[0..3]` and each `ProgressionArray` tier: ensure each target squad entry
exists with weight `1.0`; zero others. Raise `MaxNumPawnsAlive`, `MaxNumSquadsAlive`,
`MaxNumSquadsPerWave`, `MaxTotalAISpawnCount`; clear `AITypesToIgnore`; ensure
`TypesToIgnoreDuringFirstBuildup` empty.

- [ ] **Step 3: Build script**

`Build-Pak.ps1` wraps: read AES key → verifies `assets\` files → `retoc to-zen --version UE5_5
assets dist\TrainingSpawns_P.utoc` → copies triple shape required by Task 2 outcome to `dist\`.

- [ ] **Step 4: Install + verify**

Copy to `~mods`; in game enter range on each difficulty (or whichever difficulty is available) and
tick each enemy type on the checklist (Task 8). Record screenshot/log evidence.

---

### Task 7: Phase 3 — TrainingFreeze Lua mod (TDD)

**Files:**
- Create: `TrainingGroundsMod\lua\TrainingFreeze\scripts\main.lua`
- Create: `TrainingGroundsMod\lua\TrainingFreeze\packages\` (pure-logic module + tests, fengari)
- Deploy: `ue4ss\Mods\TrainingFreeze\` (+ `enabled.txt`)
- Update: `TrainingGroundsMod\docs\phase0-findings.md`, runbook

**Interfaces:**
- Consumes: Task 4 answers (whether kickstart needed), CrewLab `pd3.safe` patterns.
- Produces: freeze watcher with `[TrainingFreeze]` log lines and a `F7` manual tick for testing.

- [ ] **Step 1: Write failing tests for pure logic (fengari syntax + unit)**

Test module `freeze_logic.lua`: `ShouldHandle(levelName)` (only `NewShootingRange`),
`ClassifyPawn(className)` (target set), `NeedsFreeze(controllerLastReason, reason)` (true when
different), dedupe rule. Run with the existing fengari harness pattern
(`C:\Users\AB\AppData\Local\Temp\opencode\fengari\node_modules\.bin\fengari.cmd` + a local test
script). Expected: FAIL (module missing).

- [ ] **Step 2: Implement minimal module; tests pass**

- [ ] **Step 3: Wire runtime `main.lua`**

Level gate via `OnLevelInit`; tick loop collecting `SBZAICharacter`/enemy pawns, reading
`Controller:LastDisabledReason`, calling `SetAIEnabled(false, ToFName("TrainingFreeze"))`; re-apply
on new pawns; optional kickstart calls only if Task 4 said needed; `F7` manual tick logging.

- [ ] **Step 4: Syntax gate + deploy + full restart**

`npx --yes luaparse` on both files; copy to `ue4ss\Mods\TrainingFreeze`; create `enabled.txt`; verify
no existing mods touched; full game restart.

- [ ] **Step 5: In-game verification**

Enter range: every enemy frozen (no movement/shooting), `[TrainingFreeze] frozen <class> (<n>)` log
lines for each type; kill one and confirm replacement wave also freezes. Record evidence.

---

### Task 8: Phase 4 — verification checklist and runbook

**Files:**
- Create: `TrainingGroundsMod\docs\runbook.md`
- Create: `TrainingGroundsMod\docs\reference\` (per-file documentation of edited assets)

**Interfaces:**
- Produces: user-facing install/verify/uninstall instructions + data-vs-runtime map.

- [ ] **Step 1: Per-file asset documentation**

For each edited asset: source path in the live container, changed fields (before → after), and why.

- [ ] **Step 2: Enemy/difficulty checklist**

Table: enemy class × expected (present, frozen) × observed per difficulty; plus fallback-mode
side-effect notes (HoldOut/legacy range) and difficulty-selection findings.

- [ ] **Step 3: Runbook**

Install path (`~mods` triple), launch requirements (bypass), what to expect in game, verification
(log lines, F7 keybind), uninstall (delete container + `TrainingFreeze` folder), known limitations
(data-only vs runtime split), restore-from-backup instructions.

- [ ] **Step 4: Final clean-boot verification**

With mod removed: game boots vanilla and range behaves normally. With mod installed: checklist
passes. Record both in runbook.
