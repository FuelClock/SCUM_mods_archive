# FuelClockLoader

Personal pak mod loader for SCUM: a fork of **Troopermanaic**'s
[Unofficial Editor Mod Loader](https://www.nexusmods.com/scum/mods/61)
(Beta 0.1), updated with these changes:

- `SCUM/Config/DefaultEngine.ini` regenerated from the **current client build**
  (the original shipped a June-2026 config whose stale redirects caused vehicle
  physics explosions on game entry: entering a vehicle flung the player and
  the vehicle across the map).
- The config's `GameInstanceClass` points at the loader's own
  `BP_ConZGameInstance_Child`, which scans `/Game/MOD/<MapName>` on the Asset
  Registry and auto-spawns every actor-class asset found there (per map:
  `MainMenu`, `CharacterCreationMenu`, `The_Island`).
- Discord link/button neutralized (URL points to a dead localhost address).

## Install

Drop `SCUM_FuelClockLoader_P.pak` into `SCUM/Content/Paks/~mods/`.

Per the original loader's requirements, add these Steam launch options (or to
the executable shortcut / server batch file):

    -fileopenlog -nobattleye

Remove the launch options when playing multiplayer servers that don't need mods.

## Writing loader-convention mods

Drop a cooked Blueprint actor asset under `SCUM/Content/MOD/<MapName>/` in any
`_P` pak. The loader spawns it on that map automatically (menu maps get their
`MainMenu`/`CharacterCreationMenu` paths, the game world uses `The_Island`).

## Maintenance

If a SCUM update changes `DefaultEngine.ini`, regenerate the ini from the
current client's `pakchunk0` and swap it into this pak (keep only the
`GameInstanceClass` override; pak file-version 9).

## Upstream status

The original loader's author has marked it pending removal from Nexus (they're
building a new editor with its own loading system) - this fork exists so the
convention keeps working locally regardless.
