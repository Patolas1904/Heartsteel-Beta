return function(HS, S)
    local Misc = HS.Misc or {}
    HS.Misc = Misc

    local Core = HS.Core

    Misc.eggAnimMovedToStorage   = false
    Misc.eggAnimChildAddedConn   = nil

    local function getEggAnimContainers()
        local mainGui    = Core.player.PlayerGui:FindFirstChild("MainGui")
        local otherFrames = mainGui and mainGui:FindFirstChild("OtherFrames")
        if not otherFrames then return nil, nil end
        local openEggs  = otherFrames:FindFirstChild("OpenEggs")
        if not openEggs then return nil, nil end
        local openEggs2 = otherFrames:FindFirstChild("OpenEggs2")
        if not openEggs2 then
            openEggs2 = openEggs:Clone()
            openEggs2.Name = "OpenEggs2"
            openEggs2.Parent = otherFrames
            for _, child in ipairs(openEggs2:GetChildren()) do child:Destroy() end
        end
        return openEggs, openEggs2
    end

    local function moveEggChildren(from, to)
        for _, child in ipairs(from:GetChildren()) do child.Parent = to end
    end

    function Misc.applyHideEggAnimations(enabled)
        local openEggs, openEggs2 = getEggAnimContainers()
        if not openEggs or not openEggs2 then return end
        if enabled and not Misc.eggAnimMovedToStorage then
            moveEggChildren(openEggs, openEggs2)
            Misc.eggAnimMovedToStorage = true
            if not Misc.eggAnimChildAddedConn then
                Misc.eggAnimChildAddedConn = openEggs.ChildAdded:Connect(function(child)
                    if Misc.eggAnimMovedToStorage then child.Parent = openEggs2 end
                end)
            end
            Core.debugLog("Hide egg animations ON")
        elseif not enabled and Misc.eggAnimMovedToStorage then
            if Misc.eggAnimChildAddedConn then
                Misc.eggAnimChildAddedConn:Disconnect()
                Misc.eggAnimChildAddedConn = nil
            end
            moveEggChildren(openEggs2, openEggs)
            Misc.eggAnimMovedToStorage = false
            Core.debugLog("Hide egg animations OFF")
        end
    end
end
