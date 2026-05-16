return function(HS, S)
local Core = HS.Core

Core.ClientNotifierRemote.OnClientEvent:Connect(function(eventName, rewards)
    if eventName == "DungeonReward" and typeof(rewards) == "table" then
        local handledEggReward = false
        if HS.Dungeon and HS.Dungeon.markRunEnding then
            HS.Dungeon.markRunActive("reward received")
            HS.Dungeon.markRunEnding("reward received")
        end
        for _, reward in ipairs(rewards) do
            if typeof(reward) == "table" and reward.Type == "DungeonEgg" then
                handledEggReward = true
                task.spawn(function()
                    local ok, err = pcall(HS.Dungeon.handleEggReward, reward.Name or "Unknown Egg")
                    if not ok then
                        Core.debugLog("Dungeon egg reward handler failed:", err)
                    end
                    if HS.Dungeon and HS.Dungeon.markRunEnded then
                        HS.Dungeon.markRunEnded("egg reward handled")
                    end
                end)
                break
            end
        end
        if not handledEggReward and HS.Dungeon and HS.Dungeon.scheduleRunEnd then
            HS.Dungeon.scheduleRunEnd(5, "post reward grace")
        end
    elseif eventName == "PopupText" then
        local rewardsStr = tostring(rewards or "")
        if rewardsStr:find("Clan XP") then
            Core.debugLog("Clan XP gained:", rewardsStr)
            task.delay(0.15, HS.Farming.refreshClanQuestInfo)
        end
    end
end)
end
