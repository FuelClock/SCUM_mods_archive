-- SkipCutscenes v6: UE4SS Lua mod for SCUM.
-- v5 lesson (UE4SS.log 01:44): menu-map gate works (menu camera untouched,
-- actions=0 outside gate). While the intro played (~12.5s), NO non-menu
-- sequence player existed under any probed class -> the cutscene is driven
-- by SCUM's NATIVE CutsceneWidget controller (/Script/SCUM, exe packed).
-- v3 note: Stop() succeeded while Close() failed, with the error text hidden.
-- v6 (diagnosis + one candidate):
--   1. probe native class "CutsceneWidget" (the controller) while playing
--   2. while playing: call Close() on the Bink player ONCE and log the
--      FULL pcall error (if Close succeeds the controller may advance;
--      if not, the error names the real signature)
--   3. read GetTime/GetTimeEnd while playing (progress visibility)
--   4. keep v5's protections: never touch menu-map sequences, Bink is the
--      only object modified, and only while a cutscene is playing

local POLL_MS = 250

local loggedNames = {}
local invalidLogged = false
local counters = { polls = 0, census = {} }
local binkPlaying = false
local playId = 0
local closeTried = false

local function log(msg)
    print(string.format("[SkipCutscenes] %s", tostring(msg)))
end

log("mod loaded (v6)")

local function keyOf(obj)
    local name = "?"
    local ok = pcall(function() name = obj:GetFullName() end)
    if not ok then return false, "?" end
    if name == nil then name = "?" end
    return true, name
end

local function isValidObj(obj)
    local okV, valid = pcall(function() return obj:IsValid() end)
    if okV and valid == false then return false end
    local okName, name = keyOf(obj)
    if not okName or name == "?" then return false end
    return true, name
end

-- Probe the native controller class + the BP widget classes while playing.
local function probeController()
    for _, cls in ipairs({ "CutsceneWidget", "UI_Parent_CutsceneWidget_C",
                           "UI_Child_IntroCutsceneWidget_C" }) do
        local ok, obj = pcall(function() return FindFirstOf(cls) end)
        if ok and obj ~= nil then
            local okN, name = isValidObj(obj)
            if okN then
                log(string.format("CONTROLLER probe %s found: %s", cls, name))
            else
                log(string.format("CONTROLLER probe %s: found but invalid", cls))
            end
        else
            log(string.format("CONTROLLER probe %s: not found", cls))
        end
    end
end

local function observeBink(player)
    local ok, name = isValidObj(player)
    if not ok then return false end
    local okP, playing = pcall(function() return player:IsPlaying() end)
    if not ok then return false end

    if playing and not binkPlaying then
        playId = playId + 1
        closeTried = false
        log(string.format("BINK PLAYING #%d: %s", playId, name))
        probeController()
    elseif not playing and binkPlaying then
        log(string.format("BINK idle after play #%d (natural end or skipped)",
            playId))
    end
    binkPlaying = playing

    if playing then
        -- progress read (safe, read-only)
        local tOk, t = pcall(function() return player:GetTime() end)
        local eOk, e = pcall(function() return player:GetTimeEnd() end)
        if tOk and eOk and not closeTried then
            log(string.format("BINK time=%.3f end=%.3f", tostring(t), tostring(e)))
        end
        -- the one candidate: Close, once per play, full error captured
        if not closeTried then
            closeTried = true
            local cOk, cErr = pcall(function() player:Close() end)
            log(string.format("BINK Close()=%s %s", tostring(cOk),
                cErr and (": " .. tostring(cErr)) or "(no error)"))
        end
    end
    return playing
end

-- Census: log construction of cutscene-widget / player classes (diagnostic).
local CENSUS_CLASSES = {
    "CutsceneWidget", "UI_Parent_CutsceneWidget_C",
    "UI_Child_IntroCutsceneWidget_C", "MovieSceneSequencePlayer",
    "LevelSequencePlayer", "BinkMediaPlayer",
}
for _, cls in ipairs(CENSUS_CLASSES) do
    pcall(function()
        NotifyOnNewObject(cls, function(obj)
            counters.census[cls] = (counters.census[cls] or 0) + 1
            if counters.census[cls] <= 5 then
                local _, name = keyOf(obj)
                log(string.format("CONSTRUCT %s: %s", cls, tostring(name)))
            end
        end)
    end)
end

local function poll()
    counters.polls = counters.polls + 1

    local playing = false
    local binks = FindAllOf("BinkMediaPlayer")
    if binks ~= nil then
        for _, b in ipairs(binks) do
            if observeBink(b) then playing = true end
        end
    end
    if observeBink(FindFirstOf("BinkMediaPlayer")) then playing = true end

    if counters.polls % 20 == 0 then
        local parts = {}
        for cls, n in pairs(counters.census) do
            parts[#parts + 1] = string.format("%s=%d", cls, n)
        end
        log(string.format("summary poll=%d census[%s]",
            counters.polls, table.concat(parts, " ")))
    end
end

LoopAsync(POLL_MS, poll)
