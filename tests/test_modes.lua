-- Race mode / time trial mode on every event (0.8.4); the old "timetrial" type is gone.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function soloOf(w, A, n) return w:ui(A).course.events[n].solo end

t.test("old time trial events become destination races in time trial mode", function()
  local cfg = F.config({
    { name = "Old Trial",  type = "timetrial", start = p(500), checkpoints = { p(700) }, via = {} },
    { name = "Hill Climb", type = "race", start = p(1500), checkpoints = { p(1700) }, via = {} },          -- never migrated
    { name = "Hill Climb 2", type = "race", solo = false, start = p(2500), checkpoints = { p(2700) }, via = {} }, -- chose race mode
  })
  local w = World.new({ files = F.files(cfg) })
  local saved = w:serverConfig().events
  t.eq(saved[1].type, "race"); t.eq(saved[1].solo, true)
  t.eq(saved[2].solo, true, "an unmigrated Hill Climb race runs one at a time")
  t.eq(saved[3].solo, false, "an explicit race mode is kept")
  t.anyLine(w.console, "'Old Trial' is now a destination race in time trial mode")
  w:assertClean()
end)

t.test("time trial is no longer an event type; settype timetrial still works as a shortcut", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg menu")
  w:step(2.5)
  for _, ty in ipairs(w:ui(A).course.types) do t.ok(ty.id ~= "timetrial", "no timetrial type offered") end
  t.ok(not A.client.im.hasButton("Time trial"), "no Time trial type button")
  w:chat(A, "/tg settype 2 timetrial")
  t.ok(w:chatHas(A, "event 2 is now a destination race in time trial mode"))
  w:step(2.5)
  t.eq(w:ui(A).course.events[2].type, "race")
  t.eq(soloOf(w, A, 2), true)
  w:chat(A, "/tg settype 2 slalom")
  t.ok(w:chatHas(A, "event 2 is now a slalom, in time trial mode (one at a time)."), "a type change resets to that type's default mode")
  w:assertClean()
end)

t.test("setmode switches any event between race mode and time trial mode, from chat or the course builder", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg menu")
  w:step(2.5)
  t.eq(soloOf(w, A, 1), false, "a race defaults to race mode")
  w:chat(A, "/tg setmode 1 trial")
  t.ok(w:chatHas(A, "event 1 now runs in time trial mode (one at a time)."))
  w:chat(A, "/tg setmode 1 race")
  t.ok(w:chatHas(A, "event 1 now runs in race mode (everyone at once)."))
  w:chat(A, "/tg setmode 1 sideways")
  t.ok(w:chatHas(A, "Usage: /tg setmode <event> race|trial"))
  w:chat(B, "/tg setmode 1 trial")
  t.ok(w:chatHas(B, "That's an admin command."))

  -- the course builder buttons (event 1 is selected by default)
  w:step(2.5)
  t.ok(A.client.im.hasButton("> Race - everyone at once"), "current mode marked")
  A.client.im.click("Time trial - one at a time##modetrial")
  w:step(2.5)
  t.eq(soloOf(w, A, 1), true)
  t.ok(A.client.im.hasButton("> Time trial - one at a time"))
  t.ok(w:serverConfig().events[1].solo == true, "saved to config.json")
  w:assertClean()
end)

t.test("a race switched to time trial mode runs one at a time; a slalom switched to race mode runs together", function()
  local cfg = F.config({
    { name = "Sprint", type = "race",   solo = true,  timeLimit = 120, start = p(500),  checkpoints = { p(700) }, via = {} },
    { name = "Weave",  type = "slalom", solo = false, timeLimit = 120, start = p(1000), checkpoints = { p(1050), p(1100) }, via = {} },
  })
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")

  w:driveAll({ { A, p(500), 40 }, { B, p(500), 35 } })
  w:chat(A, "/tg go")
  t.ok(w:chatHas(A, "One at a time - running order: Alice, Bob."), "Sprint runs as a time trial")
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 20, "Alice's GO")
  w:drive(A, p(700), 40)
  w:waitFor(function() return w:sawMessage(B, "Bob: GO!") end, 20, "Bob's GO")
  w:drive(B, p(700), 30)
  w:waitFor(function() return w:state(A).phase == "travel" end, 10, "leg 2")
  t.ok(w:chatHas(A, "1st  Alice"))

  w:driveAll({ { A, p(1000), 40 }, { B, p(1000), 35 } })
  w:chat(A, "/tg go")
  t.ok(w:chatHas(A, "Weave! Starting in 5 seconds..."), "Weave counts down for everyone at once")
  t.noLine(A.chat, "running order: Alice, Bob, Carol")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:driveAll({ { A, p(1100), 30 }, { B, p(1100), 20 } })
  w:waitFor(function() return w:state(A).phase == "finale" end, 10, "the finale")
  t.ok(w:chatHas(A, "1st  Alice"))
  w:assertClean()
end)

t.test("the running event's mode can't be changed mid-run; the others can", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M")
  w:chat(A, "/tg ready")
  w:drive(A, p(500), 40)
  w:chat(A, "/tg go")
  w:chat(A, "/tg setmode 1 trial")
  t.ok(w:chatHas(A, "That event is running right now - change its mode after it's finished."))
  w:chat(A, "/tg setmode 2 trial")
  t.ok(w:chatHas(A, "event 2 now runs in time trial mode"), "a later event can be switched")
  w:assertClean()
end)

t.test("time trial mode: the next driver isn't started until the current one has finished", function()
  local cfg = F.config({
    { name = "Sprint", type = "race", solo = true, timeLimit = 300, start = p(500), checkpoints = { p(700), p(900) }, via = {} },
  })
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 35 } })
  w:chat(A, "/tg go")
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 20, "Alice's GO")

  w:drive(A, p(700), 20)   -- half way, then she dawdles for a minute
  w:step(60)
  t.ok(not w:sawMessage(B, "Bob: "), "no countdown for Bob while Alice is still out")
  t.eq(w:state(B).target.label, "Wait at the start - Alice is running")

  w:drive(A, p(900), 20)   -- Alice crosses the line
  t.ok(w:chatHas(A, "Alice crosses the line!"))
  w:waitFor(function() return w:sawMessage(B, "Bob: GO!") end, 10, "Bob's GO after Alice finished")
  w:drive(B, p(900), 35)
  w:waitFor(function() return w:state(A).phase ~= "event" end, 10, "results")
  w:assertClean()
end)
