return function(HS, S)
    local Event = HS.Event or {}
    HS.Event = Event

    local Core = HS.Core

    Event.CURRENT_EVENT_KEY = "Summer26"
    Event.CURRENT_EVENT_CURRENCY_NAME = "Seashells"
    Event.EVENT_MERCHANT_BUY_ACTION = "EventMerchantBuyItem"
    Event.EVENT_UPGRADE_BUY_ACTION = "BuyEventUpgrade"
    Event.CURRENCY_PICKUP_STATE_KEY = "event_currency_pickup"
    Event.CURRENCY_PICKUP_DELAY = 0.05

    Event.moduleCache = Event.moduleCache or {}
    Event.currencyPickupConnection = Event.currencyPickupConnection or nil
    Event.currencyPickupStarting = Event.currencyPickupStarting or false

    local function getModulesFolder()
        local replicatedStorage = S.ReplicatedStorage
        return replicatedStorage and replicatedStorage:FindFirstChild("Modules") or nil
    end

    local function requireModule(moduleName)
        if Event.moduleCache[moduleName] ~= nil then
            return Event.moduleCache[moduleName]
        end

        local modules = getModulesFolder()
        local moduleScript = modules and modules:FindFirstChild(moduleName)
        if not moduleScript then return nil end

        local ok, result = pcall(require, moduleScript)
        if not ok then
            if Core and Core.debugLog then
                Core.debugLog("Event module require failed:", moduleName, tostring(result))
            end
            return nil
        end

        Event.moduleCache[moduleName] = result
        return result
    end

    function Event.getEventsInfo()
        return requireModule("EventsInfo")
    end

    function Event.getEventMerchantInfo()
        return requireModule("EventMerchantInfo")
    end

    function Event.getCurrentEventInfo()
        local eventsInfo = Event.getEventsInfo()
        local events = type(eventsInfo) == "table" and eventsInfo.Events or nil
        return type(events) == "table" and events[Event.CURRENT_EVENT_KEY] or nil
    end

    function Event.getCurrentEventCurrencyName()
        local info = Event.getCurrentEventInfo()
        if type(info) == "table" then
            local currencyName = info.CurrencyName or info.Currency or info.CurrencyType
            if type(currencyName) == "string" and currencyName ~= "" then
                return currencyName
            end
        end
        return Event.CURRENT_EVENT_CURRENCY_NAME
    end

    function Event.getEventMerchantListings()
        local merchantInfo = Event.getEventMerchantInfo()
        local listings = type(merchantInfo) == "table" and merchantInfo.Listings or nil
        return type(listings) == "table" and listings or nil
    end

    function Event.getEventBossHRP()
        local gameplay = workspace:FindFirstChild("Gameplay")
        local regionsLoaded = gameplay and gameplay:FindFirstChild("RegionsLoaded")
        local summerEvent = regionsLoaded and regionsLoaded:FindFirstChild("SummerEvent26")
        local bossRoot = summerEvent and summerEvent:FindFirstChild("Boss")
        local bossHolder = bossRoot and bossRoot:FindFirstChild("BossHolder")
        local boss = bossHolder and bossHolder:FindFirstChild("Boss")
        return boss and boss:FindFirstChild("HumanoidRootPart") or nil
    end

    function Event.getCollectCurrencyPickupRemote()
        if Core and Core.CollectCurrencyRemote then return Core.CollectCurrencyRemote end

        local events = S.ReplicatedStorage and S.ReplicatedStorage:FindFirstChild("Events")
        return events and events:FindFirstChild("CollectCurrencyPickup") or nil
    end

    local function findAmountLabel(root)
        local mainGui = root and root:FindFirstChild("MainGui")
        local startFrame = mainGui and mainGui:FindFirstChild("StartFrame")
        local currency = startFrame and startFrame:FindFirstChild("Currency")
        local eventCoins = currency and currency:FindFirstChild("EventCoins")
        return eventCoins and eventCoins:FindFirstChild("Amount") or nil
    end

    function Event.getEventCurrencyAmountLabel()
        local playerGui = Core and (Core.playerGui or (Core.player and Core.player:FindFirstChild("PlayerGui")))
        local liveLabel = findAmountLabel(playerGui)
        if liveLabel then return liveLabel end

        local starterGui = S.StarterGui
        return findAmountLabel(starterGui)
    end

    function Event.getEventCurrencyAmountText()
        local label = Event.getEventCurrencyAmountLabel()
        local text = label and label.Text
        return type(text) == "string" and text or nil
    end

    function Event.getEventCurrencyAmount()
        local text = Event.getEventCurrencyAmountText()
        if not text then return nil end
        return Core and Core.parseCompactNumber and Core.parseCompactNumber(text) or tonumber(text)
    end

    function Event.getCurrencyHolder()
        if Core and Core.CurrencyHolder then return Core.CurrencyHolder end

        local gameplay = workspace:FindFirstChild("Gameplay")
        local currencyPickup = gameplay and gameplay:FindFirstChild("CurrencyPickup")
        return currencyPickup and currencyPickup:FindFirstChild("CurrencyHolder") or nil
    end

    local function containsNeedle(value, needle)
        return type(value) == "string"
            and value ~= ""
            and string.find(string.lower(value), string.lower(needle), 1, true) ~= nil
    end

    local function readAttribute(obj, attributeName)
        local ok, value = pcall(function()
            return obj:GetAttribute(attributeName)
        end)
        return ok and value or nil
    end

    function Event.isEventCurrencyPickup(obj)
        if typeof(obj) ~= "Instance" then return false end

        local holder = Event.getCurrencyHolder()
        if not holder or not obj:IsDescendantOf(holder) then return false end

        local currencyName = Event.getCurrentEventCurrencyName() or Event.CURRENT_EVENT_CURRENCY_NAME
        local eventKey = Event.CURRENT_EVENT_KEY
        local checks = {
            obj.Name,
            tostring(readAttribute(obj, "Currency")),
            tostring(readAttribute(obj, "CurrencyName")),
            tostring(readAttribute(obj, "CurrencyType")),
            tostring(readAttribute(obj, "Type")),
            tostring(readAttribute(obj, "EventCurrency")),
            tostring(readAttribute(obj, "EventName")),
        }

        for _, value in ipairs(checks) do
            if containsNeedle(value, currencyName)
                or containsNeedle(value, eventKey)
                or containsNeedle(value, "EventCoin")
                or containsNeedle(value, "EventCurrency")
            then
                return true
            end
        end

        return false
    end

    function Event.findEventCurrencyPickups()
        local holder = Event.getCurrencyHolder()
        if not holder then return {} end

        local pickups = {}
        for _, obj in ipairs(holder:GetChildren()) do
            if Event.isEventCurrencyPickup(obj) then
                table.insert(pickups, obj)
            end
        end
        return pickups
    end

    function Event.collectCurrencyPickup(obj)
        if not Core or not Core.alive or not Core.state[Event.CURRENCY_PICKUP_STATE_KEY] then return end
        if not Event.isEventCurrencyPickup(obj) then return end

        local remote = Event.getCollectCurrencyPickupRemote()
        if not remote then return end

        pcall(function()
            remote:FireServer(obj)
        end)
    end

    function Event.stopCurrencyPickup()
        Event.currencyPickupStarting = false
        local connection = Event.currencyPickupConnection
        if connection then
            connection:Disconnect()
            Event.currencyPickupConnection = nil
        end
    end

    function Event.startCurrencyPickup()
        if Event.currencyPickupConnection or Event.currencyPickupStarting then return end
        Event.currencyPickupStarting = true

        task.spawn(function()
            local holder = Event.getCurrencyHolder()
            if not holder then
                Event.currencyPickupStarting = false
                return
            end

            for _, obj in ipairs(holder:GetChildren()) do
                if not Core.alive or not Core.state[Event.CURRENCY_PICKUP_STATE_KEY] then
                    Event.currencyPickupStarting = false
                    return
                end
                Event.collectCurrencyPickup(obj)
                task.wait(Event.CURRENCY_PICKUP_DELAY)
            end

            if Event.currencyPickupConnection then
                Event.currencyPickupStarting = false
                return
            end
            Event.currencyPickupConnection = holder.ChildAdded:Connect(function(obj)
                if not Core.alive or not Core.state[Event.CURRENCY_PICKUP_STATE_KEY] then
                    Event.stopCurrencyPickup()
                    return
                end

                task.wait(Event.CURRENCY_PICKUP_DELAY)
                Event.collectCurrencyPickup(obj)
            end)
            Event.currencyPickupStarting = false
        end)
    end

    function Event.getEventMerchantBuyAction()
        return Event.EVENT_MERCHANT_BUY_ACTION
    end

    function Event.getEventUpgradeBuyAction()
        return Event.EVENT_UPGRADE_BUY_ACTION
    end

    function Event.isEventWheelEnabled()
        -- EventWheelInfo exists, but Event Wheel is intentionally disabled until it is live.
        return false
    end

    Event.canUseEventWheel = Event.isEventWheelEnabled

    local function countEntries(tbl)
        if type(tbl) ~= "table" then return nil end

        local ok, length = pcall(function()
            return #tbl
        end)
        if ok and type(length) == "number" and length > 0 then
            return length
        end

        local count = 0
        for _ in pairs(tbl) do
            count += 1
        end
        return count
    end

    function Event.getStatusText()
        local eventInfo = Event.getCurrentEventInfo()
        local currencyName = Event.getCurrentEventCurrencyName() or "Unknown"
        local amountText = Event.getEventCurrencyAmountText()
        local listingCount = countEntries(Event.getEventMerchantListings())
        local bossHRP = Event.getEventBossHRP()
        local pickupRemote = Event.getCollectCurrencyPickupRemote()

        return table.concat({
            "Current Event: " .. tostring(Event.CURRENT_EVENT_KEY),
            "Currency: " .. tostring(currencyName),
            "Amount: " .. (amountText and tostring(amountText) or "unavailable"),
            "EventsInfo: " .. (eventInfo and "found" or "missing"),
            "Merchant Listings: " .. (listingCount and tostring(listingCount) or "missing"),
            "Boss HRP: " .. (bossHRP and "found" or "missing"),
            "Pickup Remote: " .. (pickupRemote and "found" or "missing"),
            "Event Wheel: disabled",
        }, "\n")
    end
end
