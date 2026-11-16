-- Puts the player inside the moving train when they spawn and keeps them
-- steady on their feet. They can walk out through the open ends of the cars.
-- Placing the player happens here on their own computer (not on the server),
-- so they're put exactly where they see the train and never overlap a wall.

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

-- No jumping, and the train's motion can't knock them over or ragdoll them.
humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
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

-- Start inside the train.
task.wait(0.5) -- let the avatar finish loading in
putInTrain()

-- Getting back in from the orange pad.
prompt.Triggered:Connect(putInTrain)
