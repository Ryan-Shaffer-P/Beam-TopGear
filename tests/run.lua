-- Runs every tests/test_*.lua (or only tests whose name/file contains the first argument).
-- Run from the repo root:  lua tests/run.lua [filter]     (or tests/run.sh for every Lua version)
local root = os.getenv("TG_ROOT") or "."
package.path = root .. "/tests/lib/?.lua;" .. package.path

local t = require("t")
local p = io.popen('ls "' .. root .. '"/tests/test_*.lua 2>/dev/null')
local files = {}
for f in p:lines() do files[#files + 1] = f end
p:close()
table.sort(files)
if #files == 0 then io.stderr:write("no tests found under " .. root .. "/tests\n"); os.exit(1) end

for _, f in ipairs(files) do
  t.currentFile = f:match("([^/]+)$")
  local chunk, err = loadfile(f)
  if not chunk then io.stderr:write(err .. "\n"); os.exit(1) end
  chunk()
end

os.exit(t.run(arg and arg[1]) == 0 and 0 or 1)
