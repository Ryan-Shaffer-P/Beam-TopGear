-- Built-in car catalogue (0.9.7): Resources/Server/TopGear/cars.json ships every stock BeamNG car and truck with
-- its price and details, so a new server sells cars without /tg importprices. It isn't copied into config.json;
-- a server's own import replaces it (and is kept); /tg importprices builtin goes back.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local json = require("json")

local WIN = "Top Gear Challenge"
local CARS = "Resources/Server/TopGear/cars.json"
local CONFIG = "Resources/Server/TopGear/config.json"
local function shipped()
  local f = assert(io.open(CARS, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local function fresh(extra)   -- a new install: the plugin's files, no config.json yet
  local files = { [CARS] = shipped() }
  for k, v in pairs(extra or {}) do files[k] = v end
  return files
end
local function restart(w)     -- the same server's files, plugin reloaded
  local files = {}
  for k, v in pairs(w.files) do files[k] = v end
  return World.new({ files = files })
end

t.test("cars.json: only stock cars and trucks, with prices and details", function()
  local d = json.decode(shipped())
  local models, trims, priced = 0, 0, 0
  for model, cfgs in pairs(d.gamePrices) do
    models = models + 1
    for config, e in pairs(cfgs) do
      trims = trims + 1
      if e.price then priced = priced + 1 end
      local ty = e.attrs and e.attrs.Type
      t.ok(ty == "Car" or ty == "Truck" or ty == "Heavy Machinery", model .. "/" .. config .. " is a " .. tostring(ty))
      t.eq(e.attrs.Source, "BeamNG - Official", model .. "/" .. config)
    end
  end
  t.eq(models, d.models); t.eq(trims, d.trims)
  t.ok(models >= 40 and priced >= 940, string.format("%d models, %d priced trims", models, priced))
  t.ok(d.modelNames.sunburst2, "with model names")
end)

t.test("a new install sells every stock car without an import; config.json stays small", function()
  local w = World.new({ files = fresh(F.files(F.twoRaces())) })   -- (a course, so /tg start runs; no import)
  local A, B = w:join("Alice"), w:join("Bob")
  t.ok(w:consoleHas("cars: the built-in catalogue (986 trims)"))
  local saved = w:serverConfig().dealer
  t.eq(saved.catalogue, "builtin"); t.eq(saved.useGamePrices, true)
  t.eq(next(saved.gamePrices), nil, "the catalogue isn't copied into config.json")
  t.ok(#w.files[CONFIG] < 60000, "config.json is " .. #w.files[CONFIG] .. " bytes")
  w:chat(A, "/tg class preset")
  t.ok(w:chatHas(A, "  jdm - Japanese cars (227 trims"), "the ready-made classes work on it")
  w:chat(A, "/tg budget 30000")
  w:chat(A, "/tg start")
  w:step(2.5)
  local s = B.client.im.textOf(WIN)
  t.match(s, "TODAY'S CARS: every car and truck")
  t.match(s, "%$25,500  Hirochi Sunburst [^\n]*\n")
  -- (a dealership line starts with its price; the $180,000 Scintillas are $54,000 even as Death Traps: not listed.
  -- The estimated $73,000 Off-Road one is $21,900 as a Death Trap, inside this $30,000 budget: listed)
  t.ok(not s:find("%$1%d%d,%d%d%d  Civetta Scintilla"), "over budget even as a Death Trap: not listed")
  t.match(s, "%$73,000  Civetta Scintilla Off%-Road")
  t.match(A.client.im.textOf(WIN), "Cars: the built%-in catalogue")
  w:assertClean()
end)

t.test("custom prices, classes and the budget are saved in config.json and survive a restart", function()
  local w = World.new({ files = fresh(F.files(F.twoRaces())) })
  local A = w:join("Alice")
  w:chat(A, "/tg setprice pigeon/base 4000")
  t.ok(w:chatHas(A, "now costs $4,000."))
  w:chat(A, "/tg class preset jdm")
  w:chat(A, "/tg class multiplier jdm 0.25")
  w:chat(A, "/tg budget 20000")
  w:chat(A, "/tg gameprices off")
  local w2 = restart(w)
  local A2 = w2:join("Alice")
  local d = w2:serverConfig().dealer
  t.eq(d.prices["pigeon/base"], 4000); t.eq(d.classes.jdm.multiplier, 0.25)
  t.eq(w2:serverConfig().economy.startingCash, 20000)
  t.eq(d.useGamePrices, false, "an admin's 'game prices off' isn't undone by the catalogue")
  w2:chat(A2, "/tg gameprices on")
  w2:chat(A2, "/tg class use jdm")
  w2:chat(A2, "/tg start")
  w2:step(2.5)
  t.match(A2.client.im.textOf(WIN), "%$6,375  Hirochi Sunburst", "$25,500 x 0.25, from the catalogue after a restart")
  w2:assertClean()
end)

t.test("an import replaces the catalogue and is kept; /tg importprices builtin goes back", function()
  local w = World.new({ files = fresh() })
  local A = w:join("Alice")
  w:chat(A, "/tg importprices")   -- the fake game's cars (tests/lib/world.lua MODELS)
  w:step(2)
  local d = w:serverConfig().dealer
  t.eq(d.catalogue, "import")
  t.ok(d.gamePrices.covet and d.gamePrices.covet.base_M.price == 4200, "the import is saved in config.json")
  t.eq(d.gamePrices.sunburst2, nil, "the catalogue's cars are replaced")
  local w2 = restart(w)
  local A2 = w2:join("Alice")
  t.ok(not w2:consoleHas("built-in catalogue"), "a server with its own import keeps it")
  t.eq(w2:serverConfig().dealer.gamePrices.covet.base_M.price, 4200)
  w2:chat(A2, "/tg importprices builtin")
  t.ok(w2:chatHas(A2, "Back to the built-in car catalogue (986 trims). Your classes and /tg setprice prices are kept."))
  t.eq(next(w2:serverConfig().dealer.gamePrices), nil, "nothing big in config.json again")
  local w3 = restart(w2)
  w3:join("Alice")
  t.ok(w3:consoleHas("cars: the built-in catalogue"))
  w:assertClean(); w2:assertClean(); w3:assertClean()
end)

t.test("a server that imported before the catalogue existed keeps its own cars", function()
  local old = F.config(F.twoRaces().events, { dealer = { useGamePrices = true, gamePrices = {
    covet = { base_M = { name = "Ibishu Covet base_M", price = 4200, attrs = { Type = "Car" } } } } } })
  local w = World.new({ files = fresh(F.files(old)) })
  w:join("Alice")
  t.ok(not w:consoleHas("built-in catalogue"))
  t.eq(w:serverConfig().dealer.gamePrices.covet.base_M.price, 4200)
  t.eq(w:serverConfig().dealer.gamePrices.pigeon, nil)
  w:assertClean()
end)

t.test("no cars.json: the dealer list is used, with a console note", function()
  local w = World.new()
  local A = w:join("Alice")
  t.ok(w:consoleHas("cars: cars.json is missing - the dealer list is used until /tg importprices"))
  w:chat(A, "/tg start")
  t.ok(w:buy(A, "covet", "base_M"), "the dealer list still sells")
  w:assertClean()
end)

t.test("the ~1,000-trim car list is only re-sent when it changes; the window keeps showing it", function()
  local w = World.new({ files = fresh(F.files(F.twoRaces())) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg budget 30000")
  w:chat(A, "/tg start")
  w:step(2.5)
  local sizes = {}
  setmetatable(w.queue, { __newindex = function(q, k, m)
    if m.ev == "tg_ui" and m.pid == B.pid then sizes[#sizes + 1] = #m.data end
    rawset(q, k, m)
  end })
  w:step(6.5)   -- three refreshes with nothing changed
  t.ok(#sizes >= 3, "refreshes: " .. #sizes)
  for _, n in ipairs(sizes) do t.ok(n < 20000, "an unchanged refresh is small: " .. n .. " bytes") end
  t.match(B.client.im.textOf(WIN), "%$25,500  Hirochi Sunburst", "the list is still shown")
  local before = #sizes
  w:chat(A, "/tg setprice sunburst2/base_EU_M 7000")   -- the list changed: it's sent again
  w:step(2.5)
  local big = 0
  for i = before + 1, #sizes do big = math.max(big, sizes[i]) end
  t.ok(big > 50000, "the changed list is sent: " .. big .. " bytes")
  t.match(B.client.im.textOf(WIN), "%$7,000  Hirochi Sunburst")
  w:assertClean()
end)

t.test("car condition pricing (career's formula): a beaten-up luxury car costs what a new cheap one does", function()
  local w = World.new({ files = fresh(F.files(F.twoRaces())) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg budget 12000")
  w:chat(A, "/tg start")
  w:chat(B, "/tg condition death trap")
  w:step(2.5)
  local a, b = A.client.im.textOf(WIN), B.client.im.textOf(WIN)
  t.match(a, "%$10,000  Ibishu Pigeon Base %(M%)\n", "a new Pigeon: $10,000")
  t.match(b, "%$10,200  ETK 800%-Series 844 150 %(M%)\n", "a Death Trap ETK 800: $34,000 x 0.3")
  t.match(a, "%$34,000  ETK 800%-Series 844 150 %(M%)  %- %$10,200 as a Death Trap", "Alice's list says what it'd take")
  t.ok(not b:find("Civetta Bolide", 1, true), "a supercar stays out of reach ($180,000 x 0.3 = $54,000): not even listed")
  t.ok(w:buy(B, "etk800", "844_150_M"), "Bob buys the Death Trap ETK")
  t.eq(w:state(B).cash, 12000 - 10200)
  w:step(2.5)
  t.match(B.client.im.textOf(WIN), "%- %$1,700 for yours", "fixing a problem: 5% of the ETK's $34,000 new price")
  w:assertClean()
end)
