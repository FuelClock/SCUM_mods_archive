-- QuestCompleteHotkey v1 for SCUM (UE4SS Lua) - prebuilt 2026-11-06
-- GOAL (user decision 2026-11-06): press Numpad0 -> the ACTIVE quest is
--   ADVANCED step-by-step until it completes (NOT a one-shot outright
--   completion). One press = one advance grind run: we call Client_AdvanceQuest
--   repeatedly (paced one per poll tick) until the quest leaves activeQuests
--   or MAX_ADVANCES_PER_PRESS is hit.
-- v1 is a DIAGNOSTIC BUILD: DEBUG=true. It (a) probes which Numpad0 key enum
--   name exists on this UE4SS install (NUM_PAD_* names logged "no-key" once
--   before), (b) discovers the live object owning activeQuests
--   (_playerQuestComponent property seen in SCUM.exe strings; owner unknown),
--   (c) attempts the advance call and logs every error so v2 is informed by
--   ONE boot paste instead of blind iterations.
--
-- INSTALL (exact path - a wrong dir is silently ignored):
--   SCUM/SCUM/Binaries/Win64/ue4ss/Mods/QuestCompleteHotkey/
--     Scripts/main.lua   <- this file
--     enable.txt         <- empty file
--   and add to Mods/mods.txt:  QuestCompleteHotkey : 1
--
-- VERIFY (one grep):
--   grep -E "\[QCH\]" UE4SS.log
--   Look for: "v1 loaded", "hotkey bound"/"no-key" lines, "quest owner:",
--   "activeQuests:", "PRESS", "ADVANCE", heartbeat lines every ~30s.
--
-- Rebind: change KEY_CANDIDATES/MOD_FALLBACK below. DEBUG=false once working.

local TAG = "[QCH]"
local DEBUG = true   -- diagnostic build; flip to false when the flow is proven
local POLL_MS = 500
local HEARTBEAT_TICKS = 60          -- every 60 ticks (~30s) so a dead loop is visible in one paste
local MAX_ADVANCES_PER_PRESS = 20   -- safety cap per press
local SANITY_CAP = 20               -- hard cap for ANY array walk (crash guard)

-- Keybind candidates for Numpad0. The FIRST existing one gets the plain bind;
-- the first existing one ALSO gets a Ctrl+Shift fallback (survives even if
-- the game eats the plain one). Previous attempt: NUM_PAD_ONE logged "no-key".
local KEY_CANDIDATES = {
    "KEY_NUMPAD0", "KEY_NUM_ZERO", "KEY_NUMPAD_ZERO", "KEY_PAD_ZERO", "KEY_0",
}
local MOD_FALLBACK = { ModifierKey.CONTROL, ModifierKey.SHIFT }

local function log(s) if DEBUG then print(TAG .. " " .. s) end end
local function logAlways(s) print(TAG .. " " .. s) end

logAlways("v1 loaded (advance-until-complete on Numpad0 | debug=" .. tostring(DEBUG) .. ")")

-- ---------------------------------------------------------------- helpers
local function valid(a)
    local ok, v = pcall(function() return a:IsValid() end)
    return ok and v
end

local function fullName(a)
    local okN, fn = pcall(function() return a:GetFullName() end)
    if okN and fn then return fn end
    local ok2, n2 = pcall(function() return a:GetName() end)
    if ok2 and n2 then return n2 end
    return "<name unreadable>"
end

local function readProp(obj, prop)
    if obj == nil then return nil end
    local ok, v = pcall(function() return obj[prop] end)
    if ok then return v end
    return nil
end

-- Bounded array read: returns { ok, count, {elements} } - ipairs is FORBIDDEN
-- on engine arrays (walks past the end, hard crash).
local function readArray(arr)
    if arr == nil then return false, 0, nil end
    local okN, n = pcall(function() return arr:GetArrayNum() end)
    if not okN or type(n) ~= "number" then return false, 0, nil end
    local items = {}
    local cap = n
    if cap > SANITY_CAP then cap = SANITY_CAP end
    for i = 0, cap - 1 do
        local okE, e = pcall(function() return arr[i] end)
        if okE and e ~= nil then items[#items + 1] = e end
    end
    return true, n, items
end

-- ------------------------------------------------------------- keybinds
local pressQueued = false
local anyBound = false
local boundNames = {}

local function onPress(name)
    pressQueued = true
    logAlways("PRESS via " .. tostring(name) .. " - queued (executes on game thread)")
end

if type(Key) == "table" or type(Key) == "userdata" then
    for _, name in ipairs(KEY_CANDIDATES) do
        local k = Key[name]
        if k ~= nil then
            local ok, err = pcall(RegisterKeyBind, k, function() onPress(name) end)
            if ok then
                anyBound = true
                boundNames[#boundNames + 1] = name
                logAlways("hotkey PLAIN " .. name .. " bound")
            else
                logAlways("hotkey PLAIN " .. name .. " BIND FAILED: " .. tostring(err))
            end
        else
            logAlways("no-key " .. name .. " (enum name does not exist on this UE4SS)")
        end
    end
    -- modifier fallback: register Ctrl+Shift+<first existing candidate>
    for _, name in ipairs(KEY_CANDIDATES) do
        local k = Key[name]
        if k ~= nil then
            local ok, err = pcall(RegisterKeyBind, k, MOD_FALLBACK, function() onPress(name .. " +Ctrl+Shift") end)
            logAlways("hotkey FALLBACK Ctrl+Shift+" .. name .. " " .. (ok and "bound" or "BIND FAILED: " .. tostring(err)))
            if ok then anyBound = true end
            break
        end
    end
else
    logAlways("Key table unavailable on this UE4SS build - no binds possible")
end
if not anyBound then
    logAlways("NO KEY BOUND - edit KEY_CANDIDATES and restart")
end

-- --------------------------------------------------- quest-owner discovery
-- Candidates for whoever owns activeQuests / _playerQuestComponent.
local OWNER_CLASSES = { "PlayerController", "PlayerState", "QuestManager" }
local QUEST_PROPS = { "_playerQuestComponent", "PlayerQuestComponent", "activeQuests", "ActiveQuest" }

local discovered = nil   -- { holder=..., holderName=..., qc=..., via=... }
local discoveredWorld = nil

-- Describe the active-quest list: names + one deep-ish look at element 1.
local function describeQuests(qList)
    local ok, n, items = readArray(qList)
    if not ok then
        log("activeQuests: unreadable (GetArrayNum failed)")
        return 0, nil
    end
    log("activeQuests: count=" .. tostring(n))
    for i, e in ipairs(items) do
        log("  quest[" .. i .. "]: " .. (type(e) == "userdata" and fullName(e) or tostring(e)))
    end
    return n, items[1]
end

local function findOwner()
    local holder, holderName, via = nil, nil, nil
    for _, cls in ipairs(OWNER_CLASSES) do
        local ok, list = pcall(FindAllOf, cls)
        if ok and list ~= nil then
            local cap = #list
            if cap > SANITY_CAP then cap = SANITY_CAP end
            for i = 1, cap do
                local obj = list[i]
                if obj ~= nil and valid(obj) then
                    for _, prop in ipairs(QUEST_PROPS) do
                        local v = readProp(obj, prop)
                        if v ~= nil then
                            holder = obj
                            holderName = fullName(obj)
                            via = cls .. "." .. prop
                            if prop == "activeQuests" then
                                -- already the list itself
                                discovered = { holder = obj, holderName = holderName, via = via, qList = v }
                                logAlways("quest owner: " .. holderName .. " (via " .. via .. ")")
                                describeQuests(v)
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    -- second pass: component holders (property gave us the component, list lives there)
    for _, cls in ipairs(OWNER_CLASSES) do
        local ok, list = pcall(FindAllOf, cls)
        if ok and list ~= nil then
            local cap = #list
            if cap > SANITY_CAP then cap = SANITY_CAP end
            for i = 1, cap do
                local obj = list[i]
                if obj ~= nil and valid(obj) then
                    local qc = readProp(obj, "_playerQuestComponent") or readProp(obj, "PlayerQuestComponent")
                    if qc ~= nil and valid(qc) then
                        for _, prop in ipairs({ "activeQuests", "ActiveQuest" }) do
                            local v = readProp(qc, prop)
                            if v ~= nil then
                                logAlways("quest owner: " .. fullName(qc) .. " (component of " .. fullName(obj) .. ", via " .. prop .. ")")
                                describeQuests(v)
                                discovered = { holder = qc, holderName = fullName(qc), via = prop, qList = v }
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- -------------------------------------------------------- advance the quest
local pressActive = false       -- a press is being ground
local advancesDone = 0
local lastQuestKey = nil

local function tryAdvance(holder, questRef)
    -- signature unknown in v1: try the plausible call forms, log every error.
    -- 1) holder:Client_AdvanceQuest(quest)
    local ok, err = pcall(function() holder:Client_AdvanceQuest(questRef) end)
    if ok then return "holder:Client_AdvanceQuest(quest) ok" end
    -- 2) quest object carries the call
    if type(questRef) == "userdata" then
        local ok2, err2 = pcall(function() questRef:Client_AdvanceQuest(questRef) end)
        if ok2 then return "quest:Client_AdvanceQuest(self) ok" end
    end
    return nil, tostring(err)
end

local function questListCount(holder)
    local qList = readProp(holder, "activeQuests")
    if qList == nil and discovered ~= nil then qList = discovered.qList end
    local ok, n = pcall(function() return qList:GetArrayNum() end)
    if ok and type(n) == "number" then return n end
    return nil
end

-- ------------------------------------------------------------- poll loop
-- CONTRACT (proven FogKiller pattern): callback MUST return false to keep
-- looping; returning true silently kills the poll after one tick.
local tick = 0
LoopAsync(POLL_MS, function()
    tick = tick + 1
    if tick % HEARTBEAT_TICKS == 0 then
        log(string.format("heartbeat tick=%d (pressQueued=%s, grinding=%s)", tick, tostring(pressQueued), tostring(pressActive)))
    end

    -- world gate (proven pattern)
    local okG, gs = pcall(FindFirstOf, "GameState")
    local inWorld = okG and gs ~= nil and valid(gs)
    if not inWorld then
        discovered = nil
        discoveredWorld = nil
        pressActive = false
        return false
    end

    -- discover the owner once per world
    local okW, wname = pcall(function() return gs:GetFullName() end)
    if discovered == nil and okW and wname ~= discoveredWorld then
        discoveredWorld = wname
        log("discovering quest owner for world " .. tostring(wname) .. " ...")
        findOwner()
    end

    -- execute a queued press
    if pressQueued then
        pressQueued = false
        if discovered == nil then
            logAlways("PRESS but no quest owner discovered yet - cannot advance")
        else
            local n, first = describeQuests(readProp(discovered.holder, "activeQuests") or discovered.qList)
            if n == 0 then
                logAlways("PRESS but activeQuests is EMPTY - no active quest to advance")
            else
                pressActive = true
                advancesDone = 0
                if type(first) == "userdata" then lastQuestKey = fullName(first) else lastQuestKey = tostring(first) end
                logAlways("ADVANCE grind started on: " .. tostring(lastQuestKey) .. " (cap " .. MAX_ADVANCES_PER_PRESS .. ")")
            end
        end
    end

    -- grind: ONE advance attempt per tick, paced
    if pressActive and discovered ~= nil then
        local qList = readProp(discovered.holder, "activeQuests") or discovered.qList
        local ok, n, items = readArray(qList)
        if not ok or n == 0 or #(items or {}) == 0 then
            pressActive = false
            logAlways("QUEST COMPLETED - left activeQuests after " .. advancesDone .. " advance call(s)")
        else
            local target = items[1]
            local res, err = tryAdvance(discovered.holder, target)
            advancesDone = advancesDone + 1
            if res then
                log("ADVANCE #" .. advancesDone .. ": " .. res)
            else
                log("ADVANCE #" .. advancesDone .. " FAILED (all call forms): " .. tostring(err))
            end
            if advancesDone >= MAX_ADVANCES_PER_PRESS then
                pressActive = false
                logAlways("ADVANCE cap " .. MAX_ADVANCES_PER_PRESS .. " reached - quest still in activeQuests (see FAILED lines)")
            end
        end
    end

    return false
end)
