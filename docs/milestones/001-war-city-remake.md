# 001. War-Ruined City Remake

## Status

Completed and saved.

## Goal

Replace the previous Berlin map and all gameplay scripts with a clean, map-only war-ruined city while keeping the original world scale and spawn area.

## Done

- Removed the previous Workspace map, character, weapon, legacy ground, and spawn.
- Removed all Script, LocalScript, and ModuleScript instances.
- Removed the old combat HUD and rifle template.
- Built a 20,000 by 20,000 cm ruined city around the original coordinate system.
- Added a central crossroad, two bypass alleys, fourteen enterable ruined building shells, a destroyed plaza, checkpoint, cover, rubble, and industrial landmarks.
- Added a safe spawn at approximately `(2000, 100, 3000)`.
- Imported a damaged concrete wall and two wooden barricade accent assets.
- Adjusted Lighting and Atmosphere for a dusty late-afternoon war-zone mood.
- Replaced nested transform Models with Folders after runtime mobility testing.
- Completed a clean one-player runtime check with no Lua or mobility errors.

## High-Quality Berlin Asset Upgrade

- Recovered the original Berlin map's mesh, texture, and scale data from the pre-rebuild snapshot without discarding the remade layout.
- Added `Workspace/HighQualityBerlinAssets` with fifteen visible architectural MeshParts, Brandenburg Gate, and two T-34 wrecks.
- Reused the original Berlin church, VEB factory, Plattenbau, Altbau, East Housing, school, Palast, Reichstag, Brandenburg Gate, and T-34 resources.
- Converted the 446 procedural building-shell parts to invisible collision blockout, preserving routes and openings while removing the low-quality visible block architecture.
- Verified the upgraded world in one-player Play mode with no Lua, asset-loading, or mobility attachment errors.

## Current Studio Structure

- `Workspace/RemadeWarCity`: generated city geometry, organized with Folders.
- `Workspace/WarCitySpawn`: the only spawn point.
- `Workspace/Accent_DamagedConcreteWall`: imported static accent.
- `Workspace/Accent_WoodBarricade_A`: imported static accent.
- `Workspace/Accent_WoodBarricade_B`: imported static accent.
- `Workspace/HighQualityBerlinAssets`: visible Berlin architecture, landmark, and vehicle meshes.
- `ServerScriptService`: intentionally empty.
- `StarterGui`: intentionally empty.
- `ReplicatedStorage`: legacy combat modules and weapon template removed.

## Reusable Procedural Recipes

- `.overdare/procedural/war_ruined_city_remake/main.lua`: deterministic city generator. Final parameters use `OffsetX=0` and `Seed=202603`.
- `.overdare/procedural/war_city_asset_placement/main.lua`: positions the three imported accents.
- `.overdare/procedural/legacy_city_cleanup/main.lua`: legacy Workspace cleanup recipe; do not rerun casually because it deletes unprotected Workspace children.
- `.overdare/procedural/high_quality_berlin_overlay/main.lua`: regenerates and places the recovered Berlin meshes; final parameter is `OffsetX=0`.
- `.overdare/procedural/hide_ruined_city_blockout/main.lua`: keeps procedural buildings as invisible collision blockout.

## Acceptance Criteria Met

- The previous map and all scripts are absent.
- The new city occupies the original map area.
- The foundation and major routes have collision.
- A valid enabled spawn exists in the safe plaza.
- Play mode starts without Lua errors or mobility attachment warnings.

## Next Possible Milestone

Walk through the map in Studio and choose any visual or route adjustments. Gameplay systems should be planned and rebuilt separately only if requested.

