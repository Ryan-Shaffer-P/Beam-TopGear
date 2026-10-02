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
  t.eq(firstTab(A), "Quick start", "the far-left tab")
  t.eq(A.client.im.selectedTabs["Quick start"], 1, "selected when the menu opens")

  local q = tab(A, "Quick start")
  for _, s in ipairs({ "1. What course do you want to load?", "2. What is the budget?", "3. What type of cars do you want to drive?",
                       "[Start the challenge]", "[Car condition (after Start)]", "[Go to the dealer]" }) do
    t.ok(has(q, s), "Quick start has " .. s)
  end
  t.ok(has(tab(B, "Quick start"), "Waiting for an admin to set up and start the challenge."), "players wait")
  t.ok(not has(tab(B, "Quick start"), "1. What course"), "the questions are the admin's")

  A.client.im.click("Twin"); w:step(2.5)   -- 1. course dropdown
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
  t.ok(has(tab(A, "Quick start"), "[Start the challenge  (done)]"))
  w:assertClean()
end)

t.test("quick start: condition dropdown lights after Start, the dealer button after a condition", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg course save Twin")
  w:chat(A, "/tg start"); w:step(2.5)
  local q = tab(B, "Quick start")
  t.ok(has(q, "[Start the challenge  (done)]"))
  t.ok(combo(B, "Pick a condition..."), "the condition dropdown is up")
  t.ok(has(q, "Pick a car condition first."))
  B.client.im.click("Go to the dealer##qdealer"); w:step(1)
  t.eq(B.client.selectorOpened or 0, 0, "not lit yet: no selector")

  local lv = w:ui(B).faults.levels[4]   -- Beater
  B.client.im.click(string.format("%s  (%d%% off)", lv.name, lv.off)); w:step(2.5)
  t.ok(w:chatHas(B, "Car condition: " .. lv.name))
  q = tab(B, "Quick start")
  t.ok(not has(q, "Pick a car condition first."))
  t.ok(has(q, "Opens the vehicle selector"), "the dealer button is lit")
  B.client.im.click("Go to the dealer##qdealer"); w:step(1)
  t.eq(B.client.selectorOpened, 1, "opens the game's vehicle selector")

  -- New is a real choice too: picking it (no change) still lights the dealer
  A.client.im.click("New  (full price)"); w:step(2.5)
  t.ok(has(tab(A, "Quick start"), "Opens the vehicle selector"))

  w:buy(B, "pessima", "base_M"); w:step(2.5)
  q = tab(B, "Quick start")
  t.ok(has(q, "[Car condition: " .. lv.name .. "  (done)]"))
  t.ok(has(q, "[Go to the dealer - you bought the "), "bought: done")
  w:assertClean()
end)

t.test("quick start: Start stays grey until a finished course is loaded; later phases point to Status", function()
  local w = World.new({ files = F.files(F.config({ { name = "Empty", type = "race", timeLimit = 300, via = {} } })) })
  local A = w:join("Alice")
  w:chat(A, "/tg course save Half"); w:chat(A, "/tg menu"); w:step(2.5)
  t.ok(has(tab(A, "Quick start"), "isn't finished"))
  t.ok(has(tab(A, "Quick start"), "Load a finished course first."))
  A.client.im.click("Start the challenge##qstart"); w:step(2.5)
  t.eq(w:ui(A).phase, "idle", "grey Start does nothing")
  w:assertClean()

  local w2 = World.new({ files = F.files(F.twoRaces()) })
  local A2, B2 = w2:join("Alice"), w2:join("Bob")
  w2:chat(A2, "/tg start"); w2:step(1)
  w2:buy(A2, "covet", "base_M"); w2:buy(B2, "pessima", "base_M")
  w2:chat(A2, "/tg next"); w2:step(2.5)   -- dealership closes: travel
  t.ok(has(tab(B2, "Quick start"), "The challenge is under way - the Status tab has the rest."))
  w2:assertClean()
end)
