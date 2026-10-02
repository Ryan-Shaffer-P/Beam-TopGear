-- Settings tab (0.9.6): every player's own sound, start lights / finish flag placement and tests, colour theme and
-- diagnostics - moved off the Status tab. (The fake ImGui draws every tab, in order; tabs show as "[Name]".)
local t = require("t")
local World = require("world")
local F = require("fixtures")

local WIN = "Top Gear Challenge"
local function tab(p, name)   -- the text of one tab: from its "[Name]" marker to the next tab's
  local s = p.client.im.textOf(WIN)
  local tabs = {}
  for _, it in ipairs(p.client.im.items(WIN)) do if it.kind == "tab" then tabs[#tabs + 1] = it.label end end
  local from = s:find("[" .. name .. "]", 1, true)
  if not from then return nil, tabs end
  local to = #s + 1
  for _, other in ipairs(tabs) do
    local at = s:find("[" .. other .. "]", from + 1, true)
    if at and at < to then to = at end
  end
  return s:sub(from, to - 1), tabs
end

t.test("every player gets a Settings tab, last, with sound, lights/flag, theme and diagnostics", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")   -- Alice is the admin, Bob isn't
  w:chat(A, "/tg start")
  w:step(2.5)
  local s, tabs = tab(B, "Settings")
  t.ok(s, "Bob has a Settings tab")
  t.eq(tabs[#tabs], "Settings", "it's the last tab")
  for _, b in ipairs({ "Sounds: ON - turn off", "Test sound", "Not hearing it? Try another way", "Position the start lights",
                       "Test them", "Position the finish flag", "Test it", "Colour theme: ON - turn off", "Diagnostics",
                       "Parts tab diagnostics" }) do
    t.ok(s:find("[" .. b .. "]", 1, true), "Settings has " .. b)
  end
  local _, atabs = tab(A, "Settings")
  t.eq(atabs[#atabs], "Settings", "after Admin for an admin too")
  for _, pl in ipairs({ A, B }) do
    local st = tab(pl, "Status")
    t.ok(not st:find("Position the start lights", 1, true) and not st:find("Sounds:", 1, true), "gone from Status")
  end
  w:assertClean()
end)

t.test("Settings buttons work: mute only you, theme toggles, tests and diagnostics run", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:step(2.5)
  B.client.im.click("Sounds: ON - turn off##sounds")
  w:step(2.5)
  t.ok(w:chatHas(B, "Sounds OFF for you."))
  t.ok(tab(B, "Settings"):find("[Sounds: OFF - turn on]", 1, true))
  t.ok(tab(A, "Settings"):find("[Sounds: ON - turn off]", 1, true), "Alice's sound is unchanged")

  B.client.im.click("Colour theme: ON - turn off##theme")
  w:step(2.5)
  t.ok(tab(B, "Settings"):find("[Colour theme: OFF - turn on]", 1, true))
  B.client.im.click("Colour theme: OFF - turn on##theme")
  w:step(2.5)
  t.ok(tab(B, "Settings"):find("[Colour theme: ON - turn off]", 1, true))

  B.client.im.click("Test them##lightstest"); w:step(1)
  B.client.im.click("Test it##flagtest"); w:step(1)
  B.client.im.click("Diagnostics##diag"); w:step(2)
  t.ok(w:chatHas(B, "client mod v"), "diagnostics reply in chat")
  w:assertClean()
end)
