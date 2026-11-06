-- SightDotProbe v5 — SetMaterial slot-swap probe for reflex-sight glass.
-- Route (gbrain all-scope-no-reticle, continuation brief): the reflex dot is a
-- shader constant, immune to every pak texture/color patch. Last untried lever:
-- swap the glass MATERIAL SLOT on the sight's StaticMeshComponent to a proven
-- transparent donor at runtime. Vehicle-glass lesson: comp:SetMaterial(slot, mat)
-- ACCEPTS StaticFindObject-sourced pointers and silently IGNORES
-- FindAllOf-sourced ones -> BOTH the component and the donor are re-resolved via
-- StaticFindObject by full path at action time. Donor candidates: the two
-- MI_Glass_shared assets (verified in AssetRegistry).
--
-- SAFETY (vehicle-glass v25-31 crashed via an all-component slot scan):
--   * we NEVER FindAllOf("StaticMeshComponent") / never scan all components.
--   * we scan ONLY the 9 narrow reflex-sight BP actor classes.
--   * slot cataloging (GetMaterial reads) happens once per component, only
--     after the actor has been seen valid in >= 3 consecutive polls (grace).
--   * every engine call is pcall'd and logged BEFORE firing (crash names the
--     guilty line: log ending on a CALLING line = that call is guilty).
--
-- HOTKEYS (Ctrl+Shift + letter; SCUM swallows bare digits and F-keys):
--   Ctrl+Shift+G = rescan for sight actors now
--   Ctrl+Shift+H = status (tracked actors + their slot catalogs)
--   Ctrl+Shift+J = swap GLASS-named slots to the donor
--   Ctrl+Shift+K = swap ALL slots to the donor (fallback if no slot has
--                  "glass" in its material name)
--   Ctrl+Shift+L = restore original materials
-- Keybind callbacks ONLY set flags; the 1s poll services them (game-thread
-- rule: callbacks run off-thread, no UObject calls there).
--
-- Test procedure: equip/pickup a sight -> press G -> look for TRACKED +
-- SLOT lines -> press J (then K if J swapped nothing) -> observe the sight
-- glass/dot in game. If the dot is gone with usable glass: route proven.
-- Restore with L. Log: ue4ss/UE4SS.log, grep [SightDotProbe].

local P = '[SightDotProbe]'
print(P, 'loaded v5 setmaterial slot-swap probe')

-- reflex sights that still render dots (holos OKP-7/NavTech/XPS already clear
-- via the pak mask route and are NOT targets)
local CLASSES = {
    'WeaponSights_RedDot_CA401B_C',
    'WeaponSights_MRO_Red_Dot_C',
    'WeaponSights_AimPRO_C',
    'WeaponSights_AimPRO_ES_C',
    'WeaponSights_Deagle_RedDot_C',
    'WeaponSights_Sentry_RDRS_C',
    'WeaponSights_Wasp_C',
    'WeaponSights_Snake_C',
    'WeaponSights_Shark_C',
}

-- donors resolved ONLY via StaticFindObject, in this order; first hit wins
local DONORS = {
    '/Game/ConZ_Files/Models/Objects/Outdoor/Camping/Camping_House/Windows/MI_Glass_shared.MI_Glass_shared',
    '/Game/ConZ_Files/Models/Buildings/City/SharedMaterials/MI_Glass_shared.MI_Glass_shared',
}

local tracked = {}      -- fullname -> entry
local scan_tick = 0
local rescan_req = false
local status_req = false
local swap_glass_req = false
local swap_all_req = false
local restore_req = false

local function log(...) print(P, ...) end

local function safe(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

-- "StaticMeshComponent /Game/X.Y.Z.ItemMesh0" -> "/Game/X.Y.Z.ItemMesh0"
local function fullpath(obj)
    local s = safe(function() return obj:GetFullName() end)
    if not s then return nil end
    return s:match(' (.+)$') or s
end

local function alive(obj)
    if obj == nil then return false end
    local un = safe(function() return obj:IsUnreachable() end)
    if un == true then return false end
    local v = safe(function() return obj:IsValid() end)
    if v == false then return false end
    return true
end

local function resolve_donor()
    for _, path in ipairs(DONORS) do
        local d = safe(StaticFindObject, nil, nil, path, false)
        if d ~= nil and alive(d) then
            log('donor RESOLVED via StaticFindObject: ' .. path)
            return d, path
        end
        log('donor not resolved (nil/dead): ' .. path)
    end
    return nil, nil
end

-- catalog a tracked actor's mesh component once: comp path + per-slot material
-- paths. READ ONLY. Never re-catalogued (vehicle lesson: slot reads during
-- seat/attach churn are the crash surface).
local function catalog(entry)
    local actor = entry.actor
    local mesh = safe(function() return actor.ItemMesh0 end)
    if mesh == nil then
        mesh = safe(function() return actor.RootComponent end)
        if mesh then log('catalog: ItemMesh0 missing, using RootComponent') end
    end
    if mesh == nil then
        log('catalog FAIL: no mesh component on ' .. entry.key)
        entry.cataloged = true
        entry.catalog_failed = true
        return
    end
    local cpath = fullpath(mesh)
    if not cpath then
        log('catalog FAIL: mesh GetFullName unreadable on ' .. entry.key)
        entry.cataloged = true
        entry.catalog_failed = true
        return
    end
    entry.comp_path = cpath
    entry.slots = {}
    local n = safe(function() return mesh:GetNumMaterials() end) or 0
    if n > 8 then n = 8 end
    for i = 0, n - 1 do
        local mat = safe(function() return mesh:GetMaterial(i) end)
        local mp = mat and fullpath(mat) or nil
        entry.slots[#entry.slots + 1] = { slot = i, mat_path = mp, swapped = false }
        log(string.format('SLOT %s [%d] = %s', cpath, i, mp or 'UNREADABLE'))
    end
    entry.cataloged = true
    log(string.format('catalog done: %s (%d slots)', cpath, n))
end

local function scan()
    local new_n = 0
    for _, cls in ipairs(CLASSES) do
        local list = safe(FindAllOf, cls)
        if list == nil then
            -- FindAllOf is unreliable on this build (returns nil for live
            -- classes); FindFirstOf fallback, logged as such
            local one = safe(FindFirstOf, cls)
            if one ~= nil then
                list = { one }
                log('scan: FindAllOf nil for ' .. cls .. ', FindFirstOf fallback hit')
            end
        end
        if list ~= nil then
            for i = 1, #list do
                local actor = list[i]
                if alive(actor) then
                    local key = safe(function() return actor:GetFullName() end)
                    if key and not tracked[key] then
                        tracked[key] = { key = key, actor = actor, class = cls,
                                         seen = 0, cataloged = false }
                        new_n = new_n + 1
                        log('TRACKED ' .. cls .. ' :: ' .. key)
                    end
                end
            end
        end
    end
    local total = 0
    for _ in pairs(tracked) do total = total + 1 end
    log(string.format('scan done: %d tracked total, %d new', total, new_n))
end

local function do_swap(all_slots)
    local donor, dpath = resolve_donor()
    if donor == nil then
        log('SWAP ABORT: no donor resolved via StaticFindObject (neither MI_Glass_shared path loaded)')
        return
    end
    log('SWAP begin: donor=' .. dpath .. ' mode=' .. (all_slots and 'ALL' or 'GLASS'))
    local calls, ok_n = 0, 0
    for _, entry in pairs(tracked) do
        if entry.cataloged and not entry.catalog_failed and alive(entry.actor) then
            local comp = safe(StaticFindObject, nil, nil, entry.comp_path, false)
            if comp == nil or not alive(comp) then
                log('SWAP skip: comp not re-resolvable: ' .. tostring(entry.comp_path))
            else
                for _, s in ipairs(entry.slots) do
                    local hit = all_slots or
                        (s.mat_path and s.mat_path:lower():find('glass', 1, true) ~= nil)
                    if s.mat_path and hit then
                        calls = calls + 1
                        log(string.format('CALLING SetMaterial(%s [%d], donor) old=%s',
                            entry.comp_path, s.slot, s.mat_path))
                        local ok = safe(function()
                            comp:SetMaterial(s.slot, donor)
                            return true
                        end)
                        if ok then
                            ok_n = ok_n + 1
                            s.swapped = true
                            log(string.format('SWAPPED slot %d on %s', s.slot, entry.key))
                        else
                            log(string.format('SWAP FAILED slot %d on %s', s.slot, entry.key))
                        end
                    end
                end
            end
        end
    end
    log(string.format('SWAP done: %d call(s), %d ok', calls, ok_n))
end

local function do_restore()
    log('RESTORE begin')
    local calls, ok_n = 0, 0
    for _, entry in pairs(tracked) do
        if entry.cataloged and not entry.catalog_failed and alive(entry.actor) then
            local comp = safe(StaticFindObject, nil, nil, entry.comp_path, false)
            if comp == nil or not alive(comp) then
                log('RESTORE skip: comp not re-resolvable: ' .. tostring(entry.comp_path))
            else
                for _, s in ipairs(entry.slots) do
                    if s.swapped and s.mat_path then
                        calls = calls + 1
                        local orig = safe(StaticFindObject, nil, nil, s.mat_path, false)
                        if orig == nil then
                            log('RESTORE FAIL: original not re-resolvable: ' .. s.mat_path)
                        else
                            local ok = safe(function()
                                comp:SetMaterial(s.slot, orig)
                                return true
                            end)
                            if ok then
                                ok_n = ok_n + 1
                                s.swapped = false
                            end
                        end
                    end
                end
            end
        end
    end
    log(string.format('RESTORE done: %d call(s), %d ok', calls, ok_n))
end

local function do_status()
    local n = 0
    for _, entry in pairs(tracked) do
        n = n + 1
        log(string.format('status [%d] %s class=%s seen=%d cataloged=%s comp=%s',
            n, entry.key, entry.class, entry.seen, tostring(entry.cataloged),
            tostring(entry.comp_path)))
        if entry.slots then
            for _, s in ipairs(entry.slots) do
                log(string.format('  slot %d = %s%s', s.slot, s.mat_path or 'UNREADABLE',
                    s.swapped and '  (SWAPPED)' or ''))
            end
        end
    end
    if n == 0 then
        log('status: nothing tracked yet - pickup/equip a sight then press Ctrl+Shift+G')
    end
end

-- binds: log every result; SCUM eats bare digits + F-keys, so Ctrl+Shift+letter
local function bind(keyname, fn, tag)
    local k = Key[keyname]
    if k == nil then
        log('bind ' .. tag .. ' FAILED: Key.' .. keyname .. ' is nil (no-key)')
        return
    end
    local ok, r = pcall(RegisterKeyBind, k, { ModifierKey.CONTROL, ModifierKey.SHIFT }, fn)
    if ok then
        log('bind ' .. tag .. ' OK (' .. tostring(r) .. ')')
    else
        log('bind ' .. tag .. ' FAILED: ' .. tostring(r))
    end
end
bind('G', function() rescan_req = true end,       'Ctrl+Shift+G rescan')
bind('H', function() status_req = true end,       'Ctrl+Shift+H status')
bind('J', function() swap_glass_req = true end,   'Ctrl+Shift+J swap-glass')
bind('K', function() swap_all_req = true end,     'Ctrl+Shift+K swap-all')
bind('L', function() restore_req = true end,      'Ctrl+Shift+L restore')

log('initial scan...')
safe(scan)

LoopAsync(1000, function()
    scan_tick = scan_tick + 1
    if scan_tick % 60 == 0 then
        local n = 0
        for _ in pairs(tracked) do n = n + 1 end
        log(string.format('heartbeat: poll alive, tick=%d, tracked=%d', scan_tick, n))
    end
    -- grace: catalog only after 3 consecutive live sightings
    for _, entry in pairs(tracked) do
        if alive(entry.actor) then
            entry.seen = entry.seen + 1
            if entry.seen >= 3 and not entry.cataloged then
                catalog(entry)
            end
        end
    end
    if rescan_req then
        rescan_req = false
        log('key: rescan requested')
        safe(scan)
    end
    if swap_glass_req then
        swap_glass_req = false
        log('key: swap-glass requested')
        safe(do_swap, false)
    end
    if swap_all_req then
        swap_all_req = false
        log('key: swap-all requested')
        safe(do_swap, true)
    end
    if restore_req then
        restore_req = false
        log('key: restore requested')
        safe(do_restore)
    end
    if status_req then
        status_req = false
        do_status()
    end
    return false
end)

log('poll started; keys: G=rescan H=status J=swap-glass K=swap-all L=restore')
