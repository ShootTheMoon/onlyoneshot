# Project Documentation

## Current World

The live map is `Workspace/JSN_Sangok` (Sangok, 260 x 260 m), 3,396 instances, plus the
lobby, viewmodels, and a Changdeokgung arrival marker. Gameplay and first-person control
scripts in Studio are active and should be treated as implemented reality.

Gyeongbokgung and Suwon Hwaseong are **parked in `ServerStorage`**, not in the world -
1,584 instances that are neither rendered nor referenced by any script. Hwaseong was moved
there on 2026-08-25 and that single change took the lobby from ~28 fps to 44. Do not
describe them as part of the current world.

A sound layer is deployed but silent: every catalog slot in `Lua/SoundDB.lua` is empty
until asset ids are filled in. See milestone 004.

## Active Records

- `docs/milestones/001-war-city-remake.md` (superseded map, kept for the procedural recipes)
- `docs/milestones/002-gyeongbokgung-import.md`
- `docs/milestones/003-hwaseong-v23-import.md`
- `docs/milestones/004-perf-and-sound.md`
