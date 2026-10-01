-- Fake BeamNG vec3 / quat (enough of the API the client uses).
local M = {}

local V = {}
V.__index = V
local function vec3(x, y, z)
  if type(x) == "table" then x, y, z = x.x or x[1], x.y or x[2], x.z or x[3] end
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end
V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function(a) return vec3(-a.x, -a.y, -a.z) end
V.__mul = function(a, b)
  if type(a) == "number" then return vec3(b.x * a, b.y * a, b.z * a) end
  return vec3(a.x * b, a.y * b, a.z * b)
end
V.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
V.__tostring = function(a) return string.format("vec3(%g, %g, %g)", a.x, a.y, a.z) end
function V:length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function V:normalized()
  local l = self:length()
  if l < 1e-12 then return vec3(0, 0, 0) end
  return vec3(self.x / l, self.y / l, self.z / l)
end
function V:dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function V:cross(b) return vec3(self.y * b.z - self.z * b.y, self.z * b.x - self.x * b.z, self.x * b.y - self.y * b.x) end
function V:toPoint3F() return self end
M.vec3 = vec3

local Q = {}
Q.__index = Q
local function quat(x, y, z, w)
  if type(x) == "table" then x, y, z, w = x.x or x[1], x.y or x[2], x.z or x[3], x.w or x[4] end
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0, w = w or 1 }, Q)
end
M.quat = quat

-- yaw-only rotation facing `dir` (x/y plane), z up
function M.quatFromYaw(yaw)
  return quat(0, 0, math.sin(yaw / 2), math.cos(yaw / 2))
end
function M.quatFromDir(dir, _up)
  local atan2 = math.atan2 or math.atan
  -- BeamNG's forward is -y for vehicles; tests only need a consistent convention
  return M.quatFromYaw(atan2(dir.y, dir.x))
end
function M.dirFromQuat(q)
  local atan2 = math.atan2 or math.atan
  local yaw = atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z))
  return vec3(math.cos(yaw), math.sin(yaw), 0)
end

return M
