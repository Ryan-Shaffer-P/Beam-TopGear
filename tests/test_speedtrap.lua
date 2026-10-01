-- Speed trap: one run through the trap (0.8.4); slow passes don't count.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function trapCourse(extra)
  local e = { name = "Speed Trap", type = "speedtrap", timeLimit = 300, start = p(500), trap = p(800), trapRadius = 10, minRunSpeed = 20, via = {} }
  for k, v in pairs(extra or {}) do e[k] = v end
  return F.config({ e })
end

local function toTheTrap(w, A, B)
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 40 } })
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
end

t.test("speed trap: one run each; a slow pass doesn't count; highest speed wins", function()
  local w = World.new({ files = F.files(trapCourse()) })
  local A, B = w:join("Alice"), w:join("Bob")
  toTheTrap(w, A, B)
  t.eq(w:state(A).target.label, "Speed trap")

  w:drive(A, p(1000), 15)   -- Alice creeps through first: under 20 m/s, doesn't count
  w:drive(A, p(500), 15)
  t.noLine(A.chat, "Through the trap")
  t.eq(w:state(A).phase, "event", "Alice still has her run")

  w:driveAll({ { A, p(1000), 45 }, { B, p(1000), 50 } })
  t.ok(w:chatHas(A, "Through the trap at 162.0 km/h"), "Alice's run")
  t.ok(w:chatHas(A, "Alice is done - 162.0 km/h"))
  t.ok(w:chatHas(B, "Bob is done - 180.0 km/h"))
  w:waitFor(function() return w:state(A).phase ~= "event" end, 10, "results")
  t.ok(w:chatHas(A, "1st  Bob - 180.0 km/h"), "Bob wins")
  t.ok(w:chatHas(A, "2nd  Alice - 162.0 km/h"))
  w:assertClean()
end)

t.test("speed trap: saved 3-run events become one run; the description is updated", function()
  local w = World.new({ files = F.files(trapCourse({ runs = 3, description = "Three runs through the trap. Highest speed wins." })) })
  local e = w:serverConfig().events[1]
  t.eq(e.runs, 1)
  t.eq(e.description, "One run through the trap. Highest speed wins.")
  w:assertClean()
end)

t.test("speed trap: a different runs value set in config.json is still respected", function()
  local w = World.new({ files = F.files(trapCourse({ runs = 2 })) })
  local A, B = w:join("Alice"), w:join("Bob")
  t.eq(w:serverConfig().events[1].runs, 2, "only the old default of 3 is migrated")
  toTheTrap(w, A, B)
  t.eq(w:state(A).target.label, "Speed trap (run 1/2)")
  w:driveAll({ { A, p(1000), 45 }, { B, p(1000), 50 } })
  t.ok(w:chatHas(A, "Run 1: 162.0 km/h"))
  t.eq(w:state(A).phase, "event", "a second run to go")
  w:assertClean()
end)
