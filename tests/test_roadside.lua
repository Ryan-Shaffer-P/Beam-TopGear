-- Roadside help (0.8.6): tow / respawn / unstick cost the repair price x 1.25 plus a fee, and -1 pt each.
-- Workshop repair price = $250 + $0.50 x damage (cap $6,000 on the damage part); none under 50 damage.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function onTheRoad(w, ...)
  local players = { ... }
  w:chat(players[1], "/tg start")
  local models = { "covet", "pessima", "miramar" }
  for i, pl in ipairs(players) do w:buy(pl, models[i], "base_M") end
  for _, pl in ipairs(players) do w:chat(pl, "/tg ready") end
  t.eq(w:state(players[1]).phase, "travel")
end
local function dent(w, pl, dmg) w:damage(pl, dmg); w:step(2.5) end   -- the damage report reaches the server

t.test("tow: repair x 1.25 + $1,000; the Status button shows the live price", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  onTheRoad(w, A)
  t.eq(w:state(A).cash, 5500)   -- (the window is already open: /tg start opens it)
  dent(w, A, 2000)   -- workshop price 250 + 1000 = 1250 -> roadside 1562.5 -> $1,563, + $1,000 fee = $2,563
  w:step(2.5)
  t.ok(A.client.im.hasButton("Tow ($2,563)"), "the button shows the price")
  w:chat(A, "/tg tow")
  t.ok(w:chatHas(A, "Alice calls the tow truck (-$2,563: repair $1,563 + fee $1,000, -2 pts)"))
  t.eq(w:state(A).cash, 5500 - 2563)
  w:assertClean()
end)

t.test("respawn: repair x 1.25 + $500, so a wrecked car is never cheap to fix at the roadside", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  onTheRoad(w, A, B)
  dent(w, A, 10000)  -- 250 + 5000 = 5250 -> x 1.25 = 6562.5 -> $6,563, + $500 = $7,063
  w:chat(A, "/tg respawn")
  t.ok(w:chatHas(A, "Alice respawns their Ibishu Covet on the spot (-$7,063: repair $6,563 + fee $500, -2 pts)."))
  t.eq(w:state(A).cash, 5500 - 7063, "into the red")
  w:chat(B, "/tg respawn")   -- Bob's car is undamaged: just the fee
  t.ok(w:chatHas(B, "Bob respawns their Ibishu Pessima (1988) on the spot (-$500, -2 pts)."))
  t.eq(w:state(B).cash, 5000 - 500)
  w:assertClean()
end)

t.test("the workshop is the cheapest repair", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  onTheRoad(w, A)
  dent(w, A, 2000)
  w:chat(A, "/tg quote")
  t.ok(w:chatHas(A, "Repair: $1,250 (damage 2000)"), "workshop price $1,250 vs $1,563 at the roadside")
  w:assertClean()
end)

t.test("unstick is free and keeps the damage, unless the game repairs the car - then it's billed once", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  onTheRoad(w, A, B, C)
  for _, pl in ipairs({ A, B, C }) do dent(w, pl, 2000) end

  w:chat(A, "/tg unstick")      -- a game where the move doesn't repair: free
  w:step(5)
  t.eq(A.current.damage, 2000, "damage kept")
  t.eq(w:state(A).cash, 5500)

  B.client.teleportRepairs = "silent"   -- the move repairs the car, no reset reported
  w:chat(B, "/tg unstick")
  w:step(5)
  t.ok(w:chatHas(B, "Unstick repaired your car on this BeamNG version - that roadside repair is billed ($1,563)."))
  t.eq(w:state(B).cash, 5000 - 1563)

  C.client.teleportRepairs = "reset"    -- the move repairs it and BeamMP reports a reset
  w:chat(C, "/tg unstick")
  w:step(5)
  t.eq(w:state(C).cash, 6500 - 1563, "billed once, not for both the reset and the damage drop")
  t.noLine(C.chat, "pressed the reset button")
  w:assertClean()
end)

t.test("each tow and respawn costs 2 points at the final standings", function()
  local cfg = F.config({
    { name = "Race One", type = "race", timeLimit = 120, start = p(500), checkpoints = { p(700) }, via = {} },
  }, { finale = { name = "The Test Track", pos = p(1500), radius = 25, timeLimit = 1200, via = {} } })
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  onTheRoad(w, A)
  w:chat(A, "/tg tow")          -- delivered to Race One's start
  w:step(20)                    -- (a reset within 15 s of a tow is part of the tow, not fined)
  w:resetCar(A)                 -- two illegal resets, -2 each
  w:resetCar(A)
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(700), 40)
  w:waitFor(function() return w:state(A).phase == "finale" end, 10, "the finale")
  w:chat(A, "/tg respawn")
  w:drive(A, p(1500), 40)
  w:waitFor(function() return w:state(A).phase == "results" end, 10, "results")
  -- 10 (race) + 0 drivability (no workshops; respawned on the final leg: 0 at the finale) - 2 x 2 resets - 2 x 2 (tow + respawn) = 2
  t.ok(w:chatHas(A, "Alice loses 8 pts: 2 illegal resets (-4), 2 tows/respawns (-4)."))
  t.eq(w:state(A).points, 2)
  w:assertClean()
end)

t.test("saved configs with the old flat $2,000 fees get the new ones; custom fees are kept", function()
  local w = World.new({ files = F.files(F.config({}, { economy = { towFee = 2000, respawnFee = 2000 } })) })
  local ec = w:serverConfig().economy
  t.eq(ec.towFee, 1000); t.eq(ec.respawnFee, 500); t.eq(ec.roadsideMarkup, 1.25)
  local w2 = World.new({ files = F.files(F.config({}, { economy = { towFee = 1500, respawnFee = 750 } })) })
  local ec2 = w2:serverConfig().economy
  t.eq(ec2.towFee, 1500); t.eq(ec2.respawnFee, 750)
  t.eq(w2:serverConfig().scoring.towPenaltyPoints, 2)
end)

t.test("a workshop repair (and a workshop respawn) fixes the car where it stands - no teleport", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  onTheRoad(w, A)
  w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:drive(A, p(950, 40), 20)              -- pull into the gas station
  dent(w, A, 2000)
  w:chat(A, "/tg repair")
  w:step(3)
  t.eq(A.current.damage, 0, "repaired")
  t.ok(math.abs(A.current.pos.x - 950) < 1 and math.abs(A.current.pos.y - 40) < 1,
    string.format("still at the gas station, not moved to (%.0f, %.0f)", A.current.pos.x, A.current.pos.y))
  dent(w, A, 2000)
  w:chat(A, "/tg respawn")
  w:step(3)
  t.eq(A.current.damage, 0, "respawned")
  t.ok(math.abs(A.current.pos.x - 950) < 1 and math.abs(A.current.pos.y - 40) < 1, "a respawn stays put too")
  w:assertClean()
end)

t.test("on a game without spawn.safeTeleport, a repair resets and puts the car back where it was", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  A.client.sb.set("spawn", nil)
  onTheRoad(w, A)
  w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:drive(A, p(950, 40), 20)
  dent(w, A, 2000)
  w:chat(A, "/tg repair")
  w:step(3)
  t.eq(A.current.damage, 0, "repaired")
  t.ok(math.abs(A.current.pos.x - 950) < 1 and math.abs(A.current.pos.y - 40) < 1, "put back at the gas station")
  local pr = w:problems()
  t.eq(#pr, 1, "only the fallback note:\n" .. table.concat(pr, "\n"))
  t.match(pr[1], "repair in place: no spawn.safeTeleport")
end)

t.test("repairs, tows and respawns can go as deep into the red as they need; parts and fault fixes stop at -$1,500", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:chat(A, "/tg fault take")
  w.rolls = { 5 }; w:buy(A, "covet", "base_M")   -- (draw 5 = worn brakes: a fault to try fixing later)
  w:step(10)
  w:chat(A, "/tg ready")
  w:chat(A, "/tg setcash Alice 0")
  dent(w, A, 10000)
  w:chat(A, "/tg tow")                     -- 250 + 5000 = 5250 x 1.25 = 6563 + 1000
  t.eq(w:state(A).cash, -7563, "a tow goes past the $1,500 limit")
  dent(w, A, 4000)
  w:step(20)
  w:chat(A, "/tg respawn")                 -- 250 + 2000 = 2250 x 1.25 = 2813 + 500
  t.eq(w:state(A).cash, -7563 - 3313, "so does a respawn")

  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)                   -- 1st: +$6,000
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  local cash = w:state(A).cash
  t.eq(cash, -10876 + 6000)
  dent(w, A, 8000)
  w:chat(A, "/tg repair")                  -- 250 + 4000 = $4,250, far past the limit: allowed
  t.ok(w:chatHas(A, "Alice paid $4,250 to have their Ibishu Covet repaired."))
  t.eq(w:state(A).cash, cash - 4250)
  t.ok(w:chatHas(A, "You're overdrawn: -$9,126. Prize money pays it off. (Parts and problem fixes stop at -$1,500 overdrawn.)"))
  w:chat(A, "/tg fix brakes")              -- $3,750: refused, way past -$1,500
  t.ok(w:chatHas(A, "Fixing that costs $500 - you have -$9,126 (at most $1,500 overdrawn)."))
  -- a part fitted with the game's own parts menu: refused by the server, taken back off the car
  local parts = {}
  for k, v in pairs(A.current.parts) do parts[k] = v end
  parts["/covet_engine/"] = "covet_engine_turbo"
  A.client.sb.env.core_vehicle_partmgmt.setPartsConfig(parts, true)
  w:pump(); w:step(4)
  t.ok(w:chatHas(A, "You can't afford that: it costs $1,500 and you have -$9,126 (at most $1,500 overdrawn). Taking the parts back off."))
  t.eq(A.current.parts["/covet_engine/"], "covet_engine", "the part came back off")
  t.eq(w:state(A).cash, -9126, "nothing charged")
  w:assertClean()
end)
