-- Scoring (0.9.1): drivability /20 = the average of an inspection on arrival at every workshop and at the finale;
-- penalties: illegal reset -2, tow/respawn -2, unfixed fault -3 (its own line), every $500 (or part) in debt -1;
-- producer awards (/tg award). Money in the bank only breaks ties.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function oneRace()   -- one event, no workshop, finale at x=5000
  return F.config({ { name = "Race One", type = "race", timeLimit = 300, start = p(500), checkpoints = { p(700), p(900) }, via = {} } })
end
local function startAndBuy(w, players)
  w:chat(players[1], "/tg start")
  local models = { "covet", "pessima", "miramar" }
  for i, pl in ipairs(players) do w:buy(pl, models[i], "base_M") end
  for _, pl in ipairs(players) do w:chat(pl, "/tg ready") end
end
local function raceTo(w, A, from, to)
  w:drive(A, p(from), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(to), 40)
end

t.test("a workshop inspects the car on arrival, before repairs; drivability is the average with the finale", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  startAndBuy(w, { A })
  w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(700), 40)
  w:damage(A, 8000); w:step(2.5)              -- a big hit during the race
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  t.ok(w:chatHas(A, "Workshop inspection: damage 8000 -> 12.0/20 drivability (all your inspections are averaged at the end)."))
  w:chat(A, "/tg repair")                     -- a repair fixes the car, not the inspection
  w:chat(A, "/tg next")
  raceTo(w, A, 1500, 1900)
  w:waitFor(function() return w:state(A).phase == "finale" end, 10, "the finale")
  w:drive(A, p(5000), 40)
  t.ok(w:chatHas(A, "Alice made it to The Test Track! Inspection: damage 0 -> 20.0/20. Drivability (average of 2 inspections): 16.0/20"))
  t.eq(w:state(A).points, 10 + 10 + 16, "two wins + the average of 12 and 20")
  w:assertClean()
end)

t.test("with workshop locations: inspected on arrival at one; anyone who stays away is inspected at closing", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  cfg.workshopSpots = { { x = 950, y = 100, z = 0, name = "Gas station" } }
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  startAndBuy(w, { A, B })
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 35 } }); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 35 } })
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:step(3)
  t.noLine(A.chat, "Workshop inspection", "not before arriving")
  w:damage(A, 4000); w:step(2.5)
  w:drive(A, p(950, 100), 20)
  t.ok(w:chatHas(A, "Workshop inspection: damage 4000 -> 16.0/20"), "on arrival")
  w:damage(B, 10000); w:step(2.5)              -- Bob never goes to the gas station
  w:chat(A, "/tg next")
  t.ok(w:chatHas(B, "Workshop inspection (you didn't make it to a workshop): damage 10000 -> 10.0/20"))
  w:assertClean()
end)

t.test("debt: -1 for every $500 or part of it in the red at the end", function()
  local w = World.new({ files = F.files(oneRace()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  startAndBuy(w, { A, B, C })
  w:chat(A, "/tg next"); w:chat(A, "/tg next")   -- force the race, call time: on to the finale
  w:waitFor(function() return w:state(A).phase == "finale" end, 10, "the finale")
  w:chat(A, "/tg setcash Alice -1")
  w:chat(A, "/tg setcash Bob -501")
  w:chat(A, "/tg setcash Carol -1200")
  w:chat(A, "/tg next")                          -- finale over
  t.ok(w:chatHas(A, "Alice loses 1 pt: $1 in debt (-1)."))
  t.ok(w:chatHas(A, "Bob loses 2 pts: $501 in debt (-2)."))
  t.ok(w:chatHas(A, "Carol loses 3 pts: $1,200 in debt (-3)."))
  t.eq(w:state(C).points, -3, "nothing else scored: no finish, 0 at the finale inspection")
  w:assertClean()
end)

t.test("each unfixed fault costs 3 points on its own line - not capped by a zero drivability", function()
  local w = World.new({ files = F.files(oneRace()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:chat(A, "/tg fault take 2")
  w.rolls = { 1, 2 }; w:buy(A, "covet", "base_M")   -- worn tyres, then (alignment won't fit: swapped)...
  w:step(10)
  w:chat(A, "/tg ready")
  raceTo(w, A, 500, 900)
  w:waitFor(function() return w:state(A).phase == "finale" end, 10, "the finale")
  w:damage(A, 25000); w:step(2.5)              -- wrecked: the finale inspection scores 0
  w:drive(A, p(5000), 40)
  t.ok(w:chatHas(A, "Alice loses 6 pts: 2 problems left unfixed (-6)."))
  t.eq(w:state(A).points, 10 + 0 - 6)
  w:assertClean()
end)

t.test("producer points: /tg award adds or docks points with a reason, shown on the results", function()
  local w = World.new({ files = F.files(oneRace()) })
  local A, B = w:join("Alice"), w:join("Bob")
  startAndBuy(w, { A, B })
  w:chat(A, "/tg award Bob 2 best-looking wreck")
  t.ok(w:chatHas(B, "The producers award Bob 2 pts: best-looking wreck."))
  w:chat(A, "/tg award Bob -0.5")
  t.ok(w:chatHas(B, "The producers dock Bob 0.5 pts."))
  t.eq(w:state(B).points, 1.5)
  w:chat(B, "/tg award Bob 100")
  t.ok(w:chatHas(B, "That's an admin command."))
  w:chat(A, "/tg award Nobody 2")
  t.ok(w:chatHas(A, "Usage: /tg award <driver>"))
  w:chat(A, "/tg next"); w:chat(A, "/tg next")
  w:waitFor(function() return w:state(A).phase == "finale" end, 10, "the finale")
  w:chat(A, "/tg next")
  w:step(3)
  t.match(B.client.im.textOf("Top Gear Challenge"), "%+ 1%.5 from the producers")
  w:assertClean()
end)

t.test("saved configs move to the new scoring once (custom values kept)", function()
  local old = F.config({}, { scoring = { drivabilityMaxPoints = 10, towPenaltyPoints = 1 }, faults = { inspectionPenaltyPoints = 1 } })
  local sc = World.new({ files = F.files(old) }):serverConfig()
  t.eq(sc.scoring.drivabilityMaxPoints, 20); t.eq(sc.scoring.towPenaltyPoints, 2); t.eq(sc.faults.inspectionPenaltyPoints, 3)
  t.eq(sc.scoring.debtStep, 500); t.eq(sc.scoring.debtPenaltyPoints, 1)
  local custom = F.config({}, { scoring = { drivabilityMaxPoints = 15, towPenaltyPoints = 3 } })
  local sc2 = World.new({ files = F.files(custom) }):serverConfig()
  t.eq(sc2.scoring.drivabilityMaxPoints, 15); t.eq(sc2.scoring.towPenaltyPoints, 3)
end)
