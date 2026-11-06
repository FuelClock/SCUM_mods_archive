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
| CleanCarWindows | Pak | Dirt-free vehicle windows (current approach) |
| CleanPlaneWindows | Pak | Dirt-free plane windows (current approach) |
| CarMasksBlack | Pak | Black vehicle glass masks |
| PlaneGlassBlack | Pak | Black plane glass (superseded by CleanPlaneWindows) |
| PlaneGlassWhite | Pak | White/frosted plane glass (superseded by CleanPlaneWindows) |
| NoReticles | Pak | Removes scope/weapon reticles |
| SpekralScopeNoReticle | Pak | No-reticle variant for the Spekral scope |
| FogKiller | UE4SS Lua | Fog removal (Ctrl+Shift+F keybind taken by this mod) |
| SkipCutscenes | UE4SS Lua | Skips intro cutscenes |
| QuestCompleteHotkey | UE4SS Lua | Quest-complete hotkey |
| Lockpicking | Pak source | Lockpicking variants (full-angle build; loose asset tree, never pakged) |
| WeaponPlacement | Pak source | Weapon placement variant (loose asset tree) |
| PowerplantInteriorsRestore | Pak source | Interiors restore. **v2 (3 GB) exceeds GitHub's 100 MB file limit, stored locally on /opt only.** |

Older versions of every mod are kept locally on `/opt` (`/opt/scum-<mod>-v<N>.zip`).
