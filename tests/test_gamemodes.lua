-- Game modes (0.9.31, Ryan): switches in the Start tab and the Admin tab - Free Repair, No faults, No quirks
-- (Turbo Mode: planned). Admins switch them; everyone sees which are on.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local WIN = "Top Gear Challenge"
local function text(pl) return pl.client.im.textOf(WIN) end

t.test("the switches: Start tab and the Admin tab's Game modes box, each with its (?) help; everyone sees what's on", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob")   -- (Alice is the admin)
  w:chat(A, "/tg menu"); w:chat(B, "/tg menu"); w:step(2.5)
  for _, label in ipairs({ "Free Repair: OFF", "Turbo Mode: coming next", "No faults: OFF", "No quirks: OFF" }) do
    t.ok(A.client.im.hasButton(label), label)
  end
  t.ok(text(A):find("Every repair is free", 1, true), "the (?) explains it")
  A.client.im.click("Free Repair: OFF##mode_freeRepair"); w:step(2.5)
  t.ok(w:chatHas(B, "Game mode: Free Repair is ON."))
  t.eq(w:serverConfig().modes.freeRepair, true, "kept in config.json")
  t.ok(A.client.im.hasButton("Free Repair: ON"))
  t.ok(text(B):find("Game modes: Free Repair", 1, true), "Bob sees it")
  w:chat(B, "/tg mode freerepair off"); t.ok(w:chatHas(B, "That's an admin command."))
  A.client.im.click("Turbo Mode: coming next##mode_turbo"); w:step(0.5)
  t.noLine(B.chat, "Turbo Mode is ON", "Turbo isn't switchable yet")
  w:chat(A, "/tg mode turbo on"); t.ok(w:chatHas(A, "Turbo Mode isn't built yet"))
  w:assertClean()
end)

t.test("Free Repair: tows, respawns and workshop repairs cost nothing; a tow in an event still disqualifies", function()
  local cfg = F.twoRaces(); cfg.modes = { freeRepair = true }; cfg.workshopEvery = 1
  local w = World.new({ files = F.files(cfg) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start"); w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready"); w:step(1)
  local cash = w:state(A).cash
  w:damage(A, 3000); w:step(2.5)
  w:chat(A, "/tg respawn"); w:step(2.5)
  t.eq(w:state(A).cash, cash, "a free respawn")
  w:driveAll({ { A, p(500), 40 }, { B, p(500, 3), 30 } }); w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:waitFor(function() return w:sawMessage(A, "GO!") end, 10, "the start")
  cash = w:state(A).cash
  w:damage(A, 4000); w:step(2.5)
  w:chat(A, "/tg tow"); w:step(3)
  t.ok(w:chatHas(B, "Alice calls the tow truck (free - Free Repair mode"), "the tow is free")
  t.eq(w:state(A).cash, cash, "nothing charged")
  w:drive(B, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "workshop" end, 15, "the workshop")
  t.ok(w:chatHas(B, "Alice"), "results")
  local dsq = false
  for _, l in ipairs(B.chat) do if l:find("Alice", 1, true) and l:find("DSQ", 1, true) then dsq = true end end
  t.ok(dsq, "the tow still disqualified her from the event")
  w:damage(B, 2000); w:step(2.5)
  local bc = w:state(B).cash
  w:chat(B, "/tg repair")
  t.ok(w:chatHas(A, "Bob had their Ibishu Pessima (1988) repaired (free)."))
  t.eq(w:state(B).cash, bc, "a free workshop repair")
  w:assertClean()
end)

t.test("No faults: every car is New - no condition to pick, no problems; can't be switched once the challenge has started", function()
  local cfg = F.twoRaces(); cfg.modes = { noFaults = true }
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  w:chat(A, "/tg condition death trap")
  t.ok(w:chatHas(A, "switched off"), "no condition to pick")
  w:buy(A, "covet", "base_M"); w:step(3)
  t.eq((w:ui(A).faults or {}).count, nil, "no problems")
  w:chat(A, "/tg mode nofaults off")
  t.ok(w:chatHas(A, "No faults can only be changed before the challenge starts"))
  w:chat(A, "/tg mode freerepair on")
  t.ok(w:chatHas(A, "Game mode: Free Repair is ON."), "Free Repair can change any time")
  w:assertClean()
end)

t.test("No quirks: a Death Trap comes with none", function()
  local cfg = F.twoRaces(); cfg.quirks = { enabled = true }; cfg.modes = { noQuirks = true }
  local w = World.new({ files = F.files(cfg) })
  local A = w:join("Alice")
  w:chat(A, "/tg start"); w:chat(A, "/tg condition death trap"); w:buy(A, "covet", "base_M"); w:step(2.5)
  t.eq((w:ui(A).me or {}).quirks, nil, "no quirks")
  t.ok(#((w:ui(A).faults or {}).levels or {}) > 0, "faults are still on")
  w:assertClean()
end)
