-- FogKiller v33 for SCUM (UE4SS Lua) - 2026-11-04
-- v33: un-hide uses SetActorHiddenInGame(false) so fog spheres reappear
--   immediately (raw bHidden writes left render state stale until a mouse
--   move); hide path unchanged.
-- v32: un-hidden fog spheres get a same-value location write (render-state
--   kick) so they reappear without needing a mouse/camera update.
-- v31: queued toggle presses drain on a dedicated 150ms loop (was: 1s poll)
--   so spammed presses no longer trail the tint on fog restore.
-- v30: polarity flip - fog ON by default, Ctrl+Shift+F toggles fog OFF/ON;
--   PP_Powerplant tint now killed with the powerplant fog.
-- v16 city run: fog survived PPV disable + every particle class observed
--   (city Niagara = flies only, Emitters = river splashes) and fog vanishes
--   at altitude -> the city fog is ENGINE height fog, i.e. the same thing
--   scum.EnableFog toggles server-side. v17 turns the equivalent cvars off
--   client-side via ExecuteInConsole: "r.Fog 0", "r.VolumetricFog 0".
--   Applied once per world session; actor hiding kept as belt-and-braces.
-- Purpose: hide every fake-volumetric fog shell SCUM places at POIs, client-side.
-- v15 CHANGE: the v14 city run identified the fog source - PostProcessVolume
--   "PP_AbandonedCity" (the city Niagara systems are all NS_Flies_Exposed, no
--   fog). v15 DISABLES any PostProcessVolume whose name contains
--   "abandonedcity" or "fog": writes bEnabled=false and BlendWeight=0.0 so the
--   volume contributes neither volumetric fog nor color grading. Other PPVs
--   (menu, distant clouds) are untouched. NiagaraActor + LocalFogVolume remain
--   observation-only.
-- v14 CHANGE (diagnostic pass): three city sessions (20:59 run: spawned INSIDE
--   the fog, flew, exit+re-enter) produced ZERO tracked fog actors of any of
--   the 5 hide classes - the city fog is not a known fog-sphere actor. This
--   version OBSERVES three remaining suspects WITHOUT hiding them:
--     NiagaraActor      - v8b dumped 95 with no 'fog' in the ACTOR name, but an
--                         actor name never reveals its SYSTEM asset; this
--                         version reads and logs each Niagara system's asset
--                         full name (pcall candidate list: .NiagaraSystem
--                         property, then :GetAsset()).
--     PostProcessVolume - can override fog/exposure per volume.
--     LocalFogVolume    - engine-local fog volume actor (UE4.26+).
--   Observe sweeps run every 5th poll to keep FindAllOf wrapper cost low.
-- v13 CHANGE (kept): hide at spawn via bare bHidden property write in the
--   NotifyOnNewObject callback; poll verifies after 5s grace and escalates.
--
-- CHANGES vs v11 (both from the 19:28 city run):
--   * tracking keyed on GetFullName() STRING, not userdata identity.
--     FindAllOf returns a NEW userdata wrapper each poll, so userdata keys
--     deduplicated to nothing and the same actor was re-logged every second.
--   * added ExponentialHeightFog + AtmosphericFog + BP_Fog_BOX_C probes.
--     The v11 log showed ZERO BP_FogSphere_C actors ever spawning, so the
--     city fog must use one of these other mechanisms (they are native /
--     narrow classes, safe to probe; NOT the Actor base-class sweep that
--     crashed clients before).
--   * hides ExponentialHeightFog's fog too if it is the city mechanism
--     (set bEnabled=false rather than hiding the actor - engine fog is not
--     hidden by SetActorHiddenInGame reliably).
--
-- ENABLE IT (this build reads Mods/mods.txt):
--   FogKiller : 1
-- USAGE: press Ctrl+Shift+F in-game to switch fog OFF (kill) / ON (restore).
--   The key is the TOGGLE_KEY/TOGGLE_MODS pair at the top of the script -
--   change it there if you want a different combo.
--   DEBUG: plain boolean at the top of the script. true = full verbose log
--   (per-actor sweep/track chatter); false = critical lines only (loaded
--   banner, bind status, TOGGLE ->, debounce). Flip it and restart SCUM.
-- VERIFY: grep FogKiller UE4SS.log -> "v26 loaded (fog: Ctrl+Shift+F |
--   debug=false | 2s debounce)", "fog hotkey Ctrl+Shift+F bound",
--   "TOGGLE -> fog ON/OFF".
-- v26: with DEBUG=false the UE4SS.log is FULLY clean at runtime - the sweep
--   and un-hide-drain summaries moved behind the debug gate, only the loaded
--   banner, bind status and TOGGLE -> lines ever print.

-- v18: probe COMPONENT classes too - the fog is very likely an
-- ExponentialHeightFogComponent (or a NiagaraComponent playing
-- NS_GroundFog_Unlit) attached to a custom SCUM actor, which no actor-class
-- probe can ever find. Components are tracked and disabled directly.
-- v19: in-game fog TOGGLE via UE4SS hotkey. Ctrl+Shift+F kills/restores the
-- fog client-side. Plain F and the F-keys are game bindings, so a modifier
-- combo cannot overlap anything. CHANGE THESE to rebind:
local TOGGLE_KEY = Key.F
local TOGGLE_MODS = { ModifierKey.CONTROL, ModifierKey.SHIFT }

local TAG = "[FogKiller]"
-- narrow classes only; BP_VolumetricFog_C is a base class and was removed in v10
local CLASSES = {
    "BP_Real_VolumetricFog_Sphere_C",
    "BP_FogSphere_C",
    "BP_Fog_BOX_C",
    "ExponentialHeightFog",
    "AtmosphericFog",
    -- component probes (owner actors can be anything)
    "ExponentialHeightFogComponent",
    "AtmosphericFogComponent",
    "NiagaraComponent",
}
-- observed (diagnostics only); fog-named particle actors ARE hidden (v16)
local OBSERVE = {
    "NiagaraActor",
    "PostProcessVolume",
    "LocalFogVolume",
    "Emitter",
}

local GRACE_MS = 5000
local POLL_MS = 1000

-- v22: distance-based untracking. The tracked set grew for the whole session
-- (every fog sphere you walk past stays in it forever) and every toggle ON
-- re-un-hid ALL of them. Now an actor farther than UNTRACK_DISTANCE from the
-- player is un-hidden (restored to the game's own state) and dropped from
-- `tracked`; it re-tracks naturally when you come back into range. In UE
-- units (1uu = 1cm): 50000 = 500m.
-- v26 final: 500m. The fog shells are ground-hugging volumes (user observation:
-- fog vanishes at altitude, reappears on descent) so they're not rendering from
-- beyond a few hundred meters - 1km was overkill. 500m still guarantees every
-- actor that CAN be visible is tracked, while shrinking the tracked set ~75%
-- (area scales with radius squared).
local UNTRACK_DISTANCE = 50000
-- v22: crash fix for repeated toggles. The SCUM.log tail shows the crash came
-- after ~a dozen fog ON/OFF cycles (plus settime changes re-initializing the
-- weather controller) - each cycle calls Deactivate()/Activate() on the
-- weather controller's HeightFog component, and repeated activation cycles
-- crash the engine. v22 therefore never calls Deactivate/Activate: kill and
-- restore are PURE PROPERTY WRITES (bEnabled/bActive/bVisible/FogDensity),
-- which cannot trip the render-state race.
local USE_ENGINE_ACTIVATE = false   -- keep false; property writes only

-- v21: DEBUG flag. Set to true when troubleshooting to get the full verbose
-- log (per-actor sweep/track chatter); false keeps UE4SS.log to critical
-- lines only (loaded banner, bind status, TOGGLE ->, debounce). It is a plain
-- top-of-script boolean: flip it here, restart SCUM, no hotkey needed.
local DEBUG = false

-- v21: log() is debug-gated by the DEBUG flag above; logAlways() is the
-- critical-only channel.
local debugOn = DEBUG
local function log(s) if debugOn then print(TAG .. " " .. s) end end
local function logAlways(s) print(TAG .. " " .. s) end

logAlways("v30 loaded (fog ON by default; hotkey kills) (fog: Ctrl+Shift+F | debug=" .. tostring(DEBUG) .. " | 2s debounce)")

-- v22: batched un-hide queue. doToggle ON fills it; the poll loop pops at most
-- 2 entries per tick, spacing the render-state churn out over engine time.
local unhideQueue = {}
local unhideCount = 0

-- v20: the fast-toggle crash fix. Every press does Deactivate/Activate on the
-- weather controller's fog component; flipping render state faster than the
-- engine can settle crashes it (confirmed at the powerplant with sub-second
-- presses). So the toggle carries a COOLDOWN, but presses inside the window
-- are QUEUED, not dropped: the latest queued press executes once the cooldown
-- expires (via the poll loop), so rapid mashing still ends up toggled.
local TOGGLE_COOLDOWN_MS = 2000
local toggleQueued = false   -- a press landed inside the cooldown window
local lastToggleMs = nil
-- monotonic-ish ms clock via GetTickCount (UE4SS global); fallback to counting polls
local function nowMs()
    local ok, ms = pcall(GetTickCount)
    if ok and type(ms) == "number" then return ms end
    return nil
end

-- v19 toggle state: fogKilled = fog removed. saved holds the pre-kill values
-- needed to put everything back exactly as the game had it.
local fogKilled = false   -- v30: fog ON by default; the hotkey kills it
local saved = {}            -- fullname -> {kind="comp"/"ppv", ref=..., density=?, enabled=?, blend=?}
local savedOrder = {}       -- fullnames in discovery order (restore order)

local tracked = {}          -- name-string -> {born, actor, cls}
local pending = {}          -- {actor, since, cls} from NotifyOnNewObject
local seenSys = {}          -- system-asset full names already logged (spam control)
local censusPending = false
local censusDone = false
local lastSummary = nil
local now = 0

-- v24: world-session tracking. The v23 crash happened at a MAP TRANSITION
-- (main menu -> game): the untracking sweep read actor locations while the
-- level was being torn down. GameState's full name CHANGES between maps, so
-- we detect transitions here: on change, reset every actor-tracking table and
-- skip all actor access for a few polls while the new map streams in.
local lastWorldName = nil
local transitionCooldown = 0

-- v23: property-write-only visibility helpers. The v21/v22 crash trail says
-- SetActorHiddenInGame / Deactivate / Activate rebuild render state and
-- repeated cycles crash the engine, so every toggle path uses bHidden only.
-- v33: un-hide via SetActorHiddenInGame(false). A raw bHidden=false property
-- write never rebuilds the render state - the sphere stays invisible until
-- something else nudges the scene (user report: only a mouse move revived the
-- fog; WASD did not). SetActorHiddenInGame is the engine's own visibility
-- path and marks every component's render state dirty in one call. The
-- historic crash was Deactivate/Activate on the weather fog component (removed
-- in v22), not visibility calls; hide (bHidden=true) keeps the cheap path.
local function unhideActor(a)
    local ok = pcall(function() a:SetActorHiddenInGame(false) end)
    if ok then
        pcall(function() a.bHidden = false end)
    else
        pcall(function() a.bHidden = false end)
    end
end

-- v19: register a fog object's pre-kill state (first time only). Returns
-- true when newly saved. snapshotFn fills kind-specific fields via pcall.
local function saveEntry(kind, ref, key, snapshotFn)
    if key == nil or saved[key] ~= nil then return false end
    local snap = { kind = kind, ref = ref }
    if snapshotFn ~= nil then pcall(snapshotFn, snap) end
    saved[key] = snap
    savedOrder[#savedOrder + 1] = key
    return true
end

local function valid(a)
    local ok, v = pcall(function() return a:IsValid() end)
    return ok and v
end

local function fullName(a)
    local okN, fn = pcall(function() return a:GetFullName() end)
    if okN and fn then return fn end
    local ok2, n2 = pcall(function() return a:GetName() end)
    if ok2 and n2 then return n2 end
    return "<name unreadable>" .. tostring(now)
end

local function isHidden(a)
    local ok, v = pcall(function() return a.bHidden end)
    if ok then return v end
    local ok2, v2 = pcall(function() return a:IsHidden() end)
    if ok2 then return v2 end
    return nil
end

local function hide(a)
    pcall(function() a:SetActorHiddenInGame(true) end)
    pcall(function() a.bHidden = true end)
end

-- v18: disable a fog COMPONENT. pcall candidate writes - whatever this build
-- supports wins; a missing property is harmless.
-- v19: every kill also SNAPSHOTs the pre-kill state into `saved` (keyed by
-- full name) so Ctrl+Shift+F can restore the fog exactly as the game had it.
local function disableComponent(c, key)
    local writes = 0
    saveEntry("comp", c, key, function(snap)
        pcall(function() snap.density = c.FogDensity end)
    end)
    pcall(function() c.bEnabled = false; writes = writes + 1 end)
    pcall(function() c.bActive = false; writes = writes + 1 end)
    pcall(function() c.bVisible = false; writes = writes + 1 end)
    pcall(function() c.FogDensity = 0.0; writes = writes + 1 end)
    -- v22: Deactivate() removed - it rebuilds the component's render state and
    -- repeated activation cycles crash the engine (v19/v21 crash evidence).
    -- The property writes above are sufficient; if the fog survives them on
    -- some component, set USE_ENGINE_ACTIVATE = true to re-enable the call.
    if USE_ENGINE_ACTIVATE then
        pcall(function() c:Deactivate(); writes = writes + 1 end)
    end
    return writes
end

-- v19: restore one saved entry. Whatever write fails is left as-is.
local function restoreSaved()
    local restored = 0
    for _, key in ipairs(savedOrder) do
        local s = saved[key]
        if s ~= nil and valid(s.ref) then
            if s.kind == "comp" then
                pcall(function() s.ref.bEnabled = true end)
                pcall(function() s.ref.bActive = true end)
                pcall(function() s.ref.bVisible = true end)
                if s.density ~= nil then pcall(function() s.ref.FogDensity = s.density end) end
                if USE_ENGINE_ACTIVATE then
                    pcall(function() s.ref:Activate(true) end)
                end
            elseif s.kind == "ppv" then
                if s.enabled ~= nil then pcall(function() s.ref.bEnabled = s.enabled end) end
                if s.blend ~= nil then pcall(function() s.ref.BlendWeight = s.blend end) end
            end
            restored = restored + 1
        end
    end
    return restored
end

-- resolve a NiagaraComponent's system asset (candidates: .NiagaraSystem, .Asset, :GetAsset())
local function niagaraComponentSystem(c)
    local sys = nil
    pcall(function() sys = c.NiagaraSystem end)
    if sys == nil or not valid(sys) then
        pcall(function() sys = c.Asset end)
    end
    if sys == nil or not valid(sys) then
        local ok, asset = pcall(function() return c:GetAsset() end)
        if ok then sys = asset end
    end
    if sys ~= nil and valid(sys) then
        local ok, fn = pcall(function() return sys:GetFullName() end)
        if ok and fn then return fn end
    end
    return nil
end

-- v18: fog-name test (case-insensitive substring); must precede all users.
local function fogNamed(s)
    if s == nil then return false end
    local l = s:lower()
    return l:find("fog", 1, true) ~= nil
end

-- v18: NiagaraComponent handler. Components number in the hundreds (every
-- particle in the game), so: never enter `tracked` (the grace-hide loop would
-- blind-hide rain/campfires), dedupe logging by SYSTEM asset name, and only
-- disable when the system is fog-named.
local function trackNiagaraComponent(c)
    if c == nil or not valid(c) then return false end
    local sys = niagaraComponentSystem(c)
    local key = sys or "<unresolved>"
    if seenSys[key] then return false end
    seenSys[key] = true
    log("niagara component system: " .. key)
    if fogNamed(sys) then
        saveEntry("comp", c, "nia:" .. key, nil)   -- no density; restore just re-enables
        if fogKilled then
            local n = disableComponent(c, "nia:" .. key)
            log("niagara component disabled (fog-named system): " .. n .. " write(s)")
        end
    end
    return true
end

local function track(a, cls, doHide)
    if cls == "NiagaraComponent" then return trackNiagaraComponent(a) end
    if a == nil or not valid(a) then return false end
    local name = fullName(a)
    if tracked[name] ~= nil then return false end
    tracked[name] = { born = now, actor = a, cls = cls, hide = doHide ~= false }
    log("tracked: " .. cls .. " " .. name)
    -- fog component probes: snapshot, then disable immediately ONLY while the
    -- toggle is in the OFF/fog-killed state; when fog is ON they stay active
    -- but are registered so a later toggle can kill them.
    if cls == "ExponentialHeightFogComponent" or cls == "AtmosphericFogComponent" then
        local owner = nil
        pcall(function() owner = a:GetOwner() end)
        log("fog component owner: " .. (owner ~= nil and fullName(owner) or "<none>"))
        saveEntry("comp", a, name, function(snap)
            pcall(function() snap.density = a.FogDensity end)
        end)
        if fogKilled then
            local n = disableComponent(a, name)
            log("fog component disabled: " .. n .. " write(s) succeeded")
        else
            log("fog component left active (toggle is ON)")
        end
    end
    return true
end

-- v16: resolve an Emitter actor's particle-system asset name.
-- ANiagaraActor-style property chain does not exist for Cascade Emitters;
-- candidates: .ParticleSystem property, .Component (ParticleSystemComponent).ParticleSystem.
local function emitterSystemName(a)
    local sys = nil
    pcall(function() sys = a.ParticleSystem end)
    if sys ~= nil and valid(sys) then
        local ok, fn = pcall(function() return sys:GetFullName() end)
        if ok and fn then return fn end
    end
    local comp = nil
    pcall(function() comp = a.Component end)
    if comp ~= nil and valid(comp) then
        local ok, ps = pcall(function() return comp.ParticleSystem end)
        if ok and ps ~= nil and valid(ps) then
            local ok2, fn2 = pcall(function() return ps:GetFullName() end)
            if ok2 and fn2 then return fn2 end
        end
    end
    return nil
end

-- v16: hide a particle actor whose SYSTEM or actor name contains fog
-- (case-insensitive). Returns true when a hide was performed.
local function hideParticleIfFog(a, sysName)
    if not valid(a) then return false end
    if fogNamed(sysName) or fogNamed(fullName(a)) then
        pcall(function() a.bHidden = true end)
        pcall(function() a:SetActorHiddenInGame(true) end)
        log("hidden particle (fog-named): " .. (sysName or fullName(a)))
        return true
    end
    return false
end

-- read a NiagaraActor's SYSTEM asset name (actor names never reveal it);
-- pcall candidate list per build: .NiagaraSystem property first, :GetAsset() second
local function niagaraSystemName(a)
    local comp = nil
    pcall(function() comp = a.NiagaraComponent end)
    if comp ~= nil and valid(comp) then
        local sys = nil
        pcall(function() sys = comp.NiagaraSystem end)
        if sys ~= nil and valid(sys) then
            local ok, fn = pcall(function() return sys:GetFullName() end)
            if ok then return fn end
        end
        local okA, asset = pcall(function() return comp:GetAsset() end)
        if okA and asset ~= nil and valid(asset) then
            local ok2, fn2 = pcall(function() return asset:GetFullName() end)
            if ok2 then return fn2 end
        end
    end
    return nil
end

-- v15: disable a city-fog PostProcessVolume. Writes bEnabled=false and
-- BlendWeight=0.0 (APostProcessVolume's own properties), so the volume
-- contributes neither volumetric fog nor color grading. Returns true if any
-- write succeeded.
local function disablePPV(a)
    local done = false
    pcall(function() a.bEnabled = false; done = true end)
    pcall(function() a.BlendWeight = 0.0; done = true end)
    return done
end

-- v19: the hotkey handler. Kill when fog is up, restore when killed.
-- Defined after disablePPV because the re-kill path also disables PPVs.
-- v20: doToggle is forward-declared so toggleFog's upvalue resolves correctly.
local doToggle
local function toggleFog()
    -- v20: debounce - a press inside the cooldown is QUEUED, not dropped.
    local ms = nowMs()
    if ms ~= nil and lastToggleMs ~= nil and (ms - lastToggleMs) < TOGGLE_COOLDOWN_MS then
        toggleQueued = true
        logAlways(string.format("TOGGLE queued (%.1fs inside %ds debounce; fires when it ends)",
            (ms - lastToggleMs) / 1000, TOGGLE_COOLDOWN_MS / 1000))
        return
    end
    lastToggleMs = ms
    toggleQueued = false
    doToggle()
end

-- v20: the actual toggle body (debounce lives in toggleFog).
doToggle = function()
    if fogKilled then
        local n = restoreSaved()
        -- v22: do NOT un-hide everything in this frame. Instead queue the
        -- tracked fog-sphere actors; the poll loop un-hides at most 2 per tick
        -- (2s apart), so a big tracked set spreads over engine time instead of
        -- slamming every actor's render state in one frame (v21 crash: the
        -- un-hide count grew 1 -> 3 -> 4 per toggle and the game died after ~a
        -- dozen cycles).
        unhideQueue = {}
        unhideCount = 0
        for _, st in pairs(tracked) do
            if st.hide and st.actor ~= nil and valid(st.actor) then
                unhideQueue[#unhideQueue + 1] = st
            end
        end
        logAlways(string.format("TOGGLE -> fog ON (restored %d saved object(s), queued %d actor(s) to un-hide)",
            n, #unhideQueue))
        fogKilled = false
    else
        local n = 0
        for _, key in ipairs(savedOrder) do
            local s = saved[key]
            if s ~= nil and valid(s.ref) then
                if s.kind == "comp" then
                    disableComponent(s.ref, key)   -- snapshot already exists: re-kill only
                    n = n + 1
                elseif s.kind == "ppv" then
                    disablePPV(s.ref)
                    n = n + 1
                end
            end
        end
        -- v22: cancel any un-hide backlog from a previous toggle ON - the
        -- actors must stay hidden now.
        unhideQueue = {}
        unhideCount = 0
        -- v23: re-hide ALL tracked fog-sphere actors right here via property
        -- writes. City fog lives in `tracked` (saved is empty in city
        -- sessions - see the v22 log: "restored 0, re-killed 0"), so without
        -- this the OFF toggle relied on the 5s-grace poll loop and looked dead.
        local h = 0
        for _, st in pairs(tracked) do
            if st.hide and st.actor ~= nil and valid(st.actor) then
                -- v28: write ONLY when the state actually differs. The city has
                -- few fog objects, but the powerplant shells are dozens of
                -- spheres; rewriting bHidden on all of them on every press is
                -- the "laggy powerplant" feel. A property READ is cheap.
                local cur = nil
                pcall(function() cur = st.actor.bHidden end)
                if cur ~= true then
                    pcall(function() st.actor.bHidden = true end)
                    h = h + 1
                end
            end
        end
        logAlways(string.format("TOGGLE -> fog OFF (re-killed %d fog object(s), re-hid %d actor(s))", n, h))
        fogKilled = true
    end
end

-- bind once at load; pcall so a missing RegisterKeyBind/modifier support on
-- this UE4SS build degrades to "no toggle" without killing the whole mod
local okBind, errBind = pcall(RegisterKeyBind, TOGGLE_KEY, TOGGLE_MODS, toggleFog)
logAlways("fog hotkey Ctrl+Shift+F " .. (okBind and "bound" or "BIND FAILED: " .. tostring(errBind)))
-- v21: debug is a plain top-of-script boolean (no hotkey). Flip DEBUG=true
-- at the top of this file when troubleshooting, then restart SCUM.

local function observeTrack(a, cls)
    if not track(a, cls, false) then return false end
    if cls == "NiagaraActor" then
        local sys = niagaraSystemName(a)
        log("niagara system: " .. (sys or "<unresolved>"))
        hideParticleIfFog(a, sys)
    elseif cls == "Emitter" then
        local sys = emitterSystemName(a)
        log("emitter system: " .. (sys or "<unresolved>"))
        hideParticleIfFog(a, sys)
    elseif cls == "PostProcessVolume" then
        local lname = fullName(a):lower()
        if lname:find("abandonedcity") or lname:find("fog") or lname:find("powerplant") then
            local fn = fullName(a)
            saveEntry("ppv", a, fn, function(snap)
                pcall(function() snap.enabled = a.bEnabled end)
                pcall(function() snap.blend = a.BlendWeight end)
            end)
            if fogKilled then
                if disablePPV(a) then
                    log("ppv disabled: " .. fn)
                else
                    log("ppv disable FAILED: " .. fn)
                end
            end
        end
    end
    return true
end

for _, cls in ipairs(CLASSES) do
    pcall(NotifyOnNewObject, cls, function(a)
        if a ~= nil then
            -- hide at spawn: property write only, no engine function calls here
            -- (only while the toggle is in the OFF/fog-killed state)
            if fogKilled then
                pcall(function() a.bHidden = true end)
            end
            pending[#pending + 1] = { a = a, since = now, cls = cls }
        end
    end)
end
for _, cls in ipairs(OBSERVE) do
    pcall(NotifyOnNewObject, cls, function(a)
        if a ~= nil then
            pending[#pending + 1] = { a = a, since = now, cls = cls, observe = true }
        end
    end)
end

local function sweepClass(cls)
    local ok, list = pcall(FindAllOf, cls)
    if ok and list ~= nil then
        local added = 0
        for _, a in ipairs(list) do
            if track(a, cls) then added = added + 1 end
        end
        if added > 0 then
            log(string.format("sweep %s: +%d via FindAllOf", cls, added))
        end
        return true
    end
    local ok2, one = pcall(FindFirstOf, cls)
    if ok2 and one ~= nil then
        if track(one, cls) then
            log("sweep " .. cls .. ": +1 via FindFirstOf")
        end
    end
    return false
end

local function census()
    for _, cls in ipairs(CLASSES) do
        local allOK = sweepClass(cls)
        if not allOK then
            log("census " .. cls .. ": FindAllOf nil, FindFirstOf fallback")
        end
    end
end

-- v31: fast drain for QUEUED toggle presses. The queued press used to wait
-- for the next 1s poll tick, so a spammed "show fog" landed up to 1s after
-- the tint restore -> fog trailing the tint. A dedicated 150ms loop drains
-- queued presses quickly; the writes are property-only (v23 safe path).
LoopAsync(150, function()
    local okGQ, gsQ = pcall(FindFirstOf, "GameState")
    if not (okGQ and gsQ ~= nil and valid(gsQ)) then return false end
    if toggleQueued and transitionCooldown <= 0 then
        local ms = nowMs()
        if ms == nil or lastToggleMs == nil or (ms - lastToggleMs) >= TOGGLE_COOLDOWN_MS then
            if ms ~= nil then lastToggleMs = ms end
            toggleQueued = false
            doToggle()
        end
    end
    return false
end)

LoopAsync(POLL_MS, function()
    now = now + 1

    -- v20: drain the queued toggle once the cooldown has expired. Firing via
    -- the poll loop guarantees it runs in a fresh game thread, never back-to-
    -- back with the press that queued it. v24: drain only when a live world is
    -- present - toggling during a map transition touches dead actors.
    local okG0, gs0 = pcall(FindFirstOf, "GameState")
    local worldLive = okG0 and gs0 ~= nil and valid(gs0)
    if toggleQueued and worldLive and transitionCooldown <= 0 then
        local ms = nowMs()
        if ms == nil then
            -- no clock on this build: drain after 2 polls as a fallback
            if now % 2 == 0 then
                toggleQueued = false
                log("TOGGLE executing (queued press drained)")
                doToggle()
            end
        elseif (ms - lastToggleMs) >= TOGGLE_COOLDOWN_MS then
            toggleQueued = false
            log("TOGGLE executing (queued press drained)")
            doToggle()
        end
    end

    for i = #pending, 1, -1 do
        local e = pending[i]
        pending[i] = nil
        if e.observe then
            observeTrack(e.a, e.cls)
        else
            track(e.a, e.cls)
        end
    end

    local okG, gs = pcall(FindFirstOf, "GameState")
    local inWorld = okG and gs ~= nil and valid(gs)
    if not inWorld then
        censusPending = false
        -- v24: world is gone (main menu) - the queue and pending table hold
        -- actors from the old map; clear them so nothing survives into the
        -- transition. The untracking sweep is NOT run here (no valid pawn).
        unhideQueue = {}
        unhideCount = 0
        pending = {}
        return false
    end
    -- v24: map-transition detection. GameState's full name changes between
    -- maps (menu map <-> game map). On change: reset all actor tables and arm
    -- a cooldown so the first polls on the new map skip every actor access.
    local okW, wname = pcall(function() return gs:GetFullName() end)
    if okW and wname ~= nil then
        if lastWorldName ~= nil and wname ~= lastWorldName then
            logAlways("world transition detected (" .. tostring(wname) .. ") - resetting actor state")
            tracked = {}
            pending = {}
            unhideQueue = {}
            unhideCount = 0
            saved = {}
            savedOrder = {}
            censusDone = false
            transitionCooldown = 10
        end
        lastWorldName = wname
    end
    if transitionCooldown > 0 then
        transitionCooldown = transitionCooldown - 1
        return false   -- new map still streaming: touch nothing
    end

    if not censusPending and not censusDone then
        censusPending = true
        census()
        censusDone = true
        censusPending = false
    end

    -- v18/v19: kill engine fog client-side every 5th poll (10s) - the thing
    -- scum.EnableFog toggles server-side, re-applied client-side. Only while
    -- the toggle is in the OFF/fog-killed state (it would otherwise fight a
    -- "fog ON" restore). A level load or map travel can re-arm fog, so this
    -- must not be a one-shot. Bad cvar names are harmless.
    if fogKilled and now % 5 == 0 then
        for _, cmd in ipairs({ "r.Fog 0", "r.VolumetricFog 0", "r.FogDensity 0" }) do
            pcall(ExecuteInConsole, cmd)
        end
        log("cvar re-apply: r.Fog 0, r.VolumetricFog 0, r.FogDensity 0")
    end

    for _, cls in ipairs(CLASSES) do sweepClass(cls) end

    -- observe sweeps every 5th poll (wrapper-cost limiter)
    if now % 5 == 0 then
        for _, cls in ipairs(OBSERVE) do
            local ok, list = pcall(FindAllOf, cls)
            if ok and list ~= nil then
                local added = 0
                for _, a in ipairs(list) do
                    if observeTrack(a, cls) then added = added + 1 end
                end
                if added > 0 then
                    log(string.format("observe %s: +%d via FindAllOf", cls, added))
                end
            else
                pcall(function()
                    local one = FindFirstOf(cls)
                    if one ~= nil then observeTrack(one, cls) end
                end)
            end
        end
    end

    -- v22: drain the un-hide queue, 2 actors per tick. Only while the toggle
    -- is ON (fog restored); toggle OFF empties the queue before setting
    -- fogKilled, so nothing here can fight a re-kill.
    if not fogKilled and #unhideQueue > 0 then
        -- v26: SCALE the drain with the queue. The tracked set grows all
        -- session (every fog actor driven past while fog was OFF stays
        -- tracked), so a fixed 5/tick made toggle-ON take 30s+ after a long
        -- drive (user report). The un-hide path is a pure bHidden property
        -- write (no engine calls since v23), safe at volume: drain ~half the
        -- queue per tick (floor 20, cap 300) -> any backlog clears in ~2s.
        -- v29: drain the ENTIRE queue in one tick. The un-hide path is pure
        -- bHidden property writes (no engine calls since v23), so even a few
        -- hundred writes in one frame are trivial - and the user-visible
        -- symptom of pacing them was fog not returning for 30s+ after toggle
        -- ON at the powerplant (restore tint arrived instantly, spheres lagged
        -- behind). Pacing is unnecessary; kill instantly, restore instantly.
        local perTick = #unhideQueue
        local batch = 0
        while #unhideQueue > 0 and batch < perTick do
            local st = table.remove(unhideQueue)
            -- v33: route through unhideActor - the raw bHidden write leaves
            -- the render state stale (fog only reappearing on a mouse move);
            -- SetActorHiddenInGame(false) rebuilds it in one engine call.
            if st ~= nil and st.actor ~= nil and valid(st.actor) then
                -- v28: same read-before-write as the hide path. At the
                -- powerplant the queue holds dozens of spheres; restoring
                -- visibility on already-visible ones is pure churn.
                local cur = nil
                pcall(function() cur = st.actor.bHidden end)
                if cur ~= false then
                    unhideActor(st.actor)
                    unhideCount = unhideCount + 1
                end
                batch = batch + 1
                log("un-hid: " .. st.cls .. " " .. fullName(st.actor))
            end
        end
        if #unhideQueue == 0 then
            log(string.format("un-hide queue drained: %d actor(s) restored", unhideCount))
        end
    end

    -- v22: distance-based untracking, every 10th poll. Player position comes
    -- from the first valid Pawn; if none is available this sweep is skipped.
    -- Actors farther than UNTRACK_DISTANCE are un-hidden (restored to the
    -- game's own state) and dropped from `tracked`; they re-track naturally
    -- when the player comes back into range.
    if now % 10 == 0 then
        local okP, pawn = pcall(FindFirstOf, "Pawn")
        local px, py, pz = nil, nil, nil
        if okP and pawn ~= nil and valid(pawn) then
            pcall(function()
                local loc = pawn.K2_GetActorLocation()
                px, py, pz = loc.X, loc.Y, loc.Z
            end)
        end
        if px ~= nil then
            local untracked = 0
            for name, st in pairs(tracked) do
                local a = st.actor
                -- v23: fresh validity check IMMEDIATELY before each access, and
                -- the whole sweep is skipped while fog is killed (the game
                -- changed itself to hide the fog - touching those actors during
                -- a fog-killed session un-hides them and defeats the toggle).
                if a ~= nil and valid(a) then
                    local okL, loc = pcall(function() return a.K2_GetActorLocation() end)
                    if okL and loc ~= nil and loc.X ~= nil then
                        local dx, dy, dz = loc.X - px, loc.Y - py, (loc.Z or 0) - (pz or 0)
                        if dx * dx + dy * dy + dz * dz > UNTRACK_DISTANCE * UNTRACK_DISTANCE then
                            -- restore the game's own visibility state ONLY when
                            -- fog is ON; when fog is killed the actor must stay
                            -- hidden even after we forget about it (the poll
                            -- loop's re-hide relies on it being tracked, so
                            -- leaving it hidden is the correct final state).
                            if st.hide and not fogKilled then
                                unhideActor(a)
                            end
                            tracked[name] = nil
                            untracked = untracked + 1
                            log("untracked (out of range): " .. st.cls .. " " .. name)
                        end
                    end
                end
            end
            if untracked > 0 then
                log(string.format("untracking sweep: dropped %d actor(s)", untracked))
            end
        end
    end

    local total, hidden, shownNow = 0, 0, 0
    for name, st in pairs(tracked) do
        local a = st.actor
        if not valid(a) then
            tracked[name] = nil
        else
            total = total + 1
            if st.hide and fogKilled and now - st.born >= GRACE_MS / POLL_MS then
                local h = isHidden(a)
                if h == false then
                    hide(a)
                    shownNow = shownNow + 1
                    log("hidden: " .. st.cls .. " " .. name)
                elseif h == true then
                    hidden = hidden + 1
                end
            end
        end
    end

    local summary = string.format("tracked=%d hidden=%d", total, hidden)
    if summary ~= lastSummary then
        lastSummary = summary
        log(summary)
    end
    return false
end)
