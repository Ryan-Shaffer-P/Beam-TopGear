-- Parts tab (0.8.7): a priced list of every part that fits the car, Fit buttons in workshops,
-- and looks-only parts free. Fake catalogue: tests/lib/world.lua partCatalogue (Covet: engine $2,000 ->
-- turbo $3,200, coilovers $400 -> $1,800, spoiler none -> $300, lip none -> $150, seat $100 -> $600,
-- hood $250 -> $900, an "odd" part with no game price). Labour $300 once; refunds are half the difference.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local WIN = "Top Gear Challenge"
local function buyCovet(w, A, format)
  if format then A.client.partsFormat = format end
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M")
  w:step(2.5)   -- the window refreshes; the client snapshots the car's parts
end
local function fit(w, A, key, part)
  A.client.im.click("Fit##fit_" .. key .. "_" .. part)
  w:step(3)     -- the car rebuilds, the client reports what changed, the server bills it
end
local function text(A) return A.client.im.textOf(WIN) end

local function lists(A)
  local s = text(A)
  t.match(s, "PERFORMANCE PARTS")
  t.match(s, "LOOKS %- FREE")
  t.match(s, "1%.5L I4 Turbo   %+%$1,200")
  t.match(s, "Sport coilovers   %+%$1,400")
  t.match(s, "Fiberglass hood   %+%$650", "hoods are billed")
  t.match(s, "Rear spoiler   %+%$300", "spoilers are billed")
  t.match(s, "Odd part plus   %+%$500 %(no game price%)")
  t.match(s, "Front lip   free", "a lip is looks-only")
  t.match(s, "Race seat   free", "interior is free")
  t.match(s, "%(fitted%)  1%.5L I4\n")
end

t.test("parts tab: every part that fits, with what fitting it costs (flat parts format)", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  buyCovet(w, A)
  lists(A)
  t.ok(A.client.im.hasButton("Fit"), "Fit buttons at the dealership")
  w:assertClean()
end)

t.test("parts tab: Fit charges exactly the price shown; looks are free; a cheaper part refunds half", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  buyCovet(w, A)
  t.eq(w:state(A).cash, 5500)

  fit(w, A, "/covet_engine/", "covet_engine_turbo")   -- +$1,200 and the first labour charge
  t.eq(A.current.parts["/covet_engine/"], "covet_engine_turbo", "fitted in game")
  t.ok(w:chatHas(A, "Workshop labour: -$300 (once per workshop)."))
  t.ok(w:chatHas(A, "Parts fitted: -$1,200. Cash $4,000."))
  t.eq(w:state(A).cash, 4000)
  w:step(2.5)
  t.match(text(A), "%(fitted%)  1%.5L I4 Turbo", "the list follows the car")
  t.match(text(A), "1%.5L I4   refund %$600")

  fit(w, A, "/covet_lip/", "covet_lip")               -- looks only: free
  t.eq(A.current.parts["/covet_lip/"], "covet_lip")
  t.eq(w:state(A).cash, 4000, "no charge for the lip")

  fit(w, A, "/covet_spoiler/", "covet_spoiler")       -- +$300, labour already paid
  t.eq(w:state(A).cash, 3700)

  w:step(2.5)
  fit(w, A, "/covet_engine/", "covet_engine")         -- back to stock: half the $1,200 back
  t.ok(w:chatHas(A, "Old parts sold back: +$600. Cash $4,300."))
  t.eq(w:state(A).cash, 4300)
  w:assertClean()
end)

t.test("parts tab: the newer parts-tree format lists and fits the same way", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  buyCovet(w, A, "tree")
  lists(A)
  fit(w, A, "/covet_coilover_F/", "covet_coilover_F_sport")
  t.eq(A.current.parts["/covet_coilover_F/"], "covet_coilover_F_sport")
  t.eq(w:state(A).cash, 5500 - 300 - 1400)
  w:chat(A, "/tg partsdiag")
  t.ok(w:chatHas(A, "Parts tab: 7 slots with options, 12 parts listed (10 priced), via the parts tree."))
  w:assertClean()
end)

t.test("parts box: a read-only (greyed) price list away from the dealership and workshops", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  buyCovet(w, A)
  w:chat(A, "/tg ready")
  w:drive(A, p(300), 40)   -- driven away from the dealership (the window stays open)
  w:step(2.5)
  t.match(text(A), "Price list %- parts can be fitted at the dealership or in a workshop%.")
  t.match(text(A), "1%.5L I4 Turbo   %+%$1,200", "prices still shown")
  t.ok(A.client.im.hasButton("Fit"), "Fit buttons greyed out (0.9.13), not hidden")
  local cash = w:state(A).cash
  fit(w, A, "/covet_engine/", "covet_engine_turbo")
  t.eq(w:state(A).cash, cash, "and they do nothing")
  w:assertClean()
end)

t.test("parts tab: options you can't afford (with unpaid labour) are marked and can't be fitted", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  buyCovet(w, A)
  w:chat(A, "/tg setcash Alice -1000")   -- $500 of overdraft left
  w:step(2.5)
  t.match(text(A), "1%.5L I4 Turbo   %+%$1,200 %- over your limit")
  t.match(text(A), "Rear spoiler   %+%$300 %- over your limit", "$300 + $300 labour > $500")
  t.ok(A.client.im.hasButton("Fit"), "free parts can still be fitted")
  w:assertClean()
end)

t.test("parts diag reports what the Parts tab can list", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  buyCovet(w, A)
  w:chat(A, "/tg partsdiag")
  t.ok(w:chatHas(A, "Parts tab: 7 slots with options, 12 parts listed (10 priced), via the slot map."))
  w:assertClean()
end)

t.test("parts tab: a game version without the catalogue functions shows an error, not a broken window", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  A.client.noSlotMap = true
  buyCovet(w, A)
  t.match(text(A), "Couldn't list your car's parts: couldn't list this car's parts on this BeamNG version")
  t.match(text(A), "Status", "the rest of the window still works")
  local pr = w:problems()
  t.eq(#pr, 1, "just the one warning:\n" .. table.concat(pr, "\n"))
  t.match(pr[1], "parts list:")
end)

t.test("free or billed: looks-only slots are free, wings/spoilers/hoods are billed", function()
  local w = World.new()
  local A = w:join("Alice")
  local free = A.client.M.isFreeSlot
  for _, slot in ipairs({ "/covet_lip/", "/covet_sideskirt_L/", "/covet_fender_flare_FL/", "/covet_grille/", "covet_seat_FL",
                          "/covet_interior/covet_steering/", "/covet_bumper_F/", "/covet_mirror_L/", "/covet_wing_mirror_R/",
                          "/covet_trim/", "/covet_paint_design/" }) do
    t.ok(free(slot), slot .. " should be free")
  end
  for _, slot in ipairs({ "/covet_spoiler/", "/covet_lip_spoiler/", "/covet_wing/", "/covet_body/covet_wing/", "/covet_hood/",
                          "/covet_fiberglass_hood/", "/covet_engine/", "/covet_engine/covet_intake/", "/covet_radiator/",
                          "/covet_coilover_F/", "/covet_exhaust/" }) do
    t.ok(not free(slot), slot .. " should be billed")
  end
end)

t.test("parts only in the dealership and workshop phases: on a leg the Parts box is greyed and Fit does nothing", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A = w:join("Alice")
  buyCovet(w, A)
  w:chat(A, "/tg ready"); w:step(2.5)          -- leg 1, still parked at the dealership
  t.eq(w:state(A).phase, "travel")
  t.match(text(A), "Price list %- parts can be fitted at the dealership or in a workshop%.")
  t.ok(A.client.im.hasButton("Fit"), "Fit is shown, greyed")
  local cash = w:state(A).cash
  fit(w, A, "/covet_engine/", "covet_engine_turbo")
  t.eq(w:state(A).cash, cash, "nothing fitted, nothing charged")
  t.eq(A.current.parts["/covet_engine/"], "covet_engine", "the engine is unchanged")
  t.noLine(A.chat, "Workshop labour")
  w:assertClean()
end)
