-- TOP GEAR CHALLENGE - BeamMP client extension (v0.1)
-- Packaged in Resources/Client/topgear.zip as lua/ge/extensions/topgear.lua
-- The server is authoritative; this file only displays state, blocks menus/resets,
-- reports damage + parts value, and performs paid repairs.

local M = {}

local state       = { phase = "idle" }
local faults      = { want = {}, restore = {}, test = false, applyAt = nil, report = false,
                      results = {}, waitSpawn = nil, physicsDeadline = nil, active = false }
local onPartsDiag, onFindGas, onRevertParts, onTrailerSave   -- defined further down, registered in tryRegister
local copyTable, readParts, lastGoodSnap, walkTree, ordinal  -- shared helpers/state, defined further down
local addLog                                                 -- window log, defined with the in-game window
local startMove                                              -- moving the car (tow/unstick), defined further down
local lights = { clock = 0, goUntil = nil, wasOn = false, who = nil, test = nil, openPtr = nil, errored = false }
local flag   = { clock = 0, untilT = nil, title = nil, detail = nil, pinned = false, openPtr = nil, errored = false }
local sound  = { idx = 1, method = nil, warned = false }   -- which way of playing sounds works on this game
local shop   = { cat = nil, tried = nil, err = nil }        -- the Parts tab's catalogue of the current car
local ui          = { open = false, data = nil, log = {}, reqTimer = 0, t = 0, sel = 1, confirm = {}, player = nil, failed = {} }
local stateAge    = 0
local registered  = false
local reportTimer = 0
local hudTimer    = 0
local partsValue  = nil   -- cached parts value; nil = recompute, false = unavailable
local lastTarget  = nil
local filterState = {}

local RESET_ACTIONS = {
  "reset_physics", "reset_all_physics", "reload_vehicle", "reload_all_vehicles",
  "loadHome", "saveHome", "recover_vehicle", "recover_vehicle_alt", "recover_to_last_road",
  "dropPlayerAtCamera", "dropPlayerAtCameraNoReset",
  "nodegrabberAction", "nodegrabberGrab", "nodegrabberRender",
  "editorToggle", "editorSafeModeToggle",
}
local VEHSEL_ACTIONS = { "vehicle_selector" }
local PARTS_ACTIONS  = { "parts_selector" }

local VERSION = "0.9.13"
local recentErrors = {}
local function warn(msg)
  log("W", "topgear", tostring(msg))
  recentErrors[#recentErrors + 1] = tostring(msg):sub(1, 160)
  if #recentErrors > 4 then table.remove(recentErrors, 1) end
end

-- input locks ----------------------------------------------------------------
local function setFilter(group, actions, blocked)
  if filterState[group] == blocked then return end
  local ok, err = pcall(function()
    core_input_actionFilter.setGroup(group, actions)
    core_input_actionFilter.addAction(0, group, blocked)
  end)
  if not ok then warn("actionFilter failed: " .. tostring(err)) end
  filterState[group] = blocked
end

local function applyFilters()
  local active = state.phase ~= "idle"
  setFilter("tg_reset",  RESET_ACTIONS,  active and not state.allowReset)
  setFilter("tg_vehsel", VEHSEL_ACTIONS, active and not state.allowVehicleSelector)
  setFilter("tg_parts",  PARTS_ACTIONS,  active and not state.allowParts)
end

-- which vehicle is my challenge car? -------------------------------------------
local function getCar()
  if state.carId and MPVehicleGE and MPVehicleGE.getGameVehicleID then
    local ok, gid = pcall(MPVehicleGE.getGameVehicleID, state.carId)
    if ok and gid and gid ~= -1 then
      local v = be:getObjectByID(gid)
      if v then return v end
    end
  end
  return be:getPlayerVehicle(0)
end

-- Star in a reasonably priced car: the car for your turn (spawned here, allowed by the server). Your own car - getCar()
-- - stays parked and keeps being the one that's reported, repaired and scored. (One table: 200-local limit.)
local Rpc = { veh = nil, job = nil }
function Rpc.car()   -- the RPC, while it exists
  local v = Rpc.veh
  if not v then return nil end
  local ok, alive = pcall(function() return be:getObjectByID(v:getID()) ~= nil end)
  if ok and alive then return v end
  Rpc.veh = nil
  return nil
end
function Rpc.driving() return Rpc.car() or getCar() end   -- what the HUD measures from

-- the Top Gear window's shared parts: boxes, hover help, the message log, the Start tab (filled in further down;
-- declared here because the tab functions above them use it - one local: the chunk is near Lua's 200)
local Tabs = {}

local function getDamage(v)
  local o = map and map.objects and map.objects[v:getID()]
  return (o and o.damage) or 0
end

-- Workshop billing: parts that only change the looks are free; everything else costs its game value.
-- Decided by the slot: a free word anywhere in the slot's name/path makes it free (so everything inside
-- "interior" is free), but a billed word in the slot's OWN name always means billed - wings, spoilers and
-- hoods change downforce or weight, so a "lip spoiler" or a "fiberglass hood" is paid for.
local FREE_SLOT_WORDS = { "skin", "paint", "livery", "decal", "sticker", "plate", "license", "licence", "badge",
  "emblem", "logo", "mirror", "trim", "interior", "seat", "steering_wheel", "steeringwheel", "dash", "gauge",
  "carpet", "door_panel", "doorpanel", "headliner", "visor", "radio", "speaker", "accessor", "hubcap",
  "wheelcover", "light", "lamp", "antenna", "mudflap", "horn", "glass", "window", "wiper", "bumper",
  "lip", "skirt", "flare", "fender", "grille", "grill", "bodykit", "body_kit" }
local BILLED_SLOT_WORDS = { "wing", "spoiler", "hood", "bonnet" }
local function slotLeaf(slot)   -- "/covet_body/covet_spoiler/" -> "covet_spoiler"
  slot = tostring(slot or "")
  return slot:match("([^/]+)/?$") or slot
end
local function isFreeSlot(slot)
  local full, leaf = tostring(slot or ""):lower(), slotLeaf(slot):lower()
  if leaf:find("mirror", 1, true) then return true end   -- a wing mirror is a mirror, not a wing
  for _, w in ipairs(BILLED_SLOT_WORDS) do if leaf:find(w, 1, true) then return false end end
  for _, w in ipairs(FREE_SLOT_WORDS) do if full:find(w, 1, true) then return true end end
  return false
end
M.isFreeSlot = isFreeSlot   -- for tests

-- Sum of jbeam "information.value" over the car's installed parts.
-- Used to bill workshop upgrades. Returns nil if this game version doesn't expose it.
local function getPartsValue(v)
  local ok, total = pcall(function()
    local vd = core_vehicle_manager.getVehicleData(v:getID())
    if not vd then return nil end
    local sum, found = 0, false
    -- path 1: processed vehicle data keeps the active parts
    local active = vd.vdata and vd.vdata.activeParts
    if type(active) == "table" then
      for key, part in pairs(active) do
        local val = type(part) == "table" and part.information and tonumber(part.information.value)
        local st = type(part) == "table" and part.slotType or ""
        local skip = isFreeSlot(key) or isFreeSlot(type(st) == "table" and table.concat(st, " ") or st)
        if val and not skip then sum = sum + val; found = true end
      end
      if found then return sum end
    end
    -- path 2: look each chosen part up through jbeam io
    local chosen = vd.chosenParts or (vd.config and vd.config.parts)
    if type(chosen) == "table" and vd.ioCtx then
      local jbeamIO = require("jbeam/io")
      for slot, partName in pairs(chosen) do
        if type(partName) == "string" and partName ~= "" and not isFreeSlot(slot) then
          local part = jbeamIO.getPart(vd.ioCtx, partName)
          local val = part and part.information and tonumber(part.information.value)
          if val then sum = sum + val; found = true end
        end
      end
    end
    return found and sum or nil
  end)
  if not ok then warn("parts value failed: " .. tostring(total)); return nil end
  return total
end

-- navigation arrows --------------------------------------------------------------
-- Ground arrows follow the AI road network. Several BeamNG versions name this API
-- differently, so try each and log which one worked (see the game console, filter "topgear").
local pathMethod, pathCarId, pathKey, reassertTimer = nil, nil, nil, 0

local function trySetPath(pos)
  local attempts = {
    { "core_groundMarkers.setPath",  function() return core_groundMarkers and core_groundMarkers.setPath end },
    { "core_groundMarkers.setFocus", function() return core_groundMarkers and core_groundMarkers.setFocus end },
    { "freeroam_bigMapMode.setNavFocus", function() return freeroam_bigMapMode and freeroam_bigMapMode.setNavFocus end },
  }
  for _, a in ipairs(attempts) do
    local okGet, fn = pcall(a[2])
    if okGet and type(fn) == "function" then
      local ok, err = pcall(fn, pos)
      if ok then return a[1] end
      warn(a[1] .. " failed: " .. tostring(err))
    end
  end
  return nil
end

local function applyPath(force)
  local t = state.target
  local key = t and string.format("%.1f,%.1f,%.1f", t.x, t.y, t.z) or "none"
  local car = getCar()
  local carId = car and car:getID() or -1
  if not force and key == pathKey and carId == pathCarId and (pathMethod or not t) then return end
  pathKey, pathCarId = key, carId
  if not t then trySetPath(nil); pathMethod = nil; return end
  pathMethod = trySetPath(vec3(t.x, t.y, t.z))
  log("I", "topgear", string.format("target '%s' at %s, arrows via %s", tostring(t.label), key, tostring(pathMethod or "NONE")))
end

-- Some versions clear the route on arrival or vehicle change; re-apply when that happens.
local function reassertPath(dt)
  reassertTimer = reassertTimer + dt
  if reassertTimer < 3 then return end
  reassertTimer = 0
  if not state.target then return end
  local lost = false
  pcall(function()
    if core_groundMarkers and core_groundMarkers.currentlyHasTarget then
      lost = not core_groundMarkers.currentlyHasTarget()
    end
  end)
  applyPath(lost)
end

-- HUD --------------------------------------------------------------------------
local CONDITION_NAMES = { [0] = "New", "Used", "Needs work", "Beater", "Death Trap" }   -- (the server sends them too)
local function commas(n)
  n = math.floor((n or 0) + 0.5)
  local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n < 0 and "-$" or "$") .. s
end

-- Arrow showing where the target is relative to the car's heading.
local ARROWS = { "↑", "↗", "→", "↘", "↓", "↙", "←", "↖" }
function M.compass(fx, fy, dx, dy)
  local atan2 = math.atan2 or math.atan
  local ccw = atan2(fx * dy - fy * dx, fx * dx + fy * dy)   -- + = target to the left
  local cw = (-math.deg(ccw)) % 360
  return ARROWS[math.floor((cw + 22.5) / 45) % 8 + 1]
end

local function hud()
  if state.phase == "idle" then return end
  local bits = { "TOP GEAR: " .. (state.title or "") }
  if state.traffic then bits[#bits + 1] = "TRAFFIC MODE" end
  if state.cash then bits[#bits + 1] = commas(state.cash) end
  if state.points then bits[#bits + 1] = string.format("%.1f pts", state.points) end
  if state.timeLeft then
    local left = state.timeLeft - stateAge
    if left > 0 then bits[#bits + 1] = string.format("%d:%02d left", math.floor(left / 60), math.floor(left % 60)) end
  end
  local t, v = state.target, Rpc.driving()
  if t and v then
    local pos = vec3(v:getPosition())
    local to = vec3(t.x, t.y, t.z) - pos
    local d = to:length()
    local dir = vec3(v:getDirectionVector())
    bits[#bits + 1] = string.format("%s %s %s", M.compass(dir.x, dir.y, to.x, to.y), t.label or "Target",
      d >= 1000 and string.format("%.1f km", d / 1000) or string.format("%d m", math.floor(d)))
  end
  ui_message(table.concat(bits, "  |  "), 2, "tg_hud", "flag")
end

local function drawTarget()
  local t = state.target
  if not t or state.phase == "idle" then return end
  local p, r = vec3(t.x, t.y, t.z), t.r or 10
  local ok = pcall(function()
    debugDrawer:drawCylinder(p, p + vec3(0, 0, 6), r, ColorF(1, 0.45, 0, 0.18))
    debugDrawer:drawCylinder(p, p + vec3(0, 0, 120), 0.8, ColorF(1, 0.45, 0, 0.6))  -- beacon, visible from afar
    debugDrawer:drawTextAdvanced(p + vec3(0, 0, 7), String(t.label or ""), ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 0, 180))
  end)
  if not ok then  -- older builds want Point3F
    pcall(function()
      debugDrawer:drawCylinder(p:toPoint3F(), (p + vec3(0, 0, 6)):toPoint3F(), r, ColorF(1, 0.45, 0, 0.18))
    end)
  end
end

-- server -> client -----------------------------------------------------------
-- The dealership in the game's own vehicle selector ---------------------------------------------------------
-- The selector screen gets its list from the 'sendVehicleList' UI hook (core_vehicles.requestList() sends it when
-- the screen opens; career mode swaps in its own list the same way). While the dealership is open we catch that
-- hook - whichever game function sends it - and swap in today's cars at today's prices ("Value"), with
-- "$5,500 as a Beater" (the car condition that would afford it) / "over budget" in the name. Thumbnails, filters and search keep working. Buying is still
-- spawning: the server checks and charges. Today's list is fetched in advance (dealership opening, cash changes)
-- so it's ready when the screen opens. If anything goes wrong the game's own list goes through untouched (the
-- server still refuses what isn't for sale). /tg diag reports what this game version does.
-- BeamNG 0.37+ rebuilt the selector (ui_vehicleSelector_general): it no longer uses 'sendVehicleList' but reads
-- every car through core_vehicles.getModelsData / getModel / getConfig (looked up on each call). While the
-- dealership is open those answer with today's cars only, priced and labelled, and the selector is told to
-- reload (clearCache), so its tiles, filters, search and grouping are all built from today's list.
local selector = { list = nil, trigger = nil, origTrigger = nil, seen = {}, delivered = 0, swapped = 0,
                   t = 0, askedAt = -99, sig = nil,
                   sale = nil, saleCount = 0, lookups = nil, lookupFns = nil, cache = {}, reloads = 0 }
-- the game's own vehicle data, even while the dealership's lookups are in place (our import and list building)
local function gameGetModel(model)
  local f = selector.lookups and selector.lookups.getModel or core_vehicles.getModel
  return f(model)
end
local function selFilters(list, ranges)   -- the game's createFilters (not exported): what the filter panel offers
  local filter = {}
  for _, item in ipairs(list) do
    for prop, val in pairs(item.aggregates or {}) do
      if ranges[prop] and type(val) == "table" and tonumber(val.min) and tonumber(val.max) then
        local f = filter[prop]
        if f then f.min, f.max = math.min(f.min, val.min), math.max(f.max, val.max)
        else filter[prop] = { min = val.min, max = val.max } end
      elseif type(val) == "table" then
        filter[prop] = filter[prop] or {}
        for k in pairs(val) do filter[prop][tostring(k)] = true end
      end
    end
  end
  return filter
end
local function selBuild(offers)
  local display
  pcall(function() display = (core_vehicles.getModelList(true) or {}).displayInfo end)
  local ranges = {}
  for _, r in ipairs((((display or {}).ranges or {}).all) or { "Years", "Value", "Weight", "Top Speed", "0-100 km/h",
                       "0-60 mph", "Weight/Power", "Off-Road Score" }) do ranges[r] = true end
  local models, configs = {}, {}
  for _, g in ipairs(offers or {}) do
    local okM, m = pcall(gameGetModel, g.model)
    if okM and type(m) == "table" and type(m.model) == "table" then
      local mine = {}
      local wanted = {}   -- { config object, offer }: a trim with no config (the plain dealer list) = every trim of the model
      for _, tr in ipairs(g.trims or {}) do
        if tr.config == nil then
          for _, src in pairs(m.configs or {}) do wanted[#wanted + 1] = { src, tr } end
        elseif type((m.configs or {})[tr.config]) == "table" then
          wanted[#wanted + 1] = { m.configs[tr.config], tr }
        end
      end
      for _, pair in ipairs(wanted) do
        local src, tr = pair[1], pair[2]
        local c = {}
        for k, v in pairs(src) do c[k] = v end
        c.aggregates = copyTable(src.aggregates or {})
        c.Value, c.aggregates.Value = tr.price, { min = tr.price, max = tr.price }
        local note = ""
        if tr.over then note = " - over budget"
        elseif (tonumber(tr.needs) or 0) > 0 then note = string.format(" - %s as a %s", commas(tr.condPrice), tostring(tr.cond)) end
        c.Name = string.format("%s (%s%s)%s", tostring(src.Name or tr.name), commas(tr.price), tr.est and ", est." or "", note)
        configs[#configs + 1] = c
        mine[#mine + 1] = c
      end
      if #mine > 0 then
        local mod = {}
        for k, v in pairs(m.model) do mod[k] = v end
        mod.aggregates = selFilters(mine, ranges)   -- the model's ranges cover only the trims for sale
        models[#models + 1] = mod
      end
    end
  end
  return { models = models, configs = configs, filters = selFilters(models, ranges), displayInfo = display }
end
local function selWanted() return state.phase == "dealer" and not state.traffic end
-- 0.37+ selector: today's cars through core_vehicles' lookups ------------------------------------------------
local function selLabel(text, tr)
  local note = ""
  if tr.over then note = " - over budget"
  elseif (tonumber(tr.needs) or 0) > 0 then note = string.format(" - %s as a %s", commas(tr.condPrice), tostring(tr.cond)) end
  return string.format("%s (%s%s)%s", tostring(text), commas(tr.price), tr.est and ", est." or "", note)
end
local function selSaleModel(model)   -- a model with only its trims for sale, priced (built once per list)
  if selector.cache[model] ~= nil then return selector.cache[model] or nil end
  local offers = selector.sale and selector.sale[model]
  local okM, m = pcall(selector.lookups.getModel, model)
  if not (offers and okM and type(m) == "table") then selector.cache[model] = false; return nil end
  local copy = {}
  for k, v in pairs(m) do copy[k] = v end
  copy.configs = {}
  for key, src in pairs(m.configs or {}) do
    local tr = offers[key] or offers["*"]
    if tr and type(src) == "table" then
      local c = {}
      for k, v in pairs(src) do c[k] = v end
      c.Value = tr.price
      if type(src.aggregates) == "table" then c.aggregates = copyTable(src.aggregates); c.aggregates.Value = { min = tr.price, max = tr.price } end
      c.Configuration = selLabel(src.Configuration or key, tr)
      c.Name = selLabel(src.Name or key, tr)
      copy.configs[key] = c
    end
  end
  if not next(copy.configs) then selector.cache[model] = false; return nil end
  selector.cache[model] = copy
  return copy
end
local function selLookupsOn() return selector.lookups ~= nil and selector.sale ~= nil and selWanted() end
local function selReload()   -- ask the 0.37+ selector to rebuild its list from the lookups
  local gen = rawget(_G, "ui_vehicleSelector_general")
  if type(gen) == "table" and type(gen.clearCache) == "function" and pcall(gen.clearCache) then selector.reloads = selector.reloads + 1 end
end
local function selWrapLookups()
  local cv = core_vehicles
  if type(cv) ~= "table" or type(cv.getModelsData) ~= "function" or type(cv.getModel) ~= "function" then return end
  local fns = selector.lookupFns
  if fns and cv.getModelsData == fns.getModelsData and cv.getModel == fns.getModel and cv.getConfig == fns.getConfig then return end
  local orig = { getModelsData = cv.getModelsData, getModel = cv.getModel, getConfig = cv.getConfig }
  selector.lookups, selector.cache = orig, {}
  fns = {
    getModelsData = function(...)
      local all = orig.getModelsData(...)
      if not selLookupsOn() or type(all) ~= "table" then return all end
      local out = {}
      for k, v in pairs(all) do if selSaleModel(k) then out[k] = v end end
      return out
    end,
    getModel = function(model, ...)
      if selLookupsOn() and selector.sale[model] then
        local m = selSaleModel(model)
        if m then return m end
      end
      return orig.getModel(model, ...)
    end,
    getConfig = orig.getConfig and function(model, key, ...)
      if selLookupsOn() and selector.sale[model] then
        local m = selSaleModel(model)
        if m and m.configs[key] then return m.configs[key] end
      end
      return orig.getConfig(model, key, ...)
    end or nil,
  }
  selector.lookupFns = fns
  cv.getModelsData, cv.getModel, cv.getConfig = fns.getModelsData, fns.getModel, fns.getConfig
  selReload()
end
local function selUnwrapLookups()
  local cv, fns, orig = core_vehicles, selector.lookupFns, selector.lookups
  if not fns then return end
  if type(cv) == "table" then
    if cv.getModelsData == fns.getModelsData then cv.getModelsData = orig.getModelsData end
    if cv.getModel == fns.getModel then cv.getModel = orig.getModel end
    if fns.getConfig and cv.getConfig == fns.getConfig then cv.getConfig = orig.getConfig end
  end
  selector.lookups, selector.lookupFns, selector.sale, selector.cache, selector.saleCount = nil, nil, nil, {}, 0
  selReload()
end
local function selSetSale(offers)   -- server offers -> { model = { config | "*" = offer } }
  local sale, n = {}, 0
  for _, g in ipairs(offers or {}) do
    for _, tr in ipairs(g.trims or {}) do
      sale[g.model] = sale[g.model] or {}
      sale[g.model][tr.config or "*"] = tr
      n = n + 1
    end
  end
  selector.sale, selector.saleCount, selector.cache = sale, n, {}
  if selector.lookupFns then selReload() end
end

local function selRequest(force)   -- ask the server for today's list (it changes with cash and faults)
  if not TriggerServerEvent or (not force and selector.t - selector.askedAt < 3) then return end
  selector.askedAt = selector.t
  TriggerServerEvent("tg_dealerlist_req", "")
end
local function selHook()   -- wrap guihooks.trigger (again, if the game replaced it)
  if type(guihooks) ~= "table" or type(guihooks.trigger) ~= "function" then
    if not selector.warned then selector.warned = true; warn("vehicle selector: no guihooks.trigger on this BeamNG version") end
    return
  end
  if selector.trigger and guihooks.trigger == selector.trigger then return end
  local orig = guihooks.trigger
  selector.origTrigger = orig
  selector.trigger = function(name, data, ...)
    if type(name) == "string" and name:lower():find("vehicle", 1, true) then selector.seen[name] = (selector.seen[name] or 0) + 1 end
    if name == "sendVehicleList" and selWanted() then
      selector.delivered = selector.delivered + 1
      if selector.list then selector.swapped = selector.swapped + 1; data = selector.list end
      selRequest(true)   -- a fresh one follows, in case cash or prices changed
    end
    return orig(name, data, ...)
  end
  guihooks.trigger = selector.trigger
end
local function selUnhook()
  if selector.trigger and type(guihooks) == "table" and guihooks.trigger == selector.trigger then guihooks.trigger = selector.origTrigger end
  selector.trigger, selector.origTrigger, selector.list, selector.sig = nil, nil, nil, nil
  selUnwrapLookups()
end
local function selUpdate(dt)   -- every frame: keep the hook in place while the dealership is open
  selector.t = selector.t + dt
  if not selWanted() then if selector.trigger or selector.lookupFns then selUnhook() end return end
  selHook()
  selWrapLookups()
  local sig = tostring(state.cash) .. "|" .. tostring(state.budget) .. "|" .. tostring(state.condition)
  if sig ~= selector.sig or not selector.list then
    if sig ~= selector.sig then selector.sig = sig; selRequest(true) else selRequest(false) end
  end
end
local function selDiag()
  local seen = {}
  for name, n in pairs(selector.seen) do seen[#seen + 1] = name .. " x" .. n end
  table.sort(seen)
  local ver = rawget(_G, "beamng_versiond") or rawget(_G, "beamng_version") or "?"
  local listText = not selWanted() and "not in use (the dealership isn't open)"
    or (selector.list and (#selector.list.configs .. " cars ready") or "not ready yet")
  return string.format("BeamNG %s | today's list: %s | hook %s | selector lists %d, replaced %d | lookups %s (%d for sale, reloads %d) | vehicle UI messages: %s",
    tostring(ver), listText, selector.trigger and "on" or "off", selector.delivered, selector.swapped,
    selector.lookupFns and "on" or "off", selector.saleCount or 0, selector.reloads,
    #seen > 0 and table.concat(seen, ", ") or "none yet (open the vehicle selector first)")
end
local function onDealerList(data)   -- server -> client: { offers = dealerOffers }
  local ok, t = pcall(jsonDecode, data)
  if not ok or type(t) ~= "table" or not selWanted() then return end
  selSetSale(t.offers)
  local okB, list = pcall(selBuild, t.offers)
  if okB and #list.configs == 0 and #(t.offers or {}) > 0 then okB, list = false, "none of today's cars were found in this game" end
  if not okB then
    if selector.lastErr ~= tostring(list) then selector.lastErr = tostring(list); warn("vehicle selector list: " .. tostring(list)) end
    selector.list = nil   -- the game's own list goes through instead
    return
  end
  selector.list = list
  -- refresh the screen if it's open (straight to the game's trigger: our own hook would ask for it again)
  pcall(function() (selector.origTrigger or guihooks.trigger)("sendVehicleList", list) end)
end
function M.openSelector()   -- the Dealership tab's button
  local ok, err = pcall(function() core_vehicles.openSelectorUI() end)
  if not ok then warn("couldn't open the vehicle selector: " .. tostring(err)) end
end

local function onState(data)
  local ok, t = pcall(jsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  -- the challenge has started (the dealership closed, or a saved one resumed): the window shows the Status tab
  if (state.phase == "dealer" or state.phase == "paused") and t.phase == "travel" then ui.selectStatus = true end
  state, stateAge = t, 0
  if ui.open then ui.reqTimer = math.min(ui.reqTimer, 0.2) end
  applyFilters()
  applyPath(false)
  if state.phase == "idle" and not faults.test then
    faults.want, faults.restore, faults.active = {}, {}, false
    faults.applyAt, faults.waitSpawn, faults.physicsDeadline, faults.report = nil, nil, nil, false
  end
  if state.phase == "idle" then ui_message("", 0, "tg_hud") else hudTimer = 0 end
end

-- Repair the car where it stands. A plain physics reset (obj:requestReset) puts the car back at its reset
-- point - where it spawned or was last reset - so BeamNG's own "reset here" is used: spawn.safeTeleport to the
-- car's current position (what the game's flip-upright helper does). Fallback: reset, then put it back.
local function repairInPlace(kind)
  local car = getCar()
  if not car then return end
  local pos = vec3(car:getPosition())
  local dir = vec3(car:getDirectionVector())
  local ok, err = pcall(function()
    if not (spawn and spawn.safeTeleport) then error("no spawn.safeTeleport on this version", 0) end
    spawn.safeTeleport(car, pos, quatFromDir(dir))
  end)
  if not ok then
    warn(kind .. " in place: " .. tostring(err) .. " - resetting and putting the car back")
    startMove(kind, { reset = true, pos = { x = pos.x, y = pos.y, z = pos.z + 0.3 }, dir = { x = dir.x, y = dir.y } })
  end
end

local function onRepair()
  repairInPlace("repair")
  partsValue = nil
  ui_message("The mechanics have fixed your car.", 5, "tg_msg", "build")
end

local function onMsg(text)
  ui_message(tostring(text), 4, "tg_msg", "flag")
end

-- /tg diag: report what this client sees back to the server
local function onDiag()
  applyPath(true)
  local r = { version = VERSION, phase = state.phase, pathMethod = pathMethod, errors = recentErrors, carId = state.carId,
              sound = sound.method }
  pcall(function() r.selector = selDiag() end)
  if faults.mileage then
    r.mileage = string.format("%s km - %s", (commas(math.floor(faults.mileage.m / 1000)):gsub("^%$", "")),
      faults.mileageStatus or "not applied yet")
  end
  if faults.pullStatus then r.pull = faults.pullStatus end
  local t = state.target
  if t then r.target = string.format("%s at (%.0f, %.0f, %.0f)", tostring(t.label), t.x, t.y, t.z) end
  pcall(function()
    r.gmLoaded  = core_groundMarkers ~= nil
    r.gmSetPath = core_groundMarkers ~= nil and core_groundMarkers.setPath ~= nil
    r.gmSetFocus = core_groundMarkers ~= nil and core_groundMarkers.setFocus ~= nil
    if core_groundMarkers and core_groundMarkers.currentlyHasTarget then r.hasTarget = core_groundMarkers.currentlyHasTarget() end
  end)
  pcall(function() r.bigMap = freeroam_bigMapMode ~= nil and freeroam_bigMapMode.setNavFocus ~= nil end)
  local car, pv = getCar(), be:getPlayerVehicle(0)
  r.carFound = car and car:getID() or nil
  r.playerVeh = pv and pv:getID() or nil
  if TriggerServerEvent then TriggerServerEvent("tg_diag_reply", jsonEncode(r)) end
end

-- /tg importprices: read every stock configuration's value - and the details car classes filter on (the same
-- attributes BeamNG's own vehicle menu filters by) - from this game install
local ATTR_FIELDS = { "Brand", "Country", "Body Style", "Type", "Drivetrain", "Transmission", "Fuel Type", "Propulsion",
  "Induction Type", "Config Type", "Performance Class", "Derby Class", "Commercial Class", "Source", "Years", "Value",
  "Weight", "Top Speed", "0-100 km/h", "0-60 mph", "Weight/Power", "Off-Road Score" }
local function trimAttrs(info, c)
  local a = {}
  for _, f in ipairs(ATTR_FIELDS) do
    local v = c[f]
    if v == nil then v = info[f] end
    if type(v) == "string" or type(v) == "number" then a[f] = v
    elseif type(v) == "table" and (tonumber(v.min) or tonumber(v.max)) then a[f] = { min = tonumber(v.min), max = tonumber(v.max) } end
  end
  return a
end
local function readModelPrices(model)
  local m = gameGetModel(model)
  if not (m and m.configs) then return nil, nil end
  local info = m.model or {}
  local modelName = ((info.Brand and (info.Brand .. " ") or "") .. (info.Name or model))
  local out = {}
  for key, c in pairs(m.configs) do
    local price = tonumber(c.Value)
    local trim = c.Configuration or c.Name or key
    out[#out + 1] = { config = c.key or key, name = modelName .. " " .. tostring(trim), price = price, attrs = trimAttrs(info, c) }
  end
  return out, modelName
end

local function onImport(data)
  local ok, req = pcall(jsonDecode, data)
  if not ok or type(req) ~= "table" then return end
  if req.all then   -- every model installed, mods included
    req.models = {}
    local okL, err = pcall(function()
      for key in pairs((core_vehicles.getModelList() or {}).models or {}) do req.models[#req.models + 1] = key end
    end)
    if not okL then warn("listing the game's cars failed: " .. tostring(err)) end
    table.sort(req.models)
  end
  if type(req.models) ~= "table" then return end
  for _, model in ipairs(req.models) do
    local okRead, configs, modelName = pcall(readModelPrices, model)
    local reply = { model = model }
    if okRead then reply.configs, reply.modelName = configs, modelName
    else reply.err = tostring(configs); warn("price import failed for " .. model .. ": " .. reply.err) end
    TriggerServerEvent("tg_import_reply", jsonEncode(reply))  -- one message per model keeps each packet small
  end
  if req.all then TriggerServerEvent("tg_import_reply", jsonEncode({ done = true, models = #req.models })) end
end

-- Problem-car faults -------------------------------------------------------------
-- Setup faults (tires, alignment, suspension, and accident damage's missing bumpers) change the car's configuration
-- and respawn it.
-- Physics faults (engine, brakes) run inside the car's own Lua and are re-applied after
-- every reset or respawn. The server says which faults this car should have; applying is
-- idempotent, and anything a fault changed is recorded in `restore` so it can be undone.

local function sanitize(v) return (tostring(v):gsub("[%c\"\\%]%[]", " ")) end

local VLUA = [==[
tgFaults = tgFaults or {}
local want, afterReset, mileage = %s, %s, %s
local out = {}
-- wearFresh: the engine/gearbox wear values are at their base (after a reset, or the mileage just set them):
-- the faults that scale them start again from there instead of undoing what they think is applied
local wearFresh = afterReset
-- mileage wear (the car's condition): BeamNG's own part conditions, as career's used-car dealership sets them.
-- Once per spawned car - the game keeps them through resets - and before the faults (it resets the same values).
-- (parts bought new since - mileage.fresh, by part name - start at 0 km; the rest of the car keeps its mileage)
local mileageKey = mileage and (tostring(mileage.m) .. "|" .. table.concat(mileage.fresh or {}, ","))
if mileage and tgFaults.mileage ~= mileageKey then
  local pc = rawget(_G, "partCondition")
  if pc and pc.initConditions then
    local perPart, fresh, nFresh = nil, {}, 0
    for _, name in ipairs(mileage.fresh or {}) do fresh[name] = true end
    if next(fresh) and v and v.data and type(v.data.activeParts) == "table" then
      perPart = {}
      for partId, name in pairs(v.data.activeParts) do
        if fresh[name] then perPart[partId] = { odometer = 0, integrityValue = 1, visualState = {} }; nFresh = nFresh + 1 end
      end
    end
    -- (visual = {}: no paint aging - the game does it by locking each mesh's colour, which stops repaints showing)
    local ok, err = pcall(pc.initConditions, perPart, mileage.m, nil, {})
    if ok then
      tgFaults.mileage, out._mileage, wearFresh = mileageKey, nFresh > 0 and ("ok, " .. nFresh .. " new part(s) at 0 km") or "ok", true
      tgFaults.ignOrig = nil   -- (the misfire chances have a new base)
    else
      out._mileage = "error: " .. tostring(err)
    end
  else
    out._mileage = "unavailable"
  end
end
if afterReset and tgFaults.engine then
  local e = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine")
  if not e or type(e.outputTorqueState) ~= "number" or math.abs(e.outputTorqueState - 1) < 1e-6 then tgFaults.engine = nil end
end
local function run(id, fn)
  if not want[id] and not tgFaults[id] then return end
  local ok, err = pcall(fn, want[id])
  if not ok then out[id] = "error: " .. tostring(err) end
end
run("engine", function(factor)
  local e = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine")
  if not e then out.engine = "unavailable"; return end
  local cur, target = tgFaults.engine or 1, factor or 1
  if math.abs(cur - target) > 1e-6 then
    if type(e.outputTorqueState) == "number" then e.outputTorqueState = e.outputTorqueState / cur * target
    elseif e.scaleOutputTorque then e:scaleOutputTorque(target / cur)
    else error("engine has no torque control") end
  end
  tgFaults.engine = factor
  out.engine = factor and "ok" or "removed"
end)
run("brakes", function(factor)
  if not (wheels and wheels.wheels) then out.brakes = "unavailable"; return end
  tgFaults.brakeOrig = tgFaults.brakeOrig or {}
  local n = 0
  for i, wd in pairs(wheels.wheels) do
    if type(wd) == "table" and tonumber(wd.brakeTorque) then
      if tgFaults.brakeOrig[i] == nil then tgFaults.brakeOrig[i] = wd.brakeTorque end
      wd.brakeTorque = tgFaults.brakeOrig[i] * (factor or 1)
      n = n + 1
    end
  end
  tgFaults.brakes = factor
  if n == 0 then out.brakes = "unavailable" else out.brakes = factor and "ok" or "removed" end
end)
local eng = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine")
run("ignition", function(add)   -- the engine's own misfire chances, raised (cut-outs are timed from the game side)
  if not eng or type(eng.slowIgnitionErrorChance) ~= "number" or type(eng.fastIgnitionErrorChance) ~= "number" then
    out.ignition = "unavailable"; return
  end
  tgFaults.ignOrig = tgFaults.ignOrig or { slow = eng.slowIgnitionErrorChance, fast = eng.fastIgnitionErrorChance }
  eng.slowIgnitionErrorChance = tgFaults.ignOrig.slow + (add or 0)
  eng.fastIgnitionErrorChance = tgFaults.ignOrig.fast + (add or 0) * 0.5
  tgFaults.ignition = add
  out.ignition = add and "ok" or "removed"
end)
run("cooling", function(amount)   -- radiator damage: the same thing a front-end crash does (a reset repairs it)
  local th = eng and eng.thermals
  if not (th and th.applyDeformGroupDamageRadiator) then out.cooling = "unavailable"; return end
  local cur, target = afterReset and 0 or (tgFaults.cooling or 0), amount or 0
  if math.abs(target - cur) > 1e-9 then th.applyDeformGroupDamageRadiator(target - cur) end
  tgFaults.cooling = amount
  out.cooling = amount and "ok" or "removed"
end)
run("fuelleak", function(rate)   -- needs a fuel tank; the draining itself is timed from the game side
  local tank = nil
  if energyStorage and energyStorage.getStorages then
    for _, st in pairs(energyStorage.getStorages()) do
      if type(st) == "table" and st.type == "fuelTank" and st.setRemainingVolume then tank = st end
    end
  end
  if not tank then out.fuelleak = "unavailable"; return end
  tgFaults.fuelleak = rate
  out.fuelleak = rate and "ok" or "removed"
end)
run("body", function(amount)   -- extra damage on the damage meter (a reset clears it) + some broken lights and glass
  if not (beamstate and beamstate.addDamage) then out.body = "unavailable"; return end
  local cur, target = afterReset and 0 or (tgFaults.body or 0), amount or 0
  if math.abs(target - cur) > 1e-9 then beamstate.addDamage(target - cur) end
  if amount and cur == 0 and beamstate.breakBreakGroup and v and v.data and v.data.beams then
    local groups, n = {}, 0
    for _, b in pairs(v.data.beams) do
      local g = b.breakGroup
      for _, name in ipairs(type(g) == "table" and g or { g }) do
        if type(name) == "string" and (name:find("light") or name:find("glass")) then groups[name] = true end
      end
    end
    for name in pairs(groups) do if n < 4 then beamstate.breakBreakGroup(name); n = n + 1 end end
  end
  tgFaults.body = amount
  out.body = amount and "ok" or "removed"
end)
local function devicesOfType(t)
  local list = {}
  if powertrain and powertrain.getDevices then
    for _, d in pairs(powertrain.getDevices()) do if type(d) == "table" and d.type == t then list[#list + 1] = d end end
  end
  return list
end
run("starter", function(f)   -- a weak starter: slow cranking before the engine catches
  if not eng or type(eng.starterTorque) ~= "number" then out.starter = "unavailable"; return end
  tgFaults.starterOrig = tgFaults.starterOrig or eng.starterTorque
  eng.starterTorque = tgFaults.starterOrig * (f or 1)
  tgFaults.starter = f
  out.starter = f and "ok" or "removed"
end)
run("clutch", function(on)   -- the clutch's own "permanently overheated" state: it slips (manual gearboxes)
  local clutches = devicesOfType("frictionClutch")
  if #clutches == 0 then out.clutch = "unavailable"; return end
  for _, d in ipairs(clutches) do d.clutchPermanentlyDamaged = on and true or false end
  tgFaults.clutch = on
  out.clutch = on and "ok" or "removed"
end)
-- worn synchros grind on quick shifts (manual gearboxes). Grind, never break: BeamNG adds wear while a shift grinds
-- (synchroWearCoef per gear) and at 100%% sets that gear's ratio to 0 - a gear with no drive. While the fault is on,
-- the wear coefficients are 0, so the wear stays at the fault's level; the originals come back when it's fixed.
run("synchros", function(wear)
  local n = 0
  tgFaults.syncCoef = tgFaults.syncCoef or setmetatable({}, { __mode = "k" })
  for _, d in ipairs(devicesOfType("manualGearbox")) do
    if type(d.synchroWear) == "table" and type(d.gearRatios) == "table" then
      local coef = type(d.synchroWearCoef) == "table" and d.synchroWearCoef or nil
      local orig = coef and tgFaults.syncCoef[d]
      if coef and wear and not orig then
        orig = {}
        for i, c in pairs(coef) do orig[i] = c end
        tgFaults.syncCoef[d] = orig
      end
      for i in pairs(d.gearRatios) do
        if wear then
          d.synchroWear[i] = math.max(d.synchroWear[i] or 0, math.min(wear, 0.95))
          if coef then coef[i] = 0 end
        else
          d.synchroWear[i] = 0
          if coef and orig and orig[i] ~= nil then coef[i] = orig[i] end
        end
      end
      if not wear and coef then tgFaults.syncCoef[d] = nil end
      n = n + 1
    end
  end
  if n == 0 then out.synchros = "unavailable"; return end
  tgFaults.synchros = wear
  out.synchros = wear and "ok" or "removed"
end)
run("turbo", function(amount)   -- the turbo's own damage (turbo cars; a reset repairs it)
  local tc = eng and eng.turbocharger
  if not (tc and tc.isExisting and tc.applyDeformGroupDamage) then out.turbo = "unavailable"; return end
  local cur, target = afterReset and 0 or (tgFaults.turbo or 0), amount or 0
  if math.abs(target - cur) > 1e-9 then tc.applyDeformGroupDamage(target - cur) end
  tgFaults.turbo = amount
  out.turbo = amount and "ok" or "removed"
end)
run("brakefade", function(g)   -- glazed pads: weaker and worse when hot (topped up from the game side)
  local n = 0
  if wheels and wheels.wheels then
    for _, wd in pairs(wheels.wheels) do
      if type(wd) == "table" and type(wd.padGlazingFactor) == "number" then wd.padGlazingFactor = g or 0; n = n + 1 end
    end
  end
  if n == 0 then out.brakefade = "unavailable"; return end
  tgFaults.brakefade = g
  out.brakefade = g and "ok" or "removed"
end)
run("abs", function(on)   -- ABS switched off
  if not (wheels and wheels.setABSBehavior) then out.abs = "unavailable"; return end
  if on then wheels.setABSBehavior("off") elseif wheels.resetABSBehavior then wheels.resetABSBehavior() end
  tgFaults.abs = on
  out.abs = on and "ok" or "removed"
end)
run("oilleak", function(f)   -- more engine friction: runs hot, a little less power (the blow-up is timed from the game side)
  if not eng or type(eng.damageFrictionCoef) ~= "number" then out.oilleak = "unavailable"; return end
  local cur, target = wearFresh and 1 or (tgFaults.oilMult or 1), 1 + (f or 0)
  eng.damageFrictionCoef = eng.damageFrictionCoef / cur * target
  tgFaults.oilMult = f and target or nil
  tgFaults.oilleak = f
  out.oilleak = f and "ok" or "removed"
end)
run("idle", function(f)   -- a rough idle: the engine's idle-speed error (what wear raises) - it hunts and can stall
  if not eng or type(eng.damageIdleAVReadErrorRangeCoef) ~= "number" then out.idle = "unavailable"; return end
  local cur, target = wearFresh and 1 or (tgFaults.idleMult or 1), f or 1
  eng.damageIdleAVReadErrorRangeCoef = eng.damageIdleAVReadErrorRangeCoef / cur * target
  tgFaults.idleMult = f
  tgFaults.idle = f
  out.idle = f and "ok" or "removed"
end)
run("gearbox", function(f)   -- a worn gearbox: more friction in whatever gearbox the car has
  local n = 0
  for _, d in pairs((powertrain and powertrain.getDevices and powertrain.getDevices()) or {}) do
    if type(d) == "table" and type(d.type) == "string" and d.type:find("Gearbox") and type(d.damageFrictionCoef) == "number" then
      local cur = wearFresh and 1 or (tgFaults.gearboxMult or 1)
      d.damageFrictionCoef = d.damageFrictionCoef / cur * (f or 1)
      n = n + 1
    end
  end
  if n == 0 then out.gearbox = "unavailable"; return end
  tgFaults.gearboxMult = f
  tgFaults.gearbox = f
  out.gearbox = f and "ok" or "removed"
end)
-- the alignment pulls to one side: the steering rack's "straight ahead" moved by `d` of full steering (- left,
-- + right). BeamNG works out each steering hydro's mapping (cOut/cIn) once at spawn - a reset keeps it - so the
-- originals are kept per hydro and the offset is always applied to them (never twice).
run("pull", function(d)
  local hs = rawget(_G, "hydros") and hydros.hydros
  if type(hs) ~= "table" then out.pull = "unavailable"; return end
  tgFaults.pullOrig = tgFaults.pullOrig or setmetatable({}, { __mode = "k" })
  local n = 0
  for _, h in pairs(hs) do
    if type(h) == "table" and h.inputSource == "steering_input" and type(h.cOut) == "number" and type(h.cIn) == "number"
       and type(h.multOut) == "number" and type(h.multIn) == "number" and type(h.inputFactor) == "number" then
      local o = tgFaults.pullOrig[h]
      if not o then o = { cOut = h.cOut, cIn = h.cIn }; tgFaults.pullOrig[h] = o end
      local shift = (d or 0) * h.inputFactor   -- what the steering input d would add to this hydro's command
      h.cOut, h.cIn = o.cOut + shift * h.multOut, o.cIn + shift * h.multIn
      n = n + 1
    end
  end
  tgFaults.pull = d
  if n == 0 then out.pull = "unavailable"; return end
  out.pull = d and string.format("ok, %%+.3f on %%d steering hydro(s)", d, n) or "removed"
end)
local parts = {}
for k, v in pairs(out) do parts[#parts + 1] = '"' .. k .. '":"' .. tostring(v):gsub('[%%c"\\%%]%%[]', ' ') .. '"' end
obj:queueGameEngineLua("extensions.topgear.onVehicleFaultReport([[{" .. table.concat(parts, ",") .. "}]])")
]==]

local PHYSICS = { engine = true, brakes = true, ignition = true, cooling = true, fuelleak = true, body = true,
                  starter = true, clutch = true, synchros = true, turbo = true, brakefade = true, abs = true, oilleak = true,
                  idle = true, gearbox = true }

local function sendFaultReport()
  if not faults.report then return end
  faults.report = false
  if TriggerServerEvent then
    TriggerServerEvent("tg_fault_report", jsonEncode({ results = faults.results, restore = faults.restore, test = faults.test }))
  end
end

local function runPhysicsFaults(afterReset)
  local car = getCar()
  if not car then return end
  local items = {}
  for id, f in pairs(faults.want) do
    if PHYSICS[id] then items[#items + 1] = string.format("[%q]=%s", id, tostring(tonumber(f.factor) or 1)) end
  end
  local ig = faults.want.ignition   -- (the ignition problems include a weak starter - 0.9.13: was its own fault)
  if ig and tonumber(ig.starter) then items[#items + 1] = string.format("starter=%.4f", tonumber(ig.starter)) end
  local al = faults.want.alignment   -- (alignment is a setup fault - toe - that also pulls: that part is physics)
  if al and tonumber(al.pull) and tonumber(al.pull) ~= 0 then items[#items + 1] = string.format("pull=%.5f", tonumber(al.pull)) end
  local m = faults.mileage
  local mileage = "nil"
  if type(m) == "table" and tonumber(m.m) then
    local fresh = {}
    for _, name in ipairs(type(m.fresh) == "table" and m.fresh or {}) do fresh[#fresh + 1] = string.format("%q", tostring(name)) end
    mileage = string.format("{m=%d,fresh={%s}}", math.floor(m.m), table.concat(fresh, ","))
  end
  local code = string.format(VLUA, "{" .. table.concat(items, ",") .. "}", afterReset and "true" or "false", mileage)
  car:queueLuaCommand(code)
  faults.physicsDeadline = 5
end

function M.onVehicleFaultReport(js)
  faults.physicsDeadline = nil
  local ok, t = pcall(jsonDecode, js)
  if ok and type(t) == "table" then
    for id, st in pairs(t) do
      if id == "_mileage" then
        faults.mileageStatus = tostring(st)
        if not tostring(st):find("^ok") then warn("mileage wear: " .. tostring(st)) end
      elseif id == "body" and st == "unavailable" and faults.want.body and faults.bumperStatus == "ok" then
        faults.results.body = "ok"   -- (no dents on this version, but the bumpers came off: it's applied)
      elseif id == "starter" then   -- part of the ignition problems: it counts as applied if either part is
        faults.starterStatus = tostring(st)
        if tostring(st):find("^error") then warn("weak starter: " .. tostring(st)) end
      elseif id == "pull" then   -- part of the alignment fault: it counts as applied if either the toe or the pull is
        faults.pullStatus = tostring(st)
        if tostring(st):find("^error") then warn("alignment pull: " .. tostring(st)) end
        if faults.want.alignment and tostring(st):find("^ok") and faults.results.alignment ~= "ok" then faults.results.alignment = "ok" end
      else
      faults.results[id] = st
      -- "unavailable" is normal (the server swaps it for another fault); only a real error is worth a warning
      if tostring(st):find("^error") then warn("fault " .. id .. ": " .. tostring(st)) end
      end
    end
  end
  -- (after the loop: the car reports both parts in no particular order)
  if faults.want.ignition and tostring(faults.starterStatus):find("^ok") and faults.results.ignition == "unavailable" then
    faults.results.ignition = "ok"
  end
  sendFaultReport()
end

local function applyConfigFaults()
  local car = getCar()
  if not car then faults.applyAt = 1; return end
  faults.results = {}
  local changedVars, changedParts = false, false
  local ok, err = pcall(function()
    local pm = core_vehicle_partmgmt
    local conf = pm.getConfig() or {}
    local vars, parts = conf.vars or {}, conf.parts or {}
    local defs = {}
    pcall(function()
      local vd = core_vehicle_manager.getVehicleData(car:getID())
      defs = (vd and vd.vdata and vd.vdata.variables) or {}
    end)
    local function info(n) return type(defs[n]) == "table" and defs[n] or {} end
    local function names(pattern, prefer)
      local out, seen = {}, {}
      local pats = type(pattern) == "table" and pattern or { pattern }
      for _, src in ipairs({ defs, vars }) do
        for n in pairs(src) do
          if type(n) == "string" and not seen[n] then
            for _, pat in ipairs(pats) do
              if n:find(pat) then seen[n] = true; out[#out + 1] = n; break end
            end
          end
        end
      end
      if prefer then
        local preferred = {}
        for _, n in ipairs(out) do if n:find(prefer) then preferred[#preferred + 1] = n end end
        if #preferred > 0 then out = preferred end
      end
      table.sort(out)
      return out
    end
    local function current(n)
      local v = vars[n]
      if v == nil then v = info(n).val or info(n).default end
      return tonumber(v)
    end

    local function varFault(id, pattern, prefer, target)
      local rec = faults.restore[id]
      if faults.want[id] then
        rec = rec or { vars = {} }
        rec.vars = rec.vars or {}
        local applied = 0
        for _, n in ipairs(names(pattern, prefer)) do
          if rec.vars[n] == nil then rec.vars[n] = current(n) or "default" end
          local orig = rec.vars[n]
          local t = target(orig ~= "default" and orig or tonumber(info(n).default), info(n), tonumber(faults.want[id].factor), n)
          if t then
            applied = applied + 1
            if vars[n] ~= t then vars[n] = t; changedVars = true end
          end
        end
        if applied == 0 then faults.results[id] = "unavailable"; faults.restore[id] = nil; return end
        faults.restore[id] = rec
        faults.results[id] = "ok"
      elseif rec and rec.vars then
        for n, orig in pairs(rec.vars) do
          local want = (orig ~= "default") and orig or nil
          if vars[n] ~= want then vars[n] = want; changedVars = true end
        end
        faults.restore[id] = nil
        faults.results[id] = "removed"
      end
    end

    -- tires: pressure down to factor x normal (never below the car's minimum)
    varFault("tires", "^%$tirepressure", nil, function(base, d, factor)
      base = base or 30
      local t = math.floor(base * (factor or 0.55) + 0.5)
      if tonumber(d.min) then t = math.max(tonumber(d.min), t) end
      return t
    end)
    -- alignment: front toe pushed min(factor, 1) of the way to its limit; any factor above 1 goes on the rear toe
    varFault("alignment", "^%$toe", nil, function(base, d, factor, name)
      local hi, lo = tonumber(d.max), tonumber(d.min)
      base = base or tonumber(d.default)
      if not (hi and lo and base) then return nil end
      factor = factor or 1.4
      local frac
      if tostring(name):find("_F") then frac = math.min(factor, 1)
      else frac = math.min(math.max(factor - 1, 0), 1) end
      if frac <= 0 then return nil end
      return base + (hi - base) * frac
    end)

    -- accident damage (body): empty the front and rear bumper slots (its dents and broken lights are physics, applied
    -- after the respawn). The parts record keeps its old key, "bumpers" (0.9.13: that was a fault of its own).
    local rec = faults.restore.bumpers
    if faults.want.body then
      rec = rec or { parts = {} }
      rec.parts = rec.parts or {}
      local n = 0
      for slot, part in pairs(parts) do
        if type(slot) == "string" and slot:find("bumper_[FR]/?$") then
          if rec.parts[slot] == nil and part ~= "" then rec.parts[slot] = part end
          if rec.parts[slot] ~= nil then
            n = n + 1
            if part ~= "" then parts[slot] = ""; changedParts = true end
          end
        end
      end
      if n == 0 then faults.bumperStatus = "no bumpers on this car"; faults.restore.bumpers = nil
      else faults.restore.bumpers = rec; faults.bumperStatus = "ok" end
    elseif rec and rec.parts then
      for slot, orig in pairs(rec.parts) do
        if parts[slot] ~= orig then parts[slot] = orig; changedParts = true end
      end
      faults.restore.bumpers = nil
      faults.bumperStatus = nil
    end

    -- suspension: softest springs and dampers (adjustable suspension); otherwise the anti-roll bars come off
    local srec = faults.restore.suspension
    if faults.want.suspension then
      srec = srec or { vars = {}, parts = {} }
      srec.vars, srec.parts = srec.vars or {}, srec.parts or {}
      local n = 0
      for _, nm in ipairs(names({ "^%$spring", "^%$damp" })) do
        local lo = tonumber(info(nm).min)
        if lo then
          if srec.vars[nm] == nil then srec.vars[nm] = current(nm) or "default" end
          n = n + 1
          if vars[nm] ~= lo then vars[nm] = lo; changedVars = true end
        end
      end
      if n == 0 then
        for slot, part in pairs(parts) do
          local leaf = (tostring(slot):match("([^/]+)/?$") or tostring(slot)):lower()
          if leaf:find("sway", 1, true) or leaf:find("antiroll", 1, true) or leaf:find("_arb", 1, true) then
            if srec.parts[slot] == nil and part ~= "" then srec.parts[slot] = part end
            if srec.parts[slot] ~= nil then
              n = n + 1
              if part ~= "" then parts[slot] = ""; changedParts = true end
            end
          end
        end
      end
      if n == 0 then faults.results.suspension = "unavailable"; faults.restore.suspension = nil
      else faults.restore.suspension = srec; faults.results.suspension = "ok" end
    elseif srec then
      for nm, orig in pairs(srec.vars or {}) do
        local want = (orig ~= "default") and orig or nil
        if vars[nm] ~= want then vars[nm] = want; changedVars = true end
      end
      for slot, orig in pairs(srec.parts or {}) do
        if parts[slot] ~= orig then parts[slot] = orig; changedParts = true end
      end
      faults.restore.suspension = nil
      faults.results.suspension = "removed"
    end

    if changedParts or changedVars then
      faults.waitSpawn = 8          -- armed before the respawn can fire
      faults.ownRebuild = 10        -- that rebuild is the mod's own change: a new baseline, not something to bill
    end
    if changedParts and changedVars then
      pm.setPartsConfig(parts, false)
      pm.setConfigVars(vars, true)
    elseif changedParts then
      pm.setPartsConfig(parts, true)
    elseif changedVars then
      pm.setConfigVars(vars, true)
    end
  end)
  if not ok then
    warn("setup faults failed: " .. tostring(err))
    for _, id in ipairs({ "tires", "alignment", "suspension" }) do
      if faults.want[id] then faults.results[id] = "error: " .. sanitize(err) end
    end
    changedVars, changedParts = false, false
    faults.waitSpawn = nil
  end
  if not (changedVars or changedParts) then runPhysicsFaults(false) end   -- otherwise after the respawn
end

local function onFaults(data)
  local ok, t = pcall(jsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  faults.want = {}
  for _, f in ipairs(t.faults or {}) do if type(f) == "table" and f.id then faults.want[f.id] = f end end
  faults.restore = type(t.restore) == "table" and t.restore or {}
  faults.test = t.test and true or false
  faults.mileage = type(t.mileage) == "table" and t.mileage or nil
  faults.active = next(faults.want) ~= nil or next(faults.restore) ~= nil or faults.mileage ~= nil
  if faults.test or not (faults.want.oilleak and faults.want.oilleak.doomed) then faults.oilBlown, faults.blowAt = false, nil end
  faults.report = true
  faults.applyAt = 0.5   -- let a fresh purchase finish spawning first
end

-- the fuel leak: litres drained from every fuel tank (goes through string.format)
local LEAK_VLUA = [[
local litres = %f
if energyStorage and energyStorage.getStorages then
  for _, st in pairs(energyStorage.getStorages()) do
    if type(st) == "table" and st.type == "fuelTank" and st.setRemainingVolume then
      st:setRemainingVolume(math.max(0, (st.remainingVolume or 0) - litres))
    end
  end
end
]]
-- glazed pads: keep them glazed (the game may let glazing recover as the brakes cool)
local GLAZE_VLUA = [[
local g = %f
if wheels and wheels.wheels then
  for _, wd in pairs(wheels.wheels) do
    if type(wd) == "table" and type(wd.padGlazingFactor) == "number" then wd.padGlazingFactor = math.max(wd.padGlazingFactor, g) end
  end
end
]]
-- a doomed engine lets go: BeamNG's own engine failure (the state oil starvation ends in)
local BLOW_VLUA = [[
local e = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine")
if e and e.lockUp then e:lockUp() end
]]
local LEAK_PHASES = { travel = true, countdown = true, event = true, finale = true }
local CUTOUT_PHASES = { travel = true, event = true, finale = true }   -- never during a countdown

-- faults that act over time: the fuel leak drains, the ignition fault kills the engine now and then.
-- In a challenge only on the road; an admin's fault test (/tg fault test) acts any time, cut-outs sooner.
local function updateTimedFaults(dt)
  local leak = faults.want.fuelleak
  if leak and faults.results.fuelleak == "ok" and (faults.test or LEAK_PHASES[state.phase]) then
    faults.leakT = (faults.leakT or 0) + dt
    if faults.leakT >= 5 then
      local litres = (tonumber(leak.factor) or 0.5) / 60 * faults.leakT
      faults.leakT = 0
      local car = getCar()
      if car then pcall(function() car:queueLuaCommand(string.format(LEAK_VLUA, litres)) end) end
    end
  end
  local glaze = faults.want.brakefade
  if glaze and faults.results.brakefade == "ok" then
    faults.glazeT = (faults.glazeT or 0) + dt
    if faults.glazeT >= (tonumber(glaze.refresh) or 0.5) then   -- (hard braking scrubs glazing off within seconds)
      faults.glazeT = 0
      local car = getCar()
      if car then pcall(function() car:queueLuaCommand(string.format(GLAZE_VLUA, tonumber(glaze.factor) or 1)) end) end
    end
  end
  local oil = faults.want.oilleak
  if oil and oil.doomed and faults.results.oilleak == "ok" and not faults.oilBlown and (faults.test or CUTOUT_PHASES[state.phase]) then
    local car = getCar()
    local fast = true   -- only hard driving counts (about 54 km/h and up); if the speed can't be read, all driving does
    pcall(function() fast = vec3(car:getVelocity()):length() > 15 end)
    if car and fast then
      if not faults.blowAt then
        local lo, hi = tonumber(oil.blowMin) or 60, tonumber(oil.blowMax) or 600
        if faults.test then lo, hi = 20, 40 end
        faults.blowAt = lo + math.random() * math.max(0, hi - lo)
      end
      faults.blowAt = faults.blowAt - dt
      if faults.blowAt <= 0 then
        faults.blowAt, faults.oilBlown = nil, true
        pcall(function() car:queueLuaCommand(BLOW_VLUA) end)
        ui_message("BANG! Your engine has let go. That's a tow.", 6, "tg_msg", "warning")
        if TriggerServerEvent and not faults.test then TriggerServerEvent("tg_engine_blown", "") end
      end
    end
  end
  local ign = faults.want.ignition
  if ign and faults.results.ignition == "ok" and (faults.test or CUTOUT_PHASES[state.phase]) then
    if not faults.cutAt then
      local lo, hi = tonumber(ign.cutoutMin) or 90, tonumber(ign.cutoutMax) or 240
      if faults.test then lo, hi = 15, 30 end   -- a test shouldn't make the admin wait minutes
      faults.cutAt = lo + math.random() * math.max(0, hi - lo)
    end
    faults.cutAt = faults.cutAt - dt
    if faults.cutAt <= 0 then
      faults.cutAt = nil
      local car = getCar()
      if car then
        pcall(function() car:queueLuaCommand("if electrics and electrics.setIgnitionLevel then electrics.setIgnitionLevel(0) end") end)
        ui_message("Your engine just died! Restart it.", 5, "tg_msg", "warning")
      end
    end
  else
    faults.cutAt = nil
  end
end

local function updateFaults(dt)
  if faults.ownRebuild then
    faults.ownRebuild = faults.ownRebuild - dt
    if faults.ownRebuild <= 0 then faults.ownRebuild = nil end
  end
  local okT, errT = pcall(updateTimedFaults, dt)
  if not okT and not faults.timedErrored then faults.timedErrored = true; warn("timed faults: " .. tostring(errT)) end
  if faults.applyAt then
    faults.applyAt = faults.applyAt - dt
    if faults.applyAt <= 0 then faults.applyAt = nil; applyConfigFaults() end
  end
  if faults.waitSpawn then
    faults.waitSpawn = faults.waitSpawn - dt
    if faults.waitSpawn <= 0 then faults.waitSpawn = nil; runPhysicsFaults(false) end  -- no respawn seen; try anyway
  end
  if faults.physicsDeadline then
    faults.physicsDeadline = faults.physicsDeadline - dt
    if faults.physicsDeadline <= 0 then
      faults.physicsDeadline = nil
      for id in pairs(faults.want) do
        if PHYSICS[id] and not faults.results[id] then faults.results[id] = "error: no reply from the car" end
      end
      sendFaultReport()
    end
  end
end

-- Tow + unstick: moving the car -------------------------------------------------------
-- The server decides where the car goes; this moves it without a reset where possible
-- (unstick keeps all damage), verifies it ended up upright and facing the right way,
-- and reports the method that worked.
local move = nil

local function flatDir(v)
  if not v then return nil end
  local d = vec3(v.x, v.y, 0)
  if d:length() < 0.01 then return nil end
  return d:normalized()
end

local function moveReport(ok, method, detail)
  if TriggerServerEvent and move then
    TriggerServerEvent("tg_move_report", jsonEncode({ kind = move.kind, ok = ok, method = method or "none", detail = tostring(detail or "") }))
  end
  if not ok then warn(tostring(move and move.kind) .. " failed: " .. tostring(detail)) end
  move = nil
end

local function rotationCandidates(car, dir)
  local out = {}
  if dir and quatFromDir then
    for _, d in ipairs({ dir, -dir }) do
      local ok, q = pcall(quatFromDir, d, vec3(0, 0, 1))
      if ok and q then out[#out + 1] = q end
    end
  end
  if #out == 0 then
    local ok, q = pcall(function() return quat(car:getRotation()) end)
    if ok and q then out[#out + 1] = q end
  end
  return out
end

local function setPose(car, pos, q)
  if car.setPositionRotation then
    car:setPositionRotation(pos.x, pos.y, pos.z, q.x, q.y, q.z, q.w)
    return "setPositionRotation"
  end
  if spawn and spawn.safeTeleport then
    spawn.safeTeleport(car, pos, q, nil, nil, nil, nil, false)
    return "safeTeleport"
  end
  error("no teleport function on this BeamNG version")
end

local function poseOK(car, dir)
  local okU, up = pcall(function() return vec3(car:getDirectionVectorUp()) end)
  if okU and up and up.z < 0.8 then return false end
  if dir then
    local okF, f = pcall(function() return flatDir(vec3(car:getDirectionVector())) end)
    if okF and f and f:dot(dir) < 0.7 then return false end
  end
  return true
end

startMove = function(kind, t)
  local car = getCar()
  if not car then return end
  move = { kind = kind, t = 0, reset = t.reset, config = t.config, idx = 1 }
  if kind == "unstick" then
    local pos = vec3(car:getPosition())
    move.pos = pos + vec3(0, 0, 1.2)
    move.dir = flatDir(vec3(car:getDirectionVector()))
  else
    move.pos = t.pos and vec3(t.pos.x, t.pos.y, t.pos.z) or nil
    move.dir = t.dir and flatDir(vec3(t.dir.x, t.dir.y, 0)) or flatDir(vec3(car:getDirectionVector()))
  end
  move.stage = move.config and "config" or "reset"
end

local function updateMove(dt)
  if not move then return end
  move.t = move.t + dt
  local car = getCar()
  if not car then if move.t > 10 then moveReport(false, nil, "car not found") end return end
  if move.stage == "config" then
    if not move.started then
      move.started, move.t = true, 0
      faults.ownRebuild = 10   -- restoring the car's upgrades: the mod's own change, not something to bill
      local ok, err = pcall(function()
        local pm = core_vehicle_partmgmt
        local c = move.config
        if type(c.parts) == "table" and type(c.vars) == "table" then
          pm.setPartsConfig(c.parts, false); pm.setConfigVars(c.vars, true)
        elseif type(c.parts) == "table" then pm.setPartsConfig(c.parts, true)
        elseif type(c.vars) == "table" then pm.setConfigVars(c.vars, true) end
      end)
      if not ok then warn("couldn't restore the car's upgrades: " .. tostring(err)); move.stage, move.t = "reset", 0 end
    elseif move.spawned or move.t > 4 then
      move.stage, move.t = "reset", 0
    end
  elseif move.stage == "reset" then
    if move.reset and not move.resetSent then
      move.resetSent, move.t = true, 0
      car:queueLuaCommand("obj:requestReset(RESET_PHYSICS)")
    elseif not move.reset or move.t > 0.7 then
      if not move.pos then moveReport(true, "reset", "repaired in place"); return end
      move.stage, move.t = "place", 0
    end
  elseif move.stage == "place" then
    move.cands = move.cands or rotationCandidates(car, move.dir)
    local q = move.cands[move.idx]
    if not q then moveReport(false, nil, "no usable rotation"); return end
    local ok, res = pcall(setPose, car, move.pos, q)
    if not ok then moveReport(false, nil, res); return end
    move.method, move.stage, move.t = res, "verify", 0
  elseif move.stage == "verify" and move.t > 0.4 then
    if poseOK(car, move.dir) then moveReport(true, move.method, "candidate " .. move.idx); return end
    move.idx = move.idx + 1
    if move.cands[move.idx] then move.stage = "place"
    else moveReport(true, move.method, "placed, but orientation not verified") end
  end
end

local function onRespawn(data)
  local ok, t = pcall(jsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  if t.spawn and t.model then   -- the car was lost: bring it back (the server treats that as a tow)
    pcall(function() core_vehicles.spawnNewVehicle(t.model, t.config and { config = t.config } or {}) end)
    return
  end
  repairInPlace("respawn")   -- "respawn on the spot": a fresh car right where it is
end

local function onTow(data)
  local ok, t = pcall(jsonDecode, data)
  if ok and type(t) == "table" then startMove(t.kind == "restore" and "restore" or "tow", t) end   -- (restore: after a crash/rejoin)
end
local function onUnstick() startMove("unstick", {}) end

-- Trailer delivery: spawn a trailer behind the car, then loose cargo on its deck --------
local trailerJob, spawnedTest = nil, {}

-- bounding box of a spawned object: centre + half extents (x/y horizontal, z up), or nil
local function bbox(obj)
  local ok, c, h = pcall(function()
    local b = obj:getSpawnWorldOOBB()
    return vec3(b:getCenter()), vec3(b:getHalfExtents())
  end)
  if ok and c and h then return c, h end
  local ok2, cx, cy, cz = pcall(function() return be:getObjectOOBBCenterXYZ(obj:getID()) end)
  local ok3, hx, hy, hz = pcall(function() return be:getObjectOOBBHalfExtentsXYZ(obj:getID()) end)
  if ok2 and cx then return vec3(cx, cy, cz), (ok3 and hx) and vec3(hx, hy, hz) or nil end
  return nil
end
local function halfLength(h) return h and math.max(h.x, h.y) or nil end

local function couple(car, alsoTrailer)
  local code = "if beamstate then if beamstate.activateAutoCoupling then beamstate.activateAutoCoupling() " ..
               "elseif beamstate.toggleCouplers then beamstate.toggleCouplers() end end"
  pcall(function() car:queueLuaCommand(code) end)
  if alsoTrailer then pcall(function() alsoTrailer:queueLuaCommand(code) end) end
end

local function spawnProp(model, pos, rot, config)
  local opts = { pos = pos, rot = rot, autoEnterVehicle = false }
  if config ~= nil then opts.config = config end
  return core_vehicles.spawnNewVehicle(model, opts)
end

-- the prebuilt trailer's load: how much of it is still on the bed (0..1), measured in the trailer's own Lua
local activeTrailer, activeLoad, cargoValue = nil, nil, nil
function M.onCargo(v)
  v = tonumber(v)
  if v and v >= 0 then cargoValue = v else cargoValue = nil end
end
local CARGO_VLUA = [==[
local LOAD = %s
local fwd, up = vec3(obj:getDirectionVector()), vec3(obj:getDirectionVectorUp())
local right = fwd:cross(up)
local lo, hi, loads = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }, {}
for _, n in pairs(v.data.nodes) do
  local p = vec3(obj:getNodePosition(n.cid))
  local a = { p:dot(fwd), p:dot(right), p:dot(up) }
  if LOAD[tostring(n.partOrigin or "")] then loads[#loads + 1] = a
  else for i = 1, 3 do lo[i] = math.min(lo[i], a[i]); hi[i] = math.max(hi[i], a[i]) end end
end
local on = 0
for _, a in ipairs(loads) do
  if a[1] >= lo[1] - 0.3 and a[1] <= hi[1] + 0.3 and a[2] >= lo[2] - 0.3 and a[2] <= hi[2] + 0.3
     and a[3] >= lo[3] - 0.5 and a[3] <= hi[3] + 2.5 then on = on + 1 end
end
obj:queueGameEngineLua("extensions.topgear.onCargo(" .. string.format("%%.3f", #loads > 0 and on / #loads or -1) .. ")")
]==]
local function measureCargo()
  if not (activeTrailer and activeLoad) then return end
  local items = {}
  for _, name in ipairs(activeLoad) do items[#items + 1] = string.format("[%q]=true", name) end
  local ok = pcall(function() activeTrailer:queueLuaCommand(string.format(CARGO_VLUA, "{" .. table.concat(items, ",") .. "}")) end)
  if not ok then activeTrailer, activeLoad, cargoValue = nil, nil, nil end
end

local function trailerReport(ok, hasTrailer, nCargo, err, onDeck)
  if TriggerServerEvent then
    TriggerServerEvent("tg_trailer_report", jsonEncode({ ok = ok, trailer = hasTrailer, cargo = nCargo, onDeck = onDeck,
      err = err and tostring(err) or nil }))
  end
  if not ok then warn("trailer: " .. tostring(err)) end
end

local function onTrailer(data)
  local ok, t = pcall(jsonDecode, data)
  if ok and type(t) == "table" then trailerJob = { t = t, stage = "wait", timer = 0.5 } end
end

-- tg_rpc { model, config, pos, look }: your turn - a fresh RPC on the start line, facing the first checkpoint
function Rpc.onStart(data)
  local ok, t = pcall(jsonDecode, data)
  if ok and type(t) == "table" and t.model and type(t.pos) == "table" then Rpc.job = { t = t, stage = "spawn", timer = 0.3 } end
end
function Rpc.onEnd()   -- tg_rpc_end: the turn is over - back into your own car
  Rpc.job = nil
  local v = Rpc.car()
  if v then pcall(function() v:delete() end) end   -- (normally the server has removed it already)
  Rpc.veh = nil
  local own = getCar()
  if own then pcall(function() be:enterVehicle(0, own) end) end
end
function Rpc.update(dt)
  local job = Rpc.job
  if not job then return end
  job.timer = job.timer - dt
  if job.timer > 0 then return end
  local t = job.t
  if job.stage == "spawn" then
    local ok, err = pcall(function()
      local pos = vec3(t.pos.x, t.pos.y, t.pos.z)
      local dir
      if type(t.look) == "table" then dir = vec3(t.look.x - pos.x, t.look.y - pos.y, 0) end
      if not dir or dir:length() < 1 then local own = getCar(); dir = own and vec3(own:getDirectionVector()) or vec3(0, 1, 0); dir.z = 0 end
      dir = dir:normalized()
      local old = Rpc.car()
      if old then pcall(function() old:delete() end) end
      local opts = { pos = pos + vec3(0, 0, 0.5), rot = quatFromDir(dir, vec3(0, 0, 1)), autoEnterVehicle = true }
      if t.config then opts.config = t.config end
      Rpc.veh = core_vehicles.spawnNewVehicle(t.model, opts)
      if not Rpc.veh then error("the game didn't spawn it") end
      job.pos, job.dir, job.stage, job.timer = pos, dir, "place", 0.5
    end)
    if not ok then warn("reasonably priced car: couldn't spawn " .. tostring(t.model) .. ": " .. tostring(err)); Rpc.job = nil end
  elseif job.stage == "place" then
    local v = Rpc.car()
    if not v then Rpc.job = nil; return end
    -- BeamNG's own "reset here" on the brand-new car: on the ground, clear of the cars waiting at the start
    local ok, err = pcall(function() spawn.safeTeleport(v, job.pos, quatFromDir(job.dir, vec3(0, 0, 1))) end)
    if not ok then warn("reasonably priced car: placing it failed: " .. tostring(err)) end
    pcall(function() be:enterVehicle(0, v) end)
    job.stage, job.timer = "verify", 0.5
  else   -- facing the wrong way? (quatFromDir's convention isn't confirmed on every version) - turn it round
    local v = Rpc.car()
    Rpc.job = nil
    if not v then return end
    pcall(function()
      local d = vec3(v:getDirectionVector())
      if d.x * job.dir.x + d.y * job.dir.y < 0 then spawn.safeTeleport(v, job.pos, quatFromDir(-job.dir, vec3(0, 0, 1))) end
    end)
  end
end

local function updateTrailer(dt)
  local job = trailerJob
  if not job then return end
  if move then return end                    -- a tow delivery finishes first
  job.timer = job.timer - dt
  if job.timer > 0 then return end
  local car = getCar()
  if not car then trailerReport(false, false, 0, "no car"); trailerJob = nil; return end
  local t = job.t
  if job.stage == "wait" then
    local ok, err = pcall(function()
      local pos = vec3(car:getPosition())
      local fwd = vec3(car:getDirectionVector()):normalized()
      local rot = quat(car:getRotation())
      job.fwd, job.rot = fwd, rot
      -- put the trailer's front just behind the car's rear, so a short reverse couples it
      local cc, ch = bbox(car)
      local back = t.back or 7
      if cc and ch then back = halfLength(ch) + 2.2; pos = cc end
      local config = nil
      if type(t.setup) == "table" then
        if type(t.setup.parts) == "table" and next(t.setup.parts) then
          config = { format = 2, parts = t.setup.parts, vars = t.setup.vars or {} }   -- exactly as built
        elseif t.setup.loadSlot and t.setup.loadPart then
          config = { format = 2, parts = { [t.setup.loadSlot] = t.setup.loadPart } }   -- (older saves) defaults + the load
        elseif type(t.setup.config) == "table" then
          config = t.setup.config
        end
        local ser = rawget(_G, "serialize")
        if config and ser then config = ser(config) end   -- the same form BeamMP uses for vehicle configs
      end
      job.trailer = spawnProp(t.trailer, pos - fwd * back + vec3(0, 0, 0.3), rot, config)
      pcall(function() be:enterVehicle(0, car) end)   -- stay in your own car
    end)
    if not ok or not job.trailer then trailerReport(false, false, 0, err or ("couldn't spawn " .. tostring(t.trailer))); trailerJob = nil; return end
    if t.test then spawnedTest[#spawnedTest + 1] = job.trailer end
    if type(t.setup) == "table" then
      -- the load is part of the trailer: nothing to place, just couple and measure it once it settles
      activeTrailer, activeLoad, cargoValue = job.trailer, t.setup.loadParts or {}, nil
      couple(car, job.trailer)
      job.stage, job.timer = "measure", 3
      return
    end
    job.stage, job.timer = "cargo", 1.5          -- let the trailer settle before loading it
  elseif job.stage == "cargo" then
    local n, lastErr = 0, nil
    local center, h = bbox(job.trailer)
    local deck
    if center and h then
      -- the box includes the tongue at the front: nudge the load towards the rear, drop it from just above the box
      deck = center - job.fwd * (halfLength(h) * 0.25) + vec3(0, 0, h.z + (t.height or 0.3))
    else
      deck = vec3(job.trailer:getPosition()) - job.fwd * 1.5 + vec3(0, 0, 1.4)
    end
    job.deck, job.cargo = deck, {}
    local count = tonumber(t.count) or 5
    for i = 1, count do
      local along = (i - (count + 1) / 2) * (t.spacing or 0.7)
      local ok, res = pcall(spawnProp, t.cargo, deck + job.fwd * along, job.rot)
      if ok and res then
        n = n + 1
        job.cargo[#job.cargo + 1] = res
        if t.test then spawnedTest[#spawnedTest + 1] = res end
      else lastErr = res end
    end
    pcall(function() be:enterVehicle(0, car) end)
    couple(car, job.trailer)   -- auto-couple: reversing onto the trailer latches it
    if n == 0 then trailerReport(false, true, 0, lastErr or ("couldn't spawn " .. tostring(t.cargo))); trailerJob = nil; return end
    job.stage, job.timer = "verify", 2.5   -- let the load settle, then count what stayed on the deck
  elseif job.stage == "measure" then
    measureCargo()
    job.stage, job.timer = "measured", 0.5
  elseif job.stage == "measured" then
    local hasLoad = nil
    pcall(function()
      local want = {}
      for _, n in ipairs(activeLoad or {}) do want[n] = true end
      local vd = core_vehicle_manager.getVehicleData(job.trailer:getID())
      local found = {}
      if vd and type(vd.chosenParts) == "table" then for _, n in pairs(vd.chosenParts) do found[#found + 1] = n end
      elseif vd and vd.config and type(vd.config.partsTree) == "table" then
        local flat = {}
        walkTree(vd.config.partsTree, flat, "/")
        for _, n in pairs(flat) do found[#found + 1] = n end
      end
      if #found > 0 then
        hasLoad = false
        for _, n in ipairs(found) do if want[n] then hasLoad = true end end
      end
    end)
    if TriggerServerEvent then
      TriggerServerEvent("tg_trailer_report", jsonEncode({ ok = true, trailer = true, prebuilt = true, load = cargoValue, hasLoad = hasLoad }))
    end
    trailerJob = nil
  elseif job.stage == "verify" then
    local onDeck = 0
    for _, c in ipairs(job.cargo or {}) do
      local ok, cp = pcall(function() return vec3(c:getPosition()) end)
      if ok and cp and (cp - job.deck):length() < 3 then onDeck = onDeck + 1 end
    end
    trailerReport(true, true, #(job.cargo or {}), nil, onDeck)
    trailerJob = nil
  end
end

local function onHitchUp()
  local car = getCar()
  if car then couple(car) end
end

onTrailerSave = function()
  local r = {}
  local ok, err = pcall(function()
    local car = be:getPlayerVehicle(0)   -- the vehicle you're in right now: your built trailer
    if not car then error("you're not in a vehicle - switch into the trailer first") end
    r.model = car:getJBeamFilename()
    local parts, fmt = readParts(car)
    if not fmt then error("couldn't read the trailer's parts on this BeamNG version") end
    r.format, r.loadParts, r.slots, r.parts, r.vars = fmt, {}, {}, {}, {}
    local conf = core_vehicle_partmgmt.getConfig()
    for k, val in pairs((type(conf) == "table" and conf.vars) or {}) do
      if type(k) == "string" and type(val) == "number" then r.vars[k] = val end
    end
    for slot, name in pairs(parts) do
      local slotName = tostring(slot):match("([^/]+)/?$") or tostring(slot)
      if type(name) == "string" then r.parts[slotName] = name end   -- "" keeps a slot empty (e.g. no straps)
      if #r.slots < 40 then r.slots[#r.slots + 1] = slotName .. "=" .. tostring(name) end
      local sl = slotName:lower()
      if type(name) == "string" and name ~= "" and (sl:find("load") or sl:find("cargo")) then
        r.loadParts[#r.loadParts + 1] = name
        if not r.loadSlot then r.loadSlot, r.loadPart = slotName, name end
      end
    end
    table.sort(r.loadParts)
    table.sort(r.slots)
  end)
  if not ok then r = { err = sanitize(err) } end
  local okJ, payload = pcall(jsonEncode, r)
  if not okJ then payload = jsonEncode({ err = "couldn't package the trailer: " .. sanitize(payload) }) end
  if TriggerServerEvent then TriggerServerEvent("tg_trailersave_reply", payload) end
end

local function onLightsTest() lights.test = lights.clock end
local function onLightsPin() lights.pinned = not lights.pinned end
-- finish flag: the server sends { event, detail, seconds } the moment your run is complete
local function onFinish(data)
  local ok, t = pcall(jsonDecode, data)
  if not ok or type(t) ~= "table" then t = {} end
  flag.title = t.event and tostring(t.event) or nil
  flag.detail = t.detail and tostring(t.detail) or nil
  flag.untilT = flag.clock + (tonumber(t.seconds) or 6)
end
local function onFlagTest()
  flag.title, flag.detail, flag.untilT = "Test", "Your time shows here", flag.clock + 6
end
local function onFlagPin() flag.pinned = not flag.pinned end

-- Sound bites: art/sound/topgear/<clip>.ogg in this mod. Which playback API works isn't verified on every
-- BeamNG version, so try each in turn and remember the first that runs; /tg soundtest next moves on to the
-- next one (a method can run without error and still be silent).
local SOUND_METHODS = {
  { name = "game audio (Engine.Audio.playOnce)", play = function(path) Engine.Audio.playOnce("AudioGui", path) end },
  { name = "game audio, relative path", play = function(path) Engine.Audio.playOnce("AudioGui", path:sub(2)) end },
  { name = "UI audio (executeJS)", play = function(path)
      be:executeJS(string.format("(new Audio(%q)).play()", "local://local" .. path)) end },
}
local function playClip(clip)
  if type(clip) ~= "string" or not clip:match("^[%w%-]+$") then return nil, "bad clip name", nil end
  local path = "/art/sound/topgear/" .. clip .. ".ogg"
  local n, lastErr = #SOUND_METHODS, nil
  for k = 0, n - 1 do
    local i = (sound.idx - 1 + k) % n + 1
    local ok, err = pcall(SOUND_METHODS[i].play, path)
    if ok then sound.idx, sound.method = i, SOUND_METHODS[i].name; return sound.method, nil, i end
    lastErr = err
  end
  return nil, tostring(lastErr), nil
end
-- server -> client: { clip, test = bool, cycle = bool }
local function onSound(data)
  local ok, t = pcall(jsonDecode, data)
  if not ok or type(t) ~= "table" then return end
  if t.cycle then sound.idx = sound.idx % #SOUND_METHODS + 1 end
  local method, err, idx = playClip(t.clip)
  if err and not t.test and not sound.warned then sound.warned = true; warn("sound: " .. err) end
  if t.test and TriggerServerEvent then
    TriggerServerEvent("tg_sound_report", jsonEncode({ clip = t.clip, method = method, err = err and sanitize(err) or nil,
      index = idx, count = #SOUND_METHODS }))
  end
end
local function onTheme()
  ui.noTheme = not ui.noTheme
  addLog("Colour theme " .. (ui.noTheme and "off." or "on."))
end

local function onTrailerClear()
  for _, v in ipairs(spawnedTest) do pcall(function() v:delete() end) end
  spawnedTest = {}
  activeTrailer, activeLoad, cargoValue = nil, nil, nil
end

-- In-game window (BeamNG's built-in ImGui) ---------------------------------------
-- Every button sends the same text as a chat command over a private channel; the
-- server applies the same permission checks as chat.
local okffi, ffi = pcall(require, "ffi")
local im = nil
local bufs = {}

addLog = function(msg)
  ui.log[#ui.log + 1] = tostring(msg)
  if #ui.log > 30 then table.remove(ui.log, 1) end
end

local function sendCmd(cmd)
  if TriggerServerEvent then TriggerServerEvent("tg_ui_cmd", cmd) end
  ui.reqTimer = 2
end
local function requestUi()   -- says which car list we have, so an unchanged one isn't re-sent
  if TriggerServerEvent then TriggerServerEvent("tg_ui_req", tostring(ui.data and ui.data.dealerVer or "")) end
end

local function intPtr(key, serverValue, default)
  local b = bufs[key]
  if not b then b = { ptr = im.IntPtr(math.floor(serverValue or default or 0)) }; bufs[key] = b end
  if serverValue ~= nil and b.seen ~= serverValue then b.ptr[0] = math.floor(serverValue); b.seen = serverValue end
  return b.ptr
end
local function textBuf(key)
  if not bufs[key] then bufs[key] = im.ArrayChar(64, "") end
  return bufs[key]
end
local function textOf(buf) if okffi then return ffi.string(buf) end return "" end

local function txt(s)
  s = tostring(s)
  if im.TextUnformatted then im.TextUnformatted(s) else im.Text((s:gsub("%%", "%%%%"))) end
end
local function colored(r, g, b, s)
  if im.TextColored and im.ImVec4 then im.TextColored(im.ImVec4(r, g, b, 1), (tostring(s):gsub("%%", "%%%%"))) else txt(s) end
end
local function header(label)
  local f = im.CollapsingHeader1 or im.CollapsingHeader
  return f(label)
end
local function button(label, cmd)
  if im.Button(label) then sendCmd(cmd); return true end
  return false
end
local function confirmButton(label, id, cmd)  -- click twice within 3 s
  local armed = ui.confirm[id] and (ui.t - ui.confirm[id]) < 3
  if im.Button((armed and ("Really? " .. label) or label) .. "##" .. id) then
    if armed then ui.confirm[id] = nil; sendCmd(cmd) else ui.confirm[id] = ui.t end
  end
end
local function same() im.SameLine() end

local function buyCar(model, config)
  ui.busy, ui.reqTimer = ui.t, 0.5
  local ok, err = pcall(function()
    local opts = {}
    if config then opts.config = "vehicles/" .. model .. "/" .. config .. ".pc" end
    core_vehicles.spawnNewVehicle(model, opts)
  end)
  if not ok then warn("buy failed: " .. tostring(err)); addLog("Couldn't spawn that - pick it from the vehicle menu instead.") end
end

local function returnCar()
  local car = getCar()
  if not car then return end
  ui.busy, ui.reqTimer = ui.t, 0.5
  local ok = pcall(function() car:delete() end)
  if not ok then pcall(function() core_vehicles.removeCurrent() end) end
end

-- Colour theme (Top Gear-inspired: deep blue-green backdrop, electric-blue accents, sky-grey panels).
-- Buttons = solid electric blue (click me). Editable fields = grey inset with a blue outline (type here).
local THEME = {
  WindowBg = { 0.07, 0.13, 0.14, 0.97 }, ChildBg = { 0.09, 0.16, 0.17, 1 }, PopupBg = { 0.09, 0.16, 0.17, 0.98 },
  TitleBg = { 0.10, 0.18, 0.20, 1 }, TitleBgActive = { 0.14, 0.28, 0.55, 1 }, TitleBgCollapsed = { 0.10, 0.18, 0.20, 1 },
  Text = { 0.95, 0.96, 0.97, 1 }, TextDisabled = { 0.55, 0.62, 0.64, 1 },
  Border = { 0.40, 0.56, 0.95, 0.60 }, Separator = { 0.40, 0.56, 0.95, 0.40 },
  Button = { 0.16, 0.36, 0.86, 1 }, ButtonHovered = { 0.32, 0.52, 1.00, 1 }, ButtonActive = { 0.10, 0.24, 0.62, 1 },
  FrameBg = { 0.24, 0.30, 0.32, 1 }, FrameBgHovered = { 0.30, 0.37, 0.40, 1 }, FrameBgActive = { 0.34, 0.42, 0.46, 1 },
  Header = { 0.13, 0.23, 0.25, 1 }, HeaderHovered = { 0.19, 0.32, 0.35, 1 }, HeaderActive = { 0.23, 0.38, 0.42, 1 },
  Tab = { 0.11, 0.20, 0.22, 1 }, TabHovered = { 0.32, 0.52, 1.00, 1 }, TabActive = { 0.16, 0.36, 0.86, 1 },
  CheckMark = { 0.56, 0.72, 1.00, 1 }, SliderGrab = { 0.56, 0.72, 1.00, 1 },
}
local THEME_VARS = { FrameRounding = 4, FrameBorderSize = 1, WindowRounding = 6, TabRounding = 4, GrabRounding = 4 }
local ACCENT = { 0.56, 0.72, 1.00 }   -- headings

local function imGet(name)   -- read an ImGui constant/function without tripping over ones this version lacks
  local ok, v = pcall(function() return im[name] end)
  return ok and v or nil
end
local function pushColors(tbl, rec)   -- rec.c counts pushes as they happen
  local push = imGet("PushStyleColor2") or imGet("PushStyleColor")
  if not push then return end
  for name, c in pairs(tbl) do
    local idx = imGet("Col_" .. name)
    if idx ~= nil then
      local okV, col = pcall(im.ImVec4, c[1], c[2], c[3], c[4])
      if okV and pcall(push, idx, col) then rec.c = rec.c + 1 end
    end
  end
end
local function popColors(rec) if rec.c > 0 then pcall(im.PopStyleColor, rec.c); rec.c = 0 end end
local function pushTheme(rec)
  pushColors(THEME, rec)
  local pv = imGet("PushStyleVar1") or imGet("PushStyleVar")
  if pv then
    for name, val in pairs(THEME_VARS) do
      local idx = imGet("StyleVar_" .. name)
      if idx ~= nil and pcall(pv, idx, val) then rec.v = rec.v + 1 end
    end
  end
end
local function popTheme(rec)
  popColors(rec)
  if rec.v > 0 then pcall(im.PopStyleVar, rec.v); rec.v = 0 end
end
local function heading(t) colored(ACCENT[1], ACCENT[2], ACCENT[3], t) end

-- A big, full-width, pulsing green button for the one thing everyone should press (GO).
-- Colours follow ui.noTheme; every push is popped even if the button itself fails.
local function bigButton(label, cmd)
  local rec = { c = 0, v = 0 }
  if not ui.noTheme then
    local p = 0.5 + 0.5 * math.sin((ui.t or 0) * 4)   -- gentle pulse so it catches the eye
    pcall(pushColors, { Button = { 0.10 + 0.08 * p, 0.55 + 0.20 * p, 0.15 + 0.05 * p, 1 },
                        ButtonHovered = { 0.25, 0.85, 0.30, 1 }, ButtonActive = { 0.05, 0.40, 0.10, 1 },
                        Text = { 1, 1, 1, 1 } }, rec)
    local pv = imGet("PushStyleVar1") or imGet("PushStyleVar")
    local idx = imGet("StyleVar_FrameRounding")
    if pv and idx ~= nil and pcall(pv, idx, 10) then rec.v = rec.v + 1 end
  end
  local width = -1   -- negative = stretch to the window's right edge
  local okW, avail = pcall(function() return im.GetContentRegionAvail() end)
  if okW and type(avail) ~= "number" and avail and tonumber(avail.x) and avail.x > 100 then width = avail.x end
  local scaled = imGet("SetWindowFontScale") and pcall(im.SetWindowFontScale, 1.8) or false
  local okB, clicked = pcall(im.Button, label, im.ImVec2(width, 80))
  if scaled then pcall(im.SetWindowFontScale, 1) end
  popTheme(rec)
  if not okB then warn("big button: " .. tostring(clicked)); return button(label, cmd) end
  if clicked then sendCmd(cmd); return true end
  return false
end

-- Standings: a light sky-grey table with dark text so it stands out from the dark window
local function drawStandings(d)
  local rows = d.standings or {}
  if #rows == 0 then return end
  local drawn = false
  local rec = { c = 0 }
  if not ui.noTheme then pcall(pushColors, { TableRowBg = { 0.90, 0.93, 0.95, 1 }, TableRowBgAlt = { 0.80, 0.86, 0.90, 1 },
                          TableHeaderBg = { 0.56, 0.72, 1.00, 1 }, TableBorderStrong = { 0.16, 0.36, 0.86, 1 },
                          TableBorderLight = { 0.60, 0.68, 0.74, 1 }, Text = { 0.05, 0.09, 0.11, 1 } }, rec) end
  pcall(function()
    local flags = 0
    for _, f in ipairs({ "TableFlags_RowBg", "TableFlags_Borders" }) do flags = flags + (tonumber(imGet(f)) or 0) end
    if imGet("BeginTable") and im.BeginTable("##standings", 5, flags) then
      local ok = pcall(function()
        for _, c in ipairs({ "#", "Driver", "Points", "Wins", "Cash" }) do im.TableSetupColumn(c) end
        im.TableHeadersRow()
        for i, r in ipairs(rows) do
          im.TableNextRow()
          im.TableNextColumn(); txt(ordinal(i))
          im.TableNextColumn(); txt(r.name .. (r.online and "" or " (offline)"))
          im.TableNextColumn(); txt(string.format("%.1f", r.points or 0))
          im.TableNextColumn(); txt(tostring(r.wins or 0))
          im.TableNextColumn(); txt(commas(r.cash))
        end
      end)
      im.EndTable()
      drawn = ok
    end
  end)
  popColors(rec)
  if not drawn then   -- builds without tables: bright lines instead
    for i, r in ipairs(rows) do
      colored(0.85, 0.92, 1.0, string.format("%s  %s - %.1f pts, %d win%s, %s%s", ordinal(i), r.name, r.points or 0, r.wins or 0,
        (r.wins == 1) and "" or "s", commas(r.cash), r.online and "" or " (offline)"))
    end
  end
end

local function drawDriverButtons(d, me)
  local ph = d.phase
  button(((me.repair or 0) > 0 and ("Repair (" .. commas(me.repair) .. ")") or "Repair") .. "##drv_repair", "repair"); same()
  confirmButton("Tow (" .. commas(me.towCost or d.towFee or 1000) .. ")", "drv_tow", "tow"); same()
  button("Unstick (free)##drv_unstick", "unstick"); same()
  local rl
  if ph == "dealer" or ph == "idle" or ph == "results" then rl = "Respawn (free)"
  elseif ph == "workshop" then rl = "Respawn (repair price)"
  else rl = "Respawn (" .. commas(me.respawnCost or d.respawnFee or 500) .. ")" end
  confirmButton(rl, "drv_respawn", "respawn")
  local notes = {}
  if ph ~= "workshop" then notes[#notes + 1] = "Repair: workshops only" end
  if not me.canTow then notes[#notes + 1] = "Tow: during legs and events" end
  if ph ~= "dealer" and ph ~= "workshop" and ph ~= "results" and ph ~= "idle" then
    notes[#notes + 1] = "Tow/Respawn mid-run = DSQ"
  end
  notes[#notes + 1] = "Tow and Respawn need two clicks"
  if (d.helpPoints or 0) > 0 then
    notes[#notes + 1] = string.format("Tow/Respawn price = repair x markup + fee, and -%g pt%s each", d.helpPoints, d.helpPoints == 1 and "" or "s")
  end
  if (me.tows or 0) + (me.respawns or 0) > 0 then
    notes[#notes + 1] = string.format("So far: %d tow%s, %d respawn%s", me.tows or 0, me.tows == 1 and "" or "s",
      me.respawns or 0, me.respawns == 1 and "" or "s")
  end
  Tabs.help(table.concat(notes, "\n"))
  if state.eventType == "trailer" and (ph == "travel" or ph == "countdown" or ph == "event") then
    button("Hitch up (couple the trailer)##hitchup", "hitchup")
    Tabs.help("Reverse so your hitch meets the trailer's coupler. No hitch? Fit one in a workshop (parts menu).")
  end
end

-- Settings tab (everyone): this player's own sound, window placement, colour theme and diagnostics
local function drawSettings(d)
  Tabs.box("Sound", "sound", function()
  if d.soundsOn == false then button("Sounds: OFF - turn on##sounds", "sounds on")
  else button("Sounds: ON - turn off##sounds", "sounds off") end
  same(); button("Test sound##soundtest", "soundtest"); same()
  button("Not hearing it? Try another way##soundnext", "soundtest next")
  Tabs.help("Only for you: other players keep their own setting.")
  end)
  Tabs.box("Lights & flag", "lightsflag", function()
  button("Position the start lights##lightspin", "lights"); same(); button("Test them##lightstest", "lightstest")
  Tabs.help("Position: shows the window so you can drag it where you want it.")
  button("Position the finish flag##flagpin", "flag"); same(); button("Test it##flagtest", "flagtest")
  end)
  Tabs.box("Window", "window", function()
  button((ui.noTheme and "Colour theme: OFF - turn on" or "Colour theme: ON - turn off") .. "##theme", "theme")
  end)
  Tabs.box("Troubleshooting", "trouble", function()
  button("Diagnostics##diag", "diag"); same(); button("Parts diagnostics##partsdiag", "partsdiag")
  Tabs.help("The results appear in chat - handy when reporting a problem.")
  end)
end

local function drawPaused(d)   -- a challenge saved before a server restart, waiting to be resumed
  local pz = d.paused
  if not pz then return end
  txt("The server restarted mid-challenge. Everything was saved: " .. tostring(pz.at or "") .. ".")
  txt("Back: " .. (#(pz.back or {}) > 0 and table.concat(pz.back, ", ") or "nobody yet"))
  if #(pz.away or {}) > 0 then colored(1, 0.8, 0.3, "Not back yet: " .. table.concat(pz.away, ", ")) end
  if d.admin then
    bigButton("Resume the challenge", "resume")
    confirmButton("Discard it", "discard", "discard")
    Tabs.help("Resume brings everyone's car back (upgrades kept; each driver pays their car's repairs).")
  else
    txt("Waiting for an admin to resume it - your car comes back then.")
  end
end

-- Admin tab, first two boxes: run the challenge, and a player's cash & points
local function drawAdminControls(d)
  if not d.admin then return end
  Tabs.box("Challenge", "admchallenge", function()
    button("Start", "start"); same(); button("Start (unfinished course)", "start force"); same()
    button("Next phase", "next"); same(); confirmButton("Stop", "stop", "stop")
    Tabs.help("Next phase: closes the dealership, forces a start, ends a run or event, or closes a workshop.\nStop needs two clicks.")
    if d.traffic then
      colored(1, 0.8, 0.3, "Traffic mode is ON: what you spawn is non-scoring traffic, and your vehicle menu is open.")
      button("Turn traffic mode off##traffic", "traffic off")
    else
      button("Traffic mode (add AI traffic / parked cars)##traffic", "traffic on")
    end
  end)
  Tabs.box("Players", "admplayers", function()
    txt("Player cash & points")
    if #(d.standings or {}) == 0 then
      colored(0.65, 0.65, 0.65, "Players appear here once a challenge is running.")
    else
      for i, s in ipairs(d.standings) do
        if i > 1 then same() end
        if im.Button((ui.player == s.name and "> " or "") .. s.name .. "##pl_" .. s.name) then ui.player = s.name end
      end
      local nb = textBuf("admplayer")
      im.InputText("Or type a name##admplayer", nb)
      local typed = textOf(nb):gsub("^%s+", ""):gsub("%s+$", "")
      local who = typed ~= "" and typed or ui.player
      if not who then
        colored(0.65, 0.65, 0.65, "Pick a player above or type a name.")
      else
        for _, s in ipairs(d.standings) do
          if s.name == who then txt(string.format("%s: %s, %.1f points", s.name, commas(s.cash), s.points or 0)) end
        end
        local a = intPtr("admcash", nil, 1000)
        im.InputInt("Cash##admcash", a); same()
        button("Give##admgive", "give " .. who .. " " .. a[0]); same()
        button("Set##admset", "setcash " .. who .. " " .. a[0])
        local pt = intPtr("admpts", nil, 1)
        im.InputInt("Points##admpts", pt)
        local rb = textBuf("admreason")
        im.InputText("Reason (optional)##admreason", rb); same()
        button("Award##admaward", "award " .. who .. " " .. pt[0] .. " " .. textOf(rb))
        Tabs.help("A negative amount takes cash or points away. Award: everyone sees it, and it shows in the results.")
      end
    end
  end, true)
end

local function drawStatus(d)
  local me = d.me
  Tabs.box("My car", "mycar", function()
  txt(state.title or "")
  if not me then
    txt("You're not in this challenge.")
    if d.phase == "dealer" then button("Join the challenge", "join") end
  else
    txt("Car: " .. tostring(me.car or "none yet"))
    local fl = d.faults or {}
    if fl.revealed and #(fl.mine or {}) > 0 then
      local names = {}
      for _, f in ipairs(fl.mine) do names[#names + 1] = f.name end
      colored(1, 0.8, 0.3, "Problems: " .. table.concat(names, ", "))
    elseif (fl.count or 0) > 0 and not fl.revealed then
      colored(1, 0.8, 0.3, string.format("Bought as %s: %d hidden problem%s - a workshop will find %s", (fl.names or {})[fl.count + 1] or "worn",
        fl.count, fl.count == 1 and "" or "s", fl.count == 1 and "it" or "them"))
    end
    txt(string.format("Cash: %s    Points: %.1f    Wins: %d    Damage: %d", commas(me.cash), me.points or 0, me.wins or 0, me.damage or 0))
    if (me.cash or 0) < 0 then
      colored(1, 0.4, 0.4, string.format("Overdrawn: %s - prize money pays it off. Parts and problem fixes stop at %s overdrawn.",
        commas(-me.cash), commas(me.creditLimit or 1500)))
    end
    if d.phase == "dealer" and me.hasCar then
      colored(0.6, 0.8, 1, "Workshop mode: fit upgrades and paint from the parts menu now (upgrades charged, paint free).")
    elseif d.phase == "workshop" and (d.workshopSpots or 0) > 0 then
      if me.inShop then colored(0.4, 1, 0.4, "You're at a workshop - repairs, parts and paint are open.")
      else colored(1, 0.8, 0.3, "Drive to a workshop (follow the arrows) - repairs, parts and paint open when you get there.") end
    end
    if d.phase == "dealer" then
      if not me.hasCar then txt("Pick a car in the Dealership tab.")
      elseif me.ready then colored(0.4, 1, 0.4, "Ready - waiting for the others.")
      else button("I'm happy with my car - Ready!", "ready") end
    elseif d.phase == "travel" then
      if not me.arrived then txt("Drive to the start - follow the arrows.")
      elseif d.allHere then
        colored(0.4, 1, 0.4, "Everyone's here!")
        bigButton("GO! Start the countdown", "go")
      else txt("Waiting for everyone to arrive...") end
    elseif d.phase == "workshop" then
      for _, f in ipairs((d.faults or {}).mine or {}) do
        button("Fix this problem: " .. f.name .. " (" .. commas(d.faults.fix) .. ")##fix_" .. f.id, "fix " .. f.id)
      end
      txt("Spent in this workshop: " .. commas(me.upgrade or 0) .. " (parts charged as fitted; paint, cosmetics and tuning free)")
    end
    drawDriverButtons(d, me)
  end
  end)
  if d.paused then Tabs.box("Challenge saved", "paused", function() drawPaused(d) end) end
  if #(d.standings or {}) > 0 then Tabs.box("Standings", "standings", function() drawStandings(d) end) end
end

-- Car condition (= how many hidden faults the car comes with): a slider New .. Death Trap; each step down from New
-- is cheaper on the market (+payout to spend). Moves both ways until a car is bought, then only toward Death Trap.
local function drawCondition(d, fl)
  local levels, max, count = fl.levels or {}, math.min(fl.max or 4, 4), fl.count or 0
  local function name(n) return (levels[n + 1] or {}).name or CONDITION_NAMES[n] or tostring(n) end
  local function km(n) return (commas((levels[n + 1] or {}).km or 0):gsub("^%$", "")) .. " km" end
  local function off(n) return (levels[n + 1] or {}).off or 0 end
  if fl.locked or d.phase ~= "dealer" then
    txt(string.format("Bought as %s%s.", name(count), count > 0 and (" (" .. km(count) .. ")") or ""))
    if d.phase == "dealer" then colored(0.65, 0.65, 0.65, "That's locked in - return the car to choose again.") end
  else
    local ptr = intPtr("condition", count)
    if ptr[0] < 0 then ptr[0] = 0 elseif ptr[0] > max then ptr[0] = max end
    local okS, changed = pcall(im.SliderInt, "##condition", ptr, 0, max, name(ptr[0]))
    if not okS then   -- (no slider on this ImGui: one button per condition instead)
      if not ui.sliderWarned then ui.sliderWarned = true; warn("condition slider: " .. tostring(changed)) end
      for n = 0, max do
        button((n == count and "> " or "") .. name(n) .. "##cond_" .. n, "condition " .. n)
        if n < max then same() end
      end
    elseif changed and ptr[0] ~= count then
      sendCmd("condition " .. ptr[0])   -- every price in the list follows straight away
    end
    local offs = {}
    for n = 1, max do offs[#offs + 1] = string.format("%s up to %d%% off", name(n), off(n)) end
    if count > 0 then
      colored(0.4, 1, 0.4, string.format("%s (%s): prices up to %d%% off.", name(count), km(count), off(count)))
    else
      txt("New: full price.")
    end
    Tabs.help("A more worn car is cheaper on the market: " .. table.concat(offs, ", ") .. ".\n" ..
      "Fast cars hold their value: the quicker a car, the smaller its discount.\nChoose before you buy - it's locked in with the car.")
  end
  txt("Each step down hides a problem in the car.")
  Tabs.help(string.format("A workshop finds them. Fixing one costs %d%% of the car's new price (at least %s)%s;\n" ..
    "each one still there at the finale costs %s points.", math.floor((fl.fixPercent or 0.05) * 100 + 0.5), commas(fl.fixMin or 500),
    fl.fix and (" - " .. commas(fl.fix) .. " for yours") or "", tostring(fl.points or 0)))
end

local function drawDealer(d)
  local me = d.me
  local busy = ui.busy and (ui.t - ui.busy) < 5
  local canBuy = d.phase == "dealer" and me and not me.hasCar and not busy
  Tabs.box("Buy a car", "buy", function()
  txt("Budget " .. commas(d.budget) .. (me and ("    You have " .. commas(me.cash)) or ""))
  if d.phase ~= "dealer" then colored(1, 0.7, 0.3, "The dealership is closed.") end
  if busy then colored(1, 0.85, 0.3, "Talking to the dealer...") end
  if canBuy then
    if im.Button("Browse the cars in the vehicle selector##opensel") then M.openSelector() end
    Tabs.help("Today's cars at today's prices, with pictures and filters - spawning one buys it.\nOr pick from Today's cars below.")
  end
  if d.phase == "dealer" and me and me.hasCar and not busy then
    txt("You own the " .. tostring(me.car) .. ".")
    same()
    if im.Button("Return it for a full refund") then returnCar() end
  end
  end)
  local fl = d.faults
  if fl and me then Tabs.box("Car condition", "condition", function() drawCondition(d, fl) end) end
  Tabs.box("Today's cars" .. (d.dealerClass and (": " .. d.dealerClass.name) or ""), "cars", function()
  if d.dealerClass then txt(d.dealerClass.summary) end
  local list = d.dealer or {}
  if #list == 0 then txt("Nothing for sale.") end
  -- one make/model at a time: a dropdown of the models, then that model's trims (a real catalogue has ~100 models)
  local pickM
  for _, m in ipairs(list) do if m.model == ui.dealerModel then pickM = m end end
  pickM = pickM or list[1]
  if #list > 1 then
    local items = {}
    for _, m in ipairs(list) do
      items[#items + 1] = { string.format("%s (%d)  from %s", m.name, #m.trims, commas((m.trims[1] or {}).price or 0)), m.model, m == pickM }
    end
    local picked = Tabs.combo("dealermodel", pickM and (pickM.name .. " (" .. #pickM.trims .. ")") or "Pick a car...", items)
    if picked then ui.dealerModel = picked end
  end
  for _, m in ipairs(pickM and { pickM } or {}) do
    do
      for _, t in ipairs(m.trims) do
        local needs = tonumber(t.needs) or 0
        if canBuy and needs == 0 and not t.over then
          if im.Button("Buy##" .. m.model .. "_" .. tostring(t.config)) then buyCar(m.model, t.config) end
          same()
        end
        local label = t.est and (t.name .. "  (est. price)") or t.name
        if t.over then
          colored(1, 0.45, 0.45, string.format("%s  %s  - over budget", commas(t.price), label))
        elseif needs > 0 then
          colored(1, 0.7, 0.3, string.format("%s  %s  - %s as a %s", commas(t.price), label, commas(t.condPrice), tostring(t.cond)))
        elseif me and t.price > (me.cash or 0) then colored(1, 0.45, 0.45, commas(t.price) .. "  " .. label)
        else txt(commas(t.price) .. "  " .. label) end
      end
    end
  end
  end)
  if me and me.hasCar then Tabs.box("Parts", "parts", function() Tabs.parts(d) end, true) end
end

local function trim(str) return (tostring(str or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function drawLibrary(c)
  if c.active then
    txt("Loaded course: " .. c.active)
    if c.dirty then same(); colored(1, 0.8, 0.3, "(unsaved changes)") end
  else
    colored(1, 0.8, 0.3, "This course has no name yet - type one and press Save as.")
  end
  local lib = c.library or {}
  local known = false
  for _, e in ipairs(lib) do if e.name == ui.courseSel then known = true end end
  if not known then ui.courseSel = nil end

  local function entryLabel(e)
    return e.name .. "  -  " .. ((e.problems or 0) == 0 and "complete" or (tostring(e.problems) .. " to set")) ..
      (e.savedAt and ("  (" .. e.savedAt .. ")") or "")
  end
  if #lib == 0 then
    txt("No saved courses yet.")
  elseif im.BeginCombo then
    local preview = ui.courseSel or "Pick a saved course..."
    if im.BeginCombo("##courselib", preview) then
      local ok, err = pcall(function()
        local selectable = im.Selectable1 or im.Selectable
        for _, e in ipairs(lib) do
          if selectable(entryLabel(e) .. "##lib_" .. e.name, ui.courseSel == e.name) then ui.courseSel = e.name end
        end
      end)
      im.EndCombo()   -- always closed, even if an entry failed
      if not ok then error(err) end
    end
  else
    for _, e in ipairs(lib) do  -- fallback for builds without dropdowns
      if im.Button(((ui.courseSel == e.name) and "> " or "") .. entryLabel(e) .. "##libb_" .. e.name) then ui.courseSel = e.name end
    end
  end
  if ui.courseSel then
    same(); button("Load##libload", "course load " .. ui.courseSel)
    same(); confirmButton("Delete", "libdel", "course delete " .. ui.courseSel)
  end

  local nb = textBuf("coursename")
  im.InputText("##coursename", nb)
  same()
  if im.Button("Save as##libsaveas") then
    local nm = trim(textOf(nb))
    if nm ~= "" then sendCmd("course save " .. nm) else addLog("Type a name for the course first.") end
  end
  if c.active then same(); button("Save##libsave", "course save " .. c.active) end
  same()
  if im.Button("New course##libnew") then sendCmd("course new " .. trim(textOf(nb))) end
  im.Separator()
end

local function drawAdmin(d)
  drawAdminControls(d)
  Tabs.box("Money & timers", "money", function()
    local b = intPtr("budget", d.baseBudget or d.budget)
    im.InputInt("Budget##b", b); same(); button("Set##budget", "budget " .. b[0])
    local w = intPtr("ws", d.workshopMinutes)
    im.InputInt("Workshop minutes##w", w); same(); button("Set##ws", "workshop " .. w[0])
    local we = intPtr("wsevery", d.workshopEvery)
    im.InputInt("Workshop every N events##we", we); same(); button("Set##wsevery", "workshopevery " .. we[0])
    txt("Game prices: " .. (d.gamePrices and "ON" or "OFF")); same()
    button((d.gamePrices and "Turn off" or "Turn on") .. "##gp", d.gamePrices and "gameprices off" or "gameprices on"); same()
    button("Import game prices", "importprices")
    local cat = (d.classes or {}).catalogue
    if cat == "builtin" then
      colored(0.65, 0.65, 0.65, "Cars: the built-in catalogue (every stock BeamNG car). Import only for mod cars or a newer BeamNG.")
    elseif cat == "import" or (d.classes or {}).imported then
      colored(0.65, 0.65, 0.65, "Cars: imported from your game."); same()
      confirmButton("Back to the built-in catalogue", "catbuiltin", "importprices builtin")
    end
  end, true)
  local cl = d.classes
  if cl then Tabs.box("Car classes", "classes", function()
    txt("Which cars the dealership sells.")
    if not cl.imported then colored(1, 0.8, 0.3, "Import the game's cars first (prices + details):"); same(); button("Import every car", "importprices") end
    txt("Next challenge: " .. (cl.active or cl.none or "no class - the normal dealer list"))
    if cl.idle and cl.active then same(); button("Use no class##clsnone", "class use none") end
    for _, c in ipairs(cl.list or {}) do
      if cl.idle and c.name ~= cl.active then button("Use##clsuse_" .. c.name, "class use " .. c.name); same() end
      button((cl.view == c.name and "> " or "") .. "Edit##clsedit_" .. c.name, "class edit " .. c.name); same()
      local line = string.format("%s%s - %d trims%s", c.name, c.name == cl.active and " (in use)" or "", c.count or 0,
        c.min and string.format(", %s to %s", commas(c.min), commas(c.max)) or "")
      if c.name == cl.active then colored(0.4, 1, 0.4, line) else txt(line) end
    end
    local nb = textBuf("newclass")
    im.InputText("##newclass", nb); same()
    if im.Button("New class (one word)##clsnew") then
      local nm = trim(textOf(nb))
      if nm ~= "" then sendCmd("class new " .. nm) else addLog("Type a name for the class first.") end
    end
    same()
    if im.Button("All cars, base trims##clsnewbase") then   -- every car, each model's cheapest factory trim
      local nm = trim(textOf(nb))
      sendCmd("class new " .. (nm ~= "" and nm or "basetrims") .. " base")
    end
    -- ready-made classes: one click makes an ordinary (editable) class
    if cl.imported and #(cl.presets or {}) > 0 and header("Ready-made classes##clspresets") then
      for _, pr in ipairs(cl.presets) do
        if pr.made then
          if cl.idle and pr.key ~= cl.active then button("Use##clspu_" .. pr.key, "class use " .. pr.key); same() end
        else
          button("Make##clspm_" .. pr.key, "class preset " .. pr.key); same()
        end
        local line = string.format("%s - %s (%d trims)", pr.key, pr.title, pr.count or 0)
        if pr.key == cl.active then colored(0.4, 1, 0.4, line .. "  (in use)") else txt(line) end
      end
    end
    local v
    for _, c in ipairs(cl.list or {}) do if c.name == cl.view then v = c end end
    if v then
      im.Separator()
      heading("CLASS " .. v.name)
      txt(v.summary)
      for _, r in ipairs(v.rules or {}) do
        button("Remove##rm_" .. r.field, "class unrule " .. v.name .. " " .. r.field); same(); txt(r.text)
      end
      -- add a rule: pick the field, type the value(s)
      ui.clsField = ui.clsField or 1
      local fields = cl.fields or {}
      local f = fields[ui.clsField]
      if f then
        if im.BeginCombo and im.BeginCombo("##clsfield", f.name) then
          local okC = pcall(function()
            local selectable = im.Selectable1 or im.Selectable
            for i, ff in ipairs(fields) do if selectable(ff.name .. "##fld_" .. ff.key, i == ui.clsField) then ui.clsField = i end end
          end)
          im.EndCombo()
          if not okC then error("field list failed") end
        end
        same()
        local vb = textBuf("clsvalue")
        im.InputText("##clsvalue", vb); same()
        if im.Button("Add rule##clsaddrule") then
          local val = trim(textOf(vb))
          if val ~= "" then sendCmd("class rule " .. v.name .. " " .. f.key .. " " .. val) else addLog("Type a value for the rule.") end
        end
        if f.kind == "base" then colored(0.65, 0.65, 0.65, "Type: base  (each model's cheapest factory trim only)")
        elseif f.kind == "range" then colored(0.65, 0.65, 0.65, "A range: 1985-1999, 1985- or -1999")
        elseif f.values and #f.values > 0 then colored(0.65, 0.65, 0.65, "Comma separated, e.g.: " .. table.concat(f.values, ", ")) end
      end
      -- hand-picks
      local kb = textBuf("clskey")
      im.InputText("##clskey", kb); same()
      local key = trim(textOf(kb))
      if im.Button("Include##clsinc") and key ~= "" then sendCmd("class include " .. v.name .. " " .. key) end; same()
      if im.Button("Exclude##clsexc") and key ~= "" then sendCmd("class exclude " .. v.name .. " " .. key) end
      colored(0.65, 0.65, 0.65, "A model (covet) or one trim (covet/base_M).")
      for _, k in ipairs(v.include or {}) do button("Remove##inc_" .. k, "class clear " .. v.name .. " " .. k); same(); txt("Included: " .. k) end
      for _, k in ipairs(v.exclude or {}) do button("Remove##exc_" .. k, "class clear " .. v.name .. " " .. k); same(); txt("Left out: " .. k) end
      local mp = intPtr("clsmult_" .. v.name, math.floor((v.multiplier or 1) * 100 + 0.5))
      im.InputInt("Price %##clsmult", mp); same(); button("Set##clsmultset", "class multiplier " .. v.name .. " " .. (mp[0] / 100))
      -- the cars it sells
      if header(string.format("The %d cars in %s##clstrims", v.count or 0, v.name)) then
        for _, t in ipairs(v.trims or {}) do
          confirmButton("Leave out", "clsx_" .. t.key, "class exclude " .. v.name .. " " .. t.key); same()
          local pp = intPtr("clsprice_" .. t.key, t.price or 0)
          im.InputInt("##clsprice_" .. t.key, pp); same()
          button("Set price##clsps_" .. t.key, "class price " .. v.name .. " " .. t.key .. " " .. pp[0]); same()
          if t.override then button("Back to normal##clspo_" .. t.key, "class price " .. v.name .. " " .. t.key .. " off"); same() end
          if t.noPrice then colored(1, 0.7, 0.3, t.name .. "  (no price - not for sale until it has one)")
          else txt(t.est and (t.name .. "  (estimated price)") or t.name) end
        end
        if (v.count or 0) > #(v.trims or {}) then txt(string.format("... and %d more", v.count - #(v.trims or {}))) end
      end
      confirmButton("Delete class " .. v.name, "clsdel", "class delete " .. v.name)
    end
    -- trims the game has no price for (derby/joke builds, mod cars): estimated from similar cars; a dealership-wide
    -- price replaces the estimate
    if (cl.unpricedCount or 0) > 0 and header(string.format("Cars without a game price (%d)##unpriced", cl.unpricedCount)) then
      txt("The game has no price for these. They're priced by estimate from similar cars (power-to-weight, 0-100,")
      txt("top speed, weight, year); Set price replaces an estimate, Clear goes back to it.")
      for _, u in ipairs(cl.unpriced or {}) do
        local pp = intPtr("unpriced_" .. u.key, u.price or u.est or 0)
        im.InputInt("##unpriced_" .. u.key, pp); same()
        button("Set price##ups_" .. u.key, "setprice " .. u.key .. " " .. pp[0]); same()
        if u.price then button("Clear##upc_" .. u.key, "setprice " .. u.key .. " off"); same(); txt(u.name .. "  - " .. commas(u.price))
        elseif u.est then txt(u.name .. "  - est. " .. commas(u.est))
        else colored(1, 0.7, 0.3, u.name .. "  - no price (no details to estimate from)") end
      end
      if cl.unpricedCount > #(cl.unpriced or {}) then txt(string.format("... and %d more (/tg setprice list)", cl.unpricedCount - #cl.unpriced)) end
    end
  end, true) end
  Tabs.box("Tools", "tools", function()
    if #(d.soundClips or {}) > 0 and header("Soundboard##soundboard") then
      txt("Plays the clip for everyone (players who turned sounds off don't hear it).")
      for i, clip in ipairs(d.soundClips) do
        button(clip .. "##sb_" .. clip, "play " .. clip)
        if i % 3 ~= 0 and i < #d.soundClips then same() end
      end
    end
    if d.faults and header("Problem-car fault test##ftest") then
      txt("Applies faults to the car you're in right now (no money involved) and reports what worked.")
      -- as which condition: the same strengths as a car bought that way (more worn, worse problems)
      ui.testCond = ui.testCond or 3
      local levels, items = d.faults.levels or {}, {}
      local function lname(n) return ((levels[n + 1] or {}).name or CONDITION_NAMES[n] or tostring(n)) end
      for n = 1, 4 do
        items[#items + 1] = { string.format("%s (x%g)", lname(n), (levels[n + 1] or {}).sev or 1), n, n == ui.testCond }
      end
      txt("Test as:"); same()
      local pick = Tabs.combo("ftestcond", string.format("%s (x%g)", lname(ui.testCond), (levels[ui.testCond + 1] or {}).sev or 1), items)
      if pick then ui.testCond = pick end
      Tabs.help("Each problem's strength scales with the car's condition, as on a bought car: x1 = the listed values.")
      local as = " as " .. ui.testCond
      button("Test all faults on my car", "fault test" .. as); same(); button("Remove test faults", "fault testoff")
      for _, f in ipairs(d.faults.all or {}) do
        button("Test: " .. f.name .. "##ft1_" .. f.id, "fault test " .. f.id .. as)
      end
      button("Which cars take which faults##fcaps", "fault caps")
    end
  end, true)
  local c = d.course
  if c then Tabs.box("Course", "course", function()
    if header("Workshop locations##wsloc") then
      if (c.workshops or 0) == 0 then txt("No workshop locations: workshops work anywhere on the map.")
      else txt(string.format("%d workshop location%s: players drive to the nearest one when a workshop opens.",
        c.workshops, c.workshops == 1 and "" or "s")) end
      button("Import gas stations", "importgas"); same(); button("Add workshop here", "addworkshop"); same()
      button("Undo workshop", "undoworkshop"); same(); confirmButton("Clear workshops", "clrws", "clearworkshops")
      colored(0.65, 0.65, 0.65, "Saved with the course - remember Save in the course library.")
    end
    if header("Session - pick and order the events##session") then
      local on = 0
      for _, e in ipairs(c.events) do if e.enabled then on = on + 1 end end
      local every = c.workshopEvery or 2
      txt(string.format("%d event%s switched on. They run top to bottom; %s.", on, on == 1 and "" or "s",
        every > 0 and ("a workshop after every " .. every .. " events (not after the last)") or "no workshops"))
      if not c.idle then colored(1, 0.8, 0.3, "Locked while a challenge is running.") end
      local pos = 0
      for i, e in ipairs(c.events) do
        if c.idle then
          button((e.enabled and "Turn off" or "Turn on") .. "##en" .. i, "enable " .. i .. (e.enabled and " off" or " on")); same()
          if i > 1 then button("Up##up" .. i, "moveevent " .. i .. " up") else txt("  ") end; same()
          if i < #c.events then button("Down##dn" .. i, "moveevent " .. i .. " down") else txt("    ") end; same()
          confirmButton("Remove", "rm" .. i, "delevent " .. i); same()
        end
        if e.enabled then pos = pos + 1 end
        local line = string.format("%s%s  (%s%s)", e.enabled and (pos .. ". ") or "off  ", e.name, e.typeLabel or e.type,
          e.solo and ", time trial mode" or "")
        if e.enabled then colored(0.5, 1, 0.5, line) else txt(line) end
      end
      im.Separator()
      txt("Add a new event to the course:")
      for i, t in ipairs(c.types or {}) do
        button(t.label .. "##add_" .. t.id, "addevent " .. t.id)
        if i % 4 ~= 0 then same() end
      end
      txt("")
    end
    if header("Course builder##course") then
      drawLibrary(c)
      txt("Drive to the spot, then press a button - positions come from your car.")
      if ui.sel ~= "finale" and not c.events[ui.sel] then ui.sel = 1 end
      for _, e in ipairs(c.events) do
        if im.Button(((ui.sel == e.n) and "> " or "") .. e.n .. "##ev" .. e.n) then ui.sel = e.n end
        same()
        local detail
        if e.type == "speedtrap" then detail = "trap:" .. (e.trap and "yes" or "NO")
        elseif e.type == "parking" then detail = "bays:" .. (e.bays or 0)
        elseif e.type == "slalom" then detail = "gates:" .. e.cps
        elseif e.type == "circuit" then detail = string.format("checkpoints:%d  laps:%d", e.cps, e.laps or 3)
        elseif e.type == "rpc" then detail = string.format("checkpoints:%d  laps:%d  car:%s", e.cps, e.laps or 3, tostring(e.rpcCar))
        else detail = "checkpoints:" .. e.cps end
        local line = string.format("%s%s [%s]  start:%s  %s  route:%d", e.enabled and "" or "(off) ", e.name,
          e.typeLabel or e.type, e.start and "yes" or "NO", detail, e.via)
        if e.enabled then txt(line) else colored(0.6, 0.6, 0.6, line) end
      end
      if im.Button(((ui.sel == "finale") and "> " or "") .. "F##evf") then ui.sel = "finale" end
      same()
      txt(string.format("%s  finish:%s  route:%d", c.finale.name, c.finale.pos and "yes" or "NO", c.finale.via))
      im.Separator()
      local target = tostring(ui.sel)
      if ui.sel == "finale" then
        button("Set finish here", "setfinale"); same()
        button("Add route waypoint", "addvia finale"); same(); button("Undo route waypoint", "undovia finale"); same()
        button("Clear route", "clearvia finale")
      else
        local e = c.events[ui.sel]
        button("Set start here", "setstart " .. target); same()
        if e.type == "speedtrap" then button("Set speed trap here", "settrap " .. target)
        elseif e.type == "parking" then
          button("Add bay here", "addbay " .. target); same(); button("Undo bay", "undobay " .. target); same()
          button("Clear bays", "clearbays " .. target)
          txt("Park in each spot facing the way the bay should face. Bays are parked in the order you add them.")
        else
          local what = (e.type == "slalom") and "gate" or "checkpoint"
          button("Add " .. what, "addcp " .. target); same(); button("Undo " .. what, "undocp " .. target); same()
          button("Clear " .. what .. "s", "clearcp " .. target)
          if e.type == "slalom" then txt("Gates in order - the last one is the finish.")
          elseif e.type == "circuit" or e.type == "rpc" then
            txt("Checkpoints round the lap, in order. The start point is the start/finish line - each lap ends by crossing it.")
            local lp = intPtr("laps" .. target, e.laps or 3)
            im.InputInt("Laps##laps", lp); same(); button("Set laps##setlaps", "setlaps " .. target .. " " .. lp[0])
            if e.type == "rpc" then
              txt("The reasonably priced car: " .. tostring(e.rpcCar) .. " - each driver gets a fresh one on the start line. Best lap wins.")
              button("Use the car I'm in##rpcmine", "setrpc " .. target .. " mine"); same()
              button("Default car##rpcdefault", "setrpc " .. target .. " default")
            end
          else txt("Checkpoints in order - the last one is the finish.") end
        end
        button("Add route waypoint", "addvia " .. target); same(); button("Undo route waypoint", "undovia " .. target); same()
        button("Clear route", "clearvia " .. target)
        local tl = intPtr("time" .. target, e.timeLimit or 600)
        im.InputInt("Time limit (s)##tl", tl); same(); button("Set time##settime", "settime " .. target .. " " .. tl[0])
        if e.solo then same(); txt("(per run)") end
        if e.type == "rpc" then txt("Mode: time trial - one at a time (always, for this type)")
        else
          txt("Mode:"); same()
          button((e.solo and "" or "> ") .. "Race - everyone at once##moderace", "setmode " .. target .. " race"); same()
          button((e.solo and "> " or "") .. "Time trial - one at a time##modetrial", "setmode " .. target .. " trial")
        end
        txt("Event type:")
        for i, t in ipairs(c.types or {}) do
          local label = (t.id == e.type and "> " or "") .. t.label .. "##ty_" .. t.id
          button(label, "settype " .. target .. " " .. t.id)
          if i % 4 ~= 0 then same() end
        end
        txt("")
        if c.idle then confirmButton("Delete this event", "delev", "delevent " .. target) end
        if e.type == "trailer" then same(); button("Test trailer spawn##tt", "trailertest"); same(); button("Remove test trailer##tto", "trailertest off") end
      end
      local nb = textBuf("rename")
      im.InputText("##rename", nb); same()
      if im.Button("Rename") then
        local nm = textOf(nb)
        if nm ~= "" then sendCmd("rename " .. target .. " " .. nm) end
      end
      im.Separator()
      if c.problems == 0 then colored(0.4, 1, 0.4, "Course complete.") else txt(c.problems .. " thing(s) still to set.") end
      if c.active then button("Save course##bottomsave", "course save " .. c.active); same() end
      if c.active and c.dirty then
        local saved = false
        for _, e in ipairs(c.library or {}) do if e.name == c.active then saved = true end end
        if saved then button("Revert to saved##revert", "course load " .. c.active); same() end
      end
      confirmButton("Clear this one", "clr1", "clearcourse " .. target); same()
      confirmButton("Clear ALL", "clrall", "clearcourse all")
    end
  end, true) end
end

ordinal = function(n)
  n = math.floor(n or 0)
  local suf = ({ "st", "nd", "rd" })[n % 10]
  if not suf or (n % 100 >= 11 and n % 100 <= 13) then suf = "th" end
  return n .. suf
end

local function tableFlags()
  local f = 0
  for _, name in ipairs({ "TableFlags_Borders", "TableFlags_RowBg", "TableFlags_SizingFixedFit" }) do
    f = f + (tonumber(im[name]) or 0)   -- distinct flag bits, so + is the same as OR
  end
  return f
end

local function drawResults(d)
  local s = d.summary
  local rows = s.rows or {}
  local win = rows[1]
  if win then
    Tabs.box("Winner", "winner", function()
      colored(1, 0.85, 0.2, string.format("WINNER: %s in the %s - %.1f points", win.name, win.car, win.points or 0))
    end)
  end
  Tabs.box("Results", "restable", function()

  -- build every cell as text first, so the table itself only draws
  local cols = { "#", "Driver", "Car" }
  for _, name in ipairs(s.events or {}) do cols[#cols + 1] = name end
  for _, c in ipairs({ "Condition", "Repairs", "Upgrades", "Tows", "Resets", "Drivability", "Points", "Cash left" }) do cols[#cols + 1] = c end
  local cells = {}
  for _, r in ipairs(rows) do
    local row = { ordinal(r.place), r.name, string.format("%s (%s)", r.car, commas(r.carPrice)) }
    for i = 1, #(s.events or {}) do row[#row + 1] = (r.places or {})[i] or "-" end
    if (r.condition or 0) > 0 then
      row[#row + 1] = string.format("%s (%s off), %d fixed (-%s)", CONDITION_NAMES[math.min(r.condition, 4)], commas(r.conditionSaving),
        r.faultsFixed or 0, commas(r.faultFixes))
    else row[#row + 1] = "New" end
    row[#row + 1] = commas(r.repairs)
    row[#row + 1] = commas(r.upgrades)
    local nt, nr = r.tows or 0, r.respawns or 0
    if nt + nr == 0 then row[#row + 1] = "0"
    elseif nr == 0 then row[#row + 1] = string.format("%d (%s)", nt, commas(r.towCost))
    else row[#row + 1] = string.format("%d + %d respawn%s (%s)", nt, nr, nr == 1 and "" or "s", commas(r.towCost)) end
    row[#row + 1] = (r.resets or 0) > 0 and string.format("%d (%s)", r.resets, commas(r.fines)) or "0"
    local insp = {}
    for _, sc in ipairs(r.inspections or {}) do insp[#insp + 1] = string.format("%g", sc) end
    row[#row + 1] = string.format("%.1f", r.drivability or 0) .. (#insp > 1 and (" (" .. table.concat(insp, "/") .. ")") or "")
    row[#row + 1] = string.format("%.1f", r.points or 0)
    row[#row + 1] = commas(r.cash)
    cells[#cells + 1] = row
  end

  if im.BeginTable and im.BeginTable("##tgsummary", #cols, tableFlags()) then
    local ok, err = pcall(function()
      for _, c in ipairs(cols) do im.TableSetupColumn(c) end
      im.TableHeadersRow()
      for _, row in ipairs(cells) do
        im.TableNextRow()
        for _, cell in ipairs(row) do im.TableNextColumn(); txt(cell) end
      end
    end)
    im.EndTable()   -- always closed, even if a cell failed
    if not ok then error(err) end
  else
    for _, row in ipairs(cells) do  -- fallback for builds without tables
      txt(row[1] .. "  " .. row[2] .. " - " .. row[3])
      local ev = {}
      for i, name in ipairs(s.events or {}) do ev[#ev + 1] = name .. ": " .. row[3 + i] end
      txt("    " .. table.concat(ev, " | "))
      local n = #row
      txt(string.format("    Condition %s | Repairs %s | Upgrades %s | Tows %s | Resets %s | Drivability %s | Points %s | Cash %s",
        row[n - 7], row[n - 6], row[n - 5], row[n - 4], row[n - 3], row[n - 2], row[n - 1], row[n]))
    end
  end

  end)
  Tabs.box("How the points add up", "respoints", function()
  for _, r in ipairs(rows) do
    local n = #(r.inspections or {})
    txt(string.format("  %s: %g from events + %.1f drivability%s%s%s = %.1f   (%d win%s)", r.name, r.eventPoints or 0,
      r.drivability or 0, n > 1 and string.format(" (average of %d inspections)", n) or "",
      (r.penalty or 0) > 0 and string.format(" - %g penalties", r.penalty) or "",
      (r.awards or 0) ~= 0 and string.format(" %s %g from the producers", r.awards > 0 and "+" or "-", math.abs(r.awards)) or "",
      r.points or 0, r.wins or 0, r.wins == 1 and "" or "s"))
  end
  end, true)
end

-- Parts tab -------------------------------------------------------------------------
-- Every slot on the player's car with the parts that fit it and what fitting each would cost - built the
-- way career mode's parts shop does it: the parts tree's suitablePartNames (0.31+) or jbeam/io's slot map,
-- names from getAvailableParts, prices from each part's information.value (the value billing uses too).
local function niceSlotName(key, model)
  local leaf = slotLeaf(key)
  if model and leaf:sub(1, #model + 1) == model .. "_" then leaf = leaf:sub(#model + 2) end
  leaf = leaf:gsub("_", " ")
  return (leaf:gsub("^%l", string.upper))
end

local function buildCatalogue(car)
  local jbeamIO = require("jbeam/io")
  local vd = core_vehicle_manager.getVehicleData(car:getID())
  if not (vd and vd.ioCtx) then error("no vehicle data for this car", 0) end
  local model = car:getJBeamFilename()
  local names = {}
  pcall(function()
    for n, desc in pairs(jbeamIO.getAvailableParts(vd.ioCtx) or {}) do
      if type(desc) == "table" and type(desc.description) == "string" and desc.description ~= "" then names[n] = desc.description end
    end
  end)
  local slots, method = {}, nil
  local tree = vd.config and vd.config.partsTree
  if type(tree) == "table" then   -- newer versions: each slot node lists the parts that fit it
    local function walk(node)
      if type(node) ~= "table" then return end
      if type(node.path) == "string" and type(node.suitablePartNames) == "table" and #node.suitablePartNames > 0 then
        slots[#slots + 1] = { key = node.path, chosen = node.chosenPartName or "", options = node.suitablePartNames }
      end
      for _, child in pairs(node.children or {}) do walk(child) end
    end
    walk(tree)
    if #slots > 0 then method = "parts tree" end
  end
  if #slots == 0 and jbeamIO.getAvailableSlotMap then   -- older versions: the career shop's slot map
    local slotMap = jbeamIO.getAvailableSlotMap(vd.ioCtx) or {}
    local parts = readParts(car)
    for key, chosen in pairs(parts) do
      local list = slotMap[key] or slotMap[slotLeaf(key)]
      if type(list) == "table" and #list > 0 then slots[#slots + 1] = { key = key, chosen = chosen or "", options = list } end
    end
    if #slots > 0 then method = "slot map" end
  end
  if #slots == 0 then error("couldn't list this car's parts on this BeamNG version", 0) end

  local prices = {}
  local function price(name)   -- nil = the game has no price for it
    if name == "" then return 0 end
    if prices[name] == nil then
      local ok, part = pcall(jbeamIO.getPart, vd.ioCtx, name)
      prices[name] = (ok and type(part) == "table" and part.information and tonumber(part.information.value)) or false
    end
    return prices[name] or nil
  end
  local out = {}
  for _, sl in ipairs(slots) do
    local e = { key = sl.key, name = niceSlotName(sl.key, model), chosen = sl.chosen, free = isFreeSlot(sl.key),
                chosenName = sl.chosen == "" and "(empty)" or (names[sl.chosen] or sl.chosen), chosenPrice = price(sl.chosen), options = {} }
    for _, n in ipairs(sl.options) do
      if type(n) == "string" and n ~= "" then e.options[#e.options + 1] = { part = n, name = names[n] or n, price = price(n) } end
    end
    table.sort(e.options, function(a, b)
      if (a.price or 0) ~= (b.price or 0) then return (a.price or 0) < (b.price or 0) end
      return a.name < b.name
    end)
    local others = 0
    for _, o in ipairs(e.options) do if o.part ~= e.chosen then others = others + 1 end end
    if others > 0 then out[#out + 1] = e end   -- only slots with something else to fit
  end
  table.sort(out, function(a, b) if a.free ~= b.free then return not a.free end return a.name < b.name end)
  return { slots = out, method = method, carId = car:getID(), model = model }
end

-- what fitting `opt` in slot `e` costs, the way the server bills it: the difference in value, x markup
-- for an upgrade, x resale for a cheaper part (a refund); a part with no game price counts as flatPartPrice
local function quote(e, opt, sh)
  if e.free then return 0, "free" end
  local delta
  if e.chosenPrice == nil or opt.price == nil then delta = sh.flat or 500
  else delta = opt.price - e.chosenPrice end
  if delta > 0 then
    local cost = math.floor(delta * (sh.markup or 1) + 0.5)
    return cost, "+" .. commas(cost) .. ((e.chosenPrice == nil or opt.price == nil) and " (no game price)" or "")
  end
  local refund = math.floor(-delta * (sh.resale or 0.5) + 0.5)
  if refund == 0 then return 0, "no charge" end
  return -refund, "refund " .. commas(refund)
end

-- fit a part through the game's own config functions; the rebuild that follows is billed like any part change
local function fitPart(key, partName)
  local ok, err = pcall(function()
    local pm = core_vehicle_partmgmt
    local conf = pm.getConfig() or {}
    if type(conf.parts) == "table" and next(conf.parts) then
      local parts = copyTable(conf.parts)
      parts[key] = partName
      pm.setPartsConfig(parts, true)
    elseif type(conf.partsTree) == "table" and pm.setPartsTreeConfig then
      local tree, found = copyTable(conf.partsTree), false
      local function walk(n)
        if type(n) ~= "table" or found then return end
        if n.path == key then n.chosenPartName, n.children, found = partName, nil, true; return end   -- the game refills its sub-slots
        for _, c in pairs(n.children or {}) do walk(c) end
      end
      walk(tree)
      if not found then error("slot " .. tostring(key) .. " not found") end
      pm.setPartsTreeConfig(tree, true)
    else
      error("can't read this car's configuration")
    end
  end)
  shop.cat, shop.tried = nil, nil   -- the car changes: list it again
  if not ok then
    warn("fitting " .. tostring(partName) .. " failed: " .. tostring(err))
    addLog("Couldn't fit that part here - use the game's parts menu instead.")
  end
end

local function drawParts(d)
  local car = getCar()
  if not car then txt("No car out."); return end
  if not (shop.cat and shop.cat.carId == car:getID()) and shop.tried ~= car:getID() then
    shop.tried = car:getID()
    local ok, res = pcall(buildCatalogue, car)
    if ok then shop.cat, shop.err = res, nil
    else shop.cat, shop.err = nil, sanitize(res); warn("parts list: " .. tostring(res)) end
  end
  local sh = d.shop or {}
  -- Fit only in the dealership and workshop phases (and in a workshop); otherwise the list is greyed out
  local canFit = (state.allowParts and (state.phase == "dealer" or state.phase == "workshop")) and true or false
  if canFit then
    colored(0.4, 1, 0.4, "Workshop open: click Fit. The price shown is what you're charged.")
  else
    colored(1, 0.8, 0.3, "Price list - parts can be fitted at the dealership or in a workshop.")
  end
  if im.Button("Refresh the list##partsrefresh") then shop.cat, shop.tried = nil, nil end
  Tabs.help("Upgrades cost the difference to the part you have; a cheaper part refunds " ..
    math.floor((sh.resale or 0.5) * 100 + 0.5) .. "% of the difference. Looks-only parts are free." ..
    ((sh.labour or 0) > 0 and ("\nLabour: " .. commas(sh.labour) .. " once per workshop" .. (sh.labourPaid and " (already paid)" or "") ..
      ". Parts that come with a part (e.g. an engine's own intake) are billed too.") or ""))
  if shop.err then colored(1, 0.4, 0.4, "Couldn't list your car's parts: " .. shop.err); return end
  local cat = shop.cat
  if not cat then return end
  local rec = { c = 0 }
  if not canFit then
    local g = { 0.30, 0.32, 0.34, 1 }
    pcall(pushColors, { Text = { 0.50, 0.52, 0.55, 1 }, Button = g, ButtonHovered = g, ButtonActive = g }, rec)
  end
  local ok, err = pcall(Tabs.partList, cat, sh, canFit)
  popColors(rec)
  if not ok then error(err, 0) end
end
Tabs.partList = function(cat, sh, canFit)   -- the slots and their parts (greyed, Fit inert, when canFit is false)
  local inFree = nil
  for _, e in ipairs(cat.slots) do
    if inFree ~= e.free then
      inFree = e.free
      im.Separator()
      heading(e.free and "LOOKS - FREE" or "PERFORMANCE PARTS")
    end
    if header(e.name .. "  -  " .. e.chosenName .. "##slot_" .. e.key) then
      for _, o in ipairs(e.options) do
        if o.part == e.chosen then
          colored(0.6, 0.8, 1, "      (fitted)  " .. o.name)
        else
          local cost, label = quote(e, o, sh)
          local over = cost > 0 and sh.credit and (cost + (sh.labourPaid and 0 or (sh.labour or 0))) > sh.credit
          if not over then
            if im.Button("Fit##fit_" .. e.key .. "_" .. o.part) and canFit then fitPart(e.key, o.part) end
            same()
          end
          if over then colored(1, 0.45, 0.45, "      " .. o.name .. "   " .. label .. " - over your limit")
          else txt(o.name .. "   " .. label) end
        end
      end
    end
  end
end
Tabs.parts = drawParts   -- (shown as the Parts box in the Dealership tab)

local function section(name, fn, d)  -- a broken section shows an error instead of breaking the window
  local ok, err = pcall(fn, d)
  if not ok and not ui.noTheme then
    ui.noTheme = true   -- first suspect: the colour theme. Redraw plain next frame and report.
    warn(name .. " error with the colour theme - theme switched off: " .. tostring(err))
    addLog("The colour theme didn't work on this BeamNG version and was switched off (/tg theme to retry).")
    txt("(redrawing without the colour theme...)")
    return
  end
  if not ok then
    txt("(" .. name .. " couldn't be drawn - see log)")
    if not ui.failed[name] then ui.failed[name] = true; warn(name .. " UI error: " .. tostring(err)) end
  end
end

-- A box: a collapsible section (ImGui's own header - its arrow folds it) with a rounded border round the header and
-- its contents. Every tab is a short stack of these. closed = starts folded. If the border can't be drawn on this
-- BeamNG version it's left off (plain headers), never breaking the window.
Tabs.box = function(title, id, fn, closed)
  local okP, at = pcall(function() return im.GetCursorScreenPos() end)
  local okW, avail = pcall(function() return im.GetContentRegionAvail() end)
  local hdr = im.CollapsingHeader1 or im.CollapsingHeader
  local label = title .. "##box_" .. id
  local okH, open = pcall(hdr, label, closed and 0 or (tonumber(imGet("TreeNodeFlags_DefaultOpen")) or 32))
  if not okH then open = hdr(label) end
  if open then
    local indent = imGet("Indent") ~= nil
    if indent then pcall(im.Indent, 8) end
    local ok, err = pcall(fn)
    if indent then pcall(im.Unindent, 8) end
    if not ok then error(err, 0) end
  end
  if not ui.noBoxes and okP and type(at) == "table" and okW and type(avail) == "table" and tonumber(avail.x) then
    local okD, errD = pcall(function()
      local bottom = im.GetCursorScreenPos()
      im.ImDrawList_AddRect(im.GetWindowDrawList(), im.ImVec2(at.x - 4, at.y - 3), im.ImVec2(at.x + avail.x + 4, bottom.y + 2),
        im.GetColorU322(im.ImVec4(0.40, 0.56, 0.95, 0.85)), 6, 0, 1.5)
    end)
    if not okD then ui.noBoxes = true; warn("box borders unavailable, plain sections instead: " .. tostring(errD)) end
  end
  pcall(im.Dummy, im.ImVec2(1, 8))   -- a gap before the next box
end

-- hover help: a dim "(?)" after the item before it; the explanation shows when the mouse is over it.
-- (Without hover support on this BeamNG version, the explanation is shown as a dim line instead.)
Tabs.help = function(text)
  same()
  colored(0.55, 0.62, 0.70, "(?)")
  local okH, hov = pcall(function() return im.IsItemHovered() end)
  if not okH then colored(0.65, 0.65, 0.65, text); return end
  if hov then pcall(function() im.SetTooltip((tostring(text):gsub("%%", "%%%%"))) end) end
end

-- The message log under the tabs: a "System messages" heading and a tinted, bordered box (a child window) with the
-- last few lines, newest brightest. BeginChild isn't used anywhere else, so if it fails the lines show plain.
Tabs.messages = function() Tabs.box("Messages", "messages", Tabs.messageLines) end   -- (under every tab)
Tabs.messageLines = function()
  local MSG_LINES = 6
  local MSG_BOX = { ChildBg = { 0.05, 0.09, 0.22, 1 }, Border = { 0.40, 0.56, 0.95, 0.80 } }
  local from = math.max(1, #ui.log - MSG_LINES + 1)
  local function lines()
    if #ui.log == 0 then colored(0.55, 0.62, 0.70, "No messages yet."); return end
    for i = from, #ui.log do
      if i == #ui.log then colored(0.95, 0.97, 1.00, ui.log[i]) else colored(0.70, 0.76, 0.86, ui.log[i]) end
    end
  end
  local begin = imGet("BeginChild1") or imGet("BeginChild")
  local okH, lh = pcall(function() return im.GetTextLineHeightWithSpacing() end)
  lh = (okH and tonumber(lh)) or 17
  local rec = { c = 0 }
  pcall(pushColors, MSG_BOX, rec)
  local okB, err = false, "no BeginChild"
  if begin then okB, err = pcall(begin, "##tgmessages", im.ImVec2(0, MSG_LINES * lh + 12), 1) end   -- 1 = border (bool or child flags)
  if okB then
    local okL, errL = pcall(lines)
    pcall(im.EndChild)   -- always, whatever BeginChild returned
    popColors(rec)
    if not okL and not ui.failed.messages then ui.failed.messages = true; warn("messages UI error: " .. tostring(errL)) end
  else
    popColors(rec)
    if not ui.failed.msgbox then ui.failed.msgbox = true; warn("message box unavailable, plain lines instead: " .. tostring(err)) end
    lines()
  end
end

-- A step button on the Quick start tab: "lit" (green, clickable), "done" (dim, says so) or "wait" (grey, ignores
-- clicks). Every colour push is popped here, whatever the button does.
Tabs.step = function(label, id, how)
  local rec = { c = 0 }
  local cols
  if how == "lit" then
    cols = { Button = { 0.10, 0.62, 0.20, 1 }, ButtonHovered = { 0.25, 0.85, 0.30, 1 }, ButtonActive = { 0.05, 0.40, 0.10, 1 },
             Text = { 1, 1, 1, 1 } }
  elseif how == "red" then   -- (an undo: Return this car)
    cols = { Button = { 0.70, 0.12, 0.12, 1 }, ButtonHovered = { 0.88, 0.22, 0.20, 1 }, ButtonActive = { 0.50, 0.06, 0.06, 1 },
             Text = { 1, 1, 1, 1 } }
  elseif how == "done" then
    cols = { Button = { 0.14, 0.26, 0.30, 1 }, ButtonHovered = { 0.14, 0.26, 0.30, 1 }, ButtonActive = { 0.14, 0.26, 0.30, 1 },
             Text = { 0.60, 0.80, 0.65, 1 } }
  else
    cols = { Button = { 0.22, 0.24, 0.26, 1 }, ButtonHovered = { 0.22, 0.24, 0.26, 1 }, ButtonActive = { 0.22, 0.24, 0.26, 1 },
             Text = { 0.50, 0.52, 0.55, 1 } }
  end
  pcall(pushColors, cols, rec)
  local okB, clicked = pcall(im.Button, (how == "done" and (label .. "  (done)") or label) .. "##" .. id, im.ImVec2(-1, 36))
  popColors(rec)
  if not okB then error(clicked) end
  return clicked and (how == "lit" or how == "red")
end

-- A dropdown; items = { { label, value, selected } }. Returns the picked value, or nil.
Tabs.combo = function(id, preview, items)
  local picked
  if im.BeginCombo then
    if im.BeginCombo("##" .. id, preview) then
      local ok, err = pcall(function()
        local selectable = im.Selectable1 or im.Selectable
        for i, it in ipairs(items) do
          if selectable(it[1] .. "##" .. id .. "_" .. i, it[3] == true) then picked = it[2] end
        end
      end)
      im.EndCombo()   -- always closed, even if an entry failed
      if not ok then error(err) end
    end
  else
    for i, it in ipairs(items) do   -- fallback for builds without dropdowns
      if im.Button((it[3] and "> " or "") .. it[1] .. "##" .. id .. "b_" .. i) then picked = it[2] end
    end
  end
  return picked
end

-- Quick start (the first tab): an admin answers three questions (course, budget, cars) and presses Start; then every
-- player picks a car condition and goes to the dealer. Each step lights up only once the one before it is done.
Tabs.quick = function(d)
  local me, fl, admin = d.me, d.faults, d.admin
  local idle, dealer = d.phase == "idle", d.phase == "dealer"
  if not ui.quick or (idle and ui.quick.phase ~= "idle") then ui.quick = {} end   -- back to idle: a new challenge
  local q = ui.quick
  q.phase = d.phase
  local c, cl = d.course or {}, d.classes or {}
  local ready, budget = false, nil

  Tabs.box("Setup", "setup", function()
  heading("SET UP THE CHALLENGE")
  if not admin then
    colored(0.65, 0.65, 0.65, idle and "Waiting for an admin to set up and start the challenge." or "The challenge is set up.")
  else
    txt("1. What course do you want to load?")
    if idle then
      local items = {}
      for _, e in ipairs(c.library or {}) do
        items[#items + 1] = { e.name .. ((e.problems or 0) > 0 and ("  (" .. e.problems .. " to set)") or ""), e.name, e.name == c.active }
      end
      if #items == 0 then
        colored(1, 0.8, 0.3, "No saved courses yet - build one in the Admin tab's Course builder.")
      else
        if q.course == c.active then q.course = nil end   -- (loaded)
        for _, it in ipairs(items) do it[3] = it[2] == (q.course or c.active) end
        local pick = Tabs.combo("qcourse", q.course or c.active or "Pick a course...", items)
        if pick then q.course = pick end
        same()
        if im.Button((q.course and "Load" or "Loaded") .. "##qload") and q.course then sendCmd("course load " .. q.course) end
      end
      if c.active and c.dirty then colored(1, 0.8, 0.3, "The loaded course has unsaved changes - picking another drops them.") end
    else
      txt("   " .. tostring(c.active or "(unnamed course)"))
    end
    ready = c.active ~= nil and (c.problems or 0) == 0
    if c.active and (c.problems or 0) > 0 then
      colored(1, 0.8, 0.3, string.format("   %s isn't finished: %d thing%s to set (Admin tab, Course builder).",
        c.active, c.problems, c.problems == 1 and "" or "s"))
    end

    txt("2. What is the budget?")
    if idle then
      budget = intPtr("qbudget", d.baseBudget or d.budget)
      im.InputInt("Budget##qbudget", budget)
    else
      txt("   " .. commas(d.baseBudget or d.budget))
    end

    txt("3. What type of cars do you want to drive?")
    if idle then
      local items, made = { { "Any car (" .. tostring(cl.none or "no class") .. ")", "none", cl.active == nil } }, {}
      for _, e in ipairs(cl.list or {}) do
        made[e.name] = true
        items[#items + 1] = { string.format("%s - %d cars%s", e.name, e.count or 0,
          e.min and string.format(", %s to %s", commas(e.min), commas(e.max)) or ""), "use " .. e.name, e.name == cl.active }
      end
      for _, pr in ipairs(cl.presets or {}) do   -- ready-made classes not made yet: picking one makes it, then uses it
        if not made[pr.key] then
          items[#items + 1] = { string.format("%s (%s cars)", tostring(pr.title or pr.key), tostring(pr.count or "?")), "preset " .. pr.key, false }
        end
      end
      local pick = Tabs.combo("qclass", cl.active or "Any car", items)
      if pick == "none" then
        sendCmd("class use none")
      elseif pick and pick:sub(1, 4) == "use " then
        sendCmd("class " .. pick)
      elseif pick then
        local key = pick:sub(8)
        sendCmd("class preset " .. key); sendCmd("class use " .. key)
      end
    else
      txt("   " .. tostring(d.dealerClass and d.dealerClass.name or cl.active or "Any car"))
    end
  end

  end)

  Tabs.box("Dealer", "dealer", function()
  heading("GO")
  local rd = d.ready
  if dealer and rd and (rd.total or 0) > 0 then   -- top right of the box: how many are ready
    local okW, avail = pcall(function() return im.GetContentRegionAvail() end)
    local x = okW and type(avail) == "table" and tonumber(avail.x) or nil
    if x and x > 260 then pcall(im.SameLine, x - 170) else same() end
    local line = string.format("%d/%d player%s ready", rd.n or 0, rd.total, rd.total == 1 and " is" or "s are")
    if (rd.n or 0) >= rd.total then colored(0.4, 1, 0.4, line) else colored(1, 0.85, 0.3, line) end
  end
  if dealer and d.readyGo then colored(0.4, 1, 0.4, string.format("Everyone's ready - starting in %d...", d.readyGo)) end
  if idle then
    if Tabs.step("Start the challenge", "qstart", (admin and ready) and "lit" or "wait") then
      if budget and budget[0] ~= (d.baseBudget or d.budget) then sendCmd("budget " .. budget[0]) end
      sendCmd("start")
    end
    if not admin then colored(0.65, 0.65, 0.65, "An admin presses Start.")
    elseif not ready then colored(0.65, 0.65, 0.65, "Load a finished course first.") end
  else
    Tabs.step("Start the challenge", "qstart", "done")
  end

  -- car condition: a dropdown, lit once the challenge has started
  local count = fl and fl.count or 0
  local function cname(n) return ((fl and fl.levels or {})[n + 1] or {}).name or CONDITION_NAMES[n] or tostring(n) end
  local canPick = dealer and me and fl and not fl.locked and not me.hasCar
  local chosen = q.cond or count > 0
  if canPick then
    txt("Car condition:")
    same()
    local items = {}
    for n = 0, math.min(fl.max or 4, 4) do
      local off = ((fl.levels or {})[n + 1] or {}).off or 0
      items[#items + 1] = { cname(n) .. (n > 0 and string.format("  (%d%% off)", off) or "  (full price)"), n, chosen and n == count }
    end
    local rec = { c = 0 }
    if not chosen then pcall(pushColors, { FrameBg = { 0.10, 0.62, 0.20, 1 }, FrameBgHovered = { 0.25, 0.85, 0.30, 1 } }, rec) end
    local okC, pick = pcall(Tabs.combo, "qcond", chosen and cname(count) or "Pick a condition...", items)
    popColors(rec)
    if not okC then error(pick) end
    if pick then
      q.cond = true
      if pick ~= count then sendCmd("condition " .. pick) end
    end
  elseif (dealer and me and me.hasCar) or not (idle or dealer) then
    Tabs.step("Car condition: " .. cname(count), "qcond", "done")
  else
    Tabs.step("Car condition (after Start)", "qcond", "wait")
  end

  -- the dealer: opens the game's vehicle selector with today's cars
  if dealer and me and me.hasCar then
    Tabs.step("Go to the dealer - you bought the " .. tostring(me.car), "qdealer", "done")
  elseif not (idle or dealer) then
    Tabs.step("Go to the dealer", "qdealer", "done")
    colored(0.65, 0.65, 0.65, "The challenge is under way - the Status tab has the rest.")
  else
    local lit = canPick and chosen and not (ui.busy and (ui.t - ui.busy) < 5)
    if Tabs.step("Go to the dealer", "qdealer", lit and "lit" or "wait") then M.openSelector() end
    if canPick and not chosen then colored(0.65, 0.65, 0.65, "Pick a car condition first.") end
    if lit then colored(0.65, 0.65, 0.65, "Opens the vehicle selector with today's cars - spawning one buys it.") end
  end

  -- changed your mind? return the car (full refund) and pick another - two clicks, red; locked once you're ready
  if dealer and me and me.hasCar and not me.ready then
    local armed = q.returnAt and (ui.t - q.returnAt) < 3
    if Tabs.step(armed and "Really? Click again to return it" or ("Return this car - full refund"), "qreturn", "red") then
      if armed then q.returnAt = nil; returnCar() else q.returnAt = ui.t end
    end
  elseif dealer and me and me.ready then
    Tabs.step("Return this car - locked, you're ready", "qreturn", "wait")
  else
    Tabs.step("Return this car", "qreturn", "wait")
  end
  -- I'm ready: locks the car in; when everyone is, a 5 s countdown starts the challenge
  if dealer and me and me.ready then
    Tabs.step("I'm ready", "qready", "done")
  elseif dealer and me and me.hasCar then
    if Tabs.step("I'm ready", "qready", "lit") then sendCmd("ready") end
    colored(0.65, 0.65, 0.65, "Locks in your car. When everyone's ready, the challenge starts.")
  elseif not (idle or dealer) then
    Tabs.step("I'm ready", "qready", "done")
  else
    Tabs.step("I'm ready", "qready", "wait")
  end
  end)
end

local function drawWindow(dt)
  ui.t = ui.t + dt
  ui.reqTimer = ui.reqTimer - dt
  if ui.reqTimer <= 0 then ui.reqTimer = 2; requestUi() end
  if not ui.openPtr then ui.openPtr = im.BoolPtr(true) end
  ui.openPtr[0] = true
  local ALWAYS, FIRST = im.Cond_Always or 1, im.Cond_FirstUseEver or 4
  if ui.layout == "reset" and im.SetNextWindowPos then im.SetNextWindowPos(im.ImVec2(80, 80), ALWAYS) end
  if ui.layout == "results" and im.SetNextWindowSize then im.SetNextWindowSize(im.ImVec2(1100, 520), ALWAYS)
  elseif im.SetNextWindowSize then im.SetNextWindowSize(im.ImVec2(560, 600), ui.layout == "reset" and ALWAYS or FIRST) end
  if ui.layout and im.SetNextWindowCollapsed then im.SetNextWindowCollapsed(false, ALWAYS) end  -- never reopen collapsed
  if im.SetNextWindowSizeConstraints then im.SetNextWindowSizeConstraints(im.ImVec2(420, 320), im.ImVec2(4000, 4000)) end
  ui.layout = nil
  if im.Begin("Top Gear Challenge##tg", ui.openPtr) then
    local d = ui.data
    if not d then txt("Loading...")
    else
      -- Start | Status | Dealership | Admin | Settings | Results - each tab a short stack of boxes (Tabs.box)
      if im.BeginTabBar("##tgtabs") then
        local quickOpen
        if ui.selectQuick and (d.phase == "idle" or d.phase == "dealer") and im.TabItemFlags_SetSelected then
          quickOpen = im.BeginTabItem("Start", nil, im.TabItemFlags_SetSelected)
        else
          quickOpen = im.BeginTabItem("Start")
        end
        ui.selectQuick = false
        if quickOpen then section("Start", Tabs.quick, d); im.EndTabItem() end
        local statusOpen
        if ui.selectStatus and im.TabItemFlags_SetSelected then
          statusOpen = im.BeginTabItem("Status", nil, im.TabItemFlags_SetSelected)
          if ui.open then ui.selectStatus = false end   -- (once; a closed window opens on it next time)
        else
          statusOpen = im.BeginTabItem("Status")
        end
        if statusOpen then section("Status", drawStatus, d); im.EndTabItem() end
        if im.BeginTabItem("Dealership") then section("Dealership", drawDealer, d); im.EndTabItem() end
        if d.admin and im.BeginTabItem("Admin") then section("Admin", drawAdmin, d); im.EndTabItem() end
        if im.BeginTabItem("Settings") then section("Settings", drawSettings, d); im.EndTabItem() end
        if d.summary then
          local open
          if ui.selectResults and im.TabItemFlags_SetSelected then
            open = im.BeginTabItem("Results", nil, im.TabItemFlags_SetSelected)
          else
            open = im.BeginTabItem("Results")
          end
          if open then ui.selectResults = false; section("Results", drawResults, d); im.EndTabItem() end
        end
        im.EndTabBar()
      end
      Tabs.messages()
    end
  end
  im.End()
  if not ui.openPtr[0] then ui.open = false end
end

-- F1-style starting lights: five reds come on one per second, then all go out for GO
local function drawLights(dt)
  lights.clock = lights.clock + dt
  local L = (state.phase ~= "idle") and state.lights or nil
  local left = L and ((tonumber(L.left) or 0) - stateAge) or nil
  if not L and lights.pinned then   -- /tg lights: keep the box up (all dark) so it can be moved
    L, left = { total = 5, who = "Drag me" }, 99
  end
  if not L and lights.test then   -- /tg lightstest: a 5-second sequence with no race
    L = { total = 5, who = "Test" }
    left = 5 - (lights.clock - lights.test)
    if left <= 0 then lights.test = nil end
  end
  local lit = 0
  if L and L.who == "Drag me" then
    lit = 0
  elseif left and left > 0 then
    local total = math.max(1, tonumber(L.total) or 5)
    lit = math.min(5, math.max(0, 5 - math.ceil(left * 5 / total) + 1))
    lights.wasOn, lights.who, lights.goUntil = true, L.who, nil
  elseif lights.wasOn then
    lights.wasOn, lights.goUntil = false, lights.clock + 1.5
  end
  local go = lights.goUntil ~= nil and lights.clock < lights.goUntil
  if lit == 0 and not go and not lights.pinned then return end
  im = im or ui_imgui
  if not im then return end
  local width = 800
  pcall(function() width = im.GetIO().DisplaySize.x end)
  local flags = 0
  -- its own window: title bar to drag it, position remembered by the game, never docked into the TG menu
  for _, f in ipairs({ "WindowFlags_NoResize", "WindowFlags_NoScrollbar", "WindowFlags_NoCollapse",
                       "WindowFlags_AlwaysAutoResize", "WindowFlags_NoFocusOnAppearing", "WindowFlags_NoDocking" }) do
    local okF, v = pcall(function() return im[f] end)   -- a flag this version doesn't have is just skipped
    flags = flags + ((okF and tonumber(v)) or 0)
  end
  if im.SetNextWindowPos then im.SetNextWindowPos(im.ImVec2(width / 2 - 185, 70), im.Cond_FirstUseEver or 4) end
  -- open it exactly like the main window (a real open flag, not nil)
  if not lights.openPtr then lights.openPtr = im.BoolPtr(true) end
  lights.openPtr[0] = true
  if im.Begin("Start lights##tglights", lights.openPtr, flags) then
    local ok = pcall(function()
      local title = go and "GO!" or ((L and L.who == "Drag me") and "Drag this box by its title bar - /tg lights to hide"
                    or (lights.who and (lights.who .. "'s run") or "Lights..."))
      if go then colored(0.3, 1, 0.3, title) else txt(title) end
      local dl = im.GetWindowDrawList()
      local at = im.GetCursorScreenPos()
      for i = 1, 5 do
        local r, g, b = 0.12, 0.12, 0.12
        if go then r, g, b = 0.1, 0.9, 0.2 elseif i <= lit then r, g, b = 0.95, 0.05, 0.05 end
        im.ImDrawList_AddCircleFilled(dl, im.ImVec2(at.x + 35 + (i - 1) * 70, at.y + 35), 28, im.GetColorU322(im.ImVec4(r, g, b, 1)), 24)
      end
      im.Dummy(im.ImVec2(350, 72))
    end)
    if not ok then   -- builds without draw lists: text lights
      for i = 1, 5 do
        if go then colored(0.3, 1, 0.3, "( GO )") elseif i <= lit then colored(1, 0.1, 0.1, "(####)") else txt("(    )") end
        if i < 5 then same() end
      end
    end
  end
  im.End()
end

-- Finish flag: its own movable window, shown for a few seconds when your run is complete
local function drawFlag(dt)
  flag.clock = flag.clock + dt
  local showing = flag.untilT ~= nil and flag.clock < flag.untilT
  if not showing then flag.untilT = nil end
  if not showing and not flag.pinned then return end
  im = im or ui_imgui
  if not im then return end
  local width = 800
  pcall(function() width = im.GetIO().DisplaySize.x end)
  local flags = 0
  for _, f in ipairs({ "WindowFlags_NoResize", "WindowFlags_NoScrollbar", "WindowFlags_NoCollapse",
                       "WindowFlags_AlwaysAutoResize", "WindowFlags_NoFocusOnAppearing", "WindowFlags_NoDocking" }) do
    local okF, v = pcall(function() return im[f] end)
    flags = flags + ((okF and tonumber(v)) or 0)
  end
  if im.SetNextWindowPos then im.SetNextWindowPos(im.ImVec2(width / 2 - 170, 170), im.Cond_FirstUseEver or 4) end
  if not flag.openPtr then flag.openPtr = im.BoolPtr(true) end
  flag.openPtr[0] = true
  local okBody, errBody = true, nil
  if im.Begin("Finish##tgflag", flag.openPtr, flags) then
    okBody, errBody = pcall(function()
      local okDraw = pcall(function()   -- a checkered flag: 12 x 4 squares
        local dl = im.GetWindowDrawList()
        local at = im.GetCursorScreenPos()
        local sq = 28
        for r = 0, 3 do
          for c = 0, 11 do
            local v = ((r + c) % 2 == 0) and 0.95 or 0.05
            im.ImDrawList_AddRectFilled(dl, im.ImVec2(at.x + c * sq, at.y + r * sq), im.ImVec2(at.x + (c + 1) * sq, at.y + (r + 1) * sq),
              im.GetColorU322(im.ImVec4(v, v, v, 1)))
          end
        end
        im.Dummy(im.ImVec2(12 * sq, 4 * sq))
      end)
      if not okDraw then txt("[#] [ ] [#] [ ] [#] [ ] [#] [ ]") end   -- builds without draw lists
      local scaled = im.SetWindowFontScale and pcall(im.SetWindowFontScale, 3) or false
      colored(1, 0.85, 0.2, "FINISH")
      if scaled then pcall(im.SetWindowFontScale, 1) end
      if not showing then
        txt("Drag this box by its title bar - /tg flag to hide")
      else
        if flag.title then txt(flag.title) end
        if flag.detail then txt(flag.detail) end
      end
    end)
  end
  im.End()   -- always closed, even if the contents failed
  if not okBody then error(errBody) end
end

local function updateWindow(dt)
  if not ui.open then return end
  im = im or ui_imgui
  if not im then warn("ui_imgui not available - use the /tg chat commands"); ui.open = false; return end
  local rec = { c = 0, v = 0 }
  if not ui.noTheme then pcall(pushTheme, rec) end
  local ok, err = pcall(drawWindow, dt)
  popTheme(rec)
  if not ok then
    if not ui.noTheme then
      ui.noTheme = true   -- keep the menu open, plain, and report what failed
      warn("window error with the colour theme - theme switched off: " .. tostring(err))
      addLog("The colour theme didn't work on this BeamNG version and was switched off (/tg theme to retry).")
    else
      warn("window error: " .. tostring(err)); ui.open = false
    end
  end
end

local function onMenu(data)
  local wasOpen = ui.open
  if data == "open" or data == "reset" then ui.open = true else ui.open = not ui.open end
  if data == "results" then ui.open = true; ui.layout = "results"; ui.selectResults = true end
  if data == "reset" then ui.layout = "reset" elseif ui.open and not wasOpen and not ui.layout then ui.layout = "open" end
  if ui.open and not wasOpen and data ~= "results" then ui.selectQuick = true end   -- Quick start first (before/at the dealership)
  if ui.open then ui.reqTimer = 0 end
end
local function onUi(data)
  local ok, t = pcall(jsonDecode, data)
  if ok and type(t) == "table" then
    if t.dealerSame then t.dealer = ui.data and ui.data.dealer or {} end   -- unchanged car list: not re-sent
    ui.data = t; ui.busy = nil
  end
end
function M.toggleMenu() onMenu("") end

local sinceLoad, warnedNoApi = 0, false

local function getAddHandler()
  if type(AddEventHandler) == "function" then return AddEventHandler end
  if MPGameNetwork and type(MPGameNetwork.addEventHandler) == "function" then return MPGameNetwork.addEventHandler end
  return nil
end

local function tryRegister(dt)
  if registered then return end
  local add = getAddHandler()
  if not add then
    sinceLoad = sinceLoad + (dt or 0)
    if sinceLoad > 15 and not warnedNoApi then
      warnedNoApi = true
      warn("BeamMP event API not found after 15 s (AddEventHandler=" .. type(AddEventHandler) ..
        ", MPGameNetwork=" .. type(MPGameNetwork) .. ") - are you connected to a BeamMP server?")
    end
    return
  end
  local ok, err = pcall(function()
    add("tg_state",  onState)
    add("tg_repair", onRepair)
    add("tg_msg",    onMsg)
    add("tg_diag",   onDiag)
    add("tg_import", onImport)
    add("tg_menu",   onMenu)
    add("tg_ui",     onUi)
    add("tg_dealerlist", onDealerList)
    add("tg_log",    addLog)
    add("tg_faults", onFaults)
    add("tg_tow",    onTow)
    add("tg_unstick", onUnstick)
    add("tg_respawn", onRespawn)
    add("tg_trailer", onTrailer)
    add("tg_trailer_clear", onTrailerClear)
    add("tg_lightstest", onLightsTest)
    add("tg_lightspin", onLightsPin)
    add("tg_finish", onFinish)
    add("tg_flagtest", onFlagTest)
    add("tg_flagpin", onFlagPin)
    add("tg_sound", onSound)
    add("tg_theme", onTheme)
    add("tg_partsdiag", onPartsDiag)
    add("tg_findgas", onFindGas)
    add("tg_revertparts", onRevertParts)
    add("tg_trailersave", onTrailerSave)
    add("tg_hitchup", onHitchUp)
    add("tg_rpc", Rpc.onStart)
    add("tg_rpc_end", Rpc.onEnd)
  end)
  if not ok then warn("registering BeamMP events failed: " .. tostring(err)); return end
  registered = true
  log("I", "topgear", "Top Gear Challenge client " .. VERSION .. " ready (BeamMP events registered)")
end

-- what's left in the car, read from its own Lua (for the economy run): litres in the fuel tanks, and the energy
-- stored in tanks AND batteries (joules) - the same unit for petrol, diesel and electric cars
local fuelValue, energyValue = nil, nil
function M.onFuel(litres, joules) fuelValue, energyValue = tonumber(litres), tonumber(joules) end
local FUEL_VLUA = [[
local litres, joules, gotL, gotE = 0, 0, false, false
pcall(function()
  if energyStorage and energyStorage.getStorages then
    for _, st in pairs(energyStorage.getStorages()) do
      if type(st) == "table" then
        if st.type == "fuelTank" and type(st.remainingVolume) == "number" then litres, gotL = litres + st.remainingVolume, true end
        if (st.type == "fuelTank" or st.type == "electricBattery") and type(st.storedEnergy) == "number" then
          joules, gotE = joules + st.storedEnergy, true
        end
      end
    end
  end
end)
if not gotL and electrics and electrics.values and type(electrics.values.fuelVolume) == "number" then
  litres, gotL = electrics.values.fuelVolume, true
end
if gotL or gotE then
  obj:queueGameEngineLua("extensions.topgear.onFuel(" .. (gotL and string.format("%.4f", litres) or "nil") .. "," ..
    (gotE and string.format("%.0f", joules) or "nil") .. ")")
end
]]

-- Workshop billing: snapshot the car's parts; after every rebuild, report exactly what changed.
-- Cosmetic and mod-managed slots (isFreeSlot) and tuning values are free; the server bills the rest.
local cfgSnap, rebuildCheckIn = nil, nil

-- A car's parts as { slot-or-path = partName }, from whichever format this BeamNG version uses.
walkTree = function(node, out, path)
  if type(node) ~= "table" then return end
  local name = node.chosenPartName or node.partName
  local key = node.path or path or "/"
  if type(name) == "string" then out[key] = name end
  local kids = node.children or node.slots
  if type(kids) == "table" then
    for slot, child in pairs(kids) do walkTree(child, out, key .. tostring(slot) .. "/") end
  end
end

readParts = function(car)
  local conf, vd
  pcall(function() conf = core_vehicle_partmgmt.getConfig() end)
  pcall(function() vd = core_vehicle_manager.getVehicleData(car:getID()) end)
  local out, fmt = {}, nil
  if type(conf) == "table" and type(conf.parts) == "table" and next(conf.parts) then
    for k, v in pairs(conf.parts) do out[k] = v end; fmt = "flat parts"
  elseif type(conf) == "table" and type(conf.partsTree) == "table" then
    walkTree(conf.partsTree, out, "/"); fmt = "parts tree"
  elseif vd and type(vd.chosenParts) == "table" and next(vd.chosenParts) then
    for k, v in pairs(vd.chosenParts) do out[k] = v end; fmt = "chosenParts"
  elseif vd and type(vd.config) == "table" and type(vd.config.partsTree) == "table" then
    walkTree(vd.config.partsTree, out, "/"); fmt = "vehicle data parts tree"
  end
  return out, fmt, conf, vd
end

-- part prices (the same "value" career mode's shop uses), from the car's loaded parts, else jbeam
local function priceMap(vd)
  local map = {}
  local active = vd and vd.vdata and vd.vdata.activeParts
  if type(active) == "table" then
    for k, part in pairs(active) do
      local val = type(part) == "table" and part.information and tonumber(part.information.value)
      if val then
        map[tostring(k)] = val
        if part.partName then map[tostring(part.partName)] = val end
      end
    end
  end
  return map
end
local function partValue(vd, prices, name)
  if type(name) ~= "string" or name == "" then return nil end
  if prices[name] then return prices[name] end
  local ok, part = pcall(function() return require("jbeam/io").getPart(vd and vd.ioCtx, name) end)
  return ok and part and part.information and tonumber(part.information.value) or nil
end

copyTable = function(t, depth)
  if type(t) ~= "table" or (depth or 0) > 30 then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = copyTable(v, (depth or 0) + 1) end
  return r
end

local function takeSnapshot(car)
  local parts, fmt, conf, vd = readParts(car)
  if not fmt then return nil end
  local prices = priceMap(vd)
  local snap = { carId = car:getID(), parts = parts, vars = {}, values = {}, fmt = fmt, conf = copyTable(conf) }
  for k, v in pairs((type(conf) == "table" and conf.vars) or {}) do snap.vars[k] = v end
  for slot, name in pairs(parts) do
    if not isFreeSlot(slot) then
      local val = partValue(vd, prices, name)
      if val == nil then snap.values[slot] = false else snap.values[slot] = val end   -- false = price unknown
    end
  end
  return snap
end

onPartsDiag = function()
  local car = getCar()
  local r = { count = 0, priced = 0, examples = {} }
  local ok, err = pcall(function()
    if not car then error("no car") end
    local snap = takeSnapshot(car)
    if not snap then error("couldn't read this car's parts (unknown format)") end
    r.format = snap.fmt
    for slot, name in pairs(snap.parts) do
      if name ~= "" then
        r.count = r.count + 1
        local v = snap.values[slot]
        if type(v) == "number" then
          r.priced = r.priced + 1
          if #r.examples < 5 and v > 0 then r.examples[#r.examples + 1] = string.format("%s = $%d", name, math.floor(v)) end
        end
      end
    end
  end)
  if not ok then r.err = sanitize(err) end
  local okC, cat = pcall(buildCatalogue, car)   -- what the Parts tab can list
  if okC then
    r.shopMethod, r.shopSlots, r.shopOptions, r.shopPriced = cat.method, #cat.slots, 0, 0
    for _, e in ipairs(cat.slots) do
      for _, o in ipairs(e.options) do
        r.shopOptions = r.shopOptions + 1
        if o.price then r.shopPriced = r.shopPriced + 1 end
      end
    end
  else r.shopErr = sanitize(cat) end
  if TriggerServerEvent then TriggerServerEvent("tg_partsdiag_reply", jsonEncode(r)) end
end

-- gas stations on this map: the freeroam facility list, else fuel-pump objects in the scene
local function findGasStations()
  local out, method, errs = {}, nil, {}
  local function add(pos, name) if pos then out[#out + 1] = { x = pos.x, y = pos.y, z = pos.z, name = name } end end
  local ok, e = pcall(function()
    local fac = freeroam_facilities
    if not fac then error("no facilities module") end
    local list
    if fac.getFacilitiesByType then list = fac.getFacilitiesByType("gasStation") end
    if (not list or #list == 0) and fac.getFacilities then
      local lvl = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or nil
      local all = fac.getFacilities(lvl)
      list = all and (all.gasStations or all.gasStation)
    end
    for i, g in ipairs(list or {}) do
      local sum, n = vec3(0, 0, 0), 0
      for _, pumpName in ipairs(g.pumps or {}) do
        local o = scenetree.findObject(pumpName)
        if o then sum = sum + vec3(o:getPosition()); n = n + 1 end
      end
      if n > 0 then add(sum * (1 / n), g.name or ("Gas station " .. i))
      elseif g.pos then add(vec3(g.pos), g.name or ("Gas station " .. i)) end
    end
    if #out > 0 then method = "map facilities" end
  end)
  if not ok then errs[#errs + 1] = tostring(e) end
  if #out == 0 then
    local ok2, e2 = pcall(function()
      local pumps = {}
      for _, nm in ipairs(scenetree.findClassObjects("TSStatic") or {}) do
        local o = scenetree.findObject(nm)
        if o then
          local shape = ""
          pcall(function() shape = tostring(o:getField("shapeName", 0) or "") end)
          shape, nm = shape:lower(), tostring(nm):lower()
          if (shape:find("pump") and (shape:find("fuel") or shape:find("gas") or shape:find("petrol")))
             or nm:find("fuelpump") or nm:find("gaspump") or nm:find("fuel_pump") then
            pumps[#pumps + 1] = vec3(o:getPosition())
          end
        end
      end
      local clusters = {}
      for _, pp in ipairs(pumps) do
        local placed = false
        for _, c in ipairs(clusters) do
          if (c.sum * (1 / c.n) - pp):length() < 40 then c.sum, c.n, placed = c.sum + pp, c.n + 1, true; break end
        end
        if not placed then clusters[#clusters + 1] = { sum = pp, n = 1 } end
      end
      for i, c in ipairs(clusters) do add(c.sum * (1 / c.n), "Gas station " .. i) end
      if #out > 0 then method = "fuel pump objects" end
    end)
    if not ok2 then errs[#errs + 1] = tostring(e2) end
  end
  return out, method, (#errs > 0) and table.concat(errs, "; ") or nil
end

local function applyConfigTable(conf)
  local pm = core_vehicle_partmgmt
  local tries = {}
  if pm.setConfig then tries[#tries + 1] = function() pm.setConfig(conf, true) end end
  if type(conf.partsTree) == "table" and pm.setPartsTreeConfig then tries[#tries + 1] = function() pm.setPartsTreeConfig(conf.partsTree, true) end end
  if type(conf.parts) == "table" and next(conf.parts) and pm.setPartsConfig then tries[#tries + 1] = function() pm.setPartsConfig(conf.parts, true) end end
  local lastErr = "no way to set a config on this version"
  for _, f in ipairs(tries) do
    local ok, e = pcall(f)
    if ok then return true end
    lastErr = e
  end
  return false, lastErr
end

onRevertParts = function()
  local snap = lastGoodSnap
  local ok, err = false, "nothing to go back to"
  if getCar() and snap and snap.conf then ok, err = applyConfigTable(snap.conf) end
  if ok then cfgSnap = snap end   -- the rebuild that follows isn't a new change
  if TriggerServerEvent then TriggerServerEvent("tg_revert_report", jsonEncode({ ok = ok, err = (not ok) and sanitize(err) or nil })) end
end

onFindGas = function()
  local st, method, err = findGasStations()
  if TriggerServerEvent then
    TriggerServerEvent("tg_gas_reply", jsonEncode({ stations = st, method = method, err = err and sanitize(err) or nil }))
  end
end

local function checkRebuild()
  local car = getCar()
  if not car then return end
  local new = takeSnapshot(car)
  if not new then return end
  local old = cfgSnap
  cfgSnap = new
  if faults.ownRebuild then   -- the mod changed the car itself (a fault, a fix, restored upgrades): the new normal
    faults.ownRebuild = nil
    lastGoodSnap = new
    return
  end
  lastGoodSnap = old   -- what to go back to if the server refuses the bill
  if not old or old.carId ~= new.carId then return end
  local billable, cosmetic, delta, unknown, seen, changes = 0, 0, 0, 0, {}, {}
  for _, t in ipairs({ old.parts, new.parts }) do
    for slot in pairs(t) do
      if not seen[slot] then
        seen[slot] = true
        local a, b = old.parts[slot], new.parts[slot]
        if a == "" then a = nil end
        if b == "" then b = nil end
        if a ~= b then
          if isFreeSlot(slot) then cosmetic = cosmetic + 1
          else
            billable = billable + 1
            local va = (a == nil) and 0 or old.values[slot]
            local vb = (b == nil) and 0 or new.values[slot]
            if type(va) ~= "number" or type(vb) ~= "number" then unknown = unknown + 1
            else delta = delta + (vb - va) end
            if #changes < 40 then   -- which slots changed (a replaced part takes its problems with it)
              changes[#changes + 1] = { slot = slot, from = a, to = b, from_value = type(va) == "number" and va or nil }
            end
          end
        end
      end
    end
  end
  local varsChanged = false
  for k, v in pairs(new.vars) do if old.vars[k] ~= v then varsChanged = true end end
  for k, v in pairs(old.vars) do if new.vars[k] ~= v then varsChanged = true end end
  if (billable + cosmetic > 0 or varsChanged) and TriggerServerEvent then
    TriggerServerEvent("tg_rebuild", jsonEncode({ billable = billable, cosmetic = cosmetic, vars = varsChanged,
      valueDelta = delta, unknown = unknown, changes = changes }))
  end
end

-- client -> server -------------------------------------------------------------
local function report()
  if not TriggerServerEvent or state.phase == "idle" then return end
  local v = getCar()
  if not v then return end
  if state.allowParts then partsValue = nil end  -- parts can change during the workshop
  if partsValue == nil then partsValue = getPartsValue(v) or false end
  pcall(function() v:queueLuaCommand(FUEL_VLUA) end)   -- answer arrives before the next report
  if (not cfgSnap or cfgSnap.carId ~= v:getID()) and not rebuildCheckIn then
    cfgSnap = takeSnapshot(v)
    faults.ownRebuild = nil   -- this snapshot already includes any change the mod made
  end
  measureCargo()   -- answer arrives before the next report
  TriggerServerEvent("tg_report", jsonEncode({ damage = getDamage(v), partsValue = partsValue or nil, fuel = fuelValue,
    energy = energyValue, cargo = cargoValue }))
end

-- hooks ------------------------------------------------------------------------
function M.onExtensionLoaded()
  log("I", "topgear", "extension " .. VERSION .. " loaded")
  pcall(extensions.load, "core_groundMarkers")
  tryRegister(0)
end

function M.onUpdate(dtReal)
  tryRegister(dtReal)
  stateAge = stateAge + dtReal
  reportTimer = reportTimer + dtReal
  if reportTimer >= 2 then reportTimer = 0; report() end
  reassertPath(dtReal)
  updateWindow(dtReal)
  local okS, errS = pcall(selUpdate, dtReal)
  if not okS and not selector.errored then selector.errored = true; warn("vehicle selector: " .. tostring(errS)) end
  local okL, errL = pcall(drawLights, dtReal)
  if not okL and not lights.errored then lights.errored = true; warn("starting lights: " .. tostring(errL)) end
  local okF, errF = pcall(drawFlag, dtReal)
  if not okF and not flag.errored then flag.errored = true; warn("finish flag: " .. tostring(errF)) end
  updateFaults(dtReal)
  updateMove(dtReal)
  updateTrailer(dtReal)
  Rpc.update(dtReal)
  if rebuildCheckIn then
    rebuildCheckIn = rebuildCheckIn - dtReal
    if rebuildCheckIn <= 0 then rebuildCheckIn = nil; pcall(checkRebuild) end
  end
  hudTimer = hudTimer - dtReal
  if hudTimer <= 0 then hudTimer = 1; hud() end
end

function M.onPreRender() drawTarget() end
function M.onVehicleSpawned(vid)
  partsValue = nil; pathCarId = nil
  shop.cat, shop.tried = nil, nil
  local mine = getCar()
  if mine and mine:getID() == vid and cfgSnap and cfgSnap.carId == vid then rebuildCheckIn = 1.0 end
  if move and move.stage == "config" then move.spawned = true end
  local car = getCar()
  if not faults.active or not car or car:getID() ~= vid then return end
  if faults.waitSpawn then
    faults.waitSpawn = nil
    runPhysicsFaults(false)
  elseif not faults.applyAt then
    faults.applyAt = 0.5   -- someone changed the setup (e.g. tuning menu): put the faults back
  end
end

function M.onVehicleResetted(vid)
  local car = getCar()
  if faults.active and car and car:getID() == vid then runPhysicsFaults(true) end
end
function M.onVehicleSwitched() pathCarId = nil end

function M.onExtensionUnloaded()
  selUnhook()   -- give the game its own vehicle list back
  state = { phase = "idle" }
  applyFilters()
  trySetPath(nil)
end

return M
