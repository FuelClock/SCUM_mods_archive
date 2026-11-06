-- GlassClear v34: RAW array writes only — ZERO engine calls on MIDs.
-- v33 proved SetScalarParameterValue native-faults on this build (log died mid-call).
-- Indices come from the cooked JSON dump (/opt/scum_files_json): per MI template,
-- the scalar override array order is fixed; element FNames read nil at runtime,
-- so we write by index and verify by value anchors in the log.
local SCAN_ONLY = false     -- true = log only, no writes
local INVISIBLE = false     -- true = also zero the opacity clamp scalars (windows disappear)
local GRACE_POLLS = 3       -- polls a new MID must be seen before first touch

-- parent MI name -> { dirt = {idx,...}, invis = {idx,...} }
-- dirt = Dirt Opacity / Dirt str / Dirt_Rougness per template; invis = opacity clamp pair
local MIDX = {
    ["MI_Laika_Glass"]                    = { dirt = {0,3}, invis = {5,6} },
    ["MI_WW_Glass"]                       = { dirt = {0,3}, invis = {5,6} },
    ["MI_Rager_Glass"]                    = { dirt = {0,3}, invis = {5,6} },
    ["MI_Rager_Glass_New"]                = { dirt = {0,3}, invis = {6,8} },
    ["MI_Motorcycle_03_Glass_BodyMain"]   = { dirt = {0},   invis = {4,5} },
    ["MI_Motorcycle_03_Glass_PlasticShell"] = { dirt = {0}, invis = {3,4} },
    ["MI_Motorcycle_01_Glass"]            = { dirt = {0},   invis = {5,6} },
    ["MI_Motorcycle_3_Add_Glass"]         = { dirt = {},    invis = {2,4} },
    ["MI_Bicycle_01_Glass"]               = { dirt = {},    invis = {2,3} },
    ["MI_Tractor_Glass"]                  = { dirt = {},    invis = {2,3} },
    ["MI_Plane_01_Glass"]                 = { dirt = {},    invis = {1,2} },
    ["MI_Marley_Glass"]                   = { dirt = {6},   invis = {2,5} },
    ["MI_WW_Police_Glass"]                = { dirt = {},    invis = {1,2} },
    ["MI_Quad_Civ_Glass"]                 = { dirt = {},    invis = {2,4} },
    ["MI_Quad_Civ_Add_Glass"]             = { dirt = {},    invis = {2,4} },
    ["MI_Quad_Speedometer_Glass"]         = { dirt = {},    invis = {2,4} },
    ["MI_Quad_Mil_Glass"]                 = { dirt = {},    invis = {2,4} },
}

local dummy_tex = nil
local function find_dummy()
    local ok, t = pcall(StaticFindObject, "/Game/ConZ_Files/Textures/Basic/T_FlatWhiteMask_Dummy_01.T_FlatWhiteMask_Dummy_01")
    if ok and t and t:IsValid() then return t end
    return nil
end

local EXCLUDE = { "Lights", "Light", "Radio", "Item", "HitZone", "Scope", "Reflex" }
local zeroed = {}
local mid_seen = {}

local function is_window_glass(name)
    if not name:find("Glass") then return false end
    if not (name:find("Vehicles2") or name:find("Zil_Truck") or name:find("Models/Vehicles/")) then return false end
    for _, x in ipairs(EXCLUDE) do
        if name:find(x) then return false end
    end
    return true
end

-- v23 baseline: raw-zero every scalar on the template MIC override arrays
local function zero_mi(obj, name)
    local okt, scal = pcall(function() return obj.ScalarParameterValues end)
    local okn, n = pcall(function() return scal and scal:GetArrayNum() or 0 end)
    if okt and scal and type(n) == "number" and n > 0 then
        for i = 0, n - 1 do
            pcall(function() local e = scal[i]; if e then e.ParameterValue = 0.0 end end)
        end
    end
    -- v23's proven texture route: swap every _D (grime) texture on the template
    -- to the flat black dummy. Planes (MI_Plane_01_Glass) have NO dirt scalar,
    -- so this is the only lever for the Duster/Mariner.
    if dummy_tex then
        local okt2, tex = pcall(function() return obj.TextureParameterValues end)
        local okn2, tn = pcall(function() return tex and tex:GetArrayNum() or 0 end)
        if okt2 and tex and type(tn) == "number" and tn > 0 then
            local swapped = 0
            local diag = {}
            for i = 0, tn - 1 do
                local okr, pv, valid, matched = pcall(function()
                    local e = tex[i]
                    local okv = e and e.ParameterValue and e.ParameterValue:IsValid()
                    local fn = okv and e.ParameterValue:GetFullName() or "?"
                    return fn, okv, okv and fn:find("_D%.") ~= nil
                end)
                if okr and matched then
                    local okw = pcall(function()
                        local e = tex[i]
                        if e then e.ParameterValue = dummy_tex end
                    end)
                    if okw then swapped = swapped + 1 end
                end
                if not zeroed[name] then
                    diag[#diag+1] = i .. ":" .. tostring(valid) .. ":" .. tostring(pv)
                end
            end
            if not zeroed[name] then
                print("[GlassClear] template " .. name .. " tex swaps=" .. swapped .. "/" .. tn ..
                    " valid=dummy=" .. tostring(dummy_tex and dummy_tex:IsValid()) ..
                    " elems=" .. table.concat(diag, " | "))
            end
        else
            if not zeroed[name] then
                print("[GlassClear] template " .. name .. " tex array unreadable ok=" ..
                    tostring(okt2) .. " n=" .. tostring(okn2 and type(okn2) == "number"))
            end
        end
    else
        if not zeroed[name] then
            print("[GlassClear] template " .. name .. " dummy_tex still nil")
        end
    end
    if not zeroed[name] then
        zeroed[name] = true
        print("[GlassClear] zeroed template " .. name)
    end
end

local function handle_mid(mid, pf, key)
    mid_seen[key] = mid_seen[key] + 1
    local polls = mid_seen[key]
    if polls < GRACE_POLLS then return end
    local first = polls == GRACE_POLLS
    local mname = pf:match("([%a%d_]+)$") or pf
    local idx = MIDX[mname]
    if not idx then
        if first then print("[GlassClear] MID " .. key .. " parent=" .. pf .. " NO index map (skipped)") end
        return
    end
    local okarr, scal = pcall(function() return mid.ScalarParameterValues end)
    local okn, n = pcall(function() return scal and scal:GetArrayNum() or 0 end)
    if not (okarr and scal and type(n) == "number" and n > 0) then
        if first then print("[GlassClear] MID " .. key .. " parent=" .. pf .. " scalar array unreadable") end
        return
    end
    if first then
        local vals = {}
        local cap = n <= 16 and n or 16
        for i = 0, cap - 1 do
            local okv, v = pcall(function() local e = scal[i]; return e and e.ParameterValue end)
            vals[#vals+1] = i .. "=" .. (okv and tostring(v) or "?")
        end
        print("[GlassClear] MID " .. key .. " parent=" .. pf .. " n=" .. n .. " stocks: " .. table.concat(vals, " "))
    end
    if SCAN_ONLY then return end
    local writes = 0
    for _, i in ipairs(INVISIBLE and idx.invis or {}) do
        if i < n then
            local okw = pcall(function() local e = scal[i]; if e then e.ParameterValue = 0.0 end end)
            if okw then writes = writes + 1 end
        end
    end
    for _, i in ipairs(idx.dirt) do
        if i < n then
            local okw = pcall(function() local e = scal[i]; if e then e.ParameterValue = 0.0 end end)
            if okw then writes = writes + 1 end
        end
    end
    if first then
        print("[GlassClear] MID " .. key .. " raw wrote " .. writes ..
            (INVISIBLE and " (dirt+invis)" or " (dirt only)") .. " idx in 0.." .. (n-1))
    end
end

local function act()
    if not dummy_tex then dummy_tex = find_dummy() end
    local ok, mis = pcall(FindAllOf, "MaterialInstanceConstant")
    if ok and mis then
        for _, mi in ipairs(mis) do
            local okn, name = pcall(function() return mi:GetFullName() end)
            if okn and name and is_window_glass(name) then zero_mi(mi, name) end
        end
    end
    local okm, mids = pcall(FindAllOf, "MaterialInstanceDynamic")
    if not (okm and mids) then return end
    for _, mid in ipairs(mids) do
        local okv, v = pcall(mid.IsValid, mid)
        if okv and v then
            local okp, parent = pcall(function() return mid.Parent end)
            if okp and parent and parent:IsValid() then
                local okf, pf = pcall(function() return parent:GetFullName() end)
                if okf and pf and is_window_glass(pf) then
                    local okey, mfn = pcall(function() return mid:GetFullName() end)
                    local key = tostring(mfn)
                    if key ~= "nil" then
                        if not mid_seen[key] then mid_seen[key] = 1 end
                        handle_mid(mid, pf, key)
                    end
                end
            end
        end
    end
end

LoopAsync(1000, function()
    local ok, err = pcall(act)
    if not ok then print("[GlassClear] err: " .. tostring(err)) end
    return false
end)
print("[GlassClear] v36 loaded: scalar zeroing + WHITE dummy tex swap + tex diagnostics, zero engine calls (SCAN_ONLY=" ..
    tostring(SCAN_ONLY) .. ", INVISIBLE=" .. tostring(INVISIBLE) .. ", grace=" .. GRACE_POLLS .. ")")
