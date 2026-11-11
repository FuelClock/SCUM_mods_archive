NoReticles placeholder
NoReticles placeholderOne folder per mod. Each folder holds the mod itself (the `.pak` for pak mods, the
NoReticles placeholder`Mods/<Name>/` UE4SS Lua tree for script mods) plus its `SCUM/` source tree -
NoReticles placeholderno zips.
NoReticles placeholder
NoReticles placeholderPak install: drop the `_P.pak` into `SCUM/Content/Paks/~mods/` (the trailing `_P`
NoReticles placeholderis the UE patch-priority suffix and must stay, it makes the pak override vanilla
NoReticles placeholderfiles). Lua install: copy the `Mods/<Name>/` folder into
NoReticles placeholder`SCUM/Binaries/Win64/ue4ss/Mods/` and enable it in `mods.txt`.
NoReticles placeholder
NoReticles placeholder| Mod | Kind | Notes |
NoReticles placeholder|---|---|---|
NoReticles placeholder| FuelClockLoader | Pak | Personal pak mod loader (fork of Nexus "Unofficial Editor Mod Loader" Beta 0.1, config regenerated from stock 1.3.6 (collision channels reworked upstream this build)). Loader-convention mods drop BP actors under `Content/MOD/<MapName>/`. |
NoReticles placeholder| CleanCarWindows | Pak | Dirt-free vehicle windows (current approach) |
NoReticles placeholder| CleanPlaneWindows | Pak | Dirt-free plane windows (current approach) |
NoReticles placeholder| NoReticles | Pak | Removes scope/weapon reticles (rebuilt on 1.3.6 client) |
NoReticles placeholder| SpekralScopeNoReticle | Pak | No-reticle variant for the Spekral scope |
NoReticles placeholder| FogKiller | UE4SS Lua | Fog removal (Ctrl+Shift+F keybind taken by this mod) |
NoReticles placeholder| QuestCompleteHotkey | UE4SS Lua | Quest-complete hotkey |
NoReticles placeholder| Lockpicking | Pak source | Lockpicking variants (full-angle build; loose asset tree, never pakged) |
NoReticles placeholder| WeaponPlacement | Pak source | Weapon placement variant (loose asset tree) |
NoReticles placeholder
NoReticles placeholderOlder versions of every mod are kept locally on `/opt` (`/opt/scum-<mod>-v<N>.zip`).
