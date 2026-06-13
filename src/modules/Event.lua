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
    Event.EVENT_BOSS_STATE_KEY = "event_boss"
    Event.EVENT_BOSS_TP_STATE_KEY = "event_boss_tp"
    Event.EVENT_MERCHANT_STATE_KEY = "event_merchant_enabled"
    Event.EVENT_MERCHANT_BUY_DELAY = 1
    Event.EVENT_MERCHANT_CLICK_DELAY = 0.15
    Event.EVENT_EGG_OPEN_STATE_KEY = "event_egg_auto_open_week1_gl_egg"
    Event.EVENT_EGG_TP_STATE_KEY = "event_egg_auto_tp"
    Event.EVENT_EGG_WEEK1_NAME = "GL Egg"
    Event.EVENT_EGG_HATCH_DELAY = (HS.EggOpener and HS.EggOpener.HATCH_DELAY) or 0.35
    Event.EVENT_EGG_TELEPORT_DELAY = (HS.PetdexFarm and HS.PetdexFarm.TELEPORT_DELAY) or 1.0
    Event.EVENT_EGG_TP_CFRAME = CFrame.new(
        824.292236, 83.591301, 1408.22717,
        -0.983073473, 5.67926506e-08, 0.183211744,
        5.20563184e-08, 1, -3.06610595e-08,
        -0.183211744, -2.06047446e-08, -0.983073473
    )
    Event.EVENT_BOSS_TP_CFRAME = CFrame.new(
        1021.30432, 89.4617004, 1521.46338,
        -0.734982431, -5.48722916e-08, -0.678086162,
        -6.02579533e-08, 1, -1.5608272e-08,
        0.678086162, 2.93882785e-08, -0.734982431
    )
    Event.EVENT_BOSS_FOLLOW_DISTANCE = 14
    Event.EVENT_BOSS_TP_COOLDOWN = 3
    Event.EVENT_UPGRADE_LIST = {
        {type="Luck", key="event_upgrade_Luck", label="Auto Event Egg Luck"},
        {type="EventCoinsMulti", key="event_upgrade_EventCoinsMulti", label="Auto More Seashells"},
        {type="CrownMulti", key="event_upgrade_CrownMulti", label="Auto More Crowns"},
        {type="EventSellMulti", key="event_upgrade_EventSellMulti", label="Auto Event Sell Boost"},
        {type="BossHits", key="event_upgrade_BossHits", label="Auto Event Boss Hits"},
        {type="EventStrengthMulti", key="event_upgrade_EventStrengthMulti", label="Auto Event Strength Boost"},
        {type="EventSecretChance", key="event_upgrade_EventSecretChance", label="Auto Event Secret Luck"},
    }
    Event.EVENT_MERCHANT_FILTERS = {
        {key="event_merchant_buy_4_star", label="Auto Buy Event Merchant 4 Star"},
        {key="event_merchant_buy_5_star", label="Auto Buy Event Merchant 5 Star"},
        {key="event_merchant_buy_single_moon", label="Auto Buy Event Merchant Single Moon"},
        {key="event_merchant_buy_double_moon", label="Auto Buy Event Merchant Double Moon"},
        {key="event_merchant_buy_triple_moon", label="Auto Buy Event Merchant Triple Moon"},
        {key="event_merchant_buy_normal_pets", label="Auto Buy Event Merchant Normal Pets"},
        {key="event_merchant_buy_golden_pets", label="Auto Buy Event Merchant Golden Pets"},
        {key="event_merchant_buy_shiny_pets", label="Auto Buy Event Merchant Shiny Pets"},
        {key="event_merchant_buy_rainbow_pets", label="Auto Buy Event Merchant Rainbow Pets"},
        {key="event_merchant_buy_shiny_charms", label="Auto Buy Event Merchant Shiny Charms"},
        {key="event_merchant_buy_rainbow_charms", label="Auto Buy Event Merchant Rainbow Charms"},
        {key="event_merchant_buy_void_charms", label="Auto Buy Event Merchant Void Charms"},
        {key="event_merchant_buy_x5_crowns_boost", label="Auto Buy Event Merchant x5 Crowns Boost"},
        {key="event_merchant_buy_x5_coins_boost", label="Auto Buy Event Merchant x5 Coins Boost"},
        {key="event_merchant_buy_auto_sell_boost", label="Auto Buy Event Merchant Auto Sell Boost"},
        {key="event_merchant_buy_shield_boost", label="Auto Buy Event Merchant Shield Boost"},
    }
    Event.EVENT_MERCHANT_TIER_KEYS = {
        ["4 Star"] = "event_merchant_buy_4_star",
        ["5 Star"] = "event_merchant_buy_5_star",
        ["Single Moon"] = "event_merchant_buy_single_moon",
        ["Double Moon"] = "event_merchant_buy_double_moon",
        ["Triple Moon"] = "event_merchant_buy_triple_moon",
    }
    Event.EVENT_MERCHANT_VARIANT_KEYS = {
        Normal = "event_merchant_buy_normal_pets",
        Golden = "event_merchant_buy_golden_pets",
        Shiny = "event_merchant_buy_shiny_pets",
        Rainbow = "event_merchant_buy_rainbow_pets",
    }
    Event.EVENT_MERCHANT_CHARM_KEYS = {
        ShinyCharms = "event_merchant_buy_shiny_charms",
        RainbowCharms = "event_merchant_buy_rainbow_charms",
        VoidCharms = "event_merchant_buy_void_charms",
    }
    Event.EVENT_MERCHANT_BOOST_KEYS = {
        x5CrownsTime = "event_merchant_buy_x5_crowns_boost",
        x5CoinsTime = "event_merchant_buy_x5_coins_boost",
        AutoSellTime = "event_merchant_buy_auto_sell_boost",
        ShieldTime = "event_merchant_buy_shield_boost",
    }
    Event.EVENT_MERCHANT_PRICE_TIERS = {
        Normal = {[150]="4 Star", [300]="5 Star", [600]="Single Moon", [4500]="Double Moon", [50000]="Triple Moon"},
        Golden = {[300]="4 Star", [600]="5 Star", [1200]="Single Moon", [9000]="Double Moon", [100000]="Triple Moon"},
        Shiny = {[600]="4 Star", [1200]="5 Star", [2250]="Single Moon", [20000]="Double Moon", [180000]="Triple Moon"},
        Rainbow = {[1200]="4 Star", [2250]="5 Star", [4500]="Single Moon"},
    }

    Event.moduleCache = Event.moduleCache or {}
    Event.currencyPickupConnection = Event.currencyPickupConnection or nil
    Event.currencyPickupStarting = Event.currencyPickupStarting or false
    Event.lastPickupBatchSize = Event.lastPickupBatchSize or 0
    Event.eventBossHeartbeat = Event.eventBossHeartbeat or nil
    Event.eventBossAttackThread = Event.eventBossAttackThread or nil
    Event.eventBossStatusThread = Event.eventBossStatusThread or nil
    Event.eventBossAttacking = Event.eventBossAttacking or false
    Event.eventBossLastTeleport = Event.eventBossLastTeleport or 0
    Event.eventBossLastPriorityLog = Event.eventBossLastPriorityLog or 0
    Event.lastUpgradeBuy = Event.lastUpgradeBuy or {}
    Event.eventUpgradeThread = Event.eventUpgradeThread or nil
    Event.eventMerchantStatusLabel = Event.eventMerchantStatusLabel or nil
    Event.eventMerchantStatus = Event.eventMerchantStatus or "idle"
    Event.lastEventMerchantBuy = Event.lastEventMerchantBuy or {}
    Event.eventEggLastTeleport = Event.eventEggLastTeleport or 0

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

    function Event.getUpgradeShopInfo()
        return requireModule("EventUpgradeShop")
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

    function Event.getSummerEventMap()
        local gameplay = workspace:FindFirstChild("Gameplay")
        local regionsLoaded = gameplay and gameplay:FindFirstChild("RegionsLoaded")
        local summerEvent = regionsLoaded and regionsLoaded:FindFirstChild("SummerEvent26")
        return summerEvent and summerEvent:FindFirstChild("Map") or nil
    end

    function Event.getEventEggAreaBasePart(obj)
        if typeof(obj) ~= "Instance" then return nil end
        if not obj then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            local primary = obj.PrimaryPart
            if primary and primary:IsA("BasePart") then return primary end
        end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end

    function Event.findNamedEventEggArea(map)
        if not map then return nil end
        local preferredNames = {
            "GLEggArea",
            "GLEggZone",
            "GLEggCube",
            "EventEggArea",
            "EventEggZone",
            "EventEggCube",
            "Week1EggArea",
            "Week1EggZone",
        }
        for _, name in ipairs(preferredNames) do
            local found = map:FindFirstChild(name, true)
            local part = Event.getEventEggAreaBasePart(found)
            if part then return part end
        end
        for _, child in ipairs(map:GetDescendants()) do
            if child:IsA("BasePart") then
                local lower = child.Name:lower()
                if lower:find("egg", 1, true)
                    and (lower:find("gl", 1, true) or lower:find("event", 1, true) or lower:find("week", 1, true)) then
                    return child
                end
            end
        end
        return nil
    end

    function Event.getEventEggAreaPart()
        local map = Event.getSummerEventMap()
        if not map then return nil end

        local named = Event.findNamedEventEggArea(map)
        if named then return named end

        local children = map:GetChildren()
        return Event.getEventEggAreaBasePart(children[33])
    end

    function Event.isInsideEventEggArea(root)
        root = root or Core.getRoot()
        local area = Event.getEventEggAreaPart()
        if not root or not area then return false end
        local localPos = area.CFrame:PointToObjectSpace(root.Position)
        local half = area.Size * 0.5
        return math.abs(localPos.X) <= half.X
            and math.abs(localPos.Y) <= half.Y + 8
            and math.abs(localPos.Z) <= half.Z
    end

    function Event.shouldContinueEventEggOpen()
        return Core.alive and Core.state[Event.EVENT_EGG_OPEN_STATE_KEY] == true
    end

    function Event.teleportToEventEgg()
        if not Event.getEventEggAreaPart() then return false end
        if Event.isInsideEventEggArea() then return true end
        if not Core.state[Event.EVENT_EGG_TP_STATE_KEY] then return false end
        if os.clock() - (Event.eventEggLastTeleport or 0) < Event.EVENT_EGG_TELEPORT_DELAY then return false end

        Event.eventEggLastTeleport = os.clock()
        return Core.teleportWorld(Event.EVENT_EGG_TP_CFRAME, "event egg", function()
            return Event.shouldContinueEventEggOpen()
                and Core.state[Event.EVENT_EGG_TP_STATE_KEY] == true
        end)
    end

    function Event.openWeek1EventEgg()
        if not Event.shouldContinueEventEggOpen() then return end
        if not Event.getEventEggAreaPart() then return end

        if not Event.isInsideEventEggArea() then
            if Core.state[Event.EVENT_EGG_TP_STATE_KEY] then
                Event.teleportToEventEgg()
            end
            return
        end

        if not Core.waitForPriority("eggs", Event.shouldContinueEventEggOpen) then return end
        if not Event.isInsideEventEggArea() then return end
        if not Core.claimPriority("eggs") then return end

        Core.setCurrentAction("Opening Event Egg", math.max(2, Event.EVENT_EGG_HATCH_DELAY + 1))
        pcall(function()
            Core.UIActionRemote:FireServer("BuyEgg", Event.EVENT_EGG_WEEK1_NAME)
        end)
    end

    function Event.startEventEggOpen()
        Core.loopWhile(Event.EVENT_EGG_OPEN_STATE_KEY, Event.EVENT_EGG_HATCH_DELAY, Event.openWeek1EventEgg)
    end

    function Event.stopEventEggOpen()
        Core.clearCurrentAction("Opening Event Egg")
        if not Core.state.auto_egg_opener and not Core.state.auto_petdex and not Core.state.petdex_auto_teleport then
            Core.releasePriority("eggs")
        end
    end

    function Event.setEventMerchantStatus(text)
        Event.eventMerchantStatus = text or Event.eventMerchantStatus or "idle"
        local lbl = Event.eventMerchantStatusLabel
        if lbl and lbl.Parent then
            lbl.Text = "Event Merchant: " .. Event.eventMerchantStatus
        end
    end

    function Event.getEventMerchantData()
        local dataManager = Core.getClientDataManager()
        local Data = dataManager and dataManager.Data
        local eventMerchant = Data and Data.EventMerchant
        return Data, eventMerchant
    end

    function Event.getSortedEventMerchantSlots(items)
        local slots = {}
        if type(items) ~= "table" then return slots end
        for slotIndex, slotData in pairs(items) do
            if type(slotData) == "table" then
                local numericSlot = tonumber(slotIndex)
                if numericSlot then
                    slots[#slots + 1] = {slot=numericSlot, data=slotData}
                end
            end
        end
        table.sort(slots, function(a, b) return a.slot < b.slot end)
        return slots
    end

    function Event.getEventMerchantListing(listingIndex)
        local listings = Event.getEventMerchantListings()
        if type(listings) ~= "table" then return nil end
        return listings[listingIndex] or listings[tostring(listingIndex)]
    end

    function Event.getEventMerchantVariant(listing)
        local class = tostring(type(listing) == "table" and listing.Class or "")
        if class == "" or class == "nil" then return "Normal" end
        local lower = class:lower()
        if lower:find("golden", 1, true) or lower:find("gold", 1, true) then return "Golden" end
        if lower:find("shiny", 1, true) then return "Shiny" end
        if lower:find("rainbow", 1, true) then return "Rainbow" end
        return "Normal"
    end

    function Event.normalizeEventMerchantTier(value)
        local text = tostring(value or ""):lower()
        if text == "" then return nil end
        if text:find("triple", 1, true) or text:find("3 moon", 1, true) or text:find("3moon", 1, true) then return "Triple Moon" end
        if text:find("double", 1, true) or text:find("2 moon", 1, true) or text:find("2moon", 1, true) then return "Double Moon" end
        if text:find("single", 1, true) or text:find("1 moon", 1, true) or text:find("1moon", 1, true) or text == "moon" then return "Single Moon" end
        if text:find("5", 1, true) and text:find("star", 1, true) then return "5 Star" end
        if text:find("4", 1, true) and text:find("star", 1, true) then return "4 Star" end
        return nil
    end

    function Event.getEventMerchantPetTier(listing)
        if type(listing) ~= "table" then return nil end
        local direct = Event.normalizeEventMerchantTier(listing.Tier or listing.Rarity or listing.PetTier or listing.RarityName)
        if direct then return direct end

        local variant = Event.getEventMerchantVariant(listing)
        local price = tonumber(listing.EventCoinsPrice)
        local prices = Event.EVENT_MERCHANT_PRICE_TIERS[variant]
        return prices and prices[price] or nil
    end

    function Event.eventMerchantListingMatchesFilters(listing)
        if type(listing) ~= "table" then return false end
        local itemType = tostring(listing.Type or ""):lower()

        if itemType == "pets" or itemType == "pet" then
            local tier = Event.getEventMerchantPetTier(listing)
            local variant = Event.getEventMerchantVariant(listing)
            local tierKey = tier and Event.EVENT_MERCHANT_TIER_KEYS[tier]
            local variantKey = variant and Event.EVENT_MERCHANT_VARIANT_KEYS[variant]
            return tierKey ~= nil and variantKey ~= nil
                and Core.state[tierKey] == true
                and Core.state[variantKey] == true
        elseif listing.Type == "Charms" then
            local key = Event.EVENT_MERCHANT_CHARM_KEYS[listing.Name]
            return key ~= nil and Core.state[key] == true
        elseif listing.Type == "Boosts" then
            local key = Event.EVENT_MERCHANT_BOOST_KEYS[listing.Name]
            return key ~= nil and Core.state[key] == true
        end

        return false
    end

    function Event.canBuyEventMerchantSlot(slotInfo, Data, eventMerchant)
        if not Core.state[Event.EVENT_MERCHANT_STATE_KEY] then return false, "disabled" end
        if type(slotInfo) ~= "table" or type(slotInfo.data) ~= "table" then return false, "missing slot" end
        if type(eventMerchant) ~= "table" then return false, "missing data" end

        local slotIndex = tonumber(slotInfo.slot)
        local resetDT = eventMerchant.ResetDT
        if not slotIndex or resetDT == nil then return false, "missing reset" end

        local slotData = slotInfo.data
        local buysLeft = tonumber(slotData.BuysLeft) or 0
        if buysLeft <= 0 then return false, "sold out" end

        local listingIndex = tonumber(slotData.Index) or slotData.Index
        local listing = Event.getEventMerchantListing(listingIndex)
        if type(listing) ~= "table" then return false, "missing listing" end
        if not Event.eventMerchantListingMatchesFilters(listing) then return false, "filtered", listing end

        local price = tonumber(listing.EventCoinsPrice)
        if not price then return false, "missing price", listing end

        local eventCoins = tonumber(Data and Data.EventCoins) or 0
        if eventCoins < price then return false, "not enough Seashells", listing, price, eventCoins end

        return true, "buy", listing, price, eventCoins, slotIndex, resetDT, listingIndex
    end

    function Event.buyEventMerchantSlot(slotInfo, Data, eventMerchant)
        local canBuy, reason, listing, _, _, slotIndex, resetDT, listingIndex = Event.canBuyEventMerchantSlot(slotInfo, Data, eventMerchant)
        if not canBuy then return false, reason end

        local buyKey = tostring(slotIndex) .. ":" .. tostring(resetDT) .. ":" .. tostring(listingIndex)
        local now = os.clock()
        if now - (Event.lastEventMerchantBuy[buyKey] or 0) < 1 then
            return false, "debounced"
        end

        Event.lastEventMerchantBuy[buyKey] = now
        Event.setEventMerchantStatus("buying " .. tostring(listing.Name or "item"))
        Core.setCurrentAction("Buying Event Merchant Items", math.max(2, Event.EVENT_MERCHANT_CLICK_DELAY + 1))
        Core.UIActionRemote:FireServer(Event.getEventMerchantBuyAction(), slotIndex, resetDT)
        task.wait(Event.EVENT_MERCHANT_CLICK_DELAY)
        Core.clearCurrentAction("Buying Event Merchant Items")
        return true, "bought"
    end

    function Event.buySelectedEventMerchant()
        local Data, eventMerchant = Event.getEventMerchantData()
        local slots = eventMerchant and Event.getSortedEventMerchantSlots(eventMerchant.Items)
        if type(eventMerchant) ~= "table" or not slots or #slots == 0 then
            Event.setEventMerchantStatus("missing data")
            return
        end
        if eventMerchant.ResetDT == nil then
            Event.setEventMerchantStatus("missing reset")
            return
        end
        if not Event.getEventMerchantListings() then
            Event.setEventMerchantStatus("missing listings")
            return
        end

        local sawSoldOut = false
        local sawFiltered = false
        local sawUnaffordable = false
        for _, slotInfo in ipairs(slots) do
            if not Core.alive or not Core.state[Event.EVENT_MERCHANT_STATE_KEY] then break end

            local bought, reason = Event.buyEventMerchantSlot(slotInfo, Data, eventMerchant)
            if bought then return end
            if reason == "sold out" then sawSoldOut = true end
            if reason == "filtered" then sawFiltered = true end
            if reason == "not enough Seashells" then sawUnaffordable = true end
        end

        if sawUnaffordable then
            Event.setEventMerchantStatus("not enough Seashells")
        elseif sawFiltered then
            Event.setEventMerchantStatus("waiting")
        elseif sawSoldOut then
            Event.setEventMerchantStatus("sold out")
        else
            Event.setEventMerchantStatus("waiting")
        end
    end

    function Event.startEventMerchant()
        Event.setEventMerchantStatus("waiting")
        Core.loopWhile(Event.EVENT_MERCHANT_STATE_KEY, Event.EVENT_MERCHANT_BUY_DELAY, Event.buySelectedEventMerchant)
    end

    function Event.getEventMerchantUiItems()
        local items = {
            {type="toggle", key=Event.EVENT_MERCHANT_STATE_KEY, label="Auto Event Merchant",
                callback=function(on)
                    if on then Event.startEventMerchant()
                    else Event.setEventMerchantStatus("idle") end
                end},
            {type="status", bind="event_merchant", text="Event Merchant: idle"},
            {type="label", text="Pet Tiers"},
        }

        for i = 1, 5 do
            local filter = Event.EVENT_MERCHANT_FILTERS[i]
            items[#items + 1] = {type="toggle", key=filter.key, label=filter.label, callback=function() if Core.state[Event.EVENT_MERCHANT_STATE_KEY] then Event.startEventMerchant() end end}
        end

        items[#items + 1] = {type="label", text="Pet Variants"}
        for i = 6, 9 do
            local filter = Event.EVENT_MERCHANT_FILTERS[i]
            items[#items + 1] = {type="toggle", key=filter.key, label=filter.label, callback=function() if Core.state[Event.EVENT_MERCHANT_STATE_KEY] then Event.startEventMerchant() end end}
        end

        items[#items + 1] = {type="label", text="Charms"}
        for i = 10, 12 do
            local filter = Event.EVENT_MERCHANT_FILTERS[i]
            items[#items + 1] = {type="toggle", key=filter.key, label=filter.label, callback=function() if Core.state[Event.EVENT_MERCHANT_STATE_KEY] then Event.startEventMerchant() end end}
        end

        items[#items + 1] = {type="label", text="Boosts"}
        for i = 13, #Event.EVENT_MERCHANT_FILTERS do
            local filter = Event.EVENT_MERCHANT_FILTERS[i]
            items[#items + 1] = {type="toggle", key=filter.key, label=filter.label, callback=function() if Core.state[Event.EVENT_MERCHANT_STATE_KEY] then Event.startEventMerchant() end end}
        end

        return items
    end

    function Event.getEventUpgradeStateKey(upgradeType)
        for _, entry in ipairs(Event.EVENT_UPGRADE_LIST) do
            if entry.type == upgradeType then return entry.key end
        end
        return nil
    end

    function Event.isKnownEventUpgrade(upgradeType)
        return Event.getEventUpgradeStateKey(upgradeType) ~= nil
    end

    function Event.getEventUpgradeInfo(upgradeType)
        if not Event.isKnownEventUpgrade(upgradeType) then return nil end
        local shopInfo = Event.getUpgradeShopInfo()
        return type(shopInfo) == "table" and shopInfo[upgradeType] or nil
    end

    function Event.getCurrentEventUpgradeLevel(upgradeType)
        local dataManager = Core.getClientDataManager()
        local Data = dataManager and dataManager.Data
        local upgrades = Data and Data.EventUpgrades
        return tonumber(upgrades and upgrades[upgradeType]) or 0
    end

    function Event.getNextEventUpgradeInfo(upgradeType)
        local upgradeInfo = Event.getEventUpgradeInfo(upgradeType)
        if type(upgradeInfo) ~= "table" then return nil, nil, "missing upgrade info" end

        local upgrades = upgradeInfo.Upgrades
        if type(upgrades) ~= "table" then return nil, nil, "missing upgrade levels" end

        local currentLevel = Event.getCurrentEventUpgradeLevel(upgradeType)
        local nextLevel = currentLevel + 1
        return upgrades[nextLevel] or upgrades[tostring(nextLevel)], nextLevel, nil, currentLevel
    end

    function Event.getEventCoins()
        local dataManager = Core.getClientDataManager()
        local Data = dataManager and dataManager.Data
        return tonumber(Data and Data.EventCoins) or 0
    end

    function Event.canBuyEventUpgrade(upgradeType)
        local stateKey = Event.getEventUpgradeStateKey(upgradeType)
        if not stateKey then return false, "invalid upgrade" end
        if not Core.state[stateKey] then return false, "disabled" end

        local nextInfo, nextLevel, reason, currentLevel = Event.getNextEventUpgradeInfo(upgradeType)
        if reason then return false, reason, nextInfo, nextLevel, currentLevel end
        if not nextInfo then return false, "maxed", nextInfo, nextLevel, currentLevel end

        local cost = tonumber(nextInfo.Price)
        if not cost then return false, "missing cost", nextInfo, nextLevel, currentLevel end

        local eventCoins = Event.getEventCoins()
        if eventCoins < cost then
            return false, "not enough currency", nextInfo, nextLevel, currentLevel, cost, eventCoins
        end

        return true, "affordable", nextInfo, nextLevel, currentLevel, cost, eventCoins
    end

    function Event.setEventUpgradeToggleOff(upgradeType, reason)
        local stateKey = Event.getEventUpgradeStateKey(upgradeType)
        if not stateKey or Core.state[stateKey] == false then return end

        Core.state[stateKey] = false
        Core.debugLog("Event upgrade disabled:", upgradeType, reason or "stopped")
        if HS.Session and HS.Session.save and not HS.Session.suppressSave then
            pcall(HS.Session.save)
        end
        if HS.UI and HS.UI.renderContent and Core.activeTab == "event" then
            pcall(HS.UI.renderContent)
        end
    end

    function Event.buyEventUpgrade(upgradeType)
        local canBuy, reason, _, nextLevel = Event.canBuyEventUpgrade(upgradeType)
        if reason == "maxed" then
            Event.setEventUpgradeToggleOff(upgradeType, "max level")
            return false, reason
        end
        if not canBuy then return false, reason end
        if not Core.UIActionRemote or type(nextLevel) ~= "number" then return false, "missing remote or level" end

        local buyKey = tostring(upgradeType) .. ":" .. tostring(nextLevel)
        local now = os.clock()
        if now - (Event.lastUpgradeBuy[buyKey] or 0) < 1 then
            return false, "debounced"
        end

        Event.lastUpgradeBuy[buyKey] = now
        Core.debugLog("Buying event upgrade", upgradeType, "level", nextLevel)
        Core.UIActionRemote:FireServer(Event.getEventUpgradeBuyAction(), upgradeType, nextLevel)
        return true, "bought"
    end

    function Event.hasEnabledEventUpgrade()
        for _, entry in ipairs(Event.EVENT_UPGRADE_LIST) do
            if Core.state[entry.key] == true then return true end
        end
        return false
    end

    function Event.runAutoEventUpgrades()
        if Event.eventUpgradeThread or not Event.hasEnabledEventUpgrade() then return end

        Event.eventUpgradeThread = task.spawn(function()
            Core.debugLog("Auto Event Upgrades loop started")
            while Core.alive and Event.hasEnabledEventUpgrade() do
                for _, entry in ipairs(Event.EVENT_UPGRADE_LIST) do
                    if Core.state[entry.key] == true then
                        local bought = Event.buyEventUpgrade(entry.type)
                        if bought then break end
                    end
                end
                task.wait(Core.BUY_DELAY or 2)
            end
            Event.eventUpgradeThread = nil
            if Core.alive and Event.hasEnabledEventUpgrade() then
                Event.runAutoEventUpgrades()
            else
                Core.debugLog("Auto Event Upgrades loop stopped")
            end
        end)
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

    function Event.getEventBossModel()
        local hrp = Event.getEventBossHRP()
        return hrp and hrp.Parent or nil
    end

    function Event.getEventBossArenaBase()
        local gameplay = workspace:FindFirstChild("Gameplay")
        local regionsLoaded = gameplay and gameplay:FindFirstChild("RegionsLoaded")
        local summerEvent = regionsLoaded and regionsLoaded:FindFirstChild("SummerEvent26")
        local bossRoot = summerEvent and summerEvent:FindFirstChild("Boss")
        return bossRoot and bossRoot:FindFirstChild("ArenaBase") or nil
    end

    function Event.getEventBossArenaStatusLabel()
        local gameplay = workspace:FindFirstChild("Gameplay")
        local regionsLoaded = gameplay and gameplay:FindFirstChild("RegionsLoaded")
        local summerEvent = regionsLoaded and regionsLoaded:FindFirstChild("SummerEvent26")
        local bossRoot = summerEvent and summerEvent:FindFirstChild("Boss")
        local arenaGui = bossRoot and bossRoot:FindFirstChild("ArenaGui")
        local billboardGui = arenaGui and arenaGui:FindFirstChild("BillboardGui")
        local frame = billboardGui and billboardGui:FindFirstChild("Frame")
        local label = frame and frame:FindFirstChild("TextLabelBottom")
        return label and label:IsA("TextLabel") and label or nil
    end

    function Event.getEventBossArenaStatusText()
        local label = Event.getEventBossArenaStatusLabel()
        local text = label and label.Text
        return type(text) == "string" and text or nil
    end

    local function normalizeStatusText(text)
        if type(text) ~= "string" then return "" end
        return text:lower():gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    end

    function Event.isEventBossCooldownStatusText(text)
        local lower = normalizeStatusText(text)
        if lower == "" then return false end
        if lower:find("respawn", 1, true)
            or lower:find("spawns", 1, true)
            or lower:find("spawn", 1, true)
            or lower:find("cooldown", 1, true)
            or lower:find("cool down", 1, true) then
            return true
        end

        local hasTimerWord = lower:find("timer", 1, true)
            or lower:find("time", 1, true)
            or lower:match("%f[%a]in%f[%A]") ~= nil
        local hasCountdown = lower:match("%d+%s*:%s*%d+") ~= nil
            or lower:match("%d+%s*[smh]%f[%A]") ~= nil
            or lower:match("%d+%s*sec") ~= nil
            or lower:match("%d+%s*min") ~= nil
        return hasTimerWord and hasCountdown
    end

    function Event.isEventBossActiveStatusText(text)
        local lower = normalizeStatusText(text)
        if lower == "" then return false end
        if lower:find("hp", 1, true) or lower:find("health", 1, true) then
            return true
        end
        return lower:match("%d[%d,%.%s]*%s*/%s*%d[%d,%.%s]*") ~= nil
    end

    function Event.isEventBossAvailable()
        local hrp = Event.getEventBossHRP()
        if not hrp then return false end

        local statusText = Event.getEventBossArenaStatusText()
        if Event.isEventBossCooldownStatusText(statusText) then return false end
        return Event.isEventBossActiveStatusText(statusText)
    end

    Event.isEventBossSpawned = Event.isEventBossAvailable

    function Event.isInEventBossArena(root)
        local arena = Event.getEventBossArenaBase()
        if not root or not arena or not arena:IsA("BasePart") then return false end
        local localPos = arena.CFrame:PointToObjectSpace(root.Position)
        local half = arena.Size * 0.5
        return math.abs(localPos.X) <= half.X
            and math.abs(localPos.Y) <= half.Y + 8
            and math.abs(localPos.Z) <= half.Z
    end

    function Event.setEventBossStatus(text, color)
        local lbl = Event.eventBossStatusLabel
        if lbl and lbl.Parent then
            lbl.Text = text
            lbl.TextColor3 = color or Core.C.textDim
        end
    end

    function Event.canUseEventBossPriority()
        return Core and Core.canUsePriority and Core.canUsePriority("boss")
    end

    function Event.stopEventBossFollow()
        if Event.eventBossHeartbeat then
            Event.eventBossHeartbeat:Disconnect()
            Event.eventBossHeartbeat = nil
        end
    end

    function Event.ensureEventBossFollow()
        if Event.eventBossHeartbeat then return end
        Event.eventBossHeartbeat = S.RunService.Heartbeat:Connect(function()
            if not Core.alive or not Core.state[Event.EVENT_BOSS_STATE_KEY] then
                Event.stopEventBossFollow()
                return
            end

            if not Event.isEventBossAvailable() or not Event.canUseEventBossPriority() then
                Event.stopEventBossFollow()
                return
            end

            local bossRoot = Event.getEventBossHRP()
            local root = Core.getRoot()
            if not bossRoot or not root or not Event.isInEventBossArena(root) then
                Event.stopEventBossFollow()
                return
            end

            local character = Core.player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not humanoid then return end

            local offset = root.Position - bossRoot.Position
            local distance = offset.Magnitude
            if distance > Event.EVENT_BOSS_FOLLOW_DISTANCE and distance > 0.1 then
                local targetPos = bossRoot.Position + offset.Unit * Event.EVENT_BOSS_FOLLOW_DISTANCE
                humanoid:MoveTo(targetPos)
            end
        end)
    end

    function Event.ensureEventBossAttackLoop()
        if Event.eventBossAttackThread then return end
        Event.eventBossAttacking = true
        Event.eventBossAttackThread = task.spawn(function()
            Core.debugLog("Auto Event Boss attack loop started")
            while Core.alive and Core.state[Event.EVENT_BOSS_STATE_KEY] and Event.eventBossAttacking do
                local boss = Event.getEventBossModel()
                local root = Core.getRoot()
                if boss and Event.isEventBossAvailable() and root and Event.isInEventBossArena(root) and Event.canUseEventBossPriority() then
                    local remote = Core.getEquippedRemote()
                    if remote then
                        Core.setCurrentAction("Auto Event Boss", 2)
                        pcall(function() remote:FireServer({boss}) end)
                    end
                end
                task.wait(Core.getFastHitDelay(Core.BOSS_DELAY))
            end
            Event.eventBossAttackThread = nil
            Event.eventBossAttacking = false
            Core.clearCurrentAction("Auto Event Boss")
            Core.debugLog("Auto Event Boss attack loop stopped")
        end)
    end

    function Event.stopEventBossAttack()
        Event.eventBossAttacking = false
        if Core and Core.clearCurrentAction then
            Core.clearCurrentAction("Auto Event Boss")
        end
    end

    function Event.stopEventBoss()
        Event.stopEventBossAttack()
        Event.stopEventBossFollow()
        if Core and Core.releasePriority then Core.releasePriority("boss") end
        Event.setEventBossStatus("Event Boss: stopped", Core.C.textDim)
    end

    function Event.startEventBoss()
        if Event.eventBossStatusThread then return end
        Event.eventBossStatusThread = task.spawn(function()
            Core.debugLog("Auto Event Boss loop started")
            while Core.alive and Core.state[Event.EVENT_BOSS_STATE_KEY] do
                local statusText = Event.getEventBossArenaStatusText()
                local bossAvailable = Event.isEventBossAvailable()
                local root = Core.getRoot()
                local inArena = Event.isInEventBossArena(root)

                if bossAvailable then
                    if inArena then
                        if Event.canUseEventBossPriority() then
                            Core.claimPriority("boss")
                            Event.ensureEventBossFollow()
                            Event.ensureEventBossAttackLoop()
                            Event.setEventBossStatus("Event Boss: spawned / following", Core.C.orange)
                        else
                            Event.stopEventBossFollow()
                            Event.stopEventBossAttack()
                            if os.clock() - Event.eventBossLastPriorityLog >= 3 then
                                Event.eventBossLastPriorityLog = os.clock()
                                Core.debugLog("Auto Event Boss paused by priority:", Core.priorityOwner or "idle")
                            end
                            Event.setEventBossStatus("Event Boss: waiting for priority", Core.C.textDim)
                        end
                    elseif Core.state[Event.EVENT_BOSS_TP_STATE_KEY] then
                        Event.stopEventBossFollow()
                        Event.stopEventBossAttack()
                        if os.clock() - Event.eventBossLastTeleport >= Event.EVENT_BOSS_TP_COOLDOWN then
                            Event.eventBossLastTeleport = os.clock()
                            if Core.teleportWorld(Event.EVENT_BOSS_TP_CFRAME, "boss", function()
                                return Core.alive
                                    and Core.state[Event.EVENT_BOSS_STATE_KEY]
                                    and Core.state[Event.EVENT_BOSS_TP_STATE_KEY]
                                    and Event.isEventBossAvailable()
                            end) then
                                Event.setEventBossStatus("Event Boss: teleporting", Core.C.orange)
                            end
                        end
                    else
                        Event.stopEventBossFollow()
                        Event.stopEventBossAttack()
                        Core.releasePriority("boss")
                        Event.setEventBossStatus("Event Boss: outside arena", Core.C.textDim)
                    end
                else
                    Event.stopEventBossFollow()
                    Event.stopEventBossAttack()
                    Core.releasePriority("boss")
                    Event.setEventBossStatus("Event Boss: " .. ((statusText and statusText ~= "") and statusText or "waiting for spawn"), Core.C.textDim)
                end

                task.wait(0.5)
            end
            Event.eventBossStatusThread = nil
            Event.stopEventBoss()
            Core.debugLog("Auto Event Boss loop stopped")
        end)
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

    function Event.getEventCurrencyHolder()
        local gameplay = workspace:FindFirstChild("Gameplay")
        local regionsLoaded = gameplay and gameplay:FindFirstChild("RegionsLoaded")
        local summerEvent = regionsLoaded and regionsLoaded:FindFirstChild("SummerEvent26")
        local currencyPickup = summerEvent and summerEvent:FindFirstChild("CurrencyPickup")
        return currencyPickup and currencyPickup:FindFirstChild("CurrencyHolder") or nil
    end

    function Event.getCurrencyHolder()
        return Event.getEventCurrencyHolder()
    end

    function Event.isEventCurrencyPickup(obj)
        if typeof(obj) ~= "Instance" then return false end

        local holder = Event.getCurrencyHolder()
        if not holder or not obj:IsDescendantOf(holder) then return false end
        return obj.Parent ~= nil
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

    function Event.collectCurrencyPickups(pickups)
        if not Core or not Core.alive or not Core.state[Event.CURRENCY_PICKUP_STATE_KEY] then return end
        if type(pickups) ~= "table" or #pickups <= 0 then
            Event.lastPickupBatchSize = 0
            return
        end

        local validPickups = {}
        for _, pickup in ipairs(pickups) do
            if Event.isEventCurrencyPickup(pickup) then
                table.insert(validPickups, pickup)
            end
        end
        if #validPickups <= 0 then
            Event.lastPickupBatchSize = 0
            return
        end

        local remote = Event.getCollectCurrencyPickupRemote()
        if not remote then return end

        Event.lastPickupBatchSize = #validPickups
        pcall(function()
            remote:FireServer(validPickups)
        end)
    end

    function Event.collectCurrencyPickup(obj)
        if not Event.isEventCurrencyPickup(obj) then return end
        Event.collectCurrencyPickups({obj})
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

            if not Core.alive or not Core.state[Event.CURRENCY_PICKUP_STATE_KEY] then
                Event.currencyPickupStarting = false
                return
            end
            Event.collectCurrencyPickups(Event.findEventCurrencyPickups())

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
        local bossStatusText = Event.getEventBossArenaStatusText()
        local bossAvailable = Event.isEventBossAvailable()
        local pickupRemote = Event.getCollectCurrencyPickupRemote()
        local pickupHolder = Event.getEventCurrencyHolder()
        local pickupChildren = pickupHolder and #pickupHolder:GetChildren() or nil

        return table.concat({
            "Current Event: " .. tostring(Event.CURRENT_EVENT_KEY),
            "Currency: " .. tostring(currencyName),
            "Amount: " .. (amountText and tostring(amountText) or "unavailable"),
            "EventsInfo: " .. (eventInfo and "found" or "missing"),
            "Merchant Listings: " .. (listingCount and tostring(listingCount) or "missing"),
            "Boss HRP: " .. (bossHRP and "found" or "missing"),
            "Boss Status: " .. ((bossStatusText and bossStatusText ~= "") and bossStatusText or "unavailable"),
            "Boss Available: " .. (bossAvailable and "Yes" or "No"),
            "Pickup Remote: " .. (pickupRemote and "found" or "missing"),
            "Pickup Holder: " .. (pickupHolder and "found" or "missing"),
            "Pickup Children: " .. (pickupChildren and tostring(pickupChildren) or "missing"),
            "Last Pickup Batch: " .. tostring(Event.lastPickupBatchSize or 0),
            "Event Wheel: disabled",
        }, "\n")
    end
end
