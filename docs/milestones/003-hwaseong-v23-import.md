# 003. Hwaseong v23 Import

## Goal

Import the Suwon Hwaseong v23 Blender scene into the `onlyoneshot` world without breaking the FBX mesh offsets, and provide walkable terrain collision.

## Done

- Imported 150 MODEL assets in one bulk operation under `Workspace/Hwaseong Place`.
- Preserved 189 MeshParts and their published mesh/texture data by reimporting the 150 MODEL assets with their original Model-to-MeshPart hierarchy.
- Replaced the outdated ground with HGD MODEL `ovdrassetid://42601100`, mesh `ovdrassetid://42600300`, and texture `ovdrassetid://42600200`.
- Rebuilt the final visual placement at quarter scale (`0.25`) with a 180-degree world-Y conversion while preserving each imported MODEL's internal FBX offsets.
- Final visual bounds are X `56750..66050` and Z `-4800..4800`; the HGD ground is `9300 x 397.272 x 9600 cm` at `(61400, -98.558, 0)`.
- Compared all 189 visual MeshParts with the placement manifests. 183 matched within 0.1 cm; the remaining six differed by no more than 2.44 cm.
- Generated `Workspace/Hwaseong Collision` with 992 transparent DEM collision slabs.
- Verified all 992 slabs for count, name, position, rotation, size, collision profile, and transparency with zero mismatches.
- Completed a one-player walking test. The creator confirmed that terrain walking and building assembly look normal.
- Restored the JSN red and blue team spawns after the temporary Hwaseong test.
- Restored all 189 MeshParts' published TextureIds and verified that no texture reference is empty.
- Kept the HGD ground texture `ovdrassetid://42600200` and restored its required grass tint to RGB `(112, 142, 82)`; the creator confirmed the ground is green and visually correct.
- Scaled `Workspace/Hwaseong Collision` to the same final footprint: X approximately `56742..66060`, Z approximately `-4808..4810`.

## Acceptance Criteria

- `Workspace/Hwaseong Place` has 150 direct MODEL children and 189 descendant MeshParts.
- `Workspace/Hwaseong Collision` has exactly 992 transparent, anchored, `BlockAll` Parts.
- The visual model uses quarter scale and preserves the published MODEL hierarchy and internal FBX offsets.
- The HGD ground texture renders green with RGB tint `(112, 142, 82)`.
- The player can walk on the imported terrain without falling through it.
- Hanok and wall assets appear assembled during play.

## Important Implementation Notes

- Do not reconstruct imported geometry from bare MeshParts or overwrite it from simplified per-object transforms; FBX offsets must be preserved.
- In this Studio build, setting `Model.WorldPivot` changes pivot metadata but does not move descendants. The final correction is therefore applied as one identical rigid world-space transform to each existing MeshPart CFrame.
- Visual rebuild recipe: `.overdare/procedural/hwaseong-v23-placement/main.lua`
- MODEL hierarchy reimport recipe: `.overdare/procedural/hwaseong-place-reimport-models/main.lua`
- Published texture restore and final bounds verifier: `.overdare/procedural/hwaseong-place-restore-textures/main.lua`
- Collision recipe: `.overdare/procedural/hwaseong-v23-collision/main.lua`
- Collision verifier: `.overdare/tools/verify_hwaseong_collision.ps1`

## Remaining

- No remaining import work.
- Publishing was intentionally not performed.

## Out of Scope

- Re-publishing JAM, SBK, or HPR assets.
- Changing gameplay, team logic, or permanent spawn positions.
- Publishing the world.
