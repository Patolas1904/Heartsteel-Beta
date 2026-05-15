return function(HS, S)
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
