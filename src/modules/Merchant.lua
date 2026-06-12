return function(HS, S)
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
