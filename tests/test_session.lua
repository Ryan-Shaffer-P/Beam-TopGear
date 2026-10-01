-- Stage 2: a full challenge, start to results (the successor of the Desktop-era sim13).
--
-- Three drivers, five event types, two workshops, faults, a tow, an illegal reset, the finale
-- inspection and the summary table. Expected money and points were worked out by hand from the
-- rules in README.md / main.lua (see the tally at the bottom), not copied from a run.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function sessionCourse()
  return F.config({
    { name = "Race One",     type = "race",      timeLimit = 300, start = p(500),  checkpoints = { p(700), p(900) }, via = {} },
    { name = "Hill Climb",   type = "race", solo = true, timeLimit = 120, start = p(1500), checkpoints = { p(1700), p(1900) }, via = {} },
    { name = "Speed Trap",   type = "speedtrap", solo = false, timeLimit = 600, start = p(2500), trap = p(2800), trapRadius = 10, minRunSpeed = 20, via = {} },
    { name = "Fragile",      type = "fragile",   timeLimit = 300, start = p(3500), checkpoints = { p(3700), p(3900) }, via = {} },
    { name = "Economy",      type = "economy",   timeLimit = 300, start = p(4200), checkpoints = { p(4400), p(4600) }, via = {} },
  }, { finale = { name = "The Test Track", pos = p(6000), radius = 25, timeLimit = 1200, via = {} } })
end

t.test("full session: five events, two workshops, faults, tow, reset fine, finale, results", function()
  local w = World.new({ files = F.files(sessionCourse()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  local all = { A, B, C }
  local function cash(pl) return w:state(pl).cash end
  local function travel(to) w:driveAll({ { A, to, 40 }, { B, to, 35 }, { C, to, 30 } }) end
  local function go()
    w:chat(A, "/tg go")
    w:waitFor(function() return w:state(A).phase == "event" end, 10, "the countdown to finish")
  end
  local function waitPhase(phase, secs)
    w:waitFor(function() return w:state(A).phase == phase end, secs or 30, "phase " .. phase)
  end

  -- dealership ------------------------------------------------------------------
  w:chat(A, "/tg start")
  t.eq(w:state(A).phase, "dealer")
  w:buy(A, "covet", "base_M")      -- $4,500
  w:buy(B, "pessima", "base_M")    -- $5,000
  w:buy(C, "pickup", "d15_M")      -- $7,500
  -- faults are taken by number and drawn at random from the 10 (in list order): pin the draws
  w.rolls = { 1 }; w:chat(B, "/tg fault take")   -- +$2,500: draw 1 = worn tyres (setup fault: respawns the car)
  w.rolls = { 4 }; w:chat(C, "/tg fault take")   -- +$2,500: draw 4 = tired engine (physics fault: vehicle Lua)
  w:step(10)                           -- faults applied, reports back
  t.eq(B.current.vars["$tirepressure_F"], 9, "Bob's tyres let down to 30%")
  t.ok(math.abs(C.current.engine.outputTorqueState - 0.8) < 1e-9, "Carol's engine at 80%")
  t.ok(w:chatHas(C, "Carol takes a car with 1 hidden fault for an extra $2,500."), "the fault stays hidden")
  t.eq(cash(A), 5500); t.eq(cash(B), 7500); t.eq(cash(C), 5000)
  for _, pl in ipairs(all) do w:chat(pl, "/tg ready") end
  t.eq(w:state(A).phase, "travel")

  -- 1: destination race --------------------------------------------------------------
  travel(p(500))
  t.ok(w:chatHas(A, "Alice arrives at Race One (1st) - $500 bonus"))
  t.ok(w:chatHas(A, "Bob arrives at Race One (2nd) - $250 bonus"))
  go()
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 35 }, { C, p(900), 30 } })
  waitPhase("travel")
  t.ok(w:chatHas(A, "1st  Alice"), "Alice wins the race")
  t.ok(w:chatHas(A, "2nd  Bob")); t.ok(w:chatHas(A, "3rd  Carol"))

  -- 2: a race in time trial mode, one at a time in arrival order -------------------------------------
  w:resetCar(B)   -- Bob gets round the reset lock: fined
  t.ok(w:chatHas(A, "Bob pressed the reset button! -$1,000"))
  travel(p(1500))
  go()
  t.ok(w:chatHas(A, "running order: Alice, Bob, Carol"))
  for _, run in ipairs({ { A, 30 }, { B, 40 }, { C, 35 } }) do
    local who = run[1]
    w:waitFor(function() return w:sawMessage(who, who.name .. ": GO!") end, 30, who.name .. "'s GO")
    w:drive(who, p(1900), run[2])
  end
  waitPhase("workshop")
  t.ok(w:chatHas(A, "1st  Bob")); t.ok(w:chatHas(A, "2nd  Carol")); t.ok(w:chatHas(A, "3rd  Alice"))

  -- workshop 1: a paid repair and a fault fix ---------------------------------------------
  w:damage(A, 2000)
  w:step(2.5)                          -- damage report reaches the server
  w:chat(A, "/tg repair")              -- $250 + 2000 x 0.5 = $1,250
  t.ok(w:chatHas(A, "Alice paid $1,250 to have their Ibishu Covet repaired."))
  t.ok(w:chatHas(B, "The mechanics have looked your car over and found: Worn, underinflated tires (/tg fix tires)."), "diagnosed")
  w:chat(B, "/tg fix tires")           -- 1.5 x $2,500 = $3,750
  w:step(10)
  t.eq(B.current.vars["$tirepressure_F"], 30, "Bob's tyres back to normal")
  t.eq(A.current.damage, 0, "Alice's car repaired in game")
  w:chat(A, "/tg next")                -- admin closes the workshop
  t.eq(w:state(A).phase, "travel")

  -- 3: speed trap (Carol is towed to the start) ----------------------------------------------
  w:chat(C, "/tg tow")
  w:step(3)
  t.ok(math.abs(C.current.pos.x - 2500) < 1 and math.abs(C.current.pos.y) < 1, "Carol delivered to the speed trap start")
  t.ok(math.abs(C.current.engine.outputTorqueState - 0.8) < 1e-9, "Carol's engine fault survives the tow's reset")
  w:driveAll({ { A, p(2500), 40 }, { B, p(2500), 35 } })
  t.ok(w:chatHas(A, "Alice arrives at Speed Trap (1st) - $500 bonus"))
  t.ok(w:chatHas(A, "Bob arrives at Speed Trap (2nd) - $250 bonus"))
  go()
  w:driveAll({ { A, p(3000), 45 }, { B, p(3000), 40 }, { C, p(3000), 50 } })   -- one run each
  waitPhase("travel")
  t.ok(w:chatHas(A, "1st  Carol")); t.ok(w:chatHas(A, "2nd  Alice")); t.ok(w:chatHas(A, "3rd  Bob"))

  -- 4: fragile delivery (Alice is quickest but dents her car) ------------------------------
  travel(p(3500))
  go()
  w:driveAll({ { A, p(3700), 40 }, { B, p(3700), 30 }, { C, p(3700), 25 } })
  w:damage(A, 3000)
  w:step(2.5)
  w:driveAll({ { A, p(3900), 40 }, { B, p(3900), 30 }, { C, p(3900), 25 } })
  waitPhase("workshop")
  t.ok(w:chatHas(A, "1st  Bob")); t.ok(w:chatHas(A, "2nd  Carol")); t.ok(w:chatHas(A, "3rd  Alice"))
  t.ok(w:chatHas(A, "3000 damage (+30.0 s)"), "Alice's damage penalty")
  t.ok(w:chatHas(A, "repaired, free of charge"))
  w:step(2)
  t.eq(A.current.damage, 0, "the free repair happened in game")

  -- workshop 2: nothing to do --------------------------------------------------------------
  w:chat(A, "/tg next")

  -- 5: economy run (fuel read from each car's own Lua) --------------------------------------
  travel(p(4200))
  go()
  w:driveAll({ { A, p(4600), 20 }, { B, p(4600), 40 }, { C, p(4600), 30 } })
  waitPhase("finale")
  t.ok(w:chatHas(A, "1st  Alice")); t.ok(w:chatHas(A, "2nd  Carol")); t.ok(w:chatHas(A, "3rd  Bob"))
  t.noLine(A.chat, "fuel reading unavailable")

  -- finale: Carol arrives battered and with her engine fault unfixed ---------------------------
  w:driveAll({ { A, p(5300), 40 }, { B, p(5300), 35 }, { C, p(5300), 30 } })
  w:damage(C, 10000)
  w:step(2.5)
  travel(p(6000))
  waitPhase("results")
  t.ok(w:chatHas(A, "Carol made it to The Test Track! Inspection: damage 10000, 1 unfixed fault (Tired engine (about -20% power)) -> drivability 4.0/10"))
  t.ok(w:chatHas(A, "Alice made it to The Test Track! Inspection: damage 0 -> drivability 10.0/10"))
  t.ok(w:chatHas(A, "Bob loses 2 pts for 1 illegal reset(s)."))
  t.ok(w:chatHas(A, "Carol loses 1 pts for 1 tow(s)/respawn(s)."))

  -- the tally ----------------------------------------------------------------------------------
  -- Alice: 10000 - 4500 car + 5 x 500 arrivals + prizes (6000 + 1500 + 3000 + 1500 + 6000) - 1250 repair = 24750
  --        points 10 + 3 + 6 + 3 + 10 + 10 drivability = 42
  -- Bob:   10000 - 5000 + 2500 fault + 5 x 250 + (3000 + 6000 + 1500 + 6000 + 1500) - 3750 fix - 1000 fine = 22000
  --        points 6 + 10 + 3 + 10 + 3 + 10 - 2 reset penalty = 40
  -- Carol: 10000 - 7500 + 2500 fault + 0 arrivals + (1500 + 3000 + 6000 + 3000 + 3000) - 1000 tow = 20500
  --        (her car was undamaged when towed: 0 repair x 1.25 + $1,000 fee)
  --        points 3 + 6 + 10 + 6 + 6 + (5.0 - 1 unfixed fault) - 1 for the tow = 34
  t.eq(cash(A), 24750, "Alice's cash"); t.eq(cash(B), 22000, "Bob's cash"); t.eq(cash(C), 20500, "Carol's cash")
  t.eq(w:state(A).points, 42, "Alice's points"); t.eq(w:state(B).points, 40, "Bob's points"); t.eq(w:state(C).points, 34, "Carol's points")
  t.ok(w:chatHas(A, "Alice and the Ibishu Covet win!"))

  -- the results window -----------------------------------------------------------------------
  w:step(3)
  local s = w:ui(A).summary
  t.eq(s.winner, "Alice")
  t.eq(#s.events, 5)
  local rows = {}
  for _, r in ipairs(s.rows) do rows[r.name] = r end
  t.eq(rows.Alice.place, 1); t.eq(rows.Bob.place, 2); t.eq(rows.Carol.place, 3)
  t.eq(rows.Alice.repairs, 1250)
  t.eq(rows.Bob.faultFixes, 3750); t.eq(rows.Bob.resets, 1); t.eq(rows.Bob.fines, 1000)
  t.eq(rows.Carol.tows, 1); t.eq(rows.Carol.towCost, 1000); t.eq(rows.Carol.penalty, 1); t.eq(rows.Carol.faultsLeft[1], "Tired engine (about -20% power)")
  t.eq(rows.Carol.places[3], "1st (180 km/h)", "speed trap cell")
  t.match(A.client.im.textOf("Top Gear Challenge"), "WINNER: Alice in the Ibishu Covet %- 42%.0 points")
  w:assertClean()
end)
