return function(HS, S)
    local Misc = HS.Misc or {}
    HS.Misc = Misc

    local Core = HS.Core

    function Misc.antiAfkPulse(reason)
        local currentCamera = workspace.CurrentCamera
        if not currentCamera then return end
        local saved = currentCamera.CFrame
        currentCamera.CFrame = saved * CFrame.Angles(0, math.rad(1), 0)
        task.wait(0.1)
        if currentCamera.Parent then
            currentCamera.CFrame = saved
        end
        Core.debugLog("Anti AFK camera pulse", reason or "")
    end

    function Misc.startAntiAfk()
        Core.loopWhile("anti_afk", Misc.ANTI_AFK_DELAY, function()
            Misc.antiAfkPulse("background")
        end)
    end

    Core.player.Idled:Connect(function()
        if not Core.state.anti_afk then return end
        Core.debugLog("Player idled; firing anti AFK burst")
        Misc.antiAfkPulse("idled-1")
        task.wait(1)
        Misc.antiAfkPulse("idled-2")
    end)
end
