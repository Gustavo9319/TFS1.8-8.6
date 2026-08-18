-- Native Task Board NPC. Uses the same data and rewards as the Astra board.
-- VAUTER_BUILD: 2026-08-17-map-spawn-balance

local internalNpcName = "Vauter"
local npcType = Game.createNpcType(internalNpcName)
local npcConfig = {}

npcConfig.name = internalNpcName
npcConfig.description = internalNpcName

npcConfig.health = 100
npcConfig.maxHealth = npcConfig.health
npcConfig.walkInterval = 2000
npcConfig.walkRadius = 2

npcConfig.outfit = {
	lookType = 140,
	lookHead = 60,
	lookBody = 22,
	lookLegs = 24,
	lookFeet = 32,
	lookAddons = 1,
}

npcConfig.flags = {
	floorchange = false,
}

-- The Bounty Talisman is required to use Bounty upgrades. Keep it here so
-- players do not need to find a separate merchant before using this system.
npcConfig.shop = {
	{ itemName = "bounty talisman", clientId = 51978, buy = 5000 },
}

local MapSpawnPool = dofile("data/lib/task_board/map_spawn_pool.lua")

local TOPIC_BOUNTY_CHOOSE = 100
local TOPIC_BOUNTY_DIFFICULTY = 101
local TOPIC_WEEKLY_DIFFICULTY = 102
local TOPIC_HUNTING_SELECT = 200 -- + slot
local TOPIC_HUNTING_WILDCARD = 210 -- + slot
local TOPIC_HUNTING_ACTIVE = 220 -- + slot
local TOPIC_SHOP = 300
local bountyPage = {}

local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
-- The default NPC conversation timeout is two minutes. Vauter's explanations
-- are intentionally detailed, so keep the player's conversation open for five.
npcHandler:setMaxIdleTime(300)

npcType.onThink = function(npc, interval)
	npcHandler:onThink(npc, interval)
end

npcType.onAppear = function(npc, creature)
	npcHandler:onAppear(npc, creature)
end

npcType.onDisappear = function(npc, creature)
	npcHandler:onDisappear(npc, creature)
end

npcType.onMove = function(npc, creature, fromPosition, toPosition)
	npcHandler:onMove(npc, creature, fromPosition, toPosition)
end

npcType.onSay = function(npc, creature, type, message)
	npcHandler:onSay(npc, creature, type, message)
end

npcType.onCloseChannel = function(npc, creature)
	npcHandler:onCloseChannel(npc, creature)
end

local function taskBoardEnabled()
	return configManager and configManager.getBoolean
		and configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED)
end

local function enabled(key)
	return taskBoardEnabled() and configManager.getBoolean(key)
end

local function say(npc, creature, text)
	npcHandler:say(text, npc, creature)
end

local function show(player, lines)
	player:showTextDialog(1950, table.concat(lines, "\n"))
end

local function monsterName(raceId)
	raceId = tonumber(raceId) or 0
	if raceId <= 0 then
		return "None chosen"
	end
	local entry = CustomBestiary and CustomBestiary.getMonster and CustomBestiary.getMonster(raceId)
	return (entry and entry.name) or ("Unknown creature #" .. tostring(raceId))
end

local function monsterFacts(raceId)
	local entry = CustomBestiary and CustomBestiary.getMonster and CustomBestiary.getMonster(tonumber(raceId) or 0)
	if not entry then
		return "Monster details are unavailable."
	end
	return string.format("Monster details: %d-star difficulty; about %d normal EXP per kill, plus its usual loot.", tonumber(entry.stars) or 0, tonumber(entry.experience) or 0)
end

-- Classic clients cannot choose a Bestiary entry through the Task Board UI.
-- Let players use a readable monster name instead of exposing internal race IDs.
local function findMonsterRaceId(nameOrRaceId)
	local raceId = tonumber(nameOrRaceId)
	local directEntry = raceId and CustomBestiary and CustomBestiary.getMonster and CustomBestiary.getMonster(raceId)
	if directEntry and MapSpawnPool.hasMonster(directEntry.name) then
		return raceId
	end

	local wantedName = tostring(nameOrRaceId or ""):lower():gsub("^%s*(.-)%s*$", "%1")
	if wantedName == "" or not CustomBestiary or not CustomBestiary.monstersByRaceId then
		return nil
	end
	for candidateRaceId, entry in pairs(CustomBestiary.monstersByRaceId) do
		if tostring(entry.name or ""):lower() == wantedName and MapSpawnPool.hasMonster(entry.name) then
			return tonumber(candidateRaceId)
		end
	end
	return nil
end

local function difficultyName(value)
	return ({ [0] = "Beginner", [1] = "Adept", [2] = "Expert", [3] = "Master" })[tonumber(value)] or "Unknown"
end

local function difficulty(message)
	local names = {
		beginner = 0, iniciante = 0,
		adept = 1, adepto = 1,
		expert = 2, especialista = 2,
		master = 3, mestre = 3,
	}
	if names[message] ~= nil then return names[message] end
	local value = tonumber(message)
	return value and value >= 1 and value <= 4 and value - 1 or nil
end

local function number(message)
	local words = { one = 1, two = 2, three = 3, um = 1, dois = 2, tres = 3, ["três"] = 3 }
	return tonumber(message:match("(%d+)")) or words[message]
end

-- Native Task Board actions end by sending an Astra-only UI packet. That send
-- returns false for classic clients even after the data was correctly saved.
-- Validate the saved state instead of trusting that packet return value.
local function bountyDifficultyChanged(player, value)
	if not TaskBoardBountyTasks then return false end
	local before = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	if before.state == 2 then return false end
	TaskBoardBountyTasks.changeDifficulty(player, value)
	local after = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	return after.difficulty == value and after.state == 1 and #(after.creaturesList or {}) > 0
end

local function bountyTaskSelected(player, choice)
	if not TaskBoardBountyTasks then return false end
	local before = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	local offer = before.state == 1 and (before.creaturesList or {})[choice]
	if not offer or not offer.raceId or offer.raceId <= 0 then return false end
	TaskBoardBountyTasks.selectTask(player, choice - 1)
	local after = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	return after.state == 2 and after.activeTask and after.activeTask.raceId == offer.raceId
end

local function bountyRerolled(player)
	if not TaskBoardBountyTasks then return false end
	local before = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	local now = os.time()
	if before.state == 2 or not ((before.freeRerollTimestamp or 0) > 0 and now >= before.freeRerollTimestamp or (before.rerollTokens or 0) > 0) then
		return false
	end
	TaskBoardBountyTasks.rerollTasks(player)
	local after = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	return after.state == 1 and #(after.creaturesList or {}) > 0
end

local function dailyBountyRerollClaimed(player)
	if not TaskBoardBountyTasks then return false end
	local before = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	if (before.freeRerollTimestamp or 0) <= 0 or os.time() < before.freeRerollTimestamp then return false end
	TaskBoardBountyTasks.claimDailyReroll(player)
	local after = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	return (after.freeRerollTimestamp or 0) > os.time()
end

local function bountyPreferenceSaved(player, slot, raceId, unwanted)
	if not TaskBoardBountyTasks then return false end
	local before = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	if not before.preferredLists[slot] or not before.preferredLists[slot].active then return false end
	if unwanted then TaskBoardBountyTasks.assignUnwanted(player, slot, raceId)
	else TaskBoardBountyTasks.assignPreferred(player, slot, raceId) end
	local after = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	local saved = after.preferredLists[slot]
	return saved and (unwanted and saved.unwantedRaceId or saved.preferredRaceId) == raceId
end

local function bountyPreferenceCleared(player, slot, unwanted)
	if not TaskBoardBountyTasks then return false end
	local before = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	local saved = before.preferredLists[slot]
	if not saved or not saved.active or (unwanted and (saved.unwantedRaceId or 0) or (saved.preferredRaceId or 0)) <= 0 then return false end
	if unwanted then TaskBoardBountyTasks.clearUnwanted(player, slot)
	else TaskBoardBountyTasks.clearPreferred(player, slot) end
	local after = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	saved = after.preferredLists[slot]
	return saved and (unwanted and (saved.unwantedRaceId or 0) or (saved.preferredRaceId or 0)) == 0
end

local function weeklyHasStartedProgress(data)
	if (data.anyCreatureCurrent or 0) > 0 or (data.completedKillTasks or 0) > 0
		or (data.completedDeliveryTasks or 0) > 0 or data.needsReward == true then
		return true
	end
	for _, task in ipairs(data.killTasks or {}) do
		if (task.kills or 0) > 0 then return true end
	end
	for _, task in ipairs(data.deliveryTasks or {}) do
		if task.delivered == 1 then return true end
	end
	return false
end

local function weeklyDifficultyChanged(player, value)
	if not TaskBoardWeeklyTasks then return false end
	local before = TaskBoardWeeklyTasks.loadWeeklyData(player:getGuid())
	if #(before.killTasks or {}) > 0 or #(before.deliveryTasks or {}) > 0 then return false end
	TaskBoardWeeklyTasks.selectDifficulty(player, value)
	local after = TaskBoardWeeklyTasks.loadWeeklyData(player:getGuid())
	return after.difficulty == value and #(after.killTasks or {}) > 0
end

local function claimBountyWithDetails(player)
	if not TaskBoardBountyTasks then return false end
	local data = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	local task = data.activeTask
	if not task then return false end
	local exp, points, tokens = task.rewardExp or 0, task.rewardBountyPoints or 0, data.rerollTokens or 0
	if not TaskBoardBountyTasks.claimReward(player) then return false end
	local after = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	local tokenText = (after.rerollTokens or 0) > tokens and " and +1 Bounty reroll token" or ""
	return true, string.format("Your Bounty reward has been claimed: +%d normal player EXP, +%d Bounty Points%s.", exp, points, tokenText)
end

local function claimWeeklyWithDetails(player)
	if not TaskBoardWeeklyTasks then return false end
	local data = TaskBoardWeeklyTasks.loadWeeklyData(player:getGuid())
	if not data.needsReward then return false end
	local points, soulseals = data.rewardHTP or 0, data.rewardSoulseals or 0
	if not TaskBoardWeeklyTasks.distributeRewards(player) then return false end
	return true, string.format("Your Weekly reward has been claimed: +%d Hunting Points and +%d Soulseals.", points, soulseals)
end

-- Legacy-client bridge for the native Task Hunting data. The original module
-- intentionally exposes its actions only through Astra packets. This bridge
-- uses the exact same table, states, reward formula and onKill handler, while
-- giving classic clients a safe NPC conversation instead of custom packets.
local NativeHunting = { pending = {} }

local HUNTING_SELECT = 2
local HUNTING_WILDCARD = 3
local HUNTING_ACTIVE = 4
local HUNTING_REDEEM = 5
local HUNTING_SLOT_COUNT = 3
local HUNTING_LIST_SIZE = 9
local HUNTING_FREE_REROLL_SECONDS = 20 * 60 * 60
local HUNTING_REROLL_PRICE_PER_LEVEL = 200
local HUNTING_WILDCARD_SELECT_PRICE = 5
local HUNTING_WILDCARD_REWARD_REROLL_PRICE = 1

local function splitRaceList(raw)
	local result = {}
	for value in tostring(raw or ""):gmatch("[^,]+") do
		local raceId = tonumber(value)
		if raceId and raceId > 0 then
			result[#result + 1] = raceId
		end
	end
	return result
end

local function joinRaceList(raceList)
	local values = {}
	for _, raceId in ipairs(raceList or {}) do
		values[#values + 1] = tostring(raceId)
	end
	return table.concat(values, ",")
end

local function shuffle(values)
	for index = #values, 2, -1 do
		local other = math.random(index)
		values[index], values[other] = values[other], values[index]
	end
end

local function nativeDefaultSlot(dbSlot)
	return {
		dbSlot = dbSlot,
		slot = dbSlot + 1,
		state = HUNTING_SELECT,
		selectedRaceId = 0,
		currentKills = 0,
		rarity = 1,
		upgraded = false,
		wildcard = false,
		raceList = {},
		freeRerollAt = 0,
	}
end

local function loadNativeSlot(playerGuid, dbSlot)
	local resultId = db.storeQuery("SELECT `state`, `selected_raceid`, `current_kills`, `rarity`, `upgraded`, `wildcard`, `race_list`, `free_reroll_at` FROM `player_task_hunting` WHERE `player_id` = " .. playerGuid .. " AND `slot` = " .. dbSlot)
	if resultId == false then
		return nativeDefaultSlot(dbSlot)
	end

	local slot = {
		dbSlot = dbSlot,
		slot = dbSlot + 1,
		state = result.getDataInt(resultId, "state"),
		selectedRaceId = result.getDataInt(resultId, "selected_raceid"),
		currentKills = result.getDataInt(resultId, "current_kills"),
		rarity = math.max(1, math.min(5, result.getDataInt(resultId, "rarity"))),
		upgraded = result.getDataInt(resultId, "upgraded") ~= 0,
		wildcard = result.getDataInt(resultId, "wildcard") ~= 0,
		raceList = splitRaceList(result.getDataString(resultId, "race_list")),
		freeRerollAt = result.getDataLong(resultId, "free_reroll_at"),
	}
	result.free(resultId)
	return slot
end

local function saveNativeSlot(playerGuid, slot)
	return db.query(string.format(
		"INSERT INTO `player_task_hunting` (`player_id`, `slot`, `state`, `selected_raceid`, `current_kills`, `rarity`, `upgraded`, `wildcard`, `race_list`, `free_reroll_at`) " ..
		"VALUES (%d, %d, %d, %d, %d, %d, %d, %d, %s, %d) " ..
		"ON DUPLICATE KEY UPDATE `state` = VALUES(`state`), `selected_raceid` = VALUES(`selected_raceid`), `current_kills` = VALUES(`current_kills`), " ..
		"`rarity` = VALUES(`rarity`), `upgraded` = VALUES(`upgraded`), `wildcard` = VALUES(`wildcard`), `race_list` = VALUES(`race_list`), `free_reroll_at` = VALUES(`free_reroll_at`)",
		playerGuid, slot.dbSlot, slot.state, slot.selectedRaceId, slot.currentKills, slot.rarity,
		slot.upgraded and 1 or 0, slot.wildcard and 1 or 0, db.escapeString(joinRaceList(slot.raceList)), slot.freeRerollAt))
end

local function allTaskHuntingRaceIds(player)
	local raceIds = {}
	if not CustomBestiary or not CustomBestiary.monstersByRaceId then
		return raceIds
	end
	for raceId, entry in pairs(CustomBestiary.monstersByRaceId) do
		if tonumber(raceId) and tonumber(raceId) > 0 and MapSpawnPool.isHuntingTarget(entry, player:getLevel()) then
			raceIds[#raceIds + 1] = tonumber(raceId)
		end
	end
	return raceIds
end

local function nativeExcludedRaceIds(slots, exceptDbSlot)
	local excluded = {}
	for _, slot in ipairs(slots) do
		if slot.dbSlot ~= exceptDbSlot then
			if slot.selectedRaceId and slot.selectedRaceId > 0 then
				excluded[slot.selectedRaceId] = true
			end
			for _, raceId in ipairs(slot.raceList or {}) do
				excluded[raceId] = true
			end
		end
	end
	return excluded
end

local function generateNativeRaceList(player, slots, dbSlot)
	local excluded = nativeExcludedRaceIds(slots, dbSlot)
	local buckets = { {}, {}, {}, {} }
	for _, raceId in ipairs(allTaskHuntingRaceIds(player)) do
		if not excluded[raceId] then
			local entry = CustomBestiary.getMonster(raceId)
			local stars = math.max(1, math.min(5, tonumber(entry and entry.stars) or 1))
			local bucket = stars <= 1 and 1 or (stars == 2 and 2 or (stars == 3 and 3 or 4))
			buckets[bucket][#buckets[bucket] + 1] = raceId
		end
	end
	for _, bucket in ipairs(buckets) do shuffle(bucket) end

	local stage = math.floor(player:getLevel() / 100)
	local targets = stage == 0 and { 3, 3, 2, 1 }
		or (stage <= 2 and { 1, 3, 3, 2 } or (stage <= 4 and { 1, 2, 3, 3 } or { 1, 1, 3, 4 }))
	local selected, selectedSet = {}, {}
	for bucketIndex, target in ipairs(targets) do
		for index = 1, math.min(target, #buckets[bucketIndex]) do
			local raceId = buckets[bucketIndex][index]
			selected[#selected + 1], selectedSet[raceId] = raceId, true
		end
	end
	if #selected < HUNTING_LIST_SIZE then
		local remaining = {}
		for _, bucket in ipairs(buckets) do
			for _, raceId in ipairs(bucket) do
				if not selectedSet[raceId] then remaining[#remaining + 1] = raceId end
			end
		end
		shuffle(remaining)
		for _, raceId in ipairs(remaining) do
			if #selected >= HUNTING_LIST_SIZE then break end
			selected[#selected + 1] = raceId
		end
	end
	return selected
end

local function generateNativeWildcardList(player, slots, dbSlot)
	local excluded = nativeExcludedRaceIds(slots, dbSlot)
	local raceIds = {}
	for _, raceId in ipairs(allTaskHuntingRaceIds(player)) do
		if not excluded[raceId] then raceIds[#raceIds + 1] = raceId end
	end
	table.sort(raceIds)
	return raceIds
end

local function hasUnavailableNativeRaceId(player, raceList)
	for _, raceId in ipairs(raceList or {}) do
		local entry = CustomBestiary and CustomBestiary.getMonster(raceId)
		if not entry or not MapSpawnPool.isHuntingTarget(entry, player:getLevel()) then
			return true
		end
	end
	return false
end

local function resetNativeSlot(player, slots, slot)
	slot.state = HUNTING_SELECT
	slot.selectedRaceId, slot.currentKills, slot.rarity = 0, 0, 1
	slot.upgraded, slot.wildcard = false, false
	slot.raceList = generateNativeRaceList(player, slots, slot.dbSlot)
end

local function ensureNativeSlot(player, slots, slot)
	if slot.state == 0 or slot.state == 1 then
		resetNativeSlot(player, slots, slot)
	end
	if slot.state == HUNTING_SELECT and (#slot.raceList == 0 or hasUnavailableNativeRaceId(player, slot.raceList)) then
		slot.raceList = generateNativeRaceList(player, slots, slot.dbSlot)
	end
end

function NativeHunting.getSlots(player)
	local slots = {}
	for dbSlot = 0, HUNTING_SLOT_COUNT - 1 do
		slots[#slots + 1] = loadNativeSlot(player:getGuid(), dbSlot)
	end
	for _, slot in ipairs(slots) do
		local previousState = slot.state
		ensureNativeSlot(player, slots, slot)
		if previousState ~= slot.state or (slot.state == HUNTING_SELECT and #slot.raceList > 0) then
			saveNativeSlot(player:getGuid(), slot)
		end
	end
	return slots
end

local function bestiaryComplete(player, raceId)
	local entry = CustomBestiary and CustomBestiary.getMonster and CustomBestiary.getMonster(raceId)
	if not entry then return false end
	local kills = 0
	if Game.getBestiaryKills then
		kills = (Game.getBestiaryKills(player:getGuid()) or {})[raceId] or 0
	else
		local resultId = db.storeQuery("SELECT `kills` FROM `player_bestiary_kills` WHERE `player_id` = " .. player:getGuid() .. " AND `raceid` = " .. raceId)
		if resultId ~= false then
			kills = result.getDataInt(resultId, "kills")
			result.free(resultId)
		end
	end
	return kills >= (entry.toKill or math.huge)
end

local function nativeReward(entry, rarity)
	local difficulty = (entry and (entry.stars or 0) <= 1) and 1 or ((entry and (entry.stars or 0) <= 3) and 2 or 3)
	local kills = 25
	for currentDifficulty = 1, 3 do
		local reward = math.floor((10 * kills) / 25 + 0.5)
		for currentRarity = 1, 5 do
			if currentDifficulty == difficulty and currentRarity == rarity then
				return kills, reward
			end
			reward = math.floor(reward * (115 + currentDifficulty * 5) / 100 + 0.5)
		end
		kills = kills * 4
	end
	return 0, 0
end

local function huntingRewardQuality(rarity)
	return ({ [1] = "basic", [2] = "better", [3] = "good", [4] = "great", [5] = "best" })[tonumber(rarity)] or "basic"
end

local function nativeGold(player)
	return math.max(0, player:getMoney()) + math.max(0, player:getBankBalance())
end

local function removeNativeGold(player, amount)
	if nativeGold(player) < amount then return false end
	local inventoryGold = math.min(player:getMoney(), amount)
	if inventoryGold > 0 and not player:removeMoney(inventoryGold) then return false end
	local remaining = amount - inventoryGold
	if remaining > 0 then player:setBankBalance(player:getBankBalance() - remaining) end
	return true
end

local function nativeContains(raceList, raceId)
	for _, listedRaceId in ipairs(raceList or {}) do
		if listedRaceId == raceId then return true end
	end
	return false
end

local function rerollNativeReward(slot)
	if slot.rarity >= 4 then slot.rarity = 5 return end
	local maximum = ({ [1] = 70, [2] = 45, [3] = 20 })[slot.rarity] or 100
	local chance = math.random(0, maximum)
	if chance <= 5 then slot.rarity = 5
	elseif chance <= 20 then slot.rarity = 4
	elseif chance <= 45 then slot.rarity = 3
	else slot.rarity = 2 end
end

local function nativeBarrier(player, mutation, completion)
	if NativeHunting.pending[player:getId()] then
		return false, "I am still updating your Hunting Task. Please wait a moment."
	end
	NativeHunting.pending[player:getId()] = true
	local playerId, playerGuid = player:getId(), player:getGuid()
	if _TASK_HUNTING_MODULE and _TASK_HUNTING_MODULE.onLogout then
		_TASK_HUNTING_MODULE.onLogout(player)
	end
	-- The empty update is queued after the native module's async saves. Its
	-- callback therefore runs only after the native cache has reached MySQL.
	db.asyncQuery("UPDATE `player_task_hunting` SET `player_id` = `player_id` WHERE `player_id` = " .. playerGuid, function()
		local currentPlayer = Player(playerId)
		if not currentPlayer then
			NativeHunting.pending[playerId] = nil
			return
		end
		local slots = NativeHunting.getSlots(currentPlayer)
		local success, text = mutation(currentPlayer, slots)
		NativeHunting.pending[playerId] = nil
		if completion then
			completion(currentPlayer, success, text)
		else
			currentPlayer:sendTextMessage(success and MESSAGE_EVENT_ADVANCE or MESSAGE_STATUS_SMALL, "[Vauter] " .. text)
		end
	end)
	return true
end

function NativeHunting.perform(player, uiSlot, action, argument, completion)
	if not _TASK_HUNTING_MODULE then
		return false, "Hunting Tasks are disabled."
	end
	uiSlot = tonumber(uiSlot)
	if not uiSlot or uiSlot < 1 or uiSlot > HUNTING_SLOT_COUNT then
		return false, "Choose {slot 1}, {slot 2} or {slot 3}."
	end
	return nativeBarrier(player, function(currentPlayer, slots)
		local slot = slots[uiSlot]
		if not slot then return false, "That slot does not exist." end

		if action == "reroll" then
			if slot.state ~= HUNTING_SELECT then return false, "You can reroll only a creature list." end
			local now = os.time()
			if now >= (slot.freeRerollAt or 0) then
				slot.freeRerollAt = now + HUNTING_FREE_REROLL_SECONDS
			elseif not removeNativeGold(currentPlayer, currentPlayer:getLevel() * HUNTING_REROLL_PRICE_PER_LEVEL) then
				return false, "You do not have enough gold for this reroll."
			end
			slot.raceList = generateNativeRaceList(currentPlayer, slots, slot.dbSlot)
			saveNativeSlot(currentPlayer:getGuid(), slot)
			return true, "Your Hunting Task creature list has been rerolled."
		elseif action == "wildcard" then
			if slot.state ~= HUNTING_SELECT then return false, "You can use a wildcard only while selecting a creature." end
			if currentPlayer:getPreyWildcards() < HUNTING_WILDCARD_SELECT_PRICE then
				return false, "You need 5 Prey Wildcards for a wildcard selection."
			end
			currentPlayer:setPreyWildcards(currentPlayer:getPreyWildcards() - HUNTING_WILDCARD_SELECT_PRICE)
			slot.state, slot.wildcard, slot.raceList = HUNTING_WILDCARD, true, {}
			saveNativeSlot(currentPlayer:getGuid(), slot)
			return true, "Wildcard mode is ready. Say the exact creature {name} or {race ID}."
		elseif action == "select" then
			if slot.state ~= HUNTING_SELECT and slot.state ~= HUNTING_WILDCARD then
				return false, "This slot is not waiting for a creature."
			end
			local wantsUpgrade = type(argument) == "table" and argument.upgrade == true
			local selected = tonumber(type(argument) == "table" and argument.value or argument)
			local raceId = selected
			if slot.state == HUNTING_SELECT then
				raceId = slot.raceList[selected or 0]
			else
				local wildcardList = generateNativeWildcardList(currentPlayer, slots, slot.dbSlot)
				if not nativeContains(wildcardList, raceId) then raceId = nil end
			end
			local entry = raceId and CustomBestiary and CustomBestiary.getMonster(raceId)
			if not entry then return false, "That creature is not available for this slot." end
			slot.state, slot.selectedRaceId, slot.currentKills, slot.rarity = HUNTING_ACTIVE, raceId, 0, 1
			slot.upgraded = wantsUpgrade and bestiaryComplete(currentPlayer, raceId)
			slot.wildcard, slot.raceList = false, {}
			saveNativeSlot(currentPlayer:getGuid(), slot)
			return true, "Your Hunting Task for " .. entry.name .. " has started. Every kill will be counted automatically."
		elseif action == "reward" then
			if slot.state ~= HUNTING_ACTIVE then return false, "You can improve only an active task reward." end
			if slot.rarity >= 5 then return false, "This task already has the highest reward grade." end
			if currentPlayer:getPreyWildcards() < HUNTING_WILDCARD_REWARD_REROLL_PRICE then
				return false, "You need 1 Prey Wildcard to improve this reward."
			end
			currentPlayer:setPreyWildcards(currentPlayer:getPreyWildcards() - HUNTING_WILDCARD_REWARD_REROLL_PRICE)
			rerollNativeReward(slot)
			saveNativeSlot(currentPlayer:getGuid(), slot)
			return true, "Your task reward grade is now " .. slot.rarity .. "."
		elseif action == "cancel" then
			if slot.state ~= HUNTING_ACTIVE then return false, "There is no active task to cancel." end
			if not removeNativeGold(currentPlayer, currentPlayer:getLevel() * HUNTING_REROLL_PRICE_PER_LEVEL) then
				return false, "You do not have enough gold to cancel this task."
			end
			resetNativeSlot(currentPlayer, slots, slot)
			saveNativeSlot(currentPlayer:getGuid(), slot)
			return true, "Your task was cancelled and a new creature list is ready."
		elseif action == "claim" then
			if slot.state ~= HUNTING_REDEEM then return false, "This task is not complete yet." end
			local entry = CustomBestiary and CustomBestiary.getMonster(slot.selectedRaceId)
			local _, reward = nativeReward(entry, slot.rarity)
			if slot.upgraded then reward = reward * 2 end
			currentPlayer:addTaskHuntingPoints(reward)
			resetNativeSlot(currentPlayer, slots, slot)
			saveNativeSlot(currentPlayer:getGuid(), slot)
			return true, string.format("Your Hunting Task reward has been claimed: +%d Hunting Points.", reward)
		end
		return false, "I did not understand that Hunting Task action."
	end, completion)
end

local function getShopOffers(player)
	local ok, offers = pcall(dofile, "data/lib/task_board/shop_offers.lua")
	if not ok then return {} end
	local result = {}
	for index, offer in ipairs(offers) do
		local purchased = false
		if offer.type == 1 and offer.mountId then purchased = player:hasMount(offer.mountId)
		elseif offer.type == 2 and offer.outfitId then purchased = player:hasOutfit(offer.outfitId, offer.addons or 0)
		elseif offer.type == 5 then purchased = player:hasWeeklyExpansion()
		elseif offer.type == 4 then purchased = player:isPremium() end
		result[#result + 1] = { index = index, name = offer.name, count = offer.count or 1, price = offer.price or 0, purchased = purchased }
	end
	return result
end

local function resetTopic(player)
	npcHandler:setTopic(player:getId(), 0)
	bountyPage[player:getId()] = nil
end

local function result(npc, creature, success, successText, failureText)
	say(npc, creature, success and successText or failureText)
	resetTopic(Player(creature))
	return true
end

local function containsAny(message, words)
	for _, word in ipairs(words) do
		if message:find(word, 1, true) then return true end
	end
	return false
end

local function normalizeMessage(message)
	return tostring(message or ""):lower():gsub("^%s*(.-)%s*$", "%1"):gsub("[?!,;:.]", "")
end

local function isQuestion(message)
	return containsAny(message, {
		"help", "ajuda", "explain", "explica", "explique", "como", "how", "what", "why", "where", "when", "onde", "quando", "info",
		"nao entendi", "não entendi", "i dont understand", "i don't understand", "dont understand", "confused",
		"o que", "para que", "pra que", "por que", "porque", "duvida", "dúvida", "gasto", "pontos", "reward", "rewards", "benefit", "beneficio", "benefício", "information", "informacao", "informação",
	})
end

local function showGuide(player, section)
	local lines = { "=== VAUTER'S SIMPLE TASK GUIDE ===", "" }
	if section == "bounty" then
		lines = {
			"=== BOUNTY: PICK ONE MONSTER TO HUNT ===",
			"A BOUNTY is NOT a reward. It is a monster-hunting mission.",
			"Example: if you choose a Dragon Bounty, your job is to kill Dragons until the counter is full.",
			"After you choose it, that mission is your ACTIVE BOUNTY. It stays active until you finish and claim it.",
			"",
			"HOW TO START:",
			"1. Say {bounty}.",
			"2. Choose {beginner}, {adept}, {expert} or {master}. Beginner is best for a new player.",
			"3. I show 3 monster missions. Say {1}, {2} or {3} to pick ONE.",
			"4. Kill the monster you picked. Each correct kill increases your counter automatically.",
			"5. When the counter says complete, return and say {claim bounty}.",
			"",
			"WHEN YOU FINISH: you receive EXP, Bounty Points and usually a reroll token.",
			"Bounty Points are special points. They are NOT gold and they do NOT buy shop items.",
			"You spend Bounty Points in only two ways: improve your Bounty Talisman, or unlock/use Preferences.",
			"",
			"PREFERENCES ARE A CHOICE LIST, NOT A COMBAT BONUS.",
			"Preferred = tell me a monster you like hunting. I try to offer it when it fits your difficulty.",
			"Unwanted = tell me a monster you dislike. I do not put it in random Bounty choices.",
			"Say {preferences} to see your slots and instructions. You start with one free slot.",
			"",
			"THE BOUNTY TALISMAN IS EQUIPMENT THAT HELPS ONLY WITH YOUR ACTIVE BOUNTY.",
			"You can buy it from me for 5,000 gold: say {trade talisman}. Put it in the AMMUNITION SLOT.",
			"If you chose Dragon, its bonuses work against Dragons until that Bounty is finished. It does nothing against other monsters.",
			"Say {bounty talisman info} for a simple explanation of every bonus and {talisman} to see your own levels.",
			"",
			"WHAT IS DIFFICULTY? Higher difficulty means stronger monster pools, more kills and bigger possible rewards.",
			"Beginner: 50-100 kills | Adept: 100-200 | Expert: 200-300 | Master: 300-600.",
			"",
			"WHAT IS REROLL? Before choosing a Bounty, say {reroll} to replace the 3 offered monsters.",
			"You have a free reroll after its cooldown. Otherwise a reroll token is used. You cannot reroll after starting a hunt.",
			"",
			"Say {bounty} to begin, {reroll} for new choices, {talisman} to improve bonuses, or {preferences} to guide future choices.",
		}
	elseif section == "weekly" then
		lines = {
			"=== WEEKLY: BIG GOALS + LONG-TERM REWARDS ===",
			"Choose Weekly when you want many goals for the week and a large final reward.",
			"",
			"STEP 1: Say {weekly} and choose a difficulty.",
			"STEP 2: Kill the listed monsters. You also have an ANY CREATURE goal: every monster kill helps it.",
			"STEP 3: Collect the requested items and say {deliver 1}, {deliver 2}, and so on.",
			"STEP 4: Complete as many goals as you can. More completed goals means a larger final multiplier.",
			"STEP 5: Say {claim weekly} when Vauter says your pending reward is ready.",
			"",
			"WHAT DO I GET? Every finished named-monster goal, Any Creature goal or delivery gives normal player EXP immediately.",
			"Each finished goal also adds Hunting Points and 1 Soulseal to the Weekly reward waiting to be claimed.",
			"Hunting Points are spent in {shop}. Soulseals pay for a Soulpit challenge. Weekly Tasks do NOT directly give Bounty Points, items, mounts, outfits or extra loot.",
			"The more Weekly goals you finish, the bigger the Hunting Point multiplier becomes. Open {weekly} to see the exact point value and multiplier for every current goal.",
			"",
			"WHAT IS DIFFICULTY? Beginner has smaller goals; Master has the longest goals and larger point value.",
			"Any-creature goals: Beginner 1,000 | Adept 2,000 | Expert 3,000 | Master 4,000 kills.",
			"NAMED MONSTER STRENGTH: Beginner uses 1-star targets | Adept uses 2-star targets | Expert uses balanced 3-star targets | Master uses strong 4-5-star targets.",
			"To keep the missions fair, Vauter also checks each target's health and normal EXP. A 5-star boss cannot appear in an Expert Weekly.",
			"A named Weekly target must have a permanent spawn on the normal map. Quest, raid, event and unused-script creatures are ignored.",
			"After you choose a difficulty and its list is created, that Weekly difficulty is locked until the next weekly reset.",
			"",
			"Say {weekly} to see your exact goals. Say {report} or {!task} anytime to check progress.",
		}
	elseif section == "hunting" then
		lines = {
			"=== HUNTING TASKS: POINTS FOR THE SHOP ===",
			"Choose Hunting Tasks when you want to turn normal hunting into Hunting Points for shop rewards.",
			"",
			"You can use 3 slots at the same time. Each slot gives a list of monsters based on your level.",
			"STEP 1: Say {hunting}. STEP 2: Say {slot 1}, {slot 2} or {slot 3}. STEP 3: Say a listed number.",
			"STEP 4: Kill that monster. STEP 5: When it is complete, return to the same slot and say {claim}.",
			"",
			"WHAT DO I GET? Hunting Points. Say {shop} to spend them on configured items, mounts, outfits and Weekly Expansion.",
			"",
			"WHAT IS REWARD QUALITY (RARITY)? Every new Hunting Task starts at Basic quality. Quality changes only the Hunting Points you receive at the end; it never changes normal monster EXP or normal loot.",
			"BASIC REWARDS: 1 star = 25 kills for 10 points | 2-3 stars = 100 kills for 40 points | 4-5 stars = 400 kills for 160 points.",
			"Better, Good, Great and Best quality pay more points for the SAME number of kills. For example, a 3-star task starts at 40 points for 100 kills; better quality can pay 50, 63, 79 or 99 points.",
			"HOW TO IMPROVE IT: after starting a Hunting Task, open its Slot and say {reward}. It spends 1 Prey Wildcard and improves the quality. It never makes the reward worse.",
			"",
			"WHAT IS A LIST REROLL? It changes the 9 monster choices in a slot. It is free after its cooldown; otherwise it costs gold.",
			"WHAT IS A WILDCARD? It costs 5 Prey Wildcards and lets you choose a valid monster by name or race ID.",
			"",
			"If your Bestiary for the creature is complete, add the word {upgrade} when choosing it. This doubles kills and doubles the reward.",
		}
	elseif section == "rewards" then
		lines = {
			"=== WHAT ARE MY REWARDS FOR? ===",
			"EXP: normal experience for YOUR character. It raises your player level; it is not a task level. Bounty and Weekly tasks can give bonus EXP.",
			"Say {experience info} if you want the simple full explanation.",
			"",
			"BOUNTY POINTS: earned from Bounty missions. They are NOT shop money.",
			"Use them in only two ways: make your Bounty Talisman stronger, or unlock Preferences for future Bounty monster choices.",
			"The talisman works only against the Bounty monster you chose and still need to finish. Say {bounty talisman info}.",
			"Say {talisman} to improve it, or {preferences} to choose monsters you want me to offer or avoid.",
			"",
			"HUNTING POINTS: earned from Hunting Tasks and Weekly Tasks. Spend them in Vauter's shop.",
			"The shop can offer items, mounts, outfits and Weekly Expansion. Say {shop}, then say {buy 1}, {buy 2}, and so on.",
			"Say {hunting points info} for a simple explanation of how to earn and spend them.",
			"",
			"SOULSEALS: earned from Weekly Tasks. They are tickets for special Soulpit monster arena challenges, not shop money and not EXP.",
			"You need level 100. Say {soulseals info} for the easy guide, then {souls} for the challenge list.",
			"",
			"REROLL TOKENS: replace Bounty choices when you do not like them. Prey Wildcards are used by Hunting Tasks for special selections/rewards.",
		}
	elseif section == "reroll" then
		lines = {
			"=== REROLL: CHANGE A CHOICE YOU DO NOT LIKE ===",
			"BOUNTY REROLL: say {bounty}, then {reroll} BEFORE choosing Bounty {1}, {2} or {3}.",
			"It replaces all three Bounty offers. A free reroll returns after 20 hours; otherwise it uses a reroll token.",
			"Once you started the Bounty, you must finish it before choosing another one.",
			"",
			"HUNTING LIST REROLL: say {hunting}, {slot 1}/{slot 2}/{slot 3}, then {slot 1 reroll} (replace the number with your slot).",
			"It replaces that slot's monster list. It is free after 20 hours; otherwise it costs level x 200 gold.",
			"",
			"HUNTING REWARD REROLL: while a Hunting Task is active, open its slot and say {reward}.",
			"It costs 1 Prey Wildcard and improves the reward grade. It never makes the reward worse.",
		}
	elseif section == "difficulty" then
		lines = {
			"=== DIFFICULTY: WHICH ONE SHOULD I CHOOSE? ===",
			"Beginner is the best first choice. It has smaller goals and easy Bestiary creatures.",
			"Adept is for a player who can comfortably hunt regular creatures.",
			"Expert is for stronger characters who can finish larger kill goals.",
			"Master is for high-level players who want long hunts and larger rewards.",
			"",
			"BOUNTY KILLS: Beginner 50-100 | Adept 100-200 | Expert 200-300 | Master 300-600.",
			"WEEKLY ANY-CREATURE KILLS: Beginner 1,000 | Adept 2,000 | Expert 3,000 | Master 4,000.",
			"WEEKLY NAMED MONSTERS: Beginner 1 star | Adept 2 stars | Expert balanced 3 stars | Master strong 4-5 stars.",
			"Weekly also checks monster health and normal EXP, so a very strong boss is not mixed into an Expert mission.",
			"It also uses only creatures with permanent normal-map spawns, never raid, event, quest or unused-script creatures.",
			"",
			"Simple rule: choose the difficulty you can finish without getting frustrated. You can always choose a harder one next time.",
		}
	elseif section == "souls" then
		lines = {
			"=== SOULPIT: SPEND SOULSEALS ON A CHALLENGE ===",
			"Soulseals are special tickets earned from Weekly Tasks. They are not gold, items or EXP.",
			"You spend them only to enter a Soulpit arena challenge.",
			"You need level 100 and must stand next to the Soulpit obelisk.",
			"Say {souls} to see challenge creatures, their numbers and their Soulseal cost. Then say {fight NUMBER} beside the obelisk.",
			"The cost is paid when the challenge starts. Stronger creatures cost more Soulseals.",
			"IMPORTANT: this server build has no active Animus Mastery bonus. Winning Soulpit does not currently give a stat, item, EXP or usable reward from Animus.",
			"Say {animus mastery info} to understand this limitation before spending Soulseals.",
			"Say {soulseals info} for the complete beginner explanation.",
		}
	else
		lines = {
			"=== START HERE: THE SIMPLE IDEA ===",
			"A TASK is a small extra mission while you play. I ask you to kill monsters or bring items.",
			"Finish the mission, then come back to me to collect its reward.",
			"",
			"THE EASY LOOP: choose a mission -> do the goal -> come back -> get your reward.",
			"Kills for a mission are counted by the server. You do not need to count them yourself.",
			"",
			"THERE ARE THREE DIFFERENT KINDS OF POINTS. Do not mix them up:",
			"",
			"HUNTING POINTS = SHOP MONEY.",
			"Earn them from Hunting Tasks and Weekly Tasks. Say {shop} to trade them for items, mounts, outfits or Weekly Expansion.",
			"They are not gold, EXP, Bounty Points or Soulseals. Say {hunting points info} for the full beginner guide.",
			"",
			"BOUNTY POINTS = BOUNTY HELP.",
			"Earn them from Bounty missions. They CANNOT buy things in the shop.",
			"Spend them to improve the Bounty Talisman or set Preferences for Bounty monster choices.",
			"The talisman helps only against the one Bounty monster you chose and are still hunting. Say {bounty talisman info}.",
			"Preferences tell me monsters you like or dislike for future Bounty choices. Say {preferences}.",
			"",
			"SOULSEALS = SOULPIT TICKETS.",
			"Earn them from Weekly Tasks. Spend them to enter Soulpit challenges at the obelisk. They do NOT buy shop items, and they are not EXP.",
			"Say {soulseals info} to learn what the Soulpit is, how to earn Soulseals and when to use them.",
			"Important: this server build does not currently give a usable Animus Mastery reward for winning Soulpit. Say {animus mastery info} before spending Soulseals.",
			"",
			"EXP = YOUR CHARACTER'S NORMAL LEVEL EXPERIENCE.",
			"It raises your player level, exactly like normal monster experience. It is NOT a task level and tasks have no separate level.",
			"Some Bounty and Weekly goals give bonus EXP directly to your character. Say {experience info} for the complete explanation.",
			"",
			"WHAT SHOULD A NEW PLAYER DO? Say {bounty} -> {beginner} -> choose {1}, {2} or {3}.",
			"Want shop rewards later? Do HUNTING tasks and WEEKLY tasks to earn Hunting Points.",
			"",
			"Ask: 'what are rewards', 'how bounty works', 'how weekly works', 'how hunting works', 'what is reroll', or 'what is difficulty'.",
		}
	end
	show(player, lines)
end

local function showTalisman(player)
	local data = TaskBoardBountyTasks and TaskBoardBountyTasks.loadBountyData(player:getGuid())
	if not data then return false end
	show(player, {
		"=== BOUNTY TALISMAN: SIMPLE EXPLANATION ===",
		"FIRST, TWO WORDS:",
		"Bounty = one monster mission you chose from Vauter.",
		"Active Bounty = the monster mission you chose and have NOT finished yet.",
		"Example: you chose a Dragon Bounty. Until you finish it, Dragon is your active Bounty monster.",
		"",
		"WHAT IS THE TALISMAN? It is an item you wear to get extra help against that one active Bounty monster.",
		"Buy it from Vauter for 5,000 gold: say {trade talisman}. Then put it in your AMMUNITION SLOT.",
		"It is not a prize given by a task. You buy it once, then improve it with Bounty Points.",
		"",
		"WHEN DOES IT WORK? Only when ALL three things are true:",
		"1. The talisman is in your AMMUNITION SLOT.",
		"2. You have started a Bounty and have not claimed it yet.",
		"3. You are fighting the exact monster from that Bounty.",
		"If you are hunting anything else, the talisman gives no bonus. This is normal.",
		"",
		"CHOOSE ONE OF FOUR WAYS TO IMPROVE IT:",
		"1. DAMAGE: your attacks hurt the active Bounty monster more.",
		"2. LIFE LEECH: when you hurt the active Bounty monster, you get some health back.",
		"3. LOOT: when the active Bounty monster drops normal loot, there is a chance to receive an extra copy too.",
		"4. BESTIARY: the Bestiary is your monster-kill book. Sometimes one active Bounty kill counts as TWO kills in that book.",
		"",
		"HOW TO IMPROVE IT:",
		"1. Finish Bounties to earn Bounty Points.",
		"2. Say {upgrade damage}, {upgrade life}, {upgrade loot}, or {upgrade bestiary}.",
		"3. The level goes up and that bonus becomes better. Each new level costs more points.",
		"You choose what matters to you. You do not need to improve all four ways.",
		"",
		"YOUR CURRENT LEVELS:",
		"Damage: " .. ((data.talismans[1] and data.talismans[1].tier) or 0),
		"Life Leech: " .. ((data.talismans[2] and data.talismans[2].tier) or 0),
		"Loot: " .. ((data.talismans[3] and data.talismans[3].tier) or 0),
		"Bestiary: " .. ((data.talismans[4] and data.talismans[4].tier) or 0),
		"Next upgrade cost: 5 + (current path level x 12) Bounty Points.",
	})
	return true
end

local function showPreferences(player)
	local data = TaskBoardBountyTasks and TaskBoardBountyTasks.loadBountyData(player:getGuid())
	if not data then return false end

	local lines = {
		"=== PREFERENCES: TELL VAUTER WHAT YOU LIKE TO HUNT ===",
		"This does NOT make your character stronger. It only changes the monster missions I show you in the future.",
		"Use it if you like hunting one monster and do not want to see another monster as a Bounty choice.",
		"",
		"PREFERRED = 'I like this monster.' I try to show it in your next Bounty choices when it fits your difficulty.",
		"UNWANTED = 'I do not want this monster.' I leave it out of your random Bounty choices.",
		"Example: {prefer 1 dragon} means I try to offer Dragon. {avoid 1 dragon} means I do not offer Dragon randomly.",
		"",
		"HOW TO USE IT - EASY EXAMPLE:",
		"1. Pick a free Slot. Slot 1 is already free and open.",
		"2. To ask for Dragons more often, say: {prefer 1 dragon}",
		"3. To stop seeing Trolls, say: {avoid 1 troll}",
		"4. Use the exact monster name. You do NOT need to know a race ID or any number for the monster.",
		"",
		"Each Slot can save ONE liked monster and ONE unwanted monster. You can use only one of them or both.",
		"More slots let you save more monster names. Slots 2, 3, 4 and 5 cost 300, 600, 900 and 1,200 Bounty Points.",
		"Saving a name is free. To erase a saved name, say {clear prefer 1} or {clear avoid 1}. Erasing costs 10 Bounty Points.",
		"",
	}
	for index, slot in ipairs(data.preferredLists or {}) do
		lines[#lines + 1] = string.format("Slot %d: %s | preferred: %s | unwanted: %s", index,
			slot.active and "unlocked" or "locked", monsterName(slot.preferredRaceId), monsterName(slot.unwantedRaceId))
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "YOUR NEXT STEP: say {prefer 1 MONSTER NAME} or {avoid 1 MONSTER NAME}."
	lines[#lines + 1] = "Examples: {prefer 1 dragon} | {avoid 1 troll} | {clear prefer 1} | {clear avoid 1}"
	lines[#lines + 1] = "When Slot 1 is full, say {unlock preference} to buy and open the next slot."
	show(player, lines)
	return true
end

local function showSoulsealsInfo(player)
	show(player, {
		"=== SOULSEALS: SIMPLE SOULPIT GUIDE ===",
		"Soulseals are NOT gold, items, equipment or experience. They are special points for one place: the Soulpit.",
		"Think of them as tickets. You spend tickets to enter one Soulpit monster challenge.",
		"Your Soulseal Points now: " .. player:getSoulsealsPoints(),
		"",
		"HOW TO EARN THEM:",
		"1. Say {weekly} and complete Weekly goals: monster kills and item deliveries.",
		"2. Return to Vauter and say {claim weekly} when your Weekly reward is ready.",
		"3. That reward gives Hunting Points AND Soulseal Points. Your Soulseal Points are saved on your character.",
		"",
		"WHAT IS THE SOULPIT? It is a special arena challenge against one kind of monster.",
		"You need level 100. Go to the Soulpit obelisk and stand next to it.",
		"Say {souls} to see which monster challenges are available and how many Soulseals each one costs.",
		"Choose one from that list, then say {fight NUMBER} while next to the obelisk. Example: {fight 34}.",
		"",
		"The Soulseal cost is paid only when the challenge starts. Stronger creatures cost more tickets.",
		"IMPORTANT: in this server build, winning Soulpit does not currently give a usable Animus reward such as an item, EXP or stat bonus.",
		"Say {animus mastery info} before you decide to spend Soulseals on a challenge.",
		"If you are new or below level 100, save your Soulseals. You do not need to use them yet.",
	})
	return true
end

local function showExperienceInfo(player)
	show(player, {
		"=== EXP: YOUR CHARACTER'S LEVEL EXPERIENCE ===",
		"EXP means experience points for YOUR PLAYER CHARACTER.",
		"It is the same normal experience you receive from killing monsters in Tibia.",
		"When you gain enough EXP, your character level increases. Higher level lets your character become stronger.",
		"",
		"There is NO task level and there is NO separate task EXP.",
		"A task can give bonus EXP in addition to normal monster EXP. It goes directly to your character's level progress.",
		"",
		"Bounty: finish your chosen monster mission and claim its listed EXP reward.",
		"Weekly: completing its monster or delivery goals can give EXP immediately.",
		"Hunting Tasks: mainly give Hunting Points for the shop, not player EXP.",
		"",
		"Example: if Vauter says a Bounty reward is 10,000 EXP, your character receives 10,000 normal level experience after you claim it.",
	})
	return true
end

local function showHuntingPointsInfo(player)
	show(player, {
		"=== HUNTING POINTS: SIMPLE SHOP GUIDE ===",
		"Hunting Points are NOT gold and NOT experience. They are special shop points saved on your character.",
		"Your Hunting Points now: " .. player:getTaskHuntingPoints(),
		"",
		"HOW TO EARN THEM:",
		"1. Say {hunting}. Choose one of your Hunting Task slots and choose a monster from the list.",
		"2. Kill that monster until the task counter is complete, then say {claim} in its slot.",
		"3. You can also earn Hunting Points from Weekly Task rewards. Say {weekly}, complete goals and {claim weekly}.",
		"",
		"WHAT ARE THEY FOR? Hunting Points let you buy rewards from Vauter's Hunting Shop.",
		"The shop can contain useful items, trophies, backpacks, outfits, mounts and a Weekly Task Expansion.",
		"A mount is an animal your character can ride. An outfit changes your character's appearance.",
		"",
		"HOW TO SPEND THEM:",
		"1. Say {shop}. A window shows every reward and its Hunting Point price.",
		"2. Pick the reward number. Example: say {buy 1} for the first reward.",
		"3. If you have enough Hunting Points, the reward is given to you and the points are removed.",
		"",
		"Hunting Points cannot buy Bounty Talisman upgrades, cannot enter Soulpit and cannot increase your player level.",
		"Think of them as special tickets accepted only in Vauter's Hunting Shop.",
	})
	return true
end

local function showAnimusMasteryInfo(player)
	show(player, {
		"=== ANIMUS MASTERY: IMPORTANT SERVER LIMITATION ===",
		"WHAT YOU SHOULD KNOW FIRST: in the current server code, Animus Mastery gives you NO usable bonus.",
		"It does not give damage, health, loot, EXP, an item, a mount, an outfit, points or access to another feature.",
		"",
		"The Soulpit script tries to save a completion mark called Animus Mastery after you win a challenge.",
		"However, this server build has no active Animus function and no system that reads that mark to reward your character.",
		"So, at the moment, winning Dragon Soulpit or Troll Soulpit is only a personal challenge/completion message; it does not improve your character.",
		"",
		"WHAT SHOULD A NEW PLAYER DO? Do NOT spend Soulseals expecting an Animus reward. Keep them until this feature receives a real reward system, or use Soulpit only for the challenge itself.",
		"Soulseals are still earned from Weekly Tasks, but there is currently no gameplay benefit from Animus Mastery in this server version.",
	})
	return true
end

local function isTaskIntent(message)
	return isQuestion(message) or containsAny(message, {
		"bounty", "weekly", "hunting", "shop", "souls", "soul", "soulseal", "animus", "mastery", "report", "status", "progress", "talisman", "preferences", "reroll", "rarity", "quality", "difficulty", "trade", "experience", "exp", "hunting point", "more info", "more infos",
	})
end

local function getGuideIntent(message, topic)
	local question = isQuestion(message)
	if message == "help" or message == "tasks" or message == "task" or message == "i do not understand" or message == "nao entendi" or message == "não entendi" then
		return "overview"
	end
	if message == "rewards" or message == "reward" or message == "benefits" or message == "points" or message == "where spend points" then
		return "rewards"
	end
	if message == "reroll" and topic == 0 then return "reroll" end
	if message == "difficulty" and topic == 0 then return "difficulty" end
	if message == "rarity" or message == "quality" or message == "reward quality" or message == "reward grade" then return "hunting" end
	if not question then return nil end
	if containsAny(message, { "reroll", "re roll", "wildcard" }) then return "reroll" end
	if containsAny(message, { "difficulty", "beginner", "adept", "expert", "master" }) then return "difficulty" end
	if containsAny(message, { "bounty", "bounty point", "talisman", "prefer" }) then return "bounty" end
	if containsAny(message, { "weekly", "delivery", "deliver" }) then return "weekly" end
	if containsAny(message, { "hunting", "slot", "prey wildcard", "rarity", "quality", "reward grade" }) then return "hunting" end
	if containsAny(message, { "soul", "soulpit", "obelisk" }) then return "souls" end
	if containsAny(message, { "shop", "mount", "outfit", "item", "where", "spend", "point", "reward", "benefit" }) then return "rewards" end
	return "overview"
end

local function showReport(player)
	local lines = {
		"=== TASK REPORT ===",
		"Bounty Points: " .. player:getBountyPoints(),
		"Hunting Points: " .. player:getTaskHuntingPoints(),
		"Soulseal Points: " .. player:getSoulsealsPoints(),
		"",
	}
	if TaskBoardBountyTasks then
		local data = TaskBoardBountyTasks.loadBountyData(player:getGuid())
		if (data.state == 2 or data.state == 3) and data.activeTask then
			local task = data.activeTask
			lines[#lines + 1] = string.format("Bounty: %s - %d/%d killed", monsterName(task.raceId), task.currentKills or 0, task.requiredKills or 0)
			if (task.currentKills or 0) >= (task.requiredKills or 0) then lines[#lines + 1] = "Bounty reward ready: say {claim bounty}." end
		else
			lines[#lines + 1] = "Bounty: no active hunt. Say {bounty} to begin."
		end
	end
	if TaskBoardWeeklyTasks then
		local weekly = TaskBoardWeeklyTasks.loadWeeklyData(player:getGuid())
		if #(weekly.killTasks or {}) == 0 then
			lines[#lines + 1] = "Weekly: not started. Say {weekly} to choose a difficulty."
		else
			lines[#lines + 1] = string.format("Weekly: any creature %d/%d", weekly.anyCreatureCurrent or 0, weekly.anyCreatureTotal or 0)
			if weekly.needsReward then lines[#lines + 1] = "Weekly reward ready: say {claim weekly}." end
		end
	end
	if _TASK_HUNTING_MODULE then
		for _, slot in ipairs(NativeHunting.getSlots(player) or {}) do
			if slot.state == 4 or slot.state == 5 then
				local entry = CustomBestiary and CustomBestiary.getMonster(slot.selectedRaceId)
				local required = nativeReward(entry, slot.rarity)
				if slot.upgraded then required = required * 2 end
				lines[#lines + 1] = string.format("Hunting slot %d: %s - %d/%d killed", slot.slot,
					monsterName(slot.selectedRaceId), slot.currentKills or 0, required)
				if slot.state == 5 then lines[#lines + 1] = "Hunting reward ready: say {hunting}, then {slot " .. slot.slot .. "}." end
			end
		end
	end
	show(player, lines)
end

local function showBounty(player, requestedPage)
	local bounty = TaskBoardBountyTasks
	bounty.openBounty(player)
	local data = bounty.loadBountyData(player:getGuid())
	local lines = {
		"=== BOUNTY: YOUR ONE-MONSTER MISSION ===",
		"Difficulty: " .. difficultyName(data.difficulty),
		"Bounty Points: " .. player:getBountyPoints(),
		"",
	}
	if data.state == 1 then
		lines[#lines + 1] = "Pick ONE monster below. That monster becomes your only Bounty mission until you finish it."
		lines[#lines + 1] = "While hunting it, you still receive its normal monster EXP and normal loot. The Bounty reward below is EXTRA."
		lines[#lines + 1] = ""
		for index, entry in ipairs(data.creaturesList or {}) do
			if (entry.raceId or 0) > 0 then
				lines[#lines + 1] = string.format("%d. %s: kill %d. When finished, claim +%d normal player EXP and +%d Bounty Points. To start this task, say: {%d}", index,
					monsterName(entry.raceId), entry.required or 0, entry.reward or 0, entry.bountyPts or 0, index)
				lines[#lines + 1] = "   " .. monsterFacts(entry.raceId)
			end
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = "WHAT ARE BOUNTY POINTS FOR? They improve your Bounty Talisman or set future monster Preferences. They are not shop money."
		lines[#lines + 1] = "After claiming, you also receive 1 Bounty reroll token if you have room for one. A reroll token replaces future choices you dislike."
		lines[#lines + 1] = ""
		lines[#lines + 1] = ""
		lines[#lines + 1] = "START A TASK NOW: type only the number of the monster you want. Example: type {1} to start the first task above."
		lines[#lines + 1] = "After you type {1}, {2} or {3}, that task starts immediately and the monster kills begin counting automatically."
		lines[#lines + 1] = "Say {reroll} BEFORE choosing if you dislike all three. Say {difficulty} BEFORE choosing to change how big the mission is."
		show(player, lines)
		return data
	elseif (data.state == 2 or data.state == 3) and data.activeTask then
		local task = data.activeTask
		lines[#lines + 1] = "YOUR ACTIVE BOUNTY means the one monster mission you already chose."
		lines[#lines + 1] = string.format("Monster: %s | progress: %d of %d kills.", monsterName(task.raceId), task.currentKills or 0, task.requiredKills or 0)
		lines[#lines + 1] = monsterFacts(task.raceId)
		lines[#lines + 1] = "Every time you kill this exact monster, the number above goes up automatically. Other monsters do not count."
		lines[#lines + 1] = string.format("EXTRA REWARD AT THE END: +%d normal player EXP, +%d Bounty Points and +1 reroll token if you have room.", task.rewardExp or 0, task.rewardBountyPoints or 0)
		lines[#lines + 1] = "You also keep the monster's normal EXP and normal loot while doing the mission."
		lines[#lines + 1] = "Bounty Points can improve your talisman or set Preferences. Say {bounty talisman info} or {preferences} to learn more."
		if (task.currentKills or 0) >= (task.requiredKills or 0) then
			lines[#lines + 1] = "YOU FINISHED! Say {claim bounty} now to receive the extra reward."
		else
			lines[#lines + 1] = "Keep hunting " .. monsterName(task.raceId) .. ". When the progress reaches the goal, come back and say {claim bounty}."
		end
	end
	show(player, lines)
	return data, 1, 1
end

-- Weekly Tasks give EXP immediately per finished objective, then accumulate
-- Hunting Points and Soulseals for the Weekly claim.  These values mirror the
-- untouched Weekly Tasks script, but live here so classic-client players can
-- see the complete reward logic without the Task Board UI.
local WEEKLY_KILL_BASE_POINTS = {
	[0] = 25, -- Beginner
	[1] = 50, -- Adept
	[2] = 100, -- Expert
	[3] = 110, -- Master
}

local function weeklyRewardMultiplier(completedGoals)
	if completedGoals >= 17 then return 8 end
	if completedGoals >= 13 then return 5 end
	if completedGoals >= 9 then return 3 end
	if completedGoals >= 5 then return 2 end
	return 1
end

local function showWeekly(player)
	local data = TaskBoardWeeklyTasks.loadWeeklyData(player:getGuid())
	local killBasePoints = WEEKLY_KILL_BASE_POINTS[data.difficulty] or WEEKLY_KILL_BASE_POINTS[0]
	local completedKills = data.completedKillTasks or 0 -- includes the Any Creature goal
	local completedDeliveries = data.completedDeliveryTasks or 0
	local completedGoals = completedKills + completedDeliveries
	local multiplier = weeklyRewardMultiplier(completedGoals)
	local lines = {
		"=== WEEKLY: MANY SMALL GOALS, ONE BIG REWARD ===",
		"Difficulty: " .. difficultyName(data.difficulty),
		"A Weekly lasts for the current week. It gives you several goals instead of only one monster mission.",
		"You may complete kill goals, item-delivery goals and the Any Creature goal. Each completed goal gives THREE benefits.",
		"NAMED MONSTER STRENGTH: Beginner 1 star | Adept 2 stars | Expert balanced 3 stars | Master strong 4-5 stars.",
		"The system also checks health and normal EXP so each difficulty avoids very weak or extremely strong targets.",
		"Only creatures with permanent normal-map spawns can appear here. Raid, event, quest and unused-script creatures are excluded.",
		"",
	}
	if #(data.killTasks or {}) == 0 then
		lines[#lines + 1] = "There is no Weekly mission yet."
		lines[#lines + 1] = string.format("WHEN YOU START: every named monster goal and the Any Creature goal give +%d normal player EXP now, +%d base Hunting Points and +1 Soulseal. Every item delivery gives +75 normal player EXP now, +75 base Hunting Points and +1 Soulseal.", killBasePoints * 10, killBasePoints)
		lines[#lines + 1] = "Hunting Points are multiplied by completed-goal milestones: 1-4 goals = x1 | 5-8 = x2 | 9-12 = x3 | 13-16 = x5 | 17+ = x8. EXP and Soulseals are never multiplied."
		lines[#lines + 1] = "START A WEEKLY NOW: type {beginner} in the NPC chat. Vauter will create your first goals for this week."
		lines[#lines + 1] = "When you are stronger, you can type {adept}, {expert} or {master} for larger goals."
	else
		lines[#lines + 1] = "HOW TO START THIS WEEKLY: it is already active. You do NOT choose or start each goal one by one."
		lines[#lines + 1] = "For a MONSTER GOAL, simply find and kill the monster written on that line. Its counter starts increasing automatically."
		lines[#lines + 1] = "For the ANY CREATURE GOAL, kill any monster at all. Every monster kill increases that counter automatically."
		lines[#lines + 1] = "For an ITEM GOAL, collect the listed items in your backpack, then say the command shown beside it, for example {deliver 1}."
		lines[#lines + 1] = "To start a brand-new Weekly in the future: say {weekly}, then choose {beginner}, {adept}, {expert} or {master}."
		lines[#lines + 1] = ""
		lines[#lines + 1] = string.format("ANY CREATURE GOAL: %d/%d. Every monster you kill counts here, not only the monsters named below. Finish it: +%d normal player EXP now, +%d base Hunting Points and +1 Soulseal for the Weekly claim.", data.anyCreatureCurrent or 0, data.anyCreatureTotal or 0, data.killTaskRewardExp or 0, killBasePoints)
		lines[#lines + 1] = ""
		lines[#lines + 1] = "MONSTER GOALS: each finished goal gives its EXP immediately, then adds Hunting Points and 1 Soulseal to your Weekly reward."
		for index, task in ipairs(data.killTasks) do
			lines[#lines + 1] = string.format("%d. %s: %d/%d kills. Finish it: +%d normal player EXP now; +%d base Hunting Points and +1 Soulseal for the Weekly claim.", index, monsterName(task.raceId), task.kills or 0, task.required or 0, data.killTaskRewardExp or 0, killBasePoints)
			lines[#lines + 1] = "   " .. monsterFacts(task.raceId)
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = "ITEM GOALS: collect the item in your backpack, then say {deliver NUMBER}. The items are removed only when the delivery is accepted."
		for index, task in ipairs(data.deliveryTasks or {}) do
			local itemType = ItemType(task.itemId)
			local itemName = itemType and itemType:getName() or ("Item #" .. tostring(task.itemId))
			lines[#lines + 1] = string.format("%d. Bring %d %s%s. Finish it: +%d normal player EXP now; +75 base Hunting Points and +1 Soulseal for the Weekly claim. Say {deliver %d}.", index, task.required or task.amount or 0, itemName,
				task.delivered == 1 and " (already delivered)" or "", data.deliveryTaskRewardExp or 0, index)
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = "FINAL WEEKLY REWARD: Hunting Points are shop money; Soulseals are Soulpit tickets. They are NOT Bounty Points, items, mounts or extra loot."
		lines[#lines + 1] = string.format("POINT RULE: each named monster goal and the Any Creature goal add %d base Hunting Points; each item delivery adds 75 base Hunting Points; EVERY finished goal adds 1 Soulseal.", killBasePoints)
		lines[#lines + 1] = "POINT MULTIPLIER: 1-4 finished goals = x1 | 5-8 = x2 | 9-12 = x3 | 13-16 = x5 | 17 or more = x8. The multiplier affects Hunting Points only, not EXP or Soulseals."
		lines[#lines + 1] = string.format("KILLS ALREADY COUNTED: %d/%d for Any Creature. This is your monster-kill progress, and it increases every time you kill any monster.", data.anyCreatureCurrent or 0, data.anyCreatureTotal or 0)
		lines[#lines + 1] = string.format("COMPLETED GOALS: %d. This is NOT your kill count. A goal is completed only after its counter reaches the full target or an item delivery is accepted: %d kill/Any Creature goal(s) + %d delivery goal(s). Current Hunting Point multiplier: x%d.", completedGoals, completedKills, completedDeliveries, multiplier)
		if data.needsReward then
			lines[#lines + 1] = string.format("READY TO CLAIM: +%d Hunting Points for Vauter's shop and +%d Soulseals for Soulpit. Say {claim weekly}.", data.rewardHTP or 0, data.rewardSoulseals or 0)
		else
			lines[#lines + 1] = "No Weekly reward is waiting to be claimed right now. Finish a goal and this screen will show the exact Hunting Points and Soulseals waiting for you."
		end
	end
	show(player, lines)
	return data
end

local function showHunting(player, requestedSlot)
	local slots = _TASK_HUNTING_MODULE and NativeHunting.getSlots(player)
	if not slots then return nil end
	local lines = {
		"=== HUNTING TASKS: HUNT FOR SHOP POINTS ===",
		"Hunting Points: " .. player:getTaskHuntingPoints(),
		"A Hunting Task is an extra goal you can do while normally hunting monsters.",
		"You still receive normal monster EXP and normal loot. When the task ends, you also receive Hunting Points for Vauter's shop.",
		"You can run up to three Hunting Tasks at the same time: one in each Slot.",
		"HOW TO SEE THE CREATURES: say {hunting}. This window shows the creature list available in every free Slot.",
		"HOW TO SEE ONE SLOT ONLY: say {slot 1}, {slot 2} or {slot 3}. I reopen this window showing only that Slot and its creature list.",
		"HOW TO START: after reading that Slot's list, type the {number} beside the monster you want.",
		"REWARD QUALITY (RARITY): every new task starts Basic. Basic rewards are: 1 star = 25 kills / 10 points | 2-3 stars = 100 kills / 40 points | 4-5 stars = 400 kills / 160 points.",
		"Better quality gives more points for the same kills. After you start a task, say {slot NUMBER}, then {reward}; it costs 1 Prey Wildcard and improves the quality without making it worse.",
		"",
		"=== YOUR SLOT STATUS: QUICK CHECK ===",
	}
	for _, slot in ipairs(slots) do
		if slot.state == 2 then
			lines[#lines + 1] = string.format("Slot %d: READY. No creature is selected yet; %d creature choices are loaded for this Slot. Say {slot %d} to see them.", slot.slot, #(slot.raceList or {}), slot.slot)
		elseif slot.state == 3 then
			lines[#lines + 1] = string.format("Slot %d: WILDCARD MODE. No creature is selected yet. Say {slot %d}, then type the {exact creature name} or its {race ID}.", slot.slot, slot.slot)
		elseif slot.state == 4 or slot.state == 5 then
			local entry = CustomBestiary and CustomBestiary.getMonster(slot.selectedRaceId)
			local required, reward = nativeReward(entry, slot.rarity)
			if slot.upgraded then required, reward = required * 2, reward * 2 end
			if slot.state == 5 then
				lines[#lines + 1] = string.format("Slot %d: FINISHED. Your creature was %s (%d/%d kills). %d Hunting Points are waiting. Say {slot %d}, then {claim}.", slot.slot, monsterName(slot.selectedRaceId), slot.currentKills or 0, required, reward, slot.slot)
			else
				lines[#lines + 1] = string.format("Slot %d: ACTIVE. Your selected creature is %s (%d/%d kills). Say {slot %d} to see its full status.", slot.slot, monsterName(slot.selectedRaceId), slot.currentKills or 0, required, slot.slot)
			end
		else
			lines[#lines + 1] = string.format("Slot %d: no task information is loaded yet. Say {slot %d} to refresh it.", slot.slot, slot.slot)
		end
	end
	lines[#lines + 1] = ""
	for _, slot in ipairs(slots) do
		if not requestedSlot or requestedSlot == slot.slot then
			if slot.state == 2 then
				lines[#lines + 1] = string.format("SLOT %d IS READY: choose ONE monster below. Type only its {number} to start that mission.", slot.slot)
				for index, raceId in ipairs(slot.raceList) do
					local entry = CustomBestiary and CustomBestiary.getMonster(raceId)
					local required, reward = nativeReward(entry, 1)
					lines[#lines + 1] = string.format("%d. %s: kill %d, then claim %d Hunting Points for the shop.%s", index, monsterName(raceId), required, reward,
						bestiaryComplete(player, raceId) and " Bestiary complete: say the number with {upgrade} to double both kills and points." or "")
					lines[#lines + 1] = "   " .. monsterFacts(raceId)
				end
				lines[#lines + 1] = "The task reward is Hunting Points only. It does not give Bounty Points, Soulseals or extra player EXP."
				lines[#lines + 1] = string.format("START THIS SLOT NOW: type one {number} from the list. Example: type {2} to start the second monster in Slot %d.", slot.slot)
			elseif slot.state == 3 then
				lines[#lines + 1] = string.format("SLOT %d IS IN WILDCARD MODE. A Wildcard lets you choose a monster by name. Say its {exact name}.", slot.slot)
			elseif slot.state == 4 or slot.state == 5 then
				local entry = CustomBestiary and CustomBestiary.getMonster(slot.selectedRaceId)
				local required, reward = nativeReward(entry, slot.rarity)
				if slot.upgraded then required, reward = required * 2, reward * 2 end
				lines[#lines + 1] = string.format("SLOT %d ACTIVE: %s. Progress: %d of %d kills.", slot.slot,
					monsterName(slot.selectedRaceId), slot.currentKills or 0, required)
				lines[#lines + 1] = monsterFacts(slot.selectedRaceId)
				lines[#lines + 1] = string.format("WHEN YOU FINISH: claim %d Hunting Points for the shop. Reward quality: %s.%s", reward, huntingRewardQuality(slot.rarity),
					slot.upgraded and " This is an upgraded task, so both kills and points were doubled." or "")
				lines[#lines + 1] = "Normal monster EXP and normal loot still belong to you while you hunt. Only this exact monster counts for this Slot."
				if slot.state == 5 then
					lines[#lines + 1] = "YOU FINISHED! Say {claim} now to collect the Hunting Points and free this Slot for a new task."
				else
					lines[#lines + 1] = "Keep hunting this monster. When progress reaches the goal, return to this Slot and say {claim}."
				end
			end
			lines[#lines + 1] = ""
		end
	end
	show(player, lines)
	return slots
end

local function showShop(player)
	local lines = {
		"=== HUNTING TASK SHOP ===",
		"Your Hunting Points: " .. player:getTaskHuntingPoints(),
		"Earn points through Hunting Tasks and Weekly Tasks, then choose an offer below.",
		"",
		"=== HOW TO BUY ===",
		"1. Read the number at the beginning of the reward you want.",
		"2. While talking to Vauter, type {buy NUMBER}. Example: to buy offer 1, say {buy 1}.",
		"3. If you have enough Hunting Points, the points are removed and you receive that reward immediately.",
		"Items are sent first to your Store Inbox or Inbox, then to your backpack if necessary. Mounts and outfits unlock on your character. Weekly Expansion unlocks the extra Weekly goals.",
		"If you do not have enough points, or already own a one-time reward, the purchase is refused and no points are removed.",
		"",
		"=== OFFERS ===",
	}
	for _, offer in ipairs(getShopOffers(player)) do
		lines[#lines + 1] = string.format("%d. %s x%d - %d points%s", offer.index, offer.name, offer.count, offer.price,
			offer.purchased and " (already owned)" or "")
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "YOUR NEXT STEP: type {buy NUMBER}. Example: {buy 1}."
	show(player, lines)
end

local function showSouls(player)
	local entries = SoulPit.buildSoulsealEntries()
	local lines = { "=== SOULPIT ===", "Soulseal Points: " .. player:getSoulsealsPoints(), "Spend these points to challenge a creature in the Soulpit.", "" }
	for index = 1, math.min(40, #entries) do
		local entry = entries[index]
		lines[#lines + 1] = string.format("%s - race ID %d - cost %d", entry.name, entry.raceId, entry.cost)
	end
	lines[#lines + 1] = "Stand beside the Soulpit obelisk and say, for example: {fight 34}"
	show(player, lines)
end

local function startLegacySoulpit(player, raceId)
	if not enabled(configKeys.SOULSEALS_SYSTEM_ENABLED) or not SoulPit or not SoulPit.startEncounter then
		return false
	end
	local entry = CustomBestiary and CustomBestiary.getMonster and CustomBestiary.getMonster(raceId)
	if not entry or not MonsterType(entry.name) then return false end
	if player:getLevel() < 100 then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "[Vauter] You need level 100 to enter the Soulpit.")
		return false
	end
	local position, obelisk = player:getPosition(), SoulPit.obeliskPos
	if not position or not obelisk or position.z ~= obelisk.z or math.abs(position.x - obelisk.x) > 1 or math.abs(position.y - obelisk.y) > 1 then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "[Vauter] Stand next to the Soulpit obelisk before starting a challenge.")
		return false
	end
	local cost = SoulPit.getSoulsealCost(raceId)
	if not cost or player:getSoulsealsPoints() < cost then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "[Vauter] You do not have enough Soulseal Points for that creature.")
		return false
	end
	if SoulPit.encounter then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "[Vauter] Another Soulpit encounter is already running.")
		return false
	end
	if not player:removeSoulsealsPoints(cost) then return false end
	local started = SoulPit.startEncounter(player, entry.name)
	if not started then
		player:addSoulsealsPoints(cost)
		return false
	end
	return true
end

local function creatureSayCallback(npc, creature, type, message)
	local player = Player(creature)
	if not player then return false end
	local cid = player:getId()
	local msg = normalizeMessage(message)
	if not npcHandler:checkInteraction(creature) then
		if not isTaskIntent(msg) or not npcHandler:addInteraction(npc, creature) then
			return false
		end
		say(npc, creature, "Welcome back, " .. player:getName() .. ". I can explain every task and reward. Say {help} whenever you need guidance.")
	end
	local topic = npcHandler:getTopic(cid)

	if not taskBoardEnabled() then
		say(npc, creature, "The Task Board is currently disabled.")
		return true
	end

	if msg == "more infos" or msg == "more info" then
		resetTopic(player)
		say(npc, creature, "I can explain {Hunting Points info}, {Bounty Talisman info}, {preferences}, {Soulseals info}, {Animus Mastery info} and {experience info}. Say one of these options and I will explain it simply.")
		return true
	elseif msg == "hunting points info" or msg == "hunting point info" or (isQuestion(msg) and containsAny(msg, { "hunting point", "hunting points" })) then
		resetTopic(player)
		showHuntingPointsInfo(player)
		say(npc, creature, "This explains Hunting Points from the beginning. Say {hunting} to earn them, or {shop} to spend them.")
		return true
	elseif msg == "animus mastery info" or msg == "animus info" or msg == "mastery info" or (isQuestion(msg) and containsAny(msg, { "animus", "mastery" })) then
		resetTopic(player)
		showAnimusMasteryInfo(player)
		say(npc, creature, "Read this before spending Soulseals: Animus has no usable reward in the current server build.")
		return true
	elseif msg == "soulseals info" or msg == "soulseal info" or msg == "soulpit info" or (isQuestion(msg) and containsAny(msg, { "soulseal", "soulpit" })) then
		resetTopic(player)
		showSoulsealsInfo(player)
		say(npc, creature, "This explains Soulseals from the beginning. Say {souls} only when you are ready to see the challenge list.")
		return true
	elseif msg == "experience info" or msg == "exp info" or msg == "experience" or (isQuestion(msg) and (containsAny(msg, { "experience" }) or msg:match("%f[%a]exp%f[%A]"))) then
		resetTopic(player)
		showExperienceInfo(player)
		say(npc, creature, "EXP always means normal experience for your character level. It is not a task level.")
		return true
	end

	-- Questions about these two Bounty features should open the practical
	-- explanation directly, even if the player does not know the exact command.
	if isQuestion(msg) and containsAny(msg, { "talisman" }) then
		resetTopic(player)
		if not showTalisman(player) then return result(npc, creature, false, "", "The Bounty Talisman information is unavailable.") end
		say(npc, creature, "Read the examples in the window. Say {trade talisman} to buy one when you are ready.")
		return true
	elseif isQuestion(msg) and containsAny(msg, { "preference", "preferred", "unwanted", "avoid" }) then
		resetTopic(player)
		if not showPreferences(player) then return result(npc, creature, false, "", "Bounty preferences are unavailable.") end
		say(npc, creature, "Use the examples in the window. You only need a Slot number and the monster name.")
		return true
	end

	if msg == "bounty talisman info" or msg == "talisman info" or msg == "talisman information" then
		resetTopic(player)
		if not showTalisman(player) then
			return result(npc, creature, false, "", "The Bounty Talisman information is unavailable.")
		end
		say(npc, creature, "This window explains exactly what the talisman does. Say {trade talisman} when you are ready to buy one.")
		return true
	elseif msg == "trade talisman" or msg == "talisman trade" then
		resetTopic(player)
		if npcHandler:onTradeRequest(cid) and npc:openShopWindow(player, npcConfig.shop) then
			say(npc, creature, "My Talisman shop is open. The Bounty Talisman costs 5,000 gold.")
		else
			say(npc, creature, "I could not open the Talisman shop right now. Please say {trade talisman}.")
		end
		return true
	end

	local guideIntent = getGuideIntent(msg, topic)
	if guideIntent then
		resetTopic(player)
		showGuide(player, guideIntent)
		say(npc, creature, "I have explained that step by step. You can now say {bounty}, {weekly} or {hunting} when you are ready. Ask another question at any time.")
		return true
	end

	-- A player may change subject at any time; never leave an old purchase or
	-- selection topic blocking a new Task Board request.
	if topic ~= 0 and (
		msg == "help" or msg == "ajuda" or msg == "como funciona" or msg == "rewards" or msg == "reward" or msg == "benefits" or msg == "what is this" or msg == "how" or msg == "how does it work" or msg == "task" or msg == "tasks" or msg == "task board" or msg == "report" or
		msg == "bounty" or msg == "task bounty" or msg == "weekly" or msg == "task weekly" or
		msg == "hunting" or msg == "hunting task" or msg == "task hunting" or
		msg == "shop" or msg == "souls" or msg == "soul" or msg == "talisman" or msg == "bounty talisman" or
		msg == "preferred" or msg == "preferences" or msg == "more info" or msg == "more infos" or msg == "daily" or msg == "daily reroll" or
		msg == "claim bounty" or msg == "bounty claim" or msg == "claim weekly" or msg == "weekly claim" or
		msg:match("^deliver%s+%d+$") or msg:match("^fight%s+%d+$") or msg:match("^upgrade%s+") or
		msg:match("^prefer%s+") or msg:match("^avoid%s+") or msg:match("^clear%s+") or msg:match("^unlock preference$")
	) then
		resetTopic(player)
		topic = 0
	end

	if topic == TOPIC_BOUNTY_CHOOSE then
		if msg == "difficulty" or msg == "bounty difficulty" or msg == "bounty dificuldade" then
			npcHandler:setTopic(cid, TOPIC_BOUNTY_DIFFICULTY)
			say(npc, creature, "Choose your difficulty: {beginner}, {adept}, {expert} or {master}. Higher difficulties require more kills and offer higher rewards.")
			return true
		elseif msg == "reroll" or msg == "bounty reroll" then
			local success = bountyRerolled(player)
			if success then
				showBounty(player)
				say(npc, creature, "I have prepared three new Bounties. Choose {1}, {2} or {3}.")
			else
				say(npc, creature, "You cannot reroll now. Use your free reroll, a reroll token, or return after the cooldown.")
			end
			return true
		end
		local choice = number(msg)
		local success = false
		if choice and choice >= 1 and choice <= 3 then
			success = bountyTaskSelected(player, choice)
		end
		if success then
			showBounty(player)
			resetTopic(player)
			say(npc, creature, "Excellent choice. Your Bounty has started and every kill will be counted automatically. Return when the task is complete and say {claim bounty}.")
			return true
		end
		say(npc, creature, "Please choose Bounty {1}, {2} or {3}. You may also say {reroll} or {difficulty}.")
		return true
	elseif topic == TOPIC_BOUNTY_DIFFICULTY then
		local value = difficulty(msg)
		if value == nil or not bountyDifficultyChanged(player, value) then
			say(npc, creature, "Say {beginner}, {adept}, {expert} or {master}.")
			return true
		end
		showBounty(player)
		npcHandler:setTopic(cid, TOPIC_BOUNTY_CHOOSE)
		say(npc, creature, "You chose " .. difficultyName(value) .. ". Review the three Bounties, then say {1}, {2} or {3}.")
		return true
	elseif topic == TOPIC_WEEKLY_DIFFICULTY then
		local value = difficulty(msg)
		if value == nil then
			return result(npc, creature, false, "", "Say {beginner}, {adept}, {expert} or {master}.")
		end
		local success = weeklyDifficultyChanged(player, value)
		return result(npc, creature, success, "Your Weekly Tasks have been generated. Say {weekly} to view them.", "This Weekly already has its monster list, so its difficulty is locked until the next weekly reset.")
	elseif topic > TOPIC_HUNTING_SELECT and topic <= TOPIC_HUNTING_SELECT + 3 then
		local slot = topic - TOPIC_HUNTING_SELECT
		if msg == "slot " .. slot .. " wildcard" then
			return result(npc, creature, NativeHunting.perform(player, slot, "wildcard"), "Wildcard mode selected. Say {slot " .. slot .. "}.", "You cannot use a wildcard now.")
		elseif msg == "slot " .. slot .. " reroll" then
			return result(npc, creature, NativeHunting.perform(player, slot, "reroll"), "The creature list was rerolled.", "You cannot reroll that slot now.")
		end
		local selected = number(msg)
		return result(npc, creature, selected and NativeHunting.perform(player, slot, "select", { value = selected, upgrade = msg:find("upgrade", 1, true) ~= nil }), "Your Hunting Task has started.", "Please say the {number} of a listed creature.")
	elseif topic > TOPIC_HUNTING_WILDCARD and topic <= TOPIC_HUNTING_WILDCARD + 3 then
		local slot, raceId = topic - TOPIC_HUNTING_WILDCARD, number(msg)
		if not raceId and CustomBestiary and CustomBestiary.monstersByRaceId then
			for candidateRaceId, entry in pairs(CustomBestiary.monstersByRaceId) do
				if tostring(entry.name):lower() == msg then raceId = candidateRaceId break end
			end
		end
		return result(npc, creature, raceId and NativeHunting.perform(player, slot, "select", raceId), "Your wildcard Hunting Task has started.", "Please say a valid creature {name} or {race ID}.")
	elseif topic > TOPIC_HUNTING_ACTIVE and topic <= TOPIC_HUNTING_ACTIVE + 3 then
		local action = ({ claim = "claim", cancel = "cancel", reward = "reward" })[msg]
		if action == "claim" then
			local slot = topic - TOPIC_HUNTING_ACTIVE
			local started = NativeHunting.perform(player, slot, "claim", nil, function(currentPlayer, success, text)
				npcHandler:say(text, npc, currentPlayer)
			end)
			return result(npc, creature, started, "I am confirming your Hunting Task reward.", "Say {claim}, {cancel} or {reward}.")
		end
		return result(npc, creature, action and NativeHunting.perform(player, topic - TOPIC_HUNTING_ACTIVE, action), "Your Hunting Task has been updated.", "Say {claim}, {cancel} or {reward}.")
	elseif topic == TOPIC_SHOP then
		local offer = tonumber(msg:match("buy%s+(%d+)")) or number(msg)
		if not offer then
			resetTopic(player)
			say(npc, creature, "I did not understand. Say {shop} to view the offers again, or {bounty}, {weekly} or {hunting} to change subject.")
			return true
		end
		return result(npc, creature, offer and TaskBoardHuntingShop.purchaseOffer(player, offer), "Purchase completed.", "Please say {buy 1} for the first offer.")
	end

	if msg == "report" or msg == "status" or msg == "progress" then
		showReport(player)
		say(npc, creature, "Here is your current progress. Say {bounty}, {weekly} or {hunting} when you are ready for the next step.")
	elseif msg == "bounty" or msg == "task bounty" then
		if not enabled(configKeys.BOUNTY_TASKS_ENABLED) or not TaskBoardBountyTasks then return result(npc, creature, false, "", "Bounty Tasks are disabled.") end
		local data = TaskBoardBountyTasks.loadBountyData(player:getGuid())
		if data.state == 2 or data.state == 3 then
			showBounty(player)
			say(npc, creature, "Here is your active Bounty. Every matching kill is counted automatically; return when it is complete and say {claim bounty}.")
		elseif data.state == 1 then
			showBounty(player)
			npcHandler:setTopic(cid, TOPIC_BOUNTY_CHOOSE)
			say(npc, creature, "Your three Bounties are ready. Say {1}, {2} or {3} to choose one. You may also say {reroll} or {difficulty}.")
		else
			npcHandler:setTopic(cid, TOPIC_BOUNTY_DIFFICULTY)
			say(npc, creature, "A Bounty lets you choose exactly what to hunt. First, choose your difficulty: {beginner}, {adept}, {expert} or {master}. Higher difficulties mean more kills and better rewards.")
		end
	elseif msg == "bounty difficulty" or msg == "bounty dificuldade" then
		npcHandler:setTopic(cid, TOPIC_BOUNTY_DIFFICULTY)
		say(npc, creature, "Choose your Bounty level: {beginner}, {adept}, {expert} or {master}. Higher difficulties require more kills and award higher rewards.")
	elseif msg == "bounty reroll" or msg == "reroll" then
		local success = bountyRerolled(player)
		if success then
			showBounty(player)
			npcHandler:setTopic(cid, TOPIC_BOUNTY_CHOOSE)
			say(npc, creature, "Your three Bounty choices were rerolled. Say {1}, {2} or {3}.")
		else
			say(npc, creature, "You cannot reroll your Bounty now. Check the cooldown or your reroll tokens.")
		end
	elseif msg == "claim bounty" or msg == "bounty claim" then
		local success, message = claimBountyWithDetails(player)
		return result(npc, creature, success, message or "", "Your Bounty reward is not ready.")
	elseif msg == "daily" or msg == "daily reroll" then
		return result(npc, creature, dailyBountyRerollClaimed(player), "Your daily Bounty reroll token was claimed.", "Your daily reroll is not ready yet.")
	elseif msg == "talisman" or msg == "bounty talisman" then
		if not showTalisman(player) then return result(npc, creature, false, "", "The Bounty Talismans are unavailable.") end
		say(npc, creature, "The talisman grows with your Bounty Points. Choose the path you want to improve, or say {trade talisman} to buy one.")
	elseif msg == "upgrade damage" or msg == "upgrade life" or msg == "upgrade loot" or msg == "upgrade bestiary" then
		local path = ({ ["upgrade damage"] = 0, ["upgrade life"] = 1, ["upgrade loot"] = 2, ["upgrade bestiary"] = 3 })[msg]
		return result(npc, creature, TaskBoardBountyTasks and TaskBoardBountyTasks.talismanUpgrade(player, path), "Your Bounty Talisman was upgraded.", "You cannot upgrade that talisman path now. Check your Bounty Points and its level cap.")
	elseif msg == "preferred" or msg == "preferences" then
		if not showPreferences(player) then return result(npc, creature, false, "", "Bounty preferences are unavailable.") end
		say(npc, creature, "These choices help me prepare Bounties you actually want to hunt. They do not change your combat power.")
	elseif msg == "unlock preference" then
		return result(npc, creature, TaskBoardBountyTasks and TaskBoardBountyTasks.unlockPreferredSlot(player), "A new preference slot was unlocked.", "You cannot unlock another preference slot now.")
	elseif msg:match("^prefer%s+%d+%s+.+$") then
		local slot, monster = msg:match("^prefer%s+(%d+)%s+(.+)$")
		local raceId = findMonsterRaceId(monster)
		return result(npc, creature, raceId and bountyPreferenceSaved(player, tonumber(slot), raceId, false), "Good choice. " .. monsterName(raceId) .. " is now a monster you like. I will try to offer it in future Bounties when it fits your difficulty.", "I do not know that monster name, or this slot is still locked. Say {preferences} and use a name exactly as it appears in the game, for example: {prefer 1 dragon}.")
	elseif msg:match("^avoid%s+%d+%s+.+$") then
		local slot, monster = msg:match("^avoid%s+(%d+)%s+(.+)$")
		local raceId = findMonsterRaceId(monster)
		return result(npc, creature, raceId and bountyPreferenceSaved(player, tonumber(slot), raceId, true), "Understood. " .. monsterName(raceId) .. " will not appear in your future random Bounty choices.", "I do not know that monster name, or this slot is still locked. Say {preferences} and use a name exactly as it appears in the game, for example: {avoid 1 troll}.")
	elseif msg:match("^clear%s+prefer%s+%d+$") then
		return result(npc, creature, bountyPreferenceCleared(player, tonumber(msg:match("%d+")), false), "Your preferred creature was cleared.", "I could not clear that preference.")
	elseif msg:match("^clear%s+avoid%s+%d+$") then
		return result(npc, creature, bountyPreferenceCleared(player, tonumber(msg:match("%d+")), true), "Your unwanted creature was cleared.", "I could not clear that preference.")
	elseif msg == "weekly" or msg == "task weekly" then
		if not enabled(configKeys.WEEKLY_TASKS_ENABLED) or not TaskBoardWeeklyTasks then return result(npc, creature, false, "", "Weekly Tasks are disabled.") end
		local data = showWeekly(player)
		if #(data.killTasks or {}) == 0 then
			npcHandler:setTopic(cid, TOPIC_WEEKLY_DIFFICULTY)
			say(npc, creature, "Weekly Tasks combine kills and deliveries with progressive rewards. Choose: {beginner}, {adept}, {expert} or {master}.")
		else
			say(npc, creature, "This Weekly already has its monster list, so its difficulty is locked until the next reset. Complete kills, deliver items with {deliver 1} for the first delivery, and use {claim weekly} for pending points.")
		end
	elseif msg == "weekly difficulty" or msg == "weekly dificuldade" then
		local data = TaskBoardWeeklyTasks and TaskBoardWeeklyTasks.loadWeeklyData(player:getGuid())
		if data and (#(data.killTasks or {}) > 0 or #(data.deliveryTasks or {}) > 0) then
			return result(npc, creature, false, "", "This Weekly already has its monster list, so its difficulty is locked until the next weekly reset.")
		end
		npcHandler:setTopic(cid, TOPIC_WEEKLY_DIFFICULTY)
		say(npc, creature, "Choose: {beginner}, {adept}, {expert} or {master}.")
	elseif msg:match("^deliver%s+%d+$") then
		return result(npc, creature, TaskBoardWeeklyTasks and TaskBoardWeeklyTasks.deliverTask(player, tonumber(msg:match("%d+")) - 1), "Delivery accepted.", "You do not have the required items.")
	elseif msg == "claim weekly" or msg == "weekly claim" then
		local success, message = claimWeeklyWithDetails(player)
		return result(npc, creature, success, message or "", "There is no Weekly reward to claim.")
	elseif msg == "hunting" or msg == "hunting task" or msg == "task hunting" then
		if not _TASK_HUNTING_MODULE then return result(npc, creature, false, "", "Hunting Tasks are disabled.") end
		local slots = showHunting(player)
		if not slots then
			say(npc, creature, "Your Hunting Task data could not be loaded. Please try again in a moment.")
		else
			say(npc, creature, "The window now shows the creature list for every free Hunting Slot. To inspect just one list, say {slot 1}, {slot 2} or {slot 3}; then type the {number} beside the creature you want.")
		end
	elseif msg:match("^slot%s+[1-3]$") then
		local slot = tonumber(msg:match("%d+"))
		local data = showHunting(player, slot)[slot]
		if data.state == 2 then
			npcHandler:setTopic(cid, TOPIC_HUNTING_SELECT + slot)
			say(npc, creature, "Choose a creature by {number}. This task rewards Hunting Points for the shop. If the Bestiary is complete, add the word {upgrade}. If you have Prey Wildcards, say {slot " .. slot .. " wildcard}.")
		elseif data.state == 3 then
			npcHandler:setTopic(cid, TOPIC_HUNTING_WILDCARD + slot)
			say(npc, creature, "Say the exact creature {name} or its {race ID}.")
		elseif data.state == 4 or data.state == 5 then
			npcHandler:setTopic(cid, TOPIC_HUNTING_ACTIVE + slot)
			say(npc, creature, data.state == 5 and "Your reward is ready. Say {claim}." or "Say {reward} to try to improve it, or {cancel} to abandon the task.")
		end
	elseif msg:match("^slot%s+[1-3]%s+wildcard$") then
		local slot = tonumber(msg:match("%d+"))
		return result(npc, creature, NativeHunting.perform(player, slot, "wildcard"), "Wildcard mode selected. Say {slot " .. slot .. "}.", "You cannot use a wildcard now.")
	elseif msg:match("^slot%s+[1-3]%s+reroll$") then
		local slot = tonumber(msg:match("%d+"))
		return result(npc, creature, NativeHunting.perform(player, slot, "reroll"), "The creature list was rerolled.", "You cannot reroll that slot now.")
	elseif msg == "shop" then
		if not TaskBoardHuntingShop then return result(npc, creature, false, "", "The Hunting Shop is unavailable.") end
		showShop(player)
		npcHandler:setTopic(cid, TOPIC_SHOP)
		say(npc, creature, "The window explains every purchase. Choose an offer number and say {buy NUMBER}; for the first reward, say {buy 1}.")
	elseif msg == "souls" or msg == "soul" then
		if not enabled(configKeys.SOULSEALS_SYSTEM_ENABLED) or not SoulPit then return result(npc, creature, false, "", "Soulseals are disabled.") end
		showSouls(player)
		say(npc, creature, "Soulseals earned from Weeklies unlock special challenges. Stand next to the Soulpit obelisk and say, for example, {fight 34}.")
	elseif msg:match("^fight%s+%d+$") then
		return result(npc, creature, startLegacySoulpit(player, tonumber(msg:match("%d+"))), "Your Soulpit encounter has started.", "The Soulpit encounter could not be started. Stand by the obelisk, check your level and Soulseal Points.")
	else
		resetTopic(player)
		say(npc, creature, "I am the Task Master. Say {help} for the full guide. I can explain {bounty}, {weekly}, {hunting} and {shop}. Say {more infos} for detailed information, or {trade talisman} to buy one from me.")
	end
	return true
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:setMessage(MESSAGE_GREET, "Welcome, {|PLAYERNAME|}. I am Vauter, the Task Master. Say {help} for the full guide or {report} to see your tasks. Say {more infos} for detailed information, or {trade talisman} to buy one from me.")
npcHandler:setMessage(MESSAGE_FAREWELL, "See you later.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "See you later.")
npcHandler:addModule(FocusModule:new(), npcConfig.name, true, true, true)

-- Standard NPC shop callback: payment and capacity validation are handled by
-- the server's shop layer; this gives the purchased talisman to the player.
npcType.onBuyItem = function(npc, player, itemId, subType, amount, ignore, inBackpacks, totalCost)
	npc:sellItem(player, itemId, amount, subType, 0, ignore, inBackpacks)
end

-- The stock NPC handler forwards default conversation messages only after a
-- player has greeted the NPC. Task help is intentionally an exception: a
-- player can say "help", "rewards", "bounty", etc. after a timeout and
-- Vauter will focus that player again before processing the request.
npcType.onSay = function(npc, creature, type, message)
	local player = Player(creature)
	local msg = normalizeMessage(message)
	if player and not npcHandler:checkInteraction(creature) and isTaskIntent(msg) and npcHandler:isInRange(player:getId()) then
		npcHandler:addInteraction(npc, creature)
		npcHandler:say("Welcome back, " .. player:getName() .. ". Tell me what you want to know and I will guide you.", npc, creature)
		-- Let the normal handler process the same message after refocusing. This
		-- keeps its registered "trade" keyword working even after a timeout.
		return npcHandler:onSay(npc, creature, type, message)
	end
	npcHandler:onSay(npc, creature, type, message)
end

npcType:register(npcConfig)
