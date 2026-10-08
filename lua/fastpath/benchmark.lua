-- Real GLua microbenchmarks; all library writes stay in private environments.
if _G.FastPathBenchmarkRunning then return end
local realm = SERVER and "server" or "client"
local root = "addons/garrysmod-fastpath/fastpath/lua/"
local clock, sort = SysTime, table.sort
local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end
local function environment()
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.math = copy(math)
    env.hook = setmetatable({}, {__index = env})
    env.vector = copy(FindMetaTable("Vector"))
    env.color = copy(FindMetaTable("Color"))
    env.FindMetaTable = function(name)
        if name == "Vector" then return env.vector end
        if name == "Color" then return env.color end
        return FindMetaTable(name)
    end
    env.module = function(name) setfenv(2, env[name]) end
    return env
end
local function load(path, env)
    local source = assert(file.Read(path, "GAME"), "Missing " .. path)
    local fn = CompileString(source, path, false)
    assert(isfunction(fn), tostring(fn))
    setfenv(fn, env)
    fn()
    return util.CRC(source)
end
local stock, fast = environment(), environment()
local hashes = {stock_hook = load("lua/includes/modules/hook.lua", stock)}
hashes.loader = util.CRC(assert(file.Read(root .. "autorun/libs_init.lua", "GAME")))
hashes.benchmark = util.CRC(assert(file.Read("addons/garrysmod-fastpath/lua/fastpath/benchmark.lua", "GAME")))
for _, name in ipairs({"hook", "math", "vector", "color"}) do
    hashes[name] = load(root .. "libs/" .. name .. ".lua", fast)
end
local report = {
    realm = realm, date = os.date("!%Y-%m-%dT%H:%M:%SZ"), map = game.GetMap(),
    version = VERSIONSTR, branch = BRANCH, jit = {jit.status()},
    iterations = 100000, repeats = 9, warmup = 10000, hashes = hashes, rows = {},
    notes = "Private modules, live engine userdata; default JIT status unchanged. ns includes loop/wrapper overhead. No FPS claim from microbenchmarks."
}
local sink
local function runner(fn, name)
    -- A separately compiled loop per case/side avoids sharing a JIT trace
    -- guarded on another benchmark callback's identity.
    local source = [[
        local fn, clock = fn, clock
        local retained = {}
        return function(n)
            local start = clock()
            for i = 1, n do retained[i % 64 + 1] = fn(i) end
            return (clock() - start) * 1e9 / n
        end
    ]]
    local chunk = CompileString(source, "FPBenchDriver " .. name, false)
    setfenv(chunk, {fn = fn, clock = clock})
    return chunk()
end
local function stats(t)
    sort(t)
    return {median = t[5], min = t[1], max = t[9], samples = t}
end
local cases = {}
local function add(name, a, b, note, n)
    cases[#cases + 1] = {name = name, a = a, b = b, note = note, n = n or report.iterations}
end
local sm, fm = math, fast.math
add("loop control", function(i) return i end, function(i) return i end, "Harness overhead; not subtracted")
add("math.Clamp", function(i) return sm.Clamp(i % 400 - 100, 0, 255) end,
    function(i) return fm.Clamp(i % 400 - 100, 0, 255) end)
add("math.max / Max2", function(i) return sm.max(i % 97, i % 53) end,
    function(i) return fm.Max2(i % 97, i % 53) end)
add("math.min / Min3", function(i) return sm.min(i % 97, i % 53, i % 31) end,
    function(i) return fm.Min3(i % 97, i % 53, i % 31) end)
add("math.sin / qsin", function(i) return sm.sin(i * 0.001) end,
    function(i) return fm.qsin(i * 0.001) end, "Approximation; different accuracy")
add("math.cos / qcos", function(i) return sm.cos(i * 0.001) end,
    function(i) return fm.qcos(i * 0.001) end, "Approximation; different accuracy")
add("sin+cos / sincos", function(i) local x = i * 0.001 return sm.sin(x) + sm.cos(x) end,
    function(i) local a, b = fm.sincos(i * 0.001) return a + b end, "Approximation; two outputs")
add("math.random / SharedRandomFast", function() return sm.random(1, 100) end,
    function() return fm.SharedRandomFast(1, 100) end, "Different RNG and state; not util.SharedRandom replacement")
add("Color", function(i) return Color(i % 300, 20, 30, 255) end,
    function(i) return fast.Color(i % 300, 20, 30, 255) end)
local color = Color(20, 40, 60)
add("ColorAlpha", function(i) return ColorAlpha(color, i % 256) end,
    function(i) return fast.ColorAlpha(color, i % 256) end)
add("HSVToColor", function(i) return HSVToColor(i % 360, 0.7, 0.8) end,
    function(i) return fast.HSVToColor(i % 360, 0.7, 0.8) end)
add("HSLToColor", function(i) return HSLToColor(i % 360, 0.7, 0.4) end,
    function(i) return fast.HSLToColor(i % 360, 0.7, 0.4) end)
local v, target, mn, mx = Vector(150, -20, 500), Vector(100, 200, 300), Vector(), Vector(100, 100, 100)
add("Vector clamp (new)", function() return Vector(sm.Clamp(v.x, mn.x, mx.x), sm.Clamp(v.y, mn.y, mx.y), sm.Clamp(v.z, mn.z, mx.z)) end,
    function() return fast.vector.GetClamped(v, mn, mx) end, "Equivalent stock composition")
add("Vector lerp (in place)", function(i) local t = i % 100 / 100 v:Set(mn) v:Set(LerpVector(t, v, target)) return v.x end,
    function(i) v:Set(mn) fast.vector.LerpTo(v, target, i % 100 / 100) return v.x end, "Same input reset; stock allocates temporary Vector")
local function callback(x) sink = x end
for _, count in ipairs({0, 1, 10, 100}) do
    local event = "FPBench" .. count
    for i = 1, count do
        stock.hook.Add(event, "cb" .. i, callback)
        fast.hook.Add(event, "cb" .. i, callback)
    end
    add("hook.Call " .. count, function(i) return stock.hook.Call(event, nil, i) end,
        function(i) return fast.hook.Call(event, nil, i) end, "String identifiers, no return")
end
for _, count in ipairs({1, 100}) do
    local event = "FPChurn" .. count
    for i = 1, count do stock.hook.Add(event, "cb" .. i, callback) fast.hook.Add(event, "cb" .. i, callback) end
    add("hook.Add update " .. count, function() stock.hook.Add(event, "cb1", callback) end,
        function() fast.hook.Add(event, "cb1", callback) end)
    add("hook.Add+Remove " .. count, function() stock.hook.Add(event, "temp", callback) stock.hook.Remove(event, "temp") end,
        function() fast.hook.Add(event, "temp", callback) fast.hook.Remove(event, "temp") end, "One add/remove pair; COW cost", 10000)
end
report.accuracy = {qsin = 0, qcos = 0, sincos_sin = 0, sincos_cos = 0}
for i = -10000, 10000 do
    local x = i * math.pi / 10000
    local s, c = fm.sincos(x)
    report.accuracy.qsin = math.max(report.accuracy.qsin, math.abs(fm.qsin(x) - math.sin(x)))
    report.accuracy.qcos = math.max(report.accuracy.qcos, math.abs(fm.qcos(x) - math.cos(x)))
    report.accuracy.sincos_sin = math.max(report.accuracy.sincos_sin, math.abs(s - math.sin(x)))
    report.accuracy.sincos_cos = math.max(report.accuracy.sincos_cos, math.abs(c - math.cos(x)))
end
report.compatibility = {}
local function check(name, fn)
    local ok, err = pcall(fn)
    report.compatibility[#report.compatibility + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
    print("[FastPathBench] CHECK " .. realm .. " " .. name .. " " .. tostring(ok))
end
check("hook return false + six values", function()
    fast.hook.Add("FPCheck", "first", function() return false, 2, 3, 4, 5, 6 end)
    local a, b, c, d, e, f = fast.hook.Call("FPCheck", {})
    assert(a == false and b == 2 and c == 3 and d == 4 and e == 5 and f == 6)
    fast.hook.Remove("FPCheck", "first")
    assert(fast.hook.Call("FPCheck", {FPCheck = function() return 42 end}) == 42)
end)
check("Color false alpha stock compatibility", function()
    assert(Color(1, 2, 3, false).a == fast.Color(1, 2, 3, false).a)
    assert(ColorAlpha(Color(1, 2, 3), false).a == fast.ColorAlpha(Color(1, 2, 3), false).a)
end)
check("HSV/HSL channels (360 inputs)", function()
    for i = 0, 359 do
        for _, name in ipairs({"HSVToColor", "HSLToColor"}) do
            local a, b = _G[name](i, 0.7, 0.4), fast[name](i, 0.7, 0.4)
            assert(a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a, name .. " " .. i)
        end
    end
end)
check("loader migration and repeat inclusion", function()
    local env = environment()
    load("lua/includes/modules/hook.lua", env)
    env.hook.Add("FPExisting", "sentinel", function() return 123 end)
    env.file = copy(file)
    env.file.Exists = function(path, search) return file.Exists(root .. path, "GAME") end
    env.include = function(path) return load(root .. path, env) end
    env.AddCSLuaFile = function() end
    load(root .. "autorun/libs_init.lua", env)
    assert(env.hook.Call("FPExisting") == 123, "pre-existing hooks lost")
    env.hook.Add("FPAfter", "sentinel", function() return 456 end)
    load(root .. "autorun/libs_init.lua", env)
    assert(env.hook.Call("FPAfter") == 456, "repeat include lost hooks")
end)
local function finish()
    _G.FastPathBenchmarkRunning = nil
    report.completed = true
    file.CreateDir("fastpath_bench")
    file.Write("fastpath_bench/" .. realm .. ".json", util.TableToJSON(report, true))
    print("[FastPathBench] COMPLETE " .. realm)
    if SERVER then
        for _, ply in ipairs(player.GetHumans()) do ply:SendLua('include("fastpath/benchmark.lua")') end
    end
end
local function workload()
    local phases = {"idle", "stock", "fast", "fast", "stock", "idle"}
    local event = "FPFrameLoad"
    for i = 1, 100 do stock.hook.Add(event, "cb" .. i, callback) fast.hook.Add(event, "cb" .. i, callback) end
    report.workload = {dispatches = 1000, callbacks = 100, warmup_seconds = 2, sample_seconds = 5, phases = {}, tick_interval = engine.TickInterval()}
    if CLIENT then
        gui.HideGameUI()
        report.workload.focus = system.HasFocus()
        report.workload.cvars = {fps_max = GetConVar("fps_max"):GetString(), mat_vsync = GetConVar("mat_vsync"):GetString()}
        for _, name in ipairs({"fps_max_nofocus", "fps_max_menu"}) do
            if GetConVar(name) then report.workload.cvars[name] = GetConVar(name):GetString() end
        end
        report.workload.resolution = {ScrW(), ScrH()}
        local pos, angles = LocalPlayer():EyePos(), LocalPlayer():EyeAngles()
        hook.Add("CalcView", "FPFixedCamera", function() return {origin = pos, angles = angles, fov = 75} end)
        hook.Add("PostRender", "FPBenchmarkScreenshot", function()
            hook.Remove("PostRender", "FPBenchmarkScreenshot")
            local png = render.Capture({format = "png", x = 0, y = 0, w = ScrW(), h = ScrH(), alpha = false})
            if png then
                file.Write("fastpath_bench/scene.png", png)
                report.workload.screenshot = "scene.png"
            end
        end)
    end
    -- Compile/warm both dispatch paths before timing any phase.
    for i = 1, 1000 do stock.hook.Call(event, nil, i) fast.hook.Call(event, nil, i) end
    local index, started, last, times, cpu = 1, clock(), nil, {}, {}
    local focusFrames, menuFrames = 0, 0
    local hookName = SERVER and "Tick" or "Think"
    local function summary(t)
        sort(t)
        local total = 0
        for _, n in ipairs(t) do total = total + n end
        return {count = #t, median_ms = t[math.ceil(#t / 2)], p95_ms = t[math.ceil(#t * 0.95)], mean_ms = total / #t}
    end
    hook.Add(hookName, "FPWorkload", function()
        local now = clock()
        if now - started >= 7 then
            if #times < 30 then
                print("[FastPathBench] RETRY phase: insufficient samples " .. realm)
                started, last, times, cpu = now, nil, {}, {}
                return
            end
            report.workload.phases[#report.workload.phases + 1] = {mode = phases[index], interval = summary(times), cpu = summary(cpu), focus_frames = focusFrames, menu_frames = menuFrames}
            print("[FastPathBench] WORKLOAD " .. realm .. " " .. phases[index])
            index, started, last, times, cpu = index + 1, now, nil, {}, {}
            focusFrames, menuFrames = 0, 0
            if not phases[index] then
                hook.Remove(hookName, "FPWorkload")
                if CLIENT then
                    hook.Remove("CalcView", "FPFixedCamera")
                end
                finish()
                return
            end
        end
        local t = clock()
        local mode = phases[index]
        if mode ~= "idle" then
            local call = mode == "stock" and stock.hook.Call or fast.hook.Call
            for i = 1, 1000 do call(event, nil, i) end
        end
        local elapsed = (clock() - t) * 1000
        if now - started >= 2 and last then
            times[#times + 1] = (now - last) * 1000
            cpu[#cpu + 1] = elapsed
            if CLIENT then
                if system.HasFocus() then focusFrames = focusFrames + 1 end
                if gui.IsGameUIVisible() then menuFrames = menuFrames + 1 end
            end
        end
        last = now
    end)
end
local function runCase(index)
    local case = cases[index]
    if not case then
        workload()
        return
    end
    local ra, rb = runner(case.a, case.name .. " stock"), runner(case.b, case.name .. " fast")
    ra(report.warmup) rb(report.warmup)
    local a, b = {}, {}
    for r = 1, report.repeats do
        collectgarbage("collect")
        if r % 2 == 1 then a[r] = ra(case.n) b[r] = rb(case.n)
        else b[r] = rb(case.n) a[r] = ra(case.n) end
    end
    local sa, sb = stats(a), stats(b)
    report.rows[#report.rows + 1] = {name = case.name, stock = sa, fast = sb, ratio = sa.median / sb.median, note = case.note, iterations = case.n}
    print(string.format("[FastPathBench] %s %s %.2f / %.2f ns (%.2fx)", realm, case.name, sa.median, sb.median, sa.median / sb.median))
    timer.Simple(0.2, function() runCase(index + 1) end)
end
_G.FastPathBenchmarkRunning = true
runCase(1)
