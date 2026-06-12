return function(HS, S)
    local Dungeon = HS.Dungeon or {}
    HS.Dungeon = Dungeon
    local Core    = HS.Core

    -- ── Dungeon timer state ─────────────────────────────────────
    Dungeon.timerLabel              = nil
    Dungeon.timerSource             = nil
    Dungeon.timerSourceConnection   = nil
    Dungeon.timerWatcherThread      = nil
    Dungeon.timerCachedText         = "0:00"
    Dungeon.timerEndsAt             = nil
    Dungeon.queueHandled            = false
    Dungeon.queueDeferredInside     = false
    Dungeon.wasInside               = false
    Dungeon.runActive               = false
    Dungeon.runProtectionActive     = false
    Dungeon.lastDungeonActivityAt   = 0
    Dungeon.runProtectionStartedAt  = 0
    Dungeon.runProtectionHeldLogged = false
    Dungeon.runEnding               = false
    Dungeon.runEndToken             = 0
    Dungeon.autoStartCooldownUntil  = 0

    -- ── Dungeon hover/hit state ─────────────────────────────────
    Dungeon.HEIGHT          = 7
    Dungeon.SMOOTHNESS      = 0.15
    Dungeon.SWITCH_BUFFER   = 8
    Dungeon.HIT_DELAY       = 0.25
    Dungeon.currentTarget   = nil
    Dungeon.hoverConnection = nil
    Dungeon.hitThread       = nil

    -- ── Egg incubator state ─────────────────────────────────────
    Dungeon.incubatorSlots      = {}
    Dungeon.eggRewardPending    = nil
    Dungeon.MAX_INCUBATOR_SLOTS = 6
    Dungeon.FORCE_CLAIM_INTERVAL = 120
    Dungeon.lastForceClaimAttempt = Dungeon.lastForceClaimAttempt or {}

    -- ── Chest state ─────────────────────────────────────────────
    Dungeon.chestThread = nil
    Dungeon.regionLoadedHookInstalled = false
    Dungeon.forceEndedUntil = 0
    Dungeon.START_REMOTE_DELAY = 2
    Dungeon.RUN_PROTECTION_TIMEOUT = 20 * 60
    Dungeon.upgradeShopInfo = nil
    Dungeon.upgradeShopInfoLoaded = false
    Dungeon.lastUpgradeBuy = {}

    -- ── Difficulty map ──────────────────────────────────────────
    Dungeon.DIFFICULTY_MAP = {Easy=1, Medium=2, Hard=3, Impossible=4}

    Dungeon.EGG_RANKS = {
        ["moon egg"]=1, ["double moon egg"]=2,
        ["triple moon egg"]=3, ["sun egg"]=4,
    }

    Dungeon.VALID_SPAWNERS = {
        GreenEnemySpawner=true,  BlueEnemySpawner=true,
        RedEnemySpawner=true,    PurpleEnemySpawner=true,
        BlueBossEnemySpawner=true, GreenBossEnemySpawner=true,
        RedBossEnemySpawner=true,  PurpleBossEnemySpawner=true,
    }

    Dungeon.VALID_TARGETS = {
        ["Green Bot"]=true,  ["Blue Bot"]=true,
        ["Red Bot"]=true,    ["Purple Bot"]=true,
        ["Green Boss"]=true, ["Blue Boss"]=true,
        ["Red Boss"]=true,   ["Purple Boss"]=true,
    }

    Dungeon.CHEST_FOLDERS = {"Gold", "Shiny", "Rainbow", "Void"}
    Dungeon.PLAYER_RELATIVE_TO_CHEST = CFrame.new(
        -0.260986328, -9.48681641, -26.267334,
        -0.994236231, 0, 0.107211649,
        0, 1, 0,
        -0.107211649, 0, -0.994236231
    )
    Dungeon.CAMERA_RELATIVE_TO_CHEST = CFrame.new(
        -1.63598633, 19.4516602, -73.4301758,
        -0.999575257, 0.0146499779, -0.025192149,
        0, 0.864456713, 0.502707124,
        0.029142173, 0.50249362, -0.864089608
    )
    Dungeon.CHEST_CAMERA_LOCK_SECONDS = 2
    Dungeon.CHEST_SETTLE_DELAY = 0.15
    Dungeon.CHEST_LOOP_DELAY = 0.1

    -- ── Timer helpers ────────────────────────────────────────────
    function Dungeon.parseTimerText(text)
        local mins, secs = tostring(text or ""):match("^(%d+):(%d+)$")
        if not mins then return nil end
        return (tonumber(mins) or 0) * 60 + (tonumber(secs) or 0)
    end

    function Dungeon.formatSeconds(totalSeconds)
        local clamped = math.max(0, totalSeconds or 0)
        return string.format("%d:%02d", math.floor(clamped / 60), clamped % 60)
    end

    function Dungeon.updateTimerCache(text)
        local normalized = tostring(text or "")
        if normalized == "" then return end
        local parsed = Dungeon.parseTimerText(normalized)
        if parsed then
            Dungeon.timerEndsAt    = os.clock() + parsed
            Dungeon.timerCachedText = Dungeon.formatSeconds(parsed)
        else
            Dungeon.timerEndsAt    = nil
            Dungeon.timerCachedText = normalized
        end
    end

    function Dungeon.getEffectiveTimerText()
        local liveText = Dungeon.timerSource and Dungeon.timerSource.Text or ""
        if liveText ~= "" then Dungeon.updateTimerCache(liveText); return liveText end
        if Dungeon.timerEndsAt then
            local remaining = math.max(0, math.ceil(Dungeon.timerEndsAt - os.clock()))
            if remaining <= 0 then
                Dungeon.timerEndsAt = nil; Dungeon.timerCachedText = "Queue Up"; return "Queue Up"
            end
            Dungeon.timerCachedText = Dungeon.formatSeconds(remaining)
            return Dungeon.timerCachedText
        end
        return Dungeon.timerCachedText
    end

    function Dungeon.refreshTimerLabel()
        if not Dungeon.timerLabel or not Dungeon.timerLabel.Parent then return end
        local timerText = Dungeon.getEffectiveTimerText()
        Dungeon.timerLabel.Text = timerText ~= "" and timerText or "0:00"
        Dungeon.timerLabel.TextColor3 = (timerText ~= "" and timerText ~= "0:00") and Core.C.orange or Core.C.textDim
    end

    function Dungeon.getTimerSource()
        local gameplay = Core.Gameplay
        local regionsLoaded = gameplay and gameplay:FindFirstChild("RegionsLoaded")
        local dungeonLobby  = regionsLoaded and regionsLoaded:FindFirstChild("Dungeon Lobby")
        local locations     = dungeonLobby and dungeonLobby:FindFirstChild("Locations")
        local dungeonSelect = locations and locations:FindFirstChild("DungeonSelect")
        local attachment    = dungeonSelect and dungeonSelect:FindFirstChild("Attachment")
        local billboardGui  = attachment and attachment:FindFirstChild("BillboardGui")
        local frame         = billboardGui and billboardGui:FindFirstChild("Frame")
        local desc          = frame and frame:FindFirstChild("Desc")
        if desc and desc:IsA("TextLabel") then return desc end
    end

    function Dungeon.isInsideActive()
        if os.clock() < (Dungeon.forceEndedUntil or 0) then return false end
        if Dungeon.hasDungeonTargets and Dungeon.hasDungeonTargets() then return true end
        local ds = workspace:FindFirstChild("DungeonStorage")
        if not ds then return false end
        for _, dungeon in ipairs(ds:GetChildren()) do
            for _, folderName in ipairs({"Gold","Shiny","Rainbow","Void"}) do
                local folder = dungeon:FindFirstChild(folderName)
                if folder and #folder:GetDescendants() > 0 then return true end
            end
        end
        return false
    end

    function Dungeon.hasDungeonTargets()
        if os.clock() < (Dungeon.forceEndedUntil or 0) then return false end
        local ds = workspace:FindFirstChild("DungeonStorage")
        if not ds then return false end

        for _, dungeon in ipairs(ds:GetChildren()) do
            local important = dungeon:FindFirstChild("Important")
            if important then
                for _, spawner in ipairs(important:GetChildren()) do
                    if Dungeon.VALID_SPAWNERS[spawner.Name] then
                        for _, target in ipairs(spawner:GetChildren()) do
                            if target:IsA("Model") and Dungeon.VALID_TARGETS[target.Name] then
                                local root = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
                                local humanoid = target:FindFirstChildOfClass("Humanoid")
                                if root and (not humanoid or humanoid.Health > 0) then
                                    if Dungeon.markRunActive then
                                        Dungeon.markRunActive("bot detected")
                                    end
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end

        return false
    end

    function Dungeon.isDungeonPresenceActive()
        if os.clock() < (Dungeon.forceEndedUntil or 0) then return false end
        if Dungeon.isInsideActive() then return true end
        return Dungeon.hasDungeonTargets()
    end

    function Dungeon.markRunActive(reason)
        local now = os.clock()
        local wasProtected = Dungeon.runProtectionActive == true
        Dungeon.runActive = true
        Dungeon.runProtectionActive = true
        Dungeon.runEnding = false
        Dungeon.lastDungeonActivityAt = now
        if (Dungeon.runProtectionStartedAt or 0) <= 0 then
            Dungeon.runProtectionStartedAt = now
        end
        Dungeon.runProtectionHeldLogged = false
        Core.lockWorldTeleports(3)
        if not wasProtected then
            Core.debugLog("Dungeon protection active:", reason or "presence")
        end
    end

    function Dungeon.markRunEnding(reason)
        Dungeon.runEndToken = (Dungeon.runEndToken or 0) + 1
        if Dungeon.runProtectionActive and not Dungeon.runEnding then
            Core.debugLog("Dungeon protection ending:", reason or "detected")
        end
        Dungeon.runEnding = true
        Dungeon.lastDungeonActivityAt = os.clock()
        if Dungeon.runProtectionActive then
            Core.lockWorldTeleports(5)
        end
    end

    function Dungeon.markRunEnded(reason)
        local wasProtected = Dungeon.runProtectionActive == true or Dungeon.runActive == true or Core.dungeonActive == true
        Dungeon.runEndToken = (Dungeon.runEndToken or 0) + 1
        Dungeon.runActive = false
        Dungeon.runProtectionActive = false
        Dungeon.runProtectionStartedAt = 0
        Dungeon.runProtectionHeldLogged = false
        Dungeon.runEnding = false
        Dungeon.lastDungeonActivityAt = os.clock()
        Dungeon.forceEndedUntil = os.clock() + 10
        Dungeon.autoStartCooldownUntil = math.max(Dungeon.autoStartCooldownUntil or 0, os.clock() + Core.DUNGEON_AUTOSTART_COOLDOWN)
        Core.dungeonActive = false
        Core.dungeonTeleportLockUntil = 0
        if Core.priorityOwner == "dungeon" then Core.priorityOwner = nil end
        if wasProtected then
            Core.debugLog("Dungeon protection ending:", reason or "detected")
        end
        Dungeon.resetAutoStartDebounce("dungeon ended")
        Dungeon.retryDeferredAutoStart((Core.DUNGEON_AUTOSTART_COOLDOWN or 3) + 0.25)
        if Core.state.auto_cycle and HS.AutoCycle and not HS.AutoCycle.enabled then
            Core.debugLog("Dungeon ended â€” resuming Auto Cycle")
            HS.AutoCycle.start()
        end
    end

    function Dungeon.isRunProtectionActive()
        if Dungeon.runProtectionActive ~= true then return false end
        local startedAt = Dungeon.runProtectionStartedAt or 0
        if startedAt > 0 and os.clock() - startedAt > (Dungeon.RUN_PROTECTION_TIMEOUT or 1200) then
            Core.debugLog("Dungeon protection timeout release")
            Dungeon.markRunEnded("timeout release")
            return false
        end
        return Dungeon.runProtectionActive == true
    end

    function Dungeon.scheduleRunEnd(delaySeconds, reason)
        Dungeon.runEndToken = (Dungeon.runEndToken or 0) + 1
        local token = Dungeon.runEndToken
        task.delay(delaySeconds or 5, function()
            if Dungeon.runEndToken ~= token then return end
            Dungeon.markRunEnded(reason or "post reward grace")
        end)
    end

    function Dungeon.isStartBlockedByPresence()
        if type(Dungeon.isRunProtectionActive) == "function" then
            local ok, protected = pcall(Dungeon.isRunProtectionActive)
            if ok and protected then return true end
        end

        if type(Dungeon.isDungeonPresenceActive) == "function" then
            local ok, active = pcall(Dungeon.isDungeonPresenceActive)
            if ok and active then return true end
        end

        if type(Dungeon.isInsideActive) == "function" then
            local ok, inside = pcall(Dungeon.isInsideActive)
            if ok and inside then return true end
        end

        return false
    end

    function Dungeon.resetAutoStartDebounce(reason)
        local hadDebounce = Dungeon.queueHandled or Dungeon.queueDeferredInside
        Dungeon.queueHandled = false
        Dungeon.queueDeferredInside = false
        if hadDebounce then
            Core.debugLog("Dungeon auto-start debounce reset", reason or "")
        end
    end

    function Dungeon.deferAutoStartWhileInside(reason)
        if not Dungeon.queueDeferredInside then
            if reason == "run protection active" then
                Core.debugLog("Dungeon auto-start skipped: run protection active")
            else
                Core.debugLog("Dungeon auto-start deferred while active dungeon")
            end
        end
        Dungeon.queueDeferredInside = true
        Dungeon.queueHandled = false
    end

    function Dungeon.retryDeferredAutoStart(delaySeconds)
        Dungeon.autoStartRetryToken = (Dungeon.autoStartRetryToken or 0) + 1
        local token = Dungeon.autoStartRetryToken
        task.delay(delaySeconds or 0, function()
            if not Core.alive or not Core.state.start_dungeon then return end
            if Dungeon.autoStartRetryToken ~= token then return end
            Dungeon.refreshTimerLabel()
            Dungeon.tryAutoStart()
        end)
    end

    function Dungeon.markEnded(reason)
        if not Dungeon.wasInside and not Core.dungeonActive and not Dungeon.runProtectionActive then return end

        Dungeon.wasInside = false
        Dungeon.markRunEnded(reason or "detected")
        Core.clearCurrentAction("Running Dungeon")
        Core.clearCurrentAction("Farming Dungeon Enemies")
        Core.clearCurrentAction("Claiming Dungeon Chest")
        Core.debugLog("Dungeon ended;", reason or "detected", "- cooldown started for", Core.DUNGEON_AUTOSTART_COOLDOWN, "seconds")
        -- Restart the Auto Cycle thread only if it died; normal dungeon resume keeps the toggle on and resets runtime state in AutoCycle.
        if Core.state.auto_cycle and HS.AutoCycle and not HS.AutoCycle.enabled then
            Core.debugLog("Dungeon ended — resuming Auto Cycle")
            HS.AutoCycle.start()
        end
    end

    function Dungeon.updateAutoStartState()
        local botDetected = Dungeon.hasDungeonTargets and Dungeon.hasDungeonTargets() or false
        local insideDungeon = botDetected or Dungeon.isInsideActive()
        if insideDungeon then
            Core.setCurrentAction("Running Dungeon", 3)
            Dungeon.markRunActive(botDetected and "bot detected" or "presence")
        end
        if Dungeon.wasInside and not insideDungeon then
            if Dungeon.isRunProtectionActive() then
                if not Dungeon.runProtectionHeldLogged then
                    Core.debugLog("Dungeon protection held between waves")
                    Dungeon.runProtectionHeldLogged = true
                end
            else
                Dungeon.markEnded("storage cleared")
            end
        elseif not Dungeon.wasInside and insideDungeon then
            Core.lockWorldTeleports(20)
            Core.debugLog("Detected active dungeon instance")
            Core.debugLog("Dungeon started — priority lock active")
        end
        Dungeon.wasInside = insideDungeon
        return insideDungeon
    end

    function Dungeon.refreshPresenceLock()
        local presenceActive = Dungeon.isDungeonPresenceActive()
        if presenceActive then
            Dungeon.markRunActive("presence")
        end

        local autoStateActive = Dungeon.updateAutoStartState()
        if presenceActive or autoStateActive or Dungeon.isRunProtectionActive() then
            Core.lockWorldTeleports(3)
            if not presenceActive and not autoStateActive and not Dungeon.runProtectionHeldLogged then
                Core.debugLog("Dungeon protection held between waves")
                Dungeon.runProtectionHeldLogged = true
            end
            return true
        end

        return false
    end

    function Dungeon.startPresenceWatchdog()
        Core.state.dungeon_presence_watchdog = true
        Dungeon.refreshPresenceLock()
        Core.loopWhile("dungeon_presence_watchdog", 1, function()
            Dungeon.refreshPresenceLock()
        end)
    end

    function Dungeon.installRegionLoadedHook()
        if Dungeon.regionLoadedHookInstalled then return end
        if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
            Core.debugLog("Dungeon end hook unavailable: hookmetamethod missing")
            return
        end

        Dungeon.regionLoadedHookInstalled = true
        local oldNamecall
        local ok, err = pcall(function()
            oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                local args = {...}
                if self == Core.UIActionRemote
                    and getnamecallmethod() == "FireServer"
                    and args[1] == "SetRegionLoaded"
                    and args[2] == "Dungeon Lobby" then
                    task.defer(function()
                        if HS.Dungeon and HS.Dungeon.eggRewardPending then
                            if HS.Dungeon.markRunEnding then
                                HS.Dungeon.markRunEnding("lobby loaded")
                            end
                            return
                        end
                        if HS.Dungeon and HS.Dungeon.markEnded then
                            HS.Dungeon.markEnded("lobby loaded")
                        end
                    end)
                end

                return oldNamecall(self, ...)
            end)
        end)
        if not ok then
            Dungeon.regionLoadedHookInstalled = false
            Core.debugLog("Dungeon end hook failed:", err)
        end
    end

    function Dungeon.tryAutoStart()
        local timerText = Dungeon.getEffectiveTimerText()
        if timerText ~= "Queue Up" then Dungeon.resetAutoStartDebounce("timer changed"); return end
        if not Core.state.start_dungeon then return end
        if Dungeon.isRunProtectionActive() then
            Dungeon.deferAutoStartWhileInside("run protection active")
            return
        end
        if Dungeon.updateAutoStartState() or Dungeon.isStartBlockedByPresence() then
            Dungeon.deferAutoStartWhileInside("active dungeon")
            return
        end
        if Dungeon.queueDeferredInside then
            Dungeon.resetAutoStartDebounce("left dungeon")
        end
        if Dungeon.queueHandled then return end
        if os.clock() < Dungeon.autoStartCooldownUntil then
            Core.debugLog("Auto-start waiting for cooldown;", math.max(0, math.ceil(Dungeon.autoStartCooldownUntil - os.clock())), "seconds left")
            return
        end
        local privacy    = Core.selectionState.dungeon_privacy or "Public"
        local dungeonType = Core.selectionState.dungeon_type or "Space"
        local difficulty  = Dungeon.DIFFICULTY_MAP[Core.selectionState.dungeon_difficulty or "Easy"] or 1
        if Dungeon.isRunProtectionActive() then
            Dungeon.deferAutoStartWhileInside("run protection active")
            return
        end
        if Dungeon.isStartBlockedByPresence() then
            Core.debugLog("Dungeon auto-start skipped: already inside dungeon")
            Dungeon.deferAutoStartWhileInside("active dungeon")
            return
        end
        Core.debugLog("Dungeon auto-start firing Create/Start", "type=", dungeonType, "difficulty=", difficulty, "privacy=", privacy)
        if Core.state.farm_egg then Core.debugLog("Refreshing incubator cache before dungeon start"); Dungeon.refreshIncubatorUi() end
        Core.setCurrentAction("Running Dungeon", 5)
        pcall(function() Core.UIActionRemote:FireServer("DungeonGroupAction","Create",privacy,dungeonType,difficulty) end)
        task.wait(Dungeon.START_REMOTE_DELAY or 2)
        if Dungeon.isRunProtectionActive() then
            Dungeon.deferAutoStartWhileInside("run protection active")
            return
        end
        if Dungeon.isStartBlockedByPresence() then
            Core.debugLog("Dungeon auto-start skipped: already inside dungeon")
            return
        end
        pcall(function() Core.UIActionRemote:FireServer("DungeonGroupAction","Start") end)
        Dungeon.queueHandled = true
        Core.lockWorldTeleports(30)
        Dungeon.markRunActive("auto-start")
        Core.debugLog("Dungeon create/start remotes fired")
    end

    function Dungeon.watchTimerSource()
        if Dungeon.timerWatcherThread then return end
        Dungeon.timerWatcherThread = task.spawn(function()
            while Core.alive do
                Dungeon.updateAutoStartState()
                local source = Dungeon.getTimerSource()
                if source ~= Dungeon.timerSource then
                    if Dungeon.timerSourceConnection then
                        Dungeon.timerSourceConnection:Disconnect(); Dungeon.timerSourceConnection = nil
                    end
                    Dungeon.timerSource = source
                    if source then
                        Dungeon.timerSourceConnection = source:GetPropertyChangedSignal("Text"):Connect(function()
                            Dungeon.updateTimerCache(source.Text); Dungeon.refreshTimerLabel()
                        end)
                    end
                end
                if Dungeon.timerSource and Dungeon.timerSource.Text ~= "" then
                    Dungeon.updateTimerCache(Dungeon.timerSource.Text)
                end
                Dungeon.refreshTimerLabel()
                Dungeon.tryAutoStart()
                task.wait(1)
            end
        end)
    end

    function Dungeon.startTimer()
        Dungeon.watchTimerSource(); Dungeon.refreshTimerLabel()
    end

    -- ── Egg incubator helpers ────────────────────────────────────
    function Dungeon.normalizeEggName(name)
        return tostring(name or ""):lower():gsub("%s+", " "):gsub("^%s+",""):gsub("%s+$","")
    end

    function Dungeon.getEggRank(name)
        return Dungeon.EGG_RANKS[Dungeon.normalizeEggName(name)] or 0
    end

    function Dungeon.isSlotEmpty(text)
        local n = Dungeon.normalizeEggName(text)
        return n == "" or n == "empty" or n:find("empty", 1, true) ~= nil
    end

    function Dungeon.getIncubatorGui()
        local mainGui = Core.player:FindFirstChild("PlayerGui") and Core.player.PlayerGui:FindFirstChild("MainGui")
        local otherFrames = mainGui and mainGui:FindFirstChild("OtherFrames")
        return otherFrames and otherFrames:FindFirstChild("DungeonIncubator")
    end

    function Dungeon.setIncubatorVisible(visible)
        local gui = Dungeon.getIncubatorGui()
        if gui and gui:IsA("GuiObject") then
            gui.Visible = visible == true
            return true
        end
        return false
    end

    function Dungeon.findIncubatorOpenButton()
        local playerGui = Core.player:FindFirstChild("PlayerGui")
        if not playerGui then return nil end
        for _, obj in ipairs(playerGui:GetDescendants()) do
            if obj:IsA("GuiButton") then
                local name = tostring(obj.Name or ""):lower()
                local text = obj:IsA("TextButton") and tostring(obj.Text or ""):lower() or ""
                local parentName = obj.Parent and tostring(obj.Parent.Name or ""):lower() or ""
                if name:find("incubator", 1, true)
                    or text:find("incubator", 1, true)
                    or parentName:find("incubator", 1, true) then
                    return obj
                end
            end
        end
        return nil
    end

    function Dungeon.openIncubatorMenu(closeAfter)
        local gui = Dungeon.getIncubatorGui()
        local wasVisible = gui and gui:IsA("GuiObject") and gui.Visible == true
        if gui and gui:IsA("GuiObject") then
            gui.Visible = true
            task.wait(0.15)
            Dungeon.scanIncubatorSlots()
            if #Dungeon.incubatorSlots > 0 then
                Core.debugLog("Dungeon incubator menu opened directly")
                if closeAfter and not wasVisible then Dungeon.setIncubatorVisible(false) end
                return true
            end
        end

        local button = Dungeon.findIncubatorOpenButton()
        if button then
            Core.debugLog("Trying incubator open button:", button:GetFullName())
            if type(firesignal) == "function" then
                pcall(function() firesignal(button.MouseButton1Click) end)
            else
                pcall(function()
                    button.MouseButton1Click:Fire()
                end)
            end
            task.wait(0.35)
        end

        gui = Dungeon.getIncubatorGui()
        if gui and gui:IsA("GuiObject") then gui.Visible = true end
        Dungeon.scanIncubatorSlots()
        local loaded = #Dungeon.incubatorSlots > 0
        if closeAfter and not wasVisible then Dungeon.setIncubatorVisible(false) end
        return loaded
    end

    function Dungeon.scanIncubatorSlots()
        table.clear(Dungeon.incubatorSlots)
        local gui   = Dungeon.getIncubatorGui()
        local frame = gui and gui:FindFirstChild("Frame")
        if not frame then return end
        for i = 1, Dungeon.MAX_INCUBATOR_SLOTS do
            local slotFrame = frame:FindFirstChild(tostring(i))
            local title     = slotFrame and slotFrame:FindFirstChild("Title")
            local timerText = slotFrame and slotFrame:FindFirstChild("TimerText")
            if title and title:IsA("TextLabel") then
                table.insert(Dungeon.incubatorSlots, {
                    slot = i,
                    text = title.Text ~= "" and title.Text or "Empty",
                    timerText = timerText and timerText.Text or "",
                })
            end
        end
        Core.debugLog("Scanned incubator slots:", #Dungeon.incubatorSlots)
    end

    function Dungeon.refreshIncubatorUi()
        Dungeon.scanIncubatorSlots()
        if Core.activeTab == "Dungeon" then HS.UI.renderContent() end
    end

    function Dungeon.updateSlotCache(slotNumber, eggName, timerText)
        for _, info in ipairs(Dungeon.incubatorSlots) do
            if info.slot == slotNumber then
                info.text = eggName
                info.timerText = timerText or info.timerText or ""
                Core.debugLog("Updated slot cache", slotNumber, "->", eggName)
                if Core.activeTab == "Dungeon" then HS.UI.renderContent() end
                return
            end
        end
        table.insert(Dungeon.incubatorSlots, {slot=slotNumber, text=eggName, timerText=timerText or ""})
        table.sort(Dungeon.incubatorSlots, function(a,b) return a.slot < b.slot end)
        Core.debugLog("Added slot cache", slotNumber, "->", eggName)
        if Core.activeTab == "Dungeon" then HS.UI.renderContent() end
    end

    function Dungeon.claimEggToSlot(slotNumber)
        Core.debugLog("Claiming egg into incubator slot", slotNumber)
        pcall(function()
            S.ReplicatedStorage:WaitForChild("Events"):WaitForChild("UIAction"):FireServer("HatchDungeonEgg", slotNumber)
        end)
        return true
    end

    function Dungeon.replaceEggInSlot(slotNumber)
        Core.debugLog("Replacing incubator slot", slotNumber)
        pcall(function() Core.UIActionRemote:FireServer("ReplaceEggInSlot", slotNumber) end)
    end

    function Dungeon.isEggReady(timerText)
        local n = tostring(timerText or ""):lower():gsub("%s+", "")
        if n == "" then return false end
        if n:find("ready", 1, true)
            or n:find("open", 1, true)
            or n:find("claim", 1, true)
            or n:find("hatch", 1, true) then
            return true
        end

        local h, m, s = n:match("^(%d+):(%d+):(%d+)$")
        if h then
            return ((tonumber(h) or 0) * 3600 + (tonumber(m) or 0) * 60 + (tonumber(s) or 0)) <= 0
        end

        m, s = n:match("^(%d+):(%d+)$")
        if m then
            return ((tonumber(m) or 0) * 60 + (tonumber(s) or 0)) <= 0
        end

        return n == "0"
    end

    function Dungeon.isSlotClearlyClaimable(info)
        if type(info) ~= "table" then return false end
        return Dungeon.isEggReady(info.timerText) or Dungeon.isEggReady(info.text)
    end

    function Dungeon.hatchEgg(slotNumber)
        Core.debugLog("Claiming hatched egg from slot", slotNumber)
        local ok, err = pcall(function() Core.UIActionRemote:FireServer("HatchDungeonEgg", slotNumber) end)
        if not ok then Core.debugLog("HatchDungeonEgg failed:", tostring(err)) end
        return ok
    end

    function Dungeon.readSlotTimerDirectly(slotNumber)
        local gui   = Dungeon.getIncubatorGui()
        local frame = gui and gui:FindFirstChild("Frame")
        local slotFrame = frame and frame:FindFirstChild(tostring(slotNumber))
        local timerText = slotFrame and slotFrame:FindFirstChild("TimerText")
        return timerText and timerText.Text or ""
    end

    function Dungeon.tryClaimEggs()
        -- Always scan fresh so we never miss a ready egg due to stale cache
        Dungeon.scanIncubatorSlots()
        if #Dungeon.incubatorSlots == 0 then
            Core.debugLog("tryClaimEggs: no incubator slots found; opening incubator once")
            Dungeon.openIncubatorMenu(true)
            Dungeon.scanIncubatorSlots()
            if #Dungeon.incubatorSlots == 0 then
                Core.debugLog("tryClaimEggs: no incubator slots found after opening")
                return
            end
        end
        Core.debugLog("tryClaimEggs: checking", #Dungeon.incubatorSlots, "slots")
        local now = os.clock()
        for _, info in ipairs(Dungeon.incubatorSlots) do
            local slot = tonumber(info.slot)
            if slot and not Dungeon.isSlotEmpty(info.text) then
                -- Read live timer directly from GUI as secondary confirmation
                local liveTimer = Dungeon.readSlotTimerDirectly(slot)
                if liveTimer ~= "" then info.timerText = liveTimer end
                local clearlyClaimable = Dungeon.isSlotClearlyClaimable(info)
                local forceClaim = false
                if not clearlyClaimable then
                    local lastAttempt = Dungeon.lastForceClaimAttempt[slot] or (now - Dungeon.FORCE_CLAIM_INTERVAL)
                    forceClaim = (now - lastAttempt) >= Dungeon.FORCE_CLAIM_INTERVAL
                end

                Core.debugLog("Slot", slot, "egg:", info.text, "timer:", info.timerText)
                if clearlyClaimable or forceClaim then
                    if Core.state.avoid_sun and Dungeon.getEggRank(info.text) >= Dungeon.EGG_RANKS["sun egg"] then
                        Core.debugLog("Skipping Sun egg in slot", slot)
                    else
                        if forceClaim then
                            Dungeon.lastForceClaimAttempt[slot] = now
                            Core.debugLog("Force claim attempt for occupied dungeon egg slot", slot)
                        end

                        if Dungeon.hatchEgg(slot) then
                            if clearlyClaimable then
                                task.wait(0.2)
                                Dungeon.updateSlotCache(slot, "Empty", "")
                            end
                        end
                    end
                end
            else
                Core.debugLog("Slot", info.slot, "is empty — skipping")
            end
        end
    end

    function Dungeon.startClaimEggs()
        Core.debugLog("Claiming started")
        Core.loopWhile("claim_egg", Core.CLAIM_EGG_DELAY, Dungeon.tryClaimEggs)
        Core.debugLog("Claiming finished")
    end

    function Dungeon.handleEggReward(eggName)
        if not Core.state.farm_egg or Dungeon.eggRewardPending then return end
        local rewardRank = Dungeon.getEggRank(eggName)
        if rewardRank <= 0 then Core.debugLog("Unknown dungeon egg reward ignored:", eggName); return end
        Dungeon.eggRewardPending = eggName
        Core.setCurrentAction("Handling Dungeon Egg", 30)
        Core.debugLog("Handling dungeon egg reward:", eggName, "rank=", rewardRank)
        Core.fireUI("SetRegionLoaded", "Dungeon Lobby")
        task.wait(2)
        local emptySlot, replaceSlot, weakestRank = nil, nil, math.huge
        for _, info in ipairs(Dungeon.incubatorSlots) do
            local slotRank = Dungeon.getEggRank(info.text)
            if Dungeon.isSlotEmpty(info.text) then
                emptySlot = emptySlot or info.slot
            elseif slotRank > 0 and slotRank < rewardRank and slotRank < weakestRank then
                weakestRank = slotRank; replaceSlot = info.slot
            end
        end
        if emptySlot then
            Dungeon.claimEggToSlot(emptySlot); Dungeon.updateSlotCache(emptySlot, eggName)
        elseif replaceSlot then
            Dungeon.replaceEggInSlot(replaceSlot); Dungeon.updateSlotCache(replaceSlot, eggName)
        else
            Core.debugLog("No empty or weaker slot found for", eggName)
        end
        task.wait(0.2)
        Dungeon.eggRewardPending = nil
        Core.clearCurrentAction("Handling Dungeon Egg")
        Core.debugLog("Finished handling dungeon egg reward:", eggName)
    end

    -- ── Shards amount reader ─────────────────────────────────────
    function Dungeon.getShardsAmount()
        local amountLabel = Core.player:FindFirstChild("PlayerGui")
            and Core.player.PlayerGui:FindFirstChild("MainGui")
            and Core.player.PlayerGui.MainGui:FindFirstChild("StartFrame")
            and Core.player.PlayerGui.MainGui.StartFrame:FindFirstChild("Currency")
            and Core.player.PlayerGui.MainGui.StartFrame.Currency:FindFirstChild("DungeonShards")
            and Core.player.PlayerGui.MainGui.StartFrame.Currency.DungeonShards:FindFirstChild("Amount")
        return Core.parseCompactNumber(amountLabel and amountLabel.Text or "")
    end

    function Dungeon.getUpgradeShopInfo()
        if Dungeon.upgradeShopInfoLoaded then return Dungeon.upgradeShopInfo end
        Dungeon.upgradeShopInfoLoaded = true

        local ok, info = pcall(function()
            return require(S.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DungeonUpgradeShop"))
        end)
        if ok and type(info) == "table" then
            Dungeon.upgradeShopInfo = info
            return info
        end

        Core.debugLog("Dungeon upgrade shop info failed:", info)
        Dungeon.upgradeShopInfo = nil
        return nil
    end

    function Dungeon.getUpgradeLevel(upgradeType)
        local ClientData = Core.getClientDataManager()
        local data = ClientData and ClientData.Data
        local upgrades = data and data.DungeonUpgrades
        return tonumber(upgrades and upgrades[upgradeType]) or 0
    end

    function Dungeon.getDungeonShards()
        local ClientData = Core.getClientDataManager()
        local data = ClientData and ClientData.Data
        return tonumber(data and data.DungeonShards) or 0
    end

    function Dungeon.getUpgradeMaxLevel(upgradeType)
        local info = Dungeon.getUpgradeShopInfo()
        local upgrades = info and info[upgradeType] and info[upgradeType].Upgrades
        if type(upgrades) ~= "table" then return nil end

        local maxLevel = nil
        for level in pairs(upgrades) do
            local numericLevel = tonumber(level)
            if numericLevel and (not maxLevel or numericLevel > maxLevel) then
                maxLevel = numericLevel
            end
        end
        return maxLevel
    end

    function Dungeon.getUpgradeNextCost(upgradeType, currentLevel)
        local info = Dungeon.getUpgradeShopInfo()
        local upgrades = info and info[upgradeType] and info[upgradeType].Upgrades
        local nextLevel = (tonumber(currentLevel) or 0) + 1
        local nextUpgrade = type(upgrades) == "table" and (upgrades[nextLevel] or upgrades[tostring(nextLevel)])
        return tonumber(nextUpgrade and nextUpgrade.Price)
    end

    function Dungeon.setUpgradeToggleOff(upgradeType, reason)
        local key = "dungeon_" .. tostring(upgradeType)
        if Core.state[key] == false then return end

        Core.state[key] = false
        Core.debugLog("Dungeon upgrade disabled:", upgradeType, reason or "stopped")
        if HS.Session and HS.Session.save then
            pcall(HS.Session.save)
        end
        if HS.UI and HS.UI.renderContent and Core.activeTab == "Dungeon" then
            pcall(HS.UI.renderContent)
        end
    end

    -- ── Dungeon upgrade loop factory ─────────────────────────────
    function Dungeon.startUpgrade(upgradeType)
        return function()
            Core.loopWhile("dungeon_" .. upgradeType, Core.BUY_DELAY, function()
                local currentLevel = Dungeon.getUpgradeLevel(upgradeType)
                local maxLevel = Dungeon.getUpgradeMaxLevel(upgradeType)
                if maxLevel and currentLevel >= maxLevel then
                    Dungeon.setUpgradeToggleOff(upgradeType, "max level")
                    return
                end

                local nextLevel = currentLevel + 1
                local cost = Dungeon.getUpgradeNextCost(upgradeType, currentLevel)
                local shards = Dungeon.getDungeonShards()
                if not cost then
                    return
                end
                if shards < cost then
                    return
                end

                local buyKey = tostring(upgradeType) .. ":" .. tostring(nextLevel)
                local now = os.clock()
                if now - (Dungeon.lastUpgradeBuy[buyKey] or 0) < 1 then
                    return
                end

                Dungeon.lastUpgradeBuy[buyKey] = now
                Core.debugLog("Buying dungeon upgrade", upgradeType, "level", nextLevel)
                Core.UIActionRemote:FireServer("BuyDungeonUpgrade", upgradeType, nextLevel)
            end)
        end
    end

    -- ── Hover/hit dungeon farm ───────────────────────────────────
    function Dungeon.getEquippedRemote()
        local c = Core.player.Character or Core.player.CharacterAdded:Wait()
        for _, obj in ipairs(c:GetDescendants()) do
            if obj:IsA("RemoteEvent") then return obj end
        end
    end

    function Dungeon.getHoverHeight(target)
        local targetName = target and target.Name or ""
        local colorName  = targetName:match("^(%a+)")
        if colorName and colorName ~= "Green" then return Dungeon.HEIGHT + 1 end
        return Dungeon.HEIGHT
    end

    function Dungeon.getAllTargets()
        local targets = {}
        local ds = workspace:FindFirstChild("DungeonStorage")
        if not ds then return targets end
        for _, dungeon in ipairs(ds:GetChildren()) do
            local important = dungeon:FindFirstChild("Important")
            if important then
                for _, obj in ipairs(important:GetChildren()) do
                    if Dungeon.VALID_SPAWNERS[obj.Name] then
                        for _, target in ipairs(obj:GetChildren()) do
                            if target:IsA("Model") and Dungeon.VALID_TARGETS[target.Name] then
                                table.insert(targets, target)
                            end
                        end
                    end
                end
            end
        end
        return targets
    end

    function Dungeon.getClosest()
        local root = Core.getRoot()
        if not root then return nil, math.huge end
        local closest, shortest = nil, math.huge
        for _, target in ipairs(Dungeon.getAllTargets()) do
            local dist = (root.Position - target:GetPivot().Position).Magnitude
            if dist < shortest then shortest = dist; closest = target end
        end
        return closest, shortest
    end

    function Dungeon.isValid(target)
        return target and target.Parent ~= nil
    end

    function Dungeon.startFarm()
        if Dungeon.hoverConnection then Dungeon.hoverConnection:Disconnect(); Dungeon.hoverConnection = nil end
        Dungeon.currentTarget = nil
        Dungeon.hitThread = task.spawn(function()
            Core.debugLog("Farm Dungeon hit loop started")
            while Core.alive and Core.state.farm_dungeon do
                local rm = Dungeon.getEquippedRemote()
                if Dungeon.currentTarget and rm and Dungeon.isValid(Dungeon.currentTarget) then
                    Core.setCurrentAction("Farming Dungeon Enemies", 2)
                    pcall(function() rm:FireServer({Dungeon.currentTarget}) end)
                end
                task.wait(Core.getFastHitDelay(Dungeon.HIT_DELAY))
            end
            Core.clearCurrentAction("Farming Dungeon Enemies")
            Core.debugLog("Farm Dungeon hit loop stopped")
        end)
        Dungeon.hoverConnection = S.RunService.Heartbeat:Connect(function()
            if not (Core.alive and Core.state.farm_dungeon) then
                Dungeon.hoverConnection:Disconnect(); Dungeon.hoverConnection = nil; return
            end
            local root = Core.getRoot(); if not root then return end
            local closest, dist = Dungeon.getClosest()
            if not Dungeon.isValid(Dungeon.currentTarget) then
                Dungeon.currentTarget = closest
                if Dungeon.currentTarget then Core.debugLog("Dungeon target set to", Dungeon.currentTarget.Name) end
            elseif closest and closest ~= Dungeon.currentTarget then
                local curDist = (root.Position - Dungeon.currentTarget:GetPivot().Position).Magnitude
                if dist + Dungeon.SWITCH_BUFFER < curDist then
                    Dungeon.currentTarget = closest
                    Core.debugLog("Dungeon target switched to", Dungeon.currentTarget.Name)
                end
            end
            if not Dungeon.currentTarget then return end
            local targetPos = Dungeon.currentTarget:GetPivot().Position
            local hoverPos  = targetPos + Vector3.new(0, Dungeon.getHoverHeight(Dungeon.currentTarget), 0)
            local newPos    = root.Position:Lerp(hoverPos, Dungeon.SMOOTHNESS)
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = CFrame.new(newPos, targetPos)
        end)
    end

    -- ── Chest claim ──────────────────────────────────────────────
    function Dungeon.getChestPartFromPrompt(prompt)
        if not (prompt and prompt.Parent and prompt:IsA("ProximityPrompt")) then return nil end
        local parent = prompt.Parent
        if parent:IsA("BasePart") then return parent end
        if parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
            return parent.Parent
        end
        return nil
    end

    function Dungeon.findClosestChestPrompt()
        local root = Core.getRoot()
        if not root then return nil, nil end

        local ds = workspace:FindFirstChild("DungeonStorage")
        if not ds then return nil, nil end

        local closestPrompt, closestPart, closestDist = nil, nil, math.huge
        for _, dungeon in ipairs(ds:GetChildren()) do
            for _, folderName in ipairs(Dungeon.CHEST_FOLDERS) do
                local folder = dungeon:FindFirstChild(folderName)
                if folder then
                    for _, obj in ipairs(folder:GetDescendants()) do
                        if obj:IsA("ProximityPrompt") then
                            local chestPart = Dungeon.getChestPartFromPrompt(obj)
                            if chestPart then
                                local dist = (root.Position - chestPart.Position).Magnitude
                                if dist < closestDist then
                                    closestPrompt = obj
                                    closestPart = chestPart
                                    closestDist = dist
                                end
                            end
                        end
                    end
                end
            end
        end

        return closestPrompt, closestPart
    end

    function Dungeon.lockChestCamera(chestPart, shouldContinue)
        local cam = workspace.CurrentCamera
        if not cam then return false end

        local function restoreCamera()
            local currentCam = workspace.CurrentCamera or cam
            if currentCam then
                currentCam.CameraType = Enum.CameraType.Custom
            end
        end

        local ok, err = pcall(function()
            cam.CameraType = Enum.CameraType.Scriptable
            local startedAt = os.clock()
            while os.clock() - startedAt < Dungeon.CHEST_CAMERA_LOCK_SECONDS do
                if not chestPart or not chestPart.Parent then break end
                if shouldContinue and not shouldContinue() then break end
                cam = workspace.CurrentCamera or cam
                if not cam then break end
                cam.CameraType = Enum.CameraType.Scriptable
                cam.CFrame = chestPart.CFrame * Dungeon.CAMERA_RELATIVE_TO_CHEST
                S.RunService.RenderStepped:Wait()
            end
        end)

        restoreCamera()
        if not ok then
            Core.debugLog("Chest camera lock failed:", err)
        end
        return ok
    end

    function Dungeon.claimChest()
        if Dungeon.chestThread then return end
        Dungeon.chestThread = task.spawn(function()
            Core.debugLog("Claim Chest loop started")
            while Core.alive and Core.state.farm_chest do
                local prompt, chestPart = Dungeon.findClosestChestPrompt()
                if prompt and chestPart then
                    local root = Core.getRoot()
                    if root then
                        Core.debugLog("Claiming chest at", chestPart.Position)
                        Core.setCurrentAction("Claiming Dungeon Chest", 3)
                        root.CFrame = chestPart.CFrame * Dungeon.PLAYER_RELATIVE_TO_CHEST
                        task.wait(Dungeon.CHEST_SETTLE_DELAY)

                        Dungeon.lockChestCamera(chestPart, function()
                            return Core.alive
                                and Core.state.farm_chest
                                and Dungeon.isInsideActive()
                                and prompt
                                and prompt.Parent
                                and chestPart
                                and chestPart.Parent
                        end)

                        if Core.alive and Core.state.farm_chest and prompt and prompt.Parent then
                            if type(fireproximityprompt) == "function" then
                                pcall(function() fireproximityprompt(prompt) end)
                            else
                                pcall(function() prompt:InputHoldBegin() end)
                                task.wait(prompt.HoldDuration or 0)
                                pcall(function() prompt:InputHoldEnd() end)
                            end
                            Dungeon.markRunEnding("chest claimed")
                            Dungeon.scheduleRunEnd(8, "chest claimed grace")
                        end
                    end
                end
                task.wait(Dungeon.CHEST_LOOP_DELAY)
            end
            Dungeon.chestThread = nil
            Core.clearCurrentAction("Claiming Dungeon Chest")
            Core.debugLog("Claim Chest loop stopped")
        end)
    end
end
