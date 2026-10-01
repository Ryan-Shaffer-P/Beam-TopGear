-- Loads the Top Gear Challenge client extension (lua/ge/extensions/topgear.lua).
-- Every step is logged: open the game console (~) and filter for "topgear".
local function say(level, msg) pcall(log, level, "topgear", "modScript: " .. msg) end
say("I", "running")

local ok, err = pcall(function()
  if extensions and extensions.load then
    extensions.load("topgear")
  else
    load("topgear")  -- older mod-script shorthand
  end
end)
if ok then say("I", "extension load requested") else say("E", "extension load FAILED: " .. tostring(err)) end

-- keep it loaded across level changes
local ok2, err2 = pcall(function()
  if setExtensionUnloadMode then
    setExtensionUnloadMode("topgear", "manual")
  elseif extensions and extensions.setExtensionUnloadMode then
    extensions.setExtensionUnloadMode("topgear", "manual")
  end
end)
if not ok2 then say("W", "unload mode not set: " .. tostring(err2)) end
