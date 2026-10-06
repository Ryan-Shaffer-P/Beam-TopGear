-- Quirks (0.9.29, Ryan: "more variety, even cosmetic or silly"): harmless extras a worn car comes with - a fan belt,
-- a possessed radio, backfires, engine knock, squeaky brakes, flickering lights, a haunted horn, hazards, smells.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local WIN = "Top Gear Challenge"
local function count(list, x) local n = 0 for _, v in ipairs(list) do if v == x then n = n + 1 end end return n end
local function has(list, pat) for _, v in ipairs(list) do if tostring(v):find(pat, 1, true) then return true end end return false end

-- every quirk, every 5 s, a Death Trap gets them all (the test's settings)
local function everyFive()
  local cfg = F.twoRaces()
  local list = {}
  for _, q in ipairs(World.new():serverConfig().quirks.list) do
    if q.every then q.every = { 5, 5 } end
    list[#list + 1] = q
  end
  cfg.quirks = { enabled = true, count = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { #list, #list } }, list = list, fixCost = 150 }
  cfg.workshopEvery = 1
  return cfg
end
local function deathTrap(w, A, others)
  w:chat(A, "/tg start"); w:chat(A, "/tg condition death trap")
  w:buy(A, "covet", "base_M")
  for i, o in ipairs(others) do w:buy(o, ({ "pessima", "miramar" })[i], "base_M") end
  w:step(3)
  w:chat(A, "/tg ready"); for _, o in ipairs(others) do w:chat(o, "/tg ready") end
  w:step(1)
end

t.test("worse cars come with more quirks: none New, up to 1 Used .. 2-3 a Death Trap; shown in the Status tab", function()
  local function quirksFor(cond)
    local cfg = F.twoRaces(); cfg.quirks = { enabled = true }
    local w = World.new({ files = F.files(cfg) })
    local A = w:join("Alice")
    w:chat(A, "/tg start"); w:chat(A, "/tg condition " .. cond); w:buy(A, "covet", "base_M"); w:step(2.5)
    return #((w:ui(A).me or {}).quirks or {}), w, A
  end
  for _ = 1, 6 do
    local n = quirksFor("death trap"); t.ok(n >= 2 and n <= 3, "a Death Trap: 2-3 (" .. n .. ")")
    n = quirksFor("used"); t.ok(n <= 1, "Used: 0-1 (" .. n .. ")")
  end
  local n, w, A = quirksFor("new")
  t.eq(n, 0, "New: none")
  local n2, w2, A2 = quirksFor("death trap")
  t.ok(A2.client.im.textOf(WIN):find("Quirks: ", 1, true), "listed under My car")
  w:assertClean(); w2:assertClean()
end)

t.test("on the road, each quirk has its go: nearby players hear the sounds, far ones don't; horn, lights, hazards, smells", function()
  local w = World.new({ files = F.files(everyFive()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  deathTrap(w, A, { B, C })
  w:place(C, p(-3000)); w:step(1)   -- (Carol is far away)
  for _, pl in ipairs({ A, B, C }) do pl.client.sounds = {} end
  A.current.sfx, A.current.controls = {}, {}
  w:driveAll({ { A, p(800, 0), 8 }, { B, p(800, 20), 8 } })   -- 100 s side by side: every quirk goes several times
  t.ok(count(w:heard(A), "fan-belt-squeal") >= 3 and count(w:heard(B), "fan-belt-squeal") >= 3, "the fan belt: Alice and Bob")
  t.ok(count(w:heard(B), "randomradio") >= 1, "the radio")
  t.eq(count(w:heard(C), "fan-belt-squeal"), 0, "not Carol, 3 km away")
  t.ok(has(A.current.sfx, "Afterfire"), "backfires (BeamNG's own afterfire sound)")
  t.ok(has(A.current.sfx, "failure_engine_knock"), "engine knock")
  t.ok(#A.current.sfx >= 2 * 3, "played on Alice's car by both games (hers and Bob's copy)")
  t.ok(has(A.current.controls, "horn true") and has(A.current.controls, "horn false"), "the horn toots, and stops")
  t.ok(has(A.current.controls, "flash true") and has(A.current.controls, "flash false"), "lights off: the high beams flash")
  t.ok(has(A.current.controls, "hazards true"), "the hazards come on")
  local smelt = false
  for _, l in ipairs(B.chat) do if l:find("Alice's car", 1, true) or l:find("in Alice's car", 1, true) then smelt = true end end
  t.ok(smelt, "a mystery smell in chat")
  w:assertClean()
end)

t.test("parked: only the radio, the horn and the smell go - the rest wait until you're moving", function()
  local w = World.new({ files = F.files(everyFive()) })
  local A = w:join("Alice")
  deathTrap(w, A, {})
  A.client.sounds = {}; A.current.sfx = {}
  w:step(60)
  t.ok(count(w:heard(A), "randomradio") >= 1, "the radio")
  t.eq(count(w:heard(A), "fan-belt-squeal"), 0, "no fan belt while parked")
  t.eq(#A.current.sfx, 0, "no backfires parked")
  w:assertClean()
end)

t.test("squeaky brakes: BeamNG's own brake squeal turned up, kept on; a workshop sorts a quirk for $150", function()
  local w = World.new({ files = F.files(everyFive()) })
  local A, B = w:join("Alice"), w:join("Bob")
  deathTrap(w, A, { B })
  w:step(12)
  for _, wd in pairs(A.current.wheels) do t.eq(wd.squealCoefLowSpeed, 1, "squealing at low speed") end
  w:driveAll({ { A, p(500), 40 }, { B, p(500, 10), 40 } }); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 30 } })
  w:waitFor(function() return w:state(A).phase == "workshop" end, 15, "the workshop")
  w:step(2.5)
  local cash = w:state(A).cash
  A.client.im.click("Sort the quirk: Squeaky brakes ($150)##fixq_squeak"); w:step(12)
  t.ok(w:chatHas(B, "Alice pays $150 to get rid of the squeaky brakes."))
  t.eq(w:state(A).cash, cash - 150)
  for _, wd in pairs(A.current.wheels) do t.ok(wd.squealCoefLowSpeed ~= 1, "the brakes' own values back") end
  w:chat(A, "/tg fix squeak"); t.ok(w:chatHas(A, "Your car doesn't have that problem."), "gone")
  w:assertClean()
end)

t.test("admin: /tg quirk test <id> - one go of it on the car you're in, now", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:buy(A, "covet", "base_M"); w:step(1.5)
  A.current.sfx, A.current.controls, A.client.sounds = {}, {}, {}
  w:chat(A, "/tg quirk test backfire"); w:step(0.5)
  t.ok(has(A.current.sfx, "Afterfire"))
  w:chat(A, "/tg quirk test horn"); w:step(1)
  t.ok(has(A.current.controls, "horn true") and has(A.current.controls, "horn false"))
  w:chat(A, "/tg quirk test fanbelt"); w:step(0.5)
  t.eq(count(w:heard(A), "fan-belt-squeal"), 1)
  w:chat(A, "/tg quirk test squeak"); w:step(0.5)
  for _, wd in pairs(A.current.wheels) do t.eq(wd.squealCoefLowSpeed, 1) end
  w:chat(A, "/tg menu"); w:step(2.5)
  A.client.im.click("Haunted horn##qt_horn"); w:step(1.5)
  t.ok(w:chatHas(A, "Quirk test: Haunted horn."), "the Admin tab's quirk buttons")
  w:chat(A, "/tg quirk test nope"); t.ok(w:chatHas(A, "Usage: /tg quirk test <fanbelt|radio|backfire"))
  w:assertClean()
end)
