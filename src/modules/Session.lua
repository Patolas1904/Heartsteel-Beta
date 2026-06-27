return function(HS, S)
    local Session = HS.Session or {}
    HS.Session = Session
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
        if HS.Dungeon and HS.Dungeon.clearCooldownTimer then
            pcall(HS.Dungeon.clearCooldownTimer, "session reset", true)
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
            "has Logs config:", tostring(type(data.Logs) == "table" or (type(data.config) == "table" and type(data.config.Logs) == "table")),
            "has Dungeon cooldown:", tostring(type(data.Dungeon) == "table")
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
            Dungeon = HS.Dungeon and HS.Dungeon.getSessionState and HS.Dungeon.getSessionState() or nil,
        }
        Core.debugLog(
            "Session save path:", Session.FILE_NAME,
            "state keys count:", Session.countKeys(Core.state),
            "input keys count:", Session.countKeys(Core.inputState),
            "slider keys count:", Session.countKeys(Core.sliderState),
            "selection keys count:", Session.countKeys(Core.selectionState),
            "has Logs config:", tostring(type(data.Logs) == "table"),
            "has Dungeon cooldown:", tostring(type(data.Dungeon) == "table")
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
