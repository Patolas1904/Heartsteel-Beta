return function(HS, S)
    local Misc = HS.Misc or {}
    HS.Misc = Misc

    local Core = HS.Core

    function Misc.hasSafeGroundBelow(savedCFrame)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        local character = Core.player.Character
        if character then
            params.FilterDescendantsInstances = {character}
        end

        local result = workspace:Raycast(savedCFrame.Position, Vector3.new(0, -12, 0), params)
        return result ~= nil and result.Instance ~= nil
    end

    function Misc.isInsideActiveDungeon()
        local dungeon = HS.Dungeon
        if not dungeon or type(dungeon.isInsideActive) ~= "function" then return false end
        local ok, inside = pcall(dungeon.isInsideActive)
        return ok and inside == true
    end

    function Misc.simulateMovementPulse()
        if Misc.isInsideActiveDungeon() then
            Core.debugLog("Simulate movement skipped; active dungeon")
            return
        end

        local root = Core.getRoot()
        if not root then return end
        local saved = root.CFrame

        local wasAnchored = root.Anchored
        root.Anchored = true
        root.CFrame = saved * CFrame.new(0, 0, Misc.SIM_MOVE_DISTANCE)
        task.wait(Misc.SIM_MOVE_WAIT)
        if root.Parent then
            root.CFrame = saved
            root.Anchored = wasAnchored
        end
        Core.debugLog("Simulated movement pulse")
    end

    function Misc.startSimulateMovement()
        Core.loopWhile("simulate_movement", Misc.SIM_MOVE_DELAY, function()
            Misc.simulateMovementPulse()
        end)
    end
end
