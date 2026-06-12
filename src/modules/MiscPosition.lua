return function(HS, S)
    local Misc = HS.Misc or {}
    HS.Misc = Misc

    local Core = HS.Core

    function Misc.saveCurrentPosition()
        local root = Core.getRoot()
        if not root then Core.debugLog("Unable to save position; HumanoidRootPart missing"); return end
        Misc.savedPositionCFrame = root.CFrame
        Core.debugLog("Saved position", Misc.savedPositionCFrame)
    end

    function Misc.teleportToSavedPosition()
        if not Misc.savedPositionCFrame then Core.debugLog("No saved position to teleport to"); return end
        if Core.teleportWorld(Misc.savedPositionCFrame, "saved position") then
            Core.debugLog("Teleported to saved position")
        end
    end

    function Misc.copyCurrentPosition()
        local root = Core.getRoot()
        if not root then Core.debugLog("Unable to copy position; HumanoidRootPart missing"); return end
        local text = tostring(root.CFrame)
        if setclipboard then
            pcall(setclipboard, text)
            Core.debugLog("Copied position to clipboard", text)
        else
            Core.debugLog("Clipboard API unavailable; position =", text)
        end
    end
end
