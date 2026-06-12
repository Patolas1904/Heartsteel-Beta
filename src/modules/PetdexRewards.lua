return function(HS, S)
    local Rewards = HS.PetdexRewards or {}
    HS.PetdexRewards = Rewards

    local Core    = HS.Core

    Rewards.STATE_KEY   = "auto_petdex_rewards"
    Rewards.CLAIM_DELAY = 0.3
    Rewards.SCAN_DELAY  = 5
    Rewards.ClientData  = nil
    Rewards.rewardInfo  = nil
    Rewards.rewardList  = {}
    Rewards.running     = false
    Rewards.thread      = nil
    Rewards.runId       = 0
    Rewards.statusLabel = nil
    Rewards.status      = {
        state="Idle", unlocked=0, completedEggs=0, claimed=0, total=0, nextReward="-",
    }

    function Rewards.init()
        if Rewards.ClientData and #Rewards.rewardList > 0 then return true end
        local ok, data, rewardInfo = pcall(function()
            local clientData = (HS.PetdexFarm and HS.PetdexFarm.ClientData) or Core.getClientDataManager()
            local info = require(S.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetdexRewardInfo"))
            return clientData, info
        end)
        if ok and data and rewardInfo and type(rewardInfo.Items) == "table" then
            Rewards.ClientData = data
            Rewards.rewardInfo = rewardInfo
            Rewards.buildRewardList()
            return true
        end
        Core.debugLog("Petdex rewards init failed:", data, rewardInfo)
        return false
    end

    function Rewards.getData()
        local cd = Rewards.ClientData
        return cd and cd.Data or {}
    end

    function Rewards.buildRewardList()
        table.clear(Rewards.rewardList)
        local items = Rewards.rewardInfo and Rewards.rewardInfo.Items
        if type(items) ~= "table" then return end

        for key, item in pairs(items) do
            if type(key) == "string" and type(item) == "table" then
                local petsNeeded = tonumber(item.PetsNeeded)
                local eggsNeeded = tonumber(item.EggsNeeded)
                if petsNeeded or eggsNeeded then
                    local order = tonumber(item.Order)
                    local needed = petsNeeded or eggsNeeded or 0
                    Rewards.rewardList[#Rewards.rewardList + 1] = {
                        Key=key,
                        Data=item,
                        PetsNeeded=petsNeeded,
                        EggsNeeded=eggsNeeded,
                        Order=order,
                        Needed=needed,
                        key=key,
                        petsNeeded=petsNeeded,
                        eggsNeeded=eggsNeeded,
                        order=order,
                        needed=needed,
                    }
                end
            end
        end

        table.sort(Rewards.rewardList, function(a, b)
            local ao = a.Order or a.order or math.huge
            local bo = b.Order or b.order or math.huge
            if ao ~= bo then return ao < bo end
            local an = a.Needed or a.needed or 0
            local bn = b.Needed or b.needed or 0
            if an ~= bn then return an < bn end
            return (a.Key or a.key) < (b.Key or b.key)
        end)

        Core.debugLog("Petdex rewards loaded:", #Rewards.rewardList)
    end

    function Rewards.getUnlockedCount()
        local index = Rewards.getData().Index
        if type(index) ~= "table" then return 0 end

        local owned = {}
        local seenTables = {}

        local function markPetName(name)
            if type(name) == "string" and name ~= "" then
                owned[name] = true
            end
        end

        local function scan(tbl)
            if seenTables[tbl] then return end
            seenTables[tbl] = true

            for key, value in pairs(tbl) do
                if value == true then markPetName(key) end
                if type(value) == "string" then
                    markPetName(value)
                elseif type(value) == "table" then
                    markPetName(value.Name or value.PetName or value.petName or value.Pet or value.pet)
                    scan(value)
                end
            end
        end

        scan(index)

        local count = 0
        for _ in pairs(owned) do
            count += 1
        end

        return count > 0 and count or #index
    end

    function Rewards.getCompletedEggCount()
        local Petdex = HS.PetdexFarm
        if not Petdex or not Petdex.init or not Petdex.init() then return 0 end

        local completedNormal = 0
        local completedEvent = 0
        local countedEggs = {}
        local ownedPets = Petdex.getOwnedPets()

        for _, eggName in ipairs(Petdex.eggOrder or {}) do
            -- Egg rewards require a full regular egg completion. The Petdex skip
            -- slider is intentionally ignored here; secret pets are not required.
            local pets, required = Petdex.getCountedPets(eggName, true)

            if required > 0 then
                local complete = true
                for i = 1, required do
                    local pet = pets[i]
                    if not pet or not ownedPets[pet.name] then
                        complete = false
                        break
                    end
                end

                if complete then
                    completedNormal += 1
                    countedEggs[eggName] = true
                end
            end
        end

        for _, eggName in ipairs(Petdex.eventEggOrder or {}) do
            if not countedEggs[eggName] then
                local _, _, counted, _, _, complete = Petdex.evaluateEventEgg(eggName, ownedPets, true)
                if counted > 0 and complete then
                    completedEvent += 1
                    countedEggs[eggName] = true
                end
            end
        end

        local total = completedNormal + completedEvent
        Core.debugLog("Petdex Rewards: completed normal eggs =", completedNormal)
        Core.debugLog("Petdex Rewards: completed event eggs =", completedEvent)
        Core.debugLog("Petdex Rewards: total completed eggs =", total)
        return total
    end

    function Rewards.getClaimedSet()
        local claimed = Rewards.getData().PetdexRewardsClaimed
        local set = {}
        if type(claimed) ~= "table" then return set end

        local function markReward(value)
            if type(value) == "number" then
                set["Pets" .. tostring(value)] = true
            elseif type(value) == "string" then
                if value:match("^Pets%d+$") or value:match("^Eggs%d+$") then
                    set[value] = true
                else
                    local rewardValue = tonumber(value:match("(%d+)"))
                    if rewardValue then set["Pets" .. tostring(rewardValue)] = true end
                end
            end
        end

        for key, value in pairs(claimed) do
            if value == true then
                markReward(key)
            elseif value ~= false and value ~= nil then
                if type(key) ~= "number" then markReward(key) end
                markReward(value)
            end
        end
        return set
    end

    function Rewards.claimReward(rewardKey)
        if type(rewardKey) ~= "string" or rewardKey == "" then
            Core.debugLog("Petdex reward skipped:", tostring(rewardKey))
            return false
        end

        Core.debugLog("Petdex Rewards: claiming", rewardKey)
        local ok, err = pcall(function()
            Core.UIActionRemote:FireServer("ClaimPetdexReward", rewardKey)
        end)
        if not ok then
            Core.debugLog("Petdex reward claim failed:", rewardKey, tostring(err))
        end
        return ok
    end

    function Rewards.makeSnapshot(unlocked, completedEggs, claimedSet)
        local claimedCount = 0
        local nextReward = "-"
        local claimable = {}

        for _, reward in ipairs(Rewards.rewardList) do
            local rewardKey = reward.Key or reward.key
            local petsNeeded = reward.PetsNeeded or reward.petsNeeded
            local eggsNeeded = reward.EggsNeeded or reward.eggsNeeded

            if type(rewardKey) ~= "string" or rewardKey == "" then
                Core.debugLog("Petdex reward skipped:", tostring(rewardKey))
                continue
            end

            if claimedSet[rewardKey] then
                claimedCount += 1
            elseif nextReward == "-" then
                nextReward = rewardKey
            end

            local canClaim = false
            if petsNeeded then
                canClaim = unlocked >= petsNeeded
            elseif eggsNeeded then
                canClaim = completedEggs >= eggsNeeded
            end

            if canClaim and not claimedSet[rewardKey] then
                claimable[#claimable + 1] = rewardKey
            end
        end

        return {
            unlocked=unlocked,
            completedEggs=completedEggs,
            claimed=claimedCount,
            total=#Rewards.rewardList,
            nextReward=nextReward,
            claimable=claimable,
            claimedSet=claimedSet,
        }
    end

    function Rewards.getSnapshot()
        if not Rewards.init() then
            return {unlocked=0, completedEggs=0, claimed=0, total=0, nextReward="-", claimable={}}
        end
        local unlocked = Rewards.getUnlockedCount()
        local completedEggs = Rewards.getCompletedEggCount()
        local claimedSet = Rewards.getClaimedSet()
        local snapshot = Rewards.makeSnapshot(unlocked, completedEggs, claimedSet)
        Core.debugLog(
            "Petdex rewards scan:",
            "loaded=", snapshot.total,
            "unlockedPets=", unlocked,
            "completedEggs=", completedEggs,
            "claimed=", snapshot.claimed
        )
        return snapshot
    end

    function Rewards.setStatus(state, snapshot)
        local snap = snapshot or Rewards.getSnapshot()
        Rewards.status.state = state or Rewards.status.state
        Rewards.status.unlocked = snap.unlocked or 0
        Rewards.status.completedEggs = snap.completedEggs or 0
        Rewards.status.claimed = snap.claimed or 0
        Rewards.status.total = snap.total or #Rewards.rewardList
        Rewards.status.nextReward = snap.nextReward or "-"
        Rewards.updateStatusLabel()
    end

    function Rewards.getStatusText()
        local s = Rewards.status
        return string.format(
            "Petdex Rewards: %s\nUnlocked Pets: %d\nCompleted Eggs: %d\nClaimed: %d / %d\nNext Reward: %s",
            s.state, s.unlocked, s.completedEggs or 0, s.claimed, s.total, s.nextReward
        )
    end

    function Rewards.updateStatusLabel()
        local lbl = Rewards.statusLabel
        if lbl and lbl.Parent then lbl.Text = Rewards.getStatusText() end
    end

    function Rewards.refreshStatus()
        if Rewards.running then
            local state = Rewards.status.state ~= "Idle" and Rewards.status.state or "Running"
            Rewards.setStatus(state)
        else
            Rewards.setStatus(Rewards.status.state or "Idle")
        end
    end

    function Rewards.stop()
        Rewards.runId += 1
        Rewards.running = false
        Rewards.thread = nil
        Rewards.setStatus("Idle")
        Core.clearCurrentAction("Claiming Petdex Rewards")
    end

    function Rewards.start()
        if Rewards.running then return end
        if not Rewards.init() then
            Core.state[Rewards.STATE_KEY] = false
            HS.Session.save()
            if Core.activeTab == "pets" then HS.UI.renderContent() end
            return
        end

        Rewards.running = true
        Rewards.runId += 1
        local runId = Rewards.runId
        Rewards.thread = task.spawn(function()
            while Core.alive and Core.state[Rewards.STATE_KEY] and Rewards.running and Rewards.runId == runId do
                local snapshot = Rewards.getSnapshot()
                local stateText = snapshot.claimed >= snapshot.total and "Complete" or "Waiting"
                Rewards.setStatus(#snapshot.claimable > 0 and "Running" or stateText, snapshot)

                if #snapshot.claimable > 0 then
                    local unlocked = snapshot.unlocked or 0
                    local completedEggs = snapshot.completedEggs or 0
                    local claimedSet = snapshot.claimedSet or {}
                    for _, rewardKey in ipairs(snapshot.claimable) do
                        if not (Core.alive and Core.state[Rewards.STATE_KEY] and Rewards.running and Rewards.runId == runId) then
                            break
                        end
                        if not claimedSet[rewardKey] then
                            Core.setCurrentAction("Claiming Petdex Rewards", math.max(2, Rewards.CLAIM_DELAY + 1))
                            if Rewards.claimReward(rewardKey) then
                                claimedSet[rewardKey] = true
                                task.wait(Rewards.CLAIM_DELAY)
                                Rewards.setStatus("Running", Rewards.makeSnapshot(unlocked, completedEggs, claimedSet))
                            end
                        else
                            Core.debugLog("Petdex reward already claimed:", rewardKey)
                        end
                    end
                end

                local elapsed = 0
                while elapsed < Rewards.SCAN_DELAY and Core.alive and Core.state[Rewards.STATE_KEY] and Rewards.running and Rewards.runId == runId do
                    task.wait(0.5)
                    elapsed += 0.5
                end
            end

            if Rewards.runId ~= runId then return end
            Rewards.running = false
            if Rewards.status.state == "Running" or Rewards.status.state == "Waiting" then
                Rewards.setStatus("Idle")
            end
            Rewards.thread = nil
            Core.clearCurrentAction("Claiming Petdex Rewards")
        end)
    end
end
