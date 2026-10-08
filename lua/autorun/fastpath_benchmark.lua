-- Opt-in diagnostic only. Does not install FastPath into the game globals.
if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("fastpath/benchmark.lua")
end
local enabled = CreateConVar("fastpath_bench_autorun", "0", 0, "Run isolated FastPath benchmarks after map load")
concommand.Add("fastpath_bench", function(ply)
    if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
    include("fastpath/benchmark.lua")
end)
-- Avoid depending on another addon's InitPostEntity return value/order.
timer.Simple(20, function()
    if SERVER and (enabled:GetBool() or file.Exists("addons/garrysmod-fastpath/benchmarks/RUN_ONCE", "GAME")) then
        for _, ply in ipairs(player.GetHumans()) do ply:SendLua("gui.HideGameUI()") end
        include("fastpath/benchmark.lua")
    end
end)
