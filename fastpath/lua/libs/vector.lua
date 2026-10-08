--------------------------------------------------------------------
-- Length, Distance, Normalize, Dot, Cross, LengthSqr, DistToSqr,
-- GetNormalized, IsZero are intentionally NOT redefined here.
-- They are native C++ engine methods, and any Lua replacement
-- of them is slower.
--
-- Key optimization: method functions are localized once. Vector's
-- __index is a C function, so `self:Unpack()` costs TWO boundary
-- crossings (method lookup + call); `Unpack(self)` costs one.
--------------------------------------------------------------------

local vec    = FindMetaTable("Vector")
local Vector = Vector
local sqrt   = math.sqrt

local Unpack      = vec.Unpack
local SetUnpacked = vec.SetUnpacked

function vec:Clamp(mn, mx)
    local x, y, z    = Unpack(self)
    local ax, ay, az = Unpack(mn)
    local bx, by, bz = Unpack(mx)
    SetUnpacked(self,
        x < ax and ax or (x > bx and bx or x),
        y < ay and ay or (y > by and by or y),
        z < az and az or (z > bz and bz or z)
    )
    return self
end

function vec:GetClamped(mn, mx)
    local x, y, z    = Unpack(self)
    local ax, ay, az = Unpack(mn)
    local bx, by, bz = Unpack(mx)
    return Vector(
        x < ax and ax or (x > bx and bx or x),
        y < ay and ay or (y > by and by or y),
        z < az and az or (z > bz and bz or z)
    )
end

function vec:Min(other)
    local x, y, z    = Unpack(self)
    local ox, oy, oz = Unpack(other)
    SetUnpacked(self,
        x < ox and x or ox,
        y < oy and y or oy,
        z < oz and z or oz
    )
    return self
end

function vec:Max(other)
    local x, y, z    = Unpack(self)
    local ox, oy, oz = Unpack(other)
    SetUnpacked(self,
        x > ox and x or ox,
        y > oy and y or oy,
        z > oz and z or oz
    )
    return self
end

function vec:GetMin(other)
    local x, y, z    = Unpack(self)
    local ox, oy, oz = Unpack(other)
    return Vector(
        x < ox and x or ox,
        y < oy and y or oy,
        z < oz and z or oz
    )
end

function vec:GetMax(other)
    local x, y, z    = Unpack(self)
    local ox, oy, oz = Unpack(other)
    return Vector(
        x > ox and x or ox,
        y > oy and y or oy,
        z > oz and z or oz
    )
end

function vec:ClampLength(maxlen)
    local x, y, z = Unpack(self)
    local lsq = x * x + y * y + z * z
    if lsq > maxlen * maxlen then
        local s = maxlen / sqrt(lsq)
        SetUnpacked(self, x * s, y * s, z * s)
    end
    return self
end

function vec:GetClampedLength(maxlen)
    local x, y, z = Unpack(self)
    local lsq = x * x + y * y + z * z
    if lsq > maxlen * maxlen then
        local s = maxlen / sqrt(lsq)
        return Vector(x * s, y * s, z * s)
    end
    return Vector(x, y, z)
end

function vec:LerpTo(other, t)
    local x, y, z    = Unpack(self)
    local ox, oy, oz = Unpack(other)
    local it = 1 - t
    SetUnpacked(self,
        x * it + ox * t,
        y * it + oy * t,
        z * it + oz * t
    )
    return self
end
