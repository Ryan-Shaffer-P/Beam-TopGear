-- Time trial mode, GO per driver (0.9.13): the event's GO starts the first driver; every later driver waits
-- until GO is pressed - by them, or by an admin. The button says whose turn it is.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local WIN = "Top Gear Challenge"
local function trialCourse()
  local cfg = F.config({ { name = "The Hill Climb", type = "race", solo = true, timeLimit = 120,
                           start = p(500), checkpoints = { p(700), p(900) }, via = {} } })
  cfg.defaults = { readyCountdown = 0, soloGo = true, readyToGo = false }   -- (the fixtures switch it off for the older tests)
  return cfg
end

-- Alice is the admin. Arrival order (= running order): Bob, Alice, Carol
local function toTheStart(w, A, B, C)
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M"); w:buy(C, "miramar", "base_M")
  for _, pl in ipairs({ A, B, C }) do w:chat(pl, "/tg ready") end
  w:drive(B, p(500), 40); w:drive(A, p(505, 8), 40); w:drive(C, p(495, -8), 40)
  w:step(2.5)
end

t.test("time trial: GO per driver - the first by the event's GO, then each waits for theirs (them or an admin)", function()
  local w = World.new({ files = F.files(trialCourse()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  toTheStart(w, A, B, C)
  t.eq(w:ui(A).goName, "Bob", "the event's GO button says who goes first")
  t.ok(A.client.im.hasButton("GO: Bob"), "GO: Bob")
  w:chat(C, "/tg go")
  t.ok(w:chatHas(A, "running order: Bob, Alice, Carol."))
  w:waitFor(function() return w:sawMessage(B, "Bob: GO!") end, 10, "Bob's GO - his countdown started with the event's GO")
  w:drive(B, p(900), 40)

  -- Alice is up: nothing happens until her GO
  w:step(2.5)
  t.ok(w:chatHas(A, "Alice is up (Carol next) - Alice presses GO when ready."))
  t.eq(w:state(A).target.label, "Your turn - press GO when ready")
  t.eq(w:state(C).target.label, "Wait at the start - Alice's turn (waiting for GO)")
  w:step(8)
  t.ok(not w:sawMessage(A, "Alice: 3"), "no countdown by itself")
  t.ok(A.client.im.hasButton("GO: Alice"), "her button says her name")
  t.eq(w:ui(C).soloWait.canGo, false)
  t.ok(C.client.im.textOf(WIN):find("Waiting for Alice to press GO.", 1, true), "the others see who they're waiting for")
  w:chat(C, "/tg go")
  t.ok(w:chatHas(C, "It's Alice's turn - Alice presses GO (or an admin)."), "Carol can't start Alice")
  A.client.im.click("GO: Alice"); w:step(0.5)
  t.ok(w:chatHas(A, "Alice - GO!"))
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 10, "Alice's GO")
  w:drive(A, p(900), 40)

  -- Carol is up: Alice, the admin, starts her run for her
  w:step(2.5)
  t.ok(A.client.im.hasButton("GO: Carol"), "an admin gets the button for someone else's turn")
  w:chat(A, "/tg go")
  t.ok(w:chatHas(C, "Alice starts Carol's run."))
  w:waitFor(function() return w:sawMessage(C, "Carol: GO!") end, 10, "Carol's GO")
  w:drive(C, p(900), 40)
  w:waitFor(function() return w:state(A).phase ~= "event" end, 15, "the results")
  t.ok(w:chatHas(A, "RESULTS: The Hill Climb"))
  w:assertClean()
end)

t.test("Star in an RPC with GO per driver: the next driver's car comes only when their GO is pressed", function()
  local cfg = F.config({ { name = "Star in a Reasonably Priced Car", type = "rpc", laps = 1, timeLimit = 300,
                           start = p(500), checkpoints = { p(800) }, via = {} } })
  cfg.defaults = { readyCountdown = 0, soloGo = true, readyToGo = false }
  local w = World.new({ files = F.files(cfg) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  toTheStart(w, A, B, C)
  local ownA = A.current
  w:chat(B, "/tg go")
  w:waitFor(function() return w:sawMessage(B, "Bob: GO!") end, 20, "Bob's GO (his car came with the event's GO)")
  w:drive(B, p(800), 40); w:drive(B, p(500), 40)   -- one lap
  w:step(6)                                         -- (3 s to stop, then he's out)
  t.eq(A.current, ownA, "Alice is still in her own car: no RPC until her GO")
  t.noLine(A.chat, "Alice's reasonably priced car is on its way")
  w:chat(A, "/tg go")
  w:waitFor(function() return A.current ~= ownA end, 5, "her RPC")
  t.eq(A.current.model, "covet")
  w:assertClean()
end)

t.test("spectating: everyone else watches the driver on track, and is back in their own car when the run ends", function()
  local cfg = trialCourse(); cfg.defaults.watchRunner = true
  local w = World.new({ files = F.files(cfg) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  w:chat(C, "/tg watch off")
  t.ok(w:chatHas(C, "You won't be switched to watch the driver on track."))
  toTheStart(w, A, B, C)
  local ownA = A.current
  w:chat(A, "/tg go")
  w:waitFor(function() return A.viewing ~= nil end, 10, "Alice watching")
  t.eq(A.viewing, B.current, "Alice's camera is on Bob's car")
  t.eq(A.current, ownA, "...her own car is still hers")
  t.eq(C.viewing, nil, "Carol turned watching off")
  t.eq(B.viewing, nil, "Bob drives")
  t.ok(A.client.im.textOf(WIN):find("Watching Bob - you're back in your car when their run ends.", 1, true))
  A.client.im.click("Back to my car##unwatch"); w:step(0.5)
  t.eq(A.viewing, nil, "Back to my car")
  w:waitFor(function() return w:sawMessage(B, "Bob: GO!") end, 10, "Bob's GO")
  w:drive(B, p(900), 40)
  w:step(2.5)
  t.eq(A.viewing, nil, "the run's over: nobody watching")
  -- Alice's turn (her GO): Bob watches her
  w:chat(A, "/tg go")
  w:step(1)
  t.eq(B.viewing, A.current, "Bob watches Alice")
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 10, "Alice's GO")
  w:drive(A, p(900), 40)
  w:step(2.5)
  t.eq(B.viewing, nil, "back in his own car")
  w:assertClean()
end)

t.test("spectating an RPC driver: the watchers follow the reasonably priced car, not the driver's parked one", function()
  local cfg = F.config({ { name = "Star in a Reasonably Priced Car", type = "rpc", laps = 1, timeLimit = 300,
                           start = p(500), checkpoints = { p(800) }, via = {} } })
  cfg.defaults = { readyCountdown = 0, soloGo = true, watchRunner = true, readyToGo = false }
  local w = World.new({ files = F.files(cfg) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  toTheStart(w, A, B, C)
  local ownB = B.current
  w:chat(A, "/tg go")
  w:waitFor(function() return B.current ~= ownB end, 10, "Bob in his RPC")
  w:step(1)
  t.eq(A.viewing, B.current, "Alice watches Bob's RPC")
  t.ok(A.viewing ~= ownB, "not his parked car")
  w:assertClean()
end)
