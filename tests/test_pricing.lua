-- Price estimates (0.9.3): trims the game has no value for are priced from the most similar priced trims
-- (power-to-weight, 0-100, top speed, weight, year, off-road score); props, traffic and trailers aren't imported.
-- tests/data/game-cars.json is a real import from Ryan's game (BeamNG 0.36-era, 122 models, 1,711 trims).
local t = require("t")
local World = require("world")
local F = require("fixtures")
local json = require("json")

local WIN = "Top Gear Challenge"
local function perf(wp, acc, top, weight, year, extra)
  local a = { ["Weight/Power"] = wp, ["0-100 km/h"] = acc, ["Top Speed"] = top, Weight = weight, ["Off-Road Score"] = 30,
              ["Config Type"] = "Factory", Transmission = "Manual" }
  if year then a.Years = { min = year, max = year } end
  for k, v in pairs(extra or {}) do a[k] = v end
  return a
end
-- a hatchback range from slow to quick, a derby build with no price, a joke build with no figures at all,
-- a trailer and a cone (both priced) and an AI-traffic stand-in (no price)
local MODELS = {
  covet = { brand = "Ibishu", name = "Covet", configs = { base_M = 4000, sport_M = 8000, gtz_M = 16000, derby = false, joke = false },
            info = { Country = "Japan", ["Body Style"] = "Hatchback", Type = "Car", Years = { min = 1988, max = 1996 } },
            trims = { base_M = perf(14, 12, 50, 1000), sport_M = perf(10, 9, 55, 1050), gtz_M = perf(7, 6.5, 62, 1100),
                      derby = perf(9.5, 8.8, 54, 1080, nil, { ["Config Type"] = "Custom" }), joke = { ["Config Type"] = "Custom" } } },
  pessima = { brand = "Ibishu", name = "Pessima", configs = { base_M = 4400, gt_M = 12000 },
              info = { Country = "Japan", ["Body Style"] = "Sedan", Type = "Car", Years = { min = 1988, max = 1996 } },
              trims = { base_M = perf(13, 11.5, 51, 1200), gt_M = perf(8, 7.5, 60, 1250) } },
  tsfb = { brand = "", name = "Small flatbed trailer", configs = { base = 900 }, info = { Type = "Trailer" } },
  cones = { brand = "", name = "Cones", configs = { base = 10 }, info = { Type = "Prop" } },
  simple_traffic = { brand = "", name = "Traffic", configs = { covet = false, covet_parked = false },
                     trims = { covet = { Type = "PropTraffic" }, covet_parked = { Type = "PropParked" } } },
}
local function setup(opts)
  local w = World.new({ files = F.files(F.twoRaces()), models = MODELS })
  local A = w:join("Alice")
  w:chat(A, "/tg importprices")
  w:step(2)
  return w, A
end

t.test("import: props, traffic and trailers are skipped; trims without a game price get an estimate", function()
  local w, A = setup()
  t.ok(w:chatHas(A, "Imported 5 trim prices from 5 models."))
  t.ok(w:chatHas(A, "Skipped 4 trims that aren't cars (props, traffic, trailers)."))
  t.ok(w:chatHas(A, "2 trims had no game price: 2 priced by estimate from similar cars."))
  local gp = w:serverConfig().dealer.gamePrices
  t.eq(gp.tsfb, nil); t.eq(gp.cones, nil); t.eq(gp.simple_traffic, nil)
  t.eq(gp.covet.derby.est, 8000, "the derby Covet performs like the sport Covet ($8,000) - the middle of its 5 neighbours")
  t.eq(gp.covet.joke.est, 8000, "no figures: the middle of its own model's prices ($4,000 / $8,000 / $16,000)")
  t.eq(gp.covet.derby.price, nil, "an estimate isn't a game price")
  w:assertClean()
end)

t.test("an estimated car sells at its estimate, marked as one; /tg setprice replaces it and 'off' goes back", function()
  local w, A = setup()
  local B = w:join("Bob")
  w:chat(A, "/tg setprice list")
  t.ok(w:chatHas(A, "Ibishu Covet derby [covet/derby] - est. $8,000"))
  w:chat(A, "/tg start")
  w:step(2.5)
  t.match(B.client.im.textOf(WIN), "8,000  Ibishu Covet derby  %(est%. price%)")
  t.ok(w:buy(B, "covet", "derby"), "it sells")
  t.eq(w:state(B).cash, 10000 - 8000)
  w:chat(A, "/tg stop")
  w:chat(A, "/tg setprice covet/derby 2500")
  t.ok(w:chatHas(A, "Ibishu Covet derby now costs $2,500."))
  w:step(2.5)
  t.match(A.client.im.textOf(WIN), "Cars without a game price %(2%)")
  t.match(A.client.im.textOf(WIN), "Ibishu Covet joke  %- est%. %$8,000")
  t.match(A.client.im.textOf(WIN), "Ibishu Covet derby  %- %$2,500")
  w:chat(A, "/tg setprice covet/derby off")
  t.ok(w:chatHas(A, "Ibishu Covet derby now costs $8,000 (estimated from similar cars)."))
  w:assertClean()
end)

t.test("a class's multiplier applies to estimates too; the base-trims rule ignores custom builds", function()
  local w, A = setup()
  w:chat(A, "/tg class new cheap")
  w:chat(A, "/tg class rule cheap body Hatchback")
  w:chat(A, "/tg class multiplier cheap 0.5")
  t.ok(w:chatHas(A, "5 trims, $2,000 to $8,000."), "covet $4,000/$8,000/$16,000 + two $8,000 estimates, halved")
  w:chat(A, "/tg class new basics base")
  t.ok(w:chatHas(A, "2 trims, $4,000 to $4,400."), "the derby and joke builds aren't factory trims")
  w:assertClean()
end)

-- the real data ---------------------------------------------------------------------------------------------
local function realCars()
  local f = assert(io.open("tests/data/game-cars.json", "rb"))
  local d = json.decode(f:read("*a"))
  f:close()
  return d
end
local function withCars(gamePrices, modelNames)
  return F.files(F.config(F.twoRaces().events, { dealer = { useGamePrices = true, gamePrices = gamePrices, modelNames = modelNames } }))
end

t.test("real game data: an older import loads with props dropped and every real car priced", function()
  local d = realCars()
  local w = World.new({ files = withCars(d.gamePrices, d.modelNames) })
  w:join("Alice")
  local gp = w:serverConfig().dealer.gamePrices
  t.eq(gp.simple_traffic, nil, "252 AI-traffic stand-ins gone"); t.eq(gp.unicycle, nil); t.eq(gp.cones, nil)
  local noPrice, est = {}, 0
  for model, trims in pairs(gp) do
    for config, e in pairs(trims) do
      t.ok(e.attrs.Type ~= "Trailer" and not tostring(e.attrs.Type):find("^Prop"), model .. "/" .. config .. " is a " .. tostring(e.attrs.Type))
      if not e.price then
        if e.est then est = est + 1 else noPrice[#noPrice + 1] = model .. "/" .. config end
      end
    end
  end
  t.eq(#noPrice, 0, "unpriced: " .. table.concat(noPrice, ", "))
  t.eq(est, 41)
  local function near(e, lo, hi, what) t.ok(e.est >= lo and e.est <= hi, what .. ": $" .. tostring(e.est)) end
  near(gp.pigeon.gambler, 10000, 38000, "Pigeon Gambler, within the Pigeon's range")
  near(gp.miramar.derby, 20000, 40000, "Miramar Derby, near a base Miramar")
  t.ok(gp.sbr.powerglow.est > gp.covet["3wheel"].est * 3, "a 3.3 s SBR costs far more than a three-wheel Covet")
  w:assertClean()
end)

t.test("real game data: hide 1 in 6 real prices - the estimates land close to them", function()
  local d = realCars()
  local hidden, i = {}, 0
  local models = {}
  for model in pairs(d.gamePrices) do models[#models + 1] = model end
  table.sort(models)
  for _, model in ipairs(models) do
    local configs = {}
    for config in pairs(d.gamePrices[model]) do configs[#configs + 1] = config end
    table.sort(configs)
    for _, config in ipairs(configs) do
      local e = d.gamePrices[model][config]
      if e.price and e.attrs and e.attrs["Weight/Power"] and (e.attrs.Type == "Car" or e.attrs.Type == "Truck") then
        i = i + 1
        if i % 6 == 0 then hidden[model .. "/" .. config] = e.price; e.price = nil; e.noPrice = true end
      end
    end
  end
  local w = World.new({ files = withCars(d.gamePrices, d.modelNames) })
  w:join("Alice")
  local gp = w:serverConfig().dealer.gamePrices
  local errs = {}
  for key, real in pairs(hidden) do
    local model, config = key:match("^([^/]+)/(.+)$")
    local est = gp[model][config].est
    t.ok(est, key .. " got no estimate")
    errs[#errs + 1] = math.abs(math.log(est / real))
  end
  table.sort(errs)
  local function pct(q) return math.exp(errs[math.max(1, math.floor(q * #errs))]) - 1 end
  local within25 = 0
  for _, e in ipairs(errs) do if e < math.log(1.25) then within25 = within25 + 1 end end
  print(string.format("        %d hidden prices: median error %.0f%%, 80%% within %.0f%%, %.0f%% within 25%%",
    #errs, pct(0.5) * 100, pct(0.8) * 100, within25 / #errs * 100))
  t.ok(#errs > 120, "enough samples")
  t.ok(pct(0.5) < 0.2, "median error under 20%")
  t.ok(pct(0.8) < 0.5, "80% within 50%")
end)
