-- Admin controls (Status tab): give / set a player's cash and award points, picking the player by button or typed name.
local t = require("t")
local World = require("world")
local F = require("fixtures")

local WIN = "Top Gear Challenge"
local function standing(w, viewer, name)
  for _, s in ipairs(w:ui(viewer).standings or {}) do if s.name == name then return s end end
end
local function hasText(p, s) return p.client.im.textOf(WIN):find(s, 1, true) ~= nil end

t.test("admin controls: pick a player, give and set cash, award and dock points", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob Smith")   -- Alice is the admin
  w:chat(A, "/tg menu"); w:step(2.5)   -- (in idle the window only opens when asked)
  t.ok(hasText(A, "Players appear here once a challenge is running."), "idle: nobody to pick")
  w:chat(A, "/tg start")
  w:step(2.5)
  t.ok(hasText(A, "Pick a player above or type a name."))
  t.ok(not hasText(B, "Player cash & points"), "not for non-admins")
  local cash0 = w:state(B).cash

  A.client.im.click("Bob Smith##pl_Bob Smith"); w:step(0.5)
  A.client.im.setInt("Cash##admcash", 750)
  A.client.im.click("Give##admgive"); w:step(2.5)
  t.eq(w:state(B).cash, cash0 + 750)
  t.ok(w:chatHas(B, "The producers give Bob Smith $750."))
  t.ok(hasText(A, "> Bob Smith"), "the picked player is marked")

  A.client.im.setInt("Cash##admcash", 2000)
  A.client.im.click("Set##admset"); w:step(2.5)
  t.eq(w:state(B).cash, 2000)

  A.client.im.setInt("Points##admpts", 3)
  A.client.im.setText("Reason (optional)##admreason", "best wreck")
  A.client.im.click("Award##admaward"); w:step(2.5)
  t.eq(standing(w, A, "Bob Smith").points, 3)
  t.ok(w:chatHas(B, "The producers award Bob Smith 3 pts: best wreck."))

  -- a typed name wins over the picked button, ignoring case; a negative number takes away
  A.client.im.setText("Or type a name##admplayer", "alice")
  A.client.im.setInt("Points##admpts", -1)
  A.client.im.setText("Reason (optional)##admreason", "")
  A.client.im.click("Award##admaward"); w:step(2.5)
  t.eq(standing(w, A, "Alice").points, -1)
  t.eq(standing(w, A, "Bob Smith").points, 3, "Bob untouched")
  t.ok(w:chatHas(A, "The producers dock Alice 1 pt."))
  w:assertClean()
end)

t.test("chat commands take a typed name loosely: any case, or the start of one name", function()
  local w = World.new({ files = F.files(F.twoRaces()) })
  local A, B = w:join("Alice"), w:join("Bob Smith")
  w:chat(A, "/tg start")
  w:step(2.5)
  w:chat(A, "/tg setcash bob 1234"); w:step(1)
  t.eq(w:state(B).cash, 1234)
  w:chat(A, "/tg give BOB SMITH -234"); w:step(1)
  t.eq(w:state(B).cash, 1000)
  w:chat(A, "/tg give nobody 50")
  t.ok(w:chatHas(A, "Usage: /tg give <player name> <amount>"))
  w:assertClean()
end)
