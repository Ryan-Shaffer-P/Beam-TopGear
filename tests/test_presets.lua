-- 0.9.5: with no class picked, a full import sells every imported car and truck (not just the dealer list);
-- ready-made classes (/tg class preset). Test cars: tests/lib/world.lua MODELS + a Sunburst that isn't on the
-- default dealer list.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local json = require("json")

local WIN = "Top Gear Challenge"
local function models()
  local m = {}
  for k, v in pairs(World.MODELS) do m[k] = v end
  m.sunburst2 = { brand = "Hirochi", name = "Sunburst", configs = { base_M = 5500, sport_M = 9000 },
                  info = { Country = "Japan", ["Body Style"] = "Sedan", Type = "Car", Years = { min = 2005, max = 2012 } },
                  trims = { base_M = { ["Config Type"] = "Factory", Transmission = "Manual" },
                            sport_M = { ["Config Type"] = "Factory", Transmission = "Manual" } } }
  return m
end
local function world(cmd)
  local w = World.new({ files = F.files(F.twoRaces()), models = models() })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, cmd or "/tg importprices")
  w:step(2)
  return w, A, B
end

t.test("no class after a full import: every imported car and truck is for sale, not just the dealer list", function()
  local w, A, B = world()
  t.ok(w:serverConfig().dealer.importedAll, "remembered")
  w:chat(A, "/tg class list")
  t.ok(w:chatHas(A, "Next challenge: no class - every imported car and truck."))
  w:chat(A, "/tg start")
  w:step(2.5)
  w:showModel(B, "Hirochi Sunburst")
  local s = B.client.im.textOf(WIN)
  t.match(s, "Today's cars: every car and truck")
  t.match(s, "Hirochi Sunburst %(2%)", "a model that isn't on the dealer list")
  t.match(s, "%$5,500  Hirochi Sunburst base_M")
  w:chat(B, "/tg dealer")
  t.ok(w:chatHas(B, "Every imported car and truck is for sale."))
  t.ok(w:chatHas(B, "Hirochi Sunburst (sunburst2) - 2 trims, $5,500 to $9,000"))
  t.ok(w:buy(B, "sunburst2", "base_M"), "it sells")
  t.eq(w:state(B).cash, 10000 - 5500, "at its game price")
  w:assertClean()
end)

t.test("an import of named models only keeps the dealer list", function()
  local w, A, B = world("/tg importprices covet sunburst2")
  t.eq(w:serverConfig().dealer.importedAll, nil)
  w:chat(A, "/tg class list")
  t.ok(w:chatHas(A, "Next challenge: no class - the normal dealer list."))
  w:assertClean()
end)

t.test("a config imported in full by an older version sells every car too", function()
  local cfg = F.config(F.twoRaces().events, { dealer = { useGamePrices = true, gamePrices = {
    covet = { base_M = { name = "Ibishu Covet base_M", price = 4200, attrs = { Type = "Car" } } },
    sunburst2 = { base_M = { name = "Hirochi Sunburst base_M", price = 5500, attrs = { Type = "Car" } } } } } })
  local w = World.new({ files = F.files(cfg), models = models() })
  local A = w:join("Alice")
  t.ok(w:serverConfig().dealer.importedAll, "a model off the dealer list means it was a full import")
  w:chat(A, "/tg start")
  t.ok(w:buy(A, "sunburst2", "base_M"))
  w:assertClean()
end)

t.test("ready-made classes: list them, make one by name or with a button, use it", function()
  local w, A, B = world()
  w:chat(A, "/tg class preset")
  t.ok(w:chatHas(A, "  jdm - Japanese cars (8 trims, $3,100 to $14,000)"), "covet x3, pessima x2, miramar, sunburst x2")
  t.ok(w:chatHas(A, "  american - American cars and trucks (2 trims, $6,800 to $12,500)"))
  w:chat(A, "/tg class preset jdm")
  t.ok(w:chatHas(A, "Made class jdm (Japanese cars): Country: Japan; Type: Car"))
  w:chat(A, "/tg class preset jdm")
  t.ok(w:chatHas(A, "There's already a class called jdm"))
  w:chat(A, "/tg class preset classics oldies")   -- under another name
  t.ok(w:chatHas(A, "Made class oldies (Classics (up to 1979)): Years up to 1979; Type: Car - 1 trim, $3,100 to $3,100."))
  -- the Admin tab
  w:chat(A, "/tg menu"); w:step(2.5)
  local s = A.client.im.textOf(WIN)
  t.match(s, "Ready%-made classes")
  t.match(s, "american %- American cars and trucks %(2 trims%)")
  A.client.im.click("Make##clspm_american")
  w:step(2.5)
  t.ok(w:serverConfig().dealer.classes.american, "made from the button")
  A.client.im.click("Use##clspu_american")
  w:step(1)
  w:chat(A, "/tg start")
  t.ok(w:chatHas(B, "Today's cars: american"))
  t.eq(w:buy(B, "sunburst2", "base_M"), nil)
  t.ok(w:chatHas(B, "not in today's class (american): Country is Japan"))
  t.ok(w:buy(B, "pickup", "d15_M"))
  w:assertClean()
end)

t.test("ready-made classes on the real game data: none is empty", function()
  local f = assert(io.open("tests/data/game-cars.json", "rb"))
  local d = json.decode(f:read("*a"))
  f:close()
  local cfg = F.config(F.twoRaces().events, { dealer = { useGamePrices = true, gamePrices = d.gamePrices, modelNames = d.modelNames } })
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg class preset")
  local lines = {}
  for _, l in ipairs(A.chat) do
    local key, n = l:match("   (%w+) %- .-%((%d+) trims?,")
    if key then lines[#lines + 1] = key .. " " .. n end
    t.ok(not l:find("%(no cars%)"), "empty: " .. l)
  end
  print("        " .. table.concat(lines, ", "))
  t.eq(#lines, 18)
  w:chat(A, "/tg start")   -- a $10,000 budget: a Sunburst ($25,500) only as a Death Trap; a Bolide ($180,000) never
  w:step(2.5)
  w:showModel(A, "Hirochi Sunburst")
  local txt = A.client.im.textOf(WIN)
  t.match(txt, "Hirochi Sunburst", "Ryan's missing Sunburst is on sale with no class")
  t.match(txt, "%$25,500  Hirochi Sunburst [^\n]*  %- %$7,700 as a Death Trap", "x0.3 = $7,650 -> $7,700")
  t.ok(not txt:find("%$[%d,]+  Civetta Bolide"), "over budget even as a Death Trap ($54,000): not in the dealership")
  local buy = {}
  for _, it in ipairs(A.client.im.items(WIN)) do if it.kind == "button" then buy[it.id] = true end end
  t.ok(buy["Buy##pigeon_base_M"] or next(buy), "sanity: buttons recorded")
  t.ok(not buy["Buy##sunburst2_base_EU_M"], "no Buy button until the condition makes it affordable")
  w:chat(A, "/tg dealer bolide")
  t.ok(w:chatHas(A, "No model 'bolide' for sale."), "nor in /tg dealer")
  w:dropWarning("none of today's cars were found in this game")   -- (harness: real catalogue, 8 fake models)
  w:assertClean()
end)
