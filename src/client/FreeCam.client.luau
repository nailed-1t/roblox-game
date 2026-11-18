-- Free-fly camera. Press the key (default "L") to detach the camera from the
-- character and fly it around; the avatar stays where it is and doesn't move.
-- Press the key again to go back to the normal first-person view.
--
-- Controls while flying:
--   Mouse        look around
--   W A S D      move
--   E / Space    up
--   Q / Ctrl     down
--   Shift        faster

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local TOGGLE_KEY = Enum.KeyCode.L
local SPEED = 60 -- studs per second
local FAST_MULTIPLIER = 3
local LOOK_SENSITIVITY = 0.25 -- degrees per pixel of mouse movement

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Roblox's default movement controls, so they can be paused while flying.
-- (Movement keys are also blocked separately below, so flying still works
-- even if a place doesn't use the default controls.)
local controls = nil
task.spawn(function()
	local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 15)
	if module then
		local ok, playerModule = pcall(require, module)
		if ok and playerModule then
			controls = playerModule:GetControls()
		end
	end
end)

local flying = false
local yaw, pitch = 0, 0
local position = Vector3.zero
local renderConnection: RBXScriptConnection? = nil
local savedMouseBehavior = Enum.MouseBehavior.Default

local MOVE_KEYS = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.E] = Vector3.new(0, 1, 0),
	[Enum.KeyCode.Space] = Vector3.new(0, 1, 0),
	[Enum.KeyCode.Q] = Vector3.new(0, -1, 0),
	[Enum.KeyCode.LeftControl] = Vector3.new(0, -1, 0),
}

-- While flying, swallow movement keys so they never reach the character.
local function sinkInput()
	return Enum.ContextActionResult.Sink
end
local sunkKeys = {}
for key in pairs(MOVE_KEYS) do
	table.insert(sunkKeys, key)
end

local function startFlying()
	flying = true
	local look = camera.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.asin(math.clamp(look.Y, -1, 1))
	position = camera.CFrame.Position

	if controls then
		controls:Disable()
	end
	ContextActionService:BindActionAtPriority("FreeCamSink", sinkInput, false, Enum.ContextActionPriority.High.Value, table.unpack(sunkKeys))

	camera.CameraType = Enum.CameraType.Scriptable
	savedMouseBehavior = UserInputService.MouseBehavior

	renderConnection = RunService.RenderStepped:Connect(function(dt)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local delta = UserInputService:GetMouseDelta()
		yaw -= math.rad(delta.X * LOOK_SENSITIVITY)
		pitch = math.clamp(pitch - math.rad(delta.Y * LOOK_SENSITIVITY), math.rad(-89), math.rad(89))

		local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local move = Vector3.zero
		for key, dir in pairs(MOVE_KEYS) do
			if UserInputService:IsKeyDown(key) then
				move += dir
			end
		end
		if move.Magnitude > 0 then
			local speed = SPEED
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
				speed *= FAST_MULTIPLIER
			end
			local horizontal = rotation:VectorToWorldSpace(Vector3.new(move.X, 0, move.Z))
			local worldMove = horizontal + Vector3.new(0, move.Y, 0)
			position += worldMove.Unit * speed * dt
		end
		camera.CFrame = CFrame.new(position) * rotation
	end)
end

local function stopFlying()
	flying = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	ContextActionService:UnbindAction("FreeCamSink")
	if controls then
		controls:Enable()
	end
	UserInputService.MouseBehavior = savedMouseBehavior
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= TOGGLE_KEY then
		return -- ignore the key while typing in chat
	end
	if flying then
		stopFlying()
	else
		startFlying()
	end
end)

-- Respawning while flying puts the camera back on the new character.
player.CharacterAdded:Connect(function()
	if flying then
		stopFlying()
	end
end)
