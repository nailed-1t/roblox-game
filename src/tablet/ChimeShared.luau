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

-- Robots, summoned with coins; each one hunts your opponent.
-- Colours are placeholders until the real models arrive (ServerStorage.ChimeRobots.<id>).
ChimeShared.ROBOTS = {
	{
		id = "glare",
		name = "Glare",
		price = 15,
		color = Color3.fromRGB(255, 214, 64),
		speed = 11,
		counter = "Shine your flashlight (F) on it to send it away. Doors don't stop it.",
	},
	{
		id = "brute",
		name = "Brute",
		price = 20,
		color = Color3.fromRGB(200, 50, 50),
		speed = 14,
		counter = "Pushes through open doors. Shut your door (click it) until it gives up.",
	},
	{
		id = "hollow",
		name = "Hollow",
		price = 25,
		color = Color3.fromRGB(120, 70, 190),
		speed = 9,
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
function ChimeShared.door(side: string): (CFrame, Vector3)
	local d = ChimeShared.sign(side)
	local s = ChimeShared.scale()
	local base = ChimeShared.at(d * 27.6, 0, 0)
	local height = 2.7 * s
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
