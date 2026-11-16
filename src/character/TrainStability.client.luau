-- Keeps the player inside the moving train and steady on their feet.
-- Placing the player happens here on their own computer (not on the server),
-- so they're put exactly where they see the train and never overlap a wall.
local RunService = game:GetService("RunService")

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
local interior = train:WaitForChild("Interior")
local spawnPoints = train:WaitForChild("SpawnPoints")
local pad = workspace:WaitForChild("BoardTrainPad")
local prompt = pad:WaitForChild("BoardPrompt") :: ProximityPrompt

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { interior }

local function isInTrain(): boolean
	return workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), rayParams) ~= nil
end

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

-- If the player ever ends up outside the train (or stuck in its floor),
-- put them back inside.
local outsideSince: number? = nil
RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 then
		return
	end
	if isInTrain() then
		outsideSince = nil
	elseif not outsideSince then
		outsideSince = os.clock()
	elseif os.clock() - outsideSince > 1 then
		outsideSince = nil
		putInTrain()
	end
end)
