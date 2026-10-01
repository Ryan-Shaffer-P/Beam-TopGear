--[[
  TOP GEAR CHALLENGE - BeamMP server plugin (v0.1)
  ------------------------------------------------
  Put this file at:  <BeamMP server>/Resources/Server/TopGear/main.lua
  Client mod:        <BeamMP server>/Resources/Client/topgear.zip
  Settings + course: config.json next to this file (written with defaults on first run).
  In game, type /tg help.
]]

local SERVER_VERSION = "0.8.4"
local PLUGIN_DIR  = "Resources/Server/TopGear/"
local CONFIG_PATH = PLUGIN_DIR .. "config.json"
local COURSES_PATH = PLUGIN_DIR .. "courses.json"   -- saved course library
local TICK_MS     = 250   -- position polling interval
local PUSH_EVERY  = 8     -- ticks between HUD refreshes (8 x 250 ms = 2 s)

---------------------------------------------------------------------------
-- Default configuration (copied to config.json on first run, then edit that)
---------------------------------------------------------------------------
local DEFAULT_CONFIG = {
  admins = {},                 -- names allowed to use admin commands. EMPTY = EVERYONE (testing only)
  adminExtraVehicles = true,   -- admins may spawn extra non-scoring vehicles (AI traffic, parked obstacles)
  clearVehiclesOnStart = true, -- delete everyone's vehicles when /tg start runs
  debugSpawns = false,         -- print raw spawn data to the server console

  economy = {
    startingCash        = 10000,
    prizes              = { 6000, 3000, 1500, 500 }, -- cash by finishing position
    arrivalBonus        = { 500, 250 },             -- cash for 1st/2nd to arrive at each event
    repairBaseFee       = 250,
    repairCostPerDamage = 0.5,   -- $ per unit of BeamNG damage (calibrate with /tg status)
    repairCap           = 6000,
    repairMinDamage     = 50,
    towFee              = 2000,  -- /tg tow (or respawning a lost car): full repair + delivery, DSQ from a running event
    resetPenalty        = 1000,  -- if someone manages an illegal reset (R / Insert) anyway
    respawnFee          = 2000,  -- /tg respawn outside the dealership/workshop (a fresh car on the spot)
    unstickCooldown     = 15,    -- seconds between free /tg unstick uses
    unstickMaxSpeed     = 3,     -- m/s: unstick only works when (nearly) stopped
  },

  scoring = {
    placementPoints          = { 10, 6, 3, 1 },
    drivabilityMaxPoints     = 10,     -- awarded at the finale for an undamaged car
    damageForZeroDrivability = 20000,  -- damage at which drivability hits 0
    recoveryPenaltyPoints    = 2,      -- per illegal reset (tows don't cost points)
  },

  faults = {
    enabled = true,
    maxPerCar = 3,
    fixMultiplier = 1.5,          -- workshop fix costs this x the payout
    inspectionPenaltyPoints = 1,  -- drivability points lost per unfixed fault at the finale
    list = {                      -- factor = severity (see README)
      { id = "tires",     name = "Worn, underinflated tires",     payout = 2400, factor = 0.3 },   -- pressure = 30% of normal
      { id = "alignment", name = "Knocked-out wheel alignment",   payout = 2100, factor = 1.4 },   -- front toe to its limit + rear 40%
      { id = "bumpers",   name = "Missing bumpers",               payout = 1500 },
      { id = "engine",    name = "Tired engine (about -20% power)",   payout = 6000, factor = 0.8 },
      { id = "brakes",    name = "Worn brakes (about -40% braking)",  payout = 3600, factor = 0.6 },
    },
  },

  workshop = { minutes = 10, laborFee = 300, partsMarkup = 1.0, resaleRate = 0.5,
               flatPartPrice = 500,     -- charged per changed part when the game can't tell us its price
               radius = 30,             -- how close to a workshop spot (gas station) counts as "in the workshop"
               creditLimit = 1500 },    -- workshop/dealership spending may take a driver this far into the red
  workshopEvery = 2,              -- a workshop after every Nth event (never after the last one); 0 = none

  defaults = {
    startRadius = 20, cpRadius = 12, viaRadius = 25,
    countdown = 5, falseStartPenalty = 5, eventTimeLimit = 600,
  },

  dealer = {
    useGamePrices = false,  -- true after /tg importprices: every trim costs its BeamNG value
    gamePrices = {},        -- filled by /tg importprices: { model = { configKey = { name, price } } }
    strictConfigs = false,  -- (manual prices only) true = only exact model+config entries are sold
    cars = {                -- prices are the challenge's, not BeamNG's. Tune freely.
      { model = "miramar",  name = "Ibishu Miramar",        price = 3500 },
      { model = "covet",    name = "Ibishu Covet",          price = 4500 },
      { model = "pessima",  name = "Ibishu Pessima (1988)", price = 5000 },
      { model = "legran",   name = "Bruckell LeGran",       price = 5500 },
      { model = "wendover", name = "Soliad Wendover",       price = 5500 },
      { model = "hopper",   name = "Ibishu Hopper",         price = 6000 },
      { model = "fullsize", name = "Gavril Grand Marshal",  price = 6500 },
      { model = "burnside", name = "Burnside Special",      price = 7000 },
      { model = "pickup",   name = "Gavril D-Series",       price = 7500 },
      { model = "etki",     name = "ETK I-Series",          price = 8000 },
      { model = "barstow",  name = "Gavril Barstow",        price = 8500 },
      { model = "moonhawk", name = "Bruckell Moonhawk",     price = 9000 },
    },
  },

  -- The course is a pool of events; the session runs the ones with enabled ~= false, in order.
  -- type: race | circuit | speedtrap | parking | fragile | economy | slalom | trailer
  -- solo: true = time trial mode (one at a time), false = race mode (everyone at once), nil = the type's default
  events = {
    { name = "The Drag Race",  type = "race", timeLimit = 180,
      description = "Flat out down the straight. First across the line wins.", via = {}, checkpoints = {} },
    { name = "The Hill Climb", type = "race", solo = true, timeLimit = 300,
      description = "Up the mountain, one at a time. Fastest run wins.", via = {}, checkpoints = {} },
    { name = "The Circuit", type = "circuit", laps = 3, timeLimit = 900, enabled = false,
      description = "Round and round. First to complete the laps wins.", via = {}, checkpoints = {} },
    { name = "Rush Hour",      type = "race", timeLimit = 900,
      description = "Across downtown through the traffic. Every checkpoint, in order.", via = {}, checkpoints = {} },
    { name = "The Speed Trap", type = "speedtrap", runs = 1, trapRadius = 10, minRunSpeed = 20, timeLimit = 600,
      description = "One run through the trap. Highest speed wins.", via = {} },
    { name = "Precision Parking", type = "parking", timeLimit = 180, enabled = false,
      description = "Park in every bay, in order. Precise, quick and without a scratch wins.", via = {}, bays = {} },
    { name = "Fragile Delivery", type = "fragile", timeLimit = 600, enabled = false,
      description = "Get there fast - but every bit of damage costs you time. Don't spill the drink.", via = {}, checkpoints = {} },
    { name = "The Economy Run", type = "economy", timeLimit = 900, enabled = false,
      description = "Least fuel used wins. Finish inside the time limit.", via = {}, checkpoints = {} },
    { name = "The Slalom", type = "slalom", timeLimit = 240, enabled = false,
      description = "Through every gate. Each one you miss costs 5 seconds.", via = {}, checkpoints = {} },
    { name = "Trailer Delivery", type = "trailer", timeLimit = 900, enabled = false,
      description = "Hitch up and deliver the load. 70 points for the load you keep, 30 for speed.", via = {}, checkpoints = {} },
  },

  eventTypes = {   -- tuning for each event type
    parking = { bayRadius = 5, stillSeconds = 1.5, stillSpeed = 0.3, distWeight = 10, angleWeight = 0.5, timeWeight = 0.1,
                damageWeight = 0.01, missedBayPenalty = 50 },
    fragile = { damageWeight = 0.01 },   -- seconds added per point of damage picked up
    slalom  = { gateRadius = 4, gatePenalty = 5 },
    trailer = { setup = nil,   -- saved with /tg trailersave: a prebuilt trailer whose load is part of it (replaces the cones)
                loadWeight = 0.7, speedWeight = 0.3,   -- score out of 100: share of the load kept + speed vs the fastest
                trailerModel = "tsfb", cargoModel = "cones", cargoCount = 5,
                cargoRadius = 5, hitchRadius = 15, trailerBack = 7, cargoSpacing = 0.7, cargoHeight = 0.8 },
  },

  finale = { name = "The Test Track", radius = 25, timeLimit = 1200, via = {} },
  workshopSpots = {},   -- course: where workshops are (gas stations). Empty = the workshop works anywhere
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local cfg
local game = { phase = "idle", stage = 0, players = {} }
local clock = MP.CreateTimer()
local tickCount = 0
local pendingImport, finishImport  -- price import state (defined with the admin commands)
local performTow                   -- defined with the player commands
local routePoints                  -- circuit: checkpoints + the start/finish line (defined with the event engine)
local function now() return clock:GetCurrent() end

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
local function log(msg) print("[TopGear] " .. msg) end
local function say(pid, msg)
  if pid then MP.SendChatMessage(pid, "[TG] " .. msg); MP.TriggerClientEvent(pid, "tg_log", msg) end
end
local function sayAll(msg) MP.SendChatMessage(-1, "[TG] " .. msg); MP.TriggerClientEvent(-1, "tg_log", msg) end
local function bigAll(msg) MP.TriggerClientEvent(-1, "tg_msg", msg) end

local function money(n)
  n = math.floor((n or 0) + 0.5)
  local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n < 0 and "-$" or "$") .. s
end
local function fmtTime(s) s = s or 0; return string.format("%d:%05.2f", math.floor(s / 60), s % 60) end
local function fmtSpeed(ms) return string.format("%.1f km/h (%.1f mph)", ms * 3.6, ms * 2.23694) end
local function ordinal(n)
  n = math.floor(n)
  local s = ({ "st", "nd", "rd" })[n % 10]
  if not s or (n % 100 >= 11 and n % 100 <= 13) then s = "th" end
  return n .. s
end
local function withArticle(name)
  name = tostring(name or "car")
  return (name:match("^[AEIOUaeiou]") and "an " or "a ") .. name
end
local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end
local function contains(t, v)
  for _, x in ipairs(t or {}) do if tonumber(x) == tonumber(v) then return true end end
  return false
end

local function readFile(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function writeFile(path, s)
  local f, err = io.open(path, "w")
  if not f then log("write failed: " .. tostring(err)); return false end
  f:write(s); f:close(); return true
end
local function isArray(t) return type(t) == "table" and t[1] ~= nil end
local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}; for k, v in pairs(t) do r[k] = deepcopy(v) end; return r
end
local function merge(dst, src)  -- objects merge recursively, arrays are replaced
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" and not isArray(v) and not isArray(dst[k]) then
      merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

-- One-off: saved "Hill Climb" races become one-at-a-time time trials.
local function migrateEvents(events)
  local changed = false
  for _, e in ipairs(events or {}) do
    if type(e.bay) == "table" and (type(e.bays) ~= "table" or #e.bays == 0) then
      e.bays, e.bay, changed = { e.bay }, nil, true
    end
    if e.type == "trailer" and e.description == "Hitch up and deliver the load. Lost cargo costs 20 seconds a piece." then
      e.description, changed = "Hitch up and deliver the load. 70 points for the load you keep, 30 for speed.", true   -- 0.8.3 scoring
    end
    if e.type == "speedtrap" and not e.oneRun then   -- 0.8.4: one run through the trap instead of three
      e.oneRun, changed = true, true
      if e.runs == 3 then e.runs = 1 end
      if e.description == "Three runs through the trap. Highest speed wins." then
        e.description = "One run through the trap. Highest speed wins."
      end
    end
    if e.type == "timetrial" then   -- 0.8.4: time trial is a mode of any event, not a type of its own
      e.type, changed = "race", true
      if e.solo == nil then e.solo = true end
      e.ttMigrated = true
      print("[TopGear] '" .. tostring(e.name) .. "' is now a destination race in time trial mode")
    end
    if not e.ttMigrated then
      e.ttMigrated = true
      if e.type == "race" and e.solo == nil and tostring(e.name):lower():find("hill climb") then
        e.solo, changed = true, true
        print("[TopGear] '" .. tostring(e.name) .. "' now runs in time trial mode (one at a time)")
      end
    end
  end
  return changed
end

local function saveConfig()
  local s = Util.JsonEncode(cfg)
  if Util.JsonPrettify then s = Util.JsonPrettify(s) end
  return writeFile(CONFIG_PATH, s)
end
local function loadConfig()
  cfg = deepcopy(DEFAULT_CONFIG)
  local s = readFile(CONFIG_PATH)
  if not s then
    if saveConfig() then log("wrote default config.json") end
    return
  end
  local ok, t = pcall(Util.JsonDecode, s)
  if ok and type(t) == "table" then
    merge(cfg, t); log("config.json loaded")
    local changed = migrateEvents(cfg.events)
    cfg.migrations = cfg.migrations or {}
    for _, f in ipairs((cfg.faults or {}).list or {}) do   -- old default severities -> current defaults (once)
      if f.id == "tires" and not cfg.migrations.tires30 and (f.factor == 0.55 or f.factor == 0.1) then f.factor, changed = 0.3, true end
      if f.id == "alignment" and f.factor == 0.7 then f.factor, changed = 1.4, true end
    end
    if not cfg.migrations.tires30 then cfg.migrations.tires30, changed = true, true end
    if changed then saveConfig() end
  else
    log("config.json is not valid JSON - running on defaults (file left untouched)")
  end
end

-- course library -----------------------------------------------------------
local library = {}          -- name -> { events, finale, savedAt, problems }
local courseDirty = false   -- loaded course edited since last save/load

local function loadLibrary()
  local s = readFile(COURSES_PATH)
  if not s then return end
  local ok, t = pcall(Util.JsonDecode, s)
  if ok and type(t) == "table" and type(t.courses) == "table" then library = t.courses
  else log("courses.json is not valid JSON - library not loaded (file left untouched)") end
end
local function saveLibrary()
  local s = Util.JsonEncode({ courses = library })
  if Util.JsonPrettify then s = Util.JsonPrettify(s) end
  return writeFile(COURSES_PATH, s)
end
local function markDirty()
  courseDirty = true
  cfg.courseDirty = true
  saveConfig()   -- write the working course now, so a server restart never loses edits
end

-- vectors ------------------------------------------------------------------
local function v3(t)
  if type(t) ~= "table" then return nil end
  local x, y, z = t.x or t[1], t.y or t[2], t.z or t[3]
  if not (x and y and z) then return nil end
  return { x = x, y = y, z = z }
end
local function r2(n) return math.floor(n * 100 + 0.5) / 100 end
local function roundPos(p) return { x = r2(p.x), y = r2(p.y), z = r2(p.z) } end
local function dist(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end
local function segDist(p, a, b)  -- distance from point p to segment a-b
  local abx, aby, abz = b.x - a.x, b.y - a.y, b.z - a.z
  local len2 = abx * abx + aby * aby + abz * abz
  if len2 < 1e-6 then return dist(p, a) end
  local t = ((p.x - a.x) * abx + (p.y - a.y) * aby + (p.z - a.z) * abz) / len2
  t = math.max(0, math.min(1, t))
  return dist(p, { x = a.x + abx * t, y = a.y + aby * t, z = a.z + abz * t })
end
-- Did the car pass within r of target during the last tick? Uses the path
-- between samples so fast cars can't skip a checkpoint between polls.
local function reached(p, target, r)
  target = v3(target)
  if not (p.pos and target) then return false end
  if not p.prevPos or dist(p.prevPos, p.pos) > 150 then return dist(p.pos, target) <= r end
  return segDist(target, p.prevPos, p.pos) <= r
end

-- players ------------------------------------------------------------------
local function isAdmin(name)
  if not cfg.admins or #cfg.admins == 0 then return true end
  for _, a in ipairs(cfg.admins) do if a == name then return true end end
  return false
end
local function newRun()
  return { status = "pending", cp = 1, penalty = 0, attempts = 0, best = 0, trapMax = 0, inTrap = false }
end
local function newPlayer(name, pid)
  return {
    name = name, pid = pid, cash = cfg.economy.startingCash, points = 0, wins = 0,
    results = {}, damage = 0, carPrice = 0, recoveries = 0, drivability = 0,
    spent = { repairs = 0, upgrades = 0, towCost = 0, fines = 0, faultCash = 0, faultFixes = 0 },
    faults = {}, faultsFixed = 0, tows = 0, respawns = 0,
    leg = { via = 1, arrived = false }, run = newRun(),
  }
end
local function playerByPid(pid)
  for _, p in pairs(game.players) do if p.pid == pid then return p end end
  return nil
end
local function racing(p) return p.pid ~= nil and p.carVid ~= nil end
-- admins in traffic mode (/tg traffic on): everything they spawn is non-scoring traffic, in any phase
local trafficMode = {}   -- player name -> true
local function inTrafficMode(name) return trafficMode[name] == true and isAdmin(name) end
local function spend(p, kind, amount)
  p.spent = p.spent or {}
  p.spent[kind] = (p.spent[kind] or 0) + amount
end

-- trailer event vehicles ---------------------------------------------------------
local function trailerPayload(tc)
  if type(tc.setup) == "table" and tc.setup.model then
    return { trailer = tc.setup.model, setup = tc.setup, count = 0, back = tc.trailerBack or 7 }
  end
  return { trailer = tc.trailerModel, cargo = tc.cargoModel, count = tc.cargoCount or 5,
           back = tc.trailerBack or 7, spacing = tc.cargoSpacing or 0.7, height = tc.cargoHeight or 0.8 }
end

local function requestTrailer(p)
  if not p.pid or (p.eventVeh and p.eventVeh.trailer) then return end
  local tc = (cfg.eventTypes or {}).trailer or {}
  local payload = trailerPayload(tc)
  p.spawnAllow = { untilT = now() + 30, trailer = payload.trailer, cargo = payload.cargo, count = payload.count or 0 }
  p.eventVeh = { cargo = {}, prebuilt = payload.setup ~= nil }
  p.cargoFrac = nil
  MP.TriggerClientEvent(p.pid, "tg_trailer", Util.JsonEncode(payload))
  say(p.pid, "Your trailer and its load are being dropped behind you - reverse up, hitch it, and don't lose the cargo. " ..
    "(No tow hitch on your car? It's fitted from the parts menu in a workshop.)")
end

-- faults ---------------------------------------------------------------------
local function faultsOn() return cfg.faults and cfg.faults.enabled end
local function playerBudget(p)   -- what the dealership lets this player spend up to
  return cfg.economy.startingCash + ((p and p.spent and p.spent.faultCash) or 0)
end
local function faultDef(id)
  for _, f in ipairs((cfg.faults or {}).list or {}) do if f.id == id then return f end end
  return nil
end
local function fixCost(f) return math.ceil((f.payout or 0) * (cfg.faults.fixMultiplier or 1.5)) end
local function hasFault(p, id)
  for _, x in ipairs(p.faults or {}) do if x == id then return true end end
  return false
end
local function removeFault(p, id)
  for i, x in ipairs(p.faults or {}) do if x == id then table.remove(p.faults, i); return true end end
  return false
end
local function faultNames(p)
  local names = {}
  for _, id in ipairs(p.faults or {}) do local f = faultDef(id); names[#names + 1] = f and f.name or id end
  return names
end
local SETUP_FAULTS = { tires = true, alignment = true, bumpers = true }   -- these respawn the car

local function sendFaults(p, test)
  if not p.pid then return end
  local list, setup = {}, false
  for _, id in ipairs(p.faults or {}) do
    local f = faultDef(id)
    if f then list[#list + 1] = { id = f.id, factor = f.factor }; setup = setup or SETUP_FAULTS[f.id] or false end
  end
  for id in pairs(p.faultRestore or {}) do setup = setup or SETUP_FAULTS[id] or false end
  -- a setup fault change respawns the car: accept that edit without billing it
  if setup then p.faultEditUntil = now() + 15 end
  MP.TriggerClientEvent(p.pid, "tg_faults", Util.JsonEncode({ faults = list, restore = p.faultRestore or {}, test = test or false }))
end

-- vehicles -----------------------------------------------------------------
local function parseVehicle(data)
  if type(data) ~= "string" then return nil end
  local s = data:find("{", 1, true)
  if not s then return nil end
  local ok, t = pcall(Util.JsonDecode, data:sub(s))
  if not ok or type(t) ~= "table" then return nil end
  local config
  local vcf = t.vcf
  if type(vcf) == "table" and type(vcf.partConfigFilename) == "string" then
    config = vcf.partConfigFilename:match("([^/]+)%.pc$")
  end
  return t.jbm, config, (type(vcf) == "table") and vcf or nil
end
local function modelListed(model)
  for _, c in ipairs(cfg.dealer.cars) do if c.model == model then return c end end
  return nil
end

local function lookupCar(model, config)
  if not model then return nil, "unknown vehicle" end
  if cfg.dealer.useGamePrices then
    if not modelListed(model) then return nil, "not sold here" end
    local gp = (cfg.dealer.gamePrices or {})[model]
    if not gp then return nil, "no imported prices for this model (/tg importprices)" end
    local e = config and gp[config]
    if not (e and tonumber(e.price)) then return nil, "not a stock trim with a price (custom configs aren't sold)" end
    return { model = model, config = config, name = e.name or (model .. " " .. config), price = tonumber(e.price) }
  end
  local fallback
  for _, c in ipairs(cfg.dealer.cars) do
    if c.model == model then
      local cc = (c.config ~= "" and c.config) or nil
      if cc and cc == config then return c end
      if not cc then fallback = c end
    end
  end
  if cfg.dealer.strictConfigs then return nil, "not a listed configuration" end
  if not fallback then return nil, "not sold here" end
  return fallback
end
local function setCar(p, vid, model, config, car)
  p.carVid, p.carModel, p.carConfig = vid, model, config
  p.carName, p.carPrice = car.name, car.price
end
local function refundCar(p)
  p.cash = p.cash + (p.carPrice or 0) + (p.dealerParts or 0)   -- upgrades fitted at the dealership go back with it
  if (p.dealerParts or 0) ~= 0 then spend(p, "upgrades", -p.dealerParts) end
  p.dealerParts = 0
  p.carVid, p.carModel, p.carConfig, p.carName, p.carPrice = nil, nil, nil, nil, 0
  p.ready = false
end

---------------------------------------------------------------------------
-- Targets / HUD state
---------------------------------------------------------------------------
local function curEvent() return (game.events or {})[game.stage] end

local TYPE_ORDER = { "race", "circuit", "speedtrap", "parking", "fragile", "economy", "slalom", "trailer" }
local TYPE_INFO = {
  race      = { label = "Destination race",  name = "The Race" },
  circuit   = { label = "Circuit race",      name = "The Circuit" },
  speedtrap = { label = "Speed trap",        name = "The Speed Trap" },
  parking   = { label = "Precision parking", name = "Precision Parking" },
  fragile   = { label = "Fragile delivery",  name = "Fragile Delivery" },
  economy   = { label = "Economy run",       name = "The Economy Run" },
  slalom    = { label = "Slalom",            name = "The Slalom" },
  trailer   = { label = "Trailer delivery",  name = "Trailer Delivery" },
}
-- Mode: every event runs in race mode (everyone at once) or time trial mode (one at a time, in arrival
-- order). e.solo stores an explicit choice; without one, parking and slalom default to time trial mode.
local SOLO_DEFAULT = { parking = true, slalom = true }
local function isSolo(e)
  if e.solo ~= nil then return e.solo and true or false end
  return SOLO_DEFAULT[e.type] or false
end
local function trapRuns(e) return math.max(1, math.floor(tonumber(e.runs) or 1)) end   -- speed trap passes that count
local function modeLabel(e) return isSolo(e) and "time trial mode (one at a time)" or "race mode (everyone at once)" end
local function typeCfg(t) return (cfg.eventTypes or {})[t] or {} end
local function eventBays(e)
  if type(e.bays) == "table" and #e.bays > 0 then return e.bays end
  if type(e.bay) == "table" and (e.bay.x or e.bay[1]) then return { e.bay } end
  return {}
end
local function workshopSpots() return cfg.workshopSpots or {} end
-- where workshops can be used: the course's spots plus the dealership (only when the course has spots;
-- a course without spots has workshops anywhere)
local function allSpots()
  local out = {}
  for _, sp in ipairs(workshopSpots()) do out[#out + 1] = sp end
  if #out > 0 then for _, sp in ipairs(game.dealerSpots or {}) do out[#out + 1] = sp end end
  return out
end
local function nearDealership(p)
  if not p.pos then return true end   -- no position yet: still where they bought it
  for _, sp in ipairs(game.dealerSpots or {}) do
    if dist(p.pos, v3(sp)) <= (cfg.workshop.radius or 30) then return true end
  end
  return false
end
local function nearestSpot(pos)
  local best, bestD
  for _, sp in ipairs(allSpots()) do
    local sv = v3(sp)
    if sv and pos then
      local d = dist(pos, sv)
      if not bestD or d < bestD then best, bestD = sp, d end
    end
  end
  return best, bestD
end
-- can this player use workshop services right now? (the dealership counts once they own a car)
local function inWorkshop(p)
  if game.phase == "dealer" then return p.carVid ~= nil end
  -- after the doors close you can keep working on the car until you drive away from the dealership
  if p.dealerGrace and (game.phase == "travel" or game.phase == "countdown") and game.stage == 1 then
    return p.carVid ~= nil and nearDealership(p)
  end
  if game.phase ~= "workshop" then return false end
  if #workshopSpots() == 0 then return true end
  return p.inShop == true
end
local function enabledEvents()
  local out = {}
  for _, e in ipairs(cfg.events) do if e.enabled ~= false then out[#out + 1] = e end end
  return out
end
local function yawFromQuat(q)
  if not q then return nil end
  local x, y, z, w = q.x or q[1], q.y or q[2], q.z or q[3], q.w or q[4]
  if not (x and y and z and w) then return nil end
  local atan2 = math.atan2 or math.atan
  return math.deg(atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)))
end

local function legTarget(p, via, destPos, destR, destLabel)
  via = via or {}
  if p.leg.via <= #via then
    return { pos = via[p.leg.via], r = cfg.defaults.viaRadius,
             label = string.format("Waypoint %d/%d", p.leg.via, #via), kind = "via" }
  end
  return { pos = destPos, r = destR, label = destLabel, kind = "dest" }
end
local function eventStartTarget(p, e)
  return legTarget(p, e.via, e.start, e.startRadius or cfg.defaults.startRadius, e.name .. " - start")
end
local function finaleTarget(p)
  local f = cfg.finale
  return legTarget(p, f.via, f.pos, f.radius or cfg.defaults.startRadius, f.name .. " - finish")
end

local function currentTarget(p)
  local e, ph = curEvent(), game.phase
  if ph == "travel" and e then return eventStartTarget(p, e)
  elseif ph == "countdown" and e then
    return { pos = e.start, r = e.startRadius or cfg.defaults.startRadius, label = e.name .. " - start" }
  elseif ph == "event" and e and (p.run.status == "waiting" or (p.run.status == "staged" and isSolo(e))) then
    local runner = game.solo and game.solo.runner
    return { pos = e.start, r = e.startRadius or cfg.defaults.startRadius,
             label = p.run.status == "staged" and "Your run - get ready" or ("Wait at the start" .. (runner and (" - " .. runner.name .. " is running") or "")) }
  elseif ph == "event" and e and p.run.status == "running" then
    if e.type == "parking" then
      local bays = eventBays(e)
      local i = p.run.bay or 1
      return { pos = bays[i], r = typeCfg("parking").bayRadius or 5,
               label = p.run.needMove and string.format("Bay %d/%d - drive on", i, #bays)
                       or (#bays == 1 and "Park in the bay and stop" or string.format("Bay %d/%d - park and stop", i, #bays)) }
    end
    if e.type == "slalom" then
      local g = e.checkpoints or {}
      return { pos = g[p.run.cp], r = e.cpRadius or typeCfg("slalom").gateRadius or 4,
               label = (p.run.cp >= #g) and "FINISH" or string.format("Gate %d/%d", p.run.cp, #g - 1) }
    end
    if e.type == "speedtrap" then
      return { pos = e.trap, r = e.trapRadius or 10,
               label = trapRuns(e) == 1 and "Speed trap" or string.format("Speed trap (run %d/%d)", p.run.attempts + 1, trapRuns(e)) }
    end
    local cps = routePoints(e)
    if e.type == "circuit" then
      local laps = math.max(1, math.floor(tonumber(e.laps) or 3))
      local last = p.run.cp >= #cps
      return { pos = cps[p.run.cp], r = e.cpRadius or cfg.defaults.cpRadius,
               label = string.format("Lap %d/%d - %s", p.run.lap or 1, laps,
                 last and ((p.run.lap or 1) >= laps and "FINISH" or "Start/finish line") or string.format("Checkpoint %d/%d", p.run.cp, #cps - 1)) }
    end
    return { pos = cps[p.run.cp], r = e.cpRadius or cfg.defaults.cpRadius,
             label = (p.run.cp >= #cps) and "FINISH" or string.format("Checkpoint %d/%d", p.run.cp, #cps - 1) }
  elseif ph == "finale" then return finaleTarget(p)
  elseif ph == "workshop" and #workshopSpots() > 0 and p.pos then   -- nearest of the spots and the dealership
    local sp = nearestSpot(p.pos)
    if sp then return { pos = sp, r = cfg.workshop.radius or 30, label = "Workshop" .. (sp.name and (" - " .. sp.name) or "") } end
  end
  return nil
end

local function timeLeft()
  local e, t = curEvent(), now()
  if game.phase == "countdown" then return game.countdownEnd - t
  elseif game.phase == "event" and e then return (e.timeLimit or cfg.defaults.eventTimeLimit) - (t - game.eventStart)
  elseif game.phase == "workshop" then return game.workshopEnd - t
  elseif game.phase == "finale" then return (cfg.finale.timeLimit or 1200) - (t - game.phaseStart) end
  return nil
end

local function phaseTitle()
  local e, n, ph = curEvent(), #(game.events or {}), game.phase
  if ph == "dealer" then return "Dealership - buy a car, then /tg ready (no route until everyone is ready)"
  elseif ph == "travel" then return string.format("Leg %d/%d -> %s", game.stage, n, e.name)
  elseif ph == "countdown" then return e.name .. " - get ready"
  elseif ph == "event" then
    local runner = game.solo and game.solo.runner
    return string.format("Event %d/%d: %s%s", game.stage, n, e.name, runner and (" - " .. runner.name .. " running") or "")
  elseif ph == "workshop" then return "Workshop open"
  elseif ph == "finale" then return "Final leg -> " .. cfg.finale.name
  elseif ph == "results" then return "Challenge complete" end
  return ""
end

local function stateFor(p)
  local ph = game.phase
  local title = phaseTitle()
  if ph == "travel" and p.leg.arrived then
    title = game.allHere and "Everyone's here - type /tg go to start" or ("Waiting at " .. curEvent().name .. " for the others")
  end
  local s = {
    phase = ph, title = title, cash = p.cash, points = p.points, wins = p.wins,
    car = p.carName, carId = p.carVid and (tostring(p.pid) .. "-" .. tostring(p.carVid)) or nil,
    allowVehicleSelector = (ph == "dealer") or inTrafficMode(p.name),
    traffic = inTrafficMode(p.name) or nil,
    allowParts = inWorkshop(p),
    allowReset = (ph == "dealer" or ph == "results"),
    timeLeft = timeLeft(),
    eventType = curEvent() and curEvent().type or nil,
  }
  if ph == "countdown" and game.countdownEnd then
    s.lights = { left = game.countdownEnd - now(), total = cfg.defaults.countdown }
  elseif ph == "event" and game.solo and game.solo.runner and game.solo.runner.run.status == "staged" and game.solo.countEnd then
    s.lights = { left = game.solo.countEnd - now(), total = cfg.defaults.countdown, who = game.solo.runner.name }
  end
  local tgt = currentTarget(p)
  local tp = tgt and v3(tgt.pos)
  if tp then s.target = { x = tp.x, y = tp.y, z = tp.z, r = tgt.r, label = tgt.label } end
  return s
end
local function pushState(p)
  if p.pid then MP.TriggerClientEvent(p.pid, "tg_state", Util.JsonEncode(stateFor(p))) end
end
local function pushAll() for _, p in pairs(game.players) do pushState(p) end end
local function pushIdle(pid) MP.TriggerClientEvent(pid, "tg_state", Util.JsonEncode({ phase = "idle" })) end

---------------------------------------------------------------------------
-- Money helpers
---------------------------------------------------------------------------
local function repairQuote(p)
  local ec, d = cfg.economy, p.damage or 0
  if d < (ec.repairMinDamage or 50) then return 0 end
  return math.floor(ec.repairBaseFee + math.min(d * ec.repairCostPerDamage, ec.repairCap) + 0.5)
end
-- slots whose parts are cosmetic (free in the workshop) or managed by the mod (bumpers)
local FREE_SLOT_WORDS = { "skin", "paint", "livery", "decal", "sticker", "plate", "license", "licence", "badge",
  "mirror", "trim", "interior", "seat", "steering_wheel", "dash", "hubcap", "wheelcover", "light", "lamp",
  "antenna", "mudflap", "horn", "glass", "window", "wiper", "bumper" }
local function isFreeSlot(slot)
  slot = tostring(slot):lower()
  for _, w in ipairs(FREE_SLOT_WORDS) do if slot:find(w, 1, true) then return true end end
  return false
end
local function chargeLabour(p)
  if p.wsLabour then return end
  p.wsLabour = true
  local fee = cfg.workshop.laborFee or 0
  if fee <= 0 then return end
  p.cash = p.cash - fee
  spend(p, "upgrades", fee)
  p.wsSpent = (p.wsSpent or 0) + fee
  say(p.pid, string.format("Workshop labour: -%s (once per workshop).", money(fee)))
end

local function chargeParts(p, delta)   -- delta = change in parts value since the last charge
  chargeLabour(p)
  local w = cfg.workshop
  local amount = math.floor((delta > 0 and delta * (w.partsMarkup or 1) or delta * (w.resaleRate or 0.5)) + 0.5)
  if amount == 0 then return end
  p.cash = p.cash - amount
  spend(p, "upgrades", amount)
  p.wsSpent = (p.wsSpent or 0) + amount
  if game.phase == "dealer" then p.dealerParts = (p.dealerParts or 0) + amount end
  say(p.pid, amount > 0 and string.format("Parts fitted: -%s. Cash %s.", money(amount), money(p.cash))
                        or string.format("Old parts sold back: +%s. Cash %s.", money(-amount), money(p.cash)))
end

local function upgradeBill(p)   -- what this workshop has cost so far (for /tg quote and the window)
  return p.wsSpent or 0
end

---------------------------------------------------------------------------
-- Phase flow
---------------------------------------------------------------------------
local beginTravel, beginCountdown, startEvent, finishEvent
local beginWorkshop, endWorkshop, beginFinale, showResults
local nextSoloRunner

-- Where does a tow truck take this player? Returns pos, dir, targetEventIndex.
local function towDestination(p)
  local ph, n = game.phase, game.stage
  local idx
  if ph == "travel" then idx = n
  elseif ph == "event" or ph == "countdown" then idx = n + 1 end
  local e = idx and game.events[idx]
  if not (e and v3(e.start)) then return nil end
  local start = v3(e.start)
  local ahead = (e.type == "speedtrap") and v3(e.trap) or v3((e.checkpoints or {})[1])
  local dir = ahead and { x = ahead.x - start.x, y = ahead.y - start.y, z = 0 } or nil
  -- park towed cars side by side, not on top of each other
  game.towSlots = game.towSlots or {}
  local slot = game.towSlots[idx] or 0
  game.towSlots[idx] = slot + 1
  local pos = { x = start.x, y = start.y, z = start.z + 0.5 }
  if dir and slot > 0 then
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    if len > 0.01 then
      local side = (slot % 2 == 1) and 1 or -1
      local off = 4 * math.ceil(slot / 2) * side
      pos.x, pos.y = pos.x + dir.y / len * off, pos.y - dir.x / len * off
    end
  end
  return pos, dir, idx
end

local function validate(events, finale, onlyEnabled)
  events, finale = events or cfg.events, finale or cfg.finale
  local errs = {}
  for i, e in ipairs(events) do
    if not onlyEnabled or e.enabled ~= false then
      if not v3(e.start) then errs[#errs + 1] = string.format("Event %d (%s): no start - /tg setstart %d", i, e.name, i) end
      if e.type == "speedtrap" then
        if not v3(e.trap) then errs[#errs + 1] = string.format("Event %d: no trap - /tg settrap %d", i, i) end
      elseif e.type == "parking" then
        if #eventBays(e) == 0 then errs[#errs + 1] = string.format("Event %d: no parking bays - /tg addbay %d", i, i) end
      elseif #(e.checkpoints or {}) == 0 then
        errs[#errs + 1] = string.format("Event %d: no %s - /tg addcp %d", i, e.type == "slalom" and "gates" or "checkpoints", i)
      elseif e.type == "circuit" and #(e.checkpoints or {}) < 1 then
        errs[#errs + 1] = string.format("Event %d: a circuit needs checkpoints round the lap - /tg addcp %d", i, i)
      end
    end
  end
  if not v3((finale or {}).pos) then errs[#errs + 1] = "Finale: no finish point - /tg setfinale" end
  return errs
end

local function startGame(pid, force)
  if #enabledEvents() == 0 then say(pid, "No events are switched on - pick some in the Admin tab's Session list (/tg enable <n> on)."); return end
  local errs = validate(nil, nil, true)
  if #errs > 0 and not force then
    say(pid, "Course isn't finished:")
    for _, e in ipairs(errs) do say(pid, "  " .. e) end
    say(pid, "Fix those, or /tg start force to test anyway.")
    return
  end
  game = { phase = "dealer", stage = 0, players = {}, events = enabledEvents() }
  for ppid, name in pairs(MP.GetPlayers() or {}) do
    game.players[name] = newPlayer(name, ppid)
    if cfg.clearVehiclesOnStart then
      for vid in pairs(MP.GetPlayerVehicles(ppid) or {}) do MP.RemoveVehicle(ppid, vid) end
    end
  end
  sayAll("=== THE TOP GEAR CHALLENGE ===")
  local names = {}
  for i, e in ipairs(game.events) do names[i] = e.name end
  sayAll("Today: " .. table.concat(names, ", ") .. ".")
  local every = tonumber(cfg.workshopEvery) or 2
  for i, e in ipairs(game.events) do
    if e.type == "trailer" and (every <= 0 or i <= every) then
      say(pid, string.format("Heads-up: %s is event %d, before the first workshop - nobody can have fitted a tow hitch yet. " ..
        "Move it later in the Session list (hitches are fitted from the parts menu in a workshop).", e.name, i))
    end
  end
  sayAll(string.format("You each have %s. Buy a car from the dealership (spawn it from the vehicle menu). " ..
    "Whatever you don't spend, you keep for repairs and upgrades. /tg dealer for the list, /tg ready when done.",
    money(cfg.economy.startingCash)))
  bigAll("Go and buy a car!")
  pushAll()
  for _, p in pairs(game.players) do if p.pid then MP.TriggerClientEvent(p.pid, "tg_menu", "open") end end
end

local function stopGame()
  for _, p in pairs(game.players) do
    local ev = p.eventVeh
    if ev and p.pid then
      if ev.trailer then MP.RemoveVehicle(p.pid, ev.trailer) end
      for _, vid in ipairs(ev.cargo or {}) do MP.RemoveVehicle(p.pid, vid) end
    end
  end
  game = { phase = "idle", stage = 0, players = {} }
  pushIdle(-1)
end

local function lockDealer()
  for name, p in pairs(game.players) do
    if not p.carVid then
      say(p.pid, "You didn't buy a car, so you're spectating this one.")
      if p.pid then pushIdle(p.pid) end
      game.players[name] = nil
    end
  end
  if next(game.players) == nil then
    sayAll("Nobody bought a car. Challenge cancelled."); stopGame(); return
  end
  game.dealerSpots = {}
  for _, p in pairs(game.players) do
    if p.pos then
      local dup = false
      for _, sp in ipairs(game.dealerSpots) do if dist(v3(sp), p.pos) < 40 then dup = true end end
      if not dup then game.dealerSpots[#game.dealerSpots + 1] = { x = p.pos.x, y = p.pos.y, z = p.pos.z, name = "the dealership" } end
    end
    p.dealerGrace = true
  end
  sayAll("The dealership is closed - you can keep fitting parts and painting until you drive away from it. Today's cars:")
  for _, p in pairs(game.players) do
    sayAll(string.format("  %s - %s (%s), %s left over", p.name, p.carName, money(p.carPrice), money(p.cash)))
  end
  beginTravel(1)
end

beginTravel = function(n)
  game.phase, game.stage, game.phaseStart, game.arrivals, game.allHere = "travel", n, now(), 0, false
  local e = game.events[n]
  for _, p in pairs(game.players) do
    p.leg = { via = 1, arrived = false }; p.run = newRun(); p.arrivalRank = nil
    if p.towDeliveredTo == n then
      p.leg = { via = #(e.via or {}) + 1, arrived = true }
      p.towDeliveredTo = nil
      p.arrivalRank = 50
      if e.type == "trailer" then requestTrailer(p) end
      say(p.pid, "The tow truck already dropped you at " .. e.name .. " - no arrival bonus, but you're in.")
    end
  end
  local nv = #(e.via or {})
  sayAll(string.format("LEG %d of %d: drive to %s%s. Follow the arrows. Once everyone's there, anyone can /tg go.", n, #game.events, e.name,
    nv > 0 and string.format(" via %d waypoint%s", nv, nv == 1 and "" or "s") or ""))
  bigAll("Leg " .. n .. ": drive to " .. e.name)
  if not v3(e.start) then
    sayAll(string.format("Event %d has no start point, so there's no route to show. Admin: drive there and /tg setstart %d.", n, n))
  end
  pushAll()
end

local function tickTravel()
  local e = curEvent()
  for _, p in pairs(game.players) do
    if p.dealerGrace and racing(p) and p.pos and not nearDealership(p) then
      p.dealerGrace = false
      say(p.pid, "You've left the dealership - parts and paint are closed until the next workshop.")
      pushState(p)
    end
  end
  local total, arrived = 0, 0
  for _, p in pairs(game.players) do
    if racing(p) then
      total = total + 1
      if not p.leg.arrived then
        local tgt = eventStartTarget(p, e)
        if reached(p, tgt.pos, tgt.r) then
          if tgt.kind == "via" then
            say(p.pid, tgt.label .. " reached.")
            p.leg.via = p.leg.via + 1
          else
            p.leg.arrived = true
            game.arrivals = game.arrivals + 1
            p.arrivalRank = game.arrivals
            if e.type == "trailer" then requestTrailer(p) end
            local bonus = (cfg.economy.arrivalBonus or {})[game.arrivals] or 0
            p.cash = p.cash + bonus
            sayAll(string.format("%s arrives at %s (%s)%s", p.name, e.name, ordinal(game.arrivals),
              bonus > 0 and (" - " .. money(bonus) .. " bonus") or ""))
          end
          pushState(p)
        end
      end
      if p.leg.arrived then arrived = arrived + 1 end
    end
  end
  local allHere = total > 0 and arrived == total
  if allHere and not game.allHere then
    sayAll(string.format("Everyone's at %s! Line up - anyone can type /tg go to start the countdown.", e.name))
    bigAll("Everyone's here - /tg go to start")
  end
  if allHere ~= game.allHere then game.allHere = allHere; pushAll() end
end

-- Event engine -----------------------------------------------------------------
-- Simultaneous events: shared countdown, everyone runs at once.
-- Solo events (time trial, parking, slalom by default): one runner at a time in arrival order,
-- each with their own countdown; everyone else waits at the start.

local function startRun(p)
  local r = p.run
  r.status, r.startT, r.cp, r.missed = "running", now(), 1, 0
  r.lap, r.lapStart, r.bestLap = 1, now(), nil
  r.bay, r.parks, r.needMove, r.stillSince = 1, {}, false, nil
  r.startDamage, r.startFuel = p.damage or 0, p.fuel
  r.endDamage, r.endFuel, r.sampleAfter = nil, nil, nil
end

-- the finish flag on this player's screen: { event, detail, seconds }
local function showFinish(p, eventName, detail)
  if p.pid then
    MP.TriggerClientEvent(p.pid, "tg_finish", Util.JsonEncode({ event = eventName, detail = detail, seconds = 6 }))
  end
end

local function endRun(p, status)
  local r = p.run
  r.status = status or "finished"
  if r.status == "finished" then
    r.endT = now()
    r.sampleAfter = now() + 0.5   -- the next damage/fuel report counts as the finish reading
    local e = curEvent()
    local detail
    if e and e.type == "speedtrap" then detail = (trapRuns(e) == 1 and "Speed " or "Best ") .. fmtSpeed(r.best or 0)
    elseif r.time then detail = "Time " .. fmtTime(r.time) end
    showFinish(p, e and e.name, detail)
  end
end

beginCountdown = function()
  local e = curEvent()
  game.closeAt = nil
  for _, p in pairs(game.players) do
    if racing(p) and p.leg.arrived then
      p.run.status = "staged"
    else
      p.run.status = "dns"
      sayAll(p.name .. " didn't make it to the start - DNS.")
    end
  end
  if e.type == "trailer" then
    for _, p in pairs(game.players) do
      local ev = p.eventVeh
      if p.run.status == "staged" and ev and ev.trailer and p.pos then
        local raw = MP.GetPositionRaw(p.pid, ev.trailer)
        local tpos = type(raw) == "table" and v3(raw.pos)
        if tpos and dist(tpos, p.pos) > 10 then say(p.pid, "Your trailer isn't hooked up! Reverse onto it and press Hitch up (or /tg hitchup).") end
      end
    end
  end
  local desc = (e.description and e.description ~= "") and (" " .. e.description) or ""
  if isSolo(e) then
    game.phase, game.eventStart = "event", now()
    local order = {}
    for _, p in pairs(game.players) do
      if p.run.status == "staged" then p.run.status = "waiting"; order[#order + 1] = p end
    end
    table.sort(order, function(a, b) return (a.arrivalRank or 99) < (b.arrivalRank or 99) end)
    local names = {}
    for i, p in ipairs(order) do names[i] = p.name end
    game.solo = { order = order, idx = 0 }
    sayAll(string.format("%s!%s One at a time - running order: %s.", e.name, desc, table.concat(names, ", ")))
    nextSoloRunner()
  else
    game.phase, game.countdownEnd, game.lastCount = "countdown", now() + cfg.defaults.countdown, nil
    sayAll(string.format("%s!%s Starting in %s seconds...", e.name, desc, tostring(cfg.defaults.countdown)))
  end
  pushAll()
end

nextSoloRunner = function()
  local s = game.solo
  if not s then return false end
  while true do
    s.idx = s.idx + 1
    local p = s.order[s.idx]
    if not p then s.runner = nil; pushAll(); return false end
    if p.run.status == "waiting" and racing(p) then
      s.runner, s.countEnd, s.lastCount = p, now() + cfg.defaults.countdown, nil
      p.run.status = "staged"
      local nxt = s.order[s.idx + 1]
      sayAll(string.format("%s is up%s.", p.name, nxt and (" - " .. nxt.name .. " is next") or " - last run"))
      pushAll()
      return true
    elseif p.run.status == "waiting" then
      p.run.status = "dns"
    end
  end
end

local function falseStartCheck(p, e)
  local r = (e.startRadius or cfg.defaults.startRadius) + 5
  if p.pos and not p.run.jumped and dist(p.pos, v3(e.start)) > r then
    p.run.jumped = true
    p.run.penalty = cfg.defaults.falseStartPenalty
    sayAll(string.format("%s jumped the start! +%ss penalty.", p.name, tostring(cfg.defaults.falseStartPenalty)))
  end
end

local function tickCountdown()
  local e = curEvent()
  local left = game.countdownEnd - now()
  local sec = math.ceil(left)
  if sec > 0 and sec ~= game.lastCount then game.lastCount = sec; bigAll(tostring(sec)) end
  for _, p in pairs(game.players) do
    if p.run.status == "staged" then falseStartCheck(p, e) end
  end
  if left <= 0 then startEvent() end
end

startEvent = function()
  game.phase, game.eventStart, game.closeAt = "event", now(), nil
  for _, p in pairs(game.players) do if p.run.status == "staged" then startRun(p) end end
  bigAll("GO! GO! GO!")
  sayAll("GO!")
  pushAll()
end

-- per-type run logic --------------------------------------------------------------
local function countCargo(p)
  local ev = p.eventVeh
  if not (ev and ev.trailer and p.pid) then return 0, (ev and #ev.cargo) or 0 end
  local tc = typeCfg("trailer")
  local raw = MP.GetPositionRaw(p.pid, ev.trailer)
  local tpos = type(raw) == "table" and v3(raw.pos)
  local total = #ev.cargo
  if not tpos or not p.pos or dist(tpos, p.pos) > (tc.hitchRadius or 15) then return 0, total end  -- trailer left behind
  local left = 0
  for _, vid in ipairs(ev.cargo) do
    local cr = MP.GetPositionRaw(p.pid, vid)
    local cpos = type(cr) == "table" and v3(cr.pos)
    if cpos and dist(cpos, tpos) <= (tc.cargoRadius or 5) then left = left + 1 end
  end
  return left, total
end

routePoints = function(e)
  local cps = e.checkpoints or {}
  if e.type ~= "circuit" or not v3(e.start) then return cps end
  local r = {}
  for i, c in ipairs(cps) do r[i] = c end
  r[#r + 1] = e.start   -- the start point is the start/finish line
  return r
end

local function tickRoute(p, e)
  local cps = routePoints(e)
  if e.type == "circuit" then
    local line = v3(e.start)
    if line and p.pos and dist(p.pos, line) > math.max(40, (e.cpRadius or cfg.defaults.cpRadius) * 3) then p.run.leftLine = true end
    if p.run.cp >= #cps and not p.run.leftLine then return end
  end
  local cp = cps[p.run.cp]
  if not cp or not reached(p, cp, e.cpRadius or cfg.defaults.cpRadius) then return end
  local elapsed = now() - p.run.startT
  if e.type == "circuit" and p.run.cp >= #cps then
    local laps = math.max(1, math.floor(tonumber(e.laps) or 3))
    local lapTime = now() - p.run.lapStart
    p.run.bestLap = math.min(p.run.bestLap or lapTime, lapTime)
    if p.run.lap < laps then
      say(p.pid, string.format("Lap %d/%d done: %s. Lap %d!", p.run.lap, laps, fmtTime(lapTime), p.run.lap + 1))
      p.run.lap, p.run.cp, p.run.lapStart, p.run.leftLine = p.run.lap + 1, 1, now(), false
      pushState(p)
      return
    end
  end
  if p.run.cp >= #cps then
    p.run.time = elapsed + (p.run.penalty or 0)
    if e.type == "trailer" then
      if p.eventVeh and p.eventVeh.prebuilt then
        local tc = typeCfg("trailer")
        local raw = p.eventVeh.trailer and MP.GetPositionRaw(p.pid, p.eventVeh.trailer)
        local tpos = type(raw) == "table" and v3(raw.pos)
        local withYou = tpos and p.pos and dist(tpos, p.pos) <= (tc.hitchRadius or 15)
        local frac = withYou and (p.cargoFrac or 1) or 0
        p.run.cargoFrac = frac
        p.run.cargoLeft, p.run.cargoTotal = frac * (tc.cargoCount or 5), (tc.cargoCount or 5)
      else
        p.run.cargoLeft, p.run.cargoTotal = countCargo(p)
      end
    end
    endRun(p)
    local cargoTxt = ""
    if e.type == "trailer" then
      cargoTxt = p.run.cargoFrac and string.format(" with %d%% of the load", math.floor(p.run.cargoFrac * 100 + 0.5))
                 or string.format(" with %d/%d cargo", p.run.cargoLeft, p.run.cargoTotal)
    end
    sayAll(string.format("%s crosses the line! %s%s", p.name, fmtTime(p.run.time), cargoTxt))
  else
    say(p.pid, string.format("Checkpoint %d/%d - %s", p.run.cp, #cps - 1, fmtTime(elapsed)))
    p.run.cp = p.run.cp + 1
  end
  pushState(p)
end

local function tickSlalom(p, e)
  local gates = e.checkpoints or {}
  local r = e.cpRadius or typeCfg("slalom").gateRadius or 4
  for j = p.run.cp, #gates do
    if reached(p, gates[j], r) then
      local skipped = j - p.run.cp
      if skipped > 0 then
        p.run.missed = p.run.missed + skipped
        say(p.pid, string.format("Missed %d gate%s! (+%s s each)", skipped, skipped == 1 and "" or "s", tostring(typeCfg("slalom").gatePenalty or 5)))
      end
      if j >= #gates then
        p.run.time = now() - p.run.startT + (p.run.penalty or 0)
        endRun(p)
        sayAll(string.format("%s is through the slalom: %s, %d gate%s missed.", p.name, fmtTime(p.run.time), p.run.missed, p.run.missed == 1 and "" or "s"))
      else
        p.run.cp = j + 1
      end
      pushState(p)
      return
    end
  end
end

local function tickParking(p, e)
  local tc = typeCfg("parking")
  local bays = eventBays(e)
  local i = p.run.bay or 1
  local bay = bays[i]
  if not bay then return end
  if p.run.needMove then   -- after parking, drive off before the next bay can count
    if (p.speed or 0) > 1 then p.run.needMove = false end
    return
  end
  local bx, by = bay.x or bay[1], bay.y or bay[2]
  local d = math.sqrt((p.pos.x - bx) ^ 2 + (p.pos.y - by) ^ 2)
  if d <= (tc.bayRadius or 5) and (p.speed or 0) < (tc.stillSpeed or 0.3) then
    p.run.stillSince = p.run.stillSince or now()
    if now() - p.run.stillSince >= (tc.stillSeconds or 1.5) then
      local ang = 0
      if p.yaw and bay.yaw then
        ang = math.abs(p.yaw - bay.yaw) % 180
        if ang > 90 then ang = 180 - ang end   -- nose-in or reversed in both count as straight
      end
      p.run.parks[i] = { dist = d, angle = ang }
      p.run.stillSince = nil
      say(p.pid, string.format("Bay %d/%d parked: %d cm off centre, %.0f degrees skew.", i, #bays, math.floor(d * 100 + 0.5), ang))
      if i >= #bays then
        p.run.time = now() - p.run.startT + (p.run.penalty or 0)
        endRun(p)
        sayAll(string.format("%s has parked in all %d bay%s in %s.", p.name, #bays, #bays == 1 and "" or "s", fmtTime(p.run.time)))
      else
        p.run.bay, p.run.needMove = i + 1, true
      end
      pushState(p)
    end
  else
    p.run.stillSince = nil
  end
end

local function tickSpeedtrap(p, e)
  local r, trap, run = e.trapRadius or 10, v3(e.trap), p.run
  if reached(p, trap, r) then
    run.inTrap = true
    run.trapMax = math.max(run.trapMax, p.speed or 0)
  end
  if run.inTrap and dist(p.pos, trap) > r then  -- left the trap: that was one run
    run.inTrap = false
    if run.trapMax < (e.minRunSpeed or 20) then run.trapMax = 0; return end  -- slow pass (e.g. driving back) doesn't count
    run.attempts = run.attempts + 1
    run.best = math.max(run.best, run.trapMax)
    local runs = trapRuns(e)
    if runs == 1 then say(p.pid, "Through the trap at " .. fmtSpeed(run.trapMax) .. ".")
    else say(p.pid, string.format("Run %d: %s (best %s)", run.attempts, fmtSpeed(run.trapMax), fmtSpeed(run.best))) end
    run.trapMax = 0
    if run.attempts >= runs then
      endRun(p)
      sayAll(string.format("%s is done - %s%s", p.name, runs == 1 and "" or "best ", fmtSpeed(run.best)))
    end
    pushState(p)
  end
end

local function tickRun(p, e)
  if e.type == "speedtrap" then tickSpeedtrap(p, e)
  elseif e.type == "parking" then tickParking(p, e)
  elseif e.type == "slalom" then tickSlalom(p, e)
  else tickRoute(p, e) end
end

local function settleUnfinished(p, e)
  local r = p.run
  if r.status == "running" then
    if e.type == "speedtrap" and r.attempts > 0 then endRun(p)
    elseif e.type == "parking" and next(r.parks or {}) then
      r.time = now() - r.startT + (r.penalty or 0)
      endRun(p)
    else r.status = "dnf" end
  elseif r.status == "staged" or r.status == "waiting" then
    r.status = "dnf"
  end
end

local function closeEvent()  -- time limit or admin: settle everyone still going
  local e = curEvent()
  for _, p in pairs(game.players) do settleUnfinished(p, e) end
  finishEvent()
end

local function closeWhenSettled()  -- short grace so the last damage/fuel readings arrive
  game.closeAt = game.closeAt or (now() + 2.5)
  if now() >= game.closeAt then game.closeAt = nil; finishEvent() end
end

local function tickSolo(e)
  local s = game.solo
  local p = s and s.runner
  if not p then return closeWhenSettled() end
  local st = p.run.status
  if st == "staged" then
    if not racing(p) then p.run.status = "dnf"; nextSoloRunner(); return end
    local left = s.countEnd - now()
    local sec = math.ceil(left)
    if sec > 0 and sec ~= s.lastCount then s.lastCount = sec; bigAll(p.name .. ": " .. sec) end
    falseStartCheck(p, e)
    if left <= 0 then startRun(p); bigAll(p.name .. ": GO!"); pushAll() end
  elseif st == "running" then
    if racing(p) and p.pos then tickRun(p, e) end
    if p.run.status == "running" and now() - p.run.startT > (e.timeLimit or cfg.defaults.eventTimeLimit) then
      settleUnfinished(p, e)
      sayAll(p.name .. " is out of time.")
    end
    if p.run.status ~= "running" then nextSoloRunner() end
  else
    nextSoloRunner()   -- towed (DSQ) or lost before/while running
  end
end

local function tickTogether(e)
  local running = 0
  for _, p in pairs(game.players) do
    if p.run.status == "running" and racing(p) and p.pos then tickRun(p, e) end
    if p.run.status == "running" then running = running + 1 end
  end
  if running == 0 then return closeWhenSettled() end
  if now() - game.eventStart > (e.timeLimit or cfg.defaults.eventTimeLimit) then
    sayAll("Time's up!")
    closeEvent()
  end
end

local function tickEvent()
  local e = curEvent()
  if game.solo then tickSolo(e) else tickTogether(e) end
end

-- ctx = { bestTime = fastest finishing time in this event } (trailer speed score)
local function finalizeScore(p, e, ctx)
  local r, tc = p.run, typeCfg(e.type)
  local t = r.time or 0
  if e.type == "speedtrap" then
    r.score, r.perf, r.short = -(r.best or 0), fmtSpeed(r.best or 0), string.format("%.0f km/h", (r.best or 0) * 3.6)
  elseif e.type == "parking" then
    local nb = #eventBays(e)
    local sumD, sumA, n = 0, 0, 0
    for _, pk in pairs(r.parks or {}) do sumD, sumA, n = sumD + pk.dist, sumA + pk.angle, n + 1 end
    local dmg = math.max(0, (r.endDamage or p.damage or 0) - (r.startDamage or 0))
    local missed = math.max(0, nb - n)
    r.score = sumD * (tc.distWeight or 10) + sumA * (tc.angleWeight or 0.5) + t * (tc.timeWeight or 0.1)
            + dmg * (tc.damageWeight or 0.01) + missed * (tc.missedBayPenalty or 50)
    r.perf = string.format("%d/%d bays, avg %d cm off, %.0f deg skew, %s, %d damage (score %.1f)", n, nb,
      n > 0 and math.floor(sumD / n * 100 + 0.5) or 0, n > 0 and sumA / n or 0, fmtTime(t), math.floor(dmg), r.score)
    r.short = string.format("%.1f pts", r.score)
  elseif e.type == "fragile" then
    local dmg = math.max(0, (r.endDamage or p.damage or 0) - (r.startDamage or 0))
    local pen = dmg * (tc.damageWeight or 0.01)
    r.score = t + pen
    r.perf = string.format("%s + %d damage (+%.1f s) = %s", fmtTime(t), math.floor(dmg), pen, fmtTime(r.score))
    r.short = fmtTime(r.score)
  elseif e.type == "economy" then
    local endFuel = r.endFuel or p.fuel
    if r.startFuel and endFuel then
      local used = math.max(0, r.startFuel - endFuel)
      r.score = used + t * 1e-6   -- time only breaks exact ties
      r.perf, r.short = string.format("%.2f L in %s", used, fmtTime(t)), string.format("%.2f L", used)
    else
      r.score, r.perf, r.short = 1e6 + t, fmtTime(t) .. " (fuel reading unavailable)", fmtTime(t)
    end
  elseif e.type == "slalom" then
    local pen = (r.missed or 0) * (tc.gatePenalty or 5)
    r.score = t + pen
    r.perf = string.format("%s + %d missed (+%d s) = %s", fmtTime(t), r.missed or 0, pen, fmtTime(r.score))
    r.short = fmtTime(r.score)
  elseif e.type == "trailer" then
    -- out of 100: loadWeight x share of the load kept + speedWeight x (fastest time / your time). Highest wins.
    local frac = r.cargoFrac
    if frac == nil then frac = (r.cargoTotal or 0) > 0 and (r.cargoLeft or 0) / r.cargoTotal or 0 end
    frac = math.max(0, math.min(1, frac))
    local best = ctx and ctx.bestTime
    local speed = (best and t > 0) and math.min(1, best / t) or 1
    local lw, sw = math.max(0, tonumber(tc.loadWeight) or 0.7), math.max(0, tonumber(tc.speedWeight) or 0.3)
    if lw + sw <= 0 then lw, sw = 0.7, 0.3 end
    local loadPts, speedPts = 100 * lw / (lw + sw) * frac, 100 * sw / (lw + sw) * speed
    local pts = loadPts + speedPts
    r.score = -pts + t * 1e-9   -- higher points win; on an exact tie the faster run does
    local pct = math.floor(frac * 100 + 0.5)
    local load = r.cargoFrac and string.format("%d%% of the load", pct)
                 or string.format("%d/%d cargo", math.floor(r.cargoLeft or 0), math.floor(r.cargoTotal or 0))
    r.perf = string.format("%s, %s: load %.1f + speed %.1f = %.1f pts", fmtTime(t), load, loadPts, speedPts, pts)
    r.short = string.format("%.1f pts (%d%%, %s)", pts, pct, fmtTime(t))
  elseif e.type == "circuit" then
    r.score = t
    r.perf = string.format("%s (%d laps, best lap %s)", fmtTime(t), r.lap or 1, fmtTime(r.bestLap or t))
    r.short = fmtTime(t)
  else
    r.score, r.perf, r.short = t, fmtTime(t), fmtTime(t)
  end
end

local STATUS_LABEL = { dnf = "DNF", dns = "DNS", dsq = "DSQ (towed)", pending = "DNS", staged = "DNS", waiting = "DNS",
                       running = "DNF", finished = "NO TIME" }

local function cleanupEventVehicles()
  for _, p in pairs(game.players) do
    local ev = p.eventVeh
    if ev and p.pid then
      if ev.trailer then MP.RemoveVehicle(p.pid, ev.trailer) end
      for _, vid in ipairs(ev.cargo or {}) do MP.RemoveVehicle(p.pid, vid) end
    end
    p.eventVeh, p.spawnAllow = nil, nil
  end
end

finishEvent = function()
  local e = curEvent()
  local ranked, others = {}, {}
  for _, p in pairs(game.players) do
    if p.run.status == "finished" and (e.type ~= "speedtrap" or (p.run.best or 0) > 0) then
      ranked[#ranked + 1] = p
    else
      others[#others + 1] = p
    end
  end
  local ctx = {}
  for _, p in ipairs(ranked) do
    local tm = tonumber(p.run.time)
    if tm and tm > 0 then ctx.bestTime = math.min(ctx.bestTime or tm, tm) end
  end
  for _, p in ipairs(ranked) do finalizeScore(p, e, ctx) end
  table.sort(ranked, function(a, b) return a.run.score < b.run.score end)
  sayAll("===== RESULTS: " .. e.name .. " =====")
  for i, p in ipairs(ranked) do
    local prize = cfg.economy.prizes[i] or 0
    local pts = cfg.scoring.placementPoints[i] or 0
    p.cash, p.points = p.cash + prize, p.points + pts
    if i == 1 then p.wins = p.wins + 1 end
    p.results[game.stage] = { place = i, perf = p.run.perf, short = p.run.short, prize = prize, points = pts }
    sayAll(string.format("%s  %s - %s  (+%s, +%s pts)", ordinal(i), p.name, p.run.perf, money(prize), tostring(pts)))
  end
  for _, p in ipairs(others) do
    local st = STATUS_LABEL[p.run.status] or "DNF"
    if p.run.status == "dsq" then st = "DSQ (" .. (p.run.dsqReason or "towed") .. ")" end
    p.results[game.stage] = { perf = st, prize = 0, points = 0 }
    sayAll(string.format("--   %s - %s", p.name, st))
  end
  cleanupEventVehicles()
  if e.type == "fragile" then
    for _, p in pairs(game.players) do
      if racing(p) and p.run.status ~= "dns" then
        p.repairPending, p.damage = now(), 0
        MP.TriggerClientEvent(p.pid, "tg_repair", "")
      end
    end
    sayAll("The cars from the fragile delivery have been repaired, free of charge.")
  end
  game.solo, game.closeAt = nil, nil
  local n = game.stage
  local every = tonumber(cfg.workshopEvery) or 2
  if every > 0 and n % every == 0 and n < #game.events then beginWorkshop()
  elseif n >= #game.events then beginFinale()
  else beginTravel(n + 1) end
end

beginWorkshop = function()
  game.phase, game.workshopEnd, game.warned = "workshop", now() + cfg.workshop.minutes * 60, false
  for _, p in pairs(game.players) do p.wsLabour, p.wsSpent, p.wsCharged = false, 0, p.partsValue end
  if #workshopSpots() > 0 then
    sayAll(string.format("WORKSHOP open for %s minutes: drive to any workshop (the arrows show the nearest). " ..
      "Repairs, fault fixes, parts, paint and tuning work while you're parked there.", tostring(cfg.workshop.minutes)))
  end
  for _, p in pairs(game.players) do p.inShop = false end
  sayAll(string.format("WORKSHOP open for %s minutes. /tg quote for a repair price, /tg repair to fix your car. " ..
    "The parts menu is unlocked: parts are charged as you fit them (plus %s labour once). Paint, cosmetics and tuning are free.",
    tostring(cfg.workshop.minutes), money(cfg.workshop.laborFee)))
  bigAll("Workshop open")
  pushAll()
  for _, p in pairs(game.players) do if p.pid then MP.TriggerClientEvent(p.pid, "tg_menu", "open") end end
end

endWorkshop = function()
  sayAll("The workshop is closed.")
  for _, p in pairs(game.players) do
    local bill, delta = 0, nil   -- parts and labour are now charged as they happen
    if bill ~= 0 then
      p.cash = p.cash - bill
      spend(p, "upgrades", bill)
      say(p.pid, string.format("Workshop bill: %s%s. Cash now %s.", money(bill),
        delta and string.format(" (parts value change %s)", money(delta)) or " (labour only)", money(p.cash)))
    end
    if (p.wsSpent or 0) ~= 0 then say(p.pid, string.format("This workshop cost you %s in parts and labour.", money(p.wsSpent))) end
    p.wsLabour, p.wsSpent, p.wsCharged = false, 0, nil
  end
  if game.stage >= #game.events then beginFinale() else beginTravel(game.stage + 1) end
end

local function tickWorkshop()
  if #allSpots() > 0 and #workshopSpots() > 0 then
    local r = cfg.workshop.radius or 30
    for _, p in pairs(game.players) do
      if racing(p) and p.pos then
        local sp, d = nearestSpot(p.pos)
        local inside = d ~= nil and d <= r
        if inside ~= (p.inShop == true) then
          p.inShop = inside
          say(p.pid, inside and ("You're in the workshop" .. (sp and sp.name and (" at " .. sp.name) or "") .. " - repairs, parts and paint are open.")
                           or "You've left the workshop - repairs, parts and paint are closed until you're back.")
          pushState(p)
        end
      end
    end
  end
  local left = game.workshopEnd - now()
  if left <= 60 and not game.warned then game.warned = true; sayAll("Workshop closes in 1 minute!") end
  if left <= 0 then endWorkshop() end
end

beginFinale = function()
  game.phase, game.phaseStart, game.stage = "finale", now(), #game.events
  for _, p in pairs(game.players) do p.leg = { via = 1, arrived = false } end
  local f = cfg.finale
  sayAll(string.format("FINAL LEG: get your car to %s within %d minutes. Cars that make it are inspected - " ..
    "the less damage, the more points.", f.name, math.floor((f.timeLimit or 1200) / 60)))
  bigAll("Final leg: " .. f.name)
  pushAll()
end

local function tickFinale()
  local total, arrived = 0, 0
  local s = cfg.scoring
  for _, p in pairs(game.players) do
    if racing(p) then
      total = total + 1
      if not p.leg.arrived and p.pos and not p.finaleTowed then
        local tgt = finaleTarget(p)
        if reached(p, tgt.pos, tgt.r) then
          if tgt.kind == "via" then
            say(p.pid, tgt.label .. " reached.")
            p.leg.via = p.leg.via + 1
          else
            p.leg.arrived = true
            local frac = math.max(0, 1 - (p.damage or 0) / s.damageForZeroDrivability)
            p.drivability = math.floor(s.drivabilityMaxPoints * frac * 10 + 0.5) / 10
            if p.finaleRebuilt then p.drivability = 0 end   -- respawned on the final leg
            local nf = #(p.faults or {})
            local fpen = faultsOn() and nf * (cfg.faults.inspectionPenaltyPoints or 0) or 0
            if fpen > 0 then p.drivability = math.max(0, p.drivability - fpen) end
            p.points = p.points + p.drivability
            showFinish(p, cfg.finale.name, string.format("Drivability %.1f/%s", p.drivability, tostring(s.drivabilityMaxPoints)))
            sayAll(string.format("%s made it to %s! Inspection: damage %d%s -> drivability %.1f/%s",
              p.name, cfg.finale.name, math.floor(p.damage or 0),
              fpen > 0 and string.format(", %d unfixed fault%s", nf, nf == 1 and "" or "s") or "",
              p.drivability, tostring(s.drivabilityMaxPoints)))
          end
          pushState(p)
        end
      end
      if p.leg.arrived then arrived = arrived + 1 end
    end
  end
  local expired = now() - game.phaseStart > (cfg.finale.timeLimit or 1200)
  if expired or (total > 0 and arrived == total) then showResults() end
end

local function buildSummary(list)
  local s = { events = {}, rows = {}, winner = list[1] and list[1].name or nil }
  for i, e in ipairs(game.events or {}) do s.events[i] = e.name end
  for i, p in ipairs(list) do
    local places, eventPts = {}, 0
    for n = 1, #(game.events or {}) do
      local r = p.results[n]
      if r and r.place then
        places[n] = ordinal(r.place) .. " (" .. tostring(r.short or r.perf or "") .. ")"
        eventPts = eventPts + (r.points or 0)
      elseif r then places[n] = r.perf or "DNF"
      else places[n] = "-" end
    end
    local sp = p.spent or {}
    s.rows[i] = {
      place = i, name = p.name, car = p.carName or "-", carPrice = p.carPrice or 0, places = places,
      repairs = sp.repairs or 0, upgrades = sp.upgrades or 0,
      tows = p.tows or 0, respawns = p.respawns or 0, towCost = sp.towCost or 0, resets = p.recoveries or 0, fines = sp.fines or 0,
      faultsTaken = #(p.faults or {}) + (p.faultsFixed or 0), faultsFixed = p.faultsFixed or 0,
      faultCash = sp.faultCash or 0, faultFixes = sp.faultFixes or 0, faultsLeft = faultNames(p),
      drivability = p.drivability or 0, eventPoints = eventPts, penalty = p.penaltyPoints or 0,
      points = p.points, wins = p.wins, cash = p.cash,
    }
  end
  return s
end

showResults = function()
  game.phase = "results"
  local list = {}
  for _, p in pairs(game.players) do
    local pen = (p.recoveries or 0) * (cfg.scoring.recoveryPenaltyPoints or 0)
    p.penaltyPoints = pen
    if pen > 0 then
      p.points = p.points - pen
      sayAll(string.format("%s loses %s pts for %d illegal reset(s).", p.name, tostring(pen), p.recoveries))
    end
    list[#list + 1] = p
  end
  table.sort(list, function(a, b)
    if a.points ~= b.points then return a.points > b.points end
    if a.wins ~= b.wins then return a.wins > b.wins end
    return a.cash > b.cash
  end)
  sayAll("========== FINAL STANDINGS ==========")
  for i, p in ipairs(list) do
    sayAll(string.format("%s  %s - %.1f pts | %d win%s | drivability %.1f | %s | %s", ordinal(i), p.name,
      p.points, p.wins, p.wins == 1 and "" or "s", p.drivability or 0, money(p.cash), p.carName or "no car"))
  end
  sayAll("----- What it cost -----")
  for _, p in ipairs(list) do
    local sp = p.spent or {}
    local taken = #(p.faults or {}) + (p.faultsFixed or 0)
    sayAll(string.format("%s: repairs %s, upgrades %s, tows %d + respawns %d (%s), illegal resets %d (%s)%s", p.name, money(sp.repairs or 0),
      money(sp.upgrades or 0), p.tows or 0, p.respawns or 0, money(sp.towCost or 0), p.recoveries or 0, money(sp.fines or 0),
      taken > 0 and string.format(", faults %d taken (+%s) %d fixed (-%s)", taken, money(sp.faultCash or 0),
        p.faultsFixed or 0, money(sp.faultFixes or 0)) or ""))
  end
  if list[1] then
    bigAll(list[1].name .. " wins the Top Gear Challenge!")
    sayAll(string.format("%s and the %s win! Some say...", list[1].name, list[1].carName or "car"))
  end
  game.summary = buildSummary(list)
  pushAll()
  MP.TriggerClientEvent(-1, "tg_menu", "results")
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------
local pendingDiag = {}   -- pid -> time the report was requested

local phaseTick = { travel = tickTravel, countdown = tickCountdown, event = tickEvent,
                    workshop = tickWorkshop, finale = tickFinale }

function TG_onTick()
  for dpid, t0 in pairs(pendingDiag) do
    if now() - t0 > 5 then
      pendingDiag[dpid] = nil
      say(dpid, "No reply from the Top Gear client mod after 5 s - it is NOT running on your game.")
      say(dpid, "Check Resources/Client/topgear.zip is on the server, then fully restart BeamNG and reconnect.")
    end
  end
  if pendingImport and now() - pendingImport.started > 15 then finishImport() end
  if game.phase == "idle" then return end
  for _, p in pairs(game.players) do
    if racing(p) then
      local raw = MP.GetPositionRaw(p.pid, p.carVid)
      local pos = type(raw) == "table" and v3(raw.pos)
      if pos then
        p.prevPos = p.pos or pos
        p.pos = pos
        local vel = v3(raw.vel)
        p.speed = vel and math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z) or 0
        p.yaw = yawFromQuat(raw.rot) or p.yaw
      end
    end
  end
  local fn = phaseTick[game.phase]
  if fn then
    local ok, err = pcall(fn)
    if not ok then log("tick error: " .. tostring(err)) end
  end
  tickCount = tickCount + 1
  if tickCount % PUSH_EVERY == 0 then pushAll() end
end

---------------------------------------------------------------------------
-- BeamMP events
---------------------------------------------------------------------------
function TG_onPlayerJoin(pid)
  local name = MP.GetPlayerName(pid)
  local p = game.players[name]
  if p and game.phase ~= "idle" then
    p.pid, p.carVid, p.pos, p.prevPos = pid, nil, nil, nil
    if game.phase == "dealer" then
      say(pid, "Welcome back - the dealership is still open.")
    else
      say(pid, string.format("Welcome back %s. Respawn your %s (a %s tow fee applies).",
        name, p.carName or "car", money(cfg.economy.towFee)))
    end
    pushState(p)
  elseif game.phase == "dealer" then
    say(pid, "A Top Gear Challenge is about to start - type /tg join to take part.")
  elseif game.phase ~= "idle" then
    say(pid, "A Top Gear Challenge is in progress - you're spectating.")
  end
end

function TG_onPlayerDisconnect(pid)
  local p = playerByPid(pid)
  if not p then return end
  if game.phase == "dealer" and p.carVid then refundCar(p) end
  if p.run.status == "running" or p.run.status == "staged" then p.run.status = "dnf" end
  p.pid, p.carVid, p.pos, p.prevPos = nil, nil, nil, nil
  sayAll(p.name .. " has left. Their progress is kept if they rejoin with the same name.")
end

function TG_onVehicleSpawn(pid, vid, data)
  if game.phase == "idle" then return 0 end
  local name = MP.GetPlayerName(pid)
  local p = playerByPid(pid)
  -- trailer + cargo for a trailer event (requested by the server moments ago)
  if p and p.spawnAllow and now() < p.spawnAllow.untilT and p.eventVeh then
    local m = parseVehicle(data)
    local a, ev = p.spawnAllow, p.eventVeh
    if m == a.trailer and not ev.trailer then ev.trailer = vid; return 0 end
    if m == a.cargo and #ev.cargo < a.count then ev.cargo[#ev.cargo + 1] = vid; return 0 end
  end
  if cfg.debugSpawns then log("spawn " .. name .. " vid " .. tostring(vid) .. ": " .. tostring(data):sub(1, 400)) end
  local bringingBack = p and p.carModel and not p.carVid and game.phase ~= "dealer" and parseVehicle(data) == p.carModel
  if inTrafficMode(name) and not bringingBack then   -- the admin is placing traffic: never a purchase, never scored
    log(string.format("traffic: %s spawned %s (vid %s)", name, tostring((parseVehicle(data))), tostring(vid)))
    return 0
  end
  local extraOK = cfg.adminExtraVehicles and isAdmin(name) and game.phase ~= "dealer"  -- traffic only after the dealership
  local hint = isAdmin(name) and " (Admin: /tg traffic on to add traffic.)" or ""

  if not p then
    if extraOK then return 0 end
    say(pid, "A challenge is running - spectators can't spawn vehicles." .. hint)
    return 1
  end
  if p.carVid then
    if extraOK then say(pid, "Extra (non-scoring) vehicle spawned."); return 0 end
    say(pid, (game.phase == "dealer" and "You already have a car - delete it first to swap." or
      "You already have your car.") .. hint)
    return 1
  end

  local model, config = parseVehicle(data)
  if game.phase == "dealer" then
    local car, why = lookupCar(model, config)
    if car and car.price > playerBudget(p) then
      say(pid, string.format("The %s (%s) is over your %s budget - taking faults raises it (/tg faults).", car.name, money(car.price), money(playerBudget(p))))
      return 1
    end
    if not car then
      say(pid, string.format("The dealership can't sell you that (%s / %s): %s. /tg dealer for the list.",
        tostring(model), tostring(config), tostring(why)))
      log(string.format("rejected spawn: model=%s config=%s", tostring(model), tostring(config)))
      return 1
    end
    if car.price > p.cash then
      say(pid, string.format("The %s costs %s - you have %s.", car.name, money(car.price), money(p.cash)))
      return 1
    end
    p.cash = p.cash - car.price
    setCar(p, vid, model, config, car)
    p.lastVcf = select(3, parseVehicle(data))
    sayAll(string.format("%s bought %s for %s (%s left).", p.name, withArticle(car.name), money(car.price), money(p.cash)))
    if #(p.faults or {}) > 0 then sendFaults(p) end
    pushState(p)
    return 0
  end

  -- mid-challenge: the only thing you may spawn is your own car back, via the tow truck
  if not p.carModel or model ~= p.carModel then
    say(pid, "You can only respawn your own " .. (p.carName or "car") .. ".")
    return 1
  end
  p.carVid, p.pos, p.prevPos = vid, nil, nil
  performTow(p, false)
  return 0
end

function TG_onVehicleEdited(pid, vid, data)
  if game.phase == "idle" or game.phase == "results" then return 0 end
  local p = playerByPid(pid)
  if not p or p.carVid ~= vid then return 0 end   -- admin extras etc.
  local model, config = parseVehicle(data)
  model = model or p.carModel
  config = config or p.carConfig
  local _, _, vcf = parseVehicle(data)
  p.lastEditAt = now()
  log(string.format("edit by %s in phase %s (mod change window: %s)", p.name, game.phase,
    tostring(p.faultEditUntil ~= nil and now() < p.faultEditUntil)))
  if p.faultEditUntil and now() < p.faultEditUntil and model == p.carModel then
    if vcf then p.lastVcf = vcf end   -- our own fault/tow change; allowed in any phase
    return 0
  end

  if game.phase == "dealer" and model == p.carModel and config == p.carConfig then
    -- same car, same stock trim: an upgrade or paint job at the dealership (billed from the rebuild report)
    if vcf then p.lastVcf = vcf end
    return 0
  end
  if game.phase == "dealer" then
    local car = lookupCar(model, config)
    if not car then say(pid, "The dealership doesn't sell that configuration."); return 1 end
    p.swapAt = now()   -- a trim/model swap is priced here, not as parts
    local diff = car.price - (p.carPrice or 0)
    if diff > p.cash then say(pid, "You can't afford that - " .. money(car.price) .. "."); return 1 end
    p.cash = p.cash - diff
    setCar(p, vid, model, config, car)
    if vcf then p.lastVcf = vcf end
    if diff ~= 0 then say(pid, string.format("Swapped to the %s. Cash now %s.", car.name, money(p.cash))) end
    if #(p.faults or {}) > 0 then sendFaults(p) end   -- faults come with the deal, not the car
    pushState(p)
    return 0
  elseif game.phase == "workshop" then
    if model ~= p.carModel then say(pid, "No swapping cars mid-challenge!"); return 1 end
    if not inWorkshop(p) then p.outsideEditAt = now() end   -- a part change gets put back via the rebuild report
    if vcf then p.lastVcf = vcf end   -- labour/parts are billed from the client's rebuild report
    return 0
  end
  -- outside a workshop: paint is simply accepted (free, no rebuild); a part/tuning change is put back by
  -- the player's own game when its rebuild report arrives. Never cancel here: BeamMP removes the car.
  p.outsideEditAt = now()
  log(string.format("edit outside a workshop by %s in phase %s: accepted, parts/tuning will be put back", p.name, game.phase))
  return 0
end

function TG_onVehicleDeleted(pid, vid)
  local p = playerByPid(pid)
  if not p or p.carVid ~= vid then return end
  if game.phase == "dealer" then
    local price = (p.carPrice or 0) + (p.dealerParts or 0)
    local extra = (p.dealerParts or 0) ~= 0 and string.format(" (car %s + upgrades %s)", money(p.carPrice), money(p.dealerParts)) or ""
    refundCar(p)
    say(pid, "Car returned to the dealership - " .. money(price) .. " refunded" .. extra .. ".")
    pushState(p)
    return
  end
  p.carVid, p.pos, p.prevPos = nil, nil, nil
  if p.run.status == "running" or p.run.status == "staged" then p.run.status = "dnf" end
  if game.phase ~= "results" then
    sayAll(string.format("%s's %s is out of action! (Respawn the same car for a %s tow.)",
      p.name, p.carName or "car", money(cfg.economy.towFee)))
  end
  pushState(p)
end

function TG_onVehicleReset(pid, vid, data)
  local p = playerByPid(pid)
  if not p or p.carVid ~= vid then return end
  p.prevPos = nil
  if p.repairPending and now() - p.repairPending < 10 then p.repairPending = nil; return end
  p.repairPending = nil
  -- tows and unsticks may reset the car more than once (one per placement attempt): excuse them all
  if p.towPending and now() - p.towPending < 15 then return end
  if p.respawnPending and now() - p.respawnPending < 10 then return end
  if p.faultEditUntil and now() < p.faultEditUntil then return end        -- our own config change rebuilt the car
  if p.lastEditAt and now() - p.lastEditAt < 5 then return end            -- a part change rebuilt the car
  if game.phase == "workshop" then   -- never fined here; if it repaired the car, the damage drop is billed
    log(string.format("reset by %s in the workshop (not fined)", p.name))
    return
  end
  if p.unstickPending and now() - p.unstickPending < 6 then
    local cost = p.unstickRepairQuote or 0
    p.unstickRepairQuote = 0   -- bill the repair once
    if cost > 0 then
      p.cash = p.cash - cost
      spend(p, "repairs", cost)
      say(p.pid, string.format("On this BeamNG version unstick resets the car, which also repaired it - that repair is billed (%s). The unstick itself is free.", money(cost)))
    end
    p.damage = 0
    pushState(p)
    return
  end
  local ph = game.phase
  if ph == "idle" or ph == "dealer" or ph == "results" then return end
  log(string.format("illegal reset by %s in phase %s: fined", p.name, ph))
  p.cash = p.cash - cfg.economy.resetPenalty
  spend(p, "fines", cfg.economy.resetPenalty)
  p.recoveries = (p.recoveries or 0) + 1
  sayAll(string.format("%s pressed the reset button! -%s. That's not very Top Gear.", p.name, money(cfg.economy.resetPenalty)))
  pushState(p)
end

-- Tow: full repair (keeps upgrades, paid fixes and unfixed faults), $towFee, DSQ from a
-- running event, delivery to the next start. carExists=false when a lost car was respawned.
performTow = function(p, carExists)
  local ph = game.phase
  local fee = cfg.economy.towFee
  p.cash = p.cash - fee
  spend(p, "towCost", fee)
  p.tows = (p.tows or 0) + 1
  p.damage = 0
  local msg
  local pos, dir, idx
  if ph == "event" or ph == "countdown" then
    if p.run.status == "running" or p.run.status == "staged" or p.run.status == "waiting" or p.run.status == "dnf" then
      p.run.status, p.run.dsqReason = "dsq", "towed"
    end
    pos, dir, idx = towDestination(p)
    msg = idx and ("disqualified from " .. curEvent().name .. " and dropped at " .. game.events[idx].name)
          or ("disqualified from " .. curEvent().name)
  elseif ph == "travel" then
    pos, dir, idx = towDestination(p)
    if idx == game.stage then
      p.leg.via = #(curEvent().via or {}) + 1
      p.leg.arrived = true
      p.arrivalRank = 50
      if curEvent().type == "trailer" then requestTrailer(p) end
    end
    msg = "dropped at the start of " .. curEvent().name .. " (no arrival bonus)"
  elseif ph == "finale" then
    pos = v3(cfg.finale.pos)
    if pos then pos.z = pos.z + 0.5 end
    p.leg.arrived, p.finaleTowed, p.drivability = true, true, 0
    msg = "towed to " .. cfg.finale.name .. " - that's 0 drivability at the inspection"
  else
    msg = "repaired where it stands"
  end
  if idx and idx ~= game.stage then p.towDeliveredTo = idx end
  p.towPending = now()
  if not carExists and p.lastVcf then p.faultEditUntil = now() + 15 end   -- the upgrade restore respawns the car
  MP.TriggerClientEvent(p.pid, "tg_tow", Util.JsonEncode({
    reset = carExists, pos = pos, dir = dir,
    config = (not carExists) and p.lastVcf or nil,
  }))
  if #(p.faults or {}) > 0 then sendFaults(p) end   -- unfixed faults come back with the car
  sayAll(string.format("%s calls the tow truck (-%s): %s.", p.name, money(fee), msg))
  pushState(p)
end

local function creditLeft(p) return p.cash + (cfg.workshop.creditLimit or 1500) end
local function overdraftNote(p)
  if p.cash < 0 then say(p.pid, string.format("You're overdrawn: %s (limit %s). Prize money pays it off.", money(p.cash), money(-(cfg.workshop.creditLimit or 1500)))) end
end

-- client -> server after the car was rebuilt: { billable = n, cosmetic = n, vars = bool, valueDelta = number, unknown = n }
function TG_onRebuild(pid, data)
  local p = playerByPid(pid)
  if not p then return end
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  log(string.format("rebuild by %s in phase %s: %s", p.name, game.phase, tostring(data)))
  if game.phase == "idle" or game.phase == "results" then return end
  if game.phase == "dealer" and p.swapAt and now() - p.swapAt < 8 then return end   -- a trim swap, already priced
  if p.faultEditUntil and now() < p.faultEditUntil then return end                   -- the mod's own fault/tow change
  if not inWorkshop(p) then
    if (tonumber(t.billable) or 0) + (tonumber(t.cosmetic) or 0) > 0 or t.vars then
      say(p.pid, "Parts and tuning can only be changed at the dealership or in a workshop - putting it back.")
      p.putBackAt = now()
      MP.TriggerClientEvent(p.pid, "tg_revertparts", "")
    end
    return
  end
  local billable = tonumber(t.billable) or 0
  if billable <= 0 then return end   -- paint, cosmetics, tuning, the mod's own changes: free
  local w = cfg.workshop
  local delta = (tonumber(t.valueDelta) or 0) + (tonumber(t.unknown) or 0) * (w.flatPartPrice or 500)
  local labour = p.wsLabour and 0 or (w.laborFee or 0)
  local partsAmt = math.floor((delta > 0 and delta * (w.partsMarkup or 1) or delta * (w.resaleRate or 0.5)) + 0.5)
  local total = labour + partsAmt
  if total > 0 and total > creditLeft(p) then
    -- over the overdraft limit: refuse, and the player's game takes the parts back off
    p.pendingCharge = { delta = delta, at = now() }
    say(p.pid, string.format("You can't afford that: it costs %s and you have %s (at most %s overdrawn). Taking the parts back off.",
      money(total), money(p.cash), money(w.creditLimit or 1500)))
    log(string.format("credit limit: refused %s for %s (cash %s)", money(total), p.name, money(p.cash)))
    MP.TriggerClientEvent(p.pid, "tg_revertparts", "")
    return
  end
  chargeLabour(p)
  if delta ~= 0 then chargeParts(p, delta) end
  overdraftNote(p)
  pushState(p)
end

-- client -> server: did taking the unaffordable parts back off work? { ok = bool, err }
function TG_onRevertReport(pid, data)
  local p = playerByPid(pid)
  if not (p and p.pendingCharge) then return end
  local ok, t = pcall(Util.JsonDecode, data)
  local pc = p.pendingCharge
  p.pendingCharge = nil
  if ok and type(t) == "table" and t.ok then
    say(p.pid, "The parts are back on the shelf - nothing was charged.")
  else
    -- the game couldn't undo it: the parts stay on and the bill stands (past the limit)
    chargeLabour(p)
    if pc.delta ~= 0 then chargeParts(p, pc.delta) end
    say(p.pid, "Couldn't take the parts back off, so the bill stands: " .. money(p.cash) .. ".")
    log("revert failed for " .. p.name .. ": " .. tostring(ok and type(t) == "table" and t.err or data))
  end
  pushState(p)
end

-- client -> server: { damage = number, partsValue = number|nil }
function TG_onReport(pid, data)
  local p = playerByPid(pid)
  if not p then return end
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  if tonumber(t.damage) then
    local before, nowDmg = p.damage or 0, tonumber(t.damage)
    local paidRecently = p.repairPending and now() - p.repairPending < 10
    local rebuiltOutside = p.putBackAt and now() - p.putBackAt < 15
    if (game.phase == "workshop" or rebuiltOutside) and not paidRecently and before >= (cfg.economy.repairMinDamage or 50)
       and nowDmg < before * 0.2 then
      -- the car got repaired (a part change rebuilds it, or a reset): bill what the repair would have cost
      local cost = math.floor(cfg.economy.repairBaseFee + math.min(before * cfg.economy.repairCostPerDamage, cfg.economy.repairCap) + 0.5)
      p.cash = p.cash - cost
      spend(p, "repairs", cost)
      say(p.pid, string.format("Your car was rebuilt%s, which repaired its damage - billed as a repair: -%s.",
        game.phase == "workshop" and " in the workshop" or "", money(cost)))
      log(string.format("workshop: %s's damage dropped %d -> %d, billed repair %s", p.name, math.floor(before), math.floor(nowDmg), money(cost)))
    end
    p.damage = nowDmg
  end
  if tonumber(t.fuel) then p.fuel = tonumber(t.fuel) end
  if tonumber(t.cargo) then p.cargoFrac = tonumber(t.cargo) end
  local r = p.run
  if r and r.sampleAfter and now() >= r.sampleAfter and r.endDamage == nil then
    r.endDamage, r.endFuel = p.damage, p.fuel   -- finish reading for fragile / economy scoring
  end
  if tonumber(t.partsValue) then
    p.partsValue = tonumber(t.partsValue)

  end
end

---------------------------------------------------------------------------
-- Chat commands
---------------------------------------------------------------------------
-- the admin's vehicles, their own challenge car first (so traffic they spawned never moves a course point)
local function adminVehicles(pid)
  local list, own = {}, nil
  local p = playerByPid(pid)
  if p and p.carVid then own = p.carVid; list[1] = own end
  local rest = {}
  for vid in pairs(MP.GetPlayerVehicles(pid) or {}) do if vid ~= own then rest[#rest + 1] = vid end end
  table.sort(rest)
  for _, vid in ipairs(rest) do list[#list + 1] = vid end
  return ipairs(list)
end

local function adminPos(pid)
  for _, vid in adminVehicles(pid) do
    local raw = MP.GetPositionRaw(pid, vid)
    local pos = type(raw) == "table" and v3(raw.pos)
    if pos then return roundPos(pos) end
  end
  return nil
end

local function adminPose(pid)
  for _, vid in adminVehicles(pid) do
    local raw = MP.GetPositionRaw(pid, vid)
    local pos = type(raw) == "table" and v3(raw.pos)
    if pos then return roundPos(pos), yawFromQuat(raw.rot) end
  end
  return nil
end

local function eventArg(pid, s, allowFinale)
  if allowFinale and s == "finale" then return cfg.finale, "finale" end
  local n = tonumber(s)
  if n and cfg.events[n] then return cfg.events[n], "event " .. n end
  say(pid, "Give an event number 1-" .. #cfg.events .. (allowFinale and " or 'finale'" or ""))
  return nil
end

local function fmtPos(p) return string.format("(%.1f, %.1f, %.1f)", p.x, p.y, p.z) end

local function sortedPlayers()
  local list = {}
  for _, p in pairs(game.players) do list[#list + 1] = p end
  table.sort(list, function(a, b)
    if a.points ~= b.points then return a.points > b.points end
    if a.wins ~= b.wins then return a.wins > b.wins end
    return a.cash > b.cash
  end)
  return list
end

local PLAYER_CMDS, ADMIN_CMDS = {}, {}

PLAYER_CMDS.help = function(pid, name)
  say(pid, "/tg theme (menu colours on/off) | /tg lights (show/hide to position the box) | lightstest shows the sequence | /tg flag (position the finish flag) | flagtest | Trailer event: /tg hitchup couples your trailer | /tg partsdiag shows what the game reports about your parts")
  say(pid, "Respawn your car: /tg respawn (free at the dealership, repair price in a workshop, otherwise " ..
    money(cfg.economy.respawnFee or 2000) .. ")")
  say(pid, "Stuck? /tg unstick (free, when stopped) | /tg tow (" .. money(cfg.economy.towFee) .. ", full repair, DSQ from a running event)")
  say(pid, "Problem cars: /tg faults | fault take <id> | fault undo <id> | fix <id> (workshop)")
  say(pid, "/tg menu (window; /tg menu reset if it's squashed) | status | dealer | join | ready | go | quote | repair | standings | diag")
  if isAdmin(name) then
    say(pid, "Admin: /tg start [force] | next (force the next phase) | stop | where | workshop <minutes> | workshopevery <n>")
    say(pid, "Traffic: /tg traffic on|off - while on, what you spawn is non-scoring traffic (any phase) and your vehicle menu is open")
    say(pid, "Faults: /tg fault test [id] (applies to your car) | fault testoff")
    say(pid, "Money: /tg budget <amount> | setcash <name> <amount> | give <name> <amount> | importprices [models] | gameprices on|off")
    say(pid, "Course: /tg setstart <n> | addcp <n> | undocp <n> | clearcp <n> | settrap <n> | settype <n> <type> | settime <n> <s>")
    say(pid, "Parking: /tg addbay <n> | undobay <n> | clearbays <n>  (park facing the way the bay faces)")
    say(pid, "Workshops: /tg importgas | addworkshop [name] | undoworkshop | clearworkshops  (none = anywhere)")
    say(pid, "Session: /tg addevent <type> [name] | delevent <n> | enable <n> on|off | moveevent <n> up|down | setlaps <n> <laps>")
    say(pid, "Trailers: /tg trailersave (sit in your built trailer) | trailercones | trailertest [off]")
    say(pid, "        /tg addvia <n|finale> | clearvia <n|finale> | setfinale | rename <n|finale> <name> | courses | save")
    say(pid, "        /tg undovia <n|finale> | clearcourse <n|finale|all> | reload (undo unsaved changes)")
    say(pid, "Library: /tg course list | save <name> | load <name> | new <name> | delete <name>")
  end
end

PLAYER_CMDS.status = function(pid)
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge. Phase: " .. game.phase); return end
  say(pid, string.format("%s | %s | Cash %s | %.1f pts | %d win%s | Damage %d", phaseTitle(), p.carName or "no car",
    money(p.cash), p.points, p.wins, p.wins == 1 and "" or "s", math.floor(p.damage or 0)))
end

local function listedModels()
  local seen, out = {}, {}
  for _, c in ipairs(cfg.dealer.cars) do
    if not seen[c.model] then seen[c.model] = true; out[#out + 1] = c end
  end
  return out
end

local function trimsFor(model, budget)  -- affordable trims sorted by price, plus hidden count
  local list, hidden = {}, 0
  for key, e in pairs((cfg.dealer.gamePrices or {})[model] or {}) do
    local price = tonumber(e.price)
    if price and price <= budget then list[#list + 1] = { config = key, name = e.name or key, price = price }
    elseif price then hidden = hidden + 1 end
  end
  table.sort(list, function(a, b) return a.price < b.price end)
  return list, hidden
end

PLAYER_CMDS.dealer = function(pid, _, args)
  local p = playerByPid(pid)
  local budget = playerBudget(p)
  local want = args[3] and args[3]:lower()
  say(pid, "DEALERSHIP - budget " .. money(budget) .. (p and (", you have " .. money(p.cash)) or ""))

  if not cfg.dealer.useGamePrices then
    local hidden = 0
    for _, c in ipairs(cfg.dealer.cars) do
      if c.price <= budget then
        say(pid, string.format("  %s - %s%s", c.name, money(c.price), (c.config and c.config ~= "") and (" [" .. c.config .. "]") or ""))
      else hidden = hidden + 1 end
    end
    if hidden > 0 then say(pid, string.format("(%d over-budget car%s hidden)", hidden, hidden == 1 and "" or "s")) end
    if not cfg.dealer.strictConfigs then say(pid, "(Any stock configuration of a listed model sells at that price.)") end
    return
  end

  if want then
    local listed = modelListed(want)
    if not listed then say(pid, "No model '" .. want .. "' here. /tg dealer for the list."); return end
    local trims, hidden = trimsFor(want, budget)
    if #trims == 0 then say(pid, "  Nothing from " .. listed.name .. " fits the budget.") end
    for _, t in ipairs(trims) do say(pid, string.format("  %s  %s", money(t.price), t.name)) end
    if hidden > 0 then say(pid, string.format("(%d over-budget trim%s hidden)", hidden, hidden == 1 and "" or "s")) end
    return
  end

  local totalHidden = 0
  for _, c in ipairs(listedModels()) do
    local trims, hidden = trimsFor(c.model, budget)
    totalHidden = totalHidden + hidden
    if #trims > 0 then
      local range = (#trims == 1) and money(trims[1].price) or (money(trims[1].price) .. " to " .. money(trims[#trims].price))
      say(pid, string.format("  %s (%s) - %s, %s", c.name, c.model, plural(#trims, "trim"), range))
    end
  end
  if totalHidden > 0 then say(pid, string.format("(%d over-budget trims hidden)", totalHidden)) end
  say(pid, "/tg dealer <model> lists that car's trims, e.g. /tg dealer covet")
end

PLAYER_CMDS.join = function(pid, name)
  if game.phase ~= "dealer" then say(pid, "You can only join while the dealership is open."); return end
  if game.players[name] then game.players[name].pid = pid; say(pid, "You're already in."); return end
  game.players[name] = newPlayer(name, pid)
  sayAll(name .. " joins the challenge with " .. money(cfg.economy.startingCash) .. ".")
  pushState(game.players[name])
end

PLAYER_CMDS.ready = function(pid)
  local p = playerByPid(pid)
  if not p or game.phase ~= "dealer" then say(pid, "Nothing to be ready for right now."); return end
  if not p.carVid then say(pid, "Buy a car first!"); return end
  p.ready = true
  sayAll(string.format("%s is happy with their %s.", p.name, p.carName))
  for _, q in pairs(game.players) do if q.pid and not q.ready then return end end
  lockDealer()
end

PLAYER_CMDS.quote = function(pid)
  local p = playerByPid(pid)
  if not p then return end
  local rq = repairQuote(p)
  say(pid, string.format("Repair: %s (damage %d). Spent in this workshop so far: %s. Cash: %s", rq > 0 and money(rq) or "nothing to fix",
    math.floor(p.damage or 0), money(upgradeBill(p)), money(p.cash)))
end

PLAYER_CMDS.repair = function(pid)
  local p = playerByPid(pid)
  if not p or not p.carVid then say(pid, "You don't have a car here."); return end
  if game.phase ~= "workshop" then say(pid, "The workshop is closed."); return end
  if not inWorkshop(p) then say(pid, "Drive to a workshop first - the arrows show the nearest."); return end
  local cost = repairQuote(p)
  if cost <= 0 then say(pid, "Your car doesn't need repairs."); return end
  if cost > creditLeft(p) then say(pid, string.format("Repairs cost %s - you have %s (at most %s overdrawn).", money(cost), money(p.cash), money(cfg.workshop.creditLimit or 1500))); return end
  p.cash = p.cash - cost
  spend(p, "repairs", cost)
  p.repairPending = now()  -- the repair's own reset is excused for a few seconds only
  p.damage = 0
  MP.TriggerClientEvent(p.pid, "tg_repair", "")
  sayAll(string.format("%s paid %s to have their %s repaired.", p.name, money(cost), p.carName))
  overdraftNote(p)
  pushState(p)
end

PLAYER_CMDS.diag = function(pid)
  say(pid, "Asking your client mod for a report...")
  pendingDiag[pid] = now()
  MP.TriggerClientEvent(pid, "tg_diag", "")
end

function TG_onDiag(pid, data)
  pendingDiag[pid] = nil
  log("diag from " .. tostring(MP.GetPlayerName(pid)) .. ": " .. tostring(data))
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then say(pid, "Client replied, but the report was unreadable."); return end
  local function yn(v) if v == nil then return "?" end return v and "yes" or "NO" end
  local p = playerByPid(pid)
  say(pid, string.format("Server v%s, client mod v%s. The client sees phase '%s' (server: '%s').",
    SERVER_VERSION, tostring(t.version), tostring(t.phase), game.phase))
  say(pid, "Target: " .. tostring(t.target or "none") .. (p and "" or " (you're not in the challenge)"))
  say(pid, string.format("Arrows via: %s | groundMarkers loaded %s, setPath %s, setFocus %s, bigmap %s | route active: %s",
    tostring(t.pathMethod or "NONE"), yn(t.gmLoaded), yn(t.gmSetPath), yn(t.gmSetFocus), yn(t.bigMap), yn(t.hasTarget)))
  say(pid, string.format("Challenge car %s -> game id %s, you're driving id %s",
    tostring(t.carId or "none"), tostring(t.carFound or "none"), tostring(t.playerVeh or "none")))
  for _, e in ipairs(t.errors or {}) do say(pid, "Client error: " .. tostring(e)) end
end

PLAYER_CMDS.go = function(pid)
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  if game.phase == "countdown" or game.phase == "event" then say(pid, "It's already under way!"); return end
  if game.phase ~= "travel" then say(pid, "There's no event waiting to start."); return end
  local e = curEvent()
  local start = v3(e.start)
  local r = (e.startRadius or cfg.defaults.startRadius) + 5
  local waiting, away = {}, {}
  for _, q in pairs(game.players) do
    if racing(q) then
      local d = (q.pos and start) and dist(q.pos, start) or nil
      local where = d and (d >= 1000 and string.format(" (%.1f km)", d / 1000) or string.format(" (%d m)", math.floor(d))) or ""
      if not q.leg.arrived then waiting[#waiting + 1] = q.name .. where
      elseif d and d > r then away[#away + 1] = q.name .. where end
    end
  end
  if #waiting > 0 then say(pid, "Can't start yet - still waiting for: " .. table.concat(waiting, ", ")); return end
  if #away > 0 then say(pid, "Everyone back to the start line first: " .. table.concat(away, ", ")); return end
  sayAll(string.format("%s calls it - %s is on!", p.name, e.name))
  beginCountdown()
end

local testRestore = {}   -- pid -> restore data from an admin fault test

PLAYER_CMDS.faults = function(pid)
  if not faultsOn() then say(pid, "Problem cars are switched off."); return end
  local p = playerByPid(pid)
  say(pid, string.format("PROBLEM CARS - take up to %d for extra cash; a workshop fix costs %sx the payout.",
    cfg.faults.maxPerCar, tostring(cfg.faults.fixMultiplier)))
  for _, f in ipairs(cfg.faults.list) do
    say(pid, string.format("  [%s] %s  +%s  (fix %s)%s", f.id, f.name, money(f.payout), money(fixCost(f)),
      (p and hasFault(p, f.id)) and "  <- yours" or ""))
  end
  say(pid, "/tg fault take <id> | /tg fault undo <id> at the dealership, /tg fix <id> in a workshop")
end

PLAYER_CMDS.fault = function(pid, name, args)
  if not faultsOn() then say(pid, "Problem cars are switched off."); return end
  local sub, id = (args[3] or ""):lower(), (args[4] or ""):lower()
  if sub == "test" or sub == "testoff" then
    if not isAdmin(name) then say(pid, "That's an admin command."); return end
    local list = {}
    if sub == "test" then
      for _, f in ipairs(cfg.faults.list) do
        if id == "" or id == f.id then list[#list + 1] = { id = f.id, factor = f.factor } end
      end
    end
    say(pid, sub == "test" and ("Applying " .. #list .. " test fault(s) to your current car...") or "Removing test faults...")
    MP.TriggerClientEvent(pid, "tg_faults", Util.JsonEncode({ faults = list, restore = testRestore[pid] or {}, test = true }))
    return
  end
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  if game.phase ~= "dealer" then say(pid, "Faults can only be taken or handed back at the dealership. Fix them in a workshop: /tg fix <id>"); return end
  local f = faultDef(id)
  if not f then say(pid, "No fault '" .. id .. "'. /tg faults for the list."); return end
  if sub == "take" then
    if hasFault(p, id) then say(pid, "You already took that one."); return end
    if #p.faults >= (cfg.faults.maxPerCar or 3) then say(pid, "That's the limit - " .. cfg.faults.maxPerCar .. " faults per car."); return end
    p.faults[#p.faults + 1] = id
    p.cash = p.cash + f.payout
    spend(p, "faultCash", f.payout)
    sayAll(string.format("%s takes a car with %s for an extra %s.", p.name, f.name:lower(), money(f.payout)))
  elseif sub == "undo" then
    if not removeFault(p, id) then say(pid, "You haven't taken that one."); return end
    p.cash = p.cash - f.payout
    spend(p, "faultCash", -f.payout)
    say(pid, string.format("Handed back %s - no more %s.", money(f.payout), f.name:lower()))
  else
    say(pid, "Usage: /tg fault take <id> | /tg fault undo <id>"); return
  end
  if p.carVid then sendFaults(p) end
  pushState(p)
end

PLAYER_CMDS.fix = function(pid, _, args)
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  if game.phase ~= "workshop" then say(pid, "Faults can only be fixed in a workshop."); return end
  if not inWorkshop(p) then say(pid, "Drive to a workshop first - the arrows show the nearest."); return end
  local id = (args[3] or ""):lower()
  local f = faultDef(id)
  if not (f and hasFault(p, id)) then say(pid, "Your car doesn't have that fault. Yours: " .. table.concat(p.faults, ", ")); return end
  local cost = fixCost(f)
  if cost > creditLeft(p) then say(pid, string.format("Fixing that costs %s - you have %s (at most %s overdrawn).", money(cost), money(p.cash), money(cfg.workshop.creditLimit or 1500))); return end
  removeFault(p, id)
  p.cash = p.cash - cost
  spend(p, "faultFixes", cost)
  p.faultsFixed = (p.faultsFixed or 0) + 1
  sayAll(string.format("%s pays %s to have the %s sorted.", p.name, money(cost), f.name:lower()))
  sendFaults(p)
  pushState(p)
end

-- client -> server: { results = { id = "ok" | "unavailable" | "error: ..." }, restore = {...}, test = bool }
function TG_onFaultReport(pid, data)
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  if t.test then
    testRestore[pid] = t.restore
    for id, st in pairs(t.results or {}) do say(pid, "Fault test - " .. tostring(id) .. ": " .. tostring(st)) end
    return
  end
  local p = playerByPid(pid)
  if not p then return end
  if type(t.restore) == "table" then p.faultRestore = t.restore end
  local changed = false
  for id, st in pairs(t.results or {}) do
    if st ~= "ok" and st ~= "removed" and hasFault(p, id) then
      local f = faultDef(id)
      removeFault(p, id)
      p.cash = p.cash - (f and f.payout or 0)
      spend(p, "faultCash", -(f and f.payout or 0))
      say(p.pid, string.format("'%s' can't be applied to your %s (%s) - removed, and the %s is handed back.",
        f and f.name or id, p.carName or "car", tostring(st), money(f and f.payout or 0)))
      log(string.format("fault %s failed for %s: %s", tostring(id), p.name, tostring(st)))
      changed = true
    end
  end
  if changed then sendFaults(p); pushState(p) end
end

PLAYER_CMDS.menu = function(pid, _, args)
  local reset = args[3] and args[3]:lower() == "reset"
  MP.TriggerClientEvent(pid, "tg_menu", reset and "reset" or "")
end

local TOW_PHASES = { travel = true, countdown = true, event = true, finale = true }

PLAYER_CMDS.tow = function(pid)
  local p = playerByPid(pid)
  if not (p and p.carVid) then say(pid, "You don't have a car out to tow - respawn it from the vehicle menu (that counts as a tow)."); return end
  if not TOW_PHASES[game.phase] then say(pid, game.phase == "workshop" and "You're in the workshop - use /tg repair." or "No tow truck needed right now."); return end
  if p.finaleTowed or (game.phase == "finale" and p.leg.arrived) then say(pid, "You've already finished."); return end
  performTow(p, true)
end

PLAYER_CMDS.respawn = function(pid)
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  if not p.carVid then
    if not p.carModel then say(pid, "You haven't bought a car yet."); return end
    -- the car was lost: spawn it again here (that's a tow, as before: upgrades restored, tow fee)
    say(pid, "Bringing your " .. (p.carName or "car") .. " back - a lost car counts as a tow.")
    MP.TriggerClientEvent(pid, "tg_respawn", Util.JsonEncode({ spawn = true, model = p.carModel,
      config = p.carConfig and ("vehicles/" .. p.carModel .. "/" .. p.carConfig .. ".pc") or nil }))
    return
  end
  local ph = game.phase
  if ph == "idle" or ph == "dealer" or ph == "results" then
    p.respawnPending = now()
    MP.TriggerClientEvent(pid, "tg_respawn", Util.JsonEncode({ reset = true }))
    say(pid, "Respawning your car.")
    return
  end
  if ph == "workshop" and inWorkshop(p) then   -- the repair it causes is billed like any workshop repair (damage drop)
    p.respawnPending = now()
    MP.TriggerClientEvent(pid, "tg_respawn", Util.JsonEncode({ reset = true }))
    say(pid, "Respawning your car - in the workshop that's billed as a normal repair.")
    return
  end
  if p.finaleTowed or (ph == "finale" and p.leg.arrived) then say(pid, "You've already finished."); return end
  local fee = cfg.economy.respawnFee or cfg.economy.towFee or 2000
  p.cash = p.cash - fee
  spend(p, "towCost", fee)
  p.respawns = (p.respawns or 0) + 1
  p.damage, p.respawnPending = 0, now()
  local extra = ""
  if (ph == "event" or ph == "countdown") and (p.run.status == "running" or p.run.status == "staged" or p.run.status == "waiting") then
    p.run.status, p.run.dsqReason = "dsq", "respawned"
    extra = " - disqualified from " .. curEvent().name
  elseif ph == "finale" then
    p.finaleRebuilt = true
    extra = " - a fresh car scores 0 drivability at the inspection"
  end
  MP.TriggerClientEvent(pid, "tg_respawn", Util.JsonEncode({ reset = true }))
  sayAll(string.format("%s respawns their %s on the spot (-%s)%s.", p.name, p.carName or "car", money(fee), extra))
  pushState(p)
end

PLAYER_CMDS.unstick = function(pid)
  local p = playerByPid(pid)
  if not (p and p.carVid) then say(pid, "You don't have a car out."); return end
  if game.phase == "idle" or game.phase == "countdown" then say(pid, "Not during the countdown."); return end
  if (p.speed or 0) > (cfg.economy.unstickMaxSpeed or 3) then say(pid, "Stop first - unstick only works when you're (nearly) stationary."); return end
  local cd = cfg.economy.unstickCooldown or 15
  if p.lastUnstick and now() - p.lastUnstick < cd then
    say(pid, string.format("Unstick is cooling down - try again in %d s.", math.ceil(cd - (now() - p.lastUnstick)))); return
  end
  p.lastUnstick, p.unstickPending, p.unstickRepairQuote = now(), now(), repairQuote(p)
  MP.TriggerClientEvent(pid, "tg_unstick", "")
end

-- client -> server: { kind = "tow"|"unstick", ok = bool, method = string, detail = string }
function TG_onMoveReport(pid, data)
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  log(string.format("%s %s by %s: %s (%s)", tostring(t.kind), t.ok and "ok" or "FAILED", tostring(MP.GetPlayerName(pid)),
    tostring(t.method), tostring(t.detail)))
  if not t.ok then
    say(pid, string.format("Couldn't move your car for the %s (%s). Tell the admin - /tg diag has details.", tostring(t.kind), tostring(t.detail)))
  elseif t.kind == "unstick" then
    say(pid, "Unstuck - carry on.")
  end
end

PLAYER_CMDS.hitchup = function(pid)
  local p = playerByPid(pid)
  if not (p and p.carVid) then say(pid, "You don't have a car out."); return end
  MP.TriggerClientEvent(pid, "tg_hitchup", "")
  say(pid, "Coupling... reverse so your hitch is right at the trailer's coupler if it doesn't latch.")
end

PLAYER_CMDS.theme = function(pid)
  MP.TriggerClientEvent(pid, "tg_theme", "")
end

PLAYER_CMDS.lights = function(pid)
  MP.TriggerClientEvent(pid, "tg_lightspin", "")
  say(pid, "Starting lights box toggled - drag it where you want it (its title bar), then /tg lights again to hide it.")
end

PLAYER_CMDS.lightstest = function(pid)
  MP.TriggerClientEvent(pid, "tg_lightstest", "")
  say(pid, "Starting lights test - watch the top of the screen.")
end

PLAYER_CMDS.flag = function(pid)
  MP.TriggerClientEvent(pid, "tg_flagpin", "")
  say(pid, "Finish flag box toggled - drag it where you want it (its title bar), then /tg flag again to hide it.")
end

PLAYER_CMDS.flagtest = function(pid)
  MP.TriggerClientEvent(pid, "tg_flagtest", "")
  say(pid, "Finish flag test - it shows for 6 seconds.")
end

PLAYER_CMDS.standings = function(pid)
  if game.phase == "idle" then say(pid, "No challenge running."); return end
  for i, p in ipairs(sortedPlayers()) do
    say(pid, string.format("%s  %s - %.1f pts, %d win%s, %s", ordinal(i), p.name, p.points, p.wins,
      p.wins == 1 and "" or "s", money(p.cash)))
  end
end

ADMIN_CMDS.start = function(pid, _, args)
  if game.phase ~= "idle" then say(pid, "Already running - /tg stop first."); return end
  startGame(pid, args[3] == "force")
end

ADMIN_CMDS.traffic = function(pid, name, args)
  local want = (args[3] or ""):lower()
  local on
  if want == "on" then on = true elseif want == "off" then on = false else on = not trafficMode[name] end
  trafficMode[name] = on or nil
  if on then
    say(pid, "Traffic mode ON: everything you spawn now is non-scoring traffic (AI traffic, parked cars), in any phase, " ..
      "and your vehicle menu is unlocked. Your own car, cash and score are untouched. /tg traffic off when you're done.")
    local p = playerByPid(pid)
    if p and game.phase == "dealer" and not p.carVid then
      say(pid, "Heads-up: you haven't bought your own car yet - while traffic mode is on, a car you spawn is traffic, not a purchase.")
    end
  else
    say(pid, "Traffic mode OFF: spawning is back to the challenge rules. The traffic you placed stays.")
  end
  log(string.format("traffic mode %s for %s", on and "on" or "off", name))
  local p = playerByPid(pid)
  if p then pushState(p) end
end

ADMIN_CMDS.stop = function()
  stopGame(); sayAll("Challenge stopped by admin.")
end

ADMIN_CMDS.next = function(pid)
  local ph = game.phase
  if ph == "dealer" then lockDealer()
  elseif ph == "travel" then beginCountdown()
  elseif ph == "countdown" then startEvent()
  elseif ph == "event" and game.solo and game.solo.runner then
    local r = game.solo.runner
    r.run.status = "dnf"
    sayAll("The producers end " .. r.name .. "'s run.")
    nextSoloRunner()
  elseif ph == "event" then sayAll("The producers have called time."); closeEvent()
  elseif ph == "workshop" then endWorkshop()
  elseif ph == "finale" then showResults()
  else say(pid, "Nothing to advance.") end
end

ADMIN_CMDS.give = function(pid, _, args)
  local amount = tonumber(args[#args])
  local target = table.concat(args, " ", 3, #args - 1)
  local p = game.players[target]
  if not (p and amount) then say(pid, "Usage: /tg give <player name> <amount>"); return end
  p.cash = p.cash + amount
  sayAll(string.format("The producers give %s %s.", p.name, money(amount)))
  pushState(p)
end

finishImport = function()
  local imp = pendingImport
  pendingImport = nil
  if not imp then return end
  for m in pairs(imp.waiting) do imp.failed[#imp.failed + 1] = m .. " (no reply)" end
  for _, f in ipairs(imp.failed) do say(imp.pid, "  Couldn't import " .. f) end
  if imp.imported > 0 then
    cfg.dealer.useGamePrices = true
    saveConfig()
    say(imp.pid, string.format("Imported %s%s. Game prices are ON and saved to config.json.",
      plural(imp.imported, "trim price"), imp.skipped > 0 and string.format(" (%s had no price and %s skipped)",
      plural(imp.skipped, "trim"), imp.skipped == 1 and "was" or "were") or ""))
  else
    say(imp.pid, "Nothing was imported - prices unchanged.")
  end
end

-- client -> server: { model, modelName, configs = { {config, name, price}, ... } | nil, err }
function TG_onImportReply(pid, data)
  local imp = pendingImport
  if not imp or imp.pid ~= pid then return end
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" or not t.model or not imp.waiting[t.model] then return end
  imp.waiting[t.model] = nil
  imp.left = imp.left - 1
  if type(t.configs) ~= "table" or #t.configs == 0 then
    imp.failed[#imp.failed + 1] = t.model .. (t.err and (" (" .. tostring(t.err) .. ")") or " (not found in your game)")
  else
    local prices, n, under, cheapest = {}, 0, 0, nil
    for _, c in ipairs(t.configs) do
      local price = tonumber(c.price)
      if price and c.config then
        price = math.floor(price + 0.5)
        prices[c.config] = { name = c.name or c.config, price = price }
        n = n + 1
        if price <= cfg.economy.startingCash then under = under + 1 end
        cheapest = math.min(cheapest or price, price)
      else
        imp.skipped = imp.skipped + 1
      end
    end
    cfg.dealer.gamePrices = cfg.dealer.gamePrices or {}
    cfg.dealer.gamePrices[t.model] = prices
    imp.imported = imp.imported + n
    local listed = modelListed(t.model)
    if not listed then
      cfg.dealer.cars[#cfg.dealer.cars + 1] = { model = t.model, name = t.modelName or t.model, price = cheapest or 0 }
    elseif t.modelName then
      listed.name = t.modelName
    end
    say(pid, string.format("  %s: %s, %d within the %s budget", t.modelName or t.model, plural(n, "trim"), under, money(cfg.economy.startingCash)))
  end
  if imp.left <= 0 then finishImport() end
end

ADMIN_CMDS.importprices = function(pid, _, args)
  if pendingImport then say(pid, "An import is already running."); return end
  local models = {}
  if #args >= 3 then
    for i = 3, #args do models[#models + 1] = args[i]:lower() end
  else
    for _, c in ipairs(listedModels()) do models[#models + 1] = c.model end
  end
  pendingImport = { pid = pid, waiting = {}, left = #models, started = now(), imported = 0, skipped = 0, failed = {} }
  for _, m in ipairs(models) do pendingImport.waiting[m] = true end
  say(pid, string.format("Reading prices for %d model%s from your game...", #models, #models == 1 and "" or "s"))
  MP.TriggerClientEvent(pid, "tg_import", Util.JsonEncode({ models = models }))
end

ADMIN_CMDS.gameprices = function(pid, _, args)
  local v = args[3] and args[3]:lower()
  if v == "on" then
    if next(cfg.dealer.gamePrices or {}) == nil then say(pid, "Nothing imported yet - run /tg importprices first."); return end
    cfg.dealer.useGamePrices = true
  elseif v == "off" then
    cfg.dealer.useGamePrices = false
  else
    say(pid, "Game prices are " .. (cfg.dealer.useGamePrices and "ON" or "OFF") .. ". Usage: /tg gameprices on|off"); return
  end
  saveConfig()
  say(pid, "Game prices " .. (cfg.dealer.useGamePrices and "ON" or "OFF - using the manual price list") .. " (saved).")
end

ADMIN_CMDS.budget = function(pid, _, args)
  local amount = tonumber(args[3])
  if not amount then say(pid, "Budget is " .. money(cfg.economy.startingCash) .. ". Usage: /tg budget <amount>"); return end
  amount = math.floor(amount)
  if amount < 0 or amount > 10000000 then say(pid, "Pick an amount between $0 and $10,000,000."); return end
  local delta = amount - cfg.economy.startingCash
  if game.phase == "dealer" then
    local over = {}
    for _, p in pairs(game.players) do
      if p.carVid and (p.carPrice or 0) > amount then over[#over + 1] = p.name .. " (" .. money(p.carPrice) .. ")" end
    end
    if #over > 0 then say(pid, "Can't go below cars already bought: " .. table.concat(over, ", ")); return end
    for _, p in pairs(game.players) do p.cash = p.cash + delta end
  end
  cfg.economy.startingCash = amount
  saveConfig()
  if game.phase == "dealer" then pushAll() end
  local note = ""
  if game.phase == "dealer" then note = " - everyone's cash has been adjusted"
  elseif game.phase ~= "idle" then note = " (applies from the next challenge)" end
  sayAll("The producers set the budget to " .. money(amount) .. note .. ".")
end

ADMIN_CMDS.workshop = function(pid, _, args)
  local mins = tonumber(args[3])
  if not mins then say(pid, "Workshop time is " .. tostring(cfg.workshop.minutes) .. " min. Usage: /tg workshop <minutes>"); return end
  if mins < 0.5 or mins > 120 then say(pid, "Pick between 0.5 and 120 minutes."); return end
  local delta = (mins - cfg.workshop.minutes) * 60
  cfg.workshop.minutes = mins
  saveConfig()
  if game.phase == "workshop" then
    game.workshopEnd = game.workshopEnd + delta
    game.warned = (game.workshopEnd - now()) <= 60
    local left = math.max(0, game.workshopEnd - now())
    sayAll(string.format("Workshop time changed to %s min - %d:%02d left in this one.", tostring(mins), math.floor(left / 60), math.floor(left % 60)))
    pushAll()
  else
    say(pid, "Workshop time set to " .. tostring(mins) .. " min (saved).")
  end
end

ADMIN_CMDS.workshopevery = function(pid, _, args)
  local n = tonumber(args[3])
  if not n then say(pid, "A workshop comes after every " .. tostring(cfg.workshopEvery or 2) .. " events. Usage: /tg workshopevery <n> (0 = none)"); return end
  n = math.max(0, math.floor(n))
  cfg.workshopEvery = n
  saveConfig()
  say(pid, n == 0 and "Workshops switched off (saved)." or ("A workshop now comes after every " .. n .. " events (never after the last). Saved."))
end

ADMIN_CMDS.setcash = function(pid, _, args)
  local amount = tonumber(args[#args])
  local target = table.concat(args, " ", 3, #args - 1)
  local p = game.players[target]
  if #args < 4 or not (p and amount) then say(pid, "Usage: /tg setcash <player name> <amount>"); return end
  p.cash = math.floor(amount)
  sayAll(string.format("The producers set %s's cash to %s.", p.name, money(p.cash)))
  pushState(p)
end

ADMIN_CMDS.where = function(pid)
  local pos = adminPos(pid)
  say(pid, pos and fmtPos(pos) or "Spawn a vehicle first.")
end

local function withPos(pid, fn)
  local pos = adminPos(pid)
  if not pos then say(pid, "Spawn a vehicle and drive to the spot first."); return end
  fn(pos)
end

ADMIN_CMDS.setstart = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  withPos(pid, function(pos) e.start = pos; markDirty(); say(pid, label .. " start set " .. fmtPos(pos) .. " (/tg save)") end)
end
ADMIN_CMDS.addcp = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  withPos(pid, function(pos)
    e.checkpoints = e.checkpoints or {}
    e.checkpoints[#e.checkpoints + 1] = pos
    markDirty()
    say(pid, string.format("%s checkpoint %d set %s - the last one is the finish (/tg save)", label, #e.checkpoints, fmtPos(pos)))
  end)
end
ADMIN_CMDS.undocp = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  if e.checkpoints and #e.checkpoints > 0 then table.remove(e.checkpoints); markDirty() end
  say(pid, label .. " now has " .. #(e.checkpoints or {}) .. " checkpoints.")
end
ADMIN_CMDS.clearcp = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  e.checkpoints = {}; markDirty(); say(pid, label .. " checkpoints cleared.")
end
ADMIN_CMDS.settrap = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  withPos(pid, function(pos) e.trap = pos; markDirty(); say(pid, label .. " speed trap set " .. fmtPos(pos) .. " (/tg save)") end)
end
ADMIN_CMDS.settype = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  local t = (args[4] or ""):lower()
  if t == "timetrial" then   -- the old type: a destination race in time trial mode
    e.type, e.solo = "race", true
    markDirty()
    say(pid, label .. " is now a destination race in time trial mode (one at a time). Time trial is a mode now: /tg setmode " ..
      tostring(args[3]) .. " race|trial.")
    return
  end
  if not TYPE_INFO[t] then say(pid, "Type must be one of: " .. table.concat(TYPE_ORDER, ", ")); return end
  e.type, e.solo = t, nil
  markDirty()
  say(pid, string.format("%s is now a %s, in %s.", label, TYPE_INFO[t].label:lower(), modeLabel(e)))
end
ADMIN_CMDS.setmode = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  local m = (args[4] or ""):lower()
  local solo
  if m == "race" or m == "together" then solo = false
  elseif m == "trial" or m == "timetrial" or m == "solo" then solo = true
  else say(pid, "Usage: /tg setmode <event> race|trial  (race = everyone at once, trial = one at a time)"); return end
  if (game.phase == "countdown" or game.phase == "event") and curEvent() == e then
    say(pid, "That event is running right now - change its mode after it's finished."); return
  end
  e.solo = solo
  markDirty()
  say(pid, string.format("%s now runs in %s.", label, modeLabel(e)))
end
ADMIN_CMDS.addvia = function(pid, _, args)
  local e, label = eventArg(pid, args[3], true); if not e then return end
  withPos(pid, function(pos)
    e.via = e.via or {}
    e.via[#e.via + 1] = pos
    markDirty()
    say(pid, string.format("Route to %s: waypoint %d set %s (/tg save)", label, #e.via, fmtPos(pos)))
  end)
end
ADMIN_CMDS.clearvia = function(pid, _, args)
  local e, label = eventArg(pid, args[3], true); if not e then return end
  e.via = {}; markDirty(); say(pid, "Route waypoints to " .. label .. " cleared.")
end
ADMIN_CMDS.setlaps = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  local n = tonumber(args[4])
  if not n or n < 1 or n > 50 then say(pid, "Usage: /tg setlaps <event> <1-50>"); return end
  e.laps = math.floor(n)
  markDirty()
  say(pid, string.format("%s: %d lap%s (/tg course save)%s", label, e.laps, e.laps == 1 and "" or "s",
    e.type ~= "circuit" and " - note: laps only count on a circuit race" or ""))
end

local function placeBay(pid, e, label, replace)
  local pos, yaw = adminPose(pid)
  if not pos then say(pid, "Park your car in the bay, facing the way it should face, first."); return end
  local bay = { x = pos.x, y = pos.y, z = pos.z, yaw = yaw and math.floor(yaw * 10 + 0.5) / 10 or nil }
  e.bays = replace and {} or eventBays(e)
  e.bay = nil
  e.bays[#e.bays + 1] = bay
  markDirty()
  say(pid, string.format("%s bay %d set %s%s (/tg course save)", label, #e.bays, fmtPos(pos),
    yaw and string.format(", heading %.0f deg", yaw) or " (heading unavailable - straightness won't be scored)"))
end
ADMIN_CMDS.addbay = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  placeBay(pid, e, label, false)
end
ADMIN_CMDS.setbay = function(pid, _, args)   -- replaces all bays with this one
  local e, label = eventArg(pid, args[3]); if not e then return end
  placeBay(pid, e, label, true)
end
ADMIN_CMDS.undobay = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  e.bays, e.bay = eventBays(e), nil
  if #e.bays > 0 then table.remove(e.bays); markDirty() end
  say(pid, label .. " now has " .. #e.bays .. " bay(s).")
end
ADMIN_CMDS.clearbays = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  e.bays, e.bay = {}, nil
  markDirty()
  say(pid, label .. " bays cleared.")
end
ADMIN_CMDS.settime = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  local n = tonumber(args[4])
  if not n or n < 10 or n > 3600 then say(pid, "Usage: /tg settime <event> <10-3600 seconds>"); return end
  e.timeLimit = math.floor(n)
  markDirty()
  say(pid, string.format("%s time limit: %s%s (/tg course save)", label, fmtTime(e.timeLimit),
    isSolo(e) and " per run" or ""))
end

ADMIN_CMDS.addevent = function(pid, _, args)
  local t = (args[3] or ""):lower()
  if not TYPE_INFO[t] then say(pid, "Usage: /tg addevent <" .. table.concat(TYPE_ORDER, "|") .. "> [name]"); return end
  local name = table.concat(args, " ", 4)
  if name == "" then name = TYPE_INFO[t].name end
  local base, n = name, 1
  local function taken(nm) for _, e in ipairs(cfg.events) do if e.name == nm then return true end end return false end
  while taken(name) do n = n + 1; name = base .. " " .. n end
  cfg.events[#cfg.events + 1] = { name = name, type = t, via = {}, checkpoints = {}, enabled = true, timeLimit = 600, ttMigrated = true }
  markDirty()
  say(pid, string.format("Added event %d: %s (%s). Drive out and place it in the course builder.", #cfg.events, name, TYPE_INFO[t].label:lower()))
end

ADMIN_CMDS.delevent = function(pid, _, args)
  if game.phase ~= "idle" then say(pid, "Stop the challenge before removing events."); return end
  local n = tonumber(args[3])
  if not (n and cfg.events[n]) then say(pid, "Usage: /tg delevent <n>"); return end
  local e = table.remove(cfg.events, n)
  markDirty()
  say(pid, "Removed event " .. n .. ": " .. e.name)
end

ADMIN_CMDS.enable = function(pid, _, args)
  if game.phase ~= "idle" then say(pid, "The session is locked while a challenge runs."); return end
  local n, v = tonumber(args[3]), (args[4] or ""):lower()
  if not (n and cfg.events[n]) or (v ~= "on" and v ~= "off") then say(pid, "Usage: /tg enable <n> on|off"); return end
  cfg.events[n].enabled = (v == "on")
  markDirty()
  say(pid, string.format("%s is %s for the session (%d event%s on).", cfg.events[n].name, v == "on" and "ON" or "off",
    #enabledEvents(), #enabledEvents() == 1 and "" or "s"))
end

ADMIN_CMDS.moveevent = function(pid, _, args)
  if game.phase ~= "idle" then say(pid, "The session is locked while a challenge runs."); return end
  local n, dir = tonumber(args[3]), (args[4] or ""):lower()
  local m = (dir == "up") and n and n - 1 or (dir == "down") and n and n + 1 or nil
  if not (n and m and cfg.events[n] and cfg.events[m]) then say(pid, "Usage: /tg moveevent <n> up|down"); return end
  cfg.events[n], cfg.events[m] = cfg.events[m], cfg.events[n]
  markDirty()
  say(pid, cfg.events[m].name .. " moved " .. dir .. ".")
end

ADMIN_CMDS.trailersave = function(pid)
  say(pid, "Reading the trailer you're in (build it first: spawn it, pick a load, remove the straps)...")
  MP.TriggerClientEvent(pid, "tg_trailersave", "")
end
ADMIN_CMDS.trailercones = function(pid)
  local tc = typeCfg("trailer")
  tc.setup = nil
  saveConfig()
  say(pid, "Trailer events are back to the empty trailer + loose cones.")
end
-- client -> server: { model, config, loadParts = {...}, err }
function TG_onTrailerSave(pid, data)
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  log("trailersave from " .. tostring(MP.GetPlayerName(pid)) .. ": " .. tostring(data):sub(1, 600))
  if t.err or not t.model then say(pid, "Couldn't read the trailer: " .. tostring(t.err or "no vehicle")); return end
  if not t.loadPart then
    say(pid, "Not saved: no load found on your " .. tostring(t.model) .. ". Pick one in the parts menu's Load slot first.")
    say(pid, "Slots I can see: " .. table.concat(t.slots or {}, ", "))
    return
  end
  cfg.eventTypes.trailer.setup = { model = t.model, loadSlot = t.loadSlot, loadPart = t.loadPart, loadParts = t.loadParts or { t.loadPart },
                                    parts = t.parts, vars = t.vars }
  saveConfig()
  local nParts, straps = 0, {}
  for slot, part in pairs(t.parts or {}) do
    nParts = nParts + 1
    if tostring(slot):lower():find("strap") then straps[#straps + 1] = (part == "" and "removed" or ("fitted: " .. tostring(part))) end
  end
  say(pid, string.format("Saved your %s exactly as built (%d slots) with %s. Straps: %s. /tg trailertest to check it; /tg trailercones to go back.",
    tostring(t.model), nParts, tostring(t.loadPart), #straps > 0 and table.concat(straps, ", ") or "no strap slot on this trailer"))
end

ADMIN_CMDS.trailertest = function(pid, _, args)
  if (args[3] or ""):lower() == "off" then
    MP.TriggerClientEvent(pid, "tg_trailer_clear", "")
    say(pid, "Removing the test trailer and cargo.")
    return
  end
  local tc = typeCfg("trailer")
  local payload = trailerPayload(tc)
  payload.test = true
  MP.TriggerClientEvent(pid, "tg_trailer", Util.JsonEncode(payload))
  if payload.setup then
    say(pid, "Spawning your saved trailer (" .. tostring(payload.trailer) .. " with its load) behind you...")
  else
    say(pid, string.format("Spawning a test %s with %d x %s behind you (no challenge needed)...", tostring(tc.trailerModel),
      tc.cargoCount or 5, tostring(tc.cargoModel)))
  end
end

-- client -> server: { ok, trailer = bool, cargo = n, err }
function TG_onTrailerReport(pid, data)
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  log(string.format("trailer for %s: %s", tostring(MP.GetPlayerName(pid)), tostring(data)))
  if t.ok and t.prebuilt and t.hasLoad == false then
    say(pid, "The trailer spawned WITHOUT its load on this BeamNG version - send the admin the [TopGear] trailer line from the server console.")
    return
  end
  if t.ok and t.prebuilt then
    say(pid, string.format("Trailer OK with its built-in load%s.", tonumber(t.load) and string.format(" - %d%% of the load on the bed", math.floor(t.load * 100 + 0.5)) or " (load reading unavailable)"))
    return
  end
  if t.ok then
    local deck = tonumber(t.onDeck)
    say(pid, string.format("Trailer %s, %s cargo item(s) spawned%s.", t.trailer and "OK" or "MISSING", tostring(t.cargo or 0),
      deck and string.format(", %d on the deck", deck) or ""))
    if deck and deck < (tonumber(t.cargo) or 0) then
      say(pid, "Some cargo missed the deck - adjust eventTypes.trailer.cargoHeight / cargoSpacing in config.json, or pick a fenced trailer (boxutility_large).")
    end
  else
    say(pid, "Couldn't spawn the trailer/cargo: " .. tostring(t.err) .. " - check eventTypes.trailer model names in config.json.")
  end
end

ADMIN_CMDS.undovia = function(pid, _, args)
  local e, label = eventArg(pid, args[3], true); if not e then return end
  if e.via and #e.via > 0 then table.remove(e.via); markDirty() end
  local n = #(e.via or {})
  say(pid, string.format("Route to %s now has %d waypoint%s.", label, n, n == 1 and "" or "s"))
end

local BACKUP_NAME = "~ unsaved backup"

local function findCourse(name)
  if library[name] then return name end
  local lower = name:lower()
  for n in pairs(library) do if n:lower() == lower then return n end end
  return nil
end

local function snapshotCourse()
  local errs = validate(nil, nil, true)
  local stamp = nil
  pcall(function() stamp = os.date("%Y-%m-%d %H:%M") end)
  return { events = deepcopy(cfg.events), finale = deepcopy(cfg.finale), workshopSpots = deepcopy(cfg.workshopSpots or {}),
           savedAt = stamp, problems = #errs }
end

local function backupIfDirty(pid, exceptName)
  if courseDirty and cfg.activeCourse ~= exceptName then
    library[BACKUP_NAME] = snapshotCourse()
    saveLibrary()
    say(pid, "Your unsaved changes were kept as '" .. BACKUP_NAME .. "'.")
  end
end

local function applyCourse(name, course)
  cfg.events = deepcopy(course.events or {})
  migrateEvents(cfg.events)
  cfg.finale = deepcopy(course.finale or DEFAULT_CONFIG.finale)
  cfg.workshopSpots = deepcopy(course.workshopSpots or {})
  cfg.activeCourse = name
  courseDirty = false
  cfg.courseDirty = false
  saveConfig()
end

local COURSE_SUB = {}

COURSE_SUB.list = function(pid)
  local names = {}
  for n in pairs(library) do names[#names + 1] = n end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  say(pid, "Loaded: " .. tostring(cfg.activeCourse or "(unnamed)") .. (courseDirty and " - unsaved changes" or ""))
  if #names == 0 then say(pid, "No saved courses yet - /tg course save <name>"); return end
  for _, n in ipairs(names) do
    local c = library[n]
    say(pid, string.format("  %s - %s%s", n, (c.problems or 0) == 0 and "complete" or (tostring(c.problems) .. " to set"),
      c.savedAt and ("  (" .. c.savedAt .. ")") or ""))
  end
end

COURSE_SUB.save = function(pid, name)
  name = name ~= "" and name or cfg.activeCourse
  if not name or name == "" then say(pid, "Usage: /tg course save <name>"); return end
  if #name > 40 then say(pid, "Keep course names to 40 characters."); return end
  library[name] = snapshotCourse()
  cfg.activeCourse = name
  courseDirty = false
  cfg.courseDirty = false
  local ok = saveLibrary() and saveConfig()
  say(pid, ok and ("Course '" .. name .. "' saved.") or "Save FAILED - check the server console.")
end

COURSE_SUB.load = function(pid, name)
  if game.phase ~= "idle" then say(pid, "Stop the challenge before loading a course."); return end
  local found = name ~= "" and findCourse(name)
  if not found then say(pid, "No saved course called '" .. name .. "'. /tg course list"); return end
  backupIfDirty(pid, found)
  applyCourse(found, library[found])
  sayAll("Course '" .. found .. "' loaded.")
end

COURSE_SUB.new = function(pid, name)
  if game.phase ~= "idle" then say(pid, "Stop the challenge before starting a new course."); return end
  name = name ~= "" and name or "Untitled"
  backupIfDirty(pid, nil)
  applyCourse(name, { events = DEFAULT_CONFIG.events, finale = DEFAULT_CONFIG.finale })
  say(pid, "New course '" .. name .. "' - drive out and place its points, then Save.")
end

COURSE_SUB.delete = function(pid, name)
  local found = name ~= "" and findCourse(name)
  if not found then say(pid, "No saved course called '" .. name .. "'."); return end
  library[found] = nil
  saveLibrary()
  if cfg.activeCourse == found then markDirty() end
  say(pid, "Deleted saved course '" .. found .. "'" .. (cfg.activeCourse == found and " (still loaded - Save to keep it)." or "."))
end

ADMIN_CMDS.course = function(pid, _, args)
  local sub = (args[3] or "list"):lower()
  local name = table.concat(args, " ", 4):gsub("^%s+", ""):gsub("%s+$", "")
  if not COURSE_SUB[sub] then say(pid, "Usage: /tg course list | save <name> | load <name> | new <name> | delete <name>"); return end
  COURSE_SUB[sub](pid, name)
end

ADMIN_CMDS.addworkshop = function(pid, _, args)
  local pos = adminPos(pid)
  if not pos then say(pid, "Drive to the workshop spot first."); return end
  local name = table.concat(args, " ", 3)
  cfg.workshopSpots = cfg.workshopSpots or {}
  cfg.workshopSpots[#cfg.workshopSpots + 1] = { x = pos.x, y = pos.y, z = pos.z, name = name ~= "" and name or ("Workshop " .. (#cfg.workshopSpots + 1)) }
  markDirty()
  say(pid, string.format("Workshop %d set %s (/tg course save)", #cfg.workshopSpots, fmtPos(pos)))
end
ADMIN_CMDS.undoworkshop = function(pid)
  if cfg.workshopSpots and #cfg.workshopSpots > 0 then table.remove(cfg.workshopSpots); markDirty() end
  say(pid, #(cfg.workshopSpots or {}) .. " workshop spot(s) left.")
end
ADMIN_CMDS.clearworkshops = function(pid)
  cfg.workshopSpots = {}
  markDirty()
  say(pid, "Workshop spots cleared - workshops now work anywhere.")
end
ADMIN_CMDS.importgas = function(pid)
  say(pid, "Looking for this map's gas stations (your game reads them)...")
  MP.TriggerClientEvent(pid, "tg_findgas", "")
end
-- client -> server: { stations = { {x,y,z,name}, ... }, method = "...", err = "..." }
function TG_onGasStations(pid, data)
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  log("gas station import: " .. tostring(data):sub(1, 400))
  local st = type(t.stations) == "table" and t.stations or {}
  if #st == 0 then
    say(pid, "Couldn't find gas stations on this map (" .. tostring(t.err or t.method or "none found") ..
      "). Place workshops yourself: drive to a spot and use Add workshop here (/tg addworkshop [name]).")
    return
  end
  cfg.workshopSpots = cfg.workshopSpots or {}
  local added = 0
  for _, g in ipairs(st) do
    local gv = v3(g)
    if gv then
      local dup = false
      for _, sp in ipairs(cfg.workshopSpots) do if dist(v3(sp), gv) < 40 then dup = true end end
      if not dup then
        cfg.workshopSpots[#cfg.workshopSpots + 1] = { x = r2(gv.x), y = r2(gv.y), z = r2(gv.z), name = g.name or ("Gas station " .. (#cfg.workshopSpots + 1)) }
        added = added + 1
      end
    end
  end
  markDirty()
  say(pid, string.format("Added %d gas station%s as workshops (%d total, via %s). Save the course to keep them.",
    added, added == 1 and "" or "s", #cfg.workshopSpots, tostring(t.method)))
end

-- client -> server: what the game reports about the car's parts and prices
function TG_onPartsDiag(pid, data)
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  log("parts diag from " .. tostring(MP.GetPlayerName(pid)) .. ": " .. tostring(data):sub(1, 600))
  say(pid, string.format("Parts: %s found (%s format), %s with a price.", tostring(t.count), tostring(t.format), tostring(t.priced)))
  for _, ex in ipairs(t.examples or {}) do say(pid, "  " .. tostring(ex)) end
  if t.err then say(pid, "  error: " .. tostring(t.err)) end
end
PLAYER_CMDS.partsdiag = function(pid)
  MP.TriggerClientEvent(pid, "tg_partsdiag", "")
end

ADMIN_CMDS.setfinale = function(pid)
  withPos(pid, function(pos) cfg.finale.pos = pos; markDirty(); say(pid, "Finale finish set " .. fmtPos(pos) .. " (/tg save)") end)
end
ADMIN_CMDS.rename = function(pid, _, args)
  local e = eventArg(pid, args[3], true); if not e then return end
  local newName = table.concat(args, " ", 4)
  if newName == "" then say(pid, "Usage: /tg rename <n|finale> <name>"); return end
  e.name = newName; markDirty(); say(pid, "Renamed to " .. newName)
end
ADMIN_CMDS.clearcourse = function(pid, _, args)
  if game.phase ~= "idle" then say(pid, "Stop the challenge first (/tg stop)."); return end
  local which = args[3]
  local function wipeEvent(e) e.start, e.trap = nil, nil; e.checkpoints = {}; e.via = {} end
  local function wipeFinale() cfg.finale.pos = nil; cfg.finale.via = {} end
  if which == "all" then
    for _, e in ipairs(cfg.events) do wipeEvent(e) end
    wipeFinale()
    say(pid, "Whole course cleared.")
  elseif which == "finale" then
    wipeFinale()
    say(pid, "Finale finish and route cleared.")
  else
    local n = tonumber(which)
    if not (n and cfg.events[n]) then
      say(pid, "Usage: /tg clearcourse <1-" .. #cfg.events .. " | finale | all>"); return
    end
    wipeEvent(cfg.events[n])
    say(pid, "Event " .. n .. " (" .. cfg.events[n].name .. ") cleared: start, checkpoints, trap and route.")
  end
  markDirty()
  say(pid, "Not saved yet - /tg course save to keep it.")
end
ADMIN_CMDS.courses = function(pid)
  for i, e in ipairs(cfg.events) do
    local detail
    if e.type == "speedtrap" then detail = "trap:" .. (v3(e.trap) and "yes" or "NO")
    elseif e.type == "parking" then detail = "bays:" .. #eventBays(e)
    else detail = (e.type == "slalom" and "gates:" or "cps:") .. #(e.checkpoints or {}) end
    say(pid, string.format("%d. %s%s [%s] start:%s %s route:%d wp", i, e.enabled == false and "(off) " or "", e.name,
      e.type or "race", v3(e.start) and "yes" or "NO", detail, #(e.via or {})))
  end
  say(pid, string.format("Finale: %s finish:%s route:%d wp", cfg.finale.name, v3(cfg.finale.pos) and "yes" or "NO", #(cfg.finale.via or {})))
  local errs = validate(nil, nil, true)
  say(pid, #errs == 0 and "Every event that's switched on is complete." or (#errs .. " thing(s) still to set on the events that are on."))
end
ADMIN_CMDS.save = function(pid)
  say(pid, saveConfig() and "Saved config.json." or "Save FAILED - check the server console.")
end
ADMIN_CMDS.reload = function(pid)
  if game.phase ~= "idle" then say(pid, "Stop the challenge before reloading config."); return end
  loadConfig(); courseDirty = cfg.courseDirty == true; say(pid, "config.json reloaded.")
end

local function runCommand(pid, name, msg)
  local args = {}
  for w in msg:gmatch("%S+") do args[#args + 1] = w end
  local cmd = (args[2] or "help"):lower()
  local ok, err = pcall(function()
    if PLAYER_CMDS[cmd] then PLAYER_CMDS[cmd](pid, name, args)
    elseif ADMIN_CMDS[cmd] then
      if isAdmin(name) then ADMIN_CMDS[cmd](pid, name, args) else say(pid, "That's an admin command.") end
    else say(pid, "Unknown command. /tg help") end
  end)
  if not ok then log("command error: " .. tostring(err)); say(pid, "Command failed - see server console.") end
end

function TG_onChat(pid, name, msg)
  if msg ~= "/tg" and msg:sub(1, 4) ~= "/tg " then return 0 end
  runCommand(pid, name, msg)
  return 1  -- keep /tg commands out of public chat
end

-- In-game window --------------------------------------------------------------
local function buildUi(pid)
  local name = MP.GetPlayerName(pid)
  local p = playerByPid(pid)
  local budget = playerBudget(p)
  local d = {
    admin = isAdmin(name), phase = game.phase, budget = budget, baseBudget = cfg.economy.startingCash,
    towFee = cfg.economy.towFee, workshopSpots = #workshopSpots(),
    respawnFee = cfg.economy.respawnFee or cfg.economy.towFee,
    workshopEvery = tonumber(cfg.workshopEvery) or 2,
    workshopMinutes = cfg.workshop.minutes,
    gamePrices = cfg.dealer.useGamePrices and true or false, allHere = game.allHere and true or false,
    traffic = inTrafficMode(name),
  }
  if p then
    d.me = {
      cash = p.cash, points = p.points, wins = p.wins, car = p.carName, damage = math.floor(p.damage or 0),
      repair = repairQuote(p), upgrade = (upgradeBill(p)), ready = p.ready and true or false,
      arrived = p.leg.arrived and true or false, hasCar = p.carVid ~= nil, tows = p.tows or 0,
      canTow = p.carVid ~= nil and TOW_PHASES[game.phase] and not p.finaleTowed and not (game.phase == "finale" and p.leg.arrived) or false,
      canUnstick = p.carVid ~= nil and game.phase ~= "countdown" or false,
      respawns = p.respawns or 0, hasCarModel = p.carModel ~= nil, inShop = inWorkshop(p),
      creditLimit = cfg.workshop.creditLimit or 1500,
    }
  end
  local dealer = {}
  if cfg.dealer.useGamePrices then
    for _, c in ipairs(listedModels()) do
      local trims = trimsFor(c.model, budget)
      if #trims > 0 then dealer[#dealer + 1] = { model = c.model, name = c.name, trims = trims } end
    end
  else
    local byModel = {}
    for _, c in ipairs(cfg.dealer.cars) do
      if c.price <= budget then
        local g = byModel[c.model]
        if not g then g = { model = c.model, name = c.name, trims = {} }; byModel[c.model] = g; dealer[#dealer + 1] = g end
        g.trims[#g.trims + 1] = { config = (c.config and c.config ~= "") and c.config or nil, name = c.name, price = c.price }
      end
    end
  end
  d.dealer = dealer
  d.summary = game.summary
  if faultsOn() then
    local offers = {}
    for _, f in ipairs(cfg.faults.list or {}) do
      offers[#offers + 1] = { id = f.id, name = f.name, payout = f.payout, fix = fixCost(f), taken = p and hasFault(p, f.id) or false }
    end
    d.faults = { offers = offers, max = cfg.faults.maxPerCar, count = p and #(p.faults or {}) or 0 }
  end
  d.standings = {}
  for _, q in ipairs(sortedPlayers()) do
    d.standings[#d.standings + 1] = { name = q.name, points = q.points, wins = q.wins, cash = q.cash, car = q.carName, online = q.pid ~= nil }
  end
  if d.admin then
    local ev = {}
    for i, e in ipairs(cfg.events) do
      ev[#ev + 1] = { n = i, name = e.name, type = e.type or "race", start = v3(e.start) ~= nil,
                      cps = #(e.checkpoints or {}), trap = v3(e.trap) ~= nil, bays = #eventBays(e), via = #(e.via or {}),
                      timeLimit = e.timeLimit or cfg.defaults.eventTimeLimit,
                      enabled = e.enabled ~= false, solo = isSolo(e), typeLabel = (TYPE_INFO[e.type or "race"] or {}).label,
                      laps = e.laps }
    end
    local lib = {}
    for n, c in pairs(library) do lib[#lib + 1] = { name = n, problems = c.problems or 0, savedAt = c.savedAt } end
    table.sort(lib, function(a, b) return a.name:lower() < b.name:lower() end)
    local types = {}
    for i, t in ipairs(TYPE_ORDER) do types[i] = { id = t, label = TYPE_INFO[t].label } end
    d.course = { events = ev, problems = #validate(nil, nil, true), library = lib, active = cfg.activeCourse, dirty = courseDirty,
                 workshops = #workshopSpots(),
                 types = types, workshopEvery = tonumber(cfg.workshopEvery) or 2, idle = game.phase == "idle",
                 finale = { name = cfg.finale.name, pos = v3(cfg.finale.pos) ~= nil, via = #(cfg.finale.via or {}) } }
  end
  return d
end

local function sendUi(pid) MP.TriggerClientEvent(pid, "tg_ui", Util.JsonEncode(buildUi(pid))) end

function TG_onUiRequest(pid) sendUi(pid) end

-- window buttons send the same text as the chat commands; permissions are checked the same way
function TG_onUiCommand(pid, data)
  local cmd = tostring(data or "")
  if cmd:sub(1, 4) ~= "/tg " then cmd = "/tg " .. cmd end
  runCommand(pid, MP.GetPlayerName(pid), cmd)
  sendUi(pid)
end

---------------------------------------------------------------------------
-- Init (runs when the plugin loads)
---------------------------------------------------------------------------
loadConfig()
courseDirty = cfg.courseDirty == true
loadLibrary()
MP.RegisterEvent("onChatMessage",      "TG_onChat")
MP.RegisterEvent("onPlayerJoin",       "TG_onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "TG_onPlayerDisconnect")
MP.RegisterEvent("onVehicleSpawn",     "TG_onVehicleSpawn")
MP.RegisterEvent("onVehicleEdited",    "TG_onVehicleEdited")
MP.RegisterEvent("onVehicleDeleted",   "TG_onVehicleDeleted")
MP.RegisterEvent("onVehicleReset",     "TG_onVehicleReset")
MP.RegisterEvent("tg_report",          "TG_onReport")
MP.RegisterEvent("tg_diag_reply",      "TG_onDiag")
MP.RegisterEvent("tg_import_reply",    "TG_onImportReply")
MP.RegisterEvent("tg_ui_req",          "TG_onUiRequest")
MP.RegisterEvent("tg_ui_cmd",          "TG_onUiCommand")
MP.RegisterEvent("tg_fault_report",    "TG_onFaultReport")
MP.RegisterEvent("tg_move_report",     "TG_onMoveReport")
MP.RegisterEvent("tg_trailer_report",  "TG_onTrailerReport")
MP.RegisterEvent("tg_rebuild",         "TG_onRebuild")
MP.RegisterEvent("tg_revert_report",   "TG_onRevertReport")
MP.RegisterEvent("tg_trailersave_reply", "TG_onTrailerSave")
MP.RegisterEvent("tg_gas_reply",       "TG_onGasStations")
MP.RegisterEvent("tg_partsdiag_reply", "TG_onPartsDiag")
MP.RegisterEvent("tg_tick",            "TG_onTick")
MP.CreateEventTimer("tg_tick", TICK_MS)
if #cfg.admins == 0 then log("WARNING: no admins set in config.json - everyone can run admin commands") end
log(string.format("Top Gear Challenge server v%s loaded: %d events. Type /tg help in game.", SERVER_VERSION, #cfg.events))
