# Heartsteel Saber Simulator Helper - Project Context

This workspace contains a Roblox/Luau helper script for Saber Simulator.

- Active working file: `testing.lua`
- Reference/backup file: `last-working.lua`
- Future chats should read this file first, then inspect only the relevant section of `testing.lua`.
- Do not edit `last-working.lua` unless explicitly asked.

## Architecture

The script is one large Luau file organized around a top-level `HS` table. Each subsystem owns a subtable:

- `HS.Core`: shared remotes, services, runtime state, priority teleporting, shared helpers.
- `HS.Session`: save/load of UI state to `heartsteel_session.json`.
- `HS.Misc`: movement speed, anti-AFK, element switching, position helpers, egg animation hiding.
- `HS.Farming`: swing/sell, boss, crowns, KOTH, clan quests.
- `HS.AutoCycle`: cycles enabled element farming zones.
- `HS.ElementZonePull`: pulls mobs/bosses for Fire/Water/Earth/Plasma zones.
- `HS.Flags`: flag capture logic.
- `HS.Dungeon`: dungeon timer/start, dungeon farming, chest/egg/incubator handling, dungeon upgrades.
- `HS.PetdexFarm`: completes petdex eggs by buying eggs until enough pets are unlocked/opened.
- `HS.PetdexRewards`: claims petdex reward milestones.
- `HS.EggOpener`: selected page/slot egg opener.
- `HS.Merchant`: traveling merchant filters and auto-buy.
- `HS.Logs`: logging/monitoring subsystems: pet hatch webhooks, dungeon egg timer UI, and Discord live monitor.
- `HS.UI`: creates and renders all UI tabs/rows.

`Core.state` stores toggle booleans. `Core.callbacks` maps toggle keys to their callbacks. `Core.selectionState` stores dropdown selections. `Core.sliderState` stores slider values. `Core.inputState` stores text input values such as webhook URLs. `Core.config.Logs` stores structured log/webhook config derived from state and inputs.

UI is declared in `HS.UI.UI_DATA`; rows are rendered by `UI.renderContent()` through row builders such as `UI.makeToggleRow`, `UI.makeSliderRow`, `UI.makeInputRow`, `UI.makeStatusRow`, etc.

Last context sync: 2026-05-12, against active `testing.lua`, `healthcheck.lua`, and the private Health API GitHub repo.

Recent synced changes:

- Health check now uses a public executor-side probe that sends safe runtime facts to the Render API. Private pass/warn/fail scoring must stay server-side in `scorer.js`.
- Health check now emits compact Petdex event egg facts under `checks.petdexEventEggs`; the private scorer consumes those facts server-side.
- Health API repo `Patolas1904/heartsteel-health-api` was updated through the GitHub connector. Commit `7918e79d3012491d8f372a3596dd77a91a8f41e8` on `main` scores dungeon watchdog, teleport-protection, dungeon target fallback presence facts, persistent dungeon run-protection facts, and the 2-second dungeon start delay.
- Health API repo commit `1f732de004c98d0c684f1fa4708461e5cfc23b30` on `main` scores the Petdex event egg safe facts.
- Petdex reward egg completion now includes event/limited eggs detected from `PetsInfo.Eggs - PetShopInfo`, while Auto Petdex farming remains limited to shop/current eggs.
- Dungeon teleport protection now uses persistent runtime state (`Dungeon.runProtectionActive`) once dungeon presence/bots are detected, so world teleports remain blocked between bot waves until a reward/chest/lobby/end signal or the long timeout releases protection.
- Health check now emits safe facts for `Dungeon.hasDungeonTargets`, `Dungeon.isDungeonPresenceActive`, run-protection helpers, `Dungeon.refreshPresenceLock`, `Dungeon.VALID_SPAWNERS`, `Dungeon.VALID_TARGETS`, `Dungeon.START_REMOTE_DELAY`, `Dungeon.RUN_PROTECTION_TIMEOUT`, controlled `presenceFallbackProbe`, and controlled `runProtectionProbe`.
- Session restore in `testing.lua` now broadly restores saved runtime keys, including dynamic merchant filters and log/Discord monitor toggles. `KILL` suppresses all session saves during shutdown so it cannot overwrite or reset the saved session.

## Health Check

The Heartsteel health check is split between a public executor probe and a private server-side scorer.

Current working flow:

1. The executor runs a public probe script.
2. The probe collects safe facts about the Heartsteel client runtime.
3. The probe sends those facts as JSON to:

```text
https://heartsteel-health-api.onrender.com/healthcheck
```

4. The Render API receives the POST request.
5. `server.js` handles the Express route.
6. `scorer.js` contains the private pass/warn/fail scoring logic.
7. The API returns a JSON response with `verdict`, `errors`, `warnings`, and `messages`.
8. The executor probe prints the returned result.

Purpose:

- The executor-side probe is allowed to be public and readable.
- Private scoring rules must stay server-side in `scorer.js`.
- Do not move scoring logic back into the executor probe.
- Do not expose private scoring rules in client-side code.
- Do not send sensitive values such as webhook URLs, tokens, cookies, or secrets.
- Only send safe boolean/status facts from the client.
- Petdex event egg diagnostics live under `checks.petdexEventEggs` and must stay compact: booleans, counts, and status strings only. Do not send egg names, pet names, client data, webhook URLs, tokens, or other large/sensitive values.
- Keep the Render API compatible with Node/Express and Render's `PORT` environment variable.

Confirmed working on 2026-05-10:

```text
POST /healthcheck
runtimeFound: true
runtimeLabel: getgenv().__HeartsteelHS
version: 3.0
build: 2026-05-10-testing-mode
verdict: pass
errors: 0
warnings: 0
```

## Health API GitHub Repository

Private repo:

```text
Patolas1904/heartsteel-health-api
```

Known repo context:

- Default branch: `main`.
- GitHub connector access was confirmed on 2026-05-10 with read/write permissions.
- `server.js`: Node/Express app, handles `POST /healthcheck`, imports `scoreHealthCheck` from `./scorer.js`, listens on Render-compatible `process.env.PORT || 3000`.
- `scorer.js`: private health scoring rules. Keep pass/warn/fail logic here, not in executor-side Lua.
- `package.json`: ESM Node app (`"type": "module"`), `npm start` runs `node server.js`, Express dependency.

Latest known server-side scorer update:

- Commit: `1f732de004c98d0c684f1fa4708461e5cfc23b30`
- Branch: `main`
- Purpose: score safe probe facts for `Core.lockWorldTeleports`, `Core.isWorldTeleportBlocked`, `checks.core.loopHealth.dungeon_presence_watchdog`, `checks.dungeon.teleportProtection.ok/stateRestored`, the dungeon target fallback presence probe, persistent dungeon run-protection probe, 2-second start remote delay, 20-minute run-protection timeout, and compact `checks.petdexEventEggs` diagnostics.

Rules for future work:

- Do not put private scoring thresholds or failure logic in `healthcheck.lua` or other public executor probes.
- If the Lua probe adds new safe facts, update `scorer.js` to consume them server-side.
- Never store or send webhook URLs, tokens, cookies, Render env values, or other secrets in this context file or in probe payloads.
- If Render behavior does not match the latest GitHub commit, check Render deployment status/source branch before changing code.

## Core Helpers

Important shared objects/helpers:

- `Core.player`: `Players.LocalPlayer`
- `Core.playerGui`: player GUI root
- `Core.UIActionRemote`: `ReplicatedStorage.Events.UIAction`
- `Core.ClientNotifierRemote`: `ReplicatedStorage.Events.ClientNotifierEvent`
- `Core.Gameplay`: `workspace.Gameplay`
- `Core.BossHolder`: `workspace.Gameplay.Boss.BossHolder`
- `Core.CurrencyHolder`: `workspace.Gameplay.CurrencyPickup.CurrencyHolder`
- `Core.debugLog(...)`: gated by `Core.state.debug_mode`
- `Core.fireUI(...)`: forwards to `Core.UIActionRemote:FireServer(...)`
- `Core.getRoot()`: current `HumanoidRootPart`
- `Core.getEquippedRemote()`: finds equipped weapon `RemoteClick`
- `Core.getClientDataManager()`: cached require of `Players.LocalPlayer.PlayerScripts.MainClient.ClientDataManager`
- `Core.loopWhile(key, delay, fn)`: duplicate-safe loop helper based on `Core.activeLoops`
- `Core.teleportWorld(cf, reason, shouldContinue)`: priority-aware teleport
- `Core.setCurrentAction(action, ttl)`: records the explicit runtime action shown in Discord Monitor.
- `Core.clearCurrentAction(action)`: clears the action only if it still matches, or always clears when called without an argument.
- `Core.getCurrentAction()`: returns the explicit action, expiring it back to `Idle` when its TTL has passed.

`Core.debugLog(...)` also forwards the latest debug message to `HS.Logs.DiscordMonitor.setLastDebugMessage(...)` when the monitor subsystem is loaded. Do not debug-log webhook URLs.

The script uses a service proxy:

```lua
local S = setmetatable({}, {
    __index = function(_, k) return game:GetService(k) end
})
```

Use `S.RunService`, `S.ReplicatedStorage`, etc. rather than creating duplicate service locals.

## Priority System

World teleports are coordinated through `Core.priorityOwner` and `Core.priorityRanks`:

```lua
Core.priorityRanks = {clan_quests=0, dungeon=1, flags=2, boss=3, auto_cycle=4, eggs=5, king=6}
```

Lower number means higher priority.

- Dungeon blocks world teleports entirely while active.
- Flags outrank boss.
- Boss outranks auto-cycle, egg/pet systems, and king.
- Lower-priority systems should pause or wait when a higher-priority owner is active.
- If flags are merely toggled on but are not actively holding `Core.priorityOwner = "flags"`, boss and lower-priority systems may run.
- Simulate Movement is an Anti-AFK-adjacent Misc feature, not a priority participant. It must not depend on `Core.priorityOwner`, current action, auto-cycle, boss, Petdex, flags, egg opener, merchant, or other enabled toggles. Its only valid skip condition is active dungeon detection via `HS.Dungeon.isInsideActive()` or the existing equivalent active-dungeon check.

Teleport reasons mapped by `Core.getTeleportPriority(reason)` include:

- `"flag capture"` -> `flags`
- `"clan quest"` -> `clan_quests`
- `"boss"` -> `boss`
- `"auto cycle"` -> `auto_cycle`
- `"pet shop"` -> `eggs`
- `"king"` -> `king`

## UI And Session

`HS.UI.UI_DATA` defines tabs:

- `farming`
- `upgrades`
- `elements`
- `areas`
- `clan`
- `pets`
- `Dungeon`
- `merchant`
- `logs`
- `misc`
- `session`

`TAB_ORDER` controls sidebar order.

Session persistence:

- File name: `heartsteel_session.json`
- Saves toggles, selections, sliders, inputs, and structured `Logs` config.
- Uses executor APIs: `isfile`, `readfile`, `writefile`, optionally `delfile`.
- Existing sessions can restore toggles on script startup, so callbacks must be duplicate-safe.
- Startup order is: build UI defaults with `HS.Session.applyUiDefaults()`, load saved session, broadly merge saved runtime state, clamp/validate known UI sliders/selections, merge saved config/logs, install the dungeon region-loaded hook and start the dungeon presence watchdog, start callbacks for enabled toggles, render UI.
- Saved values override defaults. Defaults should only fill missing keys.
- Do not discard saved keys just because they are not currently present in `UI.UI_DATA`.
- Toggle restore must merge every saved string key with a boolean value into `Core.state`.
- Input restore must merge every saved string key with a non-nil value into `Core.inputState` as `tostring(value)`.
- Slider restore must merge every saved string key with a numeric value into `Core.sliderState` as `tonumber(value)`, then clamp known UI sliders to their configured min/max.
- Selection restore must merge every saved string key with a non-nil value into `Core.selectionState` as `tostring(value)`, then validate known UI selections against `item.options` when options exist.
- Dynamic keys must survive load. Important examples: `merchant_item_<listingIndex>`, `discord_monitor_show_element_levels`, `discord_monitor_show_mastery_levels`, `discord_monitor_show_dungeon_eggs`, `discord_monitor_show_session_stats`, and `discord_monitor_show_connection_stats`.
- Merchant item filters are generated dynamically and must not require opening the merchant tab before restore. If the session contains `Core.state["merchant_item_8"] = true`, that key must remain true after load until the merchant UI is generated.
- Session load debug logs should report saved/restored key counts for toggles, inputs, sliders, and selections. Never print webhook URLs.
- Session reset deletes/empties the saved file, clears runtime `Core.state`, `Core.inputState`, `Core.sliderState`, `Core.selectionState`, and `Core.config`, then rebuilds defaults from `UI.UI_DATA`. Old dynamic keys must not remain in memory after reset.
- `UI.allOff()` saves the all-off state when the user clicks `ALL OFF`.
- The `KILL` button must not reset or overwrite the saved session. It sets `HS.Session.suppressSave = true` before `UI.allOff(true)`, so even indirect callback saves are refused during shutdown.

Text inputs:

- `UI.makeInputRow(item)` renders `TextBox` rows.
- On `FocusLost`, input text is stored in `Core.inputState[item.key]` and `HS.Session.save()` is called.
- `Core.inputState.pet_webhook_url` stores the pet hatch Discord webhook URL. Do not print or debug-log webhook URLs.
- `Core.syncLogsConfig()` mirrors log toggles/inputs into `Core.config.Logs`; `Core.applyLogsConfig(savedLogs)` restores saved log settings.

Floating toggle button:

- Uses `heartsteel_toggle_icon.png` as the cached custom asset filename.
- Downloads from `https://raw.githubusercontent.com/Lucas-BIIks/test/refs/heads/main/image.png` if the file is missing.
- The button is circular (`UICorner` radius 999).
- Hover glow is a circular `Frame` with `UICorner`, not the old square glow image.

## Farming

State keys in the FARMING tab include:

- `swing`: calls `Core.SwingSaberRemote:FireServer()` on `Core.SWING_DELAY`.
- `sell`: calls `Core.SellStrengthRemote:FireServer()` on `Core.SELL_DELAY`.
- `boss`: Auto Farm Boss.
- `boss_tp`: compact child toggle for Auto TP Boss.
- `crowns`: auto-collects current and newly added currency pickups.
- `claim_flags`: starts flag capture.
- `flag_avoid`: compact toggle used by flags to avoid nearby players.
- `claim_koth`: KOTH/King positioning.
- `koth_avoid`: avoids KOTH if other players are nearby.

Crowns uses `Core.CollectCurrencyRemote:FireServer({[1]=obj})` and a `ChildAdded` connection. Disconnect `HS.Farming.crownsConnection` when stopped.

KOTH uses `Core.KOH_BOUNDARY`, priority `king`, and `Core.teleportWorld(..., "king", ...)`.

Clan quest claiming is in `Farming.startClanQuest()`, using:

```lua
Core.UIActionRemote:FireServer("ClaimClanQuest", i)
```

The old clan `Auto Farm Route` was removed. Do not reintroduce `clanfarm`, `FARM_ROUTE`, `FARM_DURATION`, or `farmStatusLabel` unless requested.

## Normal Auto Purchase

The `upgrades` tab is for normal non-dungeon auto purchases:

- `saber`: `Farming.startSaber()`
- `dna`: `Farming.startDNA()`
- `class`: `Farming.startClass()`
- `bossdmg`: `Farming.startBossDmg()`
- `aura`: `Farming.startAura()`
- `petaura`: `Farming.startPetAura()`

Normal Boss Damage is not a dungeon upgrade. Its state key is `bossdmg`, and the loop must remain duplicate-safe:

```lua
Core.loopWhile("bossdmg", Core.BUY_DELAY, function()
    Core.UIActionRemote:FireServer("BuyAllBossBoosts")
end)
```

Do not route normal Boss Damage through `Dungeon.startUpgrade(...)`, `dungeon_DungeonDamage`, or `BuyDungeonUpgrade`.

## Boss System

FARMING tab UI:

- `boss`: `Auto Farm Boss`
- `boss_tp`: compact `Auto TP Boss`
- Status row: `{type="status", bind="boss", text="Boss: idle"}`

Cached paths:

```lua
workspace.Gameplay.Boss.BossHolder.Boss
workspace.Gameplay.Boss.BossHolder.Boss.HumanoidRootPart
workspace.Gameplay.Boss.ArenaBase
workspace.Gameplay.Boss.ArenaGui.BillboardGui.Frame.TextLabelBottom
```

Teleport position:

```lua
Core.BOSS_POS = CFrame.new(417.53, 187.38, 143.61)
```

Behavior:

- Boss is considered spawned only when the Boss model and its `HumanoidRootPart` exist.
- Auto Farm Boss follows/attacks only when the player is inside `ArenaBase`.
- If outside arena and `boss_tp` is on, it teleports to `Core.BOSS_POS` with reason `"boss"`.
- `boss_tp` does nothing unless `boss` is also true.
- Follow uses `Humanoid:MoveTo()` and a radius, currently `Farming.BOSS_FOLLOW_DISTANCE = 14`.
- Attack uses `Core.getEquippedRemote()` and fires at the Boss model:

```lua
remote:FireServer({boss})
```

- Do not attack the boss `HumanoidRootPart`.
- Uses one Heartbeat connection (`Farming.bossHeartbeat`), one attack loop (`Farming.bossAttackThread`), and one status loop (`Farming.bossStatusThread`).
- Boss status updates every 0.5s.
- Boss should yield to an actual higher priority owner, especially active flag captures, but not to the flags toggle while flags are idle.
- `Farming.isBossFarmActive()` is the runtime guard for lower-priority region farming. It requires Auto Farm Boss to be on with the boss status loop running, a live Boss model, and a live Boss `HumanoidRootPart`; it returns true while boss attack/follow is active, `Core.priorityOwner == "boss"`, or the player is in the arena and boss priority can be used.

## Elements And Auto Cycle

`HS.AutoCycle` cycles selected element pull state keys:

- `fire_starter_pull`, `fire_advanced_pull`, `fire_master_pull`, `fire_grandmaster_pull`
- `water_starter_pull`, `water_advanced_pull`, `water_master_pull`, `water_grandmaster_pull`
- `earth_starter_pull`, `earth_advanced_pull`, `earth_master_pull`, `earth_grandmaster_pull`
- `plasma_starter_pull`, `plasma_advanced_pull`, `plasma_master_pull`, `plasma_grandmaster_pull`

Auto Cycle:

- Uses `AutoCycle.POSITIONS` and `AutoCycle.ORDER`.
- Claims priority `auto_cycle`.
- Stops other `ElementZonePull` zones before starting a new one.
- Waits minimum dwell time before checking targets.
- Moves to next zone when targets are gone or timeout is reached.
- Pauses during dungeon world-teleport blocks.
- Runtime-pauses, but does not disable, while `Farming.isBossFarmActive()` is true. This prevents the previous active region from continuing to pull/attack mobs during boss farming and lets Auto Cycle resume after the boss stops.

`HS.ElementZonePull`:

- Locates element folders in `Gameplay.Map.ElementZones` or `Gameplay.RegionsLoaded`.
- Handles duplicate `Important` child folders.
- For each target, pulls model parts near the player using Heartbeat.
- Uses an attack thread that fires the equipped remote at targets.
- For auto-cycle, only the active cycle key should run.
- Its shared `canRunState(stateKey)` guard returns false during active boss farming via `Farming.isBossFarmActive()`, so both the Heartbeat pull and hit thread yield without disconnecting or mutating UI state.

## Flags

`HS.Flags.startCaptureFlags()`:

- Clears debug circles when debug/claim state changes.
- Reads flags from `workspace.Gameplay.Flags`.
- Uses `Flags.getFlagInfo()` to read flag/base/owner.
- Uses `Flags.getExpectedHeightFromPosition()` with `Core.FLAG_TARGETS`.
- If `flag_avoid` is on, skips flags with nearby players.
- Claims priority `flags` only while actively teleporting/capturing.
- Releases priority after each flag and after each full check cycle.
- Rechecks every 15 seconds.

Boss and lower-priority systems may run during the recheck wait because `flags` priority is released.

## Action Tracking

Discord Monitor's `Current Action` field is driven by explicit runtime action calls, not by scanning every enabled toggle.

Current action rules:

- Connection states win first: `Rejoining Server` and `Teleporting`.
- Active dungeon state wins over stale non-dungeon actions.
- Dungeon action order is:
  - `Handling Dungeon Egg`
  - `Farming Dungeon Enemies`
  - `Running Dungeon`
- Otherwise, a non-idle explicit action from `Core.getCurrentAction()` is shown.
- If none apply, the monitor shows `Idle`.
- `Core.priorityOwner` is not itself a monitor action source.

Known explicit action labels:

- `Auto Farming Boss`
- `Claiming King`
- `Running Dungeon`
- `Opening Eggs for Petdex`
- `Opening Eggs`
- `Auto Cycle Farming`
- `Capturing Flags`
- `Handling Dungeon Egg`
- `Farming Dungeon Enemies`
- `Claiming Dungeon Chest`
- `Claiming Petdex Rewards`
- `Opening Selected Egg`
- `Buying Merchant Items`
- `Teleporting`
- `Rejoining Server`

Do not add `Claiming Incubator Eggs` as a current action. The incubator claim loop should silently check/hatch ready eggs and let the monitor show the real active task, dungeon state, or `Idle`.

## Dungeon

Dungeon key pieces:

- `start_dungeon`: timer-based auto queue/start.
- `farm_dungeon`: hover/farm dungeon enemies.
- `dungeon_height`: hover height slider.
- `farm_chest`: claim dungeon chests.
- `farm_egg`: equip/handle best dungeon egg reward.
- `claim_egg`: claim ready incubator eggs.
- `avoid_sun`: skip ready Sun eggs.
- dungeon upgrade toggles listed below.

Dungeon timer:

- Source is the Dungeon Lobby `DungeonSelect.Attachment.BillboardGui.Frame.Desc`.
- `Dungeon.watchTimerSource()` watches text changes.
- `Dungeon.getEffectiveTimerText()` caches countdown if UI text disappears.
- When timer is `"Queue Up"` and `start_dungeon` is enabled, it fires:

```lua
Core.UIActionRemote:FireServer("DungeonGroupAction", "Create", privacy, dungeonType, difficulty)
Core.UIActionRemote:FireServer("DungeonGroupAction", "Start")
```
- `Dungeon.START_REMOTE_DELAY = 2`; wait this long between `DungeonGroupAction, "Create"` and `"Start"` so the group settles before force-starting.
- Before Create/Start, auto-start must defer if `Dungeon.isRunProtectionActive()`, `Dungeon.isDungeonPresenceActive()`, or `Dungeon.isInsideActive()` reports active/protected dungeon state. Skipping due to active protection must not consume `Dungeon.queueHandled`.

Dungeon active state:

- `Dungeon.isInsideActive()` checks `workspace.DungeonStorage`.
- `Dungeon.hasDungeonTargets()` is a conservative fallback that only looks under `workspace.DungeonStorage` for `Important` children matching `Dungeon.VALID_SPAWNERS` and live models matching `Dungeon.VALID_TARGETS`.
- `Dungeon.isDungeonPresenceActive()` is the stronger shared presence helper: `Dungeon.isInsideActive()` OR `Dungeon.hasDungeonTargets()`.
- `Dungeon.markRunActive(reason)` sets persistent dungeon run protection, refreshes `Core.lockWorldTeleports(3)`, and records activity.
- `Dungeon.isRunProtectionActive()` is the persistent protection helper. It remains true between waves and includes a conservative timeout via `Dungeon.RUN_PROTECTION_TIMEOUT = 20 * 60`.
- `Dungeon.markRunEnding(reason)` keeps protection during reward/chest handling while noting that the run is ending.
- `Dungeon.markRunEnded(reason)` releases run protection, clears the dungeon priority lock, resets auto-start debounce, and schedules the guarded deferred auto-start retry.
- `Dungeon.refreshPresenceLock()` uses `Dungeon.isDungeonPresenceActive()` and `Dungeon.isRunProtectionActive()` before/after calling `Dungeon.updateAutoStartState()`.
- `Core.lockWorldTeleports(seconds)` blocks world teleports while dungeon is active.
- `Core.isWorldTeleportBlocked()` must read `Dungeon.isRunProtectionActive()` before falling back to current dungeon presence.
- A namecall hook watches `SetRegionLoaded, "Dungeon Lobby"` to mark dungeon ended, but holds protection if `Dungeon.eggRewardPending` is still being handled.
- `Dungeon.startPresenceWatchdog()` starts one duplicate-safe loop with key `dungeon_presence_watchdog`.
- The watchdog calls `Dungeon.refreshPresenceLock()` immediately at startup, then about every 1 second, and refreshes `Core.lockWorldTeleports(3)` while current presence or persistent run protection is active.
- Startup calls `HS.Dungeon.installRegionLoadedHook()` and `HS.Dungeon.startPresenceWatchdog()` before restored toggle callbacks, independently of the `start_dungeon` toggle, so reload/rejoin while already inside a dungeon still blocks world teleports.
- When the player is not inside an active dungeon, the watchdog does nothing and should not permanently lock teleports.

Dungeon farming:

- `Dungeon.startFarm()` uses a Heartbeat hover connection and a hit thread.
- Valid spawners/targets are listed in `Dungeon.VALID_SPAWNERS` and `Dungeon.VALID_TARGETS`.
- Hover position is based on target pivot and `Dungeon.HEIGHT`.

Incubator/egg handling:

- `Dungeon.openIncubatorMenu(closeAfter)` can directly show `DungeonIncubator` or try an incubator button.
- `Dungeon.MAX_INCUBATOR_SLOTS = 6`; scanner, logs UI, and Discord Monitor should use this constant instead of hard-coding a slot count.
- `Dungeon.scanIncubatorSlots()` reads slots 1 through `Dungeon.MAX_INCUBATOR_SLOTS`.
- `Dungeon.FORCE_CLAIM_INTERVAL = 120`.
- `Dungeon.lastForceClaimAttempt` tracks force-claim attempts per slot.
- `Dungeon.tryClaimEggs()` scans fresh and only acts on occupied slots.
- Claim priority is: clearly ready/open/claim/hatch -> claim immediately; otherwise, if occupied and the per-slot force cooldown elapsed -> attempt `HatchDungeonEgg` anyway; otherwise wait.
- Visible incubator timers are informational only and must not permanently block claiming.
- Force claims use the existing hatch action and are debounced per slot; do not spam `HatchDungeonEgg` every loop tick.
- Empty slots are skipped and should not be force-claimed.
- `Dungeon.handleEggReward(eggName)` decides whether to put the reward egg into an empty/weaker slot.
- Claiming ready incubator eggs is intentionally not a `Core.setCurrentAction(...)` action. Do not reintroduce `Claiming Incubator Eggs`.

Dungeon upgrades:

- No UI price scanning.
- No GUI button clicking.
- Requires `ReplicatedStorage.Modules.DungeonUpgradeShop` once via `Dungeon.getUpgradeShopInfo()` and caches the result.
- Reads current levels from `Core.getClientDataManager().Data.DungeonUpgrades`; nil level means `0`.
- Reads available shards from `Core.getClientDataManager().Data.DungeonShards`; prefer this over GUI shard text.
- `Dungeon.getUpgradeMaxLevel(upgradeType)` reads max numeric level from `DungeonUpgradeShop[upgradeType].Upgrades`.
- `Dungeon.getUpgradeNextCost(upgradeType, currentLevel)` reads `DungeonUpgradeShop[upgradeType].Upgrades[currentLevel + 1].Price`.
- `Dungeon.startUpgrade(upgradeType)` keeps using `Core.loopWhile("dungeon_" .. upgradeType, Core.BUY_DELAY, ...)`.
- If current level is already max, `Dungeon.setUpgradeToggleOff(upgradeType, "max level")` sets `Core.state["dungeon_" .. upgradeType] = false`, saves session state if available, and refreshes the Dungeon tab only if it is currently active.
- If the next cost is missing or shards are below cost, the loop waits and does not fire the buy remote.
- Uses `Dungeon.lastUpgradeBuy[upgradeType .. ":" .. nextLevel]` as a per-upgrade/per-level debounce; wait at least 1 second between attempts for the same upgrade level.
- Only fires when the upgrade is affordable:

```lua
Core.UIActionRemote:FireServer("BuyDungeonUpgrade", upgradeType, currentLevel + 1)
```

Supported state keys:

- `dungeon_DungeonCoins`
- `dungeon_DungeonCritChance`
- `dungeon_DungeonCrowns`
- `dungeon_DungeonDamage`
- `dungeon_DungeonEggSlots`
- `dungeon_DungeonHealth`
- `dungeon_DungeonSprint`
- `dungeon_IncubatorSpeed`

## Petdex Farm

`HS.PetdexFarm` initializes from:

- `ReplicatedStorage.Modules.PetsInfo.Eggs`
- `ReplicatedStorage.Modules.PetsInfo.PetShopInfo`
- `Core.getClientDataManager()`

It builds:

- `Petdex.eggOrder`
- `Petdex.eggPets`
- `Petdex.eventEggs`
- `Petdex.eventEggOrder`
- `Petdex.eventEggPets`

It reads:

- `ClientData.Data.Index` for owned/unlocked pets.
- `ClientData.Data.EggsOpened` for opened counts.

Auto Petdex:

- Uses `petdex_skip` slider.
- Uses `petdex_ignore_secrets`.
- Can auto-teleport to pet shop if `petdex_auto_teleport` is enabled.
- Uses priority `eggs`.
- Buys eggs with:

```lua
Core.UIActionRemote:FireServer("BuyEgg", eggName)
```

### Event Egg Completion Tracking

Petdex reward egg completion includes event/limited/seasonal/special eggs.

`ReplicatedStorage.Modules.PetsInfo.Eggs` is the full egg definition source. `ReplicatedStorage.Modules.PetsInfo.PetShopInfo` is the normal/current shop egg source. Event eggs are detected dynamically as eggs present in `PetsInfo.Eggs` but absent from `PetShopInfo`.

Event eggs are used for completion tracking and Petdex reward accuracy only. They are stored separately from normal farmable eggs and must not be inserted into Auto Petdex farming targets unless they also appear in `PetShopInfo`.

Pet lists are extracted from `eggData.Odds`; the keys are pet names. Owned pets come from `Core.getClientDataManager().Data.Index`. Event egg completion uses the same regular/secret-pet rules as normal egg completion, and completed event eggs count toward Petdex rewards with `EggsNeeded`.

Do not use `EggsOpened` as completed egg count. Do not use keyword matching, seasonal word lists, hardcoded event egg names, or hardcoded pet names.

## Petdex Rewards

`HS.PetdexRewards` no longer uses a hardcoded reward list.

It dynamically requires:

```lua
ReplicatedStorage.Modules.PetdexRewardInfo
```

Expected module structure:

```lua
PetdexRewardInfo.Items
```

Reward keys can include:

- `Pets50`, `Pets100`, `Pets450`, `Pets2250`
- `Eggs25`, `Eggs50`, `Eggs250`

Each item may contain:

- `PetsNeeded`
- `EggsNeeded`
- `Order`
- `RewardText`
- `Rewards`
- `ItemName`

Runtime fields:

- `Rewards.rewardInfo`
- `Rewards.rewardList`
- `Rewards.ClientData`
- `Rewards.status`

Build behavior:

- `Rewards.buildRewardList()` includes rewards with either `PetsNeeded` or `EggsNeeded`.
- Sorts by `Order` if present, otherwise by needed amount, then key.
- Logs loaded reward count.

Snapshot behavior:

- `Rewards.getUnlockedCount()` counts owned/unlocked pets from `ClientData.Data.Index`.
- `Rewards.getCompletedEggCount()` counts normal eggs plus completed event eggs where every regular pet in that egg is owned.
- Egg reward completion ignores the `petdex_skip` slider. Skip only affects Auto Petdex farming targets, not reward eligibility.
- Secret pets are not required for egg reward completion; this mirrors Auto Petdex's existing 10-pet egg handling by requiring the first 9 regular pets.
- Duplicate egg keys are counted once when calculating egg rewards.
- `Rewards.getClaimedSet()` reads `ClientData.Data.PetdexRewardsClaimed`.
- Claimed detection supports both `PetsXXX` and `EggsXXX`.
- Claimable rewards are based on:
  - `PetsNeeded <= unlocked pet count`
  - `EggsNeeded <= completed normal + event egg count`

Claim behavior:

```lua
Core.UIActionRemote:FireServer("ClaimPetdexReward", rewardKey)
```

Use the exact reward key from the module, such as `Pets450` or `Eggs250`.

The loop/state/runId behavior should remain as-is:

- `Rewards.STATE_KEY = "auto_petdex_rewards"`
- `Rewards.CLAIM_DELAY = 0.3`
- `Rewards.SCAN_DELAY = 5`
- `Rewards.runId` invalidates old runs.

Debug logs include:

- loaded reward count
- unlocked pets count
- completed normal/event/total eggs count
- claimed count
- each reward being claimed

Healthcheck:

- `healthcheck.lua` reports compact event egg diagnostics under `checks.petdexEventEggs`.
- Facts include Petdex table/helper presence, normal/event/total egg counts, completed egg counter presence, event-eggs-excluded-from-farming status, and an Odds extraction status.
- The probe must never send full egg lists, pet lists, client index data, webhook URLs, tokens, cookies, or executor identifiers.

## Egg Opener

`HS.EggOpener`:

- Initializes from `PetShopInfo`.
- Builds `EggOpener.eggOrder`.
- Uses sliders:
  - `egg_opener_page`
  - `egg_opener_slot`
- Checks if selected egg is unlocked via `ClientData.Data.EggsOpened`.
- If selected egg is valid and player is in shop, fires:

```lua
Core.UIActionRemote:FireServer("BuyEgg", selectedEggName)
```

It shares pet shop teleport priority with Petdex systems.

## Logs

### Dungeon Egg Timers

`HS.Logs.Dungeon` handles the in-UI dungeon egg timer display under the logs tab.

Dungeon egg timer logs and Discord Monitor dungeon timer fields are display-only. They may show live or frozen timer text, but must not control `Dungeon.tryClaimEggs()`, incubator scanning, reward handling, or teleport safety.

State/UI:

- Toggle key: `dungeon_egg_timer_logs`
- Label: `Dungeon Egg Timers`
- Update delay: `LogsDungeon.UPDATE_DELAY = 0.75`
- Frozen timer threshold: `LogsDungeon.FROZEN_AFTER = 4`

Behavior:

- Uses `Dungeon.scanIncubatorSlots()` only when the slot cache is empty, with retry throttling.
- Reads live slot timers with `Dungeon.readSlotTimerDirectly(slotNumber)`.
- `LogsDungeon.getTimerRows()` returns non-empty/timer-present slots.
- `LogsDungeon.updateFreezeState(rows)` marks timers as frozen when a positive countdown text has not changed for at least 4 seconds.
- `LogsDungeon.updateLabels(rows)` displays rows like `Egg 2: 00:14:32` or `Egg 2: (froze) 00:14:32`.
- `LogsDungeon.clearRows()` hides labels and clears frozen-slot state when disabled.

Discord Monitor reuses the same timer/freeze helpers, but formats all incubator slots from `Dungeon.MAX_INCUBATOR_SLOTS` in the webhook embed:

```text
Egg 1: Empty
Egg 2: Ready
Egg 3: (froze) 00:04:11
Egg 4: Unknown
Egg 5: Empty
Egg 6: Empty
```

### Pet Hatch Webhook

`HS.Logs.Pets` handles Discord pet hatch webhook logging.

UI:

- Sidebar tab: `logs`, label `LOGS`.
- Section title: `Pets`.
- Master toggle key: `pet_webhook_enabled`.
- Webhook URL input key: `pet_webhook_url`.
- Rarity toggles:
  - `pet_webhook_1star`
  - `pet_webhook_2star`
  - `pet_webhook_3star`
  - `pet_webhook_4star`
  - `pet_webhook_5star`
  - `pet_webhook_1moon`
  - `pet_webhook_2moon`
  - `pet_webhook_3moon`
  - `pet_webhook_secret`

Defaults:

- Master toggle is off.
- Webhook URL is empty.
- All rarity toggles are off.
- Do not hardcode personal Discord webhook URLs.
- Do not print or expose webhook URLs in logs.

Event source:

```lua
ReplicatedStorage.Events.EggHatchResult.OnClientEvent
```

Arguments:

- `args[1]`: table of pet names.
- `args[2]`: table of pet type strings, sometimes empty.
- `args[6]`: egg name.
- Do not use `args[3]`, `args[4]`, or `args[5]` for rarity/type/shiny/rainbow/void detection.

GUI source:

```lua
Players.LocalPlayer.PlayerGui.MainGui.OtherFrames.OpenEggs.Eggs
```

Visible hatch frames are children named `Example`. Use `LogsPets.isActuallyVisible(obj)` so the frame and all GUI parents must be visible.

Frame reads:

- Pet name comes from `Example.PetType.Text`. Ignore blank and `"Pet Name"`.
- Rarity comes from `Example.RarityImg.Image`.
- Type comes from visible labels under `Example.ClassText`: `Golden`, `Shiny`, `Rainbow`, `Void`; otherwise `Normal`.
- Thumbnail candidates include `FlatPet`, `PetImage`, `PetIcon`, `Icon`, `Pet`.
- Thumbnail ignores image names containing `RarityImg`, `Flash`, `SecretBKG`, `background`, `delete`, `trash`, `AutoDeleted`, or `AutoCrafted`.

Timing/matching:

- `LogsPets.waitForReadyHatchFrames(expectedCount, 6, expectedPetCounts)` waits up to about 6 seconds.
- It requires non-placeholder pet text and a nonblank rarity image.
- It waits briefly after the hatch event and matches visible frame pet names against `args[1]` to avoid stale frames from a previous hatch.

Rarity image map lives inside `HS.Logs.Pets` as `RARITY_IMAGE_MAP`.

Current known entries:

- `rbxassetid://117998638140155` -> `1Star`, displayed as 1 Star.
- `rbxassetid://101681619163898` -> `2Star`, displayed as 2 Star.
- `rbxassetid://71217129344355` -> `3Star`, displayed as 3 Star.
- `rbxassetid://85204807527224` -> `4Star`, displayed as 4 Star.
- `rbxassetid://72954799348276` -> `5Star`, displayed as 5 Star.
- `rbxassetid://90375810566006` -> `1Moon`, displayed as 1 Moon.
- `rbxassetid://135133438925164` -> `2Moon`, displayed as 2 Moon.
- `rbxassetid://108817778982252` -> `3Moon`, displayed as 3 Moon.
- `rbxassetid://103333899383000` -> `Secret`, displayed as Secret.

Unknown/unmapped rarity images are treated as:

```lua
{Label = "Secret", Key = "Secret"}
```

Filtering:

- `LogsPets.shouldSendPetWebhook(rarityKey)` requires master toggle on, valid webhook URL, and the specific rarity toggle on.
- Unknown rarity hatches only send when `pet_webhook_secret` is enabled.
- Multiple matching pets send one webhook per visible hatch frame, with a small delay (`LogsPets.SEND_DELAY`, currently 0.35s).

Discord payload:

- Uses embeds titled `New Pet Hatched!` with a paw emoji in the actual script.
- Fields include Player, Pet Name, Pet Type, Pet Rarity, and Egg.
- Uses `DateTime.now():ToIsoDate()` for the timestamp.
- Converts `rbxassetid://123` thumbnails to `https://assetdelivery.roblox.com/v1/asset?id=123`.

Connection management:

- Connection is stored at `HS.Logs.Pets.Connection`.
- A getgenv key (`__HeartsteelPetHatchWebhookConnection`) is used to disconnect old connections across reruns.
- `LogsPets.syncConnection()` is called at startup after UI render.

### Discord Monitor

`HS.Logs.DiscordMonitor` handles the live Discord dashboard embed.

State/UI keys:

- `discord_monitor_enabled`: main monitor toggle.
- `discord_monitor_webhook_url`: Discord Monitor Webhook URL input.
- `discord_monitor_update_interval`: update interval input.
- Minimum interval is `5` seconds; default is `10` seconds.

Saved config:

- Stored under `Core.config.Logs.DiscordMonitor`.
- Persisted fields are `Enabled`, `WebhookURL`, `UpdateInterval`, and `MessageId`.
- If the webhook URL changes, the saved `MessageId` is cleared so the next update creates a fresh message.

Webhook behavior:

- Valid webhook hosts are `discord.com/api/webhooks/...` and `discordapp.com/api/webhooks/...`.
- `Monitor.createMessage(url, payload)` uses `POST` with `?wait=true` and saves the returned message id.
- `Monitor.editMessage(url, messageId, payload)` uses `PATCH` to `/messages/<messageId>`.
- If editing fails with `400` or `404`, the message id is cleared and a new message is created.
- Uses executor request APIs in this order: `syn.request`, `http.request`, `request`, `http_request`, `fluxus.request`.

Embed fields:

- Player
- Status
- Current Action
- Last High Rarity Pet
- Pet Type
- Current Class
- Session Stats
- Connection Stats
- Runtime
- Dungeon Egg Timers
- Latest Debug

Runtime state:

- Global state key: `__HeartsteelDiscordMonitorState`
- Loop token key: `__HeartsteelDiscordMonitorLoop`
- Hatch tracker key: `__HeartsteelDiscordMonitorHatchConnection`
- Teleport tracker key: `__HeartsteelDiscordMonitorTeleportConnection`
- GUI error tracker key: `__HeartsteelDiscordMonitorErrorConnection`

Hatch tracking:

- Reuses `HS.Logs.Pets` hatch-frame parsing helpers.
- Counts pets hatched from `EggHatchResult`.
- Records last high-rarity pet and type.
- High rarity means Secret, 3 Moon or better, or unknown/unmapped rarity.
- Secret/unknown rarities increment `SecretsFound`.

Connection tracking:

- `Player.OnTeleport` sets `Teleporting` and marks `PendingRejoin`.
- `GuiService.ErrorMessageChanged` increments disconnect count and sets `Disconnected` or `Rejoining`.
- On the next script run, a pending rejoin increments `RejoinCount`.
- `Monitor.stop()` sends one final disconnected/offline update when possible, then restores state to connected for the next start.

Startup calls `HS.Logs.DiscordMonitor.sync()` after `HS.Logs.Pets.syncConnection()`.

## Merchant

`HS.Merchant` handles the traveling merchant tab and auto-buy logic.

State/UI keys:

- `buy_merchant`: main `Auto Buy Merchant` toggle.
- `merchant_item_<listingIndex>`: per-listing item filters generated dynamically.
- Status row: `{type="status", bind="merchant", text="Merchant: waiting"}`.

Runtime fields:

- `Merchant.STATE_KEY = "buy_merchant"`
- `Merchant.BUY_DELAY = 1`
- `Merchant.CLICK_DELAY = 0.12`
- `Merchant.status`
- `Merchant.listings`
- `Merchant.allowedIndexes`
- `Merchant.uiItems`
- `Merchant.lastCrownMulti`
- `Merchant.displayWatcherThread`

Data sources:

- Merchant world presence: `workspace.Merchant.Locations.EventMerchant`
- Player merchant state: `Core.getClientDataManager().Data.TravelingMerchant`
- Listing definitions:

```lua
require(S.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TravelingMerchantInfo")).Listings
```

Filtering/build behavior:

- `Merchant.isRelevantListing(listing)` only includes crown-priced items.
- Robux/developer-product/superitem entries are ignored.
- Relevant listings are charms, pets, or boosts.
- Listings are sorted by category, subcategory, then listing index.
- Categories/subcategories are generated by `Merchant.getCategory()` and `Merchant.getSubcategory()`.
- Merchant UI is regenerated when `TravelingMerchant.CrownMulti` changes while the merchant tab is active.

Pet rarity display:

- `BEST_EGG_RARITY_1` through `BEST_EGG_RARITY_5` map to Star pet display.
- `BEST_EGG_RARITY_6` through `BEST_EGG_RARITY_8` map to Moon pet display.
- `BEST_EGG_RARITY_9` maps to Sun pet display.
- `MERCHANT_RARITY_ICON_ASSETS` currently contains placeholder asset IDs (`PASTE_STAR_ICON`, etc.); when placeholders remain, the UI falls back to text such as `Sun Pet` or `3 Moon Pet`.

Buy behavior:

- `Merchant.buySelected()` only runs if the merchant exists and traveling merchant data has `ResetDT` and item slots.
- It scans sorted live merchant slots from `TravelingMerchant.Items`.
- For selected and allowed listing indexes, it buys while `BuysLeft > 0` by firing:

```lua
Core.UIActionRemote:FireServer("TravelingMerchantBuyItem", slotNumber, resetDT)
```

- Status values are short text states such as `waiting`, `found`, `buying`, and `done`.

## Misc

`HS.Misc` contains:

- Move speed toggle and speed slider.
- Anti-AFK loop and idle event pulse.
- Simulate Movement toggle directly under Anti-AFK in the Misc tab.
- Element switching via:

```lua
Core.UIActionRemote:FireServer("ChangeElement", selectedElement)
```

- Save current position, teleport to saved position, copy current CFrame.
- Hide egg animations by moving children from `OpenEggs` to `OpenEggs2`.

Simulate Movement behavior:

- State key: `simulate_movement`.
- UI placement: Misc tab, immediately after `anti_afk` / `Anti-AFK`.
- Uses the existing duplicate-safe loop pattern: `Core.loopWhile("simulate_movement", Misc.SIM_MOVE_DELAY, ...)`.
- Movement pulse should keep running during normal automation, Petdex, boss farming, flags, merchant, auto-cycle, egg opener, and other non-dungeon actions.
- It should only skip while the player is actually inside an active dungeon.
- Do not turn the toggle off automatically when a dungeon starts. If the toggle remains enabled, the loop should resume naturally after leaving the active dungeon.
- Do not add Heartbeat or a new movement framework for this feature unless explicitly requested.

## Remote Listener

`Core.ClientNotifierRemote.OnClientEvent` handles:

- `DungeonReward`: marks dungeon run protection as ending, keeps protection through reward handling, and if reward type is `DungeonEgg`, runs `HS.Dungeon.handleEggReward`; protection is released after egg handling completes, or after a short grace if no dungeon egg reward handler runs.
- `PopupText`: if text contains `Clan XP`, refreshes clan quest info.

## Startup

At the end of the script:

- Starts anti-AFK loop.
- Installs dungeon region-loaded hook.
- Starts the dungeon presence watchdog.
- Renders UI.
- Calls `HS.Logs.Pets.syncConnection()` after UI render so a saved enabled webhook setting reconnects safely.
- Calls `HS.Logs.DiscordMonitor.sync()` after UI render so a saved enabled monitor setting reconnects safely.
- Applies egg animation hiding based on saved state.
- Moves all `ReplicatedStorage.HiddenRegions` children into `workspace.Gameplay.RegionsLoaded`.
- Does not do a startup Grandmaster preload teleport; startup should stay passive so dungeon/auto-cycle can begin cleanly.
- Opens/scans incubator shortly after startup.
- Refreshes quest titles and clan quest info.

## Editing Rules For Future Chats

- Keep changes scoped to the requested subsystem.
- Prefer existing helpers and UI builders.
- Do not create duplicate remotes or service locals.
- Use `Core.getClientDataManager()` instead of requiring `ClientDataManager` repeatedly.
- Use `Core.UIActionRemote` instead of re-fetching `ReplicatedStorage.Events.UIAction`.
- Use `Core.teleportWorld` and priority helpers for world teleports.
- Avoid broad refactors, broad formatting changes, or encoding rewrites.
- Use `apply_patch` for manual edits.
- This is Luau, not plain Lua. Local `lua.exe` may fail on valid syntax such as `continue` and `+=`.
- `testing.lua` contains Unicode box-drawing comments and some older mojibake; avoid touching unrelated comment blocks.
