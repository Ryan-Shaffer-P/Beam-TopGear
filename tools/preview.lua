-- Text preview of the Top Gear window, drawn by the real client code in the test harness (fake ImGui).
-- Shows each tab's content and controls - not colours, fonts or exact spacing.
--   luajit tools/preview.lua [scene] [tab]      (from the repo root)
--   scenes: idle (default), dealer, travel, event, workshop, results      tab: a tab name, or "all" (default)
package.path = "tests/lib/?.lua;tests/?.lua;" .. package.path
local World = require("world")
local F = require("fixtures")
local p = F.p

local scene, want = arg[1] or "idle", arg[2] or "all"
local WIN = "Top Gear Challenge"

local w = World.new({ files = F.files(F.twoRaces()) })
local A, B = w:join("Alice"), w:join("Bob")
local function to(phase) w:waitFor(function() return (w:state(A) or {}).phase == phase end, 60, phase) end

if scene ~= "idle" then
  w:chat(A, "/tg workshopevery 1")   -- (a workshop after each event)
  w:chat(A, "/tg start")
  if scene ~= "dealer" then
    w:buy(A, "covet", "base_M"); w:buy(B, "pessima", "base_M")
    w:chat(A, "/tg ready"); w:chat(B, "/tg ready")
    if scene ~= "travel" then
      w:driveAll({ { A, p(500), 40 }, { B, p(500), 35 } })
      w:chat(A, "/tg go"); to("event")
      if scene ~= "event" then
        w:driveAll({ { A, p(900), 40 }, { B, p(900), 30 } })
        to("workshop")
        if scene == "results" then
          w:chat(A, "/tg next"); to("travel")
          w:driveAll({ { A, p(1500), 40 }, { B, p(1500), 35 } }); w:chat(A, "/tg go"); to("event")
          w:driveAll({ { A, p(1900), 40 }, { B, p(1900), 30 } }); to("finale")
          w:driveAll({ { A, p(5000), 40 }, { B, p(5000), 35 } }); to("results")
        else
          w:damage(A, 1800); w:step(3)
        end
      else
        w:step(6)
      end
    end
  end
end
w:step(3)
if #A.client.im.items(WIN) == 0 then w:chat(A, "/tg menu"); w:step(3) end   -- (open it unless it opened itself)

-- render -------------------------------------------------------------------------------------
local ESC = string.char(27)
local function c(code, s) return ESC .. "[" .. code .. "m" .. s .. ESC .. "[0m" end
local function show(it)
  local k = it.kind
  if k == "text" then
    if it.color then return c("33", it.text) end
    return it.text
  elseif k == "button" then return c("1;36", "[ " .. it.label .. " ]")
  elseif k == "selectable" then return (it.selected and c("1;32", "(*) ") or "( ) ") .. it.label
  elseif k == "input" then return it.label .. ": " .. c("4", (it.value ~= "" and it.value or "          "))
  elseif k == "inputint" then return it.label .. ": " .. c("4", " " .. tostring(it.value) .. " ") .. " -/+"
  elseif k == "slider" then return it.label .. ": " .. tostring(it.text) .. "  " .. it.min .. " |" .. string.rep("-", it.value - it.min) .. "o" .. string.rep("-", it.max - it.value) .. "| " .. it.max
  elseif k == "combo" then return (it.label ~= "" and (it.label .. ": ") or "") .. c("4", "[" .. tostring(it.preview) .. " v]")
  elseif k == "header" then return "\n" .. c("1;35", "v " .. it.label)
  elseif k == "table" then return c("2", "-- table --")
  elseif k == "column" then return c("1", it.text)
  elseif k == "child" then return c("2", "[ box: " .. it.label .. " ]")
  end
  return nil
end

local items = A.client.im.items(WIN)
local tabs = {}
for _, it in ipairs(items) do if it.kind == "tab" then tabs[#tabs + 1] = it.label end end
print(c("1;44", "  " .. WIN .. "  ") .. c("2", "   scene: " .. scene .. "   (phase " .. tostring((w:state(A) or {}).phase or "idle") .. ", seen by Alice, an admin)"))
print("tabs: " .. table.concat(tabs, " | "))

local cur, line, joined = nil, {}, false
local function flush() if #line > 0 then print("  " .. table.concat(line, "  ")) end; line = {} end
local tbl   -- { cols = { names }, cells = { texts } } while inside a table
local function flushTable()
  if not tbl then return end
  local n = math.max(1, #tbl.cols)
  local rows = { tbl.cols }
  for i = 1, #tbl.cells, n do
    local r = {}
    for j = 0, n - 1 do r[#r + 1] = tbl.cells[i + j] or "" end
    rows[#rows + 1] = r
  end
  local width = {}
  for _, r in ipairs(rows) do for j, v in ipairs(r) do width[j] = math.max(width[j] or 0, #v) end end
  for ri, r in ipairs(rows) do
    local out = {}
    for j, v in ipairs(r) do out[j] = v .. string.rep(" ", width[j] - #v) end
    print("  | " .. table.concat(out, " | ") .. " |")
    if ri == 1 then
      local sep = {}
      for j = 1, #r do sep[j] = string.rep("-", width[j]) end
      print("  |-" .. table.concat(sep, "-|-") .. "-|")
    end
  end
  tbl = nil
end
for _, it in ipairs(items) do
  if it.kind == "endtable" then flushTable(); goto continue end
  if tbl and it.kind == "column" then tbl.cols[#tbl.cols + 1] = it.text; goto continue end
  if tbl and it.kind == "text" and #tbl.cols > 0 then tbl.cells[#tbl.cells + 1] = it.text; goto continue end
  if tbl and it.kind ~= "sameline" then flushTable() end
  if it.kind == "table" and (want == "all" or (cur and want:lower() == cur:lower())) then flush(); tbl = { cols = {}, cells = {} }; goto continue end
  if it.kind == "tab" then
    flush(); cur = it.label
    if want == "all" or want:lower() == cur:lower() then print("\n" .. c("1;7", " " .. cur .. " ") .. "\n" .. string.rep("=", 60)) end
  elseif want == "all" or (cur and want:lower() == cur:lower()) then
    if it.kind == "sameline" then joined = true
    else
      local s = show(it)
      if s then
        if not joined then flush() end
        line[#line + 1] = s
        joined = false
      end
    end
  end
  ::continue::
end
flushTable()
flush()
