-- Minimal JSON for the test harness (stands in for BeamMP's Util.Json* and BeamNG's jsonEncode/jsonDecode).
-- Integral numbers decode as Lua integers on 5.3+ (like BeamMP's nlohmann-based decoder), so the
-- "%d needs an integer" class of bug shows up here too.
local json = {}

local tointeger = math.tointeger or function(n) return n end

local function isArray(t)
  local n = #t
  if n == 0 then return false end
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count == n
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function encodeString(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end

local function encode(v, depth)
  depth = depth or 0
  if depth > 60 then error("json: nesting too deep (cycle?)") end
  local t = type(v)
  if v == nil then return "null"
  elseif t == "boolean" then return tostring(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.type and math.type(v) == "integer" then return string.format("%d", v) end
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%.0f", v) end
    return string.format("%.17g", v)
  elseif t == "string" then return encodeString(v)
  elseif t == "table" then
    local out = {}
    if isArray(v) then
      for i = 1, #v do out[i] = encode(v[i], depth + 1) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      out[#out + 1] = encodeString(tostring(k)) .. ":" .. encode(v[k], depth + 1)
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
  error("json: can't encode a " .. t)
end
json.encode = function(v) return encode(v, 0) end

local function decodeError(s, i, msg) error(string.format("json: %s at position %d near %q", msg, i, s:sub(i, i + 20)), 0) end

local decodeValue
local function skip(s, i) return (s:find("[^ \t\r\n]", i)) or #s + 1 end

local function decodeString(s, i)
  local out, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == "" then decodeError(s, i, "unterminated string") end
    if c == '"' then return table.concat(out), j + 1 end
    if c == "\\" then
      local e = s:sub(j + 1, j + 1)
      local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
      if map[e] then out[#out + 1] = map[e]; j = j + 2
      elseif e == "u" then
        local code = tonumber(s:sub(j + 2, j + 5), 16)
        if not code then decodeError(s, j, "bad \\u escape") end
        if code < 128 then out[#out + 1] = string.char(code)
        elseif code < 2048 then out[#out + 1] = string.char(192 + math.floor(code / 64), 128 + code % 64)
        else out[#out + 1] = string.char(224 + math.floor(code / 4096), 128 + math.floor(code / 64) % 64, 128 + code % 64) end
        j = j + 6
      else decodeError(s, j, "bad escape") end
    else out[#out + 1] = c; j = j + 1 end
  end
end

decodeValue = function(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local t = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == "}" then return t, i + 1 end
    while true do
      if s:sub(i, i) ~= '"' then decodeError(s, i, "expected a key") end
      local k; k, i = decodeString(s, i)
      i = skip(s, i)
      if s:sub(i, i) ~= ":" then decodeError(s, i, "expected ':'") end
      local v; v, i = decodeValue(s, i + 1)
      t[k] = v
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "}" then return t, i + 1 end
      if d ~= "," then decodeError(s, i, "expected ',' or '}'") end
      i = skip(s, i + 1)
    end
  elseif c == "[" then
    local t, n = {}, 0
    i = skip(s, i + 1)
    if s:sub(i, i) == "]" then return t, i + 1 end
    while true do
      local v; v, i = decodeValue(s, i)
      n = n + 1; t[n] = v
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "]" then return t, i + 1 end
      if d ~= "," then decodeError(s, i, "expected ',' or ']'") end
      i = i + 1
    end
  elseif c == '"' then return decodeString(s, i)
  elseif s:sub(i, i + 3) == "true" then return true, i + 4
  elseif s:sub(i, i + 4) == "false" then return false, i + 5
  elseif s:sub(i, i + 3) == "null" then return nil, i + 4
  else
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not num or num == "" then decodeError(s, i, "unexpected character") end
    local v = tonumber(num)
    if not v then decodeError(s, i, "bad number") end
    if not num:find("[%.eE]") then v = tointeger(v) or v end
    return v, i + #num
  end
end

json.decode = function(s)
  if type(s) ~= "string" then error("json: expected a string, got " .. type(s), 0) end
  local v, i = decodeValue(s, 1)
  i = skip(s, i)
  if i <= #s then decodeError(s, i, "trailing characters") end
  return v
end

return json
