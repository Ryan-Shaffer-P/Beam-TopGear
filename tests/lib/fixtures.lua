-- Test courses. Everything sits along the x axis so tests can drive straight between points.
local json = require("json")
local F = {}

local function p(x, y) return { x = x, y = y or 0, z = 0 } end
F.p = p

-- config.json contents for a course; `events` replaces the default pool (arrays aren't merged)
function F.config(events, extra)
  local cfg = {
    admins = { "Alice" },
    events = events,
    finale = { name = "The Test Track", pos = p(5000), radius = 25, timeLimit = 1200, via = {} },
    workshopEvery = 2,
    -- (tests of how each problem works use its listed strength at every condition; test_faults checks the scaling)
    faults = { severity = { 1, 1, 1, 1 } },
    -- (the dealership closes the moment everyone's ready, as before 0.9.13; test_quickstart checks the 5 s countdown)
    defaults = { readyCountdown = 0,
      soloGo = false, watchRunner = false },   -- (time trial drivers start one after another by themselves; test_timetrial checks GO per driver)
  }
  for k, v in pairs(extra or {}) do cfg[k] = v end
  return cfg
end

-- two destination races: 1 at x=500 (finish 900), 2 at x=1500 (finish 1900)
function F.twoRaces()
  return F.config({
    { name = "Race One", type = "race", timeLimit = 300, start = p(500), checkpoints = { p(700), p(900) }, via = {} },
    { name = "Race Two", type = "race", timeLimit = 300, start = p(1500), checkpoints = { p(1700), p(1900) }, via = {} },
  })
end

-- World.new{ files = F.files(cfg) }
function F.files(cfg)
  return { ["Resources/Server/TopGear/config.json"] = json.encode(cfg) }
end

return F
