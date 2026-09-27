# Training Grounds — design and research report

Date: 2026-09-26
Scope: PAYDAY 3, `NewShootingRange` ("Shooting Range", DLC 00232-JUDGEMENT) — the new training area.
Goal: all enemy types spawn in the training area, fully frozen (no movement, no shooting), with all
four difficulty tiers populated, in replace mode (only the chosen enemies).
Approach: hybrid — pak for spawn data, small standalone UE4SS Lua mod for the runtime AI freeze.

## 1. Confirmed requirements (user decisions)

| Question | Answer |
|---|---|
| Maps | Training area (`NewShootingRange`) only |
| Enemies | All enemy types that exist (SWAT + heavies, Shield, Sniper, Taser, Grenadier, Dozer, Cloaker, Tower, Moon, Armed/Base cop, security guard) |
| "Disable AI" | Fully frozen — no movement, no shooting (proven `SBZAIController:SetAIEnabled(false, FName)` path) |
| Wave composition | Replace — only the chosen enemies |
| Difficulties | All four (Normal/Hard/VeryHard/Overkill); fill all 4 tiers + probe for a runtime difficulty setter |
| Strategy | Hybrid: pak (spawns) + UE4SS Lua (freeze) |
| Settings asset | Community precedent + new-UClass registration wall (see §4.3) favour replacing the existing default asset directly; re-evaluate if Phase 1 map-edit proves trivial |
| Pak mount | Assume `~mods` works; user confirms directory; Phase 0a verifies |

## 2. Verified environment

- Game: PAYDAY 3 UE **5.5**, exe `PAYDAY3-Win64-Shipping.exe` (160,226,816 B, 2026-09-24).
- IoStore under `PAYDAY3\Content\Paks\` (`pakchunk0-PAK_Minimal` = main game data,
  `PAK_Heists` = heist + assault settings, `PAK_ONE` etc. per-heist). Containers are
  Encrypted|Compressed|Indexed; header version `SoftPackageReferences`; TOC version
  `ReplaceIoChunkHashWithIoHash`; mount point `../../../PAYDAY3/Content/`.
- AES key for IoStore: in FModel settings `C:\Users\AB\AppData\Roaming\FModel\AppSettings.json`
  (`mainKey`, `0x27DF...D394`). Not duplicated here; read it from that file.
- `retoc 0.1.5` at `C:\Users\AB\.cargo\bin\retoc.exe` (to-legacy/to-zen/unpack/pack-raw/list/info).
- Legacy unpack of the game already exists at `PAYDAY3\Content\Paks\Output\` (73,326 `.uasset`,
  74,397 `.uexp`, 1,071 `.umap`), dated **2026-09-23** — may predate the 2026-09-24 hotfix.
  Always re-extract targets from the live containers for edits.
- `dotnet` available (UAssetAPI/UAssetGUI route for cooked property edits). No UE editor installed
  yet; user plans to install UE 5.5.
- UE4SS present at `...\Win64\ue4ss\` (log `...\ue4ss\UE4SS.log`), active Lua/C++ mods in `Mods\`
  (WeaponStatsViewer, CrewLab staging, KillStatsMod, …). Local UE4SS proxy is `dwmapi2.dll`
  (UE4SS Injection Proxy); no `winmm.dll`/`.asi` bypass present.
- Team rule: do not modify existing mods in `Mods\`/`Mods2\`; new work gets its own folder.

## 3. Spawn data chain (verified in exports + live container listings)

```
DA_Heist_NewShootingRange (PD3HeistDataAsset, live: PAK_Minimal)
  HeistReference "NewShootingRange", LevelPath /Game/DLCs/00232-JUDGEMENT/NewShootingRange/NewShootingRange
Map NewShootingRange → SBZWorldSettings.AssaultManagerSettings
  → /Game/Gameplay/AI/Assault/DA_AssaultManagerSettings   (the DEFAULT asset)
```

- `DA_AssaultManagerSettings` is a `PD3AssaultSettings`:
  `DifficultySettingsArray[0..3]` (Normal..Overkill) → `ProgressionArray`
  (`StartAtProgression` 0.0 / 0.33 / 0.66 / 1.0) → `SquadArray[].Weight` + `PD3SpawnSquadPawn`.
- Related editable fields: `AITypesToIgnore`, `MaxNumPawnsAlive`, `MaxNumPawnsPerPlayer`,
  `MaxNumSquadsAlive`, `MaxNumSquadsPerWave`, `MaxTotalAISpawnCount`, `SquadCooldown`,
  `SquadLimits`, `TypeCooldowns`, `TypeLimits`, `TypesToIgnoreDuringFirstBuildup`,
  `SecuritySettingDataModifiers`, drama curves.
- Squad assets observed: `DA_SWATSquad_*`, `DA_Special_{Taser,Grenadier,Dozer,Cloaker,Tower}`,
  `DA_SWATSquad_Shield`, `DA_PoliceSquad_Sniper`, DLC specials (Moon).
- The map also sets `bEnableNavigationSystem: false` and `bStartWithAICrew: false`.
- `NewShootingRange` is **not in the heist database** (`DS_HeistDatabase`) — it is not a contract;
  there is no lobby difficulty selection. Effective difficulty is whatever the range flow sets.
- Sharing: the default settings asset is also referenced by `BP_HeistGameMode` (fallback),
  `BP_HoldOutGameMode`, and the legacy shooting range/mode paths. Replacing it has global
  side-effects only where an explicit settings asset is absent.

## 4. Research findings that shape the design

### 4.1 Pak modding toolchain (community, cross-checked against local tooling)

- Install path for mod containers: `PAYDAY3\Content\Paks\~mods\`, file names end
  `_P.{pak,utoc,ucas}` (IoStore triple; the `.pak` is a stub/header next to `.utoc`/`.ucas`).
- Cooked-property edit pipeline: extract live asset (`retoc to-legacy`) → edit the cooked
  `.uasset`/`.uexp` with UAssetGUI/UAssetAPI → convert back (`retoc to-zen --version UE5_5`) →
  install triple in `~mods`.
- New Blueprint/asset authoring uses the UE 5.5 editor plus a Moolah-style cook kit
  (`PD3-MoolahProject`, Moolah docs). Not required for this mod unless we add new BPs/UI.
- Sources: Steam "How to install MODS [PAYDAY 3]" guide; `moolah.dev/docs`; PD3-MoolahProject
  `docs/pd3-ue5-modding/03-mod-loader.md`, `04-making-mods.md`; Nexus "UE4SS For PD3 - UE5" (mod 265).

### 4.2 Signature / mount walls

- Current builds reject unsigned IoStore containers unless a bypass is active. Known solutions:
  - `PD3AllowMods.asi` v19 (36 memory patches) via `winmm.dll` (PD3-MoolahProject `Tools/PD3AllowMods`);
  - `SigBypassMod` (Nexus 265) — logs `[SigBypassMod] Mounted unsigned mod: Name_P`.
- Local state: `AllowModsMod.dll` (UE4SS C++ mod) reports
  `[AllowModsMod]: Delegate not found. Unable to patch.` on the current exe; no ASI bypass present.
- **Wall A** = mount/signature; **Wall B** = new Blueprint UClass registration. Overriding an
  existing asset path is the reliable case; creating new `/Game/Mods/...` classes is not yet
  confirmed by the community. Design therefore replaces an existing asset.

### 4.3 AI-disable options (data vs runtime)

- No serialized AI on/off switch exists on any enemy asset (verified across character BPs,
  `DA_*AIAbilityData`, `PD3PawnVariation`, `SBZPawnSpawnRequestData`, utility data; no `NoAI`
  tags/GEs). `SBZAIUtilityDecider.bEnabled` is not serialized and runtime writes were ignored.
- Only proven mechanism: `SBZAIController:SetAIEnabled(false, FName)` (freeze movement + shooting).
- Precedent: community "Proving Grounds" custom heist spawns NPCs "with no logic" via a UI enemy
  spawner (different mechanism, validates the goal).

### 4.4 Reference mods to unpack (patterns for spawn edits)

- PAINDAY - More Spawns (ModWorkshop 55079, 3.03 MiB pak) — enemy limits/spawn times/amounts.
- Specials Only (ModWorkshop 50160) — replaces SWAT with a chosen special.
- No Enemy (Nexus) — removes SWAT/police after the first wave on BranchBank.
- These should be opened with `retoc`/`repak` during Phase 0b to confirm which assets they override.

## 5. Design

```
TrainingGroundsMod/
├── docs/                     this report, plan, runbook
├── work/                     scratch: live extracts, reference mods (not shipped)
├── assets/                   edited cooked assets (working copies)
├── dist/                     built mod containers (shipped)
│   └── TrainingSpawns_P.{pak,utoc,ucas}
└── lua/TrainingFreeze/       standalone UE4SS Lua mod (freeze watcher)
```

### 5.1 Pak half — spawn configuration

- Replace `/Game/Gameplay/AI/Assault/DA_AssaultManagerSettings` (the asset the range loads).
- For each of `DifficultySettingsArray[0..3]`: make every progression tier contain all enemy
  squads, replace mode (weights of non-target squads → 0, target squads → 1.0), raise the
  `MaxNum*` limits and disable `AITypesToIgnore` filtering, so all types are eligible.
- Verify with the Phase 1 minimal override before the full edit.

### 5.2 Lua half — freeze watcher

- New UE4SS mod folder (`TrainingFreeze`), scripts only, no edits to existing mods.
- Gate: only when the current level is `NewShootingRange` (heist/level name check).
- Every tick (e.g. 500 ms): collect enemy pawns (class list from `enemies.json` + DLC classes);
  for each pawn with a controller whose `LastDisabledReason` is not our reason, call
  `SetAIEnabled(false, ToFName("TrainingFreeze"))`; re-apply when a pawn respawns/re-possesses.
- If Phase 0c shows the range never starts an assault: also call `SetAssaultActive(true)` /
  `StartEndlessAssault(true)` / `ForceSpawnSquad` fallback (only if needed).
- Difficulty: if Phase 0c finds a runtime difficulty setter, optional hotkey to switch; otherwise
  the pak's all-four-tier population covers whichever difficulty the range uses.
- Honor CrewLab hard rules: never hook a function we call, no hot reload, full restart per deploy.

### 5.3 Data flow

1. Game boots → mounts `~mods` container (bypass required if unsigned).
2. Range loads → default `PD3AssaultSettings` = our edited asset → assault director picks waves
   from all-vs-all squads for the active difficulty.
3. `TrainingFreeze` observes `/Script/Starbreeze.SBZAICharacter`/pawn classes in the range and
   disables each AI controller as soon as it appears.

### 5.4 Testing / verification strategy

- Pak: boot without fatal; UE4SS probe finds the range; spawn composition observed in game
  (enemy checklist per difficulty); clean uninstall by deleting the container.
- Lua: unit-test pure logic with the existing Fengari harness pattern (see WeaponStatsViewer
  `tools/`), `luaparse` syntax gate, deploy, then in-game verification with log lines
  (`[TrainingFreeze]` prefix).
- Phase 0/1 act as smoke tests before content is authored.

## 6. Constraints and risks

- **Mount bypass may be required** (`PD3AllowMods.asi` v19 or `SigBypassMod`); Phase 0a decides.
- **New asset registration (Wall B)** — mitigated by replacing an existing asset path.
- **Range may not spawn AI at all** (nav disabled, no assault integration). Phase 0c probes
  `PD3AssaultManager` presence/state; fallback is `ForceSpawnSquad`/direct spawn + Lua kickstart.
- **Difficulty may not be selectable in the range.** All four tiers still populated; runtime setter
  probed.
- **Global default-asset side-effects** on fallback modes (HoldOut game mode, legacy range).
  Accepted for now; a dedicated asset + `.umap` repoint is the fallback if side-effects matter.
- **Hotfix drift**: live game newer than the export/dump. Always extract target assets from the
  live containers; re-verify after game updates.
- **Backups/uninstall**: keep untouched copies of every extracted asset and a one-line removal
  path (delete `TrainingSpawns_P.*` from `~mods`, delete `TrainingFreeze` folder).
