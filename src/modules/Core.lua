return function(HS, S)
    local Core = HS.Core or {}
    HS.Core = Core

    Core.player    = S.Players.LocalPlayer
    Core.playerGui = Core.player:WaitForChild("PlayerGui")

    -- cleanup old instances
    for _, name in ipairs({"HeartsteelUI", "HeartsteelToggleGui"}) do
        local old = Core.playerGui:FindFirstChild(name)
        if old then old:Destroy() end
    end

    -- ── Remotes & workspace refs ────────────────────────────────
    local EventsFolder = S.ReplicatedStorage:WaitForChild("Events")
    Core.SwingSaberRemote      = EventsFolder:WaitForChild("SwingSaber")
    Core.SellStrengthRemote    = EventsFolder:WaitForChild("SellStrength")
    Core.UIActionRemote        = EventsFolder:WaitForChild("UIAction")
    Core.ClientNotifierRemote  = EventsFolder:WaitForChild("ClientNotifierEvent")

    local _Gameplay   = workspace:WaitForChild("Gameplay", 20)
    local _Boss       = _Gameplay and _Gameplay:WaitForChild("Boss", 10)
    Core.BossHolder   = _Boss    and _Boss:WaitForChild("BossHolder", 10)
    local _KOTH       = _Gameplay and _Gameplay:WaitForChild("KOTH", 10)
    Core.KOH_BOUNDARY = _KOTH   and _KOTH:WaitForChild("KOH_BOUNDARY", 10)
    Core.Gameplay     = _Gameplay

    Core.CollectCurrencyRemote = EventsFolder:WaitForChild("CollectCurrencyPickup", 10)
    local _CurrencyPickup      = _Gameplay and _Gameplay:WaitForChild("CurrencyPickup", 10)
    Core.CurrencyHolder        = _CurrencyPickup and _CurrencyPickup:WaitForChild("CurrencyHolder", 10)

    -- ── Numeric config ──────────────────────────────────────────
    Core.SWING_DELAY            = 0.12
    Core.SELL_DELAY             = 0.25
    Core.BUY_DELAY              = 2.0
    Core.FAST_HIT_DELAY         = 0.03
    Core.BOSS_DELAY             = 0.12
    Core.BOSS_POS               = CFrame.new(417.53, 187.38, 143.61)
    Core.CLAIM_EGG_DELAY        = 5
    Core.DUNGEON_AUTOSTART_COOLDOWN = 3
    Core.activeCycleKey = nil
    Core.activeLoops = {}
    Core.ClientDataManager = nil
    Core.CurrentAction = "Idle"
    Core.CurrentActionExpiresAt = nil
    Core.sessionStartUnix = os.time()
    Core.config = {
        Logs = {
            Pets = {
                Enabled = false,
                WebhookURL = "",
            },
            DiscordMonitor = {
                Enabled = false,
                WebhookURL = "",
                UpdateInterval = 10,
                MessageId = nil,
                ShowElementLevels = false,
                ShowMasteryLevels = false,
                ShowDungeonEggs = false,
                ShowSessionStats = false,
                ShowConnectionStats = false,
            },
        },
    }

    -- ── Flag position → height mapping ──────────────────────────
    Core.FLAG_TARGETS = {
        {pos = Vector3.new(20, 0, 70), height = 254},
        {pos = Vector3.new(711, 0, 475), height = 213},
        {pos = Vector3.new(437, 0, -251), height = 285},
        {pos = Vector3.new(635, 0, 150), height = 259},
        {pos = Vector3.new(624, 0, -98), height = 478},
    }
    Core.FLAG_HEIGHT_TOLERANCE = 0.35

    -- ── Saber buy action names ──────────────────────────────────
    Core.SABER_BUY_ACTIONS = {
        "BuyBestWeapon","BuyBestSaber","BuyAllWeapons",
        "BuyAllSabers","BuyWeapons","BuySwords","BuyAllSwords"
    }

    -- ── Area / teleport table ───────────────────────────────────
    Core.AREAS = {
        {label="Dungeon Lobby", pos=Vector3.new(350.30, 184.14,  -48.00)},
        {label="Boss",          pos=Vector3.new(417.53, 187.38,  143.61)},
        {label="Egg Hatch",     pos=Vector3.new(560.97, 184.70,  -29.32)},
        {label="King",          pos=Vector3.new(735.24, 250.00,   51.20)},
        {label="--- WATER ---", isLabel=true},
        {label="Water",               pos=Vector3.new(114.07, 281.42, -561.10)},
        {label="Water Advanced",      pos=Vector3.new(-230.458694, 19.491642, -772.777283)},
        {label="Water Master",        pos=Vector3.new(-712.291687, 89.4910126, -1037.21484)},
        {label="Water GrandMaster",   pos=Vector3.new(-758.509338, 140.709015, -1614.53735)},
        {label="--- FIRE ---", isLabel=true},
        {label="Fire",                pos=Vector3.new(546.108887, 190.124451, 464.28595)},
        {label="Fire Advanced",       pos=Vector3.new(-113.955597, 36.3218079, 680.963501)},
        {label="Fire Master",         pos=Vector3.new(-758.509827, 91.2569656, 708.33075)},
        {label="Fire GrandMaster",    pos=Vector3.new(-1464.19922, 89.4910126, 744.918884)},
        {label="--- Earth ---", isLabel=true},
        {label="Earth",               pos=Vector3.new(781.821594, 209.676895, -240.4366)},
        {label="Earth Advanced",      pos=Vector3.new(1215.45911, -20.1246204, -915.426331)},
        {label="Earth Master",        pos=Vector3.new(1724.30981, 10.186799, -955.032104)},
        {label="Earth GrandMaster",   pos=Vector3.new(1869.46387, 9.67078972, -1436.64807)},
        {label="--- PLASMA ---", isLabel=true},
        {label="Plasma",              pos=Vector3.new(2063.61523, -9.85239124, 172.534424)},
        {label="Plasma Advanced",     pos=Vector3.new(2686.28003, 85.4065475, 9.84980392)},
        {label="Plasma Master",       pos=Vector3.new(2925.77148, 109.324539, 1032.02002)},
        {label="Plasma GrandMaster",  pos=Vector3.new(3780.17969, 119.138786, 1016.48413)},
    }

    -- ── Colour palette ──────────────────────────────────────────
    Core.C = {
        window      = Color3.fromRGB(13,  10,  23),
        topbar      = Color3.fromRGB(17,  13,  28),
        sidebar     = Color3.fromRGB(11,   8,  21),
        border      = Color3.fromRGB(42,  22,  69),
        border2     = Color3.fromRGB(61,  32,  96),
        purple      = Color3.fromRGB(192, 64, 224),
        purpleDark  = Color3.fromRGB(96,  48, 160),
        purpleSoft  = Color3.fromRGB(128, 96, 168),
        text        = Color3.fromRGB(200,160, 232),
        textDim     = Color3.fromRGB(90,  58, 122),
        orange      = Color3.fromRGB(245,160,  32),
        red         = Color3.fromRGB(224, 64,  64),
        redDark     = Color3.fromRGB(80,  24,  24),
        rowHover    = Color3.fromRGB(28,  18,  42),
        rowActive   = Color3.fromRGB(40,  20,  60),
        toggleOff   = Color3.fromRGB(26,  16,  40),
        toggleOn    = Color3.fromRGB(61,  16,  96),
    }

    -- ── Runtime state ───────────────────────────────────────────
    Core.alive           = true
    Core.uiOpen          = true
    Core.activeTab       = "farming"
    Core.state           = {}
    Core.selectionState  = { selected_element = "Fire" }
    Core.sliderState     = {}
    Core.inputState      = {}
    Core.callbacks       = {}
    Core.dungeonActive   = false  -- true while player is inside a dungeon run
    Core.dungeonTeleportLockUntil = 0
    Core.priorityOwner   = nil
    Core.priorityRanks   = {clan_quests=0, dungeon=1, flags=2, boss=3, auto_cycle=4, eggs=5, king=6}

    -- ── Shared references set during UI build ───────────────────
    Core.questTitleLabels = {}
    Core.questTitleCache  = {}

    function Core.getLogsConfig()
        Core.config = Core.config or {}
        Core.config.Logs = Core.config.Logs or {}
        if type(Core.config.Logs.Pets) ~= "table" then
            Core.config.Logs.Pets = {Enabled=false, WebhookURL=""}
        end
        if type(Core.config.Logs.Pets.Filters) ~= "table" then
            Core.config.Logs.Pets.Filters = {}
        end
        if type(Core.config.Logs.Dungeon) ~= "table" then
            Core.config.Logs.Dungeon = {EggTimerLogs=false}
        end
        if type(Core.config.Logs.DiscordMonitor) ~= "table" then
            Core.config.Logs.DiscordMonitor = {
                Enabled=false, WebhookURL="", UpdateInterval=10, MessageId=nil,
            }
        end
        local pets = Core.config.Logs.Pets
        if pets.Enabled == nil then pets.Enabled = false end
        if pets.WebhookURL == nil then pets.WebhookURL = "" end
        local dungeon = Core.config.Logs.Dungeon
        if dungeon.EggTimerLogs == nil then dungeon.EggTimerLogs = false end
        local monitor = Core.config.Logs.DiscordMonitor
        if monitor.ShowElementLevels == nil then monitor.ShowElementLevels = false end
        if monitor.ShowMasteryLevels == nil then monitor.ShowMasteryLevels = false end
        if monitor.ShowDungeonEggs == nil then monitor.ShowDungeonEggs = false end
        if monitor.ShowSessionStats == nil then monitor.ShowSessionStats = false end
        if monitor.ShowConnectionStats == nil then monitor.ShowConnectionStats = false end
        return Core.config.Logs
    end

    function Core.syncLogsConfig()
        local logs = Core.getLogsConfig()
        logs.Pets.Enabled = Core.state.pet_webhook_enabled == true
        logs.Pets.WebhookURL = tostring(Core.inputState.pet_webhook_url or "")
        logs.Pets.Filters.OneStar = Core.state.pet_webhook_1star == true
        logs.Pets.Filters.TwoStar = Core.state.pet_webhook_2star == true
        logs.Pets.Filters.ThreeStar = Core.state.pet_webhook_3star == true
        logs.Pets.Filters.FourStar = Core.state.pet_webhook_4star == true
        logs.Pets.Filters.FiveStar = Core.state.pet_webhook_5star == true
        logs.Pets.Filters.OneMoon = Core.state.pet_webhook_1moon == true
        logs.Pets.Filters.TwoMoon = Core.state.pet_webhook_2moon == true
        logs.Pets.Filters.ThreeMoon = Core.state.pet_webhook_3moon == true
        logs.Pets.Filters.Secret = Core.state.pet_webhook_secret == true

        logs.Dungeon.EggTimerLogs = Core.state.dungeon_egg_timer_logs == true

        local monitor = logs.DiscordMonitor
        monitor.Enabled = Core.state.discord_monitor_enabled == true
        monitor.WebhookURL = tostring(Core.inputState.discord_monitor_webhook_url or "")
        monitor.UpdateInterval = math.max(5, tonumber(Core.inputState.discord_monitor_update_interval) or tonumber(monitor.UpdateInterval) or 10)
        monitor.ShowElementLevels = Core.state.discord_monitor_show_element_levels == true
        monitor.ShowMasteryLevels = Core.state.discord_monitor_show_mastery_levels == true
        monitor.ShowDungeonEggs = Core.state.discord_monitor_show_dungeon_eggs == true
        monitor.ShowSessionStats = Core.state.discord_monitor_show_session_stats == true
        monitor.ShowConnectionStats = Core.state.discord_monitor_show_connection_stats == true
        Core.inputState.discord_monitor_update_interval = tostring(monitor.UpdateInterval)
        if monitor.MessageId ~= nil and tostring(monitor.MessageId) == "" then
            monitor.MessageId = nil
        end
        return logs
    end

    function Core.applyLogsConfig(savedLogs)
        if type(savedLogs) ~= "table" then return end
        local logs = Core.getLogsConfig()
        local pets = type(savedLogs.Pets) == "table" and savedLogs.Pets or nil
        local dungeon = type(savedLogs.Dungeon) == "table" and savedLogs.Dungeon
            or type(savedLogs.dungeon) == "table" and savedLogs.dungeon
            or nil
        local monitor = type(savedLogs.DiscordMonitor) == "table" and savedLogs.DiscordMonitor or nil

        local function applyBool(source, field, stateKey)
            if type(source) == "table" and type(source[field]) == "boolean" then
                Core.state[stateKey] = source[field]
            end
        end

        if pets then
            if type(pets.Enabled) == "boolean" then Core.state.pet_webhook_enabled = pets.Enabled end
            if pets.WebhookURL ~= nil then Core.inputState.pet_webhook_url = tostring(pets.WebhookURL) end

            local filters = type(pets.Filters) == "table" and pets.Filters
                or type(pets.filters) == "table" and pets.filters
                or nil
            local petFilters = {
                {key="pet_webhook_1star", names={"pet_webhook_1star","OneStar","1Star"}},
                {key="pet_webhook_2star", names={"pet_webhook_2star","TwoStar","2Star"}},
                {key="pet_webhook_3star", names={"pet_webhook_3star","ThreeStar","3Star"}},
                {key="pet_webhook_4star", names={"pet_webhook_4star","FourStar","4Star"}},
                {key="pet_webhook_5star", names={"pet_webhook_5star","FiveStar","5Star"}},
                {key="pet_webhook_1moon", names={"pet_webhook_1moon","OneMoon","1Moon"}},
                {key="pet_webhook_2moon", names={"pet_webhook_2moon","TwoMoon","2Moon"}},
                {key="pet_webhook_3moon", names={"pet_webhook_3moon","ThreeMoon","3Moon"}},
                {key="pet_webhook_secret", names={"pet_webhook_secret","Secret"}},
            }
            for _, filter in ipairs(petFilters) do
                for _, field in ipairs(filter.names) do
                    applyBool(pets, field, filter.key)
                    applyBool(filters, field, filter.key)
                end
            end
        end

        if dungeon then
            applyBool(dungeon, "EggTimerLogs", "dungeon_egg_timer_logs")
            applyBool(dungeon, "Enabled", "dungeon_egg_timer_logs")
            applyBool(dungeon, "dungeon_egg_timer_logs", "dungeon_egg_timer_logs")
        end
        applyBool(savedLogs, "dungeon_egg_timer_logs", "dungeon_egg_timer_logs")

        if monitor then
            if type(monitor.Enabled) == "boolean" then Core.state.discord_monitor_enabled = monitor.Enabled end
            if monitor.WebhookURL ~= nil then Core.inputState.discord_monitor_webhook_url = tostring(monitor.WebhookURL) end
            if monitor.UpdateInterval ~= nil then
                Core.inputState.discord_monitor_update_interval = tostring(math.max(5, tonumber(monitor.UpdateInterval) or 10))
            end
            if type(monitor.ShowElementLevels) == "boolean" then Core.state.discord_monitor_show_element_levels = monitor.ShowElementLevels end
            if type(monitor.ShowMasteryLevels) == "boolean" then Core.state.discord_monitor_show_mastery_levels = monitor.ShowMasteryLevels end
            if type(monitor.ShowDungeonEggs) == "boolean" then Core.state.discord_monitor_show_dungeon_eggs = monitor.ShowDungeonEggs end
            if type(monitor.ShowSessionStats) == "boolean" then Core.state.discord_monitor_show_session_stats = monitor.ShowSessionStats end
            if type(monitor.ShowConnectionStats) == "boolean" then Core.state.discord_monitor_show_connection_stats = monitor.ShowConnectionStats end
            logs.DiscordMonitor.MessageId = monitor.MessageId ~= nil and tostring(monitor.MessageId) or nil
        end

        Core.syncLogsConfig()
    end

    function Core.setCurrentAction(action, ttl)
        local text = tostring(action or "Idle")
        if text == "" then text = "Idle" end
        Core.CurrentAction = text
        local ttlNumber = tonumber(ttl)
        Core.CurrentActionExpiresAt = ttlNumber and ttlNumber > 0 and (os.clock() + ttlNumber) or nil
        if HS.Logs and HS.Logs.DiscordMonitor and HS.Logs.DiscordMonitor.State then
            HS.Logs.DiscordMonitor.State.CurrentAction = text
            HS.Logs.DiscordMonitor.State.CurrentActionExpiresAt = Core.CurrentActionExpiresAt
        end
        return text
    end

    function Core.clearCurrentAction(action)
        local text = action ~= nil and tostring(action) or nil
        if text == nil or Core.CurrentAction == text then
            return Core.setCurrentAction("Idle")
        end
        return Core.getCurrentAction()
    end

    function Core.getCurrentAction()
        if Core.CurrentAction ~= "Idle"
            and Core.CurrentActionExpiresAt
            and os.clock() >= Core.CurrentActionExpiresAt then
            Core.setCurrentAction("Idle")
        end
        return Core.CurrentAction or "Idle"
    end

    -- ── Utility: debug log ──────────────────────────────────────
    function Core.debugLog(...)
        local rawParts = {}
        for i = 1, select("#", ...) do
            rawParts[#rawParts + 1] = tostring(select(i, ...))
        end

        local message = table.concat(rawParts, " ")
        if HS.Logs and HS.Logs.DiscordMonitor and HS.Logs.DiscordMonitor.setLastDebugMessage then
            pcall(HS.Logs.DiscordMonitor.setLastDebugMessage, message)
        end

        if Core.state.debug_mode ~= true then return end
        local parts = {"[Heartsteel]"}
        for _, part in ipairs(rawParts) do
            parts[#parts + 1] = part
        end
        print(table.concat(parts, " "))
    end

    function Core.getClientDataManager()
        if Core.ClientDataManager then return Core.ClientDataManager end
        local ok, data = pcall(function()
            return require(Core.player:WaitForChild("PlayerScripts"):WaitForChild("MainClient"):WaitForChild("ClientDataManager"))
        end)
        if ok then
            Core.ClientDataManager = data
            return data
        end
        Core.debugLog("ClientDataManager require failed:", data)
        return nil
    end

    -- ── Utility: loop while state key is true ───────────────────
    function Core.loopWhile(key, delay, fn)
        if Core.activeLoops[key] then return end
        Core.activeLoops[key] = true
        task.spawn(function()
            while Core.alive and Core.state[key] do
                local ok, err = pcall(fn)
                if not ok then
                    Core.activeLoops[key] = nil
                    error(err)
                end
                task.wait(delay)
            end
            Core.activeLoops[key] = nil
        end)
    end

    -- ── Utility: forward UI action remote ──────────────────────
    function Core.fireUI(...)
        Core.UIActionRemote:FireServer(...)
    end

    -- ── Utility: fast-hit delay selector ───────────────────────
    function Core.getFastHitDelay(normalDelay)
        return Core.state.fast_hit and Core.FAST_HIT_DELAY or normalDelay
    end

    -- ── Character helpers ───────────────────────────────────────
    function Core.getRoot()
        local c = Core.player.Character or Core.player.CharacterAdded:Wait()
        return c:FindFirstChild("HumanoidRootPart")
    end

    function Core.getPriorityRank(name)
        return Core.priorityRanks[name] or 999
    end

    function Core.canUsePriority(name)
        if Core.isWorldTeleportBlocked() then return false end
        local owner = Core.priorityOwner
        return owner == nil or owner == name or Core.getPriorityRank(name) < Core.getPriorityRank(owner)
    end

    function Core.claimPriority(name)
        if not Core.canUsePriority(name) then return false end
        if Core.priorityOwner ~= name then
            Core.debugLog("Priority:", name, "paused", Core.priorityOwner or "idle")
        end
        Core.priorityOwner = name
        return true
    end

    function Core.releasePriority(name)
        if Core.priorityOwner == name then
            Core.priorityOwner = nil
            Core.debugLog("Priority released:", name)
        end
    end

    function Core.waitForPriority(name, shouldContinue)
        local logged = false
        while Core.alive and not Core.canUsePriority(name) do
            if shouldContinue and not shouldContinue() then return false end
            if not logged then
                Core.debugLog("Priority wait:", name, "blocked by", Core.priorityOwner or "dungeon")
                logged = true
            end
            task.wait(0.5)
        end
        return Core.alive and (not shouldContinue or shouldContinue())
    end

    function Core.asCFrame(value)
        if typeof(value) == "CFrame" then return value end
        if typeof(value) == "Vector3" then return CFrame.new(value) end
        return nil
    end

    function Core.ensureElementSafetyPlatform(cf)
        if Core.isWorldTeleportBlocked() then return nil end
        local targetCf = Core.asCFrame(cf)
        if not targetCf then return nil end

        local platform = Core.elementSafetyPlatform
        if not platform or not platform.Parent then
            platform = Instance.new("Part")
            platform.Name = "HeartsteelElementSafetyPlatform"
            platform.Anchored = true
            platform.CanCollide = true
            platform.CanTouch = false
            platform.CanQuery = false
            platform.Transparency = 0.45
            platform.Color = Color3.fromRGB(192, 64, 224)
            platform.Material = Enum.Material.ForceField
            platform.Parent = workspace
            Core.elementSafetyPlatform = platform
        end

        platform.Size = Vector3.new(16, 1, 16)
        platform.CFrame = targetCf * CFrame.new(0, -5, 0)
        return platform
    end

    function Core.getTeleportPriority(reason)
        if reason == "flag capture" then return "flags" end
        if reason == "clan quest" then return "clan_quests" end
        if reason == "boss" then return "boss" end
        if reason == "auto cycle" then return "auto_cycle" end
        if reason == "pet shop" then return "eggs" end
        if reason == "king" then return "king" end
        return nil
    end

    function Core.lockWorldTeleports(seconds)
        Core.dungeonActive = true
        Core.priorityOwner = "dungeon"
        Core.dungeonTeleportLockUntil = math.max(Core.dungeonTeleportLockUntil or 0, os.clock() + (seconds or 20))
    end

    function Core.isWorldTeleportBlocked()
        if Core.dungeonActive and os.clock() < (Core.dungeonTeleportLockUntil or 0) then
            return true
        end

        local dungeon = HS.Dungeon
        if dungeon and type(dungeon.isRunProtectionActive) == "function" then
            local ok, protected = pcall(dungeon.isRunProtectionActive)
            if ok and protected then
                Core.dungeonActive = true
                Core.priorityOwner = "dungeon"
                return true
            end
        end

        local dungeonPresence = dungeon and (dungeon.isDungeonPresenceActive or dungeon.isInsideActive)
        if dungeonPresence then
            local ok, inside = pcall(dungeonPresence)
            if ok then
                if inside then
                    Core.dungeonActive = true
                    if dungeon and type(dungeon.markRunActive) == "function" then
                        pcall(dungeon.markRunActive, "presence")
                    end
                    return true
                end

                if Core.priorityOwner == "dungeon" then
                    Core.priorityOwner = nil
                end
                Core.dungeonActive = false
                return Core.dungeonActive
            end
        end
        return Core.dungeonActive == true
    end

    function Core.waitForWorldTeleport(reason, shouldContinue)
        local logged = false
        while Core.alive and Core.isWorldTeleportBlocked() do
            if shouldContinue and not shouldContinue() then return false end
            if not logged then
                Core.debugLog("World teleport paused during dungeon:", reason or "unknown")
                logged = true
            end
            task.wait(1)
        end
        return Core.alive and (not shouldContinue or shouldContinue())
    end

    function Core.teleportWorld(cf, reason, shouldContinue)
        if not Core.waitForWorldTeleport(reason, shouldContinue) then return false end
        local priorityName = Core.getTeleportPriority(reason)
        if priorityName then
            if not Core.waitForPriority(priorityName, shouldContinue) then return false end
            if not Core.claimPriority(priorityName) then return false end
        else
            local logged = false
            while Core.alive and Core.priorityOwner do
                if shouldContinue and not shouldContinue() then return false end
                if not logged then
                    Core.debugLog("World teleport waiting for priority owner:", reason or "unknown", Core.priorityOwner)
                    logged = true
                end
                task.wait(0.5)
            end
        end
        local root = Core.getRoot()
        if not root then return false end
        root.CFrame = typeof(cf) == "Vector3" and CFrame.new(cf) or cf
        return true
    end

    function Core.getEquippedRemote()
        local c = Core.player.Character or Core.player.CharacterAdded:Wait()
        for _, v in ipairs(c:GetChildren()) do
            local r = v:FindFirstChild("RemoteClick")
            if r and r:IsA("RemoteEvent") then return r end
        end
    end

    -- ── Compact-number parser ────────────────────────────────────
    function Core.parseCompactNumber(text)
        if type(text) ~= "string" then return 0 end
        local cleaned = text:gsub(",", ""):gsub("%s+", "")
        local numText, suffix = cleaned:match("([%d%.]+)([KMBT]?)")
        local value = tonumber(numText)
        if not value then return 0 end
        local mult = ({K=1e3,M=1e6,B=1e9,T=1e12})[suffix] or 1
        return value * mult
    end
end
