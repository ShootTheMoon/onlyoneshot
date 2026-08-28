# 002. Gyeongbokgung Import Completion

## Status

Completed, saved, and visually accepted by the user.

## Goal

Finish the Blender-to-OVERDARE Gyeongbokgung import by correcting mesh scale, restoring missing architecture, enabling collision, and fixing stair direction without disturbing the confirmed palace layout.

## Confirmed Coordinate Rules

- Blender 1 meter maps to 100 OVERDARE centimeters.
- Blender `(x, y, z)` maps to OVERDARE `(X, Z, Y)`.
- North-facing Blender `+Y` maps to OVERDARE `-Z`; the existing Z sign is correct.
- Palace scale is `0.6` around the fixed floor height `Y=5000`.
- Mesh positions use their world bounding-box centers.

## Done

- Kept the confirmed south-to-north order: Geunjeongmun at positive Z, Geunjeongjeon near Z=0, and Sajeongjeon at negative Z.
- Corrected 160 oversized MeshParts whose bounding dimensions had been applied twice during delayed asset loading.
- Preserved the 16 Sajeongjeon MeshParts that were already at the correct scale.
- Restored 29 missing south and north corridor MeshParts from the imported static-mesh assets.
- Completed the palace model at 247 direct children: 205 MeshParts, 41 native Parts, and `GBG_Platform`.
- Verified all 246 manifest-backed palace elements with zero missing names, position errors, size errors, and UnitExtent errors.
- Moved `Workspace/WarCitySpawn` to `(0, 5050, 5400)` facing north so the palace is visible immediately.
- Enabled `CanCollide=true` and `CollisionProfile=BlockAll` on all 205 palace MeshParts.
- Rotated the nine `*STAIR*` MeshParts by 180 degrees around Y while preserving their positions, sizes, and collision.
- Confirmed in Play mode that the palace scale, restored walls and corridors, collision, and stair directions are correct.
- Final Play log contains no Lua runtime errors.

## Reusable Procedural Recipes

- `.overdare/procedural/gyeongbokgung-scale-fix/main.lua`: normalizes palace MeshPart sizes to manifest `size_cm * 0.6`.
- `.overdare/procedural/gyeongbokgung-missing-corridors/main.lua`: restores the 29 missing corridor MeshParts and supports two-step size refresh modes.
- `.overdare/procedural/gyeongbokgung-collision-fix/main.lua`: normalizes all palace MeshParts to `BlockAll` collision.

## External Import Workflow Fixes

- `C:/Users/HSP/Desktop/blender/gyeongbokgung/ovdr_place.ps1`
  - Uses initial MeshPart `Size=100*Scale` per axis so delayed MeshId loading does not multiply bounding dimensions twice.
  - Enables collision by default for palace MeshParts.
  - Rotates `*STAIR*` meshes by 180 degrees around Y.
  - Validates XYZ size, circular yaw difference, and collision state.
- `C:/Users/HSP/Desktop/blender/gyeongbokgung/ovdr_level.ps1`
  - Documents the placeholder UnitExtent and delayed MeshId scaling behavior.

## Acceptance Criteria Met

- Palace composition is complete with no missing manifest elements.
- Buildings and corridors appear at the intended 0.6 scale.
- The spawn provides an immediate view of Geunjeongmun.
- Walls, columns, floors, stairs, and other palace structures block the player.
- All nine stairs face the correct direction and can be used.
- Play mode starts without Lua errors.

## Next Possible Milestone

Continue with gameplay or visual polish only if requested. Do not rerun the old placement workflow without the corrected PowerShell scripts.
