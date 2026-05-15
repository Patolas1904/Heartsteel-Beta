return function(HS, S)
    local Misc = HS.Misc or {}
    HS.Misc = Misc

    local Core = HS.Core

    Misc.moveSpeed          = 16
    Misc.originalMoveSpeed  = nil
    Misc.moveSpeedConn      = nil
    Misc.moveSpeedCharConn  = nil

    function Misc.getHumanoid()
        local char = Core.player.Character
        if not char then return nil end
        return char:FindFirstChildOfClass("Humanoid")
    end

    function Misc.applySpeed()
        local hum = Misc.getHumanoid()
        if hum then hum.WalkSpeed = Misc.moveSpeed end
    end

    function Misc.setSpeed(val)
        Misc.moveSpeed = math.clamp(tonumber(val) or 16, 16, 160)
        if Core.state.move_speed then Misc.applySpeed() end
    end

    function Misc.startSpeed()
        local hum = Misc.getHumanoid()
        if hum and Misc.originalMoveSpeed == nil then
            Misc.originalMoveSpeed = hum.WalkSpeed
        end

        if Misc.moveSpeedConn then Misc.moveSpeedConn:Disconnect(); Misc.moveSpeedConn = nil end
        if hum then
            Misc.moveSpeedConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
                if Core.state.move_speed and hum.WalkSpeed ~= Misc.moveSpeed then
                    hum.WalkSpeed = Misc.moveSpeed
                end
            end)
        end

        if Misc.moveSpeedCharConn then Misc.moveSpeedCharConn:Disconnect(); Misc.moveSpeedCharConn = nil end
        Misc.moveSpeedCharConn = Core.player.CharacterAdded:Connect(function(char)
            local newHum = char:WaitForChild("Humanoid", 5)
            if not newHum then return end
            if Core.state.move_speed then
                if Misc.originalMoveSpeed == nil then
                    Misc.originalMoveSpeed = newHum.WalkSpeed
                end
                if Misc.moveSpeedConn then Misc.moveSpeedConn:Disconnect(); Misc.moveSpeedConn = nil end
                Misc.moveSpeedConn = newHum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
                    if Core.state.move_speed and newHum.WalkSpeed ~= Misc.moveSpeed then
                        newHum.WalkSpeed = Misc.moveSpeed
                    end
                end)
                newHum.WalkSpeed = Misc.moveSpeed
            end
        end)

        Misc.applySpeed()
        Core.debugLog("Move speed ON:", Misc.moveSpeed, "restore=", Misc.originalMoveSpeed or "unchanged")
    end

    function Misc.stopSpeed()
        if Misc.moveSpeedConn then Misc.moveSpeedConn:Disconnect(); Misc.moveSpeedConn = nil end
        if Misc.moveSpeedCharConn then Misc.moveSpeedCharConn:Disconnect(); Misc.moveSpeedCharConn = nil end

        local hum = Misc.getHumanoid()
        if hum and Misc.originalMoveSpeed ~= nil then
            hum.WalkSpeed = Misc.originalMoveSpeed
        end
        Core.debugLog("Move speed OFF - restored to", Misc.originalMoveSpeed or "unchanged")
        Misc.originalMoveSpeed = nil
    end
end
