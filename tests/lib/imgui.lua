-- Fake ui_imgui: records what each frame draws, lets a test click buttons by label, and checks
-- that every push/begin is matched in the same frame (rule 8 in CLAUDE.md).
--
--   im.click("Ready")             next frame, the button whose visible label is "Ready" returns true
--   im.setText("##coursename", s) fill an InputText
--   im.setInt("Budget##b", n)     fill an InputInt
--   im.lastFrame                  { items = {...}, windows = { [name] = { items } }, circles = {...} }
--   im.problems                   list of balance violations seen so far
local M = {}

local function visible(label) return (tostring(label):gsub("##.*$", "")) end

local function newState()
  return { colors = 0, vars = 0, windows = 0, tabbars = 0, tables = 0, combos = 0, children = 0 }
end

function M.new()
  local im = {}
  local clicks, texts, ints = {}, {}, {}
  local frame, cur, st
  im.problems = {}
  im.lastFrame = nil
  im.frames = 0

  local function problem(msg) im.problems[#im.problems + 1] = msg end
  local function record(item)
    if not frame then return end
    frame.items[#frame.items + 1] = item
    if cur then cur[#cur + 1] = item end
  end

  -- test API ------------------------------------------------------------------
  function im.click(label) clicks[#clicks + 1] = label end
  function im.setText(label, s) texts[label] = s end
  function im.setInt(label, n) ints[label] = n end
  function im.beginFrame()
    frame = { items = {}, windows = {}, circles = {}, rects = {} }
    st = newState()
    cur = nil
  end
  function im.endFrame()
    if not frame then return end
    for k, v in pairs(st) do
      if v ~= 0 then problem(string.format("frame %d: %s unbalanced (%+d)", im.frames + 1, k, v)) end
    end
    im.frames = im.frames + 1
    im.lastFrame = frame
    frame = nil
  end
  function im.pendingClicks() return #clicks end

  local function takeClick(label)
    local v = visible(label)
    for i, c in ipairs(clicks) do
      if c == label or c == v then table.remove(clicks, i); return true end
    end
    return false
  end

  -- types -----------------------------------------------------------------------
  function im.ImVec2(x, y) return { x = x, y = y } end
  function im.ImVec4(r, g, b, a) return { x = r, y = g, z = b, w = a } end
  function im.BoolPtr(b) return { [0] = b } end
  function im.IntPtr(n) return { [0] = n } end
  function im.ArrayChar(_, s) return { value = s or "", isArrayChar = true } end

  -- windows ---------------------------------------------------------------------
  function im.Begin(name, _, _)
    st.windows = st.windows + 1
    cur = {}
    frame.windows[visible(name)] = cur
    return true
  end
  function im.End()
    st.windows = st.windows - 1; cur = nil
    if (st.fontScaled or 0) ~= 0 then problem("window ended with its font still scaled") ; st.fontScaled = 0 end
  end
  function im.SetNextWindowPos() end
  function im.SetNextWindowSize() end
  function im.SetNextWindowCollapsed() end
  function im.SetNextWindowSizeConstraints() end
  function im.GetIO() return { DisplaySize = { x = 1920, y = 1080 } } end

  function im.BeginTabBar() st.tabbars = st.tabbars + 1; return true end
  function im.EndTabBar() st.tabbars = st.tabbars - 1 end
  im.selectedTabs = {}   -- tab label -> how many frames it was forced open (TabItemFlags_SetSelected)
  function im.BeginTabItem(label, _, flags)   -- every tab drawn
    record({ kind = "tab", label = visible(label) })
    if flags then im.selectedTabs[visible(label)] = (im.selectedTabs[visible(label)] or 0) + 1 end
    return true
  end
  function im.EndTabItem() end
  function im.CollapsingHeader1(label, flags) record({ kind = "header", label = visible(label), flags = flags }); return true end

  -- widgets ---------------------------------------------------------------------
  function im.TextUnformatted(s) record({ kind = "text", text = tostring(s) }) end
  function im.Text(fmt, ...) record({ kind = "text", text = string.format(fmt, ...) }) end
  function im.TextColored(col, fmt, ...) record({ kind = "text", text = string.format(fmt, ...), color = col }) end
  function im.Button(label, size)
    record({ kind = "button", label = visible(label), id = label, size = size })
    return takeClick(label)
  end
  function im.Selectable1(label, selected)
    record({ kind = "selectable", label = visible(label), selected = selected })
    return takeClick(label)
  end
  function im.InputText(label, buf)
    if texts[label] then buf.value = texts[label]; texts[label] = nil end
    record({ kind = "input", label = visible(label), value = buf.value })
    return false
  end
  function im.SliderInt(label, ptr, lo, hi, fmt)   -- (setInt(label, n) drags it; shows its text like "<Beater>")
    local changed = false
    if ints[label] then ptr[0] = math.max(lo, math.min(hi, ints[label])); ints[label] = nil; changed = true end
    record({ kind = "slider", label = visible(label), value = ptr[0], min = lo, max = hi, text = "<" .. tostring(fmt) .. ">" })
    return changed
  end
  function im.InputInt(label, ptr)   -- (like ImGui: true when the value changed this frame)
    local changed = false
    if ints[label] then changed = ptr[0] ~= ints[label]; ptr[0] = ints[label]; ints[label] = nil end
    record({ kind = "inputint", label = visible(label), value = ptr[0] })
    return changed
  end
  function im.SameLine() record({ kind = "sameline" }) end   -- (for tools/preview.lua: items side by side)
  function im.Separator() end
  function im.Dummy() end

  function im.BeginCombo(id, preview) st.combos = st.combos + 1; record({ kind = "combo", label = visible(id), preview = preview }); return true end
  function im.EndCombo() st.combos = st.combos - 1 end

  function im.BeginTable(id) st.tables = st.tables + 1; record({ kind = "table", label = visible(id) }); return true end
  function im.EndTable() st.tables = st.tables - 1; record({ kind = "endtable" }) end
  function im.TableSetupColumn(name) record({ kind = "column", text = name }) end
  function im.TableHeadersRow() end
  function im.TableNextRow() end
  function im.TableNextColumn() end

  function im.BeginChild1(id, size, border)   -- (like BeamNG's binding; returns visible, EndChild is always due)
    st.children = st.children + 1
    record({ kind = "child", label = visible(id), size = size, border = border })
    return true
  end
  function im.EndChild() st.children = st.children - 1 end
  function im.GetTextLineHeightWithSpacing() return 17 end

  -- style -----------------------------------------------------------------------
  function im.PushStyleColor2() st.colors = st.colors + 1 end
  function im.PopStyleColor(n) st.colors = st.colors - (n or 1) end
  function im.PushStyleVar1() st.vars = st.vars + 1 end
  function im.PopStyleVar(n) st.vars = st.vars - (n or 1) end

  -- drawing ---------------------------------------------------------------------
  function im.GetWindowDrawList() return {} end
  function im.GetCursorScreenPos() return { x = 0, y = 0 } end
  function im.GetColorU322(c) return c end
  function im.ImDrawList_AddCircleFilled(_, center, r, col)
    frame.circles[#frame.circles + 1] = { x = center.x, y = center.y, r = r, color = col }
  end
  function im.ImDrawList_AddRectFilled(_, a, b, col)
    frame.rects[#frame.rects + 1] = { x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y, color = col }
  end
  function im.ImDrawList_AddRect(_, a, b, col, rounding)   -- an outline (the boxes round each section)
    frame.rects[#frame.rects + 1] = { x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y, color = col, outline = true, rounding = rounding }
  end
  function im.GetContentRegionAvail() return { x = 520, y = 400 } end
  im.TreeNodeFlags_DefaultOpen = 32   -- (its real value; the generated constants below wrap to 0 after 30)
  function im.Indent() end
  function im.Unindent() end
  -- hover help: the fake is always "hovered", so a tooltip's text is recorded like a line of text (tests find it)
  function im.IsItemHovered() return true end
  function im.SetTooltip(fmt, ...) record({ kind = "tooltip", text = string.format(fmt, ...) }) end
  function im.SetWindowFontScale(scale)
    st.fontScaled = (scale ~= 1) and 1 or 0
    record({ kind = "fontscale", scale = scale })
  end

  -- enum constants (Col_*, StyleVar_*, TableFlags_*, WindowFlags_*, Cond_*, TabItemFlags_*)
  local nextConst = 1
  setmetatable(im, { __index = function(t, k)
    if type(k) == "string" and (k:find("^Col_") or k:find("^StyleVar_") or k:find("^TableFlags_") or
        k:find("^WindowFlags_") or k:find("^Cond_") or k:find("^TabItemFlags_") or k:find("^TreeNodeFlags_")) then
      nextConst = nextConst * 2 % 1073741824
      rawset(t, k, nextConst)
      return nextConst
    end
    return nil   -- like a real build without that function
  end })

  -- query helpers -----------------------------------------------------------------
  function im.items(window)
    local f = im.lastFrame
    if not f then return {} end
    if window then return f.windows[window] or {} end
    return f.items
  end
  function im.textOf(window)
    local out = {}
    for _, it in ipairs(im.items(window)) do
      if it.text then out[#out + 1] = it.text elseif it.label then out[#out + 1] = "[" .. it.label .. "]" end
    end
    return table.concat(out, "\n")
  end
  function im.buttons(window)
    local out = {}
    for _, it in ipairs(im.items(window)) do if it.kind == "button" then out[#out + 1] = it.label end end
    return out
  end
  function im.hasButton(label, window)
    for _, b in ipairs(im.buttons(window)) do if b == label then return true end end
    return false
  end

  return im
end

return M
