return function(HS, S)
    local ElementZonePull = HS.ElementZonePull or {}
    HS.ElementZonePull = ElementZonePull

    local Core = HS.Core

    ElementZonePull.enabled = {}
    ElementZonePull.connections = {}
    ElementZonePull.hitThreads = {}

    ElementZonePull.HIT_DELAY = 0.06
    ElementZonePull.TP_OFFSET = CFrame.new(0, 0, -4)

    ElementZonePull.ELEMENTS = {
        Fire = true,
        Water = true,
        Earth = true,
        Plasma = true,
    }

    ElementZonePull.TIERS = {
        Starter = {
            statePrefix = "starter",
            areaName = nil,
        },
        Advanced = {
            statePrefix = "advanced",
            areaName = "Advanced%sArea",
        },
        Master = {
            statePrefix = "master",
            areaName = "Master%sArea",
        },
        Grandmaster = {
            statePrefix = "grandmaster",
            areaName = "Grandmaster%sArea",
        },
    }
    ElementZonePull.NOCLIP_ELEMENTS = {Fire=true, Water=true, Earth=true}
    ElementZonePull.noclipConnection = nil
    ElementZonePull.noclipOriginal = {}
    ElementZonePull.noclipCharacter = nil

    function ElementZonePull.getKey(element, tier)
        return string.lower(element) .. "_" .. string.lower(tier)
    end

    function ElementZonePull.getStateKey(element, tier)
        return string.lower(element) .. "_" .. string.lower(tier) .. "_pull"
    end

    function ElementZonePull.isPausedByBoss()
        return HS.Farming
            and HS.Farming.isBossFarmActive
            and HS.Farming.isBossFarmActive()
    end

    function ElementZonePull.canRunState(stateKey)
        if ElementZonePull.isPausedByBoss() then return false end
        return not Core.state.auto_cycle or Core.activeCycleKey == stateKey
    end

    function ElementZonePull.isNoclipEligible(element, tier)
        return ElementZonePull.NOCLIP_ELEMENTS[element] == true
            and ElementZonePull.TIERS[tier] ~= nil
    end

    function ElementZonePull.restoreElementNoclipParts()
        for part, canCollide in pairs(ElementZonePull.noclipOriginal) do
            if part and part.Parent then
                part.CanCollide = canCollide
            end
        end
        ElementZonePull.noclipOriginal = {}
        ElementZonePull.noclipCharacter = nil
    end

    function ElementZonePull.applyElementNoclip()
        local character = Core.player.Character
        if not character then return end
        if ElementZonePull.noclipCharacter ~= character then
            ElementZonePull.restoreElementNoclipParts()
            ElementZonePull.noclipCharacter = character
        end

        for _, obj in ipairs(character:GetDescendants()) do
            if obj:IsA("BasePart") then
                if ElementZonePull.noclipOriginal[obj] == nil then
                    ElementZonePull.noclipOriginal[obj] = obj.CanCollide
                end
                obj.CanCollide = false
            end
        end
    end

    function ElementZonePull.hasActiveElementNoclipFarm()
        if Core.isWorldTeleportBlocked() or ElementZonePull.isPausedByBoss() then return false end
        for key, enabled in pairs(ElementZonePull.enabled) do
            if enabled then
                local elementKey, tierKey = key:match("^(%a+)_(%a+)$")
                local element = elementKey and elementKey:gsub("^%l", string.upper)
                local tier = tierKey and tierKey:gsub("^%l", string.upper)
                local stateKey = element and tier and ElementZonePull.getStateKey(element, tier)
                if element and tier
                    and ElementZonePull.isNoclipEligible(element, tier)
                    and Core.state[stateKey]
                    and ElementZonePull.canRunState(stateKey) then
                    return true
                end
            end
        end
        return false
    end

    function ElementZonePull.stopElementNoclip()
        if ElementZonePull.noclipConnection then
            ElementZonePull.noclipConnection:Disconnect()
            ElementZonePull.noclipConnection = nil
        end
        ElementZonePull.restoreElementNoclipParts()
    end

    function ElementZonePull.setElementNoclip(enabled)
        if not enabled then
            ElementZonePull.stopElementNoclip()
            return
        end
        if Core.isWorldTeleportBlocked() or ElementZonePull.isPausedByBoss() then
            ElementZonePull.stopElementNoclip()
            return
        end
        if ElementZonePull.noclipConnection then
            ElementZonePull.applyElementNoclip()
            return
        end

        ElementZonePull.applyElementNoclip()
        ElementZonePull.noclipConnection = S.RunService.Stepped:Connect(function()
            if not Core.alive or not ElementZonePull.hasActiveElementNoclipFarm() then
                ElementZonePull.stopElementNoclip()
                return
            end
            ElementZonePull.applyElementNoclip()
        end)
    end

    function ElementZonePull.updateElementNoclip()
        ElementZonePull.setElementNoclip(ElementZonePull.hasActiveElementNoclipFarm())
    end

    function ElementZonePull.getBossName(element, tier)
        if tier == "Starter" then
            return element .. " Boss"
        end

        return tier .. " " .. element .. " Boss"
    end

    -- Per-element overrides: some "Starter" zones are actually inside a named RegionsLoaded area
    ElementZonePull.STARTER_OVERRIDES = {
        Plasma = "AdvancedPlasmaArea",  -- Plasma has no true starter zone, lives in Advanced
    }

    function ElementZonePull.getFolders(element, tier)
        -- Returns a list of folders (handles duplicate Important/X children)
        local folders = {}

        if tier == "Starter" then
            local override = ElementZonePull.STARTER_OVERRIDES[element]
            if override then
                local gameplay = workspace:FindFirstChild("Gameplay")
                local regionsLoaded = gameplay and gameplay:FindFirstChild("RegionsLoaded")
                local area = regionsLoaded and regionsLoaded:FindFirstChild(override)
                local important = area and area:FindFirstChild("Important")
                if important then
                    -- Collect ALL children named element (there can be duplicates e.g. Plasma)
                    for _, child in ipairs(important:GetChildren()) do
                        if child.Name == element then
                            table.insert(folders, child)
                        end
                    end
                end
                return folders
            end

            local gameplay = workspace:FindFirstChild("Gameplay")
            local map = gameplay and gameplay:FindFirstChild("Map")
            local zones = map and map:FindFirstChild("ElementZones")
            local elementZone = zones and zones:FindFirstChild(element)
            if not elementZone then return folders end
            local direct = elementZone:FindFirstChild(element)
            if direct then table.insert(folders, direct); return folders end
            local model = elementZone:FindFirstChild("Model")
            local sub = model and model:FindFirstChild(element)
            if sub then table.insert(folders, sub) end
            return folders
        end

        local gameplay = workspace:FindFirstChild("Gameplay")
        local regionsLoaded = gameplay and gameplay:FindFirstChild("RegionsLoaded")
        local tierData = ElementZonePull.TIERS[tier]
        local areaName = tierData and string.format(tierData.areaName, element)
        local area = regionsLoaded and areaName and regionsLoaded:FindFirstChild(areaName)
        local important = area and area:FindFirstChild("Important")
        if important then
            for _, child in ipairs(important:GetChildren()) do
                if child.Name == element then
                    table.insert(folders, child)
                end
            end
        end
        return folders
    end

    function ElementZonePull.getFolder(element, tier)
        -- Legacy single-folder wrapper for compatibility
        local folders = ElementZonePull.getFolders(element, tier)
        return folders[1] or nil
    end

    function ElementZonePull.getTargets(element, tier)
        local targets = {}
        local folders = ElementZonePull.getFolders(element, tier)
        if #folders == 0 then return targets end

        local bossName = ElementZonePull.getBossName(element, tier)

        for _, folder in ipairs(folders) do
            for _, mob in ipairs(folder:GetChildren()) do
                if mob:IsA("Model") then
                    local isBoss = mob.Name == bossName
                    local isMob =
                        mob.Name:find("Golem") or
                        mob.Name:find("Enemy") or
                        mob.Name:find("Mob") or
                        mob.Name:find(element)

                    if isBoss or isMob then
                        local hrp = mob:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            table.insert(targets, mob)
                        end
                    end
                end
            end
        end

        return targets
    end

    function ElementZonePull.start(element, tier)
        local key = ElementZonePull.getKey(element, tier)
        local stateKey = ElementZonePull.getStateKey(element, tier)

        if ElementZonePull.enabled[key] then return end
        ElementZonePull.enabled[key] = true
        if ElementZonePull.isNoclipEligible(element, tier) then
            ElementZonePull.setElementNoclip(true)
        end

        ElementZonePull.connections[key] = S.RunService.Heartbeat:Connect(function()
            if not Core.alive or not Core.state[stateKey] then
                ElementZonePull.stop(element, tier)
                return
            end
            ElementZonePull.updateElementNoclip()
            if not ElementZonePull.canRunState(stateKey) then return end

            local root = Core.getRoot()
            if not root then return end

            local baseCFrame = root.CFrame * ElementZonePull.TP_OFFSET

            local targets = ElementZonePull.getTargets(element, tier)

            for _, mob in ipairs(targets) do
                local hrp = mob:FindFirstChild("HumanoidRootPart")
                local lowerTorso = mob:FindFirstChild("LowerTorso")
                if hrp and lowerTorso then
                    hrp.CanCollide = false
                    -- Sever Root Motor6D so the server moving HRP doesn't drag the body with it
                    local rootMotor = lowerTorso:FindFirstChild("Root")
                    if rootMotor and rootMotor:IsA("Motor6D") then
                        rootMotor.Part0 = nil
                    end
                    lowerTorso.AssemblyLinearVelocity  = Vector3.zero
                    lowerTorso.AssemblyAngularVelocity = Vector3.zero
                    lowerTorso.CFrame = baseCFrame
                end
            end
        end)

        ElementZonePull.hitThreads[key] = task.spawn(function()
            Core.debugLog("Element pull hit loop started:", element, tier)

            while ElementZonePull.enabled[key] and Core.alive and Core.state[stateKey] do
                ElementZonePull.updateElementNoclip()
                if not ElementZonePull.canRunState(stateKey) then
                    task.wait(0.2)
                    continue
                end
                local remote = Core.getEquippedRemote()
                local targets = ElementZonePull.getTargets(element, tier)

                if remote and #targets > 0 then
                    pcall(function()
                        remote:FireServer(targets)
                    end)

                    for _, mob in ipairs(targets) do
                        pcall(function()
                            remote:FireServer({mob})
                        end)
                    end
                end

                task.wait(ElementZonePull.HIT_DELAY)
            end

            ElementZonePull.updateElementNoclip()
            Core.debugLog("Element pull hit loop stopped:", element, tier)
        end)

        Core.debugLog("Element pull started:", element, tier)
    end

    function ElementZonePull.stop(element, tier)
        local key = ElementZonePull.getKey(element, tier)

        ElementZonePull.enabled[key] = false

        if ElementZonePull.connections[key] then
            ElementZonePull.connections[key]:Disconnect()
            ElementZonePull.connections[key] = nil
        end

        -- Restore mob state when pull ends
        local targets = ElementZonePull.getTargets(element, tier)
        for _, mob in ipairs(targets) do
            local hrp = mob:FindFirstChild("HumanoidRootPart")
            local lowerTorso = mob:FindFirstChild("LowerTorso")
            if hrp then
                hrp.CanCollide = true
            end
            if lowerTorso then
                -- Restore the Root Motor6D connection to HRP
                local rootMotor = lowerTorso:FindFirstChild("Root")
                if rootMotor and rootMotor:IsA("Motor6D") then
                    rootMotor.Part0 = hrp
                end
            end
        end

        ElementZonePull.hitThreads[key] = nil
        ElementZonePull.updateElementNoclip()

        Core.debugLog("Element pull stopped:", element, tier)
    end
end
