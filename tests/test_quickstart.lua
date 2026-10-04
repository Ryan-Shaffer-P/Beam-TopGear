-- Quick start tab (0.9.12): the first tab. An admin answers course / budget / cars and presses Start; then each player
-- picks a car condition and goes to the dealer. A step only lights up (and only acts) once the one before is done.
local t = require("t")
local World = require("world")
local F = require("fixtures")

local WIN = "Top Gear Challenge"
local function tab(p, name)   -- the text of one tab: from its "[Name]" marker to the next tab's
  local s = p.client.im.textOf(WIN)
  local from = assert(s:find("[" .. name .. "]", 1, true), "no " .. name .. " tab")
  local to = #s + 1
  for _, it in ipairs(p.client.im.items(WIN)) do
    if it.kind == "tab" and it.label ~= name then
      local at = s:find("[" .. it.label .. "]", from + 1, true)
      if at and at < to then to = at end
    end
  end
  return s:sub(from, to - 1)
end
local function firstTab(p)
  for _, it in ipairs(p.client.im.items(WIN)) do if it.kind == "tab" then return it.label end end
end
local function combo(p, preview)   -- a dropdown showing this preview
  for _, it in ipairs(p.client.im.items(WIN)) do if it.kind == "combo" and it.preview == preview then return true end end
  return false
end
local function has(s, text) return s:find(text, 1, true) ~= nil end

t.test("quick start: admin picks course, budget and cars, Start lights up and starts it", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")   -- Alice is the admin
  w:chat(A, "/tg course save Twin"); w:chat(A, "/tg course save Other")   -- two saved courses; Other is loaded
  w:chat(A, "/tg menu"); w:chat(B, "/tg menu"); w:step(2.5)
  t.eq(firstTab(A), "Start", "the far-left tab")
  t.eq(A.client.im.selectedTabs["Start"], 1, "selected when the menu opens")

  local q = tab(A, "Start")
  for _, s in ipairs({ "1. What course do you want to load?", "2. What is the budget?", "3. What type of cars do you want to drive?",
                       "[Start the challenge]", "[Car condition (after Start)]", "[Go to the dealer]" }) do
    t.ok(has(q, s), "Start has " .. s)
  end
  t.ok(has(tab(B, "Start"), "Waiting for an admin to set up and start the challenge."), "players wait")
  t.ok(not has(tab(B, "Start"), "1. What course"), "the questions are the admin's")

  A.client.im.click("Twin"); w:step(0.5)   -- 1. course dropdown, then Load
  t.eq(w:ui(A).course.active, "Other", "picking doesn't load it yet")
  A.client.im.click("Load##qload"); w:step(2.5)
  t.eq(w:ui(A).course.active, "Twin")
  local pr = w:ui(A).classes.presets[1]   -- 3. a ready-made class: made, then used
  A.client.im.click(string.format("%s (%s cars)", pr.title, tostring(pr.count))); w:step(2.5)
  t.eq(w:ui(A).classes.active, pr.key)
  t.ok(w:chatHas(A, "Made class " .. pr.key))
  -- (this test world has no imported cars, so that class is empty and wouldn't start: back to Any car, a pick too)
  A.client.im.click("Any car (" .. w:ui(A).classes.none .. ")"); w:step(2.5)
  t.eq(w:ui(A).classes.active, nil)
  A.client.im.setInt("Budget##qbudget", 9000)   -- 2. budget: sent with Start

  B.client.im.click("Start the challenge##qstart"); w:step(2.5)
  t.eq(w:ui(B).phase, "idle", "a player's Start does nothing")
  A.client.im.click("Start the challenge##qstart"); w:step(2.5)
  t.eq(w:ui(A).phase, "dealer")
  t.eq(w:ui(A).baseBudget, 9000, "the budget went over first")
  t.eq(w:state(B).cash, 9000)
  t.ok(has(tab(A, "Start"), "[Start the challenge  (done)]"))
  w:assertClean()
end)

t.test("quick start: condition dropdown lights after Start, the dealer button after a condition", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg course save Twin")
  w:chat(A, "/tg start"); w:step(2.5)
  local q = tab(B, "Start")
  t.ok(has(q, "[Start the challenge  (done)]"))
  t.ok(combo(B, "Pick a condition..."), "the condition dropdown is up")
  t.ok(has(q, "Pick a car condition first."))
  B.client.im.click("Go to the dealer##qdealer"); w:step(1)
  t.eq(B.client.selectorOpened or 0, 0, "not lit yet: no selector")

  local lv = w:ui(B).faults.levels[4]   -- Beater
  B.client.im.click(string.format("%s  (%d%% off)", lv.name, lv.off)); w:step(2.5)
  t.ok(w:chatHas(B, "Car condition: " .. lv.name))
  q = tab(B, "Start")
  t.ok(not has(q, "Pick a car condition first."))
  t.ok(has(q, "Opens the vehicle selector"), "the dealer button is lit")
  B.client.im.click("Go to the dealer##qdealer"); w:step(1)
  t.eq(B.client.selectorOpened, 1, "opens the game's vehicle selector")

  -- New is a real choice too: picking it (no change) still lights the dealer
  A.client.im.click("New  (full price)"); w:step(2.5)
  t.ok(has(tab(A, "Start"), "Opens the vehicle selector"))

  w:buy(B, "pessima", "base_M"); w:step(2.5)
  q = tab(B, "Start")
  t.ok(has(q, "[Car condition: " .. lv.name .. "  (done)]"))
  t.ok(has(q, "[Go to the dealer - you bought the "), "bought: done")
  w:assertClean()
end)

t.test("quick start: Start stays grey until a finished course is loaded; later phases point to Status", function()
  local w = World.new({ files = F.files(F.config({ { name = "Empty", type = "race", timeLimit = 300, via = {} } })) })
  local A = w:join("Alice")
  w:chat(A, "/tg course save Half"); w:chat(A, "/tg menu"); w:step(2.5)
  t.ok(has(tab(A, "Start"), "isn't finished"))
  t.ok(has(tab(A, "Start"), "Load a finished course first."))
  A.client.im.click("Start the challenge##qstart"); w:step(2.5)
  t.eq(w:ui(A).phase, "idle", "grey Start does nothing")
  w:assertClean()

  local w2 = World.new({ files = F.files(F.twoRaces()) })
  local A2, B2 = w2:join("Alice"), w2:join("Bob")
  w2:chat(A2, "/tg start"); w2:step(1)
  w2:buy(A2, "covet", "base_M"); w2:buy(B2, "pessima", "base_M")
  w2:chat(A2, "/tg next"); w2:step(2.5)   -- dealership closes: travel
  t.ok(has(tab(B2, "Start"), "The challenge is under way - the Status tab has the rest."))
  w2:assertClean()
end)

t.test("window layout: Start | Status | Dealership | Admin | Settings, each a stack of bordered boxes; admin boxes start folded", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start"); w:step(2.5)   -- (the window opens itself for the dealership)
  local tabs, heads = {}, {}
  for _, it in ipairs(A.client.im.items(WIN)) do
    if it.kind == "tab" then tabs[#tabs + 1] = it.label end
    if it.kind == "header" then heads[it.label] = it.flags end
  end
  t.eq(table.concat(tabs, "|"), "Start|Status|Dealership|Admin|Settings")
  for _, h in ipairs({ "Setup", "Dealer", "My car", "Standings", "Buy a car", "Car condition", "Today's cars", "Challenge",
                       "Sound", "Messages" }) do
    t.ok(heads[h] and heads[h] ~= 0, h .. ": a box, open")
  end
  for _, h in ipairs({ "Players", "Money & timers", "Car classes", "Tools", "Course" }) do t.eq(heads[h], 0, h .. ": folded") end
  local outlines = 0
  for _, r in ipairs(A.client.im.lastFrame.rects) do if r.outline then outlines = outlines + 1 end end
  t.ok(outlines >= 15, "a rounded border round every box: " .. outlines)
  t.ok(tab(A, "Status"):find("Tow and Respawn need two clicks", 1, true), "the help notes are behind a (?)")
  w:assertClean()
end)

t.test("Start tab: Return this car - two clicks give a full refund, then you can pick again", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start"); w:chat(B, "/tg condition used"); w:step(2.5)
  t.ok(has(tab(B, "Start"), "[Return this car]"), "grey until you own one")
  w:buy(B, "covet", "base_M"); w:step(2.5)
  t.eq(w:state(B).cash, 10000 - 4100)
  B.client.im.click("Return this car - full refund##qreturn"); w:step(0.5)
  t.ok(has(tab(B, "Start"), "[Really? Click again to return it]"), "asks first")
  t.ok(B.current, "still has the car")
  B.client.im.click("Really? Click again to return it##qreturn"); w:step(2.5)
  t.eq(B.current, nil, "returned")
  t.eq(w:state(B).cash, 10000, "full refund")
  w:assertClean()
end)
