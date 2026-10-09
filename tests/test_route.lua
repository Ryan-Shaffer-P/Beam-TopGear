-- The road guide shows the whole way (0.9.35, Ryan: drivers got lost - the guide only went to the next checkpoint, so
-- you could need to turn before it updated). state.route = every point still to come; the client hands BeamNG's
-- setPath the list (the harness records it as client.route).
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function xs(pl)   -- the route's x coordinates, "500,700,900"
  local out = {}
  for i, q in ipairs(pl.client.route or {}) do out[i] = tostring(math.floor(q.x + 0.5)) end
  return table.concat(out, ",")
end

t.test("a race: a preview of the whole course at the start, then every checkpoint left to the finish", function()
  local w = World.new({ files = F.files(F.config({
    { name = "Long Race", type = "race", timeLimit = 300, start = p(500), checkpoints = { p(700), p(900), p(1100) }, via = {} },
  })) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start"); w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready"); w:step(1)
  t.eq(A.client.route, nil, "on the way with no waypoints: just the start")
  t.eq(A.client.path.x, 500)
  w:drive(A, p(500, 3), 40); w:step(1.5)
  t.eq(xs(A), "500,700,900,1100", "at the start: the whole course")
  w:drive(B, p(500, -3), 40); w:step(1)
  w:chat(A, "/tg go"); w:waitFor(function() return w:sawMessage(A, "GO!") end, 10, "GO")
  w:step(1)
  t.eq(xs(A), "700,900,1100", "racing: every checkpoint to the finish")
  w:drive(A, p(700), 40); w:step(1)
  t.eq(xs(A), "900,1100", "one down")
  w:drive(A, p(900), 40); w:step(1)
  t.eq(A.client.route, nil, "the last one: just the finish")
  t.eq(A.client.path.x, 1100)
  w:assertClean()
end)

t.test("a circuit: the rest of this lap and the whole next one; on the last lap, to the line", function()
  local w = World.new({ files = F.files(F.config({
    { name = "Loop", type = "circuit", laps = 2, timeLimit = 600, start = p(500), checkpoints = { p(800), p(800, 300) }, via = {} },
  })) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:buy(A, "covet", "base_M"); w:chat(A, "/tg ready"); w:step(1)
  w:drive(A, p(500, 3), 40); w:step(1)
  w:chat(A, "/tg go"); w:waitFor(function() return w:sawMessage(A, "GO!") end, 10, "GO")
  w:step(1)
  t.eq(xs(A), "800,800,500,800,800,500", "lap 1: this lap and the next")
  w:drive(A, p(800), 40); w:drive(A, p(800, 300), 40); w:drive(A, p(500, 3), 40); w:step(1)
  t.eq(xs(A), "800,800,500", "lap 2 (the last): to the line")
  w:assertClean()
end)

t.test("the drive to an event: every waypoint left, then the start", function()
  local w = World.new({ files = F.files(F.config({
    { name = "Far Race", type = "race", timeLimit = 300, start = p(2000), checkpoints = { p(2400) }, via = { p(800), p(1400) } },
  })) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:buy(A, "covet", "base_M"); w:chat(A, "/tg ready"); w:step(1)
  t.eq(xs(A), "800,1400,2000", "both waypoints, then the start")
  w:drive(A, p(800), 40); w:step(1)
  t.eq(xs(A), "1400,2000", "one waypoint left")
  w:drive(A, p(1400), 40); w:step(1)
  t.eq(A.client.route, nil, "the last waypoint passed: just the start")
  t.eq(A.client.path.x, 2000)
  w:drive(A, p(2000, 3), 40); w:step(1)
  t.eq(xs(A), "2000,2400", "arrived: a preview of the course")
  w:assertClean()
end)

-- Off-road stretches, guide points, the Off-road switch (0.9.35) -------------------------------------------------------
-- (the harness's road runs along the x axis at y = 0: y = 200 is off-road)
local function arrows(pl)   -- our own road guide arrows drawn this frame (two 0.12 m bars each)
  local n = 0
  for _, cy in ipairs(pl.client.cylinders or {}) do if cy.r == 0.12 then n = n + 1 end end
  return n / 2
end
local function raceWith(cps, extra)
  local e = { name = "Rally", type = "race", timeLimit = 600, start = p(500), checkpoints = cps, via = {} }
  for k, v in pairs(extra or {}) do e[k] = v end
  return F.config({ e })
end
local function goRace(w, A)
  w:chat(A, "/tg start"); w:buy(A, "covet", "base_M"); w:chat(A, "/tg ready"); w:step(1)
  w:drive(A, p(500, 3), 40); w:step(1)
  w:chat(A, "/tg go"); w:waitFor(function() return w:sawMessage(A, "GO!") end, 10, "GO")
  w:step(1)
end

t.test("off-road: the game's guide to the first off-road point, then our straight arrows across the field", function()
  local w = World.new({ files = F.files(raceWith({ p(700, 200), p(900, 200), p(1100), p(1300) })) })
  local A = w:join("Alice")
  goRace(w, A)
  t.ok((A.client.roadPaths or 0) > 0, "after the field, the road stretch to 1100 and 1300 follows the road network's path")
  t.eq(A.client.route, nil, "the game's guide: just to the first off-road checkpoint (it can't do two in a row)")
  t.eq(A.client.path.x, 700)
  t.eq(arrows(A), 0, "our arrows start out there - too far to draw yet")
  w:drive(A, p(700, 200), 30); w:step(1)
  t.eq(A.client.path, nil, "in the field: the game's guide is off")
  t.ok(arrows(A) >= 10, "our arrows from the car: " .. arrows(A))
  for _, cy in ipairs(A.client.cylinders) do
    if cy.r == 0.12 then t.ok(math.abs(cy.a.y - 200) < 3, "a straight line across the field (y = 200)"); break end
  end
  w:drive(A, p(900, 200), 30); w:step(1)
  t.eq(A.client.path.x, 1100, "out of the field to a road checkpoint: the game's guide does that (straight to the road)")
  t.eq(arrows(A), 0, "no arrows of ours")
  w:assertClean()
end)

t.test("Off-road switch: Road puts a point back on the game's guide; Off-road sends straight arrows to a point by a road", function()
  local w = World.new({ files = F.files(raceWith({ p(700, 200), p(900, 200), p(1100) })) })
  local A = w:join("Alice")
  w:chat(A, "/tg offroad 1 cp 2 off")
  t.ok(w:chatHas(A, "event 1: cp 2 ROAD (the road route)"))
  w:chat(A, "/tg offroad 1 cp 3")
  t.ok(w:chatHas(A, "event 1: cp 3 OFF-ROAD"), "no switch: auto -> on")
  goRace(w, A)
  t.eq(xs(A), "700,900,1100", "cp 2 says road: no two off-road points meet - the game's guide does it all")
  w:drive(A, p(700, 200), 30); w:step(1)
  t.eq(A.client.path.x, 900, "cp 2 says road: the game's guide again")
  w:drive(A, p(900, 200), 30); w:step(1)
  t.eq(A.client.path, nil, "cp 3 says off-road, the car's off-road: straight arrows")
  t.ok(arrows(A) > 0)
  w:chat(A, "/tg offroad 1 all auto")
  t.ok(w:chatHas(A, "event 1: every point AUTO"))
  w:assertClean()
end)

t.test("guide points: the route goes through them, in order; passed ones drop off; the menu lists them", function()
  local w = World.new({ files = F.files(raceWith({ p(1000) })) })
  local A = w:join("Alice")
  w:chat(A, "/tg menu")
  w:clientSpawn(A, "covet", {}); w:step(1)   -- (a car to place the points with)
  w:place(A, p(650, 2), 0); w:step(1)
  w:chat(A, "/tg addguide 1")
  t.ok(w:chatHas(A, "event 1 guide point 1 (650.0, 2.0, 0.0) - the road guide goes through it on the way to the next checkpoint you add"))
  w:place(A, p(800, 2), 0); w:step(1)
  w:chat(A, "/tg addguide 1 before 1")
  t.ok(w:chatHas(A, "on the way to checkpoint 1"))
  w:step(1)
  local txt = A.client.im.textOf("Top Gear Challenge")
  t.ok(txt:find("Guide point 1", 1, true) and txt:find("Checkpoint 1 (finish)", 1, true), "the Off-road box lists them")
  goRace(w, A)
  t.eq(xs(A), "650,800,1000", "both guide points, then the finish")
  w:drive(A, p(650), 30); w:step(1)
  t.eq(xs(A), "800,1000", "the first one passed")
  w:drive(A, p(800), 30); w:step(1)
  t.eq(A.client.route, nil, "both passed: just the finish"); t.eq(A.client.path.x, 1000)
  w:chat(A, "/tg undoguide 1"); t.ok(w:chatHas(A, "event 1 now has 1 guide point(s)."))
  w:assertClean()
end)

t.test("a parking garage: guide points up the ramp, a deck above the road counts as off-road", function()
  local cfg = F.config({ { name = "Garage", type = "parking", timeLimit = 300, start = p(500),
    bays = { { x = 700, y = 0, z = 12, dx = 1, dy = 0 } },
    guide = { { x = 600, y = 0, z = 0, before = 1 }, { x = 650, y = 0, z = 6, before = 1, off = true } }, via = {} } })
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:buy(A, "covet", "base_M"); w:chat(A, "/tg ready"); w:step(1)
  w:drive(A, p(500, 3), 40); w:step(1)
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" and w:state(A).target and w:state(A).target.label:find("bay") end, 15, "the run")
  w:step(1)
  t.eq(xs(A), "600,650", "the game's guide to the bottom of the ramp and up it (into the switched point)")
  t.ok(arrows(A) > 0, "then our arrows from the ramp to the bay on the deck (12 m up: off-road): " .. arrows(A))
  w:drive(A, p(600), 20); w:step(1)
  t.eq(A.client.route, nil, "the bottom of the ramp passed")
  t.eq(A.client.path.x, 650)
  w:assertClean()
end)
