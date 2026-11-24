-- Shared settings for "Chime of Conflict": two players are locked in the two
-- rooms at opposite ends of the Looping Rooms map (workspace.ChimeMap). They
-- play Snake and Minesweeper on their tablets to earn coins (match-only, gone
-- when the match ends) and spend them on items or on robots that hunt the
-- other player. Used by the server (ChimeServer), the tablet app (ChimeApp)
-- and the on-screen match controls (ChimeClient).

local ChimeShared = {}

ChimeShared.START_ENERGY = 100
ChimeShared.MAX_ENERGY = 200
ChimeShared.DOOR_DRAIN = 1.2 -- energy per second while your door is shut
ChimeShared.FLASH_DRAIN = 2 -- energy per second while your flashlight is on
ChimeShared.MATCH_SECONDS = 8 * 60 -- a draw if nobody has been caught by then
ChimeShared.COUNTDOWN = 15 -- seconds in your room before the match starts
ChimeShared.PASSIVE_COINS = 0.5 -- coins per second, just for staying alive

-- the minigames are smaller during a match
ChimeShared.SNAKE_SIZE = 11 -- board is 11 x 11 (normally 17 x 17)
ChimeShared.MINES_LEVELS = {
	easy = { size = 6, mines = 4, minSeconds = 2 },
	medium = { size = 8, mines = 9, minSeconds = 4 },
	hard = { size = 10, mines = 15, minSeconds = 7 },
}

-- Robots: each player owns one of each, waiting in their alcove. Spend coins
-- to wake one; it then creeps toward your opponent's room FNAF-style: every
-- `interval` seconds it has a `chance` to jump to the next camera spot.
-- Colours are placeholders until the real models arrive (ServerStorage.ChimeRobots.<id>).
ChimeShared.ROBOTS = {
	{
		id = "glare",
		name = "Glare",
		price = 15,
		color = Color3.fromRGB(255, 214, 64),
		speed = 11,
		interval = 5,
		chance = 0.7,
		counter = "Shine your flashlight (F) on it to send it away. Doors don't stop it.",
	},
	{
		id = "brute",
		name = "Brute",
		price = 20,
		color = Color3.fromRGB(200, 50, 50),
		speed = 14,
		interval = 4,
		chance = 0.65,
		counter = "Pushes through open doors. Shut the door it comes to (E front, Z / C sides) until it gives up.",
	},
	{
		id = "hollow",
		name = "Hollow",
		price = 25,
		color = Color3.fromRGB(120, 70, 190),
		speed = 9,
		interval = 6,
		chance = 0.6,
		counter = "Walks into your room. Put your mask on (Q) before it reaches you.",
	},
}

ChimeShared.ITEMS = {
	{ id = "token", name = "Death Token", price = 40, icon = "💀", description = "Survive being caught once." },
	{ id = "energy", name = "Extra Energy", price = 12, icon = "🔋", description = "+40 energy for your door and flashlight." },
}

ChimeShared.SOUNDS = {
	glare = "rbxassetid://9125818886", -- slow metal footsteps
	brute = "rbxassetid://9118240078", -- heavy metal clunks
	hollow = "rbxassetid://9113984056", -- deep monster breathing
	bang = "rbxassetid://9114205090", -- banging on the door
	door = "rbxassetid://9119387876", -- the shutter moving
	chime = "rbxassetid://9113455791", -- a robot driven off by the light
	scream = "rbxassetid://9114570689", -- caught
}

---------------------------------------------------------------- the map
-- Positions are given in metres on the map's plan (x along the building,
-- y across it, z up), the way it was modelled; at() turns them into world
-- positions using the imported mesh, so the map can be moved or rescaled.
--   rooms:   the two player rooms at x = -31 and x = +31
--   doors:   the archway into each room at x = -27.6 / +27.6 (6 m wide)
--   robots:  start in an alcove off the central hall and loop round by the
--            top or bottom corridor to the victim's room

function ChimeShared.map(): Model?
	return workspace:FindFirstChild("ChimeMap") :: Model?
end

local function frame()
	local map = ChimeShared.map()
	local main = map and map:FindFirstChild("Plane.004") :: BasePart?
	if not main then
		return nil, nil
	end
	return main.Position, main.Size.Y / 6.01
end

function ChimeShared.at(x: number, y: number, z: number?): Vector3
	local c, s = frame()
	if not c then
		return Vector3.zero
	end
	return c + Vector3.new(-x * s, ((z or 0) - 2.885) * s, y * s)
end

function ChimeShared.scale(): number
	local _, s = frame()
	return s or 3
end

-- side "A" is the room at plan x = -31, side "B" at x = +31
function ChimeShared.sign(side: string): number
	return if side == "A" then -1 else 1
end

function ChimeShared.roomSpawn(side: string): CFrame
	local d = ChimeShared.sign(side)
	local p = ChimeShared.at(d * 32.3, 0, 0) + Vector3.new(0, 3, 0)
	local toward = ChimeShared.at(0, 0, 0) + Vector3.new(0, 3, 0)
	return CFrame.lookAt(p, Vector3.new(toward.X, p.Y, toward.Z))
end

-- the doorway: centre at floor level, width along world Z, facing the hall
-- the roller-shutter picture on the front doors (assets/chime-shutter.png)
ChimeShared.SHUTTER_TEXTURE = "rbxassetid://106935131448491"

function ChimeShared.door(side: string): (CFrame, Vector3)
	local d = ChimeShared.sign(side)
	local s = ChimeShared.scale()
	local base = ChimeShared.at(d * 27.6, 0, 0)
	local height = 5.75 * s -- the doorway goes all the way up to the ceiling
	local size = Vector3.new(0.6, height, 6 * s)
	return CFrame.new(base + Vector3.new(0, height / 2, 0)), size
end

-- route from the robots' alcove to the inside of a room
-- lane: 1 = top corridor, -1 = bottom corridor
function ChimeShared.route(side: string, lane: number): { Vector3 }
	local d = ChimeShared.sign(side)
	local plan = {
		{ 0, 8 * lane }, -- the alcove off the central hall
		{ 0, 4.5 * lane },
		{ d * 6.5, 4.5 * lane },
		{ d * 19.9, 4.5 * lane }, -- end of the corridor
		{ d * 19.9, 0 },
		{ d * 25.2, 0 }, -- in front of the door
		{ d * 29.6, 0 }, -- inside the room
	}
	local out = {}
	for i, p in ipairs(plan) do
		out[i] = ChimeShared.at(p[1], p[2], 0) + Vector3.new(0, 3, 0)
	end
	return out
end
ChimeShared.DOOR_STOP = 6 -- route index just outside the door
ChimeShared.INSIDE = 7 -- route index inside the room

---------------------------------------------------------------- robot spots
-- Owner A's robots wait in the north alcove, owner B's in the south one.
-- Stages: 1 home, 2 central hall, 3 near corridor, 4 far corridor,
-- 5 outside the room, 6 at a door, 7 inside the room.
-- Each room has three ways in (`entry`): 0 = the front doorway, or +1 / -1 =
-- the side door into the closet at plan y > 0 / y < 0 (reached by the
-- corridor that loops round the closet block).
ChimeShared.STAGE_DOOR = 6
ChimeShared.STAGE_INSIDE = 7
ChimeShared.STAGES = 7

local KIND_SLOT = { glare = -1, brute = 0, hollow = 1 }

local function lane(owner: string): number
	return if owner == "A" then 1 else -1
end

local function planPoint(owner: string, kind: string, victim: string, stage: number, entry: number?): (number, number)
	local L = lane(owner)
	local d = ChimeShared.sign(victim)
	local k = KIND_SLOT[kind] or 0
	local e = entry or 0
	if stage <= 1 then
		return k * 1.2, (8.9 - math.abs(k) * 0.5) * L
	elseif stage == 2 then
		return k * 1.1, 2.5 * L
	elseif stage == 3 then
		return d * 9, (4.5 + k * 0.6) * L
	elseif stage == 4 then
		return d * 16.5, (4.5 + k * 0.6) * L
	elseif e ~= 0 then
		-- round the closet block and in by a side door
		if stage == 5 then
			return d * (24.5 + k * 0.9), 8.2 * e
		elseif stage == 6 then
			return d * (31.5 + k * 0.5), (4.6 + k * 0.3) * e
		else
			return d * (30.9 + k * 0.6), 1.3 * e
		end
	elseif stage == 5 then
		return d * 19.9, (1.2 + k * 0.6) * L
	elseif stage == 6 then
		return d * 25.2, k * 0.9
	else
		return d * 29.4, k * 0.9
	end
end

-- where a robot stands at a stage (feet + 3 studs, like a character's root)
function ChimeShared.robotSpot(owner: string, kind: string, victim: string, stage: number, entry: number?): CFrame
	local x, y = planPoint(owner, kind, victim, stage, entry)
	local p = ChimeShared.at(x, y, 0) + Vector3.new(0, 3, 0)
	local tx, ty
	if stage <= 1 then
		tx, ty = 0, 0
	elseif stage >= ChimeShared.STAGES then
		tx, ty = ChimeShared.sign(victim) * 31, 0
	elseif stage == ChimeShared.STAGE_DOOR and (entry or 0) ~= 0 then
		tx, ty = x, 0 -- facing the side door
	else
		tx, ty = planPoint(owner, kind, victim, stage + 1, entry)
	end
	local t = ChimeShared.at(tx, ty, 0)
	return CFrame.lookAt(p, Vector3.new(t.X, p.Y, t.Z))
end

-- which closet side (plan y sign) a player's left / right door is on
-- (players face the front doorway, toward the middle of the map)
function ChimeShared.sideEntry(side: string, which: string): number
	local d = ChimeShared.sign(side)
	return if which == "left" then -d else d
end

-- security cameras: name, where it hangs, what it looks at (plan metres)
ChimeShared.CAMERAS = {
	{ name = "CAM 1 · Central Hall", from = { 0, -5, 5.2 }, to = { 0, 3, 0.8 } },
	{ name = "CAM 2 · North Alcove", from = { 0, 4, 5.2 }, to = { 0, 9, 0.5 } },
	{ name = "CAM 3 · South Alcove", from = { 0, -4, 5.2 }, to = { 0, -9, 0.5 } },
	{ name = "CAM 4 · West Corridor N", from = { -6.5, 4.5, 5.2 }, to = { -19, 4.5, 0.8 } },
	{ name = "CAM 5 · West Corridor S", from = { -6.5, -4.5, 5.2 }, to = { -19, -4.5, 0.8 } },
	{ name = "CAM 6 · West Hall", from = { -19.5, 8.5, 5.2 }, to = { -24, -1, 0.8 } },
	{ name = "CAM 7 · East Corridor N", from = { 6.5, 4.5, 5.2 }, to = { 19, 4.5, 0.8 } },
	{ name = "CAM 8 · East Corridor S", from = { 6.5, -4.5, 5.2 }, to = { 19, -4.5, 0.8 } },
	{ name = "CAM 9 · East Hall", from = { 19.5, 8.5, 5.2 }, to = { 24, -1, 0.8 } },
}

---------------------------------------------------------------- client signals
-- Local events between the tablet app and the on-screen controls (only used
-- on players' computers).
local signals = nil
function ChimeShared.signal(name: string): BindableEvent
	signals = signals or {}
	if not signals[name] then
		signals[name] = Instance.new("BindableEvent")
	end
	return signals[name]
end

return ChimeShared
