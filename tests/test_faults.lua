-- Fault revamp (0.8.8): faults are taken by number ($2,500 each), drawn at random from what the car can
-- take, hidden until a workshop, final; ten faults incl. ignition, cooling, suspension, fuel leak, body.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

-- the draw order is the fault list's order, minus faults already drawn / known not to fit the car
local ORDER = { "tires", "alignment", "bumpers", "engine", "brakes", "ignition", "cooling", "suspension", "fuelleak", "body" }
local function pin(w, ids, exclude)
  local gone, rolls = {}, {}
  for _, x in ipairs(exclude or {}) do gone[x] = true end
  for _, id in ipairs(ids) do
    local i = 0
    for _, f in ipairs(ORDER) do
      if not gone[f] then i = i + 1; if f == id then rolls[#rolls + 1] = i end end
    end
    gone[id] = true
  end
  w.rolls = rolls
end
local function chatText(pl) return table.concat(pl.chat, "\n") end
local function hiddenEverywhere(w, pl, names)
  for _, n in ipairs(names) do
    t.ok(not chatText(pl):find(n, 1, true), n .. " leaked in chat")
    t.ok(not pl.client.im.textOf("Top Gear Challenge"):find(n, 1, true), n .. " leaked in the window")
  end
end

local function start(w, A, model, faults, n)
  w:chat(A, "/tg start")
  w:buy(A, model or "covet", "base_M")
  if faults then pin(w, faults); w:chat(A, "/tg fault take " .. (n or #faults)) end
  w:step(10)   -- applied: setup faults respawn the car, physics faults run in its Lua, the report comes back
end

t.test("faults are taken by number for $2,500 each, before or after buying; the limit is 4; taken is final", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:chat(A, "/tg fault take 2")          -- before buying: the money raises the budget
  t.ok(w:chatHas(B, "Alice takes a car with 2 hidden faults for an extra $5,000."))
  t.eq(w:state(A).cash, 15000)
  w:chat(A, "/tg dealer")
  t.ok(w:chatHas(A, "DEALERSHIP - budget $15,000"))
  pin(w, { "engine", "brakes" })
  w:buy(A, "covet", "base_M")            -- the faults are drawn for this car now
  w:step(10)
  local e = A.current.engine
  t.ok(math.abs(e.outputTorqueState - 0.8) < 1e-9, "engine fault on the car")
  t.eq(A.current.wheels[0].brakeTorque, 1500 * 0.6, "brake fault on the car")
  w:chat(A, "/tg fault take 3")
  t.ok(w:chatHas(A, "That's over the limit - 4 faults per car (you have 2)."))
  w:chat(A, "/tg fault undo engine")
  t.ok(w:chatHas(A, "Taken faults are final"))
  t.eq(w:state(A).cash, 15000 - 4500)
  w:assertClean()
end)

t.test("faults stay hidden until a workshop diagnoses the car, then can be fixed for $3,750", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  cfg.admins = { "Zed" }   -- an ordinary player's view (admins see every fault's name in the fault-test tools)
  local w = World.new({ files = F.files(cfg) })
  local Z, A = w:join("Zed"), w:join("Alice")
  w:chat(Z, "/tg start")
  w:buy(A, "covet", "base_M")
  pin(w, { "brakes" }); w:chat(A, "/tg fault take")
  w:step(10)
  w:step(2.5)
  t.match(A.client.im.textOf("Top Gear Challenge"), "Faults: 1 hidden %- a workshop will diagnose them")
  w:chat(A, "/tg faults")
  t.ok(w:chatHas(A, "You've taken 1 - a workshop will tell you what they are."))
  hiddenEverywhere(w, A, { "Worn brakes", "brakes)" })

  w:chat(A, "/tg ready")   -- (Zed didn't buy a car: closing the dealership makes him a spectator)
  w:chat(Z, "/tg next")
  w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  t.ok(w:chatHas(A, "The mechanics have looked your car over and found: Worn brakes (about -40% braking) (/tg fix brakes)."))
  w:step(2.5)
  t.ok(A.client.im.hasButton("Fix: Worn brakes (about -40% braking) ($3,750)"), "Fix button once diagnosed")
  local before = w:state(A).cash
  w:chat(A, "/tg fix brakes")
  w:step(3)
  t.eq(w:state(A).cash, before - 3750)
  t.eq(A.current.wheels[0].brakeTorque, 1500, "brakes back to normal")
  w:assertClean()
end)

t.test("ignition: misfires raised, and the engine dies now and then on the road (not at the dealership)", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  start(w, A, "covet", { "ignition" })
  local e = A.current.engine
  t.ok(math.abs(e.slowIgnitionErrorChance - 0.11) < 1e-9 and math.abs(e.fastIgnitionErrorChance - 0.06) < 1e-9, "misfire chances raised")
  w:step(300)
  t.eq(A.current.stalls, 0, "no cut-outs at the dealership")
  w:chat(A, "/tg ready")
  w:step(250)                     -- a cut-out comes every 90-240 s
  t.ok(A.current.stalls >= 1, "the engine died on the road")
  t.eq(A.current.ignition, 0, "and stays off until the player restarts it")
  t.ok(w:sawMessage(A, "Your engine just died! Restart it."))
  w:resetCar(A)                   -- a reset gives stock values back... and the fault is put back
  w:step(3)
  t.ok(math.abs(A.current.engine.slowIgnitionErrorChance - 0.11) < 1e-9, "re-applied after a reset")
  w:assertClean()
end)

t.test("cooling: the radiator is damaged, once - and again after a reset repairs it", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  start(w, A, "covet", { "cooling" })
  t.ok(math.abs(A.current.radiatorDamage - 0.05) < 1e-9)
  w:chat(A, "/tg ready")
  w:step(20)
  w:resetCar(A)
  w:step(3)
  t.ok(math.abs(A.current.radiatorDamage - 0.05) < 1e-9, "re-applied once, not stacked")
  w:assertClean()
end)

t.test("suspension: softest springs and dampers; on a car without adjustable suspension, no anti-roll bar", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pickup", "d15_M")
  pin(w, { "suspension" }); w:chat(A, "/tg fault take")
  pin(w, { "suspension" }); w:chat(B, "/tg fault take")
  w:step(10)
  t.eq(A.current.vars["$spring_F"], 20000); t.eq(A.current.vars["$spring_R"], 20000); t.eq(A.current.vars["$damp_bump_F"], 1000)
  t.eq(B.current.parts["/pickup_swaybar_F/"], "", "the pickup's anti-roll bar is off")
  t.eq(B.current.vars["$spring_F"], nil)
  w:assertClean()
end)

t.test("fuel leak: fuel drains on the road, not at the dealership", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  start(w, A, "covet", { "fuelleak" })
  local f0 = A.current.fuel
  w:step(60)
  t.eq(A.current.fuel, f0, "no leak at the dealership")
  w:chat(A, "/tg ready")
  w:step(60)                      -- 0.5 L a minute
  local lost = f0 - A.current.fuel
  t.ok(lost > 0.4 and lost < 0.6, "lost " .. lost .. " L in a minute")
  w:assertClean()
end)

t.test("accident damage: the car starts dented with broken lights; tows don't stack it; the fix isn't billed twice", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  start(w, A, "covet", { "body" })
  t.eq(A.current.damage, 3000)
  t.ok(A.current.broken.headlight_L and A.current.broken.glass_windshield, "lights and glass broken")
  t.ok(not A.current.broken.hood_hinge, "nothing structural")
  w:chat(A, "/tg ready")
  w:chat(A, "/tg tow")            -- a tow repairs the car... and the fault puts its dents back, once
  w:step(5)
  t.eq(A.current.damage, 3000)
  for _, snd in ipairs(A.client.sounds) do
    t.ok(snd.clip ~= "oh-cock-james-may" and snd.clip ~= "clarkson-poop-shot-out", "the dents coming back isn't a crash")
  end
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  local before = w:state(A).cash
  w:chat(A, "/tg fix body")
  w:step(5)
  t.eq(A.current.damage, 0, "the dents go with the fault")
  t.eq(w:state(A).cash, before - 3750, "just the fix - not a repair bill on top")
  w:assertClean()
end)

t.test("a fault the car can't take is quietly swapped for another, and remembered for that car", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:buy(A, "miramar", "base_M")   -- no fuel tank model, no radiator model on this test car
  pin(w, { "fuelleak", "tires" }) -- the first draw can't be applied; the replacement draw is pinned too
  w:chat(A, "/tg fault take")
  w:step(10)
  t.eq(A.current.vars["$tirepressure_F"], 9, "swapped for worn tyres")
  t.eq(w:state(A).cash, 10000 - 3500 + 2500, "nothing handed back")
  t.noLine(A.chat, "can't take")
  w:chat(A, "/tg fault caps")
  t.ok(w:chatHas(A, "miramar/base_M: works tires | can't take fuelleak"))
  t.ok(w:serverConfig().faultCaps["miramar/base_M"].no.fuelleak, "saved to config.json")

  -- the next Miramar never draws the fuel leak: the draw skips it
  w:buy(B, "miramar", "base_M")
  pin(w, { "cooling", "bumpers" }, { "fuelleak" })   -- cooling can't be applied either; bumpers can
  w:chat(B, "/tg fault take")
  w:step(10)
  w:chat(A, "/tg fault caps")
  t.ok(w:chatHas(A, "miramar/base_M: works bumpers, tires | can't take cooling, fuelleak"))
  t.eq(B.current.parts["/bumper_F/"], "", "Bob got the bumpers fault in the end")
  w:assertClean()
end)

t.test("returning or swapping the car at the dealership redraws the faults for the new car", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  start(w, A, "covet", { "engine" })
  w:clientDelete(A, A.current); w:pump(); w:step(1)   -- returned to the dealership
  t.eq(w:state(A).cash, 10000 + 2500, "the car's refunded, the fault money stays")
  pin(w, { "brakes" })
  w:buy(A, "pessima", "base_M")
  w:step(10)
  t.eq(A.current.wheels[0].brakeTorque, 900, "the new car got its own draw")
  t.eq(A.current.engine.outputTorqueState, 1)
  w:assertClean()
end)

t.test("saved configs with the old 5-fault menu get the 10 faults and the single payout; custom severities kept", function()
  local old = { enabled = true, maxPerCar = 3, list = {
    { id = "tires", name = "Worn tyres", payout = 2400, factor = 0.5 },
    { id = "alignment", name = "Alignment", payout = 2100, factor = 1.4 },
    { id = "bumpers", name = "Bumpers", payout = 1500 },
    { id = "engine", name = "Engine", payout = 6000, factor = 0.8, enabled = false },
    { id = "brakes", name = "Brakes", payout = 3600, factor = 0.6 } } }
  local w = World.new({ files = F.files(F.config({}, { faults = old })) })
  local fl = w:serverConfig().faults
  t.eq(#fl.list, 10)
  t.eq(fl.payout, 2500)
  t.eq(fl.maxPerCar, 4, "the old limit of 3 becomes 4")
  local byId = {}
  for _, f in ipairs(fl.list) do byId[f.id] = f end
  t.eq(byId.tires.factor, 0.5, "custom severity kept")
  t.eq(byId.engine.enabled, false, "switched-off fault stays off")
  t.ok(byId.fuelleak and byId.body and byId.ignition, "new faults added")
end)

t.test("up to four faults: four buttons at the dealership, and a car with all four", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:step(2.5)
  for n = 1, 4 do t.ok(A.client.im.hasButton(string.format("Take %d%s (+$%s)", n, n == 1 and " fault" or " faults",
    ({ "2,500", "5,000", "7,500", "10,000" })[n])), "button for " .. n) end
  w:buy(A, "covet", "base_M")
  pin(w, { "engine", "brakes", "cooling", "fuelleak" })
  w:chat(A, "/tg fault take 4")
  w:step(10)
  t.eq(w:state(A).cash, 10000 - 4500 + 10000)
  t.ok(math.abs(A.current.engine.outputTorqueState - 0.8) < 1e-9 and A.current.wheels[0].brakeTorque == 900, "engine + brakes")
  t.ok(math.abs(A.current.radiatorDamage - 0.05) < 1e-9, "cooling")
  w:step(2.5)
  t.ok(A.client.im.textOf("Top Gear Challenge"):find("That's the limit.", 1, true), "no more buttons")
  w:assertClean()
end)

t.test("faults survive every kind of reset (illegal reset, respawn, tow, workshop repair) until fixed", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  pin(w, { "tires", "engine", "cooling", "body" }); w:chat(A, "/tg fault take 4")
  pin(w, { "brakes", "ignition", "suspension", "fuelleak" }); w:chat(B, "/tg fault take 4")
  w:step(10)

  local function stillThere(when, engineFixed)
    local a, b = A.current, B.current
    t.eq(a.vars["$tirepressure_F"], 9, "tyres " .. when)
    if not engineFixed then t.ok(math.abs(a.engine.outputTorqueState - 0.8) < 1e-9, "engine " .. when) end
    t.ok(math.abs(a.radiatorDamage - 0.05) < 1e-9, "cooling " .. when)
    t.ok(a.damage >= 3000 and a.broken.headlight_L, "accident damage " .. when)
    t.eq(b.wheels[0].brakeTorque, 900, "brakes " .. when)
    t.ok(math.abs(b.engine.slowIgnitionErrorChance - 0.11) < 1e-9, "ignition " .. when)
    t.eq(b.vars["$spring_F"], 20000, "suspension " .. when)
  end
  stillThere("when applied")

  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  w:step(20)
  w:resetCar(A); w:resetCar(B); w:step(3)
  stillThere("after an illegal reset")
  w:step(20)
  w:chat(A, "/tg respawn"); w:chat(B, "/tg respawn"); w:step(3)
  stillThere("after a respawn")
  w:step(20)
  w:chat(A, "/tg tow"); w:chat(B, "/tg tow"); w:step(5)
  stillThere("after a tow")
  local f0 = B.current.fuel
  w:step(30)
  t.ok(B.current.fuel < f0, "the fuel leak keeps leaking after all that")

  -- (both were towed to Race One's start) race, then the workshop
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 30 } })
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:chat(A, "/tg repair"); w:chat(B, "/tg repair"); w:step(5)   -- repairs the crash damage, not the faults
  stillThere("after a workshop repair")
  w:chat(A, "/tg fix engine"); w:step(5)
  t.ok(math.abs(A.current.engine.outputTorqueState - 1) < 1e-9, "the fixed fault is gone")
  w:resetCar(A); w:step(3)
  stillThere("after a reset, with only the engine fixed", true)
  t.ok(math.abs(A.current.engine.outputTorqueState - 1) < 1e-9, "and it stays fixed")
  w:assertClean()
end)

t.test("admin fault test: a button per fault, and the timed faults act outside a challenge too", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg menu"); w:step(2.5)
  for _, name in ipairs({ "Worn, underinflated tires", "Knocked-out wheel alignment", "Missing bumpers", "Tired engine (about -20% power)",
      "Worn brakes (about -40% braking)", "Ignition problems (misfires, cuts out)", "Cooling problems (leaking radiator)",
      "Worn-out suspension (soft and bouncy)", "Fuel leak", "Accident damage (dents, broken lights)" }) do
    t.ok(A.client.im.hasButton("Test: " .. name), "Test button for " .. name)
  end
  -- no challenge running: an admin tests on any car
  w:clientSpawn(A, "covet", { config = "vehicles/covet/base_M.pc" }); w:pump()
  A.client.im.click("Test: Fuel leak##ft1_fuelleak")   -- each Test button tries just that one fault
  w:step(3)
  t.ok(w:chatHas(A, "Fault test - fuelleak: ok"))
  local f0 = A.current.fuel
  w:step(30)
  t.ok(A.current.fuel < f0, "the test leak leaks")

  A.client.im.click("Test: Ignition problems (misfires, cuts out)##ft1_ignition")
  w:step(3)
  t.ok(w:chatHas(A, "Fault test - fuelleak: removed"), "the previous test fault comes off")
  t.ok(w:chatHas(A, "Fault test - ignition: ok"))
  w:step(32)
  t.ok(A.current.stalls >= 1, "the test ignition fault cuts out within 30 s")
  w:assertClean()
end)
