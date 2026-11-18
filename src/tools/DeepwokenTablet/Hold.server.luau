-- Holds the Deepwoken Tablet upright in front of the player's chest, picture
-- facing them, at the same spot every time (instead of following the arm,
-- whose animation isn't always in the same place).

local tool = script.Parent
local handle = tool:WaitForChild("Handle") :: BasePart

-- where the tablet sits, relative to the body: right/left, up/down, forward (-)
local HOLD_OFFSET = Vector3.new(0.5, 0.35, -2.3)
-- the picture is on the handle's -X side, so point +X forward and Y up
local HOLD_CFRAME = CFrame.fromMatrix(HOLD_OFFSET, Vector3.new(0, 0, -1), Vector3.new(0, 1, 0))

local holdWeld: Weld? = nil

tool.Equipped:Connect(function()
	local character = tool.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	-- remove the normal hand grip so it doesn't fight our weld
	task.defer(function()
		local arm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
		local grip = arm and arm:FindFirstChild("RightGrip")
		if grip then
			grip:Destroy()
		end
	end)
	if holdWeld then
		holdWeld:Destroy()
	end
	local weld = Instance.new("Weld")
	weld.Name = "TabletHold"
	weld.Part0 = root
	weld.Part1 = handle
	weld.C0 = HOLD_CFRAME
	weld.C1 = CFrame.identity
	weld.Parent = handle
	holdWeld = weld
end)

tool.Unequipped:Connect(function()
	if holdWeld then
		holdWeld:Destroy()
		holdWeld = nil
	end
end)
