--------------------------------------------------------------------
-- hook (modified Srlion-style) — flat arrays + segmented dispatch
--------------------------------------------------------------------

local gmod = gmod
local math = math
local file = file
local timer = timer
local pairs = pairs
local isstring = isstring
local isnumber = isnumber
local isbool = isbool
local isfunction = isfunction
local type = type
local ErrorNoHaltWithStack = ErrorNoHaltWithStack
local ErrorNoHalt = ErrorNoHalt
local print = print
local GProtectedCall = ProtectedCall
local tostring = tostring
local math_floor = math.floor

local _GLOBAL = _G

do
    HOOK_MONITOR_HIGH = -2
    HOOK_HIGH = -1
    HOOK_NORMAL = 0
    HOOK_LOW = 1
    HOOK_MONITOR_LOW = 2

    PRE_HOOK = { -4 }
    PRE_HOOK_RETURN = { -3 }
    NORMAL_HOOK = { 0 }
    POST_HOOK_RETURN = { 3 }
    POST_HOOK = { 4 }
end

local PRE_HOOK, PRE_HOOK_RETURN = PRE_HOOK, PRE_HOOK_RETURN
local NORMAL_HOOK = NORMAL_HOOK
local POST_HOOK_RETURN, POST_HOOK = POST_HOOK_RETURN, POST_HOOK

-- priority -> total order inside the normal list
local ORDER = {
    [PRE_HOOK]          = 1, -- suppressed (prefix)
    [HOOK_MONITOR_HIGH] = 2, -- suppressed (prefix)
    [PRE_HOOK_RETURN]   = 3,
    [HOOK_HIGH]         = 4,
    [NORMAL_HOOK]       = 5,
    [HOOK_NORMAL]       = 5,
    [HOOK_LOW]          = 6,
    [HOOK_MONITOR_LOW]  = 7, -- suppressed (suffix)
}
local SUP_PREFIX_MAX = 2 -- orders 1..2 cannot return
local RET_MAX        = 6 -- orders 3..6 can return; 7 cannot

local LIST_OF = { [POST_HOOK_RETURN] = 2, [POST_HOOK] = 3 }
for prio in pairs(ORDER) do LIST_OF[prio] = 1 end

local PRIORITY_NAMES = {
    [PRE_HOOK] = "PRE_HOOK", [HOOK_MONITOR_HIGH] = "HOOK_MONITOR_HIGH",
    [PRE_HOOK_RETURN] = "PRE_HOOK_RETURN", [HOOK_HIGH] = "HOOK_HIGH",
    [NORMAL_HOOK] = "NORMAL_HOOK", [HOOK_NORMAL] = "HOOK_NORMAL",
    [HOOK_LOW] = "HOOK_LOW", [HOOK_MONITOR_LOW] = "HOOK_MONITOR_LOW",
    [POST_HOOK_RETURN] = "POST_HOOK_RETURN", [POST_HOOK] = "POST_HOOK",
}

module("hook")

Author = "Srlion (mod: flat-array/segmented)"
Version = "3.1.0-flat"

--------------------------------------------------------------------
-- Storage.
-- events[event] = {
--   lists = {
--     [1] = { n=0, f={}, nm={}, ord={}, sup=0, ret=0 }, -- normal
--     [2] = { n=0, f={}, nm={} },                       -- post-return
--     [3] = { n=0, f={}, nm={} },                       -- post
--   },
--   byname = { [name] = { priority=?, order=?, li=?, pos=?,
--                         func=?, real_func=? } },
-- }
-- lists are IMMUTABLE except funcs[pos] in-place updates; any
-- structural change replaces the whole list table (COW).
--------------------------------------------------------------------
local events = {}

local function new_list(li)
    if li == 1 then
        return { n = 0, f = {}, nm = {}, ord = {}, sup = 0, ret = 0 }
    end
    return { n = 0, f = {}, nm = {} }
end

local function get_event(name)
    local e = events[name]
    if not e then
        e = {
            lists = { new_list(1), new_list(2), new_list(3) },
            byname = {},
        }
        events[name] = e
    end
    return e
end

-- Rebuild list `li` of event `e` applying one optional splice:
--   skip_name  — leave this hook out (Remove)
--   ins        — { name=?, func=?, order=? } insert in order (Add)
-- Recomputes segment boundaries and byname positions in one pass.
local function rebuild(e, li, skip_name, ins)
    local old = e.lists[li]
    local new = new_list(li)
    local f, nm = new.f, new.nm
    local ord = new.ord
    local byname = e.byname
    local n = 0

    local of, onm = old.f, old.nm
    local oord = old.ord
    local ins_order = ins and ins.order

    for i = 1, old.n do
        local hname = onm[i]
        if hname ~= skip_name then
            -- splice before the first entry with a higher order
            if ins and oord and oord[i] > ins_order then
                n = n + 1
                f[n], nm[n], ord[n] = ins.func, ins.name, ins_order
                byname[ins.name].pos = n
                ins = nil
            end
            n = n + 1
            f[n], nm[n] = of[i], hname
            if oord then ord[n] = oord[i] end
            byname[hname].pos = n
        end
    end
    if ins then -- goes at the end
        n = n + 1
        f[n], nm[n] = ins.func, ins.name
        if li == 1 then ord[n] = ins_order end
        byname[ins.name].pos = n
    end
    new.n = n

    if li == 1 then -- segment boundaries
        local sup, ret = 0, 0
        for i = 1, n do
            local o = ord[i]
            if o <= SUP_PREFIX_MAX then sup = i end
            if o <= RET_MAX then ret = i end
        end
        new.sup, new.ret = sup, ret
    end

    e.lists[li] = new
end

--------------------------------------------------------------------
-- Add / Remove
--------------------------------------------------------------------
function Remove(event_name, name)
    if not isstring(event_name) then
        ErrorNoHaltWithStack("bad argument #1 to 'Remove' (string expected, got " .. type(event_name) .. ")")
        return
    end
    if not isstring(name) then
        local bad = name == nil or isnumber(name) or isbool(name)
            or isfunction(name) or not name.IsValid
        if bad then
            ErrorNoHaltWithStack("bad argument #2 to 'Remove' (string expected, got " .. type(name) .. ")")
            return
        end
    end

    local e = events[event_name]
    if not e then return end
    local info = e.byname[name]
    if not info then return end

    rebuild(e, info.li, name, nil)
    e.byname[name] = nil
end

function Add(event_name, name, func, priority)
    if not isstring(event_name) then
        ErrorNoHaltWithStack("bad argument #1 to 'Add' (string expected, got " .. type(event_name) .. ")")
        return
    end
    if not isfunction(func) then
        ErrorNoHaltWithStack("bad argument #3 to 'Add' (function expected, got " .. type(func) .. ")")
        return
    end
    if not isstring(name) then
        local bad = name == nil or isnumber(name) or isbool(name)
            or isfunction(name) or not name.IsValid
        if bad then
            ErrorNoHaltWithStack("bad argument #2 to 'Add' (string expected, got " .. type(name) .. ")")
            return
        end
    end

    local real_func = func

    -- entity hooks: bind + self-remove when invalid (closure is
    -- unavoidable here — the binding itself needs captured state)
    if not isstring(name) then
        local ent = name
        func = function(...)
            local isvalid = ent.IsValid
            if isvalid and isvalid(ent) then
                return real_func(ent, ...)
            end
            Remove(event_name, ent)
        end
    end

    -- normalize priority; NOTE: no wrapper closures — suppression
    -- of returns is handled structurally by list segments
    if isnumber(priority) then
        priority = math_floor(priority)
        if priority < -2 then priority = -2 end
        if priority >  2 then priority =  2 end
    elseif ORDER[priority] or LIST_OF[priority] then
        -- special table priority, keep as-is
    else
        if priority ~= nil then
            ErrorNoHaltWithStack("bad argument #4 to 'Add' (priority expected, got " .. type(priority) .. ")")
        end
        priority = NORMAL_HOOK
    end

    local li = LIST_OF[priority] or 1
    local order = li == 1 and ORDER[priority] or 0

    local e = get_event(event_name)
    local byname = e.byname
    local info = byname[name]

    if info then
        if info.priority == priority then
            -- O(1) in-place function update; visible immediately,
            -- including to an in-flight Call (intended)
            info.func, info.real_func = func, real_func
            e.lists[info.li].f[info.pos] = func
            return
        end
        -- priority changed -> treat as remove + add
        rebuild(e, info.li, name, nil)
        byname[name] = nil
    end

    byname[name] = {
        priority = priority, order = order, li = li,
        pos = 0, -- set by rebuild
        func = func, real_func = real_func,
    }

    if li == 1 then
        rebuild(e, 1, nil, { name = name, func = func, order = order })
    else
        -- post lists: append order, splice at end
        rebuild(e, li, nil, { name = name, func = func, order = math.huge })
    end
end

--------------------------------------------------------------------
-- GetTable (compat)
--------------------------------------------------------------------
function GetTable()
    local out = {}
    for event_name, e in pairs(events) do
        local t = {}
        for hname, info in pairs(e.byname) do
            t[hname] = info.real_func
        end
        out[event_name] = t
    end
    return out
end

--------------------------------------------------------------------
-- Call — the hot path.
-- Three plain loops over a flat function array; locals snapshot the
-- list so concurrent Add/Remove (COW) cannot corrupt iteration.
--------------------------------------------------------------------
function Call(event_name, gm, ...)
    local e = events[event_name]
    if not e then -- fast path: no hooks at all
        if not gm then return end
        local gm_func = gm[event_name]
        if not gm_func then return end
        return gm_func(gm, ...)
    end

    local lists = e.lists
    local L = lists[1]
    local f = L.f
    local sup, ret, n = L.sup, L.ret, L.n

    local hook_src, a, b, c, d, e2, f2

    -- 1) suppressed prefix (PRE_HOOK, MONITOR_HIGH): returns ignored,
    --    no per-hook branching, no wrappers
    for i = 1, sup do
        f[i](...)
    end

    -- 2) returnable middle: first non-nil return wins
    for i = sup + 1, ret do
        local r1, r2, r3, r4, r5, r6 = f[i](...)
        if r1 ~= nil then
            hook_src = L.nm[i]
            a, b, c, d, e2, f2 = r1, r2, r3, r4, r5, r6
            break
        end
    end

    if hook_src == nil then
        -- 3) suppressed suffix (MONITOR_LOW) — only when nothing
        --    returned (same as breaking out of Srlion's single loop)
        for i = ret + 1, n do
            f[i](...)
        end

        if gm then
            local gm_func = gm[event_name]
            if gm_func then
                hook_src = gm
                a, b, c, d, e2, f2 = gm_func(gm, ...)
            end
        end
    end

    local L2, L3 = lists[2], lists[3]
    if L2.n == 0 and L3.n == 0 then
        return a, b, c, d, e2, f2
    end

    -- rare path: post-return / post hooks
    local returned_values = { hook_src, a, b, c, d, e2, f2 }

    do
        local pf, pnm = L2.f, L2.nm
        for i = 1, L2.n do
            local r1, r2, r3, r4, r5, r6 = pf[i](returned_values, ...)
            if r1 ~= nil then
                a, b, c, d, e2, f2 = r1, r2, r3, r4, r5, r6
                returned_values = { pnm[i], a, b, c, d, e2, f2 }
                break
            end
        end
    end

    do
        local pf = L3.f
        for i = 1, L3.n do
            pf[i](returned_values, ...)
        end
    end

    return a, b, c, d, e2, f2
end

--------------------------------------------------------------------
-- ProtectedCall — isolation over speed, cold-ish path
--------------------------------------------------------------------
function ProtectedCall(event_name, gm, ...)
    local e = events[event_name]
    if not e then
        if not gm then return end
        local gm_func = gm[event_name]
        if not gm_func then return end
        GProtectedCall(gm_func, gm, ...)
        return
    end

    local lists = e.lists
    local L = lists[1]
    local f, n = L.f, L.n
    for i = 1, n do
        GProtectedCall(f[i], ...)
    end

    if gm then
        local gm_func = gm[event_name]
        if gm_func then GProtectedCall(gm_func, gm, ...) end
    end

    local returned_values = { nil, nil, nil, nil, nil, nil, nil }
    local L2, L3 = lists[2], lists[3]
    for i = 1, L2.n do GProtectedCall(L2.f[i], returned_values, ...) end
    for i = 1, L3.n do GProtectedCall(L3.f[i], returned_values, ...) end
end

--------------------------------------------------------------------
-- Run / ProtectedRun with self-healing gamemode cache
--------------------------------------------------------------------
local gamemode_cache

function InvalidateGamemodeCache()
    gamemode_cache = nil
end

function Run(name, ...)
    local gm = gamemode_cache
    if gm == nil then
        gm = gmod and gmod.GetGamemode() or nil
        gamemode_cache = gm
    end
    return Call(name, gm, ...)
end

function ProtectedRun(name, ...)
    local gm = gamemode_cache
    if gm == nil then
        gm = gmod and gmod.GetGamemode() or nil
        gamemode_cache = gm
    end
    return ProtectedCall(name, gm, ...)
end

-- gamemode can change on reload; drop the cache at those moments
Add("Initialize", "hook_gm_cache_reset", InvalidateGamemodeCache, PRE_HOOK)
Add("OnReloaded", "hook_gm_cache_reset", InvalidateGamemodeCache, PRE_HOOK)

--------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------
function Debug(event_name)
    local e = events[event_name]
    if not e then
        print("No event with that name")
        return
    end
    print("------START------")
    print("event:", event_name)
    for li = 1, 3 do
        local L = e.lists[li]
        for i = 1, L.n do
            local hname = L.nm[i]
            local info = e.byname[hname]
            print("----------")
            print("   name:", hname)
            print("   func:", L.f[i])
            print("   real_func:", info and info.real_func)
            print("   priority:", info and PRIORITY_NAMES[info.priority] or info and info.priority)
            print("   list/pos:", li, i)
        end
        if li == 1 then
            print("   [segments] sup:", L.sup, "ret:", L.ret, "n:", L.n)
        end
    end
    print("-------END-------")
end

--------------------------------------------------------------------
-- ULib / DLib compatibility (from Srlion, unchanged in spirit)
--------------------------------------------------------------------
do
    if file.Exists("ulib/shared/hook.lua", "LUA") then
        local old_include = _GLOBAL.include
        function _GLOBAL.include(fl, ...)
            if fl == "ulib/shared/hook.lua" then
                timer.Simple(0, function()
                    print("Hook Library: Stopped ULX/ULib from loading its hook library!")
                end)
                _GLOBAL.include = old_include
                return
            end
            return old_include(fl, ...)
        end

        function GetULibTable()
            local new_events = {}
            for event_name, e in pairs(events) do
                local hooks = { [-2] = {}, [-1] = {}, [0] = {}, [1] = {}, [2] = {} }
                for hname, info in pairs(e.byname) do
                    local p = info.priority
                    p = isnumber(p) and p or p[1]
                    if p < -2 then p = -2 elseif p > 2 then p = 2 end
                    hooks[p][hname] = info.real_func
                end
                new_events[event_name] = hooks
            end
            return new_events
        end
    end

    if file.Exists("dlib/modules/hook.lua", "LUA") then
        timer.Simple(0, function()
            ErrorNoHalt("Hook Library: DLib hook module detected — it will conflict with this library!\n")
        end)
    end
end
