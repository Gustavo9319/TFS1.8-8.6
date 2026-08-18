-- Read-only Task Board report for classic clients.
-- !task never starts, changes, rerolls, delivers or claims a task. Vauter
-- remains responsible for all actions; this command is the live information panel.

local taskReport = TalkAction("!task")

local HUNTING_LOCKED, HUNTING_EXHAUSTED, HUNTING_SELECT = 0, 1, 2
local HUNTING_WILDCARD, HUNTING_ACTIVE, HUNTING_REDEEM = 3, 4, 5
local WEEKLY_KILL_BASE_POINTS = { [0] = 25, [1] = 50, [2] = 100, [3] = 110 }

local function add(lines, text) lines[#lines + 1] = text end
local function entry(raceId) return CustomBestiary and CustomBestiary.getMonster and CustomBestiary.getMonster(tonumber(raceId) or 0) end
local function name(raceId)
	local monster = entry(raceId)
	return monster and monster.name or ((tonumber(raceId) or 0) > 0 and "Unknown creature #" .. tostring(raceId) or "None selected")
end
local function facts(raceId)
	local monster = entry(raceId)
	return monster and string.format("%d-star creature; about %d normal EXP per kill, plus normal loot.", tonumber(monster.stars) or 0, tonumber(monster.experience) or 0) or "Monster details are unavailable."
end
local function difficulty(value) return ({ [0] = "Beginner", [1] = "Adept", [2] = "Expert", [3] = "Master" })[tonumber(value)] or "Unknown" end
local function trim(value) return tostring(value or ""):lower():match("^%s*(.-)%s*$") end
local function splitRaceList(raw)
	local result = {}
	for value in tostring(raw or ""):gmatch("[^,]+") do
		local raceId = tonumber(value)
		if raceId and raceId > 0 then result[#result + 1] = raceId end
	end
	return result
end

-- Same Task Hunting reward formula used by the native module.
local function huntingReward(raceId, rarity, upgraded)
	local monster = entry(raceId)
	local stars = tonumber(monster and monster.stars) or 1
	local grade = stars <= 1 and 1 or (stars <= 3 and 2 or 3)
	local kills = 25
	for currentGrade = 1, 3 do
		local reward = math.floor((10 * kills) / 25 + 0.5)
		for currentRarity = 1, 5 do
			if currentGrade == grade and currentRarity == (tonumber(rarity) or 1) then
				return upgraded and kills * 2 or kills, upgraded and reward * 2 or reward
			end
			reward = math.floor(reward * (115 + currentGrade * 5) / 100 + 0.5)
		end
		kills = kills * 4
	end
	return 0, 0
end
local function huntingQuality(rarity) return ({ [1] = "basic", [2] = "better", [3] = "good", [4] = "great", [5] = "best" })[tonumber(rarity)] or "basic" end
local function weeklyMultiplier(goals)
	if goals >= 17 then return 8 elseif goals >= 13 then return 5 elseif goals >= 9 then return 3 elseif goals >= 5 then return 2 end
	return 1
end
local function rerollTime(timestamp)
	local seconds = math.max(0, (tonumber(timestamp) or 0) - os.time())
	if seconds == 0 then return "available now" end
	return string.format("available in %dh %dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end
local function bestiaryComplete(player, raceId)
	local monster = entry(raceId)
	if not monster then return false end
	local kills = 0
	if Game.getBestiaryKills then kills = (Game.getBestiaryKills(player:getGuid()) or {})[raceId] or 0
	else
		local resultId = db.storeQuery("SELECT `kills` FROM `player_bestiary_kills` WHERE `player_id` = " .. player:getGuid() .. " AND `raceid` = " .. (tonumber(raceId) or 0))
		if resultId ~= false then kills = result.getDataInt(resultId, "kills"); result.free(resultId) end
	end
	return kills >= (monster.toKill or math.huge)
end

local function addHeader(player, lines)
	add(lines, "=== TASK BOARD: LIVE INFORMATION ===")
	add(lines, "This command is READ-ONLY: it never starts, changes, rerolls, delivers or claims anything.")
	add(lines, "Speak to Vauter for every action. Use this window after hunting to refresh your saved status.")
	add(lines, "")
	add(lines, "YOUR POINTS NOW:")
	add(lines, "Hunting Points: " .. player:getTaskHuntingPoints() .. " (shop money from Hunting and Weekly Tasks).")
	add(lines, "Bounty Points: " .. player:getBountyPoints() .. " (Bounty Talisman and Preferences).")
	add(lines, "Soulseal Points: " .. player:getSoulsealsPoints() .. " (Soulpit tickets).")
end

local function addQuickStatus(player, lines)
	add(lines, "")
	add(lines, "=== QUICK STATUS ===")
	if TaskBoardBountyTasks then
		local bounty = TaskBoardBountyTasks.loadBountyData(player:getGuid())
		if (bounty.state == 2 or bounty.state == 3) and bounty.activeTask then
			local task = bounty.activeTask
			add(lines, string.format("Bounty: %s %d/%d%s.", name(task.raceId), task.currentKills or 0, task.requiredKills or 0, (task.currentKills or 0) >= (task.requiredKills or 0) and " - REWARD READY AT VAUTER" or " - active"))
		elseif bounty.state == 1 then add(lines, "Bounty: 3 offers are waiting for your choice; no mission is active.")
		else add(lines, "Bounty: no mission prepared.") end
	else add(lines, "Bounty: disabled.") end
	if TaskBoardWeeklyTasks then
		local weekly = TaskBoardWeeklyTasks.loadWeeklyData(player:getGuid())
		if #(weekly.killTasks or {}) == 0 then add(lines, "Weekly: not started.")
		else add(lines, string.format("Weekly: %s | Any Creature %d/%d | %d completed goal(s)%s.", difficulty(weekly.difficulty), weekly.anyCreatureCurrent or 0, weekly.anyCreatureTotal or 0, (weekly.completedKillTasks or 0) + (weekly.completedDeliveryTasks or 0), weekly.needsReward and string.format(" | %d Hunting Points + %d Soulseals READY", weekly.rewardHTP or 0, weekly.rewardSoulseals or 0) or "")) end
	else add(lines, "Weekly: disabled.") end
	local resultId = db.storeQuery("SELECT `slot`, `state`, `selected_raceid`, `current_kills`, `rarity`, `upgraded` FROM `player_task_hunting` WHERE `player_id` = " .. player:getGuid() .. " ORDER BY `slot`")
	local slots = {}
	if resultId ~= false then
		repeat
			slots[result.getDataInt(resultId, "slot") + 1] = { state = result.getDataInt(resultId, "state"), raceId = result.getDataInt(resultId, "selected_raceid"), kills = result.getDataInt(resultId, "current_kills"), rarity = result.getDataInt(resultId, "rarity"), upgraded = result.getDataInt(resultId, "upgraded") ~= 0 }
		until not result.next(resultId)
		result.free(resultId)
	end
	for slot = 1, 3 do
		local hunting = slots[slot]
		if not hunting then add(lines, "Hunting Slot " .. slot .. ": not prepared.")
		elseif hunting.state == HUNTING_ACTIVE or hunting.state == HUNTING_REDEEM then
			local required = huntingReward(hunting.raceId, hunting.rarity, hunting.upgraded)
			add(lines, string.format("Hunting Slot %d: %s %d/%d%s.", slot, name(hunting.raceId), hunting.kills, required, hunting.state == HUNTING_REDEEM and " - REWARD READY AT VAUTER" or " - active"))
		elseif hunting.state == HUNTING_SELECT then add(lines, "Hunting Slot " .. slot .. ": creature choice ready.")
		elseif hunting.state == HUNTING_WILDCARD then add(lines, "Hunting Slot " .. slot .. ": wildcard creature choice waiting.")
		elseif hunting.state == HUNTING_LOCKED then add(lines, "Hunting Slot " .. slot .. ": locked.")
		else add(lines, "Hunting Slot " .. slot .. ": no active mission.") end
	end
	local ammo = player:getSlotItem(CONST_SLOT_AMMO)
	add(lines, "Bounty Talisman: " .. (ammo and ammo:getId() == 51978 and "equipped." or "not equipped."))
	add(lines, "=== COMPLETE DETAILS BELOW ===")
end

local function addBounty(player, lines, detailed)
	add(lines, "")
	add(lines, "=== BOUNTY: ONE MONSTER MISSION ===")
	if not TaskBoardBountyTasks then add(lines, "Bounty Tasks are disabled by server configuration."); return end
	local data = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	add(lines, "Difficulty: " .. difficulty(data.difficulty) .. " | Bounty Points: " .. player:getBountyPoints() .. " | Reroll tokens: " .. (data.rerollTokens or 0))
	if (data.state == 2 or data.state == 3) and data.activeTask then
		local task = data.activeTask
		local done = (task.currentKills or 0) >= (task.requiredKills or 0)
		add(lines, string.format("ACTIVE: %s - %d/%d kills.", name(task.raceId), task.currentKills or 0, task.requiredKills or 0))
		add(lines, "Monster: " .. facts(task.raceId))
		add(lines, string.format("Extra reward at Vauter: %d normal player EXP + %d Bounty Points + 1 reroll token if there is room.", task.rewardExp or 0, task.rewardBountyPoints or 0))
		add(lines, done and "STATUS: FINISHED. The reward is waiting at Vauter." or "STATUS: IN PROGRESS. Only this exact monster counts.")
	elseif data.state == 1 then
		add(lines, "STATUS: WAITING FOR A CHOICE. Vauter has three offers ready; no Bounty is active yet.")
		if detailed then for index, task in ipairs(data.creaturesList or {}) do if (task.raceId or 0) > 0 then add(lines, string.format("Offer %d: %s - kill %d; reward %d player EXP + %d Bounty Points.", index, name(task.raceId), task.required or 0, task.reward or 0, task.bountyPts or 0)); add(lines, "  " .. facts(task.raceId)) end end end
	else add(lines, "STATUS: no Bounty is prepared. Vauter can prepare one when you want it.") end
	if detailed then
		add(lines, "")
		add(lines, "You keep normal monster EXP and loot. The listed Bounty EXP and Bounty Points are extra.")
		add(lines, "Bounty Points are NOT shop money: they improve the Bounty Talisman or unlock/use Preferences for future Bounty offers.")
		add(lines, "Mission size: Beginner 50-100 kills | Adept 100-200 | Expert 200-300 | Master 300-600.")
		add(lines, "A reroll changes only the three unchosen offers. An already started Bounty cannot be rerolled.")
	end
end

local function addWeekly(player, lines, detailed)
	add(lines, "")
	add(lines, "=== WEEKLY: MANY GOALS FOR THE CURRENT WEEK ===")
	if not TaskBoardWeeklyTasks then add(lines, "Weekly Tasks are disabled by server configuration."); return end
	local data = TaskBoardWeeklyTasks.loadWeeklyData(player:getGuid())
	if #(data.killTasks or {}) == 0 then
		add(lines, "STATUS: NOT STARTED. Vauter has not created a Weekly list for this character yet.")
		if detailed then add(lines, "A Weekly has named-monster kills, an Any Creature goal and item deliveries."); add(lines, "Target strength: Beginner 1 star | Adept 1-3 stars | Expert 2-5 stars | Master 4-5 stars.") end
		return
	end
	local completedKills, completedDeliveries = data.completedKillTasks or 0, data.completedDeliveryTasks or 0
	local completedGoals = completedKills + completedDeliveries
	local basePoints = WEEKLY_KILL_BASE_POINTS[data.difficulty] or 25
	add(lines, string.format("Difficulty: %s | Any Creature: %d/%d kills | Completed goals: %d (%d kill/Any, %d delivery) | Hunting Point multiplier: x%d.", difficulty(data.difficulty), data.anyCreatureCurrent or 0, data.anyCreatureTotal or 0, completedGoals, completedKills, completedDeliveries, weeklyMultiplier(completedGoals)))
	if data.needsReward then add(lines, string.format("READY AT VAUTER: %d Hunting Points + %d Soulseals.", data.rewardHTP or 0, data.rewardSoulseals or 0)) else add(lines, "No new Weekly reward is waiting right now.") end
	add(lines, string.format("ALREADY CLAIMED THIS WEEK: %d Hunting Points + %d Soulseals.", data.claimedHuntingPoints or 0, data.claimedSoulseals or 0))
	if not detailed then return end
	add(lines, "")
	add(lines, string.format("ANY CREATURE: %d/%d. Every monster kill counts. Finish it: %d player EXP now, then %d base Hunting Points + 1 Soulseal in the Weekly reward.", data.anyCreatureCurrent or 0, data.anyCreatureTotal or 0, data.killTaskRewardExp or 0, basePoints))
	add(lines, "NAMED MONSTER GOALS: only the monster written on the line increases its own counter.")
	for index, task in ipairs(data.killTasks or {}) do add(lines, string.format("%d. %s: %d/%d kills%s. Reward: %d player EXP now; %d base Hunting Points + 1 Soulseal later.", index, name(task.raceId), task.kills or 0, task.required or 0, (task.kills or 0) >= (task.required or 0) and " (finished)" or "", data.killTaskRewardExp or 0, basePoints)); add(lines, "  " .. facts(task.raceId)) end
	add(lines, "ITEM DELIVERIES: keep the items in your backpack. Vauter removes them only if the delivery is accepted.")
	for index, task in ipairs(data.deliveryTasks or {}) do local itemType = ItemType(task.itemId); add(lines, string.format("%d. %d %s%s. Reward: %d player EXP now; 75 base Hunting Points + 1 Soulseal later.", index, task.required or task.amount or 0, itemType and itemType:getName() or "unknown item", task.delivered == 1 and " (delivered)" or "", data.deliveryTaskRewardExp or 0)) end
	add(lines, "WEEKLY RULE: each finished goal gives listed player EXP immediately. It also adds Hunting Points and 1 Soulseal for Vauter to pay.")
	add(lines, "Multiplier affects Hunting Points only: 1-4 goals x1 | 5-8 x2 | 9-12 x3 | 13-16 x5 | 17+ x8. EXP and Soulseals are never multiplied.")
	add(lines, "Weekly rewards are paid once. The 'already claimed' line is this current Weekly's reward record.")
end

local function addHunting(player, lines, detailed)
	add(lines, "")
	add(lines, "=== HUNTING TASKS: THREE PERSONAL SLOTS ===")
	local resultId = db.storeQuery("SELECT `slot`, `state`, `selected_raceid`, `current_kills`, `rarity`, `upgraded`, `race_list`, `free_reroll_at` FROM `player_task_hunting` WHERE `player_id` = " .. player:getGuid() .. " ORDER BY `slot`")
	if resultId == false then add(lines, "STATUS: no Hunting Task slots were prepared yet. Vauter can prepare them when you decide to use Hunting Tasks."); return end
	local slots = {}
	repeat slots[result.getDataInt(resultId, "slot") + 1] = { state = result.getDataInt(resultId, "state"), raceId = result.getDataInt(resultId, "selected_raceid"), kills = result.getDataInt(resultId, "current_kills"), rarity = result.getDataInt(resultId, "rarity"), upgraded = result.getDataInt(resultId, "upgraded") ~= 0, raceList = splitRaceList(result.getDataString(resultId, "race_list")), freeRerollAt = result.getDataLong(resultId, "free_reroll_at") } until not result.next(resultId)
	result.free(resultId)
	for slot = 1, 3 do
		local data = slots[slot]
		if not data then add(lines, "Slot " .. slot .. ": no information is saved yet.")
		elseif data.state == HUNTING_ACTIVE or data.state == HUNTING_REDEEM then local required, reward = huntingReward(data.raceId, data.rarity, data.upgraded); add(lines, string.format("Slot %d: %s - %d/%d kills - %d Hunting Points (%s)%s.", slot, name(data.raceId), data.kills, required, reward, huntingQuality(data.rarity), data.state == HUNTING_REDEEM and " - FINISHED, waiting at Vauter" or " - active"))
		elseif data.state == HUNTING_WILDCARD then add(lines, "Slot " .. slot .. ": wildcard selection is waiting; no monster is active.")
		elseif data.state == HUNTING_SELECT then add(lines, string.format("Slot %d: ready for a monster choice (%d available creatures).", slot, #data.raceList))
		elseif data.state == HUNTING_LOCKED then add(lines, "Slot " .. slot .. ": locked.")
		elseif data.state == HUNTING_EXHAUSTED then add(lines, "Slot " .. slot .. ": no task is active; Vauter can refresh it.")
		else add(lines, "Slot " .. slot .. ": unknown state " .. data.state .. ".") end
	end
	if not detailed then return end
	add(lines, "")
	add(lines, "Hunting Tasks give Hunting Points only. You still receive normal EXP and loot, but no Bounty Points, Soulseals or bonus player EXP.")
	for slot = 1, 3 do
		local data = slots[slot]
		if data and data.state == HUNTING_SELECT then
			add(lines, "SLOT " .. slot .. " AVAILABLE CREATURES:")
			for index, raceId in ipairs(data.raceList) do local required, reward = huntingReward(raceId, 1, false); add(lines, string.format("%d. %s - %d kills for %d Hunting Points%s.", index, name(raceId), required, reward, bestiaryComplete(player, raceId) and "; Bestiary completed, double-reward upgrade available from Vauter" or "")); add(lines, "  " .. facts(raceId)) end
			add(lines, "List reroll cooldown: " .. rerollTime(data.freeRerollAt) .. ". A paid list reroll costs player level x 200 gold.")
		elseif data and (data.state == HUNTING_ACTIVE or data.state == HUNTING_REDEEM) then
			local required, reward = huntingReward(data.raceId, data.rarity, data.upgraded)
			add(lines, string.format("SLOT %d DETAILS: %s, %d/%d kills, %d Hunting Points at Vauter. Reward grade: %s%s.", slot, name(data.raceId), data.kills, required, reward, huntingQuality(data.rarity), data.upgraded and "; Bestiary upgrade doubled kills and points" or "")); add(lines, "  " .. facts(data.raceId))
		elseif data and data.state == HUNTING_WILDCARD then add(lines, "Slot " .. slot .. " wildcard mode costs 5 Prey Wildcards and waits for a valid creature choice at Vauter.") end
	end
	add(lines, "A reward reroll on an active Hunting Task costs 1 Prey Wildcard and can improve its reward grade. This command only reports status.")
end

local function addTalismanAndPreferences(player, lines)
	add(lines, "")
	add(lines, "=== BOUNTY TALISMAN AND PREFERENCES ===")
	if not TaskBoardBountyTasks then add(lines, "Bounty features are disabled by server configuration."); return end
	local data = TaskBoardBountyTasks.loadBountyData(player:getGuid())
	local ammo = player:getSlotItem(CONST_SLOT_AMMO)
	add(lines, "Bounty Talisman: " .. (ammo and ammo:getId() == 51978 and "equipped in the ammunition slot" or "not equipped in the ammunition slot") .. ". It costs 5,000 gold from Vauter.")
	add(lines, string.format("Talisman levels - Damage: %d | Life Leech: %d | Loot: %d | Bestiary: %d.", (data.talismans[1] and data.talismans[1].tier) or 0, (data.talismans[2] and data.talismans[2].tier) or 0, (data.talismans[3] and data.talismans[3].tier) or 0, (data.talismans[4] and data.talismans[4].tier) or 0))
	add(lines, "It works only against the exact monster of an active Bounty while equipped; it gives no bonus against other monsters.")
	add(lines, "Damage makes attacks hurt that Bounty monster more. Life Leech returns health when you hurt it. Loot can add an extra copy of its normal loot. Bestiary can make one kill count twice in the monster-kill book.")
	add(lines, "Each talisman upgrade costs 5 + (current level x 12) Bounty Points. You choose which of the four paths to improve at Vauter.")
	add(lines, "Preferences never make a character stronger. They only guide future Bounty offers toward monsters you like and away from monsters you dislike.")
	for index, slot in ipairs(data.preferredLists or {}) do add(lines, string.format("Preference Slot %d: %s | preferred: %s | unwanted: %s.", index, slot.active and "unlocked" or "locked", name(slot.preferredRaceId), name(slot.unwantedRaceId))) end
	add(lines, "Preference Slot 1 is free. Slots 2-5 cost 300, 600, 900 and 1,200 Bounty Points. Saving is free; clearing costs 10 Bounty Points.")
end

local function addShop(player, lines)
	add(lines, "")
	add(lines, "=== HUNTING POINT SHOP ===")
	add(lines, "Your Hunting Points: " .. player:getTaskHuntingPoints() .. ". They are special shop money from Hunting and Weekly Tasks.")
	add(lines, "Vauter handles purchases. Items go to Store Inbox/Inbox first; mounts and outfits unlock on the character.")
	local ok, offers = pcall(dofile, "data/lib/task_board/shop_offers.lua")
	if not ok or type(offers) ~= "table" then add(lines, "Shop offer data could not be read. Check data/lib/task_board/shop_offers.lua."); return end
	for index, offer in ipairs(offers) do
		local owned = offer.type == 1 and offer.mountId and player:hasMount(offer.mountId) or offer.type == 2 and offer.outfitId and player:hasOutfit(offer.outfitId, offer.addons or 0) or offer.type == 5 and player:hasWeeklyExpansion()
		local kind = ({ [0] = "item", [1] = "mount", [2] = "outfit", [3] = "double item", [5] = "Weekly Expansion" })[offer.type] or "reward"
		add(lines, string.format("%d. %s x%d - %d Hunting Points (%s)%s.", index, offer.name or "Unnamed reward", offer.count or 1, offer.price or 0, kind, owned and " - already owned" or ""))
	end
	add(lines, "Mount = an animal the character can ride. Outfit = a character appearance. Weekly Expansion adds more Weekly goals.")
end

local function addSoulpit(player, lines, detailed)
	add(lines, "")
	add(lines, "=== SOULSEALS AND SOULPIT ===")
	add(lines, "Soulseal Points: " .. player:getSoulsealsPoints() .. ". Weekly Tasks earn them; Soulpit challenges spend them.")
	add(lines, "Soulpit requires level 100. Your level: " .. player:getLevel() .. (player:getLevel() >= 100 and " (eligible by level)." or " (not eligible yet)."))
	if SoulPit and SoulPit.obeliskPos then add(lines, string.format("Soulpit obelisk: %d, %d, %d. Stand beside it before Vauter can start a challenge.", SoulPit.obeliskPos.x, SoulPit.obeliskPos.y, SoulPit.obeliskPos.z)) end
	add(lines, "Cost is stars x 100: 1-star = 100 Soulseals through 5-star = 500 Soulseals. The challenge has seven monster waves and a 10-minute limit.")
	add(lines, "IMPORTANT: current server code records Animus Mastery only as completion. It gives no item, EXP, stat, damage, loot, points, mount or outfit reward.")
	if detailed and SoulPit and SoulPit.buildSoulsealEntries then
		local entries = SoulPit.buildSoulsealEntries()
		add(lines, "SOULPIT CHALLENGES (first 40, ordered by stars):")
		for index = 1, math.min(40, #entries) do local soul = entries[index]; add(lines, string.format("%d. %s - %d stars - %d Soulseals.", index, soul.name, soul.stars or 0, soul.cost or 0)) end
		if #entries > 40 then add(lines, "More Soulpit creatures exist; this report shows the first 40.") end
	end
end

local function addHelp(lines)
	add(lines, "")
	add(lines, "=== SIMPLE SYSTEM GUIDE ===")
	add(lines, "Bounty: choose one monster mission. Finish it for extra player EXP, Bounty Points and usually a reroll token.")
	add(lines, "Weekly: complete many monster, Any Creature and item goals this week. Goals give EXP now; Hunting Points and Soulseals wait at Vauter.")
	add(lines, "Hunting: run up to three monster slots. Each completed slot gives Hunting Points only.")
	add(lines, "Hunting Points = shop money. Bounty Points = talisman/preferences. Soulseals = Soulpit tickets. EXP = normal experience for character level; there is no task level.")
	add(lines, "Claim history: Weekly keeps the current week's claimed-point record. Bounty and Hunting keep their current balances and active status, but the native system does not save a historical list of old claims.")
	add(lines, "Sections: !task bounty | !task weekly | !task hunting | !task shop | !task rewards | !task souls | !task help.")
	add(lines, "Every section is information only. Speak to Vauter if you want to take an action.")
end

function taskReport.onSay(player, words, param)
	if not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then player:sendTextMessage(MESSAGE_STATUS_SMALL, "The Task Board is currently disabled."); return false end
	local mode, lines = trim(param), {}
	addHeader(player, lines)
	addQuickStatus(player, lines)
	if mode == "bounty" then addBounty(player, lines, true)
	elseif mode == "weekly" then addWeekly(player, lines, true)
	elseif mode == "hunting" or mode == "slots" then addHunting(player, lines, true)
	elseif mode == "shop" then addShop(player, lines)
	elseif mode == "souls" or mode == "soulpit" or mode == "soulseals" then addSoulpit(player, lines, true)
	elseif mode == "rewards" or mode == "info" or mode == "infos" then addBounty(player, lines, false); addWeekly(player, lines, false); addHunting(player, lines, false); addTalismanAndPreferences(player, lines); addShop(player, lines); addSoulpit(player, lines, false); addHelp(lines)
	elseif mode == "" or mode == "help" or mode == "guide" then addBounty(player, lines, false); addWeekly(player, lines, false); addHunting(player, lines, false); addTalismanAndPreferences(player, lines); addShop(player, lines); addSoulpit(player, lines, false); addHelp(lines)
	else add(lines, "Unknown section '" .. mode .. "'. Showing the live dashboard."); addBounty(player, lines, false); addWeekly(player, lines, false); addHunting(player, lines, false); addTalismanAndPreferences(player, lines); addShop(player, lines); addSoulpit(player, lines, false); addHelp(lines) end
	player:showTextDialog(1950, table.concat(lines, "\n"))
	return false
end

taskReport:separator(" ")
taskReport:register()
