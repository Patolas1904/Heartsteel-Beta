return function(HS, S)
    local AutoCycle = HS.AutoCycle or {}
    HS.AutoCycle = AutoCycle

    local Core = HS.Core

    AutoCycle.enabled = false
    AutoCycle.thread = nil
    AutoCycle.currentIndex = 1
    AutoCycle.currentKey = nil
    AutoCycle.activeKey = nil
    AutoCycle.dwellStartTime = nil
    AutoCycle.zoneStartTime = nil
    AutoCycle.lastTeleportAt = 0
    AutoCycle.waitingForDungeon = false
    AutoCycle.wasPausedByDungeon = false
    AutoCycle.lastTeleportFailed = false
    AutoCycle.restartRequested = false

    AutoCycle.POSITIONS = {
        fire_starter_pull = CFrame.new(
            526.115601, 175.945877, 505.875793,
            0.94769603, 0, -0.319174379,
            0, 1, 0,
            0.319174379, 0, 0.94769603
        ),
        water_starter_pull = CFrame.new(
            72.1237488, 267.804565, -541.859924,
            0.271793306, 0, 0.962355673,
            0, 1, 0,
            -0.962355673, 0, 0.271793306
        ),
        earth_starter_pull = CFrame.new(
            769.805054, 195.588165, -295.802734,
            0.0650548935, 0, -0.997881711,
            0, 1, 0,
            0.997881711, 0, 0.0650548935
        ),
        plasma_starter_pull = Vector3.new(2063.61523, -9.85239124, 172.534424),

        fire_advanced_pull = CFrame.new(
            -135.996277, 22.1324768, 721.547302,
            0.946418405, 0, -0.322943032,
            0, 1, 0,
            0.322943032, 0, 0.946418405
        ),
        water_advanced_pull = CFrame.new(
            -189.005905, 5.63680744, -792.825195,
            0.203112066, 0, 0.979155481,
            0, 1, 0,
            -0.979155481, 0, 0.203112066
        ),
        earth_advanced_pull = CFrame.new(
            1272.72742, -33.7016716, -913.815247,
            0.0639923289, 0, -0.997950375,
            0, 1, 0,
            0.997950375, 0, 0.0639923289
        ),
        plasma_advanced_pull = Vector3.new(2686.28003, 85.4065475, 9.84980392),

        fire_master_pull = CFrame.new(
            -788.625977, 77.0564651, 743.406006,
            -0.999372423, 0, -0.0354226939,
            0, 1, 0,
            0.0354226939, 0, -0.999372423
        ),
        water_master_pull = CFrame.new(
            -740.257629, 75.3468704, -1000.51788,
            -0.074595876, 0, 0.99721384,
            0, 1, 0,
            -0.99721384, 0, -0.074595876
        ),
        earth_master_pull = CFrame.new(
            1774.51025, -3.68670678, -981.203613,
            0.0640098229, 0, -0.997949243,
            0, 1, 0,
            0.997949243, 0, 0.0640098229
        ),
        plasma_master_pull = Vector3.new(2925.77148, 109.324539, 1032.02002),

        fire_grandmaster_pull = CFrame.new(
            -1492.47449, 75.8575592, 781.375732,
            -0.163170993, 0, 0.986597776,
            0, 1, 0,
            -0.986597776, 0, -0.163170993
        ),
        water_grandmaster_pull = CFrame.new(
            -788.625977, 126.50853, -1579.46606,
            0.999619305, 0, 0.0275901537,
            0, 1, 0,
            -0.0275901537, 0, 0.999619305
        ),
        earth_grandmaster_pull = CFrame.new(
            1919.70081, -3.68905091, -1462.81274,
            0.0640271902, 0, -0.99794817,
            0, 1, 0,
            0.99794817, 0, 0.0640271902
        ),
        plasma_grandmaster_pull = Vector3.new(3780.17969, 119.138786, 1016.48413),
    }

    AutoCycle.SAFETY_PLATFORM_KEYS = {
        fire_starter_pull = true,
        water_starter_pull = true,
        earth_starter_pull = true,
        fire_advanced_pull = true,
        water_advanced_pull = true,
        earth_advanced_pull = true,
        fire_master_pull = true,
        water_master_pull = true,
        earth_master_pull = true,
        fire_grandmaster_pull = true,
        water_grandmaster_pull = true,
        earth_grandmaster_pull = true,
    }

    AutoCycle.ORDER = {
        "fire_starter_pull",
        "water_starter_pull",
        "earth_starter_pull",
        "plasma_starter_pull",

        "fire_advanced_pull",
        "water_advanced_pull",
        "earth_advanced_pull",
        "plasma_advanced_pull",

        "fire_master_pull",
        "water_master_pull",
        "earth_master_pull",
        "plasma_master_pull",

        "fire_grandmaster_pull",
        "water_grandmaster_pull",
        "earth_grandmaster_pull",
        "plasma_grandmaster_pull",
    }

    function AutoCycle.getEnabledZones()
        local zones = {}

        for _, key in ipairs(AutoCycle.ORDER) do
            if Core.state[key] and AutoCycle.POSITIONS[key] then
                table.insert(zones, key)
            end
        end

        return zones
    end

    function AutoCycle.isPausedByBoss()
        return HS.Farming
            and HS.Farming.isBossFarmActive
            and HS.Farming.isBossFarmActive()
    end

    function AutoCycle.getElementTierFromKey(key)
        local element, tier = tostring(key or ""):match("^(%a+)_(%a+)_pull$")
        if element and tier then
            element = element:gsub("^%l", string.upper)
            tier = tier:gsub("^%l", string.upper)
        end
        return element, tier
    end

    function AutoCycle.clearAutoCyclePullState(reason)
        local Pull = HS.ElementZonePull
        if not Pull or type(Pull.stop) ~= "function" then return false end

        local pullKeys = {}
        local function addPullKey(key)
            if type(key) == "string" and key ~= "" then
                pullKeys[key] = true
            end
        end

        for key, enabled in pairs(Pull.enabled or {}) do
            if enabled then addPullKey(key) end
        end
        for key, connection in pairs(Pull.connections or {}) do
            if connection then addPullKey(key) end
        end
        for key, thread in pairs(Pull.hitThreads or {}) do
            if thread then addPullKey(key) end
        end

        if Core.activeCycleKey and AutoCycle.POSITIONS[Core.activeCycleKey] and type(Pull.getKey) == "function" then
            local element, tier = AutoCycle.getElementTierFromKey(Core.activeCycleKey)
            if element and tier then
                addPullKey(Pull.getKey(element, tier))
            end
        end

        local stopped = false
        for pullKey in pairs(pullKeys) do
            local elementKey, tierKey = pullKey:match("^(%a+)_(%a+)$")
            local element = elementKey and elementKey:gsub("^%l", string.upper)
            local tier = tierKey and tierKey:gsub("^%l", string.upper)
            local stateKey = element and tier and type(Pull.getStateKey) == "function" and Pull.getStateKey(element, tier)
            if stateKey and AutoCycle.POSITIONS[stateKey] then
                Pull.stop(element, tier)
                stopped = true
            end
        end

        if stopped and reason == "after dungeon" then
            Core.debugLog("AutoCycle cleared stale pull state after dungeon")
        end
        return stopped
    end

    function AutoCycle.resetRuntimeState(reason)
        AutoCycle.clearAutoCyclePullState(reason)
        AutoCycle.currentIndex = 1
        AutoCycle.currentKey = nil
        AutoCycle.activeKey = nil
        AutoCycle.dwellStartTime = nil
        AutoCycle.zoneStartTime = nil
        AutoCycle.lastTeleportAt = 0
        AutoCycle.waitingForDungeon = false
        AutoCycle.wasPausedByDungeon = false
        AutoCycle.lastTeleportFailed = false
        AutoCycle.restartRequested = reason == "after dungeon"
        Core.activeCycleKey = nil
        Core.releasePriority("auto_cycle")
        Core.clearCurrentAction("Auto Cycle Farming")
        if HS.ElementZonePull and HS.ElementZonePull.updateElementNoclip then
            HS.ElementZonePull.updateElementNoclip()
        end
        Core.debugLog("AutoCycle reset runtime state", reason or "runtime")
    end

    function AutoCycle.waitForDungeonPause(reason)
        if not Core.isWorldTeleportBlocked() then return false end
        if not AutoCycle.wasPausedByDungeon then
            Core.debugLog("AutoCycle paused by dungeon")
        end
        AutoCycle.wasPausedByDungeon = true
        AutoCycle.waitingForDungeon = true

        while Core.alive and Core.state.auto_cycle and AutoCycle.enabled and Core.isWorldTeleportBlocked() do
            task.wait(1)
        end

        AutoCycle.waitingForDungeon = false
        if not (Core.alive and Core.state.auto_cycle and AutoCycle.enabled) then return false end
        if AutoCycle.wasPausedByDungeon then
            AutoCycle.wasPausedByDungeon = false
            AutoCycle.resetRuntimeState(reason or "after dungeon")
            Core.debugLog("AutoCycle retrying cycle after dungeon")
            task.wait(0.2)
            return true
        end
        return false
    end

    function AutoCycle.teleportToKey(key)
        local pos = AutoCycle.POSITIONS[key]
        local targetCf = pos and Core.asCFrame(pos)
        local root = Core.getRoot()
        if not targetCf or not root then return end
        local element, tier = AutoCycle.getElementTierFromKey(key)
        if Core.isWorldTeleportBlocked() then
            local resetAfterDungeon = AutoCycle.waitForDungeonPause("after dungeon")
            if not (Core.alive and Core.state.auto_cycle and AutoCycle.enabled) then return false end
            if resetAfterDungeon then return false end
        end
        if not Core.waitForPriority("auto_cycle", function()
            return Core.alive and Core.state.auto_cycle and AutoCycle.enabled
        end) then return end
        if not Core.claimPriority("auto_cycle") then return end
       
        local activePullKey = element and tier and HS.ElementZonePull.getKey(element, tier)
        local enabledKeys = {}
        for otherKey, enabled in pairs(HS.ElementZonePull.enabled) do
            if enabled and otherKey ~= activePullKey then
                enabledKeys[#enabledKeys + 1] = otherKey
            end
        end
        for _, otherKey in ipairs(enabledKeys) do
            local e, t = otherKey:match("^(%a+)_(%a+)$")
            if e and t then
                e = e:gsub("^%l", string.upper)
                t = t:gsub("^%l", string.upper)
                HS.ElementZonePull.stop(e, t)
            end
        end

        Core.activeCycleKey = key
        AutoCycle.currentKey = key
        AutoCycle.activeKey = key

        if AutoCycle.SAFETY_PLATFORM_KEYS[key] then
            Core.ensureElementSafetyPlatform(targetCf)
            if HS.ElementZonePull and HS.ElementZonePull.setElementNoclip then
                HS.ElementZonePull.setElementNoclip(true)
            end
        end

        if not Core.teleportWorld(targetCf, "auto cycle", function()
            return Core.alive and Core.state.auto_cycle and AutoCycle.enabled
        end) then
            AutoCycle.lastTeleportFailed = true
            if HS.ElementZonePull and HS.ElementZonePull.updateElementNoclip then
                HS.ElementZonePull.updateElementNoclip()
            end
            return false
        end

        AutoCycle.lastTeleportAt = os.clock()
        AutoCycle.lastTeleportFailed = false

        if element and tier then
            HS.ElementZonePull.start(element, tier)
        end

        Core.debugLog("Auto Cycle TP:", key, targetCf.Position)
        return true
    end

    function AutoCycle.start()
        if AutoCycle.enabled then return end
        AutoCycle.enabled = true

        AutoCycle.thread = task.spawn(function()
            Core.debugLog("Auto Cycle started")

            AutoCycle.currentIndex = AutoCycle.currentIndex or 1

            while Core.alive and Core.state.auto_cycle and AutoCycle.enabled do
                while Core.alive and Core.state.auto_cycle and AutoCycle.enabled and AutoCycle.isPausedByBoss() do
                    Core.clearCurrentAction("Auto Cycle Farming")
                    if Core.isWorldTeleportBlocked() then
                        AutoCycle.waitForDungeonPause("after dungeon")
                    else
                        task.wait(0.5)
                    end
                end
                if not (Core.alive and Core.state.auto_cycle and AutoCycle.enabled) then break end

                -- Block teleport if dungeon is active — wait here until it ends
                if Core.isWorldTeleportBlocked() then
                    AutoCycle.waitForDungeonPause("after dungeon")
                    AutoCycle.restartRequested = false
                end
                if not (Core.alive and Core.state.auto_cycle and AutoCycle.enabled) then break end
                AutoCycle.restartRequested = false

                local zones = AutoCycle.getEnabledZones()

                if #zones == 0 then
                    Core.debugLog("Auto Cycle: no enabled zones")
                    task.wait(1)
                    continue
                end

                if (AutoCycle.currentIndex or 1) > #zones then
                    AutoCycle.currentIndex = 1
                end

                local key = zones[AutoCycle.currentIndex or 1]
                if AutoCycle.teleportToKey(key) == false and AutoCycle.restartRequested then
                    AutoCycle.restartRequested = false
                    continue
                end
                
                local element, tier = AutoCycle.getElementTierFromKey(key)

                local startTime = os.clock()
                AutoCycle.zoneStartTime = startTime
                AutoCycle.dwellStartTime = startTime
                local MIN_DWELL_TIME = 3  -- always stay at least 3s so the region can load
                local MAX_ZONE_TIME = 120 -- max seconds per zone before moving on

                -- Wait minimum dwell before checking targets (prevents spin-freeze on unloaded regions)
                while Core.alive and Core.state.auto_cycle and AutoCycle.enabled do
                    if os.clock() - startTime >= MIN_DWELL_TIME then break end
                    task.wait(0.5)
                end

                -- Stay in zone until all mobs are dead or timeout is reached
                local restartAfterDungeon = false
                while Core.alive and Core.state.auto_cycle and AutoCycle.enabled do
                    if AutoCycle.isPausedByBoss() then
                        Core.clearCurrentAction("Auto Cycle Farming")
                        task.wait(0.5)
                        continue
                    end

                    if Core.priorityOwner ~= "auto_cycle" then
                        if element and tier then HS.ElementZonePull.stop(element, tier) end
                        Core.debugLog("Auto Cycle paused by priority:", Core.priorityOwner or "unknown")
                        if not Core.waitForPriority("auto_cycle", function()
                            return Core.alive and Core.state.auto_cycle and AutoCycle.enabled
                        end) then break end
                        if not Core.claimPriority("auto_cycle") then break end
                        AutoCycle.teleportToKey(key)
                        startTime = os.clock()
                        AutoCycle.zoneStartTime = startTime
                        AutoCycle.dwellStartTime = startTime
                    end

                    -- Pause mid-zone if a dungeon becomes active
                    if Core.isWorldTeleportBlocked() then
                        restartAfterDungeon = AutoCycle.waitForDungeonPause("after dungeon")
                        if restartAfterDungeon then break end
                        startTime = os.clock()
                        AutoCycle.zoneStartTime = startTime
                        AutoCycle.dwellStartTime = startTime
                        task.wait(MIN_DWELL_TIME)
                    end

                    local targets = {}

                    if element and tier then
                        targets = HS.ElementZonePull.getTargets(element, tier)
                    end

                    if #targets > 0 then
                        Core.setCurrentAction("Auto Cycle Farming", 2)
                    end

                    if HS.UI and HS.UI.autoCycleTimerLabel and HS.UI.autoCycleTimerLabel.Parent then
                        local elapsed = math.floor(os.clock() - startTime)
                        HS.UI.autoCycleTimerLabel.Text =
                            key .. " - mobs: " .. tostring(#targets) .. " (" .. elapsed .. "s)"
                    end

                    if #targets <= 0 then
                        Core.debugLog("Zone cleared → next:", key)
                        break
                    end

                    if os.clock() - startTime >= MAX_ZONE_TIME then
                        Core.debugLog("Timeout → next:", key)
                        break
                    end

                    task.wait(0.5)
                end

                -- Small buffer between zones so stop() can finish cleanly before next start()
                Core.releasePriority("auto_cycle")
                task.wait(0.5)

                if restartAfterDungeon then
                    AutoCycle.restartRequested = false
                    continue
                end

                AutoCycle.currentIndex = (AutoCycle.currentIndex or 1) + 1
            end

            Core.debugLog("Auto Cycle stopped")
            AutoCycle.enabled = false
            AutoCycle.thread = nil
            Core.clearCurrentAction("Auto Cycle Farming")
            if HS.ElementZonePull and HS.ElementZonePull.updateElementNoclip then
                HS.ElementZonePull.updateElementNoclip()
            end
        end)
    end

    function AutoCycle.stop()
        AutoCycle.enabled = false
        AutoCycle.thread = nil
        Core.activeCycleKey = nil
        AutoCycle.currentIndex = 1
        AutoCycle.currentKey = nil
        AutoCycle.activeKey = nil
        AutoCycle.dwellStartTime = nil
        AutoCycle.zoneStartTime = nil
        AutoCycle.waitingForDungeon = false
        AutoCycle.wasPausedByDungeon = false
        AutoCycle.lastTeleportFailed = false
        AutoCycle.restartRequested = false
        if HS.ElementZonePull and HS.ElementZonePull.updateElementNoclip then
            HS.ElementZonePull.updateElementNoclip()
        end
        Core.clearCurrentAction("Auto Cycle Farming")
        Core.debugLog("Auto Cycle stopped")
    end
end
