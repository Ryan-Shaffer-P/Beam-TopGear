-- The finish flag: a movable window that appears when your run is complete.
local t = require("t")
local World = require("world")
local F = require("fixtures")
local p = F.p

local function oneRace()
  return F.config({
    { name = "Race One", type = "race", timeLimit = 300, start = p(500), checkpoints = { p(700), p(900) }, via = {} },
  }, { finale = { name = "The Test Track", pos = p(1500), radius = 25, timeLimit = 1200, via = {} } })
end

local function flagWin(pl) return pl.client.im.lastFrame.windows["Finish"] end
local function flagText(pl) return pl.client.im.textOf("Finish") end

local function toTheStart(w, players)
  local models = { "covet", "pessima", "miramar" }
  for i, pl in ipairs(players) do w:buy(pl, models[i], "base_M") end
  for _, pl in ipairs(players) do w:chat(pl, "/tg ready") end
  local legs = {}
  for _, pl in ipairs(players) do legs[#legs + 1] = { pl, p(500), 40 } end
  w:driveAll(legs)
  w:chat(players[1], "/tg go")
  w:waitFor(function() return w:state(players[1]).phase == "event" end, 10, "GO")
end

t.test("finish flag shows for each driver as they finish, never for a DNF, and hides itself", function()
  local w = World.new({ files = F.files(oneRace()) })
  local A, B, C = w:join("Alice"), w:join("Bob"), w:join("Carol")
  w:chat(A, "/tg start")
  toTheStart(w, { A, B, C })
  t.eq(flagWin(A), nil, "no flag during the countdown or the run")

  w:drive(A, p(900), 40)
  t.ok(flagWin(A), "Alice finished: her flag is up")
  t.match(flagText(A), "FINISH")
  t.match(flagText(A), "Race One")
  t.match(flagText(A), "Time 0:%d%d%.%d%d")
  t.eq(#A.client.im.lastFrame.rects, 48, "a 12 x 4 checkered flag")
  t.eq(flagWin(B), nil, "Bob is still driving: no flag for him")

  w:step(7)
  t.eq(flagWin(A), nil, "the flag hides itself after 6 s")

  w:drive(B, p(900), 30)
  t.ok(flagWin(B), "Bob's flag when he finishes")
  w:chat(A, "/tg next")   -- the producers call time on Carol
  w:step(10)
  t.ok(w:chatHas(A, "Carol - DNF"), "Carol didn't finish")
  t.eq(flagWin(C), nil, "no flag for a DNF")
  w:assertClean()
end)

t.test("finish flag at the finale shows the drivability score", function()
  local w = World.new({ files = F.files(oneRace()) })
  local A = w:join("Alice")
  w:chat(A, "/tg start")
  toTheStart(w, { A })
  w:drive(A, p(900), 40)
  w:waitFor(function() return w:state(A).phase == "finale" end, 10, "the finale")
  w:step(7)
  w:drive(A, p(1500), 40)
  t.match(flagText(A), "The Test Track")
  t.match(flagText(A), "Drivability 10%.0/10")
  w:assertClean()
end)

t.test("/tg flag pins the box for positioning, /tg flagtest shows a sample, Status tab has the buttons", function()
  local w = World.new()
  local A = w:join("Alice")
  w:chat(A, "/tg flag")
  w:step(0.5)
  t.match(flagText(A), "Drag this box by its title bar")
  w:chat(A, "/tg flag")
  w:step(0.5)
  t.eq(flagWin(A), nil, "hidden again")

  w:chat(A, "/tg flagtest")
  w:step(0.5)
  t.match(flagText(A), "Your time shows here")
  w:step(7)
  t.eq(flagWin(A), nil, "the sample hides itself")

  w:chat(A, "/tg start force")
  w:step(2.5)
  t.ok(A.client.im.hasButton("Position the finish flag"), "Status tab button")
  A.client.im.click("Position the finish flag##flagpin")
  w:step(1)
  t.ok(flagWin(A), "the button pins the box")
  w:assertClean()
end)

t.test("finish flag falls back to text on builds without draw lists or font scaling", function()
  local w = World.new()
  local A = w:join("Alice")
  rawset(A.client.im, "ImDrawList_AddRectFilled", nil)
  rawset(A.client.im, "SetWindowFontScale", nil)
  w:chat(A, "/tg flagtest")
  w:step(0.5)
  t.match(flagText(A), "%[#%] %[ %]")
  t.match(flagText(A), "FINISH")
  w:assertClean()
end)
