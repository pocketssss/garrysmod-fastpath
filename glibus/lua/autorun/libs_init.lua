--------------------------------------------------------------------
-- Include each library once per realm, including during auto-refresh.
--------------------------------------------------------------------

local FILES = {
    "libs/hook.lua",
    "libs/math.lua",
    "libs/vector.lua",
    "libs/color.lua",
}

local function log(fmt, ...)
    print("[lib] " .. string.format(fmt, ...))
end

local t0 = SysTime()
local failed = 0
local pre_existing = hook.GetTable()
_G.GLibusLoadedFiles = _G.GLibusLoadedFiles or {}
local loaded = _G.GLibusLoadedFiles

for i = 1, #FILES do
    local path = FILES[i]

    if not file.Exists(path, "LUA") then
        failed = failed + 1
        log("[FAIL] %s: file not found", path)
    else
        if SERVER then AddCSLuaFile(path) end

        local ok, err = true, nil
        local first_load = not loaded[path]
        if first_load then ok, err = pcall(include, path) end
        if not ok then
            failed = failed + 1
            log("[FAIL] %s: %s", path, tostring(err))
        end

        if path == "libs/hook.lua" and ok and first_load then
            local migrated = 0
            for event, hooks in pairs(pre_existing) do
                for name, fn in pairs(hooks) do
                    hook.Add(event, name, fn)
                    migrated = migrated + 1
                end
            end
            if migrated > 0 then
                log("migrated %d pre-existing hooks", migrated)
            end
        end
        if ok then loaded[path] = true end
    end
end

log("loaded %d/%d in %.1f ms", #FILES - failed, #FILES, (SysTime() - t0) * 1000)
