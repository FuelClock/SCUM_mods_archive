# SCUM Mods Archive

Latest `.pak` file of every pak-based SCUM mod, one folder per mod. Drop the `_P.pak`
into `SCUM/Content/Paks/~mods/` (the trailing `_P` is the UE patch-priority suffix and
must stay — it makes the pak override vanilla files).

| Mod | Pak | Notes |
|---|---|---|
| CleanCarWindows | CleanCarWindows_P.pak | Dirt-free vehicle windows (current approach) |
| CleanPlaneWindows | CleanPlaneWindows_P.pak | Dirt-free plane windows (current approach) |
| CarMasksBlack | CarGlassMasksBlack_P.pak | Black vehicle glass masks |
| PlaneGlassBlack | PlaneGlassBlack_P.pak | Black plane glass (superseded by CleanPlaneWindows) |
| PlaneGlassWhite | PlaneGlassWhite_P.pak | White/frosted plane glass (superseded by CleanPlaneWindows) |
| NoReticles | NoReticles_P.pak | Removes scope/weapon reticles |
| SpekralScopeNoReticle | SpektralScopeNoReticle_P.pak | No-reticle variant for the Spekral scope |

Not hosted here (no pak file exists — kept locally on `/opt` only):

- **UE4SS Lua mods** (source zips): FogKiller v33, GlassClear v36 (RETIRED, superseded
  by the pak route), GlassDump v4, SightDotProbe v5, SkipCutscenes v6, QuestCompleteHotkey v1
- **Loose-asset source mods** (SCUM/Content trees, not pakged): Lockpicking fullangle,
  WeaponPlacement all, PowerplantInteriorsRestore v1
- **Too large for GitHub** (100 MB file limit): PowerplantInteriorsRestore v2 (3 GB),
  oldscum_trimmed (41 GB)
