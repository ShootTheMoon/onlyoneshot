# 004. Performance Audit and Sound Groundwork

Date: 2026-08-25. Status: measured and deployed. No gameplay script was modified.

## What the level actually contains

`level.browse` over the live project, 5,118 instances.

| Location | Instances | Note |
|---|---|---|
| `Workspace/JSN_Sangok` | 3,396 | the only live map |
| `Workspace` (lobby, viewmodels, markers) | ~89 | |
| `ServerStorage/Hwaseong Collision` | 992 | parked, not rendered |
| `ServerStorage/Hwaseong Place` | 339 | parked |
| `ServerStorage/Gyeongbokgung Place` | 253 | parked |
| scripts | 30 | 11 LocalScript, 10 ModuleScript, 9 Script |

Inside `JSN_Sangok`: 1,669 `JSN_COL_*` invisible collision slabs, 1,096 `JSN_Pine_*`,
517 `JSN_Und_*` undergrowth, 67 rocks, 16 `STA_TER_*` terrain tiles.

Property hygiene is already correct. Every part is anchored; the 1,669 collision slabs
are `CastShadow=false`, `CanTouch=false`; only 292 objects cast shadows.

## Frame rate: what was measured

Baseline before this session was ~28 fps in the lobby.

1. **Moving Hwaseong to ServerStorage worked.** Average **44.0 fps**, steady state 46.
   Workspace parts 4,666 to 3,485. This is the one change that moved anything.

2. **Three A/B tests, all negative.** Noise floor is about +-2 fps, established with a
   control phase that changed nothing and still drifted -1.6.

   | Test | Delta |
   |---|---|
   | hide all 1,613 vegetation MeshParts | -2.6 fps |
   | `Lighting.SunCastShadow = false` | -1.6 fps |
   | disable all 10 client LocalScripts | +1.5 fps (second run: -2.1) |
   | control, nothing changed | -1.6 fps |

3. **Conclusion.** The remaining ~21 ms is not draw calls, not shadows, and not our Lua.
   The only lever that has ever moved this game's frame rate is **Workspace instance
   count** - 25% fewer parts gave 57% more fps. Visibility did not matter: hiding the
   vegetation changed nothing, but moving Hwaseong out of Workspace changed everything.

   Next optimization should therefore reduce *count*, not visual quality. The remaining
   blocks are `JSN_COL` 1,669 (a coarser quadtree would roughly halve it, at the cost of
   ground fidelity - this has to be redone in Blender), `JSN_Pine` 1,096, `JSN_Und` 517.

## A/B methodology, learned the hard way

- Do not measure immediately after bulk property edits. The mutation hitch lands inside
  the sample window. One 9-second window contained 5.7 seconds of complete stall and
  read as "rocks and shadows cost 31 fps". Settle ~4 s, and restore between phases.
- Print wall-clock elapsed alongside accumulated `dt`. When they diverge, the client was
  stalled and the fps number is meaningless.
- Always include a control phase. Without knowing the noise floor, +-2 fps reads as a win.

## Load-time noise

One minute of play appends ~13.5 MB to `Sandbox.log`, almost all of it during load:
57,191 `LogLuaBasePart: Display [UpdateCollisionEnabled]` lines and 9,798
`A null object was passed as a world context object` warnings in about 0.1 s. Steady
state is quiet, so this costs load time, not frame rate. Two stale log backups in
`%LOCALAPPDATA%\Sandbox\Saved\Logs` total about 713 MB.

## Sound: what the engine supports

Determined empirically by writing instances into the level and reading back how Studio
re-serialized them.

- `Sound` and `SoundGroup` are real classes. `Sound` carries `SoundId`, `Volume`,
  `Looped`, `PlaybackSpeed`, `TimePosition`, `RollOffMinDistance` (default 10),
  `RollOffMaxDistance` (default 5000), `RollOffMode`, `LoopRegion`, `PlaybackRegion`,
  `PlayOnRemove`, `SoundGroup`. `SoundGroup` carries only `Volume`.
- **`SoundId` format is `ovdrassetid://<contentId>`**, the same scheme as `MeshId`,
  `TextureId`, and `AnimationId`.
- There is **no `SoundService`** in this DataModel. A `Sound` needs a `BasePart` parent
  to be positional; parented anywhere else it plays 2D.
- The audio mixer is XAudio2 at 48 kHz with **32 concurrent voices maximum**. The engine
  logs missing default submix assets at startup and falls back; harmless but permanent.
- `level.apply` validates every property. Omit one and it answers `success:false` with a
  warning per missing field and substitutes the default.

## Sound layer deployed

Nothing plays yet - every catalog slot is empty by design. Filling in asset ids is the
only remaining step.

| Instance | Location | Role |
|---|---|---|
| `SoundDB` | ReplicatedStorage | 35-slot catalog plus the CombatEvent phase mapping |
| `SoundEvent` | ReplicatedStorage | server to client play requests |
| `SG_SFX` / `SG_UI` / `SG_Music` | ReplicatedStorage | volume groups |
| `SoundClient` | StarterPlayerScripts | pooled playback, voice budget, distance cull |
| `SoundServer` | ServerScriptService | `_G.SfxAll` / `_G.SfxTo` / `_G.SfxNear` |

Design points:

- **No gameplay script was edited.** `SoundClient` subscribes to the existing
  `CombatEvent` and maps `payload.phase` to a sound name through `SoundDB.PHASE_TO_SOUND`.
  Adding a sound to an existing gameplay moment is a one-line table entry.
- **Voice budget 24**, below the engine's 32, so we choose what to drop rather than
  letting the mixer choose. Per-name cooldowns keep footsteps and multi-hits from
  eating the budget.
- **`max == 0` in the catalog means 2D**, anything else is positional and gets culled
  before a voice is spent if it is out of range.
- Sound instances are pooled with an `Ended` handler plus a 12 s timeout fallback, so a
  sound that fails to load cannot drain the pool and silence the game.

Verified in play mode: `SoundServer ready`, `SoundClient ready`, catalog reports
`35칸 중 0칸`, and `boundary_warn` was requested by live gameplay - the bridge fires.
Zero Lua errors.

## To turn sound on

1. Pick audio in the Studio asset store and note each `contentId`.
2. Fill `id = "ovdrassetid://<contentId>"` in `Lua/SoundDB.lua`.
3. Push it to the level and reload:
   `Set-OvdrScriptSource -Name 'SoundDB' -File ...\SoundDB.lua; Publish-OvdrLevel`
   (helpers in `gyeongbokgung\ovdr_script.ps1`).
4. Play. The client prints how many slots are filled and which requested slots are empty.

## Not done, needs a decision

- The 1,584 parked instances in ServerStorage are still serialized into the 29.5 MB level
  file and are packaged on publish. Deleting them would shrink save time and the upload,
  but they are the only copy in this project. Left alone.
- Reducing `JSN_COL` via a coarser quadtree has to happen in Blender, which was not
  running this session.
