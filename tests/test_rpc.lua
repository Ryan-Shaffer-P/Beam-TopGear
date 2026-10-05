-- Star in a reasonably priced car (0.9.12): every driver, one at a time, in a fresh copy of the same car;
-- 3 laps, the best one counts; their own car waits at the start untouched.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

-- the lap: start/finish line at x=500, round a checkpoint at x=800 and back
local function rpcCourse(extra)
  local e = { name = "Star in a Reasonably Priced Car", type = "rpc", laps = 3, timeLimit = 300,
              start = p(500), checkpoints = { p(800) }, via = {} }
  for k, v in pairs(extra or {}) do e[k] = v end
  return F.config({ e })
end

local function toTheStart(w, A, B)
  w:chat(A, "/tg start")
  w:buy(A, "pessima", "base_M"); w:buy(B, "miramar", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  w:driveAll({ { A, p(490, 12), 45 }, { B, p(495, -14), 35 } })   -- parked beside the line (start zone: 20 m); Alice first
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
end

local function lap(w, pl, speed)   -- out to the checkpoint and back over the line
  w:drive(pl, p(800), speed); w:drive(pl, p(500), speed)
end

local function vehicleCount(pl) local n = 0 for _ in pairs(pl.vehicles) do n = n + 1 end return n end

t.test("star in a reasonably priced car: one at a time, a fresh RPC each, best of 3 laps wins, own cars untouched", function()
  local w = World.new({ files = F.files(rpcCourse()) })
  local A, B = w:join("Alice"), w:join("Bob")
  toTheStart(w, A, B)
  local ownA, ownB = A.current, B.current
  w:damage(A, 2500); w:step(2.5)   -- Alice's own car is dented - it must stay that way
  local parkedAt = ownA.pos.x

  t.ok(w:chatHas(A, "One at a time - running order: Alice, Bob."), "always time trial mode")
  t.ok(w:chatHas(A, "Alice's reasonably priced car is on its way to the start line."))
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 20, "Alice's GO")
  t.ok(A.current ~= ownA, "Alice is in another car")
  t.eq(A.current.model, "covet", "the default reasonably priced car")
  t.eq(A.current.configName, "DXi_A")
  t.eq(A.current.pos.x, 500, "on the start line")
  t.eq(vehicleCount(A), 2, "her own car is still there")
  t.ok(w:chatHas(A, "Here's your reasonably priced car - get ready!"))
  t.eq(B.current, ownB, "Bob waits in his own car")

  lap(w, A, 40)     -- ~15 s
  t.ok(w:chatHas(A, "Lap 1/3 done:"))
  lap(w, A, 50)     -- ~13 s: the best
  lap(w, A, 30)     -- ~21 s
  -- (exact times depend on the harness's 4 Hz positions and the checkpoint radius: check the rule, not the digits)
  local laps = {}
  for _, l in ipairs(A.chat) do
    local n, tm = l:match("Alice: lap (%d) %- (%d+:%d%d%.%d%d)")
    if n then laps[tonumber(n)] = tm end
  end
  t.ok(laps[1] and laps[2] and laps[3], "three timed laps")
  t.ok(laps[2] < laps[1] and laps[2] < laps[3], "lap 2 (the quickest drive) is the best: " .. table.concat(laps, ", "))
  t.ok(w:chatHas(A, "Alice's best lap: " .. laps[2]), "the best lap counts, not the total")
  local aliceBest = laps[2]
  t.eq(ownA.pos.x, parkedAt, "her own car never moved")

  w:waitFor(function() return w:sawMessage(B, "Bob: GO!") end, 30, "Bob's GO")
  t.eq(A.current, ownA, "Alice is back in her own car")
  t.eq(vehicleCount(A), 1, "her RPC is gone")
  t.eq(ownA.damage, 2500, "with its dents")
  t.eq(B.current.model, "covet", "Bob gets the same car - a fresh one")
  lap(w, B, 60)     -- ~11 s
  lap(w, B, 45)
  lap(w, B, 40)
  w:waitFor(function() return w:state(A).phase ~= "event" end, 15, "the results")
  t.eq(B.current, ownB, "Bob is back in his own car")
  t.ok(w:chatHas(A, "1st  Bob - best lap 0:1"), "Bob's quicker lap wins")
  t.ok(w:chatHas(A, "2nd  Alice - best lap " .. aliceBest))
  t.ok(w:chatHas(A, "(3 laps timed)"))
  t.noLine(A.chat, "illegal reset")
  t.eq(w:state(A).cash, 10000 - 5000 + 500 + 3000, "nothing charged for the RPC: car, 1st to arrive, 2nd place")
  t.eq(w:state(B).cash, 10000 - 3500 + 250 + 6000)
  w:assertClean()
end)

t.test("a fresh car on your turn: /tg respawn (or unstick) puts a new RPC on the line, that lap doesn't count; no tows", function()
  local w = World.new({ files = F.files(rpcCourse()) })
  local A, B = w:join("Alice"), w:join("Bob")
  toTheStart(w, A, B)
  local ownA = A.current
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 20, "Alice's GO")
  local first = A.current
  w:drive(A, p(700), 40)                   -- off into the scenery on lap 1...
  w:chat(A, "/tg tow")
  t.ok(w:chatHas(A, "You're in the reasonably priced car - /tg respawn gets you a fresh one"), "no tow in the RPC")
  local cash = w:state(A).cash
  w:chat(A, "/tg respawn"); w:step(2)
  t.ok(w:chatHas(A, "Alice needs a fresh car - lap 1 doesn't count."))
  t.ok(A.current ~= first and A.current ~= ownA, "a new RPC")
  t.eq(A.current.pos.x, 500, "on the start line")
  t.eq(A.vehicles[first.vid], nil, "the old one is gone")
  t.eq(w:state(A).cash, cash, "free")
  lap(w, A, 40)
  t.ok(w:chatHas(A, "Alice: lap 2 - "), "the next lap is lap 2")
  w:chat(A, "/tg unstick"); w:step(2)       -- stuck on lap 3: same thing, and it was the last lap
  t.ok(w:chatHas(A, "Alice gave up the last lap."))
  t.ok(w:chatHas(A, "Alice's best lap: "), "her timed lap 2 stands")
  w:waitFor(function() return w:sawMessage(B, "Bob: GO!") end, 30, "Bob's GO")
  t.eq(A.current, ownA, "Alice is back in her own car")
  lap(w, B, 40); lap(w, B, 40); lap(w, B, 40)
  w:waitFor(function() return w:state(A).phase ~= "event" end, 15, "the results")
  t.ok(w:chatHas(A, "(1 lap timed)"), "Alice's one timed lap counts")
  t.noLine(A.chat, "illegal reset")
  w:assertClean()
end)

t.test("if the RPC never appears (MaxCars 1), that driver can't run and the next one goes", function()
  local w = World.new({ files = F.files(rpcCourse()) })
  local A, B = w:join("Alice"), w:join("Bob")
  A.client.sb.env.core_vehicles.spawnNewVehicle = function() return nil end   -- BeamMP refuses a 2nd car
  toTheStart(w, A, B)
  w:waitFor(function() return w:chatHas(A, "Alice can't run: the reasonably priced car didn't appear") end, 30, "the timeout")
  t.ok(w:chatHas(A, "(the server's MaxCars must be 2 or more)"))
  w:waitFor(function() return w:sawMessage(B, "Bob: GO!") end, 30, "Bob's GO")
  lap(w, B, 40); lap(w, B, 40); lap(w, B, 40)
  w:waitFor(function() return w:state(A).phase ~= "event" end, 15, "the results")
  t.ok(w:chatHas(A, "1st  Bob"))
  t.ok(w:chatHas(A, "--   Alice - DNS"))
  local warned = false
  for i = #A.client.log, 1, -1 do   -- (the expected warning: remove it so the world counts as clean)
    if A.client.log[i].msg:find("reasonably priced car: couldn't spawn", 1, true) then warned = true; table.remove(A.client.log, i) end
  end
  t.ok(warned, "the client says why in the console")
  w:assertClean()
end)

t.test("the driver deletes their RPC: told to respawn; /tg respawn brings a fresh one", function()
  local w = World.new({ files = F.files(rpcCourse()) })
  local A, B = w:join("Alice"), w:join("Bob")
  toTheStart(w, A, B)
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 20, "Alice's GO")
  w:clientDelete(A, A.current)
  t.ok(w:chatHas(A, "Your reasonably priced car is gone - /tg respawn for a fresh one on the start line."))
  t.noLine(A.chat, "out of action")
  w:chat(A, "/tg respawn"); w:step(2)
  t.eq(A.current.model, "covet", "a fresh one")
  lap(w, A, 40)
  t.ok(w:chatHas(A, "Alice: lap 2 - "))
  w:assertClean()
end)

t.test("admin: setrpc picks the car (by name, the one you're in, or the default); always time trial", function()
  local w = World.new({ files = F.files(rpcCourse()) })
  local A = w:join("Alice")
  w:chat(A, "/tg menu"); w:step(2.5)
  t.eq(w:ui(A).course.events[1].rpcCar, "covet / DXi_A", "the default car")
  t.ok(A.client.im.hasButton("Use the car I'm in"), "course builder button")
  w:chat(A, "/tg setmode 1 race")
  t.ok(w:chatHas(A, "is always time trial mode"))
  w:chat(A, "/tg setrpc 1 pessima base_M")
  t.ok(w:chatHas(A, "the reasonably priced car is pessima / base_M"))
  w:buy(A, "miramar", "base_M")               -- (idle: just a car to sit in)
  w:chat(A, "/tg setrpc 1 mine")
  t.ok(w:chatHas(A, "the reasonably priced car is miramar / base_M"))
  t.eq(w:serverConfig().events[1].rpcModel, "miramar", "saved with the course")
  w:chat(A, "/tg setrpc 1 default")
  t.ok(w:chatHas(A, "the reasonably priced car is covet / DXi_A (the default)"))
  w:chat(A, "/tg settype 1 race")
  w:chat(A, "/tg setrpc 1 pessima")
  t.ok(w:chatHas(A, "it's only used by a Star in a reasonably priced car event"))
  w:assertClean()
end)

t.test("setrpc mine: the car you're IN, never a parked traffic car (Ryan: an RPC with no controls)", function()
  local w = World.new({ files = F.files(rpcCourse()) })
  local A = w:join("Alice")
  -- a parked traffic car first (lowest vid - the old code took the first car listed), then the car she sits in
  w:clientSpawn(A, "simple_traffic", { autoEnterVehicle = false, pos = p(300, 10),
                                       config = "vehicles/simple_traffic/legran_wagon_facelift_s_parked.pc" })
  w:pump(); w:step(0.25)
  w:buy(A, "miramar", "base_M")
  w:step(1.5)                                 -- (her game reports the car she's in)
  w:chat(A, "/tg setrpc 1 mine")
  t.ok(w:chatHas(A, "the reasonably priced car is miramar / base_M"), "the car she's in")
  w:chat(A, "/tg setrpc 1 simple_traffic legran_wagon_facelift_s_parked")
  t.ok(w:chatHas(A, "simple_traffic / legran_wagon_facelift_s_parked is a parked traffic car - it can't be driven. Pick a normal car."))
  t.eq(w:serverConfig().events[1].rpcModel, "miramar", "unchanged")
  w:assertClean()
end)

t.test("a course saved with a parked traffic car as its RPC uses the default car instead", function()
  local w = World.new({ files = F.files(rpcCourse({ rpcModel = "simple_traffic", rpcConfig = "legran_wagon_facelift_s_parked" })) })
  local A = w:join("Alice")
  w:chat(A, "/tg menu"); w:step(2.5)
  t.eq(w:ui(A).course.events[1].rpcCar, "covet / DXi_A", "the default car")
  w:assertClean()
end)

t.test("out of time on your turn: your best timed lap still counts", function()
  local w = World.new({ files = F.files(rpcCourse({ timeLimit = 40 })) })
  local A, B = w:join("Alice"), w:join("Bob")
  toTheStart(w, A, B)
  w:waitFor(function() return w:sawMessage(A, "Alice: GO!") end, 20, "Alice's GO")
  lap(w, A, 40)                                -- one lap, then dawdles
  w:drive(A, p(600), 2)
  t.ok(w:chatHas(A, "Alice is out of time."))
  t.ok(w:chatHas(A, "Alice's best lap: 0:15"))
  w:waitFor(function() return w:sawMessage(B, "Bob: GO!") end, 30, "Bob's GO")
  w:chat(A, "/tg next")                        -- admin ends it: Bob had no lap yet
  w:waitFor(function() return w:state(A).phase ~= "event" end, 15, "the results")
  t.ok(w:chatHas(A, "1st  Alice - best lap 0:15"))
  t.ok(w:chatHas(A, "--   Bob - DNF"))
  t.eq(#(function() local o = {} for vid in pairs(B.vehicles) do o[#o + 1] = vid end return o end)(), 1, "Bob's RPC removed at the end")
  w:assertClean()
end)

t.test("the RPC's start is the normal 5 s lights - the 10 s settle-in timer is gone (0.9.13: I'm ready, then GO instead)", function()
  local w = World.new({ files = F.files(rpcCourse()) })
  local A, B = w:join("Alice"), w:join("Bob")
  toTheStart(w, A, B)   -- (everyone arrived in their own cars; /tg go - the old automatic flow, readyToGo off)
  w:waitFor(function() return A.current and A.current.model == "covet" end, 5, "Alice in the RPC")
  w:step(1)
  t.eq(w:state(A).lights and w:state(A).lights.total, 5, "the start lights count 5 s, like every start")
  w:step(5)
  t.ok(w:sawMessage(A, "Alice: GO!"), "then GO")
  w:assertClean()
end)

t.test("the course builder takes positions from the car you're in (not a parked one); stacked checkpoints are caught", function()
  local cfg = F.config({ { name = "RPC", type = "rpc", laps = 3, timeLimit = 300, via = {} } })
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg traffic on")
  w:buy(A, "pessima", "base_M"); w:drive(A, p(500), 40)       -- one car parked on the start line...
  w:chat(A, "/tg setstart 1")
  w:buy(A, "covet", "base_M"); w:step(1.5)                    -- ...and the one she's driving
  w:drive(A, p(800), 40); w:step(1.5)
  w:chat(A, "/tg addcp 1")
  t.eq(w:serverConfig().events[1].checkpoints[1].x, 800, "the checkpoint is where she is, not at the parked car")
  w:drive(A, p(505), 40); w:step(1.5)
  w:chat(A, "/tg addcp 1")
  t.ok(w:chatHas(A, "Careful: checkpoint 2 is on top of the start (5 m)."), "a checkpoint on the start line is flagged")
  w:chat(A, "/tg traffic off"); w:chat(A, "/tg setfinale")
  w:chat(A, "/tg start")
  t.ok(w:chatHas(A, "Event 1 (RPC): checkpoint 2 is on top of the start (5 m) - move the start (/tg setstart 1, or Set start here: your checkpoints stay)"))
  t.eq(w:state(A) and w:state(A).phase or "idle", "idle", "won't start like that")
  w:assertClean()
end)

t.test("course builder layout: Pick a course / Event type / Events + big buttons / Event options / Save course", function()
  local w = World.new({ files = F.files(rpcCourse()) })
  local A = w:join("Alice")
  w:chat(A, "/tg menu"); w:step(2.5)
  local heads = {}
  for _, it in ipairs(A.client.im.items("Top Gear Challenge")) do if it.kind == "header" then heads[#heads + 1] = it.label end end
  local order = table.concat(heads, "|")
  t.ok(order:find("Course|Pick a course|Event type|Waypoints|Event options|Save course|Workshop locations|Session", 1, true), order)
  t.ok(A.client.im.textOf("Top Gear Challenge"):find("\nEvents\nPick the one to edit:", 1, true), "Events: a heading, not foldable")
  -- the place-it buttons, each line centred (the fake has no CalcTextSize: by character count)
  t.ok(A.client.im.hasButton("Set start\n   here") and A.client.im.hasButton("    Add\ncheckpoint") and
       A.client.im.hasButton("   Undo\ncheckpoint") and A.client.im.hasButton("   Clear\ncheckpoints"), "the big place-it buttons, centred")
  t.ok(A.client.im.hasButton("Add route\n waypoint"), "the Waypoints box")
  t.ok(A.client.im.hasButton("Delete event 1"), "Delete is in the Events box")
  t.ok(A.client.im.textOf("Top Gear Challenge"):find("Time to complete event (s):", 1, true))
  t.ok(A.client.im.hasButton("Set Time"))
  A.client.im.setInt("# of laps##laps", 5); w:step(1)
  t.eq(w:serverConfig().events[1].laps, 5, "# of laps is sent as it changes")
  w:buy(A, "covet", "base_M"); w:drive(A, p(650), 40); w:step(1.5)   -- (a car to place it with)
  A.client.im.click("##big_addcp"); w:step(1)
  t.eq(#w:serverConfig().events[1].checkpoints, 2, "Add checkpoint works")
  A.client.im.click("##big_clearcp"); w:step(1)
  t.eq(#w:serverConfig().events[1].checkpoints, 2, "Clear needs a second click")
  A.client.im.click("##big_clearcp"); w:step(1)   -- (now "Really? Clear checkpoints")
  t.eq(#w:serverConfig().events[1].checkpoints, 0, "cleared")
  w:assertClean()
end)

t.test("course builder: each event in the list says RACE or TIME TRIAL", function()
  local cfg = F.config({
    { name = "Drag", type = "race", timeLimit = 120, start = p(500), checkpoints = { p(900) }, via = {} },
    { name = "Hill Climb", type = "race", solo = true, timeLimit = 120, start = p(1500), checkpoints = { p(1900) }, via = {} },
    { name = "Star in a Reasonably Priced Car", type = "rpc", laps = 3, timeLimit = 300, start = p(2500), checkpoints = { p(2800) }, via = {} },
  })
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg menu"); w:step(2.5)
  local items, tags = A.client.im.items("Top Gear Challenge"), {}
  for i, it in ipairs(items) do
    if it.text == "RACE" or it.text == "TIME TRIAL" then
      local nxt = items[i + 2]   -- (SameLine, then the event's line)
      tags[#tags + 1] = it.text .. ": " .. tostring(nxt and nxt.text):match("^(.-) %[")
    end
  end
  t.eq(table.concat(tags, " | "), "RACE: Drag | TIME TRIAL: Hill Climb | TIME TRIAL: Star in a Reasonably Priced Car")
  w:assertClean()
end)

t.test("the RPC: you get in once BeamMP says it's yours - and again if it only says so later (no spectating)", function()
  local w = World.new({ files = F.files(rpcCourse()) })
  local A, B = w:join("Alice"), w:join("Bob")
  A.client.notOwnUntil = 1e9   -- BeamMP hasn't confirmed Alice's next car yet
  toTheStart(w, A, B)
  local ownA = A.current
  A.client.notOwnUntil = w.t + 10   -- ...it will, 10 s from now
  w:waitFor(function() return A.current and A.current.model == "covet" end, 15, "Alice in the RPC")
  w:chat(A, "/tg diag"); w:step(2)
  t.ok(w:chatHas(A, "Reasonably priced car: in it: true | yours per BeamMP:"), "/tg diag shows BeamMP's view")
  t.ok(w:chatHas(A, "BeamMP's record: owner Alice"))
  w:waitFor(function() return w.t > A.client.notOwnUntil + 2 end, 20, "BeamMP confirms it")
  local again = false
  for _, l in ipairs(A.client.log) do if l.msg:find("got in again", 1, true) then again = true end end
  t.ok(again, "switched out and back in once BeamMP said it was hers")
  t.ok(A.current ~= ownA and A.current.model == "covet", "in the RPC")
  -- (the expected warning: she got in after 8 s before BeamMP had confirmed it)
  for i = #A.client.log, 1, -1 do if A.client.log[i].msg:find("hasn't confirmed it's yours", 1, true) then table.remove(A.client.log, i) end end
  w:assertClean()
end)
