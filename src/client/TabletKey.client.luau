-- Press M to take out / put away the Deepwoken Tablet.
-- The normal Roblox item bar is hidden, so M is the only way to equip it.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")

local TOGGLE_KEY = Enum.KeyCode.M
local TOOL_NAME = "Deepwoken Tablet"

local player = Players.LocalPlayer

-- hide the default item bar (number-key hotbar)
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

local function toggleTablet()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local held = character:FindFirstChild(TOOL_NAME)
	if held then
		humanoid:UnequipTools()
		return
	end
	local tool = player.Backpack:FindFirstChild(TOOL_NAME)
	if tool then
		humanoid:EquipTool(tool)
	end
end

-- ContextActionService ignores keys typed into chat automatically.
ContextActionService:BindAction("ToggleDeepwokenTablet", function(_, state)
	if state == Enum.UserInputState.Begin then
		toggleTablet()
	end
	return Enum.ContextActionResult.Sink
end, false, TOGGLE_KEY)

-- Lets other scripts (and tests) toggle it too.
local toggleEvent = Instance.new("BindableEvent")
toggleEvent.Name = "Toggle"
toggleEvent.Event:Connect(toggleTablet)
toggleEvent.Parent = script
