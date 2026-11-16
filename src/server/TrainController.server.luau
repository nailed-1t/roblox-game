-- Spins the train around the circular track forever.
-- The train cars are welded to an invisible Root part at the track's center,
-- which a motorized HingeConstraint turns. Players stand on the cars' real
-- floors (precise collision); real physics carries them along.
-- Putting players inside the train is handled by the TrainStability script
-- in StarterCharacterScripts.

local Players = game:GetService("Players")

local train = workspace:WaitForChild("Train")
local root: BasePart = train:WaitForChild("Root")
local motor: HingeConstraint = root:WaitForChild("Motor")

local DIRECTION = 1 -- flip to -1 to reverse

-- Distance from the center of the track to the cars, measured from the model.
local function trackRadius(): number
	local rel = train:WaitForChild("head").Position - root.Position
	return Vector3.new(rel.X, 0, rel.Z).Magnitude
end
local TRACK_RADIUS = trackRadius()

local function targetAngularSpeed(): number
	local speed = train:GetAttribute("Speed") or 30 -- studs per second
	return DIRECTION * speed / TRACK_RADIUS
end

local function applySpeed()
	motor.MotorMaxTorque = math.huge
	motor.AngularVelocity = targetAngularSpeed()
end
applySpeed()
train:GetAttributeChangedSignal("Speed"):Connect(applySpeed)

-- Keep it running forever: the server always owns the train's physics, and
-- if anything ever changes the motor we put it back.
task.spawn(function()
	while true do
		if root:CanSetNetworkOwnership() then
			root:SetNetworkOwner(nil)
		end
		if math.abs(motor.AngularVelocity - targetAngularSpeed()) > 1e-4 then
			applySpeed()
		end
		task.wait(2)
	end
end)

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
