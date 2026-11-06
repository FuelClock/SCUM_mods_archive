-- GlassClear v4: get parameter NAMES (tostring fallback on FName)
local seen = {}
local MAX = 64

local function pname(v)
    if v == nil then return "nil" end
    local ok, r = pcall(function() return v:ToString() end)
    if ok and r and #r > 0 then return r end
    ok, r = pcall(function() return tostring(v) end)
    if ok then return "ts:" .. tostring(r) end
    return "?"
end

local function dump_once()
    local ok, all = pcall(FindAllOf, "MaterialInstanceConstant")
    if not ok or not all then return end
    for _, obj in ipairs(all) do
        local okn, name = pcall(function() return obj:GetFullName() end)
        if okn and name and not seen[name]
        and (name:find("MI_") or name:find("M_")) and name:find("Glass") then
            seen[name] = true
            print("[GlassClear] DUMP " .. name)
            local okt, tex = pcall(function() return obj.TextureParameterValues end)
            if okt and tex then
                local okn2, n = pcall(function() return tex:GetArrayNum() end)
                if okn2 and type(n) == "number" and n <= MAX then
                    for i = 0, n - 1 do
                        local oki, e = pcall(function() return tex[i] end)
                        if oki and e then
                            local nm, pv = "?", "?"
                            pcall(function() nm = pname(e.ParameterName) end)
                            pcall(function()
                                local p = e.ParameterValue
                                if not p or p:IsValid() == false then pv = "None" else pv = p:GetFullName() end
                            end)
                            print("[GlassClear]     tex[" .. i .. "] " .. nm .. " -> " .. pv)
                        end
                    end
                end
            end
            local oks, scal = pcall(function() return obj.ScalarParameterValues end)
            if oks and scal then
                local okn2, n = pcall(function() return scal:GetArrayNum() end)
                if okn2 and type(n) == "number" and n <= MAX then
                    for i = 0, n - 1 do
                        local oki, e = pcall(function() return scal[i] end)
                        if oki and e then
                            local nm, pv = "?", "?"
                            pcall(function() nm = pname(e.ParameterName) end)
                            pcall(function() pv = tostring(e.ParameterValue) end)
                            print("[GlassClear]     scal[" .. i .. "] " .. nm .. " = " .. pv)
                        end
                    end
                end
            end
        end
    end
end

local t = 0
LoopAsync(500, function()
    t = t + 1
    local ok, err = pcall(dump_once)
    if not ok then print("[GlassClear] dump error: " .. tostring(err)) end
    return t > 600
end)
print("[GlassClear] v4 watcher started")
