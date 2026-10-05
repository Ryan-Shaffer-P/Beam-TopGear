-- Every start is I'm ready, then GO (0.9.13, defaults.readyToGo): a race start waits for everyone's I'm ready, then
-- anyone's GO; a time trial's turns begin by themselves once everyone's there, each driver pressing I'm ready, then
-- GO (them or an admin). No 10 s settle-in timer for the reasonably priced car any more: the normal 5 s lights.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local WIN = "Top Gear Challenge"
local function cfgWith(events)
  local cfg = F.config(events)
  cfg.defaults = { readyCountdown = 0, readyToGo = true }
  return cfg
end
local function toTheStart(w, A, B, at)
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")   -- (the dealership's ready)
  w:drive(A, p(at, 5), 40); w:drive(B, p(at, -5), 40)
  w:step(2.5)
end

t.test("race start: everyone presses I'm ready, then anyone's GO starts the countdown", function()
  local w = World.new({ files = F.files(cfgWith({ { name = "Drag", type = "race", timeLimit = 120, start = p(500),
                                                    checkpoints = { p(900) }, via = {} } })) })
  local A, B = w:join("Alice"), w:join("Bob")
  toTheStart(w, A, B, 500)
  t.ok(w:chatHas(A, "Everyone's at Drag! Press I'm ready - once everyone is, anyone can press GO."))
  t.ok(A.client.im.hasButton("I'm ready"), "the button")
  w:chat(A, "/tg go")
  t.ok(w:chatHas(A, "Waiting for Alice, Bob to press I'm ready."), "GO waits for everyone")
  A.client.im.click("I'm ready"); w:step(0.5)
  t.ok(w:chatHas(A, "Alice is ready (waiting for Bob)."))
  t.ok(A.client.im.textOf(WIN):find("Waiting for Bob to press I'm ready.", 1, true))
  w:chat(B, "/tg ready")
  t.ok(w:chatHas(A, "Bob is ready - everyone is: anyone can press GO."))
  w:step(2.5)
  t.ok(B.client.im.hasButton("GO! Start the countdown"))
  w:chat(B, "/tg go")
  t.eq(w:state(A).phase, "countdown")
  w:assertClean()
end)

t.test("time trial: the turns begin by themselves; each driver presses I'm ready, then GO", function()
  local w = World.new({ files = F.files(cfgWith({ { name = "Hill Climb", type = "race", solo = true, timeLimit = 120,
                                                    start = p(500), checkpoints = { p(900) }, via = {} } })) })
  local A, B = w:join("Alice"), w:join("Bob")
  toTheStart(w, A, B, 500)
  t.ok(w:chatHas(A, "running order: Alice, Bob."), "begun by itself once everyone was there")
  t.ok(w:chatHas(A, "Alice is up (Bob next) - Alice presses I'm ready, then GO."))
  w:chat(A, "/tg go")
  t.ok(w:chatHas(A, "Alice isn't ready yet - Alice presses I'm ready first."))
  w:chat(B, "/tg ready")
  t.ok(w:chatHas(B, "Nothing to be ready for right now."), "not Bob's turn")
  w:step(2.5)
  t.ok(A.client.im.hasButton("I'm ready"))
  t.ok(B.client.im.textOf(WIN):find("Waiting for Alice to get ready.", 1, true))
  A.client.im.click("I'm ready"); w:step(2.5)
  t.ok(w:chatHas(A, "Alice is ready - Alice presses GO (or an admin)."))
  t.ok(A.client.im.hasButton("GO: Alice"))
  w:chat(A, "/tg go")
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 10, "Alice's run")
  w:drive(A, p(900), 40); w:step(2.5)
  t.ok(w:chatHas(A, "Bob is up (last run) - Bob presses I'm ready, then GO."))
  w:assertClean()
end)

t.test("Star in an RPC: the car comes with the turn - no timer: I'm ready, then GO starts the 5 s lights", function()
  local w = World.new({ files = F.files(cfgWith({ { name = "Star in a Reasonably Priced Car", type = "rpc", laps = 1,
                                                    timeLimit = 300, start = p(500), checkpoints = { p(800) }, via = {} } })) })
  local A, B = w:join("Alice"), w:join("Bob")
  local ownA
  toTheStart(w, A, B, 500)
  w:waitFor(function() return A.current and A.current.model == "covet" end, 5, "Alice in her RPC (the turn began)")
  t.ok(w:chatHas(A, "Here's your reasonably priced car - get in, start it, settle in, then press I'm ready and GO."))
  w:step(12)
  t.ok(not w:sawMessage(A, "Alice: 1"), "no countdown by itself - no 10 s timer")
  w:chat(A, "/tg ready"); w:chat(A, "/tg go"); w:step(1)
  t.eq(w:state(A).lights and w:state(A).lights.total, 5, "the normal 5 s lights")
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 10, "Alice's run")
  w:assertClean()
end)

t.test("Test event: the same - a race test waits for everyone's I'm ready, then GO", function()
  local w = World.new({ files = F.files(cfgWith({ { name = "Drag", type = "race", timeLimit = 120, start = p(500),
                                                    checkpoints = { p(900) }, via = {} } })) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:driveAll({ { A, p(500, 5), 40 }, { B, p(500, -5), 40 } }); w:step(1.5)
  w:chat(A, "/tg testevent 1")
  t.ok(w:chatHas(A, "Press I'm ready - once everyone is, anyone can press GO."))
  t.eq(w:state(A).phase, "travel")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready"); w:chat(A, "/tg go")
  t.eq(w:state(A).phase, "countdown")
  w:assertClean()
end)
