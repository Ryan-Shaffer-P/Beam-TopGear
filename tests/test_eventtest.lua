-- Testing one event without a whole challenge (0.9.13, the course builder's Test event / Quick travel / Stop event)
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local WIN = "Top Gear Challenge"
local function course()
  return F.config({
    { name = "Drag", type = "race", timeLimit = 120, start = p(500), checkpoints = { p(700), p(900) }, via = {} },
    { name = "Hill Climb", type = "race", solo = true, timeLimit = 120, start = p(1500), checkpoints = { p(1900) }, via = {} },
    { name = "Unfinished", type = "race", timeLimit = 120, via = {} },
  })
end

t.test("Test event: the event on its own from its countdown - everyone in a car races, results, then back to normal", function()
  local w = World.new({ files = F.files(course()) })
  local A, B = w:join("Alice"), w:join("Bob")   -- (Alice is the admin)
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:driveAll({ { A, p(500, 5), 40 }, { B, p(500, -5), 40 } }); w:step(1.5)
  w:chat(A, "/tg menu"); w:step(2.5)
  t.ok(A.client.im.hasButton("Test\n event") or A.client.im.hasButton(" Test\nevent"), "the Test event button")
  A.client.im.click("##big_testevent"); w:step(0.5)
  t.ok(w:chatHas(A, "TEST EVENT: Drag (event 1) - 2 drivers, from the start line. /tg testevent stop ends it."))
  t.eq(w:state(A).phase, "countdown", "straight to the countdown")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 30 } })
  w:waitFor(function() return w:state(A).phase == "idle" end, 10, "back to normal")
  t.ok(w:chatHas(A, "1st  Alice"), "results")
  t.ok(w:chatHas(A, "Test event over - back to normal."))
  t.noLine(A.chat, "WORKSHOP"); t.noLine(A.chat, "LEG 2")
  t.ok(A.current and B.current, "everyone keeps their car")
  t.ok(not (w.files["Resources/Server/TopGear/session.json"] or ""):find("Drag", 1, true), "nothing saved to resume")
  w:assertClean()
end)

t.test("Test event in time trial mode, Stop event, and the things it refuses", function()
  local w = World.new({ files = F.files(course()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg testevent 1")
  t.ok(w:chatHas(A, "Nobody's in a car - get in one first."))
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M"); w:step(1.5)
  w:chat(A, "/tg testevent 3")
  t.ok(w:chatHas(A, "Can't test event 3 yet:"), "an unfinished event")
  w:chat(B, "/tg testevent 2")
  t.noLine(B.chat, "TEST EVENT", "admins only")
  w:driveAll({ { A, p(1500, 5), 60 }, { B, p(1500, -5), 60 } })
  w:chat(A, "/tg testevent 2")
  t.ok(w:chatHas(A, "One at a time - running order: Alice, Bob."), "time trial mode: one at a time")
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 10, "Alice's GO")
  w:chat(A, "/tg testevent stop")
  t.ok(w:chatHas(A, "Test event stopped - back to normal."))
  t.eq(w:state(A).phase, "idle")
  w:chat(A, "/tg testevent stop")
  t.ok(w:chatHas(A, "No test event is running."))
  -- not during a real challenge
  w:chat(A, "/tg start force")   -- (force: event 3 is unfinished on purpose)
  w:chat(A, "/tg testevent 1"); w:chat(A, "/tg quicktravel 1")
  t.ok(w:chatHas(A, "Test events only run when no challenge is going (/tg stop first)."))
  t.ok(w:chatHas(A, "Quick travel only works when no challenge is going."))
  w:assertClean()
end)

t.test("Quick travel: your car to the event's start, facing the first checkpoint", function()
  local w = World.new({ files = F.files(course()) })
  local A = w:join("Alice")
  w:buy(A, "covet", "base_M"); w:drive(A, p(3000, 200), 60); w:step(1.5)
  w:chat(A, "/tg quicktravel 2"); w:step(0.5)
  t.ok(w:chatHas(A, "Off to event 2's start."))
  t.eq(A.current.pos.x, 1500); t.eq(A.current.pos.y, 0)
  t.ok(math.abs(math.cos(A.current.yaw or 0) - 1) < 1e-6 or math.abs(math.sin(A.current.yaw or 0) - 1) < 1e-6,
    "facing along the course: " .. tostring(A.current.yaw))
  w:chat(A, "/tg quicktravel 3")
  t.ok(w:chatHas(A, "event 3 has no start yet."))
  w:assertClean()
end)

t.test("checkpoints are 5 m (12 m until 0.9.13): saved configs at 12 move once, an admin's own value stays", function()
  t.eq(World.new():serverConfig().defaults.cpRadius, 5)
  local function load(r)
    local cfg = course(); cfg.defaults.cpRadius = r
    return World.new({ files = F.files(cfg) }):serverConfig().defaults.cpRadius
  end
  t.eq(load(12), 5)
  t.eq(load(8), 8, "a custom radius isn't touched")
end)

t.test("Test event, trailer delivery: the first GO brings everyone's trailer to hitch up; then GO per driver in a time trial", function()
  local cfg = F.config({ { name = "Trailer Delivery", type = "trailer", solo = true, timeLimit = 300,
                           start = p(500), checkpoints = { p(700), p(900) }, via = {} } })
  cfg.defaults = { readyCountdown = 0, soloGo = true, readyToGo = false }
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:driveAll({ { A, p(500, 5), 40 }, { B, p(500, -5), 40 } }); w:step(1.5)
  w:chat(A, "/tg testevent 1"); w:step(6)
  t.ok(w:chatHas(A, "Trailers are on their way - hitch up, then press GO for the first run (one at a time)."))
  local function trailers(pl) local n = 0 for _, v in pairs(pl.vehicles) do if v.model == "tsfb" then n = n + 1 end end return n end
  t.eq(trailers(A), 1, "Alice's trailer"); t.eq(trailers(B), 1, "Bob's trailer")
  t.eq(w:state(A).phase, "travel", "nothing starts until GO - time to hitch up")
  t.noLine(A.chat, "running order")
  w:hitch(A); w:hitch(B)
  w:chat(A, "/tg menu"); w:step(2.5)
  t.eq(w:ui(A).goName, "Alice")
  t.ok(A.client.im.hasButton("GO: Alice"), "the next GO is for the first driver (Alice pressed Test event)")
  w:chat(B, "/tg go")
  t.ok(w:chatHas(A, "running order: Alice, Bob."))
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 10, "Alice's run")
  w:drive(A, p(900), 40)
  w:step(2.5)
  t.ok(w:chatHas(A, "Bob is up (last run) - Bob presses GO when ready."), "then Bob, on his own GO")
  w:chat(A, "/tg testevent stop")
  t.eq(trailers(A) + trailers(B), 0, "Stop event cleans the trailers up")
  w:assertClean()
end)

t.test("Test event, trailer delivery in race mode: hitch up first, then one GO starts everyone", function()
  local cfg = F.config({ { name = "Trailer Delivery", type = "trailer", timeLimit = 300,
                           start = p(500), checkpoints = { p(700), p(900) }, via = {} } })
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:driveAll({ { A, p(500, 5), 40 }, { B, p(500, -5), 40 } }); w:step(1.5)
  w:chat(A, "/tg testevent 1"); w:step(6)
  t.ok(w:chatHas(A, "Trailers are on their way - hitch up, then press GO to start everyone."))
  t.eq(w:state(A).phase, "travel")
  w:hitch(A); w:hitch(B)
  w:chat(A, "/tg go")
  t.eq(w:state(A).phase, "countdown", "everyone's countdown")
  w:assertClean()
end)

t.test("checkpoint sizes: 5 / 10 / 20 m, or a Line across the road - each checkpoint keeps its own", function()
  local cfg = F.config({ { name = "Drag", type = "race", timeLimit = 300, start = p(500), checkpoints = {}, via = {} } })
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:buy(A, "covet", "base_M"); w:drive(A, p(700), 40); w:step(1.5)
  w:chat(A, "/tg addcp 1 20")
  t.ok(w:chatHas(A, "checkpoint 1 set (700.0, 0.0, 0.0) (a 20 m checkpoint)"))
  w:drive(A, p(900), 40); w:step(1.5)
  w:chat(A, "/tg addcp 1 line")
  t.ok(w:chatHas(A, "(a 20 m line)"))
  local cps = w:serverConfig().events[1].checkpoints
  t.eq(cps[1].r, 20)
  t.eq(cps[2].line.ax, 900); t.eq(math.abs(cps[2].line.ay), 10, "across the way from checkpoint 1: x = 900, y -10 .. 10")
  w:chat(A, "/tg addcp 1 huge")
  t.ok(w:chatHas(A, "Usage: /tg addcp <event> [5|10|20|line]"))
  -- run it: 15 m off the middle still counts for the 20 m checkpoint; the line only counts when you cross it
  w:drive(A, p(500), 40); w:chat(A, "/tg testevent 1")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  t.eq(w:state(A).target.r, 20, "the marker is 20 m")
  w:drive(A, p(700, 15), 40)
  t.ok(w:chatHas(A, "Checkpoint 1/1"), "15 m off: inside 20 m")
  t.ok(w:state(A).target.line, "the finish is a line (the client draws posts and a bar)")
  w:drive(A, p(950, 15), 40)
  t.noLine(A.chat, "crosses the line", "past the end of the line (15 m out, the line's 10 m each side): not crossed")
  w:drive(A, p(850, 0), 40); w:drive(A, p(950, 0), 40)
  t.ok(w:chatHas(A, "Alice crosses the line!"), "straight across it: the finish")
  w:assertClean()
end)

t.test("moving the start keeps every checkpoint; a stacked one says how to fix just that", function()
  local cfg = F.config({ { name = "Drag", type = "race", timeLimit = 300, start = p(500), checkpoints = { p(700), p(900) }, via = {} } })
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:buy(A, "covet", "base_M"); w:drive(A, p(450), 40); w:step(1.5)
  w:chat(A, "/tg setstart 1")
  local e = w:serverConfig().events[1]
  t.eq(e.start.x, 450, "the start moved"); t.eq(#e.checkpoints, 2, "the checkpoints stayed")
  w:drive(A, p(702), 40); w:step(1.5)
  w:chat(A, "/tg setstart 1")   -- right on checkpoint 1
  w:chat(A, "/tg setfinale"); w:chat(A, "/tg start")
  t.ok(w:chatHas(A, "checkpoint 1 is on top of the start (2 m) - move the start (/tg setstart 1, or Set start here: your checkpoints stay)"))
  w:assertClean()
end)

t.test("parking: the bay's box and arrow follow the way the car faced when it was added (from its own game)", function()
  local cfg = F.config({ { name = "Parking", type = "parking", timeLimit = 300, start = p(500), bays = {}, via = {} } })
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:buy(A, "covet", "base_M")
  w:place(A, p(600, 20), math.pi / 2); w:step(1.5)   -- parked facing +y (the harness car points along (cos, sin) of its yaw)
  w:chat(A, "/tg addbay 1")
  local bay = w:serverConfig().events[1].bays[1]
  t.ok(math.abs(bay.dx) < 0.01 and math.abs(bay.dy - 1) < 0.01, "the direction her game reported")
  w:drive(A, p(500), 40); w:step(1.5)
  w:chat(A, "/tg testevent 1")
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 10, "her run")
  w:step(0.5)
  local d = w:state(A).target.dir
  t.ok(d and math.abs(d.y - 1) < 0.01, "the bay's direction goes to her game")
  -- an arrowhead at the front end of the bay's centre line: facing +y, so its tip is 2.2 m up y from the bay
  local heads = 0
  for _, cy in ipairs(A.client.cylinders) do
    if math.abs(cy.a.x - 600) < 0.01 and math.abs(cy.a.y - 22.2) < 0.01 and cy.b.y < cy.a.y and math.abs(cy.b.x - 600) > 0.5 then heads = heads + 1 end
  end
  t.eq(heads, 2, "two arrowhead strokes back from the tip at the +y end")
  -- straightness is scored from the same directions: backed in, 30 degrees off
  w:place(A, p(600, 20), -math.pi / 2 + math.pi / 6); w:step(3)
  t.ok(w:chatHas(A, "Bay 1/1 parked: 0 cm off centre, 30 degrees skew."))
  w:assertClean()
end)

t.test("parking: a bay added before 0.9.19 (no direction) is a plain marker - no skewed box, no arrow", function()
  local cfg = F.config({ { name = "Parking", type = "parking", timeLimit = 300, start = p(500),
                           bays = { { x = 600, y = 0, z = 0, yaw = 90 } }, via = {} } })
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:buy(A, "covet", "base_M"); w:drive(A, p(500), 40); w:step(1.5)
  w:chat(A, "/tg testevent 1")
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 10, "her run")
  w:step(0.5)
  t.eq(w:state(A).target.dir, nil)
  for _, cy in ipairs(A.client.cylinders) do t.ok(cy.r ~= 0.05, "no centre line or arrow") end
  w:assertClean()
end)

t.test("course builder: the selected checkpoint size has an orange border; the Test event row is framed in orange", function()
  local w = World.new({ files = F.files(course()) })
  local A = w:join("Alice")
  w:chat(A, "/tg menu"); w:step(2.5)
  t.ok(A.client.im.hasButton("5 m") and A.client.im.hasButton("Line"), "no '> ' marker on the selected size any more")
  local orange = 0
  for _, r in ipairs(A.client.im.lastFrame.rects) do
    if r.outline and r.color and r.color.x == 1 and r.color.y == 0.55 then orange = orange + 1 end
  end
  t.eq(orange, 1, "one orange outline: round Test event / Quick travel / Stop event")
  t.eq(A.client.im.problems[1], nil, "every style push popped")
  w:assertClean()
end)
