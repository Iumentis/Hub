local ScriptsByPlaceId = {
    -- [PlaceId] = raw github URL
    [125517737144798] = "https://raw.githubusercontent.com/Iumentis/Hub/refs/heads/scripts/WordConnect.lua",
    -- [123456789012345] = "https://raw.githubusercontent.com/Iumentis/Hub/refs/heads/scripts/example.lua",
}

local PlaceId = game.PlaceId
local Url = ScriptsByPlaceId[PlaceId]

if not Url then
    print(("Not in Supported Game (PlaceId: %d)"):format(PlaceId))
    return
end

print(("Loading script for PlaceId %d"):format(PlaceId))

local Ok, Body = pcall(function() return game:HttpGet(Url) end)
if not Ok or type(Body) ~= "string" or #Body == 0 then
    warn(("Fetch failed: %s"):format(tostring(Body)))
    return
end

local Fn, Err = loadstring(Body)
if not Fn then
    warn(("Compile error: %s"):format(tostring(Err)))
    return
end

local RunOk, RunErr = pcall(Fn)
if not RunOk then
    warn(("Runtime error: %s"):format(tostring(RunErr)))
    return
end

print(("Loaded successfully"))
