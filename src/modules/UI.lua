return function(HS, S)
    local UI     = HS.UI or {}
    HS.UI = UI
    local Core   = HS.Core
    local C      = Core.C
    HS.StandaloneScripts = HS.StandaloneScripts or {}

    local StandaloneScripts = HS.StandaloneScripts
    StandaloneScripts.Scripts = StandaloneScripts.Scripts or {}

    function StandaloneScripts.add(label, callback, options)
        options = type(options) == "table" and options or {}
        StandaloneScripts.Scripts[#StandaloneScripts.Scripts + 1] = {
            label = label,
            callback = callback,
            buttonText = options.buttonText,
            danger = options.danger == true,
        }
    end

    StandaloneScripts.add("Remote Spy", function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Klinac/scripts/main/utopia_spy.lua", true))()
    end)

    StandaloneScripts.add("Health Check", function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Patolas1904/Heartsteel-Beta/dev/src/healthcheck.lua"))()
    end)

    function StandaloneScripts.run(script)
        if type(script) ~= "table" then return end

        local runner = script.callback or script.run
        if type(runner) ~= "function" then
            Core.debugLog("Standalone script missing callback:", script.label or script.name or "Unnamed")
            return
        end

        local ok, err = pcall(runner)
        if not ok then
            Core.debugLog("Standalone script failed:", script.label or script.name or "Unnamed", tostring(err))
        end
    end

    function StandaloneScripts.getUiItems()
        local items = {}
        for _, script in ipairs(StandaloneScripts.Scripts) do
            if type(script) == "table" then
                local capturedScript = script
                items[#items + 1] = {
                    type = "action",
                    label = tostring(script.label or script.name or "Standalone Script"),
                    buttonText = script.buttonText or "RUN",
                    danger = script.danger == true,
                    callback = function()
                        StandaloneScripts.run(capturedScript)
                    end,
                }
            end
        end

        if #items == 0 then
            items[#items + 1] = {type="note", text="No standalone scripts added yet."}
        end

        return items
    end

    -- ── Tiny GUI helpers ─────────────────────────────────────────
    function UI.make(class, props, parent)
        local obj = Instance.new(class)
        for k, v in pairs(props or {}) do obj[k] = v end
        if parent then obj.Parent = parent end
        return obj
    end

    function UI.addCorner(obj, radius)
        UI.make("UICorner", {CornerRadius=UDim.new(0, radius or 4)}, obj)
    end

    function UI.addStroke(obj, color, thickness, transparency)
        UI.make("UIStroke", {
            Color=color or C.border, Thickness=thickness or 1,
            Transparency=transparency or 0,
        }, obj)
    end

    function UI.clearChildren(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding")
                and not child:IsA("UIGridLayout") and not child:IsA("UIScale")
                and not child:IsA("UIStroke") then
                child:Destroy()
            end
        end
    end

    function UI.countEnabled()
        local n = 0
        for _, v in pairs(Core.state) do if v then n += 1 end end
        return n
    end

    function UI.allOff(skipSave)
        for key in pairs(Core.state) do
            Core.state[key] = false
            local cb = Core.callbacks[key]
            if cb then task.spawn(cb, false) end
        end
        local fcc = HS.Farming.crownsConnection
        if fcc then fcc:Disconnect(); HS.Farming.crownsConnection = nil end
        if HS.ElementZonePull and HS.ElementZonePull.stopElementNoclip then
            HS.ElementZonePull.stopElementNoclip()
        end
        Core.priorityOwner = nil
        if not skipSave then HS.Session.save() end
    end

    -- ── Quest title reader ───────────────────────────────────────
    local SF_PATH = {"MainGui","OtherFrames","Clans","InClan","Frames","Quests","ScrollingFrame"}

    local function getScrollingFrame()
        local node = Core.player:FindFirstChild("PlayerGui"); if not node then return nil end
        for _, name in ipairs(SF_PATH) do node = node:FindFirstChild(name); if not node then return nil end end
        return node
    end

    function UI.refreshQuestTitles()
        local sf = getScrollingFrame(); if not sf then return end
        local quests = {}
        for _, child in ipairs(sf:GetChildren()) do
            if child.Name == "Quest" then table.insert(quests, child) end
        end
        table.sort(quests, function(a,b) return a.LayoutOrder < b.LayoutOrder end)
        for i, lbl in ipairs(Core.questTitleLabels) do
            local q    = quests[i]
            local info = q and q:FindFirstChild("InfoText")
            local text = (info and info.Text ~= "") and info.Text or Core.questTitleCache[i] or ("Quest " .. i)
            if info and info.Text ~= "" then Core.questTitleCache[i] = info.Text end
            if lbl and lbl.Parent then
                lbl.Text = text
            end
        end
    end
    _G.refreshQuestTitles = UI.refreshQuestTitles

    local sidebar, content  -- forward refs; assigned during build

    -- ── Nav ──────────────────────────────────────────────────────
    UI.navButtons = {}

    function UI.refreshNav()
        for key, btn in pairs(UI.navButtons) do
            if key == Core.activeTab then
                btn.TextColor3 = C.purple; btn.BackgroundTransparency = 0.88; btn.BackgroundColor3 = C.rowActive
            else
                btn.TextColor3 = C.textDim; btn.BackgroundTransparency = 1; btn.BackgroundColor3 = Color3.new()
            end
        end
    end

    function UI.isTabVisible(tab)
        if type(tab) ~= "table" then return false end
        if tab.testingOnly == true and Core.state.testing_mode ~= true then return false end
        if tab.debugOnly == true and Core.state.debug_mode ~= true then return false end
        return true
    end

    function UI.ensureActiveTabVisible()
        local tabData = UI.UI_DATA and UI.UI_DATA[Core.activeTab]
        if UI.isTabVisible(tabData) then return end
        Core.activeTab = "misc"
    end

    function UI.renderSidebar()
        if not sidebar then return end

        UI.clearChildren(sidebar)
        table.clear(UI.navButtons)
        for _, tab in ipairs(UI.TAB_ORDER or {}) do
            if tab.separator then
                local sepWrap = UI.make("Frame", {Parent=sidebar, Size=UDim2.new(1,0,0,14), BackgroundTransparency=1})
                UI.make("Frame", {Parent=sepWrap, Size=UDim2.new(1,-20,0,1), Position=UDim2.new(0,10,0.5,0), BackgroundColor3=C.border, BorderSizePixel=0})
            elseif UI.isTabVisible(tab) then
                local btn = UI.make("TextButton", {Parent=sidebar, Size=UDim2.new(1,0,0,34), BackgroundColor3=Color3.new(), BackgroundTransparency=1, Text=tab.label, Font=Enum.Font.GothamBold, TextSize=11, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left, AutoButtonColor=false})
                UI.make("UIPadding", {Parent=btn, PaddingLeft=UDim.new(0,14)})
                UI.navButtons[tab.key] = btn
                btn.MouseButton1Click:Connect(function() Core.activeTab = tab.key; UI.renderContent() end)
            end
        end
        UI.refreshNav()
    end

    -- ── Status bar ───────────────────────────────────────────────
    UI.statusDot  = nil
    UI.statusText = nil

    function UI.updateStatus()
        if not Core.alive then
            UI.statusText.Text = "killed"; UI.statusDot.BackgroundColor3 = Color3.fromRGB(160,32,32); return
        end
        local n = UI.countEnabled()
        if n > 0 then
            UI.statusText.Text = tostring(n) .. " active"; UI.statusDot.BackgroundColor3 = C.purple
        else
            UI.statusText.Text = "idle"; UI.statusDot.BackgroundColor3 = C.border2
        end
    end

    -- ── Row builders ─────────────────────────────────────────────
    function UI.sectionTitle(text)
        local holder = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,20), BackgroundTransparency=1})
        local marker = UI.make("Frame", {Parent=holder, Size=UDim2.fromOffset(3,10), Position=UDim2.new(0,0,0,5), BackgroundColor3=C.purple, BorderSizePixel=0})
        UI.addCorner(marker, 1)
        UI.make("TextLabel", {Parent=holder, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-8,1,0), Text=text, Font=Enum.Font.Garamond, TextSize=12, TextColor3=C.purpleDark, TextXAlignment=Enum.TextXAlignment.Left})
        UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,1), BackgroundColor3=C.border, BorderSizePixel=0})
    end

    function UI.makeToggleVisual(parent, on)
        local track = UI.make("Frame", {Parent=parent, Size=UDim2.fromOffset(32,17), Position=UDim2.new(1,-40,0.5,-8), BackgroundColor3=on and C.toggleOn or C.toggleOff, BorderSizePixel=0})
        UI.addCorner(track, 2); UI.addStroke(track, on and C.purple or C.border, 1)
        local knob = UI.make("Frame", {Parent=track, Size=UDim2.fromOffset(11,11), Position=on and UDim2.fromOffset(17,2) or UDim2.fromOffset(2,2), BackgroundColor3=on and C.purple or C.border2, BorderSizePixel=0})
        UI.addCorner(knob, 1)
    end

    function UI.toggleKey(key)
        if not Core.alive then return end
        Core.state[key] = not Core.state[key]
        local cb = Core.callbacks[key]
        if cb then
            task.spawn(function()
                local ok, err = pcall(cb, Core.state[key])
                if not ok then
                    Core.debugLog("Toggle callback failed:", key, tostring(err))
                end
                HS.Session.save()
            end)
        end
        HS.Session.save()
        UI.renderContent()
    end

    function UI.makeMerchantPetLabel(parent, item, labelColor, textSz)
        local display = item.petRarity
        local holder = UI.make("Frame", {
            Parent=parent,
            BackgroundTransparency=1,
            Position=UDim2.fromOffset(8,0),
            Size=UDim2.new(1, -50, 1, 0),
        })
        UI.make("UIListLayout", {
            Parent=holder,
            FillDirection=Enum.FillDirection.Horizontal,
            SortOrder=Enum.SortOrder.LayoutOrder,
            VerticalAlignment=Enum.VerticalAlignment.Center,
            Padding=UDim.new(0, 3),
        })

        local function makeRarityIcon(asset)
            return UI.make("ImageLabel", {
                Parent=holder,
                BackgroundTransparency=1,
                Size=UDim2.fromOffset(13, 13),
                Image=asset,
                ImageColor3=labelColor,
                ScaleType=Enum.ScaleType.Fit,
            })
        end

        if display.classText and display.classText ~= "" then
            UI.make("TextLabel", {
                Parent=holder,
                BackgroundTransparency=1,
                Size=UDim2.fromOffset(0, textSz + 8),
                AutomaticSize=Enum.AutomaticSize.X,
                Text=display.classText,
                Font=Enum.Font.Gotham,
                TextSize=textSz,
                TextColor3=labelColor,
                TextXAlignment=Enum.TextXAlignment.Left,
            })
        end

        if display.asset then
            for _ = 1, display.iconCount or 1 do
                makeRarityIcon(display.asset)
            end
            UI.make("TextLabel", {
                Parent=holder,
                BackgroundTransparency=1,
                Size=UDim2.fromOffset(0, textSz + 8),
                AutomaticSize=Enum.AutomaticSize.X,
                Text="Pet" .. (item.labelSuffix or ""),
                Font=Enum.Font.Gotham,
                TextSize=textSz,
                TextColor3=labelColor,
                TextXAlignment=Enum.TextXAlignment.Left,
            })
        else
            UI.make("TextLabel", {
                Parent=holder,
                BackgroundTransparency=1,
                Size=UDim2.fromOffset(0, textSz + 8),
                AutomaticSize=Enum.AutomaticSize.X,
                Text=(display.fallbackText or "Pet") .. (item.labelSuffix or ""),
                Font=Enum.Font.Gotham,
                TextSize=textSz,
                TextColor3=labelColor,
                TextXAlignment=Enum.TextXAlignment.Left,
            })
        end
    end

    function UI.makeToggleRow(item)
        local on      = Core.state[item.key]
        local compact = item.compact == true
        local rowH    = compact and 22 or 30
        local textSz  = compact and 10 or 12
        local wrapper = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,rowH), BackgroundTransparency=1})
        if compact then
            UI.make("Frame", {Parent=wrapper, Size=UDim2.new(0,1,0.5,0),     Position=UDim2.fromOffset(10,0),       BackgroundColor3=C.border2, BorderSizePixel=0})
            UI.make("Frame", {Parent=wrapper, Size=UDim2.new(0,8,0,1),        Position=UDim2.fromOffset(10,rowH/2), BackgroundColor3=C.border2, BorderSizePixel=0})
        end
        local xOffset = compact and 22 or 0
        local row = UI.make("TextButton", {Parent=wrapper, Position=UDim2.fromOffset(xOffset,0), Size=UDim2.new(1,-xOffset,1,0), BackgroundTransparency=on and 0 or 1, BackgroundColor3=on and C.rowActive or C.rowHover, Text="", AutoButtonColor=false})
        UI.addCorner(row, 3)
        local labelColor = on and C.text or (compact and C.textDim or C.purpleSoft)
        if item.petRarity then
            UI.makeMerchantPetLabel(row, item, labelColor, textSz)
        else
            UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1, item.showTimer and -106 or -50, 1, 0), Text=item.label, Font=Enum.Font.Gotham, TextSize=textSz, TextColor3=labelColor, TextXAlignment=Enum.TextXAlignment.Left})
        end
        if item.showTimer then
            HS.Dungeon.timerLabel = UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.new(1,-98,0,0), Size=UDim2.fromOffset(54,30), Text="0:00", Font=Enum.Font.GothamBold, TextSize=11, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Right})
            HS.Dungeon.startTimer()
        end
        UI.makeToggleVisual(row, on)
        row.MouseButton1Click:Connect(function() UI.toggleKey(item.key) end)
    end

    function UI.makeTeleportRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,30), BackgroundTransparency=1})
        UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-70,1,0), Text=item.label, Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        local btn = UI.make("TextButton", {Parent=row, Size=UDim2.fromOffset(50,20), Position=UDim2.new(1,-50,0.5,-10), BackgroundTransparency=1, Text="GO", TextColor3=C.orange, Font=Enum.Font.GothamBold, TextSize=10})
        UI.addCorner(btn, 2); UI.addStroke(btn, C.border2, 1)
        btn.MouseButton1Click:Connect(function() if item.callback then task.spawn(item.callback) end end)
    end

    function UI.makeQuestRow(item)
        local lbl = UI.make("TextLabel", {Parent=content, BackgroundTransparency=1, Size=UDim2.new(1,0,0,20), Text="Quest " .. (item.questIdx or "?"), Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        if item.questIdx then Core.questTitleLabels[item.questIdx] = lbl end
    end

    function UI.makeAutoCycleTimerRow()
    local row = UI.make("Frame", {
        Parent = content,
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
    })

    UI.autoCycleTimerLabel = UI.make("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(22, 0),
        Size = UDim2.new(1, -30, 1, 0),
        Text = "Cycle timer: inactive",
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextColor3 = C.textDim,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    end

    function UI.makeIncubatorSlotsRows()
        for _, info in ipairs(HS.Dungeon.incubatorSlots) do
            UI.make("TextLabel", {Parent=content, BackgroundTransparency=1, Size=UDim2.new(1,0,0,18), Text=string.format("slot %d - %s", info.slot, info.text), Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left})
        end
    end

    function UI.makeDungeonEggTimerLogRows()
        if not (HS.Logs and HS.Logs.Dungeon and Core.state[HS.Logs.Dungeon.STATE_KEY] == true) then
            if HS.Logs and HS.Logs.Dungeon then HS.Logs.Dungeon.bindTimerRows({}) end
            return
        end

        local labels = {}
        for slot = 1, (HS.Dungeon and HS.Dungeon.MAX_INCUBATOR_SLOTS or 6) do
            labels[slot] = UI.make("TextLabel", {
                Parent=content,
                BackgroundTransparency=1,
                Size=UDim2.new(1,0,0,0),
                Text="",
                Font=Enum.Font.Gotham,
                TextSize=11,
                TextColor3=C.textDim,
                TextXAlignment=Enum.TextXAlignment.Left,
                Visible=false,
            })
        end
        HS.Logs.Dungeon.bindTimerRows(labels)
    end

    function UI.makeSliderRow(item)
        local minVal = item.min ~= nil and item.min or 16
        local maxVal = item.max ~= nil and item.max or 160
        local val = Core.sliderState[item.key]
        if val == nil and item.getValue then val = item.getValue() end
        if val == nil then val = item.default ~= nil and item.default or minVal end
        val = math.clamp(tonumber(val) or minVal, minVal, maxVal)
        local pendingVal = val
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,44), BackgroundTransparency=1})
        local topBar = UI.make("Frame", {Parent=row, BackgroundTransparency=1, Size=UDim2.new(1,0,0,18)})
        UI.make("TextLabel", {Parent=topBar, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-70,1,0), Text=item.label, Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        local valLabel = UI.make("TextLabel", {Parent=topBar, BackgroundTransparency=1, Position=UDim2.new(1,-60,0,0), Size=UDim2.fromOffset(52,18), Text=tostring(val), Font=Enum.Font.GothamBold, TextSize=12, TextColor3=C.purple, TextXAlignment=Enum.TextXAlignment.Right})

        local track = UI.make("Frame", {Parent=row, Size=UDim2.new(1,-16,0,6), Position=UDim2.new(0,8,0,30), BackgroundColor3=C.toggleOff, BorderSizePixel=0})
        UI.addCorner(track, 3); UI.addStroke(track, C.border, 1)
        local fillPct = (val - minVal) / (maxVal - minVal)
        local fill = UI.make("Frame", {Parent=track, Size=UDim2.new(fillPct,0,1,0), BackgroundColor3=C.purpleDark, BorderSizePixel=0})
        UI.addCorner(fill, 3)
        local knob = UI.make("Frame", {Parent=track, Size=UDim2.fromOffset(14,14), Position=UDim2.new(fillPct,0,0.5,-7), BackgroundColor3=C.purpleDark, BorderSizePixel=0})
        UI.addCorner(knob, 999); UI.addStroke(knob, C.border, 1)

        local dragging = false
        local function updateSlider(absX)
            local trackAbs = track.AbsolutePosition.X
            local trackW = track.AbsoluteSize.X
            if trackW <= 0 then return end
            local pct = math.clamp((absX - trackAbs) / trackW, 0, 1)
            pendingVal = math.floor(minVal + pct * (maxVal - minVal) + 0.5)
            fill.Size = UDim2.new(pct, 0, 1, 0)
            knob.Position = UDim2.new(pct, 0, 0.5, -7)
            fill.BackgroundColor3 = C.purple
            knob.BackgroundColor3 = C.purple
            valLabel.Text = tostring(pendingVal)
            if item.key then Core.sliderState[item.key] = pendingVal end
            if item.callback then item.callback(pendingVal) end
            HS.Session.save()
        end

        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                updateSlider(input.Position.X)
            end
        end)
        track.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        S.UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                updateSlider(input.Position.X)
            end
        end)
    end

    function UI.makeSelectionRow(item)
        local options      = item.options or {}
        local instant      = item.instant == true
        local currentValue = Core.selectionState[item.key] or item.default or options[1] or ""
        local currentIndex = table.find(options, currentValue) or 1
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,58), BackgroundTransparency=1})
        UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-16,0,18), Text=item.label or "Selection", Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        local selectBox = UI.make("TextButton", {Parent=row, Size=UDim2.new(1, instant and -16 or -78, 0, 26), Position=UDim2.new(0,8,0,24), BackgroundColor3=C.toggleOff, Text=currentValue, TextColor3=C.text, Font=Enum.Font.Gotham, TextSize=12, AutoButtonColor=false})
        UI.addCorner(selectBox, 3); UI.addStroke(selectBox, C.border2, 1)
        local applyBtn
        if not instant then
            applyBtn = UI.make("TextButton", {Parent=row, Size=UDim2.fromOffset(62,26), Position=UDim2.new(1,-70,0,24), BackgroundTransparency=1, Text="APPLY", TextColor3=C.orange, Font=Enum.Font.GothamBold, TextSize=10})
            UI.addCorner(applyBtn, 2); UI.addStroke(applyBtn, C.border2, 1)
        end
        selectBox.MouseButton1Click:Connect(function()
            if #options == 0 then return end
            currentIndex += 1; if currentIndex > #options then currentIndex = 1 end
            currentValue = options[currentIndex]
            if item.key then Core.selectionState[item.key] = currentValue end
            selectBox.Text = currentValue
            if instant and item.callback then item.callback(currentValue) end
            HS.Session.save()
        end)
        if applyBtn then
            applyBtn.MouseButton1Click:Connect(function()
                if item.callback then item.callback(currentValue) end
                applyBtn.TextColor3 = C.purple
                task.delay(0.4, function() if applyBtn and applyBtn.Parent then applyBtn.TextColor3 = C.orange end end)
            end)
        end
    end

    function UI.makeInputRow(item)
        local currentValue = Core.inputState[item.key]
        if currentValue == nil then currentValue = item.default or "" end
        currentValue = tostring(currentValue)

        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,52), BackgroundTransparency=1})
        UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0),
            Size=UDim2.new(1,-16,0,18), Text=item.label or "Input",
            Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft,
            TextXAlignment=Enum.TextXAlignment.Left,
        })
        local box = UI.make("TextBox", {
            Parent=row, Size=UDim2.new(1,-16,0,26), Position=UDim2.fromOffset(8,22),
            BackgroundColor3=C.toggleOff, Text=currentValue, PlaceholderText=item.placeholder or "",
            TextColor3=C.text, PlaceholderColor3=C.textDim, Font=Enum.Font.Gotham,
            TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ClearTextOnFocus=false,
        })
        UI.addCorner(box, 3); UI.addStroke(box, C.border2, 1)
        UI.make("UIPadding", {Parent=box, PaddingLeft=UDim.new(0,8), PaddingRight=UDim.new(0,8)})
        box.FocusLost:Connect(function()
            Core.inputState[item.key] = box.Text or ""
            if item.callback then item.callback(Core.inputState[item.key]) end
            HS.Session.save()
        end)
    end

    function UI.makeSimpleLabel(text)
        UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,6), BackgroundTransparency=1})
        UI.sectionTitle(text)
    end

    function UI.makeNoteRow(text)
        UI.make("TextLabel", {
            Parent=content, BackgroundTransparency=1, Size=UDim2.new(1,0,0,24),
            Text=text or "", Font=Enum.Font.Gotham, TextSize=11,
            TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left,
            TextWrapped=true,
        })
    end

    function UI.makeMerchantSeparatorRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,30), BackgroundColor3=C.rowActive, BorderSizePixel=0})
        UI.addCorner(row, 3); UI.addStroke(row, C.border2, 1, 0.15)
        UI.make("Frame", {Parent=row, Size=UDim2.fromOffset(4,18), Position=UDim2.new(0,8,0.5,-9), BackgroundColor3=C.orange, BorderSizePixel=0})
        UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(18,0),
            Size=UDim2.new(1,-26,1,0), Text=string.upper(item.text or ""),
            Font=Enum.Font.GothamBold, TextSize=11, TextColor3=C.orange,
            TextXAlignment=Enum.TextXAlignment.Left,
        })
    end

    function UI.makeMerchantSubseparatorRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,22), BackgroundTransparency=1})
        UI.make("Frame", {Parent=row, Size=UDim2.new(0,18,0,1), Position=UDim2.new(0,10,0.5,0), BackgroundColor3=C.border2, BorderSizePixel=0})
        UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(34,0),
            Size=UDim2.new(1,-42,1,0), Text=item.text or "",
            Font=Enum.Font.GothamBold, TextSize=10, TextColor3=C.purple,
            TextXAlignment=Enum.TextXAlignment.Left,
        })
    end

    function UI.makeStatusRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,28), BackgroundTransparency=1})
        local lbl = UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-16,1,0), Text=item.text or "", Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left})
        if item.bind == "session" then
            HS.Session.statusLabel = lbl
            HS.Session.setStatus(HS.Session.lastMessage)
        elseif item.bind == "boss" then
            HS.Farming.bossStatusLabel = lbl
            HS.Farming.setBossStatus(item.text or "Boss: idle", C.textDim)
        elseif item.bind == "merchant" then
            HS.Merchant.statusLabel = lbl
            HS.Merchant.setStatus(HS.Merchant.status or "waiting")
            HS.Merchant.startDisplayWatcher()
        elseif item.bind == "clan_auto" then
            HS.Farming.clanQuestStatusLabel = lbl
            HS.Farming.setClanQuestStatus(HS.Farming.clanQuestStatus or "waiting: idle")
        elseif item.bind == "auto_craft_pets" then
            HS.Pets.statusLabel = lbl
            HS.Pets.setStatus(HS.Pets.status or "Auto Craft: waiting")
        end
    end

    function UI.makePetdexProgressRow()
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,126), BackgroundColor3=C.toggleOff, BorderSizePixel=0})
        UI.addCorner(row, 3); UI.addStroke(row, C.border, 1)
        local lbl = UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,6),
            Size=UDim2.new(1,-16,1,-12), Text=HS.PetdexFarm.getProgressText(),
            Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim,
            TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top,
            TextWrapped=true,
        })
        HS.PetdexFarm.progressLabel = lbl
        task.spawn(HS.PetdexFarm.refreshProgress)
    end

    function UI.makePetdexRewardsStatusRow()
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,94), BackgroundColor3=C.toggleOff, BorderSizePixel=0})
        UI.addCorner(row, 3); UI.addStroke(row, C.border, 1)
        local lbl = UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,6),
            Size=UDim2.new(1,-16,1,-12), Text=HS.PetdexRewards.getStatusText(),
            Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim,
            TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top,
            TextWrapped=true,
        })
        HS.PetdexRewards.statusLabel = lbl
        task.spawn(HS.PetdexRewards.refreshStatus)
    end

    function UI.makeEggOpenerStatusRow()
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,90), BackgroundColor3=C.toggleOff, BorderSizePixel=0})
        UI.addCorner(row, 3); UI.addStroke(row, C.border, 1)
        local lbl = UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,6),
            Size=UDim2.new(1,-16,1,-12), Text=HS.EggOpener.getStatusText(),
            Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim,
            TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top,
            TextWrapped=true,
        })
        HS.EggOpener.statusLabel = lbl
        task.spawn(function()
            HS.EggOpener.init()
            HS.EggOpener.updateSelection()
        end)
    end

    function UI.makeEventStatusRow()
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,118), BackgroundColor3=C.toggleOff, BorderSizePixel=0})
        UI.addCorner(row, 3); UI.addStroke(row, C.border, 1)
        UI.make("TextLabel", {
            Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,6),
            Size=UDim2.new(1,-16,1,-12),
            Text=HS.Event and HS.Event.getStatusText and HS.Event.getStatusText() or "Event: unavailable",
            Font=Enum.Font.Gotham, TextSize=11, TextColor3=C.textDim,
            TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top,
            TextWrapped=true,
        })
    end

    function UI.makeActionRow(item)
        local row = UI.make("Frame", {Parent=content, Size=UDim2.new(1,0,0,34), BackgroundTransparency=1})
        UI.make("TextLabel", {Parent=row, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-92,1,0), Text=item.label, Font=Enum.Font.Gotham, TextSize=12, TextColor3=C.purpleSoft, TextXAlignment=Enum.TextXAlignment.Left})
        local btn = UI.make("TextButton", {Parent=row, Size=UDim2.fromOffset(76,24), Position=UDim2.new(1,-76,0.5,-12), BackgroundTransparency=1, Text=item.buttonText or "RUN", TextColor3=item.danger and C.red or C.orange, Font=Enum.Font.GothamBold, TextSize=10})
        UI.addCorner(btn, 2); UI.addStroke(btn, item.danger and C.redDark or C.border2, 1)
        btn.MouseButton1Click:Connect(function()
            if item.callback then task.spawn(item.callback) end
        end)
    end

    -- ── Render ───────────────────────────────────────────────────
    function UI.renderContent()
        Core.questTitleLabels = {}
        UI.ensureActiveTabVisible()
        UI.clearChildren(content)
        local tabData = UI.UI_DATA[Core.activeTab]
        if not tabData then return end
        if Core.activeTab == "merchant" then
            tabData.items = HS.Merchant.getUiItems(true)
        elseif Core.activeTab == "standalone_scripts" then
            tabData.items = HS.StandaloneScripts.getUiItems()
        end
        UI.sectionTitle(tabData.title)
        for _, item in ipairs(tabData.items) do
            if     item.type == "slider"          then UI.makeSliderRow(item)
            elseif item.type == "selection"       then UI.makeSelectionRow(item)
            elseif item.type == "input"           then UI.makeInputRow(item)
            elseif item.type == "toggle"          then UI.makeToggleRow(item)
            elseif item.type == "teleport"        then UI.makeTeleportRow(item)
            elseif item.type == "quest"           then UI.makeQuestRow(item)
            elseif item.type == "incubator_slots" then UI.makeIncubatorSlotsRows()
            elseif item.type == "dungeon_egg_timer_logs" then UI.makeDungeonEggTimerLogRows()
            elseif item.type == "label"           then UI.makeSimpleLabel(item.text)
            elseif item.type == "note"            then UI.makeNoteRow(item.text)
            elseif item.type == "merchant_separator" then UI.makeMerchantSeparatorRow(item)
            elseif item.type == "merchant_subseparator" then UI.makeMerchantSubseparatorRow(item)
            elseif item.type == "cycle_timer"     then UI.makeAutoCycleTimerRow()
            elseif item.type == "status"          then UI.makeStatusRow(item)
            elseif item.type == "petdex_progress" then UI.makePetdexProgressRow()
            elseif item.type == "petdex_rewards_status" then UI.makePetdexRewardsStatusRow()
            elseif item.type == "eggopener_status" then UI.makeEggOpenerStatusRow()
            elseif item.type == "event_status"    then UI.makeEventStatusRow()
            elseif item.type == "action"          then UI.makeActionRow(item)
            end
        end
        UI.updateStatus(); UI.renderSidebar()
        if Core.activeTab == "clan" then task.spawn(UI.refreshQuestTitles) end
    end

    -- ── UI_DATA ──────────────────────────────────────────────────
    UI.UI_DATA = {
        farming = {
            title = "automation",
            items = {
                {type="toggle", key="swing",   label="Auto Swing",   callback=function(on) if on then HS.Farming.startSwing() end end},
                {type="toggle", key="sell",    label="Auto Sell",    callback=function(on) if on then HS.Farming.startSell()  end end},
                {type="toggle", key="boss",    label="Auto Farm Boss",
                    callback=function(on)
                        if on then HS.Farming.startBoss()
                        else HS.Farming.stopBoss() end
                    end},
                {type="toggle", key="boss_tp", label="Auto TP Boss", compact=true,
                    callback=function(on)
                        if on and Core.state.boss then HS.Farming.startBoss() end
                    end},
                {type="status", bind="boss", text="Boss: idle"},
                {type="toggle", key="crowns",  label="Auto Collect Crowns",
                    callback=function(on)
                        if on then HS.Farming.startCrowns()
                        else
                            local cc = HS.Farming.crownsConnection
                            if cc then cc:Disconnect(); HS.Farming.crownsConnection = nil end
                        end
                    end},
                {type="toggle", key="claim_flags", label="Capture Flags",
                    callback=function(on) if on then HS.Flags.startCaptureFlags() end end},
                {type="toggle", key="flag_avoid", label="Avoid Players", compact=true, callback=function() end},
                {type="toggle", key="claim_koth", label="King",
                    callback=function(on) if on then HS.Farming.startKoth() end end},
                {type="toggle", key="koth_avoid", label="Avoid Players", compact=true, callback=function() end},
            },
        },
        misc = {
            title = "Various",
            items = {
                {type="toggle", key="debug_mode",         label="Debug Mode",       default=true,  callback=function() end},
                {type="toggle", key="testing_mode",       label="Testing Mode",     default=false, callback=function() end},
                {type="toggle", key="anti_afk", label="Anti-AFK", default=true,
                    callback=function(on)
                        if on then HS.Misc.startAntiAfk(); task.spawn(HS.Misc.antiAfkPulse, "toggle-on"); Core.debugLog("Anti AFK active")
                        else Core.debugLog("Anti AFK inactive") end
                    end},
                {type="toggle", key="simulate_movement", label="Simulate Movement",
                    callback=function(on)
                        if on then HS.Misc.startSimulateMovement(); Core.debugLog("Simulate movement active")
                        else Core.debugLog("Simulate movement inactive") end
                    end},
                {type="toggle", key="fast_hit", label="Fast Hit (Experimental)", callback=function() end},
                {type="teleport", label="Save Pos",    callback=function() HS.Misc.saveCurrentPosition() end},
                {type="teleport", label="TP Saved Pos",callback=function() HS.Misc.teleportToSavedPosition() end},
                {type="teleport", label="Copy Pos",    callback=function() HS.Misc.copyCurrentPosition() end},
                {type="toggle", key="move_speed", label="Move Speed",
                    callback=function(on)
                        if on then HS.Misc.startSpeed() else HS.Misc.stopSpeed() end
                    end},
                {type="slider", key="movespeed_val", label="Speed Value", min=16, max=160, default=16,
                    callback=function(val) HS.Misc.setSpeed(val) end},
            },
        },
        session = {
            title = "Session",
            items = {
                {type="status", bind="session", text="No session loaded"},
                {type="action", label="Reset saved session", buttonText="RESET", danger=true,
                    callback=function()
                        HS.Session.resetNextStartup()
                    end},
            },
        },
        standalone_scripts = {
            title = "Standalone Scripts",
            testingOnly = true,
            items = {},
        },
        elements = {
            title = "Main",
            items = {
                {type="selection", key="selected_element", label="Change Element",
                    options=HS.Misc.ELEMENT_OPTIONS, default="Fire",
                    callback=function(value) HS.Misc.applyElement(value) end},
                {type = "toggle",
                 key = "auto_cycle",
                 label = "Auto Cycle",
                 callback = function(on)
                    if on then
                        HS.AutoCycle.start()
                    else
                        HS.AutoCycle.stop()
                        end
                    end
                },
                {type = "cycle_timer"},

                {type="label", text="Fire"},
                {type="toggle", key="fire_starter_pull", label="Fire Starter Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Fire", "Starter")
                    else HS.ElementZonePull.stop("Fire", "Starter") end
                end},
                {type="toggle", key="fire_advanced_pull", label="Fire Advanced Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Fire", "Advanced")
                    else HS.ElementZonePull.stop("Fire", "Advanced") end
                end},
                {type="toggle", key="fire_master_pull", label="Fire Master Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Fire", "Master")
                    else HS.ElementZonePull.stop("Fire", "Master") end
                end},
               {type="toggle", key="fire_grandmaster_pull", label="Fire Grandmaster Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Fire", "Grandmaster")
                    else HS.ElementZonePull.stop("Fire", "Grandmaster") end
                end},

                {type="label", text="Water"},
                {type="toggle", key="water_starter_pull", label="Water Starter Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Water", "Starter")
                    else HS.ElementZonePull.stop("Water", "Starter") end
                end},
                {type="toggle", key="water_advanced_pull", label="Water Advanced Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Water", "Advanced")
                    else HS.ElementZonePull.stop("Water", "Advanced") end
                end},
                {type="toggle", key="water_master_pull", label="Water Master Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Water", "Master")
                    else HS.ElementZonePull.stop("Water", "Master") end
                end},
               {type="toggle", key="water_grandmaster_pull", label="Water Grandmaster Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Water", "Grandmaster")
                    else HS.ElementZonePull.stop("Water", "Grandmaster") end
                end},

                {type="label", text="Earth"},
                {type="toggle", key="earth_starter_pull", label="Earth Starter Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Earth", "Starter")
                    else HS.ElementZonePull.stop("Earth", "Starter") end
                end},
                {type="toggle", key="earth_advanced_pull", label="Earth Advanced Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Earth", "Advanced")
                    else HS.ElementZonePull.stop("Earth", "Advanced") end
                end},
                {type="toggle", key="earth_master_pull", label="Earth Master Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Earth", "Master")
                    else HS.ElementZonePull.stop("Earth", "Master") end
                end},
               {type="toggle", key="earth_grandmaster_pull", label="Earth Grandmaster Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Earth", "Grandmaster")
                    else HS.ElementZonePull.stop("Earth", "Grandmaster") end
                end},   
                
                {type="label", text="Plasma"},
                {type="toggle", key="plasma_starter_pull", label="Plasma Starter Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Plasma", "Starter")
                    else HS.ElementZonePull.stop("Plasma", "Starter") end
                end},
                {type="toggle", key="plasma_advanced_pull", label="Plasma Advanced Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Plasma", "Advanced")
                    else HS.ElementZonePull.stop("Plasma", "Advanced") end
                end},
                {type="toggle", key="plasma_master_pull", label="Plasma Master Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Plasma", "Master")
                    else HS.ElementZonePull.stop("Plasma", "Master") end
                end},
               {type="toggle", key="plasma_grandmaster_pull", label="Plasma Grandmaster Pull",
                callback=function(on)
                    if on then HS.ElementZonePull.start("Plasma", "Grandmaster")
                    else HS.ElementZonePull.stop("Plasma", "Grandmaster") end
                end},

            },
        },
        upgrades = {
            title = "auto purchase",
            items = {
                {type="toggle", key="saber",   label="Saber",       callback=function(on) if on then HS.Farming.startSaber()   end end},
                {type="toggle", key="dna",     label="DNA",         callback=function(on) if on then HS.Farming.startDNA()     end end},
                {type="toggle", key="class",   label="Class",       callback=function(on) if on then HS.Farming.startClass()   end end},
                {type="toggle", key="bossdmg", label="Boss Damage", callback=function(on) if on then HS.Farming.startBossDmg() end end},
                {type="toggle", key="aura",    label="Aura",        callback=function(on) if on then HS.Farming.startAura()    end end},
                {type="toggle", key="petaura", label="Pet Aura",    callback=function(on) if on then HS.Farming.startPetAura() end end},
            },
        },
        clan = {
            title = "clan automation",
            items = {
                {type="toggle", key="clanquest", label="Claim Quests",
                    callback=function(on) if on then HS.Farming.startClanQuest() end end},
                {type="toggle", key="clan_auto_quests", label="Clan Auto Quests Completion",
                    callback=function(on)
                        if on then HS.Farming.startClanAutoQuests()
                        else HS.Farming.stopClanAutoQuests() end
                    end},
                {type="status", bind="clan_auto", text="waiting: idle"},
                {type="note", text="Leave Auto Swing enabled for Swing Saber quests."},
                {type="label", text="dungeon missions"},
                {type="toggle", key="clan_dungeon_impossible", label="Always do Impossible", callback=function() end},
                {type="toggle", key="farm_dungeon", label="Farm Dungeon",
                    callback=function(on)
                        if on then HS.Dungeon.startFarm()
                        else
                            if HS.Dungeon.hoverConnection then HS.Dungeon.hoverConnection:Disconnect(); HS.Dungeon.hoverConnection = nil end
                            HS.Dungeon.currentTarget = nil
                        end
                    end},
                {type="slider", key="dungeon_height", label="Dungeon Height", min=6, max=16, default=7,
                    getValue=function() return HS.Dungeon.HEIGHT end,
                    callback=function(val) HS.Dungeon.HEIGHT = math.clamp(val, 6, 16) end},
                {type="toggle", key="farm_chest", label="Claim Chest",
                    callback=function(on)
                        if on then HS.Dungeon.claimChest()
                        else HS.Dungeon.chestThread = nil end
                    end},
                {type="toggle", key="farm_egg", label="Equip Best Egg", callback=function() end},
                {type="incubator_slots"},
                {type="toggle", key="claim_egg", label="Claim Eggs",
                    callback=function(on) if on then HS.Dungeon.startClaimEggs() end end},
                {type="toggle", key="avoid_sun", label="Avoid Sun", compact=true, callback=function() end},
                {type="label", text="flag capture missions"},
                {type="toggle", key="clan_flag_avoid", label="Avoid Players", callback=function() end},
                {type="toggle", key="clan_flag_ignore", label="Ignore Flag Missions", callback=function() end},
                {type="label", text="king missions"},
                {type="toggle", key="clan_koth_avoid", label="Avoid Players", callback=function() end},
                {type="toggle", key="clan_koth_ignore", label="Ignore KOTH Missions", callback=function() end},
                {type="label", text="element mob missions"},
                {type="selection", key="clan_element", label="Element", options={"Fire","Water","Earth","Plasma"}, default="Fire", instant=true},
                {type="label", text="egg opening missions"},
                {type="selection", key="clan_egg_mode", label="Egg Mode", options={"Best Egg","Cheap Egg","Petdex"}, default="Best Egg", instant=true},
                {type="label",      text="active quests"},
                {type="quest",      questIdx=1},
                {type="quest",      questIdx=2},
                {type="quest",      questIdx=3},
            },
        },
        areas = {
            title = "areas",
            items = (function()
                local t = {}
                for _, area in ipairs(Core.AREAS) do
                    if area.isLabel then
                        table.insert(t, {type="label", text=area.label})
                    else
                        local capturedPos = area.pos
                        table.insert(t, {type="teleport", label=area.label, callback=function() HS.Farming.teleportTo(capturedPos) end})
                    end
                end
                return t
            end)(),
        },
        event = {
            title = "Event",
            items = {
                {type="event_status"},
                {type="label", text="Foundations"},
                {type="note", text="Event helpers are loaded for info, currency, merchant listings, shop upgrades, and boss paths."},
                {type="note", text="Event Wheel is intentionally disabled until it is live."},
            },
        },
        pets = {
            title = "Hatchery & Petdex",
            items = {
                {type="toggle", key="auto_egg_opener", label="Auto Egg Opener",
                    callback=function(on)
                        if on then HS.EggOpener.start() else HS.EggOpener.stop() end
                    end},
                {type="slider", key="egg_opener_page", label="Egg Page", min=1, max=50, default=1,
                    callback=function()
                        if HS.EggOpener.initialized or HS.EggOpener.statusLabel then
                            HS.EggOpener.init()
                            HS.EggOpener.updateSelection()
                        end
                    end},
                {type="slider", key="egg_opener_slot", label="Egg Slot", min=1, max=12, default=1,
                    callback=function()
                        if HS.EggOpener.initialized or HS.EggOpener.statusLabel then
                            HS.EggOpener.init()
                            HS.EggOpener.updateSelection()
                        end
                    end},
                {type="eggopener_status"},

                {type="label", text="Quality of Life"},
                {type="toggle", key="auto_craft_pets", label="Auto Craft Pets",
                    callback=function(on)
                        if on then HS.Pets.startAutoCraft() else HS.Pets.stopAutoCraft() end
                    end},
                {type="toggle", key="auto_craft_allow_equipped", label="Allow Equipped Pets", compact=true, callback=function() end},
                {type="status", bind="auto_craft_pets", text="Auto Craft: waiting"},
                {type="toggle", key="hide_egg_animations", label="Hide egg animations", default=false,
                    callback=function(on) HS.Misc.applyHideEggAnimations(on) end},
                {type="toggle", key="petdex_auto_teleport", label="Auto Teleport",
                    callback=function(on)
                        if on then HS.PetdexFarm.startTeleport() else HS.PetdexFarm.stopTeleport() end
                    end},
                    
                {type="label", text="Petdex"},
                {type="toggle", key="auto_petdex_rewards", label="Auto Claim Petdex Rewards",
                    callback=function(on)
                        if on then HS.PetdexRewards.start() else HS.PetdexRewards.stop() end
                    end},
                {type="petdex_rewards_status"},
                {type="toggle", key="auto_petdex", label="Auto Petdex",
                    callback=function(on)
                        if on then HS.PetdexFarm.start() else HS.PetdexFarm.stop() end
                    end},
                {type="slider", key="petdex_skip", label="Petdex Skip", min=0, max=10, default=0,
                    callback=function()
                        if HS.PetdexFarm.initialized or HS.PetdexFarm.progressLabel then HS.PetdexFarm.refreshProgress() end
                    end},
                {type="toggle", key="petdex_ignore_secrets", label="Ignore Secrets", default=true,
                    callback=function()
                        if HS.PetdexFarm.initialized or HS.PetdexFarm.progressLabel then HS.PetdexFarm.refreshProgress() end
                    end},
                {type="petdex_progress"},
            },
        },
        logs = {
            title = "Logs",
            items = {
                {type="label", text="Discord Monitor"},
                {type="toggle", key=HS.Logs.DiscordMonitor.STATE_KEY, label="Enable Discord Monitor",
                    callback=function(on) HS.Logs.DiscordMonitor.setEnabled(on) end},
                {type="label", text="Discord Monitor Settings"},
                {type="input", key=HS.Logs.DiscordMonitor.URL_KEY, label="Discord Monitor Webhook URL", default="",
                    placeholder="https://discord.com/api/webhooks/...",
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="input", key=HS.Logs.DiscordMonitor.INTERVAL_KEY, label="Update Interval (seconds)", default="10",
                    placeholder="10",
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_ELEMENT_LEVELS_KEY, label="Show Element Levels", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_MASTERY_LEVELS_KEY, label="Show Mastery Levels", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_DUNGEON_EGGS_KEY, label="Show Dungeon Egg Timers", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_SESSION_STATS_KEY, label="Show Session Stats", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="toggle", key=HS.Logs.DiscordMonitor.SHOW_CONNECTION_STATS_KEY, label="Show Connection Stats", default=false,
                    callback=function() HS.Logs.DiscordMonitor.onSettingsChanged() end},
                {type="label", text="Pets"},
                {type="toggle", key=HS.Logs.Pets.STATE_KEY, label="Pet Hatch Webhook",
                    callback=function(on) HS.Logs.Pets.setEnabled(on) end},
                {type="input", key=HS.Logs.Pets.URL_KEY, label="Webhook URL", default="",
                    placeholder="https://discord.com/api/webhooks/...",
                    callback=function() HS.Logs.Pets.syncConnection() end},
                {type="label", text="Rarity Filters"},
                {type="toggle", key="pet_webhook_1star", label="1 Star", callback=function() end},
                {type="toggle", key="pet_webhook_2star", label="2 Star", callback=function() end},
                {type="toggle", key="pet_webhook_3star", label="3 Star", callback=function() end},
                {type="toggle", key="pet_webhook_4star", label="4 Star", callback=function() end},
                {type="toggle", key="pet_webhook_5star", label="5 Star", callback=function() end},
                {type="toggle", key="pet_webhook_1moon", label="1 Moon", callback=function() end},
                {type="toggle", key="pet_webhook_2moon", label="2 Moon", callback=function() end},
                {type="toggle", key="pet_webhook_3moon", label="3 Moon", callback=function() end},
                {type="toggle", key="pet_webhook_secret", label="Secret", callback=function() end},
                {type="label", text="Dungeon"},
                {type="toggle", key=HS.Logs.Dungeon.STATE_KEY, label="Dungeon Egg Timers",
                    callback=function(on) HS.Logs.Dungeon.setEnabled(on) end},
                {type="dungeon_egg_timer_logs"},
            },
        },
        merchant = {
            title = "Auto Merchant",
            items = HS.Merchant.getUiItems(),
        },
        Dungeon = {
            title = "Setup & Farming",
            items = {
                {type="toggle", key="start_dungeon", label="Auto Start Dungeon", showTimer=true,
                    callback=function(on)
                        if on then HS.Dungeon.startTimer(); HS.Dungeon.tryAutoStart()
                        else HS.Dungeon.resetAutoStartDebounce("toggle disabled") end
                    end},
                {type="selection", key="dungeon_type",       label="Dungeon Type", options={"Space"}, default="Space", instant=true},
                {type="selection", key="dungeon_difficulty",  label="Difficulty",   options={"Easy","Medium","Hard","Impossible"}, default="Easy", instant=true},
                {type="selection", key="dungeon_privacy",     label="Privacy",      options={"Public","Friends","Private"}, default="Public", instant=true},
                {type="label", text="Farming"},
                {type="toggle", key="farm_dungeon", label="Farm Dungeon",
                    callback=function(on)
                        if on then HS.Dungeon.startFarm()
                        else
                            if HS.Dungeon.hoverConnection then HS.Dungeon.hoverConnection:Disconnect(); HS.Dungeon.hoverConnection = nil end
                            HS.Dungeon.currentTarget = nil
                        end
                    end},
                {type="slider", key="dungeon_height", label="Dungeon Height", min=6, max=16, default=7,
                    getValue=function() return HS.Dungeon.HEIGHT end,
                    callback=function(val) HS.Dungeon.HEIGHT = math.clamp(val, 6, 16) end},
                {type="toggle", key="farm_chest", label="Claim Chest",
                    callback=function(on)
                        if on then HS.Dungeon.claimChest()
                        else HS.Dungeon.chestThread = nil end
                    end},
                {type="toggle", key="farm_egg", label="Equip Best Egg", callback=function() end},
                {type="incubator_slots"},
                {type="toggle", key="claim_egg", label="Claim Eggs",
                    callback=function(on) if on then HS.Dungeon.startClaimEggs() end end},
                {type="toggle", key="avoid_sun", label="Avoid Sun", compact=true, callback=function() end},
                {type="label", text="Upgrades"},
                {type="toggle", key="dungeon_DungeonCoins",      label="Dungeon Coins",  callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonCoins")()      end end},
                {type="toggle", key="dungeon_DungeonCritChance", label="Crit Chance",    callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonCritChance")()  end end},
                {type="toggle", key="dungeon_DungeonCrowns",     label="Dungeon Crowns", callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonCrowns")()     end end},
                {type="toggle", key="dungeon_DungeonDamage",     label="Dungeon Damage", callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonDamage")()     end end},
                {type="toggle", key="dungeon_DungeonEggSlots",   label="Egg Slots",      callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonEggSlots")()   end end},
                {type="toggle", key="dungeon_DungeonHealth",     label="Dungeon Health", callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonHealth")()     end end},
                {type="toggle", key="dungeon_DungeonSprint",     label="Dungeon Sprint", callback=function(on) if on then HS.Dungeon.startUpgrade("DungeonSprint")()     end end},
                {type="toggle", key="dungeon_IncubatorSpeed",    label="Incubator Speed",callback=function(on) if on then HS.Dungeon.startUpgrade("IncubatorSpeed")()    end end},
            },
        },
    }

    UI.TAB_ORDER = {
        {key="farming",  label="FARMING"},
        {key="upgrades", label="UPGRADES"},
        {separator=true},
        {key="elements", label="ELEMENTS"},
        {key="areas",    label="AREAS"},
        {separator=true},
        {key="clan",     label="CLAN"},
        {key="pets",     label="PETS"},
        {key="Dungeon",  label="DUNGEON"},
        {key="event",    label="EVENT"},
        {key="merchant", label="MERCHANT"},
        {key="logs",     label="☀ LOGS"},
        {separator=true},
        {key="misc",     label="MISC"},
        {key="session",  label="SESSION"},
        {key="standalone_scripts", label="STANDALONE", testingOnly=true},
    }

    -- ── Build state from UI_DATA ─────────────────────────────────
    HS.Session.applyUiDefaults()

    -- ── Root GUIs ────────────────────────────────────────────────
    local savedSession = HS.Session.load()
    if type(savedSession) == "table" then
        local savedConfig = type(savedSession.config) == "table" and savedSession.config
            or type(savedSession.Config) == "table" and savedSession.Config
            or {}
        local savedToggles = type(savedSession.state) == "table" and savedSession.state
            or type(savedSession.toggles) == "table" and savedSession.toggles
            or {}
        local savedSelections = type(savedSession.selectionState) == "table" and savedSession.selectionState
            or type(savedSession.selections) == "table" and savedSession.selections
            or {}
        local savedSliders = type(savedSession.sliderState) == "table" and savedSession.sliderState
            or type(savedSession.sliders) == "table" and savedSession.sliders
            or {}
        local savedInputs = type(savedSession.inputState) == "table" and savedSession.inputState
            or type(savedSession.inputs) == "table" and savedSession.inputs
            or {}
        local savedLogs = type(savedSession.Logs) == "table" and savedSession.Logs
            or type(savedSession.logs) == "table" and savedSession.logs
            or type(savedConfig.Logs) == "table" and savedConfig.Logs
            or type(savedConfig.logs) == "table" and savedConfig.logs
            or nil

        local function mergeSavedConfig(target, saved)
            if type(target) ~= "table" or type(saved) ~= "table" then return end
            for key, value in pairs(saved) do
                if type(key) == "string" then
                    if type(value) == "table" then
                        if type(target[key]) ~= "table" then
                            target[key] = {}
                        end
                        mergeSavedConfig(target[key], value)
                    else
                        target[key] = value
                    end
                end
            end
        end

        if savedSliders.petdex_skip == nil and savedSliders.petdex_target ~= nil then
            savedSliders.petdex_skip = math.clamp(10 - (tonumber(savedSliders.petdex_target) or 10), 0, 10)
        end

        local function countStringKeys(tbl)
            local count = 0
            if type(tbl) == "table" then
                for key in pairs(tbl) do
                    if type(key) == "string" then
                        count += 1
                    end
                end
            end
            return count
        end

        local function logRestoreCount(label, savedTable, restoredCount)
            Core.debugLog(
                "Session restore " .. label .. " keys count:",
                "saved=", countStringKeys(savedTable),
                "restored=", restoredCount
            )
        end

        local restoredToggles = 0
        if type(savedToggles) == "table" then
            for key, value in pairs(savedToggles) do
                if type(key) == "string" and type(value) == "boolean" then
                    Core.state[key] = value
                    restoredToggles += 1
                end
            end
        end
        logRestoreCount("toggle", savedToggles, restoredToggles)

        local restoredInputs = 0
        if type(savedInputs) == "table" then
            for key, value in pairs(savedInputs) do
                if type(key) == "string" and value ~= nil then
                    Core.inputState[key] = tostring(value)
                    restoredInputs += 1
                end
            end
        end
        logRestoreCount("input", savedInputs, restoredInputs)

        local restoredSliders = 0
        if type(savedSliders) == "table" then
            for key, value in pairs(savedSliders) do
                local numberValue = tonumber(value)
                if type(key) == "string" and numberValue ~= nil then
                    Core.sliderState[key] = numberValue
                    restoredSliders += 1
                end
            end
        end
        logRestoreCount("slider", savedSliders, restoredSliders)

        local restoredSelections = 0
        if type(savedSelections) == "table" then
            for key, value in pairs(savedSelections) do
                if type(key) == "string" and value ~= nil then
                    Core.selectionState[key] = tostring(value)
                    restoredSelections += 1
                end
            end
        end
        logRestoreCount("selection", savedSelections, restoredSelections)

        for _, tabData in pairs(UI.UI_DATA) do
            for _, item in ipairs(tabData.items) do
                if item.type == "slider" and item.key then
                    local minVal = item.min or 0
                    local maxVal = item.max or minVal
                    local fallback = item.default ~= nil and item.default or minVal
                    local value = tonumber(Core.sliderState[item.key])
                    if value == nil then value = tonumber(fallback) or minVal end
                    Core.sliderState[item.key] = math.clamp(value, minVal, maxVal)
                elseif item.type == "selection" and item.key then
                    local value = Core.selectionState[item.key]
                    if value ~= nil then
                        value = tostring(value)
                        if type(item.options) == "table" and #item.options > 0 and not table.find(item.options, value) then
                            Core.selectionState[item.key] = item.default or item.options[1]
                        else
                            Core.selectionState[item.key] = value
                        end
                    end
                end
            end
        end

        if type(savedConfig) == "table" then
            Core.config = Core.config or {}
            mergeSavedConfig(Core.config, savedConfig)
        end

        if Core.applyLogsConfig then
            Core.applyLogsConfig(savedLogs)
        end

        Core.debugLog(
            "Session load restored state keys count:", HS.Session.countKeys(Core.state),
            "input keys count:", HS.Session.countKeys(Core.inputState),
            "slider keys count:", HS.Session.countKeys(Core.sliderState),
            "selection keys count:", HS.Session.countKeys(Core.selectionState)
        )
    end

    HS.Dungeon.installRegionLoadedHook()
    HS.Dungeon.startPresenceWatchdog()

    for _, tabData in pairs(UI.UI_DATA) do
        for _, item in ipairs(tabData.items) do
            if item.type == "slider" and item.key and item.callback then
                item.callback(Core.sliderState[item.key])
            elseif item.type == "selection" and item.key and item.instant and item.callback then
                item.callback(Core.selectionState[item.key])
            end
        end
    end

    for key, on in pairs(Core.state) do
        local cb = Core.callbacks[key]
        if on and cb then task.spawn(cb, true) end
    end

    local gui = UI.make("ScreenGui", {Name="HeartsteelUI", ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, Parent=Core.playerGui})
    local toggleGui = UI.make("ScreenGui", {Name="HeartsteelToggleGui", ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, Parent=Core.playerGui})

    -- ── Floating toggle button ───────────────────────────────────
    local toggleButton = UI.make("ImageButton", {Parent=toggleGui, Name="ToggleButton", Size=UDim2.fromOffset(64,64), Position=UDim2.new(0,24,0.5,-32), BackgroundTransparency=1, AutoButtonColor=false, ZIndex=50})
    pcall(function()
        local iconFile = "heartsteel_toggle_icon.png"
        if not isfile(iconFile) then
            writefile(iconFile, game:HttpGet("https://raw.githubusercontent.com/Lucas-BIIks/test/refs/heads/main/image.png"))
        end
        toggleButton.Image = getcustomasset(iconFile)
    end)
    toggleButton.ScaleType = Enum.ScaleType.Crop
    UI.addCorner(toggleButton, 999)
    local buttonStroke = UI.make("UIStroke", {Parent=toggleButton, ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Thickness=2, Color=Core.C.orange, Transparency=0.15})
    UI.make("UIGradient", {Parent=buttonStroke, Rotation=35, Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Core.C.purple), ColorSequenceKeypoint.new(1,Core.C.orange)})})
    local glow = UI.make("Frame", {Name="Glow", Parent=toggleButton, BackgroundColor3=Core.C.purple, BackgroundTransparency=0.82, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.fromOffset(88,88), ZIndex=49})
    UI.addCorner(glow, 999)
    UI.make("UIGradient", {Parent=glow, Rotation=35, Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Core.C.purple), ColorSequenceKeypoint.new(1,Core.C.orange)})})
    local ring = UI.make("Frame", {Parent=toggleButton, Name="Ring", AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.fromScale(1,1), BackgroundTransparency=1, ZIndex=48})
    UI.addCorner(ring, 999)
    local ringStroke = UI.make("UIStroke", {Parent=ring, Thickness=3, Color=Core.C.purple, Transparency=0.75})
    local function tw(obj, props) return S.TweenService:Create(obj, TweenInfo.new(0.18), props) end
    local hIGlow=tw(glow,{BackgroundTransparency=0.62,Size=UDim2.fromOffset(100,100)}); local hOGlow=tw(glow,{BackgroundTransparency=0.82,Size=UDim2.fromOffset(88,88)})
    local hIStroke=tw(buttonStroke,{Thickness=3,Transparency=0}); local hOStroke=tw(buttonStroke,{Thickness=2,Transparency=0.15})
    local hIRing=tw(ringStroke,{Transparency=0.45}); local hORing=tw(ringStroke,{Transparency=0.75})
    toggleButton.MouseEnter:Connect(function() hIGlow:Play(); hIStroke:Play(); hIRing:Play() end)
    toggleButton.MouseLeave:Connect(function() hOGlow:Play(); hOStroke:Play(); hORing:Play() end)

    -- ── Main window ──────────────────────────────────────────────
    local main = UI.make("Frame", {Name="Main", Parent=gui, Size=UDim2.fromOffset(440,370), Position=UDim2.new(0.5,-220,0.5,-185), BackgroundColor3=C.window, BorderSizePixel=0})
    UI.addCorner(main, 4); UI.addStroke(main, C.border2, 1)
    local topbar = UI.make("Frame", {Name="Topbar", Parent=main, Size=UDim2.new(1,0,0,40), BackgroundColor3=C.topbar, BorderSizePixel=0})
    UI.addStroke(topbar, C.border, 1)
    local diamond = UI.make("Frame", {Parent=topbar, Size=UDim2.fromOffset(18,18), Position=UDim2.new(0,12,0.5,-9), BackgroundColor3=C.purple, Rotation=45, BorderSizePixel=0})
    UI.addCorner(diamond, 2)
    UI.make("Frame", {Parent=diamond, Size=UDim2.new(1,-6,1,-6), Position=UDim2.new(0,3,0,3), BackgroundColor3=C.window, BorderSizePixel=0})
    UI.make("TextLabel", {Parent=topbar, BackgroundTransparency=1, Position=UDim2.new(0,34,0,4), Size=UDim2.new(0,180,0,16), Text="HEARTSTEEL", Font=Enum.Font.Garamond, TextSize=17, TextColor3=C.purple, TextXAlignment=Enum.TextXAlignment.Left})
    UI.make("TextLabel", {Parent=topbar, BackgroundTransparency=1, Position=UDim2.new(0,34,0,20), Size=UDim2.new(0,180,0,14), Text="saber simulator · v3.0", Font=Enum.Font.Gotham, TextSize=10, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left})
    local mainLayout = UI.make("Frame", {Name="MainLayout", Parent=main, Position=UDim2.fromOffset(0,40), Size=UDim2.new(1,0,1,-78), BackgroundTransparency=1})
    sidebar = UI.make("ScrollingFrame", {Parent=mainLayout, Size=UDim2.new(0,110,1,0), BackgroundColor3=C.sidebar, BorderSizePixel=0, CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=3, ScrollBarImageColor3=C.border2})
    UI.addStroke(sidebar, C.border, 1)
    UI.make("UIListLayout", {Parent=sidebar, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,0)})
    UI.make("UIPadding", {Parent=sidebar, PaddingTop=UDim.new(0,8)})
    content = UI.make("ScrollingFrame", {Name="Content", Parent=mainLayout, Position=UDim2.fromOffset(110,0), Size=UDim2.new(1,-110,1,0), BackgroundColor3=C.window, BorderSizePixel=0, CanvasSize=UDim2.new(), AutomaticCanvasSize=Enum.AutomaticSize.Y, ScrollBarThickness=3, ScrollBarImageColor3=C.border2})
    UI.make("UIPadding", {Parent=content, PaddingTop=UDim.new(0,12), PaddingLeft=UDim.new(0,12), PaddingRight=UDim.new(0,12), PaddingBottom=UDim.new(0,12)})
    UI.make("UIListLayout", {Parent=content, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,2)})
    local footer = UI.make("Frame", {Parent=main, Size=UDim2.new(1,0,0,38), Position=UDim2.new(0,0,1,-38), BackgroundColor3=C.sidebar, BorderSizePixel=0})
    UI.addStroke(footer, C.border, 1)
    UI.statusDot = UI.make("Frame", {Parent=footer, Size=UDim2.fromOffset(5,5), Position=UDim2.new(0,12,0.5,-2), BackgroundColor3=C.border2, BorderSizePixel=0})
    UI.addCorner(UI.statusDot, 999)
    UI.statusText = UI.make("TextLabel", {Parent=footer, BackgroundTransparency=1, Position=UDim2.new(0,24,0,0), Size=UDim2.new(1,-140,1,0), Text="idle", Font=Enum.Font.Garamond, TextSize=12, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left})
    local allOffBtn = UI.make("TextButton", {Parent=footer, Size=UDim2.fromOffset(62,22), Position=UDim2.new(1,-128,0.5,-11), BackgroundTransparency=1, Text="ALL OFF", TextColor3=C.textDim, Font=Enum.Font.GothamBold, TextSize=10})
    UI.addCorner(allOffBtn, 2); UI.addStroke(allOffBtn, C.border, 1)
    local killBtn = UI.make("TextButton", {Parent=footer, Size=UDim2.fromOffset(52,22), Position=UDim2.new(1,-60,0.5,-11), BackgroundColor3=C.redDark, Text="KILL", TextColor3=C.red, Font=Enum.Font.GothamBold, TextSize=10})
    UI.addCorner(killBtn, 2); UI.addStroke(killBtn, Color3.fromRGB(80,24,24), 1)

    -- ── Sidebar nav ───────────────────────────────────────────────
    UI.renderSidebar()

    -- ── Button events ─────────────────────────────────────────────
    allOffBtn.MouseButton1Click:Connect(function() UI.allOff(); UI.renderContent() end)
    killBtn.MouseButton1Click:Connect(function()
        HS.Session.suppressSave = true
        Core.alive = false; UI.allOff(true); task.wait(1.5); gui:Destroy(); toggleGui:Destroy()
    end)
    toggleButton.MouseButton1Click:Connect(function() Core.uiOpen = not Core.uiOpen; main.Visible = Core.uiOpen end)

    -- ── Drag: main window ─────────────────────────────────────────
    do
        local dragging, dragStart, startPos = false, nil, nil
        topbar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging=true; dragStart=input.Position; startPos=main.Position
                input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging=false end end)
            end
        end)
        S.UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - dragStart
                main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
            end
        end)
    end

    -- ── Drag: floating button ──────────────────────────────────────
    do
        local dragging, dragStart, startPos = false, nil, nil
        toggleButton.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging=true; dragStart=input.Position; startPos=toggleButton.Position
                input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging=false end end)
            end
        end)
        S.UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - dragStart
                toggleButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
            end
        end)
    end
end
