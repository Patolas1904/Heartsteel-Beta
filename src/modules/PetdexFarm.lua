return function(HS, S)
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
