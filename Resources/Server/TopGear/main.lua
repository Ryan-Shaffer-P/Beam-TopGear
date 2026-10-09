--[[
  TOP GEAR CHALLENGE - BeamMP server plugin (v0.1)
  ------------------------------------------------
  Put this file at:  <BeamMP server>/Resources/Server/TopGear/main.lua
  Client mod:        <BeamMP server>/Resources/Client/topgear.zip
  Settings + course: config.json next to this file (written with defaults on first run).
  In game, type /tg help.
]]

local SERVER_VERSION = "0.9.35"
local PLUGIN_DIR  = "Resources/Server/TopGear/"
local CONFIG_PATH = PLUGIN_DIR .. "config.json"
local COURSES_PATH = PLUGIN_DIR .. "courses.json"   -- saved course library
local CARS_PATH = PLUGIN_DIR .. "cars.json"         -- the built-in car catalogue (used until a server imports its own)
local TICK_MS     = 250   -- position polling interval
local PUSH_EVERY  = 8     -- ticks between HUD refreshes (8 x 250 ms = 2 s)

---------------------------------------------------------------------------
-- Default configuration (copied to config.json on first run, then edit that)
---------------------------------------------------------------------------
local DEFAULT_CONFIG = {
  admins = {},                 -- names allowed to use admin commands. EMPTY = EVERYONE (testing only)
  aliases = {},
  -- Game modes (0.9.31, Ryan): switches for the next challenge - Start tab and the Admin tab's Game modes box.
  -- freeRepair: repairs, tows, respawns and unstick repairs cost nothing (a tow/respawn mid-run still disqualifies);
  -- noFaults: every car is New (no problems, no condition discounts); noQuirks: no quirks; turbo: prizes (planned).
  modes = { freeRepair = false, noFaults = false, noQuirks = false, turbo = false },   -- (turbo: Turbo Mode, below)
  -- Turbo Mode's prizes (0.9.32): earned for everything but winning - first to arrive at an event, the cleanest car at
  -- the finish, last place (a helpful prize), most air time, the biggest crash, first into a workshop, or an admin's /tg prize. Kept in the player's
  -- glovebox (at most maxHeld) and used when they like; the nasty ones pick a rival (not mid-run, once a leg each).
  turbo = {
    maxHeld = 3,
    envelope = { 500, 2000 }, taxman = 500, headStart = 2, penalty = 3, tune = 1.1, frontRight = 3,
    minAir = 1, minCrash = 1000,   -- (0.9.33) the least air time (s) / crash damage that wins those prizes
    prizes = {
      { id = "tune", name = "Free engine tune", good = true, help = "+10% power for your next event." },
      { id = "favour", name = "Mechanic's favour", good = true, help = "One of your car's problems fixed, free, right now." },
      { id = "exorcism", name = "Quirk exorcism", good = true, help = "One of your quirks gone." },
      { id = "jail", name = "Get out of jail", good = true, help = "Your next tow or respawn costs no points." },
      { id = "envelope", name = "Producers' envelope", good = true, help = "Cash: $500 to $2,000." },
      { id = "headstart", name = "Head start", good = true, help = "2 seconds off your time in the next event." },
      { id = "horn", name = "Sabotage: haunted horn", target = true, help = "A rival's horn sounds every time they brake - until their next workshop." },
      { id = "frbrake", name = "Brake \"upgrade\"", target = true, help = "A rival's brakes upgraded - the front right one only, 3x stronger. Until their next workshop." },
      { id = "sugar", name = "Sugar in the tank", target = true, help = "A rival's engine gets tired (or springs a fuel leak) - a workshop can fix it." },
      { id = "taxman", name = "Taxman", target = true, help = "$500 from a rival, to you." },
      { id = "penalty", name = "Penalty card", target = true, help = "3 seconds on a rival's time in their next event." },
    },
  },                -- BeamMP name -> the name everyone sees (/tg name, admin /tg setname; BeamMP's guests are random)
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
    workshopDiscount    = 0.15,  -- a workshop repair costs this much less than the repair price (roadside help pays it all)
    -- Roadside help repairs the car too, so it costs the repair price x roadsideMarkup plus a service fee:
    -- tow = that + towFee (and delivery to the next start), respawn = that + respawnFee. The workshop is cheapest.
    roadsideMarkup      = 1.25,
    towFee              = 1000,  -- /tg tow (or respawning a lost car): + delivery, DSQ from a running event
    resetPenalty        = 1000,  -- if someone manages an illegal reset (R / Insert) anyway
    respawnFee          = 500,   -- /tg respawn outside the dealership/workshop (a fresh car on the spot)
    unstickCooldown     = 15,    -- seconds between free /tg unstick uses
    unstickMaxSpeed     = 3,     -- m/s: unstick only works when (nearly) stopped
  },

  -- Points: event placings + drivability (the AVERAGE of an inspection on arrival at every workshop and at the
  -- finale) - penalties (illegal resets, tows/respawns, unfixed faults, debt) + producer awards (/tg award).
  -- Money in the bank only breaks ties.
  scoring = {
    placementPoints          = { 10, 6, 3, 1 },
    drivabilityMaxPoints     = 20,     -- one inspection of an undamaged car
    damageForZeroDrivability = 20000,  -- damage at which an inspection scores 0
    recoveryPenaltyPoints    = 2,      -- per illegal reset
    towPenaltyPoints         = 2,      -- per tow and per roadside respawn
    debtStep                 = 500,    -- at the end: debtPenaltyPoints for every debtStep (or part of it) in the red
    debtPenaltyPoints        = 1,
  },

  -- Problem cars: at the dealership a player takes a NUMBER of faults (not which ones) for `payout` each;
  -- the server picks them at random from those the player's car can take. They stay hidden until a
  -- workshop diagnoses the car, can't be handed back, cost fixMultiplier x payout to fix in a workshop,
  -- and inspectionPenaltyPoints drivability each if still there at the finale. `enabled = false` on a
  -- fault leaves it out of the draw.
  faults = {
    enabled = true,
    maxPerCar = 4,                -- 0 (New) .. 4 (Death Trap) problems: the car's condition
    -- Condition pricing (0.9.12, career mode's formula without age): every car's price x
    -- (1 - lossPerKm x the condition's mileage) + scrapValue -> Used 90%, Needs work 80%, Beater 55%, Death Trap 30%
    lossPerKm = 0.0000025,
    scrapValue = 0.05,
    -- 0.9.13, Ryan: steeper early steps instead (career's formula made Used only 10% off - at a $15,000 budget it
    -- unlocked 3 more cars): the price off for Used, Needs work, Beater, Death Trap. Remove it to go back to the formula.
    discount = { 0.25, 0.40, 0.55, 0.70 },
    -- Fast cars hold their value: the condition discount is scaled by the car's 0-100 km/h time - the full discount
    -- at perfSlowSeconds or slower, perfMinShare of it at perfFastSeconds or quicker (a worn 340 hp ETK isn't a bargain)
    perfFastSeconds = 4, perfSlowSeconds = 10, perfMinShare = 0.3,
    -- More worn, worse problems: each problem's strength x this for Used, Needs work, Beater, Death Trap (the values in
    -- `list` are a Beater's). Floors/caps keep it sane; the weak starter and ignition cut-outs never get harsher than listed.
    severity = { 0.5, 0.75, 1.0, 1.3 },
    fixPercent = 0.05,            -- a workshop fix costs this share of the car's new price per problem...
    fixMin = 500,                 -- ...but at least this
    inspectionPenaltyPoints = 3,  -- points lost per fault still unfixed at the end (its own penalty)
    -- Mileage wear by car condition (New, Used, Needs work, Beater, Death Trap): BeamNG's own part-condition
    -- system, as career mode's used-car dealership uses it - odometer (engine/gearbox/clutch wear, rough idle).
    -- Applied when the car spawns; it stays (resets, repairs, problem fixes). No paint aging: the game does it by
    -- locking every body mesh's colour, which stops repaints from showing (and only the owner would see it).
    mileageKm = { 0, 60000, 100000, 200000, 300000 },
    -- Problem tiers (0.9.21, Ryan: some problems together make a car undriveable). Each problem has a tier - 1
    -- annoying, 2 hurts performance, 3 can stop the car - and groups: a car never gets two problems that share a group.
    -- maxTier: the worst tier each condition can draw (Used, Needs work, Beater, Death Trap); maxPerTier: at most this
    -- many problems of each tier (1, 2, 3) on one car. A problem without a tier counts as tier 1.
    fires = true,                 -- false = a fuel leak never catches fire (fuelleak fireChance: how often it does)
    tiers = true,                 -- false = no tier or group rules (any problem with any other, as before 0.9.21)
    maxTier = { 1, 2, 3, 3 },
    maxPerTier = { 4, 4, 1 },
    list = {                      -- factor = severity (see README); tier / groups: see maxTier above
      { id = "tires", tier = 1,      name = "Worn, underinflated tires",               factor = 0.3 },   -- pressure = 30% of normal
      { id = "alignment", tier = 1,  name = "Knocked-out wheel alignment",             factor = 1.4,     -- front toe to its limit + rear 40%
        pull = 0.028 },   -- and it pulls to one side (random per car): straight ahead moved this share of full steering
      { id = "engine", tier = 2,     name = "Tired engine (about -20% power)",         factor = 0.8 },
      { id = "brakes", tier = 2, groups = { "brakes" },     name = "Worn brakes (about -40% braking)",        factor = 0.6 },
      { id = "ignition", tier = 3, groups = { "stalling" },   name = "Ignition problems (misfires, cuts out, slow to start)", factor = 0.05,   -- extra misfire chance
        cutoutMin = 120, cutoutMax = 240,     -- seconds between cut-outs (a Beater's; / severity: Used 4-8 min)
        starter = 0.6 },                      -- and a weak starter: its torque x this (0.9.13: was its own fault)
      { id = "cooling", tier = 3, groups = { "heat" },    name = "Cooling problems (leaking radiator)",     factor = 0.05 },  -- radiator damage (0.1 = wrecked)
      { id = "suspension", tier = 1, name = "Worn-out suspension (soft and bouncy)" },                   -- softest springs/dampers, or no anti-roll bars
      { id = "fuelleak", tier = 2, groups = { "stalling" },   name = "Fuel leak",                                factor = 1.0,   -- litres per minute
        fireChance = 0.2, fireMin = 60, fireMax = 600 },   -- chance it's the kind that catches fire (once); seconds of driving until it does
      { id = "body", tier = 1,       name = "Accident damage (missing bumpers, dents, broken lights)", factor = 3000 },   -- damage it
                                                       -- starts with, plus no front/rear bumper (0.9.13: was its own fault)
      { id = "clutch", tier = 2, groups = { "gears" },     name = "Slipping clutch", enabled = false,          factor = 0.6 },   -- clutch grip x this (0.9.13: was
                                                       -- BeamNG's "permanently damaged" = 25%); manuals; off: mileage wears the clutch
      { id = "synchros", tier = 2, groups = { "gears" },   name = "Worn gearbox synchros (gears grind)",     factor = 0.8 },   -- synchro wear (1 = gears break); manuals
      { id = "turbo", tier = 2,      name = "Damaged turbo (low boost)",               factor = 0.02 },  -- turbo damage; turbo cars
      { id = "brakefade", tier = 2, groups = { "brakes" },  name = "Glazed brake pads (squeal, fade when hot)", factor = 1,     -- pad glazing (1 = fully glazed:
        refresh = 0.5 },   -- the game's brakes x0.8 + squeal); re-glazed every `refresh` s - hard braking scrubs glazing off
      { id = "abs", tier = 1, groups = { "brakes" },        name = "ABS failure (wheels lock)" },
      { id = "oilleak", tier = 3, groups = { "stalling", "heat" },    name = "Oil leak (runs hot - might blow the engine)", factor = 0.5, -- engine friction +50%
        blowChance = 0.2, blowMin = 60, blowMax = 600,     -- chance the engine is doomed; seconds of hard driving until it goes
        minCondition = 3 },                                -- only Beaters and Death Traps (a Used car's engine doesn't blow)
      { id = "idle", tier = 2, groups = { "stalling" },       name = "Rough idle (hunts and stalls)",           factor = 15, enabled = false },   -- idle-speed error x this
      { id = "gearbox", tier = 2, groups = { "gears" },    name = "Worn gearbox (power lost to friction)",   factor = 3, enabled = false },    -- gearbox friction x this
      -- (idle, gearbox and clutch are off by default since 0.9.12: the car condition's mileage wear does the same)
    },
  },

  -- Sound bites (client mod: art/sound/topgear/<clip>.ogg). For each moment: who hears it and which
  -- clips (one picked at random). to = all | self (the player it's about) | others (everyone but them)
  -- | near (players within nearRadius of them, them included). Players can mute with /tg sounds off.
  sounds = {
    enabled = true,
    nearRadius = 100,      -- metres, for to = "near"
    crashDamage = 1500,    -- damage gained between two reports that counts as a crash
    clips = { "baby-jesus", "clarkson-poop-shot-out", "clarksooon", "grunt-yes", "happy-yes", "james-may-says-cheese",
              "jeremy-clarkson-oh-for-gods-sake", "jeremy-clarkson-yeeeeeesss", "oh-cock-james-may", "oh-for-gods-sake",
              "oh-no-anyway", "poweeerr-jeremy-clarkson", "speed-and-power", "this-is-mp3", "top-gear-theme-intro", "yes-no-yes",
              "workshop-intro", "lights-out", "fan-belt-squeal", "randomradio" },
    events = {
      start      = { to = "all",    clips = { "top-gear-theme-intro" } },                          -- challenge starts
      go         = { to = "all",    clips = { "lights-out" } },                                    -- GO: the lights go out (each run in time trial mode)
      finish     = { to = "self",   clips = { "happy-yes", "grunt-yes" } },                        -- you complete a run
      win        = { to = "self",   clips = { "jeremy-clarkson-yeeeeeesss" } },                    -- you win an event
      winOthers  = { to = "others", clips = { "yes-no-yes" } },                                    -- ...and everyone else hears
      out        = { to = "self",   clips = { "oh-no-anyway" } },                                  -- DNF / DNS, tow, respawn DSQ
      resetFine  = { to = "all",    clips = { "oh-for-gods-sake", "jeremy-clarkson-oh-for-gods-sake" } },
      crash      = { to = "near",   clips = { "oh-cock-james-may", "clarkson-poop-shot-out" } },
      trapRecord = { to = "all",    clips = { "poweeerr-jeremy-clarkson" } },                      -- fastest through the trap so far
      parked     = { to = "near",   clips = { "grunt-yes" } },                                     -- a parking bay measured (not the last: finish plays)
      workshop   = { to = "all",    clips = { "workshop-intro" } },                                -- workshop opens
      champion   = { to = "all",    clips = { "top-gear-theme-intro" } },                          -- the overall winner is announced
    },
  },

  -- Quirks (0.9.29, Ryan: "more variety, even cosmetic or silly"): harmless extras a worn car comes with, on top of
  -- its problems - they don't change its condition, its drivability or its points. count: how many (min, max) for Used,
  -- Needs work, Beater, Death Trap. A workshop sorts one for fixCost. every = seconds between goes (min, max), on the
  -- road while moving (parked = standing still too); clip = one of sounds.clips; events = BeamNG's own one-shot sounds;
  -- action = the car's own controls (horn, lights, hazards - BeamMP shows them to everyone); say = a chat line (%s = name).
  quirks = {
    enabled = true,
    count = { { 0, 1 }, { 1, 1 }, { 1, 2 }, { 2, 3 } },
    fixCost = 150,
    list = {
      { id = "fanbelt", name = "Squealing fan belt", every = { 90, 240 }, clip = "fan-belt-squeal" },
      { id = "radio", name = "Possessed radio (switches itself on)", every = { 180, 420 }, clip = "randomradio", parked = true },
      { id = "backfire", name = "Backfiring exhaust", every = { 30, 90 },
        events = { "event:>Vehicle>Afterfire>01_Single_EQ1", "event:>Vehicle>Afterfire>01_Multi_EQ1" } },
      { id = "knock", name = "Engine knock", every = { 60, 180 }, events = { "event:>Vehicle>Failures>failure_engine_knock" } },
      { id = "squeak", name = "Squeaky brakes" },   -- (BeamNG's own brake squeal, turned up: whenever you brake gently)
      { id = "lights", name = "Flickering headlights", every = { 60, 180 }, action = "lights" },
      { id = "horn", name = "Haunted horn (beeps five times)", every = { 180, 420 }, action = "horn", parked = true },
      { id = "hazards", name = "Hazard lights with a mind of their own", every = { 120, 240 }, action = "hazards" },
    },
  },

  workshop = { minutes = 10, laborFee = 300, partsMarkup = 1.0, resaleRate = 0.5,
               flatPartPrice = 500,     -- charged per changed part when the game can't tell us its price
               radius = 30,             -- how close to a workshop spot (gas station) counts as "in the workshop"
               creditLimit = 1500 },    -- workshop/dealership spending may take a driver this far into the red
  workshopEvery = 2,              -- a workshop after every Nth event (never after the last one); 0 = none

  defaults = {
    startRadius = 20, cpRadius = 5, viaRadius = 25,   -- (checkpoints: 12 m until 0.9.13 - Ryan: tighter)
    lineWidth = 20,       -- a line checkpoint (course builder: Line): this wide, across the way from the point before it
    countdown = 5, falseStartPenalty = 5, eventTimeLimit = 600,
    backToStartSeconds = 5,   -- time trial: a finished driver's car goes behind the start line after this countdown
    readyCountdown = 5,   -- seconds from "everyone's ready" at the dealership to the dealership closing (leg 1)
    soloGo = true,        -- time trial mode: each driver after the first starts when GO is pressed (by them or an admin)
    watchRunner = true,   -- time trial mode: everyone else watches the driver on track (their camera; /tg watch off)
    readyToGo = true,     -- every start is I'm ready, then GO (race: everyone ready, then GO; time trial: each driver's
                          -- Ready then GO - turns begin by themselves once everyone's arrived). false = the old starts
  },

  dealer = {
    useGamePrices = false,  -- true after /tg importprices: every trim costs its BeamNG value
    gamePrices = {},        -- filled by /tg importprices: { model = { configKey = { name, price, attrs } } }
    modelNames = {},        -- filled by /tg importprices: { model = "Ibishu Covet" }
    -- importedAll = true after a full /tg importprices: with no class picked, every imported car and truck is sold
    -- catalogue = "builtin": the cars come from cars.json (shipped with the mod; not saved here); "import": this
    -- server's own /tg importprices (saved in gamePrices). /tg importprices builtin goes back to cars.json.
    prices = {},            -- dealership-wide prices, set with /tg setprice: { ["model/config"] = price } - for trims the
                            -- game has no value for (mostly mods), or to change one; used everywhere, a class can override
    -- Car classes (/tg class ...): a class sells only the imported trims matching its rules (BeamNG's own vehicle
    -- attributes), plus hand-picked `include`s, minus `exclude`s ("model" or "model/config"), at their game price x
    -- `multiplier` or a per-trim `prices` override. The admin picks the class for each challenge (/tg class use).
    --   classes = { jdm90s = { rules = { { field = "Country", values = { "Japan" } },
    --                                    { field = "Years", min = 1985, max = 1999 } },
    --                          include = {}, exclude = {}, prices = { ["covet/gtz_M"] = 13000 }, multiplier = 1 } }
    classes = {},
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
  -- type: race | circuit | speedtrap | parking | fragile | economy | slalom | trailer | rpc
  -- solo: true = time trial mode (one at a time), false = race mode (everyone at once), nil = the type's default
  --       (speedtrap, parking and slalom default to time trial mode, the rest to race mode)
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
    { name = "Star in a Reasonably Priced Car", type = "rpc", laps = 3, timeLimit = 600, enabled = false,
      description = "Everyone drives the same cheap car round the track, one at a time. Best lap of three wins.",
      via = {}, checkpoints = {} },
  },

  eventTypes = {   -- tuning for each event type
    parking = { bayRadius = 5, stillSeconds = 1.5, stillSpeed = 0.3, distWeight = 10, angleWeight = 0.5, timeWeight = 0.1,
                damageWeight = 0.01, missedBayPenalty = 50 },
    fragile = { damageWeight = 0.01 },   -- seconds added per point of damage picked up
    rpc     = { model = "covet", config = "DXi_A",   -- the reasonably priced car (each event can pick its own: /tg setrpc)
                spawnTimeout = 20,                   -- seconds to wait for it to appear (BeamMP MaxCars must be 2+)
                stopSeconds = 3 },                   -- after the last lap: time to stop before you're back in your own car
    slalom  = { gateRadius = 4, gatePenalty = 5 },
    trailer = { setup = nil,   -- saved with /tg trailersave: a prebuilt trailer whose load is part of it (replaces the cones)
                loadWeight = 0.7, speedWeight = 0.3,   -- score out of 100: share of the load kept + speed vs the fastest
                trailerModel = "tsfb", cargoModel = "cones", cargoCount = 5,
                cargoRadius = 5, hitchRadius = 15, trailerBack = 7, cargoSpacing = 0.7, cargoHeight = 0.8,
                -- a saved trailer with no load (a caravan): delivered in one piece - the 70 is the share still intact,
                -- 1 - its damage / wreckDamage (0.9.13)
                wreckDamage = 10000 },
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
local billUnstickRepair            -- defined with the tow
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
  local keep = cfg.dealer and cfg.dealer.catalogue == "builtin" and cfg.dealer.gamePrices   -- not copied into config.json
  if keep then cfg.dealer.gamePrices = {} end
  local okE, s = pcall(Util.JsonEncode, cfg)
  if keep then cfg.dealer.gamePrices = keep end
  if not okE then log("saving config.json failed: " .. tostring(s)); return false end
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
    if not cfg.migrations.faults10 then   -- 0.8.8: ten faults, one payout, taken by number
      cfg.migrations.faults10, changed = true, true
      local old = {}
      for _, f in ipairs((cfg.faults or {}).list or {}) do old[f.id] = f end
      if not old.ignition then
        local list = deepcopy(DEFAULT_CONFIG.faults.list)
        for _, f in ipairs(list) do
          local o = old[f.id]
          if o then f.factor = o.factor ~= nil and o.factor or f.factor; f.enabled = o.enabled end
        end
        cfg.faults.list = list
      end
    end
    if not cfg.migrations.faults19 then   -- 0.8.8: nine more faults
      cfg.migrations.faults19, changed = true, true
      local have = {}
      for _, f in ipairs((cfg.faults or {}).list or {}) do have[f.id] = true end
      for _, f in ipairs(DEFAULT_CONFIG.faults.list) do
        if not have[f.id] then cfg.faults.list[#cfg.faults.list + 1] = deepcopy(f) end
      end
    end
    if not cfg.migrations.combineBumpers then   -- 0.9.13, Ryan: missing bumpers is part of accident damage now
      cfg.migrations.combineBumpers, changed = true, true
      local list = (cfg.faults or {}).list or {}
      for i = #list, 1, -1 do
        local f = list[i]
        if f.id == "bumpers" then table.remove(list, i) end
        if f.id == "body" and f.name == "Accident damage (dents, broken lights)" then f.name = "Accident damage (missing bumpers, dents, broken lights)" end
      end
      for _, c in pairs(cfg.faultCaps or {}) do
        if type(c) == "table" then
          if c.ok then c.ok.bumpers = nil end
          if c.no then c.no.bumpers = nil end
        end
      end
    end
    if not cfg.migrations.faultTuning2 then   -- 0.9.12, Ryan's in-game tuning: ignition halved, a starter that still
      cfg.migrations.faultTuning2, changed = true, true   -- starts, double the fuel leak, pads kept glazed (only old defaults)
      for _, f in ipairs((cfg.faults or {}).list or {}) do
        if f.id == "ignition" and f.factor == 0.1 then f.factor = 0.05 end
        if f.id == "ignition" and f.cutoutMin == 90 and f.cutoutMax == 240 then f.cutoutMin, f.cutoutMax = 180, 480 end
        if f.id == "starter" and f.factor == 0.35 then f.factor = 0.6 end
        if f.id == "fuelleak" and f.factor == 0.5 then f.factor = 1.0 end
        if f.id == "brakefade" and f.refresh == nil then f.refresh = 0.5 end
      end
    end
    if not cfg.migrations.alignmentPull then   -- 0.9.12, Ryan: a knocked-out alignment that pulls to one side
      cfg.migrations.alignmentPull, changed = true, true
      for _, f in ipairs((cfg.faults or {}).list or {}) do
        if f.id == "alignment" and f.pull == nil then f.pull = 0.015 end
      end
    end
    if not cfg.migrations.alignmentPull2 then   -- 0.9.12, Ryan couldn't feel it on a Death Trap: +20% everywhere
      cfg.migrations.alignmentPull2, changed = true, true
      for _, f in ipairs((cfg.faults or {}).list or {}) do
        if f.id == "alignment" and f.pull == 0.015 then f.pull = 0.018 end
      end
    end
    if not cfg.migrations.cpRadius5 then   -- 0.9.13, Ryan: checkpoints 5 m (were 12 m); an admin's own value is kept
      cfg.migrations.cpRadius5, changed = true, true
      if cfg.defaults and cfg.defaults.cpRadius == 12 then cfg.defaults.cpRadius = 5 end
    end
    if not cfg.migrations.alignmentPull3 then   -- 0.9.13, Ryan: +1 point (Beater 1.8% -> 2.8%; Death Trap 3.64%)
      cfg.migrations.alignmentPull3, changed = true, true
      for _, f in ipairs((cfg.faults or {}).list or {}) do
        if f.id == "alignment" and f.pull == 0.018 then f.pull = 0.028 end
      end
    end
    if not cfg.migrations.lightsOut then   -- 0.9.13, Ryan: a lights-out clip as the start lights go out (GO)
      cfg.migrations.lightsOut, changed = true, true
      local snd = cfg.sounds or {}
      local have = false
      for _, c in ipairs(snd.clips or {}) do if c == "lights-out" then have = true end end
      if snd.clips and not have then snd.clips[#snd.clips + 1] = "lights-out" end
      local go = (snd.events or {}).go
      if type(go) == "table" and type(go.clips) == "table" and #go.clips == 2 and go.clips[1] == "speed-and-power"
         and go.clips[2] == "poweeerr-jeremy-clarkson" then
        go.clips = { "lights-out" }   -- (only the old default; an admin's own choice is kept)
      end
    end
    if not cfg.migrations.workshopIntro then   -- 0.9.13, Ryan: a workshop-intro clip when the workshop opens
      cfg.migrations.workshopIntro, changed = true, true
      local snd = cfg.sounds or {}
      local have = false
      for _, c in ipairs(snd.clips or {}) do if c == "workshop-intro" then have = true end end
      if snd.clips and not have then snd.clips[#snd.clips + 1] = "workshop-intro" end
      local ws = (snd.events or {}).workshop
      if type(ws) == "table" and type(ws.clips) == "table" and #ws.clips == 1 and ws.clips[1] == "james-may-says-cheese" then
        ws.clips = { "workshop-intro" }   -- (only the old default; an admin's own choice is kept)
      end
    end
    if not cfg.migrations.championTheme then   -- 0.9.12, Ryan: the Top Gear theme when the winner is announced
      cfg.migrations.championTheme, changed = true, true   -- (only the old default clips; an admin's own choice is kept)
      local ch = ((cfg.sounds or {}).events or {}).champion
      if type(ch) == "table" and type(ch.clips) == "table" and #ch.clips == 2
         and ch.clips[1] == "clarksooon" and ch.clips[2] == "jeremy-clarkson-yeeeeeesss" then
        ch.clips = { "top-gear-theme-intro" }
      end
    end
    if not cfg.migrations.clutchGrip then   -- 0.9.13, Ryan: the slipping clutch killed whole gears (BeamNG's 25% damage)
      cfg.migrations.clutchGrip, changed = true, true
      for _, f in ipairs((cfg.faults or {}).list or {}) do
        if f.id == "clutch" and f.factor == nil then f.factor = 0.6 end
      end
    end
    if not cfg.migrations.combineStarter then   -- 0.9.13, Ryan: the weak starter is part of the ignition problems now
      cfg.migrations.combineStarter, changed = true, true
      local list = (cfg.faults or {}).list or {}
      local starter
      for i = #list, 1, -1 do if list[i].id == "starter" then starter = table.remove(list, i) end end
      for _, f in ipairs(list) do
        if f.id == "ignition" then
          if f.starter == nil then f.starter = tonumber(starter and starter.factor) or 0.6 end   -- (an admin's own strength kept)
          if f.name == "Ignition problems (misfires, cuts out)" then f.name = "Ignition problems (misfires, cuts out, slow to start)" end
        end
      end
      for _, c in pairs(cfg.faultCaps or {}) do
        if type(c) == "table" then
          if c.ok then c.ok.starter = nil end
          if c.no then c.no.starter = nil end
        end
      end
    end
    if not cfg.migrations.ignitionCutouts then   -- 0.9.12, Ryan's 2nd drive: cut-outs too rare; a Used car's every 4-8 min
      cfg.migrations.ignitionCutouts, changed = true, true   -- (120-240 s / severity 0.5); only the old default
      for _, f in ipairs((cfg.faults or {}).list or {}) do
        if f.id == "ignition" and f.cutoutMin == 180 and f.cutoutMax == 480 then f.cutoutMin, f.cutoutMax = 120, 240 end
      end
    end
    if not cfg.migrations.conditionPricing then   -- 0.9.12: condition pricing; mileage 60k/100k/200k/300k km
      cfg.migrations.conditionPricing, changed = true, true
      local f = cfg.faults or {}
      if type(f.mileageKm) == "table" and f.mileageKm[5] == 500000 and f.mileageKm[3] == 150000 then f.mileageKm = deepcopy(DEFAULT_CONFIG.faults.mileageKm) end
    end
    if not cfg.migrations.quirks2 then   -- 0.9.30, Ryan: no mystery smell; hazards every 2-4 min; the horn beeps five times
      cfg.migrations.quirks2, changed = true, true
      local list = (cfg.quirks or {}).list
      for i = #(list or {}), 1, -1 do
        local q = list[i]
        if q.id == "smell" then table.remove(list, i)
        elseif q.id == "hazards" and type(q.every) == "table" and q.every[1] == 240 and q.every[2] == 480 then q.every = { 120, 240 }
        elseif q.id == "horn" and q.name == "Haunted horn" then q.name = "Haunted horn (beeps five times)" end
      end
    end
    if not cfg.migrations.quirkClips then   -- 0.9.28: two new clips (Ryan): a fan belt squeal, a random radio blurt
      cfg.migrations.quirkClips, changed = true, true
      local snd = cfg.sounds or {}
      for _, id in ipairs({ "fan-belt-squeal", "randomradio" }) do
        local have = false
        for _, c in ipairs(snd.clips or {}) do if c == id then have = true end end
        if snd.clips and not have then snd.clips[#snd.clips + 1] = id end
      end
    end
    if not cfg.migrations.fuelFire then   -- 0.9.26: a fuel leak can catch fire (once) - a saved list has no fire settings
      cfg.migrations.fuelFire, changed = true, true
      for _, f in ipairs((cfg.faults or {}).list or {}) do
        if f.id == "fuelleak" and f.fireChance == nil then f.fireChance, f.fireMin, f.fireMax = 0.2, 60, 600 end
      end
    end
    if not cfg.migrations.faultTiers then   -- 0.9.21: problem tiers and groups (a saved list has none)
      cfg.migrations.faultTiers, changed = true, true
      for _, f in ipairs((cfg.faults or {}).list or {}) do
        local def
        for _, d in ipairs(DEFAULT_CONFIG.faults.list) do if d.id == f.id then def = d end end
        if def and f.tier == nil then f.tier = def.tier end
        if def and f.groups == nil and def.groups then f.groups = deepcopy(def.groups) end
      end
    end
    if not cfg.migrations.mileageOverlap then   -- 0.9.12: mileage wear replaces rough idle / worn gearbox / slipping clutch;
      cfg.migrations.mileageOverlap, changed = true, true   -- the oil leak only for Beaters and worse
      for _, f in ipairs((cfg.faults or {}).list or {}) do
        if f.id == "idle" or f.id == "gearbox" or f.id == "clutch" then f.enabled = false end
        if f.id == "oilleak" and f.minCondition == nil then f.minCondition = 3 end
      end
    end
    if not cfg.migrations.faults4 then   -- 0.8.8: up to 4 faults per car (was 3)
      cfg.migrations.faults4, changed = true, true
      if cfg.faults and cfg.faults.maxPerCar == 3 then cfg.faults.maxPerCar = 4 end
    end
    if not cfg.migrations.scoring2 then   -- 0.9.1: drivability /20 averaged, tows -2, unfixed faults -3
      cfg.migrations.scoring2, changed = true, true
      if cfg.scoring.drivabilityMaxPoints == 10 then cfg.scoring.drivabilityMaxPoints = 20 end
      if cfg.scoring.towPenaltyPoints == 1 then cfg.scoring.towPenaltyPoints = 2 end
      if cfg.faults and cfg.faults.inspectionPenaltyPoints == 1 then cfg.faults.inspectionPenaltyPoints = 3 end
    end
    if not cfg.migrations.roadside then   -- 0.8.6: repair price x markup + a smaller service fee, instead of a flat $2,000
      cfg.migrations.roadside, changed = true, true
      if cfg.economy.towFee == 2000 then cfg.economy.towFee = 1000 end
      if cfg.economy.respawnFee == 2000 then cfg.economy.respawnFee = 500 end
    end
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
local function newPlayer(name, pid)   -- (p.name = what everyone sees - an alias, cfg.aliases; p.login = BeamMP's name)
  return {
    name = (cfg.aliases or {})[name] or name, login = name, pid = pid, cash = cfg.economy.startingCash, points = 0, wins = 0,
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

-- sound bites --------------------------------------------------------------------
local soundsOff = {}   -- player name -> true: muted with /tg sounds off (kept while the server runs)
local function knownClip(clip)
  for _, c in ipairs((cfg.sounds or {}).clips or {}) do if c == clip then return true end end
  return false
end
local function sendSound(pid, clip, test)
  MP.TriggerClientEvent(pid, "tg_sound", Util.JsonEncode({ clip = clip, test = test or nil }))
end
-- play the sound for a moment (cfg.sounds.events[key]) to its audience; p = the player it's about
local function playSound(key, p)
  local sc = cfg.sounds
  local ev = sc and sc.enabled and (sc.events or {})[key]
  if type(ev) ~= "table" or type(ev.clips) ~= "table" or #ev.clips == 0 then return end
  local clip = ev.clips[math.random(#ev.clips)]
  local to, pids = ev.to or "all", {}
  if to == "self" then
    if p and p.pid then pids[1] = p.pid end
  elseif to == "near" then
    local r = tonumber(sc.nearRadius) or 100
    for _, q in pairs(game.players) do
      if q.pid and (q == p or (q.pos and p and p.pos and dist(q.pos, p.pos) <= r)) then pids[#pids + 1] = q.pid end
    end
  else   -- all / others: everyone connected, players and spectators
    for pid in pairs(MP.GetPlayers() or {}) do
      if to ~= "others" or not (p and p.pid == pid) then pids[#pids + 1] = pid end
    end
  end
  for _, pid in ipairs(pids) do
    if not soundsOff[MP.GetPlayerName(pid)] then sendSound(pid, clip) end
  end
end
local function spend(p, kind, amount)
  p.spent = p.spent or {}
  p.spent[kind] = (p.spent[kind] or 0) + amount
end

-- trailer event vehicles ---------------------------------------------------------
local function trailerPayload(tc)
  if type(tc.setup) == "table" and tc.setup.model then
    return { trailer = tc.setup.model, setup = tc.setup, count = 0, back = tc.trailerBack or 7,
             wreck = tc.setup.mode == "damage" and (tonumber(tc.wreckDamage) or 10000) or nil }
  end
  return { trailer = tc.trailerModel, cargo = tc.cargoModel, count = tc.cargoCount or 5,
           back = tc.trailerBack or 7, spacing = tc.cargoSpacing or 0.7, height = tc.cargoHeight or 0.8 }
end

local function requestTrailer(p)
  if not p.pid or (p.eventVeh and p.eventVeh.trailer) then return end
  p.trailerAsked = true
  local tc = (cfg.eventTypes or {}).trailer or {}
  local payload = trailerPayload(tc)
  p.spawnAllow = { untilT = now() + 30, trailer = payload.trailer, cargo = payload.cargo, count = payload.count or 0 }
  p.eventVeh = { cargo = {}, prebuilt = payload.setup ~= nil, intact = payload.wreck ~= nil }
  p.cargoFrac = nil
  MP.TriggerClientEvent(p.pid, "tg_trailer", Util.JsonEncode(payload))
  say(p.pid, "Your trailer and its load are being dropped behind you - reverse up, hitch it, and don't lose the cargo. " ..
    "(No tow hitch on your car? It's fitted from the parts menu in a workshop.)")
end

-- faults ---------------------------------------------------------------------
local function faultsOn() return cfg.faults and cfg.faults.enabled and not (cfg.modes or {}).noFaults end
local function playerBudget(p)   -- what the dealership lets this player spend up to
  return cfg.economy.startingCash
end
local function faultDef(id)
  for _, f in ipairs((cfg.faults or {}).list or {}) do if f.id == id then return f end end
  return nil
end
local function fixCost(p)   -- a workshop fix: a share of the car's new price (a luxury car is dear to keep running)
  local newPrice = p and (p.carNewPrice or p.carPrice) or 0
  local pct, min = tonumber(cfg.faults.fixPercent) or 0.05, tonumber(cfg.faults.fixMin) or 500
  return math.max(min, math.floor(newPrice * pct / 50 + 0.5) * 50)
end
-- Players see faults as the car's CONDITION (0.9.12): New, Used, Needs work, Beater, Death Trap = 0..4 problems.
-- (Code and config keep the word "fault"; a single fault is "a problem" to players.)
local CONDITION = { [0] = "New", "Used", "Needs work", "Beater", "Death Trap" }
function CONDITION.name(n) n = math.floor(tonumber(n) or 0); return CONDITION[math.max(0, math.min(n, 4))] end
function CONDITION.level(p)   -- the condition chosen (before buying) or the car was bought in (fixes don't change it)
  if not p then return 0 end
  if p.boughtCondition then return p.boughtCondition end
  return math.min(#(p.faults or {}) + (p.faultsOwed or 0), 4)
end
-- problem tiers (0.9.21): may this car (its condition `level`) get problem f, given the problems it already has?
function CONDITION.tier(f) return math.max(1, math.floor(tonumber(f and f.tier) or 1)) end
function CONDITION.tierOK(p, f, level)
  local fc = cfg.faults or {}
  if fc.tiers == false then return true end
  local maxTier = tonumber((fc.maxTier or {})[math.max(1, math.min(level or 1, 4))]) or 3
  local tier = CONDITION.tier(f)
  if tier > maxTier then return false end
  local cap, same = tonumber((fc.maxPerTier or {})[tier]), 0
  local mine = {}
  for _, id in ipairs(p.faults or {}) do
    local g = nil
    for _, d in ipairs(fc.list or {}) do if d.id == id then g = d end end
    if g then
      if CONDITION.tier(g) == tier then same = same + 1 end
      for _, grp in ipairs(type(g.groups) == "table" and g.groups or {}) do mine[grp] = true end
    end
  end
  if cap and same >= cap then return false end
  for _, grp in ipairs(type(f.groups) == "table" and f.groups or {}) do if mine[grp] then return false end end
  return true
end
function CONDITION.km(n) return tonumber(((cfg.faults or {}).mileageKm or {})[(n or 0) + 1]) or 0 end
-- career's used-car price: x (1 - lossPerKm x km) + scrap value (age left out); New = full price
-- the share of the condition discount a car gets for its 0-100 km/h time (acc; nil = unknown: the full discount)
function CONDITION.perfShare(acc)
  acc = tonumber(acc)
  if not acc then return 1 end
  local f = cfg.faults
  local fast, slow, min = tonumber(f.perfFastSeconds) or 4, tonumber(f.perfSlowSeconds) or 10, tonumber(f.perfMinShare) or 0.3
  if slow <= fast then return 1 end
  local t = math.max(0, math.min(1, (acc - fast) / (slow - fast)))
  return min + (1 - min) * t
end
function CONDITION.accel(model, config)   -- a trim's 0-100 km/h time from the imported details (nil if unknown)
  local e = ((cfg.dealer.gamePrices or {})[model or ""] or {})[config or ""]
  return type(e) == "table" and e.attrs and tonumber(e.attrs["0-100 km/h"]) or nil
end
function CONDITION.factor(n, acc)
  if (n or 0) <= 0 or not faultsOn() then return 1 end
  local off = tonumber(((cfg.faults or {}).discount or {})[n])   -- the condition's price off (faults.discount)...
  if not off then   -- ...or career's formula from its mileage
    local career = math.max(0, 1 - CONDITION.km(n) * (tonumber(cfg.faults.lossPerKm) or 0.0000025)) + (tonumber(cfg.faults.scrapValue) or 0.05)
    off = 1 - math.min(1, career)
  end
  return 1 - math.max(0, math.min(1, off)) * CONDITION.perfShare(acc)   -- (fast cars hold their value)
end
function CONDITION.price(n, newPrice, acc)   -- a car's price in that condition (to the nearest $100)
  if not newPrice then return nil end
  if (n or 0) <= 0 or not faultsOn() then return newPrice end
  return math.floor(newPrice * CONDITION.factor(n, acc) / 100 + 0.5 + 1e-9) * 100   -- (1e-9: 25,500 x 0.3 is 7,649.999...)
end
function CONDITION.percentOff(n, acc) return math.floor((1 - CONDITION.factor(n, acc)) * 100 + 0.5) end
-- the best (newest) condition that brings a car's new price within the budget; nil = not even as a Death Trap
function CONDITION.needed(p, newPrice, acc)
  local budget, max = playerBudget(p), math.min((cfg.faults or {}).maxPerCar or 4, 4)
  for n = 0, faultsOn() and max or 0 do
    if CONDITION.price(n, newPrice, acc) <= budget then return n end
  end
  return nil
end
function CONDITION.mileage(p)   -- { m = odometer in metres, v = paint visual value } or nil for a New car
  local n = CONDITION.level(p)
  local km = tonumber(((cfg.faults or {}).mileageKm or {})[n + 1]) or 0
  if n <= 0 or km <= 0 then return nil end
  local fresh = {}   -- parts bought new since: they start at 0 km
  for _, part in pairs(p.freshParts or {}) do fresh[#fresh + 1] = part end
  table.sort(fresh)
  return { m = math.floor(km * 1000), fresh = #fresh > 0 and fresh or nil }
end
-- Replacing a part replaces its problems (0.9.12): which problems live in which part, by the slot's own name.
-- A replaced part that had problems is scrap - no trade-in: the new part is billed at its full value.
CONDITION.SYSTEMS = {
  { name = "engine",     words = { "engine" }, not_ = { "mount", "cover", "bay" },
    faults = { "engine", "oilleak", "ignition", "idle" } },
  { name = "radiator",   words = { "radiator" },                 faults = { "cooling" } },
  { name = "turbo",      words = { "turbo" },                    faults = { "turbo" } },
  { name = "gearbox",    words = { "transmission", "gearbox" },  faults = { "synchros", "gearbox" } },
  { name = "clutch",     words = { "clutch" },                   faults = { "clutch" } },
  { name = "brakes",     words = { "brake" },                    faults = { "brakes", "brakefade" } },
  { name = "tires",      words = { "tire", "tyre", "wheel" }, not_ = { "steering" }, faults = { "tires" } },
  { name = "suspension", words = { "coilover", "spring", "damper", "shock", "strut", "swaybar", "suspension" },
    faults = { "suspension" } },
}
function CONDITION.systemOf(slot)   -- "/covet_engine/" -> the engine system (or nil)
  local own = (tostring(slot or ""):gsub("/+$", ""):match("([^/]+)$") or ""):lower()
  for _, sys in ipairs(CONDITION.SYSTEMS) do
    local hit = false
    for _, w in ipairs(sys.words) do if own:find(w, 1, true) then hit = true end end
    for _, w in ipairs(sys.not_ or {}) do if own:find(w, 1, true) then hit = false end end
    if hit then return sys end
  end
  return nil
end
-- how each problem's `factor` scales with the condition's severity:
--   loss = factor is what's left (0.8 = -20%): the loss scales, never below `floor`; noWorse = never harsher than listed
--   add  = factor is an amount: it scales, at most `cap`;  mult = factor is a multiplier: (factor - 1) scales
CONDITION.SCALE = {
  tires = { "loss", floor = 0.15 }, engine = { "loss", floor = 0.5 }, brakes = { "loss", floor = 0.3 },
  starter = { "loss", noWorse = true },
  ignition = { "add" }, cooling = { "add" }, fuelleak = { "add" }, body = { "add" }, turbo = { "add" }, oilleak = { "add" },
  clutch = { "loss", floor = 0.35 },   -- (grip: Used 80%, Beater 60%, Death Trap 48%)
  synchros = { "add", cap = 0.9 }, brakefade = { "add", cap = 1 },   -- (synchros: at 1 BeamNG breaks the gear - Ryan's Death Trap had no 2nd/3rd)
  idle = { "mult" }, gearbox = { "mult" },
}
function CONDITION.sevOf(n)   -- condition 1..4 -> how bad its problems are (faults.severity); New: as listed
  if not n or n <= 0 then return 1 end
  return tonumber(((cfg.faults or {}).severity or {})[n]) or 1
end
function CONDITION.severity(p) return CONDITION.sevOf(CONDITION.level(p)) end
-- what the client gets for one problem at severity sev (a bought car's, or an admin's fault test "as" a condition):
-- the factor scaled, ignition cut-outs further apart / closer, the alignment pull x sev on `side` (-1 left, +1 right)
function CONDITION.payload(f, sev, side, doomed)
  local calmer = sev > 0 and sev or 1
  local pull = tonumber(f.pull)
  if f.id == "alignment" and pull and pull > 0 then pull = pull * sev * (side or 1) else pull = nil end
  local starter = (f.id == "ignition" and tonumber(f.starter)) and CONDITION.scaled({ id = "starter", factor = f.starter }, sev) or nil
  return { id = f.id, factor = CONDITION.scaled(f, sev), refresh = f.refresh, pull = pull, starter = starter,
           cutoutMin = f.cutoutMin and f.cutoutMin / calmer, cutoutMax = f.cutoutMax and f.cutoutMax / calmer,
           blowMin = f.blowMin, blowMax = f.blowMax, fireMin = f.fireMin, fireMax = f.fireMax, doomed = doomed or nil }
end
function CONDITION.scaled(f, s)   -- a problem's factor for a car of severity s
  local how, fac = CONDITION.SCALE[f.id], tonumber(f.factor)
  if not how or not fac or s == 1 then return f.factor end
  if how.noWorse and s > 1 then s = 1 end
  if how[1] == "loss" then return math.max(how.floor or 0, 1 - (1 - fac) * s) end
  if how[1] == "mult" then return 1 + (fac - 1) * s end
  return math.min(how.cap or math.huge, fac * s)
end
function CONDITION.problemName(p, id)   -- the name, with its "-20%" made to fit this car's severity
  local f = faultDef(id)
  if not f then return id end
  local how = CONDITION.SCALE[id]
  if how and how[1] == "loss" and p then
    local left = CONDITION.scaled(f, CONDITION.severity(p))
    return (f.name:gsub("%-%d+%%", "-" .. math.floor((1 - left) * 100 + 0.5) .. "%%"))
  end
  if id == "alignment" and p and p.alignSide and tonumber(f.pull) and f.pull > 0 then
    return f.name .. (p.alignSide < 0 and " (pulls to the left)" or " (pulls to the right)")
  end
  return f.name
end
function CONDITION.parse(text)   -- "3", "beater", "needs work" -> 3
  text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if tonumber(text) then return math.floor(tonumber(text)) end
  for i = 0, 4 do if CONDITION[i]:lower() == text then return i end end
  return nil
end
local function hasFault(p, id)
  for _, x in ipairs(p.faults or {}) do if x == id then return true end end
  return false
end
-- the damage the accident damage problem gives the car itself: it comes straight back after any repair, so it's
-- never billed as a repair (only fixing the problem removes it). 0 without that problem.
function CONDITION.dents(p)
  if not hasFault(p, "body") then return 0 end
  return tonumber(CONDITION.scaled(faultDef("body") or {}, CONDITION.severity(p))) or 0
end
local function removeFault(p, id)
  for i, x in ipairs(p.faults or {}) do if x == id then table.remove(p.faults, i); return true end end
  return false
end
local function faultNames(p)
  local names = {}
  for _, id in ipairs(p.faults or {}) do names[#names + 1] = CONDITION.problemName(p, id) end
  return names
end
local SETUP_FAULTS = { tires = true, alignment = true, body = true, suspension = true,   -- these respawn the car (body: the bumpers)
                       bumpers = true }   -- (accident damage's bumper record in faultRestore keeps this key)

-- faults taken = drawn ones + ones paid for but not drawn yet (no car yet)
local function faultsTaken(p) return #(p.faults or {}) + (p.faultsOwed or 0) end
-- what we've learnt about which faults each car can take: cfg.faultCaps["model/config"] = { ok = {}, no = {} }
local function carKey(p) return tostring(p.carModel) .. "/" .. tostring(p.carConfig or "") end
local function capsFor(p)
  cfg.faultCaps = cfg.faultCaps or {}
  local k = carKey(p)
  cfg.faultCaps[k] = cfg.faultCaps[k] or { ok = {}, no = {} }
  return cfg.faultCaps[k]
end
-- a random enabled fault this car doesn't have and isn't known to be unable to take
local function rollFault(p)
  local caps, tried, cands = capsFor(p), p.faultTried or {}, {}
  local level = CONDITION.level(p)
  for _, f in ipairs(cfg.faults.list or {}) do
    local tooNew = tonumber(f.minCondition) and level < tonumber(f.minCondition)   -- e.g. oil leak: Beaters and worse
    if f.enabled ~= false and not tooNew and not hasFault(p, f.id) and not caps.no[f.id] and not tried[f.id]
       and CONDITION.tierOK(p, f, level) then cands[#cands + 1] = f.id end
  end
  if #cands == 0 then return nil end
  return cands[math.random(#cands)]
end
-- turn faults paid for into real ones for the car the player has; hand back what the car can't take
local function drawFaults(p)
  if not p.carModel then return end
  while (p.faultsOwed or 0) > 0 do
    local id = rollFault(p)
    if not id then break end
    if id == "oilleak" then   -- the secret roll: is this engine going to blow?
      local f = faultDef(id)
      local chance = math.min(1, (tonumber(f and f.blowChance) or 0.2) * CONDITION.severity(p))   -- (a Death Trap's is likelier)
      p.oilDoomed, p.oilBlown = math.random() < chance, false
    elseif id == "fuelleak" then   -- (0.9.26, Ryan) the secret roll: will this one catch fire? (once)
      local f = faultDef(id)
      local chance = cfg.faults.fires == false and 0 or (tonumber(f and f.fireChance) or 0.2)
      p.fuelDoomed, p.fuelBurnt = chance > 0 and math.random() < chance, false
    end
    p.faults[#p.faults + 1] = id
    p.faultsOwed = p.faultsOwed - 1
  end
  if (p.faultsOwed or 0) > 0 then   -- the car can't take that many problems: it keeps its condition (and price)
    log(string.format("%s's %s can't take %d more problem(s)", p.name, carKey(p), p.faultsOwed))
    p.faultsOwed = 0
  end
end
-- a different car (bought, swapped or returned at the dealership): its faults get drawn again
local function redrawFaults(p)
  p.faultsOwed = faultsTaken(p)
  p.faults, p.faultRestore, p.faultTried = {}, {}, {}
  p.oilDoomed, p.oilBlown = nil, nil
  p.fuelDoomed, p.fuelBurnt = nil, nil
  drawFaults(p)
  CONDITION.drawQuirks(p)   -- (and its quirks)
end
-- a workshop diagnoses the car: the player finds out what they've got
local function revealFaults(p)
  if p.faultsRevealed or #(p.faults or {}) == 0 then return end
  p.faultsRevealed = true
  local lines = {}
  for _, id in ipairs(p.faults) do
    local f = faultDef(id)
    lines[#lines + 1] = string.format("%s (/tg fix %s)", f and CONDITION.problemName(p, id) or id, id)
  end
  say(p.pid, "The mechanics have looked your car over and found: " .. table.concat(lines, ", ") .. ".")
  say(p.pid, string.format("Each fix costs %s here; every problem still there at the finale costs %s point%s.",
    money(fixCost(p)), tostring(cfg.faults.inspectionPenaltyPoints or 0), (cfg.faults.inspectionPenaltyPoints or 0) == 1 and "" or "s"))
end

local function sendFaults(p, test)
  if not p.pid then return end
  local list, setup = {}, false
  local sev = CONDITION.severity(p)   -- more worn, worse problems
  for _, id in ipairs(p.faults or {}) do
    local f = faultDef(id)
    if f then
      if f.id == "alignment" and tonumber(f.pull) and not p.alignSide then   -- which way it pulls: once per car (kept through fixes)
        p.alignSide = math.random() < 0.5 and -1 or 1
      end
      list[#list + 1] = CONDITION.payload(f, sev, p.alignSide, (f.id == "oilleak" and p.oilDoomed and not p.oilBlown)
        or (f.id == "fuelleak" and p.fuelDoomed and not p.fuelBurnt))
      setup = setup or SETUP_FAULTS[f.id] or false
    end
  end
  for id in pairs(p.faultRestore or {}) do setup = setup or SETUP_FAULTS[id] or false end
  -- a setup fault change respawns the car: accept that edit without billing it
  if setup then p.faultEditUntil = now() + 15 end
  MP.TriggerClientEvent(p.pid, "tg_faults", Util.JsonEncode({ faults = list, restore = p.faultRestore or {}, test = test or false,
    mileage = (not test) and CONDITION.mileage(p) or nil }))
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

-- Car classes -----------------------------------------------------------------------
local chosenClass = nil   -- the class for the next / current challenge (picked each time, not saved)
local Class = {}          -- the class helpers (kept in one table: Lua allows only 200 locals per chunk)
local Save = {}           -- the running challenge saved to session.json (crash / restart protection), defined further down

-- chat name -> BeamNG attribute (the filters of the game's own vehicle menu); "list" or "range"
Class.FIELDS = {
  brand = { "Brand", "list" }, country = { "Country", "list" }, body = { "Body Style", "list" }, type = { "Type", "list" },
  drivetrain = { "Drivetrain", "list" }, transmission = { "Transmission", "list" }, fuel = { "Fuel Type", "list" },
  propulsion = { "Propulsion", "list" }, induction = { "Induction Type", "list" }, configtype = { "Config Type", "list" },
  performance = { "Performance Class", "list" }, derby = { "Derby Class", "list" },
  years = { "Years", "range" }, value = { "Value", "range" }, weight = { "Weight", "range" },
  topspeed = { "Top Speed", "range" }, accel = { "0-100 km/h", "range" }, offroad = { "Off-Road Score", "range" },
  trims = { "Trims", "base" },   -- "base": only each model's cheapest factory trim
}
Class.ORDER = { "country", "brand", "body", "type", "years", "transmission", "drivetrain", "fuel", "propulsion",
  "induction", "configtype", "performance", "derby", "value", "weight", "topspeed", "accel", "offroad", "trims" }

function Class.def(name) return name and (cfg.dealer.classes or {})[name] or nil end
local function activeClass() return Class.def(chosenClass) end
-- With no class picked, a full import (/tg importprices with no names) sells every imported car and truck;
-- before one, the dealer list (cfg.dealer.cars) is used.
Class.ALL = { rules = { { field = "Type", values = { "Car", "Truck" } } }, include = {}, exclude = {}, prices = {}, multiplier = 1 }
function Class.selling()   -- the class the dealership sells from (nil = the dealer list)
  local cls = activeClass()
  if cls then return cls, chosenClass end
  if cfg.dealer.useGamePrices and cfg.dealer.importedAll then return Class.ALL, nil end
  return nil
end
function Class.noneText()
  return cfg.dealer.importedAll and "no class - every imported car and truck" or "no class - the normal dealer list"
end
-- Ready-made classes (/tg class preset <key>, or the Admin tab): ordinary classes, editable once made.
Class.PRESETS = {
  { key = "allcars",    title = "Every car and truck",  rules = { { field = "Type", values = { "Car", "Truck" } } } },
  { key = "basetrims",  title = "Base trims only",      rules = { { field = "Trims", base = true }, { field = "Type", values = { "Car", "Truck" } } } },
  { key = "jdm",        title = "Japanese cars",        rules = { { field = "Country", values = { "Japan" } }, { field = "Type", values = { "Car" } } } },
  { key = "american",   title = "American cars and trucks", rules = { { field = "Country", values = { "United States" } }, { field = "Type", values = { "Car", "Truck" } } } },
  { key = "euro",       title = "European cars",        rules = { { field = "Country", values = { "Germany", "Italy", "France", "Poland" } }, { field = "Type", values = { "Car" } } } },
  { key = "classics",   title = "Classics (up to 1979)", rules = { { field = "Years", max = 1979 }, { field = "Type", values = { "Car" } } } },
  { key = "retro",      title = "80s and 90s cars",     rules = { { field = "Years", min = 1980, max = 1999 }, { field = "Type", values = { "Car" } } } },
  { key = "modern",     title = "2000 and newer",       rules = { { field = "Years", min = 2000 }, { field = "Type", values = { "Car", "Truck" } } } },
  { key = "muscle",     title = "American muscle (RWD, 1960s-70s)", rules = { { field = "Country", values = { "United States" } },
      { field = "Body Style", values = { "Coupe", "Sedan" } }, { field = "Drivetrain", values = { "RWD" } }, { field = "Years", min = 1960, max = 1979 } } },
  { key = "hothatch",   title = "Hot hatches (0-100 in 9 s or less)", rules = { { field = "Body Style", values = { "Hatchback" } }, { field = "0-100 km/h", max = 9 } } },
  { key = "small",      title = "Small cars",           rules = { { field = "Derby Class", values = { "Sub-Compact Car", "Sub-Compact", "Compact Car" } } } },
  { key = "sports",     title = "Sports cars",          rules = { { field = "Derby Class", values = { "Sports Car" } } } },
  { key = "offroad",    title = "Pickups and 4x4s",     rules = { { field = "Body Style", values = { "Pickup", "SUV" } }, { field = "Drivetrain", values = { "4WD", "AWD", "4x4" } } } },
  { key = "vans",       title = "Vans and minivans",    rules = { { field = "Body Style", values = { "Van", "Minivan" } } } },
  { key = "police",     title = "Police cars",          rules = { { field = "Config Type", values = { "Police" } } } },
  { key = "motorsport", title = "Race, rally and drift builds", rules = { { field = "Config Type", values = { "Race", "Rally", "Drift" } } } },
  { key = "specials",   title = "Specials: derby, Gambler 500, ratrods and other custom builds", rules = { { field = "Config Type", values = { "Custom", "Powerglow" } }, { field = "Type", values = { "Car" } } } },
  { key = "commercial", title = "Commercial trucks and buses", rules = { { field = "Commercial Class", values = { "Class 4 Truck", "Class 6 Truck", "Class 7 Truck", "Class 8 Truck", "Transit Bus" } } } },
}
function Class.preset(key)
  for _, pr in ipairs(Class.PRESETS) do if pr.key == key then return pr end end
  return nil
end
function Class.rangeText(lo, hi)
  if lo and hi then return lo == hi and tostring(lo) or (tostring(lo) .. "-" .. tostring(hi)) end
  if lo then return tostring(lo) .. " and up" end
  return "up to " .. tostring(hi)
end
function Class.ruleText(r)
  if r.base then return "Base trims only" end
  if r.values then return r.field .. ": " .. table.concat(r.values, ", ") end
  return r.field .. " " .. Class.rangeText(r.min, r.max)
end
local function classSummary(cls)
  local parts = {}
  for _, r in ipairs(cls.rules or {}) do parts[#parts + 1] = Class.ruleText(r) end
  if #(cls.include or {}) > 0 then parts[#parts + 1] = "plus " .. table.concat(cls.include, ", ") end
  if #(cls.exclude or {}) > 0 then parts[#parts + 1] = "not " .. table.concat(cls.exclude, ", ") end
  if tonumber(cls.multiplier) and tonumber(cls.multiplier) ~= 1 then parts[#parts + 1] = "prices x" .. tostring(cls.multiplier) end
  return #parts > 0 and table.concat(parts, "; ") or "no rules yet"
end
-- does one rule match a trim's attributes? (a range matches if it overlaps, e.g. Years 1987-1995 vs 1985-1999)
local function trimPrice(model, config, entry)   -- before any class: the dealership price list, else the game's value
  local o = tonumber((cfg.dealer.prices or {})[model .. "/" .. tostring(config)])
  if o then return math.floor(o) end
  if entry and tonumber(entry.price) then return math.floor(tonumber(entry.price)) end
  return entry and tonumber(entry.est) and math.floor(tonumber(entry.est)) or nil   -- estimated from similar cars
end
function Class.isEstimate(model, config, entry)   -- priced only by the estimate (no game value, no /tg setprice)
  return type(entry) == "table" and not tonumber(entry.price) and tonumber(entry.est) ~= nil
     and not tonumber((cfg.dealer.prices or {})[model .. "/" .. tostring(config)])
end

-- Not cars: props (cones, barriers, AI traffic stand-ins, the walking unicycle), trailers and debug objects are
-- never sold, so the import drops them.
function Class.notACar(entry)
  local ty = type(entry) == "table" and entry.attrs and entry.attrs.Type
  return type(ty) == "string" and (ty:find("^Prop") ~= nil or ty == "Trailer" or ty == "Debug")
end
function Class.dropNonCars()
  local n = 0
  for model, trims in pairs(cfg.dealer.gamePrices or {}) do
    for config, e in pairs(trims) do
      if Class.notACar(e) then trims[config] = nil; n = n + 1 end
    end
    if next(trims) == nil then cfg.dealer.gamePrices[model] = nil end
  end
  return n
end

-- Price estimates for trims the game has no value for: the median price of the 5 most similar priced trims,
-- compared on power-to-weight, 0-100 km/h, top speed, weight, year and off-road score (the same model and the
-- same type count as closer). Tested on the real game's priced trims: half land within ~11% of their price.
-- With no performance figures, the median of the model's own priced trims. Rounded to $100.
function Class.features(a)
  if type(a) ~= "table" or not tonumber(a["Weight/Power"]) or tonumber(a["Weight/Power"]) <= 0 then return nil end
  local y, year = a.Years, nil
  if type(y) == "table" and (tonumber(y.min) or tonumber(y.max)) then year = ((tonumber(y.min) or y.max) + (tonumber(y.max) or y.min)) / 2
  elseif tonumber(y) then year = tonumber(y) end
  local acc, top, wt, off = tonumber(a["0-100 km/h"]), tonumber(a["Top Speed"]), tonumber(a.Weight), tonumber(a["Off-Road Score"])
  return { math.log(tonumber(a["Weight/Power"])), acc and acc > 0 and math.log(math.max(acc, 2)) or false,
           top and top / 10 or false, year and (year - 1990) / 10 or false, off and off / 20 or false,
           wt and wt > 0 and 2 * math.log(wt) or false }
end
function Class.median(list)
  if #list == 0 then return nil end
  table.sort(list)
  local m = (#list + 1) / 2
  return (list[math.floor(m)] + list[math.ceil(m)]) / 2
end
function Class.estimatePrices()
  local pool, byModel = {}, {}
  for model, trims in pairs(cfg.dealer.gamePrices or {}) do
    for _, e in pairs(trims) do
      if type(e) == "table" and tonumber(e.price) and tonumber(e.price) > 0 then
        local f = Class.features(e.attrs)
        if f then pool[#pool + 1] = { model = model, f = f, ty = e.attrs.Type, price = tonumber(e.price) } end
        byModel[model] = byModel[model] or {}
        table.insert(byModel[model], tonumber(e.price))
      end
    end
  end
  local n, changed = 0, false
  for model, trims in pairs(cfg.dealer.gamePrices or {}) do
    for _, e in pairs(trims) do
      if type(e) == "table" and not tonumber(e.price) then
        local was = e.est
        e.est = nil
        local f, est = Class.features(e.attrs), nil
        if f and #pool > 0 then
          local near = {}
          for _, q in ipairs(pool) do
            local d = 0
            for i = 1, #f do
              if f[i] and q.f[i] then d = d + (f[i] - q.f[i]) ^ 2 else d = d + 1 end
            end
            if q.ty ~= (e.attrs or {}).Type then d = d + 4 end
            if q.model == model then d = d * 0.5 end
            near[#near + 1] = { d = d, price = q.price }
          end
          table.sort(near, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.price < b.price end)
          local prices = {}
          for i = 1, math.min(5, #near) do prices[i] = near[i].price end
          est = Class.median(prices)
        elseif byModel[model] then
          local copy = {}
          for i, v in ipairs(byModel[model]) do copy[i] = v end
          est = Class.median(copy)
        end
        if est then e.est = math.max(100, math.floor(est / 100 + 0.5) * 100); n = n + 1 end
        if e.est ~= was then changed = true end
      end
    end
  end
  return n, changed
end
-- the built-in catalogue (cars.json), used while the server has no import of its own
function Class.loadBuiltin()
  local s = readFile(CARS_PATH)
  if not s then return false, "cars.json is missing" end
  local ok, t = pcall(Util.JsonDecode, s)
  if not ok or type(t) ~= "table" or type(t.gamePrices) ~= "table" then return false, "cars.json is not valid" end
  cfg.dealer.gamePrices = t.gamePrices
  cfg.dealer.modelNames = cfg.dealer.modelNames or {}
  for k, v in pairs(t.modelNames or {}) do if cfg.dealer.modelNames[k] == nil then cfg.dealer.modelNames[k] = v end end
  local first = cfg.dealer.catalogue ~= "builtin"
  if first then   -- first time: sell from it (an admin's /tg gameprices off is kept after)
    cfg.dealer.catalogue, cfg.dealer.useGamePrices = "builtin", true
  end
  cfg.dealer.importedAll = true
  return true, tonumber(t.trims) or 0, first
end
-- after an import, and on loading a config imported by an older version
function Class.tidyImport()
  Class.presetCounts = nil
  local dropped = Class.dropNonCars()
  local n, changed = Class.estimatePrices()
  return dropped, n, changed or dropped > 0
end
-- a model's base trim: its cheapest factory trim that has a price
function Class.baseTrim(model)
  local best, bestPrice
  for config, e in pairs((cfg.dealer.gamePrices or {})[model] or {}) do
    local ct = type(e) == "table" and e.attrs and e.attrs["Config Type"]
    local price = type(e) == "table" and trimPrice(model, config, e)
    if price and (ct == nil or ct == "Factory") and (not bestPrice or price < bestPrice or (price == bestPrice and config < best)) then
      best, bestPrice = config, price
    end
  end
  return best
end
function Class.ruleCheck(r, attrs, model, config)
  if r.base then
    local base = Class.baseTrim(model)
    if base == config then return true end
    return false, base and ("not the base trim (that's " .. (((cfg.dealer.gamePrices or {})[model] or {})[base] or {}).name .. ")")
                        or "this model has no priced factory trim"
  end
  local v = attrs and attrs[r.field]
  if r.values then
    if v == nil then return false, r.field .. " unknown" end
    local sv = tostring(v):lower()
    for _, x in ipairs(r.values) do if tostring(x):lower() == sv then return true end end
    return false, r.field .. " is " .. tostring(v)
  end
  local lo, hi
  if type(v) == "table" then lo, hi = tonumber(v.min), tonumber(v.max) else lo = tonumber(v) end
  hi = hi or lo
  lo = lo or hi
  if not lo then return false, r.field .. " unknown" end
  if (r.min and hi < r.min) or (r.max and lo > r.max) then
    local have = (hi ~= lo) and (tostring(lo) .. "-" .. tostring(hi)) or tostring(lo)
    return false, string.format("%s %s (needs %s)", r.field, have, Class.rangeText(r.min, r.max))
  end
  return true
end
function Class.inPickList(list, model, config)
  for _, k in ipairs(list or {}) do
    if k == model or (config and k == model .. "/" .. config) then return true end
  end
  return false
end
function Class.match(cls, model, config, entry)
  if Class.inPickList(cls.exclude, model, config) then return false, "left out of the class" end
  if Class.inPickList(cls.include, model, config) then return true end
  if #(cls.rules or {}) == 0 then return false, "not picked for the class" end
  for _, r in ipairs(cls.rules) do
    local ok, why = Class.ruleCheck(r, entry and entry.attrs, model, config)
    if not ok then return false, why end
  end
  return true
end
function Class.price(cls, model, config, entry)   -- nil = no price anywhere (can't be sold yet)
  local o = tonumber((cls.prices or {})[model .. "/" .. tostring(config)])
  if o then return math.floor(o) end
  local base = trimPrice(model, config, entry)
  return base and math.floor(base * (tonumber(cls.multiplier) or 1) + 0.5) or nil
end
-- every imported trim in a class that can be sold (has a price): { model, config, name, modelName, price }, cheapest
-- first. withUnpriced: also the matching trims with no price yet (price = nil), for the admin's list.
local function classTrims(cls, withUnpriced)
  local out = {}
  for model, trims in pairs(cfg.dealer.gamePrices or {}) do
    for config, e in pairs(trims) do
      if type(e) == "table" and Class.match(cls, model, config, e) then
        local price = Class.price(cls, model, config, e)
        if price or withUnpriced then
          out[#out + 1] = { model = model, config = config, name = e.name or (model .. " " .. config), price = price,
                            modelName = (cfg.dealer.modelNames or {})[model] or model,
                            est = Class.isEstimate(model, config, e) and not tonumber((cls.prices or {})[model .. "/" .. config]) }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if (a.price ~= nil) ~= (b.price ~= nil) then return a.price ~= nil end   -- priced first
    if a.price and b.price and a.price ~= b.price then return a.price < b.price end
    return a.name < b.name
  end)
  return out
end
-- 0 = affordable now; n = n more faults would cover it; nil = out of reach even with the most faults
-- 0 = affordable in the chosen condition; n = n conditions worse would bring it within budget; nil = out of reach
-- (newPrice = the car's price as new)
local function faultsNeeded(p, newPrice, acc)
  local need = CONDITION.needed(p, newPrice, acc)
  if not need then return nil end
  return math.max(0, need - CONDITION.level(p))
end

local function lookupCar(model, config)
  if not model then return nil, "unknown vehicle" end
  local cls, cname = Class.selling()
  if cls then   -- today's class (or every imported car) decides what's sold, at its prices
    local e = ((cfg.dealer.gamePrices or {})[model] or {})[config or ""]
    if not e then return nil, "only stock trims are sold (/tg importprices reads them)" end
    local ok, why = Class.match(cls, model, config, e)
    if not ok then return nil, cname and ("not in today's class (" .. cname .. "): " .. why) or ("not a car or truck: " .. why) end
    local price = Class.price(cls, model, config, e)
    if not price then return nil, "it has no price yet (admin: /tg setprice " .. model .. "/" .. config .. " <amount>)" end
    return { model = model, config = config, name = e.name or (model .. " " .. config), price = price }
  end
  if cfg.dealer.useGamePrices then
    if not modelListed(model) then return nil, "not sold here" end
    local gp = (cfg.dealer.gamePrices or {})[model]
    if not gp then return nil, "no imported prices for this model (/tg importprices)" end
    local e = config and gp[config]
    local price = e and trimPrice(model, config, e)
    if not price then return nil, "not a stock trim with a price (custom configs aren't sold; admin: /tg setprice)" end
    return { model = model, config = config, name = e.name or (model .. " " .. config), price = price }
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
-- car.price is the price as new; the player pays it in their chosen condition (locked in from now on)
local function setCar(p, vid, model, config, car)
  p.carVid, p.carModel, p.carConfig = vid, model, config
  p.boughtCondition = math.min(#(p.faults or {}) + (p.faultsOwed or 0), 4)
  p.carName, p.carNewPrice = car.name, car.price
  p.carPrice = CONDITION.price(p.boughtCondition, car.price, CONDITION.accel(model, config))
  p.conditionSaving = car.price - p.carPrice
  p.freshParts = {}   -- (parts fitted from now on are new: 0 km)
end
local function refundCar(p)
  p.faultsOwed = #(p.faults or {}) + (p.faultsOwed or 0)   -- faults stay paid for; drawn again for the next car
  p.faults, p.faultRestore, p.faultTried = {}, {}, {}
  p.quirks, p.quirkAt = nil, nil
  p.cash = p.cash + (p.carPrice or 0) + (p.dealerParts or 0)   -- upgrades fitted at the dealership go back with it
  if (p.dealerParts or 0) ~= 0 then spend(p, "upgrades", -p.dealerParts) end
  p.dealerParts = 0
  p.carVid, p.carModel, p.carConfig, p.carName, p.carPrice = nil, nil, nil, nil, 0
  p.boughtCondition, p.carNewPrice, p.conditionSaving, p.freshParts = nil, nil, nil, nil   -- (the condition can be changed again)
  p.alignSide = nil   -- (the next car pulls whichever way it pulls)
  p.ready = false
end

---------------------------------------------------------------------------
-- Targets / HUD state
---------------------------------------------------------------------------
local function curEvent() return (game.events or {})[game.stage] end

local TYPE_ORDER = { "race", "circuit", "speedtrap", "parking", "fragile", "economy", "slalom", "trailer", "rpc" }
local TYPE_INFO = {
  race      = { label = "Destination race",  name = "The Race" },
  circuit   = { label = "Circuit race",      name = "The Circuit" },
  speedtrap = { label = "Speed trap",        name = "The Speed Trap" },
  parking   = { label = "Precision parking", name = "Precision Parking" },
  fragile   = { label = "Fragile delivery",  name = "Fragile Delivery" },
  economy   = { label = "Economy run",       name = "The Economy Run" },
  slalom    = { label = "Slalom",            name = "The Slalom" },
  trailer   = { label = "Trailer delivery",  name = "Trailer Delivery" },
  rpc       = { label = "Star in a reasonably priced car", name = "Star in a Reasonably Priced Car" },
}
-- Mode: every event runs in race mode (everyone at once) or time trial mode (one at a time, in arrival
-- order). e.solo stores an explicit choice; without one, speed traps, parking and slalom default to time trial mode.
local SOLO_DEFAULT = { speedtrap = true, parking = true, slalom = true }
local function isSolo(e)
  if e.type == "rpc" then return true end   -- one reasonably priced car on track at a time, always
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
  -- (0.9.13, Ryan: parts only in the dealership and workshop phases - no more grace after the doors close)
  if game.phase ~= "workshop" then return false end
  if #workshopSpots() == 0 then return true end
  return p.inShop == true
end
local function enabledEvents()
  local out = {}
  for _, e in ipairs(cfg.events) do if e.enabled ~= false then out[#out + 1] = e end end
  return out
end
local Course = {}   -- course helpers (filled in further down; declared here for the targets just below)
-- which way a start faces (0.9.23, Ryan: drivers didn't know which way to line up): the way the admin's car pointed at
-- Set start here (e.startDir, from their game), else towards the first checkpoint / trap / bay. { x, y } or nil.
function Course.startFace(e)
  local d = type(e) == "table" and e.startDir
  if type(d) == "table" and tonumber(d.x) and tonumber(d.y) and (d.x * d.x + d.y * d.y) > 0.01 then
    local len = math.sqrt(d.x * d.x + d.y * d.y)
    return { x = d.x / len, y = d.y / len }
  end
  local start = type(e) == "table" and v3(e.start)
  local ahead = start and (v3((e.checkpoints or {})[1]) or v3(e.trap) or v3((e.bays or {})[1] or e.bay))
  if not ahead then return nil end
  local dx, dy = ahead.x - start.x, ahead.y - start.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.5 then return nil end
  return { x = dx / len, y = dy / len }
end
function Course.startLook(e)   -- a point 20 m ahead of the start, the way it faces (for "facing ..." placements)
  local f, start = Course.startFace(e), v3(e.start)
  if not (f and start) then return nil end
  return { x = start.x + f.x * 20, y = start.y + f.y * 20, z = start.z }
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
  local tgt = legTarget(p, e.via, e.start, e.startRadius or cfg.defaults.startRadius, e.name .. " - start")
  if tgt and tgt.kind == "dest" then tgt.face = Course.startFace(e) end   -- (an arrow: which way to line up)
  return tgt
end
local function finaleTarget(p)
  local f = cfg.finale
  return legTarget(p, f.via, f.pos, f.radius or cfg.defaults.startRadius, f.name .. " - finish")
end

local function currentTarget(p)
  local e, ph = curEvent(), game.phase
  if ph == "travel" and e then return eventStartTarget(p, e)
  elseif ph == "countdown" and e then
    return { pos = e.start, r = e.startRadius or cfg.defaults.startRadius, label = e.name .. " - start", face = Course.startFace(e) }
  elseif ph == "event" and e and (p.run.status == "waiting" or (p.run.status == "staged" and isSolo(e))) then
    local runner = game.solo and game.solo.runner
    return { pos = e.start, r = e.startRadius or cfg.defaults.startRadius, face = Course.startFace(e),
             label = (p.run.status == "staged" and game.solo and game.solo.waitGo) and "Your turn - press GO when ready"
               or p.run.status == "staged" and "Your run - get ready"
               or ("Wait at the start" .. (runner and (" - " .. runner.name .. ((game.solo and game.solo.waitGo) and "'s turn (waiting for GO)" or " is running")) or "")) }
  elseif ph == "event" and e and p.run.status == "running" then
    if e.type == "parking" then
      local bays = eventBays(e)
      local i = p.run.bay or 1
      local b = type(bays[i]) == "table" and bays[i] or {}
      return { pos = bays[i], r = typeCfg("parking").bayRadius or 5,
               dir = (tonumber(b.dx) and tonumber(b.dy)) and { x = b.dx, y = b.dy } or nil,   -- (older bays: none - a plain marker)
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
    if e.type == "circuit" or e.type == "rpc" then
      local laps = math.max(1, math.floor(tonumber(e.laps) or 3))
      local last = p.run.cp >= #cps
      local c = cps[p.run.cp]
      return { pos = c, r = (type(c) == "table" and tonumber(c.r)) or e.cpRadius or cfg.defaults.cpRadius,
               line = type(c) == "table" and c.line or nil,
               label = string.format("Lap %d/%d - %s", p.run.lap or 1, laps,
                 last and ((p.run.lap or 1) >= laps and "FINISH" or "Start/finish line") or string.format("Checkpoint %d/%d", p.run.cp, #cps - 1)) }
    end
    local c = cps[p.run.cp]
    return { pos = c, r = (type(c) == "table" and tonumber(c.r)) or e.cpRadius or cfg.defaults.cpRadius,
             line = type(c) == "table" and c.line or nil,
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
  elseif ph == "results" then return "Challenge complete"
  elseif ph == "paused" then return "Challenge saved - waiting for an admin to /tg resume" end
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
    budget = ph == "dealer" and playerBudget(p) or nil,   -- (the vehicle selector's list follows these)
    condition = ph == "dealer" and CONDITION.level(p) or nil,
    car = p.carName, carId = p.carVid and (tostring(p.pid) .. "-" .. tostring(p.carVid)) or nil,
    allowVehicleSelector = (ph == "dealer") or inTrafficMode(p.name),
    traffic = inTrafficMode(p.name) or nil,
    allowParts = inWorkshop(p),
    allowReset = (ph == "dealer" or ph == "results"),
    timeLeft = timeLeft(),
    eventType = curEvent() and curEvent().type or nil,
    quirks = (p.quirks and #p.quirks > 0) and p.quirks or nil,   -- (the client keeps the squeaky brakes squeaking)
    turbo = p.effects and (p.effects.horn or p.effects.frbrake or p.effects.tune) and {   -- (Turbo Mode on this car)
      horn = p.effects.horn or nil, frontRight = p.effects.frbrake and (tonumber((cfg.turbo or {}).frontRight) or 3) or nil,
      tune = (p.effects.tune and (p.effects.tuneNow or ph == "countdown" or ph == "event")) and (tonumber((cfg.turbo or {}).tune) or 1.1) or nil } or nil,
  }
  if ph == "countdown" and game.countdownEnd then
    s.lights = { left = game.countdownEnd - now(), total = cfg.defaults.countdown }
  elseif ph == "event" and game.solo and game.solo.runner and game.solo.runner.run.status == "staged" and game.solo.countEnd then
    s.lights = { left = game.solo.countEnd - now(), total = game.solo.countTotal or cfg.defaults.countdown, who = game.solo.runner.name }
  end
  local tgt = currentTarget(p)
  local tp = tgt and v3(tgt.pos)
  if tp then s.target = { x = tp.x, y = tp.y, z = tp.z, r = tgt.r, label = tgt.label, line = tgt.line, dir = tgt.dir, face = tgt.face } end
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
-- the repair price for damage d: in a workshop (the discount), or full = the price roadside help is based on
local function repairQuote(p, full, d)
  local ec = cfg.economy
  d = d or p.damage or 0
  -- (0.9.13, Ryan's bug: the accident damage problem's dents were billed, repaired, put back, billed again - only the
  -- damage beyond them counts; under 20% of them more - its broken glass and lights - is nothing to repair)
  local dents = CONDITION.dents(p)
  if dents > 0 then
    d = d - dents
    if d < math.max(ec.repairMinDamage or 50, dents * 0.2) then return 0 end
  end
  if d < (ec.repairMinDamage or 50) then return 0 end
  local price = math.floor(ec.repairBaseFee + math.min(d * ec.repairCostPerDamage, ec.repairCap) + 0.5)
  if full then return price end
  return math.floor(price * (1 - (tonumber(ec.workshopDiscount) or 0)) + 0.5)
end
-- Scoring helpers (one table: main.lua is near Lua's 200-local limit) -------------------
local Score = {}
-- one drivability inspection: maxPoints x (1 - damage / damageForZeroDrivability); `score` given = fixed (e.g. 0)
function Score.inspect(p, where, score, note)
  local sc, dmg = cfg.scoring, math.floor(p.damage or 0)
  if score == nil then
    local frac = math.max(0, 1 - dmg / (sc.damageForZeroDrivability or 20000))
    score = math.floor((sc.drivabilityMaxPoints or 20) * frac * 10 + 0.5) / 10
  end
  p.inspections = p.inspections or {}
  p.inspections[#p.inspections + 1] = { where = where, damage = dmg, score = score, note = note }
  return score
end
-- the drivability score: the average of every inspection
function Score.average(p)
  local sum, n = 0, 0
  for _, i in ipairs(p.inspections or {}) do sum, n = sum + i.score, n + 1 end
  if n == 0 then return 0 end
  return math.floor(sum / n * 10 + 0.5) / 10
end
-- was p's car brought by an admin (Bring to me) in this phase - this leg's travel, or this workshop? Then it doesn't
-- count as arriving first (no bonus, no Turbo prize).
function Score.brought(p, phase)
  local b = p.broughtAt
  if not b or b.phase ~= phase then return false end
  if phase == "workshop" then return b.ws == game.workshopNo end
  return b.stage == game.stage
end
-- a workshop inspection, once per workshop: as the car arrives, before any repair
function Score.workshop(p, late)
  if p.wsInspectedAt == game.workshopNo then return end
  p.wsInspectedAt = game.workshopNo
  if not late and #workshopSpots() > 0 and game.wsFirst ~= game.workshopNo and not Score.brought(p, "workshop") then   -- (Turbo Mode: first one in)
    game.wsFirst = game.workshopNo
    Score.turboAward(p, "first into a workshop")
  end
  local sc = Score.inspect(p, "Workshop " .. tostring(game.workshopNo))
  say(p.pid, string.format("Workshop inspection%s: damage %d -> %.1f/%s drivability (all your inspections are averaged at the end).",
    late and " (you didn't make it to a workshop)" or "", math.floor(p.damage or 0), sc, tostring(cfg.scoring.drivabilityMaxPoints or 20)))
end
-- at the end: the finale inspection (0 if there wasn't one), the average added to the points (once)
function Score.finishDrivability(p, note)
  if p.drivabilityDone then return end
  p.drivabilityDone = true
  local hasFinale = false
  for _, i in ipairs(p.inspections or {}) do if i.where == "Finale" then hasFinale = true end end
  if not hasFinale then Score.inspect(p, "Finale", 0, note or "didn't arrive") end
  p.drivability = Score.average(p)
  p.points = p.points + p.drivability
end
local function pts(n) n = tonumber(n) or 0; return string.format("%g pt%s", n, n == 1 and "" or "s") end

-- a repair done at the roadside (tow, respawn, an unstick that repaired the car): the workshop price x markup
local function roadsideRepair(p)
  return math.floor(repairQuote(p, true) * (tonumber(cfg.economy.roadsideMarkup) or 1.25) + 0.5)
end
-- kind = "tow" | "respawn": total, service fee, repair part
local function roadsideCost(p, kind)
  if (cfg.modes or {}).freeRepair then return 0, 0, 0 end   -- (Free Repair mode)
  local ec = cfg.economy
  local fee = kind == "tow" and (tonumber(ec.towFee) or 1000) or (tonumber(ec.respawnFee) or 500)
  local repair = roadsideRepair(p)
  return fee + repair, fee, repair
end
local function ptNote()   -- ", -2 pts" (tows and respawns cost points at the final standings)
  local n = (cfg.modes or {}).freeRepair and 0 or (tonumber(cfg.scoring.towPenaltyPoints) or 0)   -- (none in Free Repair)
  return n > 0 and (", -" .. pts(n)) or ""
end
local function costNote(fee, repair)   -- "-$1,250: repair $250 + fee $1,000" (with its minus sign)
  if (cfg.modes or {}).freeRepair then return "free - Free Repair mode" end
  if repair <= 0 then return "-" .. money(fee) end
  return string.format("-%s: repair %s + fee %s", money(fee + repair), money(repair), money(fee))
end
-- (which parts are free - looks only - is decided on the client: isFreeSlot in topgear.lua)
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
local function towDestination(p, here)   -- (here: this event's start, for a driver whose run hasn't started)
  local ph, n = game.phase, game.stage
  local idx
  if ph == "travel" or (here and (ph == "event" or ph == "countdown")) then idx = n
  elseif ph == "event" or ph == "countdown" then idx = n + 1 end
  local e = idx and game.events[idx]
  if not (e and v3(e.start)) then return nil end
  local start = v3(e.start)
  local face = Course.startFace(e)
  local dir = face and { x = face.x, y = face.y, z = 0 } or nil
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

-- course checks (one table: main.lua is near Lua's 200-local limit; declared further up, by yawFromQuat)
-- a checkpoint on top of the start (or of the checkpoint before it) is reached the moment the run starts - e.g. one
-- placed from a parked car instead of the one being driven. Returns why, or nil.
-- a checkpoint reached: within its own radius (cp.r - 5/10/20 m from the course builder), or for a line checkpoint
-- (cp.line = { ax, ay, bx, by }) the car's path since the last sample crossed the line
function Course.reachedCp(p, cp, r)
  if type(cp) == "table" and type(cp.line) == "table" and p.pos then
    local L = cp.line
    if not p.prevPos then return segDist(p.pos, { x = L.ax, y = L.ay, z = p.pos.z }, { x = L.bx, y = L.by, z = p.pos.z }) <= 2 end
    local function side(ax, ay, bx, by, px, py) return (bx - ax) * (py - ay) - (by - ay) * (px - ax) end
    local a, b, c, d = p.prevPos, p.pos, { x = L.ax, y = L.ay }, { x = L.bx, y = L.by }
    local d1, d2 = side(c.x, c.y, d.x, d.y, a.x, a.y), side(c.x, c.y, d.x, d.y, b.x, b.y)
    local d3, d4 = side(a.x, a.y, b.x, b.y, c.x, c.y), side(a.x, a.y, b.x, b.y, d.x, d.y)
    if ((d1 <= 0 and d2 >= 0) or (d1 >= 0 and d2 <= 0)) and ((d3 <= 0 and d4 >= 0) or (d3 >= 0 and d4 <= 0)) and (d1 ~= d2) then
      return true
    end
    return segDist(p.pos, { x = L.ax, y = L.ay, z = p.pos.z }, { x = L.bx, y = L.by, z = p.pos.z }) <= 1
  end
  return reached(p, cp, (type(cp) == "table" and tonumber(cp.r)) or r)
end
function Course.stacked(e, cps)
  cps = cps or e.checkpoints or {}
  local start, near = v3(e.start), 2 * (e.cpRadius or cfg.defaults.cpRadius or 12)
  for k, cp in ipairs(cps) do
    local c = v3(cp)
    if c and start and dist(c, start) < near then return string.format("checkpoint %d is on top of the start (%.0f m)", k, dist(c, start)), "start" end
    local prev = k > 1 and v3(cps[k - 1])
    if c and prev and dist(c, prev) < near then return string.format("checkpoints %d and %d are on top of each other (%.0f m)", k - 1, k, dist(c, prev)), "each" end
  end
  return nil
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
      elseif (e.type == "circuit" or e.type == "rpc") and #(e.checkpoints or {}) < 1 then
        errs[#errs + 1] = string.format("Event %d: a circuit needs checkpoints round the lap - /tg addcp %d", i, i)
      else
        local why, kind = Course.stacked(e)
        if why then   -- (0.9.13: say how to fix just that - moving the start keeps every checkpoint)
          errs[#errs + 1] = string.format("Event %d (%s): %s - %s", i, e.name, why, kind == "start"
            and string.format("move the start (/tg setstart %d, or Set start here: your checkpoints stay)", i)
            or string.format("/tg undocp %d takes the last one back, /tg clearcp %d all of them", i, i))
        end
      end
    end
  end
  if not v3((finale or {}).pos) then errs[#errs + 1] = "Finale: no finish point - /tg setfinale" end
  return errs
end

local function startGame(pid, force)
  if chosenClass and not activeClass() then chosenClass = nil end   -- (deleted meanwhile)
  if activeClass() and #classTrims(activeClass()) == 0 then
    say(pid, "Today's class (" .. chosenClass .. ") has no cars: " .. classSummary(activeClass()) ..
      ". /tg class show " .. chosenClass .. " - or /tg importprices if nothing's been imported yet.")
    return
  end
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
  if activeClass() then sayAll("Today's cars: " .. chosenClass .. " - " .. classSummary(activeClass()) .. ".") end
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
  playSound("start")
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
  game.dealerGo, game.dealerCount = nil, nil   -- (an admin's Next phase skips the ready countdown)
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
  end
  sayAll("The dealership is closed - parts and paint are closed until the next workshop. Today's cars:")
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
      if e.type == "trailer" and cfg.defaults.readyToGo == false then requestTrailer(p) end   -- (else at I'm ready)
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
          elseif Score.brought(p, "travel") then   -- (0.9.35: an admin's Bring to me - arrived, but no place, bonus or prize)
            p.leg.arrived = true
            p.arrivalRank = 99
            if e.type == "trailer" and cfg.defaults.readyToGo == false then requestTrailer(p) end
            sayAll(string.format("%s is at %s (brought by an admin - no arrival bonus or prize)", p.name, e.name))
          else
            p.leg.arrived = true
            game.arrivals = game.arrivals + 1
            p.arrivalRank = game.arrivals
            if e.type == "trailer" and cfg.defaults.readyToGo == false then requestTrailer(p) end   -- (else at I'm ready)
            if game.arrivals == 1 and not game.test then Score.turboAward(p, "first to arrive at " .. e.name) end
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
    if cfg.defaults.readyToGo ~= false and isSolo(e) then   -- a time trial: the turns begin by themselves
      sayAll(string.format("Everyone's at %s!", e.name))
      game.allHere = true
      beginCountdown()
      return
    elseif cfg.defaults.readyToGo ~= false then
      sayAll(string.format("Everyone's at %s! Press I'm ready - once everyone is, anyone can press GO.", e.name))
      bigAll("Everyone's here - I'm ready, then GO")
    else
      sayAll(string.format("Everyone's at %s! Line up - anyone can type /tg go to start the countdown.", e.name))
      bigAll("Everyone's here - /tg go to start")
    end
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
  r.startDamage, r.startFuel, r.startEnergy = p.damage or 0, p.fuel, p.energy
  r.endDamage, r.endFuel, r.endEnergy, r.sampleAfter = nil, nil, nil, nil
  r.startAir, r.startCrash, r.endAir, r.endCrash = p.airTotal or 0, p.crashTotal or 0, nil, nil
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
    playSound("finish", p)
  end
end

-- Star in a reasonably priced car: on their turn each driver gets a fresh copy of the same car on the start line,
-- spawned by their own game and allowed here; their own car stays parked, untouched (damage, problems, parts).
-- p.rpc = { vid, want, allowUntil, model, removing }. Positions come from the RPC while p.rpc is set.
local RPC = {}
-- Spectating: while a time trial driver is on track, everyone else's game points its camera at that car (BeamMP:
-- "entering" someone else's car = watching it, you can't drive it). The exact car is sent - an RPC driver has two.
RPC.watchOff = {}   -- player name -> true: /tg watch off (kept while the server runs, like /tg sounds off)
function RPC.watch(p, vid)
  if cfg.defaults.watchRunner == false or not (p.pid and vid) then return end
  local s = game.solo
  if s then s.watching = true end
  local msg = Util.JsonEncode({ sid = tostring(p.pid) .. "-" .. tostring(vid), name = p.name })
  for pid, name in pairs(MP.GetPlayers() or {}) do
    if pid ~= p.pid and not RPC.watchOff[name] then MP.TriggerClientEvent(pid, "tg_watch", msg) end
  end
end
function RPC.unwatch()   -- the run's over: everyone back to their own car
  local s = game.solo
  if not (s and s.watching) then return end
  s.watching = nil
  MP.TriggerClientEvent(-1, "tg_watch_end", "")
end
-- a time trial turn begins (its GO pressed, or straight away): the countdown - or for an RPC, the car first
function RPC.beginTurn(p, e)
  local s = game.solo
  s.waitGo = nil
  if e.type == "rpc" and p.rpc and p.rpc.vid then   -- (Ready -> GO: the car came with the turn; GO counts it down)
    s.countEnd, s.countTotal, s.lastCount = now() + cfg.defaults.countdown, nil, nil
    RPC.watch(p, p.rpc.vid)
  elseif e.type == "rpc" then   -- the countdown starts once their car is on the line
    s.countEnd = nil
    RPC.request(p, e)
    sayAll(string.format("%s's reasonably priced car is on its way to the start line.", p.name))
  else
    s.countEnd, s.countTotal, s.lastCount = now() + cfg.defaults.countdown, nil, nil
    RPC.watch(p, p.carVid)
  end
  pushAll()
end
-- I'm ready (defaults.readyToGo): at a race start everyone presses it, then GO; in a time trial, the driver whose turn
-- it is presses it, then GO (them or an admin)
function RPC.allReady()
  local names = {}
  for _, q in pairs(game.players) do
    if racing(q) and not (q.run and q.run.ready) then names[#names + 1] = q.name end
  end
  table.sort(names)
  return #names == 0, names
end
function RPC.wsAllReady()   -- the workshop: who hasn't pressed I'm ready yet
  local names = {}
  for _, q in pairs(game.players) do if racing(q) and not q.wsReady then names[#names + 1] = q.name end end
  table.sort(names)
  return #names == 0, names
end
function RPC.ready(p)
  local s, e = game.solo, curEvent()
  if game.phase == "workshop" then   -- done in the workshop: once everyone is, anyone's GO starts the next leg
    if p.wsReady then say(p.pid, "You're already ready."); return end
    p.wsReady = true
    local all, waiting = RPC.wsAllReady()
    sayAll(all and string.format("%s is done - everyone is: anyone can press GO for the next leg.", p.name)
      or string.format("%s is done in the workshop (waiting for %s).", p.name, table.concat(waiting, ", ")))
    pushAll()
    return
  end
  if game.phase == "event" and s and s.runner == p and s.waitGo then   -- a time trial: this driver's run
    if e and e.type == "rpc" and not (p.rpc and p.rpc.vid) then say(p.pid, "Wait for your reasonably priced car first."); return end
    if p.run.ready then say(p.pid, "You're ready - GO when you like."); return end
    p.run.ready = true
    if e and e.type == "trailer" then requestTrailer(p) end   -- (0.9.20: each trailer comes at its driver's I'm ready)
    sayAll(string.format("%s is ready - %s presses GO (or an admin).", p.name, p.name))
    pushAll()
    return
  end
  if game.phase ~= "travel" or not (e and racing(p)) then say(p.pid, "Nothing to be ready for right now."); return end
  if not p.leg.arrived then say(p.pid, "Get to the start first."); return end
  if isSolo(e) then say(p.pid, "It's one at a time: your turn comes - then you press I'm ready and GO."); return end
  if p.run.ready then say(p.pid, "You're already ready."); return end
  p.run.ready = true
  if e.type == "trailer" then requestTrailer(p) end   -- (0.9.20: one at a time - they landed on top of each other)
  local all, waiting = RPC.allReady()
  sayAll(all and string.format("%s is ready - everyone is: anyone can press GO.", p.name)
    or string.format("%s is ready (waiting for %s).", p.name, table.concat(waiting, ", ")))
  pushAll()
end
-- BeamNG's parked traffic cars (simple_traffic, "*_parked" configs) are props: no engine, controls or driver camera
function RPC.drivable(model, config)
  model, config = tostring(model or ""):lower(), tostring(config or ""):lower()
  return not (model == "simple_traffic" or config:find("parked", 1, true))
end
-- Not ready after all (0.9.20, Ryan): any I'm ready can be taken back until what it was waiting for has started -
-- the dealership's countdown (it stops), a race start's / the workshop's GO, a time trial driver's GO
function RPC.unready(p)
  local s, e = game.solo, curEvent()
  if game.phase == "dealer" then
    if not p.ready then say(p.pid, "You're not marked ready."); return end
    p.ready = false
    local stopped = game.dealerGo ~= nil
    game.dealerGo, game.dealerCount = nil, nil
    sayAll(string.format("%s isn't ready after all%s.", p.name, stopped and " - the countdown is stopped" or ""))
  elseif game.phase == "workshop" then
    if not p.wsReady then say(p.pid, "You're not marked ready."); return end
    p.wsReady = false
    sayAll(string.format("%s isn't done in the workshop after all.", p.name))
  elseif game.phase == "travel" and e and racing(p) and p.run.ready then
    p.run.ready = false
    sayAll(string.format("%s isn't ready after all.", p.name))
  elseif game.phase == "event" and s and s.runner == p and s.waitGo and p.run.ready then
    p.run.ready = false
    sayAll(string.format("%s isn't ready after all.", p.name))
  else
    say(p.pid, (p.run and p.run.ready) and "Too late - it's already started." or "You're not marked ready.")
    return
  end
  pushAll()
end
function RPC.car(e)   -- model, config name
  local tc = typeCfg("rpc")
  if e and e.rpcModel and RPC.drivable(e.rpcModel, e.rpcConfig) then return e.rpcModel, e.rpcConfig end
  return tc.model or "covet", tc.config
end
function RPC.label(e)
  local m, c = RPC.car(e)
  return c and (m .. " / " .. c) or m
end
function RPC.request(p, e)   -- a fresh RPC on the start line (the old one, if any, already removed)
  if not p.pid then return end
  local model, config = RPC.car(e)
  local look = Course.startLook(e)   -- (the RPC faces the way the start does)
  p.rpc = p.rpc or {}
  p.rpc.want, p.rpc.vid, p.rpc.model = true, nil, model
  p.rpc.allowUntil = now() + (tonumber(typeCfg("rpc").spawnTimeout) or 20)
  p.pos, p.prevPos = nil, nil
  MP.TriggerClientEvent(p.pid, "tg_rpc", Util.JsonEncode({ model = model,
    config = config and ("vehicles/" .. model .. "/" .. config .. ".pc") or nil, pos = e.start, look = look }))
end
function RPC.remove(p)   -- the turn is over: the RPC goes, the driver goes back to their own car
  local r = p.rpc
  if not r then return end
  p.rpc = nil
  if r.vid and p.pid then r.removing = true; MP.RemoveVehicle(p.pid, r.vid) end
  if p.pid then MP.TriggerClientEvent(p.pid, "tg_rpc_end", "") end
  p.pos, p.prevPos = nil, nil
end
function RPC.spawned(p, vid, model)   -- TG_onVehicleSpawn: is this the RPC we asked for?
  local r = p.rpc
  if not (r and r.want and not r.vid and model == r.model and now() < (r.allowUntil or 0)) then return false end
  r.vid, r.want = vid, false
  local s, run = game.solo, p.run
  if run.status == "staged" and s and s.runner == p and s.waitGo then   -- (Ready -> GO: the car comes with the turn)
    say(p.pid, "Here's your reasonably priced car - get in, start it, settle in, then press I'm ready and GO.")
  elseif run.status == "staged" and s and s.runner == p and not s.countEnd then
    s.countEnd, s.countTotal, s.lastCount = now() + cfg.defaults.countdown, nil, nil
    say(p.pid, "Here's your reasonably priced car - get ready!")
    RPC.watch(p, vid)
  elseif run.status == "running" then   -- a fresh car mid-run: a new lap from the line (watchers follow it)
    run.cp, run.lapStart, run.leftLine = 1, now(), false
    if s and s.runner == p then RPC.watch(p, vid) end
  end
  pushAll()
  return true
end
-- /tg respawn (or unstick) on your turn: a fresh car on the start line. The lap you were on counts as one of
-- your laps but has no time; on the last lap it ends your turn.
function RPC.fresh(p)
  local e = curEvent()
  local run = p.run
  if not (e and e.type == "rpc" and game.solo and game.solo.runner == p) then return false end
  if run.status == "running" then
    local laps = math.max(1, math.floor(tonumber(e.laps) or 3))
    if run.lap >= laps then
      sayAll(string.format("%s gave up the last lap.", p.name))
      RPC.endOnBest(p)
      return true   -- (tickSolo ends the turn)
    end
    sayAll(string.format("%s needs a fresh car - lap %d doesn't count.", p.name, run.lap))
    run.lap, run.cp, run.leftLine = run.lap + 1, 1, false
  elseif run.status ~= "staged" then return false end
  local vid = p.rpc and p.rpc.vid
  if vid and p.pid then p.rpc.removing = true; MP.RemoveVehicle(p.pid, vid) end
  RPC.request(p, e)
  return true
end
-- the turn is over: on to the next driver - but leave a finished driver in the RPC for a few seconds to stop
-- (it would vanish at full speed), then they're back in their own car
function RPC.endOnBest(p)   -- the turn ends early: the best timed lap stands (none = DNF)
  local run = p.run
  if run.bestLap then
    run.time = run.bestLap + (run.penalty or 0)
    endRun(p)
    sayAll(string.format("%s's best lap: %s", p.name, fmtTime(run.time)))
  else run.status = "dnf" end
end
function RPC.handOver(p, e)
  local s = game.solo
  if e.type == "rpc" and p.rpc and p.rpc.vid and p.run.status == "finished" then
    s.handBack = s.handBack or (now() + (tonumber(typeCfg("rpc").stopSeconds) or 3))
    if now() < s.handBack then return end
  elseif RPC.backToStart(p, e) then return end
  s.handBack = nil
  nextSoloRunner()
end
-- (0.9.20, Ryan: a driver whose run is over sat on the track while the next one drove - and was switched to watching)
-- a 5 s countdown on their screen, then their car - as it is, no repair - goes to a spot behind the start line.
-- Not for the RPC (their own car never left), a trailer event (the trailer is hitched), a tow, or the last run.
-- Returns true while counting down.
function RPC.backToStart(p, e)
  local s = game.solo
  local later = false
  for i = s.idx + 1, #s.order do if s.order[i].run.status == "waiting" and racing(s.order[i]) then later = true end end
  if e.type == "rpc" or e.type == "trailer" or p.run.status == "dsq" or not (later and p.pid and p.carVid and racing(p)) then
    s.backAt = nil
    return false
  end
  local secs = tonumber(cfg.defaults.backToStartSeconds) or 5
  if secs <= 0 then s.backAt = now() end
  if not s.backAt then s.backAt, s.backLast = now() + secs, nil end
  local left = s.backAt - now()
  if left > 0 then
    local sec = math.ceil(left)
    if sec ~= s.backLast then s.backLast = sec; MP.TriggerClientEvent(p.pid, "tg_msg", "Back to the start in " .. sec) end
    return true
  end
  s.backAt = nil
  local start = v3(e.start)
  if not start then return false end
  local face = Course.startFace(e)
  local fx, fy = face and face.x or 0, face and face.y or 1
  s.backSlot = (s.backSlot or 0) + 1
  local k = s.backSlot - 1
  local back = (tonumber(cfg.defaults.startRadius) or 20) + 15 + 8 * math.floor(k / 3)   -- clear of the cars waiting at the start
  local side = ((k % 3) - 1) * 4
  local pos = { x = start.x - fx * back + fy * side, y = start.y - fy * back - fx * side, z = (start.z or 0) + 0.5 }
  p.towPending = now()   -- (the move isn't a reset to fine)
  MP.TriggerClientEvent(p.pid, "tg_tow", Util.JsonEncode({ kind = "return", reset = false, pos = pos, dir = { x = fx, y = fy, z = 0 } }))
  say(p.pid, "Your car's been moved behind the start line - as it is, no repairs.")
  return false
end
function RPC.tickRunner(p, e)   -- the car didn't arrive in time
  local r = p.rpc
  if not (r and r.want and not r.vid and now() >= (r.allowUntil or 0)) then return end
  local why = "the reasonably priced car didn't appear (the server's MaxCars must be 2 or more)"
  if p.run.status == "staged" then
    p.run.status = "dns"
    sayAll(string.format("%s can't run: %s.", p.name, why))
  else
    say(p.pid, "Your fresh car didn't appear: " .. why .. ".")
    RPC.endOnBest(p)
  end
  log("rpc: " .. p.name .. ": " .. why)
end

beginCountdown = function()
  local e = curEvent()
  game.closeAt, game.trapRecord = nil, nil
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
    nextSoloRunner(true)   -- (this GO is the first driver's)
  else
    game.phase, game.countdownEnd, game.lastCount = "countdown", now() + cfg.defaults.countdown, nil
    sayAll(string.format("%s!%s Starting in %s seconds...", e.name, desc, tostring(cfg.defaults.countdown)))
  end
  pushAll()
end

-- go = true: the next driver starts right away (the event's own GO); otherwise, with defaults.soloGo, they wait
-- for GO - pressed by them or an admin (PLAYER_CMDS.go)
nextSoloRunner = function(go)
  local s = game.solo
  if not s then return false end
  RPC.unwatch()   -- (the last run's over)
  if s.runner and s.runner.rpc then RPC.remove(s.runner) end
  while true do
    s.idx = s.idx + 1
    local p = s.order[s.idx]
    if not p then s.runner = nil; pushAll(); return false end
    if p.run.status == "waiting" and racing(p) then
      s.runner, s.countEnd, s.countTotal, s.lastCount = p, nil, nil, nil
      p.run.status = "staged"
      local nxt = s.order[s.idx + 1]
      local e = curEvent()
      local readyGo = cfg.defaults.readyToGo ~= false
      if not readyGo and (go or cfg.defaults.soloGo == false) then
        sayAll(string.format("%s is up%s.", p.name, nxt and (" - " .. nxt.name .. " is next") or " - last run"))
        RPC.beginTurn(p, e)
      else
        s.waitGo = true
        if readyGo then
          sayAll(string.format("%s is up%s - %s presses I'm ready, then GO.", p.name, nxt and (" (" .. nxt.name .. " next)") or " (last run)", p.name))
          bigAll(p.name .. " is up - Ready, then GO")
          if e and e.type == "rpc" then
            RPC.request(p, e)
            sayAll(string.format("%s's reasonably priced car is on its way to the start line.", p.name))
          end
        else
          sayAll(string.format("%s is up%s - %s presses GO when ready.", p.name, nxt and (" (" .. nxt.name .. " next)") or " (last run)", p.name))
          bigAll(p.name .. " is up - GO when ready")
        end
        pushAll()
      end
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
  playSound("go")
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
  if (e.type ~= "circuit" and e.type ~= "rpc") or not v3(e.start) then return cps end
  local r = {}
  for i, c in ipairs(cps) do r[i] = c end
  r[#r + 1] = e.start   -- the start point is the start/finish line
  return r
end

local function tickRoute(p, e)
  local cps = routePoints(e)
  local lapped = e.type == "circuit" or e.type == "rpc"
  if lapped then
    local line = v3(e.start)
    if line and p.pos and dist(p.pos, line) > math.max(40, (e.cpRadius or cfg.defaults.cpRadius) * 3) then p.run.leftLine = true end
    if p.run.cp >= #cps and not p.run.leftLine then return end
  end
  local cp = cps[p.run.cp]
  if not cp or not Course.reachedCp(p, cp, e.cpRadius or cfg.defaults.cpRadius) then return end
  if e.type == "rpc" then   -- (in the server console: where each one was reached, to check a course in game)
    log(string.format("rpc: %s lap %d, point %d/%d reached %.0f m from it at (%.0f, %.0f)", p.name, p.run.lap or 1, p.run.cp, #cps,
      dist(p.pos, v3(cp)), p.pos.x, p.pos.y))
  end
  local elapsed = now() - p.run.startT
  if lapped and p.run.cp >= #cps then
    local laps = math.max(1, math.floor(tonumber(e.laps) or 3))
    local lapTime = now() - p.run.lapStart
    p.run.bestLap = math.min(p.run.bestLap or lapTime, lapTime)
    p.run.lapsTimed = (p.run.lapsTimed or 0) + 1
    if e.type == "rpc" then sayAll(string.format("%s: lap %d - %s", p.name, p.run.lap, fmtTime(lapTime))) end
    if p.run.lap < laps then
      say(p.pid, string.format("Lap %d/%d done: %s. Lap %d!", p.run.lap, laps, fmtTime(lapTime), p.run.lap + 1))
      p.run.lap, p.run.cp, p.run.lapStart, p.run.leftLine = p.run.lap + 1, 1, now(), false
      pushState(p)
      return
    end
  end
  if p.run.cp >= #cps then
    p.run.time = elapsed + (p.run.penalty or 0)
    if e.type == "rpc" then p.run.time = p.run.bestLap + (p.run.penalty or 0) end   -- the best lap counts
    if e.type == "trailer" then
      if p.eventVeh and p.eventVeh.prebuilt then
        local tc = typeCfg("trailer")
        local raw = p.eventVeh.trailer and MP.GetPositionRaw(p.pid, p.eventVeh.trailer)
        local tpos = type(raw) == "table" and v3(raw.pos)
        local withYou = tpos and p.pos and dist(tpos, p.pos) <= (tc.hitchRadius or 15)
        local frac = withYou and (p.cargoFrac or 1) or 0
        p.run.cargoFrac = frac
        p.run.intact = p.eventVeh.intact or nil   -- (no load: the share is how much of the trailer is intact)
        p.run.cargoLeft, p.run.cargoTotal = frac * (tc.cargoCount or 5), (tc.cargoCount or 5)
      else
        p.run.cargoLeft, p.run.cargoTotal = countCargo(p)
      end
    end
    endRun(p)
    local cargoTxt = ""
    if e.type == "trailer" then
      cargoTxt = p.run.cargoFrac and string.format(p.run.intact and " with the trailer %d%% intact" or " with %d%% of the load",
        math.floor(p.run.cargoFrac * 100 + 0.5))
                 or string.format(" with %d/%d cargo", p.run.cargoLeft, p.run.cargoTotal)
    end
    if e.type == "rpc" then sayAll(string.format("%s's best lap: %s", p.name, fmtTime(p.run.time)))
    else sayAll(string.format("%s crosses the line! %s%s", p.name, fmtTime(p.run.time), cargoTxt)) end
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
      local cd = Course.activeDir[p.pid]   -- the way the car points, from its own game (0.9.19)
      if cd and cd.vid == p.carVid and tonumber(bay.dx) and tonumber(bay.dy) then
        local dot = math.abs((cd.x * bay.dx + cd.y * bay.dy) / math.sqrt((cd.x * cd.x + cd.y * cd.y) * (bay.dx * bay.dx + bay.dy * bay.dy)))
        ang = math.deg(math.acos(math.min(1, dot)))   -- nose-in or reversed in both count as straight
      elseif p.yaw and bay.yaw then
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
        playSound("parked", p)   -- (the last bay ends the run: the finish clip plays instead)
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
    if run.trapMax > (game.trapRecord or 0) then game.trapRecord = run.trapMax; playSound("trapRecord", p) end
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
    elseif e.type == "rpc" and r.bestLap then RPC.endOnBest(p)
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
    if not racing(p) then p.run.status = "dnf"; s.waitGo = nil; nextSoloRunner(); return end
    if e.type == "rpc" and s.waitGo then   -- (waiting for Ready / GO - but the car has to turn up)
      RPC.tickRunner(p, e)
      if p.run.status ~= "staged" then s.waitGo = nil; nextSoloRunner() end
      return
    end
    if s.waitGo then return end   -- (waiting for their GO)
    if e.type == "rpc" then
      RPC.tickRunner(p, e)
      if p.run.status ~= "staged" then nextSoloRunner(); return end
      if not s.countEnd then return end   -- (still waiting for the car)
    end
    local left = s.countEnd - now()
    local sec = math.ceil(left)
    if sec > 0 and sec ~= s.lastCount then s.lastCount = sec; bigAll(p.name .. ": " .. sec) end
    falseStartCheck(p, e)
    if left <= 0 then startRun(p); bigAll(p.name .. ": GO!"); playSound("go"); pushAll() end
  elseif st == "running" then
    if e.type == "rpc" then RPC.tickRunner(p, e) end
    if racing(p) and p.pos and p.run.status == "running" then tickRun(p, e) end
    if p.run.status == "running" and now() - p.run.startT > (e.timeLimit or cfg.defaults.eventTimeLimit) then
      settleUnfinished(p, e)
      sayAll(p.name .. " is out of time.")
    end
    if p.run.status ~= "running" then RPC.handOver(p, e) end
  else
    RPC.handOver(p, e)   -- finished (an RPC driver stops first), or towed (DSQ) / lost before or while running
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
    -- least ENERGY used wins (tanks + batteries, in MJ), so petrol, diesel and electric cars compare fairly;
    -- shown as litres for fuel cars, kWh for electric ones. Older clients that only report litres: ~34.2 MJ/L.
    local endE, endFuel = r.endEnergy or p.energy, r.endFuel or p.fuel
    local litres = (r.startFuel and endFuel) and math.max(0, r.startFuel - endFuel) or nil
    local mj
    if r.startEnergy and endE then mj = math.max(0, r.startEnergy - endE) / 1e6
    elseif litres then mj = litres * 34.2 end
    if mj then
      r.score = mj + t * 1e-6   -- time only breaks exact ties
      local amount = (litres and litres > 0) and string.format("%.2f L", litres) or string.format("%.2f kWh", mj / 3.6)
      r.perf = string.format("%s (%.1f MJ) in %s", amount, mj, fmtTime(t))
      r.short = amount
    else
      r.score, r.perf, r.short = 1e6 + t, fmtTime(t) .. " (no fuel or energy reading)", fmtTime(t)
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
    local load = r.cargoFrac and string.format(r.intact and "trailer %d%% intact" or "%d%% of the load", pct)
                 or string.format("%d/%d cargo", math.floor(r.cargoLeft or 0), math.floor(r.cargoTotal or 0))
    r.perf = string.format("%s, %s: load %.1f + speed %.1f = %.1f pts", fmtTime(t), load, loadPts, speedPts, pts)
    r.short = string.format("%.1f pts (%d%%, %s)", pts, pct, fmtTime(t))
  elseif e.type == "rpc" then   -- the best single lap
    r.score = t
    r.perf = string.format("best lap %s (%d lap%s timed)%s", fmtTime(t), r.lapsTimed or 1, (r.lapsTimed or 1) == 1 and "" or "s",
      (r.penalty or 0) > 0 and string.format(" incl. +%ss jump start", tostring(r.penalty)) or "")
    r.short = fmtTime(t)
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
    if p.rpc then RPC.remove(p) end
  end
  RPC.unwatch()
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
  -- (0.9.35) what these results hand out, so /tg rerunevent can take it back: cash, points, wins, Turbo prizes and the
  -- head starts / penalty cards / tune the event used up
  local undo = { stage = game.stage, workshopNo = game.workshopNo or 0, players = {} }
  for _, p in pairs(game.players) do
    local ef = p.effects or {}
    undo.players[p.login or p.name] = { prize = 0, points = 0, win = 0, held = #(p.glovebox or {}),
      effects = { headstart = ef.headstart, penalty = ef.penalty, tune = ef.tune } }
  end
  if not game.test then game.rerun = undo end
  Score.turboTimes(ranked, e)   -- (Turbo Mode: head starts and penalty cards)
  for _, p in ipairs(ranked) do finalizeScore(p, e, ctx) end
  table.sort(ranked, function(a, b) return a.run.score < b.run.score end)
  sayAll("===== RESULTS: " .. e.name .. " =====")
  for i, p in ipairs(ranked) do
    local prize = cfg.economy.prizes[i] or 0
    local pts = cfg.scoring.placementPoints[i] or 0
    p.cash, p.points = p.cash + prize, p.points + pts
    local u = undo.players[p.login or p.name]
    if u then u.prize, u.points, u.win = prize, pts, i == 1 and 1 or 0 end
    if i == 1 then p.wins = p.wins + 1; playSound("win", p); playSound("winOthers", p) end
    p.results[game.stage] = { place = i, perf = p.run.perf, short = p.run.short, prize = prize, points = pts }
    sayAll(string.format("%s  %s - %s  (+%s, +%s pts)", ordinal(i), p.name, p.run.perf, money(prize), tostring(pts)))
  end
  for _, p in ipairs(others) do
    local st = STATUS_LABEL[p.run.status] or "DNF"
    if p.run.status == "dsq" then st = "DSQ (" .. (p.run.dsqReason or "towed") .. ")" end
    p.results[game.stage] = { perf = st, prize = 0, points = 0 }
    sayAll(string.format("--   %s - %s", p.name, st))
    if p.run.status ~= "dsq" then playSound("out", p) end   -- towed/respawned drivers heard it at the time
  end
  if not game.test then Score.turboEventPrizes(ranked, others) end   -- (Turbo Mode: cleanest car, last place, air, crash)
  for _, p in pairs(game.players) do   -- (the prizes these results put in a glovebox)
    local u = undo.players[p.login or p.name]
    if u then
      u.won = {}
      for k = u.held + 1, #(p.glovebox or {}) do u.won[#u.won + 1] = p.glovebox[k] end
    end
  end
  for _, p in pairs(game.players) do if p.effects then p.effects.tune, p.effects.tuneNow = nil, nil end end   -- (a tune lasts one event)
  cleanupEventVehicles()   -- (no free repair after a fragile delivery since 0.9.12: the dents are yours to pay for)
  game.solo, game.closeAt = nil, nil
  if game.test and game.testFinish then return game.testFinish() end   -- (a test event: the course builder's Test event)
  local n = game.stage
  local every = tonumber(cfg.workshopEvery) or 2
  if every > 0 and n % every == 0 and n < #game.events then beginWorkshop()
  elseif n >= #game.events then beginFinale()
  else beginTravel(n + 1) end
end

beginWorkshop = function()
  game.phase, game.workshopEnd, game.warned = "workshop", now() + cfg.workshop.minutes * 60, false
  game.workshopNo = (game.workshopNo or 0) + 1
  for _, p in pairs(game.players) do
    p.wsLabour, p.wsSpent, p.wsCharged, p.wsReady = false, 0, p.partsValue, nil
    if p.effects and (p.effects.horn or p.effects.frbrake) then   -- (Turbo Mode sabotage lasts until a workshop)
      p.effects.horn, p.effects.frbrake = nil, nil
      say(p.pid, "The workshop has sorted the sabotage on your car (the horn and the brakes).")
    end
  end
  if #workshopSpots() > 0 then
    sayAll(string.format("WORKSHOP open for %s minutes: drive to any workshop (the arrows show the nearest). " ..
      "Repairs, problem fixes, parts, paint and tuning work while you're parked there.", tostring(cfg.workshop.minutes)))
  end
  for _, p in pairs(game.players) do p.inShop = false end
  if #workshopSpots() == 0 then   -- workshops anywhere: everyone's in one now
    for _, p in pairs(game.players) do Score.workshop(p); revealFaults(p) end
  end
  sayAll(string.format("WORKSHOP open for %s minutes. /tg quote for a repair price, /tg repair to fix your car. " ..
    "The parts menu is unlocked: parts are charged as you fit them (plus %s labour once). Paint, cosmetics and tuning are free.",
    tostring(cfg.workshop.minutes), money(cfg.workshop.laborFee)))
  bigAll("Workshop open")
  playSound("workshop")
  pushAll()
  for _, p in pairs(game.players) do if p.pid then MP.TriggerClientEvent(p.pid, "tg_menu", "open") end end
end

endWorkshop = function()
  sayAll("The workshop is closed.")
  for _, p in pairs(game.players) do Score.workshop(p, true) end   -- no dodging an inspection by staying away
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
          if inside then Score.workshop(p); revealFaults(p) end
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
            local sc = Score.inspect(p, "Finale", p.finaleRebuilt and 0 or nil, p.finaleRebuilt and "respawned on the final leg" or nil)
            Score.finishDrivability(p)
            local nf = #(p.faults or {})
            local fpen = faultsOn() and nf * (cfg.faults.inspectionPenaltyPoints or 0) or 0
            p.faultsRevealed = true   -- the inspection finds them all
            local max = tostring(s.drivabilityMaxPoints)
            showFinish(p, cfg.finale.name, string.format("Drivability %.1f/%s", p.drivability, max))
            sayAll(string.format("%s made it to %s! Inspection: damage %d -> %.1f/%s. Drivability (average of %d inspections): %.1f/%s%s",
              p.name, cfg.finale.name, math.floor(p.damage or 0), sc, max, #p.inspections, p.drivability, max,
              fpen > 0 and string.format(". %d problem%s left unfixed (%s): -%s at the results", nf, nf == 1 and "" or "s",
                table.concat(faultNames(p), ", "), pts(fpen)) or ""))
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
      condition = CONDITION.level(p), conditionSaving = p.conditionSaving or 0, faultFixes = sp.faultFixes or 0, faultsLeft = faultNames(p),
      drivability = p.drivability or 0, eventPoints = eventPts, penalty = p.penaltyPoints or 0,
      inspections = (function() local o = {} for _, i in ipairs(p.inspections or {}) do o[#o + 1] = i.score end return o end)(),
      awards = p.awardPoints or 0,
      points = p.points, wins = p.wins, cash = p.cash,
    }
  end
  return s
end

showResults = function()
  game.phase = "results"
  local list = {}
  local sc = cfg.scoring
  for _, p in pairs(game.players) do
    Score.finishDrivability(p, p.finaleTowed and "towed" or (p.finaleRebuilt and "respawned on the final leg") or "didn't arrive")
    local parts = {}
    local function add(n, text) if n > 0 then parts[#parts + 1] = { n = n, text = text } end end
    local nReset, nHelp, nFault = p.recoveries or 0, (p.tows or 0) + (p.respawns or 0), #(p.faults or {})
    if (cfg.modes or {}).freeRepair then nHelp = 0 end   -- (Free Repair mode: tows and respawns cost no points - Ryan)
    nHelp = math.max(0, nHelp - (p.pardons or 0))        -- (Turbo Mode's Get out of jail)
    add(nReset * (sc.recoveryPenaltyPoints or 0), string.format("%d illegal reset%s", nReset, nReset == 1 and "" or "s"))
    add(nHelp * (sc.towPenaltyPoints or 0), string.format("%d tow%s/respawn%s", nHelp, nHelp == 1 and "" or "s", nHelp == 1 and "" or "s"))
    if faultsOn() then
      add(nFault * (cfg.faults.inspectionPenaltyPoints or 0), string.format("%d problem%s left unfixed", nFault, nFault == 1 and "" or "s"))
    end
    if p.cash < 0 then
      add(math.ceil(-p.cash / (sc.debtStep or 500)) * (sc.debtPenaltyPoints or 1), money(-p.cash) .. " in debt")
    end
    local pen, why = 0, {}
    for _, x in ipairs(parts) do pen = pen + x.n; why[#why + 1] = string.format("%s (-%g)", x.text, x.n) end
    p.penaltyPoints, p.penaltyParts = pen, parts
    if pen > 0 then
      p.points = p.points - pen
      sayAll(string.format("%s loses %s: %s.", p.name, pts(pen), table.concat(why, ", ")))
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
    local taken = CONDITION.level(p)
    sayAll(string.format("%s: repairs %s, upgrades %s, tows %d + respawns %d (%s), illegal resets %d (%s)%s", p.name, money(sp.repairs or 0),
      money(sp.upgrades or 0), p.tows or 0, p.respawns or 0, money(sp.towCost or 0), p.recoveries or 0, money(sp.fines or 0),
      taken > 0 and string.format(", bought as %s (%s off), %d problem%s fixed (-%s)", CONDITION.name(taken), money(p.conditionSaving or 0),
        p.faultsFixed or 0, (p.faultsFixed or 0) == 1 and "" or "s", money(sp.faultFixes or 0)) or ""))
  end
  if list[1] then
    bigAll(list[1].name .. " wins the Top Gear Challenge!")
    playSound("champion", list[1])
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

-- the dealership: once everyone is ready, a short countdown, then it closes and leg 1 starts. Anyone not ready any more
-- (returned their car) or a newcomer stops it.
local function tickDealer()
  if not game.dealerGo then return end
  for _, q in pairs(game.players) do
    if q.pid and not q.ready then
      game.dealerGo, game.dealerCount = nil, nil
      sayAll(q.name .. " isn't ready any more - the countdown is off.")
      pushAll()
      return
    end
  end
  local left = game.dealerGo - now()
  local sec = math.ceil(left)
  if sec > 0 and sec ~= game.dealerCount then game.dealerCount = sec; bigAll("Starting in " .. sec) end
  if left <= 0 then game.dealerGo, game.dealerCount = nil, nil; lockDealer() end
end

local phaseTick = { travel = tickTravel, countdown = tickCountdown, event = tickEvent,
                    workshop = tickWorkshop, finale = tickFinale, dealer = tickDealer }

function TG_onTick()
  for dpid, t0 in pairs(pendingDiag) do
    if now() - t0 > 5 then
      pendingDiag[dpid] = nil
      say(dpid, "No reply from the Top Gear client mod after 5 s - it is NOT running on your game.")
      say(dpid, "Check Resources/Client/topgear.zip is on the server, then fully restart BeamNG and reconnect.")
    end
  end
  if pendingImport and now() - pendingImport.started > (pendingImport.all and 120 or 15) then finishImport() end
  local okS, errS = pcall(Save.tick)
  if not okS then log("save error: " .. tostring(errS)) end
  if game.phase == "idle" or game.phase == "paused" then return end
  Save.tickRestore()
  local okQ, errQ = pcall(CONDITION.quirkTick)
  if not okQ then log("quirks error: " .. tostring(errQ)) end
  for _, p in pairs(game.players) do
    if racing(p) then
      local rpcVid = p.rpc and p.rpc.vid   -- on a reasonably priced car turn, the run follows the RPC
      local raw = (not p.rpc or rpcVid) and MP.GetPositionRaw(p.pid, rpcVid or p.carVid)
      local pos = type(raw) == "table" and v3(raw.pos)
      if pos then
        p.prevPos = p.pos or pos
        p.pos = pos
        local vel = v3(raw.vel)
        p.speed = vel and math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z) or 0
        p.yaw = yawFromQuat(raw.rot) or p.yaw
        if not rpcVid then   -- (your own car's place - not the RPC's)
          p.lastPos = { x = pos.x, y = pos.y, z = pos.z }   -- (saved: where the car comes back after a crash)
          local dx, dy = pos.x - p.prevPos.x, pos.y - p.prevPos.y
          if dx * dx + dy * dy > 0.25 then p.lastDir = { x = dx, y = dy, z = 0 } end
        end
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
-- Persistent game state: the running challenge is saved to session.json, so a server crash or restart
-- doesn't lose it. After a restart it comes back paused; an admin resumes it (/tg resume) when people are
-- back, or discards it. Cars come back as they were (upgrades, setup faults) - after a crash or when a
-- player rejoins - and the owner pays their car's repair price (no tow fee, no points).
---------------------------------------------------------------------------
Save.PATH = PLUGIN_DIR .. "session.json"
Save.EVERY = 5   -- seconds between saves while a challenge runs (and at every phase change)
Save.TIMERS = { "closeAt", "workshopEnd", "countdownEnd", "phaseStart", "eventStart" }
-- per-player runtime state that means nothing after a restart (game ids, positions, short time windows)
Save.TRANSIENT = { "quirkAt", "pid", "carVid", "pos", "prevPos", "speed", "eventVeh", "spawnAllow", "rpc", "towPending", "repairPending",
  "respawnPending", "unstickPending", "faultEditUntil", "lastEditAt", "outsideEditAt", "putBackAt", "swapAt", "lastUnstick",
  "lastCrashSound", "airSeen", "pendingCharge", "restoring", "restoreAt", "restoreTries" }

-- JSON can't hold every Lua table (number keys, holes): arrays stay arrays, other number keys become "#n"
function Save.pack(v, path)
  local tv = type(v)
  if tv == "number" then if v ~= v or v == math.huge or v == -math.huge then return nil end return v end
  if tv ~= "table" then if tv == "string" or tv == "boolean" then return v end return nil end
  path = path or {}
  if path[v] then return nil end   -- (cycles aren't saved)
  path[v] = true
  local n, count = #v, 0
  for _ in pairs(v) do count = count + 1 end
  local out = {}
  if n > 0 and n == count then
    for i = 1, n do out[i] = Save.pack(v[i], path) end
  else
    for k, x in pairs(v) do
      local key = (type(k) == "number" and ("#" .. tostring(k))) or (type(k) == "string" and k) or nil
      if key then out[key] = Save.pack(x, path) end
    end
  end
  path[v] = nil
  return out
end
function Save.unpack(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do
    local nk = type(k) == "string" and k:match("^#(%-?[%d%.]+)$")
    out[nk and tonumber(nk) or k] = Save.unpack(x)
  end
  return out
end

function Save.snapshot()
  local g = {}
  for k, v in pairs(game) do if k ~= "solo" and k ~= "players" then g[k] = v end end   -- (an event is re-run anyway)
  g.timers = {}
  for _, k in ipairs(Save.TIMERS) do
    if tonumber(game[k]) then g.timers[k] = game[k] - now(); g[k] = nil end
  end
  g.players = {}
  for name, p in pairs(game.players) do
    local c = {}
    for k, v in pairs(p) do c[k] = v end
    for _, k in ipairs(Save.TRANSIENT) do c[k] = nil end
    g.players[name] = c
  end
  g.chosenClass = chosenClass
  if game.phase == "paused" then g.phase, g.resumePhase = game.resumePhase, nil end
  return { version = SERVER_VERSION, game = Save.pack(g) }
end

function Save.write()
  Save.lastAt, Save.lastPhase, Save.lastStage = now(), game.phase, game.stage
  local okE, s = pcall(Util.JsonEncode, game.phase == "idle" and { game = { phase = "idle" } } or Save.snapshot())
  if not okE then log("couldn't save the challenge: " .. tostring(s)); return false end
  -- write a temporary file, then swap it in, so a crash mid-write can't leave a broken save
  local tmp = Save.PATH .. ".tmp"
  if writeFile(tmp, s) then
    local okR, res = pcall(function() return FS.Rename(tmp, Save.PATH) end)
    if okR and res ~= false then return true end
  end
  return writeFile(Save.PATH, s)
end
function Save.clear() Save.write() end   -- (idle: nothing to resume)

-- called every tick: save at phase changes and every few seconds while a challenge runs
function Save.tick()
  if game.test then return end   -- (a test event isn't a challenge: nothing to resume)
  if game.phase == "idle" then
    if Save.lastPhase and Save.lastPhase ~= "idle" then Save.write() end
    return
  end
  local periodic = game.phase ~= "paused" and game.phase ~= "results"   -- (nothing changes while paused or after the end)
  if game.phase ~= Save.lastPhase or game.stage ~= Save.lastStage or not Save.lastAt or (periodic and now() - Save.lastAt >= Save.EVERY) then
    Save.write()
  end
end

-- on plugin load: a challenge in progress comes back paused (results come back as they were)
function Save.load()
  local s = readFile(Save.PATH)
  if not s or s == "" then return end
  local ok, t = pcall(Util.JsonDecode, s)
  if not ok or type(t) ~= "table" or type(t.game) ~= "table" then log("session.json is unreadable - not restored"); return end
  local g = Save.unpack(t.game)
  if g.phase == "idle" or type(g.players) ~= "table" or not next(g.players) then return end
  for _, p in pairs(g.players) do
    p.run = p.run or newRun(); p.leg = p.leg or { via = 1, arrived = false }
    p.results, p.faults, p.spent = p.results or {}, p.faults or {}, p.spent or {}
    -- (0.9.13: missing bumpers became part of accident damage, the weak starter part of the ignition problems)
    local MERGED, have, list = { bumpers = "body", starter = "ignition" }, {}, {}
    for _, id in ipairs(p.faults) do
      local into = MERGED[id] or id
      if not have[into] then have[into] = true; list[#list + 1] = into end
    end
    p.faults = list
  end
  if g.chosenClass and Class.def(g.chosenClass) then chosenClass = g.chosenClass end
  g.chosenClass = nil
  local timers = g.timers or {}
  g.timers = nil
  game = g
  game.savedTimers = timers
  if game.phase == "results" then
    log("restored the last challenge's results")
  else
    game.resumePhase, game.phase = game.phase, "paused"
    log(string.format("restored a challenge in progress (%s, stage %s, %d drivers) - paused until an admin types /tg resume",
      tostring(game.resumePhase), tostring(game.stage), (function() local n = 0 for _ in pairs(game.players) do n = n + 1 end return n end)()))
  end
  Save.lastPhase, Save.lastStage, Save.lastAt = game.phase, game.stage, now()
end

-- the car comes back: ask the client to spawn it (stock trim), then put the upgrades back and place it.
-- charge = true: the owner pays the car's repair price (its damage when it was lost).
function Save.restoreCar(p, charge, pos, dir)
  if not (p.pid and p.carModel) or p.carVid then return end
  local cost = (charge and not (cfg.modes or {}).freeRepair) and repairQuote(p, true) or 0
  p.restoring = { pos = pos, dir = dir, cost = cost }
  p.restoreAt, p.restoreTries = now() + 3, 0   -- (sent from the tick: the client mod may still be loading)
end
function Save.tickRestore()
  for _, p in pairs(game.players) do
    if p.restoring and p.pid and not p.carVid and p.restoreAt and now() >= p.restoreAt then
      p.restoreTries = (p.restoreTries or 0) + 1
      if p.restoreTries > 6 then
        p.restoreAt = nil
        say(p.pid, "Couldn't bring your car back automatically - spawn it from the vehicle menu (/tg respawn).")
      else
        p.restoreAt = now() + 10
        MP.TriggerClientEvent(p.pid, "tg_respawn", Util.JsonEncode({ spawn = true, model = p.carModel,
          config = p.carConfig and ("vehicles/" .. p.carModel .. "/" .. p.carConfig .. ".pc") or nil }))
      end
    end
  end
end
-- TG_onVehicleSpawn: the car we asked for has appeared
function Save.carBack(p, vid)
  local r = p.restoring or {}
  p.restoring, p.restoreAt, p.restoreTries = nil, nil, nil
  p.carVid, p.pos, p.prevPos = vid, nil, nil
  p.towPending, p.faultEditUntil = now(), now() + 15   -- its rebuild and the upgrade restore aren't the driver's
  if (r.cost or 0) > 0 then
    p.cash = p.cash - r.cost
    spend(p, "repairs", r.cost)
  end
  p.damage = 0
  pushState(p)
  MP.TriggerClientEvent(p.pid, "tg_tow", Util.JsonEncode({ kind = "restore", reset = false, pos = r.pos, dir = r.dir,
    config = p.lastVcf }))
  if CONDITION.level(p) > 0 then sendFaults(p) end   -- (problems and mileage)
  say(p.pid, string.format("Your %s is back%s.", p.carName or "car",
    (r.cost or 0) > 0 and (" - its repairs cost " .. money(r.cost) .. " (no tow fee, no points lost)") or ""))
end
-- where a car comes back: where it was last seen, or the event's start line when an event is re-run
function Save.placeFor(p, rerun)
  if rerun then
    local pos, dir = towDestination(p)
    if pos then return pos, dir end
  end
  local lp = p.lastPos
  if lp and tonumber(lp.x) then return { x = lp.x, y = lp.y, z = lp.z + 0.5 }, p.lastDir end
  return nil
end

---------------------------------------------------------------------------
-- BeamMP events
---------------------------------------------------------------------------
function TG_onPlayerJoin(pid)
  local name = MP.GetPlayerName(pid)
  local p = game.players[name]
  if p and game.phase ~= "idle" then
    p.pid, p.carVid, p.pos, p.prevPos = pid, nil, nil, nil
    if game.phase == "paused" then
      say(pid, "Welcome back - the challenge was saved when the server stopped. Waiting for an admin to /tg resume.")
      MP.TriggerClientEvent(pid, "tg_menu", "open")   -- (admins see Resume / Discard there)
    elseif game.phase == "dealer" then
      say(pid, "Welcome back - the dealership is still open.")
    elseif game.phase == "results" or not p.carModel then
      say(pid, "Welcome back " .. name .. ".")
    else   -- the car comes back where it was, with its upgrades; the driver pays its repairs (no tow fee, no points)
      say(pid, string.format("Welcome back %s - your %s is on its way back.", name, p.carName or "car"))
      local pos, dir = Save.placeFor(p, false)
      Save.restoreCar(p, true, pos, dir)
    end
    pushState(p)
    if game.phase == "paused" then
      for _, q in pairs(game.players) do
        if q.pid and isAdmin(MP.GetPlayerName(q.pid)) then say(q.pid, name .. " is back. /tg resume when everyone's here.") end
      end
    end
  elseif game.phase == "dealer" then
    say(pid, "A Top Gear Challenge is about to start - type /tg join to take part.")
  elseif game.phase ~= "idle" then
    say(pid, "A Top Gear Challenge is in progress - you're spectating.")
  end
end

function TG_onPlayerDisconnect(pid)
  Class.sentDealer[pid] = nil
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
  if p and p.rpc and RPC.spawned(p, vid, (parseVehicle(data))) then return 0 end   -- the reasonably priced car
  -- trailer + cargo for a trailer event (requested by the server moments ago)
  if p and p.spawnAllow and now() < p.spawnAllow.untilT and p.eventVeh then
    local m = parseVehicle(data)
    local a, ev = p.spawnAllow, p.eventVeh
    if m == a.trailer and not ev.trailer then ev.trailer = vid; return 0 end
    if m == a.cargo and #ev.cargo < a.count then ev.cargo[#ev.cargo + 1] = vid; return 0 end
  end
  if cfg.debugSpawns then log("spawn " .. name .. " vid " .. tostring(vid) .. ": " .. tostring(data):sub(1, 400)) end
  if p and p.restoring and not p.carVid and parseVehicle(data) == p.carModel then   -- the car we brought back
    Save.carBack(p, vid)
    return 0
  end
  if game.phase == "paused" then
    say(pid, "The challenge is paused until an admin types /tg resume - your car comes back then.")
    return 1
  end
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
    local cond = CONDITION.level(p)
    local acc = CONDITION.accel(model, config)
    local price = car and CONDITION.price(cond, car.price, acc)
    if car and price > playerBudget(p) then
      local need = CONDITION.needed(p, car.price, acc)
      say(pid, string.format("The %s (%s as %s) is over your %s budget%s.", car.name, money(price), CONDITION.name(cond), money(playerBudget(p)),
        need and string.format(" - as a %s it's %s (/tg condition %s)", CONDITION.name(need), money(CONDITION.price(need, car.price, acc)), CONDITION.name(need):lower())
          or (", even as a " .. CONDITION.name(math.min(cfg.faults.maxPerCar or 4, 4)))))
      return 1
    end
    if not car then
      say(pid, string.format("The dealership can't sell you that (%s / %s): %s. /tg dealer for the list.",
        tostring(model), tostring(config), tostring(why)))
      log(string.format("rejected spawn: model=%s config=%s", tostring(model), tostring(config)))
      return 1
    end
    if price > p.cash then
      say(pid, string.format("The %s costs %s - you have %s.", car.name, money(price), money(p.cash)))
      return 1
    end
    p.cash = p.cash - price
    setCar(p, vid, model, config, car)
    p.lastVcf = select(3, parseVehicle(data))
    sayAll(string.format("%s bought %s for %s%s (%s left).", p.name, withArticle(car.name), money(price),
      cond > 0 and string.format(" - a %s, %s off", CONDITION.name(cond), money(p.conditionSaving)) or "", money(p.cash)))
    if faultsTaken(p) > 0 then redrawFaults(p); sendFaults(p) end
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
  if game.phase == "idle" or game.phase == "results" or game.phase == "paused" then return 0 end
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
    local swapPrice = CONDITION.price(CONDITION.level(p), car.price, CONDITION.accel(model, config))   -- (same condition as the car it replaces)
    local diff = swapPrice - (p.carPrice or 0)
    if diff > p.cash then say(pid, "You can't afford that - " .. money(swapPrice) .. "."); return 1 end
    p.cash = p.cash - diff
    setCar(p, vid, model, config, car)
    if vcf then p.lastVcf = vcf end
    if diff ~= 0 then say(pid, string.format("Swapped to the %s. Cash now %s.", car.name, money(p.cash))) end
    if faultsTaken(p) > 0 then redrawFaults(p); sendFaults(p) end   -- faults come with the deal: drawn again for this car
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
  if p and p.rpc and p.rpc.vid == vid then   -- the RPC: removed by us at the end of a turn, or deleted by the driver
    if not p.rpc.removing then
      p.rpc.vid, p.pos, p.prevPos = nil, nil, nil
      say(pid, "Your reasonably priced car is gone - /tg respawn for a fresh one on the start line.")
    end
    return
  end
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
  if p.run.status == "running" then p.run.status = "dnf" end   -- (before the start: still in, once it's towed back)
  if game.phase ~= "results" then
    sayAll(string.format("%s's %s is out of action! (Respawning it counts as a tow: repair price + %s.)",
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
    billUnstickRepair(p)
    p.damage = 0
    pushState(p)
    return
  end
  local ph = game.phase
  if ph == "idle" or ph == "dealer" or ph == "results" or game.test then return end
  log(string.format("illegal reset by %s in phase %s: fined", p.name, ph))
  p.cash = p.cash - cfg.economy.resetPenalty
  spend(p, "fines", cfg.economy.resetPenalty)
  p.recoveries = (p.recoveries or 0) + 1
  sayAll(string.format("%s pressed the reset button! -%s. That's not very Top Gear.", p.name, money(cfg.economy.resetPenalty)))
  playSound("resetFine", p)
  pushState(p)
end

-- Unstick is free, but if the game repaired the car while moving it, that roadside repair is billed (once)
billUnstickRepair = function(p)
  local cost = (cfg.modes or {}).freeRepair and 0 or (p.unstickRepairQuote or 0)
  p.unstickRepairQuote = 0
  if cost > 0 then
    p.cash = p.cash - cost
    spend(p, "repairs", cost)
    say(p.pid, string.format("Unstick repaired your car on this BeamNG version - that roadside repair is billed (%s). The unstick itself is free.", money(cost)))
  end
end

-- Tow: full repair (keeps upgrades, paid fixes and unfixed faults), repair x markup + towFee, DSQ from a
-- running event, delivery to the next start. carExists=false when a lost car was respawned.
performTow = function(p, carExists)
  local ph = game.phase
  local total, fee, repair = roadsideCost(p, "tow")
  local free = p.freeTow   -- (an admin's free respawn of a lost car)
  p.freeTow = nil
  if free then total, fee, repair = 0, 0, 0 else
    playSound("out", p)
    p.cash = p.cash - total
    spend(p, "towCost", total)
    p.tows = (p.tows or 0) + 1
  end
  p.damage = 0
  local msg
  local pos, dir, idx
  if free then   -- back where it was last seen, nothing else changes
    local lp = p.lastPos
    if lp and tonumber(lp.x) then pos, dir = { x = lp.x, y = lp.y, z = lp.z + 0.5 }, p.lastDir end
    msg = "back where it was"
  elseif (ph == "event" or ph == "countdown") and (p.run.status == "waiting" or p.run.status == "staged") then
    -- (0.9.35, Ryan) the run hasn't started (waiting for a turn, or Ready but no GO yet): back to this start, still in
    pos, dir = towDestination(p, true)
    if p.run.status == "staged" and game.phase == "event" and p.run.ready then
      p.run.ready = nil   -- (a time trial turn: I'm ready again once the car's back)
      say(p.pid, "Press I'm ready again once your car is back on the start line.")
    end
    msg = "dropped back at the start of " .. curEvent().name .. " - your run hasn't started, so you're still in"
  elseif ph == "event" or ph == "countdown" then
    if p.run.status == "running" or p.run.status == "dnf" then
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
      if curEvent().type == "trailer" and cfg.defaults.readyToGo == false then requestTrailer(p) end
    end
    msg = "dropped at the start of " .. curEvent().name .. " (no arrival bonus)"
  elseif ph == "finale" then
    pos = v3(cfg.finale.pos)
    if pos then pos.z = pos.z + 0.5 end
    p.leg.arrived, p.finaleTowed = true, true
    msg = "towed to " .. cfg.finale.name .. " - that's 0 at the finale inspection"
  elseif ph == "workshop" and #workshopSpots() > 0 and nearestSpot(p.pos or p.lastPos) then
    -- (0.9.20, Ryan: a car stuck or beyond repair during the workshop goes to one - the nearest, side by side)
    local sp = nearestSpot(p.pos or p.lastPos)
    local key = "ws " .. tostring(sp.x) .. " " .. tostring(sp.y)
    game.towSlots = game.towSlots or {}
    local slot = game.towSlots[key] or 0
    game.towSlots[key] = slot + 1
    local side = (slot % 2 == 1) and 1 or -1
    pos = { x = sp.x + (slot > 0 and 5 * math.ceil(slot / 2) * side or 0), y = sp.y, z = (sp.z or 0) + 0.5 }
    msg = "towed to the workshop" .. (sp.name and (" at " .. sp.name) or "")
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
  if CONDITION.level(p) > 0 then sendFaults(p) end   -- unfixed faults (and the mileage) come back with the car
  if free then sayAll(string.format("%s's car is back (free, from the producers): %s.", p.name, msg))
  else sayAll(string.format("%s calls the tow truck (%s%s): %s.", p.name, costNote(fee, repair), ptNote(), msg)) end
  pushState(p)
end

local function creditLeft(p) return p.cash + (cfg.workshop.creditLimit or 1500) end
local function overdraftNote(p)
  if p.cash < 0 then
    say(p.pid, string.format("You're overdrawn: %s. Prize money pays it off. (Parts and problem fixes stop at %s overdrawn.)",
      money(p.cash), money(-(cfg.workshop.creditLimit or 1500))))
  end
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
  -- (the mod's own fault / tow changes aren't reported by the client, so everything here is the player's own)
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
  -- a replaced part that had problems is scrap: no trade-in (the new part at its full value); its problems go with it
  local cleared, scrapped = {}, {}
  for _, c in ipairs(type(t.changes) == "table" and t.changes or {}) do
    local sys = c.to and faultsOn() and CONDITION.systemOf(c.slot)
    if sys then
      local any = false
      for _, id in ipairs(sys.faults) do
        if hasFault(p, id) and not cleared[id] then cleared[id], any = sys.name, true end
      end
      if any and tonumber(c.from_value) and tonumber(c.from_value) > 0 then
        delta = delta + tonumber(c.from_value)   -- (the old part's value isn't credited)
        scrapped[#scrapped + 1] = sys.name
      end
    end
  end
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
  -- every part bought here is new (0 km); a replaced part takes its problems with it
  p.freshParts = p.freshParts or {}
  for _, c in ipairs(type(t.changes) == "table" and t.changes or {}) do
    if c.slot then p.freshParts[c.slot] = c.to end
  end
  local names = {}
  for id, sysName in pairs(cleared) do
    removeFault(p, id)
    p.faultsReplaced = (p.faultsReplaced or 0) + 1
    local f = faultDef(id)
    names[#names + 1] = f and CONDITION.problemName(p, id) or id
  end
  table.sort(names)
  if #names > 0 then
    say(p.pid, string.format("The new part%s sorted: %s.%s", #scrapped > 1 and "s" or "", table.concat(names, ", "),
      #scrapped > 0 and " The old one was scrap - no trade-in." or ""))
  end
  if #names > 0 or CONDITION.level(p) > 0 then sendFaults(p) end   -- (the new parts' mileage; removed problems)
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
    local unsticking = p.unstickPending and now() - p.unstickPending < 10
    if unsticking and before >= (cfg.economy.repairMinDamage or 50) and nowDmg < before * 0.2 then
      billUnstickRepair(p)   -- the move repaired the car without the game reporting a reset
    elseif (game.phase == "workshop" or rebuiltOutside) and not paidRecently and before >= (cfg.economy.repairMinDamage or 50)
       and nowDmg < before * 0.2 then
      -- the car got repaired (a part change rebuilds it, or a reset): bill what the repair would have cost - minus
      -- the dents a just-fixed accident-damage problem gave it (that fix puts the bumpers back: the car respawns)
      local billable = before
      local dc = p.dentsCredit
      if dc and now() - dc.at < 15 then billable, p.dentsCredit = math.max(0, before - dc.amount), nil end
      local cost = repairQuote(p, game.phase ~= "workshop", billable)   -- (the workshop discount in a workshop)
      if cost <= 0 or (cfg.modes or {}).freeRepair then cost = nil end
      if cost then
      p.cash = p.cash - cost
      spend(p, "repairs", cost)
      say(p.pid, string.format("Your car was rebuilt%s, which repaired its damage - billed as a repair: -%s.",
        game.phase == "workshop" and " in the workshop" or "", money(cost)))
      log(string.format("workshop: %s's damage dropped %d -> %d, billed repair %s", p.name, math.floor(before), math.floor(nowDmg), money(cost)))
      end
    end
    local ph = game.phase
    if (ph == "travel" or ph == "countdown" or ph == "event" or ph == "finale")
       and nowDmg - before >= (tonumber((cfg.sounds or {}).crashDamage) or 1500)
       and not (p.lastCrashSound and now() - p.lastCrashSound < 10)
       -- (after a tow / respawn / repair the accident-damage fault puts its dents back: not a crash)
       and not (p.towPending and now() - p.towPending < 15) and not (p.respawnPending and now() - p.respawnPending < 15)
       and not (p.repairPending and now() - p.repairPending < 15) then
      p.lastCrashSound = now()
      playSound("crash", p)
    end
    -- (Turbo Mode's biggest crash: every rise in damage adds up, so a repair or a tow mid-event doesn't hide a crash -
    -- but not the dents the accident-damage problem puts back after one)
    if nowDmg > before and not (p.towPending and now() - p.towPending < 15)
       and not (p.respawnPending and now() - p.respawnPending < 15) and not (p.repairPending and now() - p.repairPending < 15) then
      p.crashTotal = (p.crashTotal or 0) + (nowDmg - before)
    end
    p.damage = nowDmg
  end
  if tonumber(t.fuel) then p.fuel = tonumber(t.fuel) end
  if tonumber(t.energy) then p.energy = tonumber(t.energy) end   -- joules in tanks + batteries
  if tonumber(t.cargo) then p.cargoFrac = tonumber(t.cargo) end
  if tonumber(t.air) then   -- the game's running air-time total (s); it starts again from 0 when the game does
    local a = tonumber(t.air)
    p.airTotal = (p.airTotal or 0) + math.max(0, a - ((p.airSeen and p.airSeen <= a) and p.airSeen or 0))
    p.airSeen = a
  end
  local r = p.run
  if r and r.sampleAfter and now() >= r.sampleAfter and r.endDamage == nil then
    r.endDamage, r.endFuel, r.endEnergy = p.damage, p.fuel, p.energy   -- finish reading for fragile / economy scoring
    r.endAir, r.endCrash = p.airTotal or 0, p.crashTotal or 0   -- (Turbo Mode: air time, biggest crash)
  end
  if tonumber(t.partsValue) then
    p.partsValue = tonumber(t.partsValue)

  end
end

---------------------------------------------------------------------------
-- Chat commands
---------------------------------------------------------------------------
-- the admin's vehicles, their own challenge car first (so traffic they spawned never moves a course point)
-- the car each player is sitting in (their game reports it - tg_activeveh): the course builder takes positions from it.
-- Before 0.9.13 it took the challenge car or the first vehicle, so with two cars out every checkpoint could land on a
-- parked one - e.g. on the start line.
-- 0.9.19: "pid-vid|dx|dy" - also the way that car points (from the game itself: the rotation BeamMP reports here
-- doesn't follow the convention we assumed - Ryan: bay boxes skewed, arrows backwards)
local activeVeh = {}
Course.activeDir = {}   -- pid -> { vid, x, y } (a table field: the chunk is at Lua's 200 locals)
function TG_onActiveVeh(pid, data)
  local sid, dx, dy = tostring(data or ""):match("^([^|]*)|?([^|]*)|?([^|]*)")
  activeVeh[pid] = tonumber(tostring(sid or ""):match("(%d+)%s*$"))
  dx, dy = tonumber(dx), tonumber(dy)
  Course.activeDir[pid] = (activeVeh[pid] and dx and dy and (dx * dx + dy * dy) > 0.01) and { vid = activeVeh[pid], x = dx, y = dy } or nil
end
local function adminVehicles(pid)
  local list, own = {}, nil
  local p = playerByPid(pid)
  local mine = MP.GetPlayerVehicles(pid) or {}
  local active = activeVeh[pid]
  if active and mine[active] ~= nil then own = active; list[1] = own
  elseif p and p.carVid then own = p.carVid; list[1] = own end
  local rest = {}
  for vid in pairs(mine) do if vid ~= own then rest[#rest + 1] = vid end end
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

local function adminPose(pid)   -- position, yaw (BeamMP's rotation - for scoring), the way the car points (its game)
  for _, vid in adminVehicles(pid) do
    local raw = MP.GetPositionRaw(pid, vid)
    local pos = type(raw) == "table" and v3(raw.pos)
    local d = Course.activeDir[pid]
    if pos then return roundPos(pos), yawFromQuat(raw.rot), (d and d.vid == vid) and d or nil end
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
  say(pid, "/tg theme (menu colours on/off) | /tg lights (show/hide to position the box) | lightstest shows the sequence | /tg flag (position the finish flag) | flagtest | /tg sounds on|off|list | soundtest [clip|next] | Trailer event: /tg hitchup couples your trailer | /tg partsdiag shows what the game reports about your parts")
  say(pid, "Respawn your car: /tg respawn (free at the dealership, repair price in a workshop, otherwise " ..
    "roadside repair + " .. money(cfg.economy.respawnFee or 500) .. ptNote() .. ")")
  say(pid, "Stuck? /tg unstick (free, when stopped) | /tg tow (roadside repair + " .. money(cfg.economy.towFee) ..
    ptNote() .. ", DSQ from a running event; in workshop time, to the nearest workshop). Roadside repair = the workshop price x " .. tostring(cfg.economy.roadsideMarkup or 1.25) .. ".")
  say(pid, "Car condition: /tg condition new|used|needs work|beater|death trap (at the dealership; alone = yours) | fix <id> (workshop, once it's found the problem)")
  say(pid, "/tg menu (window; /tg menu reset if it's squashed) | name <what to call you> | use <n> [rival] (Turbo Mode prizes) | status | dealer | join | ready | unready | go | quote | repair | standings | diag")
  if isAdmin(name) then
    say(pid, "Game modes: /tg mode <freerepair|nofaults|noquirks|turbo> [on|off] | Turbo Mode: /tg prize <player> [prize] (the producers' choice)")
    say(pid, "Admin: /tg start [force] | next (force the next phase) | stop | restartevent | where | workshop <minutes> | workshopevery <n>")
    say(pid, "Players: /tg give <driver> <+/-cash> | setcash <driver> <cash> | freerespawn <driver> (fixes their car where it stands, free) | bring <driver> (50 m in front of you) | setname <player> <new name>")
    say(pid, "Producers: /tg award <driver> <+/-points> [reason]")
    say(pid, "Traffic: /tg traffic on|off - while on, what you spawn is non-scoring traffic (any phase) and your vehicle menu is open")
    say(pid, "Soundboard: /tg play <clip> plays it for everyone (/tg sounds list)")
    say(pid, "Quirks: /tg quirk test <id> (one go of it on your car, now)")
    say(pid, "Faults: /tg fault test [id] (applies to your car) | fault testoff | fault caps (which cars take which faults) | fault sample <condition> [n] (example problem sets by the tier rules) | fault fire [player] / fault blow [player] (right now)")
    say(pid, "Money: /tg budget <amount> | setcash <name> <amount> | give <name> <amount> | importprices [models] | gameprices on|off")
    say(pid, "Course: /tg setstart <n> | addcp <n> | undocp <n> | clearcp <n> | settrap <n> | settype <n> <type> | settime <n> <s>")
    say(pid, "Parking: /tg addbay <n> | undobay <n> | clearbays <n>  (park facing the way the bay faces)")
    say(pid, "Workshops: /tg importgas | addworkshop [name] | undoworkshop | clearworkshops  (none = anywhere)")
    say(pid, "Session: /tg addevent <type> [name] | delevent <n> | enable <n> on|off | moveevent <n> up|down | setlaps <n> <laps> | setrpc <n> <model> [config]|mine|default")
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

-- what the dealership sells this player: { { model, name, trims = { { config, name, price, needs } } } }, cheapest models
-- first. needs = how many conditions worse would make it affordable (0 = now). A car over the budget even as a Death
-- Trap isn't listed at all (0.9.12: no point showing what nobody can buy) - in the window, /tg dealer and the selector.
local function dealerOffers(p)
  local groups, byModel = {}, {}
  local cond = CONDITION.level(p)
  local function add(model, modelName, t)   -- t.price comes in as the price new; shown in the chosen condition
    local acc = CONDITION.accel(model, t.config)   -- (fast cars hold their value)
    local need = faultsNeeded(p, t.price, acc)
    if need == nil then return end   -- over budget even at the worst condition: not shown
    t.newPrice, t.price = t.price, CONDITION.price(cond, t.price, acc)
    t.needs = need or 0
    t.minCond = CONDITION.needed(p, t.newPrice, acc)   -- the newest condition that affords it (the window colours by it)
    t.over = need == nil or nil
    if need and need > 0 then   -- the condition that would afford it, and its price then
      t.cond, t.condPrice = CONDITION.name(cond + need), CONDITION.price(cond + need, t.newPrice, acc)
    end
    local g = byModel[model]
    if not g then g = { model = model, name = modelName, trims = {} }; byModel[model] = g; groups[#groups + 1] = g end
    g.trims[#g.trims + 1] = t
  end
  local cls = Class.selling()
  if cls then
    for _, t in ipairs(classTrims(cls)) do add(t.model, t.modelName, { config = t.config, name = t.name, price = t.price, est = t.est or nil }) end
  elseif cfg.dealer.useGamePrices then
    for _, c in ipairs(listedModels()) do
      for key, e in pairs((cfg.dealer.gamePrices or {})[c.model] or {}) do
        local price = type(e) == "table" and trimPrice(c.model, key, e)
        if price then add(c.model, c.name, { config = key, name = e.name or key, price = price, est = Class.isEstimate(c.model, key, e) or nil }) end
      end
    end
  else
    for _, c in ipairs(cfg.dealer.cars) do
      add(c.model, c.name, { config = (c.config and c.config ~= "") and c.config or nil, name = c.name, price = c.price })
    end
  end
  local function byPrice(x, y) if x.price ~= y.price then return x.price < y.price end return x.name < y.name end
  for _, g in ipairs(groups) do table.sort(g.trims, byPrice) end
  table.sort(groups, function(x, y) return byPrice(x.trims[1], y.trims[1]) end)
  return groups
end

PLAYER_CMDS.dealer = function(pid, _, args)
  local p = playerByPid(pid)
  local want = args[3] and args[3]:lower()
  say(pid, "DEALERSHIP - budget " .. money(playerBudget(p)) .. (p and (", you have " .. money(p.cash)) or ""))
  if activeClass() then say(pid, "Today's class: " .. chosenClass .. " - " .. classSummary(activeClass()))
  elseif Class.selling() then say(pid, "Every imported car and truck is for sale.") end
  local groups = dealerOffers(p)
  if #groups == 0 then say(pid, "  Nothing for sale."); return end
  local function line(t)
    return string.format("  %s  %s%s", money(t.price), t.name,
      t.over and "  (over budget)" or (t.needs > 0 and ("  (" .. money(t.condPrice) .. " as a " .. tostring(t.cond) .. ")")) or "")
  end
  if want then
    for _, g in ipairs(groups) do
      if g.model == want then for _, t in ipairs(g.trims) do say(pid, line(t)) end; return end
    end
    say(pid, "No model '" .. want .. "' for sale. /tg dealer for the list."); return
  end
  for _, g in ipairs(groups) do
    local tr = g.trims
    local range = (#tr == 1) and money(tr[1].price) or (money(tr[1].price) .. " to " .. money(tr[#tr].price))
    say(pid, string.format("  %s (%s) - %s, %s", g.name, g.model, plural(#tr, "trim"), range))
  end
  if not activeClass() and not cfg.dealer.useGamePrices and not cfg.dealer.strictConfigs then
    say(pid, "(Any stock configuration of a listed model sells at that price.)")
  end
  say(pid, "/tg dealer <model> lists that car's trims and what each one needs, e.g. /tg dealer covet")
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
  if p and (game.phase == "travel" or game.phase == "event" or game.phase == "workshop") and cfg.defaults.readyToGo ~= false then
    return RPC.ready(p)
  end
  if not p or game.phase ~= "dealer" then say(pid, "Nothing to be ready for right now."); return end
  if not p.carVid then say(pid, "Buy a car first!"); return end
  if p.ready then say(pid, "You're already marked ready."); return end
  p.ready = true
  sayAll(string.format("%s is happy with their %s.", p.name, p.carName))
  pushAll()
  for _, q in pairs(game.players) do if q.pid and not q.ready then return end end
  local secs = tonumber(cfg.defaults.readyCountdown) or 5
  if secs <= 0 then lockDealer(); return end
  game.dealerGo, game.dealerCount = now() + secs, nil   -- (tickDealer counts down, then closes the dealership)
  sayAll(string.format("Everyone's ready! The challenge starts in %d seconds.", math.floor(secs)))
end

PLAYER_CMDS.unready = function(pid)
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  RPC.unready(p)
end

PLAYER_CMDS.name = function(pid, name, args)   -- /tg name <what everyone calls you> | /tg name (back to your BeamMP name)
  Score.setAlias(pid, name, table.concat(args, " ", 3))
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
  if cost <= 0 then
    if CONDITION.dents(p) > 0 and (p.damage or 0) > 0 then
      say(pid, "Nothing to repair: the dents are the accident damage problem's - they'd come straight back. Fix the problem itself (/tg fix body).")
    else say(pid, "Your car doesn't need repairs.") end
    return
  end
  -- (repairs, like tows, respawns and fines, may take you as far into the red as they need to; only parts and
  -- fault fixes stop at the overdraft limit)
  if (cfg.modes or {}).freeRepair then cost = 0 end   -- (Free Repair mode)
  p.cash = p.cash - cost
  spend(p, "repairs", cost)
  p.repairPending = now()  -- the repair's own reset is excused for a few seconds only
  p.damage = 0
  MP.TriggerClientEvent(p.pid, "tg_repair", "")
  sayAll(cost > 0 and string.format("%s paid %s to have their %s repaired.", p.name, money(cost), p.carName)
    or string.format("%s had their %s repaired (free).", p.name, p.carName))
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
  say(pid, "Sounds play via: " .. tostring(t.sound or "no clip played yet this session (one plays at the next GO, or try /tg soundtest)") .. (soundsOff[MP.GetPlayerName(pid)] and " - your sounds are OFF" or ""))
  if t.selector then say(pid, "Vehicle selector: " .. tostring(t.selector)) end
  if t.mileage then say(pid, "Car wear (mileage): " .. tostring(t.mileage)) end
  if t.pull then say(pid, "Alignment pull: " .. tostring(t.pull)) end
  if t.rpc then say(pid, "Reasonably priced car: " .. tostring(t.rpc)) end
  for _, e in ipairs(t.errors or {}) do say(pid, "Client error: " .. tostring(e)) end
end

PLAYER_CMDS.go = function(pid, name)
  local p = playerByPid(pid)
  local s = game.solo
  if game.phase == "workshop" and cfg.defaults.readyToGo ~= false then   -- everyone done: on to the next leg
    local all, waiting = RPC.wsAllReady()
    if not all then say(pid, "Waiting for " .. table.concat(waiting, ", ") .. " to press I'm ready."); return end
    sayAll(string.format("%s closes the workshop - on to the next leg!", p and p.name or name))
    endWorkshop()
    return
  end
  if game.phase == "event" and s and s.runner and s.waitGo then   -- a time trial: the waiting driver's GO
    local r = s.runner
    if p ~= r and not isAdmin(name or MP.GetPlayerName(pid)) then
      say(pid, string.format("It's %s's turn - %s presses GO (or an admin).", r.name, r.name)); return
    end
    if cfg.defaults.readyToGo ~= false and not r.run.ready then
      say(pid, string.format("%s isn't ready yet - %s presses I'm ready first.", r.name, r.name)); return
    end
    sayAll(p == r and string.format("%s - GO!", r.name) or string.format("%s starts %s's run.", p and p.name or name, r.name))
    RPC.beginTurn(r, curEvent())
    return
  end
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
  if cfg.defaults.readyToGo ~= false and isSolo(e) then say(pid, "It's one at a time - the turns begin by themselves."); return end
  if cfg.defaults.readyToGo ~= false then
    local all, waiting = RPC.allReady()
    if not all then say(pid, "Waiting for " .. table.concat(waiting, ", ") .. " to press I'm ready."); return end
  end
  sayAll(string.format("%s calls it - %s is on!", p.name, e.name))
  beginCountdown()
end

local testRestore = {}   -- pid -> restore data from an admin fault test

PLAYER_CMDS.faults = function(pid)
  if not faultsOn() then say(pid, "Car condition is switched off (every car is New)."); return end
  local p = playerByPid(pid)
  local offs = {}
  for n = 1, 4 do offs[#offs + 1] = string.format("%s up to %d%% off", CONDITION.name(n), CONDITION.percentOff(n)) end
  say(pid, "CAR CONDITION - a more worn car is cheaper on the market (every car's price): " .. table.concat(offs, ", ") ..
    " - less for fast cars, which hold their value. Each step adds mileage and one hidden problem picked at random; a workshop finds them.")
  say(pid, string.format("Fixing a problem in a workshop costs %d%% of the car's new price (at least %s); each one still there at the finale costs %s points.",
    math.floor((tonumber(cfg.faults.fixPercent) or 0.05) * 100 + 0.5), money(tonumber(cfg.faults.fixMin) or 500), tostring(cfg.faults.inspectionPenaltyPoints or 0)))
  if p then
    local n = CONDITION.level(p)
    say(pid, "Your car: " .. CONDITION.name(n) .. (p.faultsRevealed and (" - " .. (#p.faults == 0 and "no problems left" or table.concat(faultNames(p), ", ")))
      or (n > 0 and " - a workshop will find its problems" or "")))
  end
  say(pid, "/tg condition <New|Used|Needs work|Beater|Death Trap> at the dealership | /tg fix <id> in a workshop once it has found the problem")
end

PLAYER_CMDS.fault = function(pid, name, args)
  if not faultsOn() then say(pid, "Problem cars are switched off."); return end
  local sub, id = (args[3] or ""):lower(), (args[4] or ""):lower()
  if sub == "fire" or sub == "blow" then   -- (0.9.27) right now, on your car (or a player's): a fuel leak fire / a blown engine
    if not isAdmin(name) then say(pid, "That's an admin command."); return end
    local who = table.concat(args, " ", 4)
    local target = who ~= "" and Score.findPlayer(who) or nil
    if who ~= "" and not (target and target.pid) then say(pid, "Usage: /tg fault " .. sub .. " [player] - no connected player " .. who .. "."); return end
    local tpid = target and target.pid or pid
    MP.TriggerClientEvent(tpid, "tg_faultnow", sub)
    say(pid, (sub == "fire" and "Setting fire to " or "Blowing the engine of ") .. (target and (target.name .. "'s car") or "your car") ..
      " - a test: no tow, no message to the others, nothing on the bill.")
    if target and tpid ~= pid then say(tpid, "An admin is testing a " .. (sub == "fire" and "car fire" or "blown engine") .. " on your car.") end
    return
  end
  if sub == "sample" then   -- (0.9.21) example problem sets for a condition, drawn by the tier rules (any car)
    if not isAdmin(name) then say(pid, "That's an admin command."); return end
    local count = tonumber(args[#args])
    local cond = CONDITION.parse(table.concat(args, " ", 4, count and (#args - 1) or #args))
    if not cond or cond < 1 or cond > 4 then say(pid, "Usage: /tg fault sample <Used|Needs work|Beater|Death Trap> [how many, up to 50]"); return end
    count = math.max(1, math.min(50, math.floor(count or 5)))
    for i = 1, count do
      local car = { faults = {}, boughtCondition = cond }
      for _ = 1, cond do
        local cands = {}
        for _, f in ipairs(cfg.faults.list or {}) do
          local tooNew = tonumber(f.minCondition) and cond < tonumber(f.minCondition)
          if f.enabled ~= false and not tooNew and not hasFault(car, f.id) and CONDITION.tierOK(car, f, cond) then cands[#cands + 1] = f.id end
        end
        if #cands == 0 then break end
        car.faults[#car.faults + 1] = cands[math.random(#cands)]
      end
      local shown = {}
      for _, fid in ipairs(car.faults) do shown[#shown + 1] = fid .. " (T" .. CONDITION.tier(faultDef(fid)) .. ")" end
      say(pid, string.format("%s %d: %s", CONDITION.name(cond), i, table.concat(shown, ", ")))
    end
    return
  end
  if sub == "test" or sub == "testoff" then
    if not isAdmin(name) then say(pid, "That's an admin command."); return end
    local list = {}
    -- "/tg fault test [id] [as <condition>]": strengths as on a car bought in that condition (none: as listed)
    local cond
    for i = 3, #args do
      if (args[i] or ""):lower() == "as" then
        cond = CONDITION.parse(table.concat(args, " ", i + 1))
        if not cond or cond < 1 or cond > 4 then say(pid, "Test as: used, needs work, beater or death trap."); return end
        if i == 4 then id = "" end
        break
      end
    end
    local sev = cond and CONDITION.sevOf(cond) or 1
    if sub == "test" then
      for _, f in ipairs(cfg.faults.list) do
        if id == "" or id == f.id then
          -- (a test alignment pulls right; a test oil leak always blows - soon - so it can be seen)
          list[#list + 1] = CONDITION.payload(f, sev, 1, f.id == "oilleak" or f.id == "fuelleak")   -- (a test shows the worst)
        end
      end
    end
    say(pid, sub == "test" and string.format("Applying %d test fault(s) to your current car%s...", #list,
      cond and string.format(" as a %s (x%g)", CONDITION.name(cond), sev) or " (listed strengths)") or "Removing test faults...")
    MP.TriggerClientEvent(pid, "tg_faults", Util.JsonEncode({ faults = list, restore = testRestore[pid] or {}, test = true }))
    return
  end
  if sub == "caps" then   -- what we've learnt about which cars take which faults
    if not isAdmin(name) then say(pid, "That's an admin command."); return end
    local keys = {}
    for k in pairs(cfg.faultCaps or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    if #keys == 0 then say(pid, "No cars tested yet - faults are learnt as players take them (or /tg fault test on a car)."); return end
    for _, k in ipairs(keys) do
      local c, ok, no = cfg.faultCaps[k], {}, {}
      for fid in pairs(c.ok or {}) do ok[#ok + 1] = fid end
      for fid in pairs(c.no or {}) do no[#no + 1] = fid end
      table.sort(ok); table.sort(no)
      say(pid, string.format("%s: works %s%s", k, #ok > 0 and table.concat(ok, ", ") or "-",
        #no > 0 and (" | can't take " .. table.concat(no, ", ")) or ""))
    end
    return
  end
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  if sub == "undo" then say(pid, "Use /tg condition to pick a better condition (only before you've bought your car)."); return end
  if sub ~= "take" then say(pid, "Usage: /tg condition <New|Used|Needs work|Beater|Death Trap>"); return end
  local n = tonumber(args[4] or "1")
  if not n or n < 1 then say(pid, "Usage: /tg condition <New|Used|Needs work|Beater|Death Trap>"); return end
  PLAYER_CMDS.condition(pid, name, { "/tg", "condition", tostring(faultsTaken(p) + math.floor(n)) })
end

-- /tg condition <0-4 | New | Used | Needs work | Beater | Death Trap> - the Dealership tab's slider sends this.
-- Before a car is bought it moves both ways (the cash follows); after, only toward Death Trap.
PLAYER_CMDS.condition = function(pid, name, args)
  if not faultsOn() then say(pid, "Car condition is switched off (every car is New)."); return end
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  local cur, max = CONDITION.level(p), math.min(cfg.faults.maxPerCar or 4, 4)
  local want = CONDITION.parse(table.concat(args, " ", 3))
  if not want then say(pid, "Your car: " .. CONDITION.name(cur) .. ". Usage: /tg condition <New|Used|Needs work|Beater|Death Trap>"); return end
  if game.phase ~= "dealer" then say(pid, "The car's condition is picked at the dealership."); return end
  if p.boughtCondition then
    say(pid, string.format("You've bought your %s as %s - that's locked in (return it to choose again).", p.carName or "car", CONDITION.name(cur)))
    pushState(p)
    return
  end
  want = math.max(0, math.min(want, max))
  p.faultsOwed = want   -- (drawn as hidden problems when the car is bought)
  say(pid, string.format("Car condition: %s%s.", CONDITION.name(want),
    want > 0 and string.format(" (%s km) - cars up to %d%% off (fast ones hold their value)", (money(CONDITION.km(want)):gsub("^%$", "")), CONDITION.percentOff(want)) or " - full price"))
  pushState(p)
end

PLAYER_CMDS.fix = function(pid, _, args)
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  if game.phase ~= "workshop" then say(pid, "Problems can only be fixed in a workshop."); return end
  if not inWorkshop(p) then say(pid, "Drive to a workshop first - the arrows show the nearest."); return end
  revealFaults(p)   -- (a workshop always diagnoses the car first)
  local id = (args[3] or ""):lower()
  if CONDITION.hasQuirk(p, id) then   -- a quirk: a flat fee (0.9.29)
    local q, cost = CONDITION.quirkDef(id), math.floor(tonumber((cfg.quirks or {}).fixCost) or 150)
    if cost > creditLeft(p) then say(pid, string.format("Sorting that costs %s - you have %s.", money(cost), money(p.cash))); return end
    for i, x in ipairs(p.quirks) do if x == id then table.remove(p.quirks, i); break end end
    if p.quirkAt then p.quirkAt[id] = nil end
    p.cash = p.cash - cost
    spend(p, "faultFixes", cost)
    sayAll(string.format("%s pays %s to get rid of the %s.", p.name, money(cost), (q and q.name or id):lower()))
    pushState(p)
    return
  end
  local f = faultDef(id)
  if not (f and hasFault(p, id)) then say(pid, "Your car doesn't have that problem. Yours: " .. (#p.faults > 0 and table.concat(p.faults, ", ") or "none")); return end
  local cost = fixCost(p)
  if cost > creditLeft(p) then say(pid, string.format("Fixing that costs %s - you have %s (at most %s overdrawn).", money(cost), money(p.cash), money(cfg.workshop.creditLimit or 1500))); return end
  removeFault(p, id)
  if id == "body" then   -- the dents go with the fault: not a repair to bill as well (any other crash damage still is)
    p.repairPending = now()
    p.dentsCredit = { at = now(), amount = tonumber(CONDITION.scaled(f, CONDITION.severity(p))) or 0 }
  end
  p.cash = p.cash - cost
  spend(p, "faultFixes", cost)
  p.faultsFixed = (p.faultsFixed or 0) + 1
  sayAll(string.format("%s pays %s to have the %s sorted.", p.name, money(cost), CONDITION.problemName(p, id):lower()))
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
  local changed, learnt = false, false
  local caps = p.carModel and capsFor(p)
  for id, st in pairs(t.results or {}) do
    if st == "ok" and caps and not caps.ok[id] then caps.ok[id], learnt = true, true end
    if st ~= "ok" and st ~= "removed" and hasFault(p, id) then
      -- this car can't take it: swap it for another one (the player doesn't know which they have anyway)
      removeFault(p, id)
      p.faultTried = p.faultTried or {}
      p.faultTried[id] = true
      if caps and st == "unavailable" and not caps.no[id] then caps.no[id], learnt = true, true end
      p.faultsOwed = (p.faultsOwed or 0) + 1
      log(string.format("fault %s can't be applied to %s's %s (%s) - drawing another", tostring(id), p.name, carKey(p), tostring(st)))
      changed = true
    end
  end
  if changed then drawFaults(p); sendFaults(p); pushState(p) end
  if learnt then saveConfig() end
end

-- client -> server: a doomed engine (oil leak) has just let go
function TG_onEngineBlown(pid)
  local p = playerByPid(pid)
  if not p or not hasFault(p, "oilleak") or p.oilBlown then return end
  p.oilBlown, p.oilDoomed = true, false   -- that engine has gone; the next one won't
  sayAll(string.format("%s's engine has let go! That's a tow.", p.name))
  playSound("crash", p)
  log(string.format("engine blown (oil leak) for %s", p.name))
  pushState(p)
end

-- client -> server: a doomed fuel leak has just caught fire (once per car - 0.9.26)
function TG_onCarFire(pid)
  local p = playerByPid(pid)
  if not p or not hasFault(p, "fuelleak") or p.fuelBurnt then return end
  p.fuelBurnt, p.fuelDoomed = true, false
  sayAll(string.format("%s's car is ON FIRE! The fuel leak's found something hot.", p.name))
  playSound("crash", p)
  log(string.format("car fire (fuel leak) for %s", p.name))
  pushState(p)
end

-- Turbo Mode (0.9.32, Ryan): prizes for everything but winning, kept in a glovebox, used when the player likes --------
function Score.turboOn() return (cfg.modes or {}).turbo == true end
function Score.prizeDef(id)
  for _, pr in ipairs((cfg.turbo or {}).prizes or {}) do if pr.id == id then return pr end end
  return nil
end
function Score.prizeUsable(id)   -- (not one the game modes have switched off)
  if (id == "favour" or id == "sugar") and not faultsOn() then return false end
  if id == "exorcism" and ((cfg.modes or {}).noQuirks or (cfg.quirks or {}).enabled == false) then return false end
  return true
end
function Score.gloveboxList(p)
  if not Score.turboOn() or not p.glovebox or #p.glovebox == 0 then return nil end
  local out = {}
  for _, id in ipairs(p.glovebox) do
    local pr = Score.prizeDef(id)
    if pr then out[#out + 1] = { id = id, name = pr.name, help = pr.help, target = pr.target or nil } end
  end
  return out
end
-- a prize for p: `id`, or one at random (goodOnly: only the helpful ones - last place's comeback)
function Score.turboAward(p, why, goodOnly, id)
  if not Score.turboOn() or not p then return end
  local tc = cfg.turbo or {}
  p.glovebox = p.glovebox or {}
  if #p.glovebox >= (tonumber(tc.maxHeld) or 3) then
    say(p.pid, "Your glovebox is full (" .. why .. ") - use a prize to make room."); return
  end
  if not id then
    local pool = {}
    for _, pr in ipairs(tc.prizes or {}) do
      if pr.enabled ~= false and Score.prizeUsable(pr.id) and (pr.good or not goodOnly) then pool[#pool + 1] = pr.id end
    end
    if #pool == 0 then return end
    id = pool[math.random(#pool)]
  end
  local pr = Score.prizeDef(id)
  if not pr then return end
  p.glovebox[#p.glovebox + 1] = id
  sayAll(string.format("TURBO: %s wins a prize for %s - it's in their glovebox.", p.name, why))
  say(p.pid, string.format("Your prize: %s - %s (Status tab: Glovebox)", pr.name, pr.help))
  pushState(p)
end
function Score.turboEventPrizes(ranked, others)
  if not Score.turboOn() or #ranked < 2 then return end
  local clean, cleanD = nil, nil
  for _, p in ipairs(ranked) do
    local d = math.max(0, (p.run.endDamage or p.damage or 0) - (p.run.startDamage or 0))
    if not cleanD or d < cleanD then clean, cleanD = p, d end
  end
  local last = ranked[#ranked]
  if clean then Score.turboAward(clean, "the cleanest car at the finish") end
  if last then Score.turboAward(last, "last place (a comeback prize)", true) end
  -- (0.9.33) most air time and the biggest crash: everyone who started the event, finished or not
  local tc = cfg.turbo or {}
  local air, airS, crash, crashD = nil, tonumber(tc.minAir) or 1, nil, tonumber(tc.minCrash) or 1000
  for _, list in ipairs({ ranked, others or {} }) do
    for _, p in ipairs(list) do
      local r = p.run or {}
      if r.startT then
        local a = (r.endAir or p.airTotal or 0) - (r.startAir or 0)
        local c = (r.endCrash or p.crashTotal or 0) - (r.startCrash or 0)
        if a >= airS then air, airS = p, a end
        if c >= crashD and p ~= clean then crash, crashD = p, c end
      end
    end
  end
  if air then Score.turboAward(air, string.format("the most air time (%.1f s)", airS)) end
  if crash then Score.turboAward(crash, "the biggest crash") end
end
function Score.turboTimes(ranked, e)   -- head starts and penalty cards, on the time before the event is scored
  for _, p in ipairs(ranked) do
    local ef = p.effects or {}
    local adj = (ef.penalty or 0) - (ef.headstart or 0)
    if adj ~= 0 and e.type ~= "speedtrap" and tonumber(p.run.time) then
      p.run.time = math.max(0, p.run.time + adj)
      sayAll(string.format("TURBO: %s's time %s %s s (%s).", p.name, adj > 0 and "gets" or "loses", tostring(math.abs(adj)),
        adj > 0 and "a penalty card" or "a head start"))
    end
    ef.penalty, ef.headstart = nil, nil
  end
end
-- /tg use <n> [rival]: use the nth prize in your glovebox
function Score.turboUse(p, n, targetText)
  local id = (p.glovebox or {})[n]
  local pr = id and Score.prizeDef(id)
  if not pr then say(p.pid, "No prize " .. tostring(n) .. " in your glovebox."); return end
  local q
  if pr.target then
    q = Score.findPlayer(targetText or "")
    if not q or q == p then say(p.pid, pr.name .. ": pick a rival (/tg use " .. n .. " <name>)."); return end
    if q.run and q.run.status == "running" then say(p.pid, q.name .. " is on a run - try again after it."); return end
    if q.sabotagedAt == game.stage then say(p.pid, q.name .. " has already been got at this leg - try again later."); return end
  end
  local msg = Score.turboApply(p, id, q)
  if not msg then return end
  table.remove(p.glovebox, n)
  -- (msg starts "%s" = the user's name; not string.format: a problem's name can hold a % - "Tired engine (about -20% power)")
  sayAll("TURBO: " .. p.name .. msg:sub(3) .. "!")
  playSound("trapRecord", p)
  pushState(p)
end
-- what prize `id` does: p uses it (on rival q for the nasty ones). Returns the message ("%s ..." = p's name), or nil
-- when it can't be used (p has been told why). test (the admin's Testing tools): the tune works at once (not just
-- in the next event) and nobody is marked as got at this leg; q may be p.
function Score.turboApply(p, id, q, test)
  local tc = cfg.turbo or {}
  p.effects = p.effects or {}
  local msg
  if id == "tune" then
    p.effects.tune = true
    if test then p.effects.tuneNow = true end
    msg = "%s has their engine tuned: +10% power for the next event"
  elseif id == "favour" then
    if #(p.faults or {}) == 0 then say(p.pid, "Your car has no problems to fix - keep it for later."); return end
    local fid = p.faults[math.random(#p.faults)]
    removeFault(p, fid); sendFaults(p)
    msg = "%s calls in a mechanic's favour: the " .. CONDITION.problemName(p, fid):lower() .. " is fixed, free"
  elseif id == "exorcism" then
    if #(p.quirks or {}) == 0 then say(p.pid, "Your car has no quirks - keep it for later."); return end
    local qid = table.remove(p.quirks, math.random(#p.quirks))
    local qd = CONDITION.quirkDef(qid)
    msg = "%s has their car exorcised: no more " .. ((qd and qd.name) or qid):lower()
  elseif id == "jail" then p.pardons = (p.pardons or 0) + 1; msg = "%s has a get out of jail card: their next tow or respawn costs no points"
  elseif id == "envelope" then
    local lo, hi = tonumber((tc.envelope or {})[1]) or 500, tonumber((tc.envelope or {})[2]) or 2000
    local cash = math.floor(math.random(math.floor(lo / 100), math.floor(hi / 100))) * 100
    p.cash = p.cash + cash
    msg = "%s opens the producers' envelope: " .. money(cash)
  elseif id == "headstart" then p.effects.headstart = tonumber(tc.headStart) or 2; msg = "%s takes a head start: 2 s off their next event time"
  else   -- the nasty ones
    q.effects = q.effects or {}
    if not test then q.sabotagedAt = game.stage end
    if id == "horn" then q.effects.horn = true; msg = "%s sabotages " .. q.name .. ": their horn now goes off every time they brake"
    elseif id == "frbrake" then q.effects.frbrake = true; msg = "%s kindly upgrades " .. q.name .. "'s brakes - the front right one"
    elseif id == "sugar" then
      local fid = hasFault(q, "engine") and "fuelleak" or "engine"
      if hasFault(q, fid) then say(p.pid, q.name .. "'s engine is already as bad as it gets - pick another rival."); return end
      q.faults = q.faults or {}
      q.faults[#q.faults + 1] = fid
      sendFaults(q)
      msg = "%s puts sugar in " .. q.name .. "'s tank: " .. CONDITION.problemName(q, fid):lower()
    elseif id == "taxman" then
      local amt = tonumber(tc.taxman) or 500
      q.cash, p.cash = q.cash - amt, p.cash + amt
      msg = "%s sends the taxman round to " .. q.name .. ": " .. money(amt) .. " changes hands"
    elseif id == "penalty" then q.effects.penalty = (q.effects.penalty or 0) + (tonumber(tc.penalty) or 3); msg = "%s shows " .. q.name .. " a penalty card: +3 s on their next event time" end
    pushState(q)
  end
  return msg
end
PLAYER_CMDS.use = function(pid, _, args)   -- /tg use <n> [rival]
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  if not Score.turboOn() then say(pid, "Turbo Mode is off."); return end
  Score.turboUse(p, math.floor(tonumber(args[3]) or 0), table.concat(args, " ", 4))
end
-- the Admin tab's Turbo Mode box: every prize, and each player's glovebox, Turbo effects and air time / crash counters
function Score.turboAdminView()
  local prizes, players = {}, {}
  for _, pr in ipairs((cfg.turbo or {}).prizes or {}) do
    if pr.enabled ~= false then
      prizes[#prizes + 1] = { id = pr.id, name = pr.name, help = pr.help, target = pr.target or nil, usable = Score.prizeUsable(pr.id) }
    end
  end
  for _, q in ipairs(sortedPlayers()) do
    local held, on = {}, {}
    for _, id in ipairs(q.glovebox or {}) do local pr = Score.prizeDef(id); held[#held + 1] = pr and pr.name or id end
    local ef = q.effects or {}
    if ef.tune then on[#on + 1] = ef.tuneNow and "engine tune (now)" or "engine tune (next event)" end
    if ef.headstart then on[#on + 1] = "head start -" .. tostring(ef.headstart) .. " s" end
    if ef.penalty then on[#on + 1] = "penalty +" .. tostring(ef.penalty) .. " s" end
    if ef.horn then on[#on + 1] = "haunted horn" end
    if ef.frbrake then on[#on + 1] = "front-right brake" end
    if (q.pardons or 0) > 0 then on[#on + 1] = "get out of jail x" .. tostring(q.pardons) end
    local r = q.run or {}
    players[#players + 1] = { name = q.name, glovebox = held, effects = on,
      air = math.floor((q.airTotal or 0) * 10 + 0.5) / 10, crash = math.floor(q.crashTotal or 0),
      runAir = r.startT and math.floor(((r.endAir or q.airTotal or 0) - (r.startAir or 0)) * 10 + 0.5) / 10 or nil,
      runCrash = r.startT and math.floor((r.endCrash or q.crashTotal or 0) - (r.startCrash or 0)) or nil }
  end
  local tc = cfg.turbo or {}
  return { prizes = prizes, players = players, maxHeld = tonumber(tc.maxHeld) or 3,
           minAir = tonumber(tc.minAir) or 1, minCrash = tonumber(tc.minCrash) or 1000 }
end
-- Admin testing tools (0.9.34): /tg prize test <id> [player] = the prize's effect right now (a nasty one on that player -
-- yourself by default - from you; a helpful one for that player), skipping the glovebox and the once-a-leg / mid-run
-- rules, told only to you and them; /tg prize clear [player] = every Turbo effect on them gone; /tg prize empty [player]
-- = their glovebox emptied.
function Score.turboAdminTest(pid, sub, args)
  local admin = playerByPid(pid)
  local id = sub == "test" and (args[4] or ""):lower() or nil
  local rest = table.concat(args, " ", sub == "test" and 5 or 4)
  local q = rest ~= "" and Score.findPlayer(rest) or admin
  if not q then
    say(pid, rest ~= "" and ("No player called " .. rest .. ".") or "You're not in the challenge - start one (Start (unfinished course) will do) and buy a car.")
    return
  end
  if sub == "clear" then
    q.effects, q.pardons, q.sabotagedAt = {}, nil, nil
    say(pid, "Turbo test: every Turbo effect on " .. q.name .. " cleared (horn, brake, tune, head start, penalty, jail cards).")
    pushState(q); return
  elseif sub == "empty" then
    q.glovebox = {}
    say(pid, "Turbo test: " .. q.name .. "'s glovebox emptied.")
    pushState(q); return
  end
  local pr = Score.prizeDef(id)
  if not pr then say(pid, "Usage: /tg prize test <prize id> [player]"); return end
  if not Score.prizeUsable(id) then say(pid, pr.name .. " does nothing with the current game modes."); return end
  local user, victim = q, nil
  if pr.target then user, victim = admin or q, q end
  local msg = Score.turboApply(user, id, victim, true)
  if not msg then
    if user.pid ~= pid then say(pid, "Turbo test: " .. pr.name .. " didn't work on " .. user.name .. " (they were told why).") end
    return
  end
  local text = "TURBO TEST: " .. user.name .. msg:sub(3) .. "."
  say(pid, text)
  if q.pid and q.pid ~= pid then say(q.pid, text) end
  log(text)
  pushState(user)
end
ADMIN_CMDS.prize = function(pid, _, args)   -- /tg prize <player> [prize id]: the producers' choice
  if not Score.turboOn() then say(pid, "Turbo Mode is off (/tg mode turbo on)."); return end
  local sub = (args[3] or ""):lower()
  if sub == "test" or sub == "clear" or sub == "empty" then return Score.turboAdminTest(pid, sub, args) end
  local last = (args[#args] or ""):lower()
  local id = Score.prizeDef(last) and last or nil
  local p = Score.findPlayer(table.concat(args, " ", 3, id and (#args - 1) or #args))
  if not p then
    local ids = {}
    for _, pr in ipairs((cfg.turbo or {}).prizes or {}) do ids[#ids + 1] = pr.id end
    say(pid, "Usage: /tg prize <player> [" .. table.concat(ids, "|") .. "]"); return
  end
  Score.turboAward(p, "the producers' choice", false, id)
end

-- Quirks (0.9.29): drawn with the car's problems, fired by the server's tick, heard by everyone nearby ----------------
function CONDITION.quirkDef(id)
  for _, q in ipairs((cfg.quirks or {}).list or {}) do if q.id == id then return q end end
  return nil
end
function CONDITION.hasQuirk(p, id)
  for _, x in ipairs(p.quirks or {}) do if x == id then return true end end
  return false
end
function CONDITION.quirkList(p)   -- { { id, name } } for the menu
  local out = {}
  for _, id in ipairs(p.quirks or {}) do local q = CONDITION.quirkDef(id); out[#out + 1] = { id = id, name = q and q.name or id } end
  return #out > 0 and out or nil
end
function CONDITION.drawQuirks(p)
  p.quirks, p.quirkAt = {}, nil
  local qc = cfg.quirks or {}
  local range = (qc.count or {})[CONDITION.level(p)]
  if qc.enabled == false or (cfg.modes or {}).noQuirks or type(range) ~= "table" then return end
  local lo, hi = math.floor(tonumber(range[1]) or 0), math.floor(tonumber(range[2]) or 0)
  local n = hi > lo and math.random(lo, hi) or lo
  local pool = {}
  for _, q in ipairs(qc.list or {}) do if q.enabled ~= false then pool[#pool + 1] = q.id end end
  for _ = 1, n do
    if #pool == 0 then break end
    p.quirks[#p.quirks + 1] = table.remove(pool, math.random(#pool))
  end
end
-- one go of quirk q on car "pid-vid" (owner = pid): to the owner, and to everyone within sounds.nearRadius for sounds
function CONDITION.quirkFire(pid, vid, name, pos, q)
  if type(q.say) == "table" and #q.say > 0 then sayAll(string.format(q.say[math.random(#q.say)], name)); return end
  local sid = tostring(pid) .. "-" .. tostring(vid)
  if q.action then   -- (the owner's game works the controls; BeamMP shows them to the others)
    MP.TriggerClientEvent(pid, "tg_quirkfx", Util.JsonEncode({ sid = sid, own = true, action = q.action }))
    return
  end
  local event = type(q.events) == "table" and #q.events > 0 and q.events[math.random(#q.events)] or nil
  local r = tonumber((cfg.sounds or {}).nearRadius) or 100
  for qpid, qname in pairs(MP.GetPlayers() or {}) do
    local qp = playerByPid(qpid)
    local near = qpid == pid or (pos and qp and qp.pos and dist(qp.pos, pos) <= r)
    if near and not soundsOff[qname] then
      if q.clip then MP.TriggerClientEvent(qpid, "tg_sound", Util.JsonEncode({ clip = q.clip }))
      elseif event then MP.TriggerClientEvent(qpid, "tg_quirkfx", Util.JsonEncode({ sid = sid, own = qpid == pid, event = event })) end
    end
  end
end
CONDITION.QUIRK_PHASES = { travel = true, event = true, finale = true }   -- on the road (never during a countdown; a table field: 200 locals)
function CONDITION.quirkTick()
  if not CONDITION.QUIRK_PHASES[game.phase] or (cfg.quirks or {}).enabled == false or (cfg.modes or {}).noQuirks then return end
  for _, p in pairs(game.players) do
    if racing(p) and not p.rpc and p.quirks and #p.quirks > 0 then
      p.quirkAt = p.quirkAt or {}
      for _, id in ipairs(p.quirks) do
        local q = CONDITION.quirkDef(id)
        local every = q and type(q.every) == "table" and q.every
        if every then
          local lo, hi = tonumber(every[1]) or 120, tonumber(every[2]) or 300
          p.quirkAt[id] = p.quirkAt[id] or (now() + lo + math.random(0, math.max(0, math.floor(hi - lo))))
          if now() >= p.quirkAt[id] then
            if q.parked or (p.speed or 0) > 3 then
              p.quirkAt[id] = nil
              CONDITION.quirkFire(p.pid, p.carVid, p.name, p.pos, q)
            else p.quirkAt[id] = now() + 5 end   -- (it waits until you're moving)
          end
        end
      end
    end
  end
end
-- /tg quirk test <id> (admin): one go of it on the car you're in, now
ADMIN_CMDS.quirk = function(pid, name, args)
  local id = (args[4] or ""):lower()
  local q = (args[3] or ""):lower() == "test" and CONDITION.quirkDef(id)
  if not q then
    local ids = {}
    for _, x in ipairs((cfg.quirks or {}).list or {}) do ids[#ids + 1] = x.id end
    say(pid, "Usage: /tg quirk test <" .. table.concat(ids, "|") .. ">"); return
  end
  local vid = activeVeh[pid]
  if not vid then local p = playerByPid(pid); vid = p and p.carVid end
  if not vid then say(pid, "Get in a car first."); return end
  local raw = MP.GetPositionRaw(pid, vid)
  if q.id == "squeak" then
    MP.TriggerClientEvent(pid, "tg_quirkfx", Util.JsonEncode({ sid = tostring(pid) .. "-" .. tostring(vid), own = true, action = "squeak" }))
  else CONDITION.quirkFire(pid, vid, MP.GetPlayerName(pid), type(raw) == "table" and v3(raw.pos) or nil, q) end
  say(pid, "Quirk test: " .. q.name .. (q.id == "squeak" and " - brake gently to hear it (until your car resets)" or "") .. ".")
end

PLAYER_CMDS.menu = function(pid, _, args)
  local reset = args[3] and args[3]:lower() == "reset"
  MP.TriggerClientEvent(pid, "tg_menu", reset and "reset" or "")
end

local TOW_PHASES = { travel = true, countdown = true, event = true, finale = true }
-- (0.9.20) the workshop too, when the course has workshop locations and you're not at one: to the nearest one
function Course.canTow(p)
  if TOW_PHASES[game.phase] then return true end
  return game.phase == "workshop" and #workshopSpots() > 0 and not inWorkshop(p)
end

PLAYER_CMDS.tow = function(pid)
  local p = playerByPid(pid)
  if p and p.rpc then say(pid, "You're in the reasonably priced car - /tg respawn gets you a fresh one on the start line (free)."); return end
  if not (p and p.carVid) then say(pid, "You don't have a car out to tow - respawn it from the vehicle menu (that counts as a tow)."); return end
  if not Course.canTow(p) then say(pid, game.phase == "workshop" and "You're in the workshop - use /tg repair." or "No tow truck needed right now."); return end
  if p.finaleTowed or (game.phase == "finale" and p.leg.arrived) then say(pid, "You've already finished."); return end
  performTow(p, true)
end

PLAYER_CMDS.respawn = function(pid)
  local p = playerByPid(pid)
  if not p then say(pid, "You're not in the challenge."); return end
  if p.rpc then   -- your turn in the reasonably priced car: a fresh one on the start line, free
    if not RPC.fresh(p) then say(pid, "Wait a moment - your car is on its way.") end
    return
  end
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
  local total, fee, repair = roadsideCost(p, "respawn")
  p.cash = p.cash - total
  spend(p, "towCost", total)
  p.respawns = (p.respawns or 0) + 1
  p.damage, p.respawnPending = 0, now()
  local extra = ""
  if (ph == "event" or ph == "countdown") and p.run.status == "running" then   -- (not before the run starts - 0.9.35)
    p.run.status, p.run.dsqReason = "dsq", "respawned"
    playSound("out", p)
    extra = " - disqualified from " .. curEvent().name
  elseif ph == "finale" then
    p.finaleRebuilt = true
    extra = " - a fresh car scores 0 drivability at the inspection"
  end
  MP.TriggerClientEvent(pid, "tg_respawn", Util.JsonEncode({ reset = true }))
  sayAll(string.format("%s respawns their %s on the spot (%s%s)%s.", p.name, p.carName or "car", costNote(fee, repair),
    ptNote(), extra))
  pushState(p)
end

PLAYER_CMDS.unstick = function(pid)
  local p = playerByPid(pid)
  if p and p.rpc then return PLAYER_CMDS.respawn(pid) end   -- (stuck in the RPC: a fresh one)
  if not (p and p.carVid) then say(pid, "You don't have a car out."); return end
  if game.phase == "idle" or game.phase == "countdown" then say(pid, "Not during the countdown."); return end
  if (p.speed or 0) > (cfg.economy.unstickMaxSpeed or 3) then say(pid, "Stop first - unstick only works when you're (nearly) stationary."); return end
  local cd = cfg.economy.unstickCooldown or 15
  if p.lastUnstick and now() - p.lastUnstick < cd then
    say(pid, string.format("Unstick is cooling down - try again in %d s.", math.ceil(cd - (now() - p.lastUnstick)))); return
  end
  p.lastUnstick, p.unstickPending, p.unstickRepairQuote = now(), now(), roadsideRepair(p)
  MP.TriggerClientEvent(pid, "tg_unstick", "")
end

-- client -> server: { kind = "tow"|"unstick", ok = bool, method = string, detail = string }
function TG_onMoveReport(pid, data)
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  log(string.format("%s %s by %s: %s (%s)", tostring(t.kind), t.ok and "ok" or "FAILED", tostring(MP.GetPlayerName(pid)),
    tostring(t.method), tostring(t.detail)))
  local p = playerByPid(pid)
  if p and t.kind == "restore" and p.trailerAfterRestore then   -- a re-run trailer event: a new trailer behind it
    p.trailerAfterRestore = nil
    requestTrailer(p)
  end
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

PLAYER_CMDS.sounds = function(pid, name, args)
  local want = (args[3] or ""):lower()
  if want == "list" then
    say(pid, "Clips: " .. table.concat((cfg.sounds or {}).clips or {}, ", ")); return
  end
  local off
  if want == "off" then off = true elseif want == "on" then off = false else off = not soundsOff[name] end
  soundsOff[name] = off or nil
  say(pid, off and "Sounds OFF for you. /tg sounds on to hear them again." or "Sounds ON. /tg soundtest plays one to check you can hear it.")
end

PLAYER_CMDS.watch = function(pid, name, args)   -- /tg watch on|off: watch the driver on track in time trials
  local want = (args[3] or ""):lower()
  local off
  if want == "off" then off = true elseif want == "on" then off = false else off = not RPC.watchOff[name] end
  RPC.watchOff[name] = off or nil
  say(pid, off and "You won't be switched to watch the driver on track. /tg watch on to watch again."
    or "In time trials your camera follows the driver on track; you're back in your car when their run ends.")
  if off then MP.TriggerClientEvent(pid, "tg_watch_end", "") end
end

PLAYER_CMDS.soundtest = function(pid, _, args)
  local arg = (args[3] or ""):lower()
  local clips = (cfg.sounds or {}).clips or {}
  if #clips == 0 then say(pid, "No sound clips are configured."); return end
  if arg == "next" then
    MP.TriggerClientEvent(pid, "tg_sound", Util.JsonEncode({ clip = clips[1], test = true, cycle = true }))
    return
  end
  if arg ~= "" and not knownClip(arg) then say(pid, "No clip '" .. arg .. "'. /tg sounds list shows them."); return end
  local clip = arg ~= "" and arg or (knownClip("speed-and-power") and "speed-and-power" or clips[1])
  sendSound(pid, clip, true)   -- a test plays even when your sounds are off
end

function TG_onSoundReport(pid, data)
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  log(string.format("sound test by %s: %s", tostring(MP.GetPlayerName(pid)), tostring(data)))
  if t.method then
    say(pid, string.format("Played '%s' via %s. Not hearing it? /tg soundtest next tries the next way of playing sounds (%s of %s).",
      tostring(t.clip), tostring(t.method), tostring(t.index or "?"), tostring(t.count or "?")))
  else
    say(pid, "Your game couldn't play the sound: " .. tostring(t.err) .. ". /tg soundtest next tries another way.")
  end
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

ADMIN_CMDS.resume = function(pid)
  if game.phase ~= "paused" then say(pid, "There's no saved challenge waiting to resume."); return end
  local ph, n = game.resumePhase, game.stage
  local rerun = ph == "countdown" or ph == "event"
  for _, k in ipairs(Save.TIMERS) do
    local left = (game.savedTimers or {})[k]
    game[k] = left and (now() + left) or nil
  end
  game.savedTimers, game.resumePhase = nil, nil
  if rerun then   -- the interrupted event is run again from its start line
    game.phase, game.allHere, game.solo, game.closeAt, game.countdownEnd = "travel", false, nil, nil, nil
    game.towSlots = {}
    for _, p in pairs(game.players) do p.run = newRun(); p.leg.arrived = true; p.leg.via = #(curEvent().via or {}) + 1 end
    sayAll(string.format("Challenge resumed: %s is run again from the start - your cars are being brought to the line.", curEvent().name))
  else
    game.phase = ph
    if ph == "workshop" then game.warned = (game.workshopEnd or now()) - now() <= 60 end
    sayAll("Challenge resumed - your cars are being brought back where they were.")
  end
  for _, p in pairs(game.players) do
    if p.pid and p.carModel then
      if rerun and curEvent().type == "trailer" then p.trailerAfterRestore = true end
      for vid, data in pairs(MP.GetPlayerVehicles(p.pid) or {}) do   -- the plugin was reloaded but the car is still out: keep it
        if parseVehicle(data) == p.carModel then p.carVid = tonumber(vid) or vid; break end
      end
      local pos, dir = Save.placeFor(p, rerun)
      if not p.carVid then
        Save.restoreCar(p, true, pos, dir)
      else
        pushState(p)
        if rerun then MP.TriggerClientEvent(p.pid, "tg_tow", Util.JsonEncode({ kind = "restore", reset = false, pos = pos, dir = dir })) end
      end
    end
  end
  local away = {}
  for _, p in pairs(game.players) do if not p.pid then away[#away + 1] = p.name end end
  if #away > 0 then sayAll("Not back yet: " .. table.concat(away, ", ") .. " - their cars return when they rejoin.") end
  Save.write()
  pushAll()
end

-- Restart the event (0.9.20, Ryan): the running event (or its countdown) again from the start line - every car brought
-- back as it is, every run wiped (nothing's been scored yet), trailers and RPCs removed. Then Ready -> GO as usual.
-- everyone back at the start line of the current stage's event, as they are, runs wiped: travel with everyone arrived
-- (then I'm ready and GO) - Restart event, and Rerun after its results
function Course.backToStart(e)
  cleanupEventVehicles()
  game.phase, game.allHere, game.solo, game.closeAt, game.countdownEnd = "travel", false, nil, nil, nil
  game.towSlots, game.trapRecord = {}, nil
  for _, p in pairs(game.players) do
    p.run = newRun(); p.leg.arrived = true; p.leg.via = #(e.via or {}) + 1
    p.trailerAsked = nil
    if p.pid and p.carVid then
      local pos, dir = towDestination(p)
      p.towPending = now()
      if e.type == "trailer" and cfg.defaults.readyToGo == false then p.trailerAfterRestore = true end
      MP.TriggerClientEvent(p.pid, "tg_tow", Util.JsonEncode({ kind = "restore", reset = false, pos = pos, dir = dir }))
    end
  end
end
ADMIN_CMDS.restartevent = function(pid)
  if game.phase ~= "event" and game.phase ~= "countdown" then
    if Course.canRerun() then say(pid, "That event is over - Rerun it (/tg rerunevent) to undo its results and run it again.")
    else say(pid, "There's no event running to restart.") end
    return
  end
  local e = curEvent()
  Course.backToStart(e)
  sayAll(string.format("%s is restarted - your cars are going back to the start line as they are.%s", e.name,
    cfg.defaults.readyToGo ~= false and " Then I'm ready and GO, as before." or ""))
  bigAll("Restart: " .. e.name)
  pushAll()
end

-- Rerun (0.9.35, Ryan): the event that has just finished, again - its results taken back (prize money, points, a win,
-- the Turbo prizes it gave, the head starts / penalty cards it used), a workshop that followed it cancelled (its
-- inspection dropped; what was spent there stays spent), and everyone back at its start line as they are.
-- Only until the next event starts (on the way to it, in the workshop or on the final leg).
function Course.canRerun()
  local u = game.rerun
  if not u or not game.events or not game.events[u.stage] then return nil end
  local ph = game.phase
  if ph == "travel" and game.stage == u.stage + 1 then return u end
  if (ph == "workshop" or ph == "finale") and game.stage == u.stage then return u end
  return nil
end
ADMIN_CMDS.rerunevent = function(pid)
  local u = Course.canRerun()
  if not u then
    say(pid, (game.phase == "event" or game.phase == "countdown") and "An event is running - Restart event runs it again."
      or "There's no finished event to rerun (only until the next one starts)."); return
  end
  local used = {}
  for _, p in pairs(game.players) do
    local r = u.players[p.login or p.name]
    if r then
      p.cash, p.points, p.wins = p.cash - (r.prize or 0), p.points - (r.points or 0), p.wins - (r.win or 0)
      for _, id in ipairs(r.won or {}) do
        local gone = false
        for k = #(p.glovebox or {}), 1, -1 do
          if p.glovebox[k] == id then table.remove(p.glovebox, k); gone = true; break end
        end
        if not gone then used[#used + 1] = p.name end
      end
      p.effects = p.effects or {}
      for k, v in pairs(r.effects or {}) do p.effects[k] = v end
    end
    if p.results then p.results[u.stage] = nil end
    if (game.workshopNo or 0) > u.workshopNo then   -- (the workshop after it: as if it hadn't opened)
      local keep = {}
      for _, i in ipairs(p.inspections or {}) do
        local no = tonumber(tostring(i.where):match("^Workshop (%d+)$"))
        if not (no and no > u.workshopNo) then keep[#keep + 1] = i end
      end
      p.inspections, p.wsInspectedAt, p.inShop = keep, nil, false
    end
  end
  if (game.workshopNo or 0) > u.workshopNo then game.workshopNo, game.wsFirst, game.workshopEnd = u.workshopNo, nil, nil end
  game.rerun = nil
  game.stage, game.phaseStart, game.arrivals = u.stage, now(), 0
  local e = curEvent()
  game.phase = "travel"
  Course.backToStart(e)
  sayAll(string.format("%s will be run again - its results are taken back (prize money, points%s), and your cars are " ..
    "going back to its start line as they are.%s", e.name, Score.turboOn() and ", Turbo prizes" or "",
    cfg.defaults.readyToGo ~= false and " Then I'm ready and GO." or ""))
  if #used > 0 then sayAll("(Prizes already used from those results stay used: " .. table.concat(used, ", ") .. ".)") end
  bigAll("Rerun: " .. e.name)
  if Save.write then Save.write() end
  pushAll()
end

-- A free respawn (0.9.20, Ryan): an admin fixes a player's car where it stands - no cost, no points lost, no DSQ.
-- A lost car comes back the tow truck's way, also free.
ADMIN_CMDS.freerespawn = function(pid, _, args)
  local p = Score.findPlayer(table.concat(args, " ", 3))
  if not p then say(pid, "Usage: /tg freerespawn <player name>"); return end
  if not p.pid then say(pid, p.name .. " isn't connected."); return end
  if not p.carVid then
    if not p.carModel then say(pid, p.name .. " hasn't bought a car yet."); return end
    p.freeTow = true
    MP.TriggerClientEvent(p.pid, "tg_respawn", Util.JsonEncode({ spawn = true, model = p.carModel,
      config = p.carConfig and ("vehicles/" .. p.carModel .. "/" .. p.carConfig .. ".pc") or nil }))
  else
    p.respawnPending, p.damage = now(), 0
    MP.TriggerClientEvent(p.pid, "tg_respawn", Util.JsonEncode({ reset = true }))
  end
  sayAll(string.format("The producers give %s a free respawn.", p.name))
  pushState(p)
end

-- Bring to me (0.9.22, Ryan): a player's car - as it is, no repair - to 50 m in front of the admin's car, facing the
-- same way. The direction is the admin's game's own (tg_activeveh); the ground height is found by the player's game.
ADMIN_CMDS.bring = function(pid, _, args)
  local p = Score.findPlayer(table.concat(args, " ", 3))
  if not p then say(pid, "Usage: /tg bring <player name>"); return end
  if not (p.pid and p.carVid) then say(pid, p.name .. " has no car out to bring."); return end
  if p.pid == pid then say(pid, "That's you."); return end
  local pos, _, dir = adminPose(pid)
  if not (pos and dir) then say(pid, "Get in your car (and move it a little) first - the server needs to know which way you face."); return end
  local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
  local dist = tonumber(cfg.defaults.bringDistance) or 50
  local to = { x = pos.x + dir.x / len * dist, y = pos.y + dir.y / len * dist, z = pos.z + 0.5 }
  if p.rpc then RPC.remove(p) end   -- (their own car comes, not the reasonably priced one)
  p.towPending = now()   -- (the move isn't a reset to fine)
  p.broughtAt = { phase = game.phase, stage = game.stage, ws = game.workshopNo }   -- (no arrival bonus / prize for it)
  MP.TriggerClientEvent(p.pid, "tg_tow", Util.JsonEncode({ kind = "bring", reset = false, pos = to, ground = true,
    dir = { x = dir.x / len, y = dir.y / len, z = 0 } }))
  say(p.pid, "An admin brought your car to them.")
  say(pid, string.format("Bringing %s's car to %d m in front of you.", p.name, math.floor(dist)))
end

ADMIN_CMDS.setname = function(pid, _, args)   -- /tg setname <player> <new name> (empty: back to their BeamMP name)
  local p = Score.findPlayer(args[3] or "")
  local login = p and (p.login or p.name)
  if not login then   -- (not in the challenge: anyone connected)
    for _, n in pairs(MP.GetPlayers() or {}) do if n:lower() == tostring(args[3] or ""):lower() then login = n end end
  end
  if not login then say(pid, "Usage: /tg setname <player> <new name> - who? (their current name, or the start of it)"); return end
  Score.setAlias(pid, login, table.concat(args, " ", 4))
end

-- /tg mode <freerepair|nofaults|noquirks|turbo> [on|off] (admin): a game mode for the next challenge. Free Repair can
-- change any time; No faults / No quirks only before /tg start (cars and their problems are drawn at the dealership).
Course.MODES = { freerepair = "freeRepair", nofaults = "noFaults", noquirks = "noQuirks", turbo = "turbo" }
Course.MODE_NAMES = { freeRepair = "Free Repair", noFaults = "No faults", noQuirks = "No quirks", turbo = "Turbo Mode" }
ADMIN_CMDS.mode = function(pid, _, args)
  local key = Course.MODES[(args[3] or ""):lower()]
  if not key then say(pid, "Usage: /tg mode <freerepair|nofaults|noquirks|turbo> [on|off]"); return end
  local m = cfg.modes or {}
  cfg.modes = m
  local want = (args[4] or ""):lower()
  local on
  if want == "on" then on = true elseif want == "off" then on = false else on = not m[key] end
  if (key == "noFaults" or key == "noQuirks") and game.phase ~= "idle" and (m[key] or false) ~= on then
    say(pid, Course.MODE_NAMES[key] .. " can only be changed before the challenge starts (the cars' problems are already drawn)."); return
  end
  m[key] = on
  saveConfig()
  sayAll(string.format("Game mode: %s is %s.", Course.MODE_NAMES[key], on and "ON" or "off"))
  pushAll()
end

ADMIN_CMDS.discard = function(pid)
  if game.phase ~= "paused" then say(pid, "There's no saved challenge waiting."); return end
  game = { phase = "idle", stage = 0, players = {} }
  Save.write()
  pushIdle(-1)
  sayAll("The saved challenge was discarded.")
end

ADMIN_CMDS.start = function(pid, _, args)
  if game.phase == "paused" then say(pid, "A saved challenge is waiting: /tg resume to carry on, or /tg discard to drop it."); return end
  if game.phase ~= "idle" then say(pid, "Already running - /tg stop first."); return end
  startGame(pid, args[3] == "force")
end

ADMIN_CMDS.play = function(pid, _, args)
  local clip = (args[3] or ""):lower()
  if not knownClip(clip) then say(pid, "Usage: /tg play <clip> - /tg sounds list shows them."); return end
  for qpid, qname in pairs(MP.GetPlayers() or {}) do
    if not soundsOff[qname] then sendSound(qpid, clip) end
  end
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

-- a player typed by an admin: the exact name, else ignoring case, else the only name that starts with it
Score.findPlayer = function(text)   -- (by the name everyone sees or the BeamMP name)
  if game.players[text] then return game.players[text] end
  local low, hit, n = tostring(text):lower(), nil, 0
  if low == "" then return nil end
  for name, p in pairs(game.players) do if name:lower() == low or tostring(p.name):lower() == low then return p end end
  for name, p in pairs(game.players) do
    if name:lower():sub(1, #low) == low or tostring(p.name):lower():sub(1, #low) == low then hit, n = p, n + 1 end
  end
  if n == 1 then return hit end
  return nil
end

-- Aliases (0.9.25, Ryan: BeamMP gives everyone a random guest name): the name everyone sees in chat, the menu and the
-- results. Kept in config.json by BeamMP name (cfg.aliases), so it's back when that name rejoins. Empty = none.
function Score.setAlias(pid, login, alias)
  alias = tostring(alias or ""):gsub("[%c\"]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if #alias > 20 then say(pid, "Keep it to 20 characters."); return end
  local low = alias:lower()
  for name, q in pairs(game.players) do
    if name ~= login and alias ~= "" and (name:lower() == low or tostring(q.name):lower() == low) then
      say(pid, "Someone's already called " .. alias .. "."); return
    end
  end
  for other, a in pairs(cfg.aliases or {}) do
    if other ~= login and alias ~= "" and tostring(a):lower() == low then say(pid, "Someone's already called " .. alias .. "."); return end
  end
  cfg.aliases = cfg.aliases or {}
  cfg.aliases[login] = alias ~= "" and alias or nil
  markDirty()
  local p = game.players[login]
  local was = p and p.name or login
  local now = alias ~= "" and alias or login
  if p then p.name = now end
  if was ~= now then sayAll(string.format("%s is now known as %s.", was, now)) else say(pid, "Your name is " .. now .. ".") end
  pushAll()
end

-- producer points: /tg award <driver> <+/-points> [reason]
ADMIN_CMDS.award = function(pid, _, args)
  if game.phase == "idle" then say(pid, "No challenge running."); return end
  local k
  for i = 4, #args do if tonumber(args[i]) then k = i; break end end
  local who = k and table.concat(args, " ", 3, k - 1) or ""
  local p = Score.findPlayer(who)
  if not (k and p) then say(pid, "Usage: /tg award <driver> <points, e.g. 2 or -1.5> [reason]"); return end
  local n = tonumber(args[k])
  local reason = table.concat(args, " ", k + 1)
  p.points = p.points + n
  p.awardPoints = (p.awardPoints or 0) + n
  p.awards = p.awards or {}
  p.awards[#p.awards + 1] = { points = n, reason = reason }
  sayAll(string.format("The producers %s %s %s%s.", n >= 0 and "award" or "dock", p.name, pts(math.abs(n)),
    reason ~= "" and (": " .. reason) or ""))
  if game.phase == "results" then game.summary = buildSummary(sortedPlayers()) end
  pushState(p)
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
  local p = Score.findPlayer(target)
  if #args < 4 or not (p and amount) then say(pid, "Usage: /tg give <player name> <amount>"); return end
  amount = math.floor(amount)
  p.cash = p.cash + amount
  sayAll(amount < 0 and string.format("The producers take %s from %s.", money(-amount), p.name)
    or string.format("The producers give %s %s.", p.name, money(amount)))
  pushState(p)
end

finishImport = function()
  local imp = pendingImport
  pendingImport = nil
  if not imp then return end
  for m in pairs(imp.waiting) do imp.failed[#imp.failed + 1] = m .. " (no reply)" end
  if imp.all and not imp.done then imp.failed[#imp.failed + 1] = "the rest (your game stopped replying)" end
  for i, f in ipairs(imp.failed) do
    if i <= 8 then say(imp.pid, "  Couldn't import " .. f) end
  end
  if #imp.failed > 8 then say(imp.pid, string.format("  ...and %d more", #imp.failed - 8)) end
  if imp.imported > 0 then
    cfg.dealer.useGamePrices = true
    cfg.dealer.catalogue = "import"   -- from now on config.json keeps this server's own cars
    if imp.all then cfg.dealer.gamePrices = imp.fresh end   -- every car in this game, nothing left over
    if imp.all then cfg.dealer.importedAll = true end
    local _, estimated = Class.tidyImport()
    saveConfig()
    say(imp.pid, string.format("Imported %s%s. Game prices are ON and saved to config.json.",
      plural(imp.imported, "trim price"), imp.all and string.format(" from %s", plural(imp.models or 0, "model")) or ""))
    if (imp.props or 0) > 0 then say(imp.pid, string.format("Skipped %s that aren't cars (props, traffic, trailers).", plural(imp.props, "trim"))) end
    if imp.skipped > 0 then
      say(imp.pid, string.format("%s had no game price: %d priced by estimate from similar cars. Check or change them in the " ..
        "Admin tab's Cars without a game price (or /tg setprice list).", plural(imp.skipped, "trim"), estimated))
    end
  else
    say(imp.pid, "Nothing was imported - prices unchanged.")
  end
end

-- client -> server: { model, modelName, configs = { {config, name, price}, ... } | nil, err }
function TG_onImportReply(pid, data)
  local imp = pendingImport
  if not imp or imp.pid ~= pid then return end
  local ok, t = pcall(Util.JsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  if t.done then imp.done = true; finishImport(); return end   -- (importing every car: the client says when it's done)
  if not t.model or not (imp.all or imp.waiting[t.model]) then return end
  imp.waiting[t.model] = nil
  imp.left = imp.left - 1
  imp.models = (imp.models or 0) + 1
  if type(t.configs) ~= "table" or #t.configs == 0 then
    imp.failed[#imp.failed + 1] = t.model .. (t.err and (" (" .. tostring(t.err) .. ")") or " (not found in your game)")
  else
    local prices, n, under, cheapest = {}, 0, 0, nil
    for _, c in ipairs(t.configs) do
      local price = tonumber(c.price)
      if Class.notACar(c) then   -- props, trailers: never sold
        imp.props = (imp.props or 0) + 1
      elseif price and c.config then
        price = math.floor(price + 0.5)
        prices[c.config] = { name = c.name or c.config, price = price, attrs = type(c.attrs) == "table" and c.attrs or nil }
        n = n + 1
        if price <= cfg.economy.startingCash then under = under + 1 end
        cheapest = math.min(cheapest or price, price)
      elseif c.config then   -- no game value (mostly mod cars): kept, so it can be given a price (/tg setprice)
        prices[c.config] = { name = c.name or c.config, attrs = type(c.attrs) == "table" and c.attrs or nil, noPrice = true }
        imp.skipped = imp.skipped + 1
      end
    end
    cfg.dealer.gamePrices = cfg.dealer.gamePrices or {}
    local dest = imp.all and imp.fresh or cfg.dealer.gamePrices   -- a full import replaces the whole list at the end
    dest[t.model] = next(prices) and prices or nil
    imp.imported = imp.imported + n
    cfg.dealer.modelNames = cfg.dealer.modelNames or {}
    if t.modelName then cfg.dealer.modelNames[t.model] = t.modelName end
    local listed = modelListed(t.model)
    if not listed and not imp.all then   -- named on the command line: add it to the dealer list
      cfg.dealer.cars[#cfg.dealer.cars + 1] = { model = t.model, name = t.modelName or t.model, price = cheapest or 0 }
    elseif listed and t.modelName then
      listed.name = t.modelName
    end
    if not imp.all then
      say(pid, string.format("  %s: %s, %d within the %s budget", t.modelName or t.model, plural(n, "trim"), under, money(cfg.economy.startingCash)))
    end
  end
  if not imp.all and imp.left <= 0 then finishImport() end
end

ADMIN_CMDS.importprices = function(pid, _, args)
  if pendingImport then say(pid, "An import is already running."); return end
  if args[3] and args[3]:lower() == "builtin" then   -- forget this server's import, back to cars.json
    local was, wasNames = cfg.dealer.gamePrices, cfg.dealer.modelNames
    cfg.dealer.catalogue = nil
    local ok, n = Class.loadBuiltin()
    if not ok then cfg.dealer.gamePrices, cfg.dealer.modelNames = was, wasNames; say(pid, "Couldn't: " .. tostring(n) .. "."); return end
    Class.tidyImport()
    saveConfig()
    say(pid, string.format("Back to the built-in car catalogue (%s). Your classes and /tg setprice prices are kept.", plural(n, "trim")))
    return
  end
  local models = {}
  if #args >= 3 and args[3]:lower() ~= "listed" then
    for i = 3, #args do models[#models + 1] = args[i]:lower() end
  elseif args[3] and args[3]:lower() == "listed" then
    for _, c in ipairs(listedModels()) do models[#models + 1] = c.model end
  end
  if #models == 0 then   -- no names: every car in the game (mods too), with the attributes car classes filter on
    pendingImport = { pid = pid, all = true, fresh = {}, waiting = {}, left = 0, started = now(), imported = 0, skipped = 0, failed = {} }
    say(pid, "Reading every car in your game (prices and details for car classes) - this can take a little while...")
    MP.TriggerClientEvent(pid, "tg_import", Util.JsonEncode({ all = true }))
    return
  end
  pendingImport = { pid = pid, waiting = {}, left = #models, started = now(), imported = 0, skipped = 0, failed = {} }
  for _, m in ipairs(models) do pendingImport.waiting[m] = true end
  say(pid, string.format("Reading prices for %d model%s from your game...", #models, #models == 1 and "" or "s"))
  MP.TriggerClientEvent(pid, "tg_import", Util.JsonEncode({ models = models }))
end

-- /tg class ... - car classes (see DEFAULT_CONFIG.dealer.classes) -------------------------------------------
Class.view = {}   -- admin name -> the class they're editing in the window
function Class.parseField(word)
  word = tostring(word or ""):lower()
  if Class.FIELDS[word] then return Class.FIELDS[word][1], Class.FIELDS[word][2] end
  for _, f in pairs(Class.FIELDS) do if f[1]:lower() == word then return f[1], f[2] end end
  return nil
end
function Class.fieldValues(field)   -- the values a list field takes across the imported cars (hints)
  local seen, out = {}, {}
  for _, trims in pairs(cfg.dealer.gamePrices or {}) do
    for _, e in pairs(trims) do
      local v = type(e) == "table" and e.attrs and e.attrs[field]
      if type(v) == "string" and v ~= "" and not seen[v] then seen[v] = true; out[#out + 1] = v end
    end
  end
  table.sort(out)
  return out
end
function Class.count(cls)
  local trims = classTrims(cls)
  if #trims == 0 then return "no cars" end
  return string.format("%s, %s to %s", plural(#trims, "trim"), money(trims[1].price), money(trims[#trims].price))
end
function Class.removeFrom(list, key)
  for i = #list, 1, -1 do if list[i] == key then table.remove(list, i) end end
end

ADMIN_CMDS.class = function(pid, name, args)
  cfg.dealer.classes = cfg.dealer.classes or {}
  local classes = cfg.dealer.classes
  local sub, cname = (args[3] or ""):lower(), args[4]
  local function need(cls)
    if not cls then say(pid, "No class '" .. tostring(cname) .. "'. /tg class list"); return false end
    return true
  end
  local function changed(cls)
    saveConfig()
    say(pid, string.format("%s: %s - %s.", cname, classSummary(cls), Class.count(cls)))
  end
  if sub == "" or sub == "list" then
    local names = {}
    for n in pairs(classes) do names[#names + 1] = n end
    table.sort(names)
    if #names == 0 then say(pid, "No car classes yet - /tg class new <name> (one word), then /tg class rule <name> <field> <value>."); end
    for _, n in ipairs(names) do
      say(pid, string.format("%s%s: %s - %s", n, n == chosenClass and " (in use)" or "", classSummary(classes[n]), Class.count(classes[n])))
    end
    say(pid, "Next challenge: " .. (chosenClass or Class.noneText()) .. ". /tg class use <name>|none - ready-made ones: /tg class preset")
    return
  elseif sub == "use" then
    if game.phase ~= "idle" then say(pid, "Pick the class before /tg start - not during a challenge."); return end
    if not cname or cname:lower() == "none" then chosenClass = nil; say(pid, "No class: " .. Class.noneText() .. "."); return end
    if not need(classes[cname]) then return end
    chosenClass = cname
    say(pid, string.format("Next challenge's cars: %s - %s (%s).", cname, classSummary(classes[cname]), Class.count(classes[cname])))
    if not next(cfg.dealer.gamePrices or {}) then say(pid, "Nothing's been imported yet: run /tg importprices first.") end
    return
  elseif sub == "preset" then   -- /tg class preset [key [name]]
    local pr = cname and Class.preset(cname:lower())
    if not pr then
      say(pid, "Ready-made classes (/tg class preset <name>):")
      for _, x in ipairs(Class.PRESETS) do
        say(pid, string.format("  %s - %s (%s)", x.key, x.title, Class.count({ rules = x.rules })))
      end
      return
    end
    local nm = args[5] or pr.key
    if not nm:match("^[%w_%-]+$") then say(pid, "A class name is one word (letters, digits, - and _)."); return end
    if classes[nm] then say(pid, "There's already a class called " .. nm .. " - /tg class use " .. nm .. " (or delete it first)."); return end
    classes[nm] = { rules = deepcopy(pr.rules), include = {}, exclude = {}, prices = {}, multiplier = 1 }
    Class.view[name] = nm
    saveConfig()
    say(pid, string.format("Made class %s (%s): %s - %s. /tg class use %s for the next challenge.", nm, pr.title,
      classSummary(classes[nm]), Class.count(classes[nm]), nm))
    return
  elseif sub == "values" then   -- /tg class values <field>
    local field, kind = Class.parseField(cname)
    if not field then say(pid, "Fields: " .. table.concat(Class.ORDER, ", ")); return end
    if kind == "range" then say(pid, field .. " is a range: e.g. /tg class rule <name> " .. cname .. " 1985-1999 (or 1985- / -1999)"); return end
    if kind == "base" then say(pid, "Trims: base - each model's cheapest factory trim only."); return end
    local vals = Class.fieldValues(field)
    say(pid, field .. ": " .. (#vals > 0 and table.concat(vals, ", ") or "nothing imported yet (/tg importprices)"))
    return
  end
  if not cname then say(pid, "Usage: /tg class list|use|new|delete|show|rule|unrule|include|exclude|clear|price|multiplier|values"); return end
  local cls = classes[cname]

  if sub == "new" then
    if not cname:match("^[%w_%-]+$") then say(pid, "A class name is one word (letters, digits, - and _)."); return end
    if cls then say(pid, "There's already a class called " .. cname .. "."); return end
    classes[cname] = { rules = {}, include = {}, exclude = {}, prices = {}, multiplier = 1 }
    if (args[5] or ""):lower() == "base" then   -- every car, base trims only (props and trailers left out)
      classes[cname].rules = { { field = "Trims", base = true }, { field = "Type", values = { "Car", "Truck" } } }
    end
    Class.view[name] = cname
    saveConfig()
    if #classes[cname].rules > 0 then
      say(pid, string.format("Made class %s: %s - %s.", cname, classSummary(classes[cname]), Class.count(classes[cname])))
    else
      say(pid, "Made class " .. cname .. ". Add rules: /tg class rule " .. cname .. " country Japan | years 1985-1999 | body Hatchback | trims base ...")
    end
  elseif sub == "delete" then
    if not need(cls) then return end
    if cname == chosenClass and game.phase ~= "idle" then say(pid, "That class is in use - after the challenge."); return end
    classes[cname] = nil
    if chosenClass == cname then chosenClass = nil end
    saveConfig()
    say(pid, "Deleted class " .. cname .. ".")
  elseif sub == "show" or sub == "edit" then
    if not need(cls) then return end
    Class.view[name] = cname
    say(pid, string.format("%s: %s - %s.", cname, classSummary(cls), Class.count(cls)))
    if sub == "show" then
      for i, t in ipairs(classTrims(cls)) do
        if i > 12 then say(pid, "  ... (the Admin tab lists them all)"); break end
        say(pid, string.format("  %s  %s  [%s/%s]", money(t.price), t.name, t.model, t.config))
      end
    end
  elseif sub == "rule" then   -- /tg class rule <name> <field> <values, comma separated | range>
    if not need(cls) then return end
    local field, kind = Class.parseField(args[5])
    if not field then say(pid, "Fields: " .. table.concat(Class.ORDER, ", ")); return end
    local text = table.concat(args, " ", 6)
    local rule = { field = field }
    if kind == "base" then
      if text:lower() ~= "base" then say(pid, "Usage: /tg class rule " .. cname .. " trims base  (each model's cheapest factory trim)"); return end
      rule.base = true
    elseif kind == "range" then
      local lo, hi
      if text:find("-", 1, true) then lo, hi = text:match("^%s*([%d%.]*)%s*%-%s*([%d%.]*)%s*$") else lo, hi = text, text end
      rule.min, rule.max = tonumber(lo), tonumber(hi)
      if not (rule.min or rule.max) then say(pid, "Give a range, e.g. 1985-1999, 1985- or -1999."); return end
    else
      rule.values = {}
      for raw in (text .. ","):gmatch("([^,]*),") do
        local v = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if v ~= "" then rule.values[#rule.values + 1] = v end
      end
      if #rule.values == 0 then say(pid, "Give one or more values, comma separated. /tg class values " .. args[5] .. " lists them."); return end
    end
    cls.rules = cls.rules or {}
    for i = #cls.rules, 1, -1 do if cls.rules[i].field == field then table.remove(cls.rules, i) end end
    cls.rules[#cls.rules + 1] = rule
    changed(cls)
  elseif sub == "unrule" then
    if not need(cls) then return end
    local field = Class.parseField(args[5])
    for i = #(cls.rules or {}), 1, -1 do if cls.rules[i].field == field then table.remove(cls.rules, i) end end
    changed(cls)
  elseif sub == "include" or sub == "exclude" or sub == "clear" then   -- <model> or <model/config>
    if not need(cls) then return end
    local key = (args[5] or ""):lower():gsub("^([^/]+)/", "%1/")
    if args[5] and args[5]:find("/") then key = args[5]:match("^([^/]+)"):lower() .. "/" .. args[5]:match("/(.+)$") end
    if key == "" then say(pid, "Usage: /tg class " .. sub .. " <name> <model> or <model/config>"); return end
    cls.include, cls.exclude, cls.prices = cls.include or {}, cls.exclude or {}, cls.prices or {}
    Class.removeFrom(cls.include, key); Class.removeFrom(cls.exclude, key)
    if sub == "include" then cls.include[#cls.include + 1] = key
    elseif sub == "exclude" then cls.exclude[#cls.exclude + 1] = key
    else cls.prices[key] = nil end
    changed(cls)
  elseif sub == "price" then   -- <model/config> <amount|off>
    if not need(cls) then return end
    local key, amount = args[5], (args[6] or ""):lower()
    if not (key and key:find("/")) then say(pid, "Usage: /tg class price <name> <model/config> <amount|off>"); return end
    cls.prices = cls.prices or {}
    if amount == "off" then cls.prices[key] = nil
    elseif tonumber(amount) and tonumber(amount) >= 0 then cls.prices[key] = math.floor(tonumber(amount))
    else say(pid, "Give an amount, or off."); return end
    changed(cls)
  elseif sub == "multiplier" then
    if not need(cls) then return end
    local x = tonumber(args[5])
    if not x or x <= 0 then say(pid, "Usage: /tg class multiplier <name> <e.g. 0.8>"); return end
    cls.multiplier = x
    changed(cls)
  else
    say(pid, "Usage: /tg class list|use|new|delete|show|rule|unrule|include|exclude|clear|price|multiplier|values")
  end
end

-- dealership-wide prices: /tg setprice <model/config> <amount|off> ; /tg setprice list (the trims with no price)
ADMIN_CMDS.setprice = function(pid, _, args)
  cfg.dealer.prices = cfg.dealer.prices or {}
  local key, amount = args[3], (args[4] or ""):lower()
  if not key or key:lower() == "list" then
    local list = {}
    for model, trims in pairs(cfg.dealer.gamePrices or {}) do
      for config, e in pairs(trims) do
        if type(e) == "table" and not tonumber(e.price) then
          local k = model .. "/" .. config
          list[#list + 1] = string.format("%s [%s]%s", e.name or k, k, cfg.dealer.prices[k] and (" - " .. money(cfg.dealer.prices[k]))
            or (tonumber(e.est) and (" - est. " .. money(e.est))) or " - no price")
        end
      end
    end
    table.sort(list)
    if #list == 0 then say(pid, "Every imported trim has a game price."); return end
    say(pid, plural(#list, "trim") .. " without a game price:")
    for i, l in ipairs(list) do if i <= 15 then say(pid, "  " .. l) end end
    if #list > 15 then say(pid, "  ... (the Admin tab lists them all)") end
    return
  end
  local model, config = key:match("^([^/]+)/(.+)$")
  if not model then say(pid, "Usage: /tg setprice <model/config> <amount|off>  (e.g. covet/base_M 4000)"); return end
  model = model:lower()
  key = model .. "/" .. config
  local e = ((cfg.dealer.gamePrices or {})[model] or {})[config]
  if not e then say(pid, "No imported trim " .. key .. " - /tg importprices first, or check the name."); return end
  if amount == "off" then cfg.dealer.prices[key] = nil
  elseif tonumber(amount) and tonumber(amount) >= 0 then cfg.dealer.prices[key] = math.floor(tonumber(amount))
  else say(pid, "Give an amount, or off."); return end
  saveConfig()
  Class.presetCounts = nil
  local nowPrice = trimPrice(model, config, e)
  local how = ""
  if not cfg.dealer.prices[key] then how = tonumber(e.price) and " (its game price)" or (tonumber(e.est) and " (estimated from similar cars)" or "") end
  say(pid, string.format("%s now costs %s%s.", e.name or key, nowPrice and money(nowPrice) or "nothing (no price - it can't be sold)", how))
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
  local p = Score.findPlayer(target)
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
  withPos(pid, function(pos)
    local _, _, dir = adminPose(pid)   -- (the way your car points: drivers get an arrow to line up)
    e.start = pos
    e.startDir = dir and { x = math.floor(dir.x * 1000 + 0.5) / 1000, y = math.floor(dir.y * 1000 + 0.5) / 1000 } or nil
    markDirty()
    say(pid, label .. " start set " .. fmtPos(pos) .. (dir and ", facing the way your car points" or
      " (the way you face isn't known yet - it faces the first checkpoint)") .. " (/tg save)")
  end)
end
ADMIN_CMDS.addcp = function(pid, _, args)   -- /tg addcp <n> [5|10|20|line]: the checkpoint's size (default: defaults.cpRadius)
  local e, label = eventArg(pid, args[3]); if not e then return end
  local size = (args[4] or ""):lower()
  if size ~= "" and size ~= "line" and not tonumber(size) then say(pid, "Usage: /tg addcp <event> [5|10|20|line]"); return end
  withPos(pid, function(pos)
    e.checkpoints = e.checkpoints or {}
    local cp = { x = pos.x, y = pos.y, z = pos.z }
    local what = "a " .. tostring(e.cpRadius or cfg.defaults.cpRadius) .. " m checkpoint"
    if tonumber(size) then
      cp.r = math.max(1, math.min(50, tonumber(size)))
      what = "a " .. tostring(cp.r) .. " m checkpoint"
    elseif size == "line" then   -- across the way from the point before it (the last checkpoint, or the start)
      local prev = v3(e.checkpoints[#e.checkpoints] or e.start)
      local dx, dy = prev and (pos.x - prev.x) or 0, prev and (pos.y - prev.y) or 0
      local len = math.sqrt(dx * dx + dy * dy)
      if len < 3 then say(pid, "A line goes across the way from the point before it - set the start (or the checkpoint before) first, a bit back."); return end
      local half = (tonumber(cfg.defaults.lineWidth) or 20) / 2
      local rx, ry = -dy / len * half, dx / len * half
      cp.line = { ax = pos.x + rx, ay = pos.y + ry, bx = pos.x - rx, by = pos.y - ry }
      what = string.format("a %d m line", math.floor(half * 2))
    end
    e.checkpoints[#e.checkpoints + 1] = cp
    markDirty()
    say(pid, string.format("%s checkpoint %d set %s (%s) - the last one is the finish (/tg save)", label, #e.checkpoints, fmtPos(pos), what))
    local why = Course.stacked(e)
    if why then say(pid, "Careful: " .. why .. ". Positions come from the car you're in - /tg undocp " .. tostring(args[3]) .. " to take it back.") end
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
  if e.type == "rpc" then say(pid, label .. " is always time trial mode - there's one reasonably priced car on track at a time."); return end
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
    (e.type ~= "circuit" and e.type ~= "rpc") and " - note: laps only count on a circuit race or a reasonably priced car" or ""))
end

local function placeBay(pid, e, label, replace)
  local pos, yaw, dir = adminPose(pid)
  if not pos then say(pid, "Park your car in the bay, facing the way it should face, first."); return end
  local bay = { x = pos.x, y = pos.y, z = pos.z, yaw = yaw and math.floor(yaw * 10 + 0.5) / 10 or nil }
  if dir then   -- (what the box and its arrow are drawn from)
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    bay.dx, bay.dy = math.floor(dir.x / len * 1000 + 0.5) / 1000, math.floor(dir.y / len * 1000 + 0.5) / 1000
  end
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
-- /tg setrpc <event> <model> [config] | mine | default: which car is the reasonably priced car
ADMIN_CMDS.setrpc = function(pid, _, args)
  local e, label = eventArg(pid, args[3]); if not e then return end
  local m = args[4]
  if not m then say(pid, "Usage: /tg setrpc <event> <model> [config] | mine (the car you're in) | default"); return end
  if m:lower() == "default" then
    e.rpcModel, e.rpcConfig = nil, nil
  elseif m:lower() == "mine" then
    -- the car you're IN (your game reports it); before 0.9.15 the first car the server listed - with traffic mode
    -- on, that could be one of your parked traffic cars (Ryan: an RPC with no controls)
    local p = playerByPid(pid)
    local vehs = MP.GetPlayerVehicles(pid) or {}
    local data = activeVeh[pid] and vehs[activeVeh[pid]]
    if not data and p and p.carVid then data = vehs[p.carVid] end
    if not data then   -- (not reported yet: a car of yours that can be driven)
      for _, d in pairs(vehs) do if RPC.drivable(parseVehicle(d)) then data = d; break end end
    end
    local model, config = parseVehicle(data)
    if not model then say(pid, "Get in the car you want first (spawn it from the vehicle menu)."); return end
    if not RPC.drivable(model, config) then
      say(pid, string.format("%s / %s is a parked traffic car - it can't be driven. Get in a normal car first.", model, tostring(config)))
      return
    end
    e.rpcModel, e.rpcConfig = model, config
  else
    if not RPC.drivable(m, args[5]) then
      say(pid, string.format("%s / %s is a parked traffic car - it can't be driven. Pick a normal car.", m, tostring(args[5])))
      return
    end
    e.rpcModel, e.rpcConfig = m, args[5]
  end
  markDirty()
  say(pid, string.format("%s: the reasonably priced car is %s%s (/tg course save)%s", label, RPC.label(e),
    e.rpcModel and "" or " (the default)", e.type ~= "rpc" and (" - note: it's only used by a Star in a reasonably priced car event (/tg settype " .. tostring(args[3]) .. " rpc)") or ""))
end
-- Test event (course builder): one event on its own, from its countdown - everyone in a car takes part in the car
-- they're in; results, then back to normal. No money, workshop, finale, reset fines or saving. /tg testevent <n> | stop
ADMIN_CMDS.testevent = function(pid, _, args)
  local sub = (args[3] or ""):lower()
  if sub == "stop" then
    if not game.test then say(pid, "No test event is running."); return end
    cleanupEventVehicles()
    game = { phase = "idle", stage = 0, players = {} }
    pushIdle(-1)
    sayAll("Test event stopped - back to normal.")
    return
  end
  if game.phase ~= "idle" then say(pid, "Test events only run when no challenge is going (/tg stop first)."); return end
  local e, label = eventArg(pid, args[3]); if not e then return end
  local errs = {}
  for _, er in ipairs(validate({ e }, { pos = { x = 0, y = 0, z = 0 } })) do errs[#errs + 1] = (er:gsub("^Event 1", label)) end
  if #errs > 0 then say(pid, "Can't test " .. label .. " yet: " .. table.concat(errs, "; ")); return end
  local players, n = {}, 0
  for qpid, qname in pairs(MP.GetPlayers() or {}) do
    local vehs = MP.GetPlayerVehicles(qpid) or {}
    local vid = activeVeh[qpid]
    if not (vid and vehs[vid] ~= nil) then
      vid = nil
      for v in pairs(vehs) do if not vid or v < vid then vid = v end end
    end
    if vid then
      local q = newPlayer(qname, qpid)
      local model = parseVehicle(vehs[vid])
      q.carVid, q.carModel, q.carName = vid, model, tostring(model or "car")
      q.leg, q.run = { via = 1, arrived = true }, newRun()
      n = n + 1
      players[qname] = q
    end
  end
  if n == 0 then say(pid, "Nobody's in a car - get in one first."); return end
  -- the running order (time trials): whoever pressed Test event first, then everyone else by name
  local order, me = {}, MP.GetPlayerName(pid)
  for qname in pairs(players) do order[#order + 1] = qname end
  table.sort(order, function(a, b)
    if (a == me) ~= (b == me) then return a == me end
    return a:lower() < b:lower()
  end)
  for i, qname in ipairs(order) do players[qname].arrivalRank = i end
  game = { phase = "travel", stage = 1, events = { deepcopy(e) }, players = players, test = true, phaseStart = now(),
           arrivals = n, allHere = true }
  game.testFinish = function()
    game = { phase = "idle", stage = 0, players = {} }
    pushIdle(-1)
    sayAll("Test event over - back to normal.")
  end
  sayAll(string.format("TEST EVENT: %s (%s) - %d driver%s, from the start line. /tg testevent stop ends it.", e.name, label, n, n == 1 and "" or "s"))
  if e.type == "trailer" and cfg.defaults.readyToGo == false then for _, q in pairs(players) do requestTrailer(q) end end
  if cfg.defaults.readyToGo ~= false then   -- every start is I'm ready, then GO
    if e.type == "trailer" then sayAll("Your trailer is dropped behind you when you press I'm ready - hitch up, then GO.") end
    if isSolo(e) then beginCountdown()   -- (the turns begin: the first driver's Ready, then GO)
    else
      sayAll("Press I'm ready - once everyone is, anyone can press GO.")
      bigAll("I'm ready, then GO")
      pushAll()
    end
    return
  end
  if e.type == "trailer" then   -- (Ryan: time to hitch up first - like arriving at a trailer event in a challenge)
    sayAll("Trailers are on their way - hitch up, then press GO" .. (isSolo(e) and " for the first run (one at a time)." or " to start everyone."))
    bigAll("Hitch up your trailer - then GO")
    pushAll()
    return
  end
  beginCountdown()
end
-- Quick travel (course builder): your car to an event's start (or the finale), facing the first checkpoint. Not during a
-- challenge. /tg quicktravel <n|finale>
ADMIN_CMDS.quicktravel = function(pid, _, args)
  if game.phase ~= "idle" then say(pid, "Quick travel only works when no challenge is going."); return end
  local e, label = eventArg(pid, args[3], true); if not e then return end
  local pos = v3(e.start or e.pos)
  local what = label == "finale" and "finish" or "start"
  if not pos then say(pid, label .. " has no " .. what .. " yet."); return end
  local look = Course.startLook(e) or v3((e.via or {})[1])
  MP.TriggerClientEvent(pid, "tg_quicktravel", Util.JsonEncode({ pos = pos, look = look }))
  say(pid, "Off to " .. label .. "'s " .. what .. ".")
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
  if not t.loadPart then   -- no load (a caravan): delivered in one piece - scored on how undamaged it arrives
    cfg.eventTypes.trailer.setup = { model = t.model, mode = "damage", loadParts = {}, parts = t.parts, vars = t.vars }
    saveConfig()
    say(pid, string.format("Saved your %s - it has no load, so it's delivered in one piece: the 70 load points are how undamaged " ..
      "it arrives (a wreck at %s damage). /tg trailertest to check it; /tg trailercones to go back.", tostring(t.model),
      tostring(typeCfg("trailer").wreckDamage or 10000)))
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
    say(pid, "Spawning your saved trailer (" .. tostring(payload.trailer) .. (payload.wreck and ", no load - in one piece" or " with its load") .. ") behind you...")
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
  if t.ok and t.prebuilt and t.intact then
    say(pid, string.format("Trailer OK - deliver it in one piece: no load, so it's scored on how undamaged it arrives%s.",
      tonumber(t.load) and string.format(" (%d%% intact now)", math.floor(t.load * 100 + 0.5)) or ""))
    return
  end
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
  if t.shopErr then say(pid, "Parts tab: can't list this car's parts - " .. tostring(t.shopErr))
  elseif t.shopSlots then
    say(pid, string.format("Parts tab: %s slots with options, %s parts listed (%s priced), via the %s.",
      tostring(t.shopSlots), tostring(t.shopOptions), tostring(t.shopPriced), tostring(t.shopMethod)))
  end
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
    respawnFee = cfg.economy.respawnFee,
    helpPoints = (cfg.modes or {}).freeRepair and 0 or (cfg.scoring.towPenaltyPoints or 0),
    workshopEvery = tonumber(cfg.workshopEvery) or 2,
    workshopMinutes = cfg.workshop.minutes,
    gamePrices = cfg.dealer.useGamePrices and true or false, allHere = game.allHere and true or false,
    readyGo = game.dealerGo and math.max(0, math.ceil(game.dealerGo - now())) or nil,
    -- time trial: the driver waiting for their GO, and whether this player may press it (them, or an admin)
    soloWait = (game.phase == "event" and game.solo and game.solo.waitGo and game.solo.runner)
      and { name = game.solo.runner.name, canGo = (p == game.solo.runner) or isAdmin(name), isMe = p == game.solo.runner,
            ready = (cfg.defaults.readyToGo == false) or (game.solo.runner.run.ready and true or false),
            carReady = not (game.solo.runner.rpc and not game.solo.runner.rpc.vid) } or nil,
    readyToGo = cfg.defaults.readyToGo ~= false,
    traffic = inTrafficMode(name),
    soundsOn = not soundsOff[name], soundClips = (cfg.sounds or {}).clips or {},
    watchOn = not RPC.watchOff[name],
    shop = p and {   -- the Parts tab prices options exactly the way TG_onRebuild bills them
      markup = cfg.workshop.partsMarkup or 1, resale = cfg.workshop.resaleRate or 0.5,
      flat = cfg.workshop.flatPartPrice or 500, labour = cfg.workshop.laborFee or 0,
      labourPaid = p.wsLabour == true, credit = p.cash + (cfg.workshop.creditLimit or 1500),
    } or nil,
  }
  if p then
    d.me = {
      name = p.name, cash = p.cash, points = p.points, wins = p.wins, car = p.carName, damage = math.floor(p.damage or 0),
      repair = repairQuote(p), upgrade = (upgradeBill(p)), ready = p.ready and true or false,
      dentsOnly = (repairQuote(p) == 0 and CONDITION.dents(p) > 0 and (p.damage or 0) > 0) or nil,
      towCost = (roadsideCost(p, "tow")), respawnCost = (roadsideCost(p, "respawn")),
      arrived = p.leg.arrived and true or false, hasCar = p.carVid ~= nil, tows = p.tows or 0,
      startReady = (p.run and p.run.ready) and true or false, wsReady = p.wsReady and true or false,
      canTow = p.carVid ~= nil and Course.canTow(p) and not p.finaleTowed and not (game.phase == "finale" and p.leg.arrived) or false,
      canUnstick = p.carVid ~= nil and game.phase ~= "countdown" or false,
      respawns = p.respawns or 0, hasCarModel = p.carModel ~= nil, inShop = inWorkshop(p),
      creditLimit = cfg.workshop.creditLimit or 1500,
      quirks = CONDITION.quirkList(p), quirkFix = (cfg.quirks or {}).fixCost or 150,
      glovebox = Score.gloveboxList(p),
    }
  end
  d.dealer = dealerOffers(p)   -- (sendUi leaves it out when the client already has this exact list)
  if game.phase == "paused" then   -- a challenge restored after a restart, waiting for /tg resume
    local back, away = {}, {}
    for pname, q in pairs(game.players) do if q.pid then back[#back + 1] = pname else away[#away + 1] = pname end end
    table.sort(back); table.sort(away)
    local e = (game.events or {})[game.stage]
    d.paused = { at = (game.resumePhase == "travel" and e) and ("on the way to " .. e.name)
                   or ((game.resumePhase == "event" or game.resumePhase == "countdown") and e) and (e.name .. " (it will be run again)")
                   or game.resumePhase, back = back, away = away }
  end
  if activeClass() then d.dealerClass = { name = chosenClass, summary = classSummary(activeClass()) }
  elseif Class.selling() then d.dealerClass = { name = "every car and truck", summary = "No class picked: everything imported is for sale (props and trailers aside)." } end
  d.summary = game.summary
  d.modes = { freeRepair = (cfg.modes or {}).freeRepair or false, noFaults = (cfg.modes or {}).noFaults or false,
              noQuirks = (cfg.modes or {}).noQuirks or false, turbo = (cfg.modes or {}).turbo or false, locked = game.phase ~= "idle" }
  if faultsOn() then
    local all, mine = {}, nil
    for _, f in ipairs(cfg.faults.list or {}) do   -- (admin fault test)
      all[#all + 1] = { id = f.id, name = f.name, tier = CONDITION.tier(f), groups = type(f.groups) == "table" and f.groups or nil }
    end
    if p and p.faultsRevealed then
      mine = {}
      for _, id in ipairs(p.faults or {}) do mine[#mine + 1] = { id = id, name = CONDITION.problemName(p, id) } end
    end
    local levels = {}
    for n = 0, 4 do levels[n + 1] = { name = CONDITION[n], km = CONDITION.km(n), off = CONDITION.percentOff(n), sev = CONDITION.sevOf(n) } end
    local quirkAll = {}   -- (admin quirk tests)
    for _, q in ipairs((cfg.quirks or {}).list or {}) do quirkAll[#quirkAll + 1] = { id = q.id, name = q.name } end
    d.quirkAll = quirkAll
    d.faults = { all = all, max = math.min(cfg.faults.maxPerCar or 4, 4), count = CONDITION.level(p), levels = levels,
                 fixPercent = tonumber(cfg.faults.fixPercent) or 0.05, fixMin = tonumber(cfg.faults.fixMin) or 500,
                 names = { CONDITION[0], CONDITION[1], CONDITION[2], CONDITION[3], CONDITION[4] },
                 locked = (p and p.boughtCondition ~= nil) and true or false,
                 fix = (p and p.carModel) and fixCost(p) or nil, revealed = (p and p.faultsRevealed) and true or false, mine = mine,
                 points = cfg.faults.inspectionPenaltyPoints or 0 }
  end
  d.standings = {}
  local nReady, nIn = 0, 0   -- (the Start tab's "2/3 players are ready")
  for _, q in ipairs(sortedPlayers()) do
    d.standings[#d.standings + 1] = { name = q.name, login = q.login, points = q.points, wins = q.wins, cash = q.cash, car = q.carName, online = q.pid ~= nil }
    if q.pid then nIn = nIn + 1; if q.ready then nReady = nReady + 1 end end
  end
  d.ready = { n = nReady, total = nIn }
  if d.admin and Score.turboOn() then d.turboAdmin = Score.turboAdminView() end
  if d.admin then local u = Course.canRerun(); d.rerun = u and game.events[u.stage].name or nil end   -- (Rerun <event>)   -- (the Admin tab's Turbo Mode box)
  -- the event's own GO in time trial mode starts the first driver: its button says who (the first to arrive)
  if game.phase == "workshop" and cfg.defaults.readyToGo ~= false then
    local _, waiting = RPC.wsAllReady()
    d.wsNotReady = waiting
  end
  if game.phase == "travel" and cfg.defaults.readyToGo ~= false and curEvent() and not isSolo(curEvent()) then
    local _, waiting = RPC.allReady()
    d.notReady = waiting   -- (the race start: who still has to press I'm ready)
  end
  if game.phase == "travel" and curEvent() and isSolo(curEvent()) then
    local first
    for _, q in pairs(game.players) do
      if racing(q) and q.leg and q.leg.arrived and (not first or (q.arrivalRank or 99) < (first.arrivalRank or 99)) then first = q end
    end
    d.goName = first and first.name or nil
  end
  if d.admin then
    local clist, cnames = {}, {}
    for n in pairs(cfg.dealer.classes or {}) do cnames[#cnames + 1] = n end
    table.sort(cnames)
    for _, n in ipairs(cnames) do
      local c = cfg.dealer.classes[n]
      local trims = classTrims(c)
      local e = { name = n, summary = classSummary(c), count = #trims, min = trims[1] and trims[1].price or nil,
                  max = trims[#trims] and trims[#trims].price or nil, rules = {}, include = c.include or {}, exclude = c.exclude or {},
                  multiplier = tonumber(c.multiplier) or 1 }
      for _, r in ipairs(c.rules or {}) do e.rules[#e.rules + 1] = { field = r.field, text = Class.ruleText(r) } end
      if Class.view[name] == n then   -- the one being edited: its cars (first 60), unpriced ones last
        e.trims = {}
        for i, t in ipairs(classTrims(c, true)) do
          if i > 60 then break end
          local key = t.model .. "/" .. t.config
          e.trims[#e.trims + 1] = { key = key, name = t.name, price = t.price, override = (c.prices or {})[key] ~= nil, noPrice = t.price == nil, est = t.est or nil }
        end
      end
      clist[#clist + 1] = e
    end
    local fields = {}
    for _, k in ipairs(Class.ORDER) do
      local f = Class.FIELDS[k]
      local vals = f[2] == "list" and Class.fieldValues(f[1]) or nil
      if vals and #vals > 30 then vals = { table.unpack and table.unpack(vals, 1, 30) or unpack(vals, 1, 30) } end
      fields[#fields + 1] = { key = k, name = f[1], kind = f[2], values = vals }
    end
    local unpriced, nUnpriced = {}, 0
    for model, trims in pairs(cfg.dealer.gamePrices or {}) do
      for config, e in pairs(trims) do
        if type(e) == "table" and not tonumber(e.price) then
          nUnpriced = nUnpriced + 1
          local key = model .. "/" .. config
          unpriced[#unpriced + 1] = { key = key, name = e.name or key, price = tonumber((cfg.dealer.prices or {})[key]), est = tonumber(e.est) }
        end
      end
    end
    table.sort(unpriced, function(a, b) return a.name < b.name end)
    while #unpriced > 60 do table.remove(unpriced) end
    -- ready-made class sizes: counting ~1,000 trims 18 times is slow on the server, so they're cached
    -- (cleared by imports and price changes; refreshed every 30 s anyway)
    if not Class.presetCounts or now() - Class.presetCounts.at > 30 then
      Class.presetCounts = { at = now() }
      for _, pr in ipairs(Class.PRESETS) do Class.presetCounts[pr.key] = #classTrims({ rules = pr.rules }) end
    end
    local presets = {}
    for _, pr in ipairs(Class.PRESETS) do
      presets[#presets + 1] = { key = pr.key, title = pr.title, count = Class.presetCounts[pr.key],
                                made = (cfg.dealer.classes or {})[pr.key] ~= nil }
    end
    d.classes = { catalogue = cfg.dealer.catalogue, active = chosenClass, none = Class.noneText(), presets = presets, list = clist, view = Class.view[name], fields = fields, idle = game.phase == "idle",
                  imported = next(cfg.dealer.gamePrices or {}) ~= nil, unpriced = unpriced, unpricedCount = nUnpriced }
    local ev = {}
    for i, e in ipairs(cfg.events) do
      ev[#ev + 1] = { n = i, name = e.name, type = e.type or "race", start = v3(e.start) ~= nil,
                      cps = #(e.checkpoints or {}), trap = v3(e.trap) ~= nil, bays = #eventBays(e), via = #(e.via or {}),
                      timeLimit = e.timeLimit or cfg.defaults.eventTimeLimit,
                      enabled = e.enabled ~= false, solo = isSolo(e), typeLabel = (TYPE_INFO[e.type or "race"] or {}).label,
                      laps = e.laps, rpcCar = e.type == "rpc" and RPC.label(e) or nil }
    end
    local lib = {}
    for n, c in pairs(library) do lib[#lib + 1] = { name = n, problems = c.problems or 0, savedAt = c.savedAt } end
    table.sort(lib, function(a, b) return a.name:lower() < b.name:lower() end)
    local types = {}
    for i, t in ipairs(TYPE_ORDER) do types[i] = { id = t, label = TYPE_INFO[t].label } end
    local tset = typeCfg("trailer").setup
    local trailerInfo = (type(tset) == "table" and tset.model)
      and string.format("%s - %s", tset.model, tset.mode == "damage" and "no load: delivered in one piece (scored on damage)"
                                               or ("built-in load " .. tostring(tset.loadPart)))
      or string.format("%s with %d x %s (loose cargo)", tostring(typeCfg("trailer").trailerModel), typeCfg("trailer").cargoCount or 5,
                       tostring(typeCfg("trailer").cargoModel))
    d.course = { events = ev, problems = #validate(nil, nil, true), library = lib, active = cfg.activeCourse, dirty = courseDirty,
                 trailer = trailerInfo, testing = game.test or nil,
                 workshops = #workshopSpots(),
                 types = types, workshopEvery = tonumber(cfg.workshopEvery) or 2, idle = game.phase == "idle",
                 finale = { name = cfg.finale.name, pos = v3(cfg.finale.pos) ~= nil, via = #(cfg.finale.via or {}) } }
  end
  return d
end

-- The car list can be ~1,000 trims (~100 KB): it's only sent when it changed since the version the client says it
-- has (the client echoes `dealerVer` in its refresh requests; pushes without one always carry the list).
Class.sentDealer = {}   -- pid -> { str, ver }
local function sendUi(pid, haveVer)
  local d = buildUi(pid)
  local okD, str = pcall(Util.JsonEncode, d.dealer or {})
  if okD then
    local sent = Class.sentDealer[pid]
    if not sent or sent.str ~= str then
      sent = { str = str, ver = ((sent and sent.ver) or 0) + 1 }
      Class.sentDealer[pid] = sent
    end
    d.dealerVer = sent.ver
    if haveVer and tonumber(haveVer) == sent.ver then d.dealer, d.dealerSame = nil, true end
  end
  MP.TriggerClientEvent(pid, "tg_ui", Util.JsonEncode(d))
end

function TG_onUiRequest(pid, data) sendUi(pid, data) end

-- the game's vehicle selector, opened during the dealership: the client shows today's cars at these prices
-- the game's vehicle selector during the dealership: only the cars you can buy in the condition you've picked
-- (Ryan, 0.9.13 - the Dealership tab still lists the rest, coloured by the condition each needs)
function TG_onDealerListReq(pid)
  if game.phase ~= "dealer" then return end
  local offers = {}
  for _, g in ipairs(dealerOffers(playerByPid(pid))) do
    local trims = {}
    for _, t in ipairs(g.trims) do if (tonumber(t.needs) or 0) == 0 and not t.over then trims[#trims + 1] = t end end
    if #trims > 0 then offers[#offers + 1] = { model = g.model, name = g.name, trims = trims } end
  end
  MP.TriggerClientEvent(pid, "tg_dealerlist", Util.JsonEncode({ offers = offers }))
end

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
pcall(function() math.randomseed(os.time()) end)   -- Lua 5.3 doesn't seed itself: vary the random sound picks
loadConfig()
if cfg.dealer.catalogue == "builtin" or not next(cfg.dealer.gamePrices or {}) then   -- no import of its own
  local okB, n, first = Class.loadBuiltin()
  if okB then
    log(string.format("cars: the built-in catalogue (%d trims) - /tg importprices reads your own game's", n))
    if first then saveConfig() end
  else log("cars: " .. tostring(n) .. " - the dealer list is used until /tg importprices") end
end
if cfg.dealer.importedAll == nil and next(cfg.dealer.gamePrices or {}) then   -- a full import by 0.9.0-0.9.3: models off the list
  for model in pairs(cfg.dealer.gamePrices) do if not modelListed(model) then cfg.dealer.importedAll = true end end
  if cfg.dealer.importedAll then saveConfig() end
end
if next(cfg.dealer.gamePrices or {}) then   -- drop non-cars and estimate missing prices (also for older imports)
  local okT, dropped, estimated, changed = pcall(Class.tidyImport)
  if not okT then log("pricing estimates failed: " .. tostring(dropped))
  elseif changed and cfg.dealer.catalogue ~= "builtin" then   -- (the built-in catalogue isn't saved: nothing to write)
    saveConfig()
    log(string.format("imported cars: dropped %d props/trailers, %d prices estimated", dropped, estimated))
  end
end
courseDirty = cfg.courseDirty == true
loadLibrary()
do
  local okL, errL = pcall(Save.load)
  if not okL then log("couldn't restore the saved challenge: " .. tostring(errL)) end
end
MP.RegisterEvent("onChatMessage",      "TG_onChat")
MP.RegisterEvent("onPlayerJoin",       "TG_onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "TG_onPlayerDisconnect")
MP.RegisterEvent("onVehicleSpawn",     "TG_onVehicleSpawn")
MP.RegisterEvent("onVehicleEdited",    "TG_onVehicleEdited")
MP.RegisterEvent("onVehicleDeleted",   "TG_onVehicleDeleted")
MP.RegisterEvent("onVehicleReset",     "TG_onVehicleReset")
MP.RegisterEvent("tg_report",          "TG_onReport")
MP.RegisterEvent("tg_activeveh",       "TG_onActiveVeh")
MP.RegisterEvent("tg_diag_reply",      "TG_onDiag")
MP.RegisterEvent("tg_import_reply",    "TG_onImportReply")
MP.RegisterEvent("tg_ui_req",          "TG_onUiRequest")
MP.RegisterEvent("tg_dealerlist_req",  "TG_onDealerListReq")
MP.RegisterEvent("tg_ui_cmd",          "TG_onUiCommand")
MP.RegisterEvent("tg_fault_report",    "TG_onFaultReport")
MP.RegisterEvent("tg_move_report",     "TG_onMoveReport")
MP.RegisterEvent("tg_trailer_report",  "TG_onTrailerReport")
MP.RegisterEvent("tg_rebuild",         "TG_onRebuild")
MP.RegisterEvent("tg_revert_report",   "TG_onRevertReport")
MP.RegisterEvent("tg_trailersave_reply", "TG_onTrailerSave")
MP.RegisterEvent("tg_gas_reply",       "TG_onGasStations")
MP.RegisterEvent("tg_partsdiag_reply", "TG_onPartsDiag")
MP.RegisterEvent("tg_sound_report",    "TG_onSoundReport")
MP.RegisterEvent("tg_engine_blown",    "TG_onEngineBlown")
MP.RegisterEvent("tg_car_fire",        "TG_onCarFire")
MP.RegisterEvent("tg_tick",            "TG_onTick")
MP.CreateEventTimer("tg_tick", TICK_MS)
if #cfg.admins == 0 then log("WARNING: no admins set in config.json - everyone can run admin commands") end
log(string.format("Top Gear Challenge server v%s loaded: %d events. Type /tg help in game.", SERVER_VERSION, #cfg.events))
