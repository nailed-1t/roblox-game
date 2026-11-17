-- Keeps the player steady inside the moving train. Every wagon has a
-- SpawnLocation (Train.Spawns), so players spawn straight into a wagon;
-- this script then lines them up on that wagon's floor and matches the
-- train's speed so they don't slide. They can get off and back on by
-- jumping up into a car.
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

-- Put the player on the floor of the wagon they spawned in (the nearest one).
local function settleInWagon()
	local best: Attachment? = nil
	local bestDistance = math.huge
	for _, ref in ipairs(spawnPoints:GetChildren()) do
		local attachment = (ref :: ObjectValue).Value :: Attachment?
		if attachment then
			local distance = (attachment.WorldPosition - hrp.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = attachment, distance
			end
		end
	end
	if not best then
		return
	end
	local target = best.WorldCFrame
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

task.wait(0.1)
settleInWagon()
