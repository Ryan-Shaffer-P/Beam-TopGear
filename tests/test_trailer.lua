-- Trailer delivery: spawning, hitching, and the 70% load / 30% speed scoring (server 0.8.3).
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function trailerCourse(extra)
  return F.config({
    { name = "Trailer Delivery", type = "trailer", timeLimit = 300, start = p(500), checkpoints = { p(700), p(900) }, via = {} },
  }, extra)
end

-- three drivers reach the start, get a trailer each, hitch up and are counted down
local function lineUp(w, A, B, C)
  for _, pl in ipairs({ A, B, C }) do
    local carModel = ({ Alice = "covet", Bob = "pessima", Carol = "miramar" })[pl.name]
    w:buy(pl, carModel, "base_M")
  end
  for _, pl in ipairs({ A, B, C }) do w:chat(pl, "/tg ready") end
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 40 }, { C, p(500), 40 } })
  w:step(6)   -- trailers (and cargo) spawn behind each car and report in
  for _, pl in ipairs({ A, B, C }) do w:hitch(pl) end
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
end

-- the driver's line in the event's RESULTS block
local function resultLine(pl, who)
  local inResults = false
  for _, l in ipairs(pl.chat) do
    if l:find("===== RESULTS:", 1, true) then inResults = true
    elseif inResults and l:find("  " .. who .. " - ", 1, true) then return l end
  end
  error("no result line for " .. who .. ". Chat:\n  " .. table.concat(pl.chat, "\n  "))
end

t.test("trailer (loose cones): 70% load + 30% speed decides it, not time + 20 s per cone", function()
  local w = World.new({ files = F.files(trailerCourse()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  w:chat(A, "/tg start")
  lineUp(w, A, B, C)
  t.ok(w:chatHas(A, "Trailer OK, 5 cargo item(s) spawned, 5 on the deck."), "cones landed on the deck")

  w:dropCargo(A, 1)   -- Alice loses a cone at the start and then drives flat out
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 30 }, { C, p(900), 18 } })
  w:waitFor(function() return w:state(A).phase ~= "event" end, 10, "results")

  -- Alice: 4/5 = 80% -> 56.0, fastest -> 30.0, = 86.0
  -- Bob:   5/5 -> 70.0, speed 30 x 10/13.3 = ~22.5, = ~92.5
  -- Carol: 5/5 -> 70.0, speed 30 x 10/22.2 = ~13.5, = ~83.5
  -- (old rule: Alice 10 s + 20 s = 30 s would have finished behind Carol's ~22 s)
  t.match(resultLine(A, "Alice"), "4/5 cargo: load 56%.0 %+ speed 30%.0 = 86%.0 pts")
  t.match(resultLine(A, "Bob"), "%] 1st .*5/5 cargo: load 70%.0 %+ speed 2%d%.%d")
  t.match(resultLine(A, "Alice"), "%] 2nd ")
  t.match(resultLine(A, "Carol"), "%] 3rd .*5/5 cargo: load 70%.0 %+ speed 1%d%.%d")
  local left = 0
  for _ in pairs(A.vehicles) do left = left + 1 end
  t.eq(left, 1, "trailer and cones cleaned up, only the car left")
  w:assertClean()
end)

t.test("trailer (prebuilt load): the measured load share is the 70%", function()
  local setup = { model = "tsfb", parts = { tsfb_load = "tsfb_load_crates", tsfb_straps = "" }, vars = {},
                  loadParts = { "tsfb_load_crates" }, loadSlot = "tsfb_load", loadPart = "tsfb_load_crates" }
  local w = World.new({ files = F.files(trailerCourse({ eventTypes = { trailer = { setup = setup } } })) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  w:chat(A, "/tg start")
  lineUp(w, A, B, C)
  t.ok(w:chatHas(A, "Trailer OK with its built-in load - 100% of the load on the bed."), "load measured at the start")

  w:setLoad(A, 0.6)   -- 40% of Alice's load slides off as she launches
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 25 }, { C, p(900), 20 } })
  w:waitFor(function() return w:state(A).phase ~= "event" end, 10, "results")

  -- Alice: 60% -> 42.0 + fastest 30.0 = 72.0 ; Bob: 70 + 30 x 10/16 = ~88.8 ; Carol: 70 + 15 = ~85
  t.match(resultLine(A, "Alice"), "%] 3rd .*60%% of the load: load 42%.0 %+ speed 30%.0 = 72%.0 pts")
  t.match(resultLine(A, "Bob"), "%] 1st .*100%% of the load: load 70%.0")
  t.match(resultLine(A, "Carol"), "%] 2nd .*100%% of the load: load 70%.0")
  w:assertClean()
end)

t.test("trailer weights come from config and are scaled to 100", function()
  -- 1 : 1 weights -> 50 / 50
  local w = World.new({ files = F.files(trailerCourse({ eventTypes = { trailer = { loadWeight = 1, speedWeight = 1 } } })) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  w:chat(A, "/tg start")
  lineUp(w, A, B, C)
  w:dropCargo(A, 1)
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 30 }, { C, p(900), 18 } })
  w:waitFor(function() return w:state(A).phase ~= "event" end, 10, "results")
  t.match(resultLine(A, "Alice"), "4/5 cargo: load 40%.0 %+ speed 50%.0 = 90%.0 pts")
  w:assertClean()
end)

t.test("saved trailer events get the new description; custom ones are left alone", function()
  local cfg = trailerCourse()
  cfg.events[1].description = "Hitch up and deliver the load. Lost cargo costs 20 seconds a piece."
  cfg.events[2] = { name = "Custom", type = "trailer", description = "My own words.", start = p(1500), checkpoints = { p(1600) }, via = {} }
  local w = World.new({ files = F.files(cfg) })
  local saved = w:serverConfig()
  t.eq(saved.events[1].description, "Hitch up and deliver the load. 70 points for the load you keep, 30 for speed.")
  t.eq(saved.events[2].description, "My own words.")
  t.eq(saved.eventTypes.trailer.loadWeight, 0.7, "new weights added to an existing config")
  w:assertClean()
end)

t.test("a trailer with no load (a caravan): saved as is, delivered in one piece - the 70 is how intact it arrives", function()
  -- saving: sit in a trailer with nothing in a load slot and press Set trailer (/tg trailersave)
  local w0 = World.new({ files = F.files(trailerCourse()) })
  local A0 = w0:join("Alice")
  w0:buy(A0, "tsfb", "base"); w0:step(1)
  w0:chat(A0, "/tg trailersave"); w0:step(1)
  t.ok(w0:chatHas(A0, "Saved your tsfb - it has no load, so it's delivered in one piece"), "saved, not refused")
  t.eq(w0:serverConfig().eventTypes.trailer.setup.mode, "damage")

  local setup = { model = "tsfb", mode = "damage", parts = { tsfb_straps = "" }, vars = {}, loadParts = {} }
  local w = World.new({ files = F.files(trailerCourse({ eventTypes = { trailer = { setup = setup } } })) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  w:chat(A, "/tg start")
  lineUp(w, A, B, C)
  t.ok(w:chatHas(A, "Trailer OK - deliver it in one piece: no load, so it's scored on how undamaged it arrives (100% intact now)."))
  for _, v in pairs(A.vehicles) do if v.model == "tsfb" then v.damage = 4000 end end   -- Alice clips a kerb with it
  w:step(2.5)
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 25 }, { C, p(900), 20 } })
  w:waitFor(function() return w:state(A).phase ~= "event" end, 10, "results")
  -- Alice: 1 - 4000/10000 = 60% intact -> 42.0 + fastest 30.0 = 72.0; Bob and Carol: 70 + their speed share
  t.match(resultLine(A, "Alice"), "trailer 60%% intact: load 42%.0 %+ speed 30%.0 = 72%.0 pts")
  t.match(resultLine(A, "Bob"), "%] 1st .*trailer 100%% intact: load 70%.0")
  t.ok(w:chatHas(A, "Alice crosses the line! ") and w:chatHas(A, "with the trailer 60% intact"))
  w:assertClean()
end)
