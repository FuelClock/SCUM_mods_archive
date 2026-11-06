# SCUM Mods Archive

One folder per mod. Each folder holds the mod itself (the `.pak` for pak mods, the
`Mods/<Name>/` UE4SS Lua tree for script mods) plus its `SCUM/` source tree -
no zips.

Pak install: drop the `_P.pak` into `SCUM/Content/Paks/~mods/` (the trailing `_P`
is the UE patch-priority suffix and must stay, it makes the pak override vanilla
files). Lua install: copy the `Mods/<Name>/` folder into
`SCUM/Binaries/Win64/ue4ss/Mods/` and enable it in `mods.txt`.

| Mod | Kind | Notes |
|---|---|---|
| FuelClockLoader | Pak | Personal pak mod loader (fork of Nexus "Unofficial Editor Mod Loader" Beta 0.1, config regenerated for the current build). Loader-convention mods drop BP actors under `Content/MOD/<MapName>/`. |
| CleanCarWindows | Pak | Dirt-free vehicle windows (current approach) |
| CleanPlaneWindows | Pak | Dirt-free plane windows (current approach) |
| NoReticles | Pak | Removes scope/weapon reticles |
| SpekralScopeNoReticle | Pak | No-reticle variant for the Spekral scope |
| FogKiller | UE4SS Lua | Fog removal (Ctrl+Shift+F keybind taken by this mod) |
| QuestCompleteHotkey | UE4SS Lua | Quest-complete hotkey |
| Lockpicking | Pak source | Lockpicking variants (full-angle build; loose asset tree, never pakged) |
| WeaponPlacement | Pak source | Weapon placement variant (loose asset tree) |

Older versions of every mod are kept locally on `/opt` (`/opt/scum-<mod>-v<N>.zip`).
