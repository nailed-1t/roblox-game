-- Keeps players steady while riding the moving train:
-- 1. The train's motion can't knock them over or ragdoll them.
-- 2. When they jump inside the train, they keep moving with it instead of
--    flying backwards (or forwards) through the car.
local RunService = game:GetService("RunService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)

local train = workspace:WaitForChild("Train")
local trainRoot = train:WaitForChild("Root") :: BasePart
local interior = train:WaitForChild("Interior")

local MAX_DROP = 20 -- only counts as "in the train" if its floor is this close below

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { interior }

local function isOverTrainFloor(): boolean
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -MAX_DROP, 0), rayParams)
	return hit ~= nil
end

RunService.PreSimulation:Connect(function()
	if humanoid.Health <= 0 or humanoid.FloorMaterial ~= Enum.Material.Air then
		return -- on the ground the floor already carries the player
	end
	if not isOverTrainFloor() then
		return
	end
	-- In the air above the train: move with the train, plus whatever
	-- direction the player is actually walking.
	local trainVelocity = trainRoot:GetVelocityAtPosition(hrp.Position)
	local walk = humanoid.MoveDirection * humanoid.WalkSpeed
	local current = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(trainVelocity.X + walk.X, current.Y, trainVelocity.Z + walk.Z)
end)
