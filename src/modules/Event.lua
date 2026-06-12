return function(HS, S)
    local Event = HS.Event or {}
    HS.Event = Event

    local Core = HS.Core

    Event.CURRENT_EVENT_KEY = "Summer26"
    Event.CURRENT_EVENT_CURRENCY_NAME = "Seashells"
    Event.EVENT_MERCHANT_BUY_ACTION = "EventMerchantBuyItem"
    Event.EVENT_UPGRADE_BUY_ACTION = "BuyEventUpgrade"

    Event.moduleCache = Event.moduleCache or {}

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
        local listingCount = countEntries(Event.getEventMerchantListings())
        local bossHRP = Event.getEventBossHRP()
        local pickupRemote = Event.getCollectCurrencyPickupRemote()

        return table.concat({
            "Current Event: " .. tostring(Event.CURRENT_EVENT_KEY),
            "Currency: " .. tostring(currencyName),
            "EventsInfo: " .. (eventInfo and "found" or "missing"),
            "Merchant Listings: " .. (listingCount and tostring(listingCount) or "missing"),
            "Boss HRP: " .. (bossHRP and "found" or "missing"),
            "Pickup Remote: " .. (pickupRemote and "found" or "missing"),
            "Event Wheel: disabled",
        }, "\n")
    end
end
