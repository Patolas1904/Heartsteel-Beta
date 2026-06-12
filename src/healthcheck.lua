--// Heartsteel public health probe
--// Private scoring happens on your Render API.
--// This script only collects safe facts and sends them to your server.

local ENDPOINT = "https://heartsteel-health-api.onrender.com/healthcheck"

local RUN_SAFE_CALL_TESTS = true
local PRINT_API_MESSAGES = true

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local function safeGetGenv()
    if type(getgenv) ~= "function" then
        return nil
    end

    local ok, env = pcall(getgenv)

    if ok and type(env) == "table" then
        return env
    end

    return nil
end

local function safeRead(container, key)
    if type(container) ~= "table" then
        return nil
    end

    local ok, value = pcall(function()
        return rawget(container, key)
    end)

    if ok then
        return value
    end

    return nil
end

local function looksLikeHeartsteel(value)
    return type(value) == "table"
        and type(safeRead(value, "Core")) == "table"
        and type(safeRead(value, "UI")) == "table"
end

local function findRuntime()
    local env = safeGetGenv()

    local candidates = {
        { label = "getgenv().__HeartsteelHS", container = env, key = "__HeartsteelHS" },
        { label = "getgenv().HeartsteelHS", container = env, key = "HeartsteelHS" },
        { label = "getgenv().HS", container = env, key = "HS" },

        { label = "_G.__HeartsteelHS", container = _G, key = "__HeartsteelHS" },
        { label = "_G.HeartsteelHS", container = _G, key = "HeartsteelHS" },
        { label = "_G.HS", container = _G, key = "HS" },

        { label = "shared.__HeartsteelHS", container = shared, key = "__HeartsteelHS" },
        { label = "shared.HeartsteelHS", container = shared, key = "HeartsteelHS" },
        { label = "shared.HS", container = shared, key = "HS" },
    }

    for _, candidate in ipairs(candidates) do
        local value = safeRead(candidate.container, candidate.key)

        if looksLikeHeartsteel(value) then
            return value, candidate.label
        end
    end

    return nil, nil
end

local function getPath(root, path)
    local value = root

    for _, key in ipairs(path) do
        if value == nil then
            return nil
        end

        if type(value) == "table" then
            value = safeRead(value, key)
        else
            local ok, nextValue = pcall(function()
                return value[key]
            end)

            if not ok then
                return nil
            end

            value = nextValue
        end
    end

    return value
end

local function exists(root, path)
    return getPath(root, path) ~= nil
end

local function isTable(root, path)
    return type(getPath(root, path)) == "table"
end

local function isFunction(root, path)
    return type(getPath(root, path)) == "function"
end

local function countKeys(tbl)
    if type(tbl) ~= "table" then
        return 0
    end

    local count = 0

    for _ in pairs(tbl) do
        count = count + 1
    end

    return count
end

local function countArrayOrKeys(tbl)
    if type(tbl) ~= "table" then
        return 0
    end

    local ok, length = pcall(function()
        return #tbl
    end)

    if ok and type(length) == "number" and length > 0 then
        return length
    end

    return countKeys(tbl)
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

local function getPetsInfoEggCounts()
    local counts = {
        available = false,
        normalEggCount = 0,
        totalEggCount = 0,
        status = "unavailable",
    }

    local ok = pcall(function()
        local replicatedStorage = game:GetService("ReplicatedStorage")
        local modules = replicatedStorage and replicatedStorage:FindFirstChild("Modules")
        local petsInfo = modules and modules:FindFirstChild("PetsInfo")
        local eggsScript = petsInfo and petsInfo:FindFirstChild("Eggs")
        local shopScript = petsInfo and petsInfo:FindFirstChild("PetShopInfo")

        if not eggsScript or not shopScript then
            counts.status = "missing_modules"
            return
        end

        local eggsModule = require(eggsScript)
        local shopInfo = require(shopScript)

        if type(eggsModule) ~= "table" or type(shopInfo) ~= "table" then
            counts.status = "bad_module_shape"
            return
        end

        local normalEggs = {}
        for key, entry in pairs(shopInfo) do
            local eggName = getShopEggName(key, entry, eggsModule)
            if eggName then
                normalEggs[eggName] = true
            end
        end

        counts.available = true
        counts.status = "ok"
        counts.totalEggCount = countKeys(eggsModule)
        counts.normalEggCount = countKeys(normalEggs)
    end)

    if not ok then
        counts.available = false
        counts.status = "failed"
    end

    return counts
end

local function buildPetdexEventEggFacts(HS)
    local petdexFarm = HS and getPath(HS, { "PetdexFarm" }) or nil
    local petdexRewards = HS and getPath(HS, { "PetdexRewards" }) or nil
    local moduleCounts = getPetsInfoEggCounts()

    local facts = {
        hasPetdexRewards = type(petdexRewards) == "table",
        hasPetdexFarm = type(petdexFarm) == "table",
        hasEventEggTracking = false,
        initAttempted = false,
        initOk = false,
        initStatus = "not_run",
        eventEggCount = 0,
        normalEggCount = 0,
        totalEggCount = 0,
        moduleCountsAvailable = moduleCounts.available,
        moduleCountsStatus = moduleCounts.status,
        hasCompletedEggCounter = type(petdexRewards) == "table"
            and type(safeRead(petdexRewards, "getCompletedEggCount")) == "function",
        hasEventEggProgress = false,
        eventEggsExcludedFromFarming = true,
        usesOddsExtraction = "unknown",
    }

    if type(petdexFarm) ~= "table" then
        return facts
    end

    local init = safeRead(petdexFarm, "init")
    if type(init) == "function" then
        facts.initAttempted = true
        local ok, result = pcall(init)
        facts.initOk = ok and result ~= false
        facts.initStatus = facts.initOk and "ok" or "failed"
    end

    local eventEggs = safeRead(petdexFarm, "eventEggs")
    local eventEggOrder = safeRead(petdexFarm, "eventEggOrder")
    local eventEggPets = safeRead(petdexFarm, "eventEggPets")
    local eggOrder = safeRead(petdexFarm, "eggOrder")
    local eggPets = safeRead(petdexFarm, "eggPets")

    facts.hasEventEggTracking =
        type(eventEggs) == "table"
        or type(eventEggOrder) == "table"
        or type(eventEggPets) == "table"

    facts.hasEventEggProgress =
        type(safeRead(petdexFarm, "getEventEggProgress")) == "function"
        or type(safeRead(petdexFarm, "evaluateEventEgg")) == "function"

    facts.eventEggCount = math.max(
        countKeys(eventEggs),
        countArrayOrKeys(eventEggOrder),
        countKeys(eventEggPets)
    )

    local runtimeNormalEggCount = math.max(
        countArrayOrKeys(eggOrder),
        countKeys(eggPets)
    )

    facts.normalEggCount = moduleCounts.available and moduleCounts.normalEggCount or runtimeNormalEggCount
    facts.totalEggCount = moduleCounts.available
        and moduleCounts.totalEggCount
        or runtimeNormalEggCount + facts.eventEggCount

    local farmEggSet = {}
    if type(eggOrder) == "table" then
        for _, eggName in ipairs(eggOrder) do
            if type(eggName) == "string" then
                farmEggSet[eggName] = true
            end
        end
    end

    local excluded = true

    local function checkEventEggName(eggName)
        if type(eggName) == "string" and farmEggSet[eggName] then
            excluded = false
        end
    end

    if type(eventEggs) == "table" then
        for eggName in pairs(eventEggs) do
            checkEventEggName(eggName)
            if not excluded then break end
        end
    end

    if excluded and type(eventEggPets) == "table" then
        for eggName in pairs(eventEggPets) do
            checkEventEggName(eggName)
            if not excluded then break end
        end
    end

    if excluded and type(eventEggOrder) == "table" then
        for _, eggName in ipairs(eventEggOrder) do
            checkEventEggName(eggName)
            if not excluded then break end
        end
    end

    facts.eventEggsExcludedFromFarming = excluded

    if type(eventEggPets) == "table" then
        for _, pets in pairs(eventEggPets) do
            if type(pets) == "table" and #pets > 0 then
                local first = pets[1]
                facts.usesOddsExtraction =
                    type(first) == "table"
                    and type(rawget(first, "name")) == "string"
                    and rawget(first, "odds") ~= nil
                break
            end
        end
    end

    return facts
end

local function valueKind(value)
    if value == nil then
        return "nil"
    end

    local kind = type(value)

    if kind == "boolean" or kind == "number" or kind == "string" then
        return tostring(value)
    end

    if kind == "userdata" or kind == "table" then
        local ok, className = pcall(function()
            return value.ClassName
        end)

        if ok and className then
            return tostring(className)
        end
    end

    return kind
end

local function inputStatus(inputs, key)
    local value = type(inputs) == "table" and safeRead(inputs, key) or nil

    if tostring(value or "") ~= "" then
        return "set"
    end

    return "empty"
end

local function callEventHelper(event, helperName)
    local fn = type(event) == "table" and safeRead(event, helperName) or nil

    if type(fn) ~= "function" then
        return false, nil, "missing_function"
    end

    local ok, result = pcall(fn)
    if not ok then
        return false, nil, "failed"
    end

    return true, result, "ok"
end

local function buildEventSubsystemFacts(HS)
    local event = HS and getPath(HS, { "Event" }) or nil

    local facts = {
        table = type(event) == "table",
        currentEventKey = type(event) == "table" and tostring(safeRead(event, "CURRENT_EVENT_KEY") or "") or "",
        expectedCurrencyName = type(event) == "table" and tostring(safeRead(event, "CURRENT_EVENT_CURRENCY_NAME") or "") or "",

        getEventsInfo = type(event) == "table" and type(safeRead(event, "getEventsInfo")) == "function" or false,
        getEventMerchantInfo = type(event) == "table" and type(safeRead(event, "getEventMerchantInfo")) == "function" or false,
        getCurrentEventInfo = type(event) == "table" and type(safeRead(event, "getCurrentEventInfo")) == "function" or false,
        getCurrentEventCurrencyName = type(event) == "table" and type(safeRead(event, "getCurrentEventCurrencyName")) == "function" or false,
        getEventMerchantListings = type(event) == "table" and type(safeRead(event, "getEventMerchantListings")) == "function" or false,
        getEventBossHRP = type(event) == "table" and type(safeRead(event, "getEventBossHRP")) == "function" or false,
        getCollectCurrencyPickupRemote = type(event) == "table" and type(safeRead(event, "getCollectCurrencyPickupRemote")) == "function" or false,
        isEventWheelEnabled = type(event) == "table" and type(safeRead(event, "isEventWheelEnabled")) == "function" or false,

        eventsInfoAvailable = false,
        eventMerchantInfoAvailable = false,
        currentEventInfoAvailable = false,
        currencyName = nil,
        currencyNameStatus = "missing",
        merchantListingsAvailable = false,
        merchantListingCount = 0,
        bossHRPAvailable = false,
        bossHRPType = "nil",
        collectCurrencyPickupRemote = false,
        collectCurrencyPickupRemoteType = "nil",
        eventWheelEnabled = false,
        eventWheelDisabled = true,
        eventUiTab = HS and getPath(HS, { "UI", "UI_DATA", "event" }) ~= nil or false,
    }

    if type(event) ~= "table" then
        return facts
    end

    local okEventsInfo, eventsInfo = callEventHelper(event, "getEventsInfo")
    facts.eventsInfoAvailable = okEventsInfo and type(eventsInfo) == "table"

    local okMerchantInfo, merchantInfo = callEventHelper(event, "getEventMerchantInfo")
    facts.eventMerchantInfoAvailable = okMerchantInfo and type(merchantInfo) == "table"

    local okCurrentInfo, currentInfo = callEventHelper(event, "getCurrentEventInfo")
    facts.currentEventInfoAvailable = okCurrentInfo and type(currentInfo) == "table"

    local okCurrency, currencyName = callEventHelper(event, "getCurrentEventCurrencyName")
    if okCurrency and type(currencyName) == "string" and currencyName ~= "" then
        facts.currencyName = currencyName
        facts.currencyNameStatus = currencyName == "Seashells" and "seashells" or "other"
    end

    local okListings, listings = callEventHelper(event, "getEventMerchantListings")
    facts.merchantListingsAvailable = okListings and type(listings) == "table"
    facts.merchantListingCount = facts.merchantListingsAvailable and countArrayOrKeys(listings) or 0

    local okBossHRP, bossHRP = callEventHelper(event, "getEventBossHRP")
    facts.bossHRPAvailable = okBossHRP and bossHRP ~= nil
    facts.bossHRPType = valueKind(bossHRP)

    local okRemote, remote = callEventHelper(event, "getCollectCurrencyPickupRemote")
    facts.collectCurrencyPickupRemote = okRemote and remote ~= nil
    facts.collectCurrencyPickupRemoteType = valueKind(remote)

    local okWheel, wheelEnabled = callEventHelper(event, "isEventWheelEnabled")
    facts.eventWheelEnabled = okWheel and wheelEnabled == true
    facts.eventWheelDisabled = okWheel and wheelEnabled ~= true

    return facts
end

local function listEnabledToggles(state)
    local keys = {}

    if type(state) ~= "table" then
        return keys
    end

    for key, value in pairs(state) do
        if value == true then
            local text = tostring(key)
            local lower = string.lower(text)

            if not lower:find("url", 1, true)
                and not lower:find("webhook", 1, true)
                and not lower:find("token", 1, true)
                and not lower:find("secret", 1, true)
                and not lower:find("cookie", 1, true) then
                keys[#keys + 1] = text
            end
        end
    end

    table.sort(keys)

    return keys
end

local function findUiItemKey(items, wantedKey)
    if type(items) ~= "table" then
        return false
    end

    for _, item in ipairs(items) do
        if type(item) == "table" then
            if rawget(item, "key") == wantedKey then
                return true
            end

            if findUiItemKey(rawget(item, "items"), wantedKey) then
                return true
            end
        end
    end

    return false
end

local function hasElementPositions(autoCycle, element)
    local positions = safeRead(autoCycle, "POSITIONS")

    if type(positions) ~= "table" then
        return false
    end

    local lower = string.lower(element)
    local tiers = { "starter", "advanced", "master", "grandmaster" }

    for _, tier in ipairs(tiers) do
        local key = lower .. "_" .. tier .. "_pull"

        if rawget(positions, key) == nil then
            return false
        end
    end

    return true
end

local function loopStatus(core, key)
    local state = safeRead(core, "state")
    local activeLoops = safeRead(core, "activeLoops")

    local enabled = type(state) == "table" and state[key] == true or false
    local active = type(activeLoops) == "table" and activeLoops[key] ~= nil or false

    return {
        enabled = enabled,
        active = active,
        healthy = enabled == false or active == true,
    }
end

local function safeCall(fn)
    if type(fn) ~= "function" then
        return {
            ran = false,
            ok = false,
            result = nil,
            error = "not a function",
        }
    end

    local ok, result = pcall(fn)

    return {
        ran = true,
        ok = ok,
        result = ok and tostring(result) or nil,
        error = ok and nil or tostring(result),
    }
end

local function controlledTeleportLockProbe(core)
    local lockWorldTeleports = safeRead(core, "lockWorldTeleports")
    local isWorldTeleportBlocked = safeRead(core, "isWorldTeleportBlocked")

    local result = {
        ran = false,
        ok = false,
        lockWorldTeleports = type(lockWorldTeleports) == "function",
        isWorldTeleportBlocked = type(isWorldTeleportBlocked) == "function",
        lockCallOk = false,
        blockedCallOk = false,
        dungeonActiveAfterLock = false,
        prioritySetToDungeon = false,
        lockUntilInFutureAfterLock = false,
        blockedAfterLock = false,
        stateRestored = false,
        error = nil,
    }

    if type(lockWorldTeleports) ~= "function" or type(isWorldTeleportBlocked) ~= "function" then
        result.error = "missing teleport lock function"
        return result
    end

    local oldDungeonActive = safeRead(core, "dungeonActive")
    local oldDungeonTeleportLockUntil = safeRead(core, "dungeonTeleportLockUntil")
    local oldPriorityOwner = safeRead(core, "priorityOwner")

    local function restore()
        rawset(core, "dungeonActive", oldDungeonActive)
        rawset(core, "dungeonTeleportLockUntil", oldDungeonTeleportLockUntil)
        rawset(core, "priorityOwner", oldPriorityOwner)
        result.stateRestored =
            safeRead(core, "dungeonActive") == oldDungeonActive
            and safeRead(core, "dungeonTeleportLockUntil") == oldDungeonTeleportLockUntil
            and safeRead(core, "priorityOwner") == oldPriorityOwner
    end

    result.ran = true

    local lockOk, lockErr = pcall(lockWorldTeleports, 2)
    result.lockCallOk = lockOk

    if not lockOk then
        result.error = tostring(lockErr)
        restore()
        return result
    end

    local lockUntil = tonumber(safeRead(core, "dungeonTeleportLockUntil"))
    result.dungeonActiveAfterLock = safeRead(core, "dungeonActive") == true
    result.prioritySetToDungeon = safeRead(core, "priorityOwner") == "dungeon"
    result.lockUntilInFutureAfterLock = lockUntil ~= nil and lockUntil > os.clock()

    local blockedOk, blocked = pcall(isWorldTeleportBlocked)
    result.blockedCallOk = blockedOk
    result.blockedAfterLock = blockedOk and blocked == true or false

    result.ok =
        result.lockCallOk
        and result.blockedCallOk
        and result.dungeonActiveAfterLock
        and result.prioritySetToDungeon
        and result.lockUntilInFutureAfterLock
        and result.blockedAfterLock

    restore()
    return result
end

local function controlledDungeonPresenceFallbackProbe(core, dungeon)
    local isDungeonPresenceActive = safeRead(dungeon, "isDungeonPresenceActive")
    local refreshPresenceLock = safeRead(dungeon, "refreshPresenceLock")
    local lockWorldTeleports = safeRead(core, "lockWorldTeleports")

    local result = {
        ran = false,
        ok = false,
        hasDungeonTargets = type(safeRead(dungeon, "hasDungeonTargets")) == "function",
        isDungeonPresenceActive = type(isDungeonPresenceActive) == "function",
        refreshPresenceLock = type(refreshPresenceLock) == "function",
        lockWorldTeleports = type(lockWorldTeleports) == "function",
        presenceCallOk = false,
        fallbackPresenceOk = false,
        refreshCallOk = false,
        refreshReturnedTrue = false,
        lockRefreshedByFallback = false,
        runProtectionActiveAfterRefresh = false,
        prioritySetToDungeon = false,
        stateRestored = false,
        functionsRestored = false,
        error = nil,
    }

    if type(isDungeonPresenceActive) ~= "function"
        or type(refreshPresenceLock) ~= "function"
        or type(lockWorldTeleports) ~= "function" then
        result.error = "missing dungeon presence fallback function"
        return result
    end

    local oldIsInsideActive = safeRead(dungeon, "isInsideActive")
    local oldHasDungeonTargets = safeRead(dungeon, "hasDungeonTargets")
    local oldUpdateAutoStartState = safeRead(dungeon, "updateAutoStartState")
    local oldWasInside = safeRead(dungeon, "wasInside")
    local oldForceEndedUntil = safeRead(dungeon, "forceEndedUntil")
    local oldRunActive = safeRead(dungeon, "runActive")
    local oldRunProtectionActive = safeRead(dungeon, "runProtectionActive")
    local oldLastDungeonActivityAt = safeRead(dungeon, "lastDungeonActivityAt")
    local oldRunProtectionStartedAt = safeRead(dungeon, "runProtectionStartedAt")
    local oldRunProtectionHeldLogged = safeRead(dungeon, "runProtectionHeldLogged")
    local oldRunEnding = safeRead(dungeon, "runEnding")
    local oldRunEndToken = safeRead(dungeon, "runEndToken")

    local oldDungeonActive = safeRead(core, "dungeonActive")
    local oldDungeonTeleportLockUntil = safeRead(core, "dungeonTeleportLockUntil")
    local oldPriorityOwner = safeRead(core, "priorityOwner")

    local function restore()
        rawset(dungeon, "isInsideActive", oldIsInsideActive)
        rawset(dungeon, "hasDungeonTargets", oldHasDungeonTargets)
        rawset(dungeon, "updateAutoStartState", oldUpdateAutoStartState)
        rawset(dungeon, "wasInside", oldWasInside)
        rawset(dungeon, "forceEndedUntil", oldForceEndedUntil)
        rawset(dungeon, "runActive", oldRunActive)
        rawset(dungeon, "runProtectionActive", oldRunProtectionActive)
        rawset(dungeon, "lastDungeonActivityAt", oldLastDungeonActivityAt)
        rawset(dungeon, "runProtectionStartedAt", oldRunProtectionStartedAt)
        rawset(dungeon, "runProtectionHeldLogged", oldRunProtectionHeldLogged)
        rawset(dungeon, "runEnding", oldRunEnding)
        rawset(dungeon, "runEndToken", oldRunEndToken)

        rawset(core, "dungeonActive", oldDungeonActive)
        rawset(core, "dungeonTeleportLockUntil", oldDungeonTeleportLockUntil)
        rawset(core, "priorityOwner", oldPriorityOwner)

        result.functionsRestored =
            safeRead(dungeon, "isInsideActive") == oldIsInsideActive
            and safeRead(dungeon, "hasDungeonTargets") == oldHasDungeonTargets
            and safeRead(dungeon, "updateAutoStartState") == oldUpdateAutoStartState

        result.stateRestored =
            safeRead(core, "dungeonActive") == oldDungeonActive
            and safeRead(core, "dungeonTeleportLockUntil") == oldDungeonTeleportLockUntil
            and safeRead(core, "priorityOwner") == oldPriorityOwner
            and safeRead(dungeon, "runActive") == oldRunActive
            and safeRead(dungeon, "runProtectionActive") == oldRunProtectionActive
            and safeRead(dungeon, "lastDungeonActivityAt") == oldLastDungeonActivityAt
            and safeRead(dungeon, "runProtectionStartedAt") == oldRunProtectionStartedAt
            and safeRead(dungeon, "runProtectionHeldLogged") == oldRunProtectionHeldLogged
            and safeRead(dungeon, "runEnding") == oldRunEnding
            and safeRead(dungeon, "runEndToken") == oldRunEndToken
    end

    result.ran = true

    rawset(dungeon, "isInsideActive", function()
        return false
    end)
    rawset(dungeon, "hasDungeonTargets", function()
        return true
    end)
    rawset(dungeon, "updateAutoStartState", function()
        return false
    end)
    rawset(dungeon, "wasInside", false)
    rawset(dungeon, "forceEndedUntil", 0)
    rawset(dungeon, "runActive", false)
    rawset(dungeon, "runProtectionActive", false)
    rawset(dungeon, "lastDungeonActivityAt", 0)
    rawset(dungeon, "runProtectionStartedAt", 0)
    rawset(dungeon, "runProtectionHeldLogged", false)
    rawset(dungeon, "runEnding", false)
    rawset(dungeon, "runEndToken", 0)

    rawset(core, "dungeonActive", false)
    rawset(core, "dungeonTeleportLockUntil", 0)
    rawset(core, "priorityOwner", nil)

    local presenceOk, presence = pcall(isDungeonPresenceActive)
    result.presenceCallOk = presenceOk
    result.fallbackPresenceOk = presenceOk and presence == true or false

    local refreshOk, refreshResult = pcall(refreshPresenceLock)
    result.refreshCallOk = refreshOk
    result.refreshReturnedTrue = refreshOk and refreshResult == true or false

    local lockUntil = tonumber(safeRead(core, "dungeonTeleportLockUntil"))
    result.lockRefreshedByFallback = lockUntil ~= nil and lockUntil > os.clock()
    result.runProtectionActiveAfterRefresh = safeRead(dungeon, "runProtectionActive") == true
    result.prioritySetToDungeon = safeRead(core, "priorityOwner") == "dungeon"

    if not presenceOk then
        result.error = tostring(presence)
    elseif not refreshOk then
        result.error = tostring(refreshResult)
    end

    local probeOk =
        result.presenceCallOk
        and result.fallbackPresenceOk
        and result.refreshCallOk
        and result.refreshReturnedTrue
        and result.lockRefreshedByFallback
        and result.runProtectionActiveAfterRefresh
        and result.prioritySetToDungeon

    restore()
    result.ok = probeOk and result.stateRestored and result.functionsRestored
    return result
end

local function controlledDungeonRunProtectionProbe(core, dungeon)
    local markRunActive = safeRead(dungeon, "markRunActive")
    local markRunEnded = safeRead(dungeon, "markRunEnded")
    local isRunProtectionActive = safeRead(dungeon, "isRunProtectionActive")
    local refreshPresenceLock = safeRead(dungeon, "refreshPresenceLock")
    local isWorldTeleportBlocked = safeRead(core, "isWorldTeleportBlocked")

    local result = {
        ran = false,
        ok = false,
        markRunActive = type(markRunActive) == "function",
        markRunEnded = type(markRunEnded) == "function",
        isRunProtectionActive = type(isRunProtectionActive) == "function",
        refreshPresenceLock = type(refreshPresenceLock) == "function",
        isWorldTeleportBlocked = type(isWorldTeleportBlocked) == "function",
        markActiveCallOk = false,
        protectedAfterMark = false,
        blockedByProtection = false,
        refreshCallOk = false,
        refreshHeldProtection = false,
        prioritySetToDungeon = false,
        markEndedCallOk = false,
        releasedAfterEnd = false,
        stateRestored = false,
        functionsRestored = false,
        error = nil,
    }

    if type(markRunActive) ~= "function"
        or type(markRunEnded) ~= "function"
        or type(isRunProtectionActive) ~= "function"
        or type(refreshPresenceLock) ~= "function"
        or type(isWorldTeleportBlocked) ~= "function" then
        result.error = "missing dungeon run protection function"
        return result
    end

    local oldIsInsideActive = safeRead(dungeon, "isInsideActive")
    local oldHasDungeonTargets = safeRead(dungeon, "hasDungeonTargets")
    local oldUpdateAutoStartState = safeRead(dungeon, "updateAutoStartState")
    local oldWasInside = safeRead(dungeon, "wasInside")
    local oldForceEndedUntil = safeRead(dungeon, "forceEndedUntil")
    local oldRunActive = safeRead(dungeon, "runActive")
    local oldRunProtectionActive = safeRead(dungeon, "runProtectionActive")
    local oldLastDungeonActivityAt = safeRead(dungeon, "lastDungeonActivityAt")
    local oldRunProtectionStartedAt = safeRead(dungeon, "runProtectionStartedAt")
    local oldRunProtectionHeldLogged = safeRead(dungeon, "runProtectionHeldLogged")
    local oldRunEnding = safeRead(dungeon, "runEnding")
    local oldRunEndToken = safeRead(dungeon, "runEndToken")
    local oldAutoStartCooldownUntil = safeRead(dungeon, "autoStartCooldownUntil")
    local oldAutoStartRetryToken = safeRead(dungeon, "autoStartRetryToken")

    local oldDungeonActive = safeRead(core, "dungeonActive")
    local oldDungeonTeleportLockUntil = safeRead(core, "dungeonTeleportLockUntil")
    local oldPriorityOwner = safeRead(core, "priorityOwner")
    local coreState = safeRead(core, "state")
    local oldAutoCycleState = type(coreState) == "table" and rawget(coreState, "auto_cycle") or nil

    local function restore()
        rawset(dungeon, "isInsideActive", oldIsInsideActive)
        rawset(dungeon, "hasDungeonTargets", oldHasDungeonTargets)
        rawset(dungeon, "updateAutoStartState", oldUpdateAutoStartState)
        rawset(dungeon, "wasInside", oldWasInside)
        rawset(dungeon, "forceEndedUntil", oldForceEndedUntil)
        rawset(dungeon, "runActive", oldRunActive)
        rawset(dungeon, "runProtectionActive", oldRunProtectionActive)
        rawset(dungeon, "lastDungeonActivityAt", oldLastDungeonActivityAt)
        rawset(dungeon, "runProtectionStartedAt", oldRunProtectionStartedAt)
        rawset(dungeon, "runProtectionHeldLogged", oldRunProtectionHeldLogged)
        rawset(dungeon, "runEnding", oldRunEnding)
        rawset(dungeon, "runEndToken", oldRunEndToken)
        rawset(dungeon, "autoStartCooldownUntil", oldAutoStartCooldownUntil)
        rawset(dungeon, "autoStartRetryToken", oldAutoStartRetryToken)

        rawset(core, "dungeonActive", oldDungeonActive)
        rawset(core, "dungeonTeleportLockUntil", oldDungeonTeleportLockUntil)
        rawset(core, "priorityOwner", oldPriorityOwner)
        if type(coreState) == "table" then
            rawset(coreState, "auto_cycle", oldAutoCycleState)
        end

        result.functionsRestored =
            safeRead(dungeon, "isInsideActive") == oldIsInsideActive
            and safeRead(dungeon, "hasDungeonTargets") == oldHasDungeonTargets
            and safeRead(dungeon, "updateAutoStartState") == oldUpdateAutoStartState

        result.stateRestored =
            safeRead(core, "dungeonActive") == oldDungeonActive
            and safeRead(core, "dungeonTeleportLockUntil") == oldDungeonTeleportLockUntil
            and safeRead(core, "priorityOwner") == oldPriorityOwner
            and safeRead(dungeon, "wasInside") == oldWasInside
            and safeRead(dungeon, "forceEndedUntil") == oldForceEndedUntil
            and safeRead(dungeon, "runActive") == oldRunActive
            and safeRead(dungeon, "runProtectionActive") == oldRunProtectionActive
            and safeRead(dungeon, "lastDungeonActivityAt") == oldLastDungeonActivityAt
            and safeRead(dungeon, "runProtectionStartedAt") == oldRunProtectionStartedAt
            and safeRead(dungeon, "runProtectionHeldLogged") == oldRunProtectionHeldLogged
            and safeRead(dungeon, "runEnding") == oldRunEnding
            and safeRead(dungeon, "runEndToken") == oldRunEndToken
            and safeRead(dungeon, "autoStartCooldownUntil") == oldAutoStartCooldownUntil
            and safeRead(dungeon, "autoStartRetryToken") == oldAutoStartRetryToken
            and (type(coreState) ~= "table" or rawget(coreState, "auto_cycle") == oldAutoCycleState)
    end

    result.ran = true

    rawset(dungeon, "isInsideActive", function()
        return false
    end)
    rawset(dungeon, "hasDungeonTargets", function()
        return false
    end)
    rawset(dungeon, "updateAutoStartState", function()
        return false
    end)
    rawset(dungeon, "wasInside", false)
    rawset(dungeon, "forceEndedUntil", 0)
    rawset(dungeon, "runActive", false)
    rawset(dungeon, "runProtectionActive", false)
    rawset(dungeon, "lastDungeonActivityAt", 0)
    rawset(dungeon, "runProtectionStartedAt", 0)
    rawset(dungeon, "runProtectionHeldLogged", false)
    rawset(dungeon, "runEnding", false)
    rawset(dungeon, "runEndToken", 0)
    rawset(dungeon, "autoStartCooldownUntil", 0)
    rawset(dungeon, "autoStartRetryToken", 0)

    rawset(core, "dungeonActive", false)
    rawset(core, "dungeonTeleportLockUntil", 0)
    rawset(core, "priorityOwner", nil)
    if type(coreState) == "table" then
        rawset(coreState, "auto_cycle", false)
    end

    local markActiveOk, markActiveErr = pcall(markRunActive, "health probe")
    result.markActiveCallOk = markActiveOk
    if not markActiveOk then
        result.error = tostring(markActiveErr)
        restore()
        return result
    end

    local protectedOk, protected = pcall(isRunProtectionActive)
    result.protectedAfterMark = protectedOk and protected == true

    rawset(core, "dungeonActive", false)
    rawset(core, "dungeonTeleportLockUntil", 0)
    rawset(core, "priorityOwner", nil)

    local blockedOk, blocked = pcall(isWorldTeleportBlocked)
    result.blockedByProtection = blockedOk and blocked == true
    result.prioritySetToDungeon = safeRead(core, "priorityOwner") == "dungeon"

    rawset(core, "dungeonActive", false)
    rawset(core, "dungeonTeleportLockUntil", 0)
    rawset(core, "priorityOwner", nil)

    local refreshOk, refreshResult = pcall(refreshPresenceLock)
    result.refreshCallOk = refreshOk
    result.refreshHeldProtection = refreshOk
        and refreshResult == true
        and safeRead(dungeon, "runProtectionActive") == true
        and tonumber(safeRead(core, "dungeonTeleportLockUntil")) ~= nil
        and tonumber(safeRead(core, "dungeonTeleportLockUntil")) > os.clock()

    local markEndedOk, markEndedErr = pcall(markRunEnded, "health probe")
    result.markEndedCallOk = markEndedOk
    if not markEndedOk then
        result.error = tostring(markEndedErr)
        restore()
        return result
    end

    local releasedOk, released = pcall(isRunProtectionActive)
    result.releasedAfterEnd = releasedOk and released == false and safeRead(dungeon, "runProtectionActive") == false

    if not protectedOk then
        result.error = tostring(protected)
    elseif not blockedOk then
        result.error = tostring(blocked)
    elseif not refreshOk then
        result.error = tostring(refreshResult)
    end

    local probeOk =
        result.markActiveCallOk
        and result.protectedAfterMark
        and result.blockedByProtection
        and result.refreshCallOk
        and result.refreshHeldProtection
        and result.prioritySetToDungeon
        and result.markEndedCallOk
        and result.releasedAfterEnd

    restore()
    result.ok = probeOk and result.stateRestored and result.functionsRestored
    return result
end

local function getRequestFunction()
    if type(request) == "function" then
        return request
    end

    if type(http_request) == "function" then
        return http_request
    end

    if syn and type(syn.request) == "function" then
        return syn.request
    end

    if http and type(http.request) == "function" then
        return http.request
    end

    if fluxus and type(fluxus.request) == "function" then
        return fluxus.request
    end

    return nil
end

local function postJson(url, payload)
    local req = getRequestFunction()

    if not req then
        return false, "Executor does not expose request/http_request/syn.request/http.request."
    end

    local body = HttpService:JSONEncode(payload)

    local ok, response = pcall(function()
        return req({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json",
            },
            Body = body,
        })
    end)

    if not ok then
        return false, tostring(response)
    end

    if type(response) ~= "table" then
        return false, "Request returned a non-table response."
    end

    local status = tonumber(response.StatusCode or response.status_code or response.status or 0) or 0
    local responseBody = response.Body or response.body or ""

    if status ~= 0 and (status < 200 or status >= 300) then
        return false, "API returned HTTP " .. tostring(status) .. ": " .. tostring(responseBody):sub(1, 400)
    end

    local decodedOk, decoded = pcall(function()
        return HttpService:JSONDecode(responseBody)
    end)

    if not decodedOk then
        return false, "API returned invalid JSON: " .. tostring(responseBody):sub(1, 400)
    end

    return true, decoded
end

local player = Players.LocalPlayer
local HS, runtimeLabel = findRuntime()

local Core = HS and getPath(HS, { "Core" }) or nil
local state = HS and getPath(HS, { "Core", "state" }) or nil
local inputs = HS and getPath(HS, { "Core", "inputState" }) or nil
local uiData = HS and getPath(HS, { "UI", "UI_DATA" }) or nil
local autoCycle = HS and getPath(HS, { "AutoCycle" }) or nil
local Dungeon = HS and getPath(HS, { "Dungeon" }) or nil
local dungeonIsInsideActive = HS and getPath(HS, { "Dungeon", "isInsideActive" }) or nil
local dungeonHasDungeonTargets = HS and getPath(HS, { "Dungeon", "hasDungeonTargets" }) or nil
local dungeonIsDungeonPresenceActive = HS and getPath(HS, { "Dungeon", "isDungeonPresenceActive" }) or nil
local dungeonIsRunProtectionActive = HS and getPath(HS, { "Dungeon", "isRunProtectionActive" }) or nil

local payload = {
    schema = 1,

    place = {
        placeId = game.PlaceId,
        jobId = game.JobId,
        gameId = game.GameId,
    },

    player = {
        userId = player and player.UserId or 0,
        name = player and player.Name or "unknown",
    },

    runtime = {
        found = HS ~= nil,
        label = runtimeLabel,

        meta = {
            name = HS and getPath(HS, { "Meta", "name" }) or nil,
            version = HS and getPath(HS, { "Meta", "version" }) or nil,
            build = HS and getPath(HS, { "Meta", "build" }) or nil,
            runtimeKey = HS and getPath(HS, { "Meta", "runtimeKey" }) or nil,
            expectedLoader = HS and getPath(HS, { "Meta", "expectedLoader" }) or nil,
            loadedAtUnix = HS and getPath(HS, { "Meta", "loadedAtUnix" }) or nil,
        },
    },

    safety = {
        sessionSaveCalled = false,
        sessionLoadCalled = false,
        uiRenderCalled = false,
        remotesFired = false,
        teleportsStarted = false,
        farmingLoopsStarted = false,
        webhookUrlsHidden = true,
    },

    checks = {
        core = {
            table = HS and isTable(HS, { "Core" }) or false,
            state = HS and isTable(HS, { "Core", "state" }) or false,
            callbacks = HS and isTable(HS, { "Core", "callbacks" }) or false,
            selectionState = HS and isTable(HS, { "Core", "selectionState" }) or false,
            sliderState = HS and isTable(HS, { "Core", "sliderState" }) or false,
            inputState = HS and isTable(HS, { "Core", "inputState" }) or false,

            loopWhile = HS and isFunction(HS, { "Core", "loopWhile" }) or false,
            teleportWorld = HS and isFunction(HS, { "Core", "teleportWorld" }) or false,
            lockWorldTeleports = HS and isFunction(HS, { "Core", "lockWorldTeleports" }) or false,
            isWorldTeleportBlocked = HS and isFunction(HS, { "Core", "isWorldTeleportBlocked" }) or false,
            getClientDataManager = HS and isFunction(HS, { "Core", "getClientDataManager" }) or false,
            uiActionRemote = HS and exists(HS, { "Core", "UIActionRemote" }) or false,
            uiActionRemoteType = HS and valueKind(getPath(HS, { "Core", "UIActionRemote" })) or "nil",

            activeLoops = countKeys(Core and safeRead(Core, "activeLoops")),

            loopHealth = {
                dungeon_presence_watchdog = Core and loopStatus(Core, "dungeon_presence_watchdog") or nil,
                swing = Core and loopStatus(Core, "swing") or nil,
                sell = Core and loopStatus(Core, "sell") or nil,
                bossdmg = Core and loopStatus(Core, "bossdmg") or nil,
                claim_egg = Core and loopStatus(Core, "claim_egg") or nil,
            },
        },

        session = {
            table = HS and isTable(HS, { "Session" }) or false,
            save = HS and isFunction(HS, { "Session", "save" }) or false,
            load = HS and isFunction(HS, { "Session", "load" }) or false,
            suppressSave = HS and exists(HS, { "Session", "suppressSave" }) or false,
            suppressSaveValue = HS and tostring(getPath(HS, { "Session", "suppressSave" })) or nil,
        },

        ui = {
            table = HS and isTable(HS, { "UI" }) or false,
            uiData = HS and isTable(HS, { "UI", "UI_DATA" }) or false,
            renderContent = HS and isFunction(HS, { "UI", "renderContent" }) or false,

            tabs = {
                farming = uiData and rawget(uiData, "farming") ~= nil or false,
                upgrades = uiData and rawget(uiData, "upgrades") ~= nil or false,
                elements = uiData and rawget(uiData, "elements") ~= nil or false,
                Dungeon = uiData and rawget(uiData, "Dungeon") ~= nil or false,
                merchant = uiData and rawget(uiData, "merchant") ~= nil or false,
                logs = uiData and rawget(uiData, "logs") ~= nil or false,
                misc = uiData and rawget(uiData, "misc") ~= nil or false,
                session = uiData and rawget(uiData, "session") ~= nil or false,
                standalone_scripts = uiData and rawget(uiData, "standalone_scripts") ~= nil or false,
            },

            miscTestingMode = findUiItemKey(getPath(HS, { "UI", "UI_DATA", "misc", "items" }), "testing_mode"),

            standaloneScriptsGated =
                type(getPath(HS, { "UI", "UI_DATA", "standalone_scripts" })) == "table"
                and getPath(HS, { "UI", "UI_DATA", "standalone_scripts", "testingOnly" }) == true,
        },

        farming = {
            table = HS and isTable(HS, { "Farming" }) or false,
            startBossDmg = HS and isFunction(HS, { "Farming", "startBossDmg" }) or false,
            startBoss = HS and isFunction(HS, { "Farming", "startBoss" }) or false,
            isBossFarmActive = HS and isFunction(HS, { "Farming", "isBossFarmActive" }) or false,

            bossdmgStateKey = type(state) == "table" and rawget(state, "bossdmg") ~= nil or false,
            bossdmgUiToggle = findUiItemKey(getPath(HS, { "UI", "UI_DATA", "upgrades", "items" }), "bossdmg"),
        },

        dungeon = {
            table = HS and isTable(HS, { "Dungeon" }) or false,
            isInsideActive = HS and isFunction(HS, { "Dungeon", "isInsideActive" }) or false,
            hasDungeonTargets = HS and isFunction(HS, { "Dungeon", "hasDungeonTargets" }) or false,
            isDungeonPresenceActive = HS and isFunction(HS, { "Dungeon", "isDungeonPresenceActive" }) or false,
            markRunActive = HS and isFunction(HS, { "Dungeon", "markRunActive" }) or false,
            markRunEnding = HS and isFunction(HS, { "Dungeon", "markRunEnding" }) or false,
            markRunEnded = HS and isFunction(HS, { "Dungeon", "markRunEnded" }) or false,
            isRunProtectionActive = HS and isFunction(HS, { "Dungeon", "isRunProtectionActive" }) or false,
            scheduleRunEnd = HS and isFunction(HS, { "Dungeon", "scheduleRunEnd" }) or false,
            refreshPresenceLock = HS and isFunction(HS, { "Dungeon", "refreshPresenceLock" }) or false,
            startPresenceWatchdog = HS and isFunction(HS, { "Dungeon", "startPresenceWatchdog" }) or false,
            tryClaimEggs = HS and isFunction(HS, { "Dungeon", "tryClaimEggs" }) or false,
            scanIncubatorSlots = HS and isFunction(HS, { "Dungeon", "scanIncubatorSlots" }) or false,
            validSpawners = HS and isTable(HS, { "Dungeon", "VALID_SPAWNERS" }) or false,
            validTargets = HS and isTable(HS, { "Dungeon", "VALID_TARGETS" }) or false,

            maxIncubatorSlots = HS and getPath(HS, { "Dungeon", "MAX_INCUBATOR_SLOTS" }) or nil,
            forceClaimInterval = HS and getPath(HS, { "Dungeon", "FORCE_CLAIM_INTERVAL" }) or nil,
            startRemoteDelay = HS and getPath(HS, { "Dungeon", "START_REMOTE_DELAY" }) or nil,
            runProtectionTimeout = HS and getPath(HS, { "Dungeon", "RUN_PROTECTION_TIMEOUT" }) or nil,
            runProtectionActive = HS and getPath(HS, { "Dungeon", "runProtectionActive" }) == true or false,
            runActive = HS and getPath(HS, { "Dungeon", "runActive" }) == true or false,
            teleportProtection = Core and controlledTeleportLockProbe(Core) or nil,
            presenceFallbackProbe = Core and Dungeon and controlledDungeonPresenceFallbackProbe(Core, Dungeon) or nil,
            runProtectionProbe = Core and Dungeon and controlledDungeonRunProtectionProbe(Core, Dungeon) or nil,
        },

        logs = {
            table = HS and isTable(HS, { "Logs" }) or false,
            pets = HS and isTable(HS, { "Logs", "Pets" }) or false,
            discordMonitor = HS and isTable(HS, { "Logs", "DiscordMonitor" }) or false,
            dungeon = HS and isTable(HS, { "Logs", "Dungeon" }) or false,

            petsSyncConnection = HS and isFunction(HS, { "Logs", "Pets", "syncConnection" }) or false,
            petsConnectionActive = HS and exists(HS, { "Logs", "Pets", "Connection" }) or false,

            discordMonitorSync = HS and isFunction(HS, { "Logs", "DiscordMonitor", "sync" }) or false,
            discordMonitorThreadActive = HS and exists(HS, { "Logs", "DiscordMonitor", "Thread" }) or false,
        },

        autoCycle = {
            table = HS and isTable(HS, { "AutoCycle" }) or false,
            positions = HS and isTable(HS, { "AutoCycle", "POSITIONS" }) or false,
            order = HS and isTable(HS, { "AutoCycle", "ORDER" }) or false,

            elementPositions = {
                Fire = autoCycle and hasElementPositions(autoCycle, "Fire") or false,
                Water = autoCycle and hasElementPositions(autoCycle, "Water") or false,
                Earth = autoCycle and hasElementPositions(autoCycle, "Earth") or false,
                Plasma = autoCycle and hasElementPositions(autoCycle, "Plasma") or false,
            },
        },

        elementZonePull = {
            table = HS and isTable(HS, { "ElementZonePull" }) or false,
        },

        merchant = {
            table = HS and isTable(HS, { "Merchant" }) or false,
            stateKey = HS and getPath(HS, { "Merchant", "STATE_KEY" }) or nil,
            buySelected = HS and isFunction(HS, { "Merchant", "buySelected" }) or false,
        },

        eventSubsystem = buildEventSubsystemFacts(HS),

        petdexEventEggs = buildPetdexEventEggFacts(HS),
    },

    safeCalls = {
        dungeonIsInsideActive = RUN_SAFE_CALL_TESTS and safeCall(dungeonIsInsideActive) or {
            ran = false,
            ok = false,
            result = nil,
            error = "safe calls disabled",
        },
        dungeonHasDungeonTargets = RUN_SAFE_CALL_TESTS and safeCall(dungeonHasDungeonTargets) or {
            ran = false,
            ok = false,
            result = nil,
            error = "safe calls disabled",
        },
        dungeonIsDungeonPresenceActive = RUN_SAFE_CALL_TESTS and safeCall(dungeonIsDungeonPresenceActive) or {
            ran = false,
            ok = false,
            result = nil,
            error = "safe calls disabled",
        },
        dungeonIsRunProtectionActive = RUN_SAFE_CALL_TESTS and safeCall(dungeonIsRunProtectionActive) or {
            ran = false,
            ok = false,
            result = nil,
            error = "safe calls disabled",
        },
    },

    stateSummary = {
        enabledToggles = listEnabledToggles(state),

        sensitiveInputs = {
            discord_monitor_webhook_url = inputStatus(inputs, "discord_monitor_webhook_url"),
            pet_webhook_url = inputStatus(inputs, "pet_webhook_url"),
        },
    },
}

print("[Heartsteel Health Check] Sending probe to API...")
print("[Heartsteel Health Check] Endpoint: " .. ENDPOINT)

local ok, result = postJson(ENDPOINT, payload)

if not ok then
    warn("[Heartsteel Health Check] API request failed: " .. tostring(result))
    return
end

print("")
print("[Heartsteel Health Check]")
print("Verdict: " .. tostring(result.verdict or "unknown"))
print("Warnings: " .. tostring(result.warnings or 0))
print("Errors: " .. tostring(result.errors or 0))

if PRINT_API_MESSAGES and type(result.messages) == "table" then
    print("")
    print("Messages:")

    for _, message in ipairs(result.messages) do
        print(tostring(message))
    end
end
