-- Shared normal-map monster pool for Task Board systems.
-- A Bestiary monster is eligible only if it is present in the active map's
-- permanent spawn XML. Quest, raid, event and unused-script creatures stay out.

if _TASK_BOARD_MAP_SPAWN_POOL then
	return _TASK_BOARD_MAP_SPAWN_POOL
end

local MapSpawnPool = {}
local monsterNames = nil
local sourceFile = nil

-- Shared combat bands for Bounty and Weekly difficulty levels.  Bestiary
-- stars classify creature families, but custom servers need HP and EXP caps
-- as well to prevent a mission from mixing trivial and extreme monsters.
local difficultyFilters = {
	[0] = { minStars = 1, maxStars = 1, minHealth = 1, maxHealth = 250, minExperience = 1, maxExperience = 50 },
	[1] = { minStars = 2, maxStars = 2, minHealth = 1, maxHealth = 650, minExperience = 1, maxExperience = 350 },
	[2] = { minStars = 3, maxStars = 3, minHealth = 300, maxHealth = 5000, minExperience = 200, maxExperience = 3000 },
	[3] = { minStars = 4, maxStars = 5, minHealth = 2500, maxHealth = 15000, minExperience = 2000, maxExperience = 12000 },
}

-- Hunting Tasks have no selected difficulty; their offers scale with player
-- level. Minimum and maximum values keep each bracket away from both trivial
-- targets and unreachable bosses.
local huntingLevelFilters = {
	-- Levels 1-50: early game targets.
	{ maximumLevel = 50, minStars = 1, maxStars = 1, minHealth = 1, maxHealth = 600, minExperience = 1, maxExperience = 150 },
	-- Levels 51-100: low-mid game targets.
	{ maximumLevel = 100, minStars = 2, maxStars = 2, minHealth = 100, maxHealth = 2000, minExperience = 50, maxExperience = 700 },
	-- Levels 101-150: mid game targets.
	{ maximumLevel = 150, minStars = 2, maxStars = 3, minHealth = 400, maxHealth = 4000, minExperience = 250, maxExperience = 1600 },
	-- Levels 151-200: established characters. Keep one clear tier so level-8
	-- creatures (such as Scarab) cannot enter this selection.
	{ maximumLevel = 200, minStars = 3, maxStars = 3, minHealth = 1000, maxHealth = 6500, minExperience = 700, maxExperience = 3500 },
	-- Levels 201-300: late mid game targets.
	{ maximumLevel = 300, minStars = 3, maxStars = 4, minHealth = 1800, maxHealth = 9000, minExperience = 1500, maxExperience = 6500 },
	-- Levels 301-400: high-level targets.
	{ maximumLevel = 400, minStars = 4, maxStars = 4, minHealth = 3000, maxHealth = 13000, minExperience = 3000, maxExperience = 11000 },
	-- Levels 401-500: advanced targets.
	{ maximumLevel = 500, minStars = 4, maxStars = 5, minHealth = 5000, maxHealth = 20000, minExperience = 5000, maxExperience = 18000 },
	-- Levels 501+: endgame targets, still excluding extreme raid/boss values.
	{ maximumLevel = math.huge, minStars = 4, maxStars = 5, minHealth = 7500, maxHealth = 30000, minExperience = 7500, maxExperience = 25000 },
}

local function normalizeName(name)
	return tostring(name or ""):lower():gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
end

local function fileExists(path)
	local file = io.open(path, "rb")
	if not file then return false end
	file:close()
	return true
end

local function worldPath(path)
	path = tostring(path or ""):gsub("\\", "/")
	if path:sub(1, 11) == "data/world/" then
		return path
	end
	return "data/world/" .. path
end

local function findSpawnFileInOtbm(mapName)
	local mapFile = io.open("data/world/" .. mapName .. ".otbm", "rb")
	if not mapFile then return nil end

	-- Scan the binary OTBM in chunks. Loading a large map into Lua just to find
	-- EXT_SPAWN_FILE would consume unnecessary memory.
	local tail = ""
	while true do
		local chunk = mapFile:read(65536)
		if not chunk then break end
		local data = tail .. chunk
		for spawnName in data:gmatch("([%w%._%-%/\\]+%-spawn%.xml)") do
			local candidate = worldPath(spawnName)
			if fileExists(candidate) then
				mapFile:close()
				return candidate
			end
		end
		tail = data:sub(-512)
	end
	mapFile:close()
	return nil
end

local function loadMonsterNames()
	if monsterNames then return monsterNames end

	monsterNames = {}
	local mapName = configManager and configManager.getString and configManager.getString(configKeys.MAP_NAME) or ""
	local spawnFile = mapName ~= "" and findSpawnFileInOtbm(mapName) or nil
	if not spawnFile and mapName ~= "" then
		local fallback = worldPath(mapName .. "-spawn.xml")
		if fileExists(fallback) then
			spawnFile = fallback
		end
	end

	sourceFile = spawnFile
	if not spawnFile then
		print("[Task Board] Could not find the active map spawn XML. Task targets will not be generated.")
		return monsterNames
	end

	local file = io.open(spawnFile, "rb")
	if not file then
		print("[Task Board] Could not read map spawn XML: " .. spawnFile)
		return monsterNames
	end
	local contents = file:read("*a")
	file:close()
	for name in contents:gmatch('<monster%s+.-name%s*=%s*"([^"]+)"') do
		monsterNames[normalizeName(name)] = true
	end

	if not next(monsterNames) then
		print("[Task Board] No monster entries found in map spawn XML: " .. spawnFile)
	else
		print("[Task Board] Task targets use normal-map spawns from: " .. spawnFile)
	end
	return monsterNames
end

function MapSpawnPool.hasMonster(name)
	return loadMonsterNames()[normalizeName(name)] == true
end

function MapSpawnPool.isDifficultyTarget(entry, difficulty)
	local filter = difficultyFilters[tonumber(difficulty) or 0] or difficultyFilters[0]
	if not entry or not MapSpawnPool.hasMonster(entry.name) then return false end
	local stars = tonumber(entry.stars) or 0
	local health = tonumber(entry.health) or 0
	local experience = tonumber(entry.experience) or 0
	return stars >= filter.minStars and stars <= filter.maxStars
		and health >= filter.minHealth and health <= filter.maxHealth
		and experience >= filter.minExperience and experience <= filter.maxExperience
end

function MapSpawnPool.isHuntingTarget(entry, level)
	if not entry or not MapSpawnPool.hasMonster(entry.name) then return false end
	level = math.max(0, tonumber(level) or 0)
	local filter = huntingLevelFilters[#huntingLevelFilters]
	for _, candidate in ipairs(huntingLevelFilters) do
		if level <= candidate.maximumLevel then
			filter = candidate
			break
		end
	end
	local stars = tonumber(entry.stars) or 0
	local health = tonumber(entry.health) or 0
	local experience = tonumber(entry.experience) or 0
	return stars >= filter.minStars and stars <= filter.maxStars
		and health >= filter.minHealth and health <= filter.maxHealth
		and experience >= filter.minExperience and experience <= filter.maxExperience
end

function MapSpawnPool.getSourceFile()
	loadMonsterNames()
	return sourceFile
end

function MapSpawnPool.invalidate()
	monsterNames = nil
	sourceFile = nil
end

_TASK_BOARD_MAP_SPAWN_POOL = MapSpawnPool
return MapSpawnPool
