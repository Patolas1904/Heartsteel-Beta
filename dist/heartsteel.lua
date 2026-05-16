--// HEARTSTEEL — Saber Simulator Helper v3
--// Refactored: modular architecture to eliminate "Out of local registers" error

-- ══════════════════════════════════════════════════════════════════
-- SERVICE PROXY  (eliminates ~10 top-level service locals)
-- ══════════════════════════════════════════════════════════════════
local S = setmetatable({}, {
    __index = function(_, k) return game:GetService(k) end
})

-- ══════════════════════════════════════════════════════════════════
-- MODULE TABLE
-- ══════════════════════════════════════════════════════════════════
local HS = {}
HS.Core    = {}   -- state, config, shared utilities
HS.UI      = {}   -- all GUI construction & rendering
HS.Farming = {}   -- swing/sell/boss/flags/koth/clan loops
HS.Dungeon = {}   -- dungeon farming, eggs, chest, timer, auto-start
HS.PetdexFarm = {} -- petdex egg completion
HS.PetdexRewards = {} -- petdex reward claiming
HS.EggOpener = {} -- selected egg auto opener
HS.Pets    = {}   -- pet inventory automation
HS.Merchant = {} -- traveling merchant auto-buy
HS.Flags   = {}   -- flag capture subsystem
HS.Misc    = {}   -- speed, element, anti-afk, position helpers
HS.Logs    = {}   -- Discord/webhook logging
HS.Session = {}   -- persistent saved UI/session state
HS.Meta    = {
    name = "Heartsteel",
    version = "3.0",
    build = "2026-05-10-testing-mode",
    runtimeKey = "__HeartsteelHS",
    expectedLoader = "https://pastebin.com/raw/Lmvyg8cu",
    loadedAtUnix = os.time(),
}

if type(getgenv) == "function" then
    getgenv().__HeartsteelHS = HS
end

-- ══════════════════════════════════════════════════════════════════
-- CORE — CONFIG & STATE
-- ══════════════════════════════════════════════════════════════════
do
    local Core = HS.Core

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

-- ══════════════════════════════════════════════════════════════════
-- MISC — speed, element, anti-afk, position helpers
-- ══════════════════════════════════════════════════════════════════
-- SESSION - persistent controls between script runs
do
    local Session = HS.Session
    local Core    = HS.Core

    Session.FILE_NAME     = "heartsteel_session.json"
    Session.loaded        = false
    Session.lastMessage   = "No session loaded"
    Session.statusLabel   = nil
    Session.isResetting   = false
    Session.suppressSave  = false

    local function getGlobal(name)
        if type(getgenv) == "function" then
            local env = getgenv()
            if type(env[name]) == "function" then return env[name] end
        end
        if type(_G[name]) == "function" then return _G[name] end
        if type(getfenv) == "function" then
            local env = getfenv()
            if type(env[name]) == "function" then return env[name] end
        end
        return nil
    end

    local function hasGlobal(name)
        return getGlobal(name) ~= nil
    end

    local function callGlobal(name, ...)
        local fn = getGlobal(name)
        if not fn then return false, "missing " .. name end
        return pcall(fn, ...)
    end

    function Session.isAvailable()
        return hasGlobal("isfile") and hasGlobal("readfile") and hasGlobal("writefile")
    end

    function Session.setStatus(text)
        Session.lastMessage = text
        if Session.statusLabel and Session.statusLabel.Parent then
            Session.statusLabel.Text = text
        end
    end

    local function clearTable(tbl)
        if type(tbl) ~= "table" then return end
        for key in pairs(tbl) do
            tbl[key] = nil
        end
    end

    function Session.countKeys(tbl)
        local count = 0
        if type(tbl) == "table" then
            for _ in pairs(tbl) do
                count += 1
            end
        end
        return count
    end

    function Session.defaultLogsConfig()
        return {
            Pets = {
                Enabled = false,
                WebhookURL = "",
                Filters = {
                    OneStar = false,
                    TwoStar = false,
                    ThreeStar = false,
                    FourStar = false,
                    FiveStar = false,
                    OneMoon = false,
                    TwoMoon = false,
                    ThreeMoon = false,
                    Secret = false,
                },
            },
            Dungeon = {
                EggTimerLogs = false,
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
        }
    end

    function Session.applyUiDefaults()
        Core.state = Core.state or {}
        Core.selectionState = Core.selectionState or {}
        Core.sliderState = Core.sliderState or {}
        Core.inputState = Core.inputState or {}
        Core.callbacks = Core.callbacks or {}

        clearTable(Core.state)
        clearTable(Core.selectionState)
        clearTable(Core.sliderState)
        clearTable(Core.inputState)
        clearTable(Core.callbacks)

        Core.selectionState.selected_element = "Fire"

        local uiData = HS.UI and HS.UI.UI_DATA
        if type(uiData) ~= "table" then return end

        for _, tabData in pairs(uiData) do
            local items = type(tabData) == "table" and tabData.items or nil
            if type(items) == "table" then
                for _, item in ipairs(items) do
                    if item.type == "toggle" and item.key then
                        Core.state[item.key] = item.default == true
                        Core.callbacks[item.key] = item.callback
                    elseif item.type == "selection" and item.key then
                        Core.selectionState[item.key] = item.default or (item.options and item.options[1]) or ""
                    elseif item.type == "slider" and item.key then
                        Core.sliderState[item.key] = item.default or item.min or 0
                    elseif item.type == "input" and item.key then
                        Core.inputState[item.key] = item.default or ""
                    end
                end
            end
        end
    end

    function Session.syncResetSystems()
        Core.priorityOwner = nil
        Core.activeCycleKey = nil

        if HS.AutoCycle and HS.AutoCycle.stop then
            pcall(HS.AutoCycle.stop)
        end
        if HS.ElementZonePull and HS.ElementZonePull.stopElementNoclip then
            pcall(HS.ElementZonePull.stopElementNoclip)
        end
        if HS.Misc and HS.Misc.stopSpeed then
            pcall(HS.Misc.stopSpeed)
        end
        if HS.Misc and HS.Misc.applyHideEggAnimations then
            pcall(HS.Misc.applyHideEggAnimations, false)
        end
        if HS.Logs and HS.Logs.DiscordMonitor then
            if HS.Logs.DiscordMonitor.setMessageId then
                pcall(HS.Logs.DiscordMonitor.setMessageId, nil, true)
            end
            if HS.Logs.DiscordMonitor.stop then
                pcall(HS.Logs.DiscordMonitor.stop)
            end
        end
        if HS.Logs and HS.Logs.Pets and HS.Logs.Pets.syncConnection then
            pcall(HS.Logs.Pets.syncConnection)
        end
        if HS.Logs and HS.Logs.Dungeon and HS.Logs.Dungeon.clearRows then
            pcall(HS.Logs.Dungeon.clearRows)
        end
    end

    function Session.runDefaultCallbacks()
        local uiData = HS.UI and HS.UI.UI_DATA
        if type(uiData) == "table" then
            for _, tabData in pairs(uiData) do
                local items = type(tabData) == "table" and tabData.items or nil
                if type(items) == "table" then
                    for _, item in ipairs(items) do
                        if item.type == "slider" and item.key and item.callback then
                            pcall(item.callback, Core.sliderState[item.key])
                        elseif item.type == "selection" and item.key and item.instant and item.callback then
                            pcall(item.callback, Core.selectionState[item.key])
                        end
                    end
                end
            end
        end

        for key, on in pairs(Core.state) do
            local cb = Core.callbacks[key]
            if on and cb then
                task.spawn(function()
                    local ok, err = pcall(cb, true)
                    if not ok then
                        Core.debugLog("Default callback failed:", key, tostring(err))
                    end
                end)
            end
        end
    end

    function Session.resetRuntimeToDefaults()
        Session.applyUiDefaults()
        Core.config = {
            Logs = Session.defaultLogsConfig(),
        }
        if Core.syncLogsConfig then
            pcall(Core.syncLogsConfig)
        end
        Session.syncResetSystems()
        Session.runDefaultCallbacks()
        Core.debugLog(
            "Session reset cleared in-memory state:",
            "state keys", Session.countKeys(Core.state),
            "input keys", Session.countKeys(Core.inputState),
            "slider keys", Session.countKeys(Core.sliderState),
            "selection keys", Session.countKeys(Core.selectionState)
        )
    end

    function Session.load()
        if not Session.isAvailable() then
            Session.setStatus("Session unavailable: file API missing")
            return nil
        end

        local okIsFile, exists = callGlobal("isfile", Session.FILE_NAME)
        if not okIsFile or not exists then
            Session.setStatus("No saved session")
            return nil
        end

        local okRead, raw = callGlobal("readfile", Session.FILE_NAME)
        if okRead and raw == "" then
            Session.setStatus("No saved session")
            return nil
        end
        if not okRead or type(raw) ~= "string" then
            Session.setStatus("Saved session could not be read")
            return nil
        end

        local okDecode, data = pcall(function()
            return S.HttpService:JSONDecode(raw)
        end)
        if not okDecode or type(data) ~= "table" then
            Session.setStatus("Saved session is invalid")
            return nil
        end

        Session.loaded = true
        Session.setStatus("Saved session loaded")
        Core.debugLog(
            "Session load path:", Session.FILE_NAME,
            "state keys count:", Session.countKeys(type(data.state) == "table" and data.state or data.toggles),
            "input keys count:", Session.countKeys(type(data.inputState) == "table" and data.inputState or data.inputs),
            "slider keys count:", Session.countKeys(type(data.sliderState) == "table" and data.sliderState or data.sliders),
            "selection keys count:", Session.countKeys(type(data.selectionState) == "table" and data.selectionState or data.selections),
            "has Logs config:", tostring(type(data.Logs) == "table" or (type(data.config) == "table" and type(data.config.Logs) == "table"))
        )
        return data
    end

    function Session.save()
        if Session.suppressSave then
            Session.setStatus("Session save suppressed")
            return false
        end

        if Session.isResetting then
            Session.setStatus("Session reset in progress")
            return false
        end

        if not Session.isAvailable() then
            Session.setStatus("Session unavailable: file API missing")
            return false
        end

        if Core.syncLogsConfig then
            pcall(Core.syncLogsConfig)
        end

        local data = {
            version = 2,
            state = Core.state,
            selectionState = Core.selectionState,
            sliderState = Core.sliderState,
            inputState = Core.inputState,
            config = Core.config,
            toggles = Core.state,
            selections = Core.selectionState,
            sliders = Core.sliderState,
            inputs = Core.inputState,
            Logs = Core.getLogsConfig and Core.getLogsConfig() or nil,
        }
        Core.debugLog(
            "Session save path:", Session.FILE_NAME,
            "state keys count:", Session.countKeys(Core.state),
            "input keys count:", Session.countKeys(Core.inputState),
            "slider keys count:", Session.countKeys(Core.sliderState),
            "selection keys count:", Session.countKeys(Core.selectionState),
            "has Logs config:", tostring(type(data.Logs) == "table")
        )
        local okEncode, encoded = pcall(function()
            return S.HttpService:JSONEncode(data)
        end)
        if not okEncode then
            Session.setStatus("Session save failed: encode error")
            return false
        end

        local okWrite = callGlobal("writefile", Session.FILE_NAME, encoded)
        if not okWrite then
            Session.setStatus("Session save failed: write error")
            return false
        end

        Session.setStatus("Session saved")
        return true
    end

    function Session.resetNextStartup()
        if Session.isResetting then return false end

        Session.isResetting = true
        Session.setStatus("Resetting saved session")
        Core.debugLog("Session reset deleting:", Session.FILE_NAME)

        if hasGlobal("delfile") then
            local okIsFile, exists = callGlobal("isfile", Session.FILE_NAME)
            if okIsFile and exists then
                local okDelete = callGlobal("delfile", Session.FILE_NAME)
                if not okDelete then
                    Session.isResetting = false
                    Session.setStatus("Reset failed: delete error")
                    return false
                end
            end
        elseif Session.isAvailable() then
            local okWrite = callGlobal("writefile", Session.FILE_NAME, "")
            if not okWrite then
                Session.isResetting = false
                Session.setStatus("Reset failed: write error")
                return false
            end
        else
            Session.isResetting = false
            Session.setStatus("Reset unavailable: file API missing")
            return false
        end

        Session.loaded = false
        Session.resetRuntimeToDefaults()
        if HS.UI and HS.UI.renderContent then
            pcall(HS.UI.renderContent)
        end
        Core.debugLog("Session reset completed:", Session.FILE_NAME)
        Session.isResetting = false
        Session.setStatus("Session reset; defaults restored")
        return true
    end
end

do
    local Misc   = HS.Misc
    local Core   = HS.Core

-- HEARTSTEEL_MODULE_START: MiscSpeed
-- Bundled from src/modules/MiscSpeed.lua
do
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
-- HEARTSTEEL_MODULE_END: MiscSpeed
-- HEARTSTEEL_MODULE_START: MiscConfig
-- Bundled from src/modules/MiscConfig.lua
do
    local Misc = HS.Misc or {}
    HS.Misc = Misc

    Misc.ANTI_AFK_DELAY     = 20
    Misc.SIM_MOVE_DELAY     = 20
    Misc.SIM_MOVE_DISTANCE  = 1.5
    Misc.SIM_MOVE_WAIT      = 0.12

    Misc.ELEMENT_OPTIONS = {"Fire","Water","Earth","Plasma"}
end
-- HEARTSTEEL_MODULE_END: MiscConfig

    -- ── Element ─────────────────────────────────────────────────
-- HEARTSTEEL_MODULE_START: MiscElement
-- Bundled from src/modules/MiscElement.lua
do
    local Misc = HS.Misc or {}
    HS.Misc = Misc

    local Core = HS.Core

    function Misc.applyElement(selectedValue)
        Core.UIActionRemote:FireServer("ChangeElement", selectedValue or Core.selectionState.selected_element)
    end
end
-- HEARTSTEEL_MODULE_END: MiscElement

    -- ── Position helpers ─────────────────────────────────────────
-- HEARTSTEEL_MODULE_START: MiscPosition
-- Bundled from src/modules/MiscPosition.lua
do
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
-- HEARTSTEEL_MODULE_END: MiscPosition

    -- ── Anti-AFK ─────────────────────────────────────────────────
-- HEARTSTEEL_MODULE_START: MiscAntiAfk
-- Bundled from src/modules/MiscAntiAfk.lua
do
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
-- HEARTSTEEL_MODULE_END: MiscAntiAfk

    -- ── Simulated movement ───────────────────────────────────────
-- HEARTSTEEL_MODULE_START: MiscSimMovement
-- Bundled from src/modules/MiscSimMovement.lua
do
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
-- HEARTSTEEL_MODULE_END: MiscSimMovement

    -- ── Egg animation hide/show ──────────────────────────────────
-- HEARTSTEEL_MODULE_START: MiscEggAnimations
-- Bundled from src/modules/MiscEggAnimations.lua
do
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
-- HEARTSTEEL_MODULE_END: MiscEggAnimations
end

-- ══════════════════════════════════════════════════════════════════
-- FARMING — swing, sell, boss, crowns, KOTH, clan quests
-- ══════════════════════════════════════════════════════════════════
do
    local Farming = HS.Farming
    local Core    = HS.Core

    Farming.BossFolder      = Core.Gameplay and Core.Gameplay:WaitForChild("Boss", 10)
    Farming.BossHolder      = Core.BossHolder
    Farming.BossArenaBase   = Farming.BossFolder and Farming.BossFolder:WaitForChild("ArenaBase", 10)
    Farming.BossTimerLabel  = Farming.BossFolder
        and Farming.BossFolder:WaitForChild("ArenaGui", 10)
        and Farming.BossFolder.ArenaGui:WaitForChild("BillboardGui", 10)
        and Farming.BossFolder.ArenaGui.BillboardGui:WaitForChild("Frame", 10)
        and Farming.BossFolder.ArenaGui.BillboardGui.Frame:WaitForChild("TextLabelBottom", 10)
    Farming.bossHeartbeat   = nil
    Farming.bossAttackThread = nil
    Farming.bossStatusThread = nil
    Farming.bossStatusLabel = nil
    Farming.bossAttacking   = false
    Farming.clanBossActive  = false
    Farming.bossLastTeleport = 0
    Farming.bossLastPriorityLog = 0
    Farming.BOSS_FOLLOW_DISTANCE = 14
    Farming.BOSS_TP_COOLDOWN = 3
    Farming.classesInfoLoaded = false
    Farming.ClassesInfo       = nil
    Farming.classList         = nil
    Farming.classLookup       = nil
    Farming.CLASS_DEBUG       = true

    Farming.crownsConnection = nil

    function Farming.teleportTo(pos, shouldContinue)
        Core.teleportWorld(CFrame.new(pos), "farming/area", shouldContinue)
    end

    function Farming.startSwing()
        Core.loopWhile("swing", Core.SWING_DELAY, function()
            Core.SwingSaberRemote:FireServer()
        end)
    end

    function Farming.startSell()
        Core.loopWhile("sell", Core.SELL_DELAY, function()
            Core.SellStrengthRemote:FireServer()
        end)
    end

    function Farming.tryBuySaber()
        for _, name in ipairs(Core.SABER_BUY_ACTIONS) do
            pcall(Core.fireUI, name); task.wait(0.08)
        end
    end

    function Farming.startSaber()   Core.loopWhile("saber",   Core.BUY_DELAY, Farming.tryBuySaber) end
    function Farming.startDNA()     Core.loopWhile("dna",     Core.BUY_DELAY, function() Core.fireUI("BuyAllDNAs") end) end

    function Farming.classDebug(...)
        if not Farming.CLASS_DEBUG or Core.state.debug_mode ~= true then return end
        local parts = {"[Heartsteel][Class]"}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        print(table.concat(parts, " "))
    end

    function Farming.getClassesInfo()
        if Farming.classesInfoLoaded then return Farming.ClassesInfo end
        Farming.classesInfoLoaded = true
        local ok, info = pcall(function()
            return require(S.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemInfo"):WaitForChild("Classes"))
        end)
        if ok and type(info) == "table" then
            Farming.ClassesInfo = info
            Farming.classDebug("ClassesInfo required successfully")
            return info
        end
        Farming.classDebug("ClassesInfo require failed:", info)
        Farming.ClassesInfo = nil
        return nil
    end

    function Farming.cleanClassText(value)
        if value == nil then return nil end
        local raw = nil
        if type(value) == "string" or type(value) == "number" then
            raw = tostring(value)
        elseif typeof(value) == "Instance" then
            local ok, text = pcall(function()
                return value.Text
            end)
            if ok then
                raw = tostring(text or "")
            else
                ok, text = pcall(function()
                    return value.Value
                end)
                if ok then raw = tostring(text or "") end
            end
        end
        if not raw then return nil end
        raw = raw:gsub("<[^>]->", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
        return raw ~= "" and raw or nil
    end

    function Farming.classKey(value)
        local text = Farming.cleanClassText(value)
        return text and text:lower():gsub("[^%w]+", "") or nil
    end

    function Farming.readNumber(value)
        if type(value) == "number" then return value end
        if type(value) == "string" then
            local cleaned = value:gsub(",", ""):gsub("%s+", "")
            local direct = tonumber(cleaned)
            if direct then return direct end
            local compact = Core.parseCompactNumber(value)
            if compact > 0 or cleaned:match("^0+$") then return compact end
        elseif typeof(value) == "Instance" then
            local ok, instanceValue = pcall(function()
                return value.Value
            end)
            if not ok then
                ok, instanceValue = pcall(function()
                    return value.Text
                end)
            end
            if ok then return Farming.readNumber(instanceValue) end
        end
        return nil
    end

    function Farming.getClassEntryName(key, item)
        if type(item) == "table" then
            for _, field in ipairs({"Name","ClassName","DisplayName","Title","Id","ID"}) do
                local name = Farming.cleanClassText(item[field])
                if name then return name end
            end
        elseif type(item) == "number" and type(key) == "string" then
            return Farming.cleanClassText(key)
        elseif type(item) == "string" or type(item) == "number" then
            local name = Farming.cleanClassText(item)
            if name then return name end
        end
        return type(key) == "string" and Farming.cleanClassText(key) or nil
    end

    function Farming.getClassOrderValue(key, item, fallback)
        if type(item) == "table" then
            for _, field in ipairs({"Order","Index","SortOrder","LayoutOrder","Rank","Level"}) do
                local order = tonumber(item[field])
                if order then return order end
            end
        end
        return tonumber(key) or fallback
    end

    function Farming.readClassCostValue(value)
        local cost = Farming.readNumber(value)
        if cost then return cost, nil end
        if type(value) ~= "table" then return nil, nil end
        if tonumber(value[1]) and tonumber(value[2]) then return nil, value.Currency end
        local currency = value.Currency or value.CurrencyType or value.Type or value.Name
        for _, field in ipairs({"Amount","Price","Cost","Value","Required","Requirement"}) do
            cost = Farming.readNumber(value[field])
            if cost then return cost, currency end
        end
        for key, amount in pairs(value) do
            cost = Farming.readNumber(amount)
            if cost then return cost, tostring(key) end
        end
        return nil, currency
    end

    function Farming.normalizePriceParts(mantissa, exponent)
        mantissa = tonumber(mantissa)
        exponent = tonumber(exponent) or 0
        if not mantissa then return nil, nil end
        if mantissa == math.huge or mantissa ~= mantissa then return nil, nil end
        if mantissa <= 0 then return 0, 0 end
        local shift = math.floor(math.log(mantissa) / math.log(10))
        mantissa = mantissa / (10 ^ shift)
        exponent += shift
        return mantissa, exponent
    end

    function Farming.getClassPriceParts(item)
        if type(item) ~= "table" then return nil, nil, "nil" end
        local price = item.Price or item.Cost or item.Required or item.Requirement
        if type(price) == "number" then
            local mantissa, exponent = Farming.normalizePriceParts(price, 0)
            return mantissa, exponent, tostring(price)
        end
        if type(price) == "table" then
            local mantissa = price[1] or price.Mantissa or price.mantissa or price.Value or price.value
            local exponent = price[2] or price.Exponent or price.exponent or price.Power or price.power
            mantissa, exponent = Farming.normalizePriceParts(mantissa, exponent)
            if mantissa and exponent then
                return mantissa, exponent, tostring(mantissa) .. "e" .. tostring(exponent)
            end
        end
        return nil, nil, "nil"
    end

    function Farming.getClassCost(entry)
        local item = entry and entry.raw
        if type(item) ~= "table" then return nil, nil end
        local currency = item.Currency or item.CurrencyType or item.PriceType or item.CostType
        for _, field in ipairs({
            "CoinsPrice","CoinPrice","CrownsPrice","CrownPrice","StrengthPrice",
            "RequiredCoins","RequiredCrowns","RequiredStrength",
            "Price","Cost","Required","Requirement",
        }) do
            local cost, costCurrency = Farming.readClassCostValue(item[field])
            if cost then
                if not currency then currency = costCurrency end
                if not currency and field:lower():find("crown", 1, true) then currency = "Crowns" end
                if not currency and field:lower():find("strength", 1, true) then currency = "Strength" end
                if not currency and field:lower():find("coin", 1, true) then currency = "Coins" end
                return cost, currency
            end
        end
        return nil, currency
    end

    function Farming.getClassSource(info)
        if type(info) ~= "table" then return nil end
        for _, field in ipairs({"Classes","Items","List","ClassList"}) do
            if type(info[field]) == "table" then return info[field] end
        end
        return info
    end

    function Farming.buildClassList()
        if Farming.classList then return Farming.classList, Farming.classLookup end
        local info = Farming.getClassesInfo()
        local source = Farming.getClassSource(info)
        local list, seen = {}, {}

        local function addClass(key, item, fallbackOrder)
            if type(item) == "function" then return end
            if type(key) == "string" and ({
                Classes=true, Items=true, List=true, ClassList=true,
                ClassOrder=true, Order=true, Progression=true, ProgressionOrder=true,
                CurrentClass=true, EquippedClass=true, CurrentRank=true,
            })[key] then return end
            local name = Farming.getClassEntryName(key, item)
            local classKey = Farming.classKey(name)
            if not classKey or seen[classKey] then return end
            local entry = {
                name=name,
                raw=type(item) == "table" and item or (type(item) == "number" and {Price=item} or {}),
                order=Farming.getClassOrderValue(key, item, fallbackOrder),
                insertOrder=#list + 1,
            }
            entry.cost, entry.currency = Farming.getClassCost(entry)
            entry.priceMantissa, entry.priceExponent, entry.priceText = Farming.getClassPriceParts(entry.raw)
            seen[classKey] = true
            list[#list + 1] = entry
        end

        if type(source) == "table" then
            local explicitOrder = info.ClassOrder or info.Order or info.Progression or info.ProgressionOrder
            if type(explicitOrder) == "table" then
                local addedExplicitOrder = false
                for index, name in ipairs(explicitOrder) do
                    local item = type(name) == "table" and name or source[name] or source[tostring(name)]
                    addClass(name, item or name, index)
                    addedExplicitOrder = true
                end
                if not addedExplicitOrder then
                    for name, order in pairs(explicitOrder) do
                        local item = source[name] or source[tostring(name)]
                        addClass(name, item or name, tonumber(order) or (#list + 1))
                    end
                end
            end
            for key, item in ipairs(source) do addClass(key, item, key) end
            for key, item in pairs(source) do addClass(key, item, nil) end
        end

        table.sort(list, function(a, b)
            if a.order and b.order and a.order ~= b.order then return a.order < b.order end
            if (a.order ~= nil) ~= (b.order ~= nil) then return a.order ~= nil end
            local aExp = a.priceExponent or math.huge
            local bExp = b.priceExponent or math.huge
            if aExp ~= bExp then return aExp < bExp end
            local aMantissa = a.priceMantissa or math.huge
            local bMantissa = b.priceMantissa or math.huge
            if aMantissa ~= bMantissa then return aMantissa < bMantissa end
            return a.name < b.name
        end)

        local lookup = {}
        for index, entry in ipairs(list) do
            lookup[Farming.classKey(entry.name)] = index
        end
        Farming.classList = list
        Farming.classLookup = lookup
        Farming.classDebug("Class list built:", #list, "classes")
        for index, entry in ipairs(list) do
            Farming.classDebug(
                "Class", index,
                "name=", entry.name,
                "order=", entry.order,
                "price=", entry.priceText or "nil",
                "cost=", entry.cost or "nil",
                "currency=", entry.currency or "nil"
            )
        end
        return list, lookup
    end

    function Farming.resolveClassName(value)
        local list, lookup = Farming.buildClassList()
        if not list or #list == 0 then return nil end
        if type(value) == "number" then
            return (list[value] and list[value].name) or (list[value + 1] and list[value + 1].name)
        end

        local text = Farming.cleanClassText(value)
        if not text then return nil end
        local numeric = tonumber(text)
        if numeric then
            return (list[numeric] and list[numeric].name) or (list[numeric + 1] and list[numeric + 1].name)
        end

        local index = lookup[Farming.classKey(text)]
        if index then return list[index].name end

        local haystack = text:lower()
        local bestName, bestLength = nil, 0
        for _, entry in ipairs(list) do
            local name = entry.name:lower()
            if haystack:find(name, 1, true) and #name > bestLength then
                bestName, bestLength = entry.name, #name
            end
        end
        return bestName
    end

    function Farming.resolveClassCandidate(value)
        if type(value) == "table" then
            for _, field in ipairs({"CurrentClass","EquippedClass","Class","ClassName","Name","Rank","RankName","CurrentRank","Current","Equipped","Value"}) do
                local className = Farming.resolveClassName(value[field])
                if className then return className end
            end
            return nil
        end
        return Farming.resolveClassName(value)
    end

    function Farming.getCurrentClassFromClientData()
        local ClientData = Core.getClientDataManager()
        local data = ClientData and ClientData.Data
        if type(data) ~= "table" then return nil end
        local directFields = {
            "CurrentClass","EquippedClass","Class","ClassName","PlayerClass",
            "Rank","RankName","CurrentRank","ClassIndex","CurrentClassIndex","RankIndex",
            "Classes","ClassData","RankData",
        }
        for _, field in ipairs(directFields) do
            local className = Farming.resolveClassCandidate(data[field])
            if className then return className end
        end
        for _, containerName in ipairs({"PlayerData","Stats"}) do
            local container = data[containerName]
            if type(container) == "table" then
                for _, field in ipairs({"CurrentClass","EquippedClass","Class","ClassName","Rank","RankName","CurrentRank","Classes","ClassData","RankData"}) do
                    local className = Farming.resolveClassCandidate(container[field])
                    if className then return className end
                end
            end
        end
        return nil
    end

    function Farming.getCurrentClassFromClassesInfo()
        local info = Farming.getClassesInfo()
        if type(info) ~= "table" then return nil end
        return Farming.resolveClassCandidate(info.CurrentClass or info.EquippedClass or info.Current)
    end

    function Farming.getCurrentClassFromFallbackTag()
        local character = workspace:FindFirstChild("SlipKatarinas")
        if not character then
            Farming.classDebug("Tag1 current class failed: workspace.SlipKatarinas missing")
            return nil
        end
        local head = character and character:FindFirstChild("Head")
        if not head then
            Farming.classDebug("Tag1 current class failed: SlipKatarinas.Head missing")
            return nil
        end
        local rankingGui = head and head:FindFirstChild("RankingGui")
        if not rankingGui then
            Farming.classDebug("Tag1 current class failed: RankingGui missing")
            return nil
        end
        local tag = rankingGui and rankingGui:FindFirstChild("Tag1")
        if not tag then
            Farming.classDebug("Tag1 current class failed: Tag1 missing")
            return nil
        end
        local raw = Farming.cleanClassText(tag)
        local resolved = Farming.resolveClassCandidate(tag)
        Farming.classDebug("Tag1 current class raw=", raw or "nil", "resolved=", resolved or "nil")
        return resolved
    end

    function Farming.getCurrentClassName()
        return Farming.getCurrentClassFromClientData()
            or Farming.getCurrentClassFromClassesInfo()
            or Farming.getCurrentClassFromFallbackTag()
    end

    function Farming.getCurrencyNames(currency)
        local hint = tostring(currency or ""):lower()
        if hint:find("crown", 1, true) then return {"Crowns","Crown","TotalCrowns","CrownsAmount"} end
        if hint:find("strength", 1, true) then return {"Strength","TotalStrength","StoredStrength","StrengthAmount"} end
        return {"Coins","Coin","Money","Cash","Gold","CoinsAmount","TotalCoins"}
    end

    function Farming.findDataNumber(container, names)
        if type(container) ~= "table" then return nil end
        for _, name in ipairs(names) do
            local value = Farming.readNumber(container[name])
            if value ~= nil then return value end
            local wanted = tostring(name):lower()
            for key, candidate in pairs(container) do
                if type(key) == "string" and key:lower() == wanted then
                    value = Farming.readNumber(candidate)
                    if value ~= nil then return value end
                end
            end
        end
        return nil
    end

    function Farming.getCurrencyAmount(currency)
        local names = Farming.getCurrencyNames(currency)
        local ClientData = Core.getClientDataManager()
        local data = ClientData and ClientData.Data
        local containers = {}
        local function addContainer(container)
            if type(container) == "table" then containers[#containers + 1] = container end
        end
        addContainer(data)
        if type(data) == "table" then
            addContainer(data.Currency)
            addContainer(data.Currencies)
            addContainer(data.Stats)
            addContainer(data.PlayerStats)
            addContainer(data.Resources)
        end
        for _, container in ipairs(containers) do
            local amount = Farming.findDataNumber(container, names)
            if amount ~= nil then return amount end
        end

        local leaderstats = Core.player:FindFirstChild("leaderstats")
        if leaderstats then
            for _, name in ipairs(names) do
                local stat = leaderstats:FindFirstChild(name)
                local amount = stat and Farming.readNumber(stat)
                if amount ~= nil then return amount end
            end
        end
        return nil
    end

    function Farming.canBuyClass(entry)
        local cost = entry and entry.cost
        local currency = entry and entry.currency
        if not cost or cost <= 0 then
            Farming.classDebug("Class cost missing/zero, allowing buy:", entry and entry.name or "nil", "price=", entry and entry.priceText or "nil", "cost=", cost or "nil")
            return true, cost, currency
        end
        local amount = Farming.getCurrencyAmount(currency)
        if amount == nil then
            Farming.classDebug("Currency amount unknown, allowing buy:", entry.name, "cost=", cost, "currency=", currency or "nil")
            return true, cost, currency
        end
        Farming.classDebug("Class affordability:", entry.name, "cost=", cost, "currency=", currency or "nil", "amount=", amount, "canBuy=", amount >= cost)
        return amount >= cost, cost, currency, amount
    end

    function Farming.getNextClassEntry()
        local list, lookup = Farming.buildClassList()
        if not list or #list == 0 then
            Farming.classDebug("Next class failed: class info unavailable")
            return nil, "class info unavailable"
        end
        local currentClass = Farming.getCurrentClassName()
        if not currentClass then
            Farming.classDebug("Next class failed: current class unknown from Tag1")
            return nil, "current class unknown"
        end
        local index = lookup[Farming.classKey(currentClass)]
        if not index then
            Farming.classDebug("Next class failed: Tag1 class not in ClassesInfo:", currentClass)
            return nil, "current class not in ClassesInfo: " .. tostring(currentClass)
        end
        local currentEntry = list[index]
        local nextName = currentEntry
            and type(currentEntry.raw) == "table"
            and (currentEntry.raw.NextClass or currentEntry.raw.Next or currentEntry.raw.NextName or currentEntry.raw.NextRank)
        local nextIndex = nextName and lookup[Farming.classKey(nextName)]
        local nextEntry = (nextIndex and list[nextIndex]) or list[index + 1]
        if not nextEntry then
            Farming.classDebug("Next class failed: max class reached", "current=", currentClass, "index=", index)
            return nil, "max class reached"
        end
        Farming.classDebug(
            "Next class resolved:",
            "current=", currentClass,
            "currentIndex=", index,
            "next=", nextEntry.name,
            "nextIndex=", nextIndex or (index + 1),
            "price=", nextEntry.priceText or "nil",
            "cost=", nextEntry.cost or "nil",
            "currency=", nextEntry.currency or "nil"
        )
        return nextEntry, currentClass
    end

    function Farming.readClassName()
        local entry = Farming.getNextClassEntry()
        return entry and entry.name or nil
    end

    function Farming.startClass()
        local lastClassName = nil
        local lastWaitReason = nil
        Core.loopWhile("class", Core.BUY_DELAY, function()
            local entry, currentOrReason = Farming.getNextClassEntry()
            if not entry then
                if currentOrReason ~= lastWaitReason then
                    Farming.classDebug("Auto buy class waiting:", currentOrReason)
                    lastWaitReason = currentOrReason
                end
                return
            end

            local canBuy, cost, currency, amount = Farming.canBuyClass(entry)
            if not canBuy then
                local reason = string.format(
                    "need %s %s, have %s",
                    tostring(cost),
                    tostring(currency or "currency"),
                    tostring(amount)
                )
                if reason ~= lastWaitReason then
                    Farming.classDebug("Auto buy class waiting:", entry.name, reason)
                    lastWaitReason = reason
                end
                return
            end

            if entry.name ~= lastClassName then
                Farming.classDebug("Auto buy class target:", entry.name, "current:", currentOrReason)
                lastClassName = entry.name
                lastWaitReason = nil
            end
            Farming.classDebug("Firing BuyClass remote:", entry.name, "cost=", cost or "nil", "currency=", currency or "nil", "amount=", amount or "nil")
            Core.fireUI("BuyClass", entry.name)
        end)
    end
    function Farming.startBossDmg() Core.loopWhile("bossdmg", Core.BUY_DELAY, function() Core.UIActionRemote:FireServer("BuyAllBossBoosts") end) end
    function Farming.startAura()    Core.loopWhile("aura",    Core.BUY_DELAY, function() Core.fireUI("BuyAllAuras") end) end
    function Farming.startPetAura() Core.loopWhile("petaura", Core.BUY_DELAY, function() Core.fireUI("BuyAllPetAuras") end) end

    function Farming.getBossModel()
        local holder = Farming.BossHolder or Core.BossHolder
        return holder and holder:FindFirstChild("Boss")
    end

    function Farming.getBossRoot()
        local boss = Farming.getBossModel()
        return boss and boss:FindFirstChild("HumanoidRootPart")
    end

    function Farming.isInBossArena(root)
        local arena = Farming.BossArenaBase
        if not root or not arena or not arena:IsA("BasePart") then return false end
        local localPos = arena.CFrame:PointToObjectSpace(root.Position)
        local half = arena.Size * 0.5
        return math.abs(localPos.X) <= half.X
            and math.abs(localPos.Y) <= half.Y + 8
            and math.abs(localPos.Z) <= half.Z
    end

    function Farming.setBossStatus(text, color)
        local lbl = Farming.bossStatusLabel
        if lbl and lbl.Parent then
            lbl.Text = text
            lbl.TextColor3 = color or Core.C.textDim
        end
    end

    function Farming.getBossTimerText()
        local lbl = Farming.BossTimerLabel
        return (lbl and lbl.Parent and lbl.Text and lbl.Text ~= "") and lbl.Text or "waiting for boss"
    end

    function Farming.canUseBossPriority()
        if Farming.clanBossActive and Core.priorityOwner == "clan_quests" then
            return true
        end
        return Core.canUsePriority("boss")
    end

    function Farming.isBossFeatureActive()
        return Core.state.boss or Farming.clanBossActive == true
    end

    function Farming.isBossFarmActive()
        if not Core.alive or not Core.state.boss or not Farming.bossStatusThread then return false end

        local boss = Farming.getBossModel()
        local bossRoot = boss and boss:FindFirstChild("HumanoidRootPart")
        if not boss or not bossRoot then return false end

        if Farming.bossAttacking == true
            or Farming.bossHeartbeat ~= nil
            or Core.priorityOwner == "boss" then
            return true
        end

        local root = Core.getRoot()
        return root ~= nil and Farming.isInBossArena(root) and Farming.canUseBossPriority()
    end

    function Farming.stopBossFollow()
        if Farming.bossHeartbeat then
            Farming.bossHeartbeat:Disconnect()
            Farming.bossHeartbeat = nil
        end
    end

    function Farming.ensureBossFollow()
        if Farming.bossHeartbeat then return end
        Farming.bossHeartbeat = S.RunService.Heartbeat:Connect(function()
            if not Core.alive or not Farming.isBossFeatureActive() then
                Farming.stopBossFollow()
                return
            end

            if not Farming.canUseBossPriority() then
                Farming.stopBossFollow()
                return
            end

            local bossRoot = Farming.getBossRoot()
            local root = Core.getRoot()
            if not bossRoot or not root or not Farming.isInBossArena(root) then
                Farming.stopBossFollow()
                return
            end

            local character = Core.player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not humanoid then return end

            local offset = root.Position - bossRoot.Position
            local distance = offset.Magnitude
            if distance > Farming.BOSS_FOLLOW_DISTANCE and distance > 0.1 then
                local targetPos = bossRoot.Position + offset.Unit * Farming.BOSS_FOLLOW_DISTANCE
                humanoid:MoveTo(targetPos)
            end
        end)
    end

    function Farming.ensureBossAttackLoop()
        if Farming.bossAttackThread then return end
        Farming.bossAttacking = true
        Farming.bossAttackThread = task.spawn(function()
            Core.debugLog("Auto Boss attack loop started")
            while Core.alive and Farming.isBossFeatureActive() and Farming.bossAttacking do
                local boss = Farming.getBossModel()
                local root = Core.getRoot()
                if boss and root and Farming.isInBossArena(root) and Farming.canUseBossPriority() then
                    local remote = Core.getEquippedRemote()
                    if remote then
                        Core.setCurrentAction("Auto Farming Boss", 2)
                        pcall(function() remote:FireServer({boss}) end)
                    end
                end
                task.wait(Core.getFastHitDelay(Core.BOSS_DELAY))
            end
            Farming.bossAttackThread = nil
            Farming.bossAttacking = false
            Core.clearCurrentAction("Auto Farming Boss")
            Core.debugLog("Auto Boss attack loop stopped")
        end)
    end

    function Farming.stopBossAttack()
        Farming.bossAttacking = false
        Core.clearCurrentAction("Auto Farming Boss")
    end

    function Farming.stopBoss()
        Farming.stopBossAttack()
        Farming.stopBossFollow()
        Farming.clanBossActive = false
        Core.releasePriority("boss")
        Farming.setBossStatus("Boss: stopped", Core.C.textDim)
    end

    function Farming.startBoss()
        if Farming.bossStatusThread then return end
        Farming.bossStatusThread = task.spawn(function()
            Core.debugLog("Auto Boss loop started")
            while Core.alive and Core.state.boss do
                local boss = Farming.getBossModel()
                local bossRoot = Farming.getBossRoot()
                local root = Core.getRoot()
                local inArena = Farming.isInBossArena(root)
                local bossSpawned = boss ~= nil and bossRoot ~= nil

                if bossSpawned then
                    if inArena then
                        if Farming.canUseBossPriority() then
                            Core.claimPriority("boss")
                            Farming.ensureBossFollow()
                            Farming.ensureBossAttackLoop()
                            Farming.setBossStatus("Boss: spawned / following", Core.C.orange)
                        else
                            Farming.stopBossFollow()
                            Farming.stopBossAttack()
                            if os.clock() - Farming.bossLastPriorityLog >= 3 then
                                Farming.bossLastPriorityLog = os.clock()
                                Core.debugLog("Auto Boss paused by priority:", Core.priorityOwner or "idle")
                            end
                            Farming.setBossStatus("Boss: waiting for priority", Core.C.textDim)
                        end
                    elseif Core.state.boss_tp then
                        Farming.stopBossFollow()
                        Farming.stopBossAttack()
                        if os.clock() - Farming.bossLastTeleport >= Farming.BOSS_TP_COOLDOWN then
                            Farming.bossLastTeleport = os.clock()
                            if Core.teleportWorld(Core.BOSS_POS, "boss", function()
                                return Core.alive and Core.state.boss and Core.state.boss_tp and Farming.getBossRoot() ~= nil
                            end) then
                                Farming.setBossStatus("Boss: teleporting", Core.C.orange)
                            end
                        end
                    else
                        Farming.stopBossFollow()
                        Farming.stopBossAttack()
                        Core.releasePriority("boss")
                        Farming.setBossStatus("Boss: left arena / stopped", Core.C.textDim)
                    end
                else
                    Farming.stopBossFollow()
                    Farming.stopBossAttack()
                    Core.releasePriority("boss")
                    Farming.setBossStatus("Boss: " .. Farming.getBossTimerText(), Core.C.textDim)
                end

                task.wait(0.5)
            end
            Farming.bossStatusThread = nil
            Farming.stopBoss()
            Core.debugLog("Auto Boss loop stopped")
        end)
    end

    function Farming.startCrowns()
        task.spawn(function()
            for _, obj in ipairs(Core.CurrencyHolder:GetChildren()) do
                if Core.alive and Core.state.crowns then
                    pcall(function() Core.CollectCurrencyRemote:FireServer({[1]=obj}) end)
                end
            end
            Farming.crownsConnection = Core.CurrencyHolder.ChildAdded:Connect(function(obj)
                if not Core.alive or not Core.state.crowns then
                    if Farming.crownsConnection then Farming.crownsConnection:Disconnect(); Farming.crownsConnection = nil end
                    return
                end
                task.wait(0.05)
                pcall(function() Core.CollectCurrencyRemote:FireServer({[1]=obj}) end)
            end)
        end)
    end

    function Farming.startKoth()
        task.spawn(function()
            Core.debugLog("KOTH loop started")
            while Core.alive and Core.state.claim_koth do
                local root = Core.getRoot()
                if not root then task.wait(1); continue end
                Core.setCurrentAction("Claiming King", 6)
                if Core.state.koth_avoid then
                    local boundary = Core.KOH_BOUNDARY
                    if not boundary then
                        Core.debugLog("KOTH - KOH_BOUNDARY not found, skipping avoid check")
                    else
                        local kothRadius  = boundary.Size.X / 2
                        local kothPos     = boundary.Position
                        local playerNearby = false
                        for _, plr in ipairs(S.Players:GetPlayers()) do
                            if plr ~= Core.player then
                                local char = plr.Character
                                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                                if hrp and (hrp.Position - kothPos).Magnitude <= kothRadius then
                                    Core.debugLog("KOTH - player nearby:", plr.Name, "- skipping")
                                    playerNearby = true; break
                                end
                            end
                        end
                        if playerNearby then task.wait(30); continue end
                    end
                end
                local boundary = Core.KOH_BOUNDARY
                local dest = boundary and boundary.Position or Vector3.new(735.24, 250.00, 51.20)

                local radius = boundary and (boundary.Size.X / 2) or 20
                local distance = (root.Position - dest).Magnitude

                if distance > radius then
                    if not Core.waitForPriority("king", function()
                        return Core.alive and Core.state.claim_koth
                    end) then break end
                    if not Core.claimPriority("king") then task.wait(1); continue end
                    Core.debugLog("KOTH - outside zone, teleporting back to King at", dest)
                    Core.teleportWorld(CFrame.new(dest), "king", function()
                        return Core.alive and Core.state.claim_koth
                    end)
                else
                    Core.debugLog("KOTH - still inside zone, no teleport needed")
                end

                Core.releasePriority("king")
                task.wait(5)
            end
            Core.releasePriority("king")
            Core.clearCurrentAction("Claiming King")
            Core.debugLog("KOTH loop stopped")
        end)
    end

    function Farming.isInKothArea(position)
        local boundary = Core.KOH_BOUNDARY
        if not boundary then
            local dest = Vector3.new(735.24, 250.00, 51.20)
            return (Vector3.new(position.X, dest.Y, position.Z) - dest).Magnitude <= 20
        end

        local localPos = boundary.CFrame:PointToObjectSpace(position)
        local half = boundary.Size * 0.5
        return math.abs(localPos.X) <= half.X
            and math.abs(localPos.Z) <= half.Z
            and math.abs(localPos.Y) <= half.Y + 12
    end

    Farming.clanQuestRunId = 0
    Farming.clanQuestCurrentIndex = nil
    Farming.clanQuestCurrentSignature = nil
    Farming.clanQuestCurrentStartedAt = 0
    Farming.clanQuestStatusLabel = nil
    Farming.clanQuestStatus = "waiting: idle"
    Farming.CLAN_QUEST_KEY = "clan_auto_quests"
    Farming.CLAN_QUEST_DELAY = 0.5
    Farming.CLAN_QUEST_UPDATE_WAIT = 3
    Farming.CLAN_QUEST_BLOCKED_RETRY_DELAY = 10
    Farming.CLAN_DUNGEON_BLOCKED_RETRY_DELAY = 3
    Farming.CLAN_FLAG_RECHECK_DELAY = 5
    Farming.CLAN_ELEMENTS = {"Fire","Water","Earth","Plasma"}
    Farming.clanQuestBlockedUntil = {}
    Farming.clanElementPull = nil
    Farming.clanElementSearchIndex = 0
    Farming.clanQuestStarterStates = {
        Fire="fire_starter_pull", Water="water_starter_pull",
        Earth="earth_starter_pull", Plasma="plasma_starter_pull",
    }
    Farming.clanQuestElementPositions = {
        Fire=CFrame.new(
            526.115601, 175.945877, 505.875793,
            0.94769603, 0, -0.319174379,
            0, 1, 0,
            0.319174379, 0, 0.94769603
        ),
        Water=CFrame.new(
            72.1237488, 267.804565, -541.859924,
            0.271793306, 0, 0.962355673,
            0, 1, 0,
            -0.962355673, 0, 0.271793306
        ),
        Earth=CFrame.new(
            769.805054, 195.588165, -295.802734,
            0.0650548935, 0, -0.997881711,
            0, 1, 0,
            0.997881711, 0, 0.0650548935
        ),
        Plasma=Vector3.new(2063.61523, -9.85239124, 172.534424),
    }
    Farming.clanQuestPlatformElements = {Fire=true, Water=true, Earth=true}

    local function clanQuestContinue(runId)
        return Core.alive and Core.state[Farming.CLAN_QUEST_KEY] and Farming.clanQuestRunId == runId
    end

    function Farming.setClanQuestStatus(text)
        Farming.clanQuestStatus = text or Farming.clanQuestStatus or "waiting: idle"
        local lbl = Farming.clanQuestStatusLabel
        if lbl and lbl.Parent then
            lbl.Text = Farming.clanQuestStatus
        end
    end

    function Farming.getClanQuestDebugText(quest)
        if not quest then return "none" end
        local raw = quest.raw or {}
        local progress, goal = Farming.getClanQuestProgress(quest)
        local name = Farming.getClanQuestText(quest.index)
        if name == "" then name = tostring(raw.Text or raw.Name or raw.QuestName or raw.Type or raw.MissionType or raw.Id or "?") end
        return string.format("#%s [%s] %s (%s/%s)", tostring(quest.index), Farming.classifyClanQuest(quest), name, tostring(progress), tostring(goal))
    end

    function Farming.isClanQuestBlocked(index)
        return (Farming.clanQuestBlockedUntil[index] or 0) > os.clock()
    end

    function Farming.markClanQuestBlocked(index, reason)
        Farming.clanQuestBlockedUntil[index] = os.clock() + Farming.CLAN_QUEST_BLOCKED_RETRY_DELAY
        Core.debugLog("Clan quest blocked:", tostring(index), reason or "no progress", "retry in", Farming.CLAN_QUEST_BLOCKED_RETRY_DELAY, "s")
    end

    function Farming.markClanQuestBlockedFor(index, seconds, reason)
        Farming.clanQuestBlockedUntil[index] = os.clock() + (seconds or Farming.CLAN_QUEST_BLOCKED_RETRY_DELAY)
        Core.debugLog("Clan quest blocked:", tostring(index), reason or "no progress", "retry in", seconds or Farming.CLAN_QUEST_BLOCKED_RETRY_DELAY, "s")
    end

    function Farming.getClanQuestGuiQuests()
        local pGui = Core.player:FindFirstChild("PlayerGui"); if not pGui then return {} end
        local mainGui = pGui:FindFirstChild("MainGui"); if not mainGui then return {} end
        local otherFrames = mainGui:FindFirstChild("OtherFrames"); if not otherFrames then return {} end
        local clans = otherFrames:FindFirstChild("Clans"); if not clans then return {} end
        local inClan = clans:FindFirstChild("InClan"); if not inClan then return {} end
        local frames = inClan:FindFirstChild("Frames"); if not frames then return {} end
        local questsFrame = frames:FindFirstChild("Quests"); if not questsFrame then return {} end
        local scrolling = questsFrame:FindFirstChild("ScrollingFrame"); if not scrolling then return {} end

        local questFrames = {}
        for _, child in ipairs(scrolling:GetChildren()) do
            if child.Name == "Quest" then questFrames[#questFrames + 1] = child end
        end
        table.sort(questFrames, function(a, b) return a.LayoutOrder < b.LayoutOrder end)

        local quests = {}
        for i, frame in ipairs(questFrames) do
            local info = frame:FindFirstChild("InfoText")
            local text = info and tostring(info.Text or "") or ""
            if text ~= "" then
                Core.questTitleCache[i] = text
                quests[#quests + 1] = {index=i, raw={Name=text, Text=text}}
            end
        end
        return quests
    end

    function Farming.refreshClanQuestCacheFromGui()
        local pGui = Core.player:FindFirstChild("PlayerGui"); if not pGui then return end
        local mainGui = pGui:FindFirstChild("MainGui"); if not mainGui then return end
        local otherFrames = mainGui:FindFirstChild("OtherFrames"); if not otherFrames then return end
        local clans = otherFrames:FindFirstChild("Clans"); if not clans then return end
        local inClan = clans:FindFirstChild("InClan"); if not inClan then return end
        local frames = inClan:FindFirstChild("Frames"); if not frames then return end
        local questsFrame = frames:FindFirstChild("Quests"); if not questsFrame then return end
        local scrolling = questsFrame:FindFirstChild("ScrollingFrame"); if not scrolling then return end

        local questFrames = {}
        for _, child in ipairs(scrolling:GetChildren()) do
            if child.Name == "Quest" then questFrames[#questFrames + 1] = child end
        end
        table.sort(questFrames, function(a, b) return a.LayoutOrder < b.LayoutOrder end)

        for i, frame in ipairs(questFrames) do
            local info = frame:FindFirstChild("InfoText")
            local text = info and tostring(info.Text or "") or ""
            if text ~= "" then Core.questTitleCache[i] = text end
        end
    end

    function Farming.getClanQuestData()
        Farming.refreshClanQuestCacheFromGui()
        local cd = Core.getClientDataManager()
        local data = cd and cd.Data
        if type(data) ~= "table" then return Farming.getClanQuestGuiQuests() end
        local candidates = {
            data.ClanQuests, data.ClanQuest, data.CurrentClanQuests,
            data.PlayerClanQuests, data.Clan and data.Clan.Quests,
            data.ClanData and data.ClanData.Quests,
        }
        for _, source in ipairs(candidates) do
            if type(source) == "table" then
                local quests = {}
                for key, value in pairs(source) do
                    if type(value) == "table" then
                        local idx = tonumber(value.Index or value.Slot or key) or (#quests + 1)
                        local raw = value
                        if (raw.Text == nil or raw.Text == "") and Core.questTitleCache[idx] then
                            raw = {}
                            for k, v in pairs(value) do raw[k] = v end
                            raw.Text = Core.questTitleCache[idx]
                        end
                        quests[#quests + 1] = {index=idx, raw=raw}
                    end
                end
                table.sort(quests, function(a, b) return a.index < b.index end)
                if #quests > 0 then return quests end
            end
        end
        return Farming.getClanQuestGuiQuests()
    end

    function Farming.getClanQuestText(index)
        local labels = Core.questTitleLabels
        local lbl = labels and labels[index]
        if lbl and lbl.Parent and lbl.Text and lbl.Text ~= "" then return lbl.Text end
        local cache = Core.questTitleCache
        if cache and cache[index] and cache[index] ~= "" then return cache[index] end
        return ""
    end

    function Farming.getClanQuestNumber(raw, names)
        if type(raw) ~= "table" then return nil end
        for _, name in ipairs(names) do
            local value = raw[name]
            if tonumber(value) then return tonumber(value) end
        end
        return nil
    end

    function Farming.getClanQuestSignature(quest)
        if not quest then return "none" end
        local raw = quest.raw or {}
        local text = Farming.getClanQuestText(quest.index)
        if text == "" then text = tostring(raw.Text or raw.Name or "") end
        local progress = Farming.getClanQuestNumber(raw, {"Progress","Amount","Current","Count","CompletedAmount","QuestProgress"}) or 0
        local goal = Farming.getClanQuestNumber(raw, {"Goal","Target","Required","Needed","AmountNeeded","QuestTarget"}) or 0
        return tostring(quest.index) .. ":" .. tostring(raw.Type or raw.MissionType or raw.Name or raw.Id or text) .. ":" .. tostring(progress) .. "/" .. tostring(goal) .. ":" .. tostring(raw.Completed or raw.Claimed)
    end

    function Farming.classifyClanQuest(quest)
        local raw = quest.raw or {}
        local haystack = table.concat({
            tostring(raw.Type or ""), tostring(raw.MissionType or ""), tostring(raw.Name or ""),
            tostring(raw.Id or ""), tostring(raw.QuestName or ""), tostring(raw.Text or ""),
            tostring(raw.Objective or ""), tostring(raw.Description or ""), tostring(raw.Title or ""),
            Farming.getClanQuestText(quest.index),
        }, " "):lower()

        if haystack:find("dungeon", 1, true) then return "dungeon" end
        if haystack:find("swing", 1, true) or haystack:find("saber", 1, true) then return "swing" end
        if haystack:find("flag", 1, true) then return "flag" end
        if haystack:find("king", 1, true) or haystack:find("koth", 1, true) or haystack:find("hill", 1, true) then return "koth" end
        if haystack:find("mob", 1, true) or haystack:find("enemy", 1, true) or haystack:find("golem", 1, true) or haystack:find("element", 1, true)
            or (haystack:find("boss", 1, true) and (haystack:find("fire", 1, true) or haystack:find("water", 1, true) or haystack:find("earth", 1, true) or haystack:find("plasma", 1, true))) then return "element" end
        if haystack:find("boss", 1, true) then return "boss" end
        if haystack:find("egg", 1, true) or haystack:find("hatch", 1, true) or haystack:find("open", 1, true) then return "egg" end
        return "unknown"
    end

    function Farming.getClanQuestProgress(quest)
        local raw = quest.raw or {}
        local progress = Farming.getClanQuestNumber(raw, {"Progress","Amount","Current","Count","CompletedAmount","QuestProgress"})
        local goal = Farming.getClanQuestNumber(raw, {"Goal","Target","Required","Needed","AmountNeeded","QuestTarget"})
        local text = Farming.getClanQuestText(quest.index)
        if text == "" then text = tostring(raw.Text or raw.Name or "") end
        if (not progress or not goal) and text ~= "" then
            local a, b = text:match("(%d+)%s*/%s*(%d+)")
            if a and b then progress, goal = tonumber(a), tonumber(b) end
        end
        return progress or 0, goal or 0
    end

    function Farming.isClanQuestComplete(quest)
        if not quest then return true end
        local raw = quest.raw or {}
        if raw.Completed == true or raw.Complete == true or raw.Finished == true or raw.Claimed == true then return true end
        local progress, goal = Farming.getClanQuestProgress(quest)
        return goal > 0 and progress >= goal
    end

    function Farming.findClanQuestByIndex(index)
        for _, quest in ipairs(Farming.getClanQuestData()) do
            if quest.index == index then return quest end
        end
        return nil
    end

    function Farming.getClanQuestDifficultyName(quest)
        local raw = quest and quest.raw or {}
        local text = (quest and Farming.getClanQuestText(quest.index) or "")
        if text == "" then text = tostring(raw.Text or raw.Name or raw.QuestName or "") end
        local value = raw.Difficulty or raw.DungeonDifficulty or text
        local lower = tostring(value or ""):lower()
        if Core.state.clan_dungeon_impossible or lower:find("impossible", 1, true) then return "Impossible" end
        if lower:find("hard", 1, true) then return "Hard" end
        if lower:find("medium", 1, true) then return "Medium" end
        if lower:find("easy", 1, true) then return "Easy" end
        return Core.selectionState.dungeon_difficulty or "Easy"
    end

    function Farming.getClanQuestDifficultyValue(quest)
        return (HS.Dungeon and HS.Dungeon.DIFFICULTY_MAP and HS.Dungeon.DIFFICULTY_MAP[Farming.getClanQuestDifficultyName(quest)]) or 1
    end

    function Farming.getClanDungeonTimerText()
        if HS.Dungeon and HS.Dungeon.startTimer then
            pcall(HS.Dungeon.startTimer)
        end
        if HS.Dungeon and HS.Dungeon.getEffectiveTimerText then
            local ok, text = pcall(HS.Dungeon.getEffectiveTimerText)
            if ok and tostring(text or "") ~= "" then
                return tostring(text)
            end
        end
        return nil
    end

    function Farming.isDungeonStartBlockedByPresence()
        local dungeon = HS.Dungeon
        if not dungeon then return false end

        if type(dungeon.isStartBlockedByPresence) == "function" then
            local ok, blocked = pcall(dungeon.isStartBlockedByPresence)
            if ok and blocked then return true end
        end

        if type(dungeon.isDungeonPresenceActive) == "function" then
            local ok, active = pcall(dungeon.isDungeonPresenceActive)
            if ok and active then return true end
        end

        if type(dungeon.isInsideActive) == "function" then
            local ok, inside = pcall(dungeon.isInsideActive)
            if ok and inside then return true end
        end

        return false
    end

    function Farming.canStartClanDungeonQuest()
        if Farming.isDungeonStartBlockedByPresence() then
            return false, "active dungeon"
        end
        if HS.Dungeon.updateAutoStartState and HS.Dungeon.updateAutoStartState() then
            return false, "active dungeon"
        end
        if os.clock() < (HS.Dungeon.autoStartCooldownUntil or 0) then
            local left = math.max(0, math.ceil((HS.Dungeon.autoStartCooldownUntil or 0) - os.clock()))
            return false, "local cooldown " .. tostring(left) .. "s"
        end

        local timerText = Farming.getClanDungeonTimerText()
        if timerText ~= "Queue Up" then
            return false, timerText and ("timer " .. timerText) or "timer unavailable"
        end

        return true, "ready"
    end

    function Farming.getBestReadyClanDungeonQuest(quests)
        local canStart, reason = Farming.canStartClanDungeonQuest()
        if not canStart then
            Core.debugLog("Clan dungeon unavailable:", reason or "not ready")
            return nil
        end
        local best = nil
        local bestDifficulty = -1
        for _, quest in ipairs(quests) do
            if Farming.classifyClanQuest(quest) == "dungeon"
                and not Farming.isClanQuestComplete(quest)
                and not Farming.isClanQuestBlocked(quest.index) then
                local difficulty = Farming.getClanQuestDifficultyValue(quest)
                if difficulty > bestDifficulty then
                    best = quest
                    bestDifficulty = difficulty
                end
            end
        end
        return best
    end

    function Farming.isClanQuestIgnored(kind)
        return (kind == "flag" and Core.state.clan_flag_ignore == true)
            or (kind == "koth" and Core.state.clan_koth_ignore == true)
    end

    function Farming.isClanQuestIgnoredQuest(quest, kind)
        kind = kind or Farming.classifyClanQuest(quest)
        if Farming.isClanQuestIgnored(kind) then return true end
        if Core.state.clan_koth_ignore ~= true then return false end

        local raw = quest and quest.raw or {}
        local haystack = table.concat({
            tostring(raw.Type or ""), tostring(raw.MissionType or ""), tostring(raw.Name or ""),
            tostring(raw.Id or ""), tostring(raw.QuestName or ""), tostring(raw.Text or ""),
            tostring(raw.Objective or ""), tostring(raw.Description or ""), tostring(raw.Title or ""),
            quest and Farming.getClanQuestText(quest.index) or "",
        }, " "):lower()

        return haystack:find("king", 1, true) ~= nil
            or haystack:find("koth", 1, true) ~= nil
            or haystack:find("hill", 1, true) ~= nil
    end

    function Farming.getNextClanQuest(preferredIndex)
        local quests = Farming.getClanQuestData()
        Core.debugLog("Clan quest scan count:", #quests, "previous:", preferredIndex or "none")
        local dungeonQuest = Farming.getBestReadyClanDungeonQuest(quests)
        if dungeonQuest and not Farming.isClanQuestIgnoredQuest(dungeonQuest) then
            Core.debugLog("Clan quest selected highest ready dungeon:", Farming.getClanQuestDebugText(dungeonQuest))
            return dungeonQuest
        end
        for _, quest in ipairs(quests) do
            local complete = Farming.isClanQuestComplete(quest)
            local blocked = Farming.isClanQuestBlocked(quest.index)
            local kind = Farming.classifyClanQuest(quest)
            local ignored = Farming.isClanQuestIgnoredQuest(quest, kind)
            if kind == "dungeon" and not complete and not blocked then
                local _, reason = Farming.canStartClanDungeonQuest()
                Farming.markClanQuestBlockedFor(quest.index, Farming.CLAN_DUNGEON_BLOCKED_RETRY_DELAY, "dungeon " .. tostring(reason or "not ready"))
                blocked = true
            end
            Core.debugLog("Clan quest candidate:", Farming.getClanQuestDebugText(quest), "complete=", complete, "blocked=", blocked, "ignored=", ignored)
            if not complete and not blocked and not ignored then return quest end
        end
        Farming.setClanQuestStatus("waiting: no available clan quests")
        return nil
    end

    function Farming.getFallbackClanQuest(blockedIndex)
        for _, quest in ipairs(Farming.getClanQuestData()) do
            local kind = Farming.classifyClanQuest(quest)
            if quest.index ~= blockedIndex
                and not Farming.isClanQuestComplete(quest)
                and not Farming.isClanQuestBlocked(quest.index)
                and not Farming.isClanQuestIgnoredQuest(quest, kind) then
                Core.debugLog("Clan quest fallback selected:", Farming.getClanQuestDebugText(quest), "blocked was", blockedIndex)
                return quest
            end
        end
        Core.debugLog("Clan quest fallback unavailable; blocked was", blockedIndex)
        return nil
    end

    function Farming.getClanQuestRetryDelay(kind)
        if kind == "dungeon" then return Farming.CLAN_DUNGEON_BLOCKED_RETRY_DELAY end
        if kind == "flag" then return Farming.CLAN_FLAG_RECHECK_DELAY end
        return Farming.CLAN_QUEST_BLOCKED_RETRY_DELAY
    end

    function Farming.waitForClanQuestReadUpdate(index, oldSignature, runId)
        local start = os.clock()
        Core.debugLog("Clan quest waiting for read update:", tostring(index), oldSignature)
        repeat
            task.wait(0.2)
            local fresh = Farming.findClanQuestByIndex(index)
            if fresh and Farming.getClanQuestSignature(fresh) ~= oldSignature then
                Core.debugLog("Clan quest read updated:", tostring(index), Farming.getClanQuestSignature(fresh))
                return fresh
            end
        until os.clock() - start >= Farming.CLAN_QUEST_UPDATE_WAIT or not clanQuestContinue(runId)
        Core.debugLog("Clan quest read update wait ended:", tostring(index))
        return Farming.findClanQuestByIndex(index)
    end

    function Farming.startClanQuest()
        Core.loopWhile("clanquest", 1, function()
            for i = 1, 3 do
                if not Core.alive or not Core.state.clanquest then break end
                pcall(function() Core.UIActionRemote:FireServer("ClaimClanQuest", i) end)
                task.wait(0.3)
            end
            if _G.refreshQuestTitles then _G.refreshQuestTitles() end
            task.wait(4)
        end)
    end

    function Farming.claimClanQuestReward(index, runId)
        if not index or not clanQuestContinue(runId) then return end
        Core.debugLog("Claiming completed clan quest:", tostring(index))
        pcall(function() Core.UIActionRemote:FireServer("ClaimClanQuest", index) end)
        task.wait(0.5)
        if _G.refreshQuestTitles then _G.refreshQuestTitles() end
    end

    function Farming.claimCompletedClanQuests(runId)
        local claimedAny = false
        for _, quest in ipairs(Farming.getClanQuestData()) do
            if not clanQuestContinue(runId) then break end
            if Farming.isClanQuestComplete(quest) then
                Farming.claimClanQuestReward(quest.index, runId)
                claimedAny = true
                task.wait(0.2)
            end
        end
        if claimedAny then
            Farming.refreshClanQuestInfo()
        end
        return claimedAny
    end

    function Farming.startClanDungeonQuest(quest, runId)
        local raw = quest.raw or {}
        local canStart, reason = Farming.canStartClanDungeonQuest()
        if not canStart then
            Core.debugLog("Clan dungeon quest waiting:", reason or "not ready")
            return false
        end
        local privacy = Core.selectionState.dungeon_privacy or "Public"
        local dungeonType = raw.DungeonType or raw.Dungeon or Core.selectionState.dungeon_type or "Space"
        local difficultyName = Farming.getClanQuestDifficultyName(quest)
        local difficulty = HS.Dungeon.DIFFICULTY_MAP[difficultyName] or tonumber(difficultyName) or 1
        Core.debugLog("Clan dungeon quest start:", Farming.getClanQuestDebugText(quest), "type=", dungeonType, "difficulty=", difficultyName)
        if not Core.waitForPriority("clan_quests", function() return clanQuestContinue(runId) end) then return false end
        if not Core.claimPriority("clan_quests") then return false end
        canStart, reason = Farming.canStartClanDungeonQuest()
        if not canStart then
            Core.debugLog("Clan dungeon quest cancelled before start:", reason or "not ready")
            Core.releasePriority("clan_quests")
            return false
        end
        if Farming.isDungeonStartBlockedByPresence() then
            Core.debugLog("Clan dungeon quest start deferred: active dungeon")
            Core.releasePriority("clan_quests")
            return false
        end
        Core.setCurrentAction("Running Dungeon", 5)
        pcall(function() Core.UIActionRemote:FireServer("DungeonGroupAction", "Create", privacy, dungeonType, difficulty) end)
        task.wait((HS.Dungeon and HS.Dungeon.START_REMOTE_DELAY) or 2)
        if Farming.isDungeonStartBlockedByPresence() then
            Core.debugLog("Clan dungeon quest start skipped: already inside dungeon")
            Core.releasePriority("clan_quests")
            return false
        end
        pcall(function() Core.UIActionRemote:FireServer("DungeonGroupAction", "Start") end)
        if HS.Dungeon then
            HS.Dungeon.queueHandled = true
            if HS.Dungeon.markRunActive then HS.Dungeon.markRunActive("clan dungeon start") end
        end
        Core.lockWorldTeleports(30)
        Core.releasePriority("clan_quests")
        return true
    end

    function Farming.isFlagHeightReached(info)
        if not info then return false end
        local expectedHeight = HS.Flags.getExpectedHeightFromPosition(info.position)
        if not expectedHeight then return true end

        local flag = info.flag
        local flagY
        if flag:IsA("BasePart") then
            flagY = flag.Position.Y
        elseif flag:IsA("Model") then
            local part = flag.PrimaryPart or flag:FindFirstChildWhichIsA("BasePart")
            flagY = part and part.Position.Y or flag:GetPivot().Position.Y
        end

        return flagY ~= nil and math.abs(flagY - expectedHeight) <= (Core.FLAG_HEIGHT_TOLERANCE or 0.35)
    end

    function Farming.doClanFlagQuest(quest, runId)
        if Core.state.clan_flag_ignore then Core.debugLog("Clan flag quest ignored:", Farming.getClanQuestDebugText(quest)); return true end
        local flagsFolder = workspace:FindFirstChild("Gameplay") and workspace.Gameplay:FindFirstChild("Flags")
        if not flagsFolder then Core.debugLog("Clan flag quest blocked: flags folder missing"); return false end
        local playerName = Core.player.Name
        local didWork = false
        local needsReclaim = false
        Core.debugLog("Clan flag quest scan:", Farming.getClanQuestDebugText(quest))
        for index, flagModel in ipairs(flagsFolder:GetChildren()) do
            if not clanQuestContinue(runId) then break end
            if Core.state.clan_flag_ignore then
                Core.debugLog("Clan flag quest ignored during scan:", Farming.getClanQuestDebugText(quest))
                break
            end
            local info = HS.Flags.getFlagInfo(flagModel)
            if not info then continue end
            if info.owner == playerName and Farming.isFlagHeightReached(info) then continue end
            needsReclaim = true
            local baseBottomPos = info.base.Position - Vector3.new(0, info.base.Size.Y / 2, 0)
            if Core.state.clan_flag_avoid and HS.Flags.isPlayerNearFlag(baseBottomPos, 20, index) then
                Core.debugLog("Clan flag quest skipping flag due to nearby player:", index)
                continue
            end
            if not Core.waitForPriority("clan_quests", function() return clanQuestContinue(runId) end) then return didWork end
            if not Core.claimPriority("clan_quests") then return didWork end
            if Core.teleportWorld(CFrame.new(info.position + Vector3.new(0, 10, 0)), "clan quest", function()
                return clanQuestContinue(runId)
            end) then
                didWork = true
                local start = os.clock()
                local heightReached = false
                local ownershipChanged = false
                repeat
                    task.wait(0.25)
                    if Core.state.clan_flag_ignore then
                        Core.debugLog("Clan flag quest ignored while capturing:", index)
                        break
                    end
                    local fresh = HS.Flags.getFlagInfo(flagModel)
                    if fresh and fresh.owner == playerName then
                        ownershipChanged = true
                        heightReached = Farming.isFlagHeightReached(fresh)
                    end
                until (ownershipChanged and heightReached) or os.clock() - start > 30 or not clanQuestContinue(runId)
                Core.debugLog("Clan flag result:", index, "owner=", ownershipChanged, "height=", heightReached)
            end
            Core.releasePriority("clan_quests")
            if Farming.isClanQuestComplete(Farming.findClanQuestByIndex(quest.index) or quest) then break end
        end
        Core.releasePriority("clan_quests")
        if not needsReclaim then
            Farming.markClanQuestBlockedFor(quest.index, Farming.CLAN_FLAG_RECHECK_DELAY, "flags already captured; passive recheck")
            Farming.setClanQuestStatus("waiting: flags captured, checking other missions")
            return false
        end
        if not Farming.isClanQuestComplete(Farming.findClanQuestByIndex(quest.index) or quest) then
            Farming.markClanQuestBlockedFor(quest.index, Farming.CLAN_FLAG_RECHECK_DELAY, didWork and "flag scan complete" or "no claimable flags")
        end
        return didWork
    end

    function Farming.doClanKothQuest(runId)
        if Core.state.clan_koth_ignore then
            Core.debugLog("Clan KOTH quest ignored by setting")
            Farming.setClanQuestStatus("skipped: koth mission ignored")
            return false
        end
        local boundary = Core.KOH_BOUNDARY
        local dest = boundary and boundary.Position or Vector3.new(735.24, 250.00, 51.20)
        if Core.state.clan_koth_avoid and boundary then
            for _, plr in ipairs(S.Players:GetPlayers()) do
                local hrp = plr ~= Core.player and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp and Farming.isInKothArea(hrp.Position) then
                    Core.debugLog("Clan KOTH blocked: player in area", plr.Name)
                    return false
                end
            end
        end
        if not Core.waitForPriority("clan_quests", function()
            return clanQuestContinue(runId) and not Core.state.clan_koth_ignore
        end) then return false end
        if Core.state.clan_koth_ignore then return false end
        if not Core.claimPriority("clan_quests") then return false end
        local root = Core.getRoot()
        if root and not Farming.isInKothArea(root.Position) then
            Core.debugLog("Clan KOTH teleporting back to area")
            Core.teleportWorld(CFrame.new(dest), "clan quest", function()
                return clanQuestContinue(runId) and not Core.state.clan_koth_ignore
            end)
        else
            Core.debugLog("Clan KOTH already inside area; no teleport")
        end
        task.wait(3)
        Core.releasePriority("clan_quests")
        return true
    end

    function Farming.doClanBossQuest(runId)
        local boss = Farming.getBossModel()
        if not boss or not Farming.getBossRoot() then
            Farming.stopClanBossSupport("boss not spawned")
            Core.debugLog("Clan boss quest blocked: boss not spawned")
            Farming.setClanQuestStatus("waiting: boss unavailable")
            return false
        end
        if not Core.waitForPriority("clan_quests", function() return clanQuestContinue(runId) and Farming.getBossRoot() ~= nil end) then return false end
        if not Core.claimPriority("clan_quests") then return false end
        Farming.clanBossActive = true
        local root = Core.getRoot()
        if root and not Farming.isInBossArena(root) then
            Core.teleportWorld(Core.BOSS_POS, "clan quest", function()
                return clanQuestContinue(runId) and Farming.getBossRoot() ~= nil
            end)
            task.wait(0.5)
        end
        Farming.ensureBossFollow()
        Farming.ensureBossAttackLoop()
        return true
    end

    function Farming.stopClanBossSupport(reason)
        if not Farming.clanBossActive then return end
        Core.debugLog("Clan boss support stopping:", reason or "")
        Farming.clanBossActive = false
        if not Core.state.boss then
            Farming.stopBossFollow()
            Farming.stopBossAttack()
            Core.releasePriority("clan_quests")
        end
    end

    function Farming.stopClanElementPull(reason)
        local active = Farming.clanElementPull
        if not active then return end
        Core.debugLog("Clan element pull stopping:", active.element, reason or "")
        if active.element and not active.hadEnabled then
            HS.ElementZonePull.stop(active.element, "Starter")
        end
        if active.stateKey and active.previousState ~= nil then
            Core.state[active.stateKey] = active.previousState
        end
        if Core.activeCycleKey == active.stateKey then
            Core.activeCycleKey = active.previousCycleKey
        end
        Farming.clanElementPull = nil
    end

    function Farming.ensureClanElementPull(element, stateKey)
        local active = Farming.clanElementPull
        local pullKey = HS.ElementZonePull.getKey(element, "Starter")
        if active and active.element == element and active.stateKey == stateKey then
            Core.state[stateKey] = true
            Core.activeCycleKey = stateKey
            if HS.ElementZonePull.enabled[pullKey] and (not HS.ElementZonePull.connections[pullKey] or not HS.ElementZonePull.hitThreads[pullKey]) then
                Core.debugLog("Clan element pull restarting stale loop:", element)
                HS.ElementZonePull.stop(element, "Starter")
                HS.ElementZonePull.start(element, "Starter")
            elseif not HS.ElementZonePull.enabled[pullKey] then
                HS.ElementZonePull.start(element, "Starter")
            end
            return
        end

        Farming.stopClanElementPull("switching element")
        Farming.clanElementPull = {
            element=element,
            stateKey=stateKey,
            previousState=Core.state[stateKey],
            previousCycleKey=Core.activeCycleKey,
            hadEnabled=HS.ElementZonePull.enabled[pullKey] == true,
            startedAt=os.clock(),
        }
        Core.state[stateKey] = true
        Core.activeCycleKey = stateKey
        HS.ElementZonePull.start(element, "Starter")
        Core.debugLog("Clan element pull started:", element, stateKey)
    end

    function Farming.getClanElementQuestMode(quest)
        local raw = quest and quest.raw or {}
        local text = quest and Farming.getClanQuestText(quest.index) or ""
        if text == "" then text = tostring(raw.Text or raw.Name or raw.QuestName or raw.Type or raw.MissionType or raw.Id or "") end
        local haystack = text:lower()
        if haystack:find("boss", 1, true) then return "boss" end
        if haystack:find("golem", 1, true) or haystack:find("mob", 1, true) or haystack:find("enemy", 1, true) then return "golem" end
        return "any"
    end

    function Farming.getClanElementOrder()
        local selected = Core.selectionState.clan_element or "Fire"
        local order = {}
        local seen = {}
        if Farming.clanQuestStarterStates[selected] then
            order[#order + 1] = selected
            seen[selected] = true
        end
        for _, element in ipairs(Farming.CLAN_ELEMENTS) do
            if not seen[element] then order[#order + 1] = element end
        end
        return order
    end

    function Farming.getClanElementTargets(element, targetType)
        local allTargets = HS.ElementZonePull.getTargets(element, "Starter")
        local targets = {}
        local bossName = HS.ElementZonePull.getBossName(element, "Starter")
        for _, target in ipairs(allTargets) do
            local isBoss = target.Name == bossName
            if targetType == "boss" and isBoss then
                targets[#targets + 1] = target
            elseif targetType == "golem" and not isBoss then
                targets[#targets + 1] = target
            elseif targetType == "any" then
                targets[#targets + 1] = target
            end
        end
        return targets
    end

    function Farming.selectClanElementWork(quest)
        local mode = Farming.getClanElementQuestMode(quest)
        local selected = Core.selectionState.clan_element or "Fire"
        local order = Farming.getClanElementOrder()

        if mode == "boss" then
            local selectedBosses = Farming.getClanElementTargets(selected, "boss")
            if #selectedBosses > 0 then return selected, selectedBosses, "boss" end
            for _, element in ipairs(order) do
                if element ~= selected then
                    local bosses = Farming.getClanElementTargets(element, "boss")
                    if #bosses > 0 then return element, bosses, "boss" end
                end
            end
            for _, element in ipairs(order) do
                local golems = Farming.getClanElementTargets(element, "golem")
                if #golems > 0 then return element, golems, "golem waiting for boss" end
            end
            Farming.clanElementSearchIndex = (Farming.clanElementSearchIndex % #order) + 1
            return order[Farming.clanElementSearchIndex] or selected, {}, "searching for boss"
        end

        if mode == "golem" then
            local selectedGolems = Farming.getClanElementTargets(selected, "golem")
            if #selectedGolems > 0 then return selected, selectedGolems, "golem" end
            local selectedBosses = Farming.getClanElementTargets(selected, "boss")
            if #selectedBosses > 0 then return selected, selectedBosses, "boss to spawn golems" end
            for _, element in ipairs(order) do
                local golems = Farming.getClanElementTargets(element, "golem")
                if #golems > 0 then return element, golems, "golem" end
            end
            for _, element in ipairs(order) do
                local bosses = Farming.getClanElementTargets(element, "boss")
                if #bosses > 0 then return element, bosses, "boss to spawn golems" end
            end
            Farming.clanElementSearchIndex = (Farming.clanElementSearchIndex % #order) + 1
            return order[Farming.clanElementSearchIndex] or selected, {}, "searching for golems"
        end

        for _, element in ipairs(order) do
            local targets = Farming.getClanElementTargets(element, "any")
            if #targets > 0 then return element, targets, "any" end
        end
        Farming.clanElementSearchIndex = (Farming.clanElementSearchIndex % #order) + 1
        return order[Farming.clanElementSearchIndex] or selected, {}, "searching"
    end

    function Farming.doClanElementQuest(quest, runId)
        local element, selectedTargets, mode = Farming.selectClanElementWork(quest)
        local stateKey = Farming.clanQuestStarterStates[element]
        local pos = Farming.clanQuestElementPositions[element]
        local targetCf = pos and Core.asCFrame(pos)
        local targetPos = targetCf and targetCf.Position
        if not stateKey then Core.debugLog("Clan element quest blocked: bad element", tostring(element)); return false end
        Core.debugLog("Clan element quest:", element, "mode=", mode, "targets=", #selectedTargets, "stateKey=", stateKey)
        if not Core.waitForPriority("clan_quests", function() return clanQuestContinue(runId) end) then return false end
        if not Core.claimPriority("clan_quests") then return false end
        local root = Core.getRoot()
        if targetCf and (not root or (root.Position - targetPos).Magnitude > 60) then
            if Farming.clanQuestPlatformElements[element] then
                Core.ensureElementSafetyPlatform(targetCf)
                if HS.ElementZonePull and HS.ElementZonePull.setElementNoclip then
                    HS.ElementZonePull.setElementNoclip(true)
                end
            end
            Core.teleportWorld(targetCf, "clan quest", function() return clanQuestContinue(runId) end)
        elseif targetCf and Farming.clanQuestPlatformElements[element] then
            Core.ensureElementSafetyPlatform(targetCf)
            if HS.ElementZonePull and HS.ElementZonePull.setElementNoclip then
                HS.ElementZonePull.setElementNoclip(true)
            end
        end
        Farming.ensureClanElementPull(element, stateKey)
        local active = Farming.clanElementPull
        if active and os.clock() - (active.startedAt or 0) < 3 then
            Core.debugLog("Clan element pull warming up:", element)
            Core.releasePriority("clan_quests")
            return true
        end
        local remote = Core.getEquippedRemote()
        if remote and #selectedTargets > 0 then
            pcall(function() remote:FireServer(selectedTargets) end)
            for _, target in ipairs(selectedTargets) do
                pcall(function() remote:FireServer({target}) end)
            end
        end
        Core.debugLog("Clan element targets:", #selectedTargets, mode)
        Core.releasePriority("clan_quests")
        if #selectedTargets <= 0 then
            Core.debugLog("Clan element quest waiting for enemies instead of skipping:", element)
        end
        return true
    end

    function Farming.getBestUnlockedClanEgg()
        if not HS.EggOpener.init() then return nil end
        local opened = HS.EggOpener.getOpenedTable()
        local best
        for _, eggName in ipairs(HS.EggOpener.eggOrder) do
            if opened[eggName] ~= nil then best = eggName end
        end
        return best
    end

    function Farming.getCheapClanEgg()
        if not HS.EggOpener.init() then return nil end
        return HS.EggOpener.eggOrder[1]
    end

    function Farming.getPetdexClanEgg()
        local Petdex = HS.PetdexFarm
        if not Petdex.init() then return nil end
        local ownedPets = Petdex.getOwnedPets()
        for _, eggName in ipairs(Petdex.eggOrder) do
            local unlocked, target, counted, opened, complete = Petdex.evaluateEgg(eggName, ownedPets, 0, true)
            if not complete then return eggName end
        end
        return Farming.getBestUnlockedClanEgg()
    end

    function Farming.teleportClanPetShop(runId)
        local Petdex = HS.PetdexFarm
        if not Petdex.init() then Core.debugLog("Clan pet shop teleport blocked: petdex init failed"); return false end
        if Petdex.isInShop() then return true end
        local part = Petdex.getShopPart()
        if not part then Core.debugLog("Clan pet shop teleport blocked: shop part missing"); return false end
        if not Core.waitForPriority("clan_quests", function() return clanQuestContinue(runId) end) then return false end
        if not Core.claimPriority("clan_quests") then return false end
        Core.debugLog("Clan pet shop teleporting")
        local ok = Core.teleportWorld(part.CFrame + Vector3.new(0, math.max(5, part.Size.Y * 0.5 + 3), 0), "clan quest", function()
            return clanQuestContinue(runId)
        end)
        Core.releasePriority("clan_quests")
        task.wait(0.35)
        return ok == true
    end

    function Farming.doClanEggQuest(quest, runId)
        local function getEggName()
            local mode = Core.selectionState.clan_egg_mode or "Best Egg"
            return mode == "Cheap Egg" and Farming.getCheapClanEgg()
                or mode == "Petdex" and Farming.getPetdexClanEgg()
                or Farming.getBestUnlockedClanEgg(), mode
        end

        local openedAny = false
        Core.debugLog("Clan egg quest loop started:", Farming.getClanQuestDebugText(quest))

        while clanQuestContinue(runId) do
            local fresh = Farming.findClanQuestByIndex(quest.index) or quest
            if Farming.isClanQuestComplete(fresh) then
                Core.debugLog("Clan egg quest complete:", Farming.getClanQuestDebugText(fresh))
                Core.releasePriority("clan_quests")
                return true
            end
            if Farming.classifyClanQuest(fresh) ~= "egg" then
                Core.debugLog("Clan egg quest changed:", Farming.getClanQuestDebugText(fresh))
                Core.releasePriority("clan_quests")
                return openedAny
            end

            local eggName, mode = getEggName()
            if not eggName then
                Core.debugLog("Clan egg quest blocked: no egg for mode", mode)
                Core.releasePriority("clan_quests")
                return openedAny
            end

            if not HS.PetdexFarm.isInShop() then
                Core.releasePriority("clan_quests")
                if not Farming.teleportClanPetShop(runId) then return openedAny end
            end

            if not Core.waitForPriority("clan_quests", function() return clanQuestContinue(runId) end) then
                Core.releasePriority("clan_quests")
                return openedAny
            end
            if Core.claimPriority("clan_quests") then
                Core.debugLog("Clan egg quest opening:", eggName, "mode=", mode)
                Core.setCurrentAction(mode == "Petdex" and "Opening Eggs for Petdex" or "Opening Eggs", 2)
                pcall(function() Core.UIActionRemote:FireServer("BuyEgg", eggName) end)
                openedAny = true
            end
            Core.releasePriority("clan_quests")

            task.wait((HS.PetdexFarm and HS.PetdexFarm.HATCH_DELAY) or 0.35)
        end

        Core.releasePriority("clan_quests")
        return openedAny
    end

    function Farming.executeClanQuest(quest, runId)
        local kind = Farming.classifyClanQuest(quest)
        Core.debugLog("Clan quest execute:", Farming.getClanQuestDebugText(quest), "kind=", kind)
        if Farming.isClanQuestIgnoredQuest(quest, kind) then
            Core.debugLog("Clan quest ignored by setting:", Farming.getClanQuestDebugText(quest))
            Farming.setClanQuestStatus("skipped: " .. kind .. " mission ignored")
            return "ignored"
        end
        Farming.setClanQuestStatus("running: " .. kind .. " mission")
        if kind ~= "element" then Farming.stopClanElementPull("leaving element quest") end
        if kind ~= "boss" then Farming.stopClanBossSupport("leaving boss quest") end
        if kind == "swing" then Core.debugLog("Clan swing quest: Auto Swing must handle this"); return true end
        if kind == "dungeon" then return Farming.startClanDungeonQuest(quest, runId) end
        if kind == "flag" then return Farming.doClanFlagQuest(quest, runId) end
        if kind == "koth" then return Farming.doClanKothQuest(runId) end
        if kind == "boss" then return Farming.doClanBossQuest(runId) end
        if kind == "element" then return Farming.doClanElementQuest(quest, runId) end
        if kind == "egg" then return Farming.doClanEggQuest(quest, runId) end
        Core.debugLog("Clan quest unknown type:", Farming.getClanQuestDebugText(quest))
        return false
    end

    function Farming.startClanAutoQuests()
        if Farming.clanQuestThread then return end
        Farming.clanQuestRunId += 1
        local runId = Farming.clanQuestRunId
        Farming.clanQuestThread = task.spawn(function()
            Core.debugLog("Clan auto quests loop started")
            Farming.setClanQuestStatus("running: scanning clan quests")
            Farming.refreshClanQuestInfo()
            while clanQuestContinue(runId) do
                if Core.isWorldTeleportBlocked() then
                    Core.debugLog("Clan auto quests paused during dungeon")
                    Farming.setClanQuestStatus("paused: dungeon active")
                    Farming.stopClanBossSupport("inside dungeon")
                    Farming.stopClanElementPull("inside dungeon")
                    Core.releasePriority("clan_quests")
                    repeat
                        task.wait(1)
                    until not clanQuestContinue(runId) or not Core.isWorldTeleportBlocked()
                    continue
                end

                if Farming.claimCompletedClanQuests(runId) then
                    Farming.clanQuestCurrentIndex = nil
                    Farming.clanQuestCurrentSignature = nil
                    Farming.clanQuestCurrentStartedAt = 0
                    task.wait(0.5)
                    continue
                end

                local quest = Farming.getNextClanQuest(Farming.clanQuestCurrentIndex)
                if not quest then
                    Core.debugLog("Clan auto quests: no available quest right now")
                    Farming.setClanQuestStatus("waiting: no available clan quests")
                    Farming.clanQuestCurrentIndex = nil
                    Farming.clanQuestCurrentSignature = nil
                    Farming.clanQuestCurrentStartedAt = 0
                    Farming.stopClanBossSupport("no available quest")
                    Farming.stopClanElementPull("no available quest")
                    Core.releasePriority("clan_quests")
                    task.wait(2)
                    continue
                end

                local signature = Farming.getClanQuestSignature(quest)
                if Farming.clanQuestCurrentIndex ~= quest.index or Farming.clanQuestCurrentSignature ~= signature then
                    Farming.clanQuestCurrentStartedAt = os.clock()
                    Farming.clanQuestCurrentSignature = signature
                end
                Farming.clanQuestCurrentIndex = quest.index
                local progressed = Farming.executeClanQuest(quest, runId)
                local fresh = Farming.findClanQuestByIndex(quest.index) or quest
                local complete = Farming.isClanQuestComplete(fresh)
                Core.debugLog("Clan quest result:", Farming.getClanQuestDebugText(fresh), "progressed=", progressed, "complete=", complete)
                if complete then
                    Farming.setClanQuestStatus("claiming: completed clan quest")
                    Farming.waitForClanQuestReadUpdate(quest.index, signature, runId)
                    Farming.claimClanQuestReward(quest.index, runId)
                    Farming.refreshClanQuestInfo()
                    Farming.stopClanElementPull("quest complete")
                    Farming.stopClanBossSupport("quest complete")
                    Farming.clanQuestCurrentIndex = nil
                    Farming.clanQuestCurrentSignature = nil
                    Farming.clanQuestCurrentStartedAt = 0
                elseif not progressed then
                    Farming.stopClanElementPull("quest blocked")
                    local kind = Farming.classifyClanQuest(quest)
                    Farming.setClanQuestStatus("waiting: " .. kind .. " mission unavailable")
                    if not Farming.isClanQuestBlocked(quest.index) then
                        Farming.markClanQuestBlockedFor(quest.index, Farming.getClanQuestRetryDelay(kind), "mission could not progress")
                    end
                    Farming.clanQuestCurrentIndex = nil
                    Farming.clanQuestCurrentSignature = nil
                    Farming.clanQuestCurrentStartedAt = 0
                end
                Core.releasePriority("clan_quests")
                task.wait(Farming.CLAN_QUEST_DELAY)
            end
            Core.releasePriority("clan_quests")
            if Farming.clanQuestRunId == runId then Farming.clanQuestThread = nil end
            Farming.setClanQuestStatus("waiting: idle")
            Core.debugLog("Clan auto quests loop stopped")
        end)
    end

    function Farming.stopClanAutoQuests()
        Farming.clanQuestRunId += 1
        Farming.clanQuestThread = nil
        Farming.clanQuestCurrentIndex = nil
        Farming.clanQuestCurrentSignature = nil
        Farming.clanQuestCurrentStartedAt = 0
        Farming.stopClanElementPull("auto quests stopped")
        Farming.stopClanBossSupport("auto quests stopped")
        Core.releasePriority("clan_quests")
        Farming.setClanQuestStatus("waiting: idle")
    end
    function Farming.refreshClanQuestInfo()
        local pGui = Core.player:FindFirstChild("PlayerGui"); if not pGui then return end
        local mainGui = pGui:FindFirstChild("MainGui"); if not mainGui then return end
        local otherFrames = mainGui:FindFirstChild("OtherFrames"); if not otherFrames then return end
        local clans = otherFrames:FindFirstChild("Clans"); if not clans then return end
        local inClan = clans:FindFirstChild("InClan"); if not inClan then return end
        local frames = inClan:FindFirstChild("Frames"); if not frames then return end
        local quests = frames:FindFirstChild("Quests"); if not quests then return end

        local oldClansVisible = clans.Visible
        local oldVisibleFrames = {}
        for _, v in pairs(frames:GetChildren()) do
            if v:IsA("Frame") then oldVisibleFrames[v] = v.Visible end
        end
        clans.Visible = true
        for _, v in pairs(frames:GetChildren()) do
            if v:IsA("Frame") then v.Visible = false end
        end
        quests.Visible = true
        task.wait(0.1)
        Farming.refreshClanQuestCacheFromGui()
        if _G.refreshQuestTitles then _G.refreshQuestTitles() end
        task.wait(0.05)
        for frame, wasVisible in pairs(oldVisibleFrames) do
            if frame and frame.Parent then frame.Visible = wasVisible end
        end
        clans.Visible = oldClansVisible
        Core.debugLog("Refreshed clan quest info")
    end
end

-- ══════════════════════════════════════════════════════════════════
-- ELEMENT AUTO CYCLE
-- Cycles enabled element pull zones every 20 seconds
-- ══════════════════════════════════════════════════════════════════
-- HEARTSTEEL_MODULE_START: AutoCycle
-- Bundled from src/modules/AutoCycle.lua
do
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
-- HEARTSTEEL_MODULE_END: AutoCycle

-- ══════════════════════════════════════════════════════════════════
-- ELEMENT ZONE PULL — Fire / Water / Earth / Plasma
-- Starter / Advanced / Master / Grandmaster
-- ══════════════════════════════════════════════════════════════════
-- HEARTSTEEL_MODULE_START: ElementZonePull
-- Bundled from src/modules/ElementZonePull.lua
do
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
-- HEARTSTEEL_MODULE_END: ElementZonePull


-- ══════════════════════════════════════════════════════════════════
-- FLAGS — flag capture subsystem
-- ══════════════════════════════════════════════════════════════════
-- HEARTSTEEL_MODULE_START: Flags
-- Bundled from src/modules/Flags.lua
do
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
-- HEARTSTEEL_MODULE_END: Flags
-- ══════════════════════════════════════════════════════════════════
-- DUNGEON — timer, auto-start, egg incubator, chest, hover/hit
-- ══════════════════════════════════════════════════════════════════
do
    local Dungeon = HS.Dungeon
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

-- ══════════════════════════════════════════════════════════════════
-- UI — construction and rendering
-- ══════════════════════════════════════════════════════════════════
-- PETDEX FARM - auto-complete egg indexes
-- HEARTSTEEL_MODULE_START: PetdexFarm
-- Bundled from src/modules/PetdexFarm.lua
do
    local Petdex = HS.PetdexFarm or {}
    HS.PetdexFarm = Petdex
    local Core   = HS.Core

    Petdex.HATCH_DELAY = 0.35
    Petdex.TELEPORT_DELAY = 1.0
    Petdex.MIN_OPENED  = 10
    Petdex.initialized = false
    Petdex.running     = false
    Petdex.thread      = nil
    Petdex.teleportThread = nil
    Petdex.runId       = 0
    Petdex.teleportRunId = 0
    Petdex.eggOrder    = {}
    Petdex.eggPets     = {}
    Petdex.eventEggs   = {}
    Petdex.eventEggOrder = {}
    Petdex.eventEggPets = {}
    Petdex.shopPart    = nil
    Petdex.ClientData  = nil
    Petdex.status      = {
        state="Idle", egg="-", unlocked=0, target=0, counted=0, skip=0,
        opened=0, complete=0, total=0, ignoreSecrets=false,
    }
    Petdex.progressLabel = nil

    local function getOddsValue(info)
        if type(info) == "number" then return info end
        if type(info) ~= "table" then return math.huge end
        return tonumber(info.Odds or info.odds or info.Chance or info.chance or info.Probability or info.probability) or math.huge
    end

    local function getPetName(key, info)
        if type(info) == "string" then return info end
        if type(info) == "table" then
            return info.Name or info.PetName or info.petName or info.Pet or info.pet
        end
        return type(key) == "string" and key or nil
    end

    local function buildEggPets(eggData)
        local odds = type(eggData) == "table" and eggData.Odds or {}
        local pets = {}
        if type(odds) == "table" then
            for petKey, petInfo in pairs(odds) do
                local petName = getPetName(petKey, petInfo)
                if petName then pets[#pets + 1] = {name=tostring(petName), odds=getOddsValue(petInfo)} end
            end
        end
        table.sort(pets, function(a, b)
            if a.odds == b.odds then return a.name < b.name end
            return a.odds > b.odds
        end)
        return pets
    end

    local function getShopEggName(key, entry, eggsModule)
        if type(entry) == "table" and entry.EggName and eggsModule[entry.EggName] then
            return entry.EggName
        end
        if type(key) == "string" and eggsModule[key] then
            return key
        end
        if type(entry) == "string" and eggsModule[entry] then
            return entry
        end
        return nil
    end

    function Petdex.init()
        if Petdex.initialized then return true end
        local ok, err = pcall(function()
            local petsInfo = S.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetsInfo")
            local eggsModule = require(petsInfo:WaitForChild("Eggs"))
            local shopInfo = require(petsInfo:WaitForChild("PetShopInfo"))
            Petdex.ClientData = Core.getClientDataManager()
            local ordered = {}
            local normalEggs = {}
            for index, entry in pairs(shopInfo) do
                if type(index) == "string" and eggsModule[index] then normalEggs[index] = true end
                if type(entry) == "string" and eggsModule[entry] then normalEggs[entry] = true end
                if type(entry) == "table" and entry.EggName and eggsModule[entry.EggName] then normalEggs[entry.EggName] = true end
                local eggName = getShopEggName(index, entry, eggsModule)
                if eggName then
                    normalEggs[eggName] = true
                    local sortIndex = tonumber(index)
                    if type(entry) == "table" then
                        sortIndex = sortIndex or tonumber(entry.Index or entry.index)
                    end
                    ordered[#ordered + 1] = {index=sortIndex or math.huge, eggName=eggName}
                end
            end
            table.sort(ordered, function(a, b)
                if a.index == b.index then return a.eggName < b.eggName end
                return a.index < b.index
            end)
            table.clear(Petdex.eggOrder)
            table.clear(Petdex.eggPets)
            table.clear(Petdex.eventEggs)
            table.clear(Petdex.eventEggOrder)
            table.clear(Petdex.eventEggPets)
            local seen = {}
            for _, entry in ipairs(ordered) do
                local eggName = entry.eggName
                if not seen[eggName] then
                    seen[eggName] = true
                    Petdex.eggOrder[#Petdex.eggOrder + 1] = eggName
                    Petdex.eggPets[eggName] = buildEggPets(eggsModule[eggName])
                end
            end
            for eggName, eggData in pairs(eggsModule) do
                if not normalEggs[eggName] then
                    Petdex.eventEggs[eggName] = eggData
                    Petdex.eventEggOrder[#Petdex.eventEggOrder + 1] = eggName
                    Petdex.eventEggPets[eggName] = buildEggPets(eggData)
                end
            end
            table.sort(Petdex.eventEggOrder, function(a, b) return tostring(a) < tostring(b) end)
            Core.debugLog("Petdex: normal eggs loaded =", #Petdex.eggOrder)
            Core.debugLog("Petdex: event eggs detected =", #Petdex.eventEggOrder)
        end)
        Petdex.initialized = ok
        if not ok then
            Petdex.status.state = "Init failed"
            Core.debugLog("Petdex init failed:", err)
            Petdex.updateProgressLabel()
        end
        return ok
    end

    function Petdex.getData()
        local cd = Petdex.ClientData
        return cd and cd.Data or {}
    end

    function Petdex.getOwnedPets()
        local owned = {}
        local index = Petdex.getData().Index
        if type(index) ~= "table" then return owned end
        local seen = {}
        local function addFromTable(tbl)
            if seen[tbl] then return end
            seen[tbl] = true
            for key, value in pairs(tbl) do
                if value == true and type(key) == "string" then
                    owned[key] = true
                elseif type(value) == "string" then
                    owned[value] = true
                elseif type(value) == "table" then
                    local name = value.Name or value.PetName or value.petName or value.Pet or value.pet
                    if name then owned[tostring(name)] = true end
                    addFromTable(value)
                end
            end
        end
        addFromTable(index)
        return owned
    end

    function Petdex.getOpened(eggName)
        local opened = Petdex.getData().EggsOpened
        return type(opened) == "table" and (tonumber(opened[eggName]) or 0) or 0
    end

    function Petdex.getCountedPetsFrom(source, ignoreSecrets)
        source = source or {}
        local count = #source
        if ignoreSecrets and count == 10 then count -= 1 end
        return source, count
    end

    function Petdex.getCountedPets(eggName, ignoreSecrets)
        return Petdex.getCountedPetsFrom(Petdex.eggPets[eggName], ignoreSecrets)
    end

    function Petdex.getCountedEventPets(eggName, ignoreSecrets)
        return Petdex.getCountedPetsFrom(Petdex.eventEggPets[eggName], ignoreSecrets)
    end

    function Petdex.getSkipValue()
        return math.clamp(tonumber(Core.sliderState.petdex_skip) or 0, 0, 10)
    end

    function Petdex.getShopPart()
        local cached = Petdex.shopPart
        if cached and cached.Parent then return cached end
        local gameplay = workspace:FindFirstChild("Gameplay")
        local map = gameplay and gameplay:FindFirstChild("Map")
        local buildings = map and map:FindFirstChild("Buildings")
        local petShop = buildings and buildings:FindFirstChild("PetShopBuilding")
        Petdex.shopPart = petShop and petShop:FindFirstChild("MeshPart")
        return Petdex.shopPart
    end

    function Petdex.isInShop()
        local root = Core.getRoot()
        local part = Petdex.getShopPart()
        if not root or not part then return false end
        local localPos = part.CFrame:PointToObjectSpace(root.Position)
        local half = part.Size * 0.5
        return math.abs(localPos.X) <= half.X
            and math.abs(localPos.Y) <= half.Y + 8
            and math.abs(localPos.Z) <= half.Z
    end

    function Petdex.teleportToShop()
        local part = Petdex.getShopPart()
        if part then
            if not Core.waitForPriority("eggs", function()
                return Core.alive and (Core.state.petdex_auto_teleport or Core.state.auto_petdex or Core.state.auto_egg_opener)
            end) then return false end
            if not Core.claimPriority("eggs") then return false end
            return Core.teleportWorld(part.CFrame + Vector3.new(0, math.max(5, part.Size.Y * 0.5 + 3), 0), "pet shop", function()
                return Core.alive and (Core.state.petdex_auto_teleport or Core.state.auto_petdex or Core.state.auto_egg_opener)
            end)
        end
        return false
    end

    function Petdex.startTeleport()
        if Petdex.teleportThread then return end
        Petdex.teleportRunId += 1
        local teleportRunId = Petdex.teleportRunId
        Petdex.teleportThread = task.spawn(function()
            while Core.alive and Core.state.petdex_auto_teleport and Petdex.teleportRunId == teleportRunId do
                if Core.isWorldTeleportBlocked() then
                    task.wait(Petdex.TELEPORT_DELAY)
                    continue
                elseif not Petdex.isInShop() then
                    Petdex.teleportToShop()
                end
                task.wait(Petdex.TELEPORT_DELAY)
            end
            if Petdex.teleportRunId ~= teleportRunId then return end
            Petdex.teleportThread = nil
        end)
    end

    function Petdex.stopTeleport()
        Petdex.teleportRunId += 1
        Petdex.teleportThread = nil
        if not Core.state.auto_petdex and not Core.state.auto_egg_opener then
            Core.releasePriority("eggs")
        end
    end

    function Petdex.evaluateEgg(eggName, ownedPets, skipCount, ignoreSecrets)
        local pets, counted = Petdex.getCountedPets(eggName, ignoreSecrets)
        local target = math.clamp(counted - (tonumber(skipCount) or 0), 0, counted)
        local unlocked = 0
        for i = 1, counted do
            local pet = pets[i]
            if pet and ownedPets[pet.name] then unlocked += 1 end
        end
        local opened = Petdex.getOpened(eggName)
        return unlocked, target, counted, opened, unlocked >= target and opened >= Petdex.MIN_OPENED
    end

    function Petdex.evaluateEventEgg(eggName, ownedPets, ignoreSecrets)
        ownedPets = ownedPets or Petdex.getOwnedPets()
        local pets, counted = Petdex.getCountedEventPets(eggName, ignoreSecrets)
        local unlocked = 0
        local missing = {}
        for i = 1, counted do
            local pet = pets[i]
            if pet and ownedPets[pet.name] then
                unlocked += 1
            elseif pet then
                missing[#missing + 1] = pet.name
            end
        end
        local percent = counted > 0 and math.floor((unlocked / counted) * 100 + 0.5) or 0
        return unlocked, counted, counted, missing, percent, counted > 0 and unlocked >= counted
    end

    function Petdex.getEventEggProgress(ownedPets, ignoreSecrets)
        local progress = {}
        ownedPets = ownedPets or Petdex.getOwnedPets()
        for _, eggName in ipairs(Petdex.eventEggOrder or {}) do
            local unlocked, target, counted, missing, percent, complete = Petdex.evaluateEventEgg(eggName, ownedPets, ignoreSecrets)
            progress[#progress + 1] = {
                eggName=eggName,
                EggName=eggName,
                unlocked=unlocked,
                owned=unlocked,
                target=target,
                total=counted,
                counted=counted,
                missing=missing,
                percent=percent,
                complete=complete,
                completed=complete,
            }
        end
        return progress
    end

    function Petdex.countComplete(ownedPets, skipCount, ignoreSecrets)
        local done = 0
        for _, eggName in ipairs(Petdex.eggOrder) do
            local _, _, _, _, complete = Petdex.evaluateEgg(eggName, ownedPets, skipCount, ignoreSecrets)
            if complete then done += 1 end
        end
        return done
    end
    function Petdex.setStatus(state, eggName, unlocked, target, counted, opened, complete, total, ignoreSecrets, skipCount)
        Petdex.status.state = state or Petdex.status.state
        Petdex.status.egg = eggName or Petdex.status.egg
        Petdex.status.unlocked = unlocked or 0
        Petdex.status.target = target or 0
        Petdex.status.counted = counted or 0
        Petdex.status.skip = skipCount or 0
        Petdex.status.opened = opened or 0
        Petdex.status.complete = complete or 0
        Petdex.status.total = total or #Petdex.eggOrder
        Petdex.status.ignoreSecrets = ignoreSecrets == true
        Petdex.updateProgressLabel()
    end

    function Petdex.getProgressText()
        local s = Petdex.status
        return string.format(
            "Auto Petdex: %s\nEgg: %s\nUnlocked: %d / %d\nPets counted: %d\nSkip: %d\nOpened: %d / %d\nSecret ignored: %s\nEgg progress: %d / %d",
            s.state, s.egg, s.unlocked, s.target, s.counted,
            s.skip, s.opened, Petdex.MIN_OPENED, s.ignoreSecrets and "ON" or "OFF",
            s.complete, s.total
        )
    end

    function Petdex.updateProgressLabel()
        local lbl = Petdex.progressLabel
        if lbl and lbl.Parent then lbl.Text = Petdex.getProgressText() end
    end

    function Petdex.refreshProgress()
        if not Petdex.init() then return end
        local skipCount = Petdex.getSkipValue()
        local ignoreSecrets = Core.state.petdex_ignore_secrets == true
        local ownedPets = Petdex.getOwnedPets()
        local complete = Petdex.countComplete(ownedPets, skipCount, ignoreSecrets)
        Petdex.setStatus(Petdex.running and "Running" or "Idle", "-", 0, 0, 0, 0, complete, #Petdex.eggOrder, ignoreSecrets, skipCount)
    end

    function Petdex.stop()
        Petdex.runId += 1
        Petdex.running = false
        Petdex.thread = nil
        Petdex.status.state = "Idle"
        Core.clearCurrentAction("Opening Eggs for Petdex")
        Petdex.updateProgressLabel()
        if not Core.state.petdex_auto_teleport and not Core.state.auto_egg_opener then
            Core.releasePriority("eggs")
        end
    end

    function Petdex.start()
        if Petdex.running then return end
        if not Petdex.init() then
            Core.state.auto_petdex = false
            HS.Session.save()
            if Core.activeTab == "pets" then HS.UI.renderContent() end
            return
        end
        Petdex.running = true
        Petdex.runId += 1
        local runId = Petdex.runId
        Petdex.thread = task.spawn(function()
            while Core.alive and Core.state.auto_petdex and Petdex.running and Petdex.runId == runId do
                local skipCount = Petdex.getSkipValue()
                local ignoreSecrets = Core.state.petdex_ignore_secrets == true
                local ownedPets = Petdex.getOwnedPets()
                local complete = 0
                local nextEgg, nextUnlocked, nextTarget, nextCounted, nextOpened
                for _, eggName in ipairs(Petdex.eggOrder) do
                    local unlocked, target, counted, opened, isComplete = Petdex.evaluateEgg(eggName, ownedPets, skipCount, ignoreSecrets)
                    if isComplete then
                        complete += 1
                    elseif not nextEgg then
                        nextEgg, nextUnlocked, nextTarget, nextCounted, nextOpened = eggName, unlocked, target, counted, opened
                    end
                end

                if nextEgg and not Petdex.isInShop() then
                    if Core.state.petdex_auto_teleport then Petdex.teleportToShop() end
                    Petdex.setStatus("Paused", nextEgg, nextUnlocked, nextTarget, nextCounted, nextOpened, complete, #Petdex.eggOrder, ignoreSecrets, skipCount)
                    task.wait(Petdex.TELEPORT_DELAY)
                    continue
                end

                if not nextEgg then
                    Core.state.auto_petdex = false
                    Petdex.running = false
                    Petdex.setStatus("Complete", "-", 0, 0, 0, 0, complete, #Petdex.eggOrder, ignoreSecrets, skipCount)
                    if not Core.state.petdex_auto_teleport and not Core.state.auto_egg_opener then
                        Core.releasePriority("eggs")
                    end
                    HS.Session.save()
                    if Core.activeTab == "pets" then HS.UI.renderContent() end
                    break
                end
                Petdex.setStatus("Running", nextEgg, nextUnlocked, nextTarget, nextCounted, nextOpened, complete, #Petdex.eggOrder, ignoreSecrets, skipCount)
                if not Core.waitForPriority("eggs", function()
                    return Core.alive and Core.state.auto_petdex and Petdex.running and Petdex.runId == runId
                end) then break end
                if not Core.claimPriority("eggs") then
                    task.wait(Petdex.HATCH_DELAY)
                    continue
                end
                Core.setCurrentAction("Opening Eggs for Petdex", math.max(2, Petdex.HATCH_DELAY + 1))
                pcall(function() Core.UIActionRemote:FireServer("BuyEgg", nextEgg) end)
                task.wait(Petdex.HATCH_DELAY)
            end
            if Petdex.runId ~= runId then return end
            Petdex.running = false
            Petdex.thread = nil
            if Petdex.status.state == "Running" then
                Petdex.status.state = "Idle"
                Petdex.updateProgressLabel()
            end
            Core.clearCurrentAction("Opening Eggs for Petdex")
        end)
    end
end
end
-- HEARTSTEEL_MODULE_END: PetdexFarm

-- PETS - inventory craft/evolve automation
-- HEARTSTEEL_MODULE_START: Pets
-- Bundled from src/modules/Pets.lua
do
    local Pets = HS.Pets or {}
    HS.Pets = Pets

    local Core = HS.Core

    Pets.STATE_KEY       = "auto_craft_pets"
    Pets.ALLOW_EQUIPPED  = "auto_craft_allow_equipped"
    Pets.REQUIRED_COUNT  = 10
    Pets.SCAN_DELAY      = 1.5
    Pets.CRAFT_COOLDOWN  = 2.0
    Pets.DEBUG           = true
    Pets.statusLabel     = nil
    Pets.status          = "Auto Craft: waiting"

    function Pets.debugPrint(...)
        if not Pets.DEBUG or Core.state.debug_mode ~= true then return end
        local parts = {"[Heartsteel][Pets]"}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        print(table.concat(parts, " "))
    end

    function Pets.setStatus(text)
        Pets.status = text or Pets.status
        if Pets.statusLabel and Pets.statusLabel.Parent then
            Pets.statusLabel.Text = Pets.status
        end
    end

    function Pets.getInventoryFrame()
        local gui = Core.playerGui:FindFirstChild("MainGui")
        local otherFrames = gui and gui:FindFirstChild("OtherFrames")
        local petsInventory = otherFrames and otherFrames:FindFirstChild("PetsInventory")
        local frame = petsInventory and petsInventory:FindFirstChild("Frame")
        return frame and frame:FindFirstChild("ScrollingFrame")
    end

    function Pets.parseLevel(text)
        if type(text) ~= "string" then return 0 end
        return tonumber(text:match("(%d+)")) or 0
    end

    function Pets.isVisible(guiObject)
        return guiObject and guiObject:IsA("GuiObject") and guiObject.Visible == true
    end

    function Pets.getPetId(petFrame, button)
        local candidates = {
            petFrame.Name,
            petFrame:GetAttribute("PetID"),
            petFrame:GetAttribute("PetId"),
            petFrame:GetAttribute("ID"),
            button and button:GetAttribute("PetID"),
            button and button:GetAttribute("PetId"),
            button and button:GetAttribute("ID"),
        }

        for _, value in ipairs(candidates) do
            if value ~= nil and tostring(value) ~= "" then
                return tostring(value)
            end
        end
        return nil
    end

    function Pets.readPet(petFrame)
        if not (petFrame and petFrame:IsA("Frame") and petFrame.Visible) then return nil end
        local button = petFrame:FindFirstChild("Button")
        local holder = button and button:FindFirstChild("Holder")
        local flatPet = holder and holder:FindFirstChild("FlatPet")
        local underlay = holder and holder:FindFirstChild("Underlay")
        local levelText = button and button:FindFirstChild("LevelText")
        local locked = button and button:FindFirstChild("Locked")
        local equipped = button and button:FindFirstChild("Equipped")
        local petId = Pets.getPetId(petFrame, button)
        local petImage = flatPet and flatPet.Image or "N/A"
        local underlayImage = underlay and underlay.Image or "NORMAL"
        if not petId then return nil end
        return {
            ID = petId,
            key = petImage .. "|" .. underlayImage,
            petImage = petImage,
            underlayImage = underlayImage,
            level = Pets.parseLevel(levelText and levelText.Text),
            locked = Pets.isVisible(locked),
            equipped = Pets.isVisible(equipped),
        }
    end

    function Pets.collectPetFrames(inventory)
        local frames = {}
        local seen = {}

        local function addFrame(frame)
            if seen[frame] then return end
            seen[frame] = true
            if not frame.Visible then return end
            frames[#frames + 1] = frame
        end

        for _, child in ipairs(inventory:GetChildren()) do
            if child:IsA("Frame") then addFrame(child) end
        end

        return frames
    end

    function Pets.addVisibleGroups(inventory, groups)
        local maxCount = 0
        for _, frame in ipairs(Pets.collectPetFrames(inventory)) do
            local pet = Pets.readPet(frame)
            if pet then
                local group = groups[pet.key]
                if not group then
                    group = {
                        PetImage = pet.petImage,
                        Underlay = pet.underlayImage,
                        Pets = {},
                    }
                    groups[pet.key] = group
                end
                group.Pets[#group.Pets + 1] = pet
            end
        end

        for _, group in pairs(groups) do
            if #group.Pets > maxCount then maxCount = #group.Pets end
        end
        return maxCount
    end

    function Pets.scanGroups()
        local groups = {}
        local maxCount = 0
        local inventory = Pets.getInventoryFrame()
        if not inventory then
            Pets.setStatus("Auto Craft: inventory missing")
            Pets.debugPrint("inventory missing at MainGui.OtherFrames.PetsInventory.Frame.ScrollingFrame")
            return groups, 0
        end

        maxCount = math.max(maxCount, Pets.addVisibleGroups(inventory, groups))

        return groups, maxCount
    end

    function Pets.chooseCraftGroup()
        Pets.setStatus("Auto Craft: scanning")
        local groups, maxCount = Pets.scanGroups()
        local bestGroup
        local bestUsable
        local allowEquipped = Core.state[Pets.ALLOW_EQUIPPED] == true
        for _, group in pairs(groups) do
            table.sort(group.Pets, function(a, b)
                if a.level == b.level then return tostring(a.ID) < tostring(b.ID) end
                return a.level > b.level
            end)

            local usable = {}
            local protected = {}
            for _, pet in ipairs(group.Pets) do
                if pet.locked or (pet.equipped and not allowEquipped) then
                    protected[#protected + 1] = pet
                else
                    usable[#usable + 1] = pet
                end
            end

            if #usable >= Pets.REQUIRED_COUNT and (not bestUsable or #usable > #bestUsable) then
                bestGroup = group
                bestUsable = usable
            end
        end

        if not bestUsable then
            Pets.setStatus(string.format("Auto Craft: found %d/%d", math.min(maxCount, Pets.REQUIRED_COUNT), Pets.REQUIRED_COUNT))
            Pets.debugPrint("no craftable group found", "max raw group=", maxCount, "required usable=", Pets.REQUIRED_COUNT)
            return nil
        end

        Pets.debugPrint(
            "selected craft",
            "FlatPet.Image=", bestGroup.PetImage,
            "Underlay.Image=", bestGroup.Underlay,
            "usable=", #bestUsable,
            "allow equipped=", allowEquipped,
            "base=", bestUsable[1].ID,
            "level=", bestUsable[1].level
        )

        return bestUsable[1]
    end

    function Pets.tryCraftOne()
        local mainPet = Pets.chooseCraftGroup()
        if not (mainPet and mainPet.ID and mainPet.ID ~= "") then
            task.wait(Pets.SCAN_DELAY)
            return
        end

        Pets.setStatus("Auto Craft: crafting")
        Pets.debugPrint("firing CombinePet", mainPet.ID)
        local ok, err = pcall(function() Core.UIActionRemote:FireServer("CombinePet", mainPet.ID) end)
        Pets.debugPrint("CombinePet result", ok, err or "ok")
        task.wait(Pets.CRAFT_COOLDOWN)
        Pets.setStatus("Auto Craft: waiting")
    end

    function Pets.startAutoCraft()
        Pets.setStatus("Auto Craft: scanning")
        Pets.debugPrint("auto craft started")
        Core.loopWhile(Pets.STATE_KEY, Pets.SCAN_DELAY, Pets.tryCraftOne)
    end

    function Pets.stopAutoCraft()
        Pets.setStatus("Auto Craft: waiting")
        Pets.debugPrint("auto craft stopped")
    end
end
-- HEARTSTEEL_MODULE_END: Pets

-- PETDEX REWARDS - auto-claim unlocked pet count milestones
-- HEARTSTEEL_MODULE_START: PetdexRewards
-- Bundled from src/modules/PetdexRewards.lua
do
    local Rewards = HS.PetdexRewards or {}
    HS.PetdexRewards = Rewards

    local Core    = HS.Core

    Rewards.STATE_KEY   = "auto_petdex_rewards"
    Rewards.CLAIM_DELAY = 0.3
    Rewards.SCAN_DELAY  = 5
    Rewards.ClientData  = nil
    Rewards.rewardInfo  = nil
    Rewards.rewardList  = {}
    Rewards.running     = false
    Rewards.thread      = nil
    Rewards.runId       = 0
    Rewards.statusLabel = nil
    Rewards.status      = {
        state="Idle", unlocked=0, completedEggs=0, claimed=0, total=0, nextReward="-",
    }

    function Rewards.init()
        if Rewards.ClientData and #Rewards.rewardList > 0 then return true end
        local ok, data, rewardInfo = pcall(function()
            local clientData = (HS.PetdexFarm and HS.PetdexFarm.ClientData) or Core.getClientDataManager()
            local info = require(S.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetdexRewardInfo"))
            return clientData, info
        end)
        if ok and data and rewardInfo and type(rewardInfo.Items) == "table" then
            Rewards.ClientData = data
            Rewards.rewardInfo = rewardInfo
            Rewards.buildRewardList()
            return true
        end
        Core.debugLog("Petdex rewards init failed:", data, rewardInfo)
        return false
    end

    function Rewards.getData()
        local cd = Rewards.ClientData
        return cd and cd.Data or {}
    end

    function Rewards.buildRewardList()
        table.clear(Rewards.rewardList)
        local items = Rewards.rewardInfo and Rewards.rewardInfo.Items
        if type(items) ~= "table" then return end

        for key, item in pairs(items) do
            if type(key) == "string" and type(item) == "table" then
                local petsNeeded = tonumber(item.PetsNeeded)
                local eggsNeeded = tonumber(item.EggsNeeded)
                if petsNeeded or eggsNeeded then
                    local order = tonumber(item.Order)
                    local needed = petsNeeded or eggsNeeded or 0
                    Rewards.rewardList[#Rewards.rewardList + 1] = {
                        Key=key,
                        Data=item,
                        PetsNeeded=petsNeeded,
                        EggsNeeded=eggsNeeded,
                        Order=order,
                        Needed=needed,
                        key=key,
                        petsNeeded=petsNeeded,
                        eggsNeeded=eggsNeeded,
                        order=order,
                        needed=needed,
                    }
                end
            end
        end

        table.sort(Rewards.rewardList, function(a, b)
            local ao = a.Order or a.order or math.huge
            local bo = b.Order or b.order or math.huge
            if ao ~= bo then return ao < bo end
            local an = a.Needed or a.needed or 0
            local bn = b.Needed or b.needed or 0
            if an ~= bn then return an < bn end
            return (a.Key or a.key) < (b.Key or b.key)
        end)

        Core.debugLog("Petdex rewards loaded:", #Rewards.rewardList)
    end

    function Rewards.getUnlockedCount()
        local index = Rewards.getData().Index
        if type(index) ~= "table" then return 0 end

        local owned = {}
        local seenTables = {}

        local function markPetName(name)
            if type(name) == "string" and name ~= "" then
                owned[name] = true
            end
        end

        local function scan(tbl)
            if seenTables[tbl] then return end
            seenTables[tbl] = true

            for key, value in pairs(tbl) do
                if value == true then markPetName(key) end
                if type(value) == "string" then
                    markPetName(value)
                elseif type(value) == "table" then
                    markPetName(value.Name or value.PetName or value.petName or value.Pet or value.pet)
                    scan(value)
                end
            end
        end

        scan(index)

        local count = 0
        for _ in pairs(owned) do
            count += 1
        end

        return count > 0 and count or #index
    end

    function Rewards.getCompletedEggCount()
        local Petdex = HS.PetdexFarm
        if not Petdex or not Petdex.init or not Petdex.init() then return 0 end

        local completedNormal = 0
        local completedEvent = 0
        local countedEggs = {}
        local ownedPets = Petdex.getOwnedPets()

        for _, eggName in ipairs(Petdex.eggOrder or {}) do
            -- Egg rewards require a full regular egg completion. The Petdex skip
            -- slider is intentionally ignored here; secret pets are not required.
            local pets, required = Petdex.getCountedPets(eggName, true)

            if required > 0 then
                local complete = true
                for i = 1, required do
                    local pet = pets[i]
                    if not pet or not ownedPets[pet.name] then
                        complete = false
                        break
                    end
                end

                if complete then
                    completedNormal += 1
                    countedEggs[eggName] = true
                end
            end
        end

        for _, eggName in ipairs(Petdex.eventEggOrder or {}) do
            if not countedEggs[eggName] then
                local _, _, counted, _, _, complete = Petdex.evaluateEventEgg(eggName, ownedPets, true)
                if counted > 0 and complete then
                    completedEvent += 1
                    countedEggs[eggName] = true
                end
            end
        end

        local total = completedNormal + completedEvent
        Core.debugLog("Petdex Rewards: completed normal eggs =", completedNormal)
        Core.debugLog("Petdex Rewards: completed event eggs =", completedEvent)
        Core.debugLog("Petdex Rewards: total completed eggs =", total)
        return total
    end

    function Rewards.getClaimedSet()
        local claimed = Rewards.getData().PetdexRewardsClaimed
        local set = {}
        if type(claimed) ~= "table" then return set end

        local function markReward(value)
            if type(value) == "number" then
                set["Pets" .. tostring(value)] = true
            elseif type(value) == "string" then
                if value:match("^Pets%d+$") or value:match("^Eggs%d+$") then
                    set[value] = true
                else
                    local rewardValue = tonumber(value:match("(%d+)"))
                    if rewardValue then set["Pets" .. tostring(rewardValue)] = true end
                end
            end
        end

        for key, value in pairs(claimed) do
            if value == true then
                markReward(key)
            elseif value ~= false and value ~= nil then
                if type(key) ~= "number" then markReward(key) end
                markReward(value)
            end
        end
        return set
    end

    function Rewards.claimReward(rewardKey)
        if type(rewardKey) ~= "string" or rewardKey == "" then
            Core.debugLog("Petdex reward skipped:", tostring(rewardKey))
            return false
        end

        Core.debugLog("Petdex Rewards: claiming", rewardKey)
        local ok, err = pcall(function()
            Core.UIActionRemote:FireServer("ClaimPetdexReward", rewardKey)
        end)
        if not ok then
            Core.debugLog("Petdex reward claim failed:", rewardKey, tostring(err))
        end
        return ok
    end

    function Rewards.makeSnapshot(unlocked, completedEggs, claimedSet)
        local claimedCount = 0
        local nextReward = "-"
        local claimable = {}

        for _, reward in ipairs(Rewards.rewardList) do
            local rewardKey = reward.Key or reward.key
            local petsNeeded = reward.PetsNeeded or reward.petsNeeded
            local eggsNeeded = reward.EggsNeeded or reward.eggsNeeded

            if type(rewardKey) ~= "string" or rewardKey == "" then
                Core.debugLog("Petdex reward skipped:", tostring(rewardKey))
                continue
            end

            if claimedSet[rewardKey] then
                claimedCount += 1
            elseif nextReward == "-" then
                nextReward = rewardKey
            end

            local canClaim = false
            if petsNeeded then
                canClaim = unlocked >= petsNeeded
            elseif eggsNeeded then
                canClaim = completedEggs >= eggsNeeded
            end

            if canClaim and not claimedSet[rewardKey] then
                claimable[#claimable + 1] = rewardKey
            end
        end

        return {
            unlocked=unlocked,
            completedEggs=completedEggs,
            claimed=claimedCount,
            total=#Rewards.rewardList,
            nextReward=nextReward,
            claimable=claimable,
            claimedSet=claimedSet,
        }
    end

    function Rewards.getSnapshot()
        if not Rewards.init() then
            return {unlocked=0, completedEggs=0, claimed=0, total=0, nextReward="-", claimable={}}
        end
        local unlocked = Rewards.getUnlockedCount()
        local completedEggs = Rewards.getCompletedEggCount()
        local claimedSet = Rewards.getClaimedSet()
        local snapshot = Rewards.makeSnapshot(unlocked, completedEggs, claimedSet)
        Core.debugLog(
            "Petdex rewards scan:",
            "loaded=", snapshot.total,
            "unlockedPets=", unlocked,
            "completedEggs=", completedEggs,
            "claimed=", snapshot.claimed
        )
        return snapshot
    end

    function Rewards.setStatus(state, snapshot)
        local snap = snapshot or Rewards.getSnapshot()
        Rewards.status.state = state or Rewards.status.state
        Rewards.status.unlocked = snap.unlocked or 0
        Rewards.status.completedEggs = snap.completedEggs or 0
        Rewards.status.claimed = snap.claimed or 0
        Rewards.status.total = snap.total or #Rewards.rewardList
        Rewards.status.nextReward = snap.nextReward or "-"
        Rewards.updateStatusLabel()
    end

    function Rewards.getStatusText()
        local s = Rewards.status
        return string.format(
            "Petdex Rewards: %s\nUnlocked Pets: %d\nCompleted Eggs: %d\nClaimed: %d / %d\nNext Reward: %s",
            s.state, s.unlocked, s.completedEggs or 0, s.claimed, s.total, s.nextReward
        )
    end

    function Rewards.updateStatusLabel()
        local lbl = Rewards.statusLabel
        if lbl and lbl.Parent then lbl.Text = Rewards.getStatusText() end
    end

    function Rewards.refreshStatus()
        if Rewards.running then
            local state = Rewards.status.state ~= "Idle" and Rewards.status.state or "Running"
            Rewards.setStatus(state)
        else
            Rewards.setStatus(Rewards.status.state or "Idle")
        end
    end

    function Rewards.stop()
        Rewards.runId += 1
        Rewards.running = false
        Rewards.thread = nil
        Rewards.setStatus("Idle")
        Core.clearCurrentAction("Claiming Petdex Rewards")
    end

    function Rewards.start()
        if Rewards.running then return end
        if not Rewards.init() then
            Core.state[Rewards.STATE_KEY] = false
            HS.Session.save()
            if Core.activeTab == "pets" then HS.UI.renderContent() end
            return
        end

        Rewards.running = true
        Rewards.runId += 1
        local runId = Rewards.runId
        Rewards.thread = task.spawn(function()
            while Core.alive and Core.state[Rewards.STATE_KEY] and Rewards.running and Rewards.runId == runId do
                local snapshot = Rewards.getSnapshot()
                local stateText = snapshot.claimed >= snapshot.total and "Complete" or "Waiting"
                Rewards.setStatus(#snapshot.claimable > 0 and "Running" or stateText, snapshot)

                if #snapshot.claimable > 0 then
                    local unlocked = snapshot.unlocked or 0
                    local completedEggs = snapshot.completedEggs or 0
                    local claimedSet = snapshot.claimedSet or {}
                    for _, rewardKey in ipairs(snapshot.claimable) do
                        if not (Core.alive and Core.state[Rewards.STATE_KEY] and Rewards.running and Rewards.runId == runId) then
                            break
                        end
                        if not claimedSet[rewardKey] then
                            Core.setCurrentAction("Claiming Petdex Rewards", math.max(2, Rewards.CLAIM_DELAY + 1))
                            if Rewards.claimReward(rewardKey) then
                                claimedSet[rewardKey] = true
                                task.wait(Rewards.CLAIM_DELAY)
                                Rewards.setStatus("Running", Rewards.makeSnapshot(unlocked, completedEggs, claimedSet))
                            end
                        else
                            Core.debugLog("Petdex reward already claimed:", rewardKey)
                        end
                    end
                end

                local elapsed = 0
                while elapsed < Rewards.SCAN_DELAY and Core.alive and Core.state[Rewards.STATE_KEY] and Rewards.running and Rewards.runId == runId do
                    task.wait(0.5)
                    elapsed += 0.5
                end
            end

            if Rewards.runId ~= runId then return end
            Rewards.running = false
            if Rewards.status.state == "Running" or Rewards.status.state == "Waiting" then
                Rewards.setStatus("Idle")
            end
            Rewards.thread = nil
            Core.clearCurrentAction("Claiming Petdex Rewards")
        end)
    end
end
-- HEARTSTEEL_MODULE_END: PetdexRewards

-- EGG OPENER - selected page/slot auto hatch
-- HEARTSTEEL_MODULE_START: EggOpener
-- Bundled from src/modules/EggOpener.lua
do
    local EggOpener = HS.EggOpener or {}
    HS.EggOpener = EggOpener

    local Core      = HS.Core

    EggOpener.STATE_KEY    = "auto_egg_opener"
    EggOpener.PAGE_SIZE    = 12
    EggOpener.HATCH_DELAY  = 0.35
    EggOpener.initialized  = false
    EggOpener.running      = false
    EggOpener.status       = "Idle"
    EggOpener.thread       = nil
    EggOpener.runId        = 0
    EggOpener.eggOrder     = {}
    EggOpener.ClientData   = nil
    EggOpener.statusLabel  = nil
    EggOpener.selection    = {
        eggName="-", page=1, slot=1, index=1, opened=0,
        valid=false, unlocked=false,
    }

    function EggOpener.init()
        if EggOpener.initialized then return true end
        local ok, err = pcall(function()
            local petsInfo = S.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetsInfo")
            local shopInfo = require(petsInfo:WaitForChild("PetShopInfo"))
            EggOpener.ClientData = Core.getClientDataManager()

            local ordered = {}
            for index, entry in pairs(shopInfo) do
                if type(entry) == "table" and entry.EggName then
                    ordered[#ordered + 1] = {index=tonumber(index) or tonumber(entry.Index or entry.index) or math.huge, eggName=entry.EggName}
                end
            end
            table.sort(ordered, function(a, b) return a.index < b.index end)

            table.clear(EggOpener.eggOrder)
            local seen = {}
            for _, entry in ipairs(ordered) do
                if not seen[entry.eggName] then
                    seen[entry.eggName] = true
                    EggOpener.eggOrder[#EggOpener.eggOrder + 1] = entry.eggName
                end
            end
        end)
        EggOpener.initialized = ok
        if not ok then
            Core.debugLog("Egg opener init failed:", err)
        end
        EggOpener.updateSelection()
        return ok
    end

    function EggOpener.getData()
        local cd = EggOpener.ClientData
        return cd and cd.Data or {}
    end

    function EggOpener.getOpenedTable()
        local opened = EggOpener.getData().EggsOpened
        return type(opened) == "table" and opened or {}
    end

    function EggOpener.getMaxPage()
        return math.max(1, math.ceil(#EggOpener.eggOrder / EggOpener.PAGE_SIZE))
    end

    function EggOpener.updateSelection()
        if not EggOpener.initialized then
            EggOpener.selection.eggName = "-"
            EggOpener.selection.valid = false
            EggOpener.updateStatusLabel()
            return
        end

        local maxPage = EggOpener.getMaxPage()
        local page = math.clamp(tonumber(Core.sliderState.egg_opener_page) or 1, 1, maxPage)
        local slot = math.clamp(tonumber(Core.sliderState.egg_opener_slot) or 1, 1, EggOpener.PAGE_SIZE)
        Core.sliderState.egg_opener_page = page
        Core.sliderState.egg_opener_slot = slot

        local index = ((page - 1) * EggOpener.PAGE_SIZE) + slot
        local eggName = EggOpener.eggOrder[index]
        local openedTable = EggOpener.getOpenedTable()
        local unlocked = eggName ~= nil and openedTable[eggName] ~= nil

        EggOpener.selection.page = page
        EggOpener.selection.slot = slot
        EggOpener.selection.index = index
        EggOpener.selection.eggName = eggName or "-"
        EggOpener.selection.opened = eggName and (tonumber(openedTable[eggName]) or 0) or 0
        EggOpener.selection.unlocked = unlocked == true
        EggOpener.selection.valid = unlocked == true
        EggOpener.updateStatusLabel()
    end

    function EggOpener.getStatusText()
        local s = EggOpener.selection
        local state = EggOpener.running and EggOpener.status or "Idle"
        if s.eggName ~= "-" and not s.unlocked then state = "Locked" end
        return string.format(
            "Auto Egg Opener: %s\nEgg: %s\nPage: %d\nSlot: %d\nOpened: %d",
            state, s.eggName, s.page, s.slot, s.opened
        )
    end

    function EggOpener.updateStatusLabel()
        local lbl = EggOpener.statusLabel
        if lbl and lbl.Parent then lbl.Text = EggOpener.getStatusText() end
    end

    function EggOpener.stop()
        EggOpener.runId += 1
        EggOpener.running = false
        EggOpener.status = "Idle"
        EggOpener.thread = nil
        Core.clearCurrentAction("Opening Selected Egg")
        EggOpener.updateStatusLabel()
        if not Core.state.petdex_auto_teleport and not Core.state.auto_petdex then
            Core.releasePriority("eggs")
        end
    end

    function EggOpener.start()
        if EggOpener.running then return end
        if not EggOpener.init() then
            Core.state[EggOpener.STATE_KEY] = false
            HS.Session.save()
            if Core.activeTab == "pets" then HS.UI.renderContent() end
            return
        end

        EggOpener.running = true
        EggOpener.status = "Running"
        EggOpener.runId += 1
        local runId = EggOpener.runId
        EggOpener.thread = task.spawn(function()
            while Core.alive and Core.state[EggOpener.STATE_KEY] and EggOpener.running and EggOpener.runId == runId do
                local s = EggOpener.selection
                if not HS.PetdexFarm.isInShop() then
                    if Core.state.petdex_auto_teleport then HS.PetdexFarm.teleportToShop() end
                    EggOpener.status = "Paused"
                    EggOpener.updateStatusLabel()
                    task.wait(HS.PetdexFarm.TELEPORT_DELAY or EggOpener.HATCH_DELAY)
                    continue
                end

                if s.valid and s.eggName ~= "-" then
                    if not Core.waitForPriority("eggs", function()
                        return Core.alive and Core.state[EggOpener.STATE_KEY] and EggOpener.running and EggOpener.runId == runId
                    end) then break end
                    if not Core.claimPriority("eggs") then
                        task.wait(EggOpener.HATCH_DELAY)
                        continue
                    end
                    EggOpener.status = "Running"
                    Core.setCurrentAction("Opening Selected Egg", math.max(2, EggOpener.HATCH_DELAY + 1))
                    pcall(function() Core.UIActionRemote:FireServer("BuyEgg", s.eggName) end)
                end
                task.wait(EggOpener.HATCH_DELAY)
                EggOpener.updateSelection()
            end
            if EggOpener.runId ~= runId then return end
            EggOpener.running = false
            EggOpener.status = "Idle"
            EggOpener.thread = nil
            Core.clearCurrentAction("Opening Selected Egg")
            EggOpener.updateStatusLabel()
        end)
    end
end
-- HEARTSTEEL_MODULE_END: EggOpener

-- MERCHANT - traveling merchant item filters and auto-buy
-- HEARTSTEEL_MODULE_START: Merchant
-- Bundled from src/modules/Merchant.lua
do
    local Merchant = HS.Merchant or {}
    HS.Merchant = Merchant
    local Core     = HS.Core
    local MERCHANT_RARITY_ICON_ASSETS = {
        Star = "rbxassetid://PASTE_STAR_ICON",
        Moon = "rbxassetid://PASTE_MOON_ICON",
        Sun = "rbxassetid://PASTE_SUN_ICON",
    }

    Merchant.STATE_KEY   = "buy_merchant"
    Merchant.BUY_DELAY   = 1
    Merchant.CLICK_DELAY = 0.12
    Merchant.statusLabel = nil
    Merchant.status      = "waiting"
    Merchant.initialized = false
    Merchant.listings    = {}
    Merchant.allowedIndexes = {}
    Merchant.uiItems     = nil
    Merchant.lastCrownMulti = nil
    Merchant.displayWatcherThread = nil

    function Merchant.setStatus(text)
        Merchant.status = text or Merchant.status
        if Merchant.statusLabel and Merchant.statusLabel.Parent then
            Merchant.statusLabel.Text = "Merchant: " .. Merchant.status
        end
    end

    function Merchant.exists()
        local merchant = workspace:FindFirstChild("Merchant")
        local locations = merchant and merchant:FindFirstChild("Locations")
        return locations and locations:FindFirstChild("EventMerchant") ~= nil
    end

    function Merchant.getData()
        local ClientData = Core.getClientDataManager()
        local data = ClientData and ClientData.Data
        return data and data.TravelingMerchant or nil
    end

    function Merchant.getCrownMulti()
        local data = Merchant.getData()
        return tonumber(data and data.CrownMulti) or 1
    end

    function Merchant.formatCompact(value)
        local num = tonumber(value) or 0
        local suffixes = {"","K","M","B","T","q","Q","s","S","O","N","d","U"}
        local idx = 1
        while math.abs(num) >= 1000 and idx < #suffixes do
            num /= 1000
            idx += 1
        end
        local text = idx == 1 and tostring(math.floor(num + 0.5)) or string.format("%.2f", num)
        text = text:gsub("%.00$", ""):gsub("(%.%d)0$", "%1")
        return text .. suffixes[idx]
    end

    function Merchant.isBoostListing(listing)
        local name = tostring(listing.Name or ""):lower()
        local itemType = tostring(listing.Type or ""):lower()
        local class = tostring(listing.Class or ""):lower()
        return (name .. " " .. itemType .. " " .. class):find("boost", 1, true) ~= nil
    end

    function Merchant.formatDuration(value)
        if type(value) == "string" and value:find("%a") then
            return value
        end

        local seconds = tonumber(value)
        if not seconds then return tostring(value or "") end
        seconds = math.max(0, math.floor(seconds + 0.5))

        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        local secs = seconds % 60

        if hours > 0 then
            return minutes > 0 and string.format("%dh %dm", hours, minutes) or string.format("%dh", hours)
        end
        if minutes > 0 then
            return secs > 0 and string.format("%dm %ds", minutes, secs) or string.format("%dm", minutes)
        end
        return string.format("%ds", secs)
    end

    function Merchant.getBestEggRarityNumber(name)
        return tonumber(tostring(name or ""):match("^BEST_EGG_RARITY_(%d+)$"))
    end

    function Merchant.getPetIconInfo(name)
        local rarity = Merchant.getBestEggRarityNumber(name)
        if not rarity then return nil end

        if rarity <= 5 then
            return "Star", rarity
        elseif rarity <= 8 then
            return "Moon", rarity - 5
        elseif rarity == 9 then
            return "Sun", 1
        end
    end

    function Merchant.getRarityAsset(iconType)
        local asset = MERCHANT_RARITY_ICON_ASSETS[iconType]
        if type(asset) ~= "string" or asset == "" or asset:find("PASTE_", 1, true) then return nil end
        return asset
    end

    function Merchant.getRarityFallbackText(name)
        local rarity = Merchant.getBestEggRarityNumber(name)
        if not rarity then return tostring(name or "Pet") end

        if rarity <= 5 then
            return string.rep("★", rarity) .. " Pet"
        elseif rarity <= 8 then
            local count = rarity - 5
            return (count == 1 and "Moon" or tostring(count) .. " Moon") .. " Pet"
        elseif rarity == 9 then
            return "Sun Pet"
        end

        return "Pet"
    end

    function Merchant.getPetRarityDisplay(listing)
        if tostring(listing.Type or "") ~= "Pets" then return nil end
        local iconType, iconCount = Merchant.getPetIconInfo(listing.Name)
        if not iconType then return nil end

        return {
            iconType=iconType,
            iconCount=iconCount,
            asset=Merchant.getRarityAsset(iconType),
            fallbackText=Merchant.getRarityFallbackText(listing.Name),
            classText=tostring(listing.Class or ""),
        }
    end

    function Merchant.makeLabel(listing)
        local name = tostring(listing.Name or listing.ItemName or "Item")
        local petRarity = Merchant.getPetRarityDisplay(listing)
        if petRarity then
            name = (petRarity.classText ~= "" and (petRarity.classText .. " ") or "") .. petRarity.fallbackText
        end
        local amountText = ""
        if Merchant.isBoostListing(listing) then
            local duration = listing.Duration or listing.Time or listing.Seconds or listing.Amount
            if duration then amountText = " " .. Merchant.formatDuration(duration) end
        else
            local amount = listing.Amount or listing.Duration
            amountText = amount and (" x" .. tostring(amount)) or ""
        end
        local priceText = Merchant.formatCompact((tonumber(listing.CrownsPrice) or 0) * Merchant.getCrownMulti())
        local odds = tonumber(listing.Odds) or 0
        return string.format("%s%s - %s 👑 - %s%%", name, amountText, priceText, tostring(odds))
    end

    function Merchant.makeLabelSuffix(listing)
        local priceText = Merchant.formatCompact((tonumber(listing.CrownsPrice) or 0) * Merchant.getCrownMulti())
        local odds = tonumber(listing.Odds) or 0
        return string.format(" - %s 👑 - %s%%", priceText, tostring(odds))
    end

    function Merchant.isRelevantListing(listing)
        if type(listing) ~= "table" then return false end
        local name = tostring(listing.Name or ""):lower()
        local itemType = tostring(listing.Type or ""):lower()
        local class = tostring(listing.Class or ""):lower()

        if listing.RobuxPrice or listing.ProductId or listing.DeveloperProductId then return false end
        if name:find("superitem", 1, true) or itemType:find("superitem", 1, true) or class:find("superitem", 1, true) then return false end
        if not listing.CrownsPrice then return false end

        local haystack = name .. " " .. itemType .. " " .. class
        return haystack:find("charm", 1, true)
            or haystack:find("pet", 1, true)
            or haystack:find("boost", 1, true)
    end

    function Merchant.getCategory(listing)
        local name = tostring(listing.Name or ""):lower()
        local itemType = tostring(listing.Type or ""):lower()
        local class = tostring(listing.Class or ""):lower()
        local haystack = name .. " " .. itemType .. " " .. class

        if haystack:find("charm", 1, true) then return "Charms", 1 end
        if haystack:find("pet", 1, true) then return "Pets", 2 end
        if haystack:find("boost", 1, true) then return "Boosts", 3 end
        return "Other", 99
    end

    function Merchant.getSubcategory(listing, category)
        local name = tostring(listing.Name or ""):lower()
        local itemType = tostring(listing.Type or ""):lower()
        local class = tostring(listing.Class or ""):lower()
        local haystack = name .. " " .. itemType .. " " .. class

        if category == "Charms" then
            if haystack:find("void", 1, true) then return "Void Charms", 1 end
            if haystack:find("rainbow", 1, true) then return "Rainbow Charms", 2 end
            if haystack:find("shiny", 1, true) then return "Shiny Charms", 3 end
            if haystack:find("gold", 1, true) then return "Gold Charms", 4 end
            return "Other Charms", 99
        elseif category == "Pets" then
            if class ~= "" then return tostring(listing.Class), 1 end
            return "Pets", 99
        elseif category == "Boosts" then
            if haystack:find("strength", 1, true) then return "Strength Boosts", 1 end
            if haystack:find("crown", 1, true) then return "Crowns Boosts", 2 end
            if haystack:find("coin", 1, true) then return "Coins Boosts", 3 end
            if haystack:find("luck", 1, true) then return "Luck Boosts", 4 end
            if haystack:find("damage", 1, true) then return "Damage Boosts", 5 end
            if haystack:find("speed", 1, true) then return "Speed Boosts", 6 end
            if haystack:find("sell", 1, true) then return "Sell Boosts", 7 end
            if haystack:find("swing", 1, true) then return "Swing Boosts", 8 end
            if haystack:find("xp", 1, true) or haystack:find("experience", 1, true) then return "XP Boosts", 9 end
            if haystack:find("pet", 1, true) then return "Pet Boosts", 10 end
            if haystack:find("boss", 1, true) then return "Boss Boosts", 11 end
            if listing.Type and itemType ~= "" and itemType ~= "boost" and itemType ~= "boosts" then
                return tostring(listing.Type), 90
            end
            return "Other Boosts", 99
        end

        return category or "Other", 99
    end

    function Merchant.init(forceRefresh)
        local currentMulti = Merchant.getCrownMulti()
        if Merchant.initialized and not forceRefresh and Merchant.lastCrownMulti == currentMulti then return true end
        local ok, listings = pcall(function()
            return require(S.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TravelingMerchantInfo")).Listings
        end)
        if not ok or type(listings) ~= "table" then
            Core.debugLog("Merchant listings init failed:", listings)
            return false
        end

        table.clear(Merchant.listings)
        table.clear(Merchant.allowedIndexes)
        for key, listing in pairs(listings) do
            if Merchant.isRelevantListing(listing) then
                local index = tonumber(listing.Index or key)
                if index then
                    local category, categoryOrder = Merchant.getCategory(listing)
                    local subcategory, subcategoryOrder = Merchant.getSubcategory(listing, category)
                    Merchant.allowedIndexes[index] = true
                    Merchant.listings[#Merchant.listings + 1] = {
                        index=index,
                        label=Merchant.makeLabel(listing),
                        labelSuffix=Merchant.makeLabelSuffix(listing),
                        petRarity=Merchant.getPetRarityDisplay(listing),
                        category=category,
                        categoryOrder=categoryOrder,
                        subcategory=subcategory,
                        subcategoryOrder=subcategoryOrder,
                    }
                end
            end
        end

        table.sort(Merchant.listings, function(a, b)
            if a.categoryOrder ~= b.categoryOrder then return a.categoryOrder < b.categoryOrder end
            if a.subcategoryOrder ~= b.subcategoryOrder then return a.subcategoryOrder < b.subcategoryOrder end
            if a.subcategory ~= b.subcategory then return a.subcategory < b.subcategory end
            return a.index < b.index
        end)
        Merchant.initialized = true
        Merchant.lastCrownMulti = currentMulti
        return true
    end

    function Merchant.getUiItems(forceRefresh)
        if forceRefresh then Merchant.uiItems = nil end
        if Merchant.uiItems then return Merchant.uiItems end
        Merchant.init(forceRefresh)

        local items = {
            {type="toggle", key=Merchant.STATE_KEY, label="Auto Buy Merchant",
                callback=function(on) if on then HS.Merchant.start() else HS.Merchant.setStatus("waiting") end end},
            {type="status", bind="merchant", text="Merchant: waiting"},
            {type="label", text="Item Filters"},
        }

        local currentCategory = nil
        local currentSubcategory = nil
        for _, item in ipairs(Merchant.listings) do
            if item.category ~= currentCategory then
                currentCategory = item.category
                currentSubcategory = nil
                items[#items + 1] = {type="merchant_separator", text=currentCategory}
            end
            if item.subcategory ~= currentSubcategory then
                currentSubcategory = item.subcategory
                items[#items + 1] = {type="merchant_subseparator", text=currentSubcategory}
            end
            items[#items + 1] = {
                type="toggle",
                key="merchant_item_" .. tostring(item.index),
                label=item.label,
                labelSuffix=item.labelSuffix,
                petRarity=item.petRarity,
                callback=function() end,
            }
        end

        Merchant.uiItems = items
        return items
    end

    function Merchant.refreshDisplayIfNeeded()
        if Merchant.lastCrownMulti == Merchant.getCrownMulti() then return end
        Merchant.uiItems = nil
        if HS.UI and HS.UI.UI_DATA and HS.UI.UI_DATA.merchant and Core.activeTab == "merchant" then
            HS.UI.UI_DATA.merchant.items = Merchant.getUiItems(true)
            HS.UI.renderContent()
        end
    end

    function Merchant.startDisplayWatcher()
        if Merchant.displayWatcherThread then return end
        Merchant.displayWatcherThread = task.spawn(function()
            while Core.alive do
                if Core.activeTab == "merchant" then
                    Merchant.refreshDisplayIfNeeded()
                end
                task.wait(1)
            end
            Merchant.displayWatcherThread = nil
        end)
    end

    function Merchant.getSortedSlots(items)
        local slots = {}
        if type(items) ~= "table" then return slots end
        for slot, slotData in pairs(items) do
            if type(slotData) == "table" then
                local slotNumber = tonumber(slot)
                if slotNumber then
                    slots[#slots + 1] = {slot=slotNumber, data=slotData}
                end
            end
        end
        table.sort(slots, function(a, b) return a.slot < b.slot end)
        return slots
    end

    function Merchant.buySelected()
        if not Merchant.exists() then
            Merchant.setStatus("waiting")
            return
        end

        local data = Merchant.getData()
        local resetDT = data and data.ResetDT
        local slots = data and Merchant.getSortedSlots(data.Items)
        if not resetDT or not slots or #slots == 0 then
            Merchant.setStatus("found")
            return
        end

        local selectedPresent = false
        local boughtAny = false

        for _, slotInfo in ipairs(slots) do
            if not Core.alive or not Core.state[Merchant.STATE_KEY] or not Merchant.exists() then break end

            local slotData = slotInfo.data
            local listingIndex = slotData.Index
            local stateKey = "merchant_item_" .. tostring(listingIndex)
            local buysLeft = tonumber(slotData.BuysLeft) or 0

            if Merchant.allowedIndexes[tonumber(listingIndex)] and Core.state[stateKey] then
                selectedPresent = true
                while buysLeft > 0 and Core.alive and Core.state[Merchant.STATE_KEY] and Merchant.exists() do
                    Merchant.setStatus("buying")
                    Core.setCurrentAction("Buying Merchant Items", math.max(2, Merchant.CLICK_DELAY + 1))
                    Core.UIActionRemote:FireServer("TravelingMerchantBuyItem", slotInfo.slot, resetDT)
                    boughtAny = true
                    buysLeft -= 1
                    task.wait(Merchant.CLICK_DELAY)
                end
            end
        end

        if boughtAny or selectedPresent then
            Merchant.setStatus("done")
        else
            Merchant.setStatus("found")
        end
        Core.clearCurrentAction("Buying Merchant Items")
    end

    function Merchant.start()
        Merchant.init()
        Core.loopWhile(Merchant.STATE_KEY, Merchant.BUY_DELAY, Merchant.buySelected)
    end
end
-- HEARTSTEEL_MODULE_END: Merchant

-- LOGS - dungeon egg timer display
-- HEARTSTEEL_MODULE_START: LogsDungeon
-- Bundled from src/modules/LogsDungeon.lua
do
    HS.Logs = HS.Logs or {}
    HS.Logs.Dungeon = HS.Logs.Dungeon or {}

    local LogsDungeon = HS.Logs.Dungeon
    local Core        = HS.Core

    LogsDungeon.STATE_KEY = "dungeon_egg_timer_logs"
    LogsDungeon.UPDATE_DELAY = 0.75
    LogsDungeon.FROZEN_AFTER = 4
    LogsDungeon.CACHE_SCAN_RETRY_DELAY = 3
    LogsDungeon.slotState = LogsDungeon.slotState or {}
    LogsDungeon.timerLabels = LogsDungeon.timerLabels or {}
    LogsDungeon.nextCacheScanAt = 0

    function LogsDungeon.trim(text)
        local cleaned = tostring(text or "")
        cleaned = cleaned:gsub("^%s+", "")
        cleaned = cleaned:gsub("%s+$", "")
        return cleaned
    end

    function LogsDungeon.parseTimerSeconds(text)
        local normalized = LogsDungeon.trim(text):gsub("%s+", "")
        local h, m, s = normalized:match("^(%d+):(%d+):(%d+)$")
        if h then
            return ((tonumber(h) or 0) * 3600) + ((tonumber(m) or 0) * 60) + (tonumber(s) or 0)
        end

        m, s = normalized:match("^(%d+):(%d+)$")
        if m then
            return ((tonumber(m) or 0) * 60) + (tonumber(s) or 0)
        end

        return nil
    end

    function LogsDungeon.isFreezeCandidate(text)
        local seconds = LogsDungeon.parseTimerSeconds(text)
        return seconds ~= nil and seconds > 0
    end

    function LogsDungeon.ensureIncubatorCache()
        local Dungeon = HS.Dungeon
        if not Dungeon or type(Dungeon.scanIncubatorSlots) ~= "function" then return end
        if type(Dungeon.incubatorSlots) == "table" and #Dungeon.incubatorSlots > 0 then return end

        local now = os.clock()
        if now < (LogsDungeon.nextCacheScanAt or 0) then return end
        LogsDungeon.nextCacheScanAt = now + LogsDungeon.CACHE_SCAN_RETRY_DELAY
        Dungeon.scanIncubatorSlots()
    end

    function LogsDungeon.readSlotTimer(slotNumber)
        local Dungeon = HS.Dungeon
        if not Dungeon or type(Dungeon.readSlotTimerDirectly) ~= "function" then return "", false end

        local ok, timerText = pcall(Dungeon.readSlotTimerDirectly, slotNumber)
        if not ok then return "", false end

        timerText = LogsDungeon.trim(timerText)
        return timerText, timerText ~= ""
    end

    function LogsDungeon.getTimerRows()
        local Dungeon = HS.Dungeon
        if not Dungeon then return {} end

        LogsDungeon.ensureIncubatorCache()

        local cachedBySlot = {}
        if type(Dungeon.incubatorSlots) == "table" then
            for _, info in ipairs(Dungeon.incubatorSlots) do
                if type(info) == "table" and tonumber(info.slot) then
                    cachedBySlot[tonumber(info.slot)] = info
                end
            end
        end

        local rows = {}
        for slot = 1, (Dungeon.MAX_INCUBATOR_SLOTS or 6) do
            local cached = cachedBySlot[slot]
            local cachedTimer = cached and LogsDungeon.trim(cached.timerText) or ""
            local liveTimer, hasLiveTimer = LogsDungeon.readSlotTimer(slot)
            local timerText = hasLiveTimer and liveTimer or cachedTimer
            local isEmpty = cached and type(Dungeon.isSlotEmpty) == "function" and Dungeon.isSlotEmpty(cached.text)

            if timerText ~= "" and (not isEmpty or hasLiveTimer) then
                rows[#rows + 1] = {
                    slot = slot,
                    timerText = timerText,
                    live = hasLiveTimer,
                }
            end
        end

        return rows
    end

    function LogsDungeon.updateFreezeState(rows)
        local now = os.clock()
        local seen = {}

        for _, row in ipairs(rows) do
            local slot = row.slot
            local state = LogsDungeon.slotState[slot]
            seen[slot] = true

            if not state then
                state = {lastText = row.timerText, lastChangedAt = now, frozen = false}
                LogsDungeon.slotState[slot] = state
            elseif state.lastText ~= row.timerText then
                state.lastText = row.timerText
                state.lastChangedAt = now
                state.frozen = false
            elseif LogsDungeon.isFreezeCandidate(row.timerText) then
                state.frozen = (now - (state.lastChangedAt or now)) >= LogsDungeon.FROZEN_AFTER
            else
                state.frozen = false
            end

            row.frozen = state.frozen == true
        end

        for slot in pairs(LogsDungeon.slotState) do
            if not seen[slot] then
                LogsDungeon.slotState[slot] = nil
            end
        end
    end

    function LogsDungeon.updateLabels(rows)
        local labels = LogsDungeon.timerLabels
        if type(labels) ~= "table" then return end

        for _, label in pairs(labels) do
            if label and label.Parent then
                label.Text = ""
                label.Visible = false
                label.Size = UDim2.new(1, 0, 0, 0)
            end
        end

        for _, row in ipairs(rows) do
            local label = labels[row.slot]
            if label and label.Parent then
                local prefix = row.frozen and "(froze) " or ""
                label.Text = string.format("Egg %d: %s%s", row.slot, prefix, row.timerText)
                label.TextColor3 = row.frozen and Core.C.orange or Core.C.textDim
                label.Visible = true
                label.Size = UDim2.new(1, 0, 0, 18)
            end
        end
    end

    function LogsDungeon.refresh()
        if Core.state[LogsDungeon.STATE_KEY] ~= true then return end

        local rows = LogsDungeon.getTimerRows()
        LogsDungeon.updateFreezeState(rows)
        LogsDungeon.updateLabels(rows)
    end

    function LogsDungeon.bindTimerRows(labels)
        LogsDungeon.timerLabels = labels or {}
        if Core.state[LogsDungeon.STATE_KEY] == true then
            LogsDungeon.refresh()
        else
            LogsDungeon.updateLabels({})
        end
    end

    function LogsDungeon.clearRows()
        LogsDungeon.updateLabels({})
        LogsDungeon.timerLabels = {}
        table.clear(LogsDungeon.slotState)
    end

    function LogsDungeon.start()
        Core.loopWhile(LogsDungeon.STATE_KEY, LogsDungeon.UPDATE_DELAY, LogsDungeon.refresh)
    end

    function LogsDungeon.setEnabled(on)
        Core.state[LogsDungeon.STATE_KEY] = on == true
        if Core.state[LogsDungeon.STATE_KEY] then
            LogsDungeon.start()
        else
            LogsDungeon.clearRows()
        end
    end
end
-- HEARTSTEEL_MODULE_END: LogsDungeon

-- LOGS - pet hatch Discord webhook
-- HEARTSTEEL_MODULE_START: LogsPets
-- Bundled from src/modules/LogsPets.lua
do
    HS.Logs.Pets = HS.Logs.Pets or {}

    local LogsPets = HS.Logs.Pets
    local Core     = HS.Core

    local RARITY_IMAGE_MAP = {
        ["rbxassetid://117998638140155"] = {
            Label = "⭐ (1 Star)",
            Key = "1Star",
        },
        ["rbxassetid://101681619163898"] = {
            Label = "⭐⭐ (2 Star)",
            Key = "2Star",
        },
        ["rbxassetid://71217129344355"] = {
            Label = "⭐⭐⭐ (3 Star)",
            Key = "3Star",
        },
        ["rbxassetid://85204807527224"] = {
            Label = "⭐⭐⭐⭐ (4 Star)",
            Key = "4Star",
        },
        ["rbxassetid://72954799348276"] = {
            Label = "⭐⭐⭐⭐⭐ (5 Star)",
            Key = "5Star",
        },
        ["rbxassetid://90375810566006"] = {
            Label = "🌙 (1 Moon)",
            Key = "1Moon",
        },
        ["rbxassetid://135133438925164"] = {
            Label = "🌙🌙 (2 Moon)",
            Key = "2Moon",
        },
        ["rbxassetid://108817778982252"] = {
            Label = "🌙🌙🌙 (3 Moon)",
            Key = "3Moon",
        },
        ["rbxassetid://103333899383000"] = {
            Label = "☀️ Secret",
            Key = "Secret",
        },
    }

    local RARITY_STATE_KEYS = {
        ["1Star"] = "pet_webhook_1star",
        ["2Star"] = "pet_webhook_2star",
        ["3Star"] = "pet_webhook_3star",
        ["4Star"] = "pet_webhook_4star",
        ["5Star"] = "pet_webhook_5star",
        ["1Moon"] = "pet_webhook_1moon",
        ["2Moon"] = "pet_webhook_2moon",
        ["3Moon"] = "pet_webhook_3moon",
        Secret = "pet_webhook_secret",
    }

    local PET_THUMBNAIL_NAMES = {"FlatPet", "PetImage", "PetIcon", "Icon", "Pet"}
    local IGNORED_IMAGE_NAME_PARTS = {
        "rarityimg",
        "flash",
        "secretbkg",
        "background",
        "delete",
        "trash",
        "autodeleted",
        "autocrafted",
    }

    LogsPets.STATE_KEY = "pet_webhook_enabled"
    LogsPets.URL_KEY = "pet_webhook_url"
    LogsPets.Connection = nil
    LogsPets.GLOBAL_CONNECTION_KEY = "__HeartsteelPetHatchWebhookConnection"
    LogsPets.SEND_DELAY = 0.35

    function LogsPets.trim(text)
        local cleaned = tostring(text or "")
        cleaned = cleaned:gsub("^%s+", "")
        cleaned = cleaned:gsub("%s+$", "")
        return cleaned
    end

    function LogsPets.getWebhookUrl()
        return LogsPets.trim(Core.inputState[LogsPets.URL_KEY] or "")
    end

    function LogsPets.isWebhookUrlValid(url)
        url = LogsPets.trim(url)
        return url:match("^https://discord%.com/api/webhooks/%d+/%S+$") ~= nil
            or url:match("^https://discordapp%.com/api/webhooks/%d+/%S+$") ~= nil
    end

    function LogsPets.shouldSendPetWebhook(rarityKey)
        if Core.state[LogsPets.STATE_KEY] ~= true then return false end
        if not LogsPets.isWebhookUrlValid(LogsPets.getWebhookUrl()) then return false end
        local stateKey = RARITY_STATE_KEYS[rarityKey]
        return stateKey ~= nil and Core.state[stateKey] == true
    end

    function LogsPets.isActuallyVisible(obj)
        if not (obj and obj:IsA("GuiObject")) then return false end
        local current = obj
        while current do
            if current:IsA("GuiObject") and current.Visible ~= true then
                return false
            end
            current = current.Parent
            if current and current:IsA("ScreenGui") then break end
        end
        return true
    end

    function LogsPets.getEggsFolder()
        local gui = Core.playerGui and Core.playerGui:FindFirstChild("MainGui")
        local otherFrames = gui and gui:FindFirstChild("OtherFrames")
        local openEggs = otherFrames and otherFrames:FindFirstChild("OpenEggs")
        return openEggs and openEggs:FindFirstChild("Eggs")
    end

    function LogsPets.getActiveHatchFrames()
        local eggs = LogsPets.getEggsFolder()
        local frames = {}
        if not eggs then return frames end

        for _, child in ipairs(eggs:GetChildren()) do
            if child.Name == "Example" and child:IsA("GuiObject") and LogsPets.isActuallyVisible(child) then
                frames[#frames + 1] = child
            end
        end

        table.sort(frames, function(a, b)
            local ap = a.AbsolutePosition
            local bp = b.AbsolutePosition
            if ap.X ~= bp.X then return ap.X < bp.X end
            return ap.Y < bp.Y
        end)

        return frames
    end

    function LogsPets.getText(obj)
        if not obj then return nil end
        local ok, text = pcall(function()
            return obj.Text
        end)
        if not ok or type(text) ~= "string" then return nil end
        text = LogsPets.trim(text)
        if text == "" or text == "Pet Name" then return nil end
        return text
    end

    function LogsPets.getFramePetName(frame)
        local petTypeLabel = frame and frame:FindFirstChild("PetType", true)
        return LogsPets.getText(petTypeLabel)
    end

    function LogsPets.isImageObject(obj)
        return obj and (obj:IsA("ImageLabel") or obj:IsA("ImageButton"))
    end

    function LogsPets.getRarityInfo(frame)
        local rarityImg = frame and frame:FindFirstChild("RarityImg", true)
        if not LogsPets.isImageObject(rarityImg) then return nil end
        local image = LogsPets.trim(rarityImg.Image or "")
        if image == "" or image == "Rarity Image" then return nil end

        local mapped = RARITY_IMAGE_MAP[image]
        if mapped then
            return {
                Label = mapped.Label,
                Key = mapped.Key,
                Image = image,
            }
        end

        return {
            Label = "Secret",
            Key = "Secret",
            Image = image,
        }
    end

    function LogsPets.isReadyHatchFrame(frame)
        return LogsPets.getFramePetName(frame) ~= nil and LogsPets.getRarityInfo(frame) ~= nil
    end

    function LogsPets.normalizePetName(text)
        local cleaned = LogsPets.trim(text):lower()
        cleaned = cleaned:gsub("^golden%s+", "")
        cleaned = cleaned:gsub("^shiny%s+", "")
        cleaned = cleaned:gsub("^rainbow%s+", "")
        cleaned = cleaned:gsub("^void%s+", "")
        return cleaned
    end

    function LogsPets.getExpectedPetCounts(eventPets)
        if type(eventPets) ~= "table" or #eventPets == 0 then return nil end

        local counts = {}
        for _, petName in ipairs(eventPets) do
            local key = LogsPets.normalizePetName(petName)
            if key ~= "" then
                counts[key] = (counts[key] or 0) + 1
            end
        end

        return next(counts) and counts or nil
    end

    function LogsPets.copyPetCounts(counts)
        if not counts then return nil end
        local copy = {}
        for key, count in pairs(counts) do
            copy[key] = count
        end
        return copy
    end

    function LogsPets.consumeExpectedPet(counts, petName)
        if not counts then return true end

        local key = LogsPets.normalizePetName(petName)
        local count = counts[key] or 0
        if count <= 0 then return false end

        counts[key] = count - 1
        return true
    end

    function LogsPets.framesMatchExpectedPets(frames, expectedPetCounts)
        if not expectedPetCounts then return true end

        local remaining = LogsPets.copyPetCounts(expectedPetCounts)
        local needed = 0
        local matched = 0

        for _, count in pairs(remaining) do
            needed += count
        end

        for _, frame in ipairs(frames) do
            if LogsPets.isReadyHatchFrame(frame) and LogsPets.consumeExpectedPet(remaining, LogsPets.getFramePetName(frame)) then
                matched += 1
            end
        end

        return needed > 0 and matched >= needed
    end

    function LogsPets.waitForReadyHatchFrames(expectedCount, timeout, expectedPetCounts)
        expectedCount = math.max(0, tonumber(expectedCount) or 0)
        timeout = tonumber(timeout) or 6

        local started = os.clock()
        local lastFrames = {}

        while os.clock() - started < timeout do
            local frames = LogsPets.getActiveHatchFrames()
            lastFrames = frames

            local readyCount = 0
            for _, frame in ipairs(frames) do
                if LogsPets.isReadyHatchFrame(frame) then
                    readyCount += 1
                end
            end

            if readyCount > 0
                and os.clock() - started >= 0.2
                and (expectedCount == 0 or readyCount >= expectedCount)
                and LogsPets.framesMatchExpectedPets(frames, expectedPetCounts) then
                return frames
            end

            task.wait(0.15)
        end

        return lastFrames
    end

    function LogsPets.getPetType(frame)
        local classText = frame and frame:FindFirstChild("ClassText", true)
        if classText then
            for _, typeName in ipairs({"Void", "Rainbow", "Shiny", "Golden"}) do
                local label = classText:FindFirstChild(typeName)
                if LogsPets.isActuallyVisible(label) then
                    return typeName
                end
            end
        end
        return "Normal"
    end

    function LogsPets.isIgnoredImageName(name)
        local lowered = tostring(name or ""):lower()
        for _, part in ipairs(IGNORED_IMAGE_NAME_PARTS) do
            if lowered:find(part, 1, true) then
                return true
            end
        end
        return false
    end

    function LogsPets.assetDeliveryUrl(image)
        image = LogsPets.trim(image)
        local assetId = image:match("^rbxassetid://(%d+)$")
        if not assetId then return nil end
        return "https://assetdelivery.roblox.com/v1/asset?id=" .. assetId
    end

    function LogsPets.isUsableThumbnailObject(obj)
        if not LogsPets.isImageObject(obj) then return false end
        if LogsPets.isIgnoredImageName(obj.Name) then return false end
        if not LogsPets.isActuallyVisible(obj) then return false end
        return LogsPets.assetDeliveryUrl(obj.Image or "") ~= nil
    end

    function LogsPets.getPetThumbnailUrl(frame)
        if not frame then return nil end

        for _, wantedName in ipairs(PET_THUMBNAIL_NAMES) do
            for _, obj in ipairs(frame:GetDescendants()) do
                if obj.Name == wantedName and LogsPets.isUsableThumbnailObject(obj) then
                    return LogsPets.assetDeliveryUrl(obj.Image)
                end
            end
        end

        return nil
    end

    function LogsPets.readHatchFrame(frame, eggName)
        if not LogsPets.isActuallyVisible(frame) then return nil end

        local petName = LogsPets.getFramePetName(frame)
        local rarity = LogsPets.getRarityInfo(frame)
        if not (petName and rarity) then return nil end

        return {
            PetName = petName,
            PetType = LogsPets.getPetType(frame),
            RarityLabel = rarity.Label,
            RarityKey = rarity.Key,
            EggName = tostring(eggName or "Unknown Egg"),
            ThumbnailUrl = LogsPets.getPetThumbnailUrl(frame),
        }
    end

    function LogsPets.getRequestFunction()
        return (syn and syn.request)
            or (http and http.request)
            or request
            or http_request
            or (fluxus and fluxus.request)
    end

    function LogsPets.sendWebhook(hatch)
        if not hatch then return false end

        local url = LogsPets.getWebhookUrl()
        if not LogsPets.isWebhookUrlValid(url) then return false end

        local req = LogsPets.getRequestFunction()
        if not req then
            Core.debugLog("Pet webhook request unavailable")
            return false
        end

        local playerName = Core.player and Core.player.Name or "Unknown"
        local displayName = Core.player and Core.player.DisplayName or playerName
        local embed = {
            title = "🐾 New Pet Hatched!",
            color = 10181046,
            fields = {
                {name = "Player", value = tostring(displayName) .. " (`" .. tostring(playerName) .. "`)", inline = false},
                {name = "Pet Name", value = tostring(hatch.PetName), inline = true},
                {name = "Pet Type", value = tostring(hatch.PetType), inline = true},
                {name = "Pet Rarity", value = tostring(hatch.RarityLabel), inline = true},
                {name = "Egg", value = tostring(hatch.EggName), inline = false},
            },
            timestamp = DateTime.now():ToIsoDate(),
        }

        if hatch.ThumbnailUrl then
            embed.thumbnail = {url = hatch.ThumbnailUrl}
        end

        local payload = {
            embeds = {embed},
        }

        local ok, result = pcall(function()
            return req({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                },
                Body = S.HttpService:JSONEncode(payload),
            })
        end)

        if not ok then
            Core.debugLog("Pet webhook request failed")
            return false
        end

        local statusCode = type(result) == "table" and tonumber(result.StatusCode or result.status_code or result.Status) or nil
        if statusCode and (statusCode < 200 or statusCode >= 300) then
            Core.debugLog("Pet webhook HTTP status:", statusCode)
            return false
        end

        Core.debugLog("Pet webhook sent:", hatch.PetName, hatch.RarityLabel)
        return true
    end

    function LogsPets.processHatchEvent(args)
        if not Core.alive or Core.state[LogsPets.STATE_KEY] ~= true then return end
        if not LogsPets.isWebhookUrlValid(LogsPets.getWebhookUrl()) then return end

        args = type(args) == "table" and args or {}
        local eventPets = type(args[1]) == "table" and args[1] or {}
        local expectedCount = #eventPets
        local expectedPetCounts = LogsPets.getExpectedPetCounts(eventPets)
        local remainingPetCounts = LogsPets.copyPetCounts(expectedPetCounts)
        local eggName = args[6] or "Unknown Egg"
        local frames = LogsPets.waitForReadyHatchFrames(expectedCount, 6, expectedPetCounts)
        local seenFrames = {}
        local processedCount = 0

        for _, frame in ipairs(frames) do
            if expectedCount > 0 and processedCount >= expectedCount then break end
            if seenFrames[frame] or not LogsPets.isReadyHatchFrame(frame) then
                continue
            end

            local hatch = LogsPets.readHatchFrame(frame, eggName)
            if not hatch then
                continue
            end

            if not LogsPets.consumeExpectedPet(remainingPetCounts, hatch.PetName) then
                continue
            end

            seenFrames[frame] = true
            processedCount += 1

            if LogsPets.shouldSendPetWebhook(hatch.RarityKey) and LogsPets.sendWebhook(hatch) then
                task.wait(LogsPets.SEND_DELAY)
            end
        end
    end

    function LogsPets.getRemote()
        local events = S.ReplicatedStorage:FindFirstChild("Events")
        if not events then
            events = S.ReplicatedStorage:WaitForChild("Events", 5)
        end
        if not events then return nil end
        return events:FindFirstChild("EggHatchResult") or events:WaitForChild("EggHatchResult", 5)
    end

    function LogsPets.getGlobalEnv()
        if type(getgenv) ~= "function" then return nil end
        local ok, env = pcall(getgenv)
        return ok and type(env) == "table" and env or nil
    end

    function LogsPets.disconnect()
        local env = LogsPets.getGlobalEnv()
        local current = LogsPets.Connection

        if current then
            pcall(function() current:Disconnect() end)
        end
        LogsPets.Connection = nil

        local stored = env and env[LogsPets.GLOBAL_CONNECTION_KEY]
        if stored and stored ~= current then
            pcall(function() stored:Disconnect() end)
        end
        if env then
            env[LogsPets.GLOBAL_CONNECTION_KEY] = nil
        end
    end

    function LogsPets.connect()
        if LogsPets.Connection then
            local env = LogsPets.getGlobalEnv()
            if env then
                env[LogsPets.GLOBAL_CONNECTION_KEY] = LogsPets.Connection
            end
            return
        end

        LogsPets.disconnect()

        local remote = LogsPets.getRemote()
        if not remote then
            Core.debugLog("Pet webhook remote missing")
            return
        end

        LogsPets.Connection = remote.OnClientEvent:Connect(function(...)
            local args = {...}
            task.spawn(function()
                LogsPets.processHatchEvent(args)
            end)
        end)

        local env = LogsPets.getGlobalEnv()
        if env then
            env[LogsPets.GLOBAL_CONNECTION_KEY] = LogsPets.Connection
        end

        Core.debugLog("Pet webhook listener connected")
    end

    function LogsPets.syncConnection()
        if Core.state[LogsPets.STATE_KEY] == true then
            LogsPets.connect()
        else
            LogsPets.disconnect()
        end
    end

    function LogsPets.setEnabled(on)
        Core.state[LogsPets.STATE_KEY] = on == true
        LogsPets.syncConnection()
    end
end
-- HEARTSTEEL_MODULE_END: LogsPets

-- LOGS - live Discord monitor dashboard
-- HEARTSTEEL_MODULE_START: LogsDiscordMonitor
-- Bundled from src/modules/LogsDiscordMonitor.lua
do
    HS.Logs = HS.Logs or {}
    HS.Logs.DiscordMonitor = HS.Logs.DiscordMonitor or {}

    local Monitor = HS.Logs.DiscordMonitor
    local Core    = HS.Core

    Monitor.STATE_KEY = "discord_monitor_enabled"
    Monitor.URL_KEY = "discord_monitor_webhook_url"
    Monitor.INTERVAL_KEY = "discord_monitor_update_interval"
    Monitor.SHOW_ELEMENT_LEVELS_KEY = "discord_monitor_show_element_levels"
    Monitor.SHOW_MASTERY_LEVELS_KEY = "discord_monitor_show_mastery_levels"
    Monitor.SHOW_DUNGEON_EGGS_KEY = "discord_monitor_show_dungeon_eggs"
    Monitor.SHOW_SESSION_STATS_KEY = "discord_monitor_show_session_stats"
    Monitor.SHOW_CONNECTION_STATS_KEY = "discord_monitor_show_connection_stats"
    Monitor.DEFAULT_INTERVAL = 10
    Monitor.MIN_INTERVAL = 5
    Monitor.GLOBAL_STATE_KEY = "__HeartsteelDiscordMonitorState"
    Monitor.GLOBAL_LOOP_KEY = "__HeartsteelDiscordMonitorLoop"
    Monitor.GLOBAL_HATCH_CONNECTION_KEY = "__HeartsteelDiscordMonitorHatchConnection"
    Monitor.GLOBAL_TELEPORT_CONNECTION_KEY = "__HeartsteelDiscordMonitorTeleportConnection"
    Monitor.GLOBAL_ERROR_CONNECTION_KEY = "__HeartsteelDiscordMonitorErrorConnection"
    Monitor.Thread = nil
    Monitor.RunId = 0
    Monitor.HatchConnection = nil
    Monitor.TeleportConnection = nil
    Monitor.GuiErrorConnection = nil
    Monitor.LastFailureMessage = nil
    Monitor.LastFailureAt = 0
    Monitor.LastWebhookUrl = nil

    local LOW_RARITIES = {
        ["1Star"] = true, ["2Star"] = true, ["3Star"] = true,
        ["4Star"] = true, ["5Star"] = true,
        ["1Moon"] = true, ["2Moon"] = true,
    }

    local DUNGEON_ACTIONS = {
        ["Running Dungeon"] = true,
        ["Farming Dungeon Enemies"] = true,
        ["Claiming Dungeon Chest"] = true,
        ["Handling Dungeon Egg"] = true,
    }

    local ELEMENT_LEVEL_ORDER = {"Fire", "Water", "Earth", "Plasma"}
    local MASTERY_LEVEL_ORDER = {
        "Saber Swing",
        "Egg Hatching",
        "Elements",
        "Bossing",
        "Dungeon",
        "KOTH",
        "Flags",
        "Playtime",
    }

    function Monitor.trim(text)
        local cleaned = tostring(text or "")
        cleaned = cleaned:gsub("^%s+", "")
        cleaned = cleaned:gsub("%s+$", "")
        return cleaned
    end

    function Monitor.getGlobalEnv()
        if type(getgenv) ~= "function" then return nil end
        local ok, env = pcall(getgenv)
        return ok and type(env) == "table" and env or nil
    end

    function Monitor.ensureState()
        local env = Monitor.getGlobalEnv()
        local state = env and env[Monitor.GLOBAL_STATE_KEY]
        if type(state) ~= "table" then
            state = {}
            if env then env[Monitor.GLOBAL_STATE_KEY] = state end
        end

        state.CurrentAction = state.CurrentAction or "Idle"
        state.LastDebugMessage = state.LastDebugMessage or ""
        state.LastHighRarityPet = state.LastHighRarityPet or ""
        state.LastHighRarityPetType = state.LastHighRarityPetType or ""
        state.CurrentPlayerClass = state.CurrentPlayerClass or ""
        state.PetsHatched = tonumber(state.PetsHatched) or 0
        state.SecretsFound = tonumber(state.SecretsFound) or 0
        state.DisconnectCount = tonumber(state.DisconnectCount) or 0
        state.RejoinCount = tonumber(state.RejoinCount) or 0
        state.ConnectionStatus = state.ConnectionStatus or "Connected"
        state.SessionStartUnix = tonumber(state.SessionStartUnix) or os.time()

        if not Monitor.StateBootstrapped then
            if state.PendingRejoin == true then
                state.RejoinCount += 1
                state.PendingRejoin = false
            end
            state.ConnectionStatus = "Connected"
            Monitor.StateBootstrapped = true
        end

        Monitor.State = state
        return state
    end

    Monitor.ensureState()

    function Monitor.setLastDebugMessage(message)
        local state = Monitor.ensureState()
        local text = Monitor.trim(message)
        if text == "" then return end
        state.LastDebugMessage = text
    end

    function Monitor.debugFailure(message)
        local now = os.clock()
        local text = tostring(message or "Discord Monitor error")
        if Monitor.LastFailureMessage == text and now - (Monitor.LastFailureAt or 0) < 30 then return end
        Monitor.LastFailureMessage = text
        Monitor.LastFailureAt = now
        Core.debugLog(text)
    end

    function Monitor.getConfig()
        if Core.syncLogsConfig then
            pcall(Core.syncLogsConfig)
        end
        return Core.getLogsConfig().DiscordMonitor
    end

    function Monitor.getWebhookUrl()
        return Monitor.trim(Core.inputState[Monitor.URL_KEY] or Monitor.getConfig().WebhookURL or "")
    end

    function Monitor.isWebhookUrlValid(url)
        url = Monitor.trim(url)
        return url:match("^https://discord%.com/api/webhooks/%d+/%S+$") ~= nil
            or url:match("^https://discordapp%.com/api/webhooks/%d+/%S+$") ~= nil
    end

    function Monitor.getUpdateInterval()
        local raw = Core.inputState[Monitor.INTERVAL_KEY] or Monitor.getConfig().UpdateInterval
        return math.max(Monitor.MIN_INTERVAL, tonumber(raw) or Monitor.DEFAULT_INTERVAL)
    end

    function Monitor.getMessageId()
        local id = Monitor.getConfig().MessageId
        id = id ~= nil and Monitor.trim(id) or ""
        return id ~= "" and id or nil
    end

    function Monitor.setMessageId(id, skipSave)
        local config = Core.getLogsConfig().DiscordMonitor
        local text = id ~= nil and Monitor.trim(id) or ""
        config.MessageId = text ~= "" and text or nil
        if not skipSave and HS.Session and HS.Session.save then
            pcall(HS.Session.save)
        end
    end

    function Monitor.getRequestFunction()
        return (syn and syn.request)
            or (http and http.request)
            or request
            or http_request
            or (fluxus and fluxus.request)
    end

    function Monitor.baseWebhookUrl(url)
        return Monitor.trim(url):gsub("%?.*$", ""):gsub("/+$", "")
    end

    function Monitor.createWebhookUrl(url)
        local base = Monitor.baseWebhookUrl(url)
        return base .. "?wait=true"
    end

    function Monitor.editWebhookUrl(url, messageId)
        return Monitor.baseWebhookUrl(url) .. "/messages/" .. tostring(messageId)
    end

    function Monitor.getStatusCode(result)
        if type(result) ~= "table" then return nil end
        return tonumber(result.StatusCode or result.status_code or result.Status or result.status)
    end

    function Monitor.request(method, url, payload)
        local req = Monitor.getRequestFunction()
        if not req then
            return false, nil, nil, "request unavailable"
        end

        local body = nil
        if payload then
            local okEncode, encoded = pcall(function()
                return S.HttpService:JSONEncode(payload)
            end)
            if not okEncode then
                return false, nil, nil, "encode failed"
            end
            body = encoded
        end

        local requestData = {
            Url = url,
            Method = method,
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = body,
        }

        local ok, result = pcall(function()
            return req(requestData)
        end)

        if not ok then
            return false, nil, nil, "request failed"
        end

        local status = Monitor.getStatusCode(result)
        if status and status >= 200 and status < 300 then
            return true, result, status, nil
        end
        if not status and type(result) == "table" and result.Success == true then
            return true, result, 200, nil
        end

        return false, result, status, nil
    end

    function Monitor.decodeBody(result)
        local body = type(result) == "table" and (result.Body or result.body) or nil
        if type(body) ~= "string" or body == "" then return nil end
        local ok, data = pcall(function()
            return S.HttpService:JSONDecode(body)
        end)
        return ok and type(data) == "table" and data or nil
    end

    function Monitor.cleanField(value, fallback, maxLen)
        local text = Monitor.trim(value)
        if text == "" then text = fallback or "None" end
        text = text:gsub("[%c]", " ")
        maxLen = maxLen or 1024
        if #text > maxLen then
            text = text:sub(1, maxLen - 3) .. "..."
        end
        return text
    end

    function Monitor.formatDuration(seconds)
        seconds = math.max(0, math.floor(tonumber(seconds) or 0))
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        local s = seconds % 60
        return string.format("%02d:%02d:%02d", h, m, s)
    end

    function Monitor.getStatusColor(status)
        status = tostring(status or "Connected")
        if status == "Disconnected" then return 15548997 end
        if status == "Rejoining" or status == "Teleporting" then return 16705372 end
        return 5763719
    end

    function Monitor.getCurrentPlayerClass()
        local Farming = HS.Farming
        local className = nil
        if Farming then
            local okClient, fromClient = pcall(function()
                return Farming.getCurrentClassFromClientData and Farming.getCurrentClassFromClientData()
            end)
            if okClient then className = fromClient end

            if not className then
                local okModule, fromModule = pcall(function()
                    return Farming.getCurrentClassFromClassesInfo and Farming.getCurrentClassFromClassesInfo()
                end)
                if okModule then className = fromModule end
            end

            if not className then
                local okFallback, fromFallback = pcall(function()
                    return Farming.getCurrentClassFromFallbackTag and Farming.getCurrentClassFromFallbackTag()
                end)
                if okFallback then className = fromFallback end
            end
        end

        local state = Monitor.ensureState()
        if className and tostring(className) ~= "" then
            state.CurrentPlayerClass = tostring(className)
        end
        return state.CurrentPlayerClass ~= "" and state.CurrentPlayerClass or "Unknown"
    end

    function Monitor.getClientData()
        if type(Core.getClientDataManager) ~= "function" then return nil end
        local ok, manager = pcall(Core.getClientDataManager)
        if not ok or type(manager) ~= "table" then return nil end
        local data = manager.Data
        return type(data) == "table" and data or nil
    end

    function Monitor.formatLevelRows(levels, order, currentName)
        if type(levels) ~= "table" then return "Unavailable" end

        local current = Monitor.trim(currentName):lower()
        local lines = {}
        for _, name in ipairs(order) do
            local value = levels[name]
            local valueText = value ~= nil and Monitor.cleanField(value, "Unavailable", 64) or "Unavailable"
            local text = name .. ": " .. valueText
            if current ~= "" and name:lower() == current then
                text = text .. " (current)"
            end
            lines[#lines + 1] = text
        end

        return table.concat(lines, "\n")
    end

    function Monitor.getElementLevelsText()
        local data = Monitor.getClientData()
        return Monitor.formatLevelRows(data and data.ElementLevels, ELEMENT_LEVEL_ORDER, data and data.Element)
    end

    function Monitor.getMasteryLevelsText()
        local data = Monitor.getClientData()
        return Monitor.formatLevelRows(data and data.MasteryLevels, MASTERY_LEVEL_ORDER)
    end

    function Monitor.resolveCurrentAction()
        local state = Monitor.ensureState()
        local status = state.ConnectionStatus
        if status == "Rejoining" then return "Rejoining Server" end
        if status == "Teleporting" then return "Teleporting" end

        local explicit = Core.getCurrentAction and Core.getCurrentAction() or state.CurrentAction
        if status == "Disconnected" then
            if explicit and explicit ~= "" and explicit ~= "Idle" then
                return explicit
            end
            return "Disconnected"
        end

        local Dungeon = HS.Dungeon
        if explicit and explicit ~= "" and explicit ~= "Idle" and DUNGEON_ACTIONS[explicit] then
            return explicit
        end
        if Dungeon then
            if Dungeon.eggRewardPending then
                return "Handling Dungeon Egg"
            end
            if Dungeon.hitThread and Core.state.farm_dungeon and Dungeon.currentTarget and (not Dungeon.isValid or Dungeon.isValid(Dungeon.currentTarget)) then
                return "Farming Dungeon Enemies"
            end
            if Core.dungeonActive or Dungeon.wasInside then
                return "Running Dungeon"
            end
        end

        if explicit and explicit ~= "" and explicit ~= "Idle" then
            return explicit
        end

        return "Idle"
    end

    function Monitor.getDungeonEggTimerText()
        local Dungeon = HS.Dungeon
        if not Dungeon then return "Unavailable" end

        local LogsDungeon = HS.Logs and HS.Logs.Dungeon
        if LogsDungeon and LogsDungeon.ensureIncubatorCache then
            pcall(LogsDungeon.ensureIncubatorCache)
        elseif type(Dungeon.scanIncubatorSlots) == "function" and (type(Dungeon.incubatorSlots) ~= "table" or #Dungeon.incubatorSlots == 0) then
            pcall(Dungeon.scanIncubatorSlots)
        end

        local cachedBySlot = {}
        if type(Dungeon.incubatorSlots) == "table" then
            for _, info in ipairs(Dungeon.incubatorSlots) do
                if type(info) == "table" and tonumber(info.slot) then
                    cachedBySlot[tonumber(info.slot)] = info
                end
            end
        end

        local rows = {}
        local freezeRows = {}
        for slot = 1, (Dungeon.MAX_INCUBATOR_SLOTS or 6) do
            local cached = cachedBySlot[slot]
            local cachedTimer = cached and Monitor.trim(cached.timerText) or ""
            local liveTimer, hasLiveTimer = "", false

            if LogsDungeon and LogsDungeon.readSlotTimer then
                local okRead, timerText, hasTimer = pcall(LogsDungeon.readSlotTimer, slot)
                if okRead then
                    liveTimer = Monitor.trim(timerText)
                    hasLiveTimer = hasTimer == true and liveTimer ~= ""
                end
            elseif type(Dungeon.readSlotTimerDirectly) == "function" then
                local okRead, timerText = pcall(Dungeon.readSlotTimerDirectly, slot)
                if okRead then
                    liveTimer = Monitor.trim(timerText)
                    hasLiveTimer = liveTimer ~= ""
                end
            end

            local timerText = hasLiveTimer and liveTimer or cachedTimer
            local isEmpty = cached == nil
            if cached and type(Dungeon.isSlotEmpty) == "function" then
                local okEmpty, empty = pcall(Dungeon.isSlotEmpty, cached.text)
                isEmpty = okEmpty and empty == true
            elseif cached then
                isEmpty = Monitor.trim(cached.text) == "" or Monitor.trim(cached.text):lower():find("empty", 1, true) ~= nil
            end

            local row = {
                slot = slot,
                timerText = timerText,
                isEmpty = isEmpty,
                frozen = false,
            }
            rows[slot] = row
            if timerText ~= "" and not isEmpty then
                freezeRows[#freezeRows + 1] = {slot=slot, timerText=timerText}
            end
        end

        if LogsDungeon and LogsDungeon.updateFreezeState then
            pcall(LogsDungeon.updateFreezeState, freezeRows)
            for _, row in ipairs(freezeRows) do
                if rows[row.slot] then
                    rows[row.slot].frozen = row.frozen == true
                end
            end
        end

        local lines = {}
        for slot = 1, (Dungeon.MAX_INCUBATOR_SLOTS or 6) do
            local row = rows[slot] or {slot=slot, timerText="", isEmpty=true}
            local display
            if row.isEmpty and row.timerText == "" then
                display = "Empty"
            elseif row.timerText == "" then
                display = "Unknown"
            else
                display = row.timerText
                if type(Dungeon.isEggReady) == "function" then
                    local okReady, ready = pcall(Dungeon.isEggReady, row.timerText)
                    if okReady and ready then
                        display = "Ready"
                    end
                end
                if row.frozen and display ~= "Ready" then
                    display = "(froze) " .. display
                end
            end
            lines[#lines + 1] = string.format("Egg %d: %s", slot, display)
        end

        return table.concat(lines, "\n")
    end

    function Monitor.buildPayload()
        local state = Monitor.ensureState()
        local config = Monitor.getConfig()
        local showElementLevels = config.ShowElementLevels == true
        local showMasteryLevels = config.ShowMasteryLevels == true
        local showDungeonEggs = config.ShowDungeonEggs == true
        local showSessionStats = config.ShowSessionStats == true
        local showConnectionStats = config.ShowConnectionStats == true
        local playerName = Core.player and Core.player.Name or "Unknown"
        local displayName = Core.player and Core.player.DisplayName or playerName
        local connectionStatus = state.ConnectionStatus or "Connected"
        local latestDebug = Monitor.cleanField(state.LastDebugMessage, "None", 900)
        if latestDebug ~= "None" then
            latestDebug = "\"" .. latestDebug .. "\""
        end

        local elapsed = os.time() - (tonumber(state.SessionStartUnix) or os.time())
        local serverUptime = tonumber(workspace.DistributedGameTime) or 0
        local currentClass = Monitor.getCurrentPlayerClass()
        local dungeonEggTimers = Monitor.getDungeonEggTimerText()
        if Monitor.trim(dungeonEggTimers) == "" then
            dungeonEggTimers = "Egg 1: Empty\nEgg 2: Empty\nEgg 3: Empty\nEgg 4: Empty"
        end

        local fields = {}
        local function addField(name, value, inline)
            fields[#fields + 1] = {
                name = name,
                value = value,
                inline = inline == true,
            }
        end

        addField(
            "Player",
            "IGN: `" .. Monitor.cleanField(playerName, "Unknown", 64) .. "`\nDisplay Name: " .. Monitor.cleanField(displayName, "Unknown", 64),
            false
        )
        if showConnectionStats then
            addField("Status", Monitor.cleanField(connectionStatus, "Connected", 64), true)
        end
        addField("Current Action", Monitor.cleanField(Monitor.resolveCurrentAction(), "Idle", 128), true)
        if showSessionStats then
            addField("Last High Rarity Pet", Monitor.cleanField(state.LastHighRarityPet, "None", 128), true)
            addField("Pet Type", Monitor.cleanField(state.LastHighRarityPetType, "None", 64), true)
            addField("Current Class", Monitor.cleanField(currentClass, "Unknown", 128), true)
            addField(
                "Session Stats",
                "Pets Hatched: " .. tostring(state.PetsHatched or 0) .. "\nSecrets Found: " .. tostring(state.SecretsFound or 0),
                true
            )
        end
        if showConnectionStats then
            addField(
                "Connection Stats",
                "Disconnect Count: " .. tostring(state.DisconnectCount or 0) .. "\nRejoins: " .. tostring(state.RejoinCount or 0),
                true
            )
        end
        addField(
            "Runtime",
            "Elapsed Time: " .. Monitor.formatDuration(elapsed) .. "\nServer Uptime: " .. Monitor.formatDuration(serverUptime),
            false
        )
        if showElementLevels then
            addField("Element Levels", Monitor.getElementLevelsText(), false)
        end
        if showMasteryLevels then
            addField("Mastery Levels", Monitor.getMasteryLevelsText(), false)
        end
        if showDungeonEggs then
            addField("Dungeon Egg Timers", dungeonEggTimers, false)
        end
        addField("Latest Debug", latestDebug, false)

        local embed = {
            title = "Live Discord Monitor",
            color = Monitor.getStatusColor(connectionStatus),
            fields = fields,
            timestamp = DateTime.now():ToIsoDate(),
        }

        return {
            username = "Heartsteel Monitor",
            embeds = {embed},
        }
    end

    function Monitor.createMessage(url, payload)
        local ok, result, status, err = Monitor.request("POST", Monitor.createWebhookUrl(url), payload)
        if not ok then
            Monitor.debugFailure("Discord Monitor create failed: " .. tostring(status or err or "unknown"))
            return nil
        end

        local data = Monitor.decodeBody(result)
        local messageId = data and data.id
        if not messageId then
            Monitor.debugFailure("Discord Monitor create response missing message ID")
            return nil
        end

        return tostring(messageId)
    end

    function Monitor.editMessage(url, messageId, payload)
        local ok, _, status, err = Monitor.request("PATCH", Monitor.editWebhookUrl(url, messageId), payload)
        if ok then return true, status end
        Monitor.debugFailure("Discord Monitor edit failed: " .. tostring(status or err or "unknown"))
        return false, status
    end

    function Monitor.update()
        local url = Monitor.getWebhookUrl()
        if url == "" then
            Monitor.debugFailure("Discord Monitor webhook URL missing")
            return false
        end
        if not Monitor.isWebhookUrlValid(url) then
            Monitor.debugFailure("Discord Monitor webhook URL invalid")
            return false
        end

        local payload = Monitor.buildPayload()
        local messageId = Monitor.getMessageId()

        if messageId then
            local edited, status = Monitor.editMessage(url, messageId, payload)
            if edited then return true end
            if status == 400 or status == 404 then
                Monitor.setMessageId(nil)
                messageId = nil
            else
                return false
            end
        end

        local newMessageId = Monitor.createMessage(url, payload)
        if newMessageId then
            Monitor.setMessageId(newMessageId)
            Core.debugLog("Discord Monitor message ready:", newMessageId)
            return true
        end

        return false
    end

    function Monitor.installLoopToken()
        if Monitor.LoopToken and Monitor.LoopToken.Alive == true then
            return Monitor.LoopToken
        end

        local env = Monitor.getGlobalEnv()
        if env then
            local oldToken = env[Monitor.GLOBAL_LOOP_KEY]
            if type(oldToken) == "table" then
                oldToken.Alive = false
            end
        end

        local token = {Alive=true}
        Monitor.LoopToken = token
        if env then env[Monitor.GLOBAL_LOOP_KEY] = token end
        return token
    end

    function Monitor.disconnectGlobalConnection(key, current)
        local env = Monitor.getGlobalEnv()
        local stored = env and env[key]
        if stored and stored ~= current then
            pcall(function() stored:Disconnect() end)
        end
        if env then env[key] = nil end
    end

    function Monitor.disconnectHatchTracker()
        if Monitor.HatchConnection then
            pcall(function() Monitor.HatchConnection:Disconnect() end)
            Monitor.HatchConnection = nil
        end
        Monitor.disconnectGlobalConnection(Monitor.GLOBAL_HATCH_CONNECTION_KEY)
    end

    function Monitor.isHighRarity(rarityKey)
        local key = tostring(rarityKey or "Secret")
        if key == "Secret" then return true, true end
        local moonCount = tonumber(key:match("^(%d+)Moon$"))
        if moonCount and moonCount >= 3 then return true, false end
        if LOW_RARITIES[key] then return false, false end
        return true, true
    end

    function Monitor.handleHatch(hatch)
        if type(hatch) ~= "table" then return end
        local isHigh, countsAsSecret = Monitor.isHighRarity(hatch.RarityKey)
        if not isHigh then return end

        local state = Monitor.ensureState()
        state.LastHighRarityPet = tostring(hatch.PetName or "")
        state.LastHighRarityPetType = tostring(hatch.PetType or "Normal")
        state.CurrentPlayerClass = Monitor.getCurrentPlayerClass()
        if countsAsSecret then
            state.SecretsFound = (tonumber(state.SecretsFound) or 0) + 1
        end
        Monitor.setLastDebugMessage("Hatched " .. tostring(hatch.RarityKey or "Secret") .. " " .. tostring(hatch.PetName or "Unknown Pet"))
    end

    function Monitor.processHatchEvent(args)
        if not Core.alive or Core.state[Monitor.STATE_KEY] ~= true then return end
        local LogsPets = HS.Logs and HS.Logs.Pets
        if not LogsPets then return end

        args = type(args) == "table" and args or {}
        local eventPets = type(args[1]) == "table" and args[1] or {}
        local expectedCount = #eventPets
        local expectedPetCounts = LogsPets.getExpectedPetCounts and LogsPets.getExpectedPetCounts(eventPets) or nil
        local remainingPetCounts = LogsPets.copyPetCounts and LogsPets.copyPetCounts(expectedPetCounts) or nil
        local eggName = args[6] or "Unknown Egg"
        local state = Monitor.ensureState()

        if expectedCount > 0 then
            state.PetsHatched = (tonumber(state.PetsHatched) or 0) + expectedCount
        end

        if not (LogsPets.waitForReadyHatchFrames and LogsPets.isReadyHatchFrame and LogsPets.readHatchFrame) then
            state.CurrentPlayerClass = Monitor.getCurrentPlayerClass()
            return
        end

        local frames = LogsPets.waitForReadyHatchFrames(expectedCount, 6, expectedPetCounts)
        local seenFrames = {}
        local processedCount = 0

        for _, frame in ipairs(frames) do
            if expectedCount > 0 and processedCount >= expectedCount then break end
            if seenFrames[frame] or not LogsPets.isReadyHatchFrame(frame) then
                continue
            end

            local hatch = LogsPets.readHatchFrame(frame, eggName)
            if not hatch then
                continue
            end

            if LogsPets.consumeExpectedPet and not LogsPets.consumeExpectedPet(remainingPetCounts, hatch.PetName) then
                continue
            end

            seenFrames[frame] = true
            processedCount += 1
            Monitor.handleHatch(hatch)
        end

        if expectedCount == 0 and processedCount > 0 then
            state.PetsHatched = (tonumber(state.PetsHatched) or 0) + processedCount
        end
        state.CurrentPlayerClass = Monitor.getCurrentPlayerClass()
    end

    function Monitor.connectHatchTracker()
        if Monitor.HatchConnection then return end
        Monitor.disconnectHatchTracker()

        local LogsPets = HS.Logs and HS.Logs.Pets
        local remote = LogsPets and LogsPets.getRemote and LogsPets.getRemote()
        if not remote then
            Monitor.debugFailure("Discord Monitor hatch remote missing")
            return
        end

        Monitor.HatchConnection = remote.OnClientEvent:Connect(function(...)
            local args = {...}
            task.spawn(function()
                Monitor.processHatchEvent(args)
            end)
        end)

        local env = Monitor.getGlobalEnv()
        if env then
            env[Monitor.GLOBAL_HATCH_CONNECTION_KEY] = Monitor.HatchConnection
        end
    end

    function Monitor.setConnectionStatus(status)
        local state = Monitor.ensureState()
        state.ConnectionStatus = tostring(status or "Connected")
    end

    function Monitor.connectConnectionTracking()
        if Monitor.TeleportConnection or Monitor.GuiErrorConnection then return end
        Monitor.disconnectGlobalConnection(Monitor.GLOBAL_TELEPORT_CONNECTION_KEY)
        Monitor.disconnectGlobalConnection(Monitor.GLOBAL_ERROR_CONNECTION_KEY)

        pcall(function()
            Monitor.TeleportConnection = Core.player.OnTeleport:Connect(function(teleportState)
                local state = Monitor.ensureState()
                if teleportState == Enum.TeleportState.Started
                    or teleportState == Enum.TeleportState.WaitingForServer
                    or teleportState == Enum.TeleportState.InProgress then
                    state.ConnectionStatus = "Teleporting"
                    state.PendingRejoin = true
                    Core.setCurrentAction("Teleporting")
                elseif teleportState == Enum.TeleportState.Failed then
                    state.ConnectionStatus = "Connected"
                    state.PendingRejoin = false
                    Core.setCurrentAction("Idle")
                end
            end)
        end)

        pcall(function()
            Monitor.GuiErrorConnection = S.GuiService.ErrorMessageChanged:Connect(function(message)
                message = tostring(message or "")
                local state = Monitor.ensureState()
                if message ~= "" then
                    local lower = message:lower()
                    if state.ConnectionStatus ~= "Disconnected" and state.ConnectionStatus ~= "Rejoining" then
                        state.DisconnectCount = (tonumber(state.DisconnectCount) or 0) + 1
                    end
                    if lower:find("reconnect", 1, true) or lower:find("rejoin", 1, true) then
                        state.ConnectionStatus = "Rejoining"
                        Core.setCurrentAction("Rejoining Server")
                    else
                        state.ConnectionStatus = "Disconnected"
                        Core.setCurrentAction("Rejoining Server")
                    end
                    Monitor.setLastDebugMessage(message)
                elseif state.ConnectionStatus == "Disconnected" or state.ConnectionStatus == "Rejoining" then
                    state.ConnectionStatus = "Connected"
                    Core.setCurrentAction("Idle")
                end
            end)
        end)

        local env = Monitor.getGlobalEnv()
        if env then
            if Monitor.TeleportConnection then env[Monitor.GLOBAL_TELEPORT_CONNECTION_KEY] = Monitor.TeleportConnection end
            if Monitor.GuiErrorConnection then env[Monitor.GLOBAL_ERROR_CONNECTION_KEY] = Monitor.GuiErrorConnection end
        end
    end

    function Monitor.disconnectConnectionTracking()
        if Monitor.TeleportConnection then
            pcall(function() Monitor.TeleportConnection:Disconnect() end)
            Monitor.TeleportConnection = nil
        end
        if Monitor.GuiErrorConnection then
            pcall(function() Monitor.GuiErrorConnection:Disconnect() end)
            Monitor.GuiErrorConnection = nil
        end
        Monitor.disconnectGlobalConnection(Monitor.GLOBAL_TELEPORT_CONNECTION_KEY)
        Monitor.disconnectGlobalConnection(Monitor.GLOBAL_ERROR_CONNECTION_KEY)
    end

    function Monitor.start()
        if Monitor.Thread then return end
        if Core.state[Monitor.STATE_KEY] ~= true then return end

        local url = Monitor.getWebhookUrl()
        if url == "" then
            Monitor.debugFailure("Discord Monitor webhook URL missing")
            return
        end
        if not Monitor.isWebhookUrlValid(url) then
            Monitor.debugFailure("Discord Monitor webhook URL invalid")
            return
        end

        local token = Monitor.installLoopToken()
        Monitor.connectHatchTracker()
        Monitor.connectConnectionTracking()
        Monitor.RunId += 1
        local runId = Monitor.RunId

        Monitor.Thread = task.spawn(function()
            while Core.alive and Core.state[Monitor.STATE_KEY] == true and Monitor.RunId == runId and token.Alive == true do
                local ok, err = pcall(Monitor.update)
                if not ok then
                    Monitor.debugFailure("Discord Monitor update failed: " .. tostring(err))
                end

                local waited = 0
                local interval = Monitor.getUpdateInterval()
                while waited < interval
                    and Core.alive
                    and Core.state[Monitor.STATE_KEY] == true
                    and Monitor.RunId == runId
                    and token.Alive == true do
                    task.wait(0.5)
                    waited += 0.5
                end
            end

            if Monitor.RunId == runId then
                Monitor.Thread = nil
            end
        end)
    end

    function Monitor.stop()
        Monitor.RunId += 1
        Monitor.Thread = nil
        if Monitor.LoopToken then
            Monitor.LoopToken.Alive = false
            Monitor.LoopToken = nil
        end
        local env = Monitor.getGlobalEnv()
        local oldToken = env and env[Monitor.GLOBAL_LOOP_KEY]
        if type(oldToken) == "table" then
            oldToken.Alive = false
        end
        if env then
            env[Monitor.GLOBAL_LOOP_KEY] = nil
        end
        Monitor.disconnectHatchTracker()
        Monitor.disconnectConnectionTracking()
        Core.setCurrentAction("Idle")

        -- Send a final update marking the session as Disconnected/offline
        task.spawn(function()
            local url = Monitor.getWebhookUrl()
            if url == "" or not Monitor.isWebhookUrlValid(url) then return end
            local state = Monitor.ensureState()
            state.ConnectionStatus = "Disconnected"
            local ok, payload = pcall(Monitor.buildPayload)
            if ok and payload then
                -- Force the embed color to red (Disconnected)
                local embed = payload.embeds and payload.embeds[1]
                if embed then embed.color = 15548997 end
                local messageId = Monitor.getMessageId()
                if messageId then
                    Monitor.editMessage(url, messageId, payload)
                else
                    local newId = Monitor.createMessage(url, payload)
                    if newId then Monitor.setMessageId(newId) end
                end
            end
            -- Restore state to neutral so it doesn't persist as Disconnected on next start
            state.ConnectionStatus = "Connected"
        end)
    end

    function Monitor.setEnabled(on)
        Core.state[Monitor.STATE_KEY] = on == true
        if Core.syncLogsConfig then pcall(Core.syncLogsConfig) end

        if Core.state[Monitor.STATE_KEY] then
            local url = Monitor.getWebhookUrl()
            if url == "" then
                Core.state[Monitor.STATE_KEY] = false
                Core.syncLogsConfig()
                Monitor.debugFailure("Discord Monitor webhook URL missing")
                Monitor.stop()
                return
            end
            if not Monitor.isWebhookUrlValid(url) then
                Core.state[Monitor.STATE_KEY] = false
                Core.syncLogsConfig()
                Monitor.debugFailure("Discord Monitor webhook URL invalid")
                Monitor.stop()
                return
            end
            Monitor.start()
        else
            Monitor.stop()
        end
    end

    function Monitor.onSettingsChanged()
        local config = Core.getLogsConfig().DiscordMonitor
        local previousUrl = Monitor.LastWebhookUrl or config.WebhookURL or ""
        if Core.syncLogsConfig then pcall(Core.syncLogsConfig) end

        local currentUrl = Monitor.getWebhookUrl()
        Monitor.LastWebhookUrl = currentUrl
        if previousUrl ~= "" and previousUrl ~= currentUrl then
            Monitor.setMessageId(nil, true)
        end

        if HS.Session and HS.Session.save then
            pcall(HS.Session.save)
        end

        if Core.state[Monitor.STATE_KEY] == true then
            Monitor.setEnabled(true)
        end
    end

    function Monitor.sync()
        if Core.state[Monitor.STATE_KEY] == true then
            Monitor.setEnabled(true)
        else
            Monitor.stop()
        end
    end
end
-- HEARTSTEEL_MODULE_END: LogsDiscordMonitor

do
    local UI     = HS.UI
    local Core   = HS.Core
    local C      = Core.C
    HS.StandaloneScripts = HS.StandaloneScripts or {}

    local StandaloneScripts = HS.StandaloneScripts
    StandaloneScripts.Scripts = StandaloneScripts.Scripts or {}

    function StandaloneScripts.add(label, callback, options)
        options = type(options) == "table" and options or {}
        StandaloneScripts.Scripts[#StandaloneScripts.Scripts + 1] = {
            label = label,
            callback = callback,
            buttonText = options.buttonText,
            danger = options.danger == true,
        }
    end

    StandaloneScripts.add("Remote Spy", function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Klinac/scripts/main/utopia_spy.lua", true))()
    end)

    StandaloneScripts.add("Health Check", function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Patolas1904/Heartsteel-Beta/dev/src/healthcheck.lua"))()
    end)

    function StandaloneScripts.run(script)
        if type(script) ~= "table" then return end

        local runner = script.callback or script.run
        if type(runner) ~= "function" then
            Core.debugLog("Standalone script missing callback:", script.label or script.name or "Unnamed")
            return
        end

        local ok, err = pcall(runner)
        if not ok then
            Core.debugLog("Standalone script failed:", script.label or script.name or "Unnamed", tostring(err))
        end
    end

    function StandaloneScripts.getUiItems()
        local items = {}
        for _, script in ipairs(StandaloneScripts.Scripts) do
            if type(script) == "table" then
                local capturedScript = script
                items[#items + 1] = {
                    type = "action",
                    label = tostring(script.label or script.name or "Standalone Script"),
                    buttonText = script.buttonText or "RUN",
                    danger = script.danger == true,
                    callback = function()
                        StandaloneScripts.run(capturedScript)
                    end,
                }
            end
        end

        if #items == 0 then
            items[#items + 1] = {type="note", text="No standalone scripts added yet."}
        end

        return items
    end

    -- ── Tiny GUI helpers ─────────────────────────────────────────
    function UI.make(class, props, parent)
        local obj = Instance.new(class)
        for k, v in pairs(props or {}) do obj[k] = v end
        if parent then obj.Parent = parent end
        return obj
    end

    function UI.addCorner(obj, radius)
        UI.make("UICorner", {CornerRadius=UDim.new(0, radius or 4)}, obj)
    end

    function UI.addStroke(obj, color, thickness, transparency)
        UI.make("UIStroke", {
            Color=color or C.border, Thickness=thickness or 1,
            Transparency=transparency or 0,
        }, obj)
    end

    function UI.clearChildren(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding")
                and not child:IsA("UIGridLayout") and not child:IsA("UIScale")
                and not child:IsA("UIStroke") then
                child:Destroy()
            end
        end
    end

    function UI.countEnabled()
        local n = 0
        for _, v in pairs(Core.state) do if v then n += 1 end end
        return n
    end

    function UI.allOff(skipSave)
        for key in pairs(Core.state) do
            Core.state[key] = false
            local cb = Core.callbacks[key]
            if cb then task.spawn(cb, false) end
        end
        local fcc = HS.Farming.crownsConnection
        if fcc then fcc:Disconnect(); HS.Farming.crownsConnection = nil end
        if HS.ElementZonePull and HS.ElementZonePull.stopElementNoclip then
            HS.ElementZonePull.stopElementNoclip()
        end
        Core.priorityOwner = nil
        if not skipSave then HS.Session.save() end
    end

    -- ── Quest title reader ───────────────────────────────────────
    local SF_PATH = {"MainGui","OtherFrames","Clans","InClan","Frames","Quests","ScrollingFrame"}

    local function getScrollingFrame()
        local node = Core.player:FindFirstChild("PlayerGui"); if not node then return nil end
        for _, name in ipairs(SF_PATH) do node = node:FindFirstChild(name); if not node then return nil end end
        return node
    end

    function UI.refreshQuestTitles()
        local sf = getScrollingFrame(); if not sf then return end
        local quests = {}
        for _, child in ipairs(sf:GetChildren()) do
            if child.Name == "Quest" then table.insert(quests, child) end
        end
        table.sort(quests, function(a,b) return a.LayoutOrder < b.LayoutOrder end)
        for i, lbl in ipairs(Core.questTitleLabels) do
            local q    = quests[i]
            local info = q and q:FindFirstChild("InfoText")
            local text = (info and info.Text ~= "") and info.Text or Core.questTitleCache[i] or ("Quest " .. i)
            if info and info.Text ~= "" then Core.questTitleCache[i] = info.Text end
            if lbl and lbl.Parent then
                lbl.Text = text
            end
        end
    end
    _G.refreshQuestTitles = UI.refreshQuestTitles

    local sidebar, content  -- forward refs; assigned during build

    -- ── Nav ──────────────────────────────────────────────────────
    UI.navButtons = {}

    function UI.refreshNav()
        for key, btn in pairs(UI.navButtons) do
            if key == Core.activeTab then
                btn.TextColor3 = C.purple; btn.BackgroundTransparency = 0.88; btn.BackgroundColor3 = C.rowActive
            else
                btn.TextColor3 = C.textDim; btn.BackgroundTransparency = 1; btn.BackgroundColor3 = Color3.new()
            end
        end
    end

    function UI.isTabVisible(tab)
        if type(tab) ~= "table" then return false end
        if tab.testingOnly == true and Core.state.testing_mode ~= true then return false end
        if tab.debugOnly == true and Core.state.debug_mode ~= true then return false end
        return true
    end

    function UI.ensureActiveTabVisible()
        local tabData = UI.UI_DATA and UI.UI_DATA[Core.activeTab]
        if UI.isTabVisible(tabData) then return end
        Core.activeTab = "misc"
    end

    function UI.renderSidebar()
        if not sidebar then return end

        UI.clearChildren(sidebar)
        table.clear(UI.navButtons)
        for _, tab in ipairs(UI.TAB_ORDER or {}) do
            if tab.separator then
                local sepWrap = UI.make("Frame", {Parent=sidebar, Size=UDim2.new(1,0,0,14), BackgroundTransparency=1})
                UI.make("Frame", {Parent=sepWrap, Size=UDim2.new(1,-20,0,1), Position=UDim2.new(0,10,0.5,0), BackgroundColor3=C.border, BorderSizePixel=0})
            elseif UI.isTabVisible(tab) then
                local btn = UI.make("TextButton", {Parent=sidebar, Size=UDim2.new(1,0,0,34), BackgroundColor3=Color3.new(), BackgroundTransparency=1, Text=tab.label, Font=Enum.Font.GothamBold, TextSize=11, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left, AutoButtonColor=false})
                UI.make("UIPadding", {Parent=btn, PaddingLeft=UDim.new(0,14)})
                UI.navButtons[tab.key] = btn
                btn.MouseButton1Click:Connect(function() Core.activeTab = tab.key; UI.renderContent() end)
            end
        end
        UI.refreshNav()
    end

    -- ── Status bar ───────────────────────────────────────────────
    UI.statusDot  = nil
    UI.statusText = nil

    function UI.updateStatus()
        if not Core.alive then
            UI.statusText.Text = "killed"; UI.statusDot.BackgroundColor3 = Color3.fromRGB(160,32,32); return
        end
        local n = UI.countEnabled()
        if n > 0 then
            UI.statusText.Text = tostring(n) .. " active"; UI.statusDot.BackgroundColor3 = C.purple
        else
            UI.statusText.Text = "idle"; UI.statusDot.BackgroundColor3 = C.border2
        end
    end

    -- ── Row builders ─────────────────────────────────────────────
    function UI.sectionTitle(text)
        local holder = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,20), BackgroundTransparency=1})
        local marker = UI.make("Frame", {Parent=holder, Size=UDim2.fromOffset(3,10), Position=UDim2.new(0,0,0,5), BackgroundColor3=C.purple, BorderSizePixel=0})
        UI.addCorner(marker, 1)
        UI.make("TextLabel", {Parent=holder, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-8,1,0), Text=text, Font=Enum.Font.Garamond, TextSize=12, TextColor3=C.purpleDark, TextXAlignment=Enum.TextXAlignment.Left})
        UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,1), BackgroundColor3=C.border, BorderSizePixel=0})
    end

    function UI.makeToggleVisual(parent, on)
        local track = UI.make("Frame", {Parent=parent, Size=UDim2.fromOffset(32,17), Position=UDim2.new(1,-40,0.5,-8), BackgroundColor3=on and C.toggleOn or C.toggleOff, BorderSizePixel=0})
        UI.addCorner(track, 2); UI.addStroke(track, on and C.purple or C.border, 1)
        local knob = UI.make("Frame", {Parent=track, Size=UDim2.fromOffset(11,11), Position=on and UDim2.fromOffset(17,2) or UDim2.fromOffset(2,2), BackgroundColor3=on and C.purple or C.border2, BorderSizePixel=0})
        UI.addCorner(knob, 1)
    end

    function UI.toggleKey(key)
        if not Core.alive then return end
        Core.state[key] = not Core.state[key]
        local cb = Core.callbacks[key]
        if cb then
            task.spawn(function()
                local ok, err = pcall(cb, Core.state[key])
                if not ok then
                    Core.debugLog("Toggle callback failed:", key, tostring(err))
                end
                HS.Session.save()
            end)
        end
        HS.Session.save()
        UI.renderContent()
    end

    function UI.makeMerchantPetLabel(parent, item, labelColor, textSz)
        local display = item.petRarity
        local holder = UI.make("Frame", {
            Parent=parent,
            BackgroundTransparency=1,
            Position=UDim2.fromOffset(8,0),
            Size=UDim2.new(1, -50, 1, 0),
        })
        UI.make("UIListLayout", {
            Parent=holder,
            FillDirection=Enum.FillDirection.Horizontal,
            SortOrder=Enum.SortOrder.LayoutOrder,
            VerticalAlignment=Enum.VerticalAlignment.Center,
            Padding=UDim.new(0, 3),
        })

        local function makeRarityIcon(asset)
            return UI.make("ImageLabel", {
                Parent=holder,
                BackgroundTransparency=1,
                Size=UDim2.fromOffset(13, 13),
                Image=asset,
                ImageColor3=labelColor,
                ScaleType=Enum.ScaleType.Fit,
            })
        end

        if display.classText and display.classText ~= "" then
            UI.make("TextLabel", {
                Parent=holder,
                BackgroundTransparency=1,
                Size=UDim2.fromOffset(0, textSz + 8),
                AutomaticSize=Enum.AutomaticSize.X,
                Text=display.classText,
                Font=Enum.Font.Gotham,
                TextSize=textSz,
                TextColor3=labelColor,
                TextXAlignment=Enum.TextXAlignment.Left,
            })
        end

        if display.asset then
            for _ = 1, display.iconCount or 1 do
                makeRarityIcon(display.asset)
            end
            UI.make("TextLabel", {
                Parent=holder,
                BackgroundTransparency=1,
                Size=UDim2.fromOffset(0, textSz + 8),
                AutomaticSize=Enum.AutomaticSize.X,
                Text="Pet" .. (item.labelSuffix or ""),
                Font=Enum.Font.Gotham,
                TextSize=textSz,
                TextColor3=labelColor,
                TextXAlignment=Enum.TextXAlignment.Left,
            })
        else
            UI.make("TextLabel", {
                Parent=holder,
                BackgroundTransparency=1,
                Size=UDim2.fromOffset(0, textSz + 8),
                AutomaticSize=Enum.AutomaticSize.X,
                Text=(display.fallbackText or "Pet") .. (item.labelSuffix or ""),
                Font=Enum.Font.Gotham,
                TextSize=textSz,
                TextColor3=labelColor,
                TextXAlignment=Enum.TextXAlignment.Left,
            })
        end
    end

    function UI.makeToggleRow(item)
        local on      = Core.state[item.key]
        local compact = item.compact == true
        local rowH    = compact and 22 or 30
        local textSz  = compact and 10 or 12
        local wrapper = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,rowH), BackgroundTransparency=1})
        if compact then
            UI.make("Frame", {Parent=wrapper, Size=UDim2.new(0,1,0.5,0),     Position=UDim2.fromOffset(10,0),       BackgroundColor3=C.border2, BorderSizePixel=0})
            UI.make("Frame", {Parent=wrapper, Size=UDim2.new(0,8,0,1),        Position=UDim2.fromOffset(10,rowH/2), BackgroundColor3=C.border2, BorderSizePixel=0})
        end
        local xOffset = compact and 22 or 0
        local row = UI.make("TextButton", {Parent=wrapper, Position=UDim2.fromOffset(xOffset,0), Size=UDim2.new(1,-xOffset,1,0), BackgroundTransparency=on and 0 or 1, BackgroundColor3=on and C.rowActive or C.rowHover, Text="", AutoButtonColor=false})
        UI.addCorner(row, 3)
        local labelColor = on and C.text or (compact and C.textDim or C.purpleSoft)
        if item.petRarity then
            UI.makeMerchantPetLabel(row, item, labelColor, textSz)
        else
            UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1, item.showTimer and -106 or -50, 1, 0), Text=item.label, Font=Enum.Font.Gotham, TextSize=textSz, TextColor3=labelColor, TextXAlignment=Enum.TextXAlignment.Left})
        end
        if item.showTimer then
            HS.Dungeon.timerLabel = UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.new(1,-98,0,0), Size=UDim2.fromOffset(54,30), Text="0:00", Font=Enum.Font.GothamBold, TextSize=11, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Right})
            HS.Dungeon.startTimer()
        end
        UI.makeToggleVisual(row, on)
        row.MouseButton1Click:Connect(function() UI.toggleKey(item.key) end)
    end

    function UI.makeTeleportRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,30), BackgroundTransparency=1})
        UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-70,1,0), Text=item.label, Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        local btn = UI.make("TextButton", {Parent=row, Size=UDim2.fromOffset(50,20), Position=UDim2.new(1,-50,0.5,-10), BackgroundTransparency=1, Text="GO", TextColor3=C.orange, Font=Enum.Font.GothamBold, TextSize=10})
        UI.addCorner(btn, 2); UI.addStroke(btn, C.border2, 1)
        btn.MouseButton1Click:Connect(function() if item.callback then task.spawn(item.callback) end end)
    end

    function UI.makeQuestRow(item)
        local lbl = UI.make("TextLabel", {Parent=content, BackgroundTransparency=1, Size=UDim2.new(1,0,0,20), Text="Quest " .. (item.questIdx or "?"), Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        if item.questIdx then Core.questTitleLabels[item.questIdx] = lbl end
    end

    function UI.makeAutoCycleTimerRow()
    local row = UI.make("Frame", {
        Parent = content,
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
    })

    UI.autoCycleTimerLabel = UI.make("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(22, 0),
        Size = UDim2.new(1, -30, 1, 0),
        Text = "Cycle timer: inactive",
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextColor3 = C.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    end

    function UI.makeIncubatorSlotsRows()
        for _, info in ipairs(HS.Dungeon.incubatorSlots) do
            UI.make("TextLabel", {Parent=content, BackgroundTransparency=1, Size=UDim2.new(1,0,0,18), Text=string.format("slot %d - %s", info.slot, info.text), Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left})
        end
    end

    function UI.makeDungeonEggTimerLogRows()
        if not (HS.Logs and HS.Logs.Dungeon and Core.state[HS.Logs.Dungeon.STATE_KEY] == true) then
            if HS.Logs and HS.Logs.Dungeon then HS.Logs.Dungeon.bindTimerRows({}) end
            return
        end

        local labels = {}
        for slot = 1, (HS.Dungeon and HS.Dungeon.MAX_INCUBATOR_SLOTS or 6) do
            labels[slot] = UI.make("TextLabel", {
                Parent=content,
                BackgroundTransparency=1,
                Size=UDim2.new(1,0,0,0),
                Text="",
                Font=Enum.Font.Gotham,
                TextSize=11,
                TextColor3=C.textDim,
                TextXAlignment=Enum.TextXAlignment.Left,
                Visible=false,
            })
        end
        HS.Logs.Dungeon.bindTimerRows(labels)
    end

    function UI.makeSliderRow(item)
        local minVal = item.min ~= nil and item.min or 16
        local maxVal = item.max ~= nil and item.max or 160
        local val = Core.sliderState[item.key]
        if val == nil and item.getValue then val = item.getValue() end
        if val == nil then val = item.default ~= nil and item.default or minVal end
        val = math.clamp(tonumber(val) or minVal, minVal, maxVal)
        local pendingVal = val
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,44), BackgroundTransparency=1})
        local topBar = UI.make("Frame", {Parent=row, BackgroundTransparency=1, Size=UDim2.new(1,0,0,18)})
        UI.make("TextLabel", {Parent=topBar, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-70,1,0), Text=item.label, Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        local valLabel = UI.make("TextLabel", {Parent=topBar, BackgroundTransparency=1, Position=UDim2.new(1,-60,0,0), Size=UDim2.fromOffset(52,18), Text=tostring(val), Font=Enum.Font.GothamBold, TextSize=12, TextColor3=C.purple, TextXAlignment=Enum.TextXAlignment.Right})

        local track = UI.make("Frame", {Parent=row, Size=UDim2.new(1,-16,0,6), Position=UDim2.new(0,8,0,30), BackgroundColor3=C.toggleOff, BorderSizePixel=0})
        UI.addCorner(track, 3); UI.addStroke(track, C.border, 1)
        local fillPct = (val - minVal) / (maxVal - minVal)
        local fill = UI.make("Frame", {Parent=track, Size=UDim2.new(fillPct,0,1,0), BackgroundColor3=C.purpleDark, BorderSizePixel=0})
        UI.addCorner(fill, 3)
        local knob = UI.make("Frame", {Parent=track, Size=UDim2.fromOffset(14,14), Position=UDim2.new(fillPct,0,0.5,-7), BackgroundColor3=C.purpleDark, BorderSizePixel=0})
        UI.addCorner(knob, 999); UI.addStroke(knob, C.border, 1)

        local dragging = false
        local function updateSlider(absX)
            local trackAbs = track.AbsolutePosition.X
            local trackW = track.AbsoluteSize.X
            if trackW <= 0 then return end
            local pct = math.clamp((absX - trackAbs) / trackW, 0, 1)
            pendingVal = math.floor(minVal + pct * (maxVal - minVal) + 0.5)
            fill.Size = UDim2.new(pct, 0, 1, 0)
            knob.Position = UDim2.new(pct, 0, 0.5, -7)
            fill.BackgroundColor3 = C.purple
            knob.BackgroundColor3 = C.purple
            valLabel.Text = tostring(pendingVal)
            if item.key then Core.sliderState[item.key] = pendingVal end
            if item.callback then item.callback(pendingVal) end
            HS.Session.save()
        end

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                updateSlider(input.Position.X)
            end
        end)
        track.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        S.UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                updateSlider(input.Position.X)
            end
        end)
    end

    function UI.makeSelectionRow(item)
        local options      = item.options or {}
        local instant      = item.instant == true
        local currentValue = Core.selectionState[item.key] or item.default or options[1] or ""
        local currentIndex = table.find(options, currentValue) or 1
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,58), BackgroundTransparency=1})
        UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-16,0,18), Text=item.label or "Selection", Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        local selectBox = UI.make("TextButton", {Parent=row, Size=UDim2.new(1, instant and -16 or -78, 0, 26), Position=UDim2.new(0,8,0,24), BackgroundColor3=C.toggleOff, Text=currentValue, TextColor3=C.text, Font=Enum.Font.Gotham, TextSize=12, AutoButtonColor=false})
        UI.addCorner(selectBox, 3); UI.addStroke(selectBox, C.border2, 1)
        local applyBtn
        if not instant then
            applyBtn = UI.make("TextButton", {Parent=row, Size=UDim2.fromOffset(62,26), Position=UDim2.new(1,-70,0,24), BackgroundTransparency=1, Text="APPLY", TextColor3=C.orange, Font=Enum.Font.GothamBold, TextSize=10})
            UI.addCorner(applyBtn, 2); UI.addStroke(applyBtn, C.border2, 1)
        end
        selectBox.MouseButton1Click:Connect(function()
            if #options == 0 then return end
            currentIndex += 1; if currentIndex > #options then currentIndex = 1 end
            currentValue = options[currentIndex]
            if item.key then Core.selectionState[item.key] = currentValue end
            selectBox.Text = currentValue
            if instant and item.callback then item.callback(currentValue) end
            HS.Session.save()
        end)
        if applyBtn then
            applyBtn.MouseButton1Click:Connect(function()
                if item.callback then item.callback(currentValue) end
                applyBtn.TextColor3 = C.purple
                task.delay(0.4, function() if applyBtn and applyBtn.Parent then applyBtn.TextColor3 = C.orange end end)
            end)
        end
    end

    function UI.makeInputRow(item)
        local currentValue = Core.inputState[item.key]
        if currentValue == nil then currentValue = item.default or "" end
        currentValue = tostring(currentValue)

        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,52), BackgroundTransparency=1})
        UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0),
            Size=UDim2.new(1,-16,0,18), Text=item.label or "Input",
            Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft,
            TextXAlignment=Enum.TextXAlignment.Left,
        })
        local box = UI.make("TextBox", {
            Parent=row, Size=UDim2.new(1,-16,0,26), Position=UDim2.fromOffset(8,22),
            BackgroundColor3=C.toggleOff, Text=currentValue, PlaceholderText=item.placeholder or "",
            TextColor3=C.text, PlaceholderColor3=C.textDim, Font=Enum.Font.Gotham,
            TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ClearTextOnFocus=false,
        })
        UI.addCorner(box, 3); UI.addStroke(box, C.border2, 1)
        UI.make("UIPadding", {Parent=box, PaddingLeft=UDim.new(0,8), PaddingRight=UDim.new(0,8)})
        box.FocusLost:Connect(function()
            Core.inputState[item.key] = box.Text or ""
            if item.callback then item.callback(Core.inputState[item.key]) end
            HS.Session.save()
        end)
    end

    function UI.makeSimpleLabel(text)
        UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,6), BackgroundTransparency=1})
        UI.sectionTitle(text)
    end

    function UI.makeNoteRow(text)
        UI.make("TextLabel", {
            Parent=content, BackgroundTransparency=1, Size=UDim2.new(1,0,0,24),
            Text=text or "", Font=Enum.Font.Gotham, TextSize=11,
            TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left,
            TextWrapped=true,
        })
    end

    function UI.makeMerchantSeparatorRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,30), BackgroundColor3=C.rowActive, BorderSizePixel=0})
        UI.addCorner(row, 3); UI.addStroke(row, C.border2, 1, 0.15)
        UI.make("Frame", {Parent=row, Size=UDim2.fromOffset(4,18), Position=UDim2.new(0,8,0.5,-9), BackgroundColor3=C.orange, BorderSizePixel=0})
        UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(18,0),
            Size=UDim2.new(1,-26,1,0), Text=string.upper(item.text or ""),
            Font=Enum.Font.GothamBold, TextSize=11, TextColor3=C.orange,
            TextXAlignment=Enum.TextXAlignment.Left,
        })
    end

    function UI.makeMerchantSubseparatorRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,22), BackgroundTransparency=1})
        UI.make("Frame", {Parent=row, Size=UDim2.new(0,18,0,1), Position=UDim2.new(0,10,0.5,0), BackgroundColor3=C.border2, BorderSizePixel=0})
        UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(34,0),
            Size=UDim2.new(1,-42,1,0), Text=item.text or "",
            Font=Enum.Font.GothamBold, TextSize=10, TextColor3=C.purple,
            TextXAlignment=Enum.TextXAlignment.Left,
        })
    end

    function UI.makeStatusRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,28), BackgroundTransparency=1})
        local lbl = UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-16,1,0), Text=item.text or "", Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left})
        if item.bind == "session" then
            HS.Session.statusLabel = lbl
            HS.Session.setStatus(HS.Session.lastMessage)
        elseif item.bind == "boss" then
            HS.Farming.bossStatusLabel = lbl
            HS.Farming.setBossStatus(item.text or "Boss: idle", C.textDim)
        elseif item.bind == "merchant" then
            HS.Merchant.statusLabel = lbl
            HS.Merchant.setStatus(HS.Merchant.status or "waiting")
            HS.Merchant.startDisplayWatcher()
        elseif item.bind == "clan_auto" then
            HS.Farming.clanQuestStatusLabel = lbl
            HS.Farming.setClanQuestStatus(HS.Farming.clanQuestStatus or "waiting: idle")
        elseif item.bind == "auto_craft_pets" then
            HS.Pets.statusLabel = lbl
            HS.Pets.setStatus(HS.Pets.status or "Auto Craft: waiting")
        end
    end

    function UI.makePetdexProgressRow()
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,126), BackgroundColor3=C.toggleOff, BorderSizePixel=0})
        UI.addCorner(row, 3); UI.addStroke(row, C.border, 1)
        local lbl = UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,6),
            Size=UDim2.new(1,-16,1,-12), Text=HS.PetdexFarm.getProgressText(),
            Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim,
            TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top,
            TextWrapped=true,
        })
        HS.PetdexFarm.progressLabel = lbl
        task.spawn(HS.PetdexFarm.refreshProgress)
    end

    function UI.makePetdexRewardsStatusRow()
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,94), BackgroundColor3=C.toggleOff, BorderSizePixel=0})
        UI.addCorner(row, 3); UI.addStroke(row, C.border, 1)
        local lbl = UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,6),
            Size=UDim2.new(1,-16,1,-12), Text=HS.PetdexRewards.getStatusText(),
            Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim,
            TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top,
            TextWrapped=true,
        })
        HS.PetdexRewards.statusLabel = lbl
        task.spawn(HS.PetdexRewards.refreshStatus)
    end

    function UI.makeEggOpenerStatusRow()
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,90), BackgroundColor3=C.toggleOff, BorderSizePixel=0})
        UI.addCorner(row, 3); UI.addStroke(row, C.border, 1)
        local lbl = UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,6),
            Size=UDim2.new(1,-16,1,-12), Text=HS.EggOpener.getStatusText(),
            Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim,
            TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top,
            TextWrapped=true,
        })
        HS.EggOpener.statusLabel = lbl
        task.spawn(function()
            HS.EggOpener.init()
            HS.EggOpener.updateSelection()
        end)
    end

    function UI.makeActionRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,34), BackgroundTransparency=1})
        UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-92,1,0), Text=item.label, Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        local btn = UI.make("TextButton", {Parent=row, Size=UDim2.fromOffset(76,24), Position=UDim2.new(1,-76,0.5,-12), BackgroundTransparency=1, Text=item.buttonText or "RUN", TextColor3=item.danger and C.red or C.orange, Font=Enum.Font.GothamBold, TextSize=10})
        UI.addCorner(btn, 2); UI.addStroke(btn, item.danger and C.redDark or C.border2, 1)
        btn.MouseButton1Click:Connect(function()
            if item.callback then task.spawn(item.callback) end
        end)
    end

    -- ── Render ───────────────────────────────────────────────────
    function UI.renderContent()
        Core.questTitleLabels = {}
        UI.ensureActiveTabVisible()
        UI.clearChildren(content)
        local tabData = UI.UI_DATA[Core.activeTab]
        if not tabData then return end
        if Core.activeTab == "merchant" then
            tabData.items = HS.Merchant.getUiItems(true)
        elseif Core.activeTab == "standalone_scripts" then
            tabData.items = HS.StandaloneScripts.getUiItems()
        end
        UI.sectionTitle(tabData.title)
        for _, item in ipairs(tabData.items) do
            if     item.type == "slider"          then UI.makeSliderRow(item)
            elseif item.type == "selection"       then UI.makeSelectionRow(item)
            elseif item.type == "input"           then UI.makeInputRow(item)
            elseif item.type == "toggle"          then UI.makeToggleRow(item)
            elseif item.type == "teleport"        then UI.makeTeleportRow(item)
            elseif item.type == "quest"           then UI.makeQuestRow(item)
            elseif item.type == "incubator_slots" then UI.makeIncubatorSlotsRows()
            elseif item.type == "dungeon_egg_timer_logs" then UI.makeDungeonEggTimerLogRows()
            elseif item.type == "label"           then UI.makeSimpleLabel(item.text)
            elseif item.type == "note"            then UI.makeNoteRow(item.text)
            elseif item.type == "merchant_separator" then UI.makeMerchantSeparatorRow(item)
            elseif item.type == "merchant_subseparator" then UI.makeMerchantSubseparatorRow(item)
            elseif item.type == "cycle_timer"     then UI.makeAutoCycleTimerRow()
            elseif item.type == "status"          then UI.makeStatusRow(item)
            elseif item.type == "petdex_progress" then UI.makePetdexProgressRow()
            elseif item.type == "petdex_rewards_status" then UI.makePetdexRewardsStatusRow()
            elseif item.type == "eggopener_status" then UI.makeEggOpenerStatusRow()
            elseif item.type == "action"          then UI.makeActionRow(item)
            end
        end
        UI.updateStatus(); UI.renderSidebar()
        if Core.activeTab == "clan" then task.spawn(UI.refreshQuestTitles) end
    end

    -- ── UI_DATA ──────────────────────────────────────────────────
    UI.UI_DATA = {
        farming = {
            title = "automation",
            items = {
                {type="toggle", key="swing",   label="Auto Swing",   callback=function(on) if on then HS.Farming.startSwing() end end},
                {type="toggle", key="sell",    label="Auto Sell",    callback=function(on) if on then HS.Farming.startSell()  end end},
                {type="toggle", key="boss",    label="Auto Farm Boss",
                    callback=function(on)
                        if on then HS.Farming.startBoss()
                        else HS.Farming.stopBoss() end
                    end},
                {type="toggle", key="boss_tp", label="Auto TP Boss", compact=true,
                    callback=function(on)
                        if on and Core.state.boss then HS.Farming.startBoss() end
                    end},
                {type="status", bind="boss", text="Boss: idle"},
                {type="toggle", key="crowns",  label="Auto Collect Crowns",
                    callback=function(on)
                        if on then HS.Farming.startCrowns()
                        else
                            local cc = HS.Farming.crownsConnection
                            if cc then cc:Disconnect(); HS.Farming.crownsConnection = nil end
                        end
                    end},
                {type="toggle", key="claim_flags", label="Capture Flags",
                    callback=function(on) if on then HS.Flags.startCaptureFlags() end end},
                {type="toggle", key="flag_avoid", label="Avoid Players", compact=true, callback=function() end},
                {type="toggle", key="claim_koth", label="King",
                    callback=function(on) if on then HS.Farming.startKoth() end end},
                {type="toggle", key="koth_avoid", label="Avoid Players", compact=true, callback=function() end},
            },
        },
        misc = {
            title = "Various",
            items = {
                {type="toggle", key="debug_mode",         label="Debug Mode",       default=true,  callback=function() end},
                {type="toggle", key="testing_mode",       label="Testing Mode",     default=false, callback=function() end},
                {type="toggle", key="anti_afk", label="Anti-AFK", default=true,
                    callback=function(on)
                        if on then HS.Misc.startAntiAfk(); task.spawn(HS.Misc.antiAfkPulse, "toggle-on"); Core.debugLog("Anti AFK active")
                        else Core.debugLog("Anti AFK inactive") end
                    end},
                {type="toggle", key="simulate_movement", label="Simulate Movement",
                    callback=function(on)
                        if on then HS.Misc.startSimulateMovement(); Core.debugLog("Simulate movement active")
                        else Core.debugLog("Simulate movement inactive") end
                    end},
                {type="toggle", key="fast_hit", label="Fast Hit (Experimental)", callback=function() end},
                {type="teleport", label="Save Pos",    callback=function() HS.Misc.saveCurrentPosition() end},
                {type="teleport", label="TP Saved Pos",callback=function() HS.Misc.teleportToSavedPosition() end},
                {type="teleport", label="Copy Pos",    callback=function() HS.Misc.copyCurrentPosition() end},
                {type="toggle", key="move_speed", label="Move Speed",
                    callback=function(on)
                        if on then HS.Misc.startSpeed() else HS.Misc.stopSpeed() end
                    end},
                {type="slider", key="movespeed_val", label="Speed Value", min=16, max=160, default=16,
                    callback=function(val) HS.Misc.setSpeed(val) end},
            },
        },
        session = {
            title = "Session",
            items = {
                {type="status", bind="session", text="No session loaded"},
                {type="action", label="Reset saved session", buttonText="RESET", danger=true,
                    callback=function()
                        HS.Session.resetNextStartup()
                    end},
            },
        },
        standalone_scripts = {
            title = "Standalone Scripts",
            testingOnly = true,
            items = {},
        },
        elements = {
            title = "Main",
            items = {
                {type="selection", key="selected_element", label="Change Element",
                    options=HS.Misc.ELEMENT_OPTIONS, default="Fire",
                    callback=function(value) HS.Misc.applyElement(value) end},
                {type = "toggle",
                 key = "auto_cycle",
                 label = "Auto Cycle",
                 callback = function(on)
                    if on then
                        HS.AutoCycle.start()
                    else
                        HS.AutoCycle.stop()
                        end
                    end
                },
                {type = "cycle_timer"},

                {type="label", text="Fire"},
                {type="toggle", key="fire_starter_pull", label="Fire Starter Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Fire", "Starter")
                    else HS.ElementZonePull.stop("Fire", "Starter") end
                end},
                {type="toggle", key="fire_advanced_pull", label="Fire Advanced Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Fire", "Advanced")
                    else HS.ElementZonePull.stop("Fire", "Advanced") end
                end},
                {type="toggle", key="fire_master_pull", label="Fire Master Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Fire", "Master")
                    else HS.ElementZonePull.stop("Fire", "Master") end
                end},
               {type="toggle", key="fire_grandmaster_pull", label="Fire Grandmaster Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Fire", "Grandmaster")
                    else HS.ElementZonePull.stop("Fire", "Grandmaster") end
                end},

                {type="label", text="Water"},
                {type="toggle", key="water_starter_pull", label="Water Starter Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Water", "Starter")
                    else HS.ElementZonePull.stop("Water", "Starter") end
                end},
                {type="toggle", key="water_advanced_pull", label="Water Advanced Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Water", "Advanced")
                    else HS.ElementZonePull.stop("Water", "Advanced") end
                end},
                {type="toggle", key="water_master_pull", label="Water Master Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Water", "Master")
                    else HS.ElementZonePull.stop("Water", "Master") end
                end},
               {type="toggle", key="water_grandmaster_pull", label="Water Grandmaster Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Water", "Grandmaster")
                    else HS.ElementZonePull.stop("Water", "Grandmaster") end
                end},

                {type="label", text="Earth"},
                {type="toggle", key="earth_starter_pull", label="Earth Starter Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Earth", "Starter")
                    else HS.ElementZonePull.stop("Earth", "Starter") end
                end},
                {type="toggle", key="earth_advanced_pull", label="Earth Advanced Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Earth", "Advanced")
                    else HS.ElementZonePull.stop("Earth", "Advanced") end
                end},
                {type="toggle", key="earth_master_pull", label="Earth Master Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Earth", "Master")
                    else HS.ElementZonePull.stop("Earth", "Master") end
                end},
               {type="toggle", key="earth_grandmaster_pull", label="Earth Grandmaster Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Earth", "Grandmaster")
                    else HS.ElementZonePull.stop("Earth", "Grandmaster") end
                end},   
                
                {type="label", text="Plasma"},
                {type="toggle", key="plasma_starter_pull", label="Plasma Starter Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Plasma", "Starter")
                    else HS.ElementZonePull.stop("Plasma", "Starter") end
                end},
                {type="toggle", key="plasma_advanced_pull", label="Plasma Advanced Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Plasma", "Advanced")
                    else HS.ElementZonePull.stop("Plasma", "Advanced") end
                end},
                {type="toggle", key="plasma_master_pull", label="Plasma Master Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Plasma", "Master")
                    else HS.ElementZonePull.stop("Plasma", "Master") end
                end},
               {type="toggle", key="plasma_grandmaster_pull", label="Plasma Grandmaster Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Plasma", "Grandmaster")
                    else HS.ElementZonePull.stop("Plasma", "Grandmaster") end
                end},

            },
        },
        upgrades = {
            title = "auto purchase",
            items = {
                {type="toggle", key="saber",   label="Saber",       callback=function(on) if on then HS.Farming.startSaber()   end end},
                {type="toggle", key="dna",     label="DNA",         callback=function(on) if on then HS.Farming.startDNA()     end end},
                {type="toggle", key="class",   label="Class",       callback=function(on) if on then HS.Farming.startClass()   end end},
                {type="toggle", key="bossdmg", label="Boss Damage", callback=function(on) if on then HS.Farming.startBossDmg() end end},
                {type="toggle", key="aura",    label="Aura",        callback=function(on) if on then HS.Farming.startAura()    end end},
                {type="toggle", key="petaura", label="Pet Aura",    callback=function(on) if on then HS.Farming.startPetAura() end end},
            },
        },
        clan = {
            title = "clan automation",
            items = {
                {type="toggle", key="clanquest", label="Claim Quests",
                    callback=function(on) if on then HS.Farming.startClanQuest() end end},
                {type="toggle", key="clan_auto_quests", label="Clan Auto Quests Completion",
                    callback=function(on)
                        if on then HS.Farming.startClanAutoQuests()
                        else HS.Farming.stopClanAutoQuests() end
                    end},
                {type="status", bind="clan_auto", text="waiting: idle"},
                {type="note", text="Leave Auto Swing enabled for Swing Saber quests."},
                {type="label", text="dungeon missions"},
                {type="toggle", key="clan_dungeon_impossible", label="Always do Impossible", callback=function() end},
                {type="toggle", key="farm_dungeon", label="Farm Dungeon",
                    callback=function(on)
                        if on then HS.Dungeon.startFarm()
                        else
                            if HS.Dungeon.hoverConnection then HS.Dungeon.hoverConnection:Disconnect(); HS.Dungeon.hoverConnection = nil end
                            HS.Dungeon.currentTarget = nil
                        end
                    end},
                {type="slider", key="dungeon_height", label="Dungeon Height", min=6, max=16, default=7,
                    getValue=function() return HS.Dungeon.HEIGHT end,
                    callback=function(val) HS.Dungeon.HEIGHT = math.clamp(val, 6, 16) end},
                {type="toggle", key="farm_chest", label="Claim Chest",
                    callback=function(on)
                        if on then HS.Dungeon.claimChest()
                        else HS.Dungeon.chestThread = nil end
                    end},
                {type="toggle", key="farm_egg", label="Equip Best Egg", callback=function() end},
                {type="incubator_slots"},
                {type="toggle", key="claim_egg", label="Claim Eggs",
                    callback=function(on) if on then HS.Dungeon.startClaimEggs() end end},
                {type="toggle", key="avoid_sun", label="Avoid Sun", compact=true, callback=function() end},
                {type="label", text="flag capture missions"},
                {type="toggle", key="clan_flag_avoid", label="Avoid Players", callback=function() end},
                {type="toggle", key="clan_flag_ignore", label="Ignore Flag Missions", callback=function() end},
                {type="label", text="king missions"},
                {type="toggle", key="clan_koth_avoid", label="Avoid Players", callback=function() end},
                {type="toggle", key="clan_koth_ignore", label="Ignore KOTH Missions", callback=function() end},
                {type="label", text="element mob missions"},
                {type="selection", key="clan_element", label="Element", options={"Fire","Water","Earth","Plasma"}, default="Fire", instant=true},
                {type="label", text="egg opening missions"},
                {type="selection", key="clan_egg_mode", label="Egg Mode", options={"Best Egg","Cheap Egg","Petdex"}, default="Best Egg", instant=true},
                {type="label",      text="active quests"},
                {type="quest",      questIdx=1},
                {type="quest",      questIdx=2},
                {type="quest",      questIdx=3},
            },
        },
        areas = {
            title = "areas",
            items = (function()
                local t = {}
                for _, area in ipairs(Core.AREAS) do
                    if area.isLabel then
                        table.insert(t, {type="label", text=area.label})
                    else
                        local capturedPos = area.pos
                        table.insert(t, {type="teleport", label=area.label, callback=function() HS.Farming.teleportTo(capturedPos) end})
                    end
                end
                return t
            end)(),
        },
        pets = {
            title = "Hatchery & Petdex",
            items = {
                {type="toggle", key="auto_egg_opener", label="Auto Egg Opener",
                    callback=function(on)
                        if on then HS.EggOpener.start() else HS.EggOpener.stop() end
                    end},
                {type="slider", key="egg_opener_page", label="Egg Page", min=1, max=50, default=1,
                    callback=function()
                        if HS.EggOpener.initialized or HS.EggOpener.statusLabel then
                            HS.EggOpener.init()
                            HS.EggOpener.updateSelection()
                        end
                    end},
                {type="slider", key="egg_opener_slot", label="Egg Slot", min=1, max=12, default=1,
                    callback=function()
                        if HS.EggOpener.initialized or HS.EggOpener.statusLabel then
                            HS.EggOpener.init()
                            HS.EggOpener.updateSelection()
                        end
                    end},
                {type="eggopener_status"},

                {type="label", text="Quality of Life"},
                {type="toggle", key="auto_craft_pets", label="Auto Craft Pets",
                    callback=function(on)
                        if on then HS.Pets.startAutoCraft() else HS.Pets.stopAutoCraft() end
                    end},
                {type="toggle", key="auto_craft_allow_equipped", label="Allow Equipped Pets", compact=true, callback=function() end},
                {type="status", bind="auto_craft_pets", text="Auto Craft: waiting"},
                {type="toggle", key="hide_egg_animations", label="Hide egg animations", default=false,
                    callback=function(on) HS.Misc.applyHideEggAnimations(on) end},
                {type="toggle", key="petdex_auto_teleport", label="Auto Teleport",
                    callback=function(on)
                        if on then HS.PetdexFarm.startTeleport() else HS.PetdexFarm.stopTeleport() end
                    end},
                    
                {type="label", text="Petdex"},
                {type="toggle", key="auto_petdex_rewards", label="Auto Claim Petdex Rewards",
                    callback=function(on)
                        if on then HS.PetdexRewards.start() else HS.PetdexRewards.stop() end
                    end},
                {type="petdex_rewards_status"},
                {type="toggle", key="auto_petdex", label="Auto Petdex",
                    callback=function(on)
                        if on then HS.PetdexFarm.start() else HS.PetdexFarm.stop() end
                    end},
                {type="slider", key="petdex_skip", label="Petdex Skip", min=0, max=10, default=0,
                    callback=function()
                        if HS.PetdexFarm.initialized or HS.PetdexFarm.progressLabel then HS.PetdexFarm.refreshProgress() end
                    end},
                {type="toggle", key="petdex_ignore_secrets", label="Ignore Secrets", default=true,
                    callback=function()
                        if HS.PetdexFarm.initialized or HS.PetdexFarm.progressLabel then HS.PetdexFarm.refreshProgress() end
                    end},
                {type="petdex_progress"},
            },
        },
        logs = {
            title = "Logs",
            items = {
                {type="label", text="Discord Monitor"},
                {type="toggle", key=HS.Logs.DiscordMonitor.STATE_KEY, label="Enable Discord Monitor",
                    callback=function(on) HS.Logs.DiscordMonitor.setEnabled(on) end},
                {type="label", text="Discord Monitor Settings"},
                {type="input", key=HS.Logs.DiscordMonitor.URL_KEY, label="Discord Monitor Webhook URL", default="",
                    placeholder="https://discord.com/api/webhooks/...",
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="input", key=HS.Logs.DiscordMonitor.INTERVAL_KEY, label="Update Interval (seconds)", default="10",
                    placeholder="10",
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_ELEMENT_LEVELS_KEY, label="Show Element Levels", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_MASTERY_LEVELS_KEY, label="Show Mastery Levels", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_DUNGEON_EGGS_KEY, label="Show Dungeon Egg Timers", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_SESSION_STATS_KEY, label="Show Session Stats", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_CONNECTION_STATS_KEY, label="Show Connection Stats", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="label", text="Pets"},
                {type="toggle", key=HS.Logs.Pets.STATE_KEY, label="Pet Hatch Webhook",
                    callback=function(on) HS.Logs.Pets.setEnabled(on) end},
                {type="input", key=HS.Logs.Pets.URL_KEY, label="Webhook URL", default="",
                    placeholder="https://discord.com/api/webhooks/...",
                    callback=function() HS.Logs.Pets.syncConnection() end},
                {type="label", text="Rarity Filters"},
                {type="toggle", key="pet_webhook_1star", label="1 Star", callback=function() end},
                {type="toggle", key="pet_webhook_2star", label="2 Star", callback=function() end},
                {type="toggle", key="pet_webhook_3star", label="3 Star", callback=function() end},
                {type="toggle", key="pet_webhook_4star", label="4 Star", callback=function() end},
                {type="toggle", key="pet_webhook_5star", label="5 Star", callback=function() end},
                {type="toggle", key="pet_webhook_1moon", label="1 Moon", callback=function() end},
                {type="toggle", key="pet_webhook_2moon", label="2 Moon", callback=function() end},
                {type="toggle", key="pet_webhook_3moon", label="3 Moon", callback=function() end},
                {type="toggle", key="pet_webhook_secret", label="Secret", callback=function() end},
                {type="label", text="Dungeon"},
                {type="toggle", key=HS.Logs.Dungeon.STATE_KEY, label="Dungeon Egg Timers",
                    callback=function(on) HS.Logs.Dungeon.setEnabled(on) end},
                {type="dungeon_egg_timer_logs"},
            },
        },
        merchant = {
            title = "Auto Merchant",
            items = HS.Merchant.getUiItems(),
        },
        Dungeon = {
            title = "Setup & Farming",
            items = {
                {type="toggle", key="start_dungeon", label="Auto Start Dungeon", showTimer=true,
                    callback=function(on)
                        if on then HS.Dungeon.startTimer(); HS.Dungeon.tryAutoStart()
                        else HS.Dungeon.resetAutoStartDebounce("toggle disabled") end
                    end},
                {type="selection", key="dungeon_type",       label="Dungeon Type", options={"Space"}, default="Space", instant=true},
                {type="selection", key="dungeon_difficulty",  label="Difficulty",   options={"Easy","Medium","Hard","Impossible"}, default="Easy", instant=true},
                {type="selection", key="dungeon_privacy",     label="Privacy",      options={"Public","Friends","Private"}, default="Public", instant=true},
                {type="label", text="Farming"},
                {type="toggle", key="farm_dungeon", label="Farm Dungeon",
                    callback=function(on)
                        if on then HS.Dungeon.startFarm()
                        else
                            if HS.Dungeon.hoverConnection then HS.Dungeon.hoverConnection:Disconnect(); HS.Dungeon.hoverConnection = nil end
                            HS.Dungeon.currentTarget = nil
                        end
                    end},
                {type="slider", key="dungeon_height", label="Dungeon Height", min=6, max=16, default=7,
                    getValue=function() return HS.Dungeon.HEIGHT end,
                    callback=function(val) HS.Dungeon.HEIGHT = math.clamp(val, 6, 16) end},
                {type="toggle", key="farm_chest", label="Claim Chest",
                    callback=function(on)
                        if on then HS.Dungeon.claimChest()
                        else HS.Dungeon.chestThread = nil end
                    end},
                {type="toggle", key="farm_egg", label="Equip Best Egg", callback=function() end},
                {type="incubator_slots"},
                {type="toggle", key="claim_egg", label="Claim Eggs",
                    callback=function(on) if on then HS.Dungeon.startClaimEggs() end end},
                {type="toggle", key="avoid_sun", label="Avoid Sun", compact=true, callback=function() end},
                {type="label", text="Upgrades"},
                {type="toggle", key="dungeon_DungeonCoins",      label="Dungeon Coins",  callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonCoins")()      end end},
                {type="toggle", key="dungeon_DungeonCritChance", label="Crit Chance",    callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonCritChance")()  end end},
                {type="toggle", key="dungeon_DungeonCrowns",     label="Dungeon Crowns", callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonCrowns")()     end end},
                {type="toggle", key="dungeon_DungeonDamage",     label="Dungeon Damage", callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonDamage")()     end end},
                {type="toggle", key="dungeon_DungeonEggSlots",   label="Egg Slots",      callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonEggSlots")()   end end},
                {type="toggle", key="dungeon_DungeonHealth",     label="Dungeon Health", callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonHealth")()     end end},
                {type="toggle", key="dungeon_DungeonSprint",     label="Dungeon Sprint", callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonSprint")()     end end},
                {type="toggle", key="dungeon_IncubatorSpeed",    label="Incubator Speed",callback=function(on) if on then HS.Dungeon.startUpgrade("IncubatorSpeed")()    end end},
            },
        },
    }

    UI.TAB_ORDER = {
        {key="farming",  label="FARMING"},
        {key="upgrades", label="UPGRADES"},
        {separator=true},
        {key="elements", label="ELEMENTS"},
        {key="areas",    label="AREAS"},
        {separator=true},
        {key="clan",     label="CLAN"},
        {key="pets",     label="PETS"},
        {key="Dungeon",  label="DUNGEON"},
        {key="merchant", label="MERCHANT"},
        {key="logs",     label="☀ LOGS"},
        {separator=true},
        {key="misc",     label="MISC"},
        {key="session",  label="SESSION"},
        {key="standalone_scripts", label="STANDALONE", testingOnly=true},
    }

    -- ── Build state from UI_DATA ─────────────────────────────────
    HS.Session.applyUiDefaults()

    -- ── Root GUIs ────────────────────────────────────────────────
    local savedSession = HS.Session.load()
    if type(savedSession) == "table" then
        local savedConfig = type(savedSession.config) == "table" and savedSession.config
            or type(savedSession.Config) == "table" and savedSession.Config
            or {}
        local savedToggles = type(savedSession.state) == "table" and savedSession.state
            or type(savedSession.toggles) == "table" and savedSession.toggles
            or {}
        local savedSelections = type(savedSession.selectionState) == "table" and savedSession.selectionState
            or type(savedSession.selections) == "table" and savedSession.selections
            or {}
        local savedSliders = type(savedSession.sliderState) == "table" and savedSession.sliderState
            or type(savedSession.sliders) == "table" and savedSession.sliders
            or {}
        local savedInputs = type(savedSession.inputState) == "table" and savedSession.inputState
            or type(savedSession.inputs) == "table" and savedSession.inputs
            or {}
        local savedLogs = type(savedSession.Logs) == "table" and savedSession.Logs
            or type(savedSession.logs) == "table" and savedSession.logs
            or type(savedConfig.Logs) == "table" and savedConfig.Logs
            or type(savedConfig.logs) == "table" and savedConfig.logs
            or nil

        local function mergeSavedConfig(target, saved)
            if type(target) ~= "table" or type(saved) ~= "table" then return end
            for key, value in pairs(saved) do
                if type(key) == "string" then
                    if type(value) == "table" then
                        if type(target[key]) ~= "table" then
                            target[key] = {}
                        end
                        mergeSavedConfig(target[key], value)
                    else
                        target[key] = value
                    end
                end
            end
        end

        if savedSliders.petdex_skip == nil and savedSliders.petdex_target ~= nil then
            savedSliders.petdex_skip = math.clamp(10 - (tonumber(savedSliders.petdex_target) or 10), 0, 10)
        end

        local function countStringKeys(tbl)
            local count = 0
            if type(tbl) == "table" then
                for key in pairs(tbl) do
                    if type(key) == "string" then
                        count += 1
                    end
                end
            end
            return count
        end

        local function logRestoreCount(label, savedTable, restoredCount)
            Core.debugLog(
                "Session restore " .. label .. " keys count:",
                "saved=", countStringKeys(savedTable),
                "restored=", restoredCount
            )
        end

        local restoredToggles = 0
        if type(savedToggles) == "table" then
            for key, value in pairs(savedToggles) do
                if type(key) == "string" and type(value) == "boolean" then
                    Core.state[key] = value
                    restoredToggles += 1
                end
            end
        end
        logRestoreCount("toggle", savedToggles, restoredToggles)

        local restoredInputs = 0
        if type(savedInputs) == "table" then
            for key, value in pairs(savedInputs) do
                if type(key) == "string" and value ~= nil then
                    Core.inputState[key] = tostring(value)
                    restoredInputs += 1
                end
            end
        end
        logRestoreCount("input", savedInputs, restoredInputs)

        local restoredSliders = 0
        if type(savedSliders) == "table" then
            for key, value in pairs(savedSliders) do
                local numberValue = tonumber(value)
                if type(key) == "string" and numberValue ~= nil then
                    Core.sliderState[key] = numberValue
                    restoredSliders += 1
                end
            end
        end
        logRestoreCount("slider", savedSliders, restoredSliders)

        local restoredSelections = 0
        if type(savedSelections) == "table" then
            for key, value in pairs(savedSelections) do
                if type(key) == "string" and value ~= nil then
                    Core.selectionState[key] = tostring(value)
                    restoredSelections += 1
                end
            end
        end
        logRestoreCount("selection", savedSelections, restoredSelections)

        for _, tabData in pairs(UI.UI_DATA) do
            for _, item in ipairs(tabData.items) do
                if item.type == "slider" and item.key then
                    local minVal = item.min or 0
                    local maxVal = item.max or minVal
                    local fallback = item.default ~= nil and item.default or minVal
                    local value = tonumber(Core.sliderState[item.key])
                    if value == nil then value = tonumber(fallback) or minVal end
                    Core.sliderState[item.key] = math.clamp(value, minVal, maxVal)
                elseif item.type == "selection" and item.key then
                    local value = Core.selectionState[item.key]
                    if value ~= nil then
                        value = tostring(value)
                        if type(item.options) == "table" and #item.options > 0 and not table.find(item.options, value) then
                            Core.selectionState[item.key] = item.default or item.options[1]
                        else
                            Core.selectionState[item.key] = value
                        end
                    end
                end
            end
        end

        if type(savedConfig) == "table" then
            Core.config = Core.config or {}
            mergeSavedConfig(Core.config, savedConfig)
        end

        if Core.applyLogsConfig then
            Core.applyLogsConfig(savedLogs)
        end

        Core.debugLog(
            "Session load restored state keys count:", HS.Session.countKeys(Core.state),
            "input keys count:", HS.Session.countKeys(Core.inputState),
            "slider keys count:", HS.Session.countKeys(Core.sliderState),
            "selection keys count:", HS.Session.countKeys(Core.selectionState)
        )
    end

    HS.Dungeon.installRegionLoadedHook()
    HS.Dungeon.startPresenceWatchdog()

    for _, tabData in pairs(UI.UI_DATA) do
        for _, item in ipairs(tabData.items) do
            if item.type == "slider" and item.key and item.callback then
                item.callback(Core.sliderState[item.key])
            elseif item.type == "selection" and item.key and item.instant and item.callback then
                item.callback(Core.selectionState[item.key])
            end
        end
    end

    for key, on in pairs(Core.state) do
        local cb = Core.callbacks[key]
        if on and cb then task.spawn(cb, true) end
    end

    local gui = UI.make("ScreenGui", {Name="HeartsteelUI", ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, Parent=Core.playerGui})
    local toggleGui = UI.make("ScreenGui", {Name="HeartsteelToggleGui", ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, Parent=Core.playerGui})

    -- ── Floating toggle button ───────────────────────────────────
    local toggleButton = UI.make("ImageButton", {Parent=toggleGui, Name="ToggleButton", Size=UDim2.fromOffset(64,64), Position=UDim2.new(0,24,0.5,-32), BackgroundTransparency=1, AutoButtonColor=false, ZIndex=50})
    pcall(function()
        local iconFile = "heartsteel_toggle_icon.png"
        if not isfile(iconFile) then
            writefile(iconFile, game:HttpGet("https://raw.githubusercontent.com/Lucas-BIIks/test/refs/heads/main/image.png"))
        end
        toggleButton.Image = getcustomasset(iconFile)
    end)
    toggleButton.ScaleType = Enum.ScaleType.Crop
    UI.addCorner(toggleButton, 999)
    local buttonStroke = UI.make("UIStroke", {Parent=toggleButton, ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Thickness=2, Color=Core.C.orange, Transparency=0.15})
    UI.make("UIGradient", {Parent=buttonStroke, Rotation=35, Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Core.C.purple), ColorSequenceKeypoint.new(1,Core.C.orange)})})
    local glow = UI.make("Frame", {Name="Glow", Parent=toggleButton, BackgroundColor3=Core.C.purple, BackgroundTransparency=0.82, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.fromOffset(88,88), ZIndex=49})
    UI.addCorner(glow, 999)
    UI.make("UIGradient", {Parent=glow, Rotation=35, Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Core.C.purple), ColorSequenceKeypoint.new(1,Core.C.orange)})})
    local ring = UI.make("Frame", {Parent=toggleButton, Name="Ring", AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.fromScale(1,1), BackgroundTransparency=1, ZIndex=48})
    UI.addCorner(ring, 999)
    local ringStroke = UI.make("UIStroke", {Parent=ring, Thickness=3, Color=Core.C.purple, Transparency=0.75})
    local function tw(obj, props) return S.TweenService:Create(obj, TweenInfo.new(0.18), props) end
    local hIGlow=tw(glow,{BackgroundTransparency=0.62,Size=UDim2.fromOffset(100,100)}); local hOGlow=tw(glow,{BackgroundTransparency=0.82,Size=UDim2.fromOffset(88,88)})
    local hIStroke=tw(buttonStroke,{Thickness=3,Transparency=0}); local hOStroke=tw(buttonStroke,{Thickness=2,Transparency=0.15})
    local hIRing=tw(ringStroke,{Transparency=0.45}); local hORing=tw(ringStroke,{Transparency=0.75})
    toggleButton.MouseEnter:Connect(function() hIGlow:Play(); hIStroke:Play(); hIRing:Play() end)
    toggleButton.MouseLeave:Connect(function() hOGlow:Play(); hOStroke:Play(); hORing:Play() end)

    -- ── Main window ──────────────────────────────────────────────
    local main = UI.make("Frame", {Name="Main", Parent=gui, Size=UDim2.fromOffset(440,370), Position=UDim2.new(0.5,-220,0.5,-185), BackgroundColor3=C.window, BorderSizePixel=0})
    UI.addCorner(main, 4); UI.addStroke(main, C.border2, 1)
    local topbar = UI.make("Frame", {Name="Topbar", Parent=main, Size=UDim2.new(1,0,0,40), BackgroundColor3=C.topbar, BorderSizePixel=0})
    UI.addStroke(topbar, C.border, 1)
    local diamond = UI.make("Frame", {Parent=topbar, Size=UDim2.fromOffset(18,18), Position=UDim2.new(0,12,0.5,-9), BackgroundColor3=C.purple, Rotation=45, BorderSizePixel=0})
    UI.addCorner(diamond, 2)
    UI.make("Frame", {Parent=diamond, Size=UDim2.new(1,-6,1,-6), Position=UDim2.new(0,3,0,3), BackgroundColor3=C.window, BorderSizePixel=0})
    UI.make("TextLabel", {Parent=topbar, BackgroundTransparency=1, Position=UDim2.new(0,34,0,4), Size=UDim2.new(0,180,0,16), Text="HEARTSTEEL", Font=Enum.Font.Garamond, TextSize=17, TextColor3=C.purple, TextXAlignment=Enum.TextXAlignment.Left})
    UI.make("TextLabel", {Parent=topbar, BackgroundTransparency=1, Position=UDim2.new(0,34,0,20), Size=UDim2.new(0,180,0,14), Text="saber simulator · v3.0", Font=Enum.Font.Gotham, TextSize=10, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left})
    local mainLayout = UI.make("Frame", {Name="MainLayout", Parent=main, Position=UDim2.fromOffset(0,40), Size=UDim2.new(1,0,1,-78), BackgroundTransparency=1})
    sidebar = UI.make("ScrollingFrame", {Parent=mainLayout, Size=UDim2.new(0,110,1,0), BackgroundColor3=C.sidebar, BorderSizePixel=0, CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=3, ScrollBarImageColor3=C.border2})
    UI.addStroke(sidebar, C.border, 1)
    UI.make("UIListLayout", {Parent=sidebar, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,0)})
    UI.make("UIPadding", {Parent=sidebar, PaddingTop=UDim.new(0,8)})
    content = UI.make("ScrollingFrame", {Name="Content", Parent=mainLayout, Position=UDim2.fromOffset(110,0), Size=UDim2.new(1,-110,1,0), BackgroundColor3=C.window, BorderSizePixel=0, CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=3, ScrollBarImageColor3=C.border2})
    UI.make("UIPadding", {Parent=content, PaddingTop=UDim.new(0,12), PaddingLeft=UDim.new(0,12), PaddingRight=UDim.new(0,12), PaddingBottom=UDim.new(0,12)})
    UI.make("UIListLayout", {Parent=content, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,2)})
    local footer = UI.make("Frame", {Parent=main, Size=UDim2.new(1,0,0,38), Position=UDim2.new(0,0,1,-38), BackgroundColor3=C.sidebar, BorderSizePixel=0})
    UI.addStroke(footer, C.border, 1)
    UI.statusDot = UI.make("Frame", {Parent=footer, Size=UDim2.fromOffset(5,5), Position=UDim2.new(0,12,0.5,-2), BackgroundColor3=C.border2, BorderSizePixel=0})
    UI.addCorner(UI.statusDot, 999)
    UI.statusText = UI.make("TextLabel", {Parent=footer, BackgroundTransparency=1, Position=UDim2.new(0,24,0,0), Size=UDim2.new(1,-140,1,0), Text="idle", Font=Enum.Font.Garamond, TextSize=12, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left})
    local allOffBtn = UI.make("TextButton", {Parent=footer, Size=UDim2.fromOffset(62,22), Position=UDim2.new(1,-128,0.5,-11), BackgroundTransparency=1, Text="ALL OFF", TextColor3=C.textDim, Font=Enum.Font.GothamBold, TextSize=10})
    UI.addCorner(allOffBtn, 2); UI.addStroke(allOffBtn, C.border, 1)
    local killBtn = UI.make("TextButton", {Parent=footer, Size=UDim2.fromOffset(52,22), Position=UDim2.new(1,-60,0.5,-11), BackgroundColor3=C.redDark, Text="KILL", TextColor3=C.red, Font=Enum.Font.GothamBold, TextSize=10})
    UI.addCorner(killBtn, 2); UI.addStroke(killBtn, Color3.fromRGB(80,24,24), 1)

    -- ── Sidebar nav ───────────────────────────────────────────────
    UI.renderSidebar()

    -- ── Button events ─────────────────────────────────────────────
    allOffBtn.MouseButton1Click:Connect(function() UI.allOff(); UI.renderContent() end)
    killBtn.MouseButton1Click:Connect(function()
        HS.Session.suppressSave = true
        Core.alive = false; UI.allOff(true); task.wait(1.5); gui:Destroy(); toggleGui:Destroy()
    end)
    toggleButton.MouseButton1Click:Connect(function() Core.uiOpen = not Core.uiOpen; main.Visible = Core.uiOpen end)

    -- ── Drag: main window ─────────────────────────────────────────
    do
        local dragging, dragStart, startPos = false, nil, nil
        topbar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging=true; dragStart=input.Position; startPos=main.Position
                input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging=false end end)
            end
        end)
        S.UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - dragStart
                main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
            end
        end)
    end

    -- ── Drag: floating button ──────────────────────────────────────
    do
        local dragging, dragStart, startPos = false, nil, nil
        toggleButton.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging=true; dragStart=input.Position; startPos=toggleButton.Position
                input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging=false end end)
            end
        end)
        S.UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - dragStart
                toggleButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
            end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- REMOTE LISTENERS
-- ══════════════════════════════════════════════════════════════════
local Core = HS.Core

Core.ClientNotifierRemote.OnClientEvent:Connect(function(eventName, rewards)
    if eventName == "DungeonReward" and typeof(rewards) == "table" then
        local handledEggReward = false
        if HS.Dungeon and HS.Dungeon.markRunEnding then
            HS.Dungeon.markRunActive("reward received")
            HS.Dungeon.markRunEnding("reward received")
        end
        for _, reward in ipairs(rewards) do
            if typeof(reward) == "table" and reward.Type == "DungeonEgg" then
                handledEggReward = true
                task.spawn(function()
                    local ok, err = pcall(HS.Dungeon.handleEggReward, reward.Name or "Unknown Egg")
                    if not ok then
                        Core.debugLog("Dungeon egg reward handler failed:", err)
                    end
                    if HS.Dungeon and HS.Dungeon.markRunEnded then
                        HS.Dungeon.markRunEnded("egg reward handled")
                    end
                end)
                break
            end
        end
        if not handledEggReward and HS.Dungeon and HS.Dungeon.scheduleRunEnd then
            HS.Dungeon.scheduleRunEnd(5, "post reward grace")
        end
    elseif eventName == "PopupText" then
        local rewardsStr = tostring(rewards or "")
        if rewardsStr:find("Clan XP") then
            Core.debugLog("Clan XP gained:", rewardsStr)
            task.delay(0.15, HS.Farming.refreshClanQuestInfo)
        end
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- INIT
-- ══════════════════════════════════════════════════════════════════

HS.Misc.startAntiAfk()
HS.UI.renderContent()
HS.Logs.Pets.syncConnection()
HS.Logs.DiscordMonitor.sync()
HS.Misc.applyHideEggAnimations(Core.state.hide_egg_animations == true)

-- Load all hidden regions on startup
task.spawn(function()
    local hidden        = S.ReplicatedStorage:WaitForChild("HiddenRegions")
    local gameplay      = workspace:WaitForChild("Gameplay")
    local regionsLoaded = gameplay:WaitForChild("RegionsLoaded")

    local function moveAllToLoaded()
        for _, region in ipairs(hidden:GetChildren()) do
            Core.debugLog("Moving region to RegionsLoaded:", region.Name)
            region.Parent = regionsLoaded
        end
    end

    moveAllToLoaded()

    task.wait(0.5)
    -- No startup Grandmaster preload teleport. Keep startup passive so dungeon
    -- runs and restored sessions cannot be interrupted by a forced world TP.

    hidden.ChildAdded:Connect(function(region)
        Core.debugLog("Region returned to HiddenRegions, re-parenting:", region.Name)
        task.wait(0.1); region.Parent = regionsLoaded
    end)
end)

task.spawn(function()
    task.wait(0.2)
    HS.Dungeon.openIncubatorMenu(true)
    if Core.activeTab == "Dungeon" then HS.UI.renderContent() end
end)
task.spawn(function() task.wait(2); HS.UI.refreshQuestTitles() end)
task.spawn(function() task.wait(3); HS.Farming.refreshClanQuestInfo() end)
