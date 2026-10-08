local pi       = math.pi
local doublepi = pi * 2
local halfpi   = pi * 0.5
local abs      = math.abs

local a_sin, b_sin = -0.166667,  0.00833
local a_cos, b_cos = -0.5,       0.0416667
local q1, q2       = 1.27323954, 0.405284735

local function normalize_angle(n)
    return (n + pi) % doublepi - pi
end
math.NormalizeAngleRad = normalize_angle

local function max2(a, b) return a > b and a or b end
local function min2(a, b) return a < b and a or b end

local function max3(a, b, c)
    if b > a then a = b end
    if c > a then a = c end
    return a
end

local function min3(a, b, c)
    if b < a then a = b end
    if c < a then a = c end
    return a
end

local function maxt(t)
    local m = t[1]
    for i = 2, #t do
        local v = t[i]
        if v > m then m = v end
    end
    return m
end

local function mint(t)
    local m = t[1]
    for i = 2, #t do
        local v = t[i]
        if v < m then m = v end
    end
    return m
end

math.Max2, math.Min2 = max2, min2
math.Max3, math.Min3 = max3, min3
math.MaxT, math.MinT = maxt, mint

function math.Clamp(n, l, h)
    return n < l and l or (n > h and h or n)
end

-- Without the sin roll-off, the error at the edges is ~0.52; for cos, it's ~1.12
local function sincos(n)
    n = (n + pi) % doublepi - pi
    local cs = 1
    if n > halfpi then
        n = pi - n
        cs = -1
    elseif n < -halfpi then
        n = -pi - n
        cs = -1
    end
    local x2 = n * n
    return n * (1 + x2 * (a_sin + x2 * b_sin)),
           cs * (1 + x2 * (a_cos + x2 * b_cos))
end
math.sincos = sincos

local function qsin(n)
    n = (n + pi) % doublepi - pi
    local x = n * (q1 - q2 * abs(n))
    return x + 0.225 * x * (abs(x) - 1)
end
math.qsin = qsin

local function qcos(n)
    n = (n + halfpi + pi) % doublepi - pi
    local x = n * (q1 - q2 * abs(n))
    return x + 0.225 * x * (abs(x) - 1)
end
math.qcos = qcos

-- math.rad / math.deg DO NOT redefine: in LuaJIT, these are built-in assembly functions
local RAD = pi / 180
local DEG = 180 / pi

local rand_state = 1

function math.SharedRandomSeed(seed)
    rand_state = (math.floor(abs(seed)) % 2147483646) + 1
end

function math.SharedRandom(l, h)
    if not h then
        if l then h = l; l = 0
        else l = 0; h = 0xFFFFFF end
    end
    rand_state = (rand_state * 16807) % 2147483647
    return l + rand_state % (h - l + 1)
end

function math.SharedRandomFast(l, h)
    rand_state = (rand_state * 16807) % 2147483647
    return l + rand_state % (h - l + 1)
end

function math.SharedRandomFloat()
    rand_state = (rand_state * 16807) % 2147483647
    return rand_state * (1 / 2147483647)
end

return {
    sincos  = sincos,
    qsin    = qsin,
    qcos    = qcos,
    max2    = max2,
    min2    = min2,
    max3    = max3,
    min3    = min3,
    maxt    = maxt,
    mint    = mint,
    normalize_angle = normalize_angle,
    RAD = RAD,
    DEG = DEG,
}
