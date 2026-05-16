return function(HS, S)
    local Farming = HS.Farming or {}
    HS.Farming = Farming
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
