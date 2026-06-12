return function(HS, S)
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
