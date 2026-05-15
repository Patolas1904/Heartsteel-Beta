return function(HS, S)
    local Pets = HS.Pets or {}
    HS.Pets = Pets

    local Core = HS.Core

    Pets.STATE_KEY       = "auto_craft_pets"
    Pets.ALLOW_EQUIPPED  = "auto_craft_allow_equipped"
    Pets.REQUIRED_COUNT  = 10
    Pets.SCAN_DELAY      = 1.5
    Pets.CRAFT_COOLDOWN  = 2.0
    Pets.DEBUG           = true
    Pets.statusLabel     = nil
    Pets.status          = "Auto Craft: waiting"

    function Pets.debugPrint(...)
        if not Pets.DEBUG or Core.state.debug_mode ~= true then return end
        local parts = {"[Heartsteel][Pets]"}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        print(table.concat(parts, " "))
    end

    function Pets.setStatus(text)
        Pets.status = text or Pets.status
        if Pets.statusLabel and Pets.statusLabel.Parent then
            Pets.statusLabel.Text = Pets.status
        end
    end

    function Pets.getInventoryFrame()
        local gui = Core.playerGui:FindFirstChild("MainGui")
        local otherFrames = gui and gui:FindFirstChild("OtherFrames")
        local petsInventory = otherFrames and otherFrames:FindFirstChild("PetsInventory")
        local frame = petsInventory and petsInventory:FindFirstChild("Frame")
        return frame and frame:FindFirstChild("ScrollingFrame")
    end

    function Pets.parseLevel(text)
        if type(text) ~= "string" then return 0 end
        return tonumber(text:match("(%d+)")) or 0
    end

    function Pets.isVisible(guiObject)
        return guiObject and guiObject:IsA("GuiObject") and guiObject.Visible == true
    end

    function Pets.getPetId(petFrame, button)
        local candidates = {
            petFrame.Name,
            petFrame:GetAttribute("PetID"),
            petFrame:GetAttribute("PetId"),
            petFrame:GetAttribute("ID"),
            button and button:GetAttribute("PetID"),
            button and button:GetAttribute("PetId"),
            button and button:GetAttribute("ID"),
        }

        for _, value in ipairs(candidates) do
            if value ~= nil and tostring(value) ~= "" then
                return tostring(value)
            end
        end
        return nil
    end

    function Pets.readPet(petFrame)
        if not (petFrame and petFrame:IsA("Frame") and petFrame.Visible) then return nil end
        local button = petFrame:FindFirstChild("Button")
        local holder = button and button:FindFirstChild("Holder")
        local flatPet = holder and holder:FindFirstChild("FlatPet")
        local underlay = holder and holder:FindFirstChild("Underlay")
        local levelText = button and button:FindFirstChild("LevelText")
        local locked = button and button:FindFirstChild("Locked")
        local equipped = button and button:FindFirstChild("Equipped")
        local petId = Pets.getPetId(petFrame, button)
        local petImage = flatPet and flatPet.Image or "N/A"
        local underlayImage = underlay and underlay.Image or "NORMAL"
        if not petId then return nil end
        return {
            ID = petId,
            key = petImage .. "|" .. underlayImage,
            petImage = petImage,
            underlayImage = underlayImage,
            level = Pets.parseLevel(levelText and levelText.Text),
            locked = Pets.isVisible(locked),
            equipped = Pets.isVisible(equipped),
        }
    end

    function Pets.collectPetFrames(inventory)
        local frames = {}
        local seen = {}

        local function addFrame(frame)
            if seen[frame] then return end
            seen[frame] = true
            if not frame.Visible then return end
            frames[#frames + 1] = frame
        end

        for _, child in ipairs(inventory:GetChildren()) do
            if child:IsA("Frame") then addFrame(child) end
        end

        return frames
    end

    function Pets.addVisibleGroups(inventory, groups)
        local maxCount = 0
        for _, frame in ipairs(Pets.collectPetFrames(inventory)) do
            local pet = Pets.readPet(frame)
            if pet then
                local group = groups[pet.key]
                if not group then
                    group = {
                        PetImage = pet.petImage,
                        Underlay = pet.underlayImage,
                        Pets = {},
                    }
                    groups[pet.key] = group
                end
                group.Pets[#group.Pets + 1] = pet
            end
        end

        for _, group in pairs(groups) do
            if #group.Pets > maxCount then maxCount = #group.Pets end
        end
        return maxCount
    end

    function Pets.scanGroups()
        local groups = {}
        local maxCount = 0
        local inventory = Pets.getInventoryFrame()
        if not inventory then
            Pets.setStatus("Auto Craft: inventory missing")
            Pets.debugPrint("inventory missing at MainGui.OtherFrames.PetsInventory.Frame.ScrollingFrame")
            return groups, 0
        end

        maxCount = math.max(maxCount, Pets.addVisibleGroups(inventory, groups))

        return groups, maxCount
    end

    function Pets.chooseCraftGroup()
        Pets.setStatus("Auto Craft: scanning")
        local groups, maxCount = Pets.scanGroups()
        local bestGroup
        local bestUsable
        local allowEquipped = Core.state[Pets.ALLOW_EQUIPPED] == true
        for _, group in pairs(groups) do
            table.sort(group.Pets, function(a, b)
                if a.level == b.level then return tostring(a.ID) < tostring(b.ID) end
                return a.level > b.level
            end)

            local usable = {}
            local protected = {}
            for _, pet in ipairs(group.Pets) do
                if pet.locked or (pet.equipped and not allowEquipped) then
                    protected[#protected + 1] = pet
                else
                    usable[#usable + 1] = pet
                end
            end

            if #usable >= Pets.REQUIRED_COUNT and (not bestUsable or #usable > #bestUsable) then
                bestGroup = group
                bestUsable = usable
            end
        end

        if not bestUsable then
            Pets.setStatus(string.format("Auto Craft: found %d/%d", math.min(maxCount, Pets.REQUIRED_COUNT), Pets.REQUIRED_COUNT))
            Pets.debugPrint("no craftable group found", "max raw group=", maxCount, "required usable=", Pets.REQUIRED_COUNT)
            return nil
        end

        Pets.debugPrint(
            "selected craft",
            "FlatPet.Image=", bestGroup.PetImage,
            "Underlay.Image=", bestGroup.Underlay,
            "usable=", #bestUsable,
            "allow equipped=", allowEquipped,
            "base=", bestUsable[1].ID,
            "level=", bestUsable[1].level
        )

        return bestUsable[1]
    end

    function Pets.tryCraftOne()
        local mainPet = Pets.chooseCraftGroup()
        if not (mainPet and mainPet.ID and mainPet.ID ~= "") then
            task.wait(Pets.SCAN_DELAY)
            return
        end

        Pets.setStatus("Auto Craft: crafting")
        Pets.debugPrint("firing CombinePet", mainPet.ID)
        local ok, err = pcall(function() Core.UIActionRemote:FireServer("CombinePet", mainPet.ID) end)
        Pets.debugPrint("CombinePet result", ok, err or "ok")
        task.wait(Pets.CRAFT_COOLDOWN)
        Pets.setStatus("Auto Craft: waiting")
    end

    function Pets.startAutoCraft()
        Pets.setStatus("Auto Craft: scanning")
        Pets.debugPrint("auto craft started")
        Core.loopWhile(Pets.STATE_KEY, Pets.SCAN_DELAY, Pets.tryCraftOne)
    end

    function Pets.stopAutoCraft()
        Pets.setStatus("Auto Craft: waiting")
        Pets.debugPrint("auto craft stopped")
    end
end
