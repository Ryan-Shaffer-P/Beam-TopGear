-- Fault revamp (0.8.8): faults are taken by number ($2,500 each), drawn at random from what the car can
-- take, hidden until a workshop, final; ten faults incl. ignition, cooling, suspension, fuel leak, body.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p
local WIN = "Top Gear Challenge"

-- the draw order is the fault list's order, minus faults already drawn / known not to fit the car
local ORDER = { "tires", "alignment", "bumpers", "engine", "brakes", "ignition", "cooling", "suspension", "fuelleak", "body",
                "starter", "clutch", "synchros", "turbo", "brakefade", "abs", "oilleak", "idle", "gearbox" }
-- off by default since 0.9.12 (the car condition's mileage wear does the same); allFaults() switches them back on
local OFF = { clutch = true, idle = true, gearbox = true }
local function allFaults(cfg)
  local list = {}
  for _, f in ipairs(World.new():serverConfig().faults.list) do f.enabled = nil; list[#list + 1] = f end
  cfg.faults = { list = list }
  cfg.migrations = { mileageOverlap = true }
  return cfg
end
-- pin the next random draws to these faults. all = the world has every fault on (allFaults); otherwise the ones
-- that are off by default aren't in the draw. (The oil leak is only in the draw for a Beater or worse.)
local function pin(w, ids, exclude, all)
  local gone, rolls = {}, {}
  if not all then for id in pairs(OFF) do gone[id] = true end end
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
  if faults then w:chat(A, "/tg fault take " .. (n or #faults)) end   -- the condition is chosen before buying...
  if faults then pin(w, faults) end
  w:buy(A, model or "covet", "base_M")                               -- ...and its problems drawn when the car is bought
  w:step(10)   -- applied: setup faults respawn the car, physics faults run in its Lua, the report comes back
end

t.test("car condition: chosen before buying, it sets every car's price (career's formula); locked once bought", function()
  local w = World.new({ files = F.files(F.twoRaces()) })   -- (the test dealer list: the Covet is $4,500 new)
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:chat(A, "/tg condition needs work")
  t.ok(w:chatHas(A, "Car condition: Needs work (100,000 km) - every car is 20% off."))
  t.eq(w:state(A).cash, 10000, "no cash bonus: the prices drop instead")
  w:chat(A, "/tg dealer covet")
  t.ok(w:chatHas(A, "  $3,600  Ibishu Covet"), "$4,500 x 0.8")
  w:chat(A, "/tg condition used")          -- changed her mind: free before buying
  w:chat(A, "/tg dealer covet")
  t.ok(w:chatHas(A, "  $4,100  Ibishu Covet"), "$4,500 x 0.9 = $4,050, to the nearest $100")
  w:chat(A, "/tg condition new")
  t.ok(w:chatHas(A, "Car condition: New - full price."))
  w:chat(A, "/tg fault take 2")            -- the old command still works: two steps worse
  t.ok(w:chatHas(A, "Car condition: Needs work"))
  pin(w, { "engine", "brakes" })
  w:buy(A, "covet", "base_M")            -- bought at the Needs work price; the problems are drawn now
  w:step(10)
  t.ok(w:chatHas(B, "Alice bought an Ibishu Covet for $3,600 - a Needs work, $900 off ($6,400 left)."))
  t.eq(w:state(A).cash, 10000 - 3600)
  t.ok(math.abs(A.current.engine.outputTorqueState - 0.8) < 1e-9, "engine problem on the car")
  t.eq(A.current.wheels[0].brakeTorque, 1500 * 0.6, "brake problem on the car")
  w:chat(A, "/tg condition death trap")    -- locked in with the car
  t.ok(w:chatHas(A, "You've bought your Ibishu Covet as Needs work - that's locked in (return it to choose again)."))
  t.eq(w:state(A).cash, 10000 - 3600)
  w:assertClean()
end)

t.test("faults stay hidden until a workshop diagnoses the car, then can be fixed (5% of the new price, at least $500)", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  cfg.admins = { "Zed" }   -- an ordinary player's view (admins see every fault's name in the fault-test tools)
  local w = World.new({ files = F.files(cfg) })
  local Z, A = w:join("Zed"), w:join("Alice")
  w:chat(Z, "/tg start")
  w:chat(A, "/tg fault take"); pin(w, { "brakes" })
  w:buy(A, "covet", "base_M")
  w:step(10)
  w:step(2.5)
  t.match(A.client.im.textOf("Top Gear Challenge"), "Bought as Used: 1 hidden problem %- a workshop will find it")
  w:chat(A, "/tg faults")
  t.ok(w:chatHas(A, "Your car: Used - a workshop will find its problems"))
  hiddenEverywhere(w, A, { "Worn brakes", "brakes)" })

  w:chat(A, "/tg ready")   -- (Zed didn't buy a car: closing the dealership makes him a spectator)
  w:chat(Z, "/tg next")
  w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  t.ok(w:chatHas(A, "The mechanics have looked your car over and found: Worn brakes (about -40% braking) (/tg fix brakes)."))
  w:step(2.5)
  t.ok(A.client.im.hasButton("Fix this problem: Worn brakes (about -40% braking) ($500)"), "Fix button once diagnosed")
  local before = w:state(A).cash
  w:chat(A, "/tg fix brakes")
  w:step(3)
  t.eq(w:state(A).cash, before - 500, "5% of the Covet's $4,500 is $225: the $500 minimum")
  t.eq(A.current.wheels[0].brakeTorque, 1500, "brakes back to normal")
  w:assertClean()
end)

t.test("ignition: misfires raised, and the engine dies now and then on the road (not at the dealership)", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  start(w, A, "covet", { "ignition" })
  local e = A.current.engine
  -- (the mileage wear of a Used car sets the base misfire chances to the game's "new" value, 0, first)
  t.ok(math.abs(e.slowIgnitionErrorChance - 0.05) < 1e-9 and math.abs(e.fastIgnitionErrorChance - 0.025) < 1e-9, "misfire chances raised")
  w:step(300)
  t.eq(A.current.stalls, 0, "no cut-outs at the dealership")
  w:chat(A, "/tg ready")
  w:step(490)                     -- a cut-out comes every 180-480 s (halved from 90-240 s after Ryan's drive)
  t.ok(A.current.stalls >= 1, "the engine died on the road")
  t.eq(A.current.ignition, 0, "and stays off until the player restarts it")
  t.ok(w:sawMessage(A, "Your engine just died! Restart it."))
  w:resetCar(A)                   -- a reset gives stock values back... and the fault is put back
  w:step(3)
  t.ok(math.abs(A.current.engine.slowIgnitionErrorChance - 0.05) < 1e-9, "re-applied after a reset")
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
  w:chat(A, "/tg fault take"); w:chat(B, "/tg fault take")
  pin(w, { "suspension" }); w:buy(A, "covet", "base_M")
  pin(w, { "suspension" }); w:buy(B, "pickup", "d15_M")
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
  w:step(60)                      -- 1 L a minute (doubled after Ryan's drive)
  local lost = f0 - A.current.fuel
  t.ok(lost > 0.9 and lost < 1.1, "lost " .. lost .. " L in a minute")
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
  t.eq(w:state(A).cash, before - 500, "just the fix - not a repair bill on top")
  w:assertClean()
end)

t.test("a fault the car can't take is quietly swapped for another, and remembered for that car", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:chat(A, "/tg fault take")
  pin(w, { "fuelleak", "tires" }) -- the first draw can't be applied; the replacement draw is pinned too
  w:buy(A, "miramar", "base_M")   -- no fuel tank model, no radiator model on this test car
  w:step(10)
  t.eq(A.current.vars["$tirepressure_F"], 9, "swapped for worn tyres")
  t.eq(w:state(A).cash, 10000 - 3200, "a Used Miramar ($3,500 x 0.9 = $3,150 -> $3,200); no money moves on a swap")
  t.noLine(A.chat, "can't take")
  w:chat(A, "/tg fault caps")
  t.ok(w:chatHas(A, "miramar/base_M: works tires | can't take fuelleak"))
  t.ok(w:serverConfig().faultCaps["miramar/base_M"].no.fuelleak, "saved to config.json")

  -- the next Miramar never draws the fuel leak: the draw skips it
  w:chat(B, "/tg fault take")
  pin(w, { "cooling", "bumpers" }, { "fuelleak" })   -- cooling can't be applied either; bumpers can
  w:buy(B, "miramar", "base_M")
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
  t.eq(w:state(A).cash, 10000, "the car's refunded; the condition stays chosen (Used) and can be changed again")
  pin(w, { "brakes" })
  w:buy(A, "pessima", "base_M")
  w:step(10)
  t.eq(A.current.wheels[0].brakeTorque, 900, "the new car got its own draw")
  t.eq(A.current.engine.outputTorqueState, 1)
  w:assertClean()
end)

t.test("saved configs with the old 5-fault menu get every fault; custom severities kept", function()
  local old = { enabled = true, maxPerCar = 3, list = {
    { id = "tires", name = "Worn tyres", payout = 2400, factor = 0.5 },
    { id = "alignment", name = "Alignment", payout = 2100, factor = 1.4 },
    { id = "bumpers", name = "Bumpers", payout = 1500 },
    { id = "engine", name = "Engine", payout = 6000, factor = 0.8, enabled = false },
    { id = "brakes", name = "Brakes", payout = 3600, factor = 0.6 } } }
  local w = World.new({ files = F.files(F.config({}, { faults = old })) })
  local fl = w:serverConfig().faults
  t.eq(#fl.list, 19)
  t.eq(fl.maxPerCar, 4, "the old limit of 3 becomes 4")
  local byId = {}
  for _, f in ipairs(fl.list) do byId[f.id] = f end
  t.eq(byId.tires.factor, 0.5, "custom severity kept")
  t.eq(byId.engine.enabled, false, "switched-off fault stays off")
  t.ok(byId.fuelleak and byId.body and byId.ignition, "new faults added")
end)

t.test("the Dealership tab: a Car Condition slider (New .. Death Trap, no numbers) sets every price as it moves", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:step(2.5)
  local function slider()
    for _, it in ipairs(A.client.im.items(WIN)) do if it.kind == "slider" then return it end end
  end
  local s = A.client.im.textOf(WIN)
  t.match(s, "CAR CONDITION\n<New>")
  t.match(s, "A more worn car is cheaper on the market: Used 10%% off, Needs work 20%% off, Beater 45%% off, Death Trap 70%% off%.")
  t.match(s, "Choose before you buy %- it's locked in with the car%.")
  t.match(s, "%$4,500  Ibishu Covet")
  t.ok(not s:find("Problem cars", 1, true) and not A.client.im.hasButton("Take 1 fault (+$2,500)"), "no dropdown, no Take buttons")
  t.eq(slider().min, 0); t.eq(slider().max, 4)
  A.client.im.setInt("##condition", 3)
  w:step(2.5)
  t.eq(w:state(A).cash, 10000, "the cash doesn't move...")
  s = A.client.im.textOf(WIN)
  t.match(s, "%$2,500  Ibishu Covet", "...the prices do: $4,500 x 0.55")
  t.match(s, "<Beater>")
  t.match(s, "Beater %(200,000 km%): every car below is 45%% off%.")
  t.ok(not slider().text:find("%d"), "no number on the slider: " .. slider().text)
  A.client.im.setInt("##condition", 1)
  w:step(2.5)
  t.match(A.client.im.textOf(WIN), "<Used>")
  t.match(A.client.im.textOf(WIN), "%$4,100  Ibishu Covet")
  pin(w, { "engine" })
  w:buy(A, "covet", "base_M")
  w:step(2.5)
  t.eq(slider(), nil, "bought: no slider - it's locked in")
  t.match(A.client.im.textOf(WIN), "Bought as Used %(60,000 km%)%.")
  t.match(A.client.im.textOf(WIN), "That's locked in %- return the car to choose again%.")
  t.match(A.client.im.textOf(WIN), "at least %$500%) %- %$500 for yours")
  t.eq(w:state(A).cash, 10000 - 4100)
  w:assertClean()
end)

t.test("faults survive every kind of reset (illegal reset, respawn, tow, workshop repair) until fixed", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:chat(A, "/tg fault take 4"); w:chat(B, "/tg fault take 4")
  pin(w, { "tires", "engine", "cooling", "body" }); w:buy(A, "covet", "base_M")
  pin(w, { "brakes", "ignition", "suspension", "fuelleak" }); w:buy(B, "pessima", "base_M")
  w:step(10)

  local function stillThere(when, engineFixed)
    local a, b = A.current, B.current
    t.eq(a.vars["$tirepressure_F"], 9, "tyres " .. when)
    if not engineFixed then t.ok(math.abs(a.engine.outputTorqueState - 0.8) < 1e-9, "engine " .. when) end
    t.ok(math.abs(a.radiatorDamage - 0.05) < 1e-9, "cooling " .. when)
    t.ok(a.damage >= 3000 and a.broken.headlight_L, "accident damage " .. when)
    t.eq(b.wheels[0].brakeTorque, 900, "brakes " .. when)
    t.ok(math.abs(b.engine.slowIgnitionErrorChance - 0.05) < 1e-9, "ignition " .. when)   -- (0 base after the mileage + 0.05)
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
      "Worn-out suspension (soft and bouncy)", "Fuel leak", "Accident damage (dents, broken lights)",
      "Weak starter (slow to start)", "Slipping clutch", "Worn gearbox synchros (gears grind)", "Damaged turbo (low boost)",
      "Glazed brake pads (squeal, fade when hot)", "ABS failure (wheels lock)", "Oil leak (runs hot - might blow the engine)",
      "Rough idle (hunts and stalls)", "Worn gearbox (power lost to friction)" }) do
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

-- the seven faults added in the second round -----------------------------------------------------
t.test("starter, clutch, synchros, ABS on a manual car; turbo on a turbo car; ones a car can't take get swapped", function()
  local w = World.new({ files = F.files(allFaults(F.twoRaces())) })   -- (the clutch is off by default)
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:chat(A, "/tg fault take 4"); w:chat(B, "/tg fault take 3")
  pin(w, { "starter", "clutch", "synchros", "abs" }, nil, true)
  w:buy(A, "covet", "base_M")        -- manual, no turbo
  -- Bob draws a clutch and synchros (no manual gearbox: swapped) and a turbo; the swaps are pinned to brakefade/oilleak
  pin(w, { "clutch", "synchros", "turbo", "brakefade", "oilleak" }, nil, true)
  w.chances = { 0.9 }                -- (oil leak: this engine isn't doomed)
  w:buy(B, "pessima", "base_M")      -- automatic, turbo
  w:step(15)
  local a, b = A.current, B.current
  t.ok(math.abs(a.engine.starterTorque - 60) < 1e-9, "weak starter: x0.6 (it still starts)")
  t.eq(a.devices.clutch.clutchPermanentlyDamaged, true, "slipping clutch")
  t.eq(a.devices.gearbox.synchroWear[2], 0.8, "worn synchros")
  t.eq(a.abs, "off", "no ABS")
  t.ok(math.abs(b.turboDamage - 0.02) < 1e-9, "damaged turbo")
  t.eq(b.wheels[0].padGlazingFactor, 1, "glazed pads")
  t.ok(math.abs(b.engine.damageFrictionCoef - 1.5) < 1e-9, "oil leak: engine friction up")
  w:chat(A, "/tg fault caps")
  t.ok(w:chatHas(A, "pessima/base_M: works brakefade, oilleak, turbo | can't take clutch, synchros"))

  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  w:step(20)
  w:resetCar(A); w:resetCar(B); w:step(3)   -- a reset repairs all of that... and the faults go back on
  t.eq(a.devices.clutch.clutchPermanentlyDamaged, true); t.eq(a.devices.gearbox.synchroWear[2], 0.8); t.eq(a.abs, "off")
  t.ok(math.abs(b.turboDamage - 0.02) < 1e-9 and math.abs(b.engine.damageFrictionCoef - 1.5) < 1e-9, "turbo + oil, not stacked")
  t.eq(b.wheels[0].padGlazingFactor, 1)
  b.wheels[0].padGlazingFactor = 0.3        -- the game lets the glazing recover a little...
  w:step(11)
  t.eq(b.wheels[0].padGlazingFactor, 1, "...and the fault tops it back up")
  w:assertClean()
end)

local function oilCar(w, A, chance)
  w:chat(A, "/tg start")
  w:chat(A, "/tg condition beater")    -- (an oil leak needs a Beater or worse)
  pin(w, { "oilleak", "brakes", "starter" }); w.chances = { chance }
  w:buy(A, "covet", "base_M")
  w:step(10)
  w:chat(A, "/tg ready")
end
local function hardDriving(w, A, seconds, speed)
  A.current.vel = { x = speed or 25, y = 0, z = 0 }   -- (the server only reads speed here; the car stays put)
  w:step(seconds)
  A.current.vel = { x = 0, y = 0, z = 0 }
end

t.test("oil leak, doomed (the 20%): the engine lets go after hard driving, once - a tow fixes it for good", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  oilCar(w, A, 0.1)                   -- 0.1 < 0.2: doomed
  local B = w:join("Bob")             -- (joins after the start: a spectator)
  hardDriving(w, A, 20, 10)           -- gentle driving doesn't count
  hardDriving(w, A, 300, 10)
  t.eq(A.current.engine.isBroken, false, "not at 36 km/h")
  hardDriving(w, A, 610)              -- 60-600 s of hard driving
  t.eq(A.current.engine.isBroken, true, "the engine has seized")
  t.ok(w:sawMessage(A, "BANG! Your engine has let go. That's a tow."))
  t.ok(w:chatHas(B, "Alice's engine has let go! That's a tow."))
  w:chat(A, "/tg tow"); w:step(5)
  t.eq(A.current.engine.isBroken, false, "the tow fixes the engine")
  t.ok(math.abs(A.current.engine.damageFrictionCoef - 1.5) < 1e-9, "the leak is still there")
  hardDriving(w, A, 700)
  t.eq(A.current.engine.isBroken, false, "and it can't blow again")
  w:assertClean()
end)

t.test("oil leak, not doomed (the 80%): runs hot, never blows", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  oilCar(w, A, 0.5)                   -- 0.5 >= 0.2: just a leak
  hardDriving(w, A, 700)
  t.eq(A.current.engine.isBroken, false)
  t.ok(math.abs(A.current.engine.damageFrictionCoef - 1.5) < 1e-9)
  w:assertClean()
end)

t.test("oil leak test button: that engine blows within 40 s of hard driving, so admins can see it", function()
  local w = World.new()
  local A = w:join("Alice")
  w:clientSpawn(A, "covet", { config = "vehicles/covet/base_M.pc" }); w:pump()
  w:chat(A, "/tg fault test oilleak")
  w:step(3)
  t.ok(w:chatHas(A, "Fault test - oilleak: ok"))
  hardDriving(w, A, 42)
  t.eq(A.current.engine.isBroken, true)
  w:assertClean()
end)

t.test("saved configs with the 10 faults get the 9 new ones added", function()
  local ten = {}
  for _, id in ipairs({ "tires", "alignment", "bumpers", "engine", "brakes", "ignition", "cooling", "suspension", "fuelleak", "body" }) do
    ten[#ten + 1] = { id = id, name = id, factor = 0.5 }
  end
  local w = World.new({ files = F.files(F.config({}, { faults = { list = ten }, migrations = { faults10 = true, tires30 = true } })) })
  local fl = w:serverConfig().faults.list
  t.eq(#fl, 19)
  t.eq(fl[1].factor, 0.5, "existing faults untouched")
  t.eq(fl[17].id, "oilleak"); t.eq(fl[17].blowChance, 0.2)
end)

t.test("rough idle and a worn gearbox (manual or automatic), re-applied after a reset without stacking", function()
  local w = World.new({ files = F.files(allFaults(F.twoRaces())) })   -- (both off by default: an admin can switch them on)
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:chat(A, "/tg condition beater"); w:chat(B, "/tg fault take")
  -- Alice's third draw is a turbo her Covet can't take: it's swapped for brakes and the faults are sent again (no
  -- reset) - nothing may multiply twice
  pin(w, { "idle", "gearbox", "turbo", "brakes" }, nil, true); w:buy(A, "covet", "base_M")   -- manual
  w:step(10)   -- (the swap's draw uses the last pinned roll: let it happen before Bob's draw is pinned)
  pin(w, { "gearbox" }, { "oilleak" }, true); w:buy(B, "pessima", "base_M")                  -- automatic (Used: no oil leak)
  w:step(10)
  t.eq(A.current.wheels[0].brakeTorque, 900, "the swapped-in brakes problem arrived")
  t.eq(A.current.engine.damageIdleAVReadErrorRangeCoef, 15, "idle not stacked")
  t.eq(A.current.devices.gearbox.damageFrictionCoef, 3, "gearbox not stacked")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  w:step(20)
  w:resetCar(A); w:step(3)
  t.eq(A.current.engine.damageIdleAVReadErrorRangeCoef, 15, "after a reset")
  t.eq(A.current.devices.gearbox.damageFrictionCoef, 3, "after a reset, not stacked")
  w:assertClean()
end)

t.test("parts fitted right after a fault is applied are billed (no free-upgrade window)", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg fault take")
  pin(w, { "tires" }); w:buy(A, "covet", "base_M")   -- a setup fault: the car respawns
  w:step(10)
  local cash0 = w:state(A).cash
  local parts = {}
  for k, v in pairs(A.current.parts) do parts[k] = v end
  parts["/covet_engine/"] = "covet_engine_turbo"      -- $1,200 more than stock, + $300 labour
  A.client.sb.env.core_vehicle_partmgmt.setPartsConfig(parts, true); w:pump(); w:step(4)
  t.eq(A.current.parts["/covet_engine/"], "covet_engine_turbo")
  t.eq(cash0 - w:state(A).cash, 1500, "charged, even inside the old 15 s window")
  w:assertClean()
end)

t.test("the mod's own part changes (a fault taking a part off, a fix putting it back) are never billed or refunded", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg fault take")
  pin(w, { "suspension" }); w:buy(A, "pickup", "d15_M")   -- no adjustable suspension: the fault removes the anti-roll bar
  w:step(10)
  t.eq(A.current.parts["/pickup_swaybar_F/"], "", "the anti-roll bar is off")
  t.eq(w:state(A).cash, 10000 - 6800, "a Used pickup ($7,500 x 0.9 = $6,750 -> $6,800); no refund for the part the fault took off")
  w:chat(A, "/tg ready")
  w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  local before = w:state(A).cash
  w:chat(A, "/tg fix suspension")
  w:step(10)
  t.eq(A.current.parts["/pickup_swaybar_F/"], "pickup_swaybar_F", "back on")
  t.eq(w:state(A).cash, before - 500, "just the fix - no part or labour charge for putting it back")
  w:assertClean()
end)

-- Mileage wear (0.9.12): BeamNG's part conditions, as career's used-car dealership sets them, by car condition
t.test("mileage wear: each condition sets the car's odometer through the game's part conditions (paint left alone)", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  w:chat(A, "/tg start")
  w:chat(B, "/tg condition used"); w:chat(C, "/tg condition death trap")
  w:buy(A, "covet", "base_M"); w:buy(B, "covet", "base_M"); w:buy(C, "pessima", "base_M")
  w:step(10)
  t.eq(A.current.partConditionCalls, 0, "a New car is left alone")
  t.eq(B.current.odometer, 60000 * 1000); t.eq(C.current.odometer, 300000 * 1000)
  t.ok(not B.current.paintLocked and not C.current.paintLocked, "no paint aging: it would lock the mesh colours (no repaints)")
  w:chat(C, "/tg diag")
  w:step(1)
  t.ok(w:chatHas(C, "Car wear (mileage): 300,000 km - ok"))
  w:assertClean()
end)

t.test("mileage wear: kept through resets, back after a respawn, and fixing a problem doesn't make the car newer", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  start(w, A, "covet", { "brakes", "ignition" })   -- Needs work: 100,000 km
  t.eq(A.current.odometer, 100000 * 1000)
  t.ok(math.abs(A.current.engine.slowIgnitionErrorChance - 0.05) < 1e-9, "the problems go on after the mileage")
  w:resetCar(A); w:step(3)
  t.eq(A.current.odometer, 100000 * 1000, "a reset keeps it (the game's own snapshot)")
  t.eq(A.current.partConditionCalls, 1, "not set again after a reset")
  t.ok(math.abs(A.current.engine.slowIgnitionErrorChance - 0.05) < 1e-9, "the ignition problem back after the reset")
  w:chat(A, "/tg ready")
  w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:chat(A, "/tg fix brakes")
  w:step(3)
  t.eq(A.current.odometer, 100000 * 1000, "still a Needs work car's mileage after a fix")
  w:chat(A, "/tg respawn")   -- a fresh car: the mileage goes on again
  w:step(10)
  t.eq(A.current.odometer, 100000 * 1000, "re-applied after a respawn")
  w:assertClean()
end)

-- 0.9.12: the problems mileage wear already covers are off; the oil leak only for a Beater or worse
local function drawn(w, name)   -- the problems the server gave a player's car (from the saved challenge)
  local json = require("json")
  w:step(6)
  return json.decode(w.files["Resources/Server/TopGear/session.json"]).game.players[name].faults
end
local function has(list, id) for _, x in ipairs(list) do if x == id then return true end end return false end

t.test("rough idle, worn gearbox and slipping clutch are out of the draw; the oil leak only for Beaters and Death Traps", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  -- always draw the LAST candidate: the oil leak is last in the list whenever it's in the draw
  w:chat(A, "/tg condition needs work"); w.rolls = { "last", "last" }; w:buy(A, "covet", "base_M")
  local a = drawn(w, "Alice")
  t.ok(has(a, "abs") and has(a, "brakefade") and not has(a, "oilleak"), "no oil leak for a Needs work car: " .. table.concat(a, ","))
  w:chat(B, "/tg condition beater"); w.rolls = { "last", 1, 1 }; w:buy(B, "covet", "base_M")
  local b = drawn(w, "Bob")
  t.ok(has(b, "oilleak"), "a Beater can have an oil leak: " .. table.concat(b, ","))
  for _, id in ipairs({ "idle", "gearbox", "clutch" }) do
    t.ok(not has(a, id) and not has(b, id), id .. " is off")
  end
  w:assertClean()
end)

t.test("saved configs: the three overlapping problems switched off and the oil leak limited, once", function()
  local list = World.new():serverConfig().faults.list
  for _, f in ipairs(list) do f.enabled = nil; f.minCondition = nil end   -- a config saved before 0.9.12
  local cfg = F.twoRaces(); cfg.faults = { list = list }
  local sc = World.new({ files = F.files(cfg) }):serverConfig()
  for _, f in ipairs(sc.faults.list) do
    if f.id == "idle" or f.id == "gearbox" or f.id == "clutch" then t.eq(f.enabled, false, f.id) end
    if f.id == "oilleak" then t.eq(f.minCondition, 3) end
    if f.id == "brakes" then t.eq(f.enabled, nil, "the others untouched") end
  end
  local again = allFaults(F.twoRaces())   -- an admin switched them back on after the update: left on
  for _, f in ipairs(World.new({ files = F.files(again) }):serverConfig().faults.list) do
    if f.id == "idle" then t.eq(f.enabled, nil, "an admin's choice is kept") end
  end
end)

-- 0.9.12: a replaced part takes its problems with it - and a part that had problems is scrap (no trade-in)
local function toWorkshop(w, A)
  w:chat(A, "/tg ready")
  w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:step(2.5)
end
local function fit(w, A, key, part) A.client.im.click("Fit##fit_" .. key .. "_" .. part); w:step(5) end

t.test("a new engine sorts the engine's problems; the old one is scrap, so the new one costs its full price", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition beater")
  w.rolls = { "last", 6, 5 }; w.chances = { 0.9 }   -- oil leak (last when it's in the draw), ignition, worn brakes
  w:buy(A, "covet", "base_M"); w:step(10)
  toWorkshop(w, A)
  local e = A.current.engine
  t.ok(math.abs(e.damageFrictionCoef - 1.5) < 1e-9 and math.abs(e.slowIgnitionErrorChance - 0.05) < 1e-9, "oil leak + misfires")
  local before = w:state(A).cash
  fit(w, A, "/covet_engine/", "covet_engine_turbo")   -- stock $2,000 -> turbo $3,200
  t.ok(w:chatHas(A, "The new part sorted: Ignition problems (misfires, cuts out), Oil leak (runs hot - might blow the engine). The old one was scrap - no trade-in."))
  t.eq(before - w:state(A).cash, 3200 + 300, "the turbo engine's full $3,200 (not the $1,200 difference) + labour")
  w:step(10)
  e = A.current.engine
  t.ok(math.abs(e.damageFrictionCoef - 1) < 1e-9, "no oil leak")
  t.ok(math.abs(e.slowIgnitionErrorChance) < 1e-9, "no misfires")
  t.eq(A.current.wheels[0].brakeTorque, 900, "the brakes weren't part of it: still worn")
  t.eq(A.current.partOdometer.covet_engine_turbo, 0, "the new engine starts at 0 km...")
  t.eq(A.current.odometer, 200000 * 1000, "...the rest of the car keeps a Beater's mileage")
  w:chat(A, "/tg diag"); w:step(1)
  t.ok(w:chatHas(A, "Car wear (mileage): 200,000 km - ok, 1 new part(s) at 0 km"))
  t.ok(not A.current.paintLocked, "a new part doesn't lock the paint either")
  w:resetCar(A); w:step(3)
  t.ok(math.abs(A.current.engine.damageFrictionCoef - 1) < 1e-9, "the sorted problems don't come back after a reset")
  t.eq(A.current.wheels[0].brakeTorque, 900)
  w:assertClean()
end)

t.test("an upgrade to a part with no problems is billed as before (the difference), and the new part is still new", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition used")
  w.rolls = { 5 }; w:buy(A, "covet", "base_M"); w:step(10)   -- worn brakes (not an engine problem)
  toWorkshop(w, A)
  local before = w:state(A).cash
  fit(w, A, "/covet_engine/", "covet_engine_turbo")
  t.eq(before - w:state(A).cash, 1200 + 300, "the $1,200 difference + labour: a healthy engine is a trade-in")
  t.noLine(A.chat, "The new part sorted")
  t.eq(A.current.wheels[0].brakeTorque, 900, "the brakes problem stays")
  t.eq(A.current.partOdometer.covet_engine_turbo, 0, "a part bought new starts at 0 km")
  w:assertClean()
end)

t.test("new coilovers sort worn-out suspension (the same rule for every part system)", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition used")
  w.rolls = { 8 }; w:buy(A, "covet", "base_M"); w:step(10)   -- worn-out suspension
  t.eq(A.current.vars["$spring_F"], 20000, "softest springs")
  toWorkshop(w, A)
  local before = w:state(A).cash
  fit(w, A, "/covet_coilover_F/", "covet_coilover_F_sport")   -- $400 -> $1,800
  w:step(10)
  t.ok(w:chatHas(A, "The new part sorted: Worn-out suspension (soft and bouncy)."))
  t.eq(before - w:state(A).cash, 1800 + 300, "full price for the coilovers: the worn ones are scrap")
  t.eq(A.current.vars["$spring_F"], 40000, "springs back to normal")
  w:assertClean()
end)

t.test("Ryan's fault tuning: saved configs move to the new values once (custom values kept)", function()
  local list = World.new():serverConfig().faults.list
  for _, f in ipairs(list) do
    if f.id == "ignition" then f.factor, f.cutoutMin, f.cutoutMax = 0.1, 90, 240 end
    if f.id == "starter" then f.factor = 0.35 end
    if f.id == "fuelleak" then f.factor = 0.7 end   -- an admin's own value: kept
    if f.id == "brakefade" then f.refresh = nil end
  end
  local cfg = F.twoRaces(); cfg.faults = { list = list }; cfg.migrations = { mileageOverlap = true, conditionPricing = true }
  local by = {}
  for _, f in ipairs(World.new({ files = F.files(cfg) }):serverConfig().faults.list) do by[f.id] = f end
  t.eq(by.ignition.factor, 0.05); t.eq(by.ignition.cutoutMin, 180); t.eq(by.ignition.cutoutMax, 480)
  t.eq(by.starter.factor, 0.6)
  t.eq(by.fuelleak.factor, 0.7, "a custom value isn't touched")
  t.eq(by.brakefade.refresh, 0.5)
end)

t.test("glazed pads stay glazed through a hard stop (the game scrubs glazing off as you brake)", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  start(w, A, "covet", { "brakefade" })
  local wh = A.current.wheels[0]
  t.eq(wh.padGlazingFactor, 1)
  for _ = 1, 6 do wh.padGlazingFactor = math.max(0, wh.padGlazingFactor - 0.4); w:step(0.5) end   -- 3 s of hard braking
  t.ok(wh.padGlazingFactor >= 0.6, "topped up every 0.5 s: " .. wh.padGlazingFactor)
  w:assertClean()
end)
