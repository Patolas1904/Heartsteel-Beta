return function(HS, S)
local Core = HS.Core

HS.Misc.startAntiAfk()
HS.UI.renderContent()
HS.Logs.Pets.syncConnection()
HS.Logs.DiscordMonitor.sync()
HS.Misc.applyHideEggAnimations(Core.state.hide_egg_animations == true)

-- Load all hidden regions on startup
task.spawn(function()
    local hidden        = S.ReplicatedStorage:WaitForChild("HiddenRegions")
    local gameplay      = workspace:WaitForChild("Gameplay")
    local regionsLoaded = gameplay:WaitForChild("RegionsLoaded")

    local function moveAllToLoaded()
        for _, region in ipairs(hidden:GetChildren()) do
            Core.debugLog("Moving region to RegionsLoaded:", region.Name)
            region.Parent = regionsLoaded
        end
    end

    moveAllToLoaded()

    task.wait(0.5)
    -- No startup Grandmaster preload teleport. Keep startup passive so dungeon
    -- runs and restored sessions cannot be interrupted by a forced world TP.

    hidden.ChildAdded:Connect(function(region)
        Core.debugLog("Region returned to HiddenRegions, re-parenting:", region.Name)
        task.wait(0.1); region.Parent = regionsLoaded
    end)
end)

task.spawn(function()
    task.wait(0.2)
    HS.Dungeon.openIncubatorMenu(true)
    if Core.activeTab == "Dungeon" then HS.UI.renderContent() end
end)
task.spawn(function() task.wait(2); HS.UI.refreshQuestTitles() end)
task.spawn(function() task.wait(3); HS.Farming.refreshClanQuestInfo() end)
end
