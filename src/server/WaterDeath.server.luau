-- Anyone who falls into the ocean gets impaled by "piercied" bursting up
-- out of the water underneath them, and dies.
-- The template model lives in ServerStorage; a scaled-down copy is used each time.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")

local template = ServerStorage:WaitForChild("piercied") :: BasePart

local SEA_LEVEL = 4 -- top of the ocean water
local SPIKE_SCALE = 0.2 -- the model is huge; this makes it ~66 studs tall
local RISE_TIME = 0.25
local STAY_TIME = 2.5

local function pierce(character: Model, humanoid: Humanoid, hrp: BasePart)
	character:SetAttribute("Pierced", true)

	local spike = template:Clone()
	spike.Size = template.Size * SPIKE_SCALE
	spike.Anchored = true
	spike.CanCollide = false
	spike.CanQuery = false
	spike.CanTouch = false

	-- start completely under the water right below the player...
	local x, z = hrp.Position.X, hrp.Position.Z
	local hidden = CFrame.new(x, SEA_LEVEL - spike.Size.Y / 2 - 6, z)
	-- ...and burst up until the tip is well above them
	local raised = CFrame.new(x, hrp.Position.Y + 12 - spike.Size.Y / 2, z)
	spike.CFrame = hidden
	spike.Parent = workspace

	hrp.Anchored = true -- hold them in place to be skewered
	local rise = TweenService:Create(spike, TweenInfo.new(RISE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = raised })
	rise:Play()
	rise.Completed:Wait()
	humanoid.Health = 0

	task.delay(STAY_TIME, function()
		local sink = TweenService:Create(spike, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = hidden })
		sink:Play()
		sink.Completed:Wait()
		spike:Destroy()
	end)
end

while true do
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and hrp and humanoid.Health > 0 and not character:GetAttribute("Pierced") then
			local inWater = hrp.Position.Y < SEA_LEVEL + 2
				or humanoid:GetState() == Enum.HumanoidStateType.Swimming
			if inWater then
				task.spawn(pierce, character, humanoid, hrp)
			end
		end
	end
	task.wait(0.1)
end
