-- Tiny test runner.  In a test file:
--   local t = require("t")
--   t.test("dealership sells a car", function() ... t.eq(a, b) ... end)
local t = { tests = {} }

function t.test(name, fn) t.tests[#t.tests + 1] = { name = name, fn = fn, file = t.currentFile } end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function t.eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", show(expected), show(actual)), 2)
  end
end
function t.ok(v, msg) if not v then error(msg or "expected a true value", 2) end return v end
function t.match(s, pattern, msg)
  if type(s) ~= "string" or not s:find(pattern) then
    error(string.format("%sexpected %s to match %q", msg and (msg .. ": ") or "", show(s), pattern), 2)
  end
end
-- does any line in a list contain `needle` (plain text)?
function t.anyLine(lines, needle, msg)
  for _, l in ipairs(lines) do if tostring(l):find(needle, 1, true) then return l end end
  error(string.format("%sno line contains %q. Lines:\n    %s", msg and (msg .. ": ") or "", needle,
    table.concat(lines, "\n    ")), 2)
end
function t.noLine(lines, needle, msg)
  for _, l in ipairs(lines) do
    if tostring(l):find(needle, 1, true) then error(string.format("%sunexpected line: %s", msg and (msg .. ": ") or "", l), 2) end
  end
end

function t.run(filter)
  local passed, failed = 0, {}
  for _, tc in ipairs(t.tests) do
    if not filter or tc.name:find(filter, 1, true) or (tc.file or ""):find(filter, 1, true) then
      local ok, err = xpcall(tc.fn, debug.traceback)
      if ok then
        passed = passed + 1
        io.write("  ok    ", tc.name, "\n")
      else
        failed[#failed + 1] = tc
        io.write("  FAIL  ", tc.name, "\n        ", (tostring(err):gsub("\n", "\n        ")), "\n")
      end
    end
  end
  io.write(string.format("\n%d passed, %d failed  (%s)\n", passed, #failed, _VERSION .. (jit and (" / " .. jit.version) or "")))
  return #failed
end

return t
