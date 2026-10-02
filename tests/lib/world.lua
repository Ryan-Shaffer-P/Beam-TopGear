-- A simulated BeamMP world: one server (the real main.lua) and one game client per player (the
-- real topgear.lua, loaded through the real modScript.lua), joined by a message queue and driven by
-- a virtual clock. Nothing here is the mod's own code - only fakes of BeamMP and BeamNG.
--
--   local w = World.new()
--   local a = w:join("Alice")             -- connects, loads her client mod
--   w:chat(a, "/tg start force")
--   w:buy(a, "covet", "base_M")           -- spawns through the client, like the vehicle menu
--   w:step(1.0)                           -- advance time: server ticks, client frames, messages
--   w:drive(a, {x=100,y=0,z=0})           -- move the car there at a steady speed
--   w:assertClean()                       -- no errors, warnings or UI imbalance anywhere
local json     = require("json")
local sandbox  = require("sandbox")
local vecmath  = require("vecmath")
local imguiLib = require("imgui")

local vec3, quat = vecmath.vec3, vecmath.quat

local ROOT = (os.getenv("TG_ROOT") or ".") .. "/"
local SERVER_FILE = ROOT .. "Resources/Server/TopGear/main.lua"
local CLIENT_DIR  = ROOT .. "client/"

local World = {}
World.__index = World

-- default model catalogue for core_vehicles.getModel (price import) and spawn configs
-- (info = the model's attributes BeamNG's vehicle menu filters on; trims = per-trim overrides)
local MODELS = {
  covet   = { brand = "Ibishu",  name = "Covet",   configs = { base_M = 4200, sport_M = 7800, gtz_M = 14000 }, adjustable = true, manual = true,
              info = { Country = "Japan", ["Body Style"] = "Hatchback", Type = "Car", Years = { min = 1988, max = 1996 } },
              trims = { base_M = { Transmission = "Manual", ["Config Type"] = "Factory" }, sport_M = { Transmission = "Manual", ["Config Type"] = "Factory" },
                        gtz_M = { Transmission = "Manual", ["Config Type"] = "Factory" } } },
  pessima = { brand = "Ibishu",  name = "Pessima", configs = { base_M = 3900, gl_A = 5100 }, adjustable = true, turbo = true,
              info = { Country = "Japan", ["Body Style"] = "Sedan", Type = "Car", Years = { min = 1988, max = 1996 } },
              trims = { base_M = { Transmission = "Manual", ["Config Type"] = "Factory" }, gl_A = { Transmission = "Automatic", ["Config Type"] = "Factory" } } },
  pickup  = { brand = "Gavril",  name = "D-Series", configs = { d15_M = 6800, d35_A = 12500 }, manual = true,
              info = { Country = "United States", ["Body Style"] = "Pickup", Type = "Truck", Years = { min = 1990, max = 2010 } } },
  miramar = { brand = "Ibishu",  name = "Miramar", configs = { base_M = 3100 }, noFuelTank = true, noThermals = true, manual = true,
              info = { Country = "Japan", ["Body Style"] = "Sedan", Type = "Car", Years = { min = 1970, max = 1985 } } },
  tsfb    = { brand = "",        name = "Small flatbed trailer", configs = { base = 900 }, info = { Type = "Trailer" } },
  -- a mod car the game has no prices for (false = no Value)
  modcar  = { brand = "Fanto",   name = "Bolide", configs = { stradale = false, corsa = false },
              info = { Country = "Italy", ["Body Style"] = "Coupe", Type = "Car", Years = { min = 1972, max = 1978 } },
              trims = { stradale = { Transmission = "Manual", ["Config Type"] = "Factory" }, corsa = { Transmission = "Manual", ["Config Type"] = "Factory" } } },
  cones   = { brand = "",        name = "Cones", configs = { base = 10 }, info = { Type = "Prop" } },
}

-- every car's fake part catalogue: slot key -> options { part name, game value (nil = no price), nice name }.
-- The first option is what a new car has fitted ("" = the slot is empty).
local function partCatalogue(model)
  local m = model
  return {
    { key = "/body/",               options = { { m .. "_body", 0, "Body" } } },
    { key = "/bumper_F/",           options = { { m .. "_bumper_F", 200, "Front bumper" } } },
    { key = "/bumper_R/",           options = { { m .. "_bumper_R", 200, "Rear bumper" } } },
    { key = "/" .. m .. "_engine/", options = { { m .. "_engine", 2000, "1.5L I4" }, { m .. "_engine_turbo", 3200, "1.5L I4 Turbo" } } },
    { key = "/" .. m .. "_coilover_F/", options = { { m .. "_coilover_F", 400, "Stock front springs" }, { m .. "_coilover_F_sport", 1800, "Sport coilovers" } } },
    { key = "/" .. m .. "_spoiler/", options = { { "", 0 }, { m .. "_spoiler", 300, "Rear spoiler" } } },
    { key = "/" .. m .. "_lip/",     options = { { "", 0 }, { m .. "_lip", 150, "Front lip" } } },
    { key = "/" .. m .. "_seat_FL/", options = { { m .. "_seat", 100, "Stock seat" }, { m .. "_seat_race", 600, "Race seat" } } },
    { key = "/" .. m .. "_hood/",    options = { { m .. "_hood", 250, "Stock hood" }, { m .. "_hood_fiberglass", 900, "Fiberglass hood" } } },
    { key = "/" .. m .. "_odd/",     options = { { m .. "_odd", nil, "Odd part" }, { m .. "_odd_plus", nil, "Odd part plus" } } },
    { key = "/" .. m .. "_swaybar_F/", options = { { m .. "_swaybar_F", 150, "Front anti-roll bar" } } },
  }
end
World.partCatalogue = partCatalogue
World.MODELS = MODELS
local function catalogueIndex(model)   -- part name -> { value, nice, key }
  local idx = {}
  for _, sl in ipairs(partCatalogue(model)) do
    for _, o in ipairs(sl.options) do if o[1] ~= "" then idx[o[1]] = { value = o[2], nice = o[3], key = sl.key } end end
  end
  return idx
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = copy(v) end
  return r
end

local function tb(err) return debug.traceback(tostring(err), 2) end

function World.new(opts)
  opts = opts or {}
  local w = setmetatable({}, World)
  w.t = 0
  w.files = {}            -- in-memory filesystem for the server (path -> contents)
  w.console = {}          -- server print() lines
  w.errors = {}           -- uncaught errors from any handler (server or client)
  w.players = {}          -- pid -> player
  w.byName = {}
  w.queue = {}            -- pending messages between server and clients
  w.nextPid, w.nextGid = 0, 1000
  w.models = opts.models or MODELS
  for path, content in pairs(opts.files or {}) do w.files[path] = content end
  w:loadServer()
  return w
end

---------------------------------------------------------------------------------------------
-- server
---------------------------------------------------------------------------------------------
function World:loadServer()
  local w = self
  local sb = sandbox.new({ label = "server", allowWrite = function(k) return type(k) == "string" and k:find("^TG_") ~= nil end })
  w.server = { sb = sb, events = {}, timers = {} }

  sb.set("print", function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    w.console[#w.console + 1] = table.concat(parts, "\t")
  end)

  sb.set("io", { open = function(path, mode)
    mode = mode or "r"
    if mode:find("r") then
      local s = w.files[path]
      if not s then return nil, path .. ": No such file or directory" end
      return { read = function() return s end, close = function() end, lines = function() return s:gmatch("[^\n]+") end }
    end
    local buf = {}
    return { write = function(_, ...) for _, x in ipairs({ ... }) do buf[#buf + 1] = tostring(x) end end,
             close = function() w.files[path] = table.concat(buf) end }
  end })

  sb.set("Util", {
    JsonEncode = function(t) return json.encode(t) end,
    JsonDecode = function(s) return json.decode(s) end,
    JsonPrettify = function(s) return s end,
  })
  sb.set("FS", { Exists = function(p) return w.files[p] ~= nil end })
  w.rolls, w.chances = {}, {}
  sb.set("math", setmetatable({ random = function(a, b)
    if a and not b and #w.rolls > 0 then
      local r = table.remove(w.rolls, 1)
      if r == "last" then r = a end   -- (the last candidate, however many there are)
      assert(r >= 1 and r <= a, "w.rolls value " .. tostring(r) .. " out of range 1.." .. tostring(a))
      return r
    end
    if b then return math.random(a, b) elseif a then return math.random(a) end
    if #w.chances > 0 then return table.remove(w.chances, 1) end
    return math.random()
  end }, { __index = math }))

  local MP = {}
  function MP.CreateTimer() return { GetCurrent = function() return w.t end } end
  function MP.RegisterEvent(ev, fnName) w.server.events[ev] = fnName end
  function MP.CreateEventTimer(ev, ms) w.server.timers[#w.server.timers + 1] = { ev = ev, every = ms / 1000, nextT = w.t + ms / 1000 } end
  function MP.GetPlayers()
    local out = {}
    for pid, p in pairs(w.players) do if p.connected then out[pid] = p.name end end
    return out
  end
  function MP.GetPlayerName(pid) local p = w.players[pid]; return p and p.name or "" end
  function MP.GetPlayerVehicles(pid)
    local p = w.players[pid]
    if not p then return nil end
    local out = {}
    for vid, v in pairs(p.vehicles) do out[vid] = v.data end
    return out
  end
  function MP.GetPositionRaw(pid, vid)
    local p = w.players[pid]
    local v = p and p.vehicles[vid]
    if not v then return nil, "Vehicle not found" end
    local q = vecmath.quatFromYaw(v.yaw or 0)
    return { pos = { v.pos.x, v.pos.y, v.pos.z }, vel = { v.vel.x, v.vel.y, v.vel.z }, rot = { q.x, q.y, q.z, q.w } }, ""
  end
  function MP.RemoveVehicle(pid, vid)
    local p = w.players[pid]
    if not (p and p.vehicles[vid]) then return false, "Vehicle does not exist" end
    w:serverEvent("onVehicleDeleted", pid, vid)   -- BeamMP fires this synchronously
    w:dropVehicle(p, vid)
    return true
  end
  function MP.SendChatMessage(pid, msg)
    for qpid, p in pairs(w.players) do
      if (pid == -1 or pid == qpid) and p.connected then p.chat[#p.chat + 1] = msg end
    end
  end
  function MP.TriggerClientEvent(pid, ev, data)
    for qpid, p in pairs(w.players) do
      if (pid == -1 or pid == qpid) and p.connected then
        w.queue[#w.queue + 1] = { to = "client", pid = qpid, ev = ev, data = data }
      end
    end
    return true
  end
  sb.set("MP", MP)

  local ok, err = xpcall(function() sb.dofile(SERVER_FILE) end, tb)
  if not ok then error("server failed to load:\n" .. err, 0) end
end

-- call a registered server event; returns the handler's result
function World:serverEvent(ev, ...)
  local fnName = self.server.events[ev]
  if not fnName then return nil end
  local fn = rawget(self.server.sb.env, fnName)
  if type(fn) ~= "function" then
    self.errors[#self.errors + 1] = "server: event " .. ev .. " -> " .. fnName .. " is not a function"
    return nil
  end
  local args = { ... }
  local n = select("#", ...)
  local res
  local ok, err = xpcall(function() res = fn((table.unpack or unpack)(args, 1, n)) end, tb)
  if not ok then self.errors[#self.errors + 1] = "server " .. fnName .. ": " .. err end
  return res
end

---------------------------------------------------------------------------------------------
-- players and their game clients
---------------------------------------------------------------------------------------------
function World:join(name, opts)
  opts = opts or {}
  local pid = self.nextPid
  self.nextPid = pid + 1
  local p = { pid = pid, name = name, connected = true, chat = {}, vehicles = {}, nextVid = 0,
              spawnPos = opts.pos or vec3(pid * 6, 0, 0) }
  self.players[pid] = p
  self.byName[name] = p
  if opts.client ~= false then self:loadClient(p) end
  self:serverEvent("onPlayerJoin", pid)
  self:pump()
  return p
end

function World:leave(p)
  self:serverEvent("onPlayerDisconnect", p.pid)
  for vid in pairs(p.vehicles) do self:dropVehicle(p, vid) end
  p.connected = false
  p.client = nil
  self:pump()
end

function World:loadClient(p)
  local w = self
  local im = imguiLib.new()
  local sb = sandbox.new({ label = "client:" .. p.name })
  local c = { sb = sb, im = im, handlers = {}, log = {}, messages = {}, ui = {}, filters = {}, path = nil,
              vlua = {}, M = nil }
  p.client = c

  sb.set("log", function(level, tag, msg) c.log[#c.log + 1] = { level = level, tag = tag, msg = tostring(msg) } end)
  sb.set("ui_message", function(msg, ttl, cat) c.messages[#c.messages + 1] = { msg = tostring(msg), cat = cat }; if cat then c.ui[cat] = tostring(msg) end end)
  sb.set("jsonEncode", json.encode)
  sb.set("jsonDecode", json.decode)
  -- BeamNG 0.37+'s selector backend: builds its list through core_vehicles' lookups (like initializeVehicleData)
  -- when it's (re)loaded; clearCache() makes it reload. c.selector039() = { [model/config] = { name, Value } }
  c.selectorReloads = 0
  sb.set("ui_vehicleSelector_general", { clearCache = function() c.selectorReloads = c.selectorReloads + 1 end })
  function c.selector039()
    local cv, out = rawget(sb.env, "core_vehicles"), {}
    for model in pairs(cv.getModelsData()) do
      for key in pairs(cv.getModel(model).configs or {}) do
        local cfg = cv.getConfig(model, key)
        out[model .. "/" .. key] = { name = cfg.Configuration, fullName = cfg.Name, Value = cfg.Value }
      end
    end
    return out
  end
  c.selectorLists = {}   -- every list the vehicle selector screen was sent ('sendVehicleList')
  sb.set("guihooks", { trigger = function(name, data)
    if name == "sendVehicleList" then c.selectorLists[#c.selectorLists + 1] = data end
  end })
  sb.set("vec3", vec3)
  sb.set("quat", quat)
  sb.set("quatFromDir", vecmath.quatFromDir)
  sb.set("ColorF", function(...) return { ... } end)
  sb.set("ColorI", function(...) return { ... } end)
  sb.set("String", function(s) return s end)
  sb.set("debugDrawer", { drawCylinder = function() end, drawTextAdvanced = function() end, drawSphere = function() end })
  sb.set("ui_imgui", im)
  -- sound: records what played; the clip file must exist in the client mod (a typo'd clip id fails loudly)
  c.sounds, c.audioBroken = {}, false
  local function clipFile(path)
    local rel = path:gsub("^/", "")
    local f = io.open(CLIENT_DIR .. rel, "rb")
    if not f then error("sound file not found: " .. path) end
    f:close()
    return rel:match("([^/]+)%.ogg$")
  end
  sb.set("Engine", { Audio = { playOnce = function(channel, path)
    if c.audioBroken then error("Engine.Audio unavailable") end
    c.sounds[#c.sounds + 1] = { clip = clipFile(path), via = "audio", channel = channel }
  end } })
  sb.set("getCurrentLevelIdentifier", function() return "west_coast_usa" end)
  sb.set("scenetree", { findObject = function() return nil end, findClassObjects = function() return {} end })
  sb.set("spawn", { safeTeleport = function(veh, pos, rot, _, _, _, _, resetVehicle)
    local v = veh.veh
    v.pos = vec3(pos)
    v.yaw = (math.atan2 or math.atan)(2 * (rot.w * rot.z + rot.x * rot.y), 1 - 2 * (rot.y * rot.y + rot.z * rot.z))
    v.upsideDown = false
    if resetVehicle ~= false then v.resetPos = vec3(pos); w:vehicleReset(p, v) end
  end })
  sb.declare("freeroam_bigMapMode", "freeroam_facilities", "MPGameNetwork", "serialize", "setExtensionUnloadMode")

  sb.set("require", function(name)
    if name == "ffi" then return { string = function(buf) return buf.value end } end
    if name == "jbeam/io" then
      return {
        getPart = function(ioCtx, partName)
          local e = ioCtx and catalogueIndex(ioCtx.model)[partName]
          if not e then return nil end
          return { partName = partName, information = { name = e.nice, value = e.value } }
        end,
        getAvailableParts = function(ioCtx)
          local out = {}
          for n, e in pairs(catalogueIndex(ioCtx.model)) do out[n] = { description = e.nice or "" } end
          return out
        end,
        getAvailableSlotMap = (not c.noSlotMap) and function(ioCtx)
          local out = {}
          for _, sl in ipairs(partCatalogue(ioCtx.model)) do
            out[sl.key] = {}
            for _, o in ipairs(sl.options) do if o[1] ~= "" then out[sl.key][#out[sl.key] + 1] = o[1] end end
          end
          return out
        end or nil,
      }
    end
    error("module '" .. tostring(name) .. "' not available in the test game")
  end)

  sb.set("core_input_actionFilter", {
    setGroup = function(group, actions) c.filters[group] = c.filters[group] or {}; c.filters[group].actions = actions end,
    addAction = function(_, group, blocked) c.filters[group] = c.filters[group] or {}; c.filters[group].blocked = blocked end,
  })
  sb.set("core_groundMarkers", {
    setPath = function(pos) c.path = pos and vec3(pos) or nil end,
    currentlyHasTarget = function() return c.path ~= nil end,
  })

  -- vehicles as the game sees them
  local be = {}
  function be:getPlayerVehicle() return p.current and p.current.obj or nil end
  function be:getObjectByID(gid)
    for _, v in pairs(p.vehicles) do if v.gid == gid then return v.obj end end
    return nil
  end
  function be:enterVehicle(_, obj) if obj and obj.veh then p.current = obj.veh end end
  function be:executeJS(js)
    local path = js:match('new Audio%("local://local(.-)"%)')
    c.sounds[#c.sounds + 1] = { clip = path and clipFile(path), via = "js", js = js }
  end
  sb.set("be", be)
  sb.set("map", { objects = setmetatable({}, { __index = function(_, gid)
    for _, v in pairs(p.vehicles) do if v.gid == gid then return { damage = v.damage } end end
    return nil
  end }) })
  sb.set("MPVehicleGE", { getGameVehicleID = function(serverId)
    local spid, svid = tostring(serverId):match("^(%d+)%-(%d+)$")
    if tonumber(spid) ~= p.pid then return -1 end
    local v = p.vehicles[tonumber(svid)]
    return v and v.gid or -1
  end })

  sb.set("core_vehicles", {
    spawnNewVehicle = function(model, o) return w:clientSpawn(p, model, o or {}) end,
    removeCurrent = function() if p.current then w:clientDelete(p, p.current) end end,
    __fakeGetModel = function(model) return rawget(p.client.sb.env, "core_vehicles").__realGetModel(model) end,
    getModel = function(model)
      local m = w.models[model]
      if not m then return nil end
      local configs = {}
      for key, price in pairs(m.configs) do
        configs[key] = { key = key, Configuration = key, Value = price or nil, model_key = model, Name = m.name .. " " .. key,
                         preview = "/vehicles/" .. model .. "/" .. key .. ".jpg",
                         aggregates = { Value = price and { min = price, max = price } or nil, Years = (m.info or {}).Years,
                                        Country = (m.info or {}).Country and { [(m.info or {}).Country] = true } or nil } }
        for k, val in pairs((m.trims or {})[key] or {}) do configs[key][k] = val end
      end
      local info = { key = model, Brand = m.brand, Name = m.name }
      for k, val in pairs(m.info or {}) do info[k] = val end
      return { model = info, configs = configs }
    end,
    -- (0.37+) the vehicle selector reads every car through these, looked up on each call
    getModelsData = function()
      local out = {}
      for key in pairs(w.models) do out[key] = true end
      return out
    end,
    getConfig = function(model, key)
      local m = rawget(p.client.sb.env, "core_vehicles").__fakeGetModel(model)
      return m and m.configs[key] or nil
    end,
    getModelList = function()
      local models = {}
      for key, m in pairs(w.models) do models[key] = { key = key, Brand = m.brand, Name = m.name } end
      return { models = models }
    end,
    -- the vehicle selector screen: opening it asks requestList() for the list, which answers with the
    -- 'sendVehicleList' UI hook (recorded in p.client.selectorLists); the game's own list = every model
    requestList = function()
      local models, configs = {}, {}
      for key, m in pairs(w.models) do
        models[#models + 1] = { key = key, Name = m.name, aggregates = {} }
        for ck in pairs(m.configs) do configs[#configs + 1] = { key = ck, model_key = key, Name = m.name .. " " .. ck, native = true } end
      end
      rawget(p.client.sb.env, "guihooks").trigger("sendVehicleList", { models = models, configs = configs, filters = {}, native = true })
    end,
    openSelectorUI = function() p.client.selectorOpened = (p.client.selectorOpened or 0) + 1; rawget(p.client.sb.env, "core_vehicles").requestList() end,
  })
  do   -- the game's own getModel, kept for getConfig (the mod may wrap getModel)
    local cv = rawget(sb.env, "core_vehicles")
    cv.__realGetModel = cv.getModel
  end

  -- c.partsFormat = "tree": the newer parts-tree format (each slot node lists the parts that fit it)
  local function treeOf(v)
    local root = { path = "/", chosenPartName = v.model, children = {} }
    for _, sl in ipairs(partCatalogue(v.model)) do
      if v.parts[sl.key] ~= nil then
        local fits = {}
        for _, o in ipairs(sl.options) do if o[1] ~= "" then fits[#fits + 1] = o[1] end end
        root.children[sl.key:match("([^/]+)/?$")] = { path = sl.key, chosenPartName = v.parts[sl.key], suitablePartNames = fits }
      end
    end
    for key, part in pairs(v.parts) do   -- parts outside the catalogue (e.g. a trailer's load)
      local leaf = key:match("([^/]+)/?$") or key
      if not root.children[leaf] then root.children[leaf] = { path = key, chosenPartName = part } end
    end
    return root
  end
  sb.set("core_vehicle_manager", { getVehicleData = function(gid)
    for _, v in pairs(p.vehicles) do
      if v.gid == gid then
        if c.partsFormat == "tree" then
          return { ioCtx = { model = v.model }, vdata = { activeParts = {}, variables = w:varDefs(v) }, config = { partsTree = treeOf(v) } }
        end
        return { ioCtx = { model = v.model }, chosenParts = copy(v.parts), vdata = { activeParts = {}, variables = w:varDefs(v) }, config = { parts = copy(v.parts) } }
      end
    end
    return nil
  end })
  sb.set("core_vehicle_partmgmt", {
    getConfig = function()
      local v = p.current
      if not v then return nil end
      if c.partsFormat == "tree" then return { partsTree = treeOf(v), vars = copy(v.vars) } end
      return { parts = copy(v.parts), vars = copy(v.vars) }
    end,
    setPartsConfig = function(parts, respawn) w:clientEditConfig(p, { parts = parts }, respawn) end,
    setPartsTreeConfig = function(tree, respawn)
      local v = p.current
      if not v then return end
      local parts = copy(v.parts)
      local function walk(n)
        if type(n) ~= "table" then return end
        if n.path and n.path ~= "/" and n.chosenPartName ~= nil then parts[n.path] = n.chosenPartName end
        for _, ch in pairs(n.children or {}) do walk(ch) end
      end
      walk(tree)
      w:clientEditConfig(p, { parts = parts }, respawn)
    end,
    setConfigVars = function(vars, respawn) w:clientEditConfig(p, { vars = vars }, respawn) end,
  })

  sb.set("AddEventHandler", function(ev, fn) c.handlers[ev] = fn end)
  sb.set("TriggerServerEvent", function(ev, data)
    w.queue[#w.queue + 1] = { to = "server", pid = p.pid, ev = ev, data = data }
  end)

  local extensions = {}
  function extensions.load(name)
    if name == "topgear" and not c.M then
      c.M = sb.dofile(CLIENT_DIR .. "lua/ge/extensions/topgear.lua")
      extensions.topgear = c.M
      if c.M.onExtensionLoaded then c.M.onExtensionLoaded() end
    end
  end
  sb.set("extensions", extensions)

  local ok, err = xpcall(function() sb.dofile(CLIENT_DIR .. "scripts/topgear/modScript.lua") end, tb)
  if not ok then error("client failed to load for " .. p.name .. ":\n" .. err, 0) end
  if not c.M then error("modScript.lua did not load the topgear extension for " .. p.name, 0) end
end

-- call a function on a player's client, recording errors
function World:clientCall(p, label, fn, ...)
  if not (p.client and fn) then return end
  local args, n = { ... }, select("#", ...)
  local ok, err = xpcall(function() fn((table.unpack or unpack)(args, 1, n)) end, tb)
  if not ok then self.errors[#self.errors + 1] = "client " .. p.name .. " " .. label .. ": " .. err end
end

---------------------------------------------------------------------------------------------
-- vehicles
---------------------------------------------------------------------------------------------
local function vehData(p, v)
  return string.format("USER:%s:%d-%d:%s", p.name, p.pid, v.vid, json.encode({
    jbm = v.model, vcf = { partConfigFilename = v.configPath, parts = v.parts, vars = v.vars } }))
end

local function makeObj(w, p, v)
  local obj = { veh = v }
  function obj:getID() return v.gid end
  function obj:getPosition() return vec3(v.pos) end
  function obj:getDirectionVector() return vecmath.dirFromQuat(vecmath.quatFromYaw(v.yaw or 0)) end
  function obj:getDirectionVectorUp() return v.upsideDown and vec3(0, 0, -1) or vec3(0, 0, 1) end
  function obj:getRotation() return vecmath.quatFromYaw(v.yaw or 0) end
  function obj:getVelocity() return vec3(v.vel) end
  function obj:getJBeamFilename() return v.model end
  function obj:queueLuaCommand(code) w:runVehicleLua(p, v, code) end
  function obj:setPositionRotation(x, y, z, qx, qy, qz, qw)
    v.pos = vec3(x, y, z)
    v.yaw = (math.atan2 or math.atan)(2 * (qw * qz + qx * qy), 1 - 2 * (qy * qy + qz * qz))
    v.upsideDown = false
    -- some BeamNG versions repair the car when it's moved like this (set by a test):
    --   "silent" = the damage just disappears; "reset" = and BeamMP reports a reset
    local c = p.client
    if c and c.teleportRepairs == "silent" then v.damage = 0
    elseif c and c.teleportRepairs == "reset" then w:vehicleReset(p, v) end
  end
  function obj:delete() w:clientDelete(p, v) end
  function obj:getSpawnWorldOOBB()
    return { getCenter = function() return vec3(v.pos) end, getHalfExtents = function() return vec3(2.2, 1, 0.8) end }
  end
  return obj
end

-- the client spawns a vehicle (vehicle menu, Buy button, trailer...). The server may refuse it.
function World:clientSpawn(p, model, o)
  local cfgPath, cfgName = nil, nil
  if type(o.config) == "string" and o.config:find("%.pc$") then
    cfgPath = o.config
    cfgName = o.config:match("([^/]+)%.pc$")
  elseif o.config == nil then
    local m = self.models[model]
    if m then
      local keys = {}
      for k in pairs(m.configs) do keys[#keys + 1] = k end
      table.sort(keys)
      cfgName = keys[1]
      cfgPath = "vehicles/" .. model .. "/" .. cfgName .. ".pc"
    end
  end
  local vid = p.nextVid
  p.nextVid = vid + 1
  local gid = self.nextGid
  self.nextGid = gid + 1
  local v = { vid = vid, gid = gid, model = model, configName = cfgName, configPath = cfgPath,
              pos = o.pos and vec3(o.pos) or (p.current and vec3(p.current.pos) or vec3(p.spawnPos)),
              vel = vec3(0, 0, 0), yaw = 0, damage = 0,
              parts = (function()
                local parts = {}
                for _, sl in ipairs(partCatalogue(model)) do parts[sl.key] = sl.options[1][1] end
                return parts
              end)(),
              vars = { ["$tirepressure_F"] = 30, ["$tirepressure_R"] = 30 } }
  if (self.models[model] or {}).adjustable then
    v.vars["$spring_F"], v.vars["$spring_R"], v.vars["$damp_bump_F"] = 40000, 38000, 3000
  end
  if type(o.config) == "table" and type(o.config.parts) == "table" then   -- a config table (prebuilt trailer)
    v.parts = copy(o.config.parts)
    for k, val in pairs(o.config.vars or {}) do v.vars[k] = val end
  end
  v.data = vehData(p, v)
  v.fuel = 60
  v.batteryJ = 60 * 3600000   -- (electric cars) 60 kWh
  v.resetPos = vec3(v.pos)   -- where a plain reset takes it back to
  self:freshPhysics(p, v)
  local res = self:serverEvent("onVehicleSpawn", p.pid, vid, v.data)
  if res ~= nil and res ~= 0 then
    p.rejected = (p.rejected or 0) + 1
    return nil   -- BeamMP deletes a cancelled spawn
  end
  v.obj = makeObj(self, p, v)
  p.vehicles[vid] = v
  if o.autoEnterVehicle ~= false then p.current = v end
  if p.client then self:clientCall(p, "onVehicleSpawned", p.client.M.onVehicleSpawned, gid) end
  return v.obj
end

-- the player deletes a vehicle in game
function World:clientDelete(p, v)
  if not p.vehicles[v.vid] then return end
  self:dropVehicle(p, v.vid)
  self:serverEvent("onVehicleDeleted", p.pid, v.vid)
end

function World:dropVehicle(p, vid)
  local v = p.vehicles[vid]
  p.vehicles[vid] = nil
  if p.current == v then p.current = nil end
end

-- a parts/tuning change from the game: rebuilds the car (repairs it) and BeamMP sends the edit
function World:clientEditConfig(p, change, respawn)
  local v = p.current
  if not v then return end
  if change.parts then v.parts = copy(change.parts) end
  if change.vars then for k, val in pairs(change.vars) do v.vars[k] = val end end
  if respawn == false then return end
  self:freshPhysics(p, v)   -- a rebuild is a new vehicle Lua state with stock physics
  v.data = vehData(p, v)
  self:serverEvent("onVehicleEdited", p.pid, v.vid, v.data)
  self:serverEvent("onVehicleReset", p.pid, v.vid, "{}")
  if p.client then self:clientCall(p, "onVehicleSpawned", p.client.M.onVehicleSpawned, v.gid) end
end

-- the car's tuning variables as BeamNG describes them (vd.vdata.variables: min/max/default)
function World:varDefs(v)
  local defs = {}
  for name, val in pairs(v.vars) do
    if name:find("^%$spring") then defs[name] = { min = 20000, max = 80000, default = 40000, val = val }
    elseif name:find("^%$damp") then defs[name] = { min = 1000, max = 8000, default = 3000, val = val } end
  end
  return defs
end

-- Stock physics + a fresh vehicle-Lua state (what spawning or rebuilding a car gives you).
local BRAKE_TORQUE = 1500
-- Node positions relative to the vehicle, axis-aligned at yaw 0 (x forward, y left, z up).
-- A vehicle with a "load"/"cargo" part gets a bed frame plus 10 load nodes on top of it, so the
-- client's own CARGO_VLUA can measure how much of the load is still on the bed.
local function buildNodes(v)
  local nodes, pos = {}, {}
  local function add(x, y, z, origin)
    local cid = #nodes
    nodes[#nodes + 1] = { cid = cid, partOrigin = origin }
    pos[cid] = vec3(x, y, z)
  end
  local loadPart
  for slot, part in pairs(v.parts) do
    local sl = tostring(slot):lower()
    if type(part) == "string" and part ~= "" and (sl:find("load") or sl:find("cargo")) then loadPart = part end
  end
  for _, x in ipairs({ -2, 2 }) do for _, y in ipairs({ -1, 1 }) do for _, z in ipairs({ 0, 0.5 }) do
    add(x, y, z, v.model .. "_frame")
  end end end
  if loadPart then for i = 0, 9 do add(-1.5 + i / 3, 0, 0.8, loadPart) end end
  v.nodes, v.nodePos, v.loadPart = nodes, pos, loadPart
end

function World:freshPhysics(p, v)
  local w = self
  buildNodes(v)
  v.damage = 0
  local traits = w.models[v.model] or {}
  v.engine = { type = "combustionEngine", outputTorqueState = 1, slowIgnitionErrorChance = 0.01, fastIgnitionErrorChance = 0.01,
               starterTorque = 100, damageFrictionCoef = 1, damageIdleAVReadErrorRangeCoef = 1, isBroken = false,
               lockUp = function(e) e.isBroken, e.outputTorqueState = true, 0 end }
  v.turboDamage, v.abs, v.devices = 0, "realistic", { mainEngine = v.engine }
  if traits.turbo then
    v.engine.turbocharger = { isExisting = true, applyDeformGroupDamage = function(a) v.turboDamage = v.turboDamage + a end }
  else
    v.engine.turbocharger = { isExisting = false }
  end
  if traits.manual then
    v.devices.clutch = { type = "frictionClutch", clutchPermanentlyDamaged = false }
    v.devices.gearbox = { type = "manualGearbox", gearRatios = { [-1] = -3.5, [0] = 0, [1] = 3.5, [2] = 2.1, [3] = 1.4, [4] = 1.0 },
                          synchroWear = { [-1] = 0, [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 }, damageFrictionCoef = 1 }
  else
    v.devices.gearbox = { type = "automaticGearbox", damageFrictionCoef = 1 }
  end
  v.radiatorDamage, v.ignition, v.stalls, v.broken = 0, 3, v.stalls or 0, {}
  if not traits.noThermals then
    v.engine.thermals = { applyDeformGroupDamageRadiator = function(a) v.radiatorDamage = v.radiatorDamage + a end }
  end
  v.wheels = {}
  for i = 0, 3 do v.wheels[i] = { brakeTorque = BRAKE_TORQUE, padGlazingFactor = 0 } end
  local sb = sandbox.new({ label = "vlua:" .. p.name .. ":" .. v.model, allowWrite = function() return true end })
  sb.declare("tgFaults")
  sb.set("vec3", vec3)
  sb.set("RESET_PHYSICS", 1)
  sb.set("obj", {
    requestReset = function()   -- like BeamNG: the car goes back to its reset point, repaired
      if v.resetPos then v.pos = vec3(v.resetPos) end
      w:vehicleReset(p, v)
    end,
    queueGameEngineLua = function(_, code) w.queue[#w.queue + 1] = { to = "ge", pid = p.pid, code = code } end,
    getDirectionVector = function() return vecmath.dirFromQuat(vecmath.quatFromYaw(v.yaw or 0)) end,
    getDirectionVectorUp = function() return vec3(0, 0, 1) end,
    getNodePosition = function(_, cid) return vec3(v.nodePos[cid] or vec3(0, 0, 0)) end,
  })
  sb.set("powertrain", { getDevice = function(name) return v.devices[name] end, getDevices = function() return v.devices end })
  -- BeamNG's part conditions (career's used cars): mileage + paint wear. Like the game, setting them puts the
  -- engine/gearbox/clutch integrity values back to new, and a reset restores the conditions from their snapshot.
  v.odometer, v.paintVisual, v.partConditionCalls = 0, 1, 0
  sb.set("partCondition", { initConditions = function(_, odo, _, visual)
    v.odometer, v.paintVisual = odo or 0, visual or 1
    v.engine.damageFrictionCoef, v.engine.damageIdleAVReadErrorRangeCoef = 1, 1
    v.engine.slowIgnitionErrorChance, v.engine.fastIgnitionErrorChance = 0, 0
    if v.devices.gearbox then v.devices.gearbox.damageFrictionCoef = 1 end
    if v.devices.clutch then v.devices.clutch.clutchPermanentlyDamaged = false end
    v.partSnapshot = { odo = v.odometer, visual = v.paintVisual }
    v.partConditionCalls = v.partConditionCalls + 1
  end })
  sb.set("wheels", { wheels = v.wheels,
    setABSBehavior = function(b) v.abs = b end, resetABSBehavior = function() v.abs = "realistic" end })
  sb.set("energyStorage", { getStorages = function()
    if traits.noFuelTank then   -- an electric car: a battery, no fuel tank
      return { mainBattery = { type = "electricBattery", storedEnergy = v.batteryJ, remainingVolume = v.batteryJ / 3600000 } }
    end
    return { mainTank = { type = "fuelTank", remainingVolume = v.fuel, storedEnergy = v.fuel * 34.2e6,
                          setRemainingVolume = function(_, vol) v.fuel = math.max(0, math.min(60, vol)) end } }
  end })
  sb.set("electrics", { values = {}, setIgnitionLevel = function(level)
    if level == 0 and v.ignition ~= 0 then v.stalls = v.stalls + 1 end
    v.ignition = level
  end })
  sb.set("beamstate", { activateAutoCoupling = function() v.autoCouple = true end, toggleCouplers = function() v.autoCouple = true end,
    addDamage = function(d) v.damage = v.damage + d end,
    breakBreakGroup = function(g) v.broken[g] = true end })
  sb.set("v", { data = { nodes = v.nodes, beams = {
    { cid = 0, breakGroup = "headlight_L" }, { cid = 1, breakGroup = { "glass_windshield", "body" } }, { cid = 2, breakGroup = "hood_hinge" } } } })
  v.vlua = sb
end

-- what a physics reset does: repairs the car, stock engine and brakes; the vehicle-Lua state survives
function World:vehicleReset(p, v)
  v.damage = 0
  v.engine.outputTorqueState = 1
  v.engine.slowIgnitionErrorChance, v.engine.fastIgnitionErrorChance = 0.01, 0.01
  v.engine.damageFrictionCoef, v.engine.isBroken, v.engine.damageIdleAVReadErrorRangeCoef = 1, false, 1
  if v.devices.gearbox then v.devices.gearbox.damageFrictionCoef = 1 end
  v.radiatorDamage, v.broken, v.turboDamage = 0, {}, 0
  if v.devices.clutch then v.devices.clutch.clutchPermanentlyDamaged = false end
  if v.devices.gearbox then for i in pairs(v.devices.gearbox.synchroWear or {}) do v.devices.gearbox.synchroWear[i] = 0 end end   -- (automatics have none)
  for _, wd in pairs(v.wheels) do wd.padGlazingFactor = 0 end
  for _, wd in pairs(v.wheels) do wd.brakeTorque = BRAKE_TORQUE end
  if v.partSnapshot then   -- the game re-applies the part conditions' snapshot (mileage + "new" integrity values)
    v.odometer, v.paintVisual = v.partSnapshot.odo, v.partSnapshot.visual
    v.engine.slowIgnitionErrorChance, v.engine.fastIgnitionErrorChance = 0, 0
  end
  self:serverEvent("onVehicleReset", p.pid, v.vid, "{}")
  if p.client then self:clientCall(p, "onVehicleResetted", p.client.M.onVehicleResetted, v.gid) end
end

-- vehicle Lua sent with queueLuaCommand runs (next frame, as in the game) in that car's own state
function World:runVehicleLua(p, v, code)
  local c = p.client
  if c then c.vlua[#c.vlua + 1] = { gid = v.gid, code = code } end
  self.queue[#self.queue + 1] = { to = "vlua", pid = p.pid, vid = v.vid, gid = v.gid, code = code }
end

-- a player gets round the reset lock (R / Insert): the game resets the car
function World:resetCar(p)
  assert(p.current, p.name .. " has no car")
  self:vehicleReset(p, p.current)
  self:pump()
  self:step(0.25)
end

---------------------------------------------------------------------------------------------
-- time and messages
---------------------------------------------------------------------------------------------
function World:pump()
  local guard = 0
  while #self.queue > 0 do
    guard = guard + 1
    if guard > 10000 then error("message loop: more than 10000 messages in one pump") end
    local m = table.remove(self.queue, 1)
    if m.to == "server" then
      self:serverEvent(m.ev, m.pid, m.data)
    elseif m.to == "vlua" then
      local p = self.players[m.pid]
      local v = p and p.vehicles[m.vid]
      if v and v.gid == m.gid then
        local ok, err = xpcall(function() v.vlua.dostring(m.code, "=vlua") end, tb)
        if not ok then self.errors[#self.errors + 1] = "vehicle Lua (" .. p.name .. "): " .. err end
      end
    elseif m.to == "ge" then
      local p = self.players[m.pid]
      if p and p.client then
        local ok, err = xpcall(function() p.client.sb.dostring(m.code, "=queueGameEngineLua") end, tb)
        if not ok then self.errors[#self.errors + 1] = "client " .. p.name .. " queueGameEngineLua: " .. err end
      end
    else
      local p = self.players[m.pid]
      if p and p.client and (m.ev == "tg_ui" or m.ev == "tg_state") then
        local ok, t = pcall(json.decode, m.data)
        if ok then p.client[m.ev == "tg_ui" and "lastUi" or "lastState"] = t end
      end
      local fn = p and p.client and p.client.handlers[m.ev]
      if fn then self:clientCall(p, "event " .. m.ev, fn, m.data) end
    end
  end
end

-- advance the clock in frames of `frame` seconds (default 0.25): server timers, client updates, messages
function World:step(seconds, frame)
  frame = frame or 0.25
  local left = seconds or frame
  while left > 1e-9 do
    local dt = math.min(frame, left)
    left = left - dt
    self.t = self.t + dt
    for _, tm in ipairs(self.server.timers) do
      while self.t + 1e-9 >= tm.nextT do
        tm.nextT = tm.nextT + tm.every
        self:serverEvent(tm.ev)
      end
    end
    self:pump()
    for _, p in pairs(self.players) do
      if p.client then
        local c = p.client
        c.im.beginFrame()
        self:clientCall(p, "onUpdate", c.M.onUpdate, dt)
        self:clientCall(p, "onPreRender", c.M.onPreRender, dt)
        c.im.endFrame()
      end
    end
    self:pump()
  end
end

---------------------------------------------------------------------------------------------
-- actions a test performs as a player
---------------------------------------------------------------------------------------------
function World:chat(p, msg)
  local res = self:serverEvent("onChatMessage", p.pid, p.name, msg)
  if res ~= 1 then   -- not swallowed by the plugin: everyone sees it
    for _, q in pairs(self.players) do if q.connected then q.chat[#q.chat + 1] = p.name .. ": " .. msg end end
  end
  self:pump()
  self:step(0.25)
end

-- buy a car the way the vehicle menu does
function World:buy(p, model, config)
  local obj = self:clientSpawn(p, model, { config = config and ("vehicles/" .. model .. "/" .. config .. ".pc") or nil })
  self:pump()
  self:step(0.25)
  return obj
end

function World:car(p) return p.current end

-- put the player's car somewhere (no path in between)
function World:place(p, pos, yaw)
  local v = p.current
  assert(v, p.name .. " has no car to place")
  v.pos = vec3(pos)
  v.vel = vec3(0, 0, 0)
  if yaw then v.yaw = yaw end
  self:step(0.5)
end

-- litres per metre: rises with speed, so slower driving wins the economy run
local function fuelPerMetre(speed) return 0.00005 + 0.000002 * speed * speed end

-- drive several cars at once, each in a straight line at its own speed (m/s), ticking the world.
--   w:driveAll({ { alice, {x=900}, 40 }, { bob, {x=900}, 35 } })
function World:driveAll(legs)
  local frame = 0.25
  for _, leg in ipairs(legs) do
    assert(leg[1].current, leg[1].name .. " has no car to drive")
    leg.target = vec3(leg[2])
    leg.speed = leg[3] or 30
  end
  local moving = true
  while moving do
    moving = false
    for _, leg in ipairs(legs) do
      local v = leg[1].current
      if v then
        local d = leg.target - v.pos
        local len = d:length()
        if len >= 0.01 then
          moving = true
          local stepLen = math.min(len, leg.speed * frame)
          local dir = d:normalized()
          v.pos = v.pos + dir * stepLen
          for vid in pairs(leg[1].followers or {}) do   -- a hitched trailer and whatever stays on it
            local f = leg[1].vehicles[vid]
            if f then f.pos = f.pos + dir * stepLen end
          end
          v.vel = dir * leg.speed
          v.yaw = (math.atan2 or math.atan)(dir.y, dir.x)
          v.fuel = math.max(0, (v.fuel or 0) - stepLen * fuelPerMetre(leg.speed))
          -- an electric car uses about a third of the energy for the same driving
          v.batteryJ = math.max(0, (v.batteryJ or 0) - stepLen * fuelPerMetre(leg.speed) * 34.2e6 * 0.3)
        else
          v.vel = vec3(0, 0, 0)
        end
      end
    end
    if moving then self:step(frame) end
  end
  self:step(0.5)
end

-- drive one car in a straight line at `speed` m/s (default 30)
function World:drive(p, to, speed) self:driveAll({ { p, to, speed } }) end

-- step until cond() is true; fails after maxSeconds of game time
function World:waitFor(cond, maxSeconds, what)
  local waited = 0
  while not cond() do
    if waited >= (maxSeconds or 60) then error("timed out after " .. waited .. " s waiting for " .. (what or "a condition"), 2) end
    self:step(0.25)
    waited = waited + 0.25
  end
end

-- the clip ids this player's game has played so far (in order)
function World:heard(p)
  local out = {}
  for _, snd in ipairs(p.client.sounds) do out[#out + 1] = snd.clip end
  return out
end

-- did the game show this player a centre-screen message containing `text`? (ui_message)
function World:sawMessage(p, text)
  for _, m in ipairs(p.client.messages) do if m.msg:find(text, 1, true) then return true end end
  return false
end

-- the player's trailer and everything on it now follow their car (hitched; the load stays on)
function World:hitch(p)
  p.followers = {}
  for vid, v in pairs(p.vehicles) do if v ~= p.current then p.followers[vid] = true end end
end

-- n loose cargo items fall off and stay where they are
function World:dropCargo(p, n, model)
  for vid in pairs(p.followers or {}) do
    local v = p.vehicles[vid]
    if n > 0 and v and v.model == (model or "cones") then p.followers[vid] = nil; n = n - 1 end
  end
  assert(n == 0, "not enough cargo to drop")
end

-- the share of a prebuilt trailer's load still on its bed (the rest slides off, far below the bed)
function World:setLoad(p, frac)
  local trailer
  for _, v in pairs(p.vehicles) do if v.loadPart then trailer = v end end
  assert(trailer, p.name .. " has no trailer with a load")
  local keep, i = math.floor(frac * 10 + 0.5), 0
  for _, n in ipairs(trailer.nodes) do
    if n.partOrigin == trailer.loadPart then
      trailer.nodePos[n.cid] = (i < keep) and vec3(-1.5 + i / 3, 0, 0.8) or vec3(0, 0, -50)
      i = i + 1
    end
  end
end

function World:damage(p, amount)
  assert(p.current, p.name .. " has no car")
  p.current.damage = amount
end

---------------------------------------------------------------------------------------------
-- inspection
---------------------------------------------------------------------------------------------
-- the last window data (tg_ui) and HUD state (tg_state) the server sent this player
function World:ui(p) return p.client and p.client.lastUi end
function World:state(p) return p.client and p.client.lastState end

function World:consoleHas(text)   -- a server console line containing text (plain)
  for _, line in ipairs(self.console) do if line:find(text, 1, true) then return true end end
  return false
end
function World:chatHas(p, pattern, plain)
  for _, line in ipairs(p.chat) do
    if line:find(pattern, 1, plain ~= false) then return true end
  end
  return false
end
function World:chatSince(p, n)
  local out = {}
  for i = (n or 0) + 1, #p.chat do out[#out + 1] = p.chat[i] end
  return out
end

function World:serverConfig() return json.decode(assert(self.files["Resources/Server/TopGear/config.json"], "no config.json written")) end

-- everything that should never happen in a healthy run
function World:problems()
  local out = {}
  for _, e in ipairs(self.errors) do out[#out + 1] = e end
  for _, line in ipairs(self.console) do
    if line:find("error:", 1, true) or line:find("FAILED", 1, true) then out[#out + 1] = "server console: " .. line end
  end
  for _, p in pairs(self.players) do
    local c = p.client
    if c then
      for _, l in ipairs(c.log) do
        if l.level == "W" or l.level == "E" then out[#out + 1] = string.format("client %s log %s: %s", p.name, l.level, l.msg) end
      end
      for _, pr in ipairs(c.im.problems) do out[#out + 1] = "client " .. p.name .. " ui: " .. pr end
    end
  end
  return out
end

function World:assertClean()
  local pr = self:problems()
  if #pr > 0 then error("world has problems:\n  " .. table.concat(pr, "\n  "), 2) end
end

return World
