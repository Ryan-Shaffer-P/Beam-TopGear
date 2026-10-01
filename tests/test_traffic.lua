-- Admin traffic mode: /tg traffic on|off lets an admin add non-scoring vehicles in any phase.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function traffic(w, pl, model)   -- what BeamNG's traffic spawner / the vehicle menu does
  local obj = w:clientSpawn(pl, model or "pickup", { autoEnterVehicle = false, pos = p(300, 10) })
  w:pump(); w:step(0.25)
  return obj
end
local function count(pl) local n = 0 for _ in pairs(pl.vehicles) do n = n + 1 end return n end
local function selectorBlocked(pl) return pl.client.filters.tg_vehsel and pl.client.filters.tg_vehsel.blocked end

t.test("traffic mode: an admin adds traffic at the dealership without it counting as a purchase", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")   -- Alice is the admin
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M")
  w:buy(B, "pessima", "base_M")

  t.eq(traffic(w, A), nil, "refused while traffic mode is off")
  t.ok(w:chatHas(A, "You already have a car - delete it first to swap. (Admin: /tg traffic on to add traffic.)"))

  w:chat(A, "/tg traffic on")
  t.ok(w:chatHas(A, "Traffic mode ON"))
  for _ = 1, 3 do t.ok(traffic(w, A), "traffic accepted") end
  t.eq(count(A), 4, "her car + 3 traffic vehicles")
  t.eq(w:state(A).cash, 5500, "traffic costs nothing")
  t.eq(w:state(A).car, "Ibishu Covet", "still her challenge car")
  t.eq(w:state(A).traffic, true)
  t.match(A.client.ui.tg_hud or "", "TRAFFIC MODE")

  -- traffic resets and deletions never touch her score or car
  local tv
  for _, v in pairs(A.vehicles) do if v.model == "pickup" then tv = v end end
  w:vehicleReset(A, tv); w:pump()
  w:clientDelete(A, tv); w:pump()
  t.eq(w:state(A).car, "Ibishu Covet")
  t.noLine(A.chat, "pressed the reset button")

  -- other players are unaffected
  w:chat(B, "/tg traffic on")
  t.ok(w:chatHas(B, "That's an admin command."))
  t.eq(traffic(w, B), nil, "Bob still can't spawn extras")

  for _, pl in ipairs({ A, B }) do w:chat(pl, "/tg ready") end
  t.eq(w:state(A).phase, "travel")
  t.eq(selectorBlocked(A), false, "admin's vehicle menu open in traffic mode")
  t.eq(selectorBlocked(B), true, "everyone else's is locked")

  w:chat(A, "/tg traffic off")
  t.ok(w:chatHas(A, "Traffic mode OFF"))
  t.eq(selectorBlocked(A), true, "locked again")
  t.eq(count(A), 3, "the traffic she placed stays")
  t.eq(w:state(A).traffic, nil)
  w:assertClean()
end)

t.test("traffic mode: turning it on before buying warns that a spawn would be traffic", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:chat(A, "/tg traffic on")
  t.ok(w:chatHas(A, "you haven't bought your own car yet"))
  w:assertClean()
end)

t.test("traffic mode: a lost challenge car still comes back as a tow, not as traffic", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M")
  w:chat(A, "/tg ready")
  w:chat(A, "/tg traffic on")
  w:clientDelete(A, A.current); w:pump(); w:step(0.5)
  t.ok(w:chatHas(A, "Alice's Ibishu Covet is out of action!"))
  w:chat(A, "/tg respawn")
  w:step(1)
  t.eq(w:state(A).car, "Ibishu Covet")
  t.ok(w:chatHas(A, "Alice calls the tow truck (-$1,000, -2 pts)"), "billed as a tow")
  t.eq(w:state(A).cash, 4500)
  w:assertClean()
end)

t.test("traffic mode: course points come from the admin's own car, not from her traffic", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M")
  w:chat(A, "/tg traffic on")
  traffic(w, A)
  w:place(A, p(1234, 5))
  w:chat(A, "/tg setstart 2")
  t.ok(w:chatHas(A, "event 2 start set (1234.0, 5.0, 0.0)"), "start set at her car, not the traffic at x=300")
  w:assertClean()
end)

t.test("traffic mode: the Admin controls button toggles it", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:step(2.5)
  A.client.im.click("Traffic mode (add AI traffic / parked cars)##traffic")
  w:step(2.5)
  t.eq(w:state(A).traffic, true)
  t.ok(A.client.im.hasButton("Turn traffic mode off"))
  A.client.im.click("Turn traffic mode off##traffic")
  w:step(2.5)
  t.eq(w:state(A).traffic, nil)
  w:assertClean()
end)
