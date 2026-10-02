-- Persistent game state (0.9.8): the running challenge is saved to session.json; after a crash or restart it
-- comes back paused, an admin resumes it, cars come back as they were (upgrades kept) and each driver pays their
-- car's repairs. An interrupted event is run again. A player who drops and rejoins gets their car back the same way.
-- A "crash" here = a new World built from the old one's files (no disconnect events, every car gone).
local t = require("t")
local World = require("world")
local F = require("fixtures")
local json = require("json")
local p = F.p

local SESSION = "Resources/Server/TopGear/session.json"
local function crash(w)   -- the server dies and comes back with the same files
  local files = {}
  for k, v in pairs(w.files) do files[k] = v end
  return World.new({ files = files })
end
local function saved(w) return json.decode(assert(w.files[SESSION], "no session.json")) end
local function near(v, x, y, r) return v and math.abs(v.pos.x - x) < (r or 8) and math.abs(v.pos.y - (y or 0)) < (r or 8) end
local function startTwo(w)
  local A, B = w:join("Alice"), w:join("Bob")   -- Alice is the admin
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  return A, B
end
local function lastCost(pl)   -- "...its repairs cost $X..." from the car-back message
  for i = #pl.chat, 1, -1 do
    local n = pl.chat[i]:match("its repairs cost %$([%d,]+)")
    if n then return tonumber((n:gsub(",", ""))) end
  end
  return 0
end

t.test("the challenge is saved while it runs, and marked idle when it stops", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = startTwo(w)
  w:step(6)
  local s = saved(w)
  t.eq(s.game.phase, "travel")
  t.ok(s.game.players.Alice and s.game.players.Bob, "both drivers")
  t.eq(s.game.players.Alice.carModel, "covet")
  t.eq(s.game.players.Alice.pid, nil, "no game ids in the save")
  w:chat(A, "/tg stop")
  w:step(1)
  t.eq(saved(w).game.phase, "idle")
  w:assertClean()
end)

t.test("crash on the road: restored paused; Resume brings the cars back where they were; repairs are paid", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = startTwo(w)
  w:chat(A, "/tg give Alice 1234")
  w:driveAll({ { A, p(300, 20), 40 }, { B, p(200, -20), 40 } })
  w:damage(A, 4000); w:step(2.5)
  w:step(6)
  local cashA, cashB = w:state(A).cash, w:state(B).cash

  local w2 = crash(w)
  t.ok(w2:consoleHas("restored a challenge in progress (travel, stage 1, 2 drivers)"))
  local A2 = w2:join("Alice")
  t.eq(w2:state(A2).phase, "paused")
  t.match(w2:state(A2).title, "waiting for an admin")
  t.ok(w2:chatHas(A2, "Welcome back - the challenge was saved"))
  w2:step(2.5)
  local s = A2.client.im.textOf("Top Gear Challenge")
  t.match(s, "CHALLENGE SAVED"); t.match(s, "Not back yet: Bob"); t.ok(A2.client.im.hasButton("Resume the challenge"))
  t.eq(w2:buy(A2, "covet", "base_M"), nil, "no spawning while paused")
  w2:chat(A2, "/tg start")
  t.ok(w2:chatHas(A2, "A saved challenge is waiting"))

  local B2 = w2:join("Bob")
  t.ok(w2:chatHas(A2, "Bob is back."))
  w2:chat(A2, "/tg resume")
  t.ok(w2:chatHas(A2, "Challenge resumed - your cars are being brought back where they were."))
  w2:step(6)
  t.ok(near(w2:car(A2), 300, 20), "Alice's car is back where it was")
  t.ok(near(w2:car(B2), 200, -20), "Bob's too")
  t.eq(w2:state(A2).phase, "travel")
  local cost = lastCost(A2)
  t.ok(cost > 0, "Alice's damaged car: she pays its repairs")
  t.eq(w2:state(A2).cash, cashA - cost)
  t.eq(w2:state(B2).cash, cashB, "Bob's car was undamaged: free")
  t.eq(w2:state(A2).points, 0, "no tow penalty")
  -- and the challenge carries on
  w2:driveAll({ { A2, p(500), 40 }, { B2, p(500), 35 } })
  w2:chat(A2, "/tg go")
  w2:waitFor(function() return w2:state(A2).phase == "event" end, 10, "GO")
  w2:drive(A2, p(900), 40); w2:drive(B2, p(900), 30)
  w2:waitFor(function() return w2:state(A2).phase == "travel" and w2:state(A2).points > 0 end, 15, "Race One's results")
  w2:assertClean()
end)

t.test("crash during an event: it's run again from its start line, with no double arrival bonus", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = startTwo(w)
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 35 } })
  local cashA = w:state(A).cash
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)   -- Alice finishes, Bob is still going when the server dies
  w:step(6)

  local w2 = crash(w)
  local A2, B2 = w2:join("Alice"), w2:join("Bob")
  w2:chat(A2, "/tg resume")
  t.ok(w2:chatHas(A2, "Race One is run again from the start"))
  w2:step(6)
  t.eq(w2:state(A2).phase, "travel")
  t.ok(near(w2:car(A2), 500, 0, 12) and near(w2:car(B2), 500, 0, 12), "both cars at Race One's start line")
  t.eq(w2:state(A2).cash, cashA, "no second arrival bonus, nothing to repair")
  w2:step(2.5)
  t.ok(w2:chatHas(A2, "Everyone's at Race One!"), "everyone's already there")
  w2:chat(A2, "/tg go")
  w2:waitFor(function() return w2:state(A2).phase == "event" end, 10, "GO again")
  w2:drive(B2, p(900), 40); w2:drive(A2, p(900), 30)   -- this time Bob wins
  w2:waitFor(function() return w2:state(A2).phase == "travel" end, 15, "results")
  t.eq(w2:state(B2).wins, 1); t.eq(w2:state(A2).wins, 0, "the first, unfinished run doesn't count")
  w2:assertClean()
end)

t.test("upgrades and setup faults come back with the car", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M")
  w:step(2.5)
  A.client.im.click("Fit##fit_/covet_engine/_covet_engine_turbo")
  w:step(3)
  t.eq(A.current.parts["/covet_engine/"], "covet_engine_turbo")
  w:chat(A, "/tg ready")
  w:drive(A, p(300), 40)
  w:step(6)
  local w2 = crash(w)
  local A2 = w2:join("Alice")
  w2:chat(A2, "/tg resume")
  w2:step(6)
  t.eq(w2:car(A2).parts["/covet_engine/"], "covet_engine_turbo", "the turbo is still fitted")
  t.eq(lastCost(A2), 0, "putting its own parts back isn't billed")
  t.noLine(A2.chat, "Parts fitted", "nor charged as new parts")
  w2:assertClean()
end)

t.test("a workshop keeps its remaining time across a crash", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A, B = startTwo(w)
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 35 } })
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40); w:drive(B, p(900), 35)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:step(60)   -- a minute into the workshop
  local before = saved(w).game.timers.workshopEnd   -- what was left at the last save
  local w2 = crash(w)
  local A2 = w2:join("Alice"); w2:join("Bob")
  w2:step(30)   -- the restart takes a while: the clock doesn't run while paused
  w2:chat(A2, "/tg resume")
  t.ok(math.abs(saved(w2).game.timers.workshopEnd - before) < 0.5, "saved again at Resume with the same time left")
  w2:step(5.5)   -- the next save
  t.eq(w2:state(A2).phase, "workshop")
  local left = saved(w2).game.timers.workshopEnd
  t.ok(left < before - 4.5 and left > before - 6, string.format("%.1f s left at the crash, %.1f after ~5 s of play", before, left))
  w2:assertClean()
end)

t.test("one driver drops and rejoins: their car comes back where it was; they pay its repairs, no tow", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = startTwo(w)
  w:drive(B, p(250, 10), 40)
  w:damage(B, 3000); w:step(2.5)
  local cash = w:state(B).cash
  w:leave(B)
  t.ok(w:chatHas(A, "Bob has left."))
  local B2 = w:join("Bob")
  t.ok(w:chatHas(B2, "Welcome back Bob - your Ibishu Pessima"), "the car's coming back")
  w:step(6)
  t.ok(near(w:car(B2), 250, 10), "where he left it")
  local cost = lastCost(B2)
  t.ok(cost > 0)
  t.eq(w:state(B2).cash, cash - cost)
  t.eq(w:state(B2).points, 0, "no tow penalty")
  t.ok(not w:chatHas(A, "calls the tow truck"), "not a tow")
  w:assertClean()
end)

t.test("Discard drops a saved challenge; results survive a restart as they were", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  startTwo(w)
  w:step(6)
  local w2 = crash(w)
  local A2 = w2:join("Alice")
  w2:chat(A2, "/tg discard")
  w2:waitFor(function() return w2:chatHas(A2, "Discard it") or true end, 1)
  w2:chat(A2, "/tg discard")
  t.ok(w2:chatHas(A2, "The saved challenge was discarded."))
  t.eq(w2:state(A2).phase, "idle")
  t.eq(saved(w2).game.phase, "idle")
  local w3 = crash(w2)
  w3:join("Alice")
  t.ok(not w3:consoleHas("restored a challenge"), "nothing comes back after a discard")
  w2:assertClean(); w3:assertClean()
end)

t.test("Save.pack keeps number-keyed tables and holes through JSON", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = startTwo(w)
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 35 } })
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40); w:drive(B, p(900), 35)
  w:waitFor(function() return w:state(A).phase == "travel" end, 10, "results")
  w:chat(A, "/tg tow")   -- a tow to Race Two fills towSlots[2] (a table with only key 2)
  w:step(6)
  local w2 = crash(w)
  local A2 = w2:join("Alice"); w2:join("Bob")
  w2:chat(A2, "/tg resume"); w2:step(6)
  t.eq(w2:state(A2).wins, 1, "Race One's win kept")
  t.eq(saved(w2).game.towSlots["#2"], 1, "towSlots[2] survives as a number key")
  w2:assertClean()
end)
