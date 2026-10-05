-- Fault revamp (0.8.8): faults are taken by number ($2,500 each), drawn at random from what the car can
-- take, hidden until a workshop, final; ten faults incl. ignition, cooling, suspension, fuel leak, body.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p
local WIN = "Top Gear Challenge"

-- the draw order is the fault list's order, minus faults already drawn / known not to fit the car
local ORDER = { "tires", "alignment", "engine", "brakes", "ignition", "cooling", "suspension", "fuelleak", "body",
                "clutch", "synchros", "turbo", "brakefade", "abs", "oilleak", "idle", "gearbox" }
-- off by default since 0.9.12 (the car condition's mileage wear does the same); allFaults() switches them back on
local OFF = { clutch = true, idle = true, gearbox = true }
local function allFaults(cfg)
  local list = {}
  for _, f in ipairs(World.new():serverConfig().faults.list) do f.enabled = nil; list[#list + 1] = f end
  cfg.faults = { list = list, severity = { 1, 1, 1, 1 } }   -- (the listed strengths at every condition)
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

t.test("car condition: chosen before buying, it sets every car's price (faults.discount); locked once bought", function()
  local w = World.new({ files = F.files(F.twoRaces()) })   -- (the test dealer list: the Covet is $4,500 new)
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:chat(A, "/tg condition needs work")
  t.ok(w:chatHas(A, "Car condition: Needs work (100,000 km) - cars up to 40% off (fast ones hold their value)."))
  t.eq(w:state(A).cash, 10000, "no cash bonus: the prices drop instead")
  w:chat(A, "/tg dealer covet")
  t.ok(w:chatHas(A, "  $2,700  Ibishu Covet"), "$4,500 x 0.6")
  w:chat(A, "/tg condition used")          -- changed her mind: free before buying
  w:chat(A, "/tg dealer covet")
  t.ok(w:chatHas(A, "  $3,400  Ibishu Covet"), "$4,500 x 0.75 = $3,375, to the nearest $100")
  w:chat(A, "/tg condition new")
  t.ok(w:chatHas(A, "Car condition: New - full price."))
  w:chat(A, "/tg fault take 2")            -- the old command still works: two steps worse
  t.ok(w:chatHas(A, "Car condition: Needs work"))
  pin(w, { "engine", "brakes" })
  w:buy(A, "covet", "base_M")            -- bought at the Needs work price; the problems are drawn now
  w:step(10)
  t.ok(w:chatHas(B, "Alice bought an Ibishu Covet for $2,700 - a Needs work, $1,800 off ($7,300 left)."))
  t.eq(w:state(A).cash, 10000 - 2700)
  t.ok(math.abs(A.current.engine.outputTorqueState - 0.8) < 1e-9, "engine problem on the car")
  t.eq(A.current.wheels[0].brakeTorque, 1500 * 0.6, "brake problem on the car")
  w:chat(A, "/tg condition death trap")    -- locked in with the car
  t.ok(w:chatHas(A, "You've bought your Ibishu Covet as Needs work - that's locked in (return it to choose again)."))
  t.eq(w:state(A).cash, 10000 - 2700)
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
  w:step(250)                     -- a cut-out comes every 120-240 s (a Beater's; test fixtures pin severity 1)
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
  t.eq(A.current.parts["/bumper_F/"], "covet_bumper_F", "the bumpers are back on")
  w:assertClean()
end)

t.test("accident damage takes the bumpers off too; fixing it with other crash damage bills only that damage", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  start(w, A, "covet", { "body" })
  t.eq(A.current.parts["/bumper_F/"], "", "no front bumper")
  t.eq(A.current.parts["/bumper_R/"], "", "no rear bumper")
  t.eq(A.current.damage, 3000, "dented (after the respawn that took the bumpers off)")
  w:chat(A, "/tg ready"); w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:damage(A, 5000); w:step(3)                 -- 2,000 more from the race
  local before = w:state(A).cash
  w:chat(A, "/tg fix body"); w:step(5)
  t.eq(A.current.damage, 0)
  -- the fix ($500) + a workshop repair of the other 2,000: ($250 + 2000 x 0.5) x 0.85 = $1,063
  t.eq(before - w:state(A).cash, 500 + 1063, "the race damage is still billed")
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
  t.eq(w:state(A).cash, 10000 - 2600, "a Used Miramar ($3,500 x 0.75 = $2,625 -> $2,600); no money moves on a swap")
  t.noLine(A.chat, "can't take")
  w:chat(A, "/tg fault caps")
  t.ok(w:chatHas(A, "miramar/base_M: works tires | can't take fuelleak"))
  t.ok(w:serverConfig().faultCaps["miramar/base_M"].no.fuelleak, "saved to config.json")

  -- the next Miramar never draws the fuel leak: the draw skips it
  w:chat(B, "/tg fault take")
  pin(w, { "cooling", "body" }, { "fuelleak" })   -- cooling can't be applied either; accident damage can
  w:buy(B, "miramar", "base_M")
  w:step(10)
  w:chat(A, "/tg fault caps")
  t.ok(w:chatHas(A, "miramar/base_M: works body, tires | can't take cooling, fuelleak"))
  t.eq(B.current.parts["/bumper_F/"], "", "Bob got accident damage in the end: no front bumper")
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
  t.eq(#fl.list, 17)
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
  w:showModel(A, "Ibishu Covet")
  local s = A.client.im.textOf(WIN)
  t.match(s, "Car condition%]\n<New>")
  t.match(s, "A more worn car is cheaper on the market: Used up to 25%% off, Needs work up to 40%% off, Beater up to 55%% off, Death Trap up to 70%% off%.")
  t.match(s, "Fast cars hold their value: the quicker a car, the smaller its discount%.")
  t.match(s, "Choose before you buy %- it's locked in with the car%.")
  t.match(s, "%$4,500  Ibishu Covet")
  t.ok(not s:find("Problem cars", 1, true) and not A.client.im.hasButton("Take 1 fault (+$2,500)"), "no dropdown, no Take buttons")
  t.eq(slider().min, 0); t.eq(slider().max, 4)
  A.client.im.setInt("##condition", 3)
  w:step(2.5)
  t.eq(w:state(A).cash, 10000, "the cash doesn't move...")
  s = A.client.im.textOf(WIN)
  t.match(s, "%$2,000  Ibishu Covet", "...the prices do: $4,500 x 0.45 = $2,025 -> $2,000")
  t.match(s, "<Beater>")
  t.match(s, "Beater %(200,000 km%): prices up to 55%% off%.")
  t.ok(not slider().text:find("%d"), "no number on the slider: " .. slider().text)
  A.client.im.setInt("##condition", 1)
  w:step(2.5)
  t.match(A.client.im.textOf(WIN), "<Used>")
  t.match(A.client.im.textOf(WIN), "%$3,400  Ibishu Covet")
  pin(w, { "engine" })
  w:buy(A, "covet", "base_M")
  w:step(2.5)
  t.eq(slider(), nil, "bought: no slider - it's locked in")
  t.match(A.client.im.textOf(WIN), "Bought as Used %(60,000 km%)%.")
  t.match(A.client.im.textOf(WIN), "That's locked in %- return the car to choose again%.")
  t.match(A.client.im.textOf(WIN), "at least %$500%) %- %$500 for yours")
  t.eq(w:state(A).cash, 10000 - 3400)
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
  for _, name in ipairs({ "Worn, underinflated tires", "Knocked-out wheel alignment", "Tired engine (about -20% power)",
      "Worn brakes (about -40% braking)", "Ignition problems (misfires, cuts out, slow to start)", "Cooling problems (leaking radiator)",
      "Worn-out suspension (soft and bouncy)", "Fuel leak", "Accident damage (missing bumpers, dents, broken lights)",
      "Slipping clutch", "Worn gearbox synchros (gears grind)", "Damaged turbo (low boost)",
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

  A.client.im.click("Test: Ignition problems (misfires, cuts out, slow to start)##ft1_ignition")
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
  pin(w, { "ignition", "clutch", "synchros", "abs" }, nil, true)
  w:buy(A, "covet", "base_M")        -- manual, no turbo
  -- Bob draws a clutch and synchros (no manual gearbox: swapped) and a turbo; the swaps are pinned to brakefade/oilleak
  pin(w, { "clutch", "synchros", "turbo", "brakefade", "oilleak" }, nil, true)
  w.chances = { 0.9 }                -- (oil leak: this engine isn't doomed)
  w:buy(B, "pessima", "base_M")      -- automatic, turbo
  w:step(15)
  local a, b = A.current, B.current
  t.ok(math.abs(a.engine.starterTorque - 60) < 1e-9, "ignition problems include a weak starter: x0.6 (it still starts)")
  t.ok(math.abs(a.devices.clutch.damageLockTorqueCoef - 0.6) < 1e-9, "slipping clutch: 60% grip")
  t.eq(a.devices.clutch.clutchPermanentlyDamaged, false, "not BeamNG's flat 25% 'permanently damaged'")
  t.eq(a.devices.gearbox.synchroWear[2], 0.8, "worn synchros"); t.eq(a.devices.gearbox.synchroWearCoef[2], 0, "grinding adds no wear")
  t.eq(a.abs, "off", "no ABS")
  t.ok(math.abs(b.turboDamage - 0.02) < 1e-9, "damaged turbo")
  t.eq(b.wheels[0].padGlazingFactor, 1, "glazed pads")
  t.ok(math.abs(b.engine.damageFrictionCoef - 1.5) < 1e-9, "oil leak: engine friction up")
  w:chat(A, "/tg fault caps")
  t.ok(w:chatHas(A, "pessima/base_M: works brakefade, oilleak, turbo | can't take clutch, synchros"))

  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  w:step(20)
  w:resetCar(A); w:resetCar(B); w:step(3)   -- a reset repairs all of that... and the faults go back on
  t.ok(math.abs(a.devices.clutch.damageLockTorqueCoef - 0.6) < 1e-9, "not stacked"); t.eq(a.devices.gearbox.synchroWear[2], 0.8); t.eq(a.abs, "off")
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
  pin(w, { "oilleak", "brakes", "cooling" }); w.chances = { chance }
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
  t.eq(#fl, 17, "(missing bumpers and the weak starter merged into others since 0.9.13)")
  t.eq(fl[1].factor, 0.5, "existing faults untouched")
  t.eq(fl[15].id, "oilleak"); t.eq(fl[15].blowChance, 0.2)
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
  t.eq(w:state(A).cash, 10000 - 5600, "a Used pickup ($7,500 x 0.75 = $5,625 -> $5,600); no refund for the part the fault took off")
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
  w.rolls = { "last", 5, 4 }; w.chances = { 0.9 }   -- oil leak (last when it's in the draw), ignition, worn brakes
  w:buy(A, "covet", "base_M"); w:step(10)
  toWorkshop(w, A)
  local e = A.current.engine
  t.ok(math.abs(e.damageFrictionCoef - 1.5) < 1e-9 and math.abs(e.slowIgnitionErrorChance - 0.05) < 1e-9, "oil leak + misfires")
  local before = w:state(A).cash
  fit(w, A, "/covet_engine/", "covet_engine_turbo")   -- stock $2,000 -> turbo $3,200
  t.ok(w:chatHas(A, "The new part sorted: Ignition problems (misfires, cuts out, slow to start), Oil leak (runs hot - might blow the engine). The old one was scrap - no trade-in."))
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
  w.rolls = { 4 }; w:buy(A, "covet", "base_M"); w:step(10)   -- worn brakes (not an engine problem)
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
  w.rolls = { 7 }; w:buy(A, "covet", "base_M"); w:step(10)   -- worn-out suspension
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
    if f.id == "fuelleak" then f.factor = 0.7 end   -- an admin's own value: kept
    if f.id == "brakefade" then f.refresh = nil end
  end
  for _, f in ipairs(list) do if f.id == "ignition" then f.starter = nil end end   -- (as a 0.9.12 config: a starter fault of its own)
  list[#list + 1] = { id = "starter", name = "Weak starter (slow to start)", factor = 0.35 }
  local cfg = F.twoRaces(); cfg.faults = { list = list }; cfg.migrations = { mileageOverlap = true, conditionPricing = true }
  local by = {}
  for _, f in ipairs(World.new({ files = F.files(cfg) }):serverConfig().faults.list) do by[f.id] = f end
  t.eq(by.ignition.factor, 0.05); t.eq(by.ignition.cutoutMin, 120); t.eq(by.ignition.cutoutMax, 240)   -- (then 0.9.12's 2nd tuning)
  t.eq(by.ignition.starter, 0.6, "0.35 -> 0.6, then into the ignition problems (0.9.13)"); t.eq(by.starter, nil)
  t.eq(by.fuelleak.factor, 0.7, "a custom value isn't touched")
  t.eq(by.brakefade.refresh, 0.5)
end)

t.test("ignition cut-outs: saved configs at 180-480 s move to 120-240 s once (custom values kept)", function()
  local function load(min, max)
    local list = World.new():serverConfig().faults.list
    for _, f in ipairs(list) do if f.id == "ignition" then f.cutoutMin, f.cutoutMax = min, max end end
    local cfg = F.twoRaces(); cfg.faults = { list = list }
    cfg.migrations = { mileageOverlap = true, conditionPricing = true, faultTuning2 = true }
    for _, f in ipairs(World.new({ files = F.files(cfg) }):serverConfig().faults.list) do if f.id == "ignition" then return f end end
  end
  local f = load(180, 480); t.eq(f.cutoutMin, 120); t.eq(f.cutoutMax, 240)
  f = load(100, 200); t.eq(f.cutoutMin, 100, "a custom value isn't touched"); t.eq(f.cutoutMax, 200)
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

t.test("fast cars hold their value: the condition discount shrinks with the 0-100 km/h time", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local cfg = w:serverConfig()   -- (the defaults: full discount at 10 s or slower, 30% of it at 4 s or quicker)
  t.eq(cfg.faults.perfFastSeconds, 4); t.eq(cfg.faults.perfSlowSeconds, 10); t.eq(cfg.faults.perfMinShare, 0.3)
  -- worked by hand for a $64,700 car as a Death Trap (career price 30%: a 70% discount)
  -- share = 0.3 + 0.7 x (acc - 4) / 6, clamped; price = 64,700 x (1 - 0.7 x share), to the nearest $100
  local cases = { { 12, 19400 }, { 10, 19400 }, { 7, 35300 }, { 4.4, 49000 }, { 3, 51100 } }
  for _, c in ipairs(cases) do
    local acc, want = c[1], c[2]
    local list = { etkx = { m = { name = "ETK x", price = 64700, attrs = { Type = "Car", ["0-100 km/h"] = acc } } } }
    local w2 = World.new({ files = F.files(F.config(F.twoRaces().events, { dealer = { useGamePrices = true, importedAll = true,
      catalogue = "import", gamePrices = list } })) })
    local B = w2:join("Alice")   -- (the admin)
    w2:chat(B, "/tg budget 100000"); w2:chat(B, "/tg start"); w2:chat(B, "/tg condition death trap")
    w2:chat(B, "/tg dealer etkx")
    t.ok(w2:chatHas(B, string.format("  $%s  ETK x", ({ [19400] = "19,400", [35300] = "35,300", [49000] = "49,000", [51100] = "51,100" })[want])),
      string.format("0-100 in %s s -> $%d", acc, want))
  end
end)

-- More worn, worse problems (0.9.12): the listed strengths are a Beater's; Used x0.5, Needs work x0.75, Death Trap x1.3
t.test("more worn cars have worse problems: each problem's strength scales with the condition", function()
  local base = F.twoRaces(); base.faults = nil; base.workshopEvery = 1   -- (the real severities, not the tests' flat ones)
  local function car(cond, ids)
    local w = World.new({ files = F.files(base) })
    local A = w:join("Alice")
    w:chat(A, "/tg start"); w:chat(A, "/tg condition " .. cond)
    pin(w, ids); w:buy(A, "covet", "base_M"); w:step(10)
    return w, A
  end
  -- worked by hand: engine 0.8 -> loss 20% x s; brakes 0.6 -> loss 40% x s; fuel leak 1 L/min x s
  local _, U = car("used", { "engine" })
  t.ok(math.abs(U.current.engine.outputTorqueState - 0.9) < 1e-9, "Used: -10% power")
  local _, D = car("death trap", { "engine", "brakes", "cooling", "ignition" })
  t.ok(math.abs(D.current.engine.outputTorqueState - 0.74) < 1e-9, "Death Trap: -26% power")
  t.ok(math.abs(D.current.wheels[0].brakeTorque - 1500 * 0.48) < 1e-6, "Death Trap: -52% braking")
  t.ok(math.abs(D.current.engine.starterTorque - 60) < 1e-9, "the starter never gets weaker than listed (it must still start)")
  t.ok(math.abs(D.current.engine.slowIgnitionErrorChance - 0.065) < 1e-9, "misfires +0.05 x 1.3")
  local w, N = car("needs work", { "brakes", "engine" })
  t.ok(math.abs(N.current.wheels[0].brakeTorque - 1500 * 0.7) < 1e-6, "Needs work: -30% braking")
  -- the names follow (a workshop reveals them)
  w:chat(N, "/tg ready"); w:drive(N, p(500), 40); w:chat(N, "/tg go")
  w:waitFor(function() return w:state(N).phase == "event" end, 10, "GO")
  w:drive(N, p(900), 40)
  w:waitFor(function() return w:state(N).phase == "workshop" end, 10, "the workshop")
  t.ok(w:chatHas(N, "Tired engine (about -15% power)") and w:chatHas(N, "Worn brakes (about -30% braking)"), "names fit the car")
  w:assertClean()
end)

t.test("ignition cut-outs: a Used car every 4-8 minutes, a Death Trap closer together than listed", function()
  local base = F.twoRaces(); base.faults = nil
  local w = World.new({ files = F.files(base) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition used")
  pin(w, { "ignition" }); w:buy(A, "covet", "base_M"); w:step(10)
  w:chat(A, "/tg ready")
  w:step(235)   -- a Used car's cut-outs: 240-480 s (120-240 / 0.5) - Ryan: "every 4-8 mins"
  t.eq(A.current.stalls, 0, "none in the first 4 minutes")
  w:step(250)
  t.ok(A.current.stalls >= 1, "but one by 8 minutes")
  w:assertClean()
  local w2 = World.new({ files = F.files(base) })
  local B = w2:join("Alice")   -- (the admin)
  w2:chat(B, "/tg start"); w2:chat(B, "/tg condition death trap")
  pin(w2, { "ignition", "brakefade", "alignment", "abs" }); w2:buy(B, "covet", "base_M"); w2:step(10)   -- (a Death Trap has 4)
  w2:chat(B, "/tg ready")
  w2:step(190)  -- a Death Trap's: about 92-185 s (/ 1.3)
  t.ok(B.current.stalls >= 1, "a Death Trap has cut out within about 3 minutes")
  w2:assertClean()
end)

t.test("knocked-out alignment pulls to one side: steering's straight ahead moved, kept through resets, gone when fixed", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  start(w, A, "covet", { "alignment" })
  local d = w:steerOffset(A)
  t.ok(math.abs(math.abs(d) - 0.028) < 1e-9, "2.8% of full steering, either way: " .. tostring(d))
  local side = d < 0 and "left" or "right"
  w:chat(A, "/tg diag"); w:step(3)
  t.ok(w:chatHas(A, "Alignment pull: ok"), "/tg diag shows the pull")
  w:chat(A, "/tg ready")
  w:step(20)
  w:resetCar(A); w:step(3)
  t.ok(math.abs(w:steerOffset(A) - d) < 1e-9, "the same after a reset (applied to the originals, never twice)")
  w:chat(A, "/tg tow"); w:step(5)
  t.ok(math.abs(w:steerOffset(A) - d) < 1e-9, "and after a tow (a new car: applied again)")
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  t.ok(w:chatHas(A, "Knocked-out wheel alignment (pulls to the " .. side .. ") (/tg fix alignment)"), "the name says which way")
  w:chat(A, "/tg fix alignment"); w:step(5)
  t.ok(math.abs(w:steerOffset(A)) < 1e-9, "fixed: straight ahead is straight again")
  w:resetCar(A); w:step(3)
  t.ok(math.abs(w:steerOffset(A)) < 1e-9, "and stays fixed")
  w:assertClean()
end)

t.test("alignment pull: half as strong on a Used car; a car without steering hydros can't take it", function()
  local base = F.twoRaces(); base.faults = nil   -- (the real severities)
  local w = World.new({ files = F.files(base) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition used")
  pin(w, { "alignment" }); w:buy(A, "covet", "base_M"); w:step(10)
  t.ok(math.abs(math.abs(w:steerOffset(A)) - 0.014) < 1e-9, "Used: 1.4%: " .. tostring(w:steerOffset(A)))
  w.models.pessima.noSteering = true   -- (no toe settings in the test cars either)
  w:chat(B, "/tg condition used")
  pin(w, { "alignment", "brakes" }); w:buy(B, "pessima", "base_M"); w:step(10)
  t.ok(B.current.wheels[0].brakeTorque < 1800, "swapped for worn brakes")
  w:chat(A, "/tg fault caps")
  t.ok(w:chatHas(A, "can't take alignment"), "remembered for that car")
  w:assertClean()
end)

t.test("saved configs get the alignment pull once", function()
  local list = World.new():serverConfig().faults.list
  for _, f in ipairs(list) do if f.id == "alignment" then f.pull = nil end end
  local cfg = F.twoRaces(); cfg.faults = { list = list }
  cfg.migrations = { mileageOverlap = true, conditionPricing = true, faultTuning2 = true }
  for _, f in ipairs(World.new({ files = F.files(cfg) }):serverConfig().faults.list) do
    if f.id == "alignment" then t.eq(f.pull, 0.028, "(0.015, then +20%, then +1 point)") end
  end
end)

t.test("worn synchros on a Death Trap: 90% (never 100%, where BeamNG breaks the gear), and grinding adds no wear", function()
  local base = F.twoRaces(); base.faults = nil; base.workshopEvery = 1   -- (the real severities)
  local w = World.new({ files = F.files(base) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition death trap")
  pin(w, { "synchros", "brakefade", "alignment", "abs" }); w:buy(A, "covet", "base_M"); w:step(10)   -- (manual)
  local g = A.current.devices.gearbox
  for i = 1, 4 do
    t.ok(math.abs(g.synchroWear[i] - 0.9) < 1e-9, "gear " .. i .. ": 90% worn, not 1.04 or 1: " .. tostring(g.synchroWear[i]))
    t.eq(g.synchroWearCoef[i], 0, "gear " .. i .. ": grinding adds no wear")
    t.ok(g.gearRatios[i] ~= 0, "gear " .. i .. " still drives")
  end
  w:chat(A, "/tg ready")
  w:step(20)
  w:resetCar(A); w:step(3)
  t.ok(math.abs(A.current.devices.gearbox.synchroWear[2] - 0.9) < 1e-9, "back after a reset")
  t.eq(A.current.devices.gearbox.synchroWearCoef[2], 0)
  w:chat(A, "/tg tow"); w:step(5)
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:chat(A, "/tg setcash Alice 50000")
  w:chat(A, "/tg fix synchros"); w:step(5)
  g = A.current.devices.gearbox
  t.eq(g.synchroWear[2], 0, "fixed: new synchros")
  t.eq(g.synchroWearCoef[2], 5e-6, "and the game's own wear is back")
  w:assertClean()
end)

t.test("alignment pull on a Death Trap: 3.64% of full steering (Ryan: +20%, then +1 point)", function()
  local base = F.twoRaces(); base.faults = nil
  local w = World.new({ files = F.files(base) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition death trap")
  pin(w, { "alignment", "brakefade", "abs", "body" }); w:buy(A, "covet", "base_M"); w:step(10)
  t.ok(math.abs(math.abs(w:steerOffset(A)) - 0.0364) < 1e-9, "Death Trap: " .. tostring(w:steerOffset(A)))
  w:assertClean()
end)

t.test("admin fault test 'as' a condition: the same strengths as a car bought that way; the Tools dropdown picks it", function()
  local base = F.twoRaces(); base.faults = nil   -- (the real severities: Used x0.5 .. Death Trap x1.3)
  local w = World.new({ files = F.files(base) })
  local A = w:join("Alice")
  w:buy(A, "covet", "base_M"); w:step(2)       -- (idle: just a car to test on)
  w:chat(A, "/tg fault test engine as used"); w:step(3)
  t.ok(w:chatHas(A, "Applying 1 test fault(s) to your current car as a Used (x0.5)..."))
  t.ok(math.abs(A.current.engine.outputTorqueState - 0.9) < 1e-9, "Used: -10% power, not the listed -20%")
  w:chat(A, "/tg fault testoff"); w:step(3)
  w:chat(A, "/tg fault test alignment as death trap"); w:step(3)
  t.ok(math.abs(w:steerOffset(A) - 0.0364) < 1e-9, "Death Trap: a 3.64% pull (to the right): " .. tostring(w:steerOffset(A)))
  w:chat(A, "/tg fault testoff"); w:step(3)
  w:chat(A, "/tg fault test engine"); w:step(3)
  t.ok(w:chatHas(A, "(listed strengths)"), "no condition: as listed")
  t.ok(math.abs(A.current.engine.outputTorqueState - 0.8) < 1e-9)
  w:chat(A, "/tg fault test engine as new")
  t.ok(w:chatHas(A, "Test as: used, needs work, beater or death trap."))
  -- the Admin tab: Tools > fault test has a "Test as" dropdown (Beater by default); the buttons follow it
  w:chat(A, "/tg fault testoff"); w:chat(A, "/tg menu"); w:step(3)
  local combo
  for _, it in ipairs(A.client.im.items("Top Gear Challenge")) do if it.kind == "combo" and it.preview == "Beater (x1)" then combo = it end end
  t.ok(combo, "Test as: Beater (x1) by default")
  A.client.im.click("Used (x0.5)"); w:step(0.5)
  A.client.im.click("Test: Tired engine (about -20% power)##ft1_engine"); w:step(3)
  t.ok(w:chatHas(A, "as a Used (x0.5)"), "the button tested it as Used")
  w:assertClean()
end)

t.test("missing bumpers merged into accident damage: saved configs and a saved challenge move over once", function()
  local list = World.new():serverConfig().faults.list
  table.insert(list, 3, { id = "bumpers", name = "Missing bumpers" })
  for _, f in ipairs(list) do if f.id == "body" then f.name = "Accident damage (dents, broken lights)" end end
  local cfg = F.twoRaces(); cfg.faults = { list = list }
  cfg.faultCaps = { ["covet/base_M"] = { ok = { bumpers = true, tires = true }, no = {} } }
  cfg.migrations = { mileageOverlap = true, conditionPricing = true, faultTuning2 = true }
  local w = World.new({ files = F.files(cfg) })
  local sc = w:serverConfig()
  local ids, body = {}, nil
  for _, f in ipairs(sc.faults.list) do ids[#ids + 1] = f.id; if f.id == "body" then body = f end end
  t.eq(#ids, 17); t.ok(not table.concat(ids, ","):find("bumpers"), "no bumpers fault")
  t.eq(body.name, "Accident damage (missing bumpers, dents, broken lights)")
  t.eq(sc.faultCaps["covet/base_M"].ok.bumpers, nil, "learnt caps tidied")
  -- a challenge saved mid-way with the old fault: it's accident damage now (never twice)
  local A = w:join("Alice")
  start(w, A, "covet", { "tires" })
  local SESSION = "Resources/Server/TopGear/session.json"
  w:step(6)
  local files = {}
  for k, v in pairs(w.files) do files[k] = v end
  local json = require("json")
  local sess = json.decode(files[SESSION])
  for _, pl in pairs(sess.game.players) do pl.faults = { "bumpers" } end   -- (as a 0.9.12 server saved it)
  files[SESSION] = json.encode(sess)
  local w2 = World.new({ files = files })
  local A2 = w2:join("Alice"); w2:step(1)
  w2:chat(A2, "/tg resume"); w2:step(20)       -- the car comes back with its problems
  t.ok(A2.current, "Alice's car is back")
  t.eq(A2.current.parts["/bumper_F/"], "", "the saved bumpers fault became accident damage: no bumpers...")
  t.eq(A2.current.damage, 1500, "...and its dents (a Used car: 3,000 x 0.5 - this config has the real severities)")
  t.eq(A2.current.vars["$tirepressure_F"], 30, "(the tyres were never the problem)")
end)

t.test("the weak starter merged into the ignition problems: one fault, both parts, scaled; saved data moves over", function()
  local base = F.twoRaces(); base.faults = nil   -- (the real severities)
  local w = World.new({ files = F.files(base) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition used")
  pin(w, { "ignition" }); w:buy(A, "covet", "base_M"); w:step(10)
  local e = A.current.engine
  t.ok(math.abs(e.slowIgnitionErrorChance - 0.025) < 1e-9, "misfires +0.05 x 0.5")
  t.ok(math.abs(e.starterTorque - 80) < 1e-9, "a Used car's starter: -40% x 0.5 = x0.8")
  for _, f in ipairs(w:serverConfig().faults.list) do t.ok(f.id ~= "starter", "no starter fault of its own") end
  -- a 0.9.12 config with a custom starter strength: kept, inside the ignition problems
  local list = World.new():serverConfig().faults.list
  for _, f in ipairs(list) do if f.id == "ignition" then f.starter, f.name = nil, "Ignition problems (misfires, cuts out)" end end
  list[#list + 1] = { id = "starter", name = "Weak starter (slow to start)", factor = 0.7 }
  local cfg = F.twoRaces(); cfg.faults = { list = list }
  cfg.migrations = { mileageOverlap = true, conditionPricing = true, faultTuning2 = true, combineBumpers = true }
  for _, f in ipairs(World.new({ files = F.files(cfg) }):serverConfig().faults.list) do
    t.ok(f.id ~= "starter")
    if f.id == "ignition" then
      t.eq(f.starter, 0.7, "the admin's own starter strength")
      t.eq(f.name, "Ignition problems (misfires, cuts out, slow to start)")
    end
  end
  w:assertClean()
end)

t.test("slipping clutch: less grip, scaled by condition (Death Trap 48%), never BeamNG's flat 25%; no stacking on a reset", function()
  local base = allFaults(F.twoRaces()); base.faults.severity = nil   -- (clutch switched on; the real severities)
  local w = World.new({ files = F.files(base) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition death trap")
  pin(w, { "clutch", "abs", "brakefade", "alignment" }, nil, true); w:buy(A, "covet", "base_M"); w:step(10)   -- (manual)
  local c = A.current.devices.clutch
  t.ok(math.abs(c.damageLockTorqueCoef - 0.48) < 1e-9, "Death Trap: 1 - 40% x 1.3 = 48% grip: " .. tostring(c.damageLockTorqueCoef))
  t.eq(c.clutchPermanentlyDamaged, false)
  w:chat(A, "/tg ready"); w:step(20)
  w:resetCar(A); w:step(3)
  t.ok(math.abs(A.current.devices.clutch.damageLockTorqueCoef - 0.48) < 1e-9, "the same after a reset")
  w:assertClean()
end)

t.test("saved configs: the slipping clutch gets its grip factor once (switched off as before)", function()
  local list = World.new():serverConfig().faults.list
  for _, f in ipairs(list) do if f.id == "clutch" then f.factor = nil end end
  local cfg = F.twoRaces(); cfg.faults = { list = list }
  for _, f in ipairs(World.new({ files = F.files(cfg) }):serverConfig().faults.list) do
    if f.id == "clutch" then t.eq(f.factor, 0.6); t.eq(f.enabled, false) end
  end
end)

t.test("saved configs at the 1.8% alignment pull move to 2.8% once (custom values kept)", function()
  local function load(pull)
    local list = World.new():serverConfig().faults.list
    for _, f in ipairs(list) do if f.id == "alignment" then f.pull = pull end end
    local cfg = F.twoRaces(); cfg.faults = { list = list }
    cfg.migrations = { mileageOverlap = true, conditionPricing = true, faultTuning2 = true, alignmentPull = true, alignmentPull2 = true }
    for _, f in ipairs(World.new({ files = F.files(cfg) }):serverConfig().faults.list) do if f.id == "alignment" then return f.pull end end
  end
  t.eq(load(0.018), 0.028)
  t.eq(load(0.025), 0.025, "a custom value isn't touched")
end)

t.test("condition discounts: 25/40/55/70% off (faults.discount); an empty list goes back to career's mileage formula", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  for _, c in ipairs({ { "used", "$3,400" }, { "needs work", "$2,700" }, { "beater", "$2,000" }, { "death trap", "$1,400" } }) do
    w:chat(A, "/tg condition " .. c[1]); w:chat(A, "/tg dealer covet")   -- ($4,500 x 0.75 / 0.6 / 0.45 / 0.3, nearest $100)
    t.ok(w:chatHas(A, "  " .. c[2] .. "  Ibishu Covet"), c[1] .. ": " .. c[2])
  end
  local cfg = F.twoRaces(); cfg.faults.discount = {}
  local w2 = World.new({ files = F.files(cfg) })
  local B = w2:join("Alice")
  w2:chat(B, "/tg start"); w2:chat(B, "/tg condition used"); w2:chat(B, "/tg dealer covet")
  t.ok(w2:chatHas(B, "  $4,100  Ibishu Covet"), "career's formula: x0.9")
  w:assertClean()
end)

t.test("accident damage: a repair never bills the problem's own dents (they come back) - nothing to repair if they're all", function()
  local cfg = F.twoRaces(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  start(w, A, "covet", { "body" })
  t.eq(A.current.damage, 3000)
  w:chat(A, "/tg ready"); w:drive(A, p(500), 40); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  w:step(2.5)
  -- only the problem's dents: nothing to repair (Ryan's bug: repair, dents back, repair again...)
  t.eq(w:ui(A).me.repair, 0, "no repair price for the problem's own dents")
  t.ok(w:ui(A).me.dentsOnly)
  t.ok(A.client.im.hasButton("Nothing to repair"), "the button says so")
  local cash = w:state(A).cash
  w:chat(A, "/tg repair")
  t.ok(w:chatHas(A, "Nothing to repair: the dents are the accident damage problem's - they'd come straight back. Fix the problem itself (/tg fix body)."))
  t.eq(w:state(A).cash, cash, "nothing charged")
  -- more damage on top: only that is repaired and billed - ($250 + 2,000 x $0.50) x 0.85 = $1,062.50 -> $1,063
  w:damage(A, 5000); w:step(2.5)
  t.eq(w:ui(A).me.repair, 1063)
  w:chat(A, "/tg repair"); w:step(5)
  t.eq(w:state(A).cash, cash - 1063)
  t.eq(A.current.damage, 3000, "the problem's dents came back after the repair")
  w:step(2.5)
  t.eq(w:ui(A).me.repair, 0, "...and they aren't offered for repair again")
  w:chat(A, "/tg repair"); w:step(2)
  t.eq(w:state(A).cash, cash - 1063, "no second charge")
  w:assertClean()
end)
