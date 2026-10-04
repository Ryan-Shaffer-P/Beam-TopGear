-- The dealership in the game's own vehicle selector (0.9.9): while the dealership is open, the selector's list
-- (core_vehicles.requestList -> 'sendVehicleList') is today's cars at today's prices; otherwise the game's own.
-- Test cars: tests/lib/world.lua MODELS (covet $4,200/$7,800/$14,000, pessima $3,900/$5,100, pickup $6,800/$12,500,
-- miramar $3,100; budget $10,000).
local t = require("t")
local World = require("world")
local F = require("fixtures")

local function open(w, pl)   -- the player opens the vehicle selector
  rawget(pl.client.sb.env, "core_vehicles").openSelectorUI()
  w:step(0.5)
  return pl.client.selectorLists[#pl.client.selectorLists]
end
local function byKey(list)
  local out = {}
  for _, c in ipairs(list.configs) do out[c.model_key .. "/" .. c.key] = c end
  return out
end
local function setup()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg importprices")
  w:step(2)
  return w, A, B
end

t.test("during the dealership the selector lists today's cars at today's prices", function()
  local w, A, B = setup()
  w:chat(A, "/tg class new jdm")
  w:chat(A, "/tg class rule jdm country Japan")
  w:chat(A, "/tg class multiplier jdm 0.5")
  w:chat(A, "/tg class use jdm")
  w:chat(A, "/tg budget 2000")
  w:chat(A, "/tg setprice covet/sport_M 40000")   -- $20,000 in the class: out of reach even as a Death Trap
  w:chat(A, "/tg start")
  w:step(2.5)
  local list = open(w, B)
  t.ok(list and not list.native, "our list, not the game's")
  local c = byKey(list)
  t.eq(c["pickup/d15_M"], nil, "not in today's class")
  t.eq(c["covet/base_M"].Value, 2100, "$4,200 x 0.5")
  t.eq(c["covet/base_M"].Name, "Covet base_M ($2,100) - $1,600 as a Used")   -- ($2,100 x 0.75 = $1,575 -> $1,600)
  t.eq(c["miramar/base_M"].Name, "Miramar base_M ($1,550)", "affordable: just the price")
  t.eq(c["covet/gtz_M"], nil, "even a $2,100 Death Trap is over $2,000: not shown")
  t.eq(c["covet/sport_M"], nil, "over budget at any condition: not shown")
  t.eq(c["covet/base_M"].aggregates.Value.min, 2100, "the Value filter uses our price")
  t.eq(c["covet/base_M"].preview, "/vehicles/covet/base_M.jpg", "thumbnails kept")
  local models = {}
  for _, m in ipairs(list.models) do models[m.key] = m end
  t.ok(models.covet and models.miramar and not models.pickup, "only models with a car for sale")
  t.eq(models.covet.aggregates.Value.max, 2100, "a model's price range covers only the trims that can be bought")
  t.ok(list.filters.Country.Japan and not list.filters.Country["United States"], "filters offer only what's for sale")
  -- buying = spawning one from the list, at that price
  t.ok(w:buy(B, "miramar", "base_M"))
  t.eq(w:state(B).cash, 2000 - 1550)
  w:assertClean()
end)

t.test("the Dealership tab's button opens it; the list follows the car condition", function()
  local w, A, B = setup()
  w:chat(A, "/tg start")
  w:step(2.5)
  B.client.im.click("Browse the cars in the vehicle selector##opensel")
  w:step(0.5)
  t.eq(B.client.selectorOpened, 1)
  local before = byKey(B.client.selectorLists[#B.client.selectorLists])
  t.eq(before["covet/gtz_M"].Name, "Covet gtz_M ($14,000) - $8,400 as a Needs work")   -- ($14,000 x 0.6)
  w:chat(B, "/tg condition needs work")
  local after = byKey(open(w, B))
  t.eq(after["covet/gtz_M"].Name, "Covet gtz_M ($8,400)", "as Needs work it's affordable - at the Needs work price")
  w:assertClean()
end)

t.test("outside the dealership, in traffic mode, or after unloading: the game's own list", function()
  local w, A, B = setup()
  local gh = rawget(B.client.sb.env, "guihooks")
  local gameFn = gh.trigger
  t.ok(open(w, B).native, "no challenge")
  w:chat(A, "/tg start")
  w:chat(A, "/tg traffic on")
  w:step(2.5)
  t.ok(open(w, A).native, "an admin adding traffic sees every car")
  t.ok(not open(w, B).native, "everyone else sees the dealership")
  w:buy(B, "covet", "base_M"); w:chat(A, "/tg traffic off"); w:buy(A, "pessima", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  w:step(2.5)
  t.ok(open(w, B).native, "the dealership has closed")
  t.ok(gh.trigger == gameFn, "the game's own function is put back")
  B.client.M.onExtensionUnloaded()
  t.ok(open(w, B).native)
  w:assertClean()
end)

t.test("if the list can't be built, the game's own list is shown (and the server still guards purchases)", function()
  local w, A, B = setup()
  rawget(B.client.sb.env, "core_vehicles").getModel = function() error("changed in a game update") end
  w:chat(A, "/tg start")
  w:step(2.5)
  local list = open(w, B)
  t.ok(list.native, "fell back to the game's list")
  local pr = w:problems()
  t.eq(#pr, 1, table.concat(pr, "\n"))
  t.match(pr[1], "none of today's cars were found")
  t.eq(w:buy(B, "pickup", "d35_A"), nil, "an over-budget car is still refused by the server")
end)

t.test("whatever sends the list (another game version) and even if the game swaps its hook function, ours goes out", function()
  local w, A, B = setup()
  w:chat(A, "/tg start")
  w:step(2.5)
  local env = B.client.sb.env
  -- a newer game: the screen's list comes from some other function, but still through 'sendVehicleList'
  rawget(env, "guihooks").trigger("sendVehicleList", { models = {}, configs = { { key = "x", model_key = "covet" } }, native = true })
  local got = B.client.selectorLists[#B.client.selectorLists]
  t.ok(not got.native and #got.configs > 0, "swapped for today's list")
  -- the game reloads its UI code: guihooks.trigger is a new function; we hook it again on the next frame
  local fresh = function(name, data) if name == "sendVehicleList" then B.client.selectorLists[#B.client.selectorLists + 1] = data end end
  rawget(env, "guihooks").trigger = fresh
  w:step(0.5)
  t.ok(rawget(env, "guihooks").trigger ~= fresh, "hooked again")
  t.ok(not open(w, B).native)
  w:chat(B, "/tg diag")
  w:step(1)
  t.ok(w:chatHas(B, "Vehicle selector: BeamNG ? | today's list: 8 cars ready | hook on | selector lists 2, replaced 2 | lookups on (8 for sale, reloads "),
    "diag reports it")
  w:assertClean()
end)

-- BeamNG 0.37+ (Ryan's 0.39.4): the selector builds its list through core_vehicles.getModelsData/getModel/getConfig
t.test("0.39 selector: while the dealership is open it only sees today's cars, priced and labelled", function()
  local w, A, B = setup()
  local before = B.client.selector039()
  t.ok(before["pickup/d15_M"] and before["covet/base_M"].name == "base_M", "no challenge: every car, the game's names")
  w:chat(A, "/tg class preset jdm")
  w:chat(A, "/tg class use jdm")
  w:chat(A, "/tg setprice covet/gtz_M 40000")
  w:chat(A, "/tg start")
  w:step(2.5)
  t.ok(B.client.selectorReloads >= 1, "the selector was told to reload")
  local sel = B.client.selector039()
  t.eq(sel["pickup/d15_M"], nil, "not in today's class: not shown at all")
  t.eq(sel["covet/base_M"].name, "base_M ($4,200)")
  t.eq(sel["covet/base_M"].fullName, "Covet base_M ($4,200)")
  t.eq(sel["covet/sport_M"].name, "sport_M ($7,800)")
  t.eq(sel["covet/gtz_M"], nil, "over budget even as a Death Trap ($12,000): not shown")
  t.eq(sel["covet/sport_M"].Value, 7800, "Value = our price (the selector sorts and filters by it)")
  -- the car condition changes every price: the list follows
  w:chat(A, "/tg setprice covet/gtz_M 14000")
  w:chat(B, "/tg condition used")
  w:step(1)
  t.eq(B.client.selector039()["covet/gtz_M"].name, "gtz_M ($10,500) - $8,400 as a Needs work")   -- ($14,000 x 0.75 / x 0.6)
  t.eq(B.client.selector039()["covet/base_M"].name, "base_M ($3,200)", "$4,200 x 0.75 = $3,150 -> $3,200")
  -- the dealership closes: the game's own list and functions again
  local cv = rawget(B.client.sb.env, "core_vehicles")
  w:buy(B, "covet", "base_M"); w:buy(A, "pessima", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  w:step(1)
  t.ok(cv.getModel == cv.__realGetModel, "the game's getModel is back")
  t.eq(B.client.selector039()["covet/base_M"].name, "base_M")
  t.ok(B.client.selector039()["pickup/d15_M"], "every car again")
  w:assertClean()
end)

t.test("0.39 selector: our own price import still reads the game's real data during the dealership", function()
  local w, A = setup()
  w:chat(A, "/tg class preset jdm")
  w:chat(A, "/tg class use jdm")
  w:chat(A, "/tg start")
  w:step(2.5)
  w:chat(A, "/tg importprices")
  w:step(2)
  local gp = w:serverConfig().dealer.gamePrices
  t.ok(gp.pickup and gp.pickup.d15_M, "every car imported, not just today's")
  t.eq(gp.covet.base_M.name, "Ibishu Covet base_M", "with the game's own names")
  w:assertClean()
end)
