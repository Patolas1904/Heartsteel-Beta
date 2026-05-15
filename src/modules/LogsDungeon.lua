return function(HS, S)
    HS.Logs = HS.Logs or {}
    HS.Logs.Dungeon = HS.Logs.Dungeon or {}

    local LogsDungeon = HS.Logs.Dungeon
    local Core        = HS.Core

    LogsDungeon.STATE_KEY = "dungeon_egg_timer_logs"
    LogsDungeon.UPDATE_DELAY = 0.75
    LogsDungeon.FROZEN_AFTER = 4
    LogsDungeon.CACHE_SCAN_RETRY_DELAY = 3
    LogsDungeon.slotState = LogsDungeon.slotState or {}
    LogsDungeon.timerLabels = LogsDungeon.timerLabels or {}
    LogsDungeon.nextCacheScanAt = 0

    function LogsDungeon.trim(text)
        local cleaned = tostring(text or "")
        cleaned = cleaned:gsub("^%s+", "")
        cleaned = cleaned:gsub("%s+$", "")
        return cleaned
    end

    function LogsDungeon.parseTimerSeconds(text)
        local normalized = LogsDungeon.trim(text):gsub("%s+", "")
        local h, m, s = normalized:match("^(%d+):(%d+):(%d+)$")
        if h then
            return ((tonumber(h) or 0) * 3600) + ((tonumber(m) or 0) * 60) + (tonumber(s) or 0)
        end

        m, s = normalized:match("^(%d+):(%d+)$")
        if m then
            return ((tonumber(m) or 0) * 60) + (tonumber(s) or 0)
        end

        return nil
    end

    function LogsDungeon.isFreezeCandidate(text)
        local seconds = LogsDungeon.parseTimerSeconds(text)
        return seconds ~= nil and seconds > 0
    end

    function LogsDungeon.ensureIncubatorCache()
        local Dungeon = HS.Dungeon
        if not Dungeon or type(Dungeon.scanIncubatorSlots) ~= "function" then return end
        if type(Dungeon.incubatorSlots) == "table" and #Dungeon.incubatorSlots > 0 then return end

        local now = os.clock()
        if now < (LogsDungeon.nextCacheScanAt or 0) then return end
        LogsDungeon.nextCacheScanAt = now + LogsDungeon.CACHE_SCAN_RETRY_DELAY
        Dungeon.scanIncubatorSlots()
    end

    function LogsDungeon.readSlotTimer(slotNumber)
        local Dungeon = HS.Dungeon
        if not Dungeon or type(Dungeon.readSlotTimerDirectly) ~= "function" then return "", false end

        local ok, timerText = pcall(Dungeon.readSlotTimerDirectly, slotNumber)
        if not ok then return "", false end

        timerText = LogsDungeon.trim(timerText)
        return timerText, timerText ~= ""
    end

    function LogsDungeon.getTimerRows()
        local Dungeon = HS.Dungeon
        if not Dungeon then return {} end

        LogsDungeon.ensureIncubatorCache()

        local cachedBySlot = {}
        if type(Dungeon.incubatorSlots) == "table" then
            for _, info in ipairs(Dungeon.incubatorSlots) do
                if type(info) == "table" and tonumber(info.slot) then
                    cachedBySlot[tonumber(info.slot)] = info
                end
            end
        end

        local rows = {}
        for slot = 1, (Dungeon.MAX_INCUBATOR_SLOTS or 6) do
            local cached = cachedBySlot[slot]
            local cachedTimer = cached and LogsDungeon.trim(cached.timerText) or ""
            local liveTimer, hasLiveTimer = LogsDungeon.readSlotTimer(slot)
            local timerText = hasLiveTimer and liveTimer or cachedTimer
            local isEmpty = cached and type(Dungeon.isSlotEmpty) == "function" and Dungeon.isSlotEmpty(cached.text)

            if timerText ~= "" and (not isEmpty or hasLiveTimer) then
                rows[#rows + 1] = {
                    slot = slot,
                    timerText = timerText,
                    live = hasLiveTimer,
                }
            end
        end

        return rows
    end

    function LogsDungeon.updateFreezeState(rows)
        local now = os.clock()
        local seen = {}

        for _, row in ipairs(rows) do
            local slot = row.slot
            local state = LogsDungeon.slotState[slot]
            seen[slot] = true

            if not state then
                state = {lastText = row.timerText, lastChangedAt = now, frozen = false}
                LogsDungeon.slotState[slot] = state
            elseif state.lastText ~= row.timerText then
                state.lastText = row.timerText
                state.lastChangedAt = now
                state.frozen = false
            elseif LogsDungeon.isFreezeCandidate(row.timerText) then
                state.frozen = (now - (state.lastChangedAt or now)) >= LogsDungeon.FROZEN_AFTER
            else
                state.frozen = false
            end

            row.frozen = state.frozen == true
        end

        for slot in pairs(LogsDungeon.slotState) do
            if not seen[slot] then
                LogsDungeon.slotState[slot] = nil
            end
        end
    end

    function LogsDungeon.updateLabels(rows)
        local labels = LogsDungeon.timerLabels
        if type(labels) ~= "table" then return end

        for _, label in pairs(labels) do
            if label and label.Parent then
                label.Text = ""
                label.Visible = false
                label.Size = UDim2.new(1, 0, 0, 0)
            end
        end

        for _, row in ipairs(rows) do
            local label = labels[row.slot]
            if label and label.Parent then
                local prefix = row.frozen and "(froze) " or ""
                label.Text = string.format("Egg %d: %s%s", row.slot, prefix, row.timerText)
                label.TextColor3 = row.frozen and Core.C.orange or Core.C.textDim
                label.Visible = true
                label.Size = UDim2.new(1, 0, 0, 18)
            end
        end
    end

    function LogsDungeon.refresh()
        if Core.state[LogsDungeon.STATE_KEY] ~= true then return end

        local rows = LogsDungeon.getTimerRows()
        LogsDungeon.updateFreezeState(rows)
        LogsDungeon.updateLabels(rows)
    end

    function LogsDungeon.bindTimerRows(labels)
        LogsDungeon.timerLabels = labels or {}
        if Core.state[LogsDungeon.STATE_KEY] == true then
            LogsDungeon.refresh()
        else
            LogsDungeon.updateLabels({})
        end
    end

    function LogsDungeon.clearRows()
        LogsDungeon.updateLabels({})
        LogsDungeon.timerLabels = {}
        table.clear(LogsDungeon.slotState)
    end

    function LogsDungeon.start()
        Core.loopWhile(LogsDungeon.STATE_KEY, LogsDungeon.UPDATE_DELAY, LogsDungeon.refresh)
    end

    function LogsDungeon.setEnabled(on)
        Core.state[LogsDungeon.STATE_KEY] = on == true
        if Core.state[LogsDungeon.STATE_KEY] then
            LogsDungeon.start()
        else
            LogsDungeon.clearRows()
        end
    end
end
