return function(HS, S)
    local EggOpener = HS.EggOpener or {}
    HS.EggOpener = EggOpener

    local Core      = HS.Core

    EggOpener.STATE_KEY    = "auto_egg_opener"
    EggOpener.PAGE_SIZE    = 12
    EggOpener.HATCH_DELAY  = 0.35
    EggOpener.initialized  = false
    EggOpener.running      = false
    EggOpener.status       = "Idle"
    EggOpener.thread       = nil
    EggOpener.runId        = 0
    EggOpener.eggOrder     = {}
    EggOpener.ClientData   = nil
    EggOpener.statusLabel  = nil
    EggOpener.selection    = {
        eggName="-", page=1, slot=1, index=1, opened=0,
        valid=false, unlocked=false,
    }

    function EggOpener.init()
        if EggOpener.initialized then return true end
        local ok, err = pcall(function()
            local petsInfo = S.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetsInfo")
            local shopInfo = require(petsInfo:WaitForChild("PetShopInfo"))
            EggOpener.ClientData = Core.getClientDataManager()

            local ordered = {}
            for index, entry in pairs(shopInfo) do
                if type(entry) == "table" and entry.EggName then
                    ordered[#ordered + 1] = {index=tonumber(index) or tonumber(entry.Index or entry.index) or math.huge, eggName=entry.EggName}
                end
            end
            table.sort(ordered, function(a, b) return a.index < b.index end)

            table.clear(EggOpener.eggOrder)
            local seen = {}
            for _, entry in ipairs(ordered) do
                if not seen[entry.eggName] then
                    seen[entry.eggName] = true
                    EggOpener.eggOrder[#EggOpener.eggOrder + 1] = entry.eggName
                end
            end
        end)
        EggOpener.initialized = ok
        if not ok then
            Core.debugLog("Egg opener init failed:", err)
        end
        EggOpener.updateSelection()
        return ok
    end

    function EggOpener.getData()
        local cd = EggOpener.ClientData
        return cd and cd.Data or {}
    end

    function EggOpener.getOpenedTable()
        local opened = EggOpener.getData().EggsOpened
        return type(opened) == "table" and opened or {}
    end

    function EggOpener.getMaxPage()
        return math.max(1, math.ceil(#EggOpener.eggOrder / EggOpener.PAGE_SIZE))
    end

    function EggOpener.updateSelection()
        if not EggOpener.initialized then
            EggOpener.selection.eggName = "-"
            EggOpener.selection.valid = false
            EggOpener.updateStatusLabel()
            return
        end

        local maxPage = EggOpener.getMaxPage()
        local page = math.clamp(tonumber(Core.sliderState.egg_opener_page) or 1, 1, maxPage)
        local slot = math.clamp(tonumber(Core.sliderState.egg_opener_slot) or 1, 1, EggOpener.PAGE_SIZE)
        Core.sliderState.egg_opener_page = page
        Core.sliderState.egg_opener_slot = slot

        local index = ((page - 1) * EggOpener.PAGE_SIZE) + slot
        local eggName = EggOpener.eggOrder[index]
        local openedTable = EggOpener.getOpenedTable()
        local unlocked = eggName ~= nil and openedTable[eggName] ~= nil

        EggOpener.selection.page = page
        EggOpener.selection.slot = slot
        EggOpener.selection.index = index
        EggOpener.selection.eggName = eggName or "-"
        EggOpener.selection.opened = eggName and (tonumber(openedTable[eggName]) or 0) or 0
        EggOpener.selection.unlocked = unlocked == true
        EggOpener.selection.valid = unlocked == true
        EggOpener.updateStatusLabel()
    end

    function EggOpener.getStatusText()
        local s = EggOpener.selection
        local state = EggOpener.running and EggOpener.status or "Idle"
        if s.eggName ~= "-" and not s.unlocked then state = "Locked" end
        return string.format(
            "Auto Egg Opener: %s\nEgg: %s\nPage: %d\nSlot: %d\nOpened: %d",
            state, s.eggName, s.page, s.slot, s.opened
        )
    end

    function EggOpener.updateStatusLabel()
        local lbl = EggOpener.statusLabel
        if lbl and lbl.Parent then lbl.Text = EggOpener.getStatusText() end
    end

    function EggOpener.stop()
        EggOpener.runId += 1
        EggOpener.running = false
        EggOpener.status = "Idle"
        EggOpener.thread = nil
        Core.clearCurrentAction("Opening Selected Egg")
        EggOpener.updateStatusLabel()
        if not Core.state.petdex_auto_teleport and not Core.state.auto_petdex then
            Core.releasePriority("eggs")
        end
    end

    function EggOpener.start()
        if EggOpener.running then return end
        if not EggOpener.init() then
            Core.state[EggOpener.STATE_KEY] = false
            HS.Session.save()
            if Core.activeTab == "pets" then HS.UI.renderContent() end
            return
        end

        EggOpener.running = true
        EggOpener.status = "Running"
        EggOpener.runId += 1
        local runId = EggOpener.runId
        EggOpener.thread = task.spawn(function()
            while Core.alive and Core.state[EggOpener.STATE_KEY] and EggOpener.running and EggOpener.runId == runId do
                local s = EggOpener.selection
                if not HS.PetdexFarm.isInShop() then
                    if Core.state.petdex_auto_teleport then HS.PetdexFarm.teleportToShop() end
                    EggOpener.status = "Paused"
                    EggOpener.updateStatusLabel()
                    task.wait(HS.PetdexFarm.TELEPORT_DELAY or EggOpener.HATCH_DELAY)
                    continue
                end

                if s.valid and s.eggName ~= "-" then
                    if not Core.waitForPriority("eggs", function()
                        return Core.alive and Core.state[EggOpener.STATE_KEY] and EggOpener.running and EggOpener.runId == runId
                    end) then break end
                    if not Core.claimPriority("eggs") then
                        task.wait(EggOpener.HATCH_DELAY)
                        continue
                    end
                    EggOpener.status = "Running"
                    Core.setCurrentAction("Opening Selected Egg", math.max(2, EggOpener.HATCH_DELAY + 1))
                    pcall(function() Core.UIActionRemote:FireServer("BuyEgg", s.eggName) end)
                end
                task.wait(EggOpener.HATCH_DELAY)
                EggOpener.updateSelection()
            end
            if EggOpener.runId ~= runId then return end
            EggOpener.running = false
            EggOpener.status = "Idle"
            EggOpener.thread = nil
            Core.clearCurrentAction("Opening Selected Egg")
            EggOpener.updateStatusLabel()
        end)
    end
end
