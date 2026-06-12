return function(HS, S)
    local Flags = HS.Flags or {}
    HS.Flags = Flags

    local Core = HS.Core

    Flags.debugCircles = {}
    Flags.captureConnection = nil

    Core.FLAG_TARGETS = Core.FLAG_TARGETS or {
        {pos = Vector3.new(20, 0, 70), height = 254},
        {pos = Vector3.new(711, 0, 475), height = 213},
        {pos = Vector3.new(437, 0, -251), height = 285},
        {pos = Vector3.new(635, 0, 150), height = 259},
        {pos = Vector3.new(624, 0, -98), height = 478},
    }

    function Flags.getExpectedHeightFromPosition(flagPos)
        local closestHeight = nil
        local closestDist = math.huge

        for _, data in ipairs(Core.FLAG_TARGETS) do
            local dx = flagPos.X - data.pos.X
            local dz = flagPos.Z - data.pos.Z
            local dist = dx * dx + dz * dz

            if dist < closestDist then
                closestDist = dist
                closestHeight = data.height
            end
        end

        return closestHeight
    end

    function Flags.getFlagInfo(flagModel)
        local flag = flagModel:FindFirstChild("Flag")
        if not flag then return nil end

        local base = flagModel:FindFirstChild("Base")
        if not base then return nil end

        local flagPos
        if flag:IsA("BasePart") then
            flagPos = flag.Position
        elseif flag:IsA("Model") then
            flagPos = flag:GetPivot().Position
        else
            return nil
        end

        local ownerText = ""
        local billboardGui = flag:FindFirstChildOfClass("BillboardGui", true)

        if billboardGui then
            local frame = billboardGui:FindFirstChild("Frame")
            if frame then
                local tl = frame:FindFirstChild("TextLabelBottom")
                if tl and tl:IsA("TextLabel") then
                    ownerText = tl.Text
                end
            end
        end

        return {
            flagModel = flagModel,
            flag = flag,
            base = base,
            position = flagPos,
            baseHeight = base.Size.Y / 2,
            owner = ownerText,
        }
    end

    function Flags.createDebugCircle(position, radius, color, flagIndex)
        local part = Instance.new("Part")
        part.Shape = Enum.PartType.Cylinder
        part.Size = Vector3.new(0.2, radius * 2, radius * 2)
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Color = color
        part.Transparency = 0.5
        part.Name = "DebugCircle_" .. tostring(flagIndex or "temp")
        part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
        part.Parent = workspace
        return part
    end

    function Flags.clearDebugCircles()
        for _, circle in ipairs(Flags.debugCircles) do
            if circle and circle.Parent then
                circle:Destroy()
            end
        end

        Flags.debugCircles = {}
    end

    function Flags.isPlayerNearFlag(flagPos, radius, flagIndex)
            if Core.state.debug_mode == true then
            local circle = Flags.createDebugCircle(flagPos, radius, Color3.fromRGB(0, 170, 255), flagIndex)
            table.insert(Flags.debugCircles, circle)
        end

        for _, plr in ipairs(S.Players:GetPlayers()) do
            if plr ~= Core.player then
                local char = plr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")

                if hrp then
                    local dist = (hrp.Position - flagPos).Magnitude

                    if dist <= radius then
                        Core.debugLog("Player", plr.Name, "near flag at distance", math.floor(dist))

                        if Core.state.debug_mode == true and Flags.debugCircles[#Flags.debugCircles] then
                            Flags.debugCircles[#Flags.debugCircles].Color = Color3.fromRGB(255, 0, 0)
                        end

                        return true
                    end
                end
            end
        end

        return false
    end

    function Flags.startCaptureFlags()
        if Flags.captureConnection then
            Flags.captureConnection:Disconnect()
            Flags.captureConnection = nil
        end

        task.spawn(function()
            if not Core.alive or not Core.state.claim_flags then return end

            task.spawn(function()
                local wasDebug = Core.state.debug_mode
                local wasClaiming = Core.state.claim_flags

                while Core.alive and Core.state.claim_flags do
                    if (wasDebug and Core.state.debug_mode ~= true) or (wasClaiming and not Core.state.claim_flags) then
                        Flags.clearDebugCircles()
                    end

                    wasDebug = Core.state.debug_mode
                    wasClaiming = Core.state.claim_flags

                    task.wait(0.1)
                end

                Flags.clearDebugCircles()
            end)

            local root = Core.getRoot()
            if not root then
                Core.debugLog("Cannot capture flags: no character")
                return
            end

            local playerName = Core.player.Name
            local reCheckDelay = 15

            Core.debugLog("Flag capture loop started")

            while Core.alive and Core.state.claim_flags do
                Flags.clearDebugCircles()

                local flagsFolder = workspace:FindFirstChild("Gameplay") and workspace.Gameplay:FindFirstChild("Flags")
                if not flagsFolder then
                    Core.debugLog("Flags folder not found")
                    break
                end

                repeat
                    task.wait()
                until #flagsFolder:GetChildren() >= 5 or not Core.state.claim_flags

                if not Core.state.claim_flags then break end

                local flags = flagsFolder:GetChildren()
                local capturedCount = 0
                local totalFlags = #flags

                Core.debugLog("\n=== FLAG CHECK CYCLE ===")
                Core.debugLog("Checking", totalFlags, "flags...")

                for index, flagModel in ipairs(flags) do
                    if not Core.alive or not Core.state.claim_flags then
                        Core.debugLog("Flag capture interrupted")
                        break
                    end

                    local flagInfo = Flags.getFlagInfo(flagModel)
                    if not flagInfo then
                        continue
                    end

                    local expectedHeight = Flags.getExpectedHeightFromPosition(flagInfo.position)

                    if flagInfo.owner == playerName then
                        capturedCount += 1
                        continue
                    end

                    Core.debugLog(
                        "Flag", index,
                        "not owned (owner:", flagInfo.owner .. ")",
                        "expected height:", tostring(expectedHeight),
                        "- capturing..."
                    )

                    local baseBottomPos = flagInfo.base.Position - Vector3.new(0, flagInfo.base.Size.Y / 2, 0)

                    if Core.state.flag_avoid and Flags.isPlayerNearFlag(baseBottomPos, 20, index) then
                        Core.debugLog("Flag", index, "skipped - players nearby")
                        continue
                    end

                    root = Core.getRoot()
                    if not root then break end

                    if not Core.waitForPriority("flags", function()
                        return Core.alive and Core.state.claim_flags
                    end) then
                        break
                    end
                    if not Core.claimPriority("flags") then
                        task.wait(1)
                        continue
                    end

                    Core.debugLog(
                        "Flag", index,
                        "- teleporting to",
                        math.floor(flagInfo.position.X),
                        math.floor(flagInfo.position.Y),
                        math.floor(flagInfo.position.Z)
                    )
                    Core.setCurrentAction("Capturing Flags", 4)

                    if not Core.teleportWorld(CFrame.new(flagInfo.position + Vector3.new(0, 10, 0)), "flag capture", function()
                        return Core.alive and Core.state.claim_flags
                    end) then
                        Core.releasePriority("flags")
                        break
                    end
                    task.wait(0.5)

                    local startTime = tick()
                    local heightReached = false
                    local ownershipChanged = false

                    while tick() - startTime < 30 do
                        if not Core.alive or not Core.state.claim_flags then break end
                        Core.setCurrentAction("Capturing Flags", 2)

                        local currentRoot = Core.getRoot()
                        if not currentRoot then break end

                        local flagInfo2 = Flags.getFlagInfo(flagModel)
                        if not flagInfo2 then break end

                        if not ownershipChanged then
                            Core.debugLog("Flag", index, "ownership check - owner:", flagInfo2.owner, "player:", playerName)

                            if flagInfo2.owner == playerName then
                                ownershipChanged = true
                                Core.debugLog("Flag", index, "- OWNERSHIP CONFIRMED, now waiting for height...")
                            end
                        end

                        if ownershipChanged and not heightReached then
                            expectedHeight = Flags.getExpectedHeightFromPosition(flagInfo2.position)

                            if expectedHeight then
                                local flag2 = flagInfo2.flag
                                local flagY

                                if flag2:IsA("BasePart") then
                                    flagY = flag2.Position.Y
                                elseif flag2:IsA("Model") then
                                    local part = flag2.PrimaryPart or flag2:FindFirstChildWhichIsA("BasePart")
                                    flagY = part and part.Position.Y or flag2:GetPivot().Position.Y
                                end

                                if flagY then
                                    local heightDiff = math.abs(flagY - expectedHeight)

                                    Core.debugLog(
                                        "Flag", index,
                                        "height check - current:", flagY,
                                        "expected:", expectedHeight,
                                        "diff:", heightDiff
                                    )

                                    if heightDiff <= (Core.FLAG_HEIGHT_TOLERANCE or 0.35) then
                                        heightReached = true
                                        Core.debugLog("Flag", index, "- HEIGHT REACHED")
                                    end
                                end
                            else
                                heightReached = true
                            end
                        end

                        if heightReached and ownershipChanged then
                            Core.debugLog("Flag", index, "- CAPTURED AND HEIGHT REACHED, moving to next...")
                            break
                        end

                        task.wait(0.2)
                    end

                    if heightReached and ownershipChanged then
                        capturedCount += 1
                        Core.debugLog("Flag", index, "captured successfully")
                        task.wait(1)
                    else
                        Core.debugLog(
                            "Flag", index,
                            "capture failed or timed out - heightReached:",
                            heightReached,
                            "ownershipChanged:",
                            ownershipChanged
                        )
                    end
                    Core.releasePriority("flags")
                end

                Core.releasePriority("flags")
                Core.clearCurrentAction("Capturing Flags")

                Core.debugLog("Flag check complete -", capturedCount, "/", totalFlags, "owned")

                if capturedCount == totalFlags then
                    Core.debugLog("All flags captured! Rechecking in", reCheckDelay, "seconds...")
                else
                    Core.debugLog("Some flags uncaptured. Rechecking in", reCheckDelay, "seconds...")
                end

                task.wait(reCheckDelay)
            end

            Core.debugLog("Flag capture loop stopped")
            Core.clearCurrentAction("Capturing Flags")
            Flags.clearDebugCircles()
        end)
    end
end
