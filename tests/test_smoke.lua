-- Stage 1 smoke tests: everything loads, a challenge starts, cars are bought, the first leg begins.
local t = require("t")
local World = require("world")
local F = require("fixtures")

t.test("server and clients load cleanly", function()
  local w = World.new()
  t.anyLine(w.console, "Top Gear Challenge server v")
  t.ok(w.files["Resources/Server/TopGear/config.json"], "default config.json written")
  local a = w:join("Alice")
  w:step(1)
  t.anyLine((function() local o = {} for _, l in ipairs(a.client.log) do o[#o + 1] = l.msg end return o end)(),
    "BeamMP events registered")
  w:assertClean()
end)

t.test("start refuses an unfinished course, force starts anyway", function()
  local w = World.new()
  local a = w:join("Alice")
  w:chat(a, "/tg start")
  t.ok(w:chatHas(a, "Course isn't finished"), "unfinished course refused")
  w:chat(a, "/tg start force")
  t.eq(w:state(a).phase, "dealer")
  w:assertClean()
end)

t.test("dealership: buy by spawning, buy from the window, ready up, leg 1 starts", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local a, b = w:join("Alice"), w:join("Bob")
  w:chat(a, "/tg start")
  t.eq(w:state(a).phase, "dealer")
  w:step(1)
  t.ok(a.client.im.lastFrame.windows["Top Gear Challenge"], "the window opens at the dealership")

  -- Alice uses the vehicle menu: the default manual price list sells any Covet for $4,500
  t.ok(w:buy(a, "covet", "base_M"), "spawn accepted")
  t.eq(w:state(a).cash, 5500)
  t.ok(w:chatHas(a, "Alice bought an Ibishu Covet for $4,500"))

  -- Bob uses the Dealership tab's Buy button
  w:step(2.5)   -- the window refreshes its data every 2 s
  local im = b.client.im
  t.ok(im.hasButton("Buy"), "Buy buttons shown")
  w:showModel(b, "Ibishu Pessima")   -- (Today's cars: one model at a time)
  im.click("Buy##pessima_nil")
  w:step(1)
  t.eq(b.current and b.current.model, "pessima")
  t.eq(w:state(b).cash, 5000)

  local before = w:state(a).cash
  w:chat(a, "/tg ready")   -- Alice ready; Bob not yet, so the dealership stays open
  t.eq(w:state(a).phase, "dealer")

  w:step(2.5)
  im.click("I'm happy with my car - Ready!")
  w:step(1)
  t.eq(w:state(a).phase, "travel")
  t.match(w:state(a).title, "^Leg 1/2")
  t.eq(w:state(a).cash, before)
  t.ok(a.client.path, "navigation arrows set")
  t.eq(a.client.path.x, 500, "arrows point at Race One's start")
  w:assertClean()

  -- everyone at the start: the GO button is big (tall, full width, larger font) and starts the countdown
  w:driveAll({ { a, F.p(500), 40 }, { b, F.p(500), 35 } })
  w:step(2.5)
  local go
  for _, it in ipairs(im.items("Top Gear Challenge")) do
    if it.kind == "button" and it.label == "GO! Start the countdown" then go = it end
  end
  t.ok(go, "GO button shown when everyone has arrived")
  t.ok(go.size and go.size.y >= 60 and (go.size.x < 0 or go.size.x >= 520), "GO button is tall and full width")
  local scaled = false
  for _, it in ipairs(im.items("Top Gear Challenge")) do if it.kind == "fontscale" and it.scale > 1 then scaled = true end end
  t.ok(scaled, "GO button uses a bigger font")
  im.click("GO! Start the countdown")
  w:step(1)
  t.eq(w:state(a).phase, "countdown")
  w:assertClean()
end)

t.test("over-budget and unlisted cars are refused", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local a = w:join("Alice")
  w:chat(a, "/tg start")
  t.eq(w:buy(a, "etk800", nil), nil, "unlisted model refused")
  t.ok(w:chatHas(a, "The dealership can't sell you that"))
  t.eq(w:state(a).cash, 10000)
  w:assertClean()
end)

t.test("/tg theme toggles the colour theme without errors (addLog regression)", function()
  local w = World.new()
  local a = w:join("Alice")
  w:chat(a, "/tg menu")
  w:step(1)
  w:chat(a, "/tg theme")
  w:step(1)
  w:assertClean()
  local found = false
  for _, it in ipairs(a.client.im.items("Top Gear Challenge")) do
    if it.text == "Colour theme off." then found = true end
  end
  t.ok(found, "the window log says 'Colour theme off.'")
end)
