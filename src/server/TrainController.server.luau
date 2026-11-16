-- Spins the train around the circular track forever, with players standing
-- inside it. The train cars are welded to an invisible Root part at the
-- track's center, which a motorized HingeConstraint turns. The cars have an
-- invisible floor, walls and roof (Train.Interior), so players can walk
-- around inside while real physics carries them along.

local Players = game:GetService("Players")

local train = workspace:WaitForChild("Train")
local root: BasePart = train:WaitForChild("Root")
local motor: HingeConstraint = root:WaitForChild("Motor")
local spawnPoints = train:WaitForChild("SpawnPoints")
local pad: BasePart = workspace:WaitForChild("BoardTrainPad")
local prompt: ProximityPrompt = pad:WaitForChild("BoardPrompt")

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

-- Put a character inside the train, standing on the floor of a random car.
local function putInTrain(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local points = spawnPoints:GetChildren()
	if not hrp or #points == 0 then
		return
	end
	local ref = points[math.random(1, #points)] :: ObjectValue
	local attachment = ref.Value :: Attachment
	local target = attachment.WorldCFrame
	character:PivotTo(target)
	-- Start moving at the train's speed so the player doesn't slide.
	hrp.AssemblyLinearVelocity = root:GetVelocityAtPosition(target.Position)
end

-- Every player starts inside the train when they spawn.
local function onCharacter(character: Model)
	character:WaitForChild("Humanoid")
	character:WaitForChild("HumanoidRootPart")
	task.wait(0.2) -- let the character finish loading in
	if character.Parent then
		putInTrain(character)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayer(player)
end

-- Getting back in from outside: use the prompt on the orange pad.
prompt.Triggered:Connect(function(player)
	if player.Character then
		putInTrain(player.Character)
	end
end)
