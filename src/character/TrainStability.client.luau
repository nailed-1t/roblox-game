-- Puts the player inside the moving train when they spawn and keeps them
-- steady on their feet. They can get off and back on by jumping up into a car.
-- Placing the player happens here on their own computer (not on the server),
-- so they're put exactly where they see the train and never overlap a wall.
local RunService = game:GetService("RunService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

-- The train's motion can't knock them over or ragdoll them.
humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)

local train = workspace:WaitForChild("Train")
local trainRoot = train:WaitForChild("Root") :: BasePart
local spawnPoints = train:WaitForChild("SpawnPoints")
local pad = workspace:WaitForChild("BoardTrainPad")
local prompt = pad:WaitForChild("BoardPrompt") :: ProximityPrompt

local function putInTrain()
	local points = spawnPoints:GetChildren()
	if #points == 0 then
		return
	end
	local ref = points[math.random(1, #points)] :: ObjectValue
	local attachment = ref.Value :: Attachment
	local target = attachment.WorldCFrame
	character:PivotTo(target)
	-- Start moving at the train's speed so the player doesn't slide.
	hrp.AssemblyLinearVelocity = trainRoot:GetVelocityAtPosition(target.Position)
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- While jumping inside the moving train, keep moving with it instead of
-- flying backwards or forwards through the car.
local trainParams = RaycastParams.new()
trainParams.FilterType = Enum.RaycastFilterType.Include
trainParams.FilterDescendantsInstances = { train }

RunService.PreSimulation:Connect(function()
	if humanoid.Health <= 0 or humanoid.FloorMaterial ~= Enum.Material.Air then
		return -- on the ground the floor already carries the player
	end
	if not workspace:Raycast(hrp.Position, Vector3.new(0, -25, 0), trainParams) then
		return -- not above the train
	end
	local trainVelocity = trainRoot:GetVelocityAtPosition(hrp.Position)
	if trainVelocity.Magnitude < 0.5 then
		return -- train is stopped; jump normally
	end
	local walk = humanoid.MoveDirection * humanoid.WalkSpeed
	local current = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(trainVelocity.X + walk.X, current.Y, trainVelocity.Z + walk.Z)
end)

-- Start inside the train.
task.wait(0.5) -- let the avatar finish loading in
putInTrain()

-- Getting back in from the orange pad.
prompt.Triggered:Connect(putInTrain)
