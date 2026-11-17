-- Drives the train around the circular track forever, stopping at evenly
-- spaced stations (every quarter lap by default).
-- The train cars are welded to an invisible Root part at the track's center,
-- which a motorized HingeConstraint turns. Players stand on the cars' real
-- floors (precise collision); real physics carries them along.
-- Putting players inside the train is handled by the TrainStability script
-- in StarterCharacterScripts.
--
-- Settings (attributes on the Train model):
--   Speed        cruising speed in studs per second
--   Stops        number of stops per lap (4 = every quarter)
--   StopSeconds  how long the train waits at each stop
--   Acceleration how quickly it speeds up / slows down, studs per second²
--   FieldWarningSeconds  how long before leaving the force fields switch on
--
-- While the train is moving, force fields (Train.ForceFields) block the open
-- ends of every car so nobody can get on or off. They switch off at stops.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local train = workspace:WaitForChild("Train")
local root: BasePart = train:WaitForChild("Root")
local motor: HingeConstraint = root:WaitForChild("Motor")
local head: BasePart = train:WaitForChild("head")

local DIRECTION = 1 -- flip to -1 to reverse

local function setting(name: string, default: number): number
	local value = train:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

-- The place uses an R6 StarterCharacter; dress it in the player's own avatar.
local function applyAvatar(player: Player, character: Model)
	if player.UserId <= 0 then
		return -- Studio test players have no avatar
	end
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if ok and description then
		pcall(function()
			humanoid:ApplyDescription(description)
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		applyAvatar(player, character)
	end)
	if player.Character then
		task.spawn(applyAvatar, player, player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
end

-- The server always owns the train's physics so every player sees the same thing.
task.spawn(function()
	while true do
		if root:CanSetNetworkOwnership() then
			root:SetNetworkOwner(nil)
		end
		task.wait(2)
	end
end)

-- Distance from the center of the track to the cars, measured from the model.
local function trackRadius(): number
	local rel = head.Position - root.Position
	return Vector3.new(rel.X, 0, rel.Z).Magnitude
end
local TRACK_RADIUS = trackRadius()

-- Angle of the locomotive around the track center (radians).
local function headAngle(): number
	local rel = head.Position - root.Position
	return math.atan2(rel.Z, rel.X)
end

-- Track how far (in radians) the train has travelled in total.
local travelled = 0
local lastAngle = headAngle()
local function updateTravelled()
	local angle = headAngle()
	local delta = angle - lastAngle
	-- unwrap across the -pi/pi seam
	if delta > math.pi then
		delta -= 2 * math.pi
	elseif delta < -math.pi then
		delta += 2 * math.pi
	end
	lastAngle = angle
	-- positive motor speed moves the locomotive towards smaller angles
	travelled += -delta * DIRECTION
end

-- Force fields across the cars' doorways: solid and visible while moving.
local forceFields = train:WaitForChild("ForceFields")
local function setForceFields(on: boolean)
	for _, field in ipairs(forceFields:GetChildren()) do
		if field:IsA("BasePart") then
			field.CanCollide = on
			field.Transparency = if on then 0.4 else 1
		end
	end
	train:SetAttribute("ForceFieldsOn", on)
end

local function setSpeed(studsPerSecond: number)
	motor.MotorMaxTorque = math.huge
	motor.MotorMaxAcceleration = setting("Acceleration", 8) / TRACK_RADIUS
	motor.AngularVelocity = DIRECTION * studsPerSecond / TRACK_RADIUS
end

local function currentSpeed(): number -- studs per second along the track
	return math.abs(root.AssemblyAngularVelocity.Y) * TRACK_RADIUS
end

-- Forever: drive to the next station, then wait there. Stations are measured
-- from where the train started, so small stopping errors never add up.
local stationIndex = 0
while true do
	local stops = math.max(1, math.floor(setting("Stops", 4)))
	stationIndex += 1
	local target = stationIndex * (2 * math.pi / stops)

	setForceFields(true)
	setSpeed(setting("Speed", 50))
	local braking = false
	while true do
		RunService.Heartbeat:Wait()
		updateTravelled()
		local remaining = (target - travelled) * TRACK_RADIUS -- studs
		local speed = currentSpeed()
		local brakingDistance = speed * speed / (2 * setting("Acceleration", 8))
		if not braking and remaining <= brakingDistance then
			braking = true
			setSpeed(0)
		end
		if remaining <= 0 or (braking and speed < 0.05) then
			break
		end
	end
	setSpeed(0)
	setForceFields(false)

	-- Wait at the station; the force fields come back on just before leaving.
	local warning = math.clamp(setting("FieldWarningSeconds", 2), 0, setting("StopSeconds", 10))
	task.wait(setting("StopSeconds", 10) - warning)
	setForceFields(true)
	task.wait(warning)
	updateTravelled()
end
