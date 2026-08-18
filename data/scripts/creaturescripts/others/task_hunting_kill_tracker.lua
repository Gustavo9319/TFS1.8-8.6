-- Task Hunting kill tracker for classic clients.
--
-- The original Task Hunting network module tracks only AstraClient players,
-- because its interface is packet based. This script keeps the same database
-- rows and task states for classic clients, while Vauter handles their UI.

if not configManager or not configManager.getBoolean
	or not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then
	return
end

local STATE_ACTIVE = 4
local STATE_REDEEM = 5

local function getRequiredKills(raceId, rarity, upgraded)
	local entry = CustomBestiary and CustomBestiary.getMonster and CustomBestiary.getMonster(raceId)
	if not entry then
		return 0
	end

	local stars = tonumber(entry.stars) or 1
	local difficulty = stars <= 1 and 1 or (stars <= 3 and 2 or 3)
	local kills = 25
	rarity = math.max(1, math.min(5, tonumber(rarity) or 1))

	for currentDifficulty = 1, 3 do
		for currentRarity = 1, 5 do
			if currentDifficulty == difficulty and currentRarity == rarity then
				return upgraded and kills * 2 or kills
			end
		end
		kills = kills * 4
	end

	return 0
end

local function monsterName(raceId)
	local entry = CustomBestiary and CustomBestiary.getMonster and CustomBestiary.getMonster(raceId)
	return entry and entry.name or ("creature #" .. tostring(raceId))
end

local taskHuntingKillTracker = CreatureEvent("TaskHuntingKillTracker")

function taskHuntingKillTracker.onKill(player, target, lastHit)
	if player.isUsingAstraClient and player:isUsingAstraClient() then
		return true -- AstraClient is handled by the original Task Hunting module.
	end

	local monster = target and Monster(target)
	local monsterType = monster and monster:getType()
	local raceId = monsterType and monsterType:raceId() or 0
	if raceId <= 0 then
		return true
	end

	local resultId = db.storeQuery("SELECT `slot`, `current_kills`, `rarity`, `upgraded` FROM `player_task_hunting` WHERE `player_id` = " ..
		player:getGuid() .. " AND `state` = " .. STATE_ACTIVE .. " AND `selected_raceid` = " .. raceId)
	if resultId == false then
		return true
	end

	repeat
		local requiredKills = getRequiredKills(raceId, result.getDataInt(resultId, "rarity"), result.getDataInt(resultId, "upgraded") ~= 0)
		if requiredKills > 0 then
			local currentKills = result.getDataInt(resultId, "current_kills")
			local newKills = math.min(currentKills + 1, requiredKills)
			local newState = newKills >= requiredKills and STATE_REDEEM or STATE_ACTIVE
			db.query("UPDATE `player_task_hunting` SET `current_kills` = " .. newKills .. ", `state` = " .. newState ..
				" WHERE `player_id` = " .. player:getGuid() .. " AND `slot` = " .. result.getDataInt(resultId, "slot"))

			if currentKills < requiredKills and newKills >= requiredKills then
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "[Hunting Task] Your task for " .. monsterName(raceId) ..
					" is complete. Visit Vauter to claim your Hunting Points.")
			end
		end
	until not result.next(resultId)
	result.free(resultId)
	return true
end

taskHuntingKillTracker:type("kill")
taskHuntingKillTracker:register()

local taskHuntingTrackerLogin = CreatureEvent("TaskHuntingTrackerLogin")

function taskHuntingTrackerLogin.onLogin(player)
	if not (player.isUsingAstraClient and player:isUsingAstraClient()) then
		player:registerEvent("TaskHuntingKillTracker")
	end
	return true
end

taskHuntingTrackerLogin:type("login")
taskHuntingTrackerLogin:register()
