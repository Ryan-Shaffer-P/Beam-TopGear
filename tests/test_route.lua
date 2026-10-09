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
