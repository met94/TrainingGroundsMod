# Phase 0 findings — training area mod

Running log. Newest entries at the bottom of each section.

## Toolchain

- retoc 0.1.5 (latest release, 2026-01-02) **can read** container indexes (`info`, `list`) but
  **cannot convert assets** from the live (post-2026-09-24) containers: every `to-legacy`
  conversion fails (`Extracted 0 (N failed)`), no diagnostic even with `--debug`. Forcing
  `--override-container-header-version SoftPackageReferencesOffset` panics
  (`container_header.rs:60` assert against detected `SoftPackageReferences`).
  Tested containers: `pakchunk0-PAK_Minimal`, `pakchunk4-PAK_ShootingRange`, `pakchunk4-PAK_Players`.
- The pre-update legacy tree at `PAYDAY3\Content\Paks\Output\` (2026-09-23) is readable and usable.
  `retoc to-zen --version UE5_5` packs it successfully and emits the full IoStore triple:
  `TrainingSpawns_P.pak` (347 B) + `.utoc` (487 B) + `.ucas` (6680 B).
- Working pipeline: edit legacy asset from `Output\PAYDAY3\Content\...` → `retoc to-zen` → install
  triple to `~mods`.
- Risk: `Output\` predates the 2026-09-24 hotfix. Data-asset structure changes between the two are
  unlikely for these squad/weight fields; verify in game with the Phase 1 minimal edit.

## Mount test (Phase 0a)

- Created `PAYDAY3\Content\Paks\~mods\`; installed `TrainingSpawns_P.{pak,utoc,ucas}` (no-op copy of
  `DA_AssaultManagerSettings`).
- Packed container verified with `retoc list/info`: chunk path
  `../../../PAYDAY3/Content/Gameplay/AI/Assault/DA_AssaultManagerSettings.uasset`; flags `Indexed`
  (unsigned); header `SoftPackageReferences`; TOC `ReplaceIoChunkHashWithIoHash` — same versions the
  live game containers use; 2 chunks (ExportBundleData + ContainerHeader).
- Local bypass state: none found (`winmm.dll`/`.asi`/`PD3AllowMods.log` absent; `dwmapi2.dll` is the
  UE4SS injection proxy; `AllowModsMod.dll` failed its patch on 2026-09-26).
- Community guidance (ModWorkshop install template + PD3 Logic Mod Loader page): unsigned containers
  fatal with `Pak master signature table check failed` unless a bypass is active (`-fileopenlog` per
  that page, or UE4SS + AllowModsMod, or PD3AllowMods/SigBypassMod).
- Boot result: **pending user launch.**

## Reference mods (Phase 0b)

- PAINDAY - More Spawns: pak downloaded (`work\reference_mods\PAINDAY_MoreSpawns.pak`, 3,175,529 B);
  GitHub source `github.com/TarekLP/PAINDAY` is a cooked **legacy** tree (`*.uasset` + `*.uexp`)
  overriding per-heist `DA_AssaultManagerSettings_*` plus negotiation/fire-data assets. For the
  default `Gameplay/AI/Assault/DA_AssaultManagerSettings` their repo ships **only the `.uexp`**
  (their `.uasset` assumed byte-identical) — we will ship both files from the live-era extract.
- Both ModWorkshop reference mods are tagged **UE4.27** ("will not work on UE5.5"); their paks do not
  load on the current build, but the editing pattern (per-asset legacy override in `~mods`) is
  exactly our pipeline.
- Specials Only: description confirms same override approach (SWAT squad replacement); 5 files,
  not downloaded (API exposed no single `download` object). Lower priority.
- Tools: UAssetGUI **v1.1.0** downloaded to `work\tools\UAssetGUI.exe` (supports UE 5.4+ tagged
  properties; bundled retoc — check whether it extracts the post-update live containers, which
  standalone retoc 0.1.5 cannot).

## Phase 1 minimal override (built 2026-09-26)

- Edits (via `tools/phase1-edit.mjs` on UAssetAPI JSON): top-level `MaxTotalAISpawnCount` 200→**213**
  (marker), difficulty 0 / tier 0.0 first squad rewritten to a single `DA_Special_Dozer` pawn at
  weight 1.0 and all other tier-0 squads weight 0.0.
- Repacked with `retoc to-zen` (`.utoc` 487 B, `.ucas` 6672 B, `.pak` stub 347 B) and installed to
  `~mods` (replaces the Phase 0a no-op test container).
- Probe extended to read `Settings.MaxTotalAISpawnCount` / `Settings.EndFadePhaseMinAliveAISpawnCount`.
- Live verification pending.

## Phase 1 verified live + spawn-director verdict (2026-09-27 session)

- Live `Settings.MaxTotalAISpawnCount=213` → pak override loaded. Full pipeline proven:
  legacy asset (pre-update `Output\`) → UAssetAPI edit → `retoc to-zen` → `~mods` triple → game.
- Assault kickstart (`SetLevelProgression(1.0)` + `SetAssaultActive(true)` + `StartEndlessAssault(true)`)
  flips `IsAssaultActive=true` but **0 enemy pawns** spawn, twice. Range map has
  `bEnableNavigationSystem: false` and no assault spawn points → director has nowhere to spawn.
  Pak spawn-data route is a dead end for the training area (remains valid for real heists).
- Range is fixed to `Difficulty=0` (Normal) via `BP_HeistGameState_C`; `GetDifficultyIdx=0`.
- Marker pak reverted from `~mods` (pipeline documented; no longer needed for the range).
- Cheat spawn lead: `NPCDebugPanel` confirmed as a class (`SBZNPCDebugPanel` in usmap), no
  `NPCDebug*` assets shipped. Prior live test (02-26) had it null and spawn no-op'd; dual smoke test
  (F8 direct `SpawnActor` vs F10 cheat+panel) deployed 2026-09-27.

## Spawn engine decision (2026-09-27 round 4)

- **Direct spawn works**: `KismetMathLibrary:MakeVector/MakeRotator/MakeTransform` +
  `GameplayStatics:BeginDeferredActorSpawnFromClass`/`FinishSpawningActor` spawned
  `CH_Dozer_C` into `NewShootingRange:PersistentLevel`; follow-up dump counted `CH_Dozer_C x1`.
  (Classes must be resolved via `StaticFindObject("/Script/Engine....")`; Lua globals for script
  classes do not exist.)
- **Cheat manager dead end confirmed twice**: with `pc.CheatManager` and `cheat.NPCDebugPanel`
  both constructed and assignments verified, `SpawnAllAITypes(5,900,0,0,0,None)` still spawns
  nothing.
- Chosen engine: direct `SpawnActor`. TrainingProbe disabled (F8 key conflict); TrainingSpawner
  deployed (17-class frozen arc, auto-spawn on entry, F8/F9, F10 difficulty probe). Unit tests:
  `lua/TrainingSpawner/tests/freeze_logic_test.lua` ALL PASS under fengari.

## Round 6 crash + round 7 fixes (2026-09-27)

- Full roster spawn: 14/17 `spawned` + `frozen` cleanly in the range (all SWAT variants, Shield,
  Sniper, Taser, Grenadier, Dozer, Cloaker, Tower). Crash occurred immediately after
  `spawned Moon` — the `BP_Moon_Gun_C` drone. **Moon removed from the roster permanently** (user
  decision, 2026-09-27).
- Freeze hardening: `SetAIEnabled` result scripts pcall-checked; unsupported controllers log
  `freeze unsupported for <name>` once (round 6 emitted a false `frozen Moon (auto)` on failure).
- `F7` added: single-class cycler for crash bisection (spawns one roster class per press, 10 m ahead).
- `TrainingSpawner` v0.2.0; roster 16; fengari tests ALL PASS (roster/layout updated to 16, 8+8).
- Range difficulty live-switch confirmed: `F10` `SetDifficulty(1)` → `GetDifficultyIdx` 0→1.

## Round 7 kill crash + round 8 discrimination (2026-09-27)

- Round 7: 15/15 loadable classes spawned + frozen cleanly. Crash occurred on the **killing hit**
  (KillStatsMod logged the headshot on `CH_SWAT_SMG_C`); log ends at the death event, no Lua error.
  Two hypotheses: (1) freeze+death interaction (`SetAIEnabled(false)` then death cleanup),
  (2) death processing for pawns spawned outside the game's spawn-manager registration.
- `CH_SecurityGuard_C` not loadable in the range (8 full load-variant attempts failed); removed from
  the roster (user decision).
- TrainingSpawner v0.3.0: roster 15; `F6` = unfrozen diagnostic cycler, `F7` = frozen cycler
  (spawned entries carry `noFreeze` and the tick skips them); fengari tests ALL PASS.

## Round 8-9: damage/death crashes + isolation (2026-09-27)

- Both crash stacks are UE4SS **Lua member/property lookups on invalid objects** (crash A:
  `handle_unreal_property_value` → `GetFunctionByNameInChain` → invalid class; crash B:
  `UScriptStruct::handle_unreal_property_value` → `auto_construct_object` → `IsA(0xffffffffffffffff)`),
  and both fire on damage/kill of directly-spawned pawns. Spawn/freeze themselves never crash.
- KillStatsMod has 5 native hooks in exactly that path
  (`SBZCharacter:HandleTakePointDamage`, `Multicast_OnKill`, `SBZPlayerState:Multicast_OnKill`,
  `SBZDamageFeedBridge:OnGameDamageEvent`); WeaponStatsViewer hooks damage too.
- TrainingSpawner v0.4.0 hardening: UE4SS global `IsValid` for all liveness checks, per-tick
  pruning of dead actors before property reads, 60 s `status live/frozen/pending` line.
- Round-9 isolation test: KillStatsMod + WeaponStatsViewer temporarily disabled
  (`enabled.txt` renamed; no files inside those mods touched).

## Round 9 result + culprit narrowing (2026-09-27)

- **Round 9 (KillStatsMod + WeaponStatsViewer OFF, TrainingSpawner only): killing a frozen
  directly-spawned enemy does NOT crash.** Spawn, freeze, death, cleanup all stable → the crash is
  an interaction with the damage/kill hook callbacks of those two mods.
- KillStatsMod kill path (`detect.lua ProcessKill`) reads victim fields `KillInstigatorController`,
  `KillContextData` (struct), `LocallyDamagedByPlayer`, `DefeatState` — the struct read matches
  crash B's stack exactly (struct wrapper from freed memory). Crash A (invalid class member lookup)
  fits the same family inside the hit callback.
- Round 10 isolation: 10b = WSV ON / KillStats OFF; 10a = KillStats ON / WSV OFF.

## Round 10 isolation: culprit = KillStatsMod (2026-09-27)

- 10b (WSV ON / KillStats OFF): killing a frozen direct-spawned enemy → **no crash**.
- 10a (KillStats ON / WSV OFF): same kill → **crash**. Culprit is KillStatsMod's kill handling.
- Mechanism (from `KillStatsMod\scripts\detect.lua`): `Multicast_OnKill` schedules `ProcessKill(Victim)`
  120 ms later, which reads `KillInstigatorController`, `KillContextData` (struct), `EquippableData`,
  `DefeatState` off the victim. Lua `pcall` cannot catch native access violations, so a freed/
  partially-initialized victim crashes inside UE4SS struct-property handling (matches crash B stack).
- Open question for round 11: frozen-only or any direct-spawn death? Test = kill an F6 (unfrozen)
  pawn with KillStatsMod ON.
- Both mods restored to enabled after the isolation runs.

## v0.5.0 test-rig redesign (2026-09-27)

- User verdict: KillStatsMod incompatibility accepted (document it); no auto-spawn; single-enemy
  cycler + distance cycler for shots-to-kill testing at falloff breakpoints.
- Distance source: live equipped-weapon read
  `PlayerController.Pawn.CurrentEquippableConfig.EquippableData.FireData` (fallback
  `.CurrentEquippable.EquippableConfig...`) -> `DamageDistanceArray` +
  `CriticalDamageMultiplierDistanceArray` (cm -> m, dedupe/sort). Same numbers the weapon bench
  renders via its `stats-range` rows (`P9317/payday-weapon-bench` fork, app.js:3081/3175
  `shotsToKillAtDistances`). Config override in `scripts/user_config.lua`.
- Keys: F5 clear; F6/F7 prev/next enemy; F8 spawn selected (replaces subject, faces player, frozen);
  Shift+F8 full roster arc; F9/Shift+F9 distance cycle; Ctrl+F9 / Ctrl+Shift+F9 +/-1 m nudge;
  F10 difficulty probe.
- `weapon_ranges.lua` vendors a minimal TArray<struct> reader (1-based indexing per pd3lib
  `StructArray`), no pd3lib dependency. `user_config.lua` is user-editable.
- fengari tests ALL PASS (cyclers, cm->m union/dedupe/sort, config merge, facing yaw, nudge clamps).

## v0.5.5 chat notices (2026-09-28)

- In-game chat printing validated: `SBZChatInGame:SendChatMessageToServer(FSBZPlayerChatEvent)`
  with `{PlayerState, Message}` works solo (reference: SoloTrueConnoseuir; struct verified in
  `Starbreeze.lua`). Rich-text tags come from `Content/UI/Assets/Text/DT_ChatRichTextStyles`.
- Promoted to pd3lib as `game.chat` (`Available/Get/Send/SendFmt`) — pd3lib v2.2.0 (`bc20619`),
  README + knowledge-base + API docs regenerated with `emmylua_doc_cli`; v2.2.1 (`49b7514`) fixed
  the missing `pd3.chat` top-level alias (pd3lib has an explicit alias list per game module —
  new modules must be added there too).
- TrainingSpawner v0.5.5: enemy/distance/difficulty cycles + distance nudge announce
  `[TrainingSpawner] …` lines (`<Object>`/`<Blue>`/`<Hud_01>` accents), config `chatNotice`
  (default true). Verified in game (all lines render, readable, no spam on F8/F5).

## v0.5.6 level-transition fixes (2026-09-28)

- Symptom: after leaving the range and starting another level (or restarting it), cycling still
  logged but queued spawns silently vanished (`pending=0` at the next status, no `spawned`/`spawn
  FAIL`) and chat notices stopped. Root causes from `UE4SS.log` (12:31-12:33 and 12:53-12:55):
  - `pd3.classes.Loader` handed out class UObjects resolved in the previous level; once those
    packages unloaded they failed `Safe.IsValid`, and `spawnOne` dropped the item with no log.
    `Loader:Get` now invalidates stale states so callers re-enqueue, and `Loader:Reset()` clears
    resolved/queued/gave-up paths for a level change.
  - `pd3.world` cached the first valid PlayerController; right after level init that could be a
    pawnless transition/menu controller (nil `Pawn`/`PlayerState`) and the cache only cleared
    when it died - F8 logged `no player pawn` and weapon reads fell back to the config list while
    the player was already walking (First World Bank/ONE, 12:53:38-12:54:12). `GetPlayerController`
    now prefers a local controller with a live pawn, then any local, then a pawned one, and
    re-resolves a pawnless cache.
  - The mod had no lifecycle handling: `pd3.lifecycle` OnLevelInit/OnLevelRestart/
    OnReturnToMainMenu now run a pure-Lua reset (class loader, pending/spawn context, AI/World/
    Chat caches, chat-warning latch, distance refresh flag). Hook context stays engine-free.
  - Failure paths made visible: drop logs for gave-up/invalid classes, `(controllers=N)` on
    `no player pawn`, per-distinct-reason chat warnings, `loads=` in status lines.
- Verified in game (hot reload in range -> return to menu -> First World Bank/ONE): spawn,
  freeze, chat and live distance readout all work after the transition; second range entry also
  confirmed by the user.
- pd3lib v2.2.2 (world/classes/chat `Reset`, Loader stale invalidation, controller preference);
  TrainingSpawner 0.5.6.

## Probe (Phase 0c)

- `TrainingProbe` mod deployed (F6 dump: assault managers, Settings, enemy pawns, mission state,
  difficulty). Pending in-game run in `NewShootingRange`.

## Difficulty API evidence (`shared\types\Starbreeze.lua`)

- `ASBZMissionState:GetDifficulty()` / `GetDifficultyIdx()`, field `Difficulty: ESBZDifficulty` (L5187, L5355).
- `USBZGameInstance:SetDifficulty(InDifficulty)` (L28736) — runtime setter candidate.
- `USBZCheatManager:SetDifficulty` exists but the cheat-manager route is a proven dead end.
- `USBZGameStateMachine:GetMatchmakingDifficultyIdx()` (L28948).
