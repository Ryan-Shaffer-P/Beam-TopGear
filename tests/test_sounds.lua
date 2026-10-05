-- Sound bites (0.8.5): who hears what and when, the per-player mute, the soundboard, the test command.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local json = require("json")
local p = F.p

local function has(list, ...)
  local want = { ... }
  for _, c in ipairs(list) do for _, w in ipairs(want) do if c == w then return true end end end
  return false
end
local function count(list, clip) local n = 0 for _, c in ipairs(list) do if c == clip then n = n + 1 end end return n end
local function clear(...) for _, pl in ipairs({ ... }) do pl.client.sounds = {} end end

local function oneRace()
  return F.config({
    { name = "Race One", type = "race", timeLimit = 120, start = p(500), checkpoints = { p(700), p(900) }, via = {} },
    { name = "Race Two", type = "race", timeLimit = 120, start = p(1500), checkpoints = { p(1700) }, via = {} },
  })
end

local function startAndBuy(w, A, B, C)
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M"); if C then w:buy(C, "miramar", "base_M") end
  for _, pl in ipairs({ A, B, C }) do w:chat(pl, "/tg ready") end
end

t.test("every configured clip ships in the client mod and the zip", function()
  local w = World.new()
  local clips = w:serverConfig().sounds.clips
  t.eq(#clips, 17)
  local zf = assert(io.open("Resources/Client/topgear.zip", "rb"))
  local zip = zf:read("*a")   -- a zip keeps its file names as plain text
  zf:close()
  for _, c in ipairs(clips) do
    local f = io.open("client/art/sound/topgear/" .. c .. ".ogg", "rb")
    t.ok(f, "missing client/art/sound/topgear/" .. c .. ".ogg"); f:close()
    t.ok(zip:find("art/sound/topgear/" .. c .. ".ogg", 1, true), c .. ".ogg is not in topgear.zip - rebuild the zip")
  end
  for key, ev in pairs(w:serverConfig().sounds.events) do
    for _, c in ipairs(ev.clips) do t.ok(has(clips, c), key .. " uses unknown clip " .. c) end
  end
end)

t.test("start, GO, finish, win: the right people hear the right clips", function()
  local w = World.new({ files = F.files(oneRace()) })
  local A, B, S = w:join("Alice"), w:join("Bob"), w:join("Spectator")
  w:chat(A, "/tg start")
  for _, pl in ipairs({ A, B, S }) do t.ok(has(w:heard(pl), "top-gear-theme-intro"), pl.name .. " hears the theme") end

  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:chat(A, "/tg next")   -- close the dealership; the spectator didn't buy a car, so they just watch
  w:driveAll({ { A, p(500), 45 }, { B, p(500), 35 } })
  clear(A, B, S)
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  for _, pl in ipairs({ A, B, S }) do t.ok(has(w:heard(pl), "speed-and-power", "poweeerr-jeremy-clarkson"), pl.name .. " hears GO") end

  clear(A, B, S)
  w:drive(A, p(900), 40)
  t.ok(has(w:heard(A), "happy-yes", "grunt-yes"), "Alice hears her finish")
  t.ok(not has(w:heard(B), "happy-yes", "grunt-yes"), "Bob doesn't hear Alice's finish")

  w:drive(B, p(900), 30)
  w:waitFor(function() return w:state(A).phase == "travel" end, 10, "results")
  t.eq(count(w:heard(A), "jeremy-clarkson-yeeeeeesss"), 1, "the winner hears YES")
  t.ok(has(w:heard(B), "yes-no-yes") and has(w:heard(S), "yes-no-yes"), "everyone else hears yes-no-yes")
  t.ok(not has(w:heard(A), "yes-no-yes"), "but not the winner")
  w:assertClean()
end)

t.test("DNF, tow, reset fine and a crash", function()
  local w = World.new({ files = F.files(oneRace()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  startAndBuy(w, A, B, C)

  clear(A, B, C)
  w:resetCar(B)   -- illegal reset: everyone hears about it
  for _, pl in ipairs({ A, B, C }) do t.ok(has(w:heard(pl), "oh-for-gods-sake", "jeremy-clarkson-oh-for-gods-sake"), pl.name .. " hears the reset fine") end

  -- a crash is heard nearby (Alice is 6 m from Bob) but not 400 m away (Carol drives off first)
  w:drive(C, p(400, 0), 40)
  clear(A, B, C)
  w:damage(B, 3000)
  w:step(2.5)
  t.ok(has(w:heard(B), "oh-cock-james-may", "clarkson-poop-shot-out"), "Bob hears his crash")
  t.ok(has(w:heard(A), "oh-cock-james-may", "clarkson-poop-shot-out"), "Alice, next to him, hears it")
  t.ok(not has(w:heard(C), "oh-cock-james-may", "clarkson-poop-shot-out"), "Carol, far away, doesn't")

  clear(A, B, C)
  w:chat(C, "/tg tow")
  t.ok(has(w:heard(C), "oh-no-anyway"), "Carol hears her tow")
  t.ok(not has(w:heard(A), "oh-no-anyway"), "only Carol")

  w:driveAll({ { A, p(500), 40 }, { B, p(500), 35 } })
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:drive(A, p(900), 40)
  clear(A, B, C)
  w:chat(A, "/tg next")   -- time called: Bob and Carol didn't finish
  w:step(3)
  t.ok(has(w:heard(B), "oh-no-anyway"), "Bob's DNF")
  w:assertClean()
end)

t.test("/tg sounds off mutes you (but not a sound test); /tg sounds on brings them back", function()
  local w = World.new({ files = F.files(oneRace()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(B, "/tg sounds off")
  t.ok(w:chatHas(B, "Sounds OFF for you."))
  w:chat(A, "/tg start")
  t.ok(has(w:heard(A), "top-gear-theme-intro"))
  t.eq(#w:heard(B), 0, "Bob hears nothing")

  w:chat(B, "/tg soundtest")
  t.ok(has(w:heard(B), "speed-and-power"), "a test plays even when muted")
  t.ok(w:chatHas(B, "Played 'speed-and-power' via game audio (Engine.Audio.playOnce)."))

  w:chat(B, "/tg sounds on")
  w:chat(A, "/tg play clarksooon")
  t.ok(has(w:heard(B), "clarksooon"))

  -- the Status tab button
  w:step(2.5)
  t.ok(B.client.im.hasButton("Sounds: ON - turn off"))
  B.client.im.click("Sounds: ON - turn off##sounds")
  w:step(2.5)
  t.ok(B.client.im.hasButton("Sounds: OFF - turn on"))
  w:assertClean()
end)

t.test("soundboard: admins play any clip for everyone, from chat or the Admin tab", function()
  local w2 = World.new({ files = F.files(oneRace()) })   -- Alice is the admin
  local A2, B2 = w2:join("Alice"), w2:join("Bob")
  w2:chat(B2, "/tg play clarksooon")
  t.ok(w2:chatHas(B2, "That's an admin command."))
  t.eq(#w2:heard(A2), 0)
  w2:chat(A2, "/tg play baby-jesus")
  t.ok(has(w2:heard(A2), "baby-jesus") and has(w2:heard(B2), "baby-jesus"), "everyone hears the soundboard")
  w2:chat(A2, "/tg play nonsense")
  t.ok(w2:chatHas(A2, "Usage: /tg play <clip>"))

  w2:chat(A2, "/tg menu")
  w2:step(2.5)
  t.ok(A2.client.im.hasButton("top-gear-theme-intro"), "soundboard button")
  A2.client.im.click("yes-no-yes##sb_yes-no-yes")
  w2:step(1)
  t.ok(has(w2:heard(B2), "yes-no-yes"))
  w2:assertClean()
end)

t.test("sound test falls back to another way of playing, and 'next' cycles through them", function()
  local w = World.new()
  local A = w:join("Alice")
  w:chat(A, "/tg diag")   -- nothing has played yet this session: says so, not an error
  t.ok(w:chatHas(A, "Sounds play via: no clip played yet this session"))
  A.client.audioBroken = true   -- this game has no Engine.Audio
  w:chat(A, "/tg soundtest happy-yes")
  t.eq(A.client.sounds[1].via, "js", "fell back to UI audio")
  t.eq(A.client.sounds[1].clip, "happy-yes")
  t.ok(w:chatHas(A, "Played 'happy-yes' via UI audio (executeJS). Not hearing it? /tg soundtest next tries the next way of playing sounds (3 of 3)."))

  A.client.audioBroken = false
  w:chat(A, "/tg soundtest next")   -- from method 3, wraps round to method 1
  t.ok(w:chatHas(A, "via game audio (Engine.Audio.playOnce)"))
  w:chat(A, "/tg soundtest next")
  t.ok(w:chatHas(A, "via game audio, relative path"))
  w:chat(A, "/tg soundtest nonsense")
  t.ok(w:chatHas(A, "No clip 'nonsense'."))

  w:chat(A, "/tg diag")
  t.ok(w:chatHas(A, "Sounds play via: game audio, relative path"))
  w:assertClean()
end)

t.test("sound config: moments and clips can be changed or switched off in config.json", function()
  local cfg = oneRace()
  cfg.sounds = { events = { start = { clips = { "baby-jesus" } }, resetFine = { to = "self" } } }
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  startAndBuy(w, A, B)
  t.ok(has(w:heard(B), "baby-jesus") and not has(w:heard(B), "top-gear-theme-intro"), "changed clip")
  clear(A, B)
  w:resetCar(B)
  t.ok(has(w:heard(B), "oh-for-gods-sake", "jeremy-clarkson-oh-for-gods-sake"), "Bob hears his own fine")
  t.eq(#w:heard(A), 0, "changed audience: only the driver it's about")
  t.eq(#w:serverConfig().sounds.events.go.clips, 2, "the other defaults are kept")

  local cfg2 = oneRace(); cfg2.sounds = { enabled = false }
  local w2 = World.new({ files = F.files(cfg2) })
  local A2 = w2:join("Alice")
  w2:chat(A2, "/tg start")
  t.eq(#w2:heard(A2), 0, "all sounds off")
  w:assertClean(); w2:assertClean()
end)

t.test("saved configs with the old champion clips move to the theme once (an admin's own choice kept)", function()
  local function load(clips)
    local cfg = oneRace(); cfg.sounds = World.new():serverConfig().sounds
    cfg.sounds.events.champion.clips = clips
    return World.new({ files = F.files(cfg) }):serverConfig().sounds.events.champion.clips
  end
  local c = load({ "clarksooon", "jeremy-clarkson-yeeeeeesss" })
  t.eq(#c, 1); t.eq(c[1], "top-gear-theme-intro")
  c = load({ "baby-jesus" })
  t.eq(#c, 1); t.eq(c[1], "baby-jesus", "a custom clip isn't touched")
end)

t.test("the workshop-intro clip plays for everyone when a workshop opens; saved configs move over once", function()
  local cfg = oneRace(); cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  startAndBuy(w, A, B)
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 35 } }); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  clear(A, B)
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 30 } })
  w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
  t.ok(has(w:heard(A), "workshop-intro") and has(w:heard(B), "workshop-intro"), "everyone hears it")
  -- a 0.9.12 config: the old default clip moves over, and the new clip joins the list
  local old = oneRace(); old.sounds = World.new():serverConfig().sounds
  for i = #old.sounds.clips, 1, -1 do if old.sounds.clips[i] == "workshop-intro" then table.remove(old.sounds.clips, i) end end
  old.sounds.events.workshop.clips = { "james-may-says-cheese" }
  local sc = World.new({ files = F.files(old) }):serverConfig().sounds
  t.eq(sc.events.workshop.clips[1], "workshop-intro")
  t.ok(has(sc.clips, "workshop-intro"), "in the clip list (the soundboard too)")
  w:assertClean()
end)
