-- Problem tiers (0.9.21, Ryan): tier 1 annoying, 2 hurts performance, 3 can stop the car; Used draws tier 1 only,
-- Needs work up to 2, Beater / Death Trap up to 3 with one tier 3 at most; never two problems sharing a group.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local TIER = { tires = 1, alignment = 1, suspension = 1, body = 1, abs = 1,
               engine = 2, turbo = 2, brakes = 2, brakefade = 2, synchros = 2, fuelleak = 2, clutch = 2, idle = 2, gearbox = 2,
               ignition = 3, cooling = 3, oilleak = 3 }
local GROUPS = { brakes = { "brakes" }, brakefade = { "brakes" }, abs = { "brakes" },
                 ignition = { "stalling" }, fuelleak = { "stalling" }, idle = { "stalling" }, oilleak = { "stalling", "heat" },
                 cooling = { "heat" }, synchros = { "gears" }, clutch = { "gears" }, gearbox = { "gears" } }

local function realTiers()   -- the real fault settings (the fixtures switch the tier rules off for older tests)
  local cfg = F.twoRaces(); cfg.faults = nil
  return cfg
end
-- the problem sets /tg fault sample drew: { { ids }, ... }
local function samples(w, A, cond, n)
  local from = #A.chat
  w:chat(A, "/tg fault sample " .. cond .. " " .. n)
  local out = {}
  for i = from + 1, #A.chat do
    local list = A.chat[i]:match("^%[TG%] [%a ]+ %d+: (.*)$")
    if list then
      local ids = {}
      for id in list:gmatch("(%a+) %(T%d%)") do ids[#ids + 1] = id end
      out[#out + 1] = ids
    end
  end
  return out
end

t.test("the tier rules: Used tier 1 only, Needs work up to 2, a Beater / Death Trap one tier 3 at most, no shared groups", function()
  local w = World.new({ files = F.files(realTiers()) })
  local A = w:join("Alice")
  local worst, seen = {}, {}
  for cond, name in ipairs({ "used", "needs work", "beater", "death trap" }) do
    local sets = samples(w, A, name, 50)
    t.eq(#sets, 50, name .. ": 50 cars")
    for _, ids in ipairs(sets) do
      t.eq(#ids, cond, name .. ": " .. cond .. " problem(s)")
      local tier3, groups = 0, {}
      for _, id in ipairs(ids) do
        local tier = TIER[id]
        t.ok(tier, "a known problem: " .. id)
        worst[cond] = math.max(worst[cond] or 0, tier)
        seen[id] = true
        if tier == 3 then tier3 = tier3 + 1 end
        for _, g in ipairs(GROUPS[id] or {}) do
          t.ok(not groups[g], name .. ": two problems from the " .. g .. " group: " .. table.concat(ids, ", "))
          groups[g] = true
        end
      end
      t.ok(tier3 <= 1, name .. ": at most one tier 3")
    end
  end
  t.eq(worst[1], 1, "Used: tier 1 only")
  t.eq(worst[2], 2, "Needs work: up to tier 2")
  t.eq(worst[4], 3, "Death Trap: tier 3 turns up")
  t.ok(seen.cooling, "cooling problems are tier 3 (Ryan)")
  t.ok(not (seen.clutch or seen.idle or seen.gearbox), "the ones switched off stay out")
  w:assertClean()
end)

t.test("a saved fault list (no tiers) gets the tiers and groups once; tiers = false switches the rules off", function()
  local w0 = World.new()
  local list = w0:serverConfig().faults.list
  for _, f in ipairs(list) do f.tier, f.groups = nil, nil end   -- (as a 0.9.20 server saved it)
  local cfg = F.twoRaces(); cfg.faults = { list = list }
  local w = World.new({ files = F.files(cfg) })
  local byId = {}
  for _, f in ipairs(w:serverConfig().faults.list) do byId[f.id] = f end
  t.eq(byId.cooling.tier, 3); t.eq(byId.tires.tier, 1); t.eq(byId.brakes.tier, 2)
  t.eq(byId.oilleak.groups[1], "stalling"); t.eq(byId.oilleak.groups[2], "heat")
  -- switched off: anything goes (a Used car can draw a tier 3)
  local cfg2 = F.twoRaces(); cfg2.faults = { tiers = false }
  local w2 = World.new({ files = F.files(cfg2) })
  local A = w2:join("Alice")
  local tier3 = false
  for _, ids in ipairs(samples(w2, A, "used", 50)) do if TIER[ids[1]] == 3 then tier3 = true end end
  t.ok(tier3, "with tiers off, a Used car can get a tier 3 problem")
  w:assertClean(); w2:assertClean()
end)

t.test("a bought Death Trap follows the rules too (the real draw, not just the sample)", function()
  local base = realTiers(); base.workshopEvery = 1
  for _ = 1, 8 do
    local w = World.new({ files = F.files(base) })
    local A, B = w:join("Alice"), w:join("Bob")
    w:chat(A, "/tg start"); w:chat(A, "/tg condition death trap")
    w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
    w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
    w:driveAll({ { A, p(500), 40 }, { B, p(500), 30 } }); w:chat(A, "/tg go")
    w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
    w:driveAll({ { A, p(900), 40 }, { B, p(900), 30 } })
    w:waitFor(function() return w:state(A).phase == "workshop" end, 10, "the workshop")
    w:step(2.5)
    local mine = (w:ui(A).faults or {}).mine or {}
    t.eq(#mine, 4, "four problems")
    local tier3, groups = 0, {}
    for _, f in ipairs(mine) do
      if TIER[f.id] == 3 then tier3 = tier3 + 1 end
      for _, g in ipairs(GROUPS[f.id] or {}) do t.ok(not groups[g], "no shared group: " .. g); groups[g] = true end
    end
    t.ok(tier3 <= 1, "at most one tier 3")
  end
end)
