-- Strict sandboxes: each mod file runs in its own global environment (the server and every
-- player's game are separate Lua states in reality).
--
-- Reading a global that isn't declared raises an error. That is how a function used above its
-- `local` definition shows up (it compiles to a global read and is nil in the real game).
-- Names the real game provides but that may be nil (feature probes like `spawn` or
-- `freeroam_bigMapMode`) are declared with a nil value via sb.declare().
local sandbox = {}

local STD = {
  "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawlen", "rawset",
  "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "xpcall", "unpack",
  "string", "table", "math", "os", "coroutine", "utf8", "bit", "load", "loadstring",
}

-- opts.allowWrite(name) -> bool : which new globals the code may define (e.g. TG_* handlers)
-- opts.label : shown in error messages
function sandbox.new(opts)
  opts = opts or {}
  local label = opts.label or "sandbox"
  local declared = {}
  local env = {}
  local sb = { env = env, declared = declared, writes = {} }

  for _, k in ipairs(STD) do
    if _G[k] ~= nil then rawset(env, k, _G[k]); declared[k] = true end
  end
  rawset(env, "_G", env); declared._G = true

  function sb.set(name, value) rawset(env, name, value); declared[name] = true end
  function sb.declare(...) for _, n in ipairs({ ... }) do declared[n] = true end end

  setmetatable(env, {
    __index = function(_, k)
      if declared[k] then return nil end
      error(string.format("[%s] read of undefined global '%s'", label, tostring(k)), 2)
    end,
    __newindex = function(t, k, v)
      if declared[k] or (opts.allowWrite and opts.allowWrite(k)) then
        declared[k] = true
        sb.writes[k] = true
        rawset(t, k, v)
        return
      end
      error(string.format("[%s] write to undefined global '%s'", label, tostring(k)), 2)
    end,
  })

  -- run a file in this environment; returns whatever the chunk returns
  function sb.dofile(path)
    local f, err = loadfile(path, "t", env)
    if not f then error(err, 0) end
    return f()
  end
  -- run a string (vehicle Lua etc.)
  function sb.dostring(code, name)
    local f, err = load(code, name or "=(string)", "t", env)
    if not f then error(err, 0) end
    return f()
  end

  return sb
end

return sandbox
