-- Economy run (0.9.2): least ENERGY used wins (fuel tanks + batteries), so petrol and electric cars compare fairly.
-- Test world: a tank holds ~34.2 MJ per litre; the Miramar is electric (60 kWh) and uses ~1/3 of the energy.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function econ()
  return F.config({ { name = "Economy Run", type = "economy", timeLimit = 300, start = p(500), checkpoints = { p(700), p(900) }, via = {} } })
end
local function resultLine(pl, who)
  for _, l in ipairs(pl.chat) do if l:find("  " .. who .. " - ", 1, true) and l:find("pts)", 1, true) then return l end end
  error("no result line for " .. who)
end

t.test("economy run: petrol and electric cars ranked by energy used, shown in litres or kWh", function()
  local w = World.new({ files = F.files(econ()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M"); w:buy(C, "miramar", "base_M")   -- Carol's is electric
  for _, pl in ipairs({ A, B, C }) do w:chat(pl, "/tg ready") end
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 38 }, { C, p(500), 36 } })
  w:step(5)                                   -- fresh readings before the start
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:driveAll({ { A, p(900), 20 }, { B, p(900), 40 }, { C, p(900), 40 } })
  w:waitFor(function() return w:state(A).phase ~= "event" end, 15, "results")
  -- Alice: petrol, gentle ~11.6 MJ; Carol: electric, hard ~13.3 MJ; Bob: petrol, hard ~44.5 MJ
  -- (each a little under the estimate: the finish counts within the checkpoint radius)
  t.match(resultLine(A, "Alice"), "%] 1st  Alice %- 0%.%d%d L %(1%d%.%d MJ%)")
  t.match(resultLine(A, "Carol"), "%] 2nd  Carol %- %d%.%d%d kWh %(1%d%.%d MJ%)", "the electric car gets a reading - and isn't last")
  t.match(resultLine(A, "Bob"), "%] 3rd  Bob %- 1%.%d%d L %(%d%d%.%d MJ%)")
  t.noLine(A.chat, "no fuel or energy reading")
  w:assertClean()
end)

t.test("economy run: a car with no reading at all still finishes, last, with the reason shown", function()
  local w = World.new({ files = F.files(econ()) })
  local A, B = w:join("Alice"), w:join("Bob")
  w:chat(A, "/tg start")
  w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
  B.current.vlua.set("energyStorage", nil)    -- this car's game reports nothing
  for _, pl in ipairs({ A, B }) do w:chat(pl, "/tg ready") end
  w:driveAll({ { A, p(500), 40 }, { B, p(500), 38 } }); w:step(5)
  w:chat(A, "/tg go")
  w:waitFor(function() return w:state(A).phase == "event" end, 10, "GO")
  w:driveAll({ { A, p(900), 40 }, { B, p(900), 20 } })
  w:waitFor(function() return w:state(A).phase ~= "event" end, 15, "results")
  t.match(resultLine(A, "Bob"), "%] 2nd  Bob %- 0:%d%d%.%d%d %(no fuel or energy reading%)")
  w:assertClean()
end)
