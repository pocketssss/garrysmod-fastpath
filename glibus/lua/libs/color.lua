--------------------------------------------------------------------
-- Semantics preserved from stock:
--  * Color(): tonumber conversion (string args work), clamp at 255
--  * HSV/HSL constructors skip tonumber/clamp entirely — their
--------------------------------------------------------------------

local setmetatable = setmetatable
local tonumber = tonumber
local floor, abs = math.floor, math.abs
local COLOR = FindMetaTable("Color")

function Color(r, g, b, a)
    r = tonumber(r)
    g = tonumber(g)
    b = tonumber(b)
    a = tonumber(a or 255)
    return setmetatable({
        r = r > 255 and 255 or r,
        g = g > 255 and 255 or g,
        b = b > 255 and 255 or b,
        a = a > 255 and 255 or a,
    }, COLOR)
end

function ColorAlpha(c, a)
    local r, g, b = tonumber(c.r), tonumber(c.g), tonumber(c.b)
    a = tonumber(a or 255)
    return setmetatable({
        r = r > 255 and 255 or r,
        g = g > 255 and 255 or g,
        b = b > 255 and 255 or b,
        a = a > 255 and 255 or a,
    }, COLOR)
end

function COLOR:Copy()
    local r, g, b, a = tonumber(self.r), tonumber(self.g), tonumber(self.b), tonumber(self.a)
    return setmetatable({
        r = r > 255 and 255 or r,
        g = g > 255 and 255 or g,
        b = b > 255 and 255 or b,
        a = a > 255 and 255 or a,
    }, COLOR)
end

function COLOR:Lerp(target, frac)
    local r = self.r + (target.r - self.r) * frac
    local g = self.g + (target.g - self.g) * frac
    local b = self.b + (target.b - self.b) * frac
    local a = self.a + (target.a - self.a) * frac
    return setmetatable({
        r = r > 255 and 255 or r,
        g = g > 255 and 255 or g,
        b = b > 255 and 255 or b,
        a = a > 255 and 255 or a,
    }, COLOR)
end

local function hue_to_rgb(h, c, x)
    if h < 60  then return c, x, 0 end
    if h < 120 then return x, c, 0 end
    if h < 180 then return 0, c, x end
    if h < 240 then return 0, x, c end
    if h < 300 then return x, 0, c end
    return c, 0, x
end

local function clamp255(n)
    n = floor(n)
    if n < 0 then return 0 end
    if n > 255 then return 255 end
    return n
end

function HSVToColor(h, s, v)
    h = h % 360
    local c = v * s
    local x = c * (1 - abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = hue_to_rgb(h, c, x)
    return setmetatable({
        r = clamp255((r + m) * 255),
        g = clamp255((g + m) * 255),
        b = clamp255((b + m) * 255),
        a = 255,
    }, COLOR)
end

function HSLToColor(h, s, l)
    h = h % 360
    local c = (1 - abs(2 * l - 1)) * s
    local x = c * (1 - abs((h / 60) % 2 - 1))
    local m = l - c / 2
    local r, g, b = hue_to_rgb(h, c, x)
    return setmetatable({
        r = clamp255((r + m) * 255),
        g = clamp255((g + m) * 255),
        b = clamp255((b + m) * 255),
        a = 255,
    }, COLOR)
end
